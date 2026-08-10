#pragma once

// query.h — ABS-5: composable graph-query operators. A FIXED, CLOSED set of node-set operators over the
// already-built symbol graph — deliberately NOT a Datalog/Prolog engine: no user-defined rules, no
// recursion beyond a BOUNDED hop depth, no unification, no fixpoint. A `--query=EXPR` is a small functional
// expression that evaluates to a deterministic, sorted, de-duplicated NodeId set; main.cpp serializes it
// exactly like --callers. The point is to answer questions the fixed verbs did not pre-anticipate by
// COMPOSING a handful of primitives, while staying as predictable + bounded as every other ripwire verb.
//
// Grammar (recursive-descent; whitespace-insensitive):
//   EXPR    := SOURCE | FILTER | CLOSURE | JOIN
//   SOURCE  := name( "STR" )            symbols whose name == STR (unions same-name defs, like --callers)
//            | all                       every symbol  (parens optional: `all` or `all()`)
//   FILTER  := kind( EXPR , KIND )       keep nodes of KIND  (fn|method|cls|struct|iface|var|sec|macro)
//            | cx(   EXPR , INT )         keep nodes with cyclomatic complexity >= INT
//            | fanin(EXPR , INT )         keep nodes with in-degree (caller count) >= INT
//            | file( EXPR , "RE" )        keep nodes whose file PATH matches the ECMAScript regex RE
//   CLOSURE := callers( EXPR [, INT=1] )  nodes that transitively (<= INT hops) CALL any node in EXPR
//            | callees( EXPR [, INT=1] )  nodes transitively (<= INT hops) CALLED BY any node in EXPR
//   JOIN    := and( EXPR , EXPR )         set intersection
//            | or(  EXPR , EXPR )         set union
//            | not( EXPR , EXPR )         set difference  (left minus right)
//
//   e.g.  and( callers( name("parseArchRules"), 2 ), kind( all, fn ) )
//         — the functions that transitively (<= 2 hops) call parseArchRules.
//
// Determinism: every operator returns a SORTED, UNIQUE NodeId vector; the closure BFS visits in
// ascending-id order. Robustness: a malformed file() regex or any parse error sets ok=false and yields the
// empty set (the CLI then reports err and exits 1) — the evaluator never throws past this seam, and the
// only recursion into the graph is the hop-bounded closure, so it can neither hang nor blow the stack on a
// cyclic call graph (a `seen` set caps every node at one visit).

#include "model.h"
#include "graph.h"
#include "infra/Diagnostics.h"

#include <algorithm>
#include <cctype>
#include <regex>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{
namespace query
{

// kind keyword → SymKind; false for an unknown word.
inline bool kindOfWord( std::string_view w, SymKind& out ) noexcept
{
    if( w == "fn"     ) { out = SymKind::Function;  return true; }
    if( w == "method" ) { out = SymKind::Method;    return true; }
    if( w == "cls"    ) { out = SymKind::Class;     return true; }
    if( w == "struct" ) { out = SymKind::Struct;    return true; }
    if( w == "iface"  ) { out = SymKind::Interface; return true; }
    if( w == "var"    ) { out = SymKind::Var;       return true; }
    if( w == "sec"    ) { out = SymKind::Section;   return true; }
    if( w == "macro"  ) { out = SymKind::Macro;     return true; }   // macro-edges round: t="macro" is queryable like every other kind
    return false;
}

// One-pass recursive-descent parse-and-evaluate. The operator set is small and each node-set is
// materialized eagerly — the graphs ripwire handles fit comfortably in memory.
struct Eval
{
    const IngestResult& ing;
    const Graph&        g;
    std::string_view    src;
    std::size_t         pos = 0;
    bool                ok  = true;
    std::string         err;

    // §P0.5b — every name() literal that resolved to ZERO symbols, in evaluation order. A typo is a user
    // error, not a measurement: eleven sibling symbol-taking verbs refuse an unknown name with a
    // did-you-mean while --graph-query returned a silent count="0", and --graph-query is where a typo is
    // MOST likely because the name is buried inside an expression. Recorded here and refused at the CLI
    // seam, which owns exit codes and the shared suggester. A name that DOES resolve while the COMPOSED
    // query legitimately selects nothing still returns count="0" — that one is a measurement.
    std::vector<std::string> unresolvedNames;

    Eval( const IngestResult& ingest, const Graph& graph, std::string_view expr )
        : ing( ingest ), g( graph ), src( expr ) {}

    // ── scanner ───────────────────────────────────────────────────────────────────────────────────────
    void skipWs()
    {
        while( pos < src.size() && std::isspace( static_cast<unsigned char>( src[pos] ) ) )
        {
            ++pos;
        }
    }
    char peek()           { skipWs(); return pos < src.size() ? src[pos] : '\0'; }
    bool accept( char c ) { skipWs(); if( pos < src.size() && src[pos] == c ) { ++pos; return true; } return false; }
    void expect( char c )
    {
        if( !accept( c ) )
        {
            fail( std::string( "expected '" ) + c + "'" );
        }
    }

    // A3-F16b: every parse error gets ONE grammar reminder + a worked example appended, not just the
    // bare "expected '('" — `if( ok )` makes this a latch (first failure wins), so the reminder is
    // appended exactly once per query even though fail() may be reached again as the recursive-descent
    // unwinds after the first error.
    void fail( std::string m )
    {
        if( !ok )
        {
            return;
        }
        ok = false;
        err = std::move( m );
        err += "\n  grammar: and|or|not(...) sources name(\"X\")|all filters kind|cx|fanin|file closure "
               "callers|callees(SET[,depth])\n"
               "  e.g. and(callers(name(\"foo\"),2),kind(all,fn))";
    }

    std::string ident()
    {
        skipWs();
        const std::size_t start = pos;
        while( pos < src.size() && ( std::isalnum( static_cast<unsigned char>( src[pos] ) ) || src[pos] == '_' ) )
        {
            ++pos;
        }
        return std::string( src.substr( start, pos - start ) );
    }

    std::string quoted()
    {
        skipWs();
        if( peek() != '"' ) { fail( "expected a \"quoted\" string" ); return {}; }
        ++pos;
        const std::size_t start = pos;
        while( pos < src.size() && src[pos] != '"' )
        {
            ++pos;
        }
        std::string out( src.substr( start, pos - start ) );
        if( pos < src.size() ) { ++pos; }
        else
        {
            fail( "unterminated string" );
        }
        return out;
    }

    long integer()
    {
        skipWs();
        const std::size_t start = pos;
        while( pos < src.size() && std::isdigit( static_cast<unsigned char>( src[pos] ) ) )
        {
            ++pos;
        }
        if( pos == start ) { fail( "expected an integer" ); return 0; }
        if( pos - start > 18 ) { fail( "integer too large" ); return 0; }   // 18 digits fits a long; more is signed-overflow UB
        long v = 0;
        for( std::size_t k = start; k < pos; ++k )
        {
            v = v * 10 + ( src[k] - '0' );
        }
        return v;
    }

    static void sortUniq( std::vector<NodeId>& v )
    {
        std::sort( v.begin(), v.end() );
        v.erase( std::unique( v.begin(), v.end() ), v.end() );
    }

    // ── sources ───────────────────────────────────────────────────────────────────────────────────────
    std::vector<NodeId> sourceAll()
    {
        std::vector<NodeId> r( ing.symbols.size() );
        for( std::size_t i = 0; i < r.size(); ++i )
        {
            r[i] = static_cast<NodeId>( i );
        }
        return r;   // 0..N-1 is already sorted-unique
    }

    std::vector<NodeId> sourceName( const std::string& nm )
    {
        std::vector<NodeId> r = resolveAllByName( ing, nm );
        sortUniq( r );
        if( r.empty() )
        {
            unresolvedNames.push_back( nm ); // §P0.5b — a typo, not a measurement; refused at the CLI seam
        }
        return r;
    }

    // ── filters (node predicates) ───────────────────────────────────────────────────────────────────────
    std::vector<NodeId> filterKind( std::vector<NodeId> set, SymKind k )
    {
        set.erase( std::remove_if( set.begin(), set.end(), [ & ]( NodeId id ) { return ing.symbols[id].kind != k; } ), set.end() );
        return set;
    }

    std::vector<NodeId> filterCx( std::vector<NodeId> set, long n )
    {
        const std::uint32_t thresh = n < 0 ? 0 : static_cast<std::uint32_t>( n );
        set.erase( std::remove_if( set.begin(), set.end(), [ & ]( NodeId id ) { return ing.symbols[id].cx < thresh; } ), set.end() );
        return set;
    }

    std::vector<NodeId> filterFanin( std::vector<NodeId> set, long n )
    {
        const std::uint32_t thresh = n < 0 ? 0 : static_cast<std::uint32_t>( n );
        const auto*         ro     = g.inEdges.rowOffsets();
        set.erase( std::remove_if( set.begin(), set.end(), [ & ]( NodeId id ) { return ( ro[id + 1] - ro[id] ) < thresh; } ), set.end() );
        return set;
    }

    std::vector<NodeId> filterFile( std::vector<NodeId> set, const std::string& re )
    {
        std::regex rx;
        try { rx = std::regex( re, std::regex::ECMAScript ); }
        catch( const std::regex_error& )
        {
            DEGRADED_PATH_ALERT( "query: malformed file() regex — empty result" );
            fail( "malformed file() regex" );
            return {};
        }
        // Paths are short (<~300 B) so std::regex_search here cannot meaningfully back-track-blow-up.
        set.erase( std::remove_if( set.begin(), set.end(),
                   [ & ]( NodeId id ) { return !std::regex_search( ing.files[ ing.symbols[id].fileId ], rx ); } ), set.end() );
        return set;
    }

    // ── bounded transitive closure ──────────────────────────────────────────────────────────────────────
    // <= depth hops over in-edges (callers) or out-edges (callees). Seeds are EXCLUDED from the result
    // (we report the reached callers/callees, not the seeds). `seen` caps each node at one visit ⇒ a cyclic
    // call graph terminates.
    std::vector<NodeId> closure( const std::vector<NodeId>& seeds, bool wantCallers, int depth )
    {
        if( depth < 1 )
        {
            depth = 1;
        }
        const std::size_t   N = ing.symbols.size();
        std::vector<char>   seen( N, 0 );
        std::vector<NodeId> frontier;
        for( NodeId s : seeds )
        {
            if( s < N && !seen[s] )
            {
                seen[s] = 1;
                frontier.push_back( s );
            } // seeds marked → excluded
        }

        const auto* inRo = g.inEdges.rowOffsets();
        const auto* inCi = g.inEdges.colIndices();

        std::vector<NodeId> out;
        for( int hop = 0; hop < depth && !frontier.empty(); ++hop )
        {
            std::vector<NodeId> next;
            for( NodeId u : frontier )
            {
                if( wantCallers )
                {
                    for( std::uint32_t k = inRo[u]; k < inRo[u + 1]; ++k )
                    {
                        const NodeId c = inCi[k];
                        if( c < N && !seen[c] ) { seen[c] = 1; out.push_back( c ); next.push_back( c ); }
                    }
                }
                else
                {
                    for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k )
                    {
                        const NodeId c = g.outTargets[k];
                        if( c < N && !seen[c] ) { seen[c] = 1; out.push_back( c ); next.push_back( c ); }
                    }
                }
            }
            frontier = std::move( next );
        }
        sortUniq( out );
        return out;
    }

    // ── 2-relation joins ──────────────────────────────────────────────────────────────────────────────
    std::vector<NodeId> join( std::string_view op, std::vector<NodeId> a, std::vector<NodeId> b )
    {
        sortUniq( a ); sortUniq( b );
        std::vector<NodeId> r;
        if( op == "and" )
        {
            std::set_intersection( a.begin(), a.end(), b.begin(), b.end(), std::back_inserter( r ) );
        }
        else if( op == "or" )
        {
            std::set_union( a.begin(), a.end(), b.begin(), b.end(), std::back_inserter( r ) );
        }
        else
        {
            std::set_difference( a.begin(), a.end(), b.begin(), b.end(), std::back_inserter( r ) ); // "not"
        }
        return r;
    }

    // ── the one recursive entry: parse + evaluate an expression ──────────────────────────────────────────
    std::vector<NodeId> expr()
    {
        if( !ok )
        {
            return {};
        }
        const std::string op = ident();
        if( op.empty() ) { fail( "expected an operator name" ); return {}; }

        if( op == "all" && peek() != '(' )
        {
            return sourceAll(); // `all` may appear bare (no parens)
        }

        expect( '(' );
        if( !ok )
        {
            return {};
        }

        std::vector<NodeId> result;
        if( op == "all" )
        {
            result = sourceAll();
        }
        else if( op == "name" )
        {
            result = sourceName( quoted() );
        }
        else if( op == "kind" || op == "cx" || op == "fanin" || op == "file" || op == "callers" || op == "callees" )
        {
            std::vector<NodeId> set = expr();                         // first arg is always a SET
            if( op == "callers" || op == "callees" )
            {
                int depth = 1;
                if( accept( ',' ) )
                {
                    depth = static_cast<int>( integer() );
                }
                result = closure( set, op == "callers", depth );
            }
            else
            {
                expect( ',' );
                if( op == "kind" )
                {
                    const std::string kw = ident();
                    SymKind           k  = SymKind::Other;
                    if( !kindOfWord( kw, k ) )
                    {
                        fail( "unknown kind '" + kw + "' (use fn|method|cls|struct|iface|var|sec|macro)" );
                    }
                    result = filterKind( std::move( set ), k );
                }
                else if( op == "cx" )
                {
                    result = filterCx( std::move( set ), integer() );
                }
                else if( op == "fanin" )
                {
                    result = filterFanin( std::move( set ), integer() );
                }
                else
                {
                    result = filterFile( std::move( set ), quoted() ); // "file"
                }
            }
        }
        else if( op == "and" || op == "or" || op == "not" )
        {
            std::vector<NodeId> a = expr();
            expect( ',' );
            std::vector<NodeId> b = expr();
            result = join( op, std::move( a ), std::move( b ) );
        }
        else
        {
            fail( "unknown operator '" + op + "'" );
        }

        expect( ')' );
        return ok ? result : std::vector<NodeId>{};
    }

    // top-level: evaluate the whole expression; require all input consumed.
    std::vector<NodeId> run()
    {
        std::vector<NodeId> r = expr();
        skipWs();
        if( ok && pos != src.size() )
        {
            fail( "trailing characters after the expression" );
        }
        return ok ? r : std::vector<NodeId>{};
    }
};

}   // namespace query
}   // namespace rw

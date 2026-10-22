#pragma once
// tspredicates.h — ONE walk over a tree-sitter pattern's predicate steps, and the STRING predicates decided on it.
//
// WHY THIS EXISTS. `ts_query` parses `(#eq? @a "x")` and friends into steps but never applies them; every caller
// must. Before #355 there were two spellings of the step-group walk (passesPredicates and its regex precompiler
// buildPredicateRegexTable, src/ingest_astquery.h — "the two must agree about which steps they consume") and the
// tags pass had NONE: its predicates were silently ignored, so a keyword-headed definition (Elixir `def`, a Lisp
// `defn`) had to keep its keyword list in C++. This header is the walk all three readers share, and the string
// predicates the tags pass now evaluates.
//
// WHAT THE TAGS PASS RUNS, AND WHAT IT DOES NOT. Only the string predicates below: #eq?, #not-eq?, #any-of?,
// #not-any-of?. Never #match? / #not-match? — a regex per tags match is the cost src/ingest_astquery.h's header
// measured (13.52% of busy CPU on --lint), and the tags pass runs over every file of every crawl. An operator this
// header does not decide is StringPredicate::NotString; the tags pass then filters nothing for it, exactly as before,
// and test/tagspredicatecheck.sh arm A refuses any tags.scm that uses one.
//
// NO ALLOCATION ON THE PER-MATCH PATH. The group is a view into the query's own step array, the operator and string
// arguments are views into the query's string table, and a capture's text is a view into the file's bytes.

#include <tree_sitter/api.h>

#include <cstdint>
#include <span>
#include <string_view>
#include <vector>

namespace rw
{

// The query's string `id` as a view into the query's own table; empty when tree-sitter has no such string.
// TWO statements, deliberately: the length `len` and the call that WRITES it must not be two arguments of one call,
// whose evaluation order is unspecified (gcc on x86-64 reads `len` first, while it is still 0 — the bug
// passesPredicates' sequencing note in src/ingest_astquery.h records, measured 2026-08-02). Do not re-inline.
inline std::string_view queryString( const TSQuery* q, std::uint32_t id ) noexcept
{
    std::uint32_t len  = 0;
    const char*   text = ts_query_string_value_for_id( q, id, &len );
    return text != nullptr ? std::string_view( text, len ) : std::string_view();
}

// The source text of capture `capIndex` (its first node) in match `m`, as a view into `src`; false when the match
// has no such capture or the node's span falls outside `src`.
inline bool captureView( const TSQueryMatch& m, std::uint32_t capIndex, std::string_view src, std::string_view& out ) noexcept
{
    for( std::uint16_t i = 0; i < m.capture_count; ++i )
    {
        if( m.captures[i].index == capIndex )
        {
            const TSNode        n = m.captures[i].node;
            const std::uint32_t a = ts_node_start_byte( n ), b = ts_node_end_byte( n );
            if( a <= b && b <= src.size() )
            {
                out = src.substr( a, b - a );
                return true;
            }
            return false;
        }
    }
    return false;
}

// Call fn( group ) for each predicate of pattern `pattern`, in order. `group` is the predicate's steps without its
// trailing Done step: group[0] the operator name, then its arguments. fn returns false to stop the walk early.
template <class Fn> inline void forEachPredicate( const TSQuery* q, std::uint32_t pattern, Fn&& fn )
{
    std::uint32_t               count = 0;
    const TSQueryPredicateStep* steps = ts_query_predicates_for_pattern( q, pattern, &count );
    std::uint32_t               begin = 0;
    for( std::uint32_t i = 0; i < count; ++i )
    {
        if( steps[i].type != TSQueryPredicateStepTypeDone )
        {
            continue;
        }
        if( !fn( std::span<const TSQueryPredicateStep>( steps + begin, i - begin ) ) )
        {
            return;
        }
        begin = i + 1;
    }
}

// The operator of a predicate group whose first step is a string, or empty for a malformed or empty group.
inline std::string_view predicateOperator( const TSQuery* q, std::span<const TSQueryPredicateStep> group ) noexcept
{
    if( group.empty() || group[0].type != TSQueryPredicateStepTypeString )
    {
        return {};
    }
    return queryString( q, group[0].value_id );
}

enum class StringPredicate : std::uint8_t { Pass, Fail, NotString };

// Decide ONE predicate group if it is a string predicate:
//   (#eq? A B) / (#not-eq? A B)       — A and B each a capture or a string
//   (#any-of? @c "s" …) / (#not-any-of? @c "s" …) — the capture's text against a list of strings
// NotString: any other operator (#match? included), or a group this cannot read — an absent capture, a short group, a
// non-string list entry. The caller filters nothing for NotString, which is what an unevaluated predicate always did.
inline StringPredicate evalStringPredicate( const TSQuery* q, std::span<const TSQueryPredicateStep> group, const TSQueryMatch& m,
                                            std::string_view src ) noexcept
{
    const std::string_view op    = predicateOperator( q, group );
    const bool             eq    = op == "eq?" || op == "not-eq?";
    const bool             anyOf = op == "any-of?" || op == "not-any-of?";
    if( ( !eq && !anyOf ) || group.size() < 3 )
    {
        return StringPredicate::NotString;
    }
    const auto argText = [ & ]( const TSQueryPredicateStep& s, std::string_view& out ) -> bool
    {
        if( s.type == TSQueryPredicateStepTypeCapture )
        {
            return captureView( m, s.value_id, src, out );
        }
        if( s.type == TSQueryPredicateStepTypeString )
        {
            out = queryString( q, s.value_id );
            return true;
        }
        return false;
    };
    std::string_view lhs;
    if( !argText( group[1], lhs ) )
    {
        return StringPredicate::NotString;
    }
    const bool negated = op.starts_with( "not-" );
    if( eq )
    {
        std::string_view rhs;
        if( !argText( group[2], rhs ) )
        {
            return StringPredicate::NotString;
        }
        return ( ( lhs == rhs ) != negated ) ? StringPredicate::Pass : StringPredicate::Fail;
    }
    bool listed = false;
    for( std::size_t i = 2; i < group.size(); ++i )
    {
        if( group[i].type != TSQueryPredicateStepTypeString )
        {
            return StringPredicate::NotString;
        }
        listed = listed || queryString( q, group[i].value_id ) == lhs;
    }
    return ( listed != negated ) ? StringPredicate::Pass : StringPredicate::Fail;
}

// True when no string predicate of the match's pattern fails. The tags pass's whole predicate surface: operators this
// header does not decide (#match? among them) filter nothing here, as they never did.
inline bool passesStringPredicates( const TSQuery* q, const TSQueryMatch& m, std::string_view src ) noexcept
{
    bool ok = true;
    forEachPredicate( q, m.pattern_index, [ & ]( std::span<const TSQueryPredicateStep> group )
    {
        ok = evalStringPredicate( q, group, m, src ) != StringPredicate::Fail;
        return ok;
    } );
    return ok;
}

// The strings of every (#<op> @capture …) predicate in the query (op "any-of?" or "not-any-of?"), in pattern order,
// without repeats. A tags.scm that filters a definition head by a keyword list is the ONE place that list is written;
// a tree walk that must recognise the same head outside a match (an enclosing `def`, a reference inside `@spec`) reads
// it here instead of keeping a second copy in C++. The views point into the query's string table and live as long as
// the query.
inline std::vector<std::string_view> predicateStrings( const TSQuery* q, std::string_view op, std::string_view capture )
{
    std::vector<std::string_view> out;
    const std::uint32_t           patterns = ts_query_pattern_count( q );
    for( std::uint32_t p = 0; p < patterns; ++p )
    {
        forEachPredicate( q, p, [ & ]( std::span<const TSQueryPredicateStep> group )
        {
            if( predicateOperator( q, group ) != op || group.size() < 3 || group[1].type != TSQueryPredicateStepTypeCapture )
            {
                return true;
            }
            std::uint32_t    len  = 0;   // two statements: see queryString
            const char*      name = ts_query_capture_name_for_id( q, group[1].value_id, &len );
            if( name == nullptr || std::string_view( name, len ) != capture )
            {
                return true;
            }
            for( std::size_t i = 2; i < group.size(); ++i )
            {
                if( group[i].type != TSQueryPredicateStepTypeString )
                {
                    continue;
                }
                const std::string_view s = queryString( q, group[i].value_id );
                bool                   seen = false;
                for( const std::string_view& prior : out )
                {
                    seen = seen || prior == s;
                }
                if( !seen )
                {
                    out.push_back( s );
                }
            }
            return true;
        } );
    }
    return out;
}

} // namespace rw

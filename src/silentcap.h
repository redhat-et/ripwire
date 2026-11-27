#pragma once

// silentcap.h — the defect-shape facet silent-cap: a loop or a walk that STOPS EARLY at a limit and leaves no trace.
//
// A CAP SITE is found by structure, not by the limit's name. A COUNTER this function grows (an identifier it increments,
// or C.size() of a container it appends to) is compared against a LIMIT (an integer literal, a constant, the size of a
// fixed array) in one of three stop shapes:
//
//   loop     for( ...; MORE && n < LIMIT; ... ) / while( MORE && n < LIMIT )   the limit ends a loop that had more to read
//   stop     if( n >= LIMIT ) break; / continue; / return;                     a bare jump, nothing else in the branch
//   keep     if( n < LIMIT ) { append }                                        with no else: what is over the limit is dropped
//
// The site is SILENT when nothing in the function can tell a caller the limit was reached:
//   - the limit is named nowhere else in the function except in another silent stop shape or a clamp (std::min, reserve);
//   - the counter is not read after the loop, and the loop's other end condition is not tested again after it;
//   - the size of the collection the loop walks is not read outside a comparison (a total= beside the rows discloses);
//   - a stop branch holds only the jump, and a returned value there is one the function also returns elsewhere.
// One hop out (the caller reads the tree): a function that calls this one and names the same limit discloses for it, and
// so does a static_assert that ties the constant to legend text.
//
// Not a site: a limit that is a parameter or a lower-case member (the caller's requested size, --limit), a loop whose
// only condition is the limit (a fixed count), a comparison whose counter this function does not grow (a shape test).
// Every one of those is a stated miss. PRECISION BEFORE RECALL, as for every scanner in defectshape.h.

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include "defectshape.h"
#include "infra/sortutil.h"   // sortUnique: the tree's name sets

namespace rw::defectshape
{

// Why a cap site is, or is not, reported. Silent is the only verdict that becomes a Site; the others are the measured
// exemptions (the driver prints every finding with its verdict, so each exemption's cost is counted).
enum class CapVerdict : std::uint8_t
{
    Silent,
    LiteralLimit,     // the limit is a bare number: on the measured trees those are runaway guards and windows, not cut answers
    LimitNamed,       // the limit is named elsewhere in the function, outside a silent stop shape
    CounterRead,      // the counter is read after the loop
    EndRetested,      // the loop's other end condition is tested again after it
    TotalRead,        // the walked collection's size is read outside a comparison
    TotalCounted,     // a count beside the site grows whether or not the limit is reached (++total; if( n < k ) keep), or a DISCLOSE stands there
    BranchRecords,    // the stop branch holds more than the jump
    DistinctReturn,   // the stop branch returns a value the function returns nowhere else
    HasElse,          // a keep site with an else branch (or whose branch jumps away, so what follows is its else)
    Probe,            // a loop that leaves on a find (return / break in its body, a found flag beside the limit): a bounded search
    WorkBound,        // a loop that appends nothing and calls nothing (it only sets scalars), or whose list grows again after it
    CallerCounts,     // a function that calls this one counts beside the call (++n; note( rows, x )): the total is the caller's
    TreeNames,        // another function of the tree names the limit outside a silent stop (the caller's capped=, the renderer's shown=)
    LegendTied,       // a static_assert ties the constant to legend text
};
inline constexpr std::array<std::string_view, 15> kCapVerdictNames = { "silent",        "literal-limit",  "limit-named",     "counter-read", "end-retested",
                                                                       "total-read",    "total-counted",  "branch-records",  "distinct-return", "has-else",
                                                                       "probe",         "work-bound",     "caller-counts",   "tree-names",   "legend-tied" };

enum class CapShape : std::uint8_t { Loop, Stop, Keep, Cut };
inline constexpr std::array<std::string_view, 4> kCapShapeNames = { "loop", "stop", "keep", "cut" };

enum class CapLimit : std::uint8_t { None, Literal, Named, FixedSize, Requested };
inline constexpr std::array<std::string_view, 5> kCapLimitNames = { "none", "literal", "named", "fixed-size", "requested" };

struct CapFinding
{
    CapVerdict       verdict   = CapVerdict::Silent;
    CapShape         shape     = CapShape::Loop;
    CapLimit         limitKind = CapLimit::None;
    std::uint32_t    startByte = 0;
    std::string      text;       // the site's identity: the loop head or the if condition, tokens joined
    std::string      limit;      // the limit as written (a constant's last name segment)
    std::string      function;   // the enclosing function's name (its own naming of the limit was judged already); empty when the head names none
};

namespace detail::cap
{

// A function-like scope: the outermost brace block that is not a namespace, class, struct, union or enum body.
struct Scope
{
    std::size_t head  = 0;   // first token of the head (after the previous `;` or brace)
    std::size_t open  = 0;   // its `{`
    std::size_t close = 0;   // its `}`
};

inline bool isContainerHead( std::string_view src, const std::vector<Tok>& toks, std::size_t head, std::size_t open ) noexcept
{
    static constexpr std::array<std::string_view, 6> kContainer = { "namespace", "struct", "class", "union", "enum", "extern" };
    bool container = false;
    for( std::size_t k = head; k < open; ++k )
    {
        const std::string_view w = tokText( src, toks[k] );
        if( toks[k].kind == TokKind::Ident && std::find( kContainer.begin(), kContainer.end(), w ) != kContainer.end() )
        {
            container = true;
        }
        else if( w == "(" || w == "=" )
        {
            container = false;   // `struct X f( ) {` is a function; `auto x = struct { ... }` is an initializer
        }
    }
    return container;
}

inline std::vector<Scope> functionScopes( std::string_view src, const std::vector<Tok>& toks )
{
    struct Open
    {
        std::size_t at;
        std::size_t head;
        bool        container;
    };
    std::vector<Scope> out;
    std::vector<Open>  stack;
    std::size_t        head = 0;
    for( std::size_t k = 0; k < toks.size(); ++k )
    {
        if( toks[k].kind != TokKind::Punct || toks[k].end - toks[k].begin != 1 )
        {
            continue;
        }
        const char c = src[ toks[k].begin ];
        if( c == '{' )
        {
            const bool inContainers = std::all_of( stack.begin(), stack.end(), []( const Open& o ) { return o.container; } );
            stack.push_back( { k, head, inContainers && isContainerHead( src, toks, head, k ) } );
            head = k + 1;
        }
        else if( c == '}' && !stack.empty() )
        {
            const Open o = stack.back();
            stack.pop_back();
            if( !o.container && std::all_of( stack.begin(), stack.end(), []( const Open& p ) { return p.container; } ) )
            {
                out.push_back( { o.head, o.at, k } );
            }
            head = k + 1;
        }
        else if( c == ';' && std::all_of( stack.begin(), stack.end(), []( const Open& o ) { return o.container; } ) )
        {
            head = k + 1;
        }
    }
    return out;
}

// The name a function head declares: the identifier before its first parenthesis.
inline std::string_view scopeName( std::string_view src, const std::vector<Tok>& toks, const Scope& sc ) noexcept
{
    for( std::size_t k = sc.head + 1; k < sc.open; ++k )
    {
        if( tokIs( src, toks[k], "(" ) )
        {
            return toks[k - 1].kind == TokKind::Ident ? tokText( src, toks[k - 1] ) : std::string_view{};
        }
    }
    return {};
}

inline bool isConstName( std::string_view w ) noexcept
{
    if( w.size() >= 2 && w[0] == 'k' && w[1] >= 'A' && w[1] <= 'Z' )
    {
        return true;
    }
    return w.size() >= 3 && wordCaseOf( w ) == WordCase::Upper;
}

// One comparison of a counter against a limit, read off a condition.
struct Compare
{
    std::size_t opAt       = 0;
    std::size_t first      = 0;       // the comparison's first and last token (both sides)
    std::size_t last       = 0;
    std::size_t limitAt    = 0;       // the limit's name or number token
    CapLimit    limitKind  = CapLimit::None;
    std::string limit;
    std::string alias;                // the parameter a constant limit arrives through, when the head defaults it
    std::string counter;              // the grown identifier, or the collection whose size() is compared
    bool        counterIsSize = false;
    bool        below      = false;   // counter < limit (the loop goes on) as against counter >= limit (the stop)
};

// The scan of one function scope.
class FnScan
{
public:
    FnScan( std::string_view src, const std::vector<Tok>& toks, const Scope& sc ) : src_( src ), toks_( toks ), sc_( sc ) { markAngles(); }

    std::vector<CapFinding> findings()
    {
        std::vector<CapFinding> out;
        for( std::size_t k = sc_.open + 1; k + 1 < sc_.close; ++k )
        {
            if( toks_[k].kind != TokKind::Ident || !is( k + 1, "(" ) )
            {
                continue;
            }
            const std::size_t close = matchClose( src_, toks_, k + 1 );
            if( close >= sc_.close )
            {
                continue;
            }
            if( is( k, "substr" ) )
            {
                cutSite( k, close );
            }
            else if( is( k, "for" ) )
            {
                loopSite( k, close, /*isFor=*/true, out );
            }
            else if( is( k, "while" ) && !( k > 0 && is( k - 1, "}" ) && isDoBody( k - 1 ) ) )
            {
                loopSite( k, close, /*isFor=*/false, out );
            }
            else if( is( k, "if" ) )
            {
                ifSite( k, close, out );
            }
        }
        judge( out );
        return out;
    }

private:
    bool             is( std::size_t k, std::string_view s ) const noexcept { return k < toks_.size() && tokIs( src_, toks_[k], s ); }
    std::string_view text( std::size_t k ) const noexcept { return tokText( src_, toks_[k] ); }
    bool             isIdent( std::size_t k ) const noexcept { return k < toks_.size() && toks_[k].kind == TokKind::Ident; }

    // `<` ... `>` that brackets template arguments, not a comparison: static_cast<int>( x ), std::min<std::size_t>( a, b ).
    void markAngles()
    {
        angle_.assign( sc_.close + 1, 0 );
        for( std::size_t k = sc_.open; k < sc_.close; ++k )
        {
            if( !is( k, "<" ) || k == 0 || !isIdent( k - 1 ) )
            {
                continue;
            }
            int         depth = 0;
            std::size_t j     = k;
            for( ; j < sc_.close; ++j )
            {
                const std::string_view w = text( j );
                if( w == "<" )
                {
                    ++depth;
                }
                else if( w == ">" && --depth == 0 )
                {
                    break;
                }
                else if( w == ">>" && ( depth -= 2 ) <= 0 )
                {
                    break;
                }
                else if( j > k && toks_[j].kind == TokKind::Punct && w != "::" && w != "," && w != "*" && w != "&" && w != "<" && w != ">" && w != "[" && w != "]" )
                {
                    j = sc_.close;
                    break;
                }
            }
            if( j < sc_.close && j + 1 < sc_.close && ( is( j + 1, "(" ) || is( j + 1, "::" ) || is( j + 1, "{" ) || is( j + 1, ">" ) || is( j + 1, ")" ) || is( j + 1, "," ) ) )
            {
                for( std::size_t m = k; m <= j; ++m )
                {
                    angle_[m] = 1;
                }
            }
        }
    }

    bool isDoBody( std::size_t closeBrace ) const noexcept
    {
        int depth = 0;
        for( std::size_t j = closeBrace + 1; j-- > sc_.open; )
        {
            depth += is( j, "}" ) ? 1 : is( j, "{" ) ? -1 : 0;
            if( depth == 0 )
            {
                return j > 0 && is( j - 1, "do" );
            }
        }
        return false;
    }

    // The last token of the statement that starts at `k`: a block's `}`, or the `;` of a simple statement (an if / for /
    // while statement ends where its branch does, an else included).
    std::size_t stmtEnd( std::size_t k ) const noexcept
    {
        if( k >= sc_.close )
        {
            return sc_.close;
        }
        if( is( k, "{" ) )
        {
            return std::min( matchClose( src_, toks_, k ), sc_.close );
        }
        if( ( is( k, "if" ) || is( k, "for" ) || is( k, "while" ) || is( k, "switch" ) ) && is( k + 1, "(" ) )
        {
            const std::size_t close = matchClose( src_, toks_, k + 1 );
            std::size_t       end   = stmtEnd( close + 1 );
            if( is( k, "if" ) && is( end + 1, "else" ) )
            {
                end = stmtEnd( end + 2 );
            }
            return end;
        }
        int depth = 0;
        for( std::size_t j = k; j < sc_.close; ++j )
        {
            if( toks_[j].kind != TokKind::Punct || toks_[j].end - toks_[j].begin != 1 )
            {
                continue;
            }
            const char c = src_[ toks_[j].begin ];
            depth += ( c == '(' || c == '[' || c == '{' ) ? 1 : ( c == ')' || c == ']' || c == '}' ) ? -1 : 0;
            if( depth < 0 || ( c == ';' && depth == 0 ) )
            {
                return j;
            }
        }
        return sc_.close;
    }

    // Does this function grow `name`: ++name, name++, name += ?
    bool grows( std::string_view name ) const noexcept
    {
        for( std::size_t k = sc_.open + 1; k < sc_.close; ++k )
        {
            if( !isIdent( k ) || text( k ) != name )
            {
                continue;
            }
            // ++n, n++, n += ; and `n + 1`: the next level of a recursion or of a work list (depth + 1)
            if( is( k + 1, "++" ) || is( k + 1, "+=" ) || is( k - 1, "++" ) || ( is( k + 1, "+" ) && is( k + 2, "1" ) ) )
            {
                return true;
            }
        }
        return false;
    }

    // The methods that add to a collection (an explicit list: assign, resize, erase and clear do not grow a list toward a cap).
    static bool isAppendMethod( std::string_view m ) noexcept
    {
        static constexpr std::array<std::string_view, 12> kAppends = { "push_back", "emplace_back", "insert", "append", "emplace", "push",
                                                                       "push_front", "emplace_front", "add", "raw", "try_emplace", "insert_or_assign" };
        return std::find( kAppends.begin(), kAppends.end(), m ) != kAppends.end();
    }

    // Does this function append to the collection `name`: a call of an appending method, `name +=`, or
    // `name[ i ] =`?
    bool appendsTo( std::string_view name ) const noexcept
    {
        for( std::size_t k = sc_.open + 1; k + 2 < sc_.close; ++k )
        {
            if( !isIdent( k ) || text( k ) != name )
            {
                continue;
            }
            if( is( k + 1, "+=" ) )
            {
                return true;
            }
            if( ( is( k + 1, "." ) || is( k + 1, "->" ) ) && isIdent( k + 2 ) && is( k + 3, "(" ) && isAppendMethod( text( k + 2 ) ) )
            {
                return true;
            }
            if( is( k + 1, "[" ) )
            {
                const std::size_t close = matchClose( src_, toks_, k + 1 );
                if( close < sc_.close && is( close + 1, "=" ) )
                {
                    return true;
                }
            }
        }
        return false;
    }

    // The limit a comparison side [a, b] spells: one number of at least 2, one constant name (with `ns::` and plain
    // arithmetic around it), std::size( array ) / sizeof( x ), or a lower-case cap-named identifier (the caller's k).
    void limitOf( std::size_t a, std::size_t b, Compare& c ) const
    {
        while( a < b && is( a, "(" ) && matchClose( src_, toks_, a ) == b )
        {
            ++a;
            --b;
        }
        if( a > b )
        {
            return;
        }
        if( ( is( a, "sizeof" ) && is( a + 1, "(" ) && matchClose( src_, toks_, a + 1 ) == b )
            || ( is( a, "std" ) && is( a + 1, "::" ) && is( a + 2, "size" ) && is( a + 3, "(" ) && matchClose( src_, toks_, a + 3 ) == b ) )
        {
            c.limitKind = CapLimit::FixedSize;
            c.limit     = joinTokens( src_, toks_, a, b );
            c.limitAt   = a;
            return;
        }
        std::size_t names = 0;
        std::size_t numbers = 0;
        std::size_t at = a;
        for( std::size_t k = a; k <= b; ++k )
        {
            const std::string_view w = text( k );
            if( toks_[k].kind == TokKind::Number )
            {
                ++numbers;
                at = names == 0 ? k : at;
            }
            else if( toks_[k].kind == TokKind::Ident )
            {
                if( is( k + 1, "::" ) && k + 1 <= b )
                {
                    continue;   // a namespace or class qualifier
                }
                ++names;
                at = k;
            }
            else if( w != "::" && w != "+" && w != "-" && w != "*" )
            {
                return;   // a call, a member access, a subscript: not a limit this check reads
            }
        }
        if( names == 0 && numbers == 1 && a == b )
        {
            const std::string_view d = text( a );
            std::size_t            v = 0;
            for( const char ch : d )
            {
                if( ch == '\'' )
                {
                    continue;
                }
                if( !isDigit( ch ) )
                {
                    break;
                }
                v = v < 1'000'000'000 ? v * 10 + std::size_t( ch - '0' ) : v;
            }
            if( v >= 2 && !d.starts_with( "0x" ) && !d.starts_with( "0X" ) && d.find( '.' ) == std::string_view::npos )
            {
                c.limitKind = CapLimit::Literal;
                c.limit     = std::string( d );
                c.limitAt   = a;
            }
            return;
        }
        if( names != 1 )
        {
            return;
        }
        const std::string_view name = text( at );
        if( isConstName( name ) )
        {
            c.limitKind = CapLimit::Named;
        }
        else if( a == b && isCapName( name ) )
        {
            c.limitKind = CapLimit::Requested;
            // a parameter the head defaults to a constant (`std::size_t cap = kWalkCap`) is that constant's cap
            for( std::size_t k = sc_.head; k + 2 < sc_.open; ++k )
            {
                if( text( k ) == name && is( k + 1, "=" ) && isIdent( k + 2 ) && isConstName( text( k + 2 ) ) && ( is( k + 3, "," ) || is( k + 3, ")" ) ) )
                {
                    c.limitKind = CapLimit::Named;
                    c.alias     = std::string( name );
                    c.limit     = std::string( text( k + 2 ) );
                    c.limitAt   = at;
                    return;
                }
            }
        }
        else
        {
            return;
        }
        c.limit   = std::string( name );
        c.limitAt = at;
    }

    // The counter a comparison side [a, b] reads: C.size() / C.length() of a collection this function appends to, or an
    // identifier it grows.
    void counterOf( std::size_t a, std::size_t b, Compare& c ) const
    {
        for( std::size_t k = a; k + 4 <= b + 1 && k + 4 < toks_.size(); ++k )
        {
            if( isIdent( k ) && ( is( k + 1, "." ) || is( k + 1, "->" ) ) && ( is( k + 2, "size" ) || is( k + 2, "length" ) ) && is( k + 3, "(" ) && is( k + 4, ")" ) )
            {
                if( appendsTo( text( k ) ) )
                {
                    c.counter       = std::string( text( k ) );
                    c.counterIsSize = true;
                }
                return;
            }
        }
        for( std::size_t k = a; k <= b; ++k )
        {
            if( isIdent( k ) && !is( k + 1, "(" ) && !is( k + 1, "::" ) && !is( k + 1, "." ) && !is( k + 1, "->" ) && grows( text( k ) ) )
            {
                c.counter = std::string( text( k ) );
                return;
            }
        }
    }

    // Every counter-against-limit comparison in the condition tokens [a, b].
    std::vector<Compare> comparesIn( std::size_t a, std::size_t b ) const
    {
        std::vector<Compare> out;
        for( std::size_t k = a; k <= b; ++k )
        {
            const std::string_view op = text( k );
            if( toks_[k].kind != TokKind::Punct || angle_[k] != 0 || ( op != "<" && op != "<=" && op != ">" && op != ">=" && op != "==" ) )
            {
                continue;
            }
            const auto [ l, r ] = sidesOf( k, a, b );
            if( l > k - 1 || r < k + 1 )
            {
                continue;
            }
            Compare c;
            c.opAt  = k;
            c.first = l;
            c.last  = r;
            limitOf( k + 1, r, c );
            if( c.limitKind != CapLimit::None )
            {
                counterOf( l, k - 1, c );
                c.below = op == "<" || op == "<=";
            }
            else
            {
                limitOf( l, k - 1, c );
                counterOf( k + 1, r, c );
                c.below = op == ">" || op == ">=";
            }
            if( c.limitKind != CapLimit::None && !c.counter.empty() && ( op != "==" || !( c.below = false ) ) )
            {
                out.push_back( std::move( c ) );
            }
        }
        return out;
    }

    // The operand range around the comparison operator at `op`, inside [a, b]: out to the nearest `&&`, `||`, `?`, `:`, `,`,
    // `;` or unmatched parenthesis at the operator's own depth.
    std::pair<std::size_t, std::size_t> sidesOf( std::size_t op, std::size_t a, std::size_t b ) const noexcept
    {
        const auto stops = [ & ]( std::size_t k ) { return is( k, "&&" ) || is( k, "||" ) || is( k, "?" ) || is( k, ":" ) || is( k, "," ) || is( k, ";" ) || is( k, "=" ); };
        std::size_t l     = op;
        int         depth = 0;
        while( l > a )
        {
            const std::size_t j = l - 1;
            if( is( j, ")" ) || is( j, "]" ) )
            {
                ++depth;
            }
            else if( is( j, "(" ) || is( j, "[" ) )
            {
                if( depth == 0 )
                {
                    break;
                }
                --depth;
            }
            else if( depth == 0 && stops( j ) )
            {
                break;
            }
            l = j;
        }
        while( l < op && is( l, "!" ) )
        {
            ++l;
        }
        std::size_t r = op;
        depth         = 0;
        while( r < b )
        {
            const std::size_t j = r + 1;
            if( is( j, "(" ) || is( j, "[" ) )
            {
                ++depth;
            }
            else if( is( j, ")" ) || is( j, "]" ) )
            {
                if( depth == 0 )
                {
                    break;
                }
                --depth;
            }
            else if( depth == 0 && ( stops( j ) || ( toks_[j].kind == TokKind::Punct && angle_[j] == 0 && ( is( j, "<" ) || is( j, ">" ) || is( j, "<=" ) || is( j, ">=" ) || is( j, "==" ) ) ) ) )
            {
                break;
            }
            r = j;
        }
        return { l, r };
    }

    struct Raw   // a cap site before its verdict
    {
        Compare     cmp;
        CapShape    shape   = CapShape::Loop;
        std::size_t at      = 0;   // the for / while / if keyword
        std::size_t condA   = 0;   // the condition's token range
        std::size_t condB   = 0;
        std::size_t end     = 0;   // the last token of the loop, or of the if statement
        CapVerdict  verdict = CapVerdict::Silent;
        bool        shapeSilent = true;   // its limit mention is one a silent stop makes (not a trace by itself)
        bool        returns     = false;  // a stop that leaves the function: nothing after it runs
    };

    void loopSite( std::size_t kw, std::size_t close, bool isFor, std::vector<CapFinding>& )
    {
        std::size_t a = kw + 2;
        std::size_t b = close - 1;
        if( isFor )
        {
            // for( init; cond; step ): the condition is between the two top-level semicolons (a range-for has none)
            std::vector<std::size_t> semis;
            int                      depth = 0;
            for( std::size_t k = a; k <= b; ++k )
            {
                depth += ( is( k, "(" ) || is( k, "[" ) || is( k, "{" ) ) ? 1 : ( is( k, ")" ) || is( k, "]" ) || is( k, "}" ) ) ? -1 : 0;
                if( depth == 0 && is( k, ";" ) )
                {
                    semis.push_back( k );
                }
            }
            if( semis.size() != 2 || semis[1] <= semis[0] + 1 )
            {
                return;
            }
            a = semis[0] + 1;
            b = semis[1] - 1;
        }
        if( a > b )
        {
            return;
        }
        // the loop needs another end condition beside the limit: `i < kN` alone is a fixed count
        bool conjoined = false;
        int  depth     = 0;
        for( std::size_t k = a; k <= b; ++k )
        {
            depth += ( is( k, "(" ) || is( k, "[" ) ) ? 1 : ( is( k, ")" ) || is( k, "]" ) ) ? -1 : 0;
            conjoined = conjoined || ( depth == 0 && is( k, "&&" ) );
        }
        if( !conjoined )
        {
            return;
        }
        for( Compare& c : comparesIn( a, b ) )
        {
            if( c.below )
            {
                Raw r{ std::move( c ), CapShape::Loop, kw, a, b, stmtEnd( kw ) };
                if( holdsWord( close + 1, r.end, "return" ) || holdsWord( close + 1, r.end, "break" ) )
                {
                    r.verdict     = CapVerdict::Probe;
                    r.shapeSilent = false;
                }
                else if( setsScalarsOnly( close + 1, r.end, r.cmp.counter ) )
                {
                    r.verdict = CapVerdict::WorkBound;
                }
                raws_.push_back( std::move( r ) );
            }
        }
    }

    // Does the loop body [s, e] keep nothing: no appending call, no `+=`, no call made as a statement, no store indexed by
    // the counter? Then the limit bounds work on values that exist either way (a boost given to the first k), not a list.
    bool setsScalarsOnly( std::size_t s, std::size_t e, std::string_view counter ) const noexcept
    {
        for( std::size_t k = s; k <= e && k < sc_.close; ++k )
        {
            if( is( k, "+=" ) || is( k, "<<" ) )
            {
                return false;
            }
            if( isIdent( k ) && is( k + 1, "(" ) && !is( k, "if" ) && !is( k, "for" ) && !is( k, "while" ) && !is( k, "switch" )
                && ( isAppendMethod( text( k ) ) || cppStatementStartsAt( src_, toks_, pathStart( k ) ) ) )
            {
                return false;
            }
            if( is( k, "[" ) )
            {
                const std::size_t close = matchClose( src_, toks_, k );
                if( close < sc_.close && is( close + 1, "=" ) && holdsWord( k + 1, close, counter ) )
                {
                    return false;
                }
            }
        }
        return true;
    }

    // The first token of the member path that ends at `k` (`a.b->c` at c gives a).
    std::size_t pathStart( std::size_t k ) const noexcept
    {
        while( k >= sc_.open + 3 && ( is( k - 1, "." ) || is( k - 1, "->" ) || is( k - 1, "::" ) ) && isIdent( k - 2 ) )
        {
            k -= 2;
        }
        return k;
    }

    // Is the list `name` appended to after token `after` (the loop's end): the limit bounded one source, not the list?
    bool appendedAfter( std::string_view name, std::size_t after ) const noexcept
    {
        for( std::size_t k = after + 1; k + 3 < sc_.close; ++k )
        {
            if( isIdent( k ) && text( k ) == name && ( is( k + 1, "+=" ) || ( ( is( k + 1, "." ) || is( k + 1, "->" ) ) && isIdent( k + 2 ) && is( k + 3, "(" ) && isAppendMethod( text( k + 2 ) ) ) ) )
            {
                return true;
            }
        }
        return false;
    }

    // Is the last element of the list `name` read after token `after` (`chain.back()` compared once the walk is over)?
    bool backReadAfter( std::string_view name, std::size_t after ) const noexcept
    {
        for( std::size_t k = after + 1; k + 3 < sc_.close; ++k )
        {
            if( isIdent( k ) && text( k ) == name && ( is( k + 1, "." ) || is( k + 1, "->" ) ) && is( k + 2, "back" ) && is( k + 3, "(" ) )
            {
                return true;
            }
        }
        return false;
    }

    // Does the function hold a name with a `total` token (dirTotal, out.total, totalRows) other than the site's own counter:
    // a count kept beside the list?
    bool namesTotal( std::string_view counter ) const
    {
        for( std::size_t k = sc_.open + 1; k < sc_.close; ++k )
        {
            if( !isIdent( k ) || is( k + 1, "(" ) || text( k ) == counter )
            {
                continue;
            }
            const std::vector<std::string> parts = nameTokens( text( k ) );
            if( std::find( parts.begin(), parts.end(), "total" ) != parts.end() )
            {
                return true;
            }
        }
        return false;
    }

    bool holdsWord( std::size_t s, std::size_t e, std::string_view w ) const noexcept
    {
        for( std::size_t k = s; k <= e && k < sc_.close; ++k )
        {
            if( is( k, w ) )
            {
                return true;
            }
        }
        return false;
    }

    // A cut: X.substr( A, kLimit ) or std::min( X.size(), kLimit ) with a named constant — the text or the list past the
    // constant is dropped where it is made. Not a cut: a substr compared at once (a prefix test).
    void cutSite( std::size_t name, std::size_t close )
    {
        const std::vector<ArgRange> args = splitArgs( src_, toks_, name + 1, close );
        if( args.size() != 2 || args[0].empty() || args[1].empty() )
        {
            return;
        }
        const bool isSubstr = is( name, "substr" );
        if( isSubstr && ( !( is( name - 1, "." ) || is( name - 1, "->" ) ) || is( close + 1, "==" ) || is( close + 1, "!=" ) || is( close + 1, "." ) ) )
        {
            return;
        }
        Compare     c;
        std::size_t other = 0;
        limitOf( args[1].first, args[1].last, c );
        if( c.limitKind != CapLimit::Named && !isSubstr )
        {
            other = 1;
            limitOf( args[0].first, args[0].last, c );
        }
        if( c.limitKind != CapLimit::Named || !c.alias.empty() )
        {
            return;
        }
        if( !isSubstr )
        {
            // the clamped operand is a size: C.size() / C.length()
            const ArgRange& o = args[other];
            if( o.last < o.first + 4 || !isIdent( o.first ) || !( is( o.last - 2, "size" ) || is( o.last - 2, "length" ) ) || !is( o.last - 1, "(" ) || !is( o.last, ")" ) )
            {
                return;
            }
            c.counter       = std::string( text( o.last - 4 ) );
            c.counterIsSize = true;
        }
        else if( name >= 2 && isIdent( name - 2 ) )
        {
            c.counter       = std::string( text( name - 2 ) );
            c.counterIsSize = true;
        }
        c.opAt  = name;
        c.first = name;
        c.last  = close;
        std::size_t stmt = name;
        while( stmt > sc_.open + 1 && !isStmtBoundary( src_, toks_[stmt - 1] ) )
        {
            --stmt;
        }
        raws_.push_back( { std::move( c ), CapShape::Cut, stmt, name, close - 1, stmtEnd( stmt ) } );
    }

    // Is the size of the cut's source compared, or read as a value, anywhere outside the cut itself?
    bool cutSourceSizeRead( const Raw& r ) const noexcept
    {
        if( r.cmp.counter.empty() )
        {
            return false;
        }
        for( std::size_t k = sc_.open + 1; k + 4 < sc_.close; ++k )
        {
            if( ( k >= r.cmp.first && k <= r.cmp.last ) || !isIdent( k ) || text( k ) != r.cmp.counter || !( is( k + 1, "." ) || is( k + 1, "->" ) )
                || !( is( k + 2, "size" ) || is( k + 2, "length" ) ) || !is( k + 3, "(" ) || neutralMention( k ) || inSilentCompare( k ) )
            {
                continue;
            }
            return true;
        }
        return false;
    }

    // Is the branch [s, e] a bare jump: `break;`, `continue;`, `return;`, `return EXPR;` (braced or not)?
    bool bareJump( std::size_t s, std::size_t e, std::string& returned, bool& isReturn ) const
    {
        if( is( s, "{" ) && is( e, "}" ) )
        {
            ++s;
            --e;
        }
        if( s > e || !is( e, ";" ) )
        {
            return false;
        }
        if( ( is( s, "break" ) || is( s, "continue" ) ) && e == s + 1 )
        {
            return true;
        }
        if( !is( s, "return" ) )
        {
            return false;
        }
        for( std::size_t k = s + 1; k < e; ++k )
        {
            if( is( k, ";" ) )
            {
                return false;
            }
        }
        isReturn = true;
        returned = e > s + 1 ? joinTokens( src_, toks_, s + 1, e - 1 ) : std::string();
        return true;
    }

    // Does another `return` of this function (outside [s, e]) return the same text?
    bool returnedElsewhere( const std::string& returned, std::size_t s, std::size_t e ) const
    {
        for( std::size_t k = sc_.open + 1; k < sc_.close; ++k )
        {
            if( ( k >= s && k <= e ) || !is( k, "return" ) )
            {
                continue;
            }
            const std::size_t end = stmtEnd( k );
            if( ( end > k + 1 ? joinTokens( src_, toks_, k + 1, end - 1 ) : std::string() ) == returned )
            {
                return true;
            }
        }
        return false;
    }

    void ifSite( std::size_t kw, std::size_t close, std::vector<CapFinding>& )
    {
        const std::size_t thenA = close + 1;
        const std::size_t thenB = stmtEnd( thenA );
        const bool        hasElse = is( thenB + 1, "else" );
        // a stop is the limit alone or one of several stops (`a > kA || b > kB`); under `&&` it is a guard on something else.
        // A keep is the limit and more conditions; under `||` the branch runs past the limit too.
        const bool anyAnd = holdsWord( kw + 2, close - 1, "&&" );
        const bool anyOr  = holdsWord( kw + 2, close - 1, "||" );
        for( Compare& c : comparesIn( kw + 2, close - 1 ) )
        {
            const bool isEq = is( c.opAt, "==" );
            Raw r{ std::move( c ), CapShape::Stop, kw, kw + 2, close - 1, hasElse ? stmtEnd( thenB + 2 ) : thenB };
            if( r.cmp.below ? anyOr : ( anyAnd || ( isEq && !r.cmp.counterIsSize ) ) )
            {
                continue;
            }
            if( !r.cmp.below && foundFlagBeside( kw + 2, close - 1 ) )
            {
                r.verdict     = CapVerdict::Probe;
                r.shapeSilent = false;
                raws_.push_back( std::move( r ) );
                continue;
            }
            if( r.cmp.below )
            {
                r.shape = CapShape::Keep;
                if( !keeps( r.cmp, thenA, thenB ) && !( !r.cmp.counterIsSize && is( thenB + 1, "++" ) && is( thenB + 2, r.cmp.counter ) && is( thenB + 3, ";" ) ) )
                {
                    continue;
                }
                if( hasElse || jumpsAtEnd( thenA, thenB ) )
                {
                    r.verdict     = CapVerdict::HasElse;
                    r.shapeSilent = false;
                }
            }
            else
            {
                std::string returned;
                bool        isReturn = false;
                if( !bareJump( thenA, thenB, returned, isReturn ) )
                {
                    if( !jumpsAtEnd( thenA, thenB ) )
                    {
                        continue;   // a branch that goes on: not a stop
                    }
                    r.verdict     = CapVerdict::BranchRecords;
                    r.shapeSilent = false;
                }
                else if( isReturn && !returned.empty() && !returnedElsewhere( returned, thenA, thenB ) )
                {
                    r.verdict     = CapVerdict::DistinctReturn;
                    r.shapeSilent = false;
                }
                r.returns = isReturn;
            }
            raws_.push_back( std::move( r ) );
        }
    }

    // Is one `||` operand of the condition [a, b] a bare flag (`found || ++n > kN`): the stop is a search's, on a find?
    bool foundFlagBeside( std::size_t a, std::size_t b ) const noexcept
    {
        for( std::size_t k = a; k <= b; ++k )
        {
            const bool startsOperand = k == a || is( k - 1, "||" );
            const std::size_t name   = is( k, "!" ) ? k + 1 : k;
            if( startsOperand && isIdent( name ) && ( name == b || is( name + 1, "||" ) ) )
            {
                return true;
            }
        }
        return false;
    }

    // A keep branch appends: it names the size counter's collection, or grows the counter.
    bool keeps( const Compare& c, std::size_t s, std::size_t e ) const noexcept
    {
        for( std::size_t k = s; k <= e; ++k )
        {
            if( !isIdent( k ) || text( k ) != c.counter )
            {
                continue;
            }
            if( c.counterIsSize ? ( is( k + 1, "+=" ) || is( k + 1, "[" ) || ( ( is( k + 1, "." ) || is( k + 1, "->" ) ) && isIdent( k + 2 ) && is( k + 3, "(" ) && isAppendMethod( text( k + 2 ) ) ) )
                                : ( is( k + 1, "++" ) || is( k - 1, "++" ) || is( k + 1, "+=" ) ) )
            {
                return true;
            }
        }
        return false;
    }

    // Does the branch [s, e] end in a jump (so it is a stop that records something first)?
    bool jumpsAtEnd( std::size_t s, std::size_t e ) const noexcept
    {
        if( !is( s, "{" ) || !is( e, "}" ) || e < s + 3 )
        {
            return false;
        }
        std::size_t k = e - 1;   // the last statement's `;`
        if( !is( k, ";" ) )
        {
            return false;
        }
        while( k > s + 1 && !is( k - 1, ";" ) && !is( k - 1, "}" ) && !is( k - 1, "{" ) )
        {
            --k;
        }
        return is( k, "break" ) || is( k, "continue" ) || is( k, "return" );
    }

    // Is token `k` inside a clamp or a size hint: an argument of min / reserve / substr / resize, an array bound, a static_assert?
    bool neutralMention( std::size_t k ) const noexcept
    {
        static constexpr std::array<std::string_view, 6> kNeutral = { "min", "reserve", "substr", "resize", "static_assert", "assign" };
        int depth = 0;
        for( std::size_t j = k; j-- > sc_.open; )
        {
            if( is( j, ")" ) || is( j, "]" ) )
            {
                ++depth;
            }
            else if( is( j, "(" ) || is( j, "[" ) )
            {
                if( depth-- > 0 )
                {
                    continue;
                }
                if( is( j, "[" ) )
                {
                    return true;
                }
                std::size_t callee = j;
                while( callee > sc_.open && angle_[callee - 1] != 0 )
                {
                    --callee;
                }
                return callee > sc_.open && isIdent( callee - 1 ) && std::find( kNeutral.begin(), kNeutral.end(), text( callee - 1 ) ) != kNeutral.end();
            }
            else if( is( j, ";" ) || is( j, "{" ) || is( j, "}" ) )
            {
                return false;
            }
        }
        return false;
    }

    bool inSilentCompare( std::size_t k ) const noexcept
    {
        return std::any_of( raws_.begin(), raws_.end(), [ & ]( const Raw& r ) { return r.shapeSilent && k >= r.cmp.first && k <= r.cmp.last; } );
    }

    // Is `name` declared in this function (a local or a parameter of a lambda in it): TYPE name = / ; / { / ( ?
    bool isLocal( std::string_view name ) const noexcept
    {
        for( std::size_t k = sc_.open + 2; k + 1 < sc_.close; ++k )
        {
            if( isIdent( k ) && text( k ) == name && ( isIdent( k - 1 ) || is( k - 1, ">" ) || is( k - 1, "&" ) || is( k - 1, "*" ) ) && !is( k - 1, "return" )
                && ( is( k + 1, "=" ) || is( k + 1, ";" ) || is( k + 1, "{" ) || is( k + 1, "(" ) || is( k + 1, "," ) || is( k + 1, ")" ) ) )
            {
                return true;
            }
        }
        return false;
    }

    // An if site: does a statement of its own block, before or after it, grow a count whatever the limit says — another
    // name's (`++total;`), or the counter's own when it outlives the function (a member that counts past the limit) — or
    // is a DISCLOSE statement there?
    bool totalCountedBeside( const Raw& r ) const noexcept
    {
        const auto grownAt = [ & ]( std::size_t k )
        {
            if( isIdent( k ) && is( k, "DISCLOSE" ) )
            {
                return true;
            }
            if( !is( k, "++" ) && !is( k, "+=" ) )
            {
                return false;
            }
            // the grown name: `++a.b;` reads forward along the member path, `a.b++` / `a.b += x` reads the token before
            std::size_t n = k;
            if( is( k, "++" ) && isIdent( k + 1 ) )
            {
                n = k + 1;
                while( ( is( n + 1, "." ) || is( n + 1, "->" ) ) && isIdent( n + 2 ) )
                {
                    n += 2;
                }
            }
            else if( k > 0 && isIdent( k - 1 ) )
            {
                n = k - 1;
            }
            return n != k && ( text( n ) != r.cmp.counter || ( !r.cmp.counterIsSize && !isLocal( r.cmp.counter ) ) );
        };
        int depth = 0;
        for( std::size_t k = r.at; k-- > sc_.open + 1; )
        {
            if( is( k, ")" ) || is( k, "]" ) || is( k, "}" ) )
            {
                ++depth;
            }
            else if( is( k, "(" ) || is( k, "[" ) || is( k, "{" ) )
            {
                if( depth-- == 0 )
                {
                    break;   // the block's own opening
                }
            }
            else if( depth == 0 && grownAt( k ) )
            {
                return true;
            }
        }
        depth = 0;
        for( std::size_t k = r.end + 1; k < sc_.close; ++k )
        {
            if( is( k, "(" ) || is( k, "[" ) || is( k, "{" ) )
            {
                ++depth;
            }
            else if( is( k, ")" ) || is( k, "]" ) || is( k, "}" ) )
            {
                if( depth-- == 0 )
                {
                    break;   // the block's own closing
                }
            }
            else if( depth == 0 && grownAt( k ) )
            {
                return true;
            }
        }
        return false;
    }

    // Is the limit named in this function outside every silent stop shape and clamp?
    bool limitNamedElsewhere( const Raw& r ) const noexcept
    {
        if( r.cmp.limitKind != CapLimit::Named )
        {
            return false;
        }
        for( std::size_t k = sc_.open + 1; k < sc_.close; ++k )
        {
            if( isIdent( k ) && ( text( k ) == r.cmp.limit || ( !r.cmp.alias.empty() && text( k ) == r.cmp.alias ) ) && !inSilentCompare( k ) && !neutralMention( k ) )
            {
                return true;
            }
        }
        return false;
    }

    // The last token of the loop that holds the site (the site's own loop for a loop site), or the site's end when none does.
    std::size_t loopEndAround( const Raw& r ) const noexcept
    {
        if( r.shape == CapShape::Loop )
        {
            return r.end;
        }
        std::size_t best = r.end;
        for( std::size_t k = sc_.open + 1; k < r.at; ++k )
        {
            if( ( is( k, "for" ) || is( k, "while" ) ) && is( k + 1, "(" ) )
            {
                const std::size_t end = stmtEnd( k );
                if( end >= r.end && end < sc_.close )
                {
                    best = std::max( best, end );
                }
            }
            else if( is( k, "do" ) && is( k + 1, "{" ) )
            {
                const std::size_t end = matchClose( src_, toks_, k + 1 );
                if( end >= r.end && end < sc_.close )
                {
                    best = std::max( best, end );
                }
            }
        }
        return best;
    }

    // Is the counter read after the loop: a plain identifier named again (outside a silent stop shape), or the size
    // counter's collection compared again?
    bool counterReadAfter( const Raw& r, std::size_t after ) const noexcept
    {
        for( std::size_t k = after + 1; k < sc_.close; ++k )
        {
            if( !isIdent( k ) || text( k ) != r.cmp.counter || inSilentCompare( k ) )
            {
                continue;
            }
            if( !r.cmp.counterIsSize )
            {
                // a test against 0 or 1 reads "any at all", not the limit
                const bool smallTest = ( is( k + 1, "==" ) || is( k + 1, "!=" ) || is( k + 1, ">" ) ) && ( is( k + 2, "0" ) || is( k + 2, "1" ) );
                if( !smallTest )
                {
                    return true;
                }
                continue;
            }
            if( ( is( k + 1, "." ) || is( k + 1, "->" ) ) && ( is( k + 2, "size" ) || is( k + 2, "length" ) ) && is( k + 3, "(" ) && is( k + 4, ")" ) && k + 6 < sc_.close
                && toks_[k + 5].kind == TokKind::Punct && isCompareOp( src_, toks_[k + 5] ) && !is( k + 6, "0" ) && !is( k + 6, "1" ) )
            {
                return true;
            }
        }
        return false;
    }

    // A loop site's other end conditions: is one tested again after the loop (`!level.empty()`), or is the size of the
    // collection it walks read outside a comparison anywhere in the function (a total)?
    CapVerdict otherEndVerdict( const Raw& r ) const
    {
        std::size_t a     = r.condA;
        int         depth = 0;
        for( std::size_t k = r.condA; k <= r.condB + 1; ++k )
        {
            if( k <= r.condB )
            {
                depth += ( is( k, "(" ) || is( k, "[" ) ) ? 1 : ( is( k, ")" ) || is( k, "]" ) ) ? -1 : 0;
            }
            if( k <= r.condB && !( depth == 0 && is( k, "&&" ) ) )
            {
                continue;
            }
            std::size_t ca = a;
            std::size_t cb = k - 1;
            a              = k + 1;
            if( ca > cb || ( r.cmp.first >= ca && r.cmp.last <= cb ) )
            {
                continue;   // the limit's own conjunct
            }
            while( ca < cb && is( ca, "!" ) )
            {
                ++ca;
            }
            // the conjunct `i < V.size()`: V's size read outside a comparison, anywhere outside this loop head
            for( std::size_t j = ca; j + 4 <= cb + 1; ++j )
            {
                if( isIdent( j ) && ( is( j + 1, "." ) || is( j + 1, "->" ) ) && ( is( j + 2, "size" ) || is( j + 2, "length" ) ) && is( j + 3, "(" ) && is( j + 4, ")" )
                    && sizeReadAsValue( text( j ), r ) )
                {
                    return CapVerdict::TotalRead;
                }
            }
            // a predicate conjunct (no counter in it): its text again after the loop
            const bool holdsCounter = std::any_of( toks_.begin() + std::ptrdiff_t( ca ), toks_.begin() + std::ptrdiff_t( cb ) + 1,
                                                   [ & ]( const Tok& t ) { return t.kind == TokKind::Ident && tokText( src_, t ) == r.cmp.counter; } );
            if( !holdsCounter && ( textAgainAfter( ca, cb, r.end ) || operandTestedAfter( ca, cb, r.end ) ) )
            {
                return CapVerdict::EndRetested;
            }
        }
        return CapVerdict::Silent;
    }

    bool sizeReadAsValue( std::string_view coll, const Raw& r ) const noexcept
    {
        for( std::size_t k = sc_.open + 1; k + 4 < sc_.close; ++k )
        {
            if( ( k >= r.condA && k <= r.condB ) || !isIdent( k ) || text( k ) != coll || !( is( k + 1, "." ) || is( k + 1, "->" ) )
                || !( is( k + 2, "size" ) || is( k + 2, "length" ) ) || !is( k + 3, "(" ) || !is( k + 4, ")" ) || inSilentCompare( k ) )
            {
                continue;
            }
            const auto compares = [ & ]( std::size_t j ) { return toks_[j].kind == TokKind::Punct && angle_[j] == 0 && ( isCompareOp( src_, toks_[j] ) || is( j, "!=" ) ); };
            if( !compares( k + 5 ) && !( k > sc_.open + 1 && compares( k - 1 ) ) && !neutralMention( k ) )
            {
                return true;
            }
        }
        return false;
    }

    // Is an operand of the conjunct [a, b] (an identifier that is not a call's name) inside an if condition after the loop?
    bool operandTestedAfter( std::size_t a, std::size_t b, std::size_t after ) const noexcept
    {
        for( std::size_t k = after + 1; k + 1 < sc_.close; ++k )
        {
            if( !is( k, "if" ) || !is( k + 1, "(" ) )
            {
                continue;
            }
            const std::size_t close = std::min( matchClose( src_, toks_, k + 1 ), sc_.close );
            for( std::size_t j = k + 2; j < close; ++j )
            {
                for( std::size_t m = a; isIdent( j ) && m <= b; ++m )
                {
                    if( isIdent( m ) && !is( m + 1, "(" ) && !is( m + 1, "::" ) && !( m > a && ( is( m - 1, "." ) || is( m - 1, "->" ) ) ) && text( m ) == text( j ) )
                    {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    bool textAgainAfter( std::size_t a, std::size_t b, std::size_t after ) const noexcept
    {
        const std::size_t n = b - a + 1;
        for( std::size_t k = after + 1; k + n <= sc_.close; ++k )
        {
            std::size_t m = 0;
            while( m < n && text( k + m ) == text( a + m ) )
            {
                ++m;
            }
            if( m == n )
            {
                return true;
            }
        }
        return false;
    }

    void judge( std::vector<CapFinding>& out )
    {
        const std::string_view fn = scopeName( src_, toks_, sc_ );
        for( Raw& r : raws_ )
        {
            if( r.cmp.limitKind == CapLimit::Requested )
            {
                continue;   // the caller's requested size: not a site (a stated miss)
            }
            if( r.verdict == CapVerdict::Silent && r.cmp.limitKind == CapLimit::Literal )
            {
                r.verdict = CapVerdict::LiteralLimit;
            }
            if( r.verdict == CapVerdict::Silent && limitNamedElsewhere( r ) )
            {
                r.verdict = CapVerdict::LimitNamed;
            }
            if( r.shape == CapShape::Cut )
            {
                r.verdict = r.verdict != CapVerdict::Silent ? r.verdict : cutSourceSizeRead( r ) ? CapVerdict::TotalRead : CapVerdict::Silent;
            }
            else if( r.verdict == CapVerdict::Silent && !r.returns && counterReadAfter( r, loopEndAround( r ) ) )
            {
                r.verdict = CapVerdict::CounterRead;
            }
            if( r.verdict == CapVerdict::Silent && ( r.shape == CapShape::Stop || r.shape == CapShape::Keep ) && ( totalCountedBeside( r ) || namesTotal( r.cmp.counter ) ) )
            {
                r.verdict = CapVerdict::TotalCounted;
            }
            if( r.verdict == CapVerdict::Silent && r.cmp.counterIsSize && r.shape != CapShape::Cut )
            {
                const std::size_t after = loopEndAround( r );
                r.verdict = r.shape == CapShape::Loop && appendedAfter( r.cmp.counter, after ) ? CapVerdict::WorkBound
                          : backReadAfter( r.cmp.counter, after )                             ? CapVerdict::EndRetested
                                                                                              : CapVerdict::Silent;
            }
            if( r.verdict == CapVerdict::Silent && r.shape == CapShape::Loop )
            {
                r.verdict = otherEndVerdict( r );
            }
            // one silent site per function and limit: the first stop is the site, a second one on the same limit is its twin
            if( r.verdict == CapVerdict::Silent
                && std::any_of( out.begin(), out.end(), [ & ]( const CapFinding& f ) { return f.verdict == CapVerdict::Silent && f.limit == r.cmp.limit; } ) )
            {
                continue;
            }
            CapFinding f;
            f.verdict   = r.verdict;
            f.shape     = r.shape;
            f.limitKind = r.cmp.limitKind;
            f.startByte = toks_[r.at].begin;
            f.text      = joinTokens( src_, toks_, r.at, r.shape == CapShape::Cut ? std::min( r.end, r.at + 60 ) : r.condB + 1 );
            f.limit     = r.cmp.limit;
            f.function  = std::string( fn );
            out.push_back( std::move( f ) );
        }
        // a site that left a trace names its limit for the rest of the tree (namedConstants); set after every verdict, so a
        // function's own sites are judged in one order-free pass
        for( Raw& r : raws_ )
        {
            r.shapeSilent = r.shapeSilent && ( r.verdict == CapVerdict::Silent || r.verdict == CapVerdict::LiteralLimit );
        }
    }

public:
    // The functions this one calls as a statement with a count grown before the call in the same block (`++r.tests;
    // noteSite( r.testAt, f, l );`): the callee's keep is counted here.
    void countedCallees( std::vector<std::string>& out ) const
    {
        for( std::size_t k = sc_.open + 2; k + 1 < sc_.close; ++k )
        {
            if( !isIdent( k ) || !is( k + 1, "(" ) || !cppStatementStartsAt( src_, toks_, k ) || !is( k - 1, ";" ) )
            {
                continue;
            }
            int depth = 0;
            for( std::size_t j = k - 1; j-- > sc_.open + 1; )
            {
                if( is( j, ")" ) || is( j, "]" ) || is( j, "}" ) )
                {
                    ++depth;
                }
                else if( ( is( j, "(" ) || is( j, "[" ) || is( j, "{" ) ) && depth-- == 0 )
                {
                    break;
                }
                else if( depth == 0 && is( j, "++" ) )
                {
                    out.emplace_back( text( k ) );
                    break;
                }
            }
        }
    }

    // The constants this function names outside every silent stop shape and clamp (call after findings()): each one is a
    // limit some code of the tree can tell a reader about.
    void namedConstants( std::vector<std::string>& out ) const
    {
        for( std::size_t k = sc_.open + 1; k < sc_.close; ++k )
        {
            if( isIdent( k ) && isConstName( text( k ) ) && !is( k + 1, "(" ) && !inSilentCompare( k ) && !neutralMention( k ) )
            {
                out.emplace_back( text( k ) );
            }
        }
    }

private:
    std::string_view        src_;
    const std::vector<Tok>& toks_;
    Scope                   sc_;
    std::vector<char>       angle_;
    std::vector<Raw>        raws_;
};

}   // namespace detail::cap

// One C++ file's cap scan: every cap site with its verdict (file order), the constants its functions name outside a silent
// stop, and the constants its static_asserts name. A Silent finding with a Named limit is final only against the TREE's
// two name sets (capResolve): another function that names the limit discloses for the site.
struct CapFileScan
{
    std::vector<CapFinding>  findings;
    std::vector<std::string> named;
    std::vector<std::string> asserted;
    std::vector<std::string> counted;   // functions some caller counts beside (FnScan::countedCallees)
};

inline CapFileScan capScanCpp( std::string_view src, const std::vector<detail::Tok>& toks )
{
    using namespace detail;
    CapFileScan out;
    for( const cap::Scope& sc : cap::functionScopes( src, toks ) )
    {
        cap::FnScan             scan( src, toks, sc );
        std::vector<CapFinding> found = scan.findings();
        // a constant the function names is named for every OTHER function's sites; its own sites were judged above
        std::vector<std::string> names;
        scan.namedConstants( names );
        const std::string_view fn = cap::scopeName( src, toks, sc );
        for( std::string& n : names )
        {
            out.named.push_back( std::string( fn ) + '\x1f' + std::move( n ) );
        }
        out.findings.insert( out.findings.end(), std::make_move_iterator( found.begin() ), std::make_move_iterator( found.end() ) );
        scan.countedCallees( out.counted );
    }
    rw::sortutil::sortUnique( out.counted );
    for( std::size_t k = 0; k + 1 < toks.size(); ++k )
    {
        if( toks[k].kind == TokKind::Ident && tokIs( src, toks[k], "static_assert" ) && tokIs( src, toks[k + 1], "(" ) )
        {
            const std::size_t close = matchClose( src, toks, k + 1 );
            for( std::size_t j = k + 2; j < close && j < toks.size(); ++j )
            {
                if( toks[j].kind == TokKind::Ident && cap::isConstName( tokText( src, toks[j] ) ) )
                {
                    out.asserted.emplace_back( tokText( src, toks[j] ) );
                }
            }
        }
    }
    return out;
}

// A silent finding's why=: the limit, and what is missing.
inline std::string capWhy( const CapFinding& f )
{
    return "the stop at " + f.limit + " leaves no trace: no flag, count or total beside it"
         + ( f.limitKind == CapLimit::Named ? std::string( ", and no other function names the limit" ) : std::string() );
}

// The tree's two name sets, sorted and unique: `named` rows are FUNCTION \x1f CONSTANT.
struct CapTreeNames
{
    std::vector<std::string> named;
    std::vector<std::string> asserted;
    std::vector<std::string> counted;

    void add( CapFileScan& scan )
    {
        counted.insert( counted.end(), std::make_move_iterator( scan.counted.begin() ), std::make_move_iterator( scan.counted.end() ) );
        named.insert( named.end(), std::make_move_iterator( scan.named.begin() ), std::make_move_iterator( scan.named.end() ) );
        asserted.insert( asserted.end(), std::make_move_iterator( scan.asserted.begin() ), std::make_move_iterator( scan.asserted.end() ) );
    }
    void seal()
    {
        for( std::vector<std::string>* names : { &named, &asserted, &counted } )
        {
            rw::sortutil::sortUnique( *names );
        }
    }
};

// A Silent finding's verdict against the tree: legend-tied when a static_assert names its limit, tree-names when a
// function other than its own names it outside a silent stop. Other verdicts, and limits that are not names, stand.
inline CapVerdict capResolve( const CapFinding& f, const CapTreeNames& tree )
{
    if( f.verdict != CapVerdict::Silent )
    {
        return f.verdict;
    }
    if( !f.function.empty() && f.shape != CapShape::Loop && std::binary_search( tree.counted.begin(), tree.counted.end(), f.function ) )
    {
        return CapVerdict::CallerCounts;
    }
    if( f.limitKind != CapLimit::Named )
    {
        return CapVerdict::Silent;
    }
    if( std::binary_search( tree.asserted.begin(), tree.asserted.end(), f.limit ) )
    {
        return CapVerdict::LegendTied;
    }
    const std::string suffix = '\x1f' + f.limit;
    for( const std::string& row : tree.named )
    {
        if( row.ends_with( suffix ) && std::string_view( row ).substr( 0, row.size() - suffix.size() ) != f.function )
        {
            return CapVerdict::TreeNames;
        }
    }
    return CapVerdict::Silent;
}

}   // namespace rw::defectshape

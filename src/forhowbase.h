#pragma once
// forhowbase.h — the TRIGGER and the legend clauses of the shape="how" answer (forhow.h), dependency-free so cli.h
// (Config::howArgsDefault) and legenddict.h (the session dictionary) read them without the answer's machinery.
//
// The legend clauses are NAMED so the session dictionary
// (legenddict.h kForClauseEntries) holds the SAME bytes every surface appends: under legend="ref" a clause leaves an
// answer only where it is found verbatim and the session was already sent it, so a clause spelled twice would simply
// stop being dropped. Every clause defines its attributes `name=` (legendcoveragecheck's predicate). No "--" in any of
// them: they ride inside an XML comment, where a double hyphen is ill-formed (G4) — flags are named without dashes.

#include <algorithm>
#include <cstddef>
#include <string_view>

namespace rw
{

// What the shape is and what it leaves out. lens= takes the MCP dialect's meaning (mcpverbs.h kMcpForLensColumnsLegend):
// a named column is NOT CARRIED, never measured-and-zero.
inline constexpr std::string_view kHowShapeLegend =
    "; shape=how: a call path answer, not a ranked list; lens=: columns and sections not carried (never 0; the"
    " signatures-only flag on the same for task serves them)";

inline constexpr std::string_view kHowPathLegend =
    "; path seeds= hops=: up to 3 seeds and the resolved calls walked from them, a > b > c | b > d (a later chain"
    " starts at its branch point; 9 hops, depth 4); capped=1 next=: callees left to expand; cut_names= cut_callees="
    " cut_lines=: rows the 8 KB answer ceiling cut, in that order (each element's next= returns them);"
    " over_ceiling=1: still over after the cuts; counts_floor=1: every call count is a floor (resolved calls only)";

inline constexpr std::string_view kHowHopLegend =
    "; h n= p=file:line: a hop, its signature as text; c n= cl= p=: its resolved callees, task words first (8 for a"
    " seed, 4 deeper), cl= up to 3 call lines, p= when it has no h row; amb=K: K definitions, not followed; us u n= p="
    " cl=: a seed's callers (a member's: its type's); shown= total= capped=1 next=: the whole list (the metrics flag"
    " reads this answer's index)";

inline constexpr std::string_view kHowBodyLegend =
    "; b n= p= lines_shown= sel= lines_total= next=: the first 3 hops' selected lines, N: text (1 KB a body, 2 KB in"
    " all) of sel= selected and lines_total= in the body; next= the body";

inline constexpr std::string_view kHowNamesLegend =
    "; names shown= total= past= next=: the 40-row window's other rows, name p:line; in rank order, total= those"
    " rows, next= every window row; past= positive-score files past the window (the limit=N page)";

inline constexpr std::string_view kHowEstLegend = "; est_tokens= prices this answer in tokens";

inline constexpr std::string_view kHowTaskLegend = "; task= the query";

// Two clauses of the --for lens's COMPACT dialect, here so the how answer's compact head (forhow.h) and the lens
// (verbs_for.h appendCompactForLegend) spell them once.
inline constexpr std::string_view kForCompactConfidenceClause = "; confidence=/margin_pct= head score drop (low=flat)";
inline constexpr std::string_view kForCompactHdrClause =
    "; hdr p= of=: the named file's one same-dir same-stem decl/impl partner, listed first (a lookup)";

// The opener of the how legend inside a --pack-task / explore answer: NOT a "<!-- ripwire " prose opener, so the compact
// dialect (compactlegend.h) keeps it as the answer's own legend of the sections it adds, and legenddict.h reduces its
// clauses under legend="ref" exactly as it reduces the MCP `for` lens legend's.
inline constexpr std::string_view kHowPackTaskLegendOpen = "<!-- how";

// The attribute value lens= carries on every shape="how" root: the BASE --for row columns and sections this shape drops
// (prereg R): cx ccx in churn amp tested clone, the <lego>/<compose> stubs, the file tail, BASE's <hops>.
inline constexpr std::string_view kHowLensValue = "cx,ccx,in,churn,amp,tested,clone,lego,compose,tail,hops";

namespace forhow
{

// ── the trigger (v1 §0, frozen; the spellings below are this commit's, set on ripwire/django/webpack only) ──────────
inline constexpr std::string_view kHowPrefixes[] = { "how does ", "how do ", "how is ", "how are ", "how can ",
                                                     "explain how ", "walk me through ", "what happens when " };
inline constexpr std::string_view kHowExcludedOpeners[] = { "how many", "how much", "how often", "how long" };

// leading ASCII whitespace and quote characters — " ' ` and the four typographic quotes — trimmed in any order
inline std::string_view trimHowLead( std::string_view t ) noexcept
{
    static constexpr std::string_view kQuotes[] = { "\"", "'", "`", "\xE2\x80\x9C", "\xE2\x80\x9D", "\xE2\x80\x98", "\xE2\x80\x99" };
    bool isTrimming = true;
    while( isTrimming && !t.empty() )
    {
        isTrimming = false;
        const char c = t.front();
        if( c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f' )
        {
            t.remove_prefix( 1 );
            isTrimming = true;
            continue;
        }
        for( const std::string_view q : kQuotes )
        {
            if( t.starts_with( q ) )
            {
                t.remove_prefix( q.size() );
                isTrimming = true;
                break;
            }
        }
    }
    return t;
}

inline bool howTextFires( std::string_view task ) noexcept
{
    const std::string_view t = trimHowLead( task );
    char                   low[ 24 ];
    const std::size_t      n = std::min( t.size(), sizeof( low ) );
    for( std::size_t i = 0; i < n; ++i )
    {
        const char c = t[i];
        low[i]       = ( c >= 'A' && c <= 'Z' ) ? char( c - 'A' + 'a' ) : c;
    }
    const std::string_view head( low, n );
    for( const std::string_view x : kHowExcludedOpeners )
    {
        if( head.starts_with( x ) )
        {
            return false;
        }
    }
    for( const std::string_view p : kHowPrefixes )
    {
        if( head.starts_with( p ) )
        {
            return true;
        }
    }
    return false;
}

// The CLI half of "default arguments" (prereg §0 Scope): exactly one root, exactly one of --for=/--pack-task=, and
// otherwise only --legend=, --cache[=PATH] or --no-cache. Any other argument — a shaping flag, a format, a budget, a
// page, a second root — keeps the pre-change answer.
inline bool howCliArgsDefault( int argc, char** argv ) noexcept
{
    int rootCount = 0;
    int verbCount = 0;
    for( int i = 1; i < argc; ++i )
    {
        const std::string_view a = argv[i];
        if( a.starts_with( "--for=" ) || a.starts_with( "--pack-task=" ) )
        {
            ++verbCount;
            continue;
        }
        if( a.starts_with( "--legend=" ) || a == "--cache" || a.starts_with( "--cache=" ) || a == "--no-cache" )
        {
            continue;
        }
        if( a.starts_with( "-" ) )
        {
            return false;
        }
        ++rootCount;
    }
    return rootCount == 1 && verbCount == 1;
}

} // namespace forhow

} // namespace rw

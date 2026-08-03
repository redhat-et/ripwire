#pragma once

// didyoumean.h — the ONE near-miss suggester: bounded edit distance + "did you mean 'Y'?".
//
// It lived in main.cpp, which put it out of reach of the MCP surface — and that is exactly why the MCP
// not-found refusals had none (§B6 M8: seven verbs across both arms answered a bare "symbol not found",
// echoing neither the spelling the caller typed nor a near-miss, while the `flags` verb next door did
// both). Lifting it into a header is what makes ONE suggester serve all three surfaces instead of the MCP
// arms growing a second, differently-tuned one.
//
// Nothing about the algorithm changed in the move; the block below is main.cpp's verbatim, which still
// calls it through the same three names (main.cpp pulls them in with using-declarations so its 17 call
// sites are untouched).

#include "model.h"

#include <algorithm>
#include <cctype>
#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// §P12.1: bounded edit distance (Optimal String Alignment — Levenshtein + adjacent-transposition, the
// restricted form of Damerau-Levenshtein), case-insensitive. Returns the true distance when it is <=
// maxDist, else maxDist+1 as a "too far to matter" sentinel — callers only ever compare against maxDist,
// never need the exact magnitude past the cutoff. Length-delta pre-filter first (distance is always >=
// |len(a)-len(b)|, O(1)) prunes almost the whole corpus before the O(n*m) DP runs, which is what keeps
// didYouMean() linear-ish over ~6000 symbol names despite the DP being quadratic per candidate — symbol
// names are short (identifiers, not templates-expanded text) so n*m per surviving candidate is tiny.
inline int boundedEditDistance( std::string_view a, std::string_view b, int maxDist )
{
    const std::size_t n = a.size(), m = b.size();
    const int lenDelta = int( n ) > int( m ) ? int( n ) - int( m ) : int( m ) - int( n );
    if( lenDelta > maxDist )
    {
        return maxDist + 1;
    }

    const auto lo = []( char c ) { return static_cast<char>( std::tolower( static_cast<unsigned char>( c ) ) ); };

    // rolling three rows (prev2/prev1/cur) — prev2 is needed for the transposition term. Row 0 = distance
    // from the empty prefix of a to each prefix of b (pure insertions), matching the standard DP boundary.
    std::vector<int> prev2( m + 1, 0 ), prev1( m + 1 ), cur( m + 1 );
    for( std::size_t j = 0; j <= m; ++j )
    {
        prev1[j] = int( j );
    }

    for( std::size_t i = 1; i <= n; ++i )
    {
        cur[0] = int( i );
        const char ai = lo( a[i - 1] );
        for( std::size_t j = 1; j <= m; ++j )
        {
            const char bj   = lo( b[j - 1] );
            const int  cost = ( ai == bj ) ? 0 : 1;
            int val = std::min( { cur[j - 1] + 1, prev1[j] + 1, prev1[j - 1] + cost } );
            if( i > 1 && j > 1 && ai == lo( b[j - 2] ) && lo( a[i - 2] ) == bj )
            {
                val = std::min( val, prev2[j - 2] + 1 );   // adjacent transposition ("teh" -> "the")
            }
            cur[j] = val;
        }
        prev2.swap( prev1 );
        prev1.swap( cur );
    }
    const int dist = prev1[m];
    return dist > maxDist ? maxDist + 1 : dist;
}

// A3-F16a: "did you mean 'Y'?" for every SYM-taking verb's "not found" error (--callers/--callees/--uses/
// --expand/--around/--lego/--path/--impact/--mentions/--owners). §P12.1: true bounded edit distance, not
// the old shared-prefix*4 - |lenDelta| heuristic — that score let an unrelated symbol whose length happened
// to be close outscore a genuine one-edit typo whenever the typo landed early/mid-prefix (`parsArgs` scored
// `parseAlt`, 4+ edits away, over `parseArgs`, 1 edit away).
// Deterministic tie-break on ties: (a) smaller distance already selects the candidate; (b) longer
// case-insensitive shared prefix; (c) lexicographic name — same "closest wins, ties resolved reproducibly"
// contract as before. Empty when nothing in the corpus is within kMaxEditDistance edits (an honest "no
// plausible near-miss" rather than forcing a bad suggestion — matches the file's honest-limits ethos).
//
// (`--flip`'s own suggester, src/flipimpact.h:499 `nearestGateNames`, does NOT generalize here: it is a
// substring-containment-first heuristic tuned for SCREAMING_SNAKE gate families sharing a literal prefix
// segment, and falls back to the SAME buggy prefix*4-lenDelta score this fix replaces when containment
// doesn't fire — so it is not "a second correct convention" to reuse, it shares the defect at its edges.)
//
// X9(e) fix: EVERY call site above is a code-symbol lookup (a mistyped function/class/interface name) —
// none of them is ever asking "which markdown heading did I mean?". SymKind::Section (a markdown heading,
// captured so docs join the same graph — see model.h) was still in the candidate pool, so a code-symbol
// typo could surface a doc Section title as the suggested fix ("did you mean 'Installation'?" for a
// mistyped C++ function name) — a confusing, useless hint. Excluded here, once, for every caller; if a
// future verb genuinely wants Section suggestions (a markdown-title lookup), it needs its own pool, not
// this shared one.
inline std::string didYouMean( const IngestResult& ing, std::string_view name )
{
    constexpr int kMaxEditDistance = 3;   // bandwidth cutoff (§P12.1): beyond this a "hint" is noise, not help
    struct Cand { int dist; std::size_t prefixLen; std::string_view n; };
    Cand best{ kMaxEditDistance + 1, 0, {} };
    for( const Symbol& s : ing.symbols )
    {
        if( s.name.empty() || s.kind == SymKind::Section )
        {
            continue;
        }
        const int dist = boundedEditDistance( s.name, name, kMaxEditDistance );
        if( dist > kMaxEditDistance )
        {
            continue;
        }
        std::size_t pfx = 0;
        const std::size_t lim = std::min( s.name.size(), name.size() );
        while( pfx < lim && std::tolower( static_cast<unsigned char>( s.name[pfx] ) ) == std::tolower( static_cast<unsigned char>( name[pfx] ) ) )
        {
            ++pfx;
        }
        const bool better = dist < best.dist
                          || ( dist == best.dist && pfx > best.prefixLen )
                          || ( dist == best.dist && pfx == best.prefixLen && ( best.n.empty() || s.name < best.n ) );
        if( better )
        {
            best = { dist, pfx, std::string_view( s.name ) };
        }
    }
    return best.n.empty() ? std::string() : std::string( best.n );
}

// appends " (did you mean 'Y'?)" to a "not found"-style stderr message when a plausible nearest name
// exists, else returns the message unchanged — ONE shared call site so every SYM-taking verb's error
// gets the same suggestion behaviour instead of each verb growing its own ad hoc hint.
inline std::string withDidYouMean( const IngestResult& ing, std::string_view name, std::string msg )
{
    const std::string near = didYouMean( ing, name );
    if( !near.empty() && near != name )
    {
        msg += " (did you mean '" + near + "'?)";
    }
    return msg;
}

}   // namespace rw

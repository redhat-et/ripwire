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
// The shared "closest candidate" core behind didYouMean() and any OTHER near-miss finder over a
// different pool (e.g. lintcatalog.h's rule-name near-miss for --lint-select=/--lint-ignore=): bounded
// edit distance, tie-broken by (1) smaller distance, (2) longer case-insensitive shared prefix, (3)
// lexicographic order — one implementation of that contract instead of one per pool. `nameOf` projects
// one pool item to its comparable name; an item whose projected name is empty is skipped (didYouMean's
// own "s.name.empty() || Section" exclusion is just a nameOf that returns "" for those).
template <class It, class NameOf>
inline std::string_view nearestNameByEditDistance( It first, It last, std::string_view typed, int maxEditDistance, NameOf&& nameOf )
{
    struct Cand { int dist; std::size_t prefixLen; std::string_view n; };
    Cand best{ maxEditDistance + 1, 0, {} };
    for( It it = first; it != last; ++it )
    {
        const std::string_view cand = nameOf( *it );
        if( cand.empty() )
        {
            continue;
        }
        const int dist = boundedEditDistance( cand, typed, maxEditDistance );
        if( dist > maxEditDistance )
        {
            continue;
        }
        std::size_t       pfx = 0;
        const std::size_t lim = std::min( cand.size(), typed.size() );
        while( pfx < lim && std::tolower( static_cast<unsigned char>( cand[pfx] ) ) == std::tolower( static_cast<unsigned char>( typed[pfx] ) ) )
        {
            ++pfx;
        }
        const bool better = dist < best.dist
                          || ( dist == best.dist && pfx > best.prefixLen )
                          || ( dist == best.dist && pfx == best.prefixLen && ( best.n.empty() || cand < best.n ) );
        if( better )
        {
            best = { dist, pfx, cand };
        }
    }
    return best.n;
}

// The nearest INDEXED FILE PATH to a typed path, by bounded edit distance over the BASENAME — empty when
// nothing in the corpus is close enough. The comparison is basename-only on purpose: a caller who got the
// directory prefix wrong asked a different question (answered by the "a path SUFFIX is enough" clause the
// callers append), while the fault this suggests over is a mistyped file NAME. The FULL path is what comes
// back, because the full path is what pastes into a retry.
//
// ONE implementation for both surfaces (H6/F11, capture-audit 2026-09-04). The MCP `cochange` refusal grew
// this first ("file not found: 'src/grap.h' (did you mean './src/graph.h'?)") and the CLI FILE-list
// selectors — --situ / --test-gate / --affected / --exercises / --cochange — had none at all, so the same
// typo got a helpful answer over MCP and a bare "file not found" from the CLI. It sits beside didYouMean()
// rather than inside either surface's refusal header for exactly the reason that header exists: a suggester
// per surface is two suggesters that drift.
inline std::string_view nearestIndexedFile( const IngestResult& ing, std::string_view typed )
{
    if( typed.empty() )
    {
        return {};   // F10: the nearest path to "" is the shortest path, which is a suggestion about nothing
    }
    constexpr int kMaxEditDistance = 3;   // same bandwidth cutoff as didYouMean
    const auto    baseName = []( std::string_view p ) -> std::string_view
    {
        const std::size_t slash = p.rfind( '/' );
        return slash == std::string_view::npos ? p : p.substr( slash + 1 );
    };

    const std::string_view typedBase = baseName( typed );
    std::string_view       best;
    int                    bestDist = kMaxEditDistance + 1;
    for( const std::string& indexedPath : ing.files )
    {
        const int dist = boundedEditDistance( baseName( indexedPath ), typedBase, kMaxEditDistance );
        if( dist > kMaxEditDistance )
        {
            continue;
        }
        if( dist < bestDist || ( dist == bestDist && ( best.empty() || indexedPath < best ) ) )   // deterministic tie-break
        {
            bestDist = dist;
            best     = indexedPath;
        }
    }
    return best;
}

// " (did you mean 'PATH'? a path SUFFIX is enough)" for a FILE selector that matched nothing, or "" when no
// indexed path is close. Appended by each FILE-selector verb to its OWN sentence — the sentence differs per
// verb (each explains what its argument grammar is); the suggestion does not.
inline std::string nearestIndexedFileClause( const IngestResult& ing, std::string_view typed )
{
    const std::string_view best = nearestIndexedFile( ing, typed );
    if( best.empty() || best == typed )
    {
        return {};
    }
    return " (did you mean '" + std::string( best ) + "'? a path SUFFIX is enough)";
}

// The nearest indexed symbol name from a FILTERED pool — the one place the corpus is walked for a near-miss
// over symbols. didYouMean and nearestAggregateName differ only in which symbols are candidates, and writing
// that twice is the clone --quality-delta flags (159 shared tokens on the first draft of this pair).
// `keep` is a plain function pointer, not a template parameter: this is a refusal path, the pools are two,
// and one non-template definition keeps the header cheap for the ~40 translation units that include it.
inline std::string_view nearestSymbolNameWhere( const IngestResult& ing, std::string_view typed, bool ( *keep )( const Symbol& ) )
{
    if( typed.empty() )
    {
        return {};   // F10: the nearest name to "" is the shortest name, which is a suggestion about nothing
    }
    constexpr int kMaxEditDistance = 3;   // bandwidth cutoff (§P12.1): beyond this a "hint" is noise, not help
    return nearestNameByEditDistance( ing.symbols.begin(), ing.symbols.end(), typed, kMaxEditDistance,
                                      [ keep ]( const Symbol& s ) -> std::string_view
                                      { return keep( s ) ? std::string_view( s.name ) : std::string_view(); } );
}

// The nearest indexed STRUCT / CLASS / INTERFACE name (F13). --layout and --field-affinity refuse over a
// pool of 494 aggregates they have already loaded and offered nothing but "try --grep=<what you typed>",
// while every SYMBOL selector one keystroke away names the symbol. Same core, a different pool — which is
// exactly what nearestNameByEditDistance exists to make cheap.
inline std::string nearestAggregateName( const IngestResult& ing, std::string_view typed )
{
    const std::string_view best = nearestSymbolNameWhere( ing, typed, []( const Symbol& s )
                                                          {
                                                              return s.kind == SymKind::Struct || s.kind == SymKind::Class
                                                                  || s.kind == SymKind::Interface;
                                                          } );
    return best.empty() || best == typed ? std::string() : ( " (did you mean '" + std::string( best ) + "'?)" );
}

// F10/F14: an EMPTY item inside a comma-separated selector list. Two verbs met it two wrong ways — --path
// RESOLVED it (and had the suggester answer about ""), --connect and --expand DROPPED it, so a trailing
// comma, or a shell variable that expanded to nothing, silently changed the question and still exited 0. An
// empty item is not a selector: say which position is empty, and give the accepted form.
inline std::string emptyListItemMessage( std::string_view flag, std::size_t oneBasedPosition, std::string_view example )
{
    return "ripwire: " + std::string( flag ) + ": item " + std::to_string( oneBasedPosition ) + " of the comma list is empty "
           "— an empty item names no symbol, and dropping it would silently change the question you asked; "
           "remove the extra comma, or name a symbol there (e.g. " + std::string( example ) + ")";
}

// F10 (capture-audit 2026-09-04): the empty-query guard lives in nearestSymbolNameWhere above, not here —
// asked for the nearest name to "", the distance metric answers with the SHORTEST symbol in the corpus, and
// `--path=rankGraphTeleport,` printed "endpoint not found:  (did you mean 'A'?)". Guarded at the shared walk
// so every caller that can be handed an empty list item is covered, present and future.
inline std::string didYouMean( const IngestResult& ing, std::string_view name )
{
    const std::string_view best = nearestSymbolNameWhere( ing, name, []( const Symbol& s ) { return s.kind != SymKind::Section; } );
    return best.empty() ? std::string() : std::string( best );
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

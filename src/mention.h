#pragma once

// mention.h — B8 (query-mention anchoring; see bench/headtohead/REPORT.md).
//
// The measured #1 loss bucket in the 4-arm competitor head-to-head: when the task text LITERALLY NAMES
// the place to look — a path (`sklearn/ensemble/_iforest.py`, even inside a GitHub URL), a dotted module
// (`transformers.optimization`), or a scoped symbol (`DTypeSchema.validate`) — the subtoken+body ranker
// dilutes those few tokens across the whole prose query and the named file can land at rank 40-60, while
// a plain BM25-over-filenames competitor lands it at rank 1-8. 4 of the 5 competitor-only strict wins
// (N=60 held-out) were exactly this shape. The fix is direct and deterministic: extract explicit mentions
// from the task text, match them against the INDEXED corpus (never the filesystem), and lift the matched
// files' best symbols / the matched symbols to just below the current top score.
//
// Contract (each promise pinned in test/mentioncheck.sh):
//   * INERT WITHOUT MENTIONS — a task that names no indexed file/module/symbol leaves lensRank untouched
//     and the output BYTE-IDENTICAL (extraction is pure string work; no I/O, no subprocess).
//   * NEVER DISPLACES #1 — boosted scores are strictly BELOW the current maximum (the top hit the ranker
//     already believes in cannot be dethroned by an anchor; it can only be joined near the top).
//   * BOUNDED — at most kMentionMaxFiles files x kMentionMaxSymbolsPerFile symbols, plus at most
//     kMentionMaxDirectSymbols directly-named symbols, are touched.
//   * DETERMINISTIC — mentions keep task-text appearance order; every match set is reduced with a total
//     order (score desc, id asc / path asc); no hashing, no RNG.

#include <algorithm>
#include <array>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include "model.h"
#include "graph.h"   // R5: applyDocMentionBoost reads g.mentions (the doc->code backtick edges the
                      // --mentions=SYM verb already exposes) — same header gitmine.h already pulls in for
                      // an analogous "read one more Graph field" reason.

namespace rw
{

// Fixed knobs — deliberately NOT flags (one documented behavior, one ablation switch to kill it whole).
inline constexpr std::size_t kMentionMaxRawTokens      = 16;     // extraction cap: first N candidate mention tokens, text order
inline constexpr std::size_t kMentionMaxFiles          = 4;      // strongest evidence only: files named first in the text
inline constexpr std::size_t kMentionMaxSymbolsPerFile = 3;      // per mentioned file: its top symbols by (lens score desc, id asc)
inline constexpr std::size_t kMentionMaxDirectSymbols  = 8;      // directly-named (Scope.name / `name`) symbols, id asc
inline constexpr float       kMentionTopGapStep        = 0.05f;  // slot i lands at top*(1 - step*(i+1)) — below #1, above the pack

struct MentionBoostInfo
{
    std::uint32_t fileCount   = 0;   // matched files that received a boost
    std::uint32_t symbolCount = 0;   // total symbols lifted (file-derived + direct)
};

// One extracted candidate mention, classified by shape. `segments` are the '/'- or '.'-separated parts
// (lowercased never — corpus paths are case-sensitive).
namespace mention_detail
{

struct RawMention
{
    std::vector<std::string> segments;   // path or dotted segments, in order
    bool                     isPath = false;   // came with '/' (or an extension-bearing basename) → match as path
};

inline bool isIdentChar( char c ) noexcept
{
    return ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_';
}

// token characters: identifiers plus the joiners that make a path/module/symbol mention ('.', '/', '-')
inline bool isTokenChar( char c ) noexcept { return isIdentChar( c ) || c == '.' || c == '/' || c == '-'; }

// basename of an indexed path, and the same with its extension stripped ("src/a/b.py" → "b.py", "b")
inline std::string_view baseNameOf( std::string_view path ) noexcept
{
    const std::size_t slash = path.rfind( '/' );
    return slash == std::string_view::npos ? path : path.substr( slash + 1 );
}
inline std::string_view stripExt( std::string_view name ) noexcept
{
    const std::size_t dot = name.rfind( '.' );
    return ( dot == std::string_view::npos || dot == 0 ) ? name : name.substr( 0, dot );
}

// does `path` end with the mention's segments as whole path components (extension-agnostic on the last)?
// e.g. segments [transformers, optimization] matches "src/transformers/optimization.py".
inline bool pathSuffixMatches( std::string_view path, const std::vector<std::string>& segments ) noexcept
{
    if( segments.empty() ) return false;

    // last segment: whole basename, basename-with-extension, or basename-sans-extension
    const std::string_view base = baseNameOf( path );
    const std::string&     last = segments.back();
    std::string_view       remaining;
    if( base == last )                               remaining = path.substr( 0, path.size() - base.size() );
    else if( stripExt( base ) == last )              remaining = path.substr( 0, path.size() - base.size() );
    else                                             return false;

    // earlier segments must match the preceding whole components right-to-left
    // (decrement INSIDE the body — the `i-- > 0` idiom wraps the unsigned at loop exit, which G1's
    // integer sanitizer deliberately traps on ripwire-owned code)
    for( std::size_t i = segments.size() - 1; i > 0; )
    {
        --i;
        if( remaining.empty() || remaining.back() != '/' ) return false;
        remaining.remove_suffix( 1 );
        const std::string_view comp = baseNameOf( remaining );
        if( comp != segments[i] ) return false;
        remaining = remaining.substr( 0, remaining.size() - comp.size() );
    }
    return true;
}

// extract candidate mentions from the task text: '/'-joined path tokens, dot-joined identifier chains,
// and `backticked` identifiers. Plain prose words never qualify — precision over recall by design.
inline std::vector<RawMention> extractMentions( std::string_view task )
{
    std::vector<RawMention> raw;
    std::size_t i = 0;
    while( i < task.size() && raw.size() < kMentionMaxRawTokens )
    {
        if( !isTokenChar( task[i] ) ) { ++i; continue; }
        const std::size_t start = i;
        while( i < task.size() && isTokenChar( task[i] ) ) ++i;
        std::string_view tok = task.substr( start, i - start );
        const bool backticked = start > 0 && task[start - 1] == '`' && i < task.size() && task[i] == '`';

        // trim joiner punctuation that is really sentence punctuation ("see foo.py." / "path/,")
        while( !tok.empty() && ( tok.back() == '.' || tok.back() == '/' || tok.back() == '-' ) ) tok.remove_suffix( 1 );
        while( !tok.empty() && ( tok.front() == '.' || tok.front() == '/' || tok.front() == '-' ) ) tok.remove_prefix( 1 );
        if( tok.size() < 3 || tok.size() > 200 ) continue;

        const bool hasSlash = tok.find( '/' ) != std::string_view::npos;
        const bool hasDot   = tok.find( '.' ) != std::string_view::npos;
        if( !hasSlash && !hasDot && !backticked ) continue;   // plain word — not a mention

        // split on the joiner ('/' wins: a URL/path token's dots live inside its basename segment)
        RawMention m;
        m.isPath = hasSlash;
        const char joiner = hasSlash ? '/' : '.';
        std::size_t p = 0;
        bool malformed = false;
        std::size_t maxSegmentLen = 0;
        while( p <= tok.size() )
        {
            const std::size_t q = tok.find( joiner, p );
            const std::string_view seg = tok.substr( p, ( q == std::string_view::npos ? tok.size() : q ) - p );
            if( seg.empty() ) { malformed = !hasSlash; if( hasSlash ) { p = ( q == std::string_view::npos ) ? tok.size() + 1 : q + 1; continue; } break; }
            m.segments.emplace_back( seg );
            maxSegmentLen = std::max( maxSegmentLen, seg.size() );
            if( q == std::string_view::npos ) break;
            p = q + 1;
        }
        if( malformed || m.segments.empty() ) continue;

        // dotted chains need a real identifier somewhere ("e.g", "i.e", version numbers "3.10" stay prose)
        if( !hasSlash && !backticked )
        {
            if( m.segments.size() < 2 || maxSegmentLen < 3 ) continue;
            bool allDigits = true;
            for( const std::string& s : m.segments ) for( const char c : s ) if( c < '0' || c > '9' ) { allDigits = false; break; }
            if( allDigits ) continue;
        }

        // path mentions keep only their meaningful tail (a URL prefix like github.com/org/repo/blob/main
        // would otherwise demand components the indexed repo-relative path does not have)
        if( m.isPath && m.segments.size() > 3 ) m.segments.erase( m.segments.begin(), m.segments.end() - 3 );

        raw.push_back( std::move( m ) );
    }
    return raw;
}

} // namespace mention_detail

// Apply the mention anchor to `lensRank` (size == ing.symbols.size()). Returns true if anything moved.
inline bool applyMentionBoost( const IngestResult& ing, std::string_view task, std::vector<float>& lensRank, MentionBoostInfo* outInfo = nullptr )
{
    using namespace mention_detail;
    VERIFY( lensRank.size() == ing.symbols.size() );
    if( task.empty() || lensRank.empty() || lensRank.size() != ing.symbols.size() ) return false;

    const std::vector<RawMention> raw = extractMentions( task );
    if( raw.empty() ) return false;

    // current top score = the unbreakable ceiling (a rank with no positive score anchors from 1.0)
    float topScore = 0.0f;
    for( const float s : lensRank ) topScore = std::max( topScore, s );
    if( !( topScore > 0.0f ) ) topScore = 1.0f;

    // pass 1 — resolve mentions to files (text order, deduped, capped) and to directly-named symbols.
    std::vector<std::uint32_t> mentionedFiles;                       // <= kMentionMaxFiles, text order
    std::vector<NodeId>        directSymbols;                        // deduped, id asc at the end
    const std::size_t          fileCount = ing.files.size();
    for( const RawMention& m : raw )
    {
        // (a) file match: path-suffix / basename / basename-sans-ext against every indexed path, trying
        //     progressively SHORTER suffixes (all segments, then the last 2, then the bare basename) —
        //     a GitHub-URL mention carries branch/repo components the indexed repo-relative path never
        //     has, so the longest suffix that matches anything wins and shorter ones are not consulted.
        //     Deterministic: files are lexicographically sorted at ingest, first match by ascending fileId
        //     is stable; a basename naming MANY files (a `utils.py` everywhere) still yields at most the
        //     first few via the global file cap — bounded noise, and the ablation gate judges the trade.
        bool matchedFile = false;
        for( std::size_t suffixLen = m.segments.size(); suffixLen >= 1 && !matchedFile; --suffixLen )
        {
            const std::vector<std::string> suffix( m.segments.end() - suffixLen, m.segments.end() );
            for( std::uint32_t f = 0; f < fileCount && mentionedFiles.size() < kMentionMaxFiles; ++f )
            {
                if( !pathSuffixMatches( ing.files[f], suffix ) ) continue;
                if( std::find( mentionedFiles.begin(), mentionedFiles.end(), f ) == mentionedFiles.end() )
                    mentionedFiles.push_back( f );
                matchedFile = true;
            }
        }

        // (b) scoped-symbol match for 2-segment dotted mentions (Scope.name — `DTypeSchema.validate`):
        //     exact name + exact enclosing scope. Only when no file matched (a module path that resolved
        //     to a file should anchor the file, not every same-named method).
        if( !matchedFile && !m.isPath && m.segments.size() == 2 && directSymbols.size() < kMentionMaxDirectSymbols )
        {
            const std::string& scopeSeg = m.segments[0];
            const std::string& nameSeg  = m.segments[1];
            for( const Symbol& s : ing.symbols )
            {
                if( s.name == nameSeg && s.scope == scopeSeg )
                {
                    directSymbols.push_back( s.id );
                    if( directSymbols.size() >= kMentionMaxDirectSymbols ) break;
                }
            }
        }
    }
    if( mentionedFiles.empty() && directSymbols.empty() ) return false;

    // pass 2 — lift. Slot ladder: file i's symbols land at top*(1 - step*(i+1)); direct symbols land at
    // the first slot. max() keeps anything the ranker already scored higher exactly where it was.
    std::uint32_t liftedSymbolCount = 0;
    const auto lift = [ & ]( NodeId id, std::size_t slotIndex )
    {
        const float target = topScore * ( 1.0f - kMentionTopGapStep * float( slotIndex + 1 ) );
        if( lensRank[id] < target ) { lensRank[id] = target; ++liftedSymbolCount; }
    };

    std::sort( directSymbols.begin(), directSymbols.end() );
    directSymbols.erase( std::unique( directSymbols.begin(), directSymbols.end() ), directSymbols.end() );
    for( const NodeId id : directSymbols ) lift( id, 0 );

    for( std::size_t fi = 0; fi < mentionedFiles.size(); ++fi )
    {
        const std::uint32_t f = mentionedFiles[fi];

        // the file's top symbols by (current score desc, id asc) — a tiny insertion sort into a fixed array
        NodeId        best[ kMentionMaxSymbolsPerFile ];
        std::uint32_t bestCount = 0;
        for( const Symbol& s : ing.symbols )
        {
            if( s.fileId != f ) continue;
            std::uint32_t at = bestCount < kMentionMaxSymbolsPerFile ? bestCount : kMentionMaxSymbolsPerFile;
            while( at > 0 && ( lensRank[s.id] > lensRank[ best[at - 1] ] || ( lensRank[s.id] == lensRank[ best[at - 1] ] && s.id < best[at - 1] ) ) ) --at;
            if( at >= kMentionMaxSymbolsPerFile ) continue;
            for( std::uint32_t k = ( bestCount < kMentionMaxSymbolsPerFile ? bestCount : kMentionMaxSymbolsPerFile - 1 ); k > at; --k ) best[k] = best[k - 1];
            best[at] = s.id;
            if( bestCount < kMentionMaxSymbolsPerFile ) ++bestCount;
        }
        for( std::uint32_t k = 0; k < bestCount; ++k ) lift( best[k], fi );
    }

    if( liftedSymbolCount == 0 ) return false;
    if( outInfo )
    {
        outInfo->fileCount   = std::uint32_t( mentionedFiles.size() );
        outInfo->symbolCount = liftedSymbolCount;
    }
    return true;
}

// R5 — doc-mention surfacing: reuse g.mentions (the SAME doc<->code backtick edges the `--mentions=SYM`
// verb / mentionsJson MCP verb already expose; built OUT of the call graph in buildGraph so a doc naming a
// symbol never inflates that SYMBOL's own PageRank/blast-radius — that isolation is untouched here) as a
// --for ranking signal. Where B8 (applyMentionBoost, above) lifts a target the TASK TEXT literally names, this
// lifts a DOC that the RESOLVED symbol is already discussed by — closing the doc-localization gap: a design
// doc that explains `computeWidgetTotal` in prose sharing no words with the query should still surface once
// the query resolves onto `computeWidgetTotal` itself (recall.h's own lexical score cannot do this; it never
// sees which code symbol a query is "about", only the doc's own text).
//
// Contract (each pinned in test/docmentioncheck.sh):
//   * INERT WITHOUT MENTIONS — no top-ranked symbol has a g.mentions entry ⇒ lensRank untouched, byte-identical.
//   * NEVER OUTRANKS THE CODE IT DISCUSSES — a lifted doc's score is strictly BELOW the anchor symbol's OWN
//     score (kDocMentionDecay < 1); a doc cannot displace the code hit that earned it the lift, and an already
//     higher-scored slot (e.g. the doc's own strong lexical match) is never lowered.
//   * BOUNDED / DOWNWEIGHTED — only the top kDocMentionMaxAnchors current anchors are consulted (positive
//     scores only), at most kDocMentionMaxDocsPerAnchor docs lifted per anchor, at most kDocMentionMaxDocsTotal
//     overall — so a heavily-mentioned symbol cannot flood the bundle with doc rows ("docs must not swamp
//     code": the decay + the caps are the two levers).
//   * DETERMINISTIC — anchors chosen by (score desc, id asc) via partial_sort (the same tie-break every other
//     lens-ranking pass in this file uses); doc ids within an anchor are already sorted+deduped by buildGraph.
//   * ROUTE-AGNOSTIC — unlike B8 (routed path only), this runs identically whether or not --no-route is given:
//     "which doc explains the resolved symbol" does not depend on which BM25 mode picked that symbol.
inline constexpr std::size_t kDocMentionMaxAnchors       = 8;      // consult only the current top-N anchors
inline constexpr std::size_t kDocMentionMaxDocsPerAnchor = 2;      // strongest-anchor-first, capped per anchor
inline constexpr std::size_t kDocMentionMaxDocsTotal     = 6;      // global cap — bounds token cost regardless of fan-out
inline constexpr float       kDocMentionDecay            = 0.55f;  // doc lands at anchor_score * decay — below the code hit

struct DocMentionBoostInfo { std::uint32_t anchorCount = 0; std::uint32_t docCount = 0; };

inline bool applyDocMentionBoost( const Graph& g, std::vector<float>& lensRank, DocMentionBoostInfo* outInfo = nullptr )
{
    const std::size_t N = lensRank.size();
    VERIFY( g.mentions.empty() || g.mentions.size() == N );
    if( N == 0 || g.mentions.empty() ) return false;

    // top-kDocMentionMaxAnchors symbols by (current score desc, id asc) — the symbols THIS query, after every
    // prior boost (route/anchor/query-mention/co-change), actually resolved onto. Positive scores only, same
    // pattern as graph.h's anchoredLexicalRank anchor selection.
    std::vector<NodeId> order( N );
    for( NodeId i = 0; i < N; ++i ) order[i] = i;
    const std::size_t topN = std::min( kDocMentionMaxAnchors, N );
    std::partial_sort( order.begin(), order.begin() + topN, order.end(), [ & ]( NodeId a, NodeId b ) noexcept
    { return lensRank[a] != lensRank[b] ? lensRank[a] > lensRank[b] : a < b; } );

    std::uint32_t liftedDocs = 0, usedAnchors = 0;
    for( std::size_t k = 0; k < topN && liftedDocs < kDocMentionMaxDocsTotal; ++k )
    {
        const NodeId anchor = order[k];
        if( !( lensRank[anchor] > 0.0f ) ) break;                          // rest of `order` only gets worse
        if( anchor >= g.mentions.size() || g.mentions[anchor].empty() ) continue;

        const float   target    = lensRank[anchor] * kDocMentionDecay;
        std::size_t   perAnchor = 0;
        for( NodeId doc : g.mentions[anchor] )
        {
            if( perAnchor >= kDocMentionMaxDocsPerAnchor || liftedDocs >= kDocMentionMaxDocsTotal ) break;
            if( doc >= lensRank.size() ) continue;                        // defensive; buildGraph keeps these in-range
            if( lensRank[doc] < target )
            {
                lensRank[doc] = target;
                ++liftedDocs;
                ++perAnchor;
            }
        }
        if( perAnchor > 0 ) ++usedAnchors;
    }

    if( liftedDocs == 0 ) return false;
    if( outInfo ) { outInfo->anchorCount = usedAnchors; outInfo->docCount = liftedDocs; }
    return true;
}

// §A8.4: one row per FILE, not one per markdown SECTION — the mentions verbs' docs= used to count
// g.mentions' section NodeIds while the row itself printed only the enclosing FILE's path, so a doc split
// into several `## Section`s each mentioning SYM inflated docs= up to 3x over the number of distinct files
// a reader actually sees, with the same p= repeated across rows. Lives HERE (not in main.cpp) because the
// CLI --mentions and the MCP `mentions` verb share it — two collapses would be the §A4c clone class.
// V2-2: NO line field — g.mentions stores the doc FILE node (graph.h builds mentions[codeDef] += docFileNode),
// whose line is always 1, so an l= derived from it read as a locator while carrying zero information. Real
// mention lines live on the isDocLink references; plumbing them through is a recorded follow-up, not a fake attr.
struct MentionFileRow { std::uint32_t fileId; std::size_t mentions; };
inline std::vector<MentionFileRow> collapseMentionsToFileRows( const IngestResult& ing, const std::vector<NodeId>& docs )
{
    HashMap<std::uint32_t, std::size_t> rowOfFile;   // fileId -> index into fileRows
    std::vector<MentionFileRow>         fileRows;
    for( NodeId dn : docs )
    {
        const Symbol&    ds           = ing.symbols[dn];
        const auto [ it, wasInserted ] = rowOfFile.try_emplace( ds.fileId, fileRows.size() );
        if( wasInserted ) fileRows.push_back( { ds.fileId, 1 } );
        else
            ++fileRows[ it->second ].mentions;
    }
    std::sort( fileRows.begin(), fileRows.end(), [ & ]( const MentionFileRow& a, const MentionFileRow& b )
               { return ing.files[ a.fileId ] < ing.files[ b.fileId ]; } );
    return fileRows;
}

} // namespace rw

#pragma once

// tracelocus.h — the shared trace-to-locus bundle assembler behind --from-trace (CLI, L2) and the MCP
// from_trace verb (L4). tracein.h owns PURE frame extraction (no corpus
// knowledge); this header owns the CORPUS resolution (a frame's path → indexed fileId, then the frame's own
// NAME → a unique def, falling back to the frame's line → its enclosing symbol) and the bundle assembly (the
// <trace> map + suspects' signatures + the innermost in-corpus symbol's full body) — so main.cpp's
// runFromTrace() and mcpverbs.h's fromTraceText() share ONE implementation, never two hand-copies of the
// innermost-first ranking/serialization logic.
//
// §A2 — the two honesty contracts this file now keeps:
//   * NAME-FIRST resolution. A trace comes from a binary that may predate the checkout, so its line numbers
//     are the stale half of every frame; binding by line alone silently rebound `runDefaultMap` to whatever
//     squats on that line today. Each frame stamps resolved_by="name"|"line", and a name/line DISAGREEMENT is
//     disclosed (line_encloses=), never reconciled behind the reader's back.
//   * A CLOSING partition. in_corpus = suspects + merged + unresolved: every file-matched frame is visible in
//     exactly one bucket, so a frame can no longer be counted and then vanish from the document.
//
// Included BEFORE mcp.h in main.cpp so mcpverbs.h can reach fromTraceBundleText() — self-contained (its own
// #includes only) so include ORDER elsewhere in main.cpp never matters to it.

#include "model.h"
#include "graph.h"
#include "serialize.h"     // packSignatures / packBodies / escapeXml / kForPayloadBudgetBytes
#include "redact.h"
#include "tracein.h"        // table-driven stack-trace/sanitizer/compiler frame extraction (pure string work)
#include "infra/namesplit.h"      // stripTrailingGroup/stripTemplateArgs — shared with ingest.cpp's H4 re-split
#include "mention.h"        // mention_detail::pathSuffixMatches — the longest-suffix file match

#include <algorithm>
#include <cstdio>
#include <cstdint>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

inline constexpr std::uint32_t kNoTraceFile = UINT32_MAX;

// the indexed fileId a trace frame's path resolves to. A trace carries absolute / build-relative prefixes
// the repo-relative index never has, so the LONGEST path-suffix that matches any indexed file wins (the
// mention-anchor precedent, src/mention.h) — first ascending fileId on a tie. kNoTraceFile ⇒ out of corpus.
inline std::uint32_t traceMatchFile( const IngestResult& ing, std::string_view rawPath )
{
    // split the frame path into whole '/'-components (drop empties so a leading '/' or '//' is harmless)
    std::vector<std::string> segments;
    std::size_t p = 0;
    while( p < rawPath.size() )
    {
        while( p < rawPath.size() && rawPath[p] == '/' )
        {
            ++p;
        }
        const std::size_t s = p;
        while( p < rawPath.size() && rawPath[p] != '/' )
        {
            ++p;
        }
        if( p > s )
        {
            segments.emplace_back( rawPath.substr( s, p - s ) );
        }
    }
    if( segments.empty() )
    {
        return kNoTraceFile;
    }

    const std::uint32_t fileCount = std::uint32_t( ing.files.size() );
    for( std::size_t suffixLen = segments.size(); suffixLen >= 1; --suffixLen )
    {
        const std::vector<std::string> suffix( segments.end() - std::ptrdiff_t( suffixLen ), segments.end() );
        for( std::uint32_t f = 0; f < fileCount; ++f )
        {
            if( mention_detail::pathSuffixMatches( ing.files[f], suffix ) )
            {
                return f;
            }
        }
    }
    return kNoTraceFile;
}

// the innermost indexed symbol whose def span [line, line + loc - 1] contains `frameLine` in `fileId`.
// Deepest (largest start line) wins; ties break to the smaller span, then id asc. kNoNode ⇒ the frame hit
// file-scope code with no enclosing def (the file is still in-corpus; it just yields no ranked suspect).
inline NodeId traceEnclosingSymbol( const IngestResult& ing, std::uint32_t fileId, std::uint32_t frameLine )
{
    NodeId best = kNoNode;
    for( const Symbol& s : ing.symbols )
    {
        if( s.fileId != fileId || s.line == 0 || frameLine < s.line )
        {
            continue;
        }
        const std::uint32_t endLine = s.line + ( s.loc > 0 ? s.loc - 1 : 0 );
        if( frameLine > endLine )
        {
            continue;
        }
        if( best == kNoNode ) { best = s.id; continue; }

        const Symbol&       b    = ing.symbols[ best ];
        const std::uint32_t bEnd = b.line + ( b.loc > 0 ? b.loc - 1 : 0 );
        const bool deeper = s.line > b.line
            || ( s.line == b.line && ( endLine - s.line ) <  ( bEnd - b.line ) )
            || ( s.line == b.line && ( endLine - s.line ) == ( bEnd - b.line ) && s.id < b.id );
        if( deeper )
        {
            best = s.id;
        }
    }
    return best;
}

namespace tracelocus_detail
{

// how many progressively-less-qualified spellings of one frame name we are willing to probe (a bound, never a
// silent cap on results: the LADDER stops early on the first unique hit, and exhausting it just means the
// frame falls back to line-enclosure with resolved_by="line" stamped).
inline constexpr std::size_t kNameCandidateCap = 8;

// the balanced-trailing-group scanner now lives in the leaf header namesplit.h, because src/ingest.cpp needs
// the SAME scan for the H4 qualified-call re-split and cannot include this header (it pulls graph.h +
// serialize.h). These using-declarations keep every call site below — and every gate that rides them —
// spelled and behaving exactly as before; nothing but the definition's location changed.
using rw::namesplit::stripTrailingGroup;

// drop a trailing `(…)` parameter list AND any cv/ref/noexcept qualifiers after it, so a demangled C++ frame
// name reduces to the spelling the symbol table keys: `runDefaultMap(MainDispatch const&) const` ->
// `runDefaultMap`. Cutting to the LAST ')' first is what lets the shared scan see the group at the very end.
inline std::string_view stripCallSignature( std::string_view f ) noexcept
{
    const std::size_t closeIndex = f.rfind( ')' );
    if( closeIndex == std::string_view::npos )
    {
        return f;
    }

    const std::string_view upToClose = f.substr( 0, closeIndex + 1 );
    const std::string_view head      = stripTrailingGroup( upToClose, '(', ')' );
    return head.size() == upToClose.size() ? f : head;                // nothing stripped ⇒ keep the qualifiers too
}

// drop a trailing balanced `<…>` template-argument group: `make<Foo,Bar>` -> `make`. (Definition hoisted to
// namesplit.h alongside the scanner it wraps; the spelling here is unchanged.)
using rw::namesplit::stripTemplateArgs;

// the ordered name spellings to probe for one raw frame function name, most-qualified FIRST: the cleaned name,
// then every suffix after a `::` or `.` separator (C++ namespaces/classes, Python/JS module and method dots).
// Deterministic, deduped, bounded by kNameCandidateCap. An empty/absent frame name yields no candidates.
inline std::vector<std::string> nameCandidates( std::string_view rawFunc )
{
    const std::string_view clean = stripTemplateArgs( tracein::detail::trim( stripCallSignature( tracein::detail::trim( rawFunc ) ) ) );

    std::vector<std::string> candidates;
    const auto add = [ & ]( std::string_view c )
    {
        if( c.empty() || candidates.size() >= kNameCandidateCap )
        {
            return;
        }
        for( const std::string& have : candidates )
        {
            if( have == c )
            {
                return;
            }
        }
        candidates.emplace_back( c );
    };

    add( clean );
    for( std::size_t i = 0; i + 1 < clean.size(); ++i )
    {
        if( clean[i] == ':' && clean[i + 1] == ':' )
        {
            add( clean.substr( i + 2 ) );
        }
        else if( clean[i] == '.' )
        {
            add( clean.substr( i + 1 ) );
        }
    }
    return candidates;
}

} // namespace tracelocus_detail

// §A2a: the indexed definition the frame's OWN function name denotes, or kNoNode when the name is absent,
// unknown here, or ambiguous. This is the primary resolver: a trace comes from a binary that may predate the
// checkout, so its line numbers are the stale half of the frame and its name is the stable half. Ambiguity is
// broken ONLY by the frame's own (already file-matched) fileId — one same-named def in that file wins; two do
// not, and the frame degrades to line-enclosure rather than guessing an overload.
inline NodeId traceResolveByName( const IngestResult& ing, std::string_view rawFunc, std::uint32_t fileId )
{
    for( const std::string& candidate : tracelocus_detail::nameCandidates( rawFunc ) )
    {
        const std::vector<NodeId> defs = resolveAllByName( ing, candidate );
        if( defs.size() == 1 )
        {
            return defs[0];
        }
        if( defs.size() < 2 )
        {
            continue;
        }

        NodeId      sameFileId    = kNoNode;
        std::size_t sameFileCount = 0;
        for( const NodeId d : defs )
        {
            if( ing.symbols[d].fileId == fileId )
            {
                sameFileId = d;
                ++sameFileCount;
            }
        }
        if( sameFileCount == 1 )
        {
            return sameFileId;
        }
    }
    return kNoNode;
}

// one ranked in-corpus suspect. `frame` is the TRACE's own locator (path verbatim, its own line) — it is a
// trace report, so p= stays the frame's coordinates and the DEFINITION site travels in <sigs> l=.
// `lineEnclosesId` is set only when the two resolvers DISAGREE (name says X, today's line sits in Y): the tell
// that the trace predates this checkout, disclosed rather than silently reconciled.
struct TraceSuspect
{
    const tracein::ParsedFrame* frame            = nullptr;
    NodeId                      symbolId         = kNoNode;
    NodeId                      lineEnclosesId   = kNoNode;
    bool                        isResolvedByName = false;
};

// §A2b: the WHOLE partition of one trace's parsed frames — every frame lands in exactly one bucket, and the
// counters close: in_corpus = suspects + merged + unresolved. `skipped` is the out-of-every-root bucket
// (listed, never ranked); `unresolved` is the third bucket that used to vanish — file indexed, but no symbol
// found by either resolver (a line in a doc-comment gap / file-scope code, with no usable name).
struct TracePartition
{
    std::vector<TraceSuspect>                suspects;
    std::vector<const tracein::ParsedFrame*> skipped;
    std::vector<const tracein::ParsedFrame*> unresolved;
    std::size_t                              parsedCount   = 0;
    std::uint32_t                            inCorpusCount = 0;
    std::uint32_t                            mergedCount   = 0;    // frames folded into an already-claimed symbol
    // §B10: the OUTER denominator — frame-shaped INPUT LINES (tracein::FrameScan), of which parsedCount were
    // extractable. Set by the caller, which is the only place that still holds the raw text. Everything else
    // in this struct partitions parsedCount; this is the one number that says how big parsedCount's own
    // universe was, so a dropped frame (a dyld line with no source location) stops being invisible.
    std::size_t                              frameLinesSeen = 0;
};

// bucket every frame of an ALREADY innermost-first-sorted `frames` (whose storage must outlive the result —
// the buckets hold pointers into it). Name-first resolution per §A2a, line-enclosure fallback, dedup by
// resolved symbol so a recursive/looping trace ranks each symbol once and COUNTS the folds.
inline TracePartition partitionTraceFrames( const IngestResult& ing, const std::vector<tracein::ParsedFrame>& frames )
{
    TracePartition    part;
    std::vector<char> seenSym( ing.symbols.size(), 0 );
    part.parsedCount = frames.size();

    for( const tracein::ParsedFrame& fr : frames )
    {
        if( fr.lineOverflowed ) { part.skipped.push_back( &fr ); continue; }
        const std::uint32_t fileId = traceMatchFile( ing, fr.path );
        if( fileId == kNoTraceFile ) { part.skipped.push_back( &fr ); continue; }
        ++part.inCorpusCount;

        // name first (the stable half of a frame), line-enclosure second (the half a stale binary invalidates)
        const NodeId byName = traceResolveByName( ing, fr.func, fileId );
        const NodeId byLine = traceEnclosingSymbol( ing, fileId, fr.line );
        const NodeId chosen = byName != kNoNode ? byName : byLine;
        if( chosen == kNoNode ) { part.unresolved.push_back( &fr ); continue; }
        if( seenSym[ chosen ] ) { ++part.mergedCount; continue; }
        seenSym[ chosen ] = 1;

        TraceSuspect sus;
        sus.frame            = &fr;
        sus.symbolId         = chosen;
        sus.isResolvedByName = byName != kNoNode;
        if( byName != kNoNode && byLine != kNoNode && byLine != byName )
        {
            sus.lineEnclosesId = byLine;
        }
        part.suspects.push_back( sus );
    }

    VERIFY( part.inCorpusCount == part.suspects.size() + part.mergedCount + part.unresolved.size() );
    return part;
}

// render the <trace> block (the ranked suspect map + the two listed-but-unranked buckets) to a string, so
// the caller can subtract its exact byte cost from the sigs budget. Built through open_memstream so no
// attribute is ever truncated regardless of path length (F6: a fixed-size row buffer truncated long
// sanitizer paths mid-attribute, dropping the closing `"/>` and breaking G4).
inline std::string renderTraceBlock( const IngestResult& ing, tracein::FrameFormat dominant, std::string_view srcNote,
                                     const TracePartition& part )
{
    std::vector<char> esc;
    const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };

    char*       buf = nullptr;
    std::size_t sz  = 0;
    std::FILE*  m   = open_memstream( &buf, &sz );
    if( !m )
    {
        DEGRADED_PATH_ALERT( "renderTraceBlock: open_memstream failed — trace block omitted" );
        return {};
    }
    std::fprintf( m, "<trace src=\"%s\" format=\"%s\" frame_lines=\"%zu\" parsed=\"%zu\" in_corpus=\"%u\" skipped=\"%zu\" merged=\"%u\" unresolved=\"%zu\" suspects=\"%zu\">",
        ex( srcNote ).c_str(), tracein::formatSpec( dominant ).label, part.frameLinesSeen, part.parsedCount, part.inCorpusCount,
        part.skipped.size(), part.mergedCount, part.unresolved.size(), part.suspects.size() );
    for( std::size_t i = 0; i < part.suspects.size(); ++i )
    {
        const TraceSuspect& sus = part.suspects[i];
        const Symbol&       s   = ing.symbols[ sus.symbolId ];

        // the name/line disagreement, disclosed inline: today's line sits in a DIFFERENT def than the frame names
        std::string encloses;
        if( sus.lineEnclosesId != kNoNode )
        {
            encloses = " line_encloses=\"" + ex( ing.symbols[ sus.lineEnclosesId ].name ) + "\"";
        }

        std::fprintf( m, "<frame rank=\"%zu\" n=\"%s\" t=\"%s\" p=\"%s:%u\" resolved_by=\"%s\"%s%s/>",
            i + 1, ex( s.name ).c_str(), symTag( s.kind ), ex( sus.frame->path ).c_str(), sus.frame->line,
            sus.isResolvedByName ? "name" : "line", encloses.c_str(), i == 0 ? " innermost=\"1\"" : "" );
    }
    for( const tracein::ParsedFrame* ur : part.unresolved )
    {
        std::string named;
        if( !ur->func.empty() )
        {
            named = " n=\"" + ex( ur->func ) + "\"";
        }
        std::fprintf( m, "<unresolved p=\"%s:%u\"%s/>", ex( ur->path ).c_str(), ur->line, named.c_str() );
    }
    for( const tracein::ParsedFrame* sk : part.skipped )
    {
        std::fprintf( m, "<skipped p=\"%s\" line=\"%u\"/>", ex( sk->path ).c_str(), sk->line );
    }
    std::fprintf( m, "</trace>" );
    std::fflush( m );  std::fclose( m );
    std::string out;
    if( buf ) { out.assign( buf, sz );  std::free( buf ); }
    return out;
}

// optional Q3/redaction/notes inputs, same graceful-degrade contract as packtask.h's PackTaskInputs — every
// field defaults to "not available" (attribute simply omitted downstream).
struct FromTraceInputs
{
    std::size_t                        bundleBudgetBytes    = kForPayloadBudgetBytes;   // overall <ctx> budget; caller resolves --token-budget/budget_tokens into bytes
    std::size_t                        sigLadderBudgetBytes = 0;                        // packSignatures per-doc ladder (0 = unlimited)
    std::size_t                        bodyBudgetBytes      = 0;                        // packBodies budget for the rank-1 full body (0 = unlimited)
    bool                                compress             = false;
    const std::vector<std::uint32_t>*  fanIn  = nullptr;
    const std::vector<char>*           impure = nullptr;
    const std::vector<std::uint8_t>*   tested = nullptr;
    const std::vector<std::uint32_t>*  amp    = nullptr;
    // §B10.1 — R14's UNNAMED TWIN, named here. R14 records `PackTaskInputs::redact = nullptr` as the residual
    // W3-N1's "REQUIRED redact, no default" discipline could not reach; this field is the identical shape in
    // the identical position and was never listed beside it. Both keep the default DELIBERATELY: an aggregate
    // whose whole contract is "every field defaults to not-available, each degrades gracefully" cannot make
    // ONE field required — dropping the initialiser on a POD member does not force a caller to spell it, it
    // makes `FromTraceInputs in;` leave it INDETERMINATE, which is strictly worse than nullptr. The
    // CalleeCallsSink shape (no defaults on ANY member, so the aggregate must be spelled in full) is the
    // pattern that does work, and converting these two to it is a separate change with a real call-site cost.
    // Until then the net is held by test/fixedbufsweep.sh's population sweep, not by the compiler.
    RedactCounts*                      redact = nullptr;
    const notes::NoteIndex*            notes  = nullptr;
};

struct FromTraceResult
{
    bool        ok         = false;   // false = zero parseable frames — caller refuses loudly, xml is empty
    std::size_t frameCount = 0;
    std::size_t inCorpus   = 0;
    std::string xml;                  // the <ctx>…</ctx> bundle; only meaningful when ok
};

// extracts frames (tracein.h, table-driven), ranks the enclosing symbols INNERMOST-first over in-corpus
// frames ONLY (out-of-corpus frames are listed + counted, never ranked — no silent caps), and returns a
// --for-style bundle: the <trace> map, the suspects' signatures, and the innermost in-corpus symbol's FULL
// body. `srcNote` is the trace's human-readable source label (a filename, "<stdin>", or an MCP caller's own
// label) — "--" runs are collapsed here so it stays legal inside the emitted XML comment (G4).
inline FromTraceResult fromTraceBundleText( const IngestResult& ing, const Graph& g, const std::string& text,
                                            std::string_view srcNoteIn, const FromTraceInputs& inArg )
{
    FromTraceResult res;

    // P2.4: --from-trace emitted in="0" on every row while --for reported the truth for the SAME symbol —
    // it told the reader "nobody calls this" about the frame it had just ranked. packSignatures now omits
    // in= when no vector is supplied, so silence was already honest; supplying the real thing is better, and
    // it is free (one O(symbols) pass over the in-edge CSR that is already built).
    std::vector<std::uint32_t> localFanIn;
    FromTraceInputs            in = inArg;
    if( !in.fanIn )
    {
        localFanIn = fanInFromInEdges( ing, g );
        if( !localFanIn.empty() )
        {
            in.fanIn = &localFanIn;
        }
    }

    tracein::FrameScan                scan   = tracein::extractFrames( text );
    std::vector<tracein::ParsedFrame>& frames = scan.frames;
    if( frames.empty() )
    {
        return res; // ok=false — nothing parseable
    }

    const tracein::FrameFormat dominant   = tracein::dominantFormat( frames );
    const std::size_t          frameCount = frames.size();
    std::stable_sort( frames.begin(), frames.end(), [ & ]( const tracein::ParsedFrame& a, const tracein::ParsedFrame& b )
    {
        return tracein::innermostKey( a, dominant, frameCount ) < tracein::innermostKey( b, dominant, frameCount );
    } );

    TracePartition part = partitionTraceFrames( ing, frames );
    part.frameLinesSeen = scan.frameShapedLines;   // §B10: the outer denominator, from the only scope holding the raw text

    std::vector<float> rank( ing.symbols.size(), 0.0f );
    for( std::size_t i = 0; i < part.suspects.size(); ++i )
    {
        rank[part.suspects[i].symbolId] = float( part.suspects.size() - i );
    }

    // W3FIX M3: srcNote is a FILENAME (or an MCP caller's own label), and a filename may legally contain a
    // newline on this platform — `--from-trace=$'…/tr\nace.txt'` put a raw newline both in this comment and in
    // <trace src=…>, two G4 breaches out of one byte. xmlCommentText is the shared comment scrub (dash collapse
    // + control bytes + invalid UTF-8); the attribute half is escapeXml's character references (M2).
    const std::string srcNote = xmlCommentText( srcNoteIn );

    const std::size_t bundleBudget = in.bundleBudgetBytes > 0 ? in.bundleBudgetBytes : kForPayloadBudgetBytes;

    // CA4 §B3 — the budget ledger + the ceiling ladder, the third member of the family cli.h enumerates BY
    // NAME ("--for / --pack-task / --from-trace"). This lens STATED a budget and never labelled an overrun:
    // when the header floor exceeds it, `sigsBudget` clamps to 1 and the whole bundle is emitted anyway —
    // measured on base_w3 at --token-budget=50: 4 833 B against a 135 B allowance (35.8x) with zero
    // over_ceiling, while --pack-task printed its ledger and --for and --recall both labelled themselves.
    // Verbatim the W3FIX-H2 mechanism. THE HEADER IS NOW A BUILDER for exactly the reason the two siblings
    // are: the ladder must be able to PRICE a shape before choosing it, and a header built once cannot be.
    //
    // Rungs, cheapest information loss first (climbCeilingLadder owns the order):
    //   (a) as built;
    //   (b) the comment's src echo dropped — a byte-for-byte DUPLICATE, since ctxRootOpen's task= attribute
    //       above still carries the verbatim copy;
    //   (c) skipped: this lens has no route= attribute (hasRouteAttr=false), so rung (c) is not available;
    //   (d) over_ceiling — the complete bundle plus an honest label, never a mutilated bundle.
    const auto buildTraceHeader = [ & ]( bool withSrcEcho, std::string_view extraNotes ) -> std::string
    {
        // §B1.7 root attrs: the trace SOURCE is this lens's request text — the same slot --for/--pack-task put
        // the user's query in — so it is machine-readable and VERBATIM (escapeXml + M2 character references),
        // beside the lossy readable echo in the comment. This lens emitted a bare `<ctx>` and had neither.
        std::string h = ctxRootOpen( srcNoteIn, {} );
        h += "<!-- ripwire trace-to-locus for ";
        if( withSrcEcho ) { h += "\"";  h += srcNote;  h += "\""; }
        else
        {
            h += "[src_echo: dropped (ceiling) - the verbatim copy is the task= attribute above]";
        }
        h += ": frames of a ";
        h += tracein::formatSpec( dominant ).label;
        h += " trace mapped onto indexed symbols, ranked INNERMOST-first. ";
        h += "frame_lines=";  h += std::to_string( part.frameLinesSeen );
        h += " parsed=";      h += std::to_string( part.parsedCount );
        h += " in_corpus=";   h += std::to_string( part.inCorpusCount );
        h += " skipped=";     h += std::to_string( part.skipped.size() );
        h += " (out of every root - listed, never ranked) merged=";
        h += std::to_string( part.mergedCount );
        h += " unresolved=";  h += std::to_string( part.unresolved.size() );
        h += ". ";

        // §A2b/§A2c legend: the closing arithmetic, HOW each frame bound, and which line convention p= carries
        // §B10: the OUTER denominator, stated before the inner partition — parsed= was previously the largest
        // number in the report, so a frame-shaped line no format shape could read (a dyld frame with no source
        // location) simply lowered parsed= and left no trace of itself anywhere.
        h += "frame_lines = frame-shaped lines the INPUT presented (a #N marker, a leading \"at \", or a Python File \"...\" "
             "line, plus every line that did extract); parsed = how many of them yielded a usable path:line, so "
             "frame_lines - parsed is the count that matched no format shape and enters no bucket below. ";
        h += "in_corpus = suspects + merged + unresolved, so every file-matched frame is visible: merged= folded into an "
             "already-claimed symbol, unresolved= listed as <unresolved> (indexed file, no def by name or by line). ";
        h += "resolved_by=\"name\" means the frame's OWN function name bound to a unique def (line_encloses=, when present, "
             "names the different symbol today's line sits in: the tell that the trace predates this checkout); "
             "resolved_by=\"line\" means the name was absent, unknown or ambiguous, so the def enclosing that line was used. ";
        h += "p= on a frame is the FRAME's own locator (the trace's path:line, verbatim); definition sites live in <sigs> l=. ";
        // §B7.5 (CA4): the <sigs> rows this verb emits carry the same ranking-row vocabulary --pack-task
        // spells out, and this legend defined only the frame half — a reader met cx=/ccx=/in= on the
        // signature rows with nothing to read them against, the identical gap on the identical rows.
        h += "On a <sigs> row: n=name, id=canonical(when scoped), t=kind, cx=cyclomatic complexity, "
             "ccx=cognitive complexity, in=reuse-count (absent = not measured, never a false 0). ";
        h += "rank 1 = the innermost in-corpus frame; its FULL body follows, other suspects as signatures. ";
        // §B3 the BUDGET LEDGER, the fact this bundle never stated. The two numbers are the working budget the
        // caller resolved (--token-budget x kMinBytesPerToken x kBudgetHeadroom, or the default) and the bar
        // this lens is JUDGED against — the same single-entry overshoot tolerance --for and --pack-task use,
        // re-expressed against a post-headroom byte budget (serialize.h ceilingAllowanceFromBudgetBytes).
        h += "budget=";  h += std::to_string( bundleBudget );
        h += " bytes (allowance ";  h += std::to_string( ceilingAllowanceFromBudgetBytes( bundleBudget ) );
        h += " bytes = ceiling + the single-entry overshoot a whole first signature costs).";
        h += extraNotes;
        h += " -->";
        return h;
    };

    std::string       headerStr = buildTraceHeader( /*withSrcEcho=*/true, {} );
    const std::string traceStr  = renderTraceBlock( ing, dominant, srcNote, part );

    const std::size_t fixedBytes   = headerStr.size() + traceStr.size() + 6;   // + "</ctx>"
    const std::size_t sigsBudget   = bundleBudget > fixedBytes ? bundleBudget - fixedBytes : 1;

    std::string whole;
    whole += headerStr;
    whole += traceStr;
    if( !part.suspects.empty() )
    {
        char*       buf = nullptr;  std::size_t sz = 0;
        std::FILE*  m   = open_memstream( &buf, &sz );
        if( m )
        {
            packSignatures( m, ing, rank, int( part.suspects.size() ), in.sigLadderBudgetBytes, /*metrics=*/true,
                            in.fanIn, in.impure, in.redact,
                            nullptr, nullptr, in.tested, in.amp,     // Q3: tested/amp folded on; churn/clone omitted (no git walk here)
                            /*rankAdaptivePayload=*/true, sigsBudget,
                            in.notes );                              // L3: field-notes surfacing (inert when null)

            const std::vector<NodeId> bodyIds{ part.suspects[0].symbolId };
            packBodies( m, ing, bodyIds, in.bodyBudgetBytes, g.outOff, g.outTargets, in.compress, in.redact,
                        /*ranges=*/nullptr, in.notes );               // L3: the rank-1 body surfaces notes too
            std::fflush( m );  std::fclose( m );
            if( buf ) { whole.append( buf, sz );  std::free( buf ); }
        }
        else
        {
            DEGRADED_PATH_ALERT( "from-trace: open_memstream failed — signature/body section skipped" );
        }
    }
    whole += "</ctx>";

    // §B3 — climb the ladder over the ASSEMBLED document. Priced after assembly (like both siblings) because
    // the bar is the delivered bytes, not an estimate; the payload was rendered against the pre-ladder
    // `fixedBytes`, so a shortened header only ever leaves the bundle further UNDER its allowance — never over.
    {
        static constexpr CeilingLadderNotes kNotes{
            " [src_echo: dropped (ceiling)]",
            " [src_echo: dropped (ceiling)]",   // no route= attribute on this lens: hasRouteAttr=false ⇒ rung (c) is never taken
            " [over_ceiling: the header floor (verbatim src echo + fixed legend) plus the innermost frame's whole"
            " signature exceeds this budget - the bundle is complete and larger than the ceiling, not trimmed]" };
        const std::string chosen = climbCeilingLadder( [ & ]( bool, bool withSrcEcho, std::string_view extra )
                                                       { return buildTraceHeader( withSrcEcho, extra ); },
                                                       headerStr, whole.size() - headerStr.size(),
                                                       ceilingAllowanceFromBudgetBytes( bundleBudget ),
                                                       /*hasRouteAttr=*/false, kNotes );
        if( chosen != headerStr )
        {
            whole.replace( 0, headerStr.size(), chosen );
        }
    }

    res.ok         = true;
    res.frameCount = part.parsedCount;
    res.inCorpus   = part.inCorpusCount;
    res.xml        = std::move( whole );
    return res;
}

}   // namespace rw

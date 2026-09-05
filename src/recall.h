#pragma once

// recall.h — `--recall=TASK` / MCP `memory_recall`: retrieve the most RELEVANT documents (agent-memory
// notes, design docs) for a task and emit their FULL bodies, token-budgeted. Where `--for` returns the
// SIGNATURES of relevant code, recall returns whole prose facts — so the agent reads the handful of notes
// that matter instead of carrying the entire corpus (the per-session token win). Ranking is the same
// deterministic lexical (BM25) signal that the eval proved best for relatedness; a file is scored by the
// best score of any symbol it holds (the markdown file-node, which indexes the whole body, dominates). The
// graph half ([[links]]/PageRank) is intentionally NOT fused — the eval showed importance ≠ relatedness.

#include "docparse.h"    // §P2b: the generated-document signals (marker / size+fences) + the ONE markdown
                         //       fence scanner — a doc-side property, computed from the file's own bytes
#include "layout.h"      // §L4.3: layout::lineOf — the ONE byte-offset-to-line-number helper (reused, not
                         //        re-derived, for the `lines="LO-HI"` section anchor below)
#include "lexical.h"     // lexicalScores — the recall lens's scorer. Included HERE so recallFor below can be
                         //        the ONE call both front doors make, arguments and all (see recallFor).
#include "model.h"
#include "redact.h"      // redact secrets from recalled doc bodies (incl. extracted docText)
#include "serialize.h"   // §P2: kMinBytesPerToken / kBudgetHeadroom / bytesPerTokenFor / truncateUtf8WithEllipsis
                         //      — recall budgets and estimates with the SAME calibration as the map family

#include <algorithm>
#include <cstdio>
#include <cstdint>
#include <fstream>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

struct Recalled { std::uint32_t fileId; float score; docparse::GeneratedDocReason generated; };

// §P2b — the corpus-level facts the generated-doc de-prioritization needs: which doc files are GENERATED
// artifacts (and on what evidence), plus the median doc size those verdicts were measured against. One
// pass over the doc corpus per recall; the verdict is a per-FILE property, so it is computed once here
// rather than re-derived at every comparison.
//
// SCOPE: doc side only. The code-symbol rankers in lexical.h are untouched — a generated doc loses rank in
// `--recall`'s file ordering, and nowhere else (§P4's ranking half is a separate lane).
struct GeneratedDocVerdicts
{
    std::vector<std::uint8_t> reasonOf;       // fileId → docparse::GeneratedDocReason (None for non-docs)
    std::size_t               docCount    = 0;   // documents the median was taken over
    std::size_t               medianBytes = 0;   // the corpus median (0 ⇒ the size arm was not applicable)
};

// How much of a document the marker arm needs: its first kGeneratedMarkerHeadLines lines fit far inside
// this, and a document that clears the size line is read whole anyway.
inline constexpr std::size_t kGeneratedHeadScanBytes = 4096;

// Read at most `maxBytes` of a file (0 = all of it), preferring the EXTRACTED text of a document file over
// its raw bytes — a notebook's generated-ness is a property of its prose, not of its JSON envelope, the
// same override loadRecallBody applies. Returns false when the file cannot be read (degrade: unreadable
// files are simply never demoted).
inline bool readDocPrefix( const IngestResult& ing, std::uint32_t fileId, std::size_t maxBytes, std::string& out )
{
    if( const auto it = ing.docText.find( fileId ); it != ing.docText.end() )
    {
        out = ( maxBytes && it->second.size() > maxBytes ) ? it->second.substr( 0, maxBytes ) : it->second;
        return true;
    }
    std::ifstream in( diskPath( ing, fileId ), std::ios::binary );
    if( !in )
    {
        return false;
    }
    if( maxBytes == 0 ) { std::ostringstream ss;  ss << in.rdbuf();  out = ss.str();  return true; }
    out.assign( maxBytes, '\0' );
    in.read( out.data(), std::streamsize( maxBytes ) );
    out.resize( std::size_t( in.gcount() ) );
    return true;
}

// A doc file's size in bytes without reading it (the extracted text's size when there is one). 0 when the
// file cannot be sized — such a file takes no part in the median and is never demoted by the size arm.
inline std::size_t docByteSize( const IngestResult& ing, std::uint32_t fileId )
{
    if( const auto it = ing.docText.find( fileId ); it != ing.docText.end() )
    {
        return it->second.size();
    }
    std::ifstream in( diskPath( ing, fileId ), std::ios::binary | std::ios::ate );
    if( !in )
    {
        return 0;
    }
    const std::streampos end = in.tellg();
    return ( end > 0 ) ? std::size_t( end ) : 0;
}

// fileId → is this a DOCUMENT file? The recall lens's corpus, in one place: the ranking restricts to it and
// the generated-doc classification measures within it, so they cannot disagree.
//
// §B9.2 — the predicate is "the index carries at least one Markdown-LANG symbol from this file", which is
// deliberately WIDER than "the path ends in .md": docparse.h ingests notebooks, exported HTML and CSV as
// Markdown-lang documents, so --recall reaches them too (that is what docparse exists for). --doc-drift's
// docs= counts a DIFFERENT population — isMarkdownPath, an EXTENSION test — and the two were both narrated
// to the reader as "docs" while already standing 4 apart on this repo, a gap that widens every time
// docparse learns a format. Neither predicate is wrong for its own verb (doc-drift scans for ANCHORS, and a
// rendered HTML report must not vouch for a name), so what is fixed is the NAMING: this population is
// reported as "document files" wherever it is shown, and "docs" is now doc-drift's word alone.
inline std::vector<char> docFileMask( const IngestResult& ing )
{
    std::vector<char> isDoc( ing.files.size(), 0 );
    for( const Symbol& s : ing.symbols )
    {
        if( s.lang == Lang::Markdown && s.fileId < isDoc.size() )
        {
            isDoc[s.fileId] = 1;
        }
    }
    return isDoc;
}

// Classify every doc file in the corpus. Two passes, because the size arm is RELATIVE: sizes first (a seek,
// no read), then the evidence scan. Only a document large enough to clear the size line is read in full —
// everything else needs just its head, which is all the marker arm looks at (and the size arm short-
// circuits on bytes before it would consult the fence density, so a head-only text cannot mis-classify).
inline GeneratedDocVerdicts classifyGeneratedDocs( const IngestResult& ing, const std::vector<char>& isDoc )
{
    GeneratedDocVerdicts verdicts;
    verdicts.reasonOf.assign( ing.files.size(), std::uint8_t( docparse::GeneratedDocReason::None ) );

    std::vector<std::size_t> byteSizes( ing.files.size(), 0 );
    std::vector<std::size_t> sizeSamples;
    sizeSamples.reserve( ing.files.size() );
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        if( f >= isDoc.size() || !isDoc[f] )
        {
            continue;
        }
        byteSizes[f] = docByteSize( ing, f );
        if( byteSizes[f] > 0 )
        {
            sizeSamples.push_back( byteSizes[f] );
        }
    }
    verdicts.docCount = sizeSamples.size();
    if( !sizeSamples.empty() )
    {
        std::sort( sizeSamples.begin(), sizeSamples.end() );
        verdicts.medianBytes = sizeSamples[ sizeSamples.size() / 2 ];   // upper median — deterministic, no averaging
    }

    const std::size_t sizeArmBytes = ( verdicts.medianBytes > 0 )
                                     ? std::size_t( docparse::kGeneratedSizeRatio * double( verdicts.medianBytes ) ) : 0;
    std::string       text;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        if( f >= isDoc.size() || !isDoc[f] || byteSizes[f] == 0 )
        {
            continue;
        }
        const bool        couldClearSizeArm = sizeArmBytes > 0 && byteSizes[f] >= sizeArmBytes;
        const std::size_t readBytes         = couldClearSizeArm ? 0 : kGeneratedHeadScanBytes;   // 0 = whole file
        if( !readDocPrefix( ing, f, readBytes, text ) )
        {
            continue;
        }
        verdicts.reasonOf[f] = std::uint8_t( docparse::classifyGeneratedDoc( text, byteSizes[f],
                                                                             verdicts.medianBytes, verdicts.docCount ) );
    }
    return verdicts;
}

// Rank files by the max lexical score of any symbol they contain (the whole-file node usually wins).
// Top-k files with score > 0, best-first; deterministic (score desc, then path asc for ties).
//
// §P2b — GENERATED documents rank LAST. The order is (not-generated, score desc, path asc): a generated
// artifact loses to every hand-written doc that matches at all, exactly as --exemplar's INVARIANT 2 makes
// a fixture lose to real code — a HEAVY PENALTY expressed as a primary sort key, never a filter. A doc
// nothing competes with is still returned, still ranked #1, and always says why it was demoted.
//
// `demotedMatchCount` counts every doc the query MATCHED that was de-prioritized — counted before the
// top-k cut, because a generated doc pushed out of the top k is precisely the case the reader must be
// told about (the header tally). Returned beside the selection rather than recovered from it.
struct RecallSelection
{
    std::vector<Recalled> files;
    std::size_t           demotedMatchCount = 0;
    std::size_t           docCount          = 0;   // §A8.2: the corpus this selection actually ran over —
                                                    // docFileMask()'s population when docsOnly (the DOCUMENT
                                                    // files --recall ranks), else the whole file corpus.
    std::size_t           matchedCount      = 0;   // §B2: the TRUE relevant count — files.size() BEFORE the
                                                    // --top-k cut below. This is what "K relevant of N docs"
                                                    // and total= must report; files.size() AFTER the cut is
                                                    // an emission cap, not a fact about how many matched.
};

// The recall order itself, named so the ranking rule reads as one sentence at its only call site.
inline bool recallOrderLess( const Recalled& a, const Recalled& b, const IngestResult& ing ) noexcept
{
    const bool aGen = a.generated != docparse::GeneratedDocReason::None;
    const bool bGen = b.generated != docparse::GeneratedDocReason::None;
    if( aGen != bGen )
    {
        return !aGen; // hand-written beats generated (the primary key)
    }
    if( a.score != b.score )
    {
        return a.score > b.score;
    }
    return ing.files[ a.fileId ] < ing.files[ b.fileId ];   // deterministic tiebreak
}

inline RecallSelection recallTopFiles( const IngestResult& ing, const std::vector<float>& scores, int k, bool docsOnly )
{
    // docsOnly: restrict to DOCUMENT files (docFileMask, above) — recall = "what I already KNOW" (notes / plans /
    // designs), not code (that's --for / --grep). Over a mixed code+docs tree this keeps code files from
    // swamping the docs (which the lexical scorer down-weights ×0.30 anyway). The generated-doc verdicts are
    // taken over that same doc corpus, and only there: a caller ranking code gets the untouched ordering.
    const std::vector<char>    isDoc    = docFileMask( ing );
    const GeneratedDocVerdicts verdicts = docsOnly ? classifyGeneratedDocs( ing, isDoc ) : GeneratedDocVerdicts{};

    std::vector<float> best( ing.files.size(), 0.f );
    for( std::size_t i = 0; i < ing.symbols.size() && i < scores.size(); ++i )
    {
        const std::uint32_t f = ing.symbols[i].fileId;
        if( docsOnly && f < isDoc.size() && !isDoc[f] )
        {
            continue;
        }
        if( f < best.size() && scores[i] > best[f] )
        {
            best[f] = scores[i];
        }
    }
    RecallSelection selection;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        if( best[f] <= 0.f )
        {
            continue;
        }
        const auto reason = ( f < verdicts.reasonOf.size() ) ? docparse::GeneratedDocReason( verdicts.reasonOf[f] )
                                                             : docparse::GeneratedDocReason::None;
        if( reason != docparse::GeneratedDocReason::None )
        {
            ++selection.demotedMatchCount;
        }
        selection.files.push_back( { f, best[f], reason } );
    }
    std::sort( selection.files.begin(), selection.files.end(),
               [ & ]( const Recalled& a, const Recalled& b ) noexcept { return recallOrderLess( a, b, ing ); } );
    selection.matchedCount = selection.files.size();   // §B2: TRUE count, taken BEFORE the --top-k cut
    if( k > 0 && int( selection.files.size() ) > k )
    {
        selection.files.resize( std::size_t( k ) );
    }
    // §A8.2/§B9.2: docFileMask()'s population when docsOnly (the DOCUMENT files --recall actually ranks), else
    // the whole file corpus — see the comment above isDoc for why docsOnly is the honest denominator.
    selection.docCount = docsOnly ? std::size_t( std::count( isDoc.begin(), isDoc.end(), char( 1 ) ) )
                                  : ing.files.size();
    return selection;
}

// §P2 — the honest SHAPE of one recall bundle: what the ranking selected vs what the budget let through,
// plus the calibrated token estimate over the WHOLE emitted artifact (header included, §P9.3). Every field
// is reported in the bundle's own header line, so a cut is never silent and the fit is checkable.
struct RecallShape
{
    std::size_t docCount       = 0;       // corpus the selection ran over (files.size())
    std::size_t matchedCount   = 0;       // §B2: TRUE relevant count (score > 0), BEFORE the --top-k cut —
                                          // this is what the prose numerator and total= report
    std::size_t selectedCount  = 0;       // docs the ranking actually selected to load (top-k cut applied,
                                          // budget cut not yet applied) — internal bookkeeping for the
                                          // capped-note attribution, not itself part of the header
    std::size_t shownCount     = 0;       // docs actually emitted
    std::size_t truncatedCount = 0;       // emitted docs whose body was CUT to fit the budget
    std::size_t demotedCount   = 0;       // §P2b: MATCHING docs de-prioritized as generated artifacts
    std::size_t bytes          = 0;       // total emitted bytes (header + bodies + markers)
    std::size_t estTokens      = 0;       // calibrated estimate over those bytes
    bool        isCapped       = false;   // shownCount < matchedCount || truncatedCount > 0
    bool        isOverCeiling  = false;   // W3FIX M1: the finished artifact exceeds the --max-tokens byte budget
                                          // it was shaped against — only reachable when the header floor alone
                                          // (kRecallHeaderReserveBytes + the verbatim task echo) is over it.
    std::size_t maxTokens      = 0;       // H9: the ceiling ACTUALLY APPLIED, in tokens (0 = unbounded). Disclosed
                                          // whenever it is non-zero — see recallBytesForTokens for why this used
                                          // to read "8000 or nothing" and what that cost.
    std::size_t budgetTokens   = 0;       // F4: --token-budget's GATING ceiling in tokens (0 = none). A SECOND
                                          // ceiling applied to this run, and until verify-wave2 the header
                                          // named only the shaping one — so the number the run actually turned
                                          // on lived in prose and on stderr. Priced through the same header
                                          // fixpoint as max_tokens=, so est_tokens covers its own bytes.
};

struct RecallBundle
{
    std::string text;    // the complete artifact, header first — nothing is written before it is measured
    RecallShape shape;
};

// Budget bookkeeping: what the header + the capped-tail note may cost before the bodies get their share,
// and the smallest doc slice worth emitting (a 40-byte fragment of a design doc informs nobody).
inline constexpr std::size_t kRecallHeaderReserveBytes = 320;
inline constexpr std::size_t kRecallTruncNoteBytes     = 128;
inline constexpr std::size_t kRecallMinBodyBytes       = 240;
inline constexpr std::size_t kDefaultRecallMaxTokens   = 8000;

// H9 (capture-audit 2026-09-04): the ONE token→byte conversion for recall's ceiling, and the reason it is a
// function rather than an expression repeated at each front door. It used to be spelled out twice — once in
// verbs_for.h's --recall arm and once in mcpverbs.h's `memory_recall` — and each door then handed
// buildRecall a BYTE count, at which point the token number the caller asked for was gone. That is why the
// header could disclose a ceiling only when it happened to equal the 8000 default: the only comparison left
// was `maxBytes == defaultMaxBytes`, so `--max-tokens=1500` (and MCP `budget_tokens=1500`, which maps to
// that same flag) applied a real ceiling and named none. The TOKEN count now travels to the header and the
// conversion lives here, beside the default it converts. Gate: test/budgetpolicycheck.sh arms (B) and (C).
inline std::size_t recallBytesForTokens( std::size_t maxTokens ) noexcept
{
    return budgetBytesForTokens( maxTokens );   // serialize.h owns the one expression; this names it for recall
}

// A recalled body is raw markdown, and the budget cut lands wherever the byte count says — including
// INSIDE a ```fenced code block. The emitted doc then ends with an OPENED fence nothing ever closes: the
// `[truncated: …]` marker, the following separators and the closing `(capped: …)` note all fall inside a
// phantom code block, and a consumer that embeds the payload inherits the corrupted fence state for
// everything it appends afterwards. So: replay the fence toggles over the ALREADY-TRUNCATED body (the
// same text the reader sees, ellipsis included) and close a fence left open.
//
// The fence state machine itself is docparse::scanMarkdownFences — the ONE scanner, shared with the
// generated-doc signal (§P2b), so "inside a fence" cannot mean two different things in one binary. A state
// machine that over-closes is honest markdown; one that under-closes is not. Pure text in, pure text out:
// deterministic, no map order, no clock. Returns true when it had to close a fence.
inline bool closeOpenMarkdownFence( std::string& body )
{
    if( !docparse::scanMarkdownFences( body ).endsInsideFence )
    {
        return false;
    }
    if( !body.empty() && body.back() != '\n' )
    {
        body += '\n';
    }
    body += "```";
    return true;
}

// §L4.1 — a bounded lookback SEARCH for a clean place to land a forced cut, instead of the raw byte
// ceiling. `cut` is already a UTF-8-safe prefix length (never exceeded — this only ever moves it
// EARLIER); the window is the last `lookbackBytes` bytes before it. Priority, most specific first:
// a blank line (paragraph end), a sentence end (". "/"! "/"? ", or the same three followed by a
// newline instead of a space), any newline. No boundary found in-window ⇒ today's byte cut (`cut`
// unchanged) — the honest fallback the brief calls for. Hand-rolled rfind scans; no regex.
inline constexpr std::size_t kRecallBoundaryLookbackBytes = 400;

inline std::size_t findRecallBoundaryCut( std::string_view body, std::size_t cut, std::size_t lookbackBytes ) noexcept
{
    if( cut == 0 || cut > body.size() )
    {
        return cut;
    }
    const std::size_t     windowStart = ( cut > lookbackBytes ) ? cut - lookbackBytes : 0;
    const std::string_view window     = body.substr( windowStart, cut - windowStart );

    if( const std::size_t p = window.rfind( "\n\n" ); p != std::string_view::npos )
    {
        return windowStart + p + 2;   // land right after the blank line — a paragraph boundary
    }
    std::size_t bestSentence = std::string_view::npos;
    for( const char* term : { ". ", "! ", "? ", ".\n", "!\n", "?\n" } )
    {
        const std::size_t p = window.rfind( term );
        if( p != std::string_view::npos && ( bestSentence == std::string_view::npos || p > bestSentence ) )
        {
            bestSentence = p;
        }
    }
    if( bestSentence != std::string_view::npos )
    {
        return windowStart + bestSentence + 2;   // every candidate term is exactly 2 bytes wide
    }
    if( const std::size_t p = window.rfind( '\n' ); p != std::string_view::npos )
    {
        return windowStart + p + 1;   // a bare line break beats a mid-word tear
    }
    return cut;   // nothing in-window — the byte cut is the honest fallback
}

// §L4.2 — fenced code blocks and pipe-table row runs are WHOLE-OR-NOTHING under a forced cut: the cut
// point may not land inside one. `end` is exclusive (the byte just past the element). Detected in one
// pass over lines, mirroring docparse::scanMarkdownFences' own fence rule (three-or-more backticks,
// first non-space characters on the line, toggles state) so "inside a fence" cannot mean two different
// things in this file. A pipe-table run is ≥2 consecutive non-blank lines outside any fence that each
// contain a `|` — deliberately loose (no header/separator-row validation): a hand-rolled table detector
// that DEMANDS GFM's exact grammar would silently stop protecting a body whose table is slightly
// off-spec, which is a worse failure than over-protecting a pipe-heavy paragraph run.
struct RecallProtectedRange
{
    std::size_t start = 0;
    std::size_t end   = 0;   // exclusive
};

inline std::vector<RecallProtectedRange> findRecallProtectedRanges( std::string_view body )
{
    std::vector<RecallProtectedRange> ranges;
    bool        insideFence  = false;
    std::size_t fenceStart   = 0;
    std::size_t tableStart   = std::string_view::npos;
    std::size_t tableLines   = 0;

    const auto flushTable = [ & ]( std::size_t atByte )
    {
        if( tableStart != std::string_view::npos && tableLines >= 2 )
        {
            ranges.push_back( { tableStart, atByte } );
        }
        tableStart = std::string_view::npos;
        tableLines = 0;
    };

    for( std::size_t lineStart = 0; lineStart < body.size(); )
    {
        std::size_t lineEnd     = body.find( '\n', lineStart );
        const bool  hasNewline  = lineEnd != std::string_view::npos;
        if( !hasNewline )
        {
            lineEnd = body.size();
        }
        const std::string_view line       = body.substr( lineStart, lineEnd - lineStart );
        const std::size_t      lineFullEnd = hasNewline ? lineEnd + 1 : body.size();

        std::size_t cursor = 0;
        while( cursor < line.size() && ( line[cursor] == ' ' || line[cursor] == '\t' ) ) { ++cursor; }
        std::size_t tickCount = 0;
        while( cursor + tickCount < line.size() && line[cursor + tickCount] == '`' ) { ++tickCount; }

        if( tickCount >= 3 )
        {
            flushTable( lineStart );
            if( !insideFence )
            {
                insideFence = true;
                fenceStart  = lineStart;
            }
            else
            {
                insideFence = false;
                ranges.push_back( { fenceStart, lineFullEnd } );
            }
        }
        else if( insideFence )
        {
            // absorbed into the open fence's range once it closes (or at EOF, below) — no per-line work
        }
        else
        {
            const bool isBlank     = line.find_first_not_of( " \t\r" ) == std::string_view::npos;
            const bool isTableLine = !isBlank && line.find( '|' ) != std::string_view::npos;
            if( isTableLine )
            {
                if( tableStart == std::string_view::npos ) { tableStart = lineStart; tableLines = 1; }
                else                                       { ++tableLines; }
            }
            else
            {
                flushTable( lineStart );
            }
        }
        lineStart = lineFullEnd;
    }
    if( insideFence )
    {
        ranges.push_back( { fenceStart, body.size() } );   // unterminated fence protects through EOF
    }
    flushTable( body.size() );
    return ranges;
}

// Move `cut` to the start of any protected range it falls strictly inside — never later, only earlier,
// so a caller's byte ceiling is never exceeded. Loops because moving out of one range can start it
// inside an earlier one when ranges abut; `cut` only ever decreases, so this always terminates.
inline std::size_t adjustCutForProtectedRanges( std::size_t cut, const std::vector<RecallProtectedRange>& ranges ) noexcept
{
    bool moved = true;
    while( moved )
    {
        moved = false;
        for( const RecallProtectedRange& r : ranges )
        {
            if( cut > r.start && cut < r.end )
            {
                cut   = r.start;
                moved = true;
            }
        }
    }
    return cut;
}

// Cut ONE doc body down to AT MOST `keepBytes` and return the marker that DISCLOSES the cut. Split out
// of buildRecall's budget loop so the whole truncation policy reads in one place: UTF-8-safe prefix,
// §L4.1's boundary cascade (land on a paragraph/sentence/line boundary instead of mid-word when one is
// reachable within the lookback window), §L4.2's protected ranges (never tear a fenced block or a table
// row), fence repair as the last safety net, and what the marker admits to. `body` is edited in place;
// the returned text is appended to the doc's separator line, ahead of the body itself. Every step below
// only ever moves the cut EARLIER than the requested `keepBytes` — the byte-budget ceiling a caller
// computed is never exceeded, only under-used in exchange for landing somewhere readable. Truncating
// BEFORE formatting is what lets the marker report fence_closed: whether a fence had to be closed is
// only knowable once the cut has been made.
inline std::string truncateRecallBody( std::string& body, std::size_t keepBytes )
{
    const std::size_t fullBytes = body.size();

    std::size_t cut = std::min( keepBytes, fullBytes );
    while( cut > 0 && ( static_cast<unsigned char>( body[cut] ) & 0xC0 ) == 0x80 ) { --cut; }   // UTF-8-safe backoff

    cut = findRecallBoundaryCut( body, cut, kRecallBoundaryLookbackBytes );
    cut = adjustCutForProtectedRanges( cut, findRecallProtectedRanges( body ) );

    while( cut > 0 && ( static_cast<unsigned char>( body[cut] ) & 0xC0 ) == 0x80 ) { --cut; }   // re-verify: both
                                                                                                  // moves above land
                                                                                                  // on '\n' bytes
                                                                                                  // (always safe),
                                                                                                  // but a stale
                                                                                                  // assumption
                                                                                                  // costs nothing
                                                                                                  // to re-check.
    const std::size_t actualKeepBytes = cut;

    truncateUtf8WithEllipsis( body, actualKeepBytes );                                // deterministic UTF-8-safe prefix + a visible "…"
    const char* fenceNote = closeOpenMarkdownFence( body ) ? ", fence_closed" : "";    // §B2 — never hand back an open fence

    // CA4 H1 sibling sweep: this one was PROVABLY bounded (fixed prose + two %zu + the two-valued fenceNote =
    // 79 bytes worst case in a 160-byte buffer), so it never overflowed. It is composed on std::string anyway,
    // because the SHAPE is the defect, not the arithmetic: "snprintf into a fixed buffer, then append its
    // WOULD-BE return length" is safe only for as long as nobody widens the prose or adds an interpoland, and
    // that safety is invisible at the call site. Byte-identical to the format string it replaces.
    return "  [truncated: " + std::to_string( actualKeepBytes ) + " of " + std::to_string( fullBytes ) + " bytes"
           + fenceNote + "]";
}

// One recalled doc's emitted text, redacted. P1-B: for a document file this is its EXTRACTED text (the
// override), not the raw bytes — a recalled notebook must read as its prose/code, never as raw .ipynb JSON.
// Credential shapes are redacted HERE, before any budget arithmetic, so the budget charges the bytes
// that are actually emitted; no-op under --no-redact. An unreadable file yields nullopt (skip, never a stub).
inline std::optional<std::string> loadRecallBody( const IngestResult& ing, std::uint32_t fileId, RedactCounts* redact )
{
    std::string body;
    if( const auto it = ing.docText.find( fileId ); it != ing.docText.end() )
    {
        body = it->second;
    }
    else
    {
        std::ifstream in( diskPath( ing, fileId ), std::ios::binary );
        if( !in )
        {
            return std::nullopt;
        }
        std::ostringstream ss;  ss << in.rdbuf();
        body = ss.str();
    }
    redactInPlace( body, redact );
    return body;
}

// The bundle's header line — the ONLY place the honest-shape fields are written. Keeps the legacy prefix
// ("K relevant of N docs, best-first", which recallrelcheck parses) and appends the machine-readable
// total=/shown=/capped=/truncated=/generated_demoted=/est_tokens= tail. `truncated=` appears only when
// something WAS cut; `generated_demoted=` only when the ranking actually moved a generated doc down — an
// absent field means it did not happen, never that it was not looked for (the §P0.1 honest-limit rule).
//
// §L4.3 loop-closer, and why it rides HERE. A per-doc `lines="LO-HI[,…]"` names the SELECTED section spans —
// where the picked sections start and end in the file — and that stays true after the byte budget cuts the
// last body mid-section. The adjacent `[truncated: X of Y bytes]` marker already says the text was cut, so
// the form is honest, but nothing on the screen said which of the two numbers `lines=` belongs to, and a
// reader who assumed "the range I am looking at" would be wrong by however much was trimmed. The clause is
// charged only to a run that actually truncated something: with `truncated=` absent, lines= and the emitted
// text agree exactly and there is nothing to disambiguate — the same "charged where the attribute is" rule
// the map legend's conditional clauses follow. It is appended AFTER the last attribute, never between two,
// so the header's `name=value` tail stays scannable.
inline std::string formatRecallHeader( std::string_view task, const RecallShape& shape, std::size_t estTokens )
{
    // W3FIX M1 (same class as --for/--pack-task): `over_ceiling=1` — the artifact is larger than the --max-tokens
    // byte budget it was SHAPED against, because the header's own verbatim task echo is user-length text that
    // no body cut can shrink (kRecallHeaderReserveBytes + task.size() is charged, and a long enough task simply
    // leaves payloadBudget at 0 with the header still over). Absent ⇒ within the budget, or no --max-tokens at
    // all: the same silence-means-nothing-happened rule truncated=/generated_demoted= follow below.
    std::string overCeilingAttr;
    if( shape.isOverCeiling )
    {
        overCeilingAttr = " over_ceiling=1";
    }
    const std::string maxTokensAttr = shape.maxTokens > 0
        ? " max_tokens=" + std::to_string( shape.maxTokens )
        : std::string();
    // F4: the GATE's ceiling beside the SHAPING one, in the same unit. Absent when no --token-budget was
    // passed, so every document that never had one is byte-identical.
    const std::string budgetTokensAttr = shape.budgetTokens > 0
        ? " budget_tokens=" + std::to_string( shape.budgetTokens )
        : std::string();
    std::string truncAttr;
    std::string linesNote;   // §L4.3 — see the header comment for why it is conditional and why it trails
    if( shape.truncatedCount > 0 )
    {
        truncAttr = " truncated=" + std::to_string( shape.truncatedCount );
        linesNote = "  [lines= on a doc is its SELECTED section range — pre-truncation; the per-doc"
                    " truncation marker names the bytes actually emitted]";
    }
    std::string demotedAttr;
    if( shape.demotedCount > 0 )
    {
        demotedAttr = " generated_demoted=" + std::to_string( shape.demotedCount );
    }
    // §B2: the numerator and total= are the TRUE relevant count (matchedCount, pre-top-k) — shown= is what
    // this run actually emitted; capped= (isCapped) is honest about the gap between the two, whatever cut
    // caused it (--top-k, the byte budget, or an unreadable file).
    // W3FIX H1 (verifier, HIGH): this was a 512-byte stack buffer + snprintf, and the return read the
    // WOULD-BE length — a task over ~395 bytes made std::string(buf,len) read past the stack frame and,
    // via MCP memory_recall, leak raw stack bytes into the JSON-RPC reply (ASan: stack-buffer-overflow,
    // one client request kills the server). The task echo is USER-LENGTH text; compose on std::string —
    // the same seam rule §B1.1 applied to the columnar attr buffers. Byte-identical for every task the
    // old path did not truncate.
    // §B9.2: "document files" is docFileMask()'s population and says so — it is a SUPERSET of
    // --doc-drift's docs= (markdown by extension), and the two must not share a noun.
    std::string line;
    line.reserve( 160 + task.size() + truncAttr.size() + demotedAttr.size() + overCeilingAttr.size()
                  + maxTokensAttr.size() + budgetTokensAttr.size() + linesNote.size() );
    line += "ripwire recall — \"";
    line += task;
    line += "\" — ";
    line += std::to_string( shape.matchedCount );
    line += " relevant of ";
    line += std::to_string( shape.docCount );
    line += " document files, best-first — total=";
    line += std::to_string( shape.matchedCount );
    line += " shown=";
    line += std::to_string( shape.shownCount );
    line += " capped=";
    line += shape.isCapped ? "1" : "0";
    line += truncAttr;
    line += demotedAttr;
    line += overCeilingAttr;
    line += maxTokensAttr;
    line += budgetTokensAttr;
    line += " est_tokens=";
    line += std::to_string( estTokens );
    line += linesNote;
    line += "\n";
    return line;
}

// §P2b — what a demoted doc says ON ITS OWN separator line: the evidence that demoted it, so a reader who
// sees a capture at the bottom knows it was ranked there deliberately. "" for a hand-written doc.
inline std::string formatDemotedNote( docparse::GeneratedDocReason reason )
{
    if( reason == docparse::GeneratedDocReason::None )
    {
        return {};
    }
    return "  [generated_demoted: " + std::string( docparse::generatedReasonTag( reason ) ) + "]";
}

// One recalled doc's SEPARATOR line — "\n━━ <path>  (relevance N.NNN) ━━<demotedNote>".
//
// CA4 H1 (BROKEN HIGH, memory-safety + info leak): this was `char sep[640]` + snprintf, and buildRecall
// appended snprintf's WOULD-BE return length — so a doc whose ABSOLUTE PATH crossed ~610 bytes made
// std::string::append READ PAST the stack frame (ASan: stack-buffer-overflow READ of size 782 on a 748-byte
// path, exit 134, on the --recall CLI seam AND on MCP memory_recall, where one client request kills the
// server; under the plain build the read succeeds and 16-309 raw stack bytes — NULs and live pointers —
// are emitted into the payload, which also made the output NON-deterministic run to run).
//
// This is verbatim the W3FIX H1 class already fixed in formatRecallHeader ABOVE, whose own comment states
// the rule that fix then failed to carry to its callee: path-length and user-length text is composed on
// std::string, never sized against a fixed buffer (§B1.1). The buffer is GONE rather than grown or clamped —
// an absolute path is unbounded by nature, so no constant is the right constant, and clamping would trade a
// leak for a silent truncation of the one field a reader needs verbatim to open the doc.
//
// The score is the ONE genuinely bounded interpoland (a double under "%.3f" is at most 314 bytes: sign +
// DBL_MAX's 309 integer digits + '.' + 3), and it is appended as a NUL-TERMINATED C string, so even a
// hypothetical truncation could only shorten the text — it can never read past the buffer.
inline std::string formatRecallSeparator( std::string_view path, float score, std::string_view demotedNote )
{
    char scoreText[ 352 ];
    std::snprintf( scoreText, sizeof( scoreText ), "%.3f", double( score ) );

    std::string line;
    line.reserve( 40 + path.size() + demotedNote.size() );
    line += "\n━━ ";
    line += path;
    line += "  (relevance ";
    line += scoreText;
    line += ") ━━";
    line += demotedNote;
    return line;
}

// §B2 — the trailing "(capped: …)" note's attribution. Two independent cuts can both apply: --top-k trims
// the TRUE relevant set (matchedCount) down to what got loaded at all (selectedCount), and the byte budget
// / an unreadable file can shrink that further to what got emitted (shownCount). Name whichever actually
// fired — "raise --top-k" is never suggested for a pure budget cut, and vice versa. Split out of
// buildRecall so its budget loop doesn't carry this branch-heavy attribution logic too.
inline std::string formatRecallCappedNote( const RecallShape& shape, std::size_t maxBytes )
{
    const std::size_t topKOmitted   = shape.matchedCount - shape.selectedCount;
    const std::size_t budgetOmitted = shape.selectedCount - shape.shownCount;
    std::string        why;
    if( topKOmitted > 0 )
    {
        why += "raise --top-k (default 8) for " + std::to_string( topKOmitted ) + " more";
    }
    if( budgetOmitted > 0 )
    {
        if( !why.empty() )
        {
            why += "; ";
        }
        why += maxBytes ? ( "raise --max-tokens or narrow the query for " + std::to_string( budgetOmitted ) + " more (~" + std::to_string( maxBytes ) + "-byte budget)" )
                        : ( std::to_string( budgetOmitted ) + " unreadable on disk" );
    }
    // CA4 H1 sibling sweep: bounded, but the TIGHTEST of the four — 254 bytes worst case in a 320-byte buffer,
    // and 161 of those 254 are `why`, a std::string of prose composed just above. One more attribution clause,
    // or one longer sentence, and the same return-as-length shape becomes the same overflow. `why` is already a
    // std::string; the buffer added nothing but the hazard. Byte-identical to the format string it replaces.
    return "\n(capped: " + std::to_string( shape.matchedCount - shape.shownCount ) + " of "
           + std::to_string( shape.matchedCount ) + " relevant document files omitted — " + why + ")\n";
}

// §G3 (the markdown section tier) — the SECTION-GRANULAR recall body. When a matched document has
// heading sections of its own and at least one of them matched the query, serve those sections'
// bodies instead of the whole doc: the residual this deletes is "find the section inside the doc".
// Whole-doc remains the path for heading-less docs and extracted-text documents (notebooks/html via
// docparse, which only ever carry a whole-file node) — DISCLOSED by the absence of the
// `[sections: …]` note, and its presence names the cut: kept of total, plus the whole doc's byte
// size so the reader knows what was not loaded.
//
// Which sections: every positive-scoring heading section, most specific first — score descending
// (BM25's length normalization puts the tight matching section above its diluted parent, whose span
// contains it), byte position as the deterministic tiebreak — dropping any candidate that OVERLAPS
// an already-kept one (nested spans would emit the same text twice), then re-ordered to document
// order for reading. Returns nullopt whenever the whole-doc path is the right answer; a file that
// changed on disk since ingest (span past EOF) also returns nullopt rather than serving a wrong
// slice — the whole-doc path re-reads it honestly.
struct RecallSectionPick
{
    std::uint32_t symIndex = 0;
    float         score    = 0.f;
};

inline std::optional<std::pair<std::string, std::string>> buildSectionGranularBody(
        const IngestResult& ing, const std::vector<float>& scores, std::uint32_t fileId, RedactCounts* redact )
{
    if( ing.docText.find( fileId ) != ing.docText.end() )
    {
        return std::nullopt;   // extracted-text docs have no markdown heading sections
    }
    std::vector<RecallSectionPick> picks;
    std::size_t                    sectionCount = 0;
    for( std::size_t i = 0; i < ing.symbols.size() && i < scores.size(); ++i )
    {
        const Symbol& s = ing.symbols[ i ];
        if( s.fileId != fileId || s.kind != SymKind::Section || s.lang != Lang::Markdown
            || s.sigEndByte >= s.endByte )
        {
            continue;   // not a heading section WITH a body (the whole-file node has sigEnd == end)
        }
        ++sectionCount;
        if( scores[ i ] > 0.f )
        {
            picks.push_back( { std::uint32_t( i ), scores[ i ] } );
        }
    }
    if( picks.empty() )
    {
        return std::nullopt;
    }
    std::sort( picks.begin(), picks.end(), [ & ]( const RecallSectionPick& a, const RecallSectionPick& b ) noexcept
    {
        if( a.score != b.score )
        {
            return a.score > b.score;
        }
        return ing.symbols[ a.symIndex ].sigStartByte < ing.symbols[ b.symIndex ].sigStartByte;
    } );
    std::vector<std::uint32_t> kept;
    for( const RecallSectionPick& p : picks )
    {
        const Symbol& s        = ing.symbols[ p.symIndex ];
        bool          overlaps = false;
        for( const std::uint32_t k : kept )
        {
            const Symbol& o = ing.symbols[ k ];
            if( s.sigStartByte < o.endByte && o.sigStartByte < s.endByte )
            {
                overlaps = true;
                break;
            }
        }
        if( !overlaps )
        {
            kept.push_back( p.symIndex );
        }
    }
    std::sort( kept.begin(), kept.end(), [ & ]( std::uint32_t a, std::uint32_t b ) noexcept
    { return ing.symbols[ a ].sigStartByte < ing.symbols[ b ].sigStartByte; } );

    std::ifstream in( diskPath( ing, fileId ), std::ios::binary );
    if( !in )
    {
        return std::nullopt;
    }
    std::ostringstream ss;
    ss << in.rdbuf();
    const std::string raw = ss.str();

    std::string body;
    std::string linesAttr;   // §L4.3 — "LO-HI[,LO-HI…]", one range per kept section, document order
    for( const std::uint32_t k : kept )
    {
        const Symbol& s = ing.symbols[ k ];
        if( s.endByte > raw.size() || s.sigStartByte >= s.endByte )
        {
            return std::nullopt;   // the file moved under us — fall back to the honest whole-doc re-read
        }
        std::string slice = raw.substr( s.sigStartByte, s.endByte - s.sigStartByte );
        redactInPlace( slice, redact );
        if( !body.empty() && body.back() != '\n' )
        {
            body += '\n';
        }
        body += slice;

        const std::uint32_t lo = layout::lineOf( raw, s.sigStartByte );
        const std::uint32_t hi = layout::lineOf( raw, s.endByte - 1 );   // last INCLUDED byte — endByte is exclusive
        if( !linesAttr.empty() )
        {
            linesAttr += ",";
        }
        linesAttr += std::to_string( lo ) + "-" + std::to_string( hi );
    }
    std::string note = "  [sections: " + std::to_string( kept.size() ) + " of "
                       + std::to_string( sectionCount ) + ", section-granular; whole doc "
                       + std::to_string( raw.size() ) + " B; lines=\"" + linesAttr + "\"]";
    return std::make_pair( std::move( body ), std::move( note ) );
}

// Build the recall bundle IN MEMORY: each top file's path + relevance + body, best-first. `maxBytes` (0 =
// no cap) SHAPES it — bodies are dropped from the BOTTOM of the ranking and the last one may be truncated
// within itself, both DISCLOSED (per-doc `[truncated: …]`, header `capped=1`/`truncated=N`, a closing
// `(capped: …)` note). Building before writing is what lets --token-budget gate BEFORE a byte is emitted.
// §B10.1: `redact` is REQUIRED — no default. A recalled doc is whole-file prose straight off disk, which is
// the same credential seam packSource has; W3-N1's rule ("a new emitting clone cannot silently opt out")
// applies to it exactly. nullptr = --no-redact, spelled deliberately. The one caller already passed it.
// H9: the ceiling arrives as TOKENS (0 = no cap) — the unit the caller asked in and the unit the header
// discloses. The byte budget is derived here, once, by recallBytesForTokens.
inline RecallBundle buildRecall( const IngestResult& ing, const std::vector<float>& scores,
                                 std::string_view task, int k, std::size_t maxTokens, bool docsOnly,
                                 RedactCounts* redact,
                                 std::string_view rootArg = {},        // R-R: the separator line's path root
                                 std::size_t budgetTokens = 0 )        // F4: --token-budget's GATING ceiling, named on the header
{
    const std::size_t maxBytes = recallBytesForTokens( maxTokens );
    // R-R: same convention every other lens's pathRel uses — the "━━ <path>" separator is a DISPLAY path and
    // was the last CLI surface still printing the checkout prefix once per recalled doc.
    const std::string recallRootPrefix = rootArg.empty() ? std::string() : rw::sarif::rootPrefixOf( rootArg );
    const RecallSelection        selected = recallTopFiles( ing, scores, k, docsOnly );
    const std::vector<Recalled>& top      = selected.files;

    // the payload's own share of the budget — the header and the closing capped note are charged first so
    // the TOTAL artifact (not just its bodies) honours maxBytes.
    const std::size_t headerReserve = maxBytes ? kRecallHeaderReserveBytes + task.size() : 0;
    const std::size_t payloadBudget = ( maxBytes > headerReserve ) ? maxBytes - headerReserve : 0;

    std::string payload;
    std::size_t markupBytes = 0;   // separators + markers: envelope, estimated at the mid-band rate
    std::size_t bodyBytes   = 0;   // recalled prose: estimated at the measured markdown rate
    RecallShape shape;
    shape.docCount      = selected.docCount;      // §A8.2: docFileMask() population, not the whole file corpus
    shape.matchedCount  = selected.matchedCount;  // §B2: TRUE relevant count, pre-top-k
    shape.selectedCount = top.size();             // post-top-k, pre-budget (bookkeeping for the capped note)
    shape.demotedCount  = selected.demotedMatchCount;
    shape.maxTokens     = maxTokens;              // H9: the ceiling applied, whatever it is (0 = unbounded)
    shape.budgetTokens  = budgetTokens;           // F4: the GATING ceiling beside the shaping one (0 = none)

    for( const Recalled& r : top )
    {
        // V5: fileId is an INDEX into files[], and this VERIFY guards the NEAREST dereference — which is
        // loadRecallBody's, not the separator's. It sat one call below, i.e. one dereference late: the
        // invariant was true and correctly a VERIFY, but the first read it protected had already happened.
        VERIFY( r.fileId < ing.files.size() );
        std::string                sectionNote;   // "" = whole-doc (the disclosed default for heading-less docs)
        std::optional<std::string> loaded;
        if( auto granular = buildSectionGranularBody( ing, scores, r.fileId, redact ) )
        {
            loaded      = std::move( granular->first );
            sectionNote = std::move( granular->second );
        }
        else
        {
            loaded = loadRecallBody( ing, r.fileId, redact );
        }
        if( !loaded )
        {
            continue;
        }
        std::string body = std::move( *loaded );

        const std::string demotedNote = formatDemotedNote( r.generated ) + sectionNote;
        const std::string_view sepPath = rootArg.empty() ? std::string_view( ing.files[ r.fileId ] )
                                                         : rw::sarif::rootRelativeUri( ing.files[ r.fileId ], recallRootPrefix );
        const std::string sep         = formatRecallSeparator( sepPath, r.score, demotedNote );
        const std::size_t sepBytes    = sep.size();

        // the budget decision for THIS doc: full, sliced, or not at all. `used` is the payload so far.
        std::size_t keepBytes    = body.size();
        bool        isTruncated  = false;
        if( maxBytes )
        {
            const std::size_t used  = payload.size();
            const std::size_t floor = sepBytes + 2 + kRecallMinBodyBytes;
            if( used + floor > payloadBudget )
            {
                break; // no room for a meaningful slice
            }
            const std::size_t room = payloadBudget - used - sepBytes - 2;   // 2 = the separator's own newline + body's
            if( body.size() > room )
            {
                keepBytes   = ( room > kRecallTruncNoteBytes ) ? room - kRecallTruncNoteBytes : kRecallMinBodyBytes;
                isTruncated = true;
            }
        }

        payload     += sep;
        markupBytes += sepBytes;
        if( isTruncated )
        {
            const std::string note = truncateRecallBody( body, keepBytes );
            payload     += note;
            markupBytes += note.size();
            ++shape.truncatedCount;
        }
        payload += '\n';
        payload += body;    // append, not printf: an embedded NUL must not truncate the doc
        payload += '\n';
        markupBytes += 2;
        bodyBytes   += body.size();
        ++shape.shownCount;
        if( isTruncated )
        {
            break; // the budget is spent — the next doc would be a 0-byte stub
        }
    }

    // the closing note. "no relevant documents" is reserved for a ranking that FOUND none — a budget that
    // fits none of 8 hits is a cap, not an empty corpus, and must not read as one (the §P0.1 honest-limit rule).
    if( shape.matchedCount == 0 )
    {
        const char* empty = "\n(no relevant documents — try different terms)\n";
        payload += empty;
        markupBytes += std::char_traits<char>::length( empty );
    }
    else if( shape.shownCount < shape.matchedCount )
    {
        const std::string note = formatRecallCappedNote( shape, maxBytes );
        payload     += note;
        markupBytes += note.size();
    }
    shape.isCapped = shape.shownCount < shape.matchedCount || shape.truncatedCount > 0;

    // the header, last: it REPORTS est_tokens, so it can only be written once the payload is measured. The
    // estimate covers the whole artifact — the header's own bytes included (§P9.3) — which makes it a small
    // fixpoint: format, re-measure, repeat until the digit count stops moving (converges in ≤3 passes).
    // W3FIX M1: over_ceiling= is decided INSIDE this fixpoint for the same reason est_tokens= is — it is a fact
    // about the finished artifact, and the header is part of the artifact. The condition is monotone (the
    // attribute only ever ADDS bytes, and a document already over the budget cannot come back under by growing),
    // so it settles in one extra pass; the bound is 4 rather than 3 to leave that pass room.
    std::string header;
    for( int pass = 0; pass < 4; ++pass )
    {
        // CA4 residual ("--recall measures 2.559 B/tok on mostly-prose … prose charged at the MARKUP rate
        // over-estimates") — RE-DERIVED AND DECIDED HERE: KEEP THE SPLIT AS IT IS.
        //   1. The premise is half wrong, and the correction belongs in the source rather than a ledger: this
        //      is NOT one rate. The envelope (separators, truncation markers, the header) is charged at
        //      kBytesPerTokenDefault (2.50, mid-band) and the recalled PROSE at the Markdown calibration
        //      (2.56) — a split this loop has always had. The 2.559 B/tok the residual measured is the
        //      blended result of exactly that split on a bundle that is ~all body, i.e. it CONFIRMS the
        //      calibration is being applied, it does not show a wrong one being applied. Re-measured on three
        //      queries: 2.560, 2.560, 2.560 B/tok (129 495 B / 50 592 tok · 336 406 / 131 416 · 239 397 / 93 521).
        //   2. Moving 2.56 toward a laxer prose rate needs a MEASUREMENT against a real tokenizer, and this
        //      repo deliberately vendors no BPE table (kTokenCalib's rates are calibrated externally and
        //      reported in the write-up, never guessed in-tree). A number changed by intuition is worse than a
        //      conservative number changed by nobody.
        //   3. The error DIRECTION is the safe one and is the same bias kMinBytesPerToken encodes for
        //      --max-tokens: charging prose densely over-reads est_tokens, so --recall withholds a document it
        //      could have shown. It can never overshoot a stated ceiling. For a number whose whole job IS a
        //      ceiling, "smaller than allowed" is the correct way to be wrong.
        // If a future round does measure markdown prose against o200k, the change is one table entry
        // (kTokenCalib's Lang::Markdown row in serialize.h), not a change here — this loop already asks the
        // table the right question.
        const double      markup = double( markupBytes + header.size() );
        const std::size_t est    = std::size_t( markup / kBytesPerTokenDefault
                                                + double( bodyBytes ) / bytesPerTokenFor( Lang::Markdown ) + 0.5 );
        shape.estTokens     = est;
        shape.isOverCeiling = maxBytes > 0 && header.size() + payload.size() > maxBytes;
        std::string next    = formatRecallHeader( task, shape, est );
        if( next == header )
        {
            break;
        }
        header = std::move( next );
    }

    RecallBundle bundle;
    bundle.text = std::move( header );
    bundle.text += payload;
    shape.bytes = bundle.text.size();
    bundle.shape = shape;
    return bundle;
}

// §A8.3 / N3: the withheld path used to stream bundle.text's HEADER LINE verbatim — a header formatted (by
// formatRecallHeader, above) for the bundle that got REJECTED. It claimed `shown=8` for a run that printed
// zero rows (§A8.3 fixed that), and it went on claiming `est_tokens=98069` beside `shown=0` on a 260-byte
// emission, which is the same defect one field over: both attributes are normatively about what THIS RUN
// PRINTED (pageview.h, THE TRUNCATION VOCABULARY, rule 1 — a zero must be a measurement, and so must the
// number standing next to it). Rewriting the whole header via formatRecallHeader would need the task
// string_view threaded an extra hop for no benefit, so this substitutes the numeric field in place.
//
// `field` includes its own leading space and trailing '=' (" shown=", " est_tokens="), which is what makes
// the match unambiguous against a header whose task text is arbitrary user input.
inline std::string withHeaderField( std::string_view fullHeaderLine, std::string_view field, std::size_t value )
{
    std::string       line( fullHeaderLine );
    const std::size_t pos = line.find( field );
    if( pos == std::string::npos )
    {
        return line; // defensive: header shape changed elsewhere — leave it be
    }

    const std::size_t digitsStart = pos + field.size();
    std::size_t       digitsEnd   = digitsStart;
    while( digitsEnd < line.size() && line[digitsEnd] >= '0' && line[digitsEnd] <= '9' )
    {
        ++digitsEnd;
    }
    line.replace( digitsStart, digitsEnd - digitsStart, std::to_string( value ) );
    return line;
}

// F4 (capture-audit verify-wave2 2026-09-05) — INSERT an attribute after a numeric header field, rather
// than substituting a field that is already there. `--recall --token-budget=N` applies a second, GATING
// ceiling (D10) on top of the 8000-token SHAPING default, and the header named only the first:
//
//   --recall="…" --token-budget=1500 → over_ceiling=1 max_tokens=8000 est_tokens=182
//                            (stderr)  ripwire: --token-budget exceeded: withheld_est_tokens=6669 > budget=1500
//   --recall="…" --token-budget=6000 → max_tokens=8000                    (still the default)
//
// The ceiling that decided the run appeared nowhere an attribute reader could find it, on either side of the
// decision — H9's own rule ("a ceiling applied is a ceiling named") missed on the verb H9 was written for,
// because only the --max-tokens front door was walked. The GATE personality itself is not touched: this
// names the number, it does not turn --token-budget into a shaper (the artifact it rejected is still never
// streamed — recallbudgetcheck §2, budgetpolicycheck (C)).
inline std::string withHeaderAttrAfter( std::string_view fullHeaderLine, std::string_view afterField, std::string_view attr )
{
    std::string       line( fullHeaderLine );
    const std::size_t pos = line.find( afterField );
    if( pos == std::string::npos )
    {
        return line;   // defensive: header shape changed elsewhere — leave it be
    }
    std::size_t at = pos + afterField.size();
    while( at < line.size() && line[ at ] >= '0' && line[ at ] <= '9' )
    {
        ++at;
    }
    line.insert( at, attr );
    return line;
}

// Emit an already-built bundle under --token-budget's GATE personality (D10), returning the process exit
// code: 3 — the map family's "too big" code — when the bundle's own est_tokens exceeds `budgetTokens`, 0
// otherwise. Over budget, stdout gets ONLY the (corrected) header line plus a withheld note: §P6.8's lesson
// is that a CI log which receives the artifact the gate just rejected has learned nothing. Measure, decide,
// then write — the order lives here, beside buildRecall, so no caller can re-order it.
//
// N3: the header's est_tokens= now describes the EMITTED payload (header line + note), and the pre-cut
// estimate keeps its place under a name that says what it is — withheld_est_tokens=, in the note and on
// stderr, right beside the budget it lost to. That is the number a caller raising --max-tokens needs, and
// it was never the number `est_tokens=` is defined to be. Small fixpoint for the same reason buildRecall
// has one: the header states its own size, so the digit count feeds back (converges in <=3 passes).
inline int emitRecallBudgeted( std::FILE* out, const RecallBundle& bundle, std::size_t budgetTokens )
{
    if( budgetTokens > 0 && bundle.shape.estTokens > budgetTokens )
    {
        // CA4 H1 sibling sweep: bounded (193 bytes worst case in 320 — four %zu and fixed prose), composed on
        // std::string anyway so the return-as-length shape is gone from this file entirely. Byte-identical.
        const std::string note = "\n(withheld: withheld_est_tokens=" + std::to_string( bundle.shape.estTokens )
                                 + " > budget=" + std::to_string( budgetTokens ) + " — " + std::to_string( bundle.shape.bytes )
                                 + " bytes not emitted; re-run with --max-tokens=" + std::to_string( budgetTokens )
                                 + " to SHAPE it to fit)\n";
        const std::size_t noteBytes = note.size();

        const std::size_t headerEnd = bundle.text.find( '\n' );
        if( headerEnd != std::string::npos )
        {
            std::string honest = withHeaderField( std::string_view( bundle.text ).substr( 0, headerEnd + 1 ), " shown=", 0 );
            // F4/F5: over_ceiling= is a statement ABOUT est_tokens, and on this branch est_tokens is rewritten
            // to price the refusal header — the only thing that was emitted. The flag arrived from the SHAPING
            // stage, where it described the artifact this gate then withheld, so leaving it here puts a label
            // on a 200-token document claiming it busted a 8000-token ceiling. The withheld artifact's own
            // price is disclosed beside it (withheld_est_tokens=) and in the note, so nothing is lost; what
            // goes is a marker no number on this line can confirm. (Measured on the audit's own probe:
            // `over_ceiling=1 max_tokens=8000 budget_tokens=1500 est_tokens=200 withheld_est_tokens=6677` —
            // three ceilings and a price, none of which the flag was about.)
            const std::size_t ocAt = honest.find( " over_ceiling=1" );
            if( ocAt != std::string::npos )
            {
                honest.erase( ocAt, std::string_view( " over_ceiling=1" ).size() );
            }
            // F4: the two numbers the refusal turns on, beside each other and beside the price of what WAS
            // printed — est_tokens= stays normatively about this run's own output (182 tokens of header and
            // note), so the estimate that lost to the budget rides under the name that says what it is.
            honest = withHeaderAttrAfter( honest, " est_tokens=",
                                          " withheld_est_tokens=" + std::to_string( bundle.shape.estTokens ) );
            for( int pass = 0; pass < 3; ++pass )
            {
                const std::size_t est  = std::size_t( double( honest.size() + noteBytes ) / kBytesPerTokenDefault + 0.5 );
                std::string       next = withHeaderField( honest, " est_tokens=", est );
                if( next == honest )
                {
                    break;
                }
                honest = std::move( next );
            }
            std::fwrite( honest.data(), 1, honest.size(), out );
        }
        std::fwrite( note.data(), 1, noteBytes, out );
        std::fprintf( stderr, "ripwire: --token-budget exceeded: withheld_est_tokens=%zu > budget=%zu\n",
                      bundle.shape.estTokens, budgetTokens );
        return 3;
    }
    // The honoured side needs nothing here: budget_tokens= is part of the header buildRecall already built
    // and priced through its own fixpoint (RecallShape::budgetTokens), so the artifact streams unchanged.
    std::fwrite( bundle.text.data(), 1, bundle.text.size(), out );
    return 0;
}

// ─── the ONE recall call: rank, then build. Both front doors go through here ────────────────────────
//
// CLI `--recall=TASK` and MCP `memory_recall` are the same verb behind two transports, and until now they
// only CLAIMED to share a scorer. The CLI called `lexicalScores( …, pathFieldDefaultW=1, rootPrefix )`;
// `mcpverbs.h::recallText` called `lexicalScores( ix.ing, …, task )` — pathFieldDefaultW 0, no root prefix
// — under a comment reading "Shares lexicalScores + writeRecall with the --recall CLI". The two doors
// therefore ranked the same query differently: a doc found only by its PATH (its directory or filename
// spelling the query word) was RETRIEVED by the CLI and reported "no relevant documents" by MCP, and every
// score the two did share moved anyway, because the path tokens change each document's BM25 length. The
// divergence was registered in docs/EVALS.md (§"--recall ranks by where the repo sits on disk", 2026-08-25)
// as a known debt out of that round's one-mechanism scope; this is the discharge.
//
// The unification is structural, not a second copy of one argument list: the lens decision (docs only,
// path weight 1, the root prefix derived from the SAME rootArg buildRecall relativizes its separator line
// against) lives HERE, in the only place either door can reach the ranking from. `pathFieldDefaultW=1` is
// the recall lens's measured choice, not a default — bench/recalleval measured +0.03 lenient MRR for it
// (gate: test/recallevalcheck.sh) and test/recallrankdepthcheck.sh ARM 4 is its kill tripwire. Parity is
// gated by test/recallparitycheck.sh, which asserts the two doors return the same bundle byte for byte.
inline RecallBundle recallFor( const IngestResult& ing, const std::vector<std::uint32_t>& outOff,
                               const std::vector<NodeId>& outTargets, std::string_view task, int k,
                               std::size_t maxTokens, RedactCounts* redact, std::string_view rootArg,   // R-R
                               std::size_t budgetTokens = 0 )   // F4: --token-budget's GATING ceiling (CLI only; MCP has no such door)
{
    // R-R: one root fact, spent twice — the ranker scores the root-relative path spelling, buildRecall
    // prints it. Unguarded because rootPrefixOf( "" ) is "" (its trailing-slash loop needs size() > 1), so
    // the multi-root path (empty rootArg, ing.files already labelled) needs no branch.
    const std::string        prefix = rw::sarif::rootPrefixOf( rootArg );
    const std::vector<float> scores = lexicalScores( ing, outOff, outTargets, task, /*pruneTopK=*/0,
                                                     /*alwaysExact=*/nullptr, /*pathFieldDefaultW=*/1, prefix );
    return buildRecall( ing, scores, task, k, maxTokens, /*docsOnly=*/true, redact, rootArg, budgetTokens );
}

// (`writeRecall( out, ing, scores, … )` used to live here — a "render it and hand it over" wrapper that took
// a score vector the CALLER computed. That parameter was the divergence: MCP `memory_recall` was the one
// caller and it supplied differently-ranked scores. recallFor above takes the graph instead, so there is no
// argument left through which a front door can rank recall its own way, and the wrapper had nothing to do.)

}   // namespace rw

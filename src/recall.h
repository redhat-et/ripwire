#pragma once
#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings
#include <string_view>       // %.*s (precision, pointer) collapses to one view


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
    std::size_t shareBytes     = 0;       // §C4: the PER-DOCUMENT byte ceiling the budget was divided into, when
                                          // one actually bound a document (0 = no document was cut by its share
                                          // — either nothing was truncated, or the whole budget went to one doc).
                                          // A ceiling applied is a ceiling named (H9); a zero here means "the
                                          // share bound nothing", never "the share was not computed".
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

// §C4 — the smallest slice worth giving a document A SHARE OF THE BUDGET for: ~350 tokens, one screen of
// prose. Distinct from kRecallMinBodyBytes above, and the distinction is the whole point. kRecallMinBodyBytes
// is the LAST-RESORT floor — the least text that is not an insult when a budget can afford exactly one
// document. kRecallShareFloorBytes is the floor for a document competing for a share of a budget that has
// other documents to serve: it decides HOW MANY documents the budget is divided among, so that raising the
// document count never degrades every answer into a row of stubs. 900 bytes is deliberately near codesight's
// measured wiki-article size (~300 tokens), the shape this card was harvested from.
inline constexpr std::size_t kRecallShareFloorBytes = 900;

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
//
// §RP4 — `sourceKeptBytes` reports how many bytes of the INPUT survived the cascade. It is strictly less
// information than the marker already prints and exists for one reason: the section path has to name the
// LINE RANGE actually present in the emitted text, and the only honest way to derive it is from the
// surviving source prefix. It is the pre-ellipsis, pre-fence-repair count — the repaired bytes are this
// function's own text, not the document's, and must not be attributed to a line of the file.
//
// §RP4.1 — it RIDES ON THE RETURN, not on an out-parameter, per CONTRIBUTING §3 ("structured-binding
// returns over out-params"). The out-parameter version compiled fine and was still wrong for this file:
// it made the byte count OPTIONAL, and the caller that skipped it — the whole-document prefix cut — is
// exactly the one whose disclosure would go stale first if it ever grew a lines= of its own. Both facts
// are the truncation's, so both come back from it; the caller that only wants the marker names one half.
// `body` stays a mutable reference because it is the SUBJECT, edited in place, not an output smuggled
// through the parameter list.
struct RecallTruncation
{
    std::string marker;                // "  [truncated: X of Y bytes[, fence_closed]]" — appended to the separator line
    std::size_t sourceKeptBytes = 0;   // INPUT bytes that survived: pre-ellipsis, pre-fence-repair
};

inline RecallTruncation truncateRecallBody( std::string& body, std::size_t keepBytes )
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
    return { "  [truncated: " + std::to_string( actualKeepBytes ) + " of " + std::to_string( fullBytes ) + " bytes"
                 + fenceNote + "]",
             actualKeepBytes };
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
// total=/shown=/capped=/truncated=/generated_demoted=/share_bytes=/est_tokens= tail. `truncated=` appears only when
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
// " name=N", or "" at zero — the ONE place the header's silence-means-nothing-happened rule is spelled.
inline std::string optionalRecallAttr( std::string_view name, std::size_t value )
{
    return value == 0 ? std::string() : " " + std::string( name ) + "=" + std::to_string( value );
}

inline std::string formatRecallHeader( std::string_view task, const RecallShape& shape, std::size_t estTokens )
{
    // W3FIX M1 (same class as --for/--pack-task): `over_ceiling=1` — the artifact is larger than the --max-tokens
    // byte budget it was SHAPED against, because the header's own verbatim task echo is user-length text that
    // no body cut can shrink (kRecallHeaderReserveBytes + task.size() is charged, and a long enough task simply
    // leaves payloadBudget at 0 with the header still over). Absent ⇒ within the budget, or no --max-tokens at
    // all: the same silence-means-nothing-happened rule truncated=/generated_demoted= follow below.
    // §C4: max_tokens=, budget_tokens=, share_bytes= and generated_demoted= are FOUR spellings of one rule —
    // a fact stated when it happened and silent when it did not — and they were four copies of one ternary.
    // The zero test lives in optionalRecallAttr now, so a fifth cannot arrive with a different idea of what
    // "absent" means. share_bytes= is the newest of them: the THIRD ceiling this run can apply and the only
    // per-document one, named because without it a reader sees the top hit truncated well inside a budget
    // that could have held it whole and nothing on the page says why.
    const std::string overCeilingAttr   = shape.isOverCeiling ? " over_ceiling=1" : "";
    const std::string maxTokensAttr     = optionalRecallAttr( "max_tokens", shape.maxTokens );
    const std::string budgetTokensAttr  = optionalRecallAttr( "budget_tokens", shape.budgetTokens );
    const std::string shareBytesAttr    = optionalRecallAttr( "share_bytes", shape.shareBytes );
    const std::string demotedAttr       = optionalRecallAttr( "generated_demoted", shape.demotedCount );
    const std::string truncAttr         = optionalRecallAttr( "truncated", shape.truncatedCount );
    // §RP4 — §L4.3's trailing caveat ("lines= on a doc is its SELECTED section range — pre-truncation")
    // is GONE, because the thing it apologised for is gone. It existed because the budget cut a
    // document-ordered concatenation with a prefix, so lines= named spans the reader never received. The
    // section path now admits WHOLE units in rank order and rebuilds lines= from the units it actually
    // emitted (§RP3.2), and the one remaining within-unit cut names its surviving line range from the
    // surviving source bytes — so on every section-granular path lines= and the body agree exactly. A
    // caveat that is no longer true is not a smaller honesty debt than a silent cut; it is a bigger one,
    // because it teaches the reader to distrust a number that is now right. The whole-doc path never
    // emitted lines= at all — its `[truncated: X of Y bytes]` marker still says what it says.
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
                  + maxTokensAttr.size() + budgetTokensAttr.size() + shareBytesAttr.size() );
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
    line += shareBytesAttr;
    line += " est_tokens=";
    line += std::to_string( estTokens );
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
    rw::formatTo( scoreText, sizeof( scoreText ), "{:.3f}", double( score ) );

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
// `[sections: …]` note, and its presence names the cut: emitted of selected, plus the whole doc's
// byte size so the reader knows what was not loaded.
//
// Which sections: every positive-scoring heading section, score descending with byte position as the
// deterministic tiebreak. Returns nullopt whenever the whole-doc path is the right answer; a file
// that changed on disk since ingest (span past EOF) also returns nullopt rather than serving a wrong
// slice — the whole-doc path re-reads it honestly.
//
// ─── §RP3.1 — a section's emitted UNIT is its OWN PROSE, and what that replaced ──────────────────
//
// This used to serve each picked section's whole SUBTREE — `[sigStartByte, endByte)`, where ingest
// sets endByte to the next same-or-higher heading's start (src/ingest_docs.h, "(2) section spans +
// hierarchy") — and then dropped any candidate OVERLAPPING an already-kept one, so an ancestor and
// its descendants could never both be served. The comment that justified keeping the ancestor
// claimed "BM25's length normalization puts the tight matching section above its diluted parent".
// MEASURED, it does not: on docs/ARCHITECTURE.md, `## 1. The pipeline` (lines 12-336) outranks all
// seven `###`/`####` subsections nested inside it, wins the overlap, and one retrievable unit then
// costs 325 lines. Which unit an agent could get back was decided by heading depth, not relevance.
//
// A unit is now [heading, next heading of ANY depth) — its own prose. Units therefore TILE the
// document instead of nesting, and that is what deletes the overlap loop outright: there is no
// overlap left to resolve. `## 1. The pipeline` becomes a ~9-line unit and its subsections become
// seven units of their own, each independently admissible.
//
// THE SPAN MISMATCH, and what it costs. Scores are NOT recomputed over the narrowed span. A Section
// symbol's indexed body field is `[sigStartByte, endByte)` — src/lexical.h's scanFileSymbols hands
// scanField exactly that span — i.e. the SUBTREE, and it stays the subtree: narrowing it would reach
// into the field --expand, --grep's enclosing symbol, the quality metrics and the edit verbs all read,
// which is a different change to a different file. So an ancestor RANKS on the words of a subtree that
// other units serve, while the unit it contributes is only its own prose.
//
// §RP3.3 CORRECTS WHAT THIS COMMENT USED TO CLAIM. It said the residual was "bounded and
// self-correcting … the worst case is a heading-plus-intro admitted one slot early". That is false, and
// the counter-example is the documented way to call this verb — CLAUDE.md tells agents to phrase
// --recall as the task IN WORDS. This ranker has no query-side stopword list (the SIRA corpus-statistics
// margin, src/lexical.h's `marginBits`, ships DISARMED), so "the", "does", "are" are live query terms.
// An ancestor's subtree contains every one of them, everywhere, and tf is additive: on
// docs/ARCHITECTURE.md, `crawl order sorted before ids assigned` serves lines 353-369 — the answer —
// while `how does the crawl order get sorted before the ids are assigned` served lines 1-11 and 12-20,
// two heading-plus-intro stubs, at 800, 1200 and 1600 tokens, with the answer appearing only at 2400 and
// third. Not one slot early: the answer was gone at every ceiling an agent would use.
//
// THE FIX IS AT THE RANK, NOT AT ADMISSION, and that was measured rather than assumed. Both cheaper
// repairs are ADMISSION rules and neither works:
//   - a corpus-statistics term margin (keep the ancestor only on a query term with df <= S/2) leaves
//     the reproduction bit-identical. Measured: of the three ancestors it must drop, `# ripwire —
//     architecture` keeps "how" (df 2 of 13 own-prose units) and `## 1. The pipeline` keeps "order"
//     (df 4 of 13). Both are genuine, separating terms genuinely present in the ancestor's own prose.
//   - "keep it only if its own-prose SCORE is positive" is INERT, provably: BM25's idf is
//     ln((S-n+0.5)/(n+0.5)+1) > 0 for every n <= S, so a positive own-prose score is exactly "own prose
//     carries a query term" — the rule already shipping below, restated.
// `## 1. The pipeline`'s own prose really does say "in that order". Admission was right to keep it. What
// was wrong is that it outranked the answer, on evidence held by the seven subsections nested inside it.
//
// SO THE RANK KEY IS ATTRIBUTED: rank = scorer score × (this unit's own-prose evidence ÷ the strongest
// own-prose evidence anywhere in its subtree). A leaf's subtree IS its own prose, so its maximum is
// itself and its key is its score bit-for-bit — the keyword path this verb is strongest at does not
// move. An ancestor whose own prose is the best evidence under it is likewise untouched. Only an
// ancestor ranking on words a descendant carries better is demoted, in proportion to how much better.
// Measured against the shipped ranker on two independent harnesses (details in the round's report):
// heading-as-query over docs/, 456 trials at 800 tokens — NL answer served 76%→80%, served FIRST
// 73%→79%, NL/keyword agreement 75%→80%, keyword answers byte-identical on 98% of trials; and
// unique-term queries, 72 trials at 1600 tokens — NL served FIRST 43%→79%, agreement 42%→78%, keyword
// output byte-identical on 100%. A full own-prose re-rank (discard the scorer's number, rank every unit
// by its own-prose BM25) scores higher still on the first harness — which QUERIES HEADINGS, the field
// that re-rank weighs ×3, so it grades its own bias — and it is a ranking replacement, not a defect fix:
// it moves 9% of keyword answers for no measured keyword gain and belongs to a pre-registered ranking
// round, not to this one.
struct RecallSectionPick
{
    std::uint32_t symIndex = 0;
    std::uint32_t ownEndByte = 0;   // §RP3.1 — the next heading of ANY depth, else this section's own end
    float         score      = 0.f;   // §RP3.3 — the attributed RANK KEY, not a score anything prints
};

// One emitted section unit: where its text sits inside the document-order body, and which source
// lines it is. Byte offsets rather than a second copy of the text — the body is the storage.
struct RecallSectionUnit
{
    std::uint32_t bodyOffset = 0;   // byte offset of this unit's text within RecallSectionBody::body
    std::uint32_t bodyLength = 0;   // its length there
    std::uint32_t lineLo     = 0;   // 1-based first source line of the unit
    std::uint32_t lineHi     = 0;   // 1-based last source line of the unit
};

// What LOAD hands to EMIT. `body` is every selected unit concatenated in DOCUMENT order — which is
// what this function used to return outright — so a document the budget does not bind emits it
// unchanged and no unit arithmetic runs at all. `rankOrder` is the score-descending order the picks
// were sorted into, expressed as indices into `units`; it is the ONE thing EMIT needs in order to
// stop discarding the ranking it was handed.
struct RecallSectionBody
{
    std::string                    body;
    std::vector<RecallSectionUnit> units;              // DOCUMENT order
    std::vector<std::uint32_t>     rankOrder;          // indices into `units`, best-scoring first
    std::size_t                    sectionCount = 0;   // N — heading sections in the document
    std::size_t                    wholeBytes   = 0;   // the document's own size on disk
};

// §RP3.1 — does this span's OWN PROSE carry any of the query's terms? Tokenized with lexical.h's
// `subtokens`, which is the very state machine lexicalScores runs the query through, so "a query term"
// cannot come to mean two different things inside one binary — the rule this file already keeps for
// "inside a fence" (docparse::scanMarkdownFences, the ONE scanner). An empty query never demotes
// anything: there is nothing to have earned a rank against.
// It walks `forEachLexSubtoken` — the state machine `subtokens` itself delegates to — rather than
// calling `subtokens` and intersecting two vectors. Same tokens, same ≥2-byte drop, but no allocation
// and an early exit on the first hit: this runs once per ambiguous ancestor per recalled document, and
// the answer is almost always decided inside the heading line.
// WHICH query term one already-delimited token equals, or `terms.size()` for none. The ONE place a doc
// token is compared against the query table, shared by the boolean test below and §RP3.3's weighted
// counter — two callers that ask different questions of the identical comparison, which is exactly the
// duplicate --quality-delta flagged when they each carried their own copy of this loop. Case folding is
// lexLowerByte, the tokenizer's own; the table's strings are distinct, so the first hit is the only hit.
inline std::size_t recallMatchedTermIndex( std::string_view text, std::size_t tokStartByte, std::size_t tokLen,
                                           const std::vector<std::string>& terms ) noexcept
{
    for( std::size_t t = 0; t < terms.size(); ++t )
    {
        if( terms[t].size() != tokLen )
        {
            continue;
        }
        std::size_t matched = 0;
        while( matched < tokLen
               && terms[t][ matched ] == char( lexLowerByte( static_cast<unsigned char>( text[ tokStartByte + matched ] ) ) ) )
        {
            ++matched;
        }
        if( matched == tokLen )
        {
            return t;
        }
    }
    return terms.size();
}

inline bool ownProseCarriesQueryTerm( std::string_view prose, const std::vector<std::string>& queryToks )
{
    if( queryToks.empty() )
    {
        return true;
    }
    bool isFound = false;
    forEachLexSubtoken( prose, [ & ]( std::size_t tokStartByte, std::size_t tokEndByte )
    {
        const std::size_t tokLen = tokEndByte - tokStartByte;
        if( isFound || tokLen < 2 )
        {
            return;   // the ≥2-byte drop subtokens() applies — the query was tokenized under it too
        }
        isFound = recallMatchedTermIndex( prose, tokStartByte, tokLen, queryToks ) < queryToks.size();
    } );
    return isFound;
}

// §RP3.3 — HOW MUCH of the query each own-prose span carries, on one scale, for one document. BM25 over
// a collection of this document's own-prose units: the same formula src/lexical.h scores symbols with
// (idf = ln((S-n+0.5)/(n+0.5)+1), the same saturating tf and length normalisation, the same
// resolveBm25Params so RIPWIRE_BM25_K1/B move both together), the same forEachLexSubtoken tokenizer and
// the same ≥2-byte drop, and the same field split — the heading construct is the Section symbol's NAME
// and is weighted ×kwName, the rest of the span ×kwBody, exactly as scanFileSymbols weighs them.
//
// The COLLECTION is this document's own units, not the repo, and that is the whole point: the question
// being asked is which section of THIS document the query is about, so the document's own sections are
// the population the term statistics must come from. A word in every section of a document separates
// none of them — idf goes to ~0 for "the" (df = every unit) without a stopword list, which is the same
// idea the SIRA margin registers at corpus level (docs/EVALS.md), derived from the tree in front of it.
//
// This is a RATIO's numerator and denominator, never a printed number and never compared across
// documents, which is what makes the local collection sound: only ratios of two values from THIS call
// are ever read. The ×3/×1 field split was checked for load-bearingness rather than assumed — rerunning
// both harnesses with the heading weighted ×1 gives byte-identical results on every trial at both
// budgets, because a ratio of two spans of the same document is insensitive to it. It mirrors the
// scorer because there is no reason for it not to, not because it was tuned.
//
// Deterministic by construction: integer tf/df in fixed document order, one pass, no map, no clock.
// One field of one unit, weighted into that unit's tf row and its length. Split out of the evidence pass
// below rather than written as a lambda inside it: the tokenizer callback is where all that routine's
// nesting lived, and lifting it leaves both halves flat. Same shape as lexicalScores' `scanTextInto` —
// tokens under 2 bytes dropped exactly as subtokens() drops them, at most one term row per token, and the
// length accumulating the SAME weights the tf does so the BM25 normalisation stays consistent.
inline void accumulateRecallTermFreqs( std::string_view text, int fieldWeight, const std::vector<std::string>& terms,
                                       int* tfRow, int& lengthAccum )
{
    forEachLexSubtoken( text, [ & ]( std::size_t tokStartByte, std::size_t tokEndByte )
    {
        const std::size_t tokLen = tokEndByte - tokStartByte;
        if( tokLen < 2 )
        {
            return;
        }
        lengthAccum += fieldWeight;
        if( const std::size_t t = recallMatchedTermIndex( text, tokStartByte, tokLen, terms ); t < terms.size() )
        {
            tfRow[t] += fieldWeight;
        }
    } );
}

inline std::vector<float> recallOwnProseEvidence( const IngestResult& ing, const std::vector<std::uint32_t>& headingSyms,
                                                  const std::vector<std::uint32_t>& ownEnds, std::string_view raw,
                                                  const std::vector<std::string>& queryToks )
{
    const std::size_t  unitCount = headingSyms.size();
    std::vector<float> evidence( unitCount, 0.f );

    std::vector<std::string> uniqueToks;   // duplicate query words must not double-count df
    for( const std::string& q : queryToks )
    {
        if( std::find( uniqueToks.begin(), uniqueToks.end(), q ) == uniqueToks.end() )
        {
            uniqueToks.push_back( q );
        }
    }
    const std::size_t termCount = uniqueToks.size();
    if( termCount == 0 || unitCount == 0 )
    {
        return evidence;   // nothing to attribute; every caller reads this as "no demotion"
    }

    // SoA, the house layout: tf[unit*termCount + term] weighted, dl[unit] weighted to match.
    constexpr int    kwHeading = 3, kwProse = kLexWeightBody;   // = lexicalScores' kwName / kwBody
    std::vector<int> tf( unitCount * termCount, 0 );
    std::vector<int> dl( unitCount, 0 );
    std::vector<int> df( termCount, 0 );
    for( std::size_t u = 0; u < unitCount; ++u )
    {
        const Symbol& s = ing.symbols[ headingSyms[u] ];
        if( ownEnds[u] <= s.sigStartByte || ownEnds[u] > raw.size() )
        {
            continue;   // a zero-width unit, or a span past a file that moved — no evidence, no demotion
        }
        int* const          tfRow      = tf.data() + u * termCount;
        const std::uint32_t headingEnd = std::min( s.sigEndByte, ownEnds[u] );
        accumulateRecallTermFreqs( raw.substr( s.sigStartByte, headingEnd - s.sigStartByte ), kwHeading, uniqueToks, tfRow, dl[u] );
        if( headingEnd < ownEnds[u] )
        {
            accumulateRecallTermFreqs( raw.substr( headingEnd, ownEnds[u] - headingEnd ), kwProse, uniqueToks, tfRow, dl[u] );
        }
        for( std::size_t t = 0; t < termCount; ++t )
        {
            df[t] += tfRow[t] > 0 ? 1 : 0;
        }
    }

    const Bm25Params bm25Params = resolveBm25Params();   // A4: the ONE definition, shared with the scorer
    double           totalDl    = 0.0;
    for( const int unitDl : dl )
    {
        totalDl += unitDl;
    }
    const double avgdl = totalDl > 0.0 ? totalDl / double( unitCount ) : 1.0;
    for( std::size_t u = 0; u < unitCount; ++u )
    {
        double sum = 0.0;
        for( const std::string& q : queryToks )   // occurrence order: BM25 adds one contribution per occurrence
        {
            const std::size_t t = std::size_t( std::find( uniqueToks.begin(), uniqueToks.end(), q ) - uniqueToks.begin() );
            const double      termFreq = tf[ u * termCount + t ];
            if( termFreq <= 0.0 )
            {
                continue;
            }
            const double idf = std::log( ( double( unitCount ) - df[t] + 0.5 ) / ( df[t] + 0.5 ) + 1.0 );
            sum += idf * ( termFreq * ( bm25Params.k1 + 1.0 ) )
                   / ( termFreq + bm25Params.k1 * ( 1.0 - bm25Params.b + bm25Params.b * dl[u] / avgdl ) );
        }
        evidence[u] = float( sum );
    }
    return evidence;
}

// §RP3.1 — WHICH sections become units, and where each one ends. Split out of buildSectionGranularBody
// so the span rule and the ancestor rule read on their own, ahead of the assembly that turns them into
// text.
struct RecallSectionSelection
{
    std::vector<RecallSectionPick> picks;              // DOCUMENT order
    std::size_t                    sectionCount = 0;   // N — every heading section in the document
};

// EVERY heading section in one markdown file, in BYTE order. ing.symbols is not ordered by byte within a
// file, so byte order is ESTABLISHED here rather than assumed — §RP3.1's unit boundary is "the next
// heading", which is a question about order and would otherwise inherit whatever order the global symbol
// sort left behind.
//
// §RP3.3 — "every" is now literal, and the filter this replaces is why it had to change. It dropped any
// heading whose section body is EMPTY (`sigEndByte >= endByte`), which is a real markdown shape: a heading
// immediately followed, with no blank line, by a same-or-shallower heading. Such a heading was then
// neither counted in N nor treated as a unit boundary, so `--help`'s "up to the next heading of any depth"
// was false twice over — a 4-heading doc reported `3 of 3`, and the served range for the heading BEFORE
// the empty one ran through the empty one's heading line. Both are disclosure defects, not cosmetics: N is
// a denominator and lines= names emitted bytes.
//
// The whole-file node is what that filter was really excluding, and it is excluded by NAMING it rather
// than by a side effect. ingest_docs.h's extractMarkdown builds it with `bodyByte = 0` over `[0, size)`,
// so ingest_model.h's `sigEndByte = (bodyByte > startByte) ? bodyByte : endByte` leaves it with sigStart 0
// and sigEnd == endByte == the file's span; a heading's sigEnd is its heading construct and is strictly
// inside its span unless the section is empty. So "starts at byte 0, has no signature/body split, and ends
// no earlier than any heading in the file" is the file node — and the one heading that can collide is a
// document whose ENTIRE content is a single heading line, which the old filter dropped too. The last
// clause is measured against the file's own SYMBOLS, never against the file's size on disk: the file may
// have grown since it was indexed, and a staleness-dependent test would then admit the file node as a unit
// overlapping every other one, silently breaking the tiling in the one case nothing downstream re-checks.
inline std::vector<std::uint32_t> recallHeadingSections( const IngestResult& ing, std::size_t scoredCount, std::uint32_t fileId )
{
    std::vector<std::uint32_t> headingSyms;
    std::uint32_t              widestEndByte = 0;
    for( std::size_t i = 0; i < ing.symbols.size() && i < scoredCount; ++i )
    {
        const Symbol& s = ing.symbols[ i ];
        if( s.fileId == fileId && s.kind == SymKind::Section && s.lang == Lang::Markdown )
        {
            widestEndByte = std::max( widestEndByte, s.endByte );
            headingSyms.push_back( std::uint32_t( i ) );
        }
    }
    headingSyms.erase( std::remove_if( headingSyms.begin(), headingSyms.end(), [ & ]( std::uint32_t i ) noexcept
    {
        const Symbol& s = ing.symbols[i];
        return s.sigStartByte == 0 && s.sigEndByte >= s.endByte && s.endByte >= widestEndByte;
    } ), headingSyms.end() );
    std::sort( headingSyms.begin(), headingSyms.end(), [ & ]( std::uint32_t a, std::uint32_t b ) noexcept
    {
        if( ing.symbols[a].sigStartByte != ing.symbols[b].sigStartByte )
        {
            return ing.symbols[a].sigStartByte < ing.symbols[b].sigStartByte;
        }
        return a < b;   // two headings at one byte cannot be ordered by position; index keeps the sort TOTAL
    } );
    return headingSyms;
}

// §RP3.1 — each heading's OWN-PROSE end: the next heading of ANY depth, else its own section end. Computed
// over EVERY heading and not only the matching ones, because a unit's boundary is the next heading whether
// or not that heading scored — which is what makes the units TILE, and why no overlap pass follows them.
inline std::vector<std::uint32_t> recallOwnEndBytes( const IngestResult& ing, const std::vector<std::uint32_t>& headingSyms )
{
    std::vector<std::uint32_t> ownEnds( headingSyms.size(), 0 );
    for( std::size_t p = 0; p < headingSyms.size(); ++p )
    {
        const Symbol& s = ing.symbols[ headingSyms[p] ];
        ownEnds[p]      = ( p + 1 < headingSyms.size() )
                              ? std::min( ing.symbols[ headingSyms[ p + 1 ] ].sigStartByte, s.endByte )
                              : s.endByte;
    }
    return ownEnds;
}

// §RP3.3 — ATTRIBUTE one section's rank. The denominator is the strongest own-prose evidence anywhere in
// this section's SUBTREE, itself included, so a leaf — and any ancestor that is the best evidence under
// itself — divides by its own value and keeps the scorer's number bit-for-bit. `headingSyms` is in byte
// order and a section's descendants are the contiguous run starting inside its span, which is the same
// walk the admission test above makes. A subtree carrying no evidence at all is possible, since the scorer
// also reads the path and basename fields, which are not prose; it demotes nothing, because there is no
// attribution to make and inventing one would be a guess.
inline float recallAttributedScore( const IngestResult& ing, const std::vector<std::uint32_t>& headingSyms,
                                    const std::vector<float>& ownEvidence, std::size_t p, float scorerScore )
{
    const std::uint32_t subtreeEnd         = ing.symbols[ headingSyms[p] ].endByte;
    double              strongestInSubtree = ownEvidence[p];
    for( std::size_t q = p + 1; q < headingSyms.size() && ing.symbols[ headingSyms[q] ].sigStartByte < subtreeEnd; ++q )
    {
        strongestInSubtree = std::max( strongestInSubtree, double( ownEvidence[q] ) );
    }
    if( strongestInSubtree <= 0.0 )
    {
        return scorerScore;
    }
    return float( double( scorerScore ) * ( double( ownEvidence[p] ) / strongestInSubtree ) );
}

inline RecallSectionSelection selectRecallSectionPicks( const IngestResult& ing, const std::vector<float>& scores,
                                                        std::uint32_t fileId, std::string_view raw,
                                                        const std::vector<std::string>& queryToks )
{
    const std::vector<std::uint32_t> headingSyms = recallHeadingSections( ing, scores.size(), fileId );
    const std::vector<std::uint32_t> ownEnds     = recallOwnEndBytes( ing, headingSyms );
    const std::vector<float>         ownEvidence = recallOwnProseEvidence( ing, headingSyms, ownEnds, raw, queryToks );

    // §RP3.1 — own-prose spans, computed over EVERY heading and not only the matching ones: a unit's
    // boundary is the next heading in the document whether or not that heading scored. The result is a
    // TILING, which is why no overlap pass follows it.
    //
    // THE ANCESTOR RULE, and it is the crux of §RP3.1. A section's score is computed over its SUBTREE
    // (see the residual note above), so an ancestor can score on words that live only in a child. Two
    // rules were built and measured before this one, and each broke a real gate by getting exactly one
    // of the two cases wrong:
    //
    //   - keep every positive-scoring section (a plain tiling). test/mdsectionfix/guide.md then answers
    //     the single-token query `zqcachewarmbody` with `# Orientation Guide`'s prose attached, whose
    //     own marker is a DIFFERENT token — the sibling/parent prose that section-granular recall exists
    //     to stop serving (test/mdsectioncheck.sh).
    //   - drop every section that has a positive-scoring descendant (most-specific-wins). That one makes
    //     score and emitted text agree exactly, and it loses answers: on test/fixture/notes.md it drops
    //     `# Geometry Fixture`, whose own prose is the ONLY place the query term "geometry" occurs, for
    //     a `## Symbols` child that matched "perimeter" alone. Across this repo's docs it lost 9,577
    //     source lines and gained none.
    //
    // Neither is guessing at the same thing: the question both were approximating is whether the
    // ancestor's OWN PROSE earned its rank, and that is answerable exactly rather than by proxy. An
    // ancestor with a scoring descendant is kept only when its own prose carries a query term of its
    // own; otherwise the descendant holds the answer and the ancestor is the diluted parent the old
    // overlap rule used to serve INSTEAD of it. Both fixtures above come out right, for the reason they
    // are right, and no unit is ever emitted whose own prose has nothing to do with the query.
    //
    // §RP3.3 leaves this ADMISSION rule exactly as it stands, and the measurement above is why: the two
    // ancestors the natural-language reproduction serves both carry a genuine query term of their own
    // ("order" is literally in `## 1. The pipeline`'s "Five stages, in that order"), so no term-presence
    // test can drop them without becoming the most-specific-wins rule that already lost 9,577 lines.
    // What §RP3.3 changes is the RANK KEY below. It changes no admission decision at all: for any fixed
    // heading population the SET of picks is what it always was and only the ORDER can move, which is why
    // both fixtures named above keep their behaviour by construction rather than by re-measurement.
    std::vector<char> isScoring( headingSyms.size(), 0 );
    for( std::size_t p = 0; p < headingSyms.size(); ++p )
    {
        isScoring[p] = scores[ headingSyms[p] ] > 0.f ? 1 : 0;
    }
    std::vector<RecallSectionPick> picks;
    for( std::size_t p = 0; p < headingSyms.size(); ++p )
    {
        if( !isScoring[p] )
        {
            continue;
        }
        const Symbol&       s      = ing.symbols[ headingSyms[p] ];
        const std::uint32_t ownEnd = ownEnds[p];
        if( ownEnd <= s.sigStartByte || ownEnd > raw.size() )
        {
            continue;   // a zero-width unit (two headings at one byte), or a span past a file that moved
        }
        // a section's descendants are the run of headings starting inside its SUBTREE span, contiguous in
        // byte order — so this stops at the first heading past the subtree, not at the end of the file.
        bool hasScoringDescendant = false;
        for( std::size_t q = p + 1; q < headingSyms.size() && ing.symbols[ headingSyms[q] ].sigStartByte < s.endByte; ++q )
        {
            if( isScoring[q] )
            {
                hasScoringDescendant = true;
                break;
            }
        }
        if( hasScoringDescendant
            && !ownProseCarriesQueryTerm( raw.substr( s.sigStartByte, ownEnd - s.sigStartByte ), queryToks ) )
        {
            continue;   // it ranked on a child's words; that child is a pick in its own right
        }

        picks.push_back( { headingSyms[p], ownEnd,
                           recallAttributedScore( ing, headingSyms, ownEvidence, p, scores[ headingSyms[p] ] ) } );
    }
    return { std::move( picks ), headingSyms.size() };
}

inline std::optional<RecallSectionBody> buildSectionGranularBody(
        const IngestResult& ing, const std::vector<float>& scores, std::uint32_t fileId, RedactCounts* redact,
        const std::vector<std::string>& queryToks )
{
    if( ing.docText.find( fileId ) != ing.docText.end() )
    {
        return std::nullopt;   // extracted-text docs have no markdown heading sections
    }
    // the file is read BEFORE the selection, because §RP3.1's ancestor rule is a question about the
    // document's TEXT (does this heading's own prose carry a query term) and not only about the index.
    std::ifstream in( diskPath( ing, fileId ), std::ios::binary );
    if( !in )
    {
        return std::nullopt;
    }
    std::ostringstream ss;
    ss << in.rdbuf();
    const std::string raw = ss.str();

    const RecallSectionSelection          selection = selectRecallSectionPicks( ing, scores, fileId, raw, queryToks );
    const std::vector<RecallSectionPick>& picks     = selection.picks;
    if( picks.empty() )
    {
        return std::nullopt;
    }

    // the ranking, kept as a permutation rather than applied to `picks`: EMIT needs the units in DOCUMENT
    // order to read and in SCORE order to choose, and materializing both beats re-deriving either.
    std::vector<std::uint32_t> rankOrder( picks.size() );
    for( std::uint32_t r = 0; r < std::uint32_t( rankOrder.size() ); ++r )
    {
        rankOrder[r] = r;
    }
    std::sort( rankOrder.begin(), rankOrder.end(), [ & ]( std::uint32_t a, std::uint32_t b ) noexcept
    {
        if( picks[a].score != picks[b].score )
        {
            return picks[a].score > picks[b].score;
        }
        return a < b;   // `picks` is already in byte order, so its index IS the byte-position tiebreak
    } );

    RecallSectionBody out;
    out.sectionCount = selection.sectionCount;
    out.wholeBytes   = raw.size();
    out.rankOrder    = std::move( rankOrder );
    out.units.reserve( picks.size() );
    for( const RecallSectionPick& p : picks )   // document order — `picks` was built in it
    {
        const Symbol& s = ing.symbols[ p.symIndex ];
        if( p.ownEndByte > raw.size() || s.sigStartByte >= p.ownEndByte )
        {
            return std::nullopt;   // the file moved under us — fall back to the honest whole-doc re-read
        }
        std::string slice = raw.substr( s.sigStartByte, p.ownEndByte - s.sigStartByte );
        redactInPlace( slice, redact );
        if( !out.body.empty() && out.body.back() != '\n' )
        {
            out.body += '\n';
        }
        RecallSectionUnit unit;
        unit.bodyOffset = std::uint32_t( out.body.size() );
        unit.bodyLength = std::uint32_t( slice.size() );
        unit.lineLo     = layout::lineOf( raw, s.sigStartByte );
        unit.lineHi     = layout::lineOf( raw, p.ownEndByte - 1 );   // last INCLUDED byte — ownEndByte is exclusive
        out.body += slice;
        out.units.push_back( unit );
    }
    return out;
}

// §RP4 — the section note, in its two forms, in ONE place so the budget can price both of them.
//
// Unbound (emitted == selected) it is byte for byte the note this verb has always printed:
// `[sections: R of N, section-granular; whole doc B B; lines="…"]`. Bound, it stops letting the first
// number pass for a selection count and says which of the three each number is:
// `[sections: S of R selected (N in doc), …; dropped_by_budget=D]`. The extra clauses are charged only
// to a run that actually dropped a unit — the same silence-means-nothing-happened rule
// optionalRecallAttr spells out for the header's own attributes.
//
// WHY `dropped_by_budget=D` CARRIES NO `next=`, deliberately, against METHODOLOGY §9.3's preference for
// one. §9.3 wants "the one deterministic call that fetches it", and this cut has no such call to name.
// The unit set a document is served is decided by allocateRecallShares' §C4 water-filling over the WHOLE
// bundle, so the only knob that could restore a dropped unit — `--max-tokens=N` — is not invertible from
// inside one document: the same N buys a different share as the document SET changes, and cross-document
// monotonicity is explicitly NOT claimed (a doc's share can fall as the ceiling rises). Printing a
// computed N would therefore be a guess wearing a disclosure's clothes, which non-negotiable #3 forbids
// more firmly than §9.3 asks for the attribute. Naming the dropped ranges instead is exact but not cheap:
// on a 300-section document the full lines= list is the ~2.7 KB that recallUnitCostBytes exists to stop
// charging up front. What IS both exact and cheap is already printed — S, R, N and D — so the honest
// posture is D without a next=, and a follow-up flag that made one derivable (a section offset, the way
// --tree pages with next_offset=) is a verb-surface change, not this note's to invent.
inline std::string formatRecallSectionNote( std::size_t emittedCount, std::size_t selectedCount, std::size_t sectionCount,
                                            std::size_t wholeBytes, std::string_view linesAttr )
{
    std::string note = "  [sections: ";
    if( emittedCount < selectedCount )
    {
        note += std::to_string( emittedCount ) + " of " + std::to_string( selectedCount ) + " selected ("
                + std::to_string( sectionCount ) + " in doc)";
    }
    else
    {
        note += std::to_string( selectedCount ) + " of " + std::to_string( sectionCount );
    }
    note += ", section-granular; whole doc " + std::to_string( wholeBytes ) + " B; lines=\"";
    note += linesAttr;
    note += "\"";
    if( emittedCount < selectedCount )
    {
        note += "; dropped_by_budget=" + std::to_string( selectedCount - emittedCount );
    }
    note += "]";
    return note;
}

// The most the bound form can add to the unbound one the budget was already charged for, so EMIT can
// reserve it and still land under the ceiling. DERIVED rather than measured or guessed: against
// `R of N` the bound form spells `S of R selected (N in doc)` — 19 bytes of extra prose
// (" selected (" is 11, " in doc)" is 8) plus one extra number, S, whose digit count cannot exceed
// R's — and then appends `; dropped_by_budget=D`, 20 bytes of prose plus D, which is R-S and so
// cannot out-digit R either. Its lines= list names a SUBSET of the unbound one's ranges, so that term
// can only shrink. Hence 39 + 2·|R|, independent of the budget and of which units the budget admits.
inline std::size_t recallSectionNoteGrowthBound( std::size_t selectedCount )
{
    return 39 + 2 * std::to_string( selectedCount ).size();
}

// §RP4 — the note MINUS its lines= list: the part a document owes whatever the budget admits. The
// ranges are not charged here; they ride with the units that produce them (recallUnitCostBytes).
inline std::size_t recallSectionNoteFixedBytes( const RecallSectionBody& sec )
{
    return formatRecallSectionNote( sec.units.size(), sec.units.size(), sec.sectionCount, sec.wholeBytes, "" ).size();
}

// §RP4 — what ONE unit costs the budget: its own bytes, the newline that may join it to the unit
// before it, and the `LO-HI,` it adds to the note's lines= list.
//
// Charging the range to the UNIT rather than to the document's fixed overhead is not bookkeeping
// taste; it fixes a measured defect. A 300-section document's FULL-selection lines= list is ~2.7 KB.
// Charged up front against that document's ~3.4 KB payload budget it left 168 bytes for prose — so
// `--max-tokens=1500` cut the top-ranked section three lines in, and the budget went almost entirely
// on an attribute that, once the budget bound, listed three ranges and cost thirty bytes. Charged per
// unit the accounting is exact in both directions, and because it is still a FIXED per-unit price the
// admitted set remains a prefix of the rank order, and so remains monotone in the budget.
inline std::size_t recallUnitCostBytes( const RecallSectionUnit& unit )
{
    return std::size_t( unit.bodyLength ) + 1
           + std::to_string( unit.lineLo ).size() + std::to_string( unit.lineHi ).size() + 2;
}

// §RP3.2 — WHICH units an allowance admits: walk the RANK order, take each whole unit while it fits,
// and STOP at the first one that does not. No skip-ahead to a smaller unit further down the ranking.
//
// That refusal is the point, and it buys a guarantee with wasted bytes rather than leaving an
// optimisation on the table. Every unit is charged a FIXED price — its own bytes plus the single
// newline that may be needed to join it to whatever precedes it — so "admit while it fits, stop at the
// first non-fit" is exactly "the longest PREFIX of the rank order whose cumulative price fits".
// Prefixes of one fixed order are nested as the allowance grows, so a larger --max-tokens admits a
// strict SUPERSET of what a smaller one did and a bigger ceiling can never return less. Best-fit
// packing would spend the remainder, and would let a unit served at 4000 tokens VANISH at 8000 because
// a different combination happened to pack better. The remainder is disclosed (dropped_by_budget=);
// the non-monotonicity would not have been.
//
// The per-unit price (recallUnitCostBytes) over-charges by at most a byte or two — the first admitted
// unit needs no joining newline, and the last needs no comma in lines=. It is deliberately fixed rather
// than exact: a price that depended on which neighbours were admitted would stop being a prefix rule,
// and the guarantee above is a property of the prefix, not of the arithmetic.
struct RecallUnitAdmission
{
    std::vector<char> isAdmitted;          // per unit, DOCUMENT order (RecallSectionBody::units' own indexing)
    std::size_t       admittedCount = 0;
};

inline RecallUnitAdmission admitRecallUnits( const RecallSectionBody& sec, std::size_t allowanceBytes )
{
    RecallUnitAdmission out;
    out.isAdmitted.assign( sec.units.size(), 0 );
    std::size_t spentBytes = 0;
    for( const std::uint32_t u : sec.rankOrder )
    {
        const std::size_t unitCost = recallUnitCostBytes( sec.units[u] );
        if( spentBytes + unitCost > allowanceBytes )
        {
            break;
        }
        spentBytes        += unitCost;
        out.isAdmitted[u]  = 1;
        ++out.admittedCount;
    }
    return out;
}

// Re-assemble an admitted set into DOCUMENT order for reading, and name exactly the line ranges it
// contains. ONE routine for both the whole selection and a budget-trimmed subset, so "the bytes when
// nothing binds" cannot drift from "the bytes when something does" — the byte-identity invariant is a
// consequence of there being one assembler, not of two of them being kept in step by hand.
inline std::pair<std::string, std::string> composeRecallUnits( const RecallSectionBody& sec, const std::vector<char>& isAdmitted )
{
    std::string body;
    std::string linesAttr;   // "LO-HI[,LO-HI…]", one range per EMITTED unit, document order
    for( std::size_t u = 0; u < sec.units.size(); ++u )
    {
        if( !isAdmitted[u] )
        {
            continue;
        }
        const RecallSectionUnit& unit = sec.units[u];
        if( !body.empty() && body.back() != '\n' )
        {
            body += '\n';
        }
        body.append( sec.body, unit.bodyOffset, unit.bodyLength );
        if( !linesAttr.empty() )
        {
            linesAttr += ",";
        }
        linesAttr += std::to_string( unit.lineLo ) + "-" + std::to_string( unit.lineHi );
    }
    return { std::move( body ), std::move( linesAttr ) };
}

// §RP4 — the note for the WHOLE selection: what `overhead` is charged at LOAD, and what EMIT prints
// unchanged whenever the budget does not bind. It goes through the SAME assembler EMIT uses, over an
// all-admitted mask, so the full lines= list cannot drift from a trimmed one by being written twice —
// and the VERIFY states the byte-identity invariant the twelve standing recall gates rest on, at the
// one seam where it could break.
inline std::string fullRecallSectionNote( const RecallSectionBody& sec )
{
    const std::vector<char> allAdmitted( sec.units.size(), 1 );
    const auto [ fullBody, fullLines ] = composeRecallUnits( sec, allAdmitted );
    VERIFY( fullBody == sec.body );
    return formatRecallSectionNote( sec.units.size(), sec.units.size(), sec.sectionCount, sec.wholeBytes, fullLines );
}

// §RP3.2 — ONE document's section-granular emission when its allowance cannot hold it whole: which
// units survive, the note that names them, and the marker for the single within-unit cut that can still
// happen. Split out of buildRecall's EMIT loop because it is a policy rather than a step of that loop —
// the loop's other two paths (nothing to cut; the heading-less whole-document prefix) are two lines each
// beside it, and burying a policy between them is what made the old loop unreadable.
struct RecallSectionEmission
{
    std::string body;                // the admitted units, document order
    std::string sectionNote;         // §RP4 — the note for what was ACTUALLY served
    std::string truncNote;           // "" unless the degenerate single-unit prefix cut fired
    bool        wasReduced = false;  // did anything get dropped or cut (the header's truncated= tally)
};

inline RecallSectionEmission emitRecallSectionUnits( const RecallSectionBody& sec, std::size_t allocBytes )
{
    // The note GROWS when it takes its bound form, and `overhead` was charged the unbound one — so that
    // growth is reserved out of the allowance before a single unit is admitted. The bound is DERIVED, not
    // sampled: recallSectionNoteGrowthBound.
    const std::size_t         noteGrowth = recallSectionNoteGrowthBound( sec.units.size() );
    const std::size_t         allowance  = allocBytes > noteGrowth ? allocBytes - noteGrowth : 0;
    const RecallUnitAdmission admitted   = admitRecallUnits( sec, allowance );

    RecallSectionEmission out;
    if( admitted.admittedCount > 0 )
    {
        auto [ trimmedBody, linesAttr ] = composeRecallUnits( sec, admitted.isAdmitted );
        out.body        = std::move( trimmedBody );
        out.sectionNote = formatRecallSectionNote( admitted.admittedCount, sec.units.size(), sec.sectionCount,
                                                  sec.wholeBytes, linesAttr );
        out.wasReduced  = admitted.admittedCount < sec.units.size();
        return out;
    }

    // DEGENERATE — not even the top-ranked unit fits its share. Prefix-cut THAT unit. This is the one place
    // a prefix cut survives on the section path, and it is still strictly better than the one it replaces:
    // the reader gets the front of the best-scoring section instead of the front of the file, which on a
    // document with a table of contents was the table of contents.
    const RecallSectionUnit& top       = sec.units[ sec.rankOrder[0] ];
    const std::size_t        keepBytes = allowance > kRecallTruncNoteBytes ? allowance - kRecallTruncNoteBytes
                                                                          : kRecallMinBodyBytes;
    std::string unitText( sec.body, top.bodyOffset, top.bodyLength );
    auto [ truncMarker, sourceKeptBytes ] = truncateRecallBody( unitText, keepBytes );
    out.truncNote                         = std::move( truncMarker );

    // §RP4 — lines= names what SURVIVED, not what was picked: the unit's own first line plus however many
    // line breaks made it past the cut, never more than the unit itself spans. A cut that kept no source
    // byte at all emits no range, because there is then no line to name.
    //
    // §RP4.1 — the count runs over `kept` MINUS ITS LAST BYTE, which is the whole fix and not an
    // off-by-one taste. findRecallBoundaryCut lands the cut immediately AFTER a newline (paragraph +2,
    // sentence +2, bare +1), so the last kept byte is a '\n' and the line it opens is the first line NOT
    // served. Counting every '\n' in the prefix therefore named a line whose bytes never reached stdout —
    // a disclosure claiming output it did not produce, which is the one thing this file's non-negotiable
    // #3 forbids outright. Reproduced before the fix: a section at line 3 followed by 400 two-line
    // paragraphs, at --max-tokens=400, disclosed lines="3-10" with source line 9 the last byte served.
    // Dropping the final byte is exactly composeRecallUnits' own rule — it derives lineHi from
    // `ownEndByte - 1`, the last INCLUDED byte — so the two paths now compute the same thing the same way.
    std::string linesAttr;
    std::size_t emittedCount = 0;
    if( sourceKeptBytes > 0 )
    {
        const std::string_view kept( unitText.data(), std::min( sourceKeptBytes, unitText.size() ) );
        // [0, n-1): the LAST kept byte is the '\n' that OPENS a line nothing served. Written as a guarded
        // substr rather than `kept.size() - 1`, because a size_t decrement that is merely provably safe
        // today is the shape -fsanitize=integer exists to catch tomorrow.
        const std::string_view served = kept.empty() ? kept : kept.substr( 0, kept.size() - 1 );
        const std::uint32_t    keptHi = top.lineLo + std::uint32_t( std::count( served.begin(), served.end(), '\n' ) );
        linesAttr    = std::to_string( top.lineLo ) + "-" + std::to_string( std::min( keptHi, top.lineHi ) );
        emittedCount = 1;
    }
    out.sectionNote = formatRecallSectionNote( emittedCount, sec.units.size(), sec.sectionCount, sec.wholeBytes, linesAttr );
    out.body        = std::move( unitText );
    out.wasReduced  = true;
    return out;
}

// §C4 (harvest-B) — DIVIDE the payload budget across the selected documents, instead of handing it to
// document #1. What this replaces, and why it was a defect rather than a policy:
//
// The budget loop used to be greedy first-fit — walk the ranking, give each document all the room left,
// and `break` the moment one had to be truncated. One long top hit therefore consumed the entire budget
// and every other matching document was reported as "capped". Measured on the operator's own 157-document
// agent-memory directory (`--top-k=6 --max-tokens=5000`): `total=157 shown=1 truncated=1`, the single
// emitted document being 9,859 bytes of one 17 KB note. On a synthetic corpus of one huge on-topic
// document plus five 150-byte on-topic documents, `--max-tokens` of 2000, 5000 and 8000 all returned
// `shown=1`: 750 bytes of matching prose was dropped from a 20,000-byte budget, and TRIPLING the budget
// bought more of document #1 and never a second document. The number of documents an agent got back was
// decided by the size of the top hit, not by the budget it asked for.
//
// The allocation is WATER-FILLING, which is what makes the fix safe in both directions:
//   1. Serve a rank PREFIX — the most documents that can each be given a slice worth reading
//      (kRecallShareFloorBytes). Ranking still decides WHO; the budget decides HOW MANY.
//   2. Divide the remaining bytes equally, then let every document that needs LESS than its share take
//      only what it needs and hand the surplus back to the ones that need more. Repeat until no document
//      is satisfied by the current share. So five 150-byte notes cost 750 bytes, not five equal shares —
//      spreading never wastes budget on documents that are already whole.
// The equal share is therefore an upper bound, not a quota, and it is monotone: a bigger budget can never
// return fewer documents (gate: recallbudgetcheck §8.9).
//
// The opposite failure — dividing a budget by --top-k when only one document matched, so a single-hit
// query gets one stub and wastes the rest of the ceiling — is what the prefix rule in step 1 exists to
// prevent, and it has its own arm (§8.4). A document that alone cannot clear the share floor still gets
// served under the last-resort kRecallMinBodyBytes floor rather than nothing at all.
//
// `overhead[i]` is what document i costs BEFORE any body byte (its separator line plus the two newlines
// that frame the body); `demand[i]` is its full body size. `alloc[i]` is the returned allowance for that
// document's body PLUS its truncation marker, so the sum of overhead + alloc over the served prefix never
// exceeds `payloadBudget` — the caller's ceiling is under-used, never overshot.
struct RecallShares
{
    std::vector<std::size_t> alloc;              // per-document allowance (body + truncation marker), rank order
    std::size_t              servedCount = 0;    // the rank prefix that got an allowance at all
    std::size_t              shareBytes  = 0;    // the equal share that BOUND a document; 0 = it bound none
};

// §C4 step 1 — HOW MANY documents the budget is divided among: the longest rank PREFIX in which every
// document can still be served a slice worth reading. A document smaller than the share floor costs only
// what it IS, so a run of short memory notes never shortens the prefix.
//
// The last-resort clause is the anti-regression: a budget too small for even ONE readable slice still
// serves the top document down to kRecallMinBodyBytes, exactly as the pre-§C4 greedy loop did. Serving
// nothing where something fits would be a regression dressed as a policy.
inline std::size_t recallServedPrefix( const std::vector<std::size_t>& overhead, const std::vector<std::size_t>& demand,
                                       std::size_t payloadBudget )
{
    const std::size_t shareFloorCost = kRecallShareFloorBytes + kRecallTruncNoteBytes;
    std::size_t       served         = 0;
    std::size_t       floorSum       = 0;
    for( std::size_t i = 0; i < demand.size(); ++i )
    {
        const std::size_t minCost = overhead[i] + std::min( demand[i], shareFloorCost );
        if( floorSum + minCost > payloadBudget )
        {
            break;
        }
        floorSum += minCost;
        ++served;
    }
    const std::size_t lastResortCost = kRecallMinBodyBytes + kRecallTruncNoteBytes;
    if( served == 0 && !demand.empty() && overhead[0] + std::min( demand[0], lastResortCost ) <= payloadBudget )
    {
        served = 1;
    }
    return served;
}

// §C4 step 2 — HOW MUCH each of them gets. Classic water-filling over the bytes left once the prefix's fixed
// overhead is paid: divide equally, let every document that needs LESS than its share take only what it
// needs, hand the surplus back, repeat. `alloc` is filled for the satisfied documents; the returned share is
// what each UNSATISFIED one is bound to (0 = every document was satisfied, so nothing was bound).
//
// The share is non-decreasing across passes — a document is removed only when it takes at or below the
// current average — which is what guarantees the final share is never below the floor recallServedPrefix
// admitted the prefix on, so a truncated document is always served at least kRecallShareFloorBytes.
inline std::size_t waterFillRecallShares( const std::vector<std::size_t>& demand, std::size_t served, std::size_t avail,
                                          std::vector<char>& isSatisfied, std::vector<std::size_t>& alloc )
{
    std::size_t remaining   = avail;
    std::size_t unsatisfied = served;
    std::size_t share       = 0;
    while( unsatisfied > 0 )
    {
        share               = remaining / unsatisfied;
        std::size_t settled = 0;
        for( std::size_t i = 0; i < served; ++i )
        {
            if( isSatisfied[i] || demand[i] > share )
            {
                continue;
            }
            alloc[i]       = demand[i];
            isSatisfied[i] = 1;
            remaining     -= demand[i];
            --unsatisfied;
            ++settled;
        }
        if( settled == 0 )
        {
            break;   // nobody fits inside the share any more — the rest are bound by it
        }
    }
    if( unsatisfied == 0 )
    {
        return 0;   // every document whole: no share bound anything, and the header says nothing (H9)
    }
    // Whoever is left splits the final share; the integer remainder goes to the highest-ranked of them,
    // which is both the useful choice and a deterministic one (no ties to break).
    std::size_t surplus = remaining - share * unsatisfied;
    for( std::size_t i = 0; i < served; ++i )
    {
        if( isSatisfied[i] )
        {
            continue;
        }
        alloc[i] = share + ( surplus > 0 ? 1 : 0 );
        surplus -= ( surplus > 0 ? 1 : 0 );
    }
    return share;
}

inline RecallShares allocateRecallShares( const std::vector<std::size_t>& overhead,
                                          const std::vector<std::size_t>& demand, std::size_t payloadBudget )
{
    VERIFY( overhead.size() == demand.size() );

    RecallShares out;
    out.alloc.assign( demand.size(), 0 );
    out.servedCount = payloadBudget == 0 ? 0 : recallServedPrefix( overhead, demand, payloadBudget );
    if( out.servedCount == 0 )
    {
        return out;
    }

    // The bytes left for bodies once the served prefix's separators are paid for. recallServedPrefix admitted
    // the prefix only if overhead + a floor per document fitted, so this subtraction cannot underflow.
    std::size_t avail = payloadBudget;
    for( std::size_t i = 0; i < out.servedCount; ++i )
    {
        avail -= overhead[i];
    }
    std::vector<char> isSatisfied( out.servedCount, 0 );
    out.shareBytes = waterFillRecallShares( demand, out.servedCount, avail, isSatisfied, out.alloc );
    return out;
}

// Build the recall bundle IN MEMORY: each top file's path + relevance + body, best-first. `maxBytes` (0 =
// no cap) SHAPES it — the budget is DIVIDED across the selected docs by allocateRecallShares above (docs
// past the served rank prefix are dropped from the BOTTOM of the ranking; any doc may be truncated within
// itself), all DISCLOSED (per-doc `[truncated: …]`, header `capped=1`/`truncated=N`/`share_bytes=N`, a
// closing `(capped: …)` note). Building before writing is what lets --token-budget gate BEFORE a byte is emitted.
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

    // §C4 — LOAD, then ALLOCATE, then EMIT. The three used to be one greedy pass, and that is precisely why
    // document #1 could take the whole budget: a loop that decides one document's slice from `payload.size()`
    // alone cannot know that five more documents are waiting behind it. Sizing every candidate BEFORE any
    // byte is committed is what makes a fair division expressible at all.
    // §RP4 — the section note is no longer baked into `sep` at LOAD. It reports what the budget let
    // through, and at LOAD the budget is not known yet: allocateRecallShares has not run. `sep` therefore
    // carries everything that IS decided at load time (path, relevance, the generated-doc verdict) and the
    // note rides beside it, in its full-selection form, until EMIT either confirms or rewrites it. What
    // `overhead` charges is the note's FIXED part only — the lines= ranges are priced per unit, for the
    // reason recallUnitCostBytes states.
    struct LoadedDoc
    {
        std::string                      sep;           // "━━ path (relevance …) ━━[generated_demoted: …]"
        std::string                      sectionNote;   // §RP4, full-selection form; "" on the whole-doc path
        std::string                      wholeBody;     // the whole-doc path's prose
        std::optional<RecallSectionBody> sections;      // the section path's prose AND its units
        std::size_t                      demandBytes = 0;   // what serving it WHOLE costs the budget

        // The emitted prose, wherever it lives. An accessor rather than a second member holding a copy of a
        // 600 KB string that then has to be kept in step with the units indexing into it.
        std::string&       body()       { return sections ? sections->body : wholeBody; }
        const std::string& body() const { return sections ? sections->body : wholeBody; }
    };
    // §RP3.1 — the query's subtokens, computed ONCE for the whole bundle through lexical.h's `subtokens`,
    // the same tokenizer lexicalScores splits the query with. The section path uses it to ask whether an
    // ancestor heading's own prose earned the rank its subtree won it.
    std::vector<std::string> queryToks;
    subtokens( task, queryToks );

    std::vector<LoadedDoc>   loadedDocs;
    std::vector<std::size_t> overhead;   // per document, the bytes it costs before any body byte
    std::vector<std::size_t> demand;     // per document, its full body size
    loadedDocs.reserve( top.size() );
    overhead.reserve( top.size() );
    demand.reserve( top.size() );
    for( const Recalled& r : top )
    {
        // V5: fileId is an INDEX into files[], and this VERIFY guards the NEAREST dereference — which is
        // loadRecallBody's, not the separator's. It sat one call below, i.e. one dereference late: the
        // invariant was true and correctly a VERIFY, but the first read it protected had already happened.
        VERIFY( r.fileId < ing.files.size() );
        LoadedDoc doc;
        if( auto granular = buildSectionGranularBody( ing, scores, r.fileId, redact, queryToks ) )
        {
            doc.sections    = std::move( granular );
            doc.sectionNote = fullRecallSectionNote( *doc.sections );
            for( const RecallSectionUnit& unit : doc.sections->units )
            {
                doc.demandBytes += recallUnitCostBytes( unit );
            }
        }
        else if( auto loaded = loadRecallBody( ing, r.fileId, redact ) )
        {
            doc.wholeBody   = std::move( *loaded );
            doc.demandBytes = doc.wholeBody.size();
        }
        else
        {
            continue;   // unreadable on disk: skipped, never a stub — counted by the capped note's budgetOmitted
        }

        const std::string      demotedNote = formatDemotedNote( r.generated );
        const std::string_view sepPath     = rootArg.empty() ? std::string_view( ing.files[ r.fileId ] )
                                                             : rw::sarif::rootRelativeUri( ing.files[ r.fileId ], recallRootPrefix );
        doc.sep = formatRecallSeparator( sepPath, r.score, demotedNote );
        // 2 = the separator's own newline + the body's. The section note's FIXED part is overhead; its
        // lines= ranges are demand, priced with the units that put them there.
        overhead.push_back( doc.sep.size() + 2 + ( doc.sections ? recallSectionNoteFixedBytes( *doc.sections ) : 0 ) );
        demand.push_back( doc.demandBytes );
        loadedDocs.push_back( std::move( doc ) );
    }

    const RecallShares shares = maxBytes ? allocateRecallShares( overhead, demand, payloadBudget ) : RecallShares{};
    const std::size_t  emitCount = maxBytes ? shares.servedCount : loadedDocs.size();
    shape.shareBytes = shares.shareBytes;   // H9: 0 = the share bound nothing, and the header then says nothing

    // §RP3.2 — EMIT. The budget used to reach this loop as a byte count applied to a document-ORDERED
    // concatenation, so the prefix cut below was a document-order cut and the ranking computed at LOAD was
    // discarded exactly when it mattered: on docs/COMMANDS.md the `--field-affinity` section was SELECTED
    // and never served at any ceiling below the whole 616 KB file, because the table of contents sat in
    // front of it. Section-granular documents now spend their allowance in RANK order, whole units at a
    // time (admitRecallUnits), and only a document with no units at all — heading-less, or docparse'd
    // extracted text — still takes a prefix cut, where a prefix is the only cut there is.
    for( std::size_t i = 0; i < emitCount; ++i )
    {
        LoadedDoc&  doc             = loadedDocs[i];
        const bool  isOverAllowance = maxBytes && doc.demandBytes > shares.alloc[i];
        std::string sectionNote     = doc.sectionNote;   // the full-selection form, unless the budget rewrites it
        std::string truncNote;
        bool        wasReduced      = false;

        if( isOverAllowance && doc.sections )
        {
            RecallSectionEmission em = emitRecallSectionUnits( *doc.sections, shares.alloc[i] );
            sectionNote = std::move( em.sectionNote );
            truncNote   = std::move( em.truncNote );
            wasReduced  = em.wasReduced;
            doc.body()  = std::move( em.body );
        }
        else if( isOverAllowance )
        {
            // The marker is reserved at kRecallTruncNoteBytes and always costs less, so the allowance is
            // under-used rather than overshot — the ceiling direction the whole budget path holds to.
            const std::size_t keepBytes = shares.alloc[i] > kRecallTruncNoteBytes ? shares.alloc[i] - kRecallTruncNoteBytes
                                                                                  : kRecallMinBodyBytes;
            truncNote  = truncateRecallBody( doc.body(), keepBytes ).marker;   // this path names no lines=, so only the marker
            wasReduced = true;
        }

        payload     += doc.sep;
        payload     += sectionNote;
        payload     += truncNote;
        markupBytes += doc.sep.size() + sectionNote.size() + truncNote.size();
        if( wasReduced )
        {
            ++shape.truncatedCount;   // §RP4: still "documents reduced by ANY means" — dropped units included
        }
        payload += '\n';
        payload += doc.body();    // append, not printf: an embedded NUL must not truncate the doc
        payload += '\n';
        markupBytes += 2;
        bodyBytes   += doc.body().size();
        ++shape.shownCount;
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
// The digit run belonging to `field` in a header line, as [start, end); {npos, npos} when the field is not
// there. Both writers below need exactly this and nothing else — written twice first, and --quality-delta
// called the second a 122-token clone of the first, which it was.
inline std::pair<std::size_t, std::size_t> headerFieldDigits( const std::string& line, std::string_view field )
{
    const std::size_t pos = line.find( field );
    if( pos == std::string::npos )
    {
        return { std::string::npos, std::string::npos };   // defensive: header shape changed elsewhere
    }
    const std::size_t start = pos + field.size();
    std::size_t       end   = start;
    while( end < line.size() && line[end] >= '0' && line[end] <= '9' )
    {
        ++end;
    }
    return { start, end };
}

inline std::string withHeaderField( std::string_view fullHeaderLine, std::string_view field, std::size_t value )
{
    std::string line( fullHeaderLine );
    const auto [ start, end ] = headerFieldDigits( line, field );
    if( start != std::string::npos )
    {
        line.replace( start, end - start, std::to_string( value ) );
    }
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
    std::string line( fullHeaderLine );
    const auto [ start, end ] = headerFieldDigits( line, afterField );
    if( start != std::string::npos )
    {
        line.insert( end, attr );
    }
    return line;
}

// The third member of the family above: REMOVE an attribute the emitted document cannot vouch for. Both
// callers are the withheld branch below, where a SHAPING fact (over_ceiling=, share_bytes=) would otherwise
// stand on a header describing the one line that WAS printed. `attr` carries its own leading space and
// trailing '=' — " over_ceiling=" — so it cannot match inside another attribute's value. Absent: no-op.
inline std::string withoutHeaderAttr( std::string_view fullHeaderLine, std::string_view attr )
{
    std::string       line( fullHeaderLine );
    const std::size_t at = line.find( attr );
    if( at == std::string::npos )
    {
        return line;
    }
    const std::size_t nextAt = line.find( ' ', at + attr.size() );
    line.erase( at, nextAt == std::string::npos ? std::string::npos : nextAt - at );
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
            // F4/F5 (over_ceiling=), §C4 (share_bytes=): both are SHAPING facts about the bundle this branch
            // WITHHELD, and est_tokens= right beside them is rewritten to price the refusal header — the only
            // thing that was emitted. Leaving them puts a label on a 200-token document claiming it busted an
            // 8000-token ceiling, and a per-document share on a document that was never divided. What goes is
            // in each case a marker no number on this line can confirm; the withheld artifact's own price stays
            // beside them under withheld_est_tokens=, so nothing is lost. (Measured on the audit's own probe:
            // `over_ceiling=1 max_tokens=8000 budget_tokens=1500 est_tokens=200 withheld_est_tokens=6677` —
            // three ceilings and a price, none of which the flag was about.)
            honest = withoutHeaderAttr( honest, " over_ceiling=" );
            honest = withoutHeaderAttr( honest, " share_bytes=" );
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
        rw::emitTo( stderr, "ripwire: --token-budget exceeded: withheld_est_tokens={} > budget={}\n",
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

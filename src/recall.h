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
    if( !in ) return false;
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
    if( const auto it = ing.docText.find( fileId ); it != ing.docText.end() ) return it->second.size();
    std::ifstream in( diskPath( ing, fileId ), std::ios::binary | std::ios::ate );
    if( !in ) return 0;
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
    for( const Symbol& s : ing.symbols ) if( s.lang == Lang::Markdown && s.fileId < isDoc.size() ) isDoc[ s.fileId ] = 1;
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
        if( f >= isDoc.size() || !isDoc[f] ) continue;
        byteSizes[f] = docByteSize( ing, f );
        if( byteSizes[f] > 0 ) sizeSamples.push_back( byteSizes[f] );
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
        if( f >= isDoc.size() || !isDoc[f] || byteSizes[f] == 0 ) continue;
        const bool        couldClearSizeArm = sizeArmBytes > 0 && byteSizes[f] >= sizeArmBytes;
        const std::size_t readBytes         = couldClearSizeArm ? 0 : kGeneratedHeadScanBytes;   // 0 = whole file
        if( !readDocPrefix( ing, f, readBytes, text ) ) continue;
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
    if( aGen != bGen ) return !aGen;                        // hand-written beats generated (the primary key)
    if( a.score != b.score ) return a.score > b.score;
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
        if( docsOnly && f < isDoc.size() && !isDoc[f] ) continue;
        if( f < best.size() && scores[i] > best[f] ) best[f] = scores[i];
    }
    RecallSelection selection;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        if( best[f] <= 0.f ) continue;
        const auto reason = ( f < verdicts.reasonOf.size() ) ? docparse::GeneratedDocReason( verdicts.reasonOf[f] )
                                                             : docparse::GeneratedDocReason::None;
        if( reason != docparse::GeneratedDocReason::None ) ++selection.demotedMatchCount;
        selection.files.push_back( { f, best[f], reason } );
    }
    std::sort( selection.files.begin(), selection.files.end(),
               [ & ]( const Recalled& a, const Recalled& b ) noexcept { return recallOrderLess( a, b, ing ); } );
    selection.matchedCount = selection.files.size();   // §B2: TRUE count, taken BEFORE the --top-k cut
    if( k > 0 && int( selection.files.size() ) > k ) selection.files.resize( std::size_t( k ) );
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
    if( !docparse::scanMarkdownFences( body ).endsInsideFence ) return false;
    if( !body.empty() && body.back() != '\n' ) body += '\n';
    body += "```";
    return true;
}

// Cut ONE doc body down to `keepBytes` and return the marker that DISCLOSES the cut. Split out of
// buildRecall's budget loop so the whole truncation policy — UTF-8-safe prefix, fence repair, and what the
// marker admits to — reads in one place. `body` is edited in place; the returned text is appended to the
// doc's separator line, ahead of the body itself. Truncating BEFORE formatting is what lets the marker
// report fence_closed: whether a fence had to be closed is only knowable once the cut has been made.
inline std::string truncateRecallBody( std::string& body, std::size_t keepBytes )
{
    const std::size_t fullBytes = body.size();
    truncateUtf8WithEllipsis( body, keepBytes );                                     // deterministic UTF-8-safe prefix + a visible "…"
    const char* fenceNote = closeOpenMarkdownFence( body ) ? ", fence_closed" : "";   // §B2 — never hand back an open fence

    // CA4 H1 sibling sweep: this one was PROVABLY bounded (fixed prose + two %zu + the two-valued fenceNote =
    // 79 bytes worst case in a 160-byte buffer), so it never overflowed. It is composed on std::string anyway,
    // because the SHAPE is the defect, not the arithmetic: "snprintf into a fixed buffer, then append its
    // WOULD-BE return length" is safe only for as long as nobody widens the prose or adds an interpoland, and
    // that safety is invisible at the call site. Byte-identical to the format string it replaces.
    return "  [truncated: " + std::to_string( keepBytes ) + " of " + std::to_string( fullBytes ) + " bytes"
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
        if( !in ) return std::nullopt;
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
inline std::string formatRecallHeader( std::string_view task, const RecallShape& shape, std::size_t estTokens )
{
    // W3FIX M1 (same class as --for/--pack-task): `over_ceiling=1` — the artifact is larger than the --max-tokens
    // byte budget it was SHAPED against, because the header's own verbatim task echo is user-length text that
    // no body cut can shrink (kRecallHeaderReserveBytes + task.size() is charged, and a long enough task simply
    // leaves payloadBudget at 0 with the header still over). Absent ⇒ within the budget, or no --max-tokens at
    // all: the same silence-means-nothing-happened rule truncated=/generated_demoted= follow below.
    std::string overCeilingAttr;
    if( shape.isOverCeiling ) overCeilingAttr = " over_ceiling=1";
    std::string truncAttr;
    if( shape.truncatedCount > 0 ) truncAttr = " truncated=" + std::to_string( shape.truncatedCount );
    std::string demotedAttr;
    if( shape.demotedCount > 0 ) demotedAttr = " generated_demoted=" + std::to_string( shape.demotedCount );
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
    line.reserve( 160 + task.size() + truncAttr.size() + demotedAttr.size() + overCeilingAttr.size() );
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
    line += " est_tokens=";
    line += std::to_string( estTokens );
    line += "\n";
    return line;
}

// §P2b — what a demoted doc says ON ITS OWN separator line: the evidence that demoted it, so a reader who
// sees a capture at the bottom knows it was ranked there deliberately. "" for a hand-written doc.
inline std::string formatDemotedNote( docparse::GeneratedDocReason reason )
{
    if( reason == docparse::GeneratedDocReason::None ) return {};
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
    if( topKOmitted > 0 ) why += "raise --top-k (default 8) for " + std::to_string( topKOmitted ) + " more";
    if( budgetOmitted > 0 )
    {
        if( !why.empty() ) why += "; ";
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

// Build the recall bundle IN MEMORY: each top file's path + relevance + body, best-first. `maxBytes` (0 =
// no cap) SHAPES it — bodies are dropped from the BOTTOM of the ranking and the last one may be truncated
// within itself, both DISCLOSED (per-doc `[truncated: …]`, header `capped=1`/`truncated=N`, a closing
// `(capped: …)` note). Building before writing is what lets --token-budget gate BEFORE a byte is emitted.
// §B10.1: `redact` is REQUIRED — no default. A recalled doc is whole-file prose straight off disk, which is
// the same credential seam packSource has; W3-N1's rule ("a new emitting clone cannot silently opt out")
// applies to it exactly. nullptr = --no-redact, spelled deliberately. The one caller already passed it.
inline RecallBundle buildRecall( const IngestResult& ing, const std::vector<float>& scores,
                                 std::string_view task, int k, std::size_t maxBytes, bool docsOnly,
                                 RedactCounts* redact )
{
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

    for( const Recalled& r : top )
    {
        // V5: fileId is an INDEX into files[], and this VERIFY guards the NEAREST dereference — which is
        // loadRecallBody's, not the separator's. It sat one call below, i.e. one dereference late: the
        // invariant was true and correctly a VERIFY, but the first read it protected had already happened.
        VERIFY( r.fileId < ing.files.size() );
        std::optional<std::string> loaded = loadRecallBody( ing, r.fileId, redact );
        if( !loaded ) continue;
        std::string body = std::move( *loaded );

        const std::string demotedNote = formatDemotedNote( r.generated );
        const std::string sep         = formatRecallSeparator( ing.files[ r.fileId ], r.score, demotedNote );
        const std::size_t sepBytes    = sep.size();

        // the budget decision for THIS doc: full, sliced, or not at all. `used` is the payload so far.
        std::size_t keepBytes    = body.size();
        bool        isTruncated  = false;
        if( maxBytes )
        {
            const std::size_t used  = payload.size();
            const std::size_t floor = sepBytes + 2 + kRecallMinBodyBytes;
            if( used + floor > payloadBudget ) break;                      // no room for a meaningful slice
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
        if( isTruncated ) break;   // the budget is spent — the next doc would be a 0-byte stub
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
        if( next == header ) break;
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
    if( pos == std::string::npos ) return line;   // defensive: header shape changed elsewhere — leave it be

    const std::size_t digitsStart = pos + field.size();
    std::size_t       digitsEnd   = digitsStart;
    while( digitsEnd < line.size() && line[digitsEnd] >= '0' && line[digitsEnd] <= '9' ) ++digitsEnd;
    line.replace( digitsStart, digitsEnd - digitsStart, std::to_string( value ) );
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
            for( int pass = 0; pass < 3; ++pass )
            {
                const std::size_t est  = std::size_t( double( honest.size() + noteBytes ) / kBytesPerTokenDefault + 0.5 );
                std::string       next = withHeaderField( honest, " est_tokens=", est );
                if( next == honest ) break;
                honest = std::move( next );
            }
            std::fwrite( honest.data(), 1, honest.size(), out );
        }
        std::fwrite( note.data(), 1, noteBytes, out );
        std::fprintf( stderr, "ripwire: --token-budget exceeded: withheld_est_tokens=%zu > budget=%zu\n",
                      bundle.shape.estTokens, budgetTokens );
        return 3;
    }
    std::fwrite( bundle.text.data(), 1, bundle.text.size(), out );
    return 0;
}

// Write the recall bundle (the MCP `memory_recall` seam and the plain CLI path). Same budget semantics as
// buildRecall — this is the "render it and hand it over" form for callers that do not gate on the shape.
inline void writeRecall( std::FILE* out, const IngestResult& ing, const std::vector<float>& scores,
                         std::string_view task, int k, std::size_t maxBytes, bool docsOnly,
                         RedactCounts* redact = nullptr )
{
    const RecallBundle bundle = buildRecall( ing, scores, task, k, maxBytes, docsOnly, redact );
    std::fwrite( bundle.text.data(), 1, bundle.text.size(), out );
}

}   // namespace rw

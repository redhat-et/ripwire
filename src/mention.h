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
//     already believes in cannot be dethroned by an anchor). This is a SCORE promise (within
//     kMentionTopGapStep of the top score for the first anchored slot), not a rank promise: on a flat or
//     tied head, several unanchored candidates can sit inside that same 5% band above the anchor, so the
//     anchored hit can still land a few ranks below #1 (§L10, 2026-09-04 — measured r=5 on a flat head).
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
#include "infra/namesplit.h"   // isIdentChar — the ONE ASCII identifier-character predicate
#include "graph.h"   // R5: applyDocMentionBoost reads g.mentions (the doc->code backtick edges the
                      // --mentions=SYM verb already exposes) — same header gitmine.h already pulls in for
                      // an analogous "read one more Graph field" reason.

namespace rw
{

// ── CAP DISCLOSURE, both dialects at once (METHODOLOGY §9 #4, docs/LIMITS.md) ───────────────────────
//
// The caps in this file and in gitmine.h's co-boost family are INDEXING caps: they decide what the ranker
// is allowed to LIFT, upstream of any element. Nothing downstream can tell that a mention was dropped, and
// no flag, budget or paging brings it back — the answer simply does not contain the thing the task named.
// That is non-negotiable #3 ("a zero means none found, never none exists") one level above the emitters
// capdisclosurecheck.sh already closed, which is why the disclosure has to be built HERE and carried out
// rather than reconstructed at each verb.
//
// THE RULE, because it decides which caps get an attribute and which get a comment: DISCLOSE WHEN THE CUT
// CONTENT IS NOT OTHERWISE VISIBLE IN THE ANSWER. A cap that trims symbols out of a file the bundle NAMES
// on the rows it did serve costs zero bytes and carries a measured comment at its declaration instead —
// the caller can see the file and page into it. A cap that drops a file, a symbol, a doc or a whole commit
// that appears NOWHERE carries a conditional attribute.
//
// COST: zero unless a cap actually bit. Nothing is emitted while `fired` is false — the pr_converged shape
// (src/prconverge.h), and the one thing separating a disclosure from a tax. Never `*_capped="0"`, and
// never a `*_total=` equal to the count already shown.
struct CapDisclosure
{
    // The placeholder below is spelled `<x>` rather than a word on purpose: docs/limits_build.py harvests
    // `[a-z_]+_capped` out of this file to decide which caps it discloses, so a lower-case placeholder —
    // even inside a comment — lands in the generated table as an attribute that does not exist. Caught by
    // reading the regenerated table rather than trusting it; a generated doc is only as honest as its input.
    std::string xml;    // ` <x>_capped="1" <x>_total="N"` — spliced onto the answer's own root
    std::string json;   // `,"<x>_capped":true,"<x>_total":N` — the --json twin, same facts, same order

    // `totalAttr` may be nullptr where the true count is not exactly computable without changing what the
    // cap keeps; the honest disclosure is then the FACT of the cut alone, and the declaration says why.
    void note( const char* cappedAttr, const char* totalAttr, bool fired, std::uint64_t total )
    {
        if( !fired )
        {
            return;
        }
        xml  += std::string( " " ) + cappedAttr + "=\"1\"";
        json += std::string( ",\"" ) + cappedAttr + "\":true";
        if( totalAttr )
        {
            const std::string n = std::to_string( total );
            xml  += std::string( " " ) + totalAttr + "=\"" + n + "\"";
            json += std::string( ",\"" ) + totalAttr + "\":" + n;
        }
    }
    bool fired() const noexcept { return !xml.empty(); }
};

// The prose half: the clause a reader meets on the first screen, carrying the attribute VERBATIM so it is
// self-defining (legendcoveragecheck's `defined` predicate is `name=`, the same reason dropped_positive=
// needs no legend clause of its own). No "--" in it: it rides inside an XML comment, where a double hyphen
// is ill-formed (G4). "" when nothing fired, so the notes it is appended to stay exactly as they were.
//
// LENGTH IS NOT COSMETIC HERE, and the first cut of this clause proved it. A --for header composed BEFORE
// the signature ladder runs is charged against kForPayloadBudgetBytes, so bytes spent on a note are bytes
// taken from ranked rows: at 122 B of fixed prose this clause cost a whole <d> row on three of the sixteen
// real invocations measured for this lane, and 204 B of evidence on a fourth. Two things fixed that, and
// both are load-bearing — the clause was trimmed to ~50 B, and on --for it is now spliced in AFTER the
// ladder has run (verbs_for.h, the splice budget_bytes= uses), so the <sigs> block is byte-identical to
// what it was and the disclosure is paid for in bytes rather than in evidence. Re-measured after both:
// twelve of the sixteen are byte-identical and the four that disclose pay +106 B with no row lost.
inline std::string capDisclosureNote( const CapDisclosure& disc )
{
    return disc.fired() ? ( " [cut:" + disc.xml + " — an indexing cap dropped content not shown here]" ) : std::string();
}

// A bundle carries a disclosure in THREE accumulators — prose clause, XML attributes, JSON keys — and each
// of the three lift passes contributes to all three. Appending them in lockstep here is the point: nine
// hand-written call sites (three passes × --for, --pack-task and the MCP twin) is nine chances for one
// surface to learn a fact the other two do not, and mcpattrparitycheck exists because that has happened.
// Every one of the three is "" unless a cap actually bit, so a bundle that lost nothing still pays nothing.
inline void absorbCapDisclosure( const CapDisclosure& disc, std::string& note, std::string& xmlAttrs, std::string& jsonKeys )
{
    note     += capDisclosureNote( disc );
    xmlAttrs += disc.xml;
    jsonKeys += disc.json;
}

// The two-dialect form, for the MCP `for` verb: it serves XML text only, so there is no JSON accumulator to
// keep in step and an empty scratch string would be the fiction that there is.
inline void absorbCapDisclosure( const CapDisclosure& disc, std::string& note, std::string& xmlAttrs )
{
    note     += capDisclosureNote( disc );
    xmlAttrs += disc.xml;
}

// Record one cap into a census the caller may not have asked for. Null-tolerant on purpose: `outInfo` is
// optional on every boost entry point in this file, and without this the three census statements would each
// be wrapped in a guard of its own, which buries the facts they record inside control flow that says nothing.
template<class InfoT>
inline void noteCap( InfoT* outInfo, const char* cappedAttr, const char* totalAttr, bool fired, std::uint64_t total )
{
    if( outInfo )
    {
        outInfo->caps.note( cappedAttr, totalAttr, fired, total );
    }
}

// Fixed knobs — deliberately NOT flags (one documented behavior, one ablation switch to kill it whole).
// The three that CUT INVISIBLE CONTENT disclose (see CapDisclosure above); kMentionMaxSymbolsPerFile does
// not, and that is a measurement, not an oversight: it only ever trims symbols out of a file every one of
// whose surviving rows carries p="<that file>", so the caller can see the file and expand it. It also fires
// on essentially every anchored query (any real source file has more than three symbols), so an attribute
// there would be a per-answer tax paid for a fact already on the screen.
//
// HOW OFTEN THE THREE ACTUALLY FIRE, measured over 39 realistic --for tasks against this tool's own tree
// (2026-09-10, the cap-disclosure round): kMentionMaxRawTokens 1/39, kMentionMaxFiles 3/39, and
// kMentionMaxDirectSymbols 0/39. All three firings came from the same shape — a task that pastes SEVERAL
// paths, which is exactly the multi-file localization case B8 exists for. The kMentionMaxFiles 3/39 is an
// UPPER BOUND: it was read off the first cut of the flag, which reported a scan's STOP as a cut on exactly
// that multi-path shape (see mentionUnkeptFiles), and the 39-task list was not kept, so it cannot be re-derived. The zero is a property of this
// corpus, not of the cap: it takes more than eight definitions of one Scope.name for the cap to bite, and
// a C++ tree with unique method names has none. The class is real and gated on a fixture that does
// (test/mentioncapcheck.sh arm C), and the attribute costs nothing on the runs where it stays silent, so
// the zero is recorded here rather than used as an argument to leave the cut unsaid.
inline constexpr std::size_t kMentionMaxRawTokens      = 16;     // extraction cap: first N candidate mention tokens, text order
inline constexpr std::size_t kMentionMaxFiles          = 4;      // strongest evidence only: files named first in the text
inline constexpr std::size_t kMentionMaxSymbolsPerFile = 3;      // per mentioned file: its top symbols by (lens score desc, id asc)
inline constexpr std::size_t kMentionMaxDirectSymbols  = 8;      // directly-named (Scope.name / `name`) symbols, id asc
inline constexpr float       kMentionTopGapStep        = 0.05f;  // slot i lands at top*(1 - step*(i+1)) — below #1, above the pack

struct MentionBoostInfo
{
    std::uint32_t fileCount   = 0;   // matched files that received a boost
    std::uint32_t symbolCount = 0;   // total symbols lifted (file-derived + direct)
    // What the caps above took away. Filled even when applyMentionBoost returns FALSE — a task whose only
    // named file fell outside the extraction window lifts nothing at all, and that is precisely the run a
    // caller most needs told about, so the caller reads this whether or not the boost moved a score.
    CapDisclosure caps;
};

// The slot-ladder's placement step, factored out because every env-gated lift that uses this vocabulary
// (siblift.h, filepool.h, expand.h) repeats it identically: rank `fileId`'s positive symbols best-first,
// then raise the top kMentionMaxSymbolsPerFile of them to `slot` via max() placement (never LOWERS a
// symbol already scored higher, so #1 is never displaced by construction). Returns how many symbols this
// call actually raised — 0 means the file had nothing to promote (every candidate was already >= slot, or
// had no positive score at all), which is what lets a caller tell "the lift ran" apart from "the lift
// moved something" for its own disclosure.
inline std::uint32_t promoteFileSymbolsToSlot( const IngestResult& ing, std::vector<float>& lensRank, std::uint32_t fileId, float slot )
{
    std::vector<std::pair<float, NodeId>> symbols;
    for( std::size_t k = 0; k < ing.symbols.size(); ++k )
    {
        if( ing.symbols[k].fileId == fileId && lensRank[k] > 0.f )
        {
            symbols.emplace_back( lensRank[k], NodeId( k ) );
        }
    }
    std::sort( symbols.begin(), symbols.end(), []( const auto& a, const auto& b )
               { return a.first != b.first ? a.first > b.first : a.second < b.second; } );
    std::uint32_t promoted = 0;
    for( std::size_t k = 0; k < symbols.size() && k < kMentionMaxSymbolsPerFile; ++k )
    {
        if( slot > lensRank[ symbols[k].second ] )
        {
            lensRank[ symbols[k].second ] = slot;
            ++promoted;
        }
    }
    return promoted;
}

// The "<a>,<b>" env-value grammar every one of these lifts is configured with (RIPWIRE_SIBLIFT,
// RIPWIRE_POOL, RIPWIRE_EXPAND): two decimal integers separated by one comma, each capped. Extracted
// 2026-09-10 (lift-disclosure round) after the three per-file copies — once each was split into its own
// parse function so a malformed value could be told apart from an unset one — were flagged as a
// duplication clone of each other; before that split they were similar enough in spirit but different
// enough in shape (one env-fetch inlined here, an extra overflow guard there) that the clone detector
// had not matched them, but that was never a reason to keep three copies of one grammar.
//
// BEHAVIOR-PRESERVING vs. every pre-extraction copy: for any input string, the accept/reject verdict and
// the (a,b) pair returned are unchanged. The three originals differed only in WHEN the over-cap case was
// caught (immediately per-digit here, once at the end there), never in WHETHER it was caught — digit
// accumulation is monotonically non-decreasing, so an intermediate value that will end up over cap is
// already over cap the moment it first exceeds it, and a return at that instant or at the end reaches the
// identical verdict.
//
// Returns {0,0} for anything malformed OR either field over its cap — no partial credit, no
// clamp-and-guess; each caller decides what {0,0} means for it (every one of them: feature off).
inline std::pair<std::size_t, std::size_t> parseCappedCsvPair( std::string_view s, std::size_t capA, std::size_t capB )
{
    const std::size_t comma = s.find( ',' );
    if( comma == std::string_view::npos || comma == 0 || comma + 1 >= s.size() )
    {
        return { 0, 0 };
    }
    std::size_t a = 0, b = 0;
    for( const char c : s.substr( 0, comma ) )
    {
        if( c < '0' || c > '9' ) { return { 0, 0 }; }
        a = a * 10 + std::size_t( c - '0' );
        if( a > capA ) { return { 0, 0 }; }
    }
    for( const char c : s.substr( comma + 1 ) )
    {
        if( c < '0' || c > '9' ) { return { 0, 0 }; }
        b = b * 10 + std::size_t( c - '0' );
        if( b > capB ) { return { 0, 0 }; }
    }
    return { a, b };
}

// One extracted candidate mention, classified by shape. `segments` are the '/'- or '.'-separated parts
// (lowercased never — corpus paths are case-sensitive).
namespace mention_detail
{

struct RawMention
{
    std::vector<std::string> segments;   // path or dotted segments, in order
    bool                     isPath = false;   // came with '/' (or an extension-bearing basename) → match as path
};

// Hoisted to infra/namesplit.h (a leaf header) when pattern.h needed the same predicate; the spelling
// stays via a using-declaration so every call site below — and its gates — are byte-identical.
using rw::namesplit::isIdentChar;

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
    if( segments.empty() )
    {
        return false;
    }

    // last segment: whole basename, basename-with-extension, or basename-sans-extension
    const std::string_view base = baseNameOf( path );
    const std::string&     last = segments.back();
    std::string_view       remaining;
    if( base == last )
    {
        remaining = path.substr( 0, path.size() - base.size() );
    }
    else if( stripExt( base ) == last )
    {
        remaining = path.substr( 0, path.size() - base.size() );
    }
    else
    {
        return false;
    }

    // earlier segments must match the preceding whole components right-to-left
    // (decrement INSIDE the body — the `i-- > 0` idiom wraps the unsigned at loop exit, which G1's
    // integer sanitizer deliberately traps on ripwire-owned code)
    for( std::size_t i = segments.size() - 1; i > 0; )
    {
        --i;
        if( remaining.empty() || remaining.back() != '/' )
        {
            return false;
        }
        remaining.remove_suffix( 1 );
        const std::string_view comp = baseNameOf( remaining );
        if( comp != segments[i] )
        {
            return false;
        }
        remaining = remaining.substr( 0, remaining.size() - comp.size() );
    }
    return true;
}

// a package's contract file — the one file whose basename shares no token with the package's name, so
// the suffix match above can never reach it from a directory mention
inline bool isIndexBaseName( std::string_view base ) noexcept
{
    return base == "__init__.py" || base == "index.ts" || base == "index.tsx" || base == "index.js"
        || base == "mod.rs" || base == "lib.rs";
}

// does the DIRECTORY of `path` end with the mention's segments as whole path components?
// e.g. segments [vendor, requests] matches the dir of "vendor/requests/__init__.py".
inline bool dirSuffixMatches( std::string_view path, const std::vector<std::string>& segments ) noexcept
{
    const std::string_view base = baseNameOf( path );
    if( segments.empty() || base.size() >= path.size() )
    {
        return false;
    }
    std::string_view remaining = path.substr( 0, path.size() - base.size() - 1 );   // drop "/<base>"
    for( std::size_t i = segments.size(); i > 0; )
    {
        --i;
        const std::string_view comp = baseNameOf( remaining );
        if( comp != segments[i] )
        {
            return false;
        }
        remaining = remaining.substr( 0, remaining.size() - comp.size() );
        if( i > 0 )
        {
            if( remaining.empty() || remaining.back() != '/' )
            {
                return false;
            }
            remaining.remove_suffix( 1 );
        }
    }
    return true;
}

// package-directory mention lift: a mention that named NO file and NO symbol may name a source
// DIRECTORY — a backticked bare package name (`requests`) or a dotted chain (vendor.requests). Lift
// ONLY the directory's index file (isIndexBaseName): the package contract lives there, and its
// basename shares no token with the mention, so the path-suffix match can never reach it. No index
// file → no lift; precision over recall by design.
// (r2 head-to-head bucket R1: micropython-lib-947, gold requests/__init__.py at rank 35.)
inline void liftPackageDirMention( const IngestResult& ing, const RawMention& m, std::vector<std::uint32_t>& mentionedFiles )
{
    const std::size_t fileCount = ing.files.size();
    for( std::uint32_t f = 0; f < fileCount && mentionedFiles.size() < kMentionMaxFiles; ++f )
    {
        if( !isIndexBaseName( baseNameOf( ing.files[f] ) ) || !dirSuffixMatches( ing.files[f], m.segments ) )
        {
            continue;
        }
        if( std::find( mentionedFiles.begin(), mentionedFiles.end(), f ) == mentionedFiles.end() )
        {
            mentionedFiles.push_back( f );
        }
    }
}

// Did kMentionMaxFiles CUT a file this mention names, or only STOP a scan? The anchor's scans stop the instant the
// list is full, so files left unexamined prove nothing: at exactly kMentionMaxFiles matches, or when an earlier
// mention already filled the list, the corpus tail may hold no file the mention names at all. Reading the stop as
// the cut said mention_files_capped="1" on answers that lifted everything the task named (mentioncapcheck arm B').
// So the verdict comes from what the mention NAMES, resolved the way an uncapped scan resolves it: (a) the longest
// path suffix that matches ANY file wins and ends resolution; (b) a Scope.name the corpus defines names a symbol,
// not a file; (c) otherwise the package-dir index files. True when that set holds a file `kept` does not.
// Read-only — the kept set, every route and every score are exactly what the capped pass decided. (b) ends
// resolution on the symbol's EXISTENCE, not on whether the symbol cap had room: a file verdict must not move
// with a different cap.
inline bool definesScopeName( const IngestResult& ing, const std::string& scope, const std::string& name ) noexcept
{
    return std::any_of( ing.symbols.begin(), ing.symbols.end(), [ & ]( const Symbol& s ) { return s.name == name && s.scope == scope; } );
}

// WHICH files this mention names that `kept` does not — appended, never cleared, so a caller can union
// across mentions. This is the old first-hit predicate's body with "return true on the first one" replaced by "collect
// them all": a bare boolean told the caller something was withheld and neither how much nor how to get it,
// which is §9-3 of docs/METHODOLOGY.md unmet, and the sibling caps in this same file already pass a total.
// Verdict-equivalent to the predicate below by construction — same resolution order, same three rules, and
// a level that resolves with only KEPT matches still ends resolution with nothing appended.
inline void mentionUnkeptFiles( const IngestResult& ing, const RawMention& m, const std::vector<std::uint32_t>& kept,
                                std::vector<std::uint32_t>& out )
{
    const std::size_t fileCount = ing.files.size();
    for( std::size_t suffixLen = m.segments.size(); suffixLen >= 1; --suffixLen )
    {
        const std::vector<std::string> suffix( m.segments.end() - suffixLen, m.segments.end() );
        const std::size_t              before = out.size();
        bool                           named  = false;
        for( std::uint32_t f = 0; f < fileCount; ++f )
        {
            if( !pathSuffixMatches( ing.files[f], suffix ) )
            {
                continue;
            }
            if( std::find( kept.begin(), kept.end(), f ) == kept.end() )
            {
                out.push_back( f );
                continue;
            }
            named = true;
        }
        if( out.size() > before || named )
        {
            return;              // the longest matching suffix wins and ends resolution — capped or not
        }
    }
    if( !m.isPath && m.segments.size() == 2 && definesScopeName( ing, m.segments[0], m.segments[1] ) )
    {
        return;
    }
    for( std::uint32_t f = 0; f < fileCount; ++f )
    {
        if( isIndexBaseName( baseNameOf( ing.files[f] ) ) && dirSuffixMatches( ing.files[f], m.segments )
            && std::find( kept.begin(), kept.end(), f ) == kept.end() )
        {
            out.push_back( f );
        }
    }
}

// How many DISTINCT files the task's mentions name in total — the kept ones plus the ones the cap refused.
// Equal to kept.size() when nothing was cut, so `total > kept.size()` is exactly the file-cap verdict
// and the two can never disagree. The union is only computed on the runs where the list is full, so the
// common anchored query pays the same one size test it always did.
inline std::uint32_t mentionFilesNamedTotal( const IngestResult& ing, const std::vector<RawMention>& raw,
                                             const std::vector<std::uint32_t>& kept )
{
    if( kept.size() < kMentionMaxFiles )
    {
        return std::uint32_t( kept.size() );
    }
    std::vector<std::uint32_t> named( kept.begin(), kept.end() );
    for( const RawMention& m : raw )
    {
        mentionUnkeptFiles( ing, m, kept, named );
    }
    std::sort( named.begin(), named.end() );
    named.erase( std::unique( named.begin(), named.end() ), named.end() );
    return std::uint32_t( named.size() );
}

// extract candidate mentions from the task text: '/'-joined path tokens, dot-joined identifier chains,
// and `backticked` identifiers. Plain prose words never qualify — precision over recall by design.
// `outQualified` counts EVERY token that would have become a mention, window or no window — the scan runs
// to the end of the task text regardless, and only the KEEPING stops at kMentionMaxRawTokens. Task text is
// one sentence, so the census is free; what it buys is an exact `mention_tokens_total=` instead of a bare
// "something was dropped".
inline std::vector<RawMention> extractMentions( std::string_view task, std::uint32_t* outQualified = nullptr )
{
    std::vector<RawMention> raw;
    std::size_t i = 0;
    while( i < task.size() )
    {
        if( !isTokenChar( task[i] ) ) { ++i; continue; }
        const std::size_t start = i;
        while( i < task.size() && isTokenChar( task[i] ) )
        {
            ++i;
        }
        std::string_view tok = task.substr( start, i - start );
        const bool backticked = start > 0 && task[start - 1] == '`' && i < task.size() && task[i] == '`';

        // trim joiner punctuation that is really sentence punctuation ("see foo.py." / "path/,")
        while( !tok.empty() && ( tok.back() == '.' || tok.back() == '/' || tok.back() == '-' ) )
        {
            tok.remove_suffix( 1 );
        }
        while( !tok.empty() && ( tok.front() == '.' || tok.front() == '/' || tok.front() == '-' ) )
        {
            tok.remove_prefix( 1 );
        }
        if( tok.size() < 3 || tok.size() > 200 )
        {
            continue;
        }

        const bool hasSlash = tok.find( '/' ) != std::string_view::npos;
        const bool hasDot   = tok.find( '.' ) != std::string_view::npos;
        if( !hasSlash && !hasDot && !backticked )
        {
            continue; // plain word — not a mention
        }

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
            if( q == std::string_view::npos )
            {
                break;
            }
            p = q + 1;
        }
        if( malformed || m.segments.empty() )
        {
            continue;
        }

        // dotted chains need a real identifier somewhere ("e.g", "i.e", version numbers "3.10" stay prose)
        if( !hasSlash && !backticked )
        {
            if( m.segments.size() < 2 || maxSegmentLen < 3 )
            {
                continue;
            }
            bool allDigits = true;
            for( const std::string& s : m.segments )
            {
                for( const char c : s )
                {
                    if( c < '0' || c > '9' )
                    {
                        allDigits = false;
                        break;
                    }
                }
            }
            if( allDigits )
            {
                continue;
            }
        }

        // path mentions keep only their meaningful tail (a URL prefix like github.com/org/repo/blob/main
        // would otherwise demand components the indexed repo-relative path does not have)
        if( m.isPath && m.segments.size() > 3 )
        {
            m.segments.erase( m.segments.begin(), m.segments.end() - 3 );
        }

        if( outQualified )
        {
            ++*outQualified;
        }
        if( raw.size() < kMentionMaxRawTokens )
        {
            raw.push_back( std::move( m ) );
        }
    }
    return raw;
}

} // namespace mention_detail

// Apply the mention anchor to `lensRank` (size == ing.symbols.size()). Returns true if anything moved.
inline bool applyMentionBoost( const IngestResult& ing, std::string_view task, std::vector<float>& lensRank, MentionBoostInfo* outInfo = nullptr )
{
    using namespace mention_detail;
    VERIFY( lensRank.size() == ing.symbols.size() );
    if( task.empty() || lensRank.empty() || lensRank.size() != ing.symbols.size() )
    {
        return false;
    }

    // The census is written into outInfo as each fact is known, BEFORE the early returns below: a task whose
    // only named file fell outside the window lifts nothing, returns false, and still owes the caller this.
    std::uint32_t qualifiedTokens = 0;
    const std::vector<RawMention> raw = extractMentions( task, &qualifiedTokens );
    noteCap( outInfo, "mention_tokens_capped", "mention_tokens_total", qualifiedTokens > kMentionMaxRawTokens, qualifiedTokens );
    if( raw.empty() )
    {
        return false;
    }

    // current top score = the unbreakable ceiling (a rank with no positive score anchors from 1.0)
    float topScore = 0.0f;
    for( const float s : lensRank )
    {
        topScore = std::max( topScore, s );
    }
    if( !( topScore > 0.0f ) )
    {
        topScore = 1.0f;
    }

    // pass 1 — resolve mentions to files (text order, deduped, capped) and to directly-named symbols.
    std::vector<std::uint32_t> mentionedFiles;                       // <= kMentionMaxFiles, text order
    std::vector<NodeId>        directSymbols;                        // deduped, id asc at the end
    const std::size_t          fileCount = ing.files.size();
    std::uint32_t              directSymbolTotal = 0;                // Scope.name matches found, cap or no cap
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
                if( !pathSuffixMatches( ing.files[f], suffix ) )
                {
                    continue;
                }
                if( std::find( mentionedFiles.begin(), mentionedFiles.end(), f ) == mentionedFiles.end() )
                {
                    mentionedFiles.push_back( f );
                }
                matchedFile = true;
            }
        }

        // (b) scoped-symbol match for 2-segment dotted mentions (Scope.name — `DTypeSchema.validate`):
        //     exact name + exact enclosing scope. Only when no file matched (a module path that resolved
        //     to a file should anchor the file, not every same-named method).
        //     The scan runs to the end now; pushing is still gated on the same room test, so the kept set and
        //     `matchedSymbol` are unmoved. It buys an EXACT mention_syms_total= for nothing measurable — the
        //     common case (no match at all) already scanned every symbol.
        bool matchedSymbol = false;
        if( !matchedFile && !m.isPath && m.segments.size() == 2 )
        {
            const std::string& scopeSeg = m.segments[0];
            const std::string& nameSeg  = m.segments[1];
            for( const Symbol& s : ing.symbols )
            {
                if( s.name == nameSeg && s.scope == scopeSeg )
                {
                    ++directSymbolTotal;
                    if( directSymbols.size() < kMentionMaxDirectSymbols )
                    {
                        directSymbols.push_back( s.id );
                        matchedSymbol = true;
                    }
                }
            }
        }

        // (c) package-directory match — see liftPackageDirMention.
        if( !matchedFile && !matchedSymbol )
        {
            liftPackageDirMention( ing, m, mentionedFiles );
        }
    }
    // a STOP is not a CUT (mentionUnkeptFiles), and a CUT without a total is a fact the caller cannot act on:
    // mention_files_total= is every distinct file the task names, so `total - shown` is what the cap withheld.
    const std::uint32_t mentionFilesTotal = mentionFilesNamedTotal( ing, raw, mentionedFiles );
    noteCap( outInfo, "mention_files_capped", "mention_files_total",
             mentionFilesTotal > mentionedFiles.size(), mentionFilesTotal );
    noteCap( outInfo, "mention_syms_capped", "mention_syms_total", directSymbolTotal > kMentionMaxDirectSymbols, directSymbolTotal );
    if( mentionedFiles.empty() && directSymbols.empty() )
    {
        return false;
    }

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
    for( const NodeId id : directSymbols )
    {
        lift( id, 0 );
    }

    for( std::size_t fi = 0; fi < mentionedFiles.size(); ++fi )
    {
        const std::uint32_t f = mentionedFiles[fi];

        // the file's top symbols by (current score desc, id asc) — a tiny insertion sort into a fixed array
        NodeId        best[ kMentionMaxSymbolsPerFile ];
        std::uint32_t bestCount = 0;
        for( const Symbol& s : ing.symbols )
        {
            if( s.fileId != f )
            {
                continue;
            }
            std::uint32_t at = bestCount < kMentionMaxSymbolsPerFile ? bestCount : kMentionMaxSymbolsPerFile;
            while( at > 0 && ( lensRank[s.id] > lensRank[best[at - 1]] || ( lensRank[s.id] == lensRank[best[at - 1]] && s.id < best[at - 1] ) ) )
            {
                --at;
            }
            if( at >= kMentionMaxSymbolsPerFile )
            {
                continue;
            }
            for( std::uint32_t k = ( bestCount < kMentionMaxSymbolsPerFile ? bestCount : kMentionMaxSymbolsPerFile - 1 ); k > at; --k )
            {
                best[k] = best[k - 1];
            }
            best[at] = s.id;
            if( bestCount < kMentionMaxSymbolsPerFile )
            {
                ++bestCount;
            }
        }
        for( std::uint32_t k = 0; k < bestCount; ++k )
        {
            lift( best[k], fi );
        }
    }

    if( liftedSymbolCount == 0 )
    {
        return false;
    }
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
// The two DOC caps disclose (doc_mentions_capped=, below): a doc they refuse is nowhere in the bundle, so
// its absence reads as "no doc explains this". kDocMentionMaxAnchors does NOT, by the same rule stated at
// CapDisclosure: it is a window over the top of a ranked list this bundle prints in full, so every anchor
// it declines to consult is already on the caller's screen with its own row.
inline constexpr std::size_t kDocMentionMaxAnchors       = 8;      // consult only the current top-N anchors
inline constexpr std::size_t kDocMentionMaxDocsPerAnchor = 2;      // strongest-anchor-first, capped per anchor
inline constexpr std::size_t kDocMentionMaxDocsTotal     = 6;      // global cap — bounds token cost regardless of fan-out
inline constexpr float       kDocMentionDecay            = 0.55f;  // doc lands at anchor_score * decay — below the code hit

struct DocMentionBoostInfo
{
    std::uint32_t anchorCount = 0;
    std::uint32_t docCount    = 0;
    // doc_mentions_capped="1" — a doc that WOULD have been lifted was refused by one of the two doc caps.
    // FACT, no total: "how many docs would have risen" is a function of the rank at the moment each cap
    // fired, not a corpus count, so any number here would be an artifact of iteration order rather than
    // something the caller could check. The recoverable form already exists and is exact: `--mentions=SYM`
    // on any anchor row lists every doc that names it.
    CapDisclosure caps;
};

// WHICH docs the anchors in order[from, to) would have lifted and did not — appended to `out`. A doc that
// WAS lifted now sits at its target, so it cannot appear here; every doc that does is one a cap turned away.
// Non-empty proves kDocMentionMaxDocsTotal ended the consult loop on a liftable doc; empty is a proof of
// the negative, not a shrug. Bounded by kDocMentionMaxAnchors, so it never scans the corpus. Callers pass
// only the CONSULT WINDOW: anchors past it are the kDocMentionMaxAnchors cut, which is on the caller's
// screen and by design carries no attribute.
//
// It collects rather than returning bool because the disclosure needs a COUNT: lifted + refused is exactly
// how many docs the caps had to choose from, which is what doc_mentions_total= reports.
inline void collectRefusedDocLifts( const Graph& g, const std::vector<float>& lensRank, const std::vector<NodeId>& order,
                                    std::size_t from, std::size_t to, std::vector<NodeId>& out )
{
    for( std::size_t k = from; k < to; ++k )
    {
        const NodeId anchor = order[k];
        if( !( lensRank[anchor] > 0.0f ) || anchor >= g.mentions.size() )
        {
            continue;
        }
        const float target = lensRank[anchor] * kDocMentionDecay;
        for( const NodeId doc : g.mentions[anchor] )
        {
            if( doc < lensRank.size() && lensRank[doc] < target )
            {
                out.push_back( doc );
            }
        }
    }
}

inline bool applyDocMentionBoost( const Graph& g, std::vector<float>& lensRank, DocMentionBoostInfo* outInfo = nullptr )
{
    const std::size_t N = lensRank.size();
    VERIFY( g.mentions.empty() || g.mentions.size() == N );
    if( N == 0 || g.mentions.empty() )
    {
        return false;
    }

    // top-kDocMentionMaxAnchors symbols by (current score desc, id asc) — the symbols THIS query, after every
    // prior boost (route/anchor/query-mention/co-change), actually resolved onto. Positive scores only, same
    // pattern as graph.h's anchoredLexicalRank anchor selection.
    std::vector<NodeId> order( N );
    for( NodeId i = 0; i < N; ++i )
    {
        order[i] = i;
    }
    const std::size_t topN = std::min( kDocMentionMaxAnchors, N );
    std::partial_sort( order.begin(), order.begin() + topN, order.end(), [ & ]( NodeId a, NodeId b ) noexcept
    { return lensRank[a] != lensRank[b] ? lensRank[a] > lensRank[b] : a < b; } );

    // Set ONLY where a refusal is provable — a doc below its anchor's lift target that a cap turned away.
    // "There might be more" is not a fact and never sets it.
    std::vector<NodeId> refusedDocs;  // docs a cap turned away — the count half of the disclosure
    std::size_t   stoppedAt  = 0;    // how far the consult loop actually got — the post-loop sweep resumes here
    std::uint32_t liftedDocs = 0, usedAnchors = 0;
    for( std::size_t k = 0; k < topN && liftedDocs < kDocMentionMaxDocsTotal; ++k )
    {
        stoppedAt           = k + 1;
        const NodeId anchor = order[k];
        if( !( lensRank[anchor] > 0.0f ) )
        {
            break; // rest of `order` only gets worse
        }
        if( anchor >= g.mentions.size() || g.mentions[anchor].empty() )
        {
            continue;
        }

        const float   target    = lensRank[anchor] * kDocMentionDecay;
        std::size_t   perAnchor = 0;
        for( NodeId doc : g.mentions[anchor] )
        {
            if( perAnchor >= kDocMentionMaxDocsPerAnchor || liftedDocs >= kDocMentionMaxDocsTotal )
            {
                // A cap, not the fan-out, ended this anchor. The whole remaining fan-out is walked rather
                // than broken out of at the first hit: a bare "something was cut" could stop early, a TOTAL
                // cannot. Nothing here touches lensRank, so the lift is byte-identical either way.
                if( doc < lensRank.size() && lensRank[doc] < target )
                {
                    refusedDocs.push_back( doc );
                }
                continue;
            }
            if( doc >= lensRank.size() )
            {
                continue; // defensive; buildGraph keeps these in-range
            }
            if( lensRank[doc] < target )
            {
                lensRank[doc] = target;
                ++liftedDocs;
                ++perAnchor;
            }
        }
        if( perAnchor > 0 )
        {
            ++usedAnchors;
        }
    }

    // The other half of the total cap: it can also end the OUTER loop, leaving consulted-window anchors
    // whose docs were never looked at (see collectRefusedDocLifts).
    collectRefusedDocLifts( g, lensRank, order, stoppedAt, topN, refusedDocs );
    std::sort( refusedDocs.begin(), refusedDocs.end() );      // one doc under two anchors is ONE refusal
    refusedDocs.erase( std::unique( refusedDocs.begin(), refusedDocs.end() ), refusedDocs.end() );
    // doc_mentions_total= is lifted + refused: how many docs the caps had to choose from. It was nullptr —
    // a bare boolean saying content was withheld and neither how much nor how to get it, which is §9-3 of
    // docs/METHODOLOGY.md unmet by the same file whose mention_tokens_capped/mention_syms_capped both pass
    // a total. `doc_mentions=` on the root already carries the shown half, so total - doc_mentions is the gap.
    noteCap( outInfo, "doc_mentions_capped", "doc_mentions_total", !refusedDocs.empty(),
             std::uint64_t( liftedDocs ) + refusedDocs.size() );

    if( liftedDocs == 0 )
    {
        return false;
    }
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
        if( wasInserted )
        {
            fileRows.push_back( { ds.fileId, 1 } );
        }
        else
        {
            ++fileRows[ it->second ].mentions;
        }
    }
    std::sort( fileRows.begin(), fileRows.end(), [ & ]( const MentionFileRow& a, const MentionFileRow& b )
               { return ing.files[ a.fileId ] < ing.files[ b.fileId ]; } );
    return fileRows;
}

} // namespace rw

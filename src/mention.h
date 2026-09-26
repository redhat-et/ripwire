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
//   * A FILE ANCHOR NEVER DISPLACES #1 — a mentioned file's lifted symbols score strictly BELOW the current
//     maximum (the top hit the ranker already believes in cannot be dethroned by a file mention). This is a
//     SCORE promise (within kMentionTopGapStep of the top score for the first anchored slot), not a rank
//     promise: on a flat or tied head, several unanchored candidates can sit inside that same 5% band above
//     the anchor, so the anchored hit can still land a few ranks below #1 (§L10, 2026-09-04 — measured r=5 on
//     a flat head).
//   * A NAMED SYMBOL LEADS — a symbol the task names directly (Scope.name, or a verbatim identifier: see NAMED
//     IDENTIFIERS) lands one kMentionTopGapStep ABOVE the top score: answer first (METHODOLOGY §9.1 #3). It
//     takes the evidence the writer supplied (identifier syntax, a qualifier, backticks) AND a name defined in
//     at most kMentionMaxNameFiles files; anything weaker or ambiguous lifts nothing.
//   * BOUNDED — at most kMentionMaxFiles files x kMentionMaxSymbolsPerFile symbols, plus at most
//     kMentionMaxDirectSymbols directly-named symbols, are touched.
//   * DETERMINISTIC — mentions keep task-text appearance order; every match set is reduced with a total
//     order (score desc, id asc / path asc); no hashing, no RNG.

#include <algorithm>
#include <array>
#include <cctype>
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
    ASSUME_NO_ALIAS3( note, xmlAttrs, jsonKeys );
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
inline constexpr std::size_t kMentionMaxDirectSymbols  = 8;      // directly-named (Scope.name / identifier) symbols, task-text order kept
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
using rw::namesplit::isIdentStart;
using rw::namesplit::hasIdentifierShape;

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

// A path's STEM — its basename with the last extension dropped ("src/a/b_test.py" → "b_test"). Both halves
// already lived here; the PAIR was being re-spelled at four call sites (testmap.h twice, situ.h, binstale.h),
// which is exactly the new-clone-of-a-reused-helper --quality-delta reports. One name, one composition.
inline std::string_view pathStem( std::string_view path ) noexcept { return stripExt( baseNameOf( path ) ); }

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
        if( !isIndexBaseName( baseNameOf( ing.files[f] ) ) || !dirSuffixMatches( rootRelPath( ing, f ), m.segments ) )
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
    ASSUME_NO_ALIAS( kept, out );
    const std::size_t fileCount = ing.files.size();
    for( std::size_t suffixLen = m.segments.size(); suffixLen >= 1; --suffixLen )
    {
        const std::vector<std::string> suffix( m.segments.end() - suffixLen, m.segments.end() );
        const std::size_t              before = out.size();
        bool                           named  = false;
        for( std::uint32_t f = 0; f < fileCount; ++f )
        {
            if( !pathSuffixMatches( rootRelPath( ing, f ), suffix ) )
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
        if( isIndexBaseName( baseNameOf( ing.files[f] ) ) && dirSuffixMatches( rootRelPath( ing, f ), m.segments )
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

// ── NAMED IDENTIFIERS (dogfood G2, 2026-09-26) ──────────────────────────────────────────────────────
//
// A task that names a symbol VERBATIM — `hybrid_search`, computeLensRanking, `run()`, `mod::fn`, `mod.fn` —
// names the place a reader looks first. extractMentions above reads only paths, dotted chains and backticked
// words, and resolves a dotted chain only as a file or as an exact Scope.name, so "How does hybrid_search rank
// search results" anchored nothing: the identifier was split into the subtokens `hybrid` and `search`, the three
// eval `run()` functions whose bodies CALL hybrid_search matched more of the prose, and the function itself was
// served at r=8 behind them (a public Python repo, 10,606 symbols).
//
// WHAT QUALIFIES (identifier evidence the writer supplied — plain prose never does):
//   * a bare word with identifier SHAPE (namesplit::hasIdentifierShape: snake_case, SCREAMING_CASE, camelCase);
//   * a word written with call syntax, `name(` — so `run()` qualifies and "run the tests" does not;
//   * a `::`-qualified spelling (`ns::fn`, `Type::method`, `crate::mod::fn`) — the last segment, qualified by the one before;
//   * a backticked word or a dotted chain that extractMentions kept but that resolved to NO file, NO Scope.name and
//     NO package directory — read here as its last segment, qualified by the one before (`search.hybrid_search`).
// Tokens joined to a '.' or '/' are extractMentions' territory and are never read twice.
//
// WHAT IT MATCHES: a symbol whose name EQUALS the identifier, byte for byte — every indexed language is
// case-sensitive except PHP's function, method and class names, which PHP resolves case-insensitively and so
// are compared case-folded here. Markdown sections and synthetic module scopes are not code symbols and never
// match. A qualifier NARROWS the match to definitions whose scope, file stem or directory is spelled that way;
// a qualifier that narrows to nothing (`df.to_csv`, a local variable) is not evidence, so the bare name is used
// instead — but only when the name carries identifier shape of its own (`std::vector` lifts no user `vector`).
//
// PRECISION OVER RECALL, the rule every lookup in this file follows: a name defined in more than
// kMentionMaxNameFiles files is AMBIGUOUS and lifts nothing (no reordering is better than a wrong head row —
// METHODOLOGY §9.1 #3). Within the files it names, only each file's best-scoring definition is lifted, so
// overloads and a header's decl beside its def never flood the head. The lifted symbols join the direct-symbol
// slot (the Scope.name slot), under the same kMentionMaxDirectSymbols cap and mention_syms_capped= disclosure.
inline constexpr std::size_t kMentionMaxNameFiles = 3;   // the same specificity bound as lexical.h kMaxAnchorDefs

struct NamedIdent
{
    std::string name;        // the identifier as the task spells it
    std::string qualifier;   // the segment before it in a qualified spelling; "" when bare or a placeholder
};

// A qualifier that names no place: Python's `self.`/`cls.`, Rust's `crate::`/`super::`/`self::`/`Self::`,
// JavaScript's `this.`. Treated as bare, so `self.hybrid_search` reads as `hybrid_search`.
inline bool isPlaceholderQualifier( std::string_view q ) noexcept
{
    return q == "self" || q == "cls" || q == "this" || q == "Self" || q == "crate" || q == "super";
}

// append (name, qualifier) once, in task-text order — the order the kMentionMaxDirectSymbols cap keeps.
inline void addNamedIdent( std::vector<NamedIdent>& out, std::string_view name, std::string_view qualifier )
{
    if( name.size() < 3 || !isIdentStart( name.front() ) )
    {
        return;   // the same 3-byte floor extractMentions applies; a digit-led token is a number, not a name
    }
    const std::string_view q = isPlaceholderQualifier( qualifier ) ? std::string_view() : qualifier;
    for( const NamedIdent& n : out )
    {
        if( n.name == name && n.qualifier == q )
        {
            return;
        }
    }
    out.push_back( { std::string( name ), std::string( q ) } );
}

// Scan the task for the bare, call-syntax and `::`-qualified identifiers described above, appending to `out`.
// Pure string work over the task text; no index access.
inline void extractNamedIdentifiers( std::string_view task, std::vector<NamedIdent>& out )
{
    std::size_t i = 0;
    while( i < task.size() )
    {
        if( !isIdentChar( task[i] ) )
        {
            ++i;
            continue;
        }
        const std::size_t start = i;
        std::string_view  prev, last;
        std::size_t       segCount = 0;
        for( ;; )
        {
            const std::size_t segStart = i;
            while( i < task.size() && isIdentChar( task[i] ) )
            {
                ++i;
            }
            prev = last;
            last = task.substr( segStart, i - segStart );
            ++segCount;
            if( i + 2 < task.size() && task[i] == ':' && task[i + 1] == ':' && isIdentChar( task[i + 2] ) )
            {
                i += 2;
                continue;
            }
            break;
        }
        ASSUME( i > start && segCount >= 1 && !last.empty() );
        const char before = start > 0 ? task[start - 1] : ' ';
        const char after  = i < task.size() ? task[i] : ' ';
        const bool joined = before == '/' || ( before == '.' && start >= 2 && isIdentChar( task[start - 2] ) ) || after == '/'
                         || ( after == '.' && i + 1 < task.size() && isIdentChar( task[i + 1] ) );
        if( joined )
        {
            while( i < task.size() && ( isTokenChar( task[i] ) || task[i] == ':' ) )
            {
                ++i;   // the rest of the path / dotted chain: extractMentions reads it, its tail is no bare name
            }
            continue;
        }
        if( segCount == 1 && before == '`' && after == '`' )
        {
            continue;   // a backticked word is a RawMention; applyMentionBoost falls back to it only if nothing else resolved
        }
        if( segCount == 1 && after != '(' && !hasIdentifierShape( last ) )
        {
            continue;   // plain prose ("run", "get", "search") — no identifier evidence
        }
        addNamedIdent( out, last, segCount > 1 ? prev : std::string_view() );
    }
}

// Does the symbol's name spell `name` under its language's own case rule?
inline bool symbolNameSpells( const Symbol& s, std::string_view name ) noexcept
{
    if( s.name == name )
    {
        return true;
    }
    const bool foldsCase = s.lang == Lang::Php
                        && ( s.kind == SymKind::Function || s.kind == SymKind::Method || s.kind == SymKind::Class || s.kind == SymKind::Interface );
    return foldsCase && std::ranges::equal( s.name, name, []( char a, char b )
                                            { return std::tolower( static_cast<unsigned char>( a ) ) == std::tolower( static_cast<unsigned char>( b ) ); } );
}

// Is `q` the symbol's scope, its file's stem, or its file's directory name?
inline bool qualifierPlaces( const IngestResult& ing, const Symbol& s, std::string_view q ) noexcept
{
    if( s.scope == q )
    {
        return true;
    }
    const std::string_view path = rootRelPath( ing, s.fileId );
    const std::string_view base = baseNameOf( path );
    if( stripExt( base ) == q )
    {
        return true;
    }
    const std::string_view dir = path.substr( 0, path.size() - base.size() );
    return dir.size() > 1 && baseNameOf( dir.substr( 0, dir.size() - 1 ) ) == q;
}

// Resolve each identifier, in `named` order, to at most kMentionMaxNameFiles symbols — each named file's best
// definition by (lensRank desc, id asc) — skipping an ambiguous or unmatched name. Appends to `out`, deduplicated.
inline void resolveNamedIdents( const IngestResult& ing, const std::vector<float>& lensRank, const std::vector<NamedIdent>& named,
                                std::vector<NodeId>& out )
{
    EXPECTS( lensRank.size() == ing.symbols.size() );
    ASSUME_NO_ALIAS( lensRank, out );
    std::vector<std::pair<std::uint32_t, NodeId>> perFile;   // (fileId, best symbol in it) for one identifier
    for( const NamedIdent& n : named )
    {
        const bool bareFallback = n.qualifier.empty() || hasIdentifierShape( n.name );
        std::vector<std::pair<std::uint32_t, NodeId>> narrowed, bare;
        const auto keepBest = []( std::vector<std::pair<std::uint32_t, NodeId>>& v, const Symbol& s, const std::vector<float>& rank )
        {
            for( auto& fileBest : v )
            {
                if( fileBest.first == s.fileId )
                {
                    const NodeId b = fileBest.second;
                    if( rank[s.id] > rank[b] || ( rank[s.id] == rank[b] && s.id < b ) )
                    {
                        fileBest.second = s.id;
                    }
                    return;
                }
            }
            v.emplace_back( s.fileId, s.id );
        };
        for( const Symbol& s : ing.symbols )
        {
            if( s.kind == SymKind::Section || s.kind == SymKind::ModuleScope || !symbolNameSpells( s, n.name ) )
            {
                continue;
            }
            ASSUME( s.id < lensRank.size() );
            if( !n.qualifier.empty() && qualifierPlaces( ing, s, n.qualifier ) )
            {
                keepBest( narrowed, s, lensRank );
            }
            if( bareFallback && narrowed.empty() && bare.size() <= kMentionMaxNameFiles )
            {
                keepBest( bare, s, lensRank );   // stops growing once ambiguous — the verdict is already decided
            }
        }
        perFile = !narrowed.empty() ? std::move( narrowed ) : ( bareFallback ? std::move( bare ) : decltype( bare ){} );
        if( perFile.empty() || perFile.size() > kMentionMaxNameFiles )
        {
            continue;   // unmatched, or ambiguous: precision over recall — no lift, no reordering
        }
        std::sort( perFile.begin(), perFile.end() );   // file order, a total order on (fileId, id)
        for( const auto& fileBest : perFile )
        {
            if( std::find( out.begin(), out.end(), fileBest.second ) == out.end() )
            {
                out.push_back( fileBest.second );
            }
        }
    }
}

} // namespace mention_detail

// Apply the mention anchor to `lensRank` (size == ing.symbols.size()). Returns true if anything moved.
inline bool applyMentionBoost( const IngestResult& ing, std::string_view task, std::vector<float>& lensRank, MentionBoostInfo* outInfo = nullptr )
{
    using namespace mention_detail;
    // EXPECTS, not DASSERT (rv-s2 review, 2026-09-19): same shape as gitmine.h's applyCoChangeBoost — every
    // caller's lensRank is sized from ing.symbols by construction (see that function's comment for the
    // callers/producers traced), so this is the function's real precondition, not a defensive fallback for a
    // reachable mismatch. The old `!= ing.symbols.size()` re-test below was dead code and is deleted with it.
    EXPECTS( lensRank.size() == ing.symbols.size() );
    if( task.empty() || lensRank.empty() )
    {
        return false;
    }

    // The census is written into outInfo as each fact is known, BEFORE the early returns below: a task whose
    // only named file fell outside the window lifts nothing, returns false, and still owes the caller this.
    std::uint32_t qualifiedTokens = 0;
    const std::vector<RawMention> raw = extractMentions( task, &qualifiedTokens );
    noteCap( outInfo, "mention_tokens_capped", "mention_tokens_total", qualifiedTokens > kMentionMaxRawTokens, qualifiedTokens );
    std::vector<NamedIdent> bareNamed;   // (d): bare / call-syntax / `::`-qualified identifiers — NAMED IDENTIFIERS above
    extractNamedIdentifiers( task, bareNamed );
    if( raw.empty() && bareNamed.empty() )
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
    std::vector<NamedIdent>    named;                                // (d): identifiers named verbatim, text order
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
                if( !pathSuffixMatches( rootRelPath( ing, f ), suffix ) )
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
        const std::size_t filesBeforeDir = mentionedFiles.size();
        if( !matchedFile && !matchedSymbol )
        {
            liftPackageDirMention( ing, m, mentionedFiles );
        }

        // (d) a backticked word or dotted chain that named no file, no Scope.name and no package directory is read
        //     as the identifier it spells — its last segment, qualified by the one before (NAMED IDENTIFIERS,
        //     above). Only while the file list has room: a full list stopped (a) and (c) early, so "matched
        //     nothing" would not be proven, and an earlier rule's reading must never be taken over by this one.
        if( !matchedFile && !matchedSymbol && !m.isPath && mentionedFiles.size() == filesBeforeDir && mentionedFiles.size() < kMentionMaxFiles )
        {
            addNamedIdent( named, m.segments.back(), m.segments.size() >= 2 ? std::string_view( m.segments[ m.segments.size() - 2 ] ) : std::string_view() );
        }
    }

    // (d) continued — the bare, call-syntax and `::`-qualified identifiers extractMentions does not read, then one
    //     resolution for all of them. Each lifted symbol is one more direct symbol: same slot, same cap, same total.
    for( const NamedIdent& n : bareNamed )
    {
        addNamedIdent( named, n.name, n.qualifier );
    }
    std::vector<NodeId> namedSymbols;
    resolveNamedIdents( ing, lensRank, named, namedSymbols );
    for( const NodeId id : namedSymbols )
    {
        if( std::find( directSymbols.begin(), directSymbols.end(), id ) != directSymbols.end() )
        {
            continue;   // already a Scope.name match — counted once
        }
        ++directSymbolTotal;
        if( directSymbols.size() < kMentionMaxDirectSymbols )
        {
            directSymbols.push_back( id );
        }
    }
    ENSURES( directSymbols.size() <= kMentionMaxDirectSymbols && directSymbols.size() <= directSymbolTotal );
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

    // pass 2 — lift. Slot ladder: file i's symbols land at top*(1 - step*(i+1)). max() keeps anything the
    // ranker already scored higher exactly where it was.
    std::uint32_t liftedSymbolCount = 0;
    const auto lift = [ & ]( NodeId id, float target )
    {
        if( lensRank[id] < target ) { lensRank[id] = target; ++liftedSymbolCount; }
    };

    // ANSWER FIRST (METHODOLOGY §9.1 #3): a symbol the task names DIRECTLY — Scope.name, or a verbatim identifier
    // (NAMED IDENTIFIERS above) — lands one step ABOVE the current top, so the row the question names leads the
    // head. The 5%-below slot this used to share with file anchors is a score promise that a flat head defeats:
    // with several unanchored candidates tied at the top, the named symbol landed below every one of them (the
    // r=8 dogfood miss sat under a 3-way flat head). File anchors keep the below-#1 slot — a file mention says where
    // to look, not which of its symbols is the answer. Nothing moves when every named symbol already scores at the
    // top: the ranker agreed, and re-scoring it would only perturb the head's cliff statistics for no reordering.
    std::sort( directSymbols.begin(), directSymbols.end() );
    directSymbols.erase( std::unique( directSymbols.begin(), directSymbols.end() ), directSymbols.end() );
    const bool namedAlreadyLead = std::all_of( directSymbols.begin(), directSymbols.end(), [ & ]( NodeId id ) { return lensRank[id] >= topScore; } );
    if( !namedAlreadyLead )
    {
        const float answerFirstSlot = topScore * ( 1.0f + kMentionTopGapStep );
        for( const NodeId id : directSymbols )
        {
            lift( id, answerFirstSlot );
        }
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
            lift( best[k], topScore * ( 1.0f - kMentionTopGapStep * float( fi + 1 ) ) );
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
    ASSUME_NO_ALIAS( order, out );
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
    ASSUME( g.mentions.empty() || g.mentions.size() == N );
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

// ── R2-AF (round 2, answer-first ordering) — the S4 "named file's decl/impl partner" lookup ────────────
//
// --for's ranked rows answer "what is relevant"; they can never answer "what else has to change with the
// file the task already names", because a header does not transitively depend on its own implementation
// and a ranker has no evidence to promote it on. This is the --for-side analogue of --situ's decl/def
// partner block (situ.h declDefPartners) for a CHANGED file's symbol overlap — here there is no diff to
// read symbols from, so the test is purely LEXICAL: same directory, same stem, a fixed decl/impl
// extension. Two files that happen to share a directory and a stem almost always ARE the pair; nothing
// downstream reads this as a graph or ranking fact (§R7: "a lookup, not a ranked or graph-derived row").
//
// RESOLUTION (round-2 amendment §R7, verbatim). A row is emitted only when the named path resolves to
// EXACTLY ONE indexed file, through the SAME normalisation mention_anchored= uses (mention_detail::
// pathSuffixMatches — the longest matching suffix wins and ends resolution; a `./` prefix or a repo-name
// prefix falls out of extractMentions' own trimming and the suffix match, not a second rule here). The
// partner must resolve to exactly one indexed same-directory, same-stem file with a DIFFERENT extension,
// tried in a fixed order (a source's header: .h, .hpp, .hh; a header's source: .cc, .cpp, .c) — anything
// else names no partner: precision over recall, the same rule every other mention lookup in this file
// follows. A partner that is ITSELF named elsewhere in the task is dropped (the reader already asked for
// it by name); multiple named files are handled in the task's own text order.
//
// Shared by the CLI --for (verbs_for.h) and the MCP `for` twin (mcpverbs.h forTaskText) — ONE resolver, so
// the two surfaces cannot answer this lookup differently. Rendering (root-relative paths, XML escaping)
// stays at each call site: this file does not depend on sarif.h/serialize.h, and siblift.h already
// depends on THIS header for its slot-ladder constants, so a dependency the other way would be circular.
struct ForNamedHeaderRow
{
    std::uint32_t namedFile   = 0;   // the file the task names
    std::uint32_t partnerFile = 0;   // its one same-directory, same-stem decl/impl partner
};

namespace mention_detail
{

// the file extension (no dot), or "" when the basename carries none — DERIVED from stripExt() rather than
// a second rfind('.'): quality-delta flagged the first cut as a new clone of that reused helper (both were
// "find the last dot, slice around it"), so this composes stripExt's own answer instead of re-deriving it,
// the same way pathStem above is stripExt(baseNameOf(path)) rather than its own scan.
inline std::string_view fileExtOf( std::string_view path ) noexcept
{
    const std::string_view base = baseNameOf( path );
    const std::string_view stem = stripExt( base );
    return stem.size() == base.size() ? std::string_view() : base.substr( stem.size() + 1 );
}

// path minus its basename (no trailing '/'), or "" at the root — composed from baseNameOf rather than a
// second rfind('/'), and DELIBERATELY not siblift_detail::dirOf: siblift.h includes this header for its
// slot-ladder constants, so this header including siblift.h back would be circular.
inline std::string_view forHdrDirOf( std::string_view path ) noexcept
{
    const std::string_view base = baseNameOf( path );
    return base.size() == path.size() ? std::string_view() : path.substr( 0, path.size() - base.size() - 1 );
}

// -1 = no decl/impl convention this lookup knows; 0 = a SOURCE (look for a header partner); 1 = a HEADER
// (look for a source partner). Deliberately the §R7 fixed list, not a language table: guessing a
// convention this lookup cannot verify is worse than naming no partner at all.
inline int forHeaderPartnerKind( std::string_view ext ) noexcept
{
    if( ext == "cc" || ext == "cpp" || ext == "c" )  { return 0; }
    if( ext == "h" || ext == "hpp" || ext == "hh" )  { return 1; }
    return -1;
}

// Resolve ONE mention to a unique indexed file: try the longest suffix of its segments first (the same
// order applyMentionBoost's file pass uses), stopping at the first suffix length with any match at all —
// a shorter suffix is consulted only when a longer one matched NOTHING. Unlike applyMentionBoost, this
// requires the match to be UNIQUE at that length: 0 or >1 files name nothing this lookup can act on, and
// a shorter suffix is never tried once a longer one has matched anything (ambiguous or not) — the same
// "longest suffix ends resolution" rule mentionUnkeptFiles states above.
inline bool resolveUniqueMentionFile( const IngestResult& ing, const RawMention& m, std::uint32_t& outFile ) noexcept
{
    if( !m.isPath || m.segments.empty() )
    {
        return false;
    }
    const std::uint32_t fileCount = std::uint32_t( ing.files.size() );
    for( std::size_t suffixLen = m.segments.size(); suffixLen >= 1; --suffixLen )
    {
        const std::vector<std::string> suffix( m.segments.end() - suffixLen, m.segments.end() );
        std::uint32_t                  count = 0, match = 0;
        for( std::uint32_t f = 0; f < fileCount; ++f )
        {
            if( pathSuffixMatches( rootRelPath( ing, f ), suffix ) )
            {
                ++count;
                match = f;
            }
        }
        if( count == 1 )
        {
            outFile = match;
            return true;
        }
        if( count > 1 )
        {
            return false;   // ambiguous at the longest matching length — not a unique answer
        }
    }
    return false;
}

// The partner: same directory, same stem, a DIFFERENT extension tried in the §R7 fixed order. Exactly one
// candidate at an extension wins; zero moves to the next extension in the list; more than one (a same-stem
// collision across indexed roots) is not a unique answer either, and the lookup moves on rather than guess.
inline bool resolveUniquePartnerFile( const IngestResult& ing, std::uint32_t namedFile, std::uint32_t& outPartner ) noexcept
{
    ASSUME( namedFile < ing.files.size() );
    const std::string_view path = ing.files[ namedFile ];
    const int              kind = forHeaderPartnerKind( fileExtOf( path ) );
    if( kind < 0 )
    {
        return false;
    }
    static constexpr std::array<std::string_view, 3> kHeaderExts = { "h", "hpp", "hh" };
    static constexpr std::array<std::string_view, 3> kSourceExts = { "cc", "cpp", "c" };
    const auto&            tryExts   = kind == 0 ? kHeaderExts : kSourceExts;
    const std::string_view dir       = forHdrDirOf( path );
    const std::string_view stem      = stripExt( baseNameOf( path ) );
    const std::uint32_t    fileCount = std::uint32_t( ing.files.size() );
    for( const std::string_view partnerExt : tryExts )
    {
        std::uint32_t count = 0, match = 0;
        for( std::uint32_t f = 0; f < fileCount; ++f )
        {
            if( f == namedFile || forHdrDirOf( ing.files[f] ) != dir )
            {
                continue;
            }
            const std::string_view fbase = baseNameOf( ing.files[f] );
            if( stripExt( fbase ) != stem || fileExtOf( ing.files[f] ) != partnerExt )
            {
                continue;
            }
            ++count;
            match = f;
        }
        if( count == 1 )
        {
            outPartner = match;
            return true;
        }
    }
    return false;
}

} // namespace mention_detail

// The task's S4 header rows, in text order, deduplicated by named file, each with exactly one partner
// that is not itself named anywhere in the task. Empty when the task names no file with a unique partner
// — the common case, and the feature is byte-identical to before it on every such task (AF's self-reject
// band: 0 gold lost, 0 rows on a task that names nothing the index agrees is unique).
inline std::vector<ForNamedHeaderRow> forNamedHeaderRows( const IngestResult& ing, std::string_view task )
{
    using namespace mention_detail;
    std::vector<ForNamedHeaderRow> out;
    if( task.empty() )
    {
        return out;
    }
    const std::vector<RawMention> raw = extractMentions( task );

    // pass 1: every path mention this task names, resolved to a unique file, text order, deduplicated —
    // needed whole before pass 2, because a LATER mention can name THIS mention's partner (§R7's rule).
    std::vector<std::uint32_t> allNamed;
    for( const RawMention& m : raw )
    {
        std::uint32_t f;
        if( resolveUniqueMentionFile( ing, m, f ) && std::find( allNamed.begin(), allNamed.end(), f ) == allNamed.end() )
        {
            allNamed.push_back( f );
        }
    }

    for( const std::uint32_t namedFile : allNamed )
    {
        std::uint32_t partner;
        if( !resolveUniquePartnerFile( ing, namedFile, partner ) )
        {
            continue;
        }
        if( std::find( allNamed.begin(), allNamed.end(), partner ) != allNamed.end() )
        {
            continue;   // the partner is itself named in the task — no lookup row for it
        }
        out.push_back( { namedFile, partner } );
    }
    ENSURES( out.size() <= allNamed.size() );
    return out;
}

} // namespace rw

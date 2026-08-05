#pragma once

// docdrift.h — `--doc-drift`, the DOC-ANCHOR VERIFIER.
// Evidence: four parallel audit agents burned tokens re-verifying stale doc claims — a §Status six weeks
// wrong, dead `file:line` anchors, `[16]` arrays that are now 18, "= 10" constants now 15. A doc's PROSE is
// not checkable, but a doc's ANCHORS are: they name a file, a line, a symbol, or a number that the index
// can be asked about. This verb asks, and reports ONLY the anchors that no longer hold.
//
// ── the four anchor kinds ────────────────────────────────────────────────────────────────────────────────
//   file-line — `src/main.cpp:2332`. Checked in three steps, each reported separately so a failure names
//               its own cause: does the path still resolve to an indexed file (missing-file); is the line
//               still inside that file (past-eof); and, when the doc names a symbol on the SAME line, does
//               that line still sit inside THAT symbol (line-moved, with got= naming the squatter).
//   symbol    — a backticked identifier. Reported as drift ONLY when the name occurs NOWHERE in the code
//               as an identifier token — see the false-positive rule below.
//   const     — `kFoo = 10`. Compared against the one declaration-shaped integer literal the corpus binds
//               to that name; two different values in the tree ⇒ not comparable, reported unchecked.
//   array     — `kFoo[16]` (or a bare `[16]` on a line whose single backticked name is a known array).
//               Same comparison against the declared extent.
//
// ── the false-positive rule (the whole design constraint) ────────────────────────────────────────────────
// A doc-drift verb that cries wolf is worse than none: an agent that gets one bogus "stale" row goes back to
// re-verifying everything by hand, which is the cost this verb exists to remove. So every lane is biased to
// UNDER-report, and the bias is stated rather than hidden:
//   * A backticked name is drift only if it appears nowhere in any non-markdown file as an identifier token.
//     `std::vector`, `open_memstream`, `getenv` and every other library name is therefore silent, and so is
//     any repo constant the grammar does not tag as a definition (namespace-scope `constexpr` in C++, for
//     one). Those land in the unchecked tally as `not-a-definition`, never as drift.
//   * A `= N` / `[N]` claim is compared only against a DECLARATION-shaped literal (a decl keyword on the
//     line, or the name opening the line — so `x = 5` inside a function body is not a "definition"), and
//     only when the corpus binds exactly ONE value to the name. Disagreement across the tree ⇒ unchecked.
//   * A `NAME = N` whose NAME appears nowhere in the code is PROSE, not a broken anchor. Those are counted
//     in prose= and never enter the anchor tally — the verb does not claim to have checked them.
// Every anchor the verb declines to check is COUNTED, with its reason and a note, in the <unchecked> rows.
// checked + unchecked == anchors, always: nothing is dropped silently.
//
// ── the mention lane's own gap, and the oracle that closes it (--with-history) ───────────────────────────
// "Defined nowhere in this repo" is NOT "deleted". A PLAN or DESIGN doc naming work that was never built
// makes the exact same shape as a doc still citing a symbol someone removed, and only the second is rot.
// This was the weakest lane precisely because separating them needs git HISTORY, which the verb had no
// affordable way to consult: at the 247 candidate names one real repo produced, `git log -S<name>` per name
// costs ~126 s (measured — see gitoracle.h's table). gitoracle.h now answers all of them in ONE `git log`
// pass, so with --with-history the lane splits three ways instead of collapsing to "undefined":
//   why="deleted"                   — history removed the name, and the row names the commit, date and file
//   unchecked r="never-in-history"  — no commit ever removed it either: it was never here, so it is not rot
//   unchecked r="history-no-answer" — the probe makes no claim (walk bound, or a name too short to track)
// WITHOUT the flag the lane behaves exactly as before (why="undefined"), because the probe costs seconds and
// this verb's default path is measured in milliseconds.
//
// ── the DATED-RECORD lane: an anchor the author dated is a record, not a live claim ──────────────────────
// The verb's own CI dogfood ran `|| true` for one reason: an AUDIT doc's finding row ("Defect. `runEditVerb`
// (src/mcp.h:1582) does an unlocked read-modify-write") is an accurate HISTORICAL note, and it makes exactly
// the same shape as a live map gone stale. Both are "the code moved and the doc did not". So this lane does
// NOT try to judge which claims are still true — it reports which ones the AUTHOR MARKED as observations
// made at a time, in four escalating strengths (most specific evidence wins):
//   rec="line"   the anchor's own line hedges it ("…`kMcpVerbCount = 22` at the time of this note; 30 as of
//                2026-07-24"), or the line OPENS with an ISO date (a changelog / ledger row)
//   rec="block"  the nearest markdown heading at or above it carries an ISO date ("### §2b — … (2026-07-11
//                addendum)")
//   rec="title"  the doc's FILENAME or its H1 carries an ISO date — the author saying "this document IS the
//                artifact of that day"
//   rec="stamp"  the doc's front matter carries a LABELLED self-date ("Date: 2026-07-05", "Written 2026-06-23")
// A record still PRINTS, with kind="dated-record"; it just leaves drift= for dated=. drift + dated == the
// number the lane-free verb reported, so nothing is reclassified out of sight.
//
// TWO CANDIDATE SIGNALS WERE MEASURED AND REJECTED, because shipping a heuristic that cannot be defended is
// worse here than shipping a smaller one:
//   * git history ("was the anchor CORRECT at the doc's own last-touched commit?"). Measured over this
//     repo's 98 file:line drift rows: 90 held at their doc's own commit — audit findings and live design-doc
//     maps alike. The question it answers is "has the doc been updated since the code moved", which is the
//     DEFINITION of both a record and rot, so it separates neither. (The 8 that did not hold are docs a later
//     commit touched for an unrelated reason, not evidence of anything.) history is genuinely load-bearing
//     for the MENTION lane and stays there; for the location and value lanes it has no discriminating power.
//   * an ISO date ANYWHERE in the front matter. Measured: it admits three LIVE documents on this repo alone —
//     a phase ledger, a policy log and a design study — each on a date the doc TALKS ABOUT ("the 2026-07-12
//     whole-system audit", "(Lego round, 2026-06-19)"). Hence the label bar on rec="stamp".
//
// The lane's own honest limit: a doc that is manifestly an artifact-of-a-date to a human but never writes
// that date where a machine can read it (this repo has two such audits) is reported as LIVE. The bias is
// deliberate and one-directional — a wrong "record" hides real rot, a wrong "live" merely over-reports — and
// the fix is one line in the doc, not a looser rule here.
//
// ── what it deliberately does NOT check ──────────────────────────────────────────────────────────────────
// Prose claims of any kind, §Status lines, dates, "N of M done" tallies, and the correctness of a code
// block's body. Those need a judgement this verb cannot make, so it makes none.
//
// Determinism: docs come from the caller's already-sorted ingest file list; anchors are emitted in
// (doc, line, column) order; every corpus fact is a pure function of file bytes; no wall clock, no hashing
// of addresses. Two runs on a fixed tree are byte-identical.

#include "model.h"
#include "arch.h"         // relForHash
#include "serialize.h"    // escapeXml
#include "pageview.h"     // §P8: pageWindow / pageDisclosure — the shared --limit/--offset contract
#include "tracelocus.h"   // traceMatchFile / traceEnclosingSymbol — the SHARED frame→corpus resolver
#include "darkflags.h"    // readWhole / identByte / trimView — the shared lexical helpers (no second copy)
#include "docparse.h"     // isDocExtension — which indexed files are DOCUMENTS, not code
#include "gitoracle.h"    // the SHARED name-history oracle — "was this name ever here, and when did it leave?"
#include "ingest.h"       // isSkippedCrawlDir — the SHARED crawl denylist, for the on-disk existence probe
#include "mention.h"      // mention_detail::pathSuffixMatches — the whole-segment suffix match
#include "workspace.h"    // wsdetail::segmentsOf
#include "svector.h"      // rw::svector — small basename→path lists
#include "Diagnostics.h"  // VERIFY / DEGRADED_PATH_ALERT
#include "gitstamp.h"     // r26-stamp Task A: gitstamp::stampAt — the at="<sha>[+dirty]" root anchor
#include "layout.h"       // layout::isCFamilyPath — shared C/C++/ObjC/CUDA extension classifier

#include <algorithm>
#include <atomic>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <functional>
#include <span>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

namespace rw
{
namespace docdrift
{

// ── tuning constants (every bound the report rests on, in one place) ─────────────────────────────────────

constexpr std::size_t   kMaxAnchorsShown = 12;      // drifted anchors printed per doc; detail lifts the cap
constexpr std::size_t   kMinMentionLen   = 4;       // a backticked name shorter than this is prose, not code
constexpr std::size_t   kMinValueNameLen = 3;       // …and the bar for a `= N` / `[N]` subject name
constexpr std::size_t   kMaxNameLen      = 96;      // past this it is a sentence, not an identifier
constexpr std::size_t   kMaxDecDigits    = 10;      // overflow guard on a doc/code integer literal
constexpr std::size_t   kMaxHexDigits    = 15;      // …hex fits 15 nibbles in 64 bits with room to spare
constexpr std::size_t   kMaxExtLen       = 6;       // "cpp", "swift", "metal" — longer is not an extension
constexpr std::uint64_t kMinBareExtent   = 2;       // a bare `[0]`/`[1]` is prose/markdown, not an extent
constexpr std::uint64_t kMaxClaimedLine  = 200000;  // past this a "line number" is a hostile-input example, not a claim
constexpr std::uint32_t kAnchorSlack     = 20;      // lines above a def an anchor may point at (its doc comment)
// How far from a backticked mention a name this repo DOES define must appear for the mention to count as a
// claim about this code rather than an illustration. 0 = the same line. Measured both ways on two real
// repos: widening to ±2 lines doubled the mention lane's output and every added row was noise (external
// APIs discussed in prose, plan-doc names for unbuilt features), so the tight setting is the shipped one.
constexpr std::uint32_t kCorroborateWin  = 0;

// The dated-record lane's one bound: a self-date belongs to the doc's HEADER, not to its body, so the
// front-matter window stops at the first `##` section and never runs past this many lines. (The label→date
// gap has no numeric bound on purpose — see introducesDate: proximity was tried and the fixture's negative
// control broke it, so the rule is "nothing but punctuation between them", which is exact.)
constexpr std::size_t   kMaxFrontMatter  = 12;

// ── anchor kinds, drift verdicts and unchecked reasons: declarative tables, not switch chains ────────────

enum class AnchorKind : std::uint8_t { FileLine = 0, Symbol, Const, Array };

inline constexpr const char* kAnchorKindTag[] = { "file-line", "symbol", "const", "array" };

inline const char* anchorKindTag( AnchorKind k ) noexcept { return kAnchorKindTag[ std::size_t( k ) ]; }

// `Deleted` is a STRONGER claim than `Undefined`, not a rename of it: undefined says only "no definition
// here", deleted says "this repo HAD it and commit X removed it". Only the history oracle can say the second,
// so a run without --with-history never emits it.
enum class Drift : std::uint8_t { Holds = 0, MissingFile, PastEof, LineMoved, Undefined, Deleted, ConstValue, ArrayExtent };

inline constexpr const char* kDriftTag[] = { "holds", "missing-file", "past-eof", "line-moved", "undefined", "deleted", "const-value", "array-extent" };

inline const char* driftTag( Drift d ) noexcept { return kDriftTag[ std::size_t( d ) ]; }

// Why an anchor was recognised but NOT verified. Each carries the note that ships in the report, so the
// reader never has to guess how much the verb actually proved.
enum class Unchecked : std::uint8_t
{
    WeakFileLine = 0, NamedElsewhere, NotIndexed, NotADefinition, ForeignScope, Uncorroborated, AmbiguousValue, NoDefSite,
    NeverInHistory, HistoryNoAnswer, Count
};

struct UncheckedSpec { const char* tag; const char* note; };

inline constexpr UncheckedSpec kUncheckedTable[] = {
    { "weak-file-line",  "no symbol named on the anchor's line: file existence and the EOF bound were checked, symbol identity was not" },
    { "named-elsewhere", "the symbol named beside this anchor is not defined in the anchored file, so the doc is pointing at a call site or a neighbouring fact rather than that definition: existence and the EOF bound were checked, symbol identity was not" },
    { "not-indexed",     "the anchored file exists in the tree but is not in the index (an excluded directory, or a language ripwire does not parse), so neither the line bound nor symbol identity could be checked" },
    { "not-a-definition","the name occurs in the code as an identifier token but is not an indexed definition (library API, macro, build variable, or a declaration kind the grammar does not tag): presence checked, definition not" },
    { "foreign-scope",   "the mention is qualified by a scope this repo does not define, so it names another project's API rather than this code" },
    { "uncorroborated",  "no name this repo DOES define appears on the mention's own line, so it reads as an illustrative or external identifier rather than a claim about this code" },
    { "ambiguous-value", "the corpus binds more than one distinct literal to this name, so the doc's number has no single value to disagree with" },
    { "no-def-site",     "the name occurs in the code but never in a declaration-shaped integer literal (computed, expression-valued, or declared in a form this verb does not read)" },
    { "never-in-history",  "the name is defined nowhere in the code AND no commit reachable from HEAD ever removed a line carrying it, so this repo never had it as code: a plan or design doc naming work that was not built, which is not rot" },
    { "history-no-answer", "the name is defined nowhere and the history probe makes no claim about it — either the walk hit its bound, or the name is shorter than the length the probe tracks — so nothing is asserted either way" },
};

static_assert( sizeof( kUncheckedTable ) / sizeof( kUncheckedTable[0] ) == std::size_t( Unchecked::Count ),
               "kUncheckedTable drifted from the Unchecked enum — update both together" );

// How the AUTHOR dated this anchor. `Live` is not "we proved it is a live claim" — it is "no dating mark was
// found", which is the honest default and the one that keeps a row in drift=.
enum class Record : std::uint8_t { Live = 0, Line, Block, Title, Stamp, Count };

struct RecordSpec { const char* tag; const char* note; };

inline constexpr RecordSpec kRecordTable[] = {
    { "live",  "no dating mark was found on the line, its heading, the title or the front matter, so the doc reads as claiming this NOW" },
    { "line",  "the anchor's own line dates the claim — an at-the-time / as-of-DATE hedge, or a line that opens with an ISO date (a changelog or ledger row)" },
    { "block", "the nearest markdown heading at or above the anchor carries an ISO date, so the whole section is an observation made on that day" },
    { "title", "the doc's filename or its H1 title carries an ISO date: the document IS the artifact of that day, and its anchors are what was true then" },
    { "stamp", "the doc's front matter carries a LABELLED self-date (Date: / Written / Generated / Recorded …), which dates the document rather than something it discusses" },
};

static_assert( sizeof( kRecordTable ) / sizeof( kRecordTable[0] ) == std::size_t( Record::Count ),
               "kRecordTable drifted from the Record enum — update both together" );

inline const char* recordTag( Record r ) noexcept { return kRecordTable[ std::size_t( r ) ].tag; }

// ── one anchor, from the doc line that carries it to the verdict the corpus gives it ─────────────────────

struct Anchor
{
    AnchorKind    kind    = AnchorKind::Symbol;
    std::uint32_t line    = 0;                  // 1-based line in the DOC
    std::uint32_t col     = 0;                  // 1-based column in that line (spot-checking a finding by hand)
    std::string   ref;                          // the anchor exactly as the doc writes it
    std::string   name;                         // the symbol / constant / array name it turns on ("" ⇒ none named)
    std::string   scope;                        // the qualifier a mention was written with (`A` in `A::b`); "" if bare
    std::uint64_t want    = 0;                  // file-line: the claimed line. const/array: the claimed number.
    Drift         why     = Drift::Holds;
    bool          isChecked = false;            // false ⇒ `skip` says which check the verb declined to make
    bool          isProse   = false;            // a `= N` / `[N]` shape whose NAME is absent from the code —
                                                //   never an anchor, so it leaves the tally instead of inflating it
    Unchecked     skip    = Unchecked::WeakFileLine;
    Record        rec     = Record::Live;       // how the AUTHOR dated this anchor — Live ⇒ it reads as a claim about NOW
    std::string   got;                          // what the corpus actually says (empty when there is nothing to say)
    std::string   tgt;                          // the corpus site backing `got`, as "path:line" or "path". Emitted as
                                                //   tgt=, NOT at=: at= is the document-level "<sha>[+dirty]" provenance
                                                //   stamp on the root element, and one attribute name may not mean two
                                                //   things in one document (r27 P2 item 7).
};

inline bool anchorLess( const Anchor& a, const Anchor& b )
{
    if( a.line != b.line )
    {
        return a.line < b.line;
    }
    if( a.col != b.col )
    {
        return a.col < b.col;
    }
    return std::size_t( a.kind ) < std::size_t( b.kind );
}

struct DocRow
{
    std::string         path;                   // root-relative
    std::vector<Anchor> drifted;                // ONLY the anchors that no longer hold, in (line, col) order
    std::uint32_t       anchorCount  = 0;
    std::uint32_t       checkedCount = 0;
    std::uint32_t       datedCount   = 0;       // …of `drifted`, how many the author dated (the rest are live rot)
};

struct DriftResult
{
    std::vector<DocRow> docs;                   // only docs WITH drift; LIVE-drift desc, path asc (§P11.10)
    std::uint32_t       docsScanned = 0;
    std::uint32_t       cleanDocs   = 0;
    std::uint32_t       anchors     = 0;
    std::uint32_t       checked     = 0;
    std::uint32_t       drift       = 0;        // anchors that no longer hold AND read as LIVE claims — the rot
    std::uint32_t       dated       = 0;        // …and the ones the author dated. drift + dated == every failed anchor.
    std::uint32_t       prose       = 0;        // `= N` / `[N]` shapes whose NAME is absent from the code
    std::uint32_t       uncheckedBy[ std::size_t( Unchecked::Count ) ] = {};
    std::uint32_t       datedBy[ std::size_t( Record::Count ) ]        = {};
    std::size_t         corpusFiles = 0;
    std::string         filter;
    std::string         atStamp;                // r26-stamp Task A: gitstamp::stampAt(root) — "" on a non-git root

    // A non-owning view of the caller's history index (--with-history), kept so the report can STATE what
    // the probe did. Views at the seam: the caller owns the index and outlives both the compute and the
    // write. nullptr ⇒ the probe was never asked for, and no <history> element is emitted at all.
    const gitoracle::HistoryIndex* history = nullptr;
};

// ── lexical helpers (the shared ones come from darkflags.h; these are doc-drift's own) ───────────────────

// docparse.h owns lowerExtOf (it is the header every extension classifier here already consults); this
// alias keeps the call sites below reading as local vocabulary without a second copy of the loop.
using docparse::lowerExtOf;

inline bool isMarkdownPath( std::string_view path )
{
    const std::string ext = lowerExtOf( path );
    return ext == ".md" || ext == ".markdown";
}

// A file the index carries as a DOCUMENT rather than as code (docparse.h: notebooks, exported HTML, CSV).
// It must not vouch for a name, and its numbers are not declarations — an exported HTML report claiming
// `storyA_reserved[2]` is a rendering of a doc, not the code the doc is being checked against.
inline bool isIndexedDocPath( std::string_view path )
{
    return isMarkdownPath( path ) || docparse::isDocExtension( lowerExtOf( path ) );
}

// Split a qualified spelling into its final segment and the scope directly above it:
// `rw::docdrift::foo` → { foo, docdrift }, `Type.method` → { method, Type }, `foo` → { foo, "" }.
// The scope is what tells an external API (`infra::DispatchSystem`, `String.toSlug`) from one of ours.
inline void splitQualified( std::string_view s, std::string_view& leaf, std::string_view& scope )
{
    leaf  = s;
    scope = {};
    const std::size_t colon = s.rfind( "::" );
    if( colon != std::string_view::npos )
    {
        leaf  = s.substr( colon + 2 );
        scope = s.substr( 0, colon );
        const std::size_t prev = scope.rfind( "::" );
        if( prev != std::string_view::npos )
        {
            scope = scope.substr( prev + 2 );
        }
        return;
    }
    const std::size_t dot = s.rfind( '.' );
    if( dot != std::string_view::npos ) { leaf = s.substr( dot + 1 ); scope = s.substr( 0, dot ); }
}

// This verb's name-length window over the shared identifier shape (darkflags.h, beside identByte) — one
// predicate, so the doc lane and the env lane cannot come to disagree about what an identifier is.
inline bool identOk( std::string_view s, std::size_t minLen ) noexcept
{
    return darkflags::isIdentShaped( s, minLen, kMaxNameLen );
}

// Does this identifier LOOK like code rather than an English word? snake_case, a camelCase/PascalCase seam,
// SCREAMING_CASE, or the k-prefixed constant idiom. This is the filter that keeps `something`, `however` and
// `Status` out of the anchor tally — deliberately strict, because a prose word admitted here becomes a
// false "stale doc" row the moment it happens to be absent from the code.
inline bool codeShaped( std::string_view s ) noexcept
{
    bool hasUnderscore = false, hasLower = false, hasUpper = false, camelSeam = false;
    for( std::size_t i = 0; i < s.size(); ++i )
    {
        const unsigned char c = (unsigned char)s[i];
        if( c == '_' ) { hasUnderscore = true; continue; }
        if( std::islower( c ) )
        {
            hasLower = true;
        }
        if( std::isupper( c ) )
        {
            hasUpper = true;
            if( i > 0 && std::islower( (unsigned char)s[i - 1] ) )
            {
                camelSeam = true;
            }
        }
    }
    const bool screaming  = hasUpper && !hasLower;
    const bool kConstIdiom = s.size() > 1 && s[0] == 'k' && std::isupper( (unsigned char)s[1] );
    return hasUnderscore || camelSeam || screaming || kConstIdiom;
}

// An integer literal at s[i]: decimal or 0x-hex, `_` separators skipped, u/U/l/L suffixes consumed.
// Digit counts are capped well inside 64 bits, so the accumulate below can never wrap (G1 runs
// -fsanitize=integer, where a wrap is a hard error, not a quirk).
inline bool parseIntLiteral( std::string_view s, std::size_t& i, std::uint64_t& out )
{
    if( i >= s.size() || !std::isdigit( (unsigned char)s[i] ) )
    {
        return false;
    }

    std::uint64_t value  = 0;
    std::size_t   digits = 0;
    if( s[i] == '0' && i + 1 < s.size() && ( s[ i + 1 ] == 'x' || s[ i + 1 ] == 'X' ) )
    {
        i += 2;
        while( i < s.size() && ( std::isxdigit( (unsigned char)s[i] ) || s[i] == '_' ) )
        {
            if( s[i] == '_' ) { ++i; continue; }
            if( ++digits > kMaxHexDigits )
            {
                return false;
            }
            const unsigned char c = (unsigned char)std::tolower( (unsigned char)s[i] );
            value = value * 16u + std::uint64_t( std::isdigit( c ) ? c - '0' : c - 'a' + 10 );
            ++i;
        }
        if( digits == 0 )
        {
            return false;
        }
    }
    else
    {
        while( i < s.size() && ( std::isdigit( (unsigned char)s[i] ) || s[i] == '_' ) )
        {
            if( s[i] == '_' ) { ++i; continue; }
            if( ++digits > kMaxDecDigits )
            {
                return false;
            }
            value = value * 10u + std::uint64_t( s[i] - '0' );
            ++i;
        }
    }
    while( i < s.size() && ( s[i] == 'u' || s[i] == 'U' || s[i] == 'l' || s[i] == 'L' ) )
    {
        ++i;
    }
    out = value;
    return true;
}

// In CODE, after a literal the expression must END — `;`, `,`, a closer, a comment, or the line. This is
// what makes `kX = 4u << 20` decline to be a comparable constant instead of silently reporting the value 4.
inline bool literalTerminates( std::string_view s, std::size_t i )
{
    while( i < s.size() && ( s[i] == ' ' || s[i] == '\t' || s[i] == '`' ) )
    {
        ++i;
    }
    if( i >= s.size() )
    {
        return true;
    }
    const char c = s[i];
    return c == ';' || c == ',' || c == ')' || c == '}' || c == ']' || c == '/' || c == '#' || c == '\r';
}

// In PROSE the same literal ends a sentence, not a statement: "`kDriftedLimit` = 10." must be readable as
// the number 10, so a full stop, a word, or the line end all terminate it. Two things still do not: an
// identifier byte glued to the digits (`10x`, `10th`), and an arithmetic operator, which means the doc wrote
// an EXPRESSION (`= 4 << 20`) whose leading integer is not the value being claimed.
inline bool literalTerminatesInProse( std::string_view s, std::size_t i )
{
    if( i < s.size() && ( darkflags::identByte( (unsigned char)s[i] ) || ( s[i] == '.' && i + 1 < s.size() && std::isdigit( (unsigned char)s[i + 1] ) ) ) )
    {
        return false;
    }
    while( i < s.size() && ( s[i] == ' ' || s[i] == '\t' || s[i] == '`' ) )
    {
        ++i;
    }
    return i >= s.size() || std::strchr( "*+-/<>^&|%=", s[i] ) == nullptr;
}

// A bracketed extent `[ 16 ]` whose '[' sits at `openIndex`. Spaces inside the brackets are tolerated,
// nothing else is. `closeIndex` comes back as the INDEX of the ']' (not a count), so a caller resuming its
// walk continues at closeIndex + 1. Shared by both sides of the verb — the doc's `kFoo[16]` claim and the
// code's `T kFoo[18]` declaration are the same lexical shape, and reading them with one matcher is what
// keeps the two from drifting apart.
inline bool matchBracketExtent( std::string_view s, std::size_t openIndex, std::size_t& closeIndex, std::uint64_t& extent )
{
    VERIFY( openIndex < s.size() && s[ openIndex ] == '[' );

    std::size_t k = openIndex + 1;
    while( k < s.size() && s[k] == ' ' )
    {
        ++k;
    }
    if( !parseIntLiteral( s, k, extent ) )
    {
        return false;
    }
    while( k < s.size() && s[k] == ' ' )
    {
        ++k;
    }
    if( k >= s.size() || s[k] != ']' )
    {
        return false;
    }

    closeIndex = k;
    return true;
}

// ── what the CORPUS says about one name (filled by the single code pass) ─────────────────────────────────

struct NameFact
{
    bool          presentInCode = false;   // occurs as an identifier token in some non-markdown indexed file
    bool          hasConst      = false;
    bool          constAmbig    = false;   // two different declaration-shaped values ⇒ nothing to compare against
    std::uint64_t constValue    = 0;
    std::string   constSite;               // "path:line"
    bool          hasArray      = false;
    bool          arrayAmbig    = false;
    std::uint64_t arrayExtent   = 0;
    std::string   arraySite;
};

// The declaration keywords that make a `NAME = N` on this line a DEFINITION rather than an assignment.
// Whole-word matched; one table serves C/C++/ObjC, TS/JS, Python (via the opens-the-line rule), Go and Rust.
inline constexpr const char* kDeclKeywords[] = { "constexpr", "const", "static", "define", "enum", "let", "var", "val", "final", "readonly" };

inline bool hasWholeWord( std::string_view line, std::string_view word )
{
    for( std::size_t at = line.find( word ); at != std::string_view::npos; at = line.find( word, at + 1 ) )
    {
        const bool leftOk  = at == 0 || !darkflags::identByte( (unsigned char)line[ at - 1 ] );
        const bool rightOk = at + word.size() >= line.size() || !darkflags::identByte( (unsigned char)line[ at + word.size() ] );
        if( leftOk && rightOk )
        {
            return true;
        }
    }
    return false;
}

inline bool declKeywordOnLine( std::string_view line )
{
    for( const char* kw : kDeclKeywords )
    {
        if( hasWholeWord( line, kw ) )
        {
            return true;
        }
    }
    return false;
}

// ── doc-side anchor extraction ───────────────────────────────────────────────────────────────────────────

// The inline-code spans on one line, as [start, end) content ranges. Fenced blocks are handled by the
// caller (a fence line toggles a flag); this is only about single-backtick runs.
inline std::vector<std::pair<std::size_t, std::size_t>> backtickSpans( std::string_view line )
{
    std::vector<std::pair<std::size_t, std::size_t>> spans;
    for( std::size_t i = 0; i < line.size(); )
    {
        if( line[i] != '`' ) { ++i; continue; }
        const std::size_t open = i + 1;
        std::size_t       close = open;
        while( close < line.size() && line[close] != '`' )
        {
            ++close;
        }
        if( close >= line.size() )
        {
            break; // an unterminated run — not inline code
        }
        spans.emplace_back( open, close );
        i = close + 1;
    }
    return spans;
}

// What a backtick span names, or an empty `name` when it names nothing: `foo()` → foo, `rw::bar` → bar,
// `src/x.h` → {} (a path), `--flag` → {} (a flag). `hadParens` records the explicit call spelling, which is
// strong enough evidence on its own to skip the code-shape bar.
struct SpanName
{
    std::string_view name;
    std::string_view scope;
    bool             hadParens = false;
};

inline SpanName spanIdentifier( std::string_view span )
{
    SpanName         out;
    std::string_view s = darkflags::trimView( span );
    if( s.size() >= 2 && s.substr( s.size() - 2 ) == "()" ) { out.hadParens = true; s.remove_suffix( 2 ); }
    if( s.find( '/' ) != std::string_view::npos )
    {
        return out; // a path, whatever else it looks like
    }

    std::string_view leaf, scope;
    splitQualified( s, leaf, scope );
    if( !identOk( leaf, 2 ) )
    {
        return out;
    }
    out.name  = leaf;
    out.scope = identOk( scope, 1 ) ? scope : std::string_view{};
    return out;
}

// A `path.ext:LINE` anchor starting at `i`. Rejects times (`12:30`), URLs (`https://h:8080`) and bare
// `name:N` — an anchor must carry a file EXTENSION, which is what distinguishes it from prose punctuation.
inline bool matchFileLine( std::string_view line, std::size_t i, std::size_t& end, std::string_view& path, std::uint64_t& lineNo )
{
    const std::size_t start = i;
    while( i < line.size() && ( darkflags::identByte( (unsigned char)line[i] ) || line[i] == '.' || line[i] == '/' || line[i] == '-' || line[i] == '+' ) )
    {
        ++i;
    }
    if( i >= line.size() || line[i] != ':' || i == start )
    {
        return false;
    }

    path = line.substr( start, i - start );
    if( path.size() < 3 )
    {
        return false;
    }

    // The BASENAME must look like a filename: start with a letter or digit, and have a stem of at least two
    // characters. Markdown emphasis routinely splits a real filename mid-token (a backtick inside
    // `…Implementation`_DETAIL.md`), leaving fragments like `_DETAIL.md` and `.cpp.proto` that are neither
    // the file the doc meant nor a file at all; without this they became "missing-file" rows on both repos.
    const std::size_t   slash = path.find_last_of( '/' );
    std::string_view    base  = slash == std::string_view::npos ? path : path.substr( slash + 1 );
    if( base.empty() || !std::isalnum( (unsigned char)base.front() ) )
    {
        return false;
    }
    const std::size_t baseDot = base.find_last_of( '.' );
    if( baseDot == std::string_view::npos || baseDot < 2 )
    {
        return false;
    }

    const std::size_t dot = path.find_last_of( '.' );
    if( dot == 0 || dot == std::string_view::npos || dot + 1 >= path.size() )
    {
        return false; // no extension ⇒ not a file ref
    }
    // The extension must contain a LETTER. Without that rule `127.0.0.1:8765` parses as the file "127.0.0.1"
    // at line 8765 and every host:port in the docs becomes a missing-file row.
    const std::string_view ext = path.substr( dot + 1 );
    if( ext.size() > kMaxExtLen )
    {
        return false;
    }
    bool extHasAlpha = false;
    for( char c : ext )
    {
        if( !std::isalnum( (unsigned char)c ) )
        {
            return false;
        }
        if( std::isalpha( (unsigned char)c ) )
        {
            extHasAlpha = true;
        }
    }
    if( !extHasAlpha )
    {
        return false;
    }

    std::size_t j = i + 1;
    if( !parseIntLiteral( line, j, lineNo ) || lineNo == 0 )
    {
        return false;
    }
    // A doc that writes `engine.cpp:4294967297` is illustrating a hostile input, not claiming a location.
    // Past this bound the text is an example, so it never becomes an anchor (see the LIMITS note in help).
    if( lineNo > kMaxClaimedLine )
    {
        return false;
    }
    end = j;
    return true;
}

// A doc's `NAME[16]` extent claim, starting just past the name. A backtick may sit between the name and the
// bracket (`kFoo`[16]); whitespace may not, because `foo [16]` is prose next to a markdown reference.
inline bool matchArrayClaim( std::string_view line, std::size_t afterName, std::size_t& closeIndex, std::uint64_t& extent )
{
    std::size_t open = afterName;
    while( open < line.size() && line[open] == '`' )
    {
        ++open;
    }
    if( open >= line.size() || line[open] != '[' )
    {
        return false;
    }
    return matchBracketExtent( line, open, closeIndex, extent );
}

// Does a fresh identifier token START at `i` — an identifier byte whose left neighbour is not one? This is
// the token walk both the doc's value lane and the code harvest use to visit each identifier exactly once.
inline bool identStartsAt( std::string_view s, std::size_t i ) noexcept
{
    VERIFY( i < s.size() );
    return darkflags::identByte( (unsigned char)s[i] ) && !( i > 0 && darkflags::identByte( (unsigned char)s[ i - 1 ] ) );
}

// Advance past the padding a `NAME = 10` claim may carry between its parts. Markdown lets the doc write
// `kFoo` = 10, so PROSE counts a backtick as padding; code never does.
inline std::size_t skipClaimGap( std::string_view s, std::size_t i, bool allowsBacktick )
{
    while( i < s.size() && ( s[i] == ' ' || s[i] == '\t' || ( allowsBacktick && s[i] == '`' ) ) )
    {
        ++i;
    }
    return i;
}

// The `=` that introduces a VALUE, as opposed to the `==` of a comparison or the tail of a compound operator
// (`+=`, `<=`, `!=`). Returns the index just past it, or npos when this `=` is not an assignment.
inline std::size_t matchAssignEquals( std::string_view s, std::size_t at )
{
    if( at >= s.size() || s[at] != '=' )
    {
        return std::string_view::npos;
    }
    if( at + 1 < s.size() && s[at + 1] == '=' )
    {
        return std::string_view::npos; // a comparison
    }
    if( at > 0 && std::strchr( "!<>+-*/%&|^~=", s[at - 1] ) != nullptr )
    {
        return std::string_view::npos; // ditto
    }
    return at + 1;
}

// `NAME = 10` has two dialects, and they differ in exactly two ways: whether markdown may pad the gap, and
// what counts as the END of the literal. A doc's sentence ends with a full stop or a word; a statement ends
// with `;`, a closer or a comment. Keeping them as two rows of one table rather than two near-identical
// functions is what stops the seven precision rules from drifting apart between the reading and the
// harvesting side.
struct ValueClaimDialect
{
    bool allowsBacktickGap;
    bool ( *terminates )( std::string_view, std::size_t );
};

inline constexpr ValueClaimDialect kProseClaim = { true,  literalTerminatesInProse };   // what a DOC writes
inline constexpr ValueClaimDialect kCodeClaim  = { false, literalTerminates        };   // what the CODE declares

// What a value-claim match found. `isMatch` false ⇒ the other two fields are meaningless.
struct ValueClaim
{
    bool          isMatch  = false;
    std::size_t   valueEnd = 0;   // index ONE PAST the literal — where a caller walking the line resumes
    std::uint64_t value    = 0;
};

// One `NAME = 10` claim, starting just past the name. `isImplicitDefine` is the `#define NAME 10` shape,
// where there is no `=` at all.
inline ValueClaim matchValueClaim( std::string_view line, std::size_t afterName, const ValueClaimDialect& dialect, bool isImplicitDefine )
{
    std::size_t v = skipClaimGap( line, afterName, dialect.allowsBacktickGap );
    if( !isImplicitDefine )
    {
        v = matchAssignEquals( line, v );
        if( v == std::string_view::npos )
        {
            return {};
        }
        v = skipClaimGap( line, v, dialect.allowsBacktickGap );
    }

    std::uint64_t value = 0;
    if( !parseIntLiteral( line, v, value ) )
    {
        return {};
    }
    if( !dialect.terminates( line, v ) )
    {
        return {};
    }

    return ValueClaim{ true, v, value };
}

// Where an anchor sits in its doc: a 1-based line, and a 0-based INDEX into that line (the emitted `col` is
// that index + 1, which is what makes a finding spot-checkable by hand).
struct DocPos
{
    std::uint32_t line      = 0;
    std::size_t   nameStart = 0;
};

// The three value-anchor sites build the same shape from different spans, so one constructor serves them all.
inline Anchor valueAnchor( AnchorKind kind, DocPos at, std::string ref, std::string_view name, std::uint64_t want )
{
    Anchor a;
    a.kind = kind;
    a.line = at.line;
    a.col  = std::uint32_t( at.nameStart + 1 );
    a.ref  = std::move( ref );
    a.name.assign( name );
    a.want = want;
    return a;
}

// One backticked span on a doc line that names an identifier, resolved once and read by three of the four
// lanes. `spanStart`/`spanEnd` are INDICES into the line (content only, backticks excluded).
struct NamedSpan
{
    std::size_t spanStart = 0;
    std::size_t spanEnd   = 0;
    std::string name;                  // the leaf, after `()` and any `A::`/`A.` qualifier are stripped
    std::string scope;                 // that qualifier (`A`); "" if the span was written bare
    bool        hadParens = false;     // an explicit call spelling — evidence enough to skip the code-shape bar
    bool        isDefined = false;     // the index knows this leaf as a definition
};

// The backticked names on one doc line, in column order. Also the ONE place `resolvingLines` grows: a line
// that names something this repo defines is the corroboration signal the mention lane leans on, and it is
// appended in ascending line order so `isCorroborated` can binary-search it without a sort.
inline std::vector<NamedSpan> collectNamedSpans( std::string_view line, std::uint32_t lineNo,
                                                 std::span<const std::pair<std::size_t, std::size_t>> spans,
                                                 const HashMap<std::string, std::uint32_t>& defined,
                                                 std::vector<std::uint32_t>& resolvingLines )
{
    std::vector<NamedSpan> named;
    named.reserve( spans.size() );
    for( const auto& [ s, e ] : spans )
    {
        const SpanName id = spanIdentifier( line.substr( s, e - s ) );
        if( id.name.empty() )
        {
            continue;
        }

        const bool isDefined = defined.find( std::string( id.name ) ) != defined.end();
        if( isDefined && id.name.size() >= kMinMentionLen && codeShaped( id.name ) && ( resolvingLines.empty() || resolvingLines.back() != lineNo ) )
        {
            resolvingLines.push_back( lineNo );
        }

        named.push_back( NamedSpan{ s, e, std::string( id.name ), std::string( id.scope ), id.hadParens, isDefined } );
    }
    return named;
}

// Everything the lanes read about one doc line, gathered once. Views at the seam: the scan owns nothing and
// outlives no caller (the same posture as ResolveContext further down).
struct DocLineScan
{
    std::string_view           line;
    std::uint32_t              lineNo = 0;
    std::span<const NamedSpan> named;
};

// ── lane 1: file-line refs ───────────────────────────────────────────────────────────────────────────────

// A file-line anchor's expectation: the nearest backticked name on the line that the index defines AND that
// is code-shaped, ignoring any name sitting INSIDE the ref itself. The shape bar matters here — a doc
// writing "the `for` verb at src/mcp.h:1192" would otherwise make the English word `for` (which some grammar
// does tag as a symbol) the expectation. Empty when the line names nothing usable.
inline std::string nearestDefinedName( std::span<const NamedSpan> named, std::size_t refStart, std::size_t refEnd )
{
    std::string best;
    std::size_t bestDist = SIZE_MAX;
    for( const NamedSpan& n : named )
    {
        if( !n.isDefined || ( n.spanStart >= refStart && n.spanStart < refEnd ) )
        {
            continue;
        }
        if( n.name.size() < kMinMentionLen || !codeShaped( n.name ) )
        {
            continue;
        }
        const std::size_t dist = n.spanStart > refStart ? n.spanStart - refStart : refStart - n.spanStart;
        if( dist < bestDist ) { bestDist = dist; best = n.name; }
    }
    return best;
}

inline void scanFileLineLane( const DocLineScan& scan, std::vector<Anchor>& out )
{
    const std::string_view line = scan.line;
    for( std::size_t i = 0; i < line.size(); )
    {
        if( !( darkflags::identByte( (unsigned char)line[i] ) || line[i] == '.' || line[i] == '/' )
            || ( i > 0 && ( darkflags::identByte( (unsigned char)line[ i - 1 ] ) || line[ i - 1 ] == '.'
                            || line[ i - 1 ] == '/' || line[ i - 1 ] == ':' ) ) )
        { ++i; continue; }

        std::size_t      end  = 0;
        std::string_view path;
        std::uint64_t    at   = 0;
        if( !matchFileLine( line, i, end, path, at ) ) { ++i; continue; }

        Anchor a;
        a.kind = AnchorKind::FileLine;
        a.line = scan.lineNo;
        a.col  = std::uint32_t( i + 1 );
        a.ref.assign( line.substr( i, end - i ) );
        a.want = at;
        a.name = nearestDefinedName( scan.named, i, end );
        out.push_back( std::move( a ) );
        i = end;
    }
}

// ── lane 2: backticked symbol mentions ───────────────────────────────────────────────────────────────────

inline void scanMentionLane( const DocLineScan& scan, std::vector<Anchor>& out )
{
    for( const NamedSpan& n : scan.named )
    {
        if( !n.hadParens && !( n.name.size() >= kMinMentionLen && codeShaped( n.name ) ) )
        {
            continue;
        }

        Anchor a;
        a.kind = AnchorKind::Symbol;
        a.line = scan.lineNo;
        a.col  = std::uint32_t( n.spanStart + 1 );
        a.ref.assign( scan.line.substr( n.spanStart, n.spanEnd - n.spanStart ) );
        a.name  = n.name;
        a.scope = n.scope;
        out.push_back( std::move( a ) );
    }
}

// ── lane 3: `NAME = N` constants and `NAME[N]` extents ───────────────────────────────────────────────────

inline void scanValueLane( const DocLineScan& scan, std::vector<Anchor>& out )
{
    const std::string_view line = scan.line;
    for( std::size_t i = 0; i < line.size(); )
    {
        if( !identStartsAt( line, i ) ) { ++i; continue; }

        const std::size_t      nameStart = i;
        const std::string_view name      = darkflags::takeIdent( line, i );
        if( !identOk( name, kMinValueNameLen ) || !codeShaped( name ) )
        {
            continue;
        }

        const DocPos  at         = DocPos{ scan.lineNo, nameStart };
        std::size_t   closeIndex = 0;
        std::uint64_t extent     = 0;
        if( matchArrayClaim( line, i, closeIndex, extent ) )
        {
            out.push_back( valueAnchor( AnchorKind::Array, at, std::string( line.substr( nameStart, closeIndex + 1 - nameStart ) ), name, extent ) );
            i = closeIndex + 1;
            continue;
        }

        const ValueClaim claim = matchValueClaim( line, i, kProseClaim, false );
        if( !claim.isMatch )
        {
            continue;
        }

        // The doc's own spelling, minus the markdown: `kFoo` = 10 quotes only the name, and echoing the
        // stray backtick back into the report just makes the row harder to read.
        std::string ref( line.substr( nameStart, claim.valueEnd - nameStart ) );
        std::erase( ref, '`' );

        out.push_back( valueAnchor( AnchorKind::Const, at, std::move( ref ), name, claim.value ) );
        i = claim.valueEnd;
    }
}

// ── lane 4: the bare `[N]` variant ───────────────────────────────────────────────────────────────────────
// "the `kSymbolTag` table is a `[16]` array". Admitted only when the line names EXACTLY ONE backticked
// identifier (so the extent has one unambiguous subject) and the bracket is not a markdown link or
// reference. At most one per line, and never when lane 3 already claimed an extent on this line.
//
// This lane spells its bracket match out rather than reusing matchBracketExtent, and the difference is the
// point: with NO name in front of it, `[ 16 ]` is one space away from ordinary prose and markdown, so the
// digits must sit flush against both brackets. Lane 3 and the code harvest, which have already matched a
// name, can afford to tolerate `[ 16 ]`. Widening this one to agree with them re-admits exactly the prose
// the kMinBareExtent floor and the link/reference guards below exist to keep out.

// The '[' at `openIndex` opening a bare extent claim: it must not continue an identifier or a backticked
// span, the digits must clear the kMinBareExtent floor, and what follows must not be markdown's link,
// reference or nested-index punctuation. `closeIndex` comes back as the index of the ']'.
inline bool matchBareExtent( std::string_view line, std::size_t openIndex, std::size_t& closeIndex, std::uint64_t& extent )
{
    if( openIndex > 0 && ( darkflags::identByte( (unsigned char)line[openIndex - 1] ) || line[openIndex - 1] == '`' ) )
    {
        return false;
    }

    std::size_t k = openIndex + 1;
    if( !parseIntLiteral( line, k, extent ) || extent < kMinBareExtent )
    {
        return false;
    }
    if( k >= line.size() || line[k] != ']' )
    {
        return false;
    }
    if( k + 1 < line.size() && ( line[k + 1] == '(' || line[k + 1] == ':' || line[k + 1] == '[' ) )
    {
        return false;
    }

    closeIndex = k;
    return true;
}

inline void scanBareExtentLane( const DocLineScan& scan, std::vector<Anchor>& out )
{
    if( scan.named.size() != 1 )
    {
        return;
    }
    for( const Anchor& a : out )
    {
        if( a.kind == AnchorKind::Array && a.line == scan.lineNo )
        {
            return;
        }
    }

    const std::string_view line = scan.line;
    for( std::size_t i = 0; i + 2 < line.size(); ++i )
    {
        std::size_t   closeIndex = 0;
        std::uint64_t extent     = 0;
        if( line[i] != '[' || !matchBareExtent( line, i, closeIndex, extent ) )
        {
            continue;
        }

        out.push_back( valueAnchor( AnchorKind::Array, DocPos{ scan.lineNo, i },
                                    std::string( line.substr( i, closeIndex + 1 - i ) ), scan.named[0].name, extent ) );
        return;
    }
}

// ── the lane table: the four anchor kinds as rows, not as four branches ──────────────────────────────────
// One row per lane, in EMISSION order — the anchors are stable-sorted by (line, col, kind) afterwards, so
// this order is what breaks a tie between two anchors sharing all three. Lane 4 also READS what lane 3
// emitted, so the value lanes must stay adjacent and in this order.
//
// The one policy that genuinely differs between the lanes is FENCE ADMISSION, so it is a column rather than
// an `if` buried in each body. Fenced blocks hold illustrative code and sample tool output — measured on
// this repo, EVERY file:line and symbol anchor a fence produced was an example (`pointing at m.cpp:3`,
// `127.0.0.1:8765`) and none of the true findings lived in one. `= N` / `[N]` anchors stay admitted there,
// because a stale constant inside a copied code sample is exactly the case this verb was asked to catch.

enum class Lane : std::uint8_t { FileLine = 0, Mention, Value, BareExtent, Count };

using LaneScanner = void ( * )( const DocLineScan&, std::vector<Anchor>& );

struct LaneSpec
{
    const char* lane;               // the anchor kind(s) this row recognises, as the header's table names them
    bool        isAdmittedInFence;  // may this lane speak inside a ``` block?
    LaneScanner scan;
};

inline constexpr LaneSpec kLaneTable[] = {
    { "file-line",     false, scanFileLineLane   },
    { "symbol",        false, scanMentionLane    },
    { "const, array",  true,  scanValueLane      },
    { "array (bare)",  true,  scanBareExtentLane },
};

static_assert( sizeof( kLaneTable ) / sizeof( kLaneTable[0] ) == std::size_t( Lane::Count ),
               "kLaneTable drifted from the Lane enum — update both together" );

// One doc line → its anchors. `defined` decides which backticked name can serve as a file-line anchor's
// expectation; `inFence` suppresses the lanes the table marks fence-shy. `resolvingLines` collects the doc
// lines that name something this repo DOES define — the corroboration signal the mention lane leans on.
inline void scanDocLine( std::string_view line, std::uint32_t lineNo, bool inFence,
                         const HashMap<std::string, std::uint32_t>& defined, std::vector<Anchor>& out,
                         std::vector<std::uint32_t>& resolvingLines )
{
    const std::vector<std::pair<std::size_t, std::size_t>> spans = backtickSpans( line );
    const std::vector<NamedSpan>                           named = collectNamedSpans( line, lineNo, spans, defined, resolvingLines );

    const DocLineScan scan{ line, lineNo, named };
    for( const LaneSpec& lane : kLaneTable )
    {
        if( lane.isAdmittedInFence || !inFence )
        {
            lane.scan( scan, out );
        }
    }
}

// ── the dated-record classifier: what the AUTHOR marked, never what the verb guesses ─────────────────────
// Everything below reads the DOC only. It answers "did the author date this claim", not "is this claim still
// true" — the second question is what the four lanes above already answered, and answering it twice is how a
// verb starts inventing verdicts. See the header for the two signals that were measured and rejected.

// A whole-word, case-insensitive find. ASCII only on purpose: every phrase in the tables below is ASCII, and
// a locale-aware fold would make the verdict depend on the environment, which the det-gate forbids.
inline std::size_t findNoCase( std::string_view hay, std::string_view needle ) noexcept
{
    if( needle.empty() || needle.size() > hay.size() )
    {
        return std::string_view::npos;
    }
    for( std::size_t i = 0; i + needle.size() <= hay.size(); ++i )
    {
        std::size_t k = 0;
        while( k < needle.size() && std::tolower( (unsigned char)hay[i + k] ) == (unsigned char)needle[k] )
        {
            ++k;
        }
        if( k == needle.size() )
        {
            return i;
        }
    }
    return std::string_view::npos;
}

// An ISO calendar date — YYYY-MM-DD, year 1900..2099 — at `i`. This is the ONE date spelling the lane reads.
// "July 2026", "07/24" and a bare "2026-07" were all tried and all admit a doc that merely MENTIONS a month:
// a lane that guesses which of those dates the document rather than its subject is the failure this whole
// verb exists to avoid. Month and day are range-checked so a version string (`1999-12-99`) is not a date.
inline bool isoDateAt( std::string_view s, std::size_t i ) noexcept
{
    if( i + 10 > s.size() )
    {
        return false;
    }
    if( i > 0 && ( std::isdigit( (unsigned char)s[i - 1] ) || s[i - 1] == '-' ) )
    {
        return false;
    }
    static constexpr std::size_t kDigitOffset[] = { 0, 1, 2, 3, 5, 6, 8, 9 };   // YYYY-MM-DD, minus its two dashes
    for( std::size_t k : kDigitOffset )
    {
        if( !std::isdigit( (unsigned char)s[i + k] ) )
        {
            return false;
        }
    }
    if( s[i + 4] != '-' || s[i + 7] != '-' )
    {
        return false;
    }
    if( i + 10 < s.size() && std::isdigit( (unsigned char)s[i + 10] ) )
    {
        return false;
    }

    const int year  = ( s[i] - '0' ) * 1000 + ( s[ i + 1 ] - '0' ) * 100 + ( s[ i + 2 ] - '0' ) * 10 + ( s[ i + 3 ] - '0' );
    const int month = ( s[ i + 5 ] - '0' ) * 10 + ( s[ i + 6 ] - '0' );
    const int day   = ( s[ i + 8 ] - '0' ) * 10 + ( s[ i + 9 ] - '0' );
    return year >= 1900 && year <= 2099 && month >= 1 && month <= 12 && day >= 1 && day <= 31;
}

inline std::size_t findIsoDate( std::string_view s, std::size_t from = 0 ) noexcept
{
    for( std::size_t i = from; i + 10 <= s.size(); ++i )
    {
        if( isoDateAt( s, i ) )
        {
            return i;
        }
    }
    return std::string_view::npos;
}

inline bool hasIsoDate( std::string_view s ) noexcept { return findIsoDate( s ) != std::string_view::npos; }

// The phrases with which an author says "true THEN". Closed and short on purpose: each one is unambiguous
// about tense, which is what a looser candidate ("historical", "no longer", "originally") is not — those
// describe the SUBJECT as often as the claim, and one of them admitted as a hedge turns a live map into a
// record. "as of" is handled separately below because it only dates the claim when a TIME follows it.
inline constexpr std::string_view kAsOfPhrase[] = {
    "at the time", "at time of writing", "when this was written", "when written", "then-current", "then current"
};

// …and what may follow "as of" for it to be naming a moment rather than starting a clause ("as of a fresh
// index, the ladder…"). A year is admitted as well as a full date: "as of 2026" dates the claim just as well.
inline bool namesAMoment( std::string_view rest ) noexcept
{
    std::size_t i = 0;
    while( i < rest.size() && ( rest[i] == ' ' || rest[i] == '`' || rest[i] == '*' || rest[i] == '"' ) )
    {
        ++i;
    }
    if( i >= rest.size() )
    {
        return false;
    }
    if( isoDateAt( rest, i ) )
    {
        return true;
    }
    if( i + 4 <= rest.size() && ( rest.compare( i, 2, "19" ) == 0 || rest.compare( i, 2, "20" ) == 0 ) && std::isdigit( (unsigned char)rest[i + 2] ) && std::isdigit( (unsigned char)rest[i + 3] ) )
    {
        return true;
    }
    const std::string_view tail = rest.substr( i );
    for( std::string_view w : { "today", "this writing", "writing", "this note", "that note", "head", "then" } )
    {
        if( tail.size() >= w.size() && findNoCase( tail.substr( 0, w.size() ), w ) == 0 )
        {
            return true;
        }
    }
    return false;
}

inline bool hasAsOfHedge( std::string_view line )
{
    for( std::string_view p : kAsOfPhrase )
    {
        if( findNoCase( line, p ) != std::string_view::npos )
        {
            return true;
        }
    }

    // Every "as of" on the line, not just the first: a row commonly carries the stale value and its live one
    // ("22 at the time of this note; 30 as of 2026-07-24"), and only the second occurrence names the moment.
    constexpr std::string_view kAsOf = "as of";
    for( std::size_t from = 0; from < line.size(); )
    {
        const std::size_t at = findNoCase( line.substr( from ), kAsOf );
        if( at == std::string_view::npos )
        {
            break;
        }
        const std::size_t past = from + at + kAsOf.size();
        if( namesAMoment( line.substr( past ) ) )
        {
            return true;
        }
        from = past;
    }
    return false;
}

// A LOG ROW: the line's first content, past whatever markdown leads it, is an ISO date. `| 2026-07-14 | B7.1 |
// …` in a ledger table and `- 2026-07-14 — landed` in a changelog are both entries stamped with their own day.
inline bool opensWithIsoDate( std::string_view line ) noexcept
{
    std::size_t i = 0;
    while( i < line.size() && ( line[i] == ' ' || line[i] == '\t' || line[i] == '|' || line[i] == '-' || line[i] == '*' || line[i] == '>' || line[i] == '#' || line[i] == '`' ) )
    {
        ++i;
    }
    return isoDateAt( line, i );
}

// A whole-word case-insensitive find, so `date` never matches inside `updated` and the two tables below stay
// the closed vocabularies they are meant to be.
inline std::size_t findWordNoCase( std::string_view hay, std::string_view word ) noexcept
{
    for( std::size_t from = 0; from + word.size() <= hay.size(); )
    {
        const std::size_t rel = findNoCase( hay.substr( from ), word );
        if( rel == std::string_view::npos )
        {
            return std::string_view::npos;
        }
        const std::size_t at = from + rel;
        const bool leftOk  = at == 0 || !darkflags::identByte( (unsigned char)hay[ at - 1 ] );
        const bool rightOk = at + word.size() >= hay.size() || !darkflags::identByte( (unsigned char)hay[ at + word.size() ] );
        if( leftOk && rightOk )
        {
            return at;
        }
        from = at + 1;
    }
    return std::string_view::npos;
}

// Does `word` INTRODUCE the ISO date at `dateAt` — separated from it by nothing but markdown punctuation,
// whitespace and at most the preposition "on"? A mere proximity bound is not enough, and the fixture's
// negative control is the proof: "Written up after the 2026-01-15 migration" has the label `written` eleven
// characters before a date it does not introduce, and reading that as the document's own date would file a
// live note as a record. "Date: 2026-06-29", "**Date:** 2026-06-29" and "Written on 2026-06-23" all pass.
// Everything markdown may put between a label and the date it introduces. A set, not a chain of `||`: the
// bytes are data, and the one place the rule can be read is this string.
inline constexpr std::string_view kLabelGapBytes = " \t:*_`,([=-.";

// Skip the run of gap bytes at `k`, and the optional "on" of "written ON 2026-…" with its own gap run.
inline std::size_t skipLabelGap( std::string_view line, std::size_t k, std::size_t limit ) noexcept
{
    const auto runOfGaps = [ & ]( std::size_t at ) { while( at < limit && kLabelGapBytes.find( line[at] ) != std::string_view::npos ) { ++at; } return at; };

    k = runOfGaps( k );
    if( k + 2 <= limit && findWordNoCase( line.substr( k, 2 ), "on" ) == 0 )
    {
        k = runOfGaps( k + 2 );
    }
    return k;
}

inline bool introducesDate( std::string_view line, std::string_view word, std::size_t dateAt ) noexcept
{
    for( std::size_t from = 0; from < dateAt; )
    {
        const std::size_t rel = findWordNoCase( line.substr( from, dateAt - from ), word );
        if( rel == std::string_view::npos )
        {
            return false;
        }
        if( skipLabelGap( line, from + rel + word.size(), dateAt ) == dateAt )
        {
            return true;
        }
        from = from + rel + 1;
    }
    return false;
}

// The labels that make a date the DOCUMENT'S OWN. Without this bar an ISO date anywhere in the opening prose
// counts, and measured on this repo that admits three LIVE documents — a phase ledger ("the 2026-07-12
// whole-system audit"), a policy log and a design study ("(Lego round, 2026-06-19)") — each on a date the doc
// TALKS ABOUT.
inline constexpr std::string_view kSelfDateLabel[] = {
    "date", "dated", "written", "generated", "captured", "recorded", "reviewed", "audited", "authored", "pre-registered"
};

// The other half of the same rule: words that date the START, or the FRESHNESS, of something still running.
// "opened 2026-07-22" on an execution ledger, "since 2026-06-19", "last updated 2026-07-24" — each claims the
// document is CURRENT as of that day, which is the opposite of a record, and reading one as a record would
// hide exactly the rot this verb promises to find. Found by hand-checking every record the lane produced on
// this repo: one live remediation ledger, titled `(opened 2026-07-22)`, was the single mis-dated row.
inline constexpr std::string_view kInceptionWord[] = {
    "opened", "open", "since", "started", "starting", "updated", "revised", "active", "ongoing", "current"
};

inline bool isInceptionDate( std::string_view line, std::size_t dateAt ) noexcept
{
    return std::any_of( std::begin( kInceptionWord ), std::end( kInceptionWord ),
                        [ & ]( std::string_view w ) { return introducesDate( line, w, dateAt ); } );
}

// Is there an ISO date in `s` that DATES it, rather than dating something still running?
inline bool hasDatingIsoDate( std::string_view s ) noexcept
{
    for( std::size_t at = findIsoDate( s ); at != std::string_view::npos; at = findIsoDate( s, at + 1 ) )
    {
        if( !isInceptionDate( s, at ) )
        {
            return true;
        }
    }
    return false;
}

inline bool hasLabelledSelfDate( std::string_view line )
{
    for( std::size_t at = findIsoDate( line ); at != std::string_view::npos; at = findIsoDate( line, at + 1 ) )
    {
        if( isInceptionDate( line, at ) )
        {
            continue;
        }
        for( std::string_view label : kSelfDateLabel )
        {
            if( introducesDate( line, label, at ) )
            {
                return true;
            }
        }
    }
    return false;
}

// What dates a whole DOC, decided once from its path and its opening lines.
struct DocDating
{
    bool isTitleDated = false;   // an ISO date in the BASENAME or in the H1 — the doc IS the artifact of that day
    bool isStampDated = false;   // a labelled self-date in the front matter
};

// The front matter is the header block: everything before the first `##` section, bounded by kMaxFrontMatter.
// Only the BASENAME is read for the path date, so a directory named for a date (`research/2026-07/`) does not
// silently date every file filed under it — that is a date about the FILING, not about the claim.
inline DocDating docDatingOf( std::string_view rel, std::string_view bytes )
{
    DocDating out;
    const std::size_t slash = rel.find_last_of( '/' );
    out.isTitleDated = hasIsoDate( slash == std::string_view::npos ? rel : rel.substr( slash + 1 ) );

    std::size_t seen = 0;
    darkflags::forEachLine( bytes, [ & ]( std::string_view line, std::uint32_t )
                            {
        if( seen >= kMaxFrontMatter ) { return;
}
        const std::string_view t = darkflags::trimView( line );
        if( t.size() >= 3 && t.compare( 0, 3, "## " ) == 0 ) { seen = kMaxFrontMatter; return; }
        ++seen;
        if( t.size() >= 2 && t.compare( 0, 2, "# " ) == 0 && hasDatingIsoDate( t ) ) { out.isTitleDated = true;
}
        if( hasLabelledSelfDate( t ) ) {                                              out.isStampDated = true;
} } );
    return out;
}

// The record verdict for every anchor a doc line produced. Most SPECIFIC evidence wins, so a hedge on the
// line outranks its section's date, which outranks the document's — the reader is told the tightest fact the
// verb actually has.
inline Record recordOf( std::string_view line, bool isHeadingDated, const DocDating& dating )
{
    if( hasAsOfHedge( line ) || opensWithIsoDate( line ) )
    {
        return Record::Line;
    }
    if( isHeadingDated )
    {
        return Record::Block;
    }
    if( dating.isTitleDated )
    {
        return Record::Title;
    }
    if( dating.isStampDated )
    {
        return Record::Stamp;
    }
    return Record::Live;
}

// ── one document → its anchors ───────────────────────────────────────────────────────────────────────────
// The whole per-doc walk, lifted out of computeDocDrift so that function stays a PIPELINE (docs → corpus →
// resolution) rather than growing a fifth concern every time a lane is added. Three interleaved states live
// here and nowhere else: the fence toggle, the heading's dated-ness, and the doc's own dating. `resolving`
// grows alongside — it is the corroboration signal collectNamedSpans appends to, in ascending line order.
inline std::vector<Anchor> collectDocAnchors( std::string_view rel, std::string_view bytes,
                                              const HashMap<std::string, std::uint32_t>& defined,
                                              std::vector<std::uint32_t>& resolving )
{
    const DocDating dating = docDatingOf( rel, bytes );

    std::vector<Anchor> anchors;
    bool                inFence        = false;
    bool                isHeadingDated = false;
    darkflags::forEachLine( bytes, [ & ]( std::string_view line, std::uint32_t lineNo )
    {
        const std::string_view t = darkflags::trimView( line );
        if( t.size() >= 3 && ( t.compare( 0, 3, "```" ) == 0 || t.compare( 0, 3, "~~~" ) == 0 ) ) { inFence = !inFence; return; }
        if( !inFence && !t.empty() && t.front() == '#' )
        {
            isHeadingDated = hasDatingIsoDate( t );
        }

        // The record classifier runs ONLY over the anchors THIS line produced, so a doc line that anchors
        // nothing — the overwhelming majority — never pays for the lane.
        const std::size_t before = anchors.size();
        scanDocLine( line, lineNo, inFence, defined, anchors, resolving );
        if( anchors.size() == before )
        {
            return;
        }

        const Record rec = recordOf( line, isHeadingDated, dating );
        for( std::size_t i = before; i < anchors.size(); ++i )
        {
            anchors[i].rec = rec;
        }
    } );

    std::stable_sort( anchors.begin(), anchors.end(), anchorLess );
    return anchors;
}

// ── corpus-side harvest: one linear scan of every non-markdown indexed file ──────────────────────────────

// The declaration shape of one CODE line, decided once for the whole line rather than per token.
struct DeclShape
{
    bool isDefineLine = false;   // the `#define NAME 10` directive, where the `=` is implicit
    bool isDeclLine   = false;   // …or any line carrying a declaration keyword
};

inline DeclShape declShapeOf( std::string_view line )
{
    const std::string_view trimmed = darkflags::trimView( line );

    DeclShape shape;
    // `#define NAME 10` is a declaration; NO other `#` line is. An earlier version admitted any leading `#`,
    // which in a shell script means COMMENT — and three "stale constant" rows on this repo all traced to one
    // commented-out `est_tokens=489` in a test script. Narrow it to the directive that actually declares.
    shape.isDefineLine = trimmed.size() > 7 && trimmed.compare( 0, 7, "#define" ) == 0;
    shape.isDeclLine   = declKeywordOnLine( trimmed ) || shape.isDefineLine;
    return shape;
}

// The site a harvested fact cites, as the report prints it. The context owns nothing and outlives no caller.
struct CodeSite
{
    const std::string& rel;
    std::uint32_t      lineNo;
};

// One identifier token in a code line, with the cursor a declaration test reads from.
struct CodeToken
{
    std::string_view line;
    std::size_t      afterName = 0;      // index just past the token — where a `[` or an `=` would sit
    std::string_view tok;
    bool             opensLine = false;  // the FIRST identifier on the line (Python's decl shape has no keyword)
};

// Fold one declaration-shaped number into a name's fact. The `= N` and `[N]` lanes differ only in WHICH of
// the name's two slots they write, so one body serves both — the mirror image of the selection resolveValue
// already makes on the reading side. First writer wins, and a disagreement POISONS the fact rather than
// picking a side: two different declaration-shaped values in the tree mean the doc's number has nothing
// single to disagree with, which is the `ambiguous-value` unchecked row.
inline void foldValueFact( NameFact& f, bool isArray, std::uint64_t value, const CodeSite& site )
{
    bool&          has   = isArray ? f.hasArray    : f.hasConst;
    bool&          ambig = isArray ? f.arrayAmbig  : f.constAmbig;
    std::uint64_t& slot  = isArray ? f.arrayExtent : f.constValue;
    std::string&   where = isArray ? f.arraySite   : f.constSite;

    if( !has )               { has = true; slot = value; where = site.rel + ":" + std::to_string( site.lineNo ); }
    else if( slot != value )
    {
        ambig = true;
    }
}

// Fold ONE identifier token's evidence into the fact of the name the docs asked about. Presence is
// unconditional; the two value lanes only speak for a DECLARATION.
inline void harvestCodeToken( const CodeToken& t, const DeclShape& shape, const CodeSite& site, NameFact& f )
{
    f.presentInCode = true;
    if( !shape.isDeclLine && !t.opensLine )
    {
        return; // an assignment/index, not a declaration
    }

    // NAME[N] — a fixed array extent. This lane demands a real DECLARATION keyword, not merely opening the
    // line: `pointLocation[0] = p;` opens plenty of lines and is an INDEX, and taking it for an extent
    // produced got="0" rows against five different arrays on the GPU repo. An extent of zero is rejected for
    // the same reason — nobody declares `T x[0]`.
    if( shape.isDeclLine && t.afterName < t.line.size() && t.line[ t.afterName ] == '[' )
    {
        std::size_t   closeIndex = 0;
        std::uint64_t extent     = 0;
        if( matchBracketExtent( t.line, t.afterName, closeIndex, extent ) && extent > 0 ) { foldValueFact( f, true, extent, site ); return; }
    }

    // NAME = N  (and the `#define NAME N` shape — there the FIRST identifier on the line is the word
    // `define` itself, so the macro name is the second one and only IT gets the implicit `=`)
    const ValueClaim claim = matchValueClaim( t.line, t.afterName, kCodeClaim, shape.isDefineLine && t.tok != "define" );
    if( claim.isMatch )
    {
        foldValueFact( f, false, claim.value, site );
    }
}

// Fold one CODE line into the facts of the names the docs asked about. Three jobs, one walk: identifier
// presence, declaration-shaped `NAME = N`, and declaration-shaped `NAME[N]`.
// The two maps are deliberately different objects. `wanted` is the read-only set of names the docs asked
// about — shared, never written, safe to consult from any thread. `into` is THIS worker's own accumulator,
// which starts empty and only ever holds names it actually saw, so a threaded corpus scan neither copies the
// full name table per worker nor merges eight thousand untouched rows back (see computeDocDrift's pass B).
inline void harvestCodeLine( std::string_view line, const std::string& rel, std::uint32_t lineNo,
                             const bool ( &wantsFirstByte )[ 256 ],
                             const HashMap<std::string, NameFact>& wanted, HashMap<std::string, NameFact>& into )
{
    const DeclShape shape = declShapeOf( line );
    const CodeSite  site{ rel, lineNo };

    bool isFirstIdent = true;
    for( std::size_t i = 0; i < line.size(); )
    {
        if( !identStartsAt( line, i ) ) { ++i; continue; }

        const std::string_view tok       = darkflags::takeIdent( line, i );
        const bool             opensLine = isFirstIdent;
        isFirstIdent = false;

        if( tok.size() < kMinValueNameLen || tok.size() > kMaxNameLen )
        {
            continue;
        }
        if( !wantsFirstByte[(unsigned char)tok[0]] )
        {
            continue; // cheap reject before the hash
        }
        std::string key( tok );
        if( wanted.find( key ) == wanted.end() )
        {
            continue;
        }

        harvestCodeToken( CodeToken{ line, i, tok, opensLine }, shape, site, into[ std::move( key ) ] );
    }
}

// C-family comment text is not corpus evidence. Reuse layout's string-aware scrubber and leave every
// other language byte-identical; in Python, for example, `//` is an operator rather than a comment.
inline std::string_view codeFactText( std::string_view path, std::string_view bytes, std::string& scratch )
{
    if( !layout::isCFamilyPath( path ) )
    {
        return bytes;
    }
    scratch = layout::withoutComments( bytes );
    return scratch;
}

// ── the on-disk path set (so "missing-file" means MISSING, not merely unindexed) ─────────────────────────
// Two of this verb's early false positives were files that plainly exist — `CMakeLists.txt` (CMake is not an
// indexed grammar) and `third_party/unordered_dense.h` (an excluded directory). Calling those "missing" is
// the exact cry-wolf failure the verb must not have, so the fallback is the filesystem itself: ONE prune-
// aware directory walk, no file reads, reused for both the existence probe and the CMake presence harvest.
struct RepoPaths
{
    std::vector<std::string>                                 rel;      // root-relative, sorted
    std::vector<std::string>                                 auxFull;  // unparsed-but-textual files, absolute, sorted
    HashMap<std::string, rw::svector<std::uint32_t, 2>>     byBase;   // basename → indices into `rel`
};

// The AUXILIARY presence corpus: text files the INDEX does not parse but a doc legitimately names symbols
// from. Two measured false-positive classes came from exactly this gap — CMake build switches
// (`RIPWIRE_TSAN`, `option()`), and, on a GPU repo, every shader function, because `.metal` is not an
// indexed grammar (field notes §4). A name that lives only in one of these is present in the repo, so it
// must not read as a stale doc claim. Extensions only — no content sniffing, no full-tree read.
inline constexpr std::string_view kAuxTextExt[] = {
    ".cmake", ".metal", ".glsl", ".hlsl", ".vert", ".frag", ".comp", ".shader",
    ".yml", ".yaml", ".toml", ".ini", ".cfg", ".plist", ".entitlements", ".gradle", ".proto"
};

inline bool isAuxTextFile( std::string_view base )
{
    if( base == "CMakeLists.txt" )
    {
        return true;
    }
    const std::string ext = lowerExtOf( base );
    for( std::string_view e : kAuxTextExt )
    {
        if( ext == e )
        {
            return true;
        }
    }
    return false;
}

// The probe asks "is this file in the tree", NOT "would we index it" — so the two directories the crawl
// skips for holding SOMEONE ELSE'S source, vendor/ and third_party/, are still walked here. A doc citing a
// vendored header (`sparseCsr.h:291`) names a file that plainly exists; reporting it missing would be a lie.
inline bool isSkippedProbeDir( std::string_view dirName ) noexcept
{
    return isSkippedCrawlDir( dirName ) && dirName != "vendor" && dirName != "third_party";
}

inline RepoPaths collectRepoPaths( const std::string& root, const std::vector<std::string>& excludes )
{
    namespace fs = std::filesystem;
    RepoPaths       out;
    std::error_code ec;
    fs::recursive_directory_iterator it( root, fs::directory_options::skip_permission_denied, ec );
    if( ec ) { DEGRADED_PATH_ALERT( "doc-drift: cannot walk the root — the on-disk existence probe is skipped" ); return out; }

    const fs::recursive_directory_iterator end;
    for( ; it != end; it.increment( ec ) )
    {
        if( ec ) { ec.clear(); continue; }
        const std::string base = it->path().filename().string();
        if( it->is_directory( ec ) )
        {
            std::error_code sec;
            if( isSkippedProbeDir( base ) || std::filesystem::exists( it->path() / "CMakeCache.txt", sec ) )
            {
                it.disable_recursion_pending();
            }
            continue;
        }

        const std::string full = it->path().string();
        bool              skip = false;
        for( const std::string& x : excludes )
        {
            if( !x.empty() && full.find( x ) != std::string::npos ) { skip = true; break; }
        }
        if( skip )
        {
            continue;
        }

        out.rel.emplace_back( relForHash( full, root ) );
        if( isAuxTextFile( base ) )
        {
            out.auxFull.push_back( full );
        }
    }
    std::sort( out.rel.begin(), out.rel.end() );
    std::sort( out.auxFull.begin(), out.auxFull.end() );

    for( std::uint32_t i = 0; i < out.rel.size(); ++i )
    {
        const std::size_t slash = out.rel[i].find_last_of( '/' );
        out.byBase[ slash == std::string::npos ? out.rel[i] : out.rel[i].substr( slash + 1 ) ].push_back( i );
    }
    return out;
}

// Does any file in the tree end with this doc-written path, matched on WHOLE segments (the same suffix rule
// traceMatchFile uses on the index, so the two lanes agree about what "the same file" means)?
inline bool pathExistsOnDisk( const RepoPaths& repo, std::string_view written )
{
    std::vector<std::string> segments;
    for( std::string_view seg : wsdetail::segmentsOf( written, '/' ) )
    {
        segments.emplace_back( seg );
    }
    if( segments.empty() )
    {
        return false;
    }
    const auto hit = repo.byBase.find( segments.back() );
    if( hit == repo.byBase.end() )
    {
        return false;
    }
    for( std::uint32_t idx : hit->second )
    {
        if( mention_detail::pathSuffixMatches( repo.rel[idx], segments ) )
        {
            return true;
        }
    }
    return false;
}

// Walk `bytes` line by line, feeding `perLine( line, lineNo )`, and return the line count. Moved DOWN to
// darkflags.h (beside readWhole/trimField) when flipimpact.h's value lane needed the identical walk —
// imported here exactly like readWhole/identByte/trimView, one splitter for every scanner over file text.
using darkflags::forEachLine;

// ── per-anchor resolution ────────────────────────────────────────────────────────────────────────────────
// Everything a verdict needs, gathered once, so each lane below reads as its own rule instead of another
// branch of one long function. Views at the seam: the context owns nothing and outlives no caller.

struct ResolveContext
{
    const IngestResult&                        ing;
    const std::string&                         root;
    const RepoPaths&                           repo;
    const HashMap<std::string, std::uint32_t>& defined;      // every name the index calls a definition
    const HashMap<std::string, NameFact>&      facts;        // what the corpus says about each doc-named name
    const std::vector<std::uint32_t>&          lineCounts;   // fileId → line COUNT (0 ⇒ empty, or unread — see below)
    const HashMap<std::string, std::uint32_t>& pathMemo;     // path token → fileId, PREFILLED (read-only: the
                                                             //   resolve pass is threaded — see computeDocDrift)
    const std::vector<std::uint32_t>&          resolving;    // THIS doc's lines that name something we define
    const gitoracle::HistoryIndex*             history;      // --with-history only; nullptr ⇒ the lane behaves as before
};

// Is there a name this repo DOES define within kCorroborateWin lines of `at`? `resolving` is built in
// ascending line order by the doc walk, so this is a plain binary search, no sort needed.
inline bool isCorroborated( const ResolveContext& ctx, std::uint32_t at )
{
    const std::uint32_t lo = at > kCorroborateWin ? at - kCorroborateWin : 1;
    const auto          it = std::lower_bound( ctx.resolving.begin(), ctx.resolving.end(), lo );
    return it != ctx.resolving.end() && *it <= at + kCorroborateWin;
}

inline void resolveFileLine( const ResolveContext& ctx, Anchor& a )
{
    // The memo is prefilled with every file-line anchor's path token, so this is a hit in practice; the
    // fallback is a degrade to the direct scan, not a correctness branch, and costs only time.
    const std::string   key( a.ref.substr( 0, a.ref.find( ':' ) ) );
    const auto          memo   = ctx.pathMemo.find( key );
    const std::uint32_t fileId = memo != ctx.pathMemo.end() ? memo->second : traceMatchFile( ctx.ing, key );

    if( fileId == kNoTraceFile )
    {
        // Not indexed is not the same as not there: an excluded directory or an unparsed language still HAS
        // the file, and calling that missing is the cry-wolf failure.
        if( pathExistsOnDisk( ctx.repo, key ) ) { a.skip = Unchecked::NotIndexed; return; }
        a.why = Drift::MissingFile;  a.isChecked = true;
        return;
    }
    // `want` is a 1-based line INDEX, `lineCounts[fileId]` a line COUNT, so the last valid index IS the count
    // and only `>` is past the end. Before forEachLine's bound was fixed the count was one too high on every
    // newline-terminated file, which let an anchor citing exactly lineCount+1 slip through this test and fall
    // into the symbol lane instead of being named for what it is.
    // Known limit, unchanged by that fix: an UNREAD file (oversized past kMaxFlagFileBytes, or unreadable)
    // also carries 0 here, so an anchor into one reports past-eof "0 lines" rather than declining the check.
    if( a.want > ctx.lineCounts[ fileId ] )
    {
        a.why = Drift::PastEof;  a.isChecked = true;
        a.got = std::to_string( ctx.lineCounts[ fileId ] ) + " lines";
        a.tgt.assign( relForHash( ctx.ing.files[ fileId ], ctx.root ) );
        return;
    }
    if( a.name.empty() ) { a.skip = Unchecked::WeakFileLine; return; }

    // The named symbol must be defined IN THE ANCHORED FILE. Docs constantly write "the call at
    // main.cpp:554 to `redactInPlace`" — the symbol names the CALLEE, not what lives at that line, and
    // calling that "line-moved" is a lie the reader then has to go disprove by hand.
    std::uint32_t defLine    = 0;
    bool          hasDefHere = false, holds = false;
    for( const Symbol& s : ctx.ing.symbols )
    {
        if( s.fileId != fileId || s.name != a.name || s.line == 0 )
        {
            continue;
        }
        hasDefHere = true;
        const std::uint32_t end = s.line + ( s.loc > 0 ? s.loc - 1 : 0 );
        // The anchor may point a little ABOVE the definition — at its doc comment, which is where a reader
        // naturally cites a function from. That is not drift.
        const std::uint32_t from = s.line > kAnchorSlack ? s.line - kAnchorSlack : 1;
        if( a.want >= from && a.want <= end )
        {
            holds = true;
        }
        if( defLine == 0 || s.line < defLine )
        {
            defLine = s.line;
        }
    }
    if( !hasDefHere ) { a.skip = Unchecked::NamedElsewhere; return; }

    a.isChecked = true;
    if( holds )
    {
        return;
    }

    const NodeId enc = traceEnclosingSymbol( ctx.ing, fileId, std::uint32_t( a.want ) );
    a.why = Drift::LineMoved;
    a.got = enc == kNoNode ? std::string( "(file scope)" ) : ctx.ing.symbols[ enc ].name;
    a.tgt = std::string( relForHash( ctx.ing.files[ fileId ], ctx.root ) ) + ":" + std::to_string( defLine );
}

inline void resolveMention( const ResolveContext& ctx, Anchor& a )
{
    if( ctx.defined.find( a.name ) != ctx.defined.end() ) { a.isChecked = true; return; }
    if( !a.scope.empty() && ctx.defined.find( a.scope ) == ctx.defined.end() ) { a.skip = Unchecked::ForeignScope; return; }
    const auto f = ctx.facts.find( a.name );
    if( f != ctx.facts.end() && f->second.presentInCode ) { a.skip = Unchecked::NotADefinition; return; }
    if( !isCorroborated( ctx, a.line ) ) { a.skip = Unchecked::Uncorroborated; return; }

    // The history lane. Reached ONLY by a mention that would otherwise be reported as drift, so every
    // existing true negative above is untouched and the oracle can only ever REFINE this one verdict.
    if( ctx.history != nullptr && ctx.history->ok )
    {
        const gitoracle::NameFate fate = ctx.history->fateOf( a.name );
        if( fate.fate == gitoracle::Fate::Never )   { a.skip = Unchecked::NeverInHistory;  return; }
        if( fate.fate == gitoracle::Fate::Unknown ) { a.skip = Unchecked::HistoryNoAnswer; return; }

        a.why       = Drift::Deleted;
        a.isChecked = true;
        a.got       = "removed in " + fate.commit.substr( 0, std::min<std::size_t>( fate.commit.size(), 9 ) )
                    + " (" + fate.date + ")";
        a.tgt       = fate.path;
        return;
    }

    a.why = Drift::Undefined;  a.isChecked = true;
}

// The `= N` and `[N]` lanes differ only in WHICH of the name's two harvested facts they read, so one body
// serves both rather than two near-identical copies.
inline void resolveValue( const ResolveContext& ctx, Anchor& a )
{
    const auto f = ctx.facts.find( a.name );
    if( f == ctx.facts.end() || !f->second.presentInCode ) { a.isProse = true; return; }   // prose, never an anchor

    const bool          isArray = a.kind == AnchorKind::Array;
    const bool          has     = isArray ? f->second.hasArray    : f->second.hasConst;
    const bool          ambig   = isArray ? f->second.arrayAmbig  : f->second.constAmbig;
    const std::uint64_t value   = isArray ? f->second.arrayExtent : f->second.constValue;
    const std::string&  site    = isArray ? f->second.arraySite   : f->second.constSite;

    if( !has )  { a.skip = Unchecked::NoDefSite;      return; }
    if( ambig ) { a.skip = Unchecked::AmbiguousValue; return; }
    a.isChecked = true;
    if( value == a.want )
    {
        return;
    }

    a.why = isArray ? Drift::ArrayExtent : Drift::ConstValue;
    a.got = std::to_string( value );
    a.tgt = site;
}

inline void resolveAnchor( const ResolveContext& ctx, Anchor& a )
{
    switch( a.kind )
    {
        case AnchorKind::FileLine: resolveFileLine( ctx, a ); return;
        case AnchorKind::Symbol:   resolveMention ( ctx, a ); return;
        case AnchorKind::Const:
        case AnchorKind::Array:    resolveValue   ( ctx, a ); return;
    }
}

// ── the verb ─────────────────────────────────────────────────────────────────────────────────────────────

// ── the parallel shape, and what keeps it byte-identical ─────────────────────────────────────────────────
// Measured on a 2815-file / 1041-doc tree: 326 ms scanning the docs, 284 ms scanning the corpus, 54 ms
// resolving — all three per-file or per-doc, all three read-only against the index, and all three serial.
// Determinism is the constraint, not an aspiration: the whole verb's value is that its numbers can be quoted.
// Two disciplines carry it, and every parallel site below uses exactly one of them:
//   * SLOT-DISJOINT — a worker writes only its own index's slot, never a shared container, and the ORDERED
//     accumulation stays serial afterwards. Visit order is then irrelevant, so work may be handed out
//     dynamically. Pass A, the path-memo prefill and the resolve pass are all this shape.
//   * ORDERED FOLD — the corpus scan folds into `facts`, and that fold is FIRST-WINS, so order matters. Its
//     workers therefore take CONTIGUOUS BLOCKS of one combined index space in the serial visit order, each
//     folding into its own copy, and the blocks are merged back in block order (see mergeNameFact's proof).

// Run `work( i )` for every i in [0, count), on up to 16 workers, handing out indices dynamically. `work`
// must write only to slot `i`; anything ordered belongs in the caller's serial pass afterwards. A worker's
// escaping exception would std::terminate the process, so each one degrades to a stderr line instead.
template<class Work>
inline void forEachIndexParallel( std::size_t count, const char* what, Work&& work )
{
    if( count == 0 )
    {
        return;
    }

    std::atomic<std::size_t> nextIndex{ 0 };
    const auto               indexWorker = [ & ]()
    {
        try
        {
            for( std::size_t i = nextIndex.fetch_add( 1, std::memory_order_relaxed ); i < count;
                 i = nextIndex.fetch_add( 1, std::memory_order_relaxed ) )
            {
                work( i );
            }
        }
        catch( ... )
        {
            std::fprintf( stderr, "ripwire: doc-drift %s worker degraded (exception swallowed)\n", what );
        }
    };

    const std::size_t hwThreadCount = std::thread::hardware_concurrency();
    const std::size_t workerCount   = std::min( { hwThreadCount ? hwThreadCount : 1, count, std::size_t( 16 ) } );
    if( workerCount <= 1 ) { indexWorker(); return; }

    // symmetric bare scope: the workers live exactly as long as the pass they serve
    {
        std::vector<std::thread> workers;
        workers.reserve( workerCount );
        for( std::size_t w = 0; w < workerCount; ++w )
        {
            workers.emplace_back( indexWorker );
        }
        for( std::thread& worker : workers )
        {
            worker.join();
        }
    }
}

// Fold a LATER block's facts into the accumulated earlier ones. Exact, not approximate. harvestCodeToken's
// fold is first-wins per lane — the first declaration-shaped value for a name is the one kept, and a later
// DIFFERENT one only raises ambig — so for accumulated A followed by block B:
//   * A has no value  ⇒ the serial run would have taken B's first value, site and ambiguity verbatim;
//   * both have one   ⇒ the serial run raises ambig on any value in B differing from A's, which is exactly
//                       `B.ambig || A.value != B.value`: B.ambig already covers every value inside B that
//                       differs from B's own first, and B's own first covers the comparison against A.
// `ambig` is only ever set while `has` is true, so a value-less lane never carries a stale one.
inline void mergeNameFact( NameFact& acc, const NameFact& later )
{
    acc.presentInCode = acc.presentInCode || later.presentInCode;

    if( !acc.hasConst && later.hasConst )
    { acc.hasConst = true;  acc.constValue = later.constValue;   acc.constSite = later.constSite;  acc.constAmbig = later.constAmbig; }
    else if( acc.hasConst && later.hasConst )
    { acc.constAmbig = acc.constAmbig || later.constAmbig || acc.constValue != later.constValue; }

    if( !acc.hasArray && later.hasArray )
    { acc.hasArray = true;  acc.arrayExtent = later.arrayExtent; acc.arraySite = later.arraySite;  acc.arrayAmbig = later.arrayAmbig; }
    else if( acc.hasArray && later.hasArray )
    { acc.arrayAmbig = acc.arrayAmbig || later.arrayAmbig || acc.arrayExtent != later.arrayExtent; }
}

// ── pass A: every doc's anchors, one slot per doc ────────────────────────────────────────────────────────
// SoA, in file-id order, with the unreadable docs marked rather than removed: the caller's serial fold is
// what turns these slots into ordered rows, so nothing here may depend on which worker ran first.
struct DocScan
{
    std::vector<std::string>                docRel;            // root-relative doc path
    std::vector<std::vector<Anchor>>        perDoc;             // its anchors, unresolved
    std::vector<std::vector<std::uint32_t>> perDocResolving;    // its lines naming something this repo defines
    std::vector<char>                       isDocRead;          // 0 ⇒ the read failed; the caller alerts, in order
};

inline DocScan scanDocAnchors( const IngestResult& ing, const std::string& root, std::string_view filter,
                               const HashMap<std::string, std::uint32_t>& defined )
{
    // The doc set is settled BEFORE any thread starts, so the slot each doc writes is fixed by its file id
    // and not by which worker reached it first.
    DocScan                    out;
    std::vector<std::uint32_t> docFileIds;
    for( std::uint32_t fileId = 0; fileId < ing.files.size(); ++fileId )
    {
        if( !isMarkdownPath( ing.files[fileId] ) )
        {
            continue;
        }
        std::string rel( relForHash( ing.files[ fileId ], root ) );
        if( !filter.empty() && rel.find( filter ) == std::string::npos )
        {
            continue;
        }
        docFileIds.push_back( fileId );
        out.docRel.push_back( std::move( rel ) );
    }

    const std::size_t docCount = docFileIds.size();
    out.perDoc.assign( docCount, {} );
    out.perDocResolving.assign( docCount, {} );
    out.isDocRead.assign( docCount, 0 );

    // SLOT-DISJOINT: doc d writes out.*[d] and nothing else; `defined` is read-only here.
    forEachIndexParallel( docCount, "doc scan", [ & ]( std::size_t d )
    {
        std::string bytes;
        if( !darkflags::readWhole( diskPath( ing, docFileIds[d] ), bytes ) )
        {
            return; // isDocRead stays 0
        }
        out.perDoc[d]    = collectDocAnchors( out.docRel[d], bytes, defined, out.perDocResolving[d] );
        out.isDocRead[d] = 1;
    } );
    return out;
}

// ── pass B: what the CORPUS says about every name the docs asked about ───────────────────────────────────
// Folds into `facts` (which arrives pre-populated with exactly those names, and never grows here) and fills
// `lineCounts` for the indexed files. Returns how many files were actually read.
//
// ORDERED FOLD (see mergeNameFact): the indexed files and then the auxiliary text files form ONE index
// space in the serial visit order; workers take CONTIGUOUS BLOCKS of it, each folding into its own map, and
// the blocks merge back in block order. `lineCounts` is slot-disjoint and needs no merge.
//
// The auxiliary corpus is build files, shaders and config: text the INDEX does not parse but a doc
// legitimately names symbols from. Measured: without CMake, eight false "stale symbol" rows on this repo;
// without `.metal`, a dozen more on the GPU repo, because a shader function a doc names is genuinely in the
// tree even though no grammar parses it.
inline std::size_t scanCorpusFacts( const IngestResult& ing, const std::string& root, const RepoPaths& repo,
                                    HashMap<std::string, NameFact>& facts, std::vector<std::uint32_t>& lineCounts )
{
    bool wantsFirstByte[ 256 ] = {};
    for( const auto& [ name, fact ] : facts ) { (void)fact; wantsFirstByte[ (unsigned char)name[0] ] = true; }

    const std::size_t indexedCount = ing.files.size();
    const std::size_t scanCount    = indexedCount + repo.auxFull.size();
    if( scanCount == 0 )
    {
        return 0;
    }

    const std::size_t hwThreadCount = std::thread::hardware_concurrency();
    const std::size_t blockCount    = std::min( { ( hwThreadCount ? hwThreadCount : 1 ) * 4, scanCount, std::size_t( 64 ) } );
    const std::size_t blockSpan     = ( scanCount + blockCount - 1 ) / blockCount;

    // Each block's map starts EMPTY and grows only with the names that block actually saw: `facts` is
    // consulted for membership (read-only, thread-safe) and never written from a worker.
    std::vector<HashMap<std::string, NameFact>> blockFacts( blockCount );
    std::vector<std::size_t>                    blockCorpusFiles( blockCount, 0 );

    const auto scanOne = [ & ]( std::size_t k, HashMap<std::string, NameFact>& into, std::size_t& corpusFiles )
    {
        // Two different spellings on purpose: the READ goes through the diskPath seam (multi-root maps a
        // labeled identity path onto its real one), the reported rel comes from the IDENTITY path.
        const bool         isIndexed = k < indexedCount;
        const std::string& readPath  = isIndexed ? diskPath( ing, std::uint32_t( k ) ) : repo.auxFull[ k - indexedCount ];
        const std::string& identPath = isIndexed ? ing.files[k]                        : repo.auxFull[ k - indexedCount ];

        std::string bytes;
        if( !darkflags::readWhole( readPath, bytes ) )
        {
            return; // oversized/unreadable: counts stay 0
        }
        ++corpusFiles;

        if( isIndexed && isIndexedDocPath( identPath ) )
        {
            // A doc never vouches for its own mentions — line counts only, so a `README.md:900` anchor can
            // still be bounds-checked without the doc's own prose making every name it names "present".
            lineCounts[k] = forEachLine( bytes, []( std::string_view, std::uint32_t ) {} );
            return;
        }
        const std::string rel( relForHash( identPath, root ) );
        std::string       uncommented;
        const std::string_view corpusBytes = codeFactText( identPath, bytes, uncommented );
        const std::uint32_t lineCount = forEachLine( corpusBytes, [ & ]( std::string_view line, std::uint32_t lineIndex )
                                                     { harvestCodeLine( line, rel, lineIndex, wantsFirstByte, facts, into ); } );
        if( isIndexed )
        {
            lineCounts[k] = lineCount;
        }
    };

    forEachIndexParallel( blockCount, "corpus scan", [ & ]( std::size_t b )
    {
        const std::size_t from = b * blockSpan;
        const std::size_t to   = std::min( from + blockSpan, scanCount );
        for( std::size_t k = from; k < to; ++k )
        {
            scanOne( k, blockFacts[b], blockCorpusFiles[b] );
        }
    } );

    std::size_t corpusFiles = 0;
    for( std::size_t b = 0; b < blockCount; ++b )
    {
        corpusFiles += blockCorpusFiles[b];
        for( const auto& [ name, fact ] : blockFacts[b] )
        {
            const auto it = facts.find( name );
            if( it != facts.end() )
            {
                mergeNameFact( it->second, fact );
            }
        }
    }
    return corpusFiles;
}

// Every file-line anchor's path token resolved to a fileId, up front. traceMatchFile is a longest-suffix scan
// over every indexed file and a doc repeats the same handful of paths dozens of times, so this was a lazy
// memo — but the resolve pass is threaded now, and a map grown from workers is neither safe nor
// deterministic. Prefilling makes it read-only there, which is what lets ResolveContext hold it by const
// reference: the compiler then enforces what a comment would only have asked for.
inline HashMap<std::string, std::uint32_t> buildPathMemo( const IngestResult& ing,
                                                          const std::vector<std::vector<Anchor>>& perDoc )
{
    HashMap<std::string, std::uint32_t> memo;
    std::vector<std::string>            memoKeys;                 // distinct, in doc-then-anchor order
    for( const std::vector<Anchor>& anchors : perDoc )
    {
        for( const Anchor& a : anchors )
        {
            if( a.kind == AnchorKind::FileLine )
            {
                std::string key( a.ref.substr( 0, a.ref.find( ':' ) ) );
                if( memo.try_emplace( key, kNoTraceFile ).second )
                {
                    memoKeys.push_back( std::move( key ) );
                }
            }
        }
    }

    std::vector<std::uint32_t> memoIds( memoKeys.size(), kNoTraceFile );
    forEachIndexParallel( memoKeys.size(), "path memo", [ & ]( std::size_t k )
                          { memoIds[k] = traceMatchFile( ing, memoKeys[k] ); } );
    for( std::size_t k = 0; k < memoKeys.size(); ++k )
    {
        memo[memoKeys[k]] = memoIds[k];
    }
    return memo;
}

// §P11.10 — the report opened with two screens of drift="0" rows before the first actionable doc: rows were
// in path order, and ripwire's own alphabetically-early docs happen to be
// audit ledgers whose every failed anchor is a DATED record, so they carry drift="0" and led anyway, while
// the worst live rot (drift="14") sat far below the fold.
//
// Order by LIVE drift descending, path ascending to break ties. The dated-record rows need no separate
// demotion rule and get none: a fully-dated doc IS drift="0" by construction, so it sinks on the same key
// that lifts the rot. Ordering only — every row still prints, and drift= / dated= / the tallies are
// untouched. writeGateability walks this same vector, so its <fix> list is now worst-first too.
inline void sortDocsByLiveDrift( std::vector<DocRow>& docs )
{
    std::sort( docs.begin(), docs.end(), []( const DocRow& a, const DocRow& b )
    {
        const std::size_t al = a.drifted.size() - a.datedCount, bl = b.drifted.size() - b.datedCount;
        return al != bl ? al > bl : a.path < b.path;
    } );
}

// `history` is the caller's --with-history index, or nullptr when the flag was not given. It is threaded in
// rather than probed here so the ONE git walk is shared with every other consumer in the process (and so
// this function stays a pure function of the tree plus that index, which is what keeps it det-gate clean).
inline DriftResult computeDocDrift( const IngestResult& ing, const std::string& root,
                                    const std::vector<std::string>& excludes, std::string_view filter,
                                    const gitoracle::HistoryIndex* history = nullptr )
{
    DriftResult res;
    res.filter.assign( filter );
    res.history = history;
    res.atStamp = gitstamp::stampAt( root );   // r26-stamp Task A: anchor these counts to the commit they were run against

    // Every name the index calls a DEFINITION (first id wins; the walk is id-ascending, so it is stable).
    HashMap<std::string, std::uint32_t> defined;
    defined.reserve( ing.symbols.size() );
    for( const Symbol& s : ing.symbols )
    {
        if( !s.name.empty() )
        {
            defined.try_emplace( s.name, s.id );
        }
    }

    // ── pass A: the docs' anchors ────────────────────────────────────────────────────────────────────────
    std::vector<DocRow>                     rows;
    std::vector<std::vector<Anchor>>        perDoc;
    std::vector<std::vector<std::uint32_t>> perDocResolving;   // doc lines naming something this repo defines
    HashMap<std::string, NameFact>          facts;

    // The docs to scan, in index order — settled BEFORE any thread starts, so the slot each doc writes is
    // fixed by the file id and not by which worker got there first.
    DocScan scan = scanDocAnchors( ing, root, filter, defined );

    // …and the ORDERED half, serial: `facts` and `rows` grow in doc-index order, and the unread docs are
    // compacted out here rather than in a worker, so the alert fires once, in order, on the main thread.
    std::size_t keptCount = 0;
    for( std::size_t d = 0; d < scan.docRel.size(); ++d )
    {
        if( !scan.isDocRead[d] )
        {
            DEGRADED_PATH_ALERT( "doc-drift: cannot read a markdown file — its anchors are omitted" );
            continue;
        }
        for( const Anchor& a : scan.perDoc[d] )
        {
            if( !a.name.empty() )
            {
                facts.try_emplace( a.name, NameFact {} );
            }
        }

        DocRow row;
        row.path        = std::move( scan.docRel[d] );
        row.anchorCount = std::uint32_t( scan.perDoc[d].size() );
        rows.push_back( std::move( row ) );

        perDoc.push_back( std::move( scan.perDoc[d] ) );
        perDocResolving.push_back( std::move( scan.perDocResolving[d] ) );
        ++keptCount;
    }
    VERIFY( keptCount == rows.size() && keptCount == perDoc.size() );
    res.docsScanned = std::uint32_t( rows.size() );

    // ── pass B: one parallel scan of the corpus, answering every name the docs asked about ───────────────
    // Skipped entirely when the docs raised no anchor at all — an anchor-free tree must not pay for a read
    // of every file just to produce an empty report.
    std::size_t anchorTotal = 0;
    for( const std::vector<Anchor>& v : perDoc )
    {
        anchorTotal += v.size();
    }

    // The on-disk path set (one prune-aware walk, no reads) — the existence fallback plus the CMake list.
    // Hoisted ABOVE the corpus scan (it reads no file contents and depends on nothing the scan produces) so
    // the indexed files and the auxiliary text files form ONE index space the scan can carve into blocks.
    const RepoPaths repo = anchorTotal > 0 ? collectRepoPaths( root, excludes ) : RepoPaths{};

    std::vector<std::uint32_t> lineCounts( ing.files.size(), 0 );
    if( anchorTotal > 0 )
    {
        res.corpusFiles += scanCorpusFacts( ing, root, repo, facts, lineCounts );
    }

    // ── resolution ───────────────────────────────────────────────────────────────────────────────────────
    const HashMap<std::string, std::uint32_t> pathMemo = buildPathMemo( ing, perDoc );

    // SLOT-DISJOINT: `resolveAnchor` is a pure function of the read-only context and the anchor it is handed,
    // and doc d's anchors live only in perDoc[d]. The ordered accumulation stays in the serial loop below.
    forEachIndexParallel( perDoc.size(), "anchor resolve", [ & ]( std::size_t d )
    {
        const ResolveContext ctx{ ing, root, repo, defined, facts, lineCounts, pathMemo, perDocResolving[d], history };
        for( Anchor& a : perDoc[d] )
        {
            resolveAnchor( ctx, a );
        }
    } );

    for( std::size_t d = 0; d < rows.size(); ++d )
    {
        DocRow&              row     = rows[d];
        std::vector<Anchor>& anchors = perDoc[d];
        std::vector<Anchor>  drifted;
        std::uint32_t        prose = 0;

        for( const Anchor& a : anchors )
        {
            // Exactly one of three buckets, so `checked + unchecked == anchors` holds by construction.
            if( a.isProse )
            {
                ++prose;
            }
            else if( a.why != Drift::Holds )
            {
                drifted.push_back( a );
            }
            else if( a.isChecked )
            {
                ++row.checkedCount;
            }
            else
            {
                ++res.uncheckedBy[std::size_t( a.skip )];
            }
        }

        // A prose `= N` was never an anchor, so it leaves the tally rather than inflating "unchecked".
        VERIFY( row.anchorCount >= prose );
        row.anchorCount -= prose;
        res.prose       += prose;

        res.anchors += row.anchorCount;
        res.checked += row.checkedCount + std::uint32_t( drifted.size() );

        if( drifted.empty() ) { ++res.cleanDocs; continue; }

        // Split the failures the author DATED out of the rot, counting both. Nothing leaves `drifted`: a
        // record still prints, it just stops inflating the number a reader is being asked to act on.
        for( const Anchor& a : drifted )
        {
            if( a.rec != Record::Live )
            {
                ++row.datedCount;
                ++res.datedBy[std::size_t( a.rec )];
            }
        }
        VERIFY( row.datedCount <= drifted.size() );
        res.dated  += row.datedCount;
        res.drift  += std::uint32_t( drifted.size() ) - row.datedCount;
        row.drifted = std::move( drifted );
        res.docs.push_back( std::move( row ) );
    }

    sortDocsByLiveDrift( res.docs );        // §P11.10: worst rot first — see that function
    return res;
}

// ── XML emission (G4: minified, xmllint-clean; an XML comment may not contain a double hyphen, so flag
//    names appear here WITHOUT their leading dashes) ───────────────────────────────────────────────────────

using XmlEscaper = std::function<std::string( std::string_view )>;

// One `<TAG r=… n=… note=…/>` row per non-zero count. `UncheckedSpec` and `RecordSpec` are the same
// {tag, note} pair, so the emitter is templated on the row type rather than written twice — the second copy
// is exactly where the tag and the note would eventually stop agreeing. Views at the seam: the two spans
// carry their own extent, so a table and a counter array of different lengths cannot be paired by mistake.
template<class Spec>
inline void writeTally( std::FILE* out, const char* tag, std::span<const Spec> table,
                        std::span<const std::uint32_t> counts, const XmlEscaper& ex )
{
    VERIFY( table.size() == counts.size() );
    for( std::size_t r = 0; r < counts.size(); ++r )
    {
        if( counts[r] )
        {
            std::fprintf( out, "<%s r=\"%s\" n=\"%u\" note=\"%s\"/>", tag, table[r].tag, counts[r], ex( table[r].note ).c_str() );
        }
    }
}

inline void writeAnchor( std::FILE* out, const Anchor& a, const XmlEscaper& ex )
{
    std::fprintf( out, "<a k=\"%s\" l=\"%u\" c=\"%u\" why=\"%s\"", anchorKindTag( a.kind ), a.line, a.col, driftTag( a.why ) );
    if( a.rec != Record::Live )
    {
        std::fprintf( out, " kind=\"dated-record\" rec=\"%s\"", recordTag( a.rec ) );
    }
    std::fprintf( out, " ref=\"%s\"", ex( a.ref ).c_str() );
    if( !a.name.empty() && a.kind == AnchorKind::FileLine )
    {
        std::fprintf( out, " sym=\"%s\"", ex( a.name ).c_str() );
    }
    if( a.kind == AnchorKind::Const || a.kind == AnchorKind::Array )
    {
        std::fprintf( out, " want=\"%llu\"", (unsigned long long)a.want );
    }
    if( !a.got.empty() )
    {
        std::fprintf( out, " got=\"%s\"", ex( a.got ).c_str() );
    }
    if( !a.tgt.empty() )
    {
        std::fprintf( out, " tgt=\"%s\"", ex( a.tgt ).c_str() );
    }
    std::fprintf( out, "/>" );
}

// --doc-drift --gateability: turn "CI stays non-gating forever" into a finishable to-do list. Every doc
// listed still carries at least one LIVE (undated) failing anchor; docDatingOf (above) proves a doc-level
// title/front-matter date reclassifies EVERY anchor with no more specific Line/Block record of its own —
// which is exactly every currently-live row, by construction (a Live anchor has none of those). So the SAME
// single annotation the dated-record lane already reads is the "ONE annotation" projected here.
inline void writeGateability( std::FILE* out, const DriftResult& res, const XmlEscaper& ex )
{
    // The targets: docs with >=1 live row, plus the live total those rows represent.
    std::uint32_t              liveTotal = 0;
    std::vector<const DocRow*> targets;
    for( const DocRow& row : res.docs )
    {
        const std::uint32_t live = std::uint32_t( row.drifted.size() ) - row.datedCount;
        if( live == 0 )
        {
            continue; // already fully dated (or fully clean) — nothing to gate here
        }
        liveTotal += live;
        targets.push_back( &row );
    }

    // res.drift is BUILT as the sum of exactly these per-doc live counts (see computeDocDrift's
    // `res.drift += drifted.size() - row.datedCount`), and every doc with a live row is in `targets`, so the
    // two agree and projected_drift is 0: dating the whole list below removes ALL of drift=, because the list
    // is exhaustive by construction. A disagreement would mean this block and that accumulation came apart.
    //
    // DEGRADE, not VERIFY, deliberately. `VERIFY( liveTotal == res.drift )` compiles to __builtin_assume under
    // NDEBUG, which entitles the optimizer to fold the clamp below to a literal 0 and so DELETE the fallback
    // that makes a broken invariant survivable — the shipped-bug trap Diagnostics.h warns about, and one CI
    // (which configures Release) could never observe. This is an EMITTER, and a bad accounting total is
    // recoverable: clamp it, and say out loud that it was clamped, in the builds that can still hear.
    if( liveTotal != res.drift )
    {
        DEGRADED_PATH_ALERT( "doc-drift gateability: live total disagrees with drift= — projected_drift clamped to a floor of 0" );
    }
    const std::uint32_t projectedDrift = res.drift > liveTotal ? res.drift - liveTotal : 0u;

    std::fprintf( out, "<!-- ripwire doc-drift gateability: every doc below still has >=1 LIVE (undated) "
                       "failing anchor (live=). The ONE fix that reclassifies ALL of a doc's live rows at "
                       "once: an ISO date (YYYY-MM-DD) in its H1 heading or filename, OR a front-matter "
                       "line naming date/dated/written/generated/captured/recorded/reviewed/audited/"
                       "authored (e.g. \"Date: 2026-07-25\") — the SAME dating marks Record::Title/"
                       "Record::Stamp above already recognise; nothing new to learn. projected_drift= is "
                       "drift= minus every live= listed: an UPPER BOUND on what full annotation could "
                       "remove, NOT a mandate to date every doc — a doc that is genuinely a live/current "
                       "reference (not a snapshot-in-time record) would have real rot HIDDEN, not honestly "
                       "classified, by a date it does not deserve. Weigh each row; do not game the number. -->" );
    std::fprintf( out, "<gateability docs=\"%zu\" projected_drift=\"%u\">", targets.size(), projectedDrift );
    for( const DocRow* row : targets )
    {
        std::fprintf( out, "<fix p=\"%s\" live=\"%u\"/>", ex( row->path ).c_str(),
                      std::uint32_t( row->drifted.size() ) - row->datedCount );
    }
    std::fprintf( out, "</gateability>" );
}

// The doc-drift legend, hoisted to a file-scope constant for the reason situ.h states of kTestGateLegend:
// it is a paragraph, not control flow, and inlining ~57 lines of prose into writeDocDriftPage made the
// function read as long when nothing about its LOGIC grew. One string, one place to correct it.
inline constexpr const char* kDocDriftLegend =
    "<!-- ripwire doc drift: the CHECKABLE anchors in this repo's markdown, verified against the live "
    "index, reporting only the ones that no longer hold. Four kinds: file:line refs (missing-file / "
    "past-eof / line-moved, the last only when the doc names a symbol on that line), backticked symbol "
    "mentions (undefined), `= N` constants and `[N]` array extents (value/extent vs the declaration). "
    "Every lane under reports on purpose: a name is stale only when it occurs NOWHERE in the code as an "
    "identifier, and a number is compared only against a declaration shaped literal the corpus binds "
    "uniquely. checked + unchecked == anchors: nothing is dropped silently, and the unchecked rows say "
    "what was not proved. Read why=\"undefined\" precisely: it says the name is defined NOWHERE in this "
    "repo, which is not the same as DELETED — in a plan or design doc naming work not yet built, that is "
    "expected rather than rot. Run with the with_history flag to have git history separate the two: the "
    "lane then reports why=\"deleted\" with the commit that removed the name, and downgrades a name this "
    "repo never had to unchecked r=\"never in history\". A failed anchor the AUTHOR DATED is split out as "
    "kind=\"dated-record\" and counted in dated= rather than drift=: an audit finding, a ledger row or an "
    "as-of-DATE hedge records what was true then, so drift= is the LIVE rot and drift + dated is every "
    "anchor that no longer holds. rec= names the evidence (line / block / title / stamp), and a doc that "
    "never writes its own date anywhere a machine can read reports LIVE — the lane reads dating marks, it "
    "does not guess genre. Attribute vocabulary, one name one meaning: at= appears ONLY on this root "
    "element and is the commit the run was measured against (short sha, plus dirty when the tree had "
    "uncommitted changes); ref= is the anchor as the DOC writes it; got= is what the corpus actually "
    "says; and tgt= is the corpus SITE backing got= (a path, or path:line). On the <a/> rows k= and kind= "
    "are DIFFERENT things and both are kept: k= is the ANCHOR kind (file-line / symbol / const / array), "
    "kind= is the record classification (dated-record). k= cannot be renamed to kind= here for the obvious "
    "reason that kind= is already taken on the same element; note that in the ranked map the same k= "
    "spelling is a PageRank score instead. Docs are ordered by LIVE drift descending (path breaks ties), "
    "so the worst rot leads and a fully dated doc, which is drift zero by construction, sinks on the "
    "same key. Prose claims, Status lines and dates are NOT checked. "
    // §B9.1: this legend enumerates its vocabulary explicitly, which is what made the four counters
    // it did NOT define read as an oversight rather than a convention — and one of them, corpus=,
    // openly disagrees with the map's own files= with no note. Same shape §A10.11 used for the --deps
    // and --owners files= families: name every denominator, and state how they nest.
    //
    // W3FIX: the first version of this paragraph called corpus= a SUPERSET of files= and then, in the
    // same sentence, subtracted the unreadable and the oversize from it — self-contradictory, and false
    // on two measured runs: this walk's own 4 MiB read ceiling is INDEPENDENT of the crawl's
    // --max-file-size, so `--max-file-size=100M` on a tree with one 4.8 MB source file indexes 3 files
    // and scans a corpus of 2. It is its own population, not a relation to files=.
    "FOUR COUNTERS on this element name four DIFFERENT populations, stated here because one of them "
    "openly disagrees with a number the map reports elsewhere. docs= is the DOCUMENTS scanned for "
    "anchors (markdown by extension, after any filter); it is the denominator of the doc rows below. "
    "clean= is how many of those docs came out with NO failed anchor — drift and dated both zero for "
    "that doc — so docs minus clean is exactly the number of <doc> rows below, before any paging window "
    "is applied. A doc whose anchors were all unchecked, or all prose, is clean here: clean means "
    "nothing was found rotten, not that everything was verified. prose= is the anchors dropped as prose, "
    "so it is SUBTRACTED from anchors= rather than added to it, and the verb does not claim to have "
    "checked them; only the VALUE shapes (`= N` and `[N]`) can be dropped this way, and the drop is "
    "itself a corpus lookup — the name was searched for and not found in code — not a pre-check guess. "
    "corpus= is the file population the anchors were checked AGAINST, and it is its OWN population "
    "rather than a relation to the map's files=: the indexed files this walk could re-read, PLUS a fixed "
    "set of config, shader and build-file extensions (CMakeLists.txt, .cmake, .yml/.yaml, .toml, "
    ".metal/.glsl/.hlsl and the like — an extension whitelist, never a content sniff), MINUS every file "
    "this walk could not open or that exceeded its own 4 MiB read ceiling, which is dropped silently and "
    "never counted. So corpus= is USUALLY larger than files= and that is the normal case, but it is not "
    "always: a crawl run whose max file size ceiling was raised above 4 MiB indexes files this walk still "
    "refuses, and a file the index lists but this run cannot open is counted by one and not the other. "
    "Neither number is "
    "wrong. corpus=\"0\" means the corpus scan never ran at all, which happens only when the docs raised "
    "no anchor SHAPE whatsoever — prose ones included — so anchors=\"0\" beside a non-zero prose= still "
    "scanned, and still reports the corpus it scanned. -->";

// §P8: --limit/--offset used to be accepted and IGNORED here — every run emitted the same full <doc> list,
// so a paging loop over --doc-drift never advanced. `pageLimit`/`pageOffset` (0 = un-paginated, the pre-§P8
// shape byte for byte) window the <doc> ROWS, which are already deterministically ordered (§P11.10: live
// drift descending, path ascending — so page 0 is the worst rot, not the alphabetically first doc). Nothing
// was ever silently capped at this level, so the root gains the paging attributes ONLY when paging is
// active — no shown=/capped= appears on a plain run. docs= keeps meaning "documents scanned", a different
// quantity from the row count, which is why the paging half carries its own total=.
//
// Paging lives in its own entry point rather than as two more defaulted parameters, so writeDocDrift()'s
// contract — the one the MCP `doc_drift` verb calls — keeps its exact shape.
inline void writeDocDriftPage( std::FILE* out, const DriftResult& res, std::size_t maxPerDoc, bool gateability,
                               int pageLimit, int pageOffset )
{
    std::vector<char> esc;
    const XmlEscaper  ex = [ & ]( std::string_view s ) { return std::string( escapeXml( s, esc ) ); };

    std::uint32_t unchecked = 0;
    for( std::uint32_t n : res.uncheckedBy )
    {
        unchecked += n;
    }

    const PageWindow docPage = pageWindow( res.docs.size(), pageLimit, pageOffset );

    std::fputs( kDocDriftLegend, out );
    std::fprintf( out, "<doc-drift docs=\"%u\" clean=\"%u\" anchors=\"%u\" checked=\"%u\" unchecked=\"%u\" drift=\"%u\" dated=\"%u\" prose=\"%u\" corpus=\"%zu\"",
                  res.docsScanned, res.cleanDocs, res.anchors, res.checked, unchecked, res.drift, res.dated, res.prose, res.corpusFiles );
    if( !res.filter.empty() )
    {
        std::fprintf( out, " filter=\"%s\"", ex( res.filter ).c_str() );
    }
    // r26-stamp Task A: anchor these counts to the commit (and dirty-tree state) they were computed against —
    // omitted entirely on a non-git root rather than printed as a placeholder (see gitstamp.h's header comment).
    if( !res.atStamp.empty() )
    {
        std::fprintf( out, " at=\"%s\"", res.atStamp.c_str() );
    }
    {
        char pab[ kPageDisclosureCap ];
        std::fprintf( out, "%s", pageDisclosure( pab, sizeof( pab ), docPage.end - docPage.begin, res.docs.size(),
                                                 docPage.end, pageLimit, pageOffset, false ) );
    }
    std::fprintf( out, ">" );

    // What the history probe did, when it was asked for — stated up front so a reader knows whether the
    // mention lane below is the strong (three-way) one or the old two-way one.
    if( res.history != nullptr )
    {
        gitoracle::writeHistoryProbe( out, *res.history, ex );
    }

    for( std::size_t docIndex = docPage.begin; docIndex < docPage.end; ++docIndex )
    {
        const DocRow& row = res.docs[ docIndex ];
        std::fprintf( out, "<doc p=\"%s\" anchors=\"%u\" checked=\"%u\" drift=\"%zu\" dated=\"%u\">",
                      ex( row.path ).c_str(), row.anchorCount, row.checkedCount + std::uint32_t( row.drifted.size() ),
                      row.drifted.size() - row.datedCount, row.datedCount );
        // "Nothing is dropped without a number": shownCount is what the loop will PRINT, so the <more/>
        // remainder is exactly what it will not. The `shown++ >= cap` form got this wrong twice over — it
        // left the counter at cap+1, so <more/> under-reported the drop by one, and at exactly cap+1 rows
        // the element vanished entirely and one row disappeared unmarked.
        const std::size_t shownCount = std::min( row.drifted.size(), maxPerDoc );
        for( std::size_t anchorIndex = 0; anchorIndex < shownCount; ++anchorIndex )
        {
            writeAnchor( out, row.drifted[ anchorIndex ], ex );
        }
        if( row.drifted.size() > shownCount )
        {
            std::fprintf( out, "<more drift=\"%zu\"/>", row.drifted.size() - shownCount );
        }
        std::fprintf( out, "</doc>" );
    }

    // The two tallies print the same shape from two tables, so one emitter serves both — the reader can see
    // WHICH reason or WHICH dating mark carried each count rather than taking the header number on trust.
    // Record::Live needs no exclusion: it is the ABSENCE of evidence, so nothing ever increments its slot
    // and the zero-count skip drops it (asserted in the gate — a `dated r="live"` row would be a bug).
    writeTally<UncheckedSpec>( out, "unchecked", kUncheckedTable, res.uncheckedBy, ex );
    writeTally<RecordSpec>   ( out, "dated",     kRecordTable,    res.datedBy,     ex );

    if( gateability )
    {
        writeGateability( out, res, ex );
    }

    std::fprintf( out, "</doc-drift>" );
}

// The un-paginated form — unchanged contract, for callers that want every drifted doc in one document.
inline void writeDocDrift( std::FILE* out, const DriftResult& res, std::size_t maxPerDoc, bool gateability = false )
{
    writeDocDriftPage( out, res, maxPerDoc, gateability, 0, 0 );
}

}}   // namespace rw::docdrift

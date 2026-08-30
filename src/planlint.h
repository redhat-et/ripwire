#pragma once

// planlint.h — `--plan-lint=FILE`, the house PLAN format's STRUCTURE check.
//
// Evidence (this feature's own planning note, §P3): in a ~16-task multi-agent wave, the orchestrator's
// closer noticed — by eye, at the end — that task T5 had never been launched. Nothing mechanical caught
// it. A missing terminal status line is pure STRUCTURE, not a judgement call, so it is cheap to catch and
// this verb catches it. It never asks whether a card's CLAIMS are true (that is --doc-drift's job, out of
// scope here on purpose) — only whether the card's own bookkeeping is complete.
//
// ── the grammar, and where it actually came from ─────────────────────────────────────────────────────────────────
// FIRST DRAFT of this lint was built by surveying this repo's own ~20 PLAN_*/DESIGN_*.md files, which do
// NOT converge on one dialect (lettered lanes in a table, S<N>/T<N> tracks in a prose board, dated bullets
// under a bare "## Round record" heading — zero of them use "### T<N>" card headings at all, since that
// convention belongs to the field-evidence source repo, not this one). Validated against that source
// repo's own flagship wave plan — the document the whole feature was built to catch a gap on — the first
// draft's grammar was WRONG in a specific, corpus-provable way: it read a card's status as a glyph on the
// card's OWN body, and every real card in that plan ends its body in plain prose ("**Effort M.**") — the
// real house convention writes status into the §Status LEDGER instead. Checked against that document, the
// first draft gated 23/23 rows on a plan that was, in fact, fully closed: pure cry-wolf, exactly the
// failure mode --doc-drift's own header exists to avoid. Corrected here, and re-validated against the SAME
// document down to 0 findings (every card resolves via its ledger entry) — see LANE_REPORT.md for the
// full before/after and the rest of the corpus this correction was checked against.
//
// The corrected grammar, still deliberately narrow and OPT-IN:
//
//   * a task card is EXACTLY an H3 heading ("### ") whose text OPENS with a token shaped "T" + 1-4 digits +
//     0-3 letters ("T5", "T10", "T7b") — a different heading level is not a card, on purpose;
//   * a status ledger is EXACTLY one heading (any level) whose text, after stripping one leading section
//     mark ("§") and surrounding whitespace, reads "Status" case-insensitively — "Round record" and
//     "Status Update" are both deliberately NOT matches, because neither is the evidenced form;
//   * a card's status is satisfied by EITHER a glyph on its own terminal body line (the shape a
//     ledger-less document can still use) OR a line in the §Status ledger naming its id and carrying a
//     glyph — the real, evidenced primary path. The card's own body wins when it has one; the ledger is
//     consulted only when the card itself carries no glyph, so a document that DOES close cards out on the
//     card reads exactly as the first draft did.
//   * a ledger mention folds by DIGITS, not exact spelling: a bare card "T7" is satisfied by a ledger line
//     naming "T7a" or "T7b" — the exact shape the source plan uses when a card's own body names lettered
//     sub-tasks and the ledger then tracks each one separately. One-directional (a card that is ITSELF
//     lettered is not satisfied by some other lettered sibling), so it folds real evidence in without
//     masking a genuine orphan under a differently-shaped document.
//   * a file showing NEITHER an H3 card NOR a ledger heading is not "broken" — most of this repo's own
//     plans are exactly that file, and are reported dialect="0" with nothing further checked, never as a
//     failing lint. This verb is invoked per file by a caller who is opting a SPECIFIC document into the
//     convention, not swept over a directory the way --doc-drift is.
//   * KNOWN RESIDUAL GAP, stated rather than hidden: a document that uses "### T<N>" headings as plain
//     work-item labels with NO status-tracking mechanism at all anywhere — no ledger, no per-card glyph —
//     still reports every card "missing". Observed for real in the field-evidence corpus (a pre-work
//     design note using T<N> as section numbers, no ledger, one unrelated glyph mid-paragraph). Not fixed
//     here: closing it needs a rule for "has this document adopted ANY status convention at all", which
//     risks inventing a grammar the corpus does not actually evidence — left for a deliberate future call
//     rather than guessed at inside this round.
//
// ── the four checks, only once dialect="1" ────────────────────────────────────────────────────────────────────────────────
//   1. Every card's status (see above) resolves to a glyph, or it does not — status="missing", with why=
//      naming the exact shape: "unlaunched" (a ledger exists and never names this id, or any lettered
//      sub-task of it — the mid-wave T5 catch this verb exists for), "unresolved" (the ledger DOES name
//      the id, but no line naming it carries a glyph — recorded, just not to a resolvable state), or
//      "no-glyph" (no ledger exists in this document at all, so the card's own body was the only possible
//      source and it carried none — the shape a ledger-less document falls back to).
//   2. An hourglass (in-progress) terminal line whose blamed commit is more than kStaleCommits commits
//      behind HEAD: `--doc-drift`'s own §Status/date lane is explicitly out of scope there ("NOT CHECKED AT
//      ALL: ... Status lines, dates"), so this is the one place that gap is closed, and only for the one
//      shape that is pure structure (a glyph line's own commit age), never for the PROSE claim beside it.
//      Never claimed when the file sits outside a git repo, or the line predates the repo's history —
//      degrade-only, disclosed via git="0" / the card's own missing `since=`. Blames whichever line the
//      status actually resolved to — the card's own body, or the ledger line named by src="ledger".
//   3. A task id named inside the ledger's own body with no matching card (digit-folded, per above) — "the
//      ledger says T9 happened, there is no T9". The OTHER direction — a card the ledger never mentions —
//      is check 1's "unlaunched" why=, not a second row on the same fact.
//   4. Every literal "owed"/"OWED" mention with no check-mark or cross ANYWHERE later in the SAME document.
//      Single-document only: a mention discharged by a SUCCESSOR plan is invisible here, stated as a limit
//      rather than attempted — cross-document tracking needs a registry of which doc follows which that
//      this repo does not have, and guessing one would be exactly the false confidence this verb exists to
//      avoid. NOTE: this is substring matching with no semantic disambiguation — a design document that
//      merely QUOTES the words "owed"/"OWED" while describing this very convention (as this file's own
//      plan section does) reads identically to a real marker. Stated, not hidden.
//
// ── what this is NOT ─────────────────────────────────────────────────────────────────────────────────────────
// Not a truth-checker (--doc-drift owns citations); not a scan of a directory (one FILE, one report); not
// a judge of whether a "vacuous" ⏳/threshold SHOULD have been ✅ — that needs the measured distribution
// behind the claim, which no static tool has (see the plan's own P3.3 "not doing" note).
//
// ── exit code: a GATE, deliberately unlike --doc-drift's always-0 report ───────────────────────────────
// --doc-drift's findings are citations an author may have DATED on purpose (a record, not rot), so its own
// header states it is a report a human reads, never a gate. Nothing here has that ambiguity: a card with no
// resolvable status, a stale hourglass, a ledger-orphaned id and an undischarged "owed" are each a plain
// omission with no legitimate "I meant to leave it that way" reading, and this verb exists specifically to
// replace the human eyeballing that a wave-closer used to do by hand. So: exit 2 when dialect="1" and any
// row carries gating="1" (a plain grep for `gating="1"` is even cheaper than reading the exit code); exit 0
// when clean OR dialect="0" (nothing to gate on a file that never opted in); exit 1 only when FILE could
// not be opened — a usage error, not a finding.
//
// Reused rather than reinvented: forEachLine/trimView/identByte/readWhole (darkflags.h — the SAME line
// splitter --doc-drift's own anchor scan sits on), gitRepoToplevel (gitmine.h), gitBlameConfigPins +
// the blame --porcelain shape (quality.h — the SAME ambient-config pin the churn-blame lane already pays
// for), gitstamp::stampAt (the at="<sha>" anchor every other repo-reading verb uses), escapeXml /
// appendCdataSafe (serialize.h). The only new git plumbing is gitBlameLineSha / gitCommitsSince below: no
// existing helper answers "how many commits since THIS line", so those two are new, built the same way
// the others already are (popen + gitOneLine + the ambient-config pin) rather than a fresh subprocess
// shape. gitBlameLineSha is a genuine near-duplicate of quality.h's gitBlameRangeHasWindowCommit (same
// invocation shape, same header-sha check) — a shared-invocation extraction was tried and reverted (see
// gitBlameLineSha's own comment): it shrank the clone but only by moving cost onto the untouched sibling
// function's own short-horizon-churn, net-worse for touching an unrelated, already-shipped file. Acked
// instead — see .ripwire_quality_acks, key qd-planlint-blameclone.
//
// Determinism: one pass over the file's own bytes for structure (plus one more pass over the ledger's own
// body per card that needs it), one blame + one rev-list per hourglass card for staleness — all pure
// functions of (file content, repo HEAD), so two runs against an unchanged file and unchanged HEAD are
// byte-identical.

#include "darkflags.h"    // forEachLine / trimView / identByte / readWhole — the shared lexical + file-read primitives
#include "gitmine.h"      // gitRepoToplevel
#include "quality.h"      // quality::gitBlameConfigPins / quality::gitOneLine — the shared git-blame plumbing
#include "gitstamp.h"     // gitstamp::stampAt — the at="<sha>[+dirty]" anchor
#include "serialize.h"    // escapeXml / appendCdataSafe

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <limits.h>       // PATH_MAX
#include <string>
#include <string_view>
#include <vector>

namespace rw { namespace planlint
{

// A ⏳ line more than this many commits behind HEAD (measured from its own git-blame commit) is stale. Not
// configurable in this version — a fixed, disclosed policy keeps the flag's footprint to one arm; see the
// header comment above for why this is a plain policy call rather than something derivable from the corpus.
inline constexpr std::uint32_t kStaleCommits = 20;

enum class Glyph : std::uint8_t { None, Hourglass, Check, Cross };

inline const char* glyphName( Glyph g ) noexcept
{
    switch( g )
    {
        case Glyph::Hourglass: return "hourglass";
        case Glyph::Check:     return "check";
        case Glyph::Cross:     return "cross";
        default:                return "missing";
    }
}

struct CardRow
{
    std::string   id;                    // "T5", "T7b" — as spelled in the heading
    std::uint32_t line          = 0;     // the "### T<N>" heading's own line (1-based)
    Glyph         terminal      = Glyph::None;
    std::uint32_t terminalLine  = 0;     // the line the status was READ FROM — the card's own body, or a
                                          // ledger line when fromLedger; 0 when neither resolved anything
    bool          fromLedger    = false; // terminal was resolved from a §Status ledger mention, not the
                                          // card's own body — the real house dialect's primary path
    bool          ledgerMentioned = false; // the ledger names this id (or a lettered sub-task of it)
                                          // SOMEWHERE, independent of whether a glyph resolved — only
                                          // meaningful when the document has a ledger at all
    bool          staleComputed = false; // true iff a blame+rev-list answer was actually obtained
    std::uint32_t commitsSince  = 0;     // meaningful only when staleComputed
};

// Why a card's status did not resolve — three distinct, purely structural shapes:
//   "unlaunched" — the document HAS a ledger, and it never names this card's id at all (or any of its
//                  lettered sub-tasks) — this is the field-evidence catch: a card the wave never started.
//   "unresolved" — the ledger names the id, but no line naming it carries a status glyph — recorded, but
//                  not to a resolvable state.
//   "no-glyph"   — no ledger exists in this document at all, so the only source of status is the card's
//                  own body, and its own terminal line carries none.
inline const char* missingWhy( const CardRow& c, bool hasLedger ) noexcept
{
    if( !hasLedger )
    {
        return "no-glyph";
    }
    return c.ledgerMentioned ? "unresolved" : "unlaunched";
}

inline bool cardIsStale( const CardRow& c ) noexcept
{
    return c.terminal == Glyph::Hourglass && c.staleComputed && c.commitsSince > kStaleCommits;
}

inline bool cardIsGating( const CardRow& c ) noexcept
{
    return c.terminal == Glyph::None || cardIsStale( c );
}

struct OwedRow
{
    std::uint32_t line       = 0;
    std::string   text;                  // the trimmed source line, CDATA-escaped on write
    bool          discharged = false;    // a check-mark or cross appears on this line or any later one
};

struct LedgerOrphan
{
    std::uint32_t line = 0;    // the ledger line the id was found on
    std::string   id;
};

struct LintResult
{
    bool          ok             = true;  // false only when FILE could not be opened (or exceeds the size cap)
    std::string   file;                   // echoed verbatim, exactly as given on the command line
    std::string   atStamp;                // gitstamp anchor for the FILE's OWN enclosing repo; "" if not one
    bool          gitAvailable   = false; // whether the file's own directory resolved to a git repo at all
    bool          dialectDetected = false; // !cards.empty() || hasLedger — see the header's "opt-in" note
    bool          hasLedger      = false;
    std::uint32_t ledgerLine     = 0;
    std::uint32_t totalLines     = 0;
    std::vector<CardRow>      cards;
    std::vector<OwedRow>      owed;           // populated only when dialectDetected
    std::vector<LedgerOrphan> ledgerOrphans;  // populated only when dialectDetected && hasLedger
};

// ── small lexical helpers, local to this file ──────────────────────────────────────────────────────────

// An ATX heading's level (1-6), or 0 when `line` is not one. `text` is set to the heading's trimmed text
// with a trailing closing "###" sequence (if any) stripped, same as every other markdown-adjacent reader
// in this tree handles it.
inline std::uint32_t parseHeading( std::string_view line, std::string_view& text ) noexcept
{
    std::size_t i = 0;
    while( i < line.size() && line[i] == '#' ) { ++i; }
    if( i == 0 || i > 6 || i >= line.size() || line[i] != ' ' )
    {
        return 0;
    }
    text = darkflags::trimView( line.substr( i + 1 ) );
    std::size_t end = text.size();
    while( end > 0 && text[end - 1] == '#' ) { --end; }
    text = darkflags::trimView( text.substr( 0, end ) );
    return static_cast<std::uint32_t>( i );
}

// A task id opening `s` — "T" + 1-4 digits + 0-3 letters, then a boundary (end of text, or a byte
// identByte does not count as identifier-shaped). Independent of any scan-the-whole-line search: a card id
// must OPEN the heading text ("T5 — Foo" qualifies, "Part T5" must not), while the ledger-orphan scan below
// wants every occurrence anywhere in a line, so both are built on this one primitive rather than two.
inline bool parseCardIdAtStart( std::string_view s, std::string& idOut )
{
    if( s.empty() || s[0] != 'T' )
    {
        return false;
    }
    std::size_t       i          = 1;
    const std::size_t digitsStart = i;
    while( i < s.size() && i - digitsStart < 4 && std::isdigit( static_cast<unsigned char>( s[i] ) ) ) { ++i; }
    if( i == digitsStart )
    {
        return false; // "T" with no digits is not a card id
    }
    const std::size_t suffixStart = i;
    while( i < s.size() && i - suffixStart < 3 && std::isalpha( static_cast<unsigned char>( s[i] ) ) ) { ++i; }
    if( i < s.size() && darkflags::identByte( static_cast<unsigned char>( s[i] ) ) )
    {
        return false; // ran into more identifier bytes ("T5x9") — not a bounded id
    }
    idOut.assign( s.substr( 0, i ) );
    return true;
}

// Every task-id-shaped token in `line`, left-boundary checked (identByte on the PRECEDING byte, so "T5" in
// "xT5" is rejected). Built on parseCardIdAtStart so "what a task id looks like" has exactly one definition.
template<class OnToken>
inline void forEachTaskToken( std::string_view line, OnToken&& onToken )
{
    for( std::size_t i = 0; i < line.size(); )
    {
        const bool leftBoundary = ( i == 0 ) || !darkflags::identByte( static_cast<unsigned char>( line[ i - 1 ] ) );
        std::string id;
        if( leftBoundary && line[ i ] == 'T' && parseCardIdAtStart( line.substr( i ), id ) )
        {
            onToken( std::string_view( id ) );
            i += id.size();
            continue;
        }
        ++i;
    }
}

// The (digits, letter-suffix) split of a task id already known to match parseCardIdAtStart's shape —
// "T7" -> ("7", ""), "T7b" -> ("7", "b"). Local struct, not exposed beyond the one comparison it serves.
struct TaskIdParts { std::string_view digits; std::string_view suffix; };
inline TaskIdParts splitTaskId( std::string_view id ) noexcept
{
    std::size_t i = 1; // id[0] is always 'T'
    while( i < id.size() && std::isdigit( static_cast<unsigned char>( id[ i ] ) ) ) { ++i; }
    return { id.substr( 1, i - 1 ), id.substr( i ) };
}

// Does a ledger mention of `ledgerId` count toward card `cardId`? Exact spelling always counts. The one
// fold this repo's real field-evidence corpus earns: a BARE numeric card ("T7") is also satisfied by a
// LETTERED mention of the same digits ("T7a", "T7b") — the exact shape a real house plan uses when a
// card's own body names lettered sub-tasks and the ledger then tracks each one separately (T7's body
// literally says "T7a SURVEY... T7b implement..." in the corpus this was derived from). One-directional
// on purpose: a card that is ITSELF lettered ("T7a", if one existed) is not satisfied by some other
// lettered sibling ("T7b") — only a suffix-less card folds lettered children in, so this cannot mask a
// genuine orphan under a differently-shaped document.
inline bool ledgerMentionMatchesCard( std::string_view ledgerId, std::string_view cardId ) noexcept
{
    if( ledgerId == cardId )
    {
        return true;
    }
    const TaskIdParts card = splitTaskId( cardId );
    if( !card.suffix.empty() )
    {
        return false;
    }
    return splitTaskId( ledgerId ).digits == card.digits;
}

inline Glyph classifyGlyph( std::string_view content ) noexcept
{
    if( content.find( "⏳" ) != std::string_view::npos ) { return Glyph::Hourglass; }
    if( content.find( "✅" ) != std::string_view::npos ) { return Glyph::Check; }
    if( content.find( "❌" ) != std::string_view::npos ) { return Glyph::Cross; }
    return Glyph::None;
}

// A ledger heading, stripped of one leading section mark ("§") and surrounding whitespace, reading
// "Status" case-insensitively — exactly the one real example this repo's own corpus carries (this
// feature's own planning note's own "## §Status"). Deliberately exact: "Status Update" and "Round
// record" are both real headings elsewhere in this repo's plans and are NOT matches (see the file header).
inline bool isStatusLedgerHeadingText( std::string_view headingText ) noexcept
{
    std::string_view t = headingText;
    if( t.size() >= 2 && static_cast<unsigned char>( t[0] ) == 0xC2 && static_cast<unsigned char>( t[1] ) == 0xA7 )
    {
        t.remove_prefix( 2 ); // U+00A7 SECTION SIGN, UTF-8 0xC2 0xA7
    }
    t = darkflags::trimView( t );
    if( t.size() != 6 )
    {
        return false;
    }
    static constexpr char kStatus[] = "status";
    for( std::size_t k = 0; k < 6; ++k )
    {
        if( std::tolower( static_cast<unsigned char>( t[ k ] ) ) != kStatus[ k ] )
        {
            return false;
        }
    }
    return true;
}

inline bool containsWholeWord( std::string_view line, std::string_view word ) noexcept
{
    std::size_t pos = 0;
    while( ( pos = line.find( word, pos ) ) != std::string_view::npos )
    {
        const bool leftOk  = ( pos == 0 ) || !darkflags::identByte( static_cast<unsigned char>( line[ pos - 1 ] ) );
        const bool rightOk = ( pos + word.size() >= line.size() )
                           || !darkflags::identByte( static_cast<unsigned char>( line[ pos + word.size() ] ) );
        if( leftOk && rightOk )
        {
            return true;
        }
        ++pos;
    }
    return false;
}

// ── the two new git primitives (see the file header's "reused rather than reinvented" note) ───────────

// The 40-hex commit sha that last touched `relPath`'s line `lineNo1` (1-based) at HEAD, or "" on any
// failure (no git, an uncommitted line, path absent at HEAD, an out-of-range line). Same porcelain shape
// quality.h's gitBlameRangeHasWindowCommit already parses (a header line opens with 40 hex chars); that
// helper answers a yes/no window question and this one needs the sha itself, so it is its own small
// function built the same way rather than a variant bolted onto the existing one. (A shared-invocation
// extraction was tried and reverted — see quality-delta ack qd-planlint-blameclone: it shrank this
// clone's token count but only by moving cost onto gitBlameRangeHasWindowCommit's own short-horizon-churn,
// a net-worse trade for touching an unrelated, already-shipped function.)
inline std::string gitBlameLineSha( const std::string& repoRoot, const std::string& relPath, std::uint32_t lineNo1 )
{
    if( repoRoot.empty() || relPath.empty() || lineNo1 == 0 )
    {
        return {};
    }
    const std::string cmd = "git -c core.quotepath=false" + quality::gitBlameConfigPins( repoRoot )
                           + " -C " + shSingleQuote( repoRoot ) + " blame --porcelain -L "
                           + std::to_string( lineNo1 ) + ",+1 HEAD -- " + shSingleQuote( relPath ) + " 2>/dev/null";
    std::FILE* pipe = popen( cmd.c_str(), "r" );
    if( !pipe )
    {
        return {};
    }
    std::string sha;
    char        buf[ 128 ];
    if( std::fgets( buf, sizeof( buf ), pipe ) )
    {
        std::string_view ln( buf );
        while( !ln.empty() && ( ln.back() == '\n' || ln.back() == '\r' ) ) { ln.remove_suffix( 1 ); }
        const bool isHeaderSha = ln.size() >= 40
            && std::all_of( ln.begin(), ln.begin() + 40, []( char c ) { return std::isxdigit( static_cast<unsigned char>( c ) ); } );
        if( isHeaderSha )
        {
            sha.assign( ln.substr( 0, 40 ) );
        }
    }
    pclose( pipe );
    return sha;
}

// Commits strictly after `sha`, up to and including HEAD. Degrade-only: an empty/unresolvable sha answers
// 0, never a guess — the same posture quality.h's blame helpers take on missing evidence, and the caller
// (computePlanLint) never calls this without first confirming the sha resolved, so the 0 here is reachable
// only through a race (the blamed commit vanishing between the two git calls), not the common path.
inline std::uint32_t gitCommitsSince( const std::string& repoRoot, const std::string& sha )
{
    if( repoRoot.empty() || sha.empty() )
    {
        return 0;
    }
    const std::string out = quality::gitOneLine( repoRoot, "rev-list --count " + sha + "..HEAD 2>/dev/null" );
    if( out.empty() )
    {
        return 0;
    }
    char*               end = nullptr;
    const unsigned long n   = std::strtoul( out.c_str(), &end, 10 );
    return ( end != out.c_str() ) ? static_cast<std::uint32_t>( n ) : 0;
}

// Every gating row this result carries — the header's own gating= and the exit-code decision both read
// this ONE count, so the two can never disagree about what "gating" means.
inline std::uint32_t gatingCount( const LintResult& res ) noexcept
{
    std::uint32_t gating = 0;
    for( const CardRow& c : res.cards )
    {
        if( cardIsGating( c ) )
        {
            ++gating;
        }
    }
    gating += static_cast<std::uint32_t>( res.ledgerOrphans.size() );
    for( const OwedRow& o : res.owed )
    {
        if( !o.discharged )
        {
            ++gating;
        }
    }
    return gating;
}

// A card's status as read off the §Status ledger — the real house dialect's primary path (see the file
// header). Scans [ledgerLine+1, ledgerBodyEnd] for lines mentioning `cardId` (digit-folded via
// ledgerMentionMatchesCard, so a bare "T7" also matches a lettered "T7a"/"T7b" mention) and keeps the BEST
// glyph found: a check/cross always outranks an hourglass — a real corpus document was observed leaving a
// stale "⏳ launched" stub in place well after a fuller "✅ …" entry landed elsewhere in the same ledger,
// and picking whichever line is physically last would have read a FINISHED task as still in progress.
// Within one priority tier the LAST (highest line number) mention wins, since a ledger is written forward
// in time. `mentioned` is true the moment ANY line names the id, independent of whether a glyph resolved —
// the caller needs that fact on its own to tell "unlaunched" (never named) from "unresolved" (named, but
// no glyph nearby).
struct LedgerStatus
{
    Glyph         glyph     = Glyph::None;
    std::uint32_t line      = 0;
    bool          mentioned = false;
};
inline LedgerStatus resolveLedgerStatus( const std::vector<std::string_view>& lines, std::uint32_t ledgerLine,
                                         std::uint32_t ledgerBodyEnd, std::string_view cardId )
{
    LedgerStatus  result;
    std::uint32_t bestHourLine = 0;
    Glyph         bestHour     = Glyph::None;
    for( std::uint32_t ln = ledgerLine + 1; ln <= ledgerBodyEnd; ++ln )
    {
        const std::string_view content = lines[ ln - 1 ];
        bool                    mentioned = false;
        forEachTaskToken( content, [ & ]( std::string_view tok )
        {
            if( ledgerMentionMatchesCard( tok, cardId ) ) { mentioned = true; }
        } );
        if( !mentioned )
        {
            continue;
        }
        result.mentioned = true;
        const Glyph g = classifyGlyph( content );
        if( g == Glyph::Check || g == Glyph::Cross )
        {
            result.glyph = g; result.line = ln;
        }
        else if( g == Glyph::Hourglass )
        {
            bestHour = g; bestHourLine = ln;
        }
    }
    if( result.glyph == Glyph::None && bestHour != Glyph::None )
    {
        result.glyph = bestHour; result.line = bestHourLine;
    }
    return result;
}

// ── the compute entry point ────────────────────────────────────────────────────────────────────────────

inline LintResult computePlanLint( const std::string& fileArg )
{
    LintResult res;
    res.file = fileArg;

    std::string bytes;
    if( !darkflags::readWhole( fileArg, bytes ) )
    {
        res.ok = false;
        return res;
    }

    std::vector<std::string_view> lines;
    lines.reserve( 256 );
    res.totalLines = darkflags::forEachLine( bytes, [ & ]( std::string_view line, std::uint32_t ) { lines.push_back( line ); } );

    // The enclosing git repo is resolved from FILE's OWN directory, never from a caller-supplied root: a
    // plan file handed to this verb need not live inside any indexed root at all (the whole point of taking
    // a bare FILE argument, the same posture --from-trace already takes).
    std::string absFile;
    {
        char        resolved[ PATH_MAX ];
        const char* rp = ::realpath( fileArg.c_str(), resolved );
        absFile        = rp ? std::string( resolved ) : std::filesystem::absolute( fileArg ).lexically_normal().string();
    }
    const std::string parentDir = std::filesystem::path( absFile ).parent_path().string();
    const std::string repoRoot  = gitRepoToplevel( parentDir );
    std::string       relPath;
    res.gitAvailable = !repoRoot.empty();
    if( res.gitAvailable && absFile.size() > repoRoot.size() + 1 && absFile.compare( 0, repoRoot.size(), repoRoot ) == 0 )
    {
        relPath = absFile.substr( repoRoot.size() + 1 );
    }
    else
    {
        res.gitAvailable = false; // toplevel resolved but the path did not join cleanly under it — degrade, never guess
    }
    if( res.gitAvailable )
    {
        res.atStamp = gitstamp::stampAt( repoRoot );
    }

    // ── pass 1: every ATX heading ───────────────────────────────────────────────────────────────────────
    struct HeadingRow { std::uint32_t level; std::uint32_t line; std::string text; };
    std::vector<HeadingRow> headings;
    for( std::uint32_t i = 0; i < lines.size(); ++i )
    {
        std::string_view text;
        const std::uint32_t level = parseHeading( lines[ i ], text );
        if( level != 0 )
        {
            headings.push_back( { level, i + 1, std::string( text ) } );
        }
    }

    // ── the status ledger: the FIRST exact match wins ──────────────────────────────────────────────────
    std::size_t ledgerHeadingIndex = SIZE_MAX;
    for( std::size_t hi = 0; hi < headings.size(); ++hi )
    {
        if( isStatusLedgerHeadingText( headings[ hi ].text ) )
        {
            ledgerHeadingIndex = hi;
            res.hasLedger      = true;
            res.ledgerLine     = headings[ hi ].line;
            break;
        }
    }

    // The ledger's own body range — computed once, up front, so both the per-card status lookup below
    // and the ledger-orphan scan further down read the SAME bound rather than two independently-derived
    // (and possibly diverging) ones.
    std::uint32_t ledgerBodyEnd = 0;
    if( res.hasLedger )
    {
        const std::uint32_t ledgerLevel = headings[ ledgerHeadingIndex ].level;
        ledgerBodyEnd = res.totalLines;
        for( std::size_t hj = ledgerHeadingIndex + 1; hj < headings.size(); ++hj )
        {
            if( headings[ hj ].level <= ledgerLevel )
            {
                ledgerBodyEnd = headings[ hj ].line - 1;
                break;
            }
        }
    }

    // ── task cards: exactly H3 headings whose text opens with a task id ────────────────────────────────
    for( std::size_t hi = 0; hi < headings.size(); ++hi )
    {
        const HeadingRow& h = headings[ hi ];
        if( h.level != 3 )
        {
            continue;
        }
        std::string id;
        if( !parseCardIdAtStart( h.text, id ) )
        {
            continue;
        }

        CardRow row;
        row.id   = id;
        row.line = h.line;

        std::uint32_t bodyEndLine = res.totalLines;
        for( std::size_t hj = hi + 1; hj < headings.size(); ++hj )
        {
            if( headings[ hj ].level <= 3 )
            {
                bodyEndLine = headings[ hj ].line - 1;
                break;
            }
        }
        for( std::uint32_t ln = bodyEndLine; ln > h.line; --ln )
        {
            const std::string_view content = darkflags::trimView( lines[ ln - 1 ] );
            if( content.empty() )
            {
                continue;
            }
            row.terminalLine = ln;
            row.terminal     = classifyGlyph( content );
            break;
        }

        // The real house dialect's primary path: status lives in the §Status LEDGER, not on the card
        // (field-evidence corpus survey — see the file header). Only consulted when the card's own body
        // carried no glyph, so an author who DOES close a card out on the card itself is read exactly as
        // before.
        if( row.terminal == Glyph::None && res.hasLedger )
        {
            const LedgerStatus ls = resolveLedgerStatus( lines, res.ledgerLine, ledgerBodyEnd, row.id );
            row.ledgerMentioned = ls.mentioned;
            if( ls.glyph != Glyph::None )
            {
                row.terminal = ls.glyph; row.terminalLine = ls.line; row.fromLedger = true;
            }
        }

        if( row.terminal == Glyph::Hourglass && res.gitAvailable )
        {
            const std::string sha = gitBlameLineSha( repoRoot, relPath, row.terminalLine );
            if( !sha.empty() )
            {
                row.staleComputed = true;
                row.commitsSince  = gitCommitsSince( repoRoot, sha );
            }
        }
        res.cards.push_back( std::move( row ) );
    }

    res.dialectDetected = !res.cards.empty() || res.hasLedger;
    if( !res.dialectDetected )
    {
        return res; // opt-in: a file showing neither signal is not swept for owed/ledger findings either
    }

    // ── "owed"/"OWED": undischarged iff no check-mark or cross appears on this line or any LATER one ────
    std::vector<std::uint32_t> terminalMarks; // ascending lines carrying a check-mark or a cross
    for( std::uint32_t ln = 1; ln <= res.totalLines; ++ln )
    {
        const std::string_view content = lines[ ln - 1 ];
        if( content.find( "✅" ) != std::string_view::npos || content.find( "❌" ) != std::string_view::npos )
        {
            terminalMarks.push_back( ln );
        }
    }
    for( std::uint32_t ln = 1; ln <= res.totalLines; ++ln )
    {
        const std::string_view content = lines[ ln - 1 ];
        if( !containsWholeWord( content, "owed" ) && !containsWholeWord( content, "OWED" ) )
        {
            continue;
        }
        OwedRow row;
        row.line       = ln;
        row.text       = std::string( darkflags::trimView( content ) );
        row.discharged = std::any_of( terminalMarks.begin(), terminalMarks.end(), [ ln ]( std::uint32_t t ) { return t >= ln; } );
        res.owed.push_back( std::move( row ) );
    }

    // ── ledger orphans: a task id inside the ledger's own body with no matching card ───────────────────
    if( res.hasLedger )
    {
        for( std::uint32_t ln = res.ledgerLine + 1; ln <= ledgerBodyEnd; ++ln )
        {
            forEachTaskToken( lines[ ln - 1 ], [ & ]( std::string_view tok )
            {
                const bool known = std::any_of( res.cards.begin(), res.cards.end(),
                                                [ tok ]( const CardRow& c ) { return ledgerMentionMatchesCard( tok, c.id ); } );
                if( !known )
                {
                    res.ledgerOrphans.push_back( { ln, std::string( tok ) } );
                }
            } );
        }
    }

    return res;
}

// ── the legend, hoisted per docdrift.h's own precedent (a paragraph, not control flow) ─────────────────
inline constexpr const char* kPlanLintLegend =
    "<!-- ripwire plan-lint: STRUCTURE only, never semantics (the doc-drift lane already owns citation "
    "truth). A card is exactly an H3 heading opening with a task id (\"T\" + digits + up to three "
    "letters). A ledger is exactly one heading whose text, stripped of a leading section mark, reads "
    "\"Status\" case-insensitively. A card's status is satisfied EITHER by a glyph on the LAST non-blank "
    "line of its own body OR by a ledger line naming its id (folded by digits, so a bare card is also "
    "satisfied by a lettered ledger mention of the same number, e.g. a ledger entry for \"T7a\" answers "
    "for card \"T7\") that itself carries a glyph — the card's own body wins when it has one, the ledger "
    "is read only when it does not. Neither convention is universal even in this house's own plan corpus, "
    "so a file showing neither is reported dialect=\"0\" and nothing further is checked — this lint is "
    "opt-in per file, never a directory sweep, and a plan that never adopted the convention is not a "
    "failing one. Findings, only once dialect=\"1\": a card whose status did not resolve "
    "(status=\"missing\", why=\"unlaunched\" when a ledger exists and never names this id or a lettered "
    "sub-task of it, why=\"unresolved\" when the ledger names it with no glyph nearby, why=\"no-glyph\" "
    "when this document carries no ledger at all); an hourglass line whose blamed commit sits more than "
    "stale_commits= commits behind HEAD (never claimed outside a git repo — disclosed via git=\"0\", or "
    "the card's own missing since=; blames whichever line the status resolved to, named by src=\"ledger\" "
    "when that is the ledger rather than the card); a task id named in the ledger's own body with no "
    "matching card, digit-folded the same way (ledger-orphan); an owed/OWED mention with no check-mark or "
    "cross anywhere LATER in this same document (single-document only — a successor plan that discharges "
    "it is invisible here, a stated limit). Every gating row carries gating=\"1\" and the header's own "
    "gating= sums them. NOT CHECKED AT ALL: whether any card's claims are true, a heading level other "
    "than three for a card, a ledger heading spelled any other way, any discharge outside this one "
    "document, and a document that uses card headings as plain labels with no status mechanism anywhere "
    "(no ledger, no glyph) — every one of its cards reads \"missing\" too, a known, disclosed gap rather "
    "than a guessed-at fix. Exit 2 when dialect=\"1\" and gating is non-zero; exit 0 when clean or "
    "dialect=\"0\"; exit 1 only when FILE could not be read — a usage error, never a finding. -->";

inline void writePlanLint( std::FILE* out, const LintResult& res )
{
    std::vector<char> esc;
    const auto         ex = [ & ]( std::string_view s ) { return std::string( escapeXml( s, esc ) ); };

    std::fputs( kPlanLintLegend, out );

    const std::uint32_t gating = gatingCount( res );

    std::fprintf( out, "<plan-lint file=\"%s\" dialect=\"%d\" cards=\"%zu\" ledger=\"%d\"",
                  ex( res.file ).c_str(), res.dialectDetected ? 1 : 0, res.cards.size(), res.hasLedger ? 1 : 0 );
    if( res.hasLedger )
    {
        std::fprintf( out, " ledger_line=\"%u\"", res.ledgerLine );
    }
    if( !res.atStamp.empty() )
    {
        std::fprintf( out, " at=\"%s\"", res.atStamp.c_str() );
    }
    std::fprintf( out, " git=\"%d\" stale_commits=\"%u\" gating=\"%u\">",
                  res.gitAvailable ? 1 : 0, kStaleCommits, gating );

    for( const CardRow& c : res.cards )
    {
        std::fprintf( out, "<card id=\"%s\" line=\"%u\" status=\"%s\"", ex( c.id ).c_str(), c.line, glyphName( c.terminal ) );
        if( c.terminalLine != 0 )
        {
            std::fprintf( out, " tline=\"%u\"", c.terminalLine );
        }
        if( c.fromLedger )
        {
            std::fprintf( out, " src=\"ledger\"" );
        }
        if( c.terminal == Glyph::None )
        {
            std::fprintf( out, " why=\"%s\"", missingWhy( c, res.hasLedger ) );
        }
        if( c.staleComputed )
        {
            std::fprintf( out, " since=\"%u\"", c.commitsSince );
        }
        if( cardIsStale( c ) )
        {
            std::fprintf( out, " stale=\"1\"" );
        }
        if( cardIsGating( c ) )
        {
            std::fprintf( out, " gating=\"1\"" );
        }
        std::fprintf( out, "/>" );
    }

    for( const LedgerOrphan& lo : res.ledgerOrphans )
    {
        std::fprintf( out, "<ledger-orphan id=\"%s\" line=\"%u\" gating=\"1\"/>", ex( lo.id ).c_str(), lo.line );
    }

    for( const OwedRow& o : res.owed )
    {
        std::fprintf( out, "<owed line=\"%u\"%s>", o.line, o.discharged ? "" : " gating=\"1\"" );
        std::string safe;
        appendCdataSafe( o.text, safe );
        std::fputs( "<![CDATA[", out );
        std::fwrite( safe.data(), 1, safe.size(), out );
        std::fputs( "]]></owed>", out );
    }

    std::fputs( "</plan-lint>", out );
}

}}   // namespace rw::planlint

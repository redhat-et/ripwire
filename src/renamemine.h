#pragma once

// renamemine.h — §9.5 CALIBRATION: judge the naming-* lint rules against the repo's OWN rename history.
//
// ── why this exists ──────────────────────────────────────────────────────────────────────────────────────
// naming-body-mismatch shipped on PLAUSIBILITY and was measured INVERTED: it flagged the best-named symbols
// in the tree (a good abstraction names intent while its body names mechanism, so zero name↔body overlap is
// the signature of successful abstraction). It was withdrawn — see the WITHDRAWN note atop naminglens.h.
// This file is the instrument that would have caught it before it shipped, and it exists so that the next
// naming metric has to clear a MEASUREMENT rather than an argument.
//
// The insight is that ground truth for "is this a worse name?" is free and local. A repo's git history
// contains real renames: `old → new` pairs chosen by developers who knew the domain and who were, at that
// moment, deliberately replacing a name they had decided was worse. If a naming rule is any good, it fires
// more often on the OLD spelling than on the NEW one.
//
// ── THE PROXY IS NOISY, AND THAT IS NOT A DISCLAIMER, IT IS THE HEADLINE ─────────────────────────────────
// Developers rename for many reasons that have nothing to do with name QUALITY: a project rebrand, a module
// move, an API version bump, a type change, a merge resolution, an extract-function that happens to reuse a
// nearby spelling. Measured on ripwire's own history the single largest rename family is a whole-project
// rebrand (ctxpack → ripwire, 1686 supporting lines), which carries no information about naming quality at
// all. So:
//   * the numbers below are a PRECISION PROXY, never precision;
//   * every emitted report states the sample size, and the gate SKIPS rather than passes when the sample is
//     too small to mean anything (a gate that quietly passes on three samples is worse than no gate);
//   * the join below is deliberately strict, and every pair it drops is COUNTED in the header, so the reader
//     can see how much of the raw candidate set survived and why.
//
// ── how a rename is recognised (the miner) ───────────────────────────────────────────────────────────────
// ONE `git log --no-merges -p -U0` walk — the same stream, flags and bounds the name-history oracle walks,
// through the same shared reader (gitoracle::walkGitPatch), so this verb adds a consumer, not a second git
// lane. Within one hunk, a removed line and an added line are a RENAME SITE when they tokenize to the same
// identifier count, the same inter-token text (the "skeleton"), and differ at exactly ONE identifier
// position. That is the shape a rename has and an edit does not: `inline void foo( int x )` → `inline void
// bar( int x )` keeps every byte but the name. Requiring skeleton equality is what keeps ordinary edits out.
//
// Three candidate line-pairing rules were measured on this repo's history; the shipped one is (c):
//   (a) index-wise, only when a hunk has equally many removed and added lines   — misses split hunks
//   (b) every removed × every added line, unbounded                              — O(n²) on a vendored blob
//   (c) (b) with both sides capped at kMaxHunkSide, over-wide hunks DROPPED and COUNTED in the header
//
// ── how a candidate becomes a labelled pair (the join) ───────────────────────────────────────────────────
// A mined candidate is only usable if the lens could actually have seen both spellings, so it must join to a
// real symbol at HEAD:
//   * the NEW name must be an ELIGIBLE indexed symbol (naminglens::eligibleSymbol) — that supplies the kind,
//     language, signature and spans the rules need, so both sides are scored in the symbol's REAL context
//     rather than as bare strings;
//   * the OLD name must NOT be an indexed name anywhere at HEAD — if it still exists it was not renamed away,
//     and the line pair was some other edit;
//   * the mapping must be UNAMBIGUOUS — an old name claiming two new names (or the reverse, or a reciprocal
//     a→b/b→a pair) is a split/rework/revert, not one developer judgement, and all of its rows are dropped;
//   * the OLD spelling must itself be eligible — the live lens can never fire on a name it would skip, so
//     scoring one would credit the rule with a hit it could not have had.
// Both sides are then scored by calling naminglens' OWN predicates (checkNameShape / checkRoleReturnTypes) on
// the real Symbol and on a COPY of it carrying the old name, with the old name substituted into the signature
// bytes as well (the C-family return-type extractor locates the name inside the signature; a rename really
// does change that text). Nothing about a rule is reimplemented here — a rule that changes changes this
// measurement too, which is the entire point of a calibration gate.
//
// ── what this can and cannot judge ───────────────────────────────────────────────────────────────────────
// Six of the eight rules are decidable on ONE symbol and are scored. naming-series and naming-confusable are
// GROUP rules — they fire on a relationship between co-visible names, not on a name — so a pair carries no
// evidence about them and they are reported `scope="group-rule"` with no proxy rather than a silent 0/0.
//
// The report is FACTS: counts per rule and the pairs behind them. The floor a rule must clear lives in
// test/namingcalibrationcheck.sh, because "what is good enough" is a policy and this verb is a measurement.
// Exit 0 always.
//
// Read-only, always: one `git log` and nothing else. Never checks out, never writes a ref, never touches the
// working tree.

#include "model.h"
#include "ingest.h"
#include "naminglens.h"
#include "gitoracle.h"    // walkGitPatch — the shared `git log -p -U0` streaming reader; identByte
#include "docparse.h"     // detail::readWholeFile — the canonical whole-file byte read
#include "jsonesc.h"      // shSingleQuote
#include "quality.h"      // gitRepoHasHistory
#include "serialize.h"    // escapeXml
#include "Diagnostics.h"  // VERIFY / DEGRADED_PATH_ALERT

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{
namespace renamemine
{

// ── bounds (every one of them, in one place) ─────────────────────────────────────────────────────────────

// A 1-char identifier differs from its neighbour by one byte far too often to be evidence of anything.
constexpr std::size_t   kMinIdentLen  = 2;
constexpr std::size_t   kMaxIdentLen  = 96;     // past this it is a minified blob, not an identifier
constexpr std::size_t   kMaxHunkSide  = 24;     // per-side cap on the O(n²) line pairing; over-wide hunks are dropped + counted
constexpr std::size_t   kMaxLineLen   = 2000;   // a line this long is generated/vendored, not a rename site
constexpr std::size_t   kMaxCandidates = 200000;   // vote-map bound; 560 on the deepest history measured
constexpr std::size_t   kMaxIdentsPerLine = 256;   // a line with more tokens than this is not hand-written code

// ── the mined candidate set ──────────────────────────────────────────────────────────────────────────────

struct RenameCandidate
{
    std::string   oldName;
    std::string   newName;
    std::uint32_t support = 0;   // how many distinct hunks showed this substitution — evidence STRENGTH, not proof
};

struct RenameHarvest
{
    std::vector<RenameCandidate> candidates;          // sorted by (oldName, newName) — determinism, not taste
    std::uint32_t                commitsWalked = 0;
    std::uint64_t                hunksScanned  = 0;
    std::uint64_t                hunksTooWide  = 0;   // dropped by kMaxHunkSide — disclosed, never silent
    bool                         ok         = false;
    bool                         truncated  = false;  // a walk bound was hit ⇒ candidates= is a FLOOR
    bool                         nonGitRoot = false;
};

// ── line tokenizing: identifiers, and the text between them ──────────────────────────────────────────────
// gitoracle::forEachIdentifier answers "which names are on this line"; the question here is different —
// "does this line differ from that one at exactly one identifier POSITION" — which needs the positions and
// the separators, so the split is its own routine rather than a caller of that one. It reuses
// gitoracle::identByte so both lanes agree on what a name byte is.

struct SplitLine
{
    std::vector<std::string_view> idents;   // identifier tokens, in order
    std::vector<std::string_view> gaps;     // the text between/around them — always idents.size() + 1 entries
};

inline void splitLine( std::string_view text, SplitLine& out )
{
    out.idents.clear();
    out.gaps.clear();
    std::size_t gapStart = 0;
    for( std::size_t i = 0; i < text.size(); )
    {
        if( !( ( text[i] >= 'a' && text[i] <= 'z' ) || ( text[i] >= 'A' && text[i] <= 'Z' ) || text[i] == '_' ) )
        {
            ++i;
            continue;
        }
        const std::size_t start = i;
        while( i < text.size() && gitoracle::identByte( (unsigned char)text[i] ) )
        {
            ++i;
        }
        out.gaps.push_back( text.substr( gapStart, start - gapStart ) );
        out.idents.push_back( text.substr( start, i - start ) );
        gapStart = i;
        if( out.idents.size() > kMaxIdentsPerLine )
        {
            out.idents.clear();
            out.gaps.clear();
            return;                     // caller sees an empty split and skips the line
        }
    }
    out.gaps.push_back( text.substr( gapStart ) );
}

namespace detail
{

// The vote map key. A single string with a byte that cannot occur in an identifier keeps this to ONE hash
// lookup per candidate instead of a pair-keyed map with a custom hasher.
inline std::string voteKey( std::string_view oldName, std::string_view newName )
{
    std::string key;
    key.reserve( oldName.size() + newName.size() + 1 );
    key.append( oldName );
    key.push_back( '\x01' );
    key.append( newName );
    return key;
}

// Two lines are a rename site iff they split to the same skeleton and the same identifier count and differ at
// exactly one identifier position. Returns false when they are not — the common case, by a wide margin.
inline bool renameSiteOf( const SplitLine& before, const SplitLine& after, std::string_view& oldName, std::string_view& newName )
{
    if( before.idents.empty() || before.idents.size() != after.idents.size() || before.gaps.size() != after.gaps.size() )
    {
        return false;
    }
    for( std::size_t gapIndex = 0; gapIndex < before.gaps.size(); ++gapIndex )
    {
        if( before.gaps[gapIndex] != after.gaps[gapIndex] )
        {
            return false;
        }
    }
    std::size_t differing = 0;
    std::size_t at        = 0;
    for( std::size_t identIndex = 0; identIndex < before.idents.size(); ++identIndex )
    {
        if( before.idents[identIndex] != after.idents[identIndex] )
        {
            ++differing;
            at = identIndex;
        }
    }
    if( differing != 1 )
    {
        return false;
    }
    oldName = before.idents[at];
    newName = after.idents[at];
    return oldName.size() >= kMinIdentLen && oldName.size() <= kMaxIdentLen
        && newName.size() >= kMinIdentLen && newName.size() <= kMaxIdentLen;
}

// One hunk's two sides, folded into the vote map. A substitution votes ONCE per hunk however many lines in
// that hunk show it: a hunk is one edit, and letting a 40-line hunk cast 40 votes would make one mechanical
// sweep outweigh forty considered renames.
struct HunkBuffer
{
    std::vector<std::string> removed;
    std::vector<std::string> added;
    bool                     tooWide = false;

    void clear()
    {
        removed.clear();
        added.clear();
        tooWide = false;
    }
};

inline void foldHunk( HunkBuffer& hunk, HashMap<std::string, std::uint32_t>& votes, RenameHarvest& harvest )
{
    if( hunk.removed.empty() || hunk.added.empty() )
    {
        hunk.clear();
        return;
    }
    ++harvest.hunksScanned;
    if( hunk.tooWide )
    {
        ++harvest.hunksTooWide;
        hunk.clear();
        return;
    }

    std::vector<std::string> seenThisHunk;
    SplitLine                before;
    SplitLine                after;
    for( const std::string& removedLine : hunk.removed )
    {
        splitLine( removedLine, before );
        for( const std::string& addedLine : hunk.added )
        {
            splitLine( addedLine, after );
            std::string_view oldName;
            std::string_view newName;
            if( !renameSiteOf( before, after, oldName, newName ) )
            {
                continue;
            }
            std::string key = voteKey( oldName, newName );
            if( std::find( seenThisHunk.begin(), seenThisHunk.end(), key ) != seenThisHunk.end() )
            {
                continue;
            }
            if( votes.size() >= kMaxCandidates && votes.find( key ) == votes.end() )
            {
                harvest.truncated = true;   // the map is full — candidates= is a FLOOR from here on
                continue;
            }
            ++votes[key];
            seenThisHunk.push_back( std::move( key ) );
        }
    }
    hunk.clear();
}

}   // namespace detail

// ── the miner ────────────────────────────────────────────────────────────────────────────────────────────
// The git flag set is gitoracle::runProbe's, for gitoracle::runProbe's reasons (see that comment) — with one
// difference that matters here: --no-renames is what turns a file rename into a delete+add of every line,
// which is exactly the shape a MOVE has and a name change does not. A moved file therefore contributes hunks
// whose lines pair perfectly and differ nowhere, so it votes for nothing; that is the desired behaviour.
inline RenameHarvest mineRenamePairs( const std::string& root )
{
    RenameHarvest harvest;
    if( !quality::gitRepoHasHistory( root ) )
    {
        harvest.nonGitRoot = true;
        return harvest;
    }

    const std::string cmd = "git -c core.quotepath=false -C " + shSingleQuote( root )
                          + " log --no-merges --no-color --no-ext-diff --no-textconv --no-renames"
                            " --format='%x01%H' -p -U0 2>/dev/null";

    HashMap<std::string, std::uint32_t> votes;
    detail::HunkBuffer                  hunk;

    const auto onLine = [ & ]( std::string_view raw )
    {
        // a commit header, framed by \x01 (which cannot occur in a unified-diff marker column)
        if( !raw.empty() && raw.front() == '\x01' )
        {
            detail::foldHunk( hunk, votes, harvest );
            ++harvest.commitsWalked;
            return;
        }
        // Every file/hunk header ENDS the current hunk. The "---"/"+++" tests must precede the single-'-'
        // and single-'+' tests below, or a file header is read as a removed/added line.
        if( raw.size() >= 3 && ( raw.compare( 0, 3, "---" ) == 0 || raw.compare( 0, 3, "+++" ) == 0 ) )
        {
            detail::foldHunk( hunk, votes, harvest );
            return;
        }
        if( raw.size() >= 2 && raw.compare( 0, 2, "@@" ) == 0 )
        {
            detail::foldHunk( hunk, votes, harvest );
            return;
        }
        if( raw.empty() || ( raw.front() != '-' && raw.front() != '+' ) )
        {
            detail::foldHunk( hunk, votes, harvest );
            return;
        }
        const std::string_view body = raw.substr( 1 );
        if( body.size() > kMaxLineLen )
        {
            return;
        }
        std::vector<std::string>& side = raw.front() == '-' ? hunk.removed : hunk.added;
        if( side.size() >= kMaxHunkSide )
        {
            hunk.tooWide = true;
            return;
        }
        side.emplace_back( body );
    };

    const gitoracle::PatchWalk walk = gitoracle::walkGitPatch( cmd, onLine, [ & ] { return harvest.commitsWalked <= gitoracle::kMaxProbeCommits; } );
    detail::foldHunk( hunk, votes, harvest );

    if( !walk.started )
    {
        DEGRADED_PATH_ALERT( "renamemine: git log failed to start — the calibration corpus is empty, which the report states rather than scoring zero" );
        return harvest;
    }
    if( walk.truncated )
    {
        harvest.truncated = true;
        DEGRADED_PATH_ALERT( "renamemine: the history walk hit its bound — candidates= is a floor, not a total" );
    }
    // The dangerous failure, guarded the way gitoracle guards it: the caller has established that HEAD
    // resolves, so ZERO commit headers means git failed (stderr is swallowed, popen still succeeds). An empty
    // candidate set with ok=true reads as "this repo has no renames", which is a claim, not an observation.
    if( harvest.commitsWalked == 0 )
    {
        DEGRADED_PATH_ALERT( "renamemine: git log produced no commits despite a resolvable HEAD — reporting no answer rather than 'no renames'" );
        return harvest;
    }
    if( walk.status != 0 )
    {
        harvest.truncated = true;
        DEGRADED_PATH_ALERT( "renamemine: git log exited non-zero mid-walk — the partial answer is kept and marked truncated" );
    }

    harvest.candidates.reserve( votes.size() );
    for( const auto& vote : votes )
    {
        const std::size_t sep = vote.first.find( '\x01' );
        VERIFY( sep != std::string::npos );
        harvest.candidates.push_back( { vote.first.substr( 0, sep ), vote.first.substr( sep + 1 ), vote.second } );
    }
    // The hash map's iteration order is not a contract; the emitted order is. Sort before anyone can see it.
    std::sort( harvest.candidates.begin(), harvest.candidates.end(),
               []( const RenameCandidate& a, const RenameCandidate& b )
               {
                   if( a.oldName != b.oldName ) { return a.oldName < b.oldName; }
                   return a.newName < b.newName;
               } );
    harvest.ok = true;
    return harvest;
}

// ── scoring: which naming-* rules fire on which spelling ─────────────────────────────────────────────────

// The eight tallies of naminglens::detail::RuleSink, in ITS order — index i here is tallies[i] there. The
// two group rules are named so the report can say "no proxy" instead of printing a meaningless 0/0.
constexpr std::size_t kRuleCount = 8;
constexpr std::size_t kSeriesRuleIndex     = 2;
constexpr std::size_t kConfusableRuleIndex = 7;

inline bool isGroupRule( std::size_t ruleIndex ) noexcept
{
    return ruleIndex == kSeriesRuleIndex || ruleIndex == kConfusableRuleIndex;
}

struct RuleScore
{
    const char*   rule    = "";
    std::uint32_t oldFires = 0;   // fired on the abandoned spelling — the true-positive-ish side
    std::uint32_t newFires = 0;   // fired on the chosen spelling  — the false-positive-ish side
    bool          scored   = false;   // false ⇒ a group rule: one pair carries no evidence about it
};

struct ScoredPair
{
    std::string   oldName;
    std::string   newName;
    std::uint32_t support   = 0;
    std::uint32_t oldMask   = 0;   // bit i ⇒ rule i fired on the old spelling
    std::uint32_t newMask   = 0;
    std::uint32_t fileId    = 0;
    std::uint32_t line      = 0;
};

struct CalibrationReport
{
    RenameHarvest           harvest;
    std::vector<ScoredPair> pairs;         // sorted by (oldName, newName)
    RuleScore               rules[ kRuleCount ];
    std::uint64_t           droppedNewNotAtHead = 0;   // the new spelling is no eligible symbol at HEAD
    std::uint64_t           droppedOldStillHere = 0;   // the old spelling still exists ⇒ it was not renamed away
    std::uint64_t           droppedAmbiguous    = 0;   // one-to-many / many-to-one / reciprocal
    std::uint64_t           droppedOldIneligible = 0;  // the lens would skip the old spelling ⇒ it could never have fired
};

namespace detail
{

// Substitute every WHOLE-identifier occurrence of `from` with `to`. Used to build the counterfactual
// signature: the C-family return-type extractor finds the name inside the signature text, and a rename
// really does rewrite that text, so scoring the old name against the new name's signature would be scoring
// a signature that never existed.
inline std::string substituteIdentifier( std::string_view text, std::string_view from, std::string_view to )
{
    std::string out;
    out.reserve( text.size() );
    std::size_t at = 0;
    while( at < text.size() )
    {
        const std::size_t hit = text.find( from, at );
        if( hit == std::string_view::npos )
        {
            out.append( text.substr( at ) );
            break;
        }
        const bool leftBoundary  = hit == 0 || !gitoracle::identByte( (unsigned char)text[ hit - 1 ] );
        const bool rightBoundary = hit + from.size() >= text.size() || !gitoracle::identByte( (unsigned char)text[ hit + from.size() ] );
        out.append( text.substr( at, hit - at ) );
        if( leftBoundary && rightBoundary )
        {
            out.append( to );
        }
        else
        {
            out.append( from );
        }
        at = hit + from.size();
    }
    return out;
}

// Which rules fire on THIS symbol as spelled. Calls naminglens' own predicates — never a copy of them.
inline std::uint32_t firedRuleMask( const Symbol& s, std::string_view sig )
{
    naminglens::detail::RuleSink sink;
    sink.maxHitsPerRule = kRuleCount;          // one symbol cannot exceed this; the budget is not the subject here

    std::vector<std::string> toks;
    naminglens::splitIdentifier( s.name, toks );
    naminglens::detail::checkNameShape( s, toks, sink );
    naminglens::detail::checkRoleReturnTypes( s, sig, sink );

    std::uint32_t mask = 0;
    for( std::size_t ruleIndex = 0; ruleIndex < kRuleCount; ++ruleIndex )
    {
        if( sink.tallies[ruleIndex].count > 0 )
        {
            mask |= std::uint32_t( 1 ) << ruleIndex;
        }
    }
    return mask;
}

// Read one file whole, memoized. A signature is a byte range in a file, and an unreadable file must degrade
// to "no signature" — both role-vs-return-type rules then stay silent — rather than to a guess. The read
// itself is docparse's canonical one, not a fourth copy of the fopen/fseek/fread dance.
struct FileBytesCache
{
    std::vector<std::string> bytes;
    std::vector<char>        loaded;

    explicit FileBytesCache( std::size_t fileCount ) : bytes( fileCount ), loaded( fileCount, 0 ) {}

    const std::string& get( const IngestResult& ing, std::uint32_t fileId )
    {
        if( !loaded[fileId] )
        {
            loaded[fileId] = 1;
            if( !docparse::detail::readWholeFile( diskPath( ing, fileId ), bytes[fileId] ) )
            {
                bytes[fileId].clear();
            }
        }
        return bytes[fileId];
    }
};

}   // namespace detail

// The join + the scoring. `ing` is HEAD's index; `harvest` is the mined candidate set.
inline CalibrationReport scoreRenamePairs( const IngestResult& ing, RenameHarvest harvest )
{
    CalibrationReport report;
    for( std::size_t ruleIndex = 0; ruleIndex < kRuleCount; ++ruleIndex )
    {
        report.rules[ruleIndex].rule   = naminglens::detail::RuleSink{}.tallies[ruleIndex].tag;
        report.rules[ruleIndex].scored = !isGroupRule( ruleIndex );
    }

    // Every indexed name at HEAD (any kind), and the eligible symbols indexed by name. The first set answers
    // "did the old spelling survive"; the second answers "is the new spelling something the lens can see".
    std::vector<std::string>   allNames;
    std::vector<const Symbol*> eligible;
    allNames.reserve( ing.symbols.size() );
    for( const Symbol& s : ing.symbols )
    {
        if( !s.name.empty() )
        {
            allNames.push_back( s.name );
        }
        if( naminglens::detail::eligibleSymbol( s ) )
        {
            eligible.push_back( &s );
        }
    }
    std::sort( allNames.begin(), allNames.end() );
    allNames.erase( std::unique( allNames.begin(), allNames.end() ), allNames.end() );
    // ing.symbols is already in deterministic (file, line, name) order, so a STABLE sort by name leaves the
    // first entry for a name at its first definition site — the representative this report cites.
    std::stable_sort( eligible.begin(), eligible.end(), []( const Symbol* a, const Symbol* b ) { return a->name < b->name; } );

    const auto nameIsIndexed = [ & ]( const std::string& name )
    {
        return std::binary_search( allNames.begin(), allNames.end(), name );
    };
    const auto eligibleNamed = [ & ]( const std::string& name ) -> const Symbol*
    {
        const auto it = std::lower_bound( eligible.begin(), eligible.end(), name,
                                          []( const Symbol* s, const std::string& n ) { return s->name < n; } );
        return ( it != eligible.end() && (*it)->name == name ) ? *it : nullptr;
    };

    // Ambiguity, resolved BEFORE anything is scored: a name on either side of more than one surviving
    // candidate is a split, a rework or a revert — several developer decisions wearing one label — so every
    // row it touches goes, rather than one being picked. Reciprocal a→b / b→a pairs fall out of the same test.
    std::vector<char> keep( harvest.candidates.size(), 0 );
    for( std::size_t pairIndex = 0; pairIndex < harvest.candidates.size(); ++pairIndex )
    {
        const RenameCandidate& candidate = harvest.candidates[pairIndex];
        if( candidate.oldName == candidate.newName )
        {
            continue;
        }
        if( nameIsIndexed( candidate.oldName ) )
        {
            ++report.droppedOldStillHere;
            continue;
        }
        if( eligibleNamed( candidate.newName ) == nullptr )
        {
            ++report.droppedNewNotAtHead;
            continue;
        }
        keep[pairIndex] = 1;
    }
    for( std::size_t pairIndex = 0; pairIndex < harvest.candidates.size(); ++pairIndex )
    {
        if( !keep[pairIndex] )
        {
            continue;
        }
        for( std::size_t otherIndex = 0; otherIndex < harvest.candidates.size(); ++otherIndex )
        {
            if( otherIndex == pairIndex || !keep[otherIndex] )
            {
                continue;
            }
            if( harvest.candidates[otherIndex].oldName == harvest.candidates[pairIndex].oldName
                || harvest.candidates[otherIndex].newName == harvest.candidates[pairIndex].newName )
            {
                keep[pairIndex] = 2;   // marked, not cleared: the pass must not depend on its own output
                break;
            }
        }
    }

    detail::FileBytesCache fileBytes( ing.files.size() );
    for( std::size_t pairIndex = 0; pairIndex < harvest.candidates.size(); ++pairIndex )
    {
        if( keep[pairIndex] == 2 )
        {
            ++report.droppedAmbiguous;
            continue;
        }
        if( keep[pairIndex] != 1 )
        {
            continue;
        }
        const RenameCandidate& candidate = harvest.candidates[pairIndex];
        const Symbol*          newSymbol = eligibleNamed( candidate.newName );
        VERIFY( newSymbol != nullptr );

        Symbol oldSymbol = *newSymbol;
        oldSymbol.name   = candidate.oldName;
        if( !naminglens::detail::eligibleSymbol( oldSymbol ) )
        {
            ++report.droppedOldIneligible;   // the lens would skip this spelling ⇒ crediting a fire would be a lie
            continue;
        }

        std::string_view newSig;
        std::string      oldSig;
        if( newSymbol->kind == SymKind::Function || newSymbol->kind == SymKind::Method )
        {
            const std::string&  bytes = fileBytes.get( ing, newSymbol->fileId );
            const std::uint32_t sigA  = std::min( newSymbol->sigStartByte, std::uint32_t( bytes.size() ) );
            const std::uint32_t sigB  = std::min( newSymbol->sigEndByte, std::uint32_t( bytes.size() ) );
            newSig                    = std::string_view( bytes ).substr( sigA, sigB - sigA );
            oldSig                    = detail::substituteIdentifier( newSig, candidate.newName, candidate.oldName );
        }

        ScoredPair scored;
        scored.oldName = candidate.oldName;
        scored.newName = candidate.newName;
        scored.support = candidate.support;
        scored.fileId  = newSymbol->fileId;
        scored.line    = newSymbol->line;
        scored.oldMask = detail::firedRuleMask( oldSymbol, oldSig );
        scored.newMask = detail::firedRuleMask( *newSymbol, newSig );
        for( std::size_t ruleIndex = 0; ruleIndex < kRuleCount; ++ruleIndex )
        {
            const std::uint32_t bit = std::uint32_t( 1 ) << ruleIndex;
            report.rules[ruleIndex].oldFires += ( scored.oldMask & bit ) != 0 ? 1u : 0u;
            report.rules[ruleIndex].newFires += ( scored.newMask & bit ) != 0 ? 1u : 0u;
        }
        report.pairs.push_back( std::move( scored ) );
    }

    report.harvest = std::move( harvest );
    return report;
}

// ── emission ─────────────────────────────────────────────────────────────────────────────────────────────
// The legend the reader meets FIRST, and it leads with the caveat rather than burying it: a reader who takes
// `proxy=` for precision has been misled by this verb, so the sentence that says it is a proxy comes before
// the sentence that defines it. Every attribute emitted is defined here in the house `name=` form
// (test/legendcoveragecheck.sh derives that mechanically). No `--` digraph: illegal inside an XML comment.
inline constexpr const char* kNamingCalibrationLegend =
    "<!-- ripwire naming-calibration: each naming lint rule scored against this repo's OWN rename history. "
    "A NOISY PROXY, and that is the headline, not a footnote: developers rename for reasons that have nothing "
    "to do with name quality (rebrands, moves, API changes, type changes, reverts), so a pair labelled "
    "old to new is only WEAK evidence that the old spelling was the worse one. Read pairs= first; a small "
    "sample means nothing whatever the proxy says. "
    "pairs=labelled rename pairs that survived the join, the SAMPLE SIZE for every number below "
    "candidates=raw substitutions mined from the patch stream, before the join "
    "commits=commits walked "
    "hunks=diff hunks with content on both sides "
    "wide_hunks=hunks dropped for exceeding the per-side pairing cap "
    "drop_old_alive=candidates dropped because the old spelling is still an indexed name (so it was not renamed away) "
    "drop_new_absent=candidates dropped because the new spelling is no eligible indexed symbol at HEAD "
    "drop_ambiguous=candidates dropped because a name appeared on both sides of several candidates (a split, rework or revert) "
    "drop_old_skipped=candidates dropped because the lens would skip the old spelling, so no rule could ever have fired on it "
    "truncated=1 when a walk bound was hit, which makes candidates= a FLOOR "
    "probed=0 when there is no history to mine; r= says why "
    "r rows: n=rule name old=pairs where the rule fired on the ABANDONED spelling new=pairs where it fired on "
    "the CHOSEN spelling fired=old+new proxy=old/fired, the crude precision proxy, absent when fired=0 "
    "(0.50 is exactly chance: a rule that fires equally on both spellings has no signal) "
    "scope=group-rule marks a rule that fires on a RELATIONSHIP between co-visible names, which one pair "
    "cannot carry evidence about; it is reported unscored rather than as a meaningless 0/0. "
    "p rows: one labelled pair. o=old spelling n=new spelling sup=distinct hunks that showed the substitution "
    "at=path:line of the symbol the pair joined to old_fires=rules that fired on the old spelling "
    "new_fires=rules that fired on the new spelling (both absent when empty) -->";

namespace detail
{

inline std::string ruleListOf( std::uint32_t mask )
{
    std::string out;
    for( std::size_t ruleIndex = 0; ruleIndex < kRuleCount; ++ruleIndex )
    {
        if( ( mask & ( std::uint32_t( 1 ) << ruleIndex ) ) == 0 )
        {
            continue;
        }
        if( !out.empty() )
        {
            out.push_back( ' ' );
        }
        out.append( naminglens::detail::RuleSink{}.tallies[ruleIndex].tag );
    }
    return out;
}

}   // namespace detail

// Emit the report. Returns the process exit code — always 0: this is a MEASUREMENT. The floor a rule must
// clear is a policy, and it lives in test/namingcalibrationcheck.sh where a reader can see and argue with it.
inline int writeNamingCalibrationReport( const IngestResult& ing, const std::string& root )
{
    const CalibrationReport report = scoreRenamePairs( ing, mineRenamePairs( root ) );

    std::fputs( kNamingCalibrationLegend, stdout );
    if( !report.harvest.ok )
    {
        std::printf( "<naming-calibration probed=\"0\" r=\"%s\"/>",
                     report.harvest.nonGitRoot ? "not-a-git-repo" : "probe-failed" );
        return 0;
    }

    std::printf( "<naming-calibration probed=\"1\" pairs=\"%zu\" candidates=\"%zu\" commits=\"%u\" hunks=\"%llu\" wide_hunks=\"%llu\""
                 " drop_old_alive=\"%llu\" drop_new_absent=\"%llu\" drop_ambiguous=\"%llu\" drop_old_skipped=\"%llu\"%s>",
                 report.pairs.size(), report.harvest.candidates.size(), report.harvest.commitsWalked,
                 (unsigned long long)report.harvest.hunksScanned, (unsigned long long)report.harvest.hunksTooWide,
                 (unsigned long long)report.droppedOldStillHere, (unsigned long long)report.droppedNewNotAtHead,
                 (unsigned long long)report.droppedAmbiguous, (unsigned long long)report.droppedOldIneligible,
                 report.harvest.truncated ? " truncated=\"1\"" : "" );

    for( const RuleScore& score : report.rules )
    {
        if( !score.scored )
        {
            std::printf( "<r n=\"%s\" scope=\"group-rule\"/>", score.rule );
            continue;
        }
        const std::uint32_t fired = score.oldFires + score.newFires;
        std::printf( "<r n=\"%s\" old=\"%u\" new=\"%u\" fired=\"%u\"", score.rule, score.oldFires, score.newFires, fired );
        if( fired != 0 )
        {
            std::printf( " proxy=\"%.3f\"", double( score.oldFires ) / double( fired ) );
        }
        std::printf( "/>" );
    }

    // TWO scratch buffers, not one reused twice in the same call: escapeXml returns a VIEW into its `out`,
    // so a second call with the same buffer invalidates the first view (readability.h, same trap).
    std::vector<char> escOld;
    std::vector<char> escNew;
    std::vector<char> escPath;
    for( const ScoredPair& pair : report.pairs )
    {
        const std::string oldName( escapeXml( pair.oldName, escOld ) );
        const std::string newName( escapeXml( pair.newName, escNew ) );
        const std::string path( escapeXml( ing.files[pair.fileId], escPath ) );
        std::printf( "<p o=\"%s\" n=\"%s\" sup=\"%u\" at=\"%s:%u\"", oldName.c_str(), newName.c_str(), pair.support, path.c_str(), pair.line );
        const std::string oldFires = detail::ruleListOf( pair.oldMask );
        const std::string newFires = detail::ruleListOf( pair.newMask );
        if( !oldFires.empty() )
        {
            std::printf( " old_fires=\"%s\"", oldFires.c_str() );
        }
        if( !newFires.empty() )
        {
            std::printf( " new_fires=\"%s\"", newFires.c_str() );
        }
        std::printf( "/>" );
    }
    std::printf( "</naming-calibration>" );
    return 0;
}

}   // namespace renamemine
}   // namespace rw

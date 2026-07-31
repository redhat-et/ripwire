#pragma once

// mergescout.h — L1: --merge-scout=REF[,REF...] (PLAN_agentLeverage2026.md §L1), the read-only
// cross-branch overlap oracle. Evidence: a 2026-07-14 round hand-computed a landing order for 5
// concurrent agent branches by eyeballing which touched the same symbols — pure set intersection over
// data ripwire already has.
//
// For each REF, materialize (git-archive, read-only) BOTH its own tree and its merge-base-with-HEAD
// tree — reusing quality.h's materializeCommitTree, and (Y1, AUDIT5 P1) ingest()'s own incremental
// content-hash cache via a per-sha cache path (the SAME convention quality.h:1017-1021 uses for its own
// HEAD/ref ingest cache: a resolved commit sha is immutable, so the cache can never go stale — own "qms"
// blob family, see msCachePath below) — then diff per-symbol RAW-BODY hashes between them, keyed exactly
// like quality::bodyHashesBySym (canonicalId(relForHash(path,root), scope, name)). That gives "what this
// arm actually changed since it diverged from HEAD" — added, modified, OR deleted symbols. The dirty
// working tree participates as an implicit extra arm (base = HEAD; no merge-base call needed — a working
// tree is never diverged by commits) when `git status --porcelain` is non-empty; it reuses the CALLER's
// own already-ingested working-tree IngestResult (no re-ingest).
//
// Pairwise across arms: a changed SYMBOL present on two arms = a true CONFLICT (same-symbol collision —
// a real merge will fight over it). Two arms changing DIFFERENT symbols in the SAME FILE = textual RISK
// (no content collision, but a plain 3-way text merge can still produce an ugly diff worth a human's
// glance). Landing order: fewest-conflicts-first GREEDY — repeatedly land the not-yet-landed arm with the
// fewest true conflicts against the arms still remaining (so landing it never blocks on a conflict that a
// later landing would have to re-resolve anyway); ties break on ref name ascending — deterministic.
//
// ── ANCHORING, stated rather than assumed (r26 merge-base audit) ─────────────────────────────────────────
// Every arm here is BASE-ANCHORED by construction: a named arm is `merge-base(REF,HEAD) → REF`, and the
// working-tree arm is `HEAD → disk` (a working tree has not diverged by commits, so HEAD *is* its base).
// Nothing in this file ever diffs a ref against live HEAD, so it never had the "fires constantly because
// HEAD moved" failure --abi had to be corrected for (abicheck.h §AUTHORSHIP). That is deliberate and it is
// the right anchor for the question this verb asks — "which of MY branches fight EACH OTHER" is a question
// about what each arm authored, and a file an arm never opened cannot make it fight anything.
//
// But base-anchoring HIDES one real thing, and hiding it silently would be the same sin in the other
// direction: work that has ALREADY LANDED on HEAD since an arm forked. Arm A and arm B both changing symbol
// S is reported as a conflict; arm A changing S when the live line ALSO changed S since A forked is exactly
// as much of a merge fight, and no pairwise arm comparison can see it because HEAD is not an arm. So it is
// kept — as its own labelled row class, `head_conflicts=` / <head-conflict>, never folded into the pairwise
// conflict count and never used to re-HEAD-anchor the arm diff itself. Cost: for each DISTINCT merge-base
// that is not HEAD's own sha, one extra tree diff against HEAD's already-memoized index; arms that forked
// off current HEAD (the common case) skip the lane entirely.
//
// Read-only, always: every tree is a `git archive`-extracted TEMP COPY under the hardened cache ladder
// (quality.h's materializeCommitTree) — this module never runs `git checkout`, never touches the real
// working tree or any ref, and never mutates repo state. An unresolvable REF is a loud refusal (the
// caller exits non-zero, naming the ref) decided BEFORE any archive work starts — never a silently-empty
// arm buried in otherwise-good output. A non-git root / repo with no HEAD commit degrades to an empty
// result (DEGRADED_PATH_ALERT), matching quality.h's own non-git convention.

#include "model.h"
#include "ingest.h"
#include "quality.h"      // materializeCommitTree / TmpTreeGuard / bodyHashesBySym / gitOneLine / gitHeadSha / gitRepoHasHistory
#include "resolve.h"      // canonicalId
#include "arch.h"         // relForHash, fnv1a64
#include "jsonesc.h"      // shSingleQuote
#include "serialize.h"    // escapeXml
#include "workspace.h"    // wsdetail::segmentsOf — the shared delimiter-split primitive (also splits the CSV ref list)
#include "Diagnostics.h"  // DEGRADED_PATH_ALERT

#include "btree.hpp"      // gtl::btree_map — sorted iteration, cache-friendly (house rule: never std::map)

#include <algorithm>
#include <cstdio>
#include <functional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace ctx
{
namespace mergescout
{

inline const char* kWorkingTreeRef = "working-tree";   // reserved arm name for the dirty working tree — never a valid --merge-scout REF token

// One changed symbol as reported to the user.
struct ChangedSym
{
    std::uint64_t key = 0;     // fnv1a64(canonicalId(relForHash(path,root), scope, name)) — the SAME keying
                               // scheme quality::bodyHashesBySym uses, so a symbol changed on two arms'
                               // independently-materialized temp trees compares key-for-key regardless of
                               // where each tree was archived to (S2 root-spelling independence — exploited
                               // here across genuinely DIFFERENT temp roots, not just different spellings).
    std::string   file;        // root-relative path (relForHash)
    std::string   id;          // canonicalId — the human-readable identity
};

// One arm's derived state: what it changed since its base.
struct Arm
{
    std::string             ref;        // display name: the REF as given, or kWorkingTreeRef
    std::string             baseSha;    // merge-base(REF,HEAD) sha, or HEAD's sha for the working-tree arm
    bool                    ok = true;  // false ⇒ degraded (no merge-base / archive failed) — arm still
                                        // reported, with an empty changed set (never silently dropped)
    std::vector<ChangedSym> changed;    // sorted by key

    // r26 anchoring audit — the one thing base-anchoring hides, kept as its own row class (see this file's
    // §ANCHORING): symbols in `changed` that the LIVE LINE also changed between this arm's merge-base and
    // HEAD. A subset of `changed`, key-sorted, and empty by construction for an arm that forked off current
    // HEAD (baseSha == headSha) or for the working-tree arm.
    std::vector<ChangedSym> headConflicts;
};

// key -> body hash, and key -> identity, for one materialized tree. Overloads sharing a canonical id
// fold to ONE key exactly like quality::bodyHashesBySym (sorted-hash join) — identity keeps the FIRST
// symbol seen for that key (display only; never used for the hash comparison itself).
struct SymTreeIndex
{
    gtl::btree_map<std::uint64_t, std::uint64_t> bodyHash;
    gtl::btree_map<std::uint64_t, ChangedSym>     identity;
};

inline SymTreeIndex buildTreeIndex( const IngestResult& ing, std::string_view root )
{
    SymTreeIndex out;
    out.bodyHash = quality::bodyHashesBySym( ing, root, /*pathQualified=*/true );
    for( NodeId i = 0; i < ing.symbols.size(); ++i )
    {
        const Symbol& s = ing.symbols[i];
        if( s.fileId >= ing.files.size() || s.endByte <= s.sigStartByte ) continue;   // no real body → not in bodyHash either
        const std::string    relFile( relForHash( ing.files[ s.fileId ], root ) );
        const std::string    canon = canonicalId( relFile, s.scope, s.name );          // DISPLAY id (may be a bare name)
        std::string          idText;                                                   // COMPARISON key — always path-qualified
        idText.append( relFile ).push_back( '\0' );  idText.append( s.scope ).push_back( '\0' );  idText.append( s.name );
        const std::uint64_t  key   = fnv1a64( idText );
        out.identity.try_emplace( key, ChangedSym{ key, relFile, canon } );   // first writer wins — overloads share one id
    }
    return out;
}

// Y1 (AUDIT5 P1) — the per-sha committish INGEST cache family. `committish` is always a fully-resolved
// commit sha by the time it reaches here (resolveCommittish / merge-base already peeled any symbolic
// ref), so its tree is immutable — the SAME per-sha cache convention quality.h uses for its own
// qheadsnap/qbody families (shaKeyedCachePath + a real cacheFile handed to ingest()), but its OWN "qms"
// family so a multi-arm scout run's ~2*refCount+1 distinct trees don't thrash quality.h's own 2-slot
// keep cap. No extra per-family eviction cap here: the dir-wide 2 GiB / 30-day sweep
// (quality::sweepStaleCacheBlobsOnce) already runs on every ingest() saveCache and matches the
// "ripwire-" prefix generically, so it backstops this family too.
constexpr std::uint32_t kMsCacheScheme = 1;

inline std::string msExclHex( const std::vector<std::string>& excludes )
{
    return quality::exclConfigHex( excludes, "qms" + std::to_string( kMsCacheScheme ) );
}

inline std::string msCachePath( const std::string& repoHex, const std::string& exclHex, const std::string& sha )
{
    return quality::shaKeyedCachePath( "qms", repoHex, exclHex, sha );
}

// Materialize + ingest one committish (git-archive, read-only, TEMP copy) into a SymTreeIndex. Empty
// committish, a failed archive, or an empty ingest degrades to an empty (still valid) index — never
// throws, never crashes (mirrors quality.h's own archive/ingest degrade contract).
//
// Previously this handed ingest() an EMPTY cacheFile, forcing a full cold tree-sitter PARSE of every
// arm's tree on EVERY run despite the header comment above claiming cache reuse — the audited 9.15 s /
// 967 MB, 6-cold-ingest finding (mergescout.h:115). `repoHex`/`exclHex` are computed once by the caller
// (TreeIndexMemo) and threaded through so this per-committish call is a single hash-format + lookup, not
// a repeated realpath/hash-config cost per tree.
inline SymTreeIndex indexCommittish( const std::string& root, const std::string& committish,
                                     const std::vector<std::string>& excludes, std::size_t maxFileBytes,
                                     const std::string& repoHex, const std::string& exclHex )
{
    if( committish.empty() ) return {};
    const std::string tmpRoot = quality::materializeCommitTree( root, committish, "qms" );
    if( tmpRoot.empty() ) return {};
    quality::TmpTreeGuard guard{ tmpRoot };
    const std::string cachePath = msCachePath( repoHex, exclHex, committish );
    IngestResult ing = ingest( tmpRoot.c_str(), excludes, std::string_view( cachePath ), maxFileBytes, /*captureValueUses=*/false );
    if( ing.symbols.empty() && ing.files.empty() ) return {};
    return buildTreeIndex( ing, tmpRoot );
}

// Diff `ref` against `base`: every key present in either with a DIFFERENT (or one-sided) body hash —
// added, modified, or deleted. Sorted by key (determinism). Identity prefers the ref-side (still-
// existing) symbol; a deletion falls back to the base-side identity (the only side that still names it).
inline std::vector<ChangedSym> diffTreeIndex( const SymTreeIndex& base, const SymTreeIndex& ref )
{
    std::vector<std::uint64_t> keys;
    keys.reserve( base.bodyHash.size() + ref.bodyHash.size() );
    for( const auto& [ k, v ] : base.bodyHash ) { (void)v; keys.push_back( k ); }
    for( const auto& [ k, v ] : ref.bodyHash )  { (void)v; keys.push_back( k ); }
    std::sort( keys.begin(), keys.end() );
    keys.erase( std::unique( keys.begin(), keys.end() ), keys.end() );

    std::vector<ChangedSym> out;
    out.reserve( keys.size() );
    for( std::uint64_t k : keys )
    {
        const auto bIt = base.bodyHash.find( k );
        const auto rIt = ref.bodyHash.find( k );
        const bool inBase = bIt != base.bodyHash.end();
        const bool inRef  = rIt != ref.bodyHash.end();
        if( inBase && inRef && bIt->second == rIt->second ) continue;   // unchanged — the common case, skipped

        if( const auto rId = ref.identity.find( k ); rId != ref.identity.end() )       out.push_back( rId->second );
        else if( const auto bId = base.identity.find( k ); bId != base.identity.end() ) out.push_back( bId->second );
        // else: a body-hash key with no identity entry on either side can't happen (buildTreeIndex derives
        // both from the same symbol pass) — degrade by simply not naming it, never crash.
    }
    return out;   // already key-sorted (built from the sorted `keys` vector)
}

// Resolve REF to a commit sha via `git rev-parse --verify --quiet REF^{commit}` (the ^{commit} peel
// rejects anything that isn't a committish — a blob/tree hash, a malformed ref). "" ⇒ unresolvable, the
// caller's loud-refusal gate. Mirrors gitmine.h's resolveSinceScope rev probe.
inline std::string resolveCommittish( const std::string& root, std::string_view ref )
{
    return quality::gitOneLine( root, "rev-parse --verify --quiet " + shSingleQuote( std::string( ref ) + "^{commit}" ) + " 2>/dev/null" );
}

// Split "A,B,C" on commas, dropping empty tokens — the same primitive workspace.h's segmentsOf uses for
// path segments, reused here with ',' instead of hand-rolling a second copy of the same loop.
inline std::vector<std::string_view> splitRefs( std::string_view csv )
{
    return wsdetail::segmentsOf( csv, ',' );
}

struct ScoutResult
{
    bool              ok = true;     // false ⇒ refused — see badRef (a bad REF token) or nonGitRoot (below)
    bool              nonGitRoot = false;   // X9(a): root has no git history at all — a DIFFERENT refusal
                                             // reason than badRef (there is no ref to name); the caller picks
                                             // its message off this flag instead of guessing from badRef=="".
    std::string       badRef;        // set when ok==false && !nonGitRoot: the offending ref token
    std::string       headSha;
    std::vector<Arm>  arms;          // one per REF (declaration order), + the working-tree arm last when dirty
};

// The per-sha tree-index memo. The COMMON case is every arm having diverged straight off current HEAD, so
// EVERY merge-base equals headSha — memoizing means that tree is materialized/ingested exactly ONCE for
// the whole call, not once per arm (also dedupes a REF sha reused as another's merge-base). `get` returns
// a COPY, not a reference: gtl::btree_map (unlike std::map/HashMap) does not promise reference stability
// across a later insert into the SAME map (a node split can relocate an existing value), and a caller
// commonly needs two indices from one memo with an insert possibly happening in between. A SymTreeIndex
// is two small per-repo maps; copying it once per lookup is cheap next to the git-archive + ingest it
// amortizes away on a memo hit.
//
// Y1 (AUDIT5 P1) — bounded peak memory: a SymTreeIndex shadows the WHOLE tree's symbol set (one entry per
// real-bodied symbol in the repo), so holding every arm's tree alive for the whole call — as the memo did
// before — means peak RSS scales with arm count on a multi-arm scout. The caller now REGISTERS every
// planned `get(sha)` up front via `reserve(sha)` (once per occurrence across all arms) before the diff
// loop starts; `get` then drops a sha's cache_ entry the moment its LAST registered use has been served,
// so a tree's memory is freed right after the diff that consumes it rather than held for the rest of the
// run. A sha `get()` without a matching `reserve()` degrades to "never released" (safe over-caching, not a
// correctness bug) — every call site in this file always reserves first.
class TreeIndexMemo
{
public:
    TreeIndexMemo( const std::string& root, const std::vector<std::string>& excludes, std::size_t maxFileBytes )
        : root_( root ), excludes_( excludes ), maxFileBytes_( maxFileBytes ),
          repoHex_( quality::headSnapRepoHex( root ) ), exclHex_( msExclHex( excludes ) ) {}

    // Register one future get(sha) BEFORE the diff loop runs — see the class comment above.
    void reserve( const std::string& sha ) { ++pending_[ sha ]; }

    SymTreeIndex get( const std::string& sha )
    {
        const auto it = cache_.find( sha );
        SymTreeIndex result = ( it != cache_.end() )
            ? it->second
            : cache_.try_emplace( sha, indexCommittish( root_, sha, excludes_, maxFileBytes_, repoHex_, exclHex_ ) ).first->second;

        // Release: once every reserved use of `sha` has been served, drop the (potentially large,
        // whole-repo) SymTreeIndex from cache_ so it is freed instead of held for the rest of the run.
        if( const auto p = pending_.find( sha ); p != pending_.end() )
        {
            if( --( p->second ) == 0 ) { pending_.erase( p ); cache_.erase( sha ); }
        }
        return result;
    }

private:
    const std::string&               root_;
    const std::vector<std::string>&  excludes_;
    std::size_t                      maxFileBytes_;
    std::string                      repoHex_;
    std::string                      exclHex_;
    gtl::btree_map<std::string, SymTreeIndex> cache_;
    gtl::btree_map<std::string, std::size_t>  pending_;   // remaining reserved get() calls per sha
};

// Resolve + validate EVERY ref BEFORE any archive work — a bad ref is a loud refusal, never a partial/
// empty arm silently buried in otherwise-good output. Empty `badRef` (2nd of the pair) on success.
inline std::pair<std::vector<std::string>, std::string> resolveAllRefs( const std::string& root, const std::vector<std::string_view>& refs )
{
    std::vector<std::string> shas( refs.size() );
    for( std::size_t i = 0; i < refs.size(); ++i )
    {
        if( refs[i] == kWorkingTreeRef ) return { {}, std::string( refs[i] ) };   // reserved — collides with the implicit arm
        shas[i] = resolveCommittish( root, refs[i] );
        if( shas[i].empty() ) return { {}, std::string( refs[i] ) };
    }
    return { std::move( shas ), std::string{} };
}

// Merge-base(REF,HEAD) resolution — split out of computeNamedArm (Y1) so computeMergeScout can resolve
// every arm's base sha BEFORE the diff loop starts, letting it register each sha's total memo.get() use
// count with TreeIndexMemo::reserve() up front (see that class's comment).
inline std::string resolveMergeBase( const std::string& root, const std::string& refSha, const std::string& headSha )
{
    return quality::gitOneLine( root, "merge-base " + shSingleQuote( refSha ) + " " + shSingleQuote( headSha ) + " 2>/dev/null" );
}

// One named-REF arm: diff its tree against its (already-resolved) merge-base with HEAD. `ok=false`
// (empty `changed`) when the merge-base was unresolvable (unrelated histories) — a degrade, never a crash.
inline Arm computeNamedArm( std::string_view ref, const std::string& refSha, const std::string& baseSha, TreeIndexMemo& memo )
{
    Arm arm; arm.ref = std::string( ref ); arm.baseSha = baseSha;
    if( arm.baseSha.empty() )
    {
        arm.ok = false;   // unrelated histories / merge-base failed — degrade, never crash
        DEGRADED_PATH_ALERT( "merge-scout: no merge-base for ref (unrelated history?) — reporting an empty arm" );
        return arm;
    }
    arm.changed = diffTreeIndex( memo.get( arm.baseSha ), memo.get( refSha ) );
    return arm;
}

// ── the head-conflict lane (r26): what the LIVE LINE already changed since an arm forked ────────────────

// Keys the live line changed between `baseSha` and HEAD — i.e. work that has already LANDED while this arm
// sat unmerged. Key-sorted (diffTreeIndex's own contract), so the intersection below can binary-search it.
// Empty — and, crucially, costing NO tree at all — when the arm forked off current HEAD (baseSha == headSha,
// the common case) or when its merge-base never resolved.
inline std::vector<std::uint64_t> headChangedKeysSince( const std::string& baseSha, const std::string& headSha, TreeIndexMemo& memo )
{
    std::vector<std::uint64_t> keys;
    if( baseSha.empty() || baseSha == headSha ) return keys;

    const std::vector<ChangedSym> headChanged = diffTreeIndex( memo.get( baseSha ), memo.get( headSha ) );
    keys.reserve( headChanged.size() );
    for( const ChangedSym& s : headChanged ) keys.push_back( s.key );
    return keys;   // already key-sorted (diffTreeIndex emits in key order)
}

// The arm's own changed symbols that the live line ALSO changed since the arm forked. A subset of
// `changed`, so it stays key-sorted and keeps the arm-side identity spelling.
inline std::vector<ChangedSym> intersectHeadChanged( const std::vector<ChangedSym>& changed, const std::vector<std::uint64_t>& headKeys )
{
    std::vector<ChangedSym> out;
    if( headKeys.empty() ) return out;

    for( const ChangedSym& s : changed )
        if( std::binary_search( headKeys.begin(), headKeys.end(), s.key ) ) out.push_back( s );
    return out;
}

// The lane's plan: merge-base sha -> the live line's changed keys since it, one entry per DISTINCT base that
// is not HEAD's own sha (an arm forked off current HEAD cannot collide with landed work — there is none).
using HeadChangedByBase = gtl::btree_map<std::string, std::vector<std::uint64_t>>;

// Which bases the lane will actually diff. Empty on the common "everything forked off current HEAD" shape,
// so that shape pays nothing: no extra tree, no extra diff, no extra memo reservation.
inline HeadChangedByBase planHeadConflictLane( const std::vector<std::string>& baseShas, const std::string& headSha )
{
    HeadChangedByBase plan;
    for( const std::string& baseSha : baseShas )
        if( !baseSha.empty() && baseSha != headSha ) plan.try_emplace( baseSha );
    return plan;
}

// Register the lane's future memo.get() calls — one extra use of each side per distinct base — BEFORE any
// tree is materialized, so TreeIndexMemo still frees a tree right after its true LAST consumer (Y1).
inline void reserveHeadConflictLane( const HeadChangedByBase& plan, const std::string& headSha, TreeIndexMemo& memo )
{
    for( const auto& [ baseSha, keys ] : plan )
    {
        (void)keys;
        memo.reserve( baseSha );
        memo.reserve( headSha );
    }
}

// The dirty working tree as an implicit extra arm — base = HEAD directly (a working tree is never
// diverged by commits, so no merge-base call is needed); `workingIng` is the real on-disk tree, the
// CALLER's own crawl (no re-ingest here).
inline Arm computeWorkingTreeArm( const std::string& root, const std::string& headSha, const IngestResult& workingIng, TreeIndexMemo& memo )
{
    Arm arm;
    arm.ref     = kWorkingTreeRef;
    arm.baseSha = headSha;
    arm.changed = diffTreeIndex( memo.get( headSha ), buildTreeIndex( workingIng, root ) );
    return arm;
}

// The whole computation. `workingIng` is the CALLER's own already-ingested real working tree (root =
// `root` itself, not a temp copy) — reused directly for the implicit working-tree arm, no re-ingest.
inline ScoutResult computeMergeScout( const std::string& root, std::string_view refsCsv,
                                      const IngestResult& workingIng,
                                      const std::vector<std::string>& excludes, std::size_t maxFileBytes )
{
    ScoutResult result;

    // X9(a) fix: this used to be a soft degrade (ok=true, arms empty → the caller printed an empty
    // <merge-scout arms="0"/> and exited 0) — indistinguishable from "ran clean, no conflicts", and a
    // silent contradiction of the help text's "single-root only" / refusal contract for anything
    // unscoutable. A non-git root (or no HEAD commit) has NOTHING to diff against by construction, same
    // shape as an unresolvable REF — refuse loudly (exit 1) instead of a misleadingly-clean empty answer.
    if( !quality::gitRepoHasHistory( root ) )
    {
        result.ok         = false;
        result.nonGitRoot = true;
        return result;
    }

    const std::vector<std::string_view> refs = splitRefs( refsCsv );
    if( refs.empty() ) { result.ok = false; result.badRef = std::string( refsCsv ); return result; }

    result.headSha = quality::gitHeadSha( root );

    auto [ refShas, badRef ] = resolveAllRefs( root, refs );
    if( !badRef.empty() ) { result.ok = false; result.badRef = std::move( badRef ); return result; }

    // Resolve every arm's merge-base FIRST (Y1) — lets us register total planned memo.get() uses per sha
    // (below) before any tree is materialized, so TreeIndexMemo can free a tree right after its LAST
    // consumer instead of holding every arm alive for the whole call.
    std::vector<std::string> baseShas( refs.size() );
    for( std::size_t i = 0; i < refs.size(); ++i )
        baseShas[i] = resolveMergeBase( root, refShas[i], result.headSha );

    const bool dirty = !quality::gitOneLine( root, "status --porcelain 2>/dev/null" ).empty();   // dirty ⇒ the implicit extra arm

    HeadChangedByBase headChangedByBase = planHeadConflictLane( baseShas, result.headSha );

    TreeIndexMemo memo( root, excludes, maxFileBytes );
    for( std::size_t i = 0; i < refs.size(); ++i )
    {
        if( baseShas[i].empty() ) continue;   // unresolvable merge-base — computeNamedArm degrades below without touching the memo
        memo.reserve( baseShas[i] );
        memo.reserve( refShas[i] );
    }
    if( dirty ) memo.reserve( result.headSha );
    reserveHeadConflictLane( headChangedByBase, result.headSha, memo );

    // The head-conflict diffs run FIRST: their reserves are already counted above, so a base tree they touch
    // stays memoized for the arm loop below instead of being materialized twice.
    for( auto& [ baseSha, keys ] : headChangedByBase )
        keys = headChangedKeysSince( baseSha, result.headSha, memo );

    for( std::size_t i = 0; i < refs.size(); ++i )
    {
        Arm arm = computeNamedArm( refs[i], refShas[i], baseShas[i], memo );
        if( const auto it = headChangedByBase.find( arm.baseSha ); it != headChangedByBase.end() )
            arm.headConflicts = intersectHeadChanged( arm.changed, it->second );
        result.arms.push_back( std::move( arm ) );
    }

    if( dirty )
        result.arms.push_back( computeWorkingTreeArm( root, result.headSha, workingIng, memo ) );

    return result;
}

// ── pairwise overlap + landing order ─────────────────────────────────────────────────────────────────

struct RiskPair { ChangedSym a; ChangedSym b; };

struct PairOverlap
{
    std::size_t              a = 0, b = 0;   // indices into ScoutResult::arms
    std::vector<ChangedSym>  conflicts;      // same key changed by both arms
    std::vector<RiskPair>    risks;          // different keys, same file
};

// One pair's overlap: every same-key hit (conflict) and every same-file/different-key hit (risk)
// between two arms' changed-symbol lists. Split out of computeOverlaps so the O(arms²) nesting there
// stays two levels deep — this is the (only) O(changed²) level.
inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm& armA, const Arm& armB )
{
    PairOverlap p; p.a = a; p.b = b;
    for( const ChangedSym& x : armA.changed )
        for( const ChangedSym& y : armB.changed )
        {
            if( x.key == y.key )        p.conflicts.push_back( x );
            else if( x.file == y.file ) p.risks.push_back( RiskPair{ x, y } );
        }
    return p;
}

inline std::vector<PairOverlap> computeOverlaps( const std::vector<Arm>& arms )
{
    std::vector<PairOverlap> pairs;
    for( std::size_t a = 0; a < arms.size(); ++a )
        for( std::size_t b = a + 1; b < arms.size(); ++b )
            pairs.push_back( computeOnePairOverlap( a, b, arms[a], arms[b] ) );
    return pairs;
}

// True-conflict count between arm `i` and every OTHER not-yet-landed arm — landingOrder's per-candidate
// score. Split out so landingOrder's own greedy loop stays two levels deep.
inline std::size_t conflictScoreAgainstRemaining( std::size_t i, const std::vector<PairOverlap>& pairs, const std::vector<char>& landed )
{
    std::size_t score = 0;
    for( const PairOverlap& p : pairs )
    {
        if( p.conflicts.empty() ) continue;
        if( p.a == i && !landed[ p.b ] )      ++score;
        else if( p.b == i && !landed[ p.a ] ) ++score;
    }
    return score;
}

// The not-yet-landed arm with the lowest conflictScoreAgainstRemaining; ties break on ref name ascending.
inline std::size_t pickNextToLand( const std::vector<Arm>& arms, const std::vector<PairOverlap>& pairs, const std::vector<char>& landed )
{
    std::size_t best = 0, bestScore = std::size_t( -1 );
    bool haveBest = false;
    for( std::size_t i = 0; i < arms.size(); ++i )
    {
        if( landed[i] ) continue;
        const std::size_t score = conflictScoreAgainstRemaining( i, pairs, landed );
        if( !haveBest || score < bestScore || ( score == bestScore && arms[i].ref < arms[best].ref ) )
        { best = i; bestScore = score; haveBest = true; }
    }
    return best;
}

// Fewest-conflicts-first GREEDY landing order: repeatedly land the not-yet-landed arm with the fewest
// true conflicts against arms still remaining; tie-break by ref name ascending. Deterministic.
//
// §P11.13: an arm with NO divergent work vs its merge-base (changed="0" — already merged, or a ref that
// never forked any real work) has nothing TO land. Pre-marking it "landed" excludes it from every step's
// candidate pool (pickNextToLand skips landed[i]) without perturbing the greedy choice among the arms that
// DO have work — the loop below still runs exactly once per REMAINING arm, same algorithm, smaller input.
inline std::vector<std::size_t> landingOrder( const std::vector<Arm>& arms, const std::vector<PairOverlap>& pairs )
{
    std::vector<char> landed( arms.size(), 0 );
    std::size_t       toLand = 0;
    for( std::size_t i = 0; i < arms.size(); ++i )
    {
        if( arms[i].changed.empty() ) { landed[i] = 1; continue; }   // nothing to land — see writeScoutArm's note=
        ++toLand;
    }
    std::vector<std::size_t> order;
    order.reserve( toLand );
    for( std::size_t step = 0; step < toLand; ++step )
    {
        const std::size_t next = pickNextToLand( arms, pairs, landed );
        landed[next] = 1;
        order.push_back( next );
    }
    return order;
}

// ── XML emission (G4: minified, xmllint-clean; no `\n` outside CDATA) ──────────────────────────────────

// The shared escapeXml-backed closure type these three helpers take, so each stays a small free function
// instead of a nested lambda (which is what pushed writeMergeScout itself over the complexity/LOC bar).
using XmlEscaper = std::function<std::string( std::string_view )>;

// The ONE `<TAG p= id=/>` symbol-row loop every list in this file emits (<sym>, <head-conflict>,
// <conflict>) — three callers, one spelling, so the escape/format contract can never drift between them.
inline void writeSymRows( std::FILE* out, const char* tag, const std::vector<ChangedSym>& syms, const XmlEscaper& ex )
{
    for( const ChangedSym& s : syms )
        std::fprintf( out, "<%s p=\"%s\" id=\"%s\"/>", tag, ex( s.file ).c_str(), ex( s.id ).c_str() );
}

inline void writeScoutArm( std::FILE* out, const Arm& arm, const XmlEscaper& ex )
{
    // §A10.4: base= is display-only here — 9-hex-char width, matching the at=/head= convention
    // (gitstamp.h) every other sha-bearing attribute in the tool uses. arm.baseSha itself stays full-length
    // (it is still used as a TreeIndexMemo key elsewhere); only the printed attribute is truncated.
    std::fprintf( out, "<arm ref=\"%s\" base=\"%s\" ok=\"%d\" changed=\"%zu\" head_conflicts=\"%zu\">",
                  ex( arm.ref ).c_str(), ex( arm.baseSha.substr( 0, 9 ) ).c_str(), arm.ok ? 1 : 0, arm.changed.size(), arm.headConflicts.size() );
    // §P11.13: a changed="0" arm has no divergent work to LAND — it used to get a landing slot anyway
    // (landingOrder() below drops it now, see there), with nothing on this row saying why it's absent from
    // the list an agent would otherwise expect it in. A meaningfully-named child element carrying a `note=`
    // attribute (docdrift.h/gitoracle.h's own convention: note= as an attribute on a named element, not a
    // wrapper tag), listed alongside the other advisory facts (<sym>/<head-conflict>) rather than crowding
    // the fixed header run above. --stray-content is the verb that answers "is this ref stale / already
    // superseded" — this row just points there instead of re-deriving that itself.
    if( arm.changed.empty() )
        std::fprintf( out, "<no-work note=\"no divergent work vs merge-base — see --stray-content\"/>" );
    writeSymRows( out, "sym", arm.changed, ex );

    // r26: the live line changed these too, while this arm sat unmerged — a merge fight no pairwise ARM
    // comparison can see (HEAD is not an arm). Listed after the <sym> rows, never mixed into them.
    writeSymRows( out, "head-conflict", arm.headConflicts, ex );
    std::fprintf( out, "</arm>" );
}

inline void writeScoutPair( std::FILE* out, const std::vector<Arm>& arms, const PairOverlap& p, const XmlEscaper& ex )
{
    std::fprintf( out, "<pair a=\"%s\" b=\"%s\" conflicts=\"%zu\" risks=\"%zu\"",
                  ex( arms[ p.a ].ref ).c_str(), ex( arms[ p.b ].ref ).c_str(), p.conflicts.size(), p.risks.size() );
    if( p.conflicts.empty() && p.risks.empty() ) { std::fprintf( out, "/>" ); return; }
    std::fprintf( out, ">" );
    writeSymRows( out, "conflict", p.conflicts, ex );
    for( const RiskPair& r : p.risks )
        std::fprintf( out, "<risk p=\"%s\" a=\"%s\" b=\"%s\"/>", ex( r.a.file ).c_str(), ex( r.a.id ).c_str(), ex( r.b.id ).c_str() );
    std::fprintf( out, "</pair>" );
}

inline void writeScoutLanding( std::FILE* out, const std::vector<Arm>& arms, const std::vector<PairOverlap>& pairs, const XmlEscaper& ex )
{
    if( arms.empty() ) return;
    const std::vector<std::size_t> order = landingOrder( arms, pairs );
    std::string joined;
    for( std::size_t idx = 0; idx < order.size(); ++idx )
    { if( idx ) joined += ','; joined += arms[ order[idx] ].ref; }
    std::fprintf( out, "<landing order=\"%s\"/>", ex( joined ).c_str() );
}

inline void writeMergeScout( std::FILE* out, const ScoutResult& result )
{
    std::vector<char> esc;
    const XmlEscaper ex = [ & ]( std::string_view s ) { return std::string( escapeXml( s, esc ) ); };

    // G4: an XML comment may not contain a double hyphen, so this text names flags and attributes WITHOUT
    // their leading dashes (the same constraint crossref.h's own comments call out). Keep it that way.
    std::fprintf( out, "<!-- ripwire merge-scout: read-only cross-branch overlap for %zu arm(s) — same-symbol change "
                       "on two arms = conflict, same-file/different-symbol = textual risk. landing = "
                       "fewest-conflicts-first greedy (ties: ref name asc). Every tree is a git-archive TEMP COPY "
                       "(read-only); the real working tree/refs are never touched. ANCHORING: every arm is diffed "
                       "against its OWN merge base with HEAD (the working tree arm against HEAD itself), never "
                       "against live HEAD — so a file an arm never opened can never appear here just because the "
                       "live line moved. head_conflicts= is the one thing that anchor hides, kept as its own row "
                       "class: symbols this arm changed that the LIVE LINE also changed since the arm forked, a "
                       "merge fight no pairwise ARM comparison can see because HEAD is not an arm. -->", result.arms.size() );
    // §P8: head= was a FULL 40 here vs 9 hex in <abi>/<stray-content>/<landing-plan>/<history> — one name,
    // two widths. Aligned to the majority; nothing reads this one. (`base=` on the <arm> rows is still full
    // against <stray-content>'s 9-char base= — a second split, documented, not widened into this change.)
    std::fprintf( out, "<merge-scout arms=\"%zu\" head=\"%.9s\">", result.arms.size(), ex( result.headSha ).c_str() );

    for( const Arm& arm : result.arms ) writeScoutArm( out, arm, ex );

    const std::vector<PairOverlap> pairs = computeOverlaps( result.arms );
    for( const PairOverlap& p : pairs ) writeScoutPair( out, result.arms, p, ex );

    writeScoutLanding( out, result.arms, pairs, ex );

    std::fprintf( out, "</merge-scout>" );
}

}}   // namespace ctx::mergescout

#pragma once

// editcheck.h — the shared contract-comparison core behind --edit-check=SYM (CLI, B11/L5) and the MCP
// edit_check verb (L4, PLAN_audit5Public2026.md). "Did MY edit change a contract someone depends on", at
// edit time, for ONE symbol — compares the WORKING-TREE symbol against the git-HEAD baseline
// (computeHeadSnapshot — the SAME qheadsnap/qsnap cache family --quality-delta's auto-baseline uses, so a
// warm run is a cache-blob read, never a fresh git-archive/ingest/clone-detection pass). main.cpp's
// runEditCheck() and mcpverbs.h's editCheckText() both call editCheckBundleText() below for an
// ALREADY-RESOLVED focus symbol — symbol resolution + the "not found" message stay with each caller (the
// CLI's did-you-mean suggestion vs the MCP verb's plain not-found are presentation, not computation).
//
// Included BEFORE mcp.h in main.cpp so mcpverbs.h can reach editCheckBundleText() — self-contained (its own
// #includes only) so include ORDER elsewhere in main.cpp never matters to it.

#include "model.h"
#include "graph.h"
#include "serialize.h"     // escapeXml / symTag
#include "quality.h"        // computeHeadSnapshot / isPublicApi / baselineCanonId — the SAME qheadsnap/qsnap cache family --quality-delta uses
#include "arch.h"           // fnv1a64
#include "gitstamp.h"       // r26-stamp Task A: gitstamp::atAttr — the at="<sha>[+dirty]" root anchor
#include "graphlegend.h"    // §H4 §3.4: the shared counts_floor= marker + floor/counting-unit legend tail

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <span>
#include <string>
#include <utility>
#include <vector>

namespace rw
{

// the contract-comparison result (was/now only meaningful when status=="contract-change"). POD, no default
// member initializers — editCheckContractVsHead value-initializes it (`{}`), and an in-class initializer
// would generate an implicit-ctor symbol the quality-delta dead-code kind false-flags.
struct EditCheckContract
{
    const char*   status;
    std::uint32_t wasParams;
    std::uint32_t nowParams;
    std::uint32_t wasDefs;      // baseline overload-set CARDINALITY (quality::Snapshot::defsBySym) — the one
    std::uint32_t nowDefs;      //   baseline fact a MAX cannot express; see editCheckVerdict for why it exists
    bool          wasPublic;
    bool          nowPublic;
};

// the overload set sharing `focus`'s DEFINITION SITE (same file + scope + name) — the was/now comparison MUST
// be MAX-aggregated over this set, never read off `focus` alone (the B10 overload trap).
//
// §A6a — the file id is part of the key, not decoration: canonicalId() degrades to the BARE NAME whenever no
// scope is known (free functions, and every language whose scope we do not capture), so a canonId-only test
// unions three unrelated free functions named `empty` in three different files into one "overload set" and
// reports one contract for all of them. Two definitions are one contract only when they share a file AND a
// scope — which is exactly what the `file:name` selector can pick out.
inline std::vector<NodeId> editCheckOverloadSet( const IngestResult& ing, const Graph& g, NodeId focus )
{
    std::vector<NodeId> overloadNodes;
    if( focus < g.canonId.size() && !g.canonId[ focus ].empty() )
        for( NodeId i = 0; i < ing.symbols.size(); ++i )
            if( i < g.canonId.size() && g.canonId[i] == g.canonId[ focus ] && ing.symbols[i].fileId == ing.symbols[ focus ].fileId )
                overloadNodes.push_back( i );
    if( overloadNodes.empty() ) overloadNodes.push_back( focus );   // degrade: no canonId — treat focus alone as its own set
    return overloadNodes;
}

// ── §A6a: the DISTINCT contracts one --edit-check selector matched ───────────────────────────────────────
// A contract is per definition site. --callers may honestly UNION the callers of every overload (it says so:
// defs="3"); this verb may not — "did I break a contract?" answered about a definition the agent never edited
// is worse than no answer, because status="unchanged" reads as reassurance. So a selector that matches more
// than one definition SITE is REFUSED, and the refusal hands back the spellings that pick one.
//
// The group key is (file, scope) — see editCheckOverloadSet on why canonId alone is not enough. `spelling` is
// what the caller should retype: `file:name` when that file holds exactly one group, else the canonical id
// (both resolve through resolveAllByNameQualified).
struct EditCheckGroup
{
    NodeId      lowestNode;    // the lowest-id definition in the group — the focus resolveFocus would have picked
    std::string spelling;      // a selector that resolves to THIS group and no other
};

inline std::vector<EditCheckGroup> editCheckGroups( const IngestResult& ing, const Graph& g, std::span<const NodeId> matches )
{
    // one pass, keyed by (fileId, canonId): matches arrive in ascending node id (resolveAllByNameQualified
    // walks ing.symbols in order), so the first node seen for a key IS the group's lowest id.
    std::vector<EditCheckGroup>               groups;
    std::vector<std::pair<std::uint32_t, std::string>> keys;
    for( NodeId m : matches )
    {
        if( m >= ing.symbols.size() ) continue;
        const std::uint32_t fileId = ing.symbols[m].fileId;
        const std::string   canon  = ( m < g.canonId.size() ) ? g.canonId[m] : ing.symbols[m].name;
        if( std::find( keys.begin(), keys.end(), std::make_pair( fileId, canon ) ) != keys.end() ) continue;
        keys.emplace_back( fileId, canon );
        groups.push_back( EditCheckGroup{ m, std::string{} } );
    }

    // the spelling: file:name is the form an agent can paste from any p="file:line" row, so prefer it and fall
    // back to the canonical id only where the file alone cannot separate two scopes — and NOT even then when
    // the canonical id has degraded to the bare name (a scope-less definition), which disambiguates nothing.
    for( std::size_t groupIndex = 0; groupIndex < groups.size(); ++groupIndex )
    {
        const Symbol&      s            = ing.symbols[ groups[ groupIndex ].lowestNode ];
        const std::string& canonOfThis  = keys[ groupIndex ].second;
        std::size_t        groupsInFile = 0;
        for( const auto& [ fileId, canon ] : keys ) if( fileId == s.fileId ) ++groupsInFile;

        const bool fileIsEnough = ( groupsInFile == 1 ) || ( canonOfThis == s.name );
        groups[ groupIndex ].spelling = fileIsEnough ? ing.files[ s.fileId ] + ":" + s.name : canonOfThis;
    }
    return groups;
}

// The ONE ambiguity refusal both surfaces print, so the CLI and the MCP verb cannot drift apart: name what is
// ambiguous, say how many contracts it matched and why this verb cannot union them, list the spellings that
// pick one, and give one as a ready-to-run example. `exampleForm` is the surface's own retry syntax
// ("--edit-check=" for the CLI, "symbol=" for MCP). The listing is CAPPED — a name with forty definitions is
// a wall of text, and the count already tells the reader how many were left unsaid.
//
// §B4.1 — the message carries TWO DIFFERENT quantities and used to print `groups.size()` for both. They are
// not the same number: `groups` is the per-(file,scope) COLLAPSED count (the contracts this verb would have
// to choose between), while `definitionCount` is resolveAllByNameQualified's match count — exactly what
// --callers/--uses/--impact put in their `defs=`. The two diverge the moment one file holds two same-named
// defs (on this repo: 53 contracts, 58 definitions), and the refusal was then making a CHECKABLE FALSE CLAIM
// about a sibling verb's output, which is the worst kind of wrong — an agent can act on it without re-running
// anything. Each number now carries the noun it actually is. definitionCount >= groups.size() always
// (collapsing distinct matches into a group can never invent one), which is asserted rather than assumed.
constexpr std::size_t kEditCheckSpellingsShown = 6;

inline std::string editCheckAmbiguousMessage( std::string_view spec, std::span<const EditCheckGroup> groups,
                                              std::string_view exampleForm, std::size_t definitionCount )
{
    VERIFY( groups.size() > 1 );
    VERIFY( definitionCount >= groups.size() );

    std::string msg = "'" + std::string( spec ) + "' is ambiguous — it matches " + std::to_string( definitionCount )
                    + " definitions in " + std::to_string( groups.size() ) + " distinct contracts, and a contract is per "
                      "definition SITE (--callers may union overloads and disclose defs=\""
                    + std::to_string( definitionCount ) + "\"; this verb cannot). Qualify one contract: ";
    const std::size_t shownCount = std::min( groups.size(), kEditCheckSpellingsShown );
    for( std::size_t groupIndex = 0; groupIndex < shownCount; ++groupIndex )
        msg += ( groupIndex ? ", " : "" ) + groups[ groupIndex ].spelling;
    if( groups.size() > shownCount ) msg += " (+" + std::to_string( groups.size() - shownCount ) + " more contracts)";

    msg += " — e.g. " + std::string( exampleForm ) + groups[0].spelling;
    return msg;
}

// compare the working-tree overload set's (MAX params, publicness) against the git-HEAD baseline snapshot.
// status is exactly one of unchanged / new-symbol / contract-change (see the CLI --edit-check doc comment in
// main.cpp for the full semantics). `root` MUST be spelled exactly as the caller's `ing`/`g` were built
// against — baselineCanonId keys are root-relative, so a mismatched root spelling manufactures phantom
// contract-changes (the same AUDIT5 D1 class of bug quality_delta's MCP verb already guards against).
inline EditCheckContract editCheckContractVsHead( const IngestResult& ing, const Graph& g, const std::string& root,
                                                  std::size_t maxFileBytes, const std::vector<std::string>& excludes,
                                                  NodeId focus, std::span<const NodeId> overloadNodes )
{
    EditCheckContract res{};
    res.status  = "unchanged";
    // COUNTED UNDER THE BASELINE'S OWN KEY, not over `overloadNodes`, and the difference is the §A6a trap
    // recorded on editCheckOverloadSet — measured, on 118 of 953 sampled symbols of this repo, before it was
    // fixed. computeSnapshot buckets by hash(baselineCanonId) and baselineCanonId is g.canonId with the path
    // segment made root-relative, so equal g.canonId ⇔ equal baseline key. `overloadNodes` is that bucket
    // INTERSECTED with the focus's file, because a CONTRACT is per definition site. Comparing a file-scoped
    // count against a canonId-scoped one is comparing two different questions and reports a phantom whenever a
    // scope-less name (which canonicalId degrades to a BARE NAME) also exists in another file. Both sides are
    // canonId-scoped here, so on an unedited tree they are equal by construction — the property that makes
    // this signal safe to put in the headline at all.
    for( NodeId i = 0; i < ing.symbols.size(); ++i )
        if( i < g.canonId.size() && !g.canonId[i].empty() && g.canonId[i] == g.canonId[ focus ] ) ++res.nowDefs;
    for( NodeId i : overloadNodes ) res.nowParams = std::max( res.nowParams, std::uint32_t( ing.symbols[i].params ) );
    // §B11.3 — the WORKING-TREE side must fold the group exactly the way the BASELINE side folds it, or the
    // two numbers are answers to different questions. computeSnapshot takes the MAX of params over every node
    // sharing a baseline key and push_backs `publicApi` PER NODE (so presence in that sorted set is an OR over
    // the group). params was already MAX here; publicness was read off `focus` ALONE under a comment asserting
    // the two can never differ ("every overload shares the same file → same answer"). That assertion is true of
    // isPublicApi as written today — it is a pure function of the file extension plus the Section kind — but it
    // is a claim about a function in another header, i.e. exactly the kind of "the seam rule stated in a comment"
    // that rots. OR over the group instead: identical answer today, structurally symmetric with the snapshot
    // forever, and one fewer invariant to remember.
    for( NodeId i : overloadNodes ) res.nowPublic = res.nowPublic || quality::isPublicApi( ing, i );

    // HEAD baseline — the warm path MUST hit computeHeadSnapshot's own qsnap cache (the ≤100ms budget).
    auto [ base, baselineOk ] = quality::computeHeadSnapshot( root, nullptr, maxFileBytes, excludes );
    const std::uint64_t key   = fnv1a64( quality::baselineCanonId( ing, focus, root ) );
    if( !baselineOk || base.locBySym.find( key ) == base.locBySym.end() )
    {
        res.status = "new-symbol";
        if( !baselineOk ) DEGRADED_PATH_ALERT( "edit-check: no git HEAD baseline available — treating SYM as new-symbol" );
        return res;
    }

    const auto pit = base.paramsBySym.find( key );
    res.wasParams  = ( pit == base.paramsBySym.end() ) ? 0u : pit->second;
    res.wasPublic  = std::binary_search( base.publicApi.begin(), base.publicApi.end(), key );

    // the CARDINALITY of the baseline overload set — the one baseline fact none of the MAX-folded kinds can
    // express. computeSnapshot fills defsBySym in the same unconditional loop that fills locBySym, so a key
    // present in one is present in the other by construction; a blob where it is not is corrupt, and the
    // degrade is "claim no movement" (never a phantom contract-change out of a cache defect).
    const auto dit = base.defsBySym.find( key );
    if( dit == base.defsBySym.end() )
    {
        res.wasDefs = res.nowDefs;
        DEGRADED_PATH_ALERT( "edit-check: baseline snapshot has no definition count for SYM — defs_was suppressed" );
    }
    else res.wasDefs = dit->second;

    res.status = ( res.wasParams != res.nowParams || res.wasPublic != res.nowPublic || res.wasDefs != res.nowDefs )
                 ? "contract-change" : "unchanged";
    return res;
}

// ── THE MAX FOLD'S SECOND CONSEQUENCE, AND WHY defs_was HAD TO EXIST ──────────────────────────────────────
// The MAX aggregation has TWO consequences and only the first is benign. ADDING a wider overload raises
// params_now with nothing broken — a false alarm, the one the legend used to name. REMOVING an overload whose
// parameter count is BELOW the max moves NEITHER number, because the max survives on both sides, while the
// call site that used the removed definition stops binding. status="unchanged" is then a false REASSURANCE
// out of the one verb whose whole value is that headline word — the worse of the two failures.
//
// WHY THE FIX IS defs_was AND NOT THE FLAGGED-CALLER COUNT — measured, because the obvious fix is wrong. The
// document already carries `incompatible=`, so "escalate whenever a caller is flagged" is one line. It is
// also a CATEGORY ERROR: status is a was-vs-now verdict and incompatible= is a property of the tree as it
// stands, computed against the CURRENT definitions from NAME-BASED call edges.
//
// RE-DERIVED, and the method matters because a differently-drawn population answers a different question.
// Population = every t="fn"/t="m" symbol of this repo addressed by its own CANONICAL ID (1378 of them), on a
// CLEAN tree — nothing edited, everything compiling. Before the implicit-receiver wildcard above: **19**
// carried a nonzero incompatible=. After it: **7**, all C++, and every one of the twelve that went away was
// the Python `self` off-by-one. The 7 that remain are the irreducible NAME-BINDING class — a receiver-
// qualified call to a same-named callee this tool does not index (a std/third-party method) resolves onto the
// one indexed definition and is then measured against the wrong arity. They are NOT a precision bug this verb
// can fix cheaply: a receiver-qualified suppression predicate was probed against the worst case and took
// `--edit-check=src/ingest.cpp:find` only from 151 flagged of 169 callers to 34 — carried forward from the
// probe that established it, NOT re-derived here, and recorded as such so the next reader knows which half of
// this paragraph is measured in-tree. Either way it trades a large false-positive rate for an unquantified
// false-NEGATIVE rate on the one signal that must not lie, so the honest move is the legend's, not a
// filter's. (The same three selectors are the gate's anchors: `src/ingest.cpp:find`
// 151/169, `src/notes.h:find` 41/171, `src/svector.h:end` 5/265 — spelled `file:name`, which folds by file
// and so draws a WIDER caller set than the canonical-id form the sweep used.)
//
// Joining any of that into the headline would have moved a percent of an untouched tree to
// "contract-change". So the verdict joins only WAS-VS-NOW facts, and the third
// one is the overload set's CARDINALITY, which quality::Snapshot now carries (defsBySym) precisely because
// every other kind it stores is a MAX and a MAX cannot see a set shrink. On a clean tree defs_was == defs_now
// everywhere, so this adds no noise at all; on the removal it moves 2 -> 1 and carries the verdict.
//
// `broken-callers` therefore appears in change= only ALONGSIDE a was/now fact — never alone. It says "and a
// call site is flagged too", which is worth reading when the set demonstrably moved and is worth nothing when
// it did not. The residual, stated because a reader will look for it: an overload whose arity changes BELOW
// the max while the count stays (a 1-arg replaced by another 1-arg) moves nothing here either.
struct EditCheckVerdict
{
    const char* status;   // unchanged / new-symbol / contract-change — the DOCUMENT's headline
    std::string change;   // the evidence list, non-empty exactly when status == "contract-change"
};

inline EditCheckVerdict editCheckVerdict( const EditCheckContract& contract, std::size_t incompatibleCount )
{
    // new-symbol is not reassurance ABOUT A CONTRACT — there was none to compare against — so it is never
    // escalated and carries no change list. Its callers can still be flagged; that is the payload's job.
    if( std::string_view( contract.status ) == "new-symbol" ) return EditCheckVerdict{ contract.status, std::string{} };

    std::string change;
    const auto  add = [ &change ]( const char* token ) { if( !change.empty() ) change += ","; change += token; };
    if( contract.wasParams != contract.nowParams ) add( "params" );
    if( contract.wasPublic != contract.nowPublic ) add( "public" );
    if( contract.wasDefs   != contract.nowDefs   ) add( "defs" );
    // corroboration only, and only where something else already carried the verdict — see the note above for
    // the measurement that rules it out as a verdict-carrier of its own.
    if( !change.empty() && incompatibleCount > 0 ) add( "broken-callers" );

    // the two derivations tied together so they cannot drift: editCheckContractVsHead's own status IS the
    // was/now half of exactly this expression, so the change list is empty exactly where that half said
    // unchanged.
    VERIFY( change.empty() == ( std::string_view( contract.status ) == "unchanged" ) );
    return EditCheckVerdict{ change.empty() ? "unchanged" : "contract-change", std::move( change ) };
}

// ── the implicit-RECEIVER wildcard, recognised here because ingest's own version cannot fire ──────────────
// A definition whose first parameter is a receiver the call site never writes: `params` counts it, the
// call-site argument count does not, so an EXACT-arity comparison is off by one — and off in the direction
// that manufactures a flag. ingest.cpp's cc_paramArityExact already exempts this class, but it keys on
// `kind == SymKind::Method`, and Python's tags.scm has no `@definition.method` at all: every `def`, including
// one nested in a class, is captured as `@definition.function`. So the exemption is unreachable for Python —
// on this repo it could not fire on a single definition, and 12 of the 19 nonzero incompatible= counts on an
// untouched, compiling tree were exactly this shape (`self.m()` counted 0 args against a `def m( self )`
// counted 1 param).
//
// Recognised instead from the structural fact ingest DOES record: Python/Ruby capture the enclosing class as
// the definition's `scope` (P2-D Rule 1), so a non-empty scope in one of those languages means an implicit
// `self`/`cls`. The test is deliberately made HERE rather than on `arityExact`, which is also graph.h's
// call-resolution arity filter — moving it there would move edge counts corpus-wide, which is the qualified-
// call round's agenda and not this one's. graph.h needs no equivalent change: its filter drops a candidate
// only when `argCount > params`, and the implicit receiver errs the other way (0 args vs 1 param), so that
// one-sided form is already safe against this class.
//
// Residual, stated because it is a deliberate over-approximation: a Python function nested inside another
// FUNCTION also has a non-empty scope and is exempted too. That direction only ever suppresses a flag, which
// is the safe side of a one-sided test.
inline bool editCheckImplicitReceiver( const Symbol& s ) noexcept
{
    return ( s.lang == Lang::Python || s.lang == Lang::Ruby ) && !s.scope.empty();
}

// per-node flags for the seen callers whose call-site is incompatible with the CURRENT arity: a call site is
// flagged only when its argument count is reliably counted AND NO overload could accept it (every overload
// has a FIXED arity (arityExact!=0) that disagrees — a variadic/default-arg/implicit-receiver wildcard can
// never be proven wrong by an argument count). ONE pass over ing.references, bucketed by the seenCaller
// membership test — never an O(callers × references) rescan.
//
// The test is one-sided IN THE ARITY only: it never flags a call the compared definitions could accept. It is
// NOT a proof that the call site binds to those definitions at all — that half is name-based, and the emitted
// legend says so.
inline std::vector<char> editCheckIncompatibleFlags( const IngestResult& ing, std::span<const NodeId> overloadNodes,
                                                     const std::string& symName, std::span<const char> seenCaller )
{
    const auto provenIncompatible = [ & ]( std::uint16_t argCount ) -> bool
    {
        for( NodeId ov : overloadNodes )
            if( const Symbol& os = ing.symbols[ov];
                os.arityExact == 0 || editCheckImplicitReceiver( os ) || os.params == argCount ) return false;   // a candidate could still accept it
        return true;
    };
    std::vector<char> callerIncompatible( ing.symbols.size(), 0 );
    for( const Reference& r : ing.references )
    {
        if( r.role != RefRole::Call || r.fromSymbol >= seenCaller.size() || !seenCaller[ r.fromSymbol ] ) continue;
        if( r.calleeName != symName || !r.argCountKnown )                                                  continue;
        if( provenIncompatible( r.argCount ) ) callerIncompatible[ r.fromSymbol ] = 1;
    }
    return callerIncompatible;
}

// 1-hop callers of the overload set (the --callers in-edge walk, unioned), sorted (file, line, name), plus a
// parallel per-node flag for call-sites PROVABLY incompatible with the CURRENT arity.
inline std::pair<std::vector<NodeId>, std::vector<char>>
editCheckCallers( const IngestResult& ing, const Graph& g, std::span<const NodeId> overloadNodes, const std::string& symName )
{
    std::vector<char>   seenCaller( ing.symbols.size(), 0 );
    std::vector<NodeId> callerIds;
    const auto* ro = g.inEdges.rowOffsets();
    const auto* ci = g.inEdges.colIndices();
    for( NodeId ov : overloadNodes )
    {
        if( ov >= ing.symbols.size() ) continue;
        for( std::uint32_t k = ro[ov]; k < ro[ov + 1]; ++k )
            if( NodeId c = ci[k]; c < seenCaller.size() && !seenCaller[c] ) { seenCaller[c] = 1; callerIds.push_back( c ); }
    }

    std::vector<char> callerIncompatible = editCheckIncompatibleFlags( ing, overloadNodes, symName, seenCaller );

    std::sort( callerIds.begin(), callerIds.end(), [ & ]( NodeId a, NodeId b )
    {
        const Symbol& sa = ing.symbols[a];  const Symbol& sb = ing.symbols[b];
        if( sa.fileId != sb.fileId ) return ing.files[sa.fileId] < ing.files[sb.fileId];
        return sa.line != sb.line ? sa.line < sb.line : sa.name < sb.name;
    } );
    return { std::move( callerIds ), std::move( callerIncompatible ) };
}

// THE bundle assembler for an ALREADY-RESOLVED `focus` symbol: builds the <edit-check>…</edit-check> XML
// (status + was/now on contract-change + the flagged 1-hop callers) and returns it as a string — never
// touches stdout. `root`/`maxFileBytes`/`excludes` feed the HEAD-baseline comparison (see
// editCheckContractVsHead's root-spelling note).
inline std::string editCheckBundleText( const IngestResult& ing, const Graph& g, const std::string& root,
                                        std::size_t maxFileBytes, const std::vector<std::string>& excludes, NodeId focus )
{
    const Symbol& fsym = ing.symbols[ focus ];

    const std::vector<NodeId> overloadNodes = editCheckOverloadSet( ing, g, focus );
    const EditCheckContract   contract      = editCheckContractVsHead( ing, g, root, maxFileBytes, excludes, focus, overloadNodes );
    const auto [ callerIds, callerIncompatible ] = editCheckCallers( ing, g, overloadNodes, fsym.name );

    // the flagged-caller COUNT, needed BEFORE the headline is written: the verdict joins it with the was/now
    // pair (see editCheckVerdict), so counting it after the status attribute was already emitted is what made
    // "unchanged" reachable beside a proven break.
    std::size_t incompatibleCount = 0;
    for( NodeId c : callerIds ) if( callerIncompatible[c] ) ++incompatibleCount;
    const EditCheckVerdict verdict = editCheckVerdict( contract, incompatibleCount );

    std::vector<char> esc;
    const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };

    std::string out = "<!-- ripwire edit-check: SYM's contract (param count + publicness) NOW vs git HEAD — unchanged/new-symbol/"
                       "contract-change — plus its 1-hop callers. A caller is flagged incompatible=\"1\" when its argument count "
                       "was reliably counted and NO definition in the folded set could accept it: every one has a FIXED arity that "
                       "disagrees. A variadic, defaulted or implicit-receiver definition (a Python/Ruby method, whose params counts "
                       "the self/cls the call site never writes) has no fixed arity and is never flagged. That makes the ARITY half "
                       "one-sided — a call the compared definitions could accept is never flagged — but it is NOT a proof that the "
                       "call site binds to THIS definition. Call edges are matched by NAME, so a receiver-qualified call to a "
                       "same-named callee this tool does not index (a standard-library or third-party method) is measured against "
                       "the one definition it does index; a clean, compiling tree can therefore carry a nonzero incompatible= with "
                       "nothing edited at all, and on a widely-shared name it can be most of that name's callers. Read incompatible= "
                       "as a fact about the tree as it stands — call sites worth OPENING, not a verdict — and status= as a fact "
                       "about the edit. Warm path hits the qheadsnap/qsnap "
                       "cache — never a full quality-delta style recompute. "
                       // §B11.3 — the FOLD, and its consequence, stated where the numbers are read. Everything below is
                       // a disclosure of arithmetic that was already happening silently.
                       "defs= is how many DEFINITIONS at this site (same file, same scope, same name — the overload set) "
                       "are folded into this one contract; a selector matching more than one SITE is refused instead, so "
                       "defs= only ever counts overloads. params_was and params_now are the MAX over that set on each side "
                       "(the same MAX the baseline snapshot stores), and publicness is the OR. That MAX has TWO "
                       "consequences, in opposite directions. It can read like a break and not be one: adding a WIDER "
                       "overload beside an unchanged one raises params_now with no existing definition altered, so it "
                       "reports status=\"contract-change\" with incompatible=\"0\" and a def row still carrying the old "
                       "parameter count — no seen caller breaks. And it can read like safety and not be: REMOVING an "
                       "overload whose parameter count is BELOW the MAX moves neither number, because the MAX survives "
                       "on both sides, while the call site that used the removed definition no longer binds. "
                       "defs_was=/defs_now= is what closes that: the count of definitions sharing this symbol's "
                       "CANONICAL ID on each side. That population is the one the baseline snapshot buckets by, so the "
                       "two numbers answer the same question and are equal on an unedited tree — it is deliberately NOT "
                       "the root's defs=, which is the same bucket narrowed to this FILE (a contract is per definition "
                       "site), so where a scope-less name also exists in another file defs= is the smaller of the two. "
                       "status is therefore the join of THREE was-vs-now facts — the params MAX, publicness, and the "
                       "definition COUNT — and change= names which of them carried it. "
                       "change= adds broken-callers when a seen caller is also flagged, but never on its own — for the "
                       "reason stated at the top: incompatible= describes the TREE and status= describes the EDIT, so a "
                       "headline must not turn on it. RESIDUAL: an overload whose arity changes "
                       "BELOW the MAX while the COUNT stays the same moves none of the three. "
                       "The root's incompatible= is the COUNT of flagged callers (a c row's incompatible=\"1\" is the "
                       "per-caller flag). p= is the definition the selector resolved to; when defs is above 1 EVERY folded "
                       "definition is listed as its own def row (p=, t=, params=), which is what tells a widened single "
                       "definition apart from an added overload. At defs=\"1\" no def row is emitted: the root's own p=/t= "
                       "is that definition, and params_now is its parameter count. ";
    // §H4 §3.4: the shared floor + counting-unit tail, appended from the ONE constant every graph-count verb
    // splices. It is load-bearing HERE more than anywhere: callers="1" on a symbol with an unmodelled second
    // caller is the exact shape §H4 measured, and this legend's own "the tree as it stands" paragraph reads
    // as if the caller SET were complete.
    out += graphCountDisclosure();
    out += "-->";
    // §B14 — composed on std::string, NOT snprintf'd into a fixed buffer. `ex()` has already escaped the name
    // and the path, so a truncating snprintf here would cut the ESCAPED form: mid-entity, mid-attribute-name or
    // mid-UTF-8, i.e. a document xmllint rejects at exit 0 (measured: clean at a 456-byte path, broken at 458,
    // and as low as 228 RAW bytes once `&`/`'` expand 5:1/6:1 before the buffer). See serialize.h's
    // FIXED-BUFFER RULE for the escaper-side test that separates this shape from the safe one.
    out += "<edit-check sym=\"";  out += ex( fsym.name );
    out += "\" t=\"";             out += symTag( fsym.kind );
    out += "\" p=\"";             out += ex( ing.files[ fsym.fileId ] );
    out += ":";                   out += std::to_string( fsym.line );
    out += "\" status=\"";        out += verdict.status;   // the JOINED verdict, never editCheckContractVsHead's metric half alone
    out += "\"";
    // §B11.3 — DISCLOSE THE FOLD. The was/now pair is a MAX over `overloadNodes`, and the reader had no way to
    // learn the set was bigger than one: `--callers` on the same name says defs="2" while this verb reported a
    // scalar and named ONE definition site in p=. defs= is emitted UNCONDITIONALLY (not "absent when 1", the
    // map's `overloads=` convention) precisely because the sibling it is read against, --callers, always emits
    // it — an attribute a reader has never seen present cannot warn them.
    char defsAttr[ 32 ];
    std::snprintf( defsAttr, sizeof( defsAttr ), " defs=\"%zu\"", overloadNodes.size() );
    out += defsAttr;
    if( std::string_view( verdict.status ) == "contract-change" )
    {
        char cc[ 192 ];
        std::snprintf( cc, sizeof( cc ), " params_was=\"%u\" params_now=\"%u\" public_was=\"%d\" public_now=\"%d\" defs_was=\"%u\" defs_now=\"%u\"",
                       contract.wasParams, contract.nowParams, contract.wasPublic ? 1 : 0, contract.nowPublic ? 1 : 0,
                       contract.wasDefs, contract.nowDefs );
        out += cc;
        // change= sits AFTER the was/now group, never between its members: those four attributes are read as
        // two adjacent pairs (here and in the gate), and an attribute inserted mid-group breaks that silently.
        // Composed from fixed tokens only — no corpus text reaches it, so it needs no escaping.
        out += " change=\"";  out += verdict.change;  out += "\"";
    }
    // the flagged-caller COUNT beside the caller count. A contract-change with every caller unflagged is the
    // additive-overload shape the legend names, and "zero rows carry incompatible=" was previously an ABSENCE
    // the reader had to notice rather than a number they could read. (Counted above — the headline needs it.)
    char callersOpen[ 64 ];
    std::snprintf( callersOpen, sizeof( callersOpen ), " callers=\"%zu\" incompatible=\"%zu\"", callerIds.size(), incompatibleCount );
    out += callersOpen;
    // r26-stamp Task A: the HEAD baseline this contract compares against is only meaningful pinned to a
    // commit (+dirty state) — omitted entirely on a non-git root. Appended LAST (after every pre-existing
    // attribute) so an existing substring-adjacency assertion elsewhere (e.g. "status=\"x\" callers=\"N\"")
    // never silently breaks the way test/prcontextcheck.sh's did until this same placement rule was applied
    // there too.
    out += gitstamp::atAttr( root );
    // §H4 §3.4: LAST, after at= — same placement rule, same reason (no existing attribute-adjacency
    // assertion in test/ can break on an attribute appended past the end of every group).
    out += kGraphCountFloorAttrXml;
    out += ">";
    // §B11.3 — one row per FOLDED definition, so the set behind the scalar is nameable. Emitted only above
    // defs="1" (at 1 the row would restate the root's own p=/t=, and params_now already IS its parameter
    // count — a stated rule in the legend, not a silent omission). Order is `overloadNodes`' own ascending
    // node id, which editCheckOverloadSet builds by a forward walk of ing.symbols → deterministic, and the
    // first row is always the definition p= names.
    if( overloadNodes.size() > 1 )
        for( NodeId ov : overloadNodes )
        {
            const Symbol& os = ing.symbols[ov];
            out += "<def p=\"";  out += ex( ing.files[ os.fileId ] );          // §B14 — std::string, not char[512]
            out += ":";          out += std::to_string( os.line );
            out += "\" t=\"";    out += symTag( os.kind );
            out += "\" params=\""; out += std::to_string( std::uint32_t( os.params ) );
            out += "\"/>";
        }
    for( NodeId c : callerIds )
    {
        const Symbol& cs = ing.symbols[c];
        out += "<c n=\"";   out += ex( cs.name );                        // §B14 — std::string, not char[512]
        out += "\" p=\"";   out += ex( ing.files[ cs.fileId ] );
        out += ":";         out += std::to_string( cs.line );
        out += "\"";
        if( callerIncompatible[c] ) out += " incompatible=\"1\"";
        out += "/>";
    }
    out += "</edit-check>";
    return out;
}

}   // namespace rw

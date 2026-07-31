#pragma once

// exemplar.h — SHARED selection logic for the --exemplar (Q7) write-moment verb.
//
// --exemplar returns the repo's BEST-IN-CLASS instance of the KIND the agent is about to write, as an
// imitation target ("copy its shape, not its text"). The pick is by ROLE — a DETERMINISTIC composite over
// tested / fan-in / cognitive-complexity — NEVER by textual similarity to the query (similar-snippet
// retrieval measurably hurts; RESEARCH §2d). This header holds ONLY the selection (kind resolution + winner
// choice); emission (the <exemplar> element + body) stays at the call sites, which differ (stdout vs memstream).
//
// A3-F5 CONTRACT REPAIR — the three invariants this selector now guarantees, so the verb cannot teach a
// wrong shape (the failure that motivated it: whole-repo --exemplar=fn returned `ingest`, ccx=294 — the single
// most complex function in the tree — because tested=1 + fan-in swamped a ccx term that only broke TIES):
//
//   INVARIANT 1 (ccx binds hard) — a candidate whose cognitive complexity exceeds kExemplarCcxCeiling
//     (= kExemplarCcxCeilFactor × kCcxBar) is INELIGIBLE. An unclean, hard-to-imitate blob can never win over
//     a clean sibling no matter how reused/tested it is. The ceiling only relaxes when NOTHING of the kind is
//     under it — then the least-complex over-bar candidate wins and the pick is flagged degraded (overCcxBar).
//
//   INVARIANT 2 (fixtures lose to real code) — a candidate under a test-fixture path (a path component matches
//     test|tests|fixture|fixtures|testdata) is a WORSE exemplar than any non-fixture candidate, because test
//     fixtures are trivially low-ccx synthetic stubs that would otherwise sweep the ccx sort. This is a HEAVY
//     PENALTY (a primary sort key: non-fixture beats fixture), NOT a hard filter — an all-tests repo still gets
//     a pick. It is deterministic (path-string test only).
//
//   INVARIANT 3 (weak task→kind is admitted, not hidden) — when the arg is a TASK STRING and its top-K lexical
//     hits are not CORROBORATED — fewer than kExemplarConfMinShare of the window carry a task subtoken in
//     their own name, not just their body (an incidental body/doc keyword-magnet hit, not a real match — the
//     failure that returned class `Foo` for "a test gate shell script…") — the kind it donates is
//     untrustworthy: fall back to kind=Function (the safe default write-target) and flag lowConfidence so the
//     caller can say so, rather than confidently exemplifying garbage. §P5 A3-F5b: checking only the single
//     #1-scoring hit's name is fooled in both directions (see kExemplarConfWindow's comment) — the window
//     asks whether the match is a genuine topical CLUSTER, not a coin flip on one hit.
//
// The composite winner order, most-significant first (every term a stable integer/flag → byte-stable pick):
//     fixture ASC → tested DESC → fan-in DESC → cognitive-cx ASC → loc ASC → id ASC.
// (Eligibility — ccx ceiling — is applied BEFORE the composite; only the ceiling-relax fallback re-admits.)

#include "model.h"
#include "graph.h"
#include "lexical.h"
#include "quality.h"   // kCcxBar

#include <algorithm>
#include <cstdint>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace ctx
{

// ── tunables (HEURISTICS — defensible defaults, documented in the XML header the verb emits) ──────────────
// ccx ceiling = kExemplarCcxCeilFactor × kCcxBar. kCcxBar (=15) is SonarSource's cognitive-complexity bar; a
// function already at 4× that (60) is a maintenance hotspot, not a shape to copy. 4× is deliberately generous
// (most clean repos have plenty under it) so the ceiling only bites the genuine blobs (ingest=294, buildGraph=306).
constexpr std::uint32_t kExemplarCcxCeilFactor = 4;
constexpr std::uint32_t kExemplarCcxCeiling     = kExemplarCcxCeilFactor * quality::kCcxBar;   // = 60

// INVARIANT 3 confidence gate (§P5 A3-F5b): a lexical BM25 top-1 hit is frequently an incidental
// body/doc keyword-magnet (one generic word buried in an unrelated function's prose), not a real match —
// checking ONLY the #1-scoring name (the pre-fix behaviour) is fooled in BOTH directions: a single shared
// generic word on an unrelated #1 hit reads as confident (false negative on low_confidence), while a genuine
// topical cluster that merely lost the #1 slot to one such outlier reads as unmatched (false positive).
// The fix inspects the top kExemplarConfWindow lexical hits as a WINDOW and asks a population question
// instead of a single-hit question: what fraction of that window shares a name subtoken with the task at
// all? A real topical match clusters — several differently-named, genuinely-relevant symbols each carry a
// query word in their name (parseGeneric/parseHeaderLine/parseCorpus/... for "parse command line arguments";
// render/renderD1CallerRows/renderMaskedBundle/... for "render mermaid diagram") — while a query with no
// real match in the corpus produces only incidental, sparse, one-off hits. kExemplarConfMinShare=0.4 (must
// exceed, not merely reach) with kExemplarConfWindow=10 was calibrated against both directions: it separates
// the reported false-negative ("format byte sizes for humans" -> 30%, correctly low_confidence) from the
// reported false-positive ("parse command line arguments" -> 60%, correctly trusted) with headroom on both
// sides (checked against 6 additional probe queries spanning clear-match and no-match cases).
constexpr std::size_t kExemplarConfWindow    = 10;
constexpr float       kExemplarConfMinShare  = 0.4f;

// case-insensitive equality of a path component against an already-lower-cased fixture token (allocation-free).
inline bool eqLowerAscii( std::string_view comp, std::string_view lowerToken ) noexcept
{
    if( comp.size() != lowerToken.size() ) return false;
    for( std::size_t k = 0; k < comp.size(); ++k )
    {
        const char c = ( comp[k] >= 'A' && comp[k] <= 'Z' ) ? char( comp[k] - 'A' + 'a' ) : comp[k];
        if( c != lowerToken[k] ) return false;
    }
    return true;
}

// does any '/'-delimited component of `path` EQUAL a fixture token (case-insensitive)? — INVARIANT 2.
// Component-EQUALITY (not substring) so "latest/" or "contest/" don't false-positive.
inline bool isFixtureComponent( std::string_view comp ) noexcept
{
    static constexpr std::string_view kFixtureComponents[] = { "test", "tests", "fixture", "fixtures", "testdata" };
    for( std::string_view fx : kFixtureComponents )
        if( eqLowerAscii( comp, fx ) ) return true;
    return false;
}

inline bool isFixturePath( std::string_view path ) noexcept
{
    // walk the components between '/' separators; the allocation-free '/'-scan hands each to isFixtureComponent.
    std::size_t start = 0;
    for( std::size_t i = 0; i <= path.size(); ++i )
    {
        const bool boundary = ( i == path.size() || path[i] == '/' );
        if( !boundary ) continue;
        if( isFixtureComponent( path.substr( start, i - start ) ) ) return true;
        start = i + 1;
    }
    return false;
}

// the kind-token table (constexpr-style dispatch, not a scattered if-chain at the call site). A non-token
// arg returns Other → the caller treats it as a task string.
inline SymKind exemplarKindFromToken( std::string_view t ) noexcept
{
    if( t == "fn"     || t == "function" )  return SymKind::Function;
    if( t == "method" )                     return SymKind::Method;
    if( t == "cls"    || t == "class" )     return SymKind::Class;
    if( t == "struct" )                     return SymKind::Struct;
    if( t == "iface"  || t == "interface" ) return SymKind::Interface;
    if( t == "var" )                        return SymKind::Var;
    return SymKind::Other;   // sentinel: not a kind token → treat the arg as a task
}

// ── THE SELECTION RULE, IN WORDS — stated ONCE (§B6 M13) ─────────────────────────────────────────────────
// Three surfaces described this file's composite three incompatible ways, and none of them matched the code:
// the CLI legend led with complexity, the MCP legend led with fan-in and named no ceiling and no fixture
// penalty, and the MCP tools/list description said "highest fan-in, lowest complexity, tested where
// possible" — an ordering that is simply not the one below. All three now RENDER this constant, so changing
// the composite is changing one string, and a reader who compares two surfaces cannot be told two things.
//
// G4: this text lands verbatim inside an XML comment on two of those surfaces, so it may not contain a "--"
// run; the flags it names are spelled bare (low_confidence=1), never with their leading dashes.
inline constexpr const char* kExemplarSelectionRule =
    "chosen by ROLE, NEVER by text similarity to your task: candidates are first filtered to cognitive "
    "complexity at or under the ccx ceiling (4x the complexity bar), then ordered non-fixture path before "
    "test-fixture path, tested before untested, higher fan-in, lower complexity, fewer lines, lowest id. "
    "low_confidence=1 marks a weak task-to-kind match that fell back to fn; over_ccx_bar=1 marks a corpus "
    "where nothing was under the ceiling, so the pick is the least bad rather than a clean one; candidates= "
    "counts the ELIGIBLE instances of the kind (post-ceiling), not every instance";

// The selection result. `winner == kNoNode` ⇒ no candidate of the kind (caller reports not-found).
struct ExemplarPick
{
    NodeId      winner        = kNoNode;
    SymKind     targetKind    = SymKind::Other;
    std::size_t candidateCount = 0;      // ELIGIBLE candidates considered (post-ceiling; the number emitted as candidates=)
    bool        fromTask       = false;  // the arg was a task string, not a kind token
    bool        lowConfidence  = false;  // INVARIANT 3: weak task→kind, fell back to Function
    bool        overCcxBar     = false;  // INVARIANT 1 relaxed: nothing under the ceiling, winner is over it
};

// does the winner's NAME share at least one subtoken with the task? (INVARIANT 3 confidence gate.)
inline bool shareNameSubtoken( std::string_view name, const std::vector<std::string>& taskToks )
{
    if( taskToks.empty() ) return false;
    std::vector<std::string> nameToks;
    subtokens( name, nameToks );
    for( const std::string& nt : nameToks )
        for( const std::string& qt : taskToks )
            if( nt == qt ) return true;
    return false;
}

// resolveExemplarKind — step 1: a kind token selects the target kind directly; a task string donates its
// top-lexical-match's kind, but only when TRUSTWORTHY (INVARIANT 3). Writes targetKind/fromTask/lowConfidence
// into `pick`; leaves winner=kNoNode. Returns false only when the corpus has no exemplifiable symbol at all
// (caller = not-found).
inline bool resolveExemplarKind( const IngestResult& ing, const Graph& g, std::string_view kindOrTask, ExemplarPick& pick )
{
    pick.targetKind = exemplarKindFromToken( kindOrTask );
    if( pick.targetKind != SymKind::Other ) return true;   // a kind token — done

    // TASK path: rank lexically, then sort the eligible symbols by (score DESC, id ASC) — a byte-stable
    // total order, so both the top-1 pick and the confidence window below are deterministic.
    pick.fromTask = true;
    const std::vector<float> lensRank = lexicalScores( ing, g.outOff, g.outTargets, kindOrTask );
    std::vector<std::pair<float, NodeId>> ranked;
    ranked.reserve( ing.symbols.size() );
    for( NodeId i = 0; i < ing.symbols.size(); ++i )
    {
        const SymKind k = ing.symbols[i].kind;
        if( k == SymKind::Section || k == SymKind::Other ) continue;   // never exemplify a doc heading / unknown
        ranked.emplace_back( lensRank[i], i );
    }
    if( ranked.empty() ) return false;   // no exemplifiable symbol in the whole corpus
    std::sort( ranked.begin(), ranked.end(), []( const auto& a, const auto& b )
    {
        return ( a.first != b.first ) ? ( a.first > b.first ) : ( a.second < b.second );
    } );
    const NodeId best      = ranked.front().second;
    const float  bestScore = ranked.front().first;

    // INVARIANT 3: trust the donated kind only when the match is corroborated, not just present. Checking
    // ONLY the #1 hit's name (the pre-fix check) is fooled both ways — see kExemplarConfWindow's comment
    // above. Instead: of the top kExemplarConfWindow lexical hits, what FRACTION carry a task subtoken in
    // their own name (not just their body)? A real topical match clusters; an incidental one doesn't.
    std::vector<std::string> taskToks;
    subtokens( kindOrTask, taskToks );
    const std::size_t window = std::min( kExemplarConfWindow, ranked.size() );
    std::size_t corroborating = 0;
    for( std::size_t j = 0; j < window; ++j )
        if( shareNameSubtoken( ing.symbols[ ranked[j].second ].name, taskToks ) ) ++corroborating;
    const float shareOfWindow = window ? float( corroborating ) / float( window ) : 0.f;
    const bool  trustworthy   = bestScore > 0.f && shareOfWindow > kExemplarConfMinShare;

    pick.targetKind    = trustworthy ? ing.symbols[best].kind : SymKind::Function;
    pick.lowConfidence = !trustworthy;
    return true;
}

// pickWinnerOfKind — step 2, ONE pass: the best-in-class of `targetKind` among candidates with ccx ≤ ceiling
// when `eligibleOnly`, else all of the kind. Sets pick.winner + pick.candidateCount. The composite (most-
// significant first): fixture ASC → tested DESC → fan-in DESC → ccx ASC → loc ASC → id ASC — all stable
// integers/flags, so the winner is byte-stable run-to-run.
inline void pickWinnerOfKind( const IngestResult& ing, const std::vector<std::uint32_t>& fanIn,
                              const std::vector<std::uint8_t>& tested, bool eligibleOnly, ExemplarPick& pick )
{
    const auto fin = [ & ]( NodeId i ) -> std::uint32_t { return ( i < fanIn.size() )  ? fanIn[i]  : 0u; };
    const auto ts  = [ & ]( NodeId i ) -> std::uint8_t  { return ( i < tested.size() ) ? tested[i] : std::uint8_t( 0 ); };
    const auto fx  = [ & ]( NodeId i ) -> bool          { return isFixturePath( ing.files[ ing.symbols[i].fileId ] ); };
    const auto better = [ & ]( NodeId cand, NodeId cur ) -> bool   // is `cand` a BETTER exemplar than `cur`?
    {
        const Symbol& a = ing.symbols[cand];  const Symbol& b = ing.symbols[cur];
        const bool candFx = fx( cand ), curFx = fx( cur );
        return
            ( candFx != curFx )           ? ( !candFx && curFx ) :   // INVARIANT 2: non-fixture beats fixture
            ( ts( cand ) != ts( cur ) )   ? ts( cand ) > ts( cur ) :
            ( fin( cand ) != fin( cur ) ) ? fin( cand ) > fin( cur ) :
            ( a.ccx != b.ccx )            ? a.ccx < b.ccx :
            ( a.loc != b.loc )            ? a.loc < b.loc :
                                            a.id  < b.id;             // final id tie-break → deterministic
    };

    pick.candidateCount = 0;
    pick.winner         = kNoNode;
    for( NodeId i = 0; i < ing.symbols.size(); ++i )
    {
        const bool ofKind    = ing.symbols[i].kind == pick.targetKind;
        const bool ineligible = eligibleOnly && ing.symbols[i].ccx > kExemplarCcxCeiling;   // INVARIANT 1
        if( !ofKind || ineligible ) continue;
        ++pick.candidateCount;
        if( pick.winner == kNoNode || better( i, pick.winner ) ) pick.winner = i;
    }
}

// selectExemplar — resolve the target kind, then pick the best-in-class instance by ROLE under the three
// A3-F5 invariants. `fanIn` = in-edge CSR row lengths (reused-count), `tested` = the computeQMetrics flag;
// both indexed by NodeId (short/absent vectors degrade to 0 — no crash). The ccx ceiling is tried FIRST;
// only when nothing of the kind is under it (a corpus of all-blobs) does it relax and flag overCcxBar, so
// the verb still returns SOMETHING rather than an empty result.
inline ExemplarPick selectExemplar( const IngestResult& ing, const Graph& g,
                                    const std::vector<std::uint32_t>& fanIn,
                                    const std::vector<std::uint8_t>&  tested,
                                    std::string_view                  kindOrTask )
{
    ExemplarPick pick;
    if( !resolveExemplarKind( ing, g, kindOrTask, pick ) ) return pick;   // winner stays kNoNode → not-found

    pickWinnerOfKind( ing, fanIn, tested, /*eligibleOnly=*/true, pick );   // pass A: under the ccx ceiling
    if( pick.winner == kNoNode )
    {
        pickWinnerOfKind( ing, fanIn, tested, /*eligibleOnly=*/false, pick );   // pass B: nothing was under it
        pick.overCcxBar = pick.winner != kNoNode;
    }
    return pick;
}

}   // namespace ctxpack

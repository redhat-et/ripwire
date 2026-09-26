#pragma once
// compactlegend.h — the --legend=compact dialect for EVERY XML verb (capture-audit 2026-09-04, lane L7, P1).
//
// WHY ONE LAYER AND NOT SIXTY EDITS. Lens 8 measured the bill: twelve verbs spend >80% of their bytes on the
// legend, the canonical ten-verb edit loop pays 29,824 B of legend per session for ~9 KB of rows, and the
// MCP server re-pays it on every call. --for/--grep/--slice grew a compact dialect by hand (each emitter
// branching on the posture); the other ~60 XML roots are printed by as many emitters. Compact is therefore
// applied HERE, once, to the finished document: the explanatory comments are replaced by ONE legend (schema id +
// the verb's purpose + a reading for every completeness attribute the document actually carries), held to that
// verb's measured byte pin (test/compactlegendcheck.sh pinFor: the pins fit the definitions, docs/METHODOLOGY.md §9),
// the root gains schema="ripwire.<key>/v1", and every payload byte is untouched — rows, root attributes, CDATA
// bodies, and the comments that CARRY DATA (the map header's <!-- files= … -->, pack-task's <!-- body omitted … -->,
// the <!-- +more --> marker, --notes' counted header). The full dialect (--legend=full; the default before L1) never passes
// through this file. Compact is the CLI default since L1 (cli.h kDefaultLegendPosture).
//
// WHAT IS PROSE. A comment is explanatory prose iff it starts with one of kCompactProsePrefixes and none of
// kCompactDataPrefixes — the prefixes are the legend openers the emitters use (`<!-- ripwire <verb>: …`, the
// shared root=/at=/pr_iters=/metrics: blocks). Anything else is data and stays. A comment that already spells
// a `/v1:` schema id is a NATIVE compact legend (for/grep/slice emit their own) and is kept as-is; a root that
// already carries schema= is left alone entirely — the layer never double-compacts.
//
// THE COMPLETENESS VOCABULARY is emitted present-only: a term rides the legend iff the payload carries the
// attribute (or, for a MapHeaderRead term, iff the kept map header carries the field). The counts_floor reading
// keeps floormarkcheck's anchor ("is a FLOOR, never a total") verbatim — one attribute, one reading, in both
// dialects (lane L4's law).
//
// CONSUMERS: main.cpp (CLI — stdout is captured for the run and rewritten once), mcp.h (the textResult
// envelope, under the opt-in `legend:"compact"` argument). Gate: test/compactlegendcheck.sh (U)/(L)/(M)/(D)/(S).

#include <algorithm>
#include <cctype>
#include <charconv>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <string>
#include <string_view>
#include <vector>

#include "infra/Diagnostics.h"   // EXPECTS/ENSURES — the reprice's contract

namespace rw
{


// One entry per XML root the tool emits. `key` is the schema id stem (ripwire.<key>/v1); `purpose` is the reading
// of the verb and of the root vocabulary EVERY answer of that root carries. Its bytes count against the verb's
// per-verb pin in test/compactlegendcheck.sh, and that pin is measured from the definitions, never the reverse.
// Roots shared by several verbs (`r` = the ranked map family, `ctx` = the bundle family) are disambiguated by a
// HINT: main.cpp compactLegendHint reads it off the answer (the root picks the family, then the mark the answering verb
// writes), and mcpverbs.h mcpCompactLegendHint keys it by verb name.
struct CompactLegendSpec
{
    std::string_view rootTag;
    std::string_view key;
    std::string_view purpose;
};

inline constexpr CompactLegendSpec kCompactLegendSpecs[] =
{
    // ── the ranked-map family (root <r>) — hinted by the map-shaping flag that rode along ──
    { "r",   "map",        "ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data" },
    { "r",   "map-diff",   "the ranked map anchored at at=: what the diff touched, the map's row vocabulary" },
    { "r",   "metrics",    "the ranked map with per-symbol metrics: in/out, cx/ccx, loc, params, nest, humps/deep, locals, cbo, amp, tested, ev" },
    { "r",   "around",     "call neighbourhood of of=: depth= hops, fanout= kept per hop; absent rows lie outside that boundary" },
    { "r",   "query",      "lexical-rank map for the query term, the map's row vocabulary" },
    // ── the bundle family (root <ctx>) ──
    { "ctx", "pack-signatures", "the ranked map plus <sigs><d l= n= sc= pure=> signature rows" },
    { "ctx", "pack-top-n", "the ranked map plus <src p=> bodies of the top-N symbols" },
    { "ctx", "skipped",    "why the index lacks a file <f p= why= bytes= limit= ext=>; indexed but unvouched <h p= why= err= err_ratio=>; <lang> census" },
    { "ctx", "notes",      "field notes by target: <target id= dangling=> holds <note d= sha= branch=>; the kept count comment: notes= rows, targets= <target> rows, dangling= targets matching nothing indexed (listed, surfaced nowhere)" },
    { "ctx", "lego",       "ONE interface/base type: <iface n= p= defs= implementors=>, its <m> method contract, every implementor" },
    { "ctx", "expand",     "full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls><c n= l=> resolved callees" },
    // PR #215 review item 9: --expand has TWO servings and they share no element. The line above describes the
    // BUNDLE serving; the whole-file serving is <src p= sym=> with <s n= sc= l=/> anchor rows and no <bodies> at
    // all, so that line described a shape the document does not contain — and was LONGER than the full dialect's
    // own clause, which compactlegendcheck's "compact must shrink" arm reads as the contradiction it is.
    { "ctx", "expand-file", "the file's own text: <src p= sym=>; <s n= sc= l=/> per scoped symbol; full id = p::sc::n" },
    // pack-task (2026-09-12, the lane's end): the bundle's own vocabulary reads here, checked against packtask.h. task= is the task
    // text (a bare --pack-task refuses); <far> is the ranked name-only tier inside <sigs> (renderNameOnlyRows: t= n= p=), of_top=
    // there the ranked rows it was cut from (topRanked); <calls><c> are a body's callee signatures; <callers> rows are the bodies'
    // 1-hop neighbours in either direction, rel= which one, of_top= there the bodies that qualified (bodiesTotal), shared= how many
    // of them a row neighbours (emitted above 1); run= rides a <test> row only when a runner is derivable (testmap.h runHint). The
    // <d> lens facts and route= ride only some answers and are present-only terms below. compactlegendcheck (D36).
    { "ctx", "pack-task",  "one-call task bundle for task= under budget_tokens=: <sigs><d n= sc= l= p=> ranking, <far><s t= n= p=> ranked but over 1 hop out (of_top= ranked rows) > <bodies><b t= n= p= l=> with <calls><c n= l=> callees > <callers><s rel=caller|callee shared=> 1-hop from the bodies (of_top= bodies; shared= bodies reached, absent at 1) > notes > <tests><test p= run=> (run= when derivable)" },
    { "ctx", "from-trace", "trace frames mapped to indexed symbols, innermost first; the innermost in-corpus body included" },
    { "ctx", "exemplar",   "the best-in-class instance of kind= for the task, chosen by role: <exemplar n= p= in= ccx= tested=>, <bodies><b> to imitate" },
    { "ctx-partitions", "pack-task", "N minimally overlapping agent bundles carved along call-graph communities plus one shared core; each <bundle> wraps a <ctx>; bundle role=core|partition i= symbols= modules= bytes= tokens=: one agent's ctx, symbols= ids assigned, bytes= its size; tokens= = est_tokens= = bytes/2.36 (flat, the densest rate; the inner ctx est_tokens= is language-weighted). Inner ctx task= root= budget_tokens= dropped_positive=: the task, p= base, the slice's token target, ranked candidates its budget cut. of_top=: rows ranked (far) / bodies (callers); s rel=caller|callee shared=: 1-hop edge, bodies reached (absent at 1)" },
    // ── navigation ──
    { "callers",     "callers",     "1-hop CALLERS of of= (defs= matched, count= distinct symbols): <s t= n= p=>; hop_tested=/hop_untested=" },
    { "callees",     "callees",     "1-hop CALLEES of of= (defs= matched, count= distinct symbols): <s t= n= p= role= tested=>" },
    { "uses",        "uses",        "resolvable use-sites of of=: <u role=call|macro|read|write|import|extends|type p=file:line in_id=>" },
    // impact (2026-09-12, the fourth sweep): defs=/reaches=/radius_tested=/radius_untested=/importers= ride EVERY answer of this
    // root (the CLI XML and columnar forms and the MCP twin all write them) and were defined only by the full legend, so they read
    // here beside the rows this line already named, present exactly when the root is. Checked against the emitters: reaches= is
    // transitiveCallers( defs ), the defs themselves excluded; radius_tested= counts isTestedByReach, which never counts a test
    // symbol (a seed), so a test in the reach set lands in radius_untested=; importers= is impactImportTier's one-hop set of
    // files whose include/import resolves to a def's file. shown_importers= is a present-only term: the columnar form omits it.
    { "impact",      "impact",      "transitive blast radius of of=: <s t= n= p=> reach set, <f via= p=> importers; defs= matched, reaches= their transitive callers, radius_tested= non-tests an indexed test reaches, radius_untested= the rest; importers= files that #include/import a def's file" },
    { "path",        "path",        "one DIRECTED call path from= to to=, each <s t= n= p=> a hop; reachable=0 hops=0 when none" },
    { "connect",     "connect",     "minimal joining subgraph: <g> groups, <t> terminals, <s connects=> joins, <e f= t=> edges, <unconnected>" },
    { "at",          "at",          "enclosing-definition chain at p=:l=: sym= innermost, chain= outermost-first, <s n= t= l= el=> spans" },
    { "mentions",    "mentions",    "markdown FILES naming of= in backticks (docs=, sections=): <doc p= mentions=>; not a call edge" },
    { "whereis",     "whereis",     "every LOCAL ref whose tree holds sym= (refs_scanned=, blobs=), HEAD first: <hit ref= tip= date= p= l= kind= t=>" },
    { "verify",      "verify",      "ONE structured claim, verdict=confirmed|refuted|unknown, its witness rows <s t= n= p=> inline" },
    { "query",       "graph-query", "graph-query expression over the symbol graph: <s t= n= p=> matching rows" },
    { "match",       "match",       "tree-sitter structural query: <m p= in=> captured nodes with their enclosing symbol; grammars=/eligible_files= the scope" },
    { "grep",        "grep",        "literal/regex scan grouped by file: <f p=><hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan; <unindexed> = off-index" },
    { "exemplar",    "exemplar",    "the best-in-class instance of kind= for the task, chosen by role: n= p= in= ccx= tested=, <bodies><b> to imitate" },
    { "batch",       "batch",       "n= read sub-queries in one sweep (requested=, cap=): each <q> wraps one sub-answer verbatim in CDATA" },
    { "task-route",  "help-task",   "which verb answers this task: status=recommend|abstain confidence= score= margin=, <facts> the evidence" },
    { "slice",       "slice",       "name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth= flow" },
    // ── change / quality ──
    { "edit-check",   "edit-check",   "sym='s contract NOW vs HEAD: status=unchanged|new-symbol|contract-change; <c n= p= incompatible=1 sites_l=> callers" },
    // safe-delete (2026-09-12, the fourth sweep): radius_tested=/radius_untested= ride every answer and read here, by the same
    // isTestedByReach lens as --impact's pair (verbs_navigate.h runSafeDelete), over impact_reaches= instead of reaches=. The
    // sweep's last pass read the rest of that root against runSafeDelete: t= and p= are defs[0]'s, the lowest id
    // resolveAllByNameQualified returns. That is a MATCH, not always a definition (the sweep's design review): on a
    // header-qualified file:name selector the decl→def widening keeps the declarations beside the definitions it adds
    // (graph.h declToDefFollowThrough), and a declaration can hold the lowest id, so the reading names the unit defs= counts.
    // ambiguous_callers= counts callers whose g.ambOut is non-zero; dead_code_candidate=1 needs defs=1, no 1-hop caller,
    // deadCodeEligibleKind (SymKind::Function with a body, not in a .h/.hpp/.hh/.hxx path) and a whole-word `static` inside the
    // signature span (quality.h sourceHasStaticToken).
    { "safe-delete",  "safe-delete",  "can sym= go, a READ never a verdict: callers= impact_reaches= uses= tested_self= risk=; <c n= p= amb=>; radius_tested= non-tests of impact_reaches= an indexed test reaches, radius_untested= the rest; t= p= its lowest-id match's kind and file:line; defs= matched; ambiguous_callers= callers with a call split over several defs; dead_code_candidate=1 only at defs=1 with no caller, for a t=fn with a body, outside .h/.hpp/.hh/.hxx, whose signature spells static (0 never means in use)" },
    { "quality-delta","quality-delta","only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked" },
    { "test-gate",    "test-gate",    "tests <t p= changed= partner= hops= run=> + untested blast radius <u sym= p= l= ccx=>; exit 4 while either exists" },
    { "affected",     "affected",     "test files that transitively reach the changed files/symbols: <test p= partner= hops= run=> in evidence order (order= partners=); seeded_by= the reading taken" },
    { "exercises",    "exercises",    "NON-TEST symbols this test transitively calls (what it covers): <t p= run=>; the inverse of affected" },
    { "pr-context",   "pr-context",   "review bundle per changed file vs base=: symbols, callers, blast radius, tests, owners" },
    { "dmm",          "dmm",          "Delta Maintainability Model base=→target=: dmm= good/(good+bad) units by size_metric=; <p k= dmm= good= bad= d_low= d_high=>" },
    { "handoff",      "handoff",      "continuation packet for the NEXT session: <verified changed= blast_files=>, <tests n=>, <heuristic n= candidates=>, <note>, <doc p=>" },
    { "merge-scout",  "merge-scout",  "cross-branch overlap of arms= refs: <arm ref= base= changed= head_conflicts=>, <pair a= b= conflicts= risks=>, <landing order=>" },
    { "stray-content","stray-content","per local ref, lines/symbols NOT in HEAD: <ref ok= v= base= stray=>; v=unknown = no merge base" },
    { "abi",          "abi",          "contract diff of the indexed symbols between two refs: added/removed/changed signatures" },
    { "plan-lint",    "plan-lint",    "structural lint of a plan document: each finding names the section and the rule" },
    // ── reports ──
    { "hotspots",     "hotspots",     "maintenance pain = churn x ccx over window=: <f p= churn= ccx= score= top= top_ccx= top_l=>; unranked_*= no churn/complexity" },
    { "clones",       "clones",       "similar normalized-token bodies: <group type=2|3 gid= tokens= n= similarity=> of <f n= p=>; dup_loc=/dup_pct=" },
    { "deps",         "deps",         "file-to-file include/import view, heaviest cone first: <f p= afferent= includes= instab= transitive=>, <health>, <godfiles>, <cycles>" },
    { "dead-code",    "dead-code",    "internal-linkage functions with no caller found in the index (not a confidence score): <d n= t= p= l=>; filter= path component" },
    { "lint",         "lint",         "AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>" },
    { "lintcatalog",  "lint-catalog", "the built-in lint rule registry: <rule name= sev= cat= lang= since=>" },
    { "external-surface", "external-surface", "names used but never defined in the index: <x n= lang= refs= calls=>" },
    { "owners",       "owners",       "recency-weighted author ownership (half-life 6mo): <f p= authors= bf= top= share=>; bf=1 = one person holds it" },
    { "cochange",     "cochange",     "files that change together in git: <pair a= b= together= deg= conf_ab= conf_ba= surprising=>, or for of= <f p= together= conf_rev=>" },
    // communities and community (2026-09-12, the fourth sweep): every attribute read below rides EVERY answer of its root
    // (verbs_report.h emitCommunitiesReport / emitCommunityDrill), so its reading lives in the purpose line, present exactly
    // when the root is: the zoom/tree precedent below. Checked against the emitters: bridges= on <communities> counts community
    // PAIRS joined by a cross-community call edge (its <bridge a= b=> rows), one-symbol communities included, so its reading says
    // community where modules= (2+ symbols only) says module (the sweep's design review); on <community> the PEER communities
    // of this one, which that line's partition= clause already counts as modules, singletons included;
    // isolated= counts symbols with neither an in- nor an out-edge, and isolateStats splits it in that precedence (a markdown
    // section, then a bodyless def, then a header file, else source); dir= is the most common member directory, and
    // communityPresentation takes a top-level file's own path as its directory; label= anchors on the member with the highest
    // fan-in, non-accessors first, and appends up to three known leading verbs of member names when any occur; partition= is
    // the community count (ids 0..partition-1, the range --community refuses outside), modules= nonIsolatedModuleCount.
    // The sweep's last pass read the rest of both roots: shown_bridges= is the <bridge> rows printed (min( pairs, 12 ), with
    // bridges_capped= marking a cut) on both; connected_singletons= counts one-symbol communities whose symbol still has an in-
    // or out-edge (isolateStats); symbols= is ing.symbols.size(). The <bridge> row attributes are present-only terms below.
    { "communities",  "communities",  "call-graph modules (Louvain): <community id= size= dir= label=> of <member t= n= p=>; drill= the verb taking a row's id=; shown_modules=/shown_bridges= <community>/<bridge> rows listed; bridges= community pairs joined by a call edge; isolated= symbols with no call edge: isolated_doc= doc sections, isolated_decl= other bodyless, isolated_header= other header defs, isolated_source= the rest; modules= modules of 2+ symbols; connected_singletons= 1-symbol modules with a call edge; symbols= indexed symbols" },
    { "community",    "community",    "ONE module id=: <member t= n= p=> ranked members, its <bridge> edges; size= the TRUE count; dir= its members' most common directory (a top-level file's own path); label= dir::name@file:line:byte of its top fan-in member (non-accessors first) [up to 3 top name verbs]; bridges= modules a call edge joins to it; partition= module count incl. singletons (ids 0..partition-1); modules= those of 2+ symbols; shown_bridges= <bridge> rows listed" },
    // zoom and tree (2026-09-12): symbols=/isolated=/top_modules=/levels_shown= and files= ride EVERY answer of their root and
    // were defined only by the full legend, so they read here beside the levels=/files_unlisted= this line already named.
    // That line moved the (U) --zoom probe's compact legend from 324 to 394 B.
    { "zoom",         "zoom",         "nested module hierarchy: <module level= id= size= dir= shown= capped=> of <member t= n= p=>; levels_shown= of levels= printed; symbols= = isolated= + size= of all top_modules=" },
    { "tree",         "tree",         "each file with its top 3 symbols by rank, files by best symbol: <file p= symbols=> of <s t= n=>; of files= indexed, files_unlisted= have none" },
    { "seams",        "seams",        "cross-directory call edges NO test reaches: <seam from= to= untested= shown= capped=> of <edge caller= p= callee= cp=>" },
    { "doc-drift",    "doc-drift",    "markdown anchors that no longer hold: <doc p=> of <a k= l= c= why= ref= want= got= tgt=>; unchecked/dated rows disclose the rest" },
    { "flags",        "flags",        "BUILT but DARK: <gate name= kind=compile|cmake|env default= dark= regions= loc= reads= p= l=> with <read p= l=> sites" },
    { "skillscan",    "scan-skills",  "injection/exfiltration/path-traversal scan of skill files: files= findings= skipped= verdict=" },
    { "fieldaffinity","field-affinity","fields read together but declared far apart vs 64-byte lines: <s n= p=> structs, <pair a= b= fns= dist=>, <finding k= f= g=>" },
    { "readability",  "readability",  "Posnett/Hindle/Devanbu lens, largest Halstead volume first (a size proxy): <fn p= n= lines= toks= ops= vocab= vol= ent= posnett=>" },
    { "nonlocal_state","nonlocal-state","per function, the non-local MUTABLE state it reaches: <fn p= n= writes= reads=> over <cell n= p= dir= via=> rows" },
    { "ensemble",     "ensemble",     "four orthogonal evidence families joined, ranked by DISTINCT families fired (no composite score): <s p= n= fam= of= fired=>" },
    { "contextratio", "context-ratio","LOCAL-REASONING lens: the share of a unit's context outside its file: <s p= n= sites= ents_out= ent_ratio= read_ratio=>" },
    { "quality_panel","quality-panel","every quality family in ONE report, ranked by distinct families fired: <s p= n= fam= of= fired= join=>; bar_*= thresholds" },
    { "naming-calibration","naming-calibration","naming lint rules scored against this repo's OWN rename history (a noisy proxy): <r n= old= new= fired= proxy=>" },
    { "naming-consistency","naming-consistency","the corpus's case-convention vote per (language, kind): <g lang= kind= style= agree= total=>, <f p= n= propose=> outliers" },
    { "comment_coherence","comment-coherence","two comment/name content measures per documented function, most name-restating first: <fn p= n= c_coeff= cic=>" },
    { "doctor",       "doctor",       "setup health: <c n= ok=> checks; exit 1 when one fails" },
    { "layout",       "layout",       "struct field layout vs cache lines: offsets, padding, hot/cold split candidates" },
    { "arch",         "arch",         "layering rules fit: allowed/denied file-to-file edges, each violation a row" },
    { "flip",         "flip",         "the blast radius of flipping one build gate: the regions and symbols it toggles" },
    { "landing-plan", "landing-plan", "stranded-work landing order across refs, fewest conflicts first" },
    { "pattern",      "pattern",      "structural pattern hits with their enclosing symbol" },
    { "cands",        "candidates",   "flat top-K export for an external reranker: <cand r= s= n= id= k= p= l=><sig>" },
};

// Comment openers that are explanatory prose — replaced under compact. Everything else is data and stays.
inline constexpr std::string_view kCompactProsePrefixes[] =
{
    "<!-- ripwire ",                   // every verb's own legend opener (`<!-- ripwire callers/callees: …`), incl. the
                                       // native compact legends of grep/slice (`<!-- ripwire slice ripwire.slice/v1: …`),
                                       // which this layer restates as its own compact legend; --for's is never routed
                                       // here (main.cpp)
    "<!-- root= ",                     // the shared root-relative-paths block (graphlegend.h)
    "<!-- graph_unindexed=",           // the #66 third-gauge clause where it rides as its OWN comment
                                       // (graphlegend.h graphUnindexedLegendComment — connect/lego/verify/
                                       // nonlocal-state): prose like every other legend sentence, and the
                                       // completeness table below carries its compact reading. Without this
                                       // row the full ~200 B sentence survived into the compact dialect on
                                       // --connect alone, one verb paying full price for a fact the table
                                       // states in a third of the bytes.

    "<!-- notes_degraded=",             // L3 follow-up (CodeRabbit 4053600616): the map/--expand root's standalone
                                       // clause (serialize.h kNotesDegradedComment) — the graph_unindexed= precedent
                                       // exactly. Every OTHER emitter splices the same reading as plain text inside
                                       // its own "<!-- ripwire "-prefixed comment, already covered by that row above.
    "<!-- r:root=",                    // the map header's terse spelling of the same block
    "<!-- pr_iters=",                  // the PageRank convergence block on map-family roots
    "<!-- at= is the git commit",      // the churn/quality provenance block
    "<!-- in=DIR: ",                   // C1-b's scoped-block clause (serialize.h kRecentScopeLegendOpen/Close). Without
                                       // this row the ~640 B prose survived BESIDE the compact terms that restate it,
                                       // and was charged into est_tokens — the same defect the graph_unindexed= row
                                       // above was added for, on the newest conditional clause.
    "<!-- metrics: ",                  // --metrics' per-symbol attribute block
    "<!-- of= is the resolved SEED",   // --around's boundary block
    "<!-- anchoring: ",                // --pr-context=REF's merge-base block
    "<!-- routed: ",                   // the router note
    "<!-- doctor: ",                   // --doctor's legend
    "<!-- rank_by=",                   // --rank-by's k= semantics block
    "<!-- max_tokens=",                // --max-tokens' fit_bytes block
    "<!-- with-profile: ",             // --with-profile's heat_* block
    "<!-- lint nest_refused=",         // --lint's present-only #157 clause (verbs_lint.h); kCompactAttributeReadings'
                                       // lint-keyed nest_refused row restates it. NOT the bare "<!-- nest_refused=":
                                       // --skipped's own clause of that opener is kept in the default dialect.
    "<!-- slice-",                     // slice's seed/flow/since FULL-dialect tiers (slice-seed:/slice-flow:/slice-since:)
    "<!-- root rows: ",                // the multi-root roots table's reading (serialize.h kMultiRootTableLegend, the one
                                       // emitter of this opener); the completeness table's element-qualified label= row
                                       // restates it
    "<!-- multi-root workspace: ",     // the multi-root churn note
    "<!-- hdr:",                       // the map header's ignored_files definition
    "<!-- format=columnar: ",          // the columnar re-serialization block
    "<!-- a body's sibs=",             // --expand's sibs= block
    "<!-- extent_suspect=",            // the extent-honesty row reading (serialize.h kExtentSuspectRowLegend)
    "<!-- b truncated=",               // a cut --expand/pack-task body's reading (serialize.h kTruncatedBodyLegend)
    "<!-- b over_ceiling=",            // …and a past-the-budget one's (serialize.h kOverCeilingBodyLegend)
};

// Comments that share a prose opener and must stay: --for's trailer (est_tokens=/dropped_positive=/weak= are
// spliced into it — estchargecheck A10) and slice-since's native compact block (slicediffcheck 18c pins its
// comparable=0 clause). --notes' counted header is prose (its row readings go) but its COUNTS are kept as data by
// compactKeptLedger (L1 fix round, rv-r1-L1 MED-2).
inline constexpr std::string_view kCompactDataPrefixes[] =
{
    "<!-- root= is the crawl root; p= below is RELATIVE to it",
    "<!-- slice-since ripwire.slice/v1:",
};

// A comment is stripped iff it opens like prose and is not one of the listed data comments.
inline bool isCompactProseComment( std::string_view comment ) noexcept
{
    for( std::string_view keep : kCompactDataPrefixes )
    {
        if( comment.starts_with( keep ) ) { return false; }
    }
    for( std::string_view p : kCompactProsePrefixes )
    {
        if( comment.starts_with( p ) ) { return true; }
    }
    return false;
}

// Where a term is read BESIDES the head: the map header. serialize.h buildStats writes the map's gauges as unquoted
// `name=N` fields of one comment, `<!-- files=… -->`, which this layer keeps as DATA, while the `<!-- hdr:` clauses (and
// the always-on legend's hdr: half) that define those fields are prose and go.
enum class MapHeaderRead : std::uint8_t
{
    No,     // the head (and, with wholeDoc or onTag, the payload) only
    Also,   // the head OR the header: est_tokens= rides the header alone under order=stable, over_ceiling= under max-tokens
    Only,   // the header alone: extent_suspect_syms=, macro_blanked_files=, max_tokens=, external= are DIFFERENT quoted
            // attributes on other verbs (a hotspots row, the skipped root, the for root, a uses row)
};

// The completeness vocabulary: attribute → terse reading. Emitted present-only, in this order. The counts_floor
// reading carries floormarkcheck's BRIEF_ANCHOR verbatim ("is a FLOOR, never a total").
struct CompactCompletenessTerm
{
    std::string_view attr;
    std::string_view reading;
    bool             wholeDoc  = false;   // a ROW-level term (amb=, parse_degraded=, dangling=): read anywhere in the payload
    std::string_view onTag     = {};      // read ONLY on this element and never on the head: label= on the multi-root <root>
                                          // rows is not the label= --communities carries on its first child
    MapHeaderRead    mapHeader = MapHeaderRead::No;
    std::string_view valueItem = {};      // with onTag: read only where that attribute's quoted value LISTS this comma-separated
                                          // item: <cols fields=> naming tested carries the tested column, not every columnar answer
    std::string_view onKey     = {};      // read ONLY on an answer of this schema key (ripwire.<key>/v1): the same NAME on the same
                                          // element means different things on two verbs (<f files=> on context-ratio vs ensemble)
};

// #60: the escaped spelling of the module-scope owner's name, as it reaches a rendered document, and the
// compact reading it pulls in. One constant each so the scan and the sentence cannot drift apart.
inline constexpr std::string_view kModScopeEscapedName = "&lt;file-scope&gt;";
inline constexpr std::string_view kCompactModScopeReading =
    "<file-scope> (t=modscope): a file's MODULE SCOPE — where a top-level call and an anonymous callback "
    "body's calls live; a CALLER, never a callee, with no body to expand";

inline constexpr CompactCompletenessTerm kCompactCompletenessTerms[] =
{
    { "counts_floor",      "counts_floor=1: every count is a FLOOR, never a total" },
    { "graph_ambiguous",   "graph_ambiguous=/graph_unresolved=: resolver gauge" },
    // Issue #66's third gauge, and it needs its OWN row rather than a widening of the one above: the pair is
    // unconditional on a graph-floored root while this one is OMITTED AT ZERO, so folding it into the gauge
    // sentence would define an attribute most documents do not carry. Present-only, like every term here —
    // which is also what kept it invisible: the compact dialect stripped the full clause and had nothing to
    // put back, on every verb, for the whole of v0.6.0.
    { "graph_unindexed",   "graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge" },
    // THE COUNT QUALIFIERS the graph_unindexed row above did not bring along (2026-09-12). Each is absent at zero and
    // its full clause rides only a document that carries it (graphlegend.h declinedCallsLegend( bool ),
    // unprovenDefsLegend( bool ), the callees-only clause of callHierarchyLegendOpen( bool )), so the prose strip removed
    // a definition this table never put back: --callers/--callees/--impact, their columnar forms and the MCP impact
    // default all printed these numbers undefined. test/compactlegendcheck.sh (S) reads every conditional attribute the
    // graphlegend.h family emits from source and fails the next one that lands without a row here.
    // Written to the shortest honest form: every byte counts against the verb's pin, and the callees answer can carry the
    // first two at once.
    { "bodyless_defs",     "bodyless_defs=K: K of defs= have no body, so no callees to read" },
    { "unproven_defs",     "unproven_defs=K: K same-named defs not tied to that file, in no count or row (bare name shows them)" },
    { "declined_calls",    "declined_calls=K: K call sites left unbound (several defs, none chosen), in no count or row" },
    // #220 part 1: the FILE graph's gauge (graphlegend.h importsUnresolvedAttrXml), absent at zero, on the --deps/--arch/
    // --impact roots and the MCP impact twin. What it means for the numbers is the reading BESIDE it, never this row:
    // graph_partial= on --deps/--arch (next row), counts_floor= on --impact (its own row above; importers= only rises).
    { "imports_unresolved", "imports_unresolved=N: N TS/JS imports naming this tree (paths alias, baseUrl path, workspace package) drew no edge" },
    // Its reading on --deps/--arch, the same sentence both full legends carry (graphlegend.h kGraphPartialAttrXml): not a
    // floor, because a missing edge can merge two cycles into one and moves a ratio either way.
    { "graph_partial",     "graph_partial=1: measured over resolved edges; unresolved imports could add, merge or remove cycles and change ratios" },
    // #220 part 2: the resolver's other two root gauges (graphlegend.h tsImportRootAttrXml), absent at zero, --deps/--arch;
    // tsconfig_unread= makes the root partial exactly as imports_unresolved= does (graph_partial= above is its reading).
    { "imports_dts",       "imports_dts=N: N TS/JS imports resolved only to a .d.ts declaration, not source" },
    { "tsconfig_unread",   "tsconfig_unread=N: N tsconfig extends bases not in the tree could declare aliases (graph_partial=1)" },
    // #60: <bodies bodyless=N> — requested symbols with no body BY CONSTRUCTION (a module-scope owner), so
    // capped= stays 0. Absent at zero, like every term here.
    { "bodyless",          "bodyless=N of total=: requested symbols with NO body by construction (t=modscope), never in shown=, never raising capped=", true },
    // --uses=Owner.field's member form (fielduses.h appends kUsesFieldLegend to that answer alone). owner_candidates= is a
    // row attribute that exists only beside member=, so one head term defines the whole form.
    { "member",            "member=Owner.field: rows use that field; pinned=/amb_sites= rows with one owner/with owner_candidates=K; owners_of_name= fields so named" },
    // M21(b) / E1 (2026-09-12): the tests_to_run family's not-derivable disclosure, and the <g> group row it rides
    // once per group. Row-level (every dialect puts it on the row), present-only; the <g> reading is qualified
    // to that element so a document of single rows never pays for it, and a --flags document's own <g> never
    // triggers it (that element carries no run_unknown=).
    //
    // THE COMPACT TERM SAYS WHAT THE FULL CLAUSE SAYS (review of 6621370f). This row is the compact dialect's
    // ONLY reading of <g>, so a reader holding it and nothing else must be able to act on p=. It promised
    // "every path verbatim (&#44; a comma)" — an escape testmap.h no longer emits, because a path holding ','
    // is not grouped at all now — and it never carried the counts-FILES rule the full clause gained with it.
    // So on a comma-path corpus `--affected --legend=compact` told its reader to undo an entity that is not
    // there, and disagreed with the full legend about what a section's shown=/total= counts.
    // The two facts a <g> consumer cannot act without are now stated here in the FULL CLAUSE'S OWN WORDS: a
    // path holding ',' is never grouped, so p= splits into exactly n=; and a shown=/total= over these rows
    // counts test FILES. The compact dialect re-spells rather than quotes — that is what makes it compact, and
    // kRunHintLegendClause is 350+ B against this table's per-verb charge — so the two cannot be ONE constant.
    // test/compactlegendcheck.sh (R) pins them against each other instead: it reads the required phrases OUT
    // OF kRunHintLegendClause and fails the next release where either wording drops one or promises &#44;
    // again. Cost of saying it: the term goes 99 -> 194 B, charged ONLY on a document that carries a <g> row —
    // measured on a six-runner-less-test fixture, `--affected --legend=compact` 501 -> 596 B, and no pinned
    // legend on this tree or on any gate fixture moves at all, because every harness here has a runner.
    { "run_unknown",       "run_unknown=1: no runner derivable (a guess would be worse)", true },
    { "run_unknown",       "<g n= p=a,b,c>: n runner-less rows with equal attrs as ONE row, paths verbatim; a path holding ',' is never grouped, so p= splits into exactly n=; shown=/total= over these rows counts test FILES", true, "g" },
    { "hits_capped",       "hits_capped=1: hits= is a floor" },
    // --regex's long-line disclosure (search.h grepScanText / regexguard.h maxEngineSubjectBytes): the count rides every
    // regex answer, the bound only beside a nonzero count.
    { "regex_lines_skipped", "regex_lines_skipped=N: N lines too long for the regex engine, never matched" },
    // The degrade-disclosure lane's attributes (each set through a DISCLOSE( sink, why ) sink, present only on the degrade,
    // so a clean answer's legend is unchanged). Element-qualified where the name alone is generic.
    { "unread_files",      "unread_files=N: N indexed files unreadable when scanned (hits= is a floor)" },
    { "scan_degraded",     "scan_degraded=1: the scan stopped part-way (hits= is a floor)" },
    { "unreadable",        "unreadable=N: N same-name definitions unreadable when this ran, absent from defs=", false, "layout" },
    { "lines_skipped",     "lines_skipped=N: N sidecar lines unparsed, absent from notes=", false, "notes" },
    { "refused",           "refused=symlink: the sidecar is a symlink, refused unopened: no note was read", false, "notes" },
    { "baseline",          "baseline=symlink-refused: the sidecar is a symlink, refused unopened: every violation is new", false, "arch",
      MapHeaderRead::No, "symlink-refused" },
    { "regex_line_max",    "regex_line_max=: the longest line it could take" },
    { "regex_stack_bytes", "regex_stack_bytes=: the smaller stack every scan thread was held to" },
    // Both also ride the map header: est_tokens= alone there under order=stable (the root drops it), over_ceiling=1 there
    // under max-tokens. Same number, same reading, so one row reads both places.
    { "est_tokens",        "est_tokens=: price as emitted (an upper bound under compact)", false, {}, MapHeaderRead::Also },
    { "over_ceiling",      "over_ceiling=1: budget not met", false, {}, MapHeaderRead::Also },
    // M1 (terminality round A, 2026-09-05): the ranked head's own floor — how many rank>0 candidates the
    // ceiling ladder cut. It rides the root on --for and (since M1) on --pack-task/explore too, so the
    // compact dialect has to define it wherever it appears, or the default answer names a number with no
    // reading. Present-only, like every term here: absent means nothing was dropped.
    { "dropped_positive",  "dropped_positive=N: N ranked candidates cut by the ceiling" },
    // --handoff's withheld= (handoff.h: heuristic rows dropped to fit the budget). Key-qualified since the L1 fix round: the
    // default map's budget gate writes the SAME name on its withheld-map record (<r withheld="1"/>, main.cpp), where it
    // means the whole map was withheld — that record reads kCompactWithheldMapPurpose instead (rv-r1-L1 MED-3).
    { "withheld",          "withheld=: rows the budget cut", false, {}, MapHeaderRead::No, {}, "handoff" },
    { "at",                "at=: commit+dirty+shallow" },
    { "root",              "root=: p= relative to it" },
    // The multi-root roots table (serialize.h writeMultiRootTable): its `<!-- root rows:` clause is prose-stripped above
    // and nothing put the reading back. ELEMENT-qualified, because --communities carries a different label= on its rows.
    { "label",             "<root label= p=>: a workspace root; label= prefixes every p=/id=", true, "root" },
    // THE MAP FAMILY AND --impact (2026-09-12), the same defect a second time. prconverge.h's clause rides as the map's
    // `<!-- pr_iters=` comment and inside every other ranked verb's legend, prose either way, so pr_iters= reached every
    // compact PageRank root undefined (--impact is an (L) loop verb, which is why its reading is this short).
    // pr_converged="0" rides only a ranking that stopped at the iteration cap.
    { "pr_iters",          "pr_iters=N: PageRank iterations" },
    { "pr_converged",      "pr_converged=0: iteration cap hit before convergence" },
    // Form-conditional map roots whose clauses (kRankByDisclosure, kChurnRankLegend, --around's seed block) are prose.
    // window= and defs= are ELEMENT-qualified: --hotspots carries window= and --callers defs=, each meaning something else.
    { "rank_by",           "rank_by=: the ranker behind k=" },
    { "window",            "window=: the git span mined", true, "r" },
    // defs= names resolveFocus's pick (graph.h), and the body preference there holds only IN THE DECLARATION'S SCOPE: a pure
    // virtual beside another class's override keeps the focus. Unconditional, this reading described that answer wrongly
    // (test/decltodefcheck.sh E3g, which also holds the full --around and --connect readings to the same condition).
    { "defs",              "defs=N: of= names N defs; the lowest-id one was walked, a C/C++ body in the same scope over its declaration", true, "r" },
    // The map HEADER's absent-at-zero gauges: `<!-- files=` is kept as data while the `<!-- hdr:` clauses that define
    // these fields go (kDeclinedMapLegend, kIgnoredLegend, kExtentSuspectHdrLegend, kMacroBlankedHdrLegend, the absent-if-0
    // half of the always-on legend, kMaxTokensFitLegend). Header-ONLY: several are quoted attributes elsewhere.
    { "declined",          "declined=K: K calls left unbound (several defs, none chosen)", false, {}, MapHeaderRead::Only },
    { "external",          "external=K: K calls taken as outside the tree, no edge", false, {}, MapHeaderRead::Only },
    { "locality_pinned",   "locality_pinned=K: K calls pinned by locality alone (a guess)", false, {}, MapHeaderRead::Only },
    { "extent_suspect_syms", "extent_suspect_syms=K: K defs failed containment, corpus-wide", false, {}, MapHeaderRead::Only },
    { "macro_blanked_files", "macro_blanked_files=K: K files indexed from a macro-blanked re-parse", false, {}, MapHeaderRead::Only },
    // #157: the map header's own nest-refused gauge (kNestRefusedMapLegend, serialize.h) — same absent-at-zero,
    // header-only shape as its siblings just above.
    { "nest_refused",       "nest_refused=K: K indexed files a pre-parse nesting guard refused (json/yaml/markdown/kotlin)", false, {}, MapHeaderRead::Only },
    { "ignored_files",     "ignored_files=K: K files git's ignore rules dropped", false, {}, MapHeaderRead::Only },
    { "ignored_dirs",      "ignored_dirs=K: K subtrees git's ignore rules pruned, contents unknown", false, {}, MapHeaderRead::Only },
    { "max_tokens",        "max_tokens=/fit_bytes=: tokens asked/the byte cap applied", false, {}, MapHeaderRead::Only },
    { "est_measured",      "est_measured=0: est_tokens is the MODELLED estimate (a charge buffer failed), typically below the emitted size", false, {}, MapHeaderRead::Also },
    { "fit_unmeasured",    "fit_unmeasured=1: the fit probe could not measure the map; the cap is unverified", false, {}, MapHeaderRead::Only },
    // THE THIRD SWEEP (2026-09-12), the same defect on conditional fields the first two sweeps never produced. --zoom's
    // <module children=> rides only a module AT the levels_shown= cut, and a map's <recent> file rows only a single-root
    // rank_by=churn-decay (kChurnDecayRankLegend's `recent:` clause). Both clauses are prose. Both rows are ELEMENT-qualified:
    // of= on the map root is --around's seed, and n= is a name on every <s> row.
    { "children",          "children=K: K child modules below the levels_shown= cut, unprinted", true, "module" },
    { "of",                "<recent n= of=>: the n= newest-touched of of= touched files; <rc age_d=> days since its last commit, w= decayed weight", true, "recent" },
    // merge_bombs_skipped= (2026-09-12): the cut the churn-decay miner makes, disclosed on the block it shapes (gitmine.h
    // kChurnMergeBombMaxFiles). Always on <recent>, "0" included, so the term rides every churn-decay map.
    { "merge_bombs_skipped", "merge_bombs_skipped=N: N commits touching more than 100 INDEXED files skipped, uncounted; a file only they touched is absent; the window's count, so the global block only", true, "recent" },
    // C1-b (2026-09-12): in=DIR — the scoped block (ELEMENT-qualified: scope= rides only a <recent>) and the map stub
    // (stubbed=/would_show= on <symbols> alone; the paging window clause above already reads shown=/capped=). Both
    // present-only. The stub carries NO total=: test/recentscopecheck.sh arm 5a2 fails if it ever does, so the earlier
    // spelling of this comment described behaviour the gate now forbids (#212's review, corrected here).
    { "scope",             "<recent scope=DIR>: a second block riding when the global one does, DIR's files only (p= root-relative); of= is its total; capped=/has_more=/next_offset=/offset=/limit= page it, next= is that page", true, "recent" },
    { "stubbed",           "<symbols stubbed=1 would_show=N next=>: the symbol map in= did not ask for was not rendered; N is that run's own shown= — definitions counted individually as shown= counts them, so its rows follow from rows+sum(overloads-1)=shown (not the header's symbols= corpus count); next= fetches it", true, "symbols" },
    // The map's ROW fields that are absent at their default, defined only inside the always-on `<!-- ripwire v1` legend (prose):
    // lpin= and overloads= on <s>, prov= on <c>. Row-level, because each has one meaning tool-wide and the map emitter is its one
    // XML writer. test/compactlegendcheck.sh (S) population 4 reads that legend's absence-marked row fields from source.
    { "lpin",              "lpin=K: K calls pinned by locality alone (a guess)", true },
    { "overloads",         "overloads=N: N same-name defs merged in this row; shown= counts each", true },
    { "prov",              "prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only", true },
    // THE FOURTH SWEEP (2026-09-12): attributes that ride their documents with no reading here, which the earlier sweeps stopped
    // on at the byte pins. Owner decision: per-verb pins that fit honest definitions (docs/METHODOLOGY.md §9). The unconditional
    // root vocabulary of --impact, --safe-delete, --communities and --community reads in those roots' purpose lines above, and
    // the row here is the PRESENT-ONLY half: shown_importers= is impactImportTier's listed <f> rows, ELEMENT-qualified (only
    // <impact> carries it) and absent from the columnar form, which names the omission in lens=. The sweep also defined the map
    // header's unresolved=, which sums graph.h's unresolvedOut: three sites raise it and none mints an edge (a name defined in
    // the tree whose every def was language-filtered, a shadowed, refused or renamed-unlisted ES import binding, a
    // function-pointer binding with no function target). It had a row of its own until the sweep's design review folded it
    // into the always-on header clause below (the `files` row): buildStats writes it into EVERY map header beside files=, so
    // one clause is present exactly when both fields are, and the header-ONLY read still keeps it off <trace unresolved=>,
    // which counts frames. compactlegendcheck (S) accepts an always-on header field spelled inside that clause.
    { "shown_importers",   "shown_importers=: <f> rows (limit= sizes them)", true, "impact" },
    // cut-fix E (2026-09-24): three cut disclosures that ride only a CUT answer, so each is present-only. importers_next= is
    // graph.h sizeImportTier's call for the whole tier; shown_bridges=/bridges= is --zoom's secondaryCutAttrs on <zoom>
    // (kZoomBridgeCap); shown_symbols= is --tree's on <tree> (kTreeSymbolsPerFile). Their *_capped= siblings read in the
    // shared sub-cap clause.
    { "importers_next",    "importers_next=: the call listing every importer", true, "impact" },
    { "shown_bridges",     "shown_bridges=/bridges=: <bridge> rows printed (the 12 heaviest) / all pairs", false, "zoom", MapHeaderRead::No, {}, "zoom" },
    { "shown_symbols",     "shown_symbols=: <s> rows printed", false, "tree", MapHeaderRead::No, {}, "tree" },
    // THE SWEEP'S LAST PASS (2026-09-12) listed every attribute the compact --impact, --safe-delete, --communities,
    // --community=ID and map-header documents emit and found these still without a reading. Each rides only SOME answers of
    // its root, so each is a present-only term rather than a purpose-line clause. Checked against the emitters:
    //   lazy= (serialize.h emitImportRowsXml) is graph.h scanImporterEdges' allLazy over that importer's edges into the def
    //     files; its full clause is graphlegend.h kImpactImportTierLegend. ELEMENT-qualified on <f>, the importer row.
    //   <bridge> (verbs_report.h): --communities prints a= b= (a (min,max) community pair), from_label=/to_label= (their
    //     communityPresentation labels) and edges=; --community prints to= to_label= edges=; --zoom prints a= b= edges= over
    //     top-module pairs. edges= sums the call edges crossing the pair in both directions on all three. Four terms, because
    //     the attribute SET differs by root and a reading must not name what its row does not carry.
    //   the map header (serialize.h buildStats): files= is ing.files.size(), symbols= ing.symbols.size(), edges= the CSR's
    //     outTargets (graph.h dedupes them per caller, so distinct caller-callee pairs), shown= the kept symbol count (a
    //     merged overload row counts each def, the map legend's own arithmetic), ambiguous= the sum of every symbol's ambOut,
    //     unresolved= (above), order= the stable / important-last / important-last(auto:fill) / important-first choice. Absent
    //     unless it applies: roots= (two or more workspace roots), changed= (--map-diff only, and there even at 0: main.cpp
    //     counts the INDEXED files git reports changed, and a tree git cannot read counts 0 and ranks uniform, as a clean tree
    //     does; the sweep's design review), skipped_oversize=,
    //     unindexed= (ext:count, at most kUnindexedHeaderExts entries) with unindexed_exts= once that list was cut,
    //     escaped_root=, precise= (edges a SCIP index pinned, prov value 1 only). serialize.h records that the FULL map
    //     legend cannot define unindexed=/escaped_root= (tokenbudgetcheck arm #3's seven bytes of floor headroom); a compact
    //     legend replaces more prose than it adds, which compactlegendcheck (U) asserts on every probe, so here they fit.
    //     Header-ONLY: files=, symbols=, edges=, shown= and order= are quoted attributes with other meanings on other roots.
    //   the columnar form (columnar.h kColumnarLegend): format="columnar" on the root, <paths> I=path, <cols n= fields=>.
    //     ELEMENT-qualified on <cols>: --from-trace's <trace format=> names a trace dialect. lens= names what one form of an
    //     answer withholds and another serves: the columnar --impact (shown_importers,importers_capped), --order=stable's
    //     <r> (k,est_tokens), the MCP for dialect (churn,amp,tested). Read on the head, with one meaning on all three.
    { "lazy",              "<f lazy=1>: every edge from that importer into a def file is deferred (in a function/block body, or an autoload), firing only if reached; lazy=0: at least one is load-time", true, "f" },
    { "a",                 "<bridge a= b=>: two module ids joined by call edges", true, "bridge" },
    { "from_label",        "from_label=/to_label=: the label= of a=/b=", true, "bridge" },
    { "to",                "<bridge to= to_label=>: a peer module's id and label=", true, "bridge" },
    { "edges",             "<bridge edges=>: call edges between the two, either direction", true, "bridge" },
    { "files",             "files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (defs all language-filtered, or import/pointer binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable)", false, {}, MapHeaderRead::Only },
    { "roots",             "roots=N: N workspace roots", false, {}, MapHeaderRead::Only },
    { "changed",           "changed=K: K indexed git-changed files seed the PageRank teleport (0: uniform, incl. no git)", false, {}, MapHeaderRead::Only },
    { "skipped_oversize",  "skipped_oversize=K: K files over a size ceiling, not indexed", false, {}, MapHeaderRead::Only },
    { "unindexed",         "unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most)", false, {}, MapHeaderRead::Only },
    { "unindexed_exts",    "unindexed_exts=E: E such extensions in all, the list cut", false, {}, MapHeaderRead::Only },
    { "escaped_root",      "escaped_root=K: K files refused: a symlink led out of the root", false, {}, MapHeaderRead::Only },
    { "precise",           "precise=K: K call edges a SCIP index pinned", false, {}, MapHeaderRead::Only },
    { "fields",            "format=columnar: parallel arrays, not row attributes: <paths> maps I=path, each <cols> array holds n= comma-separated values in one row order, fields= naming them (the path column indexes <paths>; &#44; is a comma)", true, "cols" },
    // THE TESTED COLUMN (2026-09-12, the follow-up to the <s tested=> row below). --callers/--callees/--impact --format=columnar
    // always pass the test-reach lens (verbs_navigate.h), so fields= names tested and columnar.h emitColumnarTestedColumn writes one
    // DENSE value per row: 1 where graph.h isTestedByReach holds, 0 on every other row, a test symbol's row included. A parallel
    // array cannot omit a false entry, so unlike the <s> attribute this prints 0, and an answer over a tree with no test carries a
    // column of zeros: the term reads the COLUMN (a <cols fields=> that lists tested), never a 1. compactlegendcheck (D34)/(D35).
    { "fields",            "<tested> column: 1 = a non-test row an indexed test transitively reaches; 0 = none found, or a test row", true, "cols", MapHeaderRead::No, "tested" },
    { "lens",              "lens=: attributes another form of this answer serves, withheld here" },
    // THE SWEEP'S DESIGN REVIEW (2026-09-12) checked every reading above against its emitter and found one row reading still
    // missing: tested="1" on <s>. --callers/--callees and --impact (verbs_navigate.h), the MCP impact twin (mcpverbs.h) and the
    // map's own rows (serialize.h, whose tested[] column computeQMetrics fills by the same predicate) print it where graph.h
    // isTestedByReach holds: an indexed test transitively reaches that row's symbol and the symbol is not itself a test. Never
    // a literal 0. ELEMENT-qualified on <s>: flipimpact.h's <h tested=> prints 0 as well as 1 and <exemplar tested=> is another
    // root's attribute; a <d> signature row's tested= is the next row's. No earlier sweep saw it because the gate fixture holds
    // no test (compactlegendcheck (D31) builds the smallest tree that prints one).
    { "tested",            "<s tested=1>: a non-test row an indexed test transitively reaches (absent otherwise, never 0)", true, "s" },
    // The same lens on the signature rows (2026-09-12, the follow-up): serialize.h's two <d> row writers print tested="1" from
    // computeQMetrics' tested[] column, which the same isTestedByReach fills, and never a literal 0. main.cpp computes that column
    // only under --metrics, --for or --exemplar, so the reading rides the answers that computed it (--pack-task --metrics; --for
    // keeps its native legend). ELEMENT-qualified on <d>, like the row above: flipimpact.h's <d sym=> and the dead-code <d n=>
    // rows carry no tested=. compactlegendcheck (D33)/(D35).
    { "tested",            "<d tested=1>: a non-test row an indexed test transitively reaches (absent otherwise, never 0)", true, "d" },
    // THE LENS FACTS ON <d> ROWS (2026-09-12, the lane's end). serialize.h sigRowHead writes r= on a lens row (rank > 0), cx=/ccx=
    // under facts.metrics and in= when a fan-in vector was supplied, and packSignatures' lens appends amp= (main.cpp computes it
    // under --metrics; printed above 0). --pack-task passes metrics and supplies its own fan-in, so every one of its <d> rows
    // carries the first four, and --from-trace's do too; their full legends define them in a "Row keys" clause, which is prose and
    // goes. amp= is graph.h's callerCount (direct callers, the in-edge CSR) plus the co-change degree of the symbol's file (the
    // other files sharing a commit with it in git's 18-month window; 0 without git). ELEMENT-qualified on <d>: the map's <s> rows
    // carry the same names under the metrics schema's purpose line, and <exemplar in= ccx=> is another root's. route= (serialize.h
    // ctxRootOpen) rides a bundle whose task was routed to a ranker: --pack-task always, MCP explore unless no_route; it is
    // ELEMENT-qualified on <ctx>. compactlegendcheck (D36)/(D37).
    { "r",                 "<d r=N>: rank N in this ranking, rows in r= order", true, "d" },
    { "ccx",               "<d cx= ccx=>: cyclomatic/cognitive complexity", true, "d" },
    { "in",                "<d in=N>: N callers in the index (absent: not measured)", true, "d" },
    { "amp",               "<d amp=N>: direct callers + files sharing a commit with its file (absent at 0)", true, "d" },
    { "route",             "route=: the ranker: name-exact(X) = the task names symbol X (anchors: its evidence), subtoken+body = conceptual BM25 (:broad = 1-2 plain words, plain rg may also win; :declined(...) = a name hit refused as a common name)", true, "ctx" },
    // row 6 (2026-09-12): the SHORT id on symbol rows. A map <s> row and a lens <d> row carry sc= (the enclosing
    // scope) instead of the path-repeating id=; the reading spells the composition once for every root that
    // prints the rows, since the shared purposes above only name the attribute.
    { "sc",                "sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it", true },
    { "parse_degraded",    "parse_degraded=1: ERROR nodes in that parse", true },
    { "tier_partial",      "tier_partial=1: tier elected under a partial classification" },
    { "dangling",          "dangling=1: matches nothing indexed", true },
    { "amb",               "amb=K: K calls split over several defs", true },
    // A6 (2026-09-06): --connect's join-quality label. connects= is a plain count the purpose line already
    // names; the LABEL is what needs a reading, because a reader who meets hub="1" with no floor beside it
    // cannot tell what it is a label FOR. ONE term, not two: hub_floor= is unconditional on that root, so it
    // always rides and can define hub="1" in the same clause — two terms did not fit the 400 B ceiling, and
    // the ceiling is the point of this dialect. The full legend carries the derivation.
    { "hub_floor",         "hub_floor=D: connects= >= D is hub=1, vacuous" },
    // --lego's contract caveat (serialize.h, on the <iface> row): the attribute pair rides only a NAMED interface whose
    // language's method contract is not read, and no purpose line names it. ELEMENT-qualified, not a head term: the head
    // span holds the full legend comment between <ctx> and its first child, and kLegoLegend spells caveat="…" in it, so
    // a head read fired on every --lego answer (compactlegendcheck (D7) caught it on --lego=Point).
    { "caveat",            "methods=0 caveat=not-extracted-for-lang: no <m> contract read for this language", true, "iface" },
    { "next",              "next=: the one pasteable follow-up", true },
    { "scrubbed",          "scrubbed=1: this CDATA is not the bytes (]]> split or C0 replaced)", true },
    // lane/cutfix-bodies (2026-09-23): a body cut at the byte budget used to say so only INSIDE its CDATA; the cut is now
    // three attributes on the <b> (serialize.h kTruncatedBodyLegend is the full reading). ELEMENT-qualified: pr-context's
    // root truncated= and the doctor/naming-calibration truncated= rows below are other elements' attributes.
    // next= is NOT restated here: the generic next= term above rides every document that carries one (review N1).
    { "truncated",         "<b truncated=1 lines=lo-hi/T>: cut at the byte budget; lines= shown of its T", true, "b" },
    // review M1: a body whose FIRST line alone exceeds the budget is served whole, never as a fragment
    { "over_ceiling",      "<b over_ceiling=1>: its first line alone exceeds the budget, served whole", true, "b" },
    { "preview",           "preview=1: an UNWRITTEN payload; <overwrite l= end= bytes=> = the span an apply replaces, CDATA as on disk (shown=/capped=1/elided_lines= when cut)" },
    { "redacted",          "redacted=1: a credential shape rewritten to [REDACTED:kind]; the no-redact flag serves the bytes", true },
    // extent honesty (serialize.h kExtentSuspectRowLegend): a ROW-level term on the map, <d> and <b> rows alike.
    { "extent_suspect",    "extent_suspect=: span/scope/kind failed containment (name|head|scope|error)", true },
    // L1 (2026-09-19): two honesty attributes the compact dialect carried with NO reading, found when compact became the CLI
    // default and legendcoveragecheck's default-posture rows read every first screen in it (METHODOLOGY §9.4: a floor or a
    // cut is defined where it rides). locals_floor="1" rides a --metrics <s> row whose locals= count is a lower bound
    // (C/C++ only); pr-context's root truncated= names what its trim ladder dropped to fit budget_tokens=, and
    // budget-floor-exceeded means the smallest renderable document is still over it. ELEMENT-qualified, present-only.
    { "locals_floor",      "locals_floor=1: locals= is a floor", true, "s" },
    { "truncated",         "truncated=: what the trim ladder dropped to fit budget_tokens= (budget-floor-exceeded: still over)", false, "pr-context" },
    // train-7 fix round (CodeRabbit on #295): four present-only degrade disclosures whose full clauses ride only the
    // answer that carries them, so the compact strip must put a reading back. Head terms, except head_conflicts_ok=
    // (on each <arm>) and render_failed= (also on the <sigs>/<bodies> element it marks).
    { "disk_walk_failed",  "disk_walk_failed=1: the root could not be listed, so a missing-file row may name an unindexed file that exists" },
    { "refs_dropped",      "refs_dropped=K: K listed branches could not be read, in no count or row" },
    { "head_conflicts_ok", "head_conflicts_ok=0: that arm's base or HEAD tree was unavailable, head_conflicts= unknown", true, "arm" },
    { "render_failed",     "render_failed=: sections whose render FAILED (empty, not budget-omitted)", true },
    // notes.h follow-up round (CodeRabbit 4053600616, declined at train-7, landed here): the ONE marker every
    // notes-surfacing emitter carries — the map, --expand, --for, pack-task, edit-check, handoff, lanes and the
    // MCP verbs. Head term like disk_walk_failed=/refs_dropped= above; --notes itself is unaffected (its own
    // lines_skipped=/refused= rows already have readings, further up this table).
    { "notes_degraded",    "notes_degraded=1: the .ripwire_notes sidecar had unreadable lines or was refused this run (the notes verb's own listing names which)" },

};

// ── EVERY ATTRIBUTE THE DEFAULT EMITS, DEFINED (L1 fix round, rv-r1-L1 HIGH-1) ─────────────────────────────────────────
// A second table beside the completeness vocabulary above: the same row shape and the same present-only rule, but every
// row KEY-qualified (onKey) — the per-verb descriptive readings, where kCompactCompletenessTerms holds the tool-wide
// honesty terms. compactLegendText reads the vocabulary first, then these.
inline constexpr CompactCompletenessTerm kCompactAttributeReadings[] =
{
    // ── EVERY ATTRIBUTE THE DEFAULT EMITS, DEFINED (L1 fix round, rv-r1-L1 HIGH-1) ─────────────────────────────────────
    // L1 made this dialect the CLI default and seeded legendcoverage_default_baseline.txt with 269 first-screen attributes
    // it left undefined — ~25 of them cut/floor/cap terms (renames_window_truncated=, script_gates_unmodelled=, hcut=/rcut=,
    // more files=, unindexed_hits=, defs_per_name_cap= …), which a reader of the default answer then met with no reading.
    // Owner ruling: compact shortens the DICTIONARY, never a meaning. So every one reads here, present-only as ever, and
    // KEY-qualified (onKey): the same name on the same element means different things on two verbs. Each reading was
    // checked against its emitter (the per-verb comment names it) and against the full legend where it has one; the
    // default-posture floor is gone and test/legendcoveragecheck.sh fails on any undefined attribute a default row emits.
    // affected: src/verbs_change.h runAffected (+ src/testmap.h resolveAffectedSeeds/affectedAnswer)
    { "seeds", "seeds=N: symbols the argument matched; only those outside test files seed the caller walk", false, "affected", MapHeaderRead::No, {}, "affected" },
    { "seed_test_files", "seed_test_files=N: matched files that are TESTS; listed to run (seed_kind=test), never walk seeds", false, "affected", MapHeaderRead::No, {}, "affected" },
    { "tests", "tests=N: test files listed to run (the rows)", false, "affected", MapHeaderRead::No, {}, "affected" },
    { "reached", "reached=N: symbols the transitive caller walk reached from the seeds (seeds excluded)", false, "affected", MapHeaderRead::No, {}, "affected" },
    { "script_gates_unmodelled", "script_gates_unmodelled=N: test/*.sh runners; their subprocess reach is unmodelled, never in tests=/reached=", false, "affected", MapHeaderRead::No, {}, "affected" },
    // callees: src/callhierarchy.h computeHopTestedPartition, spliced in src/verbs_navigate.h
    { "hop_tested", "hop_tested=/hop_untested=: count= split by whether an indexed test reaches the row (in-process calls only)", false, "callees", MapHeaderRead::No, {}, "callees" },   // also defines hop_untested=
    // clones: src/verbs_report.h (the <clones> root emit)
    { "groups", "groups=/type3=: Type-2 and Type-3 group totals over all groups; total= is their sum", false, "clones", MapHeaderRead::No, {}, "clones" },   // also defines type3=
    { "exempt_groups", "exempt_groups=N: groups whose members all sit on fixture/shell-runner paths quality-delta duplication ignores", false, "clones", MapHeaderRead::No, {}, "clones" },
    { "idiom_groups", "idiom_groups=/demoted_groups=: groups of one recognized idiom / those quality-delta demotes to minor; floors", false, "clones", MapHeaderRead::No, {}, "clones" },   // also defines demoted_groups=
    { "clone_groups", "clone_groups=N: clusters after merging pairs (rows sharing gid=); a floor under type3_capped=1", false, "clones", MapHeaderRead::No, {}, "clones" },
    { "type3_capped", "type3_capped=1: the Type-3 pair cap fired; later pairs went uncompared, so clone_groups=/dup_loc=/dup_pct= are floors", false, "clones", MapHeaderRead::No, {}, "clones" },
    { "total_loc", "total_loc=N: lines of every function body the detector considered; dup_pct= is dup_loc= over it", false, "clones", MapHeaderRead::No, {}, "clones" },
    // connect: src/mcpverbs.h packConnect (radius from src/graph.h connectSubgraph, clamped 1..12)
    { "nodes", "nodes=N: symbols printed, terminals plus joins (a floor)", false, "connect", MapHeaderRead::No, {}, "connect" },
    { "radius", "radius=N: undirected hop bound searched (default 6, max 12); raise it with connect-radius=N", false, "connect", MapHeaderRead::No, {}, "connect" },
    { "sig", "s sig=: the join symbol's declaration signature; dropped first when a max_tokens ceiling trims", true, "s", MapHeaderRead::No, {}, "connect" },
    // dead-code: src/verbs_quality.h (the <dead-code> root emit)
    { "evidence", "evidence=: the rule every row met, internal linkage and no caller in the index; verify before deleting", false, "dead-code", MapHeaderRead::No, {}, "dead-code" },
    { "register-macro-excluded", "register-macro-excluded=N: symbols skipped as self-registering test/bench macros (TEST, BENCHMARK...); a floor", false, "dead-code", MapHeaderRead::No, {}, "dead-code" },
    // edit-check: src/editcheck.h (the <edit-check> root emit)
    { "defs", "defs=N: overloads at this site (same file, scope, name) folded into one contract; params compared by MAX", false, "edit-check", MapHeaderRead::No, {}, "edit-check" },
    { "shown_unflagged", "shown_unflagged=N: unflagged callers on this page; flagged ones always print, total= counts unflagged only", false, "edit-check", MapHeaderRead::No, {}, "edit-check" },
    // exemplar: src/verbs_for.h + src/exemplar.h selectExemplar/pickWinnerOfKind
    { "candidates", "candidates=N: instances of kind= under the ccx ceiling the pick was ranked from", false, "exemplar", MapHeaderRead::No, {}, "exemplar" },
    { "low_confidence", "low_confidence=1: weak task-to-kind match, fell back to fn; pass a kind (fn|method|class...) instead", false, "exemplar", MapHeaderRead::No, {}, "exemplar" },
    // exercises: src/verbs_change.h runExercises + exercisesHarnessAttr
    { "seed_files", "seed_files=N: test files the pattern matched", false, "exercises", MapHeaderRead::No, {}, "exercises" },
    { "shown_seed_files", "shown_seed_files=N: of those, printed as t rows (at most 20)", false, "exercises", MapHeaderRead::No, {}, "exercises" },
    { "test_symbols", "test_symbols=N: symbols in those test files, the walk's seeds", false, "exercises", MapHeaderRead::No, {}, "exercises" },
    { "reaches", "reaches=N: non-test symbols the tests transitively call (the s rows' total)", false, "exercises", MapHeaderRead::No, {}, "exercises" },
    { "harness", "harness=script|mixed: seeds include shell gates, whose subprocess coverage is unseen; note= says so", false, "exercises", MapHeaderRead::No, {}, "exercises" },   // also defines note=
    // help-task: src/main.cpp runHelpTask
    { "intent", "choice intent= skill= reason=: the route matched, the skill owning it, the evidence in words", true, "choice", MapHeaderRead::No, {}, "help-task" },   // also defines skill= and reason=
    // lint: src/verbs_lint.h (the <lint> root emit)
    { "findings", "findings=N: findings over the printed rules; a floor when findings_capped=1", false, "lint", MapHeaderRead::No, {}, "lint" },
    // map-metrics: src/serialize.h (metrics <s> row, in >= 8)
    { "role", "role=hub: in= is 8 or more", true, "s", MapHeaderRead::No, {}, "metrics" },
    // mentions: src/verbs_navigate.h runMentions
    { "defs", "defs=N: definitions of= resolved to; rows union their doc mentions", false, "mentions", MapHeaderRead::No, {}, "mentions" },
    // naming-consistency: src/namingconsistency.h (the <naming-consistency> root emit)
    { "groups", "groups=N: (language, kind) groups with at least one styled name", false, "naming-consistency", MapHeaderRead::No, {}, "naming-consistency" },
    { "candidates", "candidates=N: multi-token styled names scanned", false, "naming-consistency", MapHeaderRead::No, {}, "naming-consistency" },
    { "decided", "decided=N: groups whose leading style cleared both the sample and agreement floors", false, "naming-consistency", MapHeaderRead::No, {}, "naming-consistency" },
    { "flagged", "flagged=N: off-convention names in decided groups (the f rows)", false, "naming-consistency", MapHeaderRead::No, {}, "naming-consistency" },
    // path: src/verbs_navigate.h (the <path> root emit)
    { "from_p", "from_p=/to_p=: the definitions from= and to= were bound to", false, "path", MapHeaderRead::No, {}, "path" },   // also defines to_p=
    { "from_defs", "from_defs=/to_defs=: definitions of each name, all searched; above 1, qualify file:name", false, "path", MapHeaderRead::No, {}, "path" },   // also defines to_defs=
    // quality-delta: src/verbs_quality.h (root emit) + src/quality.h identityDisclosure
    { "stale", "stale=N: ack ledger rows whose target no longer applies (sa rows); never gating", false, "quality-delta", MapHeaderRead::No, {}, "quality-delta" },
    { "preexisting-worse", "preexisting-worse=N: regressions on symbols that existed at baseline; only these gate (when major)", false, "quality-delta", MapHeaderRead::No, {}, "quality-delta" },
    { "new-symbol", "new-symbol=N: regressions on NEW code; never gate, but the debt is yours: read them", false, "quality-delta", MapHeaderRead::No, {}, "quality-delta" },
    { "register-macro-excluded", "register-macro-excluded=N: symbols kept out of dead-code as self-registering test/bench macros; a floor", false, "quality-delta", MapHeaderRead::No, {}, "quality-delta" },
    { "api-new-surface", "api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=", false, "quality-delta", MapHeaderRead::No, {}, "quality-delta" },
    { "renames", "renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks", false, "quality-delta", MapHeaderRead::No, {}, "quality-delta" },   // also defines rename_window_commits=
    { "acked_by_rename", "acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash", false, "quality-delta", MapHeaderRead::No, {}, "quality-delta" },   // also defines acked_by_content=
    { "renames_window_truncated", "renames_window_truncated=1: history is deeper than the rename window, older renames unread", false, "quality-delta", MapHeaderRead::No, {}, "quality-delta" },
    // readability: src/readability.h (the <readability> root emit)
    { "functions", "functions=N: functions and methods measured (bodyless declarations are not)", false, "readability", MapHeaderRead::No, {}, "readability" },
    // scan-skills: src/skillscan.h printSkillScanArtifact
    { "files", "files=N: files scanned (unscannable ones are skipped=)", false, "skillscan", MapHeaderRead::No, {}, "scan-skills" },
    { "findings", "findings=N: pattern hits; rows print up to 200 (shown= capped=1 past that)", false, "skillscan", MapHeaderRead::No, {}, "scan-skills" },
    { "verdict", "verdict=clean|warn|critical: the worst finding's severity, the same as exit 0/1/2", false, "skillscan", MapHeaderRead::No, {}, "scan-skills" },
    // seams: src/verbs_report.h runStructureText (the seams arm)
    { "modules", "modules=N: directories holding indexed symbols (a module = parent dir)", false, "seams", MapHeaderRead::No, {}, "seams" },
    { "bridges", "bridges=N: cross-directory call edges, tested or not; untested= is those no test reaches", false, "seams", MapHeaderRead::No, {}, "seams" },
    { "test_files", "test_files=N: test files whose calls seed the reach; 0 means every seam reads untested", false, "seams", MapHeaderRead::No, {}, "seams" },
    { "seam_pairs", "seam_pairs=N: directed dir pairs with an untested edge (the seam rows' total)", false, "seams", MapHeaderRead::No, {}, "seams" },
    // test-gate: src/situ.h writeTestGateReport + computeTestGateFor, src/testmap.h buildShellGateIndex
    { "impacted", "impacted=N: symbols that transitively call the change (changed symbols excluded)", false, "test-gate", MapHeaderRead::No, {}, "test-gate" },
    { "shown_tests", "shown_tests=/shown_untested=: t rows and u rows printed, two independent counts", false, "test-gate", MapHeaderRead::No, {}, "test-gate" },   // also defines shown_untested=
    { "script_gates_unmodelled", "script_gates_unmodelled=N: test/*.sh runners in the corpus, a path count; not call-graph modelled", false, "test-gate", MapHeaderRead::No, {}, "test-gate" },
    { "script_gates_registered", "script_gates_registered=N: shell gates test/regression.sh registers as suite members", false, "test-gate", MapHeaderRead::No, {}, "test-gate" },
    { "script_gates_mapped", "script_gates_mapped=N: registered gates with exact dependency evidence (literal paths or RIPWIRE_TEST_DEPS)", false, "test-gate", MapHeaderRead::No, {}, "test-gate" },
    { "script_gates_unresolved_dynamic", "script_gates_unresolved_dynamic=N: registered gates with no mappable deps; they may cover the change unlisted", false, "test-gate", MapHeaderRead::No, {}, "test-gate" },
    { "evidence", "t evidence=script_literal|manifest_declared: why a shell gate joins tests=, its text names the changed path or its RIPWIRE_TEST_DEPS does", true, "t", MapHeaderRead::No, {}, "test-gate" },
    { "ccx_bar", "ccx_bar=N: the cognitive-complexity bar a u row's ccx= is read against", false, "test-gate", MapHeaderRead::No, {}, "test-gate" },
    // rv-test-gate-tsjs F3: untested_modscope=N is ALWAYS present (like the terms above), so the COMPACT
    // (default) legend needs its own reading too — the full-legend clause (situ.h::kUntestedModscopeLegend)
    // is row-gated on N>0 and pays nothing on the compact default otherwise.
    { "untested_modscope", "untested_modscope=N: <file-scope> owners excluded from untested= (#324, uncallable); still in impacted=", false, "test-gate", MapHeaderRead::No, {}, "test-gate" },
    // --flip's twin (CodeRabbit on #331), present-only there: a <file-scope> HOST no test reaches, counted rather than
    // silently left out of untested= (flipimpact.h computeRadius); the hosts row still lists it with tested="0".
    { "untested_modscope", "untested_modscope=N: untested hosts that are a <file-scope> owner (#324, uncallable), left out of untested=; still in hosts=", false, "flip", MapHeaderRead::No, {}, "flip" },
    // uses: src/verbs_navigate.h (the <uses> root emit)
    { "defs", "defs=N: definitions the selector matched; qualify file:name to narrow the call sites", false, "uses", MapHeaderRead::No, {}, "uses" },
    { "external", "external=1: of= has no definition in the indexed tree under any spelling (stdlib/third-party)", false, "uses", MapHeaderRead::No, {}, "uses" },
    // cochange: src/verbs_report.h emitCochangePairs (repo-wide, <cochange pairs=> + <pair>), coPairAttr in src/gitmine.h
    { "pairs", "pairs=N: file pairs with 3+ shared commits in window= (after min_recur), surprising or not", false, "cochange", MapHeaderRead::No, {}, "cochange" },
    { "sub_windows", "sub_windows=N: equal-commit-count slices of window=; the denominator of recur=", false, "cochange", MapHeaderRead::No, {}, "cochange" },
    { "driver", "driver=a|b: the side whose changes best imply the other's, look there first; absent on a tie", true, "pair", MapHeaderRead::No, {}, "cochange" },
    { "recur", "recur=K: slices of sub_windows= the pair co-changed in; 1 = one burst, not a standing coupling", true, "pair", MapHeaderRead::No, {}, "cochange" },
    // cochange-file: src/verbs_report.h runMaintenanceViews, the cfg.cochangeFile branch (<cochange of=> + <f>); sub_windows= row above covers it
    { "commits", "commits=N: this file's own commits in window=; the denominator of deg=", false, "cochange", MapHeaderRead::No, {}, "cochange" },
    { "partners", "partners=N: partner files with 3+ shared commits (after min_recur); the total, rows paged", false, "cochange", MapHeaderRead::No, {}, "cochange" },
    { "recur", "recur=K: slices of sub_windows= the pair co-changed in; 1 = one burst, not a standing coupling", true, "f", MapHeaderRead::No, {}, "cochange" },
    { "dep_capable", "dep_capable=0: a side cannot carry a static dependency (md, json, sh vs C++), so surprising= is undefined", true, "f", MapHeaderRead::No, {}, "cochange" },
    // context-ratio: src/contextratio.h writeContextRatioReport (root element is <contextratio>)
    { "units", "units=N: symbols measured (the s row population)", false, "contextratio", MapHeaderRead::No, {}, "context-ratio" },
    { "file_units", "file_units=N: files measured (the f row population)", false, "contextratio", MapHeaderRead::No, {}, "context-ratio" },
    { "defs_per_name_cap", "defs_per_name_cap=N: most defs one name adds (lowest ids); defs_capped=1 = cut, ents=/rtok= floors", false, "contextratio", MapHeaderRead::No, {}, "context-ratio" },
    { "body_bytes_per_token", "body_bytes_per_token=: the bytes-per-token rate rtok= is estimated at", false, "contextratio", MapHeaderRead::No, {}, "context-ratio" },
    { "shown_syms", "shown_syms=N: symbol rows printed; the rest page with offset=next_offset", false, "contextratio", MapHeaderRead::No, {}, "context-ratio" },
    { "shown_files", "shown_files=N: file rows printed (fixed cap 40, not paged); files_capped=1 = rows dropped", false, "contextratio", MapHeaderRead::No, {}, "context-ratio" },
    { "ents", "ents=N: distinct in-corpus defs its reference sites resolve to, by name (a FLOOR)", true, "s", MapHeaderRead::No, {}, "context-ratio" },
    { "files", "files=N: distinct files holding those defs (a FLOOR)", true, "s", MapHeaderRead::No, {}, "context-ratio" },
    { "files_out", "files_out=N: of files=, those other than the unit's own file", true, "s", MapHeaderRead::No, {}, "context-ratio" },
    { "rtok", "rtok=N: est. tokens of every resolved def, what a reader must read", true, "s", MapHeaderRead::No, {}, "context-ratio" },
    { "rtok_out", "rtok_out=N: the part of rtok= defined outside the unit's own file", true, "s", MapHeaderRead::No, {}, "context-ratio" },
    { "ext", "ext=N: referenced names with no in-corpus def; mostly locals/params, NOT external deps; in neither ratio", true, "s", MapHeaderRead::No, {}, "context-ratio" },
    { "amb_names", "amb_names=N: referenced names with 2+ defs, each counted (per name; not the map's per-call amb=)", true, "s", MapHeaderRead::No, {}, "context-ratio" },
    { "ents", "ents=N: distinct in-corpus defs the file's sites resolve to (a FLOOR; a union, not the sum of s rows)", true, "f", MapHeaderRead::No, {}, "context-ratio" },
    { "files", "files=N: distinct files holding those defs (a FLOOR)", true, "f", MapHeaderRead::No, {}, "context-ratio" },
    { "files_out", "files_out=N: of files=, those other than this file", true, "f", MapHeaderRead::No, {}, "context-ratio" },
    { "rtok", "rtok=N: est. tokens of every resolved def, what a reader must read", true, "f", MapHeaderRead::No, {}, "context-ratio" },
    { "rtok_out", "rtok_out=N: the part of rtok= defined outside this file", true, "f", MapHeaderRead::No, {}, "context-ratio" },
    { "ext", "ext=N: referenced names with no in-corpus def; mostly locals/params, NOT external deps; in neither ratio", true, "f", MapHeaderRead::No, {}, "context-ratio" },
    { "amb_names", "amb_names=N: referenced names with 2+ defs, each counted (per name; not the map's per-call amb=)", true, "f", MapHeaderRead::No, {}, "context-ratio" },
    // deps: src/serialize.h packDeps (<deps files=>, <stabledeps violations=><v from= to= gap=>)
    { "files", "files=N: files with at least one include/import directive; this listing's denominator (health files= = corpus)", false, "deps", MapHeaderRead::No, {}, "deps" },
    { "violations", "violations=N: edges into a file more unstable by over 0.05 (Martin I); only the worst 12 are listed", true, "stabledeps", MapHeaderRead::No, {}, "deps" },
    { "from", "from=: the including file of a stable-deps violation; it depends on the more unstable to=", true, "v", MapHeaderRead::No, {}, "deps" },
    { "gap", "gap=: instab of to= minus instab of from=, project includes only; worst first", true, "v", MapHeaderRead::No, {}, "deps" },
    // doc-drift: src/docdrift.h (root emitted near kDocDriftLegend, <doc-drift docs= clean= ... corpus=>)
    { "docs", "docs=N: markdown docs scanned for anchors; docs minus clean = the doc rows", false, "doc-drift", MapHeaderRead::No, {}, "doc-drift" },
    { "clean", "clean=N: docs with no failed anchor (drift and dated 0); not proof every anchor was checked", false, "doc-drift", MapHeaderRead::No, {}, "doc-drift" },
    { "checked", "checked=N: anchors verified against the index; checked + unchecked = anchors", false, "doc-drift", MapHeaderRead::No, {}, "doc-drift" },
    { "prose", "prose=N: value anchors dropped as prose (name not in code); subtracted from anchors=, never checked", false, "doc-drift", MapHeaderRead::No, {}, "doc-drift" },
    { "corpus", "corpus=N: files the anchors were checked against (index + config/build exts); 0 = no anchor shape, no scan", false, "doc-drift", MapHeaderRead::No, {}, "doc-drift" },
    // ensemble: src/ensemble.h (root, <s><e f= why=>, <f> file rollup)
    { "eligible", "eligible=N: functions and methods with a body, the denominator; ranked + no_family = eligible", false, "ensemble", MapHeaderRead::No, {}, "ensemble" },
    { "no_family", "no_family=N: eligible symbols where no family fired", false, "ensemble", MapHeaderRead::No, {}, "ensemble" },
    { "bar_ccx", "bar_ccx=/bar_loc=/bar_nest=/bar_params=: absolute structural bars: cognitive cx, lines, nesting, params", false, "ensemble", MapHeaderRead::No, {}, "ensemble" },   // also defines bar_loc= bar_nest= bar_params= (one emit, always together)
    { "rcut", "rcut=N: ranks the worst readability decile covers (1 to 40); rrank= inside it fires structural", false, "ensemble", MapHeaderRead::No, {}, "ensemble" },
    { "rmeasured", "rmeasured=N: functions the readability lens measured", false, "ensemble", MapHeaderRead::No, {}, "ensemble" },
    { "hcut", "hcut=N: file ranks the worst churn decile covers (1 to 40); hrank= inside it fires historical", false, "ensemble", MapHeaderRead::No, {}, "ensemble" },
    { "hranked", "hranked=N: files with any in-window commit; 0 = historical family unavailable", false, "ensemble", MapHeaderRead::No, {}, "ensemble" },
    { "cfiles", "cfiles=N: indexed files the confusion (atom) pack can read: C/C++/ObjC/CUDA", false, "ensemble", MapHeaderRead::No, {}, "ensemble" },
    { "cscope", "cscope=N: eligible symbols in those files; 0 = confusion family unavailable", false, "ensemble", MapHeaderRead::No, {}, "ensemble" },
    { "lscope", "lscope=N: eligible symbols in a language the naming pack reads; 0 = lexical family unavailable", false, "ensemble", MapHeaderRead::No, {}, "ensemble" },
    { "shown_syms", "shown_syms=N: symbol rows printed; the rest page with offset=next_offset", false, "ensemble", MapHeaderRead::No, {}, "ensemble" },
    { "shown_files", "shown_files=N: file rows printed (fixed cap 20, not paged); files_capped=1 = rows dropped", false, "ensemble", MapHeaderRead::No, {}, "ensemble" },
    { "f", "e f=: the fired family: structural, lexical, confusion or historical", true, "e", MapHeaderRead::No, {}, "ensemble" },
    { "why", "why=: the measurements that crossed, space separated; rule*N = that rule fired N times", true, "e", MapHeaderRead::No, {}, "ensemble" },
    { "top", "top=: the file's most corroborated symbol (most families on one symbol)", true, "f", MapHeaderRead::No, {}, "ensemble" },
    { "top_l", "top_l=: that symbol's line", true, "f", MapHeaderRead::No, {}, "ensemble" },
    { "top_fam", "top_fam=N: families fired on top=, the stronger claim; file rows rank by it", true, "f", MapHeaderRead::No, {}, "ensemble" },
    { "union_fam", "union_fam=N: distinct families firing anywhere in the file (weaker: may be different symbols)", true, "f", MapHeaderRead::No, {}, "ensemble" },
    { "union", "union=: the names of those families", true, "f", MapHeaderRead::No, {}, "ensemble" },
    { "syms", "syms=N: symbols in the file where at least one family fired", true, "f", MapHeaderRead::No, {}, "ensemble" },
    // grep: src/verbs_grep.h (root emit, grepTierAttrs, grepUnindexedAttrs, emitGrepEncRows)
    { "pattern", "pattern=: the search string as given", false, "grep", MapHeaderRead::No, {}, "grep" },
    { "files", "files=N: in-index files holding hits (the whole collected set, same on every page)", false, "grep", MapHeaderRead::No, {}, "grep" },
    { "suppressed_comment", "suppressed_comment=N: comment-tier hits held back, not in hits=; the grep-in=any flag serves them", false, "grep", MapHeaderRead::No, {}, "grep" },
    { "suppressed_string", "suppressed_string=N: string-tier hits held back, not in hits=; the grep-in=any flag serves them", false, "grep", MapHeaderRead::No, {}, "grep" },
    { "tier_parsed", "tier_parsed=N: hit files parsed to classify hits as code/comment/string (budgeted; see tier_budget=)", false, "grep", MapHeaderRead::No, {}, "grep" },
    { "tier_unclassified", "tier_unclassified=N: hits in files never classified; nonzero = tier label unproven for them", false, "grep", MapHeaderRead::No, {}, "grep" },
    // cut-fix lane D: three attributes the grep root and rows emit that the compact dialect never read. tier_parsed='s own
    // reading pointed at tier_budget= ("see tier_budget=") and no row defined it; tier= labelled a comment-only answer
    // undefined; and line_bytes= — the one disclosure that a row's matched text was CUT (search.h kGrepMatchedLineMaxBytes)
    // — reached a compact reader as a bare number. Present-only, like every term here.
    { "tier", "tier=: the span tier served when no hit is code: comment, string or comment+string", false, "grep", MapHeaderRead::No, {}, "grep" },
    { "tier_budget", "tier_budget=: files|bytes cap hit after tier_parsed= of tier_files= hit files; tier counts floors, every row served", false, "grep", MapHeaderRead::No, {}, "grep" },
    { "line_bytes", "line_bytes=N: whole line N bytes; text is a cut prefix", true, "hit", MapHeaderRead::No, {}, "grep" },
    { "unindexed_files_scanned", "unindexed_files_scanned=N: off-index text files also scanned; outside complete=", false, "grep", MapHeaderRead::No, {}, "grep" },
    { "unindexed_hits", "unindexed_hits=N: hits in off-index files, NOT in hits=/total=; listed in the trailing unindexed element", false, "grep", MapHeaderRead::No, {}, "grep" },
    { "callers", "callers=N: 1-hop distinct callers of this name, all same-named defs (a FLOOR)", true, "enc", MapHeaderRead::No, {}, "grep" },
    { "cx", "cx=N: cyclomatic complexity, max over same-named defs; absent when 0", true, "enc", MapHeaderRead::No, {}, "grep" },
    // layout: src/layout.h writeLayout / writeLayoutDef
    { "sym", "sym=: the aggregate name asked for", false, "layout", MapHeaderRead::No, {}, "layout" },
    { "found", "found=1: a C-family struct/class/union body was located for sym=", false, "layout", MapHeaderRead::No, {}, "layout" },
    { "defs", "defs=N: same-name aggregate defs found; a more element counts any not shown", false, "layout", MapHeaderRead::No, {}, "layout" },
    { "mirror", "mirror=: single|match|mismatch (byte drift, exits nonzero)|stub|spelling, over same-name defs", false, "layout", MapHeaderRead::No, {}, "layout" },
    { "asserts", "asserts=N: static_assert tripwires in indexed files that mention sym=", false, "layout", MapHeaderRead::No, {}, "layout" },
    { "conflicts", "conflicts=N: asserts contradicting the computed size (agree=0 rows); nonzero exits nonzero", false, "layout", MapHeaderRead::No, {}, "layout" },
    { "scanned", "scanned=N: indexed C-family files read for asserts", false, "layout", MapHeaderRead::No, {}, "layout" },
    { "agg", "agg=: struct, class or union", true, "def", MapHeaderRead::No, {}, "layout" },
    { "fields", "fields=N: member rows listed", true, "def", MapHeaderRead::No, {}, "layout" },
    { "modeled", "modeled=0: size/align/tail pad not computed; off= only up to the first unknown", true, "def", MapHeaderRead::No, {}, "layout" },
    { "ty", "ty=: the field type as written, before macro expansion (as= gives the expansion)", true, "f", MapHeaderRead::No, {}, "layout" },
    { "sz", "sz=N: field bytes incl. array extent (LP64 model); sized=0 instead when unknown", true, "f", MapHeaderRead::No, {}, "layout" },
    { "al", "al=N: field alignment in bytes (LP64 model)", true, "f", MapHeaderRead::No, {}, "layout" },
    { "off", "off=N: computed byte offset; absent after an earlier field of unknown size", true, "f", MapHeaderRead::No, {}, "layout" },
    { "d", "d=: caveat detail: the first site this kind fired on, or a plain description", true, "caveat", MapHeaderRead::No, {}, "layout" },
    { "count", "count=N: member sites this one caveat row stands for (absent = 1)", true, "caveat", MapHeaderRead::No, {}, "layout" },
    // merge-scout: src/mergescout.h writeScoutArm / root emit
    { "head", "head=: the HEAD commit, bare 9-hex sha (at= adds +dirty)", false, "merge-scout", MapHeaderRead::No, {}, "merge-scout" },
    // TRAIN 9 (L1 x t9-mergescout): the lane put both ok= postures and reason= in the FULL prose legend, which was
    // the default when it was written. L1 makes compact the default, so the same two facts read here. ok="1" needs
    // saying out loud because the whole point of that lane is that a legally EMPTY comparison is a real ok="1" with
    // changed="0", not a refusal; reason= is present only on a refusal, so its reading is too.
    { "ok", "ok=1 on an arm row means the comparison RAN, so changed=/head_conflicts= are real and may legitimately be 0 (an empty but materialized tree is a real index); ok=0 means it did not run at all", true, "arm", MapHeaderRead::No, {}, "merge-scout" },
    { "reason", "arm reason= (only with ok=0): reason=no_merge_base (no merge base with HEAD) or reason=tree_unavailable (a side's tree could not be materialized or ingested)", true, "arm", MapHeaderRead::No, {}, "merge-scout" },
    { "note", "no-work note=: arm compared and has no divergent work vs its merge base, so no landing slot", true, "no-work", MapHeaderRead::No, {}, "merge-scout" },
    // t14-cleanup #1: <sym anchoring="file-level"> (mergescout.h writeSymRows) had no compact-posture
    // definition at all — invisible until a roster run's own working-tree arm happened to touch a
    // file with zero real-body symbols (a doc/test-only diff), which is common and not an edge case.
    { "anchoring", "anchoring=file-level: a whole-file fallback row for a file with no real-body symbols, counted like any other changed file, just not attributed to one inside it", true, "sym", MapHeaderRead::No, {}, "merge-scout" },
    // owners: src/verbs_report.h (CLI owners emitter near the <owners files=> comment); <uniform/> fold
    { "files", "files=N: files analysed", false, "owners", MapHeaderRead::No, {}, "owners" },
    { "files", "files=N: single-author files folded into this one row; detail=1 lists each", true, "uniform", MapHeaderRead::No, {}, "owners" },
    // pack-task: src/serialize.h pureFromSig + the impure lens (pureSig at the <d> row emitters)
    { "pure", "pure=1: const/constexpr signature (Swift: non-mutating) and no transitive side effect found; a hint", true, "d", MapHeaderRead::No, {}, "pack-task" },
    // pr-context: src/prcontext.h (prAnchorAttr, prDirectionAttr, root tail format, per-file impact/cochange/owners, no-ref-work)
    { "anchor", "anchor=merge-base: diffed from merge base(base, HEAD); ref-tip-two-dot = no merge base, two-dot view", false, "pr-context", MapHeaderRead::No, {}, "pr-context" },
    { "base_sha", "base_sha=: the merge-base commit (9 hex) the diff is anchored at", false, "pr-context", MapHeaderRead::No, {}, "pr-context" },
    { "base_moved", "base_moved=N: paths the base ref changed since the fork that this work never touched; excluded", false, "pr-context", MapHeaderRead::No, {}, "pr-context" },
    { "direction", "direction=: side reviewed: worktree-since-head, head-since-fork or head-since-ref-tip", false, "pr-context", MapHeaderRead::No, {}, "pr-context" },
    { "skipped_mode_only", "skipped_mode_only=N: mode-only (chmod) diffs left out of the changed files; renames stay in", false, "pr-context", MapHeaderRead::No, {}, "pr-context" },
    { "trim_level", "trim_level=0-4: trim ladder step taken to fit budget_tokens= (0 none, 4 counts only); raise token-budget", false, "pr-context", MapHeaderRead::No, {}, "pr-context" },
    { "budget_default", "budget_default=1: the default 8000-token budget applied (no token-budget or max-tokens given)", false, "pr-context", MapHeaderRead::No, {}, "pr-context" },
    { "commits", "commits=N: this file's commits in window=; 0 = the window could not look, not no partners", true, "cochange", MapHeaderRead::No, {}, "pr-context" },
    { "partners", "partners=N: co-change partners NOT in the diff; rows are its top shown= (the cochange verb lists all)", true, "cochange", MapHeaderRead::No, {}, "pr-context" },
    { "dependents", "dependents=N: distinct symbols transitively calling this file's symbols (reach set, a FLOOR)", true, "impact", MapHeaderRead::No, {}, "pr-context" },
    { "files_other", "files_other=N: non-changed files among those reached; the f rows are its top shown=", true, "impact", MapHeaderRead::No, {}, "pr-context" },
    { "authors", "authors=N: distinct authors of this file (0 = no git data)", true, "owners", MapHeaderRead::No, {}, "pr-context" },
    { "bf", "bf=1: one author holds over 80% of recency-weighted commits (bus-factor risk)", true, "owners", MapHeaderRead::No, {}, "pr-context" },
    { "note", "no-ref-work note=: the base ref's tip is the merge base, so it has no work of its own; rows are HEAD's", true, "no-ref-work", MapHeaderRead::No, {}, "pr-context" },
    // stray-content: src/crossref.h writeStrayContentPage / writeStrayRef / writeStrayFile
    { "head", "head=: the HEAD commit, bare 9-hex sha (at= adds +dirty)", false, "stray-content", MapHeaderRead::No, {}, "stray-content" },
    { "head_ref", "head_ref=: HEAD's branch (HEAD when detached); that branch itself is not scanned", false, "stray-content", MapHeaderRead::No, {}, "stray-content" },
    { "refs", "refs=N: local branches scanned (refs/heads only); unmerged + superseded + merged + unknown = refs", false, "stray-content", MapHeaderRead::No, {}, "stray-content" },
    { "blobs", "blobs=N: distinct git blobs read for the sweep", false, "stray-content", MapHeaderRead::No, {}, "stray-content" },
    { "unmerged", "unmerged=N: refs whose authored work the live line genuinely lacks", false, "stray-content", MapHeaderRead::No, {}, "stray-content" },
    { "superseded", "superseded=N: refs whose work the live line re-implemented (removed the same base code)", false, "stray-content", MapHeaderRead::No, {}, "stray-content" },
    { "merged", "merged=N: refs whose work HEAD already has; omitted from the rows", false, "stray-content", MapHeaderRead::No, {}, "stray-content" },
    { "name", "name=: the local branch", true, "ref", MapHeaderRead::No, {}, "stray-content" },
    { "tip", "tip=: the branch tip commit (9 hex)", true, "ref", MapHeaderRead::No, {}, "stray-content" },
    { "date", "date=: the tip's committer date, YYYY-MM-DD", true, "ref", MapHeaderRead::No, {}, "stray-content" },
    { "files", "files=N: files with stray lines; rows capped at 12, a more element counts the rest (detail=1 lists all)", true, "ref", MapHeaderRead::No, {}, "stray-content" },
    { "superseded", "ref superseded=N>: of this ref's stray= lines, those in files the live line re-implemented", true, "ref", MapHeaderRead::No, {}, "stray-content" },
    { "authored", "authored=N: lines this ref authored in the file vs its merge base", true, "file", MapHeaderRead::No, {}, "stray-content" },
    { "del", "del=N: base lines this ref removed (0 = pure addition)", true, "file", MapHeaderRead::No, {}, "stray-content" },
    { "redone", "redone=N: of del=, the base lines HEAD removed too (the supersession evidence)", true, "file", MapHeaderRead::No, {}, "stray-content" },
    { "sim", "sim=: minhash containment, 0 to 1, of the ref's blob in HEAD's (pure-addition evidence)", true, "file", MapHeaderRead::No, {}, "stray-content" },
    { "head-touched", "head-touched=1: the live line changed this path since the merge base", true, "file", MapHeaderRead::No, {}, "stray-content" },
    { "files", "more files=N: N more file rows of this ref withheld; shown + N = the ref's files=; detail=1 lists all", true, "more", MapHeaderRead::No, {}, "stray-content" },
    // whereis: src/crossref.h writeWhereisPage (root emit, trailing <more hits=>)
    { "hits", "hits=N: occurrences in HEAD plus every scanned local ref's full tree (the total rows)", false, "whereis", MapHeaderRead::No, {}, "whereis" },
    { "on-head", "on-head=1|0: whether HEAD's tree holds it; 0 beside hits = it lives only on a branch", false, "whereis", MapHeaderRead::No, {}, "whereis" },
    { "head_labels", "head_labels=index: HEAD kind= from the parsed index; lexical: text heuristic (non-HEAD rows always are)", false, "whereis", MapHeaderRead::No, {}, "whereis" },
    { "hits", "more hits=N: rows after this page; page on with offset=next_offset", true, "more", MapHeaderRead::No, {}, "whereis" },
    // the GREY ZONE of the same sweep: attributes the compact prose named in passing ("in/out, cx/ccx", "<g> groups") but never
    // DEFINED as name= — legendcoveragecheck's default rows hold the definitional predicate, so each gets its reading here.
    // affected: src/verbs_change.h runAffected
    { "changed", "changed=: the files/symbols argument as given", false, "affected", MapHeaderRead::No, {}, "affected" },
    // connect: src/mcpverbs.h packConnect
    { "terminals", "terminals=/groups=/edges=: task symbols resolved, connected groups (g), e edges printed", false, "connect", MapHeaderRead::No, {}, "connect" },
    // dead-code: src/verbs_quality.h — T13/fix1: confidence="high" removed (a claim the code did not
    // support); count= still needs its own reading now that the confidence row is gone.
    { "count", "count=N: candidates meeting evidence= (a floor)", false, "dead-code", MapHeaderRead::No, {}, "dead-code" },
    // doc-drift: src/docdrift.h
    { "drift", "drift=/dated=: anchors that no longer hold / anchors skipped as dated (unverifiable by date)", false, "doc-drift", MapHeaderRead::No, {}, "doc-drift" },
    // edit-check: src/editcheck.h
    { "callers", "callers=N: callers of sym= (the c rows' total; a floor)", false, "edit-check", MapHeaderRead::No, {}, "edit-check" },
    // ensemble: src/ensemble.h
    { "families", "families=N: evidence families joined; ranked=N: symbols at least one fired on; window=: the git span the historical family read", false, "ensemble", MapHeaderRead::No, {}, "ensemble" },
    // exercises: src/verbs_change.h runExercises
    { "of", "of=: the test file pattern given", false, "exercises", MapHeaderRead::No, {}, "exercises" },
    // external-surface: src/verbs_navigate.h
    { "names", "names=N: distinct external names (the x rows' total)", false, "external-surface", MapHeaderRead::No, {}, "external-surface" },
    // metrics: src/serialize.h (the metrics <s> row)
    { "cx", "s in= out= cx= ccx= loc= params= nest= cbo= amp=: callers, callees, cyclomatic/cognitive complexity, lines, parameters, nesting depth, coupled types, callers + co-changed files", true, "s", MapHeaderRead::No, {}, "metrics" },
    // pr-context: src/prcontext.h
    { "files", "files=N: changed files in the diff (shown= of them listed)", false, "pr-context", MapHeaderRead::No, {}, "pr-context" },
    { "symbols", "file symbols=: indexed symbols in that changed file", true, "file", MapHeaderRead::No, {}, "pr-context" },
    { "count", "changed-symbols count= / tests count=: that section's full count (shown= of it listed)", true, "changed-symbols", MapHeaderRead::No, {}, "pr-context" },
    { "count", "tests count=: test files reaching this file (shown= of them listed)", true, "tests", MapHeaderRead::No, {}, "pr-context" },
    { "files", "impact files=: files holding the transitive callers (dependents=)", true, "impact", MapHeaderRead::No, {}, "pr-context" },
    { "deps", "impactf deps=: transitive callers in that file", true, "f", MapHeaderRead::No, {}, "pr-context" },
    // quality-delta: src/verbs_quality.h
    { "surface", "r surface=: the api-surface tier, new-symbol or contract-change", true, "r", MapHeaderRead::No, {}, "quality-delta" },
    // test-gate: src/situ.h writeTestGateReport
    { "tests", "tests=/untested=: tests to run (t total) / impacted symbols no test reaches (u total)", false, "test-gate", MapHeaderRead::No, {}, "test-gate" },
    // uses: src/verbs_navigate.h
    { "count", "count=N: use-site rows in all (a floor)", false, "uses", MapHeaderRead::No, {}, "uses" },
    { "run", "test run=: the command that runs that test file (run_unknown=1: none derivable)", true, "test", MapHeaderRead::No, {}, "pr-context" },
    // …and the fixture states compactlegendcheck (UG) reaches: every XML flag of the universe, every instance.
    // hotspots: src/verbs_report.h (the <hotspots> root emit)
    { "files", "files=/ranked=: files in the window / those with both churn and complexity; ranked + unranked_no_churn + unranked_no_complexity = files", false, "hotspots", MapHeaderRead::No, {}, "hotspots" },   // also defines ranked=
    { "unranked_no_churn", "unranked_no_churn=/unranked_no_complexity=: files left out for no commit in window= / no measured complexity", false, "hotspots", MapHeaderRead::No, {}, "hotspots" },   // also defines unranked_no_complexity=
    // naming-consistency: src/namingconsistency.h
    { "why", "g why=insufficient-sample|no-clear-convention: which bar a style=UNAVAILABLE group missed", true, "g", MapHeaderRead::No, {}, "naming-consistency" },
    // quality-delta: src/verbs_quality.h (root)
    { "acked", "acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating", false, "quality-delta", MapHeaderRead::No, {}, "quality-delta" },
    // path: src/verbs_navigate.h (the no-path hint)
    { "hint", "hint=: what to try when no directed path exists (connect for a shared caller, uses/impact for non-call references)", false, "path", MapHeaderRead::No, {}, "path" },
    // connect: src/mcpverbs.h packConnect (terminal rows)
    { "defs", "t defs=N: that terminal name has N defs in the index; all were searched (above 1, qualify file:name)", true, "t", MapHeaderRead::No, {}, "connect" },
    // grep: src/verbs_grep.h (the enc row's def count)
    { "defs", "enc defs=N: the enclosing name has N defs, the row unions them (only above 1)", true, "enc", MapHeaderRead::No, {}, "grep" },
    // owners: src/verbs_report.h (the of= form)
    { "of", "of=/defs=: the symbol asked for and how many defs it resolved to; rows are the files holding them", false, "owners", MapHeaderRead::No, {}, "owners" },   // also defines defs=
    // doc-drift: src/docdrift.h
    { "filter", "filter=: the path filter this run was narrowed to; docs outside it were not checked", false, "doc-drift", MapHeaderRead::No, {}, "doc-drift" },
    // whereis: src/crossref.h (the exhaustiveness claim)
    { "complete", "complete=1: the scan read every ref AND this page lists every hit (absent: one of the two is a floor)", false, "whereis", MapHeaderRead::No, {}, "whereis" },
    // plan-lint: src/planlint.h
    { "file", "file=/dialect=: the plan read and whether the PLAN dialect was detected (dialect=0: nothing to lint)", false, "plan-lint", MapHeaderRead::No, {}, "plan-lint" },   // also defines dialect=
    { "cards", "cards=/ledger=: card rows found / whether the doc carries a ledger (ledger_line= names its line)", false, "plan-lint", MapHeaderRead::No, {}, "plan-lint" },   // also defines ledger=
    { "git", "git=1: git was available, so the staleness read ran; stale_commits=N: a waiting card N commits behind HEAD is stale", false, "plan-lint", MapHeaderRead::No, {}, "plan-lint" },   // also defines stale_commits=
    { "gating", "gating=N: findings that fail the plan (exit 2); the rest are advisory", false, "plan-lint", MapHeaderRead::No, {}, "plan-lint" },
    // field-affinity: src/fieldaffinity.h (the named-struct form)
    { "sym", "sym=: the struct asked for; only its own fields and pairs are reported", false, "fieldaffinity", MapHeaderRead::No, {}, "field-affinity" },
    // layout: src/layout.h (the modeled definition row)
    { "size", "def size=/align=/tail_pad=: computed bytes, alignment, trailing padding (modeled=1 only)", true, "def", MapHeaderRead::No, {}, "layout" },   // also defines align= tail_pad=

    // ── round 2 of the fix (rv-r1-L1-2): the verbs and states the first roster did not reach — doctor, quality-panel,
    //    naming-calibration, dmm, comment-coherence, help-task facts.
    // doctor: src/verbs_doctor.h runDoctor / doctorIndexCacheRow / doctorGitConfigTrustAttrs / doctorLayoutCheck / doctorAgentRows
    { "n", "n=: the check's name (binary-path, grammars, cache-dir, git, tree-sitter, index-cache, layout ...)", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "agent", "agent=: the agent named by the agent flag; its live-integration c rows follow the built-in checks", false, "doctor", MapHeaderRead::No, {}, "doctor" },
    { "copied", "copied=1: the PATH binary is a byte-identical copy of this one, an ok copied install", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "loaded", "loaded=/expected=: grammars whose tags query compiled / grammars compiled in; a shortfall fails the row", true, "c", MapHeaderRead::No, {}, "doctor" },   // also defines expected=
    { "dir", "dir=: the per-user cache directory scanned (TMPDIR/XDG_CACHE_HOME ladder); unwritable fails the row", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "blobs", "blobs=N: ripwire cache blobs in dir=; the scan stops at 4096 (blobs_floor=1 then)", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "blobs_floor", "blobs_floor=1: the 4096-blob scan cap fired; blobs= and bytes= are FLOORS, not totals", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "bytes", "bytes=N: total size in bytes of the blobs counted (short when truncated=1)", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "many", "many=1: more than 50 blobs; an eviction-sanity flag, informational, never fails the row", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "truncated", "truncated=1: cache-dir, blob scan cut (cap or I/O error); tracked-binaries, scan SKIPPED, stale=0 unmeasured", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "locks", "locks=N: advisory edit-lock files under locks/; unheld ones over a day old are swept on a cache write", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "volatile", "volatile=: this row's attributes that read LIVE machine state; a determinism diff strips them, never the row", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "git", "git=0|1: git runs from PATH; 0 fails the row (churn verbs need it)", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "repo", "repo=0|1: the root is inside a git work tree; 0 is a diagnosis, not a failure", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "history", "history=0|1: the repo has at least one commit; head= prints only when it does", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "head", "head=: HEAD's short sha (9 hex, the at= width)", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "shallow", "shallow=1: a depth-limited clone; every churn number counts only the commits present", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "core_abi", "core_abi=/cpp_grammar_abi=: tree-sitter core language ABI / the C++ grammar's ABI; informational", true, "c", MapHeaderRead::No, {}, "doctor" },   // also defines cpp_grammar_abi=
    { "languages", "languages=N: distinct compiled-in grammars (the grammars row's expected=)", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "tracked", "tracked=N: git ls-files count, printed even when truncated=1 (over 20000 files skips the scan)", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "binaries", "binaries=N: tracked paths that sniff as binary content", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "non_git", "non_git=1: no git history to compare; the row passes unscanned", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "stale", "stale=N: tracked binaries committed before a same-dir same-stem source changed; any fails the row", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "p0", "p0=/src0=: one stale binary and its newer source (pairs p0..p7 at most; more= counts the rest)", true, "c", MapHeaderRead::No, {}, "doctor" },   // also defines src0=
    { "more", "more=N: stale pairs past the 8 printed; all still counted in stale=", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "cache_version", "cache_version=/parser_ver_lean=/parser_ver_rich=/artifact_arch=: index identity; reuse needs all four", true, "c", MapHeaderRead::No, {}, "doctor" },   // also defines parser_ver_lean= parser_ver_rich= artifact_arch=
    { "rich_verbs", "rich_verbs=: the verbs that consume the rich artifact (rich=); every other verb reads the lean one", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "source", "source=: auto (per-root blob), cache-flag (named by the cache flag) or disabled (no-cache: nothing read)", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "lean_path", "lean_path=/rich_path=: the artifact files checked; one path when the cache flag named it", true, "c", MapHeaderRead::No, {}, "doctor" },   // also defines rich_path=
    { "lean", "lean=/rich=: can THIS binary open that artifact (ok, absent, parser-version ...); format, never freshness", true, "c", MapHeaderRead::No, {}, "doctor" },   // also defines rich=
    { "fsmonitor", "fsmonitor=: the checkout's core.fsmonitor at startup: unset, builtin, off, or hook (a command git runs)", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "neutralised", "neutralised=1: a hook fsmonitor was overridden to false for this run; 0 when none was needed", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "state", "state=: layout records agree, disagree (mixed binary: rebuild clean-first), not-checked or no-records", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "checked", "checked=1: the cross-unit layout comparison ran; 0 = under two comparable records", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "units", "units=N: translation units that registered a layout record", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "types", "types=N: layout types recorded (only those registered in src/model.h); omitted on state=disagree", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "type", "type=: the first layout type whose two records differ (state=disagree)", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "unit0", "unit0=/unit1=/present0=/present1=/size0=/size1=/align0=/align1=: the two disagreeing records' values", true, "c", MapHeaderRead::No, {}, "doctor" },   // also defines unit1= present0= present1= size0= size1= align0= align1=
    // quality-panel: src/qualitypanel.h writePanelReport (+ kPanelLegend)
    { "preset", "preset=: strict (5 stable families, cut 2), default (6, cut 2), lenient (6, cut 1); selects, never weights", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },
    { "families", "families=6: evidence families: structural lexical confusion historical colocation state", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },
    { "enabled", "enabled=/enabled_n=: the families this preset COUNTS, and how many", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },   // also defines enabled_n=
    { "cut", "cut=N: distinct enabled families that must fire for a row to rank", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },
    { "cut_reachable", "cut_reachable=0: cut= exceeds the evaluable families (of=); a corpus fact, never a clean bill of health", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },
    { "eligible", "eligible=N: functions/methods with a body; ranked= + below_cut= + no_family= = eligible=, always", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },
    { "ranked", "ranked=N: rows that met the cut (total=); only shown= print, page with offset=", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },
    { "below_cut", "below_cut=N: fired at least one enabled family, but fewer than cut=", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },
    { "no_family", "no_family=N: no enabled family fired; unavailable= families were never measured", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },
    { "bar_ccx", "bar_ccx=/bar_loc=/bar_nest=/bar_params=: absolute bars: cognitive complexity, lines, nesting, params", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },   // also defines bar_loc= bar_nest= bar_params=
    { "rcut", "rcut=/rmeasured=: readability decile width (rrank= under it fires) / functions measured", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },   // also defines rmeasured=
    { "hcut", "hcut=/hranked=: file churn decile width / files with an in-window commit (hranked=0 voids historical)", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },   // also defines hranked=
    { "window", "window=: the git churn window hrank= and churn= are counted over (RELATIVE to this corpus)", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },
    { "ccut", "ccut=/cranked=: colocation decile width / functions reading any outside definition (0 voids it)", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },   // also defines cranked=
    { "cfiles", "cfiles=/cscope=: files the confusion atom rules read / eligible symbols in them", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },   // also defines cscope=
    { "lscope", "lscope=N: symbols the lexical naming rules read", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },
    { "sfiles", "sfiles=/sscope=: files the state lens reads / symbols in them", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },   // also defines sscope=
    { "cells", "cells=N: non-local mutable cells the state lens found", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },
    { "tested_scope", "tested_scope=N: symbols an indexed test reaches; at 0 no row can carry join=deep+untested", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },
    { "deep_untested", "deep_untested=N: rows carrying join=deep+untested across the WHOLE set, not just this page", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },
    { "unavailable", "unavailable=: families NOT evaluated at all; absence from fired= is not evidence of health", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },
    { "unavailable_why", "unavailable_why=: one reason per unavailable= family", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },
    { "unreadable_files", "unreadable_files=N: files readability could not read; rrank= is a floor", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },
    { "state_floor", "state_floor=1: the state lens hit its budget; state evidence is a FLOOR", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },
    { "findings_capped", "findings_capped=1/floor_rules=: rules that spent their per-rule budget; those families are FLOORS", false, "quality_panel", MapHeaderRead::No, {}, "quality-panel" },   // also defines floor_rules=
    { "uncounted", "uncounted=: families that fired on this row but this preset does not count", true, "s", MapHeaderRead::No, {}, "quality-panel" },
    { "unavail", "unavail=: families not measurable here (the root's unavailable=); of= already excludes them", true, "s", MapHeaderRead::No, {}, "quality-panel" },
    { "f", "e f=: the fired family this evidence row belongs to", true, "e", MapHeaderRead::No, {}, "quality-panel" },
    { "counted", "counted=1: this preset counts the family toward fam=; 0 = fired, not counted", true, "e", MapHeaderRead::No, {}, "quality-panel" },
    { "why", "why=: the measurements that crossed (rule*N fired N times; hrank=/churn= are the file's, inherited)", true, "e", MapHeaderRead::No, {}, "quality-panel" },
    // naming-calibration: src/renamemine.h writeNamingCalibrationReport (+ kNamingCalibrationLegend)
    { "probed", "probed=0: no history to mine, nothing scored (r= says why); 1 = the git walk ran", false, "naming-calibration", MapHeaderRead::No, {}, "naming-calibration" },
    { "r", "r=: why probed=0: not-a-git-repo or probe-failed", false, "naming-calibration", MapHeaderRead::No, {}, "naming-calibration" },
    { "pairs", "pairs=N: labelled rename pairs that survived the join, the SAMPLE SIZE; a small one means nothing", false, "naming-calibration", MapHeaderRead::No, {}, "naming-calibration" },
    { "candidates", "candidates=N: raw substitutions mined from the patch stream before the join; FLOOR when truncated=1", false, "naming-calibration", MapHeaderRead::No, {}, "naming-calibration" },
    { "commits", "commits=N: non-merge commits walked (the walk stops at 40000)", false, "naming-calibration", MapHeaderRead::No, {}, "naming-calibration" },
    { "hunks", "hunks=N: diff hunks with content on both sides", false, "naming-calibration", MapHeaderRead::No, {}, "naming-calibration" },
    { "wide_hunks", "wide_hunks=N: hunks DROPPED for exceeding the 24-line per-side pairing cap; never mined", false, "naming-calibration", MapHeaderRead::No, {}, "naming-calibration" },
    { "drop_old_alive", "drop_old_alive=N: candidates dropped: the old spelling is still an indexed name", false, "naming-calibration", MapHeaderRead::No, {}, "naming-calibration" },
    { "drop_new_absent", "drop_new_absent=N: candidates dropped: the new spelling is no eligible indexed symbol at HEAD", false, "naming-calibration", MapHeaderRead::No, {}, "naming-calibration" },
    { "drop_ambiguous", "drop_ambiguous=N: candidates dropped: a name on both sides of several (split, rework, revert)", false, "naming-calibration", MapHeaderRead::No, {}, "naming-calibration" },
    { "drop_old_skipped", "drop_old_skipped=N: candidates dropped: the lens skips the old spelling, no rule could fire", false, "naming-calibration", MapHeaderRead::No, {}, "naming-calibration" },
    { "truncated", "truncated=1: a git walk bound was hit; candidates= is a FLOOR", false, "naming-calibration", MapHeaderRead::No, {}, "naming-calibration" },
    { "scope", "scope=group-rule: the rule judges co-visible names, which one pair cannot evidence; unscored, not 0/0", true, "r", MapHeaderRead::No, {}, "naming-calibration" },
    { "o", "o=/n=: one labelled pair's old (abandoned) and new (chosen) spelling", true, "p", MapHeaderRead::No, {}, "naming-calibration" },   // also defines n= on p
    { "sup", "sup=N: distinct hunks that showed this substitution", true, "p", MapHeaderRead::No, {}, "naming-calibration" },
    { "at", "p at=: path:line of the symbol the pair joined to, not a commit (the root at= is)", true, "p", MapHeaderRead::No, {}, "naming-calibration" },
    { "old_fires", "old_fires=: rules that fired on the old spelling; absent when none", true, "p", MapHeaderRead::No, {}, "naming-calibration" },
    { "new_fires", "new_fires=: rules that fired on the new spelling; absent when none", true, "p", MapHeaderRead::No, {}, "naming-calibration" },
    // dmm: src/dmm.h writeDmmReport (+ kDmmLegend)
    { "available", "available=0: no score at all (dmm=UNAVAILABLE, reason= says why); never read as 1.000 or 0.000", false, "dmm", MapHeaderRead::No, {}, "dmm" },
    { "combine", "combine=pooled: root dmm= is summed good over summed good+bad of the 3 properties (ripwire's own)", false, "dmm", MapHeaderRead::No, {}, "dmm" },
    { "low_loc", "low_loc=/low_cx=/low_params=: a unit is LOW risk at or under these lines / cyclomatic / params", false, "dmm", MapHeaderRead::No, {}, "dmm" },   // also defines low_cx= low_params=
    { "base_units", "base_units=/base_volume=/target_units=/target_volume=: units with a body and their line span per side", false, "dmm", MapHeaderRead::No, {}, "dmm" },   // also defines base_volume= target_units= target_volume=
    { "reason", "reason=: why no score (no unit's size, complexity or params moved; a tree failed to parse ...)", false, "dmm", MapHeaderRead::No, {}, "dmm" },
    // comment-coherence: src/commentcoherence.h (the comment_coherence root and fn row emit)
    { "documented", "documented=N: functions with a doc comment, measured (the rows); a FLOOR when unreadable_files= shows", false, "comment_coherence", MapHeaderRead::No, {}, "comment-coherence" },
    { "no_comment", "no_comment=N: eligible symbols with no measurable comment; UNAVAILABLE, never scored as zero", false, "comment_coherence", MapHeaderRead::No, {}, "comment-coherence" },
    { "unreadable_files", "unreadable_files=N: indexed files this pass could not read; their functions are absent", false, "comment_coherence", MapHeaderRead::No, {}, "comment-coherence" },
    { "words", "words=/restate=: comment word count (c_coeff= denominator, stopwords kept) / words matching a name word", true, "fn", MapHeaderRead::No, {}, "comment-coherence" },   // also defines restate=
    { "c_terms", "c_terms=/i_terms=/shared=: comment term set / identifiers the body uses / overlap; cic= shared over union", true, "fn", MapHeaderRead::No, {}, "comment-coherence" },   // also defines i_terms= shared=
    // help-task: src/main.cpp runHelpTask (+ src/taskroute.h classifyRoutes)
    { "git", "git=/dirty=: the root is a git repo / its tree differs from HEAD (the stamp's +dirty)", true, "facts", MapHeaderRead::No, {}, "help-task" },   // also defines dirty=
    { "trace", "trace=1: the task text has a stack/sanitizer trace shape; it routes to from-trace", true, "facts", MapHeaderRead::No, {}, "help-task" },
    { "resolved_symbols", "resolved_symbols=N: indexed names the task NAMES; a bare short/common word needs backticks or F()", true, "facts", MapHeaderRead::No, {}, "help-task" },
    // doctor purpose line (compactlegend.h:179) spells c name= but the emitter writes n= (verbs_doctor.h row lambda, doctorAgentRows); the n row above defines it; consider fixing the purpose to c n= ok=.
    // doctor truncated= means two different things on two c rows (cache-dir: scan cut, bytes/blobs short; tracked-binaries: scan skipped, stale=0 unmeasured); one KEY-qualified row carries both.
    // doctor p0=/src0= are numbered: tracked-binaries emits p0..p7/src0..src7 (kShown=8); only p0/src0 get a reading, so p1..p7/src1..src7 stay undefined if a gate reads every name (needs 14 more rows or a prefix rule).
    // doctor conditional rows not in today's output (present-only): agent (root, agent flag), copied, blobs_floor, shallow, p0, more, type, unit0 group; the agent rows append check-specific attrs from codexdoctor::Check.attrs, not audited here.
    // quality-panel conditional rows not in today's output: unavailable, unavailable_why (split: not provably always co-emitted), unreadable_files, state_floor, findings_capped+floor_rules, s uncounted, s unavail.
    // naming-calibration: p at= is a path:line, NOT the commit stamp; the existing tool-wide at=: commit+dirty+shallow term also fires on these answers, so the p at row disambiguates. Conditional: r (probed=0 root), truncated, new_fires.
    // naming-calibration root r= and r row element share a name; the r row is onTag naming-calibration so it only fires on the probed=0 root.
    // dmm error path (bad/no ref) emits only available=0 dmm=UNAVAILABLE reason= at=; base_units/low_loc groups are Ok-path only, where each is always co-emitted.
    // help-task purpose says status=recommend|abstain but the emitter also writes ambiguous (confidence=low); outside this gap list.
    // comment-coherence: c_coeff= is spelled only in the purpose, which does not say HIGH c_coeff is BAD (restates the name); outside this gap list.
    // quality-delta rows (src/verbs_quality.h): the row facets the purpose line does not spell, present-only.
    { "sev", "r sev=minor: a small numeric delta, counted in minor=, never gating (absent: major)", true, "r", MapHeaderRead::No, {}, "quality-delta" },
    { "origin", "r origin=new-symbol: the finding is on NEW code, never gating (absent: preexisting-worse)", true, "r", MapHeaderRead::No, {}, "quality-delta" },
    { "churn", "r churn=self|ambient: the edit modifies lines committed inside the churn window (self) or only adds/touches older ones (ambient); informational", true, "r", MapHeaderRead::No, {}, "quality-delta" },
    { "idiom", "r idiom=: the recognized clone-body shape of a duplication row", true, "r", MapHeaderRead::No, {}, "quality-delta" },
    // --expand's bundle (src/main.cpp runDefaultMap): the ride-along note and the map it carries inside the <ctx>.
    { "note", "note=: the ranked map rides along with the payload; top-k=0 serves the payload alone", false, "ctx", MapHeaderRead::No, {}, "expand" },
    { "pr_iters", "r root= pr_iters=: the ride-along map; root= its p= base, pr_iters= PageRank iterations", true, "r", MapHeaderRead::No, {}, "expand" },   // also defines root= on <r>
    // handoff: src/handoff.h (the packet root, the heuristic block, its rows)
    { "branch", "branch=/subject=: the checked out branch and HEAD commit subject; gitok=0: the git diff probe failed, changed counts are floors", false, "handoff", MapHeaderRead::No, {}, "handoff" },   // also defines subject= gitok=
    { "cochange_window", "cochange_window=/cochange_commits=: the git window the cochange rows were mined in and the commits it held (0: could not look)", true, "heuristic", MapHeaderRead::No, {}, "handoff" },   // also defines cochange_commits=
    { "deg", "cochange deg=: how often that file is edited with the changed ones (co-change degree)", true, "cochange", MapHeaderRead::No, {}, "handoff" },
    { "s", "doc s=: lexical score of that plan/design doc for the branch+subject query", true, "doc", MapHeaderRead::No, {}, "handoff" },
    { "syms_total", "syms_total=: symbols that changed file defines; syms_capped=1: its symbol list was cut to that many", true, "f", MapHeaderRead::No, {}, "handoff" },
    { "run", "t run=: the command that runs that test (run_unknown=1: none derivable)", true, "t", MapHeaderRead::No, {}, "handoff" },
    // graph-query: src/verbs_navigate.h (the <query> root)
    { "expr", "expr=: the expression as given; count=: symbols it matched (rows page by shown=/total=)", false, "query", MapHeaderRead::No, {}, "graph-query" },   // also defines count=
    // match: src/verbs_lint.h
    { "auto_captured", "auto_captured=1: the query bound no @capture, so @m was appended to its single top-level pattern", false, "match", MapHeaderRead::No, {}, "match" },
    { "of_files", "of_files=: indexed files in all (eligible_files= of them are in the query's languages)", false, "match", MapHeaderRead::No, {}, "match" },
    // #157 (CodeRabbit on #331): the present-only nest_refused= on the <match>, <pattern> and <lint> roots. The
    // header-only row in kCompactCompletenessTerms reads the MAP header alone, and the verbs' own full-legend
    // clauses are prose the compact dialect strips, so without these a default answer carried the count unread.
    { "nest_refused", "nest_refused=K: K corpus files a pre-parse nesting guard refused; never walked, not in eligible_files= (the skipped verb names them)", false, "match", MapHeaderRead::No, {}, "match" },
    { "nest_refused", "nest_refused=K: K corpus files a pre-parse nesting guard refused; never walked, in neither eligible_files= nor skipped_files=", false, "pattern", MapHeaderRead::No, {}, "pattern" },
    { "nest_refused", "nest_refused=K: K corpus files a pre-parse nesting guard refused, corpus-wide (not narrowed to a language any rule here declares); no rule walked them (the skipped verb names them)", false, "lint", MapHeaderRead::No, {}, "lint" },
    // verify: src/verbs_navigate.h (the verify root)
    { "claim", "claim=/shape=: the claim as given and its shape; from_defs=/to_defs=: defs each name resolved to", false, "verify", MapHeaderRead::No, {}, "verify" },   // also defines shape= from_defs= to_defs=
    { "hops", "hops=N: call edges on the witness path (a confirmed reach claim only)", false, "verify", MapHeaderRead::No, {}, "verify" },
    // map-diff: the map's <f layer=> (same reading as the signature bundles)
    { "layer", "layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none", true, "f", MapHeaderRead::No, {}, "map-diff" },
    // ── the same, for the verbs outside legendcoveragecheck's original roster (its DEFAULT_ONLY rows): the expand servings,
    // slice, flags, doctor, the partition envelope, from-trace, batch, the signature bundles, the lint catalog, skipped,
    // nonlocal-state, field-affinity. The LATENT rows define cut/cap attributes those verbs emit only past a ceiling.
    // expand (bundle serving): src/main.cpp (chooseExpandServe, the exact-name top-k default insert) + src/serialize.h (inc= emit)
    { "mode", "mode=/reason=: bundle served, not the whole file; reason= gives both byte counts or the cause; explicit top-k opts out", false, "ctx", MapHeaderRead::No, {}, "expand" },   // also defines reason=
    { "topk_default", "topk_default=0: an exact name was expanded, so the ranked map was dropped; pass top-k=N to get it back", false, "ctx", MapHeaderRead::No, {}, "expand" },
    { "inc_total", "inc_total=N: the file's true include/import count; inc= lists the first 24, inc_capped=1 when cut", true, "b", MapHeaderRead::No, {}, "expand" },
    // expand (whole-file serving): src/main.cpp chooseExpandServe (fileOpen) + the topk_default insert
    { "mode", "mode=/reason=: whole-file won, the file text cost fewer bytes than the bundle; reason= gives both sizes", false, "ctx", MapHeaderRead::No, {}, "expand-file" },   // also defines reason=
    { "topk_default", "topk_default=0: an exact name was expanded, so the ranked map was dropped; pass top-k=N to get it back", false, "ctx", MapHeaderRead::No, {}, "expand-file" },
    // slice: src/slice.h (the <slice> root emit, kSliceCountsAttrXml)
    { "sym", "sym=/lang=: the sliced definition's name and language; p= is its file:line", false, "slice", MapHeaderRead::No, {}, "slice" },   // also defines lang=
    { "vars", "vars=N: sliceable local bindings in the definition, one v row each; name one to slice it", false, "slice", MapHeaderRead::No, {}, "slice" },
    { "order", "order=defuse: seed s rows (no v=) ranked among these rows by def-use coverage (distinct local names on the line) desc, then line; not source order, not a whole-function ranking (measured at chance — docs/EVALS.md) — flow s rows (v=) keep their (d=,l=,v=) order", false, "slice", MapHeaderRead::No, {}, "slice" },   // slice.h sliceDefUseRowOrder
    { "counts", "counts=as-classified: defs=/uses=/vars=/steps= count what the name classifier rowed; neither floors nor totals", false, "slice", MapHeaderRead::No, {}, "slice" },
    // flags: src/darkflags.h (the <flags> root emit)
    { "gates", "gates=/dark_gates=: gate rows (never cut) / those whose default keeps the guarded code out of the build", false, "flags", MapHeaderRead::No, {}, "flags" },   // also defines dark_gates=
    { "compile", "compile=/cmake=/env=: gates by kind: ifndef/define header gate, CMake option(), getenv read", false, "flags", MapHeaderRead::No, {}, "flags" },   // also defines cmake= env=
    { "files", "files=N: files this verb scanned for gates (source + CMakeLists), wider than the map's corpus", false, "flags", MapHeaderRead::No, {}, "flags" },
    // doctor: src/verbs_doctor.h runDoctor (+ doctorBinaryPathVerdictAttr, doctorNotOnPathHint)
    { "checks", "checks=/passed=: checks run / how many passed; exit 1 when passed= is below checks=", false, "doctor", MapHeaderRead::No, {}, "doctor" },   // also defines passed=
    { "built_from", "built_from=: the commit this binary was built from; at= is the tree HEAD now, a mismatch is normal", false, "doctor", MapHeaderRead::No, {}, "doctor" },
    { "self", "self=/which=: this binary's path and the one which ripwire finds on PATH; which_version= is the version line that one prints when they differ", true, "c", MapHeaderRead::No, {}, "doctor" },   // also defines which= which_version=
    { "on_path", "on_path=0|1: whether a ripwire is on PATH; 0 fails the row and hint= carries the export line", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "same_file", "same_file=1: the PATH copy is this very file (same device and inode)", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "same_bytes", "same_bytes=1: a different file with identical content, a copied install (ok); 0 fails the row", true, "c", MapHeaderRead::No, {}, "doctor" },
    { "self_mtime", "self_mtime=/self_size=/which_mtime=/which_size=: epoch mtime and byte size of each binary", true, "c", MapHeaderRead::No, {}, "doctor" },   // also defines self_size= which_mtime= which_size=
    { "hint", "hint=: the row's verdict and fix in plain text (which binary is stale, what to run)", true, "c", MapHeaderRead::No, {}, "doctor" },
    // pack-task partition=N: src/partition.h (partitionSummaryAttrs, the <bundle> header) + src/packtask.h (the inner ctx root)
    { "partitions", "partitions=/requested=: partitions carved / asked for", false, "ctx-partitions", MapHeaderRead::No, {}, "pack-task" },   // also defines requested=
    { "modules", "modules=/split=: call-graph groups found / cuts forced to split one", false, "ctx-partitions", MapHeaderRead::No, {}, "pack-task" },   // also defines split=
    { "core_symbols", "core_symbols=/surface=: ids in the shared core / core plus the assignable remainder", false, "ctx-partitions", MapHeaderRead::No, {}, "pack-task" },   // also defines surface=
    { "budget_per_agent_tokens", "budget_per_agent_tokens=: one agent's budget, core_budget_tokens= plus partition_budget_tokens=", false, "ctx-partitions", MapHeaderRead::No, {}, "pack-task" },   // also defines core_budget_tokens= partition_budget_tokens=
    { "total_bytes", "total_bytes=N: bytes of all bundles together", false, "ctx-partitions", MapHeaderRead::No, {}, "pack-task" },
    { "overlap_mean", "overlap_mean=/overlap_max=: pairwise Jaccard over the ids partitions name, before trimming", false, "ctx-partitions", MapHeaderRead::No, {}, "pack-task" },   // also defines overlap_max=
    { "shared_symbols", "shared_symbols=/union_symbols=: ids two or more partitions name / ids any partition names", false, "ctx-partitions", MapHeaderRead::No, {}, "pack-task" },   // also defines union_symbols=
    { "core_overlap", "core_overlap=: share of the core surface a partition reaches anyway", false, "ctx-partitions", MapHeaderRead::No, {}, "pack-task" },
    // from-trace: src/tracelocus.h (renderTraceBlock, buildTraceHeader via ctxRootOpen, the budget_tokens attr)
    { "task", "task=: the trace source this bundle maps, verbatim (a file path, stdin, or an MCP label)", false, "ctx", MapHeaderRead::No, {}, "from-trace" },
    { "budget_tokens", "budget_tokens=N: the token budget passed (absent when none); over_ceiling=1 if est_tokens= exceeds it", false, "ctx", MapHeaderRead::No, {}, "from-trace" },
    { "src", "src=/format=: the trace read and its dominant frame format, python|asan|node|compiler|generic", true, "trace", MapHeaderRead::No, {}, "from-trace" },   // also defines format=
    { "frame_lines", "frame_lines=/parsed=: frame-shaped input lines / those yielding a path:line; the rest matched no format", true, "trace", MapHeaderRead::No, {}, "from-trace" },   // also defines parsed=
    { "in_corpus", "in_corpus=: parsed frames in indexed files; always suspects= + merged= + unresolved=", true, "trace", MapHeaderRead::No, {}, "from-trace" },
    { "suspects", "suspects=/merged=/unresolved=: frame rows / folded into a claimed symbol / unresolved rows (indexed file, no def)", true, "trace", MapHeaderRead::No, {}, "from-trace" },   // also defines merged= unresolved=
    { "skipped", "skipped=N: frames outside every root, listed as skipped rows, never ranked", true, "trace", MapHeaderRead::No, {}, "from-trace" },
    { "rank", "rank=N: frame order, innermost in-corpus first; p= is the trace's own path:line, defs are sigs l=", true, "frame", MapHeaderRead::No, {}, "from-trace" },
    { "resolved_by", "resolved_by=name|line: bound by the frame's own name, else by the def enclosing its line", true, "frame", MapHeaderRead::No, {}, "from-trace" },
    { "innermost", "innermost=1: the innermost in-corpus frame (rank 1); its full body is served", true, "frame", MapHeaderRead::No, {}, "from-trace" },
    // batch: src/mcpverbs.h (the <batch>/<q> emit)
    { "verb", "i=/verb=/ok=: sub-query index, its verb text, 1 answered (payload in CDATA) or 0 failed", true, "q", MapHeaderRead::No, {}, "batch" },   // also defines i= ok=
    { "err", "err=: why an ok=0 sub-query failed; no payload follows", true, "q", MapHeaderRead::No, {}, "batch" },
    // pack-signatures: src/serialize.h (<f layer=> from src/arch.h builtinLayer)
    { "layer", "layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none", true, "f", MapHeaderRead::No, {}, "pack-signatures" },
    // pack-top-n: src/serialize.h (<f layer=> from src/arch.h builtinLayer)
    { "layer", "layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none", true, "f", MapHeaderRead::No, {}, "pack-top-n" },
    // lint-catalog: src/verbs_lint.h emitLintCatalog
    { "rules", "rules=N: rules in the built-in registry, one rule row each, never cut", false, "lintcatalog", MapHeaderRead::No, {}, "lint-catalog" },
    // skipped: src/verbs_report.h writeSkippedHeader / writeUnindexedExtRows / writeLangRows (+ kSkippedLegend)
    { "indexed", "indexed=N: the map's files=; indexed= + oversize= + excluded= + ignored= = every file the crawl enumerated", false, "skipped", MapHeaderRead::No, {}, "skipped" },
    { "oversize", "oversize=N: files dropped for exceeding a size ceiling (row limit= names which)", false, "skipped", MapHeaderRead::No, {}, "skipped" },
    { "excluded", "excluded=N: files dropped by an exclude substring you passed", false, "skipped", MapHeaderRead::No, {}, "skipped" },
    { "unsupported_ext", "unsupported_ext=N: source/text files no grammar reads; binary assets and excluded/ignored files not counted", false, "skipped", MapHeaderRead::No, {}, "skipped" },
    { "excluded_dirs", "excluded_dirs=N: subtrees an exclude pruned; their files are UNKNOWN, not zero, and in no count here", false, "skipped", MapHeaderRead::No, {}, "skipped" },
    { "pruned_dirs", "pruned_dirs=N: subtrees pruned by built-in policy (vendor/build, CMakeCache.txt dirs); contents UNKNOWN", false, "skipped", MapHeaderRead::No, {}, "skipped" },
    { "ignored", "ignored=/ignored_dirs=: files / subtrees git ignore rules hid (else indexed); subtree contents UNKNOWN", false, "skipped", MapHeaderRead::No, {}, "skipped" },   // also defines ignored_dirs=
    { "ignore_mode", "ignore_mode=: git (rules applied), off (no-ignore flag), unavailable/root-ignored (not consulted, full walk)", false, "skipped", MapHeaderRead::No, {}, "skipped" },
    { "degraded_parse", "degraded_parse=/minified_suspect=: counts of the h rows of each why=; those files stay indexed", false, "skipped", MapHeaderRead::No, {}, "skipped" },   // also defines minified_suspect=
    { "unmeasured", "unmeasured=N: indexed files never parsed (doc pass, binary sniff, nest guard, read error); not health-counted", false, "skipped", MapHeaderRead::No, {}, "skipped" },
    { "max_file_size", "max_file_size=B: the effective per-file size ceiling in bytes (the max-file-size flag raises it)", false, "skipped", MapHeaderRead::No, {}, "skipped" },
    { "json_ceiling", "json_ceiling=/yaml_ceiling=: fixed .json/.yaml byte ceilings the max-file-size flag does NOT raise", false, "skipped", MapHeaderRead::No, {}, "skipped" },   // also defines yaml_ceiling=
    { "ws_freq", "ws_freq=R: whitespace share of the leading 4096 bytes; under 0.070 = minified-suspect (never under 256 B)", true, "h", MapHeaderRead::No, {}, "skipped" },
    { "x", "x=/files=: an unindexed extension and its file count (full list; the map's unindexed= is the top 6)", true, "e", MapHeaderRead::No, {}, "skipped" },   // also defines files= on <e>
    { "files", "files=/symbols=: per language, files with its symbols (FLOOR: symbol-less files uncounted) / symbols (exact)", true, "lang", MapHeaderRead::No, {}, "skipped" },   // also defines symbols=
    // nonlocal-state: src/nonlocalstate.h writeNonLocalStateReport (+ kNonLocalStateLegend)
    { "cells", "cells=N: mutable non-local cells found in the corpus (globals, statics, Python module globals; FLOOR)", false, "nonlocal_state", MapHeaderRead::No, {}, "nonlocal-state" },
    { "functions", "functions=N: functions reaching at least one cell, directly or via callees (all rows, before paging)", false, "nonlocal_state", MapHeaderRead::No, {}, "nonlocal-state" },
    { "direct_writes", "direct_writes=/direct_reads=: the writes=/reads= cells this function's OWN body writes/reads", true, "fn", MapHeaderRead::No, {}, "nonlocal-state" },   // also defines direct_reads=
    { "cells_total", "cells_total=N: distinct cells reached (read and written counts once); at most 12 cell rows print", true, "fn", MapHeaderRead::No, {}, "nonlocal-state" },
    { "at_dir", "at=/at_dir=: one own-body use site (may be more) and what own-body sites do (can be narrower than dir=)", true, "cell", MapHeaderRead::No, {}, "nonlocal-state" },   // also defines at= on <cell> (always emitted with at_dir=; via= otherwise)
    // field-affinity: src/fieldaffinity.h writeFieldAffinity / buildStructRow / computeFieldAffinity
    { "block", "block=64: ASSUMED cache-line bytes; all geometry (dist= wt= ln= lines= findings) is against it", false, "fieldaffinity", MapHeaderRead::No, {}, "field-affinity" },
    { "model", "model=lp64-approx: sizes/offsets are the layout verb's LP64 standard-layout MODEL, not the real ABI", false, "fieldaffinity", MapHeaderRead::No, {}, "field-affinity" },
    { "weighting", "weighting=fanin-floor: w= sums 1 + fan-in per co-accessing fn; a reachability proxy, not a frequency", false, "fieldaffinity", MapHeaderRead::No, {}, "field-affinity" },
    { "aggregates", "aggregates=N: C-family structs/classes the layout model located a body for (the scanned universe)", false, "fieldaffinity", MapHeaderRead::No, {}, "field-affinity" },
    { "files", "files=N: C-family files declaring at least one struct/class the modelling pass visited", false, "fieldaffinity", MapHeaderRead::No, {}, "field-affinity" },
    { "fns_scanned", "fns_scanned=N: C-family functions/methods with a readable body scanned for dot/arrow member accesses", false, "fieldaffinity", MapHeaderRead::No, {}, "field-affinity" },
    { "accesses", "accesses=N: member-access sites tied to one aggregate field (FLOOR: bare in-method names uncounted)", false, "fieldaffinity", MapHeaderRead::No, {}, "field-affinity" },
    { "amb_skipped", "amb_skipped=N: access sites REFUSED, not guessed: 2+ aggregates declare that field name; in no count here", false, "fieldaffinity", MapHeaderRead::No, {}, "field-affinity" },
    { "structs", "structs=N: aggregates with 1+ attributed access; the top 20 by sepcost= print (shown=/capped=)", false, "fieldaffinity", MapHeaderRead::No, {}, "field-affinity" },
    { "findings", "findings=N: split-line + straddle findings over ALL structs=, not just the printed rows", false, "fieldaffinity", MapHeaderRead::No, {}, "field-affinity" },
    { "min_fns", "min_fns=2: a pair fires split-line only when co-accessed by this many distinct functions", false, "fieldaffinity", MapHeaderRead::No, {}, "field-affinity" },
    { "as_loops", "as_loops=N: for-loops the static advance-shape pass classified corpus-wide; report-only, never ranks", false, "fieldaffinity", MapHeaderRead::No, {}, "field-affinity" },
    { "as_index", "as_index=/as_chase=/as_mixed=/as_unknown=: as_loops= by advance shape (chase = pointer chase)", false, "fieldaffinity", MapHeaderRead::No, {}, "field-affinity" },   // also defines as_chase= as_mixed= as_unknown=
    { "agg", "agg=: the aggregate keyword (struct, class ...)", true, "s", MapHeaderRead::No, {}, "field-affinity" },
    { "modeled", "modeled=1: layout model placed the fields; 0 = affinity only, no geometry, no finding (why= says why)", true, "s", MapHeaderRead::No, {}, "field-affinity" },
    { "fields", "fields=N: fields declared (before the touched-only filter)", true, "s", MapHeaderRead::No, {}, "field-affinity" },
    { "touched", "touched=N: fields with 1+ attributed access; at most 32 f rows print", true, "s", MapHeaderRead::No, {}, "field-affinity" },
    { "pairs", "pairs=N: co-accessed field pairs in all; at most 12 pair rows print (most fns= first)", true, "s", MapHeaderRead::No, {}, "field-affinity" },
    { "sepcost", "sepcost=: sum over measured pairs of fns x (1 - wt); the struct ranking key", true, "s", MapHeaderRead::No, {}, "field-affinity" },
    { "findings", "findings=N: this struct's findings, every one printed", true, "s", MapHeaderRead::No, {}, "field-affinity" },
    { "size", "size=/align=/lines=: modeled sizeof, alignment, cache lines spanned (modeled=1 only)", true, "s", MapHeaderRead::No, {}, "field-affinity" },   // also defines align= lines=
    { "acc", "acc=N: member-access sites attributed to this field (FLOOR)", true, "f", MapHeaderRead::No, {}, "field-affinity" },
    { "sz", "sz=B: the field's modeled size in bytes (absent when the model could not size it)", true, "f", MapHeaderRead::No, {}, "field-affinity" },
    { "off", "off=/ln=: modeled byte offset and its cache line (off/64); placed=0 instead when the model refused", true, "f", MapHeaderRead::No, {}, "field-affinity" },   // also defines ln=
    { "w", "w=: sum of 1 + fan-in over the co-accessing functions; a static reachability proxy, never a frequency", true, "pair", MapHeaderRead::No, {}, "field-affinity" },
    { "wt", "wt=: separation weight (64 - dist)/64, 0.00 = the two can never share a line; measured=0 instead when unplaced", true, "pair", MapHeaderRead::No, {}, "field-affinity" },
    { "wt", "wt=0.00: split-line fires only when the pair can never share a 64-byte line", true, "finding", MapHeaderRead::No, {}, "field-affinity" },
    { "w", "w=: the split-line pair's 1 + fan-in weight sum (proxy); straddle rows carry none", true, "finding", MapHeaderRead::No, {}, "field-affinity" },
    { "crosses", "off=/sz=/crosses=: straddle field offset, size, and the line its last byte lands on (lines start at off/64)", true, "finding", MapHeaderRead::No, {}, "field-affinity" },   // also defines off= sz= on <finding>
    { "fanin", "fanin=N: this function's caller count (the w= proxy input)", true, "fn", MapHeaderRead::No, {}, "field-affinity" },
    { "touched", "touched=N: distinct fields of this struct the function touches (named in f=); at most 8 fn rows of fns= print", true, "fn", MapHeaderRead::No, {}, "field-affinity" },
    { "scope", "scope=: the function's PROFILE_SCOPE description (first 120 chars), a counter to confirm with", true, "fn", MapHeaderRead::No, {}, "field-affinity" },
    { "scopes", "scopes=N: distinct PROFILE_SCOPEs among the co-accessing functions (the scope children)", true, "validate", MapHeaderRead::No, {}, "field-affinity" },
    { "status", "status=: instrumented (a scope exists to measure) or uninstrumented (no witness yet)", true, "validate", MapHeaderRead::No, {}, "field-affinity" },
    { "counter", "counter=: the hardware counter to compare across the two layouts", true, "validate", MapHeaderRead::No, {}, "field-affinity" },
    { "hint", "hint=: how to add the missing instrumentation (uninstrumented only)", true, "validate", MapHeaderRead::No, {}, "field-affinity" },
    // LATENT cut/cap/refusal attributes: conditional, NOT in the src/ answer, readings from the emitter only (keep or drop)
    { "rows_capped", "rows_capped=1: a row list hit its 500-row ceiling; rows are a SAMPLE, every count stays exact", false, "skipped", MapHeaderRead::No, {}, "skipped" },
    { "cells_capped", "cells_capped=1: the cell universe hit its 2048 ceiling; cells beyond it are uncounted", false, "nonlocal_state", MapHeaderRead::No, {}, "nonlocal-state" },
    { "cells_shown", "cells_shown=/cells_capped=1: only this many of cells_total= cell rows print (cap 12)", true, "fn", MapHeaderRead::No, {}, "nonlocal-state" },   // also defines cells_capped= on <fn>
    { "decls_capped", "decls_capped=1: a declaration query hit its match budget; cells may be missing", false, "nonlocal_state", MapHeaderRead::No, {}, "nonlocal-state" },
    { "undecided_decls", "undecided_decls=N: declarations whose mutability could not be decided; dropped, never guessed", false, "nonlocal_state", MapHeaderRead::No, {}, "nonlocal-state" },
    { "unanalyzed_langs", "unanalyzed_langs=/unanalyzed_files=: indexed languages (and their files) this lens skips; NOT zero cells", false, "nonlocal_state", MapHeaderRead::No, {}, "nonlocal-state" },   // also defines unanalyzed_files=
    { "aggs_capped", "aggs_capped=N: aggregates dropped past the 8000 modelling bound; not in aggregates=", false, "fieldaffinity", MapHeaderRead::No, {}, "field-affinity" },
    { "as_loops_capped", "as_loops_capped=N: loops the shape pass dropped at its cap; every as_ count is a floor", false, "fieldaffinity", MapHeaderRead::No, {}, "field-affinity" },
    { "as_query_capped", "as_query_capped=1: the shape pass hit its query budget; every as_ count is a floor", false, "fieldaffinity", MapHeaderRead::No, {}, "field-affinity" },
    { "as_uncompiled", "as_uncompiled=N: shape queries that failed to compile; their loops are unclassified", false, "fieldaffinity", MapHeaderRead::No, {}, "field-affinity" },
    { "placed", "placed=0: the model gave no offset for this field; no off=/ln= and no geometry for its pairs", true, "f", MapHeaderRead::No, {}, "field-affinity" },
    { "measured", "measured=0: an endpoint is unplaced, so no dist=/wt= and no finding for this pair", true, "pair", MapHeaderRead::No, {}, "field-affinity" },
    // …and doc-drift, deps (cycles), pr-context author/partner rows, a detached --handoff, --metrics rows, layer= on the
    //    ranked keys, clones groups, quality-delta ref pairs and acks, from-trace stale/skipped frames, stray-content, grep.
    // doc-drift: src/docdrift.h (writeDocDriftPage, writeAnchor, writeWeakDisclosures, writeTally)
    { "unchecked", "unchecked=N: anchors not proved (the unchecked rows give each reason); checked + unchecked = anchors", false, "doc-drift", MapHeaderRead::No, {}, "doc-drift" },
    { "shown_failed", "doc shown_failed=/failed_total=: a rows printed / all failed anchors (drift+dated); cut at 12, detail=1 lifts", true, "doc", MapHeaderRead::No, {}, "doc-drift" },   // also defines failed_total=
    { "kind", "a kind=/rec=: dated-record, an author-dated failed anchor in dated= / its evidence: line|block|title|stamp", true, "a", MapHeaderRead::No, {}, "doc-drift" },   // also defines rec=
    { "sym", "a sym=: the symbol the doc names on that file:line; line-moved = that symbol no longer spans the line", true, "a", MapHeaderRead::No, {}, "doc-drift" },
    { "weak", "more weak=N: w rows of this group withheld; shown_weak + N = its n=; detail=1 lists all", true, "more", MapHeaderRead::No, {}, "doc-drift" },
    { "shown_weak", "shown_weak=N: w rows printed of n= (cut at 12 a doc, weak_capped=1); detail=1 lists all", true, "weak-file-line", MapHeaderRead::No, {}, "doc-drift" },
    { "resolves-to", "w resolves-to=: the indexed symbol spanning that line; not proof it is the one the doc meant", true, "w", MapHeaderRead::No, {}, "doc-drift" },
    { "r", "unchecked r=/note=: why n= anchors were not proved, and what was still checked for them", true, "unchecked", MapHeaderRead::No, {}, "doc-drift" },   // also defines note=
    { "r", "dated r=/note=: the dating mark that moved n= failed anchors into dated= instead of drift=", true, "dated", MapHeaderRead::No, {}, "doc-drift" },   // also defines note=
    // deps: src/serialize.h packDeps (health, cycles, f rows); DepHealth in src/graph.h
    { "dep_files", "health dep_files=N: dependency-capable files (dep_langs=), the ccd/acd/nccd denominator", true, "health", MapHeaderRead::No, {}, "deps" },
    { "dep_langs", "health dep_langs=: the languages dep_files= counts; compare its numbers across builds only when equal", true, "health", MapHeaderRead::No, {}, "deps" },
    { "ccd", "ccd=/acd=/nccd=: Lakos: sum of per-file transitive cones (self incl) / per file / over a balanced tree's", true, "health", MapHeaderRead::No, {}, "deps" },   // also defines acd= nccd=
    { "shape", "health shape=: the nccd= verdict: horizontal below 1, vertical 1 to 2, tangled above 2 (a heuristic)", true, "health", MapHeaderRead::No, {}, "deps" },
    { "lazy_edges", "health lazy_edges=N: in-closure (lazy) include pairs kept OUT of cones, cycles and ccd; absent at 0", true, "health", MapHeaderRead::No, {}, "deps" },
    { "lazy_edges", "f lazy_edges=N: this file's lazy pairs; still in its inc rows, out of afferent=/instab=/transitive=", true, "f", MapHeaderRead::No, {}, "deps" },
    { "size", "cycle size=/cost=: files in that include cycle / size squared, the cycle's share of ccd=", true, "cycle", MapHeaderRead::No, {}, "deps" },   // also defines cost=
    { "cut", "cycle cut=/cutrefs=: SUGGESTED edge to break it (fewest directives) / that edge's directive count; nothing cut", true, "cycle", MapHeaderRead::No, {}, "deps" },   // also defines cutrefs=
    // pr-context: src/prcontext.h (changed-symbols, cochange partner, owners author); coPairAttr in src/gitmine.h
    { "email", "author email=/share=: a committer of this file / its fraction of the recency-weighted commits", true, "author", MapHeaderRead::No, {}, "pr-context" },   // also defines share=
    { "deg", "partner deg=: of this file's commits in window=, the fraction that partner shares", true, "partner", MapHeaderRead::No, {}, "pr-context" },
    { "surprising", "partner surprising=1: co-changes with no transitive static dependency either way (hidden coupling)", true, "partner", MapHeaderRead::No, {}, "pr-context" },
    { "dep_capable", "partner dep_capable=0: a side cannot carry a static dependency, so surprising= is undefined", true, "partner", MapHeaderRead::No, {}, "pr-context" },
    { "callers", "s callers=N: direct callers of that changed symbol; caller rows are its top shown= (callers verb: all)", true, "s", MapHeaderRead::No, {}, "pr-context" },
    { "sections", "changed-symbols sections=N: doc headings folded into count=, no row each; count minus sections = rows", true, "changed-symbols", MapHeaderRead::No, {}, "pr-context" },
    // handoff: src/handoff.h (root detached=, heuristic note rows)
    { "detached", "detached=1: HEAD is detached, so branch= reads HEAD; the commit is at=; absent on a branch", false, "handoff", MapHeaderRead::No, {}, "handoff" },
    { "target", "note target=/txt=: a committed notes row on this work (symbol id or path) and its text; a suggestion", true, "note", MapHeaderRead::No, {}, "handoff" },   // also defines txt=
    // metrics: src/serialize.h (s row metrics, f layer= via builtinLayer in src/arch.h)
    { "humps", "humps=/deep=: regions reaching the nesting bar / lines inside them; absent when nest= is under the bar", true, "s", MapHeaderRead::No, {}, "metrics" },   // also defines deep=
    { "deep_floor", "deep_floor=1: deep= is a FLOOR; a line two humps share is billed once, so deep below humps is legal", true, "s", MapHeaderRead::No, {}, "metrics" },
    { "ev", "ev=/ev_why=: essential complexity (2+: jumps block extract-method; absent: 1) / the jumps behind it, tag:count", true, "s", MapHeaderRead::No, {}, "metrics" },   // also defines ev_why=
    { "ev_floor", "ev_floor=1: ev= is a FLOOR; noreturn calls, macro-hidden exits and unresolved gotos are unseen", true, "s", MapHeaderRead::No, {}, "metrics" },
    { "ppalt", "ppalt=N: #else/#elif branches in the body; metrics sum ALL branches, no one build compiles them all", true, "s", MapHeaderRead::No, {}, "metrics" },
    { "layer", "layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none", true, "f", MapHeaderRead::No, {}, "metrics" },
    // query: src/serialize.h (f layer= via builtinLayer)
    { "layer", "layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none", true, "f", MapHeaderRead::No, {}, "query" },
    // around: src/serialize.h (f layer= via builtinLayer)
    { "layer", "layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none", true, "f", MapHeaderRead::No, {}, "around" },
    // for: src/serialize.h lens rows (d p= layer= via builtinLayer)
    { "layer", "layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none", true, "d", MapHeaderRead::No, {}, "for" },
    // pack-task: src/serialize.h lens rows (d p= layer= via builtinLayer)
    { "layer", "layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none", true, "d", MapHeaderRead::No, {}, "pack-task" },
    // clones: src/verbs_report.h emitClonesReport (groupExemptKind, cloneIdiomAttrs)
    { "exempt", "group exempt=fixture|shell-runner: every member is on such a path; quality-delta duplication ignores it", true, "group", MapHeaderRead::No, {}, "clones" },
    { "idiom", "group idiom=: the recognized shape every member spells: threshold-ladder, switch-name-table, builder-chain", true, "group", MapHeaderRead::No, {}, "clones" },
    { "demoted", "group demoted=1: idiom collision (no shared identifier or context, under 80 tokens); quality-delta: minor", true, "group", MapHeaderRead::No, {}, "clones" },
    // quality-delta: src/verbs_quality.h (range attrs, duplication r row); staleAcksXml in src/quality.h
    { "key", "sa key=/why=: the stale ack's ledger hash / target-gone (names nothing now) or finding-gone (no longer fires)", true, "sa", MapHeaderRead::No, {}, "quality-delta" },   // also defines why=
    { "members", "r members=/tokens=: a duplication row's clone group (member ids) / their shared normalized-token count", true, "r", MapHeaderRead::No, {}, "quality-delta" },   // also defines tokens=
    // #228: which git-HEAD floor answered. A zero from a self-comparison and a zero from an archived
    // comparison are different claims, so the attribute is present-only and its ABSENCE is the archived tree.
    { "head_basis", "head_basis=identity: the floor is this tree's own snapshot; archived-index-hidden: refused, a tracked path is skip-worktree/assume-unchanged; absent: the archived HEAD tree", false, "quality-delta", MapHeaderRead::No, {}, "quality-delta" },
    { "base_ref", "base_ref=/target_ref=: the two resolved full shas a range compared (committed trees; at= omitted)", false, "quality-delta", MapHeaderRead::No, {}, "quality-delta" },   // also defines target_ref=
    { "churn", "churn=unavailable: range form; short-horizon-churn cannot be measured, so its silence is not no churn", false, "quality-delta", MapHeaderRead::No, {}, "quality-delta" },
    // from-trace: src/tracelocus.h (frame and skipped rows)
    { "line", "skipped line=: that frame's line; p= is its path, outside every root, so never ranked", true, "skipped", MapHeaderRead::No, {}, "from-trace" },
    { "line_encloses", "frame line_encloses=: the other def today's line sits in; STALE trace, the name binding was kept", true, "frame", MapHeaderRead::No, {}, "from-trace" },
    // stray-content: src/crossref.h (stray-content root)
    { "unknown", "unknown=N: refs that could not be analysed (v=unknown, e.g. no merge base); never counted merged", false, "stray-content", MapHeaderRead::No, {}, "stray-content" },
    // grep: src/verbs_grep.h grepCorpusAttrs / grepUnindexedAttrs (each absent at 0)
    { "corpus_excluded", "corpus_excluded=N: files an exclude filter kept out of the index, never searched; skipped verb lists them", false, "grep", MapHeaderRead::No, {}, "grep" },
    { "corpus_oversize", "corpus_oversize=N: files the crawl saw but dropped over the size ceiling, never searched; skipped verb lists", false, "grep", MapHeaderRead::No, {}, "grep" },
    { "corpus_pruned_dirs", "corpus_pruned_dirs=N: DIRECTORIES the built-in crawl denylist pruned whole (vendor, build etc), unsearched", false, "grep", MapHeaderRead::No, {}, "grep" },
    { "unindexed_files_skipped", "unindexed_files_skipped=N: off-index candidates not read: over max-file-size, binary, or unreadable", false, "grep", MapHeaderRead::No, {}, "grep" },
    { "count", "unindexed count=N: off-index hits, equal to unindexed_hits=; paged by the same window as the f rows", true, "unindexed", MapHeaderRead::No, {}, "grep" },
    { "unindexed_candidates_capped", "unindexed_candidates_capped=1: off-index candidates cut at 500 a class, a floor; skipped verb has all", false, "grep", MapHeaderRead::No, {}, "grep" },
    // doc-drift unchecked= and stray-content unknown= pass the checker only by regex accident (checked + unchecked = anchors,
    // doc-drift shown_failed=/failed_capped=/failed_total= are emitted together only when the a listing was cut (secondaryCutAttrs);
    // deps cycle cut= is a SUGGESTED break edge (min include-directive count), not a truncation. BUT the cycles listing itself is
    // deps: f lazy_edges= (per-row) was also undefined; row added beside health lazy_edges=.
    // pr-context HEAD~1 default posture is trim_level=3 on this tree (per-symbol/cochange/owner rows dropped); author/partner/s callers
    // clones: group demoted=1 added (not seen in this tree's output, same emitter as idiom=; demoted_groups= does not define it).
    // grep: corpus_excluded=, unindexed_candidates_capped= and unindexed count= (repo-root operand) added beyond the listed three;
    // from-trace line_encloses= reproduced with a frame naming escapeXml at serialize.h:141 (inside kXmlEscapeByteset): tmp/r1-L1-fix/stale3.txt.
    // Existing house row (quality-delta r churn=) is longer than 110 chars; untouched.
    // ── TRAIN 9 (rv-r1-L1-3 LOW): the states the gate's own arms do not reach ──────────────────────────────────────
    // The L1 fix round closed every attribute the gate's roster REACHES. A 90-argv all-instances probe then found
    // fourteen more, each on a state no arm sets up: a --handoff that the token budget actually cut, a from-trace or
    // expand map over a LAYERED tree, --field-affinity's per-cause refusals (nonzero only on a big C-family corpus),
    // --external-surface with sh builtins present, and --run-trace's whole <run>/<lines> record, whose prose legend
    // the compact posture replaces with from-trace's (run-trace shares the ripwire.from-trace/v1 key). Present-only
    // as ever, so a run that reaches none of these states gains no bytes. Re-runnable: sim/train9-defaultdefs.py.
    { "budget", "budget=: the token-budget cap this packet was fitted to; est_tokens= prices what it delivers", false, "handoff", MapHeaderRead::No, {}, "handoff" },
    { "withheld_rows", "withheld_rows=N: heuristic rows the budget dropped (withheld=1 says so); verified rows are never dropped", false, "handoff", MapHeaderRead::No, {}, "handoff" },
    { "layer", "layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none", true, "d", MapHeaderRead::No, {}, "from-trace" },
    { "layer", "layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none", true, "f", MapHeaderRead::No, {}, "expand" },
    { "as_stem_ambiguous", "as_stem_ambiguous=/as_stem_unowned=/as_stem_nonptr=: chase names REFUSED - 2+ owners / no owner / owner type has no pointer marker", false, "fieldaffinity", MapHeaderRead::No, {}, "field-affinity" },   // also defines as_stem_unowned= as_stem_nonptr=
    { "builtins_excluded", "builtins_excluded=N: sh BUILTIN rows (echo printf cd exit test ...) dropped from names=; the include-builtins flag keeps them", false, "external-surface", MapHeaderRead::No, {}, "external-surface" },
    // --run-trace's record. exit=/signal=/timed_out= are mutually exclusive postures of one fact (how the command
    // ended), so they read as one row on the attribute that is present in the common case; the rest are per-attribute.
    { "exit", "run exit=: the command's OWN exit code; signal=: the signal that killed it; timed_out=1: the timeout_s= cap did", true, "run", MapHeaderRead::No, {}, "from-trace" },   // also defines signal= timed_out=
    { "duration_ms", "run duration_ms=: wall clock, MEASURED, not deterministic; timeout_s=: the cap it ran under", true, "run", MapHeaderRead::No, {}, "from-trace" },   // also defines timeout_s=
    { "lines", "run lines=: non-empty captured lines; bytes=: the whole capture; dropped_bytes=: middle bytes the cap dropped", true, "run", MapHeaderRead::No, {}, "from-trace" },   // also defines bytes= dropped_bytes=
    { "frames", "run frames=0: the command FAILED but its output carried no mappable frame, so no bundle follows", true, "run", MapHeaderRead::No, {}, "from-trace" },
    { "view", "lines view=tail: the last shown= of total= output lines; view=relevant: shown= of relevant= error/frame-shaped ones", true, "lines", MapHeaderRead::No, {}, "from-trace" },
    { "relevant", "lines relevant=N: captured lines that are error-marked or frame-shaped; the relevant view picks from these", true, "lines", MapHeaderRead::No, {}, "from-trace" },
};

// the paging window: these five mean the same on every element (L4's one-attribute-one-reading law), so they are
// read anywhere in the payload; limit=/offset= are read on the head only (a skipped <f limit=> is a size cap)
inline constexpr std::string_view kCompactPagingAttrs[] =
{
    "shown", "total", "capped", "has_more", "next_offset",
};
inline constexpr std::string_view kCompactPagingHeadAttrs[] =
{
    "offset", "limit",
};

// ── the root finder ───────────────────────────────────────────────────────────────────────────────────────

struct CompactRootInfo
{
    std::size_t      openBegin = std::string::npos;   // offset of the root's '<'
    std::size_t      nameEnd   = std::string::npos;   // offset just past the tag name
    std::size_t      openEnd   = std::string::npos;   // offset just past the root's '>'
    std::string_view tag;
    bool             hasSchema = false;
};

// The first element after optional whitespace/comments/XML declaration. Empty tag ⇒ not an XML document.
inline CompactRootInfo findCompactRoot( std::string_view doc ) noexcept
{
    CompactRootInfo r;
    std::size_t i = 0;
    while( i < doc.size() )
    {
        const char c = doc[ i ];
        if( c == ' ' || c == '\n' || c == '\t' || c == '\r' ) { ++i;  continue; }
        if( doc.substr( i ).starts_with( "<!--" ) )
        {
            const std::size_t j = doc.find( "-->", i );
            if( j == std::string_view::npos ) { return r; }
            i = j + 3;
            continue;
        }
        if( doc.substr( i ).starts_with( "<?" ) )
        {
            const std::size_t j = doc.find( "?>", i );
            if( j == std::string_view::npos ) { return r; }
            i = j + 2;
            continue;
        }
        if( c != '<' || i + 1 >= doc.size() || !std::isalpha( static_cast<unsigned char>( doc[ i + 1 ] ) ) ) { return r; }
        std::size_t k = i + 1;
        while( k < doc.size() && ( std::isalnum( static_cast<unsigned char>( doc[ k ] ) ) || doc[ k ] == '-' || doc[ k ] == '_' || doc[ k ] == ':' || doc[ k ] == '.' ) ) { ++k; }
        const std::size_t close = doc.find( '>', k );
        if( close == std::string_view::npos ) { return r; }
        r.openBegin = i;
        r.nameEnd   = k;
        r.openEnd   = close + 1;
        r.tag       = doc.substr( i + 1, k - i - 1 );
        r.hasSchema = doc.substr( k, close - k ).find( " schema=\"" ) != std::string_view::npos;
        return r;
    }
    return r;
}

// The HEAD of the document: the root's open tag plus its FIRST CHILD's open tag (the <ctx>-wrapped verbs —
// lego/skipped/notes — put their facts on the child). Completeness terms are read HERE, never from the whole
// payload: `at=` on a nonlocal-state <cell> row or `limit=` on a skipped <f> row are different attributes
// (a line, a size cap) and a legend that read them as provenance or paging would be a lie.
inline std::string_view compactDocHead( std::string_view doc, const CompactRootInfo& root ) noexcept
{
    if( root.openEnd == std::string_view::npos ) { return {}; }
    std::size_t i = root.openEnd;
    // skip comments between the root and its first child
    while( i < doc.size() )
    {
        if( doc.substr( i ).starts_with( "<!--" ) )
        {
            const std::size_t j = doc.find( "-->", i );
            i = j == std::string_view::npos ? doc.size() : j + 3;
        }
        else { break; }
    }
    std::size_t end = root.openEnd;
    if( i < doc.size() && doc[ i ] == '<' && i + 1 < doc.size() && std::isalpha( static_cast<unsigned char>( doc[ i + 1 ] ) ) )
    {
        const std::size_t j = doc.find( '>', i );
        end = j == std::string_view::npos ? doc.size() : j + 1;
    }
    return doc.substr( root.openBegin, end - root.openBegin );
}

// The root's FIRST CHILD open tag alone, or empty when the root has no child element. compactDocHead's span runs from the root to
// that tag and keeps the comments between them (lego/skipped/notes put their legends there), so the child's '<' is the span's LAST
// one: every comment ends before the child begins, and a tag spells '<' inside an attribute value as &lt;.
inline std::string_view compactFirstChildTag( std::string_view doc, const CompactRootInfo& root ) noexcept
{
    const std::string_view head    = compactDocHead( doc, root );
    const std::size_t      childAt = head.rfind( '<' );
    return childAt == std::string_view::npos || childAt == 0 ? std::string_view() : head.substr( childAt );
}

// Does `span` carry ` <attr>=<tail>`? Matched after a leading space, so `capped` never matches `hits_capped` and `bytes`
// never matches `fit_bytes`. The head reads a quoted attribute (tail `"`); the map header an unquoted field (no tail).
inline bool spanHasAttr( std::string_view span, std::string_view attr, std::string_view tail )
{
    std::string needle;
    needle.reserve( attr.size() + tail.size() + 2 );
    needle += ' ';
    needle.append( attr );
    needle += '=';
    needle.append( tail );
    return span.find( needle ) != std::string_view::npos;
}

// Does `head` carry ` <attr>="`? Matched at a tag boundary — a leading space and a trailing `="`.
inline bool headHasAttr( std::string_view head, std::string_view attr )
{
    return spanHasAttr( head, attr, "\"" );
}

// Any payload attribute ending in `_capped` (tests_capped=, importers_capped=, …) — their names, joined by '/'.
inline std::string payloadSubCapAttrs( std::string_view doc )
{
    std::string names;
    std::size_t i = 0;
    while( i < doc.size() )
    {
        if( doc.substr( i ).starts_with( "<![CDATA[" ) )
        {
            const std::size_t j = doc.find( "]]>", i );
            i = j == std::string_view::npos ? doc.size() : j + 3;
        }
        else if( doc.substr( i ).starts_with( "<!--" ) )
        {
            const std::size_t j = doc.find( "-->", i );
            i = j == std::string_view::npos ? doc.size() : j + 3;
        }
        else if( doc[ i ] == '<' )
        {
            const std::size_t j   = doc.find( '>', i );
            const std::string_view tag = doc.substr( i, j == std::string_view::npos ? doc.size() - i : j + 1 - i );
            std::size_t k = 0;
            while( ( k = tag.find( "_capped=\"", k ) ) != std::string_view::npos )
            {
                std::size_t b = k;
                while( b > 0 && ( std::isalnum( static_cast<unsigned char>( tag[ b - 1 ] ) ) || tag[ b - 1 ] == '_' ) ) { --b; }
                const std::string_view name = tag.substr( b, k + 7 - b );   // "…_capped"
                if( name != "hits_capped" )
                {
                    const std::string probe = "/" + std::string( name ) + "=";
                    if( ( "/" + names ).find( probe ) == std::string::npos )
                    {
                        if( !names.empty() ) { names += '/'; }
                        names.append( name );
                        names += '=';
                    }
                }
                k += 9;
            }
            i = j == std::string_view::npos ? doc.size() : j + 1;
        }
        else
        {
            const std::size_t j = doc.find( '<', i );
            i = j == std::string_view::npos ? doc.size() : j;
        }
    }
    return names;
}

// Is `tag` (one `<…>` span) an element named `name`? An empty name matches every element.
inline bool isElementNamed( std::string_view tag, std::string_view name ) noexcept
{
    if( name.empty() )
    {
        return true;
    }
    if( tag.size() < name.size() + 2 || tag[ 0 ] != '<' || tag.substr( 1, name.size() ) != name )
    {
        return false;
    }
    const char next = tag[ name.size() + 1 ];
    return next == ' ' || next == '/' || next == '>';
}

// Does the quoted value that opens `value` (up to its closing quote) list `item` as one whole comma-separated entry? An empty
// item accepts any value: only a valueItem term asks what the attribute holds rather than whether it is there.
inline bool quotedValueListsItem( std::string_view value, std::string_view item ) noexcept
{
    if( item.empty() )
    {
        return true;
    }
    const std::string_view list  = value.substr( 0, value.find( '"' ) );
    std::size_t            begin = 0;
    while( begin <= list.size() )
    {
        std::size_t end = list.find( ',', begin );
        if( end == std::string_view::npos )
        {
            end = list.size();
        }
        if( list.substr( begin, end - begin ) == item )
        {
            return true;
        }
        begin = end + 1;
    }
    return false;
}

// Row-level terms: does ANY tag outside comments/CDATA carry ` <attr>="`? With `onTag`, only a `<onTag …>` element counts; with
// `valueItem`, only a value that lists that item.
inline bool payloadHasAnyAttr( std::string_view doc, std::string_view attr, std::string_view onTag = {}, std::string_view valueItem = {} )
{
    std::string needle;
    needle.reserve( attr.size() + 3 );
    needle += ' ';
    needle.append( attr );
    needle += "=\"";
    std::size_t i = 0;
    while( i < doc.size() )
    {
        if( doc.substr( i ).starts_with( "<![CDATA[" ) )
        {
            const std::size_t j = doc.find( "]]>", i );
            i = j == std::string_view::npos ? doc.size() : j + 3;
        }
        else if( doc.substr( i ).starts_with( "<!--" ) )
        {
            const std::size_t j = doc.find( "-->", i );
            i = j == std::string_view::npos ? doc.size() : j + 3;
        }
        else if( doc[ i ] == '<' )
        {
            const std::size_t j = doc.find( '>', i );
            const std::string_view tag = doc.substr( i, j == std::string_view::npos ? doc.size() - i : j + 1 - i );
            const std::size_t at = tag.find( needle );
            if( at != std::string_view::npos && isElementNamed( tag, onTag ) && quotedValueListsItem( tag.substr( at + needle.size() ), valueItem ) ) { return true; }
            i = j == std::string_view::npos ? doc.size() : j + 1;
        }
        else
        {
            const std::size_t j = doc.find( '<', i );
            i = j == std::string_view::npos ? doc.size() : j;
        }
    }
    return false;
}

// The opener of the map header's data comment (serialize.h buildStats, its one emitter).
inline constexpr std::string_view kCompactMapHeaderOpener = "<!-- files=";

// The first comment outside CDATA that opens with `opener` (which itself starts `<!--`), or empty when the document has none. A
// well-formed document spells `<!--` raw only in a comment or a CDATA body, and a comment cannot hold `--`, so the first hit
// outside CDATA IS that comment.
inline std::string_view compactCommentOpenedBy( std::string_view doc, std::string_view opener ) noexcept
{
    for( std::size_t hit = doc.find( opener ); hit != std::string_view::npos; hit = doc.find( opener, hit + 1 ) )
    {
        const std::size_t cdataOpen = doc.rfind( "<![CDATA[", hit );
        const bool        isInCdata = cdataOpen != std::string_view::npos && doc.find( "]]>", cdataOpen ) > hit;
        if( !isInCdata )
        {
            const std::size_t close = doc.find( "-->", hit );
            return doc.substr( hit, close == std::string_view::npos ? doc.size() - hit : close + 3 - hit );
        }
    }
    return {};
}

// The map header comment (before the root, or trailing under order=stable), or empty when the document has none: every
// verb outside the map family and the bundles that embed it.
inline std::string_view compactMapHeader( std::string_view doc ) noexcept
{
    return compactCommentOpenedBy( doc, kCompactMapHeaderOpener );
}

// Does this document carry term `t`? An element-qualified term reads its element alone (the head can carry the same NAME
// as a different attribute); a map-header term reads the kept header's unquoted field too (Also) or instead (Only).
inline bool isCompletenessTermPresent( const CompactCompletenessTerm& t, std::string_view head, std::string_view doc, std::string_view mapHeader )
{
    if( t.mapHeader != MapHeaderRead::No && spanHasAttr( mapHeader, t.attr, {} ) )
    {
        return true;
    }
    if( t.mapHeader == MapHeaderRead::Only )
    {
        return false;
    }
    if( !t.onTag.empty() )
    {
        return payloadHasAnyAttr( doc, t.attr, t.onTag, t.valueItem );
    }
    return headHasAttr( head, t.attr ) || ( t.wholeDoc && payloadHasAnyAttr( doc, t.attr ) );
}

// THE WITHHELD-MAP RECORD (L1 fix round, rv-r1-L1 MED-3). The default map's --token-budget gate replaces an over-budget map
// with ONE empty record, <r withheld_est_tokens= budget= withheld="1"/> (main.cpp finishTokenBudgetGate). It keeps the schema
// of the verb that asked (map, map-diff, metrics — compactlegendcheck D38), but it carries no row, so the map family's purpose
// line (<f>/<s>/<c> rows) described a shape it does not have, and the handoff reading of withheld= ("rows the budget cut")
// read as one row cut. The record's own reading replaces the purpose; withheld_est_tokens= is its unique mark (a map never
// carries it: the priced map says est_tokens=).
inline constexpr std::string_view kCompactWithheldMapPurpose =
    "the ranked map WITHHELD whole, no rows: withheld=1 marks this record, withheld_est_tokens= the map's price, over "
    "budget= (the token budget asked); rerun with a larger token budget, or max-tokens to shape a map that fits";

[[nodiscard]] inline bool isWithheldMapRecord( const CompactLegendSpec& spec, std::string_view head )
{
    return spec.rootTag == "r" && headHasAttr( head, "withheld_est_tokens" );
}

// The paging-window clause of one compact legend — " window: shown= … (capped=1 cut)." — or empty when the payload
// carries none of the window names. Split out of compactLegendText (lane r2-LO) so the ref posture (legenddict.h) can
// name the exact bytes the compact legend spends on it; the composition below is unchanged byte for byte.
inline std::string compactWindowClause( std::string_view head, std::string_view doc )
{
    std::string window;
    for( std::string_view a : kCompactPagingAttrs )
    {
        if( payloadHasAnyAttr( doc, a ) )
        {
            if( !window.empty() ) { window += ' '; }
            window.append( a );
            window += '=';
        }
    }
    for( std::string_view a : kCompactPagingHeadAttrs )
    {
        if( headHasAttr( head, a ) )
        {
            if( !window.empty() ) { window += ' '; }
            window.append( a );
            window += '=';
        }
    }
    if( window.empty() )
    {
        return {};
    }
    return " window: " + window + ( payloadHasAnyAttr( doc, "next_offset" ) ? " (capped=1 cut; next_offset= pastes as offset=)." : " (capped=1 cut)." );
}

// The sub-cap clause — " importers_capped=/…: 1 = cut." — or empty when no payload attribute ends in _capped.
inline std::string compactSubcapClause( std::string_view doc )
{
    std::string clause = payloadSubCapAttrs( doc );
    if( !clause.empty() )
    {
        clause.insert( clause.begin(), ' ' );
        clause += ": 1 = cut.";
    }
    return clause;
}

// THE TWO READING TABLES, ONE INDEX SPACE (merge of L1's second table with lane r2-LO's split-out helpers).
// compactLegendText reads the tool-wide completeness vocabulary first, then L1's key-qualified per-verb readings, so an
// index below kCompactTermCount names kCompactCompletenessTerms and any higher one names kCompactAttributeReadings.
// legenddict.h's entry ids ride this same order, which is why the concatenation lives here rather than in the composer.
inline constexpr std::size_t kCompactTermCount    = std::size( kCompactCompletenessTerms );
inline constexpr std::size_t kCompactReadingCount = kCompactTermCount + std::size( kCompactAttributeReadings );

[[nodiscard]] inline const CompactCompletenessTerm& compactReading( std::size_t i ) noexcept
{
    EXPECTS( i < kCompactReadingCount );
    return i < kCompactTermCount ? kCompactCompletenessTerms[ i ] : kCompactAttributeReadings[ i - kCompactTermCount ];
}

// The readings this document carries, as indices into that joint space, in table order. `key` is the answer's schema key:
// a key-qualified reading (L1's onKey) belongs to that verb alone, so passing the key gives EXACTLY the legend's own set.
// An EMPTY key applies no key filter and so returns a superset — which is all the `for` dialect's substring strip needs.
inline std::vector<std::uint16_t> compactPresentTerms( std::string_view head, std::string_view doc, std::string_view key = {} )
{
    static_assert( kCompactReadingCount < 0xFFFFu, "reading indices are 16-bit" );
    std::vector<std::uint16_t> present;
    const std::string_view mapHeader = compactMapHeader( doc );
    for( std::size_t i = 0; i < kCompactReadingCount; ++i )
    {
        const CompactCompletenessTerm& t = compactReading( i );
        const bool keyMatches = t.onKey.empty() || key.empty() || t.onKey == key;
        if( keyMatches && isCompletenessTermPresent( t, head, doc, mapHeader ) )
        {
            present.push_back( static_cast<std::uint16_t>( i ) );
        }
    }
    return present;
}

// The opener every compact legend starts with: "<!-- ripwire KEY schema=ripwire.KEY/v1: ".
inline std::string compactLegendOpener( const CompactLegendSpec& spec )
{
    std::string out = "<!-- ripwire ";
    out.append( spec.key );
    out += " schema=ripwire.";
    out.append( spec.key );
    out += "/v1: ";
    return out;
}

// The compact legend for one document: schema id, purpose, paging window, sub-caps, and every present reading.
inline std::string compactLegendText( const CompactLegendSpec& spec, std::string_view head, std::string_view doc )
{
    std::string out;
    out.reserve( 400 );
    out += compactLegendOpener( spec );
    out.append( isWithheldMapRecord( spec, head ) ? kCompactWithheldMapPurpose : spec.purpose );
    out += '.';
    // the paging window, one clause, present names only
    out += compactWindowClause( head, doc );
    out += compactSubcapClause( doc );
    for( const std::uint16_t i : compactPresentTerms( head, doc, spec.key ) )
    {
        out += ' ';
        out.append( compactReading( i ).reading );
        out += '.';
    }
    // #60: the module-scope owner is the one kind that arrives under a dozen different spellings —
    // <s t="modscope">, a columnar <kind> array item, <h n=>, <edge caller=>, <u sym=>, <c n=>, <t t=> —
    // so keying this reading on an element or an attribute would have to enumerate them and would miss the
    // next one. It keys on the NAME instead, which every surface escapes identically and which no source
    // identifier can collide with (angle brackets are not a legal identifier in any indexed language).
    // Present-only like every reading above: a document without such a row pays 0 bytes. It sits outside
    // compactPresentTerms deliberately — that function answers "which TERM-TABLE rows are present", and this
    // reading is not one of them (test/compactlegendcheck.sh arm (S) proves it live instead of by a row).
    if( doc.find( kModScopeEscapedName ) != std::string_view::npos )
    {
        out += ' ';
        out.append( kCompactModScopeReading );
        out += '.';
    }
    out += " -->";
    return out;
}

// ── the roster closure (lane r2-LO) ──────────────────────────────────────────────────────────────────────────
// Does any comment of `doc` outside CDATA spell `attr=` (the definitional form every legend here uses)?
inline bool commentsSpellAttr( std::string_view doc, std::string_view attr )
{
    std::string needle( attr );
    needle += '=';
    std::size_t i = 0;
    while( i < doc.size() )
    {
        const std::size_t cdata   = doc.find( "<![CDATA[", i );
        const std::size_t comment = doc.find( "<!--", i );
        if( comment == std::string_view::npos )
        {
            return false;
        }
        if( cdata != std::string_view::npos && cdata < comment )
        {
            const std::size_t j = doc.find( "]]>", cdata );
            i = j == std::string_view::npos ? doc.size() : j + 3;
            continue;
        }
        const std::size_t close = doc.find( "-->", comment );
        const std::string_view text = doc.substr( comment, close == std::string_view::npos ? doc.size() - comment : close - comment );
        for( std::size_t at = text.find( needle ); at != std::string_view::npos; at = text.find( needle, at + 1 ) )
        {
            const char before = at == 0 ? ' ' : text[ at - 1 ];
            if( !std::isalnum( static_cast<unsigned char>( before ) ) && before != '_' )
            {
                return true;
            }
        }
        i = close == std::string_view::npos ? doc.size() : close + 3;
    }
    return false;
}

// A NATIVE-legend answer (one this layer does not rewrite: the MCP `for` bundle) that carries a completeness attribute
// its own legend never spells gets that attribute's compact reading, in ONE comment after the comments that open the
// root. The class it closes, generally: a completeness attribute riding an answer undefined — found on MCP `for` as
// at= (stamped on the root, defined nowhere), ccx= (cx= alone was read) and next= (on the r=1 row). On a compact answer
// it is a no-op by construction: compactLegendText reads every present term. Returns whether anything was added.
inline bool closeRosterGaps( std::string& doc )
{
    const CompactRootInfo root = findCompactRoot( doc );
    if( root.tag.empty() )
    {
        return false;
    }
    const std::string_view view = doc;
    std::string add;
    for( const std::uint16_t i : compactPresentTerms( compactDocHead( view, root ), view ) )
    {
        // compactPresentTerms returns a JOINT index over both reading tables, so it is resolved by compactReading and
        // never by subscripting the first table — which is only 92 long and would be read past for every key-qualified
        // reading the second table holds.
        const CompactCompletenessTerm& t = compactReading( i );
        if( !commentsSpellAttr( view, t.attr ) && add.find( std::string( t.attr ) + "=" ) == std::string::npos )
        {
            add += ' ';
            add.append( t.reading );
            add += '.';
        }
    }
    if( add.empty() )
    {
        return false;
    }
    // After the comments that follow the root's open tag (the legend a reader meets first), before the first row.
    std::size_t at = root.openEnd;
    while( view.substr( at ).starts_with( "<!--" ) )
    {
        const std::size_t close = view.find( "-->", at );
        if( close == std::string_view::npos )
        {
            break;
        }
        at = close + 3;
    }
    doc.insert( at, "<!--" + add + " -->" );
    return true;
}

// ── the root finder + the rewrite ─────────────────────────────────────────────────────────────────────────

// The spec for (root tag, hint). A hint names the key when the root is shared (`r`, `ctx`); an empty hint
// takes the first entry for the tag. nullptr ⇒ this root has no compact legend.
inline const CompactLegendSpec* findCompactSpec( std::string_view rootTag, std::string_view hint ) noexcept
{
    const CompactLegendSpec* first = nullptr;
    for( const CompactLegendSpec& s : kCompactLegendSpecs )
    {
        if( s.rootTag != rootTag ) { continue; }
        if( !hint.empty() && s.key == hint ) { return &s; }
        if( first == nullptr ) { first = &s; }
    }
    return first;
}

enum class CompactOutcome : std::uint8_t
{
    Rewritten,      // compact legend applied
    AlreadyCompact, // a native compact root (schema= present) this table does not know — left alone
    NotXml,         // no root element — nothing to compact
    UnknownRoot,    // an XML root this table does not know — nothing honest to say, so nothing changes
};

// Rewrite `doc` in place: prose comments out, ONE compact legend in (at the position of the first prose
// comment, or right after the root open tag when the full dialect had none), schema= on the root.
// ── THE PRICE FOLLOWS THE BYTES (L1, 2026-09-19) ─────────────────────────────────────────────────────────
// A document's est_tokens= prices what its emitter WROTE, and this layer then takes the prose legend out of it — so,
// unrepriced, a compacted answer carried the FULL dialect's price: --connect on this repo priced 1,200 tokens for
// 1,037 delivered bytes (attrvocabcheck §4, truth ~414). While compact was opt-in that was waved through as "an
// upper bound under compact"; with compact the CLI default (and the MCP default since M1) the bound was ~3x on the
// small answers compact exists for, and a caller budgeting on it pages or refuses an answer that fits.
//
// The rewrite changes MARKUP only (prose comments out; one legend and schema= in; rows, attributes and CDATA bodies
// untouched), so the price moves by the net markup bytes. REMOVED bytes are priced at the document's OWN average
// rate (bytes / est_tokens): the emitter priced its markup at a per-corpus rate (2.36..2.55 B/token) and any bodies
// at 3.80, so the average is never BELOW the markup rate the legend was charged at — removing at the average takes
// out at most the legend's true tokens, never more, and for a body-free document it is exact. ADDED bytes (a compact
// legend longer than the prose it replaced — rare) are priced at the DENSEST markup rate (kMinBytesPerToken, 2.36;
// main.cpp static_asserts the two agree), the most tokens a byte can cost. Both directions round toward over-reading,
// so the repriced number never under-reads the document and the compact reading "price as emitted (an upper bound
// under compact)" stays true as written — now a tight bound. Two places carry a price: the priced root (M11) and the
// map header's data field (est_tokens= rides there alone under order=stable). Each is moved from its OWN value. A
// document with no price keeps none.
inline constexpr double kCompactRepriceDensestBytesPerToken = 2.36;

// The repriced value of one est_tokens= field whose document went from fullBytes to compactBytes.
[[nodiscard]] inline long long compactRepricedTokens( long long oldTokens, std::size_t fullBytes, std::size_t compactBytes ) noexcept
{
    EXPECTS( oldTokens > 0 && fullBytes > 0, "a priced document has bytes and a positive price" );
    if( compactBytes <= fullBytes )
    {
        // The document's average rate, QUANTISED to the nearest 0.05 B/token: a price must not move with bytes the rewrite
        // did not touch (runtracecheck (G2): duration_ms="9" vs "1064" is 3 bytes of digits, and an exact ratio turned that
        // into a one-token price change). Nearest, not up: a document priced at exactly 2.50 (--pr-context) reprices exactly
        // (prbudgetcheck #9 recounts to +/-1); the rounding moves the rate by at most 0.025, about 1%.
        const double    rate    = std::round( double( fullBytes ) / double( oldTokens ) * 20.0 ) / 20.0;
        const double    removed = double( fullBytes - compactBytes ) / rate;
        const long long next    = oldTokens - static_cast<long long>( removed );   // floor: the fewest tokens removed
        return next > 0 ? next : 1;
    }
    const double    added = double( compactBytes - fullBytes ) / kCompactRepriceDensestBytesPerToken;
    const long long whole = static_cast<long long>( added );
    return oldTokens + ( double( whole ) < added ? whole + 1 : whole );   // ceil: the most tokens added
}

// Reprice the first ` est_tokens=` field (optionally quoted) inside [begin, end) of `doc`. The key must start an
// attribute/field (preceded by a space) so withheld_est_tokens= is never read as the price. Returns false when the
// span carries no such field or its value is not a plain integer (a "~N" spelling is not a price this layer moves).
inline bool repriceEstTokensIn( std::string& doc, std::size_t begin, std::size_t end, std::size_t fullBytes, std::size_t compactBytes )
{
    constexpr std::string_view kKey = "est_tokens=";
    std::size_t k = doc.find( kKey, begin );
    while( k != std::string::npos && k < end && k > 0 && doc[ k - 1 ] != ' ' )
    {
        k = doc.find( kKey, k + 1 );
    }
    if( k == std::string::npos || k >= end )
    {
        return false;
    }
    std::size_t d = k + kKey.size();
    if( d < end && doc[ d ] == '"' ) { ++d; }
    std::size_t e = d;
    while( e < end && std::isdigit( static_cast<unsigned char>( doc[ e ] ) ) ) { ++e; }
    long long oldTokens = 0;
    if( e == d || std::from_chars( doc.data() + d, doc.data() + e, oldTokens ).ec != std::errc() || oldTokens <= 0 )
    {
        return false;
    }
    const long long newTokens = compactRepricedTokens( oldTokens, fullBytes, compactBytes );
    ENSURES( newTokens > 0, "a delivered document is never priced at zero tokens" );
    doc.replace( d, e - d, std::to_string( newTokens ) );
    return true;
}

// ── THE BUDGET LEDGER IS DATA (L1, 2026-09-19) ──────────────────────────────────────────────────────────────────
// --pack-task ends its legend comment with a pipe-separated LEDGER of what the budget did to each section:
// "budget=3186 bytes (1500-token target, ceiling 3540) | ranking: capped | bodies: kept 1 of 6 (capped) | callers:
// omitted (budget) | notes: none | tests: none | far: omitted (budget) | task_echo: dropped (ceiling)". Some of those
// facts ride attributes too (<sigs capped=>, <bodies shown= total=>), but "callers: omitted (budget)" and "far: omitted
// (budget)" are a SECTION the budget cut whole, and no attribute states it — dropping the ledger with the prose would
// have hidden a cut (METHODOLOGY §9.3: never cut silently). So when a prose comment carries the ledger, its ledger
// survives compaction verbatim as its own data comment, `<!-- ledger: budget=… -->`, in the comment's place. The shape
// is --pack-task's (packtask.h builds it: "budget=N bytes (T-token target, ceiling C) | …" to the comment's end);
// a comment without it contributes nothing.
//
// THE SAME RULE, TWO MORE SHAPES (L1 fix round, rv-r1-L1 MED-1/MED-2; owner ruling: compact shortens the DICTIONARY, never
// a disclosure). --from-trace states the ceiling it ACTUALLY applied in one sentence of its prose legend (tracelocus.h:
// "budget=N bytes (allowance M bytes = ceiling + the single-entry overshoot a whole first signature costs).") and no
// attribute carries M; --notes' only statement of its counts is the prose header "ripwire field notes: notes=N targets=N
// dangling=N (…)" (main.cpp), and the <notes> root carries no attribute. Both are kept as data: the trace ledger to its
// closing parenthesis, the notes counts as `<!-- notes=N targets=N dangling=N -->` (their readings ride the notes purpose).
inline std::string compactKeptLedger( std::string_view comment )
{
    constexpr std::string_view kClose = " -->";
    if( !comment.ends_with( kClose ) )
    {
        return {};
    }
    constexpr std::string_view kNotesOpen = "<!-- ripwire field notes: ";
    if( comment.starts_with( kNotesOpen ) )
    {
        const std::string_view rest   = comment.substr( kNotesOpen.size() );
        const std::size_t      counts = rest.find( " (" );
        return counts == std::string_view::npos || !rest.starts_with( "notes=" ) ? std::string()
                                                                                 : "<!-- " + std::string( rest.substr( 0, counts ) ) + " -->";
    }
    constexpr std::string_view kOpen = " budget=";
    for( std::size_t at = comment.find( kOpen ); at != std::string_view::npos; at = comment.find( kOpen, at + 1 ) )
    {
        std::size_t d = at + kOpen.size();
        const std::size_t digits = d;
        while( d < comment.size() && std::isdigit( static_cast<unsigned char>( comment[ d ] ) ) ) { ++d; }
        const std::string_view rest = comment.substr( d );
        if( d == digits || !rest.starts_with( " bytes (" ) )
        {
            continue;
        }
        const std::size_t shape = rest.find( "-token target, ceiling " );
        if( shape != std::string_view::npos && shape <= 40 )
        {
            const std::string_view ledger = comment.substr( at + 1, comment.size() - kClose.size() - ( at + 1 ) );
            return "<!-- ledger: " + std::string( ledger ) + " -->";
        }
        if( rest.starts_with( " bytes (allowance " ) )
        {
            const std::size_t close = rest.find( ')' );
            if( close != std::string_view::npos )
            {
                return "<!-- ledger: " + std::string( comment.substr( at + 1, d - ( at + 1 ) ) ) + std::string( rest.substr( 0, close + 1 ) ) + " -->";
            }
        }
    }
    return {};
}

// `priceBasisBytes`: the size of the document its est_tokens= was PRICED for, when that is not `doc` itself — the
// over_ceiling settle below removes a label from the original after its emitter priced it (0 = doc.size()).
inline CompactOutcome applyCompactDialectOnce( std::string& doc, std::string_view hint, std::size_t priceBasisBytes = 0 )
{
    const CompactRootInfo root = findCompactRoot( doc );
    if( root.tag.empty() ) { return CompactOutcome::NotXml; }
    // …and the ROOT says which serving this is, for the one verb that has two (see the expand rows above).
    //
    // THE ROOT TAG, NOT THE DOCUMENT (CodeRabbit 5216..., PR #215). This searched the WHOLE document, and an
    // --expand BUNDLE carries its bodies as CDATA: any body that merely MENTIONS the literal `mode="whole-file"`
    // — a gate script that greps for it, a doc that quotes it, this repository's own test/scroundtripcheck.sh —
    // selected the expand-file legend for a document made of <bodies>/<b>/<calls>. REPRODUCED on a 400-function
    // Python fixture whose first body holds the string: the root printed mode="bundle" reason="bundle 1957B <=
    // file 11844B" and served <bodies>, under a legend reading `<src p= sym=>; <s n= sc= l=/>`. That is the very
    // defect the expand-file row exists to fix, pointed the other way — a legend describing a shape the document
    // does not contain. The serving mode is a ROOT ATTRIBUTE and is read only there.
    std::string_view       effectiveHint = hint;
    const std::string_view rootOpen      = std::string_view( doc ).substr( root.openBegin, root.openEnd - root.openBegin );
    if( hint == "expand" && rootOpen.find( " mode=\"whole-file\"" ) != std::string_view::npos )
    {
        effectiveHint = "expand-file";
    }
    const CompactLegendSpec* spec = findCompactSpec( root.tag, effectiveHint );
    if( spec == nullptr ) { return root.hasSchema ? CompactOutcome::AlreadyCompact : CompactOutcome::UnknownRoot; }
    const bool rootCarriesRoute = rootOpen.find( " route=\"" ) != std::string_view::npos;

    // pass 1: the legend text is computed from the ORIGINAL document (payload attributes are unchanged by the
    // rewrite, so scanning before or after is the same; before keeps the two passes independent)
    const std::string legend = compactLegendText( *spec, compactDocHead( doc, root ), doc );

    // pass 2: copy, dropping prose comments; remember where the first one stood
    std::string out;
    out.reserve( doc.size() + legend.size() + 40 );
    std::size_t firstProseAt = std::string::npos;
    std::size_t i = 0;
    const std::size_t n = doc.size();
    std::size_t rootOpenBeginInOut = std::string::npos;
    while( i < n )
    {
        if( std::string_view( doc ).substr( i ).starts_with( "<![CDATA[" ) )
        {
            const std::size_t j = doc.find( "]]>", i );
            const std::size_t e = j == std::string::npos ? n : j + 3;
            out.append( doc, i, e - i );
            i = e;
        }
        else if( std::string_view( doc ).substr( i ).starts_with( "<!--" ) )
        {
            const std::size_t j = doc.find( "-->", i );
            const std::size_t e = j == std::string::npos ? n : j + 3;
            const std::string_view comment( doc.data() + i, e - i );
            // L1: the router note is prose only where the root restates it as route= (--for); on a root with no
            // route= (--query's map) it is the ONE carrier of the route decision and its anchors, so it stays.
            const bool soleRouteCarrier = comment.starts_with( "<!-- routed: " ) && !rootCarriesRoute;
            if( isCompactProseComment( comment ) && !soleRouteCarrier )
            {
                if( firstProseAt == std::string::npos ) { firstProseAt = out.size(); }
                out += compactKeptLedger( comment );   // the budget ledger's FACTS survive the prose (empty when none)
            }
            else
            {
                out.append( comment );
            }
            i = e;
        }
        else if( i == root.openBegin )
        {
            // the root open tag, with schema= spliced right after the name
            rootOpenBeginInOut = out.size();
            out.append( doc, i, root.nameEnd - i );
            if( !root.hasSchema )   // a native compact root (grep/slice) already carries its id
            {
                out += " schema=\"ripwire.";
                out.append( spec->key );
                out += "/v1\"";
            }
            out.append( doc, root.nameEnd, root.openEnd - root.nameEnd );
            i = root.openEnd;
        }
        else
        {
            std::size_t j = doc.find( '<', i + 1 );
            if( j == std::string::npos ) { j = n; }
            // never skip past the root open tag or a construct we must inspect
            if( root.openBegin > i && root.openBegin < j ) { j = root.openBegin; }
            out.append( doc, i, j - i );
            i = j;
        }
    }
    // A document whose full dialect had NO prose comment (--scan-skills, the withheld-map record <r … withheld="1"/>, which is
    // self-closing and has no inside at all) gets its legend in FRONT of the root, where a reader meets it first — as the
    // leading legend every other verb opens with — instead of inside or after the root (L1 fix round, MED-3/HIGH-1).
    const std::size_t at = firstProseAt != std::string::npos ? firstProseAt
                         : ( rootOpenBeginInOut != std::string::npos ? rootOpenBeginInOut : out.size() );
    out.insert( at, legend );
    // the price follows the bytes (see compactRepricedTokens): the root's est_tokens=, then the map header's field
    const std::size_t compactBytes = out.size();
    const std::size_t pricedBytes  = priceBasisBytes > 0 ? priceBasisBytes : doc.size();
    if( compactBytes != pricedBytes )
    {
        const CompactRootInfo outRoot = findCompactRoot( out );
        if( !outRoot.tag.empty() )
        {
            repriceEstTokensIn( out, outRoot.openBegin, outRoot.openEnd, pricedBytes, compactBytes );
        }
        const std::string_view header = compactMapHeader( out );
        if( !header.empty() )
        {
            const std::size_t hb = static_cast<std::size_t>( header.data() - out.data() );
            repriceEstTokensIn( out, hb, hb + header.size(), pricedBytes, compactBytes );
        }
    }
    doc.swap( out );
    return CompactOutcome::Rewritten;
}

// ── over_ceiling= FOLLOWS THE PRICE (L1, 2026-09-19) ──────────────────────────────────────────────────────
// over_ceiling="1" says est_tokens exceeds a ceiling THE ROOT NAMES (budget_tokens= / max_tokens=; verbs_for.h F2,
// the same predicate on --pack-task). The emitter decided it on the FULL document's price; once the layer reprices
// the compacted answer (compactRepricedTokens) the label can be stale — --pack-task at --token-budget=1200 printed
// est_tokens="1111" over_ceiling="1" (w3fixbudgetcheck's biconditional, red). So the compacted root is read back:
// if the label disagrees with the repriced number against the ceilings the root names, the ORIGINAL document's label
// is corrected and it is compacted again — the legend is built from the document, so its over_ceiling= reading
// appears exactly when the attribute does. Removing the label only shrinks the answer and adding it only grows it,
// so one correction settles it. A root that names no ceiling is never touched.
[[nodiscard]] inline std::size_t rootUnsignedAttr( std::string_view rootOpen, std::string_view name ) noexcept
{
    const std::string key = " " + std::string( name ) + "=\"";
    const std::size_t at  = rootOpen.find( key );
    if( at == std::string_view::npos )
    {
        return 0;
    }
    std::size_t value = 0;
    const char* first = rootOpen.data() + at + key.size();
    const char* last  = rootOpen.data() + rootOpen.size();
    return std::from_chars( first, last, value ).ec == std::errc() ? value : 0;
}

// The kept --pack-task ledger's last rung clause (packtask.h kNotes.overCeiling: " | over_ceiling: … no section left to trim")
// states the same verdict as the label. When the settle removes the label, the clause goes with it, or the default answer
// carries two facts that disagree (rv-r1-L1 MED-4: a settled root with no over_ceiling= beside a ledger saying the floor is
// over). The clause runs to the next " | " field or the comment's end.
inline void eraseLedgerOverCeilingClause( std::string& doc )
{
    constexpr std::string_view kClause = " | over_ceiling: ";
    const std::size_t at = doc.find( kClause );
    if( at == std::string::npos )
    {
        return;
    }
    const std::size_t nextField = doc.find( " | ", at + kClause.size() );
    const std::size_t close     = doc.find( " -->", at + kClause.size() );
    const std::size_t end       = std::min( nextField, close );
    if( end != std::string::npos )
    {
        doc.erase( at, end - at );
    }
}

// Returns true when `original`'s root label was corrected (the caller compacts it again).
inline bool settleOverCeilingLabel( std::string& original, std::string_view compacted )
{
    constexpr std::string_view kLabel = " over_ceiling=\"1\"";
    const CompactRootInfo outRoot = findCompactRoot( compacted );
    const CompactRootInfo inRoot  = findCompactRoot( original );
    if( outRoot.tag.empty() || inRoot.tag.empty() )
    {
        return false;
    }
    const std::string_view outOpen = compacted.substr( outRoot.openBegin, outRoot.openEnd - outRoot.openBegin );
    const std::size_t budget = rootUnsignedAttr( outOpen, "budget_tokens" );
    const std::size_t maxTok = rootUnsignedAttr( outOpen, "max_tokens" );
    const std::size_t est    = rootUnsignedAttr( outOpen, "est_tokens" );
    if( ( budget == 0 && maxTok == 0 ) || est == 0 )
    {
        return false;   // no named ceiling, or no price: nothing this rule can judge
    }
    const bool shouldBeOver = ( budget > 0 && est > budget ) || ( maxTok > 0 && est > maxTok );
    const std::string_view inOpen = std::string_view( original ).substr( inRoot.openBegin, inRoot.openEnd - inRoot.openBegin );
    // --pr-context states the same fact in its own vocabulary: truncated="…;budget-floor-exceeded" (prcontext.h) says
    // even the smallest renderable document is over max_tokens=. Once the compacted answer fits, that claim is false.
    // Two spellings: appended to a trim level (";budget-floor-exceeded"), or the whole value on a clean tree whose
    // floor alone was over (truncated="budget-floor-exceeded") — there the attribute goes, and its reading with it.
    constexpr std::string_view kFloorToken = ";budget-floor-exceeded";
    constexpr std::string_view kFloorAttr  = " truncated=\"budget-floor-exceeded\"";
    if( !shouldBeOver && outOpen.find( "budget-floor-exceeded" ) != std::string_view::npos )
    {
        for( const std::string_view spelling : { kFloorAttr, kFloorToken } )
        {
            const std::size_t at = inOpen.find( spelling );
            if( at != std::string_view::npos )
            {
                original.erase( inRoot.openBegin + at, spelling.size() );
                return true;
            }
        }
    }
    const bool isOver = outOpen.find( kLabel ) != std::string_view::npos;
    if( shouldBeOver == isOver )
    {
        return false;
    }
    if( isOver )
    {
        const std::size_t at = inOpen.find( kLabel );
        if( at == std::string_view::npos )
        {
            return false;   // the label was not the emitter's (never happens: the layer adds no attribute but schema=)
        }
        original.erase( inRoot.openBegin + at, kLabel.size() );
        eraseLedgerOverCeilingClause( original );
        return true;
    }
    const std::size_t estAt = inOpen.find( " est_tokens=\"" );
    if( estAt == std::string_view::npos )
    {
        return false;
    }
    const std::size_t estEnd = inOpen.find( '"', estAt + 13 );
    if( estEnd == std::string_view::npos )
    {
        return false;
    }
    original.insert( inRoot.openBegin + estEnd + 1, kLabel );
    return true;
}

inline CompactOutcome applyCompactDialect( std::string& doc, std::string_view hint )
{
    std::string       original    = doc;
    const std::size_t pricedBytes = doc.size();   // what the emitter's est_tokens= describes
    CompactOutcome    outcome     = applyCompactDialectOnce( doc, hint );
    if( outcome == CompactOutcome::Rewritten && settleOverCeilingLabel( original, doc ) )
    {
        doc = original;
        outcome = applyCompactDialectOnce( doc, hint, pricedBytes );
        ENSURES( outcome == CompactOutcome::Rewritten, "a label correction never changes whether the root has a compact dialect" );
    }
    // NOT moved here: --expand's reason="file NB < bundle MB". Both numbers are the FULL dialect's prices of the two
    // candidates the M6 choice compared (main.cpp chooseExpandServe), and moving only the served one made the stated
    // comparison false ("file 1292B < bundle 1267B", expandmodecheck (4c)); the choice itself is made on full-dialect
    // prices — recorded in the L1 lane report as a found item, not papered over with one corrected number.
    return outcome;
}

// ── THE DELIVERED PRICE, ASKED BEFORE THE CUT (L1 fix round, rv-r1-L1 MED-4) ────────────────────────────────────────
// Emitters trim to a budget BEFORE this layer runs, so a trim ladder that prices its candidates as written prices the full
// dialect's prose — prose a compact-posture run never delivers. --pr-context=REF --token-budget=4000 delivered 1,977 tokens
// at trim_level=4 while the full answer fit 3,951 of 4,000 with the same rows: the default cut files that fit. An emitter
// running under the compact posture asks THIS for the price the root will print once the layer has compacted the candidate
// (the same rewrite, reprice and over_ceiling settle), and trims against that. Returns 0 when the candidate has no price the
// layer would print (not XML, no compact dialect, no est_tokens=): the caller then keeps its own number.
[[nodiscard]] inline std::size_t compactDeliveredEstTokens( std::string_view candidate, std::string_view hint )
{
    EXPECTS( !candidate.empty(), "a trim ladder prices a rendered candidate, never an empty one" );
    std::string doc( candidate );
    if( applyCompactDialect( doc, hint ) != CompactOutcome::Rewritten )
    {
        return 0;
    }
    const CompactRootInfo root = findCompactRoot( doc );
    return root.tag.empty() ? 0 : rootUnsignedAttr( std::string_view( doc ).substr( root.openBegin, root.openEnd - root.openBegin ), "est_tokens" );
}

// …and the delivered SIZE, for the emitters whose ladders compare bytes against a byte ceiling (--pack-task's header rungs,
// --from-trace's section floor). 0 under the same conditions as above.
[[nodiscard]] inline std::size_t compactDeliveredBytes( std::string_view candidate, std::string_view hint )
{
    std::string doc( candidate );
    return applyCompactDialect( doc, hint ) == CompactOutcome::Rewritten ? doc.size() : 0;
}

} // namespace rw

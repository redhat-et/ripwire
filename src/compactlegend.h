#pragma once
// compactlegend.h — the --legend=compact dialect for EVERY XML verb (capture-audit 2026-09-04, lane L7, P1).
//
// WHY ONE LAYER AND NOT SIXTY EDITS. Lens 8 measured the bill: twelve verbs spend >80% of their bytes on the
// legend, the canonical ten-verb edit loop pays 29,824 B of legend per session for ~9 KB of rows, and the
// MCP server re-pays it on every call. --for/--grep/--slice grew a compact dialect by hand (each emitter
// branching on the posture); the other ~60 XML roots are printed by as many emitters. Compact is therefore
// applied HERE, once, to the finished document: the explanatory comments are replaced by ONE ≤400 B legend
// (schema id + the verb's purpose + a reading for every completeness attribute the document actually
// carries), the root gains schema="ripwire.<key>/v1", and every payload byte is untouched — rows, root
// attributes, CDATA bodies, and the comments that CARRY DATA (the map header's <!-- files= … -->, pack-task's
// <!-- body omitted … -->, the <!-- +more --> marker, --notes' counted header). The full dialect (the default,
// and --legend=full) never passes through this file.
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

#include <cctype>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

namespace rw
{

// One entry per XML root the tool emits. `key` is the schema id stem (ripwire.<key>/v1); `purpose` is the
// one-clause reading of the verb, ≤ ~110 B so the whole legend stays under the 400 B ceiling with every
// completeness term present. Roots shared by several verbs (`r` = the ranked map family, `ctx` = the bundle
// family) are disambiguated by a HINT the caller derives from its own flags (compactLegendHintFromRoot).
struct CompactLegendSpec
{
    std::string_view rootTag;
    std::string_view key;
    std::string_view purpose;
};

inline constexpr CompactLegendSpec kCompactLegendSpecs[] =
{
    // ── the ranked-map family (root <r>) — hinted by the map-shaping flag that rode along ──
    { "r",   "map",        "ranked symbol map: <f p= layer=> groups <s t= n= id= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data" },
    { "r",   "map-diff",   "the ranked map anchored at at=: what the diff touched, the map's row vocabulary" },
    { "r",   "metrics",    "the ranked map with per-symbol metrics: in/out, cx/ccx, loc, params, nest, humps/deep, locals, cbo, amp, tested, ev" },
    { "r",   "around",     "call neighbourhood of of=: depth= hops, fanout= kept per hop; absent rows lie outside that boundary" },
    { "r",   "query",      "lexical-rank map for the query term, the map's row vocabulary" },
    // ── the bundle family (root <ctx>) ──
    { "ctx", "pack-signatures", "the ranked map plus <sigs><d l= n= id= pure=> signature rows" },
    { "ctx", "pack-top-n", "the ranked map plus <src p=> bodies of the top-N symbols" },
    { "ctx", "skipped",    "why the index lacks a file <f p= why= bytes= limit= ext=>; indexed but unvouched <h p= why= err= err_ratio=>; <lang> census" },
    { "ctx", "notes",      "field notes by target: <target id= dangling=> holds <note d= sha= branch=>; counts = the rows" },
    { "ctx", "lego",       "ONE interface/base type: <iface n= p= defs= implementors=>, its <m> method contract, every implementor" },
    { "ctx", "expand",     "full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls><c n= l=> resolved callees" },
    { "ctx", "pack-task",  "one-call task bundle under budget_tokens=: <sigs> ranking > <bodies> > <far> callers > notes > tests_to_run" },
    { "ctx", "from-trace", "trace frames mapped to indexed symbols, innermost first; the innermost in-corpus body included" },
    { "ctx", "exemplar",   "the best-in-class instance of kind= for the task, chosen by role: <exemplar n= p= in= ccx= tested=>, <bodies><b> to imitate" },
    { "ctx-partitions", "pack-task", "N minimally overlapping agent bundles carved along call-graph communities plus one shared core; each <bundle> wraps a <ctx>" },
    // ── navigation ──
    { "callers",     "callers",     "1-hop CALLERS of of= (defs= matched, count= distinct symbols): <s t= n= p=>; hop_tested=/hop_untested=" },
    { "callees",     "callees",     "1-hop CALLEES of of= (defs= matched, count= distinct symbols): <s t= n= p= role= tested=>" },
    { "uses",        "uses",        "resolvable use-sites of of=: <u role=call|macro|read|write|import|extends|type p=file:line in_id=>" },
    { "impact",      "impact",      "transitive blast radius of of=: <s t= n= p=> reach set, <f via= p=> importers" },
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
    { "safe-delete",  "safe-delete",  "can sym= go, a READ never a verdict: callers= impact_reaches= uses= tested_self= risk=; <c n= p= amb=>" },
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
    { "dead-code",    "dead-code",    "high-confidence dead functions (internal linkage, no caller in the index): <d n= t= p= l=>; filter= path component" },
    { "lint",         "lint",         "AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>" },
    { "lintcatalog",  "lint-catalog", "the built-in lint rule registry: <rule name= sev= cat= lang= since=>" },
    { "external-surface", "external-surface", "names used but never defined in the index: <x n= lang= refs= calls=>" },
    { "owners",       "owners",       "recency-weighted author ownership (half-life 6mo): <f p= authors= bf= top= share=>; bf=1 = one person holds it" },
    { "cochange",     "cochange",     "files that change together in git: <pair a= b= together= deg= conf_ab= conf_ba= surprising=>, or for of= <f p= together= conf_rev=>" },
    { "communities",  "communities",  "call-graph modules (Louvain): <community id= size= dir= label=> of <member t= n= p=>" },
    { "community",    "community",    "ONE module id=: <member t= n= p=> ranked members, its <bridge> edges; size= the TRUE count" },
    { "zoom",         "zoom",         "nested module hierarchy: <module level= id= size= dir= shown= capped=> of <member t= n= p=>; levels= deep" },
    { "tree",         "tree",         "each file with its top symbols by rank, files by best symbol: <file p= symbols=> of <s t= n=>; files_unlisted= have none" },
    { "seams",        "seams",        "cross-directory call edges NO test reaches: <seam from= to= untested= shown= capped=> of <edge caller= p= callee= cp=>" },
    { "doc-drift",    "doc-drift",    "markdown anchors that no longer hold: <doc p=> of <a k= l= c= why= ref= want= got= tgt=>; unchecked/dated rows disclose the rest" },
    { "flags",        "flags",        "BUILT but DARK: <gate name= kind=compile|cmake|env default= dark= regions= loc= reads= p= l=> with <read p= l=> sites" },
    { "skillscan",    "scan-skills",  "injection/exfiltration/path-traversal scan of skill files: files= findings= skipped= verdict=" },
    { "fieldaffinity","field-affinity","fields read together but declared far apart vs 64-byte lines: <s n= p=> structs, <pair a= b= fns= dist=>, <finding k= f= g=>" },
    { "readability",  "readability",  "Posnett/Hindle/Devanbu lens, least readable first: <fn p= n= lines= toks= ops= vocab= vol= ent= posnett=>" },
    { "nonlocal_state","nonlocal-state","per function, the non-local MUTABLE state it reaches: <fn p= n= writes= reads=> over <cell n= p= dir= via=> rows" },
    { "ensemble",     "ensemble",     "four orthogonal evidence families joined, ranked by DISTINCT families fired (no composite score): <s p= n= fam= of= fired=>" },
    { "contextratio", "context-ratio","LOCAL-REASONING lens: the share of a unit's context outside its file: <s p= n= sites= ents_out= ent_ratio= read_ratio=>" },
    { "quality_panel","quality-panel","every quality family in ONE report, ranked by distinct families fired: <s p= n= fam= of= fired= join=>; bar_*= thresholds" },
    { "naming-calibration","naming-calibration","naming lint rules scored against this repo's OWN rename history (a noisy proxy): <r n= old= new= fired= proxy=>" },
    { "naming-consistency","naming-consistency","the corpus's case-convention vote per (language, kind): <g lang= kind= style= agree= total=>, <f p= n= propose=> outliers" },
    { "comment_coherence","comment-coherence","two comment/name content measures per documented function, most name-restating first: <fn p= n= c_coeff= cic=>" },
    { "doctor",       "doctor",       "setup health: <c name= ok=> checks; exit 1 when one fails" },
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
                                       // which this layer restates at ≤400 B; --for's is never routed here (main.cpp)
    "<!-- root= ",                     // the shared root-relative-paths block (graphlegend.h)
    "<!-- graph_unindexed=",           // the #66 third-gauge clause where it rides as its OWN comment
                                       // (graphlegend.h graphUnindexedLegendComment — connect/lego/verify/
                                       // nonlocal-state): prose like every other legend sentence, and the
                                       // completeness table below carries its compact reading. Without this
                                       // row the full ~200 B sentence survived into the compact dialect on
                                       // --connect alone, one verb paying full price for a fact the table
                                       // states in a third of the bytes.

    "<!-- r:root=",                    // the map header's terse spelling of the same block
    "<!-- pr_iters=",                  // the PageRank convergence block on map-family roots
    "<!-- at= is the git commit",      // the churn/quality provenance block
    "<!-- metrics: ",                  // --metrics' per-symbol attribute block
    "<!-- of= is the resolved SEED",   // --around's boundary block
    "<!-- anchoring: ",                // --pr-context=REF's merge-base block
    "<!-- routed: ",                   // the router note
    "<!-- doctor: ",                   // --doctor's legend
    "<!-- rank_by=",                   // --rank-by's k= semantics block
    "<!-- max_tokens=",                // --max-tokens' fit_bytes block
    "<!-- with-profile: ",             // --with-profile's heat_* block
    "<!-- slice-",                     // slice's seed/flow/since FULL-dialect tiers (slice-seed:/slice-flow:/slice-since:)
    "<!-- root rows: ",                // the multi-root roots table's reading (serialize.h kMultiRootTableLegend, the one
                                       // emitter of this opener); the completeness table's element-qualified label= row
                                       // restates it
    "<!-- multi-root workspace: ",     // the multi-root churn note
    "<!-- hdr:",                       // the map header's ignored_files definition
    "<!-- format=columnar: ",          // the columnar re-serialization block
    "<!-- a body's sibs=",             // --expand's sibs= block
    "<!-- extent_suspect=",            // the extent-honesty row reading (serialize.h kExtentSuspectRowLegend)
};

// Comments that share a prose opener and must stay: --for's trailer (est_tokens=/dropped_positive=/weak= are
// spliced into it — estchargecheck A10) and slice-since's native compact block (slicediffcheck 18c pins its
// comparable=0 clause). --notes' counted header is NOT here: notes=/targets=/dangling= are the row counts
// (<note>, <target>, dangling="1") and a compact reader counts rows.
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
};

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
    // Written to the shortest honest form: a document carrying these is already near the 400 B ceiling, and the
    // callees answer can carry the first two at once.
    { "bodyless_defs",     "bodyless_defs=K: K of defs= have no body, so no callees to read" },
    { "unproven_defs",     "unproven_defs=K: K same-named defs not tied to that file, in no count or row (bare name shows them)" },
    { "declined_calls",    "declined_calls=K: K call sites left unbound (several defs, none chosen), in no count or row" },
    // --uses=Owner.field's member form (fielduses.h appends kUsesFieldLegend to that answer alone). owner_candidates= is a
    // row attribute that exists only beside member=, so one head term defines the whole form.
    { "member",            "member=Owner.field: rows use that field; pinned=/amb_sites= rows with one owner/with owner_candidates=K; owners_of_name= fields so named" },
    { "hits_capped",       "hits_capped=1: hits= is a floor" },
    // Both also ride the map header: est_tokens= alone there under order=stable (the root drops it), over_ceiling=1 there
    // under max-tokens. Same number, same reading, so one row reads both places.
    { "est_tokens",        "est_tokens=: price as emitted (an upper bound under compact)", false, {}, MapHeaderRead::Also },
    { "over_ceiling",      "over_ceiling=1: budget not met", false, {}, MapHeaderRead::Also },
    // M1 (terminality round A, 2026-09-05): the ranked head's own floor — how many rank>0 candidates the
    // ceiling ladder cut. It rides the root on --for and (since M1) on --pack-task/explore too, so the
    // compact dialect has to define it wherever it appears, or the default answer names a number with no
    // reading. Present-only, like every term here: absent means nothing was dropped.
    { "dropped_positive",  "dropped_positive=N: N ranked candidates cut by the ceiling" },
    { "withheld",          "withheld=: rows the budget cut" },
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
    { "defs",              "defs=N: of= names N defs; the lowest-id one was walked", true, "r" },
    // The map HEADER's absent-at-zero gauges: `<!-- files=` is kept as data while the `<!-- hdr:` clauses that define
    // these fields go (kDeclinedMapLegend, kIgnoredLegend, kExtentSuspectHdrLegend, kMacroBlankedHdrLegend, the absent-if-0
    // half of the always-on legend, kMaxTokensFitLegend). Header-ONLY: several are quoted attributes elsewhere.
    { "declined",          "declined=K: K calls left unbound (several defs, none chosen)", false, {}, MapHeaderRead::Only },
    { "external",          "external=K: K calls taken as outside the tree, no edge", false, {}, MapHeaderRead::Only },
    { "locality_pinned",   "locality_pinned=K: K calls pinned by locality alone (a guess)", false, {}, MapHeaderRead::Only },
    { "extent_suspect_syms", "extent_suspect_syms=K: K defs failed containment, corpus-wide", false, {}, MapHeaderRead::Only },
    { "macro_blanked_files", "macro_blanked_files=K: K files indexed from a macro-blanked re-parse", false, {}, MapHeaderRead::Only },
    { "ignored_files",     "ignored_files=K: K files git's ignore rules dropped", false, {}, MapHeaderRead::Only },
    { "ignored_dirs",      "ignored_dirs=K: K subtrees git's ignore rules pruned, contents unknown", false, {}, MapHeaderRead::Only },
    { "max_tokens",        "max_tokens=/fit_bytes=: tokens asked/the byte cap applied", false, {}, MapHeaderRead::Only },
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
    { "preview",           "preview=1: an UNWRITTEN payload; <overwrite l= end= bytes=> = the span an apply replaces, CDATA as on disk (shown=/capped=1/elided_lines= when cut)" },
    { "redacted",          "redacted=1: a credential shape rewritten to [REDACTED:kind]; the no-redact flag serves the bytes", true },
    // extent honesty (serialize.h kExtentSuspectRowLegend): a ROW-level term on the map, <d> and <b> rows alike.
    { "extent_suspect",    "extent_suspect=: span/scope/kind failed containment (name|head|scope|error)", true },
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

// Row-level terms: does ANY tag outside comments/CDATA carry ` <attr>="`? With `onTag`, only a `<onTag …>` element counts.
inline bool payloadHasAnyAttr( std::string_view doc, std::string_view attr, std::string_view onTag = {} )
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
            if( tag.find( needle ) != std::string_view::npos && isElementNamed( tag, onTag ) ) { return true; }
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

// The map header comment (before the root, or trailing under order=stable), or empty when the document has none: every
// verb outside the map family and the bundles that embed it. A well-formed document spells `<!--` raw only in a comment
// or a CDATA body, and a comment cannot hold `--`, so the first hit outside CDATA IS the header.
inline std::string_view compactMapHeader( std::string_view doc ) noexcept
{
    for( std::size_t hit = doc.find( kCompactMapHeaderOpener ); hit != std::string_view::npos; hit = doc.find( kCompactMapHeaderOpener, hit + 1 ) )
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
        return payloadHasAnyAttr( doc, t.attr, t.onTag );
    }
    return headHasAttr( head, t.attr ) || ( t.wholeDoc && payloadHasAnyAttr( doc, t.attr ) );
}

// The ≤400 B compact legend for one document.
inline std::string compactLegendText( const CompactLegendSpec& spec, std::string_view head, std::string_view doc )
{
    std::string out;
    out.reserve( 400 );
    out += "<!-- ripwire ";
    out.append( spec.key );
    out += " ripwire.";
    out.append( spec.key );
    out += "/v1: ";
    out.append( spec.purpose );
    out += '.';
    // the paging window, one clause, present names only
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
    if( !window.empty() )
    {
        out += " window: ";
        out += window;
        out += payloadHasAnyAttr( doc, "next_offset" ) ? " (capped=1 cut; next_offset= pastes as offset=)." : " (capped=1 cut).";
    }
    const std::string subcaps = payloadSubCapAttrs( doc );
    if( !subcaps.empty() )
    {
        out += ' ';
        out += subcaps;
        out += ": 1 = cut.";
    }
    const std::string_view mapHeader = compactMapHeader( doc );
    for( const CompactCompletenessTerm& t : kCompactCompletenessTerms )
    {
        if( isCompletenessTermPresent( t, head, doc, mapHeader ) )
        {
            out += ' ';
            out.append( t.reading );
            out += '.';
        }
    }
    out += " -->";
    return out;
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
inline CompactOutcome applyCompactDialect( std::string& doc, std::string_view hint )
{
    const CompactRootInfo root = findCompactRoot( doc );
    if( root.tag.empty() ) { return CompactOutcome::NotXml; }
    const CompactLegendSpec* spec = findCompactSpec( root.tag, hint );
    if( spec == nullptr ) { return root.hasSchema ? CompactOutcome::AlreadyCompact : CompactOutcome::UnknownRoot; }

    // pass 1: the legend text is computed from the ORIGINAL document (payload attributes are unchanged by the
    // rewrite, so scanning before or after is the same; before keeps the two passes independent)
    const std::string legend = compactLegendText( *spec, compactDocHead( doc, root ), doc );

    // pass 2: copy, dropping prose comments; remember where the first one stood
    std::string out;
    out.reserve( doc.size() + legend.size() + 40 );
    std::size_t firstProseAt = std::string::npos;
    std::size_t i = 0;
    const std::size_t n = doc.size();
    std::size_t rootOpenEndInOut = std::string::npos;
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
            if( isCompactProseComment( comment ) )
            {
                if( firstProseAt == std::string::npos ) { firstProseAt = out.size(); }
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
            out.append( doc, i, root.nameEnd - i );
            if( !root.hasSchema )   // a native compact root (grep/slice) already carries its id
            {
                out += " schema=\"ripwire.";
                out.append( spec->key );
                out += "/v1\"";
            }
            out.append( doc, root.nameEnd, root.openEnd - root.nameEnd );
            rootOpenEndInOut = out.size();
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
    const std::size_t at = firstProseAt != std::string::npos ? firstProseAt
                         : ( rootOpenEndInOut != std::string::npos ? rootOpenEndInOut : out.size() );
    out.insert( at, legend );
    doc.swap( out );
    return CompactOutcome::Rewritten;
}

} // namespace rw

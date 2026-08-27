#pragma once

// cli.h — hand-rolled zero-dependency argument parser. Linear argv scan into one
// POD Config; flags are additive; first non-flag positional is the root path.

#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <string_view>
#include <vector>

#include "ingest.h"   // rw::kDefaultMaxFileBytes — the canonical crawl size ceiling (--max-file-size)
#include "version.h"  // configure-generated kRipwireVersion + short build info (--version)

namespace rw
{

enum class RankBy { PageRank, Authority, Hub, Rrf, Churn, ChurnDecay };   // --rank-by=pagerank|authority|hub|rrf|churn|churn-decay
enum class ColorBy { Lang, Community, Cx, Churn, Tested };    // --color-by=lang|community|cx|churn|tested (with --html)

struct Config
{
    std::string_view rootPath;                   // roots[0] — kept as an alias so untouched call sites compile (A1)
    std::vector<std::string_view> roots;         // ALL positional roots (multi-root workspace when size() >= 2)
    int              topK            = 200;      // --top-k=N; 0 = emit NO ranked map (payload verbs only, r27-emitters T2)
    bool             topKExplicit    = false;    // did the user actually pass --top-k=? (gates the "ride-along map" stderr hint)
    int              packTopN        = 0;        // 0 = disabled
    std::size_t      packBudgetBytes = 65536;    // 64 KB ≈ 16K tokens
    bool             ignoreTests     = false;
    bool             mapDiff         = false;
    bool             mcp             = false;
    std::string_view listen;                     // --listen=HOST:PORT (or bare PORT ⇒ loopback): serve the MCP
                                                 // server over Streamable HTTP instead of stdio.
                                                 // Implies --mcp. Binds 127.0.0.1 by default; a non-loopback host
                                                 // requires --mcp-token (refuses to start otherwise).
    std::string_view mcpToken;                   // --mcp-token=T (or RIPWIRE_MCP_TOKEN env): shared bearer for the HTTP
                                                 // transport. Required for a non-loopback bind and for --allow-remote-edits.
    bool             allowRemoteEdits = false;   // --allow-remote-edits: permit the 3 edit verbs over --listen (refused by
                                                 // default); forces the token requirement even on loopback.
    std::vector<std::string> excludes;           // --exclude=SUBSTR (repeatable): drop matching paths
    RankBy           rankBy          = RankBy::PageRank;   // --rank-by=  (default keeps output unchanged)
    bool             columnar        = false;              // --format=columnar|rows (RESEARCH lever 1): re-serialize the FLAT
                                                           // list verbs (--callers/--callees/--uses/--impact + --pr-context rows)
                                                           // as a path-table + parallel arrays; NEVER the nested map. Default
                                                           // --format=xml keeps the minified-XML output byte-identical.
    bool             candidates      = false;              // --format=candidates (A4-R6 / R6): a FLAT top-K export for EXTERNAL
                                                           // rerankers — one <cand r= s= n= id= k= p= l=><sig>…</sig></cand> row
                                                           // per --for/--query result (NO lens extras, NO doc bodies). Composes
                                                           // with --top-k. Still XML (G4). Default (unset) leaves output unchanged.
    bool             json            = false;              // --json (L2): the SAME content as the XML, machine-parseable, for the
                                                           // CORE verbs ONLY (default map, --for, --pack-task, --callers/--callees/
                                                           // --impact, --quality-delta, --test-gate). Keys mirror the XML attr names
    std::string_view legend;                               // --legend=full|compact: opt-in schema prose posture for --for/--grep
                                                           // 1:1. Every other verb refuses loudly (stderr + exit 1) rather than
                                                           // silently emitting XML — see main.cpp's jsonUnsupportedVerb().
    int              detail          = 0;                  // --detail=N (RESEARCH lever 3): with --for, emit FULL bodies for the
                                                           // top-N ranked symbols + signatures for the rest, in ONE call. 0 = off
                                                           // (byte-identical to no flag). Composes with --max-tokens and --adaptive.
    std::string_view around;                               // --around=SYMBOL (or file:name): focused ego pack
    std::string_view callers;                              // --callers=SYMBOL (or file:name): who calls it (1-hop in-edges)
    std::string_view callees;                              // --callees=SYMBOL (or file:name): what it calls (1-hop out-edges)
    std::string_view usesSym;                              // --uses=SYM (or file:name): the statically resolvable use-sites of SYM (call/read/write/import/extends/type) + external flag (ABS-3); file: narrows defs= + the call-role sites, other roles stay name-wide (§P10.2/§A6b)
    std::string_view graphQuery;                           // --graph-query=EXPR: composable node-set operators over the call graph (ABS-5)
    std::string_view verifyClaim;                          // --verify=CLAIM (G4): one structured claim in, a three-valued verdict + inline evidence out (src/verify.h owns the closed grammar)
    std::string_view helpTask;                             // --help-task=TASK: deterministic task -> one recommended Ripwire command (or honest abstention)
    bool             externalSurface = false;              // --external-surface: names referenced but never defined in-corpus (stdlib/3p surface)
    int              aroundDepth     = 2;                  // --around-depth=
    int              aroundFanout    = 32;                 // --around-fanout=
    bool             eval            = false;              // --eval: self-eval (co-change recall vs BM25)
    bool             evalRetrieval   = false;              // --eval-retrieval: KNOWN-ITEM retrieval eval — validates
                                                           // query-TIME ranker choice (name-exact/routing/anchoring)
                                                           // that the seed-based --eval structurally cannot measure
    std::string_view evalMined;                            // --eval-mined=FILE: session-trace-mined retrieval eval —
                                                           // consumes a bench/mine_traces.py minedpair.jsonl artifact.
                                                           // Explicit path required, no silent
                                                           // default lookup into ~/.ripwire/...
    std::string_view evalSkills;                           // --eval-skills=FILE: labelled skill-ROUTING eval — ROOT is a
                                                           // skills directory, FILE is the prompt→permitted-skill(s)
                                                           // corpus
    std::string_view cacheFile;                            // --cache=PATH: incremental index (re-parse only changed)
    std::string_view indexOut;                             // --index-out=BASE: CI generate-and-exit. Cold-parses the tree
                                                           // TWICE — lean then rich — writing BASE.lean.ripwirecache +
                                                           // BASE.rich.ripwirecache (both families: --for/--exemplar/--metrics
                                                           // are RICH and would stay cold on a lean-only artifact), then exits 0
                                                           // WITHOUT emitting a map. Sugar over --cache (force-rebuild both paths).
    bool             noCache = false;                      // --no-cache: disable the warm-by-default per-root TMPDIR cache
    std::size_t      maxFileBytes = kDefaultMaxFileBytes;  // --max-file-size=N[K|M|G]: crawl size ceiling (default 4 MB)
    std::string_view scipIndex;                            // --scip=index.scip: SCIP precision overlay — precise edges REPLACE name-based guesses; prov="scip" tags them
    bool             packSignatures  = false;              // --pack-signatures: body-elided decl skeletons (~59-68% fewer bytes at top-10/50/100, 68% at the default top-50; root-neutralised, since the repeated path prefix is charged in both forms and is not what this elides)
    std::string_view query;                                // --query=TERMS: pure lexical (BM25) retrieval
    std::string_view grep;                                 // --grep=STR: parallel literal scan + enclosing symbol + the matched line
    bool             grepGiven = false;                    // G1/F1: --grep=/--regex= was already given once this run — a SECOND occurrence
                                                             // used to silently overwrite the first (the pattern a caller reaches for when they
                                                             // MEAN "and"); refused instead, naming the real AND spelling. See kViewFlags' dupGuardFlag.
    bool             grepRegex = false;                    // --regex=PAT: like --grep but the pattern is an ECMAScript regex
    bool             grepHandles = false;                  // --handles: mint freshness-pinned handles on unique editable <enc> rows
    bool             noPrefilter = false;                  // --no-prefilter: (debug) skip the regex→trigram prefilter, full-scan every file — the soundness oracle for --regex
    int              grepBefore = 0;                       // --grep-before=N (ripgrep -B): N source lines emitted before each --grep/--regex hit (0 = off, unchanged output)
    int              grepAfter  = 0;                       // --grep-after=N  (ripgrep -A): N source lines emitted after each hit
                                                             // --grep-context=N (ripgrep -C): shorthand that sets BOTH grepBefore and grepAfter to N
    // G3 (2026-08-15 harvest): boolean AND/NOT over --grep's already-collected hits — a flat term list,
    // no CNF, no parens (OR stays --regex='A|B'). Literal-only: refused together with --regex (validateConfig).
    std::vector<std::string_view> grepAnd;                 // --and=TERM (repeatable): every term must ALSO be present
    std::vector<std::string_view> grepNot;                 // --not=TERM (repeatable): the term must be ABSENT
    std::string_view              grepScope;               // --grep-scope=line|file (default line; validated in validateConfig)
    // R-H (2026-08-15 harvest report-ugrep §F3/§F4, funded by E5): --grep-in=code|any — which SPAN TIER a
    // hit must sit in to print. Empty ⇒ the default, code (the tightest non-empty tier); "any" turns the
    // tier pass off entirely, which is both the escape hatch and the pre-tier answer byte for byte.
    std::string_view              grepIn;                  // --grep-in=code|any (default code; validated in validateConfig)
    std::string_view match;                                // --match=QUERY: tree-sitter structural query (shape search)
    // R2 (2026-08-20): the pattern surface. --match makes you know each grammar's node-kind vocabulary
    // before you can ask anything; --pattern takes the CODE SHAPE and compiles it per grammar (src/pattern.h).
    std::string_view pattern;                              // --pattern=PAT: code-shaped structural search, e.g. 'foo($X, ...)'
    bool             lint = false;                         // --lint: built-in AST checks (rides the same query pass)
    std::string_view lintRulesDir;                         // --lint-rules=DIR: load user YAML lint rules (ast-grep style) — runs alongside/instead of --lint
    bool             sarif = false;                        // --sarif (with --lint / --lint-rules): SAME findings, SARIF 2.1.0 (src/sarif.h)
                                                             // instead of the native XML <lint> block — the shape github/codeql-action/
                                                             // upload-sarif consumes for the code-scanning UI. Pure re-serialization: no
                                                             // new analysis, no re-ranking. Refused (loudly, in validateConfig) alone,
                                                             // with --match (SARIF covers --lint findings only), with --with-profile
                                                             // (the heat_* join has no SARIF field yet) and with paging (SARIF always
                                                             // emits the FULL result set — GitHub's action wants one complete document).
    bool             lintCatalog = false;                  // --lint-catalog: the built-in rule registry (name/sev/category/rationale/
                                                             // languages/since), one row per rule — src/lintcatalog.h. Standalone: needs
                                                             // neither --lint nor --lint-rules, and ignores the corpus entirely.
    std::string_view lintSelect;                            // --lint-select=PREFIX[,...]: run only rules whose name starts with one of
                                                             // these (or "*" for all) — modifies --lint / --lint-rules; refused alone.
    std::string_view lintIgnore;                            // --lint-ignore=PREFIX[,...]: drop rules whose name starts with one of these
                                                             // (or "*" to drop everything) — applied AFTER --lint-select narrows the set.
    std::vector<std::string> expand;                       // --expand=NAME,...: emit full def bodies for these symbols; NAME:START-END slices to 1-based lines START..END of the def (octocode partial-fetch)
    std::vector<std::string> outline;                      // --outline=NAME,...: control-flow skeletons (L3 scoped snippet)
    std::string_view forTask;                              // --for=TASK: the task lens — ranked signatures inventory + metrics, framed for reuse
    bool             anchor = false;                       // --anchor (with --for, EXPERIMENTAL): seed PPR personalization from the lexical anchors and blend graph expansion into the lens rank (LARGER-style; graph.h anchoredLexicalRank)
    bool             noRoute = false;                      // --no-route (with --for/--query): force plain subtoken+body BM25 (the pre-default-routing behavior). Routing is the DEFAULT: a deterministic confidence-gated query-shape classifier picks name-exact vs subtoken+body and prints which/why in the header (lexical.h chooseForRanker). --route is still accepted (now a no-op: routing is already on).
    bool             adaptive = false;                      // --adaptive (with --for/--query): cut the returned set at the largest relative score gap (Adaptive-k) with a floor (~5) + the existing top-k ceiling, so a sharp query returns few and a flat/broad one hits the ceiling; prints the cut in the header
    bool             noMentionBoost = false;                // --no-mention-boost (with --for): disable the B8 query-mention anchor — by default, files / dotted modules / Scope.symbols literally NAMED in the task text are lifted to just below the top hit (the measured #1 competitor-win bucket; bench/headtohead). Inert when the text names nothing indexed (byte-identical). Env RIPWIRE_NO_MENTION=1 disables everywhere (incl. the MCP `for` verb).
    bool             cochangeBoost = false;                 // --cochange-boost (with --for): OPT-IN, EXPERIMENTAL (the --anchor precedent) — the B3 co-change prior: files that historically change WITH the top-ranked files (git co-change, last 500 commits, support >= 3) get a small bounded score boost into the lower bundle; the top seeds can never be displaced. Honest numbers (B3 held-out record): train multi-file strict@10 +6.4pp but held-out +0.0pp (n=55) at warm p50 +19% — did NOT confirm on the Python LocBench corpus; default stays OFF pending a large-C++-corpus history eval. Env RIPWIRE_COCHANGE=1 enables everywhere (incl. the MCP `for` verb, which has no per-call flags).
    bool             noDocMention = false;                  // --no-doc-mention (with --for): disable the doc-mention surfacing — by default, a doc that names one of the task's top-resolved symbols in a `backtick` (the g.mentions edges `--mentions=SYM` already exposes) is lifted into the bundle, strictly below that symbol's own score. Inert when nothing resolved has a mentioning doc (byte-identical). Route-agnostic (applies under --no-route too). Env RIPWIRE_NO_DOC_MENTION=1 disables everywhere (incl. the MCP `for`/`pack_task` verbs).
    bool             signaturesOnly = false;                // --signatures-only (with --for): opt OUT of the T3 terminal-by-default bundle — no auto <bodies> section, no bundle="auto" disclosure; restores the pre-T3 signatures-only lens byte-identically. Contradicts --detail=N (the explicit body knob), refused together. Pre-registered: docs/EVALS.md §4, T3 round.
    bool             autoBodies = false;                    // --auto-bodies (with --for): opt OUT of COMPACT conceptual serving — restore the rank-first auto <bodies> walk on the subtoken+body route, which by default serves the ranked map plus a <hops> one-hop edge section and no body CDATA. A permanent posture flag, not a transition aid. Inert on the name-exact route (the allowance is already on there). Contradicts --signatures-only (no bodies at all) and --detail=N (the explicit body knob), refused with either. Pre-registered: docs/EVALS.md, the T3 route-narrowing round.
    std::string_view legoType;                             // --lego=TYPE: the interface→impls "Lego" view for ONE named interface/base (signature + method contract + every implementor, own-language only). file:name disambiguates a same-named type across languages.
    std::string_view exemplar;                             // --exemplar=TASK|KIND (Q7): the repo's best-in-class instance of what you're about to write (by ROLE, not text similarity). A plain TASK string infers KIND from the top match; a KIND token selects directly.
    std::string_view recall;                               // --recall=TASK: retrieve the most relevant DOCS (memory/notes) + emit their full bodies
    bool             mostImportantLast = false;            // --order=important-last (was --most-important-last, now a hidden alias): emit highest-rank content last (explicit; always honoured)
    bool             stable            = false;            // --order=stable (was --stable, now a hidden alias): emit in path/id order (stable prefix → provider KV-cache hits on re-runs)
    bool             noStable          = false;            // --no-stable: opt OUT of the stable default that --mcp turns on (P2-C) — NOT an --order alias, unchanged
    bool             noAutoOrder       = false;            // --order=important-first (was --no-auto-order, now a hidden alias): opt OUT of T3's fill-aware auto important-last (see serialize.h kFillOrderThreshold)
    int              maxTokens         = 0;                // --max-tokens=N: budget the map to ~N tokens (binary-search top-K) — SHAPES the map to fit
    std::size_t      tokenBudget       = 0;                // --token-budget=N[K]: CI gate — 0 = disabled. After the map is built, if its est_tokens
                                                            // (the SAME calibrated header number, never a second counter) exceeds N, exit 3 and name
                                                            // both numbers on stderr; within budget, exit 0 and emit the map unchanged. Composable with
                                                            // --max-tokens: that flag SHAPES the map to fit a target, this one ASSERTS and fails —
                                                            // set neither, either, or both.
    // T2 pagination for high-cardinality verbs (--deps/--callers/--callees/--hotspots/--tree/--lint). Default
    // limit=0 = NO pagination (whole result, byte-identical to pre-T2 callers/gates). --limit=N bounds one
    // response to N items; --offset=M skips the first M. §P8: seven more verbs honor these now (--clones /
    // --cochange / --owners / --communities / --doc-drift / --whereis / --grep) — before that they accepted
    // both flags and ignored them, so a paging loop over --cochange re-served page 0 forever. The shared
    // window + root disclosure live in src/pageview.h; the gate is test/pagingsweepcheck.sh.
    // Seams are deterministic (results already sorted) so
    // page M+N is the exact continuation of page M — no dropped/duplicated item across the seam.
    int              pageLimit         = 0;                // --limit=N: max items in this response (0 = unbounded)
    int              pageOffset        = 0;                // --offset=M: skip the first M items (0 = from the start)
    bool             metrics           = false;            // --metrics: annotate symbols with fan-in/out + role (descriptive)
    bool             deps              = false;            // --deps: file→file dependency view (#include/import counts)
    bool             hotspots          = false;            // --hotspots: complexity × recent git churn (maintenance-pain map)
    bool             clones            = false;            // --clones: token-normalized duplicate function bodies
    bool             readability       = false;            // --readability: the Posnett/Hindle/Devanbu (MSR 2011) lens — per function, Halstead
                                                            // volume + token entropy + line span → P, emitted LEAST readable first. Pages through
                                                            // limit/offset like the other report verbs; a ranking lens, never a grade (readability.h)
    bool             nonlocalState     = false;            // --nonlocal-state: per function, the non-local MUTABLE state it or its transitive
                                                            // callees reach — globals/statics/file-scope data — with READS and WRITES kept apart
                                                            // and the site or callee that explains each one. Unsound by construction (indirect
                                                            // calls, aliasing, shadowing), so every count is a floor (nonlocalstate.h)
    bool             ensemble          = false;            // --ensemble: the FAMILY JOIN — per function, which of the four orthogonal evidence
                                                            // families (structural / lexical / confusion / historical) fire, ranked by the COUNT
                                                            // of distinct families and never by a weighted composite. A family that could not be
                                                            // measured is reported UNAVAILABLE, never silent (ensemble.h)
    bool             qualityPanel      = false;            // --quality-panel[=strict|default|lenient]: THE SINGLE COMMAND — the whole panel of
                                                            // quality checks in ONE ranked report over SIX evidence families (the ensemble's four,
                                                            // plus colocation and state), ranked by the COUNT of distinct families a preset counts
                                                            // and never by a weighted composite. Presets SELECT and CUT, they never weight; a family
                                                            // that could not be measured is UNAVAILABLE, never silent (qualitypanel.h)
    std::string_view qualityPanelPreset;                    // --quality-panel=PRESET: which preset. An unknown value is REFUSED rather than
                                                            // silently replaced — a substituted selection is a silently different report
    bool             contextRatio      = false;            // --context-ratio: the LOCAL-REASONING lens — per symbol (and rolled up per
                                                            // file), the distinct entities and files a reader must resolve, and the share
                                                            // of them living outside the unit's own file, weighted by the TOKENS a reader
                                                            // must read as well as by edge count. A REFINEMENT of Beck & Diehl's per-class
                                                            // congruence (FSE 2011) / Martin's instability, not a new measure (contextratio.h)
    bool             namingCalibration = false;            // --naming-calibration: §9.5 — score the naming-* lint rules against this
                                                            // repo's OWN rename history (old -> new pairs mined from git log -p).
                                                            // A NOISY proxy, disclosed as one; the floor a rule must clear lives in
                                                            // test/namingcalibrationcheck.sh, not here (renamemine.h)
    bool             namingConsistency = false;            // --naming-consistency: §9.2 TIER A — the corpus's own case-CONVENTION
                                                            // vote per (language, kind) group; every off-convention name in a
                                                            // DECIDED group gets propose=, its own subtokens mechanically
                                                            // recombined into the dominant style. A lens, exit 0 always
                                                            // (namingconsistency.h)
    bool             namingLocals      = false;            // --naming-locals: local-variable-indexing plan Phase 2 (PLAN.md
                                                            // 2026-08-06 evening) — an OPT-IN --lint extension only, folded into
                                                            // the naming lens's existing naming-short/-wordy/-underscore/-case
                                                            // tags for LOCAL variable names inside large/deep/complex C/C++
                                                            // functions (naminglens.h). DEFAULT-OFF, and NOT wired into a plain
                                                            // --lint run without this flag: the plan's own "Hard blocker on
                                                            // default-enable" is unmet (no calibration harness can score a
                                                            // local-scoped rule yet, and the required real-corpus manual audit
                                                            // for idiomatic-short-name skew — i/j/k/buf/tmp/err — has not run).
                                                            // Deliberately breaks naminglens.h's own stated invariant ("an
                                                            // un-indexed loop local can never be flagged") — see that file's
                                                            // WITHDRAWN note for why shipping a plausible-but-unaudited rule
                                                            // is exactly the failure mode this flag's default-off guards against.
    bool             commentCoherence  = false;            // --comment-coherence: per function/method with a doc comment, TWO published
                                                            // content measures — Steidl/Hummel/Juergens c_coeff (ICPC 2013, HIGH is BAD:
                                                            // the comment mostly restates the name) and Scalabrino CIC (ICPC 2016/JSEP
                                                            // 2018, Jaccard of comment terms vs the method's own identifier terms).
                                                            // UNAVAILABLE (not scored) where no comment exists. Complements --doc-drift
                                                            // (staleness) with content, over a disjoint input (commentcoherence.h)
    bool             cochange          = false;            // --cochange[=FILE]: files that change together in git (hidden coupling)
    std::string_view cochangeFile;                         // --cochange=FILE: lockstep partners of one file
    int              cochangeRecur     = 0;                // --cochange-recur=K (with --cochange): report only pairs whose co-change RECURS in >= K of the mined window's sub-windows (Clio, ICSE 2011 — a discrepancy is not a violation the first time it appears). 0 = unfiltered (every row still carries recur=). Disclosed as min_recur= in the header when set.
    bool             cochangeGroups    = false;            // --cochange-groups (with --cochange): emit Mo/Cai/Kazman's Modularity Violation GROUPS — "X co-changes with {A,B,C}, none of which it depends on" as ONE row naming the file to fix — instead of the pair list. Greedy cover, disclosed as such; the pair form stays the default.
    std::string_view archRules;                            // --arch=FILE: enforce layering rules (exit 2 on violation)
    bool             communities = false;                  // --communities: cluster the call graph into cohesive modules
    bool             communityFlag = false;                // --community was given at all (a bare/empty value still routes to the
                                                            // handler and refuses loudly rather than falling through to the map)
    std::string_view communityId;                          // --community=ID (§P11.6): drill into ONE module printed by
                                                            // --communities/--zoom — its full ranked member list (paged) plus its
                                                            // bridge edges to other modules. The selector chain at module
                                                            // granularity: before this, the ids those two verbs emit were the only
                                                            // identifiers in the tool that no verb accepted.
    bool             zoom        = false;                   // --zoom[=depth]: NESTED module hierarchy (multi-level Louvain) + top-level bridges (S5-D)
    int              zoomDepth   = 0;                       // --zoom=depth: cap the hierarchy at `depth` levels (0 = auto: contract until ≤10 top modules)
    bool             report      = false;                  // --report: auto architecture summary (markdown)
    bool             tree        = false;                  // --tree: file-level orientation map (top symbols per file)
    bool             seams       = false;                  // --seams: cross-module bridges no test reaches (untested integration seams)
    bool             mermaid     = false;                  // --mermaid: module (directory) dependency graph as a Mermaid diagram (human-viewable)
    std::string_view pathSpec;                             // --path=SRC,DST: shortest directed call-path between two symbols
    std::string_view connectSpec;                          // --connect=A,B,C: minimal connecting subgraph over 2..16 symbols
    int              connectRadius = 6;                    // --connect-radius=N: undirected BFS bound (core clamps to 1..12)
    std::string_view impactSym;                            // --impact=SYM (or file:name): transitive blast radius (everything that reaches SYM)
    std::string_view mentionsSym;                          // --mentions=SYM: markdown docs that name SYM in a `backtick` (doc↔code)
    std::string_view affectedFiles;                        // --affected=F1,F2|SYM: test files transitively reaching the changed files — or the changed SYMBOL (§P11.2a, file-first argument rule in testmap.h)
    bool             exercisesFlag = false;                // --exercises was given at all (a bare/empty value still routes to the
                                                            // handler and refuses loudly rather than falling through to the map)
    std::string_view exercisesFile;                         // --exercises=TESTFILE (§P11.2b): the INVERSE of --affected — the
                                                            // non-test symbols this test file transitively calls into (what it
                                                            // covers). Refuses on a non-test path: the verb IS the test/non-test
                                                            // partition, so on a non-test file its subtraction means nothing.
    bool             situ        = false;                  // --situ[=FILES]: situational awareness (blast radius + tests + co-change) for a change
    std::string_view situFiles;                            // --situ=FILES: explicit changed files (else the current git diff)
    bool             handoff     = false;                  // --handoff: the continuation packet for the NEXT session — <verified> disk truth (branch/sha,
                                                            // changed files+symbols, blast radius, tests-to-run) + <heuristic> labeled suggestions
                                                            // (co-change partners, committed notes, plan/design doc pointers). Composes with --token-budget.
    bool             testGate    = false;                  // --test-gate[=FILES]: TDAD-parity regression contract — tests-to-run + untested blast radius (exit 4 if obligations)
    std::string_view testGateFiles;                        // --test-gate=FILES: explicit changed files (else the current git diff)
    bool             scanSkills  = false;                  // --scan-skills[=DIR]: scan skill files for injection/exfiltration patterns
    std::string_view scanSkillsDir;                        // --scan-skills=DIR: explicit dir (else repo-local + Claude + Codex homes)
    std::string_view scanSkillFile;                        // --scan-skill=FILE: scan a single skill file
    std::string_view batchFile;                            // --batch=FILE (or '-' for stdin): A4-R3 CLI form — newline-delimited
                                                           // `verb:arg` sub-queries answered in one deduped <batch> (MCP `batch` verb
                                                           // is the primary surface; this is the shell-pipeline counterpart)
    bool             force       = false;                  // --force: proceed even if scan finds CRITICAL issues (wrap hook only)
    bool             html        = false;                  // --html[=FILE]: emit self-contained HTML force-directed graph (P2-A)
    std::string_view htmlFile;                             // --html=FILE: write to FILE (else stdout)
    ColorBy          colorBy         = ColorBy::Lang;      // --color-by=MODE: initial node-colour mode of the --html page (all five embedded)
    bool             colorByExplicit = false;              // did the user pass --color-by=? (gates the --html-required guard)
    bool             owners      = false;                  // --owners[=SYM]: bus-factor — recency-weighted author ownership per file (S5-C)
    std::string_view ownersSym;                            // --owners=SYM: restrict to the file containing SYM
    bool             compress        = false;              // --compress: strip comments + blank runs from --expand/--outline body output (P2-B)
    bool             baseline        = false;              // --baseline: write .ripwire_arch_baseline sidecar (accept current debt), exit 0
    bool             baselineUpdate  = false;              // --baseline-update: merge current violations into baseline (accept new debt), exit 0
    bool             deadCode        = false;              // --dead-code[=DIR]: internal source functions with zero indexed callers (high-confidence candidates)
    std::string_view deadCodeDir;                          // --dead-code=DIR: restrict scan to DIR — matched as WHOLE path components (a dir, a nested dir, or a filename); a filter naming nothing indexed REFUSES (§P0.3). Leading ./ anchors DIR at the repo root instead of matching that component anywhere (§A10.6)
    bool             qualityBaseline = false;              // --quality-baseline: snapshot ccx/clones/dead to .ripwire_quality_baseline
    bool             qualityDelta    = false;              // --quality-delta: report only code-quality regressions vs that baseline (exit 2 if any MAJOR unacked one)
    std::string_view qualityDeltaRange;                    // --quality-delta=REV|A..B (R-I): compare two COMMITTED trees instead of the working
                                                            // tree vs a baseline — the WAVE-level measurement. Same grammar --dmm= takes
                                                            // (quality::resolveRefSpec owns it), same 10 kinds/gating/ack contract out
    bool             qualityAck      = false;              // --quality-ack[=REASON]: accept the current findings into .ripwire_quality_acks (per-finding ratchet); shares qualityDelta's baseline resolution
    std::string_view qualityAckReason;                     // the reason recorded next to each acked finding
    std::string_view qualityAckOnly;                       // --ack-only=SUBSTR[,SUBSTR]: ack only findings whose kind or canonical id contains one of these (default: all)
    bool             dmm             = false;              // --dmm[=REV|A..B]: the Delta Maintainability Model scalar (di Biase/Rastogi/
                                                            // Bruntink/van Deursen, TechDebt 2019) — ONE trendable number in [0,1] for a
                                                            // change: the share of moved volume that made the code healthier. The
                                                            // per-kind complement to --quality-delta, which says WHICH debt grew but has
                                                            // no scale. A DELTA, never a level: editing bad code without growing it
                                                            // scores nothing at all (dmm.h)
    std::string_view dmmRange;                             // --dmm=REV (that commit vs its first parent) or --dmm=A..B (B vs A). Bare
                                                            // --dmm compares the WORKING TREE against HEAD, the way --quality-delta does
    std::string_view editCheckSym;                         // --edit-check=SYM (B11/L5): fast per-symbol post-edit contract check — SYM's
                                                            // param count + publicness now vs git HEAD (unchanged/new-symbol/contract-change),
                                                            // plus its 1-hop callers with any call-site provably incompatible with the NEW
                                                            // arity flagged. file:name disambiguates like --around/--lego.
    std::string_view safeDeleteSym;                        // --safe-delete=SYM: "can I delete this?" composed from signals the tool already
                                                            // computes — 1-hop callers, the transitive --impact blast radius, every --uses
                                                            // read/write/import/call/extends site, how much of the radius the tested= lens
                                                            // covers, and --dead-code's own high-confidence shape at defs=1. FACTS only:
                                                            // risk= names what was found (none-found/uses-exist/untested-radius), never a
                                                            // go/no-go verdict. file:name disambiguates like --around/--lego.
    std::string_view replaceSymbolBody;                    // CLI-first write surface: the same transaction-safe engine as MCP
    std::string_view insertBeforeSymbol;
    std::string_view insertAfterSymbol;
    std::string_view editPayload;                          // --edit-payload=FILE|-: exact bytes; required for a CLI edit
    std::string_view editTargetFile;                       // --edit-target-file=SUBSTR: disambiguate same-named definitions
    bool             prContext       = false;              // --pr-context[=BASEREF]: no-LLM review-evidence bundle for the diff (Wave-4)
    std::string_view prContextBase;                        // --pr-context=BASEREF: diff vs this ref (else the working-tree diff)
    bool             mergeScoutFlag  = false;               // --merge-scout was given at all (tracked separately from the CSV value so a bare
                                                             // `--merge-scout=` still routes to the handler and refuses loudly, rather than
                                                             // silently falling through to the default map)
    std::string_view mergeScout;                            // --merge-scout=REF[,REF...] (L1): read-only cross-branch overlap — per-ref
                                                             // changed symbols vs its merge-base with HEAD, pairwise same-symbol conflicts /
                                                             // same-file textual risks, and a fewest-conflicts-first landing order. The dirty
                                                             // working tree joins as an implicit extra arm. Single-root only (like --pr-context).
    bool             planLanesFlag   = false;               // --plan-lanes[=N]: the PRE-HOC lane plan —
                                                             // split across N worktrees, which lanes would collide and in what order
                                                             // should they land. Tracked apart from the count so a bare --plan-lanes
                                                             // (the --brief form) still routes to the handler. Single-root only.
    int              planLaneCount   = 0;                    // --plan-lanes=N: lanes to carve, 2..16 (auto-carve only)
    std::string_view laneTask;                               // --task="GOAL": what auto-carve partitions the ranked surface of
    std::string_view laneBrief;                              // --brief=FILE: one non-blank line per lane, each ranked on its own
    bool             whereisFlag     = false;               // --whereis was given at all (a bare/empty value still routes to the
                                                             // handler and refuses loudly rather than falling through to the map)
    std::string_view whereis;                               // --whereis=SYM: every ref whose TREE contains SYM,
                                                             // HEAD first, with on-head= saying whether the live line has it at all.
                                                             // Scans each ref's FULL tree; each distinct blob is read once (content-
                                                             // addressed), so N refs cost ~one tree. Single-root only.
    bool             strayContent    = false;               // --stray-content[=SUBSTR]: per ref, the lines its own
                                                             // divergent work AUTHORED that HEAD lacks + a merged/superseded/unmerged
                                                             // verdict. SUBSTR filters the ref names. Single-root only.
    std::string_view strayFilter;                           // --stray-content=SUBSTR: only refs whose name contains SUBSTR
    bool             landingPlan     = false;               // --plan (with --stray-content): "which branches still hold
                                                             // real work, and in what order to land them" — selects the
                                                             // unmerged refs (dropping superseded ones) and feeds them to
                                                             // merge-scout's overlap + landing-order machinery. Alone it
                                                             // would silently no-op — refuses without --stray-content
                                                             // (the --detail/--flip companion-flag pattern).
    bool             abiFlag         = false;               // --abi (with --stray-content): the cross-branch ABI-BREAK gate
                                                             // — for every ref that changed a path HEAD declares a C-family
                                                             // struct/class in, model that struct LEXICALLY on the ref's
                                                             // blob (layout.h's own field-offset arithmetic, reused
                                                             // verbatim) and compare against HEAD's --layout-computed
                                                             // fields; report only DIFFERENCES, exit 2 on a real drift.
                                                             // Single-root only (like --stray-content).
    std::string_view evalStray;                             // --eval-stray=FILE: labelled verdict-accuracy
                                                             // eval for --stray-content. FILE is TSV `ref<TAB>verdict`.
                                                             // The verdict verbs classify rather than rank, so their eval is
                                                             // a confusion table, not recall@k like --eval-retrieval.
    bool             darkFlags       = false;               // --flags[=SUBSTR]: the dark-content dashboard — every
                                                             // #ifndef/#define compile gate, CMake option() and getenv() read, with
                                                             // its kind, default, guarded size and read sites.
    std::string_view darkFlagsFilter;                       // --flags=SUBSTR: only gates whose name contains SUBSTR
    bool             flipFlag        = false;               // --flip was given at all (a bare/empty value still routes to the
                                                             // handler and refuses loudly rather than silently doing nothing)
    std::string_view flipGate;                              // --flip=NAME (with --flags): the blast radius of turning ONE gate ON —
                                                             // the #if regions AND the constexpr-bool branches it governs, the
                                                             // symbols holding them, what those transitively reach, and the tests
                                                             // that cover them. Traverses the alias chain in both directions.
    bool             docDrift        = false;               // --doc-drift[=SUBSTR]: verify the markdown docs'
                                                             // CHECKABLE anchors (file:line refs, backticked symbol mentions,
                                                             // `= N` constants, `[N]` array extents) against the live index and
                                                             // report only the ones that no longer hold.
    std::string_view docDriftFilter;                        // --doc-drift=SUBSTR: only docs whose path contains SUBSTR
    bool             gateabilityFlag = false;               // --doc-drift --gateability (r26-stamp Task B): per-UNDATED-doc
                                                             // "what ONE annotation would make its live rows classifiable" +
                                                             // the projected repo-wide drift= if every listed doc got it.
                                                             // No-op without --doc-drift (cli.h below refuses a bare use).
    bool             withHistory     = false;               // --with-history: turn ON the git-history name oracle
                                                             // (src/gitoracle.h) for --doc-drift and --whereis. OPT-IN
                                                             // because the probe is ONE git log walk over all of HEAD's
                                                             // history — 0.8 s here, 3.0 s on a 2900-file/1863-commit
                                                             // repo, against default paths of 0.15 s / 0.64 s. The
                                                             // result is memoized per (repo, HEAD sha), so the second
                                                             // question on one commit is a cache load, not a walk.
    bool             layoutFlag      = false;               // --layout was given at all (a bare/empty value still routes to the
                                                             // handler and refuses loudly rather than falling through to the map)
    std::string_view layoutStruct;                          // --layout=STRUCT: the CPU/GPU contract view for one
                                                             // struct/class — COMPUTED field offsets/sizes/padding, every
                                                             // static_assert in the index that mentions it, and every same-name
                                                             // definition compared field-by-field (the mirror/stub drift check).
                                                             // file:name disambiguates like --around/--lego. Exit 2 on a mirror
                                                             // mismatch or a sizeof tripwire the computed size contradicts.
    bool             fieldAffinity   = false;               // --field-affinity[=STRUCT]: the CACHE-LOCALITY lens. Which fields are
                                                             // READ TOGETHER (a static field co-access affinity graph, Chilimbi
                                                             // PLDI 1999) but declared far apart, diffed against 64-byte cache-line
                                                             // geometry via the same LP64 offset model --layout uses. Bare = the
                                                             // whole repo, ranked by separation cost. ADVICE ONLY — it never
                                                             // proposes a reordering, because packing advice is non-monotonic
                                                             // (tight packing can induce false sharing).
    std::string_view fieldAffinityStruct;                    // --field-affinity=STRUCT: narrow the report to one aggregate. The
                                                             // AMBIGUITY universe stays the whole corpus either way (a field name
                                                             // declared by two aggregates is refused, never guessed) — see
                                                             // src/fieldaffinity.h::buildFieldOwners.
    std::string_view withProfile;                           // --with-profile=FILE: join --lint findings to the #PROF_TSV
                                                             // block a RIPWIRE_PROFILE build's report emitted — a finding whose
                                                             // enclosing symbol contains a scope site gains measured heat_*
                                                             // attributes (the SYZYGY advice-mode pairing: static shape ×
                                                             // PMU weight). Modifier of --lint only; refused loudly alone.
    std::string_view fromTrace;                             // --from-trace=FILE ('-'=stdin) (B11/L2): map a stack trace /
                                                             // sanitizer report / compiler-error text onto the indexed symbols —
                                                             // table-driven frame extraction (python/asan/node/compiler/generic),
                                                             // innermost-first ranking over IN-CORPUS frames only (out-of-corpus
                                                             // frames listed+counted, never ranked), emits a --for-style bundle.
    std::string_view runTrace;                              // --run-trace="CMD" (VT-1): EXEC-MODE --from-trace. Run CMD under
                                                             // `sh -c` (the make trust model: user privileges, inherited env,
                                                             // stdin=/dev/null, NO sandbox), capture stdout+stderr interleaved,
                                                             // and on a non-zero exit serve the from-trace bundle for the
                                                             // captured text plus a token-frugal <lines> cut of the relevant
                                                             // output lines; exit 0 gets a minimal success record, NO bundle.
                                                             // The command's exit code is ALWAYS disclosed on <run exit=>.
    int              runTimeoutSec   = 0;                   // --run-timeout=SECONDS: cap for --run-trace's command (0 = the
                                                             // default 600 s, disclosed as timeout_s=). At the cap the whole
                                                             // process group is killed and the record says timed_out="1" — an
                                                             // honest TIMEOUT, never an empty success. Modifier of --run-trace
                                                             // only; refused loudly alone (validateConfig).
    bool             noteAddFlag     = false;               // --note-add was given at all (a bare/empty value still routes to the
                                                             // handler and refuses loudly rather than falling through to the map)
    std::string_view noteAdd;                               // --note-add="TARGET: text" (B11/L3): append a field note (target = a
                                                             // canonical id path::scope::name, or a file path) to the committed,
                                                             // sorted .ripwire_notes at the repo root; date = git committer clock,
                                                             // NOT wall time. MUTATES a repo file — single-root only; prints the
                                                             // exact written line and touches nothing else.
    bool             notesList       = false;               // --notes (B11/L3): list all field notes grouped by target, dangling
                                                             // targets (no matching indexed symbol/file — legal) flagged. Read-only.
    bool             packTaskFlag    = false;               // --pack-task was given at all (a bare/empty value still routes to the
                                                             // handler and refuses loudly rather than falling through to the map)
    std::string_view packTask;                              // --pack-task="TASK" (B11/L4): the budget-shared task bundle — ONE call
                                                             // assembling, under ONE deterministic budget (default 6K tokens;
                                                             // --token-budget overrides), the 5-call orientation dance in FIXED order:
                                                             // (1) routed+anchored ranking, (2) top-K full bodies, (3) their 1-hop
                                                             // caller signatures, (4) their field notes, (5) tests_to_run for the top
                                                             // files, in FIXED order ranking>bodies>callers>notes>tests. Each section
                                                             // holds a FIXED, up-front proportional quota of the budget (rank40/
                                                             // body30/caller15/note5/test10, pct); an under-spent section's leftover
                                                             // quota rolls forward, so a small budget still zeroes a section
                                                             // eventually but never past its own fair share. Each section truncates
                                                             // rank-adaptively and the header reports EVERY truncation.
    int              partitionCount  = 0;                   // --partition=N (with --pack-task): fan-out form of the
                                                             // bundle — ONE shared common core plus N minimally-overlapping per-agent
                                                             // slices carved along the call graph's own Louvain communities, each
                                                             // through the SAME assembler. --token-budget then means the budget for
                                                             // ONE AGENT (core + its partition), not the whole document. 0 = off;
                                                             // legal range 2..16; alone (without --pack-task) it refuses loudly.
    bool             withGraph        = false;             // --with-graph (R8, with --for/--pack-task): append a compact MERMAID
                                                             // flowchart of the bundle's top-N (<=8) ranked anchors + their 1-hop
                                                             // call edges among themselves, as <graph fmt="mermaid"><![CDATA[...]]></graph>
                                                             // right before </ctx>. Reuses the --mermaid emitter's syntax, not a new
                                                             // one. Off by default (G5: additive) — omitted, output is byte-identical.
    bool             exportCcJson    = false;              // --export=cc.json[:FILE]: CodeCharta interchange export (Wave-4)
    std::string_view exportFile;                           // --export=cc.json:FILE: write to FILE (else stdout)
    bool             noRedact        = false;              // --no-redact: emit source/doc bodies VERBATIM (skip the credential redaction; local-only workflows)
    bool             refetch         = false;              // S3: --refetch: force a fresh git clone of a git-URL root instead of reusing the cached one
    bool             doctor           = false;              // --doctor: self-diagnosis (binary/PATH staleness, grammar load, cache-dir
                                                             // health, git reachability, tree-sitter version) — a DIAGNOSTIC verb, not
                                                             // the deterministic map; environment-dependent lines are its whole point.
    bool             skippedList      = false;              // --skipped (§P0.5d, §L1): WHY the index does not contain a file, and
                                                             // which files it DOES contain but cannot vouch for — one <f p= why=/> row
                                                             // per drop (oversize/excluded/unsupported-ext) plus <h p= why=/> rows for
                                                             // indexed-but-suspect files (degraded-parse/minified-suspect) and <e x=/>
                                                             // per unindexed extension. Read-only; exit 0 always.
    std::string_view since;                                 // --since=REV|DATE: scope churn/co-change mining to commits after this point
                                                              // (--hotspots/--cochange/--rank-by=churn). REV (e.g. HEAD~20, a tag) is
                                                              // deterministic; a git approxidate ("2 weeks ago") is wall-clock-relative
                                                              // by construction. Absent/unresolvable ⇒ unchanged all-history default —
                                                              // additive flag, degrades clean (never crashes on a bad value).
    bool             ok              = true;      // false ⇒ parse error / usage printed
};

inline bool startsWith( std::string_view s, std::string_view p ) noexcept
{
    return s.size() >= p.size() && std::memcmp( s.data(), p.data(), p.size() ) == 0;
}

// parse a NUL-terminated "...=<int>" value tail; reject empty / non-numeric / <1 / overflow
// (so `--top-k=` no longer silently becomes 0 = "emit ALL symbols").
inline bool parsePosInt( const char* s, int& out ) noexcept
{
    char*      end = nullptr;
    const long v   = std::strtol( s, &end, 10 );
    if( end == s || *end != '\0' || v < 1 || v > 1000000000 )
    {
        return false;
    }
    out = int( v );
    return true;
}

// like parsePosInt but 0 is VALID (for --offset=0 = "from the start"). Rejects empty / non-numeric /
// negative / overflow. Kept separate so --limit / --top-k stay strictly positive (0 = "emit all" trap).
inline bool parseNonNegInt( const char* s, int& out ) noexcept
{
    if( s[0] < '0' || s[0] > '9' )
    {
        return false; // reject "-1"/"" (strtol would wrap/accept)
    }
    char*      end = nullptr;
    const long v   = std::strtol( s, &end, 10 );
    if( end == s || *end != '\0' || v < 0 || v > 1000000000 )
    {
        return false;
    }
    out = int( v );
    return true;
}

// §A10.2 — WHY a --limit/--offset value was refused, not just THAT it was. Both flags used to answer every
// bad value with the same one-liner, and for an out-of-range value that sentence is simply untrue:
// `--offset=999999999999` was refused with "needs a non-negative integer" when the value IS non-negative
// and merely exceeds the accepted range. The house refusal shape (used by --partition, --plan-lanes,
// --token-budget) names the flag, states the actual problem, and shows what to type instead.
//
// kPageValueMax is parsePosInt's own ceiling, restated here so the two cannot drift: the paging flags stay
// on exactly the range every other integer flag accepts.
inline constexpr long kPageValueMax = 1000000000;

// §B8.2 — the ONE sentence a bad flag VALUE is refused with, so the surface cannot grow a second dialect.
// Ten numeric arms each hand-wrote their own fprintf and every one of them drifted the same way: a single
// fixed sentence for empty AND garbage, with neither the offending value nor an example in it —
// `--zoom=` and `--zoom=zzq` were byte-identical refusals, so a caller whose $DEPTH expanded to nothing
// could not tell an unset variable from a typo without re-reading its own command line. The compliant
// shape was already in this file twice (refusePageValue below, refuseEmptyValue further down): name the
// FLAG, state the DOMAIN, echo what was GOT, show something RUNNABLE.
//
// `got` is a view because the --path arm's value is a slice of argv, not a NUL-terminated tail.
inline void refuseFlagValue( const char* flag, const char* wanted, std::string_view got, const char* example ) noexcept
{
    std::fprintf( stderr, "ripwire: %s needs %s — got '%.*s', e.g. %s\n", flag, wanted, int( got.size() ), got.data(), example );
}

// Parse ONE paging value and, on refusal, print the reason itself. Returns false ⇔ the caller must set
// c.ok = false and bail — the arms stay one line each, which is what keeps 91 parse arms readable.
inline bool refusePageValue( const char* flag, const char* s, bool isZeroAllowed, int& out ) noexcept
{
    const long   least   = isZeroAllowed ? 0 : 1;
    const char*  wanted  = isZeroAllowed ? "a non-negative integer" : "a positive integer";
    char*        end     = nullptr;
    // first char must be a digit: strtol would accept "-1" (and " 12"), and a negative value must read as
    // "not an integer we accept" rather than as an out-of-range one
    const bool   isDigit = s[0] >= '0' && s[0] <= '9';
    const long   v       = isDigit ? std::strtol( s, &end, 10 ) : 0;

    // the paging flags' example is the flag itself at a round value — built here rather than passed in so
    // the two paging arms stay one line each, and printed through the shared refusal above so a change to
    // the sentence reaches every value-taking flag at once.
    char example[64] = {};
    std::snprintf( example, sizeof( example ), "%s=100", flag );

    if( !isDigit || end == s || *end != '\0' || v < least )
    {
        refuseFlagValue( flag, wanted, s, example );
        return false;
    }
    if( v > kPageValueMax )
    {
        std::fprintf( stderr, "ripwire: %s=%s is out of range (the maximum is %ld) — e.g. %s=100\n", flag, s, kPageValueMax, flag );
        return false;
    }
    out = int( v );
    return true;
}

// §A9 V1-4 — an EMPTY value is a MISTYPED VERB, not a request for the default map. `--grep=` (usually a
// shell variable that expanded to nothing) fell through every value-taking arm and printed the whole
// 6302-symbol ranked map at exit 0: the caller asked a question and silently got an atlas. Five verbs
// (--whereis / --pack-task / --community / --zoom / --exercises) already refused, each through its own
// hand-written sentence in its own handler. This is that refusal expressed ONCE, so a value-taking flag
// inherits it by filling in two table columns instead of by remembering to copy a paragraph — and so a NEW
// value-taking flag cannot ship without its author deciding, in the table, whether an empty value means
// anything for it.
//
// §B5 (capture-audit-4) made that last clause TRUE rather than aspirational: "deciding in the table" only
// binds arms that are IN the table, and 40 were not. 23 moved in, and the EmptyValue column beside the
// prefix makes the decision a required, named, consteval-checked field. The counts that used to sit in this
// paragraph are deliberately gone — a rotted count is trap-ledger #12, and kViewFlags/kHandWrittenFlagArms
// are the two places that state them, each with a gate that re-derives them from source.
//
// `flag` is the table's prefix spelling ("--grep="); the trailing '=' is dropped for the sentence so the
// refusal names the FLAG and the example names the spelling to type — the house shape refusePageValue and
// the --partition / --plan-lanes guards already use.
inline void refuseEmptyValue( std::string_view flag, const char* needs, const char* example ) noexcept
{
    const std::string_view bare = flag.substr( 0, flag.size() - 1 );
    std::fprintf( stderr, "ripwire: %.*s= is empty — it needs %s, e.g. %s\n", int( bare.size() ), bare.data(), needs, example );
}

// parse a NUL-terminated "...=<u64>" value tail with the same reject rules as parsePosInt: empty /
// non-numeric / signed / zero / overflow (so `--pack-budget-bytes=-1` no longer wraps to 2^64-1 and
// `=abc` no longer silently becomes 0). First char must be a digit — strtoull would accept "-1" by wrapping.
inline bool parsePosU64( const char* s, std::size_t& out ) noexcept
{
    if( s[0] < '0' || s[0] > '9' )
    {
        return false;
    }
    char* end = nullptr;
    errno     = 0;
    const unsigned long long v = std::strtoull( s, &end, 10 );
    if( end == s || *end != '\0' || v < 1 || errno == ERANGE )
    {
        return false;
    }
    out = std::size_t( v );
    return true;
}

// parse a "...=<u64>[K|M|G]" BYTE-SIZE value: an optional single-char suffix (case-insensitive, powers of
// 1024, a trailing "B" tolerated so "10MB" works) scales the number; a bare number is bytes. Same reject
// rules as parsePosU64 (empty / signed / zero / bad-suffix / overflow). Used by --max-file-size.
inline bool parseByteSize( const char* s, std::size_t& out ) noexcept
{
    if( s[0] < '0' || s[0] > '9' )
    {
        return false;
    }
    char* end = nullptr;
    errno     = 0;
    const unsigned long long v = std::strtoull( s, &end, 10 );
    if( end == s || v < 1 || errno == ERANGE )
    {
        return false;
    }

    std::size_t mult = 1;
    if( *end != '\0' )                                        // an optional K/M/G scale suffix
    {
        switch( *end )
        {
            case 'k': case 'K': mult = 1024ull;                    break;
            case 'm': case 'M': mult = 1024ull * 1024;             break;
            case 'g': case 'G': mult = 1024ull * 1024 * 1024;      break;
            default:            return false;
        }
        ++end;
        if( *end == 'b' || *end == 'B' )
        {
            ++end; // tolerate the "B" of KB/MB/GB
        }
        if( *end != '\0' )
        {
            return false;
        }
    }
    if( v > static_cast<unsigned long long>( SIZE_MAX / mult ) )
    {
        return false; // overflow guard
    }
    out = std::size_t( v ) * mult;
    return true;
}

// The self-documenting surface: a coding agent that finds the binary learns the WHOLE surface here,
// grouped by the question each flag answers. Keep this complete — it is the cold-start contract (README
// mirrors it). --help prints to stdout (exit 0); a parse error prints the same to stderr (exit nonzero).
// The --plan-lanes rows, split out of printUsage's one giant literal rather than appended to it: this verb's
// help carries the whole claim-key argument and the auto-carve caveat (the single most important sentence in
// it), which is a paragraph, not a row — and printUsage is already the longest function in this file.
inline void printPlanLanesUsage( std::FILE* out ) noexcept
{
    std::fprintf( out,
        "    --plan-lanes=N --task=GOAL PRE-HOC lane plan: BEFORE a line is written, if this task is split across N isolated\n"
        "                               worktrees (N=2..16), which lanes would COLLIDE and in what order should they land.\n"
        "                               Where --merge-scout says \"these branches already conflict\", this says \"these lanes\n"
        "                               WOULD conflict if assigned this way\" — no ref to resolve, no archive, no re-ingest.\n"
        "                               JSON on stdout, always (redirect it: > .ripwire_lanes.json); ripwire writes no file.\n"
        "                               Exit 0 whenever a plan was produced, INCLUDING when conflicts are predicted (conflicts\n"
        "                               are data, and the landing order exists to handle them); exit 1 only for refusals.\n"
        "                               A claim keys on path+scope+name, never on id= (id degrades to a bare NAME when no scope\n"
        "                               was captured, so free functions in different files would collide); id= is carried per row\n"
        "                               for addressability, null when it would be bare, with id_addressable saying so. Three\n"
        "                               separate pair classes: conflicts[] (same claim key on both lanes — git will fight),\n"
        "                               same_file_risk[] (different keys, same file, aggregated per file), contract_touch[] (one\n"
        "                               lane's claim sits in another's blast radius — an adaptation, NOT a merge conflict). The\n"
        "                               conflict test runs on CLAIMS, never on blast radii. warnings[] carries every honest limit\n"
        "                               in band with a stable code. Single-root only. AUTO-CARVE SPLITS THE RANKED SURFACE, NOT\n"
        "                               YOUR SENTENCE: if your task has enumerable parts, use --brief and write one line per part.\n"
        "    --plan-lanes --brief=FILE  the explicit form of the above: one non-blank line per lane, N = the line count. Each line\n"
        "                               is ranked on its own — no community carve, no bin packing — so the lane boundaries are the\n"
        "                               ones you wrote. This is the mode whose precision is defensible; prefer it when you can.\n"
        "                               Lane isolation is a QUALITY argument, not a speed one (CAID, arXiv 2603.21489: 63.3%% vs\n"
        "                               55.5%% shared, largest gains on weaker lane models — and wall clock got WORSE).\n" );
}

inline void printUsage( std::FILE* out ) noexcept
{
    std::fprintf( out,
        "ripwire — the \"ripgrep of AI context\": parse a codebase, rank symbols by Personalized PageRank,\n"
        "stream a deterministic minified XML map to stdout. Zero runtime deps. Languages: C++, C, ObjC/ObjC++,\n"
        "Metal (MSL, .metal — C++ grammar), CUDA (.cu/.cuh — tree-sitter-cuda, <<<>>> launches are call edges),\n"
        "Python, TypeScript, JavaScript, Java, Ruby, PHP (.php/.phtml), Lua, Bash, Go, Rust, Swift, C#;\n"
        "JSON, TOML, YAML (config keys); Markdown (.md/.markdown — headings are section symbols with spans).\n\n"
        "usage: ripwire <dir> [flags]            # default = the ranked map of <dir> on stdout\n"
        "       ripwire <dir1> <dir2> ... [flags] # multi-root workspace: ONE merged graph over 2..16 checkouts\n"
        "                                        # (service+client, split monorepo). Paths are labeled <root>/<rel>;\n"
        "                                        # cross-root edges only on explicit evidence (path-resolved include/\n"
        "                                        # import, FFI binding) — same-name symbols in unrelated repos stay\n"
        "                                        # unlinked. Root order on the command line is irrelevant (canonical).\n"
        "                                        # Per-root git history; --quality-delta/--test-gate/--eval*/--arch\n"
        "                                        # baselines/--pr-context stay single-root (run them per root).\n"
        "       ripwire <git-url> [flags]        # shallow-clone the repo to a temp cache dir, then map it (https:// or git@)\n"
        "       ripwire wrap <agent>             # print the recipe to wire ripwire into claude|cursor|codex|aider|...\n\n"
        "  understand a codebase cold\n"
        "    <dir>                      ranked symbol map (start here)\n"
        "    --top-k=N                  keep the N highest-ranked symbols (default 200) — applies to the default map,\n"
        "                               plain --query, and --format=candidates (incl. with --for). --for's OWN\n"
        "                               signature/lego/compose bundle self-limits via --pack-top-n instead — --top-k is\n"
        "                               INERT there (documented, not fixed — a real fix is a behavior change).\n"
        "                               --pack-task/--from-trace/--run-trace/--situ self-budget via --token-budget, not --top-k.\n"
        "                               --top-k=0 emits NO ranked map at all — ONLY the payload you asked for\n"
        "                               (--expand/--outline/--pack-signatures/--pack-top-n). Use it when you want the\n"
        "                               body and not the ~200-symbol map that otherwise rides along with it.\n"
        "    --max-tokens=N             budget the map to ~N tokens (binary-search top-K) — SHAPES the map to fit.\n"
        "                               THE FIT IS A BYTE CEILING, and it is deliberately CONSERVATIVE: N is converted at\n"
        "                               2.36 B/tok (the densest calibrated language, so N holds for any corpus) times a 0.90\n"
        "                               headroom factor. The map's own est_tokens uses THIS corpus's language-weighted rate\n"
        "                               instead, so a conformant fit REPORTS a number below the N you asked for — expect\n"
        "                               ~10-20%% of N unused. The shaped map discloses both: max_tokens=N (asked) and\n"
        "                               fit_bytes=B (honoured). Consequence for composing it with --token-budget=N below:\n"
        "                               the two Ns are different units, so the same N on both is NOT a tautology.\n"
        "                               At a SMALL N the map's fixed floor (envelope + legend) can exceed fit_bytes with\n"
        "                               even one symbol emitted — that map says over_ceiling=1 rather than overshoot in\n"
        "                               silence, and its est_tokens can then exceed N. XML only: the --json map carries\n"
        "                               no max_tokens=/fit_bytes= keys yet, and its fit is measured in XML bytes.\n"
        "                               On --recall it SHAPES the doc bundle the same way: docs are dropped from the\n"
        "                               BOTTOM of the ranking and the last one may be cut within itself — every cut is\n"
        "                               DISCLOSED (header total=/shown=/capped=/truncated=, a per-doc [truncated: X of Y\n"
        "                               bytes] marker, and a closing (capped: …) note). Selection order never changes.\n"
        "    --token-budget=N[K|M|G]    two personalities depending on the verb:\n"
        "                                 - default map / --query / --recall: a CI GATE — exit 3 if the emitted DOCUMENT's\n"
        "                                   est_tokens exceeds N. That is the map PLUS every block appended after it\n"
        "                                   (<sigs>/<src>/<bodies>/<outline>), each charged from the bytes it actually\n"
        "                                   emits at the calibrated rate for what those bytes are — so\n"
        "                                   --pack-top-n=3 --token-budget=600 gates on the ~67KB it would stream, not on\n"
        "                                   the map alone. (test/tokenbudgetcheck.sh reports the live MAPE vs tiktoken\n"
        "                                   o200k when tiktoken is installed; the estimate is calibrated, never exact —\n"
        "                                   Claude's tokenizer is not public.) Within budget: exit 0, output unchanged.\n"
        "                                   ASSERTS and fails, vs --max-tokens which shapes to fit — composable: set\n"
        "                                   neither, either, or both (e.g. --max-tokens=16000 --token-budget=16K), but see\n"
        "                                   --max-tokens above: the two Ns are measured in different units.\n"
        "                                   Over budget, nothing of the artifact reaches stdout — only a small record\n"
        "                                   naming withheld_est_tokens= vs budget=, the same vocabulary --recall uses,\n"
        "                                   since est_tokens= is normatively about what a run PRINTED. On --recall the\n"
        "                                   check likewise runs BEFORE a byte of the bundle is emitted: stdout gets the\n"
        "                                   header line naming what was withheld, never the artifact just rejected.\n"
        "                                   --json GATES AT A DIFFERENT NUMBER for the same request, and by design: the\n"
        "                                   flag measures the DOCUMENT that was emitted, and the JSON encoding of the\n"
        "                                   same map is smaller than the XML one (MEASURED on src/ --top-k=200:\n"
        "                                   est_tokens 577 XML vs 435 JSON, ~25%% apart). So the same N can pass under\n"
        "                                   --json and fail without it — pick the budget for the dialect you emit.\n"
        "                                 - --for / --pack-task / --from-trace / --run-trace: SHAPES instead of gating — overrides that\n"
        "                                   lens's own default payload budget and trims to fit, always exit 0. --for's\n"
        "                                   header reports est_tokens=\"N\" so its fit is checkable; --pack-task/--from-trace\n"
        "                                   report their budget ledger in the header report line instead. On --for's auto\n"
        "                                   bundle the ceiling is SPLIT, not handed to the signatures first: the sig side's\n"
        "                                   claim caps at the default sig budget and the rest flows to the inline bodies,\n"
        "                                   so a wider ceiling never serves fewer of them (see --for below).\n"
        "                                   Its VERBATIM task echo is bytes no trim can shrink, so past some task length the\n"
        "                                   header floor alone exceeds the ceiling: the lens drops the comment's DUPLICATE echo\n"
        "                                   first (task_echo: dropped (ceiling); task= keeps the verbatim copy), then labels it\n"
        "                                   over_ceiling (--recall: over_ceiling=1) — never a trim it did not actually do.\n"
        "    --help-task=TASK           deterministic enhanced help: recommend ONE executable Ripwire CLI command for this\n"
        "                               repository and task, or abstain when evidence/applicability is insufficient. Reports\n"
        "                               the intent, integer score/margin and repository facts; never calls a model, executes\n"
        "                               the recommendation, or accesses the network. Structured claims/traces/symbols outrank\n"
        "                               lexical cues. Recommendation only; pipe trace text to stdin for --from-trace=-.\n"
        "    --for=TASK                 the task lens: ranked signatures + metrics framed for reuse. The bundle enforces a\n"
        // §B7.5 (CA4): this said <sigs payload="capped"> — the STRING ENUM the §P8 vocabulary migration
        // replaced with the boolean capped="1" every other truncating element spells (serialize.h's own
        // comment records the rename). No output the tool can emit has contained payload= since; --help was
        // the last place the dead spelling survived, and a reader grepping their bundle for it finds nothing.
        "                               ~7.5KB default payload budget (tail entries trim first; <sigs capped=\"1\"> marks\n"
        "                               it) — an explicit --token-budget=N overrides the default at the conservative byte rate\n"
        "                               (SHAPES, exit 0; see --token-budget above) and the header reports the delivered est_tokens.\n"
        "                               TERMINAL BY DEFAULT: after the signatures, the top-ranked symbols' FULL bodies ride\n"
        "                               inline (CDATA + callee signatures, the --expand shape) under a fixed extra body allowance —\n"
        "                               whole-body-or-not-at-all, rank-first, capped at the --pack-task candidate cap (6). The <ctx>\n"
        "                               root discloses it: bundle=\"auto\" bodies=\"N\" (bodies=\"0\" reason=\"budget\" when none fit) —\n"
        "                               on EVERY auto-mode run: a ceiling the signatures alone exhaust still carries the attribute\n"
        "                               (legend and empty <bodies> shell dropped there; only the attribute has reserved bytes), and\n"
        "                               --for --json, which serves no bodies by design, says so with \"bundle\":\"sigs\". Only the\n"
        "                               caller-chosen postures (--signatures-only, --detail=N) are attribute-free.\n"
        "                               ANCHOR-ONLY when the route names one: a query that NAMES a symbol gets THAT symbol's own\n"
        "                               body or NO body — never a same-named doc section, type stub or re-export shim from another\n"
        "                               file standing in for it. If the anchor's own body does not fit, the bundle serves nothing\n"
        "                               and says so, and the per-item over-budget comment names what was dropped.\n"
        "                               COMPACT ON THE CONCEPTUAL ROUTE: a query that anchors nothing (subtoken+body) gets the\n"
        "                               ranked map plus a <hops> section — the same candidate head's ONE-HOP callee signatures,\n"
        "                               the <calls> block a body carries — and NO body CDATA, disclosed as bundle=\"compact\"\n"
        "                               bodies=\"0\" reason=\"compact-route\". Read the map, then --expand=SYM the one you want.\n"
        "                               --auto-bodies restores the body walk there. That shape discloses on every run too: a\n"
        "                               ceiling the signatures alone exhaust carries bundle=\"compact\" bodies=\"0\"\n"
        "                               reason=\"budget\" — three distinct reasons, never collapsed (compact-route = the route\n"
        "                               chose edges, no_candidates = nothing scored, budget = the ceiling was spent).\n"
        "                               An explicit --token-budget=N is a hard ceiling, split so a wider ceiling never buys less:\n"
        "                               the signature side's claim is capped at the DEFAULT ~7.5KB sig budget and every byte beyond\n"
        "                               it flows to the enrichment — at any ceiling at or above the default's effective total the\n"
        "                               <sigs> block is byte-identical to the default run's, so every body (or hop row) the default\n"
        "                               serves still fits. An explicit --pack-top-n is an explicit SIG posture and keeps the\n"
        "                               whole-ceiling sig claim\n"
        "    --signatures-only          (with --for) opt out of the terminal-by-default bundle: no auto bodies, no bundle=\"auto\"\n"
        "                               attribute — the signatures-only lens exactly as before. Contradicts --detail=N (refused\n"
        "                               together); --detail=N remains the explicit body knob and supersedes the automatic pick\n"
        "    --auto-bodies              (with --for) opt out of COMPACT conceptual serving: restore the rank-first auto <bodies>\n"
        "                               walk on the subtoken+body route (bundle=\"auto\", up to 6 full bodies) instead of the\n"
        "                               <hops> edge section. Inert on the name-exact route, where the allowance already runs.\n"
        "                               Contradicts --signatures-only and --detail=N (refused with either)\n"
        "    --no-route                 (with --for/--query) force plain subtoken+body BM25. Routing is now the DEFAULT: a deterministic,\n"
        "                               confidence-gated query-shape router picks name-exact BM25 when the query NAMES a symbol (identifier\n"
        "                               syntax, or every content word is a symbol name) else subtoken+body, and prints which/why in the\n"
        "                               header. It only routes with a query (the plain map is unaffected). --no-route restores the old behavior.\n"
        "                               A name-exact header also names its EVIDENCE: anchors: word(defining/file) per anchoring word, +N when N\n"
        "                               further definitions share that name, or word(syntax) when the word routed on camel/snake SHAPE and names\n"
        "                               nothing. Paths deeper than two segments print top/.../basename. Discount a one-use test helper yourself.\n"
        "    --adaptive                 (with --for/--query) cut the result at the relevance CLIFF — the largest relative score gap\n"
        "                               (Adaptive-k), floor 5, ceiling = the existing top-k; a sharp query returns few, a flat/broad one\n"
        "                               hits the ceiling. Prints [adaptive: kept K of N ...] in the header. Without it, output is unchanged.\n"
        "    --no-mention-boost         (with --for) disable the query-mention anchor. By DEFAULT, a file, dotted module, or\n"
        "                               Scope.symbol literally NAMED in the task text (a path, `pkg.module`, `Type.method` — even\n"
        "                               inside a URL) is lifted to just below the top hit; the header says what anchored. Inert\n"
        "                               (byte-identical) when the text names nothing indexed. RIPWIRE_NO_MENTION=1 disables it\n"
        "                               everywhere (incl. MCP `for`).\n"
        "    --no-doc-mention           (with --for) disable doc-mention surfacing. By DEFAULT, a markdown doc that names one of\n"
        "                               the task's top-resolved symbols in a `backtick` (the same doc<->code edges --mentions=SYM\n"
        "                               reads) is lifted into the bundle, strictly below that symbol's own score — closing the\n"
        "                               \"the doc explains it but shares no words with the query\" gap. Inert (byte-identical)\n"
        "                               when no resolved symbol has a mentioning doc. RIPWIRE_NO_DOC_MENTION=1 disables it\n"
        "                               everywhere (incl. MCP `for`/`pack_task`).\n"
        "    --lego=TYPE                the interface->impls view for ONE named interface/base: its signature, method contract,\n"
        "                               and every implementor (own-language only). file:name disambiguates a same-named type.\n"
        "                               No contract for a language this surface cannot read soundly: methods=0 caveat=… says so.\n"
        "    --exemplar=TASK|KIND       before you write: the repo's best-in-class instance to IMITATE. Just pass a plain task —\n"
        "                               --exemplar=\"format byte sizes\" — and the KIND is inferred from the top match; or name a\n"
        "                               KIND directly (fn|method|class|struct|iface|var). Picks by ROLE — lowest cognitive cx\n"
        "                               under a hard ccx ceiling, then tested + highest fan-in; test-fixture paths de-prioritized —\n"
        "                               NOT text similarity (similar-snippet retrieval measurably hurts). A weak task match falls\n"
        "                               back to fn (low_confidence=1); an all-over-ceiling kind flags over_ccx_bar=1\n"
        "    --recall=TASK              recall the most relevant DOCS — memory/plans/designs, full bodies (md, .ipynb/.html/.csv,\n"
        "                               plus Office/PDF via the optional markitdown bridge). This is the tool's LARGEST output:\n"
        "                               its header reports est_tokens + total=/shown=/capped=, where total= is the TRUE relevant\n"
        "                               count (score > 0) and shown= is what this run actually emitted. The header's \"of N document\n"
        "                               files\" denominator counts every file the index carries as a DOCUMENT — .md plus the\n"
        "                               docparse'd .ipynb/.html/.csv — so it is a SUPERSET of --doc-drift's docs=, which is an\n"
        "                               extension test (markdown only). Two populations, two names, deliberately. --top-k=N shapes HOW MANY\n"
        "                               docs are emitted (default 8, not the general --top-k default of 200). Recall defaults to an\n"
        "                               8000-token body ceiling; --max-tokens=N overrides it and shapes to fit (disclosing each cut),\n"
        "                               while --token-budget=N gates the finished artifact (exit 3, nothing streamed).\n"
        "                               GENERATED documents rank LAST by default — a doc that declares itself generated in\n"
        "                               its first lines, or is BOTH >=5x the median doc's size AND mostly ```-fenced quoted\n"
        "                               output (a capture/API dump quotes every term, so BM25 hands it every query). Never\n"
        "                               dropped: it still wins when nothing else matches. Each one says [generated_demoted:\n"
        "                               marker|size+fences] on its own line and the header tallies generated_demoted=N\n"
        "    --tree                     file-by-file orientation map (top symbols per file)\n"
        "    --html[=FILE]              self-contained HTML force-directed call graph (no CDN — redirect or write FILE)\n"
        "    --color-by=MODE            (with --html) node colour: lang (default) | community | cx | churn | tested — the page embeds all\n"
        "                               five and keeps a live selector; the flag only sets the initial mode\n"
        "    --order=MODE               emit order: stable (path/id order — provider KV-cache hits across re-runs) |\n"
        "                               important-first (rank order, the default; no auto-flip) | important-last\n"
        "                               (highest-rank content emitted last — recency bias for an LLM). Large default\n"
        "                               maps auto-flip to important-last past ~50%% of a nominal 32K window\n"
        "                               (est_tokens>16000) unless MODE is explicitly given.\n"
        "    --no-stable                opt out of the stable ordering that --mcp enables by default\n\n"
        "  navigate / answer a question\n"
        "    --around=SYM               ego graph around SYM   [--around-depth=N] [--around-fanout=K]\n"
        "    --callers=SYM              who calls SYM (1-hop in-edges). file:name disambiguates a same-named symbol across files (like --around/--lego)\n"
        "    --callees=SYM              what SYM calls (1-hop out-edges). file:name disambiguates like --callers\n"
        "    --uses=SYM                 the statically resolvable use-sites of SYM (role=call|macro|read|write|import|extends|type, file:line); external=\"1\" if SYM has no in-corpus def.\n"
        "                               file:name narrows defs= AND the role=\"call\" sites (kept only where the call RESOLVES to a chosen def —\n"
        "                               --callers' own narrowing); read/write/import/extends carry no resolution and stay name-matched.\n"
        "                               narrowed_roles=/defs_of_name=/call_sites_of_name= (file: qualifier only) disclose what narrowed and\n"
        "                               the un-narrowed totals; a file: qualifier naming a file with no such def REFUSES, like --callers/--impact\n"
        "    --graph-query=EXPR         composable node-set query over the call graph: sources name(\"X\")/all; filters kind|cx|fanin|file|layer;\n"
        "                               bounded closure callers|callees(SET[,depth]); joins and|or|not.  e.g. and(callers(name(\"foo\"),2),kind(all,fn));\n"
        "                               file() regex example: file(\"src/.*\\\\.cpp\") (or in bash, use single quotes: file('src/.*\\.cpp'))\n"
        "                               layer(SET,NAME) keeps the architecture layer NAME (game|infra|render|math|audio|ai|test) — the SAME\n"
        "                               built-in directory-name taxonomy the map prints as layer= on a file node, so the two cannot disagree.\n"
        "                               It does NOT read a --arch=FILE rules file: --arch is a verb and outranks --graph-query, so the two never\n"
        "                               run together. An unknown layer word, or ANY layer() against a tree where no path names a layer, is\n"
        "                               REFUSED (exit 1) rather than answered count=\"0\" — 0 there would read as \"no such code\".\n"
        "                               a name(\"X\") literal matching NO indexed symbol refuses with a did-you-mean (a typo is not a count=0);\n"
        "                               a query whose names all resolve but that selects nothing still reports count=\"0\" — that IS a measurement\n"
        "                               (including a VALID layer with no members in a tree that does have layers).\n"
        "                               Ranked result set is capped at --top-k (default 200); --limit overrides that cap (raise or lower it),\n"
        "                               --offset pages past it — see --limit=N --offset=M above\n"
        "    --external-surface         names referenced but never defined in-corpus (the stdlib/third-party surface), by ref count;\n"
        "                               each row's lang= is the REFERENCING file's language — a name called from several languages\n"
        "                               (e.g. printf: C stdio call vs Bash builtin) gets one row PER language, not a merged count\n"
        "    --path=SRC,DST             shortest directed call-path SRC -> DST\n"
        "    --connect=A,B,C            minimal connecting subgraph over 2..16 symbols: terminals + fewest joining intermediaries +\n"
        "                               call edges in TRUE direction (finds the shared-caller join a directed --path can't)   [--connect-radius=N (1..12, default 6)]\n"
        "    --impact=SYM               transitive blast radius — the indexed symbols that reach SYM (a floor, see counts_floor). file:name disambiguates like --callers\n"
        "                               importers= is a SECOND, weaker reach beside it: the files that directly include/import a file defining SYM,\n"
        "                               emitted as <f via=\"import\" lazy=\"0|1\"> rows (format=columnar carries the count only). NEVER added to reaches= —\n"
        "                               files and symbols are different units, and an importer may use a different symbol from that file, or none at all.\n"
        "                               lazy=\"1\" (TS/JS only): every one of that importer's edges is a require()/import() written inside a function\n"
        "                               body, not at module load time — still a real dependency, weaker than a top-level one\n"
        "    counts_floor=\"1\"           on --callers/--callees/--uses/--impact/--edit-check every count is a FLOOR, never a total: the\n"
        "                               call graph is extracted from source text by name, so dynamic dispatch\n"
        "                               and declarations that parse without a call expression (C++ most-vexing-parse) contribute no edge;\n"
        "                               a call through a function pointer/callback is an edge only when ONE function is bound to that\n"
        "                               variable in scope (reassigned/table-indexed/lambda-bound/escaped — address-taken or\n"
        "                               reference-bound — pointers stay edge-less, C-family);\n"
        "                               a macro-generated call site contributes a role=\"macro\" edge when its name uniquely names an\n"
        "                               indexed function-like #define (t=\"macro\"); a shared name stays a plain call, an unindexed\n"
        "                               macro's site is no edge. Read a 0 as \"none found\", never as \"none exists\". Those five\n"
        "                               verbs also count DISTINCT (caller,callee) pairs, while --uses counts call SITES — see each verb's own legend\n"
        "    pr_iters=\"N\"               on every PageRank-ordered document (the map, and the tree, seams, communities, zoom,\n"
        "                               impact, graph-query and exercises verbs, plus their MCP twins): how many power iterations produced that\n"
        "                               ordering. The iteration stops when the L1 residual between successive rank vectors falls below\n"
        "                               tolerance, or at a fixed iteration ceiling, whichever comes first. pr_converged=\"0\" is emitted\n"
        "                               ONLY on that second exit and means the ranking is a rank vector that stopped SHORT of tolerance,\n"
        "                               not the fixed point it approximates. ABSENCE MEANS IT CONVERGED (there is no pr_converged=\"1\":\n"
        "                               the converged path is the normal one and must cost zero bytes), and absence of pr_iters= itself\n"
        "                               means the document was not ordered by a power iteration at all (a lexical query score, or a hub\n"
        "                               or authority HITS vector), never that the count is unknown\n"
        "    --verify=\"CLAIM\"           VERIFY A CLAIM about the code in ONE call: a CLOSED claim language in, a three-valued verdict out\n"
        "                               (confirmed / refuted / not-established) with the evidence rows inline — the collapse of the manual\n"
        "                               verification grep-chain. Shapes: calls(A,B) does A transitively call B; uses(SYM) / unused(SYM) is\n"
        "                               SYM referenced anywhere / nowhere; contains(FILE, \"LIT\") do FILE's indexed bytes contain the\n"
        "                               literal; defines(FILE, SYM) does FILE define SYM; reaches(SYM, \"FILE\"|LAYER) does code in that\n"
        "                               file/layer transitively call SYM (LAYER unquoted: game|infra|render|math|audio|ai|test).\n"
        "                               refuted appears ONLY with complete evidence: a clean literal-scan absence carries complete=, and an\n"
        "                               unused claim is refuted by printed witness sites. A graph or reference ZERO can never refute — it\n"
        "                               yields not-established with limit= naming the floor (call-graph-floor, reference-floor,\n"
        "                               collection-ceiling, scan-degraded, extraction-floor); see counts_floor above for why. An unknown\n"
        "                               shape refuses loudly with the whole vocabulary; SYM takes the shared selector grammar (name,\n"
        "                               file:name, canonical id), FILE is a path substring\n"
        "    --mentions=SYM             markdown docs (plans/designs) that name SYM in a `backtick` (doc↔code)\n"
        "    the pre-PR family — plumbing (--affected) to mid-task report (--situ) to gate (--test-gate):\n"
        "    --affected=F1,F2|SYM       test files that transitively reach the changed files -- or the changed SYMBOL. Each item may be\n"
        "                               `path`, `./path`, `path:LINE` / `path:N-M` (paste a --hotspots/--clones/--grep/--lint/\n"
        "                               --quality-delta row's locator verbatim; the trailing line locator is stripped, same for\n"
        "                               --situ/--test-gate), or a symbol: `NAME`, `file:NAME`, `path::scope::name`.\n"
        "                               FILE-FIRST: an item matching any indexed path is a PATH pattern (unchanged semantics --\n"
        "                               `--affected=widget` stays the ./src/widget.cpp pattern); only an item matching NO indexed\n"
        "                               path is offered to the symbol resolver, and `file:NAME` reaches the symbol reading\n"
        "                               explicitly. seeded_by=\"file|symbol|mixed\" + seeds=N report which reading fired and how\n"
        "                               many defs it seeded. An item matching NEITHER refuses (exit 1) naming both readings.\n"
        "                               script_gates_unmodelled= counts the script runners under test/, recursively (a path count; not\n"
        "                               every one invokes the binary) that this call's graph walk cannot see either way (script-to-binary is not\n"
        "                               a call edge) — a corpus-wide fact, not scoped to the changed set given\n"
        "    --exercises=TESTFILE       the INVERSE of --affected: the non-test symbols this test file transitively calls into --\n"
        "                               what it actually covers. The first question when a test fails and you have its name and\n"
        "                               nothing else. Ranked by PageRank, capped at 40 rows (raise with --limit; --offset pages).\n"
        "                               A NON-TEST path REFUSES rather than answering generically: this verb IS the test/non-test\n"
        "                               partition (it subtracts test code from the answer), which means nothing for a non-test\n"
        "                               file -- for \"what does this call\", use --callees=SYM or --graph-query callees(...)\n"
        "                               A shell harness carries harness=script: subprocess coverage is unmodelled, so reaches=0\n"
        "                               there is a stated limit, not a measurement (the inverse of script_gates_unmodelled).\n"
        "    --situ[=F1,F2]             situational awareness for a change: blast radius + tests + co-change (default = git diff)\n"
        "    --handoff                  continuation packet for the NEXT session: <verified> disk truth (branch/sha, changed files+symbols,\n"
        "                               blast radius, tests-to-run) + <heuristic> labeled suggestions (co-change partners, committed notes,\n"
        "                               plan/design doc pointers via a branch+commit-subject query). Empty diff is fine — the packet still\n"
        "                               carries branch/sha + heuristics. Composes with --token-budget=N (drops heuristic rows tail-first,\n"
        "                               disclosed as withheld= in the header; verified rows are never dropped). Single-root only.\n"
        "    --test-gate[=F1,F2]        agent self-check before a PR (pair with --quality-delta): names the tests to run + the UNTESTED blast radius;\n"
        "                               exit 4 if either obligation is non-empty (run the tests, then rely on green). (default = git diff)\n"
        "      run= on a test row        --affected/--situ/--test-gate/--exercises/--pr-context/--pack-task name harness FILES, not commands. A row carries\n"
        "                               run=\"<cmd>\" when a runner is DERIVABLE from real evidence: a test-dir .sh/.py whose basename stem\n"
        "                               matches the harness's, or whose TEXT names the harness file. Spelled with the same root you scanned,\n"
        "                               so it pastes straight into a shell. NO run= means NOT DERIVABLE -- never a guessed suite command\n"
        "    --grep=STR | --regex=PAT   literal / regex search + enclosing symbol + the matched line. SPAN-TIERED by default (see\n"
        "                               --grep-in below): the scan itself is exhaustive, the ANSWER serves one tier and discloses\n"
        "                               what it held back. --grep-in=any is the exhaustive VIEW -- every hit, no tiering.\n"
        "                               For task-ranked retrieval use --for=TASK (ranks by PageRank + task relevance).\n"
        "      --handles                add h= to each unique editable enclosing-symbol row: a stable identity plus the\n"
        "                               file-content hash pinned when grep ran. Ambiguous or document-only rows get no handle;\n"
        "                               a later edit must refuse after any file change rather than retarget stale coordinates.\n"
        "      --grep-context=N | --grep-before=N / --grep-after=N   ripgrep-style N lines of source around each hit\n"
        "      --and=STR (repeatable)   modifies --grep=STR: keep only hits where STR is ALSO present (literal-only, no --regex)\n"
        "      --not=STR (repeatable)   modifies --grep=STR: drop hits where STR IS present (literal-only, no --regex)\n"
        "      --grep-scope=line|file   modifies --and=/--not=: line (default) requires the SAME matched line; file requires\n"
        "                               anywhere in the same file. Second occurrence of --grep=/--regex= itself REFUSES\n"
        "                               (naming --and= as the AND spelling) rather than silently overwriting the pattern.\n"
        "      --grep-in=code|any       SPAN TIERS: which tree-sitter span a hit must sit in to print. code (default) serves the\n"
        "                               CODE tier when any hit is code, and otherwise comment AND string TOGETHER (tier=\n"
        "                               \"comment+string\"), disclosing what it held back (suppressed_comment=/suppressed_string=);\n"
        "                               a pattern living only in prose is still answered, never silently emptied. any turns\n"
        "                               tiering off entirely -- the exhaustive view. Hit files are parsed on\n"
        "                               demand under a fixed budget; tier_budget= says so when it stops, and hits it never\n"
        "                               classified are emitted, never suppressed.\n"
        "    --match=QUERY              tree-sitter structural (shape) query\n"
        "    --pattern=PAT              structural search written in CODE, not in node kinds: --pattern='foo($X, ...)'. $NAME binds one\n"
        "                               node (repeat it and both sites must match structurally); $_ binds nothing; ... (or $$$) is an\n"
        "                               ellipsis over siblings, matched by ONE first-match-wins probe under a hard cap -- both facts on\n"
        "                               the element. Comments are transparent, everything else is kind- and text-exact ($A + $B does not\n"
        "                               match a - b). Served: c cpp objc java csharp javascript typescript python go rust swift; ruby,\n"
        "                               bash and the data tiers are named in unsupported= instead of answered. A pattern no served\n"
        "                               grammar resolves, or that collapses to a bare token, is REFUSED -- never reported as hits=0.\n"
        "    --query=TERMS              raw BM25 ranking (debug); use --for\n\n"
        "  zoom the detail ladder\n"
        "    --detail=N                 (with --for) importance-weighted detail: FULL bodies for the top-N ranked symbols +\n"
        "                               signatures for the rest, in ONE call — spend body tokens only on the head the rank\n"
        "                               identifies. Composes with --max-tokens (bounds the bodies) and --adaptive. 0 = off.\n"
        "    --pack-signatures          body-elided decl skeletons — ~59-68%% fewer element bytes than the same symbols'\n"
        "                               full --expand bodies (68%% at the top-50 sigs payload cap — the sigs payload is\n"
        "                               top-50 whatever --top-k is set to, and --top-k's own default is 200),\n"
        "                               measured at top-10/50/100 on this repo with the corpus-root prefix subtracted\n"
        "                               from both sides: that prefix repeats inside every element, is charged in both\n"
        "                               forms, and is not what this elides — count it and the figure becomes a function\n"
        "                               of how deep your checkout sits (the same corpus reads 60%% from a relative root\n"
        "                               and 41%% from a 130-byte absolute one). The share RISES with the result size.\n"
        "                               Like the --format=columnar sibling, a small result can invert it — a signature\n"
        "                               plus its doc comment can be bigger than a short body.\n"
        "    --outline=A,B,...          control-flow skeletons of A,B,...  (same selector grammar as --expand, minus the range)\n"
        "    --expand=A,B,...           full bodies of A,B,...  Selector grammar per item (the tail after the LAST ':' decides;\n"
        "                               a tail STARTING WITH A DIGIT is a range, anything else is a name):\n"
        "                                 NAME                every def of that name  |  FILE:NAME           that file's def\n"
        "                                 NAME:START-END      body slice              |  FILE:NAME:START-END selector + slice\n"
        "                                 FILE:LINE:NAME      paste a row's p=\"path:line\" straight from --callers/--lint/--grep\n"
        "                                                     (NOT --hotspots: its p= is a BARE path — build FILE:LINE:NAME from its\n"
        "                                                      own p=/top_l=/top= instead, since top= is just the worst function's name)\n"
        "                                 path::scope::name   the canonical id= --for/--pack-task emit\n"
        "                               (START-END is 1-based within the def's OWN body — lines=\"lo-hi/total\" marks the slice\n"
        "                               partial; out-of-range clamps. FILE matches any path substring, like --callers/--lego.)\n"
        "                               EXACT-NAME DEFAULT (one token, one unambiguous match, no explicit --top-k): the ranked map\n"
        "                               defaults to top-k=0 — you already named the exact symbol, so the ~200-row orientation map is\n"
        "                               pure overhead in front of the one body it exists to summarize. Disclosed on the root as\n"
        "                               topk_default=\"0\" (self-describing: the change is visible without reading source). A MULTI-match\n"
        "                               name (an ambiguous bare name) or a multi-token --expand keeps the map — there IS something to\n"
        "                               disambiguate. An EXPLICIT --top-k=N (0 included) always overrides this default.\n"
        "                               Each body also carries sibs=\"a,b,...\" sibs_total=\"N\" [sibs_capped=\"1\"] (the file's OTHER\n"
        "                               symbols, names only, capped at 40) and inc=\"x.h,...\" inc_total=\"N\" [inc_capped=\"1\"] (the\n"
        "                               file's own #include/import targets, capped at 24) — both absent when the count is 0 (a\n"
        "                               documented zero, not a degrade), so a body no longer needs a second --outline call just to\n"
        "                               learn what else lives in its file.\n"
        "                               CHEAPEST-COMPLETE-ANSWER SERVING (no explicit --top-k, no range slice): the verb ALSO measures\n"
        "                               the (possibly map-less) bundle against the requested symbols' whole FILE(s) and emits the\n"
        "                               SMALLER, disclosed on the root as mode=\"bundle|whole-file\" reason=\"the two byte counts\" — on a\n"
        "                               small file the old bundle was 5.65x the file itself; on a big file the bundle saves ~26x. The\n"
        "                               whole-file form is <src p= sym=\"name:line,...\"> with the file CDATA-wrapped (redacted as usual)\n"
        "                               and every requested symbol's line anchor kept. An EXPLICIT --top-k=N (including 0) opts out of\n"
        "                               BOTH the exact-name default and mode= auto-selection and keeps the classic undecorated shape; a\n"
        "                               SYM:START-END slice opts out of mode= auto-selection only (serving the whole file would invert\n"
        "                               an explicit narrowing) but still gets the exact-name top-k=0 default when it applies.\n"
        "    --compress                 strip comments + collapse blank runs from --expand/--outline body output (~20-35%% token cut)\n"
        "    --pack-top-n=N             pack the N top symbols' bodies  [--pack-budget-bytes=B]\n"
        "    --no-redact                emit source/doc text VERBATIM, redacting nothing\n"
        "                               REDACTED by default (high-confidence credential SHAPES only, precision over recall):\n"
        "                               emitted symbol BODIES, doc/markdown bodies and doc-comment excerpts, the --outline\n"
        "                               skeleton, and SIGNATURES — a default argument carries whatever literal was written.\n"
        "                               NOT redacted, and a deliberate residual: --grep/--regex/--match hit lines and their\n"
        "                               --grep-context neighbours, and --note-add/--notes text. --grep is the exception on\n"
        "                               purpose — auditing a repo FOR secrets needs the hit you searched for shown verbatim.\n\n"
        "  assess quality / structure\n"
        "    --metrics                  annotate fan-in/out + complexity (descriptive; coupling is the validated signal, complexity is a size-correlated one).\n"
        "                               also surfaces amp= (--metrics/--for/--exemplar): amp = |direct callers| (symbol-level, the\n"
        "                               in-edge CSR) + |co-change partners of the symbol's FILE| (file-level, mined from git history) —\n"
        "                               a deliberate GRANULARITY MIX, not a graph-only count; degrades to callers-only (still valid) when\n"
        "                               git/history is unavailable. NOT the same quantity as --impact's reaches=: reaches= is the\n"
        "                               TRANSITIVE blast radius over the call graph alone (everything that reaches SYM, any hop count);\n"
        "                               amp= is DIRECT callers plus a historical co-edit signal the call graph cannot see at all — the\n"
        "                               two numbers on the same symbol routinely differ several-fold (one seen case: 4.6x apart) because\n"
        "                               they measure different things, not because one is wrong.\n"
        "                               ppalt=N (C-family/C#): the body contains N alternative preprocessor branches (#else/#elif) —\n"
        "                               code that never coexists at compile time. cx/ccx/nest/loc/locals are summed over ALL branches\n"
        "                               (deterministic, but an over-count vs any single build; ~2x seen on a real SSE/scalar pair), so\n"
        "                               discount them accordingly. ripwire never guesses which branch your build compiles — it discloses\n"
        "                               the count instead. A bare #if with no #else adds no alternative and no ppalt=. Absent when 0.\n"
        "                               ev=N essential complexity (McCabe: 1=fully structured, 2+=jumps block extract-method\n"
        "                               cleanly — the jump makes it a rewrite, not a mechanical lift); ev_why=tag:count names\n"
        "                               which jumps raised it (guard-return, loop-escape, ...). A FLOOR (ev_floor=1): noreturn\n"
        "                               calls/macro-hidden exits go unseen; absent on a cx row means exactly 1, and Rust ?/\n"
        "                               yield/await/defer are not counted, so Bash carries no ev at all.\n"
        "                               humps=/deep=/locals= are the nesting PROFILE nest= alone cannot give: nest= is a max,\n"
        "                               so one deep line and a body that is deep throughout report the same number. humps=\n"
        "                               counts regions reaching the nesting bar, deep= the lines inside them (a floor), and\n"
        "                               locals= the local-variable-declaration count (a floor, C/C++ only). Read the three\n"
        "                               together — a tangle (many humps, few deep lines each) and a long blocked-sequential\n"
        "                               body (one hump, many deep lines) have the same nest= but opposite refactors. Absent\n"
        "                               exactly when nest is below the bar (not-deep), never a hidden 0.\n"
        "    --deps                     file->file dependency graph (god-files, cycles — validated); its nccd (Lakos) is a\n"
        "                               design heuristic, not independently outcome-validated. instab= (Martin's I=Ce/(Ca+Ce))\n"
        "                               counts project includes ONLY -- system/third-party headers are excluded from Ce,\n"
        "                               matching stabledeps' gap= so gap == consumer's instab - provider's instab always.\n"
        "                               <health>'s ccd/acd/nccd/shape are computed over dep_files= (files whose language\n"
        "                               has #include/import syntax) not files= (the raw corpus, incl. .sh/.md/.json/etc,\n"
        "                               which can't participate in the graph) -- --arch's propagation_cost uses the same N\n"
        "    --hotspots                 complexity x recent git churn (maintenance pain); each row's top= is the worst function's\n"
        "                               BARE name, top_ccx= its cognitive complexity, top_l= its source line (build an --expand\n"
        "                               selector from p=/top_l=/top=, not from top= alone — it no longer carries a :line suffix)\n"
        "    --clones                   token-normalized duplicate bodies\n"
        "    --readability              per-function readability lens, LEAST readable first: vol= Halstead volume V (N*log2(eta)),\n"
        "                               ent= Shannon token entropy E, lines= L, posnett= sigmoid(8.87 - 0.033V + 0.40L - 1.5E)\n"
        "                               (Posnett/Hindle/Devanbu, MSR 2011). APPROXIMATION, disclosed: ONE token-class table serves\n"
        "                               every language (keywords + punctuation = operators, identifiers + literals = operands),\n"
        "                               with no per-grammar refinement, so V is cross-language and not a per-grammar Halstead count.\n"
        "                               The formula was fitted on snippets of 20 lines or fewer, so it is a RANKING lens, not a\n"
        "                               grade: read the ORDER of the rows, not the number on any one of them. Pages with limit=N\n"
        "                               (offset=M); default 40 rows. Declarations with no body are not measured.\n"
        "    --nonlocal-state           per function, the NON-LOCAL MUTABLE STATE it can reach, MOST WRITES FIRST: writes= reads= are the\n"
        "                               distinct cells this function OR its transitive callees write / read; direct_writes= direct_reads=\n"
        "                               are the subsets in its own body. A cell is a file/namespace-scope variable, a function-local static,\n"
        "                               or a Python module global; a const/constexpr/consteval declaration is not a cell. Each cell child\n"
        "                               names its declaration, its direction (dir=r|w|rw) and either the use site in this body (at=) or the\n"
        "                               callee it came through (via=).\n"
        "                               Lineage: Fowler's Global Data / Mutable Data smells (2018) name the hazard and ship no metric;\n"
        "                               Marinescu's ATFD (ICSM 2004) is the closest number but is one-hop, per-class, Java, and direction-blind;\n"
        "                               QMOOD DAM and MOOD AHF/MHF count DECLARED VISIBILITY and so score a class with private fields and\n"
        "                               leaked mutable internals as perfectly encapsulated; the only published measurement of externally\n"
        "                               reachable state (Potanin/Noble/Biddle 2004) is DYNAMIC, Java-only, and its tool is unmaintained.\n"
        "                               UNSOUND BY CONSTRUCTION -- it cannot see indirect calls, pointer aliasing, macro-named cells or\n"
        "                               reflection-like dispatch, and a local SHADOWING a cell name can be charged to the cell -- so every\n"
        "                               count is a FLOOR (counts_floor=\"1\") and the blind spots are listed in the report's own legend.\n"
        "                               COVERS C++, ObjC and Python -- the languages whose read/write USE SITES the index carries. Every\n"
        "                               other indexed language is named on the root as unanalyzed_langs= and contributes no cells and no\n"
        "                               rows: that absence is NOT a measured zero. Pages with limit=N (offset=M); default 40 rows.\n"
        "    --ensemble                 the FAMILY JOIN: per function, which of FOUR orthogonal evidence families fire, ranked by the COUNT of distinct families\n"
        "    --quality-panel[=PRESET]   THE SINGLE COMMAND: the whole quality panel in ONE ranked report. Per function, which of SIX evidence\n"
        "                               families fire -- structural (shape), lexical (identifier text), confusion (syntactic construct),\n"
        "                               historical (git churn), colocation (what you must read from outside this file), state (this function's\n"
        "                               OWN BODY touching non-local mutable state) -- ranked by the COUNT of distinct families, NEVER by a\n"
        "                               weighted composite, each row carrying its own evidence. PRESET selects and cuts, never weights:\n"
        "                               strict (the four families measured steady enough to gate on, 2 must agree) | default (all six, 2; the\n"
        "                               bare form) | lenient (all six, 1 -- a reading order, not a verdict). historical and colocation are out\n"
        "                               of strict: each is a fixed-size worst-40 cut over a ranking whose population moves, so both re-shuffle\n"
        "                               on code that did not change (docs/EVALS.md section 9.9). A family that could not be measured here is\n"
        "                               UNAVAILABLE, never 'did not fire', and of= drops with it. A lens: exit 0. Pages limit=N (offset=M).\n"
        "                               WHY NO COMPOSITE, in full (the emitted legend is deliberately terse and points here): averaging\n"
        "                               correlated metrics re-weights one signal and calls it six, and a single quotable number is wrong the\n"
        "                               moment it is quoted -- fam= is ORDINAL, and every row carries its own evidence so a reader can see WHY\n"
        "                               without a second command. The families are partitioned by KIND of evidence so that corroboration means\n"
        "                               the lenses failed DIFFERENTLY, not that one weakness echoed six times: the first four are the ensemble\n"
        "                               join, called through its own entry point and unchanged; colocation and state passed the same\n"
        "                               orthogonality test on the same corpora before being enabled. Every threshold is REUSED from the lens it\n"
        "                               came from, none is new: four absolute structural bars (cognitive complexity, lines, nesting, params),\n"
        "                               and three rankings with no defensible absolute cut, each firing for the worst decile of its OWN\n"
        "                               ranking (at least one row, at most that lens's default window of 40) -- an ordinal cut is RELATIVE,\n"
        "                               'worst in THIS corpus', never 'bad in absolute terms'. The state family fires on the presence of a\n"
        "                               direct access site and deliberately uses the OWN-BODY half of the lens, not the callee closure: the\n"
        "                               panel's unit is one function's own comprehensibility, and the closure is a fact about its callees.\n"
        "                               UNAVAILABLE is never silent: an empty unavailable= means every family was measured, an empty ranking\n"
        "                               or empty language coverage counts as NOT measured, and the coverage denominators behind each verdict\n"
        "                               are published so it can be checked instead of trusted. The join=deep+untested annotation puts two\n"
        "                               facts already in the report side by side (sustained depth, no reaching test) because that pair is\n"
        "                               where a refactor is most wanted and least safe; counting it would be one family wearing a second hat.\n"
        "    --context-ratio            the LOCAL-REASONING lens: to understand this symbol, how much must you know that is NOT in front\n"
        "                               of you? Per symbol (and rolled up per file) the distinct in-corpus definitions and files its\n"
        "                               reference sites resolve to, and the share of them defined OUTSIDE its own file — as an edge\n"
        "                               count (ent_ratio=) and, weighted by the tokens a reader must actually read, as read_ratio=.\n"
        "                               ATTRIBUTION: the fraction itself is published — it is Beck and Diehl's per-class congruence\n"
        "                               (FSE 2011) flipped, with Martin's instability Ce/(Ca+Ce) as its crude ancestor. What is\n"
        "                               refined here is the READER WEIGHTING and the use of EVERY reference role (call, read, write,\n"
        "                               import, base class, member type), not calls alone. Resolution is NAME-BASED and language-gated,\n"
        "                               the same heuristic level the uses verb works at; a name with several definitions contributes\n"
        "                               each of them up to defs_per_name_cap= and amb= counts it. Names with no in-corpus definition\n"
        "                               land in ext=, which locals and parameters DOMINATE, so ext= is not a dependency count and is\n"
        "                               excluded from both ratios. ents=/files= are FLOORS. Pages with limit=N (offset=M); default 40\n"
        "                               symbol rows and 40 file rows. An ORDERING, never a grade and never a threshold.\n"
        "    --naming-calibration       score the naming-* lint rules against this repo's OWN rename history: one git log pass mines\n"
        "                               old->new identifier substitutions, joins each to the symbol it became at HEAD, and scores\n"
        "                               BOTH spellings with the same predicates --lint runs. old=fires on the abandoned spelling,\n"
        "                               new=fires on the chosen one, proxy=old/(old+new), where 0.50 is exactly chance. A NOISY\n"
        "                               PROXY, stated as one -- rebrands, moves and API changes all look like renames -- so read\n"
        "                               pairs= (the sample size) first; the group rules report scope=group-rule, not a fake 0/0.\n"
        "                               Exit 0 always: the per-rule floor lives in test/namingcalibrationcheck.sh\n"
        "    --naming-consistency       TIER A convention normalization (section 9.2): the corpus's OWN case-convention vote per\n"
        "                               (language, kind) group among multi-token eligible names -- a single-token name, or one split\n"
        "                               only on digit boundaries, carries no case signal and is silently excluded. A group DECIDES\n"
        "                               only when its leading style (camel/pascal/snake/screaming) clears a 20-name sample floor AND\n"
        "                               a 90%% agreement floor; short of either it reports style=UNAVAILABLE with why= naming which\n"
        "                               bar it missed, never a guessed winner. Every off-convention name in a DECIDED group\n"
        "                               (including mixed -- naming-case's own finding, a separator AND a transition in one name,\n"
        "                               which never wins a vote) gets propose=: its OWN subtokens mechanically recombined into the\n"
        "                               dominant style -- no dictionary, no synonym judgment, which is what keeps this derivable\n"
        "                               from the corpus rather than invented. propose= is a SUGGESTION, never a safe-to-blind-apply\n"
        "                               rename -- an actual rename needs --uses to prove the complete reference set first. Exit 0\n"
        "                               always: a lens, not a gate. Pages limit=N (offset=M); default 40 rows\n"
        "    --naming-locals            OPT-IN --lint MODIFIER (requires --lint; a no-op alone), OFF by default:\n"
        "                               local-variable-indexing plan Phase 2 (PLAN.md 2026-08-06 evening). Runs the\n"
        "                               naming-short/naming-wordy/naming-underscore/naming-case predicates (same tags, same rule\n"
        "                               bodies as the existing Symbol-scoped checks) against LOCAL variable names too, C/C++ only,\n"
        "                               but ONLY inside a function that already clears an EXISTING\n"
        "                               size/complexity gate (loc>80 OR nest>4 OR ccx>=15 -- the shipped large-function/deep-nesting\n"
        "                               thresholds) AND has locals>=8 (measured floor: median locals=9 among this repo's own 377\n"
        "                               gated functions) -- never a whole-corpus local-name sweep. naming-short additionally requires\n"
        "                               the local's own declDepth>=2 (nested, not the function's own outermost block). Deliberately\n"
        "                               breaks the lens's stated invariant that an un-indexed local can never be flagged -- read the\n"
        "                               WITHDRAWN note atop src/naminglens.h before relying on this. NOT default-enabled inside a\n"
        "                               plain --lint run and not a candidate for it yet: the plan's own hard blocker (a hand-curated\n"
        "                               fixture corpus AND a manual real-corpus audit for idiomatic-short-name skew -- i/j/k/buf/tmp/\n"
        "                               err) has not run. Exit 0 always; findings ride the same naming-* tallies/floors as --lint\n"
        "    --comment-coherence        per function/method WITH A DOC COMMENT, two published content measures, MOST NAME-RESTATING\n"
        "                               FIRST: c_coeff (Steidl/Hummel/Juergens, ICPC 2013) is the fraction of the comment's words within\n"
        "                               Levenshtein distance <2 of a word in the symbol's own (split) name — HIGH c_coeff IS BAD, it\n"
        "                               means the comment mostly repeats the name and adds no information (the opposite of the naive\n"
        "                               'high coherence sounds good' reading). cic (Scalabrino, ICPC 2016 / JSEP 2018) is the Jaccard\n"
        "                               overlap of two preprocessed term sets: the comment's vocabulary vs every identifier the\n"
        "                               definition's own span uses (operators/keywords stripped, camelCase/snake_case split, English\n"
        "                               stopwords dropped, deduplicated). The two measure different things and are expected to\n"
        "                               disagree — both are reported, never collapsed to one number. UNAVAILABLE (not scored, never a\n"
        "                               zero) where no doc comment exists, counted in no_comment= on the root. Complements --doc-drift\n"
        "                               (which checks whether a markdown CLAIM is stale) with comment CONTENT, over a disjoint input —\n"
        "                               neither verb duplicates the other. Pages with limit=N (offset=M); default 40 rows.\n"
        "    --cochange[=FILE]          files that change together in git (hidden coupling; the rows' own legend defines surprising=)\n"
        "    --cochange-recur=K         (with --cochange) report only pairs whose co-change RECURS in K or more of the mined\n"
        "                               window's sub-windows, so a one-off refactor sprint stops reading like an eighteen-month\n"
        "                               structural defect (Clio, ICSE 2011). Every row carries recur= with or without this flag;\n"
        "                               the header publishes sub_windows= (the denominator) and min_recur= when the filter is on\n"
        "    --cochange-groups          (with --cochange, repo-wide only) emit Modularity Violation GROUPS instead of pairs:\n"
        "                               \"X co-changes with {A,B,C}, none of which it depends on\" is ONE row that names the file\n"
        "                               to fix (Mo/Cai/Kazman, IEEE TSE 2019). A greedy cover, disclosed as greedy — set cover is\n"
        "                               NP-hard, so the group count is an upper bound on the minimum, not the minimum\n"
        "    --since=REV|DATE           scope --hotspots/--cochange/--rank-by=churn|churn-decay to commits after this point:\n"
        "                               a revision (HEAD~20, a tag/sha — deterministic) or a git approxidate\n"
        "                               (\"2 weeks ago\" — wall-clock-relative). e.g. --hotspots --since=\"1 week ago\"\n"
        "                               ranks by RECENT churn (the regression lens). Absent ⇒ each verb's OWN\n"
        // §B11.5 (CA4): this clause said "all-history default", which is false on all three verbs — every one
        // of them mines a BOUNDED default window, and two of them stamp it in their own output. Stating a
        // default the tool does not have is worse than stating none: a reader concludes an unstamped run
        // covered the whole history. The 12-vs-18 split itself is a RECORDED residual and is not re-litigated
        // here; what is fixed is that --help now names the real numbers and says which verbs publish them.
        "                               bounded default window, NOT all history: --hotspots 12 months,\n"
        "                               --rank-by=churn 18 months, --cochange 18 months (--rank-by=churn-decay is\n"
        "                               the ONE exception: its default IS all history, because the 90-day half-life\n"
        "                               makes a cut-off unnecessary — it stamps that too). All of them STAMP the\n"
        "                               window they used (window=\"12mo\"/\"18mo\", or the resolved --since\n"
        "                               value) — --cochange gained its window= in the same round that gave it\n"
        "                               sub_windows=, and this clause used to say it had none. An UNRESOLVABLE value is\n"
        "                               refused by --hotspots (exit 1 — its window is part of the measurement)\n"
        "                               and degrades to the verb's own default window elsewhere\n"
        "    --arch=FILE                enforce layering rules (exit 2 on violation); the Martin Ca/Ce/I/A/D block it emits is a\n"
        "                               design heuristic, not independently outcome-validated (never gates).\n"
        "                               propagation_cost's N is dependency-capable files only, same denominator as --deps <health>.\n"
        "                               Layer substrings and regex path-rules match the ROOT-RELATIVE path (src/core/x.cpp), not the\n"
        "                               spelling you passed, so a rules file means the same thing in every checkout\n"
        "    --arch=FILE --baseline     write .ripwire_arch_baseline (accept current debt as baseline), exit 0\n"
        "    --arch=FILE --baseline-update  merge current violations into baseline (accept new debt), exit 0\n"
        "    --lint                     built-in AST checks (c-cast, goto, unsafe-c-fn, naming-*, cache-* data-layout, ...). naming-uninformative\n"
        "                               is ONE-SIDED by design: it fires only when a name's subtokens are ALL corpus-common\n"
        "                               (BM25 idf over the identifier-name corpus) AND its body clears a size floor — a\n"
        "                               high-idf (distinctive) name is never penalised, unlike the withdrawn name<->body rule.\n"
        "                               Each <rule> row's applicability is per-LANGUAGE, not per-file-content: a rule whose\n"
        "                               registered languages (see --lint-catalog) intersect NONE of the corpus' languages carries\n"
        "                               applicable=\"0\" (its count=\"0\" is then structural inertness, not a measurement), and the\n"
        "                               root tallies inert_rules=\"N\"; see --lint-catalog for the full registry\n"
        "    --lint-catalog             the built-in rule registry: one row per rule with sev=/category=/rationale/lang=/since= — no\n"
        "                               corpus needed. Every built-in rule from every pack (base checks, atoms-*, cache-*, naming-*, the\n"
        "                               symbol-level checks) has exactly one row; lang= is the SAME token spelling --lint-rules'\n"
        "                               language: field accepts, so it round-trips into a user rule\n"
        "    --lint-rules=DIR           load user lint rules (YAML, ast-grep style) from DIR — runs with, or instead of, --lint\n"
        "    --lint-select=PREFIX[,...] (with --lint / --lint-rules) run ONLY rules whose name starts with one of these PREFIXes (or\n"
        "                               '*' for all) — comma-separated, e.g. cache- selects the whole cache-* family. The root then\n"
        "                               carries selected=\"K of N\" plus the raw select=/ignore= you passed, so a filtered zero is never\n"
        "                               confusable with an unfiltered one. An unresolvable PREFIX (matches no rule) refuses (exit 1),\n"
        "                               naming the nearest rule/family by edit distance\n"
        "    --lint-ignore=PREFIX[,...] (with --lint / --lint-rules) DROP rules whose name starts with one of these PREFIXes (or '*' to\n"
        "                               drop everything, e.g. paired with --lint-select elsewhere to isolate one family) — applied AFTER\n"
        "                               --lint-select narrows the set; same unresolvable-PREFIX refusal and root disclosure as --lint-select\n"
        "    --sarif                    (with --lint / --lint-rules) the SAME findings as SARIF 2.1.0 instead of the native XML\n"
        "                               <lint> block — the shape github/codeql-action/upload-sarif consumes for code scanning.\n"
        "                               Pure re-serialization (zero new analysis); results count == the native run's findings\n"
        "                               count. Levels: user severity error/warn/info -> SARIF error/warning/note; a built-in\n"
        "                               finding (a fact, never a gate) has no severity of its own and also maps to note. Fields\n"
        "                               with no SARIF home (per-rule capped= floor, enclosing symbol, raw sev=) ride in\n"
        "                               properties rather than being dropped; URIs are relative to the scanned root. Always the\n"
        "                               FULL result set — refuses loudly alongside limit=/offset= paging, --match and --with-profile\n"
        "    --with-profile=FILE        (with --lint) join MEASURED heat onto findings: FILE is a RIPWIRE_PROFILE build's report\n"
        "                               (its #PROF_TSV block); a finding whose enclosing symbol contains a PROFILE_SCOPE site\n"
        "                               gains heat_* attributes (scope, calls, total_ms, and whichever counter columns the\n"
        "                               profiled run armed — l1d_mpki etc.). Static shape x measured weight; joins nothing\n"
        "                               silently — a missing file or a FILE with no #PROF_TSV block refuses loudly\n"
        "    --communities              cluster the call graph into cohesive modules (each row's id= drills down below; drill= names the verb)\n"
        "    --community=ID             ONE module from that partition: its FULL ranked member list (40 rows by default, raise with\n"
        "                               --limit, page with --offset) plus its bridge edges to every other module it touches. ID is an\n"
        "                               id= from --communities/--zoom; ids live in 0..partition-1 (the child's partition= — the full\n"
        "                               label space, isolated singletons included), so a single-member module is a legal drill-down\n"
        "                               and reports size=\"1\". modules= counts the non-isolated communities (same number as the\n"
        "                               parent's modules=). An id outside 0..partition-1 REFUSES, naming the valid range and the\n"
        "                               nearest legal id -- a bad id is a typo, not an empty module\n"
        "    --zoom[=depth]             NESTED module hierarchy (multi-level Louvain) + cross-module bridges; --zoom --mermaid = nested diagram\n"
        "    --report                   architecture summary (modules, god-files, cycles) as markdown\n"
        "    --seams                    cross-module call seams no test reaches (untested integration seams)\n"
        "    --mermaid                  module (directory) dependency graph as a Mermaid diagram (paste/render)\n"
        "    --owners[=SYM]             bus-factor: recency-weighted author ownership per file; bf=1 = one person holds >80%%\n"
        "                               of weighted commits. Files with authors=1 (deterministically bf=1 share=1.00) fold into ONE\n"
        "                               <uniform files=\"N\"/> summary row instead of N identical rows; --detail=N restores the full listing\n"
        "    --dead-code[=DIR]          high-confidence internal source functions with no caller in the indexed tree; =DIR scopes to whole path components (dir or filename) and REFUSES a filter that names nothing indexed.\n"
        "                               A LEADING ./ anchors DIR at the repo ROOT (=./src matches only the top-level src/ subtree); a bare name (=src) matches that\n"
        "                               component ANYWHERE in the tree, including nested (test/fixture/src/…)\n"
        "    --quality-baseline         snapshot ccx/clones/dead-code to .ripwire_quality_baseline (run BEFORE a change)\n"
        "    --quality-delta            agent self-check before a PR (pair with --test-gate): report ONLY what a change made worse vs the baseline (10 kinds: complexity/verbosity/nesting/params/dup/dead/api-surface + error-masking/short-horizon-churn/reuse-decline);\n"
        "                               every finding is classified by ORIGIN: a symbol that EXISTED at the baseline and got worse (preexisting-worse=\"N\", no attribute on the row) vs one that exists only\n"
        "                               because the code is NEW (new-symbol=\"N\", origin=\"new-symbol\" on the row). A small numeric delta is additionally sev=\"minor\". EXIT 2 ONLY on preexisting-worse AND\n"
        "                               major AND unacked — the gating=\"N\" header count. New-symbol rows are still PRINTED (they are the debt you are adding — read them), they just never gate; exit 0 means\n"
        "                               \"nothing that already existed got worse\", not \"clean\". Clone kinds classify by member set (new-symbol only if EVERY member is new); short-horizon-churn is preexisting\n"
        "                               by construction. LIMIT: origin is canonId (path::scope::name) identity, so a RENAMED/MOVED symbol reads as new and a regression carried in with the move will not gate.\n"
        "                               Test-fixture dirs + doc sections are exempt from dead-code/churn; churn needs COMMITTED thrash evidence (rewritten across recent commits AND again by this diff), never the current edit alone\n"
        // §B7.2 (CA4): the strict-sha staleness rule and — the part that matters — the fact that this verb
        // can DELETE a file in the user's tree were disclosed nowhere a user reads before running it. The
        // only pre-hoc statement of the deletion was a source comment. A side effect on the user's working
        // tree belongs in --help; the baseline= marker is a post-hoc receipt, not a disclosure.
        "                               WHICH FLOOR IT COMPARES AGAINST, and a side effect: the sidecar is honored only when the sha it was pinned at EQUALS the current git HEAD (strict\n"
        "                               equality — an ancestor commit describes a DIFFERENT tree, so everything committed since would read as your regression). A sidecar pinned anywhere\n"
        "                               else is STALE: this verb then DELETES it from your working tree (self-heal, so the next run does not rediscover the dead pin) and auto-compares the\n"
        "                               working tree vs git HEAD instead. Re-pin with --quality-baseline. The read-only MCP quality_delta verb applies the SAME staleness test but never\n"
        "                               deletes. Which floor was actually used is on every report as baseline=: sidecar | git-HEAD | git-HEAD (stale sidecar removed) | git-HEAD (stale\n"
        "                               sidecar ignored) — the last two say a stale sidecar existed, and 'removed' means the file is gone. A non-git root has no HEAD to fall back to, so\n"
        "                               its sidecar is always honored; without one there, the verb exits 1.\n"
        // R-I: the WAVE-level form. Its own row rather than a bracket on the one above, because the floor it
        // compares against is a different KIND of thing (a commit, not a sidecar or the working tree) and the
        // row above spends eight lines on sidecar staleness that this form never touches.
        "    --quality-delta=REV|A..B   the same 10-kind report between two COMMITTED TREES instead of the working tree vs a baseline — the WAVE-level measurement (=A..B = tree B against tree A;\n"
        "                               =REV = that commit against its FIRST PARENT; an EMPTY side of the range means HEAD). Same grammar --dmm= takes, and A...B is REFUSED rather than read as A..B.\n"
        "                               Use it to measure a whole integration branch at once (--quality-delta=<merge-base>..<head>): per-lane checks each compare against their own baseline and cannot\n"
        "                               see a regression the WAVE introduced. Identical output contract to the bare form — same kinds, gating=\"N\", exit 2, and the same .ripwire_quality_acks ratchet\n"
        "                               (acks are keyed root-relative, so a ledger recorded from working-tree runs applies unchanged). base_ref= and target_ref= disclose the two RESOLVED shas.\n"
        "                               No sidecar is read, written or deleted by this form, and at= is omitted: the two refs ARE the anchor. A==B is a legal, empty, exit-0 comparison.\n"
        "                               ONE KIND CANNOT BE MEASURED HERE and says so as churn=\"unavailable\": short-horizon-churn needs git history at the tree being judged, and both trees are\n"
        "                               materialized OUT of the repo into temp dirs. The other 9 kinds are computed exactly as the bare form computes them.\n"
        "    --dmm[=REV|A..B]           the DELTA MAINTAINABILITY MODEL scalar: ONE comparable number in [0,1] for a change, so quality becomes TRENDABLE across commits instead of a per-kind list (di Biase, Rastogi, Bruntink and van Deursen, TechDebt 2019; thresholds and arithmetic from PyDriller's deltamaintainability reference implementation). Bare = the WORKING TREE vs git HEAD (what --quality-delta compares); =REV = that commit vs its FIRST PARENT (the per-commit scalar); =A..B = tree B vs tree A.\n"
        "                               A UNIT is a function/method definition with a body; its VOLUME is its line span. Per property a unit is LOW risk iff size: loc<=15, complexity: cyclomatic<=5, interfacing: params<=2. good = low-risk volume ADDED plus high-risk volume REMOVED; bad = low-risk REMOVED plus high-risk ADDED; dmm = good/(good+bad). So DELETING a god function scores 1.000 and GROWING one scores 0.000.\n"
        "                               The three sub-scores (size/complexity/interfacing) are emitted alongside the combined one because they are separately actionable; the combined one POOLS them (summed good over summed good+bad) and is labelled combine=\"pooled\", since the paper publishes the three separately and no aggregate.\n"
        "                               IT IS A DELTA, NEVER A LEVEL: a unit you edit without changing its size, complexity or parameter count sits in the same bin with the same volume on both sides and contributes NOTHING. Touching bad code is not punished, deliberately, because a gate that punishes it is a gate people route around.\n"
        "                               dmm=\"UNAVAILABLE\" means good+bad was 0 (a rename, a literal edit, a comment reflow): the change is outside what the model measures. That is NEVER to be read as 1.000 or 0.000, and reason= says which case it was. Same token per property.\n"
        "                               VOLUME IS PHYSICAL LINE SPAN (size_metric=\"physical-loc\"), where the reference implementation uses non-comment non-blank lines, so a heavily commented unit crosses the size threshold here earlier. NO THRESHOLD, NO VERDICT, ALWAYS EXIT 0.\n"
        "    --quality-ack[=REASON]     accept the current findings into .ripwire_quality_acks (per-finding ratchet): re-runs suppress them honestly (acked=\"N\") until one WORSENS past its acked size\n"
        "      --ack-only=SUBSTR[,SUBSTR] (with --quality-ack) ack only SOME findings — those whose KIND, canonical id, or\n"
        "                               FACET contains one of these; the pseudo-token 'gating' selects exactly what would\n"
        "                               exit 2. Bare --quality-ack accepts the WHOLE report, so accepting one deliberate\n"
        "                               change silently accepts the rest — how a ratchet turns into a rubber stamp. Prefer\n"
        "                               the facet: --ack-only=contract-change acks the deliberate arity changes WITHOUT the\n"
        "                               never-gating api-surface new-symbol rows. Matching nothing refuses (exit 1) rather\n"
        "                               than falling back to acking everything. Whatever you leave unacked stays visible.\n"
        "    --edit-check=SYM           fast per-symbol post-edit contract check: SYM's param count + publicness NOW vs git HEAD\n"
        "                               (unchanged/new-symbol/contract-change with was/now), plus its 1-hop callers with any call-site\n"
        "                               provably incompatible with the NEW arity flagged. A contract is PER DEFINITION, so a SYM\n"
        "                               matching several definition sites REFUSES (exit 1) and lists the file:name spellings that\n"
        "                               pick one — unlike --callers/--uses, this verb may not union overloads and disclose defs=.\n"
        "    --replace-symbol-body=TARGET  atomically replace one uniquely-resolved definition with exact bytes from --edit-payload=FILE|-\n"
        "    --insert-before-symbol=TARGET atomically insert the payload immediately before one uniquely-resolved definition\n"
        "    --insert-after-symbol=TARGET  atomically insert the payload immediately after one uniquely-resolved definition\n"
        "                               TARGET is a symbol name, or a freshness-pinned sym# handle emitted by --grep --handles.\n"
        "      --edit-payload=FILE|-    required exact byte payload ('-' reads stdin); empty payloads refuse, never imply deletion\n"
        "      --edit-target-file=PATH  optional file-path substring to disambiguate a same-named definition. These three CLI verbs\n"
        "                               reuse the MCP edit engine: freshness hash, lock, pre-rename recheck, fsync, mode preservation\n"
        "                               and atomic rename. Every refusal leaves the target byte-identical. Success prints a JSON\n"
        "                               receipt; follow with --edit-check=SYM and --affected=FILE. Single-root only.\n"
        "    --safe-delete=SYM          \"can I delete this?\" — ONE call composing signals the tool already computes for one\n"
        "                               already-resolved SYM: 1-hop callers=, the transitive --impact blast radius (impact_reaches=),\n"
        "                               every --uses read/write/import/call/extends site (uses=), how much of the blast radius the\n"
        "                               tested= lens covers (tested_self=/radius_tested=/radius_untested=), and --dead-code's own\n"
        "                               high-confidence shape at defs=1 (dead_code_candidate=). ambiguous_callers= names callers\n"
        "                               whose own calls include an ambiguously-resolved one (g.ambOut) — a caveat, not a count of\n"
        "                               proven-wrong edges. FACTS only: risk= names what was found — none-found (zero callers AND\n"
        "                               zero uses), untested-radius (a radius exists and none of it is test-covered), or\n"
        "                               uses-exist (a radius exists and some of it is tested) — never a go/no-go verdict.\n"
        "    --pr-context[=BASEREF]     no-LLM review-evidence bundle for the diff (working-tree, or vs BASEREF): per changed file,\n"
        "                               its symbols + callers + blast radius + affected tests + co-change partners + owners.\n"
        "                               With --max-tokens=N the bundle degrades to fit: per-file structural counts survive for\n"
        "                               ALL changed files, the deep detail (caller/co-change lists, per-symbol rows) trims\n"
        "                               deepest-first, and truncated= names what was dropped (est_tokens= reports the fit).\n"
        "                               ANCHORING: the BASEREF form diffs against merge-base(BASEREF,HEAD), never BASEREF's tip —\n"
        "                               \"what did THIS work change since it forked\", not \"how do the two trees differ today\".\n"
        "                               base_moved= counts the paths BASEREF moved since the fork that this work never touched\n"
        "                               (excluded, not silently); anchor=\"ref-tip-two-dot\" = no merge-base (unrelated history).\n"
        "                               direction= always names the SIDE you are reading, and a no-ref-work row fires when\n"
        "                               BASEREF's tip IS the merge base -- it carries no divergent work, so every row is HEAD's.\n"
        "    --merge-scout=REF[,REF...] read-only cross-branch overlap: for each REF, the symbols it changed vs its merge-base\n"
        "                               with HEAD (git-archive TEMP copies — never checked out, never mutates a ref); the dirty\n"
        "                               working tree joins as an implicit extra arm. Pairwise: a changed symbol on TWO arms is a\n"
        "                               same-symbol conflict, two arms touching different symbols in the same file is a textual\n"
        "                               risk; <landing order=...> is the fewest-conflicts-first greedy land order (ties: ref name\n"
        "                               asc). An unresolvable REF refuses loudly (exit 1, names the ref) before any archive work.\n"
        "                               ANCHORING: every arm is diffed against its OWN merge-base with HEAD, never against live\n"
        "                               HEAD — a file an arm never opened can never show up because the live line moved.\n"
        "                               head_conflicts= is what that anchor hides, kept as its own row class: symbols this arm\n"
        "                               changed that the LIVE LINE also changed since the arm forked (HEAD is not an arm, so no\n"
        "                               pairwise comparison can see it). Single-root only.\n"
        );
    printPlanLanesUsage( out );
    std::fprintf( out,
        "    --stray-content[=SUBSTR]   \"where does this content live?\" across ALL branches — the question `git cherry` cannot\n"
        "                               answer. Per local ref (SUBSTR filters ref names): the lines its own divergent work\n"
        "                               AUTHORED vs its merge-base with HEAD that the live line does NOT have, and a verdict.\n"
        "                               v=\"unmerged\" = genuinely absent; v=\"superseded\" = the live line removed the SAME base\n"
        "                               code this ref removed, i.e. it re-implemented the work (git cherry still calls that\n"
        "                               commit unmerged, forever); v=\"merged\" refs are omitted. Every row shows its raw\n"
        "                               del=/redone=/sim= evidence, so a verdict is auditable, not a black box.\n"
        "                               v=\"unknown\" (ok=\"0\") = the ref has NO merge-base with HEAD, so it could not be analysed\n"
        "                               at all — a shallow clone (the actions/checkout DEFAULT) puts every ref here. It is NOT a\n"
        "                               claim the work is merged: it is the absence of an answer, counted in its own unknown=\n"
        "                               bucket so unmerged+superseded+merged+unknown always reconciles with refs=, and surfaced\n"
        "                               by --plan as an <undetermined> row rather than silently dropped.\n"
        "                               LIMITS: line-granular, not semantic — a rewrite that shares no deleted base line reads\n"
        "                               as unmerged; binary/oversized blobs are reported diffable=\"0\" with no counts.\n"
        "                               Read-only (cat-file/diff/ls-tree); single-root only.\n"
        "    --plan                     (with --stray-content) \"of all my branches, which still hold REAL work, and in what\n"
        "                               order should I land them?\" Selects the refs --stray-content calls v=\"unmerged\", DROPS\n"
        "                               the v=\"superseded\" ones (landing them would re-do work the live line already did —\n"
        "                               the exact waste --stray-content exists to catch), and feeds the survivors to\n"
        "                               --merge-scout's existing pairwise-conflict + fewest-conflicts-first landing-order\n"
        "                               machinery — composition only, neither verb's logic is reimplemented. <ref scouted=\"0\">\n"
        "                               is unmerged work NOT fed to merge-scout THIS run (a cost bound, not a verdict);\n"
        "                               <excluded> names the superseded drops and why. COST: --stray-content is a cheap per-\n"
        "                               blob sweep, but --merge-scout is per-ARM (git-archive + full ingest of each ref's tree)\n"
        "                               — measured 27s for 9 unmerged refs on a 35-branch real C++ repo (~3s/ref). kMaxPlanScout\n"
        "                               (12) bounds it to the top-N unmerged refs BY STRAY SIZE; --detail lifts the bound to\n"
        "                               scout everything. This is an EXPLICIT opt-in \"before you land\" call, not a per-\n"
        "                               question one — the default map's ~0.10s path is untouched. Read-only; single-root only.\n"
        "    --abi                      (with --stray-content) the CROSS-BRANCH ABI-BREAK gate `--layout` and `--stray-content`\n"
        "                               each miss alone: a branch that adds one field to a dual-compile uniform struct merges\n"
        "                               textually clean and reads as a harmless \"+1 field\" to a line-granular diff. SCOPE is\n"
        "                               what each ref AUTHORED — the paths `git diff base..tip` reports against its own MERGE\n"
        "                               BASE, never `diff HEAD..tip`. A file the branch never opened cannot be a break the\n"
        "                               branch introduced, and on a long-lived shared tree that one distinction is nearly all\n"
        "                               the noise: measured on a 35-branch C++ repo, 487 drift rows fell to 4 (the rest were\n"
        "                               the live line's own evolution reflected back at the reader). For each\n"
        "                               authored path this runs --layout's OWN field-offset arithmetic lexically on that ref's\n"
        "                               git blob (never indexed) and compares it against HEAD's computed fields.\n"
        "                               LISTED by default: kind=\"drift\" (the byte contract differs — the only kind that exits\n"
        "                               2), kind=\"unknown\" (a ref-side copy this module could not model; its caveats ride along\n"
        "                               in ref_caveat and it is NEVER reported as unchanged), kind=\"absent\" (the ref does not\n"
        "                               define the struct at that path at all).\n"
        "                               EXCLUDED by default, each on its own header counter — add --detail=N to print them:\n"
        "                               kind=\"rename\" (identical slots and field TYPES under different field NAMES: every byte\n"
        "                               stayed where it was, so it is a source change, not a byte-contract one — note a\n"
        "                               same-type field REORDER is lexically indistinguishable from a rename and lands here\n"
        "                               too), kind=\"spelling\"/\"stub\" (--layout's own harmless cases), and kind=\"head-moved\"\n"
        "                               (the ref's copy equals its own merge-base copy, so the LIVE LINE changed, not the\n"
        "                               branch). head_only= counts candidate sites on paths only the live line touched;\n"
        "                               unmodelable= counts sites skipped because HEAD's own copy carries no baseline; rows=/\n"
        "                               shown=/dropped=/excluded= reconcile the body against the sweep (capped=\"0|1\" is the\n"
        "                               tool-wide truncation BIT; dropped= is the count). Nothing is dropped\n"
        "                               without a number. Structs that match are omitted (report only differences); a ref with\n"
        "                               no rows at all counts into quiet=, a ref whose every row is an excluded kind counts into\n"
        "                               excluded_refs= (and prints under --detail=N), and broken_refs= counts REFS (not rows).\n"
        "                               Rows are ranked by SIZE DELTA so the biggest contract break leads, capped at 12 per ref\n"
        "                               with an explicit <more structs=\"N\"/>; --detail=N lifts the cap.\n"
        "                               LIMITS: HEAD's own side is the WORKING TREE's --layout answer, not a re-fetched git blob\n"
        "                               at HEAD's commit (the same scope --layout itself claims); a nested field's OWN type\n"
        "                               resolves through HEAD's copy even when the ref also changed it; the ref-side locator is\n"
        "                               index-free and file-scope (one namespace deep) only, so a struct nested in a class or an\n"
        "                               extern \"C\" block reads absent rather than compared; a HEAD-side struct --layout itself\n"
        "                               cannot model at all (pragma pack, bitfields, ...) has no baseline and is counted in\n"
        "                               unmodelable=, not compared; the authorship anchor is per PATH, so a branch changing\n"
        "                               struct S in one file while the live line changes S's mirror in another is a merge hazard\n"
        "                               only `--layout=S` on the merged result can see. Read-only; single-root only.\n"
        "    --whereis=SYM              which REF's tree defines or mentions SYM — HEAD first, then every local branch, with\n"
        "                               on-head=\"0\" naming the case the verb exists for: content that lives only on a branch.\n"
        "                               Each distinct blob is read ONCE (content-addressed), so N branches cost ~one tree.\n"
        "                               kind=\"def\" on a HEAD row is the PARSED index's answer (head_labels=\"index\"); on a REF row it\n"
        "                               is a LEXICAL heuristic — ref blobs are raw text, never ingested, so a doc quoting a signature\n"
        "                               still reads as a definition. head_labels=\"lexical\" ⇒ HEAD fell back to that heuristic too (no\n"
        "                               indexed def of the name, or a working tree that drifted from HEAD). refs_scanned= is the SCAN\n"
        "                               denominator (refs read besides HEAD), not a matched count. Read-only; single-root only.\n"
        "                               LIMITS: a TREE scan finds only what some ref STILL carries, so hits=\"0\" alone cannot\n"
        "                               tell a name this repo never had from one it deleted, and content dropped by every tree\n"
        "                               is invisible. Add --with-history: a <fate> row then says v=\"never\" or v=\"removed\"\n"
        "                               with the commit, date and file that removed it. Remote-tracking refs are excluded\n"
        "                               (they mirror local ones); refs are capped, narrow with --stray-content=SUBSTR.\n"
        "    --flags[=SUBSTR]           the dark-content dashboard: what is BUILT but OFF in this repo. Harvests all three gate\n"
        "                               patterns — #ifndef/#define header gates, CMake option(), and getenv() reads — and reports\n"
        "                               gate, kind (compile/cmake/env), default, the size of the code it guards (#if regions and\n"
        "                               their LOC), and its read sites. When a name is BOTH a header gate and a CMake option the\n"
        "                               CMake default WINS (that is what the build actually passes) and both sites are listed.\n"
        "                               A gate whose default IS another gate's name (#define F_WALLS F_ALL) is resolved: it\n"
        "                               inherits the master's default and rolls its guarded size up, so a master switch shows\n"
        "                               <aliases n=..> rather than a misleading loc=\"0\".\n"
        "                               LIMITS: lexical, not preprocessed — a gate computed at configure time or set only in a\n"
        "                               CI script shows its in-repo default, never the value your build used. A gate needs a\n"
        "                               VALUE (#ifndef F / #define F 0) to be a gate: valueless pairs are include guards and\n"
        "                               are excluded, and a gate read as a VALUE (constexpr bool k = F != 0, then if constexpr)\n"
        "                               reports regions=\"0\" honestly — its code is a C++ branch, not an #if region.\n"
        "                               Pair it with --flip=NAME below to size ONE gate instead of listing them all.\n"
        "    --flip=NAME                (with --flags) the BLAST RADIUS of turning ONE gate ON: which code becomes live, how\n"
        "                               much, which SYMBOLS hold it, what those transitively reach, and which TESTS cover it —\n"
        "                               the actionable sequel to --flags' list. Reports #if regions AND the C++ branch sites a\n"
        "                               value-style gate governs (constexpr bool k = F != 0, then if constexpr( k )): the\n"
        "                               binding is followed, so the family --flags honestly sizes at regions=\"0\" gets a real\n"
        "                               radius here. Alias chains run BOTH ways — flipping a MASTER rolls up every child that\n"
        "                               #defines to it (<member> rows), flipping a CHILD lights only that child and names the\n"
        "                               <parent> plus the siblings its flip would add. kind=cmake means the switch becomes a\n"
        "                               -DNAME=1 compile definition, so the C++ radius is identical, but it ALSO steers the\n"
        "                               build graph (an if(NAME) target_sources can add whole files) — those CMake sites are\n"
        "                               listed as <c> rows and deliberately NOT followed. kind=env is RUNTIME (runtime=\"1\"):\n"
        "                               there is no delimited region, so the hosts are the symbols that consult the variable\n"
        "                               and every row is conditional at its read. --detail lifts the per-list row caps.\n"
        "                               LIMITS: lexical and single-line, never preprocessed. A binding split across two lines is\n"
        "                               missed, and block comments are only skipped line-by-line. The value lane reads C-family\n"
        "                               source only and treats a file that declares its OWN constant of the same name as\n"
        "                               shadowing the gate's (C++ scoping) — but a third header's same-named constant, included\n"
        "                               rather than redeclared, would still be counted. A lit site inside no indexed def (a\n"
        "                               guarded member field, a file-scope constexpr, a test-macro body) counts into filescope=\n"
        "                               instead of a host. Single-root only (the harvest reads on-disk paths, which a merged\n"
        "                               workspace relabels) — run it per root. Exit 0 always otherwise: a report, not a gate;\n"
        "                               an unknown gate name refuses (exit 1) and names the near-misses.\n"
        "    --layout=STRUCT            the CPU/GPU contract view for ONE struct/class: its fields in declaration order with\n"
        "                               COMPUTED offsets/sizes/padding, every static_assert in the index that mentions it, and\n"
        "                               EVERY same-name definition compared field-by-field (the mirror/stub drift check that a\n"
        "                               dual-compile uniform block needs on every edit). file:name disambiguates a same-named\n"
        "                               struct (like --around/--lego). Exit 2 when the contract is BROKEN: mirror=\"mismatch\"\n"
        "                               (two definitions of the name disagree) or agree=\"0\" (a sizeof tripwire contradicts the\n"
        "                               computed size). Multi-root aware: the mirror check spans every merged root.\n"
        "                               LIMITS, read them: the offsets are a MODEL, not the ABI — a lexical walk under standard-\n"
        "                               layout assumptions on a 64-bit Apple/LP64 target (natural alignment, interior padding,\n"
        "                               trailing pad to the aggregate's own alignment). It is NOT a compiler: #pragma pack,\n"
        "                               bitfields, virtuals, base classes, nested/anonymous aggregates, #if-conditional members,\n"
        "                               templates, pointer-to-member fields and any field type it cannot size all set\n"
        "                               modeled=\"0\" with a named caveat instead of printing a number, and one unsized field\n"
        "                               un-places every field after it. alignas(N) and attribute packed ARE modelled. Array\n"
        "                               extents and macro type names resolve against the DEFINING FILE's own #define/constexpr\n"
        "                               constants only, and a macro with two definitions is accepted only when both agree on the\n"
        "                               size (the dual-compile half/__fp16 case). Definitions and asserts come from the INDEXED\n"
        "                               C-FAMILY files only (a TypeScript/Swift class has no byte layout) — .metal IS one\n"
        "                               of them (indexed under the C++ grammar, see kLangTable), so a Metal struct's layout is\n"
        "                               modelled like any other C-family aggregate.\n"
        "    --field-affinity[=STRUCT]  the CACHE-LOCALITY lens: which fields are READ TOGETHER but declared FAR APART. Builds a\n"
        "                               static field CO-ACCESS affinity graph (one observation per indexed C-family function\n"
        "                               body) and diffs it against the DECLARED field order and 64-byte cache-line geometry,\n"
        "                               reusing --layout's LP64 offset model. Bare = every aggregate in the repo, ranked by\n"
        "                               separation cost; =STRUCT narrows the report to one. Pairs carry Chilimbi's separation\n"
        "                               weight wt = (64 - dist)/64 (Cache-Conscious Structure Definition, PLDI 1999) — CITED,\n"
        "                               not invented here, along with the affinity graph and the points-to-free access\n"
        "                               enumeration; the advice-not-transform posture is Hundt et al., CGO 2006. Exactly TWO\n"
        "                               findings fire, both with a direction you can defend in one sentence: split-line (two\n"
        "                               fields co-accessed by 2+ functions at wt 0.00, so NO field order puts them on one line)\n"
        "                               and straddle (one co-accessed field crossing a line boundary). ADVICE ONLY: it never\n"
        "                               proposes a reordering and it has no rewrite mode, because pack-tighter/sort-by-size advice is\n"
        "                               NON-MONOTONIC (tight packing can induce false sharing — the reason the Go team keeps its\n"
        "                               own fieldalignment analyzer out of vet and gopls). LIMITS, both in the header: static\n"
        "                               access counts are NOT dynamic frequency, so fns= is a FLOOR of distinct indexed\n"
        "                               functions and w= is a call-graph reachability PROXY (1 + fan-in), never a measured\n"
        "                               count; only dot/arrow member syntax is counted (a bare field name inside its own method\n"
        "                               is indistinguishable from a local); a field name declared by TWO aggregates is REFUSED\n"
        "                               and tallied in amb_skipped= rather than guessed; and all geometry is the LP64 MODEL, so\n"
        "                               a definition --layout marks modeled=\"0\" contributes its affinity graph and NO geometry\n"
        "                               finding. validate= names the instrumented PROFILE_SCOPE whose hardware counters would\n"
        "                               confirm the hypothesis (see docs/FIELDAFFINITY.md for the worked example). C/C++/ObjC\n"
        "                               only. Exit 0 always: a report, not a gate.\n"
        "    --doc-drift[=SUBSTR]       which of this repo's DOC claims are now false. Verifies the CHECKABLE anchors in every\n"
        "                               markdown file (SUBSTR filters doc paths) against the live index and prints ONLY the ones\n"
        "                               that no longer hold, four kinds: file:line refs (why=\"missing-file\" the path is gone,\n"
        "                               \"past-eof\" the file is shorter than that, \"line-moved\" the line is no longer inside the\n"
        "                               symbol the doc names beside it — got= names the squatter); backticked symbol mentions\n"
        "                               (\"undefined\"); `= N` constants (\"const-value\"); and `[N]` array extents (\"array-extent\").\n"
        "                               LIMITS, stated because a doc-drift verb that cries wolf is worse than none — every lane\n"
        "                               deliberately UNDER-reports. A backticked name is called stale only when it occurs nowhere\n"
        "                               in any non-markdown file as an identifier token, so every library name is silent, and so\n"
        "                               is any repo constant the grammar does not tag as a definition (namespace-scope constexpr\n"
        "                               in C++, for one) — those are counted as unchecked r=\"not-a-definition\", never as drift.\n"
        "                               A number is compared only against a DECLARATION-shaped integer literal (a decl keyword on\n"
        "                               the line, or the name opening it) that the corpus binds UNIQUELY; two values in the tree\n"
        "                               means unchecked, not drift. A `NAME = N` whose NAME appears nowhere in the code is prose,\n"
        "                               counted in prose= and never claimed as an anchor. Symbol mentions inside ``` fences are\n"
        "                               skipped (illustrative code, not claims). checked + unchecked = anchors, always: whatever\n"
        "                               was not proved says so in an <unchecked> row. Read why=\"undefined\" precisely — it says\n"
        "                               the name is defined NOWHERE in this repo, which is not the same as DELETED: in a plan or\n"
        "                               design doc naming work not yet built, that is expected rather than rot. The file:line,\n"
        "                               const and array lanes are the high-precision ones; the mention lane is the weakest —\n"
        "                               --with-history is the fix, splitting it into why=\"deleted\" (history removed the name;\n"
        "                               got= names the commit and date, at= the file) versus unchecked r=\"never-in-history\"\n"
        "                               (this repo never had it, so it is not rot at all).\n"
        "                               DATED RECORDS vs ROT. An audit's finding row and a live map gone stale look identical —\n"
        "                               both are \"the code moved and the doc did not\" — so a failed anchor the AUTHOR DATED is\n"
        "                               split out as kind=\"dated-record\" and counted in dated=, leaving drift= for the LIVE rot.\n"
        "                               drift + dated is every anchor that failed: a record still prints, it is never dropped.\n"
        "                               rec= names the evidence, most specific first: \"line\" (the line itself hedges — an\n"
        "                               at-the-time / as-of-DATE note, or a row opening with an ISO date), \"block\" (the nearest\n"
        "                               heading carries an ISO date), \"title\" (the filename or H1 does), \"stamp\" (a LABELLED\n"
        "                               front-matter self-date: 'Date: …', 'Written …', 'Generated: …').\n"
        "                               WHAT THIS LANE CANNOT DO, because both were measured and rejected: it cannot use git\n"
        "                               history — 90 of this repo's 98 stale file:line anchors were CORRECT at their own doc's\n"
        "                               last commit, audit findings and live design docs alike, because \"was it true when\n"
        "                               written\" is the definition of BOTH a record and rot; and it will not read a bare date in\n"
        "                               the opening prose, which on this repo alone dated three LIVE documents on a day they\n"
        "                               merely mentioned. It reads dating MARKS, so a doc that is obviously an artifact-of-a-date\n"
        "                               to a human but never writes that date machine-readably reports LIVE (this repo has two).\n"
        "                               The bias is one-directional on purpose: a wrong \"record\" hides real rot, a wrong \"live\"\n"
        "                               only over-reports. An inception or freshness date ('opened …', 'Last updated …') is a\n"
        "                               claim the doc is CURRENT and never marks a record.\n"
        "                               NOT CHECKED AT ALL: prose, Status lines, dates, 'N of M done' tallies, and whether a\n"
        "                               code block's body is still correct. Always exits 0 — a report, not a gate.\n"
        "                               Root element carries at=\"<sha>[+dirty]\" (omitted on a non-git root) — the commit these\n"
        "                               counts were computed against, so a number quoted from this report stays comparable\n"
        "                               across a HEAD that moves mid-session.\n"
        "    --doc-drift --gateability  turn \"CI stays non-gating\" into a finishable to-do list: for every doc that STILL has a\n"
        "                               LIVE (undated) failing anchor, prints its path and live=N (how many of its rows a date\n"
        "                               would fix), plus projected_drift= — repo-wide drift= if EVERY listed doc got the fix.\n"
        "                               The fix is always the same one this lane already reads for rec=\"title\"/\"stamp\": an ISO\n"
        "                               date in the doc's H1/filename, or a front-matter self-date line (Date:/Written:/\n"
        "                               Generated:/Recorded:/Reviewed:/Audited:/Authored:). projected_drift= is an UPPER BOUND,\n"
        "                               not a mandate — dating a doc that is genuinely a live/current reference (not a\n"
        "                               snapshot-in-time record) would hide real rot rather than honestly classify it. Requires\n"
        "                               --doc-drift (refused loudly alone).\n"
        "    --with-history             OPT-IN: let --doc-drift and --whereis ask git HISTORY whether a name was ever in this\n"
        "                               repo, and which commit removed it. ONE `git log -p` walk over everything reachable from\n"
        "                               HEAD, tokenizing removed lines — the pickaxe's semantics without the pickaxe's cost\n"
        "                               (`git log -S` per name is ~126 s at 247 names on a 2900-file repo; this is ~3 s, and\n"
        "                               ~0.8 s on ripwire itself). Off by default because those default paths run in 0.64 s and\n"
        "                               0.15 s. Memoized per (repo, HEAD sha) — a commit is immutable, so the cache cannot go\n"
        "                               stale — and the blob covers the WHOLE repo, so a second question on the same commit\n"
        "                               costs a cache load, and --whereis reuses whatever --doc-drift already built.\n"
        "                               LIMITS: it walks HEAD's own history, so a name that only ever lived on an unmerged\n"
        "                               branch reads as never here (use --whereis's tree scan for that); a deletion performed\n"
        "                               ONLY as a merge resolution is not seen (merge diffs are not walked); and evidence is a\n"
        "                               removed LINE carrying the name, so a name whose last removal was from a doc rather than\n"
        "                               code is reported with that doc as its site. A repo deeper than the walk bound reports\n"
        "                               truncated=\"1\" and answers unknown — never \"never\" — for anything it did not reach.\n"
        "    --from-trace=FILE          map a stack trace / sanitizer report / compiler-error text ('-'=stdin) onto the indexed\n"
        "                               symbols: table-driven frame extraction (python / asan / node / compiler / generic),\n"
        "                               ranked INNERMOST-first over in-corpus frames only (out-of-corpus frames are listed and\n"
        "                               counted, never ranked). Each frame binds by its own NAME first (resolved_by=\"name\") and\n"
        "                               falls back to the def enclosing its line (resolved_by=\"line\") only when the name is\n"
        "                               absent/unknown/ambiguous — a trace older than the checkout therefore lands on the symbol\n"
        "                               it names, and a name-vs-line disagreement is disclosed as line_encloses=, never silently\n"
        "                               rebound. The counters close: in_corpus = suspects + merged + unresolved, with one\n"
        "                               <unresolved> row per file-matched frame no resolver could place. p= on a frame is the\n"
        "                               TRACE's own path:line; definition sites are the <sigs> l= values. Emits the same bundle\n"
        "                               shape as --for — top suspects' signatures + the innermost in-corpus symbol's FULL body;\n"
        "                               composes with --token-budget, and HONORS --max-tokens=N (it bounds the bodies) — one of\n"
        "                               the six shapes that do, alongside the default map, --recall, --connect, --pr-context and\n"
        "                               --for --detail=N. --top-k is NOT read here (the frame order is the trace's, not a rank).\n"
        "                               Unparseable input refuses loudly (never an empty map).\n"
        "    --run-trace=\"CMD\"          EXEC-MODE --from-trace — the whole fix-loop entry in ONE call. Runs CMD under `sh -c`\n"
        "                               (the make trust model: your user, your environment, stdin=/dev/null, NO sandbox),\n"
        "                               captures stdout+stderr interleaved, and on a NON-ZERO exit serves the --from-trace\n"
        "                               bundle for the captured text (frames mapped innermost-first, the innermost in-corpus\n"
        "                               symbol's FULL body) plus a token-frugal <lines view=\"relevant\"> cut of the error /\n"
        "                               frame-shaped output lines — shown=/relevant=/total= all disclosed, the cut never\n"
        "                               silent. The command's own exit code is ALWAYS disclosed on <run exit=>; a command\n"
        "                               that exits 0 gets a minimal success record (exit, measured duration_ms, a disclosed\n"
        "                               tail of output) and NO bundle — nothing failed, so there is nothing to map. The <run>\n"
        "                               record and captured lines are MEASURED (not deterministic, not claimed to be); the\n"
        "                               MAPPING of the captured text is byte-deterministic, and the document says which part\n"
        "                               is which. Composes with --token-budget (it bounds the bundle half, like --from-trace);\n"
        "                               --top-k / --max-tokens are not read here. ripwire's exit: 0 = the command succeeded;\n"
        "                               4 = it failed or timed out (the report is on stdout either way); 1 = ripwire itself\n"
        "                               could not spawn it.\n"
        "    --run-timeout=SECONDS      cap for --run-trace's command (default 600 s; always disclosed as timeout_s=). A\n"
        "                               command still running at the cap has its whole process group killed and is reported\n"
        "                               timed_out=\"1\" — an honest TIMEOUT, never an empty success. Modifies --run-trace\n"
        "                               only; refused loudly alone.\n"
        "    --note-add=\"TARGET: text\"  pin a field note (write-side memory) to TARGET — a canonical id (path::scope::name, as\n"
        "                               --for/--expand emit it) or a file path — in the committed, sorted .ripwire_notes at the\n"
        "                               repo root. The date is git's committer clock (HEAD), not wall time, so the line is\n"
        "                               deterministic; prints the exact written line. Also STAMPS the writing repo's HEAD sha +\n"
        "                               branch onto the note (a \"done\"/\"fixed\" claim is then anchored to the commit it was\n"
        "                               true at) — a non-git root or an unresolvable HEAD writes the plain unstamped line rather\n"
        "                               than a wrong sha. MUTATES one file; single-root only. text with no causal/decision\n"
        "                               marker (\"because\"/\"chose\"/\"over\"/\"instead\"/etc.) gets a gentle stderr tip toward the\n"
        "                               decision shape — never a refusal, the add always proceeds.\n"
        "    --notes                    list all field notes grouped by target; a target with no matching indexed symbol/file is\n"
        "                               flagged dangling=\"1\" (legal — surfaced nowhere, listed here). Read-only.\n"
        "                               Notes surface automatically as <note d=\"date\" [sha=\"…\" branch=\"…\"]> children on the\n"
        "                               symbols/files that --for and --expand emit (and the MCP for / fetch_body verbs); the\n"
        "                               sha/branch attrs appear only on notes stamped by this version, abbreviated (7 hex) for\n"
        "                               terseness — the full sha lives in .ripwire_notes on disk. An OLDER .ripwire_notes (3\n"
        "                               fields, pre-provenance) reads and surfaces exactly as before, with no sha/branch shown.\n"
        "                               Absent/empty file = zero effect.\n"
        "    --pack-task=\"TASK\"          the budget-shared task bundle: ONE call assembling, under ONE deterministic budget\n"
        "                               (default 6K tokens; --token-budget overrides), the whole orientation dance in FIXED order —\n"
        "                               (1) routed+anchored ranking, (2) top-K full bodies, (3) their 1-hop caller signatures,\n"
        "                               (4) their field notes, (5) tests_to_run for the top files, emitted in FIXED order\n"
        "                               ranking>bodies>callers>notes>tests. Each section holds a FIXED, up-front proportional quota\n"
        "                               of the budget (rank40/body30/caller15/note5/test10, percent); an under-spent section's\n"
        "                               leftover quota ROLLS FORWARD to the next section, so a small budget still zeroes a section\n"
        "                               eventually but never past its own fair share. Each section truncates rank-adaptively and\n"
        "                               the header reports EVERY truncation (no silent caps). A tiny budget degrades to\n"
        "                               ranking-only WITH the truncation note. Refuses loudly without a task string.\n"
        "      --partition=N            (with --pack-task, N=2..16) FAN-OUT form: instead of one bundle, emit ONE shared common core\n"
        "                               plus N per-agent slices, so N parallel agents stop re-deriving the same orientation. The\n"
        "                               task's ranked surface is carved along the call graph's own Louvain communities — a partition\n"
        "                               is a union of WHOLE modules (largest-first packing) so it reads coherently; when there are\n"
        "                               fewer modules than agents the widest is cut at its rank median and split=\"K\" says so. The\n"
        "                               core is exactly the anchors a plain --pack-task would have bodied. --token-budget then means\n"
        "                               ONE AGENT's budget (core + its partition), not the document's — total_bytes reports the rest.\n"
        "                               Each inner <ctx> is byte-identical to a standalone call with that slice, so an orchestrator\n"
        "                               hands one bundle to one agent verbatim. LIMITS: overlap_mean/overlap_max are pairwise Jaccard\n"
        "                               over the ids each partition NAMES (window + bodies + their 1-hop neighbors) measured BEFORE\n"
        "                               budget trimming — a ceiling, not the trimmed truth; and on a task whose surface sits inside\n"
        "                               one module the split is a rank cut, not a semantic one (read split= and overlap_max before\n"
        "                               trusting the slices). Refuses loudly without --pack-task, or outside 2..16;\n"
        "                               --with-graph does not compose with it (N+1 bundles, no single graph — says so on stderr).\n"
        "    --with-graph               (with --for/--pack-task) append a compact MERMAID flowchart of the bundle's top-N (<=8)\n"
        "                               ranked anchors + their 1-hop call edges among themselves — <graph fmt=\"mermaid\"><![CDATA[\n"
        "                               flowchart LR ...]]></graph>, right before </ctx>. Reuses the --mermaid emitter's syntax.\n"
        "                               Costs tokens beyond the sigs it sits next to — worth it only when the reading agent\n"
        "                               renders mermaid natively. Off by default (G5): omitted, output is byte-identical.\n"
        "    --export=cc.json[:FILE]    export per-file metrics (loc/symbols/cx/cognitive_cx/fan-in/fan-out/churn) as CodeCharta\n"
        "                               cc.json (apiVersion 1.3) — write FILE or redirect stdout; feeds a CodeCharta 3D city\n"
        "    --batch=FILE               one-turn context sweep: FILE ('-'=stdin) is newline-delimited `verb:arg` sub-queries\n"
        "                               (for/grep/callers/callees/impact/uses/mentions/analyze/lego/owners/cochange/exemplar,\n"
        "                               path_between:FROM,TO), answered in ONE deduped <batch>; caps at 16 (over-cap = capped=1)\n\n"
        "  self-diagnosis\n"
        "    --doctor                   environment self-check: binary-vs-PATH staleness, grammar tags.scm compile,\n"
        "                               cache-dir health, git reachability, tree-sitter version, and TRACKED-BINARY\n"
        "                               staleness (a committed binary whose last commit is a git-history ANCESTOR of a\n"
        "                               same-directory/same-stem source's last commit — never mtime, which a fresh\n"
        "                               clone stamps at checkout time). \"Dependent source\" is a NAMING heuristic (same\n"
        "                               dir, same filename stem, e.g. tool <-> tool.cpp) — ripwire parses no build\n"
        "                               system, so a binary built from a differently-named or differently-located\n"
        "                               source is silently out of scope, neither flagged nor cleared. Single-root only.\n"
        "                               DIAGNOSTIC, not deterministic (env-dependent by design); exit 0 iff all ok,\n"
        "                               else 1. Root reports <doctor checks=N passed=M ...>; each <c/> child row\n"
        "                               carries the BOOLEAN ok=\"0|1\". passed= is the root's count (it was spelled\n"
        "                               ok= until the vocabulary pass, which collided with the child bool). A FAILING\n"
        "                               row (ok=\"0\") also carries hint=, the derived verdict (which of self=/which=\n"
        "                               is stale and the fix, which grammar(s) failed to compile, why the cache dir\n"
        "                               isn't writable, ...) — a passing row never carries hint=.\n"
        "    --skipped                  WHY the index does not contain a file, and which files it DOES contain but cannot\n"
        "                               vouch for. <f p= why= bytes=/> per DROPPED file: why=oversize (limit= names the ceiling\n"
        "                               — --max-file-size, or the fixed .json/.yaml config ceilings it does not raise),\n"
        "                               why=excluded (--exclude hit), why=unsupported-ext (ext= has no grammar in this build —\n"
        "                               the class that hides a whole LANGUAGE). <h p= why= err= err_ratio= ws_freq=/> per\n"
        "                               INDEXED-but-suspect file, nothing dropped: why=degraded-parse (the parse holds\n"
        "                               ERROR/MISSING nodes — a parser-state fact, never a syntax verdict) and/or\n"
        "                               why=minified-suspect (ws_freq under 0.070 over the leading 4KB). <e x= files=/> per\n"
        "                               unindexed extension — what the map header rolls up as unindexed=. <lang n= files=\n"
        "                               symbols=/> per LANGUAGE this build DID extract from — the mirror of unindexed= (which\n"
        "                               names what it could NOT read at all); sorted files DESC then name ASC, absent means the\n"
        "                               language contributed nothing, never a printed zero; files= is a floor (a file with zero\n"
        "                               extracted symbols is not attributed to any language), symbols= is exact. The root states the\n"
        "                               ACCOUNTING INVARIANT indexed= + oversize= + excluded= = the enumerated candidate\n"
        "                               population, plus unsupported_ext=, excluded_dirs= (SUBTREES --exclude pruned: contents\n"
        "                               UNKNOWN, not zero), pruned_dirs= (SUBTREES this build always prunes by policy — the\n"
        "                               committed noise/vendor/build denylist and any dir holding a CMakeCache.txt — contents\n"
        "                               likewise UNKNOWN), degraded_parse=, minified_suspect=, unmeasured= (indexed files this run\n"
        "                               never parsed) and the effective ceilings, so a zero-row report still states its\n"
        "                               bounds. rows_capped=\"1\" ⇒ rows are a sample of an exact count. Rows sort by path;\n"
        "                               composes with --max-file-size/--exclude and multi-root (rows carry the\n"
        "                               <label>/./<rel> spelling). Read-only; exit 0 always: a report, not a gate.\n\n"
        "  security — scan skill files for injection / exfiltration patterns (exit 2 = CRITICAL, 1 = WARN,\n"
        "                               0 = clean; exit 3 = the path could not be read at all — refused,\n"
        "                               never reported as a clean scan); stdout carries one deterministic\n"
        "                               <skillscan files= findings= verdict=> artifact with an <f p= rule= sev=>\n"
        "                               row per finding (never emitted on the exit-3 refusal path); stderr\n"
        "                               carries the human tally line\n"
        "    --scan-skill=FILE          scan a single skill file before installing (any file, not just .md)\n"
        "    --scan-skills[=DIR]        scan DIR (or .agents/skills/ + ~/.claude/skills/ + ${CODEX_HOME:-~/.codex}/skills/).\n"
        "                               EVERY text file, .md and .sh alike — a skill dir's executables are the\n"
        "                               files most worth scanning. skipped= counts what it could not scan\n"
        "                               (binary content, or unreadable); denylisted subtrees (.git, node_modules,\n"
        "                               build, ...) are not descended and the stderr tally says how many\n"
        "                               for vulnerabilities\n"
        "    --force                    (wrap) proceed even if CRITICAL findings are found\n\n"
        "  knobs / modes\n"
        "    --rank-by=pagerank|authority|hub|rrf|churn|churn-decay   ranking signal (churn = git change-frequency prior, and\n"
        "                               stamps its own map with rank_by/window/at so it cannot pass for the structural one;\n"
        "                               churn-decay = the same prior with each commit weighted 0.5^(age_days/90) instead of\n"
        "                               counted equally, so recent edits outweigh old ones. Its age clock is HEAD's OWN commit\n"
        "                               timestamp, never the wall clock, so the default (whole-history) run is byte-stable for a\n"
        "                               fixed tree; the half-life is disclosed in window=. default pagerank)\n"
        "    --format=xml|columnar|rows output shape for the FLAT list verbs (--callers/--callees/--uses/--impact):\n"
        "                               xml (default, byte-identical) or columnar (a <paths> table + parallel arrays: fields=\n"
        "                               path,name,line,kind on --callers/--callees/--impact, path,line,role,in_id on --uses —\n"
        "                               the emitted block's own legend states the zip/n=/&#44;-escape contract;\n"
        "                               ~15-60%% fewer tokens on multi-row results, by de-duplicating the repeated per-row markup + paths; results of a few rows\n"
        "                               can be LARGER — the paths/cols scaffold has a fixed cost). rows is an alias\n"
        "                               for columnar. Any OTHER verb refuses (exit 1) — it has no row list to re-encode. Map is\n"
        "                               unaffected.\n"
        "    --format=candidates        (with --for/--query) a FLAT top-K export for an EXTERNAL reranker: one\n"
        "                               <cand r= s= n= id= k= p= l=><sig>..</sig></cand> row per result — identity + score +\n"
        "                               signature only, no lens/quality extras, no doc bodies. Composes with --top-k.\n"
        "    --legend=full|compact     output legend posture for --for and --grep/--regex only. full is byte-identical to the\n"
        "                               default; compact keeps every data/completeness attribute, adds a versioned schema id,\n"
        "                               and shortens repeated explanatory prose. Unsupported verbs refuse.\n"
        "    --json                     machine-parseable JSON instead of XML, SAME content, keys mirror the XML attr\n"
        "                               names 1:1 — supported for the default map, --for, --pack-task, --callers/--callees/\n"
        "                               --impact, --quality-delta, --test-gate (the CI/scripting verbs). Every other verb\n"
        "                               (and --format=columnar/candidates, --detail, --map-diff, --scip composed with it)\n"
        "                               refuses loudly on stderr + exit 1 rather than silently falling back to XML.\n"
        "                               Deterministic: same 2-run byte-diff + stable key order contract as the XML.\n"
        "    --limit=N --offset=M       paginate a high-cardinality verb. HONORED by: --deps --callers --callees --tree\n"
        "                               --lint --hotspots --clones --cochange --owners --communities --community --doc-drift\n"
        "                               --whereis --grep/--regex --match --pattern --impact --uses --exercises --seams\n"
        "                               --zoom --external-surface --dead-code --mentions --graph-query --stray-content\n"
        "                               --test-gate --readability --ensemble --quality-panel --context-ratio\n"
        "                               --nonlocal-state --comment-coherence --naming-consistency --safe-delete.\n"
        "                               Emit at most N rows, skipping the first M; N overrides the verb's own display cap\n"
        "                               (40 hotspot files, 30 co-change pairs, 60 whereis hits, 100 grep/match hits, 40\n"
        "                               impact rows, 20 seam pairs, 40 readability rows, 40 ensemble symbol rows, 40 context-ratio\n"
        "                               symbol rows, 40 nonlocal-state rows, 200 graph-query rows / --top-k).\n"
        "                               With --offset alone (no --limit) the verb's own default page size applies and\n"
        "                               the root discloses limit=\"0\" — on OUTPUT that 0 means 'no explicit --limit',\n"
        "                               never a zero-row page (the flag itself refuses --limit=0).\n"
        "                               Deterministic seams (rows are already sorted) so --offset=N is the exact\n"
        "                               continuation of the previous --limit=N page. The root element then carries\n"
        "                               shown= capped= total= has_more= next_offset= offset= limit= — loop until\n"
        "                               has_more=\"0\" — EXCEPT the verbs with TWO INDEPENDENT listings, which carry the\n"
        "                               noun-prefixed form instead (one shown= could only describe one): --test-gate\n"
        "                               shown_tests=/tests_capped= + shown_untested=/untested_capped=, --communities\n"
        "                               shown_modules=/modules_capped= + shown_bridges=/bridges_capped=, --ensemble and\n"
        "                               --context-ratio shown_syms=/syms_capped= + shown_files=/files_capped=; the window\n"
        "                               takes the PRIMARY listing (--test-gate's <u> rows; its <t> rows repeat on every\n"
        "                               page, complete).\n"
        "                               Any verb NOT in that list REFUSES both flags (exit 1) rather than accepting and\n"
        "                               ignoring them: budget/top-k verbs (--for/--recall/--pack-task/--from-trace/\n"
        "                               --expand/--outline/--pack-signatures/--format=candidates) are shaped by\n"
        "                               --top-k/--max-tokens/--token-budget, not a page; the rest (--path/--connect/\n"
        "                               --around/--exemplar/--report/--mermaid/--map-diff/--metrics and the default map)\n"
        "                               answer with a single fixed-shape result that has no row list to window at all.\n"
        "    --exclude=SUBSTR           drop matching paths (repeatable)   --ignore-tests\n"
        "    --map-diff                 the FULL map, re-ranked with a PageRank teleport toward git-changed files (working tree\n"
        "                               vs HEAD) — changed files and their neighbours float up, but every file can still appear;\n"
        "                               this is NOT a filter to only-changed symbols. changed=\"N\" in the header names the seed\n"
        "                               file count (0 on a clean tree or no-git — teleport degrades to uniform; ranked CONTENT is\n"
        "                               then identical to the plain default map, but not byte-identical: the map-diff header keeps\n"
        "                               its changed= and at= stamp). Want only-changed instead? --pr-context.\n"
        "    --cache=PATH               incremental cache at PATH (re-parse only changed files)\n"
        "    --index-out=BASE           CI generate-and-exit: cold-parse the tree and write the committable index artifact,\n"
        "                               then exit 0 with NO map on stdout. Writes BOTH families — BASE.lean.ripwirecache (map/\n"
        "                               nav/--pr-context) and BASE.rich.ripwirecache (--for/--exemplar/--metrics/--uses are RICH,\n"
        "                               a lean-only artifact leaves them cold). Consume in a PR job with --cache=BASE.lean.ripwirecache\n"
        "                               (or .rich.). --exclude shapes the crawl and therefore the blob content. Same-architecture\n"
        "                               speed cache: consumed on a different arch it self-heals to a full cold parse (correct, slower).\n"
        "                               NOT byte-identical run-to-run (the header stamps the blob write time); the contract is\n"
        "                               RESTORE-EQUIVALENCE (a --cache restore == a cold parse), never blob-byte-identity.\n"
        "    --no-cache                 disable the warm-by-default per-root TMPDIR cache (forces a cold parse)\n"
        "    --max-file-size=N[K|M|G]   skip files larger than N bytes (default 4MB; raise for repos with\n"
        "                               big hand-authored source, e.g. --max-file-size=100M; suffix = 1024^n).\n"
        "                               .json carries a SECOND, fixed 256KB ceiling this flag does not raise\n"
        "                               (that size of .json is data, not config, and explodes the symbol\n"
        "                               table); files it drops are counted in the header's skipped_oversize=\n"
        "    --refetch                  when the root is a git URL, force a fresh clone instead of reusing the\n"
        "                               cached one (default: reuse forever; stderr notes the cached clone's age)\n"
        "    --scip=index.scip          consume a SCIP index as a PRECISION overlay: precise call edges replace\n"
        "                               name-based guesses (tagged prov=\"scip\"), ambiguous= drops. Missing/corrupt\n"
        "                               index → degrades to name-based (never fails). Zero deps (hand-rolled reader).\n"
        "    --mcp                      persistent index server (parse once, many warm queries) over stdio\n"
        "    --listen=HOST:PORT         serve the MCP server over Streamable HTTP instead of stdio (implies --mcp).\n"
        "                               Binds 127.0.0.1 by default (bare PORT = loopback); one listener serves ONE\n"
        "                               workspace fixed at startup. A non-loopback host (e.g. 0.0.0.0:8080) REQUIRES\n"
        "                               --mcp-token and refuses to start without it. No TLS — reverse-proxy it.\n"
        "    --mcp-token=T              shared bearer token gating every HTTP request (or set RIPWIRE_MCP_TOKEN);\n"
        "                               a missing/wrong token gets a 401. Required for a non-loopback bind.\n"
        "    --allow-remote-edits       permit the edit verbs over --listen (refused by default: a remote file-writer\n"
        "                               is a different trust contract); forces the token requirement even on loopback\n"
        "    --eval-stray=FILE          labelled verdict-accuracy eval for --stray-content: FILE is TSV `ref<TAB>verdict`\n"
        "                               (merged|superseded|unmerged, '#' comments ok). Emits per-case want=/got= plus an\n"
        "                               accuracy, and exits 3 if any labelled case regressed — MEASURE a supersession-\n"
        "                               threshold change against real labels instead of eyeballing it. A ref absent from\n"
        "                               the report scores as merged (merged refs are omitted by design).\n"
        "    --eval                     self-eval (co-change recall vs BM25)\n"
        "    --eval-retrieval           known-item retrieval eval: for symbols WITH a doc-comment, query by NAME and\n"
        "                               by a doc-comment PHRASE; reports MRR + recall@1/5/10 per ranker (subtoken+body,\n"
        "                               name-exact, anchored, routed) per query-mode. Validates query-TIME ranker choice.\n"
        "    --eval-mined=FILE          session-trace-mined retrieval eval: consumes a minedpair.jsonl artifact from\n"
        "                               bench/mine_traces.py (real (query, gold-files) pairs mined from local Claude\n"
        "                               Code session transcripts) and reports recall@5/10/20 + Acc@k + MRR per arm\n"
        "                               (for/query/anchor/random), assisted vs unassisted.\n"
        "    --eval-skills=FILE         labelled skill-ROUTING eval: ROOT is a skills directory (one SKILL.md per\n"
        "                               subdir); FILE is TSV `prompt<TAB>skill[,skill]|none<TAB>provenance`. Scores\n"
        "                               deterministic selectors (keyword overlap = the trivial baseline, BM25 over\n"
        "                               descriptions/full text, name match, the routed --for ranker) on top-1-in-\n"
        "                               permitted-set plus positive/negative separation (AUC) — does the right skill\n"
        "                               fire, does every skill stay quiet on off-topic prompts. Ambiguous moments\n"
        "                               carry a permitted SET; `none` rows are first-class.\n"
        "    -h, --help                 this catalog\n"
        "    -v, --version              print the version + short build info, exit 0\n\n"
        "determinism: output is byte-identical run-to-run  (ripwire <dir> >a; ripwire <dir> >b; diff -q a b)\n" );
}

inline void usage() noexcept { printUsage( stderr ); }

// ── the flag tables — the 91 arms that are exactly "set one member" ─────────────────────────────────
// House style is declarative tables over scattered switch/if (CLAUDE.md), and this is that rule applied
// to the two shapes that make up most of the argv surface: `--x` sets one bool, `--x=V` sets one view.
// Config is 71 bool + 53 string_view, so a pointer-to-member is constexpr and well-defined here — no
// offsetof, which would be UB on a non-standard-layout type.
//
// ORDER. The tables are scanned in DECLARATION ORDER, exacts before prefixes, ahead of the hand-written
// arms — so the chain's original precedence is preserved only because no literal in the surface shadows
// another. That is not asserted, it is re-derived from src/cli.h on every run by test/flagtablecheck.sh:
// no table prefix is a prefix of any other arm's literal, and an exact match cannot swallow a longer
// argv. Add a flag that violates it and that gate goes red before the parser does anything surprising.
//
// The `//` note on an arm travels WITH its row — a table row is already less greppable than an inline
// equality test, and stripping the prose that explains why a bare flag is legal would make it worse.
// (The literal that would have illustrated that is deliberately absent: flagsurfacecheck.sh harvests the
// parsed surface from THIS file's string literals, so a fake --flag in a comment reads as a real one.)
struct BoolFlag { std::string_view lit;    bool             Config::* member; };

// §A9 V1-4: `needs`/`example` are the EMPTY-VALUE contract. Non-null `needs` ⇒ `--flag=` with nothing after
// the '=' is refused (exit 1) through refuseEmptyValue above, naming this flag and showing `example`.
// Left null ⇒ an empty value is meaningful for that flag (a path/label the rest of the parser interprets,
// or a value whose own arm already refuses) and the argv reaches the member unchanged. A new value-taking
// flag therefore has to state which it is, in the row, at the point the flag is declared.
//
// OWNER RULING 2026-07-29 (recorded as reversible): NINE rows were
// carrying that null by omission rather than by decision — `--since=` `--cache=` `--index-out=` `--scip=`
// `--lint-rules=` `--mcp-token=` and the three `--eval-*=` — and downstream every one of them is guarded by
// `!cfg.X.empty()`, so the empty value did not reach a member that means anything: the run emitted the
// whole default map at exit 0 with nothing on stderr. `--hotspots --since=zzqq9` refuses loudly while
// `--hotspots --since=` was silent, one keystroke apart. The ruling is refuse-ALL: every row now states its
// domain and an example, including the five config-passthrough paths, so "an empty value is a no-op here"
// is no longer expressible by forgetting to fill the columns in. There are now no null-`needs` rows —
// leaving one is still legal, but it has to be argued for in the row, which is the whole point of the pair.
// §B5 (capture-audit-4, 2026-07-30) — WHAT AN EMPTY VALUE MEANS, as a required table column.
//
// Last round's refuse-all ruling swept this table's 33 rows and left the 40 hand-written arms in parseArgs
// alone, which is trap-ledger #6 in the flesh ("a ruling that produces a table sweeps the table, not the
// surface"). The sweep found four arms out there silently accepting an empty value — the sharpest being
// `--listen=`, where a `$PORT` that expanded to nothing turned a NETWORK TRANSPORT SELECTOR into a live
// stdio MCP server at exit 0, one keystroke from the `--listen=notaspec` form that refuses loudly.
//
// Adding four more hand-written refusals would have reproduced the bug (36 arms still outside the table), so
// instead the arms MOVED IN — every hand-written arm whose whole body was "assign one string_view member,
// optionally set one or two companion bools" is now a row here (44 → 17 hand-written). What a table cannot
// express honestly stays hand-written: a vector member (--exclude=, --expand=, --outline=), a byte-size or
// enum PARSE (--token-budget=, --rank-by=, --format=, --export=, …), the deprecation-warning aliases.
//
// And the column below is why this class cannot come back. `needs`/`example` alone could only say "refuse";
// they could not tell a row that DELIBERATELY accepts an empty value (`--situ=` means exactly `--situ`) from
// a row nobody had thought about — the two looked identical, which is how nine rows shipped with
// needs=nullptr last round and four arms shipped with no check at all this one. `EmptyValue` makes the
// decision MANDATORY and NAMED, and consteval below enforces that `needs` is present exactly for Refuse.
enum class EmptyValue : std::uint8_t
{
    Refuse,             // a trailing `=` with nothing after it is a MISTYPED VERB: refuse here, via refuseEmptyValue
    Meaningful,         // "" is a real value for this flag — the bare-or-filter forms, where --flag= ≡ --flag
    HandlerRefuses,     // the verb's own handler refuses it with a verb-specific sentence; recorded so that
                        // "accepted silently" can never hide behind "not in the table". Each such row names
                        // the refusing handler in a trailing comment.
};

struct ViewFlag
{
    std::string_view    prefix;                    // "--grep=" — matched by PREFIX, so declaration order matters
    std::string_view Config::* member;             // the value's home
    EmptyValue          onEmpty = EmptyValue::Refuse;
    const char*         needs   = nullptr;         // the DOMAIN in the refusal's voice — Refuse rows only
    const char*         example = nullptr;         // runnable, and inside that domain — Refuse rows only
    bool Config::*      isSetFlag     = nullptr;   // companion bool the =VALUE form also sets (--owners= ⇒ owners)
    bool Config::*      isSetFlagAlso = nullptr;   // a SECOND companion (--quality-ack= ⇒ qualityAck + qualityDelta)
    // G1/F1: a GENERIC "already given" guard, distinct from isSetFlag's verb-selection meaning — two rows
    // (--grep= and --regex=) point at the SAME member (Config::grep) and a second occurrence of EITHER used
    // to silently overwrite the first. When set, a row REFUSES (dupMessage, exit-1-with-example, the house
    // refusal shape) instead of assigning, the moment `c.*dupGuardFlag` is already true; on a clean first
    // assignment it flips the flag true so a genuine second occurrence — of either spelling — is caught.
    bool Config::*      dupGuardFlag  = nullptr;
    const char*         dupMessage    = nullptr;   // printed verbatim (with the "ripwire: " lead-in) when dupGuardFlag fires
};

inline constexpr BoolFlag kBoolFlags[] =
{
    // map shaping
    { "--ignore-tests",       &Config::ignoreTests        },
    { "--map-diff",           &Config::mapDiff            },

    // server + self-eval entry points
    { "--mcp",                &Config::mcp                },
    { "--allow-remote-edits", &Config::allowRemoteEdits   },
    { "--eval",               &Config::eval               },
    { "--eval-retrieval",     &Config::evalRetrieval      },
    { "--eval=knownitem",     &Config::evalRetrieval      },   // alias
    { "--pack-signatures",    &Config::packSignatures     },

    // ordering (the --order= aliases stay hand-written: they warn)
    { "--no-stable",          &Config::noStable           },

    // the analysis lenses
    { "--metrics",            &Config::metrics            },
    { "--deps",               &Config::deps               },
    { "--hotspots",           &Config::hotspots           },
    { "--clones",             &Config::clones             },
    { "--readability",        &Config::readability        },
    { "--nonlocal-state",     &Config::nonlocalState      },
    { "--ensemble",           &Config::ensemble           },
    { "--context-ratio",      &Config::contextRatio       },
    { "--quality-panel",      &Config::qualityPanel       },   // bare flag → the `default` preset (the value is an OPTIONAL selection)
    { "--naming-calibration", &Config::namingCalibration  },
    { "--naming-consistency", &Config::namingConsistency  },
    { "--naming-locals",      &Config::namingLocals       },
    { "--comment-coherence",  &Config::commentCoherence   },
    { "--cochange",           &Config::cochange           },
    { "--cochange-groups",    &Config::cochangeGroups     },   // matched by EQUALITY, scanned before the prefix table, so it can
                                                                // never shadow --cochange nor be shadowed by --cochange=FILE
    { "--communities",        &Config::communities        },
    { "--community",          &Config::communityFlag      },   // bare flag → empty ID → handler refuses loudly. Matched by
                                                                // EQUALITY and scanned before the prefix table, so it can never
                                                                // shadow --communities (nor be shadowed by --community=ID).
    { "--zoom",               &Config::zoom               },
    { "--report",             &Config::report             },
    { "--tree",               &Config::tree               },
    { "--seams",              &Config::seams              },
    { "--mermaid",            &Config::mermaid            },

    // change / blast-radius
    { "--situ",               &Config::situ               },
    { "--handoff",            &Config::handoff            },
    { "--test-gate",          &Config::testGate           },
    { "--exercises",          &Config::exercisesFlag      },   // bare flag → empty TESTFILE → handler refuses loudly
    { "--field-affinity",     &Config::fieldAffinity      },   // bare flag → whole-repo ranking (the value is an OPTIONAL narrowing)

    // cache + diagnostics
    { "--no-cache",           &Config::noCache            },
    { "--refetch",            &Config::refetch            },
    { "--doctor",             &Config::doctor             },
    { "--skipped",            &Config::skippedList        },

    // output shape
    { "--json",               &Config::json               },   // L2: JSON output for the core/CI verbs (see Config::json)

    // search
    { "--no-prefilter",       &Config::noPrefilter        },
    { "--handles",           &Config::grepHandles        },
    { "--lint",               &Config::lint               },
    { "--lint-catalog",       &Config::lintCatalog        },   // the built-in rule registry — src/lintcatalog.h
    { "--sarif",              &Config::sarif              },   // (with --lint / --lint-rules) SARIF 2.1.0 instead of native XML

    // the --for lens modifiers (each refused alone by validateConfig)
    { "--anchor",             &Config::anchor             },
    { "--no-route",           &Config::noRoute            },
    { "--adaptive",           &Config::adaptive           },
    { "--no-mention-boost",   &Config::noMentionBoost     },
    { "--cochange-boost",     &Config::cochangeBoost      },
    { "--no-doc-mention",     &Config::noDocMention       },
    { "--signatures-only",    &Config::signaturesOnly     },   // T3 opt-out: the pre-terminal signatures-only --for bundle
    { "--auto-bodies",        &Config::autoBodies         },   // compact-route opt-out: the rank-first body walk, back on the conceptual route

    // graph surface
    { "--external-surface",   &Config::externalSurface    },

    // skills, reports, redaction
    { "--scan-skills",        &Config::scanSkills         },
    { "--force",              &Config::force              },
    { "--html",               &Config::html               },
    { "--owners",             &Config::owners             },
    { "--compress",           &Config::compress           },
    { "--no-redact",          &Config::noRedact           },

    // quality + dead code
    { "--baseline",           &Config::baseline           },
    { "--baseline-update",    &Config::baselineUpdate     },
    { "--dead-code",          &Config::deadCode           },
    { "--quality-baseline",   &Config::qualityBaseline    },
    { "--quality-delta",      &Config::qualityDelta       },
    { "--dmm",                &Config::dmm                },   // bare flag → the working tree vs HEAD (the value is an OPTIONAL rev/range)

    // review + the cross-branch verbs
    { "--pr-context",         &Config::prContext          },
    { "--whereis",            &Config::whereisFlag        },   // bare flag → empty SYM → handler refuses loudly
    { "--stray-content",      &Config::strayContent       },
    { "--plan",               &Config::landingPlan        },   // bare flag → refused below without --stray-content
    { "--abi",                &Config::abiFlag            },   // bare flag; requires --stray-content, refused below
    { "--flags",              &Config::darkFlags          },
    { "--flip",               &Config::flipFlag           },   // bare flag → empty NAME → refused below
    { "--layout",             &Config::layoutFlag         },   // bare flag → empty STRUCT → handler refuses loudly
    { "--plan-lanes",         &Config::planLanesFlag      },   // bare flag → the --brief form; refused below without --task/--brief
    { "--doc-drift",          &Config::docDrift           },
    { "--gateability",        &Config::gateabilityFlag    },   // requires --doc-drift, refused below
    { "--with-history",       &Config::withHistory        },

    // notes + packs
    { "--notes",              &Config::notesList          },
    { "--pack-task",          &Config::packTaskFlag       },   // bare flag → empty task → handler refuses loudly
    { "--with-graph",         &Config::withGraph          },
};

// G1/F1 — shared by both kViewFlags rows that write Config::grep (--grep= and --regex=): a second
// occurrence of either used to silently overwrite the pattern from the first (measured: `--grep=foo
// --grep=bar` exits 0 with pattern="bar", `foo` discarded, nothing on stderr). The natural spelling an
// agent reaches for when it means "AND" is a second --grep=, so the refusal names that spelling directly
// rather than a generic "flag given twice".
inline constexpr const char* kGrepDupMessage = "--grep given twice; did you mean --grep='A' --and='B'?";

inline constexpr ViewFlag kViewFlags[] =
{
    // server + self-eval inputs
    { "--mcp-token=",   &Config::mcpToken        , EmptyValue::Refuse, "a shared bearer token",                  "--mcp-token=$RIPWIRE_MCP_TOKEN" },
    { "--eval-mined=",  &Config::evalMined       , EmptyValue::Refuse, "a minedpair.jsonl file path",            "--eval-mined=bench/minedpair.jsonl" },
    { "--eval-skills=", &Config::evalSkills      , EmptyValue::Refuse, "a labelled TSV file path",               "--eval-skills=bench/skillroute.tsv" },

    // architecture + graph paths
    { "--arch=",        &Config::archRules       , EmptyValue::Refuse, "a layering-rules file path",             "--arch=arch_rules.txt" },
    { "--path=",        &Config::pathSpec        , EmptyValue::Refuse, "two symbol names, FROM,TO",              "--path=main,rankGraph" },
    { "--connect=",     &Config::connectSpec     , EmptyValue::Refuse, "two or more symbol names, A,B[,C]",      "--connect=parseArgs,serialize,rankGraph" },
    { "--impact=",      &Config::impactSym       , EmptyValue::Refuse, "a symbol name",                          "--impact=parseArgs" },
    { "--mentions=",    &Config::mentionsSym     , EmptyValue::Refuse, "a symbol name",                          "--mentions=parseArgs" },
    { "--affected=",    &Config::affectedFiles   , EmptyValue::Refuse, "changed files or a symbol name",         "--affected=src/cli.h" },
    { "--verify=",      &Config::verifyClaim     , EmptyValue::Refuse, "a claim expression",                     "--verify='calls(parseArgs, readFile)'" },
    { "--help-task=",   &Config::helpTask        , EmptyValue::Refuse, "a task in words",                        "--help-task=\"review my changes before push\"" },

    // cache, index, history
    { "--cache=",       &Config::cacheFile       , EmptyValue::Refuse, "a cache file path",                      "--cache=.ripwirecache" },
    { "--index-out=",   &Config::indexOut        , EmptyValue::Refuse, "a base path for the index artifacts",    "--index-out=.ripwire/index" },
    { "--since=",       &Config::since           , EmptyValue::Refuse, "a git revision or date",                 "--since=HEAD~20" },
    { "--scip=",        &Config::scipIndex       , EmptyValue::Refuse, "a SCIP index file path",                 "--scip=index.scip" },

    // search and the --for lens
    { "--query=",       &Config::query           , EmptyValue::Refuse, "search terms",                           "--query=\"teleport pagerank\"" },
    { "--legend=",      &Config::legend          , EmptyValue::Refuse, "full or compact",                        "--legend=compact" },
    { "--grep=",        &Config::grep            , EmptyValue::Refuse, "a literal string to search for",         "--grep=parseArgs",
      nullptr, nullptr, &Config::grepGiven, kGrepDupMessage },
    { "--match=",       &Config::match           , EmptyValue::Refuse, "a tree-sitter s-expression pattern",     "--match='(call_expression)'" },
    { "--pattern=",     &Config::pattern         , EmptyValue::Refuse, "a code-shaped pattern",                  "--pattern='foo($X, ...)'" },
    { "--lint-rules=",  &Config::lintRulesDir    , EmptyValue::Refuse, "a rules directory path",                 "--lint-rules=lintrules/" },
    { "--lint-select=", &Config::lintSelect      , EmptyValue::Refuse, "a comma-separated PREFIX list, or '*'",  "--lint-select=cache-,goto" },
    { "--lint-ignore=", &Config::lintIgnore      , EmptyValue::Refuse, "a comma-separated PREFIX list, or '*'",  "--lint-ignore=naming-" },
    { "--for=",         &Config::forTask         , EmptyValue::Refuse, "a task in words",                        "--for=\"add retry to the http client\"" },
    { "--lego=",        &Config::legoType        , EmptyValue::Refuse, "an interface or base-type name",         "--lego=Shape" },
    { "--exemplar=",    &Config::exemplar        , EmptyValue::Refuse, "what you are about to write",            "--exemplar=\"a JSON writer\"" },
    { "--recall=",      &Config::recall          , EmptyValue::Refuse, "a task in words",                        "--recall=\"how does the cache key work\"" },

    // neighborhood + call graph
    { "--around=",      &Config::around          , EmptyValue::Refuse, "a symbol name",                          "--around=parseArgs" },
    { "--callers=",     &Config::callers         , EmptyValue::Refuse, "a symbol name",                          "--callers=parseArgs" },
    { "--callees=",     &Config::callees         , EmptyValue::Refuse, "a symbol name",                          "--callees=parseArgs" },
    { "--uses=",        &Config::usesSym         , EmptyValue::Refuse, "a symbol name",                          "--uses=parseArgs" },
    { "--graph-query=", &Config::graphQuery      , EmptyValue::Refuse, "a graph-query expression",               "--graph-query='callers(parseArgs)'" },

    // skills, batch, cross-branch
    { "--scan-skill=",  &Config::scanSkillFile   , EmptyValue::Refuse, "a skill file path (any file, not just .md)", "--scan-skill=skills/ripwire-orient/SKILL.md" },
    { "--batch=",       &Config::batchFile       , EmptyValue::Refuse, "a batch file path, or - for stdin",      "--batch=queries.txt" },
    { "--edit-check=",  &Config::editCheckSym    , EmptyValue::Refuse, "a symbol name (file:name disambiguates)", "--edit-check=parseArgs" },
    { "--safe-delete=", &Config::safeDeleteSym   , EmptyValue::Refuse, "a symbol name (file:name disambiguates)", "--safe-delete=parseArgs" },
    { "--replace-symbol-body=", &Config::replaceSymbolBody, EmptyValue::Refuse, "a symbol name", "--replace-symbol-body=parseArgs" },
    { "--insert-before-symbol=", &Config::insertBeforeSymbol, EmptyValue::Refuse, "a symbol name", "--insert-before-symbol=parseArgs" },
    { "--insert-after-symbol=",  &Config::insertAfterSymbol,  EmptyValue::Refuse, "a symbol name", "--insert-after-symbol=parseArgs" },
    { "--edit-payload=",         &Config::editPayload,        EmptyValue::Refuse, "a payload file path, or - for stdin", "--edit-payload=replacement.cpp" },
    { "--edit-target-file=",     &Config::editTargetFile,     EmptyValue::Refuse, "a target file-path substring", "--edit-target-file=src/cli.h" },
    { "--eval-stray=",  &Config::evalStray       , EmptyValue::Refuse, "a labelled TSV file path",               "--eval-stray=bench/strayverdicts.tsv" },
    { "--from-trace=",  &Config::fromTrace       , EmptyValue::Refuse, "a trace file path, or - for stdin",      "--from-trace=crash.txt" },
    { "--run-trace=",   &Config::runTrace        , EmptyValue::Refuse, "a shell command line to execute",        "--run-trace=\"make -j\"" },
    { "--with-profile=",&Config::withProfile     , EmptyValue::Refuse, "a profile report holding a #PROF_TSV block", "--with-profile=report.txt" },

    // the lane plan's two inputs (each refused alone by validateConfig)
    { "--task=",        &Config::laneTask        , EmptyValue::Refuse, "a goal in words",                        "--task=\"add a --since filter\"" },
    { "--brief=",       &Config::laneBrief       , EmptyValue::Refuse, "a brief file path",                      "--brief=lanes_brief.txt" },

    // ── §B5: the 23 arms that used to be hand-written in parseArgs ──────────────────────────────────────
    // Each was exactly "assign one member (+ set one or two companion bools)", which this table can express
    // once it has the isSetFlag columns. Grouped and ordered as they stood in the chain so a reviewer can
    // diff the move; the ONLY behaviour that changes is the four §B5 rows marked below.
    //
    // Prefix-collision check, done once so it need not be redone per row: no row's prefix is a prefix of
    // another's (`--scan-skill=` vs `--scan-skills=` differ at the byte after "--scan-skill", so neither
    // matches the other), and the exact-match kBoolFlags scan runs FIRST, so every bare `--owners` /
    // `--whereis` / `--flags` / `--situ` / `--html` / ... still lands on its bool row exactly as before.

    // §B5 FIX - a network TRANSPORT selector. `--listen=` (a $PORT that expanded to nothing) used to become
    // a live stdio MCP server at exit 0, answering a full tools/call on stdout; `--listen=notaspec` refuses
    // loudly one keystroke away. Also sets c.mcp: --listen implies --mcp.
    { "--listen=",         &Config::listen          , EmptyValue::Refuse, "HOST:PORT, or a bare PORT for loopback",           "--listen=127.0.0.1:8765",
      &Config::mcp },
    // §B5 FIX - was byte-identical to bare `--owners`, while `--owners=` reads as "restrict to SYM" and SYM
    // is missing. The bare form is the kBoolFlags row and stays the way to ask for the whole report.
    { "--owners=",         &Config::ownersSym       , EmptyValue::Refuse, "a symbol name (restricts the report to its file)", "--owners=parseArgs",
      &Config::owners },
    // §B5 FIX - was byte-identical to the DEFAULT MAP: a caller asked which findings to ack and got an atlas.
    // `--ack-only=gating` alone already exits 1, so the empty form was the only unguarded spelling.
    { "--ack-only=",       &Config::qualityAckOnly  , EmptyValue::Refuse, "one or more kind/id substrings, comma-separated",  "--ack-only=complexity" },
    // --regex= sets the pattern AND the regex-mode bool; it already called refuseEmptyValue directly and the
    // table prints the SAME sentence, so this row is byte-identical to the arm it replaces.
    { "--regex=",          &Config::grep            , EmptyValue::Refuse, "a regular expression",                             "--regex='parse[A-Z]'",
      &Config::grepRegex, nullptr, &Config::grepGiven, kGrepDupMessage },

    // the bare-or-filter forms: "" is a REAL value here - `--situ=` means exactly `--situ`, and the value is
    // an OPTIONAL narrowing filter. Recorded rather than silently accepted (that distinction is the column).
    { "--cochange=",       &Config::cochangeFile    , EmptyValue::Meaningful, nullptr, nullptr, &Config::cochange },
    { "--situ=",           &Config::situFiles       , EmptyValue::Meaningful, nullptr, nullptr, &Config::situ },
    // `--test-gate=` left the Meaningful block above on 2026-08-24: "" ≡ the bare git-diff form meant an
    // unset shell variable silently gated a DIFFERENT question, on a verb whose exit code gates a merge —
    // the same ruling --dmm=/--quality-delta= below carry for their half-typed ranges. (The unparseable-
    // FILES refusal itself is per-item, in main's --test-gate arm; gate: testgaterefusecheck.sh.)
    { "--test-gate=",      &Config::testGateFiles   , EmptyValue::Refuse, "changed files, F1,F2", "--test-gate=src/cli.h", &Config::testGate },
    { "--scan-skills=",    &Config::scanSkillsDir   , EmptyValue::Meaningful, nullptr, nullptr, &Config::scanSkills },
    { "--dead-code=",      &Config::deadCodeDir     , EmptyValue::Meaningful, nullptr, nullptr, &Config::deadCode },
    { "--pr-context=",     &Config::prContextBase   , EmptyValue::Meaningful, nullptr, nullptr, &Config::prContext },
    { "--stray-content=",  &Config::strayFilter     , EmptyValue::Meaningful, nullptr, nullptr, &Config::strayContent },
    { "--flags=",          &Config::darkFlagsFilter , EmptyValue::Meaningful, nullptr, nullptr, &Config::darkFlags },
    { "--doc-drift=",      &Config::docDriftFilter  , EmptyValue::Meaningful, nullptr, nullptr, &Config::docDrift },
    // `--field-affinity=` is exactly `--field-affinity`: the value is an OPTIONAL narrowing to one struct,
    // and the bare form (the whole-repo ranking) is the primary way to ask.
    { "--field-affinity=", &Config::fieldAffinityStruct, EmptyValue::Meaningful, nullptr, nullptr, &Config::fieldAffinity },
    // --dmm= is Refuse, not Meaningful, even though the BARE --dmm is a real form: `--dmm=` is a half-typed
    // range, and silently running the working-tree comparison for it would answer a question nobody asked.
    { "--dmm=",            &Config::dmmRange, EmptyValue::Refuse, "a commit, or a RANGE A..B (bare --dmm compares the working tree against HEAD)",
      "--dmm=HEAD~1..HEAD", &Config::dmm },
    // R-I: `--quality-delta=` is Refuse for the SAME reason `--dmm=` is — the value is a half-typed range,
    // and silently running the working-tree-vs-baseline comparison for it would answer a question nobody
    // asked, on a verb whose exit code gates a merge. Declared AFTER `--quality-panel=` would be harmless
    // (no shared prefix) but it sits beside --dmm= because the two rows carry the identical grammar.
    { "--quality-delta=",  &Config::qualityDeltaRange, EmptyValue::Refuse,
      "a commit, or a RANGE A..B of git refs (bare --quality-delta compares the working tree against the baseline)",
      "--quality-delta=HEAD~1..HEAD", &Config::qualityDelta },
    // `--quality-panel=` is exactly `--quality-panel`: the value is an OPTIONAL preset selection and the bare
    // form is the `default` preset. An UNKNOWN value is refused in validateModifierGuards with the supported
    // list — falling back to a preset the caller did not name would be a silently different report.
    { "--quality-panel=",  &Config::qualityPanelPreset , EmptyValue::Meaningful, nullptr, nullptr, &Config::qualityPanel },
    // --html=FILE-or-stdout and --quality-ack=REASON are the same shape for a different reason: the value is
    // OPTIONAL, so `--html=` is `--html` (write to stdout) and `--quality-ack=` is `--quality-ack` (no
    // reason). The audit's own enumeration classified both as "already refusing"; neither is. They are
    // correct-by-design, which is exactly what this column exists to say out loud.
    { "--html=",           &Config::htmlFile        , EmptyValue::Meaningful, nullptr, nullptr, &Config::html },
    { "--quality-ack=",    &Config::qualityAckReason, EmptyValue::Meaningful, nullptr, nullptr, &Config::qualityAck, &Config::qualityDelta },

    // the handler refuses an empty value with its own verb-specific sentence - byte-identical to before the
    // move, because the row does NOT refuse here. Each names the refusing site so a reader can check it.
    { "--merge-scout=",    &Config::mergeScout      , EmptyValue::HandlerRefuses, nullptr, nullptr, &Config::mergeScoutFlag },   // "--merge-scout needs REF[,REF...]"
    { "--whereis=",        &Config::whereis         , EmptyValue::HandlerRefuses, nullptr, nullptr, &Config::whereisFlag },      // "--whereis needs a symbol"
    { "--exercises=",      &Config::exercisesFile   , EmptyValue::HandlerRefuses, nullptr, nullptr, &Config::exercisesFlag },    // "--exercises needs a test file"
    { "--community=",      &Config::communityId     , EmptyValue::HandlerRefuses, nullptr, nullptr, &Config::communityFlag },    // "--community needs a module ID"
    { "--flip=",           &Config::flipGate        , EmptyValue::HandlerRefuses, nullptr, nullptr, &Config::flipFlag },         // validateConfig + the --flags handler
    { "--layout=",         &Config::layoutStruct    , EmptyValue::HandlerRefuses, nullptr, nullptr, &Config::layoutFlag },       // "--layout needs a struct/class name"
    { "--note-add=",       &Config::noteAdd         , EmptyValue::HandlerRefuses, nullptr, nullptr, &Config::noteAddFlag },      // "--note-add: want \"TARGET: text\""
    { "--pack-task=",      &Config::packTask        , EmptyValue::HandlerRefuses, nullptr, nullptr, &Config::packTaskFlag },     // "--pack-task: a task string is required"
};

// §B5 - the column above is only a decision if the build enforces it. `needs`/`example` are the Refuse
// sentence's two halves: a Refuse row without them would print "it needs (null)", and a Meaningful or
// HandlerRefuses row that carries them is a row whose author wrote a refusal the scan will never print -
// both are the "declared one thing, does another" shape this table exists to make impossible.
consteval bool viewFlagEmptyPolicyIsWellFormed() noexcept
{
    for( const ViewFlag& vf : kViewFlags )
    {
        const bool hasSentence = vf.needs != nullptr && vf.example != nullptr;
        if( ( vf.onEmpty == EmptyValue::Refuse ) != hasSentence )
        {
            return false;
        }
        if( ( vf.needs == nullptr ) != ( vf.example == nullptr ) )
        {
            return false; // never half a sentence
        }
    }
    return true;
}

static_assert( viewFlagEmptyPolicyIsWellFormed(),
               "a kViewFlags row's EmptyValue does not match its needs=/example= columns - EmptyValue::Refuse "
               "needs both (they ARE the refusal sentence); Meaningful and HandlerRefuses must carry neither, "
               "or the row claims a refusal applyViewFlag will never print" );

// §B8.2 — the NUMERIC arms, as the third table. `--x=N` is the surface's other repeated shape and it was
// still nine hand-written `if` arms, which is exactly how those nine ended up with a refusal DIALECT of
// their own: one fixed sentence per flag, printed for every bad value, with neither the offending value
// nor an example in it. `--zoom=` and `--zoom=zzq` produced BYTE-IDENTICAL stderr, so a caller whose
// $DEPTH expanded to nothing could not tell an unset variable from a typo — while --limit/--offset (one
// function away) and the compliant kViewFlags rows both echo the value and show what to type.
//
// The columns are the whole refusal: `wanted` is the DOMAIN in the refusal's voice, `example` is runnable
// and inside that domain, and `most` is the domain's ceiling. A new numeric flag now inherits the shared
// sentence by filling those in, the same way a new value-taking flag inherits the empty-value refusal.
//
// `most` matters for exactly one row today (§B8.1: --connect-radius' 1..12 band); everything else sits at
// kIntFlagMax, which is parsePosInt's own ceiling restated, so `v > most` is unreachable there and the
// accepted set is bit-for-bit what it was. The parse itself is still parsePosInt/parseNonNegInt — this
// table changed which SENTENCE a rejected value gets, never which values are rejected.
inline constexpr int kIntFlagMax        = 1000000000;    // parsePosInt/parseNonNegInt's own overflow ceiling
inline constexpr int kConnectRadiusMax  = 12;            // == connectcfg::kMaxRadius (static_assert at the seam in main.cpp)

struct IntFlag
{
    std::string_view prefix;
    int Config::*    member;
    bool             isZeroAllowed;                 // 0 is IN the domain (--top-k=0 = payload only, --detail=0 = off)
    int              most;                          // domain ceiling — refused, not clamped (§B8.1)
    const char*      wanted;                        // the domain, worded for the refusal
    const char*      example;                       // runnable, and inside the domain
    const char*      deprecation = nullptr;         // printed on ACCEPT (the flag still works, it is on the way out)
    int  Config::*   memberAlso  = nullptr;         // --grep-context= sets the before AND after windows
    bool Config::*   isSetFlag   = nullptr;         // companion bool: --zoom= selects the verb, --top-k= records explicitness
};

inline constexpr IntFlag kIntFlags[] =
{
    // graph shaping
    { "--zoom=",             &Config::zoomDepth,     false, kIntFlagMax,       "a positive integer depth",   "--zoom=2",
      nullptr, nullptr, &Config::zoom },
    { "--connect-radius=",   &Config::connectRadius, false, kConnectRadiusMax, "an integer in 1..12",        "--connect-radius=6" },

    // budgets + the ranked head
    { "--max-tokens=",       &Config::maxTokens,     false, kIntFlagMax,       "a positive integer",         "--max-tokens=16000" },
    // r27-emitters T2: --top-k=0 means "emit NO ranked map, only the explicitly requested payload"
    // (--expand/--outline/--pack-signatures/--pack-top-n). It used to be refused outright, so a caller
    // asking for one 1.4 KB body had no way to drop the 22 KB ride-along map and `--top-k=0 --expand=X`
    // produced ZERO bytes — the requested body vanished with it. isZeroAllowed is that decision; `--top-k=`
    // (empty) is still rejected, so the old "silently becomes 0 = emit ALL symbols" trap stays closed.
    { "--top-k=",            &Config::topK,          true,  kIntFlagMax,       "a non-negative integer (0 = suppress the ranked map, payload only)", "--top-k=200",
      nullptr, nullptr, &Config::topKExplicit },
    { "--pack-top-n=",       &Config::packTopN,      false, kIntFlagMax,       "a positive integer",         "--pack-top-n=10",
      "ripwire: --pack-top-n is deprecated — use --pack-task/--detail instead (unchanged behavior for now)\n" },
    { "--detail=",           &Config::detail,        true,  kIntFlagMax,       "a non-negative integer (0 = off)", "--detail=2" },
    // --cochange-recur=K: K is a count of SUB-WINDOWS, so it is bounded by kCoRecurSubWindows in practice;
    // the parser accepts any positive integer and the verb reports zero pairs above the ceiling rather than
    // refusing — an empty result under a disclosed min_recur= is a truthful answer, not an error.
    { "--cochange-recur=",   &Config::cochangeRecur, false, kIntFlagMax,       "a positive integer",         "--cochange-recur=2" },

    // the grep context windows (ripgrep -B/-A/-C)
    { "--grep-before=",      &Config::grepBefore,    true,  kIntFlagMax,       "a non-negative integer",     "--grep-before=3" },
    { "--grep-after=",       &Config::grepAfter,     true,  kIntFlagMax,       "a non-negative integer",     "--grep-after=3" },
    { "--grep-context=",     &Config::grepBefore,    true,  kIntFlagMax,       "a non-negative integer",     "--grep-context=3",
      nullptr, &Config::grepAfter },

    // §B8.2 verifier finding N4 (W2FIX-CLI) — the ego graph and the pack-task fan-out/lane-plan forms.
    // parsePosInt underneath (not parseNonNegInt), same as the rest of this table; `most` stays kIntFlagMax
    // for --partition/--plan-lanes because their real 2..16 band is a CROSS-FLAG contract (needs --pack-task
    // / --task first) enforced in validateConfig with its own message, not a parse-time domain.
    { "--around-depth=",     &Config::aroundDepth,     false, kIntFlagMax,     "a positive integer",         "--around-depth=3" },
    { "--around-fanout=",    &Config::aroundFanout,    false, kIntFlagMax,     "a positive integer",         "--around-fanout=50" },
    // --partition=N: the fan-out form of --pack-task (2..16 agents; range checked in validateConfig)
    { "--partition=",        &Config::partitionCount,  false, kIntFlagMax,     "a positive integer",         "--partition=4" },
    // sets TWO members: the count here AND the companion bool (the bare `--plan-lanes` --brief form is the
    // kBoolFlags row above); 2..16 is enforced in validateConfig alongside the task-xor-brief contract.
    { "--plan-lanes=",       &Config::planLaneCount,   false, kIntFlagMax,     "a positive integer",         "--plan-lanes=3",
      nullptr, nullptr, &Config::planLanesFlag },
    // VT-1: --run-trace's command cap in SECONDS (default 600 when unset; the cross-flag "modifies
    // --run-trace only" contract is validateConfig's, not a parse-time domain — same split as --partition).
    { "--run-timeout=",      &Config::runTimeoutSec,   false, kIntFlagMax,     "a positive integer (seconds)", "--run-timeout=60" },
};

// Tripwire (house style): the `--` surface is 149 arms. Adding or removing one must move exactly one of
// these counters, so a new flag cannot land without a reader deciding — and recording — which shape it
// is. kHandWrittenFlagArms counts the arms still spelled out in parseArgs: value-parsing, multi-member,
// deprecation-warning and nested-value arms, none of which a table can express honestly.
// W2FIX-CLI (§B8.2 finding N4): 44 → 40 — --around-depth=/--around-fanout=/--partition=/--plan-lanes=
// moved from hand-written arms into kIntFlags rows (4 fewer hand, 4 more table; kTotalFlagArms unchanged).
//
// §B5 (capture-audit-4): 40 → 17. The four un-swept arms were the SYMPTOM; the 40-arm surface outside the
// table was the disease, so 23 of them became kViewFlags rows (33 → 56) once that table grew the EmptyValue
// and isSetFlag columns. kTotalFlagArms is unchanged, which is exactly what this tripwire is for: a move is
// a move, and it must not look like an addition. What is LEFT is the honest residue, and each kind is here
// because a table row could not hold it without lying:
//   • a VECTOR member          --exclude= (push_back), --expand= / --outline= (comma-split into vector)
//   • a PARSE, not an assign   --token-budget= / --max-file-size= / --pack-budget-bytes= (byte sizes into a
//                              size_t/u64), --limit= / --offset= (their own out-of-range sentence)
//   • an ENUM value            --order= / --rank-by= / --color-by= / --format= / --export= (a value SET,
//                              and a refusal that must list it)
//   • a WARNING on accept      --most-important-last / --stable / --no-auto-order (deprecated aliases that
//                              warn once per RUN, not per flag — state a BoolFlag row has nowhere to keep)
//   • a bare no-op / bare pair --route, --quality-ack (the =REASON form is a kViewFlags row)
inline constexpr std::size_t kHandWrittenFlagArms = 22;   // +1: --color-by= (enum-value arm); +3 G3 (2026-08-15 harvest): --and=/--not=/--grep-scope= (repeatable-value arms, same shape as --exclude=); +1 R-H: --grep-in= (closed-value arm, same shape as --grep-scope=)
inline constexpr std::size_t kTotalFlagArms = 193;  // +5 CLI edit bridge; +1 grep handles; +1 legend posture
static_assert( std::size( kBoolFlags ) + std::size( kViewFlags ) + std::size( kIntFlags ) + kHandWrittenFlagArms == kTotalFlagArms,
               "a --flag arm was added or removed without updating the ledger above — count the arms in parseArgs and fix the counter" );

// ── the kViewFlags scan, as its own function ────────────────────────────────────────────────────────
// Three outcomes, named rather than encoded as a bool-plus-side-effect: the argv element is not a view
// flag at all; it is one and its value was assigned; or it is one whose value is EMPTY and was refused
// (§A9 V1-4). Lifted out of parseArgs because it is a LOOP WITH AN EARLY BAILOUT inside the argv loop
// inside the "--" guard — three nesting levels the caller does not otherwise need — and because "which
// flag matched, and did its value survive" is one question with one answer.
enum class ViewFlagMatch : std::uint8_t { NoMatch, Assigned, Refused };

inline ViewFlagMatch applyViewFlag( std::string_view arg, Config& c )
{
    for( const ViewFlag& vf : kViewFlags )
    {
        if( !startsWith( arg, vf.prefix ) )
        {
            continue;
        }
        const std::string_view value = arg.substr( vf.prefix.size() );
        // §B5: the EMPTY-value decision is the row's, never this loop's. Refuse prints here; Meaningful and
        // HandlerRefuses both fall through to the assignment — the difference between them is which code
        // OWNS the refusal, and the row records it (the consteval floor beside the table pins the columns).
        if( value.empty() && vf.onEmpty == EmptyValue::Refuse )
        { refuseEmptyValue( vf.prefix, vf.needs, vf.example );  return ViewFlagMatch::Refused; }

        // G1/F1: a repeat of a flag that silently overwrote its own prior value — checked BEFORE the
        // assignment so the first value is never clobbered on the way to refusing.
        if( vf.dupGuardFlag != nullptr && c.*vf.dupGuardFlag )
        {
            std::fprintf( stderr, "ripwire: %s\n", vf.dupMessage );
            return ViewFlagMatch::Refused;
        }

        c.*vf.member = value;
        // §B5: the companion bools the migrated arms used to set by hand — `--owners=SYM` selects the verb
        // AND narrows it, and a table that could only assign the value would have had to leave those 23 arms
        // outside it. Mirrors kIntFlags' isSetFlag column exactly.
        if( vf.isSetFlag != nullptr )
        {
            c.*vf.isSetFlag = true;
        }
        if( vf.isSetFlagAlso != nullptr )
        {
            c.*vf.isSetFlagAlso = true;
        }
        if( vf.dupGuardFlag != nullptr )
        {
            c.*vf.dupGuardFlag = true;
        }
        return ViewFlagMatch::Assigned;
    }
    return ViewFlagMatch::NoMatch;
}

// ── the kIntFlags scan ──────────────────────────────────────────────────────────────────────────────
// Same three outcomes and the same shape as applyViewFlag, for the same reason: one loop, one early
// bailout, one answer. `arg` is an argv element, so the value tail is NUL-terminated and the existing
// parse helpers apply to it unchanged — the domain ceiling is checked on TOP of the parse rather than
// inside it, because a value outside the band is refused (§B8.1), never clamped.
enum class IntFlagMatch : std::uint8_t { NoMatch, Assigned, Refused };

inline IntFlagMatch applyIntFlag( std::string_view arg, Config& c )
{
    for( const IntFlag& f : kIntFlags )
    {
        if( !startsWith( arg, f.prefix ) )
        {
            continue;
        }

        const char* value   = arg.data() + f.prefix.size();
        int         parsed  = 0;
        const bool  isValid = ( f.isZeroAllowed ? parseNonNegInt( value, parsed ) : parsePosInt( value, parsed ) ) && parsed <= f.most;
        if( !isValid )
        {
            // one sentence for empty, garbage and out-of-range alike: they differ only in the echoed value,
            // which is the difference the caller actually needs to see
            const std::string_view bare = f.prefix.substr( 0, f.prefix.size() - 1 );
            char                   flag[ 32 ] = {};
            std::snprintf( flag, sizeof( flag ), "%.*s", int( bare.size() ), bare.data() );
            refuseFlagValue( flag, f.wanted, value, f.example );
            return IntFlagMatch::Refused;
        }

        c.*f.member = parsed;
        if( f.memberAlso != nullptr )
        {
            c.*f.memberAlso = parsed;
        }
        if( f.isSetFlag != nullptr )
        {
            c.*f.isSetFlag = true;
        }
        if( f.deprecation != nullptr )
        {
            std::fprintf( stderr, "%s", f.deprecation );
        }
        return IntFlagMatch::Assigned;
    }
    return IntFlagMatch::NoMatch;
}

// ── validateConfig — the cross-flag contract, checked once the argv loop has closed ─────────────────
// 20 combination guards, split out of parseArgs so the FLAG SURFACE (what each literal sets) and the
// CONTRACT (which combinations are meaningful) read separately. Reads only `c`, writes only `c.ok` and
// stderr; it runs after every arm has had its say, so a guard may assume the whole argv has been seen.
//
// What deliberately did NOT move: the DEFAULTS. `--mcp` implying `--stable` sat inside this block and is
// not a validation — it is a value the parser supplies when the user did not. It stays in parseArgs above
// the call. A default carried across this boundary would still compile, still exit 0, and quietly change
// output ordering, which is why the boundary is named rather than assumed (test/guardmsgcheck.sh pins
// both sides: each guard by its own message, and the --mcp/--stable default by the bytes it changes).
// --plan-lanes takes its lanes from EXACTLY ONE of two sources. Six guards, split out
// of validateConfig rather than appended to it — that function is already the 20-guard combination contract
// and one verb owning a third of a seventh of it belongs in its own body. The refusals are the --partition
// class: a companion flag that alone would silently no-op on the default map. `--task`/`--brief` are inputs
// to this verb and to nothing else, so each is refused alone; the two are refused TOGETHER because "which
// source won?" has no defensible default, and a plan carved from the wrong one looks exactly like a plan
// carved from the right one. N is a count of worktrees: 1 is not a fan-out and past 16 an orchestrator is
// doing something else (the same 2..16 --partition and the multi-root workspace use); in --brief mode it is
// the file's non-blank line count instead, so a count on the command line there is the contradiction it says.
inline void validatePlanLanes( Config& c ) noexcept
{
    if( !c.laneTask.empty() && !c.planLanesFlag )
    {
        std::fprintf( stderr, "ripwire: --task=GOAL is the input to --plan-lanes=N — pass both (e.g. ripwire <dir> --plan-lanes=3 --task=\"the goal\")\n" );
        c.ok = false;
    }
    if( !c.laneBrief.empty() && !c.planLanesFlag )
    {
        std::fprintf( stderr, "ripwire: --brief=FILE is the input to --plan-lanes — pass both (e.g. ripwire <dir> --plan-lanes --brief=tasks.md)\n" );
        c.ok = false;
    }
    if( !c.planLanesFlag )
    {
        return; // nothing below is meaningful without the verb itself
    }

    if( c.laneTask.empty() && c.laneBrief.empty() )
    {
        std::fprintf( stderr, "ripwire: --plan-lanes needs a task to split — pass --plan-lanes=N --task=\"the goal\" (auto-carve), "
                              "or --plan-lanes --brief=FILE with one non-blank line per lane\n" );
        c.ok = false;
    }
    if( !c.laneTask.empty() && !c.laneBrief.empty() )
    {
        std::fprintf( stderr, "ripwire: --plan-lanes takes --task=GOAL or --brief=FILE, never both — the lanes would come from two "
                              "different carves and only one of them is the one you meant\n" );
        c.ok = false;
    }
    if( !c.laneTask.empty() && ( c.planLaneCount < 2 || c.planLaneCount > 16 ) )
    {
        std::fprintf( stderr, "ripwire: --plan-lanes=%d is out of range — N must be 2..16 (1 is not a fan-out)\n", c.planLaneCount );
        c.ok = false;
    }
    if( !c.laneBrief.empty() && c.planLaneCount > 0 )
    {
        std::fprintf( stderr, "ripwire: --plan-lanes=%d with --brief=FILE is a contradiction — in brief mode the lane count IS the "
                              "file's non-blank line count; drop the =N\n", c.planLaneCount );
        c.ok = false;
    }
}

// §P8 — the eleven "(with X)" modifiers the sweep found accepted-and-
// silently-ignored, split out of validateConfig for the SAME reason validatePlanLanes above is split out:
// one theme owning a chunk of the guard chain belongs in its own body, not appended to the 20-guard
// combination contract function. Also keeps these new guards from inflating validateConfig's own complexity/
// verbosity numbers against its pre-existing baseline (--quality-delta measures per-symbol, and a new
// function is a new-symbol, never a regression of an old one) — the SAME reasoning every future batch of
// guards should follow: land them in a themed helper, not by growing validateConfig line by line forever.
// §P8/G2 — the TWENTY-FIVE verbs that actually window their rows for --limit/--offset, in ONE place, adjacent
// to the guard that reads it and to the message that prints it. Keeping the list, the predicate and the
// refusal text together is the whole point: the previous failure mode was a --help paragraph naming a set
// that the code had already outgrown in both directions, with nothing to make the two disagree loudly.
//
// Membership is a fact about the EMITTER, not a preference: a verb is in this set iff its serializer runs the
// row list through pageview.h's pageWindow(). test/pagingsweepcheck.sh (K) proves the set both ways — every
// name here exits 0 under --limit=3, and a sample of the outside refuses.
//
// §P15/§P16 residual + §P16 follow-up: seven more verbs gained a real deterministic row model and joined —
// --seams (the seam-PAIR listing), --zoom (the top-level module listing; --zoom --mermaid stays a fixed-shape
// diagram, excluded below the same way plain --mermaid is), --external-surface (the referenced-name listing),
// --dead-code (the candidate listing), --mentions (the doc-hit listing), --graph-query (the ranked result
// set — --limit now overrides its --top-k display cap the same way it overrides --pack-top-n elsewhere), and
// --stray-content (the per-ref listing; row order verified byte-stable across repeated runs before migrating
// — a cross-branch git verb pages only once its ordering is proven deterministic, not assumed; its two
// companion sub-verbs, --plan and --abi, route to landingplan::writePlan / abicheck::writeAbiCheck, neither
// of which windows anything, so honorsPaging() excludes both the same way it excludes --zoom --mermaid).
// --metrics stays refusing: it is a DECORATOR on the default map's own top-k/--max-tokens-bounded row set,
// not an independent row list of its own — the same budget/top-k reasoning that keeps --for/--expand refusing.
// §A3a: --test-gate joins here too — its <u> untested-row list was a bare
// 25-row literal cap (situ.h kMaxUntestedRows) with no shown=/capped= and a refusal on --limit that FALSELY
// claimed "no page to walk" (there were 41 more rows). It now windows through pageview.h like every verb
// above, so it belongs in the honoring set, not the refusing one.
constexpr const char* kPagingHonoringVerbs =
    "--lint --hotspots --callers --callees --tree --deps --cochange --owners --clones --doc-drift "
    "--communities --community --whereis --grep/--regex --match --pattern --impact --uses --exercises "
    "--seams --zoom --external-surface --dead-code --mentions --graph-query --stray-content --test-gate "
    "--readability --ensemble --quality-panel --context-ratio --nonlocal-state --comment-coherence "
    "--naming-consistency --safe-delete";

inline bool honorsPaging( const Config& c ) noexcept
{
    return c.lint || !c.lintRulesDir.empty() || c.hotspots || !c.callers.empty() || !c.callees.empty()
        || c.tree || c.deps || c.cochange || c.owners || c.clones || c.docDrift || c.communities
        || c.whereisFlag || !c.grep.empty() || !c.match.empty() || !c.pattern.empty() || !c.impactSym.empty() || !c.usesSym.empty()
        || c.exercisesFlag || c.communityFlag
        || c.seams || ( c.zoom && !c.mermaid ) || c.externalSurface || c.deadCode || !c.mentionsSym.empty()
        || !c.graphQuery.empty() || ( c.strayContent && !c.landingPlan && !c.abiFlag ) || c.testGate
        || c.readability || c.ensemble || c.qualityPanel || c.contextRatio || c.nonlocalState || c.commentCoherence
        || c.namingConsistency || !c.safeDeleteSym.empty();
}

// --limit/--offset on a verb that windows NOTHING. Same accept-then-silently-ignore class as every guard in
// validateModifierGuards below, and by far the largest instance of it: the default map and ~15 report verbs
// took both flags and emitted byte-identical output, so a caller could not tell a no-op from a typo, and a
// paging loop written against one of them spun forever. Paginating all of them was rejected — most emit a
// small FIXED report where a page has no meaning — so the honest move is to refuse.
//
// The message names BOTH remedies because the two wrong calls have different right answers: on the default
// map the row count is bounded by --top-k (the ranked head) and --max-tokens, not by --limit; on a report
// verb there is no remedy at all, only the honoring set to redirect to.
//
// N6 (verifier fold-in, §B2 round): the closing clause used to read "every other verb emits a fixed report
// with no page to walk", which stopped being true the moment --recall started honoring --top-k — the one
// non-honoring verb with a real remedy was being told it had none. It now names that remedy and claims
// only "the rest".
//
// Scoped OFF for --mcp/--listen, matching how that surface WORKS rather than by exception: the server answers
// SUB-QUERIES carrying their own per-request arguments (the MCP verb objects), so a --limit on the outer
// command line modifies no "selected verb" — there isn't one — and refusing it would break a legal
// invocation. Its own function for the reason validateModifierGuards states in its header: a themed guard
// lands in a helper, it does not grow the combination contract line by line forever.
//
// §A5a: --batch used to be exempt on that same "sub-queries own their arguments" reasoning, but the exemption
// did not do what the reasoning implies — a --limit on the outer command line reached NO sub-query, so
// `--batch=F --limit=2` exited 0 with the payload unchanged. That is precisely the accept-and-ignore class
// §P15.3 declared extinct, and the refusal text three lines below already promised it ("Any verb NOT in that
// list REFUSES both flags"). A batch sub-query that wants a page spells it in the batch FILE, on the line
// that selects the verb; the outer flag has no honest meaning, so it refuses like every other non-honoring
// verb. --mcp keeps its exemption because there the per-request arguments are a real, exercised channel.
// §B11.6 (CA4) — the three MODE flags that turn a paging verb into a fixed report. Without this, the refusal
// hands the reader a honoring list with THEIR OWN VERB in it and no way to reconcile that with being refused:
// `--stray-content --abi --limit=3` is told "--limit/--offset are honored only by: … --stray-content …",
// which reads as a contradiction. The cause is never the base verb; it is the mode, and honorsPaging() already
// encodes exactly these three exclusions — this reads the same conditions so the two cannot drift.
// Returns nullptr when the refusal has no mode cause (the ordinary "this verb pages nothing" case).
inline const char* pagingDisablingMode( const Config& c ) noexcept
{
    if( c.strayContent && c.landingPlan )
    {
        return "--plan";
    }
    if( c.strayContent && c.abiFlag )
    {
        return "--abi";
    }
    if( c.zoom && c.mermaid )
    {
        return "--mermaid";
    }
    return nullptr;
}

inline void validatePagingHonored( Config& c ) noexcept
{
    if( ( c.pageLimit <= 0 && c.pageOffset <= 0 ) || c.mcp || honorsPaging( c ) )
    {
        return;
    }

    // §B11.6: name the MODE first when one is what disabled paging — the honoring list below is otherwise
    // read as self-contradicting, and the remedy ("drop the mode flag") is not derivable from it.
    if( const char* mode = pagingDisablingMode( c ) )
    {
        std::fprintf( stderr, "ripwire: %s turns this run into a fixed report, so --limit/--offset have nothing to "
                              "window — the base verb pages, this mode does not. Drop %s to page it.\n", mode, mode );
    }
    std::fprintf( stderr, "ripwire: --limit/--offset are honored only by: %s. The default map is bounded by --top-k=N "
                          "(or --max-tokens=N) and --recall by --top-k=N, not --limit; the rest emit a fixed report with "
                          "no page to walk\n",
                  kPagingHonoringVerbs );
    c.ok = false;
}

// §A5b — --format=columnar re-serializes a FLAT SYMBOL-ROW listing (a path table + parallel arrays), and only
// four verbs produce one. On any other verb it was accepted and silently ignored: --hotspots/--clones/--lint/
// --tree/--grep --format=columnar all emitted byte-identical XML at exit 0, while its two sibling shape
// modifiers (--json, --format=candidates) both refused with the flag named. Same class, same remedy — name
// the flag, the supported set, and one working example. Its own function for the reason validateModifierGuards
// states in its header: a themed guard lands in a helper, it does not grow validateConfig line by line forever.
//
// §A5c: --pr-context is deliberately NOT in this set. --help and columnar.h both ADVERTISED it and
// prcontext.h contains no columnar code at all (a verified no-op on a dirty tree with 12 changed symbols),
// so the claim was struck from both rather than implemented — this refusal now covers it like any other
// unsupported verb, which is the honest state of the feature.
inline void validateColumnarVerb( Config& c ) noexcept
{
    if( !c.columnar )
    {
        return;
    }
    if( !c.callers.empty() || !c.callees.empty() || !c.usesSym.empty() || !c.impactSym.empty() )
    {
        return;
    }

    std::fprintf( stderr, "ripwire: --format=columnar re-serializes the FLAT symbol-row verbs only — supported: "
                          "--callers/--callees/--uses/--impact (e.g. ripwire <dir> --callers=SYM --format=columnar). "
                          "Every other verb emits a report with no parallel-array row list to re-encode\n" );
    c.ok = false;
}

// §B9 (capture-audit-4, 2026-07-30) — --top-k / --max-tokens on the report/paging family: the exact mirror
// of validatePagingHonored above, same family (honorsPaging IS that family — reused directly rather than
// re-deriving a second list that could drift out of sync with it, the trap-ledger #6 lesson from the ruling
// that produced kPagingHonoringVerbs in the first place), same accept-and-ignore failure, same remedy shape.
//
// Measured from source (every cfg.topK / cfg.maxTokens read site in main.cpp, repo-wide grep confirms no
// other file touches either field): the default map, plain --query, --format=candidates and --recall honor
// --top-k directly; --graph-query is the ONE member of the report/paging family that also shapes its own
// ranked cap with it (kPagingHonoringVerbs' own comment already says so). Nothing else in that family reads
// cfg.topK at all. --max-tokens is honored by the default map, --recall, --connect, --pr-context and
// --from-trace — none of them members of the report/paging family — so no member of that family honors it,
// full stop. --for/--pack-task/--exemplar/--from-trace/--situ are OUTSIDE the report/paging family (they are
// not in honorsPaging, so this guard never fires for them) and --top-k's inertness there is a DIFFERENT,
// already-disclosed residual (--help's own --top-k paragraph; R12) — deliberately not re-litigated here.
inline bool honorsTopK( const Config& c ) noexcept
{
    return !c.graphQuery.empty();
}

// §H4 / V3 M-4 — the THIRD budget flag, and the one the two original guards missed. --token-budget is read in
// exactly six places outside cli.h (runForLens + emitForLensJson, runTargetedViews' --recall arm,
// runFromTrace, runRunTrace, runPackTask, runDefaultMap — re-derivable with `ripwire . --grep=tokenBudget`), none of them
// in the report/paging family. So every member of that family — including four of the five graph-count verbs
// this round disclosed — ACCEPTED it at exit 0 with an empty stderr and emitted the full document, while the
// default map on the same flag refuses with rc=3 and a withheld_est_tokens= body. Accepted-and-ignored is a
// named failure family here, and it was the sharper defect precisely BECAUSE this lane had just claimed the
// byte cost was charged: a caller who set a budget to bound the disclosure got no budget and no word about it.
//
// V4 MED-2 — DEDUPLICATED, not acked. Adding that third guard as its own function made a THREE-body clone
// (two gating duplication findings at 46/50 tokens): the three differed only in which flag selects them, one
// extra exemption, and four spans of message text. The debt was invisible to a bare `--quality-delta` on a
// clean tree, which compares HEAD to itself — it only shows up against an explicit pre-change base, which is
// how it was measured here. Now: ONE table of the four differing spans, ONE emitter, ONE guard.
//
// The message bytes are UNCHANGED by construction — the table splits each sentence at the two points where
// kPagingHonoringVerbs is spliced, so the emitter reassembles exactly what the three fprintf calls printed.
// That is the point of doing it this way rather than "harmonizing" the wording: a refusal string is a
// user-visible contract and argvdiff pins it, so a dedup that also reworded would be two changes wearing one
// commit. The `honoredPre` spans are deliberately long and prose-shaped for the same reason.
struct PagingFamilyFlagGuard
{
    const char* honoredPre;    // the sentence up to and including the "(" that opens the verb list
    const char* honoredPost;   // whatever follows the closing ")" of that list, up to the shared tail
    const char* lacks;         // why THIS flag has nothing to bite on inside the family
    const char* example;       // the runnable --limit=N alternative
};

inline constexpr PagingFamilyFlagGuard kTopKGuard
{
    "--top-k narrows only --graph-query within the --limit/--offset-honoring set (",
    ") — the default map, plain --query, --format=candidates and --recall honor it too, outside that set",
    "nothing ranked to cap",
    "ripwire <dir> --hotspots --limit=3"
};
inline constexpr PagingFamilyFlagGuard kMaxTokensGuard
{
    "--max-tokens is honored by the default map, --recall, --connect, --pr-context, --from-trace and "
    "--for --detail=N — none of them in the --limit/--offset-honoring set (",
    ")",
    "no byte budget to shape",
    "ripwire <dir> --hotspots --limit=3"
};
inline constexpr PagingFamilyFlagGuard kTokenBudgetGuard
{
    "--token-budget is honored by the default map (the CI gate), --for, --pack-task, --recall, "
    "--from-trace and --run-trace — none of them in the --limit/--offset-honoring set (",
    ")",
    "no byte budget to gate",
    "ripwire <dir> --callers=SYM --limit=3"
};

inline void refusePagingFamilyFlag( Config& c, const PagingFamilyFlagGuard& g ) noexcept
{
    std::fprintf( stderr, "ripwire: %s%s%s. The rest of that set emit a fixed report with %s; narrow it with "
                          "--limit=N instead (e.g. %s)\n",
                  g.honoredPre, kPagingHonoringVerbs, g.honoredPost, g.lacks, g.example );
    c.ok = false;
}

// The ONE guard. Evaluation order is top-k, then --max-tokens, then --token-budget, and it is OBSERVABLE:
// a command line setting two of them gets two messages, in this order (`--max-tokens=500 --token-budget=16K`
// is a live argvdiff vector). It is the order the three separate calls ran in, preserved deliberately.
inline void validateShapingFlagsHonored( Config& c ) noexcept
{
    if( c.mcp || !honorsPaging( c ) )
    {
        return;
    }

    if( c.topKExplicit && !honorsTopK( c ) )
    {
        refusePagingFamilyFlag( c, kTopKGuard );
    }
    if( c.maxTokens > 0 )
    {
        refusePagingFamilyFlag( c, kMaxTokensGuard );
    }
    if( c.tokenBudget != 0 )
    {
        refusePagingFamilyFlag( c, kTokenBudgetGuard );
    }
}

// §B9.2 (capture-audit-4, wave 3) — the shaping flags on verbs OUTSIDE the report/paging family.
//
// The two guards above are sound WITHIN honorsPaging (22/22 refuse). The wave-2 verifier then found 14 verbs
// OUTSIDE it that take --top-k / --max-tokens at exit 0 with byte-identical output, 11 of them disclosed
// nowhere at all — so the guard family closed the half it could see and the other half stayed silent.
//
// DERIVED FROM THE READ SITES, not from measurement. `cfg.topK` and `cfg.maxTokens` are read in exactly nine
// and seven places repo-wide, and a verb that never reads the field ignores it for EVERY input — which is the
// distinction the verifier's own false start turned on: its first --connect and --pr-context probes looked
// like ignores and were INERT (a 705-byte subgraph has nothing for a 200-token ceiling to trim). Measurement
// cannot separate those two; the read sites can, and they say --connect/--pr-context/--from-trace DO honour
// --max-tokens. test/shapingflagcheck.sh re-derives the read sites from source on every run and fails if this
// table disagrees with them, so the list cannot rot the way kPagingHonoringVerbs' prose once did.
//
// The answer is a NOTICE, not a refusal, and the two differ on purpose. §P15.3's complaint is that a caller
// "could not tell a no-op from a typo"; one line on stderr answers exactly that, at the moment the mistake is
// made, and better than a --help paragraph nobody re-reads. A refusal would additionally BREAK
// `--for=X --max-tokens=5000`, which is a natural thing to type and has exited 0 for the tool's whole life —
// and R12 already recorded DISCLOSE (not refuse) as the decision for --for/--pack-task/--exemplar + --top-k.
// Nothing here changes an output byte or an exit code.
struct ShapingVerb
{
    std::string_view           name;                    // the spelling the notice prints
    bool Config::*             isSelectedFlag  = nullptr;   // selected by a bool member…
    std::string_view Config::* isSelectedValue = nullptr;   // …or by a non-empty value member (exactly one)
    bool                       honorsTopK      = false;
    bool                       honorsMaxTokens = false;
    bool                       honorsTokenBudget = false;   // §H4/V3 M-4 — the third budget flag, same ledger
};

// Every row here is a verb OUTSIDE honorsPaging that reads NEITHER field, except where a column says
// otherwise. --for is the one shape a flat table cannot state: it ignores --max-tokens bare and HONOURS it
// under --detail=N (main.cpp's detailBodyBudget), so its row claims no honouring and the guard below carves
// that case out by hand, named.
//
// THE THREE-WAY SPLIT, measured on src/ + the repo root and cross-checked against the read sites. INERT is a
// property of the INPUT and never of the verb, which is why it is not a column: a verb that does not read the
// field ignores it on every input, and a verb that does read it can still look unchanged on an input too
// small to trim. Recorded here because the wave-2 verifier got exactly this wrong the first time.
//
//   HONOURS --max-tokens  default map (and everything that rides its serialize path: --query, --metrics,
//                         --map-diff, --expand, --outline, --pack-signatures), --recall, --connect,
//                         --pr-context, --from-trace, --for --detail=N                    [6 shapes]
//   HONOURS --top-k       default map (+ the same riders), --query, --format=candidates, --recall,
//                         --graph-query, and the MCP/batch/--listen pass-throughs
//   IGNORES both          --pack-task, --exemplar, --around, --path, --lego, --report, --edit-check,
//                         --situ, --scan-skills, --merge-scout, and --for for --top-k (R12's residual)
//   IGNORES --top-k only  --connect, --pr-context, --from-trace — the three the verifier first read as
//                         ignoring --max-tokens too. They were INERT on its probes: --connect answered a
//                         705 B subgraph, so a 200-token ceiling had nothing to trim. On a shape where the
//                         budget binds they all shape (--connect 705->586 B, --pr-context 25413->3697 B,
//                         --from-trace 13606->2590 B), and the read sites agree.
//   REFUSES all three     the honorsPaging members (the set above — counting them here is how this comment went stale once already) — validateShapingFlagsHonored, one guard over the
//                         kTopKGuard / kMaxTokensGuard / kTokenBudgetGuard rows.
//
//   HONOURS --token-budget  the default map (the CI gate, runDefaultMap), --for (runForLens +
//                         emitForLensJson), --pack-task (runPackTask), --recall (runTargetedViews) and
//                         --from-trace (runFromTrace). Derived the same way as the other two columns — from
//                         the five read sites outside cli.h, not from measurement. NOTE that --connect and
//                         --pr-context honour --max-tokens but NOT --token-budget: the two flags are not
//                         interchangeable and the columns differ on exactly those two rows, which is the
//                         reason this is a third column rather than an alias of the second.
inline constexpr ShapingVerb kShapingVerbs[] = {
    { "--for",          nullptr, &Config::forTask,      false, false, true },   // --detail=N carve-out below; --top-k: R12 residual
    { "--pack-task",    &Config::packTaskFlag, nullptr, false, false, true },
    { "--exemplar",     nullptr, &Config::exemplar     },
    { "--around",       nullptr, &Config::around       },
    { "--path",         nullptr, &Config::pathSpec     },
    { "--lego",         nullptr, &Config::legoType     },
    { "--report",       &Config::report,       nullptr },
    { "--edit-check",   nullptr, &Config::editCheckSym },
    { "--situ",         &Config::situ,         nullptr },
    { "--handoff",      &Config::handoff,      nullptr, false, false, true },   // writeHandoffPacket takes the budget
    { "--scan-skills",  &Config::scanSkills,   nullptr },
    { "--merge-scout",  &Config::mergeScoutFlag, nullptr },
    { "--connect",      nullptr, &Config::connectSpec,  false, true },   // packConnect takes the budget
    { "--pr-context",   &Config::prContext,    nullptr, false, true },   // writePrContext takes the budget
    { "--from-trace",   nullptr, &Config::fromTrace,    false, true, true },   // FromTraceInputs::bodyBudgetBytes
};

// which row (if any) does this invocation select? First match wins, which mirrors main()'s own dispatch
// order closely enough for a message: on a multi-verb command line an earlier verb takes precedence there
// too, and naming ONE of them is the point (the note is about the flag, not about the verb ordering).
inline const ShapingVerb* selectedShapingVerb( const Config& c ) noexcept
{
    for( const ShapingVerb& v : kShapingVerbs )
    {
        const bool isSelected = v.isSelectedFlag  != nullptr ? c.*v.isSelectedFlag
                              : v.isSelectedValue != nullptr ? !( c.*v.isSelectedValue ).empty()
                                                             : false;
        if( isSelected )
        {
            return &v;
        }
    }
    return nullptr;
}

inline void noticeShapingFlagIgnored( const Config& c ) noexcept
{
    if( c.mcp || honorsPaging( c ) )
    {
        return; // that family REFUSES; two messages would be noise
    }
    if( c.topKExplicit == false && c.maxTokens <= 0 && c.tokenBudget == 0 )
    {
        return;
    }

    const ShapingVerb* const verb = selectedShapingVerb( c );
    if( verb == nullptr )
    {
        return; // the default map (and its riders) honour both
    }

    if( c.topKExplicit && !verb->honorsTopK )
    {
        std::fprintf( stderr, "ripwire: --top-k is not read by %.*s — it shapes the default map, --query, "
                              "--format=candidates, --recall and --graph-query. %.*s emitted its full result "
                              "(nothing was dropped); narrow it with the verb's own arguments instead\n",
                      int( verb->name.size() ), verb->name.data(), int( verb->name.size() ), verb->name.data() );
    }

    // the --detail carve-out: `--for --detail=N` DOES bound its bodies with --max-tokens, so a note there
    // would be false. Stated as a condition rather than a table column because it is the one cross-flag case.
    const bool isForDetailBudget = !c.forTask.empty() && c.detail > 0;
    if( c.maxTokens > 0 && !verb->honorsMaxTokens && !isForDetailBudget )
    {
        std::fprintf( stderr, "ripwire: --max-tokens is not read by %.*s — it shapes the default map, --recall, "
                              "--connect, --pr-context, --from-trace and --for --detail=N. %.*s emitted its full "
                              "result (nothing was dropped)\n",
                      int( verb->name.size() ), verb->name.data(), int( verb->name.size() ), verb->name.data() );
    }

    // §H4 / V3 M-4: the third budget flag reaches the same rows. --edit-check is the graph-count verb this
    // arm actually covers (the other five are inside honorsPaging and REFUSE), and its warn-and-emit is
    // deliberate, not an oversight: the boundary is honorsPaging membership, not the five-verb set, and
    // §B9.2/R12 settled DISCLOSE-not-refuse out here because refusing would break `--for=X --max-tokens=5000`,
    // a shape that has exited 0 for the tool's whole life. Same treatment, same reason.
    if( c.tokenBudget > 0 && !verb->honorsTokenBudget )
    {
        std::fprintf( stderr, "ripwire: --token-budget is not read by %.*s — it gates the default map and bounds "
                              "--for, --pack-task, --recall, --from-trace and --run-trace. %.*s emitted its full result "
                              "(nothing was withheld)\n",
                      int( verb->name.size() ), verb->name.data(), int( verb->name.size() ), verb->name.data() );
    }
}

// --sarif's four companion guards (src/sarif.h serializes --lint's findings as SARIF instead of the
// native XML <lint> block). Split out of validateModifierGuards for the same reason the delegated
// calls at its top are: one flag's own guard cluster stays one small function instead of growing the
// caller's branch count.
inline void validateSarifModifierGuards( Config& c ) noexcept
{
    // Modifies --lint / --lint-rules; alone it would silently no-op exactly like --with-profile above.
    if( c.sarif && !c.lint && c.lintRulesDir.empty() )
    {
        std::fprintf( stderr, "ripwire: --sarif modifies --lint or --lint-rules=DIR — pass one (e.g. ripwire <dir> --lint --sarif)\n" );
        c.ok = false;
    }
    // --match takes an entirely different branch of runLint (its own <match> element, no rule/severity
    // shape at all) and returns before the --lint/--lint-rules findings are even assembled — --sarif
    // would silently never take effect there. Refuse rather than let it look honored.
    if( c.sarif && !c.match.empty() )
    {
        std::fprintf( stderr, "ripwire: --sarif has no effect with --match — it serializes --lint/--lint-rules findings only\n" );
        c.ok = false;
    }
    // R2: --pattern is --match's sibling in exactly the way that matters here — its own <pattern> element,
    // no rule/severity shape, and an early return from runLint before any finding is assembled. The same
    // silent no-op, so the same loud refusal; a pairing that looks honored and is not is the shape this
    // arm exists to prevent, and adding the verb without adding the arm would have reintroduced it.
    if( c.sarif && !c.pattern.empty() )
    {
        std::fprintf( stderr, "ripwire: --sarif has no effect with --pattern — it serializes --lint/--lint-rules findings only\n" );
        c.ok = false;
    }
    // --with-profile's heat_* join has no SARIF field defined yet (the honesty rule: represent it or
    // refuse, never drop it silently) — refuse the pairing rather than silently omit the join.
    if( c.sarif && !c.withProfile.empty() )
    {
        std::fprintf( stderr, "ripwire: --sarif does not yet support --with-profile — the heat_* join has no SARIF field; run them separately\n" );
        c.ok = false;
    }
    // SARIF is meant to be ONE complete document per run (that is what upload-sarif consumes) — a
    // paginated slice would silently under-report to a consumer that has no paging concept. Refuse
    // rather than emit a partial document that looks complete.
    if( c.sarif && ( c.pageLimit > 0 || c.pageOffset > 0 ) )
    {
        std::fprintf( stderr, "ripwire: --sarif always emits the full result set — drop --limit=N/--offset=M\n" );
        c.ok = false;
    }
}

// --lint-select=/--lint-ignore='s ONE companion guard, split out for the same reason
// validateSarifModifierGuards is: a flag's own guard cluster stays one small function instead of
// growing the caller's branch count. The PREFIX list itself (malformed entries, unresolvable prefixes)
// is validated inside runLint, not here — see resolveLintSelection's own header for why.
inline void validateLintSelectionModifierGuards( Config& c ) noexcept
{
    if( !c.lintSelect.empty() && !c.lint && c.lintRulesDir.empty() )
    {
        std::fprintf( stderr, "ripwire: --lint-select=PREFIX modifies --lint or --lint-rules=DIR — pass one (e.g. ripwire <dir> --lint --lint-select=cache-)\n" );
        c.ok = false;
    }
    if( !c.lintIgnore.empty() && !c.lint && c.lintRulesDir.empty() )
    {
        std::fprintf( stderr, "ripwire: --lint-ignore=PREFIX modifies --lint or --lint-rules=DIR — pass one (e.g. ripwire <dir> --lint --lint-ignore=naming-)\n" );
        c.ok = false;
    }
}

static inline void validateLegendModifier( Config& c ) noexcept
{
    if( c.legend.empty() )
    {
        return;
    }
    if( c.legend != "full" && c.legend != "compact" )
    {
        std::fprintf( stderr, "ripwire: --legend needs full or compact — got '%.*s', e.g. --legend=compact\n",
                      int( c.legend.size() ), c.legend.data() );
        c.ok = false;
    }
    if( c.forTask.empty() && c.grep.empty() )
    {
        std::fprintf( stderr, "ripwire: --legend=%.*s is supported by --for, --grep and --regex only — pass one of those verbs\n",
                      int( c.legend.size() ), c.legend.data() );
        c.ok = false;
    }
}

inline void validateModifierGuards( Config& c ) noexcept
{
    validatePagingHonored( c );      // §P8/G2: --limit/--offset on a verb that windows nothing (see its header)
    validateColumnarVerb( c );       // §A5b:   --format=columnar on a verb with no flat row list (see its header)
    validateShapingFlagsHonored( c ); // §B9 + §H4/M-4: --top-k / --max-tokens / --token-budget on a report/
                                      // paging verb that shapes with none of them (one guard, three rows)
    noticeShapingFlagIgnored( c );   // §B9.2:  the same two flags OUTSIDE that family — a NOTICE, never c.ok

    validateLegendModifier( c );

    // --mcp-token/--allow-remote-edits are read ONLY inside the --listen HTTP branch (main.cpp's
    // McpHttpConfig assembly) — the stdio --mcp path never touches either member, so bare `--mcp --mcp-token=…`
    // (no --listen) is exactly as inert as no `--mcp` at all. Refuse loudly rather than let a caller believe
    // they set a token or granted remote-edit access that never reached the server.
    if( !c.mcpToken.empty() && c.listen.empty() )
    {
        std::fprintf( stderr, "ripwire: --mcp-token is read by the --listen HTTP transport only — pass both (e.g. ripwire . --listen=127.0.0.1:8765 --mcp-token=SECRET)\n" );
        c.ok = false;
    }
    if( c.allowRemoteEdits && c.listen.empty() )
    {
        std::fprintf( stderr, "ripwire: --allow-remote-edits is read by the --listen HTTP transport only — pass both (e.g. ripwire . --listen=127.0.0.1:8765 --allow-remote-edits --mcp-token=SECRET)\n" );
        c.ok = false;
    }

    // --force is read ONLY by `ripwire wrap <agent>` (src/wrap.h, its OWN raw-argv scan — main() returns from
    // runWrap before Config/parseArgs even runs). The flag surface still accepts it into Config::force
    // (kBoolFlags), but nothing ever reads that member outside `wrap`, so `ripwire <dir> --force` silently
    // does nothing for any verb. Refuse — this is a different subcommand, not a missing companion flag.
    if( c.force )
    {
        std::fprintf( stderr, "ripwire: --force only applies to `ripwire wrap <agent>` (proceed past CRITICAL skill findings) — "
                              "pass it there instead (e.g. ripwire wrap claude --force)\n" );
        c.ok = false;
    }

    // --run-timeout caps --run-trace's command and reaches nothing anywhere else; alone it would silently
    // no-op exactly like the modifiers around it. Refuse loudly, naming both flags.
    if( c.runTimeoutSec > 0 && c.runTrace.empty() )
    {
        std::fprintf( stderr, "ripwire: --run-timeout=SECONDS modifies --run-trace — pass it too (e.g. ripwire <dir> --run-trace=\"make -j\" --run-timeout=60)\n" );
        c.ok = false;
    }

    // --with-profile joins measured scope heat onto --lint findings and reaches nothing anywhere else;
    // alone it would silently no-op exactly like the modifiers around it. Refuse loudly.
    if( !c.withProfile.empty() && !c.lint )
    {
        std::fprintf( stderr, "ripwire: --with-profile=FILE modifies --lint — pass it too (e.g. ripwire <dir> --lint --with-profile=report.txt)\n" );
        c.ok = false;
    }

    validateSarifModifierGuards( c );          // --sarif's four companion guards, split out for the same reason
                                                // the rows above it are (see its own header)
    validateLintSelectionModifierGuards( c );  // --lint-select=/--lint-ignore='s companion guard, same reason

    // --with-history is the OPT-IN git-history name oracle for --doc-drift and --whereis (src/gitoracle.h) —
    // main.cpp's buildHistoryIndex() is only ever CALLED from those two verbs' dispatch, so the flag alone
    // reaches nothing. Alone it silently no-ops exactly like --anchor/--cochange-boost (validateConfig); refuse loudly.
    if( c.withHistory && !c.docDrift && !c.whereisFlag )
    {
        std::fprintf( stderr, "ripwire: --with-history modifies --doc-drift or --whereis=SYM — pass one (e.g. ripwire <dir> --doc-drift --with-history)\n" );
        c.ok = false;
    }

    // --grep-context=N (and its --grep-before=N/--grep-after=N components — all three set the SAME
    // grepBefore/grepAfter members, see parseArgs) only widens a --grep/--regex hit; alone it silently no-ops
    // (grepHits is only ever called inside the `!cfg.grep.empty()` branch, main.cpp). Refuse loudly.
    if( ( c.grepBefore > 0 || c.grepAfter > 0 ) && c.grep.empty() )
    {
        std::fprintf( stderr, "ripwire: --grep-context=N (or --grep-before/--grep-after) modifies --grep=STR or --regex=PAT — "
                              "pass one (e.g. ripwire <dir> --grep=STR --grep-context=3)\n" );
        c.ok = false;
    }

    // --no-prefilter forces a full scan instead of the trigram prefilter — meaningful ONLY inside the same
    // `!cfg.grep.empty()` branch as --grep-context above. Alone it silently no-ops; refuse loudly.
    if( c.noPrefilter && c.grep.empty() )
    {
        std::fprintf( stderr, "ripwire: --no-prefilter modifies --grep=STR or --regex=PAT — pass one (e.g. ripwire <dir> --grep=STR --no-prefilter)\n" );
        c.ok = false;
    }

    // --handles mints a freshness-pinned symbol target only for an enclosing definition surfaced by grep.
    // Alone it would be an inert promise of an edit target, so refuse rather than silently emit the default map.
    if( c.grepHandles && c.grep.empty() )
    {
        std::fprintf( stderr, "ripwire: --handles modifies --grep=STR or --regex=PAT — pass one too "
                              "(e.g. ripwire <dir> --grep=stale --handles)\n" );
        c.ok = false;
    }

    // G3: --and=/--not=/--grep-scope= modify --grep=STR only — literal, not --regex=PAT (a flat substring
    // term list has no meaning against a regex's own alternation/anchoring, and ugrep's own CNF stays
    // regex-string-only for the same reason). Alone (no --grep) they would silently no-op like the
    // modifiers above; combined with --regex they would silently ignore the extra terms. Both refuse loudly.
    if( ( !c.grepAnd.empty() || !c.grepNot.empty() || !c.grepScope.empty() ) && c.grep.empty() )
    {
        std::fprintf( stderr, "ripwire: --and=/--not=/--grep-scope= modify --grep=STR — pass it too (e.g. ripwire <dir> --grep=stale --and=mcp)\n" );
        c.ok = false;
    }
    // R-H: --grep-in= is the one grep modifier that ALSO applies to --regex (a regex hit lands in a span
    // exactly like a literal one), so its refusal tests both spellings rather than --grep= alone.
    if( !c.grepIn.empty() && c.grep.empty() )
    {
        std::fprintf( stderr, "ripwire: --grep-in=code|any modifies --grep=STR / --regex=PAT — pass one too (e.g. ripwire <dir> --grep=stale --grep-in=any)\n" );
        c.ok = false;
    }
    if( ( !c.grepAnd.empty() || !c.grepNot.empty() ) && c.grepRegex )
    {
        std::fprintf( stderr, "ripwire: --and=/--not= are literal-only and do not apply to --regex=PAT — "
                              "use --grep=STR --and=... instead, or fold the term into the regex itself (e.g. --regex='A.*B')\n" );
        c.ok = false;
    }

    // --with-graph splices a mermaid block into ONE bundle's closing </ctx> — only --for and --pack-task ever
    // call packGraphBlock (main.cpp); --partition already warns-and-continues (N+1 bundles, no single graph to
    // splice into) rather than silently dropping it, so it is excluded here on purpose. Alone (no --for/
    // --pack-task/--partition) it silently no-ops; refuse loudly.
    if( c.withGraph && c.forTask.empty() && !c.packTaskFlag && c.partitionCount <= 0 )
    {
        std::fprintf( stderr, "ripwire: --with-graph modifies --for=TASK or --pack-task=TASK — pass one (e.g. ripwire <dir> --pack-task=\"task\" --with-graph)\n" );
        c.ok = false;
    }

    // --since scopes --hotspots/--cochange/--rank-by=churn|churn-decay to commits after a point; every other
    // verb ignores it outright (main.cpp only reads cfg.since inside those paths). Alone it silently no-ops;
    // refuse loudly. P0-4: churn-decay joins the list — its DEFAULT walk is the whole history (the decay is
    // the window), and an explicit --since narrows that walk exactly as it narrows churn's.
    if( !c.since.empty() && !c.hotspots && !c.cochange && c.rankBy != RankBy::Churn && c.rankBy != RankBy::ChurnDecay )
    {
        std::fprintf( stderr, "ripwire: --since=REV|DATE scopes --hotspots/--cochange/--rank-by=churn|churn-decay — pass one "
                              "(e.g. ripwire <dir> --hotspots --since=\"1 week ago\")\n" );
        c.ok = false;
    }

    // --cochange-recur=K / --cochange-groups are read ONLY inside the --cochange branch of
    // runMaintenanceViews (main.cpp). Alone they silently no-op; refuse loudly, exactly like --since above.
    if( ( c.cochangeRecur > 0 || c.cochangeGroups ) && !c.cochange )
    {
        std::fprintf( stderr, "ripwire: --cochange-recur=K and --cochange-groups modify --cochange — pass it "
                              "(e.g. ripwire <dir> --cochange --cochange-recur=2)\n" );
        c.ok = false;
    }

    // --cochange-groups covers the repo-wide VIOLATING-PAIR set; with --cochange=FILE there is one core file
    // by construction and the group form has nothing to group. Refusing beats emitting a one-file "group"
    // that looks like a finding — the honest reading is that the question is not defined for this form.
    if( c.cochangeGroups && !c.cochangeFile.empty() )
    {
        std::fprintf( stderr, "ripwire: --cochange-groups groups the repo-wide violating pairs — it has nothing to "
                              "group under --cochange=FILE, whose core file is already the one you named "
                              "(e.g. ripwire <dir> --cochange --cochange-groups)\n" );
        c.ok = false;
    }

    // --baseline/--baseline-update write/merge the `.ripwire_arch_baseline` sidecar — both are read only
    // inside the `!cfg.archRules.empty()` branch of runArchViews (main.cpp). Alone they silently no-op; refuse
    // loudly (mirrors --gateability/--abi/--plan's "rides on another verb's sweep" shape, validateConfig below).
    if( ( c.baseline || c.baselineUpdate ) && c.archRules.empty() )
    {
        std::fprintf( stderr, "ripwire: --baseline/--baseline-update writes the --arch=FILE debt sidecar — pass both "
                              "(e.g. ripwire <dir> --arch=rules.yaml --baseline)\n" );
        c.ok = false;
    }

    // On the --for companion (the ONLY one where --detail is a genuine COUNT rather than a boolean "restore
    // the full listing" trigger — --owners/--doc-drift/--whereis/--stray-content/--flags all read
    // `cfg.detail != 0` as a bool, see the writeX(…, cfg.detail ? SIZE_MAX : kCap) call sites in main.cpp),
    // main.cpp:1622-1634 clamps the body count to std::min(detail, forTopN, corpusSize) with NO signal that a
    // larger request was truncated — the same "accepted, silently capped" failure --rank-by/--format/--order
    // avoid by refusing an out-of-range VALUE outright. forTopN (--pack-top-n=N, else 40) is knowable from the
    // flags alone, before ingest, so this can refuse here rather than clamp silently at dispatch time.
    if( !c.forTask.empty() )
    {
        const int forTopN = c.packTopN > 0 ? c.packTopN : 40;
        if( c.detail > forTopN )
        {
            std::fprintf( stderr, "ripwire: --detail=%d exceeds the ranked head — N must be 1..%d (raise the head with "
                                  "--pack-top-n=N, or lower --detail)\n", c.detail, forTopN );
            c.ok = false;
        }
    }

    // --compress strips comments from body output — every call site is a body emitter: --expand/--outline
    // (serialize.h packBodies/packOutline), --exemplar and --detail's top-N bodies (both inside the --for
    // branch), --pack-task, and --from-trace (main.cpp PackTaskInputs/FromTraceInputs). Alone (none of those)
    // it silently no-ops — verified: `ripwire <dir> --compress` is byte-identical to the plain map. Refuse
    // loudly rather than let a caller believe they compressed something.
    if( c.compress && c.expand.empty() && c.outline.empty() && !c.packTaskFlag && c.fromTrace.empty()
        && c.exemplar.empty() && !( c.detail > 0 && !c.forTask.empty() ) )
    {
        std::fprintf( stderr, "ripwire: --compress strips comments from --expand/--outline body output — pass one "
                              "(e.g. ripwire <dir> --expand=SYM --compress)\n" );
        c.ok = false;
    }

    // --color-by bakes the initial node-colour mode of the --html page — writeHtml is its only reader.
    // Alone it silently no-ops; refuse loudly (same shape as --with-graph/--compress above).
    if( c.colorByExplicit && !c.html )
    {
        std::fprintf( stderr, "ripwire: --color-by=MODE colors the --html export — pass both "
                              "(e.g. ripwire <dir> --html=g.html --color-by=community)\n" );
        c.ok = false;
    }
}

// The three --auto-bodies guards, lifted out of validateConfig, which is already one of the longest
// functions in this file and grows by a stanza on every flag added. Same shape as the --signatures-only
// pair it sits beside: --auto-bodies opts out of COMPACT conceptual serving, so ALONE it modifies
// nothing, and it contradicts BOTH of the other body postures — honoring one of a contradictory pair
// silently drops the other's effect with no tell, so the pair is refused loudly instead, each with the
// distinction spelled out. It is a PERMANENT posture flag beside --signatures-only and --detail=N, not a
// migration aid: a caller who wants inline bodies on conceptual queries stays supported indefinitely.
inline void refuseAutoBodiesMisuse( Config& c )
{
    if( c.autoBodies && c.forTask.empty() )
    {
        std::fprintf( stderr, "ripwire: --auto-bodies modifies --for=TASK — pass both (e.g. ripwire <dir> --for=\"task\" --auto-bodies)\n" );
        c.ok = false;
    }
    if( c.autoBodies && c.signaturesOnly )
    {
        std::fprintf( stderr, "ripwire: --auto-bodies contradicts --signatures-only — pass one (--auto-bodies asks for the automatic bodies; --signatures-only means no bodies at all)\n" );
        c.ok = false;
    }
    if( c.autoBodies && c.detail > 0 )
    {
        std::fprintf( stderr, "ripwire: --auto-bodies contradicts --detail=N — pass one (--detail=N is the explicit body knob and already supersedes the automatic pick)\n" );
        c.ok = false;
    }
}

inline void validateConfig( Config& c ) noexcept
{
    if( c.rootPath.empty() && !c.mcp && !c.scanSkills && c.scanSkillFile.empty() )   // scan / --mcp may run without a path
    {
        usage();
        c.ok = false;
    }

    // The remote HTTP transport pins ONE workspace fixed at startup, so --listen
    // needs a root on the command line (stdio --mcp does not — its clients name a path per request).
    if( !c.listen.empty() && c.rootPath.empty() )
    {
        std::fprintf( stderr, "ripwire: --listen serves ONE workspace fixed at startup — pass the repo root (e.g. ripwire . --listen=127.0.0.1:8765)\n" );
        c.ok = false;
    }

    validateModifierGuards( c );   // §P8: the eleven new "(with X)" companion guards, split out above (see its header)

    // --anchor is a negative-result experiment (dropped from --help) — gated behind
    // RIPWIRE_DEV=1 so it stays reachable for continued eval work without advertising it as supported.
    if( c.anchor && !std::getenv( "RIPWIRE_DEV" ) )
    {
        std::fprintf( stderr, "ripwire: --anchor is experimental, set RIPWIRE_DEV=1\n" );
        c.ok = false;
    }

    // --anchor only modifies the --for lens rank; alone it would silently do nothing — refuse loudly instead.
    if( c.anchor && c.forTask.empty() )
    {
        std::fprintf( stderr, "ripwire: --anchor modifies --for=TASK — pass both (e.g. ripwire <dir> --for=\"task\" --anchor)\n" );
        c.ok = false;
    }

    // --no-route forces plain subtoken+body on --for/--query (routing is the default); alone it does nothing — refuse loudly.
    if( c.noRoute && c.forTask.empty() && c.query.empty() )
    {
        std::fprintf( stderr, "ripwire: --no-route modifies --for=TASK or --query=TERMS — pass one (e.g. ripwire <dir> --for=\"task\" --no-route)\n" );
        c.ok = false;
    }

    // --adaptive cuts the --for/--query result set at the relevance cliff; alone it does nothing — refuse loudly.
    if( c.adaptive && c.forTask.empty() && c.query.empty() )
    {
        std::fprintf( stderr, "ripwire: --adaptive modifies --for=TASK or --query=TERMS — pass one (e.g. ripwire <dir> --for=\"task\" --adaptive)\n" );
        c.ok = false;
    }

    // --cochange-boost is a negative-result experiment (dropped from --help) — same
    // RIPWIRE_DEV=1 gate as --anchor. RIPWIRE_COCHANGE=1 (the separate MCP-facing env activation,
    // main.cpp) is untouched — it is not a --help-advertised flag.
    if( c.cochangeBoost && !std::getenv( "RIPWIRE_DEV" ) )
    {
        std::fprintf( stderr, "ripwire: --cochange-boost is experimental, set RIPWIRE_DEV=1\n" );
        c.ok = false;
    }

    // --cochange-boost only augments the --for lens; alone it would silently do nothing — refuse loudly.
    if( c.cochangeBoost && c.forTask.empty() )
    {
        std::fprintf( stderr, "ripwire: --cochange-boost modifies --for=TASK — pass both (e.g. ripwire <dir> --for=\"task\" --cochange-boost)\n" );
        c.ok = false;
    }

    // --no-mention-boost only disables a --for lens behavior; alone it would silently do nothing — refuse loudly.
    if( c.noMentionBoost && c.forTask.empty() )
    {
        std::fprintf( stderr, "ripwire: --no-mention-boost modifies --for=TASK — pass both (e.g. ripwire <dir> --for=\"task\" --no-mention-boost)\n" );
        c.ok = false;
    }

    // --no-doc-mention only disables a --for lens behavior; alone it would silently do nothing — refuse loudly.
    // (Same shape/scope as --no-mention-boost above, incl. the same --pack-task-only gap: computeLensRanking
    // also honors this flag when reached via --pack-task, but the loud-refuse check only reads --for=TASK —
    // consistent with the pre-existing --no-mention-boost/--cochange-boost validation, not a new gap.)
    if( c.noDocMention && c.forTask.empty() )
    {
        std::fprintf( stderr, "ripwire: --no-doc-mention modifies --for=TASK — pass both (e.g. ripwire <dir> --for=\"task\" --no-doc-mention)\n" );
        c.ok = false;
    }

    // --signatures-only opts out of --for's terminal-by-default bundle (T3); alone it does nothing — refuse loudly.
    if( c.signaturesOnly && c.forTask.empty() )
    {
        std::fprintf( stderr, "ripwire: --signatures-only modifies --for=TASK — pass both (e.g. ripwire <dir> --for=\"task\" --signatures-only)\n" );
        c.ok = false;
    }

    // --signatures-only ("no bodies") and --detail=N ("these bodies, explicitly") contradict each other —
    // honoring one silently drops the other's effect with no tell, so the pair is refused loudly instead.
    if( c.signaturesOnly && c.detail > 0 )
    {
        std::fprintf( stderr, "ripwire: --signatures-only contradicts --detail=N — pass one (--detail=N is the explicit body knob; --signatures-only means no bodies at all)\n" );
        c.ok = false;
    }

    refuseAutoBodiesMisuse( c );   // the three --auto-bodies guards, out of line (see above validateConfig)

    // §P6.4: --owners is ALSO a legal --detail=N companion (restores the full per-file listing instead of
    // the <uniform/> collapse) — stacked as its own `if` rather than folded into the && chain below so this
    // is a pure ADDITION: that chain was edited by unrelated work inside quality-delta's short-horizon-churn
    // window, and appending `&& !c.owners` to it would touch that hot line and misclassify this correct,
    // unrelated addition as thrash. `if( A ) if( B )` short-circuits identically to `if( A && B )` (no dangling
    // else below to worry about) — the line it guards is otherwise completely unmodified.
    if( !c.owners )
    {
        // --detail=N (RESEARCH lever 3) folds full bodies onto the --for lens; alone it does nothing — refuse loudly.
        // The cross-branch verbs (--stray-content/--whereis) reuse it for the SAME meaning — "lift the display cap, show the
        // rows the ranked head elided" — so they join --for as a legal companion rather than growing a second
        // spelling of "show me more". --flags/--flip belongs in that list for the same reason and always did:
        // its handler has read cfg.detail since it shipped (the per-gate site cap), but the guard here never
        // admitted it, so that branch was unreachable and `--flags --detail=N` refused instead of widening.
        if( c.detail > 0 && c.forTask.empty() && !c.strayContent && !c.whereisFlag && !c.docDrift && !c.darkFlags )
        {
            std::fprintf( stderr, "ripwire: --detail=N modifies --for=TASK — pass both (e.g. ripwire <dir> --for=\"task\" --detail=3)\n" );
            c.ok = false;
        }
    }

    // --partition=N SPLITS a --pack-task bundle; there is nothing else in the tool it could
    // split, so alone it would silently no-op on the default map. Refuse loudly (mirrors --detail/--adaptive),
    // and bound N in the same breath: 1 is just --pack-task, and past kMaxPartitions=16 an orchestrator is
    // doing something other than a fan-out (the same cap --connect and multi-root use).
    if( c.partitionCount > 0 && !c.packTaskFlag )
    {
        std::fprintf( stderr, "ripwire: --partition=N splits a --pack-task bundle — pass both (e.g. ripwire <dir> --pack-task=\"task\" --partition=4)\n" );
        c.ok = false;
    }
    if( c.partitionCount > 0 && ( c.partitionCount < 2 || c.partitionCount > 16 ) )
    {
        std::fprintf( stderr, "ripwire: --partition=%d is out of range — N must be 2..16 (1 is just --pack-task)\n", c.partitionCount );
        c.ok = false;
    }

    validatePlanLanes( c );   // the 6 --plan-lanes/--task/--brief guards, split out above (see its header)

    // --flip=NAME reports the blast radius of ONE gate from the --flags gate table; there is no other verb
    // in the tool that produces one, so alone it would silently no-op on the default map. Refuse loudly
    // (mirrors --detail/--partition), and refuse the BARE flag in the same breath — "which gate?" has no
    // sensible default, and an empty-looking success is the failure mode this verb exists to prevent.
    if( c.flipFlag && !c.darkFlags )
    {
        std::fprintf( stderr, "ripwire: --flip=NAME reports one gate from the --flags table — pass both (e.g. ripwire <dir> --flags --flip=CANYON_HARMONY_SFX)\n" );
        c.ok = false;
    }
    if( c.flipFlag && c.flipGate.empty() )
    {
        std::fprintf( stderr, "ripwire: --flip needs a gate name (e.g. --flip=CANYON_HARMONY_SFX) — run `ripwire <dir> --flags` to list them\n" );
        c.ok = false;
    }

    // --plan composes --stray-content's sweep with --merge-scout's overlap oracle; there is nothing else in
    // the tool it could compose, so alone it would silently no-op on the default map. Refuse loudly (mirrors
    // --flip/--partition).
    if( c.landingPlan && !c.strayContent )
    {
        std::fprintf( stderr, "ripwire: --plan composes with --stray-content's sweep — pass both (e.g. ripwire <dir> --stray-content --plan)\n" );
        c.ok = false;
    }

    // --abi is the cross-branch ABI-BREAK gate: modelling a struct off ANOTHER ref's blob only makes sense
    // alongside the ref sweep that finds those blobs, so alone it would silently no-op on the default map.
    // Refuse loudly (mirrors --flip/--partition/--detail above) rather than let it look like a no-op success.
    if( c.abiFlag && !c.strayContent )
    {
        std::fprintf( stderr, "ripwire: --abi reports the cross-branch ABI-break gate over the --stray-content ref sweep — pass both (e.g. ripwire <dir> --stray-content --abi)\n" );
        c.ok = false;
    }

    // --gateability (r26-stamp Task B) composes with --doc-drift's own report — alone it would silently no-op
    // on the default map. Refuse loudly (mirrors --plan/--abi immediately above).
    if( c.gateabilityFlag && !c.docDrift )
    {
        std::fprintf( stderr, "ripwire: --gateability reports over --doc-drift's own scan — pass both (e.g. ripwire <dir> --doc-drift --gateability)\n" );
        c.ok = false;
    }

    // --ack-only=SUBSTR narrows WHICH findings --quality-ack accepts; without --quality-ack there is nothing
    // to narrow, so alone it would silently no-op on the plain map — exit 0, print the ordinary default map,
    // stderr empty. That is the exact failure --ack-only exists to prevent: a typo'd narrowing (or a bare
    // invocation the operator believes narrowed something) must never look like a quiet success. Refuse
    // loudly (mirrors --gateability/--abi/--plan immediately above), naming both flags.
    if( !c.qualityAckOnly.empty() && !c.qualityAck )
    {
        std::fprintf( stderr, "ripwire: --ack-only=SUBSTR narrows --quality-ack — pass both (e.g. ripwire <dir> --quality-delta --ack-only=contract-change --quality-ack=\"reason\")\n" );
        c.ok = false;
    }

    // --format=candidates is a flat top-K export of a RANKED set — only --for/--query produce one; alone it
    // would silently no-op on the plain map. Refuse loudly (mirrors --adaptive/--detail).
    if( c.candidates && c.forTask.empty() && c.query.empty() )
    {
        std::fprintf( stderr, "ripwire: --format=candidates exports a --for=TASK or --query=TERMS result — pass one (e.g. ripwire <dir> --query=\"terms\" --format=candidates)\n" );
        c.ok = false;
    }


    // r27-emitters T2: --top-k=0 = "payload only, no ranked map". It is meaningful ONLY when some other flag
    // supplies the payload; alone it would emit nothing at all, and on a set-returning verb like --graph-query
    // a 0 would fall into that verb's legacy `topK > 0 ? cap : ALL` arm and dump the whole matched set. Confine
    // it to the four payload verbs and refuse everywhere else, naming the fix.
    if( c.topK == 0 && c.expand.empty() && c.outline.empty() && !c.packSignatures && c.packTopN <= 0 )
    {
        std::fprintf( stderr, "ripwire: --top-k=0 means \"no ranked map, payload only\" — pass a payload verb "
                              "(--expand=SYM / --outline=SYM / --pack-signatures / --pack-top-n=N), or use --top-k=1 for the smallest map\n" );
        c.ok = false;
    }
}

inline Config parseArgs( int argc, char** argv ) noexcept
{
    Config c;
    // --stable/--most-important-last/--no-auto-order are hidden aliases of --order= now —
    // still work, dropped from --help, warn ONCE per run (not once per flag) pointing at the replacement.
    bool orderDeprecWarned = false;
    auto deprecatedOrderFlag = [&]( const char* oldFlag, const char* newValue ) noexcept
    {
        if( orderDeprecWarned )
        {
            return;
        }
        orderDeprecWarned = true;
        std::fprintf( stderr, "ripwire: %s is deprecated — use --order=%s instead\n", oldFlag, newValue );
    };
    for( int i = 1; i < argc; ++i )
    {
        const std::string_view a = argv[i];          // argv strings are NUL-terminated

        if( a == "--help" || a == "-h" ) { printUsage( stdout ); std::exit( 0 ); }   // self-doc; first instinct must not error

        // --version — one line, exit 0. Version + compiler come from the SAME generated
        // version.h --help's "determinism" line points at (single source: project(ripwire VERSION ...)
        // in CMakeLists.txt), so this can never drift from the CMake version test/versioncheck.sh checks.
        if( a == "--version" || a == "-v" )
        {
            std::printf( "ripwire %s (%s, %s %s, git %s)\n", kRipwireVersion, kRipwireBuildType,
                         kRipwireCompilerId, kRipwireCompilerVer, kRipwireGitStamp );
            std::exit( 0 );
        }

        if( startsWith( a, "--" ) )
        {
            // ── the table scan (kBoolFlags / kViewFlags / kIntFlags) ───────────────────────────────
            // 132 of the 149 `--` arms are exactly "set one member" (plus, for kViewFlags/kIntFlags rows, a
            // companion bool or two) and live in the tables above. They are
            // matched here, in declaration order, before the hand-written arms below; a hit `continue`s to
            // the next argv element so the chain underneath is reached only by the arms a table cannot hold.
            bool isTableFlag = false;
            for( const BoolFlag& bf : kBoolFlags )
            {
                if( a == bf.lit )                  { c.*bf.member = true;                        isTableFlag = true;  break; }
            }
            if( !isTableFlag )
            {
                const ViewFlagMatch vm = applyViewFlag( a, c );          // §A9 V1-4: also owns the empty-value refusal
                if( vm == ViewFlagMatch::Refused ) { c.ok = false;  return c; }
                isTableFlag = ( vm == ViewFlagMatch::Assigned );
            }
            if( !isTableFlag )
            {
                const IntFlagMatch im = applyIntFlag( a, c );            // §B8.2: owns the bad-value refusal for `--x=N`
                if( im == IntFlagMatch::Refused )  { c.ok = false;  return c; }
                isTableFlag = ( im == IntFlagMatch::Assigned );
            }
            if( isTableFlag )
            {
                continue;
            }

            if( startsWith( a, "--order=" ) )
            {
                const std::string_view v = a.substr( 8 );
                if( v == "stable" )
                {
                    c.stable = true;
                }
                else if( v == "important-last" )
                {
                    c.mostImportantLast = true;
                }
                else if( v == "important-first" )
                {
                    c.noAutoOrder = true;
                }
                else
                {
                    std::fprintf( stderr, "ripwire: --order: unknown value '%.*s' (supported: stable|important-first|important-last)\n", int( v.size() ), v.data() );
                    c.ok = false;
                    return c;
                }
            }
            else if( a == "--most-important-last" )       { deprecatedOrderFlag( "--most-important-last", "important-last" );  c.mostImportantLast = true; }
            else if( a == "--stable" )                    { deprecatedOrderFlag( "--stable", "stable" );                       c.stable            = true; }
            else if( a == "--no-auto-order" )             { deprecatedOrderFlag( "--no-auto-order", "important-first" );       c.noAutoOrder       = true; }
            // §B8.2 verifier finding N4 (W2FIX-CLI): reuses parseByteSize's N[K|M|G] grammar (K is the
            // practical case; M/G come free) — a std::size_t BYTE COUNT, so this stays hand-written for the
            // same reason as --pack-budget-bytes (an `int Config::*` table row would narrow the accepted
            // range). Only the REFUSAL sentence moves onto the shared dialect; the accept side is untouched.
            else if( startsWith( a, "--token-budget=" ) )
            { if( !parseByteSize( a.data() + 15, c.tokenBudget ) )
              { refuseFlagValue( "--token-budget", "a positive token count, plain or with a K/M/G suffix", a.data() + 15, "--token-budget=16000" );  c.ok = false; return c; } }
            else if( startsWith( a, "--limit=" ) )
            { if( !refusePageValue( "--limit", a.data() + 8, /*isZeroAllowed=*/false, c.pageLimit ) ) { c.ok = false; return c; } }
            else if( startsWith( a, "--offset=" ) )
            { if( !refusePageValue( "--offset", a.data() + 9, /*isZeroAllowed=*/true, c.pageOffset ) ) { c.ok = false; return c; } }
            // §B8.2: --pack-budget-bytes stays hand-written where its nine numeric siblings moved into
            // kIntFlags — its member is a u64 BYTE COUNT, and an `int Config::*` table row could only hold
            // it by narrowing the accepted range (a --pack-budget-bytes=5000000000 that parses today would
            // start refusing). It shares the refusal, which is the half that had drifted.
            else if( startsWith( a, "--pack-budget-bytes=" ) )
            {
                if( !parsePosU64( a.data() + 20, c.packBudgetBytes ) )
                { refuseFlagValue( "--pack-budget-bytes", "a positive integer", a.data() + 20, "--pack-budget-bytes=32768" );  c.ok = false;  return c; }
                std::fprintf( stderr, "ripwire: --pack-budget-bytes is deprecated — use --pack-task/--detail instead (unchanged behavior for now)\n" );
            }
            // §B8.2 verifier finding N4 (W2FIX-CLI): same std::size_t-byte-count reasoning as --token-budget
            // above — stays hand-written, refusal only routed onto the shared sentence.
            else if( startsWith( a, "--max-file-size=" ) )
            { if( !parseByteSize( a.data() + 16, c.maxFileBytes ) )
              { refuseFlagValue( "--max-file-size", "a positive byte size, plain or with a K/M/G suffix", a.data() + 16, "--max-file-size=10MB" );  c.ok = false; return c; } }
            else if( startsWith( a, "--exclude=" ) )
            {
                c.excludes.push_back( std::string( a.substr( 10 ) ) );
                // r27-emitters T5: a BAD VALUE is not an unknown FLAG. `--rank-by=bogus` used to fall through the
                // exact-match chain to the generic "unknown flag" arm, which told the agent the flag itself does not
                // exist — a fabrication the agent then believes. `--order=`/`--export=` already name the value and
                // list the supported set; these two now do the same.
            }
            // G3: repeatable, so a kViewFlags row (one member per flag) cannot hold it — same shape as
            // --exclude= above. An empty value is refused here rather than silently pushing "" (a term that
            // is a substring of everything would make --and= vacuous and --not= reject every hit).
            else if( startsWith( a, "--and=" ) )
            {
                if( a.size() == 6 )
                { refuseEmptyValue( "--and=", "a literal string that must ALSO be present", "--and='mcp'" );  c.ok = false; return c; }
                c.grepAnd.push_back( a.substr( 6 ) );
            }
            else if( startsWith( a, "--not=" ) )
            {
                if( a.size() == 6 )
                { refuseEmptyValue( "--not=", "a literal string that must be ABSENT", "--not='deprecated'" );  c.ok = false; return c; }
                c.grepNot.push_back( a.substr( 6 ) );
            }
            else if( startsWith( a, "--grep-scope=" ) )
            {
                const std::string_view v = a.substr( 13 );
                if( v != "line" && v != "file" )
                {
                    std::fprintf( stderr, "ripwire: --grep-scope=%.*s — unknown value (supported: line|file), e.g. --grep-scope=file\n",
                                  int( v.size() ), v.data() );
                    c.ok = false; return c;
                }
                c.grepScope = v;
            }
            else if( startsWith( a, "--grep-in=" ) )
            {
                // R-H span tiers. Same shape as --grep-scope= above (closed value set, refuse an unknown
                // value rather than silently defaulting) — a typo here would otherwise read as "code" and
                // quietly suppress the very rows the user asked to see.
                const std::string_view v = a.substr( 10 );
                if( v != "code" && v != "any" )
                {
                    std::fprintf( stderr, "ripwire: --grep-in=%.*s — unknown value (supported: code|any), e.g. --grep-in=any\n",
                                  int( v.size() ), v.data() );
                    c.ok = false; return c;
                }
                c.grepIn = v;
            }
            else if( startsWith( a, "--rank-by=" ) )
            {
                const std::string_view v = a.substr( 10 );
                if( v == "pagerank" )
                {
                    c.rankBy = RankBy::PageRank;
                }
                else if( v == "authority" )
                {
                    c.rankBy = RankBy::Authority;
                }
                else if( v == "hub" )
                {
                    c.rankBy = RankBy::Hub;
                }
                else if( v == "rrf" )
                {
                    c.rankBy = RankBy::Rrf;
                }
                else if( v == "churn" )
                {
                    c.rankBy = RankBy::Churn;
                }
                else if( v == "churn-decay" )
                {
                    c.rankBy = RankBy::ChurnDecay;   // P0-4: the same prior, with each commit weighted 0.5^(age/90d)
                }
                else
                {
                    std::fprintf( stderr, "ripwire: --rank-by: unknown value '%.*s' (supported: pagerank|authority|hub|rrf|churn|churn-decay)\n", int( v.size() ), v.data() );
                    c.ok = false;
                    return c;
                }
            }
            else if( startsWith( a, "--color-by=" ) )
            {
                const std::string_view v = a.substr( 11 );
                if( v == "lang" )
                {
                    c.colorBy = ColorBy::Lang;         // explicit lang still requires --html (the modifier guard below)
                }
                else if( v == "community" )
                {
                    c.colorBy = ColorBy::Community;
                }
                else if( v == "cx" )
                {
                    c.colorBy = ColorBy::Cx;
                }
                else if( v == "churn" )
                {
                    c.colorBy = ColorBy::Churn;
                }
                else if( v == "tested" )
                {
                    c.colorBy = ColorBy::Tested;
                }
                else
                {
                    // An empty value lands here too, on purpose: `--color-by=` is a bad VALUE, not an unknown
                    // FLAG, and the refusal must say which (r27-emitters T5).
                    std::fprintf( stderr, "ripwire: --color-by: unknown value '%.*s' (supported: lang|community|cx|churn|tested)\n", int( v.size() ), v.data() );
                    c.ok = false;
                    return c;
                }
                // Set ONCE, past the refusal's early return: a mode added above cannot forget it, which is
                // exactly the way the --html-required guard would go silently dark.
                c.colorByExplicit = true;
            }
            else if( startsWith( a, "--format=" ) )
            {
                const std::string_view v = a.substr( 9 );
                if( v == "columnar" )
                {
                    c.columnar = true;
                }
                else if( v == "rows" )
                {
                    c.columnar = true; // alias
                }
                else if( v == "xml" )
                {
                    c.columnar = false; // explicit default (byte-identical)
                }
                else if( v == "candidates" )
                {
                    c.candidates = true; // R6: flat top-K export for external rerankers
                }
                else
                {
                    std::fprintf( stderr, "ripwire: --format: unknown value '%.*s' (supported: xml|columnar|rows|candidates)\n", int( v.size() ), v.data() );
                    c.ok = false;
                    return c;
                }
            }
            // §A9 V1-4 / §B5: --expand and --outline stay hand-written because they SPLIT A COMMA LIST into a
            // vector<string> — the one shape kViewFlags cannot hold (--regex= moved into it once the table
            // grew an isSetFlag column). Both call the SAME refuseEmptyValue rather than growing a second
            // dialect of it. --outline= was the FOURTH §B5 arm: it had the split and not the refusal, so
            // `--outline=` emitted the whole default map at exit 0 while its identical sibling --expand=
            // refused, eleven lines up.
            else if( a == "--route" )                         { /* routing is now the DEFAULT — accept for back-compat, no-op */ }
            else if( startsWith( a, "--expand=" ) )
            {
                const std::string_view v = a.substr( 9 );
                if( v.empty() ) { refuseEmptyValue( "--expand=", "one or more symbol names, comma-separated", "--expand=parseArgs" );  c.ok = false;  return c; }
                for( std::size_t start = 0; start < v.size(); )
                {
                    std::size_t comma = v.find( ',', start );
                    if( comma == std::string_view::npos )
                    {
                        comma = v.size();
                    }
                    if( comma > start )
                    {
                        c.expand.push_back( std::string( v.substr( start, comma - start ) ) );
                    }
                    start = comma + 1;
                }
            }
            else if( startsWith( a, "--outline=" ) )
            {
                const std::string_view v = a.substr( 10 );
                if( v.empty() ) { refuseEmptyValue( "--outline=", "one or more symbol names, comma-separated", "--outline=parseArgs" );  c.ok = false;  return c; }
                for( std::size_t start = 0; start < v.size(); )
                {
                    std::size_t comma = v.find( ',', start );
                    if( comma == std::string_view::npos )
                    {
                        comma = v.size();
                    }
                    if( comma > start )
                    {
                        c.outline.push_back( std::string( v.substr( start, comma - start ) ) );
                    }
                    start = comma + 1;
                }
            }
            else if( a == "--quality-ack" )                    { c.qualityAck = true; c.qualityDelta = true; }
            else if( startsWith( a, "--export=" ) )
            {
                // --export=cc.json  or  --export=cc.json:FILE  (mirror --html's FILE-or-stdout convention).
                std::string_view v = a.substr( 9 );
                std::string_view fmt = v;  std::string_view file;
                if( const std::size_t colon = v.find( ':' ); colon != std::string_view::npos )
                { fmt = v.substr( 0, colon ); file = v.substr( colon + 1 ); }
                if( fmt == "cc.json" || fmt == "ccjson" ) { c.exportCcJson = true; c.exportFile = file; }
                else { std::fprintf( stderr, "ripwire: --export: unknown format '%.*s' (supported: cc.json)\n", int( fmt.size() ), fmt.data() ); c.ok = false; return c; }
            }
            else { std::fprintf( stderr, "ripwire: unknown flag '%.*s'\n", int( a.size() ), a.data() ); c.ok = false; return c; }
        }
        else
        {
            // every non-flag positional is a crawl root: one = today's behavior
            // verbatim; 2..kMaxWorkspaceRoots = a multi-root workspace merged into ONE graph.
            if( c.roots.size() >= kMaxWorkspaceRoots )
            {
                std::fprintf( stderr, "ripwire: too many roots (max %zu): '%.*s'\n", kMaxWorkspaceRoots, int( a.size() ), a.data() );
                c.ok = false;  return c;
            }
            if( c.rootPath.empty() )
            {
                c.rootPath = a; // roots[0] alias (A1)
            }
            c.roots.push_back( a );
        }
    }

    // P2-C: MCP callers benefit most from a stable, KV-cache-friendly prefix and shouldn't have to remember
    // the flag — so --mcp turns --stable ON by default, opt out with --no-stable. This is a DEFAULT, not a
    // validation: it must stay on THIS side of the validateConfig boundary (see that function's header).
    if( c.mcp && !c.noStable )
    {
        c.stable = true;
    }

    validateConfig( c );
    return c;
}

}   // namespace rw

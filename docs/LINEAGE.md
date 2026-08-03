# ripwire — lineage

Almost nothing in this tool is a new idea. What is new is the *combination*, and the discipline that
holds it together. This document is the row-by-row ledger of where each part came from: the paper,
the specification, or the repository, the one-line lesson taken from it, and the flag or source file
in this tree where that lesson actually lives.

It exists because "inspired by the whole field" is unfalsifiable and "we invented ranked code maps"
is false. Both are cheaper than a table. This is the table.

**The honesty rule this document obeys.** A work is listed as *folded* only if the lesson taken from
it can be named in one sentence **and** pointed at a real flag or source file. Everything else is
*surveyed* — read, catalogued, and not borrowed from. Surveyed is not a weaker form of folded; it is
a different claim, and §3b says so again where it is easy to skim past. Works that were cited during
the research but could not be traced to a shipped decision are named at the end of §2 rather than
padded into the tables — the count is the point, so the count has to be earned.

**A link here is not a dependency and not a debt claim.** No code is copied from any work in §1, §2,
or §3 except where it is vendored, and every vendored library is enumerated with its author and its
licence in [`THIRD_PARTY.md`](../THIRD_PARTY.md). First-party code under `src/` is Apache-2.0; true
third-party code lives under `third_party/` and keeps its own licence. Citing a paper means the idea
was read and applied, not that any of its text or code is here.

**The counts, derived from the tables below:** **27 repositories** and **27 papers** are folded, and
a labelled survey of **220 tools** contributed nothing and says so. **The two sets are disjoint by
construction, so they add rather than nest:** a tool that contributed a lesson gets a row in §3a and
is never repeated in §3b, which makes the field study 27 folded *plus* 220 surveyed — not 27 picked
out of 220. `test/readmedriftcheck.sh` re-derives all three numbers from these tables on every run,
fails if the README's sentence disagrees, and proves the disjointness itself (arm E6) rather than
taking this paragraph's word for it.

---

## 1. Classic papers

Six results, none newer than 2009, that the ranking and quality machinery is built directly on.

| Year | Work | Lesson taken | Where it lives |
| --- | --- | --- | --- |
| 1976 | McCabe, *A Complexity Measure* — [doi:10.1109/TSE.1976.233837](https://doi.org/10.1109/TSE.1976.233837) | Complexity is countable from syntax alone: one plus the decision points in a definition. No build, no types. | `cx=` on `--metrics`; the complexity half of `--hotspots` (`src/model.h`) |
| 1994 | *Okapi BM25* — Robertson, Walker et al. at TREC-3 (1994), in the Robertson & Spärck Jones probabilistic-relevance lineage. The TREC-3 paper has no DOI; the standard citable reference is the later survey, [Robertson & Zaragoza 2009, *The Probabilistic Relevance Framework: BM25 and Beyond*, doi:10.1561/1500000019](https://doi.org/10.1561/1500000019) | Term frequency saturates and long documents must be discounted; raw counts rank badly. | Both lexical rankers, behind `--for` and `--query` (`src/lexical.h`, k1=1.5, b=0.75) |
| 1998 | Page & Brin, *The PageRank Citation Ranking* — [Stanford InfoLab 422](http://ilpubs.stanford.edu:8090/422/) | Importance is a fixed point of who-points-at-whom; a biased teleport vector makes it relative to a query. | The default ranked map and `--rank-by=pagerank` (`src/pagerank.cpp`) |
| 1999 | Kleinberg, *Authoritative Sources in a Hyperlinked Environment* — [doi:10.1145/324133.324140](https://doi.org/10.1145/324133.324140) | One score is not enough: being pointed at and pointing at good things are different kinds of important. | `--rank-by=authority` and `--rank-by=hub` (`src/graph.h`) |
| 2008 | Blondel et al., *Fast unfolding of communities in large networks* — [arXiv:0803.0476](https://arxiv.org/abs/0803.0476) | Modules are recoverable from edges alone by greedy modularity optimisation, cheaply enough to run per invocation. | `--communities`, `--community=ID`, `--zoom` (`src/partition.h`) |
| 2009 | Cormack et al., *Reciprocal Rank Fusion* — [doi:10.1145/1571941.1572114](https://doi.org/10.1145/1571941.1572114) | Rankings fuse on reciprocal rank without score calibration or training — the deterministic way to combine signals. | `--rank-by=rrf` (`src/graph.h`) |

---

## 2. Modern research

Each row changed a decision. Where a paper's finding argued *against* something, the row says so —
several of these are the reason a feature is absent, narrow, or refuses. One row runs the other way:
the paper argued *for* a mechanism, the measurement here did not reproduce the gain, and the feature
was rejected rather than shipped on the paper's authority. That is the LARGER row, and it is the one
worth reading first.

Two rows rest on three sources that are not peer-reviewed — a vendor specification, a book, and a
practitioner article. Each is labelled as such in its own row rather than left to look like a paper.

| Work | Lesson taken | Where it lives |
| --- | --- | --- |
| *Lost in the Middle* — [arXiv:2307.03172](https://arxiv.org/abs/2307.03172) | Accuracy swings more than twenty points with *where* the answer sits in the window; a long context can score below no context. | Why the map is ranked and capped rather than dumped: `--top-k`, and `--order` for the position of the important rows |
| LongCodeBench — [arXiv:2505.07897](https://arxiv.org/abs/2505.07897) | For code specifically the effect is not a mild prose degradation but a resolve-rate collapse — roughly 29% to 3% as context grows 32K to 256K. | Budgets are treated as a correctness feature, not thrift: `--token-budget`, `--max-tokens` |
| Context selection for repository-level generation — [arXiv:2503.20589](https://arxiv.org/abs/2503.20589) | Definitions plus invoked-API signatures reached 37.8% Pass@1; adding top-5 *similar snippets* dropped it to 19.6%. Similarity-selected code actively hurts. | No similarity-snippet output exists anywhere in the tool. `--pack-signatures` emits contracts, and `--exemplar` picks by role — fan-in, complexity, test coverage — never by text similarity (`src/exemplar.h`) |
| Agentless — [arXiv:2407.01489](https://arxiv.org/abs/2407.01489) | A three-rung ladder (tree, then skeletons, then bodies for the selected few) localises well with no ML at all: signatures are usually enough to decide what to expand. | The detail ladder: `--tree` → `--pack-signatures` → `--expand` |
| RepoGraph — [arXiv:2410.14684](https://arxiv.org/abs/2410.14684) | Dependency-graph-structured retrieval beats sequence retrieval, and one hop beats two — the second hop adds noise, not recall (k=1 29.7% > k=2 26.0%). | The hop count is exposed as `--around-depth=N`, and the paper's form is `--around-depth=1`. **This landing is partial, and the row says so rather than rounding up to "shipped".** The default is **2**, not the paper's 1 (`src/cli.h`), and `N` is not capped — nothing in the tool enforces the lesson, it only makes it reachable. The research record says `--around` *should* stay shallow, which is an aspiration, not a landed default. The second hop is not cheap on this repository: `--around=buildGraph` returns 31 symbols at depth 1 and 283 at depth 2. Whether the default moves to 1 is an open question, not a settled one |
| cAST — [arXiv:2506.15655](https://arxiv.org/abs/2506.15655) | Never cut mid-construct; pack along syntax boundaries and budget by content, not by lines. | The budgeted packer emits a whole definition or skips it and discloses the skip — it never ships a truncated body |
| HCP — [arXiv:2406.18294](https://arxiv.org/abs/2406.18294) | Full bodies for the head and signatures for the tail costs a fraction of all-bodies and loses almost nothing, provided the dependency edges survive. | `--detail=N`, and the body/signature split inside `--pack-task` (`src/packtask.h`) |
| Adaptive-k — [arXiv:2506.08479](https://arxiv.org/abs/2506.08479) | Cut a ranked list at its largest score gap rather than at a fixed k; the knee moves by more than an order of magnitude between queries. | `--adaptive` |
| LARGER — [arXiv:2605.16352](https://arxiv.org/abs/2605.16352) | Lexical anchors plus confidence-filtered deterministic graph expansion beat plain lexical retrieval on public localization benchmarks, with no embeddings involved. | **The row where a paper argued *for* a mechanism and the measurement said no.** The confidence-filtered anchor-expansion candidate was built, pre-registered against a held-out slice, and scored **+0.41pp** paired with a 95% lower bound of **+0.00pp** — rejected outright by the acceptance gate and never shipped ([`EVALS.md`](EVALS.md) §7, calibration in `bench/locbench/anchorhop_calib.json`). `--anchor` is therefore absent from `--help` and refuses to run without an explicit development environment variable; §8 lists the figure that circulates for it as *not published*. What survived is the paper's cheaper half: query-shape routing, opted out with `--no-route`, and the query-mention anchor, opted out with `--no-mention-boost` (`src/filter.h`, `src/lexical.h`) |
| *Keyword search is all you need* (AAAI 2026) — [arXiv:2602.23368](https://arxiv.org/abs/2602.23368) | Agentic keyword search reaches most of a retrieval-augmented pipeline's quality with no vector store at all. | There are no embeddings in this binary. `--grep`, `--regex` and `--match` are first-class verbs rather than the fallback (`src/search.h`) |
| LocAgent / Loc-Bench — [arXiv:2503.09089](https://arxiv.org/abs/2503.09089) | A strict metric — an instance scores only if **all** gold locations are inside the top k — and a frozen public dataset, so results are comparable rather than self-reported. | `bench/locbench/`, and every localization number in [`EVALS.md`](EVALS.md) |
| ONTO — [arXiv:2604.17512](https://arxiv.org/abs/2604.17512) | Genuinely tabular rows re-encode far cheaper as parallel arrays than as repeated per-row markup. | `--format=columnar` (`src/columnar.h`) |
| Controlled serialization study — [arXiv:2603.03306](https://arxiv.org/abs/2603.03306) | The same compact re-encoding collapses on *nested* data, and the headline savings are measured against pretty-printed JSON — a baseline minified XML already beats. | `--format=columnar` refuses every non-tabular verb with exit 1 instead of degrading quietly; the nested map is never re-encoded |
| Tokenizer and formatting cost — [arXiv:2508.13666](https://arxiv.org/abs/2508.13666) | A single characters-per-token divisor is 20–35% wrong on code, and the spread is dominated by language, not by the tokenizer. | The per-language calibration behind `est_tokens` — and the decision *not* to vendor a byte-pair table, which would buy exactness for the wrong tokenizer |
| AI-generated code smells — [arXiv:2605.02741](https://arxiv.org/abs/2605.02741) | Bloat tracks architectural decay almost perfectly, and the named failure modes are god-class growth, inline re-implementation of existing interfaces, and file separation mistaken for cohesion. | Three of `--quality-delta`'s ten kinds: verbosity, duplication, and reuse-decline (`src/quality.h`) |
| Agent-code maintainability — [arXiv:2606.21804](https://arxiv.org/abs/2606.21804) | Classical complexity did not predict real agent-code maintenance failures. Contract drift and code growth did. | The api-surface kind in `--quality-delta`, and `--edit-check` as a standalone contract check (`src/editcheck.h`) |
| Metric feedback into the loop — [arXiv:2505.23953](https://arxiv.org/abs/2505.23953) | Feeding measured complexity back after a failed attempt raised Pass@1 from 12.5% to 35.7%; the oracle has to be re-readable, not just a verdict. | `--quality-delta` reports only what a change made *worse*, itemised, in a form meant to go back into the next prompt |
| Nagappan & Ball, *Use of relative code churn measures to predict defect density* — [ICSE'05](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/icse05churn.pdf) | Process history predicts defects at least as well as any static complexity number — complex code that never changes costs nothing. | `--hotspots` is complexity multiplied by git churn; churn is also a ranking signal in its own right, `--rank-by=churn` (`src/gitmine.h`) |
| SonarSource, *Cognitive Complexity* — [specification](https://www.sonarsource.com/docs/CognitiveComplexity.pdf) *(vendor specification, not peer-reviewed)* | Weight by nesting, and do not penalise a flat N-case switch — a readability measure should reward the shape people actually find readable. | `ccx=` emitted alongside `cx=` on `--metrics`, and used ahead of `cx` by `--hotspots` |
| Kamiya, Kusumoto & Inoue (2002), *CCFinder: a multilinguistic token-based code clone detection system for large scale source code* — [doi:10.1109/TSE.2002.1019480](https://doi.org/10.1109/TSE.2002.1019480) | Normalise identifiers and literals to token classes, then hash: duplication survives renaming, and detecting it needs no types. | `--clones`, and the duplication kind in `--quality-delta` (`src/clones.h`) |
| Component-coupling metrics — Lakos CCD/ACD/NCCD (*Large-Scale C++ Software Design*, 1996 — *a book, no DOI*) and [Martin's Ca/Ce/I/A/D](https://devlead.io/DevTips/PrinciplesOfComponentCoupling) *(practitioner article, not peer-reviewed)* | Both are widely implemented and neither has independent outcome-based validation. A search for one came back empty. | Both are emitted and both are labelled in `--help` as a design heuristic rather than a validated signal, and **neither is ever allowed to gate** — `--deps`, `--arch` (`src/arch.h`) |

**Cited during the research and deliberately not given a row**, because no shipped decision traces
to them alone rather than to a paper already listed: the *Power of Noise* result on plausible-but-wrong
context and the Chroma context-degradation study (both corroborate the two context rows above);
GraphCoder, RepoHyper, RepoCoder, LongCodeZip and the retrieval-augmented-code-generation survey
(read as background for the ladder, no distinct decision); the static-analysis-feedback replications
that agree with the metric-feedback row; type-constrained generation; and the ecosystem-scale
dependency-risk work — the zero-runtime-dependency posture here is an engineering judgement, and the
record is explicit that no head-to-head study supports it. One further finding shaped the tool with
no citable identifier in the research record and so appears here rather than in the table: the
measured unreliability of using a language model as a judge, which is why every evaluation instrument
in this repository is a deterministic oracle.

---

## 3. The tool field

### 3a. Folded — a named lesson, and where it landed

Every row below names a specific thing taken. Five of them are vendored code and say so; the rest are
ideas. Vendoring a library is not by itself a lesson: `third_party/` holds one library that no
shipped target links, and it is named in the near-miss paragraph below rather than given a row here.

| Repository | Lesson taken | Where it lives |
| --- | --- | --- |
| [tree-sitter](https://github.com/tree-sitter/tree-sitter) | Incremental parsing with a per-language query convention, so symbol extraction is inherited from maintained grammars instead of written per language. | The whole ingest stage (`src/ingest.cpp`); fifteen grammars vendored, enumerated in [`THIRD_PARTY.md`](../THIRD_PARTY.md) |
| [aider repo-map](https://aider.chat/2023/10/22/repomap.html) | Rank a whole-repository symbol map with PageRank over the reference graph, and hand an agent the map rather than the files. This is the direct ancestor of the default run. | The default ranked map; also the interpreted-versus-compiled comparison arm in the head-to-head ([`EVALS.md`](EVALS.md) §2) |
| [ctags](https://ctags.io/) | The durable unit of code navigation is a tiny fixed record — name, kind, and where it is — not a document. | The `<s t= n= id= k=>` symbol row: kind, name, canonical id, and a rank, nested inside its `<f p=>` file element so the path is written once per file. Line numbers are the one part of the ctags record deliberately dropped from the map — a line number goes stale on the next edit, and the map is a thing an agent rebuilds per turn |
| [Zoekt](https://github.com/sourcegraph/zoekt/blob/main/doc/design.md) | Index trigrams and intersect posting lists: pick the rarest trigrams first, then verify candidates, instead of scanning files. | The substring and regex index behind `--grep` and `--regex` (`src/search.h`) |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | A scanner fast enough stops being something you run and becomes something that is always on — and smart committed defaults beat configuration. | The name; the committed crawl skip-list rather than a per-repository ignore file (`src/ingest.h`); the warm-run latency target |
| [ast-grep](https://github.com/ast-grep/ast-grep) | Metavariable patterns over the syntax tree are a better query surface for code shape than regular expressions, and they make lint rules user-authorable. | `--match=QUERY`, and the YAML rule shape read by `--lint-rules=DIR` (`src/lintrules.h`) |
| [Semgrep](https://semgrep.dev/blog/2024/modernizing-static-analysis-for-c/) | Useful analysis is possible without include resolution or type information — own that band explicitly rather than apologising for it. | The syntax-only scope of `--lint`, stated as a limit rather than implied |
| [CodeQL](https://codeql.github.com/docs/codeql-language-guides/analyzing-data-flow-in-cpp/) | Use-after-move, null-dereference and the rest need real dataflow over a compiled program. Approximating them from syntax produces noise and costs trust. | The checks deliberately **not** implemented: `--lint` ships no dataflow rules, and the omission is documented rather than silent |
| [clang-tidy](https://clang.llvm.org/extra/clang-tidy/checks/list.html) | A specific, well-chosen set of checks is purely structural — branch clones, else-after-return, C-style casts, empty-bodied conditionals — and needs no build at all. | The built-in rules behind `--lint` (`src/lintrules.h`) |
| [SCIP](https://sourcegraph.com/blog/announcing-scip) | A human-readable cross-repository symbol moniker, in an index format compact enough to consume as an *optional* precision layer over a cheaper resolver. | `--scip=index.scip`, which replaces guessed call edges with precise ones where the index covers them (`src/scip.h`, `src/scipoverlay.h`) |
| [Glean](https://engineering.fb.com/2024/12/19/developer-tools/glean-open-source-code-indexing/) | Expose derived predicates over the base graph so callers can compose their own question, instead of shipping one fixed verb per question. | `--graph-query=EXPR` — sources, filters and bounded closure, composed by the caller |
| [stack-graphs](https://github.blog/open-source/introducing-stack-graphs/) | Make the unit of incrementality the *file*: reparse and re-merge one file rather than the tree. | The content-hashed per-file warm cache — a warm run is gated byte-identical to a cold one (`src/ingest.cpp`) |
| [Serena](https://github.com/oraios/serena) | A language-server-backed toolkit resolves what a name-based graph can only guess at. The gap is real and permanent at this cost point. | The guesses are labelled instead of hidden: `amb=` per symbol, `ambiguous=` per document, `counts_floor=` on every count name resolution cannot prove is total (`src/resolve.h` for `amb=`, `src/graphlegend.h` for `counts_floor=` and the legend that defines it) |
| [probe](https://github.com/probelabs/probe) | Determinism is a product feature worth advertising, not an implementation detail. | Two runs over one tree are byte-identical, gated on every push — `test/det-gate.sh` |
| [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) | A committable index artifact turns a team's or CI's cold start into someone else's warm one. | `--cache=FILE` and `--index-out`; it is also a measured head-to-head arm, so the comparison is a number rather than an opinion ([`EVALS.md`](EVALS.md) §2) |
| [Sourcegraph / Cody](https://sourcegraph.com/blog/how-cody-understands-your-codebase) | A vendor operating at scale deprecated embeddings in favour of keyword and structural retrieval — the strongest available external evidence against the embedding-first default. | The architecture: no embeddings, no vector store, no model weights in the binary |
| [CodeScene](https://codescene.com/product/behavioral-code-analysis) | Combine the code metric with the change history — complexity that never changes is not where the risk is. | The shape of `--hotspots`, and the `--since` window that scopes it |
| [ArchUnit](https://www.archunit.org/userguide/html/000_Index.html) | Architecture as a test, with a frozen baseline so an existing violation set can be grandfathered and only *new* debt fails the build. | `--arch=FILE --baseline` and `--baseline-update`, with exit 2 on a new violation |
| [dependency-cruiser](https://github.com/sverweij/dependency-cruiser) | Layering rules belong to the project, in a checked-in file, not to the tool. The tool enforces; it does not opine. | `--arch=FILE` reads user-authored allow/deny rules and ships none of its own (`src/arch.h`) |
| [include-what-you-use](https://github.com/include-what-you-use/include-what-you-use/blob/master/docs/WhyIWYU.md) | Deciding an include is unused needs real type resolution; a syntactic approximation is noise wearing a useful name. | Not attempted. `--deps` reports the include graph as a fact and stops there — the one place this tool most wanted a heuristic and does not ship one |
| [ruff](https://astral.sh/ruff) | Parse once, then run every check over the same tree — the parse, not the checks, is the cost. | `--lint`, `--metrics`, `--clones` and the map all read one shared parse of the corpus |
| [uv](https://github.com/astral-sh/uv/blob/main/BENCHMARKS.md) | Past a latency threshold a tool changes category: it stops being something you invoke and becomes something that runs every turn. | The design target — a repository map an agent can afford to rebuild per turn, with the medians published in [`EVALS.md`](EVALS.md) |
| [unordered_dense](https://github.com/martinus/unordered_dense) | A dense open-addressing map with contiguous values beats the standard node-based one on both lookup and iteration. | Vendored. The symbol table and every hot lookup; `std::unordered_map` is banned by house rule |
| [svector](https://github.com/martinus/svector) | Most per-symbol edge lists are tiny, so the small ones belong inline rather than on the heap. | Vendored. Edge and reference lists |
| [gtl](https://github.com/greg7mdp/gtl) | When iteration order must be sorted and deterministic, a cache-friendly B-tree beats a hash map plus a sort. | Vendored. The sorted containers on deterministic output paths |
| [octocode](https://github.com/bgauryy/octocode-mcp) | Elision has to describe itself: every truncation carries its own denominator and a visible marker, so a caller can tell *shortened* from *all there is*. | The `shown_<noun>=` / `<noun>_capped=` disclosure vocabulary on every windowed listing, with the rule set that governs it in `src/pageview.h` and the machine-readable legend the document carries with it in `src/graphlegend.h` |
| [doctest](https://github.com/doctest/doctest) | A single-header test framework keeps the test build inside a zero-dependency contract. | Vendored. The C++ unit harnesses under `test/`, built only with `-DRIPWIRE_TESTS=ON` |

**Read and not folded, and worth naming because they are the near misses.** A scoped-snippet view
with scope breadcrumbs — the one rung of the detail ladder that is still missing here — was designed
against `grep-ast`'s TreeContext and never shipped. `graphify` contributed a measured head-to-head
comparison and no design lesson, so it appears in [`EVALS.md`](EVALS.md) §2 and not in §3a — it is
still in the surveyed table below, where a catalogued-and-not-borrowed-from tool belongs.

And [pdqsort](https://github.com/orlp/pdqsort) is the near miss that is actually *in the tree*: it is
vendored at `third_party/pdqsort.hpp`, licensed and attributed in [`THIRD_PARTY.md`](../THIRD_PARTY.md)
like every other vendored library — and **currently unused by any shipped target**. The ranking sorts
are a deterministic radix pass with a `std::sort` fallback below the radix threshold (`src/sortutil.h`),
chosen because a stable radix key is easier to make byte-identical across platforms than a
pattern-defeating quicksort's pivot choices. The only consumer of the pdqsort wrapper
(`src/infra/fastSort.h`) is a benchmark that no build target compiles. It stays vendored and stays
disclosed; it is not a lesson this tool folded, so it does not get a row above.

### 3b. Surveyed — the labelled landscape

**Surveyed is not borrowed-from.** Nothing in this table contributed a lesson to ripwire; the table
records that the field was catalogued before the claims in §3a were made, which is what makes "only
these twenty-seven" a meaningful statement rather than a shrug. Tools that *did* contribute are in
§3a — and in §2, where a tool's own paper is the citation — and none of them is repeated here, so no
tool is counted twice and the two counts add rather than nest. That is not a promise: arm (E6) of
`test/readmedriftcheck.sh` intersects the two tables' names and fails on any overlap, and arm (E7)
fails if any name appears twice *within* this table.

| Category | Tools surveyed | n |
| --- | --- | --- |
| IDE pair-programmers | Copilot, Cursor, Windsurf, Continue.dev, Tabnine, Codeium, Amazon Q Developer, JetBrains AI, Supermaven, Zed AI | 10 |
| Autonomous coding harnesses | Claude Code, Codex CLI, Devin, OpenHands, SWE-agent, Cline, RooCode, Goose | 8 |
| Agent orchestration frameworks | LangGraph, AutoGen, CrewAI, DSPy, Mastra | 5 |
| Code-mod and migration | OpenRewrite, Codemod, comby, jscodeshift, Sourcegraph Batch Changes | 5 |
| AI pull-request reviewers | CodeRabbit, Greptile, Graphite Diamond, Cursor Bugbot, Qodo Merge, DeepSource, Sourcery, Ellipsis, Bito, Korbit, Cubic, Baz, Entelligence, CodeAnt, Devlo, Trag, Panto, Macroscope | 18 |
| Deterministic linters and aggregators | ESLint, Biome, oxlint, Pylint, Cppcheck, Bandit, reviewdog, pre-commit, MegaLinter, Trunk, Qlty | 11 |
| Compile- or type-required analysis | SonarQube, Clang Static Analyzer, Infer, Clippy, golangci-lint, Staticcheck, SpotBugs, Coverity, Error Prone | 9 |
| Security and supply chain | Snyk, Socket, gitleaks, TruffleHog, Trivy, Checkov, KICS, Grype, Syft, OSV-Scanner, Dependabot, Renovate, sigstore, Pixee, ZeroPath, Mobb, Copilot Autofix | 17 |
| Type checkers | mypy, pyright, ty, pyrefly, tsgo, Sorbet, PHPStan, Psalm | 8 |
| Formal methods and contracts | Kani, CBMC, ESBMC, KLEE, Dafny, Verus, Frama-C, Why3, TLA+, Apalache, Alloy, SPARK, Lean, Rocq, JML | 15 |
| Property-based testing and fuzzing | Hypothesis, QuickCheck, fast-check, proptest, jqwik, AFL++, libFuzzer, OSS-Fuzz, Atheris, Jazzer, Hypofuzz | 11 |
| Mutation testing and coverage | Stryker, mutmut, PIT, cargo-mutants, coverage.py, llvm-cov, Launchable, BuildPulse | 8 |
| Sanitizers | AddressSanitizer, UndefinedBehaviorSanitizer, ThreadSanitizer, Valgrind | 4 |
| AI test generation | Qodo, EarlyAI, Diffblue, TestGen-LLM | 4 |
| Architecture linters | NDepend, Sonargraph, madge, import-linter, Lattix | 5 |
| Build systems and caching | Bazel, Buck2, Nx, Turborepo, Pants, sccache, ccache, BuildBuddy, Depot | 9 |
| Agent sandboxes and dev environments | E2B, Modal, Northflank, Daytona, Koyeb, Blaxel, Dev Containers, Codespaces, Gitpod, Nix, devbox | 11 |
| Version control and release | gh CLI, Graphite, Sapling, jujutsu, git-branchless, semantic-release, changesets | 7 |
| Code search engines | grep.app, OpenGrok, livegrep | 3 |
| Code intelligence and index formats | LSP, Kythe, LSIF, clangd | 4 |
| Repo-map and context-for-agents | CodeGraph, GitNexus, tree-sitter-analyzer, graphify, repowise, grepai, Repomix, gitingest, kit, claude-context, codanna, grep-ast | 12 |
| Debugging and time travel | gdb, lldb, rr, Pernosco, Replay.io, WinDbg-TTD, Sentry Autofix, Rollbar | 8 |
| Profilers | perf, py-spy, pprof, Coz, hyperfine, criterion | 6 |
| Agent memory and context compression | Mem0, Letta, Zep, cognee, headroom, LLMLingua | 6 |
| Evaluation and observability | LangSmith, Langfuse, Braintrust, Galileo, Arize, AgentOps, Promptfoo, Ragas, DeepEval, OpenTelemetry | 10 |
| Documentation and diagrams | Doxygen, Sphinx, Mintlify, Swimm, Mermaid, CodeSee | 6 |

---

## What is actually new

Nothing in the tables above. The parts that are not borrowed are the constraints imposed on them:

- **Determinism as a contract, not a tendency.** Two runs byte-identical, and a warm run byte-identical to a cold one, gated on every push.
- **Every count that cannot be proven total says so, in the output.** `counts_floor=`, `shown_*`, `*_capped=`, `amb=` — the vocabulary is defined by a legend the document carries with it.
- **An advertised number is an enumerated, gated number.** Including the three in this document's own header.
- **One compiled binary, no runtime dependencies, no embeddings, no server, no network.** Each of those is a thing several tools above have and this one does not, which is a trade and is described as one.

The combination is the contribution. The pieces are everybody's.

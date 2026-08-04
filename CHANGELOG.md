# Changelog

All notable changes to ripwire are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

**No release has been cut yet.** Everything below is unreleased and pre-1.0: the flag surface may
still change. When a flag is superseded it is deprecated with a stderr pointer at its replacement
and kept working; removals wait for a major version.

Every measured number in this file names its corpus and method. Numbers without a stated method are
not published here — see `docs/EVALS.md` for the instruments behind the headline figures.

---

## [Unreleased]

### Added — retrieval and ranking

- **`--for=TASK`, the task lens** — ranked signatures + metrics framed for reuse, matching doc
  comments and bodies rather than names alone.
- **Query-shape routing, on by default.** A deterministic, confidence-gated router picks name-exact
  BM25 when the query *names* a symbol (identifier syntax, or every content word is a symbol name)
  and subtoken+body BM25 otherwise, and prints which it chose and why in the header. `--no-route`
  restores the single-ranker behavior.
- **Query-mention anchoring, on by default.** A file, dotted module, or `Type.method` literally named
  in the task text — even inside a URL — is lifted to just below the top hit, and the header names
  what anchored. Byte-identical output when the text names nothing indexed. Disable per run with
  `--no-mention-boost`, or everywhere with `RIPWIRE_NO_MENTION=1`.
- **Doc-mention surfacing on `--for` / `--pack-task`, on by default.** A markdown document that names
  one of the task's top-resolved symbols in backticks is lifted into the bundle, ranked strictly
  below that symbol's own score — closing the case where the design note explains a symbol but shares
  no vocabulary with the query. Bounded (top-8 anchors, 2 docs per anchor, 6 docs total) and
  downweighted (0.55× the anchor's score) so code still dominates a code-shaped query. Byte-identical
  when nothing resolved has a mentioning document. Opt out with `--no-doc-mention` or
  `RIPWIRE_NO_DOC_MENTION=1`. Reuses the existing doc↔code edges `--mentions=SYM` already exposed —
  no new parser, no cache-format change.
- **`--adaptive`** cuts a result set at its relevance cliff (largest relative score gap) instead of a
  fixed *k*, with a floor of 5 and the existing top-K as the ceiling; the header reports what it kept.
- **`--recall=TASK`** returns the most relevant *documents* in full — memory notes, plans, designs,
  READMEs — with the header disclosing the true relevant count, what was shown, and every cut.
- **`--pack-task="TASK"`** — ranking, top bodies, caller signatures, notes and tests-to-run in one
  bundle under one budget.
- **`--exemplar`** returns the repository's best-in-class instance of what you are about to write,
  chosen by *role* (lowest cognitive complexity under a hard ceiling, then tested, then highest
  fan-in) rather than text similarity.
- **`--detail=N`** spends body tokens only on the top-N ranked symbols and emits signatures for the
  rest, in one call.
- **`--pack-signatures`** emits body-elided declaration skeletons. See `docs/EVALS.md` for the
  measured byte reduction, its root-neutralisation methodology, and the honest counterexample.

### Added — navigation and the call graph

- **`--callers` / `--callees` / `--uses` / `--impact` / `--around` / `--path` / `--connect`** — 1-hop
  in-edges, 1-hop out-edges, every statically resolvable use site (call/read/write/import/extends),
  the transitive blast radius, the ego graph, a directed shortest path, and the minimal connecting
  subgraph over 2..16 symbols (which finds the shared-caller join a directed path cannot).
- **`--graph-query=EXPR`** — a small closed expression language over the symbol graph: sources
  (`name("X")`, `all`), filters (`kind`, `cx`, `fanin`, `file`), bounded `callers`/`callees` closure,
  and `and`/`or`/`not` joins.
- **`--grep` / `--regex` / `--match`** — literal search, regex search, and tree-sitter structural
  (shape) queries, each reported with its enclosing symbol.
- **`--from-trace=FILE`** (`-` for stdin) maps a stack trace, sanitizer report, or compiler error onto
  indexed symbols, ranked innermost-first, with the innermost in-corpus symbol's body included.
- **`--external-surface`** lists names referenced but never defined in-corpus. A name called from
  several languages gets one row per language rather than a merged count, because the referencing
  file's language is what the row reports.

### Added — change safety and review

- **`--affected` / `--situ` / `--test-gate`** as one family: plumbing (changed files or a changed
  symbol → the tests that reach them), the mid-task report (blast radius + tests + co-change
  partners + hotspot alert), and the pre-PR gate (tests to run + the untested blast radius, exit 4
  if either obligation is non-empty).
- **`--exercises=TESTFILE`** is the inverse: the non-test symbols a test file transitively calls into.
- **`--edit-check=SYM`** — did this symbol's contract (parameters, publicness) change against HEAD,
  and which callers are now provably incompatible?
- **`--pr-context[=BASEREF]`** — per-file blast radius, tests to run, and hotspot flags for a diff.
- **`--merge-scout=REF1,REF2,…`** — pairwise conflict sites (same-symbol vs same-file) plus a
  suggested landing order.
- **`--quality-delta`** reports only what a change made *worse*, across ten measured failure modes,
  comparing against git HEAD. `--quality-ack` records a reviewed exception; `--ack-only=KIND` scopes
  the acknowledgement.
- **`--plan-lanes=N --task="GOAL"`** predicts, before a line is written, which parallel work lanes
  would collide. Deterministic JSON on stdout: per-lane file and symbol claims, blast radius, the
  tests each lane must run, and a landing order sorted fewest-conflicts-first. Conflict pairs are
  classified `conflicts`, `same_file_risk`, or `contract_touch`.
  - It **exits 0 even when conflicts are predicted** — conflicts are output, not a failure signal.
    Do not wire the exit code as a CI conflict gate.
  - Pre-hoc: no ref to resolve, no second ingest. ~0.1 s warm *(measured on this repository)*.
  - Read-only. The tool never writes the plan; redirecting stdout is the entire write path.
  - Lane claims are keyed on `(path, scope, name)`, not on symbol `id`. Rows still carry `id` for
    addressability, but it is `null` where it would be ambiguous, with `id_addressable` and
    `id_collides_with` stating the residual ambiguity. *(Measured on this repository: 343 `id` values
    name more than one symbol — 29.3% of symbol rows, 1426 colliding across files.)*

### Added — cross-branch archaeology

- **`--stray-content[=SUBSTR]`** — for each local ref, the lines its own divergent work authored that
  the live line does not have, with a `merged` / `superseded` / `unmerged` verdict. **`superseded` is
  the case `git cherry` structurally cannot see**: cherry compares commit ancestry, so a fix the live
  line re-implemented differently stays "unmerged" forever. Evidence is the *deletion site* — both
  sides diff the same base, so "ref R deleted base line L" and "HEAD deleted base line L" compare
  exactly, with no fuzzy matching. A pure-addition file falls back to a high-bar similarity lane, and
  every file row prints its raw `del=` / `redone=` / `sim=` numbers so the verdict is auditable.
- **`--whereis=SYM`** — which ref's tree defines or mentions a symbol, HEAD first, scanning each ref's
  full tree, with `on-head="0"` naming the case the verb exists for.
- **`--eval-stray=FILE`** — labelled verdict-accuracy evaluation (TSV `ref<TAB>verdict`), exit 3 on
  any regressed case. A confusion table rather than a ranked-set metric, because a verdict verb
  classifies. Supersession thresholds were chosen against hand-labelled branches, so changing one is
  an experiment rather than a guess.
- Both cross-branch verbs are keyed by **blob sha**. Branches off one trunk share nearly all blobs,
  and every byte-level fact is a pure function of blob content, so blobs stream through one
  `git cat-file --batch` per run and are reduced to fixed-size facts on arrival — peak memory is
  bounded by the facts, not by the trees. *(Measured on a 35-branch repository: `--whereis` read 4,445
  distinct blobs where HEAD's tree alone holds 2,897 — 35 refs for 1.53× one tree, 1.6 s.
  `--stray-content` is diff-scoped: 443 blobs, 2.2 s.)* Both use only `cat-file`, `diff`, `ls-tree`
  and `merge-base` — read-only by construction.

### Added — dark code and feature flags

- **`--flags[=SUBSTR]`** — one report over what is built but not switched on: `#ifndef`/`#define`
  header gates, CMake `option()`s, and `getenv()` reads, with kind, default, guarded regions and LOC,
  and read sites, dark entries first. *(On the motivating private repository it named 94 dark gates
  of 102.)*
  - When a name is both a header gate and a CMake option, **the CMake default wins** — it is what the
    build actually passes — and the losing definition is shown as an `<also>` row, so the
    contradiction is surfaced rather than silently resolved.
  - Alias chains resolve (`#define F_WALLS F_ALL`): a child inherits its master's default and rolls
    its guarded size up, so a master switch shows its alias count instead of a misleading `loc="0"`.
- **`--flags --flip=NAME`** answers the follow-up: if this one gate flips, what becomes live and what
  covers it? Reports the code that becomes live (`#if` regions **and** C++ branch sites), the hosts,
  downstream and dependent symbols, the tests reaching those hosts, and **`untested`** — the hosts no
  test reaches. Flipping works in both alias directions, and three-level chains resolve correctly.
  - **Value-style gates are followed, not just preprocessor regions.** A gate consumed as
    `inline constexpr bool kWalls = FLAG != 0;` and then guarded with `if constexpr` guards a C++
    *branch*, not an `#if` region; such a gate previously reported `regions="0"` and a naive flip
    analysis would have answered "nothing lights up". *(Measured on the motivating repository: one
    gate family with 11 aliases and 0 regions yields 43 branch sites across 11 host symbols, verified
    row-for-row against an independent whole-word grep.)*
  - Flip semantics are stated per gate kind. A CMake gate becomes a `-DNAME=1` compile definition, so
    its C++ radius matches the compile case — but it also steers the build graph (adding whole
    translation units), and those sites are reported as build rows and **explicitly not followed**.
    An environment gate is marked `runtime="1"`: with no delimited region, its hosts are the symbols
    that consult the variable.

### Added — documentation drift

- **`--doc-drift[=SUBSTR]`** verifies the *checkable* anchors in every markdown file against the live
  index and reports only what no longer holds. Four anchor kinds: `file:line` references (split into
  `missing-file`, `past-eof`, and `line-moved` with `got=` naming the symbol now at that line),
  backticked symbol mentions (`undefined`), `= N` constants (`const-value`), and `[N]` array extents
  (`array-extent`).
  - **Precision is the design constraint and every lane deliberately under-reports.** A name counts as
    stale only if it occurs nowhere in any non-markdown file as an identifier token, and the presence
    corpus is the index *plus* build files, shaders and config — so a shader function or a CMake
    `option()` is never reported missing. A mention must share its line with a name the repository
    does define; a foreign-scoped mention is never treated as ours; a number is compared only against
    a declaration-shaped literal the corpus binds uniquely; fenced code blocks are treated as
    illustrations. *(Measured while tightening on this repository: the naive version emitted 329 rows,
    roughly 90% of the mention lane being library names and hypothetical examples; the shipped rules
    bring it to 110.)*
  - **`checked + unchecked == anchors` always holds**, and every declined check is named and explained.
  - Stated non-goal: prose, status lines and dates are not checked, and the verb never claims otherwise.

### Added — the git-history oracle

- **`--with-history`** (opt-in, off by default) on `--doc-drift` and `--whereis` answers "was this name
  ever in this repository, and when did it leave?"
  - `--doc-drift --with-history` splits its weakest lane three ways instead of blanket-reporting
    `undefined`: `why="deleted"` with the commit, date and file; `unchecked r="never-in-history"`; and
    `unchecked r="history-no-answer"`.
  - `--whereis --with-history` gains a `<fate>` row (`v="never"`, or `v="removed"` with commit, date
    and path) — something a tree scan structurally cannot produce, since a scan can only find content
    some ref still carries.
  - Both emit a row stating exactly what the walk did (`probed=`, `head=`, `commits=`,
    `removed-names=`, and `truncated=` when bounded).
  - **Speed.** `git log -S` has the right semantics but answers one name per process: ~126 s for 247
    candidate names on a 2,965-file application repository (~85 s even rev-range-bounded). The shipped
    probe reproduces those semantics with a single `git log --no-merges -p -U0 --no-renames` walk that
    tokenizes removed lines: **3.0 s** on that repository, **0.83 s** on this one, and O(1) in the
    number of names. `git log -G` was rejected on semantics — it matches diff *text*, so a reindent
    counts — and a `-G` alternation prefilter measured ~183 s, slower than no filter at all.
  - **Precision.** On that 2,965-file repository, 325 `undefined` rows became 80 `deleted` + 243
    `never-in-history` + 2 `history-no-answer` (75% reclassified); total drift 575 → 330, clean docs
    659 → 713. On this repository, 11 → 3 `deleted` + 8 `never-in-history`, drift 119 → 111. Every
    true positive survived, and no other drift lane moved on either repository.
  - **Cost.** Flagless paths are untouched. Under the flag, cold 0.63 s / 3.83 s and warm 0.130 s /
    0.664 s on the two repositories — about +24 ms and +40 ms over default. Results are memoized per
    (repository, HEAD sha); a commit sha is immutable, so the cache cannot go stale. The cached blob
    covers the whole repository, so `--whereis` reuses whatever `--doc-drift` built. Warm output is
    asserted byte-identical to cold.
  - **Stated limits.** It walks HEAD's own history, so a name that only ever lived on an unmerged
    branch reads as *never here* — that is what `--whereis`'s tree scan is for. Merge-only deletions
    are not seen. Evidence is a removed *line*, so a name last removed from a document is cited at
    that document (a code site is preferred when one exists). A repository past the walk bound reports
    `truncated="1"` and answers `unknown`, never `never`; names below the probe's minimum tracked
    length also get `unknown`, enforced at one choke point so absence is never readable as proof.

### Added — languages

- **TypeScript gains three definition shapes that only a real repo produces.** Validated by mapping
  `github.com/openclaw/openclaw` @`1aedd8f3` (24 658 `.ts` files, 261 760 symbols, 2026-08-04) and
  diffing the emitted `n="` set against a ground truth enumerated independently — grep over *blanked*
  source (comments and template literals stripped; that repo embeds Kotlin, Swift and JS fixtures
  inside `String.raw` templates, which otherwise fake thousands of phantom hits), then confirmed at
  AST level with `--match`. Three shapes came back at ~0 % recall, none of them present in any
  fixture: `abstract_method_signature` (76 sites) — an abstract base published its own name and
  nothing a caller could bind to; `public_field_definition` bound to an arrow (287 sites) — the
  bound-method idiom, which is a class's callable surface exactly as `method_definition` is; and a
  declarator whose value is an `as`/`satisfies` cast *wrapping* the arrow (105 sites) — the
  lazy-facade idiom that openclaw's entire public `src/plugin-sdk/` surface is written in, so every
  one of those was an exported API entry point `--for` structurally could not surface. All three now
  extract: +468 symbols and +593 edges on that corpus, **0 removed**, and byte-identical output on
  non-TypeScript trees. Deliberately still out: the object-literal `pair` form of the same syntax
  (>5000 sites there — a `--match` floor — overwhelmingly inline callbacks and mock tables, not a
  navigable surface). Known limits, disclosed in the gate: ambient `declare const/let/var` bindings
  (37 sites) do not extract, and `declare module "x"` / `declare namespace X` *container* names are
  not symbols — their members are, which is what navigation needs. Gate: `test/tsshapecheck.sh`.
- **Known limit, measured and disclosed:** the pinned `tree-sitter-typescript` (v0.23.2) cannot parse
  `typeof import("…")` once it appears in a nested type position — inside a parenthesized type
  (`(typeof import("./m.js").xs)[number]`, 235 sites) or a call's type arguments
  (`importOriginal<typeof import("./m.js")>()`, 2 087 sites, the vitest mock idiom). 1 222 of
  openclaw's 24 658 `.ts` files contain at least one. The *cost* is far smaller than the site count,
  which is the reason this is disclosed rather than paid for with a grammar-pin bump: tree-sitter
  error recovery scopes the loss to the enclosing declaration, so across all 1 222 files the total is
  ~15 definitions out of 261 760 (type-alias recall 1 607/1 614 and function recall 6 805/6 813 *within
  the affected files*). Pinned in both directions by `test/tsshapecheck.sh` §4d — if a future grammar
  bump fixes the parse, that arm fires.
- **CUDA (`.cu`/`.cuh`) is indexed**, parsed with the vendored `tree-sitter-cuda` grammar (v0.21.1,
  a generated superset of tree-sitter-cpp) under the C++ tags — no CUDA-specific query patterns,
  because the grammar aliases `kernel_call_expression` to `call_expression`. *(Measured before
  adopting, 2026-08-04 probe on the fixture now at `test/cudafix/`: under the plain C++ grammar all
  12 definitions survived error recovery, but every `kernel<<<grid, block>>>( … )` launch site
  produced no call reference — `--callers` of a kernel returned 0 — and a `__constant__` module
  table failed to extract. Losing every host→kernel edge is the Metal failure mode over again, which
  is why CUDA gets a real grammar where Metal measurably did not need one.)* `.cu`/`.cuh` map to the
  C++ language, not a language of their own, so dual-compile headers (`#ifdef __CUDACC__`) resolve
  from both the host and device halves. Known limit, disclosed in the gate: a `__constant__ float
  T[64];` module table still does not extract — the shared C++ tags constant pattern keys on
  `const`/`constexpr`, not the `__constant__` qualifier (plain `constexpr` constants in `.cu`/`.cuh`
  do extract). Gate: `test/cudacheck.sh`.
- **Qualified-call resolution across C++, Rust, C#, TypeScript, JavaScript, Java and Objective-C.**
  C++ gained qualified calls of three or more segments and explicit-template calls at any depth (with
  cast exclusion), canonically precise; Rust gained scoped, turbofish and `Self::` calls with a real
  canonical tier and a file-module guard; C# gained the `?.` family; TypeScript, JavaScript and Java
  gained qualified `new`; Objective-C reached field parity. Canonical multi-match now feeds the
  ambiguity accounting rather than being silently resolved, in every language.
- **Go qualified calls are honestly rejected and fenced** rather than half-resolved.
- **Metal Shading Language (`.metal`) is indexed**, parsed with the C++ grammar and C++ tags rather
  than a separate grammar. *(Measured on 45 real shaders, 864 KB, before adopting: ERROR-node byte
  rate 0.811% under the C++ grammar vs 12.3% under the C grammar — 15× worse; real C++ in the same
  repository: 0.000%. All 249 distinct entry points in that corpus are captured: 663 definitions,
  6,283 call references.)* `.metal` maps to the C++ language rather than a language of its own,
  because MSL and its C++/Objective-C++ host share one call namespace through dual-compile headers —
  which is the entire point of indexing shaders. *Known residual, documented rather than hidden:* an
  anonymous `enum : uint { … }` recovers as a named enum, minting 18 junk `t="type"` symbols named
  `uint` across those 45 files, 0.04% of that repository's 47,074-symbol index.
- **Module-level settings constants are first-class ranked `var` symbols in TypeScript, JavaScript,
  Rust, Ruby, Java, C#, C and C++** (the r3 head-to-head's q10 loss — a settings/feature-flag table
  in those languages previously contributed zero rankable symbols, so `--for` structurally could not
  surface it). Scoped to settings-shaped constants, not every literal: module/file/namespace-level
  capture only, gated on SCREAMING_SNAKE names for the convention-based grammars (Rust `const`/
  `static` items are constants by construction and are taken as-is). Python (case-blind module
  assignments, vendored upstream) and Go (CamelCase consts) were already captured and are unchanged
  — the r3 audit's "not extracted at all" reading is corrected in that report's addendum. Gate:
  `test/constcheck.sh`, written red-first against the pre-fix binary (18 red assertions at
  b6068c3).
- The current set: C++, C, Objective-C/Objective-C++, Metal, Python, TypeScript, JavaScript, Java,
  Ruby, Bash, Go, Rust, Swift, C#, plus JSON configuration keys.

### Added — output shaping, honesty and paging

- **`counts_floor="1"`** on `--callers` / `--callees` / `--uses` / `--impact` / `--edit-check` and
  further surfaces. Every such count is a **floor, never a total**: the call graph is extracted from
  source text by name, so dynamic dispatch, callbacks and function pointers, macro-generated call
  sites, and declarations that parse without a call expression contribute no edge. **Read a 0 as
  "none found", never as "none exists".** Each verb's legend also states its counting *unit* — those
  five count distinct (caller, callee) pairs, while `--uses` counts call sites.
- **Generated documents rank last in `--recall` by default.** A document that declares itself
  generated in its first lines, or is both ≥5× the median document's size and mostly fenced quoted
  output, is demoted — a capture that quotes every term otherwise wins every query on lexical match
  alone. It is never dropped: it still wins when nothing else matches, says why on its own line, and
  the header tallies how many were demoted.
- **One paging vocabulary across the verbs that page** — `--limit=N` and `--offset=M`, with the verbs
  that cannot page refusing rather than silently ignoring them.
- **`--token-budget=N` has two documented personalities.** On the default map, `--query` and
  `--recall` it is a CI **gate**: exit 3 if the emitted document's estimated tokens exceed N, with
  nothing of the artifact reaching stdout — only a record naming what was withheld against the budget.
  On `--for`, `--pack-task` and `--from-trace` it **shapes** instead, overriding that lens's own
  default payload budget, always exit 0. The estimate is calibrated against a public tokenizer,
  never exact.
- **`--max-tokens=N` shapes the map to fit** a deliberately conservative byte ceiling and discloses
  both the asked-for N and the honoured byte figure. Because the ceiling and the gate are measured in
  different units, the same N on both flags is not a tautology — and the shaped map says
  `over_ceiling=1` rather than overshooting in silence when even one symbol exceeds the floor.
- **`--order=stable | important-first | important-last`** is the canonical emit-order flag. `stable`
  gives path/ID order for provider KV-cache hits across re-runs; `important-last` puts the
  highest-ranked content at the end for recency-biased readers. Large default maps auto-flip to
  `important-last` past roughly half of a nominal 32K window unless the mode is given explicitly.
- **`--format=columnar` / `--format=candidates` / `--json`** alternate dialects, with an unknown value
  refusing and naming the legal set.
- **Did-you-mean on every selector**, computed as a real edit distance: a `name("X")` literal or a
  `--callers=SYM` that matches no indexed symbol **refuses** with a suggestion. A typo is not a
  `count=0`; a query whose names all resolve but that selects nothing still reports `count="0"`,
  because that is a measurement.
- **`--version` / `-v`** prints the version plus compiler id/version and build type. The version
  string has exactly one source of truth (the CMake project version), and drift between the printed
  and the declared version is gated.
- **`changed="N"` in the `--map-diff` header** — the teleport-seed file count, so a caller can tell a
  real diff run from a clean-tree or no-git degrade without shelling out to git a second time. Reads
  `0` on a clean tree, and is omitted on every other verb so it costs nothing.
- **`est_tokens="N"` on shaped `--for` output** so the delivered bundle's fit is checkable.

### Added — architecture, quality and structure

- **`--metrics`, `--deps`, `--hotspots`, `--clones`, `--cochange`, `--lint`, `--lint-rules=DIR`,
  `--communities`, `--community=ID`, `--zoom`, `--seams`, `--owners`, `--dead-code`, `--report`,
  `--mermaid`, `--tree`, `--html[=FILE]`** — complexity × churn hotspots, duplicate bodies, hidden
  co-change coupling, AST lint with user-supplied rules, call-graph modules and their nested zoom,
  untested cross-module seams, ownership and bus-factor risk, and a self-contained force-directed
  HTML call graph with no CDN.
- **`--arch=RULES`** with a committed baseline gates layering violations in CI.
- **Multi-root workspaces**: `ripwire dir1 dir2 [dir3 …]` merges 2..16 checkouts into one labeled
  graph. Cross-root edges are created **only on explicit evidence** — a path-resolved include or
  import, or an FFI binding — so same-name symbols in unrelated repositories stay unlinked. Root order
  on the command line is irrelevant. The single-root verbs (`--quality-delta`, `--test-gate`, the
  eval family, `--arch` baselines, `--pr-context`) stay single-root; run them per root.
- **`--export=cc.json:FILE`** and **`--index-out`** write the index out for reuse; **`--scip=FILE`**
  overlays a precise SCIP index where one exists, and a missing file degrades honestly rather than
  failing.
- **`--batch=FILE`** answers several lookups in one round trip.
- **`--note-add="SYM_or_path: text"`** commits a gotcha to `.ripwire_notes`, auto-surfaced whenever
  `--for` or `--expand` later emits that symbol; `--notes` lists them.
- **`--doctor`** diagnoses a stale binary, a stale cache, or a missing tool.

### Added — MCP server and agent wiring

- **`ripwire wrap <agent>`** prints the recipe to wire the tool into a coding agent as an MCP server.
- **30 MCP verbs**: 15 read verbs, 12 flagship-reflex verbs, and 3 edit verbs. Each is a thin front
  door onto the same computation *and the same renderer* as its CLI sibling — one output shape, two
  surfaces. `find_referencing_symbols` is kept and documented relative to `impact` and `uses` (1-hop
  calls only; `impact` is the full transitive radius, `uses` also catches read/write/import sites).
- **`--scan-skill=FILE` / `--scan-skills=DIR`** scan agent skill files for prompt-injection,
  exfiltration and path-traversal shapes before you install them.

### Added — evaluation instruments

- **A held-out retrieval eval** (`bench/recalleval/`) with a published labeling protocol: every gold
  label was authored by *reading the source*, never by transcribing the ranker's own output, so the
  eval is allowed to say the current ranker is wrong. `--eval`, `--eval-retrieval`, `--eval-stray`
  and `--eval-skills` run the instruments from the binary.
- **A differential argv harness** that replays a large fixed set of command lines against two binaries
  and requires every diff to be provably intended.
- See `docs/EVALS.md` for what each instrument measures and every published number's provenance.

### Changed

- **BREAKING (build): the default build is architecture-neutral.** It previously hardcoded
  `-O2 -mcpu=apple-m1 -ffast-math -fno-finite-math-only` unconditionally, which was a hard
  configure/compile failure on any non-Apple-Silicon target — Linux x86-64 and aarch64, Intel macOS,
  any cross build — because clang rejects `-mcpu=apple-m1` as an unknown target CPU. `-mcpu=apple-m1`
  is now applied only when configuring on Apple Silicon; elsewhere the default is plain
  `-O2 -ffast-math -fno-finite-math-only`. `RIPWIRE_NATIVE=ON` (`-march=native`, a dev-machine opt-in)
  is unchanged, as is the PageRank no-reassociation contract and the sanitizer target.
- **BREAKING (output): canonical symbol IDs corrected.** A parse-recovery artifact published a
  function's *return type* as its class scope. *(Measured on one repository: 80 wrong canonical IDs in
  ordinary C++ corrected, plus 5 newly-correct IDs where the real enclosing namespace took over.)*
  Anything scripted against the old IDs will see different values. Valid C++ never triggered the
  guard, so clean parses are unaffected.
- **BREAKING (caches): parser-version bumps invalidate warm caches.** Several extraction changes moved
  the parser version, so an upgrade costs one cold re-parse. The on-disk record *shape* did not
  change, so the cache format version did not move.
- **Graph shape: C-family `#import` now produces an include edge** — the edge that links a shader to
  its headers. `#pragma`, `#error` and `#warning`, which share the same parse node type, are excluded.
  `#include` and `#import` share one path extractor so they cannot drift apart, and a trailing comment
  on the directive line no longer leaks into the resolved path.
- **`--test-gate` obligations are computed per changed *symbol*, not per changed file.** A change that
  owns one symbol inside a 3,000-line file is no longer charged that whole file's test obligations.
- **Ranking: fixture and generated-content paths are de-prioritized.** A measured change, published
  with its held-out numbers in `docs/EVALS.md`, not a hand-tuned weight.
- **`--map-diff` documentation corrected.** The help text and README claimed it filtered to symbols
  changed against git HEAD. It never did: it emits the **full map, re-ranked with a PageRank teleport
  toward git-changed files**, so every file can still appear and a clean tree is byte-identical to the
  default map. `--pr-context` is the actually-filtered only-changed-files report. *(No code changed;
  expectations do.)*
- **`--detail=N` is now accepted with `--flags`, `--stray-content` and `--whereis`**, where it lifts
  the display cap — the same meaning it has on `--for`. It was previously rejected by the
  companion-flag guard.
- **`--query=TERMS` is relabelled "raw BM25 ranking (debug); use `--for`"** — fully functional, no
  longer presented as the primary retrieval entry point.
- **`--order` supersedes `--stable`, `--most-important-last` and `--no-auto-order`**, which remain
  fully functional as hidden aliases and print a one-line stderr deprecation the first time they are
  used. `--no-stable` is unrelated and untouched.
- **`--pack-top-n` and `--pack-budget-bytes`** behave unchanged but now print a stderr line naming
  `--pack-task` and `--detail` as the superseding one-call flags.
- **`--anchor` and `--cochange-boost` are negative-result experiments** — their own records show no
  confirmed recall lift. Both are dropped from `--help` and refuse with an "experimental" message
  unless `RIPWIRE_DEV=1` is set, keeping them reachable for evaluation work without advertising them
  as supported surface.
- **MCP tool count grew to 30**; the `flags` verb gained an optional `symbol` argument for the flip
  view, deliberately an argument on the existing verb rather than a new verb.
- **`install.sh` no longer hardcodes a Homebrew prefix**, which was wrong on Intel macOS and on any
  machine without Homebrew. It detects `brew --prefix` when brew is on `PATH`, honours an explicit
  install-prefix override, and otherwise falls back to `~/.local`. *(Existing installs may land in a
  different prefix than before.)*
- **Corrected performance claims.** A frequently-quoted "75× warm re-runs" was the incremental cache's
  *parse-phase* figure quoted without that qualifier; end-to-end warm command latency measures
  **8.2×** *(large private C++ corpus, 2,340 files; historical private corpus, not publicly
  reproducible; measured 2026-07-22)*. An unlabelled "`--edit-check` ~26 ms" was corpus-specific; the
  labelled figures are **43 ms at 592 files** and **114 ms at 2,340 files**.

### Fixed

- **Rust whole-impl span** — an `impl` block's span covered the whole block, minting phantom clone
  reports.
- **Merge-aware churn.** The churn walks now follow merges, so a history landed through merge commits
  is no longer under-counted.
- **False zeros closed across the count surfaces**: a count that cannot be a total is labelled a
  floor, and a count whose unit differs from its neighbours says so, on every verb that emits one.
- **Host attribution is innermost-wins.** Plain span intersection could credit a 40-line function
  above a 3-line one as the host of the same `#if` region (tree-sitter definition extents over-reach
  in preprocessor-heavy Objective-C++). Hosts are now the definitions wholly inside the region plus
  the *innermost* definition containing its opening line — the same rule `--grep`'s `in=` uses, so a
  flip host and a grep hit can never disagree.
- **Gate shadowing.** A file that declares its own constant of the same name shadows the gate's, as
  normal C++ scoping requires. Without this, short house-style names cross-wired: *measured on one
  repository, a weapons header's `constexpr float kSpeed` / `constexpr int kTurns` contributed six
  phantom branch sites and four phantom hosts to an unrelated gate.* The value lane now also runs on
  C-family source only — an extension denylist had previously let a committed HTML report that merely
  quoted a gate name through.
- **`--flags` no longer reports gates from nested worktrees or build output as the repository's own.**
  The second directory walk that `--flags` needs (CMake files are never ingested) disagreed with the
  crawl about what counts as source. *(Measured: a stale worktree copy inverted a real option's
  reported default.)*
- **Ingest robustness.** Large or degenerately-nested JSON is skipped with a stderr note: the JSON
  lane indexes configuration keys, and a big or `[[[[…`-nested file is data or a test corpus — the
  former explodes the symbol table, the latter drives tree-sitter's error recovery superlinear
  (43 s measured on a 100 KB torture file). Both were found live by benchmarking against real
  upstream repositories.
- **CRLF-encoded files** are handled identically to LF in the flag value lane.
- **Reproducible dependency pinning.** All 15 fetched grammar, tree-sitter and test-framework
  dependencies previously pinned mutable tags, which can be force-moved server-side. Every one is now
  pinned to the commit SHA that tag resolved to, with the human-legible tag kept as a trailing comment.

### Security

- **Credential redaction is on by default** — credential-shaped literals are removed from emitted
  bodies and signatures unless you opt out with **`--no-redact`**. There is no opt-IN spelling,
  because the behaviour is not opt-in. The redaction fixtures that necessarily carry synthetic
  credentials are enumerated in `test/README.md` and enforced by a gate.

### Known limits

These are stated, not hidden, and each is measurable from the output itself:

- **Call edges are heuristic and name-based.** Dynamic dispatch, callbacks, and macro-generated call
  sites produce no edge. A high-ranking symbol with no call edges may be a dispatch hub, not a leaf.
- **`amb="K"`** on a symbol means K of its calls hit a name with multiple definitions and the resolver
  guessed. The header's `ambiguous=N` is the call-graph completeness gauge — read the source when
  which-target matters.
- **Token estimates are calibrated, never exact.** The `--pr-context` estimate in particular is known
  to under-charge relative to a real tokenizer; treat it as a lower bound.
- **`--for`'s `--token-budget` shaping is not strictly binding at very small budgets** — the header
  floor (envelope, legend, verbatim task echo) is bytes no trim can shrink, and the lens labels the
  result `over_ceiling` rather than claiming a trim it did not perform.
- **Release automation has never been executed end-to-end.** The tag-triggered build-and-attach
  workflow and the release-binary installer are untested until the first real tag push.

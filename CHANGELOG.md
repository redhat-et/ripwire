# Changelog

All notable changes to ripwire are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Everything here is pre-1.0: the flag surface may still change. When a flag is superseded it is
deprecated with a stderr pointer at its replacement and kept working; removals wait for a major
version. A `v0.1.0` tag exists (2026-08-02) but its GitHub Release carries no binaries; **v0.2.0 is
the first release with published, SHA-256-checked archives**, and it contains everything below.

Every measured number in this file names its corpus and method. Numbers without a stated method are
not published here — see `docs/EVALS.md` for the instruments behind the headline figures.

---

## [Unreleased]

### Added — `--plan-lanes` now recommends a Codex model and reasoning effort per lane

Every lane carries an advisory `execution` object with a current Codex model, reasoning effort, the
deterministic policy rule that selected them, and the complete structural signals used by that rule.
The recommendation labels itself `basis="structural-only"`; partial test evidence, name-based call-graph
resolution, and truncated evidence are disclosed as in-band caveats for the orchestrator to override.
The additive JSON field keeps the top-level schema at `v: 1` and versions its policy independently as
`codex-lane/v1`.

### Changed — `.gitignore` is honoured by default; `--no-ignore` restores the old walk

ripwire is named for ripgrep, whose defining default is that ignored files are not searched. The crawl
walked them. In a git work tree it now consults git's own ignore rules and skips what the repository
already declared uninteresting — `node_modules/`, `.venv/`, `target/`, `build/`, `dist/`, whatever the
repo says — and **`--no-ignore` restores the previous behaviour exactly**.

Measured on this repository's own root with no `--exclude`, three checkouts under a gitignored
`bench/external/`: `files=` 8,674 → **1,522**, cold 2.81 s → **0.52 s**, warm 0.63 s → **0.10 s**, and
the result agrees to the file with the hand-written `--exclude=bench/external` the tool used to need.
The ignore lookup is one `git ls-files ... --directory` per root: 0.020 s (ugrep), 0.030 s (rocksdb),
0.150 s (duckdb), 0.032 s (this root) — `bench/PROFILE.md` carries the ledger.

Nothing is dropped silently. The map header states `ignored_files=` (files the rules covered, exact)
and `ignored_dirs=` (subtrees they pruned — the walk stopped there, so their contents are UNKNOWN, not
zero); both are ABSENT when the rules dropped nothing, so a tree with nothing ignored is byte-identical
to what it produced before. `--skipped` rows the ignored set and names the mode in `ignore_mode=`.
`--exclude` composes on top, and a multi-root run applies the rules per root.

Four situations keep the full walk, and `--skipped`'s `ignore_mode=` says which applied: `git` (rules
consulted), `off` (`--no-ignore`), `unavailable` (no git work tree at this root, or no git binary), and
`root-ignored` — the root is ITSELF inside an ignored subtree (`ripwire build/` in a repo that ignores
`build/`), where honouring the rules literally would hand back an empty map for a directory you pointed
at on purpose. A tracked file that happens to match a `.gitignore` pattern stays indexed, because git
ignores nothing it tracks.

### Changed — one warm cache per tree, and a narrower run no longer throws the wider one's work away

The warm-by-default cache keys on the tree's path and the verb class, and deliberately not on
`--exclude` or `--max-file-size`: one blob per tree, shared by every configuration you run against it.
That sharing had a hole. A run with an `--exclude` deserialised the WHOLE blob — including the records
for the files it had just excluded — and then, if anything had changed, rewrote the blob with only its
own file set. The next run without that `--exclude` found those files missing and re-parsed them from
scratch. Alternating `ripwire .` with `ripwire . --exclude=vendored` therefore paid a cold parse in one
direction and a superset deserialise in the other, every time.

The blob now carries a record offset table, so a run reads only the records for the files it actually
crawled, and a save carries over — byte for byte — the records for files it did not. The cache only ever
grows toward the union of the configurations that share it, so switching between them is free in both
directions.

Measured on a 31,000-file tree (1,000 files kept, 30,000 excluded), comparing `d8fa59c` with this
change. A warm excluded run: **0.06–0.09 s → 0.01 s**, now indistinguishable from that configuration
having its own private `--cache=PATH` blob. The run after a changed excluded run: **30,000 files
re-parsed in 0.96 s → 0 files re-parsed in 0.27 s**. The costs, both real: the table adds **3.3%** to the
blob (32 bytes per file), and a save that has to carry 30,000 records over takes 0.13–0.40 s where the
old truncating save took 0.02 s — which is the trade, because the truncation is what made the next run
cost 0.96 s. Full ledger in `bench/PROFILE.md`; the bands, including the earlier attempt at this that was
measured and reverted, in `docs/EVALS.md` under "The auto-cache key ignores `--exclude`".

Cache blobs from earlier versions are rejected and rebuilt on the next run, as with every format change:
no action needed, one cold parse. `RIPWIRE_CACHE_STATS=1` gains `cached_records=` and `blob_entries=`.
New gate: `test/cacheoffsetcheck.sh`.

### Added — `--slice` reaching definitions are flow-sensitive inside one definition (C-family, Python)

Every use row of `--slice=SYM:VAR` (and the MCP `slice` verb) now carries `rd=` — the lines of the defs
that reach it — computed by one structural pass over the definition's statement tree: a def is killed by
the next unconditional def of its binding on every path, defs join at `if`/`elif`/`else`, `switch` (cases
fall through, no `default` keeps the no-case path), a loop's back-edge (fixpoint), `try` handlers and
`finally`, `for`/`while ... else`, `match` and a build-dependent `#ifdef`; `return`/`break`/`continue`/
`throw`/`raise` end their path. The root says which rule is in force — `reach="cfg"` for C/C++/ObjC and
Python, `reach="linear"` (source order, nothing joins) for JS/TS, Go, Java, Rust until their control
tables are fixture-verified. `--slice-flow` and `--since` read the same reach table, so the rows, the flow
walk and the dependence diff can never disagree about an edge. The unit is the statement (uses read the
entering state, defs apply after); every construct the walk does not branch on — `?:`, short-circuit,
conditional expression/comprehension, lambda/closure/nested def/class bodies, `goto`, `global`/`nonlocal`,
the try handler's entry, aliases — is named in the legend instead of guessed. Registered and measured in
`docs/EVALS.md` ("Flow-sensitive slice in the small"): 0 wrong of 85 hand-written sentinel use rows across
53 functions, and the 57-commit `--since` labelled set unchanged at 35/35 and 22/22. Gate:
`test/sliceflowsenscheck.sh`.
### Fixed — `--expand` no longer takes minutes on a file whose lines are hundreds of kilobytes

Secret redaction (`redactSecrets`, on by default at every body-emission seam) was quadratic in LINE
length. Its low-precision `[A-Za-z0-9+/=_\-]{32,}` rule re-derived three position-independent values at
every cursor: the enclosing line's boundaries, that line's credential-keyword verdict, and — through a
greedy `regex_search` anchored at the cursor — the whole character-class run it sits in. Ordinary source
has ~100-byte lines and never noticed. A minified or vendored bundle is nothing but huge lines, and
`--expand` hands one to this path whole while pricing its whole-file candidate.

Measured on babel's `.yarn/releases/yarn-3.1.0.cjs` (2,196,921 bytes over 768 lines): a single `--expand`
selector burned 196.7 s of CPU without finishing under a manual timeout, and an unattended run was killed
at 1,343.9 s of user CPU with a still-empty output file. It now answers in 0.46 s warm. On a
self-contained 20 KB-single-line fixture, 23.02 s → 0.017 s. Each of the three values is now computed
once per line or per run, which makes the sweep linear.

This is an output no-op — same matches, same gate verdicts, same bytes — verified byte-identical on
stdout, stderr and exit code against the pre-change binary over 24 corpora (20 of them external
multi-language snapshots) × 5 verb shapes. New gate: `test/redactfixcheck.sh`. Ledger row and the
`sample(1)` breakdown in `bench/PROFILE.md`.

## [0.2.2] — 2026-08-09

### Fixed — a local variable that shadows a function name no longer steals that function's use-sites

`--uses` attributed a local's read/write sites to a same-named function (13 false sites on one
measured query). A local binding now claims its own scope, and a `using ns::name;` re-export emits
the `role="import"` row it never produced. Measured against a `scip-clang` oracle on this
repository, site-level precision/recall moved 0.9046/0.9285 → 0.9136/0.9412, with the worst
motivating query going 0.6579 → 0.9615 and three others reaching 1.0000. The suppression took three
refutation rounds to get right, and the third found a **recall loss the first cut introduced**: a
genuine call appearing ABOVE the shadowing local vanished entirely, because the suppression span
started at the enclosing block rather than at the declaration point. It now begins at the end of the
complete declarator, C++ [basic.scope.pdecl]. Fixture corpora, per-round verdicts and the verifier
history: `bench/fixround/RESULTS.md`.

### Fixed — five more shapes that invented or destroyed references

A declared name no longer leaks as a read of the symbol it shadows under a defaulted parameter, a
parameter pack, or an attributed declarator. A bare-identifier assignment (`x = y;`) mints a
function-pointer binding only when the file's own declarations allow it, and a class-typed copy no
longer does — closing a bug that was **losing real call edges**, not merely adding false rows: a
bogus binding tombstoned a genuine same-named file-scope binding corpus-wide. Zero call-edge loss
verified on two corpora (10,742 edges here, 39,741 on a 2,376-file ObjC++ tree, byte-identical
before and after); 59 false `--uses` sites removed with zero sites gained. One deliberate behaviour
change is disclosed in the count-floor legend: a variable whose function-pointer typedef lives in a
HEADER is now missed, because same-file alias evidence cannot distinguish it from a value copy.

### Changed — `--uses` states that a bare type mention is not a use-site

The role list is the whole vocabulary. Naming a symbol as a type in a signature, a declaration or a
template argument contributes no row, so a caller that only names it as a type is absent from the
count. Previously true and unstated; now stated in the legend. A `role="type"` reference class
remains the fix rather than the disclosure, and is recorded as such.

### Added — the oracle-scored reference-precision receipt

`bench/headtohead/r9-2026-08-09/` publishes the round behind the README's silent-miss claim: 68
answers scored against a `scip-clang` index, six imperfect, four self-flagged, and the two unflagged
traced to files the oracle could not see. It reports the comparison in both directions — an
LSP-backed tool is more precise, by ~1.5 points after these fixes, with recall now equal — along
with the protocol asymmetry that inflates one of our own rows and four limits that travel with the
numbers, including that the corpus is this repository.

### Changed — the held-out recall lane now scores a frozen doc corpus

`bench/recalleval/`'s recall lane no longer measures the live repository's docs: it unpacks
`snapshot.mdpack` — every tracked `*.md` at the commit pinned in `snapshot.lock` — into a temp root
and scores that, so its recall/MRR floors trip only on a ranker regression. The change closes a
standing defect: the lane's floor had been ratcheted 85→83→78→69 in five days purely by corpus
composition (documents joining, or even just growing, moved BM25 length normalization), with ranker
neutrality proven at every step — the forensic record is `test/recallevalcheck.sh`'s header. The
live tree keeps its own signal: a `recall_livepol` probe re-runs the same queries against the live
root and reports pollution@5 (ceiling 16% unchanged). Frozen bars: lenient recall@5 76.2% baseline /
floor 71; lenient MRR 0.619 baseline / floor 0.57. Corpus integrity is a content hash verified as
the gate's first check; refreshes happen only in deliberate recalibration commits
(`bench/recalleval/make_snapshot.py --freeze`). Method and bars: `docs/EVALS.md`.

### Fixed — nested JS/TS closures no longer inherit the enclosing function's metrics

Cross-codebase validation on webpack found a systematic extraction bug: a named const-closure
nested inside another function's scope (`const f = (..) => {..}` inside a function body) reported
the ENCLOSING function's loc/cx/ccx/nest/params instead of its own. In webpack's
`lib/html/syntax.js`, all eight closures inside the ~3400-line `tokenize` arrow reported identical
loc=3439 cx=487 params=3; the same happened under anonymous enclosers
(`module.exports = (..) => {..}` in `lib/util/deterministicGrouping.js`). Root cause: the tags-pass
body-climb (built for C++'s `function_declarator` → `function_definition` hop) adopted the first
ancestor owning a `body` field — for a nested closure that ancestor is the *enclosing*
`arrow_function`, whose whole span the closure then stole; `statement_block` was missing from the
climb's scope-stop list, so only nested (not top-level) defs escaped upward. The climb now refuses
any ancestor whose body *contains* the definition — a grammar-agnostic containment stop. Call-edge
attribution rides the same spans, so calls in the encloser's body now attribute to the encloser
instead of the last span-stealing closure. On webpack, unambiguously individually-scoped `nest>=4`
rows went from ~18% to 98% (django's healthy Python baseline: 89%). `kParserVer` 41 → 42 (cached
spans carry the bug). Gate: `test/jsnestedcheck.sh` on `test/jsnestedfix/` — hand-counted
loc/cx/params/nest for both shapes, JS and a byte-identical TS twin.

### Added — `--skipped`: itemize the header's `skipped_oversize=` count

The map header has long disclosed *how many* otherwise-indexable files the crawl dropped for
exceeding a size ceiling (`skipped_oversize=N`, absent when zero) — but nothing anywhere named
*which* files, so a reader could know the corpus was truncated without being able to say what was
absent from it. `--skipped` names them: one `<f p= bytes= limit=/>` row per dropped file, path-sorted,
where `limit=` is the ceiling that dropped the row — `--max-file-size`'s value, or the fixed 256 KB
`.json` config ceiling that flag does not raise; the root element repeats both effective
ceilings so a zero-row report still states its bounds. The accounting invariant is unchanged and now
itemizable: `files=` + `oversize=` = the population the crawl considered, at every `--max-file-size`.
Multi-root workspaces list rows under the same `<label>/./<rel>` spelling every other surface emits.

Scope is deliberate: the parse-time binary-sniff and read-failure skips are *not* listed, because
those files keep their `fileId` and stay inside `files=` (present with zero symbols) — they are not
absent from the accounting this verb itemizes. The default map is byte-identical (G5: purely
additive; the header count was already there). Read-only; exit 0 always. Gate:
`test/skippedcheck.sh`.

### Added — `--dmm`: the Delta Maintainability Model, one comparable number per change

`--quality-delta` reports *which kinds* of debt a change added. It has no scale, so it cannot answer
"was this change better than the last one?" — `--dmm` is that scale: one scalar in `[0,1]` per commit
or per working diff, trendable across commits and comparable across authors.

```
<dmm base="2edbb46cfd9d…" target="working-tree" available="1" combine="pooled"
     size_metric="physical-loc" dmm="0.436" good="462" bad="597"
     base_units="4759" base_volume="86331" target_units="4780" target_volume="86684">
  <p k="size"        dmm="0.184" good="65"  bad="288" d_low="65"  d_high="288"/>
  <p k="complexity"  dmm="0.499" good="176" bad="177" d_low="176" d_high="177"/>
  <p k="interfacing" dmm="0.626" good="221" bad="132" d_low="221" d_high="132"/>
```

A *unit* is a function or method definition with a body; its *volume* is its line span. Per property a
unit is **low risk** iff `loc <= 15` (size), cyclomatic `cx <= 5` (complexity), `params <= 2`
(interfacing). `good` is low-risk volume **added** plus high-risk volume **removed**; `bad` is the
reverse; `dmm = good/(good+bad)`. **Deleting a god function scores 1.000; growing one scores 0.000.**
The three sub-scores ship alongside the combined one because they are separately actionable — a low
`size` with a healthy `interfacing` says *split the function*, not *change the signature*.

Three spellings: bare `--dmm` compares the **working tree** against `git HEAD` (what `--quality-delta`
compares); `--dmm=REV` scores one commit against its **first parent**, the per-commit scalar; and
`--dmm=A..B` scores tree B against tree A. Multi-root workspaces refuse — pooling two histories into
one ratio would mean nothing.

**It is a delta, never a level, and that is the whole design.** A unit you edit without changing its
size, complexity or parameter count sits in the same bin with the same volume on both sides and
contributes exactly zero to both `good` and `bad`. You are not punished for touching pre-existing bad
code, because a gate that punishes touching a mess is a gate people route around. For the same reason
the verb has no threshold, renders no verdict, and always exits 0.

**`dmm="UNAVAILABLE"` is not a score.** When `good + bad` is 0 — a rename, a literal edit, a comment
reflow — the change is outside what the model measures, and the report says so in `reason=` rather
than picking the flattering default. It is never 1.000 and never 0.000. The same token appears per
property: a commit that only adds parameters leaves `size` and `complexity` UNAVAILABLE while
`interfacing` is measured.

**Lineage, and the one deviation.** The model is di Biase, Rastogi, Bruntink & van Deursen, TechDebt
2019 (SIG). The three risk thresholds and the exact good/bad asymmetry are PyDriller's
`deltamaintainability` reference implementation, read out of `pydriller/domain/commit.py` rather than
re-derived from the paper's prose — including the 0/0 case, whose `None` is where UNAVAILABLE comes
from. The deviation is disclosed on every report as `size_metric="physical-loc"`: PyDriller's volume
is lizard's non-comment `nloc`, ripwire's is the definition's physical line span, so a heavily
commented unit crosses the size threshold here earlier. The combined score is labelled
`combine="pooled"` because the paper publishes the three properties separately and no aggregate.

Gate: `test/dmmcheck.sh` — a hand-built git repository whose every commit has a pencil-derivable
answer (delete-only-high-risk → 1.000, grow-a-god-unit → 0.000, a 4-good-vs-4-bad mix → 0.500, a
literal-only edit → UNAVAILABLE), both sides of all three thresholds pinned (15 vs 16 lines, cx 5 vs
6, 2 vs 3 params), plus the root-commit, non-git, refusal, determinism, well-formedness, legend and
additivity arms.

### Added — `--nonlocal-state`: the mutable state a function can reach, reads and writes kept apart

A new lens: for every function and method, the non-local **mutable** state it — or anything in its
transitive callee closure — reads and writes, as two separate sets, with the site or the callee that
explains each one. A *cell* is a file- or namespace-scope variable, a function-local `static` (local
in name only), or a Python module global; a `const`/`constexpr`/`consteval` declaration is not a cell,
so a large `writes=` is genuinely shared mutable state and not a table of constants.

```
<fn p="src/infra/profilePmc.h:288" n="ensure_global_init" writes="2" reads="3"
    direct_writes="1" direct_reads="3" cells_total="3">
  <cell n="g_perf" p="src/infra/profilePmc.h:284" dir="rw" at="src/infra/profilePmc.h:339" at_dir="rw"/>
```

`writes=`/`reads=` fold in the callee closure, `direct_*` is what the body does itself, and each cell
child carries `dir=r|w|rw` plus either `at=` (a use site here, with `at_dir=` for what *this* body does
— it can be narrower than `dir=`) or `via=` (the nearest callee that touches it). Rows are ordered
most writes first; pages with `--limit`/`--offset`.

**Direction is the point, and it is not new.** Henry & Kafura's 1981 information-flow metric already
separated what a procedure reads from what it writes; folding them into one number discards the half
that is a hazard for everyone else. The lineage is recorded in full in
[`docs/LINEAGE.md`](docs/LINEAGE.md) — Fowler's **Global Data** / **Mutable Data** smells (2018), which
name this hazard and ship no metric; **Marinescu's ATFD** (ICSM 2004), the closest existing number and
one-hop, per-class, Java and direction-blind; **QMOOD DAM** and **MOOD AHF/MHF** (Bansiya & Davis, TSE
2002), which count *declared visibility* and therefore score a class with private fields and leaked
mutable internals as perfectly encapsulated; **Potanin, Noble & Biddle 2004**, the only published
*measurement* of externally reachable state, which is dynamic, Java-only and tooled with something
unmaintained; and **Meyers & Binkley** (TOSEM 2007), whose slice-based coupling already puts globals in
its output set, so the delta — per function rather than per variable, over the call graph rather than a
dependence graph — is argued in the source header rather than asserted. **The folklore term "action at
a distance" is deliberately not used**: it has zero academic presence and naming the feature after it
would have been the one indefensible choice available.

**It is unsound, and every count says so.** `counts_floor="1"` is on the root. The analysis cannot see
an indirect call (function pointer, virtual, callback, macro-generated call site), a write through a
pointer or reference that aliases a cell without naming it, a cell named only inside a macro, or
reflection-like dispatch — each of those makes the count too low. In the other direction, a local that
*shadows* a cell's name is charged to the cell unless ingest recorded a type binding for it. The
report's own legend names all of these where the reader meets them.

**Scope, stated rather than implied.** It covers **C++, ObjC and Python** — the languages for which the
index carries read/write use sites at all (`captureUses`, `src/ingest.cpp`). Every other indexed
language is named on the root as `unanalyzed_langs=` with a file count, because a Go or Rust corpus
would otherwise report a confident, wrong zero. Widening the lens means widening `captureUses` first,
with its own gate; adding a declaration rule alone would not do it, and the source header says so.

Gate: `test/nonlocalstatecheck.sh` (12 arms) — a hand-derived golden over a two-language fixture, a
mutation control that turns one cell `const` and must go red, plus determinism, direction, provenance,
paging, additivity and XML well-formedness.

### Added — `--field-affinity[=STRUCT]`, the cache-locality lens (advice only, and validated)

Which fields are **read together but declared far apart**. Every shipping struct-layout tool answers
"where are the holes?" — pahole, clang-analyzer `optin.performance.Padding`, PVS-Studio V802, Go
`fieldalignment`, `-Wpadded`. None answers this one. The verb builds a static field **co-access
affinity graph** (one observation per indexed C-family function body) and diffs it against the declared
field order and 64-byte cache-line geometry, reusing `--layout`'s LP64 offset model rather than
re-deriving it. Bare form ranks every aggregate in the repository by separation cost; `=STRUCT` narrows
the report.

**Almost none of this is new, and the output says so in its own legend.** The affinity graph, the
points-to-free static access enumeration (`<function, struct type>`, an approximation its authors
conceded), the separation weight `wt(fi,fj) = (block − dist)/block` reproduced verbatim, and
hardware-counter validation of layout work are all Chilimbi, Davidson & Larus, *Cache-Conscious
Structure Definition*, **PLDI 1999**. The advice-instead-of-transform posture and per-field counter
attribution are Hundt, Mannarswamy & Chakrabarti, **CGO 2006**. What is new is narrow and is
engineering: a *source-level, no-debug-info, whole-repo-ranking* delivery — pahole needs DWARF, Hundt's
was one proprietary compiler on a dead architecture, `lshaz` is Linux-x86-only and answers the inverse
(false-sharing) question.

**Exactly two findings fire**, both with a direction defensible in one sentence: `split-line` (two
fields co-accessed by ≥2 distinct functions at `wt == 0.00`, so no field order can put them on one line)
and `straddle` (one co-accessed field crossing a line boundary). **Pack-tighter and sort-by-size advice
is deliberately absent** — the Go team excludes its own `fieldalignment` analyzer from `vet` and `gopls`
because the diagnostics "very rarely indicate a significant problem" and tight packing can induce false
sharing. There is no rewrite mode and the verb never exits non-zero: five compiler attempts at automatic
field layout are dead (GCC `-fipa-struct-reorg`, LLVM heap SRA, esan, StructFieldCacheAnalysis,
Qualcomm's AoS→SoA RFC), every one that died on soundness died because a *compiler* must prove a pointer
points at a pool of that struct. Advice cannot miscompile.

Limits, in every header rather than in a footnote: `counts_floor="1"` (`fns=` counts distinct indexed
functions, never dynamic frequency; `w=` is a fan-in reachability *proxy*), `model="lp64-approx"` (a
definition `--layout` marks `modeled="0"` contributes its affinity graph and no geometry finding), only
dot/arrow member syntax is counted, and a field name declared by two aggregates is **refused** and
tallied in `amb_skipped=` rather than guessed.

**The validation half is real, and it refuted the hypothesis in one regime.**
`bench/bench_field_ab.cpp` builds the two layouts the lens compares and measures them through
`prof::pmc` — ripwire's existing counter backend. On an Apple M5 Pro, 64 MB per arm, five repeats per
stride: the flagged layout is 4–41 % **slower** at strides 9/1025/4097, mixed at 129, and ~2× **faster**
under a fully sequential sweep — where the packed arm moves *less* data and still costs more time,
because a single 64 B touch per 256 B element is a sparser stream than two. Hardware counters were
**UNAVAILABLE** in that run (kperf needs root on macOS) and the harness says so rather than implying
confirmation, so the *mechanism* claim remains unconfirmed. `docs/FIELDAFFINITY.md` records all of it,
including the honest reading of the lens's own #1 result on ripwire's source (`MainDispatch` — real
static separation cost, almost certainly nil dynamic cost, which is limit (1) visible in the top row).
Gate: `test/fieldaffinitycheck.sh` over `test/fieldaffinityfix/`, whose every offset is hand-computed in
the fixture's own comments.

### Measured — `--ensemble`'s four families are near-orthogonal; one of them cannot carry a gate

A calibration pass over **nine trees (five independent, 27 889 eligible functions)** spanning C, C++,
ObjC/ObjC++, Metal, Rust, Swift, Python, TypeScript and Bash. No behaviour changed: the new
`bench/ensemblecal/` harness reads `--ensemble`, `--readability` and `--metrics` and computes
nothing of its own. Full numbers, per corpus and pooled, in [`docs/EVALS.md`](docs/EVALS.md) §9.

- **The ensemble premise holds.** Largest cross-family correlation anywhere: **φ = +0.278**; pooled
  over the independent corpora no pair exceeds **+0.168** and the largest overlap between any two
  families is Jaccard 0.119. The four families are not one signal wearing four hats.
- **`historical` is disqualified from gating, on measurement.** Across three commit ladders (148 /
  792 / 1 620 first-parent commits) its flagged set has mean consecutive Jaccard **0.800–0.862** and
  endpoint Jaccard **0.426–0.546**, against 0.920–1.000 for the other three.
- **Three named presets, derived from that**: `lenient` = all four families, `fam ≥ 1` (32.22%
  pooled); `default` = all four, `fam ≥ 2` (4.39%); `strict` = structural + lexical + confusion,
  `fam ≥ 2` (2.34%) — strict is a *selection*, not a higher K, and its output set is both smaller and
  measurably steadier than `fam ≥ 3` over all four.
- **Two honesty defects found and recorded, not fixed here.** The `confusion` family is gated to
  C/C++/ObjC but does not declare itself unavailable on a corpus with no C-family file (it fires 0 of
  4 068 on a Rust tree while still counting inside `of=`); and the "worst decile" ordinal cut is
  capped at 40 rows, so its realized width is **0.23%–8.81%**, not 10%.

### Added — `--cochange` grows the three things the papers behind it already had

`--cochange`'s `surprising="1"` predicate is an independent implementation of published work, now
cited in [`docs/LINEAGE.md`](docs/LINEAGE.md) §2 (Wong/Cai/Kim/Dalton, ICSE 2011 — the Clio tool;
Mo/Cai/Kazman/Xiao, IEEE TSE 2019; Gall/Hajek/Jazayeri, ICSM 1998; Code Maat in §3a). Reading those
against the shipped predicate produced three additions:

- **`recur=` and `sub_windows=` on every row.** Clio does not report a discrepancy the first time it
  appears — it mines frequent patterns over the last five releases and reports only recurring ones.
  ripwire mined one window, in which a one-week refactor sprint and an eighteen-month structural
  defect both score `together=4`. The window is now cut into equal-**commit-count** sub-windows
  (equal time would make the number a function of when the team took holiday) and `recur=` counts how
  many contain a joint commit. `--cochange-recur=K` filters on it and the header publishes
  `min_recur=` so a shortened list is explained. Measured on a 1,648-commit, 2,718-file C++/ObjC++
  corpus: `recur>=2` removes **45%** of the surprising pairs (253 → 140) and `recur>=3` removes
  **81%** (253 → 47).
- **`--cochange-groups`.** Mo's Modularity Violation Group is the minimal set of *groups* covering the
  violating pairs, not a pair list — "X co-changes with {A,B,C}, none of which it depends on" is one
  row that names the file to fix. Same corpus: 253 pair rows collapse to **65 groups** (3.9 pairs per
  group). The cover is greedy and says so (`cover="greedy"`); minimum set cover is NP-hard, so
  `groups=` is an upper bound on the minimum, never the minimum.
- **`conf_ab=` / `conf_ba=` / `driver=`, and `conf_rev=` on the per-file form.** Clio's confidence is
  asymmetric — `conf = frq(x1 ∪ x2)/frq(x1)` — so "A always drags B" is distinguishable from the
  reverse. ripwire's `deg=` divides by the quieter file, which is exactly the *larger* of the two
  directions with the direction discarded; both are now emitted, `deg=` is documented as their max,
  and `driver=` names the antecedent of the stronger rule. A tie emits no `driver=`.

Calibration is published with the feature rather than after it. Clio reports 66% precision on Hadoop
Common and 40% on Eclipse JDT; ripwire's measurable analogue on the corpus above is a **yield** of
59.8% (flagged pairs over dependency-capable candidate pairs), which is not the same quantity — see
[`docs/EVALS.md`](docs/EVALS.md) §7 for what was measured, what was not, and the upper bound on
precision it supports. **Correction, still pre-release:** that 59.8% was measured on an index with a
capture gap (guard-wrapped `#include`/`#import` never seen), fixed in `ba82324` (`kParserVer` 40); the
re-measured yield on the same corpus is 52.2%, with the composition-derived precision ceiling moving
from ≤67.6% to ≤64.3% — now inside Clio's 40–66% band rather than a hair above its top. `docs/EVALS.md`
§7 carries both figures and the full re-derivation; this entry is left as originally written except for
this note, per the project's own rule against silently overwriting a published number.

Gate: `test/cochangecliocheck.sh` (29 arms over a scripted 24-commit fixture repo whose oversized base
commit also proves the 30-file bulk cap still fires).

## [0.2.1] — 2026-08-05

Linux portability patch. The v0.2.0 Linux archives were built on `ubuntu-24.04` and required
`GLIBCXX_3.4.31`, so they died on RHEL 9 and older (verified on ubi9). The Linux release legs now
build inside AlmaLinux-8-based `manylinux_2_28` containers with Red Hat gcc-toolset 14 — newer
libstdc++ symbols link statically (the devtoolset model), so **one binary per arch covers
RHEL/Alma/Rocky 8+, CentOS Stream, Fedora, Ubuntu 20.04+, and Debian 11+** (glibc 2.28 floor;
verified on ubi8, ubi9, ubuntu:22.04, ubuntu:24.04). A new `smoke-rhel` CI job runs the packaged
tarball on a RHEL 9 (ubi9) userland and gates publish. Also: `bench/representative_perfgate.sh`
byte counting is now GNU-portable (`stat -f %z` is BSD-only and zeroed the corpus-shape preflight
on every Linux CI leg). No library or CLI behavior changes.
### Added

- **Optimization-remarks build and triage** — `-DRIPWIRE_OPT_REMARKS=ON` (a separate tree; refused by
  name inside `build/` and `asan/`) collects clang's `-Rpass*` remarks plus a YAML opt-record, and
  `scripts/optremarks.sh` / `scripts/optremarks.py` turn it into a ranked report. `docs/OPTREMARKS.md`
  carries the full triage of the first pass over `src/`, and `skills/ripwire-opt-remarks/` carries the
  remark→fix patterns that survived it. New gate: `test/optremarkscheck.sh`.
- **`-DRIPWIRE_LTO`, now ON by default** — link-time optimization. The first change the remarks pass
  justified: 397 of 636 distinct `inline/NoDefinition` sites in `src/ingest.cpp` name a tree-sitter C
  accessor, inside the two phases that are ~31% of a cold run, and no source edit can reach a
  cross-TU definition. Measured on this repository as corpus (937 files, Apple Silicon) across four
  independent interleaved A/Bs of 9/21/21/31 runs per arm: **cold 1–6% faster, warm 0–3%**, with
  every cold statistic in every run favouring LTO and one run's warm min going the other way — the
  per-run table is in `docs/OPTREMARKS.md` F1, and the range is the claim, not its best row. Output
  is byte-identical and the determinism gate passes on the LTO tree. It costs link time — a rebuild
  after touching `src/main.cpp` goes 34 s → 89 s — which is not a reason to decline a faster binary;
  `-DRIPWIRE_LTO=OFF` restores the fast edit loop. **Note:** `option()` never overwrites an existing
  cache entry, so a build tree configured before this change keeps `RIPWIRE_LTO:BOOL=OFF`; delete the
  tree to pick the new default up.
- **`-DRIPWIRE_PGO=generate|use` and `scripts/pgobuild.sh`** — profile-guided optimization, and the answer to the remark classes LTO cannot touch: `inline/TooCostly` and
  `loop-vectorize/VectorizationNotBeneficial` are the cost model guessing at hotness, and a profile
  replaces the guess with counts. **Cold 14–25% faster than a non-LTO build (6–16% over the shipped
  LTO default), warm 5–10%**, measured on this
  repository *and* on a ~2000-file C++ tree that appears in no training run — six interleaved A/Bs,
  two corpora, two independently built PGO binaries, every statistic favouring PGO. Output is
  byte-identical on both corpora; the determinism gate passes three times on the PGO tree. `pgobuild.sh` runs instrument → train → merge →
  rebuild as one command. Honest G3 tension, stated in `docs/OPTREMARKS.md` F2: this is two configures
  and a training run against a one-build-step guardrail. The `.profdata` is deliberately not committed
  (a stale committed profile is a clang warning, not an error), and `RIPWIRE_PGO=use` **fails the
  configure** when the profile is missing rather than silently producing an ordinary binary.

## [0.2.0] — 2026-08-04

The first binary release: portable archives for macOS arm64/x64 and Linux arm64/x64, each with a
SHA-256 file, built by `.github/workflows/release.yml` on the tag push. Includes everything from the
asset-less `v0.1.0` tag plus the language definition-shape rounds (TypeScript, JavaScript, Python,
Swift, CUDA memory-space capture), the 2026-08-04 audit hardening (cache isolation, honest
lint/doc-drift behavior, transitive test reachability, skill routing, Codex plugin/CLI setup), and
the Codex CLI benchmark harness under `bench/agentloop/`.

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
- **`--color-by=MODE`** sets the initial node-colour lens of the `--html` page — `lang`
  (default), `community` (Louvain module), `cx` (cyclomatic, fixed thresholds), `churn`
  (per-file git commits, 18-month window), or `tested`. The page embeds all five lenses
  and keeps a live selector; when no git history exists the churn legend says so instead
  of painting zeros.
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
- **A Linux hardware-counter backend for the self-profiler** (`-DRIPWIRE_PROFILE=ON` builds only),
  behind the same one-surface contract as the existing Apple Silicon kperf/kpep backend: one
  `perf_event_open` group per thread, **pinned** so the kernel never multiplexes it — a reported delta
  is a raw truth or the column is absent, never a silent scale — read whole in one syscall, and
  `exclude_kernel` so the stock `perf_event_paranoid=2` admits it without root. Where the kernel
  exposes no PMU at all it arms software counters rather than going dark — see the vPMU-less entry
  below — and degrades silently to plain timing only when the kernel offers nothing whatsoever.
  `test/pmccheck.sh` asserts whichever arm (active/inactive) the
  machine can express; see `bench/PROFILE.md` for the availability and validation story.
- See `docs/EVALS.md` for what each instrument measures and every published number's provenance.

### Changed

- **BREAKING (build): the default build is architecture-neutral.** It previously hardcoded
  `-O2 -mcpu=apple-m1 -ffast-math -fno-finite-math-only` unconditionally, which was a hard
  configure/compile failure on any non-Apple-Silicon target — Linux x86-64 and aarch64, Intel macOS,
  any cross build — because clang rejects `-mcpu=apple-m1` as an unknown target CPU. `-mcpu=apple-m1`
  is now applied only when configuring on Apple Silicon; elsewhere the default is plain
  `-O2 -ffast-math -fno-finite-math-only`. `RIPWIRE_NATIVE=ON` (`-march=native`, a dev-machine opt-in)
  is unchanged, as is the PageRank no-reassociation contract and the sanitizer target.
- **x86 SIMD kernels, output-identical.** The `dynamic_map` per-node rank scan and `FixedStr`'s
  `operator==` now compile to SSE on x86_64, alongside the NEON kernels that already existed on
  aarch64 — same count-of-true-lanes contract, no node-layout, width or API change, and a portable
  scalar path everywhere else. `test/dynmapsimdcheck.sh` proves SIMD-vs-scalar parity under the full
  sanitizer set and **fails a scalar-only build on a SIMD architecture**, so the gate cannot pass by
  measuring nothing.
- **x86 radix byte-histogram kernels, output-identical.** The radix sort's contiguous-key histogram
  fast paths (uint32/uint64/float, `src/infra/radixSort.inl`) now compile to SSE2 on x86_64 — the
  same one-wide-load-then-byte-spill shape as the NEON kernels that already existed on aarch64, with
  the IEEE sortable-word flip done in SIMD for float. Same histograms bin-for-bin, scalar path
  everywhere else (including big-endian NEON). *Measured (min-of-15 ns/key, x86_64 via Rosetta 2 on
  an M-series host — a translation proxy, not real x86 silicon — `-O2 -DNDEBUG`, 4K/64K/1M random
  keys):* float 1.44–1.52× over scalar; uint32/uint64 within ±10% (a wash — kept for backend
  uniformity, at no measured cost). An AVX2 variant (32-byte load, same spill) measured *slower*
  than SSE2 under the same proxy (0.86–0.94×) and was not shipped; re-evaluate on real x86 hardware
  before adding it. `test/radixsimdcheck.sh` proves SIMD-vs-scalar parity against an
  independently-formulated histogram oracle under the full sanitizer set, **fails a scalar-only
  build on a SIMD architecture**, and on Apple Silicon runs a second cross-compiled pass under
  Rosetta so the SSE2 kernels are gated on the machines this repo is developed on.
- **sparseCsr math kernels join the x86 port.** The CSR `blockReduceDot` / `scaleVec` / `spmvRow`
  float kernels — NEON-only until now, silently falling back to scalar on x86_64 — compile to SSE2
  (mul+add: SSE2 has no FMA, so x86 rounding differs from arm64 while each platform stays
  bit-stable run-to-run, which is what the determinism contract requires). `test/dynmapsimdcheck.sh`
  grew a third parity arm — an exact-integer regime whose sums are exact in every association
  order, so lane and tail bugs surface as bit-exact mismatches with no tolerance band to hide
  behind, plus a tolerance-band random regime and a known-eigenpair check — and its non-vacuity
  banner now covers these kernels, so a scalar-only x86 build fails instead of passing vacuously.
  Found by sweeping `__ARM_NEON` sites rather than porting from the feature list; the radix-sort
  byte-histogram fast paths are the one remaining NEON-only site (identical behavior either way —
  a perf follow-up, bench-gated).
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

- **The self-profiler's Linux counter backend no longer goes dark on vPMU-less machines** — which is
  most cloud VMs and CI boxes (`src/infra/profilePmc.h`; visible only under `-DRIPWIRE_PROFILE=ON`).
  Two defects, found and fixed live on an x86 Xeon VM whose kernel refuses every hardware event with
  `ENOENT`: (1) the documented per-event graceful skip did not apply to the group *leader* — if the
  first event (`cycles`) failed to open, the whole backend went inactive even when later events would
  have opened; leadership now falls to the first event that actually opens. (2) The event table was
  hardware-only, so a PMU-less kernel had nothing to offer; two `PERF_TYPE_SOFTWARE` rows —
  `task-clock` (on-CPU ns) and `page-faults` — now trail the table. They cost no hardware counter
  slot on bare metal and keep per-scope counter columns alive on VMs, under their own names, never as
  a stand-in for hardware counts. The over-budget shrink loop also now drops the last *PMU-consuming*
  event rather than blindly the last row (dropping a software event can never make a pinned group
  fit). Gate: `test/pmccheck.sh`'s inactive arm now additionally proves the kernel offered no counter
  at all — the arm that used to pass vacuously on VMs fails on the old code and exercises the live
  path on the new. *(Measured on the 2-vCPU VM: single-thread scopes' `task-clock` agrees with the
  independent wall column to 0.05–1.6%, and the parse pool's wall-vs-task-clock gap put a number on
  CPU oversubscription — ~36% of the parse phase's wall time was spent off-CPU.)*
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
- **Binary-doc extraction (`markitdown` bridge) is uncached and re-runs every ingest.** The doc
  post-pass is deliberately outside the parse cache, so on a machine with `markitdown` installed a
  corpus containing PDF/PPTX/DOCX/XLSX pays the full subprocess extraction on *warm* runs too —
  measured at ~97% of a warm run's wall (2.05 s of 2.11 s) on a 2-vCPU VM against this repository's
  own showcase PDF+PPTX, found by the self-profiler's wall-vs-task-clock gap (child-process CPU is
  invisible to per-thread counters). The extraction is a pure function of the file bytes, so it is a
  clean cache candidate; until then, the cost scales with the corpus's binary docs, not its code.
- **`--for`'s `--token-budget` shaping is not strictly binding at very small budgets** — the header
  floor (envelope, legend, verbatim task echo) is bytes no trim can shrink, and the lens labels the
  result `over_ceiling` rather than claiming a trim it did not perform.
- **Release automation has never been executed end-to-end.** The tag-triggered build-and-attach
  workflow and the release-binary installer are untested until the first real tag push.
- **The x86 64-bit-key rank kernels need SSE4.2.** `_mm_cmpgt_epi64` is not in the SSE2 baseline, so on
  a stock `-march=x86-64` build the `int64`/`uint64` specializations — including the production
  `dynamic_map<std::uint64_t, …>` instantiation — fall back to the scalar template. Build with
  `-march=x86-64-v2` or `RIPWIRE_NATIVE=ON` to light them up. Correctness is identical either way; only
  the scan width changes.
- **The Linux counter backend's *active* path has not been run against real PMU hardware.** It is
  validated for correctness, degrade behavior and the sanitizer set under x86-64 emulation and on
  PMU-less VMs, where `perf_event_open` fails and the backend goes inactive as designed — which
  exercises the inactive arm only. The live counting path awaits a bare-metal box; `bench/PROFILE.md`
  carries the probe that tells you whether a candidate machine qualifies.

# `--slice` line recall on an issue-derived Python corpus — ARISE rung 1, measured

**Status: RUN, 2026-09-20.** The protocol in sections 1 to 6 was committed in `3d994cda` with the
results section empty — that commit contains no number produced by the harness, which is the proof
of ordering. Amendments are dated inline and labelled **AMENDMENT**, and each says whether it was
made before or after a result was seen.

**Scope.** This is the retrieval-quality question ARISE (arXiv:2605.03117) raises, asked of
ripwire's `--slice` primitive on a corpus ripwire has not measured it on: issue-derived Python fix
patches, addressed at the **pre-fix** tree. It is a research note, not a product claim. No number
here is published anywhere else until an owner pass.

---

## 1. What is already registered, and what this round adds

`docs/EVALS.md` § *"The `--slice` def-use primitive (2026-08-28)"* registered a line-recall shape.
§ *"`--slice-flow` — ARISE rung 2"* executed it (2026-08-30, ripwire's own history, 38 instances)
and extended it (2026-08-31, three D4-pinned C/C++ trees). **So the registered shape has been run —
twice — and this round does not "finally run it".** What those runs did *not* cover, and what this
round adds:

| already measured | not measured before this round |
| --- | --- |
| cpp family only (4 corpora, all C/C++) | **py family** — the one ARISE itself measured on |
| corpus mined from git history by subject regex | **issue-derived fix patches** (LocBench), the shape ARISE evaluates |
| gold = ADDED lines at the POST-fix tree | **gold = PRE-image lines at the PRE-fix tree** — the actual localization setting |
| set recall: are the gold lines among the rows | **rank**: do the rows put gold lines *first*, vs a random-order control |
| misses pooled | **reachability split**: gold out of reach *by construction* reported apart from gold the slicer dropped |
| bytes | **bytes and wall time** |
| — | **granularity vs presentation**: file-level / symbol-level / line-level answers under one byte budget |

Everything in the right-hand column is new registration and is fixed below before the harness runs.

### 1.1 Gap in the existing registration, closed here before measuring

The 2026-08-28 registration says "take the variables named on the changed lines and ask whether
`--slice=fn:var` surfaces those changed lines among its rows". It is silent on three things that
decide the number:

- **G1 — which tree.** A fix commit has a before and an after. The 2026-08-30/31 runs sliced the
  POST-fix tree and scored ADDED lines. That measures *can the slicer see lines that already exist*.
  The localization task ARISE scores is the other one: the agent holds the **pre-fix** tree and must
  find the lines to change. This round slices the **base commit** and scores **pre-image** lines.
  Both are defensible; they are different questions, and the earlier numbers are not comparable to
  these. Stated, not reconciled.
- **G2 — which lines are gold when a hunk only inserts.** A pure insertion has no pre-image line of
  its own. Rule fixed here: the gold line for an insertion run is the pre-image line **immediately
  preceding** the insertion point (`pre_ln - 1`), or the hunk's first pre-image line when the run
  opens the hunk. One anchor per run, never both neighbours.
- **G3 — what "surfaces" means when the row set is unordered.** `<s>` rows are emitted in source
  order, which is not a relevance ranking. The registration's metric is therefore a *set* metric and
  cannot answer "does the primitive rank". The two ranking rules used here (§4) are defined below,
  before any result, and both are computed from attributes the primitive already emits — no new
  scorer, nothing tuned.

**AMENDMENT 2026-09-20 (a):** G1, G2, G3 are amendments to the 2026-08-28 registration, written and
committed before the harness ran. They do not alter the 2026-08-30 or 2026-08-31 numbers, which
stand under the original reading.

---

## 2. Corpus and slice rule — fixed before looking at any result

**Source, already on disk, nothing downloaded.** `czlll/Loc-Bench_V1` test split, 560 rows, at
`<assets>/datasets/rows_czlll__Loc-Bench_V1_test_560.json`; 165 distinct repositories, of which
**90 have a local checkout**. Every `edit_functions` entry in all 560 rows is a `.py` path, so this
corpus is py-family in its entirety and is reported as such, never averaged with the cpp corpora.

**A row is USABLE iff all of:**

1. its `repo` has a local checkout;
2. `base_commit` resolves as a commit in that checkout;
3. `edit_functions_length == 1` — exactly one edited function. **Rows failing only this are the
   by-construction-unreachable population** (§4c) and are counted, never scored as misses;
4. the single `edit_functions` entry is `PATH:FN` with `PATH` ending `.py`, and `PATH` materializes
   at `base_commit`;
5. the selector resolves **uniquely**: `FILE:FN` for a plain name, `FILE::CLASS::METHOD` for a
   dotted `Class.method`. An ambiguous or unresolved selector disqualifies the row and is counted by
   reason;
6. at least one gold line (§G2 above, restricted to the resolved function's line span) exists;
7. at least one gold line names a variable in the function's own `--slice=SEL` inventory (otherwise
   there is no v1 instance to score — counted as `no_touched_var`).

**Cap: none.** Every usable row is measured. The corpus is small enough that a cap would only add a
choice to defend.

**The tree handed to ripwire is a one-file tree**: the target file alone, materialized with
`git show BASE:PATH` into a scratch directory. The checkouts are never written to, never checked
out, never `git worktree add`-ed. This is sound *because the primitive is intra-procedural by
declaration* — no row of `--slice` can depend on a file it does not read — and it removes the
basename-ambiguity that thinned 34/63 candidates in the 2026-08-31 cpp run. It is stated as a
deviation because it also removes a real-world failure mode (whole-repo selector ambiguity), so the
selector-resolution rate reported here is an **upper bound** on what an agent would see on a whole
repo.

**Determinism.** Given the dataset file, the checkouts and the binary, the instance list and every
number are a pure function of the inputs; row order is the dataset's own. The random-order control
uses a fixed seed (`20260920`) and a fixed shuffle count (200).

---

## 3. Arms

All arms run on the same instances, at the base commit's own file.

| arm | command | what it is |
| --- | --- | --- |
| **v1** | `--slice=SEL:VAR` | the registered flat slice |
| **v2** | `--slice=SEL:VAR --slice-flow=both` | rung 2, bounded def-use BFS |
| **inv** | `--slice=SEL` | the sliceable-local inventory (addressing cost) |
| **expand** | `--expand=SEL` | whole-body baseline, recall 1.0 by construction, priced in bytes |
| **file** | the raw file | file-level baseline for §5 |

---

## 4. Metrics — all defined before measuring

**(a) Set recall (the registered shape, at the pre-fix tree).** Per (row, var) instance with
`G_var` = gold lines naming `var`:
`v1_line_recall = |G_var ∩ rows| / |G_var|`; `hit_all` = that ratio is 1.0;
`over_inclusion = |rows| / |G_var|`. Same for v2.

**(b) Rank — the new question.** Candidate pool = **every line in the resolved function's span**.
Two ranking rules, both from attributes already emitted, neither tuned, plus a control:

- **R1 (coverage).** Score a line by the number of *distinct* inventory variables whose v1 slice
  contains it. Ties broken by line number ascending. Rationale: a line participating in several
  tracked locals is the more central statement. Seed-free — it unions over the whole inventory and
  never looks at the gold.
- **R2 (flow depth).** Score a line by `-min(d)` over the `--slice-flow=both` rows of every
  inventory variable (v1 rows count as `d = 0`). Ties broken by R1, then line number. This is the
  primitive's own relevance signal.
- **CTL (random).** A uniform random permutation of the same candidate pool, averaged over 200
  shuffles at seed `20260920`. This is the honest floor: a slice that merely *presents* lines will
  score like CTL.

Metric: `Recall@k = |G ∩ top-k| / |G|`, k ∈ {1, 3, 5, 10, 20}, reported as the instance mean, for
R1, R2 and CTL. Also `MRR` of the first gold line.

**A seeded upper bound is reported separately** (`R2-oracle`): the same R2 ranking computed from the
gold-touched variables only. It is an oracle and is labelled one; it bounds what a perfect seed
choice could buy.

**(c) Reachability.** A cascade, each stage counted, reported as fractions of the 560 rows and of
the gold lines:
`multi-function row` → `no checkout / no commit` → `selector unresolved` → `gold line outside the
resolved span` → `gold line names no sliceable local` → `scoreable`.
A gold line lost at any stage but the last is **out of reach by construction**, not a slicer miss,
and is reported on its own line.

**(d) Cost.** Per instance: output bytes of inv / v1 / v2 / expand / file, and wall-clock
milliseconds of each ripwire invocation (single process, warm cache, median and mean).

---

## 5. Granularity vs presentation — the paper's actual question

ARISE's claim is that the *granularity floor* binds, not the ranking. The test that separates
granularity from presentation: hold the **answer** fixed (the correct function is given) and the
**budget** fixed, and vary only the granularity of what is delivered.

Budgets `B ∈ {512, 1024, 2048, 4096}` bytes of delivered payload. Three deliveries:

- **file-level** — the file's source, from its first line, truncated at `B` bytes;
- **symbol-level** — `--expand=SEL`'s body, truncated at `B` bytes;
- **line-level** — slice rows in **R2** order, each as `line-number: source text`, packed until `B`
  bytes is reached.

Score: the fraction of gold lines whose exact source text appears in the delivered payload.
Reported split by whether the function body **fits** in `B` (where symbol-level is 1.0 by
construction and the comparison is uninformative) and where it does not (where the question bites).
This is a *presentation-controlled* comparison: same correct function, same bytes, different
granularity. It cannot speak to ranking a whole repository — see §8.

---

## 6. What we are NOT claiming

- Nothing here is a Function Recall or Line Recall@1 number comparable to ARISE's. ARISE ranks over
  a whole repository from a natural-language issue; this measures a primitive **given** the correct
  function. The two numbers are not on the same axis and are never put in the same table.
- The one-file tree is an upper bound on selector resolution (§2).
- py-family only. The cpp numbers in `docs/EVALS.md` are a different population.

---

## Results

**Binary** `ripwire 0.6.1 (dev, built_from=755f9026f)` — plain dev build, no `-DCMAKE_BUILD_TYPE`.
**Re-runs:** the full harness was run end to end twice; the summary, every per-instance row and
every per-variable row compared **identical** (wall-clock timings excluded, as they must be).

**AMENDMENT 2026-09-20 (b), made AFTER seeing the first misses and reported BESIDE the registered
metric, never instead of it.** The registered relevance oracle is a word regex over the changed
line's text. It counts a variable's name inside a docstring, a comment, a string literal, and even
the `f` of an f-string prefix, as an occurrence the slice "ought" to have rowed. A *strict* oracle is
added: an occurrence counts only when Python's own tokenizer calls it a `NAME` token on that line.
Both numbers are reported. The registered number is the headline; the strict number is what the
misses turn out to be made of.

**AMENDMENT 2026-09-20 (c), made after a 6-row smoke run and before the corpus ran.** Two arms were
added: **R0**, plain source order over the function's lines — "just read the function top-down",
the baseline an agent actually has — and **line-filtered**, the def-use-covered lines in *source*
order, which separates the granularity FILTER from the RANKING in §5.

### R1. Corpus — what was usable, and why the rest was not

| stage | rows | note |
| --- | ---: | --- |
| dataset | **560** | LocBench V1 test; every `edit_functions` path is `.py` |
| multi-function (`edit_functions_length > 1`) | **208** | out of reach by construction — §R3, not a miss |
| single-function | 352 | |
| …no local checkout | 169 | 90 of the dataset's 165 repositories are on disk |
| …`base_commit` absent from the checkout | 1 | |
| **carried to the harness** | **182** | 1 040 gold lines |
| …selector refused, plain `FILE:FN` | 3 | |
| …selector refused, scoped `FILE::CLASS::METHOD` | 2 | |
| …`--expand` served no body | 2 | |
| …every gold line outside the resolved span | 2 | |
| **scored instances** | **173** | 2 453 `--slice` calls per arm; **498** (instance, variable) pairs |

Selector resolution on the one-file tree is **177/182 = 97.3 %**. That is an upper bound (§2), and
§R6 prices the gap.

### R2. Set recall — the registered shape, at the pre-fix tree

498 (instance, variable) pairs; 480 of them also scoreable under the strict oracle.

| metric | registered oracle | strict oracle |
| --- | ---: | ---: |
| v1 per-variable line-recall (mean) | **0.932** | **0.995** |
| v1 hit-all rate | **0.902** | **0.994** |
| v2 (`--slice-flow=both`) per-variable line-recall | 0.935 | — |
| v1 over-inclusion, rows / relevant lines | 5.12× | — |
| v2 over-inclusion | 12.46× | — |

**Every miss was inspected, not sampled** (`bench/slice/inspect_slice_misses.py`). 100 gold lines
miss under the registered oracle. **97 of the 100** are lines where the variable's name is not a
`NAME` token at all — docstring prose, a trailing comment, a string literal, and in one instance the
`f` of `f"Incompatible safetensors file…"` matching a local called `f`. The **3** that survive the
strict oracle are all the same construct, a **keyword-argument name that collides with a local**:

```
pydantic-10789  var=schema  L1918: lambda x, h: h(x), schema=core_schema.any_schema()
dask-11539      var=store   L3759: z = zarr.open_array(store=url, read_only=True, path=component, **kwargs)
feast-4727      var=actions L235 : assert_permissions(resource=feature_view, actions=[AuthzedAction.WRITE_ONLINE])
```

In all three the `store=` / `schema=` / `actions=` token is the **callee's** parameter name, not a
use of the local — so the classifier is right and the gold line is one the localization task wants
but the def-use relation genuinely does not contain. **On this corpus the slicer drops no real
identifier occurrence.** This replicates, on a different family and a different corpus shape, the
2026-08-30 cpp reading that the misses belong to the oracle rather than to the slice; that reading
was a per-instance inspection then and is an exhaustive, tokenizer-decided classification now.

### R3. Reachability — what is out of reach by construction

The primitive is name-based and intra-procedural. Two cascades, kept apart on purpose.

**Dataset-level, over all 560 rows and all 9 615 gold lines** (computed without reference to which
repositories happen to be on disk):

| population | rows | gold lines | share of gold |
| --- | ---: | ---: | ---: |
| multi-function fixes — **out of reach by construction** | 208 | **6 809** | **70.8 %** |
| single-function fixes — addressable in principle | 352 | 2 806 | 29.2 % |

A fix spanning functions cannot be served by an intra-procedural slice at all. **Seven in ten gold
lines in this corpus live in such a fix.** That is the single largest number in this document and it
is a statement about the primitive's ceiling, not about its accuracy.

**Within the 173 scored instances**, per gold line:

| stage | gold lines | share of resolved |
| --- | ---: | ---: |
| carried into the harness | 1 040 | — |
| in an instance whose selector resolved and whose body was served | 945 | 100 % |
| **inside the resolved function's span** | **809** | **85.6 %** |
| …and naming a variable in that function's own sliceable inventory | **536** | **56.7 %** |

The 136 lines inside a single-function row but outside the function's span are import lines,
decorators and module-level constants the patch also touched — the row's `edit_functions` names one
function, the patch is not confined to it. The 273 further lines are inside the function but name no
local: `self.x` attribute writes, bare `return`, `raise`, blank/comment anchors, and calls whose
arguments are all literals.

**So: 56.7 % of the gold of the reachable population is addressable by a per-variable slice, and of
that 56.7 %, the slice recovers 99.5 % (strict) / 93.2 % (registered).** Those two numbers multiply;
neither on its own is the primitive's line recall.

### R4. Rank — does the primitive order, or only present?

Candidate pool = every line of the resolved function (mean span **86.9** lines; mean inventory
**14.2** sliceable locals). Instance mean of Recall@k, n = 173.

| order | @1 | @3 | @5 | @10 | @20 | MRR |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| **R0** source order (read the function top-down) | 0.029 | 0.099 | 0.156 | 0.263 | 0.428 | 0.154 |
| **CTL** random permutation (200 shuffles, seed 20260920) | 0.042 | 0.123 | 0.191 | 0.321 | 0.498 | 0.234 |
| **R1** def-use coverage | **0.048** | **0.206** | **0.311** | **0.455** | **0.595** | **0.289** |
| **R2** flow depth, `--slice-flow=both` | 0.048 | 0.206 | 0.311 | 0.455 | 0.595 | 0.289 |
| *R2-oracle* seeded with the gold-touching variables | *0.053* | *0.292* | *0.415* | *0.570* | *0.706* | *0.349* |

Three readings, in descending order of how much they matter.

1. **The ordering carries real signal, and it is modest.** R1 beats the random control at every
   depth — +8.3 pp @3, +12.0 pp @5, +13.4 pp @10 — and beats it on MRR 0.289 vs 0.234. It is not
   close to pinpointing: **@1 is 0.048 against a 0.042 chance rate**, which is no effect worth
   naming. The primitive re-ranks a shortlist; it does not name the line.
2. **Reading the function top-down is worse than random** (MRR 0.154 vs 0.234). Fixes cluster away
   from the function head, so the default presentation order an agent gets is an actively bad
   ranking, and *anything* is an improvement on it. Half of what looks like "the slice ranks well"
   is really "source order ranks badly".
3. **`--slice-flow=both` adds exactly nothing here, and the reason is structural.** R1 and R2 are
   identical to every digit, and the fraction of the function's lines the flow rows reach equals the
   fraction the flat rows reach, to 16 decimal places (0.5126 both). This is not a coincidence and
   not a bug: a flow row at depth ≥ 1 is a line where *another* variable `w` occurs, so that line is
   already in `w`'s own flat slice. **Unioned over the whole inventory, rung 2 is provably
   redundant.** Flow's value is confined to the *seeded* case — you know which variable you care
   about and you do not want the other thirteen slices — which is exactly what the R2-oracle row
   measures, and there it is worth +8.6 pp @3 over unseeded R1.

The def-use filter keeps **51.3 %** of the function's lines. That is the granularity floor moving:
half the body is dropped before any ranking happens.

### R5. Granularity versus presentation — the paper's question

Same correct function, same byte budget, different granularity. All four payloads are delivered as
`line-number: source text`, so the numbering costs the same in every arm and the score is an exact
line-number match. Instance mean over the 173 instances.

**All instances:**

| budget | file (from line 1) | file (window on the fn) | symbol (`--expand`) | line-filtered | line-ranked |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 512 B | 0.004 | 0.329 | 0.286 | 0.373 | **0.411** |
| 1 024 B | 0.015 | 0.500 | 0.457 | 0.505 | **0.560** |
| 2 048 B | 0.057 | 0.693 | 0.682 | **0.744** | 0.738 |
| 4 096 B | 0.116 | 0.840 | 0.857 | 0.868 | **0.872** |

Symbol-level is 1.0 by construction whenever the body fits the budget, so the comparison only bites
where it does not. **Restricted to instances whose body does NOT fit:**

| budget | n | file (window) | symbol | line-filtered | line-ranked | filter gain | ranking gain |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 512 B | 150 | 0.226 | 0.176 | 0.276 | **0.321** | **+10.0 pp** | +4.4 pp |
| 1 024 B | 129 | 0.330 | 0.272 | 0.336 | **0.410** | **+6.4 pp** | +7.4 pp |
| 2 048 B | 94 | 0.435 | 0.414 | **0.530** | 0.517 | **+11.6 pp** | −1.3 pp |
| 4 096 B | 51 | 0.458 | 0.517 | 0.552 | **0.567** | +3.6 pp | +1.5 pp |

*filter gain* = line-filtered − symbol (granularity alone, source order preserved).
*ranking gain* = line-ranked − line-filtered (ordering alone, same lines).

**Answer: finer granularity changes retrieval quality, not only presentation — and on this corpus
the granularity is worth more than the ordering.** The filter is worth +3.6 to +11.6 pp at equal
bytes and is positive at every budget; the ranking adds +1.5 to +7.4 pp and at 2 048 B it is
*negative*. Both effects shrink as the budget grows, which is what "granularity floor" predicts: the
floor only binds when the budget is below the symbol.

The honest size of the claim: at a 512-byte budget, line-level delivery gets 32 % of the gold lines
in front of the agent where whole-function delivery gets 18 %. That is a real lift and it is
nowhere near ARISE's +17 pp on Function Recall@1, because it is not the same measurement — this one
is handed the correct function and ARISE's is not (§6).

### R6. Cost

| arm | mean output bytes | share of `--expand` | wall clock, median | mean |
| --- | ---: | ---: | ---: | ---: |
| `--slice=SEL` (inventory) | 1 297 | 21 % | 43.9 ms | 51.4 ms |
| `--slice=SEL:VAR` (v1) | 1 152 | **18 %** | 9.3 ms | 11.5 ms |
| `--slice=SEL:VAR --slice-flow=both` (v2) | 2 087 | 34 % | 9.7 ms | 12.0 ms |
| `--expand=SEL` | 6 230 | 100 % | 7.1 ms | 8.1 ms |

The inventory call is the first invocation against each tree and pays the index build; v1/v2/expand
are warm. n = 2 453 for v1 and v2, 173 for inv and expand.

**The one-file-tree deviation, priced** (`bench/slice/probe_wholerepo_selector.py`, a deterministic
16-instance sample materialized read-only with `git archive`):

| | one-file tree | whole tree at `base_commit` |
| --- | ---: | ---: |
| selector resolves uniquely | 97.3 % (177/182) | **87.5 % (14/16)** |
| cold `--slice=SEL` wall clock | 43.9 ms median | **435 ms mean** (68 – 979 ms, 65 – 2 794 py files) |

Both failures on the whole tree are ambiguity refusals — a bare method name matching definitions in
several classes across the repository. So roughly **one selector in eight needs qualifying** on a
real checkout, and the refusal names the qualifying spellings rather than guessing, which is the
behaviour we want but is also a round trip the agent pays for.

---

## 7. Where our construct is weaker than ARISE's

Named so the gaps can be argued with, each with what we expect it to cost.

| gap | ours | ARISE | expected cost |
| --- | --- | --- | --- |
| **def-use relation** | name-based: an occurrence of the identifier, classified by role | true def-use by the reaching-definition rule over an AST | Over-inclusion, not under-inclusion: 5.12× rows per relevant line. R2's strict recall of 0.995 says we lose almost nothing; the price is precision, and precision is exactly what a ranking needs. We expect a true def-use relation to help @1 far more than @10. |
| **aliasing** | none | none stated for the slicer either | Unknown, probably similar. Python's `a = b` on a mutable object makes both names live; we row neither for the other. |
| **scope** | scope-insensitive; shadowing may over-include | explicit global/nonlocal handling | Python comprehension and `except … as` bindings shadow constantly; we suspect a share of the 5.12× over-inclusion is this, and we have not separated it. |
| **statement granularity** | one row per source LINE | AST statement nodes | A multi-statement line merges; a statement continued across lines splits. Python's style makes the second the common case, and it will *understate* recall wherever a gold line is a continuation line of a statement we rowed at its first line. We have not measured how often. |
| **inter-procedural** | none — refuses to leave the definition | also stops at function boundaries in the slicer; expansion lives in its call-graph tier | **This is the big one.** 70.8 % of this corpus's gold lines are in multi-function fixes. ARISE has a tier that covers them; rung 1 and rung 2 do not, and the number above is what that costs. |
| **seed** | `(symbol, variable)`, or `@FILE:LINE` | `(file, line, variable)` | Equivalent in reach. Ours forces a name the caller may not have; the inventory call that supplies it costs 1 297 B and a round trip. |
| **addressing** | no `Class.method` spelling — `FILE::CLASS::METHOD` only | n/a | 12.5 % of real-checkout selectors refuse as ambiguous. Costs a round trip each; never a wrong answer. |

## 8. What we would like help with

Written as questions, because we expect several of these to have obvious answers we have missed.

1. **Is the +17 pp attributable to the relation, or to the ceiling?** Our name-based relation loses
   essentially nothing in recall (0.995 strict) and pays in precision (5.12× over-inclusion). If the
   paper's gain came from *precision* rather than *coverage*, name-based def-use is a dead end for
   ranking and we should build the real thing. Does the ablation separate these?
2. **Is our intra-procedural reading of the paper's slicer right?** We read §"stops at function
   boundaries" as the slicer proper, with cross-function expansion in the call-graph tier. If the
   slicer itself crosses boundaries, our 70.8 %-out-of-reach figure is a self-inflicted ceiling and
   we would change the design rather than report the number.
3. **What is the right relevance oracle for a line-level gold?** Ours went from 0.932 to 0.995 by
   switching from a word regex to a tokenizer. Both are defensible and the difference is 6 points.
   How is Line Recall's gold decided in the paper — post-image added lines, pre-image deleted lines,
   or a tokenized identifier match?
4. **How should a keyword-argument name that shadows a local be scored?** The only three misses that
   survive our strict oracle are exactly this. The def-use relation says "not an occurrence"; the
   localization task says "a line the fix touched". We currently count it as a miss and think that
   is wrong.
5. **Does statement-node granularity beat line granularity enough to be worth the rebuild?** We
   expect it matters most for continuation lines, which Python produces constantly, and we have not
   measured it.

## 9. Reproducing

```bash
python3 bench/slice/locbench_gold.py        --assets <assets> --json gold.json
python3 bench/slice/run_slice_linerecall.py --gold gold.json --bin build/ripwire --work <scratch> --json results.json
python3 bench/slice/inspect_slice_misses.py --results results.json --gold gold.json
python3 bench/slice/probe_wholerepo_selector.py --gold gold.json --bin build/ripwire --work <scratch> --sample 16
python3 bench/slice/run_cross_fn_reach.py    --assets <assets> --bin build/ripwire --work <scratch> --json crossfn.json
```

`<assets>` is a directory holding `datasets/<dataset>.json` and one or more directories of
`owner__repo` checkouts. Nothing is downloaded and no checkout is written to. Gold is built without
invoking ripwire, so it cannot move when the binary does.

---

## 10. ARISE rung 3 — is cross-function reach worth building? (protocol pre-registered 2026-09-22)

**Status: RUN, 2026-09-22.** §§10.1–10.3 (the protocol and the decision bands) were committed in
`21737125` with §10.4–§10.6 as headings only — that commit contains no number the harness could have
produced, the same ordering proof the 2026-09-20 round's own pre-registration commit (`3d994cda`) used.
A second commit (`f18af585`) filled in §10.4–§10.6 from `bench/slice/run_cross_fn_reach.py`'s output.
**AMENDMENT 2026-09-22 (b):** made after both of those, on review — `extend_2` was reported only
against the full 6,809-line ceiling, of which 57.2 % was never measured; §10.4 and §10.5 now also
report `extend_2` against the 2,913-line **measured** subset alone (14.35 %), so the verdict is checked
against both denominators rather than resting on the one that could be challenged. Both stay under the
pre-registered 20 % kill band. §10.5 also names the specific follow-up measurement (`--connect`-style
undirected reach over the 83.8 % of unreachable lines that have graph edges but no directed path) that
would need to change before this verdict does, and states the verdict's scope (LocBench Python
multi-function fixes, `edit_functions[0]`-seeded, directed reach) explicitly. §10.1–§10.3 are
unchanged.

### 10.1 The question

§R3 measured that **70.8 % of this corpus's gold lines (6,809 of 9,615) sit in fixes touching more
than one function**, out of reach of an intra-procedural primitive *by construction* — the single
largest number in this document. ripwire already builds a call graph for every other verb in the
catalog. Before spending any engineering on extending `--slice` across call boundaries, this round
asks the cheap question first: **using the call graph the tool already has, how much of that 6,809
would a cross-function extension actually recover, and at what hop depth?**

### 10.2 Method

**Same population, same pin.** Reuses `bench/slice/locbench_gold.py`'s dataset and gold rule (§2, §1.1
G2) — the LocBench V1 test-560 rows at each row's own `base_commit` — restricted to the **208
multi-function rows already counted in §R3's 6,809**, at the *same* checkouts as the rest of this note
(one directory containing all `owner__repo` checkouts and `datasets/rows_czlll__Loc-Bench_V1_test_560.json`,
passed as `--assets`; not committed, not named here — see §2's own `<assets>` convention). This
composes with the published ceiling: it is the same denominator, not a resample.

**Whole tree, not the one-file trick.** `run_slice_linerecall.py`'s one-file tree is sound only because
`--slice` is declared intra-procedural — a cross-function question cannot reuse it, because the
enclosing function of a gold line outside the seed can live in a different file from the seed
entirely. The tree is materialized **read-only** with `git archive <base_commit> | tar -x` into scratch
(the checkout is never written to, nothing is cloned) — `probe_wholerepo_selector.py`'s existing
technique, factored into `_common.archive_tree()` so both scripts share one definition.

**Seed = `edit_functions[0]`.** The dataset gives a patch's edited functions as a bare list, not a
ranked one. The first-listed function is used as the seed — deterministic, stated before measuring,
and the same convention `locbench_gold.py`'s `carry_row` already uses for the single-function
population (`efs[0]`). The selector is spelled with the **full relative path**, not the basename
`selector_for()` uses for the one-file trick: on a whole tree a bare basename is exactly the ambiguity
source §R6 priced (12.5 % of real-checkout selectors refuse); the patch's own path is already a unique
qualifier, so this removes a chunk of that refusal rate by construction rather than by luck.

**Reachability, per row:**

1. Resolve the seed via `--expand=SEED` against the whole tree; refusal drops the row (counted).
2. Compute every gold line of the row (§1.1 G2, unchanged) across **every file the patch touches**,
   not only the seed's file.
3. A gold line inside the seed's own resolved span is **hop0** — reported apart from the rest,
   because it was already reachable by today's single-function slice had one been pointed at this row
   at all; the existing methodology never attempts a multi-function row, so this is a footnote on the
   ceiling, not new reach.
4. Every other gold line: `--at=FILE:LINE` names its **true** enclosing symbol — not the dataset's own
   `edit_functions` naming, which the task can list imprecisely — or refuses (no indexed definition:
   an import line, a decorator, a module constant, a comment). A refusal is its own bucket,
   `no_enclosing_symbol`, disclosed apart from `unreachable`: extending call-graph reach cannot help a
   line that names no enclosing call at all, so folding the two together would overstate what a
   cross-function extension could ever buy.
5. Distinct enclosing symbols are **deduped per row** — one `--path=SEED,@FILE:LINE` call per symbol,
   not per gold line, and every gold line under that symbol inherits its verdict. `--path` is a
   directed shortest call-path with its own `hops=`/`reachable=`, which is a closer fit to "how many
   hops would a call-graph-extended slice need to walk" than reconstructing depth from `--impact`'s
   transitive-but-undated reach set or from repeated 1-hop `--callers=`/`--callees=` BFS — both of
   which this round could have used instead and neither of which reports a per-target hop count
   directly. **Direction matters and is deliberate**: `--path=SEED,TARGET` asks whether *walking
   outward from the seed's own calls* reaches TARGET, which is exactly what a call-graph-extended
   slice would do; it does *not* find a shared-caller sibling relationship (two functions invoked
   by a common third function but not by each other) — `--connect` would, and §10.6 says what that
   means for the reading.
6. For a symbol `--path` calls **unreachable**, `--callers=@FILE:LINE` and `--callees=@FILE:LINE` are
   both checked: `count="0"` on both is the honesty disclosure the protocol requires — it reads
   exactly like a symbol reached only by dynamic dispatch, a callback, or a macro (the same blind spots
   named on every graph verb in `docs/COMMANDS.md`), and this round cannot tell the two apart from the
   outside.
7. `--cache=PATH` is passed on every call against one row's tree — the first call cold-parses and
   writes it, later calls against the same unchanged tree read it back.

**Reported, per gold line of the 6,809:** `hop0` / `hop1` / `hop2` / `hop3plus` / `unreachable` /
`no_enclosing_symbol` / not measured (no checkout, no commit, seed selector refused) — every bucket a
share of 6,809, summing to it exactly, because a count that cannot be a total is a floor and a
floor is disclosed, never silently dropped from the denominator.

**Reported, per instance (row):** "fully covered at reach = N" — every one of the row's gold lines is
either `hop0` or at or under N hops — for N ∈ {1, 2, 3}, as a share of the **measured** rows (the
denominator here is rows this round could actually resolve a seed for, not all 208, because an
unmeasured row has no "fully covered" verdict to report, and reporting one against the full 208 would
manufacture a number this round never produced).

### 10.3 Pre-registered decision, before any number exists

The question this buys an answer to is **marginal**: of the gold lines a single-function slice cannot
reach today, how many would a call-graph extension **newly** reach? `hop0` lines are already reachable
in principle (§10.2 step 3) and are not the extension's credit to claim; `no_enclosing_symbol` lines
cannot be reached by any amount of call-graph walking. So the decision metric is:

**`extend_2 = (hop1 + hop2) / 6809`** — the share of the published ceiling a reach-2 extension would
newly recover.

- **`extend_2 ≥ 50 %`** — strong case: build it.
- **`extend_2 < 20 %`** — kills it: the ceiling barely moves for the engineering cost.
- **`20 % ≤ extend_2 < 50 %`** — inconclusive: report it, do not build from this number alone; it
  needs a cost estimate (§7's `--slice-flow=both`'s own redundancy finding is the cautionary
  precedent — a rung that sounded obviously useful and measured provably redundant).

`hop0`, `hop3plus`, `unreachable`, `no_enclosing_symbol` and the not-measured share are reported beside
`extend_2`, every one of them as its own share of 6,809, so the bands are graded against a number nothing
else in this section can quietly inflate.

### 10.4 Results

**Binary** `ripwire 0.6.1 (dev, built_from=81b7322ce)` — plain dev build, no `-DCMAKE_BUILD_TYPE`, same
assets as the rest of this note (§2). **Population.** 208 dataset-level multi-function rows / 6,809
gold lines — recomputed independently by this round's own harness and it matches §R3's published ceiling
exactly, which is the composability check §10.2 promised.

**Availability cascade** (rows, out of the 208):

| stage | rows | note |
| --- | ---: | --- |
| multi-function rows | **208** | the §R3 ceiling population |
| …no local checkout | 80 | same 90/165-repository availability ceiling as §R1 |
| …`base_commit` absent from the checkout | 2 | |
| …seed selector (`edit_functions[0]`) refused on the whole tree | 4 | **3.2 %** of the 126 real-checkout candidates — well under §R6's 12.5 % basename-refusal rate; the full-path qualifier (§10.2) is doing the work that number predicted |
| **carried** | **122** | 2,913 gold lines, 42.8 % of the 6,809 ceiling |

**Gold-line distribution, every bucket a share of the full 6,809 ceiling — they sum to it exactly:**

| bucket | gold lines | share of 6,809 | meaning |
| --- | ---: | ---: | --- |
| not measured | 3,896 | 57.2 % | no checkout / no commit / seed refused (cascade above) |
| `hop0` | 572 | 8.4 % | inside the seed's own span — already reachable today, a footnote on the ceiling, not new reach |
| **`hop1`** | **291** | **4.3 %** | one call hop from the seed |
| **`hop2`** | **127** | **1.9 %** | two call hops |
| `hop3plus` | 58 | 0.9 % | three or more hops |
| `unreachable` | 1,559 | 22.9 % | `--path` found no directed call path at all |
| `no_enclosing_symbol` | 306 | 4.5 % | outside the seed, and `--at` found no indexed definition there either — an import line, a decorator, a module constant, a comment; no amount of call-graph walking reaches these |

2,035 of the 2,341 outside-seed gold lines resolved to a real enclosing symbol via `--at` (the rest are
the 306 `no_enclosing_symbol` lines above); those 2,035 lines deduped to **513 distinct enclosing
symbols**, one `--path` call each, and every line inherited its symbol's hop verdict.

**The decision metric:**

**`extend_2 = (hop1 + hop2) / 6809 = 418 / 6809 = 6.14 %`**

(`extend_1 = 4.27 %`, `extend_3 = 6.99 %` — depth 3 buys less than one more point over depth 2, which
is itself the point: whatever is reachable at all is mostly reachable in one hop or not in three.)

**Denominator sensitivity, stated before this is read as a verdict.** `extend_2` above is computed
against the full 6,809-line ceiling, and 57.2 % of that ceiling was never measured (the availability
cascade above). Scoring the unmeasured 57.2 % as non-extendable is the conservative choice — it favours
killing the feature — so it is worth asking what `extend_2` is over the **measured subset alone**,
where every line actually got a `--path` answer:

**`extend_2 (measured) = (hop1 + hop2) / 2913 = 418 / 2913 = 14.35 %`**

Both denominators are reported because a reader who does not trust the availability cascade should not
have to take the ceiling-scoped number on faith. **14.35 % is still under the pre-registered 20 % kill
band**, so the verdict does not depend on which denominator is used — it holds on the conservative
figure (6.14 %) and on the more forgiving one (14.35 %) alike. Had the measured-subset figure landed at
or above 20 %, §10.5 would have downgraded to inconclusive-pending-wider-measurement rather than kill,
because the pre-registered bands decide this, not a preferred outcome.

**Instance-level: share of the 122 measured rows fully covered if reach extended to N** (every gold
line in the row is `hop0` or at/under N hops — a `no_enclosing_symbol` line anywhere in the row makes
it uncoverable at any N):

| reach | rows fully covered | share of 122 |
| ---: | ---: | ---: |
| 1 | 2 | 1.6 % |
| 2 | 3 | 2.5 % |
| 3 | 6 | 4.9 % |

**Graph-limits disclosure, as required by §10.2 step 6 and the protocol's own honesty rule.** Of the
1,559 `unreachable` gold lines, 252 (**16.2 %, gold-line-weighted** — a line inherits its symbol's
verdict, and a symbol with several gold lines is counted once per line, not once) sit behind a symbol
with `count="0"` on BOTH `--callers` and `--callees`. Read literally: about one unreachable gold line in
six sits in a function with no recorded edge into or out of it at all — indistinguishable, from the
outside, between "this function truly stands alone" and "the only calls into or out of it go through
dynamic dispatch, a callback, or a macro the name-based graph does not see" (the same blind spot named
on every graph verb in `docs/COMMANDS.md`). **The other 83.8 % of unreachable gold lines sit behind a
symbol that DOES have edges elsewhere in the graph** — not a leaf — and is still unreached by a
*directed* path from the seed; the most likely structural reading is the one §10.2 step 5 named before
measuring: sibling functions a patch edits together because a common caller uses both, not because
either calls the other. A directed
`--path` cannot see that relationship by design; `--connect` could, and did not run here (§10.6).
`graph_ambiguous=` ranged 0–34,114 across the 122 trees (mean 3,176, median 2,392) and
`graph_unresolved=` 0–11,208 (mean 1,040, median 146) — both scale with repository size, and both are
resolver gauges over the WHOLE tree, not specific to any one call queried.

### 10.5 Verdict, against the bands fixed in §10.3 before any of this was measured

**Scope: this verdict is about LocBench's Python multi-function fixes, seeded at `edit_functions[0]`,
under DIRECTED reach from that one seed — not a general claim about slicing, and not about Python
patches in general.** It says what extending `--slice` across call boundaries would buy *this specific
primitive on this specific corpus*, nothing wider.

**`extend_2 = 6.14 %` over the full 6,809-line ceiling, `14.35 %` over the 2,913-line measured
subset — both under the pre-registered 20 % kill line, so the verdict does not turn on which
denominator is used.** Even the most generous read (`extend_3 = 6.99 %` ceiling-scoped / `16.3 %`
measured-scoped, or crediting every `hop0` line as if the extension bought it too, which it did not)
stays under the band. At the instance level the picture agrees: extending reach to depth 3 still
leaves 95 % of measured multi-function rows with at least one gold line the extension cannot touch.
**Kill it** — cross-function reach via the existing directed call graph would recover a small,
single-digit-to-low-teens slice of the 70.8 % ceiling on either denominator, not the "close most of the
gap" outcome that would justify the engineering. This is a **measured** answer to the question §10.1
asked cheaply before building anything, and it came back negative on both readings of the denominator.

**The specific measurement that would change this answer, named rather than left vague:** §10.4's
graph-limits paragraph found that 83.8 % of unreachable gold lines sit behind a symbol that has *some*
call-graph edge, just not on a directed path from the seed — the structural signature of a sibling
function a patch touches via a shared caller, not via a call between the two. `--path` cannot see that
relationship by design. **The next measurement, if this is revisited, is `--connect=SEED,TARGET` (or an
equivalent undirected/bidirectional reach) over exactly that 83.8 % population**, asking how much of it
joins through a shared caller. If that share turns out to be large and cheaply reachable, this verdict
does not transfer — a directed-reach kill says nothing about an undirected join, and the two are
different features with different costs. This round did not run that measurement; it is future work,
not a caveat folded into the kill above.

### 10.6 What this does not tell us

- **Directed reach only.** `--path=SEED,TARGET` asks whether walking outward from the seed's own calls
  reaches the target. It cannot find a shared-caller sibling (two functions a common third function
  calls, never calling each other) — `--connect` could, and this round did not run it over the
  unreachable population. §10.5's one open caveat is exactly this gap; the 6.14 % verdict is a verdict
  on directed extension, not on every shape a cross-function join could take.
- **57.2 % of the ceiling was never measured**, for the same repository-availability reason as the
  rest of this note (§R1): only 90 of 165 repositories have a local checkout. The `extend_2` figure is
  computed against the FULL 6,809 denominator specifically so this gap reads as an honest floor rather
  than vanishing into a smaller, rosier-looking base — but a measurement over the other 57.2 % could
  still move the number, in either direction.
- **`edit_functions[0]` is one seed choice, not the best one.** A different, better-informed pick
  (the function with the most gold lines, or the one PageRank ranks highest) could reach more; this
  round deliberately used the cheapest, most defensible rule and did not search over seed choices.
- **A leaf-looking unreachable symbol (16.2 % of them) is not proof of isolation** — §10.4 already
  says this cannot be told apart from a dynamic-dispatch/callback/macro blind spot from the outside;
  reading it as "the code really has no callers" would overstate what the graph knows.
- **This is still the given-the-correct-seed question**, the same limit §6 already states for the rest
  of the note: an agent doing real cross-repository localization does not start from a known-correct
  `edit_functions[0]`, so even a favorable `extend_2` would not transfer directly to end-to-end
  localization accuracy — it would only bound what the *primitive* could contribute once a seed is
  already in hand.
- **Cost was not priced.** The bands in §10.3 were deliberately about the ceiling only; even had
  `extend_2` cleared 50 %, this round says nothing about the byte or latency cost of a cross-function
  slice, which would need its own measurement before a build decision — the same discipline §R6 already
  applied to the one-file-tree deviation.

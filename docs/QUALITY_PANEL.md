# The quality panel

*Moved out of `README.md` for 0.7.0. Nothing was rewritten in the move.*

---

<details>
<summary><b>4,956</b> eligible functions on this repository, and 2-of-6 agreement leaves <b>401</b> worth a second look — an <b>8.1%</b> shortlist</summary>

**Six independent evidence families, ranked by how many of them agree — never one blended score.**
Pointed at this repository's **4,956** eligible functions, 2-of-6 agreement leaves **401** worth a
second look: an **8.1%** shortlist. Pooled over five corpora (n = 27,889) no two families correlate
above **+0.168**, which is what makes agreement corroboration rather than one metric counted twice.
</details>
What each family actually looks at — on this repository's own source, not a synthetic example:

| Family | Question | Backing verb | On this repo |
| --- | --- | --- | --- |
| **structural** | shape: complexity, size, nesting *and how much of the body is deep*, params, local-variable count — absolute bars, not a ranking | `--metrics` | `buildGraph` (`src/graph.h:462`): `ccx=698 loc=1244 nest=8 humps=30 deep=283 locals=114` — **114 local variables invisible to every quality lens until this session**, because naming/size analysis has always stopped at a function's signature; `locals=` is a disclosed floor (`locals_floor="1"`), threaded through the same walk that already computes `ccx`/`nest`, at zero extra parsing cost |
| **lexical** | identifier text: the 10 `naming-*` lint rules (short, wordy, case-mixed, uninformative, …) | `--lint`, `--naming-consistency`, `--lint --naming-locals` | see below — the one family with a fix, not just evidence |
| **confusion** | syntactic idiom: the 7 `atom-*` rules (implicit predicates, nested ternaries, embedded `++`/`--`, …) | `--lint` | corpus-wide finding counts, not a per-function claim to spotlight here |
| **historical** | git change frequency — `score = churn × cognitive complexity` | `--hotspots` | `src/main.cpp`: `churn=42 ccx=3387 score=142254` — top of `--hotspots`' ranking, and its own worst function (`main`, `ccx=387`) is where developers keep working *and* the code is hardest. One caveat the panel's own legend states and this table must too: churn is measured **per file**, so every symbol in a file carries that file's `churn=`/`hrank=` verbatim — this family is file evidence *inherited* by the row, never the row's own history |
| **colocation** (local reasoning) | how much you must read that isn't in front of you | `--context-ratio` | `computeQualityDelta` (`src/mcpverbs.h:2031`), ~50 lines, **87.0%** of its distinct references resolve outside its own file — by the tokens a reader must actually read, **99.6%**. A refinement of Beck & Diehl's per-class congruence (FSE 2011); Martin's instability `I = Ce/(Ca+Ce)` is its cruder ancestor |
| **state** (unintended side effects) | mutable state a change here can perturb, that `--impact` (who calls you) never asks about | `--nonlocal-state` | `ensure_global_init` (`src/infra/profilePmc.h:288`) reaches 3 distinct global/static cells through its own body and callees — a tiny, innocent-looking call site can still break state three hops away. Unsound by construction (no pointer aliasing, no indirect calls), so every count is a floor |

<details>
<summary>How the six families are joined, the churn caveat, and the <code>nest=</code> profile deep-dive</summary>

`--quality-panel` joins **six independent evidence families** (structural shape, lexical naming,
syntactic-confusion idioms, git churn history, cross-file colocation, and non-local mutable state)
and ranks by the *count* of families agreeing, never a weighted composite — averaging correlated
metrics and calling it several is the Maintainability Index's well-known failure mode. On this
repository the panel measures **4,956** eligible functions and narrows them to **401** worth a
second look at 2-of-6 agreement — an **8.1%** shortlist, not a guess — and the largest correlation
between any two families, pooled across five independent corpora (n = 27,889), is **+0.168**: the
families really are measuring different things. The six-family table above shows what each finds on
this repository's own source; the sections below are the parts that need more than a row.

### `nest=` is a max, so it cannot tell a long function from a tangled one

The structural family's `nest=` reports the single deepest line in a function. One line at depth 9 and
a thousand lines at depth 9 produce the same number — which means a long **blocked-sequential** body (a
run of shallow scoped steps, its max set by one inner loop nobody has to hold in their head) is
indistinguishable from a **tangled** one that sustains depth for hundreds of lines. Every consumer of
`nest=` inherited that blindness: the panel's structural family, `--biggest-first`'s rank, the ensemble join.

`--metrics` now emits the **profile** beside the max — `humps=` (how many maximal regions reach the
nesting bar, CodeScene's "bumpy road": a rise above the threshold then a fall, so repeated missing
abstractions read differently from one deep tangle) and `deep=` (how many lines lie inside them, against
the `loc=` already on the row). Both come from the same fused walk that already computes `ccx`/`nest`, at
zero extra parsing cost; `deep=` is a disclosed floor (`deep_floor="1"`). Both are **absent** exactly when
`nest <` the bar — not-deep, never a hidden `0`. `deep` counts **lines** and `humps` counts **regions**,
and two regions can share a line — a one-line `if(c){x;}else{y;}` at the bar is two regions on one line —
so `deep` below `humps` is legal output rather than a defect. On this repository's own source:

| function | `loc` | `nest` | `humps` | `deep` | deep/loc | reading |
| --- | --- | --- | --- | --- | --- | --- |
| `ingest` (`src/ingest.cpp`) | 1632 | 8 | 25 | 467 | **29%** | genuinely tangled |
| `buildGraph` (`src/graph.h`) | 1244 | 9 | 30 | 308 | **25%** | genuinely tangled |
| `main` (`src/main.cpp`) | 1061 | 6 | 29 | 111 | **10%** | long, mostly shallow steps |
| `dispatchMcpLine` (`src/mcp.h`) | 1099 | 7 | 22 | 102 | **9%** | a dispatch table, not a tangle |
| `runDefaultMap` (`src/main.cpp`) | 650 | 4 | 7 | 15 | **2%** | blocked-sequential |
| `ur_walkTree` (`src/ingest.cpp`) | 87 | 7 | 1 | 43 | **49%** | *small* and tangled |

`loc` and `nest` alone rank `main` and `dispatchMcpLine` beside `ingest` and `buildGraph`; the profile
separates them, and it promotes `ur_walkTree` — 87 lines, so no size bar fires, yet proportionally the
densest thing in the table. **This changes no ranking**: `humps > 0` is exactly `nest >= bar`, which is
precisely when the `nest` bar already fired, so the family count and the panel's shortlist are untouched.
It is strictly more evidence on rows that already appear — a reader can tell the two shapes apart without
opening the file.

The panel also carries **one join, and it is deliberately not a seventh family**: a row whose structural
evidence includes `deep=` (a body that *sustains* depth at the nesting bar) and that no indexed test
reaches is annotated `join="deep+untested"` — the pair where a refactor is most wanted and least safe,
put side by side because both facts are already on the row. It changes nothing: not `fam=`, not `of=`,
not the order, not which rows appear (counting it would be the structural family wearing a second hat).
The root reports `tested_scope=` (symbols any indexed test reaches — the join's honest denominator) and
`deep_untested=` (rows carrying the annotation across the whole row set); at `tested_scope="0"` no
indexed test reaches *anything* here, so "untested" would be a fact about what was crawled rather than
about the code, and the annotation is emitted on **no** row.

</details>

**Five lenses sit *beside* the six-family join — deliberately outside its vote.** Each is out for a
stated reason, not an oversight:

| Lens | Asks | Why beside the join | On this repo |
| --- | --- | --- | --- |
| `--field-affinity` | which struct fields are read together but declared far apart; each loop's access shape (index vs pointer-chase) | its subject is a **type**, not a function — attributing a struct's finding to the functions touching it is a claim the lens never makes | `MainDispatch`: **12** findings at separation cost **92.88**; **1,374** loops classified, **5** genuine pointer-chases |
| `cache-*` lint rules + `--with-profile` | cache-hostile access shapes (alloc-in-loop, `p=p->next`, `a[b[i]]`, node containers, …), then which are *measured* hot | rows are facts about **sites**, joined to per-scope hardware counters — not per-function evidence a family vote could count | aggressive rules: **0** hits in shipping `src/`; **327** findings adversarially triaged → **0** fix-worthy; the one open refactor settled by measurement (5.2 ms) |
| `--biggest-first` (was `--readability`) | orders by Halstead volume, Posnett sigmoid (a size proxy — the readability-ordering claim is withdrawn) | the fitted score **saturates past 20 lines** — only the ordering is meaningful, and an ordering cannot vote in a count | ordering only, never a grade |
| `--naming-consistency` | off-convention names, each with a computed `propose=` | the one lens that emits **advice** — a fix is not evidence, so it does not vote | camelCase dominant at **93.0%**; **136** names flagged with proposals |
| `--lint --naming-locals` | the naming rules pointed at local variables inside already-flagged functions | **opt-in and unvalidated** — stays outside any join until a real-corpus audit clears it (the withdrawn-rule lesson) | +**973** findings that were structurally invisible before |

<details>
<summary>The depth on each lens — citations, caveats, and the withdrawn-rule note</summary>

**Two verbs sit *beside* the panel, not inside its six-family join** — worth knowing the boundary
rather than blurring it:

- **`--field-affinity`** (cache-friendly co-access) is explicitly **not** a panel family, by unit: it
  measures which struct fields are read together but declared far apart, and its subject is a *type*,
  not a function — attributing a struct's finding to the functions that touch it would be a claim the
  lens itself never makes (`docs/EVALS.md` §9.9.2). `MainDispatch` (`src/main.cpp:1335`, the 144-byte
  struct threaded through nearly every verb) still carries **12** real findings against a separation
  cost of **92.88** — fields read together in the same call routinely cross cache-line boundaries.
  Chilimbi, Davidson & Larus's cache-conscious structure definition (PLDI 1999), validated on real
  hardware counters; the advice-not-transform posture (report a split, never auto-reorder a struct)
  follows Hundt, Mannarswamy & Chakrabarti (CGO 2006). **This is a genuinely rare kind of tool**: code
  review catches cache-unfriendly patterns constantly, but every adjacent tool that reasons about
  memory-access shape (Intel Advisor's pattern classifier, DMon, PerfLint) does it by *running the
  program first* — a two-round adversarial literature and patent search found no shipping tool and no
  published work that does this **statically, before a line executes** (tier: RARE BUT REAL, the full
  citation trail and hedged claim wording in [`docs/LINEAGE.md`](LINEAGE.md)). The same verb now
  also classifies each loop's access shape — `index`/handle-based (predictable, the hardware
  prefetcher can hide the latency) vs. pointer-chase (data-dependent, no struct layout fixes an
  unhideable per-hop stall) — and, for genuine chases, checks whether the pointer you dereference to
  *reach* the next node sits next to the payload you're about to read, since that cache-line fetch is
  unavoidable and colocating there is a strictly higher-value fix than generic field reordering. On
  this repository: **1,374** loops classified, **5** genuine pointer-chases found in a codebase
  deliberately built handle-based rather than pointer-linked (guardrail G2) — the lens staying quiet
  on code written to avoid the problem is itself a check that it isn't firing at random. **Ships
  entirely report-only**: an A/B benchmark against a real 64 MB shuffled linked list measured a
  mostly-null result, so the ranking-affecting half of this feature is a provable no-op until a
  blind real-corpus validation session clears it — reported here at the same honesty level as
  everything else in this table, not oversold ahead of the evidence.
- **The `cache-*` lint pack + `--with-profile`** (cache-friendly *access patterns* — the other half
  of the locality story, shipped 2026-08-07/08) covers what `--field-affinity` deliberately does not:
  eight AST shapes practitioners agree hurt — node-based containers, `vector<T*>`/vector-of-indirect
  (the "matrix as vector of vectors"), heap allocation inside loops, `p = p->next` chase advances,
  `a[b[i]]` gather subscripts, by-value `shared_ptr` parameters, and existing manual prefetches
  flagged for re-measurement — loop-fenced by span algebra, C-family only, facts never verdicts. The
  honesty numbers, both directions: on this repository the aggressive rules fire **only in benches
  and test fixtures, zero in shipping `src/`** (guardrail G2 holding is itself the check the rules
  aren't firing at random), and a 13-agent adversarial triage of all 327 findings confirmed **zero**
  as fix-worthy — every plausible refactor died on "win unmeasurable without a profile". That gap is
  exactly what **`--lint --with-profile=FILE`** closes: it joins a `RIPWIRE_PROFILE` build's own
  per-scope hardware counters (`#PROF_TSV`) onto findings, so a row carries `heat_total_ms` /
  `heat_l1d_mpki` from a real run — static shape × measured PMU weight, the two halves of SYZYGY's
  advice mode (Hundt, CGO 2006) finally in one command. Worked example: the one surviving refactor
  candidate (flattening the Louvain adjacency) was settled by its new `PROFILE_SCOPE` in a single
  measured run — **5.2 ms, 5.9% of the verb** — a wasted afternoon prevented by a number
  ([`docs/CACHELINT.md`](CACHELINT.md) holds the full catalog, the wave-2 specs, and the
  compiler-handled myths deliberately *not* checked).
- **`--biggest-first`** (renamed from `--readability`, which still works — a stderr note points scripts at
  the new spelling) is a sibling lens, not a panel family either — the one classic model in the tree
  with a published closed form: Halstead volume (Halstead, *Elements of Software Science*, 1977) and
  the Posnett/Hindle/Devanbu sigmoid fit (MSR 2011, [doi:10.1145/1985441.1985454](https://doi.org/10.1145/1985441.1985454)),
  fitted on snippets of 20 lines or fewer — past that the fitted score saturates and only the
  *ordering* stays meaningful, which is exactly how the verb is used: largest-first, never as a
  grade. Halstead's volume specifically (not the later, less-trusted difficulty/effort derivatives) is
  among the metrics shown to track measured cognitive load directly (Peitek, Apel, Parnin, Brechmann &
  Siegmund, ICSE 2021, [doi:10.1109/ICSE43902.2021.00056](https://doi.org/10.1109/ICSE43902.2021.00056)) —
  `--biggest-first` emits volume and stops there; difficulty and effort are computed nowhere in this
  tree. **A ranking lens, never a grade, and here is what it actually orders:** on ripwire's own
  history at the pinned `v0.6.2` tag (412 function pairs mined from 80 refactor/simplify/cleanup
  commits), the order between two versions of a function followed the sign of its token-count change
  in 96.0% of pairs — read a move as *more or fewer tokens*, not as *more or less readable*. Of the 412,
  154 (37.4%) ran the commit's implied direction and 258 (62.6%) ran opposite it; Halstead volume drove
  91.1% of those 258; a separate self-consistency check confirms the formula
  computes exactly what it says it computes, so this is a construct-validity finding about the
  ordering claim, not an arithmetic bug. (First recorded as 484 pairs / 30.2% from an unpinned `git
  log --all` walk that does not reproduce — full derivation, the instrument fix and the retracted
  figure: [`docs/EVALS.md` §8](EVALS.md).) **WITHDRAWN:** the ordering claim is withdrawn —
  stratified into narrow token-count bands, the later-fix association disappears in 8 of 10 deciles
  (CIs include 1), so the order this verb produces is better explained as a residual size proxy,
  measured in the lens's own units, than as an independent readability signal (derivation:
  [`docs/EVALS.md` §8](EVALS.md)). The lens's computation is unchanged pending a proper human
  study, and `--help=--biggest-first` carries the same figures where a CLI reader meets them.
- **`--naming-consistency`** is the *lexical* family's one exception to "evidence, never advice": every
  other lens in this panel tells you WHAT is wrong, never a computed fix. Case-style consistency is
  the one property with a corpus-derivable answer — on this repository's `src/`, camelCase is the
  dominant convention at **1,677/1,803 (93.0%)** agreement, and the verb flags **136** off-convention
  names with a mechanically recombined `propose=` value for each (no dictionary, no synonym judgment —
  see [What it answers](../README.md#what-it-answers)).
- **`--lint --naming-locals`** points those same naming rules at local variable names — the thing a
  human reviewer flags immediately in a sprawling function and no static tool measured until this
  session. Opt-in, off by default: on this repository, a plain `--lint` finds **2,225** findings;
  adding `--naming-locals` finds **3,198** — **973 findings that were structurally invisible**
  a moment ago, scoped tightly (only inside functions already flagged large/complex, only locals
  nested two blocks deep for the short-name rule) so it doesn't just relabel every loop counter in
  the tree. Ships disabled by default on purpose: this repository's own history includes a naming
  rule that shipped on plausibility and was later measured to flag its *best*-named functions — see
  the withdrawn-rule note below — so a rule this new stays opt-in until a real-corpus audit clears it.

</details>

<details>
<summary>The full citation table, the evidence tiers, and the naming rule that was <b>withdrawn</b> for flagging this repository's best-named functions</summary>

Full citation table, evidence tiers, and what got measured and *withdrawn* (a naming rule that
flagged this repository's best-named functions, kept as the standing argument for measuring before
shipping) → [`docs/LINEAGE.md`](LINEAGE.md).
</details>


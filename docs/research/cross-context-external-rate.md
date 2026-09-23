# What fraction of human defect fixes are cross-context? — a pre-registration

**Status: pre-registration, written 2026-09-23, before any data.** No LocBench asset is on the
machine this was written on, no row has been scored under this recipe, and no number below is a
result. The commit that adds this file precedes every measurement it describes; that ordering is the
point of the file. A number produced by the recipe is reported by *amending this note* with a dated
"Outcome" section — never by editing the recipe.

An investigation note under [`research/`](../README.md), not a claim surface. Nothing here is quoted on
the front page.

---

## 0. The question, and why it has to be settled once

Two populations of defects have been measured for *locality* — whether a defect can be seen at the
site where the wrong code lives, or only by also reading a second site:

- **Internal arm** — defects in this project's own AI-authored code that survived its gates and
  review, recorded in the project's defect ledger (the `caught-by:` rows of its lane reports, kept
  outside this repository). Settled; stated as a chain in §2.
- **External arm** — human-authored fixes in the installed base: Loc-Bench V1, the public benchmark
  [`bench/locbench/`](../../bench/locbench/README.md) already scores localisation on.

The **contrast** between the two arms is the evidence behind a proposed class of *cross-context
consistency checks* (a check that compares two sites — an emitter and the table that declares its
output, a caller and a callee's contract, a literal and the population it mirrors — instead of
scoring one function against a bar). If human code is mostly cross-context too, the class is a
general linter idea and the differentiator is thin. If human code is mostly local and this project's
AI-authored defects are 7-to-1 cross-context, the contrast is stark and the class is the right bet.
The roadmap decision for the next minor release hangs on it, so the external number has to be
produced by a recipe a stranger can re-run, and it has to be settled once rather than re-derived per
document.

**Today the external figure is unquotable.** Two internal documents give it as **62%** and as
**17–38%**, and both are right about *something*, because they are two different readings of one
script's output (§1). Neither reading measures what the internal arm measures. Until this recipe has
run, the honest statement is: *the external arm is far weaker than the internal one, and our own two
proxies disagree.*

## 1. The two numbers, and what each one actually counted

Both come from one fix-shape script run over all 560 Loc-Bench rows on 2026-09-20. It read the fix
patch and nothing else:

| bucket | rule (verbatim from the script) | rows | share |
| --- | --- | ---: | ---: |
| `CROSS` | the patch changes ≥ 2 distinct files whose extension is in a 16-entry source list | 94 | 16.8% |
| `SPREAD-IN-FILE` | one such file, ≥ 2 hunks | 254 | 45.4% |
| `LOCAL` | one such file, exactly one hunk | 212 | 37.9% |

- **17–38%** reads the table as: cross-context is somewhere between "≥ 2 files" (17%) and "not
  one-hunk-in-one-file" (100 − 38 = 62%)… and then quotes the *lower* half of that range, because
  the script's own docstring says the proxy "systematically UNDER-counts cross-context".
- **62%** is the complement of `LOCAL`: everything that is not one hunk in one file. That counts a
  two-hunk fix inside one function as cross-context.

Three things make both readings unusable as *the* rate, whichever one is preferred:

1. **The 16-entry extension list does not exclude tests.** A one-line fix plus its regression test
   is two "source" files and lands in `CROSS`. The 17% is therefore inflated by exactly the fixes
   that are most local, and the 38% is deflated by them.
2. **A hunk is not a site.** Two hunks in one function are one place to look; two hunks in two
   functions of one file are two. The script's grain (file, then hunk) straddles the thing being
   measured.
3. **Fix spread is not defect visibility.** The internal definition (§2) asks whether the *defect*
   needs a second site to be *seen*. A one-file fix can be cross-context (the second site needed no
   edit — the code merely disagreed with it), and a three-file fix can be local (a null check plus a
   drive-by rename plus a changelog line). No mechanical reading of the patch reaches the internal
   definition. A judgement step is unavoidable, so §6 specifies one that is blinded, duplicated and
   scored for agreement.

Under this recipe both legacy numbers are **reproduced on purpose, as a fingerprint of the
population (§4.4), and neither is reported as the cross-context rate.**

## 2. The internal arm, stated as a chain

The internal figure is always stated with its denominators, never as a bare percentage:

> **377** rows in the `caught-by:` ledger (94 lane reports, 2026-09-06 … 2026-09-20)
> → **292** usable (the row names a defect, not only a mechanism)
> → **169** tagged by locality, **123** untagged (42.1% of usable)
> → of the 169 tagged: **149 CROSS (88%)** / **20 LOCAL (12%)**.

Wilson 95% interval on 149/169: **[82.4%, 92.2%]**.

**The tagging rule the external recipe has to match.** The internal tag is an ordered keyword rule
over the *text of the row* — the finder's one-line description of the defect — first match wins, and
a usable row matching neither list is UNTAGGED:

- **CROSS-CONTEXT** = "the defect cannot be seen without a SECOND site": the row names a table, a
  roster, a legend, a mirror or parity relation, a caller or call site, a callee, a clone or
  duplicate, a re-export or shadowing, a pin, a contract between two places, a registration or
  allowlist entry, something "undefined in" or "not defined by" another place, a test arm that does
  not exercise what it claims, a stale or drifted copy, a merge of two lanes.
- **LOCAL** = "the defect is visible inside one function or one file": a complexity or nesting bar
  crossed, an overflow, an out-of-bounds or off-by-one index, a greedy match, a wrong branch or loop,
  a missing null test, a wrong cast, a leak, a wrong return value or exit code, a typo, a regex.

**Known limits of the internal number, carried into every comparison.** (i) It is a keyword rule
over prose written by the finder, not a reading of the code; finders in this project name mechanisms
("table", "roster", "pin") habitually, so the rule likely over-fires toward CROSS relative to a
reader of the code. (ii) 42% of usable rows are untagged. (iii) "Usable" excludes only rows that name
no defect; it *includes* the ~25% of rows that are not code defects (a changelog count, a gate
registration), many of which tag CROSS through "stale"/"drift"/"disagree". (iv) One repository, two
weeks, under unusual discipline. Limits (i) and (iii) are the two that this recipe cannot remove on
the external side and must state (§3.4).

## 3. Definitions

### 3.1 Unit

One Loc-Bench row: a real GitHub issue, the repository at `base_commit`, and the accepted fix patch.
One row is one human defect fix. The rate is a fraction of rows.

### 3.2 Site

A **site** is `(file, definition)` at `base_commit`, where *definition* is the **outermost
function-level definition** enclosing a line: a module-level `def`, or a `Class.method`. A nested
`def` belongs to the function that contains it (a reader of the outer function sees it). Lines inside
a `class` body but outside any method map to `(file, Class)`. Lines outside every definition map to
`(file, <module>)`. Loc-Bench is all-Python, so definitions are read with Python's own `ast`
(`lineno`/`end_lineno`), not with a regex and not with this tool — the recipe is deliberately
independent of the ripwire binary so no ranking or parsing choice of ours can move it. A file in
another language (a C extension in a Python repository) is one site `(file, <file>)`, flagged
`otherlang`.

This spelling — `path:Class.method`, `path:func` — is the one Loc-Bench's own `edit_functions`
field already uses, which gives the mechanical stage a free cross-check (§5, M8).

### 3.3 CROSS-CONTEXT / LOCAL / UNTAGGED, for a human fix

The **primary site** is the site whose pre-fix code was wrong. The **second-site test** — the
operational form of the internal rule's "cannot be seen without a second site" — is a *quote test*:

> To justify the fix to a colleague, what would you have to quote? If the primary site's pre-fix
> text, the language's semantics and the issue's symptom are enough, the defect is **LOCAL**. If
> you would have to quote text from a **second site** — a callee's or caller's contract, a table,
> enum, constant or format defined elsewhere, a sibling that must agree, a schema or configuration,
> a registration, a test whose assertion did not exercise the claim — the defect is
> **CROSS-CONTEXT**, and the second site is named.

**UNTAGGED** holds everything else: the two raters disagree (§6, R6), a rater cannot decide within
budget, or the row is not a defect fix at all (a feature request, a docs change, a pure refactor) —
the last is its own sub-bucket, `NOT-A-DEFECT`, and is reported separately because it is the
external analogue of the internal ledger's non-code rows.

The rate reported for comparison with the internal 88% is **CROSS / (CROSS + LOCAL)** over tagged
rows, with the untagged fraction printed beside it — the same shape as the internal chain.

### 3.4 Where the two definitions cannot match, and what that does to comparability

| difference | internal | external (this recipe) | effect |
| --- | --- | --- | --- |
| instrument | keyword rule over the finder's prose | two blinded raters over issue + patch + pre-fix sites | internal likely biased toward CROSS (§2 limit i); the contrast is therefore, if anything, *over*-stated by the internal side. A STARK verdict (§9) must survive that bias; a THIN verdict is only strengthened by it. |
| non-code rows | included in the 292 (≈25%), many tag CROSS | Loc-Bench rows are code fixes by construction; non-defect rows go to `NOT-A-DEFECT` | reported as a **pre-stated internal sensitivity**: the chain re-derived with the ledger's "not a code defect" class removed, produced by re-running the ledger's own classifier with that class excluded, and printed next to 88% in the Outcome. Not produced here. |
| grain of "one site" | "one function **or one file**" | function/method grain (primary); file grain as a sensitivity | primary is function grain because every CROSS category in the internal rule (caller, table, mirror) is a relation between *definitions*, whatever file they share; the file-grain rate is reported too (§7). |
| population | AI-authored code that survived the project's full gate suite + review, one repo, two weeks | human fixes to user-reported issues, ~250 repositories | both are *escaped* defects — selected by surviving a process — so the selection is similar in kind and different in strength; not correctable, stated. |
| untagged | 42% | whatever the raters produce | if the external untagged fraction exceeds 50%, the tagged rate is reported but the decision (§9) is INDETERMINATE regardless of its value. |

## 4. Population — pinned so the run can prove what it scored

### 4.1 The set

**Loc-Bench V1, `test` split, all 560 rows**, exactly as [`dataset.lock`](../../bench/locbench/dataset.lock)
pins them: `rows_json_sha256 = 5bbcea4bff11396f38f8aca3e64d697a8ea1da2bc54d705da7f6e34886804c97`.
The run refuses a rows file whose SHA-256 differs. Rows are processed in **sorted `instance_id`
order** (the legacy script's order), so every systematic sample below is a function of the set alone.

### 4.2 Pre-fix trees

Each row's `base_commit` is materialised with `bench/locbench/run_locbench.py`'s `checkout()` at
`--history-depth 1` — the recipe reads only `base_commit`'s own tree (`git show <base_commit>:<path>`),
never a parent, so a depth-1 clone suffices. **No history walk of any kind**: no `git log`, no
`rev-list`, no `--all`. A row whose `base_commit` cannot be materialised is `EXCLUDED-UNAVAILABLE`
and counted; it is not silently skipped and it is not scored.

### 4.3 The manifest

Before any label exists, the run writes `crossctx_population.tsv` — one line per row:
`instance_id \t repo \t base_commit \t mechanical_class` — and prints its SHA-256. **Every figure
in the Outcome names that hash.** A figure without it is not a result under this registration.

### 4.4 Fingerprint — the legacy rule, recomputed verbatim

Before the site stage runs, the legacy fix-shape rule (§1: 16-extension list, `diff --git a/… b/…`
file regex, hunk count inside the first source file's diff section, tests *not* excluded) is
recomputed over the 560 rows. It must return **CROSS 94 / SPREAD-IN-FILE 254 / LOCAL 212**. If it
does not, the rows are not the set the legacy numbers came from; the run stops there and reports the
counts it got instead. Passing this proves the population; it says nothing about the answer.

### 4.5 Floors

Counts are totals only if `EXCLUDED-UNAVAILABLE = 0`. Otherwise every count over scoreable rows is a
**floor** and is labelled one, and if more than 5% of the 560 are unavailable the Outcome opens by
saying so.

## 5. Recipe — the mechanical stage (no judgement; runs on all scoreable rows)

Every step is implemented in [`bench/locbench/crossctx_sites.py`](../../bench/locbench/crossctx_sites.py),
whose unit tests are synthetic ([`test_crossctx_sites.py`](../../bench/locbench/test_crossctx_sites.py))
and read no Loc-Bench data.

**M1 — parse the patch.** Unified diff → per-file sections (`old_path`, `new_path`, rename flag,
hunks with `old_start`/`old_len` and their lines).

**M2 — classify each file by path, first match wins:**

| class | rule | counted as a site? |
| --- | --- | --- |
| `TEST` | a path component in {`test`, `tests`, `testing`, `spec`, `specs`}, or basename starts with `test_`, or ends with `_test.py`/`_tests.py`, or is `conftest.py` | no — a test edit is evidence about the defect, not the defect's site |
| `DOC` | extension `.md`/`.rst`/`.txt`, or a path component in {`doc`, `docs`, `changelog.d`, `changes`, `news`, `release-notes`, `releasenotes`}, or basename starts with `CHANGELOG`/`CHANGES`/`NEWS`/`HISTORY`/`README`/`AUTHORS` | no |
| `GENERATED` | a path component in {`migrations`, `versions`} (Django/Alembic migrations), or basename `_version.py`, or the file's first 3 lines contain `generated` / `do not edit` (case-insensitive) | no — a migration is a *consequence* of the fix, not a place the defect was visible; the DEFECT-side question is the raters' (§6) |
| `SOURCE` | extension `.py` or `.pyi` | yes |
| `OTHERLANG` | any other extension in the 16-entry legacy list | yes, as one site `(file, <file>)`, flagged |
| `NONSOURCE` | everything else (`.json`, `.yaml`, `.toml`, `.cfg`, `.po`, lockfiles, images, …) | no |

**M3 — changed old lines per hunk.** The old line numbers of the hunk's `-` lines. A hunk with no
`-` lines (pure insertion) contributes one **anchor** line: the old line immediately preceding the
insertion point (old line 1 if the insertion is at the top of a non-empty file; `<module>` for an
empty file). Context lines never contribute.

**M4 — map lines to definitions.** Read `base_commit:old_path`, parse with `ast`, collect spans of
every module-level `def`/`async def`, every `class`, and every method (outermost function level,
nested functions collapsed into their parent), then map each changed line to the innermost span of
that set, or `(file, Class)` / `(file, <module>)` as §3.2 says. A file that does not parse at
`base_commit` (a syntax error is possible in a pre-fix tree) is one site `(file, <unparsed>)`,
flagged; if the *fix* is to the syntax error, the raters will see that.

**M5 — the site set** `S` = the distinct `(file, definition)` pairs from M4 over all `SOURCE` and
`OTHERLANG` files. Two hunks in one function are one site. A pure rename with no hunks contributes
no site (flag `rename_only`).

**M6 — moves.** A block of ≥ 3 non-blank `-` lines in one file whose whitespace-normalised
multiset equals the `+` lines of a hunk in *another* file is a **move**; the row is flagged `move`.
In the primary analysis both ends count as sites (relocating code is a relation between two places).
Sensitivity: moves collapsed to the destination site.

**M7 — mechanical class:**

| class | rule |
| --- | --- |
| `NON-CODE` | `S` is empty and no `TEST` hunk exists (docs/config only) — excluded from the denominator, counted |
| `TEST-ONLY` | `S` is empty and at least one `TEST` hunk exists — excluded, counted |
| `ONE-SITE` | `|S| = 1` |
| `MULTI-SITE-ONE-FILE` | `|S| ≥ 2`, all in one file |
| `MULTI-FILE` | `|S| ≥ 2`, in ≥ 2 files |

`ONE-SITE ∪ MULTI-SITE-ONE-FILE ∪ MULTI-FILE` is the **scoreable** set, `N`.

**M8 — cross-check against the dataset's own gold.** For each row, `S` (spelled `path:qualname`) is
compared with Loc-Bench's `edit_functions ∪ added_functions`. Agreement (Jaccard, and the count of
rows where the two sets are identical) is reported. It is a check on M1–M5's plumbing, not a
result; a Jaccard below 0.7 over the scoreable set stops the run for diagnosis before the rater
stage begins.

**M9 — the legacy proxies at the new grain**, reported as descriptive bounds only: the `MULTI-FILE`
share (the test-excluded analogue of the 17%), and `1 − ONE-SITE share` (the site-grain analogue of
the 62%). Neither is the answer; both are printed so the reader can see where the legacy figures
sit once tests and hunks are handled.

## 6. Recipe — the rater stage (the second-site test)

**R1 — sample.** Within each of the three scoreable strata, rows sorted by `instance_id`, take every
`k`-th starting at index 0 with `k = max(1, ⌊N_s / 40⌋)`: at least 40 rows per stratum when the
stratum has them, all of them otherwise. The sample is a function of the manifest and nothing else.
Expected size ≈ 120 rows.

**R2 — the packet**, one per sampled row, assembled mechanically: the issue title and body
(`problem_statement`, in full); the fix patch (all hunks, tests and docs included — they help
identify the defect); for every site in `S`, the full pre-fix text of that definition at
`base_commit`. The packet carries the `instance_id` and nothing about the mechanical class, this
note's §9, or the other rater.

**R3 — raters.** Two raters, each a *fresh* session (a person, or an agent given only §3 and this
§6 — not §1, §2 or §9 of this note), working independently, never shown the other's labels. Their
full transcripts or worksheets are kept with the run. If the raters are agents, they are of
different model families where that is possible, and the report says which.

**R4 — questions, fixed wording.** For each packet:

1. *Primary site.* Which site in the list holds the pre-fix code that was wrong? (One site; or
   `NOT-A-DEFECT` if the change is a feature, a docs-only change, or a refactor with no wrong
   behaviour named in the issue.)
2. *Quote test.* To justify the fix, what would you have to quote — only the primary site's pre-fix
   text (plus the language and the issue's symptom), or text from a second site as well?
   → `LOCAL` / `CROSS`.
3. *If CROSS:* name the second site and pick one relation from the internal rule's list (§2):
   caller/callee contract · table/roster/registration entry · constant/format/schema defined
   elsewhere · sibling or clone that must agree · mirror/parity copy · test arm not exercising the
   claim · other (free text).
4. *Confidence:* `sure` / `unsure`. A rater who cannot decide in ten minutes writes `UNDECIDED`.

**R5 — no discussion, no adjudication.** Disagreements are not talked through: the row is
`UNTAGGED`. This mirrors the internal chain, where an undecidable row is counted and dropped rather
than forced.

**R6 — the label per row.** `CROSS` if both say CROSS; `LOCAL` if both say LOCAL; otherwise
`UNTAGGED`, with sub-buckets `DISAGREE`, `UNDECIDED` (either rater), `NOT-A-DEFECT` (either rater).

**R7 — agreement.** Cohen's κ over the two raters' three-way labels (CROSS / LOCAL / other), and
binary κ over rows where both chose CROSS or LOCAL. **Reliability floor:** binary κ ≥ 0.60 for the
rater-based rate to be quotable and to feed §9; 0.40 ≤ κ < 0.60 is reported as "moderate agreement",
the rate is printed with that label and §9 is INDETERMINATE; κ < 0.40 means the rater stage failed —
only the mechanical numbers are reported and §9 is INDETERMINATE.

**R8 — order of operations.** The rater stage begins only after M1–M9 have run and the manifest
hash, the fingerprint and the M8 check are recorded. No rater sees any aggregate.

## 7. Estimators

- **Per stratum** `s`: `p̂_s = CROSS_s / (CROSS_s + LOCAL_s)` over the stratum's tagged sample rows.
- **Primary estimate** (the number compared with 88%): `P̂ = Σ_s (N_s / N) · p̂_s` — the post-
  stratified rate over the scoreable set, weights from the *whole* manifest, rates from the sample.
- **Interval:** 2,000 within-stratum bootstrap resamples of the tagged sample rows, seed
  `20260923`, percentile 2.5 / 97.5. Wilson intervals are printed for every raw count too.
- **Untagged fraction** `U = UNTAGGED / sampled`, with sub-buckets, beside the internal 42%.
- **Sensitivities**, each one line: file grain (a second site in the same file is LOCAL), moves
  collapsed, `otherlang` rows dropped, disagreements resolved toward CROSS and toward LOCAL (the two
  bounds), the sample's unweighted rate.
- **Internal comparator:** 149/169 with its Wilson interval, and — when the pre-stated sensitivity
  in §3.4 has been produced — the chain with non-code rows removed. Risk difference
  `internal − external` with a bootstrap interval.

## 8. Reported in every outcome

The Outcome section, whatever the numbers, contains this table with every cell filled, plus the
manifest hash, the `dataset.lock` hash, the checkout depth, the rater identities (kind and, for
agents, family), and the date:

```
560 rows
  EXCLUDED-UNAVAILABLE   n   (base_commit not materialised)
  NON-CODE               n
  TEST-ONLY              n
  scoreable N            n
    ONE-SITE               N_1   sampled n_1   CROSS c  LOCAL l  UNTAGGED u (DISAGREE/UNDECIDED/NOT-A-DEFECT)
    MULTI-SITE-ONE-FILE    N_2   sampled n_2   ...
    MULTI-FILE             N_3   sampled n_3   ...
  fingerprint (legacy rule)      CROSS 94 / SPREAD 254 / LOCAL 212   [pass|fail]
  M8 gold agreement              Jaccard j, identical k/N
  M9 descriptive                 MULTI-FILE share, 1 - ONE-SITE share
  kappa                          3-way κ, binary κ, n
  P̂ (post-stratified)            p  [lo, hi]      U = untagged share
  sensitivities                  file-grain p, moves-collapsed p, otherlang-dropped p, bounds [p_LOCAL, p_CROSS]
  internal                       149/169 = 88.2% [82.4, 92.2]   (chain; non-code-removed chain if produced)
  contrast                       internal − P̂ = d  [lo, hi]
  decision (§9)                  STARK | THIN | INDETERMINATE, with the clause that fired
```

## 9. Expectations, and the decision the number feeds

**What the recipe is expected to reproduce.** The legacy **94 / 254 / 212** — exactly, as the
population fingerprint (§4.4), and only because it recomputes the legacy rule verbatim. It is *not*
expected to reproduce either 62% or 17–38% as the cross-context rate, and the note says now why not
so that no later reading can call a mismatch a surprise: 62% counts multi-hunk-one-function fixes and
test hunks as cross-context (over-states); 17% counts a fix plus its test as two source files while
missing every one-file fix whose second site needed no edit (mis-states in both directions). The
site-grain descriptive shares (M9) are expected to land *between* the two legacy figures. No
directional prior on the rater-based `P̂` is registered as a hypothesis; the thresholds below are
the whole of what is pre-stated.

**Decision rule**, anchored on the roadmap ruling that framed the question ("at 62% human code is
also mostly cross-context and the differentiator is thin; at 17–38% the contrast is stark"):

| verdict | condition on `P̂`'s 95% interval `[lo, hi]` | consequence for the roadmap |
| --- | --- | --- |
| **STARK** | `hi ≤ 0.50`, **and** binary κ ≥ 0.60, **and** `U ≤ 0.50` | the arm contrast stands as evidence for the cross-context check class; the class's next candidate is justified by the contrast *plus* its own precision measurement |
| **THIN** | `lo ≥ 0.60` (κ and `U` as above) | human code is mostly cross-context too; the class may still be worth building, but **not on the strength of the contrast** — its case must rest entirely on its own precision measurement, and the "AI-authored defects are different" framing is withdrawn from every document that uses it |
| **INDETERMINATE** | anything else — including any failure of the κ floor, `U > 0.50`, a failed fingerprint, or a failed M8 check | the contrast is unproven; documents quote the internal chain with its caveats and say the external arm did not settle; the class is judged on its own precision measurement alone |

`hi ≤ 0.50` is chosen so that a STARK verdict requires the external interval to sit at least 32
points below the internal interval's *lower* bound (82.4%) — wide enough to survive the internal
side's known bias toward CROSS (§2 limit i). `lo ≥ 0.60` is the roadmap's own "thin" anchor less two
points for the interval.

**What no outcome licenses.** Any statement about software in general; a per-repository rate (the
sample is ~120 rows over ~250 repositories); a claim that any *particular* check would have caught a
particular fix (this measures where defects are visible, not whether a predicate finds them); pooling
the two arms.

## 10. Amendments and self-reject

- An amendment to §3–§7 is allowed **only before R1 runs**, must be dated and appended to this note
  with its reason, and must be committed before the rater stage starts. After R1, a change to any
  rule or constant is a new pre-registration, not a fix.
- The fingerprint (§4.4) failing, the M8 check failing, or the κ floor failing are **stops**, not
  amendments: the Outcome reports the failure and the decision is INDETERMINATE.
- Nothing in this recipe depends on the ripwire binary, so no build, flag or ranking change can move
  the result; a re-run on a different day with the same `dataset.lock` must reproduce the manifest
  hash, the fingerprint and every mechanical count exactly, and the rater counts up to rater
  variance (which κ reports).

## 11. Code

[`bench/locbench/crossctx_sites.py`](../../bench/locbench/crossctx_sites.py) implements M1–M9, R1,
the estimators of §7 and the decision table of §9 as pure functions, plus a `main()` that refuses to
run without an explicit rows file and checkout directory and refuses a rows file whose SHA-256 is
not the pinned one. It fetches nothing and walks no history. Its tests,
[`bench/locbench/test_crossctx_sites.py`](../../bench/locbench/test_crossctx_sites.py), are
synthetic only — hand-written patches and a hand-written Python module — and pin, among other
things, the internal comparator's Wilson interval and the decision thresholds, so a later edit to a
constant fails a test rather than moving silently.

```bash
python3 bench/locbench/test_crossctx_sites.py            # synthetic checks; touches no data
python3 bench/locbench/crossctx_sites.py --rows ROWS.json --repos-dir DIR --out OUTDIR   # the run, later
```

## 12. Decisions taken here, listed for an adversarial reviewer

1. **Function/method grain as the primary unit**, file grain as sensitivity (§3.2, §3.4). The
   internal rule says "one function or one file"; the choice follows the CROSS categories, which are
   relations between definitions.
2. **Tests, docs, migrations and other generated files are not sites** (M2). This removes the
   legacy 17%'s test inflation and treats a migration as a consequence of the fix rather than a place
   the defect was visible. The rater stage, not the mechanical stage, decides whether a fix that
   *also* touched a migration was cross-context.
3. **A pure insertion anchors to the preceding old line** (M3), so a new method lands on its class,
   a new function on `<module>`. Alternative: a new definition is its own site — rejected because it
   does not exist at `base_commit`, which is where sites are defined.
4. **Moves count as two sites in the primary analysis** (M6), with the collapsed rate as a
   sensitivity. Arguable either way; both numbers are printed.
5. **Disagreements become UNTAGGED rather than adjudicated** (R5). Adjudication by discussion is not
   blind; a third rater doubles the cost. The two bounds (all disagreements → CROSS, all → LOCAL) are
   reported so the reader sees what adjudication could at most have moved.
6. **The quote test as the operational form of "needs a second site to see"** (§3.3). It is the
   closest reading of the internal rule that a rater can apply to code rather than to prose. Its
   known weakness: a rater who knows the codebase well may need to quote less. Fresh sessions (R3)
   are the mitigation.
7. **The issue's symptom is given to the rater.** Without it the rater cannot identify the defect;
   with it, "is the wrongness visible here" becomes answerable. The internal finders also knew the
   symptom when they wrote the row.
8. **Stratified sampling with a 40-per-stratum floor** (R1) rather than a simple systematic sample:
   the mechanical class is the obvious confounder and the stratum sizes are known for all rows, so
   post-stratification is free precision. Cost: ~120 packets × 2 raters.
9. **The κ floor at 0.60** (R7). Below it two raters are not applying one definition and no rate is
   a rate of anything. 0.60 is a conventional "substantial agreement" cut, chosen before any packet
   exists.
10. **STARK at `hi ≤ 0.50`, THIN at `lo ≥ 0.60`** (§9), from the roadmap's own anchors (17–38 stark,
    62 thin) with the interval, not the point, doing the work. A reviewer who wants the stark bar
    lower should say so before R1.
11. **The recipe does not use the ripwire binary.** A tool that measures its own motivation is a
    conflict of interest; `ast` and `git show` are enough for the mechanical stage. The cost is that
    `OTHERLANG` files are one coarse site each, flagged and counted.
12. **The internal sensitivity (non-code rows removed) is pre-stated but not produced here** (§3.4).
    It needs the ledger, which is not on this machine and not in this repository. Its absence in an
    Outcome is reported as such, not filled by inference.

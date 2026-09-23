# What fraction of human defect fixes are cross-context? — a pre-registration

**Status: pre-registration, written 2026-09-23, before any data; amendment 1 the same day, after an
adversarial review and still before any data.** No LocBench asset is on the machine this was written
on, no row has been scored under this recipe, and no external number below is a result. The commits that
add and amend this file precede every measurement it describes; that ordering is the point of the file.
A number produced by the recipe is reported by *amending this note* with a dated "Outcome" section —
never by editing the recipe. The amendment record is §13.

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
   definition. A judgement step is unavoidable, so §6 specifies one that is blinded, duplicated,
   given the repository to read, and scored for agreement.

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
a usable row matching neither list is UNTAGGED. The two lists below are **paraphrased** from the rule
kept with the ledger; they name its categories, not its verbatim patterns:

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
weeks, under unusual discipline. Limit (iii) is now measured (§13, amendment 1): with the ledger's
"not a code defect" class removed the chain is **209 usable → 124 tagged, 85 untagged (40.7%) → 109
CROSS (87.9%) / 15 LOCAL**, Wilson **[81.0%, 92.5%]** — the rate does not move. Limit (i) cannot be
removed on the internal side and is stated wherever the arms are compared (§3.4).

## 3. Definitions

### 3.1 Unit

One Loc-Bench row: a real GitHub issue, the repository at `base_commit`, and the accepted fix patch.
One row is one human defect fix. The rate is a fraction of rows.

### 3.2 Site

A **site** is `(file, definition)` at `base_commit`, where *definition* is the **outermost
function-level definition** enclosing a line: a module-level `def`, or a `Class.method`. A nested
`def` belongs to the function that contains it (a reader of the outer function sees it). Lines inside
a `class` body but outside any method map to `(file, Class)`. Lines outside every definition map to
`(file, <module>)`. A definition under a module- or class-level `if`, `try` or `with` (an
`if TYPE_CHECKING:` class, an `except ImportError:` fallback) is a definition like any other.
Loc-Bench is all-Python, so definitions are read with Python's own `ast` (`lineno`/`end_lineno`), not
with a regex and not with this tool — the recipe is deliberately independent of the ripwire binary so
no ranking or parsing choice of ours can move it. A file in another language (a C extension in a
Python repository) is one site `(file, <file>)`, flagged `otherlang`.

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

**The second site must be a site in the repository at `base_commit`**, spelled `path:definition`,
distinct from the primary site; the driver verifies that it exists there (§6, R6) and a CROSS answer
whose second site does not verify becomes UNDECIDED, counted in its own sub-bucket. Whether the fix
*also* edited the second site is recorded (`second_site_edited`) and reported, not penalised: in the
multi-site strata the second site usually is one the fix touched, and that is the cross-context case,
not a defect of it. A contract that lives only *outside* the repository — a third-party library's
behaviour, an HTTP API, a language-version change — does not make a defect CROSS: it is **LOCAL**,
flagged `external_contract`, and the count is reported. Without that rule raters split on framework
fixes and the split reads as disagreement.

**UNTAGGED** holds everything else: the two raters disagree (R6), a rater cannot decide within budget
or exceeds it, a CROSS answer's second site did not verify, or the row is not a defect fix at all (a
feature request, a docs change, a pure refactor) — the last is its own sub-bucket, `NOT-A-DEFECT`, and
is reported separately because it is the external analogue of the internal ledger's non-code rows.

The rate reported for comparison with the internal 88% is **CROSS / (CROSS + LOCAL)** over tagged
rows, with the untagged fraction printed beside it — the same shape as the internal chain.

### 3.4 Where the two definitions cannot match, and what that does to comparability

| difference | internal | external (this recipe) | effect |
| --- | --- | --- | --- |
| instrument | keyword rule over the finder's prose | two blinded raters over issue + patch + pre-fix sites + read access to the tree | internal likely biased toward CROSS (§2 limit i); the contrast is therefore, if anything, *over*-stated by the internal side. A STARK verdict (§9) must survive that bias; a THIN verdict is only strengthened by it. |
| what a rater can see | the finder saw the whole repository | R2's packet alone would carry only the sites the *fix* touched, so a second site that needed no edit — exactly the class §1 item 3 says no proxy reaches — could not be quoted or named, and the cheap answer would be LOCAL (toward STARK). **Closed** by R3's read-only tree access. Residual: a rater reads less of the tree than a developer would, so some second sites will go unfound → still toward LOCAL/STARK, bounded by the read budget and reported through the `UNVERIFIED-SECOND-SITE` and `UNDECIDED` counts. |
| kind of test | the LOCAL list is a list of *defect kinds* (overflow, off-by-one, null test, typo) | the quote test asks what must be *quoted* | a null-check fix justified by "the callee can return None" is LOCAL under the internal list and CROSS under the quote test → external CROSS inflated → toward THIN → conservative for STARK. |
| non-code rows | included in the 292 (≈25%), many tag CROSS | Loc-Bench rows are code fixes by construction; non-defect rows go to `NOT-A-DEFECT` | **measured** (amendment 1): removing the ledger's non-code class gives 109/124 = 87.9% [81.0, 92.5] against 149/169 = 88.2% [82.4, 92.2]. Both chains are printed in every Outcome. |
| grain of "one site" | "one function **or one file**" | function/method grain (primary); file grain as a sensitivity | primary is function grain because every CROSS category in the internal rule (caller, table, mirror) is a relation between *definitions*, whatever file they share; the file-grain rate is reported too (§7). |
| population | AI-authored code that survived the project's full gate suite + review, one repo, two weeks | human fixes to user-reported issues, ~250 repositories | both are *escaped* defects — selected by surviving a process — so the selection is similar in kind and different in strength; not correctable, stated. |
| who rates | the finders were the developers | the raters are **model agents**, not developers of the repository; their judgement is a proxy for a human colleague's, and κ between two models is an agreement measure *between models*, which shared training can inflate | stated as a limitation in every Outcome; two different model families are mandatory (R3), and a human blind read of a fixed 20-row subset is recommended as a third, non-decision-bearing check. |
| untagged | 42% | whatever the raters produce | if the external untagged fraction exceeds 50%, the tagged rate is reported but the decision (§9) is INDETERMINATE regardless of its value. |

## 4. Population — pinned so the run can prove what it scored

### 4.1 The set

**Loc-Bench V1, `test` split, all 560 rows**, exactly as [`dataset.lock`](../../bench/locbench/dataset.lock)
pins them: `rows_json_sha256 = 5bbcea4bff11396f38f8aca3e64d697a8ea1da2bc54d705da7f6e34886804c97`.
The run refuses a rows file whose SHA-256 differs. Rows are processed in **sorted `instance_id`
order** (the legacy script's order), so every systematic sample below is a function of the set alone.

### 4.2 Pre-fix trees — the registered materialisation step

Each row's `base_commit` tree is materialised by the run's own `--materialise` step, which calls
`bench/locbench/run_locbench.py`'s `checkout(repo, base_commit, repos_dir, 1)` once per distinct
`(repo, base_commit)`: one directory per repository (~250 of them), a depth-1 shallow fetch of that one
commit, several commits per repository handled by the function's own per-sha markers, and a fetch that
**fails closed** (a row whose commit cannot be fetched is `EXCLUDED-UNAVAILABLE`, never silently
scored). The recipe reads only `base_commit`'s own tree (`git show <base_commit>:<path>`), never a
parent, so depth 1 suffices. **No history walk of any kind**: no `git log`, no `rev-list`, no `--all`.
The step fetches from the repositories' public hosts and is run only with the owner's go-ahead on the
machine that runs it; without `--materialise` the run scores whatever checkouts are already present and
counts the rest as unavailable.

### 4.3 The manifest

Before any label exists, the run writes `crossctx_population.tsv` — one line per row, seven columns:
`instance_id`, `repo`, `base_commit`, `mclass` (§5 M7, or an excluded bucket), `n_sites`, `flags`
(sorted, comma-joined: `move`, `otherlang`, `unparsed`, `rename_only`, `new_file`, `unreadable`,
`test_dir_only`), `mclass_collapsed` (the class with moves collapsed, M6) — and prints its SHA-256.
Every sensitivity in §7 is recomputable from the manifest and the labels alone. **Every figure in the
Outcome names that hash.** A figure without it is not a result under this registration.

### 4.4 Fingerprint — the legacy rule, recomputed verbatim

Before the site stage runs, the legacy fix-shape rule (§1: 16-extension list, `diff --git a/… b/…`
file regex, hunk count inside the first source file's diff section, tests *not* excluded) is
recomputed over the 560 rows. It must return **CROSS 94 / SPREAD-IN-FILE 254 / LOCAL 212**. If it
does not, the rows are not the set the legacy numbers came from; the run stops there and reports the
counts it got instead. Passing this proves the *rows file* is the one the legacy numbers came from
and that the rule was re-implemented verbatim; it says nothing about the answer, and it does not pin
the *scored* set — the manifest does (§4.3).

### 4.5 Floors

Counts are totals only if `EXCLUDED-UNAVAILABLE + EXCLUDED-UNREADABLE = 0`. Otherwise every count
over scoreable rows is a **floor** and is labelled one; if more than 5% of the 560 are unavailable or
unreadable, **the estimate is of the materialised sub-population**, the Outcome opens by saying so,
and the excluded rows are listed per repository so a reader can see which projects are missing.

## 5. Recipe — the mechanical stage (no judgement; runs on all scoreable rows)

Every step is implemented in [`bench/locbench/crossctx_sites.py`](../../bench/locbench/crossctx_sites.py),
whose unit tests are synthetic ([`test_crossctx_sites.py`](../../bench/locbench/test_crossctx_sites.py))
and read no Loc-Bench data.

**M1 — parse the patch.** Unified diff → per-file sections (`old_path`, `new_path`, rename flag,
`/dev/null` sides for new and deleted files, hunks with `old_start`/`old_len` and their lines). The
*file identity* used everywhere below is the pre-fix path (a rename is the same file; a brand-new
file is identified by its new path).

**M2 — classify each file by path, first match wins:**

| class | rule | counted as a site? |
| --- | --- | --- |
| `TEST` | a path component in {`test`, `tests`, `testing`, `spec`, `specs`}, or basename starts with `test_`, or ends with `_test.py`/`_tests.py`, or is `conftest.py` | no — a test edit is evidence about the defect, not the defect's site. **Known limit:** product source under a `test`/`testing` directory (`django/test/client.py`, `numpy/testing/…`) is excluded by the directory rule. A `TEST-ONLY` row whose verdict rests on the directory rule *alone* is flagged `test_dir_only`; every `TEST-ONLY` row's paths are listed in the Outcome, and the flagged count bounds the loss (§7). |
| `DOC` | extension `.md`/`.rst`/`.txt`; or, **for a non-code extension only**, a path component in {`doc`, `docs`, `changelog.d`, `changes`, `news`, `release-notes`, `releasenotes`} or basename starting with `CHANGELOG`/`CHANGES`/`NEWS`/`HISTORY`/`README`/`AUTHORS` | no. `pkg/history.py`, `app/news.py`, `docs/conf.py` are SOURCE. |
| `GENERATED` | a path component in {`migrations`, `versions`} (Django/Alembic migrations), or basename `_version.py`, or a **comment line** among the file's first 3 lines matching `auto-generated` / `automatically generated` / `generated by` / `do not edit` (case-insensitive; a docstring's prose never fires it) | no — a migration is a *consequence* of the fix, not a place the defect was visible; the DEFECT-side question is the raters' (§6) |
| `SOURCE` | extension `.py` or `.pyi` | yes |
| `OTHERLANG` | any other extension in the 16-entry legacy list | yes, as one site `(file, <file>)`, flagged |
| `NONSOURCE` | everything else (`.json`, `.yaml`, `.toml`, `.cfg`, `.po`, lockfiles, images, …) | no |

**M3 — changed old lines per hunk, and insertions.** The old line numbers of the hunk's `-` lines
are the changed lines. A hunk with no `-` lines (pure insertion) has an **anchor**: the old line
immediately preceding the insertion point (old line 1 at the top of a non-empty file; `<module>` for
an empty file). Then:

- If the insertion's first non-blank `+` line **begins a definition** (`@decorator`, `def`,
  `async def`, `class`), the site is the **container the new definition belongs to**, decided by
  indentation, not by where git placed the hunk: indent 0 → `(file, <module>)`; otherwise the innermost
  definition containing the anchor whose own column is shallower than the new indent (a class for a
  new method, a method for a new nested def); `<module>` when none contains it. A new top-level `def`
  inserted after `helper` is `<module>` whether git anchors the hunk on `helper`'s last line or on the
  blank line after it.
- Any other pure insertion (new statements inside a body) is attributed to the definition enclosing
  the anchor, as a `-` line would be. Here the anchor *is* where the dataset's patch places the hunk,
  which git chooses among equivalent positions; an insertion of plain statements exactly between two
  definitions is attributed by that placement, and this is stated rather than corrected.

Context lines never contribute.

**M4 — map lines to definitions.** Read `base_commit:old_path`, parse with `ast`, collect spans (with
their column) of every module-level `def`/`async def`, every `class`, and every method (outermost
function level, nested functions collapsed into their parent), **descending through module- and
class-level `if`/`try`/`with` bodies, `else`/`except`/`finally` included**; then map each changed line
to the innermost span of that set, or `(file, Class)` / `(file, <module>)` as §3.2 says. A file that
does not parse at `base_commit` is one site `(file, <unparsed>)`, flagged; if the *fix* is to the
syntax error, the raters will see that. A pre-fix file that *should* exist and cannot be read is a
materialisation failure: the row is `EXCLUDED-UNREADABLE`, never `NON-CODE`.

**M5 — the site set** `S` = the distinct `(file, definition)` pairs from M3–M4 over all `SOURCE` and
`OTHERLANG` files. Two hunks in one function are one site. A pure rename with no hunks contributes
no site (flag `rename_only`). A brand-new source file contributes no site (flag `new_file`; it does not
exist at `base_commit`, where sites are defined).

**M6 — moves.** A hunk whose non-blank `-` lines, as a whitespace-normalised multiset of ≥ 3 lines,
equal the non-blank `+` lines of a hunk in **another file** (file identity = pre-fix path, so a
renamed file moving a block within itself is *not* a move) is a **move source**; the row is flagged
`move`. Detection is whole-hunk equality, so a destination hunk that also adds an import defeats it —
moves are under-flagged, and this is stated. In the primary analysis both ends count as sites
(relocating code is a relation between two places). Sensitivity: **moves collapsed** = the site set
with the move sources' hunks removed; the resulting class is the manifest's `mclass_collapsed`.

**M7 — mechanical class:**

| class | rule |
| --- | --- |
| `EXCLUDED-UNAVAILABLE` | `base_commit` not materialised (§4.2) — excluded, counted, listed per repository |
| `EXCLUDED-UNREADABLE` | a pre-fix file the patch edits could not be read at `base_commit` — excluded, counted, listed per repository |
| `NON-CODE` | `S` is empty, no `TEST` hunk, no new source file (docs/config only) — excluded, counted |
| `TEST-ONLY` | `S` is empty and at least one `TEST` hunk exists — excluded, counted, paths listed |
| `NEW-FILE-ONLY` | `S` is empty, no `TEST` hunk, and the fix adds a new source file — excluded, counted |
| `ONE-SITE` | `|S| = 1` |
| `MULTI-SITE-ONE-FILE` | `|S| ≥ 2`, all in one file |
| `MULTI-FILE` | `|S| ≥ 2`, in ≥ 2 files |

`ONE-SITE ∪ MULTI-SITE-ONE-FILE ∪ MULTI-FILE` is the **scoreable** set, `N`.

**M8 — cross-check against the dataset's own gold, as recall.** For each scoreable row, the
**recall** of Loc-Bench's `edit_functions` whose file is `SOURCE` under M2 — spelled `path:Class.method`
/ `path:func`, the dataset's own spelling — in `S`. `added_functions` are never in `S` by construction
(M5) and are not gold here; test-file gold is not `SOURCE` gold; a nested gold `outer.inner` cannot be
recalled (`S` collapses it to `outer`) — a stated, small loss. Mean recall over rows with such gold
must be **≥ 0.70** or the run stops for diagnosis before the rater stage begins; Jaccard against the
raw `edit_functions` set is printed beside it as descriptive only (it is depressed by `<module>` and
`Class` sites, which have no gold analogue).

**M9 — the legacy proxies at the new grain**, reported as descriptive bounds only: the `MULTI-FILE`
share (the test-excluded analogue of the 17%), and `1 − ONE-SITE share` (the site-grain analogue of
the 62%). Neither is the answer; both are printed so the reader can see where the legacy figures
sit once tests and hunks are handled.

## 6. Recipe — the rater stage (the second-site test)

The driver for every step here is
[`bench/locbench/crossctx_rater.py`](../../bench/locbench/crossctx_rater.py) (tests:
[`test_crossctx_rater.py`](../../bench/locbench/test_crossctx_rater.py), synthetic). No packet is
assembled by hand and no label is transcribed by hand — those are the two places blinding fails.

**R1 — sample.** Within each of the three scoreable strata, rows sorted by `instance_id`, take every
`k`-th starting at index 0 with `k = max(1, ⌊N_s / 40⌋)`: **40–79 rows per stratum** (a stratum of 79
is taken whole; of 80, every second row; of 250, 42), at most 237 in total, all of them when a stratum
is small. The sample is a function of the manifest and nothing else.

**R2 — the packet**, one per sampled row, built by the driver: the issue title and body
(`problem_statement`, in full); the fix patch (all hunks, tests and docs included — they help identify
the defect); the dataset's `test_patch` when the row carries one (Loc-Bench derives from SWE-bench-style
rows, which do; the fingerprint and M1–M9 read `patch` only, as the legacy script did); for every site
in `S`, the full pre-fix text of that definition at `base_commit`; the tree-access rules and budget; the
answer schema; and the SHA-256 of the brief (R3). The packet carries a **packet index** and nothing
else that identifies the row: no `instance_id`, no repository field, no mechanical class, nothing from
§1, §2, §3.4 or §9 of this note. The driver refuses to emit a packet containing any of a fixed list of
leak words (the internal percentage, the verdict names, "bias", "roadmap", "hypothesis", …). The
`packet_index → instance_id` map stays with the driver.

**R3 — raters and protocol (executable, not aspirational).**

- **Who.** Two model agents of **different model families**, named now: one Anthropic Claude model and
  one OpenAI GPT model; the exact model identifiers are recorded in the Outcome. If only one family is
  available when the run happens, the Outcome says so and states that κ is then agreement *within* a
  family and inflated. The run's operator is not a rater and never edits a label. A human blind read of
  a fixed 20-row subset (the first 20 sampled rows in `instance_id` order) by the owner is recommended
  as a third, **non-decision-bearing** check.
- **What they read.** Exactly the frozen file
  [`bench/locbench/crossctx_rater_brief.md`](../../bench/locbench/crossctx_rater_brief.md) — §3.1–§3.3
  of this note and the questions of R4, reworded for a reader who has no other context — plus one
  packet. Nothing else from this note. The brief's SHA-256 is written into every packet and every
  Outcome; a unit test refuses a brief that contains any leak word.
- **Independence.** A **fresh context per row**, not per rater: a rater that sees the whole sample in
  one session learns the base rate and drifts. No aggregate is shown, no other rater's output, no
  discussion.
- **Tools.** Read-only access to the repository at `base_commit`, through exactly three commands —
  `ls-tree`, `show <path>`, `grep <pattern>` — every read logged. **No network** and no other tool, so a
  rater cannot look up the issue tracker, the fix commit or the upstream PR.
- **Budget.** At most **25 tree reads** and **1,500 output tokens** per row per rater, applied
  identically to both; exceeding either is recorded as UNDECIDED (`budget_exceeded`).
- **Output.** One JSON object per row in the schema of R4; the driver ingests it mechanically and
  records a malformed answer as UNDECIDED (`schema_error`), never repairing it by hand.
- **Transcripts.** Kept with the run; their SHA-256s are listed in the Outcome.
- **Pilot.** The **first ten scoreable rows in `instance_id` order that are not in the R1 sample** are
  rated once by both raters to check the wording is answerable. Pilot rows never enter any estimate.
  If the brief's wording changes after the pilot, that is an amendment under §10, committed before R1's
  rows are rated.

**R4 — questions, fixed wording (verbatim in the brief).** For each packet:

1. *Primary site.* Which site in the packet's list holds the pre-fix code that was wrong? One site,
   `path:definition`; or null with verdict `NOT-A-DEFECT` (a feature, a docs-only change, a refactor
   with no wrong behaviour named in the issue).
2. *Quote test.* To justify the fix, would you have to quote only the primary site's pre-fix text (plus
   the language and the issue's symptom), or text from a second site as well? → `LOCAL` / `CROSS`.
3. *If CROSS:* name the second site — `path:definition`, existing in the repository at `base_commit`,
   different from the primary site — and pick one relation: `caller-callee-contract` ·
   `table-roster-registration` · `constant-format-schema-elsewhere` · `sibling-or-clone-must-agree` ·
   `mirror-parity-copy` · `test-not-exercising-claim` · `other`. If the only second site is outside the
   repository, answer `LOCAL` with `external_contract: true`.
4. *Confidence:* `sure` / `unsure`. A rater who cannot decide within the budget answers `UNDECIDED`.

JSON fields: `packet_index`, `primary_site`, `verdict`, `second_site`, `relation`, `external_contract`,
`confidence`, `tool_calls`, `output_tokens`, `note` (free text, optional).

**R5 — no discussion, no adjudication.** Disagreements are not talked through: the row is
`UNTAGGED`. This mirrors the internal chain, where an undecidable row is counted and dropped rather
than forced.

**R6 — the label per row.** Each answer is first validated (schema, budget, `external_contract` →
LOCAL) and, for CROSS, **verified**: the driver checks that the named second site exists at
`base_commit` (`show` the file; the definition is in its `ast` spans, or `<module>`/`<file>` of an
existing file) and differs from the primary site; otherwise that answer becomes UNDECIDED
(`unverified_second_site`). Then `CROSS` if both say CROSS; `LOCAL` if both say LOCAL; otherwise
`UNTAGGED`, with disjoint sub-buckets `NOT-A-DEFECT` (either rater), `UNDECIDED` (either rater; the
sub-bucket is named `UNVERIFIED-SECOND-SITE` when the cause was a failed verification), `DISAGREE`.

**R7 — agreement.** Cohen's κ over the two raters' three-way verdicts (CROSS / LOCAL / other), and
binary κ over rows where both chose CROSS or LOCAL. **Reliability floor:** binary κ ≥ 0.60 for the
rater-based rate to be quotable and to feed §9; 0.40 ≤ κ < 0.60 is reported as "moderate agreement",
the rate is printed with that label and §9 is INDETERMINATE; κ < 0.40 means the rater stage failed —
only the mechanical numbers are reported and §9 is INDETERMINATE. **κ between two models is a measure
of agreement between models**, which shared training data and shared blind spots can inflate; the
Outcome says so beside the number.

**R8 — order of operations.** The rater stage begins only after M1–M9 have run and the manifest
hash, the fingerprint, the M8 recall and the brief's hash are recorded, and after the pilot. No rater
sees any aggregate.

## 7. Estimators

- **Per stratum** `s`: `p̂_s = CROSS_s / (CROSS_s + LOCAL_s)` over the stratum's tagged sample rows.
- **Primary estimate** (the number compared with 88%): `P̂ = Σ_s (N_s / N) · p̂_s` — the post-
  stratified rate over the scoreable set, weights from the *whole* manifest, rates from the sample.
- **Interval:** 2,000 within-stratum bootstrap resamples of the tagged sample rows, seed
  `20260923`, percentile 2.5 / 97.5. Wilson intervals are printed for every raw count too.
- **Untagged fraction** `U = UNTAGGED / sampled`, with sub-buckets, beside the internal 42%.
- **Sensitivities**, each one line, all recomputable from the manifest and the labels: file grain (a
  CROSS whose second site lies in the primary site's file is LOCAL); moves collapsed (strata re-weighted
  by `mclass_collapsed`); `otherlang` rows dropped; disagreements resolved toward CROSS and toward LOCAL
  (the two bounds); the sample's unweighted rate; and the `test_dir_only` bound — the count of
  `TEST-ONLY` rows that would have been scoreable without the directory rule, which are unrated and so
  can only be shown as the range they would produce at 0% and at 100% CROSS.
- **Internal comparator:** 149/169 with its Wilson interval, and the code-only chain 109/124 with its
  Wilson interval (§2, §13). Risk difference `internal − external` with a bootstrap interval.

## 8. Reported in every outcome

The Outcome section, whatever the numbers, contains this table with every cell filled (the driver's
`outcome_table` prints it), plus the manifest hash, the `dataset.lock` hash, the brief's hash, the
checkout depth, the rater identities (family and model id) and transcript hashes, whether the §9
enlargement was used, and the date:

```
560 rows  (manifest <hash>; brief <hash>; enlargement used|not used)
  EXCLUDED-UNAVAILABLE   n   (base_commit not materialised; listed per repository)
  EXCLUDED-UNREADABLE    n   (listed per repository)
  NON-CODE               n
  TEST-ONLY              n   (paths listed)
  NEW-FILE-ONLY          n
  scoreable N            n
    ONE-SITE               N_1   sampled n_1   CROSS c  LOCAL l  UNTAGGED u (DISAGREE/UNDECIDED/UNVERIFIED-SECOND-SITE/NOT-A-DEFECT)
    MULTI-SITE-ONE-FILE    N_2   sampled n_2   ...
    MULTI-FILE             N_3   sampled n_3   ...
  fingerprint (legacy)   CROSS 94 / SPREAD 254 / LOCAL 212   [pass|fail]
  M8 gold recall         r  [pass|fail]   (Jaccard, descriptive: j)
  M9 descriptive         MULTI-FILE share, 1 - ONE-SITE share
  kappa                  3-way κ, binary κ over n  [quotable|moderate|failed]
  P (post-stratified)    p  [lo, hi]      U = untagged share     dropped strata
  sensitivities          file-grain p, moves-collapsed p, otherlang-dropped p, disagree->CROSS p, disagree->LOCAL p, unweighted p
  TEST-ONLY by dir-rule  n rows (bound: unrated)
  internal               149/169 = 88.2% [82.4, 92.2]; code-only 109/124 = 87.9% [81.0, 92.5]
  contrast               internal - P = d  [lo, hi]
  raters                 families and model ids; transcript hashes
  decision (§9)          STARK | THIN | INDETERMINATE, with the clause that fired
```

## 9. Expectations, power, and the decision the number feeds

**What the recipe is expected to reproduce.** The legacy **94 / 254 / 212** — exactly, as the
population fingerprint (§4.4), and only because it recomputes the legacy rule verbatim. It is *not*
expected to reproduce either 62% or 17–38% as the cross-context rate, and the note says now why not
so that no later reading can call a mismatch a surprise: 62% counts multi-hunk-one-function fixes and
test hunks as cross-context (over-states); 17% counts a fix plus its test as two source files while
missing every one-file fix whose second site needed no edit (mis-states in both directions). The
site-grain descriptive shares (M9) are expected to land *between* the two legacy figures. No
directional prior on the rater-based `P̂` is registered as a hypothesis; the thresholds below are
the whole of what is pre-stated.

**Power, stated before the number.** With the planned sample (40–79 per stratum, ≈ 120 rows in the
likely case, of which perhaps 70–75% are tagged, so ≈ 88 tagged), the bootstrap interval is about
**± 0.10–0.11** wide (synthetic labels, pinned by a unit test): a true rate of 0.45 gives roughly
[0.35, 0.59]; 0.62 gives roughly [0.52, 0.74]; 0.70 sits *at* the THIN edge. So the **effective bars
at the planned n are a point estimate of ≲ 0.39 for STARK and ≳ 0.70–0.72 for THIN**, and a true rate
anywhere in about 0.40–0.70 returns INDETERMINATE by width alone — including the owner's own 62%
figure, if it is true. That is a legitimate design (INDETERMINATE is the honest answer at that n), but
it must be read as such, so its cost is pre-registered:

**One-step enlargement rule.** If the verdict is INDETERMINATE **solely** on the straddle clause
(κ ≥ 0.60, `U` ≤ 0.50, fingerprint and M8 passed), a second systematic pass at **offset ⌊k/2⌋** within
each stratum is added **once**, the packets are built and rated under the identical protocol, and the
estimate is recomputed on the union; both estimates are reported. A stratum already taken whole gains
nothing. No further enlargement, and none on any other clause. Declared now, this is a two-stage
design; declared later it would be p-hacking.

**Decision rule**, anchored on the roadmap ruling that framed the question ("at 62% human code is
also mostly cross-context and the differentiator is thin; at 17–38% the contrast is stark"):

| verdict | condition on `P̂`'s 95% interval `[lo, hi]` | consequence for the roadmap |
| --- | --- | --- |
| **STARK** | `hi ≤ 0.50`, **and** binary κ ≥ 0.60, **and** `U ≤ 0.50` | the arm contrast stands as evidence for the cross-context check class; the class's next candidate is justified by the contrast *plus* its own precision measurement |
| **THIN** | `lo ≥ 0.60` (κ and `U` as above) | human code is mostly cross-context too; the class may still be worth building, but **not on the strength of the contrast** — its case must rest entirely on its own precision measurement, and the "AI-authored defects are different" framing is withdrawn from every document that uses it |
| **INDETERMINATE** | anything else — including any failure of the κ floor, `U > 0.50`, a failed fingerprint, or a failed M8 check — after the one enlargement, if it applied | the contrast is unproven; documents quote the internal chain with its caveats and say the external arm did not settle; the class is judged on its own precision measurement alone |

**The bars, and their asymmetry, disclosed.** `hi ≤ 0.50` sits 12 points *above* the owner's stark
anchor (17–38%); `lo ≥ 0.60` sits 2 points *below* the thin anchor (62%). At the planned n the
*effective* STARK bar (point ≲ 0.39) coincides with the top of the owner's stark anchor and the
*effective* THIN bar (point ≳ 0.70) sits well above the thin anchor; the enlargement moves both toward
the nominal 0.50 / 0.60. `hi ≤ 0.50` was chosen so that a STARK verdict requires the external interval
to sit at least 32 points below the internal interval's *lower* bound (82.4%) — wide enough to survive
the internal side's known bias toward CROSS (§2 limit i). A reviewer who wants the stark bar lower or
the thin bar higher should say so before R1; after R1 the constants are frozen (§10).

**What no outcome licenses.** Any statement about software in general; a per-repository rate (the
sample is ~120–240 rows over ~250 repositories); a claim that any *particular* check would have caught
a particular fix (this measures where defects are visible, not whether a predicate finds them); pooling
the two arms.

## 10. Amendments and self-reject

- An amendment to §3–§7 is allowed **only before R1's rows are rated**, must be dated and appended to
  §13 with its reason, and must be committed before the rater stage starts. After R1, a change to any
  rule or constant is a new pre-registration, not a fix. The pilot (R3) is the one place wording may
  change, and only through such an amendment.
- The §9 enlargement is **not** an amendment: it is part of the design, with its offset pinned in the
  code's frozen constants.
- The fingerprint (§4.4) failing, the M8 recall failing, or the κ floor failing are **stops**, not
  amendments: the Outcome reports the failure and the decision is INDETERMINATE.
- Nothing in this recipe depends on the ripwire binary, so no build, flag or ranking change can move
  the result; a re-run on a different day with the same `dataset.lock` must reproduce the manifest
  hash, the fingerprint and every mechanical count exactly, and the rater counts up to rater
  variance (which κ reports).

## 11. Code

- [`bench/locbench/crossctx_sites.py`](../../bench/locbench/crossctx_sites.py) — M1–M9, R1 and the §9
  enlargement, the pilot list, the estimators of §7 and the decision table of §9 as pure functions,
  plus a `main()` that refuses to run without an explicit rows file, checkout directory and output
  directory, refuses a rows file whose SHA-256 is not the pinned one, and fetches nothing unless
  `--materialise` is passed (then only through `run_locbench.checkout`). It walks no history.
- [`bench/locbench/crossctx_rater.py`](../../bench/locbench/crossctx_rater.py) — R2 packets (no
  identity, leak-checked), the R4 answer schema and its validation, the F1 second-site verification, R6
  ingest, both κ, the §7 sensitivities and the §8 table.
- [`bench/locbench/crossctx_rater_brief.md`](../../bench/locbench/crossctx_rater_brief.md) — the
  frozen text the raters read, hashed into every packet.
- Tests, synthetic only: [`test_crossctx_sites.py`](../../bench/locbench/test_crossctx_sites.py) and
  [`test_crossctx_rater.py`](../../bench/locbench/test_crossctx_rater.py) — hand-written patches, a
  hand-written Python module, hand-written rater answers. They pin both internal comparators' Wilson
  intervals, the decision thresholds, the power statement, the brief's leak-freedom and every frozen
  constant, so a later edit fails a test rather than moving silently.

```bash
python3 bench/locbench/test_crossctx_sites.py            # synthetic checks; touches no data
python3 bench/locbench/test_crossctx_rater.py            # synthetic checks; touches no data
python3 bench/locbench/crossctx_sites.py --rows ROWS.json --repos-dir DIR --out OUTDIR [--materialise]   # the run, later
```

## 12. Decisions taken here, listed for an adversarial reviewer

1. **Function/method grain as the primary unit**, file grain as sensitivity (§3.2, §3.4). The
   internal rule says "one function or one file"; the choice follows the CROSS categories, which are
   relations between definitions.
2. **Tests, docs, migrations and other generated files are not sites** (M2). This removes the
   legacy 17%'s test inflation and treats a migration as a consequence of the fix rather than a place
   the defect was visible. The rater stage, not the mechanical stage, decides whether a fix that
   *also* touched a migration was cross-context. The DOC rules now spare code files and the GENERATED
   rule reads comments only; the TEST directory rule's known loss is flagged and bounded.
3. **A pure insertion that begins a definition is attributed to its container by indentation**
   (M3): a new method to its class, a new top-level function to `<module>`, independent of which
   line git anchored the hunk on. Other insertions keep the preceding-line anchor, and the note says
   that anchor is git's choice. Alternative: a new definition is its own site — rejected because it
   does not exist at `base_commit`, which is where sites are defined.
4. **Moves count as two sites in the primary analysis** (M6), with the collapsed rate as an
   implemented sensitivity (`mclass_collapsed`). Detection is whole-hunk equality across different
   pre-fix paths; under-flagging is stated.
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
   post-stratification is free precision. Cost: 40–79 packets per stratum × 2 raters, plus the pilot.
9. **The κ floor at 0.60** (R7). Below it two raters are not applying one definition and no rate is
   a rate of anything. 0.60 is a conventional "substantial agreement" cut, chosen before any packet
   exists. Between two models it is inter-model agreement and is disclosed as such.
10. **STARK at `hi ≤ 0.50`, THIN at `lo ≥ 0.60`** (§9), from the roadmap's own anchors (17–38 stark,
    62 thin) with the interval, not the point, doing the work; the asymmetry and the effective bars at
    the planned n are stated in §9. A reviewer who wants the stark bar lower should say so before R1.
11. **The recipe does not use the ripwire binary.** A tool that measures its own motivation is a
    conflict of interest; `ast` and `git show` are enough for the mechanical stage. The cost is that
    `OTHERLANG` files are one coarse site each, flagged and counted.
12. **The internal code-only sensitivity is produced now, as amendment 1** (§13), from the frozen
    ledger snapshot that is kept with the ledger's own classifier. It is comparator data, not external
    data, and fixing the comparator before the external number exists is strictly better than after.
13. **Raters read the repository** (R3), read-only, through three logged commands and a fixed budget.
    Without it the one class the whole exercise is about — a second site that needed no edit — cannot
    be named, and the cheap answer is LOCAL. The residual (a rater reads less than a developer) is
    stated and its direction (toward STARK) is disclosed in §3.4.
14. **A CROSS answer must verify** (R6): the second site exists at `base_commit` and differs from the
    primary. A second site the fix also edited stays CROSS, flagged `second_site_edited`: requiring it
    to be un-edited would define CROSS out of the multi-site strata, which is where cross-context fixes
    mostly live. This is a deliberate reading of the review's F1 and is listed here so it can be
    overruled before R1.
15. **Two named model families, fresh context per row, no network, no `instance_id`, a JSON schema
    and a fixed budget** (R3). An LLM rater is a proxy for a human colleague, disclosed as such.
16. **The one-step enlargement at offset ⌊k/2⌋** (§9) is declared now so that an INDETERMINATE by
    width alone has a pre-registered remedy instead of an after-the-fact one.

## 13. Amendments

### Amendment 1 — 2026-09-23, after adversarial review of the first commit; before any row is scored

Thirteen findings (F1–F13) from an independent review of the first registration, all landed before any
LocBench row was read under this recipe. What changed, by finding:

| finding | change |
| --- | --- |
| F1 raters could not name a second site the fix did not touch | R3 tree access (three read-only commands, 25-read budget); R6 verification of every CROSS answer against `base_commit`; §3.3 in-repository rule and `external_contract` → LOCAL; §3.4 gains the packet-starvation row with its direction |
| F2 blinding: raters were to be given §3, which includes the internal rate and the bias direction | raters read only the frozen brief (`crossctx_rater_brief.md`, hashed into every packet, leak-checked by a test); two named model families; fresh context per row; no network, no `instance_id`; JSON schema; budget; pilot of ten fixed rows; transcript hashes; §3.4 gains the "raters are models" row |
| F3 no rater-stage driver; `cohen_kappa` raised on the tuple labels | `crossctx_rater.py` (packets, validation, verification, ingest, both κ, sensitivities, §8 table) with synthetic tests; `cohen_kappa` compares labels by equality only; `three_way()` maps verdicts for R7 |
| F4 code attributed a new definition to the preceding definition, so the site depended on git's hunk placement | M3 rewritten: a new definition goes to its container by indentation (`site_for_new_definition`); the test that pinned the old behaviour now pins the new one, including the "same insertion, hunk slid one line" case |
| F5 `main()` assumed populated checkouts; `unreadable` fell into NON-CODE; no flags in the manifest | `--materialise` step through `run_locbench.checkout`; `EXCLUDED-UNREADABLE` and `NEW-FILE-ONLY` buckets; manifest columns `n_sites`, `flags`, `mclass_collapsed`; excluded rows listed per repository; §4.5 "estimate of the materialised sub-population" |
| F6 no power statement; both anchors INDETERMINATE at the planned n | §9 power paragraph, effective bars, asymmetry disclosed, one-step enlargement at offset ⌊k/2⌋ pinned in the frozen constants and tested |
| F7 M2 over-fired (`history.py` → DOC, docstring "generated" → GENERATED; `django/test/` → TEST unbounded) | DOC rules apply to non-code extensions only; GENERATED reads comment lines only; `test_dir_only` flag, listing and bound |
| F8 definitions under `try`/`if`/`with` mapped to `<module>` | M4 descends through those containers (tested on `except ImportError:`, `if TYPE_CHECKING:`, `with`) |
| F9 move detector compared old against new path; collapse unimplemented | identity = pre-fix path on both sides; source hunks returned; `mclass_collapsed` implemented and in the manifest; M6 reworded to what the code does |
| F10 M8 Jaccard was depressed by construction and could stop the run for a design reason | M8 is recall of SOURCE gold `edit_functions` in `S`, floor 0.70; Jaccard descriptive |
| F11 "the ledger is not on this machine" was false | corrected; the code-only chain produced from the frozen 377-row snapshot by the ledger's own rule with its "not a code defect" class (`klass = d`) and its unusable class (`u`) removed: **209 usable → 124 tagged, 85 untagged (40.7%) → 109 CROSS (87.9%) / 15 LOCAL**, Wilson [81.0%, 92.5%]; the unrestricted run of the same script reproduces 292 → 169 → 149/20 exactly. Pinned as `INTERNAL_CHAIN_CODE_ONLY` and tested |
| F12 wording | §2 "paraphrased"; §4.2 the registered step; R1 "40–79 per stratum, ≤ 237" |
| F13 `test_patch` | R2 states the fingerprint and M-stage read `patch` only and that the packet includes `test_patch` when the row carries it |

Nothing in this amendment was informed by any external number: none exists.

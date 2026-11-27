# ripwire-change-check — reference: pr-context (read on demand; the recipe is in SKILL.md)

Contents: The one-shot bundle — --pr-context[=BASEREF] · 1. Situational awareness on the diff · 2. Hotspot risk · 3. Lint delta · 4. Missing-test seam check · 5. The diff's structural footprint · 6. Read the numbers on what you touched · 7. Docs-sync check · 8. Run the test gate

# Change check with ripwire

> Routing:
> • Estimating a change you have NOT written yet (feasibility/plan/sizing) → **ripwire-before-you-build**.
> • Did the code ITSELF get better or worse? (complexity/dup/dead delta) → **ripwire-quality-bar** — run it
>   FIRST; this is the chain **"did the code get worse" → "is it safe to merge".**
> • Risk on an unfamiliar subsystem you did NOT write (not tied to a diff) → **ripwire-fresh-eyes**.
> • Writing a test for EXISTING untested code (not vetting a diff) → **ripwire-write-tests**.
> • Not sure which skill? → **ripwire-router**.

`<dir>` = repo root. Run from the repo with your working changes staged/unstaged, or check out the PR branch
first. This works on a real diff — `--situ`, `--map-diff`, and `--pr-context` read `git diff` automatically.

## The one-shot bundle — `--pr-context[=BASEREF]`

The flagship verb for this moment: a single no-LLM review-evidence bundle for the whole diff (working tree,
or vs `BASEREF`). Per changed file: defined symbols, their callers, transitive blast radius, affected tests,
co-change partners not in the diff, and owners — everything steps 1–5 assemble by hand, in one call:
```
ripwire <dir> --pr-context --legend=compact                # working-tree diff
ripwire <dir> --pr-context=main --legend=compact           # vs a base branch/ref
```
```
<pr-context base="working-tree" files="N"><file p="…" symbols="K">
  <impact dependents="…" files="…"/><tests count="…"/>
  <changed-symbols count="K"><s t="fn" n="…" p="…:L" callers="…"/> …
```
Use this first for the evidence dump; steps 1–5 below are the same ground as a narrated, one-pass walkthrough.

**Scope guard:** Do not turn a focused fix into a full merge audit merely because a diff now exists. Invoke
this skill when the user is actually at the submit/review/merge-safety moment, or when the edit changes a
contract or has unclear reach. But "obvious leaf-level fix with no signature/API change" is a claim, not a
given — run `--edit-check=SYM` (the fast per-symbol sibling of step 8, ~ms warm) to confirm it before trusting
it; a `status="contract-change"` result means the fix was not as leaf-level as it looked, and the full audit
below is now warranted. Only a genuinely `"unchanged"` result plus the focused test plus `git diff --check`
is enough to stop there, unless repository instructions require a broader gate.
Never run `--pr-context` and then repeat its component steps without a specific unanswered question.

**The header is stamped `at="<sha>[+dirty]"`** — the commit the evidence was measured at (`--pr-context`,
`--test-gate`, `--quality-delta` and `--map-diff` all carry it). Quote it whenever you paste findings into a
PR comment or hand them to someone else: a review bundle outlives the HEAD it was taken from. A `+dirty`
suffix means the numbers came from an **uncommitted** working tree — nobody else can reproduce them from
that sha, so re-run after you commit before treating them as review evidence. Note `--situ`, `--cochange`
and `--owners` carry **no** stamp — record the sha yourself if you quote them.

On a large diff the bundle can be huge — cap it with `--max-tokens=N` (e.g. `ripwire <dir> --pr-context --legend=compact
--max-tokens=8000`): every changed file stays present with its structural counts (blast radius / tests /
callers), the deep detail trims deepest-first, and `truncated=`/`est_tokens=` on the header report the fit.
To feed an EXTERNAL reranker instead of reviewing directly, `--query="…" --format=candidates` (or `--for=…`)
emits a flat `<cand r= s= n= id= k= p= l=>` top-K — identity + score + signature only, capped by `--top-k`.

1. **Situational awareness on the diff** — `ripwire <dir> --situ`
   (Reads `git diff` against HEAD; or `--situ=fileA.cpp,fileB.h` to name the changed set explicitly.)
   One pass, plain text:
   - changed file count + the symbols they contain
   - **transitive blast radius** — everything that reaches the changed symbols
   - **tests to run** (`--affected` under the hood) — empty = no test cover for the changed code, **flag it**.
     Each named test carries `run="<cmd>"` when a runner is derivable (a test-dir script whose stem matches
     the harness, or whose text names it), so the obligation is pasteable; **no `run=` means not derivable —
     never treat its absence as "there is no runner"**. Narrow the question to ONE function with
     `--affected=SYM` (or `--affected=file:NAME` when a path shares the name) instead of widening it to the
     whole file, and invert it with `--exercises=test/<harness>` to see what a given test actually covers.
     On a corpus where few harnesses have a runner, `--affected` serves the runner-less rows GROUPED:
     `<g hops="2" n="17" p="a,b,c" run_unknown="1"/>` is ONE row standing for 17 test files at the same hop
     distance (`p=` lists them comma-separated, a `,` inside a path written `&#44;`), with the
     not-derivable disclosure stated once for the group. Rows that DO have a `run=` stay single `<t>` rows.
     The obligation is unchanged — every path is still listed verbatim, and a row carries `run=` or
     `run_unknown="1"`, never neither.
   - **co-change partners NOT in the diff** — files that historically move together (should they be in this
     change too? — the Shotgun Surgery check: one change that has to land in many places, and did not)

2. **Hotspot risk** — `ripwire <dir> --hotspots --legend=compact`
   `<hotspots>` ranked by `score = churn × ccx`. Does any changed file appear in the top-10? A change that
   touches a high-score file deserves extra scrutiny; one that *raises* ccx in an already-churny file is a
   regression risk.

3. **Lint delta** — `ripwire <dir> --lint --legend=compact`
   `<lint findings="N">` per-rule summary, then per-finding file + enclosing symbol. Cross against the
   changed-file list from step 1 — **any finding in a touched file is one this change introduced or inherited.**

4. **Missing-test seam check** — if step 1 showed `tests="0"`, run `ripwire <dir> --seams --legend=compact` to see whether the
   changed code crosses an integration seam with no test coverage. That's the gap to fill before merging.

5. **The diff's structural footprint** — `ripwire <dir> --map-diff --legend=compact`
   Emits ONLY the symbols changed vs git HEAD, ranked — the change's footprint in one screen, without the
   rest of the map as noise. Add `--rank-by=churn` to order those symbols by git change-frequency instead of
   PageRank: what floats to the top is the code that changes *all the time* — a change touching it again is
   following (or feeding) a churn pattern worth asking about.

6. **Read the numbers on what you touched** — `ripwire <dir> --metrics --legend=compact` (also carried inline by `--for`/
   `--around --metrics`). Cross these against your changed set:
   | Attr | Means | Threshold → action |
   |---|---|---|
   | `cbo` | distinct dependencies (coupling between objects) | high (≳8, or *rose* vs neighbours) = **fragile, hard to test in isolation** → decouple: hide a dependency behind an interface or invert it |
   | `lcom4` | class cohesion = # connected method components (class-kinds only) | `>1` = the class does **N unrelated jobs** (N disjoint method clusters) → split it into N types |
   | `nest` | max block-nesting depth | `>~4`, or above the file's local median → deep-branch smell → guard clauses / extract the inner block into a named fn |
   | `loc` | lines in the symbol | well above the local median for its kind → size smell → split; a giant new fn is the #1 agent verbosity failure mode |
   | `params` | parameter count | `>~5` → bundle related params into a struct rather than widening the signature |
   | `tested` | is any indexed test reaching it | `tested="1"` = a safety net is present; omission on this explicit metrics surface means no indexed test reaches it → add one before changing it further |
   These are size-correlated signals (coupling is the validated one; complexity/size are heuristics) — read
   the delta against the file's own median, not an absolute bar. A number that was already high before your
   diff is not your regression (that judgment is **ripwire-quality-bar**'s `--quality-delta`).

7. **Docs-sync check** — `ripwire <dir> --mentions=SYM --legend=compact` for each changed symbol from step 1. Any markdown doc
   that backtick-names a symbol you just changed is a staleness candidate — the design rationale it wrote
   down may no longer match the code. Skim the listed docs; update or flag the ones that describe behavior
   your diff altered.

8. **Run the test gate** — `ripwire <dir> --test-gate --legend=compact` (the merge-safety moment, in one exit code). Packages
   step 1's blast radius + tests-to-run into a gate: NAMES the tests that reach your change and the
   **untested blast radius** (impacted symbols no test covers), **exits 4** if either is non-empty. This
   queryable map cut agent-caused regressions **−70%** (6.08%→1.82%, TDAD) — prose reminders alone made
   agents worse. The gate can't watch a run; the loop is **run the named tests, then rely on green**. A
   non-empty untested list = the gap to close before you call it merge-safe.

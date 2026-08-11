---
name: ripwire-change-check
description: >
  The merge-SAFETY check for a diff that already EXISTS — your own working changes before you submit, or an
  incoming PR you're reviewing — beyond the line-by-line view. Use at "am I ready to push?" / "is this safe
  to merge?" / "what does this PR actually touch?" / "which tests should I run for this change?". Also covers
  three narrower moments: just edited a symbol and need to know — did I change a contract someone depends on
  (a fast per-symbol contract check, --edit-check, no full diff needed); landing several branches or
  parallel agent worktrees and need to know who conflicts and in what order they should land (--merge-scout);
  and cross-ref content archaeology — "I have 30 branches and do not know what is stranded on them" — which
  ref still holds divergent work, is it genuinely unmerged or already superseded (--stray-content), and which
  ref defines or mentions a symbol (--whereis). Maps changed symbols to their transitive blast radius,
  surfaces tests to run (--affected/--situ), flags lint smells and hotspot risk in touched files, interprets
  --metrics coupling/cohesion/size on what you touched, and shows the diff's footprint via --map-diff. For
  code QUALITY (better or worse) → **ripwire-quality-bar** instead — this skill judges merge safety, not
  quality. Backed by ripwire (deterministic, on PATH). A one-line leaf fix is not a merge audit — run the
  focused test, but still run `--edit-check=SYM` first (~ms warm, cheaper than deciding by eye whether the
  edit touched a contract): a clean `unchanged` result is what actually earns the right to skip the rest of
  this skill (and this file). Sizing work not yet written → ripwire-before-you-build.
  Risk in a subsystem you did NOT write → ripwire-fresh-eyes.
  Verdict on the dirty tree: changed params, removed symbols, findings, next steps.
allowed-tools: Bash, Read
---

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
ripwire <dir> --pr-context                # working-tree diff
ripwire <dir> --pr-context=main           # vs a base branch/ref
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

On a large diff the bundle can be huge — cap it with `--max-tokens=N` (e.g. `ripwire <dir> --pr-context
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
   - **co-change partners NOT in the diff** — files that historically move together (should they be in this
     change too?)

2. **Hotspot risk** — `ripwire <dir> --hotspots`
   `<hotspots>` ranked by `score = churn × ccx`. Does any changed file appear in the top-10? A change that
   touches a high-score file deserves extra scrutiny; one that *raises* ccx in an already-churny file is a
   regression risk.

3. **Lint delta** — `ripwire <dir> --lint`
   `<lint findings="N">` per-rule summary, then per-finding file + enclosing symbol. Cross against the
   changed-file list from step 1 — **any finding in a touched file is one this change introduced or inherited.**

4. **Missing-test seam check** — if step 1 showed `tests="0"`, run `ripwire <dir> --seams` to see whether the
   changed code crosses an integration seam with no test coverage. That's the gap to fill before merging.

5. **The diff's structural footprint** — `ripwire <dir> --map-diff`
   Emits ONLY the symbols changed vs git HEAD, ranked — the change's footprint in one screen, without the
   rest of the map as noise. Add `--rank-by=churn` to order those symbols by git change-frequency instead of
   PageRank: what floats to the top is the code that changes *all the time* — a change touching it again is
   following (or feeding) a churn pattern worth asking about.

6. **Read the numbers on what you touched** — `ripwire <dir> --metrics` (also carried inline by `--for`/
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

7. **Docs-sync check** — `ripwire <dir> --mentions=SYM` for each changed symbol from step 1. Any markdown doc
   that backtick-names a symbol you just changed is a staleness candidate — the design rationale it wrote
   down may no longer match the code. Skim the listed docs; update or flag the ones that describe behavior
   your diff altered.

8. **Run the test gate** — `ripwire <dir> --test-gate` (the merge-safety moment, in one exit code). Packages
   step 1's blast radius + tests-to-run into a gate: NAMES the tests that reach your change and the
   **untested blast radius** (impacted symbols no test covers), **exits 4** if either is non-empty. This
   queryable map cut agent-caused regressions **−70%** (6.08%→1.82%, TDAD) — prose reminders alone made
   agents worse. The gate can't watch a run; the loop is **run the named tests, then rely on green**. A
   non-empty untested list = the gap to close before you call it merge-safe.

9. **Landing several concurrent branches?** — `ripwire <dir> --merge-scout=REF1,REF2,...` (read-only; the
   dirty working tree joins automatically as an implicit extra arm). For each REF it diffs the ref's tree
   against its merge-base with HEAD (git-archive temp copies — nothing is checked out or mutated) and
   reports, per pair, **same-symbol conflicts** (both arms touched the identical symbol — a real merge will
   fight over it) and **same-file/different-symbol risks** (no content collision, still worth a glance), plus
   a `<landing order="…">` — the fewest-conflicts-first sequence to land them in. Run this BEFORE picking a
   merge order for several agent branches instead of hand-diffing each pair.

9b. **Is anything STRANDED on a branch — and was it already re-done?** — `ripwire <dir> --stray-content`
    (`=SUBSTR` filters ref names). `--merge-scout` above answers "which of these named branches collide";
    this answers the prior question — *of all my branches, which still hold work the live line does not
    have?* Per ref it reports the lines that ref's own work AUTHORED (vs its merge-base with HEAD) that HEAD
    lacks, with a verdict: `unmerged` (genuinely absent — this is the queue to work), `superseded` (the live
    line removed the SAME base code this ref removed, i.e. it re-implemented the work), `merged` (omitted).
    **`superseded` is the case `git cherry` structurally cannot see** — it compares commit ancestry, so a fix
    the live line re-did differently stays "unmerged" forever, which is exactly how a finished fix sits on a
    branch for days behind a ledger that says "ported". Every row prints its raw `del=`/`redone=`/`sim=`
    evidence — read those before acting, the verdict is a summary, not an oracle. Line-granular, not
    semantic. Read-only, single-root.

9c. **"Where does this content live?"** — `ripwire <dir> --whereis=SYM`. Which ref's tree defines or mentions
    a symbol, HEAD first; `on-head="0"` alongside branch hits is content that exists ONLY on a branch. Each
    distinct blob is read once (git is content-addressed), so 30 branches cost about one tree. `kind="def"`
    on a branch row is a lexical heuristic — branch blobs are raw text, never ingested; for HEAD's parsed
    answer use `--expand`/`--callers`.
    A tree scan only finds what some ref *still carries*, so `hits="0"` cannot by itself tell a name this repo
    never had from one it deleted. Add `--with-history` and a `<fate>` row says which: `v="never"`, or
    `v="removed" commit=… date=… p=…` naming the commit that took it out. One `git log` pass, memoized per
    (repo, HEAD sha) and shared with `--doc-drift --with-history`.

9d. **"Of all my branches, which still hold REAL work, and in what order should I land them?"** — `ripwire
    <dir> --stray-content --plan`. Composes 9b + 9 in one call: selects the refs 9b calls `v="unmerged"`,
    DROPS the `v="superseded"` ones (`<excluded reason="…">` names them — landing a superseded branch would
    re-do work the live line already did, exactly the waste 9b exists to catch), and feeds the survivors to
    9's pairwise-conflict + fewest-conflicts-first landing-order machinery, unmodified. `<ref scouted="0">`
    is real unmerged work NOT fed to merge-scout THIS run — a cost bound, not a verdict (`bounded=` on the
    root element counts it; `--detail` lifts the bound to scout everything). **Cost**: 9b is a cheap per-blob
    sweep, but 9 is per-ARM (git-archive + full ingest of each ref's tree) — measured ~3s/ref on a real C++
    repo, so this is an EXPLICIT "before you land" call (pass both flags on purpose), not a per-question one.
    Bare `--plan` refuses loudly without `--stray-content`. Read-only; single-root only.
9d. **Did a branch silently break a CPU/GPU struct's byte layout?** — `ripwire <dir> --stray-content --abi`
    (`=SUBSTR` filters ref names, same as 9b). Neither `--layout=STRUCT` (one index, the working tree) nor
    `--stray-content` (line-granular — "added a float field" is just a stray line to it) catches a branch
    that adds one field to a dual-compile uniform struct: the merge is textually clean, review sees a
    harmless "+1 field", and the CPU ends up writing more bytes than the GPU reads for — wrong pixels, no
    compiler error. This runs `--layout`'s own field-offset arithmetic LEXICALLY on every ref that changed a
    path HEAD declares a struct/class in, and diffs the result against HEAD's computed fields. `kind="drift"`
    is a real byte-contract break (the only kind that exits 2); `kind="spelling"`/`"stub"` mirror `--layout`'s
    own harmless cases; `kind="unknown"` is a ref-side copy that could not be modelled (its caveats ride along
    — never reported as unchanged); `kind="absent"` is a ref that does not define the struct there at all.
    Matching structs are omitted (report only differences). Read-only, single-root, exit 2 on a real drift.

10. **Mid-edit contract check, one symbol at a time** — `ripwire <dir> --edit-check=SYM` (file:name
    disambiguates a same-named symbol, like `--around`/`--lego`). The fast, targeted sibling of step 8's
    `--test-gate`/`--quality-delta`: right after you touch a function, ask "did I just change a contract
    someone depends on" without waiting for a full diff. Reports exactly one of `status="unchanged"` /
    `"new-symbol"` / `"contract-change"` (with `params_was`/`params_now`/`public_was`/`public_now` on the
    latter) vs git HEAD, plus SYM's 1-hop callers with any call-site whose argument count is now provably
    incompatible flagged `incompatible="1"`. Warm (cache-hit) on ripwire's own tree.

## Output

Impact summary: blast-radius count, test coverage (zero = blocking concern), whether any changed file is a
top-10 hotspot, any lint findings in changed files, and any `--metrics` red flags (high/rising `cbo`,
`lcom4>1`, or missing `tested=1`) on a touched symbol. A green change passes: radius understood, tests exist, no new
lint smells, no hotspot surprise, no coupling/cohesion regression. Recommend one of: **safe to merge** /
**needs tests** / **review the hotspot** / **lint issues to fix** / **decouple before merge**. (Ran
quality-bar first? Both green = ship — see the Routing note above.)

**Honesty:** ripwire cedes data-flow/type checks (use-after-move, taint) to the compiler — pair this with
the build's warnings and the test suite. Blast radius is name-based; a high-`amb` edge was guessed.

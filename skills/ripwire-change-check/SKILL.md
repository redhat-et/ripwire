---
name: ripwire-change-check
description: >
  Merge-SAFETY of an existing diff, yours before you push or a PR you review: blast radius, tests to
  run, a broken contract (--edit-check=SYM), branch conflicts and landing order, unmerged work stranded
  on old branches, which ref defines it. Code QUALITY → quality-bar. Even a one-line leaf fix runs
  --edit-check.
allowed-tools: Bash, Read
---

# Change check with ripwire

> Routing: a change you have NOT written yet → **ripwire-before-you-build** · did the code itself get worse →
> **ripwire-quality-bar**, FIRST (the chain is "did it get worse" → "is it safe to merge") · risk not tied to a diff →
> **ripwire-fresh-eyes** · a test for existing untested code → **ripwire-write-tests**.

Run from the repo root with changes staged or unstaged, or the PR branch checked out: these verbs read `git diff`.

## Which question are you asking?

| Question | Run |
|---|---|
| did I just change a contract someone depends on? (per symbol, right after an edit) | `ripwire <dir> --edit-check=SYM` |
| which tests must I run — and is anything untested in the blast radius? | `ripwire <dir> --test-gate` (exit 4 if either is non-empty) |
| which tests reach these files | `ripwire <dir> --affected=F1,F2`, or `ripwire <dir> --situ` for the whole mid-task report |
| the review bundle for the diff (callers, blast radius, tests, co-change, owners) | `ripwire <dir> --pr-context --legend=compact` (vs a base: `--pr-context=main`) |
| can I delete this one symbol? | `ripwire <dir> --safe-delete=SYM` |
| several branches or worktrees: who conflicts, what landing order? | `ripwire <dir> --merge-scout=REF1,REF2,...` |
| what is stranded on old branches; which ref defines a symbol | `ripwire <dir> --stray-content` · `ripwire <dir> --whereis=SYM` |
| a test failed and I only have its file | `--exercises=TESTFILE` (the inverse of `--affected`) |

`--edit-check` reports one of `status="unchanged"` / `"new-symbol"` / `"contract-change"` vs git HEAD and flags any 1-hop
call site whose argument count is now provably incompatible (`incompatible="1"`).

## Stop rule

Do not turn a focused fix into a merge audit. A one-line leaf fix runs `--edit-check=SYM`: `"unchanged"` plus the focused
test plus `git diff --check` is enough. `"contract-change"` means it was not as leaf-level as it looked — now the bundle
is warranted. Never run `--pr-context` and then repeat its component steps without a specific unanswered question.

## Reading the answer

Headers carry `at="<sha>[+dirty]"`: quote it with findings; `+dirty` = uncommitted, re-run after you commit. Recommend
one of: **safe to merge** / **needs tests** / **review the hotspot** / **lint issues to fix** / **decouple before
merge**. Blast radius is name-based (a high-`amb` edge was guessed); data flow and types are the compiler's and the test
suite's job.

## Reference files

`pr-context.md` the bundle in full and the narrated walk (`--situ`, `--hotspots`, `--lint`, `--seams`, `--map-diff`,
`--metrics`, `--mentions`, `--test-gate`) · `branches.md` landing several branches, stranded content, `--whereis`, branch
ABI drift · `symbol-checks.md` `--edit-check` and `--safe-delete` in full, the Output checklist.

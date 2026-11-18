---
name: ripwire-change-check
description: >
  Merge-SAFETY of an existing diff — yours before you push, or a PR you review: blast radius, tests to
  run, a broken contract (--edit-check=SYM), branch conflicts and landing order, unmerged work
  stranded on old branches, which ref defines it. Code QUALITY → quality-bar. Even a one-line leaf fix
  runs --edit-check.
allowed-tools: Bash, Read
---

# Change check with ripwire

> Routing: a change you have NOT written yet → **ripwire-before-you-build** · did the code itself get worse →
> **ripwire-quality-bar**, run it FIRST (the chain is "did the code get worse" → "is it safe to merge") · risk in
> a subsystem not tied to a diff → **ripwire-fresh-eyes** · a test for existing untested code →
> **ripwire-write-tests** · unsure → **ripwire-router**.

`<dir>` = repo root, with your changes staged or unstaged (or the PR branch checked out): these verbs read
`git diff` themselves.

## The decision: which question are you asking?

| Question | Run |
|---|---|
| did I just change a contract someone depends on? (per symbol, right after an edit) | `ripwire <dir> --edit-check=SYM --legend=compact` |
| which tests must I run for this change — and is anything untested in the blast radius? | `ripwire <dir> --test-gate --legend=compact` (exit 4 if either is non-empty) |
| which tests reach these files | `ripwire <dir> --affected=F1,F2 --legend=compact`, or `ripwire <dir> --situ` for the whole mid-task report |
| the whole review-evidence bundle for the diff (callers, blast radius, tests, co-change, owners) | `ripwire <dir> --pr-context --legend=compact` (vs a base: `--pr-context=main`) |
| can I delete this one symbol? | `ripwire <dir> --safe-delete=SYM --legend=compact` |
| several branches or worktrees: who conflicts, what landing order? | `ripwire <dir> --merge-scout=REF1,REF2,... --legend=compact` |
| what is stranded on old branches; which ref defines a symbol | `ripwire <dir> --stray-content --legend=compact` · `ripwire <dir> --whereis=SYM --legend=compact` |
| a test failed and I only have its file | `--exercises=TESTFILE` (the inverse of `--affected`) |

`--edit-check` reports exactly one of `status="unchanged"` / `"new-symbol"` / `"contract-change"` vs git HEAD,
and flags any 1-hop call site whose argument count is now provably incompatible (`incompatible="1"`).

## Stop rule

**Scope guard:** Do not turn a focused fix into a full merge audit merely because a diff now exists. Even a
one-line leaf fix runs `--edit-check=SYM`: a genuinely `"unchanged"` result plus the focused test plus
`git diff --check` is enough to stop. A `"contract-change"` means the fix was not as leaf-level as it looked —
now the bundle is warranted. Never run `--pr-context` and then repeat its component steps without a specific
unanswered question.

## Reading the answer

Headers are stamped `at="<sha>[+dirty]"`: quote it when you paste findings; `+dirty` means uncommitted, so
re-run after you commit. Recommend one of: **safe to merge** / **needs tests** / **review the hotspot** /
**lint issues to fix** / **decouple before merge**. Blast radius is name-based; a high-`amb` edge was guessed.
ripwire cedes data-flow and type checks to the compiler and the test suite.

## Reference files

| You need | Read |
|---|---|
| the bundle in full; the narrated walk (`--situ`, `--hotspots`, `--lint`, `--seams`, `--map-diff`, `--metrics`, `--mentions`, `--test-gate`) | `pr-context.md` |
| landing several branches, stranded content, `--whereis`, branch ABI drift | `branches.md` |
| `--edit-check` and `--safe-delete` in full, and the Output checklist | `symbol-checks.md` |

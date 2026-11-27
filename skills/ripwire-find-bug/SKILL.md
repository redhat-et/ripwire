---
name: ripwire-find-bug
description: >
  A SYMPTOM — crash, exception, wrong output, failing test, error string — and no idea which code is
  responsible: ranks candidates; maps a stack trace or sanitizer output onto frames innermost-first; 'it
  worked yesterday' / 'my last edit broke it' → --situ. One clear hit plus one focused read is enough.
allowed-tools: Bash, Read
---

# Find the bug with ripwire

> Routing: you know the symbol and want to understand it → **ripwire-navigate** · blast radius / tests for a change →
> **ripwire-change-check** · a once-over with no symptom → **ripwire-fresh-eyes** · a feature that is simply not there
> may be built but flagged OFF: `ripwire <dir> --flags --legend=compact`.

## Pick the branch that matches what you have

| You have | First call |
|---|---|
| a stack trace, sanitizer report, compiler error, failing-test output | `ripwire <dir> --from-trace=FILE` (`-` = stdin) — paste it verbatim; frames map innermost-first, rank 1's body included |
| "I changed X and now something's broken" | `ripwire <dir> --situ` — your diff, its blast radius, tests to run, forgotten co-change partners |
| a symptom in words, no idea where | `ripwire <dir> --for="<symptom in plain words>"` |
| an exact error string | `ripwire <dir> --grep="ERROR_STRING" --legend=compact` (literal + enclosing symbol) |
| a suspect subsystem | `--for="<symptom>"`, then `ripwire <dir> --hotspots` on those directories |

Then read narrowly: the top symbol's body, or the smallest range that confirms or refutes it. For a regression, read
first what is in BOTH the blast radius (`--callers=SYM`) and the co-change list (`--cochange=FILE`).

## Stop rule

**Evidence-sufficiency stop:** escalate only while the responsible code is still ambiguous. One clear candidate plus a focused read that explains the
symptom with a minimal fix → stop retrieval; implement and validate. No `--hotspots`, `--impact`, other skill or
whole-file read once the defect is proven, unless the source contradicts the candidate or several remain plausible.

## Trust

Name-based edges can miss dynamic dispatch and callbacks; `--slice=SYM:VAR` (`--slice-flow=back|fwd|both`) gives a
variable's flow inside one function. Found it? `ripwire <dir> --note-add="SYM_or_path: what actually went wrong"`.

## Reference file

`branches.md` — all four branches step by step (symptom search, subsystem narrowing, regression with co-change, trace
mapping with `--token-budget` and `--run-trace`), the Output shape, the full Honesty note.

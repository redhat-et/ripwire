---
name: ripwire-find-bug
description: >
  You have a SYMPTOM — crash, exception, wrong output, failing test, error string — and don't know
  which code is responsible. Ranks candidates; a stack trace or sanitizer output maps onto frames
  innermost-first; 'it worked yesterday' / 'my last edit broke it' → --situ. One clear hit plus one
  focused read is enough.
allowed-tools: Bash, Read
---

# Find the bug with ripwire

> Routing: you know the symbol and want to understand it → **ripwire-navigate** · blast radius / tests for a
> change → **ripwire-change-check** · a quality once-over with no symptom → **ripwire-fresh-eyes** · a feature that
> is simply not there may be built but flagged OFF, not broken: `ripwire <dir> --flags --legend=compact`
> (**ripwire-fresh-eyes**).

`<dir>` = repo root; calls are warm after the first parse.

## The decision: pick the branch that matches what you already have

| You have | First call |
|---|---|
| a stack trace, sanitizer report, compiler error, or failing-test output | `ripwire <dir> --from-trace=FILE --legend=compact` (`--from-trace=-` reads stdin) — paste it verbatim; frames map to in-corpus symbols innermost-first, and rank 1's full body is included |
| "I changed X and now something's broken" | `ripwire <dir> --situ` — your diff, its blast radius, tests to run, co-change partners you forgot |
| a symptom in words, no idea where | `ripwire <dir> --for="<symptom in plain words>"` |
| an exact error string | `ripwire <dir> --grep="ERROR_STRING" --legend=compact` (literal + enclosing symbol) |
| a suspect subsystem | `--for="<symptom>"`, then `ripwire <dir> --hotspots --legend=compact` on those directories |

Then read narrowly: the top symbol's body or the smallest source range that can confirm or refute it. For a
regression, read first what appears in BOTH the blast radius (`--callers=SYM`) and the co-change list
(`--cochange=FILE`).

## Stop rule

**Evidence-sufficiency stop:** escalate only while the responsible code is still ambiguous. If one candidate
ranks clearly and a focused read explains the symptom with a minimal fix, stop retrieval and implement and
validate it. Do not add `--hotspots`, `--impact`, another skill or a whole-file read once the defect is proven.
Resume only when the source contradicts the candidate, several remain plausible, or the blast radius is itself
part of the task.

## Trust

The call graph gives structure; `--slice=SYM:VAR` (with `--slice-flow=back|fwd|both`) gives a variable's data
flow inside one function. Dynamic dispatch and callbacks can be missing from name-based edges. Found it? Pin the
gotcha: `ripwire <dir> --note-add="SYM_or_path: what actually went wrong"`.

## Reference file

`branches.md` — all four branches step by step (symptom search, subsystem narrowing, regression with co-change,
trace mapping with `--token-budget` and `--run-trace`), the Output shape and the full Honesty note.

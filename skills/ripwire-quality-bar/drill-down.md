# ripwire-quality-bar — reference: drill-down (read on demand; the recipe is in SKILL.md)

## When the delta flags something, zoom in
Thresholds/definitions are the catalog in [`quality-metrics.md`](quality-metrics.md) — this is just drill-down + fix:

| Regression | Drill-down | Fix |
|---|---|---|
| `complexity` | `--expand=SYM` | split the fn · early-return · lift the nested branch out |
| `verbosity` | `--expand=SYM` | the #1 agent failure mode (below) — cut boilerplate, don't just reformat |
| `nesting` | `--expand=SYM` · `--metrics` for the `humps=`/`deep=` profile | guard clauses · invert the condition · extract the nested block — but read the profile first: which of those three it is depends on `deep/loc` and `deep/humps` (playbook below) |
| `params` | `--expand=SYM` | bundle related params into a struct, or split the function |
| `duplication` | `--clones` | reuse the existing body — Rule of Three; wrong abstraction beats two honest copies |
| `dead-code` | — | delete what you orphaned, or wire the caller you forgot |
| `api-surface` (new public symbol) | `--callers=SYM` | intentional? keep it. Accidental? narrow it (should've been file-local) |
| `error-masking` (empty catch / bare `except: pass` / swallowed `.catch`; a broad handler that only logs and never names the error; a sole handler that re-throws it unchanged) | `--expand=SYM` | handle it, log the error itself, or drop the try — AI code adds these +47% vs human (GitClear 2026). The two widened shapes gate only in Python (measured precision); elsewhere `sev="minor"` |
| `short-horizon-churn` | `--hotspots` · `git log -p <file>` | rewritten again inside 2 weeks (+15% AI) — is the design unsettled? consolidate |
| `new-clone-of-reused-helper` | `--clones` · `--callers=HELPER` | call the existing well-reused helper — reuse is declining in AI code (GitClear) |
| `placeholder` (an added stub or TODO: `todo!()`, `NotImplementedException`, a "not implemented" throw/panic, a TODO/FIXME naming no issue) | `--expand=SYM` | finish it, or name the issue that tracks it — never gates, but do not call the work done over it |
| `defect-shape` (`defect=`: `format-arity` — a literal format whose `{}` fields do not match its arguments; `utf8-cut` — a byte cap plus an ellipsis with no UTF-8 back-off; `dedup-first` — `std::unique` keeping the first of a run over a type with a severity field; `vacuous-assert` — a test script's assertion that passes on an empty text (absence, parity) read off a run whose failure is unchecked: a capture, a pipe without pipefail, a redirected file, a dropped wrapper status; also a FAIL reporter inside `$( )` and an unread `rc=$?`; `unchecked-status` — a dropped I/O or child status: C/C++ `pclose`/`rename`/`write`/`system`/`fflush`/`waitpid`, an `fclose`/`close` of what the function wrote, Python `subprocess.run` with no `check=`, `subprocess.call`, `os.system`; the row's `call=` names it and its `p=` is the site; `unhandled-arm` — a switch/case/if-chain over a closed set that gives an unnamed value no outcome: a C/C++ switch missing an in-tree enumerator with no `default:`, a shell case with no `*)`, a Python chain that falls off to `None`; `why=` names what is left out) | `--expand=SYM` | `format-arity` gates on any origin: match the fields to the arguments. The other five are `sev="minor"`: back off continuation bytes (or call the utf8 helper), sort worst-first before the unique, check the run's exit status before the absence, check the status (`check=True`) or `(void)` it with a reason, add the arm or a default that states the decision |
| `tangle` (gates a function that is new at 6.0 or more, crossed 6.0, or grew while over it — not a moved body, not test code; a row an input rose on while the score held is `sev="minor"`: a long function's nesting past 3, deep share and steering locals, amplified by length; `why=` names the input that rose, `locals=` the steering locals, `ratchet="TAG"` a function above its best since the last tag) | `--expand=SYM` · `--metrics` for `steer=`/`tangle=` | follow `fix=`: split the step that sets a steering local from the branch that reads it, extract the deep region it names, or split into named phases. A long orchestrator of named steps scores 0 — length alone is never the finding. `<improved>` lists what your change made better |

These 13 kinds aren't a generic lint list. Ten target an agent-code degradation mode validated at large N
(verbosity, structural erosion, smell rate, contract drift; passing tests ≠ clean design); `placeholder` is an
honesty check on your own "done"; `defect-shape` is six defect shapes code review kept finding by hand. Numbers + why the
loop must be continuous, not a one-time prompt → [`quality-metrics.md`](quality-metrics.md).

**Read the Fix column as DIRECTION, not a computed answer.** None of these 13 kinds has a corpus-derivable
correct replacement — "split the fn" names a move, not a target function shape, and you still judge it. That
is deliberate: complexity, coupling, and colocation don't have a computable right answer the way a naming
CONVENTION does. The one exception in this whole tool is `--naming-consistency` (→ **ripwire-fresh-eyes**),
which proposes an actual `propose=` value because case-style consistency is Tier A — the corpus's own
majority IS the answer, mechanically recombined from the name's own subtokens, no judgment call involved.
Don't expect that anywhere else, and don't invent a "the fix is X" claim here that this tool doesn't itself
compute.

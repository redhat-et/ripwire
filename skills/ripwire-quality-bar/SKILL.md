---
name: ripwire-quality-bar
description: >
  The code-QUALITY bar for what you just wrote — not merge-safety. Needs NO setup: right before you commit /
  open a PR / tell the user it's finished, run `ripwire <dir> --quality-delta` — reports ONLY what you made
  WORSE across 10 measured kinds (complexity, verbosity, nesting, params, duplication, dead-code,
  API-surface, error-masking, short-horizon-churn, new-clone-of-reused-helper — the measured agent-code
  failure modes), exiting non-zero on new debt. Fix the real regressions, re-run, converge. Reach for this at
  every "I think this is done" moment on non-trivial work — but a single-line leaf fix with no new
  branch/symbol/signature does NOT need this pass (or this file): run the focused test and move on. For
  merge-safety / blast-radius / tests-to-run →
  **ripwire-change-check** instead (this skill judges the code, not whether it's safe to merge). Backed by
  ripwire (deterministic, on PATH).
allowed-tools: Bash, Read
---

# The quality-bar convergence loop

> Routing:
> • PR-submission readiness — tests to run, blast radius, "safe to merge?" → **ripwire-change-check** — run
>   `--quality-delta` FIRST, then its `--test-gate`: clean code that runs the wrong tests still regresses.
> • Reusing before you write the code in the first place → **ripwire-reuse-first**.
> • Wide-angle "where does this still look rotten" read across a whole file/subsystem (not a before/after
>   delta) → the panel below, or **ripwire-fresh-eyes** for the full six-family breakdown.
> • Not sure which skill? → **ripwire-router**.

Don't eyeball quality — **measure the delta your change introduced**, with a deterministic oracle, in a
bounded loop. A file that was already complex is not your regression.

Apply the "non-trivial work" trigger literally. A single-line leaf fix that preserves the signature and
adds no branch, symbol, dependency, or abstraction does not need a standalone quality-delta pass unless
the repository requires it; run the focused behavioral test and diff checks instead. This skill earns its
cost when the edit can change measured structure, not merely whenever the working tree is dirty.

## Before you converge: the wide-angle read — `--quality-panel`

`ripwire <dir> --quality-panel[=strict|default|lenient]` is THE SINGLE COMMAND for "does what I just
touched still look rotten" — one ranked report over **six** evidence families (the four `--ensemble`
joins — `structural`, `lexical`, `confusion`, `historical` — plus `colocation` and `state`; the full
per-family breakdown lives in **ripwire-fresh-eyes**). Point it at the file or symbol you just edited for
a multi-angle second opinion the single `--quality-delta` number can't give you on its own.

**Read it correctly: it is a lens, never a gate.** `--help` says so in the flag's own text and the
contract is enforced in code — `--quality-panel` exits 0 unconditionally, on every preset, on every repo.
It does not compare against a baseline and it cannot fail a commit. The gate for "did MY change make this
WORSE" is Step 3 below (`--quality-delta`) — that is the only pass in this skill (or in ripwire) with an
exit code that means something. Run `--quality-panel` for the wide-angle read, converge with
`--quality-delta`, never the other way round.

Pick the preset by what "rotten" needs to mean right now: `lenient` (all six families, 1 must agree) is a
reading order, roughly a third of any tree; `default` (all six, 2 must agree) is a review list; `strict`
(only the four families measured stable enough to stand behind repeatedly — `historical` and `colocation`
are fixed-size worst-40 cuts over a ranking whose population moves, so both re-shuffle release to release
on code that never changed) is the rung closest to something CI-shaped, but it is still a lens — nothing
here plugs into an exit code the way `--quality-delta` does.

## The loop
1. **Zero-setup path:** just make your change, then run `ripwire <dir> --quality-delta` before you call it
   done — in a git repo it auto-compares the working tree vs `git HEAD` (`<quality-delta
   baseline="git-HEAD">` confirms it), no start-of-task action needed. **Tighter loop on a long change:** run
   `ripwire <dir> --quality-baseline` FIRST to pin an explicit floor (takes precedence over HEAD) so each
   edit deltas against the original start, not the last commit.
2. **Make your change.**
3. **Measure the delta** — `ripwire <dir> --quality-delta` → only the regressions you introduced, across the
   10 kinds in the table below. Each emits `<r kind="…" sym=… was=… now=…>` (`members=` for duplication).
   Test-fixture dirs are exempt from `dead-code`; `short-horizon-churn` ignores your own current edit and
   exempts brand-new symbols/markdown/fixtures. **Watch `verbosity` hardest** — LOC growth is the single
   most-measured agent failure mode, the one most likely to hide in an otherwise-clean diff.

   **Read the exit code correctly — it is narrower than it looks.** Findings are sorted on three
   independent axes, and only one combination gates:
   - **acked** — suppressed entirely (counted honestly in `acked="N"`).
   - **ORIGIN** — a symbol that EXISTED at the baseline and got worse is *preexisting-worse* (**no**
     `origin=` attribute on the row); one that exists only because the code is NEW carries
     `origin="new-symbol"`.
   - **MATERIALITY** — a small numeric delta is additionally `sev="minor"`.

   **`--quality-delta` exits 2 ONLY on preexisting-worse AND major AND unacked** — exactly the
   `gating="N"` count in the header. Read `gating=`, not `regressions=`. A real header looks like:

   ```
   <quality-delta baseline="git-HEAD" regressions="0" minor="0" acked="0"
                  preexisting-worse="0" new-symbol="0" gating="0" at="f0a45e43d">
   ```

   **`origin="new-symbol"` rows are PRINTED but NEVER gate.** They are the debt you are adding — read
   them; nothing else will make you. And `--help` is explicit that **exit 0 means "nothing that already
   existed got worse", NOT "clean"**: a change that is entirely new code can add unbounded new-symbol
   debt and still exit 0. Never report "quality-delta passed" as "no new debt" — open the rows.

   Two more contract details worth knowing: clone kinds classify by member set (a group is new-symbol
   only if EVERY member is new), and `short-horizon-churn` is preexisting by construction.
   **LIMIT:** origin is canonId (`path::scope::name`) identity, so a **RENAMED or MOVED symbol reads as
   new** — a genuine regression carried in with a move classifies `new-symbol` and will not gate. If your
   diff moves code, the exit code is especially weak evidence; read the rows.
4. **Fix the REAL ones, re-run, converge.** Repeat until clean or the remainder are conscious trade-offs.
   **Record a trade-off instead of re-reading it forever:** `ripwire <dir> --quality-ack="why it's accepted"`
   writes the currently-visible findings into `.ripwire_quality_acks` (committable) — later runs suppress
   them honestly (`acked="N"`) and a finding REAPPEARS the moment it worsens past its acked size.

   **Ack a SUBSET, never the screen.** Bare `--quality-ack` accepts *every* finding currently visible, so
   using it to accept one deliberate change silently accepts the rest too — that is how a ratchet turns into
   a rubber stamp. Narrow it with `--ack-only=SUBSTR[,SUBSTR]`, which matches a finding's kind, its canonical
   id, or its **facet**:

   ```bash
   ripwire <dir> --quality-delta --ack-only=contract-change --quality-ack="arity change required by <fix>"
   ```

   Prefer the facet over the kind when one exists: `api-surface` also covers the never-gating `new-symbol`
   rows, so acking by kind can sweep in dozens of findings to accept a handful. `--ack-only=gating` selects
   exactly what would exit 2. A pattern matching nothing refuses (exit 1) rather than acking everything.
   Whatever you leave unacked stays visible — that is the point; an exit 2 you have explained in a commit
   message is worth more than an exit 0 you bought with a blanket ack.

## When the delta flags something, zoom in
Thresholds/definitions are the catalog in [`quality-metrics.md`](quality-metrics.md) — this is just drill-down + fix:

| Regression | Drill-down | Fix |
|---|---|---|
| `complexity` | `--expand=SYM` | split the fn · early-return · lift the nested branch out |
| `verbosity` | `--expand=SYM` | the #1 agent failure mode (below) — cut boilerplate, don't just reformat |
| `nesting` | `--expand=SYM` | guard clauses · invert the condition · extract the nested block |
| `params` | `--expand=SYM` | bundle related params into a struct, or split the function |
| `duplication` | `--clones` | reuse the existing body — Rule of Three; wrong abstraction beats two honest copies |
| `dead-code` | — | delete what you orphaned, or wire the caller you forgot |
| `api-surface` (new public symbol) | `--callers=SYM` | intentional? keep it. Accidental? narrow it (should've been file-local) |
| `error-masking` (empty catch / bare `except: pass` / swallowed `.catch`) | `--expand=SYM` | handle, log, or rethrow — AI code adds these +47% vs human (GitClear 2026) |
| `short-horizon-churn` | `--hotspots` · `git log -p <file>` | rewritten again inside 2 weeks (+15% AI) — is the design unsettled? consolidate |
| `new-clone-of-reused-helper` | `--clones` · `--callers=HELPER` | call the existing well-reused helper — reuse is declining in AI code (GitClear) |

These 10 kinds aren't a generic lint list — each targets a large-N-validated agent-code degradation mode
(verbosity, structural erosion, smell rate, contract drift; passing tests ≠ clean design). Numbers + why the
loop must be continuous, not a one-time prompt → [`quality-metrics.md`](quality-metrics.md).

## The four guardrails (why this loop converges instead of degrading)
1. **Deterministic oracle, not self-critique.** The delta is *computed* — it cannot hallucinate or reinforce
   a bad regression. Trust it over a vibe.
2. **Descriptive, never a target.** Fix the regression for the right reason. **Never** split a function or
   delete a "duplicate" *just to move the number*, and **never edit a test to make the bar pass** —
   metric-gaming: the score improves while the code gets worse.
3. **Bounded — 1–2 rounds.** A 2nd or 3rd blind refinement round often *degrades* code. Stop when clean or
   the rest are conscious trade-offs; don't chase zero.
4. **Persist the bar.** Re-baseline after you commit, so the next change measures against the new floor.

## Wire it into CI / pre-commit

`--quality-delta` exits 2 **only when a finding is preexisting-worse AND major AND unacked** — the
`gating="N"` header count. Minor-tier, acked, and `origin="new-symbol"` findings all report but never gate,
so **a green hook does not mean the diff added no debt** — it means nothing that already existed got worse.
Non-zero is the hook contract, no wrapper needed: `ripwire <dir> --quality-delta || exit 1`. If you want CI
to also block on the debt a change ADDS, exit 2 will not do it for you — parse `new-symbol="N"` from the
header (`--json` is supported for this verb) and apply your own policy. Chain the
other deterministic gates in the same hook: det-gate (`diff <(ripwire <dir>) <(ripwire <dir>)`, must be
byte-identical) and `ripwire <dir> | xmllint --noout -` (valid XML) — any non-zero exit blocks the commit.

## Honesty
ripwire measures STRUCTURE (complexity / duplication / reachability), not data flow — it cedes
use-after-move / taint / type / null errors to the compiler. A high `amb=` symbol can be a dispatch hub, not
a bug. Thresholds are heuristics: trust coupling/churn hardest, complexity as size-correlated (not
independent), and Martin `I/A/D`/`nccd` as descriptive only — never proof. Full catalog (definition · why it
predicts defects · evidence tier · the verb) → [`quality-metrics.md`](quality-metrics.md).

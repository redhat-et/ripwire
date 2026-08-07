---
name: ripwire-quality-bar
description: >
  The code-QUALITY bar for what you just wrote — not merge-safety. Needs NO setup: right before you commit /
  open a PR / tell the user it's finished, run `ripwire <dir> --quality-delta` — reports ONLY what you made
  WORSE across 10 measured kinds (complexity, verbosity, nesting, params, duplication, dead-code,
  API-surface, error-masking, short-horizon-churn, new-clone-of-reused-helper — the measured agent-code
  failure modes), exiting non-zero on new debt. Want the wider six-family "does this still look rotten" read
  alongside the delta? `--quality-panel` is THE SINGLE COMMAND for that — the headline wide-angle pass below.
  Also carries the two things a measurement alone doesn't give you: the **shape → refactor playbook** (a
  measured shape mapped to its named fix AND that fix's precondition, so you don't guard-clause a numeric
  kernel or refactor an untested hub) and the **closed fix loop** that proves the fix landed
  (`--quality-delta` → `--edit-check` → `--affected`). Fix the real regressions, re-run, converge. Reach for this at
  every "I think this is done" moment on non-trivial work. The check itself is cheap (well under a second
  warm) — run it even on a fix that looks trivial, because "trivial" is exactly the judgment this pass exists
  to catch you being wrong about; what a single-line leaf fix with no new branch/symbol/signature can skip is
  the CONVERGENCE LOOP around it (re-reading the drill-down table, acking, chasing `--dmm`) — read this file
  only if the one-shot delta actually reports something. For
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
> • **You have the measurement and need the FIX** — for your own diff or for a subsystem **ripwire-fresh-eyes**
>   just measured → the shape → refactor playbook and the closed fix loop are both on this page, below.
> • Not sure which skill? → **ripwire-router**.

Don't eyeball quality — **measure the delta your change introduced**, with a deterministic oracle, in a
bounded loop. A file that was already complex is not your regression.

Apply the "non-trivial work" trigger to the LOOP, not the check. `--quality-delta` warm-runs in well under a
second — cheaper than deciding by eye whether a fix "counts" as trivial, and that eyeball judgment is
precisely where a leaf-looking edit that quietly changed a signature or added a branch slips through
unmeasured. Run it. What a single-line leaf fix that preserves the signature and adds no branch, symbol,
dependency, or abstraction gets to skip is everything AFTER a clean run: the drill-down table, `--dmm`,
acking, a second round. This skill (and this file) earns its cost when the one-shot delta actually reports
something — a clean `gating="0"` run on a leaf fix is confirmation, not ceremony you were right to skip.

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

### Read the structural row as a PROFILE — `nest=` alone is a max, and misleads solo

`nest=` reports the single deepest line in a function. One line at depth 9 and a thousand lines at depth 9
report the same number, so `nest=9` cannot tell a **tangled** body from a long **blocked-sequential** one
whose max was set by one inner loop nobody has to hold in their head. Acting on `nest=` alone is how an
agent guard-clauses a dispatch table. `--metrics` (and the structural family's `why=` string in
`--quality-panel` / `--ensemble`) now carry the profile beside the max:

```
<e f="structural" counted="1" why="ccx=724 loc=1244 nest=9 humps=30 deep=308 rrank=1"/>
```

**Every concrete number on this page is ILLUSTRATIVE OF A SHAPE, never a value to expect.** The counters
themselves are under active calibration — an else-clause over-count fix in flight moves `humps=` down by a
large fraction, and `ccx=`/`nest=` with it, on else-heavy functions. What is durable is what you *do* with
the row: `humps=1` vs many, the two ratios below, and the semantics (regions vs lines, absence below the
bar, `deep < humps` legal). Read the row in front of you; never carry a remembered number to it.

- **`humps=`** — how many *maximal control-nesting regions* reach the nesting bar (`bar_nest=` on the panel
  root; CodeScene's "bumpy road": a rise above the threshold then a fall). One deep tangle is `1`; repeated
  missing abstractions are many. EXACT, not a floor.
- **`deep=`** — how many **LINES** lie inside those regions, read against the `loc=` already on the row. A
  disclosed FLOOR (`deep_floor="1"`).
- Both are **absent exactly when `nest <` the bar** — not-deep, never a hidden `0`.
- **`deep` below `humps` is legal output, not a defect.** `deep` counts lines and `humps` counts regions, and
  two regions can share a line: a one-line `if(c){x;}else{y;}` at the bar is 2 regions on 1 line. Three
  reviewers have read that shape as a bug; it isn't.

Two ratios do the actual discriminating, and you compute them yourself from the row:

| Ratio | High says | Low says |
|---|---|---|
| **`deep/loc`** | **tangled** — the body *sustains* depth, so most of what you read is nested | **blocked-sequential** — a long run of shallow steps (a dispatch table, a switch, a setup block); the max is one inner loop |
| **`deep/humps`** | **few giant tangles** — one region holds depth for a long stretch; the expensive fix | **many tiny touches** — repeated missing abstractions, each hump its own cheap extraction |

Three shapes off this repo's own source — read the *pattern*, not the digits, which move with calibration:
a ~1000-line function at a **low** `deep/loc` (`main`, roughly a tenth) sits beside one at **~2.5×** that
fraction (`buildGraph`) once `loc`/`nest` have declared them equivalent; and a function far too small for
any size bar to fire can carry the **highest** `deep/loc` in the table (`ur_walkTree`, `loc=87`, near half
its body deep in a single hump). The first is blocked-sequential, the second tangled, the third dense —
three different fixes, one indistinguishable `nest=`.

**`locals=`** rides the same row: the count of local-variable declarations, a FLOOR (`locals_floor="1"`),
**C/C++ only** and **absent — never a bare `0`** — for every other language. It measures the working set a
reader must hold at once, which is the thing extraction is actually supposed to shrink; a "split" that leaves
`locals` where it was mostly moved braces.

**`join="deep+untested"`** on a `--quality-panel` row is a **conjunction of two facts the report already
holds** — this row carries `deep=` *and* no indexed test reaches it — annotated, not a seventh family. It
changes nothing: not `fam=`, not `of=`, not the ordering, not which rows appear. It is the pair where a
refactor is most wanted and least safe, so it routes straight to **test first, refactor second** in the
playbook below. It is **suppressed on every row when `tested_scope="0"`**, because on a corpus whose tests
were never crawled "untested" would be a fact about the crawl, not about the code — read `tested_scope=` on
the root before you read the absence of the annotation as good news. `deep_untested=` on the root counts them
across the WHOLE row set, which the `limit=` window does not change.

**The per-file churn caveat.** The `historical` family's `churn=` and `hrank=` are **FILE facts, inherited
verbatim by every symbol in the file** — a symbol in a churny file collects that family without any property
of its own. Discount it accordingly: on a row whose other evidence is thin, `historical` may be saying only
"this file is busy", not "this function is." (`hrank=` is also a *relative* decile cut over this corpus, so
something always fires.)

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
4. **Fix the REAL ones, re-run, converge.** Which fix a row calls for is the **shape → refactor playbook**
   below; proving the fix landed is the **closed fix loop** below that. Repeat until clean or the remainder
   are conscious trade-offs.
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

5. **Want ONE number instead of a list — `ripwire <dir> --dmm`.** `--quality-delta` says *which* kinds got
   worse; it has no scale, so "is this change better than my last one?" has no answer. `--dmm` is that scale:
   the Delta Maintainability Model (di Biase, Rastogi, Bruntink & van Deursen, TechDebt 2019; thresholds and
   arithmetic from PyDriller's reference implementation) scores the share of the volume your change moved
   that landed in — or freed from — risky units.

   ```
   <dmm base="2edbb46c…" target="working-tree" available="1" combine="pooled" size_metric="physical-loc"
        dmm="0.436" good="462" bad="597" base_units="4759" target_units="4780">
     <p k="size" dmm="0.184" good="65" bad="288" d_low="65" d_high="288"/>…
   ```

   A unit (a function/method definition with a body) is **low risk** iff `loc<=15` (size), `cyclomatic<=5`
   (complexity), `params<=2` (interfacing). `good` = low-risk volume **added** plus high-risk volume
   **removed**; `bad` = the reverse; `dmm = good/(good+bad)`. **Deleting a god function scores 1.000;
   growing one scores 0.000.** The three sub-scores are separately actionable — a low `size` with a healthy
   `interfacing` says *split the function*, not *change the signature*.

   Three things to carry. **It is a DELTA, never a level:** editing bad code without changing its size,
   complexity or parameter count contributes *nothing* — you are not punished for touching a mess, which is
   deliberate. **`dmm="UNAVAILABLE"` is not a score of 1.0 or 0.0** — it means `good+bad` was 0 (a rename, a
   literal edit, a comment reflow), i.e. the change is outside what the model measures; the same token can
   appear per property. And **it never gates** (always exit 0): use it to *trend* — `--dmm=REV` scores one
   commit against its parent and `--dmm=A..B` scores a range, so a series of commits is a series of numbers.

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
| `error-masking` (empty catch / bare `except: pass` / swallowed `.catch`) | `--expand=SYM` | handle, log, or rethrow — AI code adds these +47% vs human (GitClear 2026) |
| `short-horizon-churn` | `--hotspots` · `git log -p <file>` | rewritten again inside 2 weeks (+15% AI) — is the design unsettled? consolidate |
| `new-clone-of-reused-helper` | `--clones` · `--callers=HELPER` | call the existing well-reused helper — reuse is declining in AI code (GitClear) |

These 10 kinds aren't a generic lint list — each targets a large-N-validated agent-code degradation mode
(verbosity, structural erosion, smell rate, contract drift; passing tests ≠ clean design). Numbers + why the
loop must be continuous, not a one-time prompt → [`quality-metrics.md`](quality-metrics.md).

**Read the Fix column as DIRECTION, not a computed answer.** None of these 10 kinds has a corpus-derivable
correct replacement — "split the fn" names a move, not a target function shape, and you still judge it. That
is deliberate: complexity, coupling, and colocation don't have a computable right answer the way a naming
CONVENTION does. The one exception in this whole tool is `--naming-consistency` (→ **ripwire-fresh-eyes**),
which proposes an actual `propose=` value because case-style consistency is Tier A — the corpus's own
majority IS the answer, mechanically recombined from the name's own subtokens, no judgment call involved.
Don't expect that anywhere else, and don't invent a "the fix is X" claim here that this tool doesn't itself
compute.

## The shape → refactor playbook

The table above maps a *regression kind* to a direction. This maps a **measured shape** to the **named
refactor** and — the part agents skip — that refactor's **precondition**. Same doctrine as everything else
here: these are facts plus options, never verdicts. The tool measures the shape; which option is right is
still your call, and "leave it alone" is always on the menu.

| Measured shape | The named fix | Its precondition — check this FIRST |
|---|---|---|
| **Many shallow humps** — `humps` high, `deep/humps` small, `deep/loc` low | **Extract each hump.** The bumpy-road fix: every region that rises to the bar and falls back is one missing abstraction with its own name. Cheap, mechanical, one hump at a time. | Nothing structural blocks it — but each extraction is a new symbol, so re-run the loop below: extraction that lands as `origin="new-symbol"` `api-surface` debt should be file-local, not public. |
| **One deep tangle** — `humps=1` (or few) with high `deep/loc` | **Guard-clause inversion**, then **state extraction**: invert the conditions that hold the depth, return early, and lift the sustained region's working set into a named struct or its own function. Expensive and genuinely risky — a rewrite, not a move. | `locals=` tells you what you're really moving; a big `locals` means the region's working set, not just its braces, has to travel. Check `--callers=SYM`/`--impact=SYM` before starting, and never do it in the same diff as a behavior change. |
| **Small AND dense** — small `loc`, but `deep` is a large fraction of it (roughly half or more), typically in one hump | **Read it before you prescribe anything.** Numeric kernels, tree walks, and state machines are *legitimately* dense: the depth is the algorithm. Often the right fix is a comment or a named constant, not a split. | This row is where a metric-driven agent does the most damage. `--expand=SYM` first. If the density is the algorithm, ack it (`--ack-only=`) and move on. |
| **High fan-in AND untested** — big `in=`/`amp=`, `tested="0"`, or a `--quality-panel` row carrying `join="deep+untested"` | **Test first, refactor second.** The safety net is the fix's precondition, not its follow-up. → **ripwire-write-tests** (`--seams`, the `tested=` lens, `--callers=SYM` for the outside contract). | Confirm the annotation is real: `join=` is suppressed entirely at `tested_scope="0"`, so on an uncrawled-test corpus its *absence* proves nothing. |
| **Duplication** — a `--quality-delta` `duplication` / `new-clone-of-reused-helper` row, or a `--clones` group | **Consolidate through the repo's own exemplar** — `ripwire <dir> --exemplar="<what this code does>"` names the best-in-class instance to converge on (chosen by ROLE, not text similarity), so the survivor matches house patterns instead of being whichever copy you happened to open. | **Rule of Three** — extract on the third occurrence, not the second; a wrong abstraction is worse than two honest copies. Check `type=` on the clone group: `type="3"` members are gapped near-misses and may differ on purpose. |
| **Churn-flagged, structurally quiet** — `historical` fires with thin other evidence | **Probably nothing here.** `churn=`/`hrank=` are FILE facts inherited by every symbol in the file. | Confirm at the symbol before acting: `git log -p <file>` or `--hotspots --since=` to see whether *this* function is what keeps moving. |

**None of these has a corpus-derivable "correct" answer** — see the paragraph above the table. The playbook
names a move and the condition that makes the move safe; it does not compute a target shape, and any of these
rows can honestly end in "measured, understood, left alone."

## The closed fix loop — fix it, then PROVE the fix landed

Fixing without verifying is how a refactor trades one regression for two. Four steps, in this order; each
answers a question the previous one cannot:

```bash
# 1. make the fix (playbook above)
ripwire <dir> --quality-delta        # 2. did the TARGETED kind improve, and did nothing else regress?
ripwire <dir> --edit-check=SYM       # 3. is the CONTRACT intact?
ripwire <dir> --affected=F1,F2       # 4. which tests PROVE it? (then run them)
```

2. **`--quality-delta`** — the only step with a meaningful exit code, and it is doing *two* jobs here, not
   one: the row you were chasing should be gone, **and** nothing new should have appeared. A "split the
   function" fix that drops `complexity` while adding `api-surface` + `duplication` is a lateral move.
   Read `gating=`, but also read the `origin="new-symbol"` rows — extraction *always* creates new symbols and
   those never gate, so exit 0 is not the same as "the fix was free."
3. **`--edit-check=SYM`** — `unchanged` / `new-symbol` / `contract-change` for the symbol you just edited:
   param count and publicness NOW vs `git HEAD`, plus its 1-hop callers with any call site provably
   incompatible with the new arity flagged. A refactor is *supposed* to be `unchanged` here; a
   `contract-change` you did not intend is the finding. Cheap enough (~ms warm) that skipping it is never the
   economical choice. It refuses (exit 1) if `SYM` matches several definition sites — a contract is per
   definition, so pass the `file:name` spelling it lists.
4. **`--affected=F1,F2`** (or `--affected=SYM`) — the test files that transitively reach what you changed.
   Metrics improving is not evidence the code still works; this names what to run, and then you run it.
   Mid-task, `--situ` is the same answer over the whole `git diff` plus co-change partners; at PR time
   `--test-gate` is the gating form (exit 4 when tests-to-run or the untested blast radius is non-empty).

**Done means:** the targeted kind is gone from `--quality-delta`, nothing else regressed, `--edit-check`
reports the contract you intended, and the `--affected` tests pass. Anything short of all four and the fix is
still a hypothesis.

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

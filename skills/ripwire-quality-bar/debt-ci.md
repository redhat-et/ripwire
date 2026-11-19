# ripwire-quality-bar — reference: debt-ci (read on demand; the recipe is in SKILL.md)

## The fix loop — paying down EXISTING debt, one finding per commit

The loop above converges on debt *you* just added. When the task is debt that was already there ("clean up this
module", "fix the worst of it"), run this instead — bounded, one finding at a time:

1. **Pick the top finding.** Your own open rows first (`gating=`, then `origin="new-symbol"`); otherwise row 1 of
   `ripwire <dir> --quality-panel=strict --legend=compact` pointed at the area you were asked about. The panel orders
   by how many independent families agree, not by payoff — no validated value × cost ranking ships yet — so between
   near-ties take the cheapest: small, tested, few `--callers=SYM`.
2. **Untested? Write the test first.** `join="deep+untested"` on the row, or `ripwire <dir> --affected=SYM --legend=compact`
   naming no `<test>` row that carries `hops=` (a `partner="1"` row without `hops=` is co-change, not reach), means
   the refactor has no safety net. Write one against the UNCHANGED code
   (→ **ripwire-write-tests**), see it pass, commit it alone. A test written after the refactor pins the new
   behavior, not the old.
3. **Apply the recipe the shape calls for** — the drill-down table's Fix column for a regression kind, the playbook
   row (precondition first) for a measured shape. The one recipe neither table carries:
   a `--lint --lint-select=magic-number` finding (C/C++/ObjC) → a named constant. "Leave it alone" is still on the menu.
4. **Prove it** — the closed fix loop above, all four steps, with one rule stricter than its step 2 (**anti-gaming**):
   the fix must not worsen ANY other kind. Measure BEFORE you commit, one fix per commit, so a bare `--quality-delta`
   (working tree vs `git HEAD`; re-pin after each commit if you pinned `--quality-baseline`) covers exactly this fix — after the commit it reads `regressions="0"` trivially
   (`head_basis="identity"`); to check a fix already committed, run `ripwire <dir> --quality-delta=HEAD --legend=compact`
   (that commit vs its parent). Then `regressions=` must be `0`, not just `gating=`, and `acked=` must not rise (a
   pre-ack hides a row). The one exemption: a `kind="short-horizon-churn"` row with `churn="self"` on a function this
   session already fixed is the loop's own commits, not a regression — better, take the next row from a different
   function. A fix that trades its target for a row of any other kind — a `duplication`, a `params`, a public
   `api-surface` helper that should have been file-local — is a lateral move: revert it, don't ack it.
   `--quality-delta` only lists what got worse, so confirm the target moved by re-running the command that ranked it.
5. **Stop at 3 fixes per session** (a default, not a measured optimum). Guardrail 3 bounds each fix to 1–2 rounds;
   this bounds the session. End by naming the next row, not starting it — a long unreviewed chain of mechanical
   refactors is where gaming hides.

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

`--quality-delta` exits 2 on exactly the **What exits 2** rows above — the `gating="N"` header count — so
**a green hook does not mean the diff added no debt**: it means nothing that already existed got worse (and no
format/argument mismatch was added).
Non-zero is the hook contract, no wrapper needed: `ripwire <dir> --quality-delta --legend=compact || exit 1`. If you want CI
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

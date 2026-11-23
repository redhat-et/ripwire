# ripwire-quality-bar — reference: panel (read on demand; the recipe is in SKILL.md)

# The quality-bar convergence loop

> Routing:
> • PR-submission readiness — tests to run, blast radius, "safe to merge?" → **ripwire-change-check** — run
>   `--quality-delta` FIRST, then its `--test-gate`: clean code that runs the wrong tests still regresses.
> • Reusing before you write the code in the first place → **ripwire-reuse-first**.
> • Wide-angle "where does this still look rotten" read across a whole file/subsystem (not a before/after
>   delta) → the panel below, or **ripwire-fresh-eyes** for the full six-family breakdown.
> • **You have the measurement and need the FIX** — for your own diff or for a subsystem **ripwire-fresh-eyes**
>   just measured → the shape → refactor playbook, the closed fix loop and the debt fix loop are all on this page, below.
> • **The regression is a MEMORY-layout hypothesis, not one of the 13 quality kinds** — `--lint`'s built-in
>   cache-\* pack (8 static data-layout checks) is a normal part of a lint pass; `--field-affinity[=STRUCT]`
>   is the deeper struct-level lens once a profile implicates a specific aggregate → **ripwire-perf-target**.
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

`ripwire <dir> --quality-panel[=strict|default|lenient] --legend=compact` is THE SINGLE COMMAND for "does what I just
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

# ripwire-fresh-eyes — reference: coupling-refactor (read on demand; the recipe is in SKILL.md)

## Hidden-coupling pass — "a change here keeps breaking unrelated files" (Fowler's Shotgun Surgery, in its measurable form: change coupling)

6. **Behavioural coupling** — `ripwire <dir> --cochange --legend=compact`
   Bare `--cochange` emits ONLY the *surprising* pairs — files that change together in git but share **no
   static dependency** either way:
   `<cochange pairs="N" sub_windows="3"><pair a="…" b="…" together="17" deg="1.00" conf_ab="1.00"
   conf_ba="0.34" driver="a" recur="3" surprising="1"/>…`
   (`together` = commits co-appearing, `deg` = fraction of the rarer file's commits). Pure behavioural
   coupling — shared global state, parallel ownership, or an implicit protocol; statically-linked pairs are
   filtered out as expected. For ONE file's full partner list, `--cochange=FILE`.

   **Read `recur=` before you act on a row.** It is how many of the header's `sub_windows=` equal-commit-count
   slices of the window the pair actually co-changed in. `recur="1"` at any `together=` is a *single burst* —
   a refactor sprint, a rename wave — not a standing coupling, and it is the biggest source of rows that look
   alarming and are not. `ripwire <dir> --cochange --legend=compact --cochange-recur=2` drops them; the header then carries
   `min_recur=` so the shorter list is explained rather than mysterious.

   **`driver=` names the file to look at.** `conf_ab` is "of a's commits, the fraction that also touched b";
   `conf_ba` is the reverse. `driver="a"` means a is the one that never moves alone, so a is where the
   implicit dependency lives. `deg=` is just the larger of the two, and `driver=` is omitted on a tie.

   **`ripwire <dir> --cochange --legend=compact --cochange-groups`** collapses the violating pairs around the file each one
   implicates: `<group core="…" partners="3">` says "this file co-changes with three files it does not depend
   on" in one row instead of three. That is the row to act on — it names the fix target. The cover is greedy
   (`cover="greedy"`), so `groups=` is an upper bound on the minimum, not the minimum.

7. **Structural coupling** — `ripwire <dir> --deps --legend=compact`
   `<deps>` with god-files ranked by `afferent` (dependents) and each file's `instab` (1 = leaf, 0 = core).
   High-afferent, high-instability files are unstable hubs — every change there fans out. Cross with the
   step-6 surprising partners: a clone group (step 3) that *also* co-changes is a maintenance coupling — a
   fix must land in both copies.

## Planning a refactor / "this class is a god object"

When the job is *"I'm about to restructure this — where's the seam and what will it break?"*, chain three
passes into a refactor brief:

1. **Find the high-complexity cluster** — `ripwire <dir> --communities --legend=compact` (cohesive call-graph modules) or
   `ripwire <dir> --metrics --legend=compact --top-k=40` and read `ccx`/`lcom4`. `lcom4>1` is a **god object by the numbers**
   — N disjoint method clusters that want to be N types; the community/`--zoom` view names the members that
   belong together. Pick the cluster to break apart.
2. **Its blast radius** — `ripwire <dir> --impact=SYM --legend=compact` on the cluster's lead symbol → `reaches="N"` = every
   caller a signature change would touch. Large `reaches=` → stage behind a shim, don't big-bang it.
   `--affected=<files>` names the tests to keep green through the move.
3. **Its co-change seams** — `ripwire <dir> --cochange=FILE --legend=compact` on the file you're splitting → files that
   historically move with it. A `surprising="1"` partner (no static dependency) is **hidden coupling the
   refactor must preserve or explicitly cut** — fold it into the plan before you start.

4. **Pick the fix from the SHAPE, not the score** — `ripwire <dir> --quality-panel --legend=compact` (or `--metrics`) on the
   cluster, then read `humps=`/`deep=`/`locals=` as above: many shallow humps → extract each one (cheap); one
   deep tangle → guard-clause inversion then state extraction (expensive); small-and-dense → read it first,
   density is often the algorithm; `join="deep+untested"` or high fan-in → **test before you touch it**. The
   full shape → fix → precondition table, and the fix-then-prove loop that closes it
   (`--quality-delta` → `--edit-check=SYM` → `--affected`), are in **ripwire-quality-bar**.

→ **Refactor brief:** the cluster to split (with its `lcom4`/`ccx` evidence and its nesting profile), the
blast radius + test gate, the co-change partners to keep in sync, and the named fix each shape calls for. For
CI-enforcing the boundary you extract → **ripwire-layers**.

## Output

A one-page health snapshot:
- **Hotspots** — top 3 files by `score`, each with its worst function.
- **Cleanup wins** — count of dead-code candidates meeting the evidence rule (all still marked *verify*) +
  the largest clone group (biggest dedup payoff).
- **Dominant smell** — the highest-count lint rule and where it clusters.
- **Knowledge risk** — `bf="1"` files, flagging any that are also hotspots.
- **Hidden coupling** — top surprising co-change pairs + any that overlap a clone group.
- **One-line verdict** — healthy / has-debt / needs-attention, with the single highest-priority item first.

This is the structural read — it doesn't run tests or a compiler. Pair with the build's warnings and test
suite; use **ripwire-change-check** for a specific diff rather than the whole repo.

**Date the snapshot.** A health report is quoted back weeks later, long after the numbers moved. The
git-aware verbs stamp the commit they measured at — `--map-diff`/`--doc-drift` carry `at="<sha>[+dirty]"`,
`--stray-content` carries `head="<sha>"` — but most of this skill's passes (`--hotspots`, `--clones`,
`--lint`, `--dead-code`, `--cochange`, `--owners`) carry **none**. Open the snapshot with the sha you ran
at (`git rev-parse --short HEAD`) so a reader can tell a live finding from an archaeological one.

# ripwire-fresh-eyes — reference: hotspots-churn (read on demand; the recipe is in SKILL.md)

# Fresh-eyes risk review with ripwire

> Routing:
> • Any DIFF — your own, or an incoming PR you're reviewing — about to push or merge → **ripwire-change-check**.
> • **You have the measurement and now need the FIX** — which refactor a measured shape calls for, its
>   precondition, and the fix-then-prove loop → **ripwire-quality-bar**'s shape → refactor playbook.
> • Architecture health (deps metrics, layering rules, modules) → **ripwire-layers**.
> • Finding where a specific BUG lives → **ripwire-find-bug**.
> • Not sure which skill? → **ripwire-router**.
>
> **Scope it to one unfamiliar subsystem** you're about to touch, instead of the whole tree, two ways:
> point `<dir>` at the subdirectory (`ripwire src/net --hotspots`), or keep the repo root and `--exclude` the
> rest. `--dead-code=DIR` also scopes directly. This is how you turn the repo-wide sweep into a
> "what's-gnarly-in-code-I-didn't-write" read of one module.

`<dir>` = repo root. Add `--exclude=build --exclude=.git` (repeatable) to keep build artifacts out — they
otherwise show up as false clones and dead code. This composes descriptive passes into one snapshot; run the
sections your question needs.

**Inheriting this subsystem?** Check `ripwire <dir> --notes --legend=compact` first — a prior agent's pinned gotcha
(`--note-add`'d trap, flake, or invariant) is the cheapest fact you can pick up before you start reading.

## Core health passes

1. **Maintenance hotspots** — `ripwire <dir> --hotspots --legend=compact`
   ```
   <hotspots window="12mo" ranked="33"><f p="./src/main.cpp" churn="53" ccx="1365" score="72345" top="main:1306"/> …
   ```
   `score = churn × ccx` (commits × Σ cognitive complexity). Top files = where developers keep working *and*
   the code is hard — the highest-leverage places to improve. `top=` names the worst function.
   **Recent regression, not an all-time read?** `--hotspots --since="2 weeks ago"` (or `--since=HEAD~20`)
   scopes churn to commits after that point; unresolvable/absent `--since` degrades silently to all-history.
   **On C-family/C# code, discount a body carrying `ppalt=`:** its `cx=`/`ccx=`/`nest=`/`loc=`/`locals=` are
   summed over EVERY `#else`/`#ifdef` branch (deterministic, but an over-count vs any single build), so a
   high score on a `ppalt=`-heavy function can be the preprocessor fan-out, not the logic — read `ppalt=`
   before calling a row the worst in the file.

1a. **"What changed recently / who touched this / what is moving here?"** — `ripwire <dir> --rank-by=churn-decay --legend=compact`
   ```
   <recent n="40" of="1857" merge_bombs_skipped="5"><rc p="src/graph.h" w="0.91" age="2"/> …
   ```
   The HISTORY question, not the working-tree one: `--situ` answers what *you* changed and have not
   committed, this answers what the repository has been moving, newest-and-heaviest first.
   **Scope it to a directory: `ripwire <dir> --rank-by=churn-decay --in=DIR`** (root-relative, and it must
   exist under the root) — a second `<recent scope="DIR" …>` block follows the global
   one and the symbol map collapses to a counted stub, so the answer is the window rather than a whole-repo
   map. `merge_bombs_skipped="N"` is the disclosure that N commits touching more than 100 indexed files
   were left out of the weighting — if the commit you are hunting is a giant rename, it is in that N and
   not in the rows. `--since=REV|DATE` bounds the window; `--limit/--offset` page the scoped block.
   `ripwire <dir> --help-task="what changed recently in DIR" --legend=compact` routes here on its own.

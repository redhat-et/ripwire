---
name: ripwire-navigate
description: >
  You can NAME the symbol: who calls it, what it calls, the path from A to B, its full body, or an
  exact literal/regex match. 'Safe to change or rename X — what breaks downstream?' = the transitive
  blast radius, not 1-hop callers. Three or more symbols → --connect. Run the one verb that fits, then
  stop.
allowed-tools: Bash, Read
---

# Navigate with ripwire

> Routing: no symbol yet → **ripwire-orient** · a symptom, culprit unknown → **ripwire-find-bug** · a question that
> COMBINES conditions (cx + fan-in + file + reachability) → **ripwire-graph-query** · "is this diff safe to merge"
> → **ripwire-change-check**.

`<dir>` = the repo or subsystem; calls are warm after the first parse. Split checkout: pass every root
(`ripwire dir1 dir2 --impact=SYM`).

## The decision: name it in backticks and ask `--for` — it routes itself

Who calls `X`, where it is used, what breaks if it changes (any depth): `ripwire <dir> --for="<question, X in
backticks>"` answers with `--callers` / `--uses` / `--impact`; `warn="1"` = a likely miss, the ranked page rides along.

| Anything else | Run |
|---|---|
| what X calls | `ripwire <dir> --callees=SYM --legend=compact` |
| X's full body + its callees' signatures | `ripwire <dir> --expand=SYM --legend=compact` |
| an exact literal: error text, config key, emitted string | `ripwire <dir> --grep=STR --legend=compact` (literal + enclosing symbol) |
| a regex, or a code shape | `ripwire <dir> --regex=PAT --legend=compact` · `ripwire <dir> --pattern='foo($X, ...)' --legend=compact` |
| how A reaches B | `ripwire <dir> --path=SRC,DST --legend=compact` |
| how three or more symbols relate | `ripwire <dir> --connect=A,B,C --legend=compact` |
| a closed claim: does A call B, is X unused | `ripwire <dir> --verify='calls(A,B)' --legend=compact` |
| a variable's story inside one function | `--slice=SYM:VAR` (`--slice-flow=back\|fwd\|both` for where its value flows) |
| you have a FILE:LINE, not a name | `--at=FILE:LINE`, or `@FILE:LINE` as the operand of any verb above |

## Stop rule and trust

Run the one verb that fits, then stop; read the source only for the rows that matter. `counts_floor="1"` means
the count is a floor, not a total. `amb="K"` on a symbol means K of its calls resolved by name to several
definitions — read the source when which target matters. Name-based edges miss dynamic dispatch, callbacks and
macros: a high-rank symbol with no edges can be a dispatch hub, not a leaf.

## Reference files

| You need | Read |
|---|---|
| when to keep or drop the legend; the full 1-hop vs transitive guidance; slices; flows; `--at` | `blast-radius.md` |
| every trace/locate verb (`--around`, `--defs`, `--uses=Owner.field`, `--match`, `--verify` verdicts, `amb=`, SCIP) | `trace.md` |
| a deep-dive on one symbol before editing; a struct whose bytes cross a boundary (`--layout`); `--query` vs `--for` | `deep-dive.md` |

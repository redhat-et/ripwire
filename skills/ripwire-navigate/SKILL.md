---
name: ripwire-navigate
description: >
  A symbol you can NAME: who calls it, what it calls, the path from A to B, its full body, or an exact
  literal/regex match. 'Safe to change or rename X — what breaks downstream?' = the transitive blast
  radius, not 1-hop callers. Three or more symbols → --connect. Run the one verb that fits, then stop.
allowed-tools: Bash, Read
---

# Navigate with ripwire

> Routing: no symbol yet → **ripwire-orient** · a symptom, culprit unknown → **ripwire-find-bug** · a question that
> COMBINES conditions (cx + fan-in + file + reachability) → **ripwire-graph-query** · "is this diff safe to merge" →
> **ripwire-change-check**.

Split checkout: pass every root (`ripwire dir1 dir2 --impact=SYM`).

## Name it in backticks and ask `--for` — it routes itself

Who calls `X`, where it is used, what breaks if it changes (any depth): `ripwire <dir> --for="<question, X in
backticks>"` answers with `--callers` / `--uses` / `--impact`; `warn="1"` = a likely miss, the ranked page rides along;
`--no-verb-route` = the ranked answer instead.

| Anything else | Run |
|---|---|
| what X calls | `ripwire <dir> --callees=SYM --legend=compact` |
| X's full body + its callees' signatures | `ripwire <dir> --expand=SYM` |
| an exact literal: error text, config key, emitted string | `ripwire <dir> --grep=STR --legend=compact` (literal + enclosing symbol) |
| a regex, or a code shape | `ripwire <dir> --regex=PAT --legend=compact` · `ripwire <dir> --pattern='foo($X, ...)'` |
| how A reaches B | `ripwire <dir> --path=SRC,DST --legend=compact` |
| how three or more symbols relate | `ripwire <dir> --connect=A,B,C` |
| a closed claim: does A call B, is X unused | `ripwire <dir> --verify='calls(A,B)'` |
| a variable's story inside one function | `--slice=SYM:VAR` (`--slice-flow=back\|fwd\|both` for where its value flows) |
| a FILE:LINE, not a name | `--at=FILE:LINE`, or `@FILE:LINE` as the operand of any verb above |

## Stop rule and trust

Run the one verb that fits, then stop; read source only for the rows that matter. `counts_floor="1"` = a floor, not a
total. `amb="K"` = K calls resolved by name to several definitions — read the source when the target matters.
Name-based edges miss dynamic dispatch, callbacks and macros: a high-rank symbol with no edges can be a dispatch hub.

## Reference files

`blast-radius.md` 1-hop vs transitive, keeping or dropping the legend, slices, flows, `--at` · `trace.md` every
trace/locate verb (`--around`, `--defs`, `--uses=Owner.field`, `--match`, `--verify` verdicts, `amb=`, SCIP) ·
`deep-dive.md` one symbol before editing, `--layout` for bytes crossing a boundary, `--query` vs `--for`.

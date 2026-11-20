### Changed — `--legend-have=` takes legend TIERS, so the handshake pays for itself in about ten calls instead of about 130

`--legend-have=` lets a CLI caller say which legend definitions are already in its context, so answers stop re-sending them. The only holding it could name was the whole dictionary: 131,571 B for 1,002 B saved per call, **131 calls to repay** (453 answers of 12 verbs on five corpora). Every guidance site therefore told a short session to pass nothing.

The dictionary is now served in tiers, each with its own version:

- `ripwire --legend-dict=core` — 13 definitions, **1,512 B**: the six ref-posture readings, the reading of `have=`, and the six terms that cross verbs (`root=`, `next=`, `counts_floor=`, the two resolver gauges, `graph_unindexed=`, `est_tokens=`).
- `ripwire --legend-dict=KEY` (a schema key: `callers`, `impact`, `grep`, …) — the core plus that verb's pack, the definitions at least a third of its measured answers carried. 51 schemas have a pack; a schema that was never measured answers the core with `census=0`.
- `ripwire --legend-dict` — every line, as before.

Line 1 of a tier carries `have=<16 hex>`, the FNV-1a 64 of exactly the `entries=` lines after it. `--legend-have=` takes one or several of those values, comma-joined.

**An answer never claims a definition its reader does not hold.** A definition in a tier the caller named is left out; one in no named tier stays in that answer, in a comment after the rows. `<about legend="ref" have="core|core+KEY…|full" …/>` says what was assumed. Before this the CLI served a caller as if it held everything, which was honest only because "everything" was the one thing a caller could say.

Measured on the same 453 answers, on the built binary:

| holding | bytes to read | saved per call | repays in |
| --- | ---: | ---: | ---: |
| whole dictionary | 131,710 | 991.8 | 133 calls |
| core | 1,512 | 148.6 | **11 calls** (9 over the 388 answers that are not `--for`; 9 to 17 by corpus) |
| core + the verb's own pack | +415 to +2,300 for the eleven everyday verbs | 849.8 (85.7 % of the whole dictionary's saving) | a pack repays in 1.3 to 2.0 calls of its verb |

This is **not** "single-digit": it is 11 on the registered population and 17 on koa alone.

Refusals: an empty value (unchanged); **any value that is no tier of this binary, even beside a valid one** — the message names the value, the tiers the rest of the list did name, and `ripwire --legend-dict=core` with its real size, where it used to prescribe the whole dictionary; `--mcp`/`--listen`/`--lsp`; `--legend=full`. A valid pack passed on another schema's answer is honoured, never refused.

An answer served inline under the handshake now says so on stderr, and which of the two reasons applies: `not-applicable` (the dictionary does not reduce that legend — every `--for` answer, 65 of 65) or `inline-kept` (the reduced answer would not be shorter). Stdout is unchanged in both.

Also new: `--legend-dict=tiers` (every tier: name, `have=`, entries, bytes, census) and `--legend-dict=index` (every entry by what it defines). The MCP stdio session is unchanged and carries no `have=`.

Guidance: `--help`, the empty-value refusal, `ripwire wrap`'s primer line and the `ripwire-router` and `ripwire-mcp` skills now teach the core read and its measured cost.

Gate: `test/legendtiercheck.sh` (BAND K (tiers), docs/EVALS.md amendment 11) — held-or-carried at bar 0 over every cell and holding, tier identity, the refusals, a pack costs at most 3x its per-call gain, and the repayment pin (core at most 1,536 B, `ceil(B/S)` at most 12, no core term under 25 % of the cells), with twelve registered mutants and three single-arm ones re-run on every invocation. `src/legendpacks.h` is a build product of `bench/legendtier/census.tsv`.

Versions: the legend dictionary's release pair is stated once in the `versions` entry (`dictv=cd0a012a40de1479 entries=1294`); docs/COMMANDS.md and the newest showcase capture record it.

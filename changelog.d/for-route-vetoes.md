### Fixed — `--for` no longer routes a call-path question or a quoted-message question to the wrong verb

The bare `--for` route (a backticked symbol plus a call-graph question → `--callers`, `--uses` or `--impact`) sent two
kinds of question to a verb that answers something else:

- **A call path or call chain** ("what is the call chain from `A` to `B`", "which call path from `main` triggers `X`",
  "the path from `A` to `B`"). These went to `--callers` or `--impact` on their "call" or "trace" word. A path is neither
  1-hop callers nor a blast radius, so such a question is now never routed.
- **A double-quoted literal** outside every backtick span ("running `X` prints "usage: …"; where is that message built?").
  These were routed by the symbol beside the literal, but the answer needs to find where the literal is built first. Such a
  question is now never routed. Straight and curly quotes both count. Quotes inside a backtick span are code and do not
  count, and neither does an apostrophe.

A question that is not routed gets the ranked `--for` answer, byte for byte, in the CLI, MCP `for` and the batch sub-verb.
Every other question routes exactly as before. A bare "blast radius" question still routes to `--uses`: a rule that sends it
to `--impact` is built but HELD (off) until `--impact` covers every `--uses` row and a fresh confirmation set measures it.

Lane RT3 (`results/RT3_VETOES_1119`). Measured on the spent development sets: the two vetoes match no question the old rule
routed. On a held-out set of 86 questions, they change 3 call-chain routes: all 3 stay complete, and no other answer changes. Gates:
`test/forverbroutecheck.sh` (arms 30–35) and `test/mcpforroutecheck.sh` (t1–t3).

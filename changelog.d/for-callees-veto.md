### Fixed — a `--for` question about what X calls is no longer routed to `--callers`

A bare `--for` that asks what a named symbol calls ("what does `X` call", "which helpers does `X` call", "callees of `X`",
"what `X` calls") used to be routed to `--callers` by its "call" word, which answers the opposite question. Such a question
is now never routed: its answer is the ranked `--for` answer, byte for byte, in the CLI, MCP `for` and the batch sub-verb.
Who-calls phrasing ("who calls `X`", "what calls `X`", "callers of `X`", "`X` is called by") still routes to `--callers`.
Lane RT2; `test/forverbroutecheck.sh` (arms 26–29), `test/mcpforroutecheck.sh` (v1–v2).

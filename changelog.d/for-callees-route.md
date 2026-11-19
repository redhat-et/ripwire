### Added — "what does X call" is answered by `--callees`, routed

A bare `--for` whose text names a symbol in backticks and asks what it calls ("what does `X` call", "callees of `X`", "which
functions does `X` call") is answered by `--callees`, routed like the other call-graph questions, in MCP `for` and its batch
sub-verb too. Before this, such a question was sent to `--callers` by its "call" word. When `X`'s body calls a name the repo
defines but no callee row lists (a call inside a macro invocation's arguments, a call through a local the resolver cannot
type), the route says `warn="1" why="body-gap:N:NAME"` and the first `--for` page rides along. Lane RT2;
`test/forverbroutecheck.sh` (arms 26–29), `test/mcpforroutecheck.sh`. Its single confirmation is in
`results/RT2_ROUTE_1118/READOUT.md`.

### Added — a `--for` question that names its symbol is answered by the verb it asks for, routed

A bare `--for` whose text names a symbol in backticks and asks who calls it, where it is used, what breaks if it changes or
its callers N hops up is answered by `--callers`, `--uses` or `--impact`. The answer says so first:
`<route from="for" kind= verb= complete="not-proven" next=>`, where `next=` (`--no-verb-route`) is the ranked `--for` answer.
Files that name the symbol only as text (a macro alias, a string, a shell script, a call the resolver declined) follow as
`<text_only>` rows. When the evidence says the verb is likely to miss something a text list cannot show (a macro caller,
a callback slot, twin definitions, a value hop, a cut list), the route says `warn="1" why=` and the first `--for` page
rides inside the answer. An absent `warn=` means no evidence was found, never that the answer is complete. Flags that shape
the `--for` answer (`--page-bytes`, a budget, `--json`, several roots) keep it unrouted. MCP `for` routes by the same rule and
carries the same rows (its warned answer carries MCP's own `for` answer); its `no_verb_route` argument is the opt-out.

Lanes RT1 (`1ede0078b`) and RT2 (`lane/rt2-route`); `test/forverbroutecheck.sh`, `test/mcpforroutecheck.sh`. Measured on held-out gold:
`results/RT2_ROUTE_1118/READOUT.md`.

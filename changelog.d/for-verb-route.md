### Added — a `--for` question that names its symbol is answered by the verb it asks for, routed

A bare `--for` whose text names a symbol in backticks and asks who calls it, where it is used, what breaks if it changes or
its callers N hops up is answered by `--callers`, `--uses` or `--impact`. The answer says so first:
`<route from="for" kind= verb= complete="not-proven" next=>`, where `next=` (`--no-verb-route`) is the ranked `--for` answer.
Files that name the symbol only as text (a macro alias, a string, a shell script, a call the resolver declined) follow as
`<text_only>` rows. When the evidence says the verb is likely to miss something a text list cannot show (a macro caller,
a callback slot, twin definitions, a value hop, a cut list), the route says `warn="1" why=` and the first `--for` page
rides inside the answer. An absent `warn=` means no evidence was found, never that the answer is complete. Flags that shape
the `--for` answer (`--page-bytes`, a budget, `--json`, several roots) keep it unrouted; MCP `for` is unchanged.

Lanes RT1 (`1ede0078b`) and RT2 (`lane/rt2-route`); `test/forverbroutecheck.sh`. Measured on held-out gold:
`results/RT2_ROUTE_1118/READOUT.md`.

### Added — page 1 of a who-calls `--for` answer ends early when its callers block proves itself complete

When the default page 1 of an unrouted `--for` answer leads with `<callers by="subject">` and that block shows every caller it
counts (`shown=` equals `total=`, nothing capped) and no evidence of a miss is found, the page ends right after the block:
`early="proven"`, `withheld_bytes=` and `deferred=` say what it leaves out, and `next=` is the full page 1. Lane RT2;
`test/forverbroutecheck.sh` (ES arms). Its confirmation is pending on a fresh gold set.

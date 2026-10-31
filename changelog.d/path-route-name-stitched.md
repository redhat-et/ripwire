### Fixed — a `--path` chain stitched from calls bound by name alone is no longer printed as the plain answer

`--path` (and MCP `path_between`, and the `<graph_verb>` block of a `--for` path subject) printed the shortest chain the search
found, `reachable="1"`, even when several of its hops were `via="name"` calls whose receiver nothing proves. On Django,
`--path=QuerySet.__iter__,SQLCompiler.execute_sql` answered a 12-hop chain with 5 such hops through the prefetch code, and
`--path=Model.save,SQLInsertCompiler.execute_sql` a 5-hop chain through `QuerySet.aggregate`: neither is how the call gets there,
and nothing on the answer said so. One shared verdict now judges the chain a single-pair answer prints:

- 2 or more by-name hops, and a chain over proven call edges only exists between the same definitions: that proven chain is
  printed instead, with `route_hedged="proven-preferred" route_len= route_by_name=` describing the shorter by-name one. A by-name hop, a markdown link, a link to a missing anchor and one arm of a resolver split are not proven edges for this search; the one-implementor edge (`via="impl"`) is, and its row says so.
- 2 or more by-name hops and no proven chain: printed as before, hedged on the root with
  `route_hedged="name-stitched" route_by_name="K" route_cands="P"` (K by-name hops, P the product of their same-named candidates).
- 4 or more by-name hops and `route_cands` of 64 or more (and no proven chain): refused as the answer (3 is only hedged: on CPython, `--path=asyncio.run,Handle._run` is a true chain with 3 by-name hops, and a true TypeScript or Go dependency-injection chain through interfaces carries 2 to 16 candidates, so it is hedged and printed). The root says
  `reachable="0" hops="0" route_hedged="not-proven" route_len="N"`, no hop rows print, and `next=` follows `from=`'s callees (quoted, so a path with a space pastes into a shell). The
  legend says reachable=0 here means "not proven", never "no route". `route_cands` counts in-repo same-named definitions along the route; a by-name call on a builtin or external receiver is not counted, so a low count is no proof.
- 4 or more by-name hops below that count: printed with `route_hedged="unlikely"` on the root (the chain is probably not the real route, said on the answer itself, not only in the legend); `next=` names the step that verifies it.

A chain with at most one by-name hop prints exactly as before. An answer listing several definition pairs hedges its first pair's chain (`route_hedged="name-stitched"`, or `"unlikely"` from 4 by-name hops), and is never refused. The compact `path` legend now reads "reachable=0 hops=0 when none shown", so it no longer contradicts a refusal.

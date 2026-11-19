### Fixed — a windowed routed `--for` answer now continues itself

When a bare `--for` question is routed to `--uses` or `--impact` and that verb windows its rows (`has_more="1"`
`next_offset=K`), the answer's root `next=` used to name another lens (`--safe-delete=…`), or nothing at all. And
`--for=Q --offset=K` answered with a `--for` file page instead of the verb's next window. Now the routed root's `next=` is
`--for=Q --offset=K`. That call routes the same question to the verb's window at K: it carries the `<route>` element (its
`verb=` spells the offset) and the verb's rows at `--offset=K`, byte for byte. It carries no fold, no key body and no
carried page, because those belong to the first window. MCP `for` with `offset=` (and no `limit=`) answers the same way.

Not changed:
- An unwindowed routed answer keeps the verb's own `next=`.
- An unrouted question with `--offset` is the `--for` file page, as before.
- `--no-verb-route --offset` is never routed.

Measured on the spent development sets (120 routed answers): the only bytes that move are the root `next=` of the windowed
answers. Lane RT3-F1. Gates: `test/forverbroutecheck.sh` (arms 36–40) and `test/mcpforroutecheck.sh` (t4).

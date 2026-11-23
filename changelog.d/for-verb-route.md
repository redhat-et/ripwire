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
It was measured on held-out gold questions before it shipped. Commit `1ede0078b`; gates `test/forverbroutecheck.sh` and
`test/mcpforroutecheck.sh`.

**Questions that are never routed.** A question that is not routed gets the ranked `--for` answer, byte for byte, in the CLI,
MCP `for` and the batch sub-verb:

- **What X calls** ("what does `X` call", "which helpers does `X` call", "callees of `X`", "what `X` calls"). Its "call"
  word used to route it to `--callers`, which answers the opposite question. Who-calls phrasing ("who calls `X`", "what calls
  `X`", "callers of `X`", "`X` is called by") still routes to `--callers`.
- **A call path or call chain** ("what is the call chain from `A` to `B`", "which call path from `main` triggers `X`",
  "the path from `A` to `B`"). These went to `--callers` or `--impact` on their "call" or "trace" word. A path is neither
  1-hop callers nor a blast radius.
- **A double-quoted literal** outside every backtick span ("running `X` prints "usage: …"; where is that message built?").
  These were routed by the symbol beside the literal, but the answer needs to find where the literal is built first. Straight
  and curly quotes both count. Quotes inside a backtick span are code and do not count, and neither does an apostrophe.

Every other question routes exactly as before. A bare "blast radius" question still routes to `--uses`: a rule that sends it
to `--impact` is built but HELD (off) until `--impact` covers every `--uses` row and a fresh confirmation set measures it.
Measured on the spent development sets, the path and literal vetoes match no question the old rule routed; on a held-out set
of 86 questions they change 3 call-chain routes: all 3 stay complete, and no other answer changes.

**A windowed routed answer continues itself.** When the routed `--uses` or `--impact` windows its rows (`has_more="1"`
`next_offset=K`), the answer's root `next=` used to name another lens (`--safe-delete=…`), or nothing at all, and
`--for=Q --offset=K` answered with a `--for` file page instead of the verb's next window. Now the routed root's `next=` is
`--for=Q --offset=K`. That call routes the same question to the verb's window at K: it carries the `<route>` element (its
`verb=` spells the offset) and the verb's rows at `--offset=K`, byte for byte. It carries no fold, no key body and no
carried page, because those belong to the first window. MCP `for` with `offset=` (and no `limit=`) answers the same way.
An unwindowed routed answer keeps the verb's own `next=`; an unrouted question with `--offset` is the `--for` file page, as
before; `--no-verb-route --offset` is never routed. Measured on the spent development sets (120 routed answers): the only
bytes that move are the root `next=` of the windowed answers.

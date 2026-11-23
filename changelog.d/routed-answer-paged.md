### Fixed — a routed `--for` answer, CLI and MCP, is held to the page: it no longer prints a full page on top of the verb's rows

A bare `--for` that names a symbol and asks who calls it, where it is used or what breaks is answered by `--callers` / `--uses` / `--impact`, and when the evidence says the verb may be partial (`<route warn="1">`) the first `--for` page rides along. Neither part was held to the page size: the verb printed its own window and the carried page was a full 12,000 B page on top of it. On 89 development questions from 11 open-source repositories the one warned routed answer printed 30,369 bytes where the same question unrouted prints 17,735, and in a live agent session the client stored that answer in a file and showed the agent a 2 KB preview of it.

A routed answer now counts against the page (12,000 B) the way a `--for` page does: every byte from the root on except the legends and the key-body group.

- **The carried page is cut at what the verb's rows left of the page**, by the pager's own rule. Its root says `page="1" pages=N`, `continued=` / `deferred=`, and `next="--for='…' --page-bytes=S:2"`, which is page 2 of the same `--for` answer at that size. A `--for` answer that fits what is left is carried whole, as before.
- **When that would leave the page under 6,000 B, the verb's rows are windowed first** so the page keeps at least 6,000. The verb's root then says `shown= total= has_more="1" next_offset=K` and its `next=` is `--for='…' --offset=K`, the call that already continued a windowed routed answer.
- **A routed answer with no carried page is windowed the same way** when its rows alone are over the page, and so is each `--offset=K` continuation.
- **A question whose verb part cannot be cut to fit even at one row is not routed**: the `--for` answer, byte for byte.

Nothing is dropped: the verb's windows rebuild its unwindowed rows in order, and the carried page with the pages its `next=` names rebuilds `--page-bytes=0`. An answer that already fitted is byte-identical. A spelled `--page-bytes`, the default 12000 included, still never routes: the carried page's `next=` is a page of the `--for` answer because of that. Measured on the same 89 questions (bare default, page 1): 2 questions route. The warned one goes from 30,369 to 20,727 bytes (86 `--uses` rows on page 1 become 32, the carried page is page 1 of 6 at 6,122 B instead of page 1 of 3 at 12,000 B) and still names both gold files; the other already fitted and is byte-identical, as are the 87 unrouted answers. Gate: `test/forroutepagecheck.sh`.

**MCP `for`.** A warned routed MCP answer carries MCP's own `for` bundle as its last child, and it was never held to anything: on the gate's fixtures it printed up to 48,582 bytes. It now counts against the same 12,000 B page, the same way, and what does not fit is one MCP call away and lossless:

- **the verb's rows are windowed** when the page needs the room: the root says `shown= total= has_more="1" next_offset=K`, and `for` with `offset=K` continues them (each window held to the page too);
- **the carried page is MCP's whole `for` bundle when it fits what the verb's rows left**, as before; **otherwise it is MCP's file page of the same ranking, cut to fit**: a `<files>` root with `limit=L offset="0"`, and `has_more="1" next_offset=K` when it is cut — `for` with `limit=L offset=K` continues it. MCP has no byte page of the bundle, and `limit`/`offset` is the paging contract its `for` already answers; the file page names one row per file, not the bundle's signatures;
- **a question whose answer cannot be held is not routed**: MCP's `for` answer, as for any unrouted question.

An MCP answer that already fitted is byte-identical (`test/mcpforroutepagecheck.sh`).

### Fixed — a routed MCP `for` answer is held to the page, continued through MCP's own paging arguments

MCP `for` answers a question that names its symbol and asks who calls it, where it is used or what breaks with the CLI's routed answer, and a warned one carries MCP's own `for` bundle as its last child. Unlike the CLI's (held to the page since the routed-answer paging change), the MCP answer was never held to anything: on the gate's fixtures it printed up to 48,582 bytes.

It now counts against the same 12,000 B page, the same way (every byte from the root on except the legends and the key-body group), and what does not fit is one MCP call away and lossless:

- **the verb's rows are windowed** when the page needs the room: the root says `shown= total= has_more="1" next_offset=K`, and `for` with `offset=K` continues them (each window held to the page too);
- **the carried page is MCP's whole `for` bundle when it fits what the verb's rows left**, as before; **otherwise it is MCP's file page of the same ranking, cut to fit**: a `<files>` root with `limit=L offset="0"`, and `has_more="1" next_offset=K` when it is cut — `for` with `limit=L offset=K` continues it. MCP has no byte page of the bundle, and `limit`/`offset` is the paging contract its `for` already answers; the file page names one row per file, not the bundle's signatures;
- **a question whose answer cannot be held is not routed**: MCP's `for` answer, as for any unrouted question.

An answer that already fitted is byte-identical (`test/mcpforroutepagecheck.sh` (N3)).

### Fixed — an MCP answer in the session legend posture names the resource that recovers its definitions

Over MCP, the session's first answer defines its attributes inline and later answers end with `<about legend="ref" …/>`. That pointer said `dict="ripwire --legend-dict"`, a CLI command, so an agent whose client had dropped the first answer (Claude Code compaction, or the API's `clear_tool_uses` context editing) was pointed at a command it may not be able to run. The server cannot see either kind of clearing. Over MCP the pointer now reads `dict="ripwire://legend-dict/full"`, the resource that serves every definition. No attribute is added, so no verb dialect changes. The cost is 5 bytes per ref answer (measured: 1,441 to 1,446 B and 807 to 812 B on two `impact`/`uses` answers). The CLI handshake (`--legend-have=`) still points at `ripwire --legend-dict`.

`test/mcplegendrecoverycheck.sh`: on the parent, 2 of its 5 arms fail; on this change all 5 pass.

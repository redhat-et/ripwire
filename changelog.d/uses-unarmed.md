### Fixed — a zero or "not found" that means "not indexed" now says so (`--uses`, `--defs` and the other selector refusals)

Four answers made a claim the index could not back:

- `--uses` on a definition that is read or named more than it is called (a Go or Rust struct, a C global table) printed a bare `count="0"` in a language whose read, write and type-mention sites the index never captures (only C++, ObjC and Python have that capture). Examples are fzf `Options`, terraform `FmtCommand`, mdbook `CmdRenderer`, tmux `cmd_table` and htop `Process_class`. The root now carries `unindexed_roles="read,write,type"`, and its legend says the count lists only call, value, import and extends sites, so a zero there is not a count of uses. A C-family header definition gets the same attribute when the corpus holds C files. This is the same rule `countFloorNext` already used.
- A bare member name in a language with no field capture answered `found="0" near=<a type>` on the CLI and `external="1"` ("no definition in the indexed tree") over MCP. hono's `routes` is one: it is a class field at src/hono-base.ts:125. When a lexical member declaration of that name exists in an unserved owner's body, both surfaces now refuse with the sentence the qualified form (`Hono.routes`) already printed, and they name the owner and the line.
- A selector refusal (`--defs`, `--callers`, MCP `find_symbol`, …) for an object-like `#define` on the C++ parse path said "not found … did you mean". tmux `TMUX_SOCK` is one. The refusal now names the `#define` line and says that path does not index object-like macros.
- When a definition was lost to a degraded parse, the not-found note named the first degraded file that mentioned the name, in path order. tmux `window` got alerts.c, while `struct window {` is at tmux.h:1441. The note now names the lexical definition line (whereis' own reading; a forward declaration does not count).

`test/usesunarmedcheck.sh` pins all four on the CLI and on MCP. Its positive controls are an armed C++ class, a Python class, and C, C++ and Python fields with real captures; these keep answering with no disclosure. Each negative arm counts its premise and fails on zero.

Found by the Fable ideas verify pass (USES-UNARMED-DISCLOSE), the Fable answer audit (USES-FIELD-EXTERNAL) and the Opus audit verify (TMUX-STRUCT-WINDOW).

The new `unindexed_roles=` compact legend term moves the session legend dictionary to `dictv=17c3bdf6123096e2 entries=1061` (docs/COMMANDS.md and the showcase capture are re-recorded).

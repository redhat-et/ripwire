# ripwire-router — reference: scope (read on demand; the recipe is in SKILL.md)

## Cross-cutting disciplines (fire ALONGSIDE a moment skill, not instead)

- **ripwire-orient / `map-before-you-read.md`** — the map-before-you-read token+accuracy discipline for *any* read, at *any* moment (a companion file since 2026-09-07; it was the standalone `efficient` skill).
- **ripwire-quality-bar** — the measure-what-you-made-worse convergence loop, at *every* "I think I'm done".
- **ripwire-reuse-first** — reuse-before-reinvent, at *every* new symbol.

These aren't a "moment" you land in; they're reflexes you carry into every moment.

## Wrong tool for the job

`ripwire --help` (its **Languages** line) is the source of truth for what gets parsed; it grows, so trust it over any copy.
Today: C-family (C, C++, ObjC/ObjC++, Metal, CUDA), Python, TypeScript, JavaScript, Java, Kotlin, C#, Go, Rust, Swift,
Ruby, PHP, Lua, Elixir, Dart, Clojure, GDScript, Bash; Protocol Buffers (.proto definitions); JSON/TOML/YAML (config keys); Markdown (headings are sections).
A repo in a language not on that line (Haskell, OCaml, Scala, Zig, ...) gets an empty map whose header names the skipped
extensions (`unindexed=`) — don't mistake that for "nothing here"; reach for plain `rg` + reads instead. Supported
languages are not "thin": try the map first. And ripwire maps *structure*, not build/link state — a
build failure or a linker error is the compiler's/linker's question, not ripwire's; it can still tell you
*where* the broken symbol lives (`--grep`/`--callers`), just not why the toolchain rejected it.

## Reference skills (consulted, never "entered")

**ripwire-layers** (architecture-health / `--arch` CI gate), **ripwire-graph-query** (custom graph queries),
**ripwire-mcp** (run ripwire as an MCP server). `--doctor` (setup-health row above) is diagnostic, not a
moment skill. `--eval` / `--eval-retrieval` / `--eval-mined` are
maintainer self-eval harnesses (not an agent moment) — `--eval-mined=FILE` scores ranker recall against
real session-mined (query, gold-files) pairs from `bench/mine_traces.py`. The
detail-ladder / token-squeeze (`--compress`) material
lives inside **ripwire-orient**'s companion file (`skills/ripwire-orient/compress-ladder.md`) now — it's not a standalone
moment. You don't recognize "the graph-query moment" — reach for these when a moment skill points you at
them.

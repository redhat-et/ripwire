### Fixed — the router skill no longer tells agents that PHP, Kotlin or Elixir are unsupported (#521, thanks @gucliti)

`skills/ripwire-router/SKILL.md` said ripwire parses 15 languages "— nothing else" and named PHP and Kotlin as examples of
languages that get a thin or empty map. `ripwire --help` lists 26, so an agent that read the skill on a PHP, Kotlin, Lua,
Elixir, Dart, GDScript, TOML, YAML or Markdown repo was sent to plain `rg` exactly where ripwire works. @gucliti measured it
on an Elixir/OTP project: `--skipped` showed all 126 `.ex` files indexed (3185 symbols), `--for` returned ranked symbols
with correct call edges, and `--recall` ranked the repo's ADR docs by section.

The "Wrong tool for the job" paragraph now names `--help`'s Languages line as the source of truth, lists the families
compactly, and uses languages that really are unindexed as its examples (Haskell, OCaml, Scala, Zig); the map's `unindexed=`
header names the skipped extensions. `docs/LOCALS_INDEXING.md` lost a stale "all 14 languages" count.

New gate `test/skilllangdriftcheck.sh` parses the Languages line of `--help` and fails if a skill or doc calls a listed
language unsupported or restates a closed list ("nothing else") that omits one. It is red on the old router paragraph and
green on this one, and a fake doc that calls Haskell, OCaml, Scala and Zig unsupported passes. Limit: it reads prose
patterns ("another language (...)", "unsupported language ...", "nothing else" after a list), not every possible wording.

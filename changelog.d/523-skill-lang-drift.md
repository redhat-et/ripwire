### Fixed — the router skill no longer tells agents that PHP, Kotlin or Elixir are unsupported, and `--help` lists Clojure (#523, thanks @gucliti)

Fixes #521, reported by @gucliti. `skills/ripwire-router/SKILL.md` said ripwire parses 15 languages "— nothing else" and
named PHP and Kotlin as examples of languages that get a thin or empty map. `ripwire --help` lists 27, so an agent that
read the skill on a PHP, Kotlin, Lua, Elixir, Dart, Clojure, GDScript, TOML, YAML or Markdown repo was sent to plain `rg`
exactly where ripwire works. @gucliti measured it on an Elixir/OTP project: `--skipped` showed all 126 `.ex` files
indexed (3185 symbols), `--for` returned ranked symbols with correct call edges, and `--recall` ranked the repo's ADR docs
by section.

The "Wrong tool for the job" paragraph now names `--help`'s Languages line as the source of truth, lists the families
compactly, and uses languages that really are unindexed as its examples (Haskell, OCaml, Scala, Zig); the map's `unindexed=`
header names the skipped extensions. `docs/LOCALS_INDEXING.md` lost a stale "all 14 languages" count. `--help` itself had
drifted: Clojure (`.clj/.cljs/.cljc/.bb`) has been indexed since September but was missing from its Languages line. It is
listed now.

New gate `test/skilllangdriftcheck.sh` checks both directions. It fails if `--help`'s Languages line and the crawler's
extension table (`src/ingest_crawl.h`) disagree on a language. It also fails if a skill, doc or hook calls a listed
language unsupported ("another language (PHP, ...)", "PHP is not supported", "no PHP support", "ripwire does not yet
parse PHP", "won't index", "Unsupported: ...") or restates a closed list ("nothing else", "and nothing more", "supports
only ...") that omits one. A closed list is judged on its own run of names, not on the paragraph around it. It is red on
the old router paragraph and on eleven reworded claims, and green on the new paragraph. A fake doc that calls Haskell,
OCaml, Scala and Zig unsupported passes, and so do ordinary sentences such as "files in an unsupported language are
counted in unindexed=". A per-feature sentence that only looks like a claim ("Per-language rules cover C++, Python, Go,
Rust; no other language has the gate") is exempted with `<!-- skilllangdrift: ok -->` on its line. Limit: it reads
these prose patterns, not every possible wording; "X and Y only." and "for a PHP repo, use rg" still pass.

# ripwire-router — reference: defaults (read on demand; the recipe is in SKILL.md)

## You are not in a "moment" — you are about to reach for a default

The table above assumes you recognized a moment. The most expensive case is the one where you did not:
you simply went for `Read`, `Grep`, or `Glob` because they are always there. That reflex needs no
recognition and no skill load, which is exactly why it wins by default and why it costs the most.

Match the **default you were about to use**, not a moment:

| About to… | Reach for instead |
|---|---|
| `Read` a whole file to understand one function | `--expand=SYM` — that symbol's body + its callees' signatures, no ride-along map (orient ONCE per session with `ripwire <dir>`, then look up lean). The file is not the unit of an answer. |
| `Read` several files to learn how something works | `--pack-task="<task>"` — ranking + bodies + callers + tests in ONE budgeted call |
| `Grep`/`rg` a symbol name across the tree | `--for="theExactName"` (name-exact routing, recall@1 ~99%) · `--uses=SYM` for every read/write/import site |
| `Grep` a concept ("where do we retry") | `--for="<the concept in words>"` — matches doc-comments and bodies, not just identifiers |
| `Glob` for candidate files by name | `--for=` ranks by what the code DOES; a glob only knows paths |
| paste a stack trace and hand-pick frames | `--from-trace=FILE` (`-` = stdin) — verbatim, ranked innermost-first |
| `git diff` / `git log` to judge a change | `--situ` (blast radius + tests) · `--rank-by=churn` |

The discipline behind this row set is **ripwire-orient**'s companion `map-before-you-read.md`; it is worth entering even mid-task, because
less context is measurably MORE accurate, not merely cheaper (29% → 3% code-repair accuracy as context
grew 32K → 256K, LongCodeBench). If a `ripwire wrap` primer or the opt-in `skills/install.sh --hook`
nudge is installed, these same substitutions arrive without anyone loading this file — that is the point:
a rule an agent must remember to look up is a rule that loses to a habit.

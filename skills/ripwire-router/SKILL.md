---
name: ripwire-router
description: >
  Start HERE when unsure which ripwire skill fits, or asked 'how do I use ripwire / where do I start'.
  A moment→skill map, cold start to handoff, plus the two reflexes that leak most: --exemplar before
  you write, --quality-delta before you call it done. One hop to the right skill.
allowed-tools: Bash, Read
---

# ripwire router — the moment → skill map

Agents route by **moment**, not by feature. Find your row; it names the ONE skill to enter. Each skill's own
routing line sends you one hop onward if you routed wrong.

**Not sure which verb fits?** `ripwire <dir> --help-task="<the task in words>" --legend=compact` returns ONE
recommended command with its evidence, or honestly abstains. Advice only — it never executes. Backtick a bare
word that names code (`` `F` ``) so it routes by name.

| The moment you're in | Enter | Its opening move |
|---|---|---|
| cold start in an unfamiliar repo; "how does X work / where is Y"; resuming after a compaction; one answer out of a pile of dumped output; a symbol missing from the map | **ripwire-orient** | `ripwire <dir>` once, `--recall`, `--for="X"` · resume: `--recall` → `--situ` → `--notes` |
| a NAMED symbol: callers, callees, path A→B, "safe to rename X", an exact literal, a closed claim, 3+ symbols | **ripwire-navigate** | `--impact` + `--uses` · `--grep` · `--verify` · `--connect` |
| a symptom: crash, stack trace, wrong output, "it broke after my edit" | **ripwire-find-bug** | `--from-trace=FILE` · `--situ` · `--for="symptom"` |
| about to write ONE symbol, or add a dependency | **ripwire-reuse-first** | `--for` then optionally `--exemplar` |
| planning a FEATURE; implementing an interface | **ripwire-before-you-build** | `--pack-task` · `--lego=I` |
| "did the code I wrote get worse?" before done | **ripwire-quality-bar** | `--quality-delta` |
| "is my diff safe to merge / which tests / did I break a contract / branch landing order" | **ripwire-change-check** | `--edit-check=SYM` · `--test-gate` · `--merge-scout` |
| code I did NOT write: rot, refactor planning, dark flags, owners | **ripwire-fresh-eyes** | `--quality-panel` |
| tests for existing untested code | **ripwire-write-tests** | `--seams` |
| a measured profile names a hot symbol | **ripwire-perf-target** | `--for` on the measured symbol |
| untrusted SKILL.md / `.mcp.json`, or code on an untrusted-input path | **ripwire-security-scan** | `--scan-skills` · `--lint` |
| briefing someone else on a subsystem | **ripwire-handoff** | `--for --signatures-only` → `--expand` → `--recall` |
| architecture health with rules to enforce in CI | **ripwire-layers** | `--arch=rules.txt` · `--deps` |
| a graph question the fixed verbs can't phrase | **ripwire-graph-query** | `--graph-query='EXPR'` |
| wiring ripwire into an agent as an MCP server; tool health | **ripwire-mcp** | `ripwire wrap AGENT` · `--doctor` |
| a clang optimization remark on ripwire's OWN C++ (contributors) | **ripwire-opt-remarks** | `scripts/optremarks.sh` |
| is my setup healthy? | (no skill) | `ripwire <dir> --doctor --legend=compact` |

## The two reflexes that leak most

- **Before you write a fn/class, even a quick one:** `--for="<task>"` to reuse first, then `--exemplar` for the
  shape to imitate (→ **ripwire-reuse-first**).
- **Before you call it DONE:** `ripwire <dir> --quality-delta --legend=compact` — only what your change made worse,
  across 12 kinds, vs `git HEAD` (→ **ripwire-quality-bar**).

About to `Read` a whole file for one function, or `Grep` a symbol name? `--expand=SYM` and `--for="theExactName"`
answer it for a fraction of the bytes (`defaults.md`).

## The legend, in one line

Answers carry a compact legend by default; add `--legend=full` when a definition's reasoning is needed. On a long session, read the core once — `ripwire --legend-dict=core`,
13 definitions, about 1.5 KB, all of it — then pass its `have=` value as `--legend-have=<value>` to stop paying
for definitions you hold. Under about 10 ripwire calls, pass nothing. Never pass a value whose lines you did not
read (`legend.md`).

## Reference files — read only when a row above is not enough

`moments.md` (every moment with its full opening move) · `defaults.md` (Read/Grep/Glob → the ripwire substitute) ·
`legend.md` (compact vs full, refusals, `--legend-have` measurements) · `scope.md` (cross-cutting disciplines,
languages, wrong tool for the job, reference skills) · `primer.md` (the two reflexes in full, `--help`,
installing these skills with `skills/install.sh`).

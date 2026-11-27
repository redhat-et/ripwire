---
name: ripwire-router
description: >
  Start HERE when unsure which ripwire skill fits, or asked 'how do I use ripwire / where do I start':
  maps the moment to one skill, plus the two reflexes that leak most — --exemplar before you write,
  --quality-delta before done.
allowed-tools: Bash, Read
---

# ripwire router — the moment → skill map

Find your moment and enter that ONE skill; each skill's routing line corrects a wrong pick in one hop. Unsure of
the verb? `ripwire <dir> --help-task="<the task in words>"` recommends ONE command with its evidence, or abstains
(advice only; backtick a word that names code, `` `F` ``, so it routes by name).

| The moment you're in | Enter | Opening move |
|---|---|---|
| cold start; "how does X work / where is Y"; resuming after a compaction; a symbol missing from the map | **ripwire-orient** | `ripwire <dir>` once, `--recall`, `--for="X"` · resume: `--recall` → `--situ` → `--notes` |
| a NAMED symbol: callers, callees, path A→B, "safe to rename X", an exact literal, a closed claim, 3+ symbols | **ripwire-navigate** | `--for` (routes itself) · `--grep` · `--verify` · `--connect` |
| a symptom: crash, stack trace, wrong output, "it broke after my edit" | **ripwire-find-bug** | `--from-trace=FILE` · `--situ` · `--for="symptom"` |
| about to write ONE symbol, or add a dependency | **ripwire-reuse-first** | `--for`, then optionally `--exemplar` |
| planning a FEATURE; implementing an interface | **ripwire-before-you-build** | `--pack-task` · `--lego=I` |
| "did the code I wrote get worse?" before done | **ripwire-quality-bar** | `--quality-delta` |
| "is my diff safe to merge / which tests / did I break a contract / landing order" | **ripwire-change-check** | `--edit-check=SYM` · `--test-gate` · `--merge-scout` |
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

- **Before you write a fn/class, even a quick one:** `--for="<task>"` to reuse first, then `--exemplar` for the shape
  to imitate (**ripwire-reuse-first**).
- **Before you call it DONE:** `ripwire <dir> --quality-delta --legend=compact` — only what your change made worse, across 13 kinds, vs
  `git HEAD` (**ripwire-quality-bar**).

About to `Read` a whole file for one function, or `Grep` a symbol name? `--expand=SYM` and `--for="theExactName"`
answer it for a fraction of the bytes (`defaults.md`).

## The legend

Answers carry the compact legend by default; add `--legend=full` when a definition's reasoning is needed. On a long
session (about 10+ ripwire calls), read `ripwire --legend-dict=core` in full — 13 definitions, about 1.5 KB — and pass
its `have=` as `--legend-have=<value>`; on a shorter one pass nothing. Never pass a value whose lines you did not read
(`legend.md`).

## Reference files — read only when a row above is not enough

`moments.md` every moment with its full opening move · `defaults.md` Read/Grep/Glob → the ripwire substitute ·
`legend.md` legend postures, refusals, `--legend-have` measurements · `scope.md` cross-cutting disciplines, languages,
wrong tool for the job · `primer.md` the two reflexes in full, `--help`, installing these skills (`skills/install.sh`).

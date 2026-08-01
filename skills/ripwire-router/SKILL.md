---
name: ripwire-router
description: >
  Start HERE when you're not sure which ripwire skill to use, or you're asked "which ripwire skill / how do I
  use ripwire / where do I start with ripwire". A moment→skill map: it names the ONE skill for each moment an
  agent recognizes itself in — cold-start, understand-X, planning-a-feature, about-to-write-a-symbol,
  mid-implementation, reviewing-my-diff, debugging, refactoring, perf, security, handoff — plus the two
  reflexes that leak most (before you write → --exemplar; before you call it done → --quality-delta). One
  hop from here to the right skill. Backed by ripwire (the deterministic "ripgrep of AI context", on PATH).
allowed-tools: Bash, Read
---

# ripwire router — the moment → skill map

Agents route by **moment**, not by feature. Find the row that matches what you're about to do; it names the
ONE skill to enter. If you routed wrong, each skill's own routing header sends you one hop to the right one.

| The moment you're in | The ONE skill | Its opening move |
|---|---|---|
| **Cold-start** — landed in an unfamiliar repo, "what is this / what matters here" | **ripwire-orient** | `--recall` then `--report` |
| **Resuming after a context compaction / a new session on work already in flight** — you have a task but no longer the reasoning that got you here | **ripwire-orient** | rebuild state instead of re-reading files: `--recall="<the task>"` (what past sessions WROTE down) → `--situ` (what the working tree currently has changed + tests to run) → `--notes` (gotchas already paid for). Cheaper and more accurate than re-deriving from source. |
| **Understand X** — "how does X work / where is Y / architecture overview" | **ripwire-orient** | `--for="X"` |
| **Trace one symbol** — who calls it, what it calls, is it safe to change, locate a literal | **ripwire-navigate** | `--callers`/`--callees`/`--impact`/`--grep` |
| **My task touches A, B and C — how do they relate?** — N (>2) task symbols, or a pair `--path` can't reach | **ripwire-navigate** | `--connect=A,B,C` (the shared-caller join a directed `--path` can't see) |
| **Planning a FEATURE** — multi-symbol work needing a plan / interface / size estimate | **ripwire-before-you-build** | `--recall` + `--for` + `--seams` |
| **Implementing against an interface** — writing a class/type that must satisfy interface `I` | **ripwire-before-you-build** | `--lego=I` (I's method contract + every existing implementor to copy) |
| **About to write ONE symbol** — a fn/class/helper, even a "quick" one | **ripwire-reuse-first** | `--exemplar` + `--for` + `--clones` |
| **Mid-implementation** — about to open several files just to learn something | **ripwire-efficient** | cheapest verb, then read 2-3 files |
| **Reviewing MY diff** — "am I ready to push / is this safe to merge" | **ripwire-change-check** | `--quality-delta` (that's the quality-bar reflex) → `--pr-context` |
| **Which tests should I run for this change? Did I run the right ones?** | **ripwire-change-check** | `--affected=F1,F2` / `--situ` → `--test-gate` |
| **Writing tests for existing (untested) code** | **ripwire-write-tests** | `--seams` + `tested=0` lens + `--callers=SYM` |
| **Reviewing code I did NOT write** — unfamiliar subsystem, "what's gnarly here" | **ripwire-fresh-eyes** | `--hotspots` + `--clones` + `--owners` (scope to the subsystem) |
| **Debugging** — a symptom, a suspect subsystem, or "I changed X and it broke" | **ripwire-find-bug** | `--for=symptom` / `--situ` |
| **I HAVE a stack trace / sanitizer report / compiler error** — paste it, don't hand-translate it | **ripwire-find-bug** | `--from-trace=FILE` (or `-` from stdin) — frames → ranked in-corpus suspects, innermost first |
| **Just edited a symbol** — "did I change a contract someone depends on?" (pre-commit, per-symbol) | **ripwire-change-check** | `--edit-check=SYM` — unchanged / new-symbol / contract-change + flagged incompatible callers, ~26 ms warm |
| **Landing several branches / parallel agent worktrees** — who conflicts, what order? | **ripwire-change-check** | `--merge-scout=REF1,REF2,…` — pairwise conflict sites + a suggested landing order |
| **Branch/content archaeology** — "I have 30 branches and don't know what's stranded on them" (not a diff review) | **ripwire-change-check** | `--stray-content[=SUBSTR]` (unmerged/superseded/merged verdict per ref) + `--whereis=SYM` (which ref defines/mentions it) |
| **Worth remembering for the next session** — a gotcha tied to a symbol/file (trap, flake, invariant) | **ripwire-orient** | `--note-add="SYM: text"` — surfaces automatically whenever `--for`/`--expand` later emit that symbol |
| **One-call orientation under a budget** — the whole --for → bodies → callers → tests dance at once | **ripwire-efficient** | `--pack-task="task"` (+ `--token-budget=N`) — ranking, top bodies, caller sigs, notes, tests_to_run in ONE bundle |
| **About to FAN OUT** — spawning N subagents / worktrees / lanes, about to hand-write N per-agent briefs | **ripwire-efficient** | `--pack-task="task" --partition=N` (N=2..16) — ONE shared core plus N minimally-overlapping slices carved along the call graph's own communities, so N agents stop re-deriving the same orientation. `--token-budget` here means ONE agent's budget; each inner `<ctx>` is byte-identical to that agent's standalone call, so hand it over verbatim. Check `overlap_max` before trusting the split, and `split="K"` (>0 = a module was cut at its rank median because there were fewer modules than agents). Then `--plan-lanes=N --task="…"` (or `--plan-lanes --brief=FILE`) for the conflict-aware version: which lanes would COLLIDE, in what order they should land, and what each must test — JSON, pre-hoc, before a line is written. |
| **Refactoring** — planning a restructure, or a suspected god object | **ripwire-fresh-eyes** | `--communities`/`--metrics` (lcom4) + `--impact` + `--cochange` |
| **Perf** — a benchmark/profile (including a flame graph) identifies a slow operation or symbol | **ripwire-perf-target** | measure → navigate measured surface → re-measure |
| **Security** — untrusted input, reviewing security-sensitive code, or auditing a skill/MCP config | **ripwire-security-scan** | `--lint` unsafe fns + `--scan-skills` |
| **Handoff** — writing a summary of a repo/change for the next agent or teammate | **ripwire-handoff** | the handoff bundle |
| **What's built but DARK here** — "why don't I see feature X" (code compiled/flagged OFF, not a bug) | **ripwire-fresh-eyes** | `--flags[=SUBSTR]` (dark-gate dashboard) + `--flip=NAME` (blast radius of turning one ON) — **ripwire-find-bug** points here too when a symptom turns out to be a dark flag |
| **Task spans multiple checkouts** — service+client, a split monorepo — one question over BOTH | any moment skill above | pass every root: `ripwire dir1 dir2 --for=…` (one merged graph; `--impact` across roots needs the workspace call). Refusal boundary: `--quality-delta`/`--test-gate`/`--eval*`/`--arch --baseline` stay single-root (HEAD-keyed baselines and corpora are per-repo) — run those per root. |
| **Is my ripwire setup healthy / am I running a stale binary?** | (no skill — run directly) | `ripwire <dir> --doctor` — binary-vs-PATH staleness, grammar compile, cache-dir health, git reachability (single-root, diagnostic not deterministic) |

## Cross-cutting disciplines (fire ALONGSIDE a moment skill, not instead)

- **ripwire-efficient** — the map-before-you-read token+accuracy discipline for *any* read, at *any* moment.
- **ripwire-quality-bar** — the measure-what-you-made-worse convergence loop, at *every* "I think I'm done".
- **ripwire-reuse-first** — reuse-before-reinvent, at *every* new symbol.

These aren't a "moment" you land in; they're reflexes you carry into every moment.

## Wrong tool for the job

ripwire parses **C++, C, ObjC/ObjC++, Metal (MSL), C#, Python, TypeScript, JavaScript, Java, Ruby, Bash, Go,
Rust, Swift; JSON (config keys)** — nothing else. A repo in another language (PHP, Kotlin, ...) gets a silently thin or
empty map, not an error — don't mistake that for
"nothing here." Reach for plain `rg` + reads instead. And ripwire maps *structure*, not build/link state — a
build failure or a linker error is the compiler's/linker's question, not ripwire's; it can still tell you
*where* the broken symbol lives (`--grep`/`--callers`), just not why the toolchain rejected it.

## Reference skills (consulted, never "entered")

**ripwire-layers** (architecture-health / `--arch` CI gate), **ripwire-graph-query** (custom graph queries),
**ripwire-mcp** (run ripwire as an MCP server). `--doctor` (setup-health row above) is diagnostic, not a
moment skill. `--eval` / `--eval-retrieval` / `--eval-mined` are
maintainer self-eval harnesses (not an agent moment) — `--eval-mined=FILE` scores ranker recall against
real session-mined (query, gold-files) pairs from `bench/mine_traces.py`; see `DESIGN_traceEvals.md`. The
detail-ladder / token-squeeze (`--compress`) material
lives inside **ripwire-efficient**'s companion file (`compress-ladder.md`) now — it's not a standalone
moment. You don't recognize "the graph-query moment" — reach for these when a moment skill points you at
them.

## The two-reflex primer — the moments the habit forgets

The always-loaded ripwire primer trains the READ verbs (`--for`/`--recall`/`--callers`/`--expand`/
`--hotspots`) but not the two WRITE-time reflexes, which is exactly where the most value leaks:

- **Before you write a fn/class — even a "quick" one:** `ripwire <dir> --exemplar="<the sub-task in words>"`
  → the repo's best-in-class instance of that shape to imitate (by ROLE, not text similarity), plus
  `--for="<task>"` to reuse before reinventing. Duplicates are born on tasks that felt too small to tool up
  for. (→ **ripwire-reuse-first**.)
- **Before you call it DONE:** `ripwire <dir> --quality-delta` → ONLY what your change made worse across 10
  kinds (complexity, verbosity, nesting, params, duplication, dead-code, api-surface, error-masking,
  short-horizon-churn, new-clone-of-reused-helper); exit 2 = new debt.
  In a git repo it **auto-compares vs `git HEAD`** (no start-of-task ritual — just run it before you push).
  For a mid-task convergence loop, run `ripwire <dir> --quality-baseline` at the start to pin an explicit
  floor (it takes precedence over HEAD), then re-run `--quality-delta` after each edit. (→ **ripwire-quality-bar**.)

`ripwire --help` is the full flag catalog; every skill re-verifies its commands against the shipped binary.

**Installing these skills:** `bash skills/install.sh` symlinks every `ripwire-*` skill into the Claude
skill home (`--codex` targets `CODEX_HOME/skills` instead) and prunes dangling links from removed skills.

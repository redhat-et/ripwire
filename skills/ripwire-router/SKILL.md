---
name: ripwire-router
description: >
  Start HERE when you're not sure which ripwire skill to use, or you're asked "which ripwire skill / how do I
  use ripwire / where do I start with ripwire". A moment→skill map: it names the ONE skill for each moment an
  agent recognizes itself in — cold-start, understand-X, planning-a-feature, about-to-write-a-symbol,
  mid-implementation, reviewing-my-diff, debugging, refactoring, perf, security, handoff — plus the two
  reflexes that leak most (before you write → --exemplar; before you call it done → --quality-delta) and the
  moment after a measurement: which refactor a measured shape actually calls for, and the loop that proves
  the fix landed. One
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
| **Verify one closed code claim** — does A call B, is X unused, does a file define/contain Y? | **ripwire-navigate** | `--verify='calls(A,B)'` (also `uses`/`unused`/`contains`/`defines`/`reaches`) |
| **My task touches A, B and C — how do they relate?** — N (>2) task symbols, or a pair `--path` can't reach | **ripwire-navigate** | `--connect=A,B,C` (the shared-caller join a directed `--path` can't see) |
| **Planning a FEATURE** — multi-symbol work needing a plan / interface / size estimate | **ripwire-before-you-build** | `--recall` + `--for` + `--seams` |
| **Implementing against an interface** — writing a class/type that must satisfy interface `I` | **ripwire-before-you-build** | `--lego=I` (I's method contract + every existing implementor to copy) |
| **About to write ONE symbol** — a fn/class/helper, even a "quick" one | **ripwire-reuse-first** | `--exemplar` + `--for` + `--clones` |
| **Mid-implementation** — about to open several files just to learn something | **ripwire-efficient** | cheapest verb, then read 2-3 files |
| **Reviewing MY diff** — "am I ready to push / is this safe to merge" | **ripwire-change-check** | `--quality-delta` (that's the quality-bar reflex) → `--pr-context` |
| **Which tests should I run for this change? Did I run the right ones?** | **ripwire-change-check** | `--affected=F1,F2` / `--situ` → `--test-gate` |
| **A test failed and I have its name and nothing else** — what does this harness actually cover? | **ripwire-change-check** | `--exercises=TESTFILE` — the INVERSE of `--affected`: the non-test symbols this test transitively calls into |
| **My symbol is missing from the map** — expected a def to show up and it didn't | **ripwire-orient** | `--skipped` first (was its FILE dropped — a size ceiling, one row per oversize file); if the file isn't oversize-skipped, `--doctor` next (stale binary, grammar/parse failure, cache-dir health — a setup check, not a bug report) |
| **Writing tests for existing (untested) code** | **ripwire-write-tests** | `--seams` + `tested=1` coverage lens + `--callers=SYM` |
| **Reviewing code I did NOT write** — unfamiliar subsystem, "what's gnarly here" | **ripwire-fresh-eyes** | `--quality-panel` (THE SINGLE COMMAND — six evidence families in one ranked report; a lens, not a gate) — or `--hotspots` + `--clones` + `--owners` one lens at a time (scope to the subsystem) |
| **Debugging** — a symptom, a suspect subsystem, or "I changed X and it broke" | **ripwire-find-bug** | `--for=symptom` / `--situ` |
| **I HAVE a stack trace / sanitizer report / compiler error** — paste it, don't hand-translate it | **ripwire-find-bug** | `--from-trace=FILE` (or `-` from stdin) — frames → ranked in-corpus suspects, innermost first |
| **Just edited a symbol** — "did I change a contract someone depends on?" (pre-commit, per-symbol) | **ripwire-change-check** | `--edit-check=SYM` — unchanged / new-symbol / contract-change + flagged incompatible callers, ~26 ms warm |
| **Landing several branches / parallel agent worktrees** — who conflicts, what order? | **ripwire-change-check** | `--merge-scout=REF1,REF2,…` — pairwise conflict sites + a suggested landing order |
| **Branch/content archaeology** — "I have 30 branches and don't know what's stranded on them" (not a diff review) | **ripwire-change-check** | `--stray-content[=SUBSTR]` (unmerged/superseded/merged verdict per ref) + `--whereis=SYM` (which ref defines/mentions it) |
| **Worth remembering for the next session** — a gotcha tied to a symbol/file (trap, flake, invariant) | **ripwire-orient** | `--note-add="SYM: text"` — surfaces automatically whenever `--for`/`--expand` later emit that symbol |
| **One-call orientation under a budget** — the whole --for → bodies → callers → tests dance at once | **ripwire-efficient** | `--pack-task="task"` (+ `--token-budget=N`) — ranking, top bodies, caller sigs, notes, tests_to_run in ONE bundle |
| **About to FAN OUT** — spawning N subagents / worktrees / lanes, about to hand-write N per-agent briefs | **ripwire-efficient** | `--pack-task="task" --partition=N` (N=2..16) — ONE shared core plus N minimally-overlapping slices carved along the call graph's own communities, so N agents stop re-deriving the same orientation. `--token-budget` here means ONE agent's budget; each inner `<ctx>` is byte-identical to that agent's standalone call, so hand it over verbatim. Check `overlap_max` before trusting the split, and `split="K"` (>0 = a module was cut at its rank median because there were fewer modules than agents). Then `--plan-lanes=N --task="…"` (or `--plan-lanes --brief=FILE`) for the conflict-aware version: which lanes would COLLIDE, in what order they should land, and what each must test — JSON, pre-hoc, before a line is written. |
| **Refactoring** — planning a restructure, or a suspected god object | **ripwire-fresh-eyes** | `--communities`/`--metrics` (lcom4) + `--impact` + `--cochange`; read the nesting PROFILE (`humps=`/`deep=`), never `nest=` alone |
| **I have the measurement — now WHICH refactor, and is it safe?** — a shape (many shallow humps / one deep tangle / small-and-dense / untested hub / a clone) needs a named fix and its precondition | **ripwire-quality-bar** | the shape → refactor playbook, then the closed fix loop: `--quality-delta` → `--edit-check=SYM` → `--affected` |
| **Perf** — a benchmark/profile (including a flame graph) identifies a slow operation or symbol | **ripwire-perf-target** | measure → navigate measured surface → re-measure; if the counters say MEMORY not compute, `--field-affinity[=STRUCT]` (a hypothesis generator, never a measurement) |
| **A clang optimization remark while editing ripwire's OWN C++** — `-Rpass`/`-Rpass-missed` says "loop not vectorized" / "will not inline" / etc, and you need to decide if it's worth a diff | **ripwire-opt-remarks** | `scripts/optremarks.sh` then `scripts/optremarks.py --hot` — contributor-facing, not a general perf-investigation entry: a generic "this is slow" / "where's the bottleneck" prompt with no remark in hand is **ripwire-perf-target**, not this |
| **Security** — untrusted input, reviewing security-sensitive code, or auditing a skill/MCP config | **ripwire-security-scan** | `--lint` unsafe fns + `--scan-skills` |
| **Handoff** — writing a summary of a repo/change for the next agent or teammate | **ripwire-handoff** | the handoff bundle |
| **What's built but DARK here** — "why don't I see feature X" (code compiled/flagged OFF, not a bug) | **ripwire-fresh-eyes** | `--flags[=SUBSTR]` (dark-gate dashboard) + `--flip=NAME` (blast radius of turning one ON) — **ripwire-find-bug** points here too when a symptom turns out to be a dark flag |
| **Task spans multiple checkouts** — service+client, a split monorepo — one question over BOTH | any moment skill above | pass every root: `ripwire dir1 dir2 --for=…` (one merged graph; `--impact` across roots needs the workspace call). Refusal boundary: `--quality-delta`/`--test-gate`/`--eval*`/`--arch --baseline` stay single-root (HEAD-keyed baselines and corpora are per-repo) — run those per root. |
| **Is my ripwire setup healthy / am I running a stale binary?** | (no skill — run directly) | `ripwire <dir> --doctor` — binary-vs-PATH staleness, grammar compile, cache-dir health, git reachability (single-root, diagnostic not deterministic) |

## You are not in a "moment" — you are about to reach for a default

The table above assumes you recognized a moment. The most expensive case is the one where you did not:
you simply went for `Read`, `Grep`, or `Glob` because they are always there. That reflex needs no
recognition and no skill load, which is exactly why it wins by default and why it costs the most.

Match the **default you were about to use**, not a moment:

| About to… | Reach for instead |
|---|---|
| `Read` a whole file to understand one function | `--expand=SYM` — that symbol's body + its callees' signatures. The file is not the unit of an answer. |
| `Read` several files to learn how something works | `--pack-task="<task>"` — ranking + bodies + callers + tests in ONE budgeted call |
| `Grep`/`rg` a symbol name across the tree | `--for="theExactName"` (name-exact routing, recall@1 ~99%) · `--uses=SYM` for every read/write/import site |
| `Grep` a concept ("where do we retry") | `--for="<the concept in words>"` — matches doc-comments and bodies, not just identifiers |
| `Glob` for candidate files by name | `--for=` ranks by what the code DOES; a glob only knows paths |
| paste a stack trace and hand-pick frames | `--from-trace=FILE` (`-` = stdin) — verbatim, ranked innermost-first |
| `git diff` / `git log` to judge a change | `--situ` (blast radius + tests) · `--rank-by=churn` |

The discipline behind this row set is **ripwire-efficient**; it is worth entering even mid-task, because
less context is measurably MORE accurate, not merely cheaper (29% → 3% code-repair accuracy as context
grew 32K → 256K, LongCodeBench). If a `ripwire wrap` primer or the opt-in `skills/install.sh --hook`
nudge is installed, these same substitutions arrive without anyone loading this file — that is the point:
a rule an agent must remember to look up is a rule that loses to a habit.

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
real session-mined (query, gold-files) pairs from `bench/mine_traces.py`. The
detail-ladder / token-squeeze (`--compress`) material
lives inside **ripwire-efficient**'s companion file (`skills/ripwire-efficient/compress-ladder.md`) now — it's not a standalone
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
  **A finding is only half the job** — the fix is not done until it is proven: `--quality-delta` (targeted
  kind gone, nothing else regressed) → `--edit-check=SYM` (contract intact) → `--affected` (the tests that
  prove it). That chain, and the shape → refactor playbook that picks the fix in the first place, are in
  **ripwire-quality-bar**.
  For a mid-task convergence loop, run `ripwire <dir> --quality-baseline` at the start to pin an explicit
  floor (it takes precedence over HEAD), then re-run `--quality-delta` after each edit. (→ **ripwire-quality-bar**.)
  Want the wider "does this still look rotten" picture alongside the delta, not just what you changed? —
  `ripwire <dir> --quality-panel[=strict|default|lenient]`, the six-family panel (→ **ripwire-fresh-eyes**).
  **It is a lens, not a gate** — always exits 0; `--quality-delta` above is the only pass here that gates.

`ripwire --help` is the full flag catalog; every skill re-verifies its commands against the shipped binary.

**Installing these skills:** `bash skills/install.sh` symlinks every `ripwire-*` skill into the Claude
skill home (its codex mode targets `${AGENTS_HOME:-~/.agents}/skills`; `--codex-legacy` retains
`${CODEX_HOME:-~/.codex}/skills`) and prunes dangling links from removed skills. Add `--hook` explicitly
for the advisory nudge (`--codex --hook` for Codex).

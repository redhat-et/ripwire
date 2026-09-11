### ripwire-before-you-build (294 chars)
Starting a FEATURE (multi-symbol work): the plan, the API boundary, the scope — how big does this change get — from the codebase's real structure; --lego=Iface lists an interface's contract and its implementors. ONE symbol → reuse-first. A small feature with an obvious home needs none of this.

### ripwire-change-check (313 chars)
Merge-SAFETY of an existing diff — yours before you push, or a PR you review: blast radius, tests to run, a broken contract (--edit-check=SYM), branch conflicts and landing order, unmerged work stranded on old branches, which ref defines it. Code QUALITY → quality-bar. Even a one-line leaf fix runs --edit-check.

### ripwire-find-bug (314 chars)
You have a SYMPTOM — crash, exception, wrong output, failing test, error string — and don't know which code is responsible. Ranks candidates; a stack trace or sanitizer output maps onto frames innermost-first; 'it worked yesterday' / 'my last edit broke it' → --situ. One clear hit plus one focused read is enough.

### ripwire-fresh-eyes (314 chars)
Maintenance risk in code you did NOT write — inheriting a module, a suspected god object, 'what's gnarly / where's the rot / safe to touch?': hotspots, dead code, clones, a function's real shape, bus factor, co-change. Naming the fix or judging YOUR new code → quality-bar. A single-lens question is a single call.

### ripwire-graph-query (315 chars)
A call-graph question the fixed verbs can't phrase — 'which high-complexity functions can reach X?', 'what has 10+ callers in src/?', 'untested symbols within one hop of main'. --graph-query: a small closed expression language — kind, complexity, fan-in, tested filters; a file or cluster; bounded hops; and/or/not.

### ripwire-handoff (283 chars)
Brief someone ELSE on a subsystem — 'hand this area off' to a successor, teammate or fresh session: purpose, the 2-3 entry points with bodies, the design docs that say WHY, hotspot/bus-factor risk — a compact pasteable brief, not a wall of source. Understanding it yourself → orient.

### ripwire-layers (294 chars)
Architecture HEALTH and ENFORCEMENT — 'is this a dependency mess / does the UI reach into the database / enforce module boundaries in CI?': cycles, the godfile, propagation cost (how far a touch ripples), --arch rules with a baseline gate. Overview without gating → orient. One pass answers it.

### ripwire-mcp (286 chars)
Wire ripwire into an agent as an MCP server — `ripwire wrap AGENT` (Claude Code, Cursor, Codex, Gemini…) — and choose the server verb mid-task. Also tool HEALTH: a symbol you expected is missing from the ranked output, the index feels stale after a rebase, 'is my ripwire setup broken?'

### ripwire-navigate (302 chars)
You can NAME the symbol: who calls it, what it calls, the path from A to B, its full body, or an exact literal/regex match. 'Safe to change or rename X — what breaks downstream?' = the transitive blast radius, not 1-hop callers. Three or more symbols → --connect. Run the one verb that fits, then stop.

### ripwire-opt-remarks (265 chars)
Triage clang optimization remarks (-Rpass, -Rpass-missed, opt-record YAML) while editing ripwire's OWN C++: 'loop not vectorized', 'will not be inlined' — worth a diff, or is LTO/PGO the real fix? Contributor-only: about compiling this tool, never about running it.

### ripwire-orient (319 chars)
Landing COLD in an unfamiliar repo or subsystem, or about to open several files for one question: map first, read only the files it ranks highest. Main subsystems and entry points, 'how does X work / where is Y'; compacted mid-task, rebuild what you knew. A NAMED symbol → navigate. Stop at the first rung that answers.

### ripwire-perf-target (308 chars)
A MEASURED performance problem: start from a benchmark, flame graph, perf sample or profiler run, locate the hot symbol the profile names, test structural hypotheses (memory-bound → cache-line data layout). Static metrics are change-risk signals, not runtime heat. Inspect only the symbols the profile names.

### ripwire-quality-bar (319 chars)
Code QUALITY of what YOU just wrote, before you commit or say 'done': --quality-delta reports only what got WORSE across 10 kinds and exits non-zero on new debt; then which restructuring a measured shape (humps/deep, a tangle) calls for. Merge safety → change-check. Even a single-line leaf fix runs the one-shot delta.

### ripwire-reuse-first (304 chars)
About to write ONE symbol (even a 'quick' one-liner) or add a dependency: reuse before you reinvent. Finds the building block that already exists, the house pattern to imitate, the duplicate you'd recreate, a vendored dependency. A whole feature → before-you-build. One --exemplar or --grep call at most.

### ripwire-router (279 chars)
Start HERE when unsure which ripwire skill fits, or asked 'how do I use ripwire / where do I start'. A moment→skill map, cold start to handoff, plus the two reflexes that leak most: --exemplar before you write, --quality-delta before you call it done. One hop to the right skill.

### ripwire-security-scan (311 chars)
Security review: (1) vet an untrusted SKILL.md or .mcp.json BEFORE installing it — the injection/exfiltration scanner; CRITICAL blocks the install; (2) audit code on an untrusted-input path (a deserializer, parser, exec of user data, network endpoint): taint reach, untested seams. One scan pass is the verdict.

### ripwire-write-tests (307 chars)
Write tests for EXISTING code that has none — 'this is untested, add coverage', 'add a safety net first'. Finds what no test reaches: --seams ranks untested cross-module edges, --callers gives the outside contract. Judging your own diff → change-check. For one target one --seams or --callers pass suffices.

### ripwire-before-you-build (350 chars)
About to start a whole FEATURE — multi-symbol work that needs a plan, an interface, or a size estimate before you write it — do the homework from the codebase's actual structure instead of assumptions. Use when starting a feature and you need any of: is this approach even viable (spike)? what's the ordered implementation plan? what should the bound

### ripwire-change-check (350 chars)
The merge-SAFETY check for a diff that already EXISTS — your own working changes before you submit, or an incoming PR you're reviewing — beyond the line-by-line view. Use at "am I ready to push?" / "is this safe to merge?" / "what does this PR actually touch?" / "which tests should I run for this change?". Also covers three narrower moments: just e

### ripwire-efficient (350 chars)
A token + accuracy DISCIPLINE for ANY read, not a moment: map before you open files. Reach for it the instant you catch yourself about to open more than ~2 files to figure something out — anywhere in a task. Also the moment you catch yourself typing "let me search the codebase", "let me read that file", or "let me look at a few files first": that s

### ripwire-find-bug (350 chars)
Locate the code behind a bug when you don't yet know where it lives. Use when you have a SYMPTOM (a crash, an exception, wrong output, a failing test, an error string) and need to find the responsible symbol — whether you have no idea where it is, suspect a subsystem, or just broke it with a change of your own (even a deploy) — including "it worked

### ripwire-fresh-eyes (350 chars)
Assess maintenance risk in code you did NOT write — an already identified subsystem: "what's gnarly here / where's the rot / is this area safe to touch?". Use it when PLANNING A REFACTOR or investigating a suspected god object — find the high-complexity cluster, its blast radius, and its co-change seams. One structured pass over maintenance hotspot

### ripwire-graph-query (350 chars)
Compose a call-graph question the fixed ripwire verbs don't pre-answer — "which high-complexity functions can reach X?", "what in src/ has 10+ callers?". A small, closed expression language (--graph-query) over the symbol graph: filter by kind, complexity or fan-in, narrow to a file or cluster, bounded callers/callees closure, and/or/not joins. Use

### ripwire-handoff (350 chars)
Summarize a subsystem for another agent or teammate — "hand this area off". Use when you're about to brief someone else (not understand it yourself — that's orient) on a subsystem's purpose, key symbols, design rationale, and current maintenance risk — what the recipient needs and nothing stale, written as a summary of a repo area for the next agen

### ripwire-layers (350 chars)
Architecture HEALTH and ENFORCEMENT — "how healthy are the layers / is this a dependency mess / are there layering violations / how do I enforce module boundaries in CI?". Assesses dependency structure, call-graph modules, each dependency cycle and godfile, the debt a single violation represents, propagation cost (the change-amplification tax of to

### ripwire-mcp (350 chars)
Wire ripwire into a coding agent as an MCP server — "ripwire wrap AGENT". Covers the 31 MCP verbs (16 read incl. fetch_body/flags/slice + 12 flagship-reflex verbs incl. connect/explore/from_trace/edit_check and the cross-branch pair whereis/stray_content + 3 edit verbs) and when the persistent server beats the preferred CLI form, the lazy-body hand

### ripwire-navigate (350 chars)
Trace how code connects and understand ONE symbol in depth — who calls a function, what it calls, how one symbol reaches another, the flow from A to B or a bounded neighborhood around one definition, a full-body deep-dive of a named symbol with its callers/callees/design-docs, or find a literal / regex / AST-shape with its enclosing symbol. Use whe

### ripwire-opt-remarks (350 chars)
Triage clang optimization remarks (-Rpass / -Rpass-missed / -fsave-optimization-record) while editing ripwire's own C++. Use when a compiler remark says loop not vectorized, will not be inlined, load clobbered, or LICM failed to hoist — and you must decide whether that remark is worth a diff. Covers -DRIPWIRE_OPT_REMARKS=ON, the opt-record YAML tri

### ripwire-orient (350 chars)
Understand an unfamiliar codebase or subsystem FAST, before editing. Use the moment you land cold in a repo (new to the team, about to pick up a ticket), need the lay of the land, main subsystems and entry points, are asked "how does X work / where is Y / what matters here", or need an architecture OVERVIEW (structure: what's here, how it's organiz

### ripwire-perf-target (350 chars)
Investigate a measured performance problem. Start from a representative benchmark, a flame graph, or a profiler sample. Pin the workload first, then use ripwire to locate the hot symbol the profile names, map callers/callees, and inspect structural hypotheses such as complexity, churn, coupling, nesting, and — when the counters implicate MEMORY rat

### ripwire-quality-bar (350 chars)
The code-QUALITY bar for what you just wrote — not merge-safety. Needs NO setup: right before you commit / open a PR / tell the user it's finished, run `ripwire <dir> --quality-delta` — reports ONLY what you made WORSE across 10 measured kinds (complexity, verbosity, nesting, params, duplication, dead-code, API-surface, error-masking, short-horizon

### ripwire-reuse-first (350 chars)
About to write ONE symbol — a single function, class, helper, or utility — reuse before you reinvent. Use the moment you're about to author any named thing (even a "quick" one-liner: duplicates are born on tasks that feel too small to tool up for), and before adding a dependency. ripwire finds the existing building block, the repo's best-in-class e

### ripwire-router (350 chars)
Start HERE when you're not sure which ripwire skill to use, or you're asked "which ripwire skill / how do I use ripwire / where do I start with ripwire". A moment→skill map: it names the ONE skill for each moment an agent recognizes itself in — cold-start, understand-X, planning-a-feature, about-to-write-a-symbol, mid-implementation, reviewing-my-d

### ripwire-security-scan (350 chars)
Security review — two different moments, one skill. (1) Vet an untrusted agent config BEFORE you install or activate it: a SKILL.md file (or a whole skills/ directory) → ripwire's built-in injection/exfiltration/ path-traversal scanner, whose findings carry a severity and whose CRITICAL verdict blocks the install; an .mcp.json server config → ripwi

### ripwire-write-tests (349 chars)
Write tests for EXISTING code that has none — "this is untested, add coverage" / "what's missing a test here?". Different moment from judging your own diff (ripwire-change-check) or your own code's quality (ripwire-quality-bar): this is about FINDING what lacks a safety net and writing the test that closes the gap — what no test reaches, and which

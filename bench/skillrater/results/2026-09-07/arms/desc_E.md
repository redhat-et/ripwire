### ripwire-before-you-build (350 chars)
re and you need any of: is this approach even viable (spike)? what's the ordered implementation plan? what should the boundary/API look like (interface)? how big is this change (scope/effort)? Each takes ~30s and often surfaces an existing implementation to reuse. Building against an EXISTING interface — "my new backend must plug into StorageDriver

### ripwire-change-check (349 chars)
I change a contract someone depends on (a fast per-symbol contract check, --edit-check, no full diff needed); landing several branches or parallel agent worktrees and need to know who conflicts and in what order they should land (--merge-scout); and cross-ref content archaeology — "I have 30 branches and do not know what is stranded on them" — whi

### ripwire-efficient (349 chars)
less context is measurably MORE accurate, not just cheaper; a small ranked map beats a fan-out of whole-file reads on both. Code-repair accuracy fell 29% → 3% as context grew 32K → 256K tokens (LongCodeBench), so "read a few more files to be safe" is the instinct this replaces, not a safe default. The reflex is one line: run the cheapest verb that

### ripwire-find-bug (349 chars)
an exception, wrong output, a failing test, an error string) and need to find the responsible symbol — whether you have no idea where it is, suspect a subsystem, or just broke it with a change of your own (even a deploy) — including "it worked yesterday and now it is broken". A stack trace's frames map straight onto indexed symbols, innermost firs

### ripwire-fresh-eyes (350 chars)
. Use when taking ownership of an existing module, planning a refactor, hunting consolidation, deciding who should review, or producing a health snapshot. Reads a function's nesting PROFILE (`humps=`/`deep=`/ `locals=`), not `nest=` alone, so a tangle and a long blocked-sequential body stop looking identical — then routes to ripwire-quality-bar for

### ripwire-graph-query (350 chars)
n't pre-answer — "which high-complexity functions can reach X?", "what in src/ has 10+ callers?". A small, closed expression language (--graph-query) over the symbol graph: filter by kind, complexity or fan-in, narrow to a file or cluster, bounded callers/callees closure, and/or/not joins. Use when --callers/--callees/--impact alone can't phrase th

### ripwire-handoff (349 chars)
tand it yourself — that's orient) on a subsystem's purpose, key symbols, design rationale, and current maintenance risk — what the recipient needs and nothing stale, written as a summary of a repo area for the next agent (or teammate) to pick up. Produces a compact, pasteable brief instead of a wall of source code — signatures + full bodies of the

### ripwire-layers (350 chars)
ass, and for every metric it reports, what to DO about a bad number: formalize a boundary, write a `deny` rule, gate it. This is the enforcement/gates lens on architecture; for the one-screen structure/overview lens (no gating) → ripwire-orient. One pass answers the health question — re-run only after you change the rules or the code. Backed by rip

### ripwire-mcp (350 chars)
i / opencode / aider, when deciding which ripwire MCP verb to call mid-task, or when wondering whether the server's index is stale. Also the tool-health moment: a symbol you EXPECTED is missing from the ranked output, results look stale or wrong, "is my ripwire setup broken?" — the index-staleness / server-health / rebuild surface answers whether t

### ripwire-navigate (350 chars)
r, the flow from A to B or a bounded neighborhood around one definition, a full-body deep-dive of a named symbol with its callers/callees/design-docs, or find a literal / regex / AST-shape with its enclosing symbol. Use when you know (or can name) the symbol and need the call graph, its contract, or to locate code precisely — instead of grepping an

### ripwire-opt-remarks (349 chars)
-fsave-optimization-record) while editing ripwire's own C++. Use when a compiler remark says loop not vectorized, will not be inlined, load clobbered, or LICM failed to hoist — and you must decide whether that remark is worth a diff. Covers -DRIPWIRE_OPT_REMARKS=ON, the opt-record YAML triage, which remark classes are signal versus restated algori

### ripwire-orient (350 chars)
it's organized) or a nested module map — or a gotcha worth remembering for the next session (--note-add) — or resuming cold after a context compaction, when the task survived but the reasoning did not. Runs ripwire (the deterministic "ripgrep of AI context", on PATH) to MAP the code — an escalation ladder from a one-screen report up to communities,

### ripwire-perf-target (350 chars)
symbol the profile names, map callers/callees, and inspect structural hypotheses such as complexity, churn, coupling, nesting, and — when the counters implicate MEMORY rather than compute — cache-line data layout via `--field-affinity` (which fields are read together but declared far apart), including the boundary of what that lens cannot see. Stat

### ripwire-quality-bar (350 chars)
" moment on non-trivial work. The check itself is cheap (well under a second warm) — run it even on a fix that looks trivial, because "trivial" is exactly the judgment this pass exists to catch you being wrong about; what a single-line leaf fix with no new branch/symbol/signature can skip is the CONVERGENCE LOOP around it (re-reading the drill-down

### ripwire-reuse-first (350 chars)
s the existing building block, the repo's best-in-class exemplar to imitate (by ROLE, not text similarity), the duplicate you are about to recreate, and whether the dependency is already in the tree, so you compose instead of reinvent. The least code is the least complexity, the fewest bugs, the smallest review, and the most cache-friendly diff. Fo

### ripwire-router (349 chars)
about-to-write-a-symbol, mid-implementation, reviewing-my-diff, debugging, refactoring, perf, security, handoff — plus the two reflexes that leak most (before you write → --exemplar; before you call it done → --quality-delta) and the moment after a measurement: which refactor a measured shape actually calls for, and the loop that proves the fix la

### ripwire-security-scan (350 chars)
tic checklist of its shell stanzas. (2) Reviewing security-sensitive CODE or an untrusted-input path (parsing, deserialization, auth, exec/eval, network-facing handlers) → assemble STRUCTURAL signal: unsafe-C-fn / c-style-cast lint hits, forward taint-reach via transitive callees, untested integration seams, sink use-sites. Use when you receive a s

### ripwire-write-tests (350 chars)
ests for EXISTING code that has none — "this is untested, add coverage" / "what's missing a test here?". Different moment from judging your own diff (ripwire-change-check) or your own code's quality (ripwire-quality-bar): this is about FINDING what lacks a safety net and writing the test that closes the gap — what no test reaches, and which integra

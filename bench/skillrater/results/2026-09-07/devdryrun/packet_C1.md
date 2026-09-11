# Skill routing packet

You are the skill router inside a coding agent. The agent has these skills installed; each
line is exactly what the agent sees: the skill's name and its description. Nothing else.

- **ripwire-before-you-build**: Starting a FEATURE (multi-symbol work): the plan, the API boundary, the scope — how big does this change get — from the codebase's real structure; --lego=Iface lists an interface's contract and its implementors. ONE symbol → reuse-first. A small feature with an obvious home needs none of this.
- **ripwire-change-check**: Merge-SAFETY of an existing diff — yours before you push, or a PR you review: blast radius, tests to run, a broken contract (--edit-check=SYM), branch conflicts and landing order, unmerged work stranded on old branches, which ref defines it. Code QUALITY → quality-bar. Even a one-line leaf fix runs --edit-check.
- **ripwire-efficient**: About to open more than ~2 files, or paste whole files into context, to answer one question: map first, then read only the 2-3 files the map ranks highest. The token budget discipline for ANY read — less context is measurably MORE accurate; fires alongside the moment skills.
- **ripwire-find-bug**: You have a SYMPTOM — crash, exception, wrong output, failing test, error string — and don't know which code is responsible. Ranks candidates; a stack trace or sanitizer output maps onto frames innermost-first; 'it worked yesterday' / 'my last edit broke it' → --situ. One clear hit plus one focused read is enough.
- **ripwire-fresh-eyes**: Maintenance risk in code you did NOT write — inheriting a module, a suspected god object, 'what's gnarly / where's the rot / safe to touch?': hotspots, dead code, clones, a function's real shape, bus factor, co-change. Naming the fix or judging YOUR new code → quality-bar. A single-lens question is a single call.
- **ripwire-graph-query**: A call-graph question the fixed verbs can't phrase — 'which high-complexity functions can reach X?', 'what has 10+ callers in src/?', 'untested symbols within one hop of main'. --graph-query: a small closed expression language — kind, complexity, fan-in, tested filters; a file or cluster; bounded hops; and/or/not.
- **ripwire-handoff**: Brief someone ELSE on a subsystem — 'hand this area off' to a successor, teammate or fresh session: purpose, the 2-3 entry points with bodies, the design docs that say WHY, hotspot/bus-factor risk — a compact pasteable brief, not a wall of source. Understanding it yourself → orient.
- **ripwire-layers**: Architecture HEALTH and ENFORCEMENT — 'is this a dependency mess / does the UI reach into the database / enforce module boundaries in CI?': cycles, the godfile, propagation cost (how far a touch ripples), --arch rules with a baseline gate. Overview without gating → orient. One pass answers it.
- **ripwire-mcp**: Wire ripwire into an agent as an MCP server — `ripwire wrap AGENT` (Claude Code, Cursor, Codex, Gemini…) — and choose the server verb mid-task. Also tool HEALTH: a symbol you expected is missing from the ranked output, the index feels stale after a rebase, 'is my ripwire setup broken?'
- **ripwire-navigate**: You can NAME the symbol: who calls it, what it calls, the path from A to B, its full body, or an exact literal/regex match. 'Safe to change or rename X — what breaks downstream?' = the transitive blast radius, not 1-hop callers. Three or more symbols → --connect. Run the one verb that fits, then stop.
- **ripwire-opt-remarks**: Triage clang optimization remarks (-Rpass, -Rpass-missed, opt-record YAML) while editing ripwire's OWN C++: 'loop not vectorized', 'will not be inlined' — worth a diff, or is LTO/PGO the real fix? Contributor-only: about compiling this tool, never about running it.
- **ripwire-orient**: Landing COLD in an unfamiliar repo or subsystem: the lay of the land, 'how does X work / where is Y', an architecture overview — or compacted mid-task, rebuilding what you knew. A ladder from a one- screen map upward; --skipped when the map looks short. A NAMED symbol → navigate. Stop at the first rung that answers.
- **ripwire-perf-target**: A MEASURED performance problem: start from a benchmark, flame graph, perf sample or profiler run, locate the hot symbol the profile names, test structural hypotheses (memory-bound → cache-line data layout). Static metrics are change-risk signals, not runtime heat. Inspect only the symbols the profile names.
- **ripwire-quality-bar**: Code QUALITY of what YOU just wrote, before you commit or say 'done': --quality-delta reports only what got WORSE across 10 kinds and exits non-zero on new debt; then which restructuring a measured shape (humps/deep, a tangle) calls for. Merge safety → change-check. Even a single-line leaf fix runs the one-shot delta.
- **ripwire-reuse-first**: About to write ONE symbol (even a 'quick' one-liner) or add a dependency: reuse before you reinvent. Finds the building block that already exists, the house pattern to imitate, the duplicate you'd recreate, a vendored dependency. A whole feature → before-you-build. One --exemplar or --grep call at most.
- **ripwire-security-scan**: Security review: (1) vet an untrusted SKILL.md or .mcp.json BEFORE installing it — the injection/exfiltration scanner; CRITICAL blocks the install; (2) audit code on an untrusted-input path (a deserializer, parser, exec of user data, network endpoint): taint reach, untested seams. One scan pass is the verdict.
- **ripwire-write-tests**: Write tests for EXISTING code that has none — 'this is untested, add coverage', 'add a safety net first'. Finds what no test reaches: --seams ranks untested cross-module edges, --callers gives the outside contract. Judging your own diff → change-check. For one target one --seams or --callers pass suffices.

For EACH prompt below, decide which ONE skill the agent should load first (`top1`), and the
runner-up (`top2`). If no skill fits the prompt at all, answer `none` for top1 (top2 may still
name the nearest skill). Judge from the descriptions above only.

## Prompts

P001: How tangled are our module boundaries - any cycles I should lose sleep over?
P002: I got compacted mid-task and lost my reasoning - rebuild what I knew about the migration work.
P003: Give me the house pattern for a visitor class before I author mine.
P004: I keep pasting whole files into context and the budget is bleeding - better way?
P005: Which file is the godfile gluing everything together and what would unpicking it cost?
P006: This function keeps sprouting branches and I cannot tell if it is one tangled mess or just a long plain sequence - what shape is it actually?
P007: Add a safety net around applyDiscount before we refactor it - what is its outside contract?
P008: Users report the export silently produces an empty archive - zero leads on where it happens.
P009: Exception says KeyError: locale but grepping locale gives 400 hits - find the real site.
P010: Our deploy pipeline is slow and the whole team is annoyed about it - where do we even start looking?
P011: Adding a dependency for CSV parsing - is that already vendored somewhere in here?
P012: Add MIT license headers to the new files.
P013: Wrapping up - run the last-mile debt check before I tell them it is done.
P014: Capture the state of the migration tooling so a fresh session continues without me.
P015: I already have the humps and deep numbers for this function from a subsystem review - which refactor does that shape actually call for?
P016: Find the classes in the storage file with fan-in over five.
P017: I expected this function to show up in the ranked output and it is just not there at all - is my ripwire setup broken?
P018: Pin the GitHub Action to a commit SHA instead of a tag.
P019: Which handlers in src/api have more than ten callers?
P020: Audit the deserializer path - it eats bytes arriving from the network unchecked.
P021: Show me the chain from handleUpload to the S3 client - the actual route the data takes.
P022: Which untested symbols sit within one hop of main?
P023: Enforce that utils never imports from app - and make CI hold the line.
P024: This function's complexity score looks huge, but half of it sits inside an #ifdef for a platform we do not even build - can I trust the number as reported?
P025: Read out flushQueue in full with whatever it calls - I need its contract before touching it.
P026: I am working on ripwire's C++ and clang keeps telling me a call "will not be inlined" - should I change the source or just move on?
P027: This service feels sluggish under load - any general tips for speeding it up?
P028: Track down every write to the retryBudget field before I change its type.
P029: Before I chase this LICM-failed-to-hoist remark with a source change, is a build flag more likely to be the real fix here?
P030: The function I measured has one deep tangle in the middle - which restructuring actually fits that shape?
P031: Pasting the sanitizer output here - point me at the guilty frame.
P032: Write a SQL query listing users who signed up this month.
P033: Another team inherits the exporter next sprint - produce the orientation doc.
P034: Run the remarks harness and tell me which missed optimizations sit in hot code.
P035: If I rename applyPatch, what breaks downstream?
P036: Rotate the staging API keys and update the secrets store.
P037: Spell-check the documentation folder.
P038: Bump the package version and tag the release.
P039: Does anything in the UI reach directly into the database code? It should not.
P040: Convert the images in assets to WebP.
P041: Brief the incoming agent on the ingest area - what it does, why, and where it bites.
P042: Counters put the row scanner memory-bound - which fields fight over cache lines?
P043: Before opening the PR, check whether my new code added duplication or dead branches.
P044: Upgrade the CI runners to the larger instance size.
P045: Sketch the boundary for the new caching layer - what should its API expose?
P046: My teammate left a bunch of code review remarks I still need to address before this merges.
P047: Legacy util file, no tests, heavily called - close the gap.
P048: Inheriting the billing module from a departed teammate - how rotten is it really?
P049: The profiler says we are memory-bound in this struct-heavy loop - which fields are actually read together versus how the struct is laid out?
P050: Our p99 doubled and the flame profile points at JSON encode - investigate.
P051: This endpoint execs user-supplied templates - how exposed are we?
P052: Scope this for me: adding rate limiting across the gateway - how big does that change get?
P053: Why does my Docker build keep missing the layer cache?
P054: Perf sample attached: most time under lockContention in the pool - map that call surface.
P055: A new MCP server config landed in the repo - inspect its shell blocks before I enable it.
P056: Why is feature X invisible at runtime - is it compiled out behind a flag?
P057: -Rpass-missed is noisy on ingest.cpp - triage which remarks deserve a diff.
P058: It worked on Friday and the demo just crashed - what changed underneath?
P059: I have a huge pile of optimization-record YAML from a remarks build of this repo - how do I actually triage it instead of reading a gigabyte of output?
P060: Write a friendly README intro paragraph for the project.
P061: This class smells like it does everything - confirm it is a god object and show the seams.
P062: Set this up inside Cursor so the model can query the index without shelling out.
P063: Before I reach for a heavier profiler pass, are there any obvious bad data-layout patterns a plain lint run would already catch?
P064: The index the agent sees feels stale after my rebase - how does the server refresh?
P065: Prepare a pasteable summary of the auth subsystem for the contractor starting Monday.
P066: One-liner to clamp values - just gonna type it out.
P067: I have a dozen old feature branches and no idea which ones still hold work that never made it to main.
P068: Which server verbs should the agent lean on during a task instead of the CLI flags?
P069: The build spewed will-not-inline: cost exceeds threshold on the hot comparator - do I care?
P070: The complexity number on this function is high, but I cannot tell if it is a genuine tangle or just a long simple sequence I could split by hand - how risky would splitting it actually be?
P071: The map that came back looks short - did some files just get dropped for being too big to index?
P072: Need a function that slugifies titles - surely something like it exists here already?
P073: The parser package has zero tests - give me a starting point so the effort counts.
P074: Write up the entry points and the design rationale here so a teammate does not have to re-read the whole module cold.
P075: Convert this YAML config to JSON for me.
P076: I need functions matching: in the parser dir AND complexity over 15 AND called from outside it.
P077: The compiler just printed "loop not vectorized" for a function I am editing in ripwire's own source - is that actually worth chasing with a code change?
P078: I rotate off this codebase Friday - package what my successor needs about the sync engine.
P079: Which ref actually still defines this function - I keep finding stale references to it across branches.
P080: I am wrapping up for the day and want to leave a clean summary of this subsystem for whoever picks it up tomorrow.
P081: If someone touches common.h, how far does the ripple spread through the build?
P082: Can you optimize this paragraph so it reads faster for a non-technical audience?
P083: My last edit broke the pipeline somewhere - work backwards from my working diff.

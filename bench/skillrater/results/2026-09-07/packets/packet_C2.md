# Skill routing packet

You are the skill router inside a coding agent. The agent has these skills installed; each
line is exactly what the agent sees: the skill's name and its description. Nothing else.

- **ripwire-before-you-build**: Starting a FEATURE (multi-symbol work): the plan, the API boundary, the scope — how big does this change get — from the codebase's real structure; --lego=Iface lists an interface's contract and its implementors. ONE symbol → reuse-first. A small feature with an obvious home needs none of this.
- **ripwire-change-check**: Merge-SAFETY of an existing diff — yours before you push, or a PR you review: blast radius, tests to run, a broken contract (--edit-check=SYM), branch conflicts and landing order, unmerged work stranded on old branches, which ref defines it. Code QUALITY → quality-bar. Even a one-line leaf fix runs --edit-check.
- **ripwire-find-bug**: You have a SYMPTOM — crash, exception, wrong output, failing test, error string — and don't know which code is responsible. Ranks candidates; a stack trace or sanitizer output maps onto frames innermost-first; 'it worked yesterday' / 'my last edit broke it' → --situ. One clear hit plus one focused read is enough.
- **ripwire-fresh-eyes**: Maintenance risk in code you did NOT write — inheriting a module, a suspected god object, 'what's gnarly / where's the rot / safe to touch?': hotspots, dead code, clones, a function's real shape, bus factor, co-change. Naming the fix or judging YOUR new code → quality-bar. A single-lens question is a single call.
- **ripwire-graph-query**: A call-graph question the fixed verbs can't phrase — 'which high-complexity functions can reach X?', 'what has 10+ callers in src/?', 'untested symbols within one hop of main'. --graph-query: a small closed expression language — kind, complexity, fan-in, tested filters; a file or cluster; bounded hops; and/or/not.
- **ripwire-handoff**: Brief someone ELSE on a subsystem — 'hand this area off' to a successor, teammate or fresh session: purpose, the 2-3 entry points with bodies, the design docs that say WHY, hotspot/bus-factor risk — a compact pasteable brief, not a wall of source. Understanding it yourself → orient.
- **ripwire-layers**: Architecture HEALTH and ENFORCEMENT — 'is this a dependency mess / does the UI reach into the database / enforce module boundaries in CI?': cycles, the godfile, propagation cost (how far a touch ripples), --arch rules with a baseline gate. Overview without gating → orient. One pass answers it.
- **ripwire-mcp**: Wire ripwire into an agent as an MCP server — `ripwire wrap AGENT` (Claude Code, Cursor, Codex, Gemini…) — and choose the server verb mid-task. Also tool HEALTH: a symbol you expected is missing from the ranked output, the index feels stale after a rebase, 'is my ripwire setup broken?'
- **ripwire-navigate**: You can NAME the symbol: who calls it, what it calls, the path from A to B, its full body, or an exact literal/regex match. 'Safe to change or rename X — what breaks downstream?' = the transitive blast radius, not 1-hop callers. Three or more symbols → --connect. Run the one verb that fits, then stop.
- **ripwire-opt-remarks**: Triage clang optimization remarks (-Rpass, -Rpass-missed, opt-record YAML) while editing ripwire's OWN C++: 'loop not vectorized', 'will not be inlined' — worth a diff, or is LTO/PGO the real fix? Contributor-only: about compiling this tool, never about running it.
- **ripwire-orient**: Landing COLD in an unfamiliar repo or subsystem, or about to open several files for one question: map first, read only the files it ranks highest. Main subsystems and entry points, 'how does X work / where is Y'; compacted mid-task, rebuild what you knew. A NAMED symbol → navigate. Stop at the first rung that answers.
- **ripwire-perf-target**: A MEASURED performance problem: start from a benchmark, flame graph, perf sample or profiler run, locate the hot symbol the profile names, test structural hypotheses (memory-bound → cache-line data layout). Static metrics are change-risk signals, not runtime heat. Inspect only the symbols the profile names.
- **ripwire-quality-bar**: Code QUALITY of what YOU just wrote, before you commit or say 'done': --quality-delta reports only what got WORSE across 10 kinds and exits non-zero on new debt; then which restructuring a measured shape (humps/deep, a tangle) calls for. Merge safety → change-check. Even a single-line leaf fix runs the one-shot delta.
- **ripwire-reuse-first**: About to write ONE symbol (even a 'quick' one-liner) or add a dependency: reuse before you reinvent. Finds the building block that already exists, the house pattern to imitate, the duplicate you'd recreate, a vendored dependency. A whole feature → before-you-build. One --exemplar or --grep call at most.
- **ripwire-security-scan**: Security review: (1) vet an untrusted SKILL.md or .mcp.json BEFORE installing it — the injection/exfiltration scanner; CRITICAL blocks the install; (2) audit code on an untrusted-input path (a deserializer, parser, exec of user data, network endpoint): taint reach, untested seams. One scan pass is the verdict.
- **ripwire-write-tests**: Write tests for EXISTING code that has none — 'this is untested, add coverage', 'add a safety net first'. Finds what no test reaches: --seams ranks untested cross-module edges, --callers gives the outside contract. Judging your own diff → change-check. For one target one --seams or --callers pass suffices.

For EACH prompt below, decide which ONE skill the agent should load first (`top1`), and the
runner-up (`top2`). If no skill fits the prompt at all, answer `none` for top1 (top2 may still
name the nearest skill). Judge from the descriptions above only.

## Prompts

P001: I need a fresh pair of reading glasses - what prescription strength ranges are common?
P002: Can you review this restaurant for me based on the menu photos?
P003: Two worktrees touched the tokenizer - which lands first and where do they collide?
P004: I need to add a new backend that implements the StorageDriver interface - what does an existing one look like so I do not guess the shape?
P005: This class has ballooned to two thousand lines and everyone is scared of it - where would a split actually help?
P006: Before we commit a sprint to this, is the approach even workable given how the code is actually structured?
P007: What does HTTP status 451 mean?
P008: Proofread and review my conference talk abstract.
P009: Center the logo on the landing page and darken the footer.
P010: Translate these error strings into German for the locale file.
P011: I need to find every place we retry a network call the old way, not just grep the word retry.
P012: Spinning up four subagents for this refactor - carve the repo so their briefs do not overlap.
P013: Summarize the storage engine for the teammate taking it over next sprint.
P014: We are taking over a service nobody on the team has touched in a year - what should worry us before we start editing it?
P015: Reviewing the auth handler for injection risk - assemble the evidence.
P016: Book a meeting room for the design review tomorrow.
P017: How do I turn on dark mode in my terminal emulator?
P018: Why does npm install fail with EACCES on my machine?
P019: The profiler pins 40 percent of samples in normalizeKeys - dig in from there.
P020: We just lost an hour to a stale lockfile causing a flaky build - I want that written down somewhere it will resurface next time this file comes up.
P021: Regenerate the protobuf stubs with the new compiler version.
P022: Mute the flaky Slack webhook alert until Monday.
P023: What is a good stretch routine for lower back pain from sitting all day?
P024: I am rotating off this project on Friday - put together something the next person can actually read instead of skimming the whole repo.
P025: Jot this down for future sessions: the fixture loader silently caches across tests.
P026: Periodic sweep: anything sketchy in the skills directory we installed last month?
P027: Increase the terminal font size in VS Code.
P028: How many layers should a good lasagna have, and in what order?
P029: My context window is filling with file dumps again - keep this cheap.
P030: I think the patch is finished - what did I just make worse?
P031: I keep tab-hopping between a dozen files trying to understand one code path - there has to be a faster way to see the shape of this.
P032: Rename the default branch across our repositories.
P033: If the one person who understands this subsystem left tomorrow, how exposed would we be?
P034: How do I improve my 5K running pace?
P035: I want a build order for the export feature before writing any code.
P036: My fix landed but prove the cleanup stuck and nothing regressed.
P037: Getting my aider setup to use the graph tools - walk me through the wiring.
P038: What is the difference between TCP and UDP?
P039: Before the sprint starts I want an implementation sequence for the notifications feature grounded in real code.
P040: Management wants the billing core covered - rank what deserves a test first.
P041: Merge my three feature branches with the least pain.
P042: Three people have feature branches off the same module and we need to land them this week without a mess - what order should they go in?
P043: Double-check my working tree before I open the pull request.
P044: This parser reads whatever a client sends over the socket before we have validated any of it - I want eyes on that before it ships.
P045: Benchmark shows the cold path regressed 2x - I have the numbers, now what in the code?
P046: What is the fastest driving route to the airport that avoids tolls?
P047: If I rename the third parameter of buildIndex, what downstream code breaks?
P048: New to this service as of today - what are the moving parts and where does execution start?
P049: This ticket touches the cache layer, the eviction policy, and the metrics exporter - how do those three actually tie together?
P050: Before answering I will skim src end to end.
P051: Rename a file in git while preserving its history.
P052: Windsurf integration: which config block do I add, and what safety do the editing verbs promise?
P053: Our imports have become a circular tangle - how bad is it and how do we stop the bleeding?
P054: Hook the code map into Claude Code as a tool server for this repo.
P055: How long should I marinate chicken thighs before grilling?
P056: What is a good practice test format for a driver's license exam?
P057: Is streaming decode even viable here or am I fighting the architecture?
P058: How do I hook this tool up as an MCP server so my coding agent can call it directly?
P059: Squash my last four commits into one - the history is messy.
P060: What permits do I need before building a backyard shed?
P061: Cross complexity with fan-in and show me symbols where both are high, scoped to core/.
P062: What is the plural of octopus - octopi or octopuses?
P063: What is a good deadbolt brand for a front door?
P064: What separates a good espresso bean from a mediocre one?
P065: Set up prettier so the frontend formats on save.
P066: Hand me the whole task briefing at once, capped around six thousand tokens.
P067: Undo my last three commits but keep the changes staged.
P068: Which HTTP verbs are idempotent according to the spec?
P069: A test named test_manifest_roundtrip failed on CI - I have its name and no clue what it exercises.
P070: Nothing covers the ledger rollover path - write the missing test and prove it registers.
P071: Move the nightly cron to 3am UTC instead of midnight.
P072: Convert 75 degrees Fahrenheit to Celsius.
P073: Nobody has ever written a single test for this billing module - I want to close that gap, not just poke at it randomly.
P074: The ticket names three structs - ledger, journal, snapshot - and I cannot see how they meet.
P075: Throwing this compiler error at you - which of our symbols does it actually implicate?
P076: We keep saying the UI layer should not import the database layer but nothing actually stops it - can we make that a real rule in CI?
P077: Let me write a quick retry wrapper around the fetch call.
P078: My new backend must plug into StorageDriver - what has to exist and who implements it today?
P079: Which seams in this module does nothing exercise end to end?
P080: Set up a Python virtualenv pinned to an older interpreter.
P081: Explain Python's walrus operator.
P082: A teammate sent me an mcp config file from another project - I want it checked over before I let it anywhere near my machine.
P083: I am going to write a small helper that dedupes the config list.
P084: I need every function that is both high-complexity and eventually reaches the billing code - a simple caller list cannot express that.
P085: Explain the offside rule in soccer to someone who has never watched a match.
P086: Which way is magnetic north from here, and how do I use a compass properly?
P087: Stop me from reading the whole repo - what is the minimal context to fix the pager?
P088: Before I open this PR I just want to know what got worse, not a whole style lecture.
P089: I just changed the signature on this helper function - does anything downstream actually depend on the old shape?
P090: I am mid-task in my agent with a dozen MCP tools available - which one actually answers what I need right now?
P091: How do I vertically center a div inside a flex container?
P092: Draw me the shape of this codebase - the modules and how they are organized, not a file listing.
P093: The flame graph blames string splitting - dig into that code.
P094: Explain the rules for a handoff in a 4x100 relay race.
P095: This function parses packets straight off the wire - look it over for danger before I ship.
P096: How do I make a pie chart in Excel from this spreadsheet?
P097: Before I pull in a new library for retry-with-backoff, is there already something like that in this codebase?
P098: What is a fuel-efficient way to drive on the highway?
P099: Rough out the work to support incremental compilation - what order, what surface, how much effort?
P100: I fixed the bug; tell me whether my patch made the codebase worse.
P101: Fill in the sprint retro doc with what shipped.
P102: My Kubernetes pod is stuck in CrashLoopBackOff - what are the common causes?
P103: Which parts of the checkout flow have no safety net at all if I refactor them?
P104: Before I touch this shared utility function, I need to know everything that currently calls it.
P105: New on this team as of Monday; give me the lay of the land before I pick up a ticket.
P106: What plastics are actually accepted for curbside recycling?
P107: New architecture rule: adapters may not call services directly - wire up a violation gate.
P108: I need a tiny timestamp-formatting utility; do not let me reinvent one we already have.
P109: List every function above complexity twenty that can eventually reach the database layer.
P110: The nightly job started throwing a null-pointer exception somewhere after Tuesday's deploy.
P111: Let me skim a handful of files to get context on the session store first.
P112: Give me the two-hop callee closure of dispatch but only inside the network cluster.
P113: Rate the health of our layering after the merge - worse or better?
P114: About to add a tiny date-formatting util - two minutes tops.
P115: I wrote a test for the queue - verify it actually reaches the code I meant.
P116: Someone sent me a SKILL.md to install - screen it before it touches my agent.
P117: We have a graveyard of old branches nobody remembers the status of - is any of that actually still unmerged and worth rescuing?
P118: Where does input validation actually happen in this service?
P119: Write a limerick about compilers.
P120: What is the etiquette for merging onto a busy highway?
P121: Our benchmark says one call is eating most of the frame time - help me actually look at that code and what feeds into it.
P122: I suspect the scheduler subsystem for these stuck jobs - narrow it down.
P123: Clang complains it could not vectorize the radix loop because no reduction was identified - worth chasing?
P124: Planning to break up the parser package - what is entangled with what before I start?
P125: My cat will not stop scratching the couch - any tips?
P126: I got a vectorization remark on the scoring kernel while editing - decide whether a diff pays.
P127: What does git rebase --onto actually do?
P128: Here is the crash log with the full stack trace - I would rather not manually walk every frame by hand.
P129: Recommend a wine pairing for grilled salmon.
P130: Give me everything I would need for this ticket in one shot - ranking, the actual code, who calls it, what to test - I do not want to run five separate commands.
P131: Draft the changelog entry for this week's release.
P132: What is the best way to learn a new language as an adult?
P133: Is calling fetch_body from the agent cheaper than pulling entire files into context?
P134: Write a haiku about autumn leaves.
P135: What is a good commit message format for a small team?
P136: Show me functions with complexity above twenty from which the allocator is reachable.
P137: Convert this JSON blob to YAML for me.
P138: Draft a standup update from what I did yesterday.

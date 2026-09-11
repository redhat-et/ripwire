# Skill routing packet

You are the skill router inside a coding agent. The agent has these skills installed; each
line is exactly what the agent sees: the skill's name and its description. Nothing else.

- **ripwire-before-you-build**: About to start a whole FEATURE — multi-symbol work that needs a plan, an interface, or a size estimate before you write it — do the homework from the codebase's actual structure instead of assumptions. Use when starting a feature and you need any of: is this approach even viable (spike)? what's the ordered implementation plan? what should the bound
- **ripwire-change-check**: The merge-SAFETY check for a diff that already EXISTS — your own working changes before you submit, or an incoming PR you're reviewing — beyond the line-by-line view. Use at "am I ready to push?" / "is this safe to merge?" / "what does this PR actually touch?" / "which tests should I run for this change?". Also covers three narrower moments: just e
- **ripwire-efficient**: A token + accuracy DISCIPLINE for ANY read, not a moment: map before you open files. Reach for it the instant you catch yourself about to open more than ~2 files to figure something out — anywhere in a task. Also the moment you catch yourself typing "let me search the codebase", "let me read that file", or "let me look at a few files first": that s
- **ripwire-find-bug**: Locate the code behind a bug when you don't yet know where it lives. Use when you have a SYMPTOM (a crash, an exception, wrong output, a failing test, an error string) and need to find the responsible symbol — whether you have no idea where it is, suspect a subsystem, or just broke it with a change of your own (even a deploy) — including "it worked
- **ripwire-fresh-eyes**: Assess maintenance risk in code you did NOT write — an already identified subsystem: "what's gnarly here / where's the rot / is this area safe to touch?". Use it when PLANNING A REFACTOR or investigating a suspected god object — find the high-complexity cluster, its blast radius, and its co-change seams. One structured pass over maintenance hotspot
- **ripwire-graph-query**: Compose a call-graph question the fixed ripwire verbs don't pre-answer — "which high-complexity functions can reach X?", "what in src/ has 10+ callers?". A small, closed expression language (--graph-query) over the symbol graph: filter by kind, complexity or fan-in, narrow to a file or cluster, bounded callers/callees closure, and/or/not joins. Use
- **ripwire-handoff**: Summarize a subsystem for another agent or teammate — "hand this area off". Use when you're about to brief someone else (not understand it yourself — that's orient) on a subsystem's purpose, key symbols, design rationale, and current maintenance risk — what the recipient needs and nothing stale, written as a summary of a repo area for the next agen
- **ripwire-layers**: Architecture HEALTH and ENFORCEMENT — "how healthy are the layers / is this a dependency mess / are there layering violations / how do I enforce module boundaries in CI?". Assesses dependency structure, call-graph modules, each dependency cycle and godfile, the debt a single violation represents, propagation cost (the change-amplification tax of to
- **ripwire-mcp**: Wire ripwire into a coding agent as an MCP server — "ripwire wrap AGENT". Covers the 31 MCP verbs (16 read incl. fetch_body/flags/slice + 12 flagship-reflex verbs incl. connect/explore/from_trace/edit_check and the cross-branch pair whereis/stray_content + 3 edit verbs) and when the persistent server beats the preferred CLI form, the lazy-body hand
- **ripwire-navigate**: Trace how code connects and understand ONE symbol in depth — who calls a function, what it calls, how one symbol reaches another, the flow from A to B or a bounded neighborhood around one definition, a full-body deep-dive of a named symbol with its callers/callees/design-docs, or find a literal / regex / AST-shape with its enclosing symbol. Use whe
- **ripwire-opt-remarks**: Triage clang optimization remarks (-Rpass / -Rpass-missed / -fsave-optimization-record) while editing ripwire's own C++. Use when a compiler remark says loop not vectorized, will not be inlined, load clobbered, or LICM failed to hoist — and you must decide whether that remark is worth a diff. Covers -DRIPWIRE_OPT_REMARKS=ON, the opt-record YAML tri
- **ripwire-orient**: Understand an unfamiliar codebase or subsystem FAST, before editing. Use the moment you land cold in a repo (new to the team, about to pick up a ticket), need the lay of the land, main subsystems and entry points, are asked "how does X work / where is Y / what matters here", or need an architecture OVERVIEW (structure: what's here, how it's organiz
- **ripwire-perf-target**: Investigate a measured performance problem. Start from a representative benchmark, a flame graph, or a profiler sample. Pin the workload first, then use ripwire to locate the hot symbol the profile names, map callers/callees, and inspect structural hypotheses such as complexity, churn, coupling, nesting, and — when the counters implicate MEMORY rat
- **ripwire-quality-bar**: The code-QUALITY bar for what you just wrote — not merge-safety. Needs NO setup: right before you commit / open a PR / tell the user it's finished, run `ripwire <dir> --quality-delta` — reports ONLY what you made WORSE across 10 measured kinds (complexity, verbosity, nesting, params, duplication, dead-code, API-surface, error-masking, short-horizon
- **ripwire-reuse-first**: About to write ONE symbol — a single function, class, helper, or utility — reuse before you reinvent. Use the moment you're about to author any named thing (even a "quick" one-liner: duplicates are born on tasks that feel too small to tool up for), and before adding a dependency. ripwire finds the existing building block, the repo's best-in-class e
- **ripwire-security-scan**: Security review — two different moments, one skill. (1) Vet an untrusted agent config BEFORE you install or activate it: a SKILL.md file (or a whole skills/ directory) → ripwire's built-in injection/exfiltration/ path-traversal scanner, whose findings carry a severity and whose CRITICAL verdict blocks the install; an .mcp.json server config → ripwi
- **ripwire-write-tests**: Write tests for EXISTING code that has none — "this is untested, add coverage" / "what's missing a test here?". Different moment from judging your own diff (ripwire-change-check) or your own code's quality (ripwire-quality-bar): this is about FINDING what lacks a safety net and writing the test that closes the gap — what no test reaches, and which

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

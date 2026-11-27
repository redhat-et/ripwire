# Skill routing packet

You are the skill router inside a coding agent. The agent has these skills installed; each
line is exactly what the agent sees: the skill's name and its description. Nothing else.

- **ripwire-before-you-build**: Starting a FEATURE (multi-symbol work): the plan, the API boundary, the scope — how big does this change get — from the codebase's real structure. Implementing an EXISTING interface? --lego=Iface lists its contract and current implementors. ONE standalone symbol → reuse-first. A small feature with an obvious home needs none of this.
- **ripwire-change-check**: Merge-SAFETY of an existing diff — yours before you push, or a PR you review: blast radius, tests to run, a broken contract (--edit-check=SYM), branch conflicts and landing order, unmerged work stranded on old branches, which ref defines it. Code QUALITY → quality-bar. Even a one-line leaf fix runs --edit-check.
- **ripwire-find-bug**: You have a SYMPTOM — crash, exception, wrong output, failing test, error string — and don't know which code is responsible. Ranks candidates; a stack trace or sanitizer output maps onto frames innermost-first; 'it worked yesterday' / 'my last edit broke it' → --situ. One clear hit plus one focused read is enough.
- **ripwire-fresh-eyes**: Maintenance risk in code you did NOT write — inheriting a module, planning a refactor, a suspected god object, 'what's gnarly / where's the rot / safe to touch?': hotspots, dead or inactive code, switches/defaults (--flags), clones, a function's real shape, bus factor, co-change. Naming the fix or judging YOUR new code → quality-bar. A single-lens question is a single call.
- **ripwire-graph-query**: A call-graph question the fixed verbs can't phrase — 'which high-complexity functions can reach X?', 'what has 10+ callers in src/?', 'untested symbols within one hop of main'. --graph-query: a small closed expression language — kind, complexity, fan-in, tested filters; a file or cluster; bounded hops; and/or/not.
- **ripwire-handoff**: Brief someone ELSE on a subsystem — 'hand this area off' to a successor, teammate or fresh session: purpose, the 2-3 entry points with bodies, the design docs that say WHY, hotspot/bus-factor risk — a compact pasteable brief, not a wall of source. Understanding it yourself → orient.
- **ripwire-layers**: Architecture HEALTH and ENFORCEMENT — 'is this a dependency mess / does the UI reach into the database / enforce module boundaries in CI?': cycles, the godfile, propagation cost (how far a touch ripples), --arch rules with a baseline gate. Overview without gating → orient. One pass answers it.
- **ripwire-mcp**: Wire ripwire into an agent as an MCP server — `ripwire wrap AGENT` (Claude Code, Cursor, Codex, Gemini…) — and choose the server verb mid-task. Also tool HEALTH: a symbol you expected is missing from the ranked output, the index feels stale after a rebase, 'is my ripwire setup broken?'
- **ripwire-navigate**: You can NAME the symbol: who calls it, what it calls, the path from A to B, its full body, or an exact literal/regex match. 'Safe to change or rename X — what breaks downstream?' = the transitive blast radius, not 1-hop callers. Three or more symbols → --connect. Run the one verb that fits, then stop.
- **ripwire-opt-remarks**: Triage clang optimization remarks (-Rpass, -Rpass-missed, opt-record YAML) while editing ripwire's OWN C++: 'loop not vectorized', 'will not be inlined' — worth a diff, or is LTO/PGO the real fix? Contributor-only: about compiling this tool, never about running it.
- **ripwire-orient**: Landing COLD in an unfamiliar repo or subsystem, or about to open several files for one question: map first, read only what it ranks highest — main subsystems, entry points, 'how does X work / where is Y'. Also recover context after compaction, retrieve saved docs (--recall), divide code for subagents (--partition), save gotchas (--note-add). NAMED symbol → navigate. Stop at the first rung that answers.
- **ripwire-perf-target**: A MEASURED performance problem: start from a benchmark, flame graph, perf sample or profiler run, locate the hot symbol the profile names, test structural hypotheses (memory-bound → cache-line data layout). Static metrics are change-risk signals, not runtime heat. Inspect only the symbols the profile names.
- **ripwire-quality-bar**: QUALITY of code YOU just wrote, before commit/'done' or cleanup: --quality-delta lists what got WORSE in 13 kinds; exit 2 if old code did (new-symbol rows never gate, except defect-shape format-arity, a new function at the ceiling and a tangled new one); each shape's fix. Merge safety → change-check. Even a single-line leaf fix runs it.
- **ripwire-reuse-first**: About to write ONE symbol (even a 'quick' one-liner) or add a dependency: reuse before you reinvent. Finds the building block that already exists, the house pattern to imitate, the duplicate you'd recreate, a vendored dependency. An interface or whole feature → before-you-build. One --exemplar or --grep call at most.
- **ripwire-security-scan**: Security review: (1) vet an untrusted SKILL.md or .mcp.json BEFORE installing it — the injection/exfiltration scanner; CRITICAL blocks the install; (2) audit code on an untrusted-input path (a deserializer, parser, exec of user data, network endpoint): taint reach, untested seams. One scan pass is the verdict.
- **ripwire-write-tests**: Write tests for EXISTING code that has none — 'this is untested, add coverage', 'add a safety net first'; also verify a new test reaches its intended code. Finds what no test reaches: --seams ranks untested cross-module edges, --callers gives the outside contract. Diff test selection → change-check. For one target one --seams or --callers pass suffices.

For EACH prompt below, decide which ONE skill the agent should load first (`top1`), and the
runner-up (`top2`). If no skill fits the prompt at all, answer `none` for top1 (top2 may still
name the nearest skill). Judge from the descriptions above only.

## Prompts

P001: Before I chase this LICM-failed-to-hoist remark with a source change, is a build flag more likely to be the real fix here?
P002: Management wants the billing core covered - rank what deserves a test first.
P003: Let me skim a handful of files to get context on the session store first.
P004: The ticket names three structs - ledger, journal, snapshot - and I cannot see how they meet.
P005: New to this repo - the top-level subsystems and entry points, and I will take it from there.
P006: I got compacted mid-task and lost my reasoning - rebuild what I knew about the migration work.
P007: Getting my aider setup to use the graph tools - walk me through the wiring.
P008: Does anything in the UI reach directly into the database code? It should not.
P009: I suspect the scheduler subsystem for these stuck jobs - narrow it down.
P010: What is the etiquette for merging onto a busy highway?
P011: Our benchmark says one call is eating most of the frame time - help me actually look at that code and what feeds into it.
P012: I have a sanitizer report with a full stack trace - do not make me hand-translate it.
P013: Give me the first rung only - what are the main subsystems, then stop
P014: Before answering I will skim src end to end.
P015: What is gnarly here?
P016: One target, one pass: which tests reach parseFrame and which do not
P017: Bump the package version and tag the release.
P018: Stop me from reading the whole repo - what is the minimal context to fix the pager?
P019: My fix landed but prove the cleanup stuck and nothing regressed.
P020: If I rename applyPatch, what breaks downstream?
P021: Which untested symbols sit within one hop of main?
P022: Why does my Docker build keep missing the layer cache?
P023: I received an .mcp.json server config from an external source - vet it before I install it.
P024: Hook the code map into Claude Code as a tool server for this repo.
P025: Add a safety net around applyDiscount before we refactor it - what is its outside contract?
P026: I want a build order for the export feature before writing any code.
P027: What in src/ has ten or more callers?
P028: I am mid-task in my agent with a dozen MCP tools available - which one actually answers what I need right now?
P029: Rotate the staging API keys and update the secrets store.
P030: Just one lens please: which files are the hotspots, nothing else
P031: This parser reads whatever a client sends over the socket before we have validated any of it - I want eyes on that before it ships.
P032: My new backend must plug into StorageDriver - what has to exist and who implements it today?
P033: Our deploy pipeline is slow and the whole team is annoyed about it - where do we even start looking?
P034: What permits do I need before building a backyard shed?
P035: Perf sample attached: most time under lockContention in the pool - map that call surface.
P036: Is it safe to change resolveTypes?
P037: I have to write a class that must satisfy the Codec interface - what is the contract and which implementors exist?
P038: Nobody has ever written a single test for this billing module - I want to close that gap, not just poke at it randomly.
P039: Spinning up four subagents for this refactor - carve the repo so their briefs do not overlap.
P040: I need a tiny timestamp-formatting utility; do not let me reinvent one we already have.
P041: Which file is the godfile gluing everything together and what would unpicking it cost?
P042: Prepare a pasteable summary of the auth subsystem for the contractor starting Monday.
P043: A test named test_manifest_roundtrip failed on CI - I have its name and no clue what it exercises.
P044: Who calls parseHeader, what does it call, and is it safe to change?
P045: The parser package has zero tests - give me a starting point so the effort counts.
P046: Center the logo on the landing page and darken the footer.
P047: This class has ballooned to two thousand lines and everyone is scared of it - where would a split actually help?
P048: Explain the offside rule in soccer to someone who has never watched a match.
P049: Add MIT license headers to the new files.
P050: -Rpass-missed is noisy on ingest.cpp - triage which remarks deserve a diff.
P051: My Kubernetes pod is stuck in CrashLoopBackOff - what are the common causes?
P052: My context window is filling with file dumps again - keep this cheap.
P053: Legacy util file, no tests, heavily called - close the gap.
P054: Do I really need the whole planning pass for a change this contained?
P055: What is a fuel-efficient way to drive on the highway?
P056: Can you review this restaurant for me based on the menu photos?
P057: Hand me the whole task briefing at once, capped around six thousand tokens.
P058: Pasting the sanitizer output here - point me at the guilty frame.
P059: Which parts of the checkout flow have no safety net at all if I refactor them?
P060: Double-check my working tree before I open the pull request.
P061: New architecture rule: adapters may not call services directly - wire up a violation gate.
P062: This is untested - add coverage.
P063: There is exactly one function I need coverage for - what is the shortest way to find its seam?
P064: This function keeps sprouting branches and I cannot tell if it is one tangled mess or just a long plain sequence - what shape is it actually?
P065: Landing cold here; one map is all I want before I start reading
P066: Need a function that slugifies titles - surely something like it exists here already?
P067: Benchmark shows the cold path regressed 2x - I have the numbers, now what in the code?
P068: Increase the terminal font size in VS Code.
P069: Investigate a measured performance problem starting from a profiler sample.
P070: Reviewing the auth handler for injection risk - assemble the evidence.
P071: If someone touches common.h, how far does the ripple spread through the build?
P072: This service feels sluggish under load - any general tips for speeding it up?
P073: Draft a standup update from what I did yesterday.
P074: Is streaming decode even viable here or am I fighting the architecture?
P075: Nothing covers the ledger rollover path - write the missing test and prove it registers.
P076: Planning to break up the parser package - what is entangled with what before I start?
P077: Inheriting the billing module from a departed teammate - how rotten is it really?
P078: Move the nightly cron to 3am UTC instead of midnight.
P079: Capture the state of the migration tooling so a fresh session continues without me.
P080: What is the best way to learn a new language as an adult?
P081: Fill in the sprint retro doc with what shipped.
P082: My cat will not stop scratching the couch - any tips?
P083: Set up prettier so the frontend formats on save.
P084: Before adding a dependency - is the capability already in the tree?
P085: I need functions matching: in the parser dir AND complexity over 15 AND called from outside it.
P086: Scope this for me: adding rate limiting across the gateway - how big does that change get?
P087: I changed X and it broke - trace the regression.
P088: Which ripwire MCP verb should I call mid-task?
P089: Merge my three feature branches with the least pain.
P090: Sketch the boundary for the new caching layer - what should its API expose?
P091: What is the fastest driving route to the airport that avoids tolls?
P092: We keep saying the UI layer should not import the database layer but nothing actually stops it - can we make that a real rule in CI?
P093: Which seams in this module does nothing exercise end to end?
P094: I need to write tests for existing code that has none.
P095: I rotate off this codebase Friday - package what my successor needs about the sync engine.
P096: I already have the humps and deep numbers for this function from a subsystem review - which refactor does that shape actually call for?
P097: I just edited one symbol - did I change a contract someone depends on?
P098: Write a limerick about compilers.
P099: Draw me the shape of this codebase - the modules and how they are organized, not a file listing.
P100: The profiler says we are memory-bound in this struct-heavy loop - which fields are actually read together versus how the struct is laid out?
P101: Adding a dependency for CSV parsing - is that already vendored somewhere in here?
P102: Recommend a wine pairing for grilled salmon.
P103: How do I make a pie chart in Excel from this spreadsheet?
P104: Planning a refactor of a suspected god object - where are the seams and the blast radius?
P105: I got a vectorization remark on the scoring kernel while editing - decide whether a diff pays.
P106: How many layers should a good lasagna have, and in what order?
P107: How do I turn on dark mode in my terminal emulator?
P108: How do I vertically center a div inside a flex container?
P109: This endpoint execs user-supplied templates - how exposed are we?
P110: Give me the house pattern for a visitor class before I author mine.
P111: I have a symptom: a crash, wrong output, a failing test, an error string.
P112: Pin the GitHub Action to a commit SHA instead of a tag.
P113: A new MCP server config landed in the repo - inspect its shell blocks before I enable it.
P114: Proofread and review my conference talk abstract.
P115: Before we commit a sprint to this, is the approach even workable given how the code is actually structured?
P116: Is calling fetch_body from the agent cheaper than pulling entire files into context?
P117: About to add a tiny date-formatting util - two minutes tops.
P118: A profiler sample identifies one slow symbol - investigate the measured surface.
P119: If I rename the third parameter of buildIndex, what downstream code breaks?
P120: Run the remarks harness and tell me which missed optimizations sit in hot code.
P121: Users report the export silently produces an empty archive - zero leads on where it happens.
P122: Which HTTP verbs are idempotent according to the spec?
P123: This single function has no coverage - one call to find the seam is enough
P124: Rename a file in git while preserving its history.
P125: One-liner to clamp values - just gonna type it out.
P126: I want just enough of a map to start reading, not a full tour.
P127: Before I pull in a new library for retry-with-backoff, is there already something like that in this codebase?
P128: Book a meeting room for the design review tomorrow.
P129: What plastics are actually accepted for curbside recycling?
P130: List every function above complexity twenty that can eventually reach the database layer.
P131: I wrote a test for the queue - verify it actually reaches the code I meant.
P132: I keep tab-hopping between a dozen files trying to understand one code path - there has to be a faster way to see the shape of this.
P133: Brief the incoming agent on the ingest area - what it does, why, and where it bites.
P134: I fixed the bug; tell me whether my patch made the codebase worse.
P135: Rate the health of our layering after the merge - worse or better?
P136: I am working on ripwire's C++ and clang keeps telling me a call "will not be inlined" - should I change the source or just move on?
P137: This class smells like it does everything - confirm it is a god object and show the seams.
P138: I am starting a multi-symbol feature and need an ordered implementation plan and a size estimate first.
P139: I am landing several parallel agent worktrees - who conflicts and in what order should they land?
P140: Rename the default branch across our repositories.
P141: This function's complexity score looks huge, but half of it sits inside an #ifdef for a platform we do not even build - can I trust the number as reported?
P142: Which tests should I run for this change, and did I run the right ones?
P143: Why is feature X invisible at runtime - is it compiled out behind a flag?
P144: We have a graveyard of old branches nobody remembers the status of - is any of that actually still unmerged and worth rescuing?
P145: A one-file addition with an obvious home, nothing multi-symbol about it
P146: Convert this YAML config to JSON for me.
P147: Right before I open the PR: report only what my change made worse.
P148: Show me functions with complexity above twenty from which the allocator is reachable.
P149: What is a good commit message format for a small team?
P150: I just landed in an unfamiliar repo - what is this codebase and what actually matters here?
P151: Which handlers in src/api have more than ten callers?
P152: The complexity number on this function is high, but I cannot tell if it is a genuine tangle or just a long simple sequence I could split by hand - how risky would splitting it actually be?
P153: Draft the changelog entry for this week's release.
P154: Rough out the work to support incremental compilation - what order, what surface, how much effort?
P155: Jot this down for future sessions: the fixture loader silently caches across tests.
P156: Windsurf integration: which config block do I add, and what safety do the editing verbs promise?
P157: Which server verbs should the agent lean on during a task instead of the CLI flags?
P158: Write a haiku about autumn leaves.
P159: How do I hook this tool up as an MCP server so my coding agent can call it directly?
P160: Clang complains it could not vectorize the radix loop because no reduction was identified - worth chasing?
P161: Upgrade the CI runners to the larger instance size.
P162: Before I touch this shared utility function, I need to know everything that currently calls it.
P163: The build spewed will-not-inline: cost exceeds threshold on the hot comparator - do I care?
P164: Wrapping up - run the last-mile debt check before I tell them it is done.
P165: Is this a dependency mess, and how do I enforce module boundaries in CI?
P166: Writing a summary of this repo area for the next agent to pick up.
P167: Can you optimize this paragraph so it reads faster for a non-technical audience?
P168: Convert this JSON blob to YAML for me.
P169: Where is the dead code in this module? That is the only thing I am asking.
P170: This addition is tiny and I already know which module owns it - is a full plan worth it?
P171: How long should I marinate chicken thighs before grilling?
P172: I need to find every place we retry a network call the old way, not just grep the word retry.
P173: The profiler pins 40 percent of samples in normalizeKeys - dig in from there.
P174: Regenerate the protobuf stubs with the new compiler version.
P175: There is a bug somewhere - wrong output from the exporter - and I do not know where it lives.
P176: Counters put the row scanner memory-bound - which fields fight over cache lines?
P177: Two worktrees touched the tokenizer - which lands first and where do they collide?
P178: Squash my last four commits into one - the history is messy.
P179: Our p99 doubled and the flame profile points at JSON encode - investigate.
P180: I just changed the signature on this helper function - does anything downstream actually depend on the old shape?
P181: Explain Python's walrus operator.
P182: I received a skill file from an external source and want to audit it before activating.
P183: Cross complexity with fan-in and show me symbols where both are high, scoped to core/.
P184: Another team inherits the exporter next sprint - produce the orientation doc.
P185: I expected this function to show up in the ranked output and it is just not there at all - is my ripwire setup broken?
P186: Audit the deserializer path - it eats bytes arriving from the network unchecked.
P187: I think the patch is finished - what did I just make worse?
P188: The nightly job started throwing a null-pointer exception somewhere after Tuesday's deploy.
P189: Before the sprint starts I want an implementation sequence for the notifications feature grounded in real code.
P190: Hand this area off to a teammate.
P191: Explain the rules for a handoff in a 4x100 relay race.
P192: What does this PR actually touch?
P193: Read out flushQueue in full with whatever it calls - I need its contract before touching it.
P194: About to write a quick helper function to normalize paths - should take two minutes.
P195: Before opening the PR, check whether my new code added duplication or dead branches.
P196: Reviewing my own diff now - am I ready to push and is this safe to merge?
P197: The compiler just printed "loop not vectorized" for a function I am editing in ripwire's own source - is that actually worth chasing with a code change?
P198: Here is the crash log with the full stack trace - I would rather not manually walk every frame by hand.
P199: I am wrapping up for the day and want to leave a clean summary of this subsystem for whoever picks it up tomorrow.
P200: How tangled are our module boundaries - any cycles I should lose sleep over?
P201: What does HTTP status 451 mean?
P202: Sizing up an unfamiliar module before editing it.
P203: Periodic sweep: anything sketchy in the skills directory we installed last month?
P204: Where does input validation actually happen in this service?
P205: New to this service as of today - what are the moving parts and where does execution start?
P206: I am going to write a small helper that dedupes the config list.
P207: Give me everything I would need for this ticket in one shot - ranking, the actual code, who calls it, what to test - I do not want to run five separate commands.
P208: I need a fresh pair of reading glasses - what prescription strength ranges are common?
P209: Set this up inside Cursor so the model can query the index without shelling out.
P210: That flake was caused by a stale cache file - worth remembering for the next session, tied to that symbol.
P211: One untested helper, one pass to find what reaches it, done.
P212: I only want the hotspot list for this inherited service, nothing more.
P213: How healthy are the layers here - are there layering violations we should gate in CI?
P214: I keep pasting whole files into context and the budget is bleeding - better way?
P215: Translate these error strings into German for the locale file.
P216: Why does npm install fail with EACCES on my machine?
P217: What is the difference between TCP and UDP?
P218: Convert the images in assets to WebP.
P219: The map that came back looks short - did some files just get dropped for being too big to index?
P220: Let me write a quick retry wrapper around the fetch call.
P221: What does git rebase --onto actually do?
P222: Write up the entry points and the design rationale here so a teammate does not have to re-read the whole module cold.
P223: I need to add a new backend that implements the StorageDriver interface - what does an existing one look like so I do not guess the shape?
P224: Which ref actually still defines this function - I keep finding stale references to it across branches.
P225: How does the request pipeline work in this codebase and where is the retry logic?
P226: I need every function that is both high-complexity and eventually reaches the billing code - a simple caller list cannot express that.
P227: Our imports have become a circular tangle - how bad is it and how do we stop the bleeding?
P228: The flame graph blames string splitting - dig into that code.
P229: Write a friendly README intro paragraph for the project.
P230: New on this team as of Monday; give me the lay of the land before I pick up a ticket.
P231: What is a good stretch routine for lower back pain from sitting all day?
P232: Give me the two-hop callee closure of dispatch but only inside the network cluster.
P233: Find the classes in the storage file with fan-in over five.
P234: Convert 75 degrees Fahrenheit to Celsius.
P235: Three people have feature branches off the same module and we need to land them this week without a mess - what order should they go in?
P236: Wire ripwire into Cursor as an MCP server.
P237: We just lost an hour to a stale lockfile causing a flaky build - I want that written down somewhere it will resurface next time this file comes up.
P238: How do I improve my 5K running pace?
P239: I have a dozen old feature branches and no idea which ones still hold work that never made it to main.
P240: Reviewing a subsystem I did not write - what is gnarly in there?
P241: A teammate sent me an mcp config file from another project - I want it checked over before I let it anywhere near my machine.
P242: This function parses packets straight off the wire - look it over for danger before I ship.
P243: I caught myself about to open more than two files to figure something out.
P244: It worked on Friday and the demo just crashed - what changed underneath?
P245: Before I open this PR I just want to know what got worse, not a whole style lecture.
P246: Write a SQL query listing users who signed up this month.
P247: Is this approach even viable, what should the boundary API look like, and how big is this change?
P248: I have a huge pile of optimization-record YAML from a remarks build of this repo - how do I actually triage it instead of reading a gigabyte of output?
P249: Which high-complexity functions can reach commitTxn? One-hop callers cannot phrase that question.
P250: Show me the chain from handleUpload to the S3 client - the actual route the data takes.
P251: Spell-check the documentation folder.
P252: This ticket touches the cache layer, the eviction policy, and the metrics exporter - how do those three actually tie together?
P253: Track down every write to the retryBudget field before I change its type.
P254: A single question about this inherited module - where is the rot, one answer is enough
P255: Review this codebase - where is the rot?
P256: Throwing this compiler error at you - which of our symbols does it actually implicate?
P257: Enforce that utils never imports from app - and make CI hold the line.
P258: Summarize the storage engine for the teammate taking it over next sprint.
P259: Undo my last three commits but keep the changes staged.
P260: My task touches the scheduler, the allocator and the job queue - how do those three symbols relate?
P261: Is this area safe to touch?
P262: Give me one-call orientation for this task under a token budget - ranking, bodies, callers, tests at once.
P263: We are taking over a service nobody on the team has touched in a year - what should worry us before we start editing it?
P264: What is missing a test here?
P265: My last edit broke the pipeline somewhere - work backwards from my working diff.
P266: What is a good deadbolt brand for a front door?
P267: I am about to open several files just to learn how one thing works.
P268: Exception says KeyError: locale but grepping locale gives 400 hits - find the real site.
P269: My teammate left a bunch of code review remarks I still need to address before this merges.
P270: This feature is small and I already know exactly which file it belongs in - do I still need a plan?
P271: The function I measured has one deep tangle in the middle - which restructuring actually fits that shape?
P272: I am rotating off this project on Friday - put together something the next person can actually read instead of skimming the whole repo.
P273: What separates a good espresso bean from a mediocre one?
P274: If the one person who understands this subsystem left tomorrow, how exposed would we be?
P275: Mute the flaky Slack webhook alert until Monday.
P276: Before I reach for a heavier profiler pass, are there any obvious bad data-layout patterns a plain lint run would already catch?
P277: Someone sent me a SKILL.md to install - screen it before it touches my agent.
P278: What is a good practice test format for a driver's license exam?
P279: What is the plural of octopus - octopi or octopuses?
P280: The index the agent sees feels stale after my rebase - how does the server refresh?
P281: Set up a Python virtualenv pinned to an older interpreter.
P282: Which way is magnetic north from here, and how do I use a compass properly?

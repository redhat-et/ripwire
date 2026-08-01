<!-- TODO: replace OWNER on repo creation -->
[![CI](https://github.com/OWNER/ripwire/actions/workflows/ci.yml/badge.svg)](https://github.com/OWNER/ripwire/actions/workflows/ci.yml)

# ripwire

**The ripgrep of AI context.**

The name is the design. **rip**grep for the retrieval half — point it at a repository and it answers
structural questions in tens of milliseconds, from a call graph it built itself. Trip**wire** for the
honesty half — every count it cannot prove is a total ships labelled a floor, every truncation is
disclosed in the header, and a zero means *none found*, never *none exists*.

`ripwire` is a zero-runtime-dependency C++23 CLI. It crawls a codebase, extracts symbols with
tree-sitter, resolves references into a call graph, ranks that graph with Personalized PageRank, and
streams a deterministic minified XML map to stdout. Around that core sit 102 flags across seven
families — orientation, navigation, detail, quality, self-diagnosis, security, and the knobs that
shape all of them — plus an MCP server, so a coding agent can call any of them mid-task instead of
grepping and reading whole files.

Two runs over the same tree are byte-identical, and a warm run equals a cold one. That is a
contract, enforced by a gate on every push and pull request, not a tendency.

---

## Quickstart

Requirements: CMake 3.24+ and a C++23 compiler. Nothing else — tree-sitter's core, all 15 grammars
and the test framework are vendored under `third_party/deps`, so there is no download step and no
package manager to satisfy.

```bash
git clone https://github.com/OWNER/ripwire.git    # TODO: replace OWNER on repo creation
cd ripwire
cmake -S . -B build && cmake --build build -j
./build/ripwire --help
```

The build is hermetic — prove it with the network off:

```bash
cmake -S . -B build -DFETCHCONTENT_FULLY_DISCONNECTED=ON && cmake --build build -j
```

Do **not** configure a local tree with `-DCMAKE_BUILD_TYPE=Release`: release defines `NDEBUG`, which
compiles the degrade-path alerts out and blinds the gates that assert them. CI builds both flavours
on purpose. See `CONTRIBUTING.md`.

To put it on `PATH`, `./install.sh` builds and installs into a detected prefix (Homebrew's if
present, `~/.local` otherwise; override with `RIPWIRE_INSTALL_PREFIX`).

First commands:

```bash
ripwire .                                  # the ranked map — start here on an unfamiliar repo
ripwire . --for="incremental cache invalidation"   # the task lens: what to touch, ranked
ripwire . --callers=someFunction           # who calls it
ripwire . --test-gate                      # before you commit: which tests must run
```

---

## What it does

Seven families. `./build/ripwire --help` is generated from the binary's own flag table and is
always the authority; `docs/COMMANDS.md` documents every flag with a real invocation and its
recorded output.

| Family | The question | Representative flags |
| --- | --- | --- |
| **understand a codebase cold** | "What is this repo, and what matters in it?" | `--for` · `--tree` · `--lego` · `--exemplar` · `--recall` · `--max-tokens` |
| **navigate / answer a question** | "Who calls this? Is it safe to change? Which tests?" | `--callers` · `--callees` · `--uses` · `--impact` · `--path` · `--connect` · `--affected` · `--situ` · `--test-gate` · `--grep` |
| **zoom the detail ladder** | "Show me more — but only where it pays." | `--detail` · `--pack-signatures` · `--outline` · `--expand` · `--compress` |
| **assess quality / structure** | "Where is the risk, and did I just add some?" | `--hotspots` · `--clones` · `--metrics` · `--deps` · `--lint` · `--quality-delta` · `--edit-check` · `--pr-context` · `--merge-scout` |
| **self-diagnosis** | "Is my setup actually working?" | `--doctor` |
| **security** | "Is this agent skill file safe to install?" | `--scan-skill` · `--scan-skills` |
| **knobs / modes** | shape, format, cache, budget | `--json` · `--format` · `--top-k` · `--token-budget` · `--limit` · `--mcp` |

### Four real examples

Output is minified — one line, no whitespace between tags — so the excerpts below are wrapped for
reading, and each one's leading legend comment is elided where noted. Nothing else is edited.

**1 — Who calls this?** One hop off the call graph, with the honesty marker attached.

```
$ ripwire . --callers=rankGraphTeleport
<callers of="rankGraphTeleport" defs="1" count="6" counts_floor="1">
<s t="fn" n="runEval" p="./src/eval.h:133"/>
<s t="fn" n="rankGraph" p="./src/graph.h:1303"/>
<s t="fn" n="anchoredLexicalRank" p="./src/graph.h:1552"/>
<s t="fn" n="churnRankedGraph" p="./src/main.cpp:7246"/>
<s t="fn" n="runDefaultMap" p="./src/main.cpp:7276"/>
<s t="fn" n="getIndex" p="./src/mcpindex.h:734"/>
</callers>
```

`counts_floor="1"` is the point. Call edges are extracted from source text by name, so dynamic
dispatch, callbacks and macro-generated call sites contribute no edge — `count="6"` is a floor, and
the emitted legend (elided above) says so in full before you read a single row.

**2 — The ranked map.** The default run, capped to three symbols so it fits here:

```
$ ripwire . --top-k=3
<!-- files=837 symbols=6446 edges=8740 shown=3 est_tokens=393 ambiguous=2631 unresolved=662
     precise=3 skipped_oversize=3 order=important-first -->
<r est_tokens="393">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0502"></s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0132">
<c n="buf"/><c n="buf"/><c n="grow"/></s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0125"></s>
</f>
</r>
```

The header is a measurement of the whole corpus, not of the excerpt: `ambiguous=2631` is the
call-graph completeness gauge, and `amb="2"` on a row says two of that symbol's calls hit a name with
several definitions and the resolver guessed. Read the source when which-target matters.

**3 — Before you commit.** `--test-gate` names the obligations and exits 4 while any remain:

```
$ ripwire . --test-gate          # exit code: 4
<test-gate changed="1" impacted="80" tests="2" untested="76" shown_tests="2"
           shown_untested="25" untested_capped="1" script_gates_unmodelled="331" at="9cf0b16f3+dirty">
<t p="./test/adaptivecutshapefix/adaptive_cut_shape_test.cpp" run="bash test/adaptivecutshapecheck.sh"/>
<t p="./test/verify_radix.cpp"/>
<u sym="buildGraph" p="./src/graph.h" ccx="712"/>
<u sym="dispatchMcpLine" p="./src/mcp.h" ccx="428"/>
…
</test-gate>
```

A `run=` attribute appears only when a runner is derivable from real evidence — a test-dir script
whose stem matches the harness, or whose text names it. No `run=` means *not derivable*, never a
guessed suite command. `script_gates_unmodelled="331"` is the same discipline: script-to-binary is
not a call edge, so those gates are invisible to this walk, and the number says so rather than
letting `tests="2"` read as complete.

**4 — Paste the error, don't paraphrase it.** `--from-trace` takes a stack trace, sanitizer report or
compiler error on stdin or from a file, maps its frames onto indexed symbols innermost-first, and
includes the innermost in-corpus body:

```bash
./build/ripwire . --from-trace=asan_report.txt
cmake --build build 2>&1 | ./build/ripwire . --from-trace=-
```

The neighbouring reflexes are the same shape: `--edit-check=SYM` after an edit (did the contract
change, and which callers are now provably incompatible), `--merge-scout=REF1,REF2` before landing
parallel branches, `--pack-task="…"` for ranking, bodies, callers and tests in one budgeted bundle.

---

## Wiring it into a coding agent (MCP)

`ripwire wrap <agent>` prints the recipe for the agent you name. It **prints**; it never edits your
config — you review the line and run it.

```bash
ripwire wrap claude      # → claude mcp add ripwire -- ripwire --mcp
ripwire wrap cursor      # → the mcpServers stanza for .cursor/mcp.json (also: windsurf, gemini)
ripwire wrap codex       # → the TOML stanza for ~/.codex/config.toml
ripwire wrap aider       # → no MCP: a map file, and the aider invocation that reads it
ripwire wrap             # → list the supported agents
```

Before printing, `wrap` security-scans `./skills` and `.agents/skills` with the same engine as
`--scan-skills`: a CRITICAL finding blocks the recipe, warnings print and continue.

The server (`ripwire --mcp` over stdio, or `--listen=HOST:PORT`) exposes 30 verbs: 15 read verbs, 12
flagship-reflex verbs, and 3 span-addressed edit verbs. Read verbs mirror the CLI (`analyze`, `for`,
`grep`, `impact`, `uses`, `lego`, `mentions`, `owners`, `memory_recall`, `situational_awareness`,
`batch`, …); `find_symbol` and `find_referencing_symbols` attach a stable `handle` instead of a body,
so you fetch source only when you actually need it. The edit verbs enforce a safety contract —
staleness refusal, ambiguity refusal, atomic writes. Full reference:
[`skills/ripwire-mcp/`](skills/ripwire-mcp/).

### Agent skills

`skills/` ships seventeen task-shaped skills that tell an agent *which* verb answers the moment it is
in — orienting cold, tracing a call, sizing a refactor, checking a diff, hunting a bug, writing
tests, reviewing security. Install them as symlinks back into this repo (so edits here take effect
immediately):

```bash
skills/install.sh                 # → ~/.claude/skills
skills/install.sh /some/path      # → an explicit destination
```

The script's own header documents its other modes, including Codex and an opt-in advisory
PreToolUse hook. Run `ripwire --scan-skills=skills` first if you would rather read the scanner's
verdict before installing anything.

### Improve this tool with your agent

`prompts/` collects ready-to-paste prompts for pointing a coding agent at this repository itself —
auditing a subsystem, extending a verb, adding a gate, or running the honesty review that every
claim here had to survive. They encode the workflow the project is built with rather than describing
it, so an agent can pick one up and work the same way. Start with the one whose title matches the
change you want; each states its own scope, the gates it must leave green, and what it must not
touch.

---

## Measured claims

Every published number lives in **[`docs/EVALS.md`](docs/EVALS.md)** with the instrument that
produced it, the corpus it ran on, and the in-tree file that pins it. That document also carries a
counterexample section and a list of the claims this project deliberately does *not* publish — read
those first if you are here to check whether the tool is oversold. A representative few:

- **Head-to-head, N = 60 paired instances, zero exclusions** (the first 60 scored held-out LocBench
  instances, same gold and the same metric code for every arm): strict file@10 — ripwire `--for`
  **36.7%**, codebase-memory-mcp 26.7%, graphify 21.7%, Aider repo-map 13.3%. Median wall 0.074 s
  for ripwire *warm with a pre-built index* against Aider's 2.5 s *cold per run* — the multiple is
  real but it is not an apples-to-apples cache state, and `docs/EVALS.md` says so next to the number.
- **LocBench held-out, N = 243 across 78 repositories:** strict file@10 **60.9%**, against **27.6%**
  for the pre-routing baseline — a paired **+33.33pp** with a clustered-bootstrap 95% lower bound of
  **+25.00pp**, bought for +3.4% warm latency and **−39.4%** on the production token ceiling.
- **`--pack-signatures`: 68.4% fewer element bytes** at top-50 (59.1% at top-10, 66.5% at top-100),
  root-neutralised — the corpus-root prefix subtracted from both sides, because it repeats inside
  every element, is charged in both forms, and is not what this verb elides. Quote the top-50 figure:
  the signature payload is top-50 whatever `--top-k` says. `test/showcasecapturecheck.sh` re-derives
  all three on every run and fails if the documentation drifts more than 1.5 points from the binary.
- **Token cost against a naive agent read: 96.0% fewer tokens (24.9×)** across six realistic
  questions. Carry its caveat, which is not small: measured 2026-06-20 on a large private C++ corpus
  — *historical, private, and not publicly reproducible from this tree*. It proves cheaper and
  faster, not better outcomes.

And the counterexamples, which are in-tree and published on purpose:

- **`--grep` costs more tokens than it saves** (+19.7% on one measure, −11.2% on the other). It is
  not a token reducer, and saying so is cheaper than being caught.
- **`--pack-signatures` can make output bigger.** A signature plus its doc comment measured 303 bytes
  against a 158-byte body for one short symbol. The headline is a property of large result sets.
- **PageRank is a bad co-change ranker** — 3.8% recall@5 against 40.3% for plain lexical, and fusing
  the two made it worse. Relatedness is lexical; importance is structural; the tool uses different
  machinery for each because the measurement said to.
- **Strict multi-file localization is hard and stays hard.** Held-out LocBench: single-file gold
  73.4%, multi-file 18.2%. Every corpus shows the same cliff.

---

## Languages

C, C++, Objective-C / Objective-C++, **Metal** (Metal Shading Language, `.metal` — indexed with the
C++ grammar, since MSL is a C++14 dialect, so a dual-compile header's symbols resolve from both the
GPU and CPU halves), Python, TypeScript, JavaScript, Java, Ruby, Bash, Go, Rust, Swift, C#, and JSON
(config keys). Fifteen tree-sitter grammars, all vendored.

Markdown, notebooks, HTML and CSV are indexed as *documents* for `--recall` and the doc↔code edges
behind `--mentions`; Office and PDF join them through an optional bridge.

---

## Documentation

| Need | File |
| --- | --- |
| Every flag, with a real invocation and its recorded output | [`docs/COMMANDS.md`](docs/COMMANDS.md) |
| The authoritative flag list, always current | `./build/ripwire --help` |
| Pipeline, data model, determinism contract, output-honesty contract | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| Every published number, its instrument, and what is *not* published | [`docs/EVALS.md`](docs/EVALS.md) |
| The method, as something transferable | [`docs/METHODOLOGY.md`](docs/METHODOLOGY.md) |
| C++ house style, the G1–G5 guardrails, gate discipline, the submission checklist | [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| Orientation for a coding agent working *on* this repository | [`CLAUDE.md`](CLAUDE.md) / [`AGENTS.md`](AGENTS.md) |
| User-visible capabilities, behaviour changes, known limits | [`CHANGELOG.md`](CHANGELOG.md) |
| Vendored dependencies and their licences | [`THIRD_PARTY.md`](THIRD_PARTY.md) |

If a document disagrees with `--help`, the document is the bug.

---

## How it is verified

The methodology is the product here as much as the binary is. `test/regression.sh` names **311 gate
scripts** and is the authoritative list; `python3 test/pargates.py . ./build/ripwire -j 6` runs the
same set in parallel. On top of them sit the contracts that do not fit a unit test: two runs
byte-identical, warm output identical to cold, output that pipes clean through `xmllint --noout`, a
sanitizer build with `-fno-sanitize-recover=all`, and a differential argv harness that runs a
reference binary and the candidate over every argument vector and requires stdout, stderr and exit
code to match on each.

The house rule behind all of it: **write the gate before the code it measures.** A ranking, a token
estimate and a call graph all look plausible whether or not they are correct.

Contributions are welcome — read [`CONTRIBUTING.md`](CONTRIBUTING.md) first, and
[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). Security reports: [`SECURITY.md`](SECURITY.md).

---

## Licence

Apache License 2.0 — see [`LICENSE`](LICENSE) for the full text.

Copyright 2026 David Brewster

Vendored third-party code keeps its own licence; every dependency is enumerated with its terms in
[`THIRD_PARTY.md`](THIRD_PARTY.md).

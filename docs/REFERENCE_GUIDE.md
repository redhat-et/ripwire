# ripwire reference guide

> **You do not need this guide to use ripwire.** Install it, tell your agent to use it, and the agent takes it from
> there. Come here when you want to know exactly what a command does, what its output means, or where the tool stops
> being right.

*Moved out of `README.md` for 0.7.0 so the front page answers what the tool is, why it is better and how to start
before anything else. Nothing was rewritten in the move; see [`../README.md`](../README.md) for the front page and
[`COMMANDS.md`](COMMANDS.md) for every flag with its recorded output.*

---

> **You do not need this guide to use ripwire.** Install it, tell your agent to use it, and the agent takes it from
> there. Come here when you want to know exactly what a command does, what its output means, or where the tool stops
> being right.

Re-verified against a 0.6.1 build on 2026-09-14.

ripwire reads a source tree and writes a ranked symbol map to standard output: the symbols that matter for a
task, their callers, and the tests that reach them. One binary, and a map that costs nothing to serve — no API
key, no embeddings, no index server. The history-backed commands need `git` on the path and a repository to
read. Two commands reach the network and nothing else does: a git URL in place of a directory, which is
shallow-cloned into a cache, and `--mcp --listen=HOST:PORT`, which binds a socket and is the one mode that
serves other processes (see `--mcp-token` and `--allow-remote-edits` before exposing it).

This guide tells you how to install, operate, and evaluate ripwire. Read `docs/COMMANDS.md` for the
full command reference. Run `ripwire --help` for the current flag list. The binary generates
`--help` from its own flag table, so `--help` is the authority. If this guide disagrees with
`--help`, report this guide as a defect.

<details>
<summary><b>Evidence basis.</b> Fifty years of software-engineering results. 50 repositories and 85 papers are folded. A survey of 240 tools is separate.</summary>

The counts come from `docs/LINEAGE.md`. Counts are current as of 2026-11-26. Nineteen of the folded papers are from 2026, two published in the last two months, and none in the last thirty days. The survey describes 240 tools that contributed no lesson. The two sets are disjoint, so the counts add.

</details>

---

### 1. Purpose and function

ripwire reads a source tree, answers these questions about it, and can apply whole-symbol edits
to it:

**Orient**

- Which symbols matter most in this tree? (`ripwire .`)
- Where do I start on this task, and which code does it touch? (`--for`)
- Can I get the ranking, the key function bodies, their callers and the tests to run in one bounded bundle? (`--pack-task`)
- How do I split this work across several agents without them colliding? (`--partition`, `--plan-lanes`)
- What does the tree look like, directory by directory? (`--tree`)
- Which command answers my question? (`--help-task`)
- What do the project's notes and docs already say about this task? (`--recall`, `--notes`)
- Which existing code should new code imitate? (`--exemplar`)
- What must a new implementation of this interface provide, and who implements it already? (`--lego`)
- Which names does this repo use but never define — its standard library and third-party surface? (`--external-surface`)

**Navigate**

- Who calls this symbol? (`--callers`)
- What does this symbol call? (`--callees`)
- Where is this symbol read, written or imported, not only called? (`--uses`)
- What does a change to this symbol affect, transitively? (`--impact`)
- How does one symbol reach another, following the direction of the calls? (`--path`)
- How do several symbols connect, in any direction? (`--connect`)
- What sits around this symbol in the graph? (`--around`)
- What does this function's body say, with its callees' signatures inline? (`--expand`)
- Where does this text appear, and in which function? (`--grep`)
- Where does this code shape appear? (`--match`)
- How does one variable flow through a function? (`--slice`)
- Which branch's tree defines or mentions this symbol? (`--whereis`)
- Which frames of this stack trace, sanitizer report or compiler error are in my code? (`--from-trace`)
- Is this claim about the code true? (`--verify`)
- Can I ask the call graph a question these commands do not phrase? (`--graph-query`)
- Can I run several of these lookups in one turn? (`--batch`)

**Change it safely**

- Is it safe to delete this symbol? (`--safe-delete`)
- Did my edit change a function's contract, and which callers does that break? (`--edit-check`)
- Can I replace one function's body without reading the whole file? (`--replace-symbol-body`, `--insert-before-symbol`, `--insert-after-symbol`)
- Which tests must run for this change, and what does no test reach? (`--test-gate`)
- Which tests reach these changed files? (`--affected`)
- What is my change's blast radius, and which files usually change with these that I haven't touched? (`--situ`)
- What does this branch touch, and which of those files are risky? (`--pr-context`)
- Do these branches conflict, and in what order should they land? (`--merge-scout`)
- How did the map change between two revisions? (`--map-diff`)

**Quality and structure**

- Which quality problems does this tree have at all, in one ranked report? (`--quality-panel`)
- Where is the risk: complex code that changes often? (`--hotspots`)
- Did my change make the code worse? (`--quality-delta`)
- Where is code duplicated? (`--clones`)
- What does the linter flag? (`--lint`)
- Which cross-module call seams does no test reach? (`--seams`)
- What is built but switched off in this repo? (`--flags`)
- Which environment variables do the shell scripts read, which ones must be set, and with what defaults? (`--flags --json`: each Bash read carries `form=` required, default, unset-default, settest, assign or plain; `colon=` when the expansion has an operator, `default=` when it supplies a default word, and `test=` for a `-n`/`-z` operand)
- How do the modules depend on each other? (`--deps`)
- Does the code follow our layering rules? (`--arch`)
- Which clusters of code belong together? (`--communities`)
- Who knows this code, and where is that knowledge concentrated in one person? (`--owners`)
- Which documented claims are no longer true? (`--doc-drift`)
- Which files did ripwire skip, why, and which indexed files can it therefore not vouch for? (`--skipped`)

**Setup and safety**

- Is my install working? (`--doctor`)
- Is this agent skill file safe to install? (`--scan-skill`)
- Is this whole skills directory safe to install? (`--scan-skills`)

The tool performs five steps in a fixed order:

1. **Ingest.** The tool crawls the tree, parses each file with tree-sitter, and extracts definitions
   and references.
2. **Graph.** The tool resolves each reference to a definition and builds a call graph. The
   resolution is name-based. Section 7 states the limits of this method.
3. **Rank.** The tool ranks the symbols with Personalized PageRank.
4. **Serialize.** The tool writes a minified XML map. The output is deterministic. Section 8 states
   the determinism rules.
5. **Serve.** Two front doors run that map: the command line, and an optional MCP server that a
   coding agent starts on demand.

Every command is a different view of the same graph. The command line and the MCP server use the
same renderer. One computation has one output shape.

### 2. System requirements

| Item | Requirement |
| --- | --- |
| Operating system | macOS (arm64 or x86-64) or Linux (arm64 or x86-64). Native Windows x64 **builds** with both clang-cl and MSVC `cl.exe` — CI builds both on `windows-latest` every full matrix and smoke-tests each binary (`--version`, `ctest`, a real crawl, the two-run byte-identical contract, well-formed XML); the 660-gate suite does not run there, and ASan is compiled but never executed, so treat it as a build, not a validated platform. From 0.6.3 a prebuilt `windows-x64` zip ships as a **preview** ([Windows](#windows)): CI unzips it and compares its output with Linux's byte for byte, but no maintainer runs Windows, so WSL2 remains the fully supported way to run it on a Windows machine. |
| Prebuilt Linux floor | RHEL 8 or later (glibc 2.28) |
| Prebuilt macOS floor | macOS 14 or later, Apple silicon. 0.6.1 is the last release with an Intel macOS binary; on an Intel Mac, pin `RIPWIRE_VERSION=v0.6.1` or build from source. |
| x86-64 floor | x86-64-v3 (Intel Haswell, 2013, or later), for a prebuilt binary and a source build alike |
| Build tools | CMake 3.24 or later, and a C++23 compiler |
| Compilers | clang 16+, AppleClang 15+, or gcc 13+ |
| Build dependencies | None outside the source tree. Every dependency is vendored. |
| Runtime dependencies | None for the map itself. The history-backed commands need `git` on the path, and a repository to read. |
| Network | Not required for a build or for a run. A git URL as the root is the one exception: ripwire shallow-clones it into a cache. |

The history-backed commands are `--hotspots`, `--owners`, `--cochange`, `--quality-delta`, `--dmm`,
`--map-diff`, `--whereis`, `--stray-content`, `--merge-scout`, `--pr-context`, `--situ` and
`--rank-by=churn`. Without git, or outside a repository, none of them returns a thin answer: most
refuse with exit 1 and a named reason, `--dmm` and `--pr-context` return an explicit unavailable
row, and `--map-diff` and `--rank-by=churn` still answer but disclose that the ranking fell back to
uniform.

The build completes with the network off, and `test/dependencypincheck.sh` proves it on every
commit: it runs a real disconnected configure — the step at which FetchContent would fetch — with
`-DFETCHCONTENT_FULLY_DISCONNECTED=ON`.

### 3. Installation

#### 3.1 Install a prebuilt binary

1. Run the installer:

   ```bash
   RIPWIRE_REPO=redhat-et/ripwire bash -c "$(curl -fsSL https://raw.githubusercontent.com/redhat-et/ripwire/main/scripts/install.sh)"
   ```

2. Add the install directory to the path if necessary:

   ```bash
   export PATH="$HOME/.local/bin:$PATH"
   ```

3. Check the version:

   ```bash
   ripwire --version
   ```

The installer downloads the latest GitHub release, verifies the SHA-256 digest, and installs the
binary to `~/.local/bin`. The installer also stages the agent skills under
`~/.local/share/ripwire/skills`. It activates the skills for each agent it finds. It does not edit
your shell profile. It does not register hooks. To register hooks, run
`bash ~/.local/share/ripwire/skills/install.sh --hook`.

On Windows the installer does not apply: download the `windows-x64` zip instead ([Windows](#windows), a preview).

#### 3.2 Build from source

1. Clone the repository:

   ```bash
   git clone https://github.com/redhat-et/ripwire.git
   cd ripwire
   ```

2. Build. Which build you want depends on why you are here.

   **To use the tool**, build the fast binary the released one is built as. `scripts/pgobuild.sh`
   instruments, trains and re-optimizes in one command, into `build_pgo/` — Release, plus link-time
   optimization, plus profile-guided optimization, which is 6-16% faster cold than the default
   build (14-25% against an LTO-off baseline) and byte-identical in output:

   ```bash
   scripts/pgobuild.sh
   ```

   A plain Release build is the shorter path if you would rather skip the training run. It still
   gets link-time optimization; it does not get PGO:

   ```bash
   cmake -S . -B build-release -DCMAKE_BUILD_TYPE=Release
   cmake --build build-release -j
   ```

   **To work on the tool**, build the development tree, with no build type at all:

   ```bash
   cmake -S . -B build
   cmake --build build -j
   ```

3. Test the binary you built:

   ```bash
   ./build_pgo/ripwire .               # or ./build-release/ripwire . or ./build/ripwire .
   ```

**Note:** do not add `-DCMAKE_BUILD_TYPE=Release` to the *development* tree. Release defines
`NDEBUG`. `NDEBUG` removes the `DISCLOSE( msg )` traces at compile time. A gate that
asserts a degrade path then passes without evidence. That is why the two builds above write to two
trees, and why `scripts/pgobuild.sh` writes to a third: CMakeLists refuses a profile-guided build in
`build/` or `asan/` by name, because every gate and bench number in this repository is measured
against those trees.

The continuous-integration pipeline builds both flavors. The plain build proves the degrade paths.
The release build proves the optimizer-visible invariants. Neither flavor replaces the other.

**Note:** make decides what to rebuild by comparing timestamps, so a source that changes *while* a
build runs — most often a `git checkout` under a build in flight — leaves object files that are
newer than the sources they disagree with, and no later incremental build repairs them. After a
branch switch, or whenever sources may have moved under a build, use `cmake --build build
--clean-first -j`. CONTRIBUTING.md records the three ways this has been hit and what each looked
like.

#### 3.3 Install the agent skills

The `skills/` directory holds 17 routable skills, one directory each, holding a `SKILL.md`. The
skills tell an agent which command is correct for each situation. Sixteen are for using the tool;
`ripwire-opt-remarks` is `audience: contributor` and installs only with `--contributor`.
`skills/hermes/` holds one more, Hermes-native, which is why a `find` for `SKILL.md` returns 18.
Install the skills with the script:

```bash
skills/install.sh
skills/install.sh --codex
skills/install.sh --contributor
```

The script links the skills into the configuration directory of the agent. The `--contributor` mode
adds the skill for compiling ripwire itself. Read the header of `skills/install.sh` for all modes.
To check one file before installing it, run `ripwire --scan-skill=FILE`; for a whole directory, run
`ripwire --scan-skills=DIR`. `ripwire wrap` runs that scan itself and refuses to wire an agent when
it finds a CRITICAL, unless you pass `--force`.

#### 3.4 Register the MCP server (optional)

The command line is the primary interface. The MCP server is the optional second interface. The MCP
server exposes 33 MCP verbs. The verb schemas reside in the agent context for every session. For
this reason, register the MCP server only when you need it.

`ripwire wrap <agent>` prints the recipe for one agent — `claude`, `cursor`, `codex`, `aider` and
others — and `ripwire wrap --all` prints one for every agent it detects. For Claude Code it
recommends the command line over the server, for the reason above.

The server is a standard input and output MCP process. The complete configuration is:

```json
{
  "mcpServers": {
    "ripwire": { "command": "ripwire", "args": ["--mcp"] }
  }
}
```

To list fewer tools, add `--mcp-tools=` to the server's arguments: a comma list of tool names and/or the `core`
profile (explore, batch, from_trace, impact, uses, fetch_body, edit_check, quality_delta, the loop the server's own
instructions teach). A client that loads every tool schema at session start then pays for 8 schemas instead of 33
(`tools/list` measured at 13,834 bytes instead of 46,368). A call to a tool that is not listed is refused with the
flag that enables it. The list is not access control: `batch` sub-queries still reach hidden verbs. `ripwire wrap AGENT --mcp-tools=core` writes the flag
into the recipe it prints. The default stays the full catalog, except in `ripwire wrap claude`'s recipe, which passes
`--mcp-tools=no-edit` (every tool but the three edit twins: Claude Code must Read before it edits, so it takes a symbol's
line range from ripwire, Reads that range, and uses its native Edit; `--mcp-tools=full` restores them).

For a socket instead of standard input and output, run `ripwire --listen=HOST:PORT`. A non-loopback
bind requires `--mcp-token`. The three edit verbs are disabled on a remote bind unless you pass
`--allow-remote-edits`. The socket speaks plain HTTP with no TLS, so on a non-loopback bind the bearer token and
every request cross the network in the clear: put a TLS-terminating reverse proxy in front of it.

### 4. First use

> **ripwire is AI-driven today.** By default, every command prints compact XML sized for a coding agent to read, not for a person
> scanning a terminal. The commands in this section are the ones your agent runs. Human-friendly use is on the
> roadmap: output a person can read, and more convenient input for common coding cases.

#### 4.1 Make the first map

Change to the repository. Run the following command:

```bash
ripwire .   # orient once on an unfamiliar repository
```

The command writes the ranked map: the main subsystems, the entry points, the most important symbols,
and a count of every file the ranking left out. Read it once per session, then ask lean questions
(`--for`, `--expand`, `--callers`). If your context is tight, `--max-tokens=N` keeps only the head of
the map; the cut is disclosed (`shown=` of `symbols=`), but it can drop what you need, so prefer the
full map when it fits.

The first call on a tree parses it; every call after that reads a cache and answers in a fraction of
the time. Judge the cost of the tool by the second call, not the first. If the first call fails, or
looks wrong, run `ripwire . --doctor`: it checks the binary, the grammars, the cache and the git
identity of the index, and says which one is at fault.

#### 4.2 Use the common commands

| Task | Command |
| --- | --- |
| Orient in a new tree | `ripwire .` |
| Prepare for a task | `ripwire . --for="<task description>"` |
| Get everything for one task in a single call | `ripwire . --pack-task="<task description>"` |
| Ask which command to run | `ripwire . --help-task="<task description>"` |
| Find a symbol's callers | `ripwire . --callers=SYM` |
| Find the callees | `ripwire . --callees=SYM` |
| Measure the blast radius | `ripwire . --impact=SYM` |
| List the use sites | `ripwire . --uses=SYM` |
| Read one function body | `ripwire . --expand=SYM` |
| Find the tests for a change | `ripwire . --test-gate` |
| Check an edit's contract | `ripwire . --edit-check=SYM` |
| Check what a change made worse | `ripwire . --quality-delta` |
| Find the pattern to imitate before writing | `ripwire . --exemplar="<what you are writing>"` |
| Review the current diff | `ripwire . --situ` |
| Review a branch against a base | `ripwire . --pr-context=BASEREF` |
| Read a stack trace | `ripwire . --from-trace=FILE` |
| Inspect code quality | `ripwire . --quality-panel` |
| Locate a literal, or a regex | `ripwire . --grep=STRING`, `ripwire . --regex=PAT` |
| Search the documents | `ripwire . --recall="<task>"` |

### 5. Command families

The `--help` output groups 203 long flags advertised in `--help` into seven families. The `--help=`
column below is the argument that prints one family: `ripwire --help=navigate`. `ripwire
--help=--FLAG` prints one flag's full text — the caveats, the units, what it refuses and why.
`ripwire --help=all` is the whole catalog, about 46,000 tokens.

| Family | `--help=` | Purpose | Representative flags |
| --- | --- | --- | --- |
| Understand a codebase cold | `understand` | What is this repository, and what matters? | `--for`, `--help-task`, `--tree`, `--lego`, `--exemplar`, `--recall`, `--top-k`, `--token-budget`, `--max-tokens` |
| Navigate and answer a question | `navigate` | Who calls this, and is it safe to change? | `--callers`, `--callees`, `--uses`, `--impact`, `--path`, `--connect`, `--situ`, `--test-gate`, `--grep` |
| Zoom the detail ladder | `zoom` | Show more detail only where it pays | `--detail`, `--pack-signatures`, `--outline`, `--expand`, `--compress` |
| Assess quality and structure | `quality` | Where is the risk, and did a change add risk? | `--quality-panel`, `--hotspots`, `--clones`, `--metrics`, `--deps`, `--lint`, `--quality-delta`, `--edit-check`, `--pr-context`, `--merge-scout` |
| Self-diagnosis | `self-diagnosis` | Is the setup correct? | `--doctor` |
| Security | `security` | Is this agent skill file safe to install? | `--scan-skill`, `--scan-skills` |
| Knobs and modes | `knobs` | Shape, format, cache, and budget | `--json`, `--format`, `--mcp` |

The `--help=` argument matches on a substring of the family's own name, so the family titles in the
first column are not themselves valid arguments.

Not sure which command answers the task? Run `ripwire . --help-task="<task in words>"`. The command
returns one recommended command, or it abstains when the evidence is thin. The command gives advice
only. It does not run the recommendation. A short bare word — a lone letter, a SCREAMING name, or an
ordinary word that happens to match an indexed name (django's `F`, for instance) — does not resolve on
its own; only genuine identifier shape does (camelCase, snake_case, `::`/`.`). Mark it as code in the
task text — backtick it or write it in call form, e.g. `` `F` `` or `F()` — to route on it by name.

### 6. Output format

**You do not have to learn the schema, because the document carries it.** Every answer opens with a
legend comment defining each attribute it uses, including what each count does and does not include.
The map is `<r>` root, `<f p="PATH">` files, `<s t n k>` symbols, `<c n>` call edges; each answering
command wraps its rows in an element named for the verb — `<callers>`, `<uses>`, `<pr-context>`,
`<dmm>`, `<skillscan>`.

Two runs over one tree produce the same bytes (except a disclosed history cut, whose prefix moves with machine load), and every attribute and text node is XML-escaped, so
`operator<` and a path containing `&` round-trip: `ripwire . | xmllint --noout -` is a gate here.
`docs/ARCHITECTURE.md` has the schema and the streaming writer behind it.

#### 6.1 Output example

```bash
ripwire . --callers=rankGraphTeleport
```

The leading legend comment is elided here; the line numbers are a capture and move as files grow:

```xml
<callers of="rankGraphTeleport" defs="1" count="7" root="." hop_tested="0" hop_untested="7" graph_ambiguous="7827" graph_unresolved="4865" graph_unindexed="218" counts_floor="1" next="--uses=rankGraphTeleport">
<s t="fn" n="getIndex" p="src/mcpindex.h:1165" sites_at="1268"/>
<s t="fn" n="rankGraph" p="src/graph.h:7965" sites_at="7968"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:8611" sites_at="8662"/>
<s t="fn" n="runEval" p="src/eval.h:171" sites_at="325"/>
<s t="fn" n="churnDecayRanking" p="src/main.cpp:1383" sites_at="1397"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:1422" sites_at="1436 1437 1451"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1632" sites_at="1752"/>
</callers>
```

`counts_floor="1"` says every count on that row is a floor, never a total. `next=` is the one
follow-up command worth pasting.

#### 6.2 Exit codes

This is the part to wire into a script.

| Code | Meaning |
| --- | --- |
| 0 | The command completed. |
| 1 | The command refused the request. A refusal names the reason on stderr. When `--callers`, `--callees`, `--uses`, `--impact` or `--path` refuse a selector that matches no indexed definition, they also print an answer on stdout: the verb's element with `found="0"` and the name to retry with. |
| 2 | A policy gate fired: `--arch` found a layering violation, `--scan-skill` found a CRITICAL, `--quality-delta` found new debt. |
| 3 | The output exceeded the token budget that you set. |
| 4 | `--test-gate` found an open obligation. |
| 5 | The memory guard stopped the run: over `--max-memory` (default 65% of the machine's memory) with no partial answer possible, or a verb other than the default map facing a partial index. One stderr line names the limit and the override. |

#### 6.3 JSON output

`--json` emits JSON instead of XML, with keys mirroring the XML attribute names one to one. It is an
allow-list: the default map, `--for`, `--pack-task`, `--callers`, `--callees`, `--impact`,
`--quality-delta`, `--test-gate`, `--metrics`, `--flags`, and `--plan-lanes`, which is JSON-native. Every other
verb refuses on stderr with exit 1 rather than silently falling back to XML, so a verb added tomorrow
refuses by default.

### 7. Accuracy and disclosure rules

The call graph is extracted from source text by name. The tool does not have a type system or a
compiler. These limits follow:

- A virtual call produces one edge per candidate in the receiver's inheritance cone — its static
  type, that type's ancestors and its descendants — and not one edge to the target it dispatches to
  at run time. Each such edge carries `prov="split"`. When the receiver's static type is unknown,
  the candidate set is not narrowed at all.
- A callback through a function pointer contributes an edge in one case. One function must be bound
  to the variable in scope, the variable must not escape, and the variable's type must be provably a
  function pointer: a typedef or declarator in the same file proves it, a typedef in a header is
  missed, and an `auto` or template type is read as unpinned and kept.
- A macro-generated call site contributes an edge only when the tool indexes the function-like
  `#define`.
- A name that has several definitions at the same resolution tier produces one edge per candidate.
  Each edge carries the weight `1/k`. The symbol carries `amb="K"`. The header totals the events in
  `ambiguous=`.
- Two further gauges sit beside `ambiguous=`. `unresolved=` counts calls left with no edge and no
  proof that the target is outside the tree: every same-named in-repo definition is language-filtered
  or out of the language's lookup (a method for a receiverless call, another Go package). `external=`
  counts the calls the language does prove are outside (a builtin or global, an outside import).
  `unindexed=` counts files no grammar could read, whose calls raise neither of the other two.

The output uses these disclosure rules without exception:

- **A zero is a measurement.** A zero means "none found". A zero never means "none exists".
- **A floor is labelled.** A count that cannot be a total carries `counts_floor="1"`.
- **A truncation is disclosed.** The element that truncated carries `total=`, `shown=` and
  `capped=`. A document that a budget cut carries its own marker and a `next=` step.
- **A refusal is not a zero.** A selector that names nothing indexed refuses with a did-you-mean
  suggestion computed from an edit distance. A query that resolves and selects nothing reports
  `count="0"`.
- **An estimate is labelled.** Token estimates are calibrated approximations. They are not exact
  counts for every model.
- **Counting units are named.** `--callers` counts distinct symbols. `--uses` counts
  use sites. The two numbers differ by design.

Use these methods when a disclosure says the answer is incomplete:

1. Use `--skipped` to see which files are missing from the index, and which indexed answers it
   therefore cannot vouch for.
2. Use `--expand=SYM` to read the body.
3. Use `--uses=SYM` and `--impact=SYM` to measure the blast radius.
4. Use `--verify="CLAIM"` to test one claim about the code: confirmed, refuted, or not-established.
5. Use `--scip=FILE` to supply a compiler-grade index. A precise index replaces the name-based edges
   and marks the affected edges with `prov="scip"`. A path that is missing, empty or not a regular file
   causes a refusal (exit 1). A corrupt index causes a fallback to the name-based edges and a warning on
   standard error. Neither case is silent.

### 8. Determinism

The determinism contract is byte-identity. One tree produces one byte sequence on every run. The
contract holds under four rules:

1. The crawl sorts all candidate paths before it assigns symbol identifiers.
2. Every global reduction folds fixed contiguous blocks in index order. No reduction uses an atomic
   floating-point add.
3. The rank vector uses type `double`. Edges stay `float`; the multiplication and the accumulation
   promote to `double`.
4. The PageRank translation unit compiles without floating-point reassociation: `-fno-fast-math`,
   set on `src/pagerank.cpp` alone.

Thread count and thread timing never change the output. Neither does the output emitter: the
`std::print` build and the `std::format` fallback emit the same bytes, which
`test/printffmtparitycheck.sh` asserts directly — the two disagree on float formatting by default,
and nothing else in the suite would see it.

Continuous integration runs the two-run byte diff on every leg — macOS on both architectures, Linux,
a RHEL 9 userland, both build flavours, and the fallback-emitter build — so the contract is checked
on every commit, not only when you check it. To re-check it on your own tree:

```bash
t=$(mktemp -d)           # outside the tree: an output written inside it is crawled by the next run
ripwire . > "$t/a"
ripwire . > "$t/b"
diff -q "$t/a" "$t/b"    # two runs, byte-identical
ripwire . --no-cache > "$t/c"
diff -q "$t/a" "$t/c"    # and the warm run equals the cold one
```

Neither diff may report a difference.

### 9. Verification and quality control

`test/regression.sh` names **every gate script**. It is the authoritative list.

**The gate scripts** hold five contracts that a unit test cannot hold.

1. Two runs over one tree are byte-identical — the determinism gate of section 8, run on every CI leg — except a disclosed history cut, whose prefix moves with machine load.
2. A warm run equals a cold run — the cache-transparency gates.
3. Every XML output is well-formed. The verification command is `xmllint --noout`.
4. The sanitizer build uses `-fno-sanitize-recover=all`, without which a run with undefined behaviour
   still exits 0. AddressSanitizer, UndefinedBehaviorSanitizer and LeakSanitizer are part of the
   guardrails:

   ```bash
   cmake -S . -B asan -DRIPWIRE_ASAN=ON && cmake --build asan -j
   LSAN_OPTIONS=suppressions=lsan_suppressions.txt ./asan/ripwire <dir> >/dev/null
   ```

5. `test/argvdiffcheck.sh` runs a reference binary and the candidate binary over an argument matrix.
   Standard output, standard error, and the exit code must match for every vector.

Run the full gate suite in the foreground:

```bash
python3 test/pargates.py . ./build/ripwire -j 6
```

A new gate script must be added to `test/regression.sh` in the same change. The gate
`test/manifestcheck.sh` enforces this rule.

Another gate derives the cap inventory. At the counts snapshot 2026-11-15 the tool had 431 compile-time caps and 10 ranking parameters.
`docs/LIMITS.md` lists each cap, its value, and whether the file discloses a truncation when the cap
fires, and `python3 docs/limits_build.py --check` proves that list against `src/`. `docs/TUNING.md`
lists the measured cost of the caps the sweep has measured, and names the ones it has not.

### 10. Quality evaluation

`ripwire . --quality-panel` joins six independent evidence families:

| Family | Question | Supporting command |
| --- | --- | --- |
| Structural | Shape: complexity, size, nesting, parameters, local variables | `--metrics` |
| Lexical | Identifier text: the naming rules | `--lint`, `--naming-consistency` |
| Confusion | Syntactic idiom: the confusion rules | `--lint` |
| Historical | Git change frequency | `--hotspots` |
| Colocation | How much code a reader must read outside the current file | `--context-ratio` |
| State | Mutable state that a change can disturb at a distance | `--nonlocal-state` |

The panel ranks a row by the count of families that agree. It does not blend the families into one
score. A row appears at an agreement count of two or more.

That is the default preset. `--quality-panel=strict` keeps only the four families measured steadily
enough to gate on, still at two: historical and colocation are out because each is a fixed-size
worst-40 cut over a ranking whose population moves, so both re-shuffle on code that did not change.
`--quality-panel=lenient` takes all six at one, which is a reading order rather than a verdict. A
family that could not be measured on this tree reports UNAVAILABLE, never "did not fire".

`--quality-delta` reports only the properties that the working tree made worse against a baseline.
`--test-gate` names the tests that must run. `--edit-check` compares an edited symbol against git
HEAD. `--safe-delete=SYM` composes the callers, the blast radius, the use sites, and the dead-code
shape into one risk report.

### 11. Agent integration

The command line is the recommended interface. An agent that can run shell commands needs no
registration. The installer adds the skills. The skills teach the agent when to use each command.

`ripwire wrap <agent>` prints the wiring recipe for one agent. The command prints the recipe. It
does not edit a configuration file. Run `ripwire wrap --all` to detect every installed agent and to
print each recipe. The recipe differs by agent, and `wrap` decides which interface to recommend: an
agent that can run shell commands gets the command line, and one that cannot gets the MCP server.

```bash
ripwire wrap claude
ripwire wrap codex
ripwire wrap cursor
ripwire wrap windsurf
ripwire wrap gemini
ripwire wrap opencode
ripwire wrap openclaw
ripwire wrap hermes
ripwire wrap aider
```

The write verbs are `--replace-symbol-body=SYM`, `--insert-before-symbol=SYM`, and
`--insert-after-symbol=SYM`. Supply the new text with `--edit-payload=FILE` or `--edit-payload=-`
for standard input.

**The payload replaces the whole definition, signature included — not the braced body.** A payload
that carries only `{ … }` deletes the signature. The tool discloses that in the receipt, as
`post_check_unavailable`, rather than refusing. One trailing newline on the payload folds into the
newline already after the span, which a heredoc or `echo` always adds; a second newline is kept and
is reported as `trailing_newline_folded`.

**Every write returns a receipt, so an agent never re-reads the file.** The receipt carries the
edited region with surrounding context, the new `blob_sha`, the contract check against the edited
symbol, the tests to run, and one `next=` step:

```
ripwire edit: applied atomically; receipt carries region, blob_sha, edit_check, tests_to_run; next: --test-gate=t.cpp
```

The CLI write verbs and the MCP write verbs use the same safety contract:

- A stale file hash causes a refusal.
- An ambiguous selector causes a refusal.
- A symlink target causes a refusal.
- The tool preserves the file mode.
- The tool writes a temporary file, synchronizes it, and renames it over the target. A failure leaves
  the original file unchanged.

### 12. Supported languages and formats

The tool vendors 27 tree-sitter grammars. A table maps a file extension to a grammar and a query
file. One query engine runs over every language. A new language requires a vendored grammar, a query
file, and one row in the extension table.

| Language or format | Extensions | Notes |
| --- | --- | --- |
| C | `.c`, `.h` | |
| C++ | `.cc`, `.cpp`, `.cxx`, `.hpp`, and others | Qualified calls and explicit template calls resolve in a precise tier. |
| Objective-C / Objective-C++ | `.m`, `.mm` | |
| Metal (MSL) | `.metal` | Indexed with the C++ grammar. |
| CUDA | `.cu`, `.cuh` | `<<<>>>` launch sites are call edges. |
| Python | `.py` | |
| TypeScript / JavaScript | `.ts`, `.tsx`, `.mts`, `.cts`, `.js`, `.jsx`, `.mjs`, `.cjs` | Named imports and default imports resolve. One vendored dependency supplies two of the 27 grammars, `typescript` and `tsx`. `.astro` frontmatter rides this same `Lang` — see its own row below. |
| Java | `.java` | Qualified `new` calls resolve in a precise tier. |
| Kotlin | `.kt` | Shares one call graph with Java. A file with string templates past 128 levels is refused and listed by `--skipped`. |
| Clojure | `.clj`, `.cljs`, `.cljc`, `.bb` | Structural defining forms and direct symbolic list-head calls; quoted/discarded syntax is excluded. Macro expansion and namespace/import resolution are not inferred. |
| Ruby | `.rb` | Superclasses, mixins, `autoload`, and constant receivers are read. |
| PHP | `.php`, `.phtml` | Dynamic dispatch is a stated floor. |
| Lua | `.lua` | Metatable inheritance produces no inheritance edge. `require` is a function call. A string-literal `require` that names exactly one file in the tree adds a dependency edge. |
| Dart | `.dart` | A function body is a sibling of the signature. The capture extends the span through the body. |
| Elixir | `.ex`, `.exs` | Modules, protocols, implementations, functions, macros, guards, and delegates are indexed. |
| Swift | `.swift` | |
| C# | `.cs` | The `?.` family resolves in a precise tier. |
| Go | `.go` | Qualified calls are rejected and fenced, not guessed. |
| Rust | `.rs` | Scoped, turbofish, and `Self::` calls resolve in a precise tier. |
| Bash | `.sh`, `.bash` | |
| Astro | `.astro` | **Frontmatter only.** The `---`-fenced block is parsed as TypeScript, through one `ts_parser_set_included_ranges` call; the template half — including `<script>` bodies and `{…}` interpolations — is NOT indexed, so a call made only from the template produces no edge. An `.astro` file reports `lang="ts"` because it rides `Lang::TypeScript` (that is what lets a frontmatter call resolve into a `.ts` service). A top-level frontmatter call is module-scope code, so `--callers` names `<file-scope>` rather than a function. No Astro grammar is vendored. |
| GDScript | `.gd` | A file is a class body: `class_name` names it and file-scope `func`/`var` are its members. A signal is indexed as a member. `preload`/`load` produce no dependency edge. `.tscn`, `.tres`, and `.gdshader` are not indexed. |
| JSON | `.json` | Config keys become symbols. The lane emits no call edges. |
| Protocol Buffers | `.proto` | A schema: messages (and proto2 groups), enums, oneofs, services, rpcs and enum values are definitions, nested ones scoped to their owner. No call or file edges; fields, `package`, `import`, `option` and `extend` are not read. A `--for` name that resolves to no definition but names generated code (`use x_pb::m::outer::Leaf as X`, Go `Outer_Leaf`) links to the `.proto` definition by name only (`<rung n="gen" via="name">`), never as a proven edge. |
| TOML | `.toml` | A table header is one symbol. Keys below it are one level down. |
| YAML | `.yml`, `.yaml` | Mapping depth 2 is the cut. Sequence levels are transparent. |
| Markdown | `.md`, `.markdown` | Every heading is a section symbol. The span runs to the next heading of the same or higher level. |

Notebooks, HTML, and CSV files are indexed as documents for `--recall` and `--mentions`.

### 13. Performance

| Operation | Scale | Measured result |
| --- | --- | --- |
| Cold parse | llvm-project, 182,555 files | 194.1 s to 155.6 s of CPU, measured 2026-08-08, before the performance work in 0.6.0 |
| Cold parse and answer | This repository | Parse and query retire 3.2 to 3.5 instructions per cycle |
| Warm run, cache load | The same tree | 52.3 M instructions in place of the cold run's dominant 8.74 B phase: about 167 times fewer |

The per-scope hardware-counter table behind these rows is in
[Where its own cycles go](#where-its-own-cycles-go--hardware-counters-per-scope).

One process answers a query. The tool starts no daemon and holds no server connection. The parse
cache is keyed by file content hash and a parser version. An extraction change bumps the version and
causes one cold re-parse. A gate asserts that the warm output is byte-identical to the cold output.

Measured results with their instruments and corpora are in `docs/EVALS.md`. The document also lists
the counterexamples that this project publishes against itself. For example, one comparison ran
graphify 0.9.34 with `--code-only --no-cluster`. The measurement is in `bench/headtohead/r4-2026-08-06/`.

### 14. Known limits

**What the analysis cannot see**

- The call graph is name-based, with no type system and no compiler. A virtual call resolves to every
  candidate in the receiver's inheritance cone rather than to the one target it dispatches to at run
  time, and a callback, a macro expansion or a duck-typed call can produce no edge at all. Section 7
  states the disclosure rules; `--scip=FILE` supplies a compiler-grade index where precision matters.
- Test coverage is read from call edges out of indexed test symbols, so a shell or command-line test
  that runs a built binary as a subprocess is invisible, and a repository tested that way reads as
  untested. Such a harness is labelled `harness=script` with `reaches=0`, which is a stated limit
  rather than a measurement. This repository's own gate suite has exactly that shape.
- Multi-file localization is the weakest measured result. The published metric is Strict@k — every
  gold file of a task inside the top k — and the tool finds one gold file far more often than it
  finds all of them. `docs/EVALS.md` carries the numbers, the 560-instance dataset and the split.
- The config and prose lanes index symbols but emit no call edges: JSON, TOML, YAML and Markdown, and
  the notebooks, HTML and CSV files read as documents for `--recall` and `--mentions`. They answer
  retrieval questions and never appear in a call-graph answer.
- Churn, ownership and co-change need real git history. A shallow clone reports every file as one
  commit.
- PHP dynamic dispatch and Lua metatable inheritance are floors, not complete answers.

**What the crawl skips, and how to change it**

- Files over 4 MB: `--max-file-size=N[K|M|G]`.
- JSON files over 256 KB, and YAML files over 512 KB.
- Paths covered by `.gitignore`: `--no-ignore`.
- Every symlink, whether it points at a file or a directory. A symlinked source file is not indexed
  at all, so a tree that reaches its sources through symlinks reads as if they were not there.
- `--skipped` names every file that was skipped, why, and which indexed answers cannot vouch for it.

**When a verb is not the right tool**

- `--grep` can cost more tokens than a plain grep on a small result set.
- `--pack-signatures` can be larger than the body when a symbol is short.
- A multi-root run merges 2 to 16 checkouts into one graph, but `--quality-delta`, `--test-gate`,
  `--arch` baselines, `--pr-context` and the evaluation verbs stay single-root. Run those per root.

### 15. Documentation

Every document this project publishes is listed under [Documentation](#documentation) below, with
the question each one answers. Two of them matter while you are reading this guide: `docs/COMMANDS.md`
gives every flag a real invocation and its recorded output, and `ripwire --help` is the authority
whenever a document disagrees with it.

The presentation rebuilds from `present/deck5_ripwire_build.js`. The preprint draft is in
`paper/PREPRINT.md`. The method is not submitted for peer review. Its tables name the measurement
files under `bench/`.

### 16. Improvement

`prompts/` holds thirteen **self-contained orchestrator prompts**. Each prompt is a workflow that a
coding agent can run against this repository. Each prompt writes a plan and stops for your approval
before it runs a command. Build the binary first. The prompts measure against the binary.

The prompts cover a full audit, a gap analysis from real use, a capture audit, a head-to-head
comparison, a ranking evaluation, a language improvement pass, a zero-context onboarding study, a
sibling sweep, a command tour, a presentation build, adding a new language, a quality-panel
calibration round, and a COBOL corpus measurement. The index is `prompts/README.md`.

If the tool answers incorrectly on your codebase, run `prompts/improve-for-my-language.md`. The
prompt harvests your session transcript and produces one finding per event with its evidence. Open
an issue with the result.

### 17. License

Apache License 2.0. See `LICENSE` for the full text.

Copyright 2026 David Brewster

Vendored third-party code keeps its own license. `THIRD_PARTY.md` lists every dependency and its
terms.


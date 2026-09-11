<p align="center"><img src="docs/assets/banner.svg" alt="ripwire: the ripgrep of AI context" width="880"></p>

[![CI](https://github.com/redhat-et/ripwire/actions/workflows/ci.yml/badge.svg)](https://github.com/redhat-et/ripwire/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/redhat-et/ripwire)](https://github.com/redhat-et/ripwire/releases/latest)
[![Licence](https://img.shields.io/badge/licence-Apache%202.0-blue.svg)](LICENSE)
[![Standard](https://img.shields.io/badge/C%2B%2B-23-blue.svg)](CONTRIBUTING.md)
[![Runtime dependencies](https://img.shields.io/badge/runtime%20dependencies-none-blue.svg)](THIRD_PARTY.md)
[![Slides](https://img.shields.io/badge/slides-the%20showcase%20deck-56d6e8.svg)](present/ripwire-showcase.pdf)

# ripwire

Publication date: 2026-09-12

ripwire analyzes a source tree. The tool writes a ranked symbol map to standard output. The map
shows the symbols that matter for a task, the callers of those symbols, and the tests that reach
them. The tool is one binary. It has no runtime dependencies. It does not use a network and it does
not use a background service.

This guide tells you how to install, operate, and evaluate ripwire. Read `docs/COMMANDS.md` for the
full command reference. Run `./build/ripwire --help` for the current flag list. The binary generates
`--help` from its own flag table, so `--help` is the authority. If this guide disagrees with
`--help`, report this guide as a defect.

<details>
<summary><b>Evidence basis.</b> Fifty years of software-engineering results. 49 repositories and 70 papers are folded. A survey of 237 tools is separate.</summary>

The counts come from `docs/LINEAGE.md`. Counts are current as of 2026-09-08. Seventeen of the folded papers are from 2026, seven published in the last two months, and three in the last thirty days. This project folds 49 repositories and 70 papers into one executable. The survey describes 237 tools that contributed no lesson. The two sets are disjoint, so the counts add.

</details>

---

## 1. Purpose and function

ripwire reads a source tree and answers these questions:

- Which symbols are important in this tree?
- Who calls this symbol, and what does a change to it affect?
- Which tests must run before a change is complete?
- Where is the risk in this code, and did a change make the risk worse?

The tool performs five steps in a fixed order:

1. **Ingest.** The tool crawls the tree, parses each file with tree-sitter, and extracts definitions
   and references.
2. **Graph.** The tool resolves each reference to a definition and builds a call graph. The
   resolution is name-based. Section 7 states the limits of this method.
3. **Rank.** The tool ranks the symbols with Personalized PageRank.
4. **Serialize.** The tool writes a minified XML map. The output is deterministic. Section 8 states
   the determinism rules.
5. **Serve.** The command line reads the map. An optional MCP server exposes the same computation
   to a coding agent.

Every command is a different view of the same graph. The command line and the MCP server use the
same renderer. One computation has one output shape.

## 2. System requirements

| Item | Requirement |
| --- | --- |
| Operating system | macOS (arm64 or x86-64) or Linux (arm64 or x86-64) |
| Prebuilt Linux floor | RHEL 8 or later |
| Prebuilt x86-64 floor | x86-64-v3 (Intel Haswell, 2013, or later) |
| Build tools | CMake 3.24 or later, and a C++23 compiler |
| Compilers | clang 16+, AppleClang 15+, gcc 13+, or MSVC 19.36+ |
| Dependencies | None outside the source tree. Every dependency is vendored. |
| Network | Not required for a build or for a run. |

The build completes with the network off. Use `-DFETCHCONTENT_FULLY_DISCONNECTED=ON` to prove this
condition.

## 3. Installation

### 3.1 Install a prebuilt binary

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
your shell profile. It does not register hooks unless you pass an explicit `--hook` option.

### 3.2 Build from source

1. Clone the repository:

   ```bash
   git clone https://github.com/redhat-et/ripwire.git
   cd ripwire
   ```

2. Configure and build the development binary:

   ```bash
   cmake -S . -B build
   cmake --build build -j
   ```

3. Test the binary:

   ```bash
   ./build/ripwire .
   ```

**Note:** Do not configure the development tree with `-DCMAKE_BUILD_TYPE=Release`. Release defines
`NDEBUG`. `NDEBUG` removes the `DEGRADED_PATH_ALERT` diagnostics at compile time. A gate that
asserts a degrade path then passes without evidence. Use a separate tree for a release build:

```bash
cmake -S . -B build-release -DCMAKE_BUILD_TYPE=Release
cmake --build build-release -j
```

The continuous-integration pipeline builds both flavors. The plain build proves the degrade paths.
The release build proves the optimizer-visible invariants. Neither flavor replaces the other.

### 3.3 Install the agent skills

The `skills/` directory holds 18 task-shaped skill files. The skills tell an agent which command is
correct for each situation. Install the skills with the script:

```bash
skills/install.sh
skills/install.sh --codex
skills/install.sh --contributor
```

The script links the skills into the configuration directory of the agent. The `--contributor` mode
adds the skill for compiling ripwire itself. Read the header of `skills/install.sh` for all modes.
To check a skill file before installation, run `ripwire --scan-skills`.

### 3.4 Register the MCP server (optional)

The command line is the primary interface. The MCP server is the optional second interface. The MCP
server exposes 31 MCP verbs. The verb schemas reside in the agent context for every session. For
this reason, register the MCP server only when you need it.

The server is a standard input and output MCP process. The complete configuration is:

```json
{
  "mcpServers": {
    "ripwire": { "command": "ripwire", "args": ["--mcp"] }
  }
}
```

For a socket instead of standard input and output, run `ripwire --listen=HOST:PORT`. A non-loopback
bind requires `--mcp-token`. The three edit verbs are disabled on a remote bind unless you pass
`--allow-remote-edits`.

## 4. First use

### 4.1 Make the first map

Change to the repository. Run the following command:

```bash
./build/ripwire . --max-tokens=3000   # start here on an unfamiliar repository
```

The command writes the top of the ranked map within the token budget. Remove `--max-tokens=3000`
for the complete map. The complete map is larger. On a large tree, use `--top-k=N` to limit the row
count.

### 4.2 Use the common commands

| Task | Command |
| --- | --- |
| Orient in a new tree | `ripwire . --max-tokens=3000` |
| Prepare for a task | `ripwire . --for="<task description>"` |
| Find a symbol's callers | `ripwire . --callers=SYM` |
| Find the callees | `ripwire . --callees=SYM` |
| Measure the blast radius | `ripwire . --impact=SYM` |
| List the use sites | `ripwire . --uses=SYM` |
| Read one function body | `ripwire . --expand=SYM` |
| Find the tests for a change | `ripwire . --test-gate` |
| Review the current diff | `ripwire . --situ` |
| Review a branch | `ripwire . --pr-context=REF` |
| Read a stack trace | `ripwire . --from-trace=FILE` |
| Inspect code quality | `ripwire . --quality-panel` |
| Locate a pattern | `ripwire . --grep=PATTERN` |
| Search the documents | `ripwire . --recall="<task>"` |

## 5. Command families

The `--help` output groups 179 long flags advertised in `--help` into seven families. Run
`./build/ripwire --help=all` for the complete catalog.

| Family | Purpose | Representative flags |
| --- | --- | --- |
| Understand a codebase cold | What is this repository, and what matters? | `--for`, `--help-task`, `--tree`, `--lego`, `--exemplar`, `--recall`, `--top-k`, `--token-budget`, `--max-tokens` |
| Navigate and answer a question | Who calls this, and is it safe to change? | `--callers`, `--callees`, `--uses`, `--impact`, `--path`, `--connect`, `--situ`, `--test-gate`, `--grep` |
| Zoom the detail ladder | Show more detail only where it pays | `--detail`, `--pack-signatures`, `--outline`, `--expand`, `--compress` |
| Assess quality and structure | Where is the risk, and did a change add risk? | `--quality-panel`, `--hotspots`, `--clones`, `--metrics`, `--deps`, `--lint`, `--quality-delta`, `--edit-check`, `--pr-context`, `--merge-scout` |
| Self-diagnosis | Is the setup correct? | `--doctor` |
| Security | Is this agent skill file safe to install? | `--scan-skill`, `--scan-skills` |
| Knobs and modes | Shape, format, cache, and budget | `--json`, `--format`, `--mcp` |

Not sure which command answers the task? Run `ripwire . --help-task="<task in words>"`. The command
returns one recommended command, or it abstains when the evidence is thin. The command gives advice
only. It does not run the recommendation.

## 6. Output format

The default output is minified XML. One comment line at the top holds the legend. The legend defines
every attribute that the document uses. The elements are:

| Element | Meaning |
| --- | --- |
| `<r>` | The map root |
| `<f p="PATH">` | One source file |
| `<s t="KIND" n="NAME" k="RANK">` | One symbol |
| `<c n="CALLEE">` | One resolved call edge |

The tool escapes `&`, `<`, `>`, `"`, and `'` in every attribute value and text node. C++ identifiers,
such as `operator<`, and paths that contain `&` round-trip correctly.

Two runs over one tree produce the same bytes. The output is streamed through a 64 KB buffer. The
tool does not materialize the document in memory.

### 6.1 Output example

The following command lists the callers of one function:

```bash
ripwire . --callers=rankGraphTeleport
```

The output has this shape. The line numbers are a capture and can move as the files grow.

```xml
<callers of="rankGraphTeleport" defs="1" count="6" root="." counts_floor="1">
<s t="fn" n="runEval" p="src/eval.h:171"/>
<s t="fn" n="rankGraph" p="src/graph.h:3398"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:3948"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:998"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1123"/>
<s t="fn" n="getIndex" p="src/mcpindex.h:1108"/>
</callers>
```

### 6.2 Exit codes

| Code | Meaning |
| --- | --- |
| 0 | The command completed. |
| 1 | The command refused the request. A refusal names the reason. |
| 3 | The output exceeded the token budget that you set. |
| 4 | `--test-gate` found an open obligation. |

### 6.3 JSON output

Add `--json` to a supported read command to select JSON instead of XML. The JSON carries the same
attributes with the same meaning. Run `--json` only with the verbs that support it. The binary
refuses the combination when a verb does not support it.

## 7. Accuracy and disclosure rules

The call graph is extracted from source text by name. The tool does not have a type system or a
compiler. These limits follow:

- Dynamic dispatch contributes no edge.
- A callback through a function pointer contributes an edge in one case. One function must be bound
  to the variable in scope. The variable must not escape.
- A macro-generated call site contributes an edge only when the tool indexes the function-like
  `#define`.
- A name that has several definitions at the same resolution tier produces one edge per candidate.
  Each edge carries the weight `1/k`. The symbol carries `amb="K"`. The header totals the events in
  `ambiguous=`.

The output uses these disclosure rules without exception:

- **A zero is a measurement.** A zero means "none found". A zero never means "none exists".
- **A floor is labelled.** A count that cannot be a total carries `counts_floor="1"`.
- **A truncation is disclosed.** A header carries `total=`, `shown=`, and `capped=`. A document that
  a budget cut carries its own marker and a `next=` step.
- **A refusal is not a zero.** A selector that names nothing indexed refuses with a did-you-mean
  suggestion computed from an edit distance. A query that resolves and selects nothing reports
  `count="0"`.
- **An estimate is labelled.** Token estimates are calibrated approximations. They are not exact
  counts for every model.
- **Counting units are named.** `--callers` counts distinct caller and callee pairs. `--uses` counts
  use sites. The two numbers differ by design.

Use these methods when a disclosure says the answer is incomplete:

1. Use `--expand=SYM` to read the body.
2. Use `--uses=SYM` and `--impact=SYM` to measure the blast radius.
3. Use `--scip=FILE` to supply a compiler-grade index. A precise index replaces the name-based edges
   and marks the affected edges with `prov="scip"`. A missing or corrupt index causes a refusal. It
   does not cause a silent fallback.

## 8. Determinism

The determinism contract is byte-identity. One tree produces one byte sequence on every run. The
contract holds under four rules:

1. The crawl sorts all candidate paths before it assigns symbol identifiers.
2. Every global reduction folds fixed contiguous blocks in index order. No reduction uses an atomic
   floating-point add.
3. The rank vector uses type `double`.
4. The PageRank translation unit compiles without floating-point reassociation.

Thread count and thread timing never change the output.

To verify the contract on your tree, run these commands:

```bash
ripwire . > a
ripwire . > b
diff -q a b
```

The diff must report no difference. The cached run must equal the uncached run. Use `--no-cache` for
the uncached run.

## 9. Verification and quality control

`test/regression.sh` names **602 gate scripts**. It is the authoritative list. <!-- gatecount -->

**602 gate scripts** hold five contracts that a unit test cannot hold. <!-- gatecount -->

1. Two runs over one tree are byte-identical.
2. A warm run equals a cold run.
3. Every XML output is well-formed. The verification command is `xmllint --noout`.
4. The sanitizer build uses `-fno-sanitize-recover=all`. AddressSanitizer, UndefinedBehaviorSanitizer,
   and LeakSanitizer are part of the guardrails.
5. A differential harness runs a reference binary and the candidate binary over every argument vector.
   Standard output, standard error, and the exit code must match for each vector.

Run the full gate suite in the foreground:

```bash
python3 test/pargates.py . ./build/ripwire -j 6
```

A new gate script must be added to `test/regression.sh` in the same change. The gate
`test/manifestcheck.sh` enforces this rule.

Another gate derives the cap inventory. The tool has 208 compile-time caps and 7 ranking parameters.
`docs/LIMITS.md` lists each cap, its value, and whether the file discloses a truncation when the cap
fires. `docs/TUNING.md` lists the measured cost of each cap.

## 10. Quality evaluation

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

`--quality-delta` reports only the properties that the working tree made worse against a baseline.
`--test-gate` names the tests that must run. `--edit-check` compares an edited symbol against git
HEAD. `--safe-delete=SYM` composes the callers, the blast radius, the use sites, and the dead-code
shape into one risk report.

## 11. Agent integration

The command line is the recommended interface. An agent that can run shell commands needs no
registration. The installer adds the skills. The skills teach the agent when to use each command.

`ripwire wrap <agent>` prints the wiring recipe for one agent. The command prints the recipe. It
does not edit a configuration file. Run `ripwire wrap --all` to detect every installed agent and to
print each recipe.

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
for standard input. The CLI write verbs and the MCP write verbs use the same safety contract:

- A stale file hash causes a refusal.
- An ambiguous selector causes a refusal.
- A symlink target causes a refusal.
- The tool preserves the file mode.
- The tool writes a temporary file, synchronizes it, and renames it over the target. A failure leaves
  the original file unchanged.

## 12. Supported languages and formats

The tool vendors 24 tree-sitter grammars. A table maps a file extension to a grammar and a query
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
| TypeScript / JavaScript | `.ts`, `.tsx`, `.js`, `.jsx` | Named imports and default imports resolve. |
| Java | `.java` | Qualified `new` calls resolve in a precise tier. |
| Kotlin | `.kt` | Shares one call graph with Java. A file with string templates past 128 levels is refused and listed by `--skipped`. |
| Ruby | `.rb` | Superclasses, mixins, `autoload`, and constant receivers are read. |
| PHP | `.php`, `.phtml` | Dynamic dispatch is a stated floor. |
| Lua | `.lua` | Metatable inheritance produces no inheritance edge. `require` is a function call, not an import directive. |
| Dart | `.dart` | A function body is a sibling of the signature. The capture extends the span through the body. |
| Elixir | `.ex`, `.exs` | Modules, protocols, implementations, functions, macros, guards, and delegates are indexed. |
| Swift | `.swift` | |
| C# | `.cs` | The `?.` family resolves in a precise tier. |
| Go | `.go` | Qualified calls are rejected and fenced, not guessed. |
| Rust | `.rs` | Scoped, turbofish, and `Self::` calls resolve in a precise tier. |
| Bash | `.sh`, `.bash` | |
| JSON | `.json` | Config keys become symbols. The lane emits no call edges. |
| TOML | `.toml` | A table header is one symbol. Keys below it are one level down. |
| YAML | `.yml`, `.yaml` | Mapping depth 2 is the cut. Sequence levels are transparent. |
| Markdown | `.md`, `.markdown` | Every heading is a section symbol. The span runs to the next heading of the same or higher level. |

Notebooks, HTML, and CSV files are indexed as documents for `--recall` and `--mentions`.

## 13. Performance

| Operation | Scale | Measured result |
| --- | --- | --- |
| Cold parse and answer | 1,900-file tree | About 0.7 s on an Apple M-series host |
| Warm run | The same tree | About 0.11 s |
| Cache load | The same tree | About 167 times fewer instructions than a cold parse |

One process answers a query. The tool starts no daemon and holds no server connection. The parse
cache is keyed by file content hash and a parser version. An extraction change bumps the version and
causes one cold re-parse. A gate asserts that the warm output is byte-identical to the cold output.

Measured results with their instruments and corpora are in `docs/EVALS.md`. The document also lists
the counterexamples that this project publishes against itself. For example, one comparison ran
graphify 0.9.34 with `--code-only --no-cluster`. The measurement is in `docs/EVALS.md`, Section 2.

## 14. Known limits

- The call graph is name-based. Dynamic dispatch, callbacks, and macro expansion can hide an edge.
  Section 7 states the disclosure rules.
- Multi-file localization is hard. The tool finds one gold file more often than it finds all gold
  files of one task.
- Churn measurements need real git history. A shallow clone reports every file as one commit.
- The tool skips files over 4 MB. Use `--max-file-size=N` to change the limit.
- The JSON lane skips files over 256 KB. The YAML lane skips files over 512 KB.
- Directory symlinks are not followed.
- The default crawl honors `.gitignore`. Use `--no-ignore` to disable this behavior.
- PHP dynamic dispatch and Lua metatable inheritance are floors, not complete answers.
- The `--grep` view can cost more tokens than a plain grep on a small result set.
- `--pack-signatures` can be larger than the body when a symbol is short.

## 15. Documentation

| Need | File |
| --- | --- |
| Every flag, with an invocation and a recorded output | `docs/COMMANDS.md` |
| The authoritative flag list, always current | `./build/ripwire --help` |
| Pipeline, data model, determinism contract, disclosure contract | `docs/ARCHITECTURE.md` |
| Every published number, its instrument, and its counterexamples | `docs/EVALS.md` |
| The build method as a transferable process | `docs/METHODOLOGY.md` |
| The compile-time cap inventory | `docs/LIMITS.md` |
| The measured cost of each cap | `docs/TUNING.md` |
| The origin of every folded idea | `docs/LINEAGE.md` |
| C++ style, the guardrails, and the submission checklist | `CONTRIBUTING.md` |
| Installation and removal procedures | `INSTALL.md` |
| Orientation for a coding agent that works on this repository | `AGENTS.md`, `CLAUDE.md` |
| User-visible changes and known limits | `CHANGELOG.md` |
| Vendored dependencies and their licenses | `THIRD_PARTY.md` |
| Skill-file security checks | [security](docs/COMMANDS.md#--scan-skillsdir) |
| The whole tool in 34 slides | `present/ripwire-showcase.pdf` |

The presentation rebuilds from `present/deck5_ripwire_build.js`. The preprint draft is in
`paper/PREPRINT.md`. The method is not submitted for peer review. Its tables name the measurement
files under `bench/`.

## 16. Improvement

`prompts/` holds twelve **self-contained orchestrator prompts**. Each prompt is a workflow that a
coding agent can run against this repository. Each prompt writes a plan and stops for your approval
before it runs a command. Build the binary first. The prompts measure against the binary.

The prompts cover a full audit, a gap analysis from real use, a capture audit, a head-to-head
comparison, a ranking evaluation, a language improvement pass, a zero-context onboarding study, a
sibling sweep, a command tour, and a presentation build. The index is `prompts/README.md`.

If the tool answers incorrectly on your codebase, run `prompts/improve-for-my-language.md`. The
prompt harvests your session transcript and produces one finding per event with its evidence. Open
an issue with the result.

## 17. License

Apache License 2.0. See `LICENSE` for the full text.

Copyright 2026 David Brewster

Vendored third-party code keeps its own license. `THIRD_PARTY.md` lists every dependency and its
terms.

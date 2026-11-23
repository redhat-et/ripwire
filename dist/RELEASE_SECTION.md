## [0.7.0] — 2026-11-23

**ripwire 0.7.0 is practical for large repositories on small and normal-sized machines.** On an Apple M5 Pro (48 GB) it indexes llvm-project cold in 28 s at a 5,199 MB peak, where two of five peer tools stopped at our one-hour limit and one failed; the same llvm-project runs (map cold and warm, `--for`, `--deps`, `--quality-delta`) complete on a 16 GB Apple M2 laptop. 0.6.9 and earlier could exhaust memory on llvm-project (one process reached 149.7 GB).

117 merged pull requests since 0.6.10 (#456 to #718), plus #710; 0.6.11 was skipped, so this release carries everything since 0.6.10. What a user sees (each entry below states its own measurement and its floors):

Measured against five other code-context tools on one machine (the README's "How ripwire compares"): on 213 held-out tasks, one call each, ripwire's answer was complete on 126, against 68 for the next tool; it indexed llvm-project in 28 s at a 5,199 MB peak, where two of the five stopped at our one-hour limit and one failed.

Full tables (speed, memory, answers; method and setup notes): [README — How ripwire compares](https://github.com/redhat-et/ripwire/blob/v0.7.0/README.md#how-ripwire-compares)

- **Answers: more of what a task needs, and fewer confident wrong ones.**
  - `--for` prints the manifest lines that define a package, dependency, binary, build target, feature or entry point the task names (`package.json`, `Cargo.toml`, `pyproject.toml`, `setup.cfg`, `go.mod`, `CMakeLists.txt`); on the 321 in-sample calls 8 changed, +2 required items, 0 lost, +0.188 % bytes (#565).
  - `--for` lists who calls the function that reads a literal, names the call that makes a head name's value and the declaration that holds a dispatch candidate, names the function that stores a head row into a slot, says when a hop row's function is used as a value, and points INTO the one holder on an add-a-new-X task. A sentence gets the callers, path and connect blocks its bare names get; a task that spells an import gets the chain from the spelling to the definition; a short "what does X call" question keeps its source anchor.
  - `--path`, `--connect` and `--callers` bind a refused spelling's one source definition; `--path` says when its verdict is one of many unwalked definition pairs and `Owner.method` narrows instead of refusing; `--connect` never names a test function as the joint of two source symbols.
  - A language you state orders name answers by language: `Shape@rs`, a file lane or the LSP client's declared language puts that language's definition first, `name@lang` works for every symbol verb (22 of 22 selectors answered the stated language on cpython, envoy and vscode; all were "symbol not found" before), and `reflang=` says when the language decided (#440, thanks @mpapis).
  - An interface method, a C++ pure virtual or a Go interface method no longer answers a confident zero for `--impact`, `--callers`, `--safe-delete` and `--path`; a zero or "not found" that means "not indexed" says so; `--exemplar` hedges an off-task pick; `--help-task` abstains with a next step; a `<cycle>` that lists only 12 of its files says so (`members_capped="1"`, #479, thanks @jflowers); `--lego` says "unread for this language"; lexical scans read every file and a reached limit is printed to stderr; a `--for` budget only trims the answer.
  - Answers are smaller where they repeated themselves: `--for` legends define only what the answer carries, repeated `<d>` text and tail names print once, deep same-file siblings and one-endpoint rows become tail pointers, and a tail row names up to two of its file's symbols that share the task's words (`tsym=`). `--legend-have=` takes legend tiers, so the handshake pays for itself in about ten calls instead of about 130.
- **Speed and memory.**
  - Each indexed reference takes 120 B less (264 to 144 B per row): peak footprint on large repositories 10 to 24 % lower (macOS, median of three; mem-ref-shrink). On the M5 table's machine (Apple M5 Pro, 48 GB, 2026-11-22) ripwire peaks at 668 MB indexing envoy and 1,106 MB indexing vscode.
  - A warm run on an unchanged tree reads back the crawl, the model and the resolved graph instead of rebuilding them; the cache file does not change and nothing is re-indexed (warm-snapshot). A cold JavaScript/TypeScript index retires 24 % fewer instructions on vscode (js-capture-cold); cold indexing climbs the syntax tree from a cached path instead of the root; the exact clone pass keys each function body at parse time and no longer reads every file on a warm run (cockroach was about 9,500 files per warm `--for`).
  - Large repos: llvm-project cold-indexes in 28 s at a 3,823 MB peak, and 5,199 MB peaks including the first question; ripwire indexes 80,576 of the 180,650 files git tracks (the M5 table's machine, above). The same runs (map cold and warm, `--for`, `--deps`, `--quality-delta`) complete on a 16 GB Apple M2 laptop. Three changes carry it: the name-walk fix (0.6.9 and earlier could exhaust memory on llvm-project), the allocator-level memory ceiling (a runaway step now exits 5 instead of taking the host down), and the graph-store work (120 B less per indexed reference, a warm run that reads back the resolved graph).
  - An allocator-level memory ceiling is on by default at the memory guard's own limit, and a map of llvm-project no longer grows without bound (a name-keyed class walk had no visited set: one process reached 149.7 GB; the cold map now peaks at 3,823 MB on the M5, Release build with profile-guided optimization, output byte-identical).
  - The default map's inventory tier is bounded (vscode's `<ls>` was 82.4 % of the document); the cross-branch verbs answer in repositories with more than 512 local branches; `gitFileAuthors` (behind `--owners` and `--pr-context`) uses a flat table and zero-allocation commit parsing (#473, thanks @lennix1337; byte-identical, CPU and memory unchanged within noise).
  - The prompt-routing hooks no longer time out on every prompt in a cold directory: `--help-task=TASK --deadline-ms=N` answers within the deadline and finishes the index in the background (#594, thanks @WingedGuardian).
- **Quality-delta (`--quality-delta`).**
  - The default legend defines `fix=` on a row with no `why=` (a complexity row with a repeated-decision `fix=`); other answers keep their bytes (#710).
  - `tangle` is the thirteenth kind: a long function whose nesting goes deep, whose deep regions take a growing share, or whose steering locals multiply, with a best-since-tag ratchet and an `<improved>` section; named-step orchestrators score 0.
  - New: error-masking `facet="failure-default"`, a dropped I/O or child status (`defect="unchecked-status"`), a classifier that leaves a value without an outcome (`defect="unhandled-arm"`), adjacent same-typed parameters (`similar=`, report-only), and every pull request runs `--quality-delta` over its whole range (`qd-range` CI job, `scripts/qd_range.sh`).
  - Fewer false rows: renaming or moving a function no longer reads as new code (75 placed runs over nine corpora: 18 false-alarm rows, 4 gating, to 0), a file rename git recorded keeps every function's identity, a short clone row over different data and a pair that crossed the bar only because one member shrank stop gating, a new function at the ceiling (4x the bar) now gates.
  - Warm runs are cheaper: the near-clone comparison runs 64 cells per machine word (46 % envoy, 82 % cockroach, 9 % vscode fewer instructions) and error-masking rows live in the cache record (43 / 27 / 69 % fewer).
- **Languages.**
  - C#, C++ and Java base and import clauses are read through the shared tags-capture paths (#420 `LaimaWu`, #538 and #606 `SeddonShen`); the tags pass evaluates string predicates and Elixir's keyword tables moved to `tags.scm` (#426 `conka8`; `#any-of?` and `#not-any-of?` now filter in `--match` too).
  - Rust: a call written inside a macro's arguments is a call of the enclosing function (axum 4,885 to 5,158 call edges, nushell 52,405 to 58,051, zed 288,843 to 306,195); a macro invoked by path or `use ... as` alias reaches its in-tree `macro_rules!`; builder chains resolve through `-> Self`; `<T as Trait>::m()` names T's impl; an unresolved `pub use` no longer hides an in-tree re-export (#610, thanks @soarkit); `#[test]` functions and `Drop::drop` are no longer dead code (#493, #494, #499, #500, thanks @zom-2018).
  - C and C++: calls through smart-pointer locals and aliases reach the interface tier, a call no longer binds a same-named base class in another namespace, a macro invocation or trailing annotation macro is no longer stored as a definition. Go: method expressions are references. Python: `from pkg import mod` is a file edge to `pkg/mod.py` (#478, #533, thanks @jflowers) and an import inside a function gives that function its module calls. TypeScript: a call through an in-root `paths` alias (`@/x`) binds through its import (#711, reported by SStonkSS1). Clojure: a call whose list head carries metadata is extracted (#715 `himanchalkaushale`, #548 first arm) and the inert-region walk is shared (#456, `LaimaWu`).
  - New: Protocol Buffers (`.proto`) definitions are indexed and a generated name links to its schema by name; `--flags` reports Bash environment-variable reads, child shells, `local` scope, redirections and quoting included, with `unreadable=` for a file it cannot read (#641 and #685, `jflowers`); `--recall` ranks document sections and HTML pages have a section tree.
- **MCP and wrap.** MCP `find_referencing_symbols` binds a narrowed callers selector like `--callers`; the prompt hooks answer within `--deadline-ms` (above); a build off a release tag says so in its version (`0.6.10-dev.41+g...`).
- **Fixes and hardening.** `--regex` and every user-pattern entry point (`--arch` rules, `--graph-query file()`, `#match?`) refuse the multi-quantifier family that made libc++ abandon matches and libstdc++ never return (#484, thanks @pt-act; 88-assertion gate, red on main with 15 FAIL); two release-build undefined-behavior sites on adversarial input are gone; the `mem=` legend names every key of the order it prints, owner's file, path, line and name (#595, #682, thanks @soarkit); two benchmark harnesses refuse a malformed bank (#540 `NopeCharon`, reported by `soarkit` in #492); ordering ties break on content keys, not node id, so the same answer prints on every machine.
- **The answer-first stack (#710; its 88 fragments name no community contributor).**
  - *Highlights.* On llvm-project the name-keyed and C++ base-class walks enter each name once, so a map that once grew until the OS killed it now takes 28 s (answers unchanged byte for byte). Bare `--lint`, `--expand` and the flagless map are held to a 24,000-character ceiling with one pasteable `next=` call (largest map 52,858 to 23,629 characters, largest `--lint` 83,162 to 19,589, none over 30,000 on the 11 development repositories). A `--for` answer names the ranges to read next in one `<act read="path:l-e,…"/>` element, for parallel ranged Reads (`RIPWIRE_NO_ACTLINE=1` turns it off). `skills/install.sh` installs a `ripwire-locator` Claude Code subagent that returns at most 12 lines of edit ranges; no token saving has been measured yet.
  - *Answers.*
    - A `--for` question that names its symbol in backticks and asks who calls it, where it is used or what breaks is answered by `--callers`, `--uses` or `--impact`, and the answer says so first (`<route from="for" verb= complete="not-proven" next=>`); `warn="1" why=` marks a verb likely to miss a macro caller, a callback slot, twin definitions or a cut list, and then the first `--for` page rides along. `--no-verb-route` (MCP `no_verb_route`) opts out. Call paths and chains ("the call chain from `A` to `B`"), questions that quote a literal message and "what does `X` call" are never routed. A windowed routed answer continues itself (`--for=Q --offset=K`), and a routed answer is held to the 12,000 B page (one warned question went from 30,369 to 20,727 B on 89 dev questions).
    - A who-calls `--for` puts the callers block first (bytes until the whole answer appeared: median 6,147 to 2,618 on 43 held-out questions) and its page 1 ends early when that block proves itself complete (`early="proven"`, 2 of 52 held-out answers, each still complete).
    - Page 1 of a `--for` question that names a symbol carries that symbol's body (`<bodies of="key">`, up to 4,000 B each, 5 bodies at most; a body is capped at 120 lines with `cap_lines=`); the key group keeps its own copy whatever else the page serves. `--bodies=pointer` names the bodies instead of carrying them (default unchanged, page 1 a median 715 B smaller on 60 of 89 pages; whether it lowers a session's tokens is untested).
    - `--pack-task` is one bundle again: the `--for` head, the file tail and ONE key body, the tail takes its share as a floor (bundles that name every file the question needs: 329 to 420 of 596 tasks on four sets), and `est_tokens=` and `budget_tokens=` use one conversion.
    - Ranking and paging: a symbol's file basename is a ranking field (every-file-and-function complete 66 to 67 on the 89 dev questions, body rung 24 to 27, no cell down); the sigs rows past rank 10 are short on page 1 (`<sigx>` carries their text), carry `e=` beside `l=` (usable line ranges for 80 to 96 of 123 gold functions), and a tail past row 24 lists the files in a top-5 row's directory first; an explicit priority keeps a body from displacing a research section, and a body now reaches page 1 behind a tail that fits (edit-function bodies on page 1: 9 to 20 of 89 cells with the guarded promotion, 18 to 21 with the lower body guarantee). A paged page 1 no longer defines what only a later page carries. A budgeted answer no longer stops one row short, and `docs_after_code=` counts the rows still shown.
    - `--for` serves its `<sigs>` and `<tail>` rows as text lines (`--rows=elements` / MCP `rows` opt out; decoded, byte for byte the element form; page 1 a median 7.6 % smaller; on one model the line form cost about twice the output tokens when asked to list the rows, and the effect in a real session is untested).
    - `--callers`, `--uses` and `--impact` name the definitions and declarations they measured (`<def>` rows, an untied declaration listed `bodyless="1"`): complete 12 to 27 of 48 for `--callers` and 15 to 32 for `--uses` on held-out gold, at +9.33 % and +15.49 % bytes, which failed the pre-registered +2 % bar and landed on completeness. `--impact` puts production callers and evidence-bearing importers in its first window. A `found="0"` answer names the plain-text occurrences (`text_hits=`, `next="--grep=NAME"`); `--grep` names the files whose hits its tier held back (`held_files=`) and no longer holds hits back in a file whose parse degraded; `--affected`, `--test-gate` and `--situ` answer for the files that resolve and name each unusable one (`unused`, `not_indexed` or `not_found`).
    - Graph edges: `--callers` and `--uses` see through one C function-like macro (`via="macro:NAME"`, at most 16 files per macro); a C function stored through a registrar's parameter into a struct field names who may call it (tmux `client_signal`); a C `static` in a header binds from the files that include it; a call inside a Rust `macro_rules!` transcriber is a call of that macro (axum 4,885 to 5,076 edges) and a matcher word is not a call.
    - A served body starts where its declaration starts (`export`, decorators, `template<...>`, `#[...]`): 45 of 103 language-by-form rows lost their first line or keyword before; `--insert-before-symbol` on a decorated definition lands above the decorators.
  - *Speed and memory.* The memory limit is also read at `operator new` and a runaway allocation exits 5 with one stderr line (`RIPWIRE_MEM_BUDGET_MB` sets that line alone); the header-`static` question builds its include graph from C-family `#include`s alone (5.9 % fewer instructions on a warm cpython `--for`).
  - *Tokens and bytes.* `--legend-seen=FILE` leaves out the legend definitions you already hold (a hook builds the file from the answers a session received); a `skills/install.sh --hook` install now registers the hook by default and it REWRITES ripwire commands (shown before it writes; `--no-hook-legend-seen` or `RIPWIRE_LEGEND_SEEN=0` turns it off); three more `--for` notes are held entries; the `<def>` and `<f>` readings are shorter; `--affected` groups fold their paths (`pf=`, lossless); MCP `tools/list` is shorter with the tool contract byte-identical; SKILL.md bodies are short with the rest in reference files (32 of 33 blind-rated tasks scored with both). `--legend-have=` on a non-XML answer says `not-applicable`.
  - *Quality-delta.* Two quality-delta findings the batch carried (a four-parameter legend function, a complexity-16 function) are fixed rather than acked; no output moves. A comment is no longer counted as a language predicate by the identity ratchet, which discloses its count as a floor.
  - *MCP and wrap.* MCP `for` serves rows as lines too (`rows` argument) and a routed MCP answer is held to the page and continued through `offset=`/`limit=`; `ripwire wrap claude` prints a three-moment block to paste into every subagent brief, `skills/install.sh --hook` also registers a SubagentStart note for Explore and Plan subagents, an opt-in primer (`--hook-subagent-primer`) is available, and the edit-routing line no longer says a Read always precedes an Edit (measured on stored sessions: 4 refusals in 283 Edits, all outside the working directory). Delivery into the subagent has not been run live.
  - *Fixes.* The MSVC build reads the two `--for` route cue tables again; the ASan build answers two-endpoint `--for` tasks (an unsigned hop count wrapped); the HEAD-binary build and the bench harnesses are bounded and record a timeout or a kill as its own state; the showcase capture regenerates on a merge-heavy tip; undefined legend attributes are defined where they appear; a gate for bounding the carried page landed and its mechanism was reverted because it shrank answers silently.
- Contributors: Bash environment reads, `from pkg import mod` and the capped cycle list (@jflowers: #641, #685, #533, #541); C++ and Java base captures (@SeddonShen: #538, #606); the regex guard (@pt-act: #484, #691); C# imports and Clojure's shared inert-region walk (@LaimaWu: #420, #456); tags-pass string predicates (@conka8: #426); bench refusals (@NopeCharon: #540); the flat `gitFileAuthors` table (@lennix1337: #473); Rust dead-code exemptions (@zom-2018: #499, #500); language-first name answers (@mpapis: #440); Clojure metadata heads (@himanchalkaushale: #715); reports that led to fixes (@soarkit: #492, #595, #610, #611; @WingedGuardian: #594; @SStonkSS1: #711; @pt-act: #692).
- Thanks: @jflowers, @SeddonShen, @pt-act, @LaimaWu, @conka8, @NopeCharon, @lennix1337, @zom-2018, @mpapis, @himanchalkaushale, @soarkit, @WingedGuardian and @SStonkSS1.

<!-- release-notes-end -->

### Changed — highlights of this release

The changes a user is most likely to notice; each has its own entry below with the method and what it does NOT mean.

Measured against five other code-context tools on one machine (the README's "How ripwire compares"): on 213 held-out tasks, one call each, ripwire's answer was complete on 126, against 68 for the next tool; it indexed llvm-project in 28 s at a 5.1 GB peak, where two of the five stopped at our one-hour limit and one failed.

- **Large trees finish.** On llvm-project a map used to grow until the OS killed it (one process reached 149.7 GB); the name-keyed walks now enter each name once and the cold map now takes 28 s and peaks at 3.7 GB (Release build with profile-guided optimization, 2026-11-22). A C++ base-class walk that kept a cold llvm-project map in a single-core loop for more than ten minutes now expands each root once, and the external-veto import tables went from about 2.7 s to 0.6 s there. Every answer is unchanged byte for byte.
- **A memory ceiling, on by default.** The memory guard's limit (65 % of RAM or the cgroup limit, or `--max-memory`) is now also read at `operator new`, so a runaway allocation inside one step is refused with exit 5 instead of being killed by the OS. A run under the limit is byte-identical.
- **Answers fit Claude Code's inline limit.** Bare `--lint`, `--expand` and the flagless map are held to a 24,000-character ceiling and continue with one pasteable `next=` call; on the 11 development repositories the largest map went 52,858 → 23,629 characters and the largest `--lint` 83,162 → 19,589, with no answer over 30,000. A routed `--for` answer is held to its page too, CLI and MCP.
- **`--for` answers the question it is asked.** A question that names a symbol in backticks and asks who calls it, where it is used or what breaks is answered by `--callers`, `--uses` or `--impact`, says so in a `<route>` element, and continues itself with `--offset`. Page 1 also carries the body of the named symbol.
- **An act line.** A `--for` answer names the ranges to read next in one element, `<act read="path:l-e,…"/>`, to be read in one turn of parallel ranged Reads.
- **Fewer repeated legend bytes.** With `skills/install.sh --hook`, the legend-seen hook (it rewrites ripwire commands, and says so before installing) cuts about 19 % of total answer bytes from a session's second call on; `--for` rows are served as text lines, page 1 a median 7.6 % smaller (one model spent more output tokens reading them; see that entry).
- **A locator subagent for Claude Code.** `skills/install.sh` installs `ripwire-locator` for Claude Code, which runs `--for` in its own context and returns at most 12 lines of edit ranges, so the main conversation does not carry the whole answer. No token saving has been measured yet.

### Changed — C# using directives share the import capture path (#420, thanks @LaimaWu)

C# `using` directives now use `@import.path` and the CSharp normaliser (#358, slice 1a); the old `csharpUsingTarget`
and `directiveTargetOf` branch are removed. Targets, directive sites, order, duplicate directives,
static/global forms and existing binding behaviour are preserved. The known alias gap stays pinned:
`using X = Foo.Bar` still reports X; C# alias bindings are the slice 2b follow-up (#488) on the shared binds channel (2a).

As with the Python capture move (#382), containers beyond depth 256 without a deeper import no longer
make a file `extract-partial` or prevent whole-cache reuse. A nonempty import beyond the bound still
discloses the cut and is not captured. `csharpcheck` arms C6/C7 pin the boundary and the new mechanism.
Parser tag 311 (rich 312) invalidates the old extraction cache; kCacheVersion is unchanged.

### Added — `@lang` scope selectors, `reflang=` disclosure, and the editor's declared language (#440, thanks @mpapis)

- `@rs` / `@cpp` / any known tag is now a selector on every name-taking verb: the answer is scoped to that language — unless it holds nothing, when foreign rows are still served AND the refusal sentence says so (`the matching language holds no definition; N in others`), exit code untouched. Case tolerance is parse-only: `@CPP` resolves like `@cpp`, emission stays canonical. An unknown tail REFUSES with the vocabulary, never silently ignoring it; `?` is display fallback, not vocabulary.
- An answer whose language DECIDED something says which and why: `reflang="rs" reflang-origin="explicit|context|client|corpus"` on the root, and where a list has no row to carry it (`--lsp workspace/symbol`, the picker answers), one `window/logMessage` ahead of the response — merged into the cap notice when both apply, fired only when something was answered. Presence has meaning: a corpus majority that moved nothing says nothing at all.
- A STATED language (an `@lang` tail, the asked-from file, the editor's declared languageId) orders by language: its definitions front, then its family, then the kind ladder. When nobody stated one, the ladder decides alone — a repo-wide majority is population evidence, not evidence about this name — and the majority language speaks only to break a tie between same-rung definitions, disclosing itself plus the pasteable `next=--defs=NAME` that lists every definition and the picking spellings. Id stays last on every path. Measured consequence of kind-over-population: a bare `Marker` in a JVM pair fronts wherever the grammars index the interface at the higher rung (Java's own node beats Kotlin's class-shaped one; `@kt` states the language and restores the front).
- `--lsp` reads the document's declared language: a `didOpen` `languageId` that passes the alias map replaces the path convention for definition/references/hover on the `[overrule]` suffixes only (default `.h`, `.hpp`, `.hh`, `.hxx`; never for `workspace/symbol`, never against an explicit `@lang`, unmappable ids change nothing byte-for-byte). The map is config: compiled defaults seeded from the Zed extension's grammar names, overridable via `--lsp-langmap=FILE` > `$XDG_CONFIG_HOME/ripwire/lsp-langmap.toml` > `<root>/.ripwire/lsp-langmap.toml` > `~/.config/ripwire/lsp-langmap.toml`, the first readable file rides and later candidates are not read (an unreadable `--lsp-langmap` file is disclosed and the search goes on; a row whose tag is outside the vocabulary is disclosed and skipped; a row of any other shape is ignored, so the defaults answer for it), declarations are keyed by disk path so an index rebuild cannot misattribute them, and raw client strings never enter any protocol echo — only ripwire tags and the origin word `client` flow onward. `--lsp-langmap` alone refuses rather than silently doing nothing.
- The stated tag now scopes EVERY resolution path: the canonical-id and `Scope::name` tiers used to answer ahead of the anchor, so `A::f@rs` in a C++/Rust tree could still front C++ on an id accident; the one scope rule now runs on their answers too, with the same disclosed-fallback doctrine as everywhere else.

### Fixed — `from pkg import mod` is a file edge to `pkg/mod.py` (thanks @jflowers, #478)

A from-import's one dependency record names the package (`pkg`, `.`, `..`, `.sub`), so the file graph had an edge to `pkg/__init__.py` and none to the submodule a member names: `from pkg import mod` lost `pkg/mod.py`, and `from . import sibling` lost `./sibling.py`. `--deps`, `--arch` Ca/Ce, cycles, `--impact`'s importer tier and every other view on the file graph now also carry an edge to the module `<package>.<member>` names, looked up inside the package that resolved: when `pkg` is `<dir>/__init__.py`, only `<dir>/mod.py` or `<dir>/mod/__init__.py`, never another root's `pkg/mod.py`, and no edge when both or neither exist. When `pkg` resolves to a plain module (`util.py` beside a `util/` directory) there is no member edge, since that module wins at import time. Only when the package resolves to no file is the member resolved exactly as `import pkg.mod` is, across the same roots. The member is the name taken from the package, never the local alias (`from pkg import mod as m` reaches `pkg/mod.py`, not `pkg/m.py`); `from pkg import SomeClass` with no `pkg/SomeClass.py` adds nothing, and `from pkg import *` adds nothing. A namespace package (no `__init__.py`) gets the member edge although the package itself resolves to no file.

What it does not change: the call graph. A member edge is a dependency, not evidence for a bare call, since `from pkg import mod` makes no name of `mod` visible unqualified, so call binding (Rule 3) is byte-identical. The edge is drawn whenever the submodule file exists, including when `pkg/__init__.py` also defines or imports that name; the import still loads the package, and that binding is usually the package re-exporting its own submodule.

### Fixed — a `<cycle>` that lists only 12 of its files now says so (thanks @jflowers, #479)

`--deps` lists at most 12 member files per cycle. A cycle with more printed 12 `<f>` rows and nothing marking the cut, so
only `size=` showed that files were missing. It now carries `members_capped="1"` when the list is cut; `size=` stays the
whole count, and a cycle of 12 or fewer files is byte-identical. The 12 rows kept are the first in strongly-connected-
component order: deterministic, not a ranking. The cut on the list of cycles itself (`<cycles total= shown= capped=>`)
landed in 0.6.10.

The new readings move the session legend dictionary to `dictv=61a06791da935602 entries=1114` (docs/COMMANDS.md and the showcase capture are re-recorded).

### Fixed — two benchmark harnesses refuse a malformed bank instead of writing or reading a wrong one (#492)

`bench/agentloop/grade_answers.py` refused a graded TSV whose header had the wrong number of columns, but read a row with more cells than the 13-column header and kept only the first 13, dropping the rest without a word. A row wider than the schema now refuses the whole file by line and row id, whatever the row's status; a row short of trailing cells is still padded, as before. `run_agentloop.py` reads the bank through the same loader.

`bench/roundc-h2h/derive_questions.py` picks six commits per shape at indices `0, stride, …, 5*stride` with `stride = L // 6`. Below six eligible commits the stride is 0, so one commit became six identical questions, and at zero the pick raised `IndexError`. It now refuses to write the bank when a shape has fewer than six eligible commits. The registered RocksDB derivation is unchanged: its smallest list is S4 at `L=270`. Gates: an arm in `test/agentloopgradercheck.sh` and the new `test/roundcderivecheck.sh`, both red on the old code.

### Changed — C++ base clauses are read through `@reference.base` tags captures, #446 round 1 (#538, thanks @SeddonShen)

A C++ class or struct definition now reads its base-clause types (direct, qualified, template and CRTP bases, multiple inheritance) from a `@reference.base` capture in `queries/cpp/tags.scm` instead of the hand-written kind walk, the first language on the bases-as-captures port (`LangFacts::basesAsCaptures`). Template specializations keep their own walk. Answers are unchanged: `--deps`, `--lego` and the map were byte-identical to the previous build on ripwire's own tree and two C++ corpora. Caches are rebuilt once (parser version bump). `test/chacheck.sh` gains a fixture (`test/chafix446`) whose arms fail if a base edge is lost, a nameless struct gains one, or a specialization's base is read twice.

### Fixed — the `mem=` legend names every key of the order it prints (#595, thanks @soarkit)

A compact `--for` owner row lists its member names in `mem=` ordered by question words, then the owner's own file before other files, then path, then line. Both legend clauses stopped short of that: the full one said "question words first, then line", the compact one named no tie-break at all. A reader deriving the order from the legend got a different list whenever a member in another file had an earlier line than one in the owner's file. The order is unchanged (same-file members first is the useful one); both clauses now name owner's file, path, line and name. The cost is the clause only: +25 B compact and +20 B full, on answers that carry `mem=`. @soarkit found the mismatch, wrote the root cause and the two-file Rust reproduction in #595; `test/formembernamescheck.sh` (O arms) runs that reproduction and checks that the printed order is the order derived from the clause's own keys.

### Fixed — a Rust `pub use` that resolves outside the tree no longer hides an in-tree re-export (#610, thanks @soarkit)

A module that re-exports one name twice under exclusive `#[cfg]`s (`pub use external_crate::Config;` and `pub use crate::model::Config;`) lost the class: the first binding marked the name found even though it named nothing in the tree, and every later binding then cleared it. Two re-exports of the same class cancelled each other the same way. A function returning `crate::facade::Config` therefore did not type its result, and `c.get()` on that value was a name-only `via="name"` row. Now a binding that resolves to no in-tree class carries no class, two bindings that agree keep it, and only two bindings that resolve to different in-tree classes stay ambiguous. @soarkit found the bug, wrote the root cause, the fix rule and the three-case fixture in #610; `test/rustmacropathcheck.sh` (X arms) is built from that fixture. Row value on the Rust corpora is about zero (axum, nushell and mdbook hold no same-name re-export pair in a file; zed holds three); the fix is for correct edges.

### Added — `--flags` reports Bash environment-variable reads, and answers `--json` (#641)

In `.sh`, `.bash` and `.zsh` files, every `$X` and `${X…}` is now an env read (`kind="env"`) unless the same file assigned `X` before it. An assignment takes effect where its command ends, so a value that spans lines or a `$( … )` still reads the caller's `X`. Each read row says how the script reads the name: `form=` is `required` (`${X:?}`), `default` (`${X:-d}`), `unset-default` (`${X-d}`), `settest` (`${X:+w}` or a `-n`/`-z` operand), `assign` (`${X:=d}`) or `plain`; `colon=` says whether an empty value counts as unset; `default=` carries the literal default word. Assignments (`X=`, `export X=`, `local`, `declare`, `readonly`, `read`, `for`, `mapfile`, `getopts`, `printf -v`, `(( X = … ))`, and the `REPLY`/`OPTARG`/`MAPFILE` that `read`, `select`, `getopts` and `mapfile` set themselves) are listed as `<write>` rows rather than reads, and a write that reads its own name (`X="${X:-}"`) passes the caller's value through instead of hiding later reads. A prefix assignment (`X=1 cmd`) reaches only that command and is not a write; a function's `local` (or a `declare` without `-g` inside one) hides reads only to that function's end, and a write inside `$( … )` or `( … )` only to that subshell's `)`; an element write `X[i]=v` hides later `${X[…]}` reads but not the scalar `${X:?}`. `-n`/`-z` makes a read a set test only as an operand of `[`, `[[` or `test`. Names Bash or the login always sets (`BASH_*`, `PWD`, `HOME`, `PATH`, …) carry `ambient="1"`; `REPLY` and `OPTARG` do not, since only a command sets them. An expansion inside an array subscript (`${A[${I:?}]}`) is read too. Heredoc closers match exactly (`<<-` strips tabs only, `<<''` closes at an empty line). A shell file with a `GENERATED … DO NOT EDIT` comment banner is skipped and counted as `generated_skipped=` on the root. An expansion nested more than 32 deep inside another's word is not read past that depth, and the root counts such files as `nesting_cut=`, so a crafted line (100,000 nested `${X:-…}` in 600 KB) costs 0.2 s instead of a crash. A paged answer's `next=` keeps the `--flags=SUBSTR` filter. `--flags` joins the `--json` allow-list; keys mirror the XML attributes.

A repository with no shell scripts gets byte-identical `--flags` output (checked on `test/flagsfix` and `src/`, full and compact legend). On fullsend-ai's agents tree, a `bash-env-contract` check fed by `--flags --json` reproduces its regex extractor's findings byte for byte, and drops two false assignments the regex made (`echo "  X=${X}"`). Precision is lexical within one file, like every other `--flags` check: a name set through `eval`, `printf -v "$1"` or a function defined after the read still reads as external. New gate `test/bashenvcheck.sh`.

### Fixed — the MSVC build reads the two `--for` route cue tables again (#710)

`src/forroute.h`'s `kSuffixes` (rule `\bcall(s|ed|ers?)?\b`) and `kPreps` (rule `\b(chain|path)s?\s+(from|between)\b`)
were function-local `constexpr` tables odr-used from *inside* a lambda. MSVC rejects that with
`error C2326: function cannot access 'kSuffixes'`, failing `src/main.cpp.obj` and stopping the `windows (cl, ninja)`
build; `clang-cl`, AppleClang and gcc all accept the same code, so the divergence was invisible outside the `cl` job.
Both tables are now `static constexpr`: a variable with static storage duration is never captured, so no implicit
capture is required of any compiler. No behaviour changes — the route rules, their cues and their order are untouched.

The other 19 function-local `constexpr` tables in `src/` are unaffected: each is passed as an *argument* to the
algorithm (`std::ranges::any_of( kWords, … )`), evaluated in the enclosing function's scope, so no lambda ever
accesses them. `cl` compiled all 19 in the same run that rejected these two.

### Fixed — a TypeScript call through a tsconfig `paths` alias binds through its import (#711, reported by SStonkSS1)

A named import through a `compilerOptions.paths` alias that points inside the root (`import { f } from "@/lib/mod"` with
Next.js's default `@/*` → `./src/*`) now pins its call to the imported definition, as a relative `../lib/mod` import
already did. Before, the call binder asked only the path resolver, which leaves such a specifier unresolved, so the call
bound by its name alone and was declined (`<dc … cands="2" via="declined">`) as soon as any class had a same-named method,
dropping it from `--callers`, `--impact` and `--test-gate`, while the file edge for the same import resolved. The binder
now reads the same tsconfig resolution as the file edge (`baseUrl`, `extends` chains and directory `index.ts` targets
included). Unchanged: an alias whose target is outside the root, missing, or in another workspace root; a bare package
import; a relative import. Gate: `test/lib/tspathsalias.sh`, run by `test/tsimportprecisecheck.sh`.

### Fixed — bench readers decode XML-escaped paths and names before comparing them (#719, thanks @soarkit)

`bench/arb/run_arb.py`'s `query_files` and `trace_files` took `<f p=>`, `<frame p=>` and `<hop p=>` values without undoing the
emitter's escaping, so a file such as `src/a&b.py` ranked as `src/a&amp;b.py` and never matched its gold path; both now decode through
one `xml_path` helper, as `affected_tests` already did. The same capture-without-decode shape is fixed in `bench/tgrep-h2h/arms.py`,
`bench/tokenaudit/sweep.py`, `bench/bench_proof.py` and `bench/spec_trace.py`. `benchxmlpathcheck` pins it against a fake binary.

### Changed — `--arch` names its root and prints root-relative paths; `--abi` and `--arch` drop six derivable attributes and define the rest

**`--arch` answers carry `root=` and every `from=`/`to=`/`path=` is relative to it**, the convention every other verb's root already follows. It used to print each path as the root was typed, so `ripwire "$PWD" --arch=rules.txt` repeated the checkout path in every row: on this repository 45,837 B of a 235,417 B answer (1,389 path attributes), which is now 190,330 B. Under `ripwire .` the saving is the `./` prefix only (192,358 B to 190,299 B). The rows are byte-identical whichever way the root is spelled; a multi-root run has no single root to name and is unchanged. The root's own directory is `path="."`.

**Retired, because each was a second spelling of something beside it.** A script that reads one of these reads the right-hand side instead:

| retired | read instead |
|---|---|
| `<abi head=>` | the first nine characters of `at=` (it still rides where `at=` cannot be stamped) |
| `rows=` on `<abi>` and `<ref>` | the sum of the kind counters `drift= unknown= absent= rename= spelling= stub= head-moved=` (absent at 0) |
| `excluded=` on `<abi>` and `<ref>` | the sum of `rename= spelling= stub= head-moved=` |
| `<struct size_differs=>` | `size_delta=` is not 0 |
| `<arch new_violations=>` | the `<v>` rows without `baselined="1"` (the exit code answers the same question: 2 if any) |
| `<metrics note=>` | nothing: it was 574 B of definitions repeated as data in every answer (764 B beside `zone_unknown=`), and is the legend now |

`capped=` stays on `<abi>` and `<ref>` although it is `dropped` above 0: the bit rides beside every `shown=` in the tool.

**Every attribute the two verbs print is now defined in the answer's own legend.** Before, the default answer defined 6 of the 41 attribute names on the `--abi` fixture below and 1 of the 31 on the `--arch` one; its `--abi` purpose line described a different verb.

Measured, whole default answer, same tree, old binary then new:

| answer | before | after | legend | rows |
|---|---|---|---|---|
| `--abi`, 8-branch fixture | 3,962 B | 5,313 B (+34.1 %) | +1,779 B | −428 B |
| `--abi`, this repository (512 branches) | 23,163 B | 23,901 B (+3.2 %) | +1,770 B | −1,032 B |
| `--arch`, 5-file fixture | 1,465 B | 2,216 B (+51.3 %) | +1,355 B | −604 B |
| `--arch`, this repository, absolute root | 235,417 B | 190,330 B (−19.2 %) | +1,491 B | −46,578 B |

**A small answer is larger than it was.** The definitions cost more than the retirements return until the rows outweigh them; what the bytes buy is that no attribute in either answer has to be guessed. `docs/COMMANDS.md` and the dated showcase capture still show the old `--arch` root until they are next regenerated.

### Changed — test rows that have a runner now group too: `<g … run_each="pytest {p}"/>`

A tests-to-run row with a derivable runner carried `run="<verb> <its own path>"` beside `p=`, and an attribute that repeats the path makes every row distinct, so the `<g n= p="a,b,c">` grouping that already served runner-less rows never fired on a corpus whose tests do have runners. Rows whose command is exactly `<head> <their own path>` now group with their contiguous neighbours of equal attributes and equal head, and the group says the head once as a template: `<g hops="1" n="18" p="a,b,…" run_each="node --test {p}"/>` (JSON `"run_each"`, text `(run each: …)`). A member's command is the template with `{p}` replaced by that member's path, which reconstructs every command exactly. A row whose command is not that shape keeps its own single row and full `run=`: a runner that is another file (`p="test/fuzz/main.cc" run="bash test/integration/hotrestart_test.sh"`), a package entered in a subshell (`(cd pkg && npx jest '…')`), a quoted or `--` path, and a multi-root row; rows of two different verbs never share a group. The form is a template rather than a bare verb because of how it fails unexpanded: `python3 {p}` errors, a bare `pytest` runs the whole suite.

Measured on `--affected` over 12 answers (koa, flake8, starlette, pydantic, django, nest, cpython, terraform, nushell, envoy, vscode, tmux): 472,780 B before, 388,307 B after (-17.9 %). The saving is all on the six answers whose tests have runners: koa 6,189 to 3,146 B (46 rows to 2), nest 62,712 to 28,900 B (379 rows to 33), cpython 80,983 to 40,612 B (773 rows to 203), pydantic 13,057 to 6,831 B, starlette 3,269 to 2,211 B. The six answers whose rows are runner-less (django, terraform, nushell, envoy, vscode, tmux) do not move by a byte. The legend term costs 199 B on a document that carries a `run_each=` row and nothing elsewhere, so a small answer with one two-row group can grow: flake8 2,782 to 2,819 B (+37). Every verb that lists tests to run shares the one row renderer, so `--test-gate`, `--situ`, `--pr-context`, `--handoff`, `--pack-task`, `--exercises`, `--flags --flip` and the MCP twins group the same way. A consumer that reads `run=` off `<test>` rows alone must now also read `run_each=` off `<g>` rows. New gate `test/affectedgroupcheck.sh`; `test/testrowpaths.py` gains `commands`, the one reader that expands a template.

### Changed — a tests-to-run group says its paths folded (`pf=`), lossless: −19.1 % of `--affected` bytes on the held-out set

A `<g>` test group whose paths share directories and an extension now prints them brace-folded: `<g hops="2" n="4" pf="src/{a/{x,y}.test.ts,b.ts},README" run_each="node {p}"/>` (in `--situ` text: `[hops=2] (4 folded): …`). The reader's rule is bash brace expansion over comma lists: it yields exactly `n=` paths in the order `p=` listed them. The writer only folds contiguous runs, never folds a list that holds a literal `{` or `}`, folds a row only when that saves at least 8 B and a document only when its folded rows save at least 256 B; below that bar the answer is byte-identical. A folded row is renamed (`pf=`, `(n folded):`), so `p=` still means verbatim paths and a reader that knows only `p=` fails loudly on a folded row. JSON is unchanged, as are `--pack-task`, `--pr-context`, `--handoff`, `--flags --flip`, `--exercises` and the MCP receipts; `tests=`, `n=`, the commands and the exit codes are computed exactly as before.

Held-out split (n = 206): `--affected` 719,387 to 581,811 B (−19.12 %; fires on 43 answers, the other 163 are byte-identical), `--test-gate` −13.79 %, `--situ` −17.33 %; 0 exceptions to unfold(new) == old over 639 cells, and identical exit codes. What it gives up: a literal full-path grep of the raw answer no longer hits a folded path (the stem and every directory still do). A complement encoding ("every test except …") was priced at a 0.55 % ceiling, cannot be made exact from the index, and was not built. Commit `2ba104e59`; new gate `test/affectedfoldcheck.sh`; `test/testrowpaths.py` expands a folded row.

### Fixed — `--affected` answers for the files it can use when a list also names one it cannot

`--affected=F1,F2,…` refused the whole call (exit 1, nothing on stdout) as soon as one item matched no indexed path and no indexed symbol. The usual way to build that list is `git diff --name-only | paste -sd, -`, and a diff routinely names a file the index does not hold — a deleted file, a `ChangeLog`, a generated, vendored or excluded file — so an agent that changed three source files and a changelog got no tests to run at all.

The call now answers for every item that resolves and names each one it could not use, on the answer itself:

```xml
<affected … tests="2" reached="2" unused="2" …>…<unused item="ChangeLog" reason="not_indexed"/><unused item="src/old.cpp" reason="not_found"/></affected>
```

- `reason="not_indexed"`: a file by that path exists under the root, but the index does not hold it (non-source, excluded, ignored, vendored or oversize; `--skipped` says which), so there is nothing in the graph to reach from it.
- `reason="not_found"`: no indexed path, no indexed symbol and no file match it — a deleted or renamed file, or a typo. The two cannot be told apart without history, so `near=` names the closest indexed path when there is one and the reader decides.

`tests=`, `reached=` and `seeds=` answer for the usable items only, and the test rows are byte-identical to the answer for those items alone. Exit status is 0 when at least one item resolved. A list with **no** usable item is still a refusal (exit 1), never a `tests="0"` answer, and a list of more than one item now says that none of them resolved; a one-item refusal is unchanged. A list with nothing unusable is byte-identical to before. The MCP `affected` verb carries the same disclosure (one renderer). Gate: `test/affectedpathcheck.sh`.

**`--test-gate=F1,F2` and `--situ=F1,F2` take the same fix**, as does the MCP `situational_awareness` verb's `files` argument. `--situ` prints an `unused:` block (one `unused item= reason= [near=]` line per item) above the report, which covers the other items, exit 0; its MCP twin carries an `"unused"` array. `--test-gate` names the items in `unused="N"` and `<unused>` rows (`"unused"` under `--json`) and answers for the rest — but **never exits 0 while a listed item was unusable**, because the gate did not see the whole change: exit 4 when an obligation gates (its meaning unchanged), otherwise exit 6, the code `--quality-delta` already uses for a partial verdict. For every one of these verbs a list with no usable item is still the plain refusal (exit 1), and a list of more than one item says that none of them resolved.

### Fixed — a short "what does X call" `--for` question keeps its source anchor, and "anchor has no source definition" is printed only when true

When a name-exact task spells an identifier that has a source definition (`what does Injector.loadProvider call`, `what does Model.save call`, `where concurrent.futures.ThreadPoolExecutor is defined`):

- the words `call`, `calls`, `invoke` and `invokes` and the question words leave the route, and `route=` names them (`; dropped: call(15-defs)`). A test-only `call` no longer vetoes the anchor into a ranked word list, and a source `invoke` elsewhere no longer anchors the answer and heads it with a callers block for the wrong symbol;
- an anchor that the whole-name index bound to a non-source definition (a Sphinx `.. method:: Model.save` section, a `.github/` copy) is re-bound to the source definition, so the body and the callers are the code's, not the docs page's;
- the identifier's source definition vouches for the route, so the "anchor has no source definition" note no longer fires beside one;
- WH-WORD-GUARD: the question words (`where`, `what`, `which`, `how` and the other question leads) no longer score as whole names, so `Icon.where` no longer heads `where concurrent.futures.ThreadPoolExecutor is defined`.

A task whose identifier has no source definition keeps every word and every note; so does one whose outer qualifiers place nothing (`Missing.futures.ThreadPoolExecutor` does not borrow `futures.ThreadPoolExecutor`'s definition: every qualifier before the last must name a directory, the file stem or a scope segment of that definition). CLI `--for` and MCP `for` share the rule. `test/anchorhonestycheck.sh` pins them and their negatives.

### Fixed — two release-build undefined-behavior sites on adversarial input: a 65,536-parameter list and a contradictory `engines.node`

A parameter list with 65,536 or more children (a Python `def` with 65,535 parameters and one default, for example) wrapped the 16-bit counters behind the minimum-arity fact, so an invariant check trapped the dev build and was silent undefined behavior in a release build. The counters are now 32-bit and the stored parameter count and minimum saturate at 65,535; a saturated count is labelled a floor (`params_floor="1"` in XML, `"params_floor":true` in JSON). A call with 65,536 or more arguments wrapped its argument count to a known 0, so the arity filter could drop the right definition; that count is now unknown and filters nothing. A package.json `engines.node` clause whose ceiling is at or below its floor (`">=18 <0"`, `"^18 <0.0.0"`) broke a postcondition the same way; such a clause now reads as "admits anything", like an upper-bound-led clause, so `--test-gate` keeps `run_unknown="1"` instead of guessing. A prerelease floor under an exclusive ceiling at its own release (`">=22.0.0-rc.1 <22.0.0"`) is not contradictory: it admits that release's prereleases and still gets a command. Neither input occurs in an ordinary repository, and neither value indexed memory or sized an allocation. New arms: the generated wide-list, wide-row floor and 65,536-argument call arms in `test/aritycheck.sh`, z27-z31 in `test/testgatecheck.sh`. Thanks to CodeRabbit for the floor label, the argument-count wrap and the prerelease case.

### Fixed — `--flags` Bash reads: child shells, `local` scope, redirections and quoting no longer hide a caller's variable (#641 follow-up)

Eight findings from the #641 merge review, each with a fixture row in `test/bashenvfix/followup.sh` that failed on main first:

- A write in a pipeline component (`printf x | read -r X`, `X=1 | cat`), a background job (`X=1 &`), or a compound command in a pipeline or in the background (`cmd | while read -r l; do X=1; done`, `{ X=1; } &`) runs in a child shell, so it no longer hides a later `${X:?}`. Inside its own command or loop body it still does. `&&`, `||`, `2>&1`, `&>` and a `|` between case patterns are not pipes or jobs. After `shopt -s lastpipe` a pipeline's last command runs in the script's own shell (read in file order).
- A `( … )` subshell is a pipeline component like any command: after `tar cf - . | (cd /dst && tar xf -)` the pipeline ends at the newline, so a variable set on the next line is the script's own (review of #685).
- `&` backgrounds the whole `&&` / `||` list: in `X=1 && cmd &` the write of `X` ran in the child too, so a later `${X:?}` is the caller's. A `;`, a newline or the `&` itself ends the list (review of #685).
- A later assignment to a name a function made `local` (`local X; X=v`, `read X`, `: ${X:=d}`) stays in that function, like the `local` itself.
- A `$( … )` at command position is the command name, so `$(printf printf) X=1` passes `X=1` as an argument. `X=$( … )` is still an assignment.
- A redirection no longer ends an assignment-only command: `X=1 >/dev/null`, `X=1 > f` and `X=1 2>&1` all set `X`.
- In an unquoted expansion's word, `'…'` quotes, so `: ${A:-'${B:?}'}` reads no `B`. Inside `"…"` a `'` is an ordinary byte, so `"${A:-'${B:?}'}"` still reads `B`.
- A heredoc delimiter `<<"E\"OF"` closes at `E"OF`: inside `"…"` a backslash escapes `$`, `` ` ``, `"` and `\`.
- The read lookup is linear. 160,000 `(X=1)` lines followed by 160,000 reads of `X` (2.1 MB) took about 56 s; they now take about 1 s.
- A file `--flags` cannot open, or cannot read to its end, is disclosed as `unreadable="N"` on the root (and in `--json` and the legend). It used to be skipped silently, and a read error part-way through harvested the prefix as if it were the whole file.

On this repository, fullsend-ai's agents tree and fullsend, every gate is byte-identical to before except one read that becomes correct: `$line` in `test/compactlegendcheck.sh` is set by `eval` at top level, and the `line=` writes that used to hide it are `local` to `softPair()`. Precision stays lexical within one file.

### Fixed — an interface or abstract method no longer answers a confident zero (found in a pre-release comparison run)

A selector naming a method with no body (a TypeScript or Java interface method, a C++ pure virtual, a Go interface method) used to seed `--impact`, `--callers`, `--safe-delete` and `--path` with that signature alone. A call through the interface never binds to a signature, so hono `--impact=Router.match` answered `reaches="0"` beside 23 importers, `--safe-delete=Router.match` said `risk="none-found"`, and nfpm `--impact=Packager.Package` reached 0 while the bare `Package` reached 100. One shared helper (`src/contractseed.h`) now adds the same-named bodied methods of the contract's implementors as seeds: declared implementors in TypeScript, Java and C++, and in Go the types whose methods cover the interface's method set. The root discloses the widening as `impls=K` (`from_impls=`/`to_impls=` on `--path`). `impls="0"` means no implementor was found in the tree, so a zero beside it means none found. `--safe-delete` gains `risk="contract"` for a contract with no callers found, so it never says `none-found` for one. A concrete method, and a C++ declaration with its own out-of-line body, are unchanged.

What it does not change: `--uses`. A call through the interface that the resolver declined still shows as its `<dc>` row, not as a reach.

Versions: the session legend dictionary moves to `dictv=e465b030656de882 entries=1123` (impls=, from_impls=, to_impls=), and docs/COMMANDS.md and the showcase capture are re-recorded; test/printf_parity.manifest re-pinned (moved={help_all}: the `--safe-delete` help text).

### Fixed — a callee signature row under a `<b>` body names the file its line is in

The `<calls><c n= l=>signature</c>` rows under a served `<b>` body (`--expand`, `--pack-task`, `--exemplar`, a `--for` body) printed the callee's definition line and no file, so a row could not be opened. This is the sibling of the hop-callee fix: the same helper (`calleeRowPath`) and the same rule. A row prints `p="<file>"` when the callee is not in its `<b>` row's own file; a row with no `p=` is in the `<b>`'s file. The callee set, the order, `total=` and `shown=` do not move. The legends of those verbs and the dictionary say so.

Measured on 162 fresh answers (108 `--expand`, 54 `--pack-task`, a draw no earlier cell touched; the row's file read from `--callees`, another emitter): 1,126 signature rows, 605 of them (54 %) in a file other than their body's, in 74 answers. After: every one prints its file, 0 print a file `--callees` does not give, 0 print the body's own. Cost where the set of bodies is unchanged: +144 B per `--expand` answer (1.95 %), +77 B per `--pack-task` answer (0.78 %). The path bytes are charged to the body budget, so an answer already at its budget serves fewer whole bodies, disclosed as before (`capped="1"`, `unserved_total=`): 2 of 162 answers moved, the larger `vscode --expand=clear` (328 matches) 277 to 223 bodies. Gate: `test/bodycalleefilecheck.sh`.

What it does not mean: the JSON dialect's `calls[]` (`{n,l,sig}`) still carries no file.

### Fixed — the HEAD-binary build and the bench harnesses are bounded: no unlimited `make -j`, and a timeout or a signal-kill is its own recorded state

`test/lib/headbinlib.sh` built the HEAD comparison binary with a bare `-j`, which under make means unlimited jobs; it now uses `headbin_jobs`: `CMAKE_BUILD_PARALLEL_LEVEL`, then `RIPWIRE_HEADBIN_JOBS`, then the CPU count under GitHub Actions, otherwise `max(1, min(ncpu/2, GiB/8))` (an invalid value is ignored with one stderr line). `bench/recalleval/run_r3diff.py` now defaults to `min(6, ncpu/2)` parallel jobs. Every whole-repo ripwire spawn in the bench scripts now has a timeout, and a killed or timed-out run is recorded as `timeout`/`killed(signal=N)` (or the script's existing state family) instead of an error code or, worse, a graded partial answer; a normal run's output is byte-identical. CI's staging step is unchanged. Commits `bf3fc5e62`, `bf9b44395`.

### Fixed — `--for --token-budget`: `past_target=` and `files_first=` count the rows the answer still shows

Under an explicit `--for --token-budget=N` the answer is the unbudgeted answer shed to the budget, and its `rows:N` unit cuts the worst-ranked rows first. The shed rewrote `<sigs past_target="K">` as the unbudgeted K less the rows it cut, which is true only when the rows past the target are the last ones; the head round-robin (it lifts other files' best rows into ranks 1..8) and the docs reorder (moved doc rows take the worst ranks) both renumber them. It rewrote `files_first="N"` as at most the rows kept, which is true only when every kept row is one the round-robin moved. On the 89 development questions from 11 open-source repositories, `files_first=` claimed more moved rows than the answer showed on 83 of the 87 checkable answers at `--token-budget=1600` (for example 4 rows and `files_first="4"` where 3 had moved, or none), and `past_target=`'s legend reading stayed behind without its attribute on 74.

The shed now counts both over the rows it keeps, by the ranks the render gave those rows. A count of zero leaves the attribute and its legend reading out, as `docs_after_code=` already did. The shed also prices each candidate cut as the document it would print, recounts included, so the bytes a removed reading frees go to rows: on the 89 development questions from 11 open-source repositories, 41 answers at `--token-budget=3000` keep 1 to 3 more rows (none fewer; none changes at 1600 or 6000), and `est_tokens=` still stays within the target wherever the answer is above its 4-row floor. The unbudgeted answer, `--json`, the MCP `for` verb and `--pack-task` have no shed after the render and are unchanged. The `past_target=` legend reading no longer says the counted rows are "the last K rows": the head round-robin and the docs reorder give them any rank, so that was false on 16 of 74 unbudgeted answers to the 89 development questions from 11 open-source repositories. It now says only what it counts — K shown rows are past the target, none is cut — and is shorter than before, so it costs no row; the `--help` text says the same. Gate: `test/forbudgetcountscheck.sh` (its (R) arm fails a reading that places the rows where they are not).

### Fixed — a C function passed as an argument and stored into a struct field names who may call it

tmux registers `client_signal` with `proc_set_signals( client_proc, client_signal )`; `proc_set_signals` stores the parameter (`tp->signalcb = signalcb;`) and `proc_signal_cb` calls the field. The `<vr>` row on `--callers` / `--impact` and the MCP callers twin stopped at `into="proc_set_signals#arg1"`. Go and Rust already joined a registrar's stored parameter to its field slot; the C family now records the same fact, typed by the object's declared struct type exactly as a function stored there directly is, so the row reads `called_by="proc_signal_cb" called_at="proc.c:129" via="slot" cands="2"`. It is a may-call through a slot, never an edge: `count=`, `reaches=` and the graph do not move. A field of another struct type with the same name does not join, nor does a parameter kept in a local or stored into two fields. A C++ member store without `x->` (`cb_ = cb`) is not read. Caches rebuild once (`kParserVer` 315, a placeholder). Gate: `test/paramslotcheck.sh`.

### Fixed — a `--for` hop-callee row names the file its line is in, and no longer joins two files' lines

`<hops>` listed each callee of a ranked symbol as `<c n= l=/>`: the definition line and no file. A line with no file cannot be opened, and nothing said so; `--callees` printed `p="file:line"` for the same edge. The row also merged same-named callees by name alone, so `h.render()` in `html.ts:3` and `t.render()` in `text.ts:9` came out as `<c n="render" l="3,9"/>`. On 140 `--for` answers 131 of the 176 rows that joined more than one line joined lines of more than one file.

- A hop-callee row prints `p="<file>"` when the callee is not in its `<h>` row's own file. A row with no `p=` is in the `<h>` row's file. The legend says so (`c n= l= p= (p= if not h's; …)`), and so does the dictionary.
- Same-named callees merge only within one file, so every line of one `l=` is a line of that row's file. A row that used to join two files' lines is now two rows. `total=` and `shown=` still count callees and do not move.
- `p=` is the callee symbol's own indexed file, the record `l=` is read from. A `via="name"` row keeps `via="name"`: the file is right for the line it prints, and the edge is as hedged as it was.
- The path bytes are charged to the hop budget. With no `--token-budget` nothing is cut; under a tight one the hop section can be dropped sooner than before, with the same `capped="1" next=` disclosure.

Measured at item grain with the hand-check location extractor, strict rule (same file, line within 3). On the 15 items that motivated it: 0 located before, 12 after; the other 3 are printed with the right file and line where the extractor does not read them (a line that is not first in `l=`, a same-file row). On a fresh draw of 127 other cells under a different wording: 186 to 189 of 339 required items, 0 lost. Cost: +535 B per answer on the fresh draw (1.63 %), +901 B on the development cells (2.20 %); the legend's share is 6 B. All 2,879 printed lines on the fresh and development answers, 1,013 of them `via="name"`, are spelled by the file their row names. Gate: `test/calleerowfilecheck.sh`.

What it does not mean: the `<c n= l=>signature</c>` rows under `<b>` bodies are unchanged and still carry no file, and the MCP `for` tool prints no `<hops>` at all. Three of 153 answers change one count outside `<hops>` (`<syms name_total=>` falls by 1): that section skips a candidate whose name is a word of the answer, and a printed path adds words. No `<syms>` row changed.

### Fixed — MCP `find_referencing_symbols` binds a narrowed callers selector like `--callers`

`--callers=Owner.method`, refused as written over several definitions, answers for its one source definition (the GV-PATH-BIND rule, `narrowed=`). MCP `find_referencing_symbols` and the `callers` batch verb ran their own copy of the row lookup without that step and refused the same spelling with "symbol not found". Both surfaces now call one binder, `callHierarchyRowsNarrowed` in `src/forgraphverb.h`, and the MCP answer carries `"narrowed"` and its `narrowed_note`. A spelling that still fits two source definitions refuses on both surfaces, as before. New arm (d5) in `test/gvassemblycheck.sh`.

### Changed — a warm clone pass no longer re-reads every file

The exact clone pass behind `--clones`, the `clone=` attribute of `--for`, `--partition` and the `--quality-delta` duplication kinds read every file with a function in it and normalized every body on every run, warm or cold. On cockroach that was about 9,500 files and 120 MB per warm `--for`. Each function and method body now gets a 64-bit key at parse time (a hash of its normalized token stream plus its token count), computed from the bytes the parser already holds and stored in the cache record. A warm pass groups bodies by key without opening a file, then re-reads only the bodies whose key another body shares and compares their real normalized text as before, so two bodies whose keys collide are never reported as clones. On cockroach a warm `--for` retires 15 % fewer instructions (median of three interleaved pairs, 43.9 G to 37.1 G) with the same answer bytes; peak live heap grows 0.1 % (1.5 MB). A cold run costs no measurable extra (envoy cold `--deps` 381 G before, 375 G after, inside run-to-run noise). The cache format moves to 50 (each definition record gains a key-presence byte and each keyed body its key: +0.5 % cache bytes on cockroach, +0.6 % on envoy), so an older cache is rebuilt once. Two clone groups whose first members share a file and line are now ordered by symbol id, where the order was unspecified before. New gate `test/clonepersistcheck.sh` forces two different bodies onto one key and requires that they are not reported as clones.

### Fixed — `--connect` never names a test function as the joint of two source symbols

When every `--connect` terminal is source code, the search no longer walks through test or fixture code (the `--defs class="test"` rule), so a test that calls both terminals is never printed as their common caller. terraform's `--connect=Context.Plan,Context.Apply` used to answer `TestContext2Apply_nullableVariables`; it now answers a source chain. When no source function joins the terminals within the radius, they are listed `<unconnected>` and the root says `source_joint="none"`, naming a test-class function that joins the terminals the source search left apart as `test_joint=` / `test_joint_p=` (an undirected join through test code, test-only evidence, not a source caller). A test terminal keeps the old search. CLI `--connect`, the `--for` `<graph_verb>` block and the MCP `connect` verb share the rule. `test/connectsourcejointcheck.sh`. Found in a pre-release cross-check.

The compact reading moves the session legend dictionary to `dictv=29479b4c9813f24d entries=1061` (docs/COMMANDS.md and the showcase capture are re-recorded).

### Fixed — a C++ call no longer binds to a same-named base class in another namespace

`connection_.state()` on a `Network::Connection&` printed `Http::FilterManager::state` as a resolved callee
(envoy: 36 callers listed for that method, the sampled ones all wrong). Two things went wrong together. The
base walk reads a table of method BODIES, so it passed the pure virtual `Connection::state` that ends C++'s
lookup; and it followed the base clause `: public FilterManager` by its bare name into the unrelated
`Http::FilterManager`. A bare call inside a member function went wrong the same way through the ladder's
"the caller's class reaches it" proof.

Both now read the base the deriving class names: the scope its clause is written in (a qualifier, the class it
is nested in, the namespaces its file defines things in), then the base the implementors map proved, then the
one same-named class its file includes. A class that declares the member with no body ends the walk, and the
call goes to the interface tier (one implementor is the edge; several decline with `gate="iface"`). A base
name that stays two classes is not bound: the call is hedged `via="name"` or declined, never a plain row. A
bare call to a name the class or a base declares with no body no longer falls to a free function of that name.

Measured on envoy with `--pin-census` before and after (321,956 call sites): 326 sites change.
`--callers` of `Http::FilterManager::state` goes from 36 callers (33 unhedged) to 8 (3 unhedged), and those 3
are its own (`UpstreamFilterManager::sendLocalReply`, `::isAborted`, `ActiveStreamDecoderFilter::injectDecodedData`).
ninja: 1 site of 5,765 (`DiskInterface::MakeDirs` no longer binds the pure virtual `MakeDir` call to the file's
free function). Only the C-family walk changed; the waybar and htop maps are byte-identical.

What it does NOT mean: a class's namespace is still not in the index. Where a base name has two classes and
neither the clause's scope nor the includes single one out, the call is hedged, not resolved. The walk still
starts from the receiver type's final name segment (`prov="final-segment"` discloses that), and a field read
from a base class is still found by the base's name.

### Fixed — C++ calls through smart-pointer locals, parameters and aliases reach the interface tier instead of every namesake

A C++ local or parameter declared as a `std::unique_ptr<T>` / `std::shared_ptr<T>`, or as an alias of one (`Event::TimerPtr t`, `const CodecPtr& c`, `typedef std::shared_ptr<Widget> WidgetSharedPtr`), was untyped: `t->enabled()` was matched by name against every in-tree `enabled`. Such a declaration is now its pointee through `->`, as a member written that way already was: a concrete pointee is a typed edge, an interface declines `gate="iface"` with its implementors counted. A pointer to the smart pointer (`CodecPtr* p`), `.` on it (`c.reset()`), an alias two namespaces declare for different pointees, a template alias (`Ptr<T>`), `c.get()->m()` and `(*c).m()` keep the previous reading. The interface tier also counts an implementor defined out of line as a nested class (`class Mgr::RangeTimerImpl : public Timer`, envoy) and one that inherits its body through a sibling base (`ConnectionSocketImpl : SocketImpl`); a member typed as an interface whose split holds one unproven body while another definition shares its name now declines `cands="1"` instead of listing every same-named method by name (a lone definition keeps its one by-name row). Caches are rebuilt once (parser version bump).

### Changed — the cross-branch verbs answer in repositories with more than 512 local branches

`--whereis`, `--stray-content` (with `--plan` and `--abi`), `--eval-stray` and the MCP `whereis` and `stray_content` tools used
to refuse when a repository had more than 512 local branches, which a long-lived clone with many work branches does. They now
read the newest 512 branches by committer date and print `refs_omitted=K` on the answer's root for the K older ones they did not
read. `--whereis` drops `complete="1"` whenever refs were left out, and `--eval-stray` reads every labelled branch first, so a
labelled branch is scored, not left out, as long as the labels fit the 512-branch window; past 512 labels, `labels_omitted=K`
counts the labelled branches left out and not scored. A ref-name substring (`--stray-content=SUBSTR`, or `kind=` over MCP) chooses which
branches fill the 512.

The window stays at 512 because both sweeps cost about the same per branch at any count. `--stray-content` runs about two git
processes per branch: 77 s at 511 branches and 278 s at 2,048 on an M2, with peak memory flat at 13-19 MB. `--whereis` holds
every branch's tree listing at once: 849 MB at 8,192 branches of a 200-file tree, and 0.7-1.0 GB at 524 branches of a 5,239-file
tree. With the window, `--whereis` over 8,192 branches peaks at 69 MB. Below 512 branches nothing changes.

The two compact readings (`refs_omitted`, `labels_omitted`) move the session legend dictionary to `dictv=7dfad3da38492336 entries=1109` (docs/COMMANDS.md and the showcase capture carry the pair).

### Changed — `--format=columnar` carries the declined-call rows as arrays, and a windowed `--callers` / `--impact` root names the complete call

The columnar form removed 46 % of a complete `--impact` answer's symbol rows and none of its `<dc>` rows, which it printed verbatim: on the 32 windowed impact cells of the registered population (39 symbols, five corpora) those rows were 17,479,478 of 30,101,002 B, 58.1 % of the answer.

- Under `--format=columnar`, an answer of `--callers`, `--callees` or `--impact` that lists more than 16 declined call sites (the default cut, so only one whose `--limit` lifted it) carries them as one `<dcols n= via="declined" fields=…>` block of parallel arrays after `</cols>`: `path` (an index into the answer's one `<paths>` table), `in`, `line`, `cands`, and `gate`, `bound`, `of_def`, `cand`, `cand_more` where a site has them. An empty cell is an absent attribute. Every `<dc>` row can be rebuilt from the block byte for byte. At 16 sites or fewer the form prints the rows as before: a table that small is not smaller as arrays once its definition is paid for. The XML form, `--json` and the MCP answers are unchanged.
- Measured at `--limit=<total>` on those 32 cells, against the build this change was merged onto: 30,101,002 B to 18,525,158 B (−38.5 %), the declined-call payload −66.2 % with its added path-table entries counted, the legend +1,974 B. All 186,584 declined-call rows of the 120 columnar answers measured are unchanged in content and order.
- A `--callers` or `--impact` root that windows (`has_more="1"`) carries `all_next="--impact=X --format=columnar --limit=N"` (`--callers=X` on a `--callers` root): the one call that lists every row, `N` the row total. The attribute is written from the window the verb computed for that answer, never predicted: 0 false positives and 0 false negatives on 156 measured answers. It costs about 160 B on a windowed first page (the attribute and its legend clause). `--json` and the MCP `impact` / `find_referencing_symbols` answers carry it as well; `RIPWIRE_NO_WINDOW_HANDOFF=1` turns it off. `--callees` pages the same way and is not given the pointer: it is in no measured population.
- `N` is not raised to cover the declined call sites. That was built and measured: it listed 61,381 more hedge rows on 12 cells (one with 99 rows and 4,005 declined sites) and took the median bytes to a complete answer from 77,797 to 145,532. A named call that holds more declined sites than rows says so (`dc_shown=`), and `dc_next=` names the call that lists them all.
- `dc_next=` on a columnar answer now keeps `--format=columnar` (it named the XML form): 9,288,829 B against 22,440,635 B for the 12 such calls measured.
- No answer moves from windowed to complete in one call: `--impact` windows on a row cap, and the default form is unchanged. What moves is the second call: over 39 impact cells the first page plus the named call is 77,797 B at the median against 132,960 B for the first page plus `--limit=<total>` in XML.
- The file roll-up is unchanged. It is absent from a complete answer and already withheld, by name, from the columnar form.

`test/dccolumnarcheck.sh` rebuilds every `<dc>` row from the block and compares it with the XML form, requires the pointer on exactly the windowed roots and the named call to list every row, and turns seven mutations of the real binary red, three of which lose a declined-call fact.

### Changed — `--impact`'s help says what `--limit` sizes, and the declined-tier disclosure of a named call is gated on every surface

The call a windowed `--callers` / `--impact` root names in `all_next=` carries `--limit=<row total>`, and `--limit` sizes the declined call sites as well as the rows. Where an answer holds more declined sites than rows, that call still cuts them. It was reported as a silent cut. It is not one: the answer says `dc_shown=` (the sites printed), `declined_calls=` (the tier's count, a floor) and `dc_next=` (the call that lists them all), in XML, columnar, `--json` and the MCP twins. Re-measured on 32 windowed impact cells of five corpora: 15 named calls cut the tier (102,979 of 179,022 sites listed) and 15 of 15 carry all three.

- No answer changes: 72 of 72 corpus documents are byte-identical to the previous binary.
- `--impact`'s help said the named call "lists every row". It now reads "every row of total=" and says that `--limit` sizes the declined call sites too, naming `dc_shown=`, `declined_calls=` and `dc_next=`.
- `test/dctiercutcheck.sh` asserts on six surfaces of each named call (reached from a `--impact` root, a `--callers` root and a `--for` hand-off) that a cut tier is said, that `dc_shown=` is the number of sites printed, and that `dc_next=`, run verbatim, lists every site and the same rows. Three mutations of the real binary turn it red, two of which hide or misstate the cut from the reader.
- Sizing the declined tier apart from `--limit`, and a pointer that clears both tiers, were both considered and not taken (`docs/EVALS.md`, amendment 10c): the second measured 145,532 B against 77,797 B at the median in amendment 10b.

### Added — `--for` names the call that makes a head name's value, and the declaration that holds a dispatch candidate (DECL-PRINT)

Two rows for answers that already rank the right head (found in a pre-release review of residual misses):

- `<syms>` gains `by="init"` rows. When one of the first five `<d>` rows, or the re-export walk's `<def>` row, names a value that a module-level declaration makes with one call (`export const Component: ComponentDecorator = makeDecorator(…)`, `registry = make_registry()`), the row names that call's callee, with `of=` the name and `at=` the declaration. The call must be a file-scope call that resolves to exactly one definition, and a callee a shown row already stands on is not repeated. `RIPWIRE_NO_INIT_ROWS=1` turns the rule off.
- `<dispatch>` gains `<s held="member|local">` rows. When no non-test constructor call makes a shown candidate's type, the by-value declarations that hold it are printed with their line as text: a C++ field (ninja's `RealDiskInterface disk_interface_;` in `NinjaMain`) or a function's local. Pointers, references, parameters and test code give no row. There are two rows per call, and `capped="1"` when more exist.

### Changed — a `--for` answer prints a one-line `Owner.member` declaration with a bodied twin as a tail pointer

A ranked `<sigs>` `<d>` row that is a one-line owner-qualified declaration (`l=` equals `e=`, `n=` is `Owner.member` / `Owner::member`: a TypeScript interface member, a `.d.ts` line, a C++ in-class prototype) whose last name segment is also the name of a bodied `<sigs>` row of the same answer (`l=` and `e=` present and unequal) is now printed in its place as a tail pointer `<t p="FILE" sym="NAME" r="RANK"/>`: the body row is the answer, the pointer keeps the declaration on screen. On the graded sets these declarations sat at ranks 1-3 above their bodies (`LanguageService.getCompletionsAtPosition` above `services.ts`'s body) and carried picked decoys.

A row stays a row when it carries `mem=`, `slot_by=` or `slot_fields=`, when it carries a `--note-add` note, or when the task names it (a qualified task word such as `LanguageService.getCompletionsAtPosition` names that full name; a bare word names the last segment; `Completions.getCompletionsAtPosition` does not name `LanguageService.getCompletionsAtPosition`). A short legend comment rides before the first pointer, only when the rule fires. A token budget leaves the answer as shaped and `--json` never reaches the rule; `est_tokens=` is re-priced over the rewritten bytes. CLI `--for` and MCP `for` share the one renderer; `RIPWIRE_NO_DECL_TWIN=1` turns it off.

The rule is DECL-TWIN from the wrong-items census, measured offline by the precision lab (`tools/precision_lab.py`) before it was built. `test/fordecltwincheck.sh` pins it, its guards and its negatives.

### Fixed — a build off a release tag says so in its version (`0.6.10-dev.41+g5593593d3`)

A build of `main` 46 commits past `v0.6.10` printed a plain `0.6.10`, so a bug report, a benchmark rung or an agent's MCP client could not tell it from the release. The version is now a label: exactly `X.Y.Z` on the tag `vX.Y.Z` (`+dirty` with tracked edits), `X.Y.Z-dev.N+g<sha9>` for N first-parent commits past it, `X.Y.Z-dev+g<sha9>` in a checkout with no such tag (a tagless shallow clone), and `X.Y.Z-dev` with no git at all, never the bare release number. `--version`, the MCP `serverInfo.version` (which said `1.0` whatever the build), the LSP `serverInfo.version`, the `--html` page and `--doctor`'s version-mismatch hint all print the same label. Release tag builds are unchanged. Found in a pre-release comparison run on a fresh machine; `test/versionlabelcheck.sh` pins a tag, a dirty tag, a dev, a tagless and a no-git build, and that every surface agrees.

### Changed — `--legend-have=` takes legend TIERS, so the handshake pays for itself in about ten calls instead of about 130

`--legend-have=` lets a CLI caller say which legend definitions are already in its context, so answers stop re-sending them. The only holding it could name was the whole dictionary: 131,571 B for 1,002 B saved per call, **131 calls to repay** (453 answers of 12 verbs on five corpora). Every guidance site therefore told a short session to pass nothing.

The dictionary is now served in tiers, each with its own version:

- `ripwire --legend-dict=core` — 13 definitions, **1,512 B**: the six ref-posture readings, the reading of `have=`, and the six terms that cross verbs (`root=`, `next=`, `counts_floor=`, the two resolver gauges, `graph_unindexed=`, `est_tokens=`).
- `ripwire --legend-dict=KEY` (a schema key: `callers`, `impact`, `grep`, …) — the core plus that verb's pack, the definitions at least a third of its measured answers carried. 51 schemas have a pack; a schema that was never measured answers the core with `census=0`.
- `ripwire --legend-dict` — every line, as before.

Line 1 of a tier carries `have=<16 hex>`, the FNV-1a 64 of exactly the `entries=` lines after it. `--legend-have=` takes one or several of those values, comma-joined.

**An answer never claims a definition its reader does not hold.** A definition in a tier the caller named is left out; one in no named tier stays in that answer, in a comment after the rows. `<about legend="ref" have="core|core+KEY…|full" …/>` says what was assumed. Before this the CLI served a caller as if it held everything, which was honest only because "everything" was the one thing a caller could say.

Measured on the same 453 answers, on the built binary:

| holding | bytes to read | saved per call | repays in |
| --- | ---: | ---: | ---: |
| whole dictionary | 131,710 | 991.8 | 133 calls |
| core | 1,512 | 148.6 | **11 calls** (9 over the 388 answers that are not `--for`; 9 to 17 by corpus) |
| core + the verb's own pack | +415 to +2,300 for the eleven everyday verbs | 849.8 (85.7 % of the whole dictionary's saving) | a pack repays in 1.3 to 2.0 calls of its verb |

This is **not** "single-digit": it is 11 on the registered population and 17 on koa alone.

Refusals: an empty value (unchanged); **any value that is no tier of this binary, even beside a valid one** — the message names the value, the tiers the rest of the list did name, and `ripwire --legend-dict=core` with its real size, where it used to prescribe the whole dictionary; `--mcp`/`--listen`/`--lsp`; `--legend=full`. A valid pack passed on another schema's answer is honoured, never refused.

An answer served inline under the handshake now says so on stderr, and which of the two reasons applies: `not-applicable` (the dictionary does not reduce that legend — every `--for` answer, 65 of 65) or `inline-kept` (the reduced answer would not be shorter). Stdout is unchanged in both. The same `not-applicable` line now also goes to stderr for `--situ`, `--recall`, `--report`, `--mermaid`, `--html`, `--plan-lanes`, `--sarif` and the evaluation surfaces (`ripwire: --legend-have=: not-applicable — <surface> answers with no XML legend the legend dictionary reduces, so it is served whole; nothing was saved`), which said nothing before; a stale value is still refused first (commit `35b71f385`; `test/legendhavecheck.sh`).

Also new: `--legend-dict=tiers` (every tier: name, `have=`, entries, bytes, census) and `--legend-dict=index` (every entry by what it defines). The MCP stdio session is unchanged and carries no `have=`.

Guidance: `--help`, the empty-value refusal, `ripwire wrap`'s primer line and the `ripwire-router` and `ripwire-mcp` skills now teach the core read and its measured cost.

Gate: `test/legendtiercheck.sh` (BAND K (tiers), docs/EVALS.md amendment 11) — held-or-carried at bar 0 over every cell and holding, tier identity, the refusals, a pack costs at most 3x its per-call gain, and the repayment pin (core at most 1,536 B, `ceil(B/S)` at most 12, no core term under 25 % of the cells), with twelve registered mutants and three single-arm ones re-run on every invocation. `src/legendpacks.h` is a build product of `bench/legendtier/census.tsv`.

Versions: the legend dictionary's release pair is stated once in the `versions` entry (`dictv=cd0a012a40de1479 entries=1294`); docs/COMMANDS.md and the newest showcase capture record it.

### Fixed — the legend dictionary now holds the `<file-scope>` reading, and `--legend-have=` guidance has the caller read what it asserts

Two defects in the legend handshake, both about the one thing the dictionary is for.

**A definition that existed nowhere.** The compact legend's `<file-scope> (t=modscope)` reading was written by the composer itself and was not a legend-dictionary entry. A ref answer (`--legend-have=DICTV` on the CLI, the MCP session posture) drops its legend because the reader holds the dictionary, so this sentence was dropped and the dictionary its pointer names had no line for it: a reader holding every entry still had no definition of the `<file-scope>` row in front of it. Measured on 239 answers (koa, tmux, terraform; 10 symbol verbs at map ranks 1, 2, 4 … 128, plus the map, `--dead-code` and `--hotspots`): 25 carried the reading, all 25 took the ref posture, and none of the 25 kept it. It is now an entry — the last one, so no existing entry id moves — and the handshake's bytes are unchanged on all 239 cells. `reduceCompactLegend` additionally rebuilds the legend from its entries before dropping anything: a clause the composer writes without an entry now keeps its answer inline, disclosed, rather than vanishing.

**Guidance that asserted what it never read.** `--legend-have=` is the caller's assertion that it holds the dictionary. The empty-value refusal, both skills (`ripwire-router`, `ripwire-mcp`) and the SessionStart primer all taught `ripwire --legend-dict | head -1`: 78 bytes read, the other 130,243 asserted. The refusal's own example also could not run — its `tr -dc '0-9a-f'` kept the hex letters of the words around the version, so the value it built was refused. Every site now teaches `ripwire --legend-dict`, read whole, with the value on its line 1, and states the cost: about 130 KB, which at the 896 B per call measured over 453 answers takes on the order of 140 calls to repay. On a short session the honest advice is to pass no `--legend-have=` at all, and the text says so. The handshake refuses nothing it did not refuse before.

Not changed, and reported rather than fixed: the Elixir inert-quote variants of `declined_calls=` and `declined=` are also written by the composer and are not entries. They are not in the same state — an answer carrying one fails the recompute and keeps its whole legend inline — and `test/legendhavecheck.sh` (M3) now holds that. The `-30.4 % over 80 recorded answers` figure in `--help` is left as published; the 453-answer measurement puts the same saving at 896 B per call.

Gate: `test/legendhavecheck.sh` — (A0) the gate itself now holds the dictionary instead of cutting it to line 1; (M0)–(M3) every clause a reduced answer drops is a line of the held dictionary, on a fixture of its own with a counted `<file-scope>` row, with a control that deletes each dropped line in turn; (T0)–(T3) the command the refusal teaches is run as written and must print the whole dictionary, the first-line cut must be rejected by the same check, no guidance site may pipe the dictionary into one, and the stated size must be within 10 % of the dictionary's.

Versions: the session legend dictionary moves to `dictv=cf491fcb08dfcb9a entries=1149` (the `<file-scope>` entry); docs/COMMANDS.md and the 2026-11-13 showcase capture record the new pair.

### Fixed — `--for --token-budget`: `docs_after_code=` counts the doc rows the answer still shows

`<sigs docs_after_code="N">` reads "N doc rows of the shown set moved below its code rows". Under an explicit `--for --token-budget=N` the answer is the unbudgeted answer shed to the budget, and its `rows:N` unit cuts the worst-ranked rows first — which, after the docs reorder, are exactly the doc rows it moved. The shed rewrote `shown=`, `docs_dropped=`, `past_target=` and `files_first=` but left `docs_after_code=` at the unbudgeted count, so a budgeted answer could show only code rows and still say doc rows of its shown set had moved: on 89 development questions from 11 open-source repositories, every one of the 20 answers carrying it at `--token-budget=1600` and at `3000` showed no doc row at all (for example 4 code rows with `docs_after_code="3"`).

The shed now recounts it over the rows it keeps, by the ranks the reorder gave the rows it moved: the count of moved doc rows still shown, and when none is shown the attribute and its legend reading are both absent. **Which rows are shown, their order and their text do not change** — the shed still chooses its cut against the price of the unbudgeted count, so it keeps exactly the rows it kept before; `est_tokens=` prices the document actually printed, so it falls by the bytes the recount removes. The unbudgeted answer, `--json`, the MCP `for` verb and `--pack-task` already counted after their own cut and are unchanged. Gate: `test/fordocsaftercodecheck.sh`.

### Changed — `--recall` ranks document sections, and HTML pages have sections

`--recall` (and MCP `memory_recall`) now scores each section of a document on its own text. A section is a heading and the prose up to the next heading of any depth; text before the first heading is a section of its own when it holds real prose. Before, a heading was scored on everything nested under it, the whole file was scored as one more entry, and code symbols counted in the word statistics. A long page then often won on sheer size, and its best section was not the one served. Now the statistics come from the documents' sections only, and a file ranks by its best section.

HTML pages are read as a section tree. The text comes from the page's content region (`<main>`, else `<article>`, else a content `<div>`, else `<body>`). Navigation, sidebars, headers, footers, search boxes and tables of contents are left out. Headings and `<section id>` elements are sections, and `lines=` names the HTML file's own lines. Before, a page was one flat text served from its first bytes, which on a generated docs site was mostly navigation.

HTML sections are for `--recall` alone. `--for`, `--query`, MCP `for` and pack-task rank an HTML page as before, from the page's whole text. Name lookups (`--callers`, `--defs`, a call edge, a Markdown link to a heading) do not bind a section either, PageRank gives it no weight, and the map neither counts it in `symbols=` nor prints it as a row. So a doc heading spelled like a function cannot push that function down a `--for` answer or make `--callers` report two kinds. A file-qualified selector (`page.html:Heading`) still reaches a section. The one place `--for` uses them is its `<doc_body>` block: it picks the sections of the doc files an answer shows with `--recall`'s own section scores, so an HTML page there is served by its matching section, not its head. On 321 in-sample `--for` calls, 305 are byte-identical to the previous release and the other 16 keep every graded item: 13 differ in `<doc_body>`'s sections, the rest in a served HTML page body cut a few bytes shorter or longer, a Sphinx page's `sym=` order and one `--token-budget` hint.

A directory whose documents repeat the level above it, such as a version copy (`master/`, `2.0/`) or a translation (`fr/`), is left out of the ranking. The rule is structural: at least 4 documents, and at least three quarters of them at the same relative path one level up. The header says so with `mirror_skipped=` and `mirror_dirs=`. Other verbs still see those files. A query of more than 1024 distinct terms is scored on the first 1024, and the header says so with `terms_capped=1 terms_total=N`.

Measured on 79 development docs questions (Markdown, reStructuredText and rendered HTML sites from eleven open-source projects) with a mechanical anchor grader: fully answered rose from 43 to 53, and the mean answer fell from 15.5 KB to 13.8 KB. On 28 held-out questions, fully answered rose from 13 to 19; on a second held-out set of 20 it stayed at 8, with one fewer wrong answer. The design was picked in an offline comparison of model-free retrieval methods; credit to the community discussion on #409, #414, #417, #427, #428 and #429 that shaped it.

### Changed — `--quality-delta`: a new function at the ceiling (4x the bar) now gates; constructors and moved bodies stop reading as new debt

Until now a new function never made `--quality-delta` exit 2, however large it was. A NEW complexity or verbosity row in non-test code now gates once it reaches 4 times the bar (ccx 60, or 240 code lines; `kNewSymbolCeilingMul`), and the row carries `ceiling="60"` or `ceiling="240"` (`"ceiling":N` in `--json` and over MCP). Test drivers (any path `isTestPath` reads as test code) still only report. New-symbol rows otherwise still never gate: "new-symbol rows never gate, except defect-shape format-arity and a new function at the ceiling".

Two fixes come first. Without them, rows at that size were noise:

- A C++ constructor no longer carries its class's extent. `class TextPool` and `TextPool::TextPool` share one canonical id, and the per-id maximum gave the constructor's verbosity row the whole class (129 and 149 lines on two recent merges). Where a function or method shares the id, the container measures 0 there. `--metrics` is unchanged.
- A new function whose body left another symbol in the same diff is a move. It prints `origin="moved"`, still counts in `new-symbol=`, and never gates. The source is a baseline body whose symbol is gone or now under the bars (a renamed body whose old name stays as a thin wrapper counts). The match is exact (the body scrubbed of whitespace and its own name), or near: the two bodies are each other's best match by the clone matcher's own minhash sketch, at a k-gram Jaccard of 0.70 or more (`kMoveSketchMinJaccardPct`, decided on the integer match count: 90 of 128 sketch components). On the last 30 merges the three real moves scored 0.85 to 0.98, and the best non-move 0.31. A body that was copied while the original stayed is not a move. The dead-code row of a moved symbol still reads `origin="new-symbol"`.

`test/qdentryceilingcheck.sh` pins a 250-line function and a ccx-61 function that gate; ccx-59 and 239-line functions, a moved body, a renamed body with a 4-statement edit, a constructor and a test driver that do not; a genuinely new function with a similar name beside a removed body, which still gates; the copy that still gates; `--json`; and all three legends. Each negative arm counts its premise and fails on zero.

Versions: `kQSnapCacheScheme` 26 -> 29 (a cached snapshot is recomputed once). The session legend dictionary moves to `dictv=5c28b3def06314d8 entries=1112`, and docs/COMMANDS.md and the showcase capture are re-recorded.

### Changed — `--for` on an add-a-new-X task points INTO the one holder when the family holds X instead of being X

When most members of the family carry X's plural in their name (`ServerSettingsImpl`, `MergeTreeSettingsImpl` for a setting; `CompilerOptions` for an option), a new X is not one more member: it is a row inside one of them. The block now names that holder (`into=`, `into_p=`): the one a word of X names (`query-level` picks nothing, so the one general holder without other words is taken, `into_by="bare"`), else the one a task word names (`a new option for the compiler` picks `CompilerOptions`, `into_by="word" into_word="compiler"`; a tie picks none). Its existing rows follow in `<rows by= n=>`: the largest X-macro list in its file (`list=`, `list_p=`, the row name read from the argument position with the most distinct identifiers; a tie between two positions claims no rows; text inside a multi-line raw string or comment is skipped), else its fields, else its TypeScript `name?: type` property lines; the touch list is built over those rows. The other holders are not printed (they are other scopes, the wrong place to copy from), and when no single holder is pointed at the block is withheld instead of printing them. On the ClickHouse query-level setting task this resolves to the `COMMON_SETTINGS` list in `src/Core/Settings.cpp` instead of the server and table scope settings classes; on the TypeScript compiler-option task to `CompilerOptions` with `commandLineParser.ts` as the place the options are listed. Touch rows no longer read `docs/`, `doc/` or `unittests/` trees. New gate arms i1-i8 in `test/forexemplarcheck.sh`.

### Added — `--quality-delta`: error-masking's `facet="failure-default"`, a read, parse or spawn failure returned as an empty success

A new error-masking facet. The change added a handler that turns a failed read, parse or spawn into a value a success can also return, in a function whose declared result cannot say it failed. The row carries `facet="failure-default"` and is report-only in every language, so it is `sev="minor"` unless the same symbol also gained a gating construct.

- **TypeScript:** a `catch` whose only statement returns `null`, `undefined`, `[]`, `{}`, `false`, `0` or `''`, or a promise `.catch( () => <empty> )`. The try body (or the promise chain) must call `JSON.parse`, an fs read, `readFile*`, `exec*`/`spawn*`, `fetch`, or a helper the same file defines that calls one of them. The enclosing function must declare an array, tuple, boolean, object, `Record`/`Map`/`Set` return type, or a `Promise` of one. A union with `null`/`undefined`, `unknown`, `any` or a named alias is refused.
- **C++:** `.value_or( <empty> )` on a file read (`readWholeFile`, `readRegularFile`, `readText…`), directly or through a local the read initialized, in a function that does not return an optional, expected, variant or pointer.
- **Refused:** a handler with a comment or a second statement (a log call). Also refused: a C++ local that is tested between the read and the `value_or` (the `if( !bytes ) DISCLOSE(…)` house pattern), a result the next statement tests with `.empty()`, and a comment on the `value_or` line.

This is the shape of CodeRabbit's #614 finding: `readWholeFile( … ).value_or( std::string() )` let an unreadable package.json read as `external="1"`. A replay of that pre-fix window (`--quality-delta=8808c6290..8808c6290^ --quality-kinds=error-masking`) prints one row on `resolveWebSpec`.

`test/failuredefaultcheck.sh` pins the aislop `audit-js-parser.ts` shape, a same-file parse helper, the promise form and the #614 C++ shape, each red before and green after. The negative arms are a `T[] | null` result, a commented `catch { return false; }` around `fs.lstatSync`, a try with no read, a log call, the house pattern, a commented floor line, an optional result, an `.empty()` test and a `has_value()` read; each counts the handlers or `value_or` sites it judged and fails on zero.

Versions: `kQSnapCacheScheme` 29 -> 30 (the Snapshot gained `failureDefaultBySym`; a cached snapshot is recomputed once), and the ingest cache `kCacheVersion` 51 -> 52 (the carried construct hits gain the failure-default tag; each file is re-parsed once). The session legend dictionary moves to `dictv=e465b030656de882 entries=1123`, and docs/COMMANDS.md and the showcase capture are re-recorded.

### Added — a `--for` answer names the ranges to read next, in one line: `<act read="path:l-e,…"/>`

A `--for` answer (CLI, every posture, and MCP `for`) now carries, right after its `<sigs>` (after the key-body group when one follows it), one element listing the line ranges of its top 3 ranked `<sigs>` definition rows: `<act read="src/a.py:10-42,src/b.py:7-19,src/c.py:88-101"/>`. The answer's legend defines it in one clause (a legend-dictionary entry, so `--legend-seen` and an MCP `legend="ref"` session leave a held one out): read them all in ONE turn of parallel ranged Reads, never whole files, except a body the answer already serves, and search only for what no row lists. The line is written only when every one of those rows carries both `l=` and `e=` — a list with a hole in it would send an agent searching for the hole — so an answer whose top rows include a markdown heading (no end line) carries none. It reads the ranked rows only: the fold, the body slot and the page size never change it. It is a block of the answer's row stream that no page counts, so a page ends at the row it ended at without it. Under an explicit `--token-budget` it rides only on an answer the budget fits whole, and only while it still fits with the line, so a budget the answer fits returns the unbudgeted answer byte for byte and a budget that has to cut content spends nothing on it (MCP `budget_tokens`: only while `est_tokens=` stays within it). `--legend=first` carries the same line, its clause in the leading legend. Not on `--json`. `est_tokens=` is re-priced exactly for the added bytes.

Why: agents acting on a `--for` answer were measured reading the ranges it listed one request at a time (1.02-1.27 calls per request), each request re-sending the whole context. Measured on 89 dev questions (page 1): 87 answers carry the line, 3 ranges each, a median 119 B for the element; the orientation rungs (file, function, body) are unchanged on all 89, and no page-1 row moves.

The edit-routing line `ripwire wrap` prints, the subagent brief block, the SubagentStart note and the orient skill now say the same thing: read every listed range in one turn, ranged.

`RIPWIRE_NO_ACTLINE=1` turns it off (the answer is then byte-identical to the answer served before this change); `ripwire --version` says which (`act=on|off`). Gate: `test/actlinecheck.sh`.

### Changed — `--for` scores a symbol's file basename as a ranking field by default

A question often names a file, a module or a package rather than a function ("lib/theme.githelpers: remove dead code", "restorer: reject trees …"), and a function's own text rarely repeats its file's name. The basename-only BM25 field has existed behind `RIPWIRE_BASENAME_W` and shipped at 0. The code lens (`--for`, `--pack-task`, and the MCP `for` and `pack_task` verbs, which share one constant) now scores it at weight 1: the same weight as a symbol's body, under its name (3). `--query`, `--recall` and the evals are unchanged.

Found by mining the development questions (89 questions from 11 open-source repositories) that two peer tools answer and ripwire did not: codebase-memory-mcp indexes each node's file path and qualified name at the same BM25 weight as its name, and graphify starts its traversal from the file node a query word names. The field was first measured at weight 2 on those 89 questions (page 1, the shipped argv): every-file-and-every-function complete 66 → 67, function rung 62 → 64, body rung 24 → 27, no question down at any rung; median answer +15 B. Weight 1 was not re-measured on that set. The full-path field at weight 1 took two questions down on the same set, so it stays off.

The default is 1, not 2. At weight 2 a file-name match lifts every function in a same-named file by the same amount, so a long function in a large file can sink behind its short siblings: in a gate fixture, a function named like its file among 105 short handlers fell from rank 2 to rank 107. At weight 1 it stays at rank 2, and on a held-out set of 213 questions the completeness counts are unchanged (126 / 83 / 4 of 213). `RIPWIRE_BASENAME_W=0` restores the previous ranking and `RIPWIRE_BASENAME_W=2` the heavier one. `test/forbasenamedefaultcheck.sh` pins it for JavaScript and Go, CLI and MCP.

### Added — `--bodies=inline|pointer`: a `--for` answer's first page can name its bodies instead of carrying them (default unchanged)

`--bodies=pointer` (with `--for`) serves every body the answer's first page would carry — a fold body, a class's member slice, a followed delegate, a key body — as the `<skip>` row that names it: `<skip p= n= l= e= bytes= next="--expand=…"/>`, where `l..e` are the source lines the body spans (from its declaration's first line, a decorator or `export` included; `e=` is absent where the extent is unknown, as on a markdown section), `bytes=` its source size and `next=` the call that serves it. The page is cut with the bodies in and rewritten after, so it ends at the row it ended at: no later row moves up into the freed bytes. Its root says `body_form="pointer"` and one legend comment defines the form; a page that holds no body is byte-identical to the inline one. Later pages, a verb-routed answer (its key body is the named symbol's definition, and its carried page was fitted with the bodies in), a `--token-budget` answer, `--expand`, `--pack-task` and MCP `for` keep their bodies.

**The default is `inline`, byte for byte the previous answer** (89 of 89 dev questions and every fixture the gate runs). The flag decides over `RIPWIRE_BODY_POINTERS` (any value = pointer) in both directions; any other value, an empty value, or the flag without `--for` is refused.

Measured on 89 dev questions, page 1: 60 pages change; the file rung and both readings of the edit-function rung are unchanged (0 cells down, 0 up); the delivered-body rung falls from 24 to 1 of 89, which is what the form does (the one left is a routed answer's key body); page 1 is a median 715 B smaller (1,882 B over the 60 pages that change; 2 pages whose only bodies are a few lines grow by 61-122 B). Whether naming the bodies lowers a whole agent session's tokens without costing a correct edit is UNTESTED: a live check is pre-registered, and the default changes only if it says so.

Gate: `test/bodypointercheck.sh`.

### Changed — `--for` puts the callers block first when the question asks who calls the subject

When a `--for` question asks who calls a named symbol ("Which functions call `X` directly?", "Who calls `X`?"), the answer's `<callers by="subject">` block is now the first row block of the answer-first document. Before, it came after `<sigs>`. Only the order changes: the answer has the same bytes and the same rows, and `test/foranswerfirstcheck.sh` pins it as a permutation. A change, blast-radius or transitive question ("What breaks if I change `X`?", "… transitively") keeps the old order, because a one-hop callers block does not answer it first.

Measured once, on a held-out set of 43 questions this mechanism had never seen (a different population from the published compare table):
- Bytes until the whole answer had appeared: median 6,147 → 2,618, p90 14,764 → 12,809.
- Answers complete within the first 12 KB: 32 → 34.
- On the 16 who-calls questions alone: median 6,616 → 1,305.
- Completeness (39 of 43) and the cross-gold count are unchanged, and no answer flipped from complete to incomplete.

That run fired on 2 blast-radius questions it should have left alone ("What breaks if I change `X`? … defines or calls it"). The block's `of=` is qualified while the sentence spells only the leaf, so the change cue was read only on the whole name, and a pronoun "calls it" let the block lead. The change cue is now read on both spellings and vetoes on either (a gate arm that was red before the fix). The fix can only stop the block from leading, never start it. On that set it reverts exactly those 2 questions and leaves the other 15 unchanged, a result read after the set was already used.

### Added — a gate for bounding the carried `--for` page, and the reason it is not yet bounded

A routed answer carries a `--for` page, and that page is where a first call goes over a client's character
limit: on the measured question sets, 8 of 69 first calls on one set cross, against 1 of 234 on the others, and all 8 of them carry a page. When an
answer crosses, the client replaces it with a small envelope whose preview lands inside the legend, so the
agent receives no answer rows at all and the answer's own completeness attributes go with them.

`test/carriedpageboundcheck.sh` registers the bar. The mechanism itself is deliberately not built. A spec
ladder does shrink the page — 14,531 B to 8,292 B, 43% — but it shrinks it SILENTLY: the carried page's root
carries no `page=`/`pages=`/`withheld_bytes=` before or after, so an agent would lose 43% of its rows with
nothing saying rows were withheld and no follow-up call to recover them. Shrinking an answer without saying
so is the one thing this output format does not do, so the code was reverted and only the gate landed.

The gate's disclosure arm is the one that caught it, and only after being strengthened: it first passed on
the silent cut by reading an absent set of paging attributes as "nothing was cut". It now compares against a
base binary and fails on a page that is smaller without disclosing.

### Fixed — a budgeted `--for` answer no longer stops one row short when several rows turn into pointers

Under a soft target (CLI `--token-budget`, MCP `budget_tokens`) the sibling-demote and decl-twin rules turn some rows into short pointers, and the bytes they free buy rows past the cut. That refill walk stopped after three passes. When the rows a refill buys are themselves demotable, each pass frees bytes for the next, so a third pass could free bytes that bought nothing. On this repository's `src/` at `budget_tokens` 1600 and 2000, the answer served one rank fewer than its own budget paid for — on the default ranking and on the previous one (the 2000 rung had passed `test/mcpforparitycheck.sh`'s maximality arm by 25 bytes). The walk now runs until a pass adds no row; the pass limit is only a guard against runaway, above anything the 40-row cap allows. Answers with no budget are unchanged. `test/demoterefillcheck.sh` (c) pins the fixed point on a model answer.

### Changed — the first page of a `--for` answer carries the body of the symbol the question names; a definition body is capped at 120 lines

When a `--for` question names a symbol in backticks, page 1 now carries that symbol's definition body, right after the block that answers the question. A routed answer (`--callers` / `--uses` / `--impact` chosen from the wording) gets it as the root's last child, after the verb's rows and before a carried page; MCP `for` routes through the same code, so it carries the same element. The unrouted answer-first answer gets it directly after its first row block. The block is `<bodies of="key" shown= total= capped=>`, and each `<b t= l= p= n=>` is the `--expand` body element. Each body is whole up to 120 lines and 4,000 B. A longer one is cut at a line end and says so with `truncated="1" lines="1-K/T"` and `next=` the `--expand` of the rest. At most 5 bodies ride, in the question's order with the question's primary symbol first; a further keyed definition makes `capped="1"` with `next=` its `--expand`. Only bodied source definitions count: never a test file, a bodyless declaration or a namesake flood of more than 12.

Page 1 does not count these bytes. It ends at the row it ended at without the body, so no gold row moves to a later page; page 1 is larger by the block instead. This replaces an earlier attempt in this release to move a late `<bodies>` block to the head of the tail, which failed its confirmation because the moved body still missed page 1 and is reverted. Not applied under `--legend=first`, a token budget, `--signatures-only` or non-XML output. `RIPWIRE_NO_KEY_BODY=1` turns the block off. `test/forkeybodycheck.sh` pins the routed and unrouted placement, additivity (removing the block gives the knob-off twin), pages, the byte cut, the body cap, MCP parity and seven negative controls.

**The group carries its own body, whatever else the page serves.** As first built, the group was handed the first 12,000 bytes of the finished answer and dropped any definition whose body was already in there, so once another section's body landed on page 1 the group silently lost its own copy of it — and *which* copy it lost depended on which body that other section happened to serve. The group no longer reads the page: the same `p=` and `l=` appearing both in the key group and in a row section is correct and intended, and the body may also appear in the fold or the body slot of the same answer. Measured on 89 `--for` questions over 89 repositories, one binary pair, same corpus: this moves **three** cells and costs **+4,760 bytes in total**, all of it the restored bodies. On **2 of those 3 cells the group had been emptied completely** — every backticked definition suppressed, so a question that named symbols got no key bodies at all. On the third **`total=` was under-reporting**: the suppression ran before the count, so an answer disclosed `total="3" capped="0"` for a task with five keyed definitions. On a check fixture the same defect produced `<bodies of="key" shown="3" total="3" capped="1">` with no `next=`. Both are fixed, because nothing is removed before the count, and the disclosure triple is now gated: `capped="1"` iff `shown` < `total` iff `next=` is present. Page counts, page-1 tail rows and `deferred=` are unchanged on all 89 cells. What it does NOT mean: the restored body is a duplicate of one the page already carries, so this buys no new information on a page that already had it — all four retrieval rungs measured flat. It buys the contract, and it makes the group independent of the body selector: with the body fold switched off entirely, the key group is now byte-identical (911 B and 2,693 B on the two cells checked), where before it changed.

**A candidate's definition body is capped at 120 lines.** It rides whole up to 120 lines of its indexed span and as its first 120 lines beyond that — `min(span, 120)`, monotone, with no discontinuity. The cut states its cause: `cap_lines=` rides beside the existing `truncated=`/`lines=`/`next=`, because `truncated=` is registered as "cut at the byte budget" and a line cap is a different fact. The three surfaces whose unit is a candidate's definition body take the cap — `<bodies of="key">`, `<bodies pick="name|member">` and `--pack-task`'s. The route, hops and launch groups do not: their unit is a path through several definitions, and they move no byte. The monotone shape was chosen over the cheaper "whole under 120, else a 15-line head". That form saves more — measured, −42.3 % of candidate body lines against −21.7 % — but an answer whose size jumps eightfold on a property the caller cannot see is the wrong trade, and it is worst where several agents each budget alone. The key-body block carries five bodies rather than the two it was first built with: five is the p90 of gold functions per task over an 89-task orientation set whose median is one; a cap of two could satisfy 71.9 % of those tasks and five satisfies 94.4 %. The byte budget, not the count, is what bounds the block. **This is a blow-up guard, not a token saving, and the measurements say so.** On the only stratum where the cap can act — 25 tasks whose largest gold body exceeds 120 lines, 49 gold functions — it fired on 4 of 25 `--pack-task` answers, left edit-covering completions unchanged at 5, and moved median answer bytes by zero. Whole bodies cover every gold body by construction, so a cap can only subtract at that rung; what it buys is a bound on the one place a whole large function could ride unbounded.

### Fixed — the one-side reach walk of `--for` no longer wraps an unsigned hop count, so the ASan build answers two-endpoint `--for` tasks

`addShortestPathNodes` (src/foronesidereach.h) tested `toSink[v] + 1 == toSink[u]`, and a callee the other side's walk never reached carries the hop count `UINT32_MAX`, so the sum wrapped to 0. The plain and Release builds answered correctly (a wrapped 0 never equals a hop count above 0, so no row was kept or demoted wrongly), but the ASan build (`-fsanitize=integer -fno-sanitize-recover=all`) aborted on the overflow: any `--for` task naming two endpoints where a node on the path walk calls something the walk does not reach — the two-sink shape of `test/foronesidecheck.sh` (a2), (c), (g), (h), (t), (x) and `test/foranswerfirstcheck.sh` (R0) on this repository — came back empty under ASan. The test now compares on `u`'s side (`toSink[v] == toSink[u] - 1`, `toSink[u] > 0` by the loop's own condition), which cannot wrap. Output of the plain build is byte-identical.

`test/foronesidecheck.sh` (u) adds a third tree whose root, and whose two-sink common caller, call a function no walk reaches; under the ASan binary it was red before the fix (rc 134) and is green after it.

### Changed — `--for` page 1 promotes definition bodies ahead of the tail more often, by an explicit priority order that never displaces an answer section

`promoteGuarded` (`src/foranswerfirst.h`) decides which sections after `</tail>` move ahead of it onto page 1, inside a finite guard headroom. Three changes, all measured on a fresh 89-task orientation gold set (11 repositories, 11 languages), scored by the baseline's own grader on page 1 of the shipped default call:

- **An explicit priority order.** The walk used to visit the sections once, in emitter order, so a section won a promotion slot by its POSITION rather than its value. The frozen `kPromotable` class of answer (resolved) sections is now the first of two classes and the body-bearing sections are the second (`kPromotableBody`: `fold`, `bodies`): pass 1 promotes answer sections exactly as before, pass 2 gives the body sections only the headroom pass 1 left, and the promoted bodies are emitted behind the promoted answer sections so their byte offsets do not move. Crowding-out is removed by construction rather than by a threshold, and when pass 1 exhausts the headroom nothing moves. Same guard, same stop (`kAnswerPageBytesDefault`), same emitter order within a class; tail rows 1..`kGuardTailRows` never move. Measured: gold-file naming on page 1 unchanged in every cell and every repository; edit-function naming +2 to +4 cells with none falling; edit-function bodies delivered on page 1 rising 9 to 20 cells of 89; page 1 never grows by more than 679 B and the population sheds 481 B on page 1 and 2,145 B overall; byte-identical to the previous behaviour in 56 of 89 cells. Which answer sections lead the tail, and `deferred=`, are identical to the parent in 89 of 89 cells, against 3 cells where widening `kPromotable` itself displaced `<lit>`. At that step `forkeybodycheck` stayed red, because a promoted `<bodies pick="name">` made the key group skip a body already served on the page; no body was lost from any answer, and the key group's own-body fix (see the key-body entry) is the separate change that closed it.
- **A tail that fits page 1 no longer blocks a body from reaching it.** The guard also required `</tail>` itself to end past the page stop — a precondition on the tail's own SIZE rather than a guard — so the `<fold>` behind a tail that FITS page 1 was never promoted, and page 1 ended on file-grain pointer rows while the body the question asked about began after the cut. The tail's page-1 presence is now read as a GUARANTEE of its first `kGuardTailRows` rows and only those — the rows past it carry no rank at all (0 of 88 page-1 tails on the set carries a single `r=` row) — so the size precondition scopes pass 1 alone. Nothing is removed: the tail keeps every row, in order. When `</tail>` ends past the stop the answer is the previous behaviour byte for byte. Measured: gold-file naming unchanged in every cell and every repository (84 of 89), edit-function naming unchanged (62 of 89), edit-function bodies on page 1 18 to 19 cells, median page 1 unchanged at 16,354 B with no cell growing by more than 961 B; byte-identical in 85 of 89 cells, and which answer sections lead the tail, and `deferred=`, identical to the parent for every answer section the previous page 1 delivered. The gate fixture is a subtree because on this repository itself every tail overflows the stop — 0 of 15 task strings qualify.
- **The body class gets its own, lower tail guarantee, and a floor protects everything behind the tail.** The guarantee sets the headroom every promotion is measured against. It is now two constants: `kGuardTailRows` stays at 24 for the answer class, whose pass 1 and eligibility test are unchanged on every input, and the new `kGuardTailRowsBody` is 12 for the body class, so a `<tail>` of 13 to 24 rows is a body candidate. **Lowering the single constant instead was measured and rejected, on the bar rather than taste**: at one constant of 12 the extra headroom reaches pass 1 as well — an answer section is promoted ahead of `<tail>` in four cells where the frozen rule promoted none, and in a fifth it takes the headroom the `<fold>` had won, so a `<fold>` the previous page 1 delivered is deferred; seven of 89 cells fail the crowd-out prohibition that way, five of them on its pre-existing conjuncts. Splitting the guarantee by class keeps pass 1 byte-identical by construction, and 0 of 89 cells fail. The floor (`postPageOneFloors`, generalised from `postResReach`) is per candidate and owes two things: an answer section keeps **every byte** page 1 delivered, and **any** section keeps its page-1 **presence**, which is exactly what `deferred=` reports. Measured: gold-file naming unchanged (84 of 89), edit-function naming unchanged (62 of 89), edit-function **bodies delivered on page 1 rising 18 to 21 cells**, **no cell falling on any rung**, median page 1 unchanged with **1,593 B less page 1 in total across the 89**, and the crowd-out prohibition passing **89 of 89 in its widest reading** — where the previous step failed it in two cells and a single lowered constant fails it in seven. The enrichment section the previous step pushed off page 1 in two cells stays on it. The floor is CONSERVATIVE in one cell: at a single constant of 12 a 22nd body cell is delivered whose promotion the floor refuses although the measured geometry admits it, so the bar is bought for one in-sample cell. The body guarantee's row offset is also read out of the tail as it will be emitted; the previous expression could go negative as a `std::size_t` and wrap, refusing every promotion in silence. Measured, the wrap does not fire anywhere on the set (byte-identical in all 89 cells with and without the correction), so this removes an arithmetic hazard and no observed defect.

Gates: `foranswerfirstcheck` pins that a body is promoted, that the guard still holds, that every answer section is still promoted and delivered and none displaced (red on a build that widens `kPromotable` instead), the tail-fits case (red on the previous binary), the floor over every section the previous page 1 delivered, and both guarantees by value out of the source.

### Added — page 1 of a who-calls `--for` answer ends early when its callers block proves itself complete

When the default page 1 of an unrouted `--for` answer leads with `<callers by="subject">` and that block shows every caller it
counts (`shown=` equals `total=`, nothing capped) and no evidence of a miss is found, the page ends right after the block:
`early="proven"`, `withheld_bytes=` and `deferred=` say what it leaves out, and `next=` is the full page 1. Gate:
`test/forverbroutecheck.sh`. Confirmed once on a fresh held-out set (52 questions): 2 pages ended early, each
still complete, about 16 KB down to about 2 KB; no answer lost an item.

### Changed — a `--for` answer, CLI and MCP, serves its `<sigs>` and `<tail>` rows as text lines, and sequential ranks are not spelled

On the answer-first `--for` answer (the CLI default: paged, `--page-bytes=0`, `--signatures-only`, or under a `--token-budget`), the rows of `<sigs>` and `<tail>` are text lines in ONE CDATA per section instead of one element per row, and a `<sigs>` row whose rank is the previous row's + 1 does not spell `r=` (`<sigs … rseq="1">`). A `<t p=P sym=SYMS/>` row is the line `P SYMS` (other attributes follow, tab-separated); a `<d l=L e=E n=N p=P …>SIG</d>` row is `P:L-E N k=v.. | SIG`; a row the line grammar cannot give back exactly (one that quotes a `<doc>` comment, for instance) stays verbatim XML on its own line, starting with `<`. The answer's legend defines both in two clauses, last before `</ctx>`; both are legend-dictionary entries, so `--legend-seen` leaves a held one out. The answer is still well-formed XML and a newline appears only inside CDATA.

It is lossless and it is the last step: every row, attribute and byte of text is recoverable (`test/rowlines.py` decodes an answer back to its element form byte for byte; `test/rowlinescheck.sh` pins that against the `RIPWIRE_NO_ROWLINES=1` twin, with mutation negative controls), ranking, paging and the budget fit read the rows as elements exactly as before, and each page is encoded after it is cut, so a page holds the rows it held. Measured on 89 development questions against the parent binary: the decoded answer is identical on 89 of 89 (whole answer and page 1), page 1 is a median 1,271 B = 7.6 % smaller, and the three orientation rungs are unchanged (0 cells up, 0 down).

**On by default, with a switch.** `--rows=lines|elements` (with `--for`; default `lines`) chooses the form: `--rows=elements` serves one XML element per row, byte for byte the answer the line form decodes to. The flag decides over `RIPWIRE_NO_ROWLINES=1` in both directions; any other value, an empty value, or the flag without `--for` is refused. `ripwire --version` says which form the binary serves by default in the current environment (`rows=lines`), so an experiment can record it; no answer byte carries it.

**MCP `for`** serves the same form: the same two legend clauses, the same line grammar, the same decoder. A new `rows` argument mirrors `--rows=`: `"lines"` (the default) or `"elements"`, and it decides over `RIPWIRE_NO_ROWLINES=1` in both directions; any other value, or an empty one, is refused. The file page (`limit=` / `offset=`) is unchanged, as the CLI's is. A batch `for` sub-query takes the default form (the variable still turns it off). Decoded, the answer is the `rows:"elements"` answer byte for byte, and `rows:"elements"` is the previous release's MCP `for` answer byte for byte (`test/mcpforrowscheck.sh`). The bundle keeps its `demote:` note inside `<sigs>`, so the note rides the CDATA as a verbatim line (a line starting with `<`). Under the default session legend (`--mcp-legend=session`) a later answer still drops exactly what it drops from the element form — the row clauses and the note once served — and sends no definition twice, so each call of a session decodes to the element session's call byte for byte. The `tools/list` manifest grows 73 B (the one property).

What was measured about reading it, and what was not. One model (`claude-sonnet-5`), headless, single calls: on 5 page-1 answers the line form cost a median 918 fewer INPUT tokens per answer (736 to 1,111; 9 to 14 % of the answer). Asked to list the rows ranked 1-10 with path, line and symbol, the model recovered every row from both forms (line form 100 of 100 rows over 10 answers, element form 90 of 90 over 9). **But it spent about twice the OUTPUT tokens doing so on the line form: a paired median of +700 (from a median 665 to 1,191; range +369 to +2,990, n=9)** — more model effort to read the rows, on a task that asks for exactly that reading. Whether that effort appears in a real agent session, where the model reads an answer to act on it rather than to transcribe it, is UNTESTED, and so is the net session cost. `--rows=elements` (or `RIPWIRE_NO_ROWLINES=1`; MCP `rows:"elements"`) is the way to opt out, and the way to run both forms side by side.

What it does NOT mean. `est_tokens=` and the page size still count the element form, so both are upper bounds on what is served, and page 1 does not yet use the freed bytes for more rows. A consumer that parses rows as elements (`xmllint --xpath`, a script) must decode first (`test/rowlines.py`) or pass `--rows=elements`; the decoder returns an element-form answer unchanged. Not applied to `--legend=first` or `--json`.

### Changed — page 1 of a `--for` answer carries the short form of the sigs rows past rank 10 (with their end line); their signature, doc and lens follow the rows

On the unbudgeted answer-first `--for` answer (the default, `--legend=last`, paged or `--page-bytes=0`), every `<sigs>` `<d>` row with `r` above 10 keeps `l= e= n= p= r=` and is self-closing; its other attributes and its text (the `<doc>` excerpt and the signature) are re-emitted verbatim as `<x r="R" …>text</x>` in one `<sigx>` block after the last row block, behind a `<!-- sigx: … -->` legend, and `est_tokens=` is re-priced over the added bytes. Nothing is dropped: putting every `<x>` back on its `<d r=R>` rebuilds the answer byte for byte. The median `<sigs>` is about 7.3 KB and ranks 11-40 about half of it, so a 6 KB / 12 KB page reaches ~19 more tail rows. `RIPWIRE_NO_SIGX=1` turns it off.

Measured on four development question sets (154 / 49 / 41 / 34 cells, simulated and checked against the binary; the change was pre-specified and built as specified): complete within 6 KB 50→59 / 22→25 / 13→15 / 18→22 and within 12 KB 73→75 / 32→33 / 26→29 / 25→26; on the 41-cell set −328 tok/question delivered at 12 KB pages. What it does NOT mean: it is not flip-free by construction — a gold item carried only by a moved attribute or signature leaves its page (one design cell, `mem=` on an r=25 row, leaves 12 KB) — and cross-gold on a 6 KB / 12 KB prefix rises because rows arrive earlier (accepted as a project decision). An agent reading only page 1 loses the signature, doc and lens of ranks 11-40 there.

**The short row keeps its end line.** As first built, the short form kept `l= n= p= r=` and sent `e=` to the `<sigx>` block, so the row named where a definition starts and not where it ends. It now keeps `e=`: in the line form the row reads `P:L-E N`, in the element form (`RIPWIRE_NO_ROWLINES=1`) `<d l= e= n= p= r=/>`, and a reader can range-read the definition from page 1 without a second call. The line grammar and `test/rowlines.py` already spelled `-E`, and a row whose extent is not known (a markdown heading, a config key, an `extent_suspect` row) still carries no `e=`, never a 0. The whole answer's bytes do not move: the attribute changes element, not count, and `<x>` no longer repeats it. Measured on 89 development questions against the parent binary, page 1, both answers decoded with `test/rowlines.py`: of the 123 gold functions page 1 names, those with a usable `l=`..`e=` range go from 80 to 96 (0 lost), and the cells where every gold function has a range from 45 to 51. The four orientation rungs are unchanged (FILE 84, FUNC 62 / 65, BODY 24; 0 cells up, 0 down, no cell with fewer hits). The cost is page-1 room: the `e=` bytes are paid on page 1 (1,355 more rows carry one), and the page cut answers by moving 117 unranked `<tail>` pointer rows, at most 3 per answer in 73 of the 89, to page 2. What it does NOT mean: the range is the parser's body-inclusive span, so a decorator or return type can sit above `l=`; `<b>`, `<h>`, `<c>`, `<skip>` and `<ls>` rows still print `l=` without `e=` (they are not sigs rows; two `<b>`, one `<h>` and one `<ls>` gold function stay start-only on this set); and whether an agent then reads fewer lines is untested.

Not applied under `--legend=first`, a token budget, `--signatures-only` (whose rows already carry `e=`), MCP, or non-XML output. Gates: `test/forsigxcheck.sh` pins the rebuild (with a negative control), the short rows, placement, re-pricing and the opt-outs; `test/forendlinecheck.sh` pins the end line in both row forms against the `RIPWIRE_NO_SIGX=1` twin, with known first and last lines on a fixture and two mutation negative controls; `foranswerfirstcheck` and `forpagescheck` pin the permutation with SIGX off.

### Changed — past its 24th row, a `--for` tail lists the files in a top-5 sigs row's directory first

In the answer-first `--for` answer, `<tail>` rows 1-24 keep their place; rows 25 onward are stably partitioned so that a row whose file sits in the directory of a `<sigs>` row ranked `r` 1-5 comes first, each part in its own order. Order only: the same rows, the same bytes, the same document size (the answer-first permutation contract holds), so no row is lost and the page-1 promotion guard (which reads tail row 24) is untouched. Rows 1-24 are fixed because broader re-ranks that also moved them, measured in an earlier analysis, pushed in-page gold rows out of the first 12 KB.

This is the same-directory signal that analysis found post hoc (the one signal with zero flips on both design halves), pre-registered fresh before it was built. Measured on four development question sets (design 154 / held-out 49 / 41 / 34 cells, simulated and checked against the binary): gold groups first seen within 12 KB +4 / ±0 / 0 / +1, complete-within-12 KB cells 73→74 on the design set and 25→26 on the 34-cell set, zero cells lost from 6 KB or 12 KB. A weak signal (in that analysis, ~2.3x the base rate of a needed tail row); the gain is small and measured as such. The answer-first legend states the order it serves: where the tail is reordered, the clause `t order past row 24: files in the directory of a sigs row with r<=5 first, then the rest, each part in the order above` rides right after the tail clauses (only on a tail that walks past file page 0), and the pass reorders only where that clause is in the document legend, so the two cannot disagree. `--legend=first`, `--json` and the MCP `for` tails keep rank order and their unchanged wording, so the surfaces still differ in order (same rows; a project decision). `RIPWIRE_NO_TAIL_SAMEDIR=1` turns it off; `test/foranswerfirstcheck.sh` pins the fire, rows 1-24 in place, the partition, and the permutation with a negative control.

### Added — a `--for` question that names its symbol is answered by the verb it asks for, routed

A bare `--for` whose text names a symbol in backticks and asks who calls it, where it is used, what breaks if it changes or
its callers N hops up is answered by `--callers`, `--uses` or `--impact`. The answer says so first:
`<route from="for" kind= verb= complete="not-proven" next=>`, where `next=` (`--no-verb-route`) is the ranked `--for` answer.
Files that name the symbol only as text (a macro alias, a string, a shell script, a call the resolver declined) follow as
`<text_only>` rows. When the evidence says the verb is likely to miss something a text list cannot show (a macro caller,
a callback slot, twin definitions, a value hop, a cut list), the route says `warn="1" why=` and the first `--for` page
rides inside the answer. An absent `warn=` means no evidence was found, never that the answer is complete. Flags that shape
the `--for` answer (`--page-bytes`, a budget, `--json`, several roots) keep it unrouted. MCP `for` routes by the same rule and
carries the same rows (its warned answer carries MCP's own `for` answer); its `no_verb_route` argument is the opt-out.
It was measured on held-out gold questions before it shipped. Commit `1ede0078b`; gates `test/forverbroutecheck.sh` and
`test/mcpforroutecheck.sh`.

**Questions that are never routed.** A question that is not routed gets the ranked `--for` answer, byte for byte, in the CLI,
MCP `for` and the batch sub-verb:

- **What X calls** ("what does `X` call", "which helpers does `X` call", "callees of `X`", "what `X` calls"). Its "call"
  word used to route it to `--callers`, which answers the opposite question. Who-calls phrasing ("who calls `X`", "what calls
  `X`", "callers of `X`", "`X` is called by") still routes to `--callers`.
- **A call path or call chain** ("what is the call chain from `A` to `B`", "which call path from `main` triggers `X`",
  "the path from `A` to `B`"). These went to `--callers` or `--impact` on their "call" or "trace" word. A path is neither
  1-hop callers nor a blast radius.
- **A double-quoted literal** outside every backtick span ("running `X` prints "usage: …"; where is that message built?").
  These were routed by the symbol beside the literal, but the answer needs to find where the literal is built first. Straight
  and curly quotes both count. Quotes inside a backtick span are code and do not count, and neither does an apostrophe.

Every other question routes exactly as before. A bare "blast radius" question still routes to `--uses`: a rule that sends it
to `--impact` is built but HELD (off) until `--impact` covers every `--uses` row and a fresh confirmation set measures it.
Measured on the spent development sets, the path and literal vetoes match no question the old rule routed; on a held-out set
of 86 questions they change 3 call-chain routes: all 3 stay complete, and no other answer changes.

**A windowed routed answer continues itself.** When the routed `--uses` or `--impact` windows its rows (`has_more="1"`
`next_offset=K`), the answer's root `next=` used to name another lens (`--safe-delete=…`), or nothing at all, and
`--for=Q --offset=K` answered with a `--for` file page instead of the verb's next window. Now the routed root's `next=` is
`--for=Q --offset=K`. That call routes the same question to the verb's window at K: it carries the `<route>` element (its
`verb=` spells the offset) and the verb's rows at `--offset=K`, byte for byte. It carries no fold, no key body and no
carried page, because those belong to the first window. MCP `for` with `offset=` (and no `limit=`) answers the same way.
An unwindowed routed answer keeps the verb's own `next=`; an unrouted question with `--offset` is the `--for` file page, as
before; `--no-verb-route --offset` is never routed. Measured on the spent development sets (120 routed answers): the only
bytes that move are the root `next=` of the windowed answers.

### Fixed — Go method expressions are references, and a selector call never binds a type

`fn := (*Replica).executeReadOnlyBatch` made no reference at all: `--callers=Replica.executeReadOnlyBatch` showed no production caller. A method expression `(*T).m` in a value position is now a value row of T's method m (the same join as a receiver's method value). And `unmarkedPriorVal.Type()` (a method of an outside type) printed the in-tree `type Type` as a `via="name"` row: a name-only Go selector call now drops type candidates, as it already dropped free functions, so a call nothing else answers counts `external=`. A conversion through a package alias (`types.Name( s )`) keeps its edge. Measured on terraform: 406 fewer edges, 3,713 more `external=` (`t.Fatal` beside three in-tree `Fatal` interfaces, `.Type()` on cty values).

What it does not change: a plain `T.m` method expression (its operand is spelled like a package or a variable) and `( *p ).m` on a local stay unread.

### Changed — `--grep` and `--clones` page under the output ceiling, and a many-definition `--expand` chain reaches every definition once

A default `--grep` page used to print up to 100 in-index rows plus up to 100 unindexed rows whatever their length: 29,224 characters on the bat repository, one of the 11 open-source repositories behind the 89 development questions, over the 24,000-character output ceiling (an agent harness shows only a 2,000-character preview past ~30,000). A default `--clones` page printed its 80-row head the same way (25,649 characters on gson), and `--clones --offset=K` printed every group from K on. Both now keep a default page under the ceiling by cutting their own unit, matches or clone groups, in the verb's own order. The cut is disclosed with `shown=`/`capped=`/`has_more=`/`next_offset=` as before, and `next=` is the next page as one pasteable call (`--clones` now carries `next=` too). Following `next=` to the end yields every row once. On `--grep` that now includes the unindexed rows past the end of the in-index list, which no page used to reach. A page that fits is unchanged, an explicit `--limit=N` is unchanged, and `--page-bytes=0` is the whole answer, with the one stderr size line when it is over the ceiling.

`--expand=NAME` with many definitions names the ones that did not fit in `unserved_next=`. Following that chain reached only 19 of gson's 33 `toString` definitions and served two of them twice, for two reasons. A `FILE:LINE:NAME` selector ignored its LINE and matched every same-named definition in the file, and a 16-selector cap left the rest unnamed. Now a `FILE:LINE:NAME` token on `--expand`/`--outline` serves the one definition that starts on LINE. Past 16 unserved definitions, the page serves a prefix of the request and `unserved_next=` is the same call with `--offset=K` (the first K skipped), so the chain serves every definition exactly once. Gate: `test/outputceilingcheck.sh` (G, K, X arms).

### Fixed — `--grep` names the files whose every hit its tier held back, and holds nothing back in a file whose parse degraded

`--grep`'s default tier serves code and holds comment and string hits back, counted in `suppressed_comment=` / `suppressed_string=`.

- **In a file whose indexed parse holds ERROR nodes** (its row carries `parse_degraded="1"`) that tier came from the same grammar that failed there: fzf's `shell/completion.zsh`, parsed with the bash grammar, had its definition and both calls of `__fzf_list_hosts` held back as "string", and the answer named no held-back file. A hit in such a file is now unclassified: it is served, counted in `tier_unclassified=`, and never suppressed. A string or comment hit in a clean file is held back exactly as before. The `tier_unclassified=` reading says so in both legends.
- **A file whose every hit was held back had no row**, so the answer never named it: the count said hits were held back, not where. The root now adds `held_files=` (how many such files), `held=` (the first five paths, in the answer's file order) and `held_next=` (the same search with `--grep-in=any`, which serves every tier); the MCP `grep` twin carries `held_files` / `held` / `held_next`. Present only when some file was wholly held back; every other answer is byte-identical.

Gate: `test/grepdegradedcheck.sh`.

### Fixed — a C++ map no longer re-walks the same base classes on every call: llvm-project's cold map left a 10+ minute single-core loop

The C-family base walk that decides which base class a call reaches (the guard that tells same-named base classes apart) expanded the receiver type's base levels again on every call. One level's expansion pairs every class of the deriving name with every class of the base name, so where class names repeat across files — `Impl`, `Base`, `Visitor`, hundreds of each in llvm-project — the cost was calls × (classes of a name)², and a cold flagless map of llvm-project sat in that loop on one core for more than ten minutes. The levels depend only on the root type's name, so each root's levels are now kept as they are first expanded and replayed by every later call; no level is expanded twice. The probe after each level had the same shape: for a member defined out of line in a file with no class of its name, it re-read every class of that name on every call. That answer — which classes of a name a file most plausibly means — depends only on the file and the name; it is now kept per (file, name) and shared by every walk that asks it (the ancestor and subclass walks of class identity asked it too, again per method). Class identity's step for a virtual call on a type that declares the method but defines it nowhere (the definitions in its real subclasses) likewise re-read, for every method, whether each subclass's base clause means the receiver class and the base levels a subclass inherits its body through; both are now kept per class. Telling same-named base classes apart paired every class of the deriving name with every class of the base name; it now walks whichever side is shorter — a class's own base edges, or the classes of the name. The reading of one base name by one deriving name is now computed once and shared by every walk that meets it, and the inherited-body walk's visited test is a set rather than a scan of a list that held every namesake reached. The argument-type overload pick read each candidate's enclosing namespaces by lexing its whole file again; a file is now lexed once and answers every position in it. The ladder's proof that a candidate's class is the caller's class or one of its bases walked the caller's bases again for every candidate of every call, deduplicating against its whole frontier; each class's first 64 bases are now kept. Class identity's walk up a receiver class's real ancestors for a method's definitions ran again for every call; its answer is now kept per (class, method). And the base closure the ladder's proof and the bare-call test read for a caller's class was kept for one class at a time, so every switch between caller classes re-expanded it; each class's closure is now kept. Every answer is unchanged byte for byte. `RIPWIRE_STATS` prints the counts as `[mem] guarded_walk`, `[mem] plausible`, `[mem] base_edges`, `[mem] subclass_walk`, `[mem] arg_type_chain`, `[mem] recv_cone` and `[mem] inherited`, and `test/guardedwalkcheck.sh` holds the walk to one expansion per root name and the probe to one read per out-of-line definition.

### Changed — `--path`, `--connect` and `--callers` bind a refused spelling's one source definition

A direct `--path` endpoint, `--connect` terminal or `--callers` selector that the resolver refused because several definitions fit it (`ApplicationRef.tick`: the source method plus a bodyless `.d.ts` declaration and a copy under `test/`) now answers on the ONE definition left once the definitions in a test or fixture path and the bodyless ones are dropped. This is the rule the `--for` graph block has used since GV-ASSEMBLY (#602), and the rule itself is unchanged. The verb runs with that definition's own spelling (`file:name`, else `@file:line`), so the answer is the explicit-spelling call's answer, and `narrowed="<as typed>"` on the root plus one legend clause say what was narrowed. The `--callers` JSON dialect carries `"narrowed"`. When two or more definitions are left, or none, the refusal is byte-for-byte what it was. `test/gvassemblycheck.sh` (d1)-(d4).

The three compact readings move the session legend dictionary to `dictv=f7d122c82741a996 entries=1107` (docs/COMMANDS.md and the showcase capture are re-recorded).

### Fixed — a compact legend documented attributes the answer did not carry, and `--legend-have=` refused those answers

A compact legend is meant to spell an attribute's reading if and only if the answer carries the attribute. The test behind that, `headHasAttr`, was a substring search over the answer's head — the root's open tag through its first child's — and that span keeps the comments between the two tags. When the question is asked those comments are the full-dialect legend prose, which defines an attribute by spelling it (`scrubbed="1" = a ]]> was split`), so the definition was read as the attribute.

Measured on this repository, old binary against new on the same tree: every bundle-mode `--expand` documented `scrubbed=` and `redacted=` with neither in the answer — **166 B on six of seven sampled answers, 98 B on the seventh** (whose body really is scrubbed, so only `redacted=` was false). On a three-file fixture `--pack-task` documented `run_unknown=` (61 B, 8,021 → 7,960) beside a `<tests>` block whose every row had a runner.

The larger cost was downstream. `--legend-have=DICTV` rebuilds the legend from the *compacted* answer, whose head comment no longer spells those attributes, so the two disagreed and the handshake kept the legend inline: **7 of 7 `--expand` answers refused, 0 B saved; now 7 of 7 take the ref posture, 26,531 → 21,139 B (−20.3 %)**.

The head span is unchanged. `--lego`, `--skipped` and `--notes` put their facts on the first child, inside that span, and narrowing it to the root tag — the obvious fix — silences their clauses (an adversary build confirms it: six control arms red). The attribute test now walks tags and skips comments and CDATA, reusing `payloadHasAnyAttr` rather than adding a second walker. 30 answers sampled from the other verbs are byte-identical, and the legend dictionary version does not move.

**One answer changes shape, correctly.** `--expand` serves whichever of its two documents is smaller as delivered, and the bundle was being priced 166 B too high. Inside that band the choice now goes the other way: on `test/fixture`, `--expand=distance` served the whole file (1,485 B) because the bundle measured 1,561 B; the bundle is really 1,395 B and is now served. `--legend=full` is unaffected and still serves the file, so this is a posture split of the kind `next="--expand=… --legend=full"` already discloses. Two pins followed and both were moved deliberately: `test/compactlegendcheck.sh`'s rows-identical probe is now `--expand=perimeter` (same two definitions, the same 508 B whole-file legend, whole-file in both postures), and `test/printf_parity.manifest` re-pins the `expand` label alone, 41 others unchanged.

New gate `test/headleakcheck.sh`: non-vacuity arms that read the same captures as the arms they protect and assert the trap is armed on them; the absent-term arms; present-term arms, so that deleting a term row is red too; the lego/skipped/notes control; the handshake; determinism. Evidenced red three ways — the pre-fix binary (7 arms), a build with the `scrubbed` row deleted (1 arm), and a build with the span narrowed (6 arms).

### Fixed — a C `static` in a header binds from the files that include it, without resolving every import in the tree

A `static` function or variable defined in a header is visible to every file that reaches the header over resolved `#include` edges, directly or transitively, and value references from those files now bind to it; a `static` in a `.c`/`.cc`/`.cpp` file stays private to that file, and an unresolved `#include` proves nothing (no bind, and the count stays a floor). Confirmed together with the untied-declaration fix on a fresh blind gold set (no cell lost a group, within the byte bar); on its own it changed no confirmation answer, and it changes two development `--for` cells through the shared index. Commit `4af3a959b`; `test/verbfixcheck.sh`. (A third fix from the same round, macro see-through on the one-hop verbs, failed the byte bar as built and lands limited to the first macro hop; see the macro see-through entry.)

The include graph this question reads is built from the C-family files' `#include` directives alone, instead of resolving every Python import, TypeScript specifier, Rust `use` and Ruby constant in the tree first. On a mixed C and Python tree (cpython, 4,663 files) a warm `--for` runs 5.9 % fewer instructions; answers are unchanged, and a tree where a C file includes a file of another language falls back to the whole graph. `RIPWIRE_STATS=1` prints the work as one `[stats] header_static_adj` line (gate: `test/headerstaticadjcheck.sh`).

### Fixed — a cut git history walk no longer breaks the `--for` file page, and its `history_unread="1"` is defined where it rides

When the git history walk behind `churn=` and `amp=` is cut by its budget (20 s or 200 K commits) or fails, the answer
carries `history_unread="1"` on its root and a comment that explains it. Three things were wrong with that path, and all
three showed only when the walk was actually cut, which on this repository happens only on a slow runner (a CI flake on
#688):

- `--for … --limit=N` (the file page) printed an ill-formed document: its own `coverage=`, `shown=`, `total=` and `next=`
  attributes and its legend landed inside the explaining comment, so no reader or XML parser saw them. The page now keeps
  its attributes on its `<files>` root and puts the comment after the tag.
- The comment had no space between the comment opener and `history_unread=1:`. It now has one, the spelling every other
  definition comment uses, so the legend checks read it as the attribute's definition.
- On the ranked map (`--metrics`, `--grep --metrics`), the comment now leads the legend in front of the `<r>` root, rather
  than following the root tag where the full-legend first screen does not look.

A run whose walk is read in full is byte-identical. The MCP `for` tool runs no history walk (it already declares
`churn` and `amp` absent with `lens=`), so it still carries no `history_unread`. `RIPWIRE_GIT_WALK_COMMITS=1` forces the
cut in `test/legendcoveragecheck.sh` (arm HU) and `test/mcpattrparitycheck.sh`, so both check this path on every run.

### Changed — test-row run= commands are derived with less repeated work

Verbs that print test rows with a `run=` command (`--affected`, `--situ`, the test gate rows) looked up each row's runner by testing every TS/JS test file in the tree as a possible shell or Python driver, and walked the row's `package.json` chain up to the crawl root once per test file. The driver candidates are now listed once per index, and each directory's `package.json` chain and the framework it names are read once and reused by every test file in that directory. On vscode, warm `--affected=src/vs/base/common/strings.ts`, the runner lookup fell from about 6 % to about 2 % of main-thread samples. The commands are unchanged: the output was byte-identical to the previous build on every run compared, and the test-gate fixtures pass unchanged.

### Fixed — `--exemplar` hedges an off-task pick, `--help-task` abstains with a next step, `--pattern` counts member calls

Three answers that were confident-wrong or ended with nothing to do next. Found by a pre-release answer audit and confirmed by a second audit (2026-11-11).

- `--exemplar=TASK`: when the task matched the corpus but the role pick shares no word with the task or the names it matched (hono `'a middleware'` → `useState`), the pick now carries `low_confidence="1" off_task="1"`, and the low_confidence reading no longer calls such a pick a fallback. The pick itself is unchanged. `test/exemplarconfcheck.sh` arm 5, with a positive arm where a real `middleware/` family is picked and not hedged.
- `--help-task`: an abstain carries `next="--for='<task>'"`, or `reason="system-event"` for a harness report. A recommend whose command stands on a plain word that the task names only after `of` reads `confidence="low"` (nushell `'… a pipeline of commands'` → `--expand='commands'` used to read high). `test/taskroutecheck.sh` HT-a/HT-b, with the corpus recommend count pinned so a route lost fails.
- `--pattern='f($X)'`: member and attribute calls (`obj.f(x)`, `self.f(x)`) whose called name is the pattern's are counted as `unmatched_member=N` with `next="--pattern='$O.f($X)'"`, through a per-grammar call-shape table (C, C++, Go, Rust, JS/TS, Python, C#). They are still not hits. textual `post_message($X)` read `hits="0"` with nothing else, and now adds `unmatched_member="173"`, which the next= pattern hits exactly. Pointer calls (`p->f(x)`) are counted as `unmatched_member_arrow=K`, and next= spells `$O->f($X)` when every counted call is one. A member call the ellipsis bound skipped marks the count a floor (`unmatched_member_capped="1"`). The receiver metavariable is always one the pattern does not already use. `test/patterncheck.sh` 7b/7c (7c from CodeRabbit review on #624).

The new compact readings move the session legend dictionary to `dictv=5be2bb3dabaae9de entries=1062` (docs/COMMANDS.md and the showcase capture are re-recorded).

### Added — a `--for` hop row says when its function is used as a value, and when that cannot be read

A function that is only ever stored or passed (a handler table, a registered callback) has no caller edge, so its `<h>` hop row read exactly like one whose callers are all resolved. `--callers` already prints `value_refs=N` for it; the hop row did not. Call edges are matched by name, so a callback or a call through a slot can be missing, and the reader could not tell "no caller exists" from "the caller is a slot the graph does not follow".

- `<h … value_refs="N">`: the row's function is used as a value N times (what `--callers` prints as `value_refs=`). A call through that slot is not an edge.
- No attribute: none found, for a language whose value uses are read. Never "none exists".
- `<hops … value_refs_unread_for_lang="rb,sh">`: a printed row is in a language that reads no value use at all, so its missing `value_refs=` is unknown, not zero (the precedent is `--lego`'s `implementors_unread_for_lang=`). Only languages of printed function rows are named.
- Two present-only legend comments define the attributes beside the section. `total=` `shown=` `capped=` `noedge=`, row order and every callee row are unchanged.

Measured on a fresh draw of 216 `--for` cells (short wording, not the cells that prompted it): 0 structural differences against the previous binary, 51 answers (23.6 %) carry an attribute, +58.9 B per answer on average (0.20 % of bytes), +249.5 B per answer that fires. 30 of 30 checked counts equal `--callers`. Gate: `test/hopvaluerefscheck.sh`.

What it does not do: it recovers no item and moves no rank. The retrieval-gap partition's 9 resolution items rank 220 to 4,534 and are not hop rows; only 3 of them have a value use at all. Rows whose name has several definitions count one definition, where `--callers` counts all of them.

### Changed — `--impact` puts production callers and evidence-bearing importers in its first window

Two orders decided what `--impact`'s first 40-row window held, and both let a row that answers nothing push out one that
does. Symbol rows ran depth first, then PageRank: a test helper that many tests call out-ranked a production caller at the
same depth, so django `--impact=salted_hmac` listed depth-3 tests ahead of the two depth-3 production files a blast-radius
question needs, which sat past row 40. Within a depth, rows without `test="1"` now come first, then PageRank, as before. The
import tier (`<f>` rows) ranked an importer by path tier, then how many files import it. An importer the same answer also
has evidence for now goes first within its tier. Evidence means the file holds a reached symbol, a declined call that
`declined_calls=` counts, or a value binding of SYM. Example: envoy `--impact=chargeResponseStat` listed 40 of 141
importers, and `router.cc` and `ratelimit.cc` were past the cut.

Both changes only reorder rows. No row is dropped or added. Every count stays the same, including `reaches=`, `by_depth=`,
`importers=`, `shown_importers=`, `importers_capped=` and `importers_next=`. The `has_more=` / `next_offset=` windows are still
slices of one order. CLI XML, `--json`, `--format=columnar` and the MCP `impact` twin all print the same order. The full
legend and `--help` state the new order. `test/impactfirstwindowcheck.sh` is the gate.

Measured on four spent development question sets, one of them held out, with the shared grader:
- **Routed** `--for` → `--impact`, 20 cells: complete on window 1 stays 18 of 20, with 0 flips either way.
- **`--impact` asked directly** on the 62 blast-radius and change-risk cells: complete on window 1 stays 50 of 62, with 0 flips.
- **Gold groups that only the symbol and importer rows satisfy:** 60 → 62 routed and 181 → 189 direct, and no cell lost any.
- **Delivered bytes** are unchanged to within 0.2%.

What it does NOT mean: it does not raise the dev completion rate. Every dev answer still incomplete misses files that the
reach set does not hold at all: shell functions, macro expansions, header includers behind an umbrella header, and a few
unindexed definitions. No ordering can surface those.

### Changed — an `--impact` importer row prints `<f p="…"/>`, with `lazy="1"` only when it is 1

`<f via="import" p="…" lazy="0|1"/>` carried two literals: `via="import"` is the only value that emitter writes, and `lazy="0"` is the default. The row is now `<f p="…"/>`, or `<f p="…" lazy="1"/>`. The old row is rebuilt from the new one without context: insert ` via="import"` before ` p=`, and give a row with no `lazy=` ` lazy="0"`. `--json` is unchanged.

Measured on a pre-registered draw of 160 `--impact` answers over 20 repositories: the whole answer is 3.97 % shorter (1,156,210 to 1,110,344 B), the `<impact>` element's own bytes 4.27 % (818,106 to 783,206 B), and 160 of 160 answers rebuild byte for byte. Correction: the commit message of `72419d313` says the `<impact>` element is 3.02 % shorter; 3.02 % is the element's saving divided by whole-answer bytes. The element is 4.27 % shorter and the whole answer 3.97 %. `--impact` is about 2.8 % of the graded population's bytes, so this is a verb-level saving (about 0.14 % of the population), not a headline one. The impact legend pack now reads `p` on `f` instead of `lazy` on `f`; that `bench/legendtier/census.tsv` row was amended by derivation, marked in place, and is owed a real re-take. Commit `72419d313`; new gate `test/importrowshortcheck.sh`.

### Changed — a `--for` task that spells an import gets the chain from the spelling to the definition

A `--for` task that names an import (`inject imported from @angular/core`, `Injectable type imported from @nestjs/common/internal`, `verify from hono/jwt`, `from a.b import X`, a dotted `concurrent.futures.ThreadPoolExecutor`) now gets a `<spec>` row inside `<reexports>` and the statements from the spelled import to the definition, in import order. The specifier resolves through the in-tree `package.json` whose `name` matches (its `exports` subpath, else `module`/`main`/`index`; a `./dist/...` target is mapped back to its source); for Python it resolves to the module file, and `from .m import X`, PEP 810 `lazy from`, parenthesised lists and renames are followed. `export { X as N } from`, `export * from` (hedged, `glob="1"`) and two value shapes (`export const verify = Jwt.verify`, a member of an exported object literal, `val=`) hand the name on. Two manifests that declare one name are disclosed (`cands=`); a spelling no manifest declares and no part of which names the tree is `external="1"` and prints no in-tree row. The name is now the word before the cue words (`imported`, `type`, `decorator`), not the cue word itself.

The definition-side walk now reads a relative extensionless specifier the way tsc does, the file before the directory index (`./di` beside `di.ts` and `di/`), so it no longer stops there without saying so. `RIPWIRE_NO_IMPORT_SPEC=1` turns the new block off; `test/importspellingcheck.sh` pins it.

### Changed — a cold index of a JavaScript/TypeScript repo does about a quarter less work

The two per-file JS/TS side captures (import shadows and FC3 rebinds) walked every syntax tree with a fresh cursor and child list per node, climbed to each declaration's scope with `ts_node_parent` (which re-descends from the root on every step), and tested node kinds by string compare. They now walk with one cursor that carries each node's ancestor chain, so a scope climb reads the chain, and test kinds by a per-grammar symbol table built from the same names. On vscode a cold `--deps` retires 24 % fewer instructions (median of three interleaved base/head pairs); hono and fastify cold runs drop 19-22 %. Answers do not change: `--deps`, `--for` and the plain map were byte-identical base vs head, cold and warm, on vscode, hono and fastify, and the cache differs only in its write timestamp and checksum, as two base runs do. Warm runs never ran these walks and are unchanged. `test/falseedgecheck.sh` arm S gains two shapes (a `var` declared in a nested block, and `for ( var x in … )` in one) that a wrong parent turns red.

### Fixed — `langidentitycheck`'s ratchet counted a comment as a language predicate, and now discloses its count as a floor

The ratchet in `test/langidentity/ratchet.tsv` caps the `== Lang::X` / `!= Lang::X` predicate lines `src/` may hold outside its per-language files. Its counter is LINE-BASED and excluded `case Lang::` labels but not comments, so `src/ingest_crawl.h:124` — the `//` sentence explaining why Metal rides on `Lang::Cpp` — counted as the 326th predicate against a ceiling of 325.

- The line is not new and belongs to no side: it is identical on `main` and on the integration branch. It became VISIBLE when the grep verb began serving, with their floor disclosed, the hits it used to withhold in a `parse_degraded` file (`held_files=`/`tier_unclassified=`). In such a file no span tier is known, so `--grep-in=code` cannot exclude a comment there — measured, that flag's listing is byte-identical to the default's and both count 326, so passing it on the ratchet command would have been a no-op.
- So the fix is in the instrument, not the bar: `count_predicates` now skips a hit whose line begins `//` or `/*`, alongside the `case Lang::` rejection it already had. The ceiling row and the six `perlang` rows are byte-identical; the governed quantity is 325 and the ratchet passes at it. `*` is deliberately NOT a comment opener for this test — `src/` holds real code lines that start with one and compare (`*okOut = rc == 0;`), so rejecting a leading `*` would one day drop a genuine `*lang == Lang::Cpp`.
- Proved against generated listings rather than edited source: the same saved `--regex` listing counts 326 with the previous counter and 325 with this one, and an 11-arm fixture shows every real-code shape — `==`, `!=`, a trailing `//` comment on a code line, a tab-indented predicate, a `*`-dereference predicate — still counted, while the three comment shapes are not, and the per-language exclusion is untouched.

The same counter has a second, older defect, now DISCLOSED rather than fixed: its hit regex requires the `in=` attribute, which the tool omits for a hit with no enclosing symbol, so such a row is dropped silently. Measured on this tree, 12 real `l == Lang::X` lines in `src/langfacts.h:544-555` are counted by nobody — the figure printed is 325 where the served rows hold 337. The count is therefore a FLOOR and the gate's own line, the ratchet file's header and the gate script's contract all say so; the ceiling was recorded by the same instrument, so its quantity is wrong in the SAFE direction (too low, hence stricter than it reads). The ceiling is deliberately NOT re-based on a fixed count, because making `in=` optional lifts the figure to 337 at once and that file's rule is "may fall and may never rise".

### Changed — lexical scans read every file, and a reached limit is printed to stderr

`--whereis`, `--stray-content` and `--grep` no longer skip large files. `--whereis` and `--stray-content` used to drop any blob
over 2 MiB unread. `--grep` used to leave the crawl's oversize files (`corpus_oversize=`) unsearched while it still claimed
`complete="1"`. These scans now read a file of any size in line-aligned 2 MiB pieces, so memory stays bounded. `--grep` claims
`complete="1"` only when every such file was read whole.

The branch sweeps past 512 local branches got cheaper. Merge bases now come from one history walk, and the diffs come from
batched `git diff-tree --stdin` runs instead of one git process per branch. On a one-file repository with 602 branches,
`--stray-content` went from 86 s to 2 s, `--abi` from 125 s to 2 s, and `--plan` from 10-15 min to 8 s; at 4,096 branches of that
repository each verb finishes in about 11 s or less. `--whereis` now sizes its branch window by work, about 2 million tree entries in total
(at least 16 refs), so a 602-branch clone of a tree of about 20,000 entries reads 101 refs. `--plan` scouts at most 8,192 indexed
files across its arms. `--detail=1` lifts every window.

Whenever a window or budget cuts an answer, ripwire prints one line to stderr. The line names what was cut, the limit and the
flag that raises it. At most five such lines print per run, then a single line says that further warnings are collapsed. The
answer itself still carries `refs_omitted=` for agents and never contains the warning text.

`--for` "unused functions in A/ and B/" now prints `<unused_cut>` when the table shows fewer files than the named directories
hold together.

The changed compact readings (`corpus_oversize`, `unindexed_files_skipped`, `refs_omitted`) move the session legend dictionary to `dictv=e465b030656de882 entries=1123` (docs/COMMANDS.md and the showcase capture carry the pair).

### Fixed — a Release build on macOS could unmap its own live memory: an inlined `operator delete` passed `munmap` a length nobody had loaded

Since the large-block route (macOS: every `operator new` of 256 KiB or more gets its own `mmap` region, returned with `munmap` on delete), the region's size has lived in a 16-byte header in front of the block. A Release build links with link-time optimization, which inlined the replaced `operator delete` into its callers. In a function that both allocates and frees a block, the optimizer then sees the header read as a load from outside a block it believes it knows whole (to it, `operator new` returns exactly `n` fresh bytes), and it is entitled to replace that load with any value. It did: in the 0.7.0 release candidate built without profile-guided optimization at least 15 of the 46,669 inlined frees call `munmap( block, <whatever the length register last held> )`. The PageRank score array is one of them, and there the leftover is a pointer, so the request is to unmap several gigabytes.

What that did depended on where the block was. Low in the address space the range runs into a region the kernel will not remove, the call fails with `EINVAL`, and the block is only leaked. Higher up nothing stops it: the call succeeds and removes every mapping above the block. On llvm-project (80,576 files) a fully warm `--for` places the loaded graph there, and the run then read unmapped memory and died with SIGSEGV in whichever function touched the graph next: 6 of 9 fully warm runs on the candidate, on builds with and without profile-guided optimization. Recorded on one such binary over five warm runs, the two that survived show the same call failing with `EINVAL` and the three that crashed show it succeeding. No crash was seen on smaller repositories (0 of 30 on vscode, envoy and cpython), but their Release builds made the same call and leaked the block. A build without link-time optimization, a sanitizer build and Linux were never affected: there the operators are not inlined, or the route is not linked.

The replaced allocation functions are now never inlined, so the header is read where the pointer is only a pointer, as in any allocator behind a library boundary. Output is unchanged. `test/largeallocpeakcheck.sh` gains two arms: **L** builds the route with a small fixture under `-O2 -flto` and requires that 48 blocks freed in the function that allocated them leave the footprint (385 MiB stayed mapped before the fix) and that `munmap` is called from the replaced operators only; **S** counts the `munmap` call sites of the binary under test (2 now; 46,669 in the candidate without profile-guided optimization, 4,135 with it).

### Fixed — default answers define the row keys they print; `legendcoveragecheck` (G) sees what it was blind to

Arm (G) of `test/legendcoveragecheck.sh` promises that every attribute a default answer emits is defined in that answer's own legend. It could not see four classes of attribute: the seven row keys (`p n t id l k c`) were exempt on every verb because "every map legend defines them", six modifiers had no roster row (`--pattern`, `--grep --handles`, `--stray-content --plan`, `--doc-drift --gateability`, `--cochange --cochange-groups`, `--slice-flow`), every row ran on this C++ tree only, and no MCP answer but `stray_content` was read. The gate now judges the row keys wherever a default answer prints them, adds those rows plus `--defs`, runs 18 verbs on a TypeScript and a Python fixture, and reads the MCP `for` (with and without `budget_tokens`), `analyze`, `uses` and `impact` answers. A new premise arm (G0) fails a row that judged nothing. The gaps this found are pinned in `test/legendcoverage_g_baseline.txt`, which may only shrink.

The burn-down, most-used verb first, adds one short present-only compact reading per gap: the MCP `for` twin (`d n= l= pure=`, `b t=`, `field …`, and `task=` read as the query instead of from-trace's "the trace source"), the ranked-map family (`k=` with `t= n= p=` and `<c n=>` on `--metrics`, `--map-diff`, `--around`, `--query`, `--pack-signatures`, `--pack-top-n`), `--grep` (`enc n= h=`, `hit n=`), `--deps` (`inc t=`), `--callees` (`pattern_dispatch=` and its `<pd>` rows), `--from-trace`, `--pattern`, `--exemplar`, `--connect`, `--edit-check`, `--context-ratio`, `--skipped`, `--stray-content`, `--path`'s route bodies, `--lint` (`inert_rules=`, `applicable=`), `--ensemble` (`unavailable=`) and `--merge-scout` (`sym p= id=`, seen only when an arm changed code) and `--pr-context` (`s`/`caller t= n=`, seen only when the diff touches a symbol). The over-target compact legends these readings ride on are registered in `test/legend_over_target.tsv`, one present-only row each. The MCP `for` roster closure now reads only `for`'s own readings and counts a definition only when the leading legend spells it. Found by a pre-release answer audit and confirmed by a second audit.

The new readings move the session legend dictionary to `dictv=671f21061de09758 entries=1098` (docs/COMMANDS.md and the showcase capture are re-recorded).

### Added — `--legend-seen=FILE`: an answer leaves out the legend definitions you already received, and a `--hook` install now keeps FILE for you by REWRITING your ripwire commands

A CLI agent makes several calls a session and was sent mostly the same legend definitions every time; an answer-first `--for` page 1 is about 12 KB of rows plus about 4 KB of legend. `--legend-seen=FILE` names, one 16-hex hash per line, the dictionary entries the caller already holds, and the answer leaves exactly those out. `ripwire --legend-dict=seen` reads answers you received on stdin and prints the hashes they carried, so the file is built from what actually reached you (`| head` included).

- **Per definition, no tiers.** Nothing to read first and nothing to refuse — unlike `--legend-have=`, whose taught tiers measured break-even on the same sessions (+2.6 % at 5 calls, −0.7 % at 10).
- **Lossless.** Rows, CDATA and every root attribute but `est_tokens=` (repriced to the bytes delivered) are byte-identical. Each reduced comment says `[legend-seen: N held]` where it left definitions out, and one comment names the `dictv=` of the dictionary that holds them all.
- **A hash is of the definition's text**, so a file written by another build only matches definitions that did not change. A missing, unreadable, oversized or corrupt file serves the whole answer and says so on stderr — the flag never turns a call into a failure. Refused: an empty value, `--legend-have=`, `--legend=full|dict`, the server transports.
- **`--for` is reducible now.** Its 99 legend pieces — the trailing document legend, the page clause, the `est_tokens=` sentences and the block-local `ripwire for X` legends that travel with their sections, split at their present-only clauses so a cut-down legend is still made of entries — are dictionary entries (`versions.md`). Three block-local `--for` notes were at first left out of the entry table and re-sent whole on every call: the `sigx` note (`sigx: a sigs row d with r above 10 …`), the unread-language hops note (`hops value_refs_unread_for_lang=L …`) and the key-body note (`bodies of=key: …`). They are entries too (`src/forlegendentries.h`, gate `test/legendseenblockcheck.sh`; the legend dictionary gains three lines, `dictv=b98ebdadd81dfb8a entries=1298` → `dictv=d693c8f5ff5535f1 entries=1301`), and the MCP session legend reads the same table. The `reexports` and `shortkey` legends, which are cut per answer by present-only clauses, are still not entries.
- **Still deterministic.** `--legend-seen=FILE` is read, never written, by the binary (`"rb"`, and deliberately not through the parser's own reader, so the file is not a dependency of the warm snapshot): an answer stays a pure function of argv, the tree and FILE's bytes. The hook below lives outside the binary and changes its **inputs**; it does not give the binary a session, and an in-binary session default (output depending on earlier runs) remains refused.

**The hook, ON BY DEFAULT with a hook install.** `skills/install.sh --hook` (and `--codex --hook`, and `--opencode`, whose only hook this is) registers `hooks/ripwire-legend-seen.sh` for Claude Code (PreToolUse/PostToolUse on Bash, SessionStart/PreCompact) alongside the advisory entries; Codex gets its adapter (`hooks/ripwire-codex-legend-seen.sh`) and opencode a loader for its plugin (`hooks/opencode/ripwire-legend-seen.js`). `--hook-legend-seen` installs the hook alone. The hook inserts `--legend-seen=<session file>` after the binary word and records what each received answer carried, per session and per agent, forgotten on resume, clear and compaction. It rewrites nothing but the binary word's tail, never returns a permission decision, and never names the flag to a binary too old to take it. `ripwire wrap claude|codex|opencode` prints the line, and `--doctor --agent=claude|codex` reports a `*-legend-seen` row (installed, events, executable). The MCP server is unchanged (`--mcp-legend=session` already sends each definition once); its `for` sessions now also stop re-sending the sibling-demote comment once it is served.

- **This default changes what the agent types, not just what ripwire prints**, so it is visible rather than silent. The installer prints the entries it will add, the line **"behavior: REWRITES a ripwire Bash command, only by inserting `--legend-seen=<session file>` after the binary word"**, and what it keeps on disk — all before it writes anything. `--hook`'s own banner says that it brings a rewriting hook and names the way out. Every reduced answer says in place where definitions were left out, so a rewritten call is legible in the answer too.
- **Two ways off.** `skills/install.sh --hook --no-hook-legend-seen` installs the advisory entries without it (`--opencode --no-hook-legend-seen` then has nothing to install and says so); `RIPWIRE_LEGEND_SEEN=0` turns an installed hook off at run time. Passing `--hook-legend-seen` and `--no-hook-legend-seen` together is refused rather than resolved silently. A plain `skills/install.sh` still touches no settings file at all, and `--hook-subagent-primer` alone still installs only its own hook.

Measured:

- **Replayed sessions** (flake8, fzf, tmux; the hook driven as Claude Code drives it; the inserted flag text counted against it), against the previous default: **5-call sessions −7.7 % (88,589 → 81,737 B, n = 15 calls), 10-call −10.7 % (120,565 → 107,705 B, n = 30)**; every one of the 45 answers byte-identical outside its comments and `est_tokens=`, and every attribute the default answer defined still defined in the reduced answer or in a held line. A later `--for` page 1 in a session saves a median 2,729 B (17.8 %; 2,085–3,357 B, n = 16 over 8 corpora). A call whose legend shares nothing with what came before pays the flag (about 110 B) for nothing.
- **Why the default moved:** with the hook installed, a session's answers from call 2 carry **about 3,184 fewer bytes each — a ~19 % cut in total answer bytes** (call 2 on one tree: 16,218 → 13,234 B), because the legend is **22.8–25.0 % of a bare CLI answer**.
- **The three block notes**, on 89 development questions from 11 open-source repositories, run as 11 one-repository sessions with the hook's harvest after every answer (240 answers, 229 of them not a session's first call), each call made by the build before and after back to back: **15,180 B fewer over the 229 calls (0.59 % of their output; median −160 B per question with its followed pages, n = 88), 2,254 B of it on page 1 (7 of 89 cells)**. All 240 answers are byte-identical once comments, the `est_tokens=` value and the `dictv=` value are set aside, and the removed bytes are comment bytes only; file / function / body completeness is identical on 89 of 89. Without `--legend-seen` nothing changes: 89 of 89 page 1s are byte-identical. In Claude tokens (`claude-sonnet-5`, by differencing the two builds' answers, 5 answers): −60, −107, −134, −48 and −5 tokens for −160, −307, −360, −147 and −38 B.

What it does NOT do: the per-answer `legend-seen: N definitions you hold were left out …` marker and the in-place references are the disclosure and stay as they are (they are now the larger share of what repeats: 34.3 KB over the same 229 calls). Gates: `test/legendseenhookcheck.sh` (i) and `test/legendseenportcheck.sh` (B) pin the default in both directions — registered by a hook install, absent under `--no-hook-legend-seen` while the advisory entries stay — each arm red on the tree before the default moved.

### Fixed — `--lego` says "unread for this language" instead of `implementors="0"`

`--lego=TYPE` answers one interface's method contract plus every implementor, so an agent can read a real implementation as the template for a new one. The implementor relation is built from the derived → base extends/implements CLAUSES the extractor reads (`src/ingest_relations.h` `captureBases`, the Rust `impl Trait for T` pass, the Ruby mixin capture), and that clause does not exist in every language. Go states conformance structurally and writes none at all, so `g.implementors` was empty for every Go interface and the targeted verb printed that as `implementors="0"`: on nfpm, `--lego=Packager` answered a confident zero about an interface six packagers implement (`apk`, `arch`, `deb`, `ipk`, `msix`, `rpm`), i.e. it told the reader to write from scratch with the template sitting in the tree. ObjC (`@interface D : Base`), GDScript (`extends Base`), Clojure (`defrecord .. Protocol`) and C's vtable-struct idiom measured the same way, and ObjC was the worst of them: its method contract IS read, so the reader got a full contract beside the false zero.

Where the relation is not read, `--lego=TYPE` and its MCP twin now OMIT `implementors=` and emit `implementors_unread_for_lang=LANG` instead — unknown, not zero, the reading `no_file_edges=` already carries for an absent file edge. A count that exists anyway keeps its number beside the disclosure, as a floor over whatever evidence did reach the graph. The fact is the new per-language column `LangFacts::implementorEdges` (`src/langfacts.h`), `Unread` by default so a newly added language discloses rather than claiming a zero it never measured. Ranked `--for` output is byte-identical: it selects interfaces by having a non-empty implementor list, so it never printed such a zero. `test/legounreadlangcheck.sh` pins the table to the index in BOTH directions over 18 per-language fixtures — every `Read` language must still draw a counted implementor and acquire no disclosure, every `Unread` one must draw none and disclose its own `langTag` — so a row on the wrong side, or a fix that disclaims everywhere, reds the gate.

### Changed — a default `--lint` page shows the most important findings first, and `--page-bytes=0` is the whole answer on every paged verb

A default `--lint` answer is a page of findings under the 24,000-character output ceiling, so the order decides what an agent sees first. It used to be file path order: on the eslint tree of the development question set (571 findings, 99 on page 1) the page opened with a `do-while` in `Makefile.js` and then ten rows from a vendored ponyfill under `docs/src/assets/js/`. Findings now sort most important first:

1. files nobody in the repository authors go last — a tool, vendored or generated path, a minified file (`--skipped`'s `minified-suspect`), or a bundle (the same bytes-per-line evidence the ranking lenses already demote by);
2. then rule severity from the lint catalog, `error` before `warn` before `info` (a user rule's own `sev=`);
3. then source files before test, bench and fixture files (the same path tier the ranking lenses already down-weight), then the file's place in the map's PageRank order;
4. then file path, line, rule and text, as before, so the order is still total and deterministic.

Nothing is dropped: following `next=` to the end still yields every finding exactly once, and the set of findings is unchanged.

The rules that found nothing no longer print a `<rule … count="0"/>` row each (31 of 39 rows on that eslint tree). One `<zero_rules n= ran= inert=/>` row after the counted rules names them all: `ran=` the rules that ran on a language the repository holds and matched nothing, `inert=` the rules none of whose languages are there. Every selected rule is still named once.

`--page-bytes=0` now means "the whole answer" on `--lint` (every finding; with `--offset=K`, every one from K) and on `--expand` (every body uncut), as it already did on `--for` and the bare map. Each of the four prints one stderr line, before the answer, when the whole answer is over the output ceiling. `--lint` and `--expand` still page by their own unit, so beside them `--page-bytes` takes `0` only, and it refuses to combine with their own size flags (`--limit=N`, `--pack-budget-bytes=N`), which keep working on their own. Gate: `test/lintordercheck.sh`.

### Fixed — a cold map of a large tree answers five per-call lookups once per question, or without building a key

The receiver-evidence method lookup (`x = Impl(); x.m()`: Impl's own `m`, else the shallowest base level that defines it) walked the receiver type's base levels again on every call, de-duplicating each push by a scan of everything already reached and looking every class of every level up by name. Where a class name repeats across a tree — chaUp merges every base of every class of that name — that walk was about 7% of llvm-project's cold resolve loop. The answer depends only on the type, the method name, whether the call is a `super` call, and the one class definition the type resolved to, so it is now kept per such question and every later call reads it back. A call to a name that function-local definitions share (`helper` nested in many functions) set aside every such definition the call cannot reach, then filtered the name's whole list of definitions — on every call, though a call that no local definition's function holds always gets the same answer: the list without its local definitions. That list is now kept per name, and whether a local definition holds the call is one search of the name's local definitions by file and position; on llvm-project 765,281 of 771,457 such calls are answered from the kept list. Class identity's walk over the real subclasses of a receiver class (a virtual call on a type that declares the method but defines it nowhere) asked the definitions table for "Class::method" at every subclass it visited, for every (class, method) — building the key text and hashing it into the whole table each time; the table's keys are now split once into (scope, name) numbers, each class keeps its scope's number, and a visit is one integer-keyed probe (a method name containing a `:` keeps the text lookup). The C-family guarded base walk kept each receiver type's base levels already, but every call still replayed them and probed each level for the method — though the answer depends only on the type's kept levels and the method; each type now keeps its answer per method (on llvm-project 560,222 of 746,173 walks are replays). The external-veto tables matched an absolute Python `import X` that no direct path resolves against every indexed path — once per such import statement (`import os` in each Python file), though the answer depends only on the module's spelling (and, in a multi-root workspace, the importer's root); it now reads the per-spelling answers the other import tables already kept, and on llvm-project the tables went from about 2.7 s to 0.6 s. Every answer is unchanged byte for byte. `RIPWIRE_STATS` prints the counts as `[mem] recv_method`, `[mem] reach_by_name`, `[mem] canon_split`, `[mem] guarded_answer` and `[mem] py_suffix`, and `test/guardedwalkcheck.sh` holds the method lookup to one walk per question however many calls ask it checks that every call no local definition holds is answered from the kept list, that every subclass visit is answered by the split keys, that the guarded walk answers each (type, method) once, and that the suffix match runs once per module spelling.

### Fixed — a map of llvm-project no longer grows without bound: the name-keyed class and alias walks enter each name once

Any verb on llvm-project (a flagless map too) grew resident memory at about 5 GB/s; one process reached 149.7 GB before the operating system killed it. The cause was `derivesFromName` in `buildClassIdentity`: a depth-12 breadth-first walk over the NAME-keyed base-class table with no visited set. Where one class name is defined in many files, each with its own bases (llvm's test suites define `A` 4,769 times), every level appended every base of every frontier name, so the frontier grew as the product of the fan-outs. With that bounded, graph.h's element-of-alias and arrow-opacity walks over the name-keyed alias table showed the same shape at about 60 MB/s.

All three walks now keep a visited set: each name enters once, at its shortest distance, so "reached within N steps" is unchanged and output is byte-identical. The class walk is also memoised per outer class name. Measured: the default map and one `--for` are byte-identical on koa, tmux, cpython, envoy and nushell, and llvm-project's cold map peaks at about 3.0 GB. 0.6.9 and every earlier release carry the defect.

`test/namewalkcheck.sh` builds a class fan-out (6 names x 12 layers) and an alias fan-out (16 names x 7 levels) that an unvisited walk cannot finish. The binary must finish both under a 1 GiB RSS watchdog, with exact `RIPWIRE_STATS` work counts; given the unfixed parent binary, the gate shows the parent killed past the ceiling.

Also: the Windows clang-cl legs prefer Visual Studio's bundled clang-cl over a standalone LLVM, because the runner image's MSVC 14.52 STL requires Clang 22 or newer.

### Added — the `ripwire-locator` Claude Code subagent, and a main-thread sentence that routes code lookups to it

In Claude Code every tool result stays in the main conversation and is sent again with each later request, so a
`--for` answer read in the main thread is paid for on every request after it. A subagent runs in its own context and
returns only its final report. The locator runs ripwire there and hands back a short list of ranges. No token saving
has been measured; a live A/B arm is specified separately and has not run.

- `skills/agents/ripwire-locator.md`: a Claude Code subagent definition. Given a task, it runs
  `ripwire <root> --for="<task>"`, reads the listed ranges in one turn of parallel ranged Reads, makes at most one
  `--expand` or `--callers` follow-up (Grep/Glob only for a name ripwire cannot place), and returns only `EDIT` /
  `READ path:start-end symbol — why` lines plus one `MISSING` line, at most 12 lines and about 300 tokens. Its tools
  are `Bash, Read, Grep, Glob`: it cannot spawn another subagent and cannot edit. It sets no `model`, so it runs on the
  main conversation's model. It sets `omitClaudeMd: true`, which Claude Code before v2.1.271 ignores. The description
  is 323 B and the prompt body 1,543 B.
- `skills/install.sh` (Claude) installs it into `${CLAUDE_CONFIG_DIR:-~/.claude}/agents/` as a symlink into the
  checkout, or as a copy where a link does not take. A file already at that path that is not ripwire's is kept and
  reported. `--codex`, `--hermes`, `--openclaw` and an explicit path install no agent. A checkout or release without the
  file installs its skills as before. The release and Windows packages now carry `skills/agents/`.
  `--no-locator-agent`, or `RIPWIRE_NO_LOCATOR_AGENT=1` in the environment, leaves it out; the curl installers pass the
  variable through when they activate the Claude skills. A copy installed earlier is left in place.
- `ripwire wrap claude`: the orient line of the paste block (and so the SessionStart primer, which re-prints it) ends
  with one 177 B sentence: "Main thread: for a code lookup, delegate to the `ripwire-locator` subagent (when installed)
  and ask it for edit ranges; run a full `--for` here only when you need the whole map." The block stays 20 lines; no
  other agent's recipe changes. The three-moment brief block and the SubagentStart note do not carry it, because they
  address subagents. `RIPWIRE_NO_LOCATOR_ROUTE=1` drops the sentence and prints the previous bytes exactly (the A/B
  handle).
- `skills/ripwire-orient/SKILL.md` says the same in three lines.

Gate: `test/locatoragentcheck.sh`.

### Changed — the default map's inventory tier is bounded, and its name budget no longer goes to whichever directory sorts first

The `<inv>` tier names or counts every indexed file the ranked rows did not show, one `<ls p= n= f=>` row per directory. Two things about it were measured on 15 repositories and both were wrong.

**The row list was unbounded.** The ranked map holds within 16,879–27,664 B across a 10x range of repository size — the `--top-k=200` cut doing its job — while `<ls>` ran from 2,670 B on tmux to 192,484 B on vscode, 82.4 % of that document. The cut is now taken at the measured content cliff: **2,102 of vscode's 2,534 rows were count-only** (a path and a number, no file named), costing **121,932 B, 52 % of the whole document**, and **959 of those said `n="1"`** — about 58 bytes to report that one unnamed file exists somewhere under a directory. Every row that names code files is kept; the count-only rows are cut to the 32 standing for the most files, ordered by how many that is; and a high total-row backstop bounds a pathological monorepo. The cut discloses itself as `dirs_capped="1" dirs_total=N dirs_next=` in both the XML and JSON dialects, with `dirs_next=` an argv on the same root that lists a superset of what was cut. **No file leaves the accounting**: `listed=` and `unlisted=` are unchanged by the cut, so only the per-directory enumeration is shorter. Measured alone: vscode **233,564 → 113,650 B (−51.3 %)**, cockroach −35.3 %, envoy −22.5 %, angular −21.3 %.

**The 2,000-name budget was allocated alphabetically.** The name ceiling walked directories in path order, so whether the budget reached the repository's source tree was an accident of directory naming. On vscode `.`, `.agents`, `.config`, `.eslint-plugin-local`, `.github`, `build`, `cli`, `copilot_shim` and `extensions` all sort before `src` and exhausted it first: the tier named 409 directories inside `extensions/` and **zero files in the editor's own source tree** — 0 of 1,537 `src/` rows, 0 of 719 under `src/vs/workbench/` — reproducing, for the subsystem, the exact miss the tier was built to fix. The budget is now spent **fewest-unshown-code-files-first**, which maximises how many directories get named: vscode **432 → 1,207** directories named with `src/` going **0 → 806**, cockroach `pkg/` **535 → 1,206**, angular `packages/` **227 → 315**, envoy `source/` from ~0 to 358. The ceiling value, the whole-directory rule (a directory is named completely or not at all) and the `names_capped=`/`names_total=`/`names_next=` disclosure are unchanged, and the number of names printed moved by at most +3 / −10 across the four repositories — the budget moved, it did not widen.

A probe binary with the ceiling lifted showed why a size-DESCENDING order would have been worse than path order, not better: the median directory holds 2 nameable code files and the maximum 300–786, so "most code first" named 11 directories on vscode and drove envoy's `api/` from 538 to 1. That order was pre-registered and then rejected by its own band.

**What this does not claim.** No terminality number, in either direction. The substitution meter is observational and cannot score an undeployed change, so both changes rest on `docs/METHODOLOGY.md` §9 principle 1's output bound, §9.1's "rank before you cut, and never in path order", and a zero-loss check that no named code file is lost to the row cut. Ranking and cutting the NAMED rows is deliberately not done. What remains, measured: vscode's tier still spends roughly 54 KB repeating directory paths in full on every row to deliver 1,998 filenames, which is a schema question and a separate change.

On the 11 repositories whose name ceiling never fires, the name change is byte-identical; on the five whose count-only rows fit the allowance, the whole map is. New gate `test/lstiercapcheck.sh` (22 arms), evidenced by nine adversary builds rather than by a green run; `docs/EVALS.md` carries both pre-registrations, the rejected order, the amendment and the three-binary readout.

### Fixed — a trailing C/C++ annotation macro no longer takes over the function it annotates

`T f( a ) ABSL_EXCLUSIVE_LOCKS_REQUIRED( mu ) { body }` parses as a prototype `f` and a typeless definition named after the annotation, which owned `f`'s body and calls. `f` was left as a body-less declaration, or missing outright when its parentheses were empty (`void A::f() ABSL_…( mu ) {` reads `A::f()` as a variable), so its callees went to a phantom named `ABSL_EXCLUSIVE_LOCKS_REQUIRED` and its callers bound to a declaration. Now the annotation is a `role="macro"` use of the macro, and `f` keeps its own name and body: constructors, destructors, templates, `const` / `noexcept` / `override` mixes, nested annotations (`DISABLE_…( ABSL_UNLOCK_FUNCTION() )`) and data members (`int g_ ABSL_GUARDED_BY( mu_ );`) included. The rule is the syntax, not a list of names, and it covers envoy's damaged recoveries too (a templated reference return type read as an expression, two annotations in a row, a namespace-scope `ABSL_GUARDED_BY` map read behind a missing `::`): where the `#define` is not in the tree, as with abseil's, a single surviving annotation definition would bind every use of the macro. On envoy 138 annotation definitions are gone, none is left, and 8 functions that were missing (`AdminResponse::sendErrorLockHeld`, `SymbolTable::newSymbol` …) are indexed; no other definition changed on envoy, cpython, cockroach, tmux, ninja or htop.

### Fixed — a C/C++ macro invocation is no longer stored as a function definition

tree-sitter cannot expand a macro, so an invocation written where a declaration may stand parsed as a typeless function declarator: `REGISTER_FACTORY( F, B ){ "name" };`, a class-member `MOCK_METHOD( … );` or `DECLARE_LUA_FUNCTION( C, f );`, `FALSE_RUNTIME_GUARD( x );`, an in-function `ASSIGN_OR_CO_RETURN( auto e, co_await f() );`, a C run of `EXPORT_FUNC( name )` lines. Each became a function definition named after the macro: 4,808 on envoy and 391 on cpython (0 on tmux, ninja, htop, cockroach and vscode). Beyond the phantom rows, they made the macro's name non-unique, so its real invocations never became `role="macro"` uses and an in-tree `#define` read `in="0"`: envoy's `REGISTER_FACTORY`, invoked from 573 places, had no caller (now `in="442"`, ten phantom definitions gone). Now such a site mints no definition and is a use of the macro. A block-forming macro whose braces hold statements right after its own `( … )` (`TEST_F`, `TARGET`, `WASM_EXPORT`) keeps its definition, as do real ALL-CAPS functions and constructors; no other name lost or gained a definition on the seven repos. Caches rebuild once (parser version bump).

### Fixed — `--callers` and `--uses` see through one C function-like macro to the function it calls

tmux calls `cmdq_get_callback1` only through `#define cmdq_get_callback(cb, data) cmdq_get_callback1(#cb, cb, data)`. The graph held the macro-to-function edge and `--impact` walked it, but `--callers` and `--uses` printed the macro row and stopped (1 of the 9 files). After the direct rows, unchanged, they now list the callers (and, for `--uses`, the call sites) of every direct caller that is a C function-like macro, each marked `via="macro:NAME"` (JSON `"via":"macro:NAME"`, columnar `<via>` 3), counted in `count=` (and `via_macro=` on `--uses`). One macro hop only: a macro calling that macro is listed as a row, its own callers are not. Per macro, one row per file is listed (the first in the answer's order), at most 16 files; the rest are withheld and said so on the root: `via_macro_capped=` counts them (they are not in `count=` or `via_macro=`) and `via_macro_next=` is the `--callers=MACRO` (or `--uses=MACRO`) call that lists the macro with the most of them whole (JSON and MCP carry the same keys). On CPython a helper called through one macro at 46 functions in 8 files lists 8 rows instead of 46. A Rust `macro_rules!` row is not seen through. An answer with no macro row is byte-identical; `--callees`, `--impact` and the `--for` caller hop are unchanged. As first built (`c085a49b0`) it failed the byte bar; it was limited to the first hop and then, after that version's confirmation also failed the byte bar on one-hop fan-out, to the per-macro file ceiling. Gate: `test/verbfixcheck.sh`.

### Fixed — maintenance: two quality-delta findings fixed rather than acknowledged, three full-suite reds, and a budget gate that read the wrong row

None of these moves an output byte.

- **Shape.** `graphlegend.h defTableLegend` grew from 2 parameters to 4 in two steps (`sole` with the def-row landing, then `rows`/`DefLegendFor` with `--uses`' own reading), so it gated api-surface 2 -> 4 over the range while being clean on either commit alone. It now takes one `DefTableLegendParts`, the `QualityDeltaLegendParts` shape: every field is a property of the answer whose `<def>` rows are introduced, three of the four are booleans, and an argument order a caller has to remember is the seam where a legend starts describing a table it is not attached to. The seven call sites spell the fields they mean. `defattrib.h defGroupsDropSilent` went complexity 14 -> 16 when the untied-declaration fix turned its `ofMatch` range-`for` into an index loop and added the `UINT32_MAX` test that collects a dropped group's member; that one pass is now `defGroupsRenumberMatches`. The proof that no output byte moved is six unchanged, green gates: `attribmultidefcheck`, `verbdefrowscheck`, `verbfixcheck`, `mcpclidiffcheck` (the CLI/MCP dialects still agree byte for byte), `legendcoveragecheck` and `capdisclosemapcheck`.
- **Full-suite reds** that targeted runs never executed. `test/hashsetcheck.sh`: the per-macro ceiling (`6f023ca5d`) declared `macroCeiling`'s `seen` as `HashMap<std::uint64_t, char>` and only ever asked `contains`; a membership table is a `HashSet<K>`, so it is one now (`seen.insert( key )`), one fewer byte of value per entry on the hot row loop. `test/gateexitcheck.sh`: the new `test/subagentprimercheck.sh` reported 34 verdicts through the one-line `… && ok … || no …` spelling, where a failed write of the PASS line prints FAIL for an arm that passed; all 34 are now the suite's wrapped spelling. `scripts/formatcheck.sh` gate mode: `src/graphlegend.h` is in the set that must match `.clang-format` byte for byte, and `DefTableLegendParts` was written with aligned declarations and comments; reformatted with clang-format 22 (the pin), only that block moved.
- **The MCP `for` budget gate reads the next rank past a cut, not the next printed row.** `mcpforparitycheck` checks that a soft `budget_tokens` cut is maximal: the next unit past the cut must not fit. Under a soft target the demote rules run after the ladder has cut the rows, so a rank past answer row 10 can ship as a `<t r=>` pointer, and the reference the gate priced the next row from printed those ranks as pointers too. The gate skipped them and compared a later, smaller row: on this repository's own `src/` at `budget_tokens=1600` it compared rank 15 (120 B) where the ladder's next unit is rank 13, a 367 B row that first fits at `budget_tokens=1621`. It failed on every binary on the merged tree and passed on each branch's own tree. It now takes the lowest rank served neither as a row nor as a pointer and prices it as a row without its doc, from a reference read with the demote rules off. A mutant that under-fills the MCP refill by 200 B turns it red at `budget_tokens=2000`.

### Added — `--for` prints the manifest lines that define a package, dependency, binary, build target or feature the task names

A task that names something a manifest defines now ends with a `<manifest_rows>` block before `</ctx>`: the manifests whose names hold a task word exactly, best first, each with `matched=` (the task words its names hold) and up to three defining lines (`<r l= kind=>`, the line's text, cut at 120 bytes with `cut="1"`), `kind=` saying what the line defines (package, module, dep, dev-dep, peer-dep, opt-dep, script, bin, main, lib, feature, extra, executable, library). Read: `package.json` (name, main, bin, scripts, the four dependency maps), `Cargo.toml` (`[package]` / `[lib]` / `[[bin]]` names, `[features]`, dependency tables and `[dependencies.X]` headers), `pyproject.toml` (project and poetry names, optional-dependencies, extras), `setup.cfg` (`[metadata]` name, `extras_require`), `go.mod` (module and require lines, `// indirect` ones skipped) and `CMakeLists.txt` (`add_executable`, `add_library`, `project`); the last three are not indexed files and are looked for beside every indexed file. On "add a new built-in microservice transport like NATS or MQTT" the microservices package's `package.json` comes first with its optional `mqtt` peer dependency; previously that file appeared only as a path, with no line, in the answer's tail.

When the match is a cargo feature or a Python extra, the manifest's row carries a `<feature_touch>` with the files that mention at least half of its features (the same co-mention scan as `<exemplar_family>`'s touch list): on "add a new optional extractor behind its own cargo feature like multipart" it lists the crate's `lib.rs`, whose crate docs hold the feature table.

The block never fires on the repo's own name, with or without a kind word (every task about a crate names it; only a plugin entry point's group may be the repo's name), on a generic name (core, common, test, ..), or on a `package.json` script unless the task says script, npm, yarn or pnpm. An entry anchors only when the task says what kind it is (dependency for a dependency, feature for a feature, package, binary, ..) or reads as adding one more X, so a common word (`path`, `handler`, `router`) never prints the same-named third-party dependency, Rust feature or fuzz binary; `benchmarks/` trees are skipped like `fixtures/`. Caps are disclosed (`files=`, `rows=`, `shown=`, `capped="1"`); a token budget the answer and the block do not fit holds the block (`held="budget"`; the budget fit prices it like `<exemplar_family>`); `--json` carries none; the MCP `for` tool prints the same element. New gate `test/formanifestcheck.sh` pins one fixture per manifest format, the silent wordings beside each firing one, the caps, the dialects and the legend.

Python entry points are rows of the same block: `[project.entry-points.<group>]`, `[tool.poetry.plugins.<group>]` and setup.cfg `[options.entry_points]` entries print as `kind="entry-point"` with `group=`, and `[project.scripts]` / `[tool.poetry.scripts]` keys as `kind="bin"` (read by the same readers the existing `<ep>` element uses). An entry point fires only when the task says plugin, entry point or extension, and its group matches by any dot segment, even when the group is the repo's own name: on "write and register a pydantic plugin that observes validation" the block prints the in-repo example plugin's `tests/plugin/pyproject.toml` with its `[project.entry-points.pydantic]` entry.

Parser fixes from the review: a Poetry constraint list over several lines (`numpy = [ {version = .., python = ..}, ..]`) and a trailing `# comment = ..` in a Cargo feature array no longer print `{version` or a garbage feature (an open multi-line TOML array is a value); Poetry groups (`[tool.poetry.group.<g>.dependencies]`) and `dev-dependencies` are read and the interpreter key `python` is not a dependency; CMake `#[[ .. ]]` bracket comments, `IMPORTED` and `ALIAS` targets are not read and an `add_library(` call that spans lines is. Gate arms f3a-f3e.

A feature row's `<feature_touch>` line now names where the anchored feature is defined or documented: when the line EXEMPLAR's touch list picked is a `#[cfg(feature = ..)]` use, it is replaced by the first other line of that file that names the feature (axum's crate-doc feature table row for `multipart`, not the `#[cfg(feature = "form")]` beside a module); a file with no such line keeps the cfg line, which says what it is.

When the first manifest only depends on what the task names, the best one that DEFINES a named thing (a package, bin, feature, .. anchor) moves to the front, so on "add a new built-in tool for the Zed agent" the `agent` crate's own `Cargo.toml` is no longer behind the crates that list `agent.workspace = true`.

A file name the task spells is not a task word by its extension: "how renderers are selected from `book.toml`" no longer prints the `toml` dependency rows of every crate that depends on it (`toml`, `json`, `yaml`, `yml`, `cfg`, `ini`, `lock`, `xml`, `txt` after a dot); the stem and the folded name still count, and "a dependency like toml" still fires. Gate arm fx1.

### Fixed — MCP `for` no longer over-states `est_tokens=` by four to five times the price of the act line's own bytes

When the MCP `for` bundle carried the act line (`<act read="…"/>` and its legend clause), its `est_tokens=` rose by far more than those bytes cost. The bundle's price is set before its `<syms>` block is added (that block's clause says it is "not in est_tokens"), and the act line re-priced the root from the number alone, so it charged the whole `<syms>` block along with its own bytes. On ripwire's own `src/`, a 264-byte line raised `est_tokens=` by 490 where the round-to-nearest price of those bytes is 105 to 106; on ten development questions across ten repositories the rise was 506 to 689 tokens for 265 to 385 bytes, 4.1 to 5.2 times what the fixed price charges.

MCP `for` now re-prices through what its root was converged from, the same way the CLI `--for` does, so the line raises `est_tokens=` by exactly the round-to-nearest difference its bytes cause: 106 to 154 tokens on those ten questions (each bundle's `est_tokens=` falls by 382 to 535). Without `budget_tokens=`, only the `est_tokens=` number changes: every other byte of the MCP bundle, and every byte of the CLI `--for` answer, is unchanged, and a bundle without the act line is byte-identical to before. Under `budget_tokens=` the line is written only while the bundle still fits the budget with it, and that test now reads the corrected price, so a budget the line fits by its true price now carries it where the over-stated price had dropped it (one question, `budget_tokens=5300`: before, no line; now the line, at `est_tokens="5271"`). `test/actlinecheck.sh` now bounds the MCP rise from above as well as below, as it already did on the CLI.

### Changed — MCP `tools/list` is 15.8 % shorter (47,411 to 39,940 B), the tool contract byte-identical

Every tool's description keeps its routing first sentence, every floor and "not a proof" caveat, refusals, side effects, bands, defaults and response-shape text for the legend-less JSON answers; what was removed is prose after the routing sentence that repeated a property description, a JSON key list, `readOnlyHint`, the legend's attribute glossary, or a pointer the field descriptions already carry. Property descriptions and the schema structure are unchanged (pinned by `test/mcplist_structure_golden.txt`), and `initialize.instructions` is unchanged. Descriptions went 22,498 to 15,133 B; the wire line 47,289 to 39,908 B. A blind tool-choice check (33 single-intent requests, one per tool) picked 33 of 33 identically before and after; that is a ceiling-effect sanity check, not an eval. `test/mcpmanifestcheck.sh`'s ceiling ratchets down 47,420 to 39,970 B. Commit `bfaf260c3`; new gate `test/mcplisttrimcheck.sh`.

### Changed — each indexed reference takes 120 B less memory, so large repos peak 10-24 % lower

Each indexed reference (one row per call, read, import or base-class use: 1.2 M rows on envoy, 2.0 M on vscode) carried nine text fields. Five of them are empty on most rows: a compose edge's field name and relation, a member call's receiver path, constructed type and Ruby builder. They now live in a separate block, and a reference has one only when it uses one of the five. A reference row drops from 264 to 144 B, and the raw row the parser fills drops from 248 to 136 B (libc++; libstdc++'s larger strings save more). Peak memory footprint, median of three runs on macOS: envoy 743 to 618 MB cold and 724 to 547 MB warm, cockroach 986 to 887 and 951 to 842, vscode 1,338 to 1,149 and 1,274 to 1,069. Answers do not change: `--deps` is byte-identical on the three repos, cold and warm, and so is every one of the 321 stored `--for` and map calls. The cache format is unchanged, so existing caches stay valid.

### Added — an allocator-level memory ceiling, on by default at the memory guard's own limit

`--max-memory`, `RIPWIRE_MAX_MEMORY` and the default 65%-of-RAM cap were read only at phase boundaries, in the
crawl/parse workers and in the file graph's fold. A run that grows inside one call sees none of them: on
2026-11-18 a run over llvm-project grew about 5 GB/s inside `buildGraph`'s resolve loop and reached 149.7 GB
before the OS killed it, because nothing between the `graph-tables` and `graph-end` readings reads memory.

The guard now has a second reading site at `operator new`, where every growth passes, so it sees inside a loop
with no call site in it. It is **on by default** at the guard's existing hard limit — one limit and one knob,
not two: `--max-memory` and `RIPWIRE_MAX_MEMORY` move this line too, and a refusal exits **5**, the
memory-refusal code everywhere in ripwire. **The limit is shared; the quantity measured against it is not.**
This line reads **this process's own footprint** and nothing else, while the guard's phase-boundary lines take
the larger of that and the cgroup v2 leaf's unreclaimable charge. So in a Linux leaf with a finite
`memory.max`, shared with other processes, the allocator line can admit after the leaf's charge has already
passed the limit, and that case stays covered at the guard's phase boundaries only. What this line exists to
catch — one process growing without bound inside a single loop — is exactly what the process footprint shows. `RIPWIRE_MEM_BUDGET_MB=<MiB>` sets a ceiling for
this line alone and `RIPWIRE_MEM_BUDGET_MB=0` turns it off; a value that is neither 0 nor a whole number of at
least 64 MiB refuses the run (exit 1) rather than being ignored. A refusal is one stderr line naming the limit,
the footprint, the next request and the phase, written from a stack buffer with no allocation. It does not flush
pending stdio, so a map still being assembled prints **nothing** — but `_Exit(5)` cannot retract bytes already
written, so a command that had streamed part of an answer leaves that partial stdout behind, and the refusal line
says as much ("any output already printed above is cut, not complete"). **Exit 5 means the run answers nothing: a
caller must discard whatever stdout holds rather than parse it.**

**One region refuses nothing, on purpose.** An edit verb commits the file with `atomicWrite` and then rebuilds
the index for its post-check. Ending the process there would leave the edit applied with no receipt, and a
caller that retried could insert the same text twice — so the line is **suspended for that region and only
there**: a crossing inside it is recorded rather than fatal, and every edit receipt now carries a
`memory_ceiling` field saying which of the three things happened — the ceiling was not armed for this run, or
it was suspended and the limit was not reached, or it was suspended and the check **passed** the limit, with
the peak and the count. The field is always present, on both the CLI and MCP receipts, so no receipt can imply
a ceiling-checked post-check; MCP receipts say "not armed", since a server never arms the line. The
suspension is reachable from no flag and no environment variable, every pre-write check stays armed, and the
memory guard's own phase-boundary stop still applies inside the region (it reports `post_check: "not run: …"`
and exits 0). The accepted cost: growth inside one loop is unbounded again in that one bounded region.

An allocation of 256 KiB or more reads the footprint before the block is taken; smaller ones read once per
64 MiB per thread. Disarmed the cost is one relaxed atomic load per `operator new`. **It only reads — it never
changes what is computed**, and a run under the ceiling prints byte-identical stdout, stderr and exit code with
the line on, off, or armed far above the need. `--mcp` and `--lsp` do not arm it, because its refusal ends the
process and a server must survive a refused request; a build whose `operator new` is not replaced (a sanitizer
or `RIPWIRE_ALLOC_COUNT` build) cannot arm it and says so when asked explicitly. What this line still cannot
see — `malloc` called directly by tree-sitter, `mmap`, and small allocations between readings — stays covered
by the guard's existing `memory_peak=` disclosure. macOS uses the existing allocator hook; Linux, Windows and macOS with `RIPWIRE_LARGE_ALLOC=OFF` get `src/memceiling_new.cpp`, first proven by CI. Measured on llvm-project with the pre-fix resolver: `RIPWIRE_MEM_BUDGET_MB=9000` refused with rc 5 at a 5,689 MiB footprint before a 3,520 MiB request, inside the class-identity step that held the runaway, where the OS had killed the run before. Commits `fbd3b192d`, `ec810904f`. Gate: `test/memceilingcheck.sh`.

### Fixed — a `found="0"` answer of `--callers` / `--uses` / `--impact` names the plain-text occurrences of the name

When no indexed definition matches the selector, the three "who uses it" verbs (and their MCP twins, in the refusal's `error.data.answer`, whose JSON rows use MCP's `"file"` / `"line"` keys) still answer `found="0"` with exit status 1, and, when the selector is a bare name, now also carry it as a whole word in the indexed files: `text_hits=` (lines), `text_files=`, one `<text p="FILE:LINE" n="N"/>` row per file (its first such line and its line count; at most 20 rows, source files first) and `next="--grep=NAME"`. The legend labels them PLAIN TEXT, never a call or a use the graph proved. fastify keys a reply property with `kReplyHijacked: Symbol( … )`, an object-literal key and not a definition, so every graph verb answered an empty `found="0"` while the files that read and write `reply[kReplyHijacked]` were one `--grep` away. The scan is the literal `--grep` scan plus a whole-word test, bounded (512 files, 64 MB read; a stop prints `counts_floor="1"`). A qualified selector (an unknown qualifier stays refused, never read as the bare name), a name no file holds, a refusal over several definitions, `--callees`, `--defs` and `--path` answer exactly as before. Gate: `test/notfoundtextcheck.sh`.

### Changed — a `--for` answer to a two-endpoint question prints rows that reach only one endpoint as tail pointers

When a `--for` task names exactly two symbols ("How do A and B connect?", `A + B`, "pass a new parameter into B from A"), a printed `<sigs>` `<d>`, `<callers>` `<s>` or `<syms>` `<y>` row that reaches only one of them within 3 calls, and lies on no shortest path between them, is now printed in its place as a tail pointer `<t p="FILE" sym="NAME" r="RANK"/>`: still on screen, no longer an answer row. When the index holds a short call path from one endpoint to the other, the question reads as root and sink, and the demoted rows are those that reach the sink from outside the root's reach (a wrapper above the root); a direct caller of the sink stays. Otherwise both are sinks, and a row that reaches one but not the other is demoted unless it is on a shortest path from a row that reaches both. On the graded sets these rows were the largest class of picked decoys.

The rule is off unless some printed row reaches both endpoints: where the index lacks an edge of the true chain, the true common caller looks one-sided, so nothing is touched. A row stands for every definition of its name in its file (an overload's declarations and its implementation) and, for a C/C++ header declaration, for the definitions whose file answers that header. The reach sets and path nodes are computed once per answer. A short legend comment rides before the first pointer; a token budget leaves the answer as shaped, and `est_tokens=` is re-priced over the rewritten bytes. CLI `--for` and MCP `for` share the one renderer; `RIPWIRE_NO_ONE_SIDE_REACH=1` turns it off. `test/foronesidecheck.sh` pins each arm with a twin.

### Fixed — bare `--lint`, `--expand` and map answers fit an agent's screen, and `--for --page-bytes=0` warns when it will not

Claude Code's Bash tool shows a result inline up to about 30,000 characters; past that the agent gets a file path and a 2,000-character preview instead of the answer. Every surface below is now held to the 24,000-character output ceiling (the inline limit less 20 %, `src/outputceiling.h`). All figures were measured on the 11 open-source repositories of the development question set, one tree each. Gate: `test/outputceilingcheck.sh`.

- **`--lint`.** A bare `--lint` budgeted its findings at 100,000 bytes, so on 9 of the 11 repositories it printed more than 30,000 characters (largest 83,162). The default page is now sized so the whole answer — legend, root, rule tally and findings — stays under the ceiling. The cut is the one `--lint` already disclosed: `shown= total= capped="1" has_more="1" next_offset=K`, and the root now also carries `next="--lint --offset=K"` (with any `--lint-select` / `--lint-ignore` / `--lint-rules` / `--lint-max-per-rule` / `--naming-locals` / `--with-profile` you passed). `--offset=K` alone is now byte-budgeted the same way, so every page of the chain fits too; before, it printed every finding from K on. Following `next=` until `has_more="0"` yields every finding once, in order. An explicit `--limit=N` is unchanged and is still the way to ask for a bigger page. Largest default answer 83,162 → 19,589 characters; answers over 30,000: 9 → 0.
- **`--expand`.** A bare `--expand=NAME` served bodies up to a 64 KB budget, and the budget counted only body text — not the `<b>` tags' `sibs=` / `inc=` lists: `--expand=toString` on gson (33 definitions) printed 51,406 characters and Newtonsoft.Json's hub 34,773. A bare `--expand` now budgets its bodies at 16 KB and, when the `<bodies>` section still comes out over 20,000 bytes, re-renders at a proportionally smaller budget. Nothing new is invented to say what was cut: a cut body says `truncated="1" lines="lo-hi/T"` and its `next=` is the slice that continues it (`--expand=FILE:LINE:NAME:A-B`), and definitions that did not fit are counted by `unserved_total=` and listed by `unserved_next=` (the first 16, as before — so a name with many definitions can leave some counted but unnamed; a larger `--pack-budget-bytes` serves them all). By default a file over the ceiling budget is no longer a whole-file candidate, and `reason=` says so. An explicit `--pack-budget-bytes=N` is your size and is honoured as before; `--for` is unchanged. On the map's first three named symbols per repository: largest `--expand=<hub>` answer 51,406 → 18,845 characters; answers over 30,000: 2 → 0 (gate arms: a 1,400-line body's slices rebuild it exactly; 40 definitions are served or named, none dropped).
- **The flagless map.** `ripwire DIR` prints a 200-row ranked map plus an inventory of every file the rows do not show; 3 maps were over 30,000 characters (Newtonsoft.Json 52,858) and 5 over 24,000. A bare map over the ceiling is now rendered whole, exactly as before, and served in pages cut between its own rows: the file groups and, inside a large inventory, its `ls` rows (the `<inv>` tag is re-sent around the part each page holds). Page 1 keeps the legend; every page's root says `page= pages= withheld_bytes= has_more=`, re-prices `est_tokens=` for the page, and names the next page as `next="--page-bytes=24000:K"` (plus `--exclude` / `--max-file-size` / `--no-ignore` / `--ignore-tests` when you passed them, so it maps the same files). The pages' rows rebuild the whole map. `--page-bytes=N` sets the page size and `--page-bytes=0` prints the whole map in one call. A map under the ceiling, and any map shaped by `--top-k`, `--max-tokens`, `--token-budget`, `--query`, `--rank-by`, a payload verb, `--json`/`--html` or a non-default `--legend`, is unchanged. `--page-bytes` beside a report verb now refuses instead of being read by nothing. Largest bare map 52,858 → 23,629 characters; maps over 24,000: 5 → 0, over 30,000: 3 → 0; on every repository the pages rebuild the whole map.
- **`--for --page-bytes=0`** asks for the whole `--for` answer in one call, and it still prints it whole and byte for byte; 5 of 11 such answers were over 24,000 characters and 2 over 30,000 (largest 43,403). When the answer is over the ceiling, one line now goes to stderr **before** the answer — so it lands inside that preview — naming the answer's size and that dropping `--page-bytes=0` serves it in pages. Under the ceiling nothing is printed, and stdout is byte-identical to before.

### Fixed — a C++ call whose argument types pick one overload, and a Go call through a generic field, no longer split

A C++ call to one class's same-arity overloads was split onto every overload (`prov="split"`), even when the arguments' declared types pick one of them. Now, when every argument is one of the calling function's own parameters and exactly one non-template overload takes each argument as its exact declared type, that overload is the edge, bound alone. Otherwise the split stays: no overload takes every argument by identity (one reachable only by a conversion), or a guard stops the pick: a template overload, a const or pointer mismatch (a `const` inside a template argument, `Box<const T>`, belongs to the type), a shadowed parameter, a different namespace, a receiver no lookup proved, or a qualifier naming another class. On envoy, `WatermarkBuffer::prepend( absl::string_view data )` now calls only `OwnedImpl::prepend( absl::string_view )`. 41 envoy call sites move from split to one edge.

A Go call through a struct field whose type is a qualified generic instantiation (`suppressedModules addrs.Set[addrs.Module]`) now reaches that package's type (`addrs.Set.Add`), not every type named `Set`. Other qualified field types also bind to their own package's type when it defines the method. Interfaces and embedded types keep their previous answer. New gate arms in `test/aritycheck.sh` (section 3d) and `test/receiverevidencecheck.sh` (G).

### Changed — `--pack-task` is one bundle again: the `--for` head, the file tail, and ONE key body

`--pack-task` called the same ranker as `--for` and then threw most of its locating power away: a fixed
12-row window in raw score order, every row more than one hop from its six bodies demoted to a name-only
`<far>` row, and no file-grain tail at all. Measured on 52 tasks over this repo's own history, `--for`
page 1 named 148 of the 165 files those commits changed and `--pack-task` named 89 — and the budget had
cut no ranking row in any of the 52. It was a shape problem, not a budget problem.

The bundle now takes its locating surface from `--for`: the same 40-row head, in `--for`'s order, under
`--for`'s own lens rules (the relevance floor, `e=`, docs after code, the round robin by file), with rows
past the first ten re-spelled as pointer rows — name, place and the `--expand` selector's parts; and
`--for`'s file tail, filled last with everything the other sections leave and cut at a row boundary. The
six full bodies become ONE, the key body (the symbol the task names in backticks, else the top-ranked
one), and every other candidate rides as a `<bn … next="--expand=…"/>` pointer counted in `total=`.
`<callers>` is that body's own callers.

**The file tail takes its declared share as a FLOOR, not as the leftover.** The first build of this shape
gave the tail whatever the sections above it happened to leave, and on a corpus with a long task and long
signatures that was nothing: measured over LocBench's 303 tasks, the tail declared a 20% share of the
shaping budget and received 0.6% — a median `shown="0"` of `total="512"` files — and on 82 of the 84 tasks
whose bundle did not name every file the question needed, the file it needed was in that cut tail.
Completion is counted in files and the tail is the section that names files. Its share is now reserved
before the cascade spends and handed back on top of whatever the sections above leave, so the tail still
grows into their slack but can no longer be starved by it. Over 596 tasks on four sets, that moves the
bundles that name every file the question needs from 329 to 420; LocBench alone goes from 219 to 224 of
303. The budget did not change: the finding above was that this is a shape problem, and raising the budget
would have been the wrong fix.

**`<bodies capped=>` now admits a body it cut.** The attribute read only "fewer bodies served than handed
in" and ignored `truncated="1"` on the one body it serves, so a bundle whose body was cut at the byte
budget published `capped="0"` over it: 194 of 596 measured answers said nothing was cut while a `<b
truncated="1">` row sat inside them. `capped="1"` now also rides a served body that was truncated, which is
the reading `<tail>`, `<calls>` and every other truncating element already spell.

**`--pack-task --token-budget=6000` now serves what the default serves.** The default budget IS 6,000
tokens, but the explicit form passed its own number into the head's lens rules while the default passed
none, and one of those rules is off at 6,000 — so the two answers to the same question differed by a whole
section's reading (`files_first=`). The head now takes the lens's own verdicts in both paths.

`est_tokens=` and `budget_tokens=` now use ONE conversion. The budget was converted to bytes at 2.36 B
per token while the result was priced at 2.50 and 3.80, so a bundle that had spent 91% of its bytes read
`est_tokens="3975"` against `budget_tokens="6000"` and looked a third unspent. Every delivered byte is
now priced at the rate the budget is converted at, and the legend says so and says which direction the
bound runs.

Gates: `test/packtailsharecheck.sh` (the tail's share is a floor: a 1,200-char task at the default budget still serves it, its bytes reach the floor the share implies, the share is read out of `src/packtask.h` so the gate and the cascade cannot drift apart, the row count is monotone in the budget, and a `--partition` slice reserves nothing — with an arm that asserts a pre-fix binary IS red on the same fixture), `test/packlocatecheck.sh` (the head's r=13..40 rows and the tail's files are named; the first 40
rows equal `--for`'s; the tail cut carries `capped="1"` and `next=`; the answer stays under the declared
ceiling) and `test/packkeybodycheck.sh` (exactly one body, the key-body choice, every dropped candidate a
pointer, the ledger's counts agree).

### Changed — a paged `--for` answer's page 1 no longer defines, in advance, what only a later page carries

A paged `--for` answer (the default, about 12 KB a page) used to put the WHOLE document legend on page 1, including the clauses
that define rows page 1 does not hold: the hops clause for a `<hops>` that starts on page 3, the fold clause for a `<fold>` on
page 4, `c via=name` for a `<c via="name">` two pages on. Such a clause now travels with the page whose rows carry it: page 1
leaves it out, and each later page that carries its element or attribute ends with one comment holding it verbatim
(`<!-- defined for this page, the rest on page 1; … -->`), before its `<about legend="ref" have="page1"/>`. A later page never
re-sends a clause page 1 still holds. The page clause says so in one sentence: root next= is the next page, "no legend but the
definitions of what only its rows carry (this one defines the rest)".

The rule a reader can rely on: **whatever page N carries is defined on page N or on page 1** — page 1 because every continuation
page names it, nothing between because a page may be asked directly. Nothing is reworded: a moved clause is its dictionary entry,
so `--legend-seen` leaves it out of the later page when the reader holds it, as it does on page 1. Rows are byte-identical. A clause
stays on page 1 when page 1 carries one of its elements or attributes, and also when it is the only page-1 text spelling `a=` for an
attribute a page carries (the hops clause's `n=` is the only `n=` an element-form `<d n=>` meets; with the default row-line form the
row-line clause spells it, so the hops clause can move). The MCP `for` answer is not paged by this path and is unchanged.

Gate: `test/pagelegendcheck.sh` (the rule per page on two page sizes, in both row forms, with mutation controls).

### Changed — cold indexing climbs the syntax tree from a cached path instead of the root

tree-sitter's `ts_node_parent` re-descends from the root of the file's tree on every call, and ingest climbed a few parents per call site (the argument list and receiver of every call, a C++ or Rust qualifier chain, a scope climb from the side-capture visitors), so one climb paid several descents over the same wide levels. A new `parentOf` (src/infra/tsparent.h) answers from one cached root-descent path per file and resumes the descent at the deepest cached ancestor that holds the node. It returns exactly what `ts_node_parent` returns, which a verify build (`-DRIPWIRE_VERIFY_PARENT_CACHE`) checked on every answer over large Go, Rust, C++, Python and TypeScript repos. A cold `--deps` retires 15 % fewer instructions on envoy (C++), 13.5 % on zed (Rust), 7 % on cockroach (Go) and django (Python), and 6.7 % on vscode (TypeScript, after #578), as the median of three interleaved base/head runs. Answers do not change: `--deps` was byte-identical base vs head, cold and warm, on every measured repo, and the 321 in-sample `--for` / map calls were byte-identical. Warm runs never ran these climbs and are unchanged. `RIPWIRE_NO_PARENT_CACHE=1` runs the same binary on plain `ts_node_parent`; `test/parentcachecheck.sh` compares the two and pins the shapes a wrong parent moves.

### Fixed — `--path` says when its verdict is one of many unwalked definition pairs, and `Owner.method` narrows instead of refusing

Found in a pre-release comparison run. When `to=` names more definition groups than the 16 the pair walk visits (`pairs_unlisted=G`), the root's `reachable=`/`hops=` described the nearest pair one search over all of them found, yet read as a definite verdict: nushell `--path=eval_call,run` printed `reachable="1" hops="1"` from 4 x 833 candidates. The root now carries `nearest_of="K"` (from= groups x to= groups), and the legend says the pair the reader means is not answered and to qualify both ends; MCP `path_between` prints the same. A scope-qualified endpoint that several placed definitions fit (vscode `InstantiationService._createInstance`: a class and its vendored copy) no longer answers rc=1 "none is chosen": `--path` binds every fitting definition named the spelling's last segment and lists the reaching pairs, while the one-source narrowing (`narrowed=`) still runs first and a wrong owner still refuses. `test/pathambigcheck.sh` pins both; fire321 and the `--deps`/map md5s are byte-identical. It does NOT change `--verify` or `--connect`, which resolve their ends their own way.

Versions: the session legend dictionary moves to `dictv=e465b030656de882 entries=1123`; docs/COMMANDS.md and the showcase capture are re-recorded.

### Changed — flat table accumulator and zero-allocation commit parsing in `gitFileAuthors`

`gitFileAuthors` (`src/gitmine.h`) parses whole-repository git history to compute recency-weighted ownership (`--owners`, `--pr-context`, and MCP `owners`). Previously, it accumulated per-file commits into an outer `HashMap<std::uint32_t, ...>` and parsed commit header timestamps via heap-allocated `std::string tsStr` and `std::strtoll`, before sorting results by `fileId` at the end to restore determinism.

Since `fileId` is a dense `0..fileCount - 1` integer produced by the ingested file table, `perFile` and `newestTsByFile` now use flat vectors indexed directly by `fileId`. Header parsing replaces per-commit heap allocations with zero-allocation `std::from_chars` and buffer assignment `curEmail.assign(...)`. Because vector reduction visits files in strictly ascending `fileId` order, the final `std::sort` by `fileId` is eliminated entirely. Output remains 100% byte-identical.

### Changed — PGO training covers more of ripwire without diluting its hot paths

`scripts/pgobuild.sh` trained six verbs on this checkout, though its comment spoke of two corpora. Training is now two
groups written to separate raw profiles and merged weighted: a CORE group (the original runs, unchanged, weight 4 —
`RIPWIRE_PGO_CORE_WEIGHT`) and a COVERAGE group (weight 1): page 2 of a paged map, `--lint`, `--clones`, `--expand`,
`--grep` and `--for` by name and by path on this checkout, plus the full verb list on a synthetic tree that
`scripts/pgocorpus.py` writes at build time (seeded, deterministic, standard library only: namespaces sharing the class
names `Base`/`Impl`/`A`/`B`, deep namesake inheritance, overloads, call-result chains, and one slice of each other
language family). A training run that exits non-zero on this checkout now fails the build.
`scripts/pgobuild.sh --check-training BIN` runs the same list without building; `optremarkscheck` uses it to prove every
listed verb runs, the core group is exactly the original runs, the generator writes the same bytes twice, and no
benchmark corpus is named. Output bytes are unchanged: PGO changes speed, never an answer.

### Added — Protocol Buffers (`.proto`) definitions are indexed, and a generated name links to its schema by name

A `.proto` file is now parsed (vendored coder3101/tree-sitter-proto v0.6.0, MIT): messages (and proto2 groups), enums, oneofs, services, rpcs and enum values are definitions, so `--defs`, `--whereis` and `--expand` name and print them. A schema definition is no `--for` ranking document: it adds nothing to the corpus statistics and takes no ranked slot from code that shares a word with it, so `--for` names one only through an exact-name ask (`--for=ExprService`) or the generated-name rung below; a nested message or enum is scoped to its owner and an rpc to its service. Keywords inside comments and string options are not definitions. A schema has no call or file edges: fields, `package`, `import`, `option` and `extend` are not read yet. The Rust, Go, C++, Python and TypeScript modules a build generates from a schema are usually not in the tree, so when `--for=X` resolves to no definition and the tree's code spells a generated path for X (`use x_pb::expr::expr_node::Type as ExprType;`, `from m_pb2 import Leaf as X`, Go `Outer_Leaf`), the not-found ladder gains a `gen` rung naming the `.proto` definition by name only (`via="name"`, `exact="0"`, `cands=` when several match, `shown=` the rows printed), never as a proven edge, even when a `--scip` index resolves a call to the schema definition; its legend rides only answers that print it. A generated alias that is itself a definition (Go `type A = pb.Outer_Leaf`) is served as that definition, without the rung. Caches are rebuilt once (parser version bump). New gate `test/protoindexcheck.sh`.

### Fixed — a call a rule proved is no longer listed as a call site of a same-named method

A caller row's `sites_at=` (the callers verb, `--safe-delete`, the `--for` callers hop and its site pick, `--edit-check`'s sites) matched call sites by the callee's leaf name, so a caller with edges to two definitions of one name listed every call of that name under both rows. envoy's `FilterManagerImpl::onConnectionClose` showed its proven `close_action.closeSocket()` lines (145, 154) under the by-name `ConnectionImpl::closeSocket` and `RawBufferSocket::closeSocket` rows, which read as a proven site keeping by-name namesake edges; only line 153 (`latched_close_action_->closeSocket()`, through a `std::optional`) is matched by name. A call a rule proved now counts as a site of its own targets only, and a file- or scope-qualified `--uses` drops it the same way. A call matched by name keeps the name test, and a caller with no proven call of the name keeps its row and sites. A proven recursive call is a site of its own caller only: cockroach's free function `startExec` no longer lists its `startExec(params, child)` recursion (`pkg/sql/plan.go:557`) under the 163 `startExec` method rows it also calls through `plan.startExec(params)`. The `sites_at=` legend reading says so in the same number of bytes.

Versions: the session legend dictionary moves to `dictv=b98ebdadd81dfb8a entries=1298` (the `sites_at=` reading); docs/COMMANDS.md and the 2026-11-19 showcase capture record the new pair.

### Fixed — a bare Python call binds the definition its own scope chain binds, not every namesake

A bare call `Model(...)` whose name the call's own scope, an enclosing function, or the module binds by
`def`/`class` statements alone now resolves to those definitions only, as Python's name lookup (LEGB) does.
Before, such a call took the name-only ladder and was split across every same-named definition in its
directory: on pydantic one `Model(b=1)` in a test reached all 965 `class Model` definitions of `tests/`
(517,311 edges from 643 callers). Measured with the pin census, cold, `--no-cache`: pydantic call edges
892,662 → 64,166 (the map's `edges=` 582,130 → 48,178), textual 34,013 → 28,252, django 107,887 → 100,627;
every call site keeps its disposition, and a changed site only loses targets, except where the local
definition had been dropped (pydantic's `test_args`: `foo(1, 2)` now binds the test's own `foo`). Peak
memory falls with the edges (pydantic 153–171 MB → 122–128 MB).

Two or more `def`/`class` statements of the name in that scope (an `if`/`else` pair, a redefinition) are a
split across those only. The rule makes no decision, and the call keeps the earlier answer, when another
binding shares the scope (an assignment, a parameter, an import, a `for`/`with`/`except` target), when a
`global`/`nonlocal` names it, when a lambda parameter or comprehension target of the name holds the call,
when the innermost scope is a class body that binds it, and at module scope under a star import, a
`globals()`/`setattr` write or a conditional def of a builtin's name. A default argument, decorator or
base clause runs in the enclosing scope. An annotation's names are read there too, an approximation: since
Python 3.14 an annotation is evaluated lazily, so it can see a later binding of the name. Python only;
`--for` answers on Python trees can change.
Gate: `test/pyaliascallcheck.sh` section 5.

### Fixed — a Python import inside a function now gives that function its module calls

`def main(): from . import config, runner; runner.run(conf)` left `main` with no edge to `runner.run`: a from-import (or `import a.b as c`) inside a def binds a local, and the resolver read only module-level imports. Such an import now binds the name for calls in that def only, never at module scope, in a sibling def or in a method of a class whose body holds the import. The local binding wins over a module-level binding of the same name, and any other binding of the name in that def (a parameter, an assignment such as `except ImportError: x = None`) withholds the edge. A def-scoped `import a.b as c` also stops leaking into sibling defs, which bound `c.f()` there at the previous build. Measured on the default map's `edges=`: pydantic +9 (11 calls checked, all true), django +4 (3 checked, all true; 9 more such calls, into a package whose namespace the resolver cannot prove, are now declined and counted), home-assistant +25 (7 checked, all true). On home-assistant, `homeassistant/__main__.py` `main` is now a caller of `config.safe_mode_enabled` and `runner.run`. A call in a nested def that reads the enclosing def's import by closure is still not read (a floor).

### Changed — a warm `--quality-delta` no longer re-parses every file, and a repeat `A..B` reuses its base

The error-masking and placeholder rows of `--quality-delta` (swallowed exceptions, empty catch and `if err != nil {}`
bodies, `todo!()`, `NotImplementedError`, TODO-only bodies) were found by re-reading and re-parsing every source file
on every call, warm or cold. They are now found in the parse worker from the tree the ingest already built, stored in
each file's cache record, and read back on a warm call. A warm working-tree `--quality-delta` retires 43 % (envoy),
27 % (cockroach) and 69 % (vscode) fewer instructions (median of five interleaved pairs; cycles fall 41 / 28 / 65 %)
with the same answer bytes. The cache format moves to 51 (each file record gains its construct hits, 9 bytes each), so
an older cache is rebuilt once. Only a `--quality-delta` (or `--quality-baseline`) run finds the hits: any other verb
writes its records "constructs absent" and pays nothing: cold `--deps` and the cold default map stay within 0.2 % of
before. The next `--quality-delta` decodes such a record as usual and parses the file for the hits alone, which costs
about what every warm `--quality-delta` used to (1-2 % fewer instructions), and the rewritten record carries them. A cold
working-tree `--quality-delta` retires 17 / 12 / 18 % fewer instructions than before.

The base side of `--quality-delta=A..B` (its Snapshot for the selected kinds and its C-family macro names) is now
stored by base commit sha in a self-checking blob beside the head-snapshot cache, keyed also by the excludes, the
selected kinds, the file-size cap and the build's producer identity. A repeat `A..B` with the same base archives,
parses and scores only the target: a repeat `HEAD~10..HEAD` retires 80 % (envoy), 70 % (cockroach) and 90 % (vscode)
fewer instructions than before both changes, and its peak live heap falls 21 / 19 / 30 %. `--no-cache` neither reads
nor writes the blob; a corrupt or truncated blob is refused with a stderr line and recomputed. On a hit the base
archive's own per-file ingest warnings are not repeated (they name a per-process temporary path, so they were never
byte-stable).

New gates `test/qdconstructscheck.sh` (carried hits equal re-parsed hits cold, warm and uncached, with a premise count
that fails on zero) and `test/qbasecachecheck.sh` (a hit, a miss on a changed key, `--no-cache`, corrupt and truncated
blobs).

### Changed — quality-delta: a run of calls that shares no callee is an idiom collision, not a copy; range answers say when the files on disk moved on

Duplication rows gain a fifth recognized idiom, `call-sequence`: a body that is only call statements (no return,
declaration, assignment or control flow). Normalized, every such body reads `$I . $I ( … ) ;` repeated, so a
reused two-line helper (`sortUnique`: sort, then erase-unique) gated as a NEW clone of a four-call stream writer
and of a bench wrapper it has nothing in common with. A call-sequence group whose members share no callee or
other identifier (parameter names, `std::` chains and container words aside), sit in different files or scopes,
are under 80 tokens and are not one body with renamed parameters is now reported `sev="minor"` with
`idiom="call-sequence"` instead of gating. A shared callee, one namespace, or a parameter-only rename keeps it
gating. On this repo, tmux and hono the rule demotes no existing clone group; `test/cloneidiomcheck.sh` arm (P)
pins both directions.

`--quality-delta=A..B` now carries `stale_tree="1"` (and a one-line stderr note) when the files on disk are not B's
tree — uncommitted edits, untracked files, or a HEAD whose tree differs from B's (another commit with the same tree is
not stale) — so a green range answer is not read as a
pass for the files on disk. Never gating; `test/qdrefpaircheck.sh` arm (B2).

### Fixed — `--quality-delta`: a file rename git recorded keeps every function's identity, with or without an ack ledger

Moving a whole file with `git mv` no longer reads as new code. Before, git's rename record was read only when the repo had a `.ripwire_quality_acks` ledger (or under `--quality-ack`), so in most repos a moved file healed nothing: functions whose body has an identical twin (which the body-identity match refuses to pair) showed up as new dead-code rows, and a clone group with a moved member gated as new duplication. Now the baseline follows the rename record in every repo: the working-tree form reads only the staged and unstaged renames (the baseline is HEAD's), the `A..B` form reads the range, and a clone group with a member in a renamed file is matched at the member's earlier path. A worsening carried in with the move still reports, and a new copy added beside it still gates. The `renames=` attributes appear on a no-ledger run only when a rename was read, so other runs are byte-identical.

### Changed — the near-clone comparison behind `--quality-delta` and `--clones` runs 64 DP cells per machine word

The Type-3 (gapped) clone pass compares candidate function bodies by the longest common subsequence of their normalized
tokens, and on large repos it was most of a warm `--quality-delta`. That LCS is now computed bit-parallel (Allison-Dix /
Hyyrö: one bit vector over one body, updated once per token of the other, 64 cells per word), and it stops as soon as
a pair can no longer reach the 0.8 similarity the pass keeps. The answer is unchanged: a kept pair gets its exact
length, and only pairs the threshold drops anyway stop early. A warm working-tree `--quality-delta` retires 46 %
(envoy), 82 % (cockroach) and 9 % (vscode) fewer instructions (median of five interleaved pairs, M2; user CPU −42 / −77
/ −6 %), a repeat `A..B` about the same, and a cold working-tree run 18 / 47 / 2 % fewer. `RIPWIRE_LCS_VERIFY=1` re-runs
every comparison with the plain DP and prints the counts (`test/lcsidentitycheck.sh`); on the three repos 289,811 real
pairs compared with no difference.

### Changed — `--quality-delta`: a short clone row over different data stops gating; a repeated decision is named on its complexity row

**Clone rows over different data (QD-IDIOM-ELEMTYPE).** Some clone groups are under 80 tokens, sit in distinct
contexts and were not already demoted as a recognized idiom. Such a group is now reported `sev="minor"`, and no
longer gates, when every pair of members operates on different data. "Different data" means one of two things.
The members share no literal: 0 and 1 are left out, and `true`, `nullptr`, `None` and the like count. Or the members
take the same number of concrete parameters, with a different type at some position. The row says which with
`why="different literals"`, `why="different parameter types"` or `why="different literals or parameter types"`.
A shared literal rules out the literal proof, and a template or generic member or an untyped parameter rules out the
type proof; a group with neither proof keeps gating, as before. A recognized idiom whose members share a domain
value, such as a ladder over the same `Grade::Poor` … with tuned thresholds, a pair sharing a named constant, or a
pair calling the same helper, keeps gating under both proofs. A function passed by value, like `svLess`, does not
count. Two bodies that both pass their literal straight to a call keep gating too, because that is one function with
the literal as a parameter (`rfind( '/' )` beside `rfind( "::" )`, the `afterLast` family).
`--clones` does not read this verdict and is byte-identical.

Measured on ripwire's own history, gating rows fell from 13 to 3 on the 13 acknowledged VA-FORMS rows. The 3 that
still gate do so by design: one is past the 80-token ceiling, and two members share the literal `0x80`. Other ranges:
- 41 to 36 on 40 tmux commits;
- no change on the qd-tangle range, the last 20 merges, the slip commits, textual or 20 other tmux commits;
- 1,863 to 1,327 on a synthetic envoy range that adds two whole subtrees.

The real duplicates still gate (`writeTangleLines`/`writeHexPairLines`, `steer_find`/`JsonNode::get`). Hand-reading
24 envoy demotions found 21 idiom collisions over different data and 3 borderline rows, among them the identical
"all matchers match" loop over two element types. None was a verbatim copy. `test/cloneoperandcheck.sh` pins the
path: three positives, six counted negatives and a guard-off proof.

**A repeated decision (QD-REPEATED-DECISION).** A function may test the same condition twice: the same 6 or more
tokens, verbatim, in an `if`/`while`/`elif` or a `( … ) ?` ternary. Or it may repeat a loop body: 12 or more tokens
identical. Its complexity or tangle row now carries `fix="name the decision once: <condition> is tested at lines A and
B"` or `fix="name the loop once: the loop body at line A repeats at line B"`. This is a facet. It never makes a row,
and it never changes a severity or gating. In Python a keyword counts only when it starts its line, so comprehensions
and conditional expressions are not read as statements. Ruby, Lua, Elixir and shell are not read.

On ripwire's last 20 merges 14 rows gained the fix, among them `chooseInWindow`'s copied pass loop. Three of the 42
distinct fix= rows across the ripwire, tmux and textual ranges re-test a fact that changes in between:
`memguard::overHardLimit()`, `!qsnapGet(…)` and tmux `event_initialized`. For those, deciding once is the wrong advice.
`test/repeateddecisioncheck.sh` pins it with two positives and five counted negatives.

The legend defines `why=` on a clone row and the new fix= text only when a row carries them. The compact dictionary's
`why` entry now also covers the clone row, so its `dictv` moves.

### Added — every pull request runs `--quality-delta` over its whole range (`qd-range` CI job, `scripts/qd_range.sh`)

`--quality-delta` compares a change with its parent, so a regression that merges becomes the baseline of the next comparison and never appears again. A per-commit check also misses a regression made in two steps (two `+1` parameter changes are each a minor row; over the branch the contract went 2 → 4 and gates), and a check run before the last edit passes for a tree it never measured. The design comes from #697 (the quality-drift prompt).

- `scripts/qd_range.sh BASE [HEAD]` runs `--quality-delta=<merge-base>..HEAD`, prints every row as a table (gating, minor, new-symbol), and ends on one verdict line. A `FAIL` line names each gating row and prints the `--quality-ack='<why>' --ack-only=<id>` command that accepts it with a reason in `.ripwire_quality_acks`, the existing ack ledger. Exit 0 = no gating row, 2 = gating rows, 1 = the check could not be made: an unreachable base (a shallow clone), no answer, or a partial answer under memory pressure.
- The new `qd-range` job in `ci.yml` runs the same script on every pull request against its merge ref, and `ci-gate` needs it. It builds the plain `ripwire` target once beside the release shards, so it adds no time to the critical path.
- Replay on this repo's history: the range form is red on `chooseInWindow` (complexity 12 → 16) over #693's range, its merge commit, and the single commit `fb23cb777`. It goes green once that row is acked with a reason. `test/qdrangecheck.sh` covers the script on a fixture repo: the one-commit and two-step shapes, the ack and a worsening past it, clean ranges with their rows counted, a shallow clone, a binary that answers nothing or answers a different range, and the CI wiring.

### Fixed — `--quality-delta`: renaming or moving a function no longer reads as new code

A function renamed together with its callers, or moved to a sibling file, keeps its identity when its body did not change (whitespace and its own name aside). Before, its new name or path made every kind treat it as new code. A rename of one member of an existing clone pair gated as new duplication, and the moved function's complexity, parameters, dead-code or error-masking showed up as new rows. On the seeded rename and move runs (75 placed runs over nine corpora) the false-alarm rows fell from 18 (4 gating) to 0. A body that also changed is still read as new, so a worsening carried in with a rename is still reported, and a genuinely new copy of a clone-pair member still gates. The match is exact and must be unique on both sides. The quality snapshot cache scheme moves to 30, and the baseline sidecar gains `bodyc` records; an older sidecar matches no rename.

### Changed — `--quality-delta`: a clone pair that crossed the bar only because one member shrank stops gating

**Shrink-only clone pairs (QD-SHRINK-PAIR).** A Type-3 pair's similarity is 2·LCS/(|a|+|b|), so it rises when either
member loses tokens the other does not share. Handing a body's sort and `erase( unique )` lines to a helper therefore
made it look more like its neighbour: on one development branch, `cFamilyMacroNames` fell from 135 to 99 tokens, its shared
LCS with `jsExportsOf` fell from 84 to 81, and the pair crossed 0.8. It printed as a gating duplication row and a gating
new-clone-of-reused-helper row about an edit that removed code and copied none.

Such a row is now reported `sev="minor"`, and no longer gates, when all of these hold:
- every member existed at the base;
- some member's body has fewer tokens now, and no member's body was cut to under half its base tokens;
- no pair's shared LCS grew.

The row says why: `why="pair crossed the bar because cFamilyMacroNames shrank 135->99 tok; shared code did not grow
(LCS 84->81)"`. A pair whose LCS grew still gates, even while a member shrank, because code was copied in. A member
cut to under half its body is a rewrite the rule cannot judge (a long base body holds most short ones as a subsequence,
so its base LCS says nothing), and it still gates. A group with
a member the base did not hold still gates, and so does one with an overload under a member's key, more than four
members, or a body the base commit could not be read for. The base bodies are read from git at the base commit for
the files of those rows only: the range form's base, or HEAD for the working-tree form, MCP `quality_delta` and the
`--quality-baseline` dirty-pin check. They are read with the same extraction and tokenizer the clone pass uses.
No snapshot or cache format changes. `--clones` does not read this verdict and is byte-identical.

The legend defines the new `why=` only when a row carries it, and the compact dictionary's `why` entry now covers it,
so its `dictv` moves. `test/shrinkpaircheck.sh` pins the rule with three positives (range, working tree, MCP), a
both-shrank positive, four counted negatives and a guard-off proof.

### Added — `--quality-delta` marks a new or grown list of adjacent same-typed parameters (`similar=`), report-only

A C or C++ function that is new in the change, or whose parameter list grew, and that now holds three or more adjacent parameters of one written type with different names (`g( at, nameAt, nameEnd, fileId, line )`) gets `similar="N"` on its `params` row, N being the longest such run. A call that swaps two of them compiles and runs wrong. A row the `params` kind already reported keeps its severity and gains the attribute; any other function gets a new `params` row with `sev="minor"` (`was=` and `now=` stay parameter counts). `similar=` never gates: the exit status is what it was without it. On a range (`--quality-delta=A..B`), `--quality-kinds=` without `params` drops the rows, as it drops every `params` row. A run of two (`f( task, answer )`, `begin`/`end`) is not reported: on the tidy-681 ref pair (1bbfcebc1..b0f829d69) runs of two were 160 of the 184 rows, so the shortest reported run is three (project decision, 2026-11-18). The scanner reads only the signature text: unnamed parameters, packs, `bool` and iterator types are not counted, and two spellings of one type (an alias beside its target) are two types. A run made by retyping a parameter at the same count is not seen, because the baseline stores parameter counts only. Other languages are not read.

Counting runs of two, on the 83 bugprone-easily-swappable-parameters findings of #681 the scan scored precision 0.97 and recall 0.90; on a hand-labelled sample of the functions clang-tidy does not flag, 0.78. `--for`, the map and `--deps` are unchanged. The full and compact legends define `similar=` when a row carries it.

Versions: the session legend dictionary moves to `dictv=9bdc025eecbce2a5 entries=1168` (the `similar=` reading); docs/COMMANDS.md and the 2026-11-20 showcase capture record the new pair.

### Added — `--quality-delta` reports `tangle`, the thirteenth kind, with a best-since-tag ratchet and an `<improved>` section

A long function whose nesting goes past 3, whose deep regions take a growing share, or whose steering locals (a
primitive set in one step and read by a branch 10 or more statements later) multiply, scores a tangle: T from those
three inputs, S = T x log2(lines / 50), so a function of 50 lines or fewer scores 0 and a long orchestrator of named
steps scores 0 too. The row is report-only (always `sev="minor"`) and carries `why=` (the inputs that rose), `fix=`
(the shape the rise calls for, with lines) and `locals=` (the steering locals); `--metrics` gains `steer=` and
`tangle=`. Short arms of a 4+-arm switch or else-if chain are left out of the deep share, so a flat dispatcher reads
flat. A function above its best since the last tag gets `ratchet="TAG"` (the history is read on the first-parent
line, at most 512 versions; a ref-pair range reads no history and gets no ratchet), and an `<improved>` section (JSON
`"improved"`) lists what the change made better, never as a row and never gating. Measured on 44 hand labels across
ripwire, tmux, textual and envoy: AUC 0.986 for S (0.728 for the cx metric, 0.882 for ccx). The ingest
cache moves to 54 and the warm snapshot to 4 (the definition record carries the steering byte), so both rebuild once.

### Added — `--quality-delta` names a dropped I/O or child status (`defect="unchecked-status"`)

A fifth defect-shape facet reports, as a minor row that never gates, a status the change drops: in C/C++ a
statement-level `pclose`, `rename`, `write`, `system`, `fflush` (not of stdout/stderr), `waitpid` whose status
nothing reads, and `fclose`/`close` of a stream or fd the function wrote (plain, `std::`, `os::` or `rw::os::`); in
Python `subprocess.run` without `check=` whose result is dropped or read only for its output, `subprocess.call` and
`os.system`. A `(void)` cast, `check=` and a cleanup inside a failed write's branch say "decided" and give no row. The
row's `p=` is the dropped call's line and its new `call=` attribute names the call (XML, `--json` and MCP). Replaying
three fix commits backwards gives their rows (3 of 3); a 20-site hand-check on tmux, code-review-graph and this tree
found 20 of 20 drops real and 16 worth a check. Go `_ = f()` and Rust `let _ = f()` stay out, as in error-masking.
The quality snapshot scheme moves to 37 (qd-unhandled-arm, later in the same release, takes it to 38), so an older snapshot cache is rebuilt once; the legend dictionary moves to
`dictv=c40ddf725e4befcb entries=1177` (with the other quality-delta changes in this release).

### Added — `--quality-delta` names a classifier that leaves a value without an outcome (`defect="unhandled-arm"`)

A sixth defect-shape facet reports, as a minor row that never gates, a classifier over a closed set that gives a
value it does not name no outcome: a C/C++ `switch` with no `default:` that decides a value (every arm returns one,
or every arm assigns the same name) over an enum defined in the indexed tree and leaves one of its enumerators out
(count sentinels such as `kFooCount` and aliases are owed no arm); a shell `case` with no `*)` arm that ends its
function with `return`/`echo`/`printf` arms, or whose arms each set one name read after `esac`; a Python if/elif
chain or `match` that ends a value-returning function with no `else`, so an unmatched value returns `None` (an
`Enum` the file defines is checked for coverage). The row's `p=` is the switch's line and its new `why=` attribute
names what is left out (XML, `--json` and MCP). Because the site names the missing enumerators, appending one to an
enum gives a row on every switch it leaves incomplete, even an untouched one. A default/`*)`/`else`, full coverage,
a comment that states the omission, a void dispatcher, an `#if` in the switch or the enum, and generated code give
no row. Rust and TypeScript stay out (the compiler checks `match`; TS has no never-check reading yet). The quality
snapshot scheme moves to 38, so an older snapshot cache is rebuilt once; the legend dictionary moves to
`dictv=c40ddf725e4befcb entries=1177` (with the other quality-delta changes in this release).

### Changed — `defect="vacuous-assert"` reads a test script's exit-status dataflow, not a grep prefilter

The vacuous-assert facet now runs on a C++ port of the exit-status matcher in `test/lib/exitstatus.py`
(`src/shstatus.h`; `test/gateexitcheck.sh` H4 holds the two equal on 9,144 calls). It reports an assertion that
passes on an empty text (an absence `grep`, `[ -z ]`, a `cmp`/`diff`/`=` parity) when the text was read off a run
whose status nothing checks: a capture, a pipe without `pipefail`, a redirected file, a dropped wrapper status, a FAIL
reporter inside `$( )` or an unread `rc=$?`. Every test script is read (the `grep` prefilter is gone). Recall is 8 of
11 on this project's own fix commits (it was 0), with 0 new rows on a forward replay of the same files. The row stays
`sev="minor"`. The quality snapshot scheme moves to 35 (later members of the same release take it to 38).

### Changed — a `--for` tail row no longer repeats the names its file's ranked rows or the `<syms>` block already show

A `<tail>` page row for a file whose symbols the answer already prints as ranked `<d>` rows used to list those same names again in `sym=`, so the row named nothing new. Its `sym=` now skips the names a shown row of that file carries and fills its three slots from the file's next positive-score symbols in the same lens order, each name once (the repeated-name rule the other tail rows already follow). The row count stays the same, and `sym=` never holds more names than before. A file whose positive-score names are all shown prints `p=` only.

The `<syms>` lead block keeps priority over those rows: it reads the answer as if their `sym=` names were not printed, and a name it prints is then cut from them, so the block's leads (with their `file:line` and qualified name) are the ones that survive and no name is printed twice. Both tail legend clauses say so: `sym=` is the file's top symbols minus names a sigs row or the syms block shows.

On the 321 in-sample `--for` calls this names the missing in-file symbol on mf2-pydantic-08 and nfpm-11 without losing a graded item. `test/deeptailcheck.sh` arms (1d) and (1s) pin the refill and the `<syms>` cut, each with a positive twin.

The tail legend clause change moves the session legend dictionary to `dictv=720b939e8b412eb8 entries=1050` (docs/COMMANDS.md and the showcase capture are re-recorded).

### Added — `--for` lists who calls the function that reads a literal

When a `--for` answer prints a `<lit>` block for a setting, environment variable, flag or message, the block now also lists the callers of the functions its rows sit in, as `<lc d= of= n= t= p=>` rows. These are proven call-graph callers in source files. A name-only edge counts only when the name has a single definition. When a reader has one caller, or its caller is a constructor, the block goes one more hop. A constructor hops to the places its class is built, so a message assembled in an exception constructor now reaches the code that throws it. A function with more than 6 callers prints a count and a `--callers=` pointer instead of rows. For a constructor, that count includes the places its class is built, and a second pointer, `class_next=`, lists them. An element holds at most 12 rows. Callers are walked for the first three reader functions only, and `readers_more=` counts the later readers that have callers.

Two more task shapes now get a `<lit>` block. One is a bare kebab option name next to "option", "flag" or "setting" (tmux's `escape-time` option), when it has 1 to 8 quoted source sites. The other is a task of 4 or more words with no "error"/"message" word whose whole text is a string literal at 1 to 3 confirmed string sites (a site in a file the parser could not classify does not count) (`Nest can't resolve dependencies of the`).

Measured on the 321 in-sample `--for` calls (one call each, no cache, against main c2ad05de7): 17 answers change. Four rows become Complete: a pydantic and a nest question (held back from development), and an fzf and a tmux question. That is 6 more credited items, with none lost and Wrong unchanged. Bytes grow by 0.9 % on the held-back development set, 0.7 % on the main development set and 0.4 % or less on the large sets; the 164 everyday calls do not change. The rows come after the ranked answer and are not part of `est_tokens`. Set `RIPWIRE_NO_READER_CALLERS=1` to turn the rows off.

### Fixed — a `legend="ref"` answer keeps every cut, floor and provenance attribute on its root

Under the ref posture (`--legend-have=DICTV` on the CLI, and the MCP stdio default from a session's second reducible answer onward) an answer kept only `task=`, `changed=`, `from=` and `to=` on its root and carried every other root attribute on `<about>`, its last child. That moved facts, not definitions: `capped="1"`, `has_more=`, `next_offset=`, `counts_floor="1"`, every `*_capped=`, the graph gauges, `root=`, `at=`, `route=` and `confidence=` sat after the last row, so a reader that held the rows of a long answer without its tail read a cut list as a complete one. Measured on the previous binary over 110 CLI handshake calls on five repositories (tmux, koa, nushell, terraform, cpython; 103 took the posture): `<about>` was not wholly inside the first 2 KB in 27 answers and not inside 4 KB in 16, and 22 of the 28 ref answers longer than 2 KB had a complete row in that prefix while an active cut or floor lay beyond it. In an eight-call MCP session on tmux a `for` answer put `route=`, `root=` and `confidence=` at byte 16,502 of 16,784.

The root open tag of a ref answer is now the inline answer's, byte for byte, and `<about legend="ref" dict= dictv=/>` is the legend pointer and nothing else. The map header comment (`<!-- files= … shown= … -->`, which the map legend calls data) also stays where the inline answer has it instead of following the rows. The cost is zero bytes: on the gate's fixture every handshake answer has the same length before and after, and the dictionary's core entry that describes `<about>` is 3 bytes shorter. Answers that never took the ref posture (the default, `--legend=full`, `--mcp-legend=inline`) are byte-identical to before. A consumer that read root facts off `<about>` must read them off the root.

Not changed, and reported rather than fixed: `<sigs shown="N" total="N" capped="1">` in a `--for` answer. It is the vocabulary's byte-trim reading (src/pageview.h rule 5: every row survived and was shortened), defined in band by the answer's own `[sigs capped=1 with shown=total: rows shrunk, none dropped]` clause, so it has a different cause from the relocation above. `test/refdisclosurecheck.sh` (D) holds the line that no other element may spell a cut that way.

Gate: `test/refdisclosurecheck.sh` (the invariant under four postures, a non-vacuity arm on a fixture whose answers are cut, eighteen mutation controls that must go red, determinism, and byte-identity of the non-ref postures). `test/legendrefcheck.sh` (D) asserted the old shape and is corrected to assert the new one; `test/legendhavecheck.sh`, `test/pathgapcheck.sh` and `test/mcpincrementalcheck.sh` now read root facts off the root alone.

Versions: the session legend dictionary moves to `dictv=7792c32000c4aa2b entries=1129` (the `<about>` core entry's wording); docs/COMMANDS.md and the 2026-11-13 showcase capture record the new pair.

### Fixed — `--regex` refuses the multi-quantifier family instead of handing it to the engine

Three shapes that both structural screens admitted, and that cost the engine time growing with the *subject*,
are now refused by name, bounded, before any engine sees the pattern:

- `a*a*a*a*a*b` — adjacent unbounded quantifiers at top level, where there is no group for the
  nested-repetition or alternation arms to inspect (measured on libstdc++: 5.4 ms at a 21-byte subject,
  29.5 s at 97 bytes — a doubling every ~6.1 bytes).
- `^(a)*(a)*(a)*(a)*(a)*$` — the same adjacency one level down, where the quantified groups are siblings
  (~degree-4 polynomial: 2.3 ms at 20 bytes, 984 ms at 80).
- `^(ab\w|((.|.){1,3}){1,3}){1,3}$` — an alternation the screen cannot prove disjoint, repeated inside a
  repeat. Its outer `{1,3}` is *bounded*, so the existing alternation arm never fired on the `(.|.)` overlap.
  The lone `(.|.){1,3}` stays admitted: it is cheap at every length, and it is the nesting that enumerates.

**Proportionality** (the review round, measured and adopted): clause 1 no longer refuses any adjacent
intersecting pair — a *same-set* pair (`a*a*`, `.*.*`, `\w+\w+`) refuses, and *three or more* intersecting
atoms in a row refuse as degree-(atoms−1) growth; a cross-set pair (`\s+.*`, `\w+.*`) is admitted. That
split is a policy, not a cost class: every such run is polynomial, not exponential, and on a uniform run a
cross-set pair costs what a same-set pair does (libstdc++, a 320-byte run: `\w+.*b` 133 ms, `a*a*b` 133 ms,
the rewrite `\w.*b` 1.2 ms). A same-set pair always has a one-atom rewrite with the same language; a
cross-set pair is common and costs close to its rewrite on ordinary source lines (measured: sub-millisecond,
and on a 4 KB minified line the rewrite `\w.*TODO` costs 413 ms against `\w+.*TODO`'s 898 ms — the same
order). Nine patterns in a 900-regex
agent sample (1%) were such pairs (`import\s+.*from`, `TODO:\s*.*`, `ERROR.*\d+`, `\w+.*`, `=\s*[^;]+;`,
`^#+.*`); all are re-admitted, and the refusal message now names the pair rewrite — drop one quantifier
(`import\s.*from`), same hits on ordinary source lines. An unquantified group is transparent to the walk
(`(a*)(a*)(a*)(a*)(a*)b`, over 6 s at 80 bytes on libstdc++, now refused), and the walk no longer reads
inside a character class it cannot parse (`[[:alpha:]*.*.*]` is a class, not an adjacency); its skip is
POSIX-aware — a bracket form (`[:alpha:]`, `[.x.]`, `[=x=]`) owns a `]` of its own, and the scan closes the
class only past its terminator. Clause 2 no
longer counts an *optional* (`?`, `{0,1}`) as one of its two repeats — `(https?://(www\.|www2\.)?)?example`
and `(((public|private)\s+)?static\s+)?void` measured sub-0.1 ms and are re-admitted, and neither does an
optional OUTER quantifier (`((www|www2){1,5}\.)?example` is admitted); `((a|aa){2,5}){2,5}b$` keeps its
refusal, because a bounded *repeat* is a repeat, and clause 2's refusal now carries a workaround of its own
(drop one of the two repeats, or make the branches provably disjoint) instead of "bound the outer
quantifier", which its outer already is.

What this means in practice: these patterns used to reach the engine, where libc++ abandons the match
(`error_complexity`) and libstdc++ has no budget at all and simply does not return. The verdict is now one
answer on every platform, exits 1, and says what is wrong and what to write instead — collapse the atoms
(`a*a*a*` is the language of `a*`), separate them with a literal neither can swallow (`a*b*a*b`), bound
all but one (`a{0,3}a*b`), or drop one quantifier of a pair when a pair is all it is.

It does **not** claim the residual closed. Any *admitted* pattern whose cost in the subject is super-linear
is still unbounded on libstdc++, including a *single-level* bounded quantifier over an unproven-disjoint alternation (`(a|aa){1,100}b$`, measured 7.8 ms at a 21-byte subject rising to 99.1 s at 41 B, roughly 7x per 4 bytes), which no disjointness proof can answer — and the review's own two additions to that disclosure:
`.*x.*x.*x.*x.*y` is four disjoint `.*` separated by literals, admitted, and is the same subject-growth
class; `(a*){20}b` (over 6 s at 80 bytes on libstdc++) is named in `docs/LIMITS.md` with it. That is
disclosed in `docs/LIMITS.md`, and it is why the screen refuses rather than guesses: a refusal is a bounded,
named failure; a hang is not.

Gate: `test/regexmultiquantcheck.sh` (88 assertions over 34 patterns). The two preceding families are
asserted undisplaced in the same gate, and `test/regexguardcheck.sh` arm (b2)'s real-engine vehicle moved from
`a*a*a*a*a*b` (now refused at admission, correctly) to `(a*){20}b`, so that arm keeps proving what it was
written to prove. Four evasion/over-refusal classes found in the PR's two review rounds are asserted in the
same gate: clause-1's scope collector now reads a nested group's body at every depth
(`((a*a*a*a*)b)c`, `(?:x(?:a*a*)y`), a lazy `?` suffix after a quantifier is part of the same atom, not a
delimiter that breaks adjacency (`a*?a*?a*?a*?b`), the pair/three threshold holds both directions
(`a*a*?b` refused, `import\s+.*from` admitted, `\w+.*\w+.*\w+` refused), and the optionals under either
quantifier admit (`(https?://(www\.|www2\.)?)?example`, `((www|www2)?\.){1,5}example`).

Fixed by @pt-act.

### Fixed — the prompt-routing hooks no longer time out on every prompt in a cold directory (#594, thanks @WingedGuardian)

The Claude Code and Codex prompt hooks run `ripwire DIR --help-task=…` under the harness's hook timeout (8 s in Claude Code). On a cold index of a mid-sized repository that run took longer, the harness killed it, and a killed run saved no cache, so the next prompt was cold again and every prompt in that directory timed out. Fresh git worktrees hit it first. @WingedGuardian reported it with measurements and three candidate fixes.

New: `--help-task=TASK --deadline-ms=N`. When the answer is ready within N milliseconds, the output and exit code are byte-for-byte what they are without the flag, so a warm or small repository sees no change. When it is not, ripwire prints the usual abstention and exits 0 by the deadline, and a background copy of the same run (forked before any thread starts) finishes the index and writes the cache, so the next prompt is warm. Only one index runs per directory: a second prompt while it runs abstains at once, and a concurrent cold call waits for the lock until its own deadline and then abstains. No call exits 2. Windows runs synchronously, as before.

There is no user notification. The background run writes a per-directory status file (running, then finished with its exit code, time and file count) and, in the routing meter log, `deferred` rows when a call abstains on time and a `warm-done` row when the deferred index finishes. A background run that dies before it finishes is recorded as `warm-crashed` by the next call, and a stale `running` record is ignored. These rows carry `agent="ripwire"` and are never pooled into the prompt-router A/B readout.

Both hooks pass `--deadline-ms=6000` only to a binary whose `--help` lists the flag, so an older binary runs exactly as before. Gate: `test/helptaskdeadlinecheck.sh`.

### Fixed — a routed `--for` answer, CLI and MCP, is held to the page: it no longer prints a full page on top of the verb's rows

A bare `--for` that names a symbol and asks who calls it, where it is used or what breaks is answered by `--callers` / `--uses` / `--impact`, and when the evidence says the verb may be partial (`<route warn="1">`) the first `--for` page rides along. Neither part was held to the page size: the verb printed its own window and the carried page was a full 12,000 B page on top of it. On 89 development questions from 11 open-source repositories the one warned routed answer printed 30,369 bytes where the same question unrouted prints 17,735, and in a live agent session the client stored that answer in a file and showed the agent a 2 KB preview of it.

A routed answer now counts against the page (12,000 B) the way a `--for` page does: every byte from the root on except the legends and the key-body group.

- **The carried page is cut at what the verb's rows left of the page**, by the pager's own rule. Its root says `page="1" pages=N`, `continued=` / `deferred=`, and `next="--for='…' --page-bytes=S:2"`, which is page 2 of the same `--for` answer at that size. A `--for` answer that fits what is left is carried whole, as before.
- **When that would leave the page under 6,000 B, the verb's rows are windowed first** so the page keeps at least 6,000. The verb's root then says `shown= total= has_more="1" next_offset=K` and its `next=` is `--for='…' --offset=K`, the call that already continued a windowed routed answer.
- **A routed answer with no carried page is windowed the same way** when its rows alone are over the page, and so is each `--offset=K` continuation.
- **A question whose verb part cannot be cut to fit even at one row is not routed**: the `--for` answer, byte for byte.

Nothing is dropped: the verb's windows rebuild its unwindowed rows in order, and the carried page with the pages its `next=` names rebuilds `--page-bytes=0`. An answer that already fitted is byte-identical. A spelled `--page-bytes`, the default 12000 included, still never routes: the carried page's `next=` is a page of the `--for` answer because of that. Measured on the same 89 questions (bare default, page 1): 2 questions route. The warned one goes from 30,369 to 20,727 bytes (86 `--uses` rows on page 1 become 32, the carried page is page 1 of 6 at 6,122 B instead of page 1 of 3 at 12,000 B) and still names both gold files; the other already fitted and is byte-identical, as are the 87 unrouted answers. Gate: `test/forroutepagecheck.sh`.

**MCP `for`.** A warned routed MCP answer carries MCP's own `for` bundle as its last child, and it was never held to anything: on the gate's fixtures it printed up to 48,582 bytes. It now counts against the same 12,000 B page, the same way, and what does not fit is one MCP call away and lossless:

- **the verb's rows are windowed** when the page needs the room: the root says `shown= total= has_more="1" next_offset=K`, and `for` with `offset=K` continues them (each window held to the page too);
- **the carried page is MCP's whole `for` bundle when it fits what the verb's rows left**, as before; **otherwise it is MCP's file page of the same ranking, cut to fit**: a `<files>` root with `limit=L offset="0"`, and `has_more="1" next_offset=K` when it is cut — `for` with `limit=L offset=K` continues it. MCP has no byte page of the bundle, and `limit`/`offset` is the paging contract its `for` already answers; the file page names one row per file, not the bundle's signatures;
- **a question whose answer cannot be held is not routed**: MCP's `for` answer, as for any unrouted question.

An MCP answer that already fitted is byte-identical (`test/mcpforroutepagecheck.sh`).

### Fixed — Rust `Drop::drop` no longer reads as dead code, when it is a method of an `impl Drop` block (#494, #500, thanks @zom-2018)

The compiler runs `drop` when a value goes out of scope, and no call in the source names it, so `--quality-delta` reported every `impl Drop` method as a `dead-code` row. A method named `drop` (or `r#drop`) is now exempt when its span lies inside an `impl Drop for T` block of its file and no fn or method encloses it inside that block. The trait is matched by its last path segment, so `impl std::ops::Drop for Q` and `impl<T> Drop for G<T>` count. Still reported: a free `fn drop`, including one in a `mod` or nested in another function; an inherent method named `drop`; a method named `drop` in another trait's declaration or impl; a `drop` nested in another function's body, including one inside a `Drop` method's body; C++ methods named `drop`. Floor: a user-defined trait whose last path segment is `Drop` counts the same as `std::ops::Drop`. A `#[automock]` trait named `Drop` does not count, because it names no implementor. Also exempt: an inherent method named `drop` declared inside a block in the generic arguments of a `Drop` impl header (`impl Drop for W<{ … }>`). A probe on the built binary shows this; no test in the suite covers that shape.

Versions: `kQSnapCacheScheme` 32 -> 33 (the dead set changed for Rust `Drop::drop`; a cached snapshot is recomputed once).

### Fixed — a Rust type or function reached through a `pub use` re-export now proves the call

Two shapes left a Rust call unbound (`declined_calls=`) although the code names its target exactly. First, a type that a module supplies through a glob re-export (`pub use engine_state::*;` in `engine/mod.rs`) named no class, so a parameter written `engine_state: &EngineState` after `use nu_protocol::engine::EngineState;` typed nothing and `engine_state.get_decl(id)` stayed open between every `get_decl` in the tree. The module walk now follows the globs at a module's level: one class is named when every glob that can supply the name agrees on it. The walk takes at most four re-export hops and asks each module once, so when a chain of globs reaches a module at that limit, a shorter glob path to the same module is not walked again and the name can stay unbound. Two same-named types behind two globs still name nothing, and neither does an in-tree glob beside a glob the walk cannot place (an outside crate may supply the name unseen). Second, a bare call whose name a `use` binds (`use nu_engine::redirect_env;` over `pub use eval::{redirect_env};` in `lib.rs`) was declined when a second free function of that name sat elsewhere in the same crate. Such a call now binds the one free function its `use` reaches through the re-exports, and a `use` that leads outside the tree, nowhere or two ways decides nothing, as before.

Measured on nushell (main `5139f7840` against this change, `--pin-census` dispositions over all 153 556 calls): bound 50 116 → 53 459, declined 47 545 → 44 211. `--callers` of `EngineState::get_decl` lists 53 callers with 20 declined sites (was 5 and 116), of `nu_engine::eval_block` 12 with 8 (was 2 and 19; the 8 are calls through a local closure of that name), of `redirect_env` 10 with 0 (was 3 and 7). On axum 21 calls moved from declined to bound and `TestClient::get` reads 119 proven callers where all 174 were `via="name"`. 20 changed edges sampled across both repositories were opened at the call site: 20 correct. 133 edges on nushell changed target; the ones opened had pointed at a same-named method or a private namesake before. What it does NOT mean: a glob of an enum's variants or of an outside crate is not followed, a `use … as` alias of a function is not read, and a call qualified by a crate path (`nu_engine::eval_block(..)`) resolves as before. New arm (RX) in `test/receiverevidencecheck.sh`.

### Fixed — Rust call resolution re-read every glob `use` for every call

The check that keeps an in-tree namesake by name when an outside glob (`use crossterm::style::*;`) may supply a bare Rust call was asked once per call and per in-tree candidate, and each ask re-read the caller file's `use` rows and re-ran the module-path walk for every glob in force. It now reads a file's globs once and answers a call once for all its candidates. On nushell (2,208 files): 2,024,900 asks now compute 10,343 answers; `use` records read fall from 114,460,236 to 206,024 and glob verdicts from 2,030,736 to 1,197. Cold map wall fell from about 1.6 s to 0.6 s and the first warm run from about 1.3 s to 0.36 s (indicative: a shared, loaded machine, five interleaved runs). Output is byte-identical: the full map, the per-call-site resolution census and a `--for` answer match the previous build on nushell, terraform and three Rust trees.

`RIPWIRE_STATS=1` prints the work as `[mem] rust_glob asks= answers= reads= verdicts=`; `test/rustglobscalecheck.sh` gates its growth on a generated crate.

### Fixed — Rust: a call written inside a macro's arguments is a call of the enclosing function

`--callers`, `--callees`, `--uses`, `--impact` and every answer built on the call graph now see the calls inside `assert_eq!(f(), 1)`, `format!("{}", g())`, `vec![h()]` and a user macro's arguments. Before, the Rust grammar's opaque token tree hid them: a function whose body is one macro had no callees, and a test reached nothing through its asserts. Measured on three repositories against the previous build, call edges rose 4,885 to 5,158 on axum, 52,405 to 58,051 on nushell and 288,843 to 306,195 on zed, with the symbol count unchanged on each.

A macro's arguments are re-read only when they parse, as written, as one clean Rust expression or block; a `=>` arm body and a `{ … }` group inside other tokens are tried the same way. A `macro_rules!` definition, `quote!`, `stringify!`, `cfg!` and the pattern argument of `matches!` are never read. A call found this way is resolved like any other: its row can be proven, declined or `via="name"`. This does not type a receiver that the macro itself binds, so a method call on one stays a by-name row. A cold index of Rust code costs more CPU (about 2 % on axum, 3.5 % on zed, 10 % on nushell, median of interleaved runs); a warm index is unchanged. Old cache records are rebuilt once (`kParserVer`).

### Fixed — a Rust macro's matcher words are no longer read as calls at its invocation

The re-read of a Rust macro invocation's arguments parsed `wrap!( matcher_fn( 3 ), drop )` as a tuple and
reported `matcher_fn` as a call, so `--callers=matcher_fn` listed the invoking function, although the word is a literal token
of `wrap`'s `macro_rules!` matcher (`( matcher_fn ( $x:expr ), $f:ident ) => …`) and nothing calls it. When the invoked macro is
a `macro_rules!` the same file defines, a bare call whose name one of its matchers spells as a literal word before a `( … )`
group is no longer kept; the expression the matcher binds (`$x:expr`) is still read. A macro defined in another file is not
consulted: the re-read is a per-file pass. Parser tag 338 (rich 339) invalidates the old extraction cache; kCacheVersion is
unchanged. `rustmacrocallcheck` arm [N] matcher_fn goes green and a new arm [K1] pins the kept `$x:expr` call.

### Fixed — a Rust macro invoked by a path or a `use … as` alias now reaches its in-tree `macro_rules!`

`crate::__define_thing!(..)`, `axum_core::__define_rejection! { .. }`, a transcriber's `$crate::__log_rejection!(..)` and `define_rejection! { .. }` through `use axum_core::__define_rejection as define_rejection;` had no edge and no use site: only a bare `name!` was read. Now a path invocation is a macro site named by its last segment, and it binds only the macro its written path proves (this crate, another crate of the tree, `$crate` read as the defining crate); a `use … as` alias is renamed to the item it imports and carries that path. An outside crate's path (`serde_json::json!`, `log::info!`, `use serde_json::json as sj; sj!`) never binds an in-tree namesake, whatever its export. Inside a `macro_rules!` body only the `$crate::…::name!` spelling is read (a lexical scan); a bare `name!` there stays a floor. Measured on the default map's `edges=`: axum +43, nushell +22, zed +262, mdbook +0; 30 of 30 sampled new caller rows checked by hand are true (axum 10, nushell 10, zed 10). `--uses=__define_rejection` on axum now lists the file-scope `define_rejection! { .. }` blocks. Found in a pre-release cross-check. Caches rebuild once (parser version bump).

### Fixed — a Rust module re-exported by a `use`, then globbed, now supplies its items

axum-extra's tests write `use crate::test_helpers::*;`, and `crate::test_helpers` is not a module of axum-extra but `pub(crate) use axum::test_helpers;` in its `lib.rs`. The module walk did not follow that alias, so the glob was read as one that may bring any name in unseen: `let client = TestClient::new(app);` typed nothing and `client.get(..)` was declined or matched by name alone. A path segment that names no module of the layout is now followed through the one `use` that binds it at that module's own level, across crates, in one crate and through a chain of aliases (a cycle stops at the depth cap and names nothing). Every path that resolved before resolves exactly as before. What it does NOT mean: a module that only a glob brings in is not followed, an alias of an outside crate's module still names nothing in the tree, two globs supplying one name still decide nothing, and whether an item is `pub` is still not read.

Measured with `--pin-census` against the re-export change it builds on: axum bound 4 144 → 4 157 and declined 1 577 → 1 564 of 13 348 calls (29 rows changed, 13 newly bound and 16 name-only rows now proven with the same target, all 29 opened at the call: correct); nushell and zed byte-identical. `--callers` of axum's `TestClient::get` has 66 declined sites where it had 79. New arm (RM) in `test/receiverevidencecheck.sh`.

### Fixed — Rust builder chains resolve each hop through the callee's declared `-> Self` / return type

A Rust method call whose receiver is another call (`Router::new().route(..).layer(..)`, `T::try_new()?.f()`, `x.build().unwrap().run()`, `fetch().await.report()`) used to decline or bind by name, because only a `let` binding of a call result was typed. Each hop is now typed by walking the chain from its root (a `T::f()` path call, or a typed local, field or `self`) through the ONE declared return type of each callee: a written `Self` is the impl's own type, `?` must match the `Result`/`Option` layers it strips, `.unwrap()`/`.expect()` strip one layer, and `.await` needs an `async fn` or an in-tree `impl IntoFuture` / `impl Future` with one `type Output`. `impl Trait`, `Box<dyn Trait>`, a trait object's `Self`, and a hop whose receiver is still split across same-named methods stay declined. On axum, `--callers` on `Router::route` went from 17 callers (505 declined) to 273 (110 declined), and the repo's declined calls fell from 1598 to 912. Gate arms: `callresult/rust7` in `test/receiverevidencecheck.sh`.

### Fixed — Rust `#[test]` functions no longer read as dead code (#493, #499, thanks @zom-2018)

A `#[test]` or `#[tokio::test]` function is run by the test harness, not called by name, so the call graph has no caller for it. `--quality-delta` reported every new test as a `dead-code` row. Those functions are now exempt the way `TEST` and `TEST_CASE` already are, and they count toward `register-macro-excluded=`. An attribute that only looks like the test attribute (`#[testing]`, `#[tested]`, a `#[test]` inside a comment) does not exempt the function below it, and an ordinary uncalled function is still reported. A trailing `//` comment after the test attribute (`#[test] // case`) does not hide the attribute either. `#[tokio::test(...)]` with an argument list, which the ingest's own test-scope rule does not read, is exempt now too. A `#[test]` written after code on the same line (`const A: u32 = 1; #[test]`) still applies to the next item, so that function is exempt as a test, but `register-macro-excluded=` does not count it. Every attribute on a line is read, so `#[tokio::test(flavor = "current_thread")] #[allow(unused)]` exempts the function below it, and a `#[` inside a string is text, so `#[doc = "#[tokio::test(x)]"]` exempts nothing. A misspelled `register_macros=` name is still reported as inert in a tree that holds Rust tests (thanks CodeRabbit, review of #668). The `--quality-delta` legend states the Rust case only when the excluded set holds a Rust test.

Versions: `kQSnapCacheScheme` 31 -> 32 (the dead set changed for Rust tests; a cached snapshot is recomputed once), and 33 -> 34 for the per-attribute reading. The session legend dictionary moves to `dictv=041b5eb83fe6e787 entries=1123`.

### Fixed — a call written inside a Rust `macro_rules!` transcriber is a call of that macro

`--callers`, `--impact` and the call graph now see a function or method called only inside a `macro_rules!` body: axum's `Route::oneshot_inner_owned` is called twice inside the fn-local `call!` macro of `MethodRouter::call_with_state`, and `--callers` missed that file. Each rule's transcriber (the right of `=>`) is scanned the way a C macro body already is, a lexical floor: `name(`, `.name(`, `a::name(` and `$crate::a::name(` become call references of the macro, so the macro row is listed and the graph connects through it. A metavariable (`$f(`), a keyword, a `fn name(` definition, a turbofish path and anything in a string or comment are not read; the matcher is never scanned. On axum the graph gains 191 edges (4,885 to 5,076), `ambiguous=` rises 442 to 487 and `unresolved=` 643 to 669. Caches rebuild once (`kParserVer` 317, one number with the C parameter-slot fix). Gate: `test/rustmacrocallcheck.sh`.

### Fixed — a Rust call written `<T as Trait>::m( .. )` names T's impl, not every `m`

A call through a bracketed type (`<Where as Command>::run( &Where, .. )`, `<Where>::helper( .. )`) left the call's qualifier empty, so it bound by name to every same-named method in reach, all via=name (nushell's `filter` command listed 55 `run` impls under one call). The qualifier is now the type the brackets name, held to that type's members as `Where::run( .. )` is: one in-tree type binds its impl, two same-named types split, and a type the tree does not define (`<String as Clone>::clone`) declines the call. A written type that names no one type — a type parameter (`<T as Command>::run`), `Self` of a blanket impl, `dyn Shape` — qualifies by the trait, and a trait-qualified call that stays hedged now keeps only that trait's implementors (an inherent `Runner::run` beside them is no candidate).

### Fixed — a Rust call bound by a `use` of an outside crate no longer binds an in-tree namesake

`use crossterm::style::Print; Print( s )` bound, with no hedge, to an in-tree `trait Print` of another workspace crate; `use std::cmp::max; max( a, b )` bound to an in-tree `fn max`. A bare call whose name every `use` in force leads provably out of the tree (std, a registry crate, an in-tree re-export of one) is now counted `external=` and draws no edge. A Rust call site never binds a trait (a call names a function, a tuple struct or a tuple variant). A bare call that only an outside glob (`use crossterm::style::*;`) may supply keeps an in-tree namesake the file's own `use`s do not reach as a `via="name"` row instead of an unhedged one. Measured on nushell: 72 fewer edges, 105 more `external=`; every changed edge sampled was a std, `fancy_regex`, `ndarray`, `polars` or `bracoxide` item.

What it does not change: a `use` that reaches an in-tree item (`use crate::ui::Print`, `use a::Print` of a workspace crate) binds as before, and a file with an in-tree glob beside an outside one answers as before.

### Changed — a `--for` sentence gets the callers, path and connect blocks its bare names get

A task written as a sentence lost the subject blocks that the same symbols get in a short key. "`Route::new` gains an extra required argument" printed `<callers by="subject">`; the full question about the same function printed none. The same happened to "path from A to B" asked as "trace the exact call chain from `A` to `B`", and to "common caller of A and B" asked as "which function calls both `A` and `B`". Agents write sentences, so they met the weaker answer.

- A sentence that puts ONE function in backticks and asks what calls or depends on it now gets `<callers by="subject">`, however long the sentence is and whatever other identifier it mentions in passing. A call's argument list (`` `f(title)` ``) and a Go receiver (`` `(*pkg.T).M` ``) read as the name. The rule for sentences without backticks is unchanged.
- `[call] chain from A to B` and `A reach(es) B` run the path verb, and `calls both A and B` runs the connect verb, as `path from` and `common callers of` already did. Each slot still needs a code-like name, so "a chain from start to finish" reads nothing.
- When a sentence that spells code asks for callers or a path and the answer still carries no such block, the answer ends with one `<reask next="--callers=X"/>` (or `--path=A,B`, `--connect=A,B`). That is the bare call that answers the question. The orient skill says the same.

Everything is additive: the answer before the new block is byte-identical. `test/sentencesubjectcheck.sh` pins each form, its negatives (no cue, two functions, the callee sense, a negated cue, the words with no code) and the re-ask.

Found by a pre-release review of residual misses and precision (2026-11-12), which measured the dropped blocks on 29 in-sample rows.

### Fixed — the showcase capture can be regenerated on a merge-heavy tip

The capture generator refused to write the whole 270-command document when one case's `--since` window could not be found. On an integration tip that has merged `main`, no window exists: measured on one such integration tip, the available change windows touch **1** `src/` file (`HEAD~2`..`HEAD~4`) or **53** (`HEAD~5` and every anchor beyond it, including the merge's own parents), while the `--in=DIR` case needs 4..22 — the merge of `main` contributes 53 files by itself, so the cliff is one commit wide and no anchor search can cross it.

- The window was not the problem. In the wide window the tool's answer is complete — the scoped `<recent scope="src">` page carries `capped="1" has_more="1" next_offset= next=`, and the `<symbols stubbed=>` stub follows it — and only the capture's own 30-display-line cut hid it, behind a global `<recent>` block the tool caps at 40 rows.
- So the display cut now keeps the trailing ELEMENT a caption promises, exactly as it already keeps a trailing LEGEND: `keep_from_start` beside `trailing_legend_start` in `test/showcase_capture.py`, with `fmt_block`/`publish_block` taking the element to keep. Only lines past the ordinary 30-line window qualify, so a block that already shows its element renders byte-identically and no capture that regenerated before moves.
- `chooseInWindow` and its eight named steps are unchanged: with the cut keeping the scoped page, its first pass finds a window on its own (`--in= case window derived as HEAD~6 (margin HEAD~5 holds)`).
- Disclosed on both sides: the capture's "How to read the blocks" preamble says one block keeps a trailing element and that the elided lines there are the MIDDLE of the preceding global block, and the case's own caption says so when the kept tail was needed — measured per run by re-rendering the same window with the plain cut.

`test/showcasecapturecheck.sh` arm (J) drives the nine window functions with fakes and throwaway git repos; all 21 arms are unaffected, because none of them changed.

A second defect the refusal had been hiding, found once the capture could be regenerated at all: the display re-wrap recognised a long line as XML only when it STARTED with a tag seam, so the line that CLOSES an answer whose last payload is a CDATA body (`}]]></b></fold><tail …><!-- legend --></ctx>`, beginning with the body's own `}`) was never re-wrapped. The whole tail of an answer-first `--for` document — its trailing legend included — stayed one 300-byte-truncated display line, and `trailing_legend_start` had nothing it could keep. Measured on this repo's own `--for="tree-sitter parse of a source file" --adaptive`: 91 display lines with the tail glued into the last one, against 164 once the seam test looks inside the line, where the final six ARE the trailing legend. The seam test now accepts any long line that CONTAINS a seam (the JSON branch is tested first), which is how the `[adaptive: kept N of N]` clause that case's caption names reaches the page again.

### Changed — seven cut listings spell their count `shown_<noun>=` and carry `<noun>_capped`

`dc_shown`, `levels_shown`, `transitive_shown`, `implementors_shown`, `alts_shown`, `cells_shown` and `d2_shown` were spelled noun-first, so a reader (or `truncvocabcheck`, which reads `shown_` prefixes) scanning for a capped bit on those cuts found none. They are now `shown_dc=`, `shown_levels=`, `shown_transitive=`, `shown_implementors=`, `shown_alts=`, `shown_cells=` and `shown_d2=`, the spelling `src/pageview.h` rule 1 already states, each beside its `<noun>_capped` bit.

- The four cut-only listings (`dc`, `transitive`, `implementors`, `alts`) add `<noun>_capped="1"` on a cut answer and nothing otherwise. `shown_levels=` (every `--zoom`) and `shown_d2=` (every answer with a second hop) print their bit `0|1` always. `cells_capped` already existed.
- Cost: the rename is length-neutral; the bit is about 13 B per cut answer, 15 B on every `--zoom` and about 13 B on an answer with a `d2` row. JSON `dc_shown` is renamed with its XML twin; `sigs_shown`/`sigs_total`/`sigs_next` are a separate surface and unchanged.
- `test/truncvocabcheck.sh` arm (I) fails on any noun-first `_shown`, on a cut answer missing the bit, total or next, and on a dictionary row that does not spell them (read from `--legend-dict`, never the generic `X_capped=` gloss). It is exercised on one real cut answer per noun and was shown red on binaries with a row removed and with a row's companion removed.

### Changed — a `--for` answer prints deep same-file sibling rows as tail pointers

A ranked `<sigs>` `<d>` row whose file a higher `<d>` row already shows, ranked past the 10th `<d>` row (so after the first 10 answer rows), is now printed in its place as a tail pointer `<t p="FILE" sym="NAME" r="RANK"/>` (its ranker order kept): still on screen, no longer an answer row. On the graded sets these rows are where most picked decoys sat (a same-file neighbour of the right row, deep in the list, beside a right item already printed). The first 10 answer rows are never touched, so nothing moves up into them.

A row stays a row when it carries `mem=` (a type with its member list), when it is a `<c>` callee under a `<h>` hop row, when it is `Owner.member` / `Owner::member` with its `Owner` row among the four `<d>` rows above, when the index holds a call path of at most two proven edges (no name-only binding, no link) between it and one of the first three resolved answer rows or a row the task names (an identifier-syntax word of the task: a `who calls X` task keeps X's proven callers), when a kept row's `same_as=` names it, when it carries a `--note-add` note (the pointer would drop the note), or when it carries `slot_by=` / `slot_fields=` (its function-valued slot facts). A short legend comment rides before the first pointer. A token budget leaves the answer as shaped, and `est_tokens=` is re-priced over the rewritten bytes (up when the legend and pointers outweigh the short rows they replace). CLI `--for` and MCP `for` share the one renderer; `RIPWIRE_NO_SIBLING_DEMOTE=1` turns it off.

The rule and its first three guards come from the picked-census and SIBLING-DEMOTE guard studies; the call-path guard comes from ROW-FEATURES-2. `test/forsiblingdemotecheck.sh` pins every condition and guard, each with a twin.

### Changed — a caller row's `sites_at=` prints a call site in the row's own file as a bare line

`--callers`, `--safe-delete`, the `--for` caller hop, `--format=columnar`, `--json` and MCP `calledBy` rows list each caller's call sites in `sites_at=`. Every site used to be a full `file:line` token, and the file was the one already printed in the row's `p=`: `p="c.go:4" sites_at="c.go:5 c.go:6"`. A site whose file equals the row's `p=` file is now the bare line, `p="c.go:4" sites_at="5 6"`; a site in any other file is still the full `file:line` token, so a row can hold both. The rule is a string comparison made when the row is printed, not an assumption about the index. `sites_total=` and the meaning of an absent `sites_at=` (no call there is spelled like the called name) are unchanged, and `p=` is still where the caller is defined.

Measured against the previous binary, legend included: tmux `--callers=args_get` (64 rows) 8,295 B to 5,985 B (-27.8%), its `--safe-delete` 6,102 B to 4,540 B, its columnar form 7,308 B to 5,010 B, its `--json` 8,336 B to 6,016 B. Before the change `sites_at=` was 28.5% of the bytes of 30 tmux `--callers` answers, and 1,619 of 1,619 site tokens named the row's own file. The legend reading grew 10 B (`as file:line` became `as [file:]line` with `p=` named as the default file), so an answer with one caller, one site and a four-character path is 6 B larger than before; the smallest answer that comes out ahead holds about 10 B of repeated path. Because rows are shorter, more `--callers` answers fit the 16,000 B band that serves a caller list whole instead of paging it at 40 rows.

A reader that split a `sites_at=` token on `:` to get a file must now take the file from `p=` when the token is all digits. What it does NOT mean: a bare line is not proof the call binds to this definition, exactly as before, and the form is not a delta against `p=`'s line (a site can sit above its caller's definition line). The samples in `docs/COMMANDS.md` are lifted from an earlier capture and still show the old spelling until the next capture is recorded.

### Changed — a code question's `--for` tail counts non-code path-only rows instead of listing them

On a code question the tail's widened rows (past the first 40 code rows, path only) of doc, config, script, test-data and other files are no longer listed: the tail says how many it folded per class (`folded="doc=40,config=20"`, JSON `"folded"` with `"folded_why"`), `capped="1"`, and `next=` pages from the first folded row, so every folded file is one call away. Code rows and test code (a code file under a test path, a shell test included) are never folded; a task that names test data, config or scripts keeps that class; a task that adds a new X (the reading `<exemplar_family>` uses) keeps its doc and config rows, where a new member is registered in a manifest, an API golden or a doc page; and a docs question folds nothing. `RIPWIRE_NO_TAIL_FOLD=1` lists every row as before. The MCP `for` tool folds the same way, and its `folded=` clause is a session legend-dictionary entry, sent once per session. New gate `test/fortailfoldcheck.sh`.

### Changed — repeated `<d>` text and tail names print once

A `--for` `<d>` row whose doc and signature text (40 bytes or more) repeats an earlier row's keeps all of its attributes and prints `same_as="<n of that row>"` instead of the text (a run of constants or overloads with one shared comment), with a present-only legend clause; a row whose `n=` an earlier row of other text also carries (an overload, a same-named function in another file) keeps its text, so `same_as=` names one row. The MCP `for` tool folds the same way, and the clause is a session legend-dictionary entry. A tail row's `sym=` no longer repeats a name it already lists.

### Changed — `--for` legends define only what the answer carries

The `--for` legend clauses for `d layer=`, `iface implementors=`, `field name= type= owner= rel=` and the fold's `slice members= of=` were decided from the ranked set before the rows were rendered, so most answers carried them with no such attribute anywhere in the document. They are now checked against the final rows and dropped when nothing carries them; the `<syms>` legend's `test=1` and `files= head=` readings ride only on a block that prints them. Every attribute an answer emits is still defined in that answer; a section streamed without buffering keeps its clause. The task blocks after the answer do the same for their row clauses: `<lit>` `body=`, `longer=` and `try=`; the short-key ladder's rungs, `held=lit` and `floor=1`; `<reexports>` `glob=`, `cands=`, `ns=`, `q=`, `q_by=`, `q_unmatched=` and `as_skipped=`; `<dotted_strings>` `sink=`, `loader=` and `tmpl=`; `<doc_body>` `held="budget"`; and `<exemplar_family>` `oversized=`/`unread=`.

### Changed — skills: short SKILL.md bodies, the rest moved verbatim to on-demand reference files

Each `SKILL.md` body now holds its skill's core recipe and points at reference files beside it (46 flat `*.md` files) for everything else; no line was lost in the move except two stale router statements corrected in passing (quality-delta covers 12 kinds, not 10, and exit 2 means pre-existing code got worse). SKILL.md bytes: total 261,872 to 52,931 B, median 9,478 to 3,072 B, max 41,668 to 3,787 B (router 4,544 B). Frequency-weighted bytes per invocation fall 79–86 % under all four weightings measured (telemetry 26,254 to 3,553 B; the raters' measured common path 15,488 to 3,273 B). The skill listing (name and description, paid every session) is unchanged. Following check: blind raters given only the skill text scored 32 of 33 pre-registered tasks with both the old and the new bodies, opening a reference file on 1 of 33; this shows no loss, not a gain, and real end-to-end session tokens were not measured. Bytes are counted, tokens estimated at bytes/4. Commit `e76156597`.

### Fixed — `--for --token-budget=N` no longer serves a whole `<lego>`/`<compose>` out of the bytes its trailing sections need

Under a soft target the two sections ride whole when they fit what the rows at the cut left. The `<tail>` shell and the compact route's first `<hops>` row ship however little is left, and the rows at the cut never give way, so a whole section that spent those bytes served the answer past the target (68-77 B past the rows' room on this repo's `src/` at `--token-budget=3000`-`3600`). The whole-section test now reserves both floors; when they do not fit, the sections collapse to their counted stubs. The rows served are unchanged. `test/forsoftbudgetcheck.sh` gains the (ST-L) arm.

### Fixed — two source comments still called the multi-quantifier family admitted

`src/arch.h:153` and `src/search.h:1215` described the multi-quantifier family as one the structural screen
admits — "the multi-quantifier residual `a*a*a*a*a*b`, which the screen admits by construction" and "the
structural screen ADMITS". Since #484 landed (#688), it does not: `--regex='a*a*a*a*a*b'` is refused at
byte 2, by name, before any engine sees it. Both comments named a family member that is refused as if the
gap were still open, on the same lines that explain what `RegexVerdict::Exhausted` is for.

The paragraph still needs a real example of an admitted pattern whose cost in the subject is super-linear,
so it takes `(a|aa){1,100}b$` — measured ADMITTED on the #688 binary, and the shape `docs/LIMITS.md`
already names for exactly this residual ("a bounded outer over a branch that repeats itself only through
the outer quantifier, so no clause fires"). The family is recorded as refused since #484, beside the
note the same sentence already carries for the overlapping-alternation shape.

`docs/LIMITS.md` and `docs/limits_build.py` were regenerated in #688 and already say the screen now refuses
these shapes, so this is the residue of that regeneration: generated prose was updated and the two
hand-written comments were not, because no generator owns them and no gate reads a comment for truth. The
two other pre-existing mentions in `test/regexguardcheck.sh` are already correct — both say the spec closes
the residual and that the real-engine leg moved to `(a*){20}b` for that reason.

Comment-only: no code, no behaviour, no gate, no version. `git apply --check` on `385ebd0bb` and
`clang++ -std=c++23 -fsyntax-only src/main.cpp` (the largest TU, which includes both headers) both rc=0.

### Added — routing for Claude Code subagents: a paste-ready brief block, a SubagentStart note, and an opt-in SubagentStart primer

No ripwire routing reached a subagent. SessionStart does not fire for one, the prompt router runs on the parent side,
the PreToolUse advice that does fire inside subagents was retired on 2026-09-02, and Claude Code's built-in Explore and
Plan subagents do not load CLAUDE.md, so the use-when block pasted there never reaches the agent that searches the
codebase. In the 83 subagents of one measured multi-agent session, none received any hook output, and one had a ripwire
navigation call among its first five tool calls; the generic guidance (CLAUDE.md, MCP instructions, deferred tools) was
present and not acted on. An observational study of stored sessions also shows that what a subagent acts on is its brief:
ripwire was the first source action in 5% of implementer sessions whose brief said nothing (n=369), in 34-39% of those
whose brief carried the routing (n=38, n=66), and in 6% (13 of 215) of those that had the protocol in CLAUDE.md and a
silent brief. No token saving is shown by any of it.

- **The brief block.** `ripwire wrap claude`: the paste block's parallel-agents line now ends with a three-moment block
  for the coordinating agent to copy into every subagent brief that reads source: `--for` before reading source;
  `--expand`, `--callers` or `--impact` before the first edit; commit, then `--quality-delta=BASE..HEAD` and `--test-gate`
  before reporting done. The block is 320 B. The paste block stays 20 lines and grows from 3,085 B to 3,485 B. It is a
  column of the agent table (`AgentTarget::subagentBrief`), set for Claude Code only; no other agent's recipe changes.
  `skills/ripwire-orient/subagent-brief.md` carries the same block, byte for byte, and the router's fan-out moment
  points to it.
- **The SubagentStart note.** `skills/install.sh --hook` (Claude) also registers `hooks/ripwire-nudge.sh --subagent-start`
  on `SubagentStart`. It adds a 348 B factual note (which call ranks files for a task, which prints one symbol, which names
  the tests) to each new Explore or Plan subagent. Every other subagent type loads CLAUDE.md and gets nothing.
  `RIPWIRE_SUBAGENT_ROUTE=0` turns it off and `=all` sends it to every type. It is silent without ripwire or jq on PATH and
  outside a git work tree. It does not follow the meter's arm: the subagents of a control-arm session get it too (the
  SessionStart primer's control-arm silence is unchanged). It writes no row and no file unless `RIPWIRE_SUBAGENT_ROUTE_LOG`
  names one. A machine that ran `--hook` before gains the entry on a re-run; a second run does not add a second entry. This
  note is ambient context, the kind the study above measured at 6%: a floor for the two agent types that get nothing today,
  not the lever. Whether Claude Code delivers it into the subagent's own context has not been run live.
  `ripwire --doctor --agent=claude` has a `claude-subagent-route` row (`installed`, `refs`, `events_ok`, `exec`, `jq`).
  Absent is `ok="1" installed="0"`. `claude-hooks` still counts its two nudge entries; the SubagentStart entry is not a third.
- **The opt-in primer.** `skills/install.sh --hook-subagent-primer` registers `hooks/ripwire-subagent-primer.sh` on
  `SubagentStart`. It adds ~660 B to each new subagent's context. It says to orient first with `ripwire <dir> --for="…"`.
  After the last edit and before reporting, it says to commit, run `--quality-delta=BASE..HEAD --legend=compact` and then
  `--test-gate --legend=compact`, and run the gates that names. A committed range catches a regression made in two steps.
  It cannot block a subagent. It is silent outside a git work tree or without ripwire. `RIPWIRE_SUBAGENT_PRIMER=0` turns
  it off, and `=auto` randomizes per subagent. One row per subagent start goes to `~/.ripwire/subagent_primer.jsonl` (ids
  and arm, never text), and `RIPWIRE_SUBAGENT_METER=0` stops it. The plain `--hook` does not install this hook. With both
  hooks registered, an Explore or Plan subagent receives both texts. `docs/EVALS.md` pre-registers the live A/B: plain
  brief, hook, or brief lines; 16 tasks × 3 arms, paired by task, with keep, move and remove bands. It has not been run.
- **A probe nothing installs.** `hooks/ripwire-nudge.sh --agent-brief` is a PreToolUse hook for the Agent/Task tool that
  returns `updatedInput` with the same block appended to the spawn prompt. Whether Claude Code applies `updatedInput` to an
  Agent call is not documented and has not been run live.

Gates: `test/subagentroutecheck.sh`, `test/subagentprimercheck.sh`.

### Changed — a `--for` tail row now also names up to two of its file's symbols that share the task's words (`tsym=`)

A tail row's `sym=` names its file's top three symbols by lens rank. When the symbol a question wants shares the task's words only through a stem (`restoration` and `restorer`), the lens never scores it, so the tail listed its file and named other symbols in it. Each code tail row that prints `sym=` can now carry `tsym=`, after `sym=`: up to two more of that file's symbols whose names share a task word (identifier subtokens, a light stem, and a stop list of question words such as "which", "function" and "file"), best match first, then the most central by PageRank. A name is added only on distinctive evidence: at most three of the file's symbols share a task word (more, and the word is the file's topic, so a pick among them would be a guess), and the name together with the file's path carries at least two different task words (one generic word such as "plan" or "create" is not enough). Without that rule the first cut added about 14,500 names to the 321 measured answers (+5.4 % bytes) and three of them were names the graders list as wrong answers. `sym=` is byte for byte what it was. Doc rows, the `p=`-only rows, the head and the `<syms>` block are unchanged: `<syms>` reads the answer as if `tsym=` were not there, and a name it prints is cut from `tsym=`. A task whose words no unprinted name shares leaves the answer byte for byte as before. A present-only legend clause defines `tsym=` in the full, compact and MCP dialects; the JSON tail carries `"tsym"` and `"tsym_why"`. `RIPWIRE_NO_TAIL_SYM_TERMS=1` restores the previous tail (a measurement and ablation switch; `test/tailsymtermscheck.sh` pins both).

It was found while following up a pre-release finding about answer depth. The alternative, replacing names, lost 12 credited names on 217 graded answers, so only the append ships. That analysis measured +7/−1 items on the 217 terse answers and +8/−0 on the full questions, at about +1 KB median per terse answer and +3.5 KB on the full question. The change's own numbers are in its pull request.

Versions: the session legend dictionary moves to `dictv=3b568d749cf9c03d entries=1129` (the `tsym=` clause); docs/COMMANDS.md and the 2026-11-13 showcase capture record the new pair.

### Changed — the `--for` tail's rows past page 0 now name their file's top symbols too

Since the tail walked four pages of the file page, a row past page 0 printed only its path (`p=`), so a file the answer listed at tail rank 41-160 never said which symbol in it matched. Those rows now carry `sym=` as well: the file's top three symbols by lens rank, the same pick and spelling every page 0 row uses (names the ranker already scored for that file, never a text match). The rows, their order, `total=`, `shown=` and `next=` are unchanged; only the names are added. Up to 120 such rows carry names (`kForFileTailSymWideRows`, every widened row a plain walk lists); a code question's walk can list more, and those past 120 still print `p=` only, counted by `p_only=` as before. Both walk legend clauses say so.

Measured on the 60 stored practice rows (in two wordings) and the 321 in-sample calls; the numbers are in the PR. `test/fortailwidecheck.sh` arm 14 pins the default against `RIPWIRE_TAIL_SYM_WIDE_ROWS=0` (the pre-change tail, a measurement and ablation knob) and the 10-row knob, in XML, JSON and the MCP `for` twin.

The walk legend clause change moves the session legend dictionary to `dictv=1106f51037b7009f entries=1053` (docs/COMMANDS.md and the showcase capture are re-recorded).

### Fixed — two printed orders break their last tie on content, not on node id

`mem=` on a `--for` owner row now orders two members declared on one line by name, and both legend clauses say so, so the printed order derives from the clause alone. A name with several definitions (the name tower, and the `Scope::name` tier a dotted `Svc._make` spelling reaches) now breaks its last tie on path, line, name and byte range. On a single root this matches the old order, so answers do not move. On a multi-root workspace, node ids follow the root labels, which is not path byte order (roots `a` and `a-b`), so the definition a verb picks or seeds first can change there, for example the `--verify` witness. The `--owners` and `--connect` wording that said "lowest node id" for the tower front now names path, line, name. New gate `test/tiebreakcontentcheck.sh`. Thanks to CodeRabbit for both findings in its review of #676.

### Fixed — a `--for` budget only trims the answer; it no longer switches it to a different answer

`--for --token-budget=N` used to choose a different answer as soon as any budget was given, even one far larger than the answer. In a pre-release comparison run, all 21 questions whose unbudgeted answer was under 16,000 tokens came back smaller and different at `--token-budget=16000`. On koa-02 the answer went from 24,446 B to 10,834 B, although the full answer cost only 5,494 tokens. In the other direction, `--detail=3 --max-tokens=16000` returned 1.14× the unbudgeted size.

The answer is now chosen as if no budget were given, and the budget is applied afterwards as a ceiling:

- When the answer fits, it is returned byte for byte, with no budget attribute added.
- When something is removed, the root names `budget_tokens=N` (or `max_tokens=N` for `--detail=N`) and the legend says what each removal means.
- The blocks printed outside `est_tokens` (`<syms>`, `<doc_body>`, `<decl_rows>` and the like) count toward the budget too. When the answer and those blocks do not fit, the blocks are held first: each prints its `held="budget"` stub with a `next=`, and `<doc_body>` gets only the room the answer leaves.
- After that, parts are removed in a fixed order until the answer fits: the optional attributes on `<sigs>` rows, the last `<tail>` rows, the last `<hops>` rows, the `<fold>` bodies, the last `<bodies>` bodies (the owner body the compact route serves included), the `<doc>` of the lowest-ranked `<sigs>` rows (`docs:N`), and finally the lowest-ranked `<sigs>` rows. Ranks 1 to 4 are always kept, and each ranked row removed is counted in `dropped_positive=`. `shed=` on the root lists what was removed, the legend defines only the steps taken, and the `next=` on a cut block is the same call without the budget (or the `--signatures-only` re-call the full answer already named).
- `--max-tokens` never removes a ranked `<sigs>` row. When the rest is gone and the answer is still over the ceiling, the root says `over_ceiling="1"`.
- A larger budget never returns less. Every row kept is a row of the full answer, in the same order.
- When the rows are already at their floor and the answer is still too big, `est_tokens` is higher than the budget on the root.

`--signatures-only`, the `--json` dialect and the `--limit`/`--offset` page keep their row target. `test/budgetmonotonecheck.sh` holds the contract on two fixtures and this repository's `src/`.

### Changed — `--for` exemplar touch rows name the definition that holds the line

Each `<touch p="file:line">` row of an add-a-new-X answer now carries `n=`, the innermost indexed definition whose span holds that line, spelled as the other `--for` rows spell it (`Owner.name` / `Owner::name` for a member). A line no definition holds (an import or `export *` line, or a TypeScript module constant the index does not hold yet) prints no `n=`, and neither does a line two separate definitions share, nor a line inside a Go `const (` group that declares no constant of its own. On kubernetes the `default_plugins.go:55` row now says `getDefaultPlugins`, on RisingWave `strong.rs:284` says `Strong::is_null_function_call`, and on TypeScript `program.ts:4354` says `verifyCompilerOptions`: the function to edit, not only the line. About 56 bytes of legend per add-a-new-X answer plus 20 to 50 bytes per named row; other answers are unchanged. New gate arm e6 in `test/forexemplarcheck.sh`.

### Fixed — a `build/` directory whose files git tracks is indexed

The crawl skips `build/` on the guess that it holds build output. When a repository commits real source there (bat's `build/` holds its Cargo build script), that source was missing from every answer, so a question about it could not be answered at all.

Now the crawl asks git. A `build/` that git tracks files under is indexed, and only its tracked files are: an untracked file inside it is left out and counted (`untracked_build=` on the map header, why=`untracked-build` rows in `--skipped`). A `build/` git does not track stays skipped, as before. git is asked once per root, and only when the walk reaches a `build/` that the repository's ignore rules do not already cover, so a repository that gitignores its `build/` starts no extra process. A root that is not a git repository keeps the old behaviour. Under `--no-ignore`, a tracked `build/` is indexed with every file in it, the flag's usual meaning, and the warm cache watches git's index there too, so a `git add` is never answered from a stale crawl.

Only `build/` changed. `dist/`, `out/` and `target/` stay skipped even when tracked. Repositories commit bundles under `dist/`: on axios that meant readable rollup output, which none of ripwire's minified, bundle or vendored checks flags, and the copies pushed real source off the first page of answers. `vendor/`, `third_party/` and `node_modules/` stay skipped as well.

The commands that index a commit's tree (`--quality-delta`'s HEAD side, `--merge-scout`, the churn window, `--dmm`) index the same directories, so an edit inside a tracked `build/` is reported as a change to existing code rather than as new code. The MCP server also notices a file added there.

On the 89 development questions from 11 open-source repositories, one question goes from missed to complete and none loses ground. On the 99 questions of a second development set no answer changes. The parse cache and warm snapshot versions move, so the first run after upgrading reparses. Gate: `test/trackedbuilddircheck.sh`.

### Fixed — five attributes that some answers printed with no definition are now defined where they appear

`--for`'s graph block `from_span=`/`to_span=` (and `of_span=`/`and_span=`), its unresolved-name ladder's `found=`, `key=` and `q=`, a struct row's `slot_fields_more=` (and `slot_by_more=`), and `--impact`'s file rollup `by_name=` (with `<rf via="name">`) each now carry a reading in the legend that already defines the rest of their block, present only when the attribute is (+19 to +129 B on an answer that carries one, 0 elsewhere). `test/legendcoveragecheck.sh` missed them for two reasons, both closed: its roster never reached those answer shapes (four default-only rows on small generated corpora now do, and arm G-A19 fails if one stops carrying its attribute), and its reader could not see the `<shortkey>` block's legend or the legend of the verb answer nested in `<graph_verb>`. The session legend dictionary gains two rows, so `dictv=` moves. Commit `146607f29`.

### Fixed — `--safe-delete` no longer claims coverage for an empty radius

`risk="uses-exist"` with no transitive radius (a function used only as a value, `impact_reaches="0"`) printed the reading "at least part of the radius is test-covered". The full legend now states that the radius is empty and claims no test coverage, and `--help` says the same. A non-empty radius keeps its sentence unchanged. New arm (21) in `test/safedeletecheck.sh`. Thanks to CodeRabbit for the finding in its review of #676.

### Fixed — a zero or "not found" that means "not indexed" now says so (`--uses`, `--defs` and the other selector refusals)

Four answers made a claim the index could not back:

- `--uses` on a definition that is read or named more than it is called (a Go or Rust struct, a C global table) printed a bare `count="0"` in a language whose read, write and type-mention sites the index never captures (only C++, ObjC and Python have that capture). Examples are fzf `Options`, terraform `FmtCommand`, mdbook `CmdRenderer`, tmux `cmd_table` and htop `Process_class`. The root now carries `unindexed_roles="read,write,type"`, and its legend says that for some or all users the count is a floor (every call, value, import and extends site, only the captured read, write and type ones), so a zero there is not a count of uses. A C-family header definition gets the same attribute when the corpus holds C files (read from the file list, so a declaration-only `.c` file counts); its C++ users keep their captured reads. This is the same rule `countFloorNext` already used.
- A bare member name in a language with no field capture answered `found="0" near=<a type>` on the CLI and `external="1"` ("no definition in the indexed tree") over MCP. hono's `routes` is one: it is a class field at src/hono-base.ts:125. When a lexical member declaration of that name sits directly in an unserved owner's body (not in a nested object literal), both surfaces now refuse with the sentence the qualified form (`Hono.routes`) already printed, and they name the owner and the line. Ruby declares no member lexically, so a class-body call such as `has_many :posts` or `attr_accessor :name` keeps its answer.
- A selector refusal (`--defs`, `--callers`, MCP `find_symbol`, …) for an object-like `#define` on the C++ parse path said "not found … did you mean". tmux `TMUX_SOCK` is one. The refusal now names the `#define` line and says that path does not index object-like macros. A `#define` inside a `/* … */` comment is not named, and a degraded `.c` file's `#define` gets the degraded-parse reading instead: C indexes its macros. When the scan stops at its budget (4096 files or 16 MiB), the refusal says so.
- When a definition was lost to a degraded parse, the not-found note named the first degraded file that mentioned the name, in path order. tmux `window` got alerts.c, while `struct window {` is at tmux.h:1441. The note now names the lexical definition line (whereis' own reading; a forward declaration does not count).

`test/usesunarmedcheck.sh` pins all four on the CLI and on MCP. Its positive controls are an armed C++ class, a Python class, and C, C++ and Python fields with real captures; these keep answering with no disclosure. Each negative arm counts its premise and fails on zero.

Found by pre-release reviews and answer audits.

The new `unindexed_roles=` compact legend term adds one entry to the session legend dictionary, which now reads `dictv=f7d122c82741a996 entries=1107` (docs/COMMANDS.md and the showcase capture are re-recorded).

### Changed — `--callers`, `--uses` and `--impact` name the definitions and declarations they measured

Every answer whose selector resolves a definition group now prints the `<def>` table, one-group answers included (`--callers` in XML, columnar and JSON, `--uses` in XML and columnar, `--impact`, and the MCP tools `find_referencing_symbols`, `uses` and `impact`). After each group's row comes one row per declaration tied to that definition by the existing identity rule, with the same `ix=` and `bodyless="1"`, so a declaration in another file is named: `--uses=chargeResponseStat` on envoy now prints `source/common/http/codes.h:56` and `:131` beside the `codes.cc` definition. The 16-group cap and `defs_listed=` are unchanged; `--callees`, `--safe-delete` and `find_symbol` are unchanged. The compact `bodyless=N of total=` reading is now scoped to `<bodies>`; it had fired on `<def bodyless>` rows.

- **A one-group `--impact` answer names the definition it measured.** It measured that group but never said which definition it was, so a reader holding a symbol with a declaration in a header and a body in a source file could not tell which one the blast radius was taken from. Development result on 298 graded cells: 211 to 213 complete, 0 regressions, +0.06 % bytes, cross-gold 253 of 1,742 unchanged; confirmed on the held-out gold below. Commit `57b4c3ee3`; `test/impactsoledefcheck.sh`.
- **An untied declaration is listed, never silent.** When a one-group answer counted a same-named declaration in `defs=` that the identity rule could not tie to the definition (another function, or a tie it cannot prove, such as a template member's in-class declaration, or a C header prototype parsed as C++), the declaration was dropped from the `<def>` table while `defs=` still counted it. It is now listed after the group's rows as `<def ix=K … bodyless="1"/>` with `K` past the groups and no row attributed to it, so the rows listed equal `defs=`; a present-only legend clause says so. Confirmed once on a fresh blind gold set (43 file golds): no cell lost a group, cross-gold flat, and together with the header-`static` fix within the +5 % byte bar on every surface (on tmux, +49 B on the two answers it touches). Commit `b32349df7`; `test/verbfixcheck.sh`.
- **The `<def>` legend readings are shorter with the same meaning**: 22 B less on every such answer, 53 B less on an MCP `find_referencing_symbols` answer. Each reading still says: `defs=` groups; a definition, then its tied declarations; the same `ix=`; `bodyless=1` means no body; a one-group answer names the ONE group measured, at file:line, and no row carries `of_def`; on `--uses` a use-site row names no group. Completeness unchanged on the 48-question held-out set (no cell lost or gained a group, cross-gold unchanged). Commit `dce3f8a50`; `test/verbdefrowscheck.sh` bounds each reading.

Held-out gold, matched n = 48 per verb (one llvm-project question not run): CLI `--callers` 12 to 27 complete (+9.33 % pooled bytes), `--uses` 15 to 32 (+15.49 %), `--impact` 36 to 36 (+0.17 %); MCP `uses` 14 to 31 (+15.94 %), `find_referencing_symbols` 27 to 28 (+14.47 %). Cross-gold unchanged, no cell lost a group. The pre-registered byte bar (at most +2 %) FAILED on `--callers` and `--uses`, as the registration predicted; most of the added bytes there are the compact legend reading (callers rows +2,713 B, legend +5,427 B pooled), and rows alone would still be about +3 % and +6 %. It landed on completeness, with that bar left to a separate project decision. The shorter readings above take back about 19 % of the `--callers` legend bytes and 14 % of the `--uses` legend bytes the definition rows added; the byte bar still fails, at about +8.1 % on `--callers`. Commit `e6671f267`; gate `test/verbdefrowscheck.sh`.

### Added — `--for` names the function that stores a head row into a slot

When a function on a `--for` answer's head rows is stored as a value into a slot elsewhere, the `<syms>` block now names the function that does it, as a `<y by="bind">` row with `into=` (the slot as the `--callers` `<vr>` row spells it). Examples are a factory that returns `{ isDeclarationVisible, … }`, a dict entry and a field assignment. TypeScript's `resolver.isDeclarationVisible` now shows `createResolver`, which returns the resolver object. The row can come from any file. Each head row gets at most two such rows, and `bind_total=` gives the full count when more were found. Argument passes, parameter defaults and decorators do not count. The legend clause and the rows appear only when a bind exists. `RIPWIRE_NO_BIND_ROWS=1` turns the rule off. The MCP `for` tool uses the same renderer.

### Changed — a warm run on an unchanged tree loads the crawl, the model and the resolved graph instead of rebuilding them

A warm run used to skip only the parse. It then walked the tree again, asked git for its ignore answer again, decoded every cache record, rebuilt the model and resolved every reference: all of it a deterministic function of what the cache already held. A run now stores that outcome once the tree has been parsed and is unchanged, and the next run on the same tree reads it back instead of recomputing it.

**Your cache file does not change, and nothing is written beside it.** The index format is untouched, so no existing cache file is invalidated and nothing is re-indexed: the file you name with `--cache=` is still the only file that appears there, and a run that reads it does not write to it. The stored outcome is a separate file in ripwire's own cache directory — the one `--doctor`'s `cache-dir` row reports — named after the cache file's own content, so a cache that is rewritten or deleted simply names a different one, or none. It is swept like every other cache there: one per repository per configuration, with the directory's existing age, count and byte budgets over it. Two checkouts of the same repository, or a committed cache consumed by several, each keep their own and never overwrite each other's.

Measured on the flagless map against `--cache=FILE`, median of 5, `/usr/bin/time -l`, dev build, macOS arm64. Both columns are the **same binary**, the "before" column with the feature disabled (`RIPWIRE_NO_WARMSNAP=1`), so nothing in the comparison turns on which build produced which number:

| repo | wall before | wall after | user CPU before | user CPU after | instructions before | instructions after | peak footprint before | peak footprint after | cache file | stored outcome |
|---|---|---|---|---|---|---|---|---|---|---|
| cpython | 1.34 s | 0.20 s | 1.48 s | 0.26 s | 21.81 G | 2.66 G | 386.1 MiB | 299.7 MiB | 151.6 MB (unchanged) | 76.8 MB |
| envoy | 1.29 s | 0.18 s | 1.35 s | 0.18 s | 20.21 G | 2.36 G | 339.0 MiB | 260.3 MiB | 154.6 MB (unchanged) | 62.8 MB |
| vscode | 3.30 s | 0.30 s | 3.55 s | 0.35 s | 53.55 G | 4.10 G | 594.7 MiB | 460.3 MiB | 284.6 MB (unchanged) | 112.6 MB |

**What it costs.** Disk, in ripwire's cache directory rather than in your cache file: 63 MB on envoy, 77 MB on cpython, 113 MB on vscode, against cache files of 155, 152 and 285 MB. And the one run that writes it is slower and larger than a run without it — envoy 21.09 G instructions and 385.9 MiB against 20.21 G and 339.0 MiB, about +4 % CPU and +14 % peak — while writing only the stored outcome, not your cache file. A **serving** run writes nothing at all. A cold run's CPU and peak footprint do not measurably change (three fills per arm: envoy peak +0.04 %, vscode −4.2 %, cpython −1.2 %, each inside the run-to-run spread). What a write costs in wall-clock I/O on a slow disk is not measured: `/usr/bin/time -l`'s I/O counters read zero for every run on this volume.

A run that re-parses a file stores the crawl, so the next run skips the walk, but not the model or the graph — a run that parsed is usually followed by another edit, and writing what the next run would refuse is not worth the bytes. Warm **peak memory falls** about 23 % on all three trees.

**What it never does is answer from a stored outcome it cannot vouch for.** The file carries the build's source identity, a digest of every option and of the environment the crawl and the resolver read, and one checksum over every byte. The model and the graph are keyed on every crawled file's path and content hash, and the graph on every file the resolver read outside the cache (a `go.mod`, a Cargo manifest, a `tsconfig.json` above the root). The crawl is replayed only while every directory and every entry the walk looked at still has the device, inode, size, mtime and ctime it had, every input of git's ignore answer is unchanged, and none of them was younger than two seconds when it was recorded. Any mismatch is a full run, and the answer is the one that run always gave.

`test/warmsnapcheck.sh` holds it, in 159 arms: stdout of a loading run is byte-identical to a `--no-cache` run for 23 verb invocations over every fixture tree in `test/`, and a changed file, an added or removed file, a same-size edit with its mtime put back, a new subdirectory, a changed `.gitignore`, a file added under a directory git reported ignored, a changed `go.mod`, a removed cache file, another `--exclude` set, a patched version field, a flipped byte and a file truncated inside a field each refuse it. A serving run is checked to leave the cache file byte-identical and to write nothing; two checkouts sharing one committed cache file are checked to be served from their own stored outcomes without either refusing the other's.

Not served: a multi-root run, `--scip`, `--pin-census`, `--max-memory`, `--no-cache`, a single-file root, and, for the model alone, a tree holding a pdf/docx/pptx/xlsx when `markitdown` is installed or one of them has a cached extraction (the crawl and the graph are still served). `RIPWIRE_NO_WARMSNAP=1` turns it off; `RIPWIRE_SNAPSHOT_STATS=1` prints one stderr line saying which stages a run loaded and which guard refused the rest.

### Changed — a `--for` hand-off to `--callers` / `--impact` names the complete call instead of a first page

What an agent spends is set by whether one call sufficed. On 78 `--callers` / `--impact` cells (39 symbols, five corpora) 42 window, and completing a windowed one through the chain the tool directs (the default page, then `--offset=<next_offset> --limit=<total>`) costs a median 292,807 B against 2-4 KB for an answer that fits one call. Both verbs hold their row total before they page, so the window is known exactly before a hand-off is made, and nothing pointed at the cheap complete form of the same rows.

- Where a `--for` answer hands off to `--callers` or `--impact` (the `<graph_verb verb="--callers=X">` block, the `<callers of=X next="--impact=X">` hop, a `<reask>`), the verb's rows are counted first by the verb's own code, over the definitions the verb binds to that spelling. When the default call would window, no page is appended: the hand-off carries `windows="1"`, `next_total=N` and `next="--impact=X --format=columnar --limit=N"` (or `--callers=X`, naming the verb handed off to), and its legend says a page was withheld. The named call lists the same rows (path, name, line identical in set, count and order on every measured cell).
- A hand-off whose verb does not window is byte-identical. `RIPWIRE_NO_WINDOW_HANDOFF=1` turns it off.
- `<reask>` on a change question ("is it safe to change `X`", "what breaks", "what depends on it") now names `--impact=X`, not `--callers=X`: the one-hop verb was a smaller answer to a different question. A who-calls question keeps `--callers=X`. This raises the bytes of the follow-up call and is the correct grain.
- Not extended to `--uses` / `--grep` (their windows have no graph signature), no byte estimate is printed (bytes per row is not a constant), and no in-degree proxy is used (it misses half the windowed impact cells, the 2-caller / 34,876-reach shape among them).

`test/handoffwindowcheck.sh` requires 0 false positives and 0 false negatives against the direct verb, the stated total to equal the verb's, the named call to be the same rows, a non-windowing answer to be byte-identical to the answer with it turned off, and the withholding to be visible; five mutations of the real binary each turn their arms red.

### Fixed — a multi-root workspace lists its files in path order

A workspace sorted its roots by the bare label, so roots `a` and `a-b` merged as `a/…` then `a-b/…`, while one root over their parent lists `a-b/…` first (`-` sorts below `/`). The roots now sort by `<label>/`, so the merged files, and every file or node id tie-break that reads them, follow the path order a single root gives. Argv order still never matters. Only workspaces with such a label pair change. New arm `G-label-order` in `test/multirootcheck.sh`.

### Changed — the edit-routing line `ripwire wrap claude` writes no longer says a Read is always required before an Edit

Claude Code refuses a native Edit on an unread file only when the file is outside its working directory (measured on stored sessions: 4 refusals in 283 Edits, all outside the session directory; 7 unread in-directory Edits, all accepted). The blurb now says so: a body ripwire delivered is the verbatim text of its lines and is edited directly inside the working directory; a ranged Read is for what was not delivered, and always for a file outside it. Other agents' text is unchanged. This changes no answer byte; its effect on agent behaviour is UNTESTED. Re-run `ripwire wrap claude` to refresh an installed copy.

### Fixed — a served body starts where its declaration starts: `export`, a decorator, `template<…>` and an attribute run are no longer cut off

Several grammars put the start of a declaration outside the node a symbol's span starts at: an outer node wraps it, or its attributes sit in front of it as siblings. Every body a verb printed started at the inner node, so the first line of the text came back without its prefix:

| written | was served as |
|---|---|
| `export function f() {}` | `function f() {}` |
| `@cache` / `def f(): ...` | `def f(): ...` (a different function) |
| `template<typename T>` / `T f( T a )` | `T f( T a )` (does not compile) |
| `#[inline]` / `fn f() {}` | `fn f() {}` |

Measured on 103 language × form rows over 22 languages, 45 lost their first line or its leading keyword: TypeScript, TSX and JavaScript `export` (function, default, async, class, interface, type, enum, const arrow), TypeScript `declare` and decorators, Python decorators (single, stacked, class, `@property`, `@staticmethod`), C++ and CUDA `template<…>` (function, class, member, nested, alias) and one-declaration `extern "C"`, Rust `#[…]` attributes, Ruby `private def` and a macro-wrapped `def`, Dart and GDScript annotations, Lua `local f = function`. Java, Kotlin, C#, Swift and PHP annotations and modifiers, Rust `pub`, Go, Objective-C, Bash and Clojure were already whole and are unchanged.

A body element (`--expand`, the `--for` body fold and auto bodies, `--pack-task`, `--from-trace`, `--exemplar`, the MCP `fetch_body`) now starts at the declaration's first byte. **The symbol does not move:** `l=` is still the line of its name, signature rows, ranking and every analysis are byte-for-byte what they were, and no cache is invalidated. The start is found when the body is cut, by re-parsing that one file with the grammar the index used; when the re-parse has no node at the symbol's start, the body is what it was before.

The edit verbs splice the span `--expand` prints, so they move with it. `--replace-symbol-body` replaces the wrapper too (a body replaced with the text it was served leaves the file byte-identical). **`--insert-before-symbol` on a decorated definition used to put the payload between the decorators and the function**, which silently re-attached them to the inserted code; it now lands above them.

On 89 development questions from 11 open-source repositories (page 1 of the default `--for`), 9 of the 114 served bodies carry a wrapper, all of them TypeScript `export`; the body rung goes from 18 to 21 with no cell lost, at +63 bytes over the 89 answers. Gate: `test/wrapperprefixcheck.sh`.

### Changed — the versions this release moves, stated once

The legend dictionary: `dictv=` c43b9c72ce2a139a (0.6.10, 1,050 entries) → cd0a012a40de1479, entries 1,294, 163,287 B (`ripwire --legend-dict=tiers`, the `full` row, read from the integrated release build). Among the additions, `--legend-seen=` made the CLI `--for` document legend dictionary entries, appended last: its trailing legend, the page clause, the `est_tokens=` sentences, the block-local `ripwire for X` legends, and, for a legend whose present-only clauses are erased per answer, the pieces between those clauses and the clauses themselves. The core tier is `have=6458b8da5fccacc6` (13 entries); the `callers`, `callees` and `impact` pack hashes move with the shorter `<def>` and importer readings (`def-reading-trim`, `impact-import-row-short`); only the `full` tier moves with `dictv=` otherwise.

The extraction key: `kParserVer` 317 (rich file tag 318), one number for the Rust `macro_rules!` transcriber calls and the C parameter-slot facts, above 313 on `main` before this release; every cache written by an older binary is refused and rebuilt once. `kCacheVersion` and the quality snapshot scheme do not move.


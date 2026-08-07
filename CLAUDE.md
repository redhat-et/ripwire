# ripwire — guide for coding agents

You are working **on ripwire's own source**. This file is the orientation an agent needs before it
touches this repo; it is not a manual for using the tool.

`ripwire` is a zero-runtime-dependency C++23 CLI. It crawls a codebase, extracts symbols with
tree-sitter, resolves references into a call graph, ranks the graph with Personalized PageRank, and
streams a deterministic minified XML map to stdout. Around that core sits the verb catalog in
`docs/COMMANDS.md` — navigation, diff-awareness, quality, retrieval — and an MCP server so an agent
can call them mid-task.

## Where to look

| Question | File |
| --- | --- |
| What does the tool do? Which flag answers which question? | `README.md`, `docs/COMMANDS.md`, `./build/ripwire --help` |
| How is it built internally? Pipeline, data model, determinism contract | `docs/ARCHITECTURE.md` |
| How is any published number measured? | `docs/EVALS.md` |
| C++ style, guardrails, gate discipline, submission checklist | `CONTRIBUTING.md` |
| Index of everything under `docs/` | `docs/README.md` |

`./build/ripwire --help` is generated from the binary's own flag table and is always current. When
`--help` and a document disagree, `--help` wins and the document is a bug.

## Build

```bash
cmake -S . -B build && cmake --build build -j          # dev build — no build type, deliberately
cmake -S . -B asan -DRIPWIRE_ASAN=ON && cmake --build asan -j
```

**Do not configure a local dev tree with `-DCMAKE_BUILD_TYPE=Release`.** Release defines `NDEBUG`,
which compiles `DEGRADED_PATH_ALERT` out; any gate that asserts a degrade path then passes blind.
CI builds *both* flavours on purpose — Release catches optimizer-only bugs, the plain build catches
degrade paths. If you add a degrade path, the plain run is what proves it.

**Never edit the tree while a build is running, and never background a build you then edit around.**
This is not a style preference — it silently produces a binary that cannot exist from any single
commit, and it costs hours to diagnose because every symptom points somewhere else.

Make decides what to recompile by comparing mtimes. Header tracking is correct and complete (the
compiler writes real depfiles: `build/CMakeFiles/ripwire.dir/src/ingest.cpp.o.d` lists `src/model.h`
among ~1100 headers, and `pagerank.cpp.o.d` correctly lists none). But mtime ordering is only
meaningful if the sources hold still. If you edit `src/model.h` — or `git checkout` a branch that
does — while a build is in flight, that build writes `.o` files whose **mtime is newer than the
header** but whose **content predates it**. Make then correctly concludes "up to date" and never
recompiles them again. `cmake --build build -j` reports success, exit 0, no warnings, forever.

Three ways this was hit, all from building across (or editing under) a branch switch:

- A `cmake --build asan` started on one branch and finished after a `git checkout` to another that
  changed `Symbol`. Half the objects had `sizeof(Symbol)==96`, half `104`. ASan reported a
  heap-buffer-overflow in `ingest` — a real report, of a fake bug. The tell: the overflowing buffer
  was **1344 bytes = 14 × 96**, an exact multiple of the *previous* struct size. If a sanitizer
  report's region size divides evenly by an old `sizeof`, stop debugging and rebuild.
- `src/quality.h`'s `kIngestParserVerMirror` edited while a clean rebuild ran. The binary kept
  emitting the old value through repeated successful rebuilds; `qextractionkeycheck` failed with
  `parserVer=41, expected 12/42` and looked like a missed mirror update. `touch`ing the header fixed
  it, which is the diagnosis: the object was newer than the source it disagreed with.
- The same `sizeof(Symbol)` mix can surface as an uncaught **`std::length_error`** — SIGABRT with
  `vector<unsigned int>::__append` in the stack, thrown from a `resize( symbols.size() )` deep in
  `ingest` (triaged 2026-08-07: `--quality-delta`'s `computeHeadSnapshot` re-ingest, ten identical
  reports in one morning of worktree churn). A `.size()` of a `vector<Symbol>` whose element size
  half the objects disagree on is garbage; the resize that consumes it is just the first bounds
  check it fails. Zero repro in 38 runs on clean rebuilds of the same commit. If an "impossible"
  length_error/bad_alloc comes from a resize fed by `.size()` of a struct that changed size across
  a recent branch switch, rebuild `--clean-first` before debugging the exception.

If sources may have moved under a build — after any branch switch, or if you are unsure — do not
trust an incremental rebuild:

```bash
cmake --build build --clean-first -j          # and the same for asan/ if that tree is in play
```

`test/g1freshcheck.sh` catches the ordinary stale binary (binary older than source) and is worth
believing when it fires — it is not noise. It cannot catch this variant, because here the binary is
*newer* than the source and only its contents are stale. Nothing in CMake can repair a source that
changed mid-compile; the discipline is the fix.

## Verify

```bash
python3 test/pargates.py . ./build/ripwire -j 6         # the full gate suite, in parallel
test/regression.sh                                      # the same set, sequentially (authoritative list)
LSAN_OPTIONS=suppressions=lsan_suppressions.txt ./asan/ripwire <dir> >/dev/null
./build/ripwire <dir> >a; ./build/ripwire <dir> >b; diff -q a b     # determinism gate
./build/ripwire <dir> | xmllint --noout -                          # well-formedness gate
```

Run gates in the **foreground**. A new `test/*check.sh` must be listed in `test/regression.sh` in
the same commit — `test/manifestcheck.sh` fails otherwise.

## The five guardrails

- **G1 — memory safety, adversarially verified.** `-fsanitize=address,undefined,integer,`
  `float-divide-by-zero,float-cast-overflow -fno-sanitize-recover=all -O2 -g`. The
  `-fno-sanitize-recover=all` is the linchpin: without it a run with undefined behavior still exits
  0. LeakSanitizer uses the committed `lsan_suppressions.txt` (tree-sitter grammars never free their
  static parse tables). ThreadSanitizer is a separate, mutually exclusive target.
- **G2 — cache locality over abstraction.** DOD, POD, SoA, 32-bit handles, no generic graph library.
  The no-allocation rule is scoped to our own code inside the PageRank power-iteration loop;
  tree-sitter allocates internally and is out of scope.
- **G3 — one deterministic build step.** CMake only, dependencies pinned and vendored, tree-sitter
  linked statically, no host-installed dependencies, no OpenMP. "Self-contained", not "static" — a
  fully static binary is impossible on macOS, so never pass `-static`.
- **G4 — maximum token density.** Minified XML, no inter-tag whitespace, terse attributes, one
  legend at the top. Gate: pipes clean through `xmllint --noout`, no newline outside CDATA.
- **G5 — modular zero-dependency CLI.** Hand-rolled argument parser; a flagless run is the core map;
  every flag is purely additive.

## Non-negotiables

1. **Write the gate before the code it measures.** A ranking, a token estimate, and a call graph all
   look plausible whether or not they are correct.
2. **Determinism is a contract, not a nicety.** Crawl order is sorted before IDs are assigned;
   reductions use fixed block partials in canonical order; the PageRank translation unit is compiled
   without floating-point reassociation. Anything that makes output depend on thread timing is a bug
   even when the ranking still "looks right".
3. **Honesty in output is a feature.** Counts that cannot be totals are labelled floors
   (`counts_floor="1"`); a zero means "none found", never "none exists"; every truncation is
   disclosed in the header. Do not add a surface that quietly rounds, guesses, or omits.
4. **Never `VERIFY( false )` on a degrade path** — release deletes the fallback behind it. Use
   `DEGRADED_PATH_ALERT`.
5. **Never `std::map` / `std::unordered_map`** — see the container rule in `CONTRIBUTING.md`.

## Style

Allman braces, braces on every control-statement body (no braceless `if( x ) f();` — inline
`{ … }` inside one-line lambdas), spaces inside parens (`f( x )`), ~160–200 column wraps, index-vs-count naming,
structured-binding returns, tolerance-band float tests. The full rules — with the reasoning — are in
**`CONTRIBUTING.md` §3**. Read that before writing C++ here; it is self-contained.

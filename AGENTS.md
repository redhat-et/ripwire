# ripwire — agent instructions

This repository follows the `AGENTS.md` convention. The full agent guide is **`CLAUDE.md`**; this
file is the short form, and the two do not disagree.

`ripwire` is a zero-runtime-dependency C++23 CLI that parses a codebase, ranks symbols by
Personalized PageRank, and streams a deterministic minified XML map to stdout.

## Setup

```bash
cmake -S . -B build && cmake --build build -j
```

No build type. `-DCMAKE_BUILD_TYPE=Release` defines `NDEBUG`, which compiles `DEGRADED_PATH_ALERT`
out and blinds every degrade-path gate. CI builds both flavours; locally, use the plain one.

## Test

```bash
python3 test/pargates.py . ./build/ripwire -j 6     # full gate suite, parallel — run in the foreground
./build/ripwire . >a; ./build/ripwire . >b; diff -q a b   # determinism: output must be byte-identical
./build/ripwire . | xmllint --noout -                     # XML well-formedness
```

Sanitizer build, required before a PR:

```bash
cmake -S . -B asan -DRIPWIRE_ASAN=ON && cmake --build asan -j
LSAN_OPTIONS=suppressions=lsan_suppressions.txt ./asan/ripwire . >/dev/null
```

A new `test/*check.sh` must be added to `test/regression.sh` in the same commit, or
`test/manifestcheck.sh` fails.

## Rules that will fail your change if you break them

- **Gate first, code second.** Rankings and call graphs look plausible whether or not they are right.
- **Determinism.** Sorted crawl order before ID assignment; fixed-block reductions in canonical
  order; no floating-point reassociation in the PageRank translation unit.
- **Honest output.** Floors are labelled `counts_floor="1"`; a zero is "none found", not "none
  exists"; every truncation is disclosed. Do not add a surface that rounds or guesses silently.
- **`VERIFY( cond )` for invariants; `DEGRADED_PATH_ALERT` for recoverable errors; `PANIC` for
  corruption.** Never `VERIFY( false )` on a degrade path — release deletes the fallback behind it.
- **No `std::map` / `std::unordered_map`** — `HashMap<>` for hash lookup, `gtl::btree_map` for
  ordered iteration, `dynamic_map` for bounded hot paths.
- **Allman braces, spaces inside parens** (`f( x )`), ~160–200 column wraps, index-vs-count naming
  (`nodeId` vs `nodeCount`).

## Documentation

| Need | File |
| --- | --- |
| Full C++ style, guardrails G1–G5, submission checklist | `CONTRIBUTING.md` |
| Pipeline, data model, determinism contract | `docs/ARCHITECTURE.md` |
| Measured claims and their provenance | `docs/EVALS.md` |
| Per-verb reference (generated from the binary) | `docs/COMMANDS.md` |
| Index of everything under `docs/` | `docs/README.md` |
| The authoritative flag list | `./build/ripwire --help` |

`--help` is generated from the binary. If a document disagrees with it, the document is the bug.

# Struct-layout doctor — catch the binary that cannot exist from any single commit

You are teaching `ripwire --doctor` to detect a **mixed-layout binary**: one whose translation units
were compiled against different versions of the same struct. Each translation unit records the layout
facts it was compiled with, in a way that survives Release builds, and `--doctor` compares the records
and reports any disagreement.

This is a small, self-contained change — a good first contribution to the C++ core — and it closes a
trap that has already cost this project hours of debugging a bug that was not there.

Work in a git worktree, not the main checkout. Never edit the tree while a build is running; that
is, quite literally, the hazard this work detects.

---

## Why it matters

`CLAUDE.md` describes the hazard in detail, and it is worth reading in full before you start. The
short version: `make` decides what to recompile by comparing mtimes. If a header such as `src/model.h`
changes **while a build is in flight** — an edit, or a `git checkout` of a branch that touches it —
the build writes object files whose mtime is newer than the header but whose contents predate it.
`make` then concludes they are up to date, forever. The build reports success, exit 0, no warnings.

It has been hit three ways, all recorded in `CLAUDE.md`:

- **A fake memory bug.** Half the objects had `sizeof(Symbol) == 96` and half `104`. AddressSanitizer
  reported a heap-buffer-overflow in `ingest` — a real report, of a fake bug. The tell was a
  1344-byte region: exactly 14 × 96, a multiple of the *previous* struct size.
- **A version constant that would not change.** A binary kept emitting an old value through repeated
  successful rebuilds, and the gate that caught it read like a missed update somewhere else.
- **An impossible exception.** An uncaught `std::length_error` from a `resize( symbols.size() )` deep in
  `ingest`. Ten identical reports in one morning of worktree churn, zero reproductions in 38 runs on
  clean rebuilds.

`CLAUDE.md` concludes that **nothing in CMake can repair a source that changed mid-compile**; the
discipline is the fix. The doctor cannot repair it either — but it can **say so in one line**, instead
of letting someone spend an afternoon on a sanitizer report that is really a build artifact.

`test/g1freshcheck.sh` catches the ordinary stale binary, one older than its sources, and only for
`asan/ripwire`. By `CLAUDE.md`'s own account it cannot catch this variant: here the binary is *newer*
than the source, and only its contents are stale.

---

## Background — what exists, with file pointers

| File | What it gives you |
| --- | --- |
| `CLAUDE.md`, "Build" | The hazard, the three incidents, and the `--clean-first` remedy |
| `CMakeLists.txt` | The `ripwire` target is `src/main.cpp` plus `RIPWIRE_SRCS` (`src/ingest.cpp`, `src/pagerank.cpp`, `src/infra/diagnostics.cpp`), with `src/alloccount.cpp` added under `RIPWIRE_ALLOC_COUNT`. `ripwire_probe` links `src/tsprobe.cpp` with the same sources. A Release configure turns LTO on |
| Your build's depfiles | Which translation units actually include `src/model.h`. `CLAUDE.md` notes that `ingest.cpp.o.d` lists it and `pagerank.cpp.o.d` does not. Derive the list from depfiles; do not hand-maintain it |
| `src/model.h` | `Symbol` — pinned by `static_assert( sizeof( Symbol ) == 64 + 2 * sizeof( std::string ) )`, written relative to `std::string` because that size differs between standard libraries. `Reference` carries several `std::string` members and has no size pin. `IngestResult` carries vectors of `Symbol`, `Reference`, `Include`, `ConstOpen`, `Binding`, `BindingAlias`, `RouteDef`, `RouteUse`, `FileHealth` and `SkippedOversize` from `ingest.cpp` into `main.cpp` |
| `src/ingest_cache.h` | `static_assert( sizeof( CacheEntry ) == kCacheEntryBytes )` and `alignof( CacheEntry ) == 8` — the house pattern for a struct whose bytes **are** an on-disk format. The cache header also records the platform's endianness and pointer width |
| `src/verbs_doctor.h` | `runDoctor`: a section of `main.cpp`'s translation unit (it `#error`s if included elsewhere). One `row( name, ok, attrs )` lambda per check emits `<c n= ok= …/>`; the rows today are `binary-path`, `grammars`, `cache-dir`, `git`, `tree-sitter`, `tracked-binaries`, `index-cache` and `git-config-trust`. Exit 1 when any row fails. The legend is `doctorLegendComment()` |
| `test/doctorcheck.sh` | Derives `checks=` from the emitted rows rather than pinning a count, asserts a **named row set**, and requires `hint=` only on failing rows |
| `test/g1freshcheck.sh` | The mtime-based stale-binary check this work complements, not replaces |
| `src/layout.h` (`--layout`) and `test/abicheck.sh` (`--stray-content --abi`) | **Not the same problem.** These verbs model struct layout from **source text** for the repositories ripwire analyzes; `src/layout.h` says so itself: "THIS IS A MODEL, NOT THE ABI". This task needs what each compiler invocation **actually saw**, which no source model can tell you |

---

## The one insight that shapes the design

**A `static_assert` in a header cannot catch this.** Every translation unit checks its own view of the
header, and every view is self-consistent. `main.cpp.o` built against the new `Symbol` passes the new
assertion; `ingest.cpp.o` built against the old one passed the old assertion. Only a comparison
**across** translation units, made after linking, can see that they disagree.

---

## How to reproduce the hazard (in a scratch tree only)

You do not need the real hazard to build the detector, and the gate must not depend on it. But seeing
it once makes the work concrete:

1. In a **scratch copy** of the repository, build it plainly.
2. Start `cmake --build build -j`, and while it compiles, add a field to `Symbol` in `src/model.h`.
3. Let the build finish and run `cmake --build build -j` again. Note that it rebuilds nothing, or not
   everything.
4. Run the result on a small corpus and watch for the kinds of failures `CLAUDE.md` lists.

It is timing-dependent by nature, so it is a demonstration, never a gate. Then
`cmake --build build --clean-first -j` in that tree, or delete it.

---

## Design space and constraints

**Recording.** Each relevant translation unit carries a record of `sizeof` and `alignof` for the types
that cross translation-unit boundaries — at least `Symbol`, `Reference`, `Include`, `ConstOpen`,
`Binding`, `BindingAlias`, `RouteDef`, `RouteUse`, `FileHealth`, `SkippedOversize` and `IngestResult`,
plus `sizeof( std::string )`. The record must:

- **Have internal linkage** — an anonymous namespace or `static`. An `inline` variable or function is
  merged by the linker, which keeps one copy and discards the rest: it would hide exactly the
  disagreement you are trying to see (trap 1).
- **Carry a translation-unit identity.** `__FILE__` inside a header names the header, not the unit that
  includes it (trap 4). A compile definition set per source file from CMake is one way.
- **Survive a Release build.** Not `VERIFY`, not `DEGRADED_PATH_ALERT`, not guarded by `NDEBUG` — all of
  those change or vanish in Release. It must also survive LTO: something the linker can prove unused may
  be dropped.
- **Be reachable from `--doctor`.** A registration at static-initialization time into a registry owned
  by one `.cpp` is portable; make the registry a function-local static so cross-unit initialization order
  cannot bite (trap 5). Platform section tricks also work, but differ between ELF and Mach-O.

**Comparing.** Compare the records **for agreement**, never against pinned numbers: `std::string`, and so
`Symbol`, has a different size under a different standard library, and a pinned number would fail on the
first Linux build. Do not record `offsetof`: on types that are not standard-layout, which is anything
holding a `std::string`, it is only conditionally supported. Say plainly what `sizeof` and `alignof`
cannot see: a reordered struct of the same size.

**Reporting.** One new `--doctor` row, name to be agreed (`layout` is the obvious candidate):

- `ok="1"` with how many translation units and types it compared;
- `ok="0"` and exit 1 on any disagreement, naming the first disagreeing type, the units, and each unit's
  values, with a `hint=` to rebuild with `--clean-first`;
- **never `ok="1"` when there was nothing to compare** — a binary with a single record has not been
  checked, and the row must say so rather than pass (trap 9).

The doctor's legend defines any new attribute, and the row stays deterministic for a given binary.

**Cache-format pins.** Separately, audit where a struct's raw bytes are written to the cache. Where the
bytes **are** the format, the house `static_assert( sizeof( X ) == N )` pattern belongs beside the struct,
as `CacheEntry` has. Where a writer serializes field by field, a size pin adds nothing. List what you
found either way.

**House rules that apply here.** Gate before code. Allman braces, braces on every body, spaces inside
parens, structured-binding returns (CONTRIBUTING.md §3). No `std::map` or `std::unordered_map`. No timing
assertions. Any new degrade path uses `DEGRADED_PATH_ALERT`, never `VERIFY( false )`, although a doctor
finding is a reported failure rather than a degrade path.

---

## The gate — red first

Write `test/<name>check.sh`, list it in `test/regression.sh` in the same commit, and regenerate the gate
count with `python3 docs/gatecount_build.py`. Arms worth having:

1. **Mechanism, red on purpose.** A small two-translation-unit fixture that uses the same recording
   header, with a test-only struct whose definition differs between the two units through a compile
   definition. The comparator must report the disagreement, naming the type and both values. This proves
   the detector works **without** touching `src/model.h` and without a timing race.
2. **The real binary agrees.** `ripwire --doctor` on the plain build shows the row with `ok="1"` and a
   unit count of at least two.
3. **Release survives.** A Release binary — `NDEBUG` plus LTO — still carries every record and emits the
   same row. If the gate cannot find a Release binary it SKIPs with a banner, never a silent pass (the
   `test/prconvergecheck.sh` B2 pattern).
4. **Nothing to compare is not a pass.** A single-record fixture yields the "not checked" form.
5. **`test/doctorcheck.sh`'s named row set grows** to include the new row.

---

## Acceptance criteria

1. Records in every translation unit of `ripwire` that includes `src/model.h`, with the list derived
   from depfiles, surviving plain, Release and ASan builds.
2. The `--doctor` row: agreement reported with its unit and type counts; disagreement reported with
   `ok="0"`, exit 1, the type, the units, the values, and a `--clean-first` hint; nothing-to-compare
   reported as not checked.
3. The gate above, observed red on the mixed fixture before the comparator existed, and green after.
4. The cache-format pin audit, with its findings listed in the PR even if no pin is added.
5. One sentence in `CLAUDE.md`'s hazard section pointing at the row, next to the `g1freshcheck` note.
6. Gates green in the foreground: the new gate, `test/doctorcheck.sh`, `test/legendcoveragecheck.sh` if
   the doctor's legend changed, `test/manifestcheck.sh`, `test/gatecountcheck.sh`, and
   `test/g1freshcheck.sh`.

---

## Known traps

1. **`inline` hides the bug.** The linker keeps one copy of an inline variable or function and discards
   the others — the disagreement disappears in the act of linking.
2. **A header `static_assert` checks one view.** See "The one insight".
3. **LTO and dead-code stripping remove data nothing uses.** Test the Release binary, not only the dev
   build.
4. **`__FILE__` in a header is the header.** Every record would carry the same name.
5. **Static initialization order across translation units is unspecified.** A global registry filled
   from two units can be used before it is constructed; a function-local static cannot.
6. **Pinned numbers fail on the other standard library.** Compare for agreement.
7. **`offsetof` on a type holding `std::string` is only conditionally supported.** Stay with `sizeof`
   and `alignof`.
8. **Reproducing the real hazard means editing a header during a build** — exactly what you must never do
   in your working tree. Do it in a scratch copy, and never gate on it.
9. **Empty equals agreement.** One record compared with nothing agrees with everything. CONTRIBUTING.md §2
   lists this shape; the row must not fall into it.
10. **Do not reach for `--layout`.** It models source text for other people's code; it cannot see what your
    compiler produced.
11. **`binary-path` is a different question.** That row compares the `ripwire` on `PATH` with the binary
    you ran. The new row is about the contents of one binary.

---

## What the PR description should contain

- The types recorded, and why each crosses a translation-unit boundary.
- How records survive Release and LTO, and the Release run that proves it.
- The red run of the mixed fixture, and the green run after.
- The `--doctor` output for agreement, disagreement and nothing-to-compare.
- The cache-format pin audit.
- What the check cannot see — a same-size reorder, a mismatch in a translation unit that includes none of
  the recorded types — stated plainly.

---

**Write the plan — the types to record, the recording and registration mechanism, the doctor row and its
three states, the gate arms and the red run — then STOP for my go-ahead.**

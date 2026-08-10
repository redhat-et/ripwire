# Contributing to ripwire

Thanks for looking. ripwire is a zero-runtime-dependency C++23 CLI: it parses a codebase, ranks
symbols by Personalized PageRank, and streams a deterministic minified XML map to stdout. It is
small, fast, and self-checking on purpose, and the rules below are what keep it that way.

Read this file before writing C++ here. It is self-contained — you do not need any other document
to follow it.

If you are about to write C++ here, §3 is the authoritative style-rules checklist.

- **What the tool does / which flag answers which question** → `README.md`, `docs/COMMANDS.md`, or
  `./build/ripwire --help` (the binary self-documents and is always current).
- **How it is built internally** → `docs/ARCHITECTURE.md`.
- **How its claims are measured** → `docs/EVALS.md`.

---

## 1. Build and verify

### Development build (this is the default — do not add a build type)

```bash
cmake -S . -B build && cmake --build build -j
```

**Never configure a local dev tree with `-DCMAKE_BUILD_TYPE=Release`.** Release defines `NDEBUG`,
which compiles `DEGRADED_PATH_ALERT` out. A gate that asserts a degrade path then goes blind and
passes for the wrong reason. See §5 for why CI builds both flavours.

### Sanitizer build (the G1 stack — required before you open a PR)

```bash
cmake -S . -B asan -DRIPWIRE_ASAN=ON && cmake --build asan -j
LSAN_OPTIONS=suppressions=lsan_suppressions.txt ./asan/ripwire <dir> >/dev/null
```

### Building on Linux

ripwire builds and passes its suite on Ubuntu 24.04 with gcc 13.3 or clang 18, but a few things
differ from macOS enough to cost you an afternoon if nobody says them out loud.

**Memory, not cores, sizes `-j`.** `src/main.cpp` is one very large translation unit. Compiling it
at `-O2` needs roughly **3 GB of RAM per parallel job under gcc**; clang does the same file inside
2 GB. A machine with fewer gigabytes than `3 × jobs` does not fail with a diagnostic — it meets the
OOM killer, and you get a `cc1plus … killed` line with no explanation. On an 8 GB box, use `-j2`
with gcc, or use clang.

**Suite prerequisites.** Beyond a compiler and CMake, the gates shell out to `xmllint`
(`libxml2-utils`), `ripgrep`, `bc`, `jq`, `curl`, `python3` and `git`. Two further conditions are
easy to miss because they make gates *fail* rather than skip:

- **Full git history.** The churn, co-change, ownership and hotspot gates mine `git log` for real.
  A `--depth 1` clone — GitHub `actions/checkout`'s default — leaves them measuring nothing, so CI
  pins `fetch-depth: 0` at every checkout step. Clone the same way locally.
- **Not as root.** Several gates assert that an unreadable file degrades cleanly. Under `root`,
  `chmod 000` does not actually deny a read, so those arms self-skip and prove nothing.

**`XDG_CACHE_HOME` must already exist.** The cache-directory ladder creates its own `ripwire/`
subdirectory but does not create the parent recursively, so pointing `XDG_CACHE_HOME` at a path
that is not there yet silently disables caching. Correctness is unaffected — every run is then a
cold parse — but the warm-run speed is simply gone, with nothing on stderr to say so.

**GNU `stat` is not BSD `stat`.** `-f` selects *filesystem* status on GNU coreutils and takes no
format argument, so the tempting `stat -f FMT … || stat -c FMT …` fallback does not fall back: the
first arm prints a filesystem block and exits 1, and the second arm's answer lands underneath six
lines of noise. Gate scripts detect the flavour once (`stat --version`) and then use a single form.
Please keep it that way.

**No kqueue.** The long-lived MCP server's FS-event watcher is a macOS/BSD optimisation. On Linux it
is compiled out and freshness comes from the per-request stat sweep — that is the designed path, not
a degradation, so it is silent and the staleness contract is unchanged. You can build and run that
path on a Mac with `cmake -S . -B build-nokqueue -DCMAKE_CXX_FLAGS=-DRIPWIRE_HAS_KQUEUE=0`.

### Determinism gate

Output is a sorted top-K. A sort has no tolerance band, so the contract is byte-identity:

```bash
./build/ripwire <dir> >a; ./build/ripwire <dir> >b; diff -q a b
```

Run it three times — scheduling-dependent nondeterminism does not show up reliably in one pair.
Warm (cached) output must equal cold output exactly.

### Well-formedness gate

```bash
./build/ripwire <dir> | xmllint --noout -
```

### The full gate suite

```bash
python3 test/pargates.py . ./build/ripwire -j 6
```

This runs every `test/*check.sh` gate in parallel. `test/regression.sh` runs the same set
sequentially and is the authoritative list — `test/manifestcheck.sh` fails if a committed
top-level `*check.sh` is not listed there, so **a new gate must be added to `test/regression.sh`
in the same commit that adds the gate**.

Run your gates in the foreground. A suite left running in the background at the end of a work
session is a suite nobody read.

### The formatting gate — and the rule for when it disagrees with you

```bash
scripts/formatcheck.sh              # GATE — what CI runs
scripts/formatcheck.sh --advisory   # REPORT over the whole first-party set; always exits 0
```

`.clang-format` encodes §3's house style as closely as clang-format can express it, and the gate runs
over a short, explicit `GATED` list inside `scripts/formatcheck.sh` — nine files that already agree
with `.clang-format` byte for byte. It is short on purpose. §3's style is hand-formatted in ways
clang-format has no option to preserve: multi-statement one-liners, several initialiser rows or
`case` labels packed per line, wrap seams chosen by hand at 160–200 columns, `[ & ]` lambda intros.
Reformatting all 98 first-party C++ files changes 14235 lines that survive `git diff -w` — real
joins and splits — across 89 of them (re-measured after the 2026-08-03 always-braces sweep), so a
whole-tree check would be red on a *correctly* styled tree. The advisory mode prints that gap on
every run, so its size stays on the record instead of being forgotten.

Two consequences, and the second is the one that matters:

- **Adding a file to `GATED` is the good outcome.** Run `clang-format` in place on it, confirm the
  change is whitespace only (`git diff -w --output=/tmp/d && [ ! -s /tmp/d ]`), run the suite, then
  add the path.
- **If house-style code lands in a gated file and the gate reds, delete the path from `GATED` — never
  un-write the house style.** A packed table or a `{ a; b; }` one-liner in a gated file will be
  reported as unformatted, and §3 is the rule that is right. Say so in the commit message. A gate
  that punishes the documented style is a broken gate, not a broken change.

The checker is **pinned to clang-format major 22**, because clang-format's output moves across major
releases and an unpinned checker reports drift on a tree that was formatted correctly. Set
`RIPWIRE_FORMAT_ANY_VERSION=1` to run anyway, and `CLANG_FORMAT=/path/to/clang-format` to point at a
binary that is not on `PATH` (Homebrew's LLVM is not, on macOS, by default).

**clang-tidy is advisory only, and must stay that way.** `.clang-tidy` carries an empty
`WarningsAsErrors`, CI runs it with `continue-on-error`, and the config is curated down to
`bugprone-*` / `clang-analyzer-*` / `performance-*` / `misc-dangling-*`. Its default catalogue argues
for a different C++ than the data-oriented one §3 and G2 mandate — POD and SoA, C arrays, 32-bit
handles, `VERIFY` instead of exceptions — so read its output as a to-triage list, never as a queue of
defects.

---

## 2. Gates come first

Write the gate **before** the code it measures. This is not a style preference: a ranking, a token
estimate, and a call graph all look plausible whether or not they are correct, so code-then-test
here means writing a test against whatever the code happened to do.

A change is rejected — automatically — if any of these is true:

- its test binary exits non-zero;
- stderr matches `^==[0-9]+==\s*(ERROR|WARNING)` (AddressSanitizer) or `runtime error:` (UBSan);
- the CSR property test fails;
- the determinism gate fails.

Two failure modes this project has actually shipped, and now gates against:

- **A gate that cannot observe what it asserts** ("green while inert"). If a gate's probe target
  can vanish — an empty diff, a missing fixture, a keyword the fixture never spells — the gate
  passes for the wrong reason. Add a presence guard: assert the thing you are about to search for
  actually exists, then assert the property.
- **A gate that counts.** Anchor your counts (`grep -c '^  PASS'`, not `grep -c PASS`) or a banner
  line will silently join the tally.

---

## 3. C++ style rules

### Formatting

- **Allman braces** — `{` and `}` on their own lines, for functions, `if`, `for`, and lambdas.
- **Every control-statement body takes braces** — no braceless `if( x ) f();` / `for( … ) g();`
  one-liners (rule landed 2026-08-03; `.clang-format` enforces it on new code via `InsertBraces`).
  On its own line, the body gets the full Allman form. Inside a one-line lambda the braces go
  inline — `[ & ] { if( ok ) { f(); } g(); }` — keeping the terse-lambda idiom legal.
- **Spaces inside parens** — `f( x )`, `for( std::size_t i = 0; i < n; ++i )`, `if( ok )`.
- **Wrap at ~160–200 columns**, not 80 or 120. Break on logical-operator seams, never mid-expression.
- **Blank-line groups**, each led by a `//` comment naming the group.
- C++23.

### Self-check, don't throw

- `VERIFY( cond )` at every precondition and invariant. It is free in release (`-DNDEBUG` lowers it
  to `__builtin_assume`: zero cost, plus an optimizer hint).
- A **recoverable** runtime error — an unreadable file, a full pool, a missing grammar — is a
  **degrade**, not a failure: return `nullptr` / `false` / empty / a clamped value, emit
  `DEGRADED_PATH_ALERT( "msg" )`, and keep going. The whole pipeline must survive a malformed repo.
- A **corrupt invariant** is a `PANIC`.
- **Never write `VERIFY( false )` on a degrade path.** In release the assert compiles away and the
  optimizer deletes the fallback behind it — that is a real shipped-bug shape, not a hypothetical.
  Guard, don't assert.
- Throw only at the `operator new` seam. A throw escaping a worker thread is `std::terminate`, so
  wrap thread bodies in `try { … } catch( ... ) { … }`.

### Naming encodes what the type cannot

- **Index and count stay visibly distinct**: `nodeId` vs `nodeCount`, `edgeIndex` vs `edgeCount`,
  `rowOffset` vs `rowCount`. This is the number-one off-by-one source in CSR code.
- Units, frame, and ownership go in the name.
- Predicate bools read as predicates (`isReady`, `hasNext`). No negated names. No type-Hungarian.

### Data-oriented layout

- **POD structs, SoA not AoS.** The CSR triple `rowOffsets[] / colIndices[] / values[]` is textbook
  structure-of-arrays — keep new hot structures the same shape.
- **32-bit ids and handles** (`NodeId = uint32_t`) over 64-bit pointers; the smallest type that fits.
- `static_assert( sizeof( X ) == N )` after each hot struct, so a layout regression fails loudly.
- For a field written from more than one thread, align with
  `alignas( infra::platform::hardware_destructive_interference_size )` — **never hardcode `alignas( 64 )`**.
  The Apple Silicon cache line is 128 bytes, and a hardcoded 64 quietly reintroduces false sharing.
- **Declarative constexpr tables over scattered switch/if**: `extension → { ts_language, tags.scm }`,
  `node-kind → { isDef, isRef, tag }`, `SymKind → const char* tag`. One pass to read instead of a
  branch chase.

### Containers

- **Never `std::map` or `std::unordered_map`.**
  - Hash lookup → `ankerl::unordered_dense::map` (the `HashMap<>` alias; flat, cache-friendly).
    **Call `reserve()` with your expected size** — the default starts at 4 buckets and rehashes
    through 3 / 6 / 12 / 25 / 51 …; reserving skips the whole cascade.
  - Sorted lookup or ordered iteration (byte-stable sidecars, ordered emit) → `gtl::btree_map`.
  - A hot path with a known capacity bound → `dynamic_map` (a B+ tree with a vectorized key scan
    and zero per-operation allocation; pools are sized once at construction).
- `std::vector` for the CSR arrays is correct — it is contiguous. Reach for a node-based std map
  only when you genuinely need pointer/reference stability, and say so in a comment.
- Two standing caveats: hash-map **iteration order must never reach output** (sort first, or use an
  ordered container); and `unordered_dense` invalidates references on insert (values live in one
  vector), so never hold a `T&` into it across an insert.

### Interfaces

- **Structured-binding returns** over out-params: `auto [ nodes, edges ] = build( … );`.
- **Views at seams** (`std::span`, `std::string_view`). The caller owns the storage; allocate from
  a caller-owned arena.
- **Symmetric bare scopes** for deterministic RAII teardown.

### Tests

- **Float comparisons assert a tolerance band, never bit-exactness.** Fast-math and threaded
  reductions reorder sums. For PageRank: compare scores within an epsilon and assert the top-K
  **order**, not the scores.
- **A sort has no tolerance band.** For sorted or serialized output, use the determinism gate
  instead: run twice, `diff -q` the bytes.

---

## 4. The five guardrails (G1–G5)

These are the project's standing constraints. Every one of them is enforced by a gate, not by
review discipline.

- **G1 — zero-leak memory safety, adversarially verified.** The sanitizer stack is
  `-fsanitize=address,undefined,integer,float-divide-by-zero,float-cast-overflow
  -fno-sanitize-recover=all -O2 -g`. The `-fno-sanitize-recover=all` is the linchpin: without it
  UBSan warns and continues, so a run with undefined behavior can still exit 0. LeakSanitizer uses
  the committed `lsan_suppressions.txt` (tree-sitter grammars allocate static parse tables and
  never free them, which reads as a false leak). ThreadSanitizer is a **separate** build target —
  it is mutually exclusive with ASan. Valgrind is not a gate here; it has no working Apple Silicon
  port, so memcheck belongs in a Linux CI job if it is wanted at all.
  **Build G1 with Clang.** `integer` is a Clang-only UBSan group and GCC rejects the whole option, so
  a `-DRIPWIRE_ASAN=ON` configure under GCC drops `integer` (and its ignorelist exemptions) and says
  so at configure time — a real but reduced stack. CI pins its Linux asan job to clang for that
  reason; the GCC path exists so a contributor's build degrades honestly instead of failing.
- **G2 — cache locality over abstraction.** DOD, POD, SoA, 32-bit handles, no generic graph
  library. The no-dynamic-allocation rule is scoped to the code *we* write inside the PageRank
  power-iteration loop: preallocate two rank buffers plus scratch once and ping-pong them.
  tree-sitter's parser allocates internally by design and is explicitly out of that scope.
- **G3 — one deterministic build step.** CMake only, dependencies pinned and vendored, tree-sitter
  core and grammars compiled from source and linked statically, no host-installed dependencies, no
  OpenMP. The goal is "self-contained", **not** "static": a fully static binary is impossible on
  macOS (`libSystem.dylib` is the syscall interface), so never pass `-static` to the linker.
- **G4 — maximum token density.** Minified XML, no inter-tag whitespace, terse attributes
  (`t="fn"`), one schema legend at the top. The gate: output pipes clean through `xmllint --noout`
  and contains no newline outside CDATA.
- **G5 — modular zero-dependency CLI.** Hand-rolled argument parser. A default run with no flags is
  the core map; every flag is purely additive and gated by a `Config` field.

---

## 5. The two build flavours (why CI builds twice)

CI builds and runs the whole suite **twice**: once as `Release`, once with the plain (no build
type) configuration.

Both are load-bearing, and the reason is a real regression this project shipped:

- **Release catches optimizer-only bugs** — code that is correct at `-O0` and wrong once
  `__builtin_assume` and inlining are in play, including the "assert it, then defend against it"
  trap where a `VERIFY` lets the optimizer delete the defensive branch that follows.
- **The plain build catches degrade paths** — `DEGRADED_PATH_ALERT` is compiled out under `NDEBUG`,
  so a Release-only suite cannot observe the alert that a degrade-path gate asserts. For three
  development cycles, every degrade-path gate in CI passed for exactly that reason.

**If you add a degrade path, it is the plain-flavour run that proves it.** Do not assume a green
Release CI job covered it.

---

## 6. Submitting a change

1. Write the gate, then the code.
2. Build both flavours locally; run `python3 test/pargates.py . ./build/ripwire -j 6` green.
3. Run the sanitizer build clean, and the determinism gate three times.
4. Add any new `test/*check.sh` to `test/regression.sh` in the same commit.
5. If your change alters emitted output, regenerate the goldens as their **own** commit with the
   diff reviewed by eye — never bundled with logic.
6. Keep formatting churn out of logic commits.

Scope each commit. A commit that touches one concern is a commit a reviewer can actually check.

By contributing you agree that your contributions are licensed under the project's `LICENSE`, and
that you will follow `CODE_OF_CONDUCT.md`. Security issues go through `SECURITY.md`, not the public
issue tracker.

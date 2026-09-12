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

**Memory, not cores, sizes `-j`.** `src/main.cpp` is one very large translation unit (since the
2026-08-29 split its verb families live in `src/verbs_*.h` sections included into that one TU — the
compile cost is unchanged, only the editing surface moved; `src/ingest.cpp` got the same treatment
the same day, its families in `src/ingest_*.h` sections). Compiling it
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

Gates share one checkout. **Never write into it**, not even for a moment: every stamped verb reads
`git status --porcelain` from any crawl root inside the checkout for its `at="…+dirty"` bit, so a
transient untracked file flips every determinism arm running beside you under `-j N`. Work in a
`mktemp` dir; if a copy genuinely has to sit beside a real gate, give it a name `.gitignore` hides
(`.gateprobe.*`). `test/pargates.py` samples that command while the suite runs and fails the run
naming the gate in flight. It is a sampler, so a clean run there is "none found", never "none exists".

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

### The failure mode that keeps coming back: an arm that cannot fail

A suite's verdict is a **conjunction over the arms that actually fired**. An arm that runs but
cannot reach a verdict is silently dropped from that conjunction while staying in the file — so
reading the file never finds it, and **the suite gets greener as it gets emptier**.

Six distinct routes to it have shipped or nearly shipped here. They look nothing alike in a diff:

| | shape | what it does |
| --- | --- | --- |
| 1 | **wrong population** | examines a set that cannot contain the defect (a pattern matching `std::vector` in a codebase whose containers are `HashMap`) |
| 2 | **wrong artifact** | correct check, aimed at the wrong input (a file-shaped `sed` range applied to diff output) |
| 3 | **empty equals agreement** | compares two extractions that both returned nothing; nothing matches nothing |
| 4 | **prose liveness** | the evidence the arm is live is in the commit message, not in the code |
| 5 | **no contrast** | a control whose two arms differ in nothing (a mutation that did not take; an arithmetic identity like `n+9 != n`) |
| 6 | **missing reporter** | the arm concludes but cannot record — it calls a helper the gate never defines, prints neither PASS nor FAIL, and the gate still exits 0 |
| 7 | **true but narrower** | the arm asserts a real property *strictly weaker* than its name implies, and is permanently green on the weaker one |

Shape 7 is the odd one and the reason it earns a row: nothing about it is broken. The determinism
gate runs the binary twice, the two runs genuinely differ, the comparison is real, the assertion is
true, and it has caught regressions. But it asserts **same argv → same file** while its name invites
**same argv → same picture** — and the emitted `LINKS` order turned out to decide the force-layout
above ~500 nodes, so a re-sort would change every picture with that gate green throughout. The arm
never leaves the conjunction; the conjunction just proves less than it appears to.

That makes the remedy different from shapes 1–6. Those are fixed by making the arm fire. This one is
fixed by asserting the missing property — or, where that is impossible, by naming the limit at the
place a reader will meet it. Watch for it especially when a gate's *name* is doing work its *code* is
not: "my arms do differ, so I am not shape 5" is exactly the reasoning that lets this one through.

Two older, narrower cases of the same thing, kept because they are cheap to check for:

- **A vanishing probe target** — an empty diff, a missing fixture, a keyword the fixture never
  spells. Add a presence guard: assert the thing you are about to search for exists, *then* assert
  the property.
- **A count that counts the wrong unit** — `grep -c` counts *lines*, not occurrences, so two hits on
  one line read as one. Anchor counts (`grep -c '^  PASS'`, never bare `grep -c PASS`), and reach
  for `grep -o | wc -l` when you mean occurrences.

**Care is not sufficient, and the record says so:** five of those six were introduced by someone who
already knew about the others, several while fixing one. So the rule is mechanical, not attentional:

1. **A control must mutate real input and re-run the identical extraction over it** — never compare
   fabricated numbers, and never assert a property of the mutation instead of of the check.
2. **Assert the mutation took** (`cmp -s`, or re-grep for the injected value) *before* trusting the
   outcome. A control over an unmutated copy passes and proves nothing.
3. **Prove the control fires from a `bash` script**, not from an interactive shell. The two are
   different interpreters with different tools on `PATH`, and the thing you validate interactively
   is not the thing that runs.
4. **Prefer an arm that has been observed RED.** An arm that has only ever been green has not been
   shown to have a failing state at all.
5. **When you fix an instance, remove the shape that produced it.** `test/prbudgetcheck.sh`'s Wave-45
   fix moved its diff into a scratch repo and left `ROOT` rebound to that fixture, so a line reading
   `( cd "$ROOT" && git checkout -- src/mod4.cpp )` stayed correct while looking exactly like the one
   that would revert a developer's working tree; two readers later took it for a writer (issue #71).
   A fix that leaves the shape leaves the next instance free.

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

### Output: `std::print`, feature-tested and disclosed — never a new printf-family site

- **Pick the primitive by what you actually have.** All three live in `src/infra/emit.h`; a same-shaped
  wrapper such as `lintPrintOut` / `lintPrintErr` in `src/verbs_lint.h` is fine too.

  | You have | Use |
  | --- | --- |
  | A format string **with arguments**, going to a stream | `rw::emitTo( stream, "…{}…", args )` |
  | **Literal text, no arguments** | `rw::emitRaw( stream, "…" )` |
  | A **caller-owned char buffer** | `rw::formatTo( buf, cap, "…{}…", args )` |

  `emitRaw` is not a stylistic alternative to `emitTo`: `std::format_string` is **consteval**, so literal
  text routed through `emitTo` pays compile-time format parsing for formatting that never happens — and
  the `--help` table, one 114,985-character literal, does not compile at all that way ("call to consteval
  function … is not a constant expression"). 353 sites in this tree pass a string and no arguments.
  `formatTo` exists for the same reason in the other direction: `std::format` into a `std::string` puts an
  allocation on `serialize.h`'s per-symbol path, which is a G2 regression, so buffer-targeted sites keep
  their stack buffer via `std::format_to_n`.
- **`rw::formatTo` reproduces `snprintf`'s contract exactly — do not hand-roll it with `format_to_n`.**
  `snprintf( p, S, … )` writes at most `S-1` characters **plus a NUL**; `std::format_to_n( p, S, … )` writes
  up to `S` and terminates nothing. Substituting one for the other buys a byte of buffer and drops the
  terminator. Measured 2026-09-09: that substitution made a symbol row emit `amp="1"` where every previous
  build truncated it away, with the whole parity fence green — the fixture never reaches the buffer.
- **Emit through `rw::emitTo` (`src/infra/emit.h`)**, or a same-shaped wrapper such as `lintPrintOut` /
  `lintPrintErr` in `src/verbs_lint.h`. That header is the ONE place the emitter is chosen: `std::print`
  where the standard library defines `__cpp_lib_print`, `std::format` rendered and written with
  `std::fputs` where it does not. The tree is printf-family by history, not by preference — ~1,500
  `fprintf`/`printf`/`snprintf` sites, 0 `std::cout` — and it is being converted; **no new printf-family
  call site** (rule landed 2026-09-08). Do not vendor `fmt`: the standard library has the feature, so a
  vendored copy is a G3 regression.
- **Why a feature test and not a bare `#include <print>`.** `<print>` is libstdc++ 14+; on libc++ it exists
  only at a macOS 14+ deployment target, and libc++ defines the feature macro only when the target admits
  it (measured 2026-09-08). Testing the macro means every toolchain BUILDS — which is why the choice is
  DISCLOSED: `--version` prints `emit=std::print` or `emit=std::format+fputs` (`test/versioncheck.sh` #6),
  every CI and release leg asserts `std::print` (gcc-14 on the ubuntu legs, gcc-toolset-14 on RHEL and the
  manylinux containers, Xcode 16.2 on macOS), and the `fallback-emitter` job builds the fallback arm with
  the stock ubuntu g++ 13 on purpose and proves it emits the same bytes. A silent fallback is the failure
  this whole arrangement exists to make impossible.
- **A conversion is byte-parity-fenced, not reviewed by eye.** `test/printffmtparitycheck.sh` hashes
  stdout and stderr per verb against `test/printf_parity.manifest`; a moved byte is a FAIL naming the verb
  and the stream. The trap it exists for is float rendering — `%g` prints six significant digits, `{}`
  prints the shortest round-trip (`0.3` versus `0.30000000000000004`) — so a per-specifier swap is never
  mechanical. Every emitted byte feeds G4, the determinism gate, and the stored captures.
- **The specifier mapping is measured. Use the measured one; do not extend it from memory.** 218 checks
  against printf on this toolchain found exactly ONE unsafe mapping, the bare `%g`/`%f` above:

  ```
  %s %u %d %zu %zd %lu %ld %llu %lld %i  ->  {}          %10s -> {:>10}   %-11s -> {:<11}
  %.*s (precision, pointer)              ->  {} with std::string_view( ptr, len )
  %016llx -> {:016x}   %llx -> {:x}   %llX -> {:X}   %o -> {:o}   %.9s -> {:.9}
  %.3f -> {:.3f}       %6.1f -> {:6.1f}   %.6g -> {:.6g}          (explicit precision ONLY)
  ```
- **A green fence is not coverage, and the fence cannot cover everything.** Two facts to hold together.
  First: `printffmtparitycheck` proves nothing about a verb it has no label for — add the label and pin it
  BEFORE converting, and note that pinning refuses any verb whose output embeds the git stamp (`at="<sha>"`),
  because such a verb's bytes move on the very commit that carries the pin. Second: even a covered verb
  reaches only the branches the fixture reaches — a coverage build measured 25% of one batch's call sites
  ever executed. For anything unfenceable or under-covered, **differential-test**: build the base commit
  into a scratch worktree and diff both binaries' bytes over `src/`, `test/`, `docs/` and the repo root,
  normalising only the stamp. A toy fixture cannot reach a truncation branch; a real tree does it by
  accident, which is how the `format_to_n` byte above was caught.
- **`std::print` throws on a failed write where `fputs` returns EOF.** `emitTo` catches that one
  `std::system_error` so both arms keep the contract every emitting site always had — a failed write is
  silent — rather than a `std::terminate` the fallback arm could never produce (§3 "Self-check, don't
  throw": a recoverable runtime error is a degrade, never a throw that escapes).
- **`%%` and braces invert in OPPOSITE directions when you convert.** A printf format spells a literal
  percent `%%`; text handed to `emitRaw` is no longer a format, so `%%` there prints TWO characters and must
  collapse to one `%`. Braces are the mirror image: `emitTo` needs `{{`/`}}` for a literal brace where
  `emitRaw` needs a bare `{`/`}`. JSON emitters are where the brace half bites.
- **Until a string is converted it is a printf FORMAT, not text.** The `--help` table in `src/cli.h` is one:
  a literal `%` in a help line is a conversion (`% /`, `% o` and `% c` all parse), and the generated
  `docs/COMMANDS.md` then carries garbage where the number was. Write `%%` there, and treat the regeneration
  arm (`test/docscommandscheck.sh` arm G) as the fence for that surface.

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
5. **Never edit the published gate count by hand.** After adding a gate — and again after any rebase
   or merge that moved the `for _g in …; do` loop — run `python3 docs/gatecount_build.py`. See below.
6. If your change alters emitted output, regenerate the goldens as their **own** commit with the
   diff reviewed by eye — never bundled with logic.
7. Keep formatting churn out of logic commits.

**The gate count is a build product.** It is stated in `README.md`, `docs/EVALS.md` and
`present/deck5_ripwire_build.js` — eight sites — and every one of them is written by
`docs/gatecount_build.py` from the single absorb loop in `test/regression.sh`, then gated by
`test/gatecountcheck.sh`. Hand-writing it is not a style preference: two lanes that each add one gate
both write N+1, git auto-merges the **identical** text clean, and the tree publishes N+1 against a loop
of N+2 with every existing check green (each branch's count matches its own loop, and the merged loop
matches main's — the member *sets* differ at the same number). That collided seven times in one night
on 2026-09-10. The merge recipe is therefore: **union the `for _g in …` sets, run the generator, done.**

Each published site carries a marker comment the generator owns — `<!-- gatecount -->` in markdown and
HTML (invisible when rendered), `// gatecount` in the deck's JavaScript. A count claim on a line
*without* that marker is a hand-written count, and the generator refuses the tree instead of leaving it
behind. Do not spell the marker inside a site file except at a real site.

Scope each commit. A commit that touches one concern is a commit a reviewer can actually check.

## 7. How we write

This applies to commit subjects, PR descriptions, issues, gate comments, `README.md` and the docs. It is
here because tone drifts every time someone rewrites a page, and drift in either direction costs us
contributors: too warm and vague reads as not competent, too cold and dense reads as a project nobody
wants to spend a Saturday on.

**Competence carries the fun.** The humour in this repo is not decoration laid on top of the engineering —
it comes from being unusually exact about something and then being light about it. Get the precision right
and the tone follows.

The reference for the voice is the commit log, not the front page:

> ``#if 0`` stopped serving calls and went on serving every other role
> twelve flag rows sat one indent too deep, so `--help` did not list every row
> `graph_unindexed=` shipped a number the document never defined

**Commit subjects say what was WRONG, not what you did.** "fix(help): twelve flag rows sat one indent too
deep" tells a reader in the log five months from now what the world was like before the commit.
"fix(help): change indentation" tells them nothing they cannot get from the diff.

**Let the number be the punchline.** `182,555 files. 194 s → 156 s.` An adjective on a strong number makes
it weaker — "blazingly fast" reads as though the writer does not trust the measurement. Declining to
embellish *is* the confidence.

**Deadpan the failures, especially ours.** "The gate that guards H2 reports PASS on H2." That sentence is
funny and damning at once, and it signals more competence than any claim of quality could: a project that
roasts its own bugs precisely is obviously run by people who find them. Never write a defect up as though
it were someone else's fault or a surprise.

**Rhythm, not exclamation marks.** Long sentence, then a short one. "Declined calls, derailed parses and
cut answers now say so. A zero means none found." The energy is in the cut.

**Attitude in the names, precision in the bodies.** "Rip'n Fast. Fewer Tokens. Better Code." earns its
swagger because every claim underneath it is measured and linked. Swagger plus receipts is fun; swagger
alone is marketing, receipts alone is a paper.

**Respect the reader rather than welcoming them.** "The research is done, the pointers are in the prompt,
and the prompt writes a plan and stops" recruits better than "we'd love your help!" — it says *your time is
worth something and we spent ours first*. Warmth that costs the writer nothing reads as filler; warmth that
shows up as prepared work reads as real.

Cut on sight: hedges (`we think maybe`, `a bit`, `somewhat`, `basically`), mission statements
("on a mission to revolutionize…"), exclamation marks after a claim, emoji standing in for a point of view,
and apologising for the age of the project. "Twelve weeks old and there is a lot worth doing" is confident;
"it's still early days, sorry!" is the same fact, badly told.

**The test.** Read a paragraph as two people: a skeptical staff engineer scanning for overclaim, and a
curious newcomer deciding whether this looks like a good weekend. Warm-and-vague loses the first;
cold-and-dense loses the second. A line like *"a zero means none found, never none exists"* wins both — it
is a precise contract and it has a point of view.

None of this licenses inaccuracy. Where this section and §2's honesty rules could ever disagree, the
honesty rules win and the sentence gets rewritten until it is both.

By contributing you agree that your contributions are licensed under the project's `LICENSE`, and
that you will follow `CODE_OF_CONDUCT.md`. Security issues go through `SECURITY.md`, not the public
issue tracker.

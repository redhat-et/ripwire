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
which compiles the `DISCLOSE( msg )` trace out. A gate that asserts a degrade path then goes blind and
passes for the wrong reason. See §5 for why CI builds both flavours.

### Sanitizer build (the G1 stack — required before you open a PR)

```bash
cmake -S . -B asan -DRIPWIRE_ASAN=ON && cmake --build asan -j
LSAN_OPTIONS=suppressions=lsan_suppressions.txt ./asan/ripwire <dir> >/dev/null
```

**macOS 26 with the Command Line Tools' AppleClang 17: ASan hangs before `main`.** Every
`-fsanitize=address` binary, even an empty `main`, hangs in ASan's start-up (shadow-memory set-up
walking the dyld shared cache), so each ASan gate just times out. CI's Xcode 26.6 AppleClang 21 is
not affected, and CMake warns when it sees the affected pair. Configure the sanitizer tree with
Homebrew LLVM 22 instead, linking its own libc++ so the headers and the dylib are one release
(Homebrew clang otherwise links the system libc++ against its libc++ 22 headers):

```bash
brew install llvm@22     # keg-only; nothing goes on PATH and /usr/bin/clang stays AppleClang
L=$(brew --prefix llvm@22)
cmake --fresh -S . -B asan -DRIPWIRE_ASAN=ON \
  -DCMAKE_C_COMPILER="$L/bin/clang" -DCMAKE_CXX_COMPILER="$L/bin/clang++" \
  -DCMAKE_EXE_LINKER_FLAGS="-L$L/lib/c++ -L$L/lib/unwind -lunwind -Wl,-rpath,$L/lib/c++ -Wl,-rpath,$L/lib/unwind"
cmake --build asan -j
otool -L asan/ripwire    # expect llvm@22's libc++, libunwind and libclang_rt.asan_osx_dynamic.dylib
```

Name `llvm@22`, not `llvm`: the unversioned keg moves to a new major on `brew upgrade`, and an older
one may still be installed. `--fresh` makes the switch explicit when `asan/` was first configured with
AppleClang; without it CMake sees the compiler change, warns, and discards the old cache on its own. The
directory stays `asan/`, because the gates and `test/regression.sh` look for `asan/ripwire`. Gates that
compile their own sanitizer harness take the compiler from `CXX` (strkerncheck's CMake leg also reads `CC`
and `LDFLAGS`), so export
`CC="$L/bin/clang" CXX="$L/bin/clang++" LDFLAGS="<the linker flags above>"` before running them.
Keep that environment to the ASan gates: a gate that checks `$CXX` against the compiler that built
`build/ripwire` (noaliascheck) goes red under it, so run the plain gates from a shell without it.
With libc++ 22, oswin32logiccheck arm (B) stops on an `-fsanitize=integer` report inside libc++'s own
`<string>` (`__grow_by` stores `-1` into `size_type` on purpose). That is the toolchain, not ripwire.

### Stale objects — the build that reports success and is wrong

Make decides what to recompile by comparing timestamps, and header tracking in this tree is correct
and complete. But a timestamp only means something if the sources hold still. Edit `src/model.h` — or
`git checkout` a branch that does — **while a build is in flight**, and that build writes object
files whose mtime is newer than the header but whose content predates it. Make then correctly
concludes "up to date" and never recompiles them again. `cmake --build build -j` reports success,
exit 0, no warnings, for as long as you keep trying.

So: **never edit the tree while a build is running, and never background a build you then edit
around.** After a branch switch, or whenever you are unsure, do not trust an incremental rebuild:

```bash
cmake --build build --clean-first -j          # and the same for asan/, if that tree is in play
```

Three ways this has been hit, so you can recognise the symptom instead of debugging the wrong bug:

- **A sanitizer report of a bug that does not exist.** Half the objects had `sizeof(Symbol)==96` and
  half `104`, and ASan reported a heap-buffer-overflow in `ingest`. The tell was the region size:
  1344 bytes = 14 × 96, an exact multiple of the *previous* struct size. If a report's region
  divides evenly by an old `sizeof`, stop debugging and rebuild.
- **A mirrored constant that would not update.** `src/quality.h`'s `kIngestParserVerMirror` was
  edited while a clean rebuild ran. The binary kept emitting the old value through repeated
  successful rebuilds, and `qextractionkeycheck` failed as though the mirror update had been missed.
  `touch`ing the header fixed it — which is the diagnosis, not the fix: the object was newer than
  the source it disagreed with.
- **An impossible `std::length_error`.** SIGABRT out of a `resize( symbols.size() )`, where `.size()`
  came from a vector whose element size half the objects disagree on. Zero repro in 38 runs on a
  clean rebuild of the same commit.

`test/g1freshcheck.sh` catches the ordinary stale binary — one older than its sources — and is worth
believing when it fires. It cannot catch this variant, because here the binary is *newer* than the
source and only its contents are stale. Nothing in CMake can repair a source that changed
mid-compile; the discipline is the fix.

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
path on a Mac with `cmake -S . -B build-nokqueue -DCMAKE_CXX_FLAGS=-DRW_OS_HAS_KQUEUE=0` (the seam lives in
`src/infra/os.h`, which may not name the project, so it is spelled `RW_OS_`).

### Determinism gate

Output is a sorted top-K. A sort has no tolerance band, so the contract is byte-identity:

```bash
t=$(mktemp -d); ./build/ripwire <dir> >"$t/a"; ./build/ripwire <dir> >"$t/b"; diff -q "$t/a" "$t/b"
```

Write the two outputs OUTSIDE `<dir>`. Written inside it, the second run crawls the first run's output
file, a new unindexed text file, and the `unindexed=` histogram can change between the two runs (#334).

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

### Selecting which gates to run for a change smaller than the full suite

A lane or PR does not run the full suite locally — but "which subset" is not "grep for the verb you
changed". Gate selection by VERB NAME under-covers; four classes of gate are invisible to it (found the
hard way, across several trains, each time by a gate the verb-grep never reached):

1. **Language-fixture gates.** A change to extraction, ingest or the call graph can move a fixture's
   count without the gate naming any verb you touched. Do not enumerate fixtures by name — ask the
   binary which ones your change can move, then run the gate that owns each:
   ```bash
   for d in test/*fix; do "$BIN" "$d" --no-cache '--graph-query=<the property you changed>' \
       | grep -q 'count="[1-9]' && echo "$d"; done
   # each hit's gate is test/<basename-minus-fix>check.sh, plus the cross-language gates that own no
   # fixture of their own: langcensuscheck qualnewcheck callformcheck
   ```
2. **Source- and docs-grepping gates.** A gate that reads a header's text directly (an enum's member
   list, a constant, a hardcoded roster meant to track one) has no verb and no fixture — it has a
   filename. Run every gate that names a file your change touched, over the FULL merge/PR diff, not
   just the files the last fix round happened to edit:
   ```bash
   git diff --name-only <base>...HEAD -- 'src/*' | while read f; do grep -l "$(basename "$f")" test/*.sh; done | sort -u
   ```
   A gate keyed on an enum (a shape roster indexed by `SymKind`, say) is this class, not a fifth one:
   the header that declares the enum has a name, and the sweep above finds any gate that greps it.
3. **Shard-placed gates.** A gate's CI shard says where it runs, never what it covers — do not let
   "that runs on a shard I don't usually watch" stand in for "out of scope". `portablebuildcheck` is
   the standing example: a whole-`src/` sweep with no fixture, no verb and no per-language list, so it
   is invisible to every selection method except clause 2's file sweep above (it greps `src/`
   wholesale). Run clause 2's sweep and trust it over a mental model of "what usually catches this".
4. **Run the sweep, don't just write it down.** Writing the rule is not running it: clause 2's command
   has been reasoned about and then skipped in the same round it was proposed, because it was run over
   the files edited in the latest fix rather than over the whole change. Run it over the FULL base...HEAD
   (or merge) file list before calling a round done — on a change that touches a widely-`#include`d
   header this can be most of the suite (hundreds of gates), and that size is the honest answer, not a
   sign to narrow the query: run the local intersection this sweep names and let CI carry the rest, but
   never conclude "no gate covers this" without having actually run the command.

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

**clang-tidy's broad report is advisory, and must stay that way; one narrow subset gates.**
`.clang-tidy` carries an empty `WarningsAsErrors`, CI runs it with `continue-on-error`, and the config
is curated down to `bugprone-*` / `clang-analyzer-*` / `performance-*` / `misc-dangling-*` /
`misc-redundant-expression`. Its default catalogue argues for a different C++ than the data-oriented one
§3 and G2 mandate — POD and SoA, C arrays, 32-bit handles, `ASSUME` instead of exceptions — so read its
output as a to-triage list, never as a queue of defects.

The exception is `scripts/tidycheck.sh`, a separate CI step with `--warnings-as-errors='*'`. It runs
only checks whose every finding is a silently wrong answer and that sat at **zero rows** on the five CI
TUs when admitted (0.6.3, clang-tidy 22; `bugprone-use-after-move` had one row, brought to zero by a
behaviour-neutral fix that `.clang-tidy` describes): `bugprone-use-after-move`, `bugprone-dangling-handle`,
`bugprone-sizeof-expression`, `bugprone-integer-division`, `bugprone-infinite-loop` and
`clang-analyzer-core.*`. It is a ratchet, not a style gate: a new row is a
bug to fix, never a `NOLINT`, and a gated check that proves noisy leaves the list with its count, the way
it came in (`.clang-tidy`'s header has the counts, and the candidates that stayed out or left). Run it
before a PR that touches C++: `scripts/tidycheck.sh` finds clang-tidy 22 on `PATH` or, on macOS, at
Homebrew's keg-only `/opt/homebrew/opt/llvm@22/bin/clang-tidy` — pin that path, not
`/opt/homebrew/opt/llvm`, which may be another major — and prints a `SKIP` line (not a pass) when it
finds neither.

The compiler holds the same line for the UB class: CMakeLists.txt's compile-time fence block makes
`return-type`, `uninitialized`, `format`/`format-security`, returning a local's address, and on Clang
`-Wdangling` and constant `array-bounds`, errors on our own targets, per compiler, with the cl.exe
`/we####` equivalents — each measured at zero hits on AppleClang 17, clang 22 and GCC 13/14/16 first.

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

Self-checking is this codebase's primary correctness mechanism, ahead of tests: a check at an invariant runs on
every input the tool ever sees, costs nothing in release, and tells the optimizer a fact. **Add them freely.**
`test/selfcheckcheck.sh` objects only to:
- a side effect inside a check;
- a call it has never seen inside a promise (one line in its ALLOW table, once);
- `ASSUME( false )`;
- external input handed to anything but `VALIDATE`;
- a new one-argument `DISCLOSE`;
- an `answerUnchanged` without a reason.

| word | promises | release | use for | never for |
| --- | --- | --- | --- | --- |
| `ASSUME( e[, "why"] )` | e holds because THIS code makes it hold | not evaluated; the optimizer may rely on it | invariants, indices you bounded, sizes you set | argv, files, git, sockets, the environment |
| `EXPECTS( e[, "why"] )` | the caller met this function's contract | as ASSUME | preconditions; the report blames the caller | a boundary whose callers you do not control (VALIDATE) |
| `ENSURES( e[, "why"] )` | this function met its own contract | as ASSUME | postconditions before a return | anything the caller can still change |
| `DASSERT( e[, "why"] )` | nothing: debug-only check | nothing, not evaluated | expensive or floating-point checks; corruptible structure (`verifyCsr`) | facts the optimizer should have |
| `ASSUME_NO_ALIAS( a, b )` / `3` / `_BUF` | separate allocations | separate_storage fact | out-params and read/write pairs of one type | views; members of one struct; elements of one array |
| `ASSUME_SAME_THREAD()` | this SITE runs on one thread | nothing | process singletons (the MCP index) | a body pool workers reach on different objects |
| `ASSUME_SAME_THREAD_AS( obj )` | obj is touched only by its owner (`release()` hands it on) | nothing, no storage | worker result slots, prefetch results | lock-protected state; per-node records |
| `UNREACHABLE( ["why"] )` | control never arrives here | `__builtin_unreachable()` | exhaustive `switch` defaults | a path bad input can reach |
| `VALIDATE( e[, "why"] )` | nothing: e is external input | evaluated, one compare | the condition of the refusing or degrading `if` | invariants |
| `DISCLOSE( sink, why[, "msg"] )` | the answer carries its incompleteness | `sink.disclose( why )` runs | every degrade: the sink is the struct whose field the emitter reads; `why` is its own scoped enum | — |
| `DISCLOSE( Diagnostics::answerUnchanged, "reason" )` | this degrade changes cost, never content | nothing, but the reason is listed by the gate | a rejected or unwritable cache, a same-bytes fallback, a lock skipped under a re-check | dropped/truncated/guessed rows, stored partial facts, refusals, unreachable guards |
| `DISCLOSE( Diagnostics::answerRefused, "reason" )` | this degrade refuses the answer by name | nothing, but the reason is listed by the gate | a path that, in every build, prints no answer and says why (non-zero exit + stderr, an MCP error, a query's named failure) | anything that still prints part of an answer |
| `DISCLOSE( "msg" )` | **nothing to the user**: a debug trace | nothing | existing sites only, until converted (ratchet) | any new degrade |
| `PANIC( "why" )` | we cannot continue | report and abort | a corrupt state | anything recoverable |

**The error ladder:**
- A **recoverable** runtime error (an unreadable file, a full pool, a missing grammar) is a **degrade**, not a
  failure. Return `nullptr` / `false` / empty / a clamped value, **tell the reader in the document**, and keep
  going. The whole pipeline must survive a malformed repo.
  - Write `DISCLOSE( sink, Sink::DisclosureWhy::Reason[, "subsystem: condition — consequence"] )`. The sink is the
    object whose field the emitter already reads (`complete=`, `ok="0"`, `why=`, `*_capped="1"`, `counts_floor="1"`,
    an omitted `est_tokens=`); give it a scoped `DisclosureWhy` and a `noexcept` `disclose()` that sets that field.
    The compiler checks the contract.
  - `docs/ARCHITECTURE.md`: "A disclosure that lives only in an assertion is a disclosure that does not ship."
  - If the degrade genuinely cannot change this answer (a cache rejected and rebuilt, a cache write that only
    makes the next run cold), write `DISCLOSE( Diagnostics::answerUnchanged, "why this answer is unchanged" )`.
    If it REFUSES the answer — no document at all, and the cause named where the caller reads it (stderr with a
    non-zero exit, an MCP error, a query's named failure) — write `DISCLOSE( Diagnostics::answerRefused, "how" )`.
    The gate prints both kinds of reason on every run. Neither is for a path that still prints an answer: if any
    answer goes out, it needs a real sink, and if the document has no field for the fact yet, ADD one (absent on the
    happy path, defined in the same document's legend and in `compactlegend.h`) — never leave the degrade to the trace.
  - The one-argument `DISCLOSE( msg )` is a debug trace that ships nothing. It remains only on sites not yet
    converted, and `test/selfcheckcheck.sh` refuses a new one (arm R: the count may only go down), and arm S proves
    the sink form still records in an `-O2 -DNDEBUG` build — the flavour users run.
- **External input** is checked with `VALIDATE` in the condition of the refusal, never `ASSUME`d.
- A **corrupt invariant** is a `PANIC`.
- **Never `ASSUME( false )` (or an `EXPECTS`/`ENSURES` of false) on a degrade path.** In release the assert
  compiles away and the optimizer deletes the fallback behind it — that is a real shipped-bug shape, not a
  hypothetical. Guard, don't assert.
- Throw only at the `operator new` seam. A throw escaping a worker thread is `std::terminate`, so
  wrap thread bodies in `try { … } catch( ... ) { … }`.
- **Avoid exception handling. Where a throw is unavoidable, RAII is what makes the code exception-safe:
  cleanup belongs in a destructor, never in a `catch`.** A handler that releases a resource has to know
  which resources are live at the point the throw happened, so such handlers multiply — two throw sites
  in one function own different things and need different teardown, and the handler is only correct
  until someone adds an early `return` above it. One owner whose destructor releases what it holds
  collapses that to a single handler whose only job is the conversion this codebase actually wants: a
  recoverable error becomes a degrade, returned, never propagated. Measured on `216802ad`, 2026-09-14:
  of 27 `catch` blocks under `src/`, exactly one released a resource by hand — `infra/emit.h`'s
  `renderToString`, which `fclose`d a memstream and `free`d its buffer. Re-derived after that buffer
  moved into `rw::MemoryStream` (2026-09-16, `lane/compile-time-checks`): **26 `catch` blocks, and none
  releases a resource by hand** — `renderToString`'s two handlers now leave the stream and its buffer to
  the owner's destructor. Every handler converts a throw into a degrade, sets a flag, returns a message,
  or `continue`s; they own nothing, which is why they are one line each. Re-derive rather than trust: a
  bare `grep -cE '\bcatch[[:space:]]*\('` over `src/` reports **34** there, and 8 of those hits are the
  word inside a `//` comment or inside a tree-sitter query string — most of them in `lintrules.h`, whose
  subject is *detecting* empty catch blocks in other people's code. Exclude comment and string context, then read each surviving handler's first body
  line, because the resource question is answered by reading it and not by counting.

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

### Operating-system calls: call sites never ask which OS they are on

**Call sites never ask which OS they are on; they call the `rw::os` function that says what they need.**
`src/infra/os.h` is the one file in `src/` that tests an operating system: every `#if` naming one, every feature
macro that is really an OS test (`MSG_NOSIGNAL`, `SO_NOSIGPIPE`, the kqueue seam), every POSIX or Windows system
header, and every call whose behaviour differs by platform. A call site reads like Unix code with a prefix —
`os::lstat( path, &st )`, `os::rename( tmp, dst )`, `os::flock( fd, LOCK_EX )`, `os::stat_t` — with POSIX names,
POSIX signatures and the POSIX errno contract, and it asks nothing about the platform: no `#if`, and no platform
fact (`os::kWindows`, `os::kApple`) in a plain `if` either — those are for `os.h`'s own use. Each POSIX body is the
libc call itself, `[[gnu::always_inline]]`, over the call's own raw types (no copy, no errno translation, no extra
syscall), so a release binary carries no out-of-line `rw::os` symbol; where no POSIX call says what a site needs
(`os::exepath`, `os::dirwatch_open`), the helper is lowercase and C-shaped, its POSIX body is the code that used to
sit at the site, and its shape keeps that code's evaluation order — a read stays on its side of a `fork` — so the
caller compiles to the same instructions. Check that with a release build of the base commit and `objdump -d`, not
by reading. Inside `os.h`, `#if` is kept for what does not exist on the other platform — a header, an
API or type, a field spelled differently (`st_mtimespec`/`st_mtim`) — while pure logic selects on the facts with
`if constexpr`, so both branches are type-checked on every CI leg and the non-native one cannot rot. **The naming
gotcha:** a POSIX name that some libc defines as a *function-like macro* cannot be wrapped by its own name, because
the declaration and every `os::name(` call expand before the compiler sees a function — `S_ISREG( m )`,
`S_ISLNK( m )` and the other mode predicates everywhere, and `htons` under glibc at `-O2`. Those stay bare at call
sites, like the `O_*`/`X_OK`/`PATH_MAX` constants, and `os.h`'s Windows branch defines them. `test/osswitchcheck.sh`
refuses all of the above outside `os.h`; its allowlisted files are `src/infra/profilePmc.h`, the profiler's
undocumented-ABI counter backends, and `src/infra/os_win32.cpp`.

**Windows bodies live out of line.** `os.h`'s Windows branch only *declares* — the same names, POSIX constants,
types and `stat` fields its POSIX branch uses — so `<windows.h>` never reaches a call site. The definitions are in
`src/infra/os_win32.cpp`, which CMake compiles only for a Windows target (`cmake/Windows.cmake`), and they keep the
POSIX contract their callers read: errno, `-1`, `struct stat` fields (`st_dev`/`st_ino` identify a file; `lstat`
reports `S_IFLNK` for a symlink or junction; `O_NOFOLLOW` judges the final component). Every kernel object there
has one RAII owner, and nothing throws. Anything in that port that is not a Win32 call — the Win32→errno table,
UTF-8/UTF-16 conversion, path spelling, `CreateProcessW` quoting, reparse-tag and wait-status decoding — belongs in
`src/infra/os_win32_logic.h`, a header with no `<windows.h>` and no platform test, so that every CI leg compiles
it and `test/oswin32logiccheck.sh` tests it. Paths are `/`-separated inside the program: Windows spells them once
where they enter (`os::init_process` for argv and the environment, `os::normalize_path_arg` for a path-valued
flag or MCP argument), never at a comparison. The three questions whose answer depends on drives existing have
`os::` names of their own — `os::path_is_absolute`, `os::path_is_root`, and `os::program_path( fs::path )` for a
path the program generated itself (the crawl) — and each POSIX body is the expression the call site used to hold.

**Platforms.** Unix, Linux and macOS come first; native Windows is second, with clang-cl the primary compiler and
MSVC `cl.exe` also required to build. A `cl.exe` portability problem is worth fixing, but it does not block a change
to a POSIX-only code path. **Both now build and both gate**: the `windows` CI job builds with clang-cl and with
cl.exe on every full matrix, and each leg runs the binary, runs `ctest`, and checks the two-run byte-identical
contract and well-formedness. The GCC/Clang language extensions this tree uses go through the seam in
`src/infra/platform.h` (and, for the layer below it, `src/infra/Diagnostics.h` §1c); `test/osswitchcheck.sh` arm H
refuses a new `__builtin_*`, inline asm or `__attribute__` outside that pair, so a Windows break is caught on every
POSIX leg rather than discovered on Windows.

A green Windows matrix is **not** the same as a validated platform. The 649-gate suite does not run there — it needs
the harness on #44 — and the ASan flavour is compiled on Windows but never executed.

The **windows-x64 release zip** (a preview from 0.6.3) is built by `.github/workflows/windows-package.yml`, which
`release.yml` and `ci.yml` both call, so every full-matrix run uploads the zip a tag would publish. Its header lists
the design choices (clang-cl, Release, static CRT `/MT`, no PGO) and the checks on the unzipped exe; `xplat-diff`
then compares `scripts/ci-xplat-outputs.sh`'s verb set between that exe and the Linux binary under the rules
`scripts/ci-xplat-diff.sh` names. A change that makes the two differ is a Windows bug until shown otherwise.

### Aliasing: spelling, placement, contract

- **Spelling: `__restrict__` only, never `__restrict`.** On macOS, `<sys/cdefs.h>` does
  `#if __STDC_VERSION__ < 199901` / `#define __restrict` (empty), and `__STDC_VERSION__` is
  undefined in C++, so every `__restrict` that follows any libc/libc++ include is silently deleted.
  `__restrict__` is a keyword, not a macro, and survives.
- **Prefer `ASSUME_NO_ALIAS( a, b )` (objects) or `ASSUME_NO_ALIAS_BUF( a, b )` (OWNING containers only: `std::vector`, `std::string`, `std::array`) in
  the body over a qualifier on the signature.** For a container, the promise has to land on
  `.data()` — on the objects themselves it is inert for the loop, because the optimizer reaches the
  heap buffer through a pointer loaded from the header, not through the header's own address. Never a
  view: two `std::span` or `std::string_view` objects can look into ONE allocation, and the promise is per
  allocation, so the macro refuses them at compile time — promise the owners they came from. Place
  the macro at the top of the function, before the first load or store through either argument; if the
  function already has a "nothing to do" early return on empty input, put it after that return, so the
  promise is never made on a null `.data()` (measured: same loop effect, plus only the emptiness test the
  function paid for anyway). Do not add an early return for the macro's sake — the one line is the full
  effect, and two empty containers are a vacuous promise, not a broken one.
  Three reasons, one each: it is checked in debug and is the same optimizer fact in release
  (`__builtin_assume_separate_storage`) on compilers that consume it — clang 18+ by default, LLVM 17 /
  AppleClang 16 only with the `-mllvm -basic-aa-separate-storage` that CMake adds when the compiler
  accepts it (and there only for scalar accesses, not the loop vectorizer), GCC and clang before 17
  not at all, where the release expansion is `( (void)0 )` and only the debug check runs; it does not
  change the API; `__builtin_assume( &a != &b )` is NOT that fact — alias analysis never reads it.
- **The contract is different complete allocations, not different addresses.** Verbatim from
  clang's `LanguageExtensions.rst`: the arguments "are assumed to point into separately allocated
  storage (either different variable definitions or different dynamic storage allocations) …
  'storage' here refers to the outermost enclosing allocation of any particular object (so for
  example, it's never correct to call this function passing the addresses of fields in the same
  struct, elements of the same array, etc.)". Two elements of one array or two members of one
  struct are undefined behaviour, not a stricter case of the promise. Locals allocated inside the
  function are already known-distinct to the optimizer; the macro is for parameters and members —
  and only for parameters/members of the *same element type*, since different types are already
  separated by TBAA.

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
  manylinux containers, Xcode 26.6 on macOS), and the `fallback-emitter` job builds the fallback arm with
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
- **G4 — maximum token density.** Minified XML, no inter-tag whitespace, terse attributes. The legend is emitted
  once per answer on the CLI (`--legend=full|compact`) or once per session on agent surfaces (`--legend=ref`,
  served only after the session dictionary was delivered in that process; the answer then ends with
  `<about … legend="ref" dict= dictv=/>`). Every attribute a default answer emits is defined in that answer's own
  legend — gates `legendcoveragecheck` (G) and `compactlegendcheck` (UG); a ref answer carries the same attributes
  as its inline twin, and every definition it leans on is bytes that session was already sent or that the answer
  carries itself — gate `legendrefcheck`. Output pipes clean through `xmllint --noout`; no newline outside CDATA.
- **G5 — modular zero-dependency CLI.** Hand-rolled argument parser. A default run with no flags is
  the core map; every flag is purely additive and gated by a `Config` field.

---

## 5. The two build flavours (why CI builds twice)

CI builds and runs the whole suite **twice**: once as `Release`, once with the plain (no build
type) configuration.

Both are load-bearing, and the reason is a real regression this project shipped:

- **Release catches optimizer-only bugs** — code that is correct at `-O0` and wrong once
  `__builtin_assume` and inlining are in play, including the "assert it, then defend against it"
  trap where an `ASSUME` lets the optimizer delete the defensive branch that follows.
- **The plain build catches degrade paths** — the `DISCLOSE( msg )` trace is compiled out under `NDEBUG`,
  so a Release-only suite cannot observe the alert that a degrade-path gate asserts. For three
  development cycles, every degrade-path gate in CI passed for exactly that reason.

**If you add a degrade path, it is the plain-flavour run that proves it.** Do not assume a green
Release CI job covered it.

### Light set vs. full matrix

`.github/workflows/ci.yml` does not run the full 31-job matrix on every event. A `plan` job computes one
`full` output from the event name, the pull request's labels and the ref, and every heavy job reads that
output (fallback-emitter/rhel/asan through `if:`, `release` through the matrix `plan` itself computes,
since a job-level `if:` cannot see the matrix context).

- **Push to `main`**, and **pull requests carrying the `train-member` label** (maintainer-only — a fork
  PR cannot label its own PR), run the **light set**: the `style` job plus the single
  `ubuntu-24.04`/`Release`/`clang` release leg (all 4 gate shards), which already includes the
  determinism and G4 XML checks.
- **Every other pull request** (`integration/*` train PRs, direct-land PRs, contributor PRs),
  **`workflow_dispatch`**, and a nightly **`schedule`** (05:41 UTC — off `:00`, and a different minute
  from `nightly.yml`'s own 07:17 TSan run) all run the **full matrix**. Always dispatch a full run against
  the exact commit you are about to tag; a green light-set push or an earlier nightly does not stand in
  for it.

A failure on the scheduled full-matrix run opens or updates `ci.yml`'s OWN tracking issue, titled "Nightly
checks failing on main (full matrix)". It is a separate issue from `nightly.yml`'s TSan one, on purpose:
every tracking issue carries the shared `nightly-failure` label (so "every nightly-scale failure" is one
query) plus a workflow-specific second label — `nightly-full-matrix` here, `nightly-tsan` in
`nightly.yml` — and every open/comment/close filters on BOTH labels together. Before this split the two
workflows shared one issue and each had its own green-schedule job closing it on its OWN verdict alone;
a green TSan night could close an issue the full matrix had opened while the matrix was still red, and
the reverse. With two labels and two issues, a green run in one workflow can only ever touch the issue
carrying its own second label, so it can no longer close the other workflow's still-open failure.

### What runs nightly instead of on every pull request

`.github/workflows/nightly.yml` runs the slower checks once a day, at 07:17 UTC, against `main`. Today
that is a ThreadSanitizer build (`-DRIPWIRE_TSAN=ON`) and the gates that drive ripwire's threads: the
MCP prefetch worker, the edit lock, a long-lived server's re-ingest, concurrent `--quality-ack` writers, the parallel
ingest and `--match` fan-out, `--grep`'s prefetch thread, the `--doc-drift` workers and the git-spawn
pool. Each gate runs through a wrapper that fails on a non-zero exit or on any TSan report file, and the
job first proves that check can fail: a planted race must be reported and its race-free twin must not.

It is not a per-PR leg on purpose. TSan builds already run often on contributors' and maintainers' own
machines, and every PR already waits on the macOS runners, so a TSan leg on each push would cost more
CI than it adds coverage. What a local run cannot promise is that someone ran it on what is actually on
`main` before a tag, and once a day covers that. A scheduled run skips the heavy jobs when `main` has
not moved since the last green scheduled run and no open issue carries BOTH `nightly-failure` and
`nightly-tsan` — this workflow's own tracking issue, not `ci.yml`'s full-matrix one; while it is open,
every scheduled run checks again.

**Where failures appear:** the workflow's run in the Actions tab, and one issue titled "Nightly checks
failing on main (TSan)" (labels `nightly-failure` and `nightly-tsan`). A failing night on `main` opens
it, or comments on it if it is already open, with the failing jobs and steps, the commit, the run link
and the head of the first TSan report. The next green scheduled run comments "green again at <sha>" and
closes it — and only it: `ci.yml`'s full-matrix schedule keeps its own separate issue (see "Light set vs.
full matrix" above), so this job never closes that one, and a green TSan night is never mistaken for a
green full-matrix night. A pull request that edits the workflow runs it too, without the issue reporting.
To reproduce a TSan failure locally, route the reports to files the way the job does, because many gates
discard the server's stderr:

```bash
cmake -S . -B tsan -DRIPWIRE_TSAN=ON && cmake --build tsan -j
TSAN_OPTIONS=halt_on_error=1:log_path=/tmp/tsanlog RIPWIRE_BIN=tsan/ripwire bash test/qsnapprefetchcheck.sh
ls /tmp/tsanlog.*     # one file per process that raced; none means no report
```

---

## 6. Submitting a change

1. Write the gate, then the code.
2. Build both flavours locally; run `python3 test/pargates.py . ./build/ripwire -j 6` green.
3. Run the sanitizer build clean, and the determinism gate three times.
4. Add any new `test/*check.sh` to `test/regression.sh` in the same commit — but first check
   whether a gate already owns the subject and can take another arm. A new gate file forces a
   `docs/gatecount_build.py` regeneration that collides with every other open lane; a new arm
   in an existing gate costs nothing outside its own file.
5. **Never edit the published gate count by hand.** After adding a gate — and again after any rebase
   or merge that moved the `for _g in …; do` loop — run `python3 docs/gatecount_build.py`. See below.
6. If your change alters emitted output, regenerate the goldens as their **own** commit with the
   diff reviewed by eye — never bundled with logic.
7. Keep formatting churn out of logic commits.
8. **Cutting a release:** bump the version in `CMakeLists.txt`'s `project()` call, rename
   `CHANGELOG.md`'s `## [Unreleased]` section to the new version, and add the release's blurb to
   README.md's `## Release notes` section (newest first, with a `Thanks to` line where one applies) —
   never to a `## What's new` section, which no longer exists (moved 2026-09-25; see git history if
   you are looking for it). Update the one-line **Latest: 0.6.x** pointer near the top of README.md to
   match.

**The gate count is a build product.** It is stated in `README.md`, `docs/EVALS.md` and
`present/deck5_ripwire_build.js` — eight sites — and every one of them is written by
`docs/gatecount_build.py` from the single absorb loop in `test/regression.sh`, then gated by
`test/gatecountcheck.sh`. Hand-writing it is not a style preference. Two lanes that each add one gate
both write N+1, and git auto-merges that **identical** text clean in all three files — only the
`for _g in …` loop conflicts, so the loop is the only place anyone is forced to look. That collided
seven times in one night on 2026-09-10. The merge recipe is therefore: **union the `for _g in …` sets,
run the generator (no `--check`, so it WRITES), then `--check` it. Never hand-write the number and
never trust the clean auto-merge of the three published files.**

WHAT CATCHES A BOTCHED RESOLUTION, measured on this tree 2026-09-13 rather than assumed, because the two
ways to botch it are caught by *different* gates and neither is caught by both:

| botched how | the tree then has | red on |
| --- | --- | --- |
| loop unioned, generator not re-run | loop N+2, the eight sites N+1 | `gatecountcheck` (B), `manifestcheck`, `readmedriftcheck` (F2) — `deckclaimcheck` passes, but the deck's three sites are three of the eight `gatecountcheck` owns |
| one side of the loop taken instead of the union | loop N+1 and self-consistent, but a gate FILE present that the loop never names | `manifestcheck` only (`gatecountcheck` passes: the count really is consistent, and the generator has nothing to say) |

So the count is fail-closed **provided the full suite runs** — which is why the suite before every push
is not negotiable. An earlier revision of this paragraph claimed the first row went green on every
existing check; that was true when it was written and is not true now, and a stale claim that a defect
is ungated costs more than the defect, because it sends people to build process around something three
gates already cover.

**An advertised count is an enumeration, not a sentence.** Every number this project prints about
itself — flags, gates, skills, folded repositories, orchestrator prompts — is derived from something
countable in the tree and pinned by an arm in `test/readmedriftcheck.sh`. Before writing a number
into prose, ask which command produces it. And **if a set can be counted more than one way, the
prose must say which set it counts**: `skills/` is 17 routable skills (`skills/*/SKILL.md`), 18
`SKILL.md` files in all (`skills/hermes/` holds a Hermes-native one), and 16 activated for every
agent (`ripwire-opt-remarks` is `audience: contributor`). All three are correct answers to "how many
skills are there", which is precisely why README.md carried two of them at once, unlabelled, until
arm (J) was written.

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

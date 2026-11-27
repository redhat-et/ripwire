# Add Scala to ripwire — the third JVM language

You are adding **Scala** to ripwire and joining it to the call graph that Java and Kotlin already
share. This is a full language round — a vendored grammar, extraction, disclosed blind spots, a
red-first gate — plus one resolver change that comes with an invariant that must not bend.

> **Builds on PR #126 (Kotlin support, by @xCatG), merged 2026-09-11, and on #157's shared nesting
> guard.** The JVM bridge this prompt extends — the `edgeFamily` column in `src/langfacts.h` that
> `langCompatible` reads, `keepOwnJvmLanguageCandidates` and the per-family decl/def collapse in
> `src/graph.h` — came with #126 and has since moved into the facts table. Status 2026-11-26: #159 is
> open with no claim, and nothing under `src/` mentions Scala. Line numbers drift; the function names
> are the pointers.

**Read `prompts/add-a-language.md` first and follow it step by step.** This prompt does not repeat
its file list. It adds what is specific to Scala and to the JVM bridge, and it overrides nothing.

Work in a git worktree, not your main checkout. Run every gate in the foreground.

**Orient first.** Before opening files, run
`./build/ripwire . --for="JVM bridge langCompatible keepOwnJvmLanguageCandidates collapseDeclarationsOfName Kotlin Java"`
and `--for="register a new tree-sitter language: Lang enum, kLangTable row, kLangFacts row, tags.scm"`.
Before writing the gate or a helper, `--exemplar="<what you are writing>"`; `test/kotlincheck.sh` is
the likely answer for the gate. Before calling a round done, `./build/ripwire . --quality-delta
--legend=compact`, then `--test-gate`.

---

## Why this matters

Scala carries some of the most depended-upon JVM systems there are, and ripwire cannot see a line of
it. On main a `.scala` file is a `--skipped` row with `why="unsupported-ext"`: absent from the map,
from `--callers`, from `--for`, from every verb (see "Reproduce the gap"). Nothing under `src/`
mentions Scala.

GitHub's language breakdown for the codebases this opens up, read 2026-09-11 (bytes of source as
GitHub counts them, not file counts):

| Repository | License | Scala | Java |
| --- | --- | --- | --- |
| apache/spark | Apache-2.0 | 79.5 MB | 7.4 MB |
| scala/scala3 | Apache-2.0 | 32.1 MB | 0.4 MB |
| apache/pekko | Apache-2.0 | 19.6 MB | 9.3 MB |
| apache/kafka | Apache-2.0 | 6.2 MB | 71.4 MB |

Kafka's `core/src/main` holds a `java` and a `scala` directory side by side, and a third of Pekko is
Java. Mixed trees like those are exactly where the JVM bridge earns its keep: a Scala caller of a
Java class, a Java caller of a Scala `object`. Akka itself is under the Business Source License 1.1 —
measure on it if you like, but keep its code out of fixtures; Pekko is its Apache-2.0 fork.

Who benefits: everyone working in the Spark, Kafka and Akka/Pekko ecosystems, and the agents they
point at those trees.

---

## Background — the grammar, the surfaces, the bridge

**The grammar: tree-sitter/tree-sitter-scala, MIT.** Its README says it covers "both Scala 2 and 3".
Read 2026-09-11:

- tag `v0.26.2` (2026-08-08) is commit `b931fcc338390925eb893d70ad070033f5856ccf`; `master` was at
  `db390f312a54b04b13790e1767bfac32665c17ac` (2026-08-25);
- at `v0.26.2`, `src/parser.c` declares `LANGUAGE_VERSION 15`, inside the range the vendored runtime
  accepts, 13 to 15 (`TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION` and `TREE_SITTER_LANGUAGE_VERSION`
  in `third_party/deps/tree_sitter/lib/include/tree_sitter/api.h`);
- `src/parser.c` is 26,814,426 bytes, and there is an external scanner, `src/scanner.c` (67,479
  bytes, 52 external tokens) — Scala 3's significant indentation lives there;
- `queries/tags.scm` (1,396 bytes) already tags `class_definition`, `object_definition`,
  `trait_definition`, `enum_definition`, `function_definition`, `given_definition`, `val_definition`
  and `var_definition`, bare `call_expression`s, and `extends_clause` references;
- unlike tree-sitter-kotlin, declarations carry named fields. `class_definition` has `name`, `body`,
  `class_parameters`, `extend`, `derive` and `type_parameters`; `call_expression` has `function` and
  `arguments`; `field_expression` has `value` and `field`; `import_declaration` has `path`.
  `extension_definition` has **no** `name` field;
- `node-types.json` carries the Scala 3 shapes as well: `indented_block`, `colon_argument`,
  `given_definition`, `extension_definition`, `using_directive`, `package_object`,
  `infix_expression`;
- `implicit` appears in `grammar.json` only as an anonymous keyword string. The named modifier
  children are `access_modifier`, `inline_modifier`, `open_modifier`, `transparent_modifier`,
  `infix_modifier` and a few more, so finding `implicit` means reading token text.

Pin a full 40-hex commit — the tag's, or a newer one with a reason — and say which in the
`THIRD_PARTY.md` row, the way the Kotlin row explains its own pin.

**The registration surfaces.** `prompts/add-a-language.md` lists the files the Elixir grammar
touched. On main a language is data first: `queries/scala/tags.scm`, one `kLangFacts` row in
`src/langfacts.h` (a missing row does not compile; the Java and Kotlin rows show the JVM columns —
`edgeFamily`, `baseImportEvidence = JvmImport`, `writtenModule = DirsOnly`), the `kLangTable` row in
`src/ingest_crawl.h`, and its mirrors in `src/lintrules.h`; the compile-time checks in
`src/ingest_crawl.h` and `src/main.cpp` name each table you missed. Landing Kotlin found more that a
new language has to reach, and Scala will too: the `--help`
languages line in `src/cli.h` and its regenerated copy in `docs/COMMANDS.md`
(`test/docscommandscheck.sh` arm G), the README's languages line and grammar count, a
`THIRD_PARTY.md` row with the grammar's ABI and size, `test/fuzz/run.sh` and a seed directory under
`test/fuzz/seeds/`, the help labels in `test/printf_parity.manifest`, a RE-PIN LOG entry in
`test/qschemetripcheck.sh`, and an extraction paragraph in `docs/ARCHITECTURE.md` beside Elixir's,
Dart's and Kotlin's. `Lang` in `src/model.h` is append-only because its values are serialized into
the cache: `Lang::Scala` goes after the last enumerator on the `main` you land on, and `kLangCount`
follows.

**The JVM bridge on main** (`src/graph.h`, `src/langfacts.h`):

- `langCompatible( a, b )` admits a pair when `langFamilyOf( a ) == langFamilyOf( b )`, and
  `langFamilyOf` reads each row's `edgeFamily` column (Kotlin's row says `Lang::Java`) — admission by
  bare name. `kLangFamilyMatchesBridge` beside `langCompatible` proves at compile time that the
  column still matches the original pair set, so adding Scala to the family means editing that
  proof too, in the same commit.
- `keepOwnJvmLanguageCandidates( ing, r, cand )` then lets a Java or Kotlin reference keep the *other*
  JVM language's candidates only when its own language offers none. It runs on call candidates right
  after the namespace gate, and on base candidates in the inheritance overlay. Its comment carries the
  measurement that made it necessary: on square/retrofit, bare-name admission took `Response.java`'s
  `body` from 279 callers to 5, because same-named Kotlin test functions in other directories made the
  name non-unique and the tier ladder declined every Java call.
- `collapseDeclarationsOfName` keys the decl/def collapse by root and family —
  `kCollapseFamilies * root + collapseFamilyOf( s.lang )`, over a
  `std::array<bool, kCollapseFamilies * kMaxWorkspaceRoots>`. `kCollapseFamilies` is 3 today: Kotlin,
  Ruby, and everything else. The Kotlin split exists because a Kotlin body once evicted a Java
  interface-only declaration, so adding a `.kt` file moved a Java edge; Ruby's for the same reason
  against C headers.
- `test/kotlincheck.sh` §14c ("THE INVARIANT" in its comments) is the template for the arm you will
  write: a Java-only tree, then the same tree plus a directory of Kotlin definitions spelling the same
  names, with every Java `--callers` row, `--lego` implementor and map row required to be identical.

---

## Reproduce the gap

On `main`, a two-file tree:

`Main.scala`

```scala
object Main {
  def greet(n: String): String = "hi " + n
  def main(args: Array[String]): Unit = println(greet("x"))
}
```

`J.java`

```java
class J { int f() { return 1; } }
```

`./build/ripwire "$FX" --no-cache --skipped` prints
`<f p="Main.scala" why="unsupported-ext" bytes="119" ext=".scala"/>` and
`<lang n="java" files="1" symbols="2"/>`. The Scala file contributes no symbol to anything.

The bridge fixture does not exist yet; you write it as part of the gate.

---

## STEP 0 for Scala — measure before you vendor

`prompts/add-a-language.md`'s STEP 0 applies with one addition: **measure Scala 2 and Scala 3
separately.** One grammar covers both, and the external scanner that handles significant indentation
is the part most likely to degrade.

- Scala 2 corpora: apache/spark, apache/kafka's `core`, apache/pekko.
- Scala 3 corpora: scala/scala3 (the Scala 3 compiler), plus at least one application codebase that
  uses the braceless syntax — check that it does before you count it as one.

For each, record the commit, the `.scala` file count, and the fraction that parses with no
`ERROR`/`MISSING` node. Two honest instruments: the tree-sitter CLI's parse statistics over the
corpus, or a local, uncommitted registration and `--skipped`, whose `why="degraded-parse"` rows are
exactly the files with such nodes (flagged, never dropped; a parser-state fact, not a syntax verdict).
Count `.sc` and `.sbt` files too, and decide in the plan whether either is indexed.

If the Scala 3 rate is low, stop and write that down. A grammar that parses half a dialect is worse
than a disclosed absence.

**STEP 0 also reads the scanner for the abort class, before any corpus run, and it checks both kinds
of nesting.** tree-sitter-kotlin's scanner called `abort()` when its delimiter stack filled, which ended
the run for the entire tree. Scala gives a hostile file two shapes to drive deep: string interpolation
(`s"…${ s"…" }…"`) and Scala 3's significant indentation, whose INDENT/OUTDENT stack lives in the external
scanner. Read tree-sitter-scala's `src/scanner.c` at your pinned commit and write down, in the plan, for
the interpolation path and for the indentation stack alike:

- every stack or counter the scanner keeps, its element type, and what bounds each one;
- what `serialize()` writes per entry, against `TREE_SITTER_SERIALIZATION_BUFFER_SIZE` (1024), and
  whether its guard proves the whole write fits;
- whether a push past the bound calls `abort()`, asserts, truncates, drops state, or writes out of
  bounds;
- whether any counter is narrower than the input can drive it.

What the maintainers read at the `v0.26.2` tag (`b931fcc3`, on 2026-09-16). Re-read it at your pin,
because the scanner moves:

- **The indentation stack** is `Array(int16_t) indents`, pushed on every INDENT (two `array_push` sites,
  neither bounded) and popped on OUTDENT. `serialize()` checks the whole write,
  `( indents.size + 5 ) * sizeof( int16_t )` against the buffer, and returns 0 when it would not fit:
  no out-of-bounds write and no abort, but the scanner's whole layout state is dropped past about 507
  open levels, and the parse carries on from a reset state. That is the overflow class of Kotlin's
  string stack, ending in a silently wrong tree instead of a crash.
- **The widths are narrow.** Each indentation width is an `int16_t` counted one leading space at a time,
  and `CASE_INDENT_FLAG` (`0x4000`) is packed into the same value. A line indented 16,384 spaces or more
  collides with the flag, and past 32,767 the count wraps: an implicit truncation, which the ASan build's
  `-fno-sanitize-recover=all` turns into a hard abort. `third_party/patches/kotlin/003-dollar-run-saturate.patch`
  is the precedent for a narrow counter.
- **Interpolation nesting** is not a scanner stack at that tag: the scanner lexes one string segment at
  a time, and the nesting rides the parser's own stack. Measure what a deep one costs anyway (time,
  memory, and ripwire's own walks over the tree), and give it a ceiling if STEP 0 finds a limit.
  `scan_string_content` also holds an `assert( false )` in its string-mode switch; a plain build keeps
  `assert`, so find out whether any input reaches it.

Then confirm each finding on generated files under the ASan build (`cmake -S . -B asan -DRIPWIRE_ASAN=ON`):
nested interpolations, deeply indented Scala 3 blocks (braceless `def … =` and `if … then` chains), and a
line with a very long run of leading spaces, each raised until something gives. Record each depth. Those
numbers set the ceilings in "Hostile nesting".

---

## What is hard — say it plainly in the plan

A name-based call graph sees calls that are written down. Scala makes many calls that are not.

- **Implicits.** Scala 2 `implicit` conversions and parameters, Scala 3 `given`/`using`: calls the
  compiler inserts. No syntax node names them. Disclose them as a floor; never guess.
- **Extension methods.** Scala 3 `extension (x: T) def f`, Scala 2 implicit classes. `x.f()` names
  `f` on a receiver ripwire cannot type, and `extension_definition` has no name of its own.
- **Companion objects.** `class Foo` and `object Foo` in one file are two legitimate definitions of
  one name, and `Foo(x)` calls `Foo.apply`, which a case class synthesizes. They are neither a
  collision to decline nor a declaration to collapse.
- **Trait linearization.** `class C extends A with B`, and a `super.f()` that resolves by
  linearization order. Model it or disclose it; do not approximate it with the first base.
- **Calls with no call node.** A parameterless method (`xs.size`) is a `field_expression`; an infix
  call (`a max b`) is an `infix_expression`; a `for` comprehension desugars to
  `map`/`flatMap`/`withFilter`/`foreach`; `apply` is sugar. Decide which you capture, and count what
  you do not.
- **Arity.** Overloads plus default and named arguments. `callArity` (`src/ingest_metrics.h`) has no
  Scala arm, and `arityExact` must stay 0 wherever a default argument exists.
- **Scala 2 against Scala 3.** Braces and indentation, `then`/`do`, `enum`, `given`. The fixtures
  need both.
- **Lexically scoped imports.** A Scala import can sit inside any block. If resolution walks scopes
  and you memoize the walk, the key carries the whole chain — `prompts/add-a-language.md`'s first
  trap, found in Ruby.

---

## The design space — the JVM bridge for three languages

**The invariant: adding `.scala` files never changes a Java-only or Kotlin-only edge.** Every edge
that exists in a tree without the Scala files exists with them, with the same target. The only new
edges have a Scala endpoint.

**The obvious generalization breaks it.** "Own language first, otherwise every other JVM language"
lets a Java call that today bridges to a name only Kotlin defines pick up a same-named Scala candidate
too: two candidates in other directories, declined at tier 3, and a Java → Kotlin edge vanishes
because a `.scala` file appeared. The fallback has to be **ordered**:

- a Java or Kotlin reference: its own language, then the existing Java/Kotlin partner, then Scala;
- a Scala reference: Scala first, then Java and Kotlin in an order your measurement justifies — Java
  is the common interop surface; say whether Kotlin comes after it or beside it.

**The collapse needs a fourth family.** A Scala body must not evict a Java or Kotlin declaration —
the exact bug #126's family split fixed for Kotlin. The collapse runs by name across languages
*before* any bridge, so this bites even with Scala outside `langCompatible`: a Java interface-only
declaration evicted by a same-named Scala `def` leaves the Java call with nothing to bind.
`collapseFamilyOf` gains a Scala arm and `kCollapseFamilies` goes from 3 to 4, with
`keyHasDefinition` sized from it. A tree with no `.scala` file must still collapse byte-identically.

**The inheritance overlay takes the same ordered rule:** `class Foo extends JavaBase with KotlinTrait`
resolves its bases through it.

**Consider two PRs.** Grammar, extraction, disclosure and the collapse family first, with Scala
outside the bridge; the ordered bridge second, with the invariant arms. Each is reviewable, and the
first is useful on its own. The hostile-nesting layers below belong in the first.

---

## Hostile nesting: reuse the Kotlin refusal shape

Scala gives a hostile file two nesting shapes: string interpolation (`s"…${ s"…" }…"`) and Scala 3's
significant indentation, whose INDENT/OUTDENT stack the external scanner keeps and serializes. Deep
indentation is the same overflow class as Kotlin's string stack, and as the indent stack of any
layout-sensitive grammar (Python's; GDScript's, merged in #233). Kotlin already solved this class with two
independent layers. Reuse that shape for **both** Scala shapes rather than inventing a second mechanism,
and make the disclosure safe under concurrency from the first commit.

1. **A pre-parse scan that mirrors the scanner's stacks, not a shape estimate.** One pure O(n) pass over
   the bytes that covers both shapes:
   - the indentation stack, pushed and popped by the scanner's own INDENT/OUTDENT rule, with widths
     counted the way the scanner counts them, so a file is refused before the stack stops serializing
     or a width outgrows its `int16_t`;
   - interpolation depth, with a fixed frame array (string and interpolation frames alternate, so bound
     it at twice its ceiling).

   Each ceiling sits well under the depth STEP 0 measured for that shape. The exemplar is
   `kotlinStringsNestTooDeep` (`src/ingest_crawl.h`) with `kMaxKotlinStringNestDepth` (`src/ingest.h`,
   128).
2. **A vendored scanner patch that refuses instead of failing**, for every stack and counter STEP 0
   flags: the indentation push is refused once the stack would no longer serialize, rather than state
   being dropped, and a width counter saturates rather than wrapping. The parser then recovers with an
   `ERROR` node even if the scan is ever bypassed. The precedents are
   `third_party/patches/kotlin/001-stack-push-no-abort.patch` (a push refused) and
   `003-dollar-run-saturate.patch` (a counter saturated), each with its arm in
   `test/vendorpatchcheck.sh`.
3. **One more case in the shared guard.** #157 landed: `refuseNesting` (`src/ingest_prewarm.h`) is
   the one call every corpus-file parse makes — the ingest pool's `runParseWorker` and the blob pass's
   `rawDefsOfOneBlob` — and `astQueryGrouped` (`--match`, `--pattern`, `--lint`) reads
   `ing.nestRefusedFile` so it never walks a refused file. Scala is one more `case Lang::Scala` arm
   there, one more `NestRefusal::DisclosureWhy` enumerator, and one more clause in
   `writeNestRefusedLegend` (`src/verbs_report.h`). The switch is deliberate — its header comment
   says why a table of function pointers left every prescan with zero call edges — so do not turn it
   back into a table. Keep the Kotlin mechanics: one writer per slot (`scan.nestRefusedBytes[ fileId ]`),
   rows collected serially in fileId order (`collectNestRefusals`), and the refused file's cache
   record written UNKNOWN (`forgetNestRefusalsForCache`) so a warm run re-refuses it.
4. **Disclosure lives in output rows, never only on stderr.** A refusal is a `--skipped` row with
   `why="nest-refused"`, counted in `nest_refused=`, plus a legend-defined refusal attribute on `--match`.
   Gates assert those rows. They never assert the `DISCLOSE` text: the alert fires once per
   call site per process (not once per file), compiles out in Release, and is written in several pieces
   that a concurrent stderr line can split, which is what made `test/kotlincheck.sh` §12's alert arm
   flaky.
5. **Two refused files in EVERY hostile fixture, on purpose.** That covers the interpolation fixture, the
   indentation fixture, and any fixture an arm builds for itself. Each holds:
   - a file at the ceiling depth, which is indexed;
   - **two** files past the ceiling, both refused: one level over, and far over, the way
     `test/kotlincheck.sh` §12 pairs `OverCeiling.kt` with `Deep.kt`;
   - a sibling file, which is indexed.

   Two refusals in one run are the concurrency that exposed the torn stderr notice behind §12's flaky
   alert arm. A fixture with one refused file cannot see that class of defect in any disclosure a site
   uses.

---

## Constraints — the non-negotiables

- **Write the gate before the code.** `test/scalacheck.sh` fails against a binary without your change
  before it passes against one with it.
- **Determinism is a contract.** Two runs are byte-identical; warm equals cold; a relative and an
  absolute crawl root resolve identically.
- **Honesty in output.** Unparsed files are counted, never silently dropped; a count that cannot be a
  total carries `counts_floor="1"`; a zero means "none found". Every blind spot above is disclosed in
  the output or its legend, in the gate header, and in `docs/ARCHITECTURE.md` — not only in a comment.
- **`DISCLOSE`, never `ASSUME( false )`**, on any recoverable path.
- **No `std::map` or `std::unordered_map`** — `HashMap<>` (ankerl) or `gtl::btree_map`.
- **House style** (`CONTRIBUTING.md` §3): Allman braces, braces on every control body, spaces inside
  parens, output through `rw::emitTo`, no new printf-family call site.
- **Build discipline.** Plain dev build; never `-DCMAKE_BUILD_TYPE=Release` locally; never edit the
  tree during a build. A language touches `src/model.h`: rebuild with
  `cmake --build build --clean-first -j`, and the same for `asan/`.
- **Vendored code is never silently edited** (guardrail G3, and the contract in
  `third_party/patches/README.md`). A change to the grammar is a patch file under
  `third_party/patches/<dep>/`, a `RIPWIRE_VENDOR_PATCH(...)` marker in every hunk, and
  `test/vendorpatchcheck.sh` green — or, better, a fix upstream.
- **Extraction identity.** `kParserVer` and `kIngestParserVerMirror` move in the same commit;
  `test/qschemetrip.hash` is re-pinned with a RE-PIN LOG entry.

---

## Acceptance criteria

1. **STEP 0 numbers** in the plan, per corpus and per dialect, before any code.
2. **`test/scalacheck.sh`**, red first, listed in `test/regression.sh` in the same commit
   (`test/manifestcheck.sh` fails otherwise), and `python3 docs/gatecount_build.py` run after adding
   it — the published gate count is a build product, never hand-edited.
3. **Adversarial fixtures in `test/scalafix/`:**
   - definitions with spans: `class`, `case class`, `object`, `trait`, `def`, Scala 3 `enum` and
     `given`, in both brace and indentation syntax;
   - a companion pair — both rows present, neither collapsed away;
   - a decoy: the same name in a file that must not win;
   - Scala → Java and Java → Scala calls in a **split** layout, three directories or more;
   - a disclosed blind spot: an implicit conversion's call site produces no edge, and the gate header
     says why.
4. **The invariant arm** (the §14c pattern), three ways: a Java-only tree, a Kotlin-only tree, and a
   Java+Kotlin tree whose Java → Kotlin bridge edge must survive — each against the same tree plus a
   `scala/` directory defining the same names. `--callers` rows, `--lego` implementors and map rows
   (edges, `prov=`, `amb=`) are identical for every non-Scala symbol. Plus a mutation that can fail:
   delete the Java definition, assert the deletion took, and the Java call must now bridge to Scala.
5. **Determinism** twice, warm equals cold, relative and absolute roots identical, `xmllint --noout`
   clean.
6. **Non-Scala byte identity:** the map, `--metrics` and `--lint` over a tree with no `.scala` file
   are byte-identical to the base binary's.
7. **A mixed corpus:** Kafka or Pekko at a named commit. Java (caller, callee) pairs lost against the
   base binary must be zero; list the Java ↔ Scala pairs gained and hand-check a sample.
8. **Memory safety:** ASan/UBSan/LSan over the STEP 0 corpora with zero sanitizer lines, and the
   fuzzer registered with `add_ripwire_fuzzer`.
   - **Hostile nesting, for the interpolation path and the indentation stack alike:** STEP 0's scanner
     findings in the plan; the pre-parse scan, the vendored patch with its `test/vendorpatchcheck.sh`
     arm, and the `refuseNesting` case; `--skipped` rows and `nest_refused=` asserted
     cold and warm over fixtures that each hold a ceiling-depth file, two refused files and a sibling;
     `--match` returns no hits inside a refused file and says so; the map exits 0 on the ASan build.
9. **Every registration surface** above updated, and every blind spot above either modeled or stated.

**Done means** every criterion above, proven by these **gates, plain and ASan:** `bash test/scalacheck.sh`, `bash test/kotlincheck.sh`,
`test/javarubycheck.sh`, `test/langcensuscheck.sh`, `test/parsehealthcheck.sh`,
`test/vendorpatchcheck.sh`, `test/dependencypincheck.sh`, `test/docscommandscheck.sh`,
`test/printffmtparitycheck.sh`, `test/qschemetripcheck.sh`, `test/qextractionkeycheck.sh`,
`test/multirootcheck.sh`, `test/readmedriftcheck.sh`, `test/deckcheck.sh`, `test/gatecountcheck.sh`,
`test/langidentitycheck.sh`, `test/deplangscheck.sh`.
Then `./build/ripwire . --quality-delta --legend=compact`, `./build/ripwire . --test-gate`, and
`python3 test/pargates.py . ./build/ripwire -j 6` in the foreground.

---

## Known traps

Read the traps in `prompts/add-a-language.md` first. These are the ones Scala adds or sharpens.

- **A flat fixture proves nothing.** In one directory the locality tiers pick a candidate and a
  broken bridge passes. Landing Kotlin found an "honestly ambiguous" collision that held only in a
  one-directory fixture; split across three directories, both calls reached neither definition.
- **Bare-name admission deletes edges.** retrofit's `Response.body` went from 279 callers to 5 before
  own-language-first existed. Measure a mixed tree, not only a pure-Scala one.
- **Enumerator order.** `Lang` values are serialized, so `Lang::Scala` goes after the last enumerator
  on the `main` you land on (today that is after `Lang::Proto`). Other language PRs append too — Zig
  (#166) is in flight — and two branches that each append one value give two languages the same
  serialized value. `enumCountIsExact` makes a stale `kLangCount` a build error; the duplicate value
  is still yours to catch. Re-check at every rebase.
- **A hostile file can take the whole index down.** tree-sitter-kotlin's scanner called `abort()`
  when a string stack passed 512 entries, ending the run for the entire tree; the fix is the two layers
  in "Hostile nesting" plus the patches under `third_party/patches/kotlin/`. Do STEP 0's scanner read
  before you trust tree-sitter-scala, and refuse a file rather than crash.
- **A refusal tested only cold passes blind.** Kotlin's guard first cached a refused file as "parsed,
  nothing there", and its warm arm went red. Every refusal arm gets a warm twin.
- **Grammar weight.** `src/parser.c` is about 27 MB at `v0.26.2`; the `THIRD_PARTY.md` row states the
  size, and the build gets slower.
- **A stale object mix after `src/model.h`.** Objects that disagree on `sizeof( Symbol )` produce an
  ASan overflow whose region is a multiple of the old size, or a `std::length_error` from a `resize`.
  Rebuild with `--clean-first` first.
- **Gates share one checkout.** Build fixture trees under `$TMP`; a probe written into the checkout
  flips every stamped verb's dirty bit for the gates running beside you.
- **Numbers collide across lanes.** `kParserVer` and the published gate count are both claimed by
  parallel work. The maintainers assign your `kParserVer` in the PR (add-a-language STEP 4); regenerate
  the gate count on the merged tree, never hand-merge it.

---

## What the PR description should contain

- **The STEP 0 parse rates**, per corpus and dialect, with commits, and the `.sc`/`.sbt` decision.
- **The blind spots you disclosed**, and where the output states each one.
- **The JVM ordering you chose** and the invariant evidence: the three trees and the mutation.
- **The mixed-corpus measurement**: Java pairs lost (zero), Java ↔ Scala pairs gained, the checked
  sample.
- The grammar pin and why; any vendor patch and its upstream status.
- The `kParserVer` bump and every registration surface touched.
- The gates you ran, plain and ASan, with results.
- A line that this builds on #126 by @xCatG.

**Write the plan — STEP 0 numbers and the scanner read, the dialect and extension decisions, the blind
spots you will disclose, the hostile-nesting layers, the JVM ordering and collapse change, the fixtures
and arms in red-first order — then STOP for my go-ahead.**

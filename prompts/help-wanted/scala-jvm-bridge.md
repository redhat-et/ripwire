# Add Scala to ripwire — the third JVM language

You are adding **Scala** to ripwire and joining it to the call graph that Java and Kotlin already
share. This is a full language round — a vendored grammar, extraction, disclosed blind spots, a
red-first gate — plus one resolver change that comes with an invariant that must not bend.

> **Prerequisite — PR #126 (Kotlin support, by @xCatG).** The JVM bridge this prompt extends —
> `langCompatible`'s JVM arm, `keepOwnJvmLanguageCandidates` and the per-family decl/def collapse in
> `src/graph.h` — is added by #126, which is still open as of 2026-09-11. Start from #126
> (`gh pr checkout 126` in a fresh worktree) or from main once it merges, and confirm that
> `keepOwnJvmLanguageCandidates` exists before you plan. STEP 0 below, the parse-rate measurement,
> needs none of it and can start today. Line numbers drift; the function names are the pointers.

**Read `prompts/add-a-language.md` first and follow it step by step.** This prompt does not repeat
its file list. It adds what is specific to Scala and to the JVM bridge, and it overrides nothing.

Work in a git worktree, not your main checkout. Run every gate in the foreground.

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
touched. Landing Kotlin found more that a new language has to reach, and Scala will too: the `--help`
languages line in `src/cli.h` and its regenerated copy in `docs/COMMANDS.md`
(`test/docscommandscheck.sh` arm G), the README's languages line and grammar count, a
`THIRD_PARTY.md` row with the grammar's ABI and size, `test/fuzz/run.sh` and a seed directory under
`test/fuzz/seeds/`, the help labels in `test/printf_parity.manifest`, a RE-PIN LOG entry in
`test/qschemetripcheck.sh`, and an extraction paragraph in `docs/ARCHITECTURE.md` beside Elixir's,
Dart's and Kotlin's. `Lang` in `src/model.h` is append-only because its values are serialized into
the cache: `Lang::Scala` goes after `Lang::Kotlin`, and `kLangCount` follows.

**The JVM bridge, as #126 leaves it** (`src/graph.h`):

- `langCompatible( a, b )` admits a pair when both languages are in `{ Lang::Kotlin, Lang::Java }` —
  admission by bare name.
- `keepOwnJvmLanguageCandidates( ing, r, cand )` then lets a Java or Kotlin reference keep the *other*
  JVM language's candidates only when its own language offers none. It runs on call candidates right
  after the namespace gate, and on base candidates in the inheritance overlay. Its comment carries the
  measurement that made it necessary: on square/retrofit, bare-name admission took `Response.java`'s
  `body` from 279 callers to 5, because same-named Kotlin test functions in other directories made the
  name non-unique and the tier ladder declined every Java call.
- `collapseDeclarationsOfName` keys the decl/def collapse by root and family —
  `2u * root + ( s.lang == Lang::Kotlin ? 1u : 0u )`, over a
  `std::array<bool, 2u * kMaxWorkspaceRoots>`. The family split exists because a Kotlin body once
  evicted a Java interface-only declaration, so adding a `.kt` file moved a Java edge.
- `test/kotlincheck.sh` §13c ("THE INVARIANT" in its comments) is the template for the arm you will
  write: a Java-only tree, then the same tree plus a directory of Kotlin definitions spelling the same
  names, with every Java `--callers` row, `--lego` implementor and map row required to be identical.

---

## Reproduce the gap

On main or on #126, a two-file tree:

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

**The collapse needs a third family.** A Scala body must not evict a Java or Kotlin declaration —
the exact bug #126's family split fixed for Kotlin. The collapse runs by name across languages
*before* any bridge, so this bites even with Scala outside `langCompatible`: a Java interface-only
declaration evicted by a same-named Scala `def` leaves the Java call with nothing to bind. The key
space grows from two families per root to three, and `keyHasDefinition` with it. A tree with no
`.scala` file must still collapse byte-identically.

**The inheritance overlay takes the same ordered rule:** `class Foo extends JavaBase with KotlinTrait`
resolves its bases through it.

**Consider two PRs.** Grammar, extraction, disclosure and the collapse family first, with Scala
outside the bridge; the ordered bridge second, with the invariant arms. Each is reviewable, and the
first is useful on its own.

---

## Constraints — the non-negotiables

- **Write the gate before the code.** `test/scalacheck.sh` fails against a binary without your change
  before it passes against one with it.
- **Determinism is a contract.** Two runs are byte-identical; warm equals cold; a relative and an
  absolute crawl root resolve identically.
- **Honesty in output.** Unparsed files are counted, never silently dropped; a count that cannot be a
  total carries `counts_floor="1"`; a zero means "none found". Every blind spot above is disclosed in
  the output or its legend, in the gate header, and in `docs/ARCHITECTURE.md` — not only in a comment.
- **`DEGRADED_PATH_ALERT`, never `VERIFY( false )`**, on any recoverable path.
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
4. **The invariant arm** (the §13c pattern), three ways: a Java-only tree, a Kotlin-only tree, and a
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
9. **Every registration surface** above updated, and every blind spot above either modeled or stated.

**Gates, plain and ASan:** `bash test/scalacheck.sh`, `bash test/kotlincheck.sh`,
`test/javarubycheck.sh`, `test/langcensuscheck.sh`, `test/parsehealthcheck.sh`,
`test/vendorpatchcheck.sh`, `test/dependencypincheck.sh`, `test/docscommandscheck.sh`,
`test/printffmtparitycheck.sh`, `test/qschemetripcheck.sh`, `test/qextractionkeycheck.sh`,
`test/multirootcheck.sh`, `test/readmedriftcheck.sh`, `test/deckcheck.sh`, `test/gatecountcheck.sh`.
Then `./build/ripwire . --quality-delta --legend=compact` and
`python3 test/pargates.py . ./build/ripwire -j 6` in the foreground.

---

## Known traps

Read the traps in `prompts/add-a-language.md` first. These are the ones Scala adds or sharpens.

- **A flat fixture proves nothing.** In one directory the locality tiers pick a candidate and a
  broken bridge passes. Landing Kotlin found an "honestly ambiguous" collision that held only in a
  one-directory fixture; split across three directories, both calls reached neither definition.
- **Bare-name admission deletes edges.** retrofit's `Response.body` went from 279 callers to 5 before
  own-language-first existed. Measure a mixed tree, not only a pure-Scala one.
- **Enumerator order.** `Lang::Scala` goes after `Lang::Kotlin`. A branch cut from a main without
  #126 would give two languages the same serialized value.
- **A hostile file can take the whole index down.** tree-sitter-kotlin's scanner called `abort()`
  when a string stack passed 512 entries, ending the run for the entire tree; #126 carries two patches
  under `third_party/patches/kotlin/`. Read Scala's `scanner.c` for `abort()` and unbounded stacks
  before you trust it, feed it deeply nested interpolations and blocks early, and refuse a file rather
  than crash.
- **Grammar weight.** `src/parser.c` is about 27 MB at `v0.26.2`; the `THIRD_PARTY.md` row states the
  size, and the build gets slower.
- **A stale object mix after `src/model.h`.** Objects that disagree on `sizeof( Symbol )` produce an
  ASan overflow whose region is a multiple of the old size, or a `std::length_error` from a `resize`.
  Rebuild with `--clean-first` first.
- **Gates share one checkout.** Build fixture trees under `$TMP`; a probe written into the checkout
  flips every stamped verb's dirty bit for the gates running beside you.
- **Numbers collide across lanes.** `kParserVer` and the published gate count are both claimed by
  parallel work. Re-bump at landing; regenerate the gate count, never hand-merge it.

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

**Write the plan — STEP 0 numbers, the dialect and extension decisions, the blind spots you will
disclose, the JVM ordering and collapse change, the fixtures and arms in red-first order — then STOP
for my go-ahead.**

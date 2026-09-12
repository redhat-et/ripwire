# Kotlin Multiplatform: make `expect`/`actual` calls land

You are fixing how ripwire's call graph treats Kotlin Multiplatform **`expect`/`actual`**
declarations. Today a call from shared code to a multiplatform type can resolve to nothing, and the
output reads exactly as if nobody made the call. The change is small in lines and large in reach:
every Kotlin Multiplatform codebase gets its shared-code call graph back.

> **Prerequisite — PR #126 (Kotlin support, by @xCatG).** Everything below describes code that #126
> adds, and #126 is still open as of 2026-09-11. Until it merges, work on top of it: `gh pr checkout
> 126` inside a fresh worktree. Before you plan, confirm you have the integrated head:
> `src/graph.h` must define `keepOwnJvmLanguageCandidates`, and `isDefinitionNotDeclaration` in
> `src/model.h` must carry a Kotlin clause. If either is missing you are on an older head — ask on
> #126 rather than rebuilding those pieces. Line numbers drift; the function names are the pointers.

Work in a git worktree, not your main checkout. Run every gate in the foreground.

---

## Why this matters

Kotlin Multiplatform shares code by contract. Common code declares `expect class Platform()`; each
platform source set supplies an `actual class Platform`. An agent working in shared code asks the
natural questions — who constructs `Platform`, what breaks if I change it — and ripwire has to
answer them from the call graph.

With #126 it cannot. On the three-file fixture in "Reproduce the gap", the one call from shared code
to `Platform()` produces **no edge**. On #126's integrated head `--callees=greet` answers a bare
`count="0"`, with no `amb=` and no `unresolved=` — the same bytes it would print if `greet` called
nothing. Main now counts such a call as declined (#136, `declined_calls=`), which makes the loss
visible; it still leaves the agent's question — who constructs `Platform`? — without an answer.

The cost on a real library, measured by the maintainers when #126's bodyless-type rule landed: of
the 138 Kotlin call pairs on ktor that the rule moved, **48 sit on `expect`/`actual` type names**
(the Kotlin paragraph of `docs/ARCHITECTURE.md`, as #126 lands it). The pattern is everywhere in
that tree. At ktor `166c52b3`, a line-anchored grep — a floor, since it misses annotated lines —
finds at least 59 `expect` type declarations (24 `expect class`, 8 `expect open class`,
8 `expect interface`, 8 `expect abstract class`, 7 `expect object`, 2 `expect sealed class`,
2 `expect enum class`) and 141 `expect fun`, in files spread over at least 14 source-set directory
names (`common`, `jvm`, `posix`, `web`, `nonJvm`, `js`, `wasmJs`, …).

Who benefits: every Kotlin Multiplatform codebase — libraries like ktor, and applications that share
one code base across Android, iOS, desktop and web.

---

## Background — how this part of ripwire works

**Extraction.** `queries/kotlin/tags.scm` (added by #126) captures definitions and call references
positionally, because tree-sitter-kotlin's declarations carry no named fields. For each definition,
`src/ingest_sidecap.h` fills a `RawDef` — find the block that sets `d.arityExact`, `d.testScope`,
`d.kind` and `d.lang`. The `RawDef` rides the per-file cache record (`writeDef`/`readDef` in
`src/ingest_cache.h`) and becomes a `Symbol` (`src/model.h`; the copy is in `src/ingest_model.h`,
next to `s.testScope = d.testScope`).

**Definition or declaration.** `isDefinitionNotDeclaration` (`src/model.h`) is the one predicate
every consumer uses to tell them apart. The house test is `endByte > sigEndByte`: a span that runs
past its signature owns a body. #126 adds a Kotlin clause — any Kotlin `Class`, `Struct` or
`Interface` kind is a definition — because Kotlin has no forward declarations and
`data class User(val name: String)` is complete without a body. A bodyless Kotlin *function* stays a
declaration: an interface member or an `abstract fun` really is a contract.

**The decl/def collapse.** `collapseDeclarationsOfName` (`src/graph.h`, buildGraph step 1e) removes
a name's declarations from resolution whenever a definition with the same collapse key exists. The
key is the root and the *family* — Kotlin rows with Kotlin rows, every other language together:
`2u * root + ( s.lang == Lang::Kotlin ? 1u : 0u )`. A name with no definition keeps its declarations
as the best available target.

**Resolution.** In buildGraph's resolve loop a call's candidates are the surviving same-named
definitions, filtered by `langCompatible` (Kotlin and Java share one JVM call graph), the namespace
gate, and `keepOwnJvmLanguageCandidates` (a Kotlin reference admits Java candidates only when Kotlin
defines none). Then the locality tiers: the caller's file, else its directory, else a unique global.
**Two or more candidates, none in the caller's file or directory, and the call is declined** — no
edge. Since #136 (merged into main on 2026-09-11) that decline is counted — `declined=` in the map
header, `declined_calls=` on `--callers`, `--callees` and `--impact` — but it is still not bound.

**Why `expect` breaks.** `expect class Platform()` has no body. Under #126's Kotlin clause it is a
definition, so it survives the collapse beside `actual class Platform` — two candidates, one in
`commonMain` and one in `jvmMain`. A caller anywhere else is declined. Without the clause, the span
test reads the bodyless `expect` row as a declaration and the collapse evicts it whenever a bodied
`actual` exists. The clause is right for `data class User(...)` and wrong for `expect`.

**The grammar.** `expect` and `actual` are both `platform_modifier` nodes inside the declaration's
`modifiers` child. Verified with `--match` on #126:
`(class_declaration (modifiers (platform_modifier)) (type_identifier) @name)` hits **both** the
`expect` and the `actual` declaration, so the extractor must read the modifier's text. `interface`
and `enum class` share `class_declaration`; `expect object` is an `object_declaration`.
`actual typealias Foo = …` is a `type_alias`, which #126's `tags.scm` deliberately does not capture,
so a type can have fewer `actual` rows in the index than it has platforms.

**Room in `Symbol`.** `src/model.h` pins `static_assert( sizeof( Symbol ) == 64 + 2 * sizeof(
std::string ) )`. Measured with `offsetof` on #126's tree and on main: `testScope` sits at offset 62
and `name` at 64, so **exactly one byte, 63, is free**. A `std::uint8_t` placed directly after
`testScope` keeps the assert green. Anything wider is a layout decision you must justify.

**Versions.** A new extracted fact is two bumps, in one commit:

- `kParserVer` (`src/ingest_cache.h`, bumped on any extraction change) and its mirror
  `kIngestParserVerMirror` (`src/quality.h`);
- `kCacheVersion`, because the `RawDef` record changes shape, and its mirror
  `kIngestCacheVersionMirror`; plus `kMinDefRecordBytesLean` (77 on main: 14×u32 + 13×u8 + 2×str),
  which `verifyCacheRecordMinimaTripwire()` re-derives from the writer at runtime.

`test/qschemetripcheck.sh` hashes both constants. Re-pin `test/qschemetrip.hash` with
`UPDATE_GOLDEN=1 test/qschemetripcheck.sh` and add a dated RE-PIN LOG entry to that script saying
what moved. Take the next free values when you open the PR; other lanes claim numbers too, and on a
collision you re-bump rather than keep either side (the history in `src/ingest_cache.h` shows how).

---

## Reproduce the gap

Build #126 with the plain dev build — no build type:

```bash
cmake -S . -B build && cmake --build build -j
bash test/kotlincheck.sh                 # green before you change anything
```

Create this three-file tree in a scratch directory `$FX`, outside the checkout (gates read the
checkout's `git status`, so never write probes into it).

`src/commonMain/kotlin/demo/Platform.kt`

```kotlin
package demo

expect class Platform()
```

`src/jvmMain/kotlin/demo/Platform.jvm.kt`

```kotlin
package demo

actual class Platform actual constructor() {
    fun name(): String = "jvm"
}
```

`src/commonMain/kotlin/demo/app/Greeting.kt`

```kotlin
package demo.app

import demo.Platform

fun greet(): String {
    val p = Platform()
    return "hello " + p.toString()
}
```

```bash
./build/ripwire "$FX" --no-cache --callees=greet      # count="0" graph_ambiguous="0" graph_unresolved="0"
./build/ripwire "$FX" --no-cache --callers=Platform   # defs="2" count="0"
./build/ripwire "$FX" --no-cache --uses=Platform      # the call site IS there: role="call" Greeting.kt:6 in_id="greet"
rm "$FX/src/commonMain/kotlin/demo/Platform.kt"
./build/ripwire "$FX" --no-cache --callees=greet      # count="1": Platform at src/jvmMain/kotlin/demo/Platform.jvm.kt:3
```

All four outputs were recorded on #126's integrated head. The last run is the diagnosis: deleting
the bodyless `expect` declaration, and nothing else, brings the edge back. That head predates #136;
on a #126 build that includes it, the first run should also carry `declined_calls="1"` — disclosed,
still unbound.

Then take your baseline on ktor (Apache-2.0; clone it and write down the commit). Run the full map
with `--no-cache` and `--top-k` above the symbol count, once with #126's binary and once with yours,
and diff the Kotlin (caller, callee) pairs. **Re-derive the 48-of-138 share on your ktor commit
before you rely on it** — it is the number your PR has to move, and the PR must restate it.

---

## The design space

**A — an `expect` type is a declaration. The recommended start.** Extract one bit, "this declaration
carries `expect`", into `RawDef` and `Symbol` (the free byte), and make `isDefinitionNotDeclaration`
return false for a Kotlin type that carries it. The collapse then evicts the `expect` row whenever an
`actual` definition exists in the Kotlin family:

- one `actual` in the tree → one candidate → the edge the fixture lost comes back, for the right
  reason;
- several `actual`s in other directories → still declined, and counted as `declined_calls=` (#136).
  That is honest: which `actual` runs depends on the compilation target;
- no `actual` in the tree (an `actual typealias`, or an actual that lives in another repository) →
  the `expect` row stays the best available target.

**B — the `expect` row as the call target.** Bind every call to the `expect` declaration and relate
the `actual`s to it the way an interface relates to its implementors. One stable edge per call site
whatever the platform count — but it adds a relation kind, touches `--lego`, and needs a disclosure
of its own. Consider it only if A's ktor measurement leaves most `expect` names declined, and say why
in the plan.

**Rejected up front — source-set inference.** Reading `jvmMain`, `commonMain` or ktor's `jvm/src` as
facts about compilation targets is a guess from directory names. The Gradle default is
`src/<set>Main/kotlin`, ktor uses `<set>/src`, and nothing in the tree proves either. ripwire does not
guess; if you believe a narrower rule is provable, the plan must say what proves it.

Decide and write down the edges of the rule, too: `expect object`, `expect interface`,
`expect enum class` and `expect annotation class` take the same treatment; `expect fun` is already a
declaration and must not move; members declared inside an `expect class` body stay declarations.

---

## Constraints — the non-negotiables

- **Write the gate before the code.** Every arm is observed RED on #126's binary before your change
  turns it green. An arm that has never failed is not evidence it can.
- **Determinism is a contract.** Two runs are byte-identical, and a warm run from the cache equals
  `--no-cache`. The new bit must ride the cache record, or a warm run silently serves the old answer.
- **Honesty in output.** Counts that cannot be totals stay floors (`counts_floor="1"`); a zero means
  "none found". Never bind a declined call to a guessed `actual`. Write every floor you leave into the
  gate header and into the Kotlin paragraph of `docs/ARCHITECTURE.md`.
- **`DEGRADED_PATH_ALERT`, never `VERIFY( false )`**, on any recoverable path — Release compiles the
  assert away and deletes the fallback behind it.
- **No `std::map` or `std::unordered_map`.** Use `HashMap<>` (ankerl) or `gtl::btree_map`, and never
  let hash iteration order reach output.
- **House style** (`CONTRIBUTING.md` §3): Allman braces, braces on every control body, spaces inside
  parens, output through `rw::emitTo`, no new printf-family call site.
- **Build discipline.** Plain dev build; never `-DCMAKE_BUILD_TYPE=Release` locally. Never edit the
  tree while a build runs. You will change `src/model.h`, so rebuild with
  `cmake --build build --clean-first -j`, and the same for `asan/`.
- **Trees without `.kt` files must not move.** The map and `--metrics` over such a tree are
  byte-identical before and after your change.

---

## Acceptance criteria

Add a section to `test/kotlincheck.sh` (the next free § number) that builds its trees in `$TMP` with
heredocs, the way the file's §13 does. Each arm is red on #126 first:

1. **Split tree** — caller, `expect` and `actual` in three different directories: `--callees=greet`
   binds `Platform`, and the arm asserts which file it bound.
2. **Presence guard** — before any binding assertion, the fixture's `expect` modifier and the call
   site exist (`--match` for the modifier, `--uses=Platform` for the site).
3. **Two `actual`s** (`jvmMain` and `jsMain`): no guessed edge. With the site proven present by arm
   2, the zero is a measured decline; on a base that includes #136, assert `declined_calls="1"`.
4. **No `actual` in the tree:** the call binds the `expect` row.
5. **`expect fun` unchanged:** a bodyless `expect fun` beside a bodied `actual fun` collapses and
   binds exactly as it did on #126.
6. **Mutation keyed on the keyword:** delete the word `expect` (a plain bodyless `class Platform`) and
   arm 1's edge must be declined again — proving the arm reads the modifier, not the layout. Assert
   the mutation took before reading the result.
7. **Java invariant:** a Java `Platform` class and a Java caller elsewhere in the tree keep exactly
   the `--callers` rows they have without the Kotlin files (the §13c pattern).
8. **Cache:** a warm run equals `--no-cache`, and a cache written by #126's binary is not served to
   yours.
9. **Determinism and well-formedness:** two runs are `diff -q` clean, and the output passes
   `xmllint --noout`.

**Measurements to report.** ktor at a named commit: Kotlin pairs gained and lost against #126, how
many sit on `expect`/`actual` names, and the `declined=` delta (#136). retrofit and
nowinandroid: zero Java pairs moved, and every moved Kotlin pair listed. The byte-identity check on a
tree without `.kt` files.

**Gates, plain and ASan:** `bash test/kotlincheck.sh`, `test/qschemetripcheck.sh`,
`test/qextractionkeycheck.sh`, `test/cacheidentitycheck.sh`, `test/cachefuzzcheck.sh`,
`test/savecachecheck.sh`, `test/statgatecheck.sh`, `test/defoverdeclcheck.sh`,
`test/javarubycheck.sh`, `test/multirootcheck.sh`, `test/legocheck.sh`. Then
`./build/ripwire . --quality-delta --legend=compact`,
`python3 test/pargates.py . ./build/ripwire -j 6` in the foreground, and
`LSAN_OPTIONS=suppressions=lsan_suppressions.txt ./asan/ripwire <ktor> >/dev/null` with zero
sanitizer lines.

---

## Known traps

- **A flat fixture proves nothing.** In one directory the same-directory tier picks a candidate, and
  the arm passes on the broken binary. #126's own "honestly ambiguous" collision arm held only in a
  one-directory fixture; split across three directories, both calls reached neither definition.
- **`platform_modifier` is both keywords.** An extractor that checks the node type alone marks every
  `actual` as `expect`.
- **A stale object mix after `src/model.h`.** An incremental build across a `Symbol` change links
  objects that disagree on `sizeof( Symbol )`. It shows up as an ASan heap-buffer-overflow whose
  region is an exact multiple of the old size, or a `std::length_error` from a
  `resize( symbols.size() )`. Rebuild with `--clean-first` before debugging either.
- **The warm run hides what the cold run shows.** When #126's nesting guard was first built, its warm
  arm went red: a refused file had been cached as "parsed, nothing there". Give every behaviour arm a
  warm twin.
- **A zero arm with no presence guard** passes the day the fixture's call site vanishes — a typo, a
  grammar bump. Assert the site first.
- **`actual typealias` is not indexed.** Do not read ktor's numbers as one `actual` row per platform.
- **Version constants collide across lanes,** and a hand-merged `kParserVer` that matches neither
  side is still wrong. Re-bump at landing, and keep both mirrors in the same commit.

---

## What the PR description should contain

- The gap in one paragraph, with the fixture and its before/after `--callees` output.
- The design you chose, the alternatives you rejected, and why.
- Red → green for every arm, naming the #126 head you were red on.
- The ktor, retrofit and nowinandroid measurements with their corpus commits, and the byte-identity
  result on a tree without `.kt` files.
- The version bumps (old → new) and the RE-PIN LOG entry.
- Every floor you leave, and where the output or the docs now state it.
- The gates you ran, plain and ASan, with results.
- A line that this builds on #126 by @xCatG.

**Write the plan — design choice, fixture trees, arms in red-first order, measurements, version
bumps — then STOP for my go-ahead.**

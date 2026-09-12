# Kotlin scope functions: stop `.run { }` binding to Java methods it never calls

You are removing a class of **false call edges** that Kotlin's scope functions — `let`, `run`,
`with`, `apply`, `also` — create wherever Kotlin and Java share a tree. The fix needs one new fact
from the syntax tree, one committed name table, and a resolver rule that is careful about what it
must keep.

> **Prerequisite — PR #126 (Kotlin support, by @xCatG).** Everything below describes code that #126
> adds, and #126 is still open as of 2026-09-11. Until it merges, work on top of it: `gh pr checkout
> 126` inside a fresh worktree. Before you plan, confirm you have the integrated head:
> `src/graph.h` must define `keepOwnJvmLanguageCandidates`. If it is missing you are on an older
> head — ask on #126 rather than rebuilding it. Line numbers drift; the function names are the
> pointers.

Work in a git worktree, not your main checkout. Run every gate in the foreground.

---

## Why this matters

Scope functions are everyday Kotlin: `user?.let { … }`, `builder.apply { … }`, `with(config) { … }`.
They are standard-library functions. Java code in the same tree is full of methods with the same
names — every `Runnable` has `run()`, every `java.util.function.Function` has `apply()`, builder
APIs have `with(…)`. ripwire resolves calls by name, and #126 joins Kotlin and Java into one call
graph. Wherever the Kotlin side defines no method of that name, each of those lambda blocks becomes an
edge into the Java method that shares it.

Measured on square/retrofit at `e27d855b` (306 `.java` files, 16 `.kt`): `--callers=run` answers
**2 callers on main and 5 with #126**. The three new rows:

- `deserialize` in
  `retrofit-converters/kotlinx-serialization/src/test/java/retrofit2/converter/kotlinx/serialization/KotlinxSerializationConverterFactoryContextualTest.kt:41`,
  and its twin in `…ContextualListTest.kt:41`. Both bodies are
  `decoder.decodeSerializableValue(UserResponse.serializer()).run { User(name) }` — the stdlib scope
  function. Retrofit's Kotlin defines no `run` at all, and the only `run` method in its Java is the
  anonymous `Runnable.run` at `retrofit-mock/src/main/java/retrofit2/mock/BehaviorCall.java:92`.
  **Both edges are false.**
- `dispatch` in `retrofit/kotlin-test/src/test/java/retrofit2/KotlinSuspendTest.kt:423`:
  `override fun dispatch(context: CoroutineContext, block: Runnable) = block.run()`. A real Kotlin →
  Java `Runnable.run` call. **True — and the edge your fix must keep.**

So on this one name, two of the three edges #126 adds are wrong, and the right one differs from them
by a single piece of syntax. What an agent sees today: `--callers` and `--impact` on a Java method
claim that Kotlin serialization tests depend on it, a blast radius padded with dependents that do not
exist, and a ranking that credits the method with in-edges it never receives.

Who benefits: every mixed Java/Kotlin codebase — Android apps above all, where Kotlin code and Java
libraries share one module.

---

## Background — how this part of ripwire works

**How a Kotlin call is captured.** `queries/kotlin/tags.scm` (#126) has two call rules. A bare call,
`(call_expression (simple_identifier) @name)`, covers `with(x) { }` and a receiverless `run { }`. A
navigation call, `(call_expression (navigation_expression (navigation_suffix (simple_identifier)
@name)))`, covers `x.run { }` and `x?.let { }`. Both produce a call reference whose only identity is
its name.

**The syntax that tells them apart.** Verified with `--match` on #126:

| Source | Shape |
| --- | --- |
| `s.run { User(this) }`, `xs.also { … }`, `s?.let { … }` | `(call_expression (navigation_expression) (call_suffix (annotated_lambda)))` |
| `with(sb) { toString() }` | `(call_expression (simple_identifier) (call_suffix (value_arguments) (annotated_lambda)))` |
| `j.run()` | `(call_expression (navigation_expression) (call_suffix (value_arguments)))` — no lambda |

The fact is in the tree at extraction time, and nothing keeps it.

**The reference path.** Capture → a `RawRef` built in `src/ingest_sidecap.h` (the block that calls
`receiverOf` and `callArity` for every non-import site) → the per-file cache record
(`writeRef`/`readRef` in `src/ingest_cache.h`; `kMinRefRecordBytes` is 39 on main: 3×u32 + 7×u8 +
5×str) → a `Reference` (`src/model.h`, copied in `src/ingest_model.h`) → buildGraph's resolve loop in
`src/graph.h`.

**What the resolver knows about a Kotlin call — nothing that helps here.**

- *Arity.* `callArity` (`src/ingest_metrics.h`) walks from the callee name up to the call node and
  counts arguments. It has no Kotlin arm: Kotlin's `value_arguments` sits under `call_suffix`, not
  directly under `call_expression`, so every Kotlin site is `argCountKnown=false`. The trailing-lambda
  test is the same upward walk plus one look inside `call_suffix`.
- *Receiver.* `isMemberAccessNode` (`src/ingest_binds.h`) has no Kotlin arm, and its comment
  discloses that every Kotlin call site classifies as `RecvKind::None`. `x.run { }` and
  `runnable.run()` look the same.
- *Language.* `langCompatible` lets a Kotlin reference see Java candidates, and
  `keepOwnJvmLanguageCandidates` keeps only the Kotlin candidates **when Kotlin defines the name**.
  Retrofit's Kotlin defines no `run`, so the Java one is admitted, is the unique global, and binds.

**Why the existing guards cannot fix it.**

- Own-language-first only engages when Kotlin defines the name.
- The external-name veto (`src/externalnames.h`, consulted in buildGraph after every evidence rule)
  refuses a builtin or standard-library name, but its tables cover Python builtins and C-family
  standard names only. A veto on the NAME `run` at Kotlin sites would also delete `block.run()` in
  `dispatch` — the true edge.
- Arity is unknown for Kotlin, and receivers do not narrow.

The missing input is one extracted fact per call site: **this call's lambda is written as a trailing
lambda.**

---

## Reproduce the gap

Build #126 with the plain dev build (`cmake -S . -B build && cmake --build build -j`) and run
`bash test/kotlincheck.sh` green first. Then build three scratch trees outside the checkout. Every
output below was recorded on #126's integrated head.

**Tree A — the bridge.**

`java/jobs/Job.java`

```java
package jobs;

public class Job implements Runnable {
    @Override
    public void run() {
    }
}
```

`kt/Use.kt`

```kotlin
data class User(val name: String)

fun build(s: String): User = s.run { User(this) }

fun kick(j: jobs.Job) {
    j.run()
}
```

`./build/ripwire "$A" --no-cache --callers=run` → `defs="1" count="2"`: `build` (`kt/Use.kt:3`,
false) and `kick` (`kt/Use.kt:5`, true).

**Tree B — the other four names.**

`java/lib/Builder.java`

```java
package lib;

public class Builder {
    public Builder with(String s) { return this; }
    public Builder apply(int x) { return this; }
    public void let() { }
    public void also() { }
}
```

`kt/Scopes.kt`

```kotlin
fun useWith(sb: StringBuilder): String = with(sb) { toString() }

fun useApply(): MutableList<Int> = mutableListOf<Int>().apply { add(1) }

fun useLet(s: String?): Int = s?.let { it.length } ?: 0

fun useAlso(xs: MutableList<Int>) = xs.also { it.clear() }

fun realWith(b: lib.Builder) = b.with("x")
```

`--callers=with` → `count="2"`: `useWith` (false) and `realWith` (true). `--callers=apply`,
`--callers=let` and `--callers=also` → `count="1"` each, and all three are false.

**Tree C — Kotlin defines `run` itself.** Tree A's `Job.java`, plus:

`kt/Task.kt`

```kotlin
class Task {
    fun run(block: () -> Unit) = block()
}

fun go(t: Task) = t.run { }

fun build(s: String): Int = s.run { length }

fun kick(j: jobs.Job) {
    j.run()
}
```

`--callers=run` → `defs="2" count="3"`: `go`, `build` and `kick`; and `--callees=kick` → the `run` at
`kt/Task.kt:2`. Own-language-first keeps only the Kotlin `run`, and receivers do not narrow, so
`j.run()` reaches `Task.run` instead of `Job.run` — the trade-off `keepOwnJvmLanguageCandidates`'s
comment already discloses. **That is not this round's bug**, but your arms must pin it, so that any
movement shows.

On retrofit, confirm the three rows above with `--callers=run`, and write down the commit.

---

## The design space

**1. Extract the fact.** Add it to `RawRef` and `Reference`, and carry it through
`writeRef`/`readRef`. Decide the shape and write the decision down:

- a bool "has a trailing lambda", or a small enum that also records whether ordinary arguments come
  first (`with(sb) { }` has both; `x.run { }` has only the lambda);
- whether `x.let(::transform)` or `x.run(block)` — the lambda passed inside the parentheses — counts.
  It is still the stdlib call, but it is not what the grammar marks. Either declare it out of scope
  and disclose it, or extend the test and justify the extension.

The record changes shape, so this is `kCacheVersion` + `kIngestCacheVersionMirror` +
`kMinRefRecordBytes`, and the extraction change is `kParserVer` + `kIngestParserVerMirror`, with
`test/qschemetrip.hash` re-pinned (`UPDATE_GOLDEN=1 test/qschemetripcheck.sh`) and a dated RE-PIN LOG
entry in `test/qschemetripcheck.sh`. Take the next free values when you open the PR.

**2. The table.** A committed list of Kotlin scope-function names beside the existing tables in
`src/externalnames.h`, with its provenance stated the way theirs is and the same sortedness
`static_assert`. Start from the five the Kotlin documentation calls scope functions: `let`, `run`,
`with`, `apply`, `also`. `takeIf`, `takeUnless`, `use` and `repeat` join only with corpus evidence.

**3. The rule.** For a **Kotlin** reference that **carries the trailing-lambda fact** and whose
**name is in the table**, drop the **non-Kotlin** candidates. Keep the Kotlin ones: a user-defined
`fun run(block: () -> Unit)` still binds (tree C's `go`). Apply it beside
`keepOwnJvmLanguageCandidates` in the resolve loop. Say in the plan whether the inheritance overlay
needs it; it should not, because a base clause is never a scope-function call.

**4. Where a refused site goes.** If no candidate survives, the site must end in a named disposition,
never a silent `continue`. The call really is bound outside the tree — to the Kotlin standard
library — which is what the header's `external=` gauge counts, so route the refusal the way the
external veto routes its own. #136 (merged into main on 2026-09-11) enforces this with a conservation
line: every resolve-loop iteration ends in exactly one named disposition, and an exit that names none
lands in `unaccounted` and raises `DEGRADED_PATH_ALERT` on plain builds. That line already caught one
guard leaving the loop uncounted — #134's `std::` guard, 1,495 calls on ripwire's own tree.

**Out of scope, and disclosed:**

- The stdlib `s.run { length }` in tree C still binds the user-defined Kotlin `run`. Only receiver
  typing can separate them — a `navigation_expression` arm in `isMemberAccessNode` is its own round.
- A Java method that really is named like a scope function and really is called with a trailing
  lambda through SAM conversion — `javaObj.run { }` where Java declares `run(Runnable)` — loses its
  edge. Count how often that shape occurs in retrofit, nowinandroid and ktor before you accept the
  cost, and put the number in the PR.

**Rejected up front:** a name-only veto, which deletes `block.run()`; and any rule keyed on the
enclosing function or file instead of the call site.

---

## Constraints — the non-negotiables

- **Write the gate before the code.** Every arm that asserts a change is observed RED on #126's
  binary first.
- **Determinism is a contract.** Two runs are byte-identical, and a warm run from the cache equals
  `--no-cache`. The new fact must ride the cache record.
- **Honesty in output.** A refused call is counted somewhere a reader can see; a zero means "none
  found"; counts that cannot be totals stay floors. Write every floor you leave into the gate header
  and the Kotlin paragraph of `docs/ARCHITECTURE.md`.
- **`DEGRADED_PATH_ALERT`, never `VERIFY( false )`**, on any recoverable path.
- **No `std::map` or `std::unordered_map`** — `HashMap<>` (ankerl) or `gtl::btree_map`. The table is a
  sorted constexpr array with a binary search, like its neighbours.
- **House style** (`CONTRIBUTING.md` §3): Allman braces, braces on every control body, spaces inside
  parens, output through `rw::emitTo`, no new printf-family call site.
- **Build discipline.** Plain dev build; never `-DCMAKE_BUILD_TYPE=Release` locally; never edit the
  tree during a build. `Reference` lives in `src/model.h`, so rebuild with
  `cmake --build build --clean-first -j` (and `asan/`) after touching it.
- **Trees without `.kt` files must not move.** The map and `--metrics` over such a tree are
  byte-identical before and after.

---

## Acceptance criteria

Add a section to `test/kotlincheck.sh` (the next free § number), with its trees built in `$TMP` the
way the file's §13 builds them. Every arm that asserts a change is red on #126 first:

1. **Tree A:** `--callers=run` is exactly `kick`; `build` is gone.
2. **The true edge stays:** `kick` binds `Job.run`, and a `block.run()` on a `Runnable` parameter —
   retrofit's `dispatch` shape — binds too.
3. **Tree B:** `useWith`, `useApply`, `useLet` and `useAlso` bind nothing in Java; `realWith` still
   binds `Builder.with`.
4. **Tree C:** `go` still binds `Task.run`. `build` and `kick` are pinned at today's answer, with a
   comment naming the receiver gap.
5. **Presence guards:** `--match` finds each trailing-lambda site before any absence is asserted.
6. **Disposition:** every refused site is counted — the gauge you routed it to rises by exactly the
   number of refused sites — and nothing leaves the loop uncounted.
7. **Mutation keyed on the fact:** rewrite tree A's `s.run { User(this) }` as `s.run()`, assert the
   file changed, and the Java edge must come back — proving the arm reads the trailing lambda, not the
   name.
8. **Java invariant:** a Java-only tree, then the same tree plus tree B's Kotlin: every Java
   `--callers` row and every Java map row is unchanged (the §13c pattern).
9. **Cache and determinism:** a warm run equals `--no-cache`; a cache written by #126's binary is not
   served to yours; two runs are byte-identical; `xmllint --noout` is clean.

**Measurements to report.** retrofit at a named commit: `--callers=run` before and after, with rows —
the two `deserialize` rows gone, `dispatch` kept. Across the whole map on retrofit, nowinandroid and
ktor: Kotlin → Java pairs removed, a hand-checked sample of them with its size and outcome, Java pairs
moved (must be zero), the SAM-conversion count, and the gauge delta for refused sites.

**Gates, plain and ASan:** `bash test/kotlincheck.sh`, `test/externalvetocheck.sh`,
`test/aritycheck.sh`, `test/qschemetripcheck.sh`, `test/qextractionkeycheck.sh`,
`test/cacheidentitycheck.sh`, `test/cachefuzzcheck.sh`, `test/savecachecheck.sh`,
`test/javarubycheck.sh`, `test/multirootcheck.sh`, `test/declinecheck.sh`.
Then `./build/ripwire . --quality-delta --legend=compact`,
`python3 test/pargates.py . ./build/ripwire -j 6` in the foreground, and
`LSAN_OPTIONS=suppressions=lsan_suppressions.txt ./asan/ripwire <retrofit> >/dev/null` with zero
sanitizer lines.

---

## Known traps

- **One tree per question.** Whether Kotlin defines `run` changes the candidate set (tree C against
  tree A). An arm that mixes them asserts the own-language rule, not yours.
- **Three shapes, one fact.** `with(x) { }` is a bare call with ordinary arguments *and* a lambda;
  `run { }` has no receiver; `x?.let { }` is a safe call. Test all three.
- **A silent `continue` drops a site from every count.** Route refusals to a named disposition.
- **A stale object mix after `src/model.h`.** An incremental build across a struct change links
  objects that disagree on its size: an ASan overflow whose region is a multiple of the old size, or a
  `std::length_error` from a `resize`. Rebuild with `--clean-first` before debugging either.
- **The warm run hides what the cold run shows.** Give every behaviour arm a warm twin.
- **Do not tune the table to the fixture.** Neither trim a name to make a number look better nor add
  one without evidence from a corpus.
- **Version constants collide across lanes.** Re-bump at landing, both mirrors in the same commit.

---

## What the PR description should contain

- The gap in one paragraph, with tree A's before/after `--callers=run`.
- The fact's shape, the table and its provenance, the rule, where refused sites go, and the
  alternatives you rejected.
- Red → green for every arm, naming the #126 head you were red on.
- The retrofit, nowinandroid and ktor measurements with their commits: removed pairs and the checked
  sample, Java pairs moved, the SAM-conversion count.
- The version bumps (old → new) and the RE-PIN LOG entry.
- Every floor you leave — the receiver gap, SAM conversion, parenthesised lambdas if excluded — and
  where it is now stated.
- The gates you ran, plain and ASan, with results.
- A line that this builds on #126 by @xCatG.

**Write the plan — the fact's shape, the table, the rule, where refused sites go, the trees and arms
in red-first order, the measurements — then STOP for my go-ahead.**

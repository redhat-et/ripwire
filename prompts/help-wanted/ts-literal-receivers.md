# TypeScript/JavaScript literal receivers: a built-in method never binds an unrelated user function

You are fixing a **confident false edge** in ripwire's call graph for TypeScript and JavaScript, and you
are doing it the way the last attempt did not: by the receiver's **type**, starting where the syntax
proves that type.

`"a-b".replace(/-/g, " ")` can only be `String.prototype.replace`. Today, if the repository also defines
an unrelated `export function replace`, ripwire links the two. It reports that edge with the graph's
ambiguity gauge at zero, so `--callees`, `--impact` and `--uses` all present it as certain. This round
makes literal receivers, and member chains that start from one, stop binding user functions that cannot
be their target. Every other member call keeps today's behaviour, byte for byte.

Work in a git worktree, not the main checkout, and run gates in the foreground.

---

## Why this matters

**It is issue #59, and it is on every TypeScript and JavaScript codebase.** The report's reproduction:

- `bounded()` calls `text.replace(/x/g, "").split(" ").map(part => part.trim()).join(" ")`.
- An unrelated `src/unrelated.ts` exports functions named `map` and `replace`, and nothing imports it.
- `ripwire . --no-cache --callees=src/bounded.ts:bounded` lists both unrelated functions as callees, beside
  `graph_ambiguous="0"`.
- A runtime control shows neither function ever runs.

The maintainer's reproduction on `main` added one more symptom: `--uses=replace` claims a call site where
the real callee is `String.prototype.replace`.

Built-in method names are exactly the names people give their own helpers: `map`, `filter`, `replace`,
`split`, `join`, `find`, `test`, `parse`. Every such collision:

- sends an agent reading `--callees` or `--impact` into code that never runs;
- inflates `--callers` on the user's helper;
- and does all this without a marker, because a bare call with one candidate *is* a legitimate confident
  pin, and the resolver cannot tell it was handed a member call.

The false edge is not specific to #59's typed parameter. On `main` at `766913d0`, every literal receiver
shape binds its unrelated same-named function with `graph_ambiguous="0"`:

| call | binds |
| --- | --- |
| `"a-b".replace(…)` | `replace` |
| `"a b".replace(…).split(" ")` | `replace` and `split` |
| `` `n=${n}`.padStart(8) `` | `padStart` |
| `[3, 1, 2].map(…)` | `map` |
| `/x/.test(s)` | `test` |
| `({ a: 1 }).toString()` | `toString` |

The JavaScript twin behaves the same.

**Why this is worth your time: it has already beaten one fix.** The first attempt deleted true edges at
scale and was backed out (details below). The right fix is a small, well-fenced rule, and the gate in
`test/fieldnarrowcheck.sh` tells you when you are done. Getting it right unblocks the harder next steps:
typed identifiers like #59's `text: string`, `JSON.stringify`, and `this.field.m()`.

---

## Background: read these before you plan

### How a TS/JS member call reaches the resolver today

- **`queries/typescript/tags.scm` and `queries/javascript/tags.scm`, the `references` block.** A member
  call is captured as `(call_expression function: (member_expression property: (property_identifier)
  @name))`. Only the property NAME is kept.
- **`src/ingest_binds.h`, `isMemberAccessNode`.**
  - It recognises `field_expression` (C/C++/ObjC), `attribute` (Python) and `call` (Ruby).
  - It returns **false** for TypeScript and JavaScript.
  - So `receiverOf` returns `RecvKind::None`, and to the resolver `x.replace()` looks exactly like a bare
    `replace()`.
- **`src/model.h`, `enum class RecvKind : std::uint8_t { None, ThisObj, NamedVar, FieldOfThis,
  FieldOfVar, SuperObj }`.**
  - It is serialized into the parse cache as a u8, so values are **append-only**.
  - The comment above it explains why a receiver shape exists at all: guard sites key on
    `recv == RecvKind::None`. `test/chainguardcheck.sh`'s header names the five of them.
- **`src/graph.h`, `buildGraph`, the name ladder.**
  - The ladder is: same file, then same directory, then a unique global, else no guess. Qualifier,
    receiver and include rules narrow the candidates before it.
  - `struct ExternalVeto` and `buildExternalVetoTables` (profiled as `"buildGraph/2e: Phase-5
    external-veto tables"`) hold the Phase-5 external-name veto.
  - `vetoExternal` is the refusal: no edge, one `external=` count.
  - The veto's name tables live in `src/externalnames.h`: `kPythonBuiltinNames`, `kShellBuiltinNames`
    and `kCFamilyStdNames`. Each is strictly sorted, and every search goes through
    `rw::sortutil::svLess`.
- **`src/ingest_names.h`: the `Foo.prototype.NAME = fn` definition capture.** This is how a repository's
  own extension of a built-in prototype becomes an indexed method.
- **`src/ingest_crawl.h`, the extension table.**
  - `.ts` uses `tree_sitter_typescript`, and `.tsx` uses `tree_sitter_tsx`, a separate grammar object.
  - `.js`, `.jsx`, `.mjs` and `.cjs` use `tree_sitter_javascript`.

### The rejected attempt (read this before you design anything)

The maintainers keep it on a local archive branch, `archive/false-edge-59-rejected` (commit `951d7e35`,
not pushed). The public record is issue #59's second maintainer comment and issue #71's correction
comment. If you have the branch, read it with `git show 951d7e35`; otherwise this summary is the record.

**What it did:**

1. **Made `isMemberAccessNode` true for TS/JS.** It matched `member_expression` with fields
   `object`/`property`, so EVERY TS/JS member call gained a receiver shape (`kParserVer` 84 → 85).
2. **Added a JS/TS arm to `ExternalVeto`.** Any member call (a receiver other than `this`/`super`) whose
   name was in a sorted table of 60 ECMAScript method names (`kJsBuiltinMethodNames`: `at`, `bind`,
   `call`, …, `map`, …, `replace`, …, `stringify`, …, `values`) became external with no edge. There was no
   exemption for repo functions of the same name.
3. **Counted guesses.** A single-candidate JS/TS member call that reached the ladder with no narrowing
   rule firing was counted into `ambOut` as a guess instead of a pin.
4. **Added a gate, `test/falseedgecheck.sh`, with controls that must keep their edge:**
   - a namespace import, `helpers.transform()`;
   - a class method on a typed receiver;
   - `this.replace()` calling the class's own method. That one was found on webpack, where
     `AMDDefineDependency.apply` calls `this.replace(…)`; the first version of the veto killed it.

**Why it was backed out** (issue #71's correction): the veto's premise was that every receiver-evidence
rule had already run. That was false, because the JS/TS ladder has almost no receiver evidence:

- no rule maps `import * as X` to `X.m()`;
- Rule 2's TS fuel is `variable_declarator` only, so a typed *parameter* is never bound;
- Rule 2b needs `field_identifier`, but TS spells it `property_identifier`;
- and there is no JS/TS `super` arm.

The result on webpack: **1,704 edges dropped across 20 names**, real ones included. `--callers=stringify`
went **361 → 0**, taking `ImportPhaseUtils.stringify(meta.phase)` with it.

The first measurement also said the cost was negligible, and it was wrong by about 30×: it sampled 3 of the
20 names (54 of the 1,704 edges) and reported that as the population.

**The lesson this prompt is built on: decide by receiver TYPE, not by name. Measure populations, never
samples.**

### The gate that holds the finish line

`test/fieldnarrowcheck.sh` carries a block labelled `KNOWN GAP (help wanted:
prompts/help-wanted/ts-literal-receivers.md)`. It generates two corpora under its own temp dir.

- **Five KNOWN GAP arms** assert today's wrong behaviour, so they pass today. Each shape binds
  `src/unrelated.ts` with `graph_ambiguous="0"`:
  - `viaString`: `"a-b".replace`;
  - `viaChain`: `"a b".replace(…).split(" ")`;
  - `viaTemplate`: a template literal's `padStart`;
  - `viaArray`: `[3, 1, 2].map`;
  - `viaRegex`: `/x/.test`.
- **Two controls** assert true edges and must stay green:
  - `r.replace()` on a parameter typed `Rewriter` binds `Rewriter.replace`;
  - `"x".shout()` binds the repository's own `String.prototype.shout = function () {…}`.
- **A presence guard** keeps the block from passing on an empty index.

The same file's arm `(e-ts)` pins that a TS `this.member.compute()` receiver stays an honest split, and
arm `(h)` pins that corpus's `ambiguous=7`. The KNOWN GAP block uses separate corpora so `(h)` cannot move.

---

## Reproduce

```bash
cmake -S . -B build && cmake --build build -j
bash test/fieldnarrowcheck.sh          # the KNOWN GAP lines PASS: that is the bug, pinned
```

By hand: put the gate's `literals.ts` and `unrelated.ts` in a scratch `src/`, then run

```bash
./build/ripwire . --no-cache --callees=src/literals.ts:viaString
```

It prints `<callees … count="1" … graph_ambiguous="0" …><s t="fn" n="replace" p="src/unrelated.ts:1"/>`.

Confirm the node kinds for yourself; do not trust this prompt or memory:

```bash
./build/ripwire . --no-cache --match='(call_expression function: (member_expression object: [(string) (template_string) (array) (regex) (object) (parenthesized_expression) (call_expression)] @recv))'
```

On the gate's five functions plus `({ a: 1 }).toString()`, that query returns 7 hits. The chain matches
twice: once on its string literal, once on its inner call.

Then reproduce the three TRUE edges that make this hard. Each one was run on `main` and binds today, and
any rule you write must keep it:

- **Prototype extension (JS).** `String.prototype.shout = function () { return "!"; };` and
  `function useShoutJs() { return "x".shout(); }`: `--callees` binds `shout`. A literal receiver CAN
  reach user code.
- **An object literal's own method (TS).** `({ replace(a: string) { return a; } }).replace("q")` binds
  the literal's own `replace`, not the unrelated free `replace` in the same corpus.
- **An element-returning chain (TS).** `[new Widget()].find(w => true)!.render()` binds `Widget.render`.
  The chain starts from an array literal, and its last link is still user code.

---

## Design space and constraints

### The rule, first step

A member call whose receiver's type is **syntactically certain** is a call on a built-in. It may bind only
a candidate that extends that built-in (a prototype extension). Otherwise it binds nothing, and it is
**counted**, not dropped.

"Certain" means:

- **Literals:** a string (`"…"`, `'…'`), a template literal, an array literal, a regex literal. Decide
  whether numbers and booleans are worth including.
- **Object literals, with care.** An object literal defines its own methods, so only a name the literal
  itself does not define can be a built-in (`toString`, `hasOwnProperty`). The simplest first step
  excludes object literals entirely and says so.
- **Chains that stay certain.** In `"x".replace(…).split(…)`, each link's receiver is the previous
  built-in call's result. Certainty survives a link only when that method's return type is fixed by the
  method itself:
  - String methods returning strings, or `split` returning an array of strings;
  - Array methods returning a new array (`map`, `filter`, `slice`, `concat`, …);
  - `join` returning a string.

  It ENDS at any link whose result is an element or a callback's return value: `find`, `findLast`, `at`,
  `pop`, `shift`, `reduce`, `reduceRight`, a subscript, a non-null `!`. It ENDS at any cast: `as`,
  `satisfies`, `<T>x`. The lattice you need is tiny (String, Array, RegExp, Number, Boolean, Unknown);
  write it as a declarative table, not a switch chain.
- **Everything else** (identifiers, `this`, parameters, fields, calls on identifiers such as
  `JSON.stringify`) keeps today's behaviour. The graph is byte-identical outside the literal class.

### Where to decide

- **At extraction (recommended).** Classify the receiver where the call is captured
  (`src/ingest_binds.h`, beside `receiverOf`) and carry the verdict on the raw reference, either as an
  **appended** `RecvKind` value or a small separate field.
  - This is an extraction change. Bump `kParserVer` in `src/ingest_cache.h`, mirror
    `kIngestParserVerMirror` in `src/quality.h` in the same commit, and re-pin `test/qschemetrip.hash`
    with `UPDATE_GOLDEN=1 test/qschemetripcheck.sh`.
  - Do **not** make `isMemberAccessNode` true for all TS/JS member calls to get there. That global
    widening changes the input to every `recv == RecvKind::None` guard for every TS/JS call, and it is
    half of what sank the first attempt. If you believe you need it, it is a separate, measured change.
- **At resolution.** In `buildGraph`, a certain-built-in receiver skips the name ladder. It binds only a
  candidate defined as an extension of that built-in, and otherwise refuses through `vetoExternal`: no
  edge, counted in the header's `external=`, already defined by the legend.
  - Since PR #136 merged (d752d953), the site's disposition is `CallDisposition::External`, and its
    `--pin-census` balance must stay `unaccounted=0`.
  - Find out, and write down, how the index scopes a `String.prototype.NAME = fn` definition
    (`src/ingest_names.h`) before you rely on it to recognise an extension.

### Constraints (CLAUDE.md and CONTRIBUTING.md; none of these is optional)

- **Gate before code.** Flip the KNOWN GAP arms first, into assertions of the fixed behaviour, and show
  them RED on the pre-change binary. Add your new controls in the same block.
- **No new false negatives.** Every edge the change removes is enumerated and read (see the acceptance
  criteria). `ambiguous=` must never rise.
- **Determinism.** Two runs must be byte-identical; warm equals cold.
- **Honesty in output.** The refused call is counted, never silently dropped. A zero on `--callees` means
  *none found*.
  - If you add any attribute, it is absent at zero and defined in the leading legend exactly when present
    (`test/legendcoveragecheck.sh`).
  - It is carried on every dialect and the MCP twin (`test/mcpattrparitycheck.sh`).
- **`DEGRADED_PATH_ALERT`, never `VERIFY( false )`**, on any degrade path you add.
- **No `std::map` or `std::unordered_map`**; see "Containers" in CONTRIBUTING.md.
- **Style** (CONTRIBUTING.md §3): Allman braces on every control body, spaces inside parens, output
  through `rw::emitTo`, declarative tables.
- **Build discipline.**
  - Use the plain dev build, never `-DCMAKE_BUILD_TYPE=Release`.
  - Never edit while a build runs.
  - `src/model.h` is in almost every translation unit, so after touching it or switching branches, run
    `cmake --build build --clean-first -j`.

---

## Acceptance criteria

1. **The KNOWN GAP arms are flipped in place.** In `test/fieldnarrowcheck.sh`, every shape your rule
   covers asserts two things: no edge into `unrelated.ts`, and the call counted (the header's `external=`
   rises by exactly the number of covered calls, or #136's named disposition). Each flipped arm is RED on
   the pre-change binary. A shape you deliberately leave out keeps its KNOWN GAP arm, with the reason in
   its comment.
2. **Controls stay green:**
   - the two in the block;
   - plus ones you add for the object literal's own method, `[new Widget()].find(…)!.render()`,
     `this.replace()` inside a class that defines `replace`, a namespace import `helpers.transform()`, and
     a cast (`("x" as unknown as Widget).render()`, or whichever cast your rule names).
3. **JS and TSX twins.** The same arms pass for a `.js` file and a `.tsx` file.
4. **Existing gates are unchanged:** `test/fieldnarrowcheck.sh` arms `(e-ts)` and `(h)`,
   `test/chainguardcheck.sh`, `test/callformcheck.sh` (its TS and JS rows), `test/qualnewcheck.sh`, and
   `test/tsimportprecisecheck.sh` (including its monotonicity arm: `ambiguous` never increases).
5. **Population measurement on at least two real TS/JS corpora.** webpack is the historical one; name the
   commits.
   - `edges=` and `external=`, before and after.
   - The FULL list of removed edges, each read at its call site and classified true or false. Zero true
     edges removed, or each one listed and argued.
   - A re-measured `--callers=stringify` baseline on webpack from today's `main` (361 was a past `main`),
     unchanged after.
6. **Cache and versions.**
   - A cache written by the pre-change binary is rejected by the version bump.
   - Warm equals `--no-cache`.
   - `test/qextractionkeycheck.sh` and `test/qschemetripcheck.sh` are green.
7. **Suite.**
   - `python3 test/pargates.py . ./build/ripwire -j 6` is green, run in the foreground.
   - ASan is clean on the fixtures.
   - `./build/ripwire . --quality-delta --legend=compact` shows zero unacknowledged regressions.

---

## Known traps (each is measured, not hypothetical)

**A name table is not a type.** `map` on an array literal is `Array.prototype.map`. `map` on a parameter is
anyone's `map`. The table-based veto could not tell the two apart and removed 1,704 webpack edges.

**A sample is not a population.** 3 of 20 names looked perfectly clean, and the population was not. List
every removed edge. If the list is too long to read, your rule is wider than this prompt's first step.

**Widening `isMemberAccessNode` for all TS/JS changes the input to every `recv == RecvKind::None` guard**:
Rule 1's bare arm, shadow suppression, and the external veto's bare arms. `test/chainguardcheck.sh`'s
header tells the C++ version of this story; the TS version cost the first attempt its true edges.

**A chain from a literal does not stay certain.** `[new Widget()].find(w => true)!.render()` binds
`Widget.render` on `main`, and that edge is true. Certainty ends at the first link whose result is an
element or a callback's return value.

**Object literals define methods.** `({ replace(a) { … } }).replace("q")` binds the literal's own
`replace` on `main`, and that edge is true.

**Repositories extend built-in prototypes.**
- JS `String.prototype.shout = function () {…}` is indexed, and `"x".shout()` binds it on `main`. The
  block's second control pins this.
- The TS spelling `(String.prototype as any).shout = …` is NOT captured as a definition today (verified).
- `declare global { interface String { shout(): string } }` is a declaration with no body.

Decide what each means for your rule, and disclose what you do not cover.

**Casts break certainty.** `("x" as unknown as Widget).render()` is a type-level claim that the receiver is
a `Widget`. Whatever the runtime says, a TS author reading that call expects `Widget.render`.

**`this.replace()` is not a literal receiver.** It is the webpack call that killed the first veto's first
version. Keep it as a control even though your rule should never reach it.

**`JSON.stringify` is out of scope.** It is a member call on the identifier `JSON`, not on a literal. The
`--callers=stringify` collapse happened exactly there. Don't let the rule creep onto identifiers.

**TSX is its own grammar object.** `.tsx` parses with `tree_sitter_tsx`. The node kinds match, but a
classifier or query keyed on one grammar pointer misses the other; `--pattern`'s legend spells
typescript and tsx apart for this reason.

**`kParserVer` collides with concurrent lanes.** PR #126 had to re-bump twice while it was in review. Take
the next free value when you rebase to land, and move the mirror in the same commit.

**`RecvKind` rides the cache as a u8.** Append new values; never renumber or reorder.

**`test/tsimportprecisecheck.sh` builds a comparison binary.** Its monotonicity arm builds one from HEAD
unless `RIPWIRE_HEADBIN` names one already built, which is slow on a busy machine. Build it once, then
reuse it.

**Don't commit decoy fixtures at repository scope.** A committed `export function replace` anywhere under
`test/` is indexed by every repo-wide run of the tool on itself, and changes this repository's own
graph. Generate fixtures under the gate's temp dir, as the KNOWN GAP block does.

---

## What the PR description should contain

- **The rule, stated precisely:** which receiver kinds, which chain links keep certainty, which casts end
  it, and what a prototype extension is allowed to bind.
- **Red first:** the flipped arms' FAIL count on the pre-change binary; the controls' PASS on both
  binaries.
- **The measurement:**
  - corpora and commits;
  - `edges=` and `external=` before and after;
  - the full removed-edge list (attached if long), with its classification;
  - the `--callers=stringify` spot check;
  - `ambiguous=` shown monotonic.
- **Versions:** the `kParserVer` bump, its mirror, the `test/qschemetrip.hash` re-pin, and proof that a
  cache written by the pre-change binary is rejected.
- **Scope, honestly:** what stays out (typed identifiers like #59's `text: string`, `JSON.stringify`,
  `this.field.m()`, the TS prototype spelling) and the next step this makes possible.
- **Links:** `Fixes` nothing yet. Say "first step on #59" and link #71's correction comment.

---

**Write the plan: the certainty table, the extraction and resolution changes, the flipped arms and new
controls, and the measurement protocol. Then STOP for my go-ahead.**

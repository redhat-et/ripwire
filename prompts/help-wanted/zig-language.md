# Add Zig to ripwire

You are adding **Zig** as an indexed language. This prompt is `prompts/add-a-language.md` with
LANG = `zig`, plus the Zig-specific decisions worked out in advance. Keep that file open beside this
one: its steps are authoritative, and this file does not repeat them. Where the two differ, this file
says what changed and why.

Work in a git worktree. Run gates in the foreground.

---

## Why this matters

Zig is a systems language, and its users build infrastructure:

- [TigerBeetle](https://github.com/tigerbeetle/tigerbeetle), a financial transactions database, is
  overwhelmingly Zig by GitHub's language count.
- The [Ghostty](https://github.com/ghostty-org/ghostty) terminal is mostly Zig.
- The [ZLS](https://github.com/zigtools/zls) language server is Zig.
- The Zig standard library lives at [codeberg.org/ziglang/zig](https://codeberg.org/ziglang/zig). The
  project [moved there from GitHub](https://ziglang.org/news/migrating-from-github-to-codeberg/) in
  November 2025, and the GitHub repository is now a read-only mirror.

Its compiler sits in the LLVM world. The
[0.15.1 release notes](https://ziglang.org/download/0.15.1/release-notes.html) describe the new
self-hosted x86_64 backend, now the Debug default, by comparison with LLVM, and LLVM stays selectable
with `-fllvm`.

Zig code is hard to navigate by grep. A type is a value bound by `const`. Generics are functions
evaluated at `comptime`. A file is imported as a value. A call graph and an import graph are what an
agent reading TigerBeetle's state machine is missing.

---

## STEP 0 for Zig — measure before you vendor

Run add-a-language.md's STEP 0 on the candidate below, at **both** pins, over a corpus you did not
write.

**The candidate** (checked 2026-09-11):
[tree-sitter-grammars/tree-sitter-zig](https://github.com/tree-sitter-grammars/tree-sitter-zig), MIT.

| pin | commit | date | ABI (`LANGUAGE_VERSION`) | notes |
| --- | --- | --- | --- | --- |
| tag `v1.1.2` | `b670c8df85a1568f498aa5c8cae42f51a90473c0` | 2024-12-22 | 14 | latest tag |
| `master` | `6479aa13f32f701c383083d8b28360ebd682fb7d` | 2025-09-10 | 15 | 8 commits past v1.1.2, including "ci: update corpus to Zig 0.15.1" |

- Both ABIs sit inside the vendored core's window. tree-sitter v0.26.9 accepts
  `TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION` 13 through `TREE_SITTER_LANGUAGE_VERSION` 15
  (`third_party/deps/tree_sitter/lib/include/tree_sitter/api.h`).
- Neither pin has an external scanner: `src/` holds `parser.c` only. So there is no `serialize()` for
  `test/vendorpatchcheck.sh` arm H to classify.
- An older alternative, [ziglibs/tree-sitter-zig](https://github.com/ziglibs/tree-sitter-zig) (MIT),
  was last pushed in July 2024. Measure it only if the first candidate fails.

**Which pin.** The house convention is a tagged commit, with the tag as a trailing comment in
CMakeLists.txt. Here the tag predates Zig 0.15's syntax changes, and `master` tracks them.

- Measure both pins on the same corpus, and pin the one that parses more.
- If the winner is the untagged commit, give the reason in the CMakeLists.txt comment, the way the
  Swift grammar's comment does.

**The corpus, and the dialect axis.** For Zig, the "dialect" is the language version. Zig 0.15.1
removed `usingnamespace` and the async/await keywords, so:

- code written for 0.14 still carries them;
- code written for 0.15 uses constructs an older grammar may reject.

Measure on at least two trees that target different Zig versions, and record the version each one
targets. Candidates: the standard library at a pinned Codeberg commit, TigerBeetle, Ghostty and ZLS.

**How to measure without ripwire support.** Write a throwaway C program outside the repository. It
links the candidate's `parser.c` against the vendored core and parses every `.zig` file. For each
file it records two numbers:

- whether `ts_node_has_error( root )` is true;
- the share of bytes inside ERROR subtrees.

The second number is the one the Metal entry in `src/ingest_crawl.h` reports: 0.81% of bytes under
the C++ grammar, against 12.3% under C. A file with one recoverable error still yields most of its
definitions.

Write both numbers into the plan, per corpus and per pin.

---

## Zig-specific design notes

**Scope — `@import` edges are STEP 5, and STEP 5 is optional.** add-a-language.md calls dependency
edges "optional, and a separate round", and that holds here. The first PR is registration,
definitions, calls, visibility, scaling and disclosure; resolving an `@import` specifier to a file in
the corpus is a second round unless your plan says otherwise. **Say which one you are doing, in the
plan, before you write anything** — three things below hang on the answer: the `fs.openFile()` edge,
the case-collision import fixture, and acceptance criterion 4. Deferring is fine. Leaving it unstated
is not, because a reader cannot tell a deferred edge from a missing one.

**Registration.**

- Append `Lang::Zig` at the **end** of `enum class Lang` in `src/model.h`.
- Add `.zig` to `kLangTable` in `src/ingest_crawl.h`. That table is a `std::array` sized by its row
  count, so a missing size bump fails to compile. That is on purpose.
- ZON data files (`.zon`, e.g. `build.zig.zon`) use Zig expression syntax. Claim them only if STEP 0
  measured them.

**What a definition is.**

- **Functions:** a top-level `fn`, including the `pub`, `export`, `extern` and `inline` forms.
- **Types are values.** `const Point = struct { … };` is how a type gets a name, and the same goes for
  `enum`, `union`, `opaque` and `error{ … }`. Name the symbol after the `const` binding, and give it
  the kind of the container it binds.
- **Methods are `fn` declarations inside a container body.** Scope-qualify them: `Point.distance`, not
  a bare `distance`. Read `src/ingest_elixir.h` first anyway — add-a-language.md calls it the most
  conventional extraction module — and follow how the existing extractors build scoped symbol ids
  rather than inventing a new scheme.
- **Files are values too.** `const fs = @import("fs.zig");` binds that file's top-level declarations
  to `fs`, so `fs.openFile()` is a call into `fs.zig`. This is the resolver's most valuable edge —
  and it *is* `@import` resolution, so it is STEP 5 and it follows **Scope** above. In this PR: make
  it the first thing a decoy fixture attacks. Deferred: `fs.openFile()` binds **nothing** — no edge,
  and above all no guess at a same-named definition somewhere else in the corpus — and the fixture
  pins that zero, with the blind spot disclosed alongside the others.
- **A function that returns `type` is a type constructor** (`fn ArrayList(comptime T: type) type`).
  A call to one is both a call edge and a type use. If the extraction cannot tell the two apart,
  disclose that. Do not guess.

**Visibility.** `pub` is the visibility keyword. Map it to publicness:

- `--edit-check` reports a publicness change against HEAD;
- `--quality-delta` counts growth in API surface.

**Tests.** The language reference allows three shapes:

- `test "name" { … }`;
- `test identifier { … }`, a doctest bound to a declaration;
- an anonymous `test { … }`.

Mint test symbols for them, so that `--test-gate` and `--affected` can name them. The closest
precedent is the Elixir extractor's handling of literal ExUnit tests, and `childwalkscalecheck.sh`
arm (A13) shows a string title becoming a symbol.

**Error sets.** `const FileError = error{ NotFound, AccessDenied };` is a named type. `!T` error
unions, `try` and `catch` are control flow, not calls.

**Calls.**

- `f()`, `value.method()` (method-call sugar on a container instance) and `Type.f()` are calls.
- `@`-prefixed builtins such as `@import`, `@field` and `@intCast` are not user functions. They must
  never bind to a user definition with the same name.
- #134 is the cautionary tale. A `std::`-qualified C++ call bound at full confidence to the
  repository's lone definition of that name, and one method gained 2,107 false callers on a real
  corpus.

**Dependency edges (STEP 5, optional and a separate round — see Scope).** `@import` takes a string
literal that names a module, a `.zig` source file, or a `.zon` data file (language reference,
`@import`). The four rules below apply **only if STEP 5 is in this PR**; deferred, `@import` yields no
edge at all, external or otherwise, and the PR's deferred-work list says so.

- **Modules.** `@import("std")` and `@import("builtin")` are modules, not files. Count them as
  external.
- **Relative paths.** `@import("dir/file.zig")` is a path relative to the importing file. Resolve it
  through the corpus index, never by building a path and probing the filesystem.
- **Build-wired modules.** `@import("some_pkg")` names a module wired up in `build.zig` or
  `build.zig.zon`. Nothing in the tree answers it, so it degrades to external, not to a guess.
- **Ambiguity.** If two files could answer a specifier, the answer is **neither**.

**Blind spots to disclose, not paper over.**

- declarations generated at `comptime` (`@Type`, `inline for` over `std.meta.fields`);
- calls through `anytype` or function pointers;
- `usingnamespace` re-exports in pre-0.15 code.

Each one shows up in the output as a floor, never as a silent zero.

**FFI (optional, later).** `extern fn` and `export fn` meet C. ripwire already resolves across
languages in `src/graph.h` (`langCompatible`), and open PR #126 bridges Kotlin and Java there. A
Zig↔C bridge is a second-round idea. Put it on the plan's "not now" list, unless the STEP 0 corpora
show heavy C interop.

---

## Constraints (CLAUDE.md)

These do not change for this kit:

- The gate comes before the code.
- Determinism is a contract: two runs are byte-identical, and a warm run equals a cold one.
- A zero means "none found".
- Never `VERIFY( false )` on a degrade path.
- Never use `std::map` or `std::unordered_map`.
- Style follows `CONTRIBUTING.md` §3.

**Grammars are vendored and pinned by full SHA.** Fix grammar bugs upstream. The only local edits are
crash or memory-safety fixes, carried as `third_party/patches/<dep>/NNN-name.patch` under
`test/vendorpatchcheck.sh`'s convention; yaml, markdown and swift already carry such patches.

**What add-a-language.md does not mention yet.** A gate enforces each of these today:

- **Vendored source.** The grammar must live under `third_party/deps/zig/`.
  `ripwire_use_vendored_source` in CMakeLists.txt refuses to configure without it and never fetches.
  That is what keeps "the build works with the network off" literally true.
- **Attribution.** `THIRD_PARTY.md` needs a row for the new directory. `test/dependencypincheck.sh`
  arm (A') derives its list from `third_party/deps/` itself (#131).
- **Child walks.** The O(C²) child-walk rule lives in `src/infra/tschildren.h` (since #127).
  - Any walk you write over an unbounded child list uses the cursor, or states at the loop why a
    comment cannot reach that list. Unbounded lists include container members, argument lists,
    error-set members and struct-literal fields.
  - Add a comment-flood isolation pair to `test/childwalkscalecheck.sh` for each such walk. A Zig `//`
    comment is a tree-sitter extra like any other.
- **README.** The README's Languages section is hand-written prose. Update both the grammar count in
  its summary line and a paragraph that says what the parser does and does not see.

---

## Known traps

- **One hostile file can abort a vendored parser.**
  - #126's review found Kotlin's external scanner calling `abort()` once its delimiter stack filled.
  - The yaml and markdown scanners once wrote past their serialization buffer on deep nesting; the
    fixes are in `third_party/patches/`, and the CMakeLists.txt comments tell the story.
  - Zig has no scanner, but the core parser still recurses. Run the ASan build over a generated Zig
    file with thousands of nested blocks, nested struct literals and nested `comptime` expressions,
    and over a 16,000-comment flood.
- **A memo whose key is narrower than its inputs** (add-a-language TRAPS). Zig resolves `a.b.c` by
  walking containers. If you memoize that walk, key the memo on the whole chain.
- **A case-insensitive filesystem** answers `@import("Parser.zig")` with `parser.zig`. Plant the
  decoy either way: with STEP 5 it proves the specifier resolved through the corpus index and not by
  a case-folded name; without STEP 5 it proves that nothing bound at all.
- **Parser versions collide across PRs.** `kParserVer` and `kIngestParserVerMirror` move in the same
  commit, and in-flight language PRs claim versions too; #126 records two collisions. Take the next
  free value on the tree you merge onto, not the one you branched from.
- **The standard-library corpus lives on Codeberg, not GitHub.** The GitHub mirror stopped at the
  move.
- **`main` collides by name.** `pub fn main` appears in many tool and example files. Two `main`s in
  two directories must not merge their callers.

---

## Acceptance criteria

1. **STEP 0.** Parse rate and ERROR-byte share per corpus and per pin; the chosen pin and the reason.
2. **Vendoring.** The grammar lives under `third_party/deps/zig/`, is pinned by full SHA in
   CMakeLists.txt, and has a `THIRD_PARTY.md` row. Configure succeeds with the network off.
3. **Definitions with spans.** Functions, container bindings (struct, enum, union, opaque, error set),
   scope-qualified methods and test blocks. `pub` is visible as publicness.
4. **A red-first gate.** `test/zigcheck.sh`, with fixtures in `test/zigfix/`. The fixtures are
   adversarial:
   - a decoy method name in another container;
   - a case-collision import — with STEP 5, the specifier resolves through the corpus index and the
     wrong-case file is not the answer; without STEP 5, no `@import` binds anything and the gate pins
     that zero as the disclosed behaviour, not as a silent absence;
   - two `main`s;
   - a builtin named like a user function;
   - a construct the grammar degrades on, with its disclosed behaviour.

   The gate is registered in `test/regression.sh`, and shown failing on a binary without the change.
5. **The arms from add-a-language STEP 7.** Spans, decoy, determinism, warm == cold, `xmllint`, and a
   relative vs absolute root.
6. **Scaling.** A comment-flood isolation pair for every new unbounded child walk.
7. **Memory safety and identity.** ASan/LSan clean over the real corpus and the hostile fixtures.
   `kParserVer` and its mirror, `test/qschemetrip.hash` and `test/printf_parity.manifest` handled as
   add-a-language STEP 4 describes.
8. **Disclosure.** The README Languages paragraph and count. The blind spots stated in the gate header
   and in the output. If STEP 5 is deferred, "`@import` is not resolved to a file" is one of those
   blind spots and is named in all three places — the gate header, the README paragraph and the PR —
   and no `@import` produces an edge or a guess in the meantime.
9. **STEP 8's suite** green in the foreground.

---

## What the PR description should contain

- **STEP 0.** The corpus × pin table of parse rate and ERROR-byte share, the Zig version each corpus
  targets, and the corpus commits.
- **The pin** and the reason for it.
- **Blind spots.** Each one, with where the output discloses it.
- **The gate.** Its red output, then its green output.
- **Memory safety.** The ASan/LSan result, and the hostile fixtures used.
- **Deferred work.** `@import` edges if they are not in this PR, the C bridge, and `.zon`.

---

**Write the plan — the STEP 0 corpora and harness, the rule that picks the pin, the symbol kinds, the
fixtures, and what is deferred — then STOP for my go-ahead.**

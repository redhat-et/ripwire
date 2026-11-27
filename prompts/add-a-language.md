# Add a language to ripwire

You are adding a **new language** to ripwire: a vendored tree-sitter grammar, symbol extraction, and
the disclosure that says what the new grammar cannot see. Call it **LANG** below and substitute the
real one everywhere — the extension too (`.sql`, `.kt`, `.ml`).

This is not a tour. It is the path an actual language took, reconstructed from the Elixir grammar
that landed in v0.5.0 (`f3cc02e3` through `3021ee5f`), because a plausible-looking checklist written
from memory would send you to the wrong files. **Every path below is one that commit touched.**

Work in a git worktree, not the main checkout. Run gates in the foreground.

Orient before you open files. `./build/ripwire . --for="register a new language: Lang enum, extension table, tags.scm"`
ranks the registration sites; `./build/ripwire . --grep='Lang::Clojure'` lists every arm the most recent
full language (Clojure, with call edges and keyword heads) had to touch. `CONTRIBUTING.md` §3, "Where
language-specific code lives", is the rule this prompt applies.

---

## STEP 0 — the measurement that decides whether to start

**Do this before writing any code, and be willing to stop here.**

Get a real corpus in LANG — thousands of files you did not write, ideally the ones you actually care
about. Run the candidate grammar over it and report **what fraction parses**.

A grammar that parses 95% of real-world LANG is worth vendoring. A grammar that parses 55% ships a
map whose honest header reads `unindexed="lang:1841"` on every run, and that is *worse than no
grammar at all* — a reader trusts a map that says nothing about LANG more than one that claims LANG
and silently loses half of it.

Dialects are where this bites: T-SQL vs ANSI, Kotlin vs Kotlin-with-compiler-plugins. Community
grammars usually target the standard dialect and degrade on vendor extensions.

**Write the parse rate down in the PR.** If it is low, that is a finding, not a failure — the honest
product may be lexical indexing with a disclosed floor rather than a grammar.

---

## STEP 1 — vendor the grammar (guardrail G3)

Grammars are compiled from source, pinned by commit SHA, and **never patched**. If the grammar is
wrong, fix it upstream; this repo does not carry a fork.

- `CMakeLists.txt` — `add_ts_grammar( LANG <git-url> <full-commit-sha> )`. Pin a SHA, never a tag or
  a branch. Then add `LANG` to the grammar list, `$<TARGET_OBJECTS:ts_LANG>` to the link line, the
  `ts_LANG` entry in the object list, and `add_ripwire_fuzzer( LANG tree_sitter_LANG LANG )`.
- `queries/LANG/tags.scm` — the capture file. Copy the closest existing language and cut it down;
  start with definitions only, no call edges.

The build must still complete **with the network off**. That is the point of vendoring.

---

## STEP 2 — register the language

- `src/model.h` — add to `enum class Lang`. **Append at the end**; the values are serialized into
  the cache, so reordering invalidates every cache in the world. `kLangCount` derives from the last
  entry, so it follows automatically. Add the `case Lang::LANG: return "ext";` arm.
- `src/ingest_crawl.h` — the extension table: `{ ".ext", Lang::LANG, &tree_sitter_LANG, "LANG" }`.
- `src/lintrules.h` — the extension→Lang map. Add to `dependencyCapable()` **only** if you are also
  doing STEP 5; claiming it without edges makes the `dep_files=` denominator lie.

---

## STEP 3 — extraction

**A language is data first, and C++ only where its semantics truly differ.** What is common must stay
common: twenty languages each carrying a private copy of the same idea is twenty places to fix one bug.

- `queries/LANG/tags.scm` — this is where most of a language lives. Use **only the shared capture
  vocabulary**: `@name`, `@definition.{function,method,class,struct,interface,var,constant,macro,module,type,field}`,
  `@reference.{call,import,implementation,type}`. Do not invent a language-named capture
  (`@definition.LANG`, `@LANG.head`); every consumer downstream has to learn a new name for it.
- `src/langfacts.h` — one `kLangFacts` row: the per-language facts (receiver rules, comment markers), one
  column each. A missing row, or a missing `Must<T>` column, is a compile error. Add a column rather than a
  new `l == Lang::X || …` compare in a shared file; `test/langidentitycheck.sh` counts those and may only fall.
- The exhaustive `switch( Lang )` tables (`langTag`, `isCodeLang`, `dependencyCapable`, …) — the compiler
  lists every one you missed (`-Werror=switch`). A row each, no logic.
- Then the arms the compiler cannot see: `grep` for a recently added language (`Lang::Elixir`) and read
  every hit. Lists and masks are not switches — e.g. `kAllCatalogLangs` in `src/lintcatalog.h`, the
  `langBit` masks in `src/clones.h`, `wordLang` in `src/ingest_metrics.h`. Semantic hooks (arity,
  params, attributes) live today in the per-language branches of `src/ingest_sidecap.h`.
- Per-language C++ is for semantics the grammar cannot express. **Before writing a helper, look for the
  shared one:**

  | You need | Use (do not copy) |
  |---|---|
  | the scope a definition sits in | `enclosingScopeOf` (`src/ingest_names.h`) |
  | a local that shadows a global name (`let`, params) | a `VarDecl` binding with its block span — the generic shadow pass (`suppressShadowedReferences`) does the rest |
  | imports / aliases / `require … :as` | `Binding` / `Include` facts (`src/model.h`), as JS imports and Elixir aliases already do |
  | module-qualified calls (`Mod.f`, `ns/f`) | no language-neutral resolver exists yet; `src/elixir_resolve.h` is Elixir-specific and the only one. Raise generalising it in your PR rather than writing a `LANG_resolve.h` beside it |

  Then run `ripwire --clones` on your tree: your new code should add no clone group.
- **The target rule: a qualified call you cannot resolve is counted as unresolved — never sent to the global name ladder.**
  `(str/join …)` laddered to every `join` in the corpus mints edges that are not real (the PR #81 decision:
  the ladder gave one Elixir function 55 callers where 3 were real). **Known gap:** today only Elixir, Rust and
  C++ `std::` calls have such a rule; a language that newly sets `Reference::qualifier` still falls through to
  the bare-name ladder when no `qualifier::name` definition exists — #349's Clojure `str/join` binds an in-tree
  `join` this way (CONTRIBUTING.md, "Refuse, don't guess", slices 6a and 6b).
  Do not add a guard for your language alone: pin the wrong edge as a known-gap arm and say so in your PR.

**Keyword heads are data.** Since #355 (closed 2026-11-18) the tags pass evaluates the string predicates
`#eq?`, `#not-eq?`, `#any-of?` and `#not-any-of?` (`src/infra/tspredicates.h`; never `#match?`). A
language whose definitions are *a call with a keyword head* — Elixir `def`, Clojure `defn` — keeps that
keyword list in its `tags.scm` as an `#any-of?` list, as `queries/elixir/tags.scm` does on `@_keyword`;
C++ that needs the same list reads it back from the compiled query (`predicateStrings`) instead of
keeping a copy. `test/tagspredicatecheck.sh` holds these rules. `src/ingest_elixir.h` still holds
Elixir's arity, params, attribute and alias logic; it is **not a template to copy**.

If the shared mechanism you need does not exist, say so in the PR. We would rather add it with you than
see the pattern forked.

Extract **definitions with spans** first. Call edges are a separate round.

---

## STEP 4 — extraction identity, the trap that costs an afternoon

Two constants must move **in the same commit**:

    src/ingest_cache.h    kParserVer
    src/quality.h         kIngestParserVerMirror     MUST equal it (gated)

Miss the mirror and the build stops on a `static_assert` in `src/ingest_cache.h`;
`qextractionkeycheck` checks the same pair, and its version-mismatch report reads like a totally
unrelated bug. Bump on **any** grammar, `.scm`, or extraction change — the cache is keyed on
it, and a stale cache serving old symbols for new code is the worst failure this tool has.

**Do not take the next integer blindly.** Parallel pull requests each need their own number, and the
maintainers assign you a parser version number in the PR.

Then regenerate `test/qschemetrip.hash` and update `test/printf_parity.manifest`.

---

## STEP 5 — dependency edges (optional, and a separate round)

Only if LANG has a resolvable import spelling. `src/resolve.h` (the extension→`IncludeLang` map and
the resolver arm), `src/ingest_relations.h`, and `dependencyCapable()` in `src/lintrules.h`.

`dependencyCapable()` is read directly and through derived helpers (`dependencyCapableMask`,
`dependencyCapableLangTags`, and `dependencyPairCapable` — the co-change pair filter in `src/gitmine.h`,
the one people miss). Run `./build/ripwire . --uses=dependencyCapable` and
`./build/ripwire . --impact=dependencyCapable` before you change it.

Resolve through the **corpus's own index**, never a name→path guess. A specifier that two files
answer must degrade to *neither*, not to the first one found.

---

## STEP 6 — disclosure: what the grammar cannot see

This is the step that makes the difference between a contribution and a liability.

Every language has blind spots — dynamic dispatch, macro-built names, a dialect the grammar declines.
Find yours and make the tool **say so in its output**, not in a comment:

- files that fail to parse fall back to lexical indexing and are **counted**, never silently dropped
- `kUnanalyzedLangs` if the lens cannot answer for LANG
- a count that cannot be a total carries `counts_floor="1"`
- a zero means *none found*, never *none exists*

Write the blind spots into the gate header. **A disclosure surface that under-reports is worse than
one that is absent.**

---

## TRAPS — each one cost somebody a day here

**A memo whose key is narrower than its inputs.** Found in PR #57 (Ruby constants) by an automated
reviewer, reproduced, and fixed before merge. If your resolution *walks* — tries `A::B::Name`, then
`A::Name`, then `Name` — and you memoize it, the key must carry the **whole chain**, not the
innermost frame. Two sites with the same innermost scope and different chains have different correct
answers.

What made it nasty: the wrong answer was **deterministic**, so the determinism arm passed. It varied
with *which other files were in the corpus*, and with their **filenames**, because crawl order
decides who poisons the memo first. In one order it invented an edge; in the other it suppressed a
correct one. Renaming a file changed the graph.

    a_nested.rb visits BEFORE the compact form   ->  2 edges   (one invented)
    z_nested.rb visits AFTER  the compact form   ->  0 edges   (one suppressed)
    correct answer, both orders                  ->  1 edge

Only languages with **lexically scoped name resolution** need a walk at all — Ruby constants today,
plausibly Kotlin or Scala imports. Elixir cannot have this bug: it looks up a fully-qualified name in
one `find()`, one key, one answer. If your language needs no walk, do not add a memo.

**A case-insensitive filesystem resolving a name you never meant.** macOS will happily answer a probe
for `Trackable` with `trackable.rb`. Plant a decoy in the fixture and assert the *right* file wins.

**The `Lang` enum is serialized into the cache.** Append only. Reordering invalidates every cache in
existence, silently, and the symptom appears somewhere else entirely.

---

## STEP 7 — the gate, written RED first

Write `test/LANGcheck.sh` **against a binary that does not yet have your change, and watch it fail.**
A gate that has never failed is not evidence it can detect anything.

Then register it in `test/regression.sh` in the **same commit** — `test/manifestcheck.sh` fails
otherwise.

Fixtures go in `test/LANGfix/`. Make them adversarial, not illustrative:

- a **decoy** — the same symbol name in a file that must *not* win
- a case-collision, if the filesystem could resolve it wrongly
- a construct the grammar handles badly, asserting the *disclosed* behaviour

Arms worth having, from `test/elixircheck.sh` and `test/rubyrequirecheck.sh`:

    definitions land with the right spans
    the decoy does not win
    two runs are byte-identical            (determinism is a contract)
    warm == cold                           (survives the cache round-trip)
    output is well-formed XML
    a relative and an absolute crawl root resolve identically

---

## STEP 8 — before you open the PR

    cmake -S . -B build && cmake --build build -j
    python3 test/pargates.py . ./build/ripwire -j 6          # the full suite
    cmake -S . -B asan -DRIPWIRE_ASAN=ON && cmake --build asan -j
    LSAN_OPTIONS=suppressions=lsan_suppressions.txt ./asan/ripwire <corpus> >/dev/null

Build **fresh**, not incrementally — a language change touches `src/model.h`, and an incremental
build across that produces objects that disagree about `sizeof(Symbol)`. `CONTRIBUTING.md` and
`CLAUDE.md` document what that looks like; it costs hours and every symptom points somewhere else.

In the PR, state: **the parse rate from STEP 0**, the corpus you measured on, and the blind spots you
disclosed. Those three are what the review is actually about — the grammar is the easy part.

**Write the plan — the STEP 0 corpus and how you will measure its parse rate, then the files each step
touches — then STOP for my go-ahead.** If the parse rate decides against a grammar, the plan says so
and ends there.

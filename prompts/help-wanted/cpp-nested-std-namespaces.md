# Resolve nested `std::` calls by their whole qualifier chain

You are fixing how ripwire resolves C++ calls into **nested standard-library namespaces**:
`std::ranges::move`, `std::chrono::duration_cast`, `std::filesystem::exists`. Today such a call can
bind to an in-repo definition it has nothing to do with, at full confidence, with no `amb=` to warn
anyone. The gate arms that pin today's wrong answers already exist: **`test/stdqualcheck.sh` §11,
labelled `KNOWN GAP`. Your finish line is flipping them.**

This is resolver work in the part of the tool C++ users lean on hardest: the call graph that
`--callers`, `--impact`, `--path` and the ranking all read as fact.

Work in a git worktree, not the main checkout. Run gates in the foreground. Read `CLAUDE.md` and
`CONTRIBUTING.md` §3 before writing C++.

---

## Why this matters

PR #134 fixed the flat case. A call written `std::X( … )` used to bind the repository's lone
definition named `X`. On memgraph, `SafeString::move` had **2,107** false callers from `std::move` and
was row #1 of the whole map; in ripwire's own graph `std::min` / `std::max` / `std::sort` bound in-repo
members (`--callers` 131 / 67 / 7 before, 5 / 14 / 2 after). The guard #134 added,
`keepStdQualifiedCandidates`, reads the call's **immediate** qualifier: it sees `std` in `std::move`
and `ranges` in `std::ranges::move`. The one false caller #134 left on `SafeString::move` is a
`std::ranges::move`.

The nested case is the modern-C++ case. C++20 and C++23 code spells algorithms `std::ranges::`, time
`std::chrono::` and paths `std::filesystem::`, so every such codebase meets it.

It is also worse than the flat bug, because of the **canonical tier**. Libraries that mirror std's
layout (Boost.Chrono's `boost::chrono::duration_cast`, Boost.Filesystem's `boost::filesystem::exists`)
own a definition whose immediate scope is `chrono` or `filesystem`. A `std::chrono::duration_cast` call
keys `chrono::duration_cast`, hits that definition at the canonical tier, and #134's guard exempts
canonical hits by design. Measured in this repository: a temporary, uncommitted copy of the §11 fixture
under `test/` gave `--callers=duration_cast` **count=7**, among them ripwire's own `now_ticks`
(`src/infra/profileScope.h`) and `wallClockNs` (`src/ingest_crawl.h`). Their real
`std::chrono::duration_cast` calls bound to a test decoy. Any tree that vendors a std-mirroring library
beside modern std code has this shape.

Who benefits: every agent or reviewer who asks ripwire "who calls this?" in a C++20+ codebase, and
every ranking computed over those edges.

---

## Background: where the pieces live

- `src/graph.h`: `keepStdQualifiedCandidates`, the #134 guard. Its comment block says which references
  it applies to (`Lang::Cpp` and `Lang::ObjC`, never a canonical hit), which candidates survive (scope
  `std`, a scope written `std::…`, or a standard library's inline ABI namespace), and the three
  **stated floors** this task closes. The tier-3 canonical-rescue comment right below it explains why a
  canonical hit counts as pinned.
- `src/externalnames.h`: `kStdInlineNamespaceNames` (`__1 __2 __8 __Cr __cxx11 __ndk1`), with the
  provenance of each spelling and why only reserved spellings qualify.
- `src/ingest_names.h`: `qualifierOf`, `immediateScope`, `enclosingScopeOf`, `operatorNameStart`. Both
  sides keep only the **immediate** segment: `Reference::qualifier` on the call side, `Symbol::scope`
  on the definition side.
- `src/ingest_sidecap.h`: a C++ call reference gets `r.qualifier = qualifierOf( … )` for `Lang::Cpp`
  only (`Lang::ObjC` gets none), then the "H4 RE-SPLIT" block recovers the name and immediate qualifier
  from the text of a 3+-segment call. A definition gets `d.scope = qualifierOf( … )`, else
  `enclosingScopeOf( … )`.
- `src/model.h` `struct Reference`, and `src/ingest_cache.h` `RawRef` with `writeRef` / `readRef`: the
  cached record a new per-reference field would join.
- `test/stdqualcheck.sh` with `test/stdqualfix/`: #134's gate. §7 pins the ObjC++ floor. **§11 is this
  task:** three `KNOWN GAP` arms (K1 to K3), their census twins, a header arm, and three `CONTROL` arms.
  Its corpus is written into `$TMP` at run time; read the section comment before adding C++ under
  `test/`.
- Neighbours on the same ladder: `test/cppqualcheck.sh`, `test/cppoperatorcheck.sh`.

---

## Reproduce the gap

```bash
cmake -S . -B build && cmake --build build -j
bash test/stdqualcheck.sh      # ALL PASS today: the KNOWN GAP arms pass because they pin the wrong answers
```

To look at it by hand, pull §11's four heredocs into a scratch corpus:

```bash
S="$( mktemp -d )"
awk -v d="$S" '/^cat >"\$NEST\/[a-z.]+" <<.EOF.$/ { f = $2; sub( /^>"\$NEST\//, "", f ); sub( /"$/, "", f ); out = d "/" f; next }
               /^EOF$/ { out = ""; next }
               out != "" { print > out }' test/stdqualcheck.sh
./build/ripwire "$S" --callees=shiftRange --no-cache    # K1: count=1 -> Pool::move (std::ranges::move)
./build/ripwire "$S" --callees=toMillis --no-cache      # K2: count=1 -> vendorlib::chrono::duration_cast
./build/ripwire "$S" --callees=bail --no-cache          # K3: count=1 -> a declaration-only std::terminate
./build/ripwire "$S" --pin-census="$S.tsv" --no-cache >/dev/null && grep '^C' "$S.tsv"
```

The census `mech` column names the stage that decided each site. K1 and K3 are `unique` (the bare-name
spray); K2 is `qualified` (the canonical tier). The ObjC++ half lives in the committed fixture:
`./build/ripwire test/stdqualfix --callees=bridgeStop --no-cache` binds `Cursor::unreachable`, because
`bridge.mm`'s `std::unreachable()` reaches resolution with no qualifier at all.

---

## Design space and constraints

One shape that works. The choices inside it are yours, and the PR should argue them.

1. **The call side must know where the written chain is rooted.** Either a new field holding the full
   written chain (`std::ranges`), or one bit meaning "rooted at `std`, `::std`, or an inline ABI
   namespace directly below it". Keep `qualifier` the immediate segment either way: the canonical key,
   the Rust guard, the operator re-split and receiver narrowing all read it. The bit is smaller; the
   chain would serve a later alias rule. Measure the cache-file size on a large corpus before and after.
2. **The definition side must know it too.** `namespace std { namespace ranges { … } }` gives today's
   definition the scope `ranges`. Record a rooted-in-std fact at extraction, where the parent walk is
   cheap, and handle the C++17 spelling `namespace std::ranges { … }`.
3. **The guard follows the root at every tier.** A std-rooted chain may bind only a std-rooted
   definition, and that includes a canonical hit: K2 proves the canonical exemption is wrong for a
   std-rooted chain. A chain that is not std-rooted keeps today's ladder byte for byte (§8's alias arm,
   and §11's `sampleTicks` control).
4. **Declaration-only std definitions (K3).** Decide what a std-qualified call does against a definition
   inside std that has no body in the corpus. Refusing matches #134's reasoning (a library entity with
   no in-repo evidence), but a bodyless declaration next to a real out-of-line definition must still let
   the definition win. Find out whether extraction already tells a prototype from a definition before
   you add a flag. If you keep the edge and disclose it instead, argue that and rewrite K3 to assert the
   disclosure.
5. **ObjC++, if feasible.** tree-sitter-objc leaves an ERROR node spelling `std::` beside a bare call.
   Recovering the qualifier means reading that sibling's text. Keep it bounded, and never invent a
   qualifier from an unrelated error. If you do it, §7's `FLOOR` arm flips; if you don't, disclose it.

The non-negotiables from `CLAUDE.md`:

- **Gate before code.** New shapes go into §11 first and must fail on your pre-change binary.
- **Determinism.** Output may not depend on thread timing, hash order or pointer values.
- **Honesty.** A refused site goes through the existing `vetoExternal` path: `external=` in the header,
  one `C external` census row, no edge. A zero means none found, not none exists.
- **`DEGRADED_PATH_ALERT`, never `VERIFY( false )`**, on any degrade path.
- **No `std::map` / `std::unordered_map`.** Use sorted arrays and `std::binary_search` with
  `rw::sortutil::svLess`, as `kStdInlineNamespaceNames` does.
- **Style:** Allman braces, braces on every body, spaces inside parens (`CONTRIBUTING.md` §3).
- **Build discipline:** plain dev build with no build type; never edit the tree while a build runs;
  after a branch switch or a `src/model.h` change, `cmake --build build --clean-first -j`.
- **Versions.** Any extraction change bumps `kParserVer` (`src/ingest_cache.h`) and
  `kIngestParserVerMirror` (`src/quality.h`) in the same commit. A new field in the cached per-file
  record also bumps `kCacheVersion` and `kIngestCacheVersionMirror`. Then re-pin with
  `UPDATE_GOLDEN=1 test/qschemetripcheck.sh` and add a RE-PIN LOG entry to that gate's header saying
  why. `test/qextractionkeycheck.sh` asserts the mirrors.

---

## Acceptance criteria

1. **The KNOWN GAP arms flip.** K1, K2 and K3, their census twins and the header arm go red on your
   binary. The same commit rewrites each to the corrected literal its PASS message names (`count=0`, one
   `external` census row, header `edges=3 external=3`) and drops the `KNOWN GAP` label.
2. **The controls hold:** §11's `drain`, `sampleTicks` and `hasAnswer`, and every arm in §1 to §10. Any
   literal that moves gets a sentence in the gate header saying why.
3. **Red-first arms you add**, each with its pre-change reading recorded the way #134 recorded its own:
   the `::std::chrono::` spelling; `namespace std::ranges { … }`; an inline ABI namespace above a nested
   one (`std::__1::ranges::`); a user namespace that is itself named `std` below another
   (`mylib::std::f()`, which is not std-rooted); and `using namespace std::chrono;` with an unqualified
   call, which stays unchanged.
4. **Mutations, each run and recorded:** chain root ignored → K1 and K2 red; canonical exemption kept
   for std-rooted chains → K2 red; definition-side root ignored → `hasAnswer` red.
5. **Measurements in the PR:** on a large C++20+ corpus you can name, the `--no-cache` header's
   `edges / ambiguous / external` before and after, `--callers` on the worst false target before and
   after, map wall time, and cache-file size if you added a field. On ripwire itself, the same header
   before and after.
6. **Gates:** `test/stdqualcheck.sh` on the plain and ASan builds, `test/cppqualcheck.sh`,
   `test/cppoperatorcheck.sh`, `test/qextractionkeycheck.sh`, `test/qschemetripcheck.sh`,
   `test/cacheidentitycheck.sh`, `test/cachefuzzcheck.sh`, then
   `python3 test/pargates.py . ./build/ripwire -j 6`. Two runs on your corpus are byte-identical and pass
   `xmllint --noout`, and `LSAN_OPTIONS=suppressions=lsan_suppressions.txt ./asan/ripwire <corpus> >/dev/null`
   is clean.
7. **Before you call it done:** `./build/ripwire . --quality-delta --legend=compact` is clean, and
   `./build/ripwire . --edit-check=keepStdQualifiedCandidates` shows no broken caller.

---

## TRAPS

**The fixture is the live repo.** Every C++ file committed under `test/` is crawled by ripwire's own map
and by every gate that reads it. §11 writes its corpus at run time because a committed `duration_cast`
decoy was measured taking ripwire's own callers. Put new shapes in heredocs, or use names that
`git grep` shows the tracked sources never call.

**A memo key narrower than its inputs.** If you cache "is this chain std-rooted" per scope, key it on the
whole chain. `prompts/add-a-language.md` shows how a narrower key produced a wrong answer that was still
deterministic, and so passed the determinism arm.

**Template arguments contain `::`.** In `std::chrono::duration_cast<std::chrono::milliseconds>( s )`
the chain is what comes before the argument list. The re-split already strips template arguments before
it splits; the `>`-family operator names have their own path (`operatorNameStart`). Reuse both.

**Aliases and using-directives are a different round.** After `namespace fs = std::filesystem;`, the
call `fs::exists( p )` reaches resolution with qualifier `fs`. Resolving aliases is not this task. State
it as a floor in the gate and the PR rather than half-solving it.

**Version bumps collide.** Open PR #135 also bumps `kParserVer` and `kCacheVersion`. Two lanes can land
on the same number without a textual conflict. Take the next free value when you land, re-pin
`test/qschemetrip.hash`, and re-run `test/qextractionkeycheck.sh` on the merged tree.

**`external=` rises, and that is correct.** Refused sites are counted, not dropped. Say so with the
numbers, as #134 did, so a reviewer does not read it as a regression.

**A sanitizer report after a branch switch** whose buffer size divides evenly by an old
`sizeof(Symbol)` comes from a mixed-object build, not from your change. Rebuild with `--clean-first`
before debugging it.

---

## What the PR description should contain

- The bug in two sentences, one fixture line, and the census `mech` before and after.
- The encoding you chose (chain field or root bit), why, and its measured cost.
- The rule, exactly: which chains it covers, which definitions survive, what happens at the canonical
  tier, what happens to declaration-only std definitions, and whether ObjC++ is done or disclosed.
- Evidence: red-first counts on the pre-change binary, each mutation's result, the full suite, ASan
  and LSan, determinism.
- The measurement table, and the version bumps with their RE-PIN LOG entry.
- The gaps you leave, disclosed in the gate header as well.
- For a corpus under a restrictive licence (memgraph is BSL): counts only, never its code.

---

**Write the plan — the encoding, the files you will touch, the red-first arms you will add first, the
corpus you will measure on, the version bumps — then STOP for my go-ahead.**

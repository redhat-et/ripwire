# Carry the member-macro re-parse past its first bounds, and let every verb see the repaired tree

> **Prerequisite: PR #135 must be merged.** This prompt builds on `src/macroreparse.h`,
> `src/extentsuspect.h`, `test/macroreparsecheck.sh` and `test/extentcheck.sh`, which that PR adds.
> If `git log --oneline -1 -- src/macroreparse.h` prints nothing on your base, stop here: the code this
> prompt describes has not landed.

You are extending a **parse repair** for C, C++ and Objective-C files that function-like macros knock
off course. tree-sitter reads a semicolon-less macro invocation as the last member of a struct as a
field declaration missing its `;`. Its error recovery then dissolves the earlier structs, files the free
functions that follow as methods, and in C swallows whole functions into ERROR nodes. PR #135 added a
detector that marks such rows `extent_suspect=` and a re-parse that repairs the commonest shape. It left
four gaps open on purpose, and disclosed each one.

This round closes the gaps **that measurement says are real**, with the discipline that bounded the
first round. That includes proving a gap has no producer and writing that down instead of widening.

Work in a git worktree, not the main checkout. Run gates in the foreground. Read `CLAUDE.md` and
`CONTRIBUTING.md` §3 before writing C++.

---

## Why this matters

- **The failure is not cosmetic.** Before #135, one memgraph file had 472 of its 487 definitions
  misfiled. A 14-line function, `PrintFuncSignature`, reported `cx=749 ccx=920` and ranked #4 in
  `--hotspots`, and nothing on the row said anything was wrong. After #135 it is a free function with
  `cx=3 ccx=2 loc=15`.
- **Most flagged rows remain.** #135 measured **241 extent-suspect definitions in 9 files** still on
  memgraph (93 of them in `eval.hpp`), and 1,650 → 1,483 on an llvm-project checkout. A flagged row is
  honest, but an agent still cannot use it: its scope, kind and complexity are guesses.
- **One tool, two answers.** `--match`, `--lint` and `--slice` parse files themselves, so they still
  see the FIRST parse (#135 says so in its known limits, and the code agrees). On a repaired file the
  map reports the repaired structure while a structural query over the same bytes walks the derailed
  tree. Your first red-first arm records exactly how far the two disagree.
- **Who benefits:** anyone mapping C or C++ built on macro-generated members: Qt-style, Unreal-style,
  exception or type registration macros. That is where agents most need a map, and where parsers break.

---

## Background: where the pieces live

- `src/macroreparse.h`: the scanner and the adoption rule. **Read its header comment in full first.**
  It records the candidate definition (an ALL-CAPS `_*[A-Z][A-Z0-9_]*` name, first on its line, directly
  in a class/struct/union body, after a member boundary, parentheses balanced on the line, followed by
  the start of a member) and, under "WHY THESE BOUNDS", the measurements that set each bound.
- `src/ingest_sidecap.h`: `measureHealthAdoptingMemberMacroReparse`, where ingest runs the scan, blanks
  the invocations, re-parses, and adopts on strictly fewer error bytes; `appendBlankedMacroUses`, which
  keeps each blanked invocation as a `role=type` use so `--uses` does not change.
- `src/extentsuspect.h`: the detector's four rules (`name`, `head`, `scope`, `error`) and the
  `--hotspots` exclusion.
- Disclosure surfaces: `extent_suspect=` on map, `--for`, `--expand` and `--json` rows;
  `extent_suspect_syms=` on the header; `--skipped` per-file rows with `why=macro-blanked`,
  `macro_blanked=N` and `macro_blanked_files=`.
- The verbs that parse on their own (function names, so they survive line drift): `astQueryGrouped` in
  `src/ingest_astquery.h`, reached from `runMatchQuery` and `builtInLintCaptures` in
  `src/verbs_lint.h`; `sliceScanDefinition` in `src/slice.h`, reached from `runSlice` in
  `src/verbs_navigate.h`. Confirm with `./build/ripwire . --callers=rw::astQueryGrouped` and
  `--callers=slicev::sliceScanDefinition` on your base. Other callers may exist.
- Gates: `test/macroreparsecheck.sh` (arms A to I and U; `RIPWIRE_BASE_BIN` adds the byte-identity and
  reproduction arms), `test/extentcheck.sh`, and the unit drivers `test/macroreparse_unit.cpp` and
  `test/extentsuspect_unit.cpp`. Fixtures: `test/macroreparsefix/` and `test/extentfix/`.

---

## STEP 0: the measurement that decides what to build

**Do this before writing code, and be willing to narrow the round to what it finds.**

#135's scanner header records two measurements that cut against the obvious widenings:

- **Lowercase.** Allowing *any* identifier found **zero** extra class-body candidates on the three
  corpora measured. Lowercase does derail the grammar, but a lone lowercase `f(x)` line is also how a
  constructor-shaped declarator continues onto the next line. `test/extentfix` keeps a lowercase run
  on purpose, so the detector still has a live producer.
- **Namespace scope.** Invocation runs at namespace scope recover as a zero-width MISSING `;` with the
  structure intact. Admitting them added adoptions and removed **no** `extent_suspect` flag on either
  external corpus. (Checked again on main 766913d0 while writing this prompt: three namespace-scope and
  file-scope run shapes kept every definition in place, with no phantom rows, as `degraded-parse`.)

So the remaining flags may come from neither shape. Take a corpus you can inspect and publish about
(llvm/lib is the reference corpus #135 used), run the merged binary, and **classify every flagged
file by the construct that derails it**:

```bash
./build/ripwire <corpus> --skipped --no-cache       # per-file rows: why=, err=, extent_suspect_syms=
./build/ripwire <corpus> --no-cache | grep -o 'extent_suspect="[a-z,]*"' | sort | uniq -c
```

Open each flagged file at its first ERROR node. Record: lowercase member macro, namespace-scope run,
something else (name it), or unknown. **Put that table in the PR.** Build the widening only for a
class with real producers; for a class with none, record the zero and leave its bound in place.

---

## STEP 1: route `--match`, `--lint` and `--slice` through the adopted tree

This gap is certain, whatever STEP 0 finds.

- Factor the parse-and-maybe-adopt sequence into one helper that ingest and the self-parsing verbs all
  call, so there is one adoption rule and one place it can drift.
- **Offsets are the contract.** Blanking keeps every byte offset and newline, so a node from the adopted
  tree indexes the original bytes. Every verb must read captures from the **original** bytes, never
  from the blanked copy, or a capture overlapping a blanked span reads as spaces.
- Decide what `--lint` and `--match` do with a query that targets the macro invocation itself: it is
  gone from the adopted tree. Choose a behaviour (for example, run on the first tree when the query
  names such a node), disclose it in the verb's legend, and gate it.
- Red-first arm (in `test/macroreparsecheck.sh`; do not add a gate file): on a leak fixture, a `--match`
  for function definitions returns the same names and lines as the repaired map and as the semicolon
  twin. Record the pre-change reading. The same arm for `--slice` on a function that follows the
  derailing struct.

---

## STEP 2: widen the scanner, only where STEP 0 found producers

For each widening:

1. Add the shape to `test/macroreparse_unit.cpp` and a leak fixture, with its **control twin**, before
   the scanner changes. Watch both fail.
2. Keep the scanner **per-file and pure**. Evidence from another file (a `#define` in a header) would
   make one file's parse depend on another file's bytes. The per-file cache is keyed on the file's own
   content, so a changed header could leave a stale parse in the cache. If you need corpus-wide evidence,
   the cache design must change first; argue that separately.
3. Prove it on llvm/lib and on your fixture:
   - extent-suspect definitions before and after;
   - files re-parsed and files adopted, before and after;
   - **byte-identical output for every file whose first parse is clean** (map, `--metrics`, `--for`,
     `--expand`, `--skipped`, `--json`), using `RIPWIRE_BASE_BIN` the way `macroreparsecheck` arm (F)
     does;
   - a hand check of at least 8 newly adopted files against source, as #135 did.
4. If the widening costs a live producer the detector relies on (the lowercase run in
   `test/extentfix`), move `extentcheck`'s producer to a shape the scanner still refuses, and say which.

---

## STEP 3: partial repairs and what `err=` means

Today a partial repair is adopted whenever it holds fewer error bytes. `err=` then describes the
adopted parse, so it can **rise** while `err_ratio` falls: on `mg_procedure_impl.cpp`, error nodes went
1 → 50 while error bytes fell 271,971 → 376. That is correct but easy to misread. Options: disclose the
first parse's figures beside the adopted ones, or change the adoption rule. Changing the rule needs its
own STEP 0. #135 measured that a node-count rule rejects exactly the file the pass exists for.
`docs/METHODOLOGY.md` §9 applies: honesty lives in attributes, and a legend line defines every
attribute that is emitted.

---

## Constraints (CLAUDE.md non-negotiables)

- **Gate before code.** Every new shape and verb route gets a red-first arm in an existing gate, with the
  pre-change reading recorded in the gate header.
- **Determinism.** The parse pool reuses per-worker scratch across files (`MemberMacroReparse`). Any
  state a widening adds must be reset per file, or the result depends on which worker saw which file
  first.
- **Honesty.** New attributes are absent at zero, defined by the legend only on output that carries them,
  and counted in the headers. A skipped repair is disclosed, never silent.
- **`DEGRADED_PATH_ALERT`, never `VERIFY( false )`**, when a re-parse fails or is refused.
- **No `std::map` / `std::unordered_map`.** Sorted vectors and `std::binary_search`.
- **Style:** Allman braces, braces on every body, spaces inside parens (`CONTRIBUTING.md` §3).
- **Build discipline:** plain dev build with no build type; never edit while a build runs; build a
  separate base tree for `RIPWIRE_BASE_BIN`, and never switch branches under a running build.
- **Versions.** A scanner or adoption change is an extraction change: bump `kParserVer`
  (`src/ingest_cache.h`) with `kIngestParserVerMirror` (`src/quality.h`). A change to the per-file cache
  record also bumps `kCacheVersion` with `kIngestCacheVersionMirror`. Then run
  `UPDATE_GOLDEN=1 test/qschemetripcheck.sh`, add a RE-PIN LOG entry, and re-run
  `test/qextractionkeycheck.sh`.

---

## Acceptance criteria

1. The STEP 0 classification table is in the PR, for a named public corpus.
2. `--match`, `--lint` and `--slice` agree with the map on every adopted fixture, gated red-first, with
   the macro-targeting query behaviour decided, disclosed and gated.
3. Each widening you ship has a red-first unit case, a leak fixture and a control twin, and its llvm/lib
   before-and-after numbers. Files with a clean first parse stay byte-identical against
   `RIPWIRE_BASE_BIN`.
4. `test/macroreparsecheck.sh` and `test/extentcheck.sh` pass with and without `RIPWIRE_BASE_BIN`,
   plain and ASan. The mutations in `macroreparsecheck`'s header ("never adopt", "adopt regardless")
   still turn it red.
5. Cold CPU on the measured corpus: 5 alternating runs of base and change, as #135 measured it.
6. `python3 test/pargates.py . ./build/ripwire -j 6` green; two cold runs byte-identical; `xmllint
   --noout` clean; `LSAN_OPTIONS=suppressions=lsan_suppressions.txt ./asan/ripwire <corpus> >/dev/null`
   clean; `./build/ripwire . --quality-delta --legend=compact` clean.

---

## TRAPS

**ripwire indexes itself.** Fixtures under `test/` are part of ripwire's own map. #135 noted the new
legend lines appear on this repo's map for that reason. Admitting namespace-scope runs would also
re-parse this repo's own `src/infra/dynamic_map.hpp`. Check ripwire's own map before and after.

**A widening can delete the evidence it was measured against.** `test/extentfix` is the detector's live
producer. If your scanner repairs it, `extentcheck` goes red for a good reason, not a bad one; move the
producer instead of weakening the arm.

**Per-worker scratch is a memo.** A scope stack or span list that is not cleared per file makes a file's
parse depend on crawl order and worker assignment. The output stays deterministic on one machine and
changes on another. Test with a corpus whose file order you permute.

**Version bumps collide.** Other open lanes bump `kParserVer` too. Two bumps can merge without a textual
conflict. Take the next free value when you land and re-pin on the merged tree.

**Licensed corpora.** memgraph is BSL: publish counts from it, never its code. Fixtures are written
fresh.

**A sanitizer report after a branch switch** whose buffer size divides evenly by an old `sizeof(Symbol)`
comes from a mixed-object build. Rebuild with `--clean-first` before debugging.

---

## What the PR description should contain

- The STEP 0 table: corpus, flagged files, the derailing construct for each class, and which classes you
  widened for.
- The verb-routing design: the helper, the offset contract, and how macro-targeting queries behave.
- Each widening: its exact bound, the unit and fixture arms, llvm/lib numbers before and after, the
  byte-identity result on clean-first-parse files, and the hand-checked sample.
- `err=` / `err_ratio` semantics after STEP 3, with a legend excerpt.
- Cold CPU, the full suite, ASan/LSan and determinism results; the version bumps and RE-PIN LOG entry.
- What stays open, and the measurement that says so.

---

**Write the plan — the STEP 0 corpus and classification method, the verb-routing helper, the widenings
you expect STEP 0 to justify, the red-first arms, the version bumps — then STOP for my go-ahead.**

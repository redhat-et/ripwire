# Nesting refusals, visible: a file ripwire refused to parse is never invisible

ripwire refuses pathologically nested JSON, YAML and Markdown files **before** it parses them. For YAML
and Markdown that refusal is memory safety: the vendored grammars' external scanners write past a
1024-byte buffer at around 250 levels of nesting. The refusal is right.

What is wrong is where the refusal goes:

- one line on stderr, on a **cold** run only;
- no row in `--skipped`, the verb that exists to answer "why is this file not in the index?";
- nothing at all on a **warm** run, which is the default after the first one;
- and the structural-query path parses the refused file anyway, in the same run that refused it.

You are making every refusal an itemized, legend-defined, cache-proof row, and applying one refusal
predicate at every place ripwire parses a file.

Work in a git worktree, not the main checkout, and run gates in the foreground.

---

## Why this matters

**Honesty is the product.** CLAUDE.md's non-negotiable #3 says every truncation is disclosed and a zero
means *none found*. An agent that runs `ripwire .` in a repository holding one generated 300-level YAML
file sees a map without that file. It asks `--skipped` why, and gets no answer:

- The file is not rowed.
- The only trace is `unmeasured="1"` in the header. That count also includes doc-pass files, binary
  sniffs and read failures, so it does not name the file.
- On the second run the stderr note is gone too.

The file was skipped on purpose, and the tool hides that it did.

This was measured on `main` at `766913d0`, for all three prescans (JSON, YAML, Markdown):

- **Cold run:** one stderr note, e.g. `[ripwire] ./deep.yml: yaml nesting > 64 levels — treated as data,
  not config (skipped)`.
- **Warm run** (the same command again): zero lines on stderr, and a byte-identical map.
- **`--skipped`, cold or warm:** no `<f>` row for the refused file; `unmeasured="1"` in both.
- **`--match`**, e.g. `--match='(block_mapping_pair)'`: exit 0, with hits **inside** `deep.yml`
  (255 total; the page shows 100, and all of them are in `deep.yml`). The same run's stderr carries
  ingest's refusal of that file. `--match='(block_quote)'` on the Markdown twin returns 254 hits inside
  `deepquote.md`.

**The safety design silently loses a layer.** The YAML and Markdown refusals are the first of two
independent protections. The second is the vendored scanner patch (`third_party/patches/yaml/`,
`third_party/patches/markdown/`). On the structural-query path the first layer never runs, so the patch is
the only thing between a hostile file and an out-of-bounds write.

**The maintainers have already named this gap in writing.** PR #126 (Kotlin, open) adds its own Kotlin
string-nesting guard, and its refusal legend ends with: "The json, yaml and markdown nesting guards refuse
the same way but are counted in unmeasured= only, without a row." That PR's review also found the warm-run
vanish, first for Kotlin: its own warm-cache arm was red on its first build.

Who benefits: anyone whose tree holds generated data, fuzz corpora, parser-torture fixtures or vendored
test suites. That is most large repositories. It also serves every agent that trusts `--skipped` to be
complete.

---

## Background: read these before you plan

### The three prescans and why they exist

- **Ceilings, with the defect arithmetic in their comments** (`src/ingest.h`):
  - `kMaxJsonNestDepth = 512`: a performance guard. tree-sitter-json's error recovery is superlinear, and
    100 KB of unclosed `[` measured 43 s.
  - `kMaxYamlNestDepth = 64`: memory safety. The yaml scanner's `serialize()` writes 4 bytes per block
    indent level behind a guard that only proves 1 byte fits. Measured: 253 levels exit 0, and 254 exit
    with SIGABRT; under `NDEBUG` the write corrupts memory silently.
  - `kMaxMdBlockDepth = 200`: memory safety. The markdown scanner's `serialize()` copies its open-blocks
    stack with no bounds check, and 300 nested `>` abort with rc=134.
- **The prescans** (`src/ingest_crawl.h`): `jsonNestsTooDeep`, `yamlNestsTooDeep` and `mdNestsTooDeep`.
  Each is one deterministic O(n) byte scan that over-approximates in the safe direction.
- **The second layer:** `third_party/patches/yaml/001-serialize-bounds.patch` and
  `third_party/patches/markdown/001-serialize-bounds.patch`, drift-gated by `test/vendorpatchcheck.sh`
  arm H.

### Where the refusal happens, and why a warm run never sees it

- **`src/ingest_parsepool.h`, `runParseWorker`.**
  - The worker checks the parse cache first: `if( hit != nullptr ) { … appendCacheHitFacts …; continue; }`.
  - Only a cache miss reaches the three guards further down. Each guard prints its stderr note and
    `continue`s.
- **`src/ingest_cache.h`, `saveCache`.** It writes a record for every crawled file, the refused one
  included. The next run stat-hits that record as "parsed, nothing there" and never reaches the guard.
  PR #126's commit `4802680e` diagnosed exactly this for its Kotlin guard.

### What `--skipped` can say today

- **`src/verbs_report.h`**: `runSkipped`, the legend `kSkippedLegend`, `writeDropRows`,
  `writeHealthRows` and `classifySkipHealth`.
  - Row kinds today are `oversize`, `excluded`, `unsupported-ext`, `ignored` and `ignored-dir`, plus the
    `<h>` health rows.
  - The legend already admits the class: `unmeasured=` counts indexed files never parsed, "a binary sniff
    or nesting guard refusal" among them.
- **`src/model.h`**: `struct CrawlSkips` (row vectors plus EXACT counts) and `SkippedFile`.
  `kMaxSkipRowsPerClass` (500, in `src/ingest.h`) caps rows, never counts, and a capped list carries
  `rows_capped="1"`.
- **`src/workspace.h`**: `mergeCrawlDisclosures` relabels and sums the skip classes for a multi-root run.
- **The accounting invariant** the legend states is `indexed= + oversize= + excluded= + ignored=` = the
  candidate population. A refused file is inside `indexed=`.

### Every other parse site, none of which checks nesting

`grep -rn 'NestsTooDeep' src/` finds call sites only in `src/ingest_parsepool.h`. The other places that
call `ts_parser_parse_string`:

- **`src/ingest_astquery.h`, `astQueryGrouped`**: the structural-query walk behind `--match`, `--pattern`
  and `--lint`'s built-in AST checks. It parses at the scope profiled `"astQuery/worker: tree-sitter
  parse"`. Callers are in `src/verbs_lint.h`: `runMatchQuery` and `runPatternSearch`.
- **`src/ingest_astquery.h`, `spanTiersOfFiles`**: `--grep`'s comment/string classification of hit
  files, profiled `"spanTiers/worker: tree-sitter parse"`.
- **The rest:** `src/ingest_astquery.h` `collectGatedLocalNames` (C/C++ definition bytes only),
  `src/slice.h` (one definition's source), `src/pattern.h` (parses the PATTERN text, not a corpus file),
  and `src/verbs_doctor.h` (a constant probe document).

Classify every one of them in your plan.

`--pattern` does not serve JSON, YAML or Markdown today (`src/pattern.h`: `kUnsupportedGrammars =
"ruby,bash,json,toml,yaml,markdown"`). It shares `astQueryGrouped`'s walk (`AstWalk::Pattern`), though, so a
refusal placed in that walk covers `--pattern` the day a guarded language is also a served one. PR #126's
Kotlin guard is exactly that case.

### The pattern to borrow (not to depend on): PR #126, commit `4802680e`

PR #126 is open. Its Kotlin guard does, for one language, most of what this prompt asks for all of them:

- `kotlinStringsNestTooDeep` refuses the file.
- `scan.nestRefusedBytes[ fileId ]` records the size, and `collectNestRefusals` turns the records into
  `CrawlSkips::nestRefused` rows plus an exact `nestRefusedFiles` count.
- `--skipped` rows each file as `<f p= why="nest-refused" bytes= ext=/>`.
- `nest_refused=` sits on the header, absent at zero.
- `writeNestRefusedLegend` writes its clause only into a document that carries such rows, so every other
  `--skipped` document stays byte-identical.
- The multi-root merge relabels and sums the rows.
- The warm-run fix is `forgetNestRefusalsForCache`: the refused file's record is written UNKNOWN (hash 0,
  and the stat gate's `-1` triple), so the next warm run re-reads it, re-refuses it and re-rows it.
- Its gate, `test/kotlincheck.sh` section 11, has a warm arm.

If #126 lands before you do, generalize its class; do not build a second one beside it. If you land first,
say so on #126 so its rebase is a merge of one mechanism, not two.

### Gates you will read or extend

- The guards: `test/yamllangcheck.sh` (the deep-indent arm, and the KNOWN GAP block after it),
  `test/mdsectioncheck.sh` (the deep-quote arm, and the KNOWN GAP block after it), `test/jsonlangcheck.sh`
  (the hostile-nesting arm), `test/vendorpatchcheck.sh`.
- `--skipped`: `test/skippedcheck.sh`, `test/skipreasoncheck.sh`, `test/parsehealthcheck.sh`.
- The cache: `test/statgatecheck.sh`, `test/cacheidentitycheck.sh`, `test/cachefuzzcheck.sh`.
- Output hygiene: `test/legendcoveragecheck.sh`, `test/printffmtparitycheck.sh`, `test/fixedbufsweep.sh`,
  `test/degradedhintcheck.sh`, `test/xmlwellformed.sh`, `test/multirootcheck.sh`.
- Versions: `test/qextractionkeycheck.sh`, `test/qschemetripcheck.sh`.

---

## Reproduce

The KNOWN GAP blocks already pin all of this, and they pass today:

```bash
cmake -S . -B build && cmake --build build -j
bash test/yamllangcheck.sh        # "KNOWN GAP (help wanted: prompts/help-wanted/nesting-refusals-visible.md)" lines PASS
bash test/mdsectioncheck.sh       # the markdown twin
```

By hand, in a scratch directory:

```bash
python3 -c "open('deep.yml','w').write(''.join(' '*i + 'deepnest%d:\n' % i for i in range(300)) + ' '*300 + 'leafdeep: 1\n')"
printf 'siblingkey: 1\n' > sibling.yml
../path/to/build/ripwire . --cache=nest.cache >/dev/null      # stderr: the yaml nesting note
../path/to/build/ripwire . --cache=nest.cache >/dev/null      # stderr: nothing
../path/to/build/ripwire . --cache=nest.cache --skipped       # no <f> row for deep.yml; unmeasured="1"
../path/to/build/ripwire . --no-cache --match='(block_mapping_pair)'   # hits inside deep.yml
```

The Markdown twin is `'>'*300 + ' text\n'` in a `.md` file with `--match='(block_quote)'`. The JSON twin is
`'['*600 + ']'*600` with `--match='(array)'`. Without `--cache=`, the second run is still warm: the cache is
on by default, per root, under the temp dir.

One more thing to see for yourself. `--match='(block_quote)'` over a Markdown-only tree prints hits beside
`grammars="" eligible_files="0"`. The eligibility disclosure does not name the grammar it scanned. And
`src/ingest_astquery.h` carries comments saying Markdown has "no grammar", although `src/ingest_crawl.h`'s
table gives `.md` the `tree_sitter_markdown` grammar.

---

## Design space and constraints

### One predicate, every site

Write the refusal ONCE: a declarative table of language, prescan, ceiling, stderr wording and reason
token, behind one function that answers "does this file's content refuse to parse, and why?". Call it:

- from `runParseWorker`;
- from `astQueryGrouped`'s worker;
- from `spanTiersOfFiles`;
- and from any other site your classification says reads corpus files.

Three hand-copied `if` blocks are how the other two sites were forgotten in the first place.

### Recording and disclosure

- **A per-file refusal slot, filled by the worker that owns the file** (one writer per slot), collected
  serially after the pool into `CrawlSkips` rows plus an exact count. Rows are path-sorted, capped by
  `kMaxSkipRowsPerClass`.
- **`--skipped`:** one `<f>` row per refused file.
  - Decide the `why=` token. Reusing #126's `nest-refused` is the obvious choice. Decide too whether the
    row names which guard (json/yaml/markdown) and the ceiling.
  - Add a header count, absent at zero.
  - Write a legend clause only in a document that carries such rows.
- **`unmeasured=`:** the refused file is still unmeasured. Keep the count honest and keep the accounting
  invariant true, and if you change what either means, restate it in the legend and in every gate that
  checks it.
- **`--match` and `--pattern`:**
  - A refused file is not scanned, so it must not count in `eligible_files=` as scanned.
  - Name the refusal in an attribute, absent at zero and legend-defined.
  - A zero-hit answer over a refused file must not read as "the pattern does not occur".
- **`--grep`'s span tiers:** a refused file is unclassifiable. `isParsed = false` already reads every
  offset as code, which is the honest default. Decide whether the answer should say which files were
  unclassified.

### The warm path (choose, measure, and write down the cost)

- **(A) Forget the record** (#126's choice). Write the refused file's cache record as UNKNOWN, so every warm
  run re-reads and re-refuses it. It is simple and obviously correct. The cost: one read plus one prescan of
  the refused file, and a cache rewrite, on every warm run of a tree that holds one.
- **(B) Remember the refusal.** Persist a refusal marker in the record, so a warm run rows the file without
  reading it. Invalidation must still follow the stat gate when the file changes. This is a cache format
  change.
- **(C) Prescan on the cache-hit path.** Rejected in advance: it reads every cached file on every warm run,
  which is the cost the warm path exists to avoid.

### Old caches

Whatever you choose, a cache written by today's binary already holds "parsed, nothing there" records for
refused files. Without a version bump, an upgraded binary reading an old cache keeps hiding them until the
file changes.

- Bump `kCacheVersion` (format) or `kParserVer` (extraction identity) in `src/ingest_cache.h`.
- Mirror the matching `kIngest*Mirror` in `src/quality.h` in the same commit.
- Re-pin `test/qschemetrip.hash` with `UPDATE_GOLDEN=1 test/qschemetripcheck.sh`.
- Prove it with an upgrade arm.

### Constraints (CLAUDE.md and CONTRIBUTING.md; none of these is optional)

- **Gate before code.** Flip the KNOWN GAP arms into assertions of the fixed behaviour and show them RED on
  the pre-change binary before writing the fix.
- **Determinism.** Rows are sorted and counts exact, independent of worker arrival order. Check with
  `./build/ripwire <dir> >a; ./build/ripwire <dir> >b; diff -q a b`.
- **Honesty in output.**
  - Absent-at-zero attributes.
  - Legend clauses only where their attribute is present (`test/legendcoveragecheck.sh`).
  - Caps disclosed.
  - `--json` twins for every new count.
- **`DEGRADED_PATH_ALERT`, never `VERIFY( false )`.**
  - A refusal is a recoverable degrade by CONTRIBUTING.md's definition; #126 raises one per refused file.
  - If you raise it, remember the alert prints on plain builds only, and several gates assert a clean
    stderr on their committed fixtures.
- **No `std::map` or `std::unordered_map`**; see "Containers" in CONTRIBUTING.md.
- **Style** (CONTRIBUTING.md §3):
  - Allman braces on every control body, and spaces inside parens.
  - Output goes through `rw::emitTo`.
  - A declarative guard table.
  - Any new fixed `char` buffer is a row in `test/fixedbufsweep.sh`.
- **Build discipline.**
  - Use the plain dev build: `NDEBUG` would hide the alert, and a Release binary performs the YAML scanner's
    corrupting write silently.
  - Never edit while a build runs.
  - After touching `src/model.h` or switching branches, run `cmake --build build --clean-first -j`.

---

## Acceptance criteria

1. **The KNOWN GAP blocks are flipped in place.** In `test/yamllangcheck.sh` and `test/mdsectioncheck.sh`:
   - cold `--skipped` and warm `--skipped` each carry exactly one row for the refused file, with `why=`
     and `bytes=`;
   - the header count is present and equal to the rows;
   - the legend clause is present;
   - the warm run's refusal is visible (the row at minimum; state your stderr decision);
   - `--match` exits 0 with **no** hits inside the refused file, names the refusal in its disclosure, and
     still scans the sibling.

   Each flipped arm is RED on the pre-change binary.
2. **The JSON twin.** The same four assertions exist in `test/jsonlangcheck.sh`, over a generated file.
3. **Upgrade.** A cache written by the pre-change binary, read by yours, rows the refused file.
4. **Multi-root.** `ripwire rootA rootB --skipped` relabels the rows per root and sums the count, both in
   XML and in `--json`.
5. **Nothing else moved.** On trees with no refused file, the `--skipped`, map and `--match` outputs are
   byte-identical to the pre-change binary.
6. **Every parse site classified.** Each site that reads corpus files applies the shared predicate, or the
   PR says why it cannot reach a guarded language.
7. **Safety evidence.** An ASan build (`cmake -S . -B asan -DRIPWIRE_ASAN=ON`) over the generated hostile
   files, for every verb you touched, prints zero sanitizer lines. `test/vendorpatchcheck.sh` still proves
   the patch layer on its own.
8. **Suite.**
   - `python3 test/pargates.py . ./build/ripwire -j 6` is green, run in the foreground.
   - `python3 docs/limits_build.py --check` is clean.
   - `./build/ripwire . --quality-delta --legend=compact` shows zero unacknowledged regressions.

---

## Known traps

**The warm path is where the refusal dies.** The guards run after the cache-hit `continue`. A fix tested
only with `--no-cache` passes blind, and #126's own warm arm was red on its first build. Every assertion
you write gets a warm twin.

**An old cache keeps hiding the file.** Fixing the write side does nothing for a record already on disk.
Bump the version, and write the upgrade arm with the pre-change binary actually writing the cache.

**Never commit a hostile fixture.** A committed 300-level file puts the guard's stderr note into every
repo-wide run of the tool on this repository. `test/xmlwellformed.sh`'s `--owners` arm merges stderr and
has caught exactly that; `test/mdsectioncheck.sh`'s comment records it. Generate hostile files under the
gate's temp dir, as the KNOWN GAP blocks do.

**A crashed run prints nothing.** "No hits inside deep.yml" is true of an empty document. Judge every
absence arm only after a clean exit, and FAIL on a non-zero one (the KNOWN GAP `--match` arms do).

**The alert is compiled out in Release.** A gate that asserts `DEGRADED_PATH_ALERT` must read the build
flavour from `--version`, or it is red on CI's Release leg; `test/estchargecheck.sh` shows how.

**Stale comments point the wrong way.** `src/ingest_astquery.h` says Markdown has "no grammar" at the
walk's skip. The extension table gives `.md` a grammar, and `--match` returns hits inside `.md` files. A
predicate placed on the strength of that comment would skip Markdown, the one format whose scanner has no
bounds check at all.

**`--pattern` over these three formats is vacuous.** They are unserved, so an arm there proves nothing.
Test the shared predicate in the walk, or with a served language once one is guarded.

**The rows cap is not the count.** Past 500 rows the list is a sample and `rows_capped="1"` says so; the
count stays exact. A gate that counts rows to check the header must stay under the cap.

**The accounting invariant is gated.** `test/skippedcheck.sh`, `test/skipreasoncheck.sh` and
`test/parsehealthcheck.sh` read `indexed=`, `unmeasured=` and the drop classes. Moving the refused file
between classes changes what they assert. Decide deliberately, then update the legend and the gates in the
same commit.

**#126 is in flight on the same functions.** `runParseWorker`, `runSkipped`, `CrawlSkips`,
`mergeCrawlDisclosures` and the save path. Rebase conflicts are certain; duplicate mechanisms are
avoidable. Read its diff first, and coordinate on the PR.

**Fixed buffers and LIMITS pins.** #126 added two fixed buffers and re-pinned `test/fixedbufsweep.sh`'s
enumeration, then regenerated `docs/LIMITS.md`. Expect to do the same.

**Python in a gate writes `__pycache__`.** Set `PYTHONDONTWRITEBYTECODE=1` in any gate that runs Python
inside the checkout, or the crawl counts move under the next gate.

---

## What the PR description should contain

- **The guard table:** language, ceiling, reason token, and every parse site before and after (a small
  table).
- **The warm-path choice, with its measured cost:** warm wall time and cache writes on a tree with and
  without a refused file.
- **Versions:** which constant moved and its mirror; the upgrade arm's red/green.
- **Red first:** each flipped arm's FAIL on the pre-change binary, for YAML, Markdown and JSON.
- **The new attributes and legend text**, verbatim, for `--skipped` and `--match` (and `--grep` if
  touched).
- **ASan evidence:** the verbs run over the hostile files, and zero sanitizer lines.
- **Coordination:** what you took from #126, and how the two land together.

---

**Write the plan: the guard table, the parse-site classification, the warm-path choice and its version
bump, the disclosure attributes, and the flipped arms. Then STOP for my go-ahead.**

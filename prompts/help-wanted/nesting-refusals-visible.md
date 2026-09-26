# Nesting refusals, visible: a file ripwire refused to parse is never invisible

ripwire refuses pathologically nested JSON, YAML, Markdown and Kotlin files **before** it parses them.
For YAML, Markdown and Kotlin that refusal is about survival: the vendored grammars' external scanners
write past a buffer (YAML, Markdown) or abort the whole process (Kotlin) at deep enough nesting. The
refusal is right.

What is wrong is where the refusal goes:

- **Kotlin** (added in #126) already does most of it: a `--skipped` row, a header count, and a refusal
  that survives warm runs.
- **JSON, YAML and Markdown** get one line on stderr, on a **cold** run only; no row in `--skipped`, the
  verb that exists to answer "why is this file not in the index?"; and nothing at all on a **warm** run,
  which is the default after the first one.
- **For all four**, the structural-query path parses the refused file anyway, in the same run that
  refused it, and the default map's header never mentions that a file was refused.

You are generalizing Kotlin's refusal into one class, making every refusal an itemized, legend-defined,
cache-proof row, and applying one refusal predicate at every place ripwire parses a file.

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

This was measured on `main` at `766913d0`, for the JSON, YAML and Markdown prescans:

- **Cold run:** one stderr note, e.g. `[ripwire] ./deep.yml: yaml nesting > 64 levels — treated as data,
  not config (skipped)`.
- **Warm run** (the same command again): zero lines on stderr, and a byte-identical map.
- **`--skipped`, cold or warm:** no `<f>` row for the refused file; `unmeasured="1"` in both.
- **`--match`**, e.g. `--match='(block_mapping_pair)'`: exit 0, with hits **inside** `deep.yml`
  (255 total; the page shows 100, and all of them are in `deep.yml`). The same run's stderr carries
  ingest's refusal of that file. `--match='(block_quote)'` on the Markdown twin returns 254 hits inside
  `deepquote.md`.

And for Kotlin, measured on `main` at `f8e6087c` over `test/kotlincheck.sh` §12's fixture (`Deep.kt` and
`OverCeiling.kt` refused, `AtCeiling.kt` and `Sibling.kt` indexed):

- **`--skipped`:** both refused files are rowed `why="nest-refused"`, cold and warm. This part works.
- **`--no-cache --match='(string_literal)'`:** exit 0 with `hits="860" eligible_files="4"`. Paging through
  the hits gives **600 inside `Deep.kt` and 129 inside `OverCeiling.kt`**, exactly their string counts.
  The same run's stderr carries ingest's refusal of both files.
- **The default map** over the same tree says `files=4 symbols=3` in its header comment and carries no
  refusal count. A reader of the map learns about the refusal only from stderr, or from `--skipped` if
  they think to ask.

**The safety design silently loses a layer.** The prescans are the first of two independent protections.
The second is the vendored scanner patch (`third_party/patches/yaml/`, `third_party/patches/markdown/`,
`third_party/patches/kotlin/`). On the structural-query path the first layer never runs, so the patch is
the only thing between a hostile file and an out-of-bounds write or an abort.

**The maintainers have already named this gap in writing.** The refusal legend on `main`, written when
#126 landed Kotlin's guard, ends with: "The json, yaml and markdown nesting guards refuse the same way but
are counted in unmeasured= only, without a row." That sentence is what this work retires. #126's review
also found the warm-run vanish, first for Kotlin: its own warm-cache arm was red on its first build.

Who benefits: anyone whose tree holds generated data, fuzz corpora, parser-torture fixtures or vendored
test suites. That is most large repositories. It also serves every agent that trusts `--skipped` to be
complete.

---

## Background: read these before you plan

### The four prescans and why they exist

- **Ceilings, with the defect arithmetic in their comments** (`src/ingest.h`):
  - `kMaxJsonNestDepth = 512`: a performance guard. tree-sitter-json's error recovery is superlinear, and
    100 KB of unclosed `[` measured 43 s.
  - `kMaxYamlNestDepth = 64`: memory safety. The yaml scanner's `serialize()` writes 4 bytes per block
    indent level behind a guard that only proves 1 byte fits. Measured: 253 levels exit 0, and 254 exit
    with SIGABRT; under `NDEBUG` the write corrupts memory silently.
  - `kMaxMdBlockDepth = 200`: memory safety. The markdown scanner's `serialize()` copies its open-blocks
    stack with no bounds check, and 300 nested `>` abort with rc=134.
  - `kMaxKotlinStringNestDepth = 128`: process survival. tree-sitter-kotlin's scanner bounded its string
    stack with `abort()`: 512 open strings parse, and 513 end the process.
- **The prescans** (`src/ingest_crawl.h`): `jsonNestsTooDeep`, `yamlNestsTooDeep`, `mdNestsTooDeep` and
  `kotlinStringsNestTooDeep`. Each is one deterministic O(n) byte scan that over-approximates in the safe
  direction.
- **The second layer:** `third_party/patches/yaml/001-serialize-bounds.patch`,
  `third_party/patches/markdown/001-serialize-bounds.patch` and
  `third_party/patches/kotlin/001-stack-push-no-abort.patch`, drift-gated by `test/vendorpatchcheck.sh`.

### Where the refusal happens, and why a warm run never sees it

- **`src/ingest_parsepool.h`, `runParseWorker`.**
  - The worker checks the parse cache first: `if( hit != nullptr ) { … appendCacheHitFacts …; continue; }`.
  - Only a cache miss reaches the guards further down. The JSON, YAML and Markdown guards sit inline:
    each prints its stderr note and `continue`s. Kotlin's is one named step, `refuseKotlinNesting`
    (`src/ingest_prewarm.h`).
- **`src/ingest_cache.h`, `saveCache`.** It writes a record for every crawled file, the refused one
  included. The next run stat-hits that record as "parsed, nothing there" and never reaches the guard.
  Kotlin's refusal survives because `forgetNestRefusalsForCache` rewrites a refused file's record as
  UNKNOWN before the save; the other three have no such step.

### What `--skipped` can say today

- **`src/verbs_report.h`**: `runSkipped`, the legend `kSkippedLegend`, `writeDropRows`,
  `writeHealthRows`, `classifySkipHealth` and `writeNestRefusedLegend`.
  - Row kinds today are `oversize`, `excluded`, `unsupported-ext`, `ignored`, `ignored-dir` and
    `nest-refused` (Kotlin only), plus the `<h>` health rows.
  - The legend already admits the class: `unmeasured=` counts indexed files never parsed, "a binary sniff
    or nesting guard refusal" among them.
- **`src/model.h`**: `struct CrawlSkips` (row vectors plus EXACT counts, including `nestRefused` and
  `nestRefusedFiles`) and `SkippedFile`. `kMaxSkipRowsPerClass` (500, in `src/ingest.h`) caps rows, never
  counts, and a capped list carries `rows_capped="1"`.
- **`src/workspace.h`**: `mergeCrawlDisclosures` relabels and sums the skip classes for a multi-root run.
- **The accounting invariant** the legend states is `indexed= + oversize= + excluded= + ignored=` = the
  candidate population. A refused file is inside `indexed=`.
- **The default map** carries no refusal count at all.

### Every other parse site, none of which checks nesting

`grep -rn 'NestsTooDeep\|refuseKotlinNesting' src/` finds refusal call sites only on the ingest path
(`src/ingest_parsepool.h`, `src/ingest_prewarm.h`). The other places that call `ts_parser_parse_string`:

- **`src/ingest_astquery.h`, `astQueryGrouped`**: the structural-query walk behind `--match`, `--pattern`
  and `--lint`'s built-in AST checks. It parses at the scope profiled `"astQuery/worker: tree-sitter
  parse"`. Callers are in `src/verbs_lint.h`: `runMatchQuery` and `runPatternSearch`.
- **`src/ingest_astquery.h`, `spanTiersOfFiles`**: `--grep`'s comment/string classification of hit
  files, profiled `"spanTiers/worker: tree-sitter parse"`.
- **The rest:** `src/ingest_astquery.h` `collectGatedLocalNames` (C/C++ definition bytes only),
  `src/slice.h` (one definition's source), `src/pattern.h` (parses the PATTERN text, not a corpus file),
  and `src/verbs_doctor.h` (a constant probe document).

Classify every one of them in your plan.

`--pattern` does not serve JSON, YAML or Markdown (`src/pattern.h`: `kUnsupportedGrammars =
"ruby,bash,json,toml,yaml,markdown"`). It shares `astQueryGrouped`'s walk (`AstWalk::Pattern`), though,
and **Kotlin is both guarded and served** by `--match` and `--pattern`. Kotlin is therefore the language
that tests the shared predicate in the walk for real.

### The class to generalize: Kotlin's refusal, on `main` since #126

Kotlin's guard already does, for one language, most of what this prompt asks for all of them:

- `refuseKotlinNesting` calls `kotlinStringsNestTooDeep` and refuses the file.
- `scan.nestRefusedBytes[ fileId ]` records the size (one writer per slot), and `collectNestRefusals`
  turns the records, serially and in fileId order, into `CrawlSkips::nestRefused` rows plus an exact
  `nestRefusedFiles` count.
- `--skipped` rows each file as `<f p= why="nest-refused" bytes= ext=/>`.
- `nest_refused=` sits on the `--skipped` header, absent at zero.
- `writeNestRefusedLegend` writes its clause only into a document that carries such rows, so every other
  `--skipped` document stays byte-identical. It hard-codes the Kotlin ceiling today.
- The multi-root merge relabels and sums the rows.
- The warm-run fix is `forgetNestRefusalsForCache`: the refused file's record is written UNKNOWN (hash 0,
  and the stat gate's `-1` triple), so the next warm run re-reads it, re-refuses it and re-rows it.
- Its gate, `test/kotlincheck.sh` section 12, has row, header, legend and warm arms.

**Generalize this class; do not build a second one beside it.**

### Gates you will read or extend

- The guards: `test/yamllangcheck.sh` (the deep-indent arm, and the KNOWN GAP block after it),
  `test/mdsectioncheck.sh` (the deep-quote arm, and the KNOWN GAP block after it), `test/jsonlangcheck.sh`
  (the hostile-nesting arm), `test/kotlincheck.sh` §12, `test/vendorpatchcheck.sh`.
- `--skipped`: `test/skippedcheck.sh`, `test/skipreasoncheck.sh`, `test/parsehealthcheck.sh`.
- The cache: `test/statgatecheck.sh`, `test/cacheidentitycheck.sh`, `test/cachefuzzcheck.sh`.
- Output hygiene: `test/legendcoveragecheck.sh`, `test/printffmtparitycheck.sh`, `test/fixedbufsweep.sh`,
  `test/degradedhintcheck.sh`, `test/xmlwellformed.sh`, `test/multirootcheck.sh`.
- Versions: `test/qextractionkeycheck.sh`, `test/qschemetripcheck.sh`.

---

## Reproduce

The KNOWN GAP blocks already pin the JSON/YAML/Markdown half, and they pass today:

```bash
cmake -S . -B build && cmake --build build -j
bash test/yamllangcheck.sh        # "KNOWN GAP (help wanted: prompts/help-wanted/nesting-refusals-visible.md)" lines PASS
bash test/mdsectioncheck.sh       # the markdown twin
bash test/kotlincheck.sh          # §12: Kotlin's rows, header, legend and warm arms PASS
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

For Kotlin, generate §12's tree (its Python generator is in the gate) and run
`--no-cache --match='(string_literal)'` over it. Page through the hits with `--limit`/`--offset` and count
the ones whose path is `Deep.kt` or `OverCeiling.kt`.

One more thing to see for yourself. `--match='(block_quote)'` over a Markdown-only tree prints hits beside
`grammars="" eligible_files="0"`. The eligibility disclosure does not name the grammar it scanned. And
`src/ingest_astquery.h` carries comments saying Markdown has "no grammar", although `src/ingest_crawl.h`'s
table gives `.md` the `tree_sitter_markdown` grammar.

---

## Design space and constraints

### One predicate, every site

Write the refusal ONCE: a declarative table of language, prescan, ceiling, stderr wording and reason
token, behind one function that answers "does this file's content refuse to parse, and why?". Kotlin's
`refuseKotlinNesting` becomes one row of that table. Call it:

- from `runParseWorker`;
- from `astQueryGrouped`'s worker;
- from `spanTiersOfFiles`;
- and from any other site your classification says reads corpus files.

Hand-copied `if` blocks are how the other sites were forgotten in the first place.

**Mind the alert when you merge the sites.** `DISCLOSE` holds a static latch per **call site**,
so it prints at most once per site per process. Today that is one alert for Kotlin's site, however many
files it refuses. Move it into one shared predicate and a process prints ONE alert across every language
and every parse site, whose text cannot name a language. That is fine for a debug trace, and it is exactly
why no gate may assert the alert (see Constraints).

### Recording and disclosure

- **A per-file refusal slot, filled by the worker that owns the file** (one writer per slot), collected
  serially after the pool into `CrawlSkips` rows plus an exact count. Rows are path-sorted, capped by
  `kMaxSkipRowsPerClass`. `collectNestRefusals` already does this for Kotlin.
- **`--skipped`:** one `<f>` row per refused file.
  - Reuse `why="nest-refused"`. Decide whether the row names which guard (json/yaml/markdown/kotlin) and
    the ceiling.
  - The header count stays exact and absent at zero.
  - The legend clause is written only in a document that carries such rows, with a clause per language
    (today's clause names only Kotlin's ceiling).
- **The default map:** today its header does not mention refused files. Decide whether it gains a
  refusal count, absent at zero, so a reader of the map is pointed at `--skipped`. If it does, it needs a
  legend clause and a `--json` twin, and every tree without a refused file stays byte-identical.
- **`unmeasured=`:** the refused file is still unmeasured. Keep the count honest and keep the accounting
  invariant true, and if you change what either means, restate it in the legend and in every gate that
  checks it.
- **`--match` and `--pattern`:**
  - A refused file is not scanned, so it must not count in `eligible_files=` as scanned.
  - Name the refusal in an attribute, absent at zero and legend-defined.
  - A zero-hit answer over a refused file must not read as "the pattern does not occur".
  - The refusal slot for the walk is filled by that walk's own workers and collected serially, the same
    one-writer rule as ingest.
- **`--grep`'s span tiers:** a refused file is unclassifiable. `isParsed = false` already reads every
  offset as code, which is the honest default. Decide whether the answer should say which files were
  unclassified.

### The warm path (choose, measure, and write down the cost)

- **(A) Forget the record** (Kotlin's choice, `forgetNestRefusalsForCache`). Write the refused file's
  cache record as UNKNOWN, so every warm run re-reads and re-refuses it. It is simple and obviously
  correct. The cost: one read plus one prescan of the refused file, and a cache rewrite, on every warm run
  of a tree that holds one.
- **(B) Remember the refusal.** Persist a refusal marker in the record, so a warm run rows the file without
  reading it. Invalidation must still follow the stat gate when the file changes. This is a cache format
  change.
- **(C) Prescan on the cache-hit path.** Rejected in advance: it reads every cached file on every warm run,
  which is the cost the warm path exists to avoid.

### Old caches

Whatever you choose, a cache written by today's binary already holds "parsed, nothing there" records for
refused JSON, YAML and Markdown files. Without a version bump, an upgraded binary reading an old cache
keeps hiding them until the file changes.

- Bump `kCacheVersion` (format) or `kParserVer` (extraction identity) in `src/ingest_cache.h`.
- Mirror the matching `kIngest*Mirror` in `src/quality.h` in the same commit.
- Re-pin `test/qschemetrip.hash` with `UPDATE_GOLDEN=1 test/qschemetripcheck.sh`.
- Prove it with an upgrade arm.

### Constraints (CLAUDE.md and CONTRIBUTING.md; none of these is optional)

- **Gate before code.** Flip the KNOWN GAP arms into assertions of the fixed behaviour, add the Kotlin
  `--match` arms, and show them RED on the pre-change binary before writing the fix.
- **Gates assert output rows, never the stderr alert.** The disclosure a gate reads is the document:
  `--skipped`'s `why="nest-refused"` rows, the header count, the legend clause, and the `--match`
  refusal attribute. Never assert `DISCLOSE`'s text:
  - it fires once per call site per process, not once per refused file, so a second refusal raises
    nothing;
  - it is compiled out in Release, so an arm that reads it must branch on the build flavour and asserts
    nothing on CI's Release leg;
  - its notice is written in several pieces, so a concurrent stderr line can split it. That is the root
    cause of the flaky alert arm in `test/kotlincheck.sh` §12, where two files are refused by two workers
    at once.

  Do not copy §12's flavour-dependent alert arm into `test/yamllangcheck.sh`, `test/mdsectioncheck.sh` or
  `test/jsonlangcheck.sh`.
- **Determinism.** Rows are sorted and counts exact, independent of worker arrival order. Check with
  `t=$(mktemp -d); ./build/ripwire <dir> >"$t/a"; ./build/ripwire <dir> >"$t/b"; diff -q "$t/a" "$t/b"`
  (outputs outside `<dir>`, or the second run crawls the first one's output).
- **Honesty in output.**
  - Absent-at-zero attributes.
  - Legend clauses only where their attribute is present (`test/legendcoveragecheck.sh`).
  - Caps disclosed.
  - `--json` twins for every new count.
- **`DISCLOSE`, never `ASSUME( false )`.** A refusal is a recoverable degrade by CONTRIBUTING.md's
  definition. If you keep an alert, remember it prints on plain builds only, and several gates assert a
  clean stderr on their committed fixtures.
- **No `std::map` or `std::unordered_map`**; see "Containers" in CONTRIBUTING.md.
- **Style** (CONTRIBUTING.md §3):
  - Allman braces on every control body, and spaces inside parens.
  - Output goes through `rw::emitTo`.
  - A declarative guard table.
  - Any new fixed `char` buffer is a row in `test/fixedbufsweep.sh`.
- **Build discipline.**
  - Use the plain dev build: `NDEBUG` hides the alert, and a Release binary performs the YAML scanner's
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
   - the warm run's refusal is visible in the row;
   - `--match` exits 0 with **no** hits inside the refused file, names the refusal in its disclosure, and
     still scans the sibling.

   Each flipped arm is RED on the pre-change binary.
2. **The JSON twin.** The same assertions exist in `test/jsonlangcheck.sh`, over a generated file.
3. **The Kotlin `--match` arms**, added to `test/kotlincheck.sh` over §12's fixture. They are RED today, not
   vacuous, because Kotlin is a served grammar:
   - `--no-cache --match='(string_literal)'` exits 0 with zero hits inside `Deep.kt` and `OverCeiling.kt`;
   - the answer discloses the two refusals;
   - `AtCeiling.kt` and `Sibling.kt` are still scanned (131 hits on the recorded fixture);
   - a `--pattern` arm over a Kotlin construct shows the same refusal in the shared walk.
   §12's existing row, header, legend and warm arms stay green.
4. **Every fixture refuses two files.** Refusing two files in one run is what exposes a concurrency defect in
   a disclosure, so keep the pair, with a sibling that stays indexed.
5. **Upgrade.** A cache written by the pre-change binary, read by yours, rows the refused file.
6. **Multi-root.** `ripwire rootA rootB --skipped` relabels the rows per root and sums the count, both in
   XML and in `--json`.
7. **Nothing else moved.** On trees with no refused file, the `--skipped`, map and `--match` outputs are
   byte-identical to the pre-change binary.
8. **Every parse site classified.** Each site that reads corpus files applies the shared predicate, or the
   PR says why it cannot reach a guarded language.
9. **Safety evidence.** An ASan build (`cmake -S . -B asan -DRIPWIRE_ASAN=ON`) over the generated hostile
   files, for every verb you touched, prints zero sanitizer lines. `test/vendorpatchcheck.sh` still proves
   the patch layer on its own.
10. **Suite.**
    - `python3 test/pargates.py . ./build/ripwire -j 6` is green, run in the foreground.
    - `python3 docs/limits_build.py --check` is clean.
    - `./build/ripwire . --quality-delta --legend=compact` shows zero unacknowledged regressions.

---

## Known traps

**The warm path is where the refusal dies.** The guards run after the cache-hit `continue`. A fix tested
only with `--no-cache` passes blind, and Kotlin's own warm arm was red on its first build. Every assertion
you write gets a warm twin.

**An old cache keeps hiding the file.** Fixing the write side does nothing for a record already on disk.
Bump the version, and write the upgrade arm with the pre-change binary actually writing the cache.

**Never commit a hostile fixture.** A committed 300-level file puts the guard's stderr note into every
repo-wide run of the tool on this repository. `test/xmlwellformed.sh`'s `--owners` arm merges stderr and
has caught exactly that; `test/mdsectioncheck.sh`'s comment records it. Generate hostile files under the
gate's temp dir, as the KNOWN GAP blocks and §12 do.

**A crashed run prints nothing.** "No hits inside deep.yml" is true of an empty document. Judge every
absence arm only after a clean exit, and FAIL on a non-zero one (the KNOWN GAP `--match` arms do).

**The stderr alert is not a disclosure.** It is latched per call site, compiled out in Release, and can be
split by a concurrent write. A gate that greps it on one line flakes under load, and a gate that reads the
build flavour to skip it asserts nothing in Release. Assert the rows.

**Stale comments point the wrong way.** `src/ingest_astquery.h` says Markdown has "no grammar" at the
walk's skip. The extension table gives `.md` a grammar, and `--match` returns hits inside `.md` files. A
predicate placed on the strength of that comment would skip Markdown, the one format whose scanner has no
bounds check at all. The collector's comment above `collectNestRefusals` says a refused file "never reaches
the cache"; `forgetNestRefusalsForCache` is what actually keeps it out of a warm hit.

**`--pattern` over JSON, YAML and Markdown is vacuous.** They are unserved, so an arm there proves nothing.
Kotlin is served and guarded: test the shared predicate in the walk with Kotlin.

**The rows cap is not the count.** Past 500 rows the list is a sample and `rows_capped="1"` says so; the
count stays exact. A gate that counts rows to check the header must stay under the cap.

**The accounting invariant is gated.** `test/skippedcheck.sh`, `test/skipreasoncheck.sh` and
`test/parsehealthcheck.sh` read `indexed=`, `unmeasured=` and the drop classes. Moving the refused file
between classes changes what they assert. Decide deliberately, then update the legend and the gates in the
same commit.

**Other work lands on the same code first.**
- PR #245 makes the alert's notice a single write. It lands before this work; rebase onto it, and do
  not fix the reporter here.
- The self-check macros are being renamed (`DISCLOSE` → `DISCLOSE`, `ASSUME` → `ASSUME`). A
  rename script covers open branches, so do not hand-edit around it.

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
- **Red first:** each flipped arm's FAIL on the pre-change binary, for YAML, Markdown, JSON and the Kotlin
  `--match` arms.
- **The new attributes and legend text**, verbatim, for `--skipped`, `--match` and the default map (and
  `--grep` if touched).
- **ASan evidence:** the verbs run over the hostile files, and zero sanitizer lines.
- **Coordination:** how Kotlin's class was generalized, and what the single-write reporter and the macro
  rename changed under you.

---

**Write the plan: the guard table, the parse-site classification, the warm-path choice and its version
bump, the disclosure attributes (including the default map decision), and the flipped and new arms. Then
STOP for my go-ahead.**

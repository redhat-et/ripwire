# Changelog

All notable changes to ripwire are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Everything here is pre-1.0: the flag surface may still change. When a flag is superseded it is
deprecated with a stderr pointer at its replacement and kept working; removals wait for a major
version. A `v0.1.0` tag exists (2026-08-02) but its GitHub Release carries no binaries; **v0.2.0 is
the first release with published, SHA-256-checked archives**, and it contains everything below.

Every measured number in this file names its corpus and method. Numbers without a stated method are
not published here — see `docs/EVALS.md` for the instruments behind the headline figures.

---

## [0.6.4] — 2026-09-25

### Added — Astro (`.astro`) frontmatter is indexed on the TypeScript grammar (#320, #67)

An `.astro` file's `---` frontmatter is now parsed with the vendored TypeScript grammar, restricted to that
block by one included range, so a frontmatter call resolves into the `.ts` service it imports. The template
half is not read at all, and an `.astro` file reports `lang="ts"`; both are disclosed blind spots in
`docs/ARCHITECTURE.md#astro-extraction`. `kParserVer` 121 → 122; `kCacheVersion` is unchanged.

### Documented — README: release notes moved to a section near the end

The four release blurbs (0.6.3, 0.6.2, 0.6.1, 0.6.0, with their "Thanks to" lines) sat near the top of
README.md, right after the Languages line — a lot for a first-time reader to get through before
Quickstart. They now live in a new `## Release notes` section near the end, just before
`## Documentation`, text and thanks lines unchanged. The top of the README keeps one short line
naming the current version and pointing at that section and at CHANGELOG.md. The old `## What's new`
section (a stale, differently-worded duplicate of the 0.6.0 blurb) is removed.

### Fixed — `next=` is never dropped silently, and the nudge hook reads rev-parse's answer
- `next=` is no longer silently dropped past its old 120-byte ceiling. `--for`'s page/widen
  follow-up (`forPageInvocation`/`forWidenNext`), `--flip`'s cut-listing follow-up, and the
  churn-decay map's `--in=DIR` scoped/stub follow-ups (including the task-router's `--for`-shaped
  `<choice>` widening hint) used to build the full invocation and then throw it away when it
  exceeded `kNextAttrMaxBytes`, leaving `next=` absent — indistinguishable from a root with nothing
  to suggest, so a cut answer with a long follow-up (a deep path, a long symbol name) silently lost
  its only route to the rest. `nextAttrXml` (the one place every next= producer funnels through)
  now carries no length ceiling at all and always emits the full, runnable invocation; an answer
  whose next= was already ≤120 B is unchanged.
- `hooks/ripwire-nudge.sh`'s SessionStart primer read `git rev-parse --is-inside-work-tree` by exit
  status only. A bare repository, or a cwd inside a work tree's own `.git` directory, prints `false`
  with status 0 there, so the primer could still run in a population it was never meant to reach (the
  same shape CodeRabbit flagged and 1cd00d4d fixed in the two route hooks). It now reads the answer.
- CONTRIBUTING.md's Windows-matrix note named a stale gate count (647); the live count is 649.

### Fixed — `--test-gate` derives `node --test` from a bare `node:test` import, with no `package.json` at all

#60's core defect (a TS/JS test file's call-graph reach and `--affected`/`--test-gate` listing) was fixed
in 0.6.2. What was left: the reporter's own repro (`src/bounded.ts` + `test/behavior.test.ts`, `import test
from "node:test"`, **no `package.json` anywhere in the repo**) still read `run_unknown="1"`, because
`jsrunner.h`'s runner derivation (#323) reads only the nearest `package.json`'s own evidence, and a repo
with none has no evidence for that walk to find. Thanks to @YogevKr for the report and the clean two-arm
repro, and to @alex-michaud for the non-test `--callers` arm that helped confirm the core fix.

- **New evidence source: the test file's own import/require.** When `package.json` evidence decides
  nothing for a TS/JS test file — no manifest anywhere in the crawl boundary, or the nearest one is a true
  marker (no `scripts.test`, no `vitest`/`jest` dependency) — the file's own bytes are read for a `node:test`
  import: `import test from "node:test"`, `import { test, describe } from "node:test"`, or
  `require("node:test")`, single or double quoted. This is a real parse (the same grammar the file's own
  extension selects), not a substring scan: a `"node:test"` mention inside a comment or an unrelated string
  literal is not evidence and does not derive a runner.
- **Precedence is unchanged.** An explicit `package.json` `scripts.test` (or a `vitest`/`jest` dependency)
  still wins exactly as #323/#331 already decided — including an authoritative-but-unrecognized script
  (mocha, say), which is a decided "no" and is never overridden by the weaker, file-local import evidence.
  The import fallback applies ONLY to today's `run_unknown="1"` case.
- **`.ts`/`.mts`/`.cts` get a Node-version-aware command, never a command proven to fail.** Node's own
  `--test` runner needs `--experimental-strip-types` to strip TypeScript types at all from Node 22.6
  onward; below that the flag itself is a fatal "bad option" and there is no way to run a `.ts` file with
  plain `node`. Stripping is ON BY DEFAULT (the flag becomes a harmless no-op) from two separate floors —
  Node 22.18 and Node 23.6 — because 23.6 turned it on first and the 22.x line got it later, by backport, so
  a bare 23.0–23.5 does not have it. This tool cannot see which
  Node will run the emitted command, so it reads `engines.node` from the nearest manifest
  (if any): the bare form when that range proves every satisfying Node has stripping on by default; the
  flagged form when it proves >= 22.6 but not provably default-on, or when there is no manifest at all (an
  honest, stated assumption of Node >= 22.6, never a guess at an unseen runtime); and `run_unknown="1"`
  when the range admits ANY Node below 22.6 — a plain `>=18`/`^20`, or a compound range such as
  `>=24 || ^20` (the LOWEST admitted alternative decides it, not the highest) — or cannot be read with
  confidence at all. This applies to BOTH the new import-evidence path and the existing
  `scripts.test: "node --test"` path (previously spelled `node --test <file>` unconditionally for a `.ts`
  file, with no version awareness at all). `.js`/`.mjs`/`.cjs` never need the flag and always get the bare
  form, unless `engines.node` admits a Node below 18 (`node:test` itself does not exist there).
- **`.tsx` and `.jsx` are never derived, on purpose.** Node's type stripping does not cover `.tsx` at all
  (`ERR_UNKNOWN_FILE_EXTENSION`), and plain `node` cannot load a `.jsx` file either, on any Node version, with
  or without any flag — both stay `run_unknown="1"`, the same as before this evidence source existed.
- **A `.ts`/`.mts`/`.cts` command is derived only when the test file's own relative imports can actually
  load.** Node's module resolver, under type stripping, never probes an extension and never maps a `.js`
  specifier onto a `.ts` source — both are exactly how tsc-, tsx- and bundler-run TS code imports its own
  siblings. So the command is derived only when every relative (`./`/`../`) static `import`/`export … from`
  specifier or `require(...)` argument in the test file's own bytes names a file that exists on disk at
  EXACTLY that path; an extensionless specifier, or one whose exact spelling does not exist, stays the
  honest `run_unknown="1"` instead of a command the file's own bytes already prove would fail.
- New fixtures, `test/testgatenodetestimportfix/` through `test/testgatenodetestimportprecedencefix/`
  (`test/testgatecheck.sh` arms x1-x6): the exact repro, a `.js` variant, `require("node:test")`, a negative
  control (`"node:test"` only in a comment/string — parsed, not matched), and a precedence control
  (`scripts.test: "vitest run"` still wins over a `node:test` import in the same file). Five more,
  `test/testgatenodetesttsxfix/` through `test/testgatenodetestenginescompoundfix/` (arms y1-y6, fix round):
  red-first controls for the three refusal shapes above — `.tsx`, `.jsx`, an extensionless relative import,
  and two `engines.node` shapes (`>=18`, and the compound `>=24 || ^20`) that admit a pre-22.6 Node.

### Documented — TS/JS test runners this still cannot derive (`run_unknown="1"` stays honest, not a bug)

Narrowed from the 0.6.3 list: the fourth gap below (node's test runner against a `.ts` file on an unknown
Node version) is now derived, honestly bounded — see the fix above, including the cases it deliberately
still refuses (`.tsx`/`.jsx`, an unresolvable relative import, a declared floor below Node 22.6). Still not
derived, and correctly `run_unknown="1"`: node's own test runner invoked through `tsx` (a common way to run
it against `.ts` files, when neither `package.json` nor the test file's own bytes name `node:test`
directly) and `bun`'s test runner. See #323's own discussion for a user-declared runner template, which
would be the way to name either of these explicitly once implemented.

### Fixed — `--deps` no longer reports a TS/JS graph with missing alias edges as complete (#220, part 1)

A TypeScript or JavaScript import written through a tsconfig/jsconfig `paths` alias (`@app/b`), a
`baseUrl`-relative path, or a workspace package name (`@acme/lib`) draws no file-graph edge, so a cycle
spelled through one was missing and the absent `<cycles>` element read as "acyclic". Those imports are still
not resolved (that is part 2); they are now counted. A tree without one is byte-identical.
- `--deps` and `--arch` carry `imports_unresolved="N" graph_partial="1"` on the root: every value is
  measured over the resolved edges only. Not every one is a lower bound: a missing edge can merge two
  reported cycles into one, and `instab=`/`I=`/`D=` can move either way. `afferent=`, `transitive=`,
  `ccd`/`acd`/`nccd` and `violations=` can only rise. `--arch` also says on stderr that `violations=` can
  only rise; its exit code is unchanged.
- `--report` reads `## Dependency cycles (showing 1 of 1; measured over resolved edges: 3 imports unresolved)`,
  and an empty list reads "none found over the resolved edges" instead of "none (acyclic)".
- `--impact` (XML, `--json`, `--format=columnar`, and the MCP `impact` tool) carries `imports_unresolved=`
  beside `importers=` when a TS/JS import could land on one of the symbol's files.
- Only a specifier the project's own config places in the tree counts: a `paths` key with a literal prefix
  and an in-tree target, a catch-all key or `baseUrl` path only when it names an indexed file, or a
  workspace member's name from `package.json` `workspaces` or `pnpm-workspace.yaml`. A bare package such
  as `react` never counts. Relative `extends` chains are followed; a package-form `extends` is not read.
- Measured with `--deps --no-cache`, before and after, on four TS/JS trees from the r4 corpus. Chainlit:
  409 imports now disclosed (baseUrl 247, workspace 106, paths 57). Streamlit: 972 (workspace). mlflow: 204
  (paths). Zulip and sktime report none and are byte-identical. An independent re-derivation from the
  `--deps` rows and the config files agrees: mlflow exactly, Chainlit within 1, and Streamlit within the
  48 rows `--deps` does not print (it lists at most 40 per file).

### Fixed — Windows findings from the 0.6.3 preview test (#334, reported by @elsRobin)

- `skills/install.sh` no longer reports empty directories as installed skills. On Windows without symlink
  privilege, Git Bash's `ln -sfn` exits 0 and leaves an empty directory; the installer printed `installed`
  for each one, wrote all of them to the manifest and announced them as active. It now checks each link by
  its result (a symlink whose `SKILL.md` reads back). When the link did not take, it copies the skill and
  prints `copied`. When the copy fails too, it prints `FAILED`, leaves the skill out of the count and the
  manifest, and exits 1. The prune step recognises its own copies (a marker file, an empty leftover
  directory, or a name its last manifest listed) and leaves any other `ripwire-*` directory alone; before,
  a user's own `ripwire-*` directory made the installer stop with `rm: … is a directory`.
- A cache blob written by a different ripwire build is now refused with both numbers on the line:
  `format-version — not used; … rewrites it (blob format 24, this binary 25: another ripwire build wrote
  it; …)`. The
  per-tree cache path does not depend on the build, so two builds that alternate on one tree (0.6.2 and
  0.6.3 in the report) each refuse and rewrite the other's cache and re-parse on every run. One build run
  twice in a row reuses its own cache, on Windows as elsewhere. The Windows CI job now checks that
  directly: the second run's `RIPWIRE_CACHE_STATS` line must show every file reused and none re-parsed.
- `--doctor`'s `binary-path` row, when a different `ripwire` comes first on PATH, now names that
  binary's build: `which_version=` is the line it prints for `--version`. Its `STALE:` hint goes by the
  release numbers the two binaries state, where it used to go by mtime. A 0.6.2 copied onto PATH after
  0.6.3 was installed had the newer mtime, so the hint called the running 0.6.3 stale and said to run the
  0.6.2. On Windows, Git Bash's `which` prints the name without `.exe`; the row now also tries the `.exe`
  name before it reports `on_path="0"`, so it compares the two files there too. It still marks
  `degraded="1"` on Windows. When no `ripwire` is on PATH, its hint on Windows is PowerShell's
  `$env:Path = '<dir>;' + $env:Path` with native separators, where it used to print a POSIX
  `export PATH=` line that does nothing in PowerShell (reported by @lennix1337 and @antoniojosedev).
  On every platform the hint now single-quotes the directory (`export PATH='<dir>':"$PATH"`
  elsewhere), so a `$`, a backtick or `$(…)` in the directory's name cannot expand or run when the
  line is pasted; the PowerShell form also doubles `'` and the typographic quotes ‘ ’ ‚ ‛, which
  PowerShell reads as quotes too.
- The determinism check in AGENTS.md, CLAUDE.md, CONTRIBUTING, README, `--help`, the skills and the docs
  now writes its two outputs outside the crawled tree:
  `t=$(mktemp -d); ripwire . >"$t/a"; ripwire . >"$t/b"; diff -q "$t/a" "$t/b"`. Written inside it, the
  second run crawled the first run's output as a new unindexed text file, and the map header's top-6
  `unindexed=` list could change between the two runs. The engine was deterministic; the recipe was not.
  The top-6 cut itself is well-defined (count descending, then extension name) and is unchanged.
- The Windows cache location with `TMPDIR`, `TEMP` and `TMP` all unset is now documented and kept as it
  is. Windows' own temp-directory rule then falls back to the profile folder, so the cache is
  `%USERPROFILE%\ripwire-<uid>`. That is per-user, and `--doctor`'s `cache-dir` row names it.
- README's Windows section adds three notes. The hash check passes because `-eq` ignores case; use
  `.Hash.ToLower() -ceq` for a case-sensitive compare. `Expand-Archive` does not pass Mark-of-the-Web on
  to the files it extracts, so no SmartScreen prompt is not a verdict on the exe. In Git Bash, `fc` is a
  shell builtin, so compare outputs with `cmp`, or with `MSYS_NO_PATHCONV=1 fc.exe /b`.

## [0.6.3] — 2026-09-25

### Fixed — silent cuts in the report verbs and the MCP twins now say what they dropped

Each of these cut an answer without saying so. An answer that was not cut is byte-identical.
- MCP `owners` (40 rows) and `mentions` (100 files) are capped on that surface only, since their CLI
  twins print every row. A cut answer now carries `shown=`, `capped="1"`, `total=`, `has_more=` and
  `next_offset=`, and `offset=` continues it. Rows stay in path order: that is the CLI's paging order,
  so an offset names the same rows on both surfaces.
- `--zoom` `<bridge>` rows (the 12 heaviest): `shown_bridges=`, `bridges_capped="1"` and `bridges=` (all
  pairs). `--zoom --mermaid`: each of its three caps (10 top modules, 8 child modules and 5 symbols per
  subgraph) writes a `%% … shown=N total=M capped=1` comment where it cuts.
- `--tree`: a file lists its 3 best-ranked symbols. A page where some list was cut carries
  `shown_symbols=` and `symbols_capped="1"`, and each row's `symbols=` is its total.
- `next=` on `--tree`, `--zoom` and `--external-surface` now keeps the caller's `--limit`, plus the flags
  that shape the listing (`--zoom=D`, `--zoom-levels=N`, `--include-builtins`, `--pack-top-n=N`). A
  `--limit=5` page used to point at a default-sized second page.
- `--impact`: a cut import tier names the call that lists all of it, `importers_next="--impact=SYM
  --limit=N"` (a `"importers_next"` key in `--json`). Before, the cut was counted but gave no way to get
  the rest.
- `--situ`: the co-change section probes the first 20 changed files, so on a larger diff it adds
  `partners_capped="1" probed= changed_files=`, because its partner count is then a floor.
- `--run-trace`: a success tail that kept fewer lines than the capture holds carries `capped="1"`.
- `--nonlocal-state`: the 2048-cell ceiling (`cells_capped=`/`decls_capped=`) is a collection cut, so the
  root now also says `capped="1"` and `counts_floor="1"` instead of reading as a complete page.
- `--plan-lanes --brief`: a lane whose ranking held more than its 12 claims carries `"symbols_total":N` and
  `"symbols_capped":true`.
- `--from-trace` `<test_hop>`: the dropped-row count is `dropped=`. It was `capped=`, which is a 0|1 flag
  everywhere else.
- The `--recall`/`memory_recall` capped note names both spellings of each setting
  (`--top-k/top_k`, `--max-tokens/budget_tokens`), so an MCP caller is not told to pass a CLI flag.
- A body exactly one byte over the byte budget, where that byte is its final newline, is served whole
  inside the budget. Before, it carried an `over_ceiling="1"` whose reading ("its first line alone exceeds
  the budget") was false.

### Added — a Windows x64 release asset (preview)

**Releases now carry `ripwire-<version>-windows-x64.zip` and its `.zip.sha256`**, the same layout as the
tarballs with `ripwire.exe` in place of `ripwire`. It is built with clang-cl in the Release flavour (LTO, no PGO)
against the static C runtime (`/MT`), so it runs without a Visual C++ Redistributable. One reusable workflow,
`.github/workflows/windows-package.yml`, builds it for both `release.yml` (on a tag) and `ci.yml` (every full
matrix), so each train PR run uploads the exact zip a tag would publish. On that PR run it checks the compile lines
and the exe's imports for the DLL runtime, then unzips the package into a path with a space and, from outside the
build tree, runs `--version`, `--help` and a map of this repository, checks the SHA-256 with `Get-FileHash`, runs
`--doctor` (cache directory under `%LOCALAPPDATA%`), checks that the cache is written once and reused, runs
`skills/install.sh` under Git Bash, and completes an MCP stdio handshake. A new `xplat-diff` job compares a fixed
verb set (map, `--for`, `--callers`, `--impact`, `--expand` and one MCP call, over LF, CRLF and in-repo copies of
`test/fixture`) between the unzipped Windows exe and the Linux binary, byte for byte (`scripts/ci-xplat-diff.sh`
names the three rules), and the Windows side must also match itself across two runs. It stays a **preview** until
Windows users confirm it: see the README's Windows section for install steps and what CI cannot check. The
`.gitattributes` now pins `skills/*.sh` and `hooks/*.sh` to LF, so a Git for Windows clone can run them under Git Bash.

### Fixed — vendored Swift scanner: an undefined shift width on Windows (LLP64)

The vendored `tree-sitter-swift` scanner suppressed a fake `try!`/`!` token with
`1UL << FAKE_TRY_BANG`, where `FAKE_TRY_BANG` is enum ordinal 32. `unsigned long` (`UL`) is only 32
bits on LLP64 (Windows), so that shift was undefined behaviour there — well-defined, and equal to
`1ULL << 32`, on every LP64 host this repo builds and tests on (Linux, macOS), which is why it was
invisible locally and in CI. Effect: `try!` and some `!` inside `#if` blocks could parse differently
on a Windows build. Fixed with `third_party/patches/swift/002-scanner-op-suppressor-shift-width.patch`
(`1UL` → `1ULL`, same value everywhere it already ran correctly, no `kParserVer` change).
`test/vendorpatchcheck.sh` gains arm M, a static audit for this shift-width defect class across every
vendored scanner, not just Swift's.

### Added — `--biggest-first` supersedes `--readability`

**`--biggest-first` supersedes `--readability`**, which remains fully functional as a hidden alias and
prints a one-line stderr deprecation the first time it is used. The rename follows the ordering claim's
withdrawal: the flag never measured readability directly, only Halstead volume/token entropy/length, so
after the claim went, the name was the one thing left overclaiming (derivation: `docs/EVALS.md` §8).
Renaming the flag changes nothing else — the emitted `<readability functions=… >` root, the
`schema="ripwire.readability/v1"` compact-legend tag and every attribute on a row (`vol=` `ent=`
`posnett=` …) are unchanged, since renaming those would break every script that already parses this
verb's XML. stdout is byte-identical between the two spellings; only stderr carries the notice.

### Fixed — the construct-validity caveat on `--biggest-first` (`--readability`) cited a proxy number that did not reproduce

The `UNVALIDATED` note in `--help=--biggest-first` and the README said the lens agrees with a refactor
commit's implied readability direction on 30.2% of 484 function pairs. That population came from
`bench/readability_refactor_pairs.py` walking `git log --all`, which reads every branch in this clone's
shared `.git`, so the count changed whenever an unrelated branch was pushed — a rerun of the identical
script gave 413 pairs (38.3%) and, separately, 409 pairs (38.4%), neither matching the published number.
Pinning the script to the immutable `v0.6.2` tag (#313) first reproduced **154 of 412 pairs (37.4%)**,
still worse than chance (PR #321, closed as superseded before it merged). A closer look at the same
pinned population found the actual mechanism: the sign of a
function's token-count change explains the lens's own direction in **96.0% of pairs (388/404 whose count
changed)** — the caveat now cites that figure and names the tag (train 16, PR #322, merged 2026-09-22;
ships in the next release). A follow-on study then tested the ordering claim itself — whether a
least-readable function is more likely to be fixed later — against ripwire's own history, and could not
sustain it once stratified into ten narrow token-count deciles (8 of 10 show a CI that includes 1): the
raw/tercile association is a residual size
effect, not an independent readability signal. **The ordering claim is withdrawn outright**; the lens
still orders functions by Halstead volume/token entropy/length, largest first, but is no longer claimed
to order by readability. Full derivation: `docs/EVALS.md` §8.

### Changed — `--quality-delta`'s tenth kind is named `new-clone-of-reused-helper` in `--help`

`--help`'s `--quality-delta` entry called its tenth kind `reuse-decline`. The binary emits
`kind="new-clone-of-reused-helper"`, and the verb's own legend and `docs/EVALS.md` already used that
name — one kind under two names. The help text now uses the emitted string; `docs/EVALS.md`'s
abbreviation note lists `reuse-decline` as an older name. A demoted `new-clone-of-reused-helper` row also
gained an `idiom=` attribute, and gate arms now cover the reuse-decline demotions directly (train 16,
PR #322, merged 2026-09-22; ships in the next release).

### Added — `--slice=SYM:VAR` rows are in def-use order

`--slice=SYM:VAR` rows are now in def-use order, and the root states it with `order="defuse"`. Also adds
an `docs/EVALS.md` pre-registration and result for the ordering, fixes a well-formedness bug (a bare `--`
inside a full-tier XML comment), and adds a new slicecheck arm (train 16, PR #322, merged 2026-09-22;
ships in the next release).

### Changed — `--slice=SYM:VAR`'s legend and `--help` say what `order="defuse"` does not claim

A pre-registered attempt to rank `--slice=SYM:VAR` rows by relevance over the WHOLE function span did not
beat a random-shuffle control (R3@1 0.0344 vs 0.0423, bootstrap 95% CI [−0.0310, 0.0189]). `order="defuse"`
stays the default: among the rows `--slice` already narrows to it still beats random (MRR 0.628 vs 0.602 on
478 pairs). The compact and full legends and `--help=slice` now say the order ranks those rows only and is
not a whole-function relevance ranking. No row, attribute or default changed. Derivation: `docs/EVALS.md`.

### Fixed — a file refused for pathological nesting no longer disappears silently

JSON, YAML and Markdown-family files that fail the pre-parse nesting guard (memory-safety load-bearing for
YAML and Markdown; a performance guard for JSON) used to print one stderr line on a cold run only, carry no
row in `--skipped`, and go completely silent on a warm run — the cache had no record that the file was ever
refused. Worse, the `--match`/`--pattern`/`--lint` structural-query walk parsed the refused file anyway, in
the same run whose ingest had just refused it, so the guard protected the map but not those three verbs.

- Every nesting refusal — json/yaml/markdown, and Kotlin's pre-existing one — is now itemized in `--skipped`
  (`why="nest-refused"`), on cold **and** warm runs: the refused file's cache record is forgotten before the
  save, so a warm run re-refuses and re-rows it instead of silently reusing an empty hit.
- The default map's header gains `nest_refused=N` (absent when zero; `--json` twin `"nest_refused"`), so a
  reader of the map itself — not only `--skipped` — can tell a file was excluded and why.
- `--match` and `--pattern` no longer parse a file ingest refused: they apply the same refusal, exclude the
  file from `eligible_files=`, and disclose `nest_refused=N` on their own answer (absent when zero). `--lint`
  applies the same refusal and its root carries the same `nest_refused=N`, so a refused `.kt` file no longer
  leaves every rule's `count=` short with no trace. The default (compact) legend defines `nest_refused=` on
  all three roots.
- An index cache written before this change is invalidated on load (`kCacheVersion` 24 → 25) so a refused
  file already hidden in an old cache is re-scanned and rowed once, rather than staying hidden until the
  file's content next changes.

---

### Fixed — a nested `std::` call (`std::ranges::move`, `std::chrono::duration_cast`) no longer binds an unrelated in-repo definition

#134 stopped a FLAT `std::X(...)` call from binding a lone in-repo `X`, but its guard read only the call's
IMMEDIATE qualifier segment: `std::ranges::move` arrives as qualifier `"ranges"`, indistinguishable from a
user's own `mylib::ranges::move`, so the guard never applied and the call fell through to whatever in-repo
`move` existed — at full confidence, with no `amb=`. Worse for a library that mirrors std's own layout
(Boost.Chrono's `boost::chrono::duration_cast`, or any vendored `vendorlib::chrono::duration_cast`):
`std::chrono::duration_cast` canonically hit that vendored definition, and a canonical hit was exempt from
the guard by design. Both shapes are every C++20/23 codebase's normal spelling of algorithms
(`std::ranges::`), time (`std::chrono::`) and paths (`std::filesystem::`), so `--callers`, `--impact` and
every ranking computed over them inherited the false edges.

The guard now reads the FULL written qualifier chain, not just the immediate segment, on both sides:
`Reference::qualifierRootsStd` (a call's whole chain is rooted at `std`, `::std`, or a standard library's
inline ABI namespace, at any nesting depth) and `Symbol::scopeRootsStd` (a definition's whole enclosing
chain roots at `std`, including the C++17 `namespace std::ranges { … }` spelling). A candidate now survives
only when its OWN chain is std-rooted too — so a std-rooted call can no longer canonically hit a vendored
library that merely shares std's namespace layout — and a std-rooted call against a DECLARATION-ONLY std
entity with no in-repo body (no real implementation anywhere in the corpus) is refused rather than bound to
the forward declaration standing in for it. A namespace-alias or using-directive call (`namespace sr =
std::ranges; sr::move(...)`, or an unqualified call after `using namespace std::chrono;`) is a stated,
disclosed floor — its written qualifier never names `std` at all, so it is unaffected, unchanged from
today's ladder. An out-of-line std-rooted definition (`std::detail::f(){}`, `std::hash<Foo>::mix(...){}`) and
a partially-qualified one written inside `namespace std { … }` (`namespace std { int detail::f(){} }`) are
recognised too, and a std-rooted VARIABLE (a niebloid: `namespace std::ranges { inline constexpr sort_fn
niebloid{}; }`) is never refused for having no function body. A qualified def written inside another named
namespace (`namespace vendor { int std::ranges::f(int){…} }`, which defines `vendor::std::ranges::f`) is not
std-rooted, so a call to the real `::std::ranges::f` no longer binds it. `kParserVer` moves 119 → 120 (two new
per-record extraction facts, folded together with a same-day correctness fix to how one of them is
computed) and `kCacheVersion` moves 24 → 25, so any cache written by an earlier binary is refused and
reparsed.

The same "a qualified call binds by its immediate segment alone" shape was checked in Rust, C#, Python,
Java/Kotlin and Go: Rust's `std::`/`core::` guard has the identical gap — confirmed on both binaries
(`std::collections::HashMap::new()` and `core::mem::swap`/`std::mem::swap` all still bind an unrelated
in-repo `HashMap::new`/`mem::swap`) and **currently a known, UNTRACKED gap**, not filed as its own issue as
of this writing; C#, Python and Java capture no qualifier chain at all for these calls today, so the shared
mechanism does not reach them without new capture work; Go's package-qualified calls are always exactly one
segment, so the defect shape cannot arise there.

### Fixed — the whole Windows cache path, not just `--doctor`'s report of it

On Windows with neither `TMPDIR` nor `XDG_CACHE_HOME` set, `--doctor` reported the cache directory `ok="0"`
with `blobs="0" bytes="0" truncated="1"` for a cache that was in fact writable and populated (#326).
`cacheDirLadder()`'s fallback tier returns a POSIX-spelled `/tmp/ripwire-<uid>`; `os::mkdir`/`os::lstat`/
`os::chmod` — what the ladder itself calls to create and verify the directory — silently rebase that onto the
real user temp directory on Windows, but anything reaching for the SAME directory string through
`std::filesystem` or a bare `std::fopen`, bypassing `os::`, does not get that rebase and reads/writes a
directory the tool never actually uses (typically nonexistent on the current drive). `--doctor`'s cache-dir
probe and blob/edit-lock scans were the reported symptom, but not the only consumer: `resolveCacheBlobPath`
(the one choke point nearly every cache-blob path in the tree routes through), the cache-eviction sweep
(`evictOldCacheFamily`/`sweepStaleCacheBlobsOnce`), `--slice`'s and the MCP edit-preview's temp parse roots,
the cross-branch blob-batch listing, the markitdown doc-bridge cache, and the remote-clone reuse cache all
shared the exact same defect shape. Fixed at the source: `cacheDirLadder()` itself now returns the
already-rebased spelling (via the new `rw::os::rebased_path()`, the same routing `os::open`/`os::stat`/
`os::mkdir` already apply internally; identity on POSIX, where `/tmp` is already a real, directly usable
directory), so every one of the consumers above is correct by construction — none of them needed their own
fix. `--doctor`'s cache-dir row's `dir=`/`hint=` now also name the real cache location instead of a path the
tool never touches, and its writability probe still measures the only thing "writable" can honestly mean on
either platform — creating and removing a real file — never a mode-bit check.

### Fixed — the cache-eviction sweep evicts on Windows; the cache no longer grows without bound

The consumer of the defect above with the most visible cost. With neither `TMPDIR` nor `XDG_CACHE_HOME` set —
the ordinary state of a cmd.exe or PowerShell session, which have `TMP`/`TEMP` instead — the eviction sweep
that runs once per process from `saveCache` (`sweepStaleCacheBlobsOnce` → `evictOldCacheFamily`) walked the
un-rebased spelling with `std::filesystem::directory_iterator`, met a directory that does not exist, and
returned early: nothing was ever evicted — not the 30-day age pass, not the 2 GB byte budget, not the keep-N
families — while the real cache accumulated blobs indefinitely. The fix is the one above; what this adds is
the proof. The `windows` CI job seeds the real cache directory (learned from `--doctor`'s `dir=`) with stale
blobs, forces a cache write, and asserts they are gone — loud on the pre-fix code — and `evictioncheck` pins
in the source that every value `cacheDirLadder()` returns is the rebased spelling.

### Fixed — `--quality-ack`: a refused `--ack-only` no longer discards the ledger's own healing

`--ack-only=SUBSTR` that matches none of the current findings correctly refuses (exit 1, nothing accepted) —
but it used to also throw away any legacy-row provenance healing (`backfillCloneAckProvenance`) this same run
had already computed in memory for unrelated rows, because the refusal returned before the ledger was ever
rewritten. A refused `--ack-only` now still writes that healing (only when it actually changes the ledger's
canonical bytes — a canonical ledger is still left untouched), the same "heal even with nothing to accept"
rule `--quality-ack` already applies when a run's report has zero findings at all. The refusal itself, and its
exit code, are unchanged.

### Fixed — `--test-gate` derives a TS/JS runner from package.json evidence, and never lists a file's own module scope as untested

Two `--test-gate` defects, both reported against real TS/JS repos:

`--test-gate` had no runner derivation for TypeScript/JavaScript test files — only `.sh`/`.py` were
recognized — so every TS/JS `<t>` row carried `run_unknown="1"` and the gate could never clear on a
TS/JS change with a test partner (one report measured 154 of 154 runs over three days hitting this on
a vitest project). The runner is now derived the same evidence-first way Python's already is: the
nearest `package.json` above the test file (walking up, so a monorepo/workspace test file's own
manifest is used, not the repo root's) is read for a `scripts.test` entry or a `vitest`/`jest`
dependency naming one of the three runners this recognizes — `vitest`, `jest`, or node's own built-in
test runner. A manifest naming none of the three, or no manifest at all, stays the honest
`run_unknown="1"` it already was — never a guessed default. New: `src/jsrunner.h`.

`--test-gate` could also list a file's synthetic module-scope owner (`<file-scope>`, minted for a
top-level call or an anonymous-callback body, #60) as an "untested" symbol — a row an agent could
never discharge, since nothing in any language can call `<file-scope>` and no test can be written for
it. `model.h::isUntestableOwner` now excludes it from every such obligation listing in one place:
`--test-gate`'s untested rows and `--flags --flip`'s untested hosts, the two places a synthetic owner
could reach a reader as an actionable item. It still counts toward the coarser `impacted=`/`hosts=`
gauges, where it is a real caller in the blast radius — only the per-row obligation list changes.
The excluded count is disclosed, not silent: `--test-gate` now carries `untested_modscope="N"` (XML
and JSON) alongside `untested=`, so a change whose only reader is an untestable entrypoint reports why
its `untested=` reads zero instead of reading like there was nothing to find. `--flags --flip` counts the
same exclusion as `untested_modscope="N"` on its root (present only when N > 0), where the host row itself
still lists the `<file-scope>` owner with `tested="0"`. The full `--test-gate` legend defines
`untested_modscope=` at zero too.

### Fixed — five defects in the TS/JS runner derivation above, found by independent review before merge

- **A named shell/Python driver was losing to "unknown".** TS/JS test files now have their OWN evidence
  path (`package.json`), and that path used to be preferred outright over a `test/*.sh` (or `.py`)
  driver whose own text names the file — a real, previously-working signal. A TS/JS file with no
  usable `package.json` evidence now falls through to that same driver search (shared by
  `--test-gate`, `--affected`, and the MCP `affected` tool, which all read one `TestRunnerIndex`).
- **A `scripts.test` that names no recognized runner was overridden by an unrelated dependency.** A
  `mocha` project that happens to also list `vitest` in `devDependencies` (for its config types, say)
  derived `npx vitest run …` — a command that would find no matching tests. `scripts.test`, once
  present and not npm's own placeholder, is now authoritative: it decides the runner (or decides none),
  and a same-named dependency never overrides it. Dependency evidence is consulted only when there is
  no real `scripts.test` to read. Runner names are also matched as shell WORDS now, not substrings, so
  a script naming an unrelated file that merely contains "jest" in its path no longer derives jest.
- **Every `.ts`/`.js` file under a test directory was spelled as a vitest/jest target, including
  non-tests.** A helper or setup file living beside real tests (or a `.d.ts` declaration file) matched
  the extension check and got a `run=` command that would fail in CI ("no test files found") — vitest
  and jest only collect files matching their own `.test.`/`.spec.` naming, or a `__tests__/` directory
  segment. Only a file matching that shape is now spelled as a runnable target; a `.d.ts` file is never
  one, regardless of evidence.
- **The nearest `package.json` could end the search before it decided anything.** A bare module-type
  marker (`{"type":"commonjs"}`, common in mixed-module repos) sits between a test file and its real
  runner evidence in some layouts; the walk now keeps climbing past a manifest that names neither
  `scripts.test` nor a recognized dependency, instead of stopping there and reporting unknown. A manifest
  WITH a real `scripts.test` still ends the search immediately, whatever it names (even an unrecognized
  runner): its own answer is final for that subtree and a workspace root's `vitest`/`jest` never
  overrides a package that already answered "mocha" for itself — the same authority `scripts.test`
  already has within one manifest, now honoured one level up a monorepo too.
- **A `__tests__/`-only jest test file (no `.test.`/`.spec.` in its own name) was invisible to
  `--test-gate` entirely** — not merely runner-unknown: its module scope read as an untestable owner, so
  a change covered only through such a file exited 0 with nothing to run. `__tests__/` is now a
  recognized test-path directory segment (`filter.h::isTestPath`, the ONE test-path convention every verb
  shares — widened there, not duplicated), the same fix `looksLikeJsTestFile` already carried for it
  unreachably. Checked empty of side effects on every other language: no `__tests__` directory exists
  anywhere in this repo's own tree, so no existing fixture or pinned gate could have been counted as test
  code by this convention before. jest's OTHER default pattern (a bare `test.js`/`spec.js` filename, no
  leading dot or underscore) remains a narrower, separate, undocumented-no-longer gap — see below.
- **`npm run <script>` / `yarn <script>` / `pnpm <script>` indirection inside `scripts.test` is honest-
  unknown, not derived.** `scripts.test: "npm run test:unit"` with `scripts["test:unit"]: "vitest run"`
  used to derive vitest via the (now-removed) dependency fallback; it is real, common indirection this
  version does not follow. Stated as a floor below, not fixed — following it needs the same authoritative-
  script rule one script-name hop deeper, which is a larger, separately-scoped change.

### Fixed — two more TS/JS runner-derivation defects, found in PR review

- **The test-name check read the absolute path.** The `__tests__/` segment test ran over the file's path on
  disk, so it also matched directories ABOVE the crawl root: in a checkout under `…/__tests__/repo/`, a
  helper such as `test/setup.ts` was spelled `run="npx vitest run test/setup.ts"`, and in any other checkout
  `run_unknown="1"`. It now reads the root-relative path, so the answer no longer depends on where the repo
  sits.
- **A TS/JS test file could become another row's runner.** The driver search that lets a TS/JS file fall
  back to a shell or Python driver naming it also searched the TS/JS test files themselves, so a jest test
  that merely `require`s `./util.js` gave the `util.js` row `run="npx jest test/util.test.js"`, and a miss
  read every TS/JS test file to find out. The search now covers `.sh`/`.py` drivers only, as documented.

### Documented — TS/JS test runners this cannot yet derive (`run_unknown="1"` stays honest, not a bug)

A handful of real, common TS/JS test-runner spellings are not covered by the three named in #323 and
correctly read `run_unknown="1"`: node's own test runner invoked through `tsx` (a common way to run it
against `.ts` files), `bun`'s test runner, and node's test runner against a `.ts` file on a node
version too old to strip TypeScript types natively. None of these is guessed at; see #323's own
discussion for a user-declared runner template, which would be the way to name one of these explicitly
once implemented. `pnpm`/`yarn`-prefixed `scripts.test` entries derive correctly today, spelled as
`npx …`, since `npx` finds a locally installed binary first. A bare `test.js`/`spec.js` filename (no
leading dot or underscore — jest's OTHER default `testMatch` shape, distinct from the now-recognized
`__tests__/` directory convention above) is not yet a recognized test path either. `scripts.test`
delegating through `npm run <script>` / `yarn <script>` / `pnpm <script>` to another entry in the same
manifest (`"test": "npm run test:unit"`, `"test:unit": "vitest run"` — a common shape for a project
with several test scripts) is read as this project's own authoritative-but-unrecognized answer and
stays `run_unknown="1"` rather than being followed one level deeper into the target script's own
value — a stated floor, not a guess. (A delegating script whose OWN name happens to literally contain
`vitest`/`jest` as a word, e.g. `"npm run test:vitest"`, still derives correctly today — that is the
existing word-match rule firing on the visible text, not indirection-following.)

### Fixed — a `--regex` spelling one byte by number dropped every file that matched it, at `capped="0"`

`--regex` opens only the files a sound regex→trigram query admits (`src/search.h`'s `RegexAnalyzer`, the Cox
prefilter; the full-scan switch the gates use is its oracle). That reader knew `\n`, `\t`, `\w`, `\b` and an escaped
metacharacter, and took every other escape for its letter: `\x66s::exists` became the literal run `x66s::exists`,
whose trigram `x66` no source file holds, so the ten files with `fs::exists` were never opened — and the answer
still said `files="0" hits="0" capped="0"`. In an alternation the escaped branch went missing on its own:
`fs::exists|\x66s::remove` answered 11 files where the full scan and ripgrep answer 14. The same reading inside a
class (`[\x66]s::exists` enumerated `{x,6,6}`) dropped the same ten. `\uHHHH`, `\cX` and a backreference `\1` had
the same shape; the screen in `src/regexguard.h` lists all four as portable escapes, so they were accepted and then
misread. The analyser now steps over exactly the characters the engine reads as the escape: `\xHH` and `\u00HH`
with every digit present and an ASCII value are that one byte, and the rest are one byte it does not vouch for
(ALL — sound, as `.` is). Only the CLI `--regex` evaluates that query; the MCP `grep` verb is a literal-only
scan (`src/mcpverbs.h`'s `grepHitsJson` calls `grepCollect(..., /*regex=*/false, ...)`) and never reached this
code, and neither did the literal `--grep`, the unindexed scan or the line-level literal paths.

Two more soundness gaps in the same analyser, found in review before this landed: a class range ending at
`\x7f`/`\u007f` (both portable, accepted escapes) looped forever — `for( char ch = lo; ch <= hi; ++ch )` never
terminates once `hi == CHAR_MAX`, and RSS grew without bound within seconds; the loop now counts with `int`.
And a non-capturing group `(?:...)` was read as a zero-width assertion (ε), the same as a lookaround, so its
content never entered the trigram query: a pattern such as `std::(?:string)&` required the seam trigram `::&`
of every file, and every real `std::string&` occurrence dropped at `capped="0"`. `(?:...)` is now parsed as an
ordinary group that consumes its content, and a lookaround whose skip loop passes an unescaped `[` (a class may
itself hold `(` or `)`, which desyncs that loop's depth count) now falls back to ALL rather than trust it.

Gate: `test/regexcheck.sh` — four escape patterns join the prefiltered-versus-full-scan battery (S), which now
refuses to compare two empty answers; (E) pins the alternation shape (`zylophoneXyzzy|\x63ompute`: the escaped
branch is the only match in two fixture files, and both must be listed with the file count equal to full-scan's
and above the first branch's alone); (O2) checks the escape patterns against ripgrep, which spells `\xHH` where
`grep -E` cannot; (F1) runs `[\x7e-\x7f]` under a short alarm and fails on a hang; (F2) runs `std::(?:string)&`
against this repo's own `src/` and requires prefiltered == full-scan. Red on the previous binary: (S) 4 of 17,
(E), and (O2) 3 of 3; (F1) hangs (rc=142); (F2) diverges from full-scan. A seeded differential fuzz (fixed
seed, 260 patterns mutated from this dialect: `\xHH`/`\u00HH`, `[c]`/`[cC]`, `(c)`/`(?:c)`, `(?=c)`/`(?!c)`,
`? + * {1} {1,2} {0,1} {1,}`, `\w \d \s`, `.`, backrefs, alternation, `^.*`) now compares `--regex` against
`--no-prefilter` on every run, so a future soundness regression in this analyser is a gate failure, not
another review finding.

### Fixed — body packing, `--outline` and `--pack-signatures` rank before they cut, and every cut is named

- **Bodies were cut in file order.** `packBodies` (the `<bodies>` of `--expand`, `--for` auto-bodies and `--detail`,
  `--pack-task`, `--from-trace`) grouped its requests by file before the byte budget ran, so a low-ranked body sharing
  the top body's file was admitted ahead of the second-ranked body in the next file. The budget now walks the caller's
  own order and only the survivors are grouped by file (the emitted shape is unchanged). On a three-body fixture,
  `--expand=alpha_head,gamma_mid,beta_tail --pack-budget-bytes=500` shipped `beta_tail` and dropped `gamma_mid`; it
  now ships `gamma_mid`. On the 92 held-out LocBench issues, `--for --detail=6` selects a different body set on 1/92
  (gold-body-served 52/92 before and after); the default `--for` route serves no bodies there and is byte-identical.
- **Every dropped body is named.** Bodies met after the budget was spent used to be dropped with no name at all; they
  are now listed, in rank order, in ONE `<!-- bodies omitted (budget spent): a, b -->` comment (one list rather than a
  marker each, so a long tail's disclosure stays small: 29 dropped `--for --detail=30` bodies on a 30-function fixture
  under `--token-budget=800` are named in 502 B, against 1,479 B as one marker each). A body
  skipped because it did not fit while budget remained keeps its `<!-- body omitted (over budget): NAME -->`. Every
  requested body is shown, named as omitted, counted as `bodyless=`, or (an unreadable span) only counted in
  `total=`; the JSON `bodies_omitted` lists the same names.
- **A truncated body says so outside its CDATA.** An oversized first body used to carry `<!-- truncated -->` inside
  its CDATA while `<bodies>` said `capped="0"`. It is now `<bodies … capped="1">` and
  `<b … lines="1-17/377" truncated="1" next="--expand=P:L:N:18-377">`; following `next=` at the same budget
  reassembles the body byte for byte. The cut always falls at a line end and `lines=` counts whole lines only: when
  not even the first line fits (a 70 KB line at the default 64 KB budget, or a nearly spent `--detail` budget that
  used to serve one byte), that line is served whole with `over_ceiling="1"`, so every `next=` starts past what was
  served and a chain of them always ends. The JSON twin carries the same `lines`/`truncated`/`next`/`over_ceiling`.
- **`--expand`'s cut `<calls>` listing** (16 rows) kept the lowest node ids. It now keeps the callees whose names have
  the fewest callable definitions in the index first. Over the first 60 cut listings of this repo and three held-out
  corpora, the share of kept callees defined in the body's own file rose on all four (here 11.5% to 16.2%; scrapy
  3.9% to 9.4%; sqlglot 23.6% to 31.4%; mypy 8.9% to 9.5%), but the share defined in the body's file or a file it
  imports fell on mypy (75.1% to 69.8%). The map's PageRank, the other candidate, is corpus-dependent: better than
  node-id order on scrapy and sqlglot, worse on this repo and mypy, and below the shipped order on all four.
- **`--outline` and the map's `--pack-signatures`** walked their byte budget file-major and closed a cut with a bare
  element. Both now walk rank-first, emit the survivors in the same grouped shape, and disclose a cut with
  `shown= total= capped="1"` (`<!-- outlines omitted (budget spent): a, b -->` names the dropped skeletons). An uncut
  answer is byte-identical, except that `--pack-signatures` rows sharing one start byte in a file now tie-break by id.
  `--pack-signatures`' `total=` is the rows handed to the byte budget (its `--pack-top-n` window), as on `--for`'s
  `<sigs>`, so a default call that the budget did not cut stays a bare `<sigs>`.
- The full `--expand` legend said `sibs=` is "capped at 8"; the cap has been 100 since 2026-09-10.

### Fixed — `--grep`'s collection ceiling ranks before it cuts, and every grep cut has a compact reading

- **The 4,000,000-hit collection ceiling cut the head.** `grepCollect` spent the ceiling in ascending file order and
  only then sorted SOURCE before test/bench before docs, so a pattern dense in files that sort early kept those and
  dropped the rest. On a fixture of two hit-dense `docs/*.md` files and one `src/` file (5M hits),
  `--grep=x` answered `files="2" hits="4000000" hits_capped="1"` with no source row at all. The hit files are now
  ranked first (the shared tier-then-path key, `src/filter.h`) and the ceiling spends in that order, so it drops only
  the tail of the least relevant tier: the same answer now leads with `src/main.c` and `files="3"`. The cut is
  disclosed as before (`hits_capped="1" counts_floor="1" capped="1"`). On this repository no literal reaches the
  ceiling (`--grep=e`: 2.6M hits), so every answer here is row-for-row unchanged. CLI and the MCP `grep` verb share
  the collection.
- **The span-tier classification budget says how much it left.** `tier_budget=` named which ceiling (128 files or
  8 MB) stopped the code/comment/string classification, but not how many hit files it had to cover; `files=` cannot
  stand in, because it counts files after suppression. `tier_files=` now rides beside `tier_budget=` (MCP:
  `tier_files`), e.g. `--grep=std::string` on this tree: `tier_parsed="128" tier_budget="files" tier_files="256"`
  where `files="251"`. About 16 bytes, on budgeted answers only.
- **Three grep attributes had no reading in the default (compact) legend.** `tier_budget=` (which `tier_parsed=`'s
  own reading pointed at), `tier=` on a comment- or string-only answer, and `line_bytes=`, the one sign that a row's
  matched text was cut at 512 bytes. Each now has a present-only reading: +56 to +190 bytes on the answers that carry
  them, nothing on the rest.

Gate: `test/collectioncapcheck.sh` (J) (the ceiling fixture, CLI and MCP) and (K) (`tier_files=` CLI and MCP, and
the three compact readings). Red on the previous binary: (J) 3 of 5, (K) 5 of 7.

### Changed — `--callers`, `--uses` and the `--impact` import tier rank before they cap; `--callees` keeps path order

Each of these lists sorted its rows by tier, then path, then line, and then cut at a default cap (40 symbol
rows, 100 use sites, 40 importer files). The cut therefore dropped whatever sorted last by path, not the
weakest rows: on this repository `--callers=kindIs` kept the 40 alphabetically-first of its 135 callers.

- **One order, ranked — callers, uses and the import tier.** Within a tier (source, then test/bench, then
  docs — unchanged), rows now come most-depended-on first: a caller by its own caller count, a use site by the
  caller count of the symbol it sits in (file-scope sites last), an importer file by how many files import it.
  Path and line break ties, so a list whose weights tie is byte-identical to before, and an answer with one
  row, or rows of equal weight, is unchanged. **The emitted row order changes** on any multi-row answer whose
  weights differ: the most-depended-on rows lead. That is the same total order the cap and `--offset`/`--limit`
  read, so a page is a slice of it and `page[0:k] + page[k:2k] == page[0:2k]` still holds. Selecting by rank
  and then re-sorting each page by path was considered and rejected because it would break that identity.
  The MCP twins (`find_referencing_symbols`, `find_symbol`'s `calledBy`, `uses`, `impact`) share the order.
- **`--callees` and `find_symbol`'s `calls` keep their order — rows and default output byte-identical to
  before;** only the full legend's shared ordering sentence changed. A first cut of
  this change ranked callees by the same key (each callee's own caller count), reasoning that one rule should
  cover both directions of the same call hierarchy. Measured, it was worse: on this repository's own co-change
  instrument, `--callees`' default-cap recall fell 0.592 → 0.466 (n=18), because a callee's own caller count
  says how widely-called that callee is ELSEWHERE, not how central it is to the body that calls it — the cap
  kept `empty, empty, empty, size, c_str` and dropped the two most specific callees of a 42-callee symbol.
  Callees keep the tier/path order they always had.
- **`find_symbol`'s `calledBy` array states its cut.** It is windowed by the same `limit`/`offset` as `calls`,
  but `count` and the paging keys describe `calls` only, so a 105-caller symbol served 40 `calledBy` rows with
  no sign that any were missing. A cut array now carries `calledBy_total`, `shown_calledBy`,
  `calledBy_capped` and `calledBy_next` (the `--callers` call that continues it). An uncut array is unchanged.
- **`--limit` reaches the `--impact` import tier.** `shown_importers` was fixed at 40 whatever `--limit` said,
  so a cut tier had no call that fetched the rest. `--limit=N` now sizes the tier like the symbol rows (one
  limit, one size in one answer). `offset=` still windows the symbol rows only.

Measured on this repository's own history at 60b65f02, with a new instrument (no existing recall measure
covered these lists). The "row that mattered" is a caller or use site last rewritten, per
`git blame -w`, by the same commit that last rewrote a line of the symbol's definition. Commits touching more
than 40 files are excluded. For importers it is a file changed by such a commit. Default cap, before → after,
on the SMALL populations this repository has over the cap — **17 / 19 / 9 symbols** for callers / uses /
importers: `--callers` hit rate 0.41 → 0.71, recall 0.32 → 0.51; `--uses` hit rate 0.53 → 0.74, recall
0.43 → 0.52; import tier hit rate 0.78 → 1.00, recall 0.40 → 0.70. With `--limit=10` (76 / 80 / 30 symbols),
`--callers` recall is 0.62 → 0.67 and `--uses` 0.51 → 0.54. The import tier's recall is 0.47 → 0.46, a slight
drop at that depth. `--callees` rows and default output are byte-identical to before on representative
symbols, both on the CLI and in the MCP `calls` array. Bytes on the ranked lists are otherwise unchanged apart from the legend: the
rows are the same set whenever nothing is cut.

**Honesty, from an independent review.** The review re-ran this instrument with
paired bootstrap 95% CIs and two baselines — path order (above) and a within-tier random shuffle — plus a
prospective gold (this repo, later commits) and a second corpus (LocBench). At the default cap the n above is
small (17 / 19 / 9), and every callers/uses figure there is directional: the ranked-minus-path delta crosses
zero for both lists at the default cap, and the gain over random order reaches significance at
`--limit=10` (callers +0.082 [+0.008, +0.155], uses +0.116 [+0.048, +0.187]) and, for uses alone, barely at
the default cap (+0.159 [+0.004, +0.325]). The **import-tier gain holds up
outside this instrument's own assumption**: a forward-in-time gold (the lists ranked on an earlier snapshot, scored on the commits made after it) gives
`--limit=10` recall 0.307 → 0.659 (n=11, 95% CI [+0.149, +0.574]) and `--limit=20` 0.185 → 0.792 (n=6,
[+0.379, +0.845]); LocBench gives `--limit=20` 0.143 → 1.000 (n=7, [+0.571, +1.0]) and `--limit=10`
0.500 → 0.857 (n=14, [0, +0.714]). The **uses gain is modest and replicates at k=10**: LocBench
`--limit=10` recall 0.490 → 0.673 (n=27, [+0.013, +0.356]). The **callers gain is the weakest of the three**:
on LocBench it is indistinguishable from, or below, random order (`--limit=20` recall is BELOW random order,
n=9). Nowhere does any of the three ranked lists score significantly below its pre-change baseline.

### Fixed — `--for`'s `<sigs>` byte budget cuts the rank tail, and every signature cut is named

- **The byte gate ran before the rank sort.** With `--pack-budget-bytes` (and on `--pack-task`/`--from-trace`,
  which share the path) the `<sigs>` byte gate spent its budget in file order, so a tight budget could ship
  r=7 and r=20, drop r=1, and still print a bare `<sigs>`. It now runs on the rank-sorted rows and cuts only the
  tail: on this repository `--for="rank graph teleport" --pack-budget-bytes=2000` ships r=1..8 under
  `<sigs shown="8" total="40" capped="1">`, where it used to ship ten scattered rows with nothing disclosed.
  `total=` counts the rows handed to the budget. The `--json` root gains `sigs_shown`/`sigs_total` when the
  array was cut.
- **Dropped doc comments are counted.** A shown row past r=24 (or cut by the trim ladder) prints no doc
  comment; `<sigs docs_dropped="N">` (JSON `docs_dropped`) now counts those rows, present only when N > 0.
- **A capped block that only shrank rows says so**: its legend clause reads rows shrunk, none dropped, when
  `shown=` equals `total=`.
- A default `--for` cannot reach the byte gate (a 40-row head is at most about 19 KB of 64 KB). On the 92
  held-out LocBench issues no grain moved, and bundles grew 4.5 bytes on average.

### Fixed — `--field-affinity` pair names, `--clones` paging, `--verify`'s page tail and the Type-3 cap disclosure

- **`--field-affinity` named the wrong fields in a `<pair>`.** A pair's `a=`/`b=` indexed the struct's fields
  in declaration order, but the fields were re-sorted for display first, so a struct whose display order
  differs printed the wrong names; a pair on a field past the 32-row display cap read a destroyed element
  (a libc++-hardened build traps there). Pairs are now remapped through the display order, and the cap
  bounds only the printed `<f>` rows. No pair is dropped.
- **`--clones` pages served some groups twice and others never.** The bare run served the first 40 Type-1/2
  groups plus the first 40 Type-3 groups, but `--offset` indexed one flat Type-1/2-then-Type-3 stream: on a
  448-group fixture the bare run plus its `next_offset=` walk returned 448 rows, 443 distinct. The row stream
  is now ordered so the bare run is its prefix, and every group is served exactly once. The bare output is
  unchanged.
- **`--verify` advertised a page it refused.** A capped evidence sample carried `total= has_more=
  next_offset=`, and `--offset` was then refused. It now carries `shown=`/`capped=` only; the answer's own
  count attribute (`count=`, `hits=`, `defs=`, `occurrences=`) already gives the total.
- **`--clones` printed `counts_floor="1"` on every run.** The Type-3 pair cap was never disclosed in a release
  build, and the floor marker was hard-coded. `counts_floor="1" type3_capped="1"` now appear only on a run
  where the cap fired.

### Fixed — the hooks' command-word rule no longer holds a Bash call for minutes on a long line (#327)

`rw_is_ripwire_call`, the one rule the three hooks share to decide whether a Bash line runs ripwire, rebuilt
the rest of the line for every character it read, so its cost grew with the cube of the line's length: 2.9 s at
2,000 characters, 20.6 s at 4,000 and 155 s at 8,000 under macOS bash 3.2. The PreToolUse meter runs it on every
Bash call, and one command carrying a heredoc held the call for 6 min 49 s. Two guards now run before the scan,
and both can only turn a call into a missed one, never create a false one:

- A line that does not contain the literal `ripwire` holds no call. The check reads the raw text before quote
  removal, so a command word the shell assembles from quoted or escaped fragments (`'rip''wire' .`,
  `rip\wire .`) now reads as no call; the scan alone read it as one.
- A line longer than 1,024 characters is not scanned and reads as no call.

For the substitution meter this is a numerator that can fall short on those two shapes
(`docs/SUBSTITUTION_METER.md`, "Known undercount"). `test/routehookcheck.sh` O10 holds the cost (4,000
characters: 20 s before, 0 s after) and O9 pins the four assembled-word shapes.

### Fixed — the prompt routers no longer time out on every prompt outside a git work tree (#327)

`hooks/ripwire-claude-route.sh` and `hooks/ripwire-codex-route.sh` ran `--help-task` for every prompt. Outside
a git work tree it has no file list from git and walks the whole tree under `cwd`: a session started in `$HOME`
still ran after 30 s, past the 8 s hook timeout, so Claude Code discarded the hook and printed a timeout warning
on every prompt (0.08 s for the same prompt in a git repository). Both routers now exit before the classifier
when git does not place `cwd` inside a work tree. A small non-git project gets no recommendation and
writes no routing row either. `test/routehookcheck.sh` O11 holds it with a stub `ripwire` that records each call.

### Added — Ruby's class-level attribute DSL (`attr_*`) defines Var symbols

`attr_reader`/`attr_writer`/`attr_accessor` are Ruby's canonical class DSL, and `attribute`/`attributes` are
their ActiveModel counterparts: each macro generates the accessor methods named by its arguments when the
class is defined — `attr_reader` spells only the reader, `attr_writer` only the writer, and `attr_accessor`/
`attribute` spell both. The family is EXACTLY these five verbs; ActiveSupport's neighbouring accessor macros
(`cattr_accessor`, `mattr_accessor`, `thread_mattr_accessor`, `class_attribute`, `attr_internal`) are
deliberately not in it — the scope is a decision, not an omission.
Those generated names were indexed by none of them — a write against one resolved to nothing. The class DSL
now mints real symbols: one `Var` def per `simple_symbol` argument (named as the argument, minus the leading
`:`), plus the `<x>=` setter for the writer-side macros (`attr_writer`/`attr_accessor`/`attribute`; the plural
`attributes` is READERS-ONLY — its third-party owners, AMS/jsonapi-serializer/dry-struct, define no setters,
measured — so no phantom setter weight) — the exact spelling the setter-call rename already produces, so
`record.x = v` BINDS to a def instead of dropping. The singular `attribute` takes one name; a trailing type
or `default:` argument is metadata, not a def. An `attributes` do-block body is walked but defines nothing.
An INLINE-VISIBILITY wrapper is also class-DSL position: `private attr_reader :x` (Ruby 3, RuboCop's
Style/AccessModifierDeclarations: inline) evaluates its argument first — the macro runs and the method IS
defined — then applies visibility, so the capture unwraps one receiverless `private`/`protected`/`public`
call when the family call is its sole argument. `module_function attr_accessor :x` is not unwrapped: it raises
in a class (NoMethodError) and in a module (TypeError), so it defines nothing. Accessors inside `class << self`
define on the class; inside `class << Registry` (another object's singleton) they define nothing, rather than a
def on the enclosing class. A comment before `attribute`'s first argument is skipped, not taken as that
argument. This REVERSES a stated floor:
queries/ruby/tags.scm used to say "attr_accessor/attr_writer/attr_reader define nothing in the source TEXT
… a write against one is an honest nothing". That posture predated measurement; tested to be working in a
real, running Rails application (test/rubyattrsfix/USECASES.md), these macros define methods that every
`record.price` reads — the silence was a coverage hole, not honesty. The reversal is GLOBAL: every indexed
Ruby corpus gains Var defs, attribute names leave the external surface, setter writes bind, and — because
Call refs are language-gated, not kind-gated — attr names receive real call edges and PageRank weight
(accepted churn, disclosed here). The DSL CALL itself stays a reference capture: `attr_accessor` and friends
remain external-surface names, the same posture as the schema DSL rows. One id caveat: a same-class
`def x` + `attr_accessor :x` produces TWO defs sharing one `p::sc::n` id (the dedup ladder folds only
same-byte captures; the pair is two identities) — the id is not unique in that case. kParserVer 120 → 121
(extraction facts changed, the bump past everything main carries; no record layout change — kCacheVersion
stays 25, kQSnapCacheScheme stays 14).
Gate: `test/rubyattrscheck.sh` on `test/rubyattrsfix/` (fixture proven against a running Rails application;
red on the pre-change binary — the before-state `defs=0 external=1` attribution rows are the before-evidence).
Disclosed capture floors, pinned by the gate's `floor_attr.rb` arms: a `begin`- or modifier-`if`-guarded macro
call is not unwrapped to class-DSL position; the do-block BODY of an `included`/`class_methods`
(ActiveSupport::Concern), of `Struct.new`/`Class.new`/`Module.new`, and a non-modifier `if … then … end`
block are not unwrapped either (each defines real methods at runtime); and only `simple_symbol` arguments
define — a quoted (`:"x"`/`:'x'`), string, or splat/`%i[]` argument stays an honest nothing (Ruby defines
those methods; ripwire does not capture them). Every floor is stated and pinned, never silent.

## [0.6.2] — 2026-09-21

### Added — Microsoft's `cl.exe` builds the tree, so both Windows front ends compile and both gate

The native Windows port (#44) built with clang-cl only; `cl.exe` stopped at the GCC/Clang language extensions
this tree is written in. Four classes of extension now go through a portability seam and both front ends build
on `windows-latest` in every full matrix, each running the same smoke steps (`--version`, `ctest`, a real crawl
of `test/fixture`, the two-run byte-identical contract, well-formed XML).

- `__BASE_FILE__`, which `src/structlayout.h` used to stamp a layout assertion with its own translation unit, is
  supplied by CMake as `RIPWIRE_LAYOUT_TU` per source file; the header `#error`s rather than guess when neither
  is available.
- `__PRETTY_FUNCTION__`, `__int128` and `__BYTE_ORDER__` are behind `src/infra/platform.h` — and, for the layer
  below it that cannot include it, `src/infra/Diagnostics.h` §1c.
- `/bigobj` is passed on both MSVC-ABI front ends: `src/main.cpp` exceeds the COFF limit of 2^16 sections
  (fatal error C1128, windows-latest CI, 2026-09-20).

`hashutil`'s wrapping multiply is the one place where the two front ends get different code, and deliberately.
The `unsigned __int128` product with a mask is not there for its value — that is plain modulo-2^64 arithmetic —
but to be sanitizer-clean: G1's `integer` group flags a wrapping `uint64` multiply and `-fno-sanitize-recover=all`
makes it fatal, so a narrow body aborts every ASan-flavour crawl on the first byte of the first hash. GNU and
Clang therefore keep the wide multiply, proven byte-identical to the previous binary by an empty `.s` diff at
`-O2` and under the sanitizer flags; MSVC, which has neither the wide type nor the check, gets the plain
multiply. The sanitizer is not suppressed on any platform that runs it.

`test/osswitchcheck.sh` gains arm H, which refuses a new `__builtin_*`, inline asm or `__attribute__` outside
that seam pair, with a pinned per-row `EXEMPT_COUNTS` so a growing allowlist cannot pass unnoticed. A
Windows-breaking change now fails on every POSIX leg instead of being discovered on Windows. `README.md`,
`CONTRIBUTING.md` and this file say the same three things about the platform: both compilers build, CI verifies
both, the 647-gate suite does **not** run on Windows, and the ASan flavour is compiled there but never executed.

### Changed — the README's top says what ripwire is before it says what it did

The page opened with a release note. It now opens with the differentiator — a map before an agent reads the repo,
and a check on what it writes — followed by one sentence naming what the check actually reports: blast radius,
the tests that reach a change, ten quality kinds reporting only what got worse, forgotten co-changes, fields read
and written, and names that resolve more than one way. Every clause was verified against the binary's own
`--help` and `docs/COMMANDS.md` before it was written. The 0.6.1 paragraph is condensed to the two figures that
carry it (46–66% smaller compact answers; 114 MB → 368 KB on llvm-project) with all three contributor credits
kept, and the badge row moves above the banner so the first screenful is signal rather than decoration.

### Fixed — `--adaptive` no longer narrows a large pool of identically-named symbols on tie-break order

A name-exact route against a common word (`update`, `run`) puts dozens of unrelated, identically-named
definitions into one scoring pool. Their scores differ only by the ranker's tie-break, so the largest
relative gap in that pool is an artefact of ordering, not a relevance cliff — and `--adaptive` cut on it
anyway, taking `update` from 231 symbols to 6 and `run` from 148 to 10 while the header stamped
`confidence="high"`. `--adaptive` now declines to narrow when a name-exact route's positive pool clears
`kAdaptiveHomonymPoolFloor` (50) and the proposed cut is at most twice the floor: the default top-N is
served instead, an in-band note says why (the pool size, and that the gap is tie-break order), and
`confidence=` stops claiming `high` on a cut it declined to trust. `margin_pct=` keeps the true measured
drop — a zero there still means "no cliff found", never "none exists".

The routing question behind the gate is now asked once. Three call sites — `--for`'s own bundle, the
`--format=candidates` export and the MCP `for` verb — each decided "is this the name-exact lane" their own way,
and `runForLens` asked the negation of a different question (`!isConceptualRoute`), which is also true for
the third route state, `no-route`. So `--no-route --adaptive` read an un-routed ranking as name-exact and
reported a same-name count for a pool that did not exist, with the CLI and MCP disagreeing on the same
tree. `isNameExactRouteTag` is the single predicate all three now call.

### Fixed — legend, capture and disclosure gaps found by a deferred-items sweep

Nine items carried from earlier trains, all in the disclosure surface rather than in analysis: eight stale
entries in the full/compact legend baseline closed; a live `CHANGELOG.md` figure for the `tools/list`
manifest corrected against a measurement (`test/mcpmanifestcheck.sh` arm `(1b)` now asserts it against a
live `tools/list` response, so the same rot fails a gate instead of waiting to be rediscovered);
`test/showcasecapturecheck.sh` gained staleness detection, which immediately caught a stale capture;
`--pack-task`'s bodyless placeholder branch now emits the `bodyless=` count and a false `capped="1"` is
gone; a `--around-depth` row in `docs/LINEAGE.md` corrected; `--readability` carries an explicit note in
`--help` and `README.md` that its score is not validated against a human-judgement corpus; and stale
quality acknowledgements were healed through the binary rather than by hand. The rule for choosing which
gates a change must run — by verb, by fixture, by the files it touches, and by shard — now lives in
`CONTRIBUTING.md` instead of a train's own notes.

### Fixed — `--dead-code` no longer claims a confidence its evidence cannot support

Every `--dead-code` root carried `confidence="high"`, hardcoded: nothing in the candidate loop — internal
linkage plus zero indexed callers — varied it, so the attribute was a constant wearing the shape of a
finding. The claim is also the one most likely to be acted on destructively, since the row an agent deletes
on a false "high" is live code reached by a virtual call, a reflection hook or a macro-generated caller,
none of which a name-based graph can see. The attribute is **removed** rather than replaced by a derived
number: there is no per-finding signal to derive one from, and `evidence="internal-linkage+zero-callers"`
already states the one thing the code actually knows. The full and compact legends, `--help` for
`--dead-code` and for `--safe-delete`'s `dead_code_candidate=`, and four skills that asserted the
confidence in prose all say the same thing now. `test/deadprecisioncheck.sh` asserts the attribute is
absent — the arm that used to pin the bug.

### Fixed — `reuse-decline` fired on clone groups `duplication` already exempts

`reportReusedClones` (kind `new-clone-of-reused-helper`) reads the same clone vectors as its sibling
`reportNewClones` (kind `duplication`) but carried neither of that sibling's two demotions: the
all-test-script skip, which exempts a group of sibling gate scripts repeating the house harness
boilerplate by convention, and the idiom→minor demotion. So a shell gate script cloning the house test
helper was exempt as `duplication` and gating as `reuse-decline`, from the same input — and that shape is
where the kind's one real-history firing came from. Both demotions are now applied identically in both
reporters.

### Fixed — a Java or Kotlin `import` is a dependency edge, not a call

`queries/java/tags.scm` and `queries/kotlin/tags.scm` captured an `import_declaration`/`import_header` as
`@reference.call`. That was inert while nothing owned a reference written outside every named definition;
once a top-level statement gained a `<file-scope>` owner (#60), an import line minted a real caller edge
and inflated `--callers=`/`--impact=` fan-in by one phantom caller per importing file. Both queries now
capture `@reference.import`, which routes to the existing `RefRole::Import` the C++ `using ns::name;` form
already used: the import stays fully visible on `--uses` as a `role="import"` use-site, and is excluded from
the call-graph CSR. No new C++ — the two query files are the whole change. `kParserVer` moves 118 → 119, so
any cache written by an earlier binary is refused and reparsed. Every other indexed language was checked:
Java and Kotlin were the only two that captured an import-shaped construct as a call.

A .kt file has no executable top level, so with this the Kotlin fixture correctly carries **no** module-scope
owner at all; `test/kotlincheck.sh` §1a pins that whole chain — no owner minted, the import still visible
with `role="import"`, and `square`'s fan-in counting real functions only.

### Fixed — unseeded `--slice-flow=both` now says that it adds nothing the flat rows do not

Unioned over a function's whole variable inventory, `--slice-flow=both`'s reach is byte-identical to the
union of the flat rows, which holds by construction: every flow row at depth ≥ 1 lands on an occurrence of
some other sliceable local, and that is already a row of *that* local's flat slice. Seeded with `--at=`, the
same analysis adds real reach. The unseeded case is not refused — the answer it returns is correct, just no
more informative — it is **disclosed**: the `<slice>` root carries `flow_redundant="1"` exactly when
`--slice-flow=both` runs with no `--at=` seed, never on `back`/`fwd` alone and never on a seeded run, with
one line in the legend pointing at the seed.

### Fixed — a call written outside every named function now has a caller, so `callers`, `impact`, `affected` and `test-gate` stop answering one short (#60)

A reference was attributed to the innermost definition whose span contains it, so a call written where no
definition reaches — a module top-level statement, or a call inside an anonymous callback body — had no
caller at all. No edge was minted, and the four verbs that walk those edges each answered short: `--affected`
could report `tests="0"` for a source file a passing test genuinely exercises, and `--callers` could report
`count="0"` for a function that framework registration, DI wiring or route setup calls at module scope.

Measured before the change with `--pin-census`, as the share of call sites with no caller node: **72.8% of
vue-core**, 54.8% of this repository, 1.6% of django, 1.0% of llvm-project. On a TypeScript corpus this was
the majority of the call graph.

Ingest now mints one **module-scope owner** per file that holds such a call, over exactly the population the
resolver counts as a call, so the two cannot disagree about what a call is. It is labelled rather than
disguised — `t="modscope"`, named `<file-scope>`, a caller that nothing can name and so never a callee, with
no body: `--expand` on one answers `bodyless="1" capped="0"` rather than serving the file. Every legend that
can show the kind defines it, in the full and compact dialects alike, and only when a row is actually
present. The fix is language-neutral: twelve indexed languages were measured to carry the defect, and all
twelve take the same path. Two gaps are stated rather than fixed, because they are upstream: a Ruby bare-word
call without parentheses and a C# top-level-statements call produce no call reference to own.

What a reader will notice: `--callers`/`--impact`/`--affected` counts rise where such calls exist; a
`--uses` row for a file-scope call gains `in_id=<file-scope>`; the call graph gains edges (+14% on this
repository); and the map header's `unresolved=` rises — on shell-heavy trees substantially (5,370 → 12,232
here) — because calls that used to vanish into an ungauged bucket are now counted by the resolver gauges
they always belonged to. Node count grows 0.3–4.3% depending on corpus, so every `k=` rank shifts slightly.

Reported by **@YogevKr** in #60: a passing `node:test` test calls an imported function from an arrow
callback and `--affected` reports zero tests, while moving the assertion into a named function restores
detection. **@alex-michaud** added the arm that made a callback-only fix insufficient — the same root cause
drops `--callers` and `--impact` edges for a module top-level call in ordinary production code, with no test
file and no test framework anywhere in the tree.

### Added — the legend once per session, so an agent stops paying for the same definitions on every call

Every XML answer carried its own legend, so an agent making repeated calls in one session bought the same
definitions again and again — and it bought them **before** the rows, which is exactly the part it has to read
past to reach the answer. An MCP session can now be served each definition once.

- **The dictionary is an MCP resource.** `initialize` declares `resources`, `resources/list` names
  `ripwire://legend-dict` (a small core: how to read `<about>`, `schema=`, the paging window, the `*_capped`
  readings) and `ripwire://legend-dict/full` (everything). Reading the core once is what switches the session
  on; a host that cannot read resources never switches, and every answer stays inline. Measured on this
  repository: the core is 1,094 B, and `initialize`'s instructions grow 508 → 856 B to point at it.
- **The `ref` posture.** After that read, an answer lists its rows first, carries a definition only the first
  time this session meets it — in a comment **after** the rows — and ends with
  `<about … legend="ref" dict= dictv=/>` as its last child, where `dictv=` is the dictionary version those
  definitions came from. Nothing is dropped: a ref answer carries the same attributes and the same rows as the
  inline answer it replaces, and it is never longer than that answer — if it would be, the inline answer is
  served unchanged. Measured on this repository, `impact` on `compactLegendText`: 3,386 B inline, 2,571 B
  on the second call of a switched session (−24.1%), with the bytes before the first row falling 78 → 8.
- **`--legend-dict[=roster]`** prints the same dictionary on the CLI — one definition per line, headed by its
  `dictv=`; `=roster` lists the completeness attributes it defines, as attribute/element/source rows. It is
  answered wherever it appears on the command line and nothing else runs. On this build the dictionary is
  68,316 B over 702 entries and the roster is 602 rows; a session receives only the entries its own answers
  used, not the whole thing.
- **`--legend=ref` refuses on the CLI**, naming the resource and `--legend-dict`. A CLI run is a single answer
  with no session to have been served anything, so a ref answer there would point its reader at definitions
  that reader never received. CLI output is otherwise unchanged by this work.

This amends guardrail **G4**, which said the legend is emitted once at the top of an answer: it is now once per
answer on the CLI and once per session on the agent surfaces. `CLAUDE.md` and `CONTRIBUTING.md` carry the new
wording and name the gates that hold it — `legendcoveragecheck` (G) and `compactlegendcheck` (UG) for the
default posture, `legendrefcheck` for the ref posture.

### Fixed — `--quality-delta` on a tree that is already HEAD stops reporting phantom debt

`--quality-delta` built its HEAD side by archiving the commit into a temp directory and re-ingesting it. That
tree is a different **population** from the working tree, and a dead-code verdict is a property of the whole
population — so a file present on only one side moved the verdict of a symbol in a file both sides shared. On a
working tree identical to HEAD, with untracked directories present, **@hnipps** saw 58 gating
`preexisting-worse` dead-code rows and exit 2 on a Python monolith of ~7,100 tracked files (#228) — every row
in a test file nobody had touched — and `--quality-baseline` then refused to pin a floor over that same
phantom debt, so the documented escape hatch was unavailable exactly where it was needed. The case that makes
it matter is the one reported: the exit code is meant to be a pre-commit gate, and a gate that fires on a
clean tree cannot be used.

When the tracked tree already **is** HEAD, ripwire now stops materializing a second tree: the baseline is this
tree's own snapshot, so the comparison is a snapshot against itself and no regression can exist in it. Files the
tree holds that HEAD does not track — untracked files, an untracked nested repository, a checked-out submodule —
stay in the crawl and in the graph, but not in the baseline, so their own debt is still reported as `new-symbol`
exactly as before, and the count is stated on stderr. The CLI delta, the CLI `--quality-baseline` pin and the MCP
`quality_delta` verb all take the same basis, through one function.

Measured on a nine-file fixture whose working tree is identical to HEAD, gating rows before → after: an untracked
directory 1 → 0, an untracked nested repository 2 → 0, a tracked file marked `export-ignore` 1 → 0, `--no-ignore`
over a gitignored same-named definition 1 → 0 — exit 2 → 0 in each. A shallow clone read zero both before and
after; it was a bystander in the report. A real edit that deletes a function's only caller still gates exactly one
dead-code row in the hardest of those shapes. New arms in `test/qualitycheck.sh` pin the invariant, its
sensitivity controls and its determinism across cold, warm and a fresh temp directory.

**Two checkout shapes are NOT fixed, and the answer says so rather than implying otherwise.** A tracked path
carrying `git update-index --skip-worktree` or `--assume-unchanged` hides its own bytes from git, so the
identity basis cannot be trusted over it and is refused: that tree takes the archived comparison and keeps
gating. For a hidden **edit** that is the right answer — the change is real, only concealed — and for a
**sparse checkout** it is a known gap: the archived tree is not sparse-aware, so an excluded caller can still
gate a phantom row. Both cases now name the basis on the root, `head_basis="archived-index-hidden"`, instead of
leaving a reader to guess why the fast path vanished; `head_basis="identity"` marks the answers above, and its
absence is the ordinary archived comparison. Closing the sparse gap is follow-on work, tracked with the rest of
the archived-path population problem below.

A tree that carries tracked **modifications** still takes the archived-HEAD path, so a population difference can
still move a verdict there; `prompts/help-wanted/quality-delta-unchanged-tree-zero.md` is where that follow-on
lives.

### Fixed — the MCP `for` bundle defines `at=`, `ccx=` and `next=`, which it was already emitting

`for`'s bundle writes its own legend rather than going through the compact composer, and three attributes it
carries had no reading anywhere in it: `at=` on the root, `ccx=` and `next=` on its rows. A reader had to guess
them. Any native-legend answer carrying a completeness attribute its own legend never spells now gets that
attribute's compact reading, in one comment, before the answer is priced — so the next one is defined on
arrival rather than found later. Rows are byte-identical; the legend grows 55–115 B.

### Added — `affected` and `rank_by` over MCP, so an agent can ask which tests to run and re-rank the map without leaving the server

The MCP server exposed 31 tools and neither of these two, so an agent mid-task had to shell out to the CLI for
"which tests reach what I just changed" and for a second ranking of the same graph. It now exposes 33.
Both serve the CLI's own renderer rather than a second implementation of it:

- **`affected`** — the twin of `--affected=F1,F2|SYM`. `--affected`'s resolve-and-render body moved out of the
  CLI arm into `testmap.h::writeAffectedReport`, which both surfaces now call; the CLI arm is a wrapper that
  adds its own stderr wording on the two failure returns. The payload is byte-identical to the CLI's at the
  same legend posture, modulo `root=` (`.` on a relative CLI invocation against the absolute MCP `path`) —
  measured on this repository over four selectors and three postures.
- **`rank_by`** — the twin of `--rank-by=pagerank|authority|hub|rrf`, through the same `serialize()` call
  `analyze` uses, varying the rank vector alone. `churn` and `churn-decay` are refused **by name**, with the
  CLI command that answers them, rather than read as an unknown value or quietly served as `pagerank`: they
  mine git history through the CLI's parsed-argument path, which this server does not build.

Both declare `legend`, so they take their posture per request like the rest of the family — absent means
compact, `legend:"full"` restores the prose legend byte-for-byte, and the rows do not move between the two.
The `tools/list` manifest grows 43,500 → 46,493 B (method: `test/mcpmanifestcheck.sh`'s own formula — the
compact JSON length of the served `tools` array — over one `tools/list` response on this repository's binary
before and after; its 46,600 B ceiling is unmoved, with 107 B of headroom — the 46,371 B this entry first
recorded was superseded, same round, by a `rank_by` description fix (`test/mcpmanifestcheck.sh`'s own
RE-ANCHORED/TRAIN 10 FIX ROUND comment history), and this prose copy went uncorrected for five days before
being re-derived by hand; `test/mcpmanifestcheck.sh` arm `(1b)` now asserts this figure against a live
`tools/list` measurement so that rot is a gate failure, not a future rediscovery).

### Fixed — `rank_by` over MCP no longer answers a different ranking than `--rank-by` on a tree with uncommitted changes

The warm MCP index caches a rank vector that is deliberately personalized toward the uncommitted diff, which is
right for `analyze` and wrong for a verb whose CLI twin runs an unbiased `rankGraph`. Reusing it made
`rank_by` diverge from `--rank-by` on any dirty tree — same document size, different bytes, so nothing that
compared lengths would have seen it. `rank_by` now computes a fresh unpersonalized rank unconditionally.
Measured on this repository with two tracked files edited and uncommitted: the personalization really is live
(`analyze` converges in 27 power iterations against the CLI map's 37), and all four `rank_by` modes are
byte-identical to their CLI twins in every posture on that same tree.

### Fixed — `--affected` declares its root when a repeated root argument leaves only one

`ripwire DIR DIR --affected=…` drops the duplicate and indexes one root — the crawl says so on stderr — but
`--affected`'s single-root test counted the roots as *typed* rather than the roots that survived. The report
then omitted `root=` while the runner index, which reads the deduplicated corpus, went on spelling `run=`
relative to that root: a relative command in a document giving the reader no anchor for it. The test now
reads the deduplicated corpus, which is the predicate `--situ` and the MCP twin already used, and the answer
to `DIR DIR` is byte-identical to the answer to `DIR`. A genuinely multi-root run is unchanged: it still
keeps absolute commands and declares no root. The runner index is now also given a root only when the
document declares one, so the two cannot disagree whatever a caller asks for.

### Fixed — an MCP `rank_by` sent as an empty string is refused instead of read as the default

`rank_by:""` was treated as an omitted field and answered `pagerank`, where the CLI's own `--rank-by=`
refuses with `unknown value ''`. A schema default applies to a field that is absent, not to one that is
present and outside the closed set. The two are now told apart by the same presence reader `sections` and
`legend` use, and a present-but-empty value gets the closed-set refusal with the CLI's wording. Omitting
`rank_by` still answers `pagerank`, byte for byte.

### Fixed — an MCP call that omits a required `files` argument is told which argument is missing

The generic missing-required-field composer had no case for `files`, so it could not tell the field was absent
and fell through to the unknown-tool path — which answered with the tool's own name as the thing it did not
recognise. `affected` is the first tool whose required argument is `files`, which is where this surfaced.
`affected` with no arguments now refuses with `-32602` and names the field and what it wants.

### Changed — the CLI's default legend is compact; `--legend=full` restores the prose legend

Every XML answer now leads with the compact legend unless `--legend=full` is passed — `--for` included, whose
own `ripwire.for/v1` header is its compact dialect. The compact legend defines every attribute the answer
carries — each verb's purpose, the completeness vocabulary (`counts_floor=`, `shown=`/`total=`/`capped=`, the
paging window, `est_tokens=`, `over_ceiling=`, the resolver gauges …) and every descriptive or cut attribute
(`renames_window_truncated=`, `script_gates_unmodelled=`, `hcut=`/`rcut=`, …), each reading present only where
the answer carries it. The full prose, which used to be the default, is one flag away and byte-identical to what
0.6.1 printed without it. Rows never change between the two, with one chosen exception: `--expand` serves the
bundle or the whole file by whichever the posture DELIVERS cheaper, so the two postures can serve different ones. The MCP server has defaulted to compact since
0.4.0, so both surfaces now agree. Measured on this repository: `--callers` 6,305 → 3,212 B, `--edit-check`
9,750 → 3,313 B, `--affected=src/cli.h` 2,103 → 1,234 B, `--for` 10,010 → 9,117 B (method: the same argv,
`--legend=full` against this default, `wc -c`).

What else moved with it, because a default has to be honest where an opt-in could be terse:

- **Nothing the default prints is undefined, and nothing it drops is a disclosure.** `--from-trace` keeps the
  ceiling it applied (`<!-- ledger: budget=N bytes (allowance M bytes …) -->`), `--notes` keeps its
  `notes= targets= dangling=` counts, `--pack-task` keeps its budget ledger, and the withheld-map record reads
  as a withheld map.
- **A compacted answer is priced at the bytes it delivers, and trimmed at that price.** `est_tokens=` used to
  keep the full legend's price after compaction (`--connect` here: 1,200 tokens for 1,037 bytes); it is now
  moved by the removed bytes at the document's own rate. `over_ceiling="1"` and `--pr-context`'s
  `budget-floor-exceeded` follow the repriced number, the flagless map's `--token-budget` gate decides on the
  compact price, and `--pr-context`, `--pack-task`, `--from-trace` and `--expand`'s serving choice decide their
  cuts on the price the answer will print — `--pr-context` at `--token-budget=4000` here kept 22 changed files
  where it had kept 10, with the same budget.
- **`--for` under `--token-budget` never loses a row `--legend=full` keeps.** Its compact sig ledger subtracted
  the full dialect's enrichment clause (~450 B the compact header never carried); the charge is now capped at
  the full dialect's. Re-measured over 66 budgets (300..3550 step 50) on a 72- and a 12-function fixture: the
  default lands over its budget on 15 and 15, `--legend=full` on 11 and 12; every overshoot is labelled
  `over_ceiling="1"`.
- **Nothing the default cannot shape fails because of it.** A run whose answer has no XML legend passes through
  unchanged. `--legend=full` is accepted, as a no-op, by the read answers that only have the full form (`--situ`,
  `--recall`, `--report`, `--mermaid`, `--html`, `--plan-lanes`, `--sarif`, `--eval*`); an asked
  `--legend=compact` still refuses there, and the writers and servers refuse either. `--pin-census` takes a
  posture (its map is the answer). The servers (`--mcp`, `--listen`, `--lsp`) and `--json` keep no default.
- `--help` now promises "at least 40%" of a small `--callers`/`--uses`/`--impact`/`--affected` answer saved by
  the compact legend, down from 45%: the definitions it gained cost `--affected` four points (41% measured).
- `--query`'s `<!-- routed: … -->` note is kept where the root carries no `route=`; the router's generated
  commands no longer append `--legend=compact`; the prompt-route hooks read `status=` as an attribute, so they
  route under either root attribute order.

Scripts that parse the full legend's prose, or match a root's first attribute byte for byte, should pass
`--legend=full`.

### Added — `--for` lists a named file's one declaration/implementation partner first, and `--situ` puts partners before the blast radius

When a `--for` task names a path that resolves to exactly one indexed file, and that file has exactly one
same-directory, same-stem declaration/implementation partner (a source tries `.h`/`.hpp`/`.hh`; a header tries
`.cc`/`.cpp`/`.c`), the answer now opens with `<hdr p="partner" of="named"/>`, right after the legend. It is a
lookup by name, not a ranked or graph-derived row: an ambiguous, absent or convention-less named file gets no row
and no reordering, and a partner the task already names is not repeated. The row's legend clause is present only
when a row is, and is never dropped by the ceiling ladder. The MCP `for` verb serves the same row from the same
resolver. The rows are counted in `est_tokens=`, in `over_ceiling=` and in the `--token-budget` ceiling like every
other section, and they do not take space from the ranked signatures. `--situ` now prints its decl/def-partner and
lexical-sibling blocks before the `[1] blast radius` line instead of after it; the lines themselves are unchanged,
only their order. Gates: `test/forhdrshapecheck.sh` (new), `test/situshapecheck.sh` arm (13),
`test/estchargecheck.sh` #19.

### Changed — `--for` collapses a `<lego>`/`<compose>` section to a counted stub when the stub is smaller

A `<lego>` or `<compose>` section in a `--for` answer is now replaced by a counted stub,
`<lego total="N" shown="0" capped="1" next="…"/>`, but only when the stub plus its legend clause is smaller than the section
it replaces; a small section stays whole. `total=` is the section's own pre-cap row count, and `next=` names the
new `--sections=lego,compose` flag, which restores both sections byte-identically in one call. The legend clause
is present only when a section was actually stubbed, in both legend dialects and on the MCP `for` verb
(`sections` argument). An empty value, a trailing comma or an empty segment (`lego,`) is refused rather than read
as a shorter list, on both surfaces. When the in-memory render that prices the section is unavailable, the section
is emitted whole, because nothing shows that the stub would be smaller. Gate: `test/forsectioncollapsecheck.sh` (new).

### Fixed — a `.ripwire_notes` file that could not be fully read looked the same as no notes file

A sidecar with unparseable lines, or one refused because it is a symlink, was disclosed only by `--notes`
itself (`lines_skipped=`/`refused=`). Every other reader answered as if the tree had no notes file at all. The
map, `--expand` (including whole-file and `--top-k=0`), `--for` and `--pack-task` (XML and `--json`),
`--edit-check`, `--handoff`, `--plan-lanes`, and the MCP `for`/`pack_task`/`from_trace`/`fetch_body` verbs now
carry `notes_degraded="1"` (`"notes_degraded":true` in JSON) with a legend clause. The marker is absent on a
clean read, so output for a tree with no sidecar, or one that fully parses, is unchanged. Gate:
`test/notesdegradecheck.sh` (new). (CodeRabbit review on #295)

### Fixed — a JSX tag starting with `_`/`$` lost its call edge, treated as an intrinsic HTML/SVG tag

`isJsxIntrinsicTagIdentifier` (the filter that keeps `<div>`/`<h1>` from minting a phantom call edge to a
symbol that is never defined) tested `!( c >= 'A' && c <= 'Z' )` — every non-uppercase-first-letter tag
counted as intrinsic, so `<_Widget/>` and `<$Widget/>` (both legal, non-lowercase leading characters for a
JS/TS component identifier) lost their call edge exactly like an ordinary HTML tag. The filter now tests
ASCII-lowercase directly: only `a`-`z` is intrinsic. `--callers`/`--uses`/`--affected`/`--test-gate` on such
a component now see the JSX call. kParserVer 117 → 118; a cache written before this under-counts their
callers. (CodeRabbit review on #295)

### Fixed — `--help-task` routed on "reach"/"reaches" as a plain substring, firing inside "outreach"/"unreachable"

The reach-flow router (`--help-task`'s "how does A reach B" shape) scored its single-word "reach"/"reaches"
cues with the same substring matcher its multi-word phrase cues use, so "reach" fired inside "outreach" and
"unreachable", and "reaches" scored both cues at once (10 points from one word). A task naming two indexed
files, an unrelated "reach"-containing word, and one cheap phrase cue ("how does") could cross the routing
threshold and wrongly recommend `--for=task`. The two single-word cues now match word-bounded instead.
(CodeRabbit review on #295)

### Fixed — merge-scout refused a legal empty ingest as an unavailable tree, and never said why

A `--merge-scout` arm whose base ingested zero files — a fresh root commit, a base whose every path is
excluded, or one with no file of a supported extension — was refused as `ok="0"` (unavailable tree), the same
answer a real failure gets, and the same check marked `head_conflicts_ok="0"` for it too. The cause was
upstream: `materializeCommitTree` piped `git archive` into `tar -x`, so the pipeline reported only `tar`'s
exit status, which is 0 on an empty stream whether the tree was genuinely empty or `git archive` failed and
piped nothing. It now archives to a file and extracts that file as a second command, so an archive failure and
an extract failure are each reported from the exit code of the command that had it. With materialize
trustworthy, a verified-successful materialize whose ingest is empty becomes a real, indexed, empty tree and
the arm compares normally. When an arm is still refused, the root carries `reason="no_merge_base"` or
`reason="tree_unavailable"` — present only when `ok="0"`, and written in every build flavour, not only in a
debug trace. Both `ok=` postures and `reason=` are defined in the legend. Gates:
`test/scoutheadconflictcheck.sh` arms T9(a)–(e), `test/mergescoutcheck.sh`. (CodeRabbit review on #295)

### Fixed — sixteen gates now share one GNU/BSD `stat` compat helper instead of a per-gate copy

`stat -f` is GNU coreutils' filesystem-stat flag, not BSD's format-string flag, so it succeeds with junk
instead of failing — a caller-local `stat -f ... || stat -c ...` one-liner never reaches its own fallback on
Linux. Sixteen gates each hand-rolled the same detect-once-and-redefine fix independently:
`cachehashcheck.sh`, `cachesplitcheck.sh`, `clonecachecheck.sh`, `codexpromptroutecheck.sh`,
`evictioncheck.sh`, `g1freshcheck.sh`, `headsnapcachecheck.sh`, `mcpeditmodecheck.sh`,
`portablecachecheck.sh`, `prcontextcheck.sh`, `qsnapcachecheck.sh`, `qsnapprefetchcheck.sh`,
`statgatecheck.sh`, `cacheisolationcheck.sh`, `qsnapproducercheck.sh`, `sidecarsymlinkcheck.sh` and
`tempfilesymlinkcheck.sh` all now source the new shared `test/lib/statcompat.sh` instead — one place defines
the GNU-vs-BSD `stat` compat logic, not seventeen. Centralised by **@s0undt3ch** in #298.

### Fixed — a gate that builds a throwaway git repository could be aimed at the caller's repository instead

`git -C DIR` changes the working directory; it does not override the environment, and `GIT_DIR`,
`GIT_WORK_TREE`, `GIT_COMMON_DIR`, `GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY`,
`GIT_ALTERNATE_OBJECT_DIRECTORIES` and `GIT_PREFIX` all outrank it. A gate that builds a fixture repo and
asks it a question therefore answered from somebody else's repository whenever one of those was exported —
by a git hook running the suite, a CI job, or a `git rebase` running the suite per commit — and then
passed or failed on data it never
selected. Measured at the reported call shape: with `GIT_DIR` set, `git -C "$REPO" init` created no `.git`
under `$REPO` at all, the gate's own commit landed **in the ambient repository**, and `git -C "$REPO"
rev-parse HEAD` read that foreign sha back, with the gate still reporting ALL PASS. The clearing joins the
agent-home names in the shared `test/lib/clean-env.sh` rather than becoming a 156th call-site copy: **155
gates** build a repo and were exposed, and the two that had already found this independently
(`dispatchordercheck.sh`, `pagingsweepcheck.sh`) had hand-rolled partial lists that each missed names the
other had. New gate `test/gitenvhermeticcheck.sh` proves the defect is live on this git, proves the helper
fixes it, pins the variable list against the helper, and sweeps the tree for a repo-building gate that does
not source it — with a control that strips the source line from a real gate and requires the sweep to flag
the copy. (CodeRabbit review on the train-13 branch)

### Fixed — a gate that varies `HOME=` per invocation could still leak into an ambiently-set agent-home variable

`CODEX_HOME`/`AGENTS_HOME`/`HERMES_HOME`/`CLAUDE_CONFIG_DIR`/`RIPWIRE_DATA_HOME` override the default an
agent's tools derive from `HOME`, so a gate that only sets `HOME=` per invocation is not actually sandboxed
on a machine where any of these is already exported ambiently. `codexpromptroutecheck.sh`,
`claudeconfigdircheck.sh`, `skillinstallcheck.sh` and `hermesinstallcheck.sh` now source the new shared
`test/lib/clean-env.sh` before varying `HOME=`, closing that leak in each. `claudeconfigdircheck.sh` — the
gate that exists specifically to test `CLAUDE_CONFIG_DIR` relocation — was the one this hit hardest: with
`CLAUDE_CONFIG_DIR` exported ambiently (a developer whose real Claude Code config is relocated, exactly the
case this gate tests for), its "unset" baseline arm wrote real files into that directory and then failed
comparing against its own contaminated baseline. Found and closed by **@s0undt3ch** in #298; carrying the
same shape through the rest of the suite closed six more — `hookcheck.sh`, `routehookcheck.sh`,
`agenttablecheck.sh`, `codexinstallhonestycheck.sh`, `meterdisclosurecheck.sh` and `releaseinstallcheck.sh`.

### Added — the advertised MCP verb roster is pinned by deriving it, so a count-preserving rename cannot slip through

`test/mcpverbscheck.sh` checked that `tools/list` advertises the expected *number* of verbs, which a rename
that swaps one name for another passes unchanged — and a renamed verb is a silently broken contract for every
agent that had wired up the old name. The gate now derives the roster from a live `tools/list` call and
compares the **names**, all 33 of them. Proved against the mutation it exists for: planting an added verb, a
removed verb and a count-preserving rename in the served stanza all redden the new arm, and the rename case
leaves the old count-only check green — which is the gap. Contributed by **@pt-act** in #291.

### Fixed — two documentation claims that described behaviour the binary does not have

`--expand=SYM` on an ambiguous name was documented without the scoping the disclosed `topk_default="0"`
actually applies, and the directory-of-repos row described a guard that does not exist, where the real
behaviour is a silent merge. Both corrected in `README.md` and in the `ripwire-navigate` and `ripwire-orient`
skills, against a built binary rather than from reading the source. Contributed by **@llvm-x86** in #302,
who built the Flask fixture that found them.

### Added — native Windows x64 (clang-cl, MSVC ABI), behind `src/infra/os.h` — thanks to @lennix1337 (#44)

@lennix1337 ported ripwire to native Windows in #44 and then kept it alive through weeks of a moving main: UTF-8
and long paths end to end, the no-follow sidecar opens against symlinks, junctions and OneDrive placeholders,
`--run-trace` children inside a Job Object so a timeout ends the whole tree, Git Bash script bridges so `cmd.exe`
never expands a `%`, the `LockFileEx` edit lock their race trials proved, the MCP directory watcher, the
PATH/PATHEXT search, and an owner-and-Administrators ACL for the cache directory — plus a local validation run of
the Windows gates on their own machine, and a snapshot (`win32-port-snapshot`) with the fixes that run turned up.
Their commits are in this history as they wrote them.

This release carries that work in the shape `os.h` set out: every Windows body is in
`src/infra/os_win32.cpp` (the one translation unit that sees `<windows.h>`), declared by `os.h`'s Windows branch
under the same POSIX names call sites already spell, and every piece of it that is not a Win32 call — the
Win32→errno table, UTF-8/UTF-16, `CreateProcessW` quoting (adapted from libuv, notice in `THIRD_PARTY.md`),
reparse-tag and wait-status decoding — is in `src/infra/os_win32_logic.h`, which every Linux and macOS leg now
compiles and tests (`test/oswin32logiccheck.sh`: 29 cases, 4,480,667 assertions, a sanitizer arm and a mutant arm
that must fail). A Windows build adds only `cmake/Windows.cmake`: `os_win32.cpp`, a manifest (`longPathAware`,
UTF-8 active code page), `ws2_32`/`advapi32`/`shell32`, `/EHsc`. No force-include, no compat headers, no
libc-renaming macros.

Linux and macOS pay nothing for it. Measured on macOS arm64, Release, this branch against main `e54b688e`: no
`rw::os` symbol in either binary, identical symbol sets (11,021), `__text` 9,172,004 B in both, and of 5,034
functions 5,031 disassemble identically and 3 differ only by the build stamps (the source-identity hash in the
quality snapshot's two serializers, the `built_from` length in `--doctor`). The same 71 cases the `os.h` refresh
used (map, 25 verbs, `--run-trace`, MCP stdio and `--listen`, the sidecar and index writes) are byte-identical.

Since proven on Windows, and exactly that far. @lennix1337's run against the D3 branch found five build failures, all fixed; a `windows-latest` CI job now builds with clang-cl and smoke-tests the result on every full matrix — configure, build, `ctest` (including the port's own `oswin32logiccheck` target), `--version`/`--help`, a real crawl of `test/fixture`, the two-run byte-identical determinism contract, well-formed XML, and the ASan flavour compiling. What is NOT proven: the gate suite does not run on Windows (it needs the harness), no sanitizer RUN happens there, and nothing exercises a UNC share, a junction, a non-ASCII path or a volume without a drive letter — the checklist on #44 is still open. MSVC `cl.exe` now builds too. The GCC/Clang language extensions the tree is written in go through a seam in `src/infra/platform.h` — and, for the layer below it that cannot include it, `src/infra/Diagnostics.h` §1c — so both front ends run the same CI steps and both gate. `test/osswitchcheck.sh` arm H refuses a new `__builtin_*`, inline asm or `__attribute__` outside that pair, which makes a Windows-breaking change fail on every POSIX leg instead of on Windows. The same caveats still apply to both compilers: the gate suite does not run on Windows, and ASan is compiled there but never executed.

A review pass (no Windows machine, read plus a macOS/Linux-provable subset) found one MED and five LOWs, none
touching POSIX; this fix round closes the MED and three of the LOWs, still on top of @lennix1337's work:

- Paths past ~260 characters now get the `\\?\` extended-length prefix (`NativePath`, reusing the existing
  `extendedLengthPath` helper behind a length threshold, `os_win32.cpp`/`os_win32_logic.h`): without it, a file
  deeper than that on a default-policy Windows (`LongPathsEnabled=0`) failed `CreateFileW` with
  `ERROR_PATH_NOT_FOUND` — `ENOENT` for a file that exists — and the crawl or sidecar silently skipped it.
- `ERROR_IO_PENDING` (997) now maps to `EWOULDBLOCK` in the Win32→errno table, alongside `ERROR_LOCK_VIOLATION`
  (33), as a defence for the edit-lock contention loop.
- `getline`'s buffer growth no longer reads `*capacity` while `*line` is `NULL` (POSIX ignores it in that case).
- The `stat_t::st_ino` comment now says what the code does (`BY_HANDLE_FILE_INFORMATION`'s 64-bit file index; a
  ReFS/DevDrive volume's 128-bit id is not queried) instead of describing a fold that never happens.
- `--in=`, `--doc-drift=` and `--exclude=` join the path-valued flags normalized at intake (`--scope=`, a glob
  set, and `--layout=`, a type name, deliberately do not).
- `--doctor`'s binary-path row is marked `degraded="1"` on Windows (Git Bash's MSYS `which` never prints
  `.exe`, so the row's file comparison can disagree with a correct install) rather than left to read as a false
  mismatch; POSIX is unaffected. The honest fix — a native `os::which` PATH/PATHEXT search — is a follow-up.
- `openat`'s handle-anchored join (kept as-is this release, not `NtCreateFile`) now documents its residual: the
  final `CreateFileW` re-walks a freshly built path string, so a link swapped in above the anchored directory in
  that narrow window is followed, unlike a true handle-relative open.

Left for a contributor's own Windows run (checklist in the coordination history): MSYS bash re-parsing
`spawn_sh`'s command line, and `openat` on a volume mounted without a drive letter.

### Fixed — an ambiguous `--expand` buried its body behind the ranked map, and the escape hatch was stderr-only

Reported by @mariadb-KyleHutchinson in #289: `--expand=SYM` on a name matching more than one definition, in a
file over `--pack-budget-bytes`, served `mode="bundle"` — the ~200-symbol default ranked map, then the
requested `<bodies>`. On a real ambiguous name (`--expand=write` on this repo's own source) the body landed
86% into the document, and the existing `--top-k=0` escape hatch ("the ranked map rides along... add
--top-k=0 for the bodies alone") was stderr-only, invisible to a caller reading only stdout. When the map
rides along WITHOUT an explicit `--top-k` (the caller never asked for it, `chooseExpandServe` picked bundle
mode on its own), the requested bodies are now served before the map, and the escape hatch also rides the
document itself, as a `note=` attribute on the `<ctx>` root (stderr keeps its own copy, for a human tailing
the terminal). An explicit `--top-k=N`, on a unique or an ambiguous name alike, is unaffected: it keeps the
pre-existing order and carries no `note=`, exactly as `--help=--expand` already promises.

### Added — a TS/JS import spelled with a `.jsx` runtime extension, or naming only a `.d.ts`/`.d.mts`/`.d.cts` declaration, now resolves

`kJsRuntimeSourceExts` (the one runtime→source table `resolveTsImport`'s precise include tier and graph.h's
named-import binder both read) covered `.js`→`.ts`/`.tsx`, `.mjs`→`.mts` and `.cjs`→`.cts`, but not `.jsx` or the
declaration-only case: a specifier naming a file that exists only as a hand-written `.d.ts` (no `.ts`/`.tsx`
alongside it) stayed unresolved, and neither the CLI's `--deps` edge nor the named-import call binder saw it. Two
additions, both matched against tsc 7.0.2's own resolver (verified against tsc's `traceResolution` diagnostic output, node16/nodenext/bundler identical):
a `.jsx` row (`./x.jsx` tries `.tsx` then `.ts`), and a second, DECLARATION tier per runtime extension
(`.js`→`.d.ts`, `.mjs`→`.d.mts`, `.cjs`→`.d.cts`) tried only when the source tier finds nothing — `./both.js` with
both `both.ts` and `both.d.ts` on disk still resolves to the source, the declaration untouched, matching tsc
exactly. The pre-existing unique-or-degrade rule for two real SOURCE candidates (e.g. both `x.ts` and `x.tsx`
present) is unchanged and applies identically to the new `.jsx` row — a deliberate, already-shipped conservative
choice, not something this change revisits. `test/tsimportprecisecheck.sh`'s RUNTIME-EXTENSION section gains the
`.jsx` rows, a `.jsx` source-clash decoy, the three declaration-fallback rows, and a source-vs-declaration
precedence row. Split out of PR #44 (native Windows port); the shared runtime→source table is
@lennix1337's, this change completes its coverage.

### Fixed — an edit could be reported "applied" while a concurrent writer silently undid it

The per-file advisory edit lock tried the lock for ~200 ms and then always proceeded lock-free once it gave up
— including when a live cooperating writer was still holding it. That writer could commit its own change after
this edit's rename, so the edit was reported `applied` for bytes that no longer existed on disk. The lock now
distinguishes *why* it never got in: only when every bounded attempt saw `EWOULDBLOCK` — another writer proven
live and holding it — does the edit refuse (`-32603`, "edit lock unavailable ... file left unchanged") instead of
racing it. A lockfile that cannot be opened, or a filesystem with no `flock`, proves no live holder and keeps
the existing lock-free degrade; refusing there would block every edit on such a machine without serializing
anything. `test/mcpeditracecheck.sh` arm F1b takes the lock from a separate process first and proves both the
refusal and that the same edit applies once the holder releases. Split out of #44 (native Windows port); the
original commit refused on every acquire failure, which this narrows to the proven-contention case. Thanks to
@lennix1337.

### Fixed — `sliceBodyLines`'s UTF-8 back-off read one byte past a slice ending on the body's last line

`--expand=SYM:START-END`'s continuation-byte back-off, which trims a split multi-byte codepoint off a slice
boundary, read `body[byteEnd]` before checking whether `byteEnd` was still inside the body. When the
requested slice's last line is the body's own final line, `byteEnd == body.size()`. Every CLI call sits the
view over a `std::string`, whose `operator[](size())` is defined to return the null terminator, so the read
stayed in-bounds by accident and no existing gate ever saw it; over any buffer that ends exactly at its own
allocation the same read is a real heap-buffer-overflow. The loop now stops at `byteEnd < body.size()` before
indexing. `test/expandrangecheck.sh` arm 11 compiles `serialize.h` into a standalone ASan/UBSan harness over
an exact-size buffer, so the read is sanitizer-catchable instead of silent. Split out of PR #44 (native
Windows port); the fix is lennix1337's.

### Fixed — `emptycorpuscheck`'s one-function arms never ran, and the gate said ALL PASS anyway

`run_and_check` named its output file after the test name with spaces stripped (`tr -d ' '`), so `"onefn:
default map"` wrote to `out_onefn:defaultmap` while the three assertions below it read `out_onefndefaultmap`
— a colon apart. Each sat behind `[ -s "$OUT_FILE" ]` with no `else`, so the file was always missing, the
block silently never ran, and the gate exited 0 having never checked that a one-function corpus's map
actually contains `symbols="1"` and the function's name, or that `--graph-query` with the `all` source term counts it. The naming
rule now keeps `[:alnum:]_` on write and read (and drops `:`, which Windows refuses in a filename anyway),
the assertion matches the header's `files=1 symbols=1` instead of a bare `symbols="1"`, and a missing or
empty output file now FAILs the block instead of skipping it.

Split out of #44 (native Windows port); the naming-rule and assertion fix is @lennix1337's. Evidence: on
origin/main, the gate exits 0 with zero `onefn: map contains …` / `onefn: --graph-query 'all' has count`
rows in its output — the content assertions for corpus (c) never print at all. Restoring the old `tr -d ' '`
rule under the new fail-closed guards FAILs both blocks (`onefn: … is missing or empty`), which is what
proves the old rule was truly vacuous rather than just differently spelled. `test/emptycorpuscheck.sh` is
the gate: on main its one-function checks never ran; with this fix they run and pass.

### Added — a JSX element invocation (`<Foo />`, `<Foo>…</Foo>`) is now a call edge in TS/TSX/JS (#285)

`--callers`/`--uses`/`--test-gate` used to read a component invoked only via JSX as having zero callers —
`<UniqueWidget />` sat in plain sight and `--callers=UniqueWidget` still answered `count="0"`, because
`queries/typescript/tags.scm` and `queries/javascript/tags.scm` captured `call_expression`/`new_expression`
only, never a JSX element name. Both query files now bind the OPENING tag's name (self-closing has no
separate closing tag; a paired element's closing tag repeats the same name and is deliberately not
captured, so one invocation mints exactly one edge) as a call reference, for a plain identifier
(`<Foo />`) and a qualified one (`<Foo.Bar />`, which binds through `member_expression` exactly like
`Foo.Bar()` and carries the same receiver). An intrinsic tag (`<div>`, `<h1>`) parses as the identical
node shape a real component's tag has — the grammar carries no case distinction — so a new capture-time
filter (`isJsxIntrinsicTagIdentifier`, `src/ingest_names.h`) drops any tag whose name does not start with
an uppercase letter; a namespaced tag (`<svg:rect />`) needs no filter at all, because its name field is a
different grammar node (`jsx_namespace_name`) that no pattern names, and a `<>…</>` fragment has no `name:`
field to capture. `.tsx` moved to its own query (`queries/tsx/tags.scm`, `querySub` `"tsx"` rather than
`"typescript"`): the plain TypeScript grammar has no JSX node types at all, and tree-sitter refuses a
whole query the moment one pattern names a node type the grammar doesn't have, so sharing the query with
the new JSX patterns would have silently dropped every `.ts` symbol and reference along with them — see
that file's header for the measurement. `kParserVer` 116 → 117. Reported by
@mariadb-KyleHutchinson in #285, with fixture files that dropped straight into `test/jsxcallfix/`
(`test/jsxcallcheck.sh` is the gate — RED on the base binary, GREEN after). **Not covered**: the issue's
secondary ask — a synthetic framework-caller edge for a Next.js App Router entry point (`page.tsx`)
invoked by file-path convention with no in-repo call site at all — is a separate, smaller follow-up and is
not part of this change.

### Changed — `lane/os-header` refreshed onto main (~1,400 commits, `30f14a27` → `57d713dd`)

`src/infra/os.h`'s POSIX seam (below) was built on v0.6.1; this refresh carries it forward onto everything main
grew since. The self-check rename (`VERIFY`/`VERIFY_TEXT` → `ASSUME`, `DEGRADED_PATH_ALERT` → `DISCLOSE`, and the
rest of the vocabulary in the entry below this one) landed on main while the branch slept, so every macro this
branch's own commits still spelled the old way is converted; `test/selfcheckcheck.sh` is the gate. Main also grew
POSIX call sites the branch predates — a tmp+rename publish RAII (`rw::pathguard::ExclTempFile`) and a
`MemoryStream` `open_memstream` holder replacing several hand-rolled buf/sz pairs, `gitCmd()`'s hardened
`--no-optional-locks -c core.fsmonitor=false` prefix in front of every git child, a `saturatingNanoseconds` fix
for stat timestamps past 2262, `docparse.h`'s FIFO-safe regular-file reader, `infra/stackthreads.h`'s
sized-stack thread pool (pthread attr/create/join — `os::pthread_attr_init/setstacksize/destroy`,
`os::pthread_create`, `os::pthread_join`, and `os::pthread_t`/`os::pthread_attr_t` added to the header), and the
LSP server's (`src/lsp.h`) root-directory resolution — each now routed through `os::` so `osswitchcheck` passes
because the call sites went through the seam, not because the allowlist widened. Dropped one unused macro
(`Diagnostics.h`'s `RW_NO_UNIQUE_ADDRESS`, an `_MSC_VER` branch with zero real call sites) rather than pull the
now-heavyweight `os.h` into a header that has to stay library-free for `noaliascheck`. `osswitchcheck`,
`selfcheckcheck`, `manifestcheck`, `gateexitcheck` and `gatecountcheck` are ALL PASS on the merged tree; three
duplication findings the merge's own restructuring surfaced (a network `send`-retry-loop and a file
`write`-retry-loop token-matching at 18/20/99 tokens — the same idiom, different syscalls, no shared helper to
call) are acked, `--quality-delta` gates 0. Plain build, `--clean-first`: 0 warnings.

### Changed — every operating-system difference lives in `src/infra/os.h`, and a gate refuses one anywhere else

Main answered "which operating system is this?" wherever a call happened to need the answer: 19 OS-conditional
preprocessor lines in 6 files, three more OS tests spelled as feature macros (`RIPWIRE_HAS_KQUEUE`, `MSG_NOSIGNAL`,
`SO_NOSIGPIPE`), POSIX system headers included by 14 files, and 250 raw POSIX/libc call sites in 34 files (counted by a
scanner that strips comments and string literals). Each was right for macOS and Linux, and none was findable except by
reading — which is what a third platform would have had to do, site by site.

`src/infra/os.h` owns all of it now: namespace `rw::os`, POSIX names, POSIX signatures and the POSIX errno contract, so
a call site reads like Unix code with a prefix — `os::lstat( path, &st )`, `os::rename( tmp, dst )`, `os::stat_t` — and
asks nothing about the platform. Each POSIX body is the libc call itself, `[[gnu::always_inline]]`, over the call's own
raw types. The few needs no POSIX call answers get a lowercase helper whose POSIX body is the code that used to sit at
the call site: `os::exepath` (`--doctor`'s own binary), `os::st_mtim`/`os::st_ctim` (Darwin's `st_mtimespec`),
`os::setsockopt_nosigpipe`, the thread identity the profiler reports, `os::dirwatch_*` (the MCP server's kqueue watcher)
and `os::spawn_sh` (the `--run-trace` child). That child keeps its fork/exec: `posix_spawn` would report three failure
paths differently — an unexecutable `/bin/sh`, an unopenable `/dev/null`, a refused `setpgid` — and no gate can reach
them to show the two equal. The Windows branch is a hard `#error` until #44 supplies its declarations there and its
bodies in `src/infra/os_win32.cpp`. The kqueue build seam is spelled `-DRW_OS_HAS_KQUEUE=0` now, because a
`src/infra/` file may not name the project.

**No behaviour change, and no cost.** A differential run of the origin/main dev binary against this branch's, over the
same checkout with a separate cache directory each, cold then warm: **71 comparisons, 71 byte-identical** — the flagless
map over `src/`, `test/`, `docs/`, the repository root and `test/fixture`; `--legend=compact`; `--token-budget` refused
and fitting; `--for`, `--callers`, `--uses`, `--expand`, `--impact`, `--grep`, `--situ`, `--quality-delta`,
`--hotspots`, `--cochange`, `--owners`, `--pr-context`, `--merge-scout`, `--whereis`, `--edit-check`, `--pack-task`,
`--recall`, `--lint`, `--notes`, `--doctor`, `--scip`, `--from-trace`; four `--run-trace` runs (exit code with stderr,
stdin from `/dev/null`, a timeout that kills a process group, a signal); `--note-add` and `--index-out` including the
bytes they write; a six-request `--mcp` stdio session; an MCP edit through the lock and the atomic write; and a
`--listen` session with a client that drops mid-request. Normalised: the binary's own path and stamp, a dev-build
alert's `__LINE__` (`main.cpp` lost seven include lines), `duration_ms`, and the index artifact's wall-clock write stamp
with the checksum over it. Release against release (`-DCMAKE_BUILD_TYPE=Release`, ThinLTO, AppleClang 21): **4,166 of
4,168 functions compile to identical instructions**; `getIndex` has the same 2,045 instructions with one two-instruction
load scheduled earlier, and `runRunTrace` lost one unreachable branch. `__TEXT,__text` is 8,671,392 B on origin/main and
8,671,388 B here, and `nm` finds no `rw::os` symbol in either build flavour. Getting there took the objdump: the first
helper shapes read `cmd.c_str()` in the parent instead of after `fork`, called `__error()` on a dead path, and — by
wrapping the kevent array in a struct — cost `getIndex` its stack protector; each shape now follows the code it
replaced. On Linux, `main.cpp`, `ingest.cpp`, `pagerank.cpp`, `tsprobe.cpp` and the profiler harness compile against
glibc 2.39 with g++ 13 and clang 22; the no-watcher path builds on a Mac with `-DRW_OS_HAS_KQUEUE=0`, links no
`kqueue`/`kevent`, passes `mcpwatchercheck`, `mcpstalecheck` and `freshnesscheck`, and answers an `--mcp` session with
the same bytes as origin/main built the same way. The ASan/UBSan build is clean over the touched paths
(`sidecarsymlinkcheck`, `mcpeditracecheck`, `runtracecheck`, `cachefuzzcheck` against it), and
`preprocdeadscalecheck` (D1)/(D2) and `recallbudgetcheck` pass their byte-identity arms against the origin/main binary.
`--quality-delta` over the branch gates on two 20-token "clones" — `os::dirwatch_poll` and `os::setsockopt` against
the profiler's one-line `sys_perf_event_open` — which are the one-line passthrough shape by design, acked with that
reason.

`test/osswitchcheck.sh` (new) refuses, outside `os.h`: an OS name in a preprocessor directive (A), an OS proxy macro or a
`__has_include` of a system header (A′), a POSIX or Windows system header (B), a raw POSIX call or type (F), and a
platform fact such as `os::kApple` or a reopened `namespace os` (G); and anywhere in `src/` or CMake, a force-include or
a compat header tree (C) and a macro or compile definition named after a libc function (D). It was red on origin/main —
A 17, A′ 8, B 41, F 275 — and on #44's head C and D red with 18 and 21 violations; its one allowlisted file is
`src/infra/profilePmc.h`, the profiler's undocumented-ABI counter backends, and a row that stops exempting anything is
itself a failure. Every arm fires on a planted fixture and stays silent on a clean one on every run. (E), POSIX/Windows
declaration parity, is present and turns itself on when the Windows branch declares its first function.
`test/namedfileinputcheck.sh`'s mechanism arm reads the `os::open` spelling. CONTRIBUTING §3 states the rule.
### Changed — the self-check macro vocabulary is renamed to the conventional spellings, and degrade paths gain a sink form

`VERIFY` / `VERIFY_TEXT` → `ASSUME`; `VERIFY_DEBUG_ONLY(_TEXT)` → `DASSERT`; `VERIFY_NOT_REACHED(_TEXT)` →
`UNREACHABLE`; `VERIFY_SAME_THREAD(_TEXT)` → `ASSUME_SAME_THREAD` (kept — multithreaded checking stays important);
`VERIFY_NO_ALIAS` / `3` / `_BUF` → `ASSUME_NO_ALIAS` / `3` / `_BUF`; `DYNMAP_VERIFY` → `DYNMAP_ASSUME`;
`TODO_IMPLEMENT` is dropped (no use sites remained). `VERIFY` read as "evaluated in release" in SerenityOS, Unreal
and MFC — ours is the opposite, and the wrong reading once let external input reach an assumption
(`gitmine.h`'s baseline-sha check, now `VALIDATE`d instead). Two words are new: `EXPECTS`/`ENSURES` (an `ASSUME` at
function entry/return that blames the caller/callee by name) and `VALIDATE` (external input — always evaluated,
never assumed, used only as a condition). No compatibility aliases: a gate refuses every old name outside dated
history.

`DEGRADED_PATH_ALERT` → `DISCLOSE`, in the same pass, with the same one-argument, debug-only-trace behaviour for
every existing site (839 renames, 179 files; `test/*check.sh` byte-identical PASS/FAIL sets, and `ripwire . --no-cache`
byte-identical between an origin/main binary and this one, on three trees). `DISCLOSE` also gains two new forms:
`DISCLOSE( sink, why[, "msg"] )` calls `sink.disclose( why )` in *every* build — the sink's contract is a C++20
concept (`Diagnostics::DisclosureSink`) checked at compile time, and `why` is a scoped enum the sink owns (one byte,
no runtime string) — and `DISCLOSE( Diagnostics::answerUnchanged, "reason" )` for a degrade that changes cost, never
content. No existing site is converted to a sink in this pass; that is the next lane's job, tracked by a ratchet
that counts only sink-less `DISCLOSE( msg )` sites in `src/` (217 at landing) and may only go down.

Release-build differences: on GCC ≥ 13, `ASSUME` compiles to `[[assume]]` instead of the old
`if( !e ) __builtin_unreachable()`, so a non-pure predicate (e.g. `std::is_sorted(...)`) no longer evaluates in a
GCC release build — Clang was already this way via `__builtin_assume`. `DASSERT` now type-checks its expression
without evaluating it, in both debug and release. Assert banners name the failed word and who is to blame
(caller/callee/invariant) instead of one generic message. `UNREACHABLE()`'s release form is `__builtin_unreachable()`
directly (not `std::unreachable()`, which would pull `<utility>` into a header that must stay library-free for
`noaliascheck`).

New gate: `test/selfcheckcheck.sh` (registered in `test/regression.sh`, `.github/pargates-shard-weights.json`; not
exempt in `test/binoverridecheck.sh`). It is zero-ceremony for a new `ASSUME` on a genuine invariant — it bites only
on a side effect inside a check, an unseen non-accessor callee in a promise, `ASSUME( false )`, external input
handed to anything but `VALIDATE`, a new sink-less `DISCLOSE`, or an `answerUnchanged` without a literal reason.

### Fixed — three degrade-alert arms asserted nothing on the plain build, and the gate harness now refuses that skip

A gate that asserts a `DEGRADED_PATH_ALERT` has to know whether the binary can print one, because Release compiles
the alert out. `test/churnjoincheck.sh` (G2), `test/preproccondcheck.sh` (the 600-deep guard stack) and
`test/w3fixlegendcheck.sh` (arm 6) found out by running `--rank-by=churn --since=notadate` and looking for an alert.
Since `--since` became a refusal (exit 1, before any degrade path runs), that run prints no alert on any build, so
all three skipped their alert arm on the plain build too: one SKIP each, zero failures, on the leg CI keeps
precisely to prove degrade paths. The build type `--version` names decides now, as in `kotlincheck` and
`estchargecheck`: Release, RelWithDebInfo and MinSizeRel skip, every other flavour asserts. G2 also asserts the join
alert itself, on the line after the NFD disclosure, where any `[math degraded]` line used to do. Arm 6's subject,
the wording of the `--since` alert, no longer exists, so it pins the refusal that replaced it: exit 1, no document,
one stderr line, and no alert, next to a positive control proving the binary prints alerts at all.

The suite could not see this, because an arm-level skip inside a passing gate counts as a pass. `test/pargates.py`
now reads the binary's build type once and fails any gate whose skip row blames NDEBUG or compiled-out alerts on a
build type that does not define NDEBUG. A skip for any other reason is untouched, and a binary that names no build
type disarms the check with a line in the summary. Gate: `test/skipclassifycheck.sh` arm (I), red on the old harness,
and the new harness fails all three unfixed gates ([#261](https://github.com/redhat-et/ripwire/pull/261)).

### Fixed — the churn join gate read "2 weeks ago" twice, and checked the default window against the wall clock

`test/churnjoincheck.sh` compared ripwire's churn with git's own count, but the two did not always ask about the same
window. The live audit passed `--since="2 weeks ago"` to ripwire and `"2 weeks ago"` to git, and each evaluated it when
it ran, so a commit on the edge fell inside one window and outside the other: #265 went red on `src/slice.h` churn 15 vs
14. Every default-window oracle asked git for wall-clock `"12 months ago"`, while ripwire anchors that window on HEAD,
so the fixtures' 2026-06 commits would have failed the gate from 2027-06-01. The offset arm beside them still selected a
retired `p="./…"` spelling and passed on zero rows. The gate now reads the clock once and hands one ISO-8601 instant to
both sides, computes the HEAD-anchored start for the default window, and re-derives all 163 offset rows. A new arm pins
both window edges to the second, with controls that stage the double reading through git's `GIT_TEST_DATE_NOW`. Measured
on the old gate with that staging: 4 FAIL rows for #265's straddle (`src/slice.h` 12 vs 11) and 12 FAIL rows with git's
clock at 2027-07-01; the new gate is 78 PASS under both stagings and without them
([#271](https://github.com/redhat-et/ripwire/pull/271)).

### Changed — the compiler checks the tables, switches, masks and layouts this tree's defects came from

Each check below is written against a defect this repository shipped or nearly shipped, and each was shown failing on a
deliberate break before it landed. None of them changes output. They are `static_assert`s, one template constraint, one
link-time stamp and two warning flags. Output was compared with the base binary on every fixture corpus, stdout and exit
code, and the only differences are the extension fix below.

- **Language registration.** Appending a `Lang` meant updating five tables in four files. 02f798e3 (Dart), 9418e35e (five
  unanalysed languages) and PR #233's `.gd` row each stayed one language short. `src/main.cpp` now asserts that every
  code language is analysed or disclosed as unanalysed by `--nonlocal-state`, and that it is named by the lint vocabulary,
  the lint catalog and `langOfPath`. `src/ingest_crawl.h` asserts that `langOfPath`'s extensions and the crawl's are the
  same. Each check returns the first INDEX that is wrong, so a zero-filled row cannot pass. `isCodeLang` (`src/model.h`)
  is the one declared exemption, and it has no `default:`.
- **`-Werror=switch -Werror=implicit-fallthrough`** on ripwire's own C++ targets, for every compiler. GCC ran no
  `-Wswitch` at all before this, because it enables it only under `-Wall`. The warning count was measured at 0 on
  AppleClang 21 and Homebrew clang 22, debug and `-DNDEBUG`, for both binaries and the four test harnesses. A switch that
  returns one answer per enumerator carries no `default:` any more. Eleven did, including `dependencyCapable` and
  `dependencyDialect`, where Dart was the one language never decided.
- **Cache and layout facts.** `quality.h`'s mirror of `kParserVer` and `kCacheVersion` is asserted equal to the real
  constants; only `test/qextractionkeycheck.sh` held that before. `CacheEntry` must have unique object representations,
  because `sizeof == 32` did not prove "no padding". `qsnapPut` is constrained the same way, so a padded struct or a float
  cannot reach a byte-stable blob. `ingest()` carries `sizeof( Symbol )` and `sizeof( IngestResult )` in its mangled name.
  CLAUDE.md records three mixed-layout builds that linked "successfully". Measured on this tree, an object pair compiled
  against two `Symbol` layouts now fails to link, where the same pair without the stamp linked and died with SIGBUS.
- **The redaction first-byte mask** is compared bit for bit with the rule table it hand-numbers, so an inserted rule
  cannot leave a later rule tried only at bytes its pattern cannot start with.
- **Shift width against count.** Every mask a runtime value is shifted into has its count pinned to its width: the
  language masks, the ensemble and quality-panel family masks, the naming-rule mask, the redaction rule mask, the
  pack-task subset enumeration and `strkern`'s block masks.
- **Tables indexed by an enum.** A table's extent is deduced and asserted against the enum's count, and the count is
  proven exact beside the enum with `infra/enumcount.h` (#241). A spelled extent had let several of these asserts restate
  their own declaration, and let a missing row compile as a null pointer. `kNodeFieldNames` rows now name their
  enumerator, because the enum and the table are paired by index. `skilleval`'s provenance counters were `[3]` for a
  four-value `Prov`. A new gate, `test/enumtablecheck.sh`, refuses a literal-extent table indexed by an enum. It reports 14
  subscripts over five tables on `f8e6087c`. Each of its three positive controls puts one real literal back and must
  report exactly that table among the violations the literal adds, so a violation already in the tree fails the rule
  arm alone instead of every control.

### Fixed — a memory buffer that lost a write was read back as a whole document

Twenty-three places render into an `open_memstream` buffer and then read it back: the map's own children (XML and JSON),
the `est_tokens` payload charges, the `--max-tokens` fit probes, the `--token-budget` buffer, the `--for` lens's pre-rendered
blocks, the `--from-trace` blocks and seven MCP answers. Twenty-two of them flushed and closed the buffer without looking
at either result. The one that did look, `renderToString`, could not see the failure it looked for.

Measured, not assumed: a `DYLD_INSERT_LIBRARIES` interposer failed one chosen `realloc` inside an `open_memstream` on macOS
26.5.1 (Apple libc), over 5 KB, 50 KB and 200 KB streams written in 1 KB chunks. In all 19 runs where the failure landed
inside the stream, one `fwrite` came back short and the stream's error flag was set. Each run lost 152 to 976 bytes, as
late as chunk 177 of 200, so the hole sat in the middle of the document. `fflush` and `fclose` both returned 0 every time.
Read after that, the buffer is a shorter document with no sign that it is one. What that meant per site: a map or `--json`
map with a hole in it; a payload section, trace block or MCP answer cut mid-element; a `--max-tokens` probe that read a
too-small size as fitting; and a `--token-budget` map printed short at exit 0.

Every buffer is now owned by one type, `rw::MemoryStream` (`src/infra/emit.h`). Its `finish()` flushes, reads the error
flag, closes, and reports by value, and it is `[[nodiscard]]`. The destructor closes a stream nobody finished and frees the
buffer on every path, so no site frees or closes anything by hand. A buffer that did not finish whole takes the path a
failed open already took. The map and the JSON map are rendered again, straight to the output, with the modelled
`est_tokens`: the children became one renderer both paths call. A charged section streams uncharged, and a probe answers
"unmeasured". The `--for` blocks are emitted directly, and a secret redacted in the failed buffer is not counted again when the block
re-renders. The MCP answers answer as they do when the open fails, except `uses`, which answers `-32603` instead of an
empty success. Two surfaces have
no second path, because the buffer holds the answer itself, and both refuse in every build instead of printing short.
The `--token-budget` map prints nothing, says `write error — the --token-budget buffer lost bytes` on stderr, and exits
1. `--from-trace` and `--run-trace` do the same when the `<trace>` map, the test hop or the signature/body section loses
its buffer, at the open or at the finish, and the MCP `from_trace` verb answers `-32603`. Those blocks used to be left
out of a bundle printed at exit 0, which no Release build disclosed.

`test/estchargecheck.sh` gains two arms. **#14f** uses a new debug-only fault switch, `INFRA_FAULT_MEMSTREAM_FINISH=1`,
which makes every finish really close its stream and then report failure. It asserts four surfaces, not every site. The
`--pack-signatures` map and the `--json` map come out byte-identical to the undegraded run outside `est_tokens`,
well-formed, at exit 0. The `--token-budget` run and a `--from-trace` run each print 0 bytes and exit 1 where their
controls print the answer. Under the same switch, MCP `uses` answers `-32603`, and the `--for` redaction summary
matches its control in XML and `--json`. **#14g** reads `src/` and refuses an `open_memstream`, a direct call of the charge opener, or
an `fflush`/`fclose` of a memory stream anywhere outside the type. On `f8e6087c` it reports 46 such lines. Its positive
control puts the two lines of one site back by hand, once per spelling of the opener (bare, `::`, `os::`, `rw::os::`),
and must report exactly those two each time.

### Fixed — five code extensions the index parses were no language at all to the dependency, state and lint verbs

The crawl indexes `.metal`, `.cu` and `.cuh` as C++, `.pyi` as Python and `.phtml` as PHP. `langOfPath`
(`src/lintrules.h`) is the verb-time classifier that `--deps`, `--arch`, co-change's `dep_capable=`, `--nonlocal-state`,
`--quality-panel`, the lint catalog and user `--lint-rules` use to bucket a file. It kept its own extension table "in sync
by hand", that table had drifted, and it called those five extensions Unknown. Every one of those verbs quietly left the
files out. `includeLangOf` (`src/resolve.h`) had the same four C++ and Python gaps, so even a counted file could not
resolve its includes.

Both tables now know all five, and the crawl's table and `langOfPath`'s are asserted equal at compile time (above).
`test/deplangscheck.sh` arm (G) requires every dependency-counted extension to resolve too. It went red with only the
classifier rows added, naming `.cu`, `.cuh`, `.metal` and `.pyi` as counted but unresolvable (and `.hxx` the other way
round), which is why the resolver rows land in the same change. `.hxx` left both tables: the crawl admits no `.hxx` file, so neither row could ever be reached.

Measured by comparing stdout and exit code, `--no-cache`, between the base binary (`f8e6087c`) and this change, over all
162 fixture corpora under `test/` and eight verbs: 1,296 runs. 14 differ. All 14 are on the six corpora that hold one of
the extensions, and only on `--deps`, `--nonlocal-state` and `--quality-panel`. The map, `--json`, `--lint`,
`--lint-catalog` and `--pack-signatures` are byte-identical everywhere.
- `test/cudafix` `--nonlocal-state`: `cells="0" functions="0"` became `cells="5" functions="4"`. The CUDA kernel's
  `rk_scaleTable`, read through `rk_clampScale`, was invisible.
- `test/cudafix` `--deps`: `dep_files="1"` became `3`, and the kernel's include of `reduceShared.cuh` now counts
  (`afferent` 1 → 2, `transitive` 1 → 2). `test/metalfix` already printed the `.metal` shader's row. The shader now
  counts in `dep_files` (2 → 3), and its quote include of `AAPLSharedTypes.h` resolves (the header's `afferent` 1 → 2).
  `test/phpfix`, `pyshapefix`, `stdqualfix` and `macroreparsefix` each gain the one file their denominator was missing.
- `test/phpfix` `--nonlocal-state`: `unanalyzed_files="4"` became `5`. The `.phtml` view is disclosed as unanalysed PHP.
- A user rule with `language: cpp` run over a `.metal` shader and a `.cu` kernel reported `findings="0"`. It now reports 16.
- `.pyi` typing stubs. A stub restates its module's globals (`COUNT: int` beside `m.py`'s `COUNT = 0`), so reading
  both files counted one global twice: a two-file probe went from `cells="1"` to `cells="2"` with every row still bound to
  `m.py`. `--nonlocal-state` and `--quality-panel` now skip a stub whose `.py` is indexed beside it. A stub with no
  source, the shape a C extension ships, is the only declaration of its module and keeps its cells: `test/pyshapefix`'s
  `stubs.pyi` adds one (`cells` 5 → 6). Gate: `test/nonlocalstatecheck.sh` arm (J), red at `cells="2"` before the skip.

Dart stays outside the dependency denominator, now by a named case instead of a `default:`. Dart has no import capture,
and a two-file probe showed `--deps` printing no row for `import 'util.dart';`.

### Changed — CI runs a light set on push to main and on `train-member` pull requests; the full matrix moves to a nightly schedule and `workflow_dispatch`

CI was the bottleneck: a merge to main re-ran the full 31-job matrix on a tree its pull request had already
tested, and a full run per landing-queue lane found almost nothing (measured 2026-09-14). `.github/workflows/ci.yml`
now computes one `full` output (from the event name, the pull request's labels and the ref) in a new `plan` job,
and every other job reads it instead of repeating the same condition:

- **Light** (the `style` job plus the single `ubuntu-24.04`/`Release`/`clang` release leg, all 4 shards — it
  already runs the determinism and G4 XML checks): a push to `main`, or a pull request carrying the
  `train-member` label. Labelling is maintainer-only by construction — a fork pull request cannot label its own.
  `pull_request` now also triggers on `labeled`/`unlabeled` (on top of the GitHub default types) so toggling the
  label re-evaluates the same pull request without a new push.
- **Full** (all 31 jobs): every other pull request, `workflow_dispatch` — run this against the exact commit
  before any release tag, not an earlier green nightly — and a new nightly `schedule` at 05:41 UTC (off `:00`,
  distinct from `nightly.yml`'s own 07:17 TSan run). `release`'s matrix is `plan`'s own computed output rather
  than a second hand-typed list, because a job-level `if:` cannot see the matrix context to prune legs directly.

A failure on the scheduled full-matrix run opens or updates `ci.yml`'s own tracking issue, titled "Nightly
checks failing on main (full matrix)" — deliberately separate from `nightly.yml`'s TSan one. Every tracking
issue carries the shared `nightly-failure` label (so "every nightly-scale failure" is one query) plus a
workflow-specific second label — `nightly-full-matrix` here, `nightly-tsan` in `nightly.yml` — and every
open/comment/close filters on both together, so a green run in one workflow can only ever touch the issue
carrying its own second label. (An earlier draft of this change shared one issue between the two workflows
with an uncoordinated close each; that let a green TSan night close an issue the full matrix had opened
while the matrix was still red, and the reverse — caught before merge, not shipped.) Top-level permissions
are `contents: read`; only the two report jobs widen, and only to `issues: write` on themselves.
`test/g1configcheck.sh` gates the split with ten new `ciRows` for `ci.yml` and one new `labelscope` row in
`nightlyRows` for `nightly.yml`, each proven red on its own mutated copy. Five of the ten `ciRows` extract the
`plan` job's decide script and execute it under synthetic event/label/ref combinations rather than guessing
at the bash from a regex.

### Fixed — a cached 16-bit field wider than 16 bits was believed, and a `--with-profile` line past INT_MAX joined the wrong site

Two defects found by a new static gate that asks, of the crashes fixed this cycle, whether their shapes were visible
in source before they shipped. **The ingest cache stores five def fields (`ppAlt`, `humps`, `deepLoc`, `ev`,
`params`) and a reference's `argCount` as 16-bit values in u32 slots, and read them back with
`std::uint16_t( r.u32() )`**, which keeps the low bits of a value the writer can never have produced: a
checksum-valid record carrying 0x10000 was served as 0. `ByteR::u16Of32` refuses such a record the way `enumU8`
refuses an enum byte past its count (that file reparses, the rest of the blob stands). Measured on the
`cachefuzzcheck` Part 3 fixture (15 files): 0x10000 and 0xFFFFFFFF in `ppAlt`, `params` and `argCount` were accepted
before (`cached_records=15 of 15`, 6 FAIL rows) and are refused after (`14 of 15`, output byte-identical to
`--no-cache`, clean under ASan/UBSan), while 0xFFFF is still accepted. Cost, Apple clang 21 `-O2 -DNDEBUG` on the
ingest TU: `loadCache` 3,962 → 3,992 instructions (+0.8%, six branchless compare-and-selects); no other function changed.
**`--with-profile` read its `#PROF_TSV` line column with `std::atoi`**, which is undefined past INT_MAX; libc kept
the low 32 bits, so a line of 4294967329 read as 33 and annotated the finding at line 38 with a site that is not
there (`heat_joined="1"`). The column now goes through `std::from_chars`, and a value that is not wholly a positive
int is a row that carries nothing joinable, like a short row (`test/withprofilecheck.sh` arm 8: red on the base,
`heat_joined="0"` after, with the same row at line 33 still joining as its control). `--plan-lint`'s
`std::filesystem::absolute` fallback takes an `std::error_code` too.

The new gate `test/hazardpatterncheck.sh` runs ripwire's own `--match` over `src/` (19 queries, about 5 s) for the
hazard classes no other gate holds, and registers every site it finds with the fact that makes it safe: (A) an enum
built from a byte reader outside `ByteR::enumU8` (1 site, validated in place); (B) every `catch` handler that
records nothing (11 of 27 — 6 of them rows naming a drop that is silent in Release, for the disclosure lane) and
every `throw` with no `try` in its own function (3, all permitted seams); (C) a throwing or overflow-undefined
standard call where nothing may throw — `std::sto*`, `.at( )`, `.value( )`, the `atoi` family, `std::filesystem`
without its error_code (72 calls read), a range-for over a directory iterator; (D) a decoded value narrowed without a
check (1,269 casts read, 0 left); (E) a raw acquisition `crashsweepcheck` does not name — descriptors, the malloc
family, `new`, tree-sitter parsers, queries, cursors and trees — without an owning destructor (36 sites registered,
2 owned). Every registry is exact both ways: a new site fails, a moved count fails, and a row that matches no site
fails, except a row marked PENDING, whose fix is already written on another branch and which asks to be deleted once
it lands. Red on the base: 6 rule-C sites (four of them the `--eval-skills` and `ripwire wrap` filesystem throws that
the parser-crash lane fixes) and 6 rule-D sites; green after. A probe tree with one violation and one compliant twin
per rule proves each rule fires (13 planted violations, nothing else).

### Added — reader fuzzers for ripwire's own parsers of bytes it did not create, and the two crashes they found

The fuzz suite fuzzed only the vendored tree-sitter grammars. `test/fuzz/readers/` adds 16 libFuzzer targets
(`ripwire_fuzz_reader_<name>`, `RIPWIRE_FUZZ_READERS` in CMakeLists.txt) over the code hostile input reaches: the MCP
JSON-RPC scanner and HTTP request reader, the ipynb/HTML/CSV extractors, `--from-trace`, the skill scanner, the SCIP
decoder, tsconfig/go.mod aliases, lint-rule files, the qsnap/qchurn/history-oracle caches (header and digest rebuilt so
the fuzzer reaches the parse), the committed sidecars, `--scope`, ingest-cache records and frames, and the span-tier memo.
Seeds are 54 blobs the real writers produced (`make_seeds.sh`); `run.sh replay` fails a reader that ran 0 inputs or
refused a valid seed. Five minutes per reader under ASan, UBSan (with `integer`) and libc++ extensive hardening, Homebrew
clang 22, found: a SCIP varint whose 10th byte carried payload past bit 63 was accepted as a truncated number (and
aborted the G1 build); and `openCacheFrame`'s exact-fit check summed a table offset near 2^64 through a wrap, while its
per-entry bound `recOffset + recLength` wrapped far enough to ACCEPT a record at 2^64-16 (`blob_entries=6` where the
frame is corrupt). Both are fixed without the wrap, with red-first arms: `scipcheck` 5c and `cachefuzzcheck`'s two
`*_near_u64_max` mutations plus a disclosure arm (`corrupt-frame`, `blob_entries=0`), and the minimized inputs are
`regress-*` replay seeds. The qsnap and qchurn readers hit the unbounded-count `reserve` #249 fixes (18 GB and 40 GB
allocations) within seconds.

### Fixed — a term-rich `--for`/`--pack-task` query, an unbounded MCP stdio request line, or a pathological ASan trace could exhaust memory or stall the process

- **A `--for`/`--pack-task` task string with many distinct terms could cost gigabytes of RAM.** The task
  string is agent-supplied text, not a hand-typed query — an agent can paste a whole file, log or issue
  body — and the query's DISTINCT term count had no ceiling: `lexicalScoresTiered`'s `tfFlat` allocation
  (symbols × unique query terms × 4 bytes) grew with the paste, not with the corpus. A measured 480 KB
  task string cost 5.2 GB RSS on one request. `dedupeQueryTerms` now caps the kept unique-term count at
  `kMaxUniqueQueryTerms` (1024 — about 102× the longest real `--for`/`--pack-task` query on record in
  `bench/` and `docs/`), disclosed as `terms_capped="1" terms_total="N"` on the CLI's `--for` root and on
  the MCP `for`/`explore`/`pack_task` responses, never a silent truncation. Gate: `test/forblowupcheck.sh`.
- **An MCP stdio request line had no size bound, unlike the HTTP transport.** `runMcp()`'s read loop grew
  its line buffer without limit, so one long-lived `--mcp` server could be pushed toward OOM one
  oversized line at a time by a runaway or hostile peer — HTTP already bounded a request body at 8 MiB
  before it reached the JSON-RPC layer, stdio had no equivalent. `readByteSafeLineBounded`
  (`src/infra/stdinline.h`) now bounds a stdio request line at `kMcpStdioLineMaxBytes` (32 MiB) and drains
  the remainder of an over-limit line without buffering it; `runMcp()` refuses it with a named JSON-RPC
  error (`code=-32600`, `id:null`) and keeps serving the next request on the same connection. Gate:
  `test/mcpstdiolinecapcheck.sh`.
- **A pathological `--from-trace` line could turn 160 KB of text into ~4 s of CPU.** `parseAsan`'s search
  for an ASan/UBSan frame's source location re-derived the whole candidate on every widening try
  (a demangled C++ function name can itself contain spaces, so the split cannot just be the first one) —
  O(k²) in the space-separated word count k. A line built from thousands of short, non-path-shaped
  "words" with no valid trailing location (a fuzzer or minified-diagnostic shape) showed the worst case.
  Every quantity the rescan recomputed is actually invariant once the growing window first reaches it, so
  `parseAsan` now computes each once and walks word boundaries in a single backward pass — O(size), not
  O(words²) — landing on the exact same candidate the original rescan would have found first. Gate:
  `test/traceasanlinearcheck.sh` (40 KB/160 KB/640 KB/2.5 MB timing; the baseline binary times out past
  640 KB on the same fixture).
### Fixed — a cache blob, a file in the tree, or an MCP preview could crash, hang or starve the process

Each of these was reproduced before it was fixed, and each now has a gate that fails on the old code.

- **A checksum-valid qsnap or qchurn cache blob with a huge record count aborted.** `deserializeSnapshot` and
  `deserializeRawCommitStream` passed a count read from the blob straight to `reserve`: 2^32−1 records is 32 GiB for
  the qsnap vectors and 96–128 GiB for the qchurn commit and path lists. On Linux that is `std::bad_alloc`, which
  nothing on the CLI path catches, so `--quality-delta`, `--edit-check`, `--for`, `--metrics` and `--exemplar` died
  with SIGABRT on every run until the blob was evicted (reproduced on Ubuntu, exit 134). Every count is now measured
  against the bytes left in the blob first, and a count that cannot fit makes the blob corrupt: recompute, as for any
  other damage. Gate: `test/cachefuzzcheck.sh`, Part 2's three vector-count rows and the new Part 5. The rows run
  under an allocation bound (`ulimit -v` on Linux, ASan's `max_allocation_size_mb` anywhere), because macOS
  overcommits the reservation and exits 0 against the defect. The old map-count and wrong-sha rows wrote at stale
  offsets, so an earlier guard rejected the blob before the count was ever read; they now write where
  `deserializeSnapshot` reads, and both tables check the good blob's layout first and fail loudly if a header change
  would re-aim a row.
- **A short read leaked a file descriptor.** The parse pool's `readFile` closed its stream inside
  `( got == want ) && ( std::fclose( fp ) == 0 )`, so a file that came up short (truncated between the size probe
  and the read) was never closed. A long-lived `--mcp` server re-ingesting such a tree ran out of descriptors, and
  every file it could then not open dropped out of the answer at exit 0. With an interposed short-read shim, 300 of
  600 short-read streams stayed open, and under `ulimit -n 200` all 20 ordinary files vanished from a `--grep`
  answer. The stream now has an owner, `rw::OwnedFile` (`src/infra/ownedfile.h`), whose destructor closes it on
  every path, and the whole-file readers in `ingest_crawl.h`, `docparse.h` and `editpreview.h` use it. Gate:
  `test/crashsweepcheck.sh` B1.
- **A FIFO, a directory or a device link at `.ripwire_config` or `.ripwire_quality_acks` hung or aborted.** Both
  were read through a blocking open on the name. A FIFO hung `--quality-delta` before any output, and a committed
  symlink from the acks ledger to `/dev/zero` or `/dev/urandom` never reached end of file. A directory at
  `.ripwire_config` opens on Linux; where a directory's seek reports `LLONG_MAX` (overlayfs), the string that length
  asks for aborts, the failure `ingest_crawl.h`'s `PathShape` note measured for `--cache=<dir>`. Both files now go
  through `docparse::detail::openRegularFileStream`: it opens with `O_NONBLOCK`, asks the descriptor what it opened,
  and reads anything but a regular file as absent, with a stderr line saying so. The ledger is still read one line at a
  time. Gate: `test/crashsweepcheck.sh` B2
  (eight shapes).
- **`edit_check` with `new_body` raced the HEAD-snapshot prefetch worker.** The preview's two ingests ran after the
  verb's own ingest had released the process-wide ingest lock, so they could run alongside the detached prefetch
  worker's ingest. `ingest()` installs compiled tags queries into a process-global cache and deletes the entry each
  install displaces, and that is single-writer by design. On the ThreadSanitizer build the server reported a data
  race at the parse-pool call and aborted (exit 134) mid-session. The preview's ingest now takes
  the same lock as every other ingest a server runs. Gate: `test/qsnapprefetchcheck.sh` (f), whose red needs the
  TSan build (`RIPWIRE_BIN=tsan/ripwire`).
- **A file dated after 2262 overflowed a signed multiply.** `tv_sec * 1000000000 + tv_nsec` does not fit in
  `long long` past 2262-04-11, a date ext4, XFS, tmpfs or a tar restore can store. That is undefined behaviour in
  release and an abort in the sanitizer build (reproduced on Linux tmpfs: `signed integer overflow: 10000000000 *
  1000000000`). Both stat readers now saturate through `rw::saturatingNanoseconds` (`src/infra/statclock.h`); size
  and ctime still tell apart two saturated timestamps. Gate: `test/crashsweepcheck.sh` B3. APFS clamps timestamps
  at 2262, so on macOS the arm says it cannot build its input.

Three of these shapes can be seen in the source, so `test/crashsweepcheck.sh` now also runs ripwire's own `--match`
over `src/` and fails on them. Each rule is proven live against a probe tree that holds one violation and one
compliant twin.

- **S1:** an allocation sized by a count a byte reader decoded must be bounded earlier in the same function.
- **S2:** every raw `fopen`/`open`/`fdopen`/`opendir`/`open_memstream`/`popen` site must be registered with the fact
  that makes it safe, and a new one points at `rw::OwnedFile`. A close as the right operand of `&&`/`||` or an arm
  of `?:` is refused outright.
- **S3:** every body handed to a `std::thread` must be `noexcept` or a single try block. The eight bodies that were
  neither are now declared `noexcept`, as are three that were already one try block. None of them had a throw that
  could escape except allocation failure, which already ended in `std::terminate`.

Red on the base, in order: S1 finds the three unbounded counts, S2 the short-circuited `fclose`, S3 eight bare
bodies. The gate's header states what each rule catches and what it misses.

### Added — a nightly ThreadSanitizer run against main, which opens one tracking issue when it fails

ThreadSanitizer had a build mode (`-DRIPWIRE_TSAN=ON`) and one gate written for it, `test/qsnapprefetchcheck.sh` arm
(e), but nothing ran it against `main`: a data race could reach a tag if nobody happened to build TSan locally in
between. It is not added as a per-PR leg, because TSan builds already run often on contributors' machines and every PR
already waits on the macOS runners. `.github/workflows/nightly.yml` runs it once a day at 07:17 UTC instead, and skips
the heavy job when `main` has not moved since the last green scheduled run and no tracking issue is open.

The job builds TSan with clang in its own tree and runs ten gates against it, chosen for the threads they drive: the MCP
prefetch worker (`qsnapprefetchcheck`), the edit lock (`mcpeditracecheck`), a server's re-ingest at a 128-fd limit
(`mcpwatchercheck`), a long-lived server's re-ingest after an edit (`mcpstalecheck`), concurrent `--quality-ack` writers
(`qackconcurrencycheck`), the private cache directory (`cacheisolationcheck`), the parallel ingest and `--match` fan-out
over the repository (`det-gate.sh`), `--grep`'s prefetch thread (`grepfastcheck`), the `--doc-drift` workers
(`docdriftcheck`) and the git-spawn pool (`mergescoutcheck`). A gate's own verdict is not trusted to notice a race:
reports go to per-gate files, and a wrapper fails the step on a non-zero exit or on any report file. Before any gate
runs, the job checks that every object of the `ripwire` target references the TSan runtime, and that the wrapper goes
red on a planted race and stays green on its race-free twin. Locally on Apple clang 21, the same wrapper failed on the
planted race and on a race whose exit code the command swallowed, and all ten gates passed through it against a TSan
build of 105666c1 with no report file (4 s to 404 s each, `mergescoutcheck` the slowest, on a machine at load 40-60).

A failing run on `main` opens one issue, "Nightly checks failing on main" (label `nightly-failure`), or comments on the
open one. The comment names the failing jobs and steps, the commit and the run, and quotes the head of the first report.
The next green scheduled run comments "green again at <sha>" and closes it. The top-level token is `contents: read`,
and only the two reporting jobs hold `issues: write`. A pull request that edits the workflow runs it without the
reporting. A placeholder marks where the Windows full-suite job goes (D3 of the #44 plan). `test/g1configcheck.sh`
gains six rows that pin the schedule, the skip probe, the TSan wiring, the permission scoping, the report conditions
and "no secret but `GITHUB_TOKEN`". Each row has a mutated copy that turns exactly that row red.

### Fixed — a diagnostic notice could be split across lines by another thread's output, which is what kotlincheck §12 kept tripping on

The `DEGRADED_PATH_ALERT` notice, and the assert, panic and thread-violation banners, were built from a chain of
`std::cerr` insertions. With stdio sync on, each insertion is its own write to stderr, so a line another thread
wrote at the same moment could land inside a notice. kotlincheck §12 refuses two Kotlin files at once; when the
second parse worker's refusal line landed straight after `[math degraded] `, the arm's one-line grep failed with
"raised no DEGRADED_PATH_ALERT" although the alert was on stderr, whole, one line further down. That is the
failure eight CI jobs hit since Kotlin landed, three of them on `main`. Measured on f8e6087c by running §12's map
over its own fixture: 18 gate failures in 5,700 runs, and the notice torn in 32–73% of runs depending on load.
Every reporter now formats its whole notice into a fixed 4,096-byte stack buffer and hands it to stderr in ONE
stdio call, which no other stdio writer in the process can interleave, and which needs no heap in a reporter that
may be running because memory ran out. The text is byte-identical for every notice under the cap; a longer one is
cut and says so at its end (`... [notice truncated: kept K of N bytes]`). The reporters still flush stdout
before the notice, as `std::cerr`'s tie to `std::cout` always did, so a trap or an abort right after it loses no
buffered output and `>file 2>&1` keeps its order. Measured after the fix on §12's fixture, alternating
run by run with the f8e6087c binary under four busy loops: 0 gate failures and 0 torn notices in 2,100 runs,
against 6 failures and 726 torn notices from the old binary in the same 2,100 interleaved runs. The new gate
`test/diagnoticecheck.sh` counts the write(2) calls each reporter makes by giving it a datagram socket as fd 2,
which keeps write boundaries: red on the old reporters (9 writes for the degraded notice, 15 to 21 for the banners,
every one still byte-exact), green at one write each. Three `2>&1` cases leave text in stdout's buffer before a
degraded notice, an assert and a panic, and require it first and whole: byte-identical to the old reporters. It also carries a static arm with a mutation control, a
12,000-notice race against raw and stdio writers (red in 200 of 200 runs on the old reporters), a zero-allocation
arm (global `operator new`) measured with `src/alloccount.cpp` as a delta between otherwise identical runs, and an
ASan/UBSan pass. kotlincheck §12 now prints the first five lines of stderr when that arm fails, because
none of the eight CI logs could show what the notice had looked like. Not fixed here: the default map over the same
fixture says `files=4` with no sign of the two refused files, a disclosure gap tracked by #157.

### Fixed — a user's regular expression could abort the process, hang the skill scanner, or answer a question it never finished; one header owns them now

Only `--regex` screened a user's pattern before handing it to `std::regex`. Three other entry points took the same
engine unscreened and caught nothing at match time, so on Apple libc++ — whose engine throws `error_complexity` when
it gives up — `ripwire <dir> --graph-query='file(all,"(a+)+z")'` and an `--arch` rules file holding `deny path zz/.*
-> (a+)+z` both died with an uncaught `std::regex_error` (rc 134), over a fixture whose directory name is a run of 44
`a`. `--match` swallowed the same throw and KEPT every row the `#match?` predicate never decided, at rc 0; a malformed
`#match?` pattern kept every row too. On libstdc++, which has no budget, each of these backtracks without end. A
`--regex` of 20,000 bytes died with SIGBUS (rc 138): `std::regex` compiles by recursion, and a grep worker runs on a
512 KiB stack. The skill scanner's `EXFILTRATE:net-exfil` regex was quadratic in the line — a 20,000-byte fenced `curl
curl …` line took 5.9 s and a 200,000-byte one was still running at 60 s — and an engine throw inside it would have
ended `wrap`'s `noexcept` scan. And `file()` matched the path with the checkout's own directories in front of it:
`file(all,"alpha")` selected every symbol in a clone named `repo_alpha` and none in `repo_beta`, and
`file(all,"^src/")` selected nothing under an absolute root.

`src/regexguard.h` now owns the screen (moved verbatim from `src/search.h`), the compile and the match, and is the one
place that catches `std::regex_error` and `std::bad_alloc` — by type, converted to a value behind a `noexcept` API
that `static_assert`s pin. A pattern the screen or the parser rejects is refused by name at exit 1 on every entry
point (`--graph-query file()`, an `--arch` FROM or TO path-rule, a `#match?` in `--match` or `--lint-rules`), in the
words `--regex` already printed. The screen also bounds a pattern at 2,048 bytes and 64 nested groups, under the
smallest stack overflow measured with a standalone probe (a 3,392-deep nesting and a 16,896-byte literal on a 512 KiB
libc++ thread; 960 and 3,648 on a 512 KiB libstdc++ one). A match the engine abandons part-way — overlapping
alternation such as `(a|a)+z` passes the structural screen — is refused by name at exit 1, never read as "no match":
the regex scan used to skip the rest of that file behind a `DEGRADED_PATH_ALERT`, which a Release build compiles out,
and still print `hits=` as a complete count. An `--arch` TO template that compiles for no capture rejects the rules
file at parse, and one that only breaks once an edge's captures are substituted (`a{2,\1}` becoming `a{2,1}`) is
refused naming the substituted text, where both used to leave the rule silently inert. `file()` matches the
root-relative path its own `p=` prints, the rule `--arch` adopted for its rules. The skill scanner's patterns go
through the same boundary and fail CLOSED — an undecided line is a CRITICAL `SCAN-INCOMPLETE:regex-abandoned` finding
— and `net-exfil` is decided by a linear scan derived from its regex. The built-in lint packs keep the old
keep-the-row fallback for their constant patterns.

Not fixed here, measured and disclosed: libstdc++'s matcher recurses once per consumed character, so on Linux a
`--regex` such as `a*b` crashes on a long enough matching line with an 8 MiB stack — from about 26 KB, build-dependent
(a standalone probe: 26,624 bytes, 13,312 for `(a|b)*c`; this tool's own earlier Linux builds: between 27 KB and 35 KB
for a gcc dev build, 35 KB and 45 KB for a clang Release one); a pattern bound cannot reach that.

Byte-identical: 45 of 45 comparisons of the origin/main binary against this one (dev build, one checkout, stdout,
stderr and exit code) across `--grep`/`--regex` (prefiltered and full-scan, context, compact, unindexed, the three
existing refusals, JSON), `--graph-query`, `--arch`, `--match`, `--lint`, `--lint-rules` (incl. SARIF), `--scan-skill`
and `--scan-skills` over every scanner fixture and this repository's own skills, and the map, plus a three-request
`--mcp` grep session; the only differences are the fixes above. Instructions retired (Release, `/usr/bin/time -l`,
median of 5, interleaved, the final commit against origin/main): `--regex` over an llvm-project checkout of 8,837
C/C++ files −2.4% to −3.3%, over this repository within ±0.5%, the literal `--grep` and map controls +0.3% to +1.6%;
release `__TEXT,__text` 8,684,280 → 8,704,196 bytes (+0.23%, the refusal texts and the scanner), `grepScanText` 443 →
437 instructions. No compile was added: once per query, per rule and per grep worker as before, and `file()` now
decides each FILE once instead of each symbol.

Gate: `test/regexguardcheck.sh` — (a) a catastrophic pattern refused by name on all five entry points, each with a
positive control; (b1) the non-NDEBUG fault switch `RIPWIRE_FAULT_REGEX_MATCH=1` makes every guarded match throw and
each entry point must refuse naming the pattern (or, for `--lint-rules`, the rule); (b2) `(a|a)+z` against libc++'s
real engine; (c) no `std::regex` spelled in `src/` outside the owner and a one-row allowlist (the constant redaction
table), with planted-file controls; (e) the `--arch` TO template refused at parse and after substitution; (f) the
linear `net-exfil` agrees with its regex over 1,200 generated lines, a 200,000-byte line scans in bounded time, and an
abandoned match fails closed; (g) the size and depth bounds, each with its limit still compiling; (h) an undecided
capture-typed `#match?` is reported by cause — a captured text the screen refused, one that does not compile, or an
abandoned match — naming the first site and its text; (i) `--arch` decides deny rules first, so an allow the engine
cannot finish refuses only when a deny fires and no allow matches; (d) two clones at different directory names,
absolute and relative roots, agree. Red on origin/main: 72 failures, ten of them a signal death (rc 134 or 138).
`test/astqueryregexcheck.sh` C4 now asserts the malformed-pattern refusal, and its golden's `match-malformed` section
is empty.

### Fixed — `--regex` crashed on a long matching line on Linux; a literal pattern skips the engine, and a line too long for the engine's stack is skipped and counted

libstdc++'s regex matcher recurses once for every state it visits, so on Linux `--regex='a*b'` died with SIGSEGV
(exit 139) in a grep worker on a matching line of about 26–45 KB — the residual the entry above disclosed. Measured on
this lane's own gcc 13 Linux build before the fix: exit 139 on a 300 KB matching line, and again on a 2 MB line that
could not match at all. Three changes, in this order:

- **The engine is not asked when the answer is a byte search.** `src/regexguard.h` reads each compiled pattern once. A
  literal, or literals joined by `|` (one of them optionally `^`/`$`-anchored), is matched with `strkern.h`'s byte
  kernels in the engine's own order — leftmost start first, then the first alternative written — so no line is too long
  for it. Any other pattern's required literals (the unquantified literal runs outside groups, one set per top-level
  alternative) rule out every line that holds none of them before the engine sees it: `a*b` never reads a line with no
  `b`. The full-scan switch the gates use turns both paths off, so `test/regexcheck.sh`'s prefiltered-versus-full-scan
  diff checks them too.
- **The scan threads get a stack they can state.** grep's workers and its unindexed scan run on 256 MiB POSIX threads
  (`src/infra/stackthreads.h`), halving on refusal down to 8 MiB; pages are committed only as deep as a match recurses.
  Starting 16 of them costs the same at 8 MiB and 256 MiB, within run-to-run noise, on macOS and on Linux. ONE size is
  settled — the smallest any thread got — before a single file is read, and every thread is held to it, so no file's
  answer depends on which thread picked it up; a size below 256 MiB is disclosed on the answer as `regex_stack_bytes=`,
  with `regex_line_max=` beside it even when nothing was skipped.
- **A line past the measured bound is skipped and said so.** A per-pattern model bounds the matcher's recursion; the
  bytes one modelled visit may take (128) is the largest need measured over 35 pattern shapes and six builds — gcc
  -O0/-O2, clang -O2 and -O3 -flto, gcc and clang under AddressSanitizer — rounded up, with half of every stack held
  back, so the engine's measured crash is at least 2.5× the bound. On gcc 13 at 256 MiB the bound is 149,502 bytes
  for `a*b` and 33,757 for `(a|b)*c`. A longer line is never handed to the engine: every `--regex` root now carries
  `regex_lines_skipped=` (0 means none was), and when it is not 0, `regex_line_max=` and `counts_floor="1"` ride with
  it — hits= is a floor — defined in the full legend and the compact one. libc++ does not recurse per character, so
  macOS has no bound and skips nothing.
- **Secret redaction no longer runs the engine.** `src/redact.h` redacts every emitted body by default, up to 4 MB, and
  its rules went straight to `std::regex`: on the gcc 13 Linux build, `--expand` over a file holding `sk-` and a 200 KB
  token run died with exit 139. Every rule is a literal prefix and character-class runs, so each is now matched by
  reading its runs once (the PEM banner's word loop takes the regex's greedy choice); the regexes stay in the table as
  the specification. Nothing is skipped, so there is no unscanned line to withhold. `src/regexguard.h`'s allowlist of
  files that may spell the engine is now empty.

Byte-identical: 61 of 61 comparisons against this lane's parent (dev builds, one checkout, stdout, stderr and exit
code) — 42 unchanged to the byte (`--graph-query`, `--arch`, `--match`, `--lint`, `--lint-rules` with SARIF, the map,
`--scan-skill(s)`, the literal `--grep`, and every redaction seam: `--pack-top-n`, `--expand` and `--recall` over the
secrets fixture and this tree), and 19 `--regex` answers (literal, alternation, anchored, required-literal,
prefiltered and full-scan, context, compact, unindexed) identical once the new `regex_lines_skipped="0"` and its legend
sentence are removed. Instructions retired (Release, `/usr/bin/time -l`, median of 5, interleaved, against the parent):
`--regex` over an llvm-project checkout of 8,837 C/C++ files −83% to −90% (`getOperand\w*\(` 224.5G → 28.3G), over
this repository −80% to −93%; the full-scan switch, where every line still reaches the engine, −8% and −14%; the literal
`--grep` and map controls within ±0.7%. Release `__TEXT,__text` 8,715,336 → 8,732,840 bytes (+0.20%); `grepScanText`
437 → 1,609 instructions, because the line loop, the literal searches and their kernels now inline into it.

Gate: `test/regexguardcheck.sh` — (j) `test/regexlines_harness.cpp` diffs the literal plan, the required-literal filter
and the skip policy against `std::regex` itself: adversarial, generated and corpus patterns (every `--regex` the docs,
skills and gates spell, every `#match?` a query or lint pack carries) over CRLF, LF and empty-line texts, under both
syntax sets; 0 mismatches over about 80,000 cases on libc++ and on libstdc++, and a copy of the header whose
alternation resumes one byte past a match must go red; (k) a 300 KB matching line is matched or skipped-and-disclosed,
a 2 MB line with no `b` is ruled out in bounded time, a literal alternation over a 3 MB line answers, and a literal
`--grep` is unchanged; (n) with a test switch that gives half the scan threads half the stack, 48 files are answered
identically over five runs at one bound and the smaller stack is disclosed (the per-thread bound it replaced skipped 24
to 27 of the 48, varying run to run); (o) `test/redactshape_harness.cpp` gives each redaction rule's regex match length
at every position over 30,000 generated texts (682,859 checks, 0 mismatches on libc++ and libstdc++; a threshold moved
by one goes red), and the 200 KB `sk-` file exits 0 with the key redacted; (l) on a recursing engine, for three shapes, a line of exactly `regex_line_max` bytes is matched
at exit 0 and one byte more is skipped; (m) the non-NDEBUG fault switch `RIPWIRE_FAULT_REGEX_LINE_BOUND=1` reaches the
skip path and its disclosure on every engine. Red on this lane's parent: 8 failures on macOS (a TIMEOUT on the 2 MB
line), and 8 on the gcc 13 Linux build, two of them a signal death (exit 139). `test/emittertruthcheck.sh` (Z2h) holds the
new "always present" claim at zero; `test/compactlegendcheck.sh` re-pins `ripwire.grep/v1` 360 → 440 (measured 422 on
`--regex`).

### Changed — Intel macOS binaries end with 0.6.1

0.6.1 is the last release with a prebuilt Intel macOS binary. The `macos-x64` release leg has had no Intel machine since
GitHub retired its `macos-13` runner pool, which left v0.1.0's leg and the first v0.2.0 run queued for 24 hours until
the auto-cancel. From then on it cross-compiled on an arm64 runner with `-DCMAKE_OSX_ARCHITECTURES=x86_64` and ran its
PGO training, its determinism diff and its smoke test under Rosetta 2, pinned to the one runner image whose Rosetta was
verified to execute the binary's x86-64-v3 instructions. Every step that proved the binary ran did so under a
translator. The leg is gone from `release.yml`, along with the deployment-target step and the `minos` check that only it
used. The Linux x86-64 binary and its x86-64-v3 floor are unchanged, and an Intel Mac can still build from source.

The installer was not told. Its arch map sends `x86_64` to `x64` on every OS, so an Intel Mac asking for a later release
would have heard `release vX has no asset named ripwire-X-macos-x64.tar.gz`: true, and silent on both the decision and
the two routes that still work. `scripts/install.sh` now stops an Intel Mac before any download for every release after
0.6.1, says Intel macOS binaries end with 0.6.1, and prints the exact command that pins `RIPWIRE_VERSION=v0.6.1` and the
exact source build. Pinning 0.6.1 still installs its Intel binary. A Rosetta shell on Apple silicon, which also reports
`x86_64`, is sent to a native arm64 shell rather than told it owns an Intel Mac.

Gate: `test/releaseinstallcheck.sh` section H, nine rows. Five were red on main: the unpinned one-liner on an Intel Mac
(two rows), a v0.10.0 pin whose release still listed a `macos-x64` asset and installed it, the Rosetta shell, and
`release.yml` still building the asset. The three installer controls (a v0.6.1 pin on an Intel Mac, Linux x86-64,
macOS arm64 on a later release) each went red against a mutant installer that refused one release too many, or keyed on
the arch or the OS alone. `test/portablebuildcheck.sh` #2h, which held the leg to its verified runner, Xcode and
deployment target, retires with it.

### Fixed — `--quality-delta` answered from a dead-code baseline another build computed

`--quality-delta` caches the snapshot it computes for `HEAD`, keyed on the repository, the commit, the excludes, the
file-size ceiling and the parser version. Its dead-code half also depends on call resolution — a function is dead when
nothing calls it — and a change to how calls resolve moves none of those, because resolution runs over facts already
extracted. So two builds that resolve calls differently, sharing a cache directory on one commit, answered from each
other's snapshot: after an upgrade on a repository whose `HEAD` has not moved, or with an installed `ripwire` and a local
build on one checkout. Measured on main `a55b118e` against the same tree with the `std::`-qualified call guard switched
off, over a two-file fixture where `std::launder( &v )` may or may not bind an in-repo `Pool::launder`: on a cold cache
the guarded build reports `regressions="0"`, and after the unguarded build warmed the cache it reports a gating
`dead-code` row on the untouched `Pool::launder` and exits 2. The other order hides a real one: deleting the only call is
a gating regression on a cold cache (exit 2) and nothing on the warm one (exit 0). Both runs used one cache file.

Each build now has a source identity: a SHA-256 over every file under `src/` and `queries/`, computed by
`cmake/source_identity.cmake` on each build (49 ms on this tree) and compiled in as one generated definition. The
snapshot and window-ref body caches fold its full 64-hex spelling into the material their filename key hashes, and the
blob header stores its `fnv1a64`, which a reader must match. It is derived rather than a version to bump because bumps
are what this cache has missed: an `isDeadCandidate` exemption and a parser-version change each shipped without one, and
no resolution change ever had one. The price is that any source edit renames the snapshot, including one that changes
nothing it means. On ripwire's own tree, five runs each with a private cache, a warm `--quality-delta` took a median
3.04 s (2.78–3.21) and one whose snapshot had to be recomputed 5.12 s (4.85–5.34), identical output throughout; the
parse cache underneath keeps its key, so that recompute reads a warm parse. On the fixed tree the two-build experiment
writes one snapshot per build and matches a cold cache in both orders. The snapshot and window-ref body caches move to
schemes 14 and 4.

Gate: `test/qsnapproducercheck.sh`, 16 rows. Its core is a matched pair over a real cached snapshot: dead entries
dropped (or added) with the producer bytes kept, a control that must change the answer and does, and the same forgery
with those bytes flipped, which must be refused with output byte-identical to a cold cache. Against main 8 of its 13
rows failed: the forgery had no producer bytes to flip and was served in both directions, and the key, header,
derivation and blob arms found nothing. Under ASan the gate passes with no sanitizer report on any child's stderr, and
`test/cachefuzzcheck.sh`'s snapshot sweep stays clean. Pin moved: `test/qschemetrip.hash`.

### Fixed — a pinned `--quality-baseline` was honored by a build that resolves calls differently

The same defect, in the file you write on purpose. `--quality-baseline` pins a floor to `.ripwire_quality_baseline`,
dead-code records included, and stamped it with nothing but the `HEAD` commit, so `--quality-delta` honored the pin
whenever the commit matched, whichever build had written it. Pin with the installed `ripwire`, then check with a local
build (or upgrade) before the next commit, and the floor's dead set came from one resolver while the working tree's came
from another. Measured with two builds of the previous commit, `d8c225a2` as built and with the `std::`-qualified call
guard switched off, over the fixture above: pinned by the unguarded build and checked by the guarded one, an untouched
tree reported a gating `dead-code` row on `Pool::launder` and exited 2 (the guarded build pinning its own floor: exit 0).
In the other order a real regression disappeared: deleting the only `std::launder` call exited 0 where the unguarded
build, against its own pin, exits 2.

The sidecar is now format v6 and carries a `producer` record, the same source identity the snapshot cache uses. A pin at
the current `HEAD` whose producer is missing or names another build is not the floor: `--quality-delta` falls back to
the `HEAD` tree this build computes and says so as `baseline="git-HEAD (foreign sidecar ignored)"`, with one stderr line
and a legend sentence naming the two ways back (run the delta with the build that pinned it, or re-pin on a clean tree
(commit or stash first)). Unlike a stale pin the file is never deleted, by the CLI or by the MCP `quality_delta` verb,
because the build that wrote it can still use it. A root with no git has nothing to fall back to and exits 1 naming the
foreign pin. Demoting the dead-code rows instead was ruled out: it cannot surface a regression whose row never appears,
and another build can compute any kind differently. A pin at another commit is still stale first and still self-heals.
On the same two fixed builds all four cross-build runs give the same-build answer: exit 0 and exit 2, both marked
foreign, the sidecar still on disk.

Every existing sidecar is v5, which only a build without the stamp can have written, so the version rule refuses it.
That refusal used to be reported as `baseline="git-HEAD"`, which means no sidecar existed, under a stderr line saying
there was no `.ripwire_quality_baseline`, one line below the line naming the refused file. It now reads
`baseline="git-HEAD (sidecar unreadable)"` with the matching stderr line, and a root with no git no longer says "no
<file>" about an unreadable sidecar on either arm. Upgrading costs one re-pin on a clean tree (commit or stash first).
An older binary also refuses a v6 pin rather than honoring it without its stamp, but reports the refusal the old way, as
`baseline="git-HEAD"` with a line saying there is no `.ripwire_quality_baseline`; the file is intact. A v5 pin left at
an older commit is no longer removed by the stale-pin self-heal: it is refused as unreadable, with two stderr lines on
every run, until it is re-pinned or deleted.

Gate: `test/qbaselineproducercheck.sh`, 26 rows. Matched pairs over a real pin: dead records dropped (or one added)
with the producer kept, a control that must change the answer and does, and the same forgery with one hex digit of the
producer flipped, which must give the no-sidecar answer and leave the file byte-identical. Beside them: an unstamped v6
pin, a v5 pin, a stale foreign pin, a root with no git, the MCP verb, the legend and `--help`. Against the previous
commit 12 rows failed, both forged directions among them. `test/qrevtokencheck.sh`'s hand-written sidecars move to the
v6 header so its hostile head stamps still reach the head-stamp path. Pin moved: `test/printf_parity.manifest`
(`help_all` only, `UPDATE_GOLDEN_EXPECT` matched).

### Fixed — a deep or odd-shaped argument, source file or skills tree could crash or stall a verb

Each of these was reproduced before it was fixed, and the gate that already owns each verb now fails on the old code.

- **`--graph-query` nested deep enough overflowed the stack.** The evaluator recurses once per `(`, and a 50,000-level
  `kind(kind(…all…))` chain died with SIGSEGV (exit 139). Nesting past 256 levels is now refused before evaluation,
  exit 1 with the reason. Gate: `test/graphqueryrefusecheck.sh` arm 6.
- **A `--layout` array extent could crash its evaluator.** A `#define` extent nested 200,000 parentheses deep overflowed
  the stack (exit 139). `((0-1099511627776)*8388608/(0-1))` divides INT64_MIN by −1, which is SIGFPE (exit 136) on
  Linux x86-64, and `1099511627776*1099511627776` is signed overflow, which aborts the sanitizer build. Arithmetic is
  now checked, that quotient is refused, and parenthesis nesting depth is bounded at 64 (a macro of many sibling
  parenthesised terms nests one level and still sizes). Any of these reads as an unknown extent, with its caveat.
  Gate: `test/layoutcheck.sh` §12.
- **`--layout` dropped a data member whose extent or initializer holds a parenthesis, and still said the size was
  right.** `char a[(4)];`, `int x = (3);` and `int x{ (3) };` were taken for member functions, because the test looked
  for the first `(` anywhere in the statement. The field vanished while the struct reported `modeled="1"` and a size
  short by its bytes. Only a `(` before the first `[`, `=`, `{` or bitfield `:` now opens a parameter list, and an
  `operator` member is still a function. Gate: `test/layoutcheck.sh` §13.
- **`--layout` dropped a data member whose declaration carries a `(` that belongs to an `alignas`,
  `__attribute__` or `decltype` specifier, or sits inside a template argument list, and still said the size was
  right.** `alignas(8) int x`, `int x __attribute__((aligned(8)))`, `decltype(1) x` and `std::function<void(int)>
  cb` were all taken for member functions too, for the same reason as the row above: the scan still looked at the
  first `(` in the statement, whichever `(` that was. The field vanished while the struct reported `modeled="1"`
  and a size short by its bytes. That first `(` is now skipped when it opens one of those specifiers or sits
  inside `<…>`; each shape now comes back refused (`modeled="0"`, a named caveat) instead of silently missing.
  Gate: `test/layoutcheck.sh` §14.
- **`--eval-skills` aborted on a skills directory it could not fully read.** A `SKILL.md` symlinked to itself, a
  directory link loop or a mode-000 skill raised an uncaught `filesystem_error` from the throwing
  `std::filesystem` overloads (exit 134). The walk now uses the `error_code` forms, skips an unreadable entry, the
  directory link loop included, and names it on stderr; a skills root that cannot be listed at all says "cannot list".
  Gate: `test/skillevalcheck.sh`.
- **`ripwire wrap` aborted on a `./skills` tree it could not descend.** The pre-recipe scan advanced a
  `recursive_directory_iterator` with its throwing `operator++` inside a `noexcept` function, so a tree it could not
  open mid-walk (measured with more nested folders than free descriptors) was `std::terminate` (exit 134). The walk
  now stops early instead, says so, scores the scan WARN and still prints the recipe. The same scan used to skip a
  mode-000 skills folder in silence — a skill carrying injection text scored CRITICAL while readable and nothing once
  sealed — and now names the folder it cannot enter and scores WARN. Gate: `test/codexwrapcheck.sh`.
- **A deeply nested `--match` query overflowed the query compiler.** `ts_query_new` recurses per level on a worker
  thread with a 512 KB stack: 4,000 levels died with SIGBUS (exit 138), and 2,000 ran past a minute. A query or
  `--lint-rules` spec nested past 256 levels is refused before any compile. Gate: `test/matchgrammarcheck.sh` arm 6.
- **`--slice` and the MCP `slice` verb stalled on a deeply nested function.** Every occurrence climbed to its
  statement anchor through `ts_node_parent`, which descends from the tree root each time, so the walk's cost grew with
  the cube of the nesting: 1,000 chained `if (x)` took 5.7 s, 2,000 took 48 s, and 4,000 did not finish. Over MCP that
  one call wedged the server, and a real CPython test method (a chained assignment 808 levels deep) took 21.8 s. The
  scan now builds a parent table in one cursor pass and memoizes the anchor, so the walk is linear: 2,000 / 4,000 /
  8,000 nested ifs in 0.05 / 0.06 / 0.08 s, the 808-level chain in 0.06 s, and the output is byte-identical. Past
  2,048 syntax levels the slice is refused by name: the walks still recurse once per level on the main thread, and
  nested loops, the widest frame per level, need ~1.8 MB at that depth on a plain build and 2-3× under a sanitizer, so
  this is a stack guard, not a time guard. That is still 2.5× the deepest function in 47,795 parsed files (808).
  Gate: `test/slicecheck.sh` (15), including 2,040 nested `for` loops that must be answered just under the guard.
- **That stack guard is now a heap one — `--slice`'s walk no longer recurses at all.** The scan above made the walk
  linear but it still cost one C++ stack frame per loop/if/switch/try/block nesting level, so under ASan (frames
  2-3× wider) 2,040 nested `for` loops needed 18.8 MB against an 8 MB thread and SIGSEGV'd (reproduced with the
  caller's stack held to 1 MB, `ulimit -s 1024`: rc 139). `SliceRdWalker` (the reaching-definitions pass) and the
  occurrence scan's own `sliceWalk` now run on an explicit heap work stack: every descent into a child node pushes a
  continuation instead of recursing, so nesting depth grows a `std::vector`, never the calling thread's. Two defects
  surfaced and were fixed before this shipped: passing the pending continuation by value at the one dispatch point
  reached on every level copied it — and copying a continuation copies everything it closed over, so a 2,040-level
  chain went quadratic in CLOSURE COPIES (1,000 nested `for` loops: 0.02 s → 12 s); and the loop fixpoint's own
  per-round locals, arena-allocated like everything else, were never freed when an outer level's fixpoint redid an
  inner loop's body, so superseded rounds piled up (2,040 nested `for` loops: 2.6 GB against the recursive form's
  13 MB). Both are fixed — the continuation is passed by reference, and a loop's own per-round state is
  `shared_ptr`-owned so a superseded round frees the moment its closures finish, the same lifetime the recursive
  form's stack gave for free. Verified byte-identical to the recursive form on 198 real definitions (790 slice
  calls: ripwire's own `src/`, two other local C++/Python trees, and the `#252` parity fixture set) and timing-
  neutral on the same set (interleaved, real total time within 1%). The 2,048-level guard is unchanged: it is a
  safety margin now rather than a strict necessity, but the walk's fixpoint cost is still super-linear in nesting
  (measured: 8,192 nested `for` loops, 48 s), so raising it further is a time risk, not a safety win. Gate:
  `test/slicecheck.sh` (15a)/(15b) run under `ulimit -s 1024` (red on the pre-fix binary at (15b), SIGSEGV).

The four new bounds are listed in `docs/LIMITS.md` as BOUNDARY.

### Changed — the macOS arm64 release and the macOS CI legs build with Xcode 26.6, whose loop vectorizer reads the no-alias promises

Through 0.6.1 the `macos-arm64` release asset and every macOS CI leg were built with Xcode 16.2 on `macos-14`. Its
AppleClang 16 is LLVM 17, and LLVM 17's loop vectorizer never reads `__builtin_assume_separate_storage`
(llvm/llvm-project#64666, fixed in LLVM 18). There, a `VERIFY_NO_ALIAS_BUF` promise removed scalar reloads but left each
vectorized loop's runtime overlap check and its scalar fallback in place. The release leg, the eight macOS gate shards
and the macOS sanitizer leg now build with Xcode 26.6 (17F113, Apple clang 21.0.0), the default Xcode on `macos-26`.
GitHub retires the `macos-14` images on 2026-11-02. On Xcode 26.6, with no flag beyond the release's own
`-O2 -mcpu=apple-m1`, a two-buffer loop carrying the promise vectorizes with no overlap check. objdump counts 57
instructions against 64 for the same loop without the promise, and 64 again with `-mllvm -basic-aa-separate-storage=false`.
`test/noaliascheck.sh` classifies this compiler `CONSUMED_DEFAULT` and `LOOP_CONSUMED`. No speed is claimed: the promises
that would use this land later, with the macro rename.

The minimum macOS is now pinned instead of inherited from the runner. With no deployment target, clang takes the lower of
the runner's macOS and the SDK default. The published `ripwire-0.6.1-macos-arm64` binary reads `minos 14.0` (otool), and
the same build on `macos-26` would have read 26.x and dropped every macOS 14 and 15 user. The release leg exports
`MACOSX_DEPLOYMENT_TARGET=14.0` before its PGO build and reads `minos` back off the binary it packages. The CI legs build
at the same 14.0, where Xcode 26.6's libc++ still defines `__cpp_lib_print`. The leg also records its Xcode, compiler and
`llvm-profdata`, and fails if `DEVELOPER_DIR` is empty or either tool is not the pinned Xcode's, so PGO trains, merges and
optimizes with one toolchain. None of these checks skips a leg that lost its pin. A macOS release leg without a
deployment target fails, and so does a CI leg whose CMake cache did not receive the pinned target.

Gate: `test/portablebuildcheck.sh` #2i, sixteen rows. It holds the release leg's runner, Xcode and quoted minimum macOS;
the export before the first configure; a single deployment-target source across the leg and the build job's env and
steps (no `-DCMAKE_OSX_DEPLOYMENT_TARGET`, `-mmacosx-version-min` or second `MACOSX_DEPLOYMENT_TARGET`); the exact
`otool` compare between PGO staging and packaging; and each fail-loudly guard: the empty-target refusal, the toolchain
record step ahead of the first build, and ci.yml's two CMake-cache checks. It also holds ci.yml's nine macOS runner
labels, five `matrix.os` conditions, two Xcode paths and two deployment targets to the release's values, so a half-done
runner move (an `ASAN_OPTIONS` condition still naming `macos-14`) is refused. Three mutated copies must each be refused
by exactly their own row: no minos step, `ASAN_OPTIONS` back on `macos-14`, and `-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0`
added to the pgobuild step. Red before this change: 14 FAIL, 2 PASS. All sixteen pass after.

A local emulation of the release leg on the same Xcode build (`scripts/pgobuild.sh`, Release,
`MACOSX_DEPLOYMENT_TARGET=14.0`) passed every post-step: the PGO determinism diff, `emit=std::print`, `minos 14.0`, and
xmllint. Its output was byte-identical to the plain build on `test/fixture`, the repo map and a `--for` query.

The move also exposed a test-harness defect. Under a UTF-8 locale, macOS 26's `/usr/bin/sort` sorts case-insensitively,
where macOS 14 and Linux sorted these lists in byte order. `test/scroundtripcheck.sh` compared a `sort`ed expected list
with Python's `sorted()` and went red on both macos-26 CI shards. A sweep of every `sort`, `comm`, `join`, `uniq` and
`ls` call in the gate and bench scripts found 27 sites in 20 files that compare an order with something else: Python's
`sorted()`, a literal, a pinned hash, ripwire's own byte-sorted output, or `git status`. Only that one fails today; the
other 26 pass by luck of their current names. All 27 now run under `LC_ALL=C`, and each fixed gate passes under both
`LC_ALL=C` and `LC_ALL=en_US.UTF-8`.

### Fixed — an answer depended on how the root was typed (`ripwire .` and `ripwire "$PWD"` disagreed)

Reported by **@hnipps** in #228: `--quality-delta` on an unchanged tree gated. Part of that report is how the root is
spelled, and it was a graph defect, not a delta one. The crawl stores every path with the root exactly as typed, and the
include/import index and the path predicates read that spelling raw. Three things followed. Python's root-relative
import probe joined onto an empty base, which is the crawl root only under `ripwire .`. Under `"$PWD"`, which is every
MCP session and the `--quality-delta` HEAD side (always an absolute temp root), `from pkg.store import load` stopped
resolving and the name ladder bound a same-directory `load` instead. A root typed `../repo` lost every include and
import edge in every language, because `lexicalNormalize` refuses a path that starts above its base. And a checkout that
merely lives under a `tests/` or `fixtures/` directory had every file tagged `layer="test"`, exempted from dead-code and
seeded as a test under an absolute root, and none of that under `.`. The fix is one seam: `ingest()` records the root
once, and `rootRelPath` (`src/model.h`) gives the root-relative view (a prefix strip, no syscall, no allocation). The
include/import index, the Python/JS/C declaration indexes, the module vocabularies, the test, fixture, layer and tier
predicates, the path-mention and stack-trace suffix matches, the `--lint` byte cap and the map's byte model now read
that view. Stored and printed paths are unchanged. `rootRelativeUri` also trims a trailing `/`, so `--pack-task` rows
stop printing the whole absolute path under `"$PWD/"`. On a shallow Django clone (2b30f62, 3,449 indexed files,
`--no-cache`, map header), `"$PWD"` went from 62,591 edges, `ambiguous=3135` and `declined=49153` to what `.` always
gave: 74,972, 5,958 and 40,681: 12,381 more (caller, callee) edges, and more calls reaching a definition set at all,
which is why the ambiguous gauge rises with them. On the same clone, `--quality-delta` with a fresh cache gated 14 rows
under `.` and `./`, 8 under `../dj` and 0 under `"$PWD"`; it now reports 0 under all four. A `--top-k=300` map flipped
to `order=important-last(auto:fill)` under `"$PWD"` alone and now agrees. Rooting at a test directory now answers the
way `cd tests && ripwire .` does: `ripwire tests/` no longer counts its own files as tests (no `layer="test"`, no test
seeds for `--affected`/`--test-gate`, no dead-code exemption). The `.` answer itself moves slightly on byte-capped
output, because the byte models now charge a path as printed: the default `--lint` page on this repo went from 680 to
689 rows. `kQSnapCacheScheme` moves 12 → 13 so a HEAD Snapshot computed before this fix is never served.
`test/rootspellingcheck.sh` holds six spellings (`.`, `./`, `"$PWD"`, `"$PWD/"`, a symlink and `../name`) to
byte-identical output, once the printed `root=` and `est_tokens=` are normalised, across the committed four-file repro,
eight language import fixtures and a C++ header selector whose answer rests on an include proof. It also checks a
tests/fixtures placement, a real-edit sensitivity arm and, given a pre-fix binary, the scheme upgrade. On origin/main it
fails 57 of its 86 rows. The checkout-shape half of #228 (export-ignore, submodules, sparse checkouts, skip-worktree,
`--no-ignore`) stays open.

### Fixed — a cached enum byte past its enum's last value was believed, and a span-tier memo byte wrote past a stack array

Two on-disk readers built enums straight from bytes with no range check. **The ingest cache** read ten of them —
`SymKind` and `Lang` on a definition, `Lang`/`RecvKind`/`RefRole` on a reference, `Lang`/`LocalBindKind` on a
binding, `BindKind` on an FFI alias, `HttpMethod` on both route records. **The span-tier memo** (`ripwire-stier-*`,
the `--grep` classifier's per-file blob) read one `SpanTier` byte per span.

What an out-of-range value did, measured on the unfixed binary at `3bf884e2` over a 15-file fixture
(`test/fixture` + `test/ffifix` + `test/routeedgefix`), one field class set to 255 at every site with every digest
rebuilt, 24 verbs each diffed against `--no-cache`: every record was accepted (`cached_records=15` of 15), and the
answer changed on 18 verbs for `SymKind` (served as `t="other"`; a field became a map symbol), 18 and 17 for a
definition's and a reference's `Lang`, 17 for `RefRole` (a call demoted to `role="read"` and out of the call graph),
13 for `RecvKind`, 12 for `BindKind` and 11 for `LocalBindKind`. A `Lang` of 32 or more is also undefined behaviour:
`src/clones.h:135` shifts a 32-bit language mask by it, and UBSan stops `--for`, `--clones`, `--readability` and
`--pack-task` there. The memo was worse: a tier byte of 3 or more indexes the three-element per-tier hit counter in
`grepApplySpanTiers` (`src/search.h:2174`), an out-of-bounds **write** on the stack that AddressSanitizer reports as
`stack-buffer-overflow`, and the plain binary served a different `--grep` answer.

How reachable, stated plainly. An ingest-cache record is covered by its own 32-bit digest and the offset table by
another, so a random bit flip is refused before any enum is read; an out-of-range byte gets there only from a blob
written wrong or edited with its digests rebuilt — a committed team artifact handed to `--cache=`, a copied cache
directory. For that cache this is defence in depth, and hardening rather than an integrity boundary: a blob whose
digests were rebuilt can still carry wrong in-range facts. The span-tier memo is read ONLY from the per-user cache
directory ladder (`$TMPDIR/ripwire`, `$XDG_CACHE_HOME/ripwire`, `/tmp/ripwire-<uid>`; mode 0700 and owner-checked,
failing closed otherwise), never from a repository or a `--cache=` path, so a cloned repository cannot supply one;
reaching the out-of-bounds write took storage corruption or a write by the same user. And the memo still has **no
checksum**: an in-range flip (a tier re-labelled, a span offset moved) is still believed and still changes a
`--grep` answer. This change bounds out-of-range bytes only.

Every enum byte is now validated at the read. The ingest readers go through one helper, `ByteR::enumU8`, which folds
a failure into the reader's existing `ok` flag, so the record takes the refusal path a short read already takes:
that file reparses and the rest of the blob stands. The memo refuses the whole blob and re-parses the file. Each
bound is a count constant beside its enum (`kSymKindCount`, `kRecvKindCount`, `kRefRoleCount`,
`kLocalBindKindCount`, `kBindKindCount`, `kHttpMethodCount`, `kSpanTierCount`; `kLangCount` already existed), and
each is proven exact at compile time by `src/infra/enumcount.h`, which asks the compiler whether `count - 1` names
an enumerator and `count` does not. So appending an enumerator without moving its count is a build error, not a
validator that quietly refuses the new value's every record. The proof is evaluated under clang only; GCC's
spelling was not verified, and the macOS and Linux clang legs carry it. On `-DNDEBUG` Apple clang the warm load
function `loadCache` grows from 3,936 to 3,962 instructions: the checks become compares folded into the `ok` flag
with `csel`, plus 4 conditional branches. No cache format, `kCacheVersion` or parser version moved.

`test/cachefuzzcheck.sh` gains Part 3 and Part 4. Part 3 changes ONE enum byte per field class in an otherwise
valid blob, rebuilds every digest, and asserts that the one record is refused (`cached_records` 14 of 15), that
the output is byte-identical to `--no-cache`, and that the ASan binary with `--clones` stays silent. An in-range
edit of the same byte must be accepted (15 of 15), which proves the refusal comes from the range check and not
from a digest. The enumerator counts are read from `src/model.h`, not written into the gate. Part 4 does the same
for a memo tier byte, and its control re-labels a comment span as code, which changes the answer. Against the
unfixed binaries the new arms gave 27 FAIL rows: 20 accepted mutants, the `clones.h:135` UBSan report, the
`search.h:2174` stack-buffer-overflow, and the memo serving a different answer. Against the fixed build the whole
gate is 161 PASS, 0 FAIL.

### Fixed — git runs with the file-system monitor off, temp files are created exclusively, and edit-plan reads the path it confined

- ripwire runs its git commands with `--no-optional-locks -c core.fsmonitor=false`; the one read of that setting
  runs without them, since the flag would mask the value it reads.
- the atomic-publish writers create their temp file exclusively and without following a symlink.
- `--edit-plan` reads a payload through the same confined path its containment check judged.

### Fixed — a `--pin-census` row no longer splits on a line break, TAB or `|` inside an id

A C++ out-of-line member of a class template whose template-argument list spans source lines has a scope that holds
the line break verbatim, and the census wrote it raw. One `C` row became a six-field line plus a continuation line
starting with neither `C`, `S`, `O` nor `#`, and the symbol's `S` row broke the same way; a reader splitting lines
dropped or mis-keyed the site. It was seen once, on a large private C++ corpus. The map was never affected: it writes
the same scope as `&#10;`. Five more spellings of the defect reproduce on the pre-fix binary: a TAB or a form feed
inside the argument list, a backslash line splice, CRLF source, and a `|` inside an id. `|` separates targets, and on
this repository that case is real: Markdown heading symbols such as ``--token-budget=N[K|M|G]`` made a `|`-split read
18 single-target rows as two to six targets.

Every id and callee field is now escaped. A backslash is written `\\`, TAB, LF and CR are `\t`, `\n` and `\r`, and every
other control byte and `|` is `\xHH`. Nothing else changes, so the columns are the same and an id without those bytes
is spelled exactly as before. The first line now reads `pin-census v3` and the header documents the escape.
`bench/scip_match_diag.py` decodes the fields, because it opens files by an id's path; `bench/scip_pin_precision.py`
joins ids as opaque keys and needs no decode.

Measured by running the pre-fix and fixed binaries with `--pin-census --no-cache` over a clean export of this
repository at `a55b118e`: 99 of 51,821 rows change, 18 `C` and 81 `S`. 98 of them hold a `|` and one holds a backslash,
each decodes back to its pre-fix bytes exactly, and every other row is byte-identical. Before the fix all 18 of those
`C` rows had target lists a `|`-split misread; after it, none do. Gate: `test/pincensuscheck.sh`
arm (L), over a generated fixture. Every non-comment line must be a `C`, `S` or `O` row with its full field count, and
the check also runs over arm (B)'s and arm (G)'s censuses. Each awkward caller id must decode to its source bytes,
re-encode byte-identically and appear verbatim as an `S` id. The `|` target must split into one id, and the
dispositions and summary counts must agree with what a line reader parses. Against the pre-fix binary the gate printed
12 FAIL rows: a line reader parsed 2 of 6 decision rows and 12 of 16 symbols.

### Fixed — a member call through a typed parameter was pinned to the caller's own class

`int Decoy::plainCaller( Target& other ) { return other.pick( 1 ); }` answered `--callees=plainCaller` with one edge
to `Decoy::pick` — precise, no `amb=`, nothing disclosed, and wrong. Rule 2 narrowed a receiver only through a typed
LOCAL; a parameter's written type had been captured since the member-variable round but was read only by the field
use-site index, so the call fell through to the name ladder, whose locality tie-break hands a same-file tie to the
caller's own class. The same call through `Target other;` resolved correctly.

Rule 2, and CHA-lite with it, now reads the written type of a parameter, a lambda parameter, a typed range-for
variable and a reference local LEXICALLY: the innermost declaration of the name whose scope covers the call site
decides, and only a written, unqualified type narrows. Both limits were measured before they were chosen. Folding
these types into Rule 2's flat per-function table minted three precise wrong edges on the gate fixture — a range-for
variable's type reaching a later `auto` loop of the same name, a same-named field read after the loop, and a
parameter hidden by an untyped loop variable. And a written type is recorded as its final segment against class
names that carry no namespace, so `const std::map<K, V>& ref; ref.lower_bound( q )` narrowed to an unrelated in-repo
`map`: three such edges on a private C++/ObjC++ corpus of 129,759 call sites, which refusing qualified types removes
at the cost of 11 correct narrows through namespace- or class-qualified in-repo types (those sites keep their previous
answer). An include-visibility guard was measured first and rejected: path-precise includes miss include-root
spellings such as `"LinearMath/btVector3.h"`, and it refused about 150 correct narrows on that corpus to stop the
same three. The qualified text rides the declaration's record, so **kParserVer moves 96 → 97** and a warm cache is
reparsed once.

Measured with `--pin-census --no-cache`, the `main` binary at `f8e6087c` against this change, on that corpus: 587 call
sites change target — 373 splits narrow (300 to a Rule-2 pin or the type's own overload set, 73 through the CHA cone), 147
calls the ladder had declined gain an edge (`bound=` 80,432 → 80,583, `declined=` 17,552 → 17,401), 66 pins or splits
that did not contain the parameter's type move to it (40 of them `unique` pins to the one same-file method of the
wrong class), and one edge is lost — a friend function ripwire scopes inside its class, which the parameter's type
then names as the caller itself. 956 more sites keep their target and are now decided by Rule 2. Every category was
sampled and read against the source. On this repository's `src/`, 53 splits become one Rule-2 pin and nothing else
moves target. Wall time is unchanged within noise (three cold runs each on the same corpus, 1.66–2.51 s both).

`test/narrowcheck.sh` arms 7-18 are the gate: nine rows red on `main`, arms 12-14 red on the flat-table fold, arm 17
red on the lexical lookup without the qualifier guard, arm 15 asserting through the census that the site is decided
by Rule 2 rather than the locality tie-break. Five gates' controls were built on "a parameter has no binding" and now
use an untyped `auto` receiver — `narrowcheck`, `chacheck`, `chaconecheck`, `localitycheck` (whose call no longer
reached the tie-break it exists to test) and `resolverhonestycheck` F9 (whose `check_signal` row had gone vacuous on a
single edge). `fieldnarrowcheck`'s ambiguity gauge moves 7 → 6 because `shadowParam( Decoy& m_x )` now resolves to the
parameter's type, and its arm (s1) now also asserts that the shadowed field's `Pool::acquire` is not linked. Still
open, and unchanged by this entry: an untyped receiver (`auto x = make(); x.m()`) still reaches the locality
tie-break, and a typed LOCAL still reads the flat table, qualified-type collision included.

Two floors this change does NOT remove, stated because the first one moves edges the wrong way.
**An abstract parameter type narrows onto its namesakes.** Rule 2 resolves `m` against definitions only, so a parameter
typed as an interface whose methods are pure-virtual declarations cannot narrow to it — and when unrelated classes
share the interface's final name segment and define `m`, the narrow lands on them instead. On rocksdb at
`0e2801ac3`, `--pin-census --no-cache` with the `main` binary at `f8e6087c` against this change: 79 call sites
(88 census rows) through an `Iterator*` parameter, such as `AssertItersEqual( Iterator* iter1, Iterator* iter2 )` in
`utilities/write_batch_with_index/write_batch_with_index_test.cc`, now split five ways over the nested `Iterator` classes in
`memtable/` (`skiplist.h`, `inlineskiplist.h`, `skiplistrep.cc`, `vectorrep.cc`, `hash_skiplist_rep.cc`), and none of
the five is right. Before this change 25 of them were a unique pin to a plausible override (`BlobCountingIterator::key`),
26 were a different split over overrides, and 28 had no edge. Every one is disclosed (`amb=`, `prov="split"`), but
each is a wrong answer rather than a missing one, and 28 are new edges. It is the same final-segment collision typed
locals already have on `main`; this change extends it to parameters. **A call in a constructor's member-initializer
list is not narrowed:** `Decoy( Target& t ) : v( t.pick( 3 ) )` sits outside the parameter's scope span (the body),
so it keeps `main`'s answer — on a same-named `Decoy::pick`, the locality tie-break's wrong pin.

### Fixed — an explicit receiver of unknown type was pinned to the caller's own class, and a `std::` type narrowed to an in-repo namesake

Two holes the parameter-receiver entry above left open. The S6-C locality tie-break prefers the candidate that shares
the longest segment prefix with the caller — same file, then same class — and granted the class credit to every
named receiver on the premise that a typed one had already been narrowed. A receiver no rule typed never was:
`auto other = make(); return other->pick( 1 );` inside `Decoy` answered one precise edge to `Decoy::pick`, no `amb=`,
and delegation through a member whose type Rule 2b cannot read (`rep_->Name()` inside `Wrapper::Name`) did the same.
Such a receiver — an untyped local, a member of an unreadable type, or a typed variable whose type defines no such
method — now keeps the file and directory credit and loses the scope segments, so the call is the split it is.
Skipping the tie-break outright for these receivers was measured too: it moved no target on any corpus below, and
relabelled every tier whose one competitor is the caller itself from `locality` to `unique`, dropping its `lpin=`
disclosure — so the file credit stays.

The second hole: a written type is recorded as its final segment, matched against class names that carry no
namespace. The entry above refused every qualified PARAMETER type; typed locals kept narrowing, so
`std::map<int, int> table; table.find( k )` pinned an in-repo `map::find`. Measurement overturned the blanket rule
instead of extending it, and **this entry supersedes the parameter rule stated above**: where that entry says only a
written, unqualified type narrows and that qualified in-repo types keep their previous answer, a parameter now refuses
only a type written in namespace `std`, exactly as a local does. Refusing any qualifier on locals would have refused 424 narrows on rocksdb
(`ROCKSDB_NAMESPACE::Status s; s.ok()`), 11 on a private C++ corpus and 9 on this repository's `src/` — every sampled
one correct — while the only wrong edges it removed on all three were six `std::map` locals. `std` is reserved to the
implementation, so no in-repo class is a `std::` type: a type written in namespace `std` now never narrows — for a
parameter, a typed local, a constructor-inferred local, and a C++ assignment from a constructor, whose record did not
carry the qualified text until now (**kParserVer 97 → 98**). Every other qualifier narrows on its final segment,
parameters included again. Stated floor, pinned by `test/narrowcheck.sh` arm 24: a qualifier that is neither `std`
nor the class's own namespace — an external or alias-template type whose final segment an in-repo class shares —
still narrows by name. Closing it needs the namespace chain in `Symbol::scope`.

That floor is disclosed on every edge it can produce. A narrow decided by a qualified, non-`std` written type matched
the type's last name and never checked its qualifier, so its edge carries **`prov="final-segment"`** — a parameter or
a local, through Rule 2 or CHA-lite's cone — and both map legends define it. The wrong edge arm 24 pins and the correct
`store::tree&` narrow beside it read the same way, as a guess, not as a uniquely resolved name. Byte cost on rocksdb,
the previous commit's binary against this change, the only differences being the attribute, the legend term and
`est_tokens`:

| rocksdb output | before | after |
| --- | --- | --- |
| default map | 31,366 B | 31,711 B (+345, +1.10%; 14 marked edges) |
| `--for="write batch handler mark commit"` | 8,746 B | 8,746 B (the bundle carries no `prov=`) |
| whole graph, `--top-k=100000` | 5,406,160 B | 5,413,666 B (+7,506, +0.14%; 355 marked edges) |

A private C++ corpus's default map pays only the legend term (+51 B, no marked edge printed). The Iterator-shaped
collision #248 states above is unchanged: those calls stay `amb=`-disclosed splits. A name-only collision guard was
measured against them and rejected — it moved 967 rocksdb rows off the wrong `memtable` namesakes, but declined 58
correct platform-alternate splits (`port::Mutex::Lock` over posix and win) and 8 correct `log::Writer` narrows, minted
10 new wrong unique pins on rocksdb, and declined 132 correct `Template.render` splits on django. The namespace chain
is the fix for both.

Measured with `--pin-census --no-cache`, the previous commit's binary against this change, with sampled rows of every
category read against the source. rocksdb: 211 call sites change target — 117 locality decisions become splits or wider
ones (14 of 14 sampled pins were wrong), and 94 sites narrow through in-repo qualified parameter types the blanket guard
refused (`WriteBatch::Handler* handler; handler->MarkCommit( xid )` had been pinned to `WriteBatchInternal::MarkCommit`);
`bound=` 200,009 → 200,036. The private C++ corpus: 88 — 70 locality decisions widen to splits (14 of 16 sampled pins
were wrong; one of the two right ones is now a three-way split that keeps it), 6 `std::map` locals stop narrowing to an
in-repo `map`, and 12 in-repo qualified parameters narrow, one of them an `ankerl::unordered_dense::map<…>&` alias
template that lands on that in-repo `map` again: the floor above. django: 72 locality pins become splits; rails: 145.
The removed pins were less often wrong in the dynamic languages, as an independent review's samples show: django 8 of 14
wrong (`target_ids.add`, `params.get`, `form.save`) and 6 right (`copy.set_source_expressions`, `cls._pre_setup()`);
rails 8 of 12 wrong (`pair.freeze`, `connection.create_table`) and 4 right (`set.each`, `model.history`). Every right
target stays inside the split that replaces it. Python's `cls` is a named receiver, so a classmethod's `cls.m()` splits
too (2 of django's 72). This repository's `src/`: 5 splits become Rule-2 pins through `notes::`- and
`rw::quality::`-qualified parameters. vue-core and Go's `net` package: none. The assignment capture moved no site on
these corpora; its arm is the only witness. Wall time on rocksdb is within noise (three cold runs each at load average
42: 1.69–2.19 s before, 1.73–2.80 s after).

`test/localitycheck.sh` arms 5-9 and `test/narrowcheck.sh` arms 17-25 are the gates: localitycheck 5, 6 and 7 red on
the previous commit and 8 red on the skip-the-tie-break variant; narrowcheck 19, 20, 21, 23 and 24 red on the previous
commit, 21 red without the assignment capture, and 25 (the attribute on arms 22-24's edges and in both legends, absent
from an unqualified narrow and a uniquely named call) red before `prov="final-segment"` existed. Two gates moved for the reason the fix exists. `clsrecvcheck`'s
three non-firing controls (B), (C), (E) asserted that the caller's own `Box::validate` pin STANDS for
`item.validate( v )`; they now assert the honest two-way split, which keeps the contrast with the route that fires, and
(F) reads `ambiguous=3` with no locality pin. localitycheck's HIGH-1 probe was an untyped local that no longer earns
the scope credit, so it could no longer tell a byte-prefix tie-break from a segment-aware one; it is `this->go()` in a
class template with a dependent base now, and a census row asserts the call still reaches the tie-break holding both
candidates. `chacheck`, `chaconecheck`, `resolverhonestycheck` and `fieldnarrowcheck` pass unchanged: their untyped
controls sit in scope-less free functions, which never reach the tie-break.

### Fixed — a member field typed `std::string` narrowed to an in-repo class named `string`

The entry above stopped a type written in namespace `std` from narrowing a parameter or a local. A member field is the
third place a written type is read, and it still did. The field capture records a qualified type's final segment, so
`struct Record { std::string name_; int nameLength() { return name_.size(); } };` recorded `name_` as a `string`, and
all three readers of that record took it for any in-repo class of that name: Rule 2b pinned `name_.size()` to the
in-repo `string::size` (census `receiver-rule` — one precise edge, no `amb=`), the HAS-A block drew `Record → string`,
and `--uses=string.len` pinned both `name_.len` and `this->name_.len` to that class. A field's compose record now
carries the namespace its type was written in as its qualifier — the same (name, immediate qualifier) pair a call
carries, so `std::string` is `string` in `std` (**kParserVer 98 → 99**) — and the readers refuse `std`: the field-type
table records no type for the field, and no HAS-A edge is drawn. Every other qualifier narrows as before:
`store::Text body_; body_.size()` still reaches `Text::size`.

The std field records an empty type rather than being skipped, and that choice was measured. Dropping it at capture —
the obvious fix — un-tombstones a same-named class's differently-typed field. rocksdb has two classes named
`StringSource`: `test_util/testutil.h`'s holds `std::string contents_` and `db/log_test.cc`'s holds `Slice& contents_`.
Class names carry no namespace, so both share the entry `StringSource#contents_`, and the disagreement is what keeps
either from narrowing; with the std record skipped, four `contents_.size()` calls in testutil.h pinned `Slice::size`.
The empty type tombstones the entry exactly as a second real type does.

Measured with `--pin-census --no-cache` and the default map, the previous commit's binary against this change: rocksdb,
a private C++ corpus and this repository's `src/` (a frozen copy, so both binaries read one tree) are byte-identical in
both, and so is rocksdb's `--metrics`. None of them has an in-repo class that shares a `std::` field type's name and
defines the member called on it: counted with `--match`, rocksdb has 1,258 fields whose type is written `std::X`,
`src/` 1,987 and the private corpus 143, and only rocksdb's 1,116 `std::string`/`std::wstring` fields share a name — with
gtest's `typedef ::std::string string`, which has no members and drew no HAS-A edge. So a probe measured the reach: a
copy of rocksdb plus one `namespace shim { struct string { … } }` defining `size`, `empty`, `data`, `c_str`, `clear`,
`append` and a field `len`. There the previous binary pins 384 call sites to `shim::string` by receiver-rule and this
change leaves 7, all gtest parameters written `const ::string&` — the global namespace, not `std`, and not fields. Of
the 357 sites that move, 279 land on exactly the row the unmodified rocksdb census has; the other 78 are `c_str` calls
the probe's own second `c_str` definition makes ambiguous. 455 class rows lose a composed type from `cbo=` (446 by
one, 9 by two).

`test/fieldnarrowcheck.sh` arm q is the gate. q1 (Rule 2b), q3 (HAS-A) and both q5 rows (`--uses`) are red on the
previous commit; the in-repo qualified controls q2, q4 and q6 are red on a refuse-every-qualifier variant; and the four
q7 rows — the StringSource collision in both record orders — are red on the skip-at-capture variant, the only arms that
variant turns red. `qschemetripcheck` is re-pinned for the parser version, as its own message directs.

### Fixed — `--uses=Owner.field` pinned a read through a `std::` local or parameter to an in-repo namesake

The entries above stopped a type written in namespace `std` from narrowing a call through a local, a parameter or a
member field. The member use-site index keeps its own table of local and parameter types, and that table still read the
final segment alone. Given an in-repo `struct pair { int first; int second; };` and a second owner of `first`,
`std::pair<int, int> p; return p.first;` and `const std::pair<int, int>& q` → `q.first` both answered
`--uses=pair.first` as pinned: one owner, no `owner_candidates=`, and wrong. The table now records a `std::` type as a
tombstone, as Rule 2's own table does, so such a read is the split it is (`owner_candidates=2`, one per owner of
`first`). A second declaration of the same name in that function is tombstoned with it rather than handed every site.
A tombstoned local also no longer falls back to the enclosing class's same-named member. `std::pair<int, int> p`
inside a method of a class whose member `p` is a `pair` used to answer through the member's type. But the local hides
that member, and the table cannot tell which of a function's declarations a site sees, so a local declared twice with
different types now answers the same split. Every other qualifier still narrows: `store::Text t; t.len` pins
`Text.len` against a second owner of `len`. Ingest already recorded the qualified text on both kinds of record, so the
parser version does not move.

Measured with a scratch dump of the index for every field whose name is read through a receiver whose type record this
change can alter (one written in `std`, or two that disagree), the previous commit's binary against this change. Three
corpora are byte-identical: this repository's `src/` (a frozen copy; 1,169 fields, 57,511 sites), rocksdb (824 fields,
84,617 sites) and a private C++ corpus (1,811 fields, 393,336 sites). So are `--pin-census` and the default map on
`src/` and rocksdb; the call graph never reads this table. None of those corpora has an in-repo class named after a
`std::` type that declares the member read through one. So a probe measured the reach: a copy of rocksdb plus
`namespace shim { struct pair { int first; int second; }; }` and a second owner of both names. The previous binary
pinned 110 rocksdb reads to `shim::pair` (53 `.first`, 57 `.second`, such as `std::pair<IOStatus, std::string> res;
res.first` in `env/env_chroot.cc`), and every one was wrong, because no rocksdb code declares a `shim::pair`. This change
turns all 110 into two-way splits and pins no site that was not pinned before. Six of them, sampled across files, were
read against the source, and all six are `std::pair` locals or parameters.

`test/fieldusescheck.sh` arm J is the gate, on its own fixture. It covers a `std::pair` local, a `std::pair` parameter
and a `::std::pair` local, a `std::string` receiver two hops deep, one function declaring both `std::pair v` and
`pair v`, `std::` locals and parameters that hide a member, and a non-std double declaration. The previous commit's
binary fails three of its rows. Three variants of the fix were built to prove each row can fail. Skipping the std
record turns the double-declaration and member-hiding rows red. Letting a tombstone fall back to the member turns
exactly the three `std::` member-hiding rows red (measured before the non-std row was added). Refusing every qualifier
turns only the `store::Text` controls red.

### Fixed — a C++ member call with explicit template arguments is a call (parser version 101)

`r.get<K>( 1 )`, `p->get<K>( 1 )` and `x.template get<K>()` minted no reference at all. Their callee parses as a
`template_method` under the member access — inside a `dependent_name` when the `template` keyword is spelled — and no
C++ reference pattern bound either shape, so the call was dropped at extraction, before `ambiguous=`/`unresolved=`
could count it: a four-line repro answered `--callers=get` count="0" beside count="1" for `r.plain( 1 )`,
`--callers`/`--uses`/`--impact`/`--safe-delete` under-counted every such call, and `--quality-delta` could report a
method reached only this way as `kind="dead-code"`. A new `queries/cpp/tags.scm` pattern binds both shapes, and the
receiver reader now steps over the wrapper — without that step `other.pick<int>()` reads as a bare call and the
enclosing-class rule binds it to the caller's own same-named method. The qualified dependent spelling had the same
defect family in another place: `X::template make<int>()` was extracted under the NAME `template make`, which
resolves to nothing, and `X::template Rebind<int>::f()` keyed its qualifier as `template Rebind`, so a same-named
definition in another scope split the call. The keyword is now stepped over in both halves. Free `f<T>( x )` and
qualified `ns::f<T>( x )` (the `std::get<0>( t )` shape) were already bound and are unchanged.

Measured with the pre-fix (`f8e6087c`) and fixed (`1171f775`) binaries, `--no-cache`, map header plus
`ripwire_probe`'s reference total. On this repository's `src/` (169 files) the change is small: references 168,457 →
168,463 and edges 18,308 → 18,309 — the six `r.pod<T>()` reads in `src/gitoracle.h`'s cache loader, so `--uses=pod`
goes 1 → 7. On a template-heavy tree it is not small. `clang/include` plus `clang/lib` from llvm-project `4d5358b1d`
(2,515 files) gains 10,175 references (1,855,925 → 1,866,100), 3,907 edges (409,860 → 413,767, +0.95%) and 972
`ambiguous=` (81,601 → 82,573), with `unresolved=` unchanged at 3,893; `--callers=getAs` goes 48 → 492 and
`--callers=hasAttr` 45 → 377. On `clang/lib/AST` (155 files) the reference delta, 2,027, equals the `--match` hit count
of the new call shape exactly (`hits_capped="0"`), so extraction moved only the intended class.

The new sites resolve exactly as a plain member call to the same name does, so a name like `getAs` or `hasAttr` gains
its real callers and also that resolver's wrong ones. On the same clang tree `FD->hasAttr<PackedAttr>()` in
`ASTContext::getDeclAlign` binds `Type::hasAttr(attr::Kind)` at `lib/AST/Type.cpp:2026`, not `Decl::hasAttr<T>()`,
with no `amb=` on the row. The plain spelling does the same on main: in a reduced five-file repro, `FD->plainAttr()`
binds `Type::plainAttr(int)` rather than `Decl::plainAttr()`. That is a resolver defect this change widens the reach
of, not one it introduces, and it is not fixed here.

`test/cppqualcheck.sh` §12 adds a corpus, `test/cppqualtmplfix/`, with one literal per spelling plus receiver, arity
and qualifier decoys: 19 of its checks fail on the pre-fix binary, and a mutation build that reverts each of the three
mechanisms (the receiver step, the keyword skip, `callArity`'s hop bound) turns that mechanism's own arms red. The
spellings still not bound are pinned at zero behind a check that each is still written in the fixture: `r.f<0>( x )`
without `template` (tree-sitter reads it as two comparisons, a read of the member), a base-qualified member
`r.Base::f<T>()` / `p->Base::f<T>()` (the plain `r.Base::f()` is absent too, so the gap is not template-shaped), and
`r.operator()<T>()`. `test/callformcheck.sh` row 11, `b.template memberTmpl<int>()`, was pinned as documented-absent
at literal 0 and now pins 1.

`kParserVer` → 101 with `quality.h`'s `kIngestParserVerMirror` in the same commit, assigned in merge order on
integration train 2b (after #244's 100); `kCacheVersion` stays 22, and `test/qschemetrip.hash` is re-derived once on the
train's merged tree with a RE-PIN LOG line.

### Fixed — a class template's out-of-line member is the same symbol as its declaration, and a specialization stays its own (parser version 102)

A C++ member defined out of line on a class template kept the template-argument list in its scope, so `template <class
T> void Box<T>::grow() {}` produced a `sc="Box&lt;T&gt;"` row next to the in-class declaration's `sc="Box"`. One member
was two identities. `--callers=Box::grow` resolved to the declaration and answered `count="0"` while `use( Box<int>& b
) { b.grow(); }` sat three lines below, and `--impact`, `--uses` and the S6-C locality tie-break missed it the same
way. An argument list broken over lines put the line break into the `--pin-census` id, and a list that itself holds
`::` was cut inside it: `template<> void Slot<std::string>::clear()` was scoped `string>`. On the reference side,
`Factory<int>::make()` qualified as `Factory<int>`, which keyed nothing, so the call split onto an unrelated
`Decoy::make`.

Scopes now follow what the declaration is:

- A primary template's out-of-line member keys the bare template name, because its template-id names exactly the
  parameters its own `template <…>` introduces (`template <class T, int N> void Box<T, N>::grow()`).
- An explicit or partial specialization keeps its template-id, spelled canonically. Whitespace and comments are dropped
  except between two identifier characters, and a comma is followed by one space, so `Traits< int >` and a list broken
  over lines key the same identity as `Traits<int>`.
- A call keeps the template-id it writes. `Traits<int>::encode( 1 )` resolves precisely to the int specialization,
  including from a 3-segment spelling.
- When no definition is keyed by the written id, the resolver answers from the template's family (the primary and its
  specializations), but only when that answer cannot be missing a body the call may reach. The family is the primary's
  own or inherited member (`CastInfo` inherits `CastIsPossible::isPossible`) plus every specialization's own or
  inherited member, and a member reached through a base is widened to that base template's specializations. A written
  id that names an existing specialization which does not define the member answers with what that specialization
  inherits. With nothing visible from the primary, only a split of two or more specializations answers.
- Anything else goes to the bare-name ladder, exactly as before, so a same-named definition outside the template never
  joins a family answer.
- A specialization header's base clause (`template <> struct Info<char> : CharBase {}`) is now read, as inherit
  references with no new symbol.
- The locality tie-break prefers a candidate declared in the caller's own scope over one nested inside it, for an
  unqualified bare or `this->` call only. Both ids share the caller's `Outer::` segment, so segment counting tied
  `Outer::start` with `Outer::Inner::start`.

Two earlier revisions of this change were measured and revised before merge. Joining every specialization to the
primary made precise edges splits and dropped a delegation between specializations (`DenseMapInfo<APSInt>` calling
`DenseMapInfo<APInt, void>::getHashValue`, APSInt.h:371). A family fallback that ignored inherited members pinned `isa`
(Casting.h:548) to one rare specialization.

Measured with `--pin-census --no-cache` on the same frozen corpus through main (`31e788ce`) and this change, with sites
joined on (caller symbol id, callee, line); symbol ids are identical across the two binaries. On llvm `ADT` + `Support`
+ `lib/Support` (590 files, 37,055 calls), edges moved from 45,768 to 45,001 and ambiguous from 7,247 to 7,237, and
`--callers=lib/Support/APInt.cpp:getHashValue` answers 5, as on main.

Wins: 37 splits became precise, 12 sites that had no edge gained a precise one, 12 external sites resolved in-repo, and
5 precise edges were retargeted. All 66 were read against the source and are correct: 64 in the independent review of
the previous revision (unchanged here), and the 2 new ones, `cast`/`dyn_cast` through `CastInfo<To,
std::unique_ptr<From>>`, which inherits `UniquePtrCast`. The Casting.h `isa` site is now a split that contains the
inherited `CastIsPossible::isPossible`, and the 8 `list_storage` calls that an earlier revision pinned to
`list_storage<DataType, bool>` are splits.

Costs and differences, reported apart:

- 14 sites main resolved precisely now split. In 10 of them main had pinned the wrong class, one correct pin
  (`RHS.branched()`) is a 2-way split that contains it, and 3 are `DominatorTreeBase::dominates` overloads that are now
  one identity.
- One edge is gone: `simple_ilist::sort`, which is a genuine recursive call.
- 4 sites with no edge and 9 external sites became splits.
- One call through `list_storage<DataType, StorageClass>::clear()` (CommandLine.h:1760) keeps main's locality pin to
  `list::clear`, because that primary's members are extracted under `cl` and the template supplies nothing visible.

On dgl (`f0b7cc9`, 343 C, C++ and CUDA files; main at `b1489df4`, whose resolver is identical), edges moved from 20,829
to 20,733 and ambiguous from 1,891 to 1,882. 11 splits became precise. 12 precise edges moved from a specialization's
own `Call` to the `_Sum`/`_Max`/`_Min` base it calls. 3 calls through a dependent template-id that main had pinned to
the primary now split over the primary and its specialization. On this repository nothing changes. An ack or saved
baseline keyed on a primary template member's old `Box<T>` spelling re-keys once.

Gated by `test/cpptmplscopecheck.sh`, 64 checks: main fails 42, and the previous revision fails 6. The gate covers:

- a line-aligned template/non-template twin compared byte for byte across the map, `--callers`, `--impact` and
  `--uses`, and on identities in the census;
- the primary shapes;
- all three specialization forms;
- the review's `Traits` probe;
- an APSInt-shaped delegation;
- the inherited-member shapes (a primary that inherits the member, a specialization that only inherits it, a primary
  with nothing visible, a primary that defines nothing);
- the two-segment decoy;
- the nested-class tie.

### Fixed — a narrow through a qualified field type read as a uniquely resolved edge

The receiver-qualifier entry above marks an edge **`prov="final-segment"`** when the qualified written type of a parameter or a local chose it by its last name alone. A member field is the third place that guess is made, and its edge still read as uniquely resolved. `struct Record { store::Text body_; int bodyLength() { return body_.size(); } };` is an example: Rule 2b narrowed on `Text` and never checked `store`. The disclosure now covers fields as well. Since the std-typed-field entry above, a field's compose record carries the namespace its type was written in. Rule 2b's `Class#field` table now keeps whether any agreeing declaration wrote the type qualified, and every edge a Rule 2b narrow commits on such a field carries `prov="final-segment"`. The narrow itself is unchanged: the mark discloses, it never demotes. An unqualified field narrow skipped no qualifier and stays unmarked, and a `std::` field never narrows. Extraction is unchanged, so kParserVer stays.

Measured with `--no-cache`, the `integration/train-2` binary (92b4c91d) against this change:
- **Decisions:** `--pin-census` is byte-identical on rocksdb, a private C++ corpus and this repository's `src/` (a frozen copy), so no decision moved.
- **Default map:** byte-identical on all three (rocksdb 31,711 bytes), because no newly marked edge sits on a row the default map shows.
- **Full map (`--top-k=1000000`):** marked edges grow 355 → 382 on rocksdb (+27, 567 bytes), 98 → 143 on the private corpus and 80 → 81 on `src/`.

Every sampled new mark is a qualified field type:
- `InternalStats::CompactionStatsFull compaction_stats_` → `SetMicros`
- `toku::locktree_manager ltm_` → `set_max_lock_memory`
- `strkern::Byteset256 heads` → `contains`

`test/fieldnarrowcheck.sh` arm r is the gate:
- (r1) the qualified field's mark and (r5) the compact legend term are red on the train binary.
- (r3), an unqualified field narrow staying unmarked, is red on a variant that marks every Rule 2b narrow and on nothing else.
- (r2) the refused std field and (r4) the unchanged census decision are the controls.

### Fixed — `--version` names the configuration a multi-config generator built, not `dev`

`--version` took its build-type token from `CMAKE_BUILD_TYPE`, which a multi-config generator (Ninja Multi-Config,
Xcode) leaves empty. So a `cmake --build b --config Release` binary said `dev`, although it defines `NDEBUG` and
compiles `DEGRADED_PATH_ALERT` out. Gates that read the token to decide whether the binary can print alerts
(`test/pargates.py`, `kotlincheck` §12 and others) failed loudly on such a binary, so none passed for the wrong
reason, but the token was wrong. Reported by CodeRabbit on #261. On a multi-config generator the token is now the
configuration built (`Debug`, `Release`, …). A single-config configure is unchanged: `cmake -S . -B build` still says
`dev`, and `-DCMAKE_BUILD_TYPE=Release` still says `Release`. The stamp command and both targets' compile flags are
byte-identical to before.

Passing the configuration into the stamp command was not enough, because `version.h` was one file shared by every
configuration. In a cross-config Ninja Multi-Config build (`CMAKE_CROSS_CONFIGS=all`), CMake runs a shared byproduct's
command once. On a two-file probe, the Debug, Release and RelWithDebInfo binaries all printed `Debug`, and against the
real tree the gate read `Release="Debug" RelWithDebInfo="Debug"`. Each configuration now writes its own
`generated/<Config>/version.h`, found before `generated/`. Stamping one configuration no longer rewrites another's
header, so switching `--config` does not recompile `main.cpp` either.

Gate: `test/buildtypestampcheck.sh`. It configures the real `CMakeLists.txt` in scratch trees and builds only the stamp
target. It then asks CMake's File API which `version.h` each configuration's `ripwire` compile would include, and reads
the token from that file. It checks both single-config spellings, and under Ninja Multi-Config (or Xcode when ninja is
absent) that Debug and Release each see their own token in different files. It also checks that stamping Release
leaves the Debug header's bytes and mtime alone, that re-stamping Debug keeps its mtime, and that one cross-config
build gives every configuration its own token. Two controls prove the token extraction and include resolution can
fail. On the old `CMakeLists.txt`, 6 of its rows failed under Ninja Multi-Config and 5 under Xcode. Against the
command-only fix, 4 rows still failed.

The source identity from #255 (`generated/source_identity.cpp`) is one shared file for every configuration. It now has
its own always-run target, `ripwire_source_identity`, instead of being a second command of `ripwire_version_stamp`.
Both commands in one target made a cross-config Ninja Multi-Config build fail with
`'generated/RelWithDebInfo/version.h' … missing and no known rule`, and the gate's cross-config row caught it on the
merged tree. Both stamp scripts also give their temp file a random name. Two builds of one tree used to share
`<output>.tmp`: in 40 concurrent runs of the old identity script, 10 to 19 failed with "could not write" in each of
three rounds, and none of the new script's runs did.
### Fixed — a TS/JS call on a literal no longer pins an unrelated same-named function (parser versions 100 and 103)

`"=".repeat( 50 )` bound webpack's in-repo CssSyntax `repeat`, and `/^@/.exec( … )` its DefinePlugin `exec` (issue
#163): a member call whose receiver is a literal took the bare-name ladder like any receiver of unknown type. A string,
template, array, regex, number or boolean literal's type is certain from the syntax, and so is a chain that keeps it
certain; certainty ends at `find`, `at`, `pop`, `shift`, `reduce`, a subscript, `!`, `as`, `satisfies` or `<T>x`.
`RecvKind` gains LitString, LitArray, LitRegex, LitNumber and LitBoolean, and only a name that really is a member of that
built-in (sorted per-type tables in `src/model.h`) leaves the ladder: a JS `Foo.prototype.NAME` polyfill binds first,
otherwise the call is External when the name exists in the repository and Undefined when it does not. A name that is not
a member of the built-in (`shout`, `Object.assign`, a TS `declare global { interface String { loud() } }`) keeps its old
path. Object literals, `this.replace()`, `helpers.transform()`, `JSON.stringify` and a typed `text: string` are out of
scope.

Measured with `--pin-census`: on webpack `a943d69c4`, 139 previously bound sites become External (sort 46, repeat 32,
join 25, exec 17, test 13, split 3, slice 3), edges go 23,970 → 23,823 and `--callers=stringify` stays 361; node's `lib/`
loses 10 wrong pins (`regex.test` had bound the test runner's `test`); zod's `external=` rises 112 → 192. A signed number,
`(-1).toFixed()`, was no literal in the first version and could still bind an unrelated `toFixed`: the grammar spells the
sign as a unary expression over the number, and a unary `+` or `-` over a number now classifies as LitNumber while every
other unary expression (`!1`, `typeof 1`, `-x`) stays unclassified. `test/fieldnarrowcheck.sh`'s literal-receiver arm is
the gate, with `viaNegative` and `viaPositive` in its TS, JS and TSX fixtures. `kParserVer` moved to 100 on
integration/train-2b (the PR declared 97) and 102 → 103 on integration/train-1b for the signed-number fix. Thanks to
@csy20.

### Fixed — a call through an interface pointer landed on unrelated nested classes of the same name

`void AssertItersEqual( Iterator* iter1, Iterator* iter2 ) { … iter1->key() … }` in rocksdb answered with five edges to
the nested `Iterator` classes inside memtable/'s skip lists, and none was right. Rule 2 keys a receiver's type by its final
class-name segment, a nested class keeps only that segment (`SkipList<Key, Comparator>::Iterator::key` has scope
`Iterator`), and `rocksdb::Iterator`'s methods are pure-virtual declarations the definitions-only map never holds — so the
only `Iterator::key` it could find were the namesakes. The entry above disclosed 79 such parameter sites; typed LOCALS
(`Iterator* iter = db->NewIterator( … )`) have the same shape, and there are more than a thousand.

Rule 2 now reads the call through class identity rebuilt from facts ingest already has (resolve.h `ClassIdentity`): byte
spans give each class its enclosing class and each member its owner, the inherit references give the class graph, and
an `Iterator` nested in `SkipList` can then be told apart from a namespace-level one. A hit owned by a nested class the
written type cannot name — C++ lookup outward from the caller, a qualifier naming the enclosing class — is dropped; with
nothing left, the call resolves to the shallowest ancestor that defines the method; and when the ancestry only DECLARES
it, to its definitions in the class's real subclasses — the dispatch split a virtual call through an interface is, kept
whole rather than trimmed to the same-file override by the locality ladder. Four guards came from reading the corpora,
each one a wrong edge an intermediate build made and a gate arm now pins: a forward declaration (`class Iterator;`, five
at rocksdb's namespace scope) is not a class; two namespace-level classes of one name (`llvm::Value`,
`llvm::sandboxir::Value`) are told apart by what the file includes, an include-root spelling read as a path suffix; a
type ALIAS the index cannot see (`using NodeSet = MachineGadgetGraph::NodeSet;`) keeps the nested class its caller
includes; and identity replaces an answer only with one it can explain — otherwise the previous answer stands. No
extraction change: kParserVer does not move.

Measured with `--pin-census --no-cache`, the stack tip `50129f8c` against this change:
- rocksdb @ `0e2801ac3`: 2,659 call sites change target and `bound=` goes 200,036 → 201,085. 995 namesake splits become
  the real `Iterator` implementations (DBIter, ArenaWrappedDBIter, ModelIter, … — 11 for `key`); 638 declined calls gain
  a dispatch split (`Statistics::getTickerCount`, `DB::DefaultColumnFamily`); 397 declined calls gain their inherited body
  (`IOStatus io_s; io_s.ok()` → `Status::ok`); 276 partial splits complete (`Comparator::Compare`, 6 → 26); 88 wrong unique
  pins become the interface's implementations (`env->DeleteFile` had pinned an unrelated file system).
- llvm-project @ `4d5358b1d`: 37,949 of 1,790,841 call sites change target and `bound=` goes 1,126,051 → 1,153,808 —
  21,408 declined calls gain their inherited body (`LD->getAlign()` → `MemSDNode::getAlign`, `e->getRHS()` →
  `BinaryOperator::getRHS`), and wrong locality pins move to the right base (`FD->getType()` → `ValueDecl::getType`).
- a private C++/ObjC++ corpus: 177 sites change target, `bound=` 80,582 → 80,646 (a map subclass's `begin` → its base's,
  a behaviour interface's `get` → all 64 implementations).
- this repository's `src/`: no site changes.

Every change bucket on all three corpora was sampled and read against the source on the final build; the wrong shapes
the intermediate builds produced are the four guards above. Cost, two cold runs each on llvm-project: user time 52.4 /
52.9 s before, 50.9 / 55.9 s after; peak RSS 2.37–2.47 GB both; output byte-identical run to run on every corpus.
`test/narrowcheck.sh` arms 26-38 are the gate: seven rows red on the stack tip — (26) (27) (28) (29) (32) (34) (35) — and
arms 30, 31 and 33 are controls (33 was red on the intermediate build that dropped an aliased nested class). An identity
claim is a verified answer, not a last-name match, so its edges carry no `prov="final-segment"`; a class-qualified step-1
narrow keeps that disclosure (arm 36).
A seeded sample of the retargets graded against source — 30 rocksdb and 30 llvm-project sites — read 56 better, 2 the same
and 2 worse. One worse shape is fixed here. A class template's specialization has no class symbol, so its members (scope
`SmallVectorTemplateBase<T, true>`) were never reached: `SmallVectorImpl<FunctionDecl *>& v; v.push_back( FD )` answered
the primary template alone, while pointer T instantiates the specialization. A defining level now adds its template's
specialization-scoped definitions — among them a primary template's own `DominatorTreeBase<NodeT, IsPostDom>::verify`
out-of-line bodies — and the CHA-lite cone prune skips an identity claim, as the ladder and locality already do. This moves
366 llvm-project sites (a sample of 20 graded: 12 now right, 8 hold the right target in a split; 0 worse) and none on
rocksdb, the private corpus or `src/` (arm 38).
FLOORS, stated: namespaces are evidence, not a model — a same-named class in another namespace that the caller's file
also includes stays a candidate; a type alias is kept rather than read through; an inherited body is the static answer,
as a class's own body always was (overriders join only a method no ancestor defines), and it answers for every overload
of its name. rocksdb's `BackupEngine* e; e->RestoreDBFromLatestBackup( options, db, wal )` therefore takes the inline compat
overload while the pure-virtual overload it calls goes unjoined. Joining its overriders was built and measured: 2 sites
better, 5 worse (arm 37). A dispatch split is as wide as the interface's implementations — up to 50 targets on rocksdb
and 71 on the private corpus, every one disclosed by `amb=`.

### Fixed — a receiver typed with template arguments got no type, or the wrong class's

`void f( SmallVectorImpl<FunctionDecl *> &Decls ) { Decls.push_back( FD ); }` bound nothing on llvm-project unless the
parameter was spelled `llvm::SmallVectorImpl<…>`. Rule 2 reads a receiver's type off its declaration, and that capture
recorded a type only for a plain or a qualified name: an unqualified template-id (`SmallVectorImpl<FunctionDecl *>`,
`Expected<unsigned>`, rocksdb's `autovector<VersionEdit*>`) recorded none, and that is how code inside its own namespace
writes nearly all of them. A qualified name was read by cutting its text at the first `<`, so a type whose template
arguments come before its last name — `SkipList<Key, TestComparator>::Iterator iter` — recorded `SkipList`. `SkipList`
defines no `key`, so `iter.key()` fell to the name ladder, which picked the test's own `ConcurrentTest::key` (86 such
receivers changed target: 76 on rocksdb, 10 on llvm-project). Where the outer class does define the method, the edge was
precise and wrong: `Outer<int>::Inner& in; in.size()` went to `Outer::size`. Neither corpus has an instance of that; arm
41 pins it. The last name is now read through the grammar's own fields (`Vec<T>`
and `ll::Vec<T>` are `Vec`, `Outer<int>::Inner` is `Inner`), and a `::` inside a template argument (`Vec<std::string>`)
no longer marks the type qualified, so its edge carries no `prov="final-segment"`.

Measured with `--pin-census --no-cache`, call sites joined on (caller id, callee, line), `main` 13a19162 against this
change. rocksdb `0e2801ac3`: 640 sites change target and bound calls rise by 347. llvm-project `4d5358b1d`: 5,231 sites
and +3,589. Composed with the class-identity resolver (#268), whose inherited-member walk these bindings feed, it is 657
and 18,050 sites, +12,702 bound on llvm-project. A seeded sample of 100 of those sites (seed 20260917: 20 + 30
standalone, 12 + 38 composed) was graded blind against source, each grader seeing the two answers as A and B in random
order: 99 better, 1 the same, none worse (62 NONE → RIGHT, 24 WRONG → RIGHT, 5 PARTIAL → RIGHT, 1 WRONG → PARTIAL, 7
NONE → PARTIAL where #268's template-family split lists the specialization a trivially copyable element does not select,
and 1 PARTIAL either way). Nine edges are lost, all on llvm-project, and all nine were read. Seven are a name declared
twice in one function with different types (`APInt Mask` beside `SmallVector<int> Mask`): Rule 2's per-function table
cannot tell which declaration covers a call, so it drops both, as it always has for two plain types. Two are
`auto Table = EytzingerTable<…>::create( … )`, which recorded `EytzingerTable` only because the cut stopped at `<`; it
now reads `create`, as `Foo::create()` always did.

STATED FLOOR: an unqualified template-id constructor, `auto v = Vec<T>()`, still infers nothing. It is the spelling of
every cast helper. Reading it records `dyn_cast` as the type of `auto *CI = dyn_cast<CallInst>( I )`, a name that
conflicts with the declaration's written type (`const ConstantInt *CI = dyn_cast<ConstantInt>( V )`) or with a second
declaration of the variable, and the conflict tombstones it. Measured on integration/train-3 (llvm-project `4d5358b1d`,
`--pin-census --no-cache`), reading it moves 463 sites: 324 edges lost, 137 retargeted and 2 gained, and rocksdb moves
none. On `main` 13a19162, before #278 dropped an assignment's callee name (`Spec = cast<FunctionDecl>( F )`), it moved 994
and lost 779. The qualified `llvm::cast<T>( x )` still records `cast`, as before. `kParserVer` moves 103 → 104 (the PR
declared 99 → 103 over `main`; integration/train-3 assigns 104 after train 1b's 103) and `test/qschemetrip.hash` is re-pinned.
Gate: `test/narrowcheck.sh` arms 39–43. They are red on `main` (no edge, or the precise edge to `Outer::size`) and on
#268's head, where arm 42 also fails: the qualified twin splits and the unqualified twins decline. Arm 40b is red on a fix
that reads qualification off the whole spelling.

### Fixed — `--affected=`/`--exercises=` and `--exclude=` matched a directory ABOVE the crawl root, not just the tree

Root-spelling-invariance seams #228 missed. `--affected=`/`--exercises=` (`testmap.h`'s
`resolveAffectedSeeds`/`resolveExerciseSeeds`), `--exclude=` (`ingest_crawl.h`), `--verify`'s FILE argument
(`verbs_navigate.h`), `--at=FILE:LINE` (`graph.h::resolveAtSeed`), the `file:name` qualifier every
`--callers`/`--impact`/`--uses`/`--edit-check`/`--around`/`--lego` selector shares
(`graph.h::resolveAllByNameQualified`), its own refusal diagnosis (`selectorrefuse.h::indexHasFileMatching`
and `definingFilesOf`), and the MCP write verbs' `file` disambiguation hint
(`mcpedit.h::editHintMatches`) all `filePathContains`'d the RAW stored path instead of the root-relative one
— the same seam every other index-builder and path predicate already reads per #228. So a pattern that
happened to match the CHECKOUT location — never anything inside the tree itself — decided the answer only
under an absolute or trailing-slash root: `--affected=<marker-above-root>` matched every file instead of
refusing, `--exclude=<marker-above-root>` silently dropped every file from the map, `--verify`/`--at`/the
file:name qualifier confirmed or ambiguated claims about files the index never matched, and an MCP edit's
bogus `file` hint could pass a false disambiguation. Every path-pattern consumer now routes through one
shared helper, `graph.h::filePathContainsRootRel`, so the next consumer cannot independently reintroduce the
raw form; `selectorrefuse.h::definingFilesOf`'s own "here's a runnable retry" suggestion is root-relative too,
for the same reason — the retry text has to re-match under the fixed rule to still be runnable.
`test/rootspellingcheck.sh` gained arms for `--affected`/`--exclude`/`--verify`/`--at`/`--callers=file:name`
across all six root spellings; `test/mcpeditcheck.sh` gained arm (10) for the MCP `file` hint.
Matching root-relative ONLY dropped the other way a user names a file: from the cwd. `ripwire test/fixture
--edit-check=test/fixture/geometry.cpp:distance`, `./a.cpp` under `ripwire .`, `../repo/a.cpp` under
`ripwire ../repo` and an absolute `/…/repo/a.cpp` all resolved in 0.6.1 and refused with this change's first version.
`filePathContainsRootRel` still tries the root-relative path first; on a miss it strips a root prefix the crawl
recorded once (the root as typed, the root relative to the cwd, or one of its absolute spellings, `$PWD`'s and
realpath's alike) and matches the rest root-relative. A path that names no indexed file still refuses.
`test/rootspellingcheck.sh` arm (6) pins `<root as typed>/`, absolute and cwd-relative selectors on `--edit-check`,
`--callers`, `--at` and `--affected` under all six spellings, with a refusal control for each form.

### Fixed — MCP `quality_delta`'s "sidecar present but unreadable" baseline marker now spells the CLI's own wording

The CLI and MCP arms named the same disk state — a `.ripwire_quality_baseline` sidecar that exists but was
rejected by `readBaseline` (unrecognizable, an older format, or pre-Q1) — with two different strings:
`baseline="git-HEAD (sidecar unreadable)"` on the CLI (the spelling `quality::selectBaseline` sets and
`--help`'s own legend documents) versus `"git-HEAD (unreadable sidecar ignored)"` from MCP's
`mcpBaselineMarker`, which carries its own local `std::filesystem::exists` fallback for a residual case
`selectBaseline` cannot flag on its own. MCP now returns the documented CLI string.
`test/mcpattrparitycheck.sh` gained a value-level check (its existing arms compare attribute NAMES only,
deliberately) that pins both surfaces to the identical marker on a pre-stamp v5 sidecar fixture.

### Fixed — `--layout` no longer drops a field decorated with a postfix `__attribute__((...))`

`int x __attribute__((aligned(8)));` reached `layout.h`'s plain-field parser with the attribute still
attached: the last-identifier scan that splits a declarator into its type and name took the digit inside
the attribute's own argument list (`8`) as the field NAME and left its closing parens as unparsed trailing
text, so the whole declaration was refused as `caveat k="unparsed-member"` with no `<f n="x">` row at
all — unlike every other unmodelable-field shape the fixture covers (`alignas(N)`, `decltype(...)`,
`std::function<...>`), all of which still count the field. `layout.h` now peels a trailing
`__attribute__((...))` (balanced parens, same technique as the existing array-extent peel) before the
name/type split. An attribute that changes the field's own placement (`aligned`/`packed`) still refuses —
`x` is counted (`<f n="x">`) but `unknown-type`, the same degrade `alignas(N)` already gets, rather than a
confidently wrong offset; any other attribute (`deprecated`, `unused`, …) is a pure hint and is now modelled
normally, with no caveat at all. `test/layoutcheck.sh`'s `AttributeFieldCase` gained the same
field-survives assertion `AlignasFieldCase` already had, and a new `AttributeHarmlessFieldCase` fixture
pins the fully-modelled path.

The aligned/packed check also missed GNU's reserved-namespace double-underscore spelling
(`__aligned__`/`__packed__` — what system headers reach for so the keyword cannot collide with a macro of
the same bare name): `containsWord`'s word-boundary rule treats `_` as an identifier byte, so it does not
match `aligned` inside `__aligned__` at all, and the field came back `modeled="1"` with a confidently
wrong `sz`/`al`/`off`. `attrHasKeyword` now checks both spellings. The C++11 standard attribute syntax
(`[[gnu::aligned(8)]]`/`[[gnu::packed]]`) was checked too: both already refuse, as a side effect of how the
surrounding text fails to parse as a plain field rather than by design — pinned in the fixture so a later
change to `[[...]]` handling cannot silently start modelling these as natural. `test/layoutcheck.sh` gained
`AttributeGnuAlignedFieldCase`/`AttributeGnuPackedFieldCase` (must degrade), `AttributeGnuHarmlessFieldCase`
(`__unused__`, must stay modelled), and `AttributeStdAlignedFieldCase`/`AttributeStdPackedFieldCase`
(the `[[gnu::...]]` regression pins).

### Fixed — the crawl now admits `.hxx`, a C++ header spelling every OTHER per-extension table already listed

`src/ingest_crawl.h`'s `kLangTable` — the ONE table that decides whether the crawl looks at a file at
all — had rows for `.h`/`.hpp`/`.hh` but none for `.hxx`, so a repository that spells its headers `.hxx`
was invisible to the crawl (`files=0`, `unindexed="hxx:N"`) even though six other per-extension tables in
the tree (`flipimpact.h`'s dead-code header set, `layout.h`'s `--layout` scan, `lintrules.h`,
`quality.h`'s header/public-API predicates, `resolve.h`'s include resolver, `verbs_lint.h`) already listed
`.hxx` alongside `.hpp`/`.hh`. `.hxx` now rides the same `Lang::Cpp` / tree-sitter-cpp grammar as `.h`.
This changes extraction output for any tree with `.hxx` files (new files, symbols and edges a pre-bump
cache never saw), so `kParserVer` moves 104 → 105 (the lane declared 99 → 100 over `main`;
integration/train-3 assigns 105 after #276's 104; mirrored in `kIngestParserVerMirror`, same diff;
`test/qschemetrip.hash` re-pinned). `test/filerootcheck.sh` gained an arm indexing a `.hxx` file as a
single-file root. `taskroute.h::kCodeExtensions` (the FILE:LINE token recognizer behind `--help-task`'s
at-line routing) was a seventh table listing `.hpp`/`.hh` without `.hxx` — added, with a `test/taskroutecheck.sh`
arm routing a `.hxx:LINE` token to `--slice=@FILE:LINE`. Two of the six had just dropped their `.hxx` rows as unreachable
(`langOfPath`'s and `includeLangOf`'s, in the five-extensions entry above), and the compile-time check between the crawl's
table and `langOfPath`'s refuses a crawl row without its classifier row, so both rows are restored with it.

### Fixed — `--slice --since` no longer tells the "new code" story about a blob that was never parseable source

A file whose blob at REV held ERROR/MISSING tree-sitter nodes (binary content committed under a source
extension, a merge gone wrong, anything the grammar's error recovery could not read as this language)
could leave the REV-side symbol search empty for a reason that has nothing to do with the definition
being new. `status="sym_absent_at_rev"` claims "the file was there and the definition was not" — every
row then reads `op="+"`, the reviewer's cue that this is newly-added code — which is a confidently wrong
story for a blob that was not valid source at all. `slicediff.h`'s `sliceAtRev` now checks the same
`errNodes > 0` degraded-parse signal `fileParseDegraded` already shares with `--grep`'s `parse_degraded=`
and the selector refusals, and reports `status="unparsed_at_rev"` (`comparable="0"`, no rows) instead
when the REV blob's own parse was this degraded. `test/slicediffcheck.sh` gained arm (8c) pinning a
binary-at-REV case against the (8)/(8b) sym-absent case it must not be confused with.

### Fixed — assigning a variable from a function call erased the type it was declared with

`Status s; … s = GetDBOptionsFromMap( … ); if( !s.ok() )` bound no `ok` edge on rocksdb, and `PHINode *PHI = nullptr; …
PHI = PHINode::Create( … ); PHI->addIncoming( V, BB )` bound no `addIncoming` edge on llvm-project. Rule 2 reads a
receiver's type off its declaration, and it also records a C++ ASSIGNMENT from a call as a type, so that `x = Foo()`
types `x`. A constructor call and a function call are the same grammar node, so the assignment recorded the callee's
last name, `GetDBOptionsFromMap` or `Create` (and `cast` for `x = llvm::cast<T>( y )`). Rule 2's per-function table
drops a variable whose records disagree, so that non-type erased the declared `Status` or `PHINode *`. The field use-site index (`--uses=Owner.field`) lost
the same pin. A MEMBER assigned from a call (`cur = ns::cast<Target>( y )`) also read as a local, so Rule 2b refused the
member's declared type. An assignment declares nothing, so its callee name now counts as a type only when a class of
that name exists. A declaration initialised by a call (`auto t = makeFoo()`) still counts, as a declaration whose type
is unknown: when a sibling block declares the same name with another type, both calls are dropped rather than one
block's type reaching the other's call.

Measured with `--pin-census --no-cache`, call sites joined on (caller id, callee, line), `main` fe28fd49 against this
change. rocksdb `0e2801ac3`: 1,871 sites change target, bound calls +1,562 (1,544 newly bound, 327 retargeted, none lost;
1,494 are `Status::ok`). llvm-project `4d5358b1d`: 4,046 sites, +2,984 (2,859 newly bound, 1,187 retargeted, none lost).
A seeded sample of 60 (seed 20260917: 25 rocksdb, 35 llvm-project) was graded blind against source by independent
readers, with the two answers shown as A and B in random order. 51 were better, 6 the same and 3 worse. The better ones
were 39 NONE → RIGHT, 5 WRONG → RIGHT, 4 PARTIAL → RIGHT, 2 NONE → PARTIAL and 1 WRONG → PARTIAL. The same ones were
4 WRONG → WRONG and 2 RIGHT → RIGHT. All three worse sites are resolver floors the erased type had been hiding, not
errors in the recovered type. One is a rocksdb `Iterator*` that narrows onto the memtable's same-named `Iterator` classes.
Two are llvm-project calls where arity picked the wrong overload of the right class (`getFirstInsertionPt`, `find`).
Dropping the member's record from the local-name set is 23 of the rocksdb sites and 132 of the llvm-project ones; 15 of
those graded 10 better, 2 the same and 3 worse. Two of the worse ones show a floor this change exposes but does not
cause: Rule 2c reads a member named like a class (`std::unique_ptr<ToolOutputFile> OutputFile;`) as that class.

Built and rejected: also dropping a DECLARATION's callee name. It moves 89 more llvm-project sites (none on rocksdb), and
15 graded 11 better, 2 the same and 2 worse. Arm 48 is why it is not shipped: the flat table would hand one block's
declared type to a sibling block's `auto t = ns::cast<Decoy>( y )`, a precise edge to the wrong class. The unqualified
`Vec<T>()` constructor spelling left unread by the template-id receiver lane (#276) stays unread. Composed with that lane
and this change on #276's head, reading it moves 245 llvm-project sites, and all of them get worse: 170 edges lost and none
gained, where it lost 779 before this change (on integration/train-3, with the class-identity resolver, 463 and 324). The losses left are declaration conflicts, `auto *LI = cast<LoadInst>( … )` beside
another `LI`.

The bind record gains one byte (`kCacheVersion` 22 → 23). `kParserVer` moves 105 → 106 (the PR declared 99 → 104
over `main`; integration/train-3 assigns 106 after small-fixes' 105). `test/qschemetrip.hash` is re-pinned, and `test/cachefuzzcheck.sh`'s
blob walker reads the new byte. Gate: `test/narrowcheck.sh` arms 44–51. On `main`, arms 44, 45, 46, 49 and 50 are red.
Arm 48 is red on the declaration variant, 46 without the local-name-set change, and 51 on a build that does not persist
the new byte.

### Added — a Java `Type::method` reference is a call site for `--uses` and `--callers` (parser version 107)

`Widget.makeFn()` minted a call edge and `Widget::makeFn` did not, so a lambda and the method reference beside it
disagreed about who calls `makeFn` (issue #74). The receiver is a type and the member a literal identifier, so the
target is fixed at compile time. `queries/java/tags.scm` now captures the member name after `::` on a
`method_reference`, and ingest stamps the site `RecvKind::JavaTypeCandidate`: the pinned grammar spells `Widget` and
`widget` with the same `identifier` node, so the query alone proves nothing about the receiver. `src/graph.h` admits
an ordinary call edge only when the receiver denotes an indexed Java type; a Java parameter, local or field binding of
that name in scope vetoes it, and nested and package-qualified type receivers are handled explicitly. Java shadow
binds now carry lexical spans and capture inferred lambda parameters, and the C-family shadow pass refuses Java
outright (a Java call never resolves to a local). `widget::instanceFn`, `this::thisFn`, `super::superFn` and
`Widget::new` stay unresolved, and the receiver identifier is never the callee.

`test/javamethodrefcheck.sh` is the gate: the callers of `makeFn` are exactly `genericTypeMethod`, `lambdaForm`,
`nestedTypeMethod` and `typeMethod`, nothing calls `instanceFn`, `thisFn`, `superFn`, `Widget` or `widget`, and
rewriting `Widget::makeFn` removes only `typeMethod`. `test/callformcheck.sh`'s Java `--uses=makeFn` is 2.
A catch parameter, an enhanced-for variable and a try-with-resources resource declare names as well, and none of the
three was read, so `catch (RuntimeException Widget) { return Widget::m; }` still resolved `Widget` as the class
(CodeRabbit on #281). All three now shadow, each inside its own clause, loop or statement only; the gate pins both
the shadowed reference and the one after the scope closes, and `kParserVer` moves 109 → 110.
`kParserVer` 106 → 107 (the PR declared 96 → 97 → 98 over `main`; integration/train-3 assigns 107). Thanks to
@rainhuang0220.

### Added — GDScript (`.gd`), the 25th vendored grammar (parser version 108)

A Godot repository was invisible: `.gd` fell out at crawl time as an unsupported extension, so every ranked lens
answered `reason="no_candidates"`, while `--grep`'s unindexed-text fallback still scanned the files and made the gap
read as a ranking problem. ripwire now vendors `PrestonKnopp/tree-sitter-gdscript` and extracts `class_name`, inner
classes, functions and methods, constants, enums and their members, variables and signals, plus call edges. A `.gd`
file is a class body: `class_name` names it and its file-scope `func`/`var` are its members. Measured on 13
open-source Godot projects outside this tree: 3,525 files, 58,128 symbols and 27,768 edges, indexed cold in 0.82 s,
and 98.81% of their 2,611 `.gd` files parse clean.

STATED FLOORS: three upstream grammar bugs are not patched here (G3) — a `%` scene-unique name inside a node path, a
column-0 comment inside an indented block, and Godot 3 keywords that are still reserved (`remote = {}`). tree-sitter's
recovery is local, and `test/gdscriptcheck.sh` asserts that every definition and call edge in a fixture holding them
survives. `preload`/`load("res://…")` dependency edges are a later round, so GDScript is not dependency-capable, and
`.tscn`, `.tres` and `.gdshader` are not indexed. `test/gdscriptcheck.sh` is the gate, and it is red on a
pre-GDScript binary. On integration/train-3 the language registers through train 1's compile-time-checked tables
(`isCodeLang`, `kLintExtRows`, `kLangTokenRows`, `kNodeFieldNames`, `kLangTable`'s exact extent), and `kParserVer`
107 → 108 (the PR declared 96 → 98 over `main`). Thanks to @sclyde.

### Added — a Ruby constant receiver now pins the call, instead of splitting it across every same-named method

`Calc.add( 1, 2 )`, `Outer::Engine.run( 3 )`, `::Top.ping` and `Util.format( 5 )` resolved to EVERY
method of that name in the corpus, each edge marked `prov="split"`. The resolver's Rule 2c already
says "the receiver token IS the type" (`docs/EVALS.md` "Phase 4b"), but it could not fire for Ruby:
`classifyReceiver` accepted a receiver node of kind `(identifier)` only, and Ruby's class/module
receiver is its own node kind — `(constant)` for `Calc`, `(scope_resolution)` for `Outer::Engine`
and `::Top`. Every such call classified `RecvKind::None`, and the resolver fell through to the
name spray. Ruby's one call form that carries a type was the one the type rule never saw.

The receiver's FINAL constant segment is the type name (`Outer::Engine` → `Engine`), the same
final-segment convention the existing type bindings use (`ns::Foo` → `Foo`), because `Symbol::scope`
is the IMMEDIATE enclosing name by design. A Ruby MODULE is a receiver of class methods as much as
a class is (`Util.format`), so Ruby's `SymKind::Other` symbols — which `queries/ruby/tags.scm` can
only reach through `module` — join Rule 2c's class-name set.

Measured with `--no-cache` on five Ruby corpora, before → after (map header gauges):

| corpus | files | edges | ambiguous | declined |
| --- | --- | --- | --- | --- |
| activesupport 8.1.3 `lib` | 290 | 3,868 → 3,912 | 468 → 434 | 1,022 → 985 |
| activerecord 8.1.3 `lib` | 398 | 9,116 → 9,152 | 1,496 → 1,479 | 4,576 → 4,497 |
| actionpack 8.1.3 `lib` | 157 | 3,151 → 3,140 | 390 → 364 | 943 → 923 |
| Rails app A | 4,683 | 23,784 → 24,376 | 1,328 → 1,263 | 12,485 → 11,624 |
| Rails app B | 2,174 | 14,859 → 15,257 | 275 → 431 | 3,264 → 3,050 |

`declined` falls on all five: those are call sites the resolver refused to guess at and now has
evidence for. Edges fall on actionpack because a pinned call is ONE edge where a two-way split was
two. App B's `ambiguous` rises while its `declined` falls by 214: a receiver that names two
same-final-segment classes both defining the callee produces an honest split where there was
previously no edge at all — the disclosed floor below, not a regression.

Stated floors, each pinned by an arm of `test/rubyrecvnarrowcheck.sh`: Ruby feeds no
class-hierarchy edges (`captureBases` has no Ruby arm), so a method inherited from a superclass does
not narrow — this is what holds the gem numbers down, where deep `ActiveRecord::Base` hierarchies are
the idiom; matching is by final segment, so two same-named classes in different namespaces both
defining the callee keep both candidates; a variable receiver (`c.scale`) or a chained one
(`Calc.new.scale`) is untouched; and a constant receiver whose class defines both `def self.x` and `def x` gets an
honest two-way split that includes the instance method (rails `Journey::Parser.parse`) — a split, not a pin, because
telling `method` from `singleton_method` apart is a later round. A narrow that misses degrades to the unchanged ladder — it never
deletes an edge and never invents one (`Time.now` still mints nothing).

The default map is byte-identical to the previous build on five Ruby-free corpora (this repo's
`src/`, npm, a Clojure project, CPython 3.14's stdlib, and this whole repository), and this
repository's `--report` totals are unchanged at 2,052 files · 18,979 symbols · 22,529 edges.
`kParserVer` 108 → 109 (the PR declared 96 → 97 over `main`; integration/train-3 assigns 109; record layout
unchanged by it, `kCacheVersion` stays 23; the VALUES of `recv`/`recvVar` move, so Ruby extraction facts are re-parsed),
with `quality.h`'s mirror and `test/qschemetrip.hash` re-pinned in the same commit. Thanks to @andriytyurnikov.

### Fixed — a C++ local constructed from plain names, `IRBuilder<> Builder(Rem);`, was indexed as a function and hid its type from the receiver rule

The grammar cannot tell a name from a type, so a block-scope direct-initialized local whose every argument is a plain
name (`std::lock_guard<std::mutex> Lock(Mtx);`, `Slice end(end_str);`) parses as a local function declaration, and the
tags query minted a function symbol for it. That symbol's span covers the declaration, so the local's type binding was
filed under the phantom instead of the function the local lives in: Rule 2 found no type for `Builder.CreateSExt()`, and
the call fell to the name ladder, where it declined or split. The phantoms also answered bare-name lookups: a Python
`range(...)` read as bound in-repo because a C++ local was named `range`. Such a declarator now mints no symbol unless
something in it can only be written in a prototype: `extern`/`inline`/`virtual`/`explicit`, a `void` return, anything
after the parameter list (`const`, `override`, `noexcept`), empty parentheses, or a parameter an argument cannot
produce (a primitive or cv-qualified type, a named declarator, `*`/`&`, a default, `...`). Measured with
`--pin-census --no-cache`, main against the change, C rows joined on (caller, callee, line): llvm-project 4d5358b1d
loses 12,543 function symbols and rocksdb 0e2801ac3 2,443, none added. Excluding rows that only lost a phantom target,
changed caller when a phantom disappeared, or lost a veto on a phantom name, 2,857 llvm and 1,062 rocksdb call sites
retarget. A seeded blinded sample of 40 graded 34 better, 0 same, 6 worse, and all 6 came from the 68 llvm sites that
lost an edge. Those sites are the flat per-function receiver table's existing floor: a sibling block's same-named local
of another type now tombstones the name. On train 3 (template-id receivers) the change also restores 997 of the 1,937
llvm sites that refusing Rule 2c for C++ moved, 928 of them `Builder.CreateX()`. `Widget w( a * b )` still reads as a
pointer parameter and stays a function symbol, a stated floor. Gate: `test/narrowcheck.sh` arms 52-60 (52-58 red on the
unchanged binary; 59 red on a fix that refuses every body-local declarator).

### Fixed — a class's `using Base::m;` was ignored, so a call its two bases tie on stayed split

llvm-project's `clang/lib/CodeGen/CGNonTrivialStruct.cpp` declares `struct CopyStructVisitor : StructVisitor<Derived>,
CopiedTypeVisitor<Derived, IsMove> { using StructVisitor<Derived>::asDerived; … }`. Both bases define `asDerived`, and
the using-declaration is how C++ picks one. The type-side probe that Rules 2b and 2c and Rule 1's base walk share
(`resolve.h` `methodOnTypeOrBases`) never read it. A class with no `asDerived` of its own went straight to its bases,
the two-base tie refused, and each of the file's five `asDerived()` calls split three ways: `StructVisitor::asDerived`
plus same-file namesakes in `GenFuncNameBase` and `GenFuncBase`, classes the caller does not derive from. The tags pass
has recorded every class-scope using-declaration as an import site all along; the resolver never consulted them.

A class that defines no `m` now answers with what its `using Base::m;` names: the base's own definitions, else the
result of walking that base. The walk goes one level: that base's own using-declarations are not followed. The
qualifier loses its template arguments (`using Base<T>::m;` names `Base`). A re-export naming nothing the index reaches
adds nothing, and the unchanged walk runs. So does one naming a class outside the class's base closure, which C++ forbids: trusting
`using NotABase::m;` would pin `NotABase::m` over the real bases' tie. The change is resolve-stage only: kParserVer and the cache format do not
move.

It deliberately does NOT add the base's overloads to a class that also defines `m`, though C++ does. That was measured
first. Clang's `CGBuilderTy`, for example, writes `using CGBuilderBaseTy::CreateGEP;` next to its own `CreateGEP`
overloads, yet the resolver answers the class's own overloads alone. The union was built and graded: over the 17 call
sites it moved (rocksdb 13, llvm-project 4), blinded against source, 5 were better, 4 the same and 8 worse. Three
causes, none fixable without parameter types:
- The ladder cannot drop a re-exported overload the class overrides: rocksdb's `WriteBatch::Put` and `Delete` gained
  `WriteBatchBase`'s.
- It cannot drop one the argument count rules out, because the arity filter removes only too-many-arguments
  candidates.
- One split was cut to its base half by the same-file tier.

That shape stays a stated floor, pinned by `test/fieldnarrowcheck.sh` arm (u1). It would not have reached `CGBuilderTy`'s
calls in any case. On main, `CGBuilderBaseTy` is a typedef the base walk cannot follow. With a typedef/using alias fact
applied, the S6-C locality tie-break keeps the `clang/lib/CodeGen` half of the split.

Measured with `--pin-census --no-cache`, the `main` binary at `fe28fd49` against this change, joining call-site rows
on (caller, callee, line):
- rocksdb @ `0e2801ac3`: 0 call sites change.
- llvm-project @ `4d5358b1d`: 5 change, 0 gained, 0 lost. All five `asDerived()` splits become one receiver-rule pin
  (`receiver-rule=` 520,496 → 520,501, `split=` 256,918 → 256,913). Graded blinded against source: 5 better, 0 same,
  0 worse.
- Composed with the typedef/using alias fact then in review (head `36aa4f56`), llvm-project moves one more site:
  `UsingShadowDecl::getMostRecentDeclImpl` reaches `Redeclarable::getMostRecentDecl` through `using
  redeclarable_base::getMostRecentDecl;`, graded WRONG → PARTIAL. rocksdb stays at 0.

The ASan build's llvm-project census is byte-identical to the plain build's and reports no sanitizer finding. Re-measured after merging `main` at `a5ce95e2`: the same five llvm-project sites move, and rocksdb still moves none.

The gate is `test/fieldnarrowcheck.sh` arms (u0)–(u7). On `main`, (u2) the field call, (u3) Rule 1's bare call and (u5)
the template-qualified re-export are red. (u4) is the contrast: the same two bases with no using-declaration keep their
split. (u6) is an unindexed re-export that keeps the walk. (u1) goes red on the union build, and (u5) on a build
without the template-argument strip.

### Fixed — an `--arch` TO-template interval was rejected at parse time even when a real capture made it valid

`deny path FROM -> TO` validates a TO template like `a{10,\1}` at parse time by compiling it once with a
placeholder in `\1`'s place — and used to try two placeholders, `"x"` then `"9"`, rejecting the whole rules
file (D9) only when BOTH failed. But `"x"` is not a digit, so it fails ANY numeric-interval position on that
alone (`{10,x}`), whatever the template; `a{10,\1}` failed both placeholders (`{10,x}` non-numeric, `{10,9}`
since 9<10) and was refused outright — even though `\1="20"` makes `{10,20}` a perfectly valid interval
(CodeRabbit review on #277). The probe is now a single `"9"` (valid everywhere a placeholder is: ordinary
literal text, or a genuine interval digit), and a refusal is accepted at parse time only when it is NOT
`std::regex_constants::error_badbrace` — an out-of-order `{min,max}` is a fact about which digits a specific
capture supplies, not about the template's structure, so it defers to the edge: `pathRuleMatches` already
compiles the REAL substitution per edge and refuses by name (`isRefused`) only the edges whose own capture is
actually invalid. `RegexCompile` (`src/regexguard.h`) gained `isIntervalRangeOnly`, set once at the single
`std::regex_error` catch site `compileGuardedRegex` already had — no new file spells `std::regex`
(`test/regexguardcheck.sh` arm (c), which caught the first version of this fix routing the check through a
second parse in arch.h itself).

Gates: `test/archcheck.sh` (new F-H9 section) — a valid capture applies (a real verdict, not a parse-time
refusal), an invalid capture refuses that edge by name, and a template broken independent of any capture
(an unmatched `(`) still refuses at parse time, unchanged.

### Fixed — a `#match?` predicate or an `--arch` path-rule that never reached the engine still filtered nothing

`#match?`/`#not-match?` (a `--match`/`--lint-rules` predicate) and `--arch` path-rules matched a captured node's
text, or a FROM/TO path, straight through the engine with no length bound — the same crash shape #251/the
regex-long-lines lane fixed for `--regex`, just not wired to these three entry points yet. A subject too long
for the engine on its thread now answers `RegexVerdict::Skipped` (never a silent Miss) at both: `#match?`
refuses like an abandoned match, naming the site (`--match`/`--lint-rules` exit 1); an `--arch` path-rule's
verdict refuses only when the skip could actually change the edge's answer — a LATER deny rule that decisively
matches the same edge settles it regardless, and the earlier skip is disclosed on stderr, not refused. That
"keep scanning past an undecided rule" shape used to stop at the FIRST undecided deny even when a later one
would have settled things either way; it now mirrors the allow-loop's own shape, which already scanned past an
undecided allow the same way.

Gates: `test/astqueryregexcheck.sh` (new arm G, red via `RIPWIRE_FAULT_REGEX_LINE_BOUND=1`), `test/archcheck.sh`
(a new section: arm 1 red via the same fault, arm 2 deterministic via a per-edge TO-template refusal — the
fault forces every `kCallerStackBytesFloor`-bound match to skip unconditionally, so a differential needs a
cause that isn't stack-size-uniform). quality-delta gating=0 (short-horizon-churn acked through the binary).

### Fixed — a skill scan that could not finish reading a line, or a directory, still said "clean"

`--scan-skill(s)` skipped a line the regex engine was never handed (too long for this thread's measured-safe
bound, the same bound `--regex` uses on a long matching line) and read it as an ordinary Miss, and a
`--scan-skills` walk that stopped early — a descriptor limit, not a permission error — was silently invisible:
the loop's own error was cleared in the same expression that set it, so the `if( ec )` guarding it could never
fire. Both are content that WOULD BE INSTALLED and was never actually scanned, so both now fail CLOSED
(CRITICAL, named `SCAN-INCOMPLETE:line-oversize` / `SCAN-INCOMPLETE:walk-stopped-early`), reconciling the
walk-only WARN an earlier round gave `ripwire wrap` with the CRITICAL `--scan-skill` already gives an engine
that gives up mid-match. An unreadable folder — content that install could not have picked up either — is
unchanged and stays WARN, the owner's own example of what does not need to fail closed.
`GuardedRegex::search`/`search(subject,captures)` (`src/regexguard.h`) take an optional per-thread stack bound
(default unbounded, so every existing caller is untouched) and answer `RegexVerdict::Skipped` rather than a
silent Miss when a subject exceeds it. Gates: `test/skillscanreadcheck.sh` (a new section), `test/codexwrapcheck.sh`
(a new section), both red on the unfixed binary via `RIPWIRE_FAULT_REGEX_LINE_BOUND=1` / the new
`RIPWIRE_FAULT_SKILL_WALK_STOP=1`.

### Fixed — a skill file the scan could not read, or held a NUL byte, is now reported instead of passing

`--scan-skills` counted an unreadable file (mode 000 in a readable folder, an I/O error) as `skipped=` and still
answered `verdict="clean"` at exit 0, and `ripwire wrap` read the same file as "no findings", with one pathless
degrade line on stderr however many files it hit. Both now score such a file CRITICAL and name it — a
`SCAN-INCOMPLETE:file-unreadable` row on the artifact, a `cannot read skill file <path>` line on stderr — so
`wrap` no longer emits the recipe over it without `--force`. The single-file `--scan-skill` already refused
that path. A folder the scan cannot enter stays WARN: its contents cannot be copied either.
`--scan-skills` also stops skipping a file because its first 8 KB hold a NUL byte: it scans it like any other
file, as `--scan-skill` and `wrap` already did — a PNG icon a skill bundles is now read (and comes back clean)
rather than skipped. `skipped=` counts unreadable files only.

Gates: `test/skillscanreadcheck.sh` arms (4) and (5), with the NUL-file arm re-pinned (`files="3"`, no
`skipped=`); `test/codexwrapcheck.sh` unreadable-file arm (red on the unfixed binary, with a readable control)
and a NUL-byte arm that pins `wrap`'s existing behaviour.

### Added

- **`--lsp` — a read-only navigation LSP server over stdio (Phase 1).** `definition`, `references`,
  `documentSymbol` (member variables merged into the outline), workspace symbol, and `hover` — the hover
  gist carries two clickable link tiers: **Used at** (the same call-role floor `--uses` answers with) and
  **Referenced at** (Ruby constant-load directives, so a class names the files that load it even where no
  call edge exists) — served to editors off the same warm index `--mcp` uses — no second parser, no
  second process. Saved-state answers, UTF-8 positions, every count labelled a floor in place; refuses
  `--mcp`/`--listen` — one protocol per stdin. A `workspace/symbol` query matching more than 20 symbols answers
  the first 20 and says how many it left out in a `window/logMessage`. A file URI outside the root (absolute,
  `..`-escaped, through a symlink, or percent-encoded) answers nothing, and malformed `Content-Length` framing ends
  the session at exit 1. The design record is `docs/LSP.md`; the gate is `test/lspcheck.sh` (17 arms, 19 checks, a
  scripted client speaking real LSP framing). Thanks to @mpapis.

### Fixed — a C++ member named like a class was read as that class

Rule 2c reads `Cls.m()` through a class name as a call on that class. It checked that no local shadowed the name, but
never checked members. Inside a C++ member function, name lookup finds a member of the class or of a base before any
namespace-scope class, so the token is the member. Two graded llvm-project instances resolved to ONE precise, wrong
edge:

- `LVReader.cpp:175 OutputFile->keep()`, whose member is `std::unique_ptr<ToolOutputFile> OutputFile`, went to
  `VirtualOutputFile.cpp OutputFile::keep`.
- `SampleProfile.cpp:1962 Reader->read()`, whose base-class member is `std::unique_ptr<SampleProfileReader> Reader`,
  went to msgpack `Reader::read`.

Rule 2c now refuses a C++/ObjC receiver that names a member of the caller's class or of a class up its bases. The
check reads the member side table, which holds every declarator shape, including the `std::unique_ptr<T>` members
Rule 2b's type table never records. A walk stopped by its 16-name cap also refuses. A raw-pointer member such as
`Widget* Raw;` is then typed by Rule 2b. Python keeps the route: its attributes are reached only through `self.`.

Measured with `--pin-census --no-cache`, joined on (caller, callee, line), against the alias fix above:

| Corpus | Sites retargeted | Changed target | Lost edge |
| --- | --- | --- | --- |
| rocksdb @ 0e2801ac3 | 0 | 0 | 0 |
| llvm-project @ 4d5358b1d | 1,398 | 1,346 | 52 |

Most llvm sites move from a namesake class to the member's real type: `IRBuilderBase` → `CGBuilderTy` overrides,
`Token` → `MIToken`, `Context` → `ASTContext`. The order matters. Without the alias fix, the same refusal lost 1,772
llvm edges and graded net-worse (60 blinded sites: 23 better / 3 same / 34 worse), because clang's `CGBuilderTy Builder`
had reached `IRBuilderBase` only through an unrelated class `Builder : IRBuilder` in HexagonVectorCombine.cpp.
With the alias fix in place, a seeded, blinded sample of 60 of the 1,398 llvm retargets graded 51 better, 7 same and
2 worse. The worse sites are one Rule 2b floor: `using CGBuilderBaseTy::CreateGEP;` re-exports base overloads the
class's own overload set shadows.

Neither instance above gets an edge in a scratch composition with the assignment-type lane, where they surfaced.

Gate: `test/clsrecvcheck.sh` arms H–N (a smart-pointer member, a raw-pointer member, a base's member, a class template
base's member, a member past the walk cap), red on the unfixed binary. Two controls hold: the same call from a class
without such a member keeps the route, and a Python `self.Interval` attribute does not veto `Interval.validate(v)`.

### Fixed — a base class or member type reached through a C++ `typedef` or `using` alias ended the base walk

The resolver walks a type's bases by class NAME, and an alias names no class. In llvm-project's clang CodeGen,
`class CGBuilderTy : public CGBuilderBaseTy` with `typedef llvm::IRBuilder<llvm::TargetFolder, CGBuilderInserterTy>
CGBuilderBaseTy;` stopped at `CGBuilderBaseTy`, so a member `CGBuilderTy Builder;` never reached
`IRBuilderBase::CreateCall`. The same happened for `BuilderType Builder;` (a class-scope typedef), `BuilderTy Builder;`
(a class-scope `using`) and every member or base typed through an alias of a class. Those calls got no edge, or a
split over every same-named method in the corpus.

The C/C++/ObjC capture now records a plain alias's target class, and the base walk continues at the target. Several
things are deliberately excluded:

- **Not every alias records.** A pointer, reference, array or function alias records nothing, and neither does a
  primitive, dependent or `decltype` target, or an alias local to a function body.
- **A target written in `std` is refused**, as a `std::` member type already is.
- **An alias named like a real class elsewhere is not followed.** Classes are keyed by bare name, so `using Base = Foo;`
  would otherwise hand `Foo`'s methods to an unrelated class `Base`.
- **The alias is not an inheritance fact.** It gains no `--lego` implementor, no `role="extends"` use-site and no
  HAS-A row.

**Alias templates are covered too.** `template <typename T> using SetTy = SmallPtrSet<T, 8>;` is an `alias_declaration`
inside a template declaration, so a member typed `SetTy<Foo>` walks on to `SmallPtrSet` and its bases.

The record rides the existing compose record shape, so the cache format is unchanged; `kParserVer` moves to 112 (claimed 111; integration/train-4 assigns 112 after the vexing-parse locals lane's 111).

**Known floor.** An alias records its target's class name without template arguments. So when an argument is the enclosing
template's own parameter, the walk lands on the primary template alone. For example, with `typedef SubT<marks> subtree;` it
drops an explicit specialization such as `SubT<true>` that the argument can also select. That is a lost candidate, never a
wrong-class pin. rocksdb's `omt_impl.h` hits it through `subtree_templated<true>`; before this change those calls split
over both. It is pinned as `test/fieldnarrowcheck.sh` arm t11, whose control `typedef SubT<false>` narrows correctly.

Measured with `--pin-census --no-cache`, joined on (caller, callee, line), main → this change:

| Corpus | Sites retargeted | Newly bound | Lost |
| --- | --- | --- | --- |
| rocksdb @ 0e2801ac3 | 366 | +111 | 0 |
| llvm-project @ 4d5358b1d | 2,649 | +1,146 | 0 |

A seeded, blinded sample of 60 retargets (25 rocksdb, 35 llvm) was graded against source: 57 better, 2 same, 1 worse.
The worse site is a class template specialization that shares the primary template's name.

Gate: `test/fieldnarrowcheck.sh` arm t. Arms t1–t4 are red on the unfixed binary. Arms t5, t9, t10 and t6's HAS-A row
each went red when the one guard they protect was disabled in a scratch build.

### Fixed — `--uses` on a `::` selector resolved `defs=` and then answered a silent `count="0"`

Every symbol-taking verb resolves the two `::` spellings the tool prints about itself — the canonical id
`path::scope::name` and `Scope::name` — but `--uses` then matched reference sites against the whole spelling, which
no call site carries, so a resolving selector answered `count="0"` (issue #164). `resolveUsesSelector` now takes the
resolved defs and, when they share one name, matches sites by that name and narrows the call role to those defs,
exactly as a `file:name` selector does; `--safe-delete` and `--verify` get the narrowed scan too. A wrong scope
(`Nope::ctwin`) still refuses, a member spelling with no symbol behind it still takes the field path, and an
all-Elixir resolution keeps the Elixir resolver's arity-exact sites. The MCP `uses` verb refuses a resolving `::`
spelling as CLI-only with the bare-name retry, the way `file:name` already refuses, instead of the silent zero; the
legend and `--help` name both spellings that narrow. `test/usesselectorcheck.sh` flips every KNOWN GAP arm to its
fixed answer and asserts the `::` and `file:name` twins give the same rows and that every call row sits inside
`--callers`. Thanks to @aniruddhaadak80.

### Added — `--doctor` detects a struct layout that differs between translation units

Each translation unit that includes `src/model.h` records `sizeof` and `alignof` for the shared model types
(`Symbol`, `Reference`, `Include`, `Binding`, `IngestResult` and the rest) in an internal-linkage registry that
survives Release and LTO, and `--doctor`'s `layout` row compares them: `state="agree"`, `state="disagree"` with
the first differing type and both units' sizes and alignments plus the rebuild action, or `not-checked` /
`no-records` when there is too little to compare. A mixed build — the stale-object failure CLAUDE.md warns about —
is now named rather than debugged. Stated floors: a field reorder that keeps both size and alignment, and a unit
that never includes the header, are invisible. `test/structlayoutcheck.sh` proves the disagreement on a
deterministic two-unit fixture (sizes 4 and 8) and the `not-checked` state on one unit. Thanks to @lennix1337.

### Fixed — a member held by `std::unique_ptr` or `std::shared_ptr` had no type, so every call through it guessed

The member-field capture that feeds Rule 2b read a qualified type only when a plain name sat directly under the `::`.
In `std::unique_ptr<ToolOutputFile> OutputFile;` that name is a template, so the member recorded no type at all, and
`OutputFile->keep()` took the bare-name ladder: a split over every `keep`, a locality pick, or no edge. A member written
`std::unique_ptr<T>` or `std::shared_ptr<T>` now records T, marked as reachable through `->` only, and every C++ call
reference records whether its member access was written `->`. Rule 2b narrows `p->m()` to T's `m` and leaves `p.m()`
alone, because `.` names the smart pointer's own `reset` or `get`. The `->` requirement matters: without it, 9
llvm-project sites (`MC.reset(…)`, `MII.get()`) bind the pointee's same-named method. A list of smart-pointer member
names cannot stand in for the bit either, since it would also refuse 38 `->get()`/`->reset()` narrows the change makes.
No other template is read through. `std::vector` has no `->`, and an in-repo `Holder<T>` may overload it onto anything.
Two same-named classes whose same-named member is reached through `->` in one and as the member itself in the other now
tombstone each other, as two different types already did. Recording every other `std::Tmpl<…>` member as a std type
was measured and rejected: on both corpora it changed 6 sites, and all 6 got worse. `--uses=Owner.field` reads the
same record, so `w_->level` pins to the pointee's `level` instead of every owner's.

Measured with `--pin-census --no-cache`, C rows joined on (caller id, callee, line) against the previous commit:
rocksdb @ 0e2801ac3 retargets 809 sites (448 gain an edge, 355 change target, 6 lose one; bound +442), and
llvm-project @ 4d5358b1d retargets 793 (498 gained, 295 changed, 0 lost; bound +501). A seeded, blinded, stratified
sample of 60 retargets graded against source came out 53 better, 4 same and 3 worse. The 3 worse sites are limits Rule 2b
already had, now reached through a smart pointer: a pointee class name shared by nested classes (`Iterator`), and two
overload picks that miss a default argument. The ref record grows by one byte, so kCacheVersion moves 23 → 24 and
kParserVer 112 → 113 (integration/train-5 assigns both; the PR declared 22 → 23 and 103 → 104).

`test/fieldnarrowcheck.sh` arm p is the gate. p1–p4 (the narrow), p7 (`--uses`), all four p8 tombstones and p9 (the warm
cache) are red on the previous commit. p5 (`w_.reset()`) is red on a build that ignores the `->` bit, the p6 in-repo
template controls on a build that reads through any template, and a p8 row on a build without the new tombstone.
`qschemetripcheck` is re-pinned for both versions, and `cachefuzzcheck`'s record walker learns the new byte.
`localitycheck` arm 6 had used a `std::unique_ptr` member as its example of a type Rule 2b cannot read; it now holds a
qualified non-std template, and new arm 6b asserts the smart-pointer member narrows (red on the previous commit).

### Fixed — a function definition returning a reference recorded none of its parameters

A C++ function definition finds its parameter list by walking its declarator chain down to the function declarator, and
the walk read only each declarator's `declarator` field. A definition returning `T&` or `T&&` reaches its function
declarator through a `reference_declarator`, which holds it as an unnamed child, so the walk stopped there and the
parameters recorded nothing: no declaration for shadow suppression, no written type for Rule 2's parameter receivers or
the field use-site index. `Target& Decoy::refCaller( Target& other ) { other.pick( 1 ); … }` fell to the locality
tie-break and linked `Decoy::pick`, and `int& refRet( int run ) { run += 1; … }` listed its own parameter's write under
`--uses=run`. The walk now unwraps reference, parenthesized and attributed declarators, as the shadow capture already did
for the first two, and the shadow capture unwraps `attributed_declarator` too, so `int run [[maybe_unused]] = 0;`
declares `run`. kParserVer 113 → 114 (integration/train-5 assigns it after #282's 113; the lane declared 104 → 112); no record layout changes.

Measured with `--pin-census --no-cache`, C rows joined on (caller id, callee, line) against the previous commit:
rocksdb @ 0e2801ac3 retargets 28 sites (1 gained, 27 changed, 0 lost), and llvm-project @ 4d5358b1d retargets 1,318
(977 gained, 331 changed, 10 lost; `calls=` falls by 11). Of the 10 lost, 5 were Rule 2c reading a parameter named like
a class as that class (`QualType Type`, `MaybeAlign Align`), and the rest were calls through a callable parameter
(`Compute()`, `Pred( Str )`) linked to a same-named function. A seeded, blinded sample of 26 graded against source came
out 24 better, 1 same and 1 worse; the worse site is `Type->isRecordType()` on a `QualType Type` parameter, which Rule 2c
had reached only because the parameter's name spells the class.

`test/narrowcheck.sh` arms 61-63, `test/shadowcheck.sh` arm am plus a body write in arm q8's attributed declarator, and
`test/fieldnarrowcheck.sh` arm s3 are the gates, all red on the previous commit. `qschemetripcheck` is re-pinned for the
parser version.

### Fixed — a member the method assigned before calling it read as a local, so Rule 2b refused its declared type

Rule 2b narrows `m_p->m()` to the member's declared type unless a local of that name hides the member, and it decided
"local" from ANY binding record for the name in the method. Ingest records assignments too: `x = Foo()` and
`x = std::make_unique<T>( … )` record the callee's name as a Type binding, `x = other` an L3 function-pointer binding,
and `x = nullptr` a clobber once the file binds `x` to a function. An assignment declares nothing, so every member a
method assigned before calling it lost its narrow — llvm-project's `LVSplitContext::open`, `OutputFile =
std::make_unique<ToolOutputFile>( … ); OutputFile->keep();`, had no edge. The veto now reads declaration records alone
(VarDecl, ParamType, FnDecl); every local-declaring shape emits one once the entry above lets a reference-returning
definition's parameters and an attributed declarator record theirs. Rule 2c and the Phase 5 external-name veto still read
every record: they ask whether the name is a variable at all, and an assignment says so. Letting Rule 2c ignore
assignments too was measured and rejected — it moved 7 llvm-project sites and no rocksdb site, 6 worse and 1 same, each
reading a member such as `OutputFile`, `Context` or `Section` as the class it spells.

Measured with `--pin-census --no-cache`, C rows joined on (caller id, callee, line) against the previous commit:
rocksdb @ 0e2801ac3 retargets 118 sites (67 gained, 51 changed, 0 lost), and llvm-project @ 4d5358b1d retargets 683
(521 gained, 162 changed, 0 lost); every one is decided by Rule 2b. What used to veto them: an L3 FnAssign or clobber
record for 88 rocksdb and 479 llvm-project sites, a Type record naming a class for 13 llvm-project sites, and only a
Type record naming no class for 30 and 191 — the sites #278's assignment-type guard also releases. A seeded, blinded
sample of 40 graded against source came out 35 better, 4 same and 1 worse; the worse site is a member `Instruction *`
whose name-based base walk reaches a namesake `Value` class in another namespace, a Rule 2b limit this change only
exposes.

One declaration still records none, and is pinned as a floor: a direct-initialised local whose arguments are plain
names, `Foo x( a, b );`, parses as a function declarator, so a call inside its scope takes the member's type. No
retargeted site on either corpus has such a receiver. Composed with the branch that stops minting a phantom function for
that declarator, the change retargets 24 more llvm-project sites, and all 24 name the member outside the local's block
(`MIB.buildInstr( … )` in `AArch64InstructionSelector::select`), which the previous veto refused across the whole method.

`test/fieldnarrowcheck.sh` arm v is the gate. v1 (five assignment shapes) and v3's member pickup are red on the previous
commit; the v2 declaration controls are red on a build without the veto, three of them (the reference-returning
parameters and the attributed declarator) on this veto without the entry above; v3's class-name rows are red on a build
whose Rule 2c ignores assignments. v4 pins the floor.

### Fixed — a member declared in a base class had no type in the derived class, so every call through it guessed

Rule 2b types a bare member receiver from the `Class#field` table, and it looked the field up on the caller's own class
only. A member the class inherits was never found: in `class SampleProfileLoader final : public
SampleProfileLoaderBaseImpl<Function>`, `Reader->getSummary()` names the base's `std::unique_ptr<SampleProfileReader>
Reader;` and took the bare-name ladder, which gave a split over every `getSummary`, a locality pick, or no edge. When the
class declares no member of that name, Rule 2b now walks its bases breadth-first, the way it already walks a type's bases
for a method. The shallowest level with a base declaring the member decides, and it has to be exactly one base whose
member type was captured. A member counts as declared when it is in the field side table, typed or not. So an own
`std::optional<Widget> Reader;` whose type the capture skips still hides the base's `Reader`, and so does one at any
base level before the hit. Two bases declaring the member at one level refuse, and so does a walk the 16-name cap cut
short. A local of that name still vetoes the narrow. A class template's dependent base is walked like any other base,
though C++ lookup never searches one for a bare name. This is a disclosed floor. It was measured first: 5 of the
2,203 sites this change moves sit in such a template, and all 5 are right. Three reach the template's non-dependent
base, and two reach a `using Base::G;`.

Measured with `--pin-census --no-cache`, C rows joined on (caller id, callee, line) against the previous commit:
rocksdb @ 0e2801ac3 retargets 374 sites (236 gain an edge, 138 change target, 0 lose one; bound +236), and
llvm-project @ 4d5358b1d retargets 1,829 (731 gained, 1,098 changed, 0 lost; bound +735). A seeded, blinded, stratified
sample of 60 retargets graded against source came out 52 better, 3 same and 5 worse, and in all 60 the grader traced the
receiver to a member of a base class. The 5 worse sites are limits Rule 2b already had, now reached through a base
member: a type name shared by classes in two namespaces (`llvm::Module` and `sandboxir::Module` twice, `Sema` and
`comments::Sema` once), and two overload picks that ignore the argument count. `SampleProfile.cpp:1962`, the
`Reader->read()` that motivated the change, still gets no edge. The assignment `Reader = std::move(...)` five lines up
records a local binding, and the local-shadow veto refuses the member; a fixture with the assignment deleted narrows.

`test/fieldnarrowcheck.sh` arm w is the gate. w1, w2, w4 (the narrow and its `prov="final-segment"`), w10 and the w12
floor are red on the previous commit. The refusals were each shown red on a mutated build: counting only typed
members as declared reds w6 and w7, taking the first declaring base reds w8, and probing a level the cap cut instead of refusing reds w10w.

### Fixed — a Python module ALIAS no longer loses its call edge to name-level ambiguity

Reported by **@SVC-MACSTUDIO** in #287: `import target_mod as tm` then `tm.run(…)` dropped the call edge into
`graph_ambiguous` whenever `run` was ALSO defined elsewhere in the tree, even though the alias unambiguously
names one module — a unique callee name already resolved (the bare-name ladder's own accidental win, not real
module resolution). The alias's module is now resolved to a file (`resolve.h::resolvePythonModuleSuffix`, a
whole-path-component-suffix fallback for an absolute spec Step-A's two exact bases can't place, reusing the
same matcher `canonicalIdMatches`/`sameTreePath` already use) and used to narrow the candidates for
`alias.name(…)`: bind iff exactly one candidate remains in that file, else the unchanged ambiguous/disclosed
behaviour. Handles `import X`, `import X as Y`, dotted `import a.b.c [as Y]`, `from pkg import X as Y`, and a
package `__init__.py` target; does not follow a package `__init__.py` that re-exports from a submodule, or a
`from pkg import submodule` shape — both degrade safely rather than guess.

A second pass closed a soundness gap review found before this shipped: the alias name can be REBOUND — a
plain or augmented assignment, a `for`/`with`/`except … as` target, a walrus, a `del`, a nested `def`/`class`
of the same name, or a `global`/`nonlocal` declaration — after the import and before the call, and Python
records no local-assignment binding today, so the rebinding was invisible and the narrow bound the call to the
STALE import anyway. Every one of those forms is now captured as veto evidence
(`ingest_binds.h::capturePythonRebindShadowDecls`): a rebind inside a function refuses only that function's
calls (the existing per-function shadow-evidence path, the same one a parameter shadow already used); a
rebind at module scope, or a `global`/`nonlocal` statement anywhere in the file, refuses the alias file-wide,
because a module-global rebind can reach every function that reads it.

Measured on real Python corpora (Django, DGL, numpy): the module-alias narrow bound 26 new call edges on
numpy alone (zero on Django/DGL, whose aliased internal imports resolve to package `__init__.py`s that
re-export from a submodule rather than defining the name directly — the documented limitation above). A
hand-graded sample of 17 of those 26 came back correct against source, including cases the fix also happens
to CORRECT rather than merely add: `numpy/polynomial/tests/test_polynomial.py`'s `poly.polyval(…)` calls
(`import numpy.polynomial.polynomial as poly`) were previously mis-attributed to the unrelated, same-named
`numpy/lib/polynomial.py:polyval` by the bare-name ladder; they now correctly attribute to
`numpy/polynomial/polynomial.py:polyval`. The rebind veto did not remove any of the 26 — none of the sampled
call sites has a rebind of its alias in scope, so this pass's honest measurement is a rebinding-soundness
fix with no numpy-corpus cost, not a trade-off.

### Changed — ingest releases each raw-fact family as soon as its last consumer has run

Ingest used to hold every raw-fact container until the end of the run, so the peak held all of them at once. They
are now released as soon as their last consumer has run: the parse cache map, `refOrder`, the raw references,
definitions, bindings and route uses, the field definitions, the `DefSpanIndex`, and the parse pool's per-thread
fact vectors. It is a body-only change; no signature moves and no output changes.

Measured on an llvm + clang checkout (10,266 files, 8,837 of them C/C++, 644 MB), `--no-cache`, five runs per binary:
peak RSS went from 2,380–2,476 MiB to 2,223–2,248 MiB. The two ranges do not overlap; the drop averages about
174 MiB (7%). This is a subset of the full llvm-project monorepo, which was not re-measured. Output was byte-identical
in 14 of 14 comparisons: 8 for this change (cold and warm map and `--for`, on that corpus and on this repository)
plus 6 from the earlier investigation. No gate guards it:
peak memory is recorded as a measurement, not enforced as a budget. Split out of #44 (native Windows port).
Thanks to @lennix1337.

### Fixed — `readFilePrefix` reported success on a prefix a read error had truncated

`readFilePrefix` reads the first `maxBytes` of a file for the prewarm grammar-sniffing heuristics (the ObjC-header
probe is its one caller), reusing one buffer per worker across every file it samples. Its success check was
`got > 0 || feof( fp ) != 0` — true for any nonzero byte count or a clean end-of-file, but blind to the stream's own
error indicator. A `fread()` that returned fewer bytes than requested because the underlying read failed partway,
not because the file was actually that short, still satisfied `got > 0`, so the truncated bytes went back as though
they were the whole prefix and the sniff judged a header it never fully read. `readFile`, a few lines above it in
`src/ingest_crawl.h`, compares the byte count against the size it expects and fails on any `got != want`;
`readFilePrefix` has no expected size (a file shorter than the prefix is a clean short read), so it now consults
the stream's error indicator instead: `ferror( fp ) == 0 && ( got > 0 || feof( fp ) != 0 )`, so a live error
indicator fails the read regardless of how many bytes made it through. Effect is limited to the prewarm hint —
parsing itself is unchanged either way, which is why this is neutral on output.

Split out of #44 (native Windows port), where it rode inside commit 9124d689. Gate: `test/crashsweepcheck.sh` arm
B4. B1's interposed short-read shim gains an env-selected `eio` mode — a marked `fread` delivers 16 bytes, then raises
the stream's error indicator with `errno = EIO` and no end-of-file — and B4b compiles `readFilePrefix`'s own source
text into a harness run under it: `ok=1 bytes=16` on the previous commit, `ok=0 bytes=0` after. B4a is the control
(a clean read to EOF under the same shim is the whole 64-byte prefix), and B4c runs the binary on an ObjC header whose
`@interface` sits past byte 16 with that read failing: the answer is byte-identical before and after the fix, so the
arm pins only that it survives. Thanks to @lennix1337.

### Fixed — `ripwire wrap`'s MCP JSON stanzas broke on a command path holding a quote or backslash

`ripwire wrap cursor|windsurf|gemini|opencode` (and the generic `mcpServers` stanza) print a JSON config whose
`"command"` field is either the literal string `ripwire` or, when nothing named `ripwire` resolves on `PATH`, this
binary's own absolute path. That path went into the JSON string raw: a double quote (legal in any POSIX filename)
or a backslash (every Windows path, and also a legal POSIX filename byte) produced a stanza that failed to parse,
or closed the string early on the quote. `wrapMcpJson` and `wrapMcpJsonOpencode` now pass the token through
`rw::jsonesc::escapeMcp` (`src/infra/jsonesc.h`), the escaper the MCP surface already uses elsewhere — no new
escaping code.

Split out of PR #44 (native Windows port), where it rode inside the follow-up snapshot commit e795983f on
lennix1337/ripwire:win32-port-snapshot. The fix is @lennix1337's, forward-ported and gated here.

`test/opencodewrapcheck.sh` arm 8 copies the binary into a directory whose name carries both a quote and a
backslash, with `PATH` holding no `ripwire`, and requires the `opencode` stanza and the `mcpServers` (cursor)
stanza to both parse as JSON and name the running binary. Red on an unescaped build (`Expecting ',' delimiter`);
green once both printers route through the shared escaper. Thanks to @lennix1337.

### Fixed — `--index-out` dropped `--no-ignore` on the generated artifact

The generate path called `ingest()` without the `respectGitignore` argument, so `--index-out`'s artifact always
honoured `.gitignore` even when `--no-ignore` was also on the command line; every other `ingest()` call site
already passes `!cfg.noIgnore`. A `--no-ignore` consumer of that artifact found the ignored files missing and
reparsed each one cold, which defeats the artifact's point — its whole value is that the consumer does not
reparse. `--index-out` now threads `!cfg.noIgnore` through to the generate ingest, matching the other call sites.
`test/indexoutcheck.sh` arm (e) is the gate: in a git fixture with an untracked file under an ignored directory,
it reads the artifact's own file set rather than relying on restore-equivalence (which can't see a dropped
argument — a missing record just looks like a miss) — a control default artifact must omit the file, a
`--no-ignore` artifact must hold it, and a `--no-ignore` consumer of that artifact must report `reparsed=0`.
Split out of #44 (the native Windows port), where the argument rode inside one bundled commit next to an
unrelated cache-directory parameter. Thanks to @lennix1337.

### Fixed — the prompt-routing hooks recommended nonsense on harness notifications and ordinary prose

The Claude Code and Codex prompt hooks passed every prompt to `--help-task`, including background-agent
notifications, and `--help-task` counted any capitalised word or single letter that happened to name an indexed
symbol as a symbol mention. In a fixture-heavy tree, prose like "Summary: A, Fix, Report" was routed to
`--connect=Summary,A,Fix,Report` at `confidence="high"`. The hooks now skip prompts that begin with a harness
event tag (still logging a `skip-system` meter row). `--help-task` counts a word as a symbol only when it is
identifier-shaped: a camel or Pascal seam, an underscore, a `::` or `.` qualifier, backticks or `()`, or at least
four characters and not a common word. A short real symbol routes when backticked (`` `F` ``); the rule and
that escape hatch are documented in `--help-task`, its legend and the router skill. On the labelled routing
corpus exactly 4 of 254 decisions change, and the measured harmful rate drops from 0.016 to 0.000.

### Fixed — assumptions the code tested again, and a CMake scan failure reported as "no CMake"

Three `ASSUME`s (`gitmine.h`, `mention.h`, `abicheck.h`) were followed by a runtime test of the same condition.
Each condition is guaranteed by the code that sizes both sides, so the promise stays (`EXPECTS` or `ASSUME`)
and the unreachable fallback is removed. `test/selfcheckcheck.sh` arm T now flags an assumption that is tested
again within the same function. `--flags` could not tell a CMake root it failed to read from a tree with no
CMake: it now reports `cmake_scan_failed="1"` in every build (`test/flagscheck.sh` arm 11). Five
`ASSUME_NO_ALIAS_BUF` promises on fresh local buffers state that separate storage to the compiler; each was
checked against every caller.

### Fixed — a degraded answer now says so in every build, including Release

Before this change, 217 degrade paths recorded that an answer was incomplete only through a debug-build assertion.
Release builds compile those checks out, so the binary users run printed a partial answer as if it were whole. The
self-check `DISCLOSE( sink, why )` form now records the degrade into the output document in every build. 51
one-argument sites remain, each listed with its reason. Where an answer was wrong rather than just incomplete, the
output now says so:
- `--note-add` refuses a sidecar line it cannot parse instead of deleting it, and `--notes` reports `lines_skipped=`.
- A refused symlinked notes or arch sidecar is named.
- `--grep` marks its hit count as a floor when a file could not be read or the scan stopped part-way.
- `--for` reports `reason="degraded"` when it could not serve bodies.
- `--max-tokens` reports `fit_unmeasured` when it could not measure the fit, in both XML and JSON.
- `--whereis` no longer claims `complete="1"` after dropping a ref, and a failed git worker's refs read as unknown,
  not merged.
- `--slice` reports `reach_converged="0"` when its fixpoint stopped at the bound, and it refuses (and says why)
  when git's answer for a date baseline is not an object name.
- merge-scout no longer diffs against an unavailable tree as if it were empty.
- A file whose extraction came back partial is listed under the new `--skipped` class `extract-partial`, is no
  longer cached as complete, and older caches are invalidated.
- When the token measurement fails, `est_tokens` keeps its modelled number and is labelled `est_measured="0"`.
- `--layout` exits **3** when a definition's file cannot be read (2 still means drift, 0 means verified), so a CI
  gate on its exit code no longer passes an unverified mirror.
- `--stray-content` (and its `--plan`) reports `refs_dropped=N` when a for-each-ref row's tip is not an object
  name, instead of silently dropping it from `refs=` and every bucket with no sign a branch went unswept.
- doc-drift's on-disk fallback walk (the one that keeps an existing-but-unindexed file from reading as
  missing) reports `disk_walk_failed="1"` on a root it cannot list — libc++/libstdc++ swallow `EACCES` on the
  root itself under `skip_permission_denied`, so an unlistable root used to read as an empty, successful walk.
- `--flip`'s alias-chain walk discloses the DEPTH bound too, not only the fan-out cut: a gate reached only
  past `kMaxChainDepth` links used to drop out with no `<capped>` row; it now carries
  `<capped what="depth" at="N"/>`.
- merge-scout's head-conflict lane and its working-tree arm now refuse an unavailable HEAD tree the same way
  the named-arm lane already did — an arm whose lane could not run carries `head_conflicts_ok="0"` instead of
  reading the missing tree as empty (every base symbol a false head conflict) or as entirely uncommitted (the
  working-tree arm).
- `--pack-task`'s ranking or bodies render failing no longer drops the section silently or writes an unkeyed
  JSON value: the section stays and carries `render_failed="1"`, the root names every failed section
  (`render_failed="ranking,bodies"`), and a failed body-cost probe prices that body out instead of free.

Refusals whose only disclosure is the refusal itself (a non-zero exit, an MCP error, a query failure) are recorded
through `answerRefused`. Ten guards that could not fire were removed after tracing each one: those guarded by our own
code became `ASSUME`/`EXPECTS`, and those touching external input kept a checked, disclosed path.
`CONTRIBUTING.md`'s error ladder now says a degrade that still prints an answer must record into the document.

### Changed — `--help-task` routes four more question shapes to a first verb

`--help-task` used to abstain on four common question shapes. It now routes them:
- which tests cover a file → `--affected`
- what else changes with a file → `--situ`
- how one named file reaches another → `--for`
- where a named thing is implemented → `--for`

On the labelled routing corpus none of the 254 decisions changed, and held-out precision stays 1.000 with harmful
recommendations at 0.000. A 12-question paraphrase arm routes 10 correctly, with no wrong verb.

## [0.6.1] — 2026-09-14

**A header selector answers only with the definitions it can tie to that header, every number a compact answer prints
comes with its definition, and the answers an agent reads got smaller.** Outside contributors wrote the Elixir
module-and-arity resolution (**@henry-hz**), taught `--scip` to read the indexes scip-java writes (**@dpunosevac**),
made the callers answer's `next=` pointer land on the call site it promises (**@antoleod**, in their first
contribution to ripwire), wrote the README's reference guide (**@heliocipher**), and taught the Ruby dependency view
that a constant argument and a rescue class are dependencies (**@andriytyurnikov**). Each is named below, beside the
entry their work produced.

### Highlights

**The release ran against ripwire's own instruments, and the instruments say what moved.**

*What the instruments are.* Three readouts, all registered before the work began, and none of them a model's opinion.
A frozen bank of 30 retrieval questions, each answered in ONE call on a 2,066-file C++ corpus pinned at one commit,
scored on the gold files the question's answer must name. A follow-up ladder over the same bank: six deterministic
steps per tool, no model in the loop, scored on how many questions reach a complete answer by step N. And a held-out
draw registered separately, so a round cannot be tuned onto the bank it is graded on. Every figure below is the same
question asked of two binaries on the same corpus at the same commit, `wc -c` on stdout, warm cache.

*What got better.* The work this round was routing and shape, not ranking: giving a question a scope it could not
state before (`--in=DIR`), a widening page when the single-call answer is thin (`--for … --limit=N`), and one row per
group where the answer had been repeating one fact per row. Complete answers and bytes-to-a-complete-answer are the
two numbers that decide whether that paid; the re-measure on those instruments is not part of this release's record, so
what this section stands on is the per-verb measurement in each entry below, every one naming its corpus and method.

*Where the bytes went.* Three shapes account for nearly all of it: a "what changed recently in this directory"
question that used to be answered with a whole-repository map now collapses that map to a 61-byte stub and adds a
scoped window; every scoped symbol row on a map drops the canonical id it had just printed the path half of, keeping
`sc=` instead; and a tests-to-run list on a corpus whose harnesses have no derivable runner states that fact once per
group instead of once per row. None of the three drops a row, a path or a disclosure — the multiset of answers is
unchanged in each case, and each entry below names its corpus and its method.


**Elixir resolves modules and arities statically.** Calls resolve to the module, name and arity they name, instead of
by name alone: lexical aliases, filtered imports, default arguments, pipes, captures and delegates. Nested modules and
each target of a multi-target `defimpl` have separate identities, types and callbacks are navigable, and CLI and MCP
use-site queries share one set of rules. Macro expansion, `__using__` and calls inside `unquote(…)` / `bind_quoted:`
remain static-analysis limits and are documented as such (@henry-hz,
[#81](https://github.com/redhat-et/ripwire/issues/81), landed as
[#207](https://github.com/redhat-et/ripwire/pull/207)).

**`--scip` works with scip-java.** SCIP writers encode an occurrence's range in one of two ways, and ripwire read only
the deprecated one, so every index scip-java writes was silently ignored and `--scip` changed nothing. It now reads the
typed form first, as `scip.proto` asks. On spring-petclinic the precise overlay went from no matches to 79% of
occurrences (@dpunosevac, [#198](https://github.com/redhat-et/ripwire/pull/198)).

**Numbers that shipped without a definition now have one.** `graph_unindexed=` shipped in 0.6.0 with no definition on
`--lego`, `--verify` and `--nonlocal-state`, and under `--legend=compact` on every XML verb except `--connect`
([#169](https://github.com/redhat-et/ripwire/pull/169)). Compact answers also carried `declined_calls=`,
`unproven_defs=`, `pr_iters=`, the map header's own counts, `--impact`'s blast-radius counts, `--safe-delete`'s verdict
fields and the `--communities`/`--community` structure counts with no definition; each is defined now, and the compact
pins follow the definitions rather than the definitions being trimmed to fit one pin
([#185](https://github.com/redhat-et/ripwire/pull/185), [#189](https://github.com/redhat-et/ripwire/pull/189),
[#203](https://github.com/redhat-et/ripwire/pull/203)). A budgeted `--for` that drops legend clauses to fit its
allowance now names the attributes whose definitions it dropped ([#174](https://github.com/redhat-et/ripwire/pull/174)).

**A header selector answers only with what it can prove, and says what it dropped.** A `file:name` selector that names
a C++ header declaration is widened to the definitions the declaration stands for. The widening matched on the name and
the enclosing scope, and that scope drops namespaces, so `--callers=a/Store.h:putObject` counted `callB` in
`b/Store.cpp`, a caller of a different `Store`, and a free function matched on its name alone. A definition is now kept
only when its file is the header or includes it, resolved path-precisely
([#173](https://github.com/redhat-et/ripwire/pull/173)). What the proof drops is counted as `unproven_defs=` on
`--callers`, `--callees`, `--impact`, `--safe-delete`, `--path`, `--uses`, `--mentions`, `--verify` and `--affected` —
all but the first two had answered from the declaration alone and printed a clean zero
([#190](https://github.com/redhat-et/ripwire/pull/190), [#195](https://github.com/redhat-et/ripwire/pull/195)) — and on
every verb that resolves a focus symbol at all, `--edit-check` included, where an `incompatible="0"` beside
`unproven_defs=` is now stated to be an incomplete read rather than a safe edit
([#210](https://github.com/redhat-et/ripwire/pull/210)). On ripwire's own tree, over every `file:name` selector whose
selection is all declarations, the binary after #173 shrank 89 of 4,322 answers compared with the one before it, and
grew none.

**The declined-call index fits in memory on a tree the size of llvm.** The call graph keeps, for every call the
resolver declines to bind, the list of candidates it declined between. Those lists were stored once per call, so the
structure grew with calls × candidates: 27.9 M entries, 114 MB, on llvm-project. One stored copy per distinct list
makes that 9,879 distinct lists and 62,359 entries — **368 KB** — with every count and every byte of output unchanged
([#208](https://github.com/redhat-et/ripwire/pull/208)).

**The commands ripwire writes for an agent ask for the compact legend, and say how to get the full one back.** Every
`ripwire <dir>` command in the skills, in the `ripwire wrap` paste block, in the prompt routers and in the tool routes
now carries `--legend=compact` where the verb accepts it — 158 skill commands, 9 wrap commands, 26 `--help-task`
routes and 2 tool-call routes. One sentence per surface, and not one more, says to add `--legend=full` when a
definition's reasoning is needed. The bare CLI is unchanged: it still answers with the full legend
([#215](https://github.com/redhat-et/ripwire/pull/215)). Alongside them, `--for` now pages its answer one file per row
and says when the single-call answer is thin enough to widen
([#213](https://github.com/redhat-et/ripwire/pull/213)), and `--rank-by=churn-decay --in=DIR` answers "what changed
recently in this directory" without a whole-repository map
([#212](https://github.com/redhat-et/ripwire/pull/212)).

**An agent can ask for the recency answer in words, and every new shape of this release is named where an agent
reads.** The task router had no churn or recency intent at all, so `what changed recently in db` and `who touched this
lately` abstained at `score="0"` and the churn window was unreachable from a task said in words. It routes now, and
composes `--in=DIR` only when the task names a directory of the corpus and the running build's own flag table ships
the flag. Every `--for`-shaped recommendation carries the widening page on the FIRST call rather than only after a
thin answer, four skills name the shapes this round adds, and a new ratchet keeps it that way: a flag `--help`
advertises with no agent surface, or a surface promising a shape the build refuses, goes red
([#218](https://github.com/redhat-et/ripwire/pull/218)).

### Upgrade notes

- **One cold parse.** The parser version moves to 93 (#139), then 94 (#172), then 95
  ([#207](https://github.com/redhat-et/ripwire/pull/207)); the cache format moves from 20 to 21 (#139) and stays there.
  `loadCache` returns empty on a version-or-parser-version mismatch, so the first run after upgrading reparses the tree
  and rewrites its cache. The quality snapshot scheme moves from 10 to 11 (#207), so the first `--quality-delta` after
  upgrading recomputes its snapshot.
  The parser version moves once more, to 96, and the cache format from 21 to 22, for the internal-linkage bit on
  every C and C++ definition ([#216](https://github.com/redhat-et/ripwire/pull/216)); a cache written by 0.6.0 is
  rejected and rebuilt on the first run either way.
- **A sidecar must be a regular file: a symlink at a sidecar name is refused, on read as well as on write.**
  `.ripwire_notes`, `.ripwire_quality_baseline` and `.ripwire_arch_baseline` are opened with `O_NOFOLLOW`, so a
  link at one of those names is not opened, wherever its target is. Anything else at the name that is not a regular
  file, a FIFO for example, is refused as well instead of being waited on. If you symlinked one on purpose (into a
  shared config directory, say), replace the link with a regular copy of its target. Until you do, every read of it
  prints a refusal on stderr, no notes surface, `--quality-delta` reports `baseline="git-HEAD (symlinked sidecar
  refused)"` and compares against HEAD, `--arch` reports every violation as new, and `--note-add`,
  `--quality-baseline`, `--arch --baseline` and `--baseline-update` exit 1 without writing. `.ripwire_config` and
  `.ripwire_quality_acks` are unchanged (#178, [#191](https://github.com/redhat-et/ripwire/pull/191)).
- **New flags and flag behaviour.**
  - `--in=DIR` is new, on the default map's churn-decay branch only (`--rank-by=churn-decay --in=DIR`). DIR is
    root-relative and must exist under the root; absolute paths and `..` are refused. Under `--in`, the symbol map
    collapses to a `<symbols stubbed="1" would_show=N next="--rank-by=churn-decay"/>` stub and a second
    `<recent scope= n= of= merge_bombs_skipped=>` block follows the global one, which stays byte-identical. `--in`
    joins the house `--offset=`/`--limit=` paging set; it is refused, naming the remedy, with any other verb, with
    multi-root, with `--top-k=0` and with `--json` — and, since the CI round, refused rather than silently ignored
    when a report verb wins dispatch (#212).
  - `--for=TASK --limit=N` no longer means what it meant: it now serves a file-grain widening page, one
    `<f p= score= n= sym=/>` row per positive-score file, paged with `--offset=M`. `--top-k` stays inert on `--for`,
    and `--help` now says which flag widens. Beside the page every bundle-shaping flag is refused, never ignored
    (#213).
  - `--legend=compact` is what the generated agent commands now ask for — the skills, the `ripwire wrap` paste block,
    the prompt routers and the tool routes. Add `--legend=full` to any of them to get the full legend back; the MCP
    `legend` argument's schema description now says so too. The bare CLI default is unchanged (#215).
- **Output that changes by design.** Each change is described in its entry below.
  - **`sc=` replaces `id=` on map and lens symbol rows.** A scoped row carries `sc=`, the enclosing scope; the full id
    composes as `p::sc::n`, with `p=` read from the row or from its `<f>` wrapper, and the legend states that
    composition. **Every selector still accepts the composed `id=` spelling on input** — `--expand`, `--callers`,
    `--impact`, `--uses` and the MCP twins are untouched. `<cand>` rows, `--expand`'s whole-file anchors and
    `--merge-scout` rows keep `id=`, because their path does not repeat on the row. `--json` twins print `"sc"`.
    `route=` on `--for` becomes a code rather than a sentence, and same-named callees of one `calls` block merge into
    one `<c n= l=>` row (#215).
  - **`<g>` grouped test rows.** A consumer that parses `tests_to_run` must learn one new row shape: contiguous
    runner-less rows whose other attributes are byte-equal are served as a single `<g hops= n= p="a,b,c"
    run_unknown="1"/>` row in XML, as one object with an array `"p"` (or `"test"`) in JSON, and as one
    `[hops=N] (n): a, b, c   (run: not derivable)` line in `--situ` text. Rows that carry a runner stay single
    `<t>`/`<test>` rows, a group of one stays a single row, a `,` inside an XML path is `&#44;`, and every path is kept
    verbatim — the multiset of paths is identical before and after (#214).
  - A `file:name` selector on a C++ header declaration keeps only the definitions tied to that header, so `--callers`,
    `--callees`, `--impact`, `--safe-delete`, `--path`, `--uses`, `--mentions`, `--verify` and `--affected` can answer
    fewer rows. They carry `unproven_defs=` when they dropped any (#173, #190, #195), as do `--edit-check`, `--lego`,
    `--connect`, `--around`, `--slice`, `--expand`/`--outline`, `--owners`, `--note-add` and the MCP twins (#210).
  - A C/C++ declaration without a body yields the focus to the lowest-id C/C++ definition with a body in the same
    scope; every other case keeps the lowest id. Four legend sentences that called the pick "the lowest-id one" are
    reworded (#210).
  - `--callers` on a narrowed selector with declined calls points `next=` at the bare-name `--uses` call, and its legend
    says so (#182).
  - `--lego`, `--verify` and `--nonlocal-state` define `graph_unindexed=`. `--legend=compact` answers define the
    attributes they print, so some compact answers are larger, and each compact schema is now pinned at its own
    measured size rather than at one 400 B pin: map 810 B, communities 820 B, map-diff 800 B, impact 780 B,
    community 730 B, safe-delete 720 B, around 720 B, metrics 720 B, pack-signatures 680 B, pack-top-n 660 B,
    query 630 B, and the remaining schemas between 140 B and 410 B. `--help` states the sizes and, restated from
    measurement, a saving of "at least 45%" rather than "at least 50%"; the measured savings on a small answer are
    `--callers` 65.91%, `--uses` 63.79%, `--impact` 46.17% and `--affected` 64.73%, a per-call drop of 2.8–5.8 KB
    (#169, #185, #189, #203). `--for`'s own compact dialect is present-only and pinned at 690 B (#215), and the
    pack-task schema moves to 880 B where a fixture's runner-less rows now define `run_unknown=` (#214).
  - A budgeted `--for` that takes rung zero names the legend definitions it dropped (#174).
  - Every churn-decay `<recent>` block carries `merge_bombs_skipped=`, `"0"` included, and an all-bomb window prints
    `<recent n="0" of="0" merge_bombs_skipped="N"></recent>` where it printed no block at all (#212).
  - Records inside a literal `#if 0` no longer serve any role: reads, writes, imports (`using ns::x;` and `#include`
    alike), `extends`, types, `#else` branches, variable-to-type bindings and definitions are all excluded, where 0.6.0
    excluded only calls. `--uses` counts can fall, `amb=`, `prov="split"` and `overloads=` can lose rows minted by code
    that cannot compile, and `--expand=deadType` refuses with a suggestion instead of serving a dead body. `--grep` is
    unchanged: text inside `#if 0` is still findable (#172).
  - `--connect`'s `est_tokens=` reads higher on a tree that has an unindexed file (#171).
  - `--help` lists twelve flag rows it had left out, and the `--scip` help row says a missing index refuses (#170, #184).
  - The map header, `--skipped`, `<flags>` and `<doc-drift>` can carry `escaped_root=` (#179).
  - `--scip` naming an empty file, a directory, a FIFO or a device exits 1 (#197).

### Added — `--for` pages its answer one file per row, and says when to widen

On the pre-registered follow-up ladder (a 2,066-file C++ corpus pinned at one commit, the frozen 30 questions, six
deterministic steps per tool, no model in the loop), every ripwire follow-up completed 0 answers through step 4:
`--for`'s `next=` pointed at `--expand` (a body, not a wider list), `--top-k` was inert on `--for`, and
`--format=candidates` is symbol-grain (40 symbols is about 18 files in 11 KB). The one follow-up that completed answers
in that ladder was a file-grain page — one row per file, about 6 KB. Local telemetry had `--for` → `--expand` followed
0 of 259 times.

`--for=TASK --limit=N` (`--offset=M` pages it) is now that page: a `<files>` document of one `<f p= score= n= sym=/>`
row per positive-score file, `p=` spelled root-relative exactly as every other verb spells it, ranked file-first by
`score=` — the IDF-weighted share of the query's subtokens the file's top 8 symbols cover between them (a term counts
once however often it recurs, so one huge file cannot monopolise; ties by the best symbol's lens score, then path).
The root carries the house paging vocabulary (`shown= total= capped= has_more= next_offset= offset= limit=`) and a
`next=` naming the next page. When the answer is THIN — the top-ranked symbol's name, doc or body carries under 50% of
the query's IDF-weighted subtokens (an unmatched subtoken weighs as the rarest, so a `(#12147)` token lowers the share
honestly), or the ranked head spreads over fewer than 3 files — `--for`'s root carries `coverage=` (that share, whole
percent) with its legend clause, and the r=1 row's `next=` names `--for=TASK --limit=40` instead of the body. A
confident answer carries none of the three and is byte-identical to before; the `--json` and MCP twins follow the same
present-only rule. The MCP `for` twin takes the same `limit`/`offset` and serves the same page through the same
renderer. Beside the page every bundle-shaping flag is refused, never ignored (`--limit=0` and non-numeric values were
already refused). `--top-k` stays inert on `--for` and `--help` now says which flag widens.

Measured, on the ladder re-registered with the page as step 2 on the `--for` shapes: ripwire's complete@step row is
unchanged at 14/14/14/14/17/17 — the page completed no question, because the seven misses it ran on hold 3–21 gold
files each — while adding gold files on four of the seven (+2, +1, +3 and +6 files) at 5,539–6,212 B per page (mean
5,841 B), and the thin rule named the page on 4 of those 7 misses. The frozen-30 single-call instrument is unchanged at
14/30 complete and 42/129 gold files named; its median bytes-to-answer is 6,348 B (5,988 B before: 10 of the 12
`--for` questions on that instrument are thin — commit subjects with a `(#NNNN)` token, "how does A reach B" questions
— and carry the clause; the 2 confident ones read the base again, and the 18 non-`--for` questions moved by the 2–4 B
the git stamp moved on every verb). Gate: `test/forwidencheck.sh` — a generated 33-file fixture whose gold file sits at
page rank 13 and is absent from the default head and tail; one row per file, determinism, paging with no overlap,
`coverage=` defined in both dialects, thin versus confident `next=`, the refusals, MCP parity — red on the pre-change
binary. The byte pins that ride a thin `--for` header (forrankordercheck's fixture rows, forrootlegendcheck,
compactlegendcheck's loop, the two `--no-route` goldens) were re-anchored with the measured number; the confident ones
read the base again ([#213](https://github.com/redhat-et/ripwire/pull/213)).

### Added — `--in=DIR` scopes "what changed recently", and the churn window discloses the merge bombs it skipped

Three defects, one lane.

**The churn window hid the commits its merge-bomb rule skipped.** The decayed git walk skips any commit touching more
than 100 indexed files and counted nothing about it, so a `<recent>` block could omit the very commit a question was
about — a held-out gold commit touching 71 source files was invisible — with no trace in the output. Every churn-decay
block now carries `merge_bombs_skipped=`, `"0"` included; the threshold is the named `kChurnMergeBombMaxFiles = 100`,
listed in `docs/LIMITS.md` and `static_assert`-pinned to its legend text, and defined in both the full and the compact
dialect. A window in which every commit is a bomb — a shallow clone of a large tree; llvm-project at depth 1 is one
183,835-file commit — used to print no `<recent>` block at all, which made the new count vanish on exactly the run that
needed it; it now prints `<recent n="0" of="0" merge_bombs_skipped="N"></recent>`. A tree with no git still prints no
block.

**There was no directory scope for "what changed recently in DIR".** `--rank-by=churn-decay` answered with a
whole-repository symbol map plus one global `<recent n="40">` block that a directory with more than 40 recently-touched
files never fits into, and the sub-root workaround loses the global block and spells `p=` sub-root-relative.
`--in=DIR` keeps the global block byte-identical, adds a second `<recent scope="DIR" n= of= merge_bombs_skipped=>`
block built from the same mining pass and spelled on serialize's own root-relative rule, pages it with the house
`--offset=`/`--limit=` (40 rows, then `capped="1"` and a `next=` carrying the page verbatim), and collapses the symbol
map to a `<symbols stubbed="1" would_show=N next="--rank-by=churn-decay"/>` stub.

Measured (RocksDB at `0e2801ac`, read-only corpus, scratch cache, warm, `wc -c` on stdout): the bare
`--rank-by=churn-decay` answer is 39,813 B; `--in=db` is 10,241 B, `--in=util` 10,165 B and `--in=table` 10,711 B.
The saving is the stub — 68 B in place of the 200-row map — and the scoped block itself *costs* 2.2–2.75 KB per
answer; RocksDB reads `merge_bombs_skipped="30"`. On this repository, `--in=src` takes 46,843 B to 9,259 B and reads
`"5"`. The compact legend grows 1,783 B → 1,939 B under `--in=` (+156 B: `scope=`, `total=`, the window terms). On
llvm-project (183,835 tracked files, `/usr/bin/time -l`, scratch cache, two warm samples each) the per-file scope pass
costs nothing measurable: warm bare and warm `--in=llvm/lib/Analysis` both run 2.41–2.44 s real at 2.2 GB max RSS,
while the answer falls from 47,967 B to 5,676 B. Honest caveat: that clone's single commit is a merge bomb, so every
file weight is 0 and the prefix predicate short-circuits — the 183k-file loop is exercised, but the path compare is
exercised at scale only on RocksDB's 1,857 touched files.

Gates: `test/recentscopecheck.sh` (58 PASS, 42 arms red on the pre-lane binary) and `test/churndecaycheck.sh` arm 7
(red on the pre-change binary: no attribute anywhere), both also clean under ASan
([#212](https://github.com/redhat-et/ripwire/pull/212)).

### Added — the task router reaches the recency question, and this round's shapes are named where an agent reads

Three defects, one lane. The framing for the round: for this to work the whole system has to be put together — the
answers need shortening, but the agent also has to know how to use them.

**The recency question routed nowhere.** `what changed recently in db`, `who touched this lately`, `the newest commits
here` — every phrasing abstained with `score="0"`, so `--rank-by=churn-decay`, and the `--in=DIR` scope landing beside
it, could not be reached from a task said in words. The cause was simply that no churn or recency intent existed.
`recent` is on `kWeakSymbolStopWords`, but that list governs symbol resolution only — it is why `--expand='recent'`
can never be minted out of prose — and it has never had any bearing on which INTENT a task reads as. Nothing came off
the stop list, since those words must still never name a definition; they became intent evidence instead, which is
what the list's own comment says they are, and the correction is recorded in the source beside the new route so the
next reader does not re-derive it.

The new `recency-window` route is CONJUNCTIVE in three parts, because two are not enough: a TIME word, a MOTION word,
and a word naming the corpus or a directory of it the task named. A time word alone is usually part of a compound noun
(`the recent-file cache`); a time word and a motion word together is also a sentence about a supplier revising their
terms last quarter. An EXPLANATORY question is never this route however many of the three it holds. Cues are matched
word-bounded — the explanatory ones included, since a phrase delimits its interior and nothing at its two ends, and a
word ending in `how` followed by one beginning `do` is how `show documentation` swallowed a cue. The route runs LAST,
only when the weighted tier named nothing, which is both the argument that it costs the older routes nothing and how
it reads a dirty worktree: `is my diff safe to merge, i changed these files recently` is still `review-diff`'s
question, and `review-diff` wins before this route is reached.

**`--in=DIR` is composed only when both halves hold.** The task must name a directory of the CORPUS in a locating slot
— the same cue discipline the symbol slot uses, matched on `rw::sarif::rootRelativeUri`, the one root-relative
spelling the map's `p=` and `--in=` both use — and the running build must ship the flag, which `cli.h`'s new
`shipsViewFlag` reads from the flag table itself. A router that composes a flag its own parser has no row for hands
back a command that exits non-zero on the first paste, which is the prerequisite violation this file refuses from
every other direction. When the task names a directory this build cannot scope to, the `reason=` says so instead of
handing back a whole-repository answer to a question about one directory with nothing marking the drop. The directory
walk takes the EARLIEST slot in the sentence rather than whichever cue sits earlier in an array.

**The widening page was discoverable only from a thin answer** — one call too late for an agent choosing what to run
FIRST, and the first call is what `--help-task` exists to pick. Every `--for`-shaped recommendation now carries
`next="… --limit=40"` on its `<choice>`, keyed off the INTENT rather than off finding `--for=` anywhere in the command
text (a task that quotes the flag inside another verb's argument had handed `--pack-task` a page width it refuses,
measured: exit 1), and spelled by `forpage.h`'s own `forWidenNext`, so the recommendation's follow-up and the answer's
own follow-up are one spelling under one 120-byte ceiling rather than two spellings at 197–236 B. Present-only: a
recommendation that is not `--for`-shaped carries no attribute at all.

**`--help-task` had no legend in the default dialect.** Every attribute a reader met on its only screen was undefined,
with the compact layer's present-only legend the only place any of them was explained. One line defines all twelve
plus `<run>`, ending in the shared `kNextLegendClause`, and `--help-task` joins `legendcoveragecheck`'s enumeration
and `nextverbcheck`'s population.

**No new shape of this release was named where an agent reads.** Measured on main's skills, `--for`'s
`--limit`/`--offset` page and its `coverage=` gauge appeared in no skill body and no wrap primer within reach of the
verb they belong to: `--limit` is named, `--for` is named, in different files, and naming the two apart does not tell
anyone the page exists — the PAIR is the instruction. Four skills gain one or two sentences each, no frontmatter
touched. `ripwire-fresh-eyes` gains the history question (`--rank-by=churn-decay`, `--in=DIR` and what it does to the
map, `merge_bombs_skipped=` read as the disclosure it is, `scope=`); `ripwire-orient` gains the thin-answer rule
(`coverage=`, and that the step after a thin answer is `--for=TASK --limit=40`, not a body) and how to compose a
selector out of a row whose identity is `sc=` (`p::sc::n`); `map-before-you-read` gains the same in its pagination row
(on `--for` a `--limit` is not a cut but a wider net, and the bundle-shaping flags are refused beside it); and
`ripwire-change-check` gains the grouped `<g hops= n= p= run_unknown="1"/>` row beside `--affected`, with the
invariant it preserves.

Measured (`bench/taskroute_eval.py`, the committed content-hash split; only the binary and the corpus change between
rows):

| stage | binary | rows test / dev / all | accuracy test | dev | all | precision | harmful |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| before the lane | `origin/main` | 114 / 111 / 225 | 0.939 | 0.946 | 0.942 | 1.000 | 0.000 |
| after the first review round | `aaa3baa6` | 128 / 119 / 247 | 0.945 | 0.950 | 0.947 | 1.000 | 0.000 |
| this head | `342d16d9` | 130 / 119 / 249 | **0.946** | **0.950** | **0.948** | 1.000 | 0.000 |

Coverage at this head is 0.917 test, 0.933 dev, 0.925 all, and **every miss is an abstention**: `precision=1.000` and
`harmful=0.000` on all three splits, with `want=… got=abstain` the only confusion row, and negative specificity 1.000.
The control is this head's binary scoring the pre-lane 225 rows — 0.939 / 0.946 / 0.942 at coverage 0.907 / 0.929 /
0.918, the same three numbers as the first row, so no inherited row moved. The lane added 24 rows (225 → 249): ten
positives, four of them naming a directory, and four decoys in the first round; then four NEGATIVES, one per
word-boundary class a review found (`here` in where/there, `source` in outsource, `file` in profile, `code` in codec),
one for a dirty working tree, three positives for vocabulary that abstained (a verb below the motion floor,
`since <a day or a date>`, `what is new in DIR`), and two for the cross-word explanatory cue. Two of the review rows
are labelled `instrumented-cli` rather than `handwritten`, by the rule the corpus's own section states: their trigger
is a small closed phrase list, so a sentence that routes necessarily reuses one of its phrases.

Two claims an earlier revision of this lane made were WITHDRAWN by review, and are corrected in
`test/taskroutefix/PROVENANCE.md` rather than left standing. That the 225 pre-existing rows are byte-identical on
(status, intent) across the new route is true and nearly vacuous — measured, 0 of those 225 prompts reach the recency
route at all, so the identity was never in question, and a number that cannot move is not a measurement; the evidence
that the route steals nothing is the corpus's own negatives and the gate's arms. And the contamination screen is not
down to one flagged line from two: measured with one binary at three points it reports the same 2 flagged lines every
time, neither of them a row this lane wrote.

Gates. `test/taskroutecheck.sh` gains 11 arms in the first round and 20 more in review; against the pre-change binary
4 FAIL — both recency phrasings answer `status="abstain" … score="0"`, and the locate-task recommendation carries no
widening `next=` for the follow-up arm to recover. The emitted commands are EXECUTED, not merely matched: the bare
recency command must return a `<recent>` block, and the widening `next=`, unquoted with `shlex`, must return the
`<files>` page. Every arm reads the COMMENT-STRIPPED body, so a legend that names an attribute can never satisfy an
assertion about a row carrying one. `test/agentsurfacecheck.sh` is new, and red against main's skills with 3 FAIL —
no skill body or wrap primer named `--limit=`, `--offset=` or `coverage=` within five lines of `--for`, so the
file-grain page and its thin-answer gauge were unreachable from a skill. Its arm (A) is a RATCHET over all 163 long
flags `--help` advertises: each is named in a skill body or the `ripwire wrap` primer, or recorded in
`test/agentsurfacefix/unnamed_flags_baseline.txt` with the reason it is still a gap (5 lines today: `--eval-skills`,
`--eval-stray`, `--pin-census`, `--max-file-size`, `--sarif`), a floor that may only be edited DOWNWARD and that also
fails when a recorded line stops being a gap, so a closure cannot be filed and forgotten. The match is word-bounded,
because 23 advertised flags are a strict prefix of another (`--in` inside `--index-out`, `--not` inside `--notes`,
`--for` inside `--format`) and a substring test would report every one of them as named by its longer sibling; the arm
prints that count, so the population the bounded match protects is visible. Arm (B) pairs each of this round's new
shapes with its verb within five lines on one surface, PROBED by RUNNING the verb — `--help` advertising a flag is not
evidence that the flag emits anything — with what the binary emits (`<g`) split from what a skill must spell (`<g `)
so `<graph-query` cannot satisfy a row about grouped test rows, and it asserts its own population, 8 of 8 rows probed.
A shape that has not landed is declared PENDING with the lane that ships it, and the arm is SELF-HEALING on arrival: a
pending shape that appears in the binary with its pairing already satisfied PASSES, so #212, #214 and #215 turn those
rows green without touching a skill. What stays red is the dishonest direction — a surface promising a shape this
build refuses, with no lane declared. `docs/COMMANDS.md` is deliberately NOT an accepted surface: it names every flag
by construction, so accepting it would make this gate one that cannot fail; it is the reference, not the file an agent
loads mid-task. Gate count 613 → 614, `--quality-delta` at `gating="0"` with no ack, and the five gating rows the
review round would otherwise have raised were fixed by REUSE rather than acked — two scorers became one with the match
mode as a parameter, four hand-written membership tests became `isOneOf`, and three one-line call-through wrappers
were folded into their single call sites
([#218](https://github.com/redhat-et/ripwire/pull/218)).

### Added — Elixir module and arity resolution (parser version 95)

Elixir calls now resolve by module, name and arity, with lexical aliases, filtered imports, default arguments, pipes,
captures and delegates. Nested modules and each target of a multi-target `defimpl` have separate identities. Types,
callbacks and attributes are navigable, and protocol/behaviour relationships appear in the existing relationship views.
CLI and MCP use-site queries share the same resolution rules; unknown modules and excluded imports no longer fall back
to unrelated functions.

The implementation uses the existing vendored parser and cache records, with no Elixir runtime dependency. Macro
expansion and runtime dispatch remain static-analysis limits; the supported syntax and boundaries are documented in
[Elixir extraction](docs/ARCHITECTURE.md#elixir-extraction).

`kParserVer` 94 → 95 with `quality.h`'s `kIngestParserVerMirror` in the same commit — the branch carried 87, main
spent 87..92 while it was open and the 0.6.1 round takes 93 and 94, so it was re-bumped to the next free number over
the merged tip, per the rule in `src/ingest_cache.h`; `kCacheVersion` stays 21.

Four review findings were closed as maintainer commits on the branch, each with a row in
`test/elixirnamearitycheck.sh`. A call that only a `use`-injected import could answer minted no edge and was dropped
silently; it now counts in the map header's `unresolved=` and every answer's `graph_unresolved=` (an undefined spelling
stays undefined, modelling `__using__` stays open). A variable bound on the right of `=` inside a pattern —
`def join(%Socket{} = socket, _)`, a `case` clause, a `with` generator — is a binding, not a zero-arity call of a
same-named function. The quality key folds the arity out of an Elixir name, so `run(x)` → `run(x, y)` is an
`--edit-check` contract change on `run` (params 1 → 2) with every caller of the old arity listed and flagged, and a
`--quality-delta` params row, rather than a dead symbol beside a new one; a default (`run(x, y \\ 1)`) still reports the
change but flags nobody (`kQSnapCacheScheme` 10 → 11). `--for` by an exact function name (`generate_app`, `text`)
routes name-exact and ranks the `name/N` symbol first.

Five resolution rules the branch got wrong, found by reproducing against Elixir 1.20.3 / OTP 29 before the merge, each
with a row and a control in `test/elixirnamearitycheck.sh` over `test/elixirresolvefix`. `import M, except: [...]` after
`import M, only: [...]` subtracts from the only-list instead of replacing it (a function the only-list never named
minted an edge, silently; the refusal is now counted). A dotted nested `defmodule Inner.Deep` aliases `Inner` →
`Outer.Inner` from its declaration on, so the later `Inner.Deep.f()` names the nested module rather than a top-level one
— or, with no top-level one, rather than nothing. `alias __MODULE__, as: Current` inside a multi-target `defimpl`
reaches each implementation's own function, not the first implementation's. `&_seed/0` names the underscore-named
function (the underscore rule is for unused variables; a bare `_seed` read still is one). And `f()` on a bodyless
`def f(x \\ default())` head reaches the head beside the clauses, so `--path=caller,default` and `--impact=default` see
the caller; `f(1)` still reaches the clauses alone. Every one was a wrong answer or an uncounted drop. They ride parser
version 95 — the number this entry introduces, which no released binary has written — with `kCacheVersion` 21 and
`kQSnapCacheScheme` 11 unchanged. Still open, and documented in
[Elixir extraction](docs/ARCHITECTURE.md#elixir-extraction): calls inside `unquote(...)` / `bind_quoted:` under `quote`.

Contributed by **@henry-hz**, whose ten commits carry the authorship
([#81](https://github.com/redhat-et/ripwire/issues/81), landed with the review round as
[#207](https://github.com/redhat-et/ripwire/pull/207)).

### Added — a Ruby constant argument and a rescue class are dependencies; `lazy_edges=` counts distinct pairs (parser version 93)

Round three of the Ruby constant work, on the same corpus-own index as round one (superclass, mixins, autoload —
parser version 82) and round two (constant receivers — 83). Ruby's rule is that EVALUATING a constant is what makes
the autoloader load its file, and a receiver is only one of the places a constant is evaluated. Round two pinned the
other two as its disclosed floor; this round lifts them.

**A constant argument is a directive.** A constant chain that is a direct positional child of an `argument_list`,
or the value of a keyword pair written directly in that list, is a symbolic Include: `raise Errors::Boom`,
`validates_with Validator`, `delegate :name, to: Helper`, `record.is_a?(User)`, `super(Validator)`, `yield User`.
The `argument_list` is the grammar's one node for the arguments of a call (with or without parens), a `super` and a
`yield`, so one read covers all three. The lists of `include`/`extend`/`prepend`/`autoload` stay round one's, one
record per statement. An argument is lazy inside a closure and load-time at class-body or file level, exactly like
a receiver — `validates_with Validator` in a class body is a load-time dependency on validator.rb, which is what a
Rails model file's structure actually is.

**A rescue class is a directive, and it is lazy always.** Every constant chain in a `rescue` clause's exception list
(`rescue Errors::Bust, Errors::Boom => e`) is a symbolic Include. Ruby evaluates that list only while matching an
exception, never when the clause is loaded — `class X; begin; 1; rescue Nope; end; end` is silent, and the same
`begin` with a `raise` inside names `Nope` in a NameError (ruby 4.0.6) — so a class-body rescue is a use, not a
load-time dependency, and it stays out of the ccd/godfiles structure like every other lazy pair.

**One dedupe key.** Arguments and rescue classes share round two's (file, innermost open, written name) record with
receivers: a `raise Errors::Boom`, a `rescue Errors::Boom` and an `Errors::Boom.new` in one nesting are one
directive, and the parser-86 AND rule still decides the lazy bit — a rescue above a class-body receiver of the same
name is one load-time directive.

**`lazy_edges=` over-counted, and the fixture for this round is the shape that showed it.** `<health lazy_edges=>`
and a row's `lazy_edges=` are documented as DISTINCT (file, target) pairs, but the count walked an un-deduped
adjacency that is in directive order, not sorted, and counted a pair once per run of equal ids: `Errors::Boom`,
`User`, `Errors::Bust` in one method resolve to errors.rb, user.rb, errors.rb and read as 3 for 2 pairs. It now
sorts the dropped ids and counts unique ones. At this round's parser version the old count read 1 546 / 1 147 / 6 398 / 2 549
on the four corpora below against the distinct 1 381 / 1 015 / 6 342 / 2 519; every other byte of `--deps` is
identical between the two counts (checked on activerecord). Round two's own fixture never interleaved two spellings
of one file with another target, so its pins were right by shape rather than by the count.

**A value-position constant is a dependency, not import evidence — and the call graph is byte-identical to main.**
The first cut of this round let the new records feed buildGraph's include narrow, which reads a file's resolved
includes as evidence for which definition a bare call means. That is wrong for a value position: `notify(Dev::Config)`
beside `record.update!` says nothing about what `record` is, and the narrow bound `update!` to `Config#update!` on that
reading — on discourse 1,017 call sites newly bound or narrowed, 19 of 20 sampled wrong (the PR #139 review). `Include`
gains `isValueUse` (cache format 21), set for argument and rescue records and cleared by any receiver occurrence of the
same name, and `buildPreciseIncludeAdjWithContext( …, forCallNarrow=true )` — called only for buildGraph's
`fileIncludes` — leaves those records out; `--deps`, `--impact`'s importer tier and the lazy-pair count read them as
before. Measured against main's binary, built from the same merge base: the default map is
**byte-identical** on the four corpora below and on this repository, and `--report`'s totals match to the unit
(activesupport 3 650 edges / 410 modules, activerecord 8 638 / 912, the Rails apps 23 784 / 2 067 and 12 108 / 1 384).
The pre-fix branch had moved every one of them (23 447 / 2 030 and 55 more isolated symbols on the first app). Gate:
the review's own repro, `test/rubyargnarrowfix` — two `update!` definitions in different directories, a caller in a
third that passes `Dev::Config` and then calls `record.update!` — declines the call as main does (0 callers,
`declined_calls="1"`) while `dev/config.rb` keeps notifier.rb as a lazy importer; red on the pre-fix binary (1 false
caller).

**Disclosed floor, pinned to yield nothing** (`test/rubyargfix/lib/app/floor.rb`): a `when` pattern (evaluated
eagerly by Ruby — the next round's first candidate), an array or hash-literal element, a splat, an assignment's
right-hand side, string interpolation, a binary operand. Each is an evaluation Ruby performs that this round does
not read.

Measured (`--deps --limit=100000 --no-cache`, parser version 88 → 93, measured on the branch's pre-merge binaries; the
gems are Rails 7.2.3.2, the apps the same two Rails apps as rounds one and two, aggregates only):

| corpus | ccd | nccd | shape | load-time importees | lazy_edges | bytes |
| --- | --- | --- | --- | --- | --- | --- |
| activesupport `lib/` (282) | 15 299 → 15 775 | 7.59 → 7.83 | tangled | 201 → 202 | 935 → 1 381 | 75 988 → 85 530 |
| activerecord `lib/` (395) | 4 325 → 4 657 | 1.44 → 1.55 | vertical | 310 → 310 | 1 023 → 1 015 | 114 763 → 129 011 |
| a Rails app, 4683 files / 3532 `.rb` | 13 172 → 17 798 | 0.32 → 0.43 | horizontal | 414 → 1 015 | 5 630 → 6 342 | 750 915 → 855 559 |
| a second Rails app, 2002 / 1895 `.rb` | 6 543 → 7 577 | 0.34 → 0.39 | horizontal | 200 → 557 | 1 878 → 2 519 | 370 991 → 471 865 |

The importee column is the finding: on the two applications the files with a load-time importer went 414 → 1 015
and 200 → 557, because a class-body DSL argument (`validates_with Validator`, `delegate … to: Helper`, `rescue_from
Errors::Boom`) is where a Rails file names what it loads. No shape moved; ccd grew and stayed horizontal,
which is the structure/use cut doing its job. The `lazy_edges` column carries BOTH mechanisms above — new lazy
pairs in, the over-count out — and activerecord is the corpus where the second outweighs the first. The default map
of this repository (no Ruby) is byte-identical before and after.

Gate `test/rubyargcheck.sh` + fixture `test/rubyargfix/` (19 files, written RED against the parser-88 binary: 22
arms red, every control green); `test/rubyrecvcheck.sh`'s floor arm inverts and its report.rb pins move by the one
`raise`/`rescue` directive; `test/rubyrequirecheck.sh`'s main.rb counts its `rescue LoadError` as a shown,
out-of-tree row (12 → 13). `kParserVer` 92 → 93 with the mirror (the branch spent 89 while main spent 89..92 on the
extent detector, Kotlin and the yaml patch); cache format 20 → 21 (`Include::isValueUse`); re-pins with reasons
in-file: `test/qschemetrip.hash`, `test/printf_parity.manifest` (the `--impact` help and legend name the two new
closure kinds; the `--deps` legend's lazy definition gains the rescue class). `docs/COMMANDS.md` regenerated
(2026-09-11).

Contributed by **@andriytyurnikov**, round three of their Ruby constant work
([#139](https://github.com/redhat-et/ripwire/pull/139)).

### Changed — short symbol ids on maps, a compact legend on `--for`, and compact by default on the agent surfaces

**`sc=` on symbol rows.** Every scoped symbol row printed its canonical id in full —
`id="src/mcpverbs.h::rw::applyCompactToBatchSubs"` under an `<f p="src/mcpverbs.h">` wrapper that had just printed the
path, or beside the row's own `p=` on a lens `<d>` row. The row now carries `sc=`, the enclosing scope, the one segment
nothing else on the page holds; the legend states the composition `p::sc::n`, and **every selector still accepts the
composed spelling** — the resolver is untouched, and a new `test/scroundtripcheck.sh` (17 arms) proves the composed
multiset equals the old `id=` multiset. `route=` becomes a code (`name-exact(X)`, `subtoken+body`, `:broad`,
`:declined(word;carriers,defs)`) with one shared spelling for the CLI lens, the MCP `for` twin and the compact dialect,
so a code cannot acquire two readings; the fuller reading lives once in `--help`'s `--no-route` entry. Same-named
callees of one `calls` block merge into `<c n="pick" l="70,69"/>`, and `shown=` still counts callees.

Measured (`wc -c` on stdout; a build of the merge base run on the same merged tree, so no corpus drift rides the
numbers): this repository's flagless map falls from 26,449 B to 22,407 B — **−4,042 B, −15.3%, the same rows** —
`test/cppqualfix` −5.2%, `test/nestedqualfix` −5.3%, and `test/accessshapefix` **+9 B**, where four scoped rows do not
pay for the longer reading. On `--for` the bundle is byte-shaped, so the row saving becomes rows rather than bytes:
`pagerank power iteration` goes from 9,470 B at `shown="20"` to 9,880 B at `shown="25"`, and `rank graph teleport` from
10,134 B at 19 rows to 10,022 B at 22 rows.

**`--for`'s compact legend is present-only.** Every other XML verb under `--legend=compact` answers with a present-only
legend pinned per schema; `--for`'s native compact dialect was the default sentences behind a schema id (1,177–1,216 B
on the gate's fixture) and exempt from the pin by name. It is now one present-only comment — a reading per attribute
the bundle actually prints — measured by the gate's own splitter at 678 B on the fixture probe (915 B before) and
pinned at 690 B as the `ripwire.for/v1` row. Per call on this tree, default legend → compact: `pagerank power
iteration` −537 B, `rank graph teleport` −309 B, `escapeXml` −1,222 B.

**The agent surfaces ask for the compact legend, and say how to get the full one back.** Every command ripwire writes
for an agent carries `--legend=compact` where the verb accepts it: 158 `ripwire <dir>` verb commands in 17 skill files
(bodies only — no description, stop rule or boundary moved), 9 commands in the `ripwire wrap` paste block, 26
`--help-task` routes and the 2 tool-call routes. One sentence per surface, and not seventeen, says to add
`--legend=full` when a definition's reasoning is needed: the wrap blurb, one new section in the router skill's shared
conventions, a parenthetical in the three route hooks' injected context, and the MCP `legend` argument's own schema
description. `--for` keeps the default legend; the text, JSON and writer verbs are untouched; the bare CLI is
unchanged. Separately, the `--observe` arm of both prompt routers now counts a call only when the command word really
is the binary, so `cd …/ripwire && git log --oneline` no longer burns an adoption-window slot. Gate:
`wrapverbscheck` arm 8, six rows — the wrap blurb, the router skill, the three route hooks and a live `tools/list` over
`--mcp` — verified red against the merge base's tree and binary, 0 hits on every one of the six
([#215](https://github.com/redhat-et/ripwire/pull/215)).

### Changed — tests-to-run rows without a runner are grouped, and the disclosure is stated once per group

A tests-to-run row with no derivable runner said so on the row — `run_unknown="1"` (XML, 16 B), `"run_unknown":true`
(JSON), `   (run: not derivable)` (`--situ` text, 23 B). On a corpus where almost no harness has a derivable runner
that is one fact repeated per row: on RocksDB, `--affected=db/write_batch.cc` lists 127 tests, 126 of them runner-less,
and spent 2,016 B of XML and 2,898 B of text on the repetition. The disclosure is right — an absence is not a
disclosure — its per-row placement was the cost.

Rows already come in evidence order, so a contiguous run of runner-less rows whose other attributes are byte-equal is
served as ONE `<g>` row, emitted where its first member stood. Rows that carry a runner stay single rows, a group of
one stays a single row, a `,` inside an XML path is escaped `&#44;`, and **every path is kept verbatim**: the multiset
of paths before and after is identical, and the emitted order is preserved by construction, because a group covers a
contiguous run only. All twelve emitter sites in nine files render through one seam, and the legend clause is spliced
rows-gated, so a `tests="0"` answer pays nothing for it.

Measured (RocksDB, read-only corpus, scratch cache, same commit, `wc -c` on stdout), on the 127-row
`db/write_batch.cc` list: `--affected` 10,668 → 6,878 B (−35.5%), `--test-gate` 13,242 → 9,633 B (−27.3%),
`--test-gate --json` 11,055 → 7,163 B (−35.2%), `--situ` 11,769 → 7,357 B (−37.5%),
`--affected --legend=compact` 9,312 → 5,313 B (−42.9%) and `--test-gate --legend=compact` 11,223 → 7,596 B (−32.3%).
Eight `<g>` rows replace 124 single rows; three rows stay single. The bytes still spent on the disclosure after
grouping are 160 B of 2,016 B in XML and 230 B of 2,898 B in text. A three-row list pays rather than saves
(`--affected=cache/tiered_secondary_cache.cc` 2,352 → 2,690 B: that verb had never defined `run_unknown=` at all), and
on this repository, where every harness has a `.sh` runner, nothing groups and the deltas are the legend alone
(`--affected` +371 B, `--test-gate` +180 B, `--situ` +79 B). `--pack-task="change WriteBatch::Put"` serves
`<tests shown="54" total="109">` where it served `shown="28"`.

Gate: `test/testrowruncheck.sh` arm 12 (the multiset-of-paths and order invariants in all four dialects on a fixture
with three hop groups and a runner-bearing row inside one) red on the pre-change binary, plus arm 13 sweeping
`--token-budget` 1000..1700 to prove a byte cap can no longer drop two paths that each fit alone. Two new
`prcontextcheck` arms hold the third finding: the run clause is now priced and written from the RENDERED body, so a
bundle whose selected range reaches no test cannot buy the clause
([#214](https://github.com/redhat-et/ripwire/pull/214)).

### Changed — one absolute root per change report, `--situ`'s disclosures become gauges, and a changed file's lexical siblings

Three items from the output-routing loop's list, one commit each, stacked on the grouped test rows above.

**A runner command pasted the whole checkout prefix on every row that had one.** A change report states its absolute
root once, in the envelope, and every path below it is relative to that root — which is what makes the document
independent of where the tree is checked out. One emitter never joined: `testmap.h`'s `spell()`, which builds the
`run=` command, pasted the disk path verbatim. On an absolute root `--test-gate` printed the checkout prefix three
times — the `root=` anchor, `next=`, and every `<t>` row's `run=` — and `--situ` once per runnable test line, a
per-ROW cost against a per-DOCUMENT fact. The sweep could not see it: `test/fixture` holds no runner script at all, so
every test row there reads `run_unknown="1"`, and the one emitter that pastes a PATH INSIDE A COMMAND was never
exercised. `TestRunnerIndex` now takes the run's crawl root and spells the command through the same
`rw::sarif::rootRelativeUri` every `p=` beside it uses, with the hand-rolled leading-`./` strip becoming that one
call; the root is passed at all fourteen construction sites, so the twelve emitters sharing the index cannot disagree.
**The relativity is gated to single-root runs.** A multi-root run, whose disk path is under no single root, keeps the
absolute command, because an unrelativizable command must stay pasteable rather than become relative to a root that
does not contain it — and the spelling and the sentence that describes it now answer to ONE predicate,
`runsAreRootRelative`, read by the index and by all eight legend sites, so the clause can no longer tell a multi-root
reader that a command is relative to a root the document never names. `kRunHintLegendClause` gains the sentence
(rows-gated, like the rest of that clause), `--situ`'s `[2]` header says a `(run: …)` is relative to `root:`, and
`--help` and the regenerated `docs/COMMANDS.md` say what the code does — including the multi-root exception — where
they had said `run=` is spelled with the same root you scanned. Two more surfaces that hand a caller something to
PASTE gained the anchor they lacked: `--flags --flip` emitted root-relative `p=` and declared no root, and the MCP
edit receipt had relative `file`, `run` and `next:` and no root; both carry `root=` now, single-root only, with the
one sentence that defines it. `rootRelativeUri` itself returned on a leading `./` before it tried the root prefix —
right for the root `.`, wrong for every other relative spelling: `ripwire ./corp` stores `./corp/test/x.sh`, the early
return yielded `corp/test/x.sh`, and pasting that from the declared root is rc 127. Both sides drop the optional `./`
first and compare what is left; the root `.` case stays byte-identical.

**`--situ`'s disclosures are gauges, and every gauge keeps its reading.** `--situ` is the only report with no XML root
to hang attributes on, so every disclosure it owed was a sentence, and the sentences grew: a floor clause, a decl/def
partner header, a tests-to-run header and a script-gate caveat, about 1.2 KB of prose per call carrying facts a reader
can act on only once they are named. Each is now an attribute line, spelled as the XML and JSON dialects already spell
the same fact, so the three share one vocabulary: `counts_floor=1` beside `graph_ambiguous=`, `graph_unresolved=` and
`graph_unindexed=`; `not_dependents=1`; `prcontext_cap=20`; `order=evidence`, the attribute `--affected`'s root
already carries; and `script_gates_unmodelled=`, the counter `--affected` publishes. Nothing is dropped — every floor,
cap and caveat survives, and the two readings with no attribute form, how to read a zero and what
`[changed]`/`[partner]`/`hops` mean on a row, stay as the shortest sentence that defines them. **An attribute without
a reading is a token, not a disclosure**, so each gauge keeps a short gloss: the floor's CAUSE (call edges are
name-based), what an unindexed file IS, which header the resolver gauges come from, and whose cap `prcontext_cap=` is.
`--situ` refuses `--legend=compact` and is the one dialect with no legend to look a name up in, which is why the gloss
is not optional here.

**The files a change drags with it were the ones no walk could reach.** The files that move WITH a changed file are
its neighbours by name, and the caller walk reaches none of them: a header does not call the source that implements
it, an `.inl` is not indexed by any grammar in any build, and a harness the graph cannot link is reached by nothing —
two answers on the frozen 30-question set were incomplete for exactly that reason. Section `[1]` now lists them under
the decl/def partners and the floor clause: same directory, and the same filename stem or the stem-partner convention
`testmap.h` already owns (`<stem>_test`, `test_<stem>`, `<Stem>Test`, `_unittest`, `_spec`). Same directory is
load-bearing — a same-stem file in another directory is a namesake, and listing namesakes would make the block noise
on exactly the large trees it is for. The rule is **stricter than the design that simulated it**, an exact stem plus
the test-partner affixes rather than a shared stem TOKEN, so it lists fewer files and costs less; whether the stricter
rule still completes those two questions is for the re-measure, and no completeness claim is made here. The candidate
population is the CRAWL's, not the index's, so the `.inl`/`.ipp`/`.tcc` partner a C++ change most often has to edit is
named; the crawl's unsupported-extension row list is itself capped, which is the one way this list can be short of the
truth, and that is disclosed as `unindexed_rows_floor=1`. The floor is a property of the CANDIDATE LIST, so it is
recorded whenever that list was short and the block speaks at zero as well — a crawl cut that removed the only
candidate used to print nothing at all, the silent zero `docs/METHODOLOGY.md` §9 forbids. The block is capped at 8
with `shown=`/`total=`/`capped=1` and a pasteable `next:`, raisable with `--limit`, and with no offset: `--situ=F
--offset=20` had printed `shown=0 total=9 capped=1` with a `next:` offering relief that cannot restore rows an OFFSET
removed, and `--offset=7` had dropped six rows silently. It is additive to the decl/def partners above it —
suppressing the overlap was tried and reverted, because it removed `widget.h` from "the siblings of widget.cc" to save
about 20 B. The MCP `situational_awareness` twin carries the same list as `siblings`, with a `siblings_total` that is
now the population and an explicit `siblings_capped`, emitted and never omitted, rather than the length of the array
beside it, which was a tautology.

Measured (`wc -c`, same warm cache, same commit, absolute root; the tip of the lane this one is stacked on against
this head over the SAME tree, so each pair carries all three items together):

| corpus | verb | before | after |
| --- | --- | ---: | ---: |
| this repository (root 131 chars) | `--situ=src/graph.h` | 4,448 B | 2,955 B |
| this repository | `--situ=src/situ.h` | 2,332 B | 2,040 B |
| this repository | `--situ=src/testmap.h` | 2,325 B | 2,033 B |
| this repository | `--test-gate=src/testmap.h` | 5,455 B | 5,247 B |
| RocksDB @ `0e2801ac` (root 66 chars) | `--situ=db/write_batch.cc` | 7,489 B | 7,376 B |
| RocksDB | `--test-gate=db/write_batch.cc` | 9,946 B | 9,868 B |
| RocksDB | `--affected=db/write_batch.cc` | 7,124 B | 7,113 B |

Per item. The root spelling saves one echo per row that has one, less the 56 B the conditional root sentence adds, so
it grows with checkout depth and with how many rows carry a runner: two echoes of a 132-character root on this
repository's `--test-gate`, one echo of a 66-character root on RocksDB's. The four compressed `--situ` lines, measured
by `situshapecheck`'s own `${#line}` on this repository at `--situ=src/graph.h` (the partner header on the gate's
fixture, since `graph.h` has no decl/def partner here), go 601 → 344, 228 → 209, 233 → 220 and 167 → 132: **1,229 B →
905 B**. Said plainly, that is about 20% less than the byte attribution predicted, because the prediction assumed the
gauge names could go unglossed and they carry a gloss instead — and it supersedes this lane's own first figures, which
were measured before the readings were restored and on a different corpus than the gate's. The sibling block costs
what it lists: **276 B** on RocksDB at `--situ=db/write_batch.cc`, a 244 B header and one 30 B row naming
`db/write_batch_test.cc`, which no other section of that report reaches.

Gates. `test/situshapecheck.sh` is new and red on the base binary with 17 FAIL rows — the floor line 601 B over its
ratchet, the partner header 228 B, the `[2]` header 233 B, the four missing attributes, the whole sibling block, the
offset arm's premise, both silent-zero arms and the MCP twin arm. Its sibling fixture is a
`.h`/`.cc`/`_test.cc`/`.inl` quadruple, a same-stem DECOY in another directory and a same-directory different-stem
file (both of which must be absent from the block), a nine-sibling stem for the cap and for `--limit`'s relief, a
no-git copy of the same tree proving the block is static — which is also why it cannot leak — and the MCP twin
agreeing row for row; the silent-zero arm runs on a 700-`.inl` fixture that really does cut the crawl's 500-row
unsupported list, and asserts that premise before it asserts the floor. `test/rootrelemitcheck.sh` ARM 9 is red on the
unchanged binary with 8 FAIL rows and builds its own fixture with a real runner script at two checkout depths,
EXECUTING the printed `run=` from the declared root, because a relative command that cannot be pasted would be worse
than an absolute one; ARM 9b is a matrix over `.`, `corp`, `./corp`, `corp/`, an absolute path and a symlink, all of
which must print the SAME command, ARM 9c pins the spelling and the sentence against each other, and ARM 9d covers
`--flags --flip` at two checkout depths. `receiptpostcheck` (18) covers the MCP receipt, which (13) already holds key
for key against the CLI's, and `runhintcheck` 2c/2d the `--affected` twin. Two gate self-checks were wrong the same
way the code was and now red on that outcome: an empty `run=` made `eval ""` succeed, so `runhintcheck`'s execution
arm passed on the one outcome it exists to forbid, and `rootrelemitcheck` ARM 9's empty-`next=` case fell out of an
if/elif chain printing neither PASS nor FAIL. The suite also caught a dangling `string_view`: `runHintClauseIfRows`
BUILDS its clause now, because the root sentence is conditional, and `PackTaskHeaderParts` holds views, so binding
`runClause` straight to the returned temporary read freed memory — it showed as `packtaskcheck` reporting a bundle
that was both malformed and non-deterministic (two runs, two hashes) and `xmlwellformed` red on `--pack-task --json`.
Pins moved: `runhintcheck`'s nine expected values lose their root prefix, which is the contract change, stated;
`testgatelegendbudgetcheck` 3,000 → 3,070 B for the conditional root sentence (measured 2,957 → 3,013 B on its own
fixture); `situshapecheck`'s own byte ratchets 200 → 360 and 140 → 220, because a ratchet that forbids a disclosure is
aimed at the wrong thing; `printf_parity.manifest` for `pack_task` and `help_all`, the latter regenerated from the
merged binary's own hash because neither side of the merge was the answer; the gate count 612 → 614; and
`docs/LIMITS.md` and `docs/TUNING.md` regenerated for the new row cap, which takes the tree's cap inventory from 210
to 211. `.ripwire_quality_acks` gains nine rows for `TestRunnerIndex`'s new root parameter and the eight sites that
pass it, and three more by symbol (`prLegendText`, `writeFlipHeader`, `runsAreRootRelative`); a duplication finding —
`situDirOf` was a 44-token copy of `siblift.h`'s `dirOf`, and `situStemOf` a fourth spelling of
`stripExt( baseNameOf( p ) )` — and a six-parameter new symbol were fixed rather than acked, and the default
`--quality-delta` reads `gating="0"` with no acks at all. ASan and LSan are clean on both fixtures and on `--situ`,
`--flags --flip` and the MCP twin, as are determinism and `xmllint --noout` on every changed verb
([#219](https://github.com/redhat-et/ripwire/pull/219)).

### Changed — the declined-call index no longer grows with calls × candidates

The call-graph build keeps, for every call the resolver declines to bind, the list of candidates it declined between,
so `--callers` and its neighbours can say how many calls were declined for a symbol. Those lists were stored once per
call, so the structure grew with calls × candidates: 27.9 M entries, 114 MB, on llvm-project, where most declined calls
repeat a handful of identical lists. Each distinct list is now stored once — keyed by its exact candidate sequence, an
FNV-1a hash picking the bucket and a hit confirmed by length and `memcmp` — as a CSR of distinct lists plus a call
count per list. On llvm-project that is 9,879 distinct lists and 62,359 entries: **368 KB instead of 114 MB**, with
peak footprint down about 145 MiB (median of 3 cold runs; the machine was loaded, so treat the timing and RSS figures
as indicative). Every count stays the same and the output is byte-identical to the merge base: 14 of 14 commands on
this repository, 14 of 14 on llvm-project, and `mcpclidiffcheck` 21 of 21. A uint32 offset overflow takes
`DEGRADED_PATH_ALERT`, and a new `verifyOffsetCsr` checks the list CSR beside `verifyCsr`. Gate:
`test/declinedlistcheck.sh`, 30 rows, of which a mutation that shares lists by name instead of by content fails 12
([#208](https://github.com/redhat-et/ripwire/pull/208)).

### Changed — the README and the docs

- **The call for help.** The pitch now comes before the release line and the call for help
  ([#167](https://github.com/redhat-et/ripwire/pull/167)). The call for help sits below the quality panel, where the
  reader has already seen the tool work ([#183](https://github.com/redhat-et/ripwire/pull/183)). It says what to run
  ([#175](https://github.com/redhat-et/ripwire/pull/175)) and offers a range of ways in: starter kits in
  `prompts/help-wanted/`, three open-ended prompts (a full audit, adding a language, and logging every gap while using
  ripwire on a real task), and open directions for research of your own
  ([#181](https://github.com/redhat-et/ripwire/pull/181)).
- **Who the output is for.** Under the four commands worth learning first, the README now says every command prints
  compact XML sized for an AI agent to read, and that human-readable output is on the roadmap
  ([#196](https://github.com/redhat-et/ripwire/pull/196)).
- **A solved kit says so.** `prompts/help-wanted/` lists `next-uses-bare-name` under Solved, crediting @antoleod's
  #182, and the README no longer counts the kits by hand. The reference guide's `--scip` sentence now names every
  path that refuses, not only a missing one ([#202](https://github.com/redhat-et/ripwire/pull/202)).
- **Just want to use it?** The top of the README now says what most people do: install it, then tell your agent to
  use it. The reference guide is marked as optional detail
  ([#204](https://github.com/redhat-et/ripwire/pull/204)).
- **The showcase deck is 33 slides.** The "What `--quality-delta` catches" slide is pulled until better examples replace
  it, and the rebuilt deck states the current gate count ([#205](https://github.com/redhat-et/ripwire/pull/205)).
- **What's new** had not changed since 2026-08-30 and did not mention 0.6.0. It now says what the release changed and
  points at this file, which is the record ([#177](https://github.com/redhat-et/ripwire/pull/177)).
- **The project's voice is written down.** `CONTRIBUTING.md` §7 says commit subjects state what was wrong and the number
  is the punchline. Where style and the honesty rules disagree, honesty wins
  ([#176](https://github.com/redhat-et/ripwire/pull/176)).
- **Lua `require`.** `docs/ARCHITECTURE.md` said a `require` is a plain call and a `.lua` file is never a dependency
  node. Since parser version 81, a string-literal `require` that resolves to exactly one file adds an edge, and the
  paragraph now states that contract ([#184](https://github.com/redhat-et/ripwire/pull/184)).

### Changed — the README gains a reference guide

A numbered, plain-language reference guide goes at the bottom of the README, with a pointer to it near the top. It
covers install, first use, command families, output format, the accuracy and disclosure rules, determinism, agent
integration, languages and limits. Every existing README line stays. Written by **@heliocipher**
([#168](https://github.com/redhat-et/ripwire/pull/168)), landed in [#192](https://github.com/redhat-et/ripwire/pull/192).

### Fixed — the reference guide said things the binary does not

@heliocipher's reference guide was verified claim by claim against a 0.6.0 build, and its flags held up: of the 82
`--` tokens it named, the 72 that are ripwire flags all exist and are spelled as it spells them (the other ten
belong to `cmake`, `xmllint`, `graphify`, `skills/install.sh`, or are anchor fragments). What it got wrong it
mostly inherited from this repository.
**"Dynamic dispatch contributes no edge"** was the opposite of the truth — a virtual call emits one edge per
candidate in the receiver's inheritance cone, each `prov="split"` and counted in `amb=`; a four-class fixture
returns three edges, not zero, with CHA-lite correctly dropping the same-name method of the unrelated class. The
honesty section was understating the tool, which costs a reader's trust the way overstating it does.
**`MSVC 19.36+`** was offered as a supported compiler beside an operating-system row naming only macOS and Linux;
it is not a target, and the row now points Windows users at WSL2. **"18 task-shaped skill files"** was one of three
defensible counts of one directory — 17 routable (`skills/*/SKILL.md`), 18 `SKILL.md` files in all
(`skills/hermes/` holds a Hermes-native one), 16 activated for every agent (`ripwire-opt-remarks` carries
`audience: contributor`) — and the README stated two of them, neither labelled. **"208 compile-time caps"** is 210
by `docs/limits_build.py`'s own derivation from `src/`. **"Directory symlinks are not followed"** understated the
limit: no symlink is followed, and a symlinked source file is not indexed at all, so a tree that reaches its
sources through links reads as if they were not there. **Exit code 2 was missing** from the exit-code table, which
is the one a CI script most needs — a policy gate fired (`--arch`, `--scan-skill`, `--quality-delta`), not an
unknown failure. And one sentence sent a reader to `--scan-skills` to check a single file, which is the directory
verb; the file verb is `--scan-skill=FILE`.

Unstated, and now stated: `git` is a runtime dependency for the history-backed verbs, which refuse with exit 1 and
a named reason rather than answering thin — `--map-diff` and `--rank-by=churn` answer and disclose the uniform
fallback, `--dmm` and `--pr-context` return an explicit unavailable row. A git URL as the root is the one thing
that touches the network. The write verbs return a receipt — region, `blob_sha`, contract check, tests to run —
so an agent never re-reads the file, and their payload is a whole definition, signature included, not a braced
body. Test coverage is read from call edges out of indexed test symbols, so a shell suite that runs a built binary
as a subprocess is invisible to it (`harness=script`, `reaches=0`) — which is this repository's own shape. `--json`
is an allow-list of nine verbs. `--quality-panel` has a `strict` preset that drops the two families which reshuffle
on unchanged code. Several verbs stay single-root in a multi-root run. Section 3.2 now splits by why a reader is
there — `scripts/pgobuild.sh` for a binary to use, the plain tree for work on the tool — and scopes the
`NDEBUG`/`DEGRADED_PATH_ALERT` warning to the development tree, where it belongs.

`--replace-symbol-body`'s one-line `--help` summary said it replaces a definition's *body*. It replaces the whole
definition, signature included, as its own long help already said and as both insert verbs say. An agent that
believed the summary sent a braced body and deleted the signature — disclosed in the receipt as
`post_check_unavailable`, not refused.

`test/readmedriftcheck.sh` gains three arms, so these counts cannot drift again: **(J)** the skills count, pinned to
the routable set and to the install fold's "sixteen of the seventeen"; **(K)** the `--json` allow-list, harvested
from `--help=--json` and required to match the guide in both directions, so a verb that gains `--json` support fails
the gate until the guide is updated; **(L)** the cap inventory, pinned to `docs/limits_build.py`'s derivation. Each
carries its own mutation control. Arm **(B)** took `head -1`, and so pinned one of the *two* sites stating the flag
count — the reference guide's copy had been free to drift since it was written; it now checks every site and names
the line that disagrees. `CONTRIBUTING.md` gains the rule those arms encode — an advertised count is an enumeration,
and if a set can be counted more than one way the prose must say which set — and the stale-object build hazard,
which until now lived only in `CLAUDE.md` ([#217](https://github.com/redhat-et/ripwire/pull/217)).

### Changed — published captures withhold the rename rows from the project's own history

The naming-calibration demo in the showcase captures and in `docs/COMMANDS.md` no longer reprints the rename rows from
the project's own renaming. Each withheld block is replaced by one line that says how many rows it withheld
([#193](https://github.com/redhat-et/ripwire/pull/193)).

### Changed — CI, the gate harness and internals, with no change to output

None of this changes the binary's output.

**The gate harness.**
- **A passing arm can no longer print FAIL.** Gates reported with `A && ok || no`, where `ok` is a `printf`. A blocked
  write to a full pipe can be interrupted by SIGCHLD and fail with EINTR, and the `||` then printed FAIL for an arm whose
  condition held. That happened on a macOS CI shard for #126. `ok()` now always returns 0 and records a failed write as a
  failure of its own. Every single-line site of that shape becomes an `if`/`else`: 1,782 sites on the base commit, as
  counted by `test/gateexitcheck.sh` arm (G2)'s scanner. `test/pargates.py` captures each gate into a regular file,
  where a write never blocks ([#142](https://github.com/redhat-et/ripwire/pull/142)).
- **`dispatchordercheck`** compared two runs of `--whereis`, which scans every branch of the repository around its
  fixture. A branch created between the two runs changed the answer. The gate now builds a private repository for its
  fixture ([#186](https://github.com/redhat-et/ripwire/pull/186)).
- **`pagingsweepcheck`** compared two cold `--whereis` runs that read the repository's shared ref namespace, so a
  branch created by anything else between the runs failed the gate. Those arms now run on the gate's own fixture
  ([#206](https://github.com/redhat-et/ripwire/pull/206)).
- **Three `--listen` gates share one HTTP client**, `test/lib/gatehttp.sh`. Readiness is an answered request, every
  request has a deadline, and a missing answer is its own FAIL rather than a verdict about the server. A server still
  warming up on a loaded macOS runner had read as "transports DIFFER"
  ([#188](https://github.com/redhat-et/ripwire/pull/188)).
- **The public-tree check reads decks, not just text.** A private pre-release name had reached public files — prompt
  text, an error message, a grader regex, docstring examples, `docs/EVALS.md`, three `src/` comments and six gates —
  and was fixed forward, with history left alone. `ripwirepubliccheck` arm 1b now stores only the SHA-256 and the length
  of the lowercase token, scans every tracked text file and every tracked deck (a deck it cannot read FAILS the arm),
  and prints `path:line` only, so a red run's log does not republish what it is looking for. Other command names for
  the agent-loop instrument come from `AGENTLOOP_TOOL_ALIASES`; the grade header and the grader's audit summary state how many
  aliases are in force, never the names. The `release` CI job installs `pdftotext` for the deck extractor. Red first:
  run against the merge base's checkout the arm fails with 36 locations in 13 files
  ([#209](https://github.com/redhat-et/ripwire/pull/209)).

### Changed — `mcpremotecheck` moves to the shared HTTP client

The last `--listen` gate that still had its own HTTP client gets the same deadlines and no-answer FAILs. Against a
listener that stalled, it had hung. Against one that died, it had judged the silence as verdicts
([#194](https://github.com/redhat-et/ripwire/pull/194)).

### Changed — aliasing contracts, checked in debug and read by the optimizer in release

**`VERIFY_NO_ALIAS` is an optimizer fact in release, not an inert assume.** `src/infra/Diagnostics.h` §6's macro now
expands to `__builtin_assume_separate_storage` under `NDEBUG` on clang 17 and later (`__has_builtin`-guarded,
`( (void)0 )` elsewhere), beside the debug check, so codegen matches `__restrict__` on the parameters: the gate's
`out=a; out+=b; out+=a;` arm goes 10 → 6 instructions on arm64. The previous
`__builtin_assume( &a != &b )` form was never consumed by alias analysis, so it was a debug check that promised an
optimization it did not deliver. The promise is scoped honestly to the shipped binaries: the macOS x64 release binary
consumes it fully, the macOS arm64 binary — AppleClang 16, which is LLVM 17 — consumes it for scalar accesses only,
because BasicAA reads the bundle there only with the `-mllvm -basic-aa-separate-storage` flag CMake now probes for and
passes — to our targets and to the ld64 link under LTO — that switch being `cl::init(false)` in LLVM 17 (AppleClang 16
/ Xcode 16.2: the macos-14 CI runners and the macos-arm64 release leg) and true from LLVM 18, and even then LLVM 17
does not carry it into loop vectorization (fixed upstream in LLVM 18); the Linux release binaries, built with GCC,
keep the debug check alone. A new `VERIFY_NO_ALIAS_BUF` is the form for two owning
containers, where the promise has to land on the buffer rather than the object; views that can share one allocation are
refused at compile time. `test/noaliascheck.sh`, eight arms red against the old definition, compiles the real slice three ways with a `=false`
negative control and a cross-check against the cached CMake probe, and WARNs, naming the compiler and the upstream issue, where the loop
path is not consumed ([#200](https://github.com/redhat-et/ripwire/pull/200)).

**Twenty-one functions state the contract at entry.** Fifteen functions whose two-or-more same-element-type
out-parameters would silently mis-compute or invalidate an iterator if a caller passed the same object twice now say so
at entry and abort on it in debug builds ([#201](https://github.com/redhat-et/ripwire/pull/201)); the last six —
`splitNoteTail` (`src/notes.h`), `takeAckNamedToken` and `computeDelta` (`src/quality.h`), `waterFillRecallShares`
(`src/recall.h`), `markCandidateFilesIncludingDecl` (`src/graph.h`) and `partitionByScope` (`src/verbs_quality.h`) —
complete the audit's apply list ([#211](https://github.com/redhat-et/ripwire/pull/211)), `computeDelta` with a
null-safe `VERIFY_TEXT` rather than the object form, because both of its out-pointers default to null. These are correctness contracts, not a
performance claim: for the object form the promise measured no codegen change, because it says nothing about a
container's heap buffer. One function is the tree's only codegen row — `waterFillRecallShares` in `src/recall.h` reads
`demand[i]` while writing `alloc[i]` and never resizes either, so it takes the buffer form: release codegen **309 → 301
instructions** under the build's own flags.

**House rule, with a finding behind it.** `CONTRIBUTING.md` now requires the `__restrict__` spelling. On macOS,
`<sys/cdefs.h>` defines `__restrict` to nothing in every C++ translation unit, because `__STDC_VERSION__` is undefined
there, so any `__restrict` after a libc include was silently a no-op. Ripwire had none in `src/`, so this is a rule
rather than a fix ([#199](https://github.com/redhat-et/ripwire/pull/199)).

### Fixed — a C++ header selector answered with definitions it could not tie to that header (`unproven_defs=`)

A `file:name` selector that names only declarations is widened to the definitions they stand for. The candidate test
compared the name and `Symbol::scope`, the immediately enclosing class or namespace with namespaces dropped. So `a::Store`
and `b::Store` compared equal, and for a free function the test was the name alone. `--callers=a/Store.h:putObject`
answered `count="1"` for a caller in `b/Store.cpp`. `--callers=api.h:helper` counted two callers of different
internal-linkage `helper`s, in files that never include `api.h`. The true count for both is zero, and both answers
carried `counts_floor="1"`, a floor above the truth.

A candidate definition is now kept only when its file is a declaration file or includes one. The include is resolved
path-precisely, never by basename, and a definition the proof cannot tie to the header is not widened to
([#173](https://github.com/redhat-et/ripwire/pull/173)). What the proof drops is counted, not left silent. `--callers` and
`--callees` carry `unproven_defs=` (#173). So do `--impact`, `--safe-delete` and `--path`, and MCP `impact` and
`path_between`. Those verbs had answered from the declaration alone, which has no call edges: `--safe-delete=api.h:helper`
printed `risk="none-found"`. Its legend now says that `risk="none-found"` beside `unproven_defs=` is an incomplete read,
never a sign that the name can go ([#190](https://github.com/redhat-et/ripwire/pull/190)).

On ripwire's own tree, over every `file:name` selector whose selection is all declarations, 89 of 4,322 answers shrank
between the binaries before and after #173, and none grew. Two losses are known, and `unproven_defs=` counts both. A
`.cu`/`.cuh` include does not resolve for this proof, so a CUDA header selector can under-count. A body kept in a section
file that is pasted into a translation unit without including the declaring header is no longer reached; ripwire's own
`src/ingest.h:astQuery` is one. The one over-retention this left — an internal-linkage definition kept for another file's declaration of the same
name — is fixed below (#216). Gate: `test/decltodefcheck.sh`.

### Fixed — the remaining silent zeros from a declaration selector

`--uses`, `--mentions`, `--verify` and `--affected` answered a header selector from the declaration alone when the proof
dropped its definitions: `--uses` printed `count="0"`, `--mentions` `docs="0"`, `--affected` `tests="0"`, and
`--verify`'s `uses()`, `unused()`, `calls()` and `reaches()` answered from one declaration. Each now carries
`unproven_defs=` with a clause worded for that verb; `--verify` keeps its three verdicts and says that `not-established`
beside `unproven_defs=` is an incomplete read ([#195](https://github.com/redhat-et/ripwire/pull/195)).

### Fixed — every verb that resolves a focus now says what it could not prove, and a declaration yields to its definition

#173 stopped a `file:name` selector from following a declaration to a definition it could not prove belongs to it, and
#190 and #195 disclosed that drop on the graph and listing verbs. The verbs that resolve a *focus* symbol were still
silent. `resolveFocus` now returns the count, and the answer's root carries `unproven_defs="K"` — absent at zero — with
a per-verb clause: on `--edit-check` (including `--dry-run` and the MCP twin with and without `new_body`) it sits beside
`incompatible=` and says that an `incompatible="0"` next to it is an incomplete read, not a sign the edit is safe; on
`--lego`, `--connect` (summed over its terminals), `--around`, `--slice` and their MCP twins; on the `<ctx>` root
`--expand` and `--outline` share, summed in every serving mode and charged in `est_tokens`; beside `--owners`' `defs=`;
as a JSON key on MCP `fetch_body`; and as its own stderr line on `--note-add`.

A C/C++ declaration without a body also now yields the focus to the lowest-id C/C++ definition with a body in the same
scope. The rule is scoped on purpose: measured over all 12,996 names in this repository, an unscoped "prefer a body"
moved 132 picks, 69 of them wrongly (Python and JSON keys, TypeScript overloads, jumps between languages), while the
scoped rule moves 54, each a C/C++ declaration to its own definition. Four legend sentences that called the pick "the
lowest-id one" are reworded. `test/decltodefcheck.sh` grew 36 rows red on the merge base for the disclosure, 18 more for
the narrower sites and 9 for the focus pick; 212 of 212 pass now, also under ASan
([#210](https://github.com/redhat-et/ripwire/pull/210)).

### Fixed — the callers answer's `next=` pointed at a `--uses` call that could not list the declined site

0.6.0 gave `--callers` a `declined_calls=` count and a `next=` pointer to the `--uses` call that shows those call sites.
On a bare name the pointer landed. On a narrowed selector (`file:name`, `@FILE:LINE`, a canonical id or `Scope::name`) it
repeated the narrowed selector. That `--uses` answer keeps only sites that resolve to the chosen definition, and a
declined call resolves to none, so a reader who followed the pointer got `count="0"`.

When a narrowed selector has declined calls, `next=` now names the bare-name `--uses` call in the XML, columnar and MCP
`find_referencing_symbols` answers. The callers legend says that list includes sites bound to other same-named
definitions. Every other answer keeps its bytes. `test/declinecheck.sh` arm (E) follows the pointer and requires the
declined site to appear, across Java, C++, Python and Rust spellings.

Contributed by **@antoleod**, in their first contribution to ripwire
([#182](https://github.com/redhat-et/ripwire/pull/182)), closing [#158](https://github.com/redhat-et/ripwire/issues/158).

### Fixed — a `#if 0` block stopped serving calls in 0.6.0 and went on serving every other role

0.6.0 stopped serving CALL sites from preprocessor-dead ranges and left every other role serving them. A `role="write"`
inside `#if 0` is a write that cannot compile, and `--uses` counted it: on the gate's fixture `--uses=Owner.field`
answered `count="4"` carrying `counts_floor="1"` where the truth is 2 — a floor above the truth, which is the contract's
own failure direction. Reads, writes, both emitters of `role="import"` (`using ns::x;` and `#include`, the second living
in a code path #62 never touched), `extends`, types, the `#else` of `#if 1` and of `#if 0`, variable-to-type bindings and
dead definitions are all excluded now. The question is asked once per file and answered once per record, keyed on the
record's own site byte, rather than as five more `continue`s.

Excluding dead *definitions* was the invasive half, so it was measured: on llvm-project (8,861 C-family files, 381,811
symbols) it is **−14 symbols, +3 edges, −16 declined**, with `ambiguous`, `unresolved`, `est_tokens`,
`extent_suspect_syms` and the unindexed roll-up all unchanged; every dropped row is a real `#if 0` definition, among them
five in `Descriptor.cpp` that LLVM itself comments as not needed, whose names had been minting `overloads="2"` against a
live macro. Ripwire's own map is byte-identical to the base, and user CPU on llvm is 59.1 s against 59.4 s, interleaved.
The honest costs: `--grep` is unchanged (text inside `#if 0` is still findable, hit rows byte-identical), and
`--expand=deadType` now refuses with a suggestion rather than serving a dead body. A residual is disclosed rather than
left to be found: the FFI `BindingAlias` records carry no site byte, so an `extern "C"` block inside `#if 0` still
contributes its aliases; giving them one is a record-shape change this defect does not earn. `kParserVer` 93 → 94 with
its mirror; `kCacheVersion` stays 21, because no record gains or loses a field — only which records are extracted. Gate:
`test/ppdeadrolescheck.sh`, written and run red against the unmodified base binary first
([#172](https://github.com/redhat-et/ripwire/pull/172)).

### Fixed — attributes an answer printed with no definition (`graph_unindexed=`, `--legend=compact`)

`graph_unindexed=` counts the files no grammar in this build can read. It shipped in 0.6.0 on roots whose legend never
defined it: `--lego` on the CLI and over MCP, `--verify` and `--nonlocal-state`, whose legends are fixed text rather
than the shared builders. `--legend=compact` rebuilds its definitions from a table of terms, and that table had no row
for it, so it was also undefined under compact on every XML verb that can carry it except `--connect`. Both now define it
([#169](https://github.com/redhat-et/ripwire/pull/169)).

The same table had no row for `declined_calls=`, `unproven_defs=`, `bodyless_defs=`, the `--uses=Owner.field` member
form, the multi-root `<root label= p=>` table, `--lego`'s `methods="0" caveat=`, or `pr_iters=` on every PageRank root.
It also lacked the map-header fields whose `hdr:` definitions compact strips, among them `declined=`, `external=`,
`max_tokens=` and `over_ceiling=`, plus `--around`'s `defs=` and `--rank-by`'s `rank_by=` and `window=`. Each now has a
term that prints only when its attribute is present. Answers that carry these attributes can exceed the dialect's nominal
400 B; the alternative was a number with no definition ([#185](https://github.com/redhat-et/ripwire/pull/185)).

### Fixed — twelve more attributes get compact definitions

Under `--legend=compact`, these attributes now carry definitions: `--tree`'s `files=`; `--zoom`'s `symbols=`,
`isolated=`, `top_modules=` and `levels_shown=`; a cut `<module>`'s `children=`; churn-decay's `<recent of=>` and
`<rc age_d= w=>`; and the map rows' `lpin=`, `overloads=` and `prov=` ([#189](https://github.com/redhat-et/ripwire/pull/189)).

### Fixed — compact definitions that did not fit the byte pins, so the pins now follow the definitions

Several answers still printed attributes their compact legend never defined: the map header's own counts, `--impact`'s
blast-radius counts, `--safe-delete`'s verdict fields, the `--communities` and `--community` structure counts, and
`tested="1"` rows on `--callers`, `--callees`, `--impact` and MCP `impact`. Defining them honestly did not fit the
dialect's single 400 B per-answer pin, so the pins follow the definitions: each compact schema is pinned at its measured
size rounded up to the next 10 B plus 10 B — map 810 B (measured 799), communities 820 B (807), map-diff 800 B (789),
impact 780 B (770), community 730 B (719), safe-delete 720 B (708), around 720 B (707), metrics 720 B (702),
pack-signatures 680 B (663), pack-top-n 660 B (649) and query 630 B (611), with the remaining schemas between 140 B and
410 B. The ten-verb loop total goes from 4,100 B to 4,900 B (measured 4,849 B), and MCP `impact` is pinned at 780 B.

A read-only review of every definition against the code that emits it found three readings that were wrong, all
corrected here: `--safe-delete`'s `t=`/`p=` name the lowest-id *match*, not the lowest-id definition, because a
header-qualified selector keeps its declarations; `changed=` counts only indexed git-changed files and is 0 when git
cannot be read; and `--communities`' `bridges=` counts community pairs, one-symbol communities included.

`--help` no longer claims a fixed "≤400 B legend": it states the per-verb sizes and, restated from measurement, a saving
of "at least 45%" on a small `--callers`/`--uses`/`--impact`/`--affected` answer, down from "at least 50%" — the measured
savings are 65.91%, 63.79%, 46.17% and 64.73%, a per-call drop of 2.8–5.8 KB. Byte identity was checked against the
pre-change binary: 39 of 40 non-compact answers are identical (`--help=all` is the only difference), and all 26 compact
answers keep every row and data comment byte-identical, with only legend text changing. Left for a follow-up:
`tested="1"` is still undefined under compact on `--pack-task`'s `<d>` body rows and in the columnar `tested` column
([#203](https://github.com/redhat-et/ripwire/pull/203)).

### Fixed — `--for`'s `over_ceiling=` verdict could be written by the task text, and rung zero dropped legend clauses without a word

`--for` found which ceiling-ladder rung had fired by searching the finished header for that rung's note, and the header
also carries the task echo verbatim. A task containing that note got `over_ceiling="1"` on a document well inside its
budget. Since 0.6.0 the same search also ran inside the fit predicate, where matching text could push a real bundle down
the ladder. The ladder now returns the rung it took, so no task text reaches the verdict.

Rung zero, which drops legend clauses to fit, dropped the definitions of `confidence=`, `margin_pct=` and
`budget_tokens=` while keeping the attributes. It now names each attribute whose definition it drops, in the same shape
as the rungs above it. `test/ceilingverdictcheck.sh` is new, and `test/legendcoveragecheck.sh` gains a budgeted `--for`
row ([#174](https://github.com/redhat-et/ripwire/pull/174)).

### Fixed — `--connect`'s `est_tokens=` left out a legend clause it printed

When a file in the tree was unindexed, `--connect` added the `graph_unindexed=` attribute and a legend comment defining
it, but charged only the attribute to its estimate. `est_tokens=`, the `--max-tokens` fit and `over_ceiling=` therefore
measured a smaller document than the one emitted. The v0.6.0 binary was run on a matched pair of corpora, identical except
for one unreadable file: the document grew by 205 B while `est_tokens=` stayed at 1,068. The fixed binary reads 1,142.
The clause is now one named string that both the charge and the write read
([#171](https://github.com/redhat-et/ripwire/pull/171)).

In the same change, `skills/install.sh --hermes` links only the `ripwire-*` directories under `skills/hermes/`, as its
other two loops already did. The only directory there today is `ripwire-repo-map`, so no install changes.

### Fixed — `--help` left out twelve flag rows, and `--help=--FLAG` said they did not exist

`--help`'s one-line tier treats a row indented four spaces as a flag and anything else as prose. Twelve rows in
`src/cli.h` were indented six, so the flags on them were culled from `--help`, among them `--and`, `--not`, `--scope`,
`--partition`, `--dry-run`, `--apply` and `--grep-context`. `--help=--and` answered that it matched no flag, while
telling the reader that `--help` lists every row. The flags themselves always worked.

The rows now sit at four spaces, and the `docs/COMMANDS.md` generator accepts exactly what the binary accepts.
`test/helpbudgetcheck.sh` arm (K) takes its population from the flags `parseArgs` accepts, so a new flag missing from
`--help` turns it red. The eleven flags still unadvertised are listed in the gate, each with a reason
([#170](https://github.com/redhat-et/ripwire/pull/170)).

### Fixed — a client that dropped a large reply killed the `--listen` server

`ripwire --listen` wrote replies with a plain `send()`, and nothing handled SIGPIPE. A client that closed its connection
before reading a reply larger than the socket send buffer raised SIGPIPE, which ended the server, and every later client
was refused. Each socket now suppresses the signal, with `MSG_NOSIGNAL` on Linux and `SO_NOSIGPIPE` on macOS, so the
failed send drops that one connection and the server keeps serving. The CLI's stdout behaviour is unchanged.
`test/mcpremotecheck.sh` drops a client three ways against a reply larger than 4 MiB, and requires the same listener to
answer the next request ([#187](https://github.com/redhat-et/ripwire/pull/187)).

### Fixed — `--scip` ignored every index scip-java writes

ripwire read only SCIP's deprecated `Occurrence.range` field. scip-java writes the `typed_range` form instead
(`single_line_range` / `multi_line_range`), so no occurrence ever joined, and `--scip` produced output byte-identical to a run
without it. The reader now takes the typed form, and it outranks a deprecated `range` on the same occurrence whichever
arrives first, as `scip.proto` asks. On spring-petclinic the overlay went from no matches to 79% of occurrences, and
`graph_ambiguous` from 6 to 0. `test/scipcheck.sh` arm 10 re-encodes its fixture in the typed form (red on the old
reader), and arm 10b proves the fixture cannot pass without the typed fields. Contributed by **@dpunosevac**, in their
first contribution to ripwire ([#198](https://github.com/redhat-et/ripwire/pull/198)).

### Fixed — three surfaces said a missing `--scip` index degrades; it refuses

Since v0.4.0, a `--scip` path that cannot be opened exits 1 and serves no map, while a corrupt index still warns on
stderr and proceeds name-based. The `--scip` help row, the README and `skills/ripwire-navigate/SKILL.md` said a missing
index degrades and never fails. They now say what the binary does
([#184](https://github.com/redhat-et/ripwire/pull/184)).

### Fixed — `--scip` refuses a path that is not a regular index file

A `--scip` path that is empty, a directory, a FIFO or a device now exits 1, as a missing one does, instead of serving
the name-based map at exit 0. A FIFO had hung the run. The index is opened again when it is loaded, and that open no
longer blocks either: a path replaced after the check by something that is not a regular file degrades with the usual
warning ([#197](https://github.com/redhat-et/ripwire/pull/197)).

### Fixed — a symlink at a sidecar name is refused, not written through

`.ripwire_notes`, `.ripwire_quality_baseline` and `.ripwire_arch_baseline` are opened for writing with `O_NOFOLLOW`. When
one of those names is a symbolic link, the link is not followed: the write exits 1 with a message on stderr, and the link
is left in place. A sidecar that is a regular file is written as before. The arch baseline writer now also reports a
failed write, where before it could report success ([#178](https://github.com/redhat-et/ripwire/pull/178)).

### Fixed — a symlink at a sidecar name is not read through

The readers of the same three sidecars open them with `O_NOFOLLOW` too, so a symlink at a sidecar name is refused on
read as well as on write. Anything at a sidecar name that is not a regular file, a FIFO for example, is refused
instead of waited on, and a sidecar is emptied for rewriting only after it has been confirmed to be a regular file
([#191](https://github.com/redhat-et/ripwire/pull/191)).

### Fixed — the crawl does not follow a symlink out of its root

A symlink inside the crawl root whose target resolves outside that root is not followed. Every walk that reads files
skips it and lists it on `--skipped` in a new `escaped` class. It is counted as `escaped_root=` on the map header (XML and
JSON), `<flags>` and `<doc-drift>`. The attribute is absent at zero, so a tree without such a link gives byte-identical
output, and a symlink that stays inside its root is indexed as before
([#179](https://github.com/redhat-et/ripwire/pull/179)).

### Fixed — the suite's `skip=` count stopped depending on where the checkout lives

`test/pargates.py` decided whether a gate had SKIPPED — ran, but proved nothing — from the word SKIP in the first
400 CHARACTERS of its transcript, and 515 of the 628 transcripts of one full run open with a banner naming the
checkout's own absolute paths. The same commit and binary reported `skip=2` from a 137-character checkout and
`skip=3` from a 38-character one; 24 gates print a skip marker downstream of an absolute-root mention, the nearest a
real standing skip declared 145 characters in. The rule is written down instead of measured in bytes: **a gate that
proves nothing says so before it claims anything** — the first verdict marker decides, and a SKIP after a PASS or
FAIL is an arm-level skip inside a gate that did prove something. Replayed over those 628 transcripts, the new rule
and the old one disagree on ZERO gates. One direction is newly open and disclosed rather than left to be found: a
whole-gate skip printing a PASS row above its skip marker would read as a pass, which no gate does today and nothing
yet enforces. Gate: `test/skipclassifycheck.sh`, driving the real harness over one byte-identical probe from two
corpus roots about 130 characters apart, with `test/gateexitcheck.sh` arm (D) as the gate side of the contract
([#223](https://github.com/redhat-et/ripwire/pull/223)).

### Fixed — a relative command with no anchor, and a cap that bounded the answer and not the work

Fifteen defects from four review rounds over the three `--situ` entries above. **A `run=` is a command, and its path
comes from the corpus:** the runner verb and the path were concatenated, so an unusual but legal filename could
produce a `run=` that does not parse as the single command it presents itself as. The path is now always one shell
argument — quoted whenever it is not provably safe, by an allowlist that quotes any unenumerated byte, and preceded
by an option terminator so no path reaches an interpreter as an option. Every tracked path here is inside the
allowlist, measured at 0 outside it, so the emitted bytes are unchanged on every real corpus and no pin moved;
`test/runhintcheck.sh` arms (5) and (6) EXECUTE the emitted command in a scratch corpus, each with the pre-fix
spelling as its control. **A relative command is only as good as its anchor:** four surfaces spelled a path or a
command relative to a root they never declared — the shared run-hint clause on a multi-root run, `--flags --flip`,
the MCP edit receipt, and `--help` — and the one relativizer every `p=`/`uri=` emitter routes through returned early
on a leading `./` and matched a prefix only when the next byte was `/`, which the filesystem root can never satisfy.
`test/rootrelemitcheck.sh` arm 9b prints one command for six root spellings and executes each; `test/sarifcheck.sh`
arm 11 drives the function over 22 rows, 4 red before. **A cap bounded the answer and not the work:** the new
lexical-siblings block compared every unchanged indexed file against every changed path with the row cap applied
only after collection, O( (F + U) × C ). Changed paths are indexed by directory once into a sorted vector searched
with `lower_bound` (no `std::map`), the predicate still called on the narrowed range. Interleaved, best of 5, `-O2`
with the shipped flags, on a host at load 38 on 18 cores — so the absolutes are upper bounds and the ratio is the
measurement — llvm-project `4d5358b1` (8,856 paths, C=2,000) reads 333 ms → 11.6 ms and golang/go (12,555 paths)
449 ms → 42.8 ms, its second pass 1,005 ms → 136.5 ms; that llvm population grown to `docs/EVALS.md`'s 182,555-file
rung, synthetic in SIZE only, reads 9.10 s → 22.6 ms. Emitted rows are byte-identical on all nine rungs (1,413
rows). The same block paged on another section's offset and went silent on an empty candidate list — a silent zero,
which `docs/METHODOLOGY.md` §9 forbids — and four disclosures compressed into attributes kept a short reading each,
since `--situ` has no legend to look a name up in. Measured with `wc -c` against this lane's base binary:
`--situ=src/graph.h` 4,448 → 2,955 B and `--test-gate=src/testmap.h` 5,455 → 5,247 B. Gates:
`test/situshapecheck.sh` (17 rows red on that base binary), `rootrelemitcheck`, `runhintcheck`,
`test/receiptpostcheck.sh` (18). The lane's own sibling-row cap makes the cap inventory 211, republished by its
generators rather than edited ([#219](https://github.com/redhat-et/ripwire/pull/219)).

### Fixed — two generated documents, a scoped run's ranking notice, and a tilde no shell expands

Three from the scoped-recency lane's own review. **`docs/COMMANDS.md`'s generated table of contents minted anchors
by substituting a hyphen for every run of non-alphanumeric characters where the renderer DELETES that punctuation**,
so all 169 links resolved to nothing and had done since the document was first generated; markdownlint's MD051 had
been reporting it 28 times on one line. The generator states the renderer's own rule now and assigns anchors in
emission order, audited by `test/docscommandscheck.sh` arm (J), which restates that rule rather than importing the
generator's — a gate that asks the generator what an anchor should be agrees with its mistake. `docs/TUNING.md`,
likewise generated, asserted a sum instead of deriving one ("`112 + 12` accounts for the 128 NAMES" is 124) in the
one paragraph whose subject is that quoting a wrong pair would be wrong in both halves at once; recounted from the
data its table is built from, `src/` declares 129 caps under 128 distinct names, 111 tunable, 12 that must stay
`constexpr` and 5 declared after the sweep was frozen, and `capsweep.py emit` now REFUSES to render a partition that
does not add up. **A scoped run said its ranking fell back, having run no ranking:** under `--in=DIR` the
uniform-prior notice was false three ways at once — nothing is ranked on a scoped run (the rank vector is
zero-filled, which is why the header carries no `pr_iters=`), "this map" named a document the run does not contain
since the map IS the stub, and the comparison it offered is refused beside `--in`. **And a pasteable `next=` quoted
a tilde no shell expands:** `nextFlag` quoted any value whose first character is `~` whether or not a flag name
preceded it, so a run under `--exclude=~tmp` published `--exclude=&apos;~tmp&apos;` against an expansion that cannot
happen — the guard is "word-initial AND no flag name" now, a narrowing rather than a deletion. The worse half was
the gate, which pinned the corrupted form and explained it with a belief about POSIX that is wrong twice over; a gate
that pins a false belief defends the bug against the next person to fix it, so the explanation is deleted rather
than reworded and the measured rule stated in its place. Gates: `test/recentscopecheck.sh` 13e/13f,
`test/capsweepcheck.sh` (C), `test/nextverbcheck.sh` (9)
([#212](https://github.com/redhat-et/ripwire/pull/212)).

### Fixed — an unmeasured `est_tokens` said nothing, a no-throw contract threw, and two test-row readers went quiet

Six defects from one review, each a surface that was silently wrong rather than loudly broken. **`--pr-context`
shipped a modelled `est_tokens` with no disclosure:** when a trim level's measurement render fails it returns an
empty body, the ladder priced that empty body and the root printed the price, while the verb correctly streamed the
untrimmed floor. The only signal was a `DEGRADED_PATH_ALERT`, which is `do {} while (0)` under `NDEBUG`, so the
binary a user installs published a modelled number with nothing saying so (non-negotiable #3). The bytes were never
the bug and are unchanged: `truncated=` carries `;est-unmeasured`, defined in the legend in the same voice as
`budget-floor-exceeded`, which takes the tail's worst case from 248 B to 263 B and its buffer from `tail[256]` —
seven bytes of margin, as `test/fixedbufsweep.sh` had warned in terms — to `tail[320]`. **`renderToString`'s
no-throw contract had a throwing last statement:** the one allocation on the success path sat outside the handler, so
a `std::bad_alloc` escaped a function documented to return `ok == false` and jumped the `free()` below it. It is
caught in its own handler now and the buffer is released exactly once on every path, proved by a fault switch in
`test/prcontextcheck.sh` arm (G), red on the parent commit and honest in both build flavours. **The shared test-row
reader scanned arbitrarily far forward for a `[`**, so a `null` field's answer came out of the NEXT field's array at
exit 0 where its docstring promised a parse error; the value is read adjacently now. And two `test/` path readers
had never been converted to that reader — one splitting every row on `,`, one matching single rows only and
returning the empty set on a two-row fixture ([#214](https://github.com/redhat-et/ripwire/pull/214)).

### Fixed — a ceiling priced in the wrong unit, two price lists for one comparison, and shapes that outlived their output

Fifteen findings from two review rounds of the short-id and compact-legend lane. **The ceiling was priced in the
wrong unit, and then stopped being a byte test at all.** `--for` and `--pack-task` tested their ceiling rungs at
`kMinBytesPerToken` (2.36) while `est_tokens=` prices the delivered document per kind — markup at 2.50, bodies at
3.80 — so a lens spent rungs against a ceiling it was not measured against and dropped legend definitions from
documents its own root reports as conformant. Measured on a five-symbol fixture at `--detail=1`: at every budget in
1069..1099 the kept document prices at `est_tokens="1069"` with no `over_ceiling=`, and the rung dropped all three
clauses anyway to deliver 715 — 354 tokens of headroom spent to buy nothing. The exact ceiling is the token
comparison itself now, asked once on the finished document; the allowance rungs stay byte-based, which is their
contract, and no tolerance was widened. Separately the 1.15 overshoot tolerance had gated the first free drop as
well, so a document 1–15% over budget shipped `over_ceiling="1"` with all three explanatory clauses riding; that
drop is now tried against the number the root promises. **Rung zero also stopped being byte-negative:** it removed
110–164 bytes of clauses and spliced a 161-byte note naming them, +51 bytes on a route-less compact answer, so the
candidate is built and compared and a drop that does not pay is not taken. **`--expand` chose its serving mode on
two different price lists:** the whole-file candidate was charged its raw bytes and its legend — no envelope, no root
attributes, no closing tag — so on a fixture whose symbol sits in an 864 B file the root said `reason="file 1100B
&lt; bundle 1193B"` over a document that came out 1,262 B, selecting and reporting the whole-file form while the
bundle it rejected was smaller. Both candidates are one document type now, priced by one function that charges the
whole served document and settles the self-referential `mode=`/`reason=` disclosure with the same ≤4-pass fixpoint
`est_tokens=` uses; `expandmodecheck` (4a)–(4d) assert that `reason=`'s own count equals `wc -c` of the delivered
document in all three modes and sweep seven paddings across the decision boundary. **Three surfaces answered in
shapes the tool no longer produces:** the MCP file page's hand-composed `route=`, `--expand`'s whole-file serving
printing a full canonical id inside a `<src p=>` that had just printed the path, and a benchmark keyed on the retired
`id=` that collapsed two same-named methods into one key. A merged callee row was charged `name+16` while printing
about four bytes, so a block of overloads wrote `capped="1"` over a listing that would have fit, and `l=` is sorted
rather than appended in rank order. The route hooks' command-word rule asked the shell to split a line, which never
separates a control operator from the word attached to it, so `true; ripwire .` read as not-a-call; it lexes the line
itself now, quote-aware, executing nothing. Four gates were enforcing or reporting the wrong thing — one matching map
rows by the retired spelling, checking zero rows and printing PASS; one holding a hand-typed verb list that made it
enforce a command the binary refuses; one counting two of three droppable clauses; one discarding every exit status
under `eval … || true` — and every compact-legend pin was re-derived from its own stated rule, which seven rows had
not been following. And the compact-legend policy was audited in the direction that matters for the first time: both
existing arms started from a command that already carried the flag, so a command that should carry it and does not
was invisible to the gate; seven spans across six skills are fixed, and the gate asks the binary both halves of the
question now. `docs/LINEAGE.md`'s unqualified "no network" names its one documented exception in the same round: a
git URL is shallow-cloned before it is mapped ([#215](https://github.com/redhat-et/ripwire/pull/215)).

### Fixed — a header's declaration no longer widens to an internal-linkage definition (parser version 96)

The decl-to-def widening behind every `file:name` selector (`--callers=api.h:helper`, `--impact`,
`--uses`, `--safe-delete`, the MCP twins) kept a same-named definition when its file `#include`d the
declaring header. That proof is per FILE, and a translation unit that includes `api.h` for its own
reasons may define an unrelated `helper` in an anonymous namespace or as a namespace-scope `static` —
an overload (`helper(double)` beside the declared `helper(int)`) compiles, and by name it was gathered
and served. Internal linkage makes a definition visible to its own translation unit alone, so no other
file's declaration can stand for it. Raised by CodeRabbit on #139 after merge, outside the diff.

Every C and C++ definition now carries a syntactic `internalLinkage` bit — inside an anonymous
`namespace { }` at any depth, or carrying a namespace-scope `static` (a class-scope `static` member has
external linkage and is not marked). The widening keeps such a definition only for a declaration in its
own file and otherwise counts it in `unproven_defs=`, so the reader still learns that same-named
definitions exist which no row covers; the bare-name selector still shows them, as the legend says.

Measured on the gate fixture (`test/decltodefcheck.sh` arm B2: a header, its defining `.cpp`, one real
caller, and two including TUs with an anonymous-namespace and a `static` overload): `api.h:helper`
answered `count="3"` on main where `api.cpp:helper` answered `count="1"`; it now answers `count="1"`
naming the one real caller, with `unproven_defs="2"`. On this repository at `1cf3086e` the default map
is byte-identical and none of the 11 header-qualified `--callers` selectors over `src/ingest.h`'s
declarations moved (the tree has no colliding internal-linkage overload). `kParserVer` 95 → 96 and
`kCacheVersion` 21 → 22 (the def record gains one byte) with `quality.h`'s mirrors in the same commit;
old caches are rejected and rebuilt
(@andriytyurnikov, [#216](https://github.com/redhat-et/ripwire/pull/216)).

### Planned for 0.6.2

- **A redone "What `--quality-delta` catches" slide.** It left the showcase deck in 0.6.1, and returns with stronger
  examples, each reproduced from a real repository.
- **Faster cold Elixir ingest.** Elixir parsing walks each node's ancestors to find its scope, and costs about three
  times the CPU of other languages; one top-down pass that keeps a scope stack should recover it.
- **Calls brought in by Elixir's `use`.** 0.6.1 counts them as unresolved, so the drop is disclosed; 0.6.2 aims to
  model `__using__` so they resolve.
- **Header selectors that know C++ namespaces.** `scope` drops the namespace chain, so a definition in a *different*
  namespace with the same name is still kept for a header's declaration; 0.6.1 closed the internal-linkage half of
  that over-retention (#216) and recording the chain itself is what closes the rest.
- **A full head-to-head, measured on a quiet machine.** Cold index time, per-query latency, peak memory
  and answer size in tokens for equivalent questions, each axis pre-registered with its corpus, method, N and medians,
  both versions named, and a reproducible harness published beside the result. Nothing from it is published until the
  run is done on a machine that is not doing anything else.
- **The same comparison with an agent in the loop.** Several agent sessions per task across the frozen retrieval
  questions, change-safety tasks, real merged PRs and a SWE-bench Verified subset, starting from a pilot sized against
  the pre-registered instruments. Every loss is traced, fixed and re-measured before any result is published, wins and
  losses both.
- **`--legend=compact` as the CLI default.** The agent surfaces ask for it in 0.6.1 and the bare CLI does not. Flipping
  the default moves a published contract, so it happens under a pre-registered terminality readout — does the compact
  answer still end the task in one call — rather than on a byte count.
- **`--for --in=DIR`.** `--in` scopes the churn-decay map in 0.6.1; the same scope belongs on the ranked bundle and on
  its widening page.
- **A hunk-seeded `--situ`.** `--situ` reads changed files; seeding it from the diff's hunks would let the blast radius
  start from the lines that moved rather than the files that contain them.
- **De-ranking test paths.** A ranked answer to a question about production code still spends rows on the tests that
  exercise it; the ranker should know the difference and say when it has applied it.
- **`install.sh` served as a release asset.** The one-line install command will fetch the installer from the latest
  release, next to its checksum, instead of from `main`.

## [0.6.0] — 2026-09-11

**Languages and integrations from outside the project, much faster on the largest trees, and answers that say where
they stop.** Outside contributors wrote the Kotlin support (@xCatG), the Dart support (@calvinchengx), the Hermes
installer mode and Hermes-native skill (@AnkitArya, @ashutoshsinghpr7), JavaScript and TypeScript default-import
resolution (@PollyBot13), `CLAUDE_CONFIG_DIR` support (@s0undt3ch) and the Ruby constant-dependency work
(@andriytyurnikov). Outside reports caught the tool being confidently wrong (@YogevKr, @mariadb-KyleHutchinson,
@snrmwg) and asked how to remove it (@luisdavim). Each is named below, beside the entry their work produced.

### Highlights

**Kotlin.** `.kt` files are indexed: classes, objects and companion objects, functions, calls, imports and
inheritance. Calls cross the Kotlin/Java boundary in both directions, and a reference reaches the other JVM language
only when its own defines no candidate of that name, so adding `.kt` files never moves a Java-only edge. nowinandroid
indexes to 1,850 symbols across 384 files, ktor to 19,906 across 2,527, and retrofit's `Response.java:body` keeps its
279 callers (@xCatG, [#126](https://github.com/redhat-et/ripwire/pull/126)).

**Dart.** The 23rd grammar. On flutter/packages (3,706 `.dart` files) it indexes 71,726 Dart symbols (@calvinchengx,
[#75](https://github.com/redhat-et/ripwire/pull/75), landed in
[#106](https://github.com/redhat-et/ripwire/pull/106)).

**Ruby: the dependencies a Rails application actually has.** A Zeitwerk application spells almost none of its
dependencies with `require`. 0.6.0 reads the ones it does use: superclass constants, `include`/`extend`/`prepend`,
`autoload`, and constant receivers such as `User.find` — the reference that makes the autoloader load the file, where
nothing else in the file says so (@andriytyurnikov, [#57](https://github.com/redhat-et/ripwire/pull/57),
[#65](https://github.com/redhat-et/ripwire/pull/65), and [#78](https://github.com/redhat-et/ripwire/pull/78) landed in
[#91](https://github.com/redhat-et/ripwire/pull/91)).

**Faster where it hurt.** Warm `--grep` on llvm-project falls from 159.7 s to 9.2 s, and the warm default map from
248 s to 10 s ([#83](https://github.com/redhat-et/ripwire/pull/83)). The cold parse on that tree drops from 194.1 s to
155.6 s of CPU ([#127](https://github.com/redhat-et/ripwire/pull/127),
[#130](https://github.com/redhat-et/ripwire/pull/130)), warm `--pack-task` on go from 8.13 s to 5.88 s, and a repeated
`--for` on llvm-project from 274 s to 26 s once the cache stopped evicting its own working root
([#127](https://github.com/redhat-et/ripwire/pull/127)).

**Answers that say where they stop.** A `std::`-qualified call no longer binds an in-repo definition, so memgraph's
`SafeString::move` goes from 2,107 false callers to 3 ([#134](https://github.com/redhat-et/ripwire/pull/134)). A call
the resolver declines to guess is counted and named instead of silently dropped: 65,516 of memgraph's 295,086 call
references ([#136](https://github.com/redhat-et/ripwire/pull/136)). A parse derailed by a member macro carries
`extent_suspect=` and leaves the `--hotspots` ranking, and a budgeted `--for` stops shipping past its allowance
without saying so ([#135](https://github.com/redhat-et/ripwire/pull/135)). And YAML parses the same on aarch64 Linux
as everywhere else ([#140](https://github.com/redhat-et/ripwire/pull/140)).

**Agent integrations.** Initial Hermes and OpenClaw support, activated by `skills/install.sh --hermes` or `--openclaw`,
with `ripwire wrap` printing the MCP setup ([#51](https://github.com/redhat-et/ripwire/pull/51),
[#46](https://github.com/redhat-et/ripwire/pull/46)). `CLAUDE_CONFIG_DIR` is respected wherever ripwire looks for
Claude Code's configuration (@s0undt3ch, [#101](https://github.com/redhat-et/ripwire/pull/101)). `INSTALL.md` lists
every install route and how to remove all of it ([#121](https://github.com/redhat-et/ripwire/pull/121), asked for in
[#111](https://github.com/redhat-et/ripwire/issues/111)).

### Upgrade notes

- **Prebuilt x86-64 binaries now need an x86-64-v3 CPU, on Linux and on macOS.** x86-64 builds target
  `-march=x86-64-v3`: AVX2, BMI1/BMI2, FMA, LZCNT and MOVBE, the floor RHEL 10 sets, found on roughly Intel Haswell (2013)
  or AMD Excavator (2015) and newer. On an older x86-64 CPU the 0.6.0 binary will not run. The Intel macOS binary
  carries the same floor and still runs on macOS 14 and later; on Apple silicon, use the arm64 binary. arm64 builds need
  nothing new, because NEON is in the arm64 baseline. A plain build from source on x86-64 targets the same level;
  `-DRIPWIRE_NATIVE=ON` builds for the configuring machine only, and `./install.sh` from a checkout builds a Release
  binary tuned for that machine's CPU ([#127](https://github.com/redhat-et/ripwire/pull/127),
  [#137](https://github.com/redhat-et/ripwire/pull/137)).
- **The installer checks the CPU before it downloads.** On an x86-64 machine below v3, `scripts/install.sh` stops before
  the download and lists the missing features. `RIPWIRE_SKIP_CPU_CHECK=1` skips the check, for a VM that hides CPU flags
  its host still executes. When a downloaded binary cannot run, the installer now says why instead of reporting a
  version mismatch ([#138](https://github.com/redhat-et/ripwire/pull/138)).
- **The first run on each tree is a cold parse.** The cache format moves from 16 to 20 and the parser version from 81 to
  91, so a cache written by 0.5.0 is not reused. Separately, the cache root key is now one derivation for every cache
  family, so lean, rich, qchurn and MCP blobs written by older builds are clean misses, one cold parse per root, and the
  age pass sweeps them ([#127](https://github.com/redhat-et/ripwire/pull/127)).
  The parser version moves once more, to 92, for the YAML scanner fix below
  ([#140](https://github.com/redhat-et/ripwire/pull/140)); the cache format stays 20.
- **Output that changes by design.** Each change is described in its entry below.
  - `--quality-delta` dials each kind separately, and `churn="self"` no longer gates (#127).
  - `--help` prints one line per flag; `--help=all` prints the whole catalog (#92).
  - `--regex` anchors `^` and `$` match per line, and a match can no longer span lines. The `--grep` root gains
    `corpus_pruned_dirs=` (#85).
  - `--grep` and `--regex` no longer read gitignored files of an extension the indexer skips; `--no-ignore` restores
    them (#87).
  - `--recall` spends its budget on sections in rank order, and its disclosure names what was served (30b72ec0).
  - `--expand` lists up to 100 sibling names per body, where it listed 8 (3367d537).
  - `--handoff` shows up to 50 symbols per code file and 12 per prose file, where it showed 6. `--situ` lists every
    tests-to-run row, and `--doc-drift` and `--flags`/`--flip` page (#127).
  - `--help-task` no longer answers a "how does …" question with a symbol, and the MCP answer can carry `no_route`
    (#127).
  - A call inside a literal `#if 0` is no longer a call site, and graph verb roots carry `graph_unindexed=` (#72).
  - A `std::`-qualified C++ call no longer binds an in-repo definition outside namespace `std`. It counts toward
    `external=` instead, so `external=` reads higher (#134).
  - The map header can carry `declined=`, and `--callers`, `--callees` and `--impact` can carry `declined_calls=`
    (#136).
  - Cuts disclose themselves where they fire: `line_bytes=` on long matched lines, `…` on cut signatures,
    `budget_bytes="7500"` on a trimmed default `--for`, and cut markers on several listings (#100, #108). A cut
    `<calls>` listing keeps the callees ranked for the query (#95).
  - `--for --detail` says `over_ceiling="1"` when the answer passes `--max-tokens` (#77).
  - `--version` prints `emit=`, the formatted-output emitter the binary compiled in (88a5503b).
  - `--since`, `--merge-scout` and `--pr-context` refuse a revision that begins with `-` or does not resolve to a
    commit (#115, #116, #117).
  - A malformed `RIPWIRE_*` ranking calibration variable falls back to its default with one stderr line (#120).
  - `skills/install.sh --openclaw --hook` exits 2 instead of being silently ignored, and `--hermes --hook` is refused
    the same way (#51). `ripwire wrap claude` leads with the CLI (75ed8d3a).
  - `--hotspots` leaves functions flagged `extent_suspect=` out of its ranking and counts them in
    `unranked_extent_suspect=` (#135).
  - A file whose scanned sample holds invalid UTF-8 now reports a degraded parse (#126).
  - A budgeted `--for` that cannot fit its allowance takes the ladder's last rung and discloses the overflow, where it
    used to ship past the allowance silently, so a few already-over-budget bundles come out larger (3d98f84d).

### Added — Kotlin, with calls that cross into Java (parser version 91, cache format 20)

Kotlin (`.kt`) is indexed from a vendored `fwcd/tree-sitter-kotlin` grammar: classes, objects and companion objects,
functions, calls, imports and inheritance, with scope-qualified canonical ids and complexity scoring. A JVM interop
bridge in `graph.h`'s `langCompatible` resolves calls between Kotlin and Java in both directions. Contributed by
**@xCatG** ([#126](https://github.com/redhat-et/ripwire/pull/126)).

- **A disclosure hole closed on the way.** File health never validated UTF-8 on the sample it scans, so a file with
  invalid UTF-8 but no tree-sitter `ERROR` or `MISSING` node reported no degraded parse at all, and `--skipped`'s
  disclosure had a hole. The same sample is now checked with the existing UTF-8 validator.
- **Checked.** `test/kotlincheck.sh` runs a fixture with calls in both directions between Kotlin and Java, a constructed
  same-name collision pair (including an `enum class` and a plain class), cross-file calls and imports, with every number
  pinned from a real run and mutation arms. The contributor found no ASan, UBSan or LSan report across 501 real `.kt`
  files from 8 Android/JVM repositories, a 41-file adversarial corpus (merge-conflict markers, mid-edit fragments,
  invalid UTF-8, Unicode, emoji and RTL identifiers, deep nesting), and about 9,500 more `.kt` files across nowinandroid,
  compose-samples, architecture-samples, ktor and Signal-Android. Output was deterministic and well-formed on every one.

### Added — Dart, the 23rd grammar (parser version 88)

Dart (`.dart`) is indexed as a first-class language: definitions, call edges and metrics, from a vendored
tree-sitter-dart grammar. Contributed by **@calvinchengx** ([#75](https://github.com/redhat-et/ripwire/pull/75)), landed
in [#106](https://github.com/redhat-et/ripwire/pull/106) with four maintainer commits on top. On flutter/packages (3,706
`.dart` files) it indexes 71,726 Dart symbols, and none of that corpus's 289 degraded parses is a `.dart` file. The
binaries before and after produce identical bytes on `src/` and on a 1,406-file multi-language corpus, so no other
language moves.

**The tree shape is why this is more than a table row.** tree-sitter-dart makes `function_body` a *sibling* of the
signature, never a child. A definition's span therefore stopped at the signature's closing paren, and every call in the
body was attributed to the nearest enclosing symbol. On the gate's fixture that meant 5 edges where 8 are expected, a
method's call landing on its class, and three top-level edges gone. The Dart arm adopts the following body for the byte
extent, the row extent and complexity. The call query is adapted from upstream rather than copied, so the cascade
`this..add(1)..reset()` is two call edges and the receiver is not one.

**A latent bug it exposed, fixed for every language.** Six per-language arrays took their extent from the last
enumerator written out by hand (`std::size_t( Lang::Elixir ) + 1`) instead of `kLangCount`, so appending a language
dropped it silently. With the two `--skipped` tallies reverted, a corpus of two `.cpp` and two `.dart` files prints
`indexed="4"` and a single `cpp` row, and nothing says a row is missing. The same landing registered Dart in two more
places where the honesty contract applies:
- `--nonlocal-state` had printed no `unanalyzed_langs=` on a corpus that was half Dart;
- `--lint` printed `count="1"` beside `applicable="0"` on naming rules that do fire on Dart names.

**Stated floors.**
- Named constructors and factories index under the class name, so a `C.seeded(1)` call site is unresolved rather than
  wrong.
- `noSuchMethod` dispatch names its callee at run time and is not an edge.
- `part` / `part of` is not resolved.

ASan/UBSan is clean over a 6,554-file Dart corpus, and a libFuzzer run of 109,431 executions produced no crash, leak or
timeout. Gate: `test/dartcheck.sh`, red against a pre-Dart binary and against a binary with the span arm alone disabled.

### Added — initial Hermes and OpenClaw support

`skills/install.sh` gains `--hermes` and `--openclaw`, and `ripwire wrap` prints a setup recipe for `hermes` and
`openclaw`. **This is initial support.** CI checks what the installers write on disk. For Hermes, **@ashutoshsinghpr7**
also ran the installer and the MCP registration against a real Hermes install when support landed; the maintainers have
not re-verified it since. OpenClaw has not been verified against a real install. If you use either,
[#69 (Hermes)](https://github.com/redhat-et/ripwire/issues/69) and
[#68 (OpenClaw)](https://github.com/redhat-et/ripwire/issues/68) ask for exactly that check.

**Hermes.**
- **Install.** `--hermes` deploys 17 skills into `${HERMES_HOME:-~/.hermes}/skills`: the 16 flat user-facing skills,
  plus the Hermes-native `ripwire-repo-map` skill from `skills/hermes/`. The release one-liner activates them when that
  home exists.
- **MCP.** `ripwire wrap hermes` prints the `hermes mcp add` registration. In the live run it connected and discovered
  31 tools.
- **No hook yet.** `--hermes --hook` is refused with exit 2. Hermes has a `pre_tool_call` slot, but ripwire's nudge hook
  still switches on Claude Code's tool names, so the installer says the port has not landed instead of printing a hook
  line it cannot honour.
- **Credit.** The installer mode, the release-installer branch and the `wrap` recipe are **@AnkitArya**'s
  ([#51](https://github.com/redhat-et/ripwire/pull/51)). They landed in
  [#76](https://github.com/redhat-et/ripwire/pull/76), which adds a gate arm checking that `wrap hermes` names the flag and
  directory the installer really uses. The Hermes-native skill is **@ashutoshsinghpr7**'s
  ([#46](https://github.com/redhat-et/ripwire/pull/46)), as is the widening of both skill-vetting sweeps so that a skill
  in a subdirectory cannot escape them.

**OpenClaw.** Agent support in `src/wrap.h` used to live in five hand-maintained lists that nothing forced to agree. It
is now one table, `kAgentTargets`, and OpenClaw is a row in it
([75ed8d3a](https://github.com/redhat-et/ripwire/commit/75ed8d3ac9e155618acf6317aa88a084e4f207b5)). Dispatch, usage
text, the skills line, `--all` detection and the README block all read from that table.
- **Skills root.** OpenClaw's is `~/.agents/skills`, which it reads only while its state directory is the default
  `~/.openclaw`. The recipe prints that caveat.
- **Context file.** It is `~/.openclaw/workspace/AGENTS.md`, not the repository's `AGENTS.md`.
- **No hook.** OpenClaw has no shell hook slot, so `--openclaw --hook` is now refused with exit 2 instead of being
  silently ignored ([#51](https://github.com/redhat-et/ripwire/pull/51)).
- **`wrap claude` changed too:** it now leads with the CLI, as `codex` and `opencode` do.
- **Gate.** `test/agenttablecheck.sh` iterates the table, so the next row is covered without editing the gate.

How to install and remove both is in `INSTALL.md` ([#121](https://github.com/redhat-et/ripwire/pull/121)).

### Added — derailed C-family parses disclose their guesses (`extent_suspect=`), and a member-macro re-parse repairs the commonest derailment (parser version 90, cache format 20)

**The problem.** A function-like macro invoked without `;` as the last member of a class or struct, such as
`EXC_NAME(Foo)` right before `};`, sends tree-sitter-cpp's error recovery off course. The earlier structs dissolve into
an ERROR region, and the last struct's body swallows what follows. The same shape derails tree-sitter-c and
tree-sitter-objc. On memgraph, one file had 472 of its 487 definitions misfiled. A 14-line function,
`PrintFuncSignature`, was reported with `cx=749 ccx=920` and ranked #4 in `--hotspots`, and nothing on the row said
anything was wrong.

**The detector.** `src/extentsuspect.h` makes one linear pass per file over spans that are already sorted. A definition
a derailed parse filed in the wrong place carries `extent_suspect=`, naming the rules that fired:
- `name`: a name outside its own definition's signature;
- `head` (C family): a definition in another definition's return-type position, before its name;
- `scope` (C++): filed under `C::` while lying inside a different class;
- `error`: a class whose body holds an error inside an ERROR region, and what it contains.

Map, `--for`, `--expand` and `--json` rows carry the attribute. The header carries `extent_suspect_syms=`, and
`--skipped` gets per-file rows plus `extent_suspect_files=`. Each is absent at zero, and its legend line appears only on
output that carries it. `--hotspots` leaves flagged functions out of its ranking instead of ranking a number the tool
itself calls an artifact. It says so with `extent_suspect_syms=` on the row and a fourth partition bucket,
`unranked_extent_suspect=`, so the partition still sums to `files=`.

**The re-parse.** `src/macroreparse.h` touches only a C, C++ (including CUDA and Metal) or ObjC file whose first parse
holds error bytes. It blanks ALL-CAPS function-like macro invocations that sit alone on a line as class, struct or union
members, keeping newlines and byte offsets. It re-parses the blanked text and adopts the new tree only if that tree holds
strictly fewer error bytes. A blanked invocation stays a `role=type` use of the macro name, so `--uses` is unchanged.
Disclosure: `why=macro-blanked` and `macro_blanked=N` on the `--skipped` row, and `macro_blanked_files=` on the map,
`--json` and `--skipped` headers, absent at zero.

**Measured** on memgraph, main `096e3544` against the change:

| | before | after |
| --- | --- | --- |
| `PrintFuncSignature` | a method, `cx=749 ccx=920 loc=5479` | a free function, `cx=3 ccx=2 loc=15` |
| `mg_procedure_impl.cpp` in `--hotspots` | ccx 1871, top function 920 | ccx 960, top function 40, 0 flagged |
| degraded-parse files | 307 | 289 |
| extent-suspect definitions | — (no detector) | 241 in 9 files (detector alone: 1,613 in 31) |
| re-parsed files | — | 24 |
| cold CPU, 5 alternating runs | 8.114 s | 8.108 s |

On an llvm-project checkout, extent-suspect definitions go from 1,650 to 1,483, and 24 files are re-parsed. A file that
is not re-parsed keeps every definition, scope and complexity; only graph knock-on effects, such as caller counts and
rank, move.

**Limits, stated.**
- Only the ALL-CAPS class-body shape is repaired. Lowercase and namespace-scope macro runs still derail, and the detector
  keeps flagging them: on memgraph 241 flags remain, 93 of them in `eval.hpp`.
- A partial repair is still adopted when it holds fewer error bytes. `err=` describes the adopted parse, so it can rise
  while `err_ratio` falls: on `mg_procedure_impl.cpp` it goes from 1 to 50 nodes while error bytes fall from 271,971 to
  376.
- `--match`, `--lint` and `--slice` parse files themselves, so they still see the first parse.
- The `name` and `scope` rules have no real-world trigger today; they are guards, pinned by unit cases.
- This repository's own map always carries the new legend lines, because the fixtures live in the tree (about +430
  `est_tokens` on ripwire itself). Corpora with nothing flagged are unaffected.

`kParserVer` goes 88 → 90 and `kCacheVersion` 18 → 20, because the per-file cache record gains a field. Gates:
`test/extentcheck.sh` (55 checks) and `test/macroreparsecheck.sh` (103 checks), both red on their pre-change binaries
([#135](https://github.com/redhat-et/ripwire/pull/135)).

### Added — `INSTALL.md`: every install route, and how to remove all of it

A new `INSTALL.md` gathers every way to install ripwire:
- the prebuilt one-liner and its variables;
- building from source, and `./install.sh`;
- activating skills for Claude Code, Codex, Hermes, OpenClaw or any directory;
- the optional advisory hooks;
- the MCP server via `ripwire wrap <agent>`;
- checking and upgrading.

It ends with how to uninstall, which **@luisdavim** asked for in
[#111](https://github.com/redhat-et/ripwire/issues/111). The uninstall section covers:
- the binary and staged files;
- the `ripwire-*` skill links;
- ripwire's hook entries;
- MCP registrations, per agent;
- pasted rules blocks;
- the cache;
- the per-repository files ripwire writes only on request.

Every path comes from the code. The uninstall snippets were extracted from the page itself and run against a sandboxed
`HOME` with synthetic installs, and all 15 checks passed. They cover both what must be removed and what must be kept,
such as an unrelated binary, another tool's hook and non-hook settings keys. A `.bak` is written before each config edit,
and a second run is a no-op ([#121](https://github.com/redhat-et/ripwire/pull/121)).

### Added — `--help` in two tiers: one line per flag, every disclosure one call away

`--help` now prints one line per row, saying what exists and roughly what it does, in **4,473 tokens instead of
46,385** (10.4×). Nothing is deleted:
- `--help=<flag>` returns that row's every disclosure;
- `--help=<section>` returns one family at full detail;
- `--help=all` returns the whole catalog exactly as before.

The evidence made this a split rather than a trim. A third-party evaluation (callstack/agent-device #2400) measured
ripwire spending about 10% more tokens than grep-and-read and traced the cost to the per-call legend. The fix,
`--legend=compact`, was already documented, but 92% of the way down a 1,597-line document. Asking for the one row that
answers a question now costs 90 tokens. `test/helpbudgetcheck.sh` holds tier 1 to a token ceiling and proves every
advertised row is still retrievable from tier 2, so the ceiling cannot be met by deleting content
([#92](https://github.com/redhat-et/ripwire/pull/92)). Before the split, the `--legend` entry was rewritten to lead with
what the full legend costs, a fixed ~3 KB, and `test/legendcostcheck.sh` reads that floor out of `--help` and measures
against it ([8c20e108](https://github.com/redhat-et/ripwire/commit/8c20e108)).

### Added — `.rst`, `.adoc`, `.org` and `.mdx` reach `--recall` (parser version 85)

These extensions were not indexed at all, so a `--recall` over a repository that documents itself in reStructuredText
or AsciiDoc returned nothing and, correctly but unhelpfully, said zero. They now reach `--recall`, `--for` and
`--handoff` on the markdown grammar tier. Gate: `test/textdocscheck.sh`
([#80](https://github.com/redhat-et/ripwire/pull/80)).

### Changed — `--recall` serves ranked passages, not document prefixes

`--recall` scored a document's markdown sections by relevance, then put them back in document order and let the byte
budget cut from the front. On a document larger than its share of the budget, the best section could be unreachable at
every ceiling: on a 616 KB `docs/COMMANDS.md`, the `--field-affinity` section at line 3570 of 4755 ranked #1 and was
served at none of 1,500, 4,000, 12,000 or 40,000 tokens, while the table of contents at the front of the file was.
Sections are now own-prose units that tile the document, the allowance is spent in rank order one whole unit at a time,
and the disclosure reports what was served: `[sections: S of R selected (N in doc) ... dropped_by_budget=D]`, with
`lines=` naming exactly the ranges in the body. An enclosing section no longer outranks the subsection that holds the
answer, because a unit's score is scaled by its own-prose evidence over the strongest own-prose evidence in its subtree.

Measured on a frozen 1.88 MB corpus: answer reachability went from 5 of 14 to 9 of 14, natural-language-first from 43
to 79 at 1,600 tokens, and query-term coverage rose by 58, 56 and 40 at 4,000, 8,000 and 16,000 tokens. Budget
monotonicity holds within a document over 1,380 ceilings with 0 shrinks, but not across documents, and the surfaces
that claimed otherwise now say so. Gate: `test/recallpassagecheck.sh`, written before the fix
([30b72ec0](https://github.com/redhat-et/ripwire/commit/30b72ec0)).

### Changed — one header of SIMD string kernels, and the quadratic child walks gone

For every invocation below, output is byte-identical before and after; the verbs whose output this round changes on
purpose are in their own entries. Main's binary (source `9356cf23`) was measured against the merged tip of the round,
with the same argv and interleaved arms. CPU is user+sys, the median over n pairs, on a shared machine at load 7–14:

| corpus | invocation | before (CPU s) | after (CPU s) | Δ median | n |
| --- | --- | ---: | ---: | ---: | ---: |
| llvm-project | cold map `--no-cache` | 194.14 | 155.60 | −19.9% | 1 |
| go | warm `--pack-task` | 8.13 | 5.88 | −27.6% | 5 |
| go | warm `--lint` | 18.43 | 15.18 | −17.7% | 5 |
| rocksdb | warm `--lint` | 6.77 | 5.60 | −17.3% | 5 |
| rocksdb | warm `--pack-task` | 0.68 | 0.60 | −10.9% | 5 |
| rocksdb | cold map `--no-cache` | 7.96 | 7.42 | −6.7% | 5 |
| ripwire (own tree) | warm `--pack-task` | 0.45 | 0.38 | −15.5% | 5 |
| ripwire (own tree) | warm `--lint` | 4.21 | 3.91 | −7.3% | 5 |

A warm map, `--for` and `--grep` are within noise; their floors are the serial resolve loop and file opens.

**The O(C²) child walks.** An indexed child walk over a tree-sitter node restarts the vendored iterator on every call, so
the loop is quadratic in the number of children. It only bites on wide, flat child lists, which C/C++ include guards
and comment floods produce, which is why the llvm-project cold parse moved most. `collectPreprocDeadRanges` and the other
23 quadratic walks move to one cursor helper, `src/infra/tschildren.h`, with 18 isolation arms proven red first at
11–125× ([#127](https://github.com/redhat-et/ripwire/pull/127)). [#130](https://github.com/redhat-et/ripwire/pull/130)
converts 22 more, each proven quadratic on the pre-change binary first at 13×–126× its control under a 16,000-comment
flood. Three loops stay indexed, with the reason written at the loop, and 156 generated fixture × verb pairs plus the 21
committed ones are byte-identical.

**One header of string kernels.** `src/infra/strkern.h` holds nibble-table byte classification, an A–Z fold, and byte,
byte-set and 3-byte finds, each with a NEON path, an AVX2 path and a scalar twin. The query tokenizer is rewritten on it
as mask algebra, proven against verbatim copies of the old walkers, beside a BM25 head-mask index; that is the
`--pack-task` row. The XML and JSON escapers copy clean runs between the bytes a 256-bit set finds (escaper share 4.6% →
2.0% and 6.3% → 2.6%). A SIMD scan for `--grep` was measured and refused: that verb is bound by file opens, and the scan
is 0.4% of busy samples.

**Lookups hoisted out of the per-node path.** 199 `ts_node_child_by_field_name` sites now read a per-grammar `TSFieldId`
table, checked on 1,189,205 enumerated (node, field) pairs. The `#match?` predicate's regex is compiled once per query,
not once per match, which is the `--lint` row.

The techniques are credited in `docs/LINEAGE.md`, which now folds 49 repositories and 70 papers, among them Langdale &
Lemire (VLDB J. 2019) for nibble-table classification, Daniel Lemire's 2023-07-13 blog code, StringZilla and Tempesta
fast_str. The kernel tests are a doctest target, `ripwire_test_strkern`.

### Changed — `--quality-delta` dials each kind separately

On 12 landed commits, `--quality-delta` had gated all 12, with a true-positive share of 2%. Each kind now has its own
rule:
- `churn="self"` is informational; what gates is two committed rewrites inside the window.
- Dead-code sees header files, where 96.8% of this repository's `src/` lines live, and excludes language-invoked symbols
  instead.
- Verbosity counts code lines.
- Complexity and verbosity gate on a threshold crossing or on growth of at least 25%.
- New api-surface symbols become a count, `api-new-surface=`.

On the same 12 commits, gating went from 12 of 12 to 8 of 12, the true-positive share rose from 2% to 12% with 0 wrong
rows, and the synthetic regressions caught rose from 5 to 7. The legend gains the `api-new-surface=` count and the churn
facets' gating rule ([#127](https://github.com/redhat-et/ripwire/pull/127)).

### Changed — `--handoff` shows more, and three listing verbs page instead of cutting

Caps are blow-up guards on the way to one complete answer, and none of this lowers a value to shrink a byte count.
- **`--handoff`** shows up to 50 symbols per code file and 12 per prose file, where it showed 6. Containment rises from
  16% to 54%, and the change only adds rows.
- **`--doc-drift`, `--flags`/`--flip` and `--situ`** disclose their cuts and page. Answer rows never page, so `--situ`'s
  25-row cap on tests-to-run is retired: every row is listed, and no cut is disclosed because none is made. The gate has
  33 checks, 24 of them red before the change.
- **The cap sweep was re-derived** once six honesty defects in its harness were fixed: 64 of 151 answering rows, where
  59 of 195 had been published ([#127](https://github.com/redhat-et/ripwire/pull/127)).

### Changed — `--expand` lists up to 100 sibling names, and every cap is listed in `docs/LIMITS.md`

A body's `sibs=` list on `--expand` was capped at 8 names. On this repository the median file holds 4 symbols but p99
holds 85, and symbols concentrate in large files, so the cap fired on 68.5% of bodies and hid 89.3% of sibling names. The
cap is now 100, above p99: 15.8% of bodies are cut, 56.2% of sibling names are visible where 10.7% were, and a
single-symbol `--expand` answer grows 36%. `sibs=` reaches only `--expand`, so `--for` and `--pack-task` are
byte-identical at every cap value tested. The README's `--pack-signatures` figure moves as a consequence (top-50 71.0% →
81.8%), because `--expand`'s bodies are that ratio's denominator; the cap was chosen on recall grounds and the figure
re-derived afterwards ([3367d537](https://github.com/redhat-et/ripwire/commit/3367d537)).

That cap is why caps now have an inventory. `docs/LIMITS.md` lists every cap in `src/` with its value, its site and
whether its file discloses a cut when it fires. It is generated by `docs/limits_build.py`, and `test/limitstablecheck.sh`
fails when it drifts. It began at 120 caps across 51 files (3367d537).
[#108](https://github.com/redhat-et/ripwire/pull/108) added the INDEXING/OUTPUT column, the hyperparameter register,
`docs/TUNING.md` and the `bench/capsweep` harness. [#123](https://github.com/redhat-et/ripwire/pull/123) pins each cap by
what it is rather than the line it sits on, so a comment above a cap no longer reddens CI.
[#127](https://github.com/redhat-et/ripwire/pull/127) adds a BOUNDARY class, and
[#128](https://github.com/redhat-et/ripwire/pull/128) gives the per-file tables their own `## Caps, by file` heading;
they had been filed under "Not caps". On main the register counts 208 caps across 83 files.

### Changed — faster ingest and graph building: the per-node dispatch, the include closure, three loop hoists

These build on the cone memo in the Fixed entries below. Every result here is an interleaved A/B, and output is
byte-identical before and after.

**The per-AST-node `strcmp` dispatch goes inline.** The ingest walk chooses a branch with chains of about forty
`std::strcmp` calls against `ts_node_type()`, once per AST node. `strcmp` is an external symbol that LTO cannot inline,
and on macOS each call also hops two dyld stubs. Sized before any change, `strcmp` was this share of busy samples:

| corpus | `strcmp` share of busy samples |
| --- | --- |
| rust-analyzer | 12.31% |
| go | 10.76% |
| llvm-project | 10.56% |
| django | 9.31% |
| rails | 6.14% |

`rw::kindIs` (`src/infra/nodekind.h`) is the same compare, unrolled inline against a literal, and it replaces `strcmp` at
569 call sites. On llvm-project `strcmp` is now 0.23% of busy samples.
- **Why not SIMD.** On llvm-project, 92.96% of 4,861,917,534 compares decide at byte 0, and clang compiles the chain to a
  shared-prefix decision tree that uses no vector registers.
- **The claim.** As a range over llvm-project, django, go and this repository: **cold CPU 1–7% lower, cold wall 0.3–8%
  lower**, with all 32 statistics in the same direction.
- **Same output.** Byte-identical on seven corpora. `test/argvdiffcheck.sh` finds 640 of 642 vectors identical; the
  other two differ only in `--version`'s `built_from=`.
- **Gate.** `test/nodekindcheck.sh` checks `kindIs` against `strcmp` on 1,348,096 enumerated pairs, and uses a guard page
  to catch any read past the NUL ([#107](https://github.com/redhat-et/ripwire/pull/107)).

**The include closure's sort goes radix, above 128 elements.** On rails, 38.7 ms of the ~62 ms transitive include
closure (`buildGraph/2b`) was one `std::sort`. With radix above a crossover of 128:

| on rails | before | after |
| --- | --- | --- |
| `buildGraph/2b` | 65.21 ms | 35.01 ms (−46%) |
| `buildGraph` | 223.0 ms | 186.7 ms (−16%) |
| whole `--callers=main` run | | 7.8% and 8.5% faster at the median, two independent A/Bs |

Five control corpora stay within ±1.7%. The threshold is what makes the change safe: without it, the same conversion
regresses django 7.9×, a private C++ tree 7.7× and rust-analyzer 4.7×. Three more sites were refused with numbers.
django's `implementors` would be 2.87× slower, because its records arrive already sorted, which `std::sort` detects and
radix cannot. A `std::unique` that removed 0 duplicates in 24,216 calls is gone
([#97](https://github.com/redhat-et/ripwire/pull/97)).

**Three loop hoists; two candidates refuted.**
- The CHA-lite ancestor closure is memoised: −13.2% warm on rust-analyzer.
- `lexicalNormalize` builds one string: −6.0% on rails.
- The shadow guard asks its cheap question first: −26% on that phase.

A candidate-spray optimisation was 53% of scan volume and 0% of wall, so it was not built, and another candidate
measured inside the noise. After the cone fix, no single phase dominates on any corpus, and which phase is largest
depends on the corpus's language. `bench/PROFILE.md` carries the six-corpus table
([#96](https://github.com/redhat-et/ripwire/pull/96)).

**timsort is vendored and routed nowhere.** It was measured against `std::sort`, radix, pdqsort, an `is_sorted` guard and
`std::stable_sort`, on the real id sets of three call sites across seven corpora, and was not recommended for any of
them:
- on presorted input, a three-line `is_sorted` guard measured 0.35× where timsort measured 0.58×;
- on scattered input, timsort measured 1.71×, 6.0× slower than radix.

It ships in `src/infra/` for parity with the portable layer it belongs to. The measurement is in its header, and a gate
checks that no call site uses it ([#93](https://github.com/redhat-et/ripwire/pull/93)).

### Changed — `est_tokens` measured against a real tokenizer

`est_tokens` had been checked for being present, positive and deterministic, but never for being accurate. It is now
measured: 25 invocations on 2 corpora, counted with `o200k_base` and `cl100k_base`, which agree to within 1.4%. Three
findings are published in `docs/EVALS.md`:

- **Only 9 of 25 invocations print a price at all.** The sixteen that do not include every navigation verb. One
  `--edit-check` emitted 99,006 real tokens priced at nothing.
- **The signed error runs −18.4% to +41.7%**, with a median of +16–18%. It follows document shape, not corpus language:
  real bytes per token run from 2.44 on dense signature rows to 4.66 on legend prose. So no extra `kTokenCalib` row can
  fix it.
- **`--token-budget=N` delivers 48–82% of N.** The budget is a ceiling on the estimate, and at binding budgets the
  estimate over-reads by 25–42%.

`kTokenCalib` is unchanged on purpose. A single rate cannot correct a +40% bundle and a −16% body at once, and the
per-span charge that could is a change of its own. What landed is the instrument for that change:
`test/tokenbudgetcheck.sh` #18 holds every pinned invocation inside a measured band and the set's error under a 30%
ceiling. A comment in `src/serialize.h` saying the estimate "never systematically under-reads" was false on two corpora
and is gone. `--legend=compact` is a wash or a small loss on `--for`, whose budget refills the bytes the legend frees
([#79](https://github.com/redhat-et/ripwire/pull/79)).

### Changed — one emitter for formatted output, and `--version` says which one it compiled in

`src/infra/emit.h` is now the one place the formatted-output path is chosen: `std::print` where the standard library
defines `__cpp_lib_print` (libstdc++ 14 and later; libc++ at a macOS 14 or later deployment target), and `std::format`
plus `fputs` where it does not, so every toolchain still builds. `--version` prints the choice as `emit=`, and every CI
and release leg asserts `emit=std::print` off the binary it built. Behind it, `src/` no longer holds a single
`std::printf`, `std::fprintf`, `std::snprintf` or `std::sprintf` call site: 1,526 became 0, converted in batches against
a byte-parity fence that was widened before anything was converted
([88a5503b](https://github.com/redhat-et/ripwire/commit/88a5503b),
[25d901cd](https://github.com/redhat-et/ripwire/commit/25d901cd)).

### Changed — Shotgun Surgery is named where ripwire already measures it

Fowler's Shotgun Surgery, one change that touches many modules, has two measurable forms. The historical one is change
coupling, which `--cochange` mines and `--situ` and `--pr-context` turn into a check; the name now appears on the
`--cochange` and `--situ` help entries, the MCP `cochange` and `situational_awareness` descriptions, the README and four
skills. The static one, Lanza & Marinescu's CM×CC detection strategy, was prototyped on the call graph on two corpora and
not built: its top flags were stable hubs, and per-file static fan-in tracked how widely edits actually scatter at
Spearman +0.158 and +0.163. The shipped `--situ` co-change rule, backtested against prior history only, scores
precision@8 of 0.352 and 0.427 on the same two corpora. The tables are in `docs/EVALS.md` and re-derive from
`bench/shotgun/` ([8dfd7380](https://github.com/redhat-et/ripwire/commit/8dfd7380)).

### Changed — skill descriptions get their routing triggers and stop rules back

Six skill descriptions get back discovery triggers that had been cut to fit a 320-character per-description ceiling, and
four one-sentence stop rules return to the frontmatter. The 320 was a design number, not a client limit: Codex rejects a
description over 1,024 characters, and Claude Code caps an entry at 1,536. `test/skilldescbudgetcheck.sh` now fails only
a description over 1,024 characters and keeps the 5,400-character ceiling on the set
([#112](https://github.com/redhat-et/ripwire/pull/112)).

The quality-bar description also stops promising that `--quality-delta` "exits non-zero on new debt". Exit 2 fires only
when pre-existing code got materially worse, and new-symbol rows never gate, so a clean exit is not a verdict on new code
([#114](https://github.com/redhat-et/ripwire/pull/114)).

### Changed — the README and the docs

- **The goal.** The README states what the tool is for: one question, one complete answer, with honest limits and token
  budgets as the two stair-steps toward it. It is worded so it does not promise a hard cap the tool deliberately exceeds
  with `over_ceiling="1"` ([#88](https://github.com/redhat-et/ripwire/pull/88)).
- **The top of the page.** It leads with what a stranger can check in ten seconds. The four negations are a local badge,
  `docs/assets/no-deps.svg`, rather than images fetched from a badge service. The H1 says "Fewer Tokens", and the tagline
  under it is bold text rather than a second heading. The hero keeps the Trendshift badge; the paddle-out wave moves to
  the presentation deck ([#82](https://github.com/redhat-et/ripwire/pull/82),
  [#90](https://github.com/redhat-et/ripwire/pull/90), [#103](https://github.com/redhat-et/ripwire/pull/103),
  [#113](https://github.com/redhat-et/ripwire/pull/113), [#119](https://github.com/redhat-et/ripwire/pull/119),
  [#133](https://github.com/redhat-et/ripwire/pull/133)).
- **The banner** reads "shaped in '76, finned last month, every guess says how many it chose from, see the rip before
  you're in it", and ends on "Paddle out with a map." The lineage line claims both halves of the ledger: fifty years of
  software-engineering results, and research from last month. The 5.0% token row now carries the strict-satisfaction
  caveat beside it instead of 1,150 lines away, and `test/readmedriftcheck.sh` arm (H) holds the lineage summary's counts
  to the ledger (ca3ce335, ef6168b1, a46a514d, 61d84eef, 441e35cf, 64c81d47).
- **The task example's 4.3K figure** is described as what one run produced, not an enforced budget, since the example
  passes no budget flag. Contributed by **@PollyBot13** ([#54](https://github.com/redhat-et/ripwire/pull/54)).
- **The lineage ledger** gains three rows (tgrep, codeburn, markitdown), going from 43 to 46 repositories, with a gate
  arm requiring every copy of that count in the README to agree ([#86](https://github.com/redhat-et/ripwire/pull/86)). The
  string-kernel credits in #127 take it to 49 repositories and 70 papers.
- **The head-to-head tables say what they predate.** An italic note beside both Round 4 tables records that they were
  measured on 2026-08-08, before the performance work that ships in 0.6.0, and names two of the figures that have moved
  since: llvm-project's cold parse, on 182,555 files, from 194.1 s to 155.6 s of CPU, and `--pack-task` on a Go
  repository from 8.13 s to 5.88 s. No number in the tables changes; they still show what was measured that day
  ([#141](https://github.com/redhat-et/ripwire/pull/141)).
- **The README links `INSTALL.md` again.** The sentence under the quick-install block naming every install route was
  lost when #127's merge took a branch side that predated it, and main had not linked the page since. It goes back in
  the same place ([#141](https://github.com/redhat-et/ripwire/pull/141)).
- **Adding a language, for contributors.** `prompts/add-a-language.md` is derived from the diff of the Elixir landing
  rather than from memory. It starts by measuring the parse rate on a real corpus before any code is written, and it ends
  with the traps earlier PRs actually hit (7780e4d3, d582d0de).
- **Three places where the docs contradicted the repository** ([#131](https://github.com/redhat-et/ripwire/pull/131)):
  - `THIRD_PARTY.md` gains the MIT attribution row the vendored `tree-sitter-markdown` shipped without, and a gate arm
    now derives the required rows from the directories under `third_party/deps/`;
  - `INSTALL.md` says Hermes was run live by a contributor when it landed, and OpenClaw has not been;
  - `docs/ARCHITECTURE.md` said PageRank's power iteration is parallelized; it is single-threaded, and its fixed row
    blocks exist for determinism, not parallelism.

### Changed — CI, the gate harness and internals, with no change to output

None of this changes the binary's output.

**CI.**
- macOS legs shard four ways like every other leg, which halves the gates per macOS job. A run grows from 26 checks to
  30 ([#110](https://github.com/redhat-et/ripwire/pull/110)).
- The HEAD comparison binary is built once per job, in its own step, never inside a gate's time budget, where a parallel
  `cmake` build under contention had been killed at 900 s and again at 1200 s
  ([#118](https://github.com/redhat-et/ripwire/pull/118)).
- A declared gate budget is now a floor. Under CI's 4× budget scale, 15 of 18 declared budgets had been smaller than what
  an undeclared gate got ([#109](https://github.com/redhat-et/ripwire/pull/109)).
- Every non-Ubuntu apt source is removed before `apt-get update`, after a vendor source took down every Linux leg for the
  second time ([#99](https://github.com/redhat-et/ripwire/pull/99)).
- The advisory clang-tidy step lints a real parse. `version.h` was not generated before it ran, so the translation unit
  that includes nearly every header failed to parse and 64 diagnostics were hidden. One of them is the file-handle leak
  fixed below ([#120](https://github.com/redhat-et/ripwire/pull/120)).
- Its `bugprone-easily-swappable-parameters` options are set to reveal rather than silence: of the 209 rows the check
  reports at upstream defaults, 208 are genuine, and the two options add 18 more genuine rows while silencing none
  ([#124](https://github.com/redhat-et/ripwire/pull/124)). Eight of the flagged functions, among them the whole-file
  readers, then stop filling an out-parameter and return what they produce; the flagged sites drop from 237 to 229, and a
  36-case byte-for-byte differential is identical ([#132](https://github.com/redhat-et/ripwire/pull/132)).
- `test/*.sh` is marked `linguist-detectable=false`. The gate scripts had come within 5% of the C++ source's byte count
  (8,921,478 against 9,398,027), and a few dozen more gates would have relabelled the repository's language as Shell
  ([f2589419](https://github.com/redhat-et/ripwire/commit/f2589419)).

**The gate harness.**
- The published gate count is generated from `test/regression.sh` by `docs/gatecount_build.py`. Two lanes that each add a
  gate both write N+1, and git merges that cleanly against a loop of N+2; it collided seven times in one night
  ([#104](https://github.com/redhat-et/ripwire/pull/104)).
- `test/pargates.py` watches the checkout while gates run. It samples `git status` every 0.25 s and fails the run on any
  new file a gate leaves in the tree, naming the gates in flight, and it says the count is a floor. A transient probe file
  had been flipping stamped determinism arms by marking builds `+dirty`; the writer is fixed, and `CONTRIBUTING.md` states
  the rule ([4c10be9d](https://github.com/redhat-et/ripwire/commit/4c10be9d)).
- Gates run with `PYTHONDONTWRITEBYTECODE=1`. A gitignored `__pycache__/` had changed what the crawl counts
  (`corpus_pruned_dirs=` 3 → 4), which made a paging gate nondeterministic
  ([#122](https://github.com/redhat-et/ripwire/pull/122)).
- Gates check out commits as private shared clones rather than with `git worktree add`, so a gate killed with SIGKILL
  leaves nothing registered in the shared `.git` ([#125](https://github.com/redhat-et/ripwire/pull/125)).
- A timed-out gate is stopped whole. `test/pargates.py` used to SIGKILL only the gate's `bash`, and 5 of 6 probe processes
  outlived the timeout. Each gate now leads its own process group, which gets TERM and then KILL after a 10 s grace, and a
  Ctrl-C or SIGTERM to pargates stops every running gate the same way
  ([#129](https://github.com/redhat-et/ripwire/pull/129)).
- The installer gates clear inherited agent-home variables before setting up their fixtures, so a gate run from inside an
  agent session no longer writes into that agent's real home. Contributed by **@PollyBot13** (#55, landed as fed2e2b1 and
  d05af44e, with a5c95aa6 on top); `test/agenttablecheck.sh` got the same fix for `XDG_CONFIG_HOME` (1fdf70d3).
- Four gates that could fail for reasons outside what they check now fail only as themselves: a gate whose command died
  no longer reports a missing feature ([#94](https://github.com/redhat-et/ripwire/pull/94)); a partition arm that ties
  skips with its numbers instead of failing (cb32e0dd); a truncated pipeline no longer reads as a missing attribute
  (321ee839); and the skill-eval sweep counts directories that contain a `SKILL.md`, not every directory under
  `skills/` (5e96a6a5).
- `scripts/optremarks.py --hot` covers the 14 headers the ingest split moved work into. It had been reading 0.20% of the
  ingest translation unit ([#98](https://github.com/redhat-et/ripwire/pull/98)).

### Fixed — the macOS x86-64 release binary is built for its own architecture

`cmake/PortableFlags.cmake` picked its flags from `CMAKE_SYSTEM_PROCESSOR`, which CMake takes from the build host. The
release job builds the macOS x86-64 binary on an arm64 runner, so every x86-64 compile line got `-mcpu=apple-m1` and no
`-march`. Releases through v0.5.0 therefore most likely shipped a baseline x86-64 macOS binary; no release log shows the
flags, so that is an inference. With the Xcode pinned after v0.5.0 the same flag is a hard compiler error, so the 0.6.0
macOS x86-64 job, and with it the whole release, would have failed.

Flags now follow `CMAKE_OSX_ARCHITECTURES` when it names exactly one architecture, so the macOS x86-64 binary gets
`-march=x86-64-v3` like Linux, and a build tree naming more than one architecture stops at configure ("ripwire builds one
architecture per build tree"). The job moves to a `macos-26` runner, whose Rosetta can run x86-64-v3 code for PGO
training, with Xcode 26.6 and `MACOSX_DEPLOYMENT_TARGET=14.0` pinned; without the pin the move would silently have raised
the minimum macOS to 26. A new release step reads `minos` back off the binary. Gates: `test/portablebuildcheck.sh` arms
#2d–#2h ([#137](https://github.com/redhat-et/ripwire/pull/137)).

### Fixed — the installer names an x86-64 CPU below v3 instead of reporting a version mismatch

On a CPU below x86-64-v3, `scripts/install.sh` downloaded the binary and ran `--version` to verify it; the binary died
with SIGILL inside a pipeline whose status came from `head`, and the user was told
`release vX contains ripwire <unknown> — refusing version mismatch`, which never names the requirement.
- **Before downloading**, on x86-64 and for 0.6.0 and later, the installer reads the CPU flags (`/proc/cpuinfo` on Linux,
  the `sysctl` feature keys on an Intel Mac). Below v3 it stops, lists the missing features and points to a source build
  with `./install.sh`, which builds for the local CPU. It never blocks when the flags cannot be read, under Rosetta, for
  0.5.x and older, or with `RIPWIRE_SKIP_CPU_CHECK=1`, which covers a VM that hides flags its host still executes.
- **After downloading**, the verification run's exit code is read. Exit 132 on x86-64 names the v3 requirement and the
  source-build route, and under Rosetta suggests a native arm64 shell. Any other failure, such as a glibc loader error,
  is shown with the binary's own output. "Version mismatch" is reported only when the binary ran and printed a different
  version.
- `INSTALL.md` states the requirement and the new variable. Gate: `test/releaseinstallcheck.sh` section G, 12 arms, five
  of them red on main ([#138](https://github.com/redhat-et/ripwire/pull/138)).

### Fixed — a `std::`-qualified C++ call binds only a definition inside namespace `std`

A call written `std::X(...)` bound to the repository's lone in-repo definition named `X`, at full confidence and with no
`amb=` or `prov=` marker. On memgraph, `SafeString::move` became map row #1 with 2,107 false callers from `std::move`. In
ripwire's own graph, `std::min`, `std::max` and `std::sort` bound `fastmath` and `svector` members.

A call whose written qualifier is `std`, `::std` or a standard-library inline ABI namespace (`__1 __2 __8 __Cr __cxx11
__ndk1`, tabled with sources in `src/externalnames.h`) now keeps only candidates scoped inside `std`. Otherwise it is
counted through the existing external path, `external=`, and gets no edge. Only an exact `qualifier::name` pin exempts a
site; include-based narrowing does not. Unqualified `move(x)`, ADL, using-directives and namespace aliases behave as
before, and the rule is deliberately not generalised to other qualifiers.

| `--no-cache` | before | after |
| --- | --- | --- |
| memgraph `--callers=SafeString::move` | 2,107 | 3 |
| memgraph edges / ambiguous / external | 177,280 / 39,771 / 7,404 | 174,787 / 39,606 / 12,370 |
| ripwire (main `096e3544`) edges / ambiguous / external | 20,857 / 7,626 / 1,003 | 20,413 / 7,528 / 2,498 |
| ripwire `--callers=min` / `max` / `sort` | 131 / 67 / 7 | 5 / 14 / 2 |

`unresolved=` and map wall time are unchanged. Of the three memgraph callers left, two are `SafeString` unit tests and one
is a `std::ranges::move`, the first gap below.

**Known gaps, disclosed.**
- Nested std namespaces (`std::ranges::`, `std::chrono::`) arrive as their last segment only, which cannot be told apart
  from a user namespace.
- In ObjC++, the grammar parses `std::move( x )` as an error node plus a bare `move( x )`, so the qualifier is gone before
  resolution. The gate pins this behaviour.
- A declaration-only `namespace std { void f(); }` would still receive edges. This is not gated.
- `external=` now also counts refused `std::` calls, so it reads higher than before.

No cache or parser version moves: the change is resolution-only, and a warm run on a cache written by the old binary
equals `--no-cache`. Gate: `test/stdqualcheck.sh`, 35 checks. On the pre-fix binary 19 fail, and the 16 that pass are
controls ([#134](https://github.com/redhat-et/ripwire/pull/134)).

### Fixed — the cache evicted its own working root, and every root minted two key families

One llvm-project root needs 1.76 GB of cache, and the cache sweep holds the whole cache to 2 GB. The sweep was evicting
that root's own rich blob, so a repeated same-argv `--for` on llvm-project took 274 s of CPU; with the blob kept it takes
26 s. Eviction now pins every family of the working root, and an eviction is disclosed on stderr only when one happens.
Separately, the lean/rich cache-key builder hashed the root with a truncated FNV basis while the git-metadata families
used the real one, so every root minted two key families. There is one root key for all seven families now, which is why
blobs from older builds are clean misses (see the upgrade notes) ([#127](https://github.com/redhat-et/ripwire/pull/127)).

### Fixed — `--help-task` no longer answers "how does <word>" with a symbol

`--help-task` no longer mints a symbol from a "how does <word>…" question, and JSON keys never resolve as symbols.
Harmful recommendations fell from 13 of 25 to 0, and precision rose from 0.797 to 1.000. The skills' stop rules are gated
as present and load-bearing, the router names all 16 skills, and the MCP answer gains `no_route`
([#127](https://github.com/redhat-et/ripwire/pull/127)).

### Fixed — the confident zero: three outside reports, three causes (cache format 18)

Three reports filed on 2026-09-08 described one symptom: a number that reads as authoritative and is not. They turned out
to have three causes, so each got its own fix. A single "blind spot" attribute would have been a false claim on two of
the three.

- **Callers in a file no grammar reads gave `count="0"`, undisclosed.** Reported by **@snrmwg**
  ([#66](https://github.com/redhat-et/ripwire/issues/66)). Every graph verb's root now carries `graph_unindexed=`, folded
  from the same list the map header prints and absent at zero. ripwire also stops reporting its own cache blob as an
  unread language when that file sits inside the crawl root; that had made one query answer differently cold and warm.
- **A header-qualified selector gave `reaches="0"` for seven real callers.** Reported by **@mariadb-KyleHutchinson**
  ([#63](https://github.com/redhat-et/ripwire/issues/63)). `Foo.h:name` resolved to bodyless declarations, which carry no
  edges. A selector that resolves only to declarations now widens to the definitions they stand for, matched on scope and
  name, never on name alone. `docs/EVALS.md` had published "Blast-radius calls returning an empty radius for a symbol
  with real callers: ripwire 0". That sentence is now scoped to the corpora it measured, only one of which was C++.
- **A call inside `#if 0` was served as a live call site.** Reported by **@mariadb-KyleHutchinson**
  ([#62](https://github.com/redhat-et/ripwire/issues/62)). This is an over-count, which breaks the promise of
  `counts_floor="1"` that the true count is at least the reported one. The dead-range rule `--slice` already used moved
  to `src/preprocdead.h`, and the call graph now reads the same implementation, so the two cannot disagree about which
  lines exist. Only literal `#if 0`/`#if 1` counts; `#ifdef X` and `#if EXPR` stay live. The edge is dropped, not flagged,
  because a flagged row still counts.

`kCacheVersion` goes 17 → 18: this changes which references are extracted, so a version-17 blob would replay edges this
build does not produce. Gate: `test/blindspotcheck.sh`, written red first
([#72](https://github.com/redhat-et/ripwire/pull/72)).

### Fixed — `--for --detail` named a `max_tokens` ceiling it did not apply

On a `--for --detail` run, `--max-tokens=N` budgeted the bodies only. Signatures, the header, the legend and the symbol
table were never charged, yet the root printed `max_tokens="N"` regardless. Reported by **@YogevKr**
([#61](https://github.com/redhat-et/ripwire/issues/61)): at `--max-tokens=300` the answer cost 2,640 estimated tokens,
8.8× the ceiling it named, with no `over_ceiling`.

The fix is disclosure, not enforcement, which is what the issue asked for. Thirty small functions is the complete
answer, and trimming it to fit 300 would serve the caller less while looking more obedient. The reproduction now reads
`max_tokens="300" est_tokens="3589" over_ceiling="1"`, and `--help` states what `--max-tokens` bounds on that path and
what it does not ([#77](https://github.com/redhat-et/ripwire/pull/77)).

### Fixed — a budgeted `--for` shipped past its allowance with no ladder rung fired

`--for`'s ceiling ladder priced the header it was about to emit, but not the two pieces spliced on afterwards: the root
`over_ceiling="1"` and the legend clause that defines it, 70 bytes between them. `est_tokens` prices markup at 2.50
bytes per token while the allowance is sized at 2.714, so any bundle in that band carried 70 bytes the ladder never saw,
and a bundle the ladder had fitted within 70 bytes of the allowance shipped past it. It was latent, not new: the
pre-fix binary, on the repository's own `src/`, overshot at 14 of 111 budgets.

The post-ladder splices and the `est_tokens` fixpoint now move inside the shape the ladder prices, so a shape fits only
when the old reserve test passes **and** the finished header plus every other emitted byte fits the allowance. The first
half is the old test verbatim, so a bundle that was already inside its allowance picks the same shape: over 1,971
invocations across three trees, the flag combinations and the MCP `for` twin, 1,918 are byte-identical to the pre-fix
binary. All 53 that move were past their allowance with no rung fired — 29 now fit, and 24 land on the ladder's
disclosed last rung, which is **larger** than what shipped before, because it carries the overflow disclosure the old
path dropped. `--pack-task` and `--from-trace` keep the fixed-payload form of the ladder and are unchanged by
construction. Gate: `test/estchargecheck.sh` #11 A7 and its new 52-budget sweep, red on the parent commit
([7caf968f](https://github.com/redhat-et/ripwire/commit/7caf968f),
[3d98f84d](https://github.com/redhat-et/ripwire/commit/3d98f84d), in
[#135](https://github.com/redhat-et/ripwire/pull/135)).

### Fixed — caps that cut an answer now say so where they fire

A cap that cuts output silently makes an answer look complete. Each cap below now discloses only when it fires, so an
answer the cap did not touch is byte-identical to before. No cap value moved.

- **`--grep` and `--verify` matched lines** are cut at 512 bytes, and a 512-byte source line used to print the same
  payload as a truncated 50 KB minified line. The row now carries `line_bytes="N"`, the whole line's length. The payload
  itself stays raw file bytes, because `--and`/`--not` read the same line and `--at=` must reproduce it
  ([#100](https://github.com/redhat-et/ripwire/pull/100)).
- **Signatures** cut at 240 bytes now end in `…`, through the same truncator the other three signature cuts already use.
  This affects `--pack-signatures`, `--for`'s `<sigs>`, `<calls>` callee rows and `--lego`
  ([#100](https://github.com/redhat-et/ripwire/pull/100)).
- **A default `--for` named no ceiling.** Its 7,500-byte payload budget applies to every run, but only an explicit
  `--token-budget` was ever named. A trimmed default bundle now carries `budget_bytes="7500"` on its root, in the JSON
  dialect and in the MCP `for` verb ([#100](https://github.com/redhat-et/ripwire/pull/100)).
- **Several listings disclose their own cuts** ([#108](https://github.com/redhat-et/ripwire/pull/108)):
  - `--from-trace` discloses its name-ladder cut (`name_ladder_capped`), and `--handoff` its per-file symbol cut
    (`syms_capped`).
  - The expand and sibling lifts say when they re-ranked, and a malformed `RIPWIRE_EXPAND` or `RIPWIRE_SIBLIFT` is
    reported instead of being read silently as off.
  - The seven mention caps and three co-boost caps disclose on `--for`, `--pack-task` and MCP. Across a 195-invocation
    sweep, only four `--for` invocations changed (+106 B, where `doc_mentions_capped="1"` fired), and their ranked rows
    were identical once that attribute was stripped.
- **`--edit-check`** pages its context rows only. Flagged callers and their `sites_l=` never page, the verdict is computed
  before any window, and the root carries `est_tokens=`. A gate arm proves the verdict byte-identical at
  `--limit=1000000` ([#108](https://github.com/redhat-et/ripwire/pull/108)).

One cap was refuted rather than changed. `kSliceRdMaxIter` (64) cannot fire, because each slot of the reaching-definitions
lattice stabilises on the second round. Instrumented, the highest iteration reached was 1, over 4,528 loop fixpoints in
this tree's `src/` and on adversarial C and Python fixtures ([#100](https://github.com/redhat-et/ripwire/pull/100)).
Gate: `test/capdisclosurecheck.sh`, whose nine disclosure arms fail on the parent commit while every crossing and silence
arm passes.

### Fixed — a cut callee listing kept the lowest node ids, not the rows the question was about

A body's `<calls>` listing keeps at most sixteen callee rows. On `--for`'s bodies, `--pack-task`'s `<bodies>` and
`--from-trace`'s rank-1 body, the sixteen kept were the sixteen lowest node ids. The disclosure,
`<calls total="22" shown="14" capped="1">`, was honest about the count and silent about the choice.

A cut listing is now ordered by the query's rank, with ties broken by id:
- **The measured case.** On this repository, `--pack-task="merge scout conflict"` used to keep 13 of
  `computeMergeScout`'s 22 callees, six of them STL noise, with the merge-scout functions last. It now keeps 14, with
  those functions first.
- **`--from-trace`** ranks a callee that is itself a frame of the same trace ahead of the rest, so the edge the trace
  walked survives the cut.
- **Unchanged.** `--expand`, `--around` and `--exemplar` have no query, so they keep node-id order, byte-identical.

Gate: `test/callsrankordercheck.sh` ([#95](https://github.com/redhat-et/ripwire/pull/95)).

### Fixed — `--regex` anchors match per line, and a regex can no longer kill the run

`--regex` handed a whole file to one iterator, so `^` matched only at offset 0 and `$` only at end of file, in a verb
whose every answer is a single line. On llvm-project, `--regex='^#include'` returned 1,487 hits where a line-oriented scan
returns 289,646. Anchors now match per line, as `grep`, `rg` and editors read them. The scan is also faster on that corpus
(3.40 s against 4.48 s warm).

Disclosed narrowing: a match can no longer span lines, which `[\s\S]*` could do before. That is `rg`'s default contract
too.

- **Why not `std::regex::multiline`.** It is the obvious fix and is not used. Apple libc++ reads one byte before the
  buffer when matching at offset 0, and a 40-line standalone with no ripwire code in it faulted on 74 of this
  repository's ~130 headers.
- **A bad regex no longer ends the run.** A `std::regex_error` thrown mid-scan by catastrophic backtracking used to reach
  `std::terminate`. That file now degrades, and the scan continues.
- **`corpus_pruned_dirs=` on the `--grep` root** names the built-in directory denylist, which grep had never disclosed. On
  this repository `--grep='malloc('` served 33 hits with `complete="1"` where `rg` found 78, and the 45 missing lines
  were all under `third_party/`.

Gate: `test/grepanchorcheck.sh` ([#85](https://github.com/redhat-et/ripwire/pull/85)).

### Fixed — `--grep` no longer reads gitignored files the indexer skips

`--grep` and `--regex` also scan text files whose extension the indexer does not handle. That set was recorded before the
ignore rules were consulted, so a file that was both gitignored and of an unindexed extension was read and served. In the
measured case, that was four hits from a `.cpp.bak` that the repository's own `.gitignore` names. The crawl now consults
the ignore verdict before recording such a file, and `--no-ignore` restores it. On the reporting corpus,
`unindexed_files_scanned` went from 409 to 52. `docs/ARCHITECTURE.md` had still said `.gitignore` is not consulted; that
paragraph is corrected. Gate: `test/grepignorecheck.sh` ([#87](https://github.com/redhat-et/ripwire/pull/87)).

### Fixed — a revision reaches git only as a resolved commit (`--since`, `--merge-scout`, `--pr-context`)

Three verbs resolved a caller's revision with their own copy of the `rev-parse` probe. None of the copies held the whole
rule the shared resolver states: refuse a value that begins with `-` before git is asked, and trust only a bare 40- or
64-hex answer. All three now call `gitResolveCommitSha`. This is defence in depth, not a reachable exploit today, but two
of the gaps gave wrong answers at exit 0:

- **`--since`.** For `--since='^HEAD~3'`, `rev-parse --verify` answers `^<sha>` with status 0, so the run stamped
  `window="^HEAD~3" commits="0"` and exited 0. A date value beginning with `-` passed the date check and reached git's
  argv. Both now refuse, and `git log` receives the resolved commit instead of the caller's string
  ([#115](https://github.com/redhat-et/ripwire/pull/115)).
- **`--merge-scout`.** `--merge-scout=^HEAD~1` printed an empty `ok="0"` arm at exit 0. It now refuses with exit 1 and
  names the ref ([#116](https://github.com/redhat-et/ripwire/pull/116)).
- **`--pr-context`.** `--pr-context=--output=FILE` reached git as an argv entry and was stopped only by git's own
  `rev-parse`. ripwire now refuses it before git is asked ([#117](https://github.com/redhat-et/ripwire/pull/117)).

Valid refs give byte-identical output. The gates `test/sincecheck.sh`, `test/mergescoutcheck.sh` and
`test/prrefsafecheck.sh` log every git argv entry through a PATH shim, and each is red on the base binary.

### Fixed — a repository's hook-form `core.fsmonitor` no longer runs under ripwire's git calls

A repository can configure git to run an arbitrary command on git operations, and ripwire shells out to git during a
crawl. A hook-form `core.fsmonitor` in the crawl root would therefore have run under ripwire. It is now neutralised for
ripwire's own git children and disclosed on stderr and in `--doctor`. Gate: `test/githardencheck.sh`
([#80](https://github.com/redhat-et/ripwire/pull/80)).

### Fixed — JavaScript and TypeScript default imports resolve by what the module exports (parser version 83)

`import save from './storage.js'` bound to whichever function happened to be spelled `save`. It now binds to what
`storage.js` exports as default, with `prov="import"`:
- default declarations, local identifier defaults and `export { local as default }` are all covered;
- the existing lexical-shadow and module-ambiguity handling is reused;
- an anonymous default expression stays unresolved;
- conflicting default exports cannot pick a function just because it is the only function-shaped symbol.

Contributed by **@PollyBot13** ([#56](https://github.com/redhat-et/ripwire/pull/56)). The gate covers TS, TSX, MTS, CTS,
JS, JSX, MJS and CJS, with a same-spelled decoy in each arm. The version is 83 because #57 had already spent 82; the
record shape is unchanged.

### Fixed — an 8-bit counter overflow in four vendored grammar scanners (parser version 87)

Markdown's external scanner added a `size_t` column count into a `uint8_t`. One Rails guide, whose pipe-table row is
padded to 301 columns, made the ASan build exit 134 on that file alone. On the plain build the damage was a wrong parse at
exit 0, and only at widths just past a wrap. At 256 or 257 columns:
- an indented `# Buried` became a heading;
- a fence of that many marks never opened, so its body leaked out as live markdown.

Markdown's counters now saturate at 255, which every threshold they are compared against reads the same way as a larger
true value. The Rust, Lua and C# scanners take an explicit cast instead. Their counters close a token by matching the
opening count, and at 255, 256, 257 and 300 the output recovered identically in all three.

Output is byte-identical over 3,538 real `.md`/`.rs`/`.lua`/`.cs` files, but a constructed 256-column line does move, so
the parser version moves too. Gate: `test/vendorpatchcheck.sh` arm I, with every width pinned at exactly 256
([#102](https://github.com/redhat-et/ripwire/pull/102)).

### Fixed — the vendored YAML scanner's failure status survives an unsigned `char` (parser version 92)

tree-sitter-yaml returns its scan status through four functions declared plain `char`, and one of the values it returns
is `SCN_FAIL`, `#define`d `(-1)`. **`char` is unsigned on aarch64 Linux**, which is where the `linux-arm64` release
asset is built, so there the `-1` came back as 255, with two consequences:

- **A silent parse difference, in every build type the release ships.** The three `case SCN_FAIL:` labels never matched
  255, so a malformed `%`-escape in a tag or a `%TAG` prefix was swallowed into the token instead of ending it.
  `a: !<tag:x%zz> b` parses as `ERROR` under a signed `char` and as a clean tagged scalar under an unsigned one — the
  same bytes, a different tree, decided by the CPU the binary was built for. At the product level, a ripwire built
  `-funsigned-char` minted a key the signed build does not.
- **A sanitizer abort on ordinary YAML.** `scn_pln_cnt` reaches its `return SCN_FAIL;` on a plain `key: value` line, so
  G1's implicit-conversion check stops the run there. All three `test/yamlfix` files abort, which means an aarch64 Linux
  ASan build dies on the first YAML file it crawls.

CI could not see either symptom: both sanitizer legs have a signed `char`, and there is no aarch64 Linux leg.

The fix backports upstream's own change, **a1c4812a**, which no tagged release of the grammar contains yet: the three
`#define`s become an enum whose negative member forces a signed type, and the four functions return it. Its added and
removed lines are identical to upstream's, with only the vendor-patch markers ours. A cast was rejected because it
silences the sanitizer while still never matching `case SCN_FAIL:`.

Every `char` in the grammar sources was audited, not only the two functions the report named, and the rest of the family
was swept: a detector for negative returns through plain `char`, run over all 18 vendored `scanner.c` files plus the
Kotlin scanner, finds YAML only. On a signed-`char` host the default map, `--json` and `--skipped` are byte-identical
before and after, over the repository root, five fixture directories and the generated YAML corpora. Gate:
`test/vendorpatchcheck.sh` arm K builds the vendored grammar twice, once `-fsigned-char` and once `-funsigned-char`,
and asserts identical trees for ten fixtures — one per audited site, plus a control that reaches no failure path — and
that the unsigned build parses all of them and every `test/yamlfix` file clean under the implicit-conversion sanitizer.
On unpatched main five of the ten trees differ and twelve inputs abort under the sanitizer — nine fixtures, only the
control clean, and all three `test/yamlfix` files. `kParserVer` goes 91 → 92, because the extraction of real input changes
wherever `char` is unsigned and a cache blob cannot tell the two architectures apart; `kCacheVersion` stays 20
([#140](https://github.com/redhat-et/ripwire/pull/140)).

### Fixed — `--help=all` said `--situ` self-budgets through `--token-budget`, which `--situ` refuses

The `--top-k` paragraph listed `--situ` among the verbs that self-budget via `--token-budget`. Passing the two together
exits 1, and the refusal's own roster of honouring verbs does not name `--situ`; `src/situ.h` reads neither the token
budget, the max-tokens value nor `--top-k`. The sentence sent an agent to a flag that fails. Only `--situ` is removed
from it; `--pack-task`, `--from-trace` and `--run-trace` are in the refusal's roster and keep their place.
`docs/COMMANDS.md` mirrors the sentence and is generated, so it was regenerated through the repository's own recipe;
that also drops `--top-k` from `--situ`'s derived "Shaped by" list, which is the true statement
([#140](https://github.com/redhat-et/ripwire/pull/140)).

### Fixed — `CLAUDE_CONFIG_DIR` is respected

Every path that located Claude Code's config directory read `$HOME/.claude` and ignored `CLAUDE_CONFIG_DIR`, the variable
Claude Code itself honours. The installers, `skills/install.sh --hook`, `--scan-skills`, `ripwire wrap`'s detection and
`--doctor --agent=claude` now follow `${CLAUDE_CONFIG_DIR:-~/.claude}`, the pattern `CODEX_HOME`, `AGENTS_HOME` and
`HERMES_HOME` already use. Unset behaves as before, and set-but-empty counts as unset.

Contributed by **@s0undt3ch** ([#101](https://github.com/redhat-et/ripwire/pull/101)), who found six sites. Review found a
seventh, in `--doctor`: with the variable set, the installer deployed into the relocated home and reported success, and
`--doctor --agent=claude` then reported `claude-skills ok="0"` and told the user to re-run the installer that had just
worked. `test/claudeconfigdircheck.sh` is a census over executable code rather than a list of known sites, so an eighth
site would go red on the commit that adds it ([#105](https://github.com/redhat-et/ripwire/pull/105)).

### Fixed — `--edit-check`'s tests-to-run receipt gives the answer `--affected` gives

The receipt walked its own path instead of the one `--affected` serves, so the same change could get two different
answers depending on which verb was asked. It now routes through `--affected`'s answer, emits the same evidence tiers and
carries `order="evidence"`. `--pack-task` keeps its deliberately different row set, with the reason stated in the source.
The divergence surfaced while digging into two reports by **@YogevKr**
([#59](https://github.com/redhat-et/ripwire/issues/59), [#60](https://github.com/redhat-et/ripwire/issues/60)). This
change closes neither report; both remain open.

In the same change, a published capture whose `--at=` seed had drifted onto a different function (right shape, wrong
symbol, exit 0) is regenerated. Captures now derive each seed from source, and a gate arm requires every published seed
to resolve to the symbol its demo is about ([#89](https://github.com/redhat-et/ripwire/pull/89)).

### Fixed — two defects clang-tidy found once it could parse the tree

- **A file-handle leak.** `readWholeFile` skipped `fclose` on a short read. The reader is shared by the git-config probe,
  which runs at startup and per request under `--mcp`, and by the notebook reader.
- **Unchecked calibration variables.** The `RIPWIRE_*` ranking calibration variables were read with `atof`/`atoi`. `nan`
  passed through the clamp into every BM25 score, `8x` read as 8, and `notanumber` read as 0 and was clamped to the floor:
  three rankings nobody configured, each at exit 0. A value must now parse as one whole finite token; otherwise the
  default is used and one stderr line names the variable.

Both fixes are in [#120](https://github.com/redhat-et/ripwire/pull/120).

### Fixed — a call the resolver declined to guess at no longer reads as "no caller exists" (`declined=`, `declined_calls=`)

Tier 3 of the name-based resolver refuses a call whose candidates are two or more same-language definitions, none
in the caller's file or directory, and that no qualifier or receiver rule pins. That rule stands: guessing among
cross-directory same-named definitions is how false edges are born. But the refusal was silent — no edge, no `amb=`,
and `ambiguous=`/`unresolved=`/`external=` unmoved — so `--callers` on either definition answered `count="0"` about
a call the resolver had seen, and nothing said how often. At merge, on the `--no-cache` default map, it was 22.2% of
memgraph's call references (65,516 of 295,086) and 4.6% of ripwire's own (6,263 of 135,449); on the branch base it was
8.6% of retrofit's and 0.15% of llvm `lib/Support`'s.

The decline is now counted and shown, and no edge moves:

- The map header carries `declined=N` (JSON `"declined":N`), absent at zero; its legend entry appears only on a map
  that carries the attribute.
- `--callers`, `--callees` and `--impact` carry `declined_calls="K"` in XML, `--json` and `--format=columnar`, as do
  their MCP twins `find_referencing_symbols`, `find_symbol` and `impact`: declined calls that could have meant the
  selector's definitions (callers), that those definitions make (callees), or that could reach SYM or its radius
  (impact), counted once per call. Absent at zero, defined in the legend when present.
- `--pin-census` ends with a conservation line, `# dispositions calls=N …`: every call reference lands in exactly one
  of bound, self, external, unresolved, undefined, other_root, qualified_external, declined, file_scope or
  unaccounted, and `calls=` is re-derived from the references. A resolver exit that names no bucket lands in
  `unaccounted` and raises a degrade alert on plain builds, so the next silent `continue` is caught, not shipped.

Measured on the `--no-cache` default map, the base binary against the change. memgraph and ripwire were re-measured at
merge, on a tree that already carries the `std::`-qualified call guard; retrofit and llvm `lib/Support` are from the
branch base (5c808487), where each map's byte diff is exactly the new `declined=N` plus one legend comment (+245 to
+248 B) and `edges=`, `ambiguous=`, `unresolved=`, `locality_pinned=` and `external=` are identical on every corpus. At
merge, `edges=`, `ambiguous=`, `unresolved=` and `locality_pinned=` are unchanged everywhere.

| corpus | call references | `declined=` | share |
| --- | ---: | ---: | ---: |
| memgraph (at merge) | 295,086 | 65,516 | 22.2% |
| ripwire (at merge) | 135,449 | 6,263 | 4.6% |
| retrofit (branch base) | 29,983 | 2,587 | 8.6% |
| llvm `lib/Support` (branch base) | 20,425 | 30 | 0.15% |

memgraph peak RSS 621 → 630 MB (+1.5%, the candidate index behind `declined_calls=`); wall time unchanged (0.76 s →
0.75 s). A cache written by the pre-change binary reads back warm to output byte-identical with `--no-cache`, so no
cache or parser version moves. Gate `test/declinecheck.sh` covers 17 languages and was red on the pre-change binary
(50 FAIL / 38 PASS as first committed); `test/resolverhonestycheck.sh` F5 now requires the decline to be disclosed,
not merely edge-free.

The at-merge rows are lower than the branch base's (66,015 of memgraph's calls, 7,279 of 134,739 on ripwire's
5c808487 tree) because the `std::`-qualified call guard refuses some `std::` sites before they reach tier 3. The
`# dispositions` line balances with `unaccounted=0` on both; the guard's refusals count as `external`, and
`test/declinecheck.sh` runs the guard's own fixture (`test/stdqualfix`) to keep them there.

### Fixed — the super-linear warm floor under every graph-building verb (`--grep`, `--callers`, the map)

On llvm-project (182,555 files, warm cache) a `--grep` for an absent literal took 159.7 s, `--callers=main`
152.9 s and the default map 248 s, while the same crawl + cache load + model build without the graph took
3.8 s. Profiled to one operation: the resolver rebuilt a receiver type's inheritance cone (two BFS walks
with quadratic dedup) on every still-ambiguous receiver-typed call — 86,667 rebuilds for 2,984 distinct
types, 143 s of the 154 s run. `ChaConeMemo` (`src/graph.h`) computes each cone once with the identical
walk and cap; warm `--grep` is now 9.2 s, `--callers` 8.6 s, the map 10 s, and default maps are byte-identical
before and after on go and llvm. Gate `test/chaconecheck.sh`; the phase tables are in `bench/PROFILE.md`
and the evidence chain in `docs/EVALS.md` (2026-09-09).

### Fixed — a Ruby receiver's lazy bit is order-blind, and a deep constant chain no longer overflows the stack (parser version 86)

Two defects in the receiver round (parser version 84, the entry below; its branch numbered it 83), both found by
review after the merge and both reproduced before they were fixed. Contributed by **@andriytyurnikov**
([#78](https://github.com/redhat-et/ripwire/pull/78), landed in [#91](https://github.com/redhat-et/ripwire/pull/91)).

**A load-time site below a lazy one was lost.** The receiver dedupe keeps one `Include` per (file, innermost
open, written name), and the first occurrence in source order carried the lazy bit. A `Helper.fmt` inside a
method written *above* the same `Helper.fmt` at class-body level therefore left the directive lazy; resolve.h's
pair rule — one load-time directive makes the pair load-time — never saw the load-time site, and the
structure dropped a real dependency. Two files that differ only in the order of those two lines read `ccd="3"
shape="vertical"` with a god file one way and `ccd="2" shape="horizontal" lazy_edges="1"` the other. The lazy
bit is now the AND over every occurrence: the first site still carries the byte, and a later load-time site
clears the bit on the retained record (`captureIncludes`, `seenReceivers` now maps to the record's index).

**A 5000-segment chain killed the run.** `rubyIsConstantChain` recursed once per segment of a left-nested
`scope_resolution`, and the depth bound in `captureIncludes` sits *after* `directiveTargetOf`, so a generated
`A::A::…::A.call` of 5 000 segments overflowed a parse worker's stack — SIGBUS, exit 138, no output, measured
on macOS; 2 000 survived. The check is a loop now. Nothing else on the path recurses per segment: the walk is
an explicit stack, the resolver splits the text.

**`--help` said `lazy="1"` was TS/JS only.** It has read Ruby closures and autoloads since parser version 84;
the `--impact` line now says so, and `docs/COMMANDS.md` is regenerated from it.

Measured (`--deps --limit=100000`, parser version 83 → 86, the same four corpora as the receiver round; the
gems are Rails 7.2.3.2, the apps are the same two):

| corpus | ccd | nccd | shape | lazy_edges | bytes |
| --- | --- | --- | --- | --- | --- |
| activesupport `lib/` (282) | 15 299 → 15 299 | 7.59 → 7.59 | tangled | 945 → 935 | 75 970 → 75 988 |
| activerecord `lib/` (395) | 4 088 → 4 325 | 1.36 → 1.44 | vertical | 1 026 → 1 023 | 114 745 → 114 763 |
| a Rails app, 4683 files / 3532 `.rb` | 13 170 → 13 172 | 0.32 → 0.32 | horizontal | 5 632 → 5 630 | 750 913 → 750 915 |
| a second Rails app, 1967 / 1895 `.rb` | 6 382 → 6 382 | 0.34 → 0.34 | horizontal | 1 830 → 1 830 | 363 733 → 363 750 |

Read together: the pairs that flip are the ones written lazy-first and load-time-second in one body — ten on
activesupport, three on activerecord, two on the first app, none on the second — and on activerecord three of
them sit on a spine (ccd +237). No shape moves. Wall time unchanged. Cold == warm on activerecord and the
first app; two `--no-cache` runs identical on all four.

**Record shape unchanged**, so cache format 18 holds; the extraction identity moved (a cached lazy bit could be
wrong), so cached Ruby files re-parse once. `kIngestParserVerMirror` moves in the same diff. The version is 86,
not 85: main spent 85 on the plain-text prose tier before this landed, and a collision is resolved by
re-bumping over the tip, never by keeping the fork's value.

Gate: `test/rubyrecvcheck.sh` gains `lib/app/eager_after_lazy.rb` (18 fixture files; ccd 20 → 22, helper.rb
afferent 2 → 3, a row arm with no `lazy_edges=`, the `--impact=Helper` importer tier) and a deep-chain arm that
generates a 150 000-segment receiver at gate time and expects one directive and exit 0. Written red first: six
arms fail against the pre-fix binary — the eager-after-lazy importer reads `lazy="1"`, health reads
`ccd="21" lazy_edges="10"`, the deep chain exits 138. ASan/UBSan clean on both fixtures, the deep chain, and
the cache round-trip. Re-pins with reasons in-file: `qschemetrip.hash` (parser mirror), `printf_parity.manifest`
(`help` and `impact` bytes — the `--impact` import-tier legend moved with the `--help` line).

### Added — a Ruby constant receiver is a dependency (parser version 84)

Round two of the Ruby constant work. Parser version 82 gave the declarative spellings — `class X < Base`,
include/extend/prepend, `autoload :Name`. This round adds the one a Zeitwerk application actually depends
through: a **constant receiver** — `User.find`, `App::Mailer.deliver`, `Struct.new`. The autoloader loads
lib/app/user.rb on that first reference, and nothing else in the file says so.

Contributed by **@andriytyurnikov** ([#65](https://github.com/redhat-et/ripwire/pull/65)). The round was measured and
gated on its branch as parser version 83 and shipped as 84, because the JavaScript and TypeScript default-import fix had
taken 83 first; the version numbers in this entry's tables and gate notes are the branch's.

Four decisions, each stated in `test/rubyrecvcheck.sh`'s header rather than asked:

1. **What counts.** A `call` whose receiver is a constant or a constant chain (`A::B::C`, `::A::B`), spelled
   as written. A chain whose head is not a constant — `repo::Finder`, `self.class`, an identifier, an ivar —
   is nothing (`rubyIsConstantChain`; the round-one reader accepts any scope-resolution text and is right
   for the positions the grammar already restricts to constants, a receiver is not one). A constant used as an
   **argument** (`raise Errors::Boom`, `validates_with Foo`) or as a rescue class is **not** a receiver: a
   disclosed floor of this round.
2. **Dedupe at extraction**, per (file, innermost class/module open, written name). Zeitwerk loads a
   constant once per process, on its first reference; the second `User.find` in the same body is not a new
   dependency. The first occurrence in source order carries the byte and therefore the lazy bit. The nesting
   is in the key: `User` under `module Admin` and `User` under the enclosing module may be two constants, and
   the fixture has that file. `Time` and `::Time` are two spellings, two directives. The declarative shapes
   stay one directive per occurrence — each is a statement. Measured with the Prism prototype: distinct
   (file, nesting, name) is 61 % of raw receiver sites on activesupport, 67 % on activerecord, 56 % and 53 %
   on the two Rails apps.
3. **Lazy inside a closure.** A receiver inside a `method`, `singleton_method`, `lambda`, `block` or `do_block`
   is `lazy="1"` — it runs when and if that closure runs, the parser-72 TS/JS function-body rule on Ruby's
   own closure kinds (`kRubyClosureContainers`). A receiver at class-body or file level runs at load. A
   `do`-block passed to a class-level macro (`included do`, `after_commit do`) is lazy under this rule even
   when the callee runs it at load: the tool cannot see the callee, and a block is a closure it may or may
   not run. `--impact`'s importer tier says `lazy="1"` only when every edge from that importer is lazy.
4. **Resolution is round one's, unchanged.** Module.nesting innermost-first then Object, `::` absolute,
   wrapper opens define nothing, genuine reopenings fan out, a same-file reference is shown and dropped as a
   self-include. An out-of-tree receiver (`Time`, `Struct`, `Object`) is a shown `<inc t=>` row with no edge —
   the posture every Python `import os` row already has.

**The Ruby walk now descends every node.** A receiver is an expression — under an assignment, an argument
list, a lambda, a binary, a string interpolation — so the statement-level container allowlist Ruby had through
parser version 82 (19 kinds) would have needed ~40 and every kind it missed would have been a receiver
silently dropped, a floor the tool could not disclose because it could not see it. The full descent is the
cost the reference pass already pays once per Ruby file. The depth bound (256) still degrades loudly.
`--deps --limit=100000 --no-cache` wall time on a 4683-file Rails app: 1.04 s → 0.92 s (noise); on
activerecord `lib/` 0.21 s → 0.18 s.

**Structure versus use — the decision this round adds, and it reaches TS/JS too.** With receivers counted
like every other edge, a Ruby codebase is one strongly-connected core at the file level: models name each
other, base classes name their subclasses through registries, and the cone of a controller is most of the
application. Measured before the cut, `--deps --limit=100000` on a 4683-file Rails app went ccd
12 740 → 1 407 232, nccd 0.31 → 33.74, and every Ruby corpus read `shape="tangled"`. That is a true fact
about runtime references and a useless one for a lens: a reading that is the same everywhere is not a
reading. So a **lazy edge** — a (from, to) pair every one of whose directives is written inside a closure
(a Ruby method/lambda/block, a TS/JS function body) or is a Ruby `autoload` — is a **use**, not a load-time
dependency, and the two views now say different things on purpose:

- **Use** — `--impact`'s importer tier (`lazy="1"`), the file's own `<inc t=>` rows, call-resolution
  narrowing, `--expand`'s siblings and `--cochange`'s static-coupling test all keep every edge. "Who uses
  `User`?" is answered by all 197 files that call it.
- **Structure** — `--deps`, `--arch` and `--report` measure the load-time graph: `afferent=`, `instab=`,
  `transitive=`, godfiles, stabledeps, cycles, ccd/acd/nccd and `shape=` leave lazy pairs out
  (`graph.h::resolveStructuralIncludeAdj`; one load-time directive makes the whole pair load-time, the
  parser-72 `recordLazyPair` rule). The cut is disclosed where it is made: `<health lazy_edges=N>` counts the
  distinct pairs left out and a file row carries `lazy_edges=N` for its own, both absent when 0 — so a corpus
  with no lazy directive is byte-identical to before. A lazy edge is not an unresolved one: the unresolved
  row has neither `lazy_edges=` nor an importer; the lazy row has both.

This changes one TS/JS number: a `require()` inside a function body (parser version 72) was already
`lazy="1"` in the importer tier and is now also out of `--deps`' structure. On this repo's own fixtures no
gate pinned it inside the cone. `--deps --limit=100000`, parser version 82 → 83 (`files=` is the listing's
own denominator: files with a row; `<godfiles total=>` the uncapped load-time importee count):

| corpus | files= | ccd | acd | nccd | shape | importees | lazy_edges | `--deps` bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| activesupport 7.2.3.2 `lib/` (282) | 206 → 241 | 10 450 → 15 299 | 37.2 → 54.4 | 5.19 → 7.59 | tangled → tangled | 241 → 201 | 945 | 55 483 → 75 970 |
| activerecord 7.2.3.2 `lib/` (395) | 300 → 368 | 2 714 → 4 088 | 6.9 → 10.4 | 0.90 → 1.36 | horizontal → vertical | 385 → 310 | 1 026 | 71 474 → 114 745 |
| a Rails app, 4683 files / 3532 `.rb` | 2 296 → 3 245 | 12 740 → 13 170 | 3.3 → 3.4 | 0.31 → 0.32 | horizontal → horizontal | 385 → 414 | 5 632 | 378 473 → 750 913 |
| a second Rails app, 1957 files / 1895 `.rb` | 1 072 → 1 455 | 6 289 → 6 382 | 3.3 → 3.4 | 0.33 → 0.34 | horizontal → horizontal | 189 → 197 | 1 830 | 173 606 → 363 733 |

Read the two halves together: on the Rails apps the structure barely moves (class-body receivers are few)
while `lazy_edges` says how large the runtime layer the structure leaves out is — 5 632 pairs on the first
app, where the importer tier now names them all. On the gems the structure grows because a gem does depend at
load time through class-body receivers (`ActiveSupport.on_load`, `Concern`), and importees FALL (241 → 201,
385 → 310): a file whose only importers call it from inside methods is no longer a god file, it is a file
`--impact` lists. The uncapped `<inc t=>` listing on activerecord carries 2 228 rows over 1 188 distinct
targets, the most frequent being `ActiveSupport::Concern` (57, out of tree, shown, no edge).

**Default map.** Byte-identical on a Ruby-free corpus (this repo's `src/`, modulo version stamps). On Ruby
corpora the ranking moves a little (activesupport `est_tokens` 15 745 → 15 688, `pr_iters` 56 → 54) because
include edges narrow ambiguous call resolution and there are more of them; no `id=` row moves — `scope` is
still the immediate enclosing name.

**Record shape unchanged.** A receiver is an `Include` with `isSymbolic` and `byte` (both parser version 82),
so cache format 17 holds and only the extraction identity moved: cached Ruby files re-parse once. Cold and
warm caches agree on activerecord and the 4683-file app (gated on the fixture).

**Round one's gate moved two arms, honestly.** `test/rubyconstfix`'s `dynamic.rb` (`include
Object.const_get(:Trackable)`) now has a row — the `Object` receiver, not the include, and the arm asserts
exactly that; `point.rb` (`Point = Struct.new`) has a `Struct` row with `afferent="0"` — the alias is still
not indexed, the floor note stands.

Gate: `test/rubyrecvcheck.sh` + `test/rubyrecvfix/` (17 files — dedupe across seven receiver sites, two
nestings of one name in one file, four laziness levels, lexical versus absolute, the Object-level fallback
for a module-less script, a self-include, five non-constant receiver shapes, the Struct alias floor, the
argument/rescue floor, a same-basename decoy, the structure-versus-use cut — ccd 20 over 17 files with
`lazy_edges="9"`, App::User with four lazy importers and no `--deps` row, a lazy row told from an unresolved
one — root-spelling parity, determinism, warm == cold, well-formedness). Written red first: 14 arms fail
against the parser-version-82 binary and 7 more against the receiver build before the cut; every mutation
control and floor arm passes there. 558 → 559 gate scripts.

### Added — Ruby constant references are dependencies (parser version 82, cache format 17)

A Zeitwerk application spells almost none of its dependencies with `require`: a controller depends on a
model by **naming the constant**, and a Rails gem declares half its structure with `autoload :Name`. Parser
version 81 gave Ruby `require`/`require_relative`/`load`; this round adds the constant spellings, so the
file graph `--deps`/`--arch`/`--impact`/`--cochange` see is the one Ruby actually has:

| Spelling | Directive | Resolution |
| --- | --- | --- |
| `class X < Base` | the superclass constant | index, lexical rule (below) |
| `include M` / `extend M` / `prepend M` | one directive per constant argument | index, lexical rule |
| `autoload :Name` (ActiveSupport::Autoload) | the constant | index, lexical rule; `isLazy` |
| `autoload :Name, "path"` (Kernel#autoload) | the **path**, as one directive — never the constant beside it | the load-path rule, as a `require`; `isLazy` |

**The rule is Ruby's own, not a convention.** Every `class`/`module` open in the corpus is recorded with its
name as written (`Base`, `App::Audited`, `::Top`) and its byte span (`ConstOpen`, `src/model.h`). An open's
nesting is its enclosing opens by span containment — the same containment that attributes a call to its
def — and its fully-qualified constant follows: `::X` is absolute; a compact `class A::B` inside `module X`
names `X::A::B` when the tree opens `X::A` anywhere, else `::A::B` (Module.nesting first, then Object). A
reference `Name::Sub` at nesting `[A, A::B]` is looked up as `A::B::Name::Sub`, `A::Name::Sub`,
`Name::Sub`; first hit wins. A superclass carries its class's own start byte, so it resolves in the
**enclosing** scope, exactly as Ruby evaluates it. Constant targets are never probed as paths
(`Include::isSymbolic`): `require "Foo"` is legal Ruby, and on a case-insensitive filesystem a path probe for
`Trackable` lands on `lib/trackable.rb` — the fixture's decoy pins it.

**Two kinds of "defined in many files", told apart structurally.** `module App` is opened by every file under
`lib/app/`. An open whose body holds nested opens and **nothing else** is a *namespace wrapper*: it nests,
but it defines nothing of `App` and is not a definer in the index (`ConstOpen::namespaceOnly`, read off the
body's children — comments are extras and are skipped; an EMPTY open defines). A reopening **with** a body — a
monkey patch, a decorator, a `core_ext` — is a real second definer, and a reference then edges to **every**
definer: change any of them and the constant changes, which is what `--deps` measures. That is multiplicity
(every answer is right), deliberately distinct from the specifier ambiguity every other Step-A degrades on
(`require "shared"` answered by two files: exactly one is right, and this tool cannot tell which). Only the
latter resolves to nothing. Measured with a Prism prototype of the same lexical rule on a 3532-file Rails
app: 124 constants were "multiply defined" by opens, **5** by bodies, and treating wrappers as definers was
what made 246 superclass references ambiguous there (0 after).

**Measured** (`--deps --limit=100000 --no-cache`, both binaries from this tree; `importees` is the
uncapped `<godfiles total=>` — files with at least one incoming edge — and `edge-bearing` is `<deps files=>`):

| corpus | ccd | acd | nccd | shape | importees | edge-bearing files |
| --- | --- | --- | --- | --- | --- | --- |
| activesupport 7.2.3.2 `lib/` (282 files) | 3658 → 10450 | 13.0 → 37.2 | 1.82 → 5.19 | vertical → tangled | 194 → 241 | 194 → 206 |
| activerecord 7.2.3.2 `lib/` (395) | 947 → 2714 | 2.4 → 6.9 | 0.31 → 0.90 | horizontal | 214 → 385 | 108 → 300 |
| a Rails app, 4683 files / 3532 `.rb` | 5638 → 12740 | 1.5 → 3.3 | 0.14 → 0.31 | horizontal | 103 → 385 | 1154 → 2296 |
| a second Rails app, 1957 / 1895 `.rb` | 5483 → 6258 | 2.9 → 3.3 | 0.29 → 0.33 | horizontal | 80 → 189 | 619 → 1066 |

ActiveSupport turning `tangled` is `core_ext`: `String` is reopened with a body in 15 files, so every
`< String` and `include`-of-a-patched-module depends on all of them — true, and the point of `core_ext`.
The **default map** is byte-identical to the pre-change binary on four Ruby-free corpora (this repository
and three others) and moves on Ruby ones only through the call graph's same-include tier: ActiveSupport
`edges=` 3729 → 3715, `ambiguous=` 409 → 406; ActiveRecord 8397 → 8298, 1284 → 1105.

**Floors, each pinned by an arm of `test/rubyconstcheck.sh`.** The ancestor half of Ruby's lookup (a
constant inherited from a superclass or an included module) is not walked. `Point = Struct.new(…)` is an
alias, not an open — `queries/ruby/tags.scm` skips CamelCase assignments and so does the index. `include
Object.const_get(:X)`, `autoload :X, some_path`, `require some_variable` capture nothing. Constant
**receivers** (`User.find`) are not this round: they are the bulk of a Zeitwerk app's edges and move every
Ruby denominator again, so they land as their own change with their own table.

**Record shape.** `Include` gains `isSymbolic` and `byte`; the per-file cache record gains the `ConstOpen`
family after `routeUses` — `kCacheVersion` 16 → 17 (a format change; the parser-version bump re-ingests
every cache anyway, so no extra cost). `Symbol::scope` stays the *immediate* enclosing name by design; the
fully-qualified constant lives only where it is needed. `--impact`'s importer tier reports `lazy="1"` for
an `autoload`, as it does for a function-body `require()`.

**Expired floor.** `test/rubyrequirecheck.sh` arm 3(c) pinned "`autoload :Late, "lib/helper"` is not
captured" since parser version 81. It now is (12 directives on that fixture, not 11; `lib/helper.rb`
afferent 2 → 3), and the arm was inverted rather than deleted so the expiry is on the record.

Gate: `test/rubyconstcheck.sh` + `test/rubyconstfix/` (30 files — nesting, compact and absolute names,
lexical shadowing, the three mixin verbs, `autoload` plain / in `eager_autoload do` / in `autoload_under
do` / with a path, a monkey-patched in-tree class, a patched core class, a namespace with 23 wrapper opens
and one real body, a wrapper-only reopen, out-of-tree constants, a same-basename decoy, a same-file
reference, two sites sharing an innermost open but not a nesting chain — `module A; module B` versus the
compact `module A::B`, where only the first can see `A::Helper` — root-spelling parity, determinism,
warm == cold, well-formedness). The chain pair was added after review: the resolver's memo was keyed on
the innermost open alone, so whichever site was visited first fixed the other's answer, and cold and warm
caches visit the sites in different orders — the fixture gave the helper two importers cold and none warm.
The memo is now keyed on the whole chain. Written red first: 24 arms
fail against the parser-version-81 binary, every mutation-control and floor arm passes there. 557 → 558
gate scripts.

Contributed by **@andriytyurnikov** ([#57](https://github.com/redhat-et/ripwire/pull/57)).

## [0.5.0] — 2026-09-07

**The first release carrying outside contributions.** Three people who do not work on this project
wrote fixes that are in this binary — Michael Freeman, PollyBot13 and Andriy Tyurnikov — and three
more found things it got wrong: Cort Fritz, stalep and Jan Mangs. All six are named below, beside
what they found. That is what this number is for.

### Added — Elixir, as a first-class indexed language

A vendored tree-sitter grammar and call-graph extraction, with protocol implementations indexed as
their own definitions. Contributed by **Michael Freeman**
([#43](https://github.com/redhat-et/ripwire/pull/43)), rebased onto main's tip — the extraction
identity is 78, not the 83 the fork carried — and extended with two gaps the fork could not see from
where it sat. The import edges are described in their own section below.

### Added — `<recent>` answers "what changed", not "what churns"

`--rank-by=churn-decay` emits a file-level `<recent>` block ordered by newest commit first rather
than by heaviest weight. A question about what changed recently was being answered with what changes
most often, which is a different question. The MCP instructions carry the deferral hint.

### Added — tests-to-run rows in evidence order

A changed test file comes first, then its stem partner, then graph hops, and each row says *why* it
is there. A test file that is itself in the diff is an obligation on its own evidence. The silent
zero on that surface is fixed: an empty result now says so.

### Fixed — named JavaScript and TypeScript import aliases

`import { a as b }` resolved to the wrong symbol, and the refusal path deleted edges that were
correct. Contributed by **PollyBot13**
([#45](https://github.com/redhat-et/ripwire/pull/45)). The refusal now reports which of the three
things it knew rather than collapsing them into one message.

### Fixed — five languages were invisible to the unanalyzed-language disclosure

`filesByLang` was sized with a hardcoded `16` while the `Lang` enum had grown to 21, so TOML, YAML,
PHP, Lua and Elixir were dropped from the count silently — and two of them were named in
`kUnanalyzedLangs`, meaning the lens promised to declare them and could not. Found by **Cort Fritz**
on his own fork. The array is now sized by `kLangCount`, with a `static_assert` that fails the build
if the enum outgrows it again. **A disclosure surface that under-reports is worse than one that is
absent**, which is why this is the fix in this release that mattered most.

### Fixed — the MCP tool schema a strict client refuses

One tool declared a union type that stricter MCP clients reject outright, taking the whole server
down with it ([#48](https://github.com/redhat-et/ripwire/issues/48), reported by **stalep** against
opencode with `@ai-sdk/google-vertex`). Gated by `test/mcpstrictschemacheck.sh`, written red against
the binary that had the bug.

### Fixed — twenty first-run defects a stranger hits and a maintainer never does

`PATH` not printed on install, a borrowed query in the quickstart, shallow clones mishandled, two
inverted `--doctor` verdicts, lock-file litter, sidecars that did not say what they dropped, an empty
map that read as an answer, and an upgrade path that left a binary which could not run and reported
success. Found by auditing the install as somebody who had never run it.

### Changed — the README leads with the proof

The ten-moments token table and the graphs now sit under the install block: **300 words to the first
piece of evidence instead of 1,009**. Twenty-six prose blocks moved behind `<details>`, each with a
summary carrying its own number, so the page makes the same case whether or not anything is clicked.
Nothing was removed — the full read is longer than before, because the summaries are additive.

### Changed — Graft folded into the lineage ledger as the 42nd repository

A registered head-to-head against Graft 0.17.0 ran, its losses were converted into code, and it was
re-run: 14 of 30, with the placebo arm at 13-12-5. **The stop condition fired, so no ranking claim is
published from that round.** What shipped is the two fixes it produced — tests-to-run in evidence
order, and `<recent>`.

### Changed — CI shards its gate suite across runners

Each release leg's gates split across runner jobs, so the workflow's wall clock is one shard rather
than one suite. Main runs are no longer cancelled by the next push.

### Changed — every skill description rewritten under the client budget, and one skill folded away

Reported and **measured** by [@jmangs](https://github.com/jmangs) in #49: Codex silently shortens skill
descriptions to fit its context budget, keeping the first ~350 characters of each. All eighteen ripwire
descriptions were over that budget — **18,455 characters authored, 6,300 retained, 12,155 discarded**,
fifteen of them cut mid-token. What the truncation removed was the routing boundaries: the "NOT for X,
that's skill Y" clauses, the secondary triggers, the misuse warnings. His diagnosis is the one this round
acted on, and it is worth quoting: the shortened descriptions "do not become literally identical — the
problem is semantic: related skills lose the clauses that distinguish them."

That reframed the task. Eighteen skills whose boundaries need a thousand characters each to explain are
eighteen skills whose boundaries are not carrying their own weight; the budget did not create the routing
problem, it exposed it by deleting the prose that was compensating. So the round asked what set of skills
has boundaries an agent can tell apart *in* 350 characters, rather than how to compress the existing ones.

Pre-registered before any description was touched (`docs/EVALS.md`), with a truncation-aware A/B whose
baseline was today's descriptions **truncated** — the thing users actually have — not today's full text.
The registered set-total ceiling was amended 4,800 → 5,400 and a third blind rater added, both **before**
measurement rather than after. Three LLM raters, sealed held-out set. The result was a **REJECT on the
registered band**, published as such; the parts that stood were kept, including folding
`ripwire-efficient` into `ripwire-orient` — the one boundary all three raters independently could not
distinguish. `test/skilldescbudgetcheck.sh` now pins every description under the budget, with a
binary-backed arm reading the binary's own skill discovery, so this cannot drift back silently.

### Added — Bash, Lua, Ruby and Elixir get import/dependency edges (parser version 81)

Four languages that emitted **no dependency record on any tree** now emit one per directive. Each spells a
real file dependency, and each spells it as an ordinary CALL rather than a reserved statement — which is
why `directiveTargetOf` had no branch for any of them, and why `lintrules.h::dependencyCapable` called all
four incapable. That was a true statement about this extractor and a false one about the languages.

| Language | Directives captured | Resolution rule |
| --- | --- | --- |
| Bash | `source FILE`, `. FILE` | the argument IS the path — no convention to model. A `$VAR`/`$( … )` anchor is reduced to its literal tail and probed against the includer's directory and every ancestor, unique-or-degrade |
| Lua | `require "a.b"` | package.path's dotted convention (`a.b` → `a/b.lua`, or the package form `a/b/init.lua`), probed from the requiring file upward and under the `src/` and `lua/` source roots |
| Ruby | `require_relative`, `require`, `load` | a leading dot means file-relative (the extractor normalizes `require_relative "x"` to `./x`); a bare specifier is searched against the crawl root plus `lib/`, `app/`, `test/`, `spec/` |
| Elixir | `alias`, `import`, `require`, `use` | the corpus's OWN `defmodule` index, not a `MyApp.Foo` → `lib/my_app/foo.ex` path convention — so umbrella layouts and generated paths resolve, and a module two files define resolves to neither |

Every rule is unique-or-degrade: two candidate files answering one specifier resolve to **neither**. There
is no basename fallback anywhere in this, which is the one shortcut that would have made all four look
better on a benchmark and been wrong invisibly.

**Measured on this repository** (`ripwire . --deps`): 29 `source` directives across 28 gate scripts, 26 of
them resolved. The 3 that do not are `. /dev/stdin <<EOF`, an absolute path outside the crawl — shown as a
target row with no edge, never dropped. All 29 specifiers in this tree are `$ROOT/…`, so a literal-only
resolver would have resolved zero of them.

**Disclosed floors.** A shell specifier whose FILENAME is variable (`"$1"`, `"$d/$n.sh"`) cannot be
resolved by anything short of running the script: it is captured, displayed, and produces no edge. Ruby's
`autoload :Foo, "path"` is not captured (its path is argument two). An Elixir `alias A.B.C` also binds the
local name `C`, so a later `C.f()` means `A.B.C.f` — the FILE edge lands, the NAME alias does **not** narrow
call resolution, because the call's receiver is not kept by `queries/elixir/tags.scm`. Quoted Elixir AST
(`quote do … end`) is descended into, so an `alias` inside a macro template is captured: the same
union-over-arms posture the preprocessor tables take, a spurious edge rather than a missing one.

### Changed — the dependency denominator moved, and now says so

Making four languages dependency-capable changes **five denominators and one predicate**: `--deps`'s
`dep_files=`/`ccd`/`acd`/`nccd`, `--arch`'s `propagation_cost`, and `--cochange`'s pair filter. Any number
recorded against an older build on a corpus holding Bash, Ruby, Lua or Elixir has moved. On this repository
`dep_files` went 758 → 1392 and `nccd` 0.68 → 0.39.

`--deps` therefore publishes **`<health dep_langs=>`** — the capable language set, derived from the
predicate itself so it cannot drift from what it documents. A `dep_files=` number is only comparable across
builds when `dep_langs=` matches, and until now the set behind it existed only in a source comment.

**`--cochange`'s `surprising=` is now a PAIR question.** It was "both sides dependency-capable", which
agreed with the truth only while `.sh` was incapable. The moment a shell script became capable, that form
would have declared `test/foo.sh` ↔ `src/bar.h` a pair whose missing static dependency is *evidence* — and
no `source` can name a header. Measured before the change: of 153 `dep_capable="0"` rows in this repo's top
400, the per-file form would have turned 88 capable and **75 of those are cross-dialect** pairs that would
have read as hidden architectural debt. The predicate now also requires a shared dependency dialect, which
additionally fixes 22 pre-existing over-claims of the same shape (`.js`↔`.h`, `.py`↔`.h`, `.py`↔`.cpp`).

**Markdown stays excluded, now on the record.** Markdown *does* mint doc→doc link edges — `[B](b.md)` is a
real edge and the map shows it — so "no import syntax" was never the reason. It is excluded because `--deps`
and `--arch` measure change amplification, and a README linking twelve design docs is not twelve files of
it: docs are read, not compiled. JSON/TOML/YAML have no file-level import at all.

**Fixed while building this:** the root-relative probe every unknown-anchor rule needs was anchored at an
empty base, which is the crawl root only when the root was written as `.`. The same tree scanned as
`ripwire /abs/path` resolved 13 of 29 `source` directives where `ripwire .` resolved 26. Probing the
includer's ancestor chain instead is root-spelling independent, and each new gate asserts the two spellings
produce identical edges.

Five new gates: `test/bashsourcecheck.sh`, `test/luarequirecheck.sh`, `test/rubyrequirecheck.sh`,
`test/eliximportcheck.sh`, `test/deplangscheck.sh` (550 → 555). `test/luacheck.sh` §2 was **inverted** — it
used to assert `<deps files="0">` on a Lua corpus, which is the assertion that would have kept this defect.

### Fixed — Ruby: definitions carry their enclosing class/module, and `def name=` is indexed and called

Landed from PR #47 (Andriy Tyurnikov), rebased onto the Elixir and ES-import work. Two Ruby extraction
defects, plus one resolver defect that turned out not to be Ruby's at all.

**A Ruby `def` had no scope.** `src/ingest_sidecap.h` set a definition's `scope` for C++, Python and Rust
only, so no Ruby row ever carried an `id=`: a `Scope::name` selector (`--expand=B::initialize`,
`--callers=A::helper`) could not address a Ruby method, same-named methods in different classes of one file
folded into a single `overloads=N` row, and `--edit-check=Widget::resize` answered "symbol not found".
(PR #47 also listed `editcheck.h`'s implicit-receiver exemption as a dead branch the scope revives. It does
revive it, and it is still inert: Ruby has no implicit receiver parameter to exempt, and the caller test
short-circuits on `arityExact == 0` — which `cc_paramArityExact` gives every Ruby definition, since its
language gate does not list Ruby. Measured `incompatible="0"` scoped and unscoped, before and after. The
comment there now says so rather than implying a recovered signal.) `rubyEnclosingScopeOf` (`src/ingest_names.h`) records
the nearest enclosing `class`/`module`: it walks THROUGH `class << self`, skips the definition's own node
(a `class Widget` inside `module Outer` scopes to `Outer`, never to itself) and takes the last segment of a
`class Foo::Bar` name, matching the contract C++'s `qualifierOf` already keeps. A top-level `def` still has
no scope and no `id=` — a file is not a scope.

**`def name=(v)` was never indexed, and `obj.name = v` called the getter.** tree-sitter-ruby names a setter
with a `(setter)` node, which `queries/ruby/tags.scm`'s method pattern did not accept. And `obj.name = v`
parses as `(assignment left: (call method: (identifier)))` — the same `(call)` shape as the read
`obj.name` — so the call rule captured a reference to `name` and the resolver handed a WRITE to the getter:
a false edge, not a floor. The setter is now named `name=` on both sides: the definition from the
`(setter)` node's own text, the call site by reading the assignment parent (`rubyCallIsAssignmentTarget`).
`self.name = v` inside the class pins to `Class::name=` through Rule 1, and `--callers=name=` answers.

Three resolver-side changes ride along so the new scope adds precision without losing edges: Ruby call
receivers are classified (`src/ingest_binds.h` — `self.m` is `ThisObj`, `x.m` is `NamedVar`, a receiver-less
`m(args)` stays bare); Rule 1 (`src/resolve.h`) treats a bare Ruby paren call as the implicit-self send it
is, so `helper(2)` inside `class A` pins to `A::helper` as a FACT rather than as a disclosed locality guess
(`lpin=`); and the S6-C locality tie-break (`src/graph.h`) no longer lets the caller's own definition win.

**The tie-break fix is not Ruby's, and is disclosed as such.** A candidate that IS the caller matched itself
on every locality segment, won alone, and was then dropped at emission as a self-loop — the site produced no
edge at all, silently. Ruby's facade idiom surfaced it, but the shape is language-agnostic: the same fixture
in PYTHON goes from `edges=0` to an honest 2-way split with `amb="1"` (`test/lpincheck.sh` arm (I), the
language-agnostic pin — revert that one line and it goes red before any Ruby gate does). Measured across
eight Ruby-FREE corpora (rocksdb, duckdb, ugrep, django, ccxt, mlflow, cpython and one large
ObjC++ tree —
`--no-cache --top-k=100000`, every row and every edge compared): the change is **edge-ADDITIVE, 0 edges lost
anywhere**, `symbols=`, `unresolved=` and `external=` unchanged, `edges=` +0.02% (ccxt) to +0.33% (rocksdb),
and `locality_pinned=` up where an edge that used to vanish is now emitted as a disclosed guess (rocksdb
141 → 587, duckdb 171 → 575, cpython 556 → 709, the ObjC++ tree 100 → 237). A control binary carrying
other change with only that line reverted is BYTE-IDENTICAL to the pre-merge tip on all eleven Ruby-free
corpora — so nothing else in this change moves any other language.

Measured on Ruby 2.6's own stdlib (833 `.rb` files, `--no-cache --top-k=100000`, byte-identical across runs,
`xmllint --noout` clean): `symbols=` 14220 → 14476 (250 setter rows, 253 definitions, where none were
indexed before); rows carrying `id=` 97 → 13191; rows carrying `overloads=` 649 → 194; call edges naming a
setter 0 → 534; `ambiguous=` 5872 → 5544; `edges=` 29077 → 28840 — a NET DROP, because a write against a
setter the tree does not define no longer invents an edge to the getter. **The `id=` attribute is what a
scoped row costs**: the full map's `est_tokens` rose 504107 → 816226 on that corpus and the default 200-row
map's 8796 → 12313 (+40%), the same price Python already pays. Non-Ruby corpora pay ~1% (rocksdb 14652 →
14826).

**Stated floors, each pinned by a gate arm so it stays a decision.** `rubyCallIsAssignmentTarget` reads a
plain `(assignment)` only, so a compound `w.count += 1` and a conditional `w.count ||= 1` (both
`operator_assignment`: they read AND write, and one capture carries one name) and a multiple assignment
`a.count, b.count = 1, 2` (a `left_assignment_list`, one level deeper) all keep the getter edge only.
`attr_accessor` / `attr_writer` / `attr_reader` generate their methods at load time and define nothing in
the source text, so they are not symbols and a write against one resolves to an honest NOTHING — unchanged
by this work, and now asserted. And the tie-break fix is the tie-break only: one layer up, tier 1 admits
same-FILE candidates and stops if any exist, so a caller that is the only same-file candidate is still
selected alone and still dropped to nothing (`def prerelease=; set.prerelease = v; end` in one file with the
real `prerelease=` in another). Widening tier 1 past the caller would mint a cross-file edge the same-file
tier already outranked, so the honest nothing stands.

`kParserVer` 79 → 80 with `quality.h`'s `kIngestParserVerMirror` in the same commit (the fork carried 79,
which the Elixir and ES-import bumps had already taken — re-bumped to the next free number over the merged
tip, per the rule in `src/ingest_cache.h`); `kCacheVersion` stays 16, no record shape moved. Gates:
`test/rubyscopecheck.sh` (scope shapes, the `Scope::name` selector, the overload split, facade delegation,
Rule 1 pins, a hoist mutation, determinism), `test/rubysettercheck.sh` (definitions, write vs read edges,
the explicit `w.name=(4)` and chained `w.inner.name = 5` spellings, four stated floors, `--callers` on both
names, a write-to-read mutation, determinism) and `test/lpincheck.sh` arm (I). Both new gates were run
against the PRE-fix binary and fail there (18 and 12 failing assertions), which is what makes them evidence.


## [0.4.0] — 2026-09-06

**This section spans everything since 0.2.2, not since the last tag.** v0.3.0 through v0.3.8 were cut
and published as release binaries without changelog sections of their own; rather than reconstruct nine
retrospective entries from the log, the work they carried is recorded here, in the release that first
documents it. The tags remain valid — they are what `scripts/install.sh` served while they were latest.

### Added — `--plan-lanes` now recommends a Codex model and reasoning effort per lane

Every lane carries an advisory `execution` object with a current Codex model, reasoning effort, the
deterministic policy rule that selected them, and the complete structural signals used by that rule.
The recommendation labels itself `basis="structural-only"`; partial test evidence, name-based call-graph
resolution, and truncated evidence are disclosed as in-band caveats for the orchestrator to override.
The additive JSON field keeps the top-level schema at `v: 1` and versions its policy independently as
`codex-lane/v1`.

### Changed — `.gitignore` is honoured by default; `--no-ignore` restores the old walk

ripwire is named for ripgrep, whose defining default is that ignored files are not searched. The crawl
walked them. In a git work tree it now consults git's own ignore rules and skips what the repository
already declared uninteresting — `node_modules/`, `.venv/`, `target/`, `build/`, `dist/`, whatever the
repo says — and **`--no-ignore` restores the previous behaviour exactly**.

Measured on this repository's own root with no `--exclude`, three checkouts under a gitignored
`bench/external/`: `files=` 8,674 → **1,522**, cold 2.81 s → **0.52 s**, warm 0.63 s → **0.10 s**, and
the result agrees to the file with the hand-written `--exclude=bench/external` the tool used to need.
The ignore lookup is one `git ls-files ... --directory` per root: 0.020 s (ugrep), 0.030 s (rocksdb),
0.150 s (duckdb), 0.032 s (this root) — `bench/PROFILE.md` carries the ledger.

Nothing is dropped silently. The map header states `ignored_files=` (files the rules covered, exact)
and `ignored_dirs=` (subtrees they pruned — the walk stopped there, so their contents are UNKNOWN, not
zero); both are ABSENT when the rules dropped nothing, so a tree with nothing ignored is byte-identical
to what it produced before. `--skipped` rows the ignored set and names the mode in `ignore_mode=`.
`--exclude` composes on top, and a multi-root run applies the rules per root.

Four situations keep the full walk, and `--skipped`'s `ignore_mode=` says which applied: `git` (rules
consulted), `off` (`--no-ignore`), `unavailable` (no git work tree at this root, or no git binary), and
`root-ignored` — the root is ITSELF inside an ignored subtree (`ripwire build/` in a repo that ignores
`build/`), where honouring the rules literally would hand back an empty map for a directory you pointed
at on purpose. A tracked file that happens to match a `.gitignore` pattern stays indexed, because git
ignores nothing it tracks.

### Changed — one warm cache per tree, and a narrower run no longer throws the wider one's work away

The warm-by-default cache keys on the tree's path and the verb class, and deliberately not on
`--exclude` or `--max-file-size`: one blob per tree, shared by every configuration you run against it.
That sharing had a hole. A run with an `--exclude` deserialised the WHOLE blob — including the records
for the files it had just excluded — and then, if anything had changed, rewrote the blob with only its
own file set. The next run without that `--exclude` found those files missing and re-parsed them from
scratch. Alternating `ripwire .` with `ripwire . --exclude=vendored` therefore paid a cold parse in one
direction and a superset deserialise in the other, every time.

The blob now carries a record offset table, so a run reads only the records for the files it actually
crawled, and a save carries over — byte for byte — the records for files it did not. The cache only ever
grows toward the union of the configurations that share it, so switching between them is free in both
directions.

Measured on a 31,000-file tree (1,000 files kept, 30,000 excluded), comparing `d8fa59c` with this
change. A warm excluded run: **0.06–0.09 s → 0.01 s**, now indistinguishable from that configuration
having its own private `--cache=PATH` blob. The run after a changed excluded run: **30,000 files
re-parsed in 0.96 s → 0 files re-parsed in 0.27 s**. The costs, both real: the table adds **3.3%** to the
blob (32 bytes per file), and a save that has to carry 30,000 records over takes 0.13–0.40 s where the
old truncating save took 0.02 s — which is the trade, because the truncation is what made the next run
cost 0.96 s. Full ledger in `bench/PROFILE.md`; the bands, including the earlier attempt at this that was
measured and reverted, in `docs/EVALS.md` under "The auto-cache key ignores `--exclude`".

Cache blobs from earlier versions are rejected and rebuilt on the next run, as with every format change:
no action needed, one cold parse. `RIPWIRE_CACHE_STATS=1` gains `cached_records=` and `blob_entries=`.
New gate: `test/cacheoffsetcheck.sh`.

### Added — `--slice` reaching definitions are flow-sensitive inside one definition (C-family, Python)

Every use row of `--slice=SYM:VAR` (and the MCP `slice` verb) now carries `rd=` — the lines of the defs
that reach it — computed by one structural pass over the definition's statement tree: a def is killed by
the next unconditional def of its binding on every path, defs join at `if`/`elif`/`else`, `switch` (cases
fall through, no `default` keeps the no-case path), a loop's back-edge (fixpoint), `try` handlers and
`finally`, `for`/`while ... else`, `match` and a build-dependent `#ifdef`; `return`/`break`/`continue`/
`throw`/`raise` end their path. The root says which rule is in force — `reach="cfg"` for C/C++/ObjC and
Python, `reach="linear"` (source order, nothing joins) for JS/TS, Go, Java, Rust until their control
tables are fixture-verified. `--slice-flow` and `--since` read the same reach table, so the rows, the flow
walk and the dependence diff can never disagree about an edge. The unit is the statement (uses read the
entering state, defs apply after); every construct the walk does not branch on — `?:`, short-circuit,
conditional expression/comprehension, lambda/closure/nested def/class bodies, `goto`, `global`/`nonlocal`,
the try handler's entry, aliases — is named in the legend instead of guessed. Registered and measured in
`docs/EVALS.md` ("Flow-sensitive slice in the small"): 0 wrong of 85 hand-written sentinel use rows across
53 functions, and the 57-commit `--since` labelled set unchanged at 35/35 and 22/22. Gate:
`test/sliceflowsenscheck.sh`.
### Fixed — `--expand` no longer takes minutes on a file whose lines are hundreds of kilobytes

Secret redaction (`redactSecrets`, on by default at every body-emission seam) was quadratic in LINE
length. Its low-precision `[A-Za-z0-9+/=_\-]{32,}` rule re-derived three position-independent values at
every cursor: the enclosing line's boundaries, that line's credential-keyword verdict, and — through a
greedy `regex_search` anchored at the cursor — the whole character-class run it sits in. Ordinary source
has ~100-byte lines and never noticed. A minified or vendored bundle is nothing but huge lines, and
`--expand` hands one to this path whole while pricing its whole-file candidate.

Measured on babel's `.yarn/releases/yarn-3.1.0.cjs` (2,196,921 bytes over 768 lines): a single `--expand`
selector burned 196.7 s of CPU without finishing under a manual timeout, and an unattended run was killed
at 1,343.9 s of user CPU with a still-empty output file. It now answers in 0.46 s warm. On a
self-contained 20 KB-single-line fixture, 23.02 s → 0.017 s. Each of the three values is now computed
once per line or per run, which makes the sweep linear.

This is an output no-op — same matches, same gate verdicts, same bytes — verified byte-identical on
stdout, stderr and exit code against the pre-change binary over 24 corpora (20 of them external
multi-language snapshots) × 5 verb shapes. New gate: `test/redactfixcheck.sh`. Ledger row and the
`sample(1)` breakdown in `bench/PROFILE.md`.

## [0.2.2] — 2026-08-09

### Fixed — a local variable that shadows a function name no longer steals that function's use-sites

`--uses` attributed a local's read/write sites to a same-named function (13 false sites on one
measured query). A local binding now claims its own scope, and a `using ns::name;` re-export emits
the `role="import"` row it never produced. Measured against a `scip-clang` oracle on this
repository, site-level precision/recall moved 0.9046/0.9285 → 0.9136/0.9412, with the worst
motivating query going 0.6579 → 0.9615 and three others reaching 1.0000. The suppression took three
refutation rounds to get right, and the third found a **recall loss the first cut introduced**: a
genuine call appearing ABOVE the shadowing local vanished entirely, because the suppression span
started at the enclosing block rather than at the declaration point. It now begins at the end of the
complete declarator, C++ [basic.scope.pdecl]. Fixture corpora, per-round verdicts and the verifier
history: `bench/fixround/RESULTS.md`.

### Fixed — five more shapes that invented or destroyed references

A declared name no longer leaks as a read of the symbol it shadows under a defaulted parameter, a
parameter pack, or an attributed declarator. A bare-identifier assignment (`x = y;`) mints a
function-pointer binding only when the file's own declarations allow it, and a class-typed copy no
longer does — closing a bug that was **losing real call edges**, not merely adding false rows: a
bogus binding tombstoned a genuine same-named file-scope binding corpus-wide. Zero call-edge loss
verified on two corpora (10,742 edges here, 39,741 on a 2,376-file ObjC++ tree, byte-identical
before and after); 59 false `--uses` sites removed with zero sites gained. One deliberate behaviour
change is disclosed in the count-floor legend: a variable whose function-pointer typedef lives in a
HEADER is now missed, because same-file alias evidence cannot distinguish it from a value copy.

### Changed — `--uses` states that a bare type mention is not a use-site

The role list is the whole vocabulary. Naming a symbol as a type in a signature, a declaration or a
template argument contributes no row, so a caller that only names it as a type is absent from the
count. Previously true and unstated; now stated in the legend. A `role="type"` reference class
remains the fix rather than the disclosure, and is recorded as such.

### Added — the oracle-scored reference-precision receipt

`bench/headtohead/r9-2026-08-09/` publishes the round behind the README's silent-miss claim: 68
answers scored against a `scip-clang` index, six imperfect, four self-flagged, and the two unflagged
traced to files the oracle could not see. It reports the comparison in both directions — an
LSP-backed tool is more precise, by ~1.5 points after these fixes, with recall now equal — along
with the protocol asymmetry that inflates one of our own rows and four limits that travel with the
numbers, including that the corpus is this repository.

### Changed — the held-out recall lane now scores a frozen doc corpus

`bench/recalleval/`'s recall lane no longer measures the live repository's docs: it unpacks
`snapshot.mdpack` — every tracked `*.md` at the commit pinned in `snapshot.lock` — into a temp root
and scores that, so its recall/MRR floors trip only on a ranker regression. The change closes a
standing defect: the lane's floor had been ratcheted 85→83→78→69 in five days purely by corpus
composition (documents joining, or even just growing, moved BM25 length normalization), with ranker
neutrality proven at every step — the forensic record is `test/recallevalcheck.sh`'s header. The
live tree keeps its own signal: a `recall_livepol` probe re-runs the same queries against the live
root and reports pollution@5 (ceiling 16% unchanged). Frozen bars: lenient recall@5 76.2% baseline /
floor 71; lenient MRR 0.619 baseline / floor 0.57. Corpus integrity is a content hash verified as
the gate's first check; refreshes happen only in deliberate recalibration commits
(`bench/recalleval/make_snapshot.py --freeze`). Method and bars: `docs/EVALS.md`.

### Fixed — nested JS/TS closures no longer inherit the enclosing function's metrics

Cross-codebase validation on webpack found a systematic extraction bug: a named const-closure
nested inside another function's scope (`const f = (..) => {..}` inside a function body) reported
the ENCLOSING function's loc/cx/ccx/nest/params instead of its own. In webpack's
`lib/html/syntax.js`, all eight closures inside the ~3400-line `tokenize` arrow reported identical
loc=3439 cx=487 params=3; the same happened under anonymous enclosers
(`module.exports = (..) => {..}` in `lib/util/deterministicGrouping.js`). Root cause: the tags-pass
body-climb (built for C++'s `function_declarator` → `function_definition` hop) adopted the first
ancestor owning a `body` field — for a nested closure that ancestor is the *enclosing*
`arrow_function`, whose whole span the closure then stole; `statement_block` was missing from the
climb's scope-stop list, so only nested (not top-level) defs escaped upward. The climb now refuses
any ancestor whose body *contains* the definition — a grammar-agnostic containment stop. Call-edge
attribution rides the same spans, so calls in the encloser's body now attribute to the encloser
instead of the last span-stealing closure. On webpack, unambiguously individually-scoped `nest>=4`
rows went from ~18% to 98% (django's healthy Python baseline: 89%). `kParserVer` 41 → 42 (cached
spans carry the bug). Gate: `test/jsnestedcheck.sh` on `test/jsnestedfix/` — hand-counted
loc/cx/params/nest for both shapes, JS and a byte-identical TS twin.

### Added — `--skipped`: itemize the header's `skipped_oversize=` count

The map header has long disclosed *how many* otherwise-indexable files the crawl dropped for
exceeding a size ceiling (`skipped_oversize=N`, absent when zero) — but nothing anywhere named
*which* files, so a reader could know the corpus was truncated without being able to say what was
absent from it. `--skipped` names them: one `<f p= bytes= limit=/>` row per dropped file, path-sorted,
where `limit=` is the ceiling that dropped the row — `--max-file-size`'s value, or the fixed 256 KB
`.json` config ceiling that flag does not raise; the root element repeats both effective
ceilings so a zero-row report still states its bounds. The accounting invariant is unchanged and now
itemizable: `files=` + `oversize=` = the population the crawl considered, at every `--max-file-size`.
Multi-root workspaces list rows under the same `<label>/./<rel>` spelling every other surface emits.

Scope is deliberate: the parse-time binary-sniff and read-failure skips are *not* listed, because
those files keep their `fileId` and stay inside `files=` (present with zero symbols) — they are not
absent from the accounting this verb itemizes. The default map is byte-identical (G5: purely
additive; the header count was already there). Read-only; exit 0 always. Gate:
`test/skippedcheck.sh`.

### Added — `--dmm`: the Delta Maintainability Model, one comparable number per change

`--quality-delta` reports *which kinds* of debt a change added. It has no scale, so it cannot answer
"was this change better than the last one?" — `--dmm` is that scale: one scalar in `[0,1]` per commit
or per working diff, trendable across commits and comparable across authors.

```
<dmm base="2edbb46cfd9d…" target="working-tree" available="1" combine="pooled"
     size_metric="physical-loc" dmm="0.436" good="462" bad="597"
     base_units="4759" base_volume="86331" target_units="4780" target_volume="86684">
  <p k="size"        dmm="0.184" good="65"  bad="288" d_low="65"  d_high="288"/>
  <p k="complexity"  dmm="0.499" good="176" bad="177" d_low="176" d_high="177"/>
  <p k="interfacing" dmm="0.626" good="221" bad="132" d_low="221" d_high="132"/>
```

A *unit* is a function or method definition with a body; its *volume* is its line span. Per property a
unit is **low risk** iff `loc <= 15` (size), cyclomatic `cx <= 5` (complexity), `params <= 2`
(interfacing). `good` is low-risk volume **added** plus high-risk volume **removed**; `bad` is the
reverse; `dmm = good/(good+bad)`. **Deleting a god function scores 1.000; growing one scores 0.000.**
The three sub-scores ship alongside the combined one because they are separately actionable — a low
`size` with a healthy `interfacing` says *split the function*, not *change the signature*.

Three spellings: bare `--dmm` compares the **working tree** against `git HEAD` (what `--quality-delta`
compares); `--dmm=REV` scores one commit against its **first parent**, the per-commit scalar; and
`--dmm=A..B` scores tree B against tree A. Multi-root workspaces refuse — pooling two histories into
one ratio would mean nothing.

**It is a delta, never a level, and that is the whole design.** A unit you edit without changing its
size, complexity or parameter count sits in the same bin with the same volume on both sides and
contributes exactly zero to both `good` and `bad`. You are not punished for touching pre-existing bad
code, because a gate that punishes touching a mess is a gate people route around. For the same reason
the verb has no threshold, renders no verdict, and always exits 0.

**`dmm="UNAVAILABLE"` is not a score.** When `good + bad` is 0 — a rename, a literal edit, a comment
reflow — the change is outside what the model measures, and the report says so in `reason=` rather
than picking the flattering default. It is never 1.000 and never 0.000. The same token appears per
property: a commit that only adds parameters leaves `size` and `complexity` UNAVAILABLE while
`interfacing` is measured.

**Lineage, and the one deviation.** The model is di Biase, Rastogi, Bruntink & van Deursen, TechDebt
2019 (SIG). The three risk thresholds and the exact good/bad asymmetry are PyDriller's
`deltamaintainability` reference implementation, read out of `pydriller/domain/commit.py` rather than
re-derived from the paper's prose — including the 0/0 case, whose `None` is where UNAVAILABLE comes
from. The deviation is disclosed on every report as `size_metric="physical-loc"`: PyDriller's volume
is lizard's non-comment `nloc`, ripwire's is the definition's physical line span, so a heavily
commented unit crosses the size threshold here earlier. The combined score is labelled
`combine="pooled"` because the paper publishes the three properties separately and no aggregate.

Gate: `test/dmmcheck.sh` — a hand-built git repository whose every commit has a pencil-derivable
answer (delete-only-high-risk → 1.000, grow-a-god-unit → 0.000, a 4-good-vs-4-bad mix → 0.500, a
literal-only edit → UNAVAILABLE), both sides of all three thresholds pinned (15 vs 16 lines, cx 5 vs
6, 2 vs 3 params), plus the root-commit, non-git, refusal, determinism, well-formedness, legend and
additivity arms.

### Added — `--nonlocal-state`: the mutable state a function can reach, reads and writes kept apart

A new lens: for every function and method, the non-local **mutable** state it — or anything in its
transitive callee closure — reads and writes, as two separate sets, with the site or the callee that
explains each one. A *cell* is a file- or namespace-scope variable, a function-local `static` (local
in name only), or a Python module global; a `const`/`constexpr`/`consteval` declaration is not a cell,
so a large `writes=` is genuinely shared mutable state and not a table of constants.

```
<fn p="src/infra/profilePmc.h:288" n="ensure_global_init" writes="2" reads="3"
    direct_writes="1" direct_reads="3" cells_total="3">
  <cell n="g_perf" p="src/infra/profilePmc.h:284" dir="rw" at="src/infra/profilePmc.h:339" at_dir="rw"/>
```

`writes=`/`reads=` fold in the callee closure, `direct_*` is what the body does itself, and each cell
child carries `dir=r|w|rw` plus either `at=` (a use site here, with `at_dir=` for what *this* body does
— it can be narrower than `dir=`) or `via=` (the nearest callee that touches it). Rows are ordered
most writes first; pages with `--limit`/`--offset`.

**Direction is the point, and it is not new.** Henry & Kafura's 1981 information-flow metric already
separated what a procedure reads from what it writes; folding them into one number discards the half
that is a hazard for everyone else. The lineage is recorded in full in
[`docs/LINEAGE.md`](docs/LINEAGE.md) — Fowler's **Global Data** / **Mutable Data** smells (2018), which
name this hazard and ship no metric; **Marinescu's ATFD** (ICSM 2004), the closest existing number and
one-hop, per-class, Java and direction-blind; **QMOOD DAM** and **MOOD AHF/MHF** (Bansiya & Davis, TSE
2002), which count *declared visibility* and therefore score a class with private fields and leaked
mutable internals as perfectly encapsulated; **Potanin, Noble & Biddle 2004**, the only published
*measurement* of externally reachable state, which is dynamic, Java-only and tooled with something
unmaintained; and **Meyers & Binkley** (TOSEM 2007), whose slice-based coupling already puts globals in
its output set, so the delta — per function rather than per variable, over the call graph rather than a
dependence graph — is argued in the source header rather than asserted. **The folklore term "action at
a distance" is deliberately not used**: it has zero academic presence and naming the feature after it
would have been the one indefensible choice available.

**It is unsound, and every count says so.** `counts_floor="1"` is on the root. The analysis cannot see
an indirect call (function pointer, virtual, callback, macro-generated call site), a write through a
pointer or reference that aliases a cell without naming it, a cell named only inside a macro, or
reflection-like dispatch — each of those makes the count too low. In the other direction, a local that
*shadows* a cell's name is charged to the cell unless ingest recorded a type binding for it. The
report's own legend names all of these where the reader meets them.

**Scope, stated rather than implied.** It covers **C++, ObjC and Python** — the languages for which the
index carries read/write use sites at all (`captureUses`, `src/ingest.cpp`). Every other indexed
language is named on the root as `unanalyzed_langs=` with a file count, because a Go or Rust corpus
would otherwise report a confident, wrong zero. Widening the lens means widening `captureUses` first,
with its own gate; adding a declaration rule alone would not do it, and the source header says so.

Gate: `test/nonlocalstatecheck.sh` (12 arms) — a hand-derived golden over a two-language fixture, a
mutation control that turns one cell `const` and must go red, plus determinism, direction, provenance,
paging, additivity and XML well-formedness.

### Added — `--field-affinity[=STRUCT]`, the cache-locality lens (advice only, and validated)

Which fields are **read together but declared far apart**. Every shipping struct-layout tool answers
"where are the holes?" — pahole, clang-analyzer `optin.performance.Padding`, PVS-Studio V802, Go
`fieldalignment`, `-Wpadded`. None answers this one. The verb builds a static field **co-access
affinity graph** (one observation per indexed C-family function body) and diffs it against the declared
field order and 64-byte cache-line geometry, reusing `--layout`'s LP64 offset model rather than
re-deriving it. Bare form ranks every aggregate in the repository by separation cost; `=STRUCT` narrows
the report.

**Almost none of this is new, and the output says so in its own legend.** The affinity graph, the
points-to-free static access enumeration (`<function, struct type>`, an approximation its authors
conceded), the separation weight `wt(fi,fj) = (block − dist)/block` reproduced verbatim, and
hardware-counter validation of layout work are all Chilimbi, Davidson & Larus, *Cache-Conscious
Structure Definition*, **PLDI 1999**. The advice-instead-of-transform posture and per-field counter
attribution are Hundt, Mannarswamy & Chakrabarti, **CGO 2006**. What is new is narrow and is
engineering: a *source-level, no-debug-info, whole-repo-ranking* delivery — pahole needs DWARF, Hundt's
was one proprietary compiler on a dead architecture, `lshaz` is Linux-x86-only and answers the inverse
(false-sharing) question.

**Exactly two findings fire**, both with a direction defensible in one sentence: `split-line` (two
fields co-accessed by ≥2 distinct functions at `wt == 0.00`, so no field order can put them on one line)
and `straddle` (one co-accessed field crossing a line boundary). **Pack-tighter and sort-by-size advice
is deliberately absent** — the Go team excludes its own `fieldalignment` analyzer from `vet` and `gopls`
because the diagnostics "very rarely indicate a significant problem" and tight packing can induce false
sharing. There is no rewrite mode and the verb never exits non-zero: five compiler attempts at automatic
field layout are dead (GCC `-fipa-struct-reorg`, LLVM heap SRA, esan, StructFieldCacheAnalysis,
Qualcomm's AoS→SoA RFC), every one that died on soundness died because a *compiler* must prove a pointer
points at a pool of that struct. Advice cannot miscompile.

Limits, in every header rather than in a footnote: `counts_floor="1"` (`fns=` counts distinct indexed
functions, never dynamic frequency; `w=` is a fan-in reachability *proxy*), `model="lp64-approx"` (a
definition `--layout` marks `modeled="0"` contributes its affinity graph and no geometry finding), only
dot/arrow member syntax is counted, and a field name declared by two aggregates is **refused** and
tallied in `amb_skipped=` rather than guessed.

**The validation half is real, and it refuted the hypothesis in one regime.**
`bench/bench_field_ab.cpp` builds the two layouts the lens compares and measures them through
`prof::pmc` — ripwire's existing counter backend. On an Apple M5 Pro, 64 MB per arm, five repeats per
stride: the flagged layout is 4–41 % **slower** at strides 9/1025/4097, mixed at 129, and ~2× **faster**
under a fully sequential sweep — where the packed arm moves *less* data and still costs more time,
because a single 64 B touch per 256 B element is a sparser stream than two. Hardware counters were
**UNAVAILABLE** in that run (kperf needs root on macOS) and the harness says so rather than implying
confirmation, so the *mechanism* claim remains unconfirmed. `docs/FIELDAFFINITY.md` records all of it,
including the honest reading of the lens's own #1 result on ripwire's source (`MainDispatch` — real
static separation cost, almost certainly nil dynamic cost, which is limit (1) visible in the top row).
Gate: `test/fieldaffinitycheck.sh` over `test/fieldaffinityfix/`, whose every offset is hand-computed in
the fixture's own comments.

### Measured — `--ensemble`'s four families are near-orthogonal; one of them cannot carry a gate

A calibration pass over **nine trees (five independent, 27 889 eligible functions)** spanning C, C++,
ObjC/ObjC++, Metal, Rust, Swift, Python, TypeScript and Bash. No behaviour changed: the new
`bench/ensemblecal/` harness reads `--ensemble`, `--readability` and `--metrics` and computes
nothing of its own. Full numbers, per corpus and pooled, in [`docs/EVALS.md`](docs/EVALS.md) §9.

- **The ensemble premise holds.** Largest cross-family correlation anywhere: **φ = +0.278**; pooled
  over the independent corpora no pair exceeds **+0.168** and the largest overlap between any two
  families is Jaccard 0.119. The four families are not one signal wearing four hats.
- **`historical` is disqualified from gating, on measurement.** Across three commit ladders (148 /
  792 / 1 620 first-parent commits) its flagged set has mean consecutive Jaccard **0.800–0.862** and
  endpoint Jaccard **0.426–0.546**, against 0.920–1.000 for the other three.
- **Three named presets, derived from that**: `lenient` = all four families, `fam ≥ 1` (32.22%
  pooled); `default` = all four, `fam ≥ 2` (4.39%); `strict` = structural + lexical + confusion,
  `fam ≥ 2` (2.34%) — strict is a *selection*, not a higher K, and its output set is both smaller and
  measurably steadier than `fam ≥ 3` over all four.
- **Two honesty defects found and recorded, not fixed here.** The `confusion` family is gated to
  C/C++/ObjC but does not declare itself unavailable on a corpus with no C-family file (it fires 0 of
  4 068 on a Rust tree while still counting inside `of=`); and the "worst decile" ordinal cut is
  capped at 40 rows, so its realized width is **0.23%–8.81%**, not 10%.

### Added — `--cochange` grows the three things the papers behind it already had

`--cochange`'s `surprising="1"` predicate is an independent implementation of published work, now
cited in [`docs/LINEAGE.md`](docs/LINEAGE.md) §2 (Wong/Cai/Kim/Dalton, ICSE 2011 — the Clio tool;
Mo/Cai/Kazman/Xiao, IEEE TSE 2019; Gall/Hajek/Jazayeri, ICSM 1998; Code Maat in §3a). Reading those
against the shipped predicate produced three additions:

- **`recur=` and `sub_windows=` on every row.** Clio does not report a discrepancy the first time it
  appears — it mines frequent patterns over the last five releases and reports only recurring ones.
  ripwire mined one window, in which a one-week refactor sprint and an eighteen-month structural
  defect both score `together=4`. The window is now cut into equal-**commit-count** sub-windows
  (equal time would make the number a function of when the team took holiday) and `recur=` counts how
  many contain a joint commit. `--cochange-recur=K` filters on it and the header publishes
  `min_recur=` so a shortened list is explained. Measured on a 1,648-commit, 2,718-file C++/ObjC++
  corpus: `recur>=2` removes **45%** of the surprising pairs (253 → 140) and `recur>=3` removes
  **81%** (253 → 47).
- **`--cochange-groups`.** Mo's Modularity Violation Group is the minimal set of *groups* covering the
  violating pairs, not a pair list — "X co-changes with {A,B,C}, none of which it depends on" is one
  row that names the file to fix. Same corpus: 253 pair rows collapse to **65 groups** (3.9 pairs per
  group). The cover is greedy and says so (`cover="greedy"`); minimum set cover is NP-hard, so
  `groups=` is an upper bound on the minimum, never the minimum.
- **`conf_ab=` / `conf_ba=` / `driver=`, and `conf_rev=` on the per-file form.** Clio's confidence is
  asymmetric — `conf = frq(x1 ∪ x2)/frq(x1)` — so "A always drags B" is distinguishable from the
  reverse. ripwire's `deg=` divides by the quieter file, which is exactly the *larger* of the two
  directions with the direction discarded; both are now emitted, `deg=` is documented as their max,
  and `driver=` names the antecedent of the stronger rule. A tie emits no `driver=`.

Calibration is published with the feature rather than after it. Clio reports 66% precision on Hadoop
Common and 40% on Eclipse JDT; ripwire's measurable analogue on the corpus above is a **yield** of
59.8% (flagged pairs over dependency-capable candidate pairs), which is not the same quantity — see
[`docs/EVALS.md`](docs/EVALS.md) §7 for what was measured, what was not, and the upper bound on
precision it supports. **Correction, still pre-release:** that 59.8% was measured on an index with a
capture gap (guard-wrapped `#include`/`#import` never seen), fixed in `ba82324` (`kParserVer` 40); the
re-measured yield on the same corpus is 52.2%, with the composition-derived precision ceiling moving
from ≤67.6% to ≤64.3% — now inside Clio's 40–66% band rather than a hair above its top. `docs/EVALS.md`
§7 carries both figures and the full re-derivation; this entry is left as originally written except for
this note, per the project's own rule against silently overwriting a published number.

Gate: `test/cochangecliocheck.sh` (29 arms over a scripted 24-commit fixture repo whose oversized base
commit also proves the 30-file bulk cap still fires).

## [0.2.1] — 2026-08-05

Linux portability patch. The v0.2.0 Linux archives were built on `ubuntu-24.04` and required
`GLIBCXX_3.4.31`, so they died on RHEL 9 and older (verified on ubi9). The Linux release legs now
build inside AlmaLinux-8-based `manylinux_2_28` containers with Red Hat gcc-toolset 14 — newer
libstdc++ symbols link statically (the devtoolset model), so **one binary per arch covers
RHEL/Alma/Rocky 8+, CentOS Stream, Fedora, Ubuntu 20.04+, and Debian 11+** (glibc 2.28 floor;
verified on ubi8, ubi9, ubuntu:22.04, ubuntu:24.04). A new `smoke-rhel` CI job runs the packaged
tarball on a RHEL 9 (ubi9) userland and gates publish. Also: `bench/representative_perfgate.sh`
byte counting is now GNU-portable (`stat -f %z` is BSD-only and zeroed the corpus-shape preflight
on every Linux CI leg). No library or CLI behavior changes.
### Added

- **Optimization-remarks build and triage** — `-DRIPWIRE_OPT_REMARKS=ON` (a separate tree; refused by
  name inside `build/` and `asan/`) collects clang's `-Rpass*` remarks plus a YAML opt-record, and
  `scripts/optremarks.sh` / `scripts/optremarks.py` turn it into a ranked report. `docs/OPTREMARKS.md`
  carries the full triage of the first pass over `src/`, and `skills/ripwire-opt-remarks/` carries the
  remark→fix patterns that survived it. New gate: `test/optremarkscheck.sh`.
- **`-DRIPWIRE_LTO`, now ON by default** — link-time optimization. The first change the remarks pass
  justified: 397 of 636 distinct `inline/NoDefinition` sites in `src/ingest.cpp` name a tree-sitter C
  accessor, inside the two phases that are ~31% of a cold run, and no source edit can reach a
  cross-TU definition. Measured on this repository as corpus (937 files, Apple Silicon) across four
  independent interleaved A/Bs of 9/21/21/31 runs per arm: **cold 1–6% faster, warm 0–3%**, with
  every cold statistic in every run favouring LTO and one run's warm min going the other way — the
  per-run table is in `docs/OPTREMARKS.md` F1, and the range is the claim, not its best row. Output
  is byte-identical and the determinism gate passes on the LTO tree. It costs link time — a rebuild
  after touching `src/main.cpp` goes 34 s → 89 s — which is not a reason to decline a faster binary;
  `-DRIPWIRE_LTO=OFF` restores the fast edit loop. **Note:** `option()` never overwrites an existing
  cache entry, so a build tree configured before this change keeps `RIPWIRE_LTO:BOOL=OFF`; delete the
  tree to pick the new default up.
- **`-DRIPWIRE_PGO=generate|use` and `scripts/pgobuild.sh`** — profile-guided optimization, and the answer to the remark classes LTO cannot touch: `inline/TooCostly` and
  `loop-vectorize/VectorizationNotBeneficial` are the cost model guessing at hotness, and a profile
  replaces the guess with counts. **Cold 14–25% faster than a non-LTO build (6–16% over the shipped
  LTO default), warm 5–10%**, measured on this
  repository *and* on a ~2000-file C++ tree that appears in no training run — six interleaved A/Bs,
  two corpora, two independently built PGO binaries, every statistic favouring PGO. Output is
  byte-identical on both corpora; the determinism gate passes three times on the PGO tree. `pgobuild.sh` runs instrument → train → merge →
  rebuild as one command. Honest G3 tension, stated in `docs/OPTREMARKS.md` F2: this is two configures
  and a training run against a one-build-step guardrail. The `.profdata` is deliberately not committed
  (a stale committed profile is a clang warning, not an error), and `RIPWIRE_PGO=use` **fails the
  configure** when the profile is missing rather than silently producing an ordinary binary.

## [0.2.0] — 2026-08-04

The first binary release: portable archives for macOS arm64/x64 and Linux arm64/x64, each with a
SHA-256 file, built by `.github/workflows/release.yml` on the tag push. Includes everything from the
asset-less `v0.1.0` tag plus the language definition-shape rounds (TypeScript, JavaScript, Python,
Swift, CUDA memory-space capture), the 2026-08-04 audit hardening (cache isolation, honest
lint/doc-drift behavior, transitive test reachability, skill routing, Codex plugin/CLI setup), and
the Codex CLI benchmark harness under `bench/agentloop/`.

### Added — retrieval and ranking

- **`--for=TASK`, the task lens** — ranked signatures + metrics framed for reuse, matching doc
  comments and bodies rather than names alone.
- **Query-shape routing, on by default.** A deterministic, confidence-gated router picks name-exact
  BM25 when the query *names* a symbol (identifier syntax, or every content word is a symbol name)
  and subtoken+body BM25 otherwise, and prints which it chose and why in the header. `--no-route`
  restores the single-ranker behavior.
- **Query-mention anchoring, on by default.** A file, dotted module, or `Type.method` literally named
  in the task text — even inside a URL — is lifted to just below the top hit, and the header names
  what anchored. Byte-identical output when the text names nothing indexed. Disable per run with
  `--no-mention-boost`, or everywhere with `RIPWIRE_NO_MENTION=1`.
- **Doc-mention surfacing on `--for` / `--pack-task`, on by default.** A markdown document that names
  one of the task's top-resolved symbols in backticks is lifted into the bundle, ranked strictly
  below that symbol's own score — closing the case where the design note explains a symbol but shares
  no vocabulary with the query. Bounded (top-8 anchors, 2 docs per anchor, 6 docs total) and
  downweighted (0.55× the anchor's score) so code still dominates a code-shaped query. Byte-identical
  when nothing resolved has a mentioning document. Opt out with `--no-doc-mention` or
  `RIPWIRE_NO_DOC_MENTION=1`. Reuses the existing doc↔code edges `--mentions=SYM` already exposed —
  no new parser, no cache-format change.
- **`--adaptive`** cuts a result set at its relevance cliff (largest relative score gap) instead of a
  fixed *k*, with a floor of 5 and the existing top-K as the ceiling; the header reports what it kept.
- **`--recall=TASK`** returns the most relevant *documents* in full — memory notes, plans, designs,
  READMEs — with the header disclosing the true relevant count, what was shown, and every cut.
- **`--pack-task="TASK"`** — ranking, top bodies, caller signatures, notes and tests-to-run in one
  bundle under one budget.
- **`--exemplar`** returns the repository's best-in-class instance of what you are about to write,
  chosen by *role* (lowest cognitive complexity under a hard ceiling, then tested, then highest
  fan-in) rather than text similarity.
- **`--detail=N`** spends body tokens only on the top-N ranked symbols and emits signatures for the
  rest, in one call.
- **`--pack-signatures`** emits body-elided declaration skeletons. See `docs/EVALS.md` for the
  measured byte reduction, its root-neutralisation methodology, and the honest counterexample.

### Added — navigation and the call graph

- **`--callers` / `--callees` / `--uses` / `--impact` / `--around` / `--path` / `--connect`** — 1-hop
  in-edges, 1-hop out-edges, every statically resolvable use site (call/read/write/import/extends),
  the transitive blast radius, the ego graph, a directed shortest path, and the minimal connecting
  subgraph over 2..16 symbols (which finds the shared-caller join a directed path cannot).
- **`--graph-query=EXPR`** — a small closed expression language over the symbol graph: sources
  (`name("X")`, `all`), filters (`kind`, `cx`, `fanin`, `file`), bounded `callers`/`callees` closure,
  and `and`/`or`/`not` joins.
- **`--grep` / `--regex` / `--match`** — literal search, regex search, and tree-sitter structural
  (shape) queries, each reported with its enclosing symbol.
- **`--from-trace=FILE`** (`-` for stdin) maps a stack trace, sanitizer report, or compiler error onto
  indexed symbols, ranked innermost-first, with the innermost in-corpus symbol's body included.
- **`--external-surface`** lists names referenced but never defined in-corpus. A name called from
  several languages gets one row per language rather than a merged count, because the referencing
  file's language is what the row reports.

### Added — change safety and review

- **`--affected` / `--situ` / `--test-gate`** as one family: plumbing (changed files or a changed
  symbol → the tests that reach them), the mid-task report (blast radius + tests + co-change
  partners + hotspot alert), and the pre-PR gate (tests to run + the untested blast radius, exit 4
  if either obligation is non-empty).
- **`--exercises=TESTFILE`** is the inverse: the non-test symbols a test file transitively calls into.
- **`--edit-check=SYM`** — did this symbol's contract (parameters, publicness) change against HEAD,
  and which callers are now provably incompatible?
- **`--pr-context[=BASEREF]`** — per-file blast radius, tests to run, and hotspot flags for a diff.
- **`--merge-scout=REF1,REF2,…`** — pairwise conflict sites (same-symbol vs same-file) plus a
  suggested landing order.
- **`--quality-delta`** reports only what a change made *worse*, across ten measured failure modes,
  comparing against git HEAD. `--quality-ack` records a reviewed exception; `--ack-only=KIND` scopes
  the acknowledgement.
- **`--plan-lanes=N --task="GOAL"`** predicts, before a line is written, which parallel work lanes
  would collide. Deterministic JSON on stdout: per-lane file and symbol claims, blast radius, the
  tests each lane must run, and a landing order sorted fewest-conflicts-first. Conflict pairs are
  classified `conflicts`, `same_file_risk`, or `contract_touch`.
  - It **exits 0 even when conflicts are predicted** — conflicts are output, not a failure signal.
    Do not wire the exit code as a CI conflict gate.
  - Pre-hoc: no ref to resolve, no second ingest. ~0.1 s warm *(measured on this repository)*.
  - Read-only. The tool never writes the plan; redirecting stdout is the entire write path.
  - Lane claims are keyed on `(path, scope, name)`, not on symbol `id`. Rows still carry `id` for
    addressability, but it is `null` where it would be ambiguous, with `id_addressable` and
    `id_collides_with` stating the residual ambiguity. *(Measured on this repository: 343 `id` values
    name more than one symbol — 29.3% of symbol rows, 1426 colliding across files.)*

### Added — cross-branch archaeology

- **`--stray-content[=SUBSTR]`** — for each local ref, the lines its own divergent work authored that
  the live line does not have, with a `merged` / `superseded` / `unmerged` verdict. **`superseded` is
  the case `git cherry` structurally cannot see**: cherry compares commit ancestry, so a fix the live
  line re-implemented differently stays "unmerged" forever. Evidence is the *deletion site* — both
  sides diff the same base, so "ref R deleted base line L" and "HEAD deleted base line L" compare
  exactly, with no fuzzy matching. A pure-addition file falls back to a high-bar similarity lane, and
  every file row prints its raw `del=` / `redone=` / `sim=` numbers so the verdict is auditable.
- **`--whereis=SYM`** — which ref's tree defines or mentions a symbol, HEAD first, scanning each ref's
  full tree, with `on-head="0"` naming the case the verb exists for.
- **`--eval-stray=FILE`** — labelled verdict-accuracy evaluation (TSV `ref<TAB>verdict`), exit 3 on
  any regressed case. A confusion table rather than a ranked-set metric, because a verdict verb
  classifies. Supersession thresholds were chosen against hand-labelled branches, so changing one is
  an experiment rather than a guess.
- Both cross-branch verbs are keyed by **blob sha**. Branches off one trunk share nearly all blobs,
  and every byte-level fact is a pure function of blob content, so blobs stream through one
  `git cat-file --batch` per run and are reduced to fixed-size facts on arrival — peak memory is
  bounded by the facts, not by the trees. *(Measured on a 35-branch repository: `--whereis` read 4,445
  distinct blobs where HEAD's tree alone holds 2,897 — 35 refs for 1.53× one tree, 1.6 s.
  `--stray-content` is diff-scoped: 443 blobs, 2.2 s.)* Both use only `cat-file`, `diff`, `ls-tree`
  and `merge-base` — read-only by construction.

### Added — dark code and feature flags

- **`--flags[=SUBSTR]`** — one report over what is built but not switched on: `#ifndef`/`#define`
  header gates, CMake `option()`s, and `getenv()` reads, with kind, default, guarded regions and LOC,
  and read sites, dark entries first. *(On the motivating private repository it named 94 dark gates
  of 102.)*
  - When a name is both a header gate and a CMake option, **the CMake default wins** — it is what the
    build actually passes — and the losing definition is shown as an `<also>` row, so the
    contradiction is surfaced rather than silently resolved.
  - Alias chains resolve (`#define F_WALLS F_ALL`): a child inherits its master's default and rolls
    its guarded size up, so a master switch shows its alias count instead of a misleading `loc="0"`.
- **`--flags --flip=NAME`** answers the follow-up: if this one gate flips, what becomes live and what
  covers it? Reports the code that becomes live (`#if` regions **and** C++ branch sites), the hosts,
  downstream and dependent symbols, the tests reaching those hosts, and **`untested`** — the hosts no
  test reaches. Flipping works in both alias directions, and three-level chains resolve correctly.
  - **Value-style gates are followed, not just preprocessor regions.** A gate consumed as
    `inline constexpr bool kWalls = FLAG != 0;` and then guarded with `if constexpr` guards a C++
    *branch*, not an `#if` region; such a gate previously reported `regions="0"` and a naive flip
    analysis would have answered "nothing lights up". *(Measured on the motivating repository: one
    gate family with 11 aliases and 0 regions yields 43 branch sites across 11 host symbols, verified
    row-for-row against an independent whole-word grep.)*
  - Flip semantics are stated per gate kind. A CMake gate becomes a `-DNAME=1` compile definition, so
    its C++ radius matches the compile case — but it also steers the build graph (adding whole
    translation units), and those sites are reported as build rows and **explicitly not followed**.
    An environment gate is marked `runtime="1"`: with no delimited region, its hosts are the symbols
    that consult the variable.

### Added — documentation drift

- **`--doc-drift[=SUBSTR]`** verifies the *checkable* anchors in every markdown file against the live
  index and reports only what no longer holds. Four anchor kinds: `file:line` references (split into
  `missing-file`, `past-eof`, and `line-moved` with `got=` naming the symbol now at that line),
  backticked symbol mentions (`undefined`), `= N` constants (`const-value`), and `[N]` array extents
  (`array-extent`).
  - **Precision is the design constraint and every lane deliberately under-reports.** A name counts as
    stale only if it occurs nowhere in any non-markdown file as an identifier token, and the presence
    corpus is the index *plus* build files, shaders and config — so a shader function or a CMake
    `option()` is never reported missing. A mention must share its line with a name the repository
    does define; a foreign-scoped mention is never treated as ours; a number is compared only against
    a declaration-shaped literal the corpus binds uniquely; fenced code blocks are treated as
    illustrations. *(Measured while tightening on this repository: the naive version emitted 329 rows,
    roughly 90% of the mention lane being library names and hypothetical examples; the shipped rules
    bring it to 110.)*
  - **`checked + unchecked == anchors` always holds**, and every declined check is named and explained.
  - Stated non-goal: prose, status lines and dates are not checked, and the verb never claims otherwise.

### Added — the git-history oracle

- **`--with-history`** (opt-in, off by default) on `--doc-drift` and `--whereis` answers "was this name
  ever in this repository, and when did it leave?"
  - `--doc-drift --with-history` splits its weakest lane three ways instead of blanket-reporting
    `undefined`: `why="deleted"` with the commit, date and file; `unchecked r="never-in-history"`; and
    `unchecked r="history-no-answer"`.
  - `--whereis --with-history` gains a `<fate>` row (`v="never"`, or `v="removed"` with commit, date
    and path) — something a tree scan structurally cannot produce, since a scan can only find content
    some ref still carries.
  - Both emit a row stating exactly what the walk did (`probed=`, `head=`, `commits=`,
    `removed-names=`, and `truncated=` when bounded).
  - **Speed.** `git log -S` has the right semantics but answers one name per process: ~126 s for 247
    candidate names on a 2,965-file application repository (~85 s even rev-range-bounded). The shipped
    probe reproduces those semantics with a single `git log --no-merges -p -U0 --no-renames` walk that
    tokenizes removed lines: **3.0 s** on that repository, **0.83 s** on this one, and O(1) in the
    number of names. `git log -G` was rejected on semantics — it matches diff *text*, so a reindent
    counts — and a `-G` alternation prefilter measured ~183 s, slower than no filter at all.
  - **Precision.** On that 2,965-file repository, 325 `undefined` rows became 80 `deleted` + 243
    `never-in-history` + 2 `history-no-answer` (75% reclassified); total drift 575 → 330, clean docs
    659 → 713. On this repository, 11 → 3 `deleted` + 8 `never-in-history`, drift 119 → 111. Every
    true positive survived, and no other drift lane moved on either repository.
  - **Cost.** Flagless paths are untouched. Under the flag, cold 0.63 s / 3.83 s and warm 0.130 s /
    0.664 s on the two repositories — about +24 ms and +40 ms over default. Results are memoized per
    (repository, HEAD sha); a commit sha is immutable, so the cache cannot go stale. The cached blob
    covers the whole repository, so `--whereis` reuses whatever `--doc-drift` built. Warm output is
    asserted byte-identical to cold.
  - **Stated limits.** It walks HEAD's own history, so a name that only ever lived on an unmerged
    branch reads as *never here* — that is what `--whereis`'s tree scan is for. Merge-only deletions
    are not seen. Evidence is a removed *line*, so a name last removed from a document is cited at
    that document (a code site is preferred when one exists). A repository past the walk bound reports
    `truncated="1"` and answers `unknown`, never `never`; names below the probe's minimum tracked
    length also get `unknown`, enforced at one choke point so absence is never readable as proof.

### Added — languages

- **TypeScript gains three definition shapes that only a real repo produces.** Validated by mapping
  `github.com/openclaw/openclaw` @`1aedd8f3` (24 658 `.ts` files, 261 760 symbols, 2026-08-04) and
  diffing the emitted `n="` set against a ground truth enumerated independently — grep over *blanked*
  source (comments and template literals stripped; that repo embeds Kotlin, Swift and JS fixtures
  inside `String.raw` templates, which otherwise fake thousands of phantom hits), then confirmed at
  AST level with `--match`. Three shapes came back at ~0 % recall, none of them present in any
  fixture: `abstract_method_signature` (76 sites) — an abstract base published its own name and
  nothing a caller could bind to; `public_field_definition` bound to an arrow (287 sites) — the
  bound-method idiom, which is a class's callable surface exactly as `method_definition` is; and a
  declarator whose value is an `as`/`satisfies` cast *wrapping* the arrow (105 sites) — the
  lazy-facade idiom that openclaw's entire public `src/plugin-sdk/` surface is written in, so every
  one of those was an exported API entry point `--for` structurally could not surface. All three now
  extract: +468 symbols and +593 edges on that corpus, **0 removed**, and byte-identical output on
  non-TypeScript trees. Deliberately still out: the object-literal `pair` form of the same syntax
  (>5000 sites there — a `--match` floor — overwhelmingly inline callbacks and mock tables, not a
  navigable surface). Known limits, disclosed in the gate: ambient `declare const/let/var` bindings
  (37 sites) do not extract, and `declare module "x"` / `declare namespace X` *container* names are
  not symbols — their members are, which is what navigation needs. Gate: `test/tsshapecheck.sh`.
- **Known limit, measured and disclosed:** the pinned `tree-sitter-typescript` (v0.23.2) cannot parse
  `typeof import("…")` once it appears in a nested type position — inside a parenthesized type
  (`(typeof import("./m.js").xs)[number]`, 235 sites) or a call's type arguments
  (`importOriginal<typeof import("./m.js")>()`, 2 087 sites, the vitest mock idiom). 1 222 of
  openclaw's 24 658 `.ts` files contain at least one. The *cost* is far smaller than the site count,
  which is the reason this is disclosed rather than paid for with a grammar-pin bump: tree-sitter
  error recovery scopes the loss to the enclosing declaration, so across all 1 222 files the total is
  ~15 definitions out of 261 760 (type-alias recall 1 607/1 614 and function recall 6 805/6 813 *within
  the affected files*). Pinned in both directions by `test/tsshapecheck.sh` §4d — if a future grammar
  bump fixes the parse, that arm fires.
- **CUDA (`.cu`/`.cuh`) is indexed**, parsed with the vendored `tree-sitter-cuda` grammar (v0.21.1,
  a generated superset of tree-sitter-cpp) under the C++ tags — no CUDA-specific query patterns,
  because the grammar aliases `kernel_call_expression` to `call_expression`. *(Measured before
  adopting, 2026-08-04 probe on the fixture now at `test/cudafix/`: under the plain C++ grammar all
  12 definitions survived error recovery, but every `kernel<<<grid, block>>>( … )` launch site
  produced no call reference — `--callers` of a kernel returned 0 — and a `__constant__` module
  table failed to extract. Losing every host→kernel edge is the Metal failure mode over again, which
  is why CUDA gets a real grammar where Metal measurably did not need one.)* `.cu`/`.cuh` map to the
  C++ language, not a language of their own, so dual-compile headers (`#ifdef __CUDACC__`) resolve
  from both the host and device halves. Known limit, disclosed in the gate: a `__constant__ float
  T[64];` module table still does not extract — the shared C++ tags constant pattern keys on
  `const`/`constexpr`, not the `__constant__` qualifier (plain `constexpr` constants in `.cu`/`.cuh`
  do extract). Gate: `test/cudacheck.sh`.
- **Qualified-call resolution across C++, Rust, C#, TypeScript, JavaScript, Java and Objective-C.**
  C++ gained qualified calls of three or more segments and explicit-template calls at any depth (with
  cast exclusion), canonically precise; Rust gained scoped, turbofish and `Self::` calls with a real
  canonical tier and a file-module guard; C# gained the `?.` family; TypeScript, JavaScript and Java
  gained qualified `new`; Objective-C reached field parity. Canonical multi-match now feeds the
  ambiguity accounting rather than being silently resolved, in every language.
- **Go qualified calls are honestly rejected and fenced** rather than half-resolved.
- **Metal Shading Language (`.metal`) is indexed**, parsed with the C++ grammar and C++ tags rather
  than a separate grammar. *(Measured on 45 real shaders, 864 KB, before adopting: ERROR-node byte
  rate 0.811% under the C++ grammar vs 12.3% under the C grammar — 15× worse; real C++ in the same
  repository: 0.000%. All 249 distinct entry points in that corpus are captured: 663 definitions,
  6,283 call references.)* `.metal` maps to the C++ language rather than a language of its own,
  because MSL and its C++/Objective-C++ host share one call namespace through dual-compile headers —
  which is the entire point of indexing shaders. *Known residual, documented rather than hidden:* an
  anonymous `enum : uint { … }` recovers as a named enum, minting 18 junk `t="type"` symbols named
  `uint` across those 45 files, 0.04% of that repository's 47,074-symbol index.
- **Module-level settings constants are first-class ranked `var` symbols in TypeScript, JavaScript,
  Rust, Ruby, Java, C#, C and C++** (the r3 head-to-head's q10 loss — a settings/feature-flag table
  in those languages previously contributed zero rankable symbols, so `--for` structurally could not
  surface it). Scoped to settings-shaped constants, not every literal: module/file/namespace-level
  capture only, gated on SCREAMING_SNAKE names for the convention-based grammars (Rust `const`/
  `static` items are constants by construction and are taken as-is). Python (case-blind module
  assignments, vendored upstream) and Go (CamelCase consts) were already captured and are unchanged
  — the r3 audit's "not extracted at all" reading is corrected in that report's addendum. Gate:
  `test/constcheck.sh`, written red-first against the pre-fix binary (18 red assertions at
  b6068c3).
- The current set: C++, C, Objective-C/Objective-C++, Metal, Python, TypeScript, JavaScript, Java,
  Ruby, Bash, Go, Rust, Swift, C#, plus JSON configuration keys.

### Added — output shaping, honesty and paging

- **`counts_floor="1"`** on `--callers` / `--callees` / `--uses` / `--impact` / `--edit-check` and
  further surfaces. Every such count is a **floor, never a total**: the call graph is extracted from
  source text by name, so dynamic dispatch, callbacks and function pointers, macro-generated call
  sites, and declarations that parse without a call expression contribute no edge. **Read a 0 as
  "none found", never as "none exists".** Each verb's legend also states its counting *unit* — those
  five count distinct (caller, callee) pairs, while `--uses` counts call sites.
- **Generated documents rank last in `--recall` by default.** A document that declares itself
  generated in its first lines, or is both ≥5× the median document's size and mostly fenced quoted
  output, is demoted — a capture that quotes every term otherwise wins every query on lexical match
  alone. It is never dropped: it still wins when nothing else matches, says why on its own line, and
  the header tallies how many were demoted.
- **One paging vocabulary across the verbs that page** — `--limit=N` and `--offset=M`, with the verbs
  that cannot page refusing rather than silently ignoring them.
- **`--token-budget=N` has two documented personalities.** On the default map, `--query` and
  `--recall` it is a CI **gate**: exit 3 if the emitted document's estimated tokens exceed N, with
  nothing of the artifact reaching stdout — only a record naming what was withheld against the budget.
  On `--for`, `--pack-task` and `--from-trace` it **shapes** instead, overriding that lens's own
  default payload budget, always exit 0. The estimate is calibrated against a public tokenizer,
  never exact.
- **`--max-tokens=N` shapes the map to fit** a deliberately conservative byte ceiling and discloses
  both the asked-for N and the honoured byte figure. Because the ceiling and the gate are measured in
  different units, the same N on both flags is not a tautology — and the shaped map says
  `over_ceiling=1` rather than overshooting in silence when even one symbol exceeds the floor.
- **`--order=stable | important-first | important-last`** is the canonical emit-order flag. `stable`
  gives path/ID order for provider KV-cache hits across re-runs; `important-last` puts the
  highest-ranked content at the end for recency-biased readers. Large default maps auto-flip to
  `important-last` past roughly half of a nominal 32K window unless the mode is given explicitly.
- **`--format=columnar` / `--format=candidates` / `--json`** alternate dialects, with an unknown value
  refusing and naming the legal set.
- **Did-you-mean on every selector**, computed as a real edit distance: a `name("X")` literal or a
  `--callers=SYM` that matches no indexed symbol **refuses** with a suggestion. A typo is not a
  `count=0`; a query whose names all resolve but that selects nothing still reports `count="0"`,
  because that is a measurement.
- **`--version` / `-v`** prints the version plus compiler id/version and build type. The version
  string has exactly one source of truth (the CMake project version), and drift between the printed
  and the declared version is gated.
- **`changed="N"` in the `--map-diff` header** — the teleport-seed file count, so a caller can tell a
  real diff run from a clean-tree or no-git degrade without shelling out to git a second time. Reads
  `0` on a clean tree, and is omitted on every other verb so it costs nothing.
- **`est_tokens="N"` on shaped `--for` output** so the delivered bundle's fit is checkable.

### Added — architecture, quality and structure

- **`--metrics`, `--deps`, `--hotspots`, `--clones`, `--cochange`, `--lint`, `--lint-rules=DIR`,
  `--communities`, `--community=ID`, `--zoom`, `--seams`, `--owners`, `--dead-code`, `--report`,
  `--mermaid`, `--tree`, `--html[=FILE]`** — complexity × churn hotspots, duplicate bodies, hidden
  co-change coupling, AST lint with user-supplied rules, call-graph modules and their nested zoom,
  untested cross-module seams, ownership and bus-factor risk, and a self-contained force-directed
  HTML call graph with no CDN.
- **`--color-by=MODE`** sets the initial node-colour lens of the `--html` page — `lang`
  (default), `community` (Louvain module), `cx` (cyclomatic, fixed thresholds), `churn`
  (per-file git commits, 18-month window), or `tested`. The page embeds all five lenses
  and keeps a live selector; when no git history exists the churn legend says so instead
  of painting zeros.
- **`--arch=RULES`** with a committed baseline gates layering violations in CI.
- **Multi-root workspaces**: `ripwire dir1 dir2 [dir3 …]` merges 2..16 checkouts into one labeled
  graph. Cross-root edges are created **only on explicit evidence** — a path-resolved include or
  import, or an FFI binding — so same-name symbols in unrelated repositories stay unlinked. Root order
  on the command line is irrelevant. The single-root verbs (`--quality-delta`, `--test-gate`, the
  eval family, `--arch` baselines, `--pr-context`) stay single-root; run them per root.
- **`--export=cc.json:FILE`** and **`--index-out`** write the index out for reuse; **`--scip=FILE`**
  overlays a precise SCIP index where one exists, and a missing file degrades honestly rather than
  failing.
- **`--batch=FILE`** answers several lookups in one round trip.
- **`--note-add="SYM_or_path: text"`** commits a gotcha to `.ripwire_notes`, auto-surfaced whenever
  `--for` or `--expand` later emits that symbol; `--notes` lists them.
- **`--doctor`** diagnoses a stale binary, a stale cache, or a missing tool.

### Added — MCP server and agent wiring

- **`ripwire wrap <agent>`** prints the recipe to wire the tool into a coding agent as an MCP server.
- **30 MCP verbs**: 15 read verbs, 12 flagship-reflex verbs, and 3 edit verbs. Each is a thin front
  door onto the same computation *and the same renderer* as its CLI sibling — one output shape, two
  surfaces. `find_referencing_symbols` is kept and documented relative to `impact` and `uses` (1-hop
  calls only; `impact` is the full transitive radius, `uses` also catches read/write/import sites).
- **`--scan-skill=FILE` / `--scan-skills=DIR`** scan agent skill files for prompt-injection,
  exfiltration and path-traversal shapes before you install them.

### Added — evaluation instruments

- **A held-out retrieval eval** (`bench/recalleval/`) with a published labeling protocol: every gold
  label was authored by *reading the source*, never by transcribing the ranker's own output, so the
  eval is allowed to say the current ranker is wrong. `--eval`, `--eval-retrieval`, `--eval-stray`
  and `--eval-skills` run the instruments from the binary.
- **A differential argv harness** that replays a large fixed set of command lines against two binaries
  and requires every diff to be provably intended.
- **A Linux hardware-counter backend for the self-profiler** (`-DRIPWIRE_PROFILE=ON` builds only),
  behind the same one-surface contract as the existing Apple Silicon kperf/kpep backend: one
  `perf_event_open` group per thread, **pinned** so the kernel never multiplexes it — a reported delta
  is a raw truth or the column is absent, never a silent scale — read whole in one syscall, and
  `exclude_kernel` so the stock `perf_event_paranoid=2` admits it without root. Where the kernel
  exposes no PMU at all it arms software counters rather than going dark — see the vPMU-less entry
  below — and degrades silently to plain timing only when the kernel offers nothing whatsoever.
  `test/pmccheck.sh` asserts whichever arm (active/inactive) the
  machine can express; see `bench/PROFILE.md` for the availability and validation story.
- See `docs/EVALS.md` for what each instrument measures and every published number's provenance.

### Changed

- **BREAKING (build): the default build is architecture-neutral.** It previously hardcoded
  `-O2 -mcpu=apple-m1 -ffast-math -fno-finite-math-only` unconditionally, which was a hard
  configure/compile failure on any non-Apple-Silicon target — Linux x86-64 and aarch64, Intel macOS,
  any cross build — because clang rejects `-mcpu=apple-m1` as an unknown target CPU. `-mcpu=apple-m1`
  is now applied only when configuring on Apple Silicon; elsewhere the default is plain
  `-O2 -ffast-math -fno-finite-math-only`. `RIPWIRE_NATIVE=ON` (`-march=native`, a dev-machine opt-in)
  is unchanged, as is the PageRank no-reassociation contract and the sanitizer target.
- **x86 SIMD kernels, output-identical.** The `dynamic_map` per-node rank scan and `FixedStr`'s
  `operator==` now compile to SSE on x86_64, alongside the NEON kernels that already existed on
  aarch64 — same count-of-true-lanes contract, no node-layout, width or API change, and a portable
  scalar path everywhere else. `test/dynmapsimdcheck.sh` proves SIMD-vs-scalar parity under the full
  sanitizer set and **fails a scalar-only build on a SIMD architecture**, so the gate cannot pass by
  measuring nothing.
- **x86 radix byte-histogram kernels, output-identical.** The radix sort's contiguous-key histogram
  fast paths (uint32/uint64/float, `src/infra/radixSort.inl`) now compile to SSE2 on x86_64 — the
  same one-wide-load-then-byte-spill shape as the NEON kernels that already existed on aarch64, with
  the IEEE sortable-word flip done in SIMD for float. Same histograms bin-for-bin, scalar path
  everywhere else (including big-endian NEON). *Measured (min-of-15 ns/key, x86_64 via Rosetta 2 on
  an M-series host — a translation proxy, not real x86 silicon — `-O2 -DNDEBUG`, 4K/64K/1M random
  keys):* float 1.44–1.52× over scalar; uint32/uint64 within ±10% (a wash — kept for backend
  uniformity, at no measured cost). An AVX2 variant (32-byte load, same spill) measured *slower*
  than SSE2 under the same proxy (0.86–0.94×) and was not shipped; re-evaluate on real x86 hardware
  before adding it. `test/radixsimdcheck.sh` proves SIMD-vs-scalar parity against an
  independently-formulated histogram oracle under the full sanitizer set, **fails a scalar-only
  build on a SIMD architecture**, and on Apple Silicon runs a second cross-compiled pass under
  Rosetta so the SSE2 kernels are gated on the machines this repo is developed on.
- **sparseCsr math kernels join the x86 port.** The CSR `blockReduceDot` / `scaleVec` / `spmvRow`
  float kernels — NEON-only until now, silently falling back to scalar on x86_64 — compile to SSE2
  (mul+add: SSE2 has no FMA, so x86 rounding differs from arm64 while each platform stays
  bit-stable run-to-run, which is what the determinism contract requires). `test/dynmapsimdcheck.sh`
  grew a third parity arm — an exact-integer regime whose sums are exact in every association
  order, so lane and tail bugs surface as bit-exact mismatches with no tolerance band to hide
  behind, plus a tolerance-band random regime and a known-eigenpair check — and its non-vacuity
  banner now covers these kernels, so a scalar-only x86 build fails instead of passing vacuously.
  Found by sweeping `__ARM_NEON` sites rather than porting from the feature list; the radix-sort
  byte-histogram fast paths are the one remaining NEON-only site (identical behavior either way —
  a perf follow-up, bench-gated).
- **BREAKING (output): canonical symbol IDs corrected.** A parse-recovery artifact published a
  function's *return type* as its class scope. *(Measured on one repository: 80 wrong canonical IDs in
  ordinary C++ corrected, plus 5 newly-correct IDs where the real enclosing namespace took over.)*
  Anything scripted against the old IDs will see different values. Valid C++ never triggered the
  guard, so clean parses are unaffected.
- **BREAKING (caches): parser-version bumps invalidate warm caches.** Several extraction changes moved
  the parser version, so an upgrade costs one cold re-parse. The on-disk record *shape* did not
  change, so the cache format version did not move.
- **Graph shape: C-family `#import` now produces an include edge** — the edge that links a shader to
  its headers. `#pragma`, `#error` and `#warning`, which share the same parse node type, are excluded.
  `#include` and `#import` share one path extractor so they cannot drift apart, and a trailing comment
  on the directive line no longer leaks into the resolved path.
- **`--test-gate` obligations are computed per changed *symbol*, not per changed file.** A change that
  owns one symbol inside a 3,000-line file is no longer charged that whole file's test obligations.
- **Ranking: fixture and generated-content paths are de-prioritized.** A measured change, published
  with its held-out numbers in `docs/EVALS.md`, not a hand-tuned weight.
- **`--map-diff` documentation corrected.** The help text and README claimed it filtered to symbols
  changed against git HEAD. It never did: it emits the **full map, re-ranked with a PageRank teleport
  toward git-changed files**, so every file can still appear and a clean tree is byte-identical to the
  default map. `--pr-context` is the actually-filtered only-changed-files report. *(No code changed;
  expectations do.)*
- **`--detail=N` is now accepted with `--flags`, `--stray-content` and `--whereis`**, where it lifts
  the display cap — the same meaning it has on `--for`. It was previously rejected by the
  companion-flag guard.
- **`--query=TERMS` is relabelled "raw BM25 ranking (debug); use `--for`"** — fully functional, no
  longer presented as the primary retrieval entry point.
- **`--order` supersedes `--stable`, `--most-important-last` and `--no-auto-order`**, which remain
  fully functional as hidden aliases and print a one-line stderr deprecation the first time they are
  used. `--no-stable` is unrelated and untouched.
- **`--pack-top-n` and `--pack-budget-bytes`** behave unchanged but now print a stderr line naming
  `--pack-task` and `--detail` as the superseding one-call flags.
- **`--anchor` and `--cochange-boost` are negative-result experiments** — their own records show no
  confirmed recall lift. Both are dropped from `--help` and refuse with an "experimental" message
  unless `RIPWIRE_DEV=1` is set, keeping them reachable for evaluation work without advertising them
  as supported surface.
- **MCP tool count grew to 30**; the `flags` verb gained an optional `symbol` argument for the flip
  view, deliberately an argument on the existing verb rather than a new verb.
- **`install.sh` no longer hardcodes a Homebrew prefix**, which was wrong on Intel macOS and on any
  machine without Homebrew. It detects `brew --prefix` when brew is on `PATH`, honours an explicit
  install-prefix override, and otherwise falls back to `~/.local`. *(Existing installs may land in a
  different prefix than before.)*
- **Corrected performance claims.** A frequently-quoted "75× warm re-runs" was the incremental cache's
  *parse-phase* figure quoted without that qualifier; end-to-end warm command latency measures
  **8.2×** *(large private C++ corpus, 2,340 files; historical private corpus, not publicly
  reproducible; measured 2026-07-22)*. An unlabelled "`--edit-check` ~26 ms" was corpus-specific; the
  labelled figures are **43 ms at 592 files** and **114 ms at 2,340 files**.

### Fixed

- **The self-profiler's Linux counter backend no longer goes dark on vPMU-less machines** — which is
  most cloud VMs and CI boxes (`src/infra/profilePmc.h`; visible only under `-DRIPWIRE_PROFILE=ON`).
  Two defects, found and fixed live on an x86 Xeon VM whose kernel refuses every hardware event with
  `ENOENT`: (1) the documented per-event graceful skip did not apply to the group *leader* — if the
  first event (`cycles`) failed to open, the whole backend went inactive even when later events would
  have opened; leadership now falls to the first event that actually opens. (2) The event table was
  hardware-only, so a PMU-less kernel had nothing to offer; two `PERF_TYPE_SOFTWARE` rows —
  `task-clock` (on-CPU ns) and `page-faults` — now trail the table. They cost no hardware counter
  slot on bare metal and keep per-scope counter columns alive on VMs, under their own names, never as
  a stand-in for hardware counts. The over-budget shrink loop also now drops the last *PMU-consuming*
  event rather than blindly the last row (dropping a software event can never make a pinned group
  fit). Gate: `test/pmccheck.sh`'s inactive arm now additionally proves the kernel offered no counter
  at all — the arm that used to pass vacuously on VMs fails on the old code and exercises the live
  path on the new. *(Measured on the 2-vCPU VM: single-thread scopes' `task-clock` agrees with the
  independent wall column to 0.05–1.6%, and the parse pool's wall-vs-task-clock gap put a number on
  CPU oversubscription — ~36% of the parse phase's wall time was spent off-CPU.)*
- **Rust whole-impl span** — an `impl` block's span covered the whole block, minting phantom clone
  reports.
- **Merge-aware churn.** The churn walks now follow merges, so a history landed through merge commits
  is no longer under-counted.
- **False zeros closed across the count surfaces**: a count that cannot be a total is labelled a
  floor, and a count whose unit differs from its neighbours says so, on every verb that emits one.
- **Host attribution is innermost-wins.** Plain span intersection could credit a 40-line function
  above a 3-line one as the host of the same `#if` region (tree-sitter definition extents over-reach
  in preprocessor-heavy Objective-C++). Hosts are now the definitions wholly inside the region plus
  the *innermost* definition containing its opening line — the same rule `--grep`'s `in=` uses, so a
  flip host and a grep hit can never disagree.
- **Gate shadowing.** A file that declares its own constant of the same name shadows the gate's, as
  normal C++ scoping requires. Without this, short house-style names cross-wired: *measured on one
  repository, a weapons header's `constexpr float kSpeed` / `constexpr int kTurns` contributed six
  phantom branch sites and four phantom hosts to an unrelated gate.* The value lane now also runs on
  C-family source only — an extension denylist had previously let a committed HTML report that merely
  quoted a gate name through.
- **`--flags` no longer reports gates from nested worktrees or build output as the repository's own.**
  The second directory walk that `--flags` needs (CMake files are never ingested) disagreed with the
  crawl about what counts as source. *(Measured: a stale worktree copy inverted a real option's
  reported default.)*
- **Ingest robustness.** Large or degenerately-nested JSON is skipped with a stderr note: the JSON
  lane indexes configuration keys, and a big or `[[[[…`-nested file is data or a test corpus — the
  former explodes the symbol table, the latter drives tree-sitter's error recovery superlinear
  (43 s measured on a 100 KB torture file). Both were found live by benchmarking against real
  upstream repositories.
- **CRLF-encoded files** are handled identically to LF in the flag value lane.
- **Reproducible dependency pinning.** All 15 fetched grammar, tree-sitter and test-framework
  dependencies previously pinned mutable tags, which can be force-moved server-side. Every one is now
  pinned to the commit SHA that tag resolved to, with the human-legible tag kept as a trailing comment.

### Security

- **Credential redaction is on by default** — credential-shaped literals are removed from emitted
  bodies and signatures unless you opt out with **`--no-redact`**. There is no opt-IN spelling,
  because the behaviour is not opt-in. The redaction fixtures that necessarily carry synthetic
  credentials are enumerated in `test/README.md` and enforced by a gate.

### Known limits

These are stated, not hidden, and each is measurable from the output itself:

- **Call edges are heuristic and name-based.** Dynamic dispatch, callbacks, and macro-generated call
  sites produce no edge. A high-ranking symbol with no call edges may be a dispatch hub, not a leaf.
- **`amb="K"`** on a symbol means K of its calls hit a name with multiple definitions and the resolver
  guessed. The header's `ambiguous=N` is the call-graph completeness gauge — read the source when
  which-target matters.
- **Token estimates are calibrated, never exact.** The `--pr-context` estimate in particular is known
  to under-charge relative to a real tokenizer; treat it as a lower bound.
- **Binary-doc extraction (`markitdown` bridge) is uncached and re-runs every ingest.** The doc
  post-pass is deliberately outside the parse cache, so on a machine with `markitdown` installed a
  corpus containing PDF/PPTX/DOCX/XLSX pays the full subprocess extraction on *warm* runs too —
  measured at ~97% of a warm run's wall (2.05 s of 2.11 s) on a 2-vCPU VM against this repository's
  own showcase PDF+PPTX, found by the self-profiler's wall-vs-task-clock gap (child-process CPU is
  invisible to per-thread counters). The extraction is a pure function of the file bytes, so it is a
  clean cache candidate; until then, the cost scales with the corpus's binary docs, not its code.
- **`--for`'s `--token-budget` shaping is not strictly binding at very small budgets** — the header
  floor (envelope, legend, verbatim task echo) is bytes no trim can shrink, and the lens labels the
  result `over_ceiling` rather than claiming a trim it did not perform.
- **Release automation has never been executed end-to-end.** The tag-triggered build-and-attach
  workflow and the release-binary installer are untested until the first real tag push.
- **The x86 64-bit-key rank kernels need SSE4.2.** `_mm_cmpgt_epi64` is not in the SSE2 baseline, so on
  a stock `-march=x86-64` build the `int64`/`uint64` specializations — including the production
  `dynamic_map<std::uint64_t, …>` instantiation — fall back to the scalar template. Build with
  `-march=x86-64-v2` or `RIPWIRE_NATIVE=ON` to light them up. Correctness is identical either way; only
  the scan width changes.
- **The Linux counter backend's *active* path has not been run against real PMU hardware.** It is
  validated for correctness, degrade behavior and the sanitizer set under x86-64 emulation and on
  PMU-less VMs, where `perf_event_open` fails and the backend goes inactive as designed — which
  exercises the inactive arm only. The live counting path awaits a bare-metal box; `bench/PROFILE.md`
  carries the probe that tells you whether a candidate machine qualifies.

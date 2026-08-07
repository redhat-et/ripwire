# Audit follow-up plan — updated 2026-08-04 (second pass)

Continuation of the 2026-08-04 audit handoff, executed on `docs/readme-frontpage`. This file records
what was completed this pass, the exact evidence, and what genuinely remains. Prior handoff text is
superseded; measured claims below name their instruments.

## Completed this pass (commit SHAs on `docs/readme-frontpage`)

- `987a1bf` — evaluator refactor per the reviewer decision: `run_one` ccx 23 → 15 (extracted
  `_codex_metrics`/`_claude_metrics`, shared by the timeout and success paths), `synthetic_fixture`
  nesting cut via `_fixture_record`. Gate first: `test/agentloopcodexcheck.sh` pins the helpers'
  behavior (verbatim JSONL retention, bytes/None degradation, trailer-drift-to-nulls) and now runs
  `analyze.py`'s self-test.
- `9ce286a` — version 0.1.0 → 0.2.0 in `CMakeLists.txt`; CHANGELOG `[Unreleased]` → `[0.2.0]`, and
  the stale "no release has been cut" preamble corrected (a `v0.1.0` tag + assetless GitHub Release
  have existed since 2026-08-02).
- `4fdaf48` — pilot-evidence-driven skill change: the evidence-sufficiency stop (find-bug) and the
  single-line-leaf-fix skip (quality-bar, change-check) are now in the FRONTMATTER descriptions the
  agent sees for free at advertisement time, not only in the 2–6k-token bodies it must pay to open.
  Gate asserts the guards stay in frontmatter.
- `ededc13` — `analyze.py` defect found by running the pilot: pairing required `resolved != None`,
  but `--evaluator none` (the documented pre-Docker mode) always records `resolved=None`, so the
  pilot analyzed as zero pairs. Pairs now form on `status=='ok'`; resolution stats print n/a over an
  honest `n_resolved_pairs` count, never a fabricated 0.0. Self-test extended first (red → green).

Gate evidence this pass: `python3 test/pargates.py . ./build/ripwire -j 6` run three times
(baseline, post-version-bump, post-skill-edits): **gates=340 pass=339 skip=1 fail=0** every time.
Determinism (byte-identical double run), `xmllint --noout`, and
`LSAN_OPTIONS=suppressions=lsan_suppressions.txt ./asan/ripwire .` all clean on the release tree.
The four "SLOWER" import-precision gate timings in the first run were cold-cache artifacts of the
fresh rebuild (rustimportprecisecheck 47.3s cold vs 1.5s warm re-run), not regressions.

Quality-delta discipline followed: the transient gating rows this pass were two deliberate-revisit
churn pairs (`run_one`/`synthetic_fixture`, then `analyze`/`pair_by_task_seed`) plus `self_test`
ccx 10 → 17 — the latter is the new gate assertions themselves (each check is an `if`); a
predicate-table refactor would trade self-test readability for a number, so it was accepted.
Acks, where used, were narrow `--ack-only=<ids>`; never bare `--quality-ack`.

## Codex CLI pilot — 6 runs, 3 repos, seed 1, 2026-08-04

Harness: `bench/agentloop/run_agentloop.py` schema v2, `--harness codex-exec`, codex-cli
0.144.0-alpha.4 (the ChatGPT.app-bundled binary; a `codex` PATH shim is required — symlinks break
its sibling-executable resolution [`codex-code-mode-host`], use an `exec` wrapper script), model
left at the CLI default (recorded as `""`, same as the prior diagnostic; the default per
models_cache is `gpt-5.6-sol`). Isolation preserved exactly: empty MCP table both arms, per-run
`CODEX_HOME`, baseline no skills, treatment only this checkout's skills.
Evidence: `/private/tmp/ripwire-codex-cli-agentloop-v2/pilot-6run.json` + per-run JSONL under
`events/`. Smoke `--live-one` first reproduced the prior baseline diagnostic within 0.15%
(170,317 vs 170,567 input tokens, 8 commands, ~56s).

| Instance | Arm | Gold-file hit | Input tokens | Output tokens | Wall | Cmds | ripwire calls |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| astropy-12907 | baseline | yes | 160,057 | 1,524 | 53 s | 7 | 0 |
| astropy-12907 | ripwire_cli | yes | 326,054 | 3,128 | 92 s | 11 | 5 |
| requests-1963 | baseline | yes | 176,049 | 3,201 | 109 s | 9 | 0 |
| requests-1963 | ripwire_cli | yes | 454,980 | 3,734 | 118 s | 16 | 2 |
| xarray-3364 | baseline | yes | 529,038 | 7,648 | 240 s | 14 | 0 |
| xarray-3364 | ripwire_cli | yes | 1,249,026 | 13,779 | 338 s | 26 | 6 |

`analyze.py`: n_pairs=3, localization-hit delta +0.00pp (parity — both arms localized 6/6),
tokens_out ratio p50/p95 **+80.2% / +105.2%**, wall p50/p95 **+40.7% / +72.1%**. `cost_usd` is
null in codex JSONL (no cost field emitted); resolution unscored (`--evaluator none`).

**Confound, disclosed:** commit `4fdaf48` (frontmatter guards) landed mid-pilot; the astropy and
requests treatment runs used pre-guard skills, the xarray treatment run used post-guard skills.
The xarray task is a multi-line feature fix, so the one-line skip guards legitimately did not fire.

### Loss taxonomy (per the treat-losses-as-evidence rule)

- **Not ranking:** `--for` ranked the gold file first in all three treatment runs, and the agent
  went from ranked output to a narrow source-range read directly (requests: cmd 2 → `sed 70,190p`).
- **Not output shape:** each `--for --max-tokens=4000` reply was ~600 est tokens. Measured directly
  on astropy: `--for --max-tokens=4000` = 1,436 B (~574 est tokens) vs
  `--adaptive --detail=1 --max-tokens=2000` = 3,257 B (~814). The prior plan's hypothesis that
  adaptive-detail would be cheaper is **wrong on this task** — `--for` is already smaller.
- **Skill policy (dominant):** mid-task full SKILL.md body reads (find-bug ~1.8k tok, reuse-first
  ~2k, quality-bar ~2.5k, change-check ~4.1k) are re-billed in every later turn's context; with
  8–26 turns that alone reconstructs most of the +27k..+720k input-token gaps. Advertisement is a
  second fixed tax: 17 skills ≈ 3.4k tokens of frontmatter per turn (measured over `skills/`).
- **Ritual expansion:** treatment runs add validation turns baseline never spends — xarray ran
  `ripwire . --quality-delta` **three times** (the converge loop working as designed) plus repo
  archaeology; 26 commands vs baseline's 14. Inside a token-metered benchmark these are
  uncompensated; the benchmark scores the patch only.

### Round 2 — the fix, attempted; INVALID, do not publish

A 2026-08-05 re-run of the two easy-task treatment runs with the guarded skills (`4fdaf48`)
produced apparently strong numbers (astropy overhead +103.7% → +8.0%, requests +158.4% → +33.3%,
localization intact, one skill read + zero ritual reads in the command streams), **but the Codex
account's usage quota ran out during the verification, so the runs are not comparable to round 1
and are NOT published** (reviewer call, this session). The raw records live outside the tree at
`/private/tmp/ripwire-codex-cli-agentloop-v2/pilot-postguard.json` with pre-guard events preserved
in `events-preguard/`; treat them as an encouraging *direction* only. The clean re-run (fresh
quota, both arms, all three instances, seeds expanded) is the first item of the next round.

### Next experiments (in order)

1. **Restructure the four hot skill bodies head-first** so a `sed -n '1,40p'` read suffices: TL;DR
   contract + stop rule in the first ~40 lines, reference detail below. Measure body-read bytes in
   the events JSONL before/after.
2. **Task-scoped skill linking** in the harness (e.g. `--skills=find-bug,efficient` allowlist in
   `prepare_codex_environment`) to measure the advertisement tax directly — keep the default
   all-skills arm as the honest "real install" condition; a scoped arm is a separate labeled arm,
   not a replacement.
3. **Benchmark-mode guidance**: decide whether quality rituals (quality-delta loops) belong in the
   benchmark prompt contract at all, or only in real-use contexts; if kept, cap the converge loop.
4. Re-run the 6-run pilot post-restructure (same seed, same tasks) and compare; only then consider
   more seeds/repos with repository-clustered analysis.
5. **SWE-bench evaluator still not installed** (no `swebench` package, Docker state unverified).
   Until then no resolve-rate claims; localization/token/wall only. `run_swebench_harness()`'s
   TODO-verify notes (CLI flags, predictions schema, report key) remain unexercised.

## Legacy temporary files — CLEANED

Measured before cleanup (matching the prior handoff): 132,246 direct `ripwire-*` files in
`$TMPDIR`, 460.4 MiB. Process validation first: the only pre-today ripwire process (a stale Aug-3
`--listen` fixture server from the `ripwire-wt-lineage` worktree, holding only a `tmp.*/http.log`)
was stopped; the live current-session MCP server (`ripwire --mcp`, started today) holds no tmp
handles and was left running. Deleted only direct FILES at depth 1 matching `ripwire-*` with
mtime > 24 h: **100,629 files, 314.3 MiB reclaimed** (find's `-delete` failed silently — the
removal needed `-print0 | xargs -0 rm -f`). Remaining 31,617 files (146.1 MiB) are all <24 h old,
created by today's own gate-suite runs — the leak is ONGOING (~31k files/day of heavy gate use):
`src/mcpindex.h:538` / `src/mcpedit.h:234` still write direct files and `quality.h`'s
`evictOldCacheFamily` evidently doesn't bound these families. Follow-up task chip filed
("Scope ripwire tmp-cache evictor to direct-file families").

## Release v0.2.0

- Version bumped in source (`9ce286a`), CHANGELOG cut, full gates + ASan green at the tag.
- GitHub CLI is authenticated again (`joyful-ii-V-I`, repo+workflow scopes) — the prior pass's
  auth blocker is gone. Topics `codex`/`openai-codex` were already applied.
- `v0.1.0` (2026-08-02, commit `c7364de`) remains as-is: tag untouched, its Release has **zero
  assets** — its workflow run's macos-x64 leg sat queued 24 h and auto-cancelled, skipping publish.
- **The first real workflow exercise found three defects, each fixed gate/evidence-first:**
  1. `d2217a4` — the `macos-13` Intel runner pool is retired (v0.1.0's leg queued 24 h → cancel;
     v0.2.0's first run identical). macos-x64 now cross-compiles on `macos-14` with
     `CMAKE_OSX_ARCHITECTURES=x86_64`; the produced Mach-O is genuinely x86_64 and runs under
     Rosetta (verified locally).
  2. `1c1d513` — both macOS legs failed compiling `ingest.cpp`: `61efd4e` turned `LexPair` from
     `std::pair` into a bare aggregate but kept `emplace_back( hash, slot )`, which needs P0960 —
     implemented only in Clang ≥ 20 (local AppleClang 21 and CI GCC accepted; CI Xcode 15.4
     rejected). Fixed with braced `push_back( LexPair{...} )`; full gates re-run green.
  3. `dda667f` — the published `.sha256` files embedded a `dist/` path prefix, so `shasum -c`
     beside the downloaded pair failed — which is exactly how `scripts/install.sh` verifies,
     breaking install-from-release. Checksums are now written with basenames from inside `dist/`.
  The tag was moved to each fix (four pushes total) — legitimate only because no release object /
  consumer existed until the final asset set; do NOT move it again now that it is published.

### Release verification (2026-08-05, run 30973658699 — all 5 jobs success)

- Release: <https://github.com/redhat-et/ripwire/releases/tag/v0.2.0> at commit `dda667f`.
- 8 assets: `ripwire-0.2.0-{macos,linux}-{arm64,x64}.tar.gz` + `.sha256` each (~4.4–5.1 MB).
- All four archives pass strict side-by-side `shasum -a 256 -c`.
- Native smoke test: the downloaded macos-arm64 binary reports
  `ripwire 0.2.0 (Release, AppleClang 15.0.0.15000309)` and maps `test/fixture` to well-formed XML
  (`xmllint --noout` clean). The macos-x64 binary is `Mach-O 64-bit executable x86_64` and runs
  under Rosetta.
- `scripts/install.sh` end-to-end: `RIPWIRE_REPO=redhat-et/ripwire RIPWIRE_VERSION=v0.2.0` →
  download, checksum "OK", install, `--version` correct. Its TODO(P6) default repo stays unset
  pending the fresh-history export decision.

## v0.2.1 — Linux portability patch (2026-08-05)

- Found while answering "does it run on RHEL": the v0.2.0 Linux archives (built on ubuntu-24.04)
  require `GLIBCXX_3.4.31` and die on RHEL 9 — verified on ubi9. Fix (`d2c1d51`-era commits, tag
  `v0.2.1`): the Linux release legs build inside AlmaLinux-8 `manylinux_2_28` containers with Red
  Hat gcc-toolset 14, so newer libstdc++ symbols link statically — one binary per arch for
  RHEL/Alma/Rocky 8+, CentOS Stream, Fedora, Ubuntu 20.04+, Debian 11+ (glibc 2.28 floor). A new
  `smoke-rhel` job runs the packaged tarball on ubi9 and gates publish.
- Verified: release run 31006116964 all 7 jobs green; all four v0.2.1 archives pass strict
  `shasum -c`; the published linux-arm64 asset runs `--version` + a full fixture map + xmllint on
  ubi9 and `--version` on ubi8; `scripts/install.sh` (latest = v0.2.1) end-to-end with checksum OK.
- CI-on-main was red since 2026-08-04 06:22 for an unrelated reason: `stat -f %z` (BSD-only) in
  `bench/representative_perfgate.sh` zeroed the corpus-shape preflight on GNU stat — every
  ubuntu-24.04 leg exited 2. Fixed with POSIX `find -exec cat {} + | wc -c`, verified in an
  ubuntu:24.04 container. (The Aug-4 recall-floor and deck NUL-byte failures were already fixed on
  this branch.) The v0.2.0 tag/assets are left untouched.

## Remaining launch work

- Skill-body head-first restructure + pilot re-run (experiments 1–4 above).
- SWE-bench Docker evaluator install/verify before any resolve-rate claim.
- Turn this audit trail into a concise public issue/roadmap; outreach only after
  install-from-release is verified end-to-end.
- Do not convert more shell gates to C++ without a measured payoff (sampled shell-launch share was
  ~0.09–3.1% of gate time).

---

## 2026-08-06 — readability/quality waves: state, and the handoff

**HANDOFF NOTE.** Written mid-flight so another session can pick this up cold. Current integration
branch is **`integration/all`** (worktree `.claude/worktrees/integration`). Nothing is pushed. The
full research record — every citation existence-verified — is **NOT in this repo** (`ripwirepubliccheck`
arm 6a blocks `DESIGN_*` filenames); it lives in the private ledger at
the private ctxpack ledger under `research/2026-08/` (filename intentionally not spelled here — arm 8), with an untracked working copy at the
ripwire root. Read it before extending any of this; §-numbers below refer to it.

### Landed on `integration/all` (suite green: 352 gates, 349 pass, 3 skip, 0 fail)

Naming lens (8 rules) · atoms-of-confusion pack (7 C-family rules) · `--readability` (Posnett/
Halstead/entropy) · `--ensemble` (the family join) · `--naming-calibration` · `--context-ratio` ·
`--nonlocal-state` · `--field-affinity` · Clio/MVG co-change refinements + citations · LTO/PGO with
the dev/release split · import-container capture (`kParserVer` 40) · the durable quality ledgers
un-gitignored.

### In flight when this was written

- **Wave 3** (workflow `wf_0eab98ba-d7d`): name-informativeness, comment-coherence, DMM, then the
  single quality-panel command, then a skills rewire, then a land phase. Branches exist at base.
- **`fix/ensemble-availability`** (separate thread): the `confusion` family reports itself as
  MEASURED on corpora where it cannot fire. Real honesty bug — atoms are C-family only by design, so
  on a Rust/Python tree the family was never applicable and silence reads as a clean bill of health.

### Next, in order (the reasoning matters more than the list)

1. **Finish wave 3 + the availability fix, then the README.** The README plan is settled: give the
   "writes better code" bullet a NUMBER (it is the only bullet without one — that is why it reads
   weakest), lead "saves tokens" with the head-to-head win–loss records (17–2 vs repowise, 16–2 vs
   Aider — already in the README below the fold, invisible up top), lead "goes faster" with the WARM
   number and re-measure cold on the LTO/PGO build, and add a fourth bullet on agent code rot. Then
   the line worth more than any of them: *every number above is re-derived by a gate; if the prose
   and the measurement disagree, the build fails.*
2. **"What we refused to ship, and why."** The anti-fad argument is not a citation list — it is a
   graveyard, and ours is unusually good: the withdrawn naming rule (measured INVERTED — it flagged
   the best names in the tree), Halstead difficulty/effort (refuted 1982, still shipping elsewhere),
   the Maintainability Index (constants fit to one 1980s dataset), cross-language atom porting
   (transfer empirically falsified), and 1.1M compiler remarks that justified ZERO source edits.
   `docs/LINEAGE.md` already separates *folded* from *surveyed*; **"measured and rejected" is a
   natural third class** and inherits the same honesty rule and gate.
3. **The tool-vs-command roadmap.** A command answers a question you already know how to ask; a tool
   helps you ask the right one. Four properties to deepen, cheapest first:
   - **Be a filter, not a replacement.** Accept `rg --json` on stdin and annotate each hit with its
     enclosing symbol, callers, tested state, hotspot standing. The `--from-trace=-` stdin pattern
     already exists — generalize it. Cheapest change with the largest positioning effect: it answers
     "why not just grep?" with *use both, here is the pipe*.
   - **State.** Every call is independent even when warm; an agent re-establishes intent on every
     verb. A TASK HANDLE held by the MCP server ("I am working on X" once, subsequent verbs rank
     against it) compounds across a session and is something a plain CLI structurally cannot do.
   - **Actionable limits.** `amb="3"` truthfully says the resolver guessed. It does not say WHICH
     calls or what would resolve them. Turn disclosure into a next action.
   - **Close the loop.** §9.2 Tier A: where the correct replacement is derivable FROM THE CORPUS
     (abbreviation inconsistency, synonym unification, convention normalization) propose the fix.
     That is the line between a gate and a collaborator, and the only band where auto-correction is
     safe, because consistency has a computable target and quality does not.
   - (Expensive, own wave) **Model depth** — the graph has no data flow, which is why
     `--nonlocal-state` must report floors. Today's include fix bought +23–37% edges on real corpora;
     model completeness pays disproportionately.
4. **Deferred Tier B**, to be judged by the calibration harness rather than assumed: `$gram`
   surprisal, DepDegree, change entropy.

### Traps a fresh session will hit

- **Merge conflicts are always additive bookkeeping, never real disagreement.** `test/regression.sh`'s
  single absorb-loop line (rebuild the union from BOTH sides — a naive insert mangles the `; do`
  token), the gate count in `docs/EVALS.md` (3 places, DERIVED by manifestcheck), `kTotalFlagArms`
  (the `static_assert` beats your arithmetic — it caught three wrong counts in one session), the
  README flag count and `present/deck5`. In `src/cli.h`/`main.cpp` KEEP BOTH sides: taking one whole
  hunk silently dropped a `Config` member and shipped a flag that parsed but never worked.
- **Three gates flake on machine load, none is a real failure**: `editcheckcheck` (100 ms warm
  budget), `gitstampcheck` (compares a SHARED cache-dir byte total between two runs — that is shared
  mutable state in a gate, not a timing budget), `mergescoutcheck`'s perf arm. Re-run STANDALONE and
  report both results. **A fix for these was attempted in wave 2 and never landed** — the agent
  stalled waiting on a background suite run. Still open.
- **Never copy a number from prose you did not re-measure.** A wrong denominator (159 of 171 → really
  159 of 217) survived review here and was caught only because an agent re-measured instead of
  trusting the doc. The Clio precision bound moved DOWN after the include fix, not up, for the same
  reason — measure, then write what you measured.
- `claude/unruffled-yalow-24aaa8` is **superseded** — HEAD fixed that litter by sharding and
  deliberately never evicts live locks. Do not merge it.

### UPDATE — `fix/ensemble-availability` landed (`ab3f26b`)

Merged clean into `integration/all`; builds clean. The fix went wider than the reported defect:
`confusion` was the symptom, but the same class of lie appeared three more times —
(a) with an **empty eligible set** all four families sat silent while `unavailable=""` claimed all
four were measured; (b) `unavailWhy` was a single `const char*`, so with two families unavailable at
once (a non-git Rust tree is exactly that) one reason was **silently overwritten** — truthful about
*what*, lying about *why*; (c) `lexical` has a real precondition too (the naming pack skips
Json/Markdown/Unknown), implemented though near-unreachable on today's language table.
`structural` was **verified** to have no precondition rather than assumed to have none.

Availability is now decided per corpus from what was indexed, calling each pack's OWN predicate — no
second copy of the language list anywhere. `cfiles=`/`cscope=`/`lscope=` on the root make the verdict
auditable from the output instead of taken on trust.

Gate design worth imitating: arm (C) requires the family to actually FIRE on C, so a "fix" that
marked everything unavailable would fail; the mutation arm adds exactly ONE C file and requires the
verdict and `of=` to move — it asserts a measurement, not a constant.

**NEW TRAP, add to the list above:** `git stash` → rebuild → `git stash pop` does **not** trigger a
cmake rebuild, leaving a stale `build/ripwire` that silently emits base-binary output. This produces
a FALSE GREEN in any A/B comparison — it was caught only because a differential showed *zero*
difference where there had to be some. Build A/B binaries in genuinely separate worktrees and `cmp`
them before trusting any before/after measurement.

Still open at 97% budget: wave 3 (`wf_0eab98ba-d7d`) was mid-Metrics phase — name-informativeness,
comment-coherence, DMM, then the panel, skills and land. Nothing pushed.

## 2026-08-06 (later) — four follow-up tasks: skills audit, stop-rule audit, Tier-A verb, README

**All four DONE, gate suite green (358 gates, 355 pass, 3 skip, 0 fail), nothing pushed.** Worked
straight in `.claude/worktrees/integration` (not a new branch) since the prior wave's work was
already merged into `integration/all` before this session started.

1. **Skills audit.** Found the prior wave's `feat/skills-quality-panel` merge had already done most
   of the rewire — `--quality-panel` documented as THE SINGLE COMMAND in `ripwire-fresh-eyes`,
   cross-referenced from `ripwire-quality-bar`/`ripwire-router`, all the new verbs (`--context-ratio`,
   `--nonlocal-state`, `--comment-coherence`, `--naming-calibration`, `--dmm`, `--ensemble`,
   `--field-affinity`) already routed. Real gap: `ripwire-quality-bar`'s own frontmatter description
   never mentioned `--quality-panel` at all (the thing driving BM25-desc routing) — fixed. All skill
   gates (`skilltruthcheck`/`skillinstallcheck`/`skillevalcheck`/`skillevalsplitcheck`) green before
   and after.
2. **Stop-rule audit.** Timed the "first call" of every skill with a stop rule on this repo, warm:
   `--edit-check` ~73ms, `--pr-context` ~202ms, `--quality-delta` ~585ms, `--exemplar` ~94ms,
   `--seams` ~28ms, bare report ~28ms — all sub-second. Loosened the two highest-traffic rules that
   were gating a genuinely cheap call: `ripwire-quality-bar`'s "one-line fix skips the pass" now
   means skip the LOOP (drill-down/ack/dmm), not the one-shot `--quality-delta` call itself;
   `ripwire-change-check`'s "one-line fix skips this skill" now requires `--edit-check=SYM` (~ms)
   first, only a genuine `unchanged` result earns the full skip. Kept `ripwire-orient`'s "stop at the
   first rung" (already asymmetric-safe — it says stop AFTER a cheap call answers, not before one),
   `ripwire-reuse-first`'s edit-vs-new-symbol distinction (the skill's premise genuinely doesn't apply
   to a same-symbol edit), and the "one call, don't stack the whole battery" rules in
   `ripwire-fresh-eyes`/`ripwire-write-tests`/`ripwire-navigate`/`ripwire-find-bug` (post-answer
   ceilings, not pre-answer skips — the safe direction of the asymmetry).
3. **Remediation gap — built `--naming-consistency`, a real new C++ verb** (not just a docs pass —
   no Tier-A infra existed anywhere; `naminglens.h`'s `tokensAgree` was sitting there with "no caller
   today" for exactly this). Scoped to the SAFEST Tier-A category only: convention normalization
   (case style), deliberately not abbreviation/synonym unification — those need a dictionary or
   semantic judgment, which is the exact trap that produced the withdrawn `naming-body-mismatch`
   rule. Votes the corpus's own dominant case style (camel/pascal/snake/screaming) per
   `(language, kind)` group, decided only past a 20-name sample floor AND 90% agreement;
   off-convention names in a decided group get `propose=`, their own subtokens mechanically
   recombined — no dictionary, no invention. Lens, exit 0 always; `propose=` is explicitly a
   suggestion, not a safe-to-apply rename (that needs `--uses` + the §9.3 contract, not implemented
   here). New file `src/namingconsistency.h`; gate `test/namingconsistencycheck.sh` (14 assertions
   incl. a mutation arm that flips 10/27 names and proves the verdict moves — not hardcoded).
   Dogfooded on ripwire's own `src/`: correctly calls camelCase dominant (1939/2111, 91.9%) and
   flags real PascalCase outliers (`SpanIndex`, `DoNotOptimize`, `UnionFind`, …) — some of which are
   deliberate (Google-benchmark-style helpers), which is exactly the kind of judgment `propose=`
   leaves to the reader rather than auto-applying.
   - **Refactor along the way**: `htmlexport.h` had a private `langLabel()` duplicating exactly what
     the new verb needed — moved to `model.h` as `langTag()` next to `symTag()` (the existing
     canonical-label pattern), both old call sites updated. Reuse-before-reinvent, not scope creep.
   - **Wiring touched more than the verb**: `kTotalFlagArms` static_assert (164→165, per the standing
     trap warning), TWO separate paging-honored-verb lists (`kPagingHonoringVerbs` runtime string AND
     a hand-maintained `--help` HONORED-by prose list — `testgatepagecheck.sh` PC-2 catches them
     drifting apart), `docs/EVALS.md`'s 3-place gate count (352, via `manifestcheck.sh`),
     `docs/COMMANDS.md` regenerated, and the new file had to be `git add`ed before
     `ripwirepubliccheck` arm 7 (include-closure) could see it — untracked files are invisible to
     `git ls-files`, which is what arm 7 walks.
   - **Line-number drift, exactly the trap the notes above warn about**: adding lines to `main.cpp`
     shifted `readmeexamplecheck`'s pinned `--callers=rankGraphTeleport` example by +9 lines
     (9239→9248, 9275→9284) — re-derived from a live run, not hand-arithmetic'd.
4. **README, four numbers re-measured on this exact tree** (not copied from prose): panel shortlist
   4,866 eligible → 402 at 2-of-6 agreement (8.3%, freshly run); cross-family correlation +0.168 max
   pooled φ (already current in `docs/EVALS.md` §9.9.2, dated 2026-08-06 — verified consistent with a
   spot-check on `src/` rather than re-running the full 5-corpus study); head-to-head win–loss records
   (17–2 repowise, 16–2 Aider — already current, just led with instead of buried) and cold-parse
   timing (self-measured on this repo: 603 files, ~0.15s cold/~0.10s warm, reproducible; the existing
   1,560-file/~1s number is a private, non-reproducible corpus and stays labeled as such rather than
   being re-measured under a different name — see `docs/OPTREMARKS.md` §5/§5b for the actual dated
   LTO/PGO study, cited rather than re-run since re-running the full PGO 2-phase build was judged not
   worth the wall-clock for a number already rigorously measured in-tree). Added a 4th opening bullet
   (agent-code-rot motivation, GitClear 2026 citations already used elsewhere in the tree) and a new
   "code-quality panel" subsection with real Halstead/Posnett/Peitek/Beck&Diehl/Chilimbi citations and
   three dogfooded proof-points (`computeQualityDelta`'s 99.6% read_ratio, `ensure_global_init`'s
   3-cell non-local reach, `MainDispatch`'s 12 field-affinity findings) — real numbers off this
   repository's own source, not synthetic examples. **Caught myself overclaiming**: first draft said
   "every number above is re-derived by a gate," which is false (only the flag count actually is) —
   corrected before it shipped.

**Traps hit this round, worth adding to the standing list**: (a) a brand-new `.h` file must be
`git add`ed before `ripwirepubliccheck`'s include-closure arm can resolve `#include`s to it — an
untracked file reads as a closure break, not as "new file, ignore." (b) There are TWO paging-honored
verb lists in `src/cli.h` (the runtime refusal string and a separate `--help` prose list) —
`testgatepagecheck.sh` is the only gate that catches them diverging; a change to one without the
other passes every other gate. (c) `%` in a `--help` string is a live printf format spec — `90%
agreement` in help text needs `90%%` or the build warns and the literal `%` is swallowed.

Not attempted this round (out of scope for the four tasks given): PLAN item 2 ("what we refused to
ship, and why" — the anti-fad graveyard section) and item 3's remaining tool-vs-command roadmap
bullets (filter-not-replacement, task-handle state, actionable `amb=` limits). Also not attempted:
indexing local variables (raised mid-session as a real gap — `naminglens.h`'s own eligibility rule
explicitly excludes function-local names, "params and locals are not indexed," so a 1000-line
function's 50 poorly-named locals are invisible to every naming rule today, and there is no
local-variable-count metric at all — a legitimate future-wave candidate, not touched here).

## 2026-08-06 (evening) — local-variable-indexing plan, orchestrated

Produced by a 11-agent Workflow (survey per language family → design → 3-way adversarial review →
merge), NOT implemented — a plan only, per the local-variable gap flagged in the section above.

**Process note, worth recording so it doesn't repeat.** The workflow's agents defaulted to the
session's PRIMARY working directory (a separate checkout on branch `docs/readme-frontpage`) rather
than this integration worktree, because the launch prompt used relative paths (`src/naminglens.h`)
with no explicit root. The primary root has NONE of this
session's work — no `naminglens.h`, no `namingconsistency.h`, no `fieldaffinity.h`. **Always pass the
absolute worktree path explicitly in a Workflow agent's prompt** — relative paths silently resolve
against the wrong checkout, and a background agent has no way to notice unless it independently
verifies (which this one did — see below). The design agent's own "Grounding note" caught the
mismatch, refused to invent file content, and re-fetched real `naminglens.h` text via `git show` on
`feat/name-informativeness` instead — good self-correcting behavior, but it means every line-number
citation below is grounded ~10 lines stale (the file grew between that branch and this worktree's
current `naminglens.h`, 1022 lines) and it wrongly claimed **`src/namingconsistency.h` does not
exist** — it does; it shipped earlier this same session (see above). Verified directly against this
worktree before writing this section: `checkNameShape` is at `naminglens.h:526` (plan says 515-598,
so the ~11-line drift is consistent and mechanical, not structural); `RuleSink::tallies[9]` and
`renamemine.h`'s `kRuleCount=8` position-pinning (which Open Question 3 below depends on) are
EXACTLY as the plan assumed — verified, not just trusted.

**Verdict: the design is sound, only the line-number citations and the namingconsistency.h footnote
need refreshing before implementation — not a re-plan.** `namingconsistency.h` should be read
alongside `naminglens.h` as a second, more-recent house-style exemplar when this gets built (it's the
newest lens in the tree, landed this same session, and already demonstrates the exact
legend/gate/mutation-control pattern this plan calls for).

### The plan (verbatim from the workflow's final merge, corrections above apply)

**Phase 1 — `locals` count, threaded through the existing walk.** One `std::uint32_t locals` field on
`Symbol`, populated by extending `ingest.cpp`'s existing fused-DFS complexity walk (the same one that
already computes `cx`/`ccx`/`maxNest`) — zero new tree-sitter queries, zero new indexed symbols, zero
new allocation-heavy passes. Requires a `kParserVer` cache-format bump (same commit) and a
`RuleSink`-style floor marker (`locals_floor="1"`) rather than prose-only disclosure. Gate:
`test/localscountcheck.sh` — three fixture functions with distinct hand-counted local counts (a
single-constant-stub implementation cannot pass all three), a floor-boundary fixture asserting known
declarator shapes (if-init, switch/case, catch-clause, structured bindings, lambda init-captures) are
NOT counted, a language-omission fixture proving `locals=`/`locals_floor=` are ABSENT (never `"0"`)
for a language Phase 1 doesn't cover, and a stale-cache fixture proving the version guard rejects a
pre-bump cache blob rather than silently misreading it.

**Phase 2 — gated naming predicates on local names.** Prerequisite: none further (naminglens.h is
already landed in this worktree). Deliberately breaks naminglens.h's own stated invariant ("an
un-indexed loop local can never be flagged") — stated explicitly as the point of this phase, not
hidden. A second, name-capturing walk runs ONLY for functions clearing an existing size/complexity
gate (`loc>80 OR maxNest>4 OR ccx>=15`, all three reused unchanged from `main.cpp`'s shipped
`large-function`/`deep-nesting` rules) AND `locals>=8` (new, unmeasured — Open Question 1). Captured
locals are lightweight non-owning `LocalNameFact{string_view name; line; declDepth}` records, never
promoted to `Symbol`/`NodeId`/the graph. `checkNameShape` is split into a shared
`checkNameShapeCore` (existing `Symbol`-based callers unchanged) plus a new `checkLocalNameShape`
entry point; `naming-short` additionally requires the local's own `declDepth>=2` (nested, not the
function's outermost block) — a per-local gate on top of the per-function one, added specifically
because gating only at function level reproduces the withdrawn `naming-body-mismatch` rule's failure
shape (plausible, wrong axis). Explicitly out of scope: `naming-predicate`/`naming-setter` (need a
known return type, not transferable) and `naming-confusable`/`naming-uninformative` (corpus-scale,
folding locals in risks the blow-up this design avoids).

**Phase 3 — composite finding.** A `--lint` tag (`large-function-bad-locals`, NOT a `quality.h`
`Regression` — a standing fact about the current tree has no `was`/`now` shape), firing once per
gated function when the count of Phase-2-flagged locals clears a threshold `K` (Open Question 5,
unmeasured). Both `N` (flagged count) and `M` (total locals) carry the same floor caveat — both come
from the same undercounting walk, neither is "exactly known."

**MVP scope: C/C++ (ObjC/ObjC++ fast-follow) only, not all 14 languages** — highest locals/function
ratio in the survey (5-15/fn vs 3:1 Python, 0.2-0.8 Go/Rust), and `main.cpp`'s existing
`large-function`/`deep-nesting` gate Phase 2 extends is *already* C-family-only, so this is extending
shipped code rather than building a new cross-language subsystem. Go/Swift need a Swift-style
post-capture filter for a DIFFERENT reason (query-layer scope conflation) that this walk-scoped
design sidesteps — real second-wave candidates, not intrinsically harder here, just lacking an
existing gate to piggyback on.

**Hard blocker on default-enable, not a nice-to-have:** `renamemine.h`'s calibration join requires
the new name to be `naminglens::eligibleSymbol` (indexed at HEAD) — locals are never indexed by
Phase 1's own design, so `test/namingcalibrationcheck.sh` cannot calibrate a local-scoped rule as it
stands. Required before default-enable: a hand-curated fixture corpus (Phase 2's fixtures A-E) AND a
manual audit of flagged output on a real corpus (ripwire's own `src/`) checking for skew toward
idiomatic-but-short names (`i`/`j`/`k`/`buf`/`tmp`/`err`) — cited against this exact lens's own
history: `naming-body-mismatch` passed its fixture gate, shipped, and was only caught 4.5 hours later
by a MANUAL audit of real output (159/217 findings dominated by the tree's best-named functions); the
calibration harness built afterward produced zero usable signal (13 pairs, no scorable firings) on
this same repo. Fixtures alone are demonstrated-insufficient on this exact lens, not hypothetically
insufficient.

### Open questions (unmeasured thresholds, need a human call before implementation)

1. `locals>=8` — invented, not measured; ship Phase 1 alone first, look at the real distribution,
   then set this floor.
2. ~~Message-text fork~~ — resolved (the `checkNameShapeCore` extraction gives locals accurate text).
3. Tag namespace — reuse existing tags with a `scope="local"` qualifier (recommended) vs new
   `-local`-suffixed tags, which would extend the position-pinned `tallies[9]`.
4. Validation path/timeline before default-enable — the fixture+audit combination is required, the
   `renamemine.h` extension is a condition for staying enabled past a trial period; exact trial length
   and audit sign-off owner is a real scope call, not a default to pick silently.
5. Composite `K` — same measure-don't-guess problem as #1.
6. Whether Phase 3 eventually feeds `--quality-delta` (regression view) vs staying `--lint`-only
   (standing-facts view, recommended for MVP).
7. Branch/merge sequencing note is now MOOT in this worktree (naminglens.h/renamemine.h are already
   landed here) — re-check only if this plan is executed against a different checkout.
8. How far the `declDepth>=2` gate goes toward closing the idiomatic-short-name false-positive class —
   explicitly does not fully solve it (a deeply-nested loop counter still clears the gate); resolve
   via the required real-corpus audit, not by inventing a further threshold here.

Not started. Waiting on: the access-shape/chase-pointer cache-friendliness workflow (still running at
time of writing) to land, so both plans get reviewed together rather than piecemeal.

## 2026-08-06 (evening, cont.) — access-shape / chase-pointer colocation plan, orchestrated

Produced by a 10-agent Workflow (4 independent web-backed prior-art searches → design → 4-way
adversarial review incl. a dedicated novelty-refuter → merge). NOT implemented — a plan only. This
one's design agent caught the same checkout-mismatch risk the local-variable workflow hit, but
avoided it: it explicitly read `src/fieldaffinity.h`/`docs/FIELDAFFINITY.md` from THIS integration
worktree rather than the primary session directory, and separately caught that the task prompt's
pointer to `docs/LINEAGE.md` for the "Gated-claim wording" pattern was wrong — that section actually
lives in the private research record, not in this repo — and used the real location instead of
trusting the prompt.
Good precedent: state the absolute worktree path explicitly next time regardless, since this
self-correction was diligence, not a guarantee.

### Novelty verdict: RARE BUT REAL — survived an adversarial check, not just a first pass

The underlying engineering INSIGHT (colocate a linked structure's chase/next pointer near its hot
payload fields, since the cache-line fetch to dereference it is unavoidable) is **COMMODITY** —
settled practitioner folklore (Boost.Intrusive's own performance docs; Chandler Carruth's CppCon 2014
talk; CMU's unpublished "Object Fusion" course project names the exact failure mode). Cited, not
claimed, matching how `fieldaffinity.h`'s own header already handles Chilimbi/Hundt.

The DETECTION-AND-PRIVILEGING MECHANISM — static, no-execution, source-level classification of a
traversal's access shape (index vs. pointer-chase) that then privileges the specific chase-pointer
field in an automated field-colocation check, surfaced as compile-time review advice — is **RARE BUT
REAL**: not found after two independent multi-angle searches. The first (research phase, 14 academic
queries + 8 industrial tool catalogs + a patent search) found the two closest structural cousins —
**Marmoset** (ECOOP 2024, arXiv:2405.17590 — a static compiler that auto-synthesizes packed ADT
layouts, but an automatic transform, not developer advice, and functional-ADT-scoped not general
C/C++) and the unpublished **"Object Fusion"** CMU project (names the exact problem, but requires
manual developer annotation of key/next accessors, not detection). The SECOND, independent search (a
dedicated novelty-refuter agent, explicitly told to try to kill the claim rather than confirm it, run
against a non-overlapping set of sources) additionally checked DMon (OSDI'21), DINAMITE,
Intel Advisor, PerfLint, and Lattner's LLVM Data Structure Analysis / Automatic Pool Allocation —
all fail on at least one of the two required prongs (require execution, or do generic/uniform field
colocation with no chase-pointer-distinguished case, or classify for a different consumer like
hardware prefetcher design). Neither search found a counter-example. Both are explicitly hedged as
"a genuine search that failed to find a counter-example, not a formal patent clearance" — no full
ACM DL/IEEE Xplore pass, no USPTO classification-code search.

**SAFE claim** (for `docs/LINEAGE.md` if/when this ships): *"No shipping static-analysis tool, and no
published academic work found in a multi-angle search (independently repeated by a second search
covering a non-overlapping source set), combines (a) a purely static, no-execution, no-debug-info
classification of a loop or traversal function's access shape as index/handle-based versus
pointer-chase-based with (b) a chase-pointer-specific field-colocation check that treats the
traversal pointer as a distinguished, higher-priority case of pairwise field affinity, surfaced as
compile-time code-review advice."* Full UNSAFE-wording table (five specific overreach claims, each
refuted by a named citation) and the complete prior-art citation set are in the workflow's saved
output; ready to paste into `docs/LINEAGE.md` verbatim if the feature ships.

### The plan (verbatim from the workflow's final merge)

**Recommendation: extend `--field-affinity`, don't ship a new flag.** Stage 1 (aggregate modeling)
and Stage 2 (member-access enumeration) already do the expensive part this needs; a second verb would
either double the modeling cost or import `fieldaffinity.h` as a dependency of itself.

**Phase A — access-shape classification (new).** New file `src/accessshape.h`. Classifies each
loop/recursive traversal as `index` / `chase` / `mixed` / `unknown`, via declarative `TSQuery`
patterns run through the codebase's EXISTING re-query mechanism (`astQuery()`, `ingest.cpp:7175` —
already backs `--lint`, the atoms-of-confusion pack, and `--nonlocal-state`'s cell discovery), not a
hand-rolled byte scanner and not a false reuse of parse-tree state (ingest calls `ts_tree_delete` at
every parse site — no tree survives to reuse). Self-referential chase-field detection (does a field's
declared type contain the enclosing struct's own name) handles 7 cases including typedef aliases,
templates, smart-pointer unwrapping, and cross-aggregate multi-hop links; an ambiguous stem matching
2+ modeled aggregates is REFUSED and disclosed (`stem_ambiguous=`), matching the file's existing
`ambSkipped`/"refuse rather than guess" convention, never a first-seen-order guess. `unknown` fails
closed by construction — a query that doesn't match emits no signal, never a wrong one.

**Precision traps the design explicitly fixtures, not just describes**: a constant-stride pointer walk
over a flat buffer with an arrow-deref BODY (`for(Node* p=first; p!=first+n; ++p) p->touch();`) must
classify `index` — the advance is pointer arithmetic on `p`, not a field read — despite the `->` in
the body; its near-twin differing only in the advance expression
(`for(Node* p=head; p; p=p->next) p->touch();`) must classify `chase`. An STL iterator's `++it` must
not collapse into the chase shape (`operator++`, not a field read). A single loop carrying BOTH an
index signal and a chase signal at once (not two separate loops) must classify `mixed`. These are the
minimal discriminating pairs the correctness review specified are necessary, not decorative.

**A required, explicit cost ceiling** (new section added by the scale-perf review) — an
`kMaxAggsModeled`-style skip threshold above a stated complexity band, disclosed via a floor counter,
hooked into the existing `perfharnesscheck`/`spectimingcheck` gates; a reference-corpus wall-clock
number is REQUIRED before Phase A leaves report-only status, not shipped unmeasured.

**Phase B — chase-pointer colocation (refinement, conditional on Phase A).** Not a new finding kind —
`--field-affinity`'s existing two-finding-kind contract (`split-line`/`straddle`) stays untouched. A
chase-target field's `sepCost` contribution gets a named, disclosed boost multiplier
(`kChaseSepCostBoost`) applied inline at the exact accumulation point, before the existing
`sepCost desc → findings.size() desc → name asc → path asc` sort — stated explicitly so the boost
can't silently break the file's determinism contract. The boost's actual numeric value is explicitly
NOT claimed as measured until `bench/bench_chase_ab.cpp` (a new A/B harness, same pattern as
`bench_field_ab.cpp`) produces a real number under a real `p=p->next` traversal — citing this file's
own §5.3 precedent, where the split-arm hypothesis inverted at stride 1, as the reason to distrust an
unmeasured constant here too.

**Validation methodology — three required elements, not implicit:**
1. Fixture gate (`test/accessshapecheck.sh`) — exact-match against every labelled trap case above,
   `fieldaffinitycheck.sh`'s own assertion style.
2. **A required, NOT optional, real-corpus precision/recall session** against THREE corpora — a
   chase-heavy positive corpus (intrusive-list/tree-style C/C++), ripwire's own `src/` as a negative
   control, AND a third corpus specifically added because ripwire's own SoA-heavy source is a WEAK
   adversarial test for the false-positive risk that matters (G2 keeps `->` density low there, so a
   near-zero chase rate doesn't stress the index/chase boundary) — an ordinary iterator/pointer-arithmetic-heavy
   modern-C++ codebase is the actual precision stressor. Reviewed BLIND — the classifier's own label
   is hidden until after the reviewer records an independent judgment — closing the exact
   "did I validate this or just confirm my own heuristic" trap the withdrawn naming rule fell into.
3. **A declared shipping floor**: >=85% precision on the `shape_conf="self-ref"` flagged set before
   Phase B may consume it for anything ranking-affecting. Missing the floor keeps Phase A permanently
   report-only — no all-or-nothing kill decision, no silent promotion past a floor nobody checked.

### Open questions (need a human decision)

1. The perf ceiling's exact threshold value — mechanism specified, number needs a real bench run.
2. Should a bare iterator loop (`for(auto it=v.begin(); ...; ++it)`) ever classify `index` rather than
   `unknown`? Proposed default: `unknown` (fails closed); revisit only if real-corpus recall numbers
   show this is a material miss.
3. Indirect range-for targets (`for(auto& x : *getItems())`) — safe default is `unknown`; deeper
   resolution through call returns/view adaptors is explicitly out of scope for v1.
4. `kChaseSepCostBoost`'s value — needs `bench/bench_chase_ab.cpp`, not a guess.
5. Whether the disclosed template-self-ref false-positive gap (`Node<Key>* cachedLookup` unrelated to
   traversal, still labelled self-ref under `tmpl_approx="1"`) should be narrowed in v1 or shipped
   disclosed — explicitly flagged as worth a second opinion given its parallel to the withdrawn
   naming rule's failure shape, not decided unilaterally in this plan.

Not started. Both this plan and the local-variable-indexing plan above are now written up and ready
for a future session to pick up — neither has been implemented this session.

## 2026-08-06 (night) — audit pass on the two landed features, plus two design proposals

An audit-and-improve pass over the two features the evening sections above planned and a prior
session landed (local-variable indexing Phases 1-2; access-shape/chase-pointer Phases A/B). What it
found and FIXED, so the design proposals below start from a corrected baseline:

* **Three honesty defects in the Phase A/B refusal accounting, all probe-confirmed before fixing.**
  (1) A chase field name owned by ZERO modeled aggregates (a traversal through a forward-declared /
  vendored type) was tallied under `as_stem_ambiguous=` — whose every comment and doc said "owned by
  2+ modeled aggregates". Now its own disclosed counter, `as_stem_unowned=`. (2) A chase field whose
  SOLE modeled owner declares it as a non-pointer (probe: `struct Counter { int next; }` plus a loop
  chasing `->next` on an unrelated forward-declared type) was silently attributed `chase="1"` to the
  int field — a provably wrong guess. Now refused via `accessshape::chaseTypeCanPoint` (no '*'/'&'
  marker in the declared spelling ⇒ cannot be a raw-pointer chase target; the disclosed cost is that
  smart-pointer fields are refused with it) and counted as `as_stem_nonptr=`. (3)
  `ShapeResult::saturatedTags` was fed from astQuery's UNCOMPILED-queries out-param — opposite
  failure mode (signal absent, not truncated) — and genuine budget saturation was undetected despite
  the tuning comment claiming disclosure. Renamed `uncompiledQueries` (`as_uncompiled=`), plus a real
  `queryBudgetSaturated` bit (`as_query_capped="1"`). All three pinned in
  `test/accessshapecheck.sh` (fixture grew `hopWalk`/`ledgerWalk`/`Ledger`; loop counters 5→7).
* **Open Question 8 above, measured.** The declDepth>=2 gate is NOT what protects `for( int i … )`:
  a for-init declaration's parent is the `for_statement`, so `cc_isCountableLocalDecl` structurally
  never counts it at ANY depth — the modern conventional-counter spelling can never fire
  naming-short, whitelist-free (pinned: `naminglocalscheck.sh` arm 4b). The RESIDUAL false-positive
  class is the C-style block-declared counter (`int j;` then `for( j = 0; … )`) — probe-confirmed to
  fire; deliberately NOT patched (an i/j/k whitelist or a used-as-counter heuristic would be the
  plausible-but-unaudited guard the WITHDRAWN note warns about); quantify it in the required
  real-corpus audit before default-enable.
* **The estchargecheck #5b known-red, root-caused and fixed.** A payload verb's map portion starts
  with a 5-byte `<ctx>` opener (printed by main.cpp before serialize()'s bytes) that neither the
  --max-tokens binary search nor the ceiling verdict charged — at N=6000 the map fit the 12 744 B
  cap by 4 bytes unwrapped and delivered 12 745 B wrapped, unlabelled. Both now charge
  `mapCtxOpenBytes`; suite is 361 gates / 358 pass / 2 skip / 0 real fails.
* Also: `naminglocalscheck.sh`'s mutation arm now restores `src/naminglens.h`'s ORIGINAL mtime after
  its restore-rebuild (backup `cp -p`, restore bare-cp + rebuild + `touch -r`) — a bare-cp restore
  re-stamped the file "now" and turned `g1freshcheck` red for suite-mates under `pargates.py -j 6`.

Everything below is a PLAN ONLY — nothing in the two proposals is implemented.

### Proposal 1 — the loop×layout join: static cache-line utilization (`--field-affinity` Phase C)

**The observation this answers, verbatim from the driving conversation:** "we code review for cache
friendliness before measuring it, it seems like there should be some way to write a tool to at least
get an estimate on how cache friendly so code can be quickly adjusted before measurement… I have
never seen a tool do it, it is always measure first than change the code."

**Why what exists is a partial instance.** The shipped pieces each answer ONE reviewer question:
`--layout` answers "what does a line fetch bring in?" (geometry); `--field-affinity` answers "which
fields want to be closer?" (pairwise co-access distance); Phase A/B answers "which traversals are
latency-bound and where must the unavoidable fetch land?" (advance shape). None answers the FIRST
question a reviewer actually asks of a hot loop: **"of each cache line this loop drags in, how much
does it use?"** — the question behind the two most common cache review comments (AoS→SoA; hot/cold
field split). That is a JOIN of two models this tree already builds, not a new analysis:

* Per loop, Phase A already has the loop's span and shape (index/chase/mixed/unknown).
* Per enclosing function, fieldaffinity Stage 2 already enumerates member-access sites with their
  byte spans and resolves them (sole-owner-or-refuse) to a modeled aggregate's field. Narrowing
  "per function" to "per loop" is the SAME byte-span-containment correlation accessshape.h already
  does five times — no new mechanism.
* Per aggregate, layout.h already knows each field's offset/size and the line count.

**The emitted quantity.** For an `index`-shaped loop whose contained member accesses resolve to ONE
aggregate T (anything else: refuse, disclosed): `touched` = union of accessed fields' [offset,
offset+size) within T; `util` = bytes of `touched` ÷ min( sizeof(T), kCacheBlockBytes ) — the
fraction of each fetched line the loop actually reads, under the two stated assumptions (unit
element stride, which is what `index` shape means for a `++p` advance; allocation-contiguous
elements). A `util` near sizeof(field)/sizeof(T) on a large T is the AoS-hot-loop signature; the
advice row nominates the touched set as the SoA/hot-split candidate — nominates, never decides,
same contract as every finding in the file. For a `chase` loop the number is NOT emitted (a chase
loop's element stride is unknowable statically; its lens is the already-shipped colocation
disclosure) — refusing that case is what keeps the number honest.

**Why this is believable before measurement, and what would validate it.** bench_field_ab.cpp §5
has ALREADY measured this phenomenon's two edges: 4 of 5 stride regimes confirmed the
separation-cost hypothesis and the fully-sequential regime INVERTED (§5.3) — so the plan's required
A/B (`bench/bench_util_ab.cpp`: same harness pattern, one hot 8-byte field in a 64/128/256-byte
struct, packed-SoA vs full-AoS walk, unit stride) is expected to be the STRONGEST regime for the
hypothesis (utilization is exactly what stride-1 hardware prefetching cannot fix — the prefetcher
hides latency, not wasted bandwidth), but that expectation ships as a hypothesis, not a number,
until the harness runs. Same report-only discipline as Phase B: `util=` is a disclosed attribute;
nothing ranking-affecting consumes it until a real-corpus precision session (three corpora, blind,
floor stated up front) clears.

**Novelty, hedged.** The advice itself (SoA, hot/cold splitting) is COMMODITY — Chilimbi's own
hot/cold splitting paper (PLDI 1999, the file's existing citation) plus 25 years of folklore. The
measured quantity exists DYNAMICALLY in shipping tools: Intel Advisor's Memory Access Pattern
analysis reports per-loop stride classes and cache-line utilization from an instrumented RUN — that
is the "measure first" tool the observation names. A purely STATIC, pre-compile, per-loop
utilization estimate surfaced as review advice was not found in either of the two adversarial
searches already run for Phase A/B — but neither search was ASKING this question, so the claim tier
is at most "PLAUSIBLY RARE, UNSEARCHED": a dedicated search (Advisor/VTune docs, Marmoset lineage,
the AoS-SoA auto-transform literature — Curial et al. CGO 2018 "Automatic struct peeling" class)
is a REQUIRED gate before any LINEAGE.md row, and finding a counter-example downgrades this to
"reimplementation, cited" without killing its usefulness here.

**Cost ceiling.** Reuses Phase A's astQuery output and Stage 2's access table — the join is
O(loops × accesses-in-file) worst case, bounded by the same kMaxLoopsModeled refusal; measure the
marginal wall against the 0.20 s Phase A number before landing, same discipline.

### Proposal 2 — one theory under the three lenses: the reader's environment, and what it corrects

**The direction, verbatim:** "basically we want to make a quantitative software metrics suite for
everything would normally look for in a code review… but not literally true for everything a
reviewer does, yes, but we want to push this as far as we can." Plus the worked example: a
1000-line function with 50 poorly-named primitive locals.

**The unified claim, stated so it can be wrong.** Reading a function is evaluating it over an
environment. The comprehension cost the three lenses measure is the SIZE of that environment, split
by binding lifetime: (a) bindings defined ELSEWHERE that must be loaded — `--context-ratio`'s
ents=/read_ratio= (spatial non-locality); (b) bindings mutable from ELSEWHERE whose current value
cannot be assumed across any call — `--nonlocal-state`'s reach-read/reach-write cells (temporal
non-locality); (c) bindings defined HERE that must be held simultaneously — the new `locals=` count
plus nesting (local environment width). All three are "how much is not hidden from me" — which is
why Parnas 1972 is already `--context-ratio`'s citation; the other two are the same accounting at
different lifetimes, not different theories.

**What asking it as ONE theory corrects — the concrete deliverable.** Face (c) is currently counted
WRONG for the theory: `locals=` counts declaration BIRTHS per function, but environment size is
peak POPULATION — a 1000-line function with 50 locals in disjoint 20-line blocks is a sequence of
small environments; the same 50 declared at function scope is one huge one, and the worked example
is precisely the second shape. The theory therefore predicts a specific, cheap refinement:
**`locals_live=` — the maximum number of countable locals whose enclosing scope chain is
simultaneously open**, computable in the SAME fused cc_walk that counts births (a per-depth birth
counter pushed/popped with compound_statement entry/exit — no second walk, same floor semantics).
NOT novel as a metric: live-variables-per-statement and variable span are published comprehension
measures from the structured-programming era (Dunsmore & Gannon's live-variable work is the named
ancestor — cite on rediscovery, per the DESIGN_READABILITY_METRICS shortlist discipline), and
scope-weighted rather than dataflow-live is a deliberate weakening (no dataflow here; a
scope-alive-but-dead-after-last-use local still counts — a disclosed over-count, the safe
direction for a nomination lens). The genuinely arguable-new part is only the COMPOSITION: all
three faces on one row, in commensurable units where honest (entities + estimated read-tokens —
context-ratio already prices face (a) in tokens; face (c)'s token price is the declarations'
spans), presented as a `--quality-panel`-style JOIN.

**Explicitly NOT proposed: a blended score.** The withdrawn naming rule is this tree's own proof
that an unvalidated direction on a plausible axis ships wrong; a weighted sum of three axes is
three unvalidated directions and a fake unit. The join VIEW (three columns, one row per symbol,
sorted by any single column the caller picks) delivers the theory's value — the shapes become
visible: high-(a)+low-(c) is the good-abstraction shape (context loaded, body simple);
low-(a)+high-(c) is the worked example (self-contained but unnavigable); high-(b) anywhere is the
testing hazard — without inventing weights nobody measured.

**Is there a fourth axis?** The honest answer found by asking: not a missing MEASURE — a missing
MEASURABILITY. The three faces cover what a static, name-resolved, polyglot index can see of
information hiding. What a reviewer checks that none of them can: PROTOCOL state — ordering
constraints ("must call open() before read()", init-before-use, lock-before-touch), the hidden
automaton a module's interface implies. That is temporal coupling between CALLS, not reachability
of CELLS; measuring it statically needs typestate/protocol inference, which is a different
evidence class (and where it IS approximable — co-change's "these two functions always change
together" — the tree already ships it as history evidence, not static structure). Recommendation:
state the boundary in the join view's legend ("protocol/ordering constraints are not measured
here"), do not manufacture an axis-four metric to fill it.

**Validation before any of it defaults on.** (1) `locals_live=` gate: fixture functions with
identical `locals=` and hand-derived different `locals_live=` (the two 50-local shapes above), plus
the mutation arm proving a births-counter stub fails it. (2) The join view re-ranks ripwire's own
src/ + one external corpus; a manual audit checks the top-20 against reviewer judgment the same way
the naming-locals default-enable blocker requires — fixture-passing alone is
demonstrated-insufficient on this tree (the WITHDRAWN precedent). (3) Any correlation claim
("predicts comprehension effort") is out of scope until someone designs a study; the join makes no
such claim in its legend.

### Open questions (need a human call before either proposal is implemented)

1. Proposal 1's aggregate-resolution rule inside a loop: sole-owner-or-refuse (recommended, matches
   Phase B) — or should a loop whose accesses resolve to TWO aggregates emit two util rows? Refuse
   first, measure the miss rate on the real-corpus session, then decide.
2. Proposal 1's `util` denominator when sizeof(T) > one line: per-line union (exact, costlier) vs
   min(sizeof(T), line) (floor, cheap — recommended for v1, disclosed as a floor).
3. The dedicated novelty search for static per-loop utilization advice — who runs it and against
   which source set; REQUIRED before any LINEAGE.md row (finding prior art demotes the claim, not
   the feature).
4. `locals_live=`'s interaction with the Phase 2 naming gate: should namingLocalsGate move from
   `locals>=8` to `locals_live>=K` once measured? Theory says yes (population, not births);
   measure the distribution on src/ first, same discipline as the locals>=8 floor.
5. Whether the three-face join is a new verb (`--envelope`? name TBD) or a `--quality-panel`
   preset — the panel already owns the "several lenses, one screen" contract; extending it avoids
   a 168th flag arm. Recommended: panel preset.
6. bench_util_ab.cpp's regimes: element sizes 64/128/256 B, hot-field 8 B, working sets LLC-resident
   AND DRAM-resident (bench_chase_ab's null at 64 MB says the DRAM regime may wash here too — that
   would be an honest partial-null to report, not to smooth over).

Not started. Both proposals compose shipped machinery (layout model, Stage-2 access table, Phase A
classification, cc_walk, context-ratio/nonlocal-state) — the only new code surfaces are the
loop×layout join, the per-depth live counter, and a join view; every threshold above ships
measured-or-refused, never invented.

## 2026-08-06 (late) — head-to-head round 4, five closed ranking rounds, and the handoff

Cold-start pointer for the next session: everything below is on `integration/all` == `origin/main`.
The benchmark ASSETS live OUTSIDE the repo at `~/AppDevelopLocal/project2/bench-assets/r4/` (kept
deliberately — see "Assets" at the end). Read `bench/headtohead/r4-2026-08-06/README.md` first if the
task is benchmarking, `bench/locbench/results/r6_expansion/gate_verdict.txt` first if the task is
ranking quality.

### What landed

* **Round 4 — one unified head-to-head table.** Every competitor re-run 2026-08-06 against ONE binary
  (`7a9a42ea`, rebuilt from HEAD) and ONE evaluator on the 60-instance held-out slice, paired, zero
  exclusions: ripwire 58.3% / 85.0%, codebase-memory-mcp 40.0%, repowise 33.3%, graphify 31.7%, aider
  18.3% (8.3% without ident personalization), codeseek 15.0% (0.0% on its raw arm). This RETIRES the
  two-table split and the "not number-comparable" caveat the README used to carry. ripwire's own arm
  reproduced r2 exactly, which is the evidence the harness is sound.
* **The re-run COST us margin, and the README says so.** codebase-memory-mcp is the true runner-up —
  r1 credited it 26.7%, fair re-scoring gives 40.0%. Margin over best competitor is **1.46x**, not the
  1.75x two separately-dated tables implied. graphify 21.7 -> 31.7, aider 13.3 -> 18.3 likewise.
* **An index-cost column, publishable for the first time.** r2 recorded competitor index walls and
  refused to tabulate them because ripwire's own index was unmeasured. It is measured now
  (`--measure-index --measure-cold`): ripwire cold-from-nothing-to-answer **0.299 s** against
  repowise's ~34 s (median index 33.0 s, worst **424 s**).
* **The harness is IN THE TREE** (`bench/headtohead/r4-2026-08-06/`), with all six arms' raw
  per-instance JSONL. r1's runners were not, they lived in `/private/tmp`, and macOS emptied them — so
  reproducing r1 meant rewriting three workers from prose. Round 5 is a re-run, not a rewrite.
* **Five pre-registered ranking rounds against the multi-file stratum, five rejections.** The matrix
  is complete: seed in {mention anchors, top-ranked files, none} x edge in {call/import, same
  directory, resolved import, none}. r6 was the last untried diagonal AND the only mechanism adding
  evidence the query did not supply; it moved 8-14 gold ranks per cell and crossed the @10 frontier
  zero times. Verdict recommends REFUSING a sixth candidate of that shape unless it can state its
  difference in seed x edge x evidence-source terms.

### Next work, in the order I would do it

1. **Candidate generation for the 11 (the only place multi-file instances still live).** Round 4's 22
   held-out multi-file failures decompose: 9 sibling-ranked-but-too-low (median rank 26 — five rounds
   have now failed to move these), **11 where the sibling NEVER ENTERS the candidate set**, 4
   whole-instance misses, 3 gold files with no code symbols. A reranker cannot rank a file it never
   saw, which is why every ranking round was structurally incapable of touching the 11. This is a
   different subsystem (what enters the top-k=200 candidate stream at all) and a bigger change than
   any of the five. Start by classifying the 11: is the sibling absent because of top-k truncation, or
   because it scores exactly zero? Those need different fixes and the answer is one script.
2. **C++/Rust head-to-head.** `bench/multiswe/` already mines Multi-SWE-bench's C/C++ splits and its
   README claims to be the first public issue-shaped C++ localization eval; `LANGS = ("c","cpp")` and
   the harness takes `--languages`, so Rust is a small change. The interesting question is NOT
   ripwire's score — it is whether the competitors run on C++/Rust at all. If they are Python-centric,
   that is a differentiator a Python-dominant benchmark structurally cannot show, and it is a stronger
   honest claim than anything currently on the front page. NOTE the current table's own limit: 107 of
   134 gold files are `.py`, and the README now discloses this.
3. **Store per-gold-file ranks in `run_locbench.py`'s arm JSON.** It keeps only `file_first` and
   `file_worst` today. That is why the r6 feasibility probe had to ask the weaker question
   "reachable from ANY peer gold file" instead of "reachable from the file we actually found", and why
   loss analysis keeps re-deriving things. Cheap, and it sharpens every future round.
4. **Query-compile latency, measured and bounded.** Profiling the 5.7 s index outlier
   (huggingface/transformers, 4,787 files) found ~73% is tree-sitter parse — irreducible — but that
   tree-sitter QUERY COMPILATION is on the critical path when there is not enough parse work to hide
   it: 36.8 ms of chainlit's 80 ms index, 3.5 ms of oauthenticator's 12 ms, versus 99.8 ms buried
   inside transformers' 1,549 ms pool. It scales with the most expensive grammar present (C++/CUDA),
   not file count. Compilation is ALREADY parallel across grammars, so the remaining lever is starting
   it before the crawl finishes. Realistic gain ~15-35 ms on medium polyglot repos, ~0 on large ones.
   Modest, on a thread-scheduling path with a documented lost-wakeup hazard — do it only when the
   ranking work is genuinely exhausted.
5. **StringZilla / length-carrying SIMD strings — probe `--grep`, not ingest.** The profile says our
   own string work is a small slice of indexing (readFile 3.5%, build-model 1.5%); ~73% is inside
   tree-sitter's parser where a different string type cannot reach. `--grep` is a parallel literal
   scan over file bytes and is the plausible target. Measure before committing to a dependency (G3
   would require vendoring it).

### Rules this round earned, all of them paid for

* **State an acceptance bar in INSTANCES, never in percentage points**, on any stratum small enough
  that one instance is a visible fraction. r5's PREREG said ">= +2.00pp multi-file" on a 43-instance
  stratum where one instance IS 2.33pp — the bar sat below single-instance granularity, one noisy flip
  cleared it, and the held-out run it bought returned +0.00pp. r6's bar was ">= 3 instances".
* **Run a feasibility probe before pre-registering a mechanism.** One script asking "does this
  mechanism have anything to walk to?" cost far less than the grid it would have consumed. It said yes
  (70% under a permissive text test) and r6 still failed — but the probe's own write-up had recorded
  that 70% as an UPPER bound and named both gaps, so the failure was interpretable instead of
  mysterious.
* **An identity control is not ceremony.** r5's `blend=0` cell caught that the first implementation's
  slot ladder changed output independently of the pooling. The PREREG said a failed identity control
  invalidates every cell, so the MECHANISM was corrected rather than the control waived.
* **Check the mechanism FIRED before writing a negative verdict.** r6 gained zero instances in nine
  cells; 8-14 gold ranks moved per cell, which is what makes it a result rather than a dead harness.
* **`git add -A` with no pathspec stages from the REPOSITORY ROOT regardless of cwd.** Run from
  `bench/headtohead/r4-2026-08-06/`, it swept a 113 MB (16 MB packed) `-DRIPWIRE_PROFILE=ON` build tree
  into a public commit. Use an explicit pathspec.
* **`.gitignore` has no trailing-comment syntax.** `profile*/  # why` is one literal pattern matching
  nothing. Comment on its own line above. `nulbytecheck` is what caught the tracked binaries, because
  it walks `git ls-files` rather than the files a human meant to commit.
* **A benchmark harness must not share an output channel with the tool under test**, and must not run
  with the repo under test as `cwd`. Both bit the aider arm: it returned JSON on stdout where aider
  prints progress (JSONDecodeError at char 0 on a good run), and `import numpy` from inside numpy's own
  source tree refused outright. Only the zero-silent-skip rule kept these from scoring as "found
  nothing".

### Assets (kept on purpose — large disk)

`~/AppDevelopLocal/project2/bench-assets/r4/`: `repos/`..`repos_e/` (five APFS clones, ~1.2 GB apparent
and near-zero real, one per concurrent arm because every arm mutates its checkout), `work/` (dataset
snapshot sha256 `5bbcea4b…`, plus ripwire's rich indexes), `tools/` (aider-chat 0.86.2, graphifyy
0.9.34, codebase-memory-mcp 0.9.0, repowise 0.37.0 venvs; codeseek 0.1.31 lives at `~/.codeseek`).
`results/` is already committed to the repo. Recreating all of it is roughly an hour; keeping it makes
the next round a single `bash r6_grid.sh`.

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

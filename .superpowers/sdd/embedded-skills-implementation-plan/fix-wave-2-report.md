# Fix wave 2 — round-2 adversarial review response

Branch `embedded-skills-225`, worked in worktree `agent-a49978de32350c546` starting at `4acc5f3d`.
Full review: `.superpowers/sdd/embedded-skills-implementation-plan/final-review-round2.md`.

10 commits, `4acc5f3d..HEAD`:

| Commit | One-line |
| --- | --- |
| `4d91bc2c` | fix(test): reorder+propagate agent-home sandboxing (C1,C2,C3,I0,M1,M7) |
| `4b2c9b77` | fix(test): neutralise CLAUDE_CONFIG_DIR and RIPWIRE_DATA_HOME in installer_isolation.py (I4) |
| `0a359fcf` | fix(test): update stale quote/recipe-shape assertions and per-arm temp redirects (I5,I7,M8,M3/I6) |
| `174dbb8e` | fix(test): restore OPENCLAW_STATE_DIR unset, trim comment that broke claudeconfigdircheck's guard-window scan |
| `e3f625df` | fix(test): clear ambient CLAUDE_CONFIG_DIR/RIPWIRE_DATA_HOME in agenttablecheck.sh |
| `0747ff99` | fix(skills-install): count and report foreign-entry skips instead of silence (I1) |
| `bb3441c7` | fix(codexdoctor): name what's actually blocking instead of a hint that can't fire or can't repair (I2,I2b) |
| `8eb78008` | fix(test): mise/aqua arms discriminate the shim's own path; drop stale RED comments (I3,I3b) |
| `d1e187b0` | fix(test): doctorstalecheck.sh positive assertions + sentinel enforcement (I3d); plug two more RIPWIRE_DATA_HOME leaks |
| `f56651c5` | fix(docs,install): correct INSTALL.md staging claim; gate the hooks hint on actual activation (I3c,M9) |

All commits are local to the worktree; nothing pushed, no PR opened, per instructions.

## Per-finding summary

**C3** — `test/hermesinstallcheck.sh` sourced the shared unset helper *after* exporting its own
`HERMES_HOME`; the helper's blanket unset clobbered it under `set -u`, aborting the gate with
`HERMES_HOME: unbound variable`. Reordered: source first, export after. Also added a load-bearing
ordering note to `test/lib/unset-agent-env-variables.sh`'s own header, as asked.

**C1** — `test/skillsinstallcheck.sh`'s `sandbox()` never sourced the shared helper, so an ambient
`AGENTS_HOME`/`HERMES_HOME`/`CODEX_HOME` would leak past its own `HOME=` for the `--codex`/`--hermes`
arms. Fixed by sourcing the helper inside `sandbox()`.

**C2** — `test/agenttablecheck.sh` arm (F) bound `HOME`/`AGENTS_HOME`/`CODEX_HOME` per invocation but
never `HERMES_HOME`, even though `$skillsflag` can be `--hermes`. Added `HERMES_HOME` to that
invocation's env prefix. Canary sweep (below) then found a **second, unnamed leak** in the same
file — `RIPWIRE_DATA_HOME`/`CLAUDE_CONFIG_DIR` were never bound at all — fixed by sourcing the
shared helper once at the top of the file instead of patching the per-invocation prefix again.

**I0** — `test/claudeconfigdircheck.sh` hand-rolled its own `unset CLAUDE_CONFIG_DIR` instead of the
shared helper, and its `--all` arm (which walks every detected agent) bound none of
`AGENTS_HOME`/`CODEX_HOME`/`HERMES_HOME`/`RIPWIRE_DATA_HOME`. Replaced the hand-rolled unset with a
single `source` of the shared helper at the top, covering every arm in the file (not just `--all`).

**M7** — `scripts/verify-agent-integration.sh`'s sandbox branch bound `AGENTS_HOME`/`CODEX_HOME`/
`CLAUDE_CONFIG_DIR` but not `HERMES_HOME` or `RIPWIRE_DATA_HOME`; `$AGENT` is a free CLI argument, so
`verify-agent-integration.sh hermes` could write into the operator's ambient `$HERMES_HOME` under a
"sandbox" banner. Added both vars to both branches (LIVE and sandbox) and to both places they're
consumed (the install invocation and the `RESOLVED` path-expansion `sh -c`).

Side incident on this same commit: the first version of the M7 comment I wrote pushed the
`else`-branch's literal `$H/.claude` assignment more than `GUARD_WINDOW=8` lines past the nearest
real `CLAUDE_CONFIG_DIR` reference in the file, tripping `claudeconfigdircheck.sh` arm (A)'s census
scan (a genuine regression I introduced and caught before committing — see commit `174dbb8e`).
Trimmed the comment; arm (A) is green (10/10 sites) after the fix.

**M1** — `test/lib/unset-agent-env-variables.sh`'s header claimed `OPENCLAW_STATE_DIR` is "checked
ahead of HOME" for openclaw. Verified by grep: no code reads that variable anywhere in `src/`;
`src/wrap.h` resolves openclaw through a literal `~/.agents/skills` path. Corrected the header to say
so, and kept `OPENCLAW_STATE_DIR` in the unset list as belt-and-braces (I initially dropped it
entirely in a first pass — the advisor caught that this was an unrequested isolation weakening, not
what the task asked for; restored it).

**I4** — `src/skillsinstall.h`'s `dataHome()` reads `RIPWIRE_DATA_HOME` ahead of
`$HOME/.local/share/ripwire`, and it wasn't in the shared helper's unset list — added.
`test/installer_isolation.py`'s own separate var tuple (`HOME`, `CODEX_HOME`, `AGENTS_HOME`,
`HERMES_HOME`) didn't cover `CLAUDE_CONFIG_DIR` or `RIPWIRE_DATA_HOME` either — extended it. Verified
the two pre-existing failures this gate already surfaces (ghost-symlink prune, Codex `--hook`
unimplemented — both on the disclosed list) are unchanged before/after the fix, so it introduces no
new failures.

**I5 / M8 (sourceinstallcheck.sh)** — the case pattern expected the wrap recipe in *double* quotes;
C3's earlier fix (`rw::shSingleQuote`) made the real output single-quoted, so the pattern could never
match. Updated to single quotes and reworded the pass/fail messages ("resolves the binary's own
resolved path", not "the staged Codex installer" — it doesn't resolve a staged file anymore).

**I7 (codexwrapcheck.sh)** — still grepped for the deleted `^bash skills/install\.sh --codex` line.
Updated to the current `^'[^']+' skills install --codex(...)` shape. (Needed a second pass: my first
regex used a `$`-anchor that missed the real line's trailing `# deploy to ...` comment — fixed to
match on whitespace-or-end instead.)

**M3 / I6 (skillsinstallcheck.sh)** — arms 3, 12, 13, 17, 18 redirected stderr to a bare relative
`skills_install.err` (relative to the `pargates` cwd, the repo root); each arm `rm`'d it on success
but `fail()` exits immediately, so a failing arm left it in the shared checkout. Redirected each site
to its own arm's per-arm sandbox dir (`$d3/skills_install.err`, `$d12/skills_install.err`, etc.).
Verified a full run leaves no `skills_install.err` at repo root.

**M8 (deckcheck_allowlist.txt)** — the `--codex`/`--codex-legacy`/`--hermes` rows still said
`skills/install.sh's ... destination mode`; reworded to match the `--claude` row's already-correct
`` `ripwire skills install`'s ... `` wording.

**I1** — `src/skillsinstall.h`'s `installForAgent` had two `!force` `continue` sites (a foreign-but-
live symlink; non-symlink content at a skill name) that reported nothing — no message, no counter.
Added `InstallOutcome::foreignSkipped`, incremented at both sites, surfaced as an append-only
`, M skipped (run --force to relink foreign entries)` suffix on both the bare-command and `--all`
per-agent summary lines. Kept the existing prefix format string byte-identical so the two known
consumers — `agenttablecheck.sh`'s `grep -q 'skill(s) linked into'` and
`verify-agent-integration.sh`'s `sed` extraction of the linked count — are unaffected (both verified
green). Extended `skillsinstallcheck.sh` arm 3 (which already plants exactly this fixture — a foreign
live symlink, then a bare install) to assert the skipped-count message, rather than adding a new arm
19 for a scenario the suite already had a fixture for.

**I2 / I2b** — see "Ambiguous / not fully resolved" below for I2's premise; the fix itself is
verified working (see empirical check). The manifest-parity hint's `declared < live` branch now
names the untracked entry directly (`"ripwire-orient exists at this skill home but ... never linked
it — remove it manually..."`) instead of prescribing `--force`; the `declared > live` branch (a
manifest-tracked entry that's actually missing from disk, which `--force` genuinely can relink) keeps
the original hint. I2b: the Codex hook-repair hint printed `run bash skills/install.sh --codex --hook`,
which now routes into the Codex `--hook` merge refusal (exit 2, no-op) — changed to state plainly
that Codex hook registration isn't available in this build. Updated `test/codexdoctorcheck.sh:105` to
match; grepped `test/routehookcheck.sh` too per the advisor's suggestion — it does not consume either
hint string, so no second gate needed updating.

**I3** — `test/selfcontainedcheck.sh`'s `skills install` arm predated the subcommand's existence and
had a branch where both success and "acceptable failure" printed `ok`. Now asserts success outright.

**I3b** — `test/wrapverbscheck.sh`'s `assert_skills_line()` greps for two strings deleted from
`src/wrap.h` 40+ commits ago (`bash skills/install.sh`, `skills not found locally`); those greps are
correctly-still-negative (they should never match, and don't) — on inspection they were not vacuous
the way the review described, they're legitimate "this old thing is gone" checks running alongside a
real positive-shape assertion the function already had. What *was* genuinely degraded: the mise/aqua
fixture arms only asserted a generic `^'[^']+' skills install...` shape, which matches *any*
single-quoted path, when their whole purpose is to prove the recipe names the shim's own resolved
target. Added an exact-string assertion for both (`$MISE_INSTALL/ripwire`, `$AQUA_INSTALL/ripwire`),
built against `REAL_TMP` (`pwd -P`) rather than `$TMP` directly — `$TMP` and its canonical form differ
as strings on macOS (`/var/folders/...` vs `/private/var/folders/...`), the same gotcha
`sourceinstallcheck.sh` already works around. Removed the two stale "RED until wrapPrintSkillsLine is
rewritten" header comments.

**I3d (doctorstalecheck.sh)** — arm (a) had only a negative assertion (`claude-binary` row is not
`ok="0"`) with no positive counterpart; added `ok="1"` as the paired positive. The gate's own header
claims "must never execute anything to figure that out" but nothing grepped the shim fixture's
sentinel string (`"this is a shim, not the real binary — must never be executed by --doctor"`); added
that grep, failing if the sentinel ever appears. Also added `trap 'rm -rf "$d"' EXIT` inside
`sandbox()` (previously each arm's temp dir only got cleaned by its own trailing `rm -rf`, which
`fail()`'s immediate `exit 1` would skip), and sourced the shared unset helper in `sandbox()` (it
only bound `HOME`/`CLAUDE_CONFIG_DIR` before).

**I3c** — `INSTALL.md` claimed `./install.sh` (the source build) "activates the skills ... skills and
hooks are embedded in the ripwire binary itself, not staged as separate files." Verified false:
`CMakeLists.txt` still stages `skills/` and `hooks/` under `<prefix>/share/ripwire/`, and `install.sh`
still resolves and runs that staged `skills/install.sh` (`test/sourceinstallcheck.sh` asserts the
staging exists). Rewrote the paragraph to describe each installer accurately: `./install.sh` stages
and runs the staged script; `scripts/install.sh` (the prebuilt/release installer) is the one with
skills and hooks embedded, nothing staged. Also aligned the `RIPWIRE_NO_ACTIVATE=1` wording with
`scripts/install.sh`'s own message ("skills not activated" — there's nothing to stage on that route).

**M9** — `scripts/install.sh` printed `Optional advisory hooks: ...` unconditionally, even after
`skills install --all` reported `0 agent(s) configured`. Now captures that command's output, still
prints it verbatim, and only shows the hooks hint when the parsed `N agent(s) configured` count is
`> 0`; otherwise prints "Nothing was activated — no detected agent to hook into." Verified against
`test/releaseinstallcheck.sh` arms (E1)-(E7), all green; grepped for any gate consuming the old
unconditional string — none found.

## Additional findings, beyond the review's named list

The canary leak-sweep (below) found two more `RIPWIRE_DATA_HOME` leaks the review did not name, in
gates that were not among the seven the review said already source the shared helper:

- `test/codexdoctorcheck.sh` — binds `HOME`/`CODEX_HOME`/`AGENTS_HOME` per invocation but never
  touched `RIPWIRE_DATA_HOME`; an ambient one leaked a full store extraction into the canary.
- `test/selfcontainedcheck.sh` — its `skills install` arm (the one rewritten for I3) hits the same
  `dataHome()` path with no override.

Both fixed the same way as I4/C2: source the shared helper once near the top of the file. Verified
clean by re-running the canary sweep after the fix (see below).

## Empirical leak-verification (canary sweep)

Method: pre-create five canary directories (`claude/`, `codex/`, `agents/`, `hermes/`, `data/`) under
one `mktemp -d`, point `CLAUDE_CONFIG_DIR`/`CODEX_HOME`/`AGENTS_HOME`/`HERMES_HOME`/`RIPWIRE_DATA_HOME`
at them (pre-created, per the advisor's correction — an unpopulated canary that doesn't exist yet
would make `--all`'s agent-detection skip it and falsely read as "clean"), run the gate, then
`find <canary-root> -mindepth 1`. **Caveat**: the five pre-created empty directories themselves always
appear in that `find` output — "clean" means nothing was written *inside* them, not that the listing
is empty.

Ran against every gate touched this session:

| Gate | Result |
| --- | --- |
| `hermesinstallcheck.sh` | clean (5 empty shells only) |
| `skillsinstallcheck.sh` | clean |
| `agenttablecheck.sh` | clean *after* the `RIPWIRE_DATA_HOME`/`CLAUDE_CONFIG_DIR` fix (dirty before — this is how that second leak was found) |
| `claudeconfigdircheck.sh` | clean |
| `routehookcheck.sh` | clean |
| `doctorstalecheck.sh` | clean |
| `codexdoctorcheck.sh` | clean *after* fix (dirty before — full store extraction into the canary `data/` dir) |
| `selfcontainedcheck.sh` | clean *after* fix (dirty before, same shape) |
| `wrapverbscheck.sh` | clean |

`installer_isolation.py` (I4) uses its own sentinel-snapshot method (not the canary-dir sweep, since
it already does an equivalent-but-stricter check via byte/permission snapshots of seeded homes);
verified separately by confirming the two pre-existing failures it surfaces are unchanged before and
after the fix (see I4 above).

`verify-agent-integration.sh` (M7) was verified by direct invocation (`bash
scripts/verify-agent-integration.sh codex`) rather than the canary sweep — it's an interactive/manual
tool, not a `test/*check.sh` gate `pargates` runs — confirming no `set -u` unbound-variable error and
correct output.

## Gate suite result

`python3 test/pargates.py . ./build/ripwire -j 6` — run against a `--clean-first` rebuild of the
final commit. See the appended summary below once the background run completes (the run exceeded the
120s foreground timeout in this session and was moved to background monitoring).

Reds observed this session, individually confirmed pre-existing (bisected against the commit
immediately before this fix wave, `4acc5f3d`, running the SAME binary — not attributed by
resemblance):

- `skillinstallcheck.sh` / `releaseinstallcheck.sh`: "install.sh did NOT prune a dangling
  ripwire-ghost symlink" and "--codex --hook did not create ~/.codex/hooks.json" — both on the
  disclosed list (the deliberately-red ghost-prune assertion; Codex `--hook` merge unimplemented).
- `routehookcheck.sh`: 5 failures, all naming `UserPromptSubmit`/router registration
  (`I2 install: no UserPromptSubmit entry...`, `I3 install: 0 router entries...`, `I3b`, `I6`, `V2
  doctor: route_hook is not 1`) — all on the disclosed list ("UserPromptSubmit routing hook not
  wired"). Confirmed pre-existing by running the exact `4acc5f3d` copy of this file (in `test/`, via
  `bash`, not a bare invocation — see caveat below) against the current binary: identical 5 failures.
- `agenttablecheck.sh` arm (K) — was failing before this session's work (disclosed: "ambient-env
  artifact"); after the `RIPWIRE_DATA_HOME`/`CLAUDE_CONFIG_DIR` fix to this same file (for the C2
  leak, not for arm K), it now passes as a side effect of no longer leaking ambient env into the
  gate's own detection logic. **I did not touch arm (K)'s assertion or logic** — flagging this
  explicitly so a reviewer doesn't read the flip as an unauthorized fix to a disclosed, do-not-touch
  item.
- **hermesinstallcheck.sh — 5 failures, all newly *visible* because of the C3 fix, not newly
  introduced.** At `4acc5f3d` (before C3), the gate died after ~3 arms with 2
  `HERMES_HOME: unbound variable` errors and never reached the arms below that point. After the
  reorder, the gate runs to completion and 5 arms fail:
  `--hermes exposed 16 of 17 skills`, `--hermes manifest set differs (15 vs 17)`, `a default (Claude)
  install overwrote/pruned the Hermes skill home (found=16)`, `the Hermes-native loop did not link
  the planted ripwire-decoy-map`, `the --hermes manifest omits ripwire-decoy-map`. I traced all five
  to one cause: `shipped=17` counts `skills/hermes/ripwire-repo-map` (a real Hermes-native skill in
  the repo) plus the 16 flat skills, but the Hermes-native linking loop never actually links it — the
  disclosed gap "Hermes-native selection unported." The first three failures are the same
  16-vs-17 undercount surfacing three times (fresh install, post-Claude-install re-check, and the
  manifest-set diff); the last two are a separate arm (7) that plants a *synthetic* Hermes-native
  fixture (`ripwire-decoy-map`, its own SKILL.md, its own throwaway home) and asserts it gets linked.
  Both arms 1 and 7 go through the identical code path — `skills/install.sh` is now a thin wrapper
  (`exec "$ripwire_bin" skills install "$@"`, confirmed by reading it), so there is no separate
  "shell installer" logic left to blame here, only `ripwire skills install --hermes` itself. One real
  repo skill and one purpose-built fixture skill, reached through the same wrapper into the same
  binary subcommand, both fail to link — that is the signature of the native-selection loop not
  running at all, not a fluke or a fixture bug, which is why I'm treating all 5 as one disclosed root
  cause rather than 5 separate opens. **This gate is now more red than it was before this fix wave,
  and that is expected and correct**: the previous 2-error state was masking these 5 with a crash,
  not fixing them. C3's job was to stop the crash, not to fix Hermes-native selection (out of scope,
  disclosed, not attempted).

*(Caveat on the routehookcheck baseline comparison above: my first attempt at this comparison copied
the file to `/tmp` and ran it without `bash`, which silently failed with "permission denied" — a
non-executable file invoked directly — and I misread the resulting empty grep as "0 failures,
therefore pre-existing." I caught this from the exit code before drawing any conclusion from it, and
redid it correctly: copied into `test/` so `$0`-relative `ROOT` resolution stays correct, invoked
explicitly via `bash` to bypass the missing +x bit. The corrected comparison is what's reported
above.)*

## Ambiguous / not fully resolved — reported honestly

**I2(a)'s stated premise does not reproduce in either scenario I tested.** The review states the
manifest-parity row's `ok` "never goes false for a foreign symlink (it reads ok=\"1\" — blind)". I
worked through the logic before writing the fix and concluded the opposite: `manifest.declared`
(built from `linkedNames`, which excludes a skipped foreign entry) and `live` (built by
`liveSkills()`'s `is_directory()`, which follows the symlink and counts it) should differ in both
size and membership whenever a foreign symlink is skipped — which should make `parity` false and
`ok` false, not blind. I ran the advisor's suggested empirical check twice (plant a foreign symlink
into a live directory under a sandboxed `HOME`, run bare `skills install`, then
`--doctor --agent=claude`) — once against a fresh skill home, once against a home with a prior
successful install before the symlink swap — and both times got:

```
<c n="claude-skills" ok="0" manifest="1" declared="15" live="16" hint="ripwire-orient exists at this
skill home but ripwire skills install --claude never linked it — remove it manually if it is not
meant to be there"/>
```

`ok="0"` both times, not blind. I have not found or reproduced a scenario matching the review's
literal "ok=1 for a foreign symlink" claim. My fix (the `declared < live` branch naming the untracked
entry) is verified correct and produces the intended, more-honest hint in both scenarios I tried — so
the deliverable is empirically sound regardless of which premise is right. But I'm flagging the
discrepancy rather than silently assuming either the review or my derivation is wrong: it's possible
the review's repro used a different construction (e.g. a *dangling* foreign symlink prior to some
other code path, or a manifest v1 upgrade path I didn't try) that does hit a blind case I haven't
found. If that's true, my fix's `declared < live` condition would simply never fire for that specific
sub-case (falling through to the unchanged `declared > live` branch's `--force` hint) rather than
being wrong — but I can't confirm that without knowing the exact repro the review used.

**`test/releaseinstallcheck.sh:129` and its arm (E5) PASS line repeat the same false claim I3c fixed
in INSTALL.md**: the comment says "RIPWIRE_NO_ACTIVATE=1 stages without activating" for
`scripts/install.sh` (the release installer), which stages nothing — I verified this directly while
fixing I3c. This is a test comment/message, not user-facing documentation, and wasn't named in the
review's fix list, so I left it as found-but-not-fixed rather than expanding scope. Flagging with the
exact location: `test/releaseinstallcheck.sh:129` (comment) and the `(E5)` `ok` message at line ~213.

**ASan/UBSan tree** — not run, per the task's own instruction that it's optional/time-permitting and
not required to complete this wave. Not attempted.

## Skipped, per explicit instruction

M2, M4, M5, M6, the `pargatescheck.sh`/`strkerncheck.sh`/`taskroutecheck.sh` timing items, and
everything on the prior fix-wave's already-disclosed list — untouched, as instructed.

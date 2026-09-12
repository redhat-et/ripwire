#!/usr/bin/env bash
# releaseinstallcheck.sh — the published archive and curl installer form one delivery contract.
# The release tag, binary version, asset name, bundled skills/hooks, checksum, and extracted paths
# must agree; a green build with a stale version is not a usable release.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
INSTALL="$ROOT/scripts/install.sh"
WORKFLOW="$ROOT/.github/workflows/release.yml"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
# Detection and activation must use only the per-invocation homes below.
unset CODEX_HOME AGENTS_HOME HERMES_HOME RIPWIRE_NO_ACTIVATE RIPWIRE_SKIP_CPU_CHECK RIPWIRE_CPUINFO
FAKE="$TMP/fake"; mkdir -p "$FAKE" "$TMP/assets/ripwire-0.3.6-macos-arm64/skills/ripwire-router" "$TMP/assets/ripwire-0.3.6-macos-arm64/hooks"

printf '#!/bin/sh\necho "ripwire 0.3.6 (Release, Test)"\n' >"$TMP/assets/ripwire-0.3.6-macos-arm64/ripwire"
chmod +x "$TMP/assets/ripwire-0.3.6-macos-arm64/ripwire"
# The REAL skills installer goes into the fixture, not a stub: arms (E1)/(E2) assert that the curl
# installer actually ACTIVATES skills, which a no-op stub would report without doing.
cp "$ROOT/skills/install.sh" "$TMP/assets/ripwire-0.3.6-macos-arm64/skills/install.sh"
printf '%s\n' '---' 'name: ripwire-router' 'description: route' '---' >"$TMP/assets/ripwire-0.3.6-macos-arm64/skills/ripwire-router/SKILL.md"
printf '%s\n' '#!/bin/sh' >"$TMP/assets/ripwire-0.3.6-macos-arm64/hooks/ripwire-nudge.sh"
printf '%s\n' '#!/bin/sh' >"$TMP/assets/ripwire-0.3.6-macos-arm64/hooks/ripwire-codex-nudge.sh"
chmod +x "$TMP/assets/ripwire-0.3.6-macos-arm64/skills/install.sh" "$TMP/assets/ripwire-0.3.6-macos-arm64/hooks/"*.sh
tar -C "$TMP/assets" -czf "$TMP/assets/ripwire-0.3.6-macos-arm64.tar.gz" ripwire-0.3.6-macos-arm64
( cd "$TMP/assets" && shasum -a 256 ripwire-0.3.6-macos-arm64.tar.gz >ripwire-0.3.6-macos-arm64.tar.gz.sha256 )
printf '%s\n' '{"tag_name":"v0.3.6","assets":[' \
  '{"browser_download_url":"https://example.invalid/ripwire-0.3.6-macos-arm64.tar.gz"}' ']}' >"$TMP/release.json"

cat >"$FAKE/curl" <<'EOF'
#!/bin/sh
out=""
url=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -H) shift 2 ;;
        -*) shift ;;
        *) url="$1"; shift ;;
    esac
done
[ -z "${CURL_LOG:-}" ] || printf '%s\n' "$url" >>"$CURL_LOG"
case "$url" in
    *api.github.com*) src="$RELEASE_FIXTURE" ;;
    *.sha256) src="$ASSET_FIXTURE.sha256" ;;
    *) src="$ASSET_FIXTURE" ;;
esac
if [ -n "$out" ]; then cp "$src" "$out"; else cat "$src"; fi
EOF
cat >"$FAKE/uname" <<'EOF'
#!/bin/sh
case "$1" in -s) echo "${FAKE_UNAME_S:-Darwin}";; -m) echo "${FAKE_UNAME_M:-arm64}";; *) /usr/bin/uname "$@";; esac
EOF
# `sysctl -n KEY` answers from $FAKE_SYSCTL_DIR/KEY. An absent file is an unknown oid, rc 1 — what macOS
# itself does for a key its kernel lacks. Only the (G) arms set FAKE_SYSCTL_DIR.
cat >"$FAKE/sysctl" <<'EOF'
#!/bin/sh
[ "$1" = -n ] && shift
if [ -n "${FAKE_SYSCTL_DIR:-}" ] && [ -f "$FAKE_SYSCTL_DIR/$1" ]; then cat "$FAKE_SYSCTL_DIR/$1"; exit 0; fi
echo "sysctl: unknown oid '$1'" >&2
exit 1
EOF
chmod +x "$FAKE/curl" "$FAKE/uname" "$FAKE/sysctl"

# ── HOME ISOLATION (2026-09-06). The installer now ACTIVATES skills for the agents it detects, so a
# run with the operator's real $HOME would symlink into their live ~/.claude/skills. Every invocation
# below therefore names a sandbox HOME, the same contract test/hookcheck.sh states for the meter log.
SBHOME="$TMP/home"; mkdir -p "$SBHOME"
PREFIX="$TMP/prefix"
if HOME="$SBHOME" PATH="$FAKE:$PATH" RELEASE_FIXTURE="$TMP/release.json" ASSET_FIXTURE="$TMP/assets/ripwire-0.3.6-macos-arm64.tar.gz" \
   RIPWIRE_REPO=redhat-et/ripwire RIPWIRE_VERSION=v0.3.6 RIPWIRE_INSTALL_PREFIX="$PREFIX" RIPWIRE_INSTALL_YES=1 \
   bash "$INSTALL" >"$TMP/install.out" 2>"$TMP/install.err"; then
    ok "curl installer accepts a tag-matched checksummed archive"
else
    no "curl installer rejected a valid archive: $( tail -1 "$TMP/install.err" )"
fi
[ -x "$PREFIX/bin/ripwire" ] && [ "$( "$PREFIX/bin/ripwire" --version | awk '{print $2}' )" = "0.3.6" ] \
    && ok "installed binary reports the release tag version" || no "installed binary/version mismatch"
[ -f "$PREFIX/share/ripwire/skills/ripwire-router/SKILL.md" ] \
    && ok "installer stages bundled skills" || no "installer did not stage bundled skills"
[ -x "$PREFIX/share/ripwire/hooks/ripwire-codex-nudge.sh" ] \
    && ok "installer stages bundled Codex hooks" || no "installer did not stage bundled Codex hooks"

mv "$TMP/assets/ripwire-0.3.6-macos-arm64.tar.gz.sha256" "$TMP/assets/checksum.saved"
if HOME="$SBHOME" PATH="$FAKE:$PATH" RELEASE_FIXTURE="$TMP/release.json" ASSET_FIXTURE="$TMP/assets/ripwire-0.3.6-macos-arm64.tar.gz" \
   RIPWIRE_REPO=redhat-et/ripwire RIPWIRE_VERSION=v0.3.6 RIPWIRE_INSTALL_PREFIX="$TMP/no-checksum" RIPWIRE_INSTALL_YES=1 \
   bash "$INSTALL" >/dev/null 2>&1; then
    no "installer accepted an archive whose checksum is unavailable"
else
    ok "installer refuses an archive whose checksum is unavailable"
fi
mv "$TMP/assets/checksum.saved" "$TMP/assets/ripwire-0.3.6-macos-arm64.tar.gz.sha256"

printf '#!/bin/sh\necho "ripwire 0.2.2 (Release, Test)"\n' >"$TMP/assets/ripwire-0.3.6-macos-arm64/ripwire"
chmod +x "$TMP/assets/ripwire-0.3.6-macos-arm64/ripwire"
tar -C "$TMP/assets" -czf "$TMP/assets/ripwire-0.3.6-macos-arm64.tar.gz" ripwire-0.3.6-macos-arm64
( cd "$TMP/assets" && shasum -a 256 ripwire-0.3.6-macos-arm64.tar.gz >ripwire-0.3.6-macos-arm64.tar.gz.sha256 )
if HOME="$SBHOME" PATH="$FAKE:$PATH" RELEASE_FIXTURE="$TMP/release.json" ASSET_FIXTURE="$TMP/assets/ripwire-0.3.6-macos-arm64.tar.gz" \
   RIPWIRE_REPO=redhat-et/ripwire RIPWIRE_VERSION=v0.3.6 RIPWIRE_INSTALL_PREFIX="$TMP/wrong-version" RIPWIRE_INSTALL_YES=1 \
   bash "$INSTALL" >/dev/null 2>&1; then
    no "installer accepted a checksummed 0.2.2 binary under release v0.3.6"
else
    ok "installer refuses a tag/binary version mismatch"
fi

grep -q 'releaseTag=' "$WORKFLOW" && grep -q 'binary version.*release tag\|release tag.*binary version' "$WORKFLOW" \
    && ok "release workflow gates binary version against release tag" \
    || no "release workflow can still publish a stale-version binary under a newer tag"
grep -q 'cp -R hooks' "$WORKFLOW" \
    && ok "release workflow packages hooks beside skills" || no "release workflow omits hooks"


# ── (E) THE INSTALL ENDS READY, NOT WITH A MENU ───────────────────────────────────────────────────
# A new user ran one line and then faced four more: activate skills for Claude Code, or for Codex,
# then optionally hooks for either. "Installed" did not mean "your agent knows how to use it", and the
# README's headline (the same line "ships the task-shaped skills that teach your agent when to reach
# for it") leaned on the word ships. The installer now ACTIVATES the skills for each agent it can
# actually detect and prints one receipt line per agent. Three properties this arm pins:
#   * detection drives it — an agent that is not installed is never given a skills directory;
#   * hooks are NEVER activated automatically. They carry a data-capture disclosure the user must
#     read and accept, so they stay an explicit opt-in no matter how convenient auto-arming would be;
#   * RIPWIRE_NO_ACTIVATE=1 stages without activating, for scripted and image builds.
# The version-mismatch arm above deliberately leaves a 0.2.2 binary in the fixture. Restore a pristine
# 0.3.6 archive before driving the installer for real, or every arm below fails for that reason instead
# of the one it is testing.
printf '#!/bin/sh\necho "ripwire 0.3.6 (Release, Test)"\n' >"$TMP/assets/ripwire-0.3.6-macos-arm64/ripwire"
chmod +x "$TMP/assets/ripwire-0.3.6-macos-arm64/ripwire"
tar -C "$TMP/assets" -czf "$TMP/assets/ripwire-0.3.6-macos-arm64.tar.gz" ripwire-0.3.6-macos-arm64
( cd "$TMP/assets" && shasum -a 256 ripwire-0.3.6-macos-arm64.tar.gz >ripwire-0.3.6-macos-arm64.tar.gz.sha256 )

run_install()
{
    # run_install HOMEDIR PREFIXDIR [extra env assignments...] -> stdout in $TMP/e.out, rc in $E_RC
    _h="$1"; _p="$2"; shift 2
    # HERMES_HOME= comes FIRST so an explicit HERMES_HOME from "$@" (as E7 passes) wins; env applies
    # assignments left to right, and a trailing default would silently clobber the override — leaving
    # E7 green via the $HOME/.hermes fallback instead of the override it claims to test.
    env HERMES_HOME= "$@" HOME="$_h" PATH="$FAKE:$PATH" RELEASE_FIXTURE="$TMP/release.json" \
        ASSET_FIXTURE="$TMP/assets/ripwire-0.3.6-macos-arm64.tar.gz" \
        RIPWIRE_REPO=redhat-et/ripwire RIPWIRE_VERSION=v0.3.6 RIPWIRE_INSTALL_PREFIX="$_p" RIPWIRE_INSTALL_YES=1 \
        bash "$INSTALL" >"$TMP/e.out" 2>"$TMP/e.err"; E_RC=$?
}
# NOTE: run_install defaults HERMES_HOME to EMPTY so a leaked real HERMES_HOME in the calling
# environment can never make scripts/install.sh's Hermes-activation block target the operator's live
# ~/.hermes/skills with the fixture's temp-bundled skills/install.sh (those temp src dirs are rm -rf'd
# at EXIT, leaving dangling links in a real Hermes home). Arms that want Hermes set it explicitly, as
# (E7) does, with a temp value.

# (E1) Claude Code present -> its skills are ACTIVE, and the run says so.
EH1="$TMP/home-claude"; mkdir -p "$EH1/.claude"
run_install "$EH1" "$TMP/prefix-e1"
[ "$E_RC" -eq 0 ] && ok "(E1) install succeeds with Claude Code present" \
    || no "(E1) install failed with Claude Code present: $( tail -1 "$TMP/e.err" )"
[ -e "$EH1/.claude/skills/ripwire-router" ] \
    && ok "(E1) Claude Code skills are ACTIVE after the one-liner, not merely staged" \
    || no "(E1) Claude Code was detected but its skills were left staged — the new user still has a menu"
grep -qi 'activated' "$TMP/e.out" \
    && ok "(E1) the run reports what it activated" \
    || no "(E1) skills were activated but the run never said so"

# (E2) Codex present (and Claude absent) -> the agents skills root, and NOT a Claude dir.
EH2="$TMP/home-codex"; mkdir -p "$EH2/.codex"
run_install "$EH2" "$TMP/prefix-e2"
[ -e "$EH2/.agents/skills/ripwire-router" ] \
    && ok "(E2) Codex skills are ACTIVE after the one-liner" \
    || no "(E2) Codex was detected but its skills were left staged"
[ ! -d "$EH2/.claude/skills" ] \
    && ok "(E2) an agent that is NOT installed is not given a skills directory" \
    || no "(E2) the installer created ~/.claude/skills for an agent that is not installed"

# (E3) No agent at all -> nothing invented, and the manual path still printed honestly.
EH3="$TMP/home-bare"; mkdir -p "$EH3"
run_install "$EH3" "$TMP/prefix-e3"
{ [ ! -d "$EH3/.claude/skills" ] && [ ! -d "$EH3/.agents/skills" ]; } \
    && ok "(E3) no agent detected: no skills directory is invented" \
    || no "(E3) the installer created a skills directory for an agent that is not there"
grep -q "install.sh" "$TMP/e.out" \
    && ok "(E3) no agent detected: the manual activation command is still printed" \
    || no "(E3) no agent detected and the run did not say how to activate skills by hand"

# (E4) Hooks are NEVER auto-registered — they carry a data-capture disclosure the user must accept.
[ ! -f "$EH1/.claude/settings.json" ] \
    && ok "(E4) the one-liner never registers hooks on its own (settings.json untouched)" \
    || no "(E4) the installer registered hooks without the user opting in: $( cat "$EH1/.claude/settings.json" )"
grep -qi 'hook' "$TMP/e.out" || true

# (E5) The escape hatch for scripted/image builds.
EH5="$TMP/home-noact"; mkdir -p "$EH5/.claude"
run_install "$EH5" "$TMP/prefix-e5" RIPWIRE_NO_ACTIVATE=1
[ ! -e "$EH5/.claude/skills/ripwire-router" ] \
    && ok "(E5) RIPWIRE_NO_ACTIVATE=1 stages without activating" \
    || no "(E5) RIPWIRE_NO_ACTIVATE=1 activated skills anyway"

# (E6) Idempotent: the one-liner is safe to re-run.
run_install "$EH1" "$TMP/prefix-e1"
{ [ "$E_RC" -eq 0 ] && [ -e "$EH1/.claude/skills/ripwire-router" ]; } \
    && ok "(E6) a second run is clean and leaves the activation in place" \
    || no "(E6) re-running the installer broke the activation (rc=$E_RC)"

# (E7) Hermes present -> its skills are ACTIVE via $HERMES_HOME (the install block's detection signal).
# Mirrors (E1)/(E2): Hermes home created in an isolated HOME, the release installer must activate the
# ripwire skills there, and must NOT invent a Claude dir for an agent that is not installed.
# The Hermes home is deliberately NOT $HOME/.hermes: that split proves run_install's explicit
# HERMES_HOME override reaches the installer, rather than the arm passing via the $HOME fallback.
EH7="$TMP/home-hermes"; EH7H="$EH7/custom-hermes"; mkdir -p "$EH7H"
run_install "$EH7" "$TMP/prefix-e7" HERMES_HOME="$EH7H"
[ "$E_RC" -eq 0 ] && ok "(E7) install succeeds with Hermes present (HERMES_HOME=$EH7H)" \
    || no "(E7) install failed with Hermes present: $( tail -1 "$TMP/e.err" )"
[ -e "$EH7H/skills/ripwire-router" ] \
    && ok "(E7) Hermes skills are ACTIVE after the one-liner, not merely staged" \
    || no "(E7) Hermes was detected but its skills were left staged"
[ ! -e "$EH7/.hermes" ] \
    && ok "(E7) the installer honoured HERMES_HOME instead of inventing $HOME/.hermes" \
    || no "(E7) the installer fell back to $HOME/.hermes — the explicit HERMES_HOME never arrived"
grep -qi 'Hermes' "$TMP/e.out" \
    && ok "(E7) the run reports the Hermes activation on the receipt line" \
    || no "(E7) the run did not print a Hermes activation receipt"
[ ! -d "$EH7/.claude/skills" ] \
    && ok "(E7) an agent that is NOT installed is not given a Claude skills directory" \
    || no "(E7) the installer created ~/.claude/skills for an agent that is not installed"

# ── (F) THE UPGRADE PATH LEAVES A BINARY THAT RUNS ──────────────────────────────────────────────────
# (E6) above re-ran the installer over an existing prefix and called it "clean" on the strength of an
# exit code and a symlink. On 2026-09-06 that exact upgrade -- 0.3.8 to 0.4.0 into /opt/homebrew/bin on
# macOS 15 -- left a binary the kernel SIGKILLed on sight (exit 137, no output), and every one of
# (E6)'s assertions still passed: rc was 0 because the installer's own post-install version check was
# wrapped in `|| echo "version check failed"`, so it printed that phrase INSIDE a line that also said
# "installed", and exited 0. The arm fired, was true, and proved less than its name.
#
# The two properties that were missing are gated here. Note what these arms can and cannot see: the
# fixture's "binary" is a shell script, which has no Mach-O image and cannot reproduce the kill itself.
# So (F1) gates the REPORTING contract (a broken install must be a non-zero exit, not a cheerful line)
# and (F2)/(F3) gate the MECHANISM that replaced the overwrite. The kill itself was reproduced only on
# the real path, and the source comment records that its kernel-level cause is NOT established.

# (F1) A post-install binary that cannot report its version is an INSTALL FAILURE, not a footnote.
# The fixture binary succeeds the first time it is run (the pre-install version check at install.sh's
# archive step) and fails every time after, so the archive check passes and the POST-install check is
# the one under test. Without this arm, the installer can prove an install is broken and still exit 0.
F1DIR="$TMP/assets/ripwire-0.3.6-macos-arm64"
cp "$F1DIR/ripwire" "$TMP/ripwire.fixture.bak"
# The marker is an ABSOLUTE path, not "$0.ran": the installed copy lives at a DIFFERENT path from the
# extracted one, so a $0-relative marker makes every copy think it is running for the first time and the
# post-install call succeeds. That is how the first version of this fixture reported a false green.
cat >"$F1DIR/ripwire" <<BROKEN
#!/bin/sh
# succeeds once (the pre-install archive check), then fails (the post-install check)
if [ -e "$TMP/f1.ran" ]; then exit 3; fi
: >"$TMP/f1.ran"
echo "ripwire 0.3.6 (Release, Test)"
BROKEN
chmod +x "$F1DIR/ripwire"
tar -C "$TMP/assets" -czf "$TMP/assets/ripwire-0.3.6-macos-arm64.tar.gz" ripwire-0.3.6-macos-arm64
( cd "$TMP/assets" && shasum -a 256 ripwire-0.3.6-macos-arm64.tar.gz >ripwire-0.3.6-macos-arm64.tar.gz.sha256 )
EHF="$TMP/home-f1"; mkdir -p "$EHF/.claude"
run_install "$EHF" "$TMP/prefix-f1"
if [ "$E_RC" -ne 0 ]; then
    ok "(F1) an installed binary that cannot state its version fails the install (rc=$E_RC)"
else
    no "(F1) the installer exited 0 for a binary it had just proved unrunnable — the check is cosmetic"
fi
# restore the good fixture so nothing downstream inherits the broken one
cp "$TMP/ripwire.fixture.bak" "$F1DIR/ripwire"; chmod +x "$F1DIR/ripwire"; rm -f "$TMP/f1.ran"
tar -C "$TMP/assets" -czf "$TMP/assets/ripwire-0.3.6-macos-arm64.tar.gz" ripwire-0.3.6-macos-arm64
( cd "$TMP/assets" && shasum -a 256 ripwire-0.3.6-macos-arm64.tar.gz >ripwire-0.3.6-macos-arm64.tar.gz.sha256 )

# (F2) THE BINARY REACHES ITS FINAL PATH BY RENAME. `cp` onto the destination rewrites the existing
# inode; `mv` within the directory replaces it atomically. This is the fix, so it is asserted directly
# rather than inferred from an outcome the fixture cannot produce.
if grep -qE '^mv -f "\$installTmp" "\$binDir/ripwire"' "$INSTALL"; then
    ok "(F2) the installer moves the binary into place atomically (mv, not cp-over)"
else
    no "(F2) the installer no longer installs by rename — an in-place overwrite is back"
fi

# (F3) MUTATION CONTROL for (F2), and the arm that would have caught the original bug: NO `cp` may name
# the destination path. (F2) alone passes if someone adds a cp-over BESIDE the mv.
if grep -qE 'cp[^|;]*"\$binDir/ripwire"' "$INSTALL"; then
    no "(F3) something still cp's directly onto \$binDir/ripwire — the overwrite path is reachable"
else
    ok "(F3) nothing cp's onto the destination path; the temp file is the only thing copied"
fi

# ── (G) A CPU BELOW THE x86-64 FLOOR IS NAMED, NEVER REPORTED AS A VERSION MISMATCH ────────────────────
# From 0.6.0 every non-native x86-64 build carries -march=x86-64-v3 (cmake/PortableFlags.cmake): AVX, AVX2,
# BMI1, BMI2, F16C, FMA, LZCNT, MOVBE. On an older CPU the prebuilt binary dies with SIGILL the first time it
# runs, and its first run is this installer's version check. That check was `--version 2>&1 | grep | head
# -1`: the pipeline took head's exit status, read an empty version, and told the user "refusing version
# mismatch" — true that something was wrong, false about what. Two layers are pinned here:
#   * AFTER the download, a verification run that dies or exits non-zero is a binary that COULD NOT RUN
#     (G1)-(G3); only a binary that ran and printed another version is a mismatch (G4);
#   * BEFORE the download, on x86_64, the CPU's flags are read and a CPU below v3 stops the install naming
#     what it lacks: Linux /proc/cpuinfo (G5), Intel-Mac sysctl (G9). On Linux that is EVERY processor's
#     flags record, since the binary can be scheduled on any of them: one below v3 stops it wherever it
#     sits in the file (G13, G14).
# The rest are controls, because a floor check that blocks a machine the binary runs on is worse than none:
# a v3 CPU installs (G6, G10), and so do processors whose records differ but each carry v3 (G15); unreadable
# flags never block (G1, G12); RIPWIRE_SKIP_CPU_CHECK=1 wins (G7); a pre-floor release installs on an old CPU
# (G8); Rosetta's translated bits are not judged (G11).
# Fixture flags use the names the platforms print: the kernel's arch/x86/include/asm/cpufeatures.h (LZCNT
# is "abm") and XNU's osfmk/i386/cpuid.c (AVX is "AVX1.0"; LZCNT sits in machdep.cpu.extfeatures).
GDIR="$TMP/cpufloor"
mkdir -p "$GDIR/sysctl-ivy" "$GDIR/sysctl-haswell" "$GDIR/sysctl-rosetta" "$GDIR/sysctl-partial"
# Ivy Bridge (2012) has avx and f16c but none of avx2 bmi1 bmi2 fma movbe abm; Haswell (2013) has all eight.
printf 'processor\t: 0\nvendor_id\t: GenuineIntel\nmodel name\t: Intel(R) Core(TM) i7-3770 CPU @ 3.40GHz\nflags\t\t: %s\nbugs\t\t: cpu_meltdown\n\n' \
    'fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx rdtscp lm constant_tsc pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm fsgsbase smep erms xsaveopt' \
    >"$GDIR/cpuinfo-ivy"
printf 'processor\t: 0\nvendor_id\t: GenuineIntel\nmodel name\t: Intel(R) Core(TM) i7-4770 CPU @ 3.40GHz\nflags\t\t: %s\nvmx flags\t: vnmi preemption_timer\nbugs\t\t: cpu_meltdown\n\n' \
    'fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 sdbg fma cx16 xtpr pdcm pcid sse4_1 sse4_2 x2apic movbe popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm abm cpuid_fault epb fsgsbase tsc_adjust bmi1 avx2 smep bmi2 erms invpcid xsaveopt' \
    >"$GDIR/cpuinfo-haswell"
printf '%s\n' 'FPU VME DE PSE TSC MSR PAE MCE CX8 APIC SEP MTRR PGE MCA CMOV PAT PSE36 CLFSH DS ACPI MMX FXSR SSE SSE2 SS HTT TM PBE SSE3 PCLMULQDQ DTES64 MON DSCPL VMX EST TM2 SSSE3 CX16 TPR PDCM SSE4.1 SSE4.2 x2APIC POPCNT AES PCID XSAVE OSXSAVE TSCTMR AVX1.0 RDRAND F16C' \
    >"$GDIR/sysctl-ivy/machdep.cpu.features"
printf '%s\n' 'RDWRFSGS SMEP ERMS' >"$GDIR/sysctl-ivy/machdep.cpu.leaf7_features"
printf '%s\n' 'SYSCALL XD EM64T LAHF RDTSCP TSCI' >"$GDIR/sysctl-ivy/machdep.cpu.extfeatures"
printf '%s\n' 'FPU VME DE PSE TSC MSR PAE MCE CX8 APIC SEP MTRR PGE MCA CMOV PAT PSE36 CLFSH DS ACPI MMX FXSR SSE SSE2 SS HTT TM PBE SSE3 PCLMULQDQ DTES64 MON DSCPL VMX EST TM2 SSSE3 FMA CX16 TPR PDCM SSE4.1 SSE4.2 x2APIC MOVBE POPCNT AES PCID XSAVE OSXSAVE SEGLIM64 TSCTMR AVX1.0 RDRAND F16C' \
    >"$GDIR/sysctl-haswell/machdep.cpu.features"
printf '%s\n' 'RDWRFSGS TSC_THREAD_OFFSET BMI1 HLE AVX2 SMEP BMI2 ERMS INVPCID RTM FPU_CSDS' >"$GDIR/sysctl-haswell/machdep.cpu.leaf7_features"
printf '%s\n' 'SYSCALL XD 1GBPAGE EM64T LAHF LZCNT RDTSCP TSCI' >"$GDIR/sysctl-haswell/machdep.cpu.extfeatures"
# Rosetta: a translated shell reads the translator's bits, here pre-v3. Partial: a v3 Mac whose kernel lacks
# two of the three keys — a check that reads what it can and judges the rest as missing would refuse it.
cp "$GDIR/sysctl-ivy/"* "$GDIR/sysctl-rosetta/"; printf '1\n' >"$GDIR/sysctl-rosetta/sysctl.proc_translated"
cp "$GDIR/sysctl-haswell/machdep.cpu.features" "$GDIR/sysctl-partial/"

g_release()
{
    # g_release VERSION OS ARCH BINARY-BODY -> a checksummed ripwire-VERSION-OS-ARCH archive + release JSON
    _n="ripwire-$1-$2-$3"
    rm -rf "${GDIR:?}/$_n"; mkdir -p "$GDIR/$_n"
    printf '#!/bin/sh\n%s\n' "$4" >"$GDIR/$_n/ripwire"; chmod +x "$GDIR/$_n/ripwire"
    tar -C "$GDIR" -czf "$GDIR/$_n.tar.gz" "$_n"
    ( cd "$GDIR" && shasum -a 256 "$_n.tar.gz" >"$_n.tar.gz.sha256" )
    printf '%s\n' "{\"tag_name\":\"v$1\",\"assets\":[" "{\"browser_download_url\":\"https://example.invalid/$_n.tar.gz\"}" ']}' >"$GDIR/release.json"
    G_ASSET="$GDIR/$_n.tar.gz"; G_TAG="v$1"
}
g_install()
{
    # g_install NAME UNAME_S UNAME_M [env...] -> $GDIR/NAME.{out,err,curl,prefix}, rc in $G_RC. The CPU seams
    # default to EMPTY so no arm reads the host's real CPU by accident; each arm names the one it tests.
    _n="$1"; _s="$2"; _m="$3"; shift 3
    rm -rf "${GDIR:?}/$_n.prefix"; : >"$GDIR/$_n.curl"
    env RIPWIRE_CPUINFO= RIPWIRE_SKIP_CPU_CHECK= FAKE_SYSCTL_DIR= "$@" HOME="$SBHOME" PATH="$FAKE:$PATH" \
        FAKE_UNAME_S="$_s" FAKE_UNAME_M="$_m" CURL_LOG="$GDIR/$_n.curl" RELEASE_FIXTURE="$GDIR/release.json" ASSET_FIXTURE="$G_ASSET" \
        RIPWIRE_REPO=redhat-et/ripwire RIPWIRE_VERSION="$G_TAG" RIPWIRE_INSTALL_PREFIX="$GDIR/$_n.prefix" RIPWIRE_INSTALL_YES=1 \
        RIPWIRE_NO_ACTIVATE=1 bash "$INSTALL" >"$GDIR/$_n.out" 2>"$GDIR/$_n.err"; G_RC=$?
}
g_said(){ tr '\n' ' ' <"$GDIR/$1.err" | cut -c1-260; }

# (G1) THE REPORTED DEFECT. The binary dies with 132 at its verification run, and the CPU flags could not be
# read, so nothing stopped the download: the verification run is the only layer left, and it must say CPU.
g_release 0.6.0 linux x64 'exit 132'
g_install g1 Linux x86_64 RIPWIRE_CPUINFO="$GDIR/no-such-cpuinfo"
if [ "$G_RC" -ne 0 ] && grep -q 'x86-64-v3' "$GDIR/g1.err" && ! grep -q 'version mismatch' "$GDIR/g1.err"; then
    ok "(G1) a verification run that dies with 132 (SIGILL) names the x86-64-v3 requirement, not a version mismatch"
else
    no "(G1) a SIGILL at the verification run was reported as: $( g_said g1 ) (rc=$G_RC)"
fi
if grep -qF -e '-DRIPWIRE_NATIVE=ON' "$GDIR/g1.err" && grep -q 'tar\.gz' "$GDIR/g1.curl" && [ ! -e "$GDIR/g1.prefix/bin/ripwire" ]; then
    ok "(G1) unreadable CPU flags did not block the download; the refusal names the native source build and installs nothing"
else
    no "(G1) unreadable flags blocked the download, the -DRIPWIRE_NATIVE=ON source build went unnamed, or a binary was installed"
fi

# (G2) SIGILL on arm64 is still a binary that could not run — but there is no x86-64 floor to blame.
g_release 0.6.0 linux arm64 'exit 132'
g_install g2 Linux aarch64
if [ "$G_RC" -ne 0 ] && grep -q 'SIGILL' "$GDIR/g2.err" && ! grep -q 'x86-64-v3\|version mismatch' "$GDIR/g2.err"; then
    ok "(G2) an arm64 SIGILL is named as SIGILL, with no x86-64-v3 claim and no version-mismatch claim"
else
    no "(G2) an arm64 SIGILL was reported as: $( g_said g2 ) (rc=$G_RC)"
fi

# (G3) A binary that exits non-zero on its own (a loader refusing an older glibc) could not run either; its
# own words are the diagnosis, and a CPU claim would be as wrong as the version claim was.
g_release 0.6.0 linux x64 'echo "ripwire: /lib64/libc.so.6: version GLIBC_2.38 not found (required by ripwire)" >&2; exit 1'
g_install g3 Linux x86_64 RIPWIRE_CPUINFO="$GDIR/cpuinfo-haswell"
if [ "$G_RC" -ne 0 ] && grep -q 'GLIBC_2.38 not found' "$GDIR/g3.err" && ! grep -q 'x86-64-v3\|version mismatch' "$GDIR/g3.err"; then
    ok "(G3) a binary that exits 1 is reported with its own output, not as a version mismatch or a CPU floor"
else
    no "(G3) a binary that exits 1 was reported as: $( g_said g3 ) (rc=$G_RC)"
fi

# (G4) CONTROL: a binary that RAN and printed another version is still, and only, a version mismatch.
g_release 0.6.0 linux x64 'echo "ripwire 0.5.9 (Release, Test)"'
g_install g4 Linux x86_64 RIPWIRE_CPUINFO="$GDIR/cpuinfo-haswell"
if [ "$G_RC" -ne 0 ] && grep -q 'version mismatch' "$GDIR/g4.err" && ! grep -q 'x86-64-v3\|SIGILL' "$GDIR/g4.err"; then
    ok "(G4) a genuine tag/binary version mismatch is still reported as a version mismatch"
else
    no "(G4) a genuine version mismatch was reported as: $( g_said g4 ) (rc=$G_RC)"
fi

# (G5) Linux below v3 stops BEFORE the download and names exactly what the CPU lacks — avx and f16c are
# present on Ivy Bridge, so naming them would be a detector reading the wrong line or the wrong names.
g_release 0.6.0 linux x64 'echo "ripwire 0.6.0 (Release, Test)"'
g_install g5 Linux x86_64 RIPWIRE_CPUINFO="$GDIR/cpuinfo-ivy"
G5LINE=" $( grep -i 'missing' "$GDIR/g5.err" | head -1 ) "
g5named=1
for feature in AVX2 BMI1 BMI2 FMA MOVBE LZCNT; do
    case "$G5LINE" in *" $feature "*) ;; *) g5named=0 ;; esac
done
case "$G5LINE" in *" AVX "*|*" F16C "*) g5named=0 ;; esac
if [ "$G_RC" -ne 0 ] && [ "$g5named" -eq 1 ] && grep -q 'x86-64-v3' "$GDIR/g5.err"; then
    ok "(G5) a below-v3 /proc/cpuinfo stops the install naming exactly AVX2 BMI1 BMI2 FMA MOVBE LZCNT"
else
    no "(G5) a below-v3 cpuinfo was reported as: $( g_said g5 ) (rc=$G_RC)"
fi
if ! grep -q 'tar\.gz' "$GDIR/g5.curl" && [ ! -e "$GDIR/g5.prefix/bin/ripwire" ] && grep -qF -e '-DRIPWIRE_NATIVE=ON' "$GDIR/g5.err"; then
    ok "(G5) the refusal comes before the archive is downloaded, installs nothing, and names the native source build"
else
    no "(G5) a below-v3 CPU still downloaded the archive, installed it, or went without the source-build route"
fi

# (G6) CONTROL: a v3 cpuinfo, LZCNT spelled "abm" as the kernel prints it, installs.
g_install g6 Linux x86_64 RIPWIRE_CPUINFO="$GDIR/cpuinfo-haswell"
[ "$G_RC" -eq 0 ] && [ -x "$GDIR/g6.prefix/bin/ripwire" ] \
    && ok "(G6) a v3 /proc/cpuinfo installs" || no "(G6) a v3 CPU was refused: $( g_said g6 ) (rc=$G_RC)"

# (G7) CONTROL: the user's override wins over a verdict they know is wrong (a VM hiding a flag its host has).
g_install g7 Linux x86_64 RIPWIRE_CPUINFO="$GDIR/cpuinfo-ivy" RIPWIRE_SKIP_CPU_CHECK=1
[ "$G_RC" -eq 0 ] && [ -x "$GDIR/g7.prefix/bin/ripwire" ] \
    && ok "(G7) RIPWIRE_SKIP_CPU_CHECK=1 skips the CPU check" || no "(G7) RIPWIRE_SKIP_CPU_CHECK=1 was ignored: $( g_said g7 ) (rc=$G_RC)"

# (G8) CONTROL: 0.5.x and earlier were built without the floor, so pinning one on an old CPU still installs.
g_release 0.5.0 linux x64 'echo "ripwire 0.5.0 (Release, Test)"'
g_install g8 Linux x86_64 RIPWIRE_CPUINFO="$GDIR/cpuinfo-ivy"
[ "$G_RC" -eq 0 ] && [ -x "$GDIR/g8.prefix/bin/ripwire" ] \
    && ok "(G8) a pre-floor release (v0.5.0) installs on a below-v3 CPU" || no "(G8) a pre-floor release was refused: $( g_said g8 ) (rc=$G_RC)"

# (G9) An Intel Mac below v3 stops before the download, read from sysctl.
g_release 0.6.0 macos x64 'echo "ripwire 0.6.0 (Release, Test)"'
g_install g9 Darwin x86_64 FAKE_SYSCTL_DIR="$GDIR/sysctl-ivy"
if [ "$G_RC" -ne 0 ] && grep -q 'x86-64-v3' "$GDIR/g9.err" && grep -i 'missing' "$GDIR/g9.err" | grep -q 'AVX2.*LZCNT' \
   && ! grep -q 'tar\.gz' "$GDIR/g9.curl"; then
    ok "(G9) an Intel Mac below v3 (sysctl) stops before the download, naming AVX2 through LZCNT"
else
    no "(G9) an Intel Mac below v3 was reported as: $( g_said g9 ) (rc=$G_RC)"
fi

# (G10) CONTROL: an Intel Mac with v3 installs — the arm that fails if AVX is looked up by the wrong name.
g_install g10 Darwin x86_64 FAKE_SYSCTL_DIR="$GDIR/sysctl-haswell"
[ "$G_RC" -eq 0 ] && [ -x "$GDIR/g10.prefix/bin/ripwire" ] \
    && ok "(G10) an Intel Mac with v3 (AVX1.0, leaf7 AVX2/BMI1/BMI2, extfeatures LZCNT) installs" \
    || no "(G10) a v3 Intel Mac was refused: $( g_said g10 ) (rc=$G_RC)"

# (G11) CONTROL: under Rosetta the feature bits describe the translator; the pre-check does not judge them.
g_install g11 Darwin x86_64 FAKE_SYSCTL_DIR="$GDIR/sysctl-rosetta"
[ "$G_RC" -eq 0 ] && [ -x "$GDIR/g11.prefix/bin/ripwire" ] \
    && ok "(G11) a Rosetta-translated shell is not refused on the translator's feature bits" \
    || no "(G11) a Rosetta shell was refused on translated bits: $( g_said g11 ) (rc=$G_RC)"

# (G12) CONTROL: a sysctl key that does not exist means no verdict, not "every feature in it is missing".
g_install g12 Darwin x86_64 FAKE_SYSCTL_DIR="$GDIR/sysctl-partial"
[ "$G_RC" -eq 0 ] && [ -x "$GDIR/g12.prefix/bin/ripwire" ] \
    && ok "(G12) a Mac whose sysctl lacks the leaf7/extfeatures keys is not refused" \
    || no "(G12) missing sysctl keys were judged as missing features: $( g_said g12 ) (rc=$G_RC)"

# (G13)-(G15) EVERY PROCESSOR, NOT THE FIRST. /proc/cpuinfo carries one "flags" record per online processor, and
# the binary can be scheduled on any of them: a feature one processor lacks is a SIGILL the first time the
# scheduler lands there. The records below are the Haswell one and edits of it; each keeps its "vmx flags"
# line, which a check that matched "flags" anywhere on a line would take for a processor lacking everything.
g_cpuinfo2()
{
    # g_cpuinfo2 FILE FLAGS0 FLAGS1 -> a two-processor cpuinfo (the format is applied once per processor)
    printf 'processor\t: %s\nvendor_id\t: GenuineIntel\nflags\t\t: %s\nvmx flags\t: vnmi preemption_timer\nbugs\t\t: cpu_meltdown\n\n' \
        0 "$2" 1 "$3" >"$1"
}
g_names_exactly()
{
    # g_names_exactly NAME FEATURE... -> 0 when the refusal's "missing" line names exactly those v3 features
    _line=" $( grep -i 'missing' "$GDIR/$1.err" | head -1 ) "; shift
    for _f in AVX AVX2 BMI1 BMI2 F16C FMA MOVBE LZCNT; do
        case " $* " in *" $_f "*) _want=1 ;; *) _want=0 ;; esac
        case "$_line" in *" $_f "*) _has=1 ;; *) _has=0 ;; esac
        [ "$_want" = "$_has" ] || return 1
    done
}
gV3Flags="$( sed -n 's/^flags[[:space:]]*: //p' "$GDIR/cpuinfo-haswell" )"
gV3Other="${gV3Flags/ abm / lzcnt }"; gV3Other="${gV3Other/ vmx / } hypervisor"
[ "${gV3Flags/ avx2 / }" != "$gV3Flags" ] && [ "${gV3Flags/ fma / }" != "$gV3Flags" ] \
    || no "(G13)-(G14) fixture: the Haswell flags record was not read back, so no record lacks avx2 or fma"
case " $gV3Other " in *" abm "*|*" vmx "*) no "(G15) fixture: the second complete record did not diverge from the first" ;; esac
g_cpuinfo2 "$GDIR/cpuinfo-second-lacks" "$gV3Flags" "${gV3Flags/ avx2 / }"
g_cpuinfo2 "$GDIR/cpuinfo-first-lacks" "${gV3Flags/ fma / }" "$gV3Flags"
g_cpuinfo2 "$GDIR/cpuinfo-both-v3" "$gV3Flags" "$gV3Other"
g_release 0.6.0 linux x64 'echo "ripwire 0.6.0 (Release, Test)"'

# (G13) THE REVIEWED DEFECT. Processor 0 has all of v3, processor 1 lacks avx2. Reading only the first record
# approved it; the install must stop before the download naming AVX2, and only AVX2 — the rest are on both.
g_install g13 Linux x86_64 RIPWIRE_CPUINFO="$GDIR/cpuinfo-second-lacks"
if [ "$G_RC" -ne 0 ] && g_names_exactly g13 AVX2 && ! grep -q 'tar\.gz' "$GDIR/g13.curl" && [ ! -e "$GDIR/g13.prefix/bin/ripwire" ]; then
    ok "(G13) a second processor without avx2 stops the install before the download, naming exactly AVX2"
else
    no "(G13) a second processor without avx2 was not refused before the download: $( g_said g13 ) (rc=$G_RC)"
fi

# (G14) The same verdict when the lacking processor comes FIRST: the intersection decides, not the file order,
# so a check that reads only the last record (or any one record that has the feature) fails here.
g_install g14 Linux x86_64 RIPWIRE_CPUINFO="$GDIR/cpuinfo-first-lacks"
if [ "$G_RC" -ne 0 ] && g_names_exactly g14 FMA && ! grep -q 'tar\.gz' "$GDIR/g14.curl" && [ ! -e "$GDIR/g14.prefix/bin/ripwire" ]; then
    ok "(G14) a first processor without fma stops the install before the download, naming exactly FMA"
else
    no "(G14) a first processor without fma was not refused before the download: $( g_said g14 ) (rc=$G_RC)"
fi

# (G15) CONTROL: two records that DIFFER but each carry all of v3 install. The second spells LZCNT "lzcnt" where
# the first says "abm", so a check that intersects the raw names before accepting either spelling refuses it.
g_install g15 Linux x86_64 RIPWIRE_CPUINFO="$GDIR/cpuinfo-both-v3"
[ "$G_RC" -eq 0 ] && [ -x "$GDIR/g15.prefix/bin/ripwire" ] \
    && ok "(G15) two different processor records that each carry v3 (LZCNT as abm on one, lzcnt on the other) install" \
    || no "(G15) processors that each carry v3 were refused: $( g_said g15 ) (rc=$G_RC)"

if [ "${1:-}" != "--isolation-child" ]; then
    python3 "$ROOT/test/installer_isolation.py" "${RIPWIRE_BIN:-$ROOT/build/ripwire}" \
        || no "installer gates escaped their fixture homes or failed with inherited overrides"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }

#!/usr/bin/env bash
# releaseinstallcheck.sh — the published archive and curl installer form one delivery contract.
# The release tag, binary version, asset name, bundled skills/hooks, checksum, and extracted paths
# must agree; a green build with a stale version is not a usable release.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
INSTALL="$ROOT/scripts/install.sh"
WORKFLOW="$ROOT/.github/workflows/release.yml"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
# Detection and activation must use only the per-invocation homes below.
unset CODEX_HOME AGENTS_HOME HERMES_HOME RIPWIRE_NO_ACTIVATE
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
case "$url" in
    *api.github.com*) src="$RELEASE_FIXTURE" ;;
    *.sha256) src="$ASSET_FIXTURE.sha256" ;;
    *) src="$ASSET_FIXTURE" ;;
esac
if [ -n "$out" ]; then cp "$src" "$out"; else cat "$src"; fi
EOF
cat >"$FAKE/uname" <<'EOF'
#!/bin/sh
case "$1" in -s) echo Darwin;; -m) echo arm64;; *) /usr/bin/uname "$@";; esac
EOF
chmod +x "$FAKE/curl" "$FAKE/uname"

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

if [ "${1:-}" != "--isolation-child" ]; then
    python3 "$ROOT/test/installer_isolation.py" "${RIPWIRE_BIN:-$ROOT/build/ripwire}" \
        || no "installer gates escaped their fixture homes or failed with inherited overrides"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }

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
    env "$@" HOME="$_h" PATH="$FAKE:$PATH" RELEASE_FIXTURE="$TMP/release.json" \
        ASSET_FIXTURE="$TMP/assets/ripwire-0.3.6-macos-arm64.tar.gz" \
        RIPWIRE_REPO=redhat-et/ripwire RIPWIRE_VERSION=v0.3.6 RIPWIRE_INSTALL_PREFIX="$_p" RIPWIRE_INSTALL_YES=1 \
        bash "$INSTALL" >"$TMP/e.out" 2>"$TMP/e.err"; E_RC=$?
}

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

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }

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
printf '%s\n' '#!/bin/sh' >"$TMP/assets/ripwire-0.3.6-macos-arm64/skills/install.sh"
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

PREFIX="$TMP/prefix"
if PATH="$FAKE:$PATH" RELEASE_FIXTURE="$TMP/release.json" ASSET_FIXTURE="$TMP/assets/ripwire-0.3.6-macos-arm64.tar.gz" \
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
if PATH="$FAKE:$PATH" RELEASE_FIXTURE="$TMP/release.json" ASSET_FIXTURE="$TMP/assets/ripwire-0.3.6-macos-arm64.tar.gz" \
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
if PATH="$FAKE:$PATH" RELEASE_FIXTURE="$TMP/release.json" ASSET_FIXTURE="$TMP/assets/ripwire-0.3.6-macos-arm64.tar.gz" \
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

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }

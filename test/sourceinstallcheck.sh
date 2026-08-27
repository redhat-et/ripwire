#!/usr/bin/env bash
# sourceinstallcheck.sh — a source install is one coherent Ripwire distribution, not a new binary
# beside stale agent assets. Drives the already-configured build selected by RIPWIRE_BIN into a
# temporary prefix, compares every staged skill/hook byte-for-byte with this checkout, and proves
# the installed binary's wrap recipe resolves that staged installer when no checkout is the cwd.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
BUILD="$( cd "$( dirname "$BIN" )" && pwd )"
[ -f "$BUILD/cmake_install.cmake" ] || { echo "no cmake_install.cmake beside $BIN"; exit 2; }

echo "sourceinstallcheck: BIN=$BIN"
if cmake --install "$BUILD" --prefix "$TMP/prefix" --component ripwire >"$TMP/install.out" 2>"$TMP/install.err"; then
    ok "CMake source install succeeds into an isolated prefix"
else
    no "CMake source install failed: $( tail -1 "$TMP/install.err" )"
fi

[ -x "$TMP/prefix/bin/ripwire" ] \
    && ok "installed prefix contains the binary" \
    || no "installed prefix has no executable bin/ripwire"

if diff -qr "$ROOT/skills" "$TMP/prefix/share/ripwire/skills" >"$TMP/skills.diff" 2>&1; then
    ok "installed skills byte-match the checkout (including installer and references)"
else
    no "installed skills drift from the checkout: $( head -1 "$TMP/skills.diff" )"
fi

if diff -qr "$ROOT/hooks" "$TMP/prefix/share/ripwire/hooks" >"$TMP/hooks.diff" 2>&1; then
    ok "installed hooks byte-match the checkout"
else
    no "installed hooks drift from the checkout: $( head -1 "$TMP/hooks.diff" )"
fi

WRAP="$( cd "$TMP" && "$TMP/prefix/bin/ripwire" wrap codex --force 2>&1 )"
case "$WRAP" in
    *"$TMP/prefix/share/ripwire/skills/install.sh\" --codex"*)
        ok "installed wrap recipe resolves the staged Codex installer" ;;
    *)  no "installed wrap recipe does not resolve the staged Codex installer" ;;
esac

if [ "$fail" -eq 0 ]; then echo; echo "ALL PASS"; else echo; echo "SOME CHECKS FAILED"; fi
exit "$fail"

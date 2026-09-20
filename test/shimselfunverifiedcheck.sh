#!/usr/bin/env bash
# shimselfunverifiedcheck.sh — codexdoctor.h::shimBinaryCheck must not report ok=1/same_file="0" when
# selfPath is empty (this process's own executable path could not be determined): that claims a byte
# comparison that never ran. It must instead say self_unverified="1" (review item 3, optional list).
# Unit-level: compiles codexdoctor.h standalone (same pattern selfcontainedcheck.sh uses for
# embedded_skills.h) and calls shimBinaryCheck("") directly, sidestepping the OS-specific question of
# how selfExecutablePath() itself ever comes back empty in a real run.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

TMP="$( mktemp -d )"
trap 'rm -rf "$TMP"' EXIT

generatedDir="$( dirname "$BIN" )/generated"
if [ ! -f "$generatedDir/embedded_skills.h" ]; then
    if cmake -S "$ROOT" -B "$TMP/model" -DFETCHCONTENT_FULLY_DISCONNECTED=ON >"$TMP/configure.log" 2>&1; then
        generatedDir="$TMP/model/generated"
    else
        no "could not configure the embedded-skills model"
        cat "$TMP/configure.log"
        exit 1
    fi
fi

cat > "$TMP/probe.cpp" <<'CPP'
#include "codexdoctor.h"
#include <cstdio>

int main()
{
    const rw::codexdoctor::Check c = rw::codexdoctor::shimBinaryCheck( "" );
    std::printf( "ok=%d attrs=%s\n", c.ok ? 1 : 0, c.attrs.c_str() );
    return 0;
}
CPP

if ! "${CXX:-c++}" -std=c++23 -I"$ROOT/src" -I"$generatedDir" "$TMP/probe.cpp" -o "$TMP/probe" 2>"$TMP/build.log"; then
    no "probe failed to compile"
    cat "$TMP/build.log"
    exit 1
fi

# Fixture: exactly one managed mise install, so resolveManagedInstall() returns a candidate and the
# probe actually reaches the branch under test (an empty resolveManagedInstall() would instead hit the
# managed_unverified arm below it, proving nothing about the fix).
d="$( mktemp -d )"
. "$ROOT/test/lib/unset-agent-env-variables.sh"
export HOME="$d"
export MISE_DATA_DIR="$d/mise"
mkdir -p "$MISE_DATA_DIR/installs/ripwire/0.9.9/bin"
cp "$BIN" "$MISE_DATA_DIR/installs/ripwire/0.9.9/bin/ripwire"

out="$( "$TMP/probe" )"
rm -rf "$d"

echo "$out" | grep -q 'ok=1' || { no "shimBinaryCheck with empty selfPath is not ok=1 (should still be a disclosed-unknown, not a failure): $out"; }
echo "$out" | grep -q 'self_unverified="1"' \
    && ok "empty selfPath is reported as self_unverified=\"1\", not a false same_file comparison" \
    || no "empty selfPath was NOT reported as self_unverified=\"1\": $out"
echo "$out" | grep -q 'same_file=' \
    && no "empty selfPath still emitted same_file= — a comparison that never ran must not be claimed: $out" \
    || ok "no same_file= attribute is emitted when no comparison ran"

[ "$fail" = 0 ] && echo "PASS: shimselfunverifiedcheck" || exit 1

#!/usr/bin/env bash
# stemguardcheck — the guarded stem score (src/stemguard.h): a stem-only match never outscores an exact one.
#
#   (unit)  test/verify_stemguard.cpp builds with the G1 sanitizers (-fno-sanitize-recover=all) and passes.
#   (red)   the same test built with RIPWIRE_STEMGUARD_THETA=1.0 must FAIL. A theta of 1 breaks the proof, so a
#           green run there means the property tests no longer check the guarantee.
#   (prune) --for with and without RIPWIRE_NO_PRUNE=1 is byte-identical: the pruned and exhaustive branches share
#           one scoring lambda, and the MaxScore bound must stay a bound.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; FAIL=1; }
CXX="${CXX:-c++}"
DOCTEST="$ROOT/third_party/deps/doctest"
SAN="-fsanitize=address,undefined,float-divide-by-zero -fno-sanitize-recover=all"
# A host without the sanitizer runtime still runs the property tests, and says so.
echo 'int main(){}' > "$TMP/probe.cpp"
SANNOTE="under ASan and UBSan"
if ! "$CXX" $SAN "$TMP/probe.cpp" -o "$TMP/probe" > /dev/null 2>&1; then
    SAN=""
    SANNOTE="WITHOUT sanitizers (runtime not installed on this host)"
fi
echo "stemguardcheck: BIN=$BIN"

build(){ "$CXX" -std=c++23 -O1 -g $SAN "$@" -I"$ROOT/src" -I"$DOCTEST" "$ROOT/test/verify_stemguard.cpp" -o "$TMP/$OUT" 2> "$TMP/$OUT.log"; }

OUT=unit
if build && "$TMP/unit" > "$TMP/unit.out" 2>&1; then
    ok "(unit) verify_stemguard passes $SANNOTE"
else
    no "(unit) verify_stemguard failed"; tail -15 "$TMP/unit.log" "$TMP/unit.out" 2>/dev/null
fi

OUT=red
if build -DRIPWIRE_STEMGUARD_THETA=1.0 && ! "$TMP/red" > "$TMP/red.out" 2>&1; then
    ok "(red) theta = 1.0 fails the guarantee tests"
else
    no "(red) theta = 1.0 did not fail: the property tests do not check the guarantee"
fi

if [ -x "$BIN" ]; then
    export XDG_CACHE_HOME="$TMP/xdg"; mkdir -p "$XDG_CACHE_HOME"
    FIX="$ROOT/test/routefix"
    "$BIN" "$FIX" --for="resolve graph edges" --no-cache > "$TMP/pruned.xml" 2>/dev/null
    RIPWIRE_NO_PRUNE=1 "$BIN" "$FIX" --for="resolve graph edges" --no-cache > "$TMP/exhaustive.xml" 2>/dev/null
    if [ -s "$TMP/pruned.xml" ] && cmp -s "$TMP/pruned.xml" "$TMP/exhaustive.xml"; then
        ok "(prune) pruned and exhaustive --for output are byte-identical"
    else
        no "(prune) pruned and exhaustive --for output differ or are empty"
    fi
else
    no "(prune) no ripwire binary at $BIN"
fi

[ "$FAIL" -eq 0 ] && echo "stemguardcheck: ALL PASS" || echo "stemguardcheck: FAILURES"
exit "$FAIL"

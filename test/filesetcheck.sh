#!/usr/bin/env bash
# filesetcheck.sh: src/infra/fileSetStore.h against an independent oracle, under the full G1 sanitizer set: diamonds,
# cycles, self edges, duplicates, out-of-range ids, empty rows, at every chunk size and through the sampled choice. The
# chunk sizes are what reach the multi-chunk read paths: no row of a real repo crosses a 16-bit chunk below 65,536 files.
# Independent of the ripwire binary. Usage: bash test/filesetcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/scripts/asanprobe.sh"
CXX="$( ripwire_asan_pick_cxx "${CXX:-}" )"
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
if ! ripwire_asan_probe "$CXX" "$WORK"; then
    echo "filesetcheck: SKIP: $RIPWIRE_ASAN_PROBE_WHY"
    exit 0
fi
SAN="-fsanitize=address,undefined,integer,float-divide-by-zero,float-cast-overflow"
printf 'int main(){return 0;}\n' > "$WORK/probe.cpp"
"$CXX" $SAN -fsyntax-only "$WORK/probe.cpp" 2>/dev/null || SAN="-fsanitize=address,undefined"
fail=0
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
SRC="${FILESET_UNIT_INCLUDE:-$ROOT/src}"   # a mutant copy of the header, for proving this gate can go red
if "$CXX" "$CXXSTD" -O1 -g $SAN -fno-sanitize-recover=all -I"$SRC" -I"$ROOT/src" -I"$ROOT/src/infra" -I"$ROOT/third_party" \
     "$ROOT/test/fileset_unit.cpp" "$ROOT/src/infra/diagnostics.cpp" -o "$WORK/unit" 2> "$WORK/cc.log"; then
    "$WORK/unit" || no "the unit exited $?"
else
    sed -n 1,20p "$WORK/cc.log"
    no "the unit did not compile"
fi
[ "$fail" -eq 0 ] && echo "filesetcheck: PASS" || echo "filesetcheck: FAIL"
exit "$fail"

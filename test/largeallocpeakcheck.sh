#!/usr/bin/env bash
# largeallocpeakcheck.sh — freed large blocks must not sit in the peak. src/largealloc.cpp routes operator new of
# 256 KiB or more through mmap on macOS. Linux has no route and needs none: glibc on the same fixture moved max RSS by
# 2 % with a fixed mmap threshold (CHANGELOG); the U arm still runs there, the P arms are macOS's.
#
# Arms:
#   U  the route and its table on their own (test/largeallocfix/largealloc_test.cpp): probe limit, full table, no size
#      wrap, whole request writable, blocks freed on another thread; on macOS also every replaced form, failure paths
#      and the new-handler. The binary's route is what the P arms exercise.
#   P  a generated tree whose workers' arrays walk the doubling ladder: peak with the route <= kRatio x peak with
#      RIPWIRE_TEST_LARGEALLOC=off. Same binary, same run load, so the ratio is the machine-free number. It goes red if
#      someone raises the threshold, unlinks the file, or swaps the allocator back.
#   B  the two runs' answers are byte-identical.
#   M  --max-memory still reads the routed pages: a limit under the routed peak stops the run (exit 5 or a partial answer).
# A sanitizer binary owns operator new and runs U only, and says so. Any other macOS binary must carry the route.
#
# Usage: RIPWIRE_BIN=build/ripwire bash test/largeallocpeakcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"   # no inherited agent homes or GIT_* repository selection (the gate builds a repo)
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ fail=1; printf '  FAIL  %s\n' "$*"; return 0; }

# Linux runs no peak arm, so this is what keeps the gate from passing on a binary that does not even start.
if ! "$BIN" --version 2>/dev/null | grep -q '^ripwire '; then
    echo "  FAIL  $BIN does not run"; echo "FAIL largeallocpeakcheck"; exit 1
fi

# ---- U ----
CXX="${CXX:-clang++}"
command -v "$CXX" >/dev/null 2>&1 || CXX=c++
command -v "$CXX" >/dev/null 2>&1 || CXX=g++
case "$( uname -s )" in
    Darwin) EXTRA=( -DLINK_OPERATORS "$ROOT/src/largealloc.cpp" ) ;;
    Linux)  EXTRA=( -pthread ) ;;
    *)      EXTRA=() ; echo "  SKIP  U: no mmap route on this OS"; echo "PASS largeallocpeakcheck"; exit 0 ;;
esac
if ! "$CXX" -std=c++20 -O1 -I "$ROOT/src" "$ROOT/test/largeallocfix/largealloc_test.cpp" "${EXTRA[@]}" -o "$TMP/ut" 2>"$TMP/ut.err"; then
    no "U: the unit test did not build"; sed 's/^/        /' "$TMP/ut.err" | head -20
elif [ "$( "$TMP/ut" | tail -1 )" = "UNIT_OK" ]; then
    ok "U: table, route, operators"
else
    no "U: unit arms"; "$TMP/ut" | head -20
fi

# ---- does this binary carry a route? ----
ROUTED=0
case "$( uname -s )" in
    Darwin) nm "$BIN" 2>/dev/null | grep -Eq '___(asan|tsan)_init' || ROUTED=1 ;;
esac
if [ "$ROUTED" != 1 ]; then
    echo "  SKIP  P, B, M: this binary has no large-block route ($( "$BIN" --version | head -1 ))"
    [ "$fail" = 0 ] && { echo "PASS largeallocpeakcheck"; exit 0; }
    echo "FAIL largeallocpeakcheck"; exit 1
fi

# ---- fixture: dense calls, so each worker's reference array passes 256 KiB many times over ----
FX="$TMP/fx"
python3 - "$FX" <<'P'
import os, sys
root = sys.argv[1]; files = 2000; calls = 400
for f in range(files):
    d = f"{root}/m{f % 40}"; os.makedirs(d, exist_ok=True)
    L = [f"int leaf_{f}_{k}(int x);" for k in range(8)]
    for k in range(8):
        L.append(f"int caller_{f}_{k}(int x) {{")
        L += [f"    x += leaf_{(f + c) % files}_{c % 8}(x) + helper_{c % 97}(x);" for c in range(calls // 8)]
        L.append("    return x;\n}")
    open(f"{d}/f{f}.c", "w").write("\n".join(L) + "\n")
P
git -C "$FX" init -q . 2>/dev/null

# peak MB of one run: macOS phys_footprint, else max RSS
peak(){ # outfile errfile env...
    local o="$1" e="$2"; shift 2
    if /usr/bin/time -l true >/dev/null 2>&1; then
        ( cd "$FX" && env "$@" HOME="$TMP" /usr/bin/time -l "$BIN" "$FX" --no-cache --deps >"$o" 2>"$e" )
        awk '/peak memory footprint/ { printf "%d", $1 / 1048576 }' "$e"
    else
        ( cd "$FX" && env "$@" HOME="$TMP" python3 -c '
import os, subprocess, sys
with open( sys.argv[ 1 ], "wb" ) as o:
    p = subprocess.Popen( sys.argv[ 2: ], stdout=o, stderr=subprocess.DEVNULL )
    _, _, ru = os.wait4( p.pid, 0 )
print( ru.ru_maxrss // 1024 )' "$o" "$BIN" "$FX" --no-cache --deps 2>"$e" )
    fi
}
RATIO_PCT=75
on1="$( peak "$TMP/on.out" "$TMP/on.err" X=1 )"
off1="$( peak "$TMP/off.out" "$TMP/off.err" RIPWIRE_TEST_LARGEALLOC=off )"
on2="$( peak "$TMP/on2.out" "$TMP/on2.err" X=1 )"
off2="$( peak "$TMP/off2.out" "$TMP/off2.err" RIPWIRE_TEST_LARGEALLOC=off )"
on=$(( on1 < on2 ? on1 : on2 )); off=$(( off1 < off2 ? off1 : off2 ))
echo "  peak MB with the route: $on1 $on2; without: $off1 $off2"
if [ "${on:-0}" -gt 0 ] && [ "${off:-0}" -gt 0 ] && [ $(( on * 100 )) -le $(( off * RATIO_PCT )) ]; then
    ok "P: route peak $on MB <= $RATIO_PCT % of $off MB"
else
    no "P: route peak $on MB against $off MB without it (limit $RATIO_PCT %): freed large blocks are back in the peak"
fi

# ---- B ----
if cmp -s "$TMP/on.out" "$TMP/off.out" && [ -s "$TMP/on.out" ]; then
    ok "B: answers byte-identical with and without the route"
else
    no "B: the route changed the answer"
fi

# ---- M: the guard's reading includes routed pages. Half the routed peak cannot fit. ----
lim=$(( on / 2 ))
[ "$lim" -lt 256 ] && lim=256
rc=0
( cd "$FX" && HOME="$TMP" "$BIN" "$FX" --no-cache --deps --max-memory="${lim}M" >"$TMP/m.out" 2>"$TMP/m.err" ) || rc=$?
if [ "$rc" -eq 5 ] || grep -q 'memory_stop' "$TMP/m.out" "$TMP/m.err"; then
    ok "M: --max-memory=${lim}M against a ${on} MB run stops (exit $rc)"
else
    no "M: --max-memory=${lim}M against a ${on} MB run did not stop (exit $rc): the guard does not see routed pages"
fi

if [ "$fail" = 0 ]; then echo "PASS largeallocpeakcheck"; exit 0; fi
echo "FAIL largeallocpeakcheck"; exit 1

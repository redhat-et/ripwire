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
#   D  the band M never enters: a limit at 70 % of the routed peak. The guard reads the footprint between phases, and the
#      blocks the route returned are gone from that reading, so the run finishes over its cap. It must SAY so (owner
#      2026-11-01: disclosed, not enforced): the stderr line with the peak, the cap and what the cap is for, and
#      memory_peak= in the map header; the answer is otherwise the unlimited run's. A stop (exit 5, memory_stop=) is also
#      honest. Silence is the failure (red on 38be976d, which finished at 1.0-1.3x its cap with nothing said).
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
genfx(){ # dir files calls
python3 - "$1" "$2" "$3" <<'P'
import os, sys
root = sys.argv[1]; files = int(sys.argv[2]); calls = int(sys.argv[3])
for f in range(files):
    d = f"{root}/m{f % 40}"; os.makedirs(d, exist_ok=True)
    L = [f"int leaf_{f}_{k}(int x);" for k in range(8)]
    for k in range(8):
        L.append(f"int caller_{f}_{k}(int x) {{")
        L += [f"    x += leaf_{(f + c) % files}_{c % 8}(x) + helper_{c % 97}(x);" for c in range(calls // 8)]
        L.append("    return x;\n}")
    open(f"{d}/f{f}.c", "w").write("\n".join(L) + "\n")
P
git -C "$1" init -q . 2>/dev/null
}
FX="$TMP/fx"
genfx "$FX" 2000 400

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

# ---- D: the band between the at-line reading and the peak. A 400-file tree peaks near 180 MB in ~2 s (under the guard's
#      5 s cadence, so no soft line); a limit at 70 % of the unlimited peak sits above every reading and below the peak. ----
DX="$TMP/dx"
genfx "$DX" 400 400
dpeak(){ # outfile errfile [extra args]
    local o="$1" e="$2"; shift 2
    ( cd "$DX" && HOME="$TMP" /usr/bin/time -l "$BIN" "$DX" --no-cache "$@" >"$o" 2>"$e" ); local r=$?
    echo "$r $( awk '/peak memory footprint/ { printf "%d", $1 / 1048576 }' "$e" )"
}
read -r drc0 dp0 <<<"$( dpeak "$TMP/d0.out" "$TMP/d0.err" )"
dlim=$(( dp0 * 70 / 100 )); [ "$dlim" -lt 64 ] && dlim=64
read -r drc dp <<<"$( dpeak "$TMP/d.out" "$TMP/d.err" --max-memory="${dlim}M" )"
echo "  D: unlimited peak $dp0 MB (rc $drc0); --max-memory=${dlim}M peak $dp MB (rc $drc)"
if [ "${dp0:-0}" -lt 80 ] || [ "$drc0" != 0 ]; then
    no "D: the unlimited run is too small or failed (rc $drc0, peak ${dp0:-0} MB): the band cannot be entered"
elif [ "$drc" = 5 ] || grep -q 'memory_stop=' "$TMP/d.out"; then
    ok "D: --max-memory=${dlim}M stopped the run on a real line (rc $drc), which says so itself"
elif [ "${dp:-0}" -le "$dlim" ]; then
    no "D: the capped run peaked at $dp MB, not over its ${dlim}M cap: the band was not entered"
else
    if [ "$drc" = 0 ] && grep -Eq "^ripwire: memory peak [0-9]+M went over the ${dlim}M limit \(from --max-memory\), and the run finished and answered: the guard reads the limit between phases" "$TMP/d.err" \
       && grep -q 'rule of thumb that keeps the machine from running out of memory, not an exact line — raise it with --max-memory=<N>' "$TMP/d.err"; then
        ok "D: over its ${dlim}M cap ($dp MB peak) the run finished and said so on stderr, with what the cap is for"
    else
        no "D: --max-memory=${dlim}M, peak $dp MB, rc $drc: the run went over its cap and did not say so plainly (stderr: $( grep '^ripwire' "$TMP/d.err" | head -c 300 ))"
    fi
    if grep -Eq "<!-- .* memory_peak=[0-9]+M memory_limit=${dlim}M" "$TMP/d.out"; then
        ok "D: the map header carries memory_peak= and memory_limit=${dlim}M"
    else
        no "D: the map header does not name the peak and the cap: $( grep -o '<!-- files=[^>]*-->' "$TMP/d.out" | head -1 | head -c 300 )"
    fi
    # the header comments and est_tokens= (which prices them) move with the two new terms; the rows are the answer
    if [ "$( perl -0pe 's/<!--.*?-->//gs; s/ est_tokens="[0-9]+"//' "$TMP/d.out" | md5 -q 2>/dev/null || perl -0pe 's/<!--.*?-->//gs; s/ est_tokens="[0-9]+"//' "$TMP/d.out" | md5sum )" \
         = "$( perl -0pe 's/<!--.*?-->//gs; s/ est_tokens="[0-9]+"//' "$TMP/d0.out" | md5 -q 2>/dev/null || perl -0pe 's/<!--.*?-->//gs; s/ est_tokens="[0-9]+"//' "$TMP/d0.out" | md5sum )" ]; then
        ok "D: apart from the header comments and est_tokens= the answer is the unlimited run's"
    else
        no "D: the answer differs from the unlimited run beyond the disclosure"
    fi
fi

if [ "$fail" = 0 ]; then echo "PASS largeallocpeakcheck"; exit 0; fi
echo "FAIL largeallocpeakcheck"; exit 1

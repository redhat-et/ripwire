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
#   M  --max-memory still reads the routed pages. The limit is sized from the reading the guard ALWAYS takes, the one right
#      after the ingest (main.cpp's hard line), so the stop depends neither on the 5 s cadence nor on what --deps builds
#      after the ingest (#690). It FAILS when that reading is missing, does not hold the routed reference array, or the limit
#      it sized is not below it. Then: exit 5, nothing on stdout, and the guard's own line naming the limit, with the allocator
#      line off (M) and on (Mc).
#   D  the band M never enters: a limit at 70 % of the routed peak. The guard reads the footprint between phases, and the
#      blocks the route returned are gone from that reading, so the run finishes over its cap. It must SAY so (owner
#      2026-11-01: disclosed, not enforced): the stderr line with the peak, the cap and what the cap is for, and
#      memory_peak= in the map header; the answer is otherwise the unlimited run's. A stop (exit 5, memory_stop=) is also
#      honest. Silence is the failure (red on 38be976d, which finished at 1.0-1.3x its cap with nothing said).
# A macOS binary without the route runs U only, and says so, when its build says it should not have one: a sanitizer binary
# (it owns operator new), or a build whose CMakeCache.txt beside the binary has RIPWIRE_LARGE_ALLOC=OFF, RIPWIRE_ALLOC_COUNT=ON or
# a -fsanitize= flag. Any other macOS binary must carry the route; one that does not fails here, before P can pass on noise.
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
else
    "$TMP/ut" >"$TMP/ut.out" 2>&1; urc=$?   # its exit status carries its own arms (gateexitcheck H1), not only the last line
    if [ "$urc" = 0 ] && [ "$( tail -1 "$TMP/ut.out" )" = "UNIT_OK" ]; then
        ok "U: table, route, operators"
    else
        no "U: unit arms (exit $urc)"; head -20 "$TMP/ut.out"
    fi
fi

# ---- does this binary carry a route? src/largealloc.cpp is the only source that spells RIPWIRE_TEST_LARGEALLOC, so the
#      string in the binary is the route's mark (P's peak ratio alone is not: two route-off runs can differ by 30 %). ----
ROUTED=0
case "$( uname -s )" in
    Darwin)
        if LC_ALL=C grep -aqF RIPWIRE_TEST_LARGEALLOC "$BIN"; then
            ROUTED=1
        else
            why=""
            nm "$BIN" 2>/dev/null | grep -Eq '___(asan|tsan)_init' && why="a sanitizer binary"
            CACHE="$( dirname "$BIN" )/CMakeCache.txt"
            if [ -z "$why" ] && [ -f "$CACHE" ]; then
                if grep -Eq '^RIPWIRE_LARGE_ALLOC:BOOL=(OFF|0|FALSE|NO)$' "$CACHE"; then why="built with RIPWIRE_LARGE_ALLOC=OFF"
                elif grep -Eq '^RIPWIRE_ALLOC_COUNT:BOOL=(ON|1|TRUE|YES)$' "$CACHE"; then why="built with RIPWIRE_ALLOC_COUNT=ON"
                elif grep -Eq '^(RIPWIRE_(ASAN|TSAN|FUZZ):BOOL=(ON|1|TRUE|YES)|CMAKE_CXX_FLAGS[A-Z_]*:[A-Z]+=.*-fsanitize=)' "$CACHE"; then why="a sanitizer build"
                fi
            fi
            if [ -z "$why" ]; then
                no "this macOS binary links no large-block route, and nothing says it should not (no sanitizer; $CACHE does not opt out)"
            else
                echo "  note  no large-block route: $why"
            fi
        fi ;;
esac
if [ "$ROUTED" != 1 ]; then
    echo "  SKIP  P, B, M, D: this binary has no large-block route ($( "$BIN" --version | head -1 ))"
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
# Sized so each worker's reference array passes 256 KiB many times over and the after-ingest footprint (arm M) sits well
# over the guard's 64 MB floor: 2000 files x 880 calls read ~230-245 MB after the ingest and peak near 480 MB routed on an
# M2 (main b576a95e3, 6-7 s). Until #690 arm M took half the routed peak, floored at 256 MB, and that stopped only when a
# reading landed over it: the 5 s cadence during the parse on a slow machine, or the graph build's hard line, which --deps
# no longer reaches (#648). On a fast machine the run ends inside the cadence and every reading sat under 256 MB.
FX="$TMP/fx"
genfx "$FX" 2000 880

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

# ---- M: the guard's reading includes routed pages (#690, thanks @jflowers). One unlimited run with RIPWIRE_STATS reads the
#      footprint the guard reads right after the ingest: `[mem] phase=model` is marked as ingest() returns, and main.cpp's
#      hard line reads the same footprint next, on every run whatever its speed. The limit goes a quarter under it, so that
#      reading alone must stop the run: a slow machine may stop sooner, at the cadence's soft line (half the limit), which
#      is a stop too. The allocator line (memceiling.h) is off for these two runs: it would stop the run on its own reading
#      before the hard line is asked, and it is memceilingcheck's to test. Mc then runs the same limit with it on, as
#      every user does. ----
MLINE="$TMP/m.line"
( cd "$FX" && HOME="$TMP" RIPWIRE_STATS=1 RIPWIRE_MEM_BUDGET_MB=0 "$BIN" "$FX" --no-cache --deps >"$TMP/m0.out" 2>"$TMP/m0.err" ); mrc0=$?
nread="$( grep -c '^\[mem\] phase=model cur_mib=[0-9]' "$TMP/m0.err" )"
read_mb="$( sed -n 's/^\[mem\] phase=model cur_mib=\([0-9]*\)\.[0-9].*/\1/p' "$TMP/m0.err" | tail -1 )"
refs_mb="$( sed -n 's/^\[mem\] family references .* cap_mib=\([0-9]*\)\.[0-9].*/\1/p' "$TMP/m0.err" | tail -1 )"
lim=$(( ${read_mb:-0} * 3 / 4 ))
echo "  M: after-ingest reading ${read_mb:-none} MB (readings seen: $nread, rc $mrc0), routed reference array ${refs_mb:-none} MB; limit ${lim}M"
mpremise=0
if [ "$mrc0" != 0 ] || [ "${nread:-0}" -lt 1 ] || [ -z "$read_mb" ]; then
    no "M: no after-ingest reading to size the limit from (rc $mrc0, $nread [mem] phase=model lines): the arm cannot test the stop"
elif [ -z "$refs_mb" ] || [ "$refs_mb" -lt 64 ] || [ "$read_mb" -lt "$refs_mb" ]; then
    no "M: the after-ingest reading ${read_mb} MB does not hold the routed reference array (${refs_mb:-none} MB): the footprint misses routed pages, or the fixture no longer builds the array"
elif [ "$lim" -ge "$read_mb" ] || [ "$lim" -lt 64 ]; then
    no "M: the limit ${lim}M is not below the ${read_mb} MB reading or is under the guard's 64 MB floor: the arm would pass without a stop"
else
    ok "M: limit ${lim}M sized from the ${read_mb} MB after-ingest reading, which holds the ${refs_mb} MB routed reference array"
    mpremise=1
fi
# mstop <tag> <env...>: one capped run, rc 5, nothing on stdout, and its first ripwire: line is a stop naming this limit
mstop(){
    local tag="$1"; shift
    local rc=0
    ( cd "$FX" && env "$@" HOME="$TMP" "$BIN" "$FX" --no-cache --deps --max-memory="${lim}M" >"$TMP/$tag.out" 2>"$TMP/$tag.err" ) || rc=$?
    grep -m1 '^ripwire: ' "$TMP/$tag.err" >"$MLINE"
    local how=""
    if grep -Eq "^ripwire: memory limit reached during the ingest \(limit ${lim}M, from --max-memory\); stopped cleanly without an answer" "$MLINE"; then
        how="the hard line after the ingest"
    elif grep -Eq "^ripwire: memory limit reached during the (--deps closure|include-closure fold) \(limit ${lim}M, from --max-memory\); stopped cleanly without an answer" "$MLINE"; then
        how="the --deps closure's hard line"   # read after the ingest too, on every run: a stop, though the ingest's line should come first
    elif grep -Eq "^ripwire: the memory guard stopped the (crawl|parse) (at the (crawl|parse) line \(.*the ${lim}M limit\)|under critical system memory pressure)" "$MLINE"; then
        how="a cadence reading during the ingest"
    elif grep -Eq "^ripwire: refused by the memory ceiling \(--max-memory=${lim}M\)" "$MLINE"; then
        how="the allocator line"
    fi
    if [ "$rc" = 5 ] && [ ! -s "$TMP/$tag.out" ] && [ -n "$how" ]; then
        ok "$tag: --max-memory=${lim}M under the ${read_mb} MB after-ingest reading stops (exit 5) at $how"
    else
        no "$tag: --max-memory=${lim}M under the ${read_mb} MB after-ingest reading did not stop as the guard says it does (exit $rc, stdout $( wc -c <"$TMP/$tag.out" | tr -d ' ' ) B): $( head -c 300 "$MLINE" )"
    fi
}
if [ "$mpremise" = 1 ]; then
    mstop M RIPWIRE_MEM_BUDGET_MB=0
    mstop Mc X=1
fi

# ---- D: the band between the at-line reading and the peak. The tree must peak well over the 80 MB floor below in under
#      the guard's 5 s cadence (so no soft line); a limit at 70 % of the unlimited peak sits above every reading and below
#      the peak. 400 files peaked near 180 MB when this arm was written and 108 MB on main 74456897f; with #608's 80 B
#      reference rows they peak at 71 MB on an M2 and 60 MB on CI's macOS runner, under the floor. 800 files peak at
#      ~123 MB on the M2 in ~1 s. ----
DX="$TMP/dx"
genfx "$DX" 800 400
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

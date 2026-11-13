#!/usr/bin/env bash
# textpoolcheck.sh — MEM-REF-SHRINK step 2: src/infra/internedtext.h's shared text pool (Reference / RawRef names as 4 B ids).
# Compiles test/textpool_harness.cpp (header-only: no ripwire objects) twice and runs it:
#   [g1]   the G1 sanitizer set with -fno-sanitize-recover=all: arms A-D (canonical ids under 8 threads, the empty id, text order,
#          edits) on a binary where UB or a bad slot index aborts;
#   [g1]   arms I-K (K1a LOCALTYPE-PACK): lookup never inserts; IdKeyedCsr's add order, repeats, re-seal; same answers whatever the ids;
#   N      a source scan: IdKeyedMap / IdKeyedCsr have no iteration member and IdKeyedMap is InternedTextOf's one friend;
#   [g1] also runs arm H (`exitrace`) five times: a detached thread interning while main returns must not touch a destroyed pool;
#   [tsan] ThreadSanitizer over arms A-G: a missing shard lock is a reported race (the segment pointer's acquire/release is NOT
#          observable here: see the harness's arm E note).
#          SKIP (not FAIL) when the toolchain cannot build or start a TSan binary; the g1 pass still runs.
# Usage: test/textpoolcheck.sh [BIN]   (BIN unused: the harness needs no ripwire binary). Exits non-zero on any FAIL.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/scripts/asanprobe.sh"
CXX="$( ripwire_asan_pick_cxx "${CXX:-}" )"
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
HARNESS="$ROOT/test/textpool_harness.cpp"
WORK="$( mktemp -d )"; trap 'gate_bounded_reap; rm -rf "$WORK"' EXIT; gate_bounded_arm
echo "textpoolcheck: CXX=$CXX"
fail=0

build_run()
{
    local LABEL="$1"; shift
    if ! "$CXX" "$CXXSTD" -O2 -g -Wall -Wextra "$@" -I"$ROOT/src" -I"$ROOT/third_party" "$HARNESS" "$ROOT/src/infra/diagnostics.cpp" -o "$WORK/h_$LABEL" -pthread 2> "$WORK/cc_$LABEL.log"; then
        return 3
    fi
    "$WORK/h_$LABEL" > "$WORK/out_$LABEL.log" 2>&1
}

if ripwire_asan_probe "$CXX" "$WORK"; then
    SAN="-fsanitize=address,undefined,integer,float-divide-by-zero,float-cast-overflow"
    printf 'int main(){return 0;}\n' > "$WORK/probe.cpp"
    "$CXX" $SAN -fsyntax-only "$WORK/probe.cpp" 2>/dev/null || SAN="-fsanitize=address,undefined"
    build_run g1 $SAN -fno-sanitize-recover=all; rc=$?
else
    echo "  NOTE  [g1] $RIPWIRE_ASAN_PROBE_WHY: running the plain build instead"
    build_run g1; rc=$?
fi
if [ "$rc" -eq 3 ]; then echo "  FAIL  [g1] harness failed to compile"; sed 's/^/    /' "$WORK/cc_g1.log"; exit 2; fi
if [ "$rc" -ne 0 ] || ! grep -q "textpool: ALL PASS" "$WORK/out_g1.log"; then
    echo "  FAIL  [g1] rc=$rc"; grep -v '^  PASS' "$WORK/out_g1.log" | head -20 | sed 's/^/    /'; fail=1
else
    echo "  PASS  [g1] $( grep -c '^  PASS' "$WORK/out_g1.log" ) harness arms green"
fi
# A report from the detached thread can land after main's exit status is set (rc 0), so the log, not rc alone, is the verdict.
for run in 1 2 3 4 5; do
    "$WORK/h_g1" exitrace > "$WORK/exit_$run.log" 2>&1; rc=$?
    if [ "$rc" -ne 0 ] || ! grep -q "exitrace returning" "$WORK/exit_$run.log" || grep -q "Sanitizer\|runtime error" "$WORK/exit_$run.log"; then
        echo "  FAIL  [g1] arm H run $run: rc=$rc (a detached interning thread outlived a destroyed pool?)"; grep -m 3 "ERROR\|SUMMARY" "$WORK/exit_$run.log" | sed 's/^/    /'; fail=1; break
    fi
    [ "$run" -eq 5 ] && echo "  PASS  [g1] arm H: 5/5 exits with a detached thread still interning, no sanitizer report"
done

# Arm N (K1a LOCALTYPE-PACK, owner 11-11 K1 option (a)): IdKeyedMap / IdKeyedCsr hash a pool id, whose value depends on thread
# timing, so they must stay LOOKUP-ONLY: no iteration member (begin / end / an iterator / a visitor) in either class body, and
# IdKeyedMap stays the ONE friend of InternedTextOf. Premise: both class bodies are found (fails on zero). Detector: a planted
# copy with an `auto begin()` member is flagged.
noiter_scan()   # $1 = idkeyedmap.h; prints "classes=<n> iter=<members>"
{
    python3 -I - "$1" <<'PYEOF'
import re, sys
src = open(sys.argv[1]).read()
found, hits = 0, []
for m in re.finditer(r'template\s*<[^>]*>\s*class\s+(IdKeyedMap|IdKeyedCsr)\s*\{', src):
    depth, i = 1, m.end()
    while depth and i < len(src):
        depth += {'{': 1, '}': -1}.get(src[i], 0); i += 1
    body = src[m.end():i]
    body = re.sub(r'//[^\n]*', '', body)
    found += 1
    hits += [m.group(1) + '::' + h for h in re.findall(r'(?m)^[ \t]*(?:[\w:<>,*&]+[ \t]+)+[*&]?(c?r?begin|c?r?end|iterator|const_iterator|for_each|forEach|visit|entries|items|values|keys)[ \t]*\(', body)]
print(f"classes={found} iter={','.join(hits) or 'none'}")
PYEOF
}
IKM="$ROOT/src/infra/idkeyedmap.h"
nscan="$( noiter_scan "$IKM" )"
friends="$( grep -c 'friend class IdKeyedMap' "$ROOT/src/infra/internedtext.h" )"
if [ "$nscan" != "classes=2 iter=none" ] || [ "$friends" != 1 ]; then
    echo "  FAIL  arm N: $nscan, IdKeyedMap friend declarations=$friends (want classes=2 iter=none, 1)"; fail=1
else
    sed 's/    void        clear() noexcept { map_.clear(); }/&\n    auto begin() const { return map_.begin(); }/' "$IKM" > "$WORK/planted.h"
    pscan="$( noiter_scan "$WORK/planted.h" )"
    if [ "$pscan" = "classes=2 iter=IdKeyedMap::begin" ]; then
        echo "  PASS  arm N: IdKeyedMap / IdKeyedCsr have no iteration member, one friend reads the id; a planted begin() is flagged"
    else
        echo "  FAIL  arm N detector: the planted begin() scanned as '$pscan'"; fail=1
    fi
fi

printf 'int main(){return 0;}\n' > "$WORK/tprobe.cpp"
if "$CXX" -fsanitize=thread "$WORK/tprobe.cpp" -o "$WORK/tprobe" 2>/dev/null && "$WORK/tprobe" 2>/dev/null; then
    TSAN_OPTIONS="halt_on_error=1" build_run tsan -fsanitize=thread; rc=$?
    if [ "$rc" -ne 0 ] || grep -q "WARNING: ThreadSanitizer" "$WORK/out_tsan.log" || ! grep -q "textpool: ALL PASS" "$WORK/out_tsan.log"; then
        echo "  FAIL  [tsan] rc=$rc"; grep -A 12 "ThreadSanitizer\|FAIL" "$WORK/out_tsan.log" | head -30 | sed 's/^/    /'; fail=1
    else
        echo "  PASS  [tsan] arms A-G race-free (8 interning threads)"
    fi
else
    echo "  SKIP  [tsan] this toolchain cannot build or start a ThreadSanitizer binary"
fi

[ "$fail" -eq 0 ] && echo "textpoolcheck: PASS" || echo "textpoolcheck: FAIL"
exit "$fail"

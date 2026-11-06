#!/usr/bin/env bash
# warmpeakcheck.sh — a warm run must not hold more fact memory than the cold run that wrote its cache (WARM-DIRECT,
# reports/graph-efficiency-ideas.md #4). Until cache format 49 a warm run decoded every record into a path-keyed map,
# moved the facts into the parse workers' arrays and moved them again in the merge: three sets of fact arrays at the
# parse-pool join, and a warm peak 40-49 % over the cold one on envoy, cockroach and vscode. Now a worker decodes its
# hit's record straight into its own arrays, and the merge frees each worker's array as soon as its rows have moved.
#
# Arms:
#   S  the warm run is warm: RIPWIRE_CACHE_STATS says reparsed=0 and cached_records = files.
#   B  the warm answer is byte-identical to the cold answer (and to a --no-cache run), and so is a warm map (--top-k past the
#      symbol count: it names every file's own symbols, so it sees a record decoded for the wrong file, as --deps' summary may not).
#   W  peak footprint, warm <= kWarmPct % of cold (the best of two runs each). Red when a warm-only copy of the facts
#      comes back (the decoded map, a scratch that keeps every record).
#   F  peak footprint, warm <= kFactPct % of the blob's size plus the binary's floor (a --version run): an absolute bound
#      beside W's relative one, so a change that raises cold and warm alike by more than about a quarter goes red too.
#      It does NOT see the merge keeping its moved-from per-thread arrays (mutant measured 293 vs 293 MB here, 252 vs
#      254 MB on a def-heavy tree): this tree's peak is in the model build after the merge, not at the merge, and no
#      footprint reading taken from outside the process can see a copy that is gone before the peak.
# W and F read macOS phys_footprint and need the large-block route (src/largealloc.cpp), without which freed blocks stay
# in the peak whatever the code does: elsewhere, or on a binary without the route, they SKIP by name. S and B run everywhere.
#
# Usage: RIPWIRE_BIN=build/ripwire bash test/warmpeakcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"   # no inherited agent homes or GIT_* repository selection (the gate builds a repo)
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ fail=1; printf '  FAIL  %s\n' "$*"; return 0; }
if ! "$BIN" --version 2>/dev/null | grep -q '^ripwire '; then
    echo "  FAIL  $BIN does not run"; echo "FAIL warmpeakcheck"; exit 1
fi
kWarmPct=110
kFactPct=900   # measured 2026-11-06 (Apple M2 16 GB, other builds running): this head (293 - 8) / 40 MB = 712 %, every run; the
               # keep-every-decoded-record mutant (446 - 8) / 40 = 1095 %. 900 leaves 26 % over the head and catches it.

# ---- fixture: dense calls across many files, so the reference arrays are most of the run's memory ----
FX="$TMP/fx"
python3 - "$FX" 1200 240 <<'P'
import os, sys
root = sys.argv[1]; files = int(sys.argv[2]); calls = int(sys.argv[3])
for f in range(files):
    d = f"{root}/m{f % 30}"; os.makedirs(d, exist_ok=True)
    L = [f"int leaf_{f}_{k}(int x);" for k in range(8)]
    for k in range(8):
        L.append(f"int caller_{f}_{k}(int x) {{")
        L += [f"    x += leaf_{(f + c) % files}_{c % 8}(x) + helper_{c % 97}(x);" for c in range(calls // 8)]
        L.append("    return x;\n}")
    open(f"{d}/f{f}.c", "w").write("\n".join(L) + "\n")
P
git -C "$FX" init -q . 2>/dev/null
NFILES="$( find "$FX" -name '*.c' | wc -l | tr -d ' ' )"

# one run: $1 tag, then ripwire args after the root. Prints the peak MB (macOS phys_footprint, else 0); output in $TMP/$1.{out,err}
run(){ # tag args...
    local tag="$1"; shift
    local rc=0
    ( cd "$FX" && HOME="$TMP" RIPWIRE_CACHE_STATS=1 /usr/bin/time -l "$BIN" "$FX" "$@" >"$TMP/$tag.out" 2>"$TMP/$tag.err" ) || rc=$?
    if [ "$rc" -ne 0 ]; then
        # The caller reads this function through $( ), a subshell: the FAIL line goes to stderr (stdout is the peak
        # value) and the caller sets the gate's failure from the status below, which a subshell's own `no` could not.
        { no "$tag: ripwire exited $rc ($( grep -v '^ ' "$TMP/$tag.err" | head -2 | tr '\n' ' ' ))"; } >&2
        echo 0; return 1
    fi
    awk '/peak memory footprint/ { printf "%d", $1 / 1048576; f = 1 } END { if( !f ) printf "0" }' "$TMP/$tag.err"
}
stat_of(){ sed -n "s/.*cache-stats.* $2=\([0-9]*\).*/\1/p; s/.*cache-stats $2=\([0-9]*\).*/\1/p" "$TMP/$1.err" | head -1; }
min2(){ [ "$1" -le "$2" ] && echo "$1" || echo "$2"; }

C="$TMP/blob.cache"
TIMEL=1; /usr/bin/time -l true >/dev/null 2>&1 || TIMEL=0
if [ "$TIMEL" = 0 ]; then
    # no BSD time: S and B only, through plain runs
    run(){ local tag="$1"; shift; local rc=0
        ( cd "$FX" && HOME="$TMP" RIPWIRE_CACHE_STATS=1 "$BIN" "$FX" "$@" >"$TMP/$tag.out" 2>"$TMP/$tag.err" ) || rc=$?
        [ "$rc" -ne 0 ] && { { no "$tag: ripwire exited $rc"; } >&2; echo 0; return 1; }
        echo 0; }
fi
# A failed measured run sets fail here, in the parent shell: `$( run ... )` ran in a subshell, so run's own `no` could not.
# cold2 matters most: warm2 would otherwise recreate the cache that cold2 failed to write and the gate would pass.
cold1="$( run cold1 --deps --cache="$C" )" || fail=1
warm1="$( run warm1 --deps --cache="$C" )" || fail=1
blobMB=$(( $( wc -c <"$C" 2>/dev/null || echo 0 ) / 1048576 ))
rm -f "$C"
cold2="$( run cold2 --deps --cache="$C" )" || fail=1
[ -s "$C" ] || no "cold2 wrote no cache: warm2 below would run cold and the warm arms would measure nothing"
warm2="$( run warm2 --deps --cache="$C" )" || fail=1
run nocache --deps --no-cache >/dev/null
# the map with --top-k above the symbol count lists EVERY file's own symbols (the default 200-row map names 12 of the 1200
# files, so a swap between two omitted files would pass), so a record decoded into the wrong file shows here (--deps'
# summary can be blind to a swap between two files of the same shape); served from the same cache, warm
run warmmap --cache="$C" --top-k=1000000 >/dev/null
run nocachemap --no-cache --top-k=1000000 >/dev/null

# ---- S ----
rp="$( stat_of warm1 reparsed )"; cr="$( stat_of warm1 cached_records )"; fl="$( stat_of warm1 files )"
if [ "$rp" = 0 ] && [ -n "$cr" ] && [ "$cr" = "$fl" ] && [ "$fl" = "$NFILES" ]; then
    ok "S: warm run reparsed=0 cached_records=$cr of $NFILES files"
else
    no "S: warm run is not fully warm (reparsed=${rp:-?} cached_records=${cr:-?} files=${fl:-?}, tree has $NFILES)"
fi
# ---- B ----
if [ -s "$TMP/cold1.out" ] && cmp -s "$TMP/cold1.out" "$TMP/warm1.out" && cmp -s "$TMP/cold1.out" "$TMP/warm2.out" && cmp -s "$TMP/cold1.out" "$TMP/nocache.out"; then
    ok "B: warm answers byte-identical to cold and to --no-cache ($( wc -c <"$TMP/cold1.out" | tr -d ' ' ) B)"
else
    no "B: a warm answer differs from the cold one"
fi
mrp="$( stat_of warmmap reparsed )"
mapfiles="$( grep -o '<f p="' "$TMP/nocachemap.out" | wc -l | tr -d ' ' )"
if [ "$mapfiles" != "$NFILES" ]; then
    no "B: the exhaustive map names $mapfiles of $NFILES files: it cannot see a record served for an omitted file"
elif [ -s "$TMP/nocachemap.out" ] && [ "$mrp" = 0 ] && cmp -s "$TMP/warmmap.out" "$TMP/nocachemap.out"; then
    ok "B: warm map (reparsed=0) byte-identical to --no-cache ($( wc -c <"$TMP/nocachemap.out" | tr -d ' ' ) B)"
else
    no "B: the warm map differs from the --no-cache one, or was not warm (reparsed=${mrp:-?}): a record served for the wrong file"
fi

# ---- W, F: macOS with the large-block route only ----
if [ "$( uname -s )" != Darwin ] || [ "$TIMEL" = 0 ]; then
    echo "  SKIP  W, F: peak footprint arms read macOS phys_footprint"
elif ! LC_ALL=C grep -aqF RIPWIRE_TEST_LARGEALLOC "$BIN"; then
    echo "  SKIP  W, F: this binary has no large-block route (a sanitizer or opted-out build), so freed blocks stay in the peak"
else
    cold="$( min2 "$cold1" "$cold2" )"; warm="$( min2 "$warm1" "$warm2" )"
    floor="$( ( cd "$TMP" && /usr/bin/time -l "$BIN" --version >/dev/null 2>"$TMP/floor.err" ); awk '/peak memory footprint/ { printf "%d", $1 / 1048576 }' "$TMP/floor.err" )"
    echo "  peak MB cold: $cold1 $cold2; warm: $warm1 $warm2; blob $blobMB MB; floor ${floor:-?} MB"
    if [ "$cold" -gt 0 ] && [ "$warm" -gt 0 ] && [ $(( warm * 100 )) -le $(( cold * kWarmPct )) ]; then
        ok "W: warm peak $warm MB <= $kWarmPct % of cold $cold MB"
    else
        no "W: warm peak $warm MB against cold $cold MB (limit $kWarmPct %): a warm-only copy of the facts is back in the peak"
    fi
    if [ "$warm" -gt 0 ] && [ "$blobMB" -gt 0 ] && [ -n "$floor" ] && [ $(( ( warm - floor ) * 100 )) -le $(( blobMB * kFactPct )) ]; then
        ok "F: warm peak $warm MB - floor $floor MB <= $kFactPct % of the $blobMB MB blob"
    else
        no "F: warm peak $warm MB - floor ${floor:-?} MB against the $blobMB MB blob (limit $kFactPct %): a second live set of fact arrays"
    fi
fi
[ "$fail" = 0 ] && { echo "PASS warmpeakcheck"; exit 0; }
echo "FAIL warmpeakcheck"; exit 1

#!/usr/bin/env bash
# warmcli.sh — the warm CLI per-call figure, reproducibly: what one `ripwire <root> <verb>` costs once the cache is warm.
#
#   bench/warmcli.sh [ROOT]                      # ROOT defaults to this repository's root
#   RIPWIRE_BIN=build_rel/ripwire RUNS=9 bench/warmcli.sh
#
# A FIXED argv list (below; never derived from the corpus, so two runs time the same calls), each run against a cache
# directory made fresh for this invocation (TMPDIR, so no earlier binary's blob is read), two untimed warm-up calls per
# argv, then RUNS timed calls (default 5). Prints the environment first — binary --version (its built_from= names the
# build), git --version, the root, its file count, the machine and its load — then one row per argv (median / min /
# max wall ms, exit code, stdout bytes) and the median of the per-argv medians. Wall time includes process start and
# every git child the call makes, which is what an agent calling the CLI pays. Builds nothing and writes nothing
# outside its temporary cache dir. A Release build is the flavour users run; a plain dev build is slower.
#
# Exit 0 = measured; 1 = a timed call failed (non-zero exit), so its time is not a figure; 2 = usage (no binary).
set -u
HERE="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$HERE/build/ripwire}"
ROOT_ARG="${1:-$HERE}"
RUNS="${RUNS:-5}"
[ -x "$BIN" ] || { echo "warmcli: no ripwire binary at $BIN (set RIPWIRE_BIN)" >&2; exit 2; }
case "$RUNS" in ''|*[!0-9]*|0) echo "warmcli: RUNS must be a positive integer" >&2; exit 2 ;; esac
command -v python3 >/dev/null 2>&1 || { echo "warmcli: python3 is needed for the timer" >&2; exit 2; }

CACHE="$( mktemp -d "${TMPDIR:-/tmp}/ripwire-warmcli.XXXXXX" )"; trap 'rm -rf "$CACHE"' EXIT
echo "# warmcli $( date -u +%Y-%m-%dT%H:%M:%SZ )"
echo "# bin: $BIN — $( "$BIN" --version 2>&1 | head -1 )"
echo "# git: $( git --version 2>/dev/null || echo absent )"
echo "# root: $ROOT_ARG ($( git -C "$ROOT_ARG" ls-files 2>/dev/null | wc -l | tr -d ' ' ) tracked files)"
echo "# machine: $( uname -sm ), $( sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null ) cores, load $( sysctl -n vm.loadavg 2>/dev/null || cut -d' ' -f1-3 /proc/loadavg 2>/dev/null )"
echo "# runs: $RUNS timed after 2 warm-up calls per argv; cache dir fresh for this invocation"

python3 -I - "$BIN" "$ROOT_ARG" "$CACHE" "$RUNS" <<'PY'
import os, statistics, subprocess, sys, time
bin_, root, cache, runs = sys.argv[ 1 ], sys.argv[ 2 ], sys.argv[ 3 ], int( sys.argv[ 4 ] )
ARGV = [ [ "--callers=rankGraphTeleport" ],
         [ "--callees=rankGraphTeleport" ],
         [ "--at=src/graph.h:100" ],
         [ "--impact=rankGraphTeleport" ],
         [ "--for=rankGraphTeleport" ] ]
env = dict( os.environ ); env[ "TMPDIR" ] = cache.rstrip( "/" ) + "/"
print( "argv\tmedian_ms\tmin_ms\tmax_ms\trc\tout_bytes" )
medians, failed = [], False
for argv in ARGV:
    cmd = [ bin_, root ] + argv
    for _ in range( 2 ):
        subprocess.run( cmd, stdout = subprocess.DEVNULL, stderr = subprocess.DEVNULL, env = env )
    ts, rc, nbytes = [], 0, 0
    for _ in range( runs ):
        t = time.perf_counter()
        p = subprocess.run( cmd, stdout = subprocess.PIPE, stderr = subprocess.DEVNULL, env = env )
        ts.append( ( time.perf_counter() - t ) * 1000.0 )
        rc, nbytes = p.returncode, len( p.stdout )
        failed = failed or p.returncode != 0
    medians.append( statistics.median( ts ) )
    print( f"{' '.join( argv )}\t{statistics.median( ts ):.0f}\t{min( ts ):.0f}\t{max( ts ):.0f}\t{rc}\t{nbytes}" )
print( f"# median of the per-argv medians: {statistics.median( medians ):.0f} ms" )
sys.exit( 1 if failed else 0 )
PY

#!/usr/bin/env bash
# padscalecheck.sh — the single-file ingest SCALING gate (comment-flood pathology).
#
#   test/padscalecheck.sh                       # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/padscalecheck.sh
#
# ts_node_child( n, i ) restarts tree-sitter's child iterator from the FIRST child on every call, so
# an indexed loop over a node's C children costs O(C^2). A file whose root holds tens of thousands of
# top-level nodes (14 000 line comments = ~1 MB) once turned a ~ms ingest into ~2 s of user CPU —
# quadratic in line count, measured 4x time per 2x lines. This gate generates that exact pathology at
# two sizes (7 000 and 28 000 comment lines + one small function) and asserts near-LINEAR scaling:
#
#   * short-circuit: if the 28 000-line ingest costs < 1.0 s of user CPU, scaling is moot — PASS.
#   * otherwise the 28000/7000 user-CPU ratio must stay < 8 (linear ~= 4, quadratic ~= 16; the
#     one-walker-regressed case measured ~15). User CPU, not wall time, so a loaded CI box can't flake it.
#
# Correctness on the padded file is asserted too (the one real symbol must still be found, twice,
# byte-identically) so a "fix" that skips comment-flooded files can never pass.
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

echo "padscalecheck: BIN=$BIN"

# ── fixture: NLINES identical line comments, then one small function ─────────────────────────────────
gen(){ # $1 = dir, $2 = line count
    mkdir -p "$1"
    python3 - "$1/big.cpp" "$2" <<'PY'
import sys
path, n = sys.argv[ 1 ], int( sys.argv[ 2 ] )
open( path, 'w' ).write( ( '// pad ' + 'x' * 60 + '\n' ) * n + 'int target() { return 424242; }\n' )
PY
}
gen "$TMP/small" 7000
gen "$TMP/big"   28000

# user-CPU seconds of one cold ingest of $1 (map to /dev/null; output correctness is checked separately)
usercpu(){ # $1 = corpus dir
    { /usr/bin/time -p "$BIN" "$1" --no-cache >/dev/null; } 2>"$TMP/t" || { echo FAIL; return; }
    awk '/^user/ { print $2 }' "$TMP/t"
}

# ── 1) correctness + determinism on the padded file — before any timing ──────────────────────────────
"$BIN" "$TMP/big" --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$TMP/big" --no-cache >"$TMP/b" 2>/dev/null
if [ ! -s "$TMP/a" ]; then
    no "padded-file ingest (empty output)"
elif ! grep -q 'target' "$TMP/a"; then
    no "padded-file ingest (the one real symbol 'target' is missing from the map)"
elif ! diff -q "$TMP/a" "$TMP/b" >/dev/null; then
    no "padded-file determinism (two cold runs differ)"
else
    ok "padded-file ingest (symbol found, deterministic, $( wc -c <"$TMP/a" | tr -d ' ' ) B)"
fi

# ── 2) scaling: 4x the comment lines must NOT cost ~16x the user CPU ─────────────────────────────────
u_small="$( usercpu "$TMP/small" )"
u_big="$(   usercpu "$TMP/big" )"
if [ "$u_small" = FAIL ] || [ "$u_big" = FAIL ] || [ -z "$u_small" ] || [ -z "$u_big" ]; then
    no "scaling (a timed ingest run failed outright)"
else
    verdict="$( awk -v s="$u_small" -v b="$u_big" 'BEGIN {
        if( b < 1.0 )        { print "fast";  exit }      # short-circuit: absolute cost is already fine
        if( s < 0.02 ) s = 0.02                           # floor the divisor so a ~0 small run cannot flake the ratio
        if( b / s < 8.0 )    { print "linear" } else { printf "quad %.1f", b / s }
    }' )"
    case "$verdict" in
        fast)   ok "scaling (28000-line ingest ${u_big}s user CPU < 1.0s — quadratic walk absent)";;
        linear) ok "scaling (ratio $( awk -v s="$u_small" -v b="$u_big" 'BEGIN{ if( s < 0.02 ) s = 0.02; printf "%.1f", b/s }' )x for 4x lines, ${u_big}s user CPU)";;
        *)      no "scaling (${verdict#quad }x user CPU for 4x lines — O(children^2) walk is back; small=${u_small}s big=${u_big}s)";;
    esac
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

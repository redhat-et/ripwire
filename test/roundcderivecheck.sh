#!/usr/bin/env bash
# roundcderivecheck.sh — bench/roundc-h2h/derive_questions.py picks six DISTINCT commits per shape, or refuses.
#
# WHY THIS GATE EXISTS (#492). Rule 4 of the registration picks indices 0, stride, …, 5*stride with
# stride = L // 6. Below L = 6 the stride is 0 and all six picks are elig[0]: one commit, one question, six
# rows, which gives that shape six times its weight in every score built on the bank. At L = 0 the pick is
# an IndexError. The harness must refuse such a bank, not write it.
#
# HOW. The harness only runs at its pinned RocksDB commit (`assert head == PIN`), so the gate puts a stub
# `git` on PATH that answers the three calls the harness makes (rev-parse, rev-list, log) from a synthetic
# 1200-commit history, and runs a COPY of the harness in a scratch directory: it writes questions.json next to
# itself, and the checkout must never be written. Each history fixes how many commits fit the first shape
# (S4, three or more source files) and gives every later shape plenty, so the S4 count is the one input that
# moves between arms.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
HARNESS="$ROOT/bench/roundc-h2h/derive_questions.py"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v python3 >/dev/null 2>&1 || { echo "roundcderivecheck: SKIP python3 not on PATH"; exit 0; }
[ -f "$HARNESS" ] || { echo "roundcderivecheck: no harness at $HARNESS"; exit 2; }
PIN="$( sed -n 's/^PIN = "\([0-9a-f]\{40\}\)"$/\1/p' "$HARNESS" )"
[ -n "$PIN" ] || { echo "roundcderivecheck: no 40-hex PIN = \"…\" line in $HARNESS"; exit 2; }

# ── the stub git: answers the harness's three calls from ROUNDC_S4 (commits with >= 3 source files) ──
mkdir -p "$TMP/bin" "$TMP/corpus"
cat >"$TMP/bin/fakegit.py" <<'PY'
import os, sys
# 1200 first-parent commits. The first ROUNDC_S4 carry three source files (S4); after them, 20 commits each
# of a source file plus its test (S3), two source files (S2) and one source file (S1, then S5); the rest
# touch no source file at all.
s4 = int( os.environ[ "ROUNDC_S4" ] )
kinds = [ "s4" ] * s4 + [ "s3" ] * 20 + [ "s2" ] * 20 + [ "s1" ] * 20
kinds += [ "none" ] * ( 1200 - len( kinds ) )
files = { "s4": [ "db/a.cc", "db/b.cc", "db/c.cc" ], "s3": [ "db/d.cc", "db/d_test.cc" ],
          "s2": [ "table/e.cc", "table/f.h" ], "s1": [ "util/g.cc" ], "none": [ "docs/README.md" ] }
shas = [ "%040x" % ( i + 1 ) for i in range( 1200 ) ]
args = sys.argv[ 1: ]
if args[ :1 ] == [ "-C" ]:
    args = args[ 2: ]
if args == [ "rev-parse", "HEAD" ]:
    print( os.environ[ "ROUNDC_PIN" ] )
elif args[ :1 ] == [ "rev-list" ]:
    print( "\n".join( shas ) )
elif args[ :1 ] == [ "log" ]:
    sys.stdout.write( "".join( "\0%s\x01commit %d\n%s\n" % ( sha, i, "\n".join( files[ k ] ) )
                               for i, ( sha, k ) in enumerate( zip( shas, kinds ) ) ) )
else:
    sys.exit( "fakegit: unexpected call %r" % ( sys.argv[ 1: ], ) )
PY
printf '#!/bin/sh\nexec python3 "%s" "$@"\n' "$TMP/bin/fakegit.py" >"$TMP/bin/git"
chmod +x "$TMP/bin/git"

# derive S4: run a fresh copy of the harness against a history with S4 such commits. Sets rc, out, json.
derive(){
    local d="$TMP/run$1"
    mkdir -p "$d"; cp "$HARNESS" "$d/derive_questions.py"
    ( cd "$d" && PATH="$TMP/bin:$PATH" ROUNDC_S4="$1" ROUNDC_PIN="$PIN" \
          python3 "$d/derive_questions.py" "$TMP/corpus" >"$d/out.txt" 2>&1 )
    rc=$?; out="$d/out.txt"; json="$d/questions.json"
}
# rows commits: "<rows> <distinct commits>" of a written questions.json
rows_commits(){ python3 -c 'import json, sys; r = json.load( open( sys.argv[ 1 ] ) ); print( len( r ), len( { x[ "commit" ] for x in r } ) )' "$1"; }

# ── 1. control: at L = 6 (the smallest legal list, stride 1) and above, 30 rows over 30 commits ─────
for n in 6 13; do
    derive "$n"
    if [ "$rc" = 0 ] && [ -f "$json" ] && grep -q "S4 L=$n stride=$(( n / 6 ))" "$out"; then
        got="$( rows_commits "$json" )"
        [ "$got" = "30 30" ] && ok "S4 L=$n: the bank is written with 30 rows over 30 distinct commits" \
                             || no "S4 L=$n: expected '30 30' rows/commits, got '$got'"
    else
        no "S4 L=$n: the control did not derive a bank (exit $rc):"; tail -5 "$out"
    fi
done

# ── 2. L < 6 refuses by name and writes nothing — never one commit six times, never an IndexError ──
for n in 5 3 1 0; do
    derive "$n"
    if [ "$rc" != 0 ] && [ ! -e "$json" ] && grep -q "^S4: $n eligible commits; rule 4" "$out" && ! grep -q Traceback "$out"; then
        ok "S4 L=$n: refused by name, no questions.json written"
    else
        got="$( [ -f "$json" ] && rows_commits "$json" || echo none )"
        no "S4 L=$n: expected a named refusal and no bank, got exit $rc and rows/commits '$got':"; tail -3 "$out"
    fi
done

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

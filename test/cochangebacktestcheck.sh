#!/usr/bin/env bash
# cochangebacktestcheck.sh — the co-change backtest harness (bench/cochange/backtest.py) scores Hit@k correctly
# and never reads history from after the commit it is predicting.
#
# WHY THIS GATE EXISTS. A backtest that reads future history reports a hit rate it could never have earned. The
# defect is quiet: the numbers look plausible, and higher. This gate builds a git fixture with a known answer.
#   H  (src/a.c + src/b.c): a and b co-changed 3 times before H, so the held-out half is predictable from the
#      past. Every history arm must rank it FIRST: Hit@1 = 1.
#   E  (src/a.c + lib/f.c): a and f never co-changed before E, and do 4 more times AFTER it. Read correctly,
#      no history arm can find the held-out half: Hit@10 = 0. Read with a leak, they all can.
# The leak arm (--leak-future reads history at the tip, the forbidden defect) must turn E into a hit. Without it,
# "E is a miss" would also pass on a harness that simply never finds anything.
#
# Usage: bash test/cochangebacktestcheck.sh   (RIPWIRE_BIN or build/ripwire)

set -u
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
SCRIPT="$ROOT/bench/cochange/backtest.py"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v python3 >/dev/null 2>&1 || { echo "cochangebacktestcheck: python3 required"; exit 2; }
[ -x "$BIN" ] || { echo "cochangebacktestcheck: no ripwire binary at $BIN — build first"; exit 2; }
if [ ! -f "$SCRIPT" ]; then
    no "(0) the harness exists at bench/cochange/backtest.py"
    exit 1
fi

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP"   # ripwire's per-root auto-cache lands here and dies with the fixture

# ── (1) the metric arithmetic, no git ───────────────────────────────────────────────────────────────────
selfOut="$( python3 "$SCRIPT" --self-test 2>&1 )"; selfRc=$?
if [ "$selfRc" = 0 ] && printf '%s' "$selfOut" | grep -q '^SELF-TEST PASS$'; then
    ok "(1) --self-test: Hit@1/5/10, Recall@10, tie order, both baselines, the window anchor, the [3] parser"
else
    no "(1) --self-test failed (rc=$selfRc)"; printf '%s\n' "$selfOut" | sed 's/^/        | /'
fi

# ── the fixture: one file per seed commit, then 3x a+b, H, E, then 4x a+f in E's future ───────────────────
REPO="$TMP/repo"; mkdir -p "$REPO/src" "$REPO/lib"
n=0
commit(){ n=$(( n + 1 )); d="$( printf '2026-01-10T%02d:00:00Z' "$n" )"
          git -C "$REPO" add -A && GIT_AUTHOR_DATE="$d" GIT_COMMITTER_DATE="$d" \
              git -C "$REPO" -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m "$1"; }
git -C "$REPO" init -q
for f in src/a src/b src/d lib/f lib/g; do
    printf 'int fn_%s( void ) { return 0; }\n' "${f#*/}" >"$REPO/$f.c"; commit "add $f"
done
for k in 1 2 3; do printf '// ab %s\n' "$k" >>"$REPO/src/a.c"; printf '// ab %s\n' "$k" >>"$REPO/src/b.c"; commit "ab $k"; done
printf '// H\n' >>"$REPO/src/a.c"; printf '// H\n' >>"$REPO/src/b.c"; commit "H"
printf '// E\n' >>"$REPO/src/a.c"; printf '// E\n' >>"$REPO/lib/f.c"; commit "E"
for k in 1 2 3 4; do printf '// af %s\n' "$k" >>"$REPO/src/a.c"; printf '// af %s\n' "$k" >>"$REPO/lib/f.c"; commit "af $k"; done
# U: an indexed file and one ripwire does not index (.hash). The probe must say which, from --situ's `unused:` block.
printf 'deadbeef\n' >"$REPO/src/data.hash"; commit "add hash"
printf '// U\n' >>"$REPO/src/a.c"; printf 'cafef00d\n' >>"$REPO/src/data.hash"; commit "U"
H="$( git -C "$REPO" log --format='%H %s' | awk '$2=="H"{print $1}' )"
E="$( git -C "$REPO" log --format='%H %s' | awk '$2=="E"{print $1}' )"
U="$( git -C "$REPO" log --format='%H %s' | awk '$2=="U"{print $1}' )"

python3 "$SCRIPT" --repo "$REPO" --since 2026-01-01 --n 100 --ripwire "$BIN" --work "$TMP/w" --out "$TMP/ok.jsonl" >"$TMP/ok.log" 2>&1
okRc=$?
python3 "$SCRIPT" --repo "$REPO" --since 2026-01-01 --n 100 --ripwire "$BIN" --work "$TMP/wl" --out "$TMP/leak.jsonl" --leak-future >"$TMP/leak.log" 2>&1
leakRc=$?
if [ "$okRc" != 0 ] || [ "$leakRc" != 0 ]; then
    no "(2) the harness ran on the fixture (rc=$okRc, leak rc=$leakRc)"; sed 's/^/        | /' "$TMP/ok.log" "$TMP/leak.log" | head -20
    exit 1
fi

# One python reader for every assertion; it prints "PASS <arm>" or "FAIL <arm>: why" lines.
python3 - "$TMP/ok.jsonl" "$TMP/leak.jsonl" "$H" "$E" "$U" >"$TMP/verdict" 2>&1 <<'PY'
import json, sys
okp, leakp, H, E, U = sys.argv[1:6]
def load( p ):
    recs = [ json.loads( l ) for l in open( p ) if l.strip() ]
    return recs[0][ "meta" ], [ r for r in recs if "protocol" in r ]
meta, rows = load( okp )
lmeta, lrows = load( leakp )
def row( rs, sha, proto ):
    m = [ r for r in rs if r[ "sha" ] == sha and r[ "protocol" ] == proto ]
    return m[0] if len( m ) == 1 else None
out = []
def arm( name, cond, why ):
    out.append( ( "PASS " if cond else "FAIL " ) + name + ( "" if cond else ": " + why ) )
# 10 eligible commits (3x ab, H, E, 4x af, U) — the 6 single-file add commits are not; 20 rows = 2 protocols each
arm( "(3) eligibility: 10 commits, 20 rows, the single-file adds excluded",
     meta[ "eligible" ] == 10 and len( rows ) == 20, "eligible=%s rows=%d" % ( meta[ "eligible" ], len( rows ) ) )
for proto in ( "L1O", "SEED1" ):
    h, e = row( rows, H, proto ), row( rows, E, proto )
    if not h or not e:
        arm( "(4) %s rows for H and E present" % proto, False, "missing" )
        continue
    other = [ f for f in ( "src/a.c", "src/b.c" ) if f not in h[ "seeds" ] ]
    for a in ( "ripwire", "cofreq", "cofreq3" ):
        arm( "(4) %s H %s: the past partner is ranked first (Hit@1=1)" % ( proto, a ),
             h[ "scores" ][ a ][ "hit@1" ] == 1 and h[ "ranked" ][ a ][:1] == other, "ranked=%r" % h[ "ranked" ][ a ] )
    arm( "(4) %s H samedir: same-directory src/ file found (Hit@5=1)" % proto, h[ "scores" ][ "samedir" ][ "hit@5" ] == 1,
         "ranked=%r" % h[ "ranked" ][ "samedir" ] )
    for a in ( "ripwire", "cofreq", "cofreq3" ):
        arm( "(5) %s E %s: a future-only coupling is NOT found (Hit@10=0)" % ( proto, a ),
             e[ "scores" ][ a ][ "hit@10" ] == 0, "ranked=%r" % e[ "ranked" ][ a ] )
    # the structural half of time order: E is read at its parent H, which reaches exactly 9 commits
    arm( "(6) %s E read at its parent with 9 commits of history" % proto,
         e[ "ref" ] == e[ "parent" ] == H and e[ "history_commits" ] == 9, "ref=%s history=%s" % ( e[ "ref" ][:9], e[ "history_commits" ] ) )
    le = row( lrows, E, proto )
    for a in ( "ripwire", "cofreq" ):
        arm( "(7) %s E %s under --leak-future: the same task becomes a hit (the fixture can see a leak)" % ( proto, a ),
             le is not None and le[ "scores" ][ a ][ "hit@10" ] == 1, "ranked=%r" % ( le and le[ "ranked" ][ a ] ) )
    arm( "(7) %s E under --leak-future reads 16 commits" % proto, le is not None and le[ "history_commits" ] == 16,
         "history=%s" % ( le and le[ "history_commits" ] ) )
for proto in ( "L1O", "SEED1" ):
    u = row( rows, U, proto )
    if not u:
        arm( "(10) %s U row present" % proto, False, "missing" )
        continue
    hs = "src/data.hash" in u[ "seeds" ]
    arm( "(10) %s U: the unindexed .hash file is %s" % ( proto, "dropped from ripwire's seeds" if hs else "kept out of the indexed population" ),
         ( u[ "seeds_dropped" ] == 1 and not u[ "indexed" ] ) if hs else ( u[ "seeds_dropped" ] == 0 and not u[ "indexed" ] ),
         "seeds=%r dropped=%s indexed=%s" % ( u[ "seeds" ], u[ "seeds_dropped" ], u[ "indexed" ] ) )
arm( "(8) no ripwire errors on the fixture", not any( r[ "error" ] for r in rows ), "%r" % [ r[ "error" ] for r in rows if r[ "error" ] ][:2] )
print( "\n".join( out ) )
PY
while IFS= read -r line; do
    case "$line" in
        PASS\ *) ok "${line#PASS }";;
        FAIL\ *) no "${line#FAIL }";;
        *)       no "verdict reader: $line";;
    esac
done <"$TMP/verdict"
grep -q '^PASS (7)' "$TMP/verdict" || no "(7) the leak arm never ran"

# (9) the summary renders every arm for both protocols
sumOut="$( python3 "$SCRIPT" --summarize "$TMP/ok.jsonl" 2>&1 )"
rowsN="$( printf '%s\n' "$sumOut" | grep -c '^| L1O \|^| SEED1 ' )"
if [ "$rowsN" = 16 ]; then ok "(9) --summarize: 2 protocols x 2 populations x 4 arms = 16 rows"; else no "(9) --summarize rows=$rowsN, want 16"; printf '%s\n' "$sumOut" | head -8 | sed 's/^/        | /'; fi

[ "$fail" = 0 ] && echo "cochangebacktestcheck: all arms passed" || echo "cochangebacktestcheck: FAILED"
exit "$fail"

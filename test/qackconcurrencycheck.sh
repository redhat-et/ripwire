#!/usr/bin/env bash
# qackconcurrencycheck.sh — round-4 finding F-04: `.ripwire_quality_acks` under CONCURRENT writers.
#
# WHAT BROKE. `--quality-ack` is a read-modify-write over the WHOLE ledger — read every existing row, heal
# the identities, fold in this run's accepted findings, rewrite the file from the in-memory map — and nothing
# serialized it. Three sessions acking DISJOINT rows in one shared checkout (different directory, different
# --scope, different --ack-only selector, so no legitimate conflict) is the exact scenario --scope exists for:
# "N agent sessions sharing one checkout". Measured before the fix on this fixture: 8 of 8 runs kept exactly
# ONE writer's acks and silently discarded the other two — not a partial merge, a full overwrite — and 1 of 8
# additionally left a torn line in the ledger, because the `ofstream(trunc)` rewrite was itself racing.
#
# WHAT THIS GATE ASSERTS:
#   (1) all THREE writers' acks survive every concurrent run, identified by the by=<scope> provenance stamp
#       each --scope run writes, and each writer's own selected row is present;
#   (2) the ledger PARSES after every run — every non-comment line matches the documented ack grammar, which
#       is what catches the torn-write half (a stray single-character line passes no grammar);
#   (3) no leftover tmp file from the atomic publish, and NO LOCK LITTER IN THE REPO: the lock lives in the
#       per-user cache dir, not as a `<ledger>.lock` sidecar next to a committed file (the A3-F8 rule the MCP
#       edit lock already learned — a sidecar lockfile is permanent git-status noise);
#   (4) the SINGLE-writer path is unchanged: two identical single-writer acks from the same start state
#       produce byte-identical ledgers, and the file the concurrent runs converge on is the same one three
#       sequential runs produce. The lock and the tmp+rename publish must not move a single byte of the
#       uncontended output — qackorigincheck/ackonlycheck pin the row CONTENT; this pins the bytes.
#
# Every arm was run RED against the pre-fix binary before the fix landed (arms 1 and 4's convergence arm).
#
# Own temp git repo, never the real one. Needs git + python3.
# Usage:  bash test/qackconcurrencycheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/qackconcurrencycheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "git required";     exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "qackconcurrencycheck: BIN=$BIN  (temp git repo)"

# ── the fixture: three DISJOINT directories, one regressing symbol each ──────────────────────────────────
# Committed small, then rewritten large in the working tree, so --quality-delta reports one preexisting-worse
# complexity/verbosity finding per directory and each --scope can select exactly its own.
mkdir -p "$WORK/alpha" "$WORK/beta" "$WORK/gamma"
python3 - "$WORK" <<'PY'
import sys, os
work = sys.argv[1]
for d in ( "alpha", "beta", "gamma" ):
    with open( os.path.join( work, d, d + ".py" ), "w" ) as f:
        f.write( "def %sComplex( a, b ):\n    if a > b:\n        return a\n    return b\n" % d )
PY
( cd "$WORK" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init >/dev/null 2>&1 )
# The three bodies must NOT be clones of each other: a shared duplication finding would be selected by all
# three --ack-only patterns at once (a clone row's identity names every member), and the by=/reason stamp on
# that one shared row is then legitimately last-writer-wins — which would make the convergence arm below
# order-dependent for a reason that is not a defect. Different branch counts and different operators per
# directory keep the three findings genuinely disjoint, which is what this gate is about.
python3 - "$WORK" <<'PY'
import sys, os
work = sys.argv[1]
shape = { "alpha": ( 24, "+", "-", "and", "or" ),
          "beta":  ( 19, "*", "+", "or",  "and" ),
          "gamma": ( 14, "-", "*", "and", "and" ) }
for d, ( n, op1, op2, j1, j2 ) in shape.items():
    lines = [ "def %sComplex( a, b ):" % d ]
    for i in range( n ):
        lines += [ "    if a > %d %s b < %d:" % ( i, j1, i + 1 ), "        a = a %s %d" % ( op1, i + 2 ),
                   "    elif a < %d %s b > %d:" % ( i + 3, j2, i ), "        b = b %s %d" % ( op2, i + 1 ) ]
    lines.append( "    return a %s b" % op1 )
    with open( os.path.join( work, d, d + ".py" ), "w" ) as f:
        f.write( "\n".join( lines ) + "\n" )
PY

LEDGER="$WORK/.ripwire_quality_acks"
ack_one(){ ( cd "$WORK" && "$BIN" . --quality-delta --scope="$1" --quality-ack="writer-$1" --ack-only="$1Complex" >/dev/null 2>&1 ); }

# every non-comment line must match the documented grammar:
#   ack <kind> <16 hex> <ackNow> [cid=<16 hex>] [by=<scope>] <reason to end of line>
cat > "$WORK/parse.py" <<'PY'
import re, sys
bad = []
rows = 0
pat = re.compile( r'^ack [A-Za-z0-9:_-]+ [0-9a-f]{16} \d+ (cid=[0-9a-f]{16} )?(by=\S+ )?\S.*$' )
for n, line in enumerate( open( sys.argv[1], encoding = "utf-8", errors = "replace" ), 1 ):
    line = line.rstrip( "\n" )
    if line.startswith( "#" ) or line == "":
        continue
    if pat.match( line ): rows += 1
    else: bad.append( "%d: %r" % ( n, line[ :80 ] ) )
print( rows )
for b in bad: print( "BAD " + b )
PY
parse_bad(){ python3 "$WORK/parse.py" "$LEDGER" | grep -c '^BAD '; }
# the by= stamp each --scope run writes, read off ACK LINES ONLY — the format comment line also contains the
# literal "by=<scope that acked it>" and a naive whole-file grep reports it as a fourth writer.
writers(){ grep '^ack ' "$LEDGER" 2>/dev/null | grep -oE ' by=[^ ]+ ' | tr -d ' ' | sort -u | tr '\n' ' '; }

# ── (1)+(2) three concurrent writers, four runs from a clean ledger ─────────────────────────────────────
RUNS=4
conc_lost=0; conc_bad=0; conc_missing=0
for run in $( seq 1 "$RUNS" ); do
    rm -f "$LEDGER"
    ack_one alpha & ack_one beta & ack_one gamma &
    wait
    if [ ! -s "$LEDGER" ]; then
        no "(1) run $run produced no ledger at all"
        conc_lost=$(( conc_lost + 1 )); continue
    fi
    seen="$( writers )"
    for w in alpha beta gamma; do
        case " $seen " in *" by=$w "*) ;; *) conc_lost=$(( conc_lost + 1 )) ;; esac
        grep -q "writer-$w" "$LEDGER" || conc_missing=$(( conc_missing + 1 ))
    done
    [ "$( parse_bad )" = 0 ] || conc_bad=$(( conc_bad + 1 ))
done
[ "$conc_lost" = 0 ] \
    && ok "(1) all three concurrent writers' acks survive, $RUNS/$RUNS runs (by=alpha/beta/gamma all present)" \
    || no "(1) $conc_lost writer-slot(s) lost across $RUNS concurrent runs — the ledger's read-modify-write is not serialized"
[ "$conc_missing" = 0 ] \
    && ok "(1) every writer's own reason string survives too (no last-writer-wins overwrite of the row set)" \
    || no "(1) $conc_missing writer reason(s) missing from the merged ledger"
[ "$conc_bad" = 0 ] \
    && ok "(2) the ledger parses after every concurrent run (no torn line)" \
    || no "(2) $conc_bad of $RUNS concurrent runs left a line that matches no ack grammar — a torn write"

# ── (3) no publish tmp left behind, and no lock litter anywhere in the repo tree ────────────────────────
LITTER="$( cd "$WORK" && find . -name '*.lock' -o -name '.ripwire_quality_acks.tmp*' | head -5 )"
[ -z "$LITTER" ] \
    && ok "(3) no lockfile or publish tmp left in the repo tree (the lock lives in the per-user cache dir)" \
    || { no "(3) litter left in the repo tree after acking"; printf '%s\n' "$LITTER"; }

# ── (4) the single-writer path is byte-for-byte what it always was ─────────────────────────────────────
rm -f "$LEDGER"; ack_one alpha; cp "$LEDGER" "$WORK/single1"
rm -f "$LEDGER"; ack_one alpha; cp "$LEDGER" "$WORK/single2"
cmp -s "$WORK/single1" "$WORK/single2" \
    && ok "(4) a single-writer ack is byte-identical across two runs from the same start state" \
    || no "(4) the single-writer ledger is not deterministic"
[ "$( python3 "$WORK/parse.py" "$WORK/single1" | head -1 )" -gt 0 ] \
    && ok "(4) the single-writer ledger carries at least one row that parses" \
    || no "(4) the single-writer ledger has no parsable ack row — every arm above measured nothing"

# the convergence arm: three SEQUENTIAL acks and three CONCURRENT ones must land the same ledger. This is
# what says the lock merges rather than merely survives — a serialization that dropped or reordered rows
# would still pass (1) and (2) but not this.
rm -f "$LEDGER"; ack_one alpha; ack_one beta; ack_one gamma; cp "$LEDGER" "$WORK/seq"
rm -f "$LEDGER"; ack_one alpha & ack_one beta & ack_one gamma & wait; cp "$LEDGER" "$WORK/conc"
cmp -s "$WORK/seq" "$WORK/conc" \
    && ok "(4) three concurrent acks converge on the SAME ledger three sequential acks produce (byte-identical)" \
    || { no "(4) concurrent and sequential acks disagree — the merge is not equivalent to serial execution"
         diff "$WORK/seq" "$WORK/conc" | head -8; }

# ── (5) H10 (capture-audit 2026-09-04): an ack of ZERO findings writes nothing ─────────────────────────
# Bare `--quality-ack` on a clean tree printed "acknowledged 0 finding(s)" and re-serialised the whole ledger
# anyway — the one modifier that WRITES when it has nothing to say, leaving a spurious diff in the caller's
# tree. A clean corpus (the small committed shapes, unchanged) has no finding to accept: the run must say so,
# create no ledger, and leave a pre-existing ledger byte-for-byte alone.
CLEAN="$WORK/clean"; mkdir -p "$CLEAN"
python3 - "$CLEAN" <<'PY'
import sys, os
d = sys.argv[1]
with open( os.path.join( d, "quiet.py" ), "w" ) as f:
    f.write( "def quietOne( a, b ):\n    if a > b:\n        return a\n    return b\n" )
PY
( cd "$CLEAN" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init >/dev/null 2>&1 )
( cd "$CLEAN" && "$BIN" . --quality-delta --quality-ack="nothing to accept" >/dev/null 2>"$WORK/zero.err" ); rcZ=$?
[ ! -e "$CLEAN/.ripwire_quality_acks" ] \
    && ok "(5) an ack of zero findings creates no ledger (exit $rcZ)" \
    || no "(5) an ack of zero findings CREATED $CLEAN/.ripwire_quality_acks ($( wc -c <"$CLEAN/.ripwire_quality_acks" | tr -d ' ' ) B) — a write with nothing to say"
grep -q 'nothing to acknowledge' "$WORK/zero.err" \
    && ok "(5) the zero-findings ack says so on stderr" \
    || no "(5) the zero-findings ack is not disclosed: [$( head -c 160 "$WORK/zero.err" | tr '\n' ' ' )]"
cp "$WORK/seq" "$CLEAN/.ripwire_quality_acks"
( cd "$CLEAN" && "$BIN" . --quality-delta --quality-ack="still nothing" >/dev/null 2>&1 )
cmp -s "$WORK/seq" "$CLEAN/.ripwire_quality_acks" \
    && ok "(5) with a pre-existing ledger, a zero-findings ack leaves it byte-identical" \
    || { no "(5) a zero-findings ack REWROTE a pre-existing ledger"; diff "$WORK/seq" "$CLEAN/.ripwire_quality_acks" | head -4; }

# ── (6) H10: the COMMITTED ledger is in the tool's own order, so a rewrite is byte-identical ─────────────
# writeAckRecords emits btree order — (kind, 16-hex key) as one string, bytewise — under the two header lines
# it always writes; arm (4) proves that writer deterministic. A committed ledger that is NOT in that order
# (a hand merge that kept both sides' placement) therefore reorders on the FIRST ack anyone runs, which is
# how one row moved under a bare --quality-ack that acked nothing. This arm reads the repo's own ledger and
# asserts the invariant a byte-identical rewrite needs: C-sorted keys, no duplicate (kind,key) — the reader
# merges those — and the header the tool writes.
COMMITTED="$ROOT/.ripwire_quality_acks"
if [ -f "$COMMITTED" ]; then
    python3 - "$COMMITTED" "$WORK/seq" <<'PY' > "$WORK/order.txt"
import sys
rows = [ l.rstrip( "\n" ) for l in open( sys.argv[ 1 ], encoding = "utf-8" ) ]
tool = [ l.rstrip( "\n" ) for l in open( sys.argv[ 2 ], encoding = "utf-8" ) ]
hdr  = [ l for l in rows if l.startswith( "#" ) ]
acks = [ l for l in rows if l.startswith( "ack " ) ]
keys = [ " ".join( l.split( " ", 3 )[ 1:3 ] ) for l in acks ]
moved = [ keys[ i ] for i, j in enumerate( sorted( range( len( keys ) ), key = lambda k: keys[ k ] ) ) if i != j ]
print( "rows=%d dups=%d misfiled=%d header_ok=%d" % ( len( acks ), len( keys ) - len( set( keys ) ), len( moved ),
       int( hdr == [ l for l in tool if l.startswith( "#" ) ] ) ) )
for k in moved[ :4 ]:
    print( "misfiled " + k )
PY
    ORD="$( head -1 "$WORK/order.txt" )"
    case "$ORD" in
        *" dups=0 misfiled=0 header_ok=1") ok "(6) the committed ledger is in the tool's order ($ORD) — a read+rewrite is byte-identical" ;;
        *) no "(6) the committed ledger is NOT in the tool's order ($ORD): the first ack anyone runs will reorder it"; grep '^misfiled' "$WORK/order.txt" | sed 's/^/        /' ;;
    esac
else
    ok "(6) no committed ledger in this tree — nothing to keep in order"
fi

# ── (7) H10, END TO END: the BINARY's own read+rewrite of the COMMITTED ledger is byte-identical ─────────
# Arm (6) asserts the INVARIANT a byte-identical rewrite needs (sorted keys, no duplicates, the tool's
# header) — in python, i.e. a PROXY for the property, re-derived from a reading of writeAckRecords. This arm
# is the property itself: the shipping binary reads the repo's real ledger, renders it, and either leaves the
# file alone or heals it, and the file is compared byte-for-byte afterwards. A drift between the python model
# and the C++ writer would pass (6) and fail here, which is the whole reason it exists.
#
# It runs against the CLEAN fixture rather than a clone of this repo on purpose: ackNothingToAccept's decision
# reads the ledger bytes and nothing else about the tree, so the fixture exercises the identical path in a
# fraction of the time — and its own git HEAD guarantees the "0 findings" precondition the path needs.
if [ -f "$COMMITTED" ]; then
    rm -f "$CLEAN/.ripwire_quality_acks"
    cp "$COMMITTED" "$CLEAN/.ripwire_quality_acks"
    ( cd "$CLEAN" && "$BIN" . --quality-delta --quality-ack="H10 round-trip probe" >/dev/null 2>"$WORK/rt.err" ); rcRT=$?
    if cmp -s "$COMMITTED" "$CLEAN/.ripwire_quality_acks"; then
        ok "(7) the binary's read+rewrite of the committed ledger is byte-identical (exit $rcRT)"
    else
        no "(7) the binary REWROTE the committed ledger on a run that accepted nothing (exit $rcRT)"
        diff "$COMMITTED" "$CLEAN/.ripwire_quality_acks" | head -6 | sed 's/^/        /'
    fi
    grep -q 'left untouched' "$WORK/rt.err" \
        && ok "(7) and it SAYS the ledger was left untouched" \
        || no "(7) the run did not disclose what it did to the ledger: [$( head -c 200 "$WORK/rt.err" | tr '\n' ' ' )]"
    rm -f "$CLEAN/.ripwire_quality_acks"
else
    ok "(7) no committed ledger in this tree — nothing to round-trip"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"

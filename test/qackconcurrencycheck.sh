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
#   (8) RE-SCORE PROVENANCE (round 2026-09-22): a magnitude-bearing ack row carries `now=`/`was=` — the exact
#       (was,now) pair that decided its severity — and a facet-driven kind (duplication /
#       new-clone-of-reused-helper) additionally carries `facet=`. RED on the pre-provenance binary: neither
#       token existed, so this arm fails there by construction. The "table-driven re-score formula agrees with
#       the live one" half of the contract is proven a different way — not by this shell script re-deriving the
#       materiality formula, but by an ENSURES self-check wired into the write path itself (verbs_quality.h,
#       right after `rec` is built): every `--quality-ack` on a magnitude-bearing finding calls rescoreAckRecord
#       on the row it just wrote (in memory — NOT through renderAckRecords/readAckRecords, so it does not prove
#       the ledger's text grammar round-trips; that half is this arm's own grep checks below plus arms (2)/(7))
#       and ENSURES the verdict matches the one the live report just computed. That check runs on every ack this
#       gate's own fixtures take (arms 1-7 above, and 8 below) in the plain (non-NDEBUG) build — a divergence
#       would abort the process, which this arm's plain 0-exit check therefore also covers.
#
#   (9) THE LEGACY-ACK BACKFILL (round 2026-09-22): a row written before provenance existed carries none, and
#       for the two CLONE kinds it does not have to stay that way — their ack identity is the member-set hash,
#       so the idiom verdict is recomputable from the CURRENT tree. A stripped-back (legacy) clone row must
#       come back carrying `prov=recon` and its idiom; the pass must be idempotent; a LIVE ack of the same
#       finding must outrank the reconstruction and clear `prov=`; and a legacy NUMERIC row must be left alone,
#       because nothing in this tree can supply its `was=` and half a triple is worse than none. RED on the
#       pre-backfill binary, which leaves every stripped row legacy.
#
#   (10) LEDGER TOKENS ARE EXTERNAL INPUT (train 17 fix round): the ledger is committed and hand-edited, so a
#       now=/was= or p= line number a binary could not have written — negative, or past 32 bits — must stay
#       visible text, never be narrowed into a fabricated value (now=-1 read back as 4294967295, now=4294967296
#       as 0). And a finding whose path contains a SPACE must not have its locator written as a token it cannot
#       be read back as: `p=my dir/a b.py:1` read back as path `my`, the rest pushed into the reason, and the
#       next ack committed the damage. RED on the 0d6f0490 binary on both halves.
#
# Every arm was run RED against the pre-fix binary before the fix landed (arms 1 and 4's convergence arm; 8
# against the pre-provenance binary, which writes no now=/was=/facet= token at all; 9 against the
# pre-backfill binary, which heals no legacy row).
#
# Own temp git repo, never the real one. Needs git + python3.
# Usage:  bash test/qackconcurrencycheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/qackconcurrencycheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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
#   ack <kind> <16 hex> <ackNow> [cid=<16 hex>] [by=<scope>] [now=<uint> was=<uint>] [facet=<token>] [p=<path>:<line>] <reason to end of line>
cat > "$WORK/parse.py" <<'PY'
import re, sys
bad = []
rows = 0
pat = re.compile( r'^ack [A-Za-z0-9:_-]+ [0-9a-f]{16} \d+ (cid=[0-9a-f]{16} )?(by=\S+ )?(now=\d+ was=\d+ )?(facet=\S+ )?(p=\S+ )?\S.*$' )
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
[ "$rcZ" = 0 ] && [ ! -e "$CLEAN/.ripwire_quality_acks" ] \
    && ok "(5) an ack of zero findings creates no ledger (exit $rcZ)" \
    || no "(5) exit $rcZ (want 0), or an ack of zero findings CREATED $CLEAN/.ripwire_quality_acks ($( wc -c <"$CLEAN/.ripwire_quality_acks" | tr -d ' ' ) B) — a write with nothing to say"
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
    if [ "$rcRT" = 0 ] && cmp -s "$COMMITTED" "$CLEAN/.ripwire_quality_acks"; then
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

# ── (8) RE-SCORE PROVENANCE: a magnitude-bearing ack row carries now=/was= (+facet= for clone kinds) ──────
# RED on the pre-provenance binary: it never wrote any of these three tokens, so both case arms below fail
# there (no now=/was=/facet= to match) and rcProv's check is vacuously true there too (nothing to abort on).
PROV="$WORK/prov"; mkdir -p "$PROV/a" "$PROV/b"
cat > "$PROV/a/pick.cpp" <<'EOF'
int pickA( int x )
{
    if( x < 1 )
    {
        return 100;
    }
    if( x < 2 )
    {
        return 200;
    }
    return 300;
}
EOF
( cd "$PROV" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init >/dev/null 2>&1 )
cat > "$PROV/b/pick.cpp" <<'EOF'
int pickB( int y )
{
    if( y < 1 )
    {
        return 100;
    }
    if( y < 2 )
    {
        return 200;
    }
    return 300;
}
EOF
( cd "$PROV" && "$BIN" . --quality-delta --quality-ack="provenance fixture" >"$WORK/prov.out" 2>"$WORK/prov.err" ); rcProv=$?
DUPROW="$( grep '^ack duplication ' "$PROV/.ripwire_quality_acks" 2>/dev/null )"
case "$DUPROW" in
    *" now="*" was="*" facet=threshold-ladder "*) ok "(8) a facet-driven ack row (duplication, recognized idiom) carries now=/was=/facet=" ;;
    *) no "(8) the duplication ack row is missing now=/was=/facet= provenance"; printf '%s\n' "$DUPROW" ;;
esac
[ "$rcProv" -eq 0 ] \
    && ok "(8) the write-path self-check did not abort — rescoreAckRecord on the row it just wrote reproduced the just-computed severity (ENSURES in verbs_quality.h)" \
    || no "(8) --quality-ack on the provenance fixture exited $rcProv — a crash here is the in-memory re-score self-check (ENSURES) firing"

# a plain numeric (non-facet) bar kind: complexity — same growth shape as qackorigincheck's (f) arm
NUM="$WORK/numprov"; mkdir -p "$NUM"
cat > "$NUM/c.py" <<'EOF'
def simple(a, b):
    if a > b:
        return a
    return b
EOF
( cd "$NUM" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init >/dev/null 2>&1 )
cat > "$NUM/c.py" <<'EOF'
def simple(a, b, c, d, e, f, g, h):
    if a > 0 and b > 0:
        if c > 0 and d > 0:
            if e > 0 and f > 0:
                if g > 0 and h > 0:
                    return a
                else:
                    return b
            else:
                return c
        else:
            return d
    elif a < 0 or b < 0:
        return e
    else:
        return f
EOF
( cd "$NUM" && "$BIN" . --quality-delta --quality-ack="numeric provenance fixture" >/dev/null 2>&1 )
CCXROW="$( grep '^ack complexity ' "$NUM/.ripwire_quality_acks" 2>/dev/null )"
case "$CCXROW" in
    *" now="*" was="*) ok "(8) a numeric bar-kind ack row (complexity) carries now=/was=" ;;
    *) no "(8) the complexity ack row is missing now=/was= provenance"; printf '%s\n' "$CCXROW" ;;
esac
case "$CCXROW" in
    *" facet="*) no "(8) the complexity row carries a facet= token — this kind never sets one" ;;
    *) ok "(8) …and correctly omits facet= (complexity has no facet — an honest omission, not a guess)" ;;
esac
# grammar arm (2) above already re-parses the WHOLE ledger with the updated pattern — a token this arm wrote
# in a shape that pattern does not accept would already have failed there for every run after this one.

# ── (9) THE LEGACY-ACK BACKFILL ───────────────────────────────────────────────────────────────────────
# A row written before provenance existed carries no now=/was=/facet=, so the knob sweep cannot re-score it.
# For the two CLONE kinds it does not have to stay that way: their ack identity IS the member-set hash, so a
# later run can recompute the idiom verdict from the CURRENT tree and heal the row — marked prov=recon,
# because "what the idiom is now" is a weaker claim than "what was measured when it was accepted".
#
# The only way to MAKE a legacy row here is to strip the tokens back off, because every binary under test
# writes them. That is a hand-edit of a FIXTURE ledger in a throwaway temp repo, never of the committed one
# (which is a build product and is only ever healed through the binary — quality.h's backfill note).
#
# Four things are asserted, and the last two are the honesty half rather than the feature half:
#   a) a stripped clone row comes BACK with prov=recon and its idiom — RED on the pre-backfill binary, which
#      leaves it legacy;
#   b) the pass is IDEMPOTENT — a second --quality-ack over the healed ledger moves zero bytes;
#   c) MEASURED BEATS RECONSTRUCTED — when the finding actually re-fires (its ratchet floor is dropped so it
#      is no longer suppressed) the live fold overwrites the reconstruction and prov= goes away. The backfill
#      runs BEFORE the fold, so ordering is what guarantees this rather than a check inside the backfill;
#   d) a stripped NUMERIC row is never given a reconstructed was= — nothing in this tree can supply one, and
#      inventing it is exactly the guess the honesty contract forbids. This is why the clone kinds are
#      healable and the numeric kinds are not, asserted rather than asserted-in-a-comment;
#   f) THE LEDGER-TEXT ROUND TRIP, which the write-path ENSURES does NOT cover: that promise re-scores an
#      in-memory AckRecord and never touches renderAckRecords/readAckRecords, so a serialisation or parsing
#      bug is invisible to it — and prov=, the tri-state and the omitted-when-Measured rule are all exactly
#      that class. A hand-written fixture ledger carries the shapes the binary never emits (permuted token
#      order, an unknown prov= value, a half pair, a ':' inside p=), the shipping binary reads and rewrites
#      it, and the result is checked from the bytes — including that no row ever carries both a measurement
#      and a reconstruction, which the fold ordering is supposed to make unreachable;
#   e) a reconstruction whose group is NO LONGER FOUND is left intact and reported unverified, never deleted.
#      prov=recon is a cache — re-derived on every ack that can check it — but "not found" is a floor, not a
#      verdict: a scoped scan, a capped file, or a ledger read beside a different tree all produce it, and
#      arm 7's transplant probe is one of them. Deleting derived data on a floor is irreversible.
#
# `strip_prov` is a FUNCTION, not three copies of the same regex: the two fixtures below strip the same way,
# and a lookahead (never consuming the separating space) is what makes back-to-back `now=N was=N` tokens both
# match — a naive ' now=\d+ ' eats the space its neighbour needs and silently leaves half a triple behind.
strip_prov(){
    python3 - "$1" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r' (?:now|was)=\d+(?=[ \n])', '', s)
s = re.sub(r' (?:prov|facet|p)=[^ \n]+(?=[ \n])', '', s)
open(p, 'w').write(s)
PYEOF
}

BF="$WORK/backfill"; cp -R "$PROV" "$BF" 2>/dev/null
if [ -f "$BF/.ripwire_quality_acks" ]; then
    strip_prov "$BF/.ripwire_quality_acks"
    STRIPPED="$( grep '^ack ' "$BF/.ripwire_quality_acks" 2>/dev/null | grep -c ' now=\| was=\| prov=\| facet=' || true )"
    [ "${STRIPPED:-0}" = 0 ] \
        && ok "(9) fixture precondition: every row is legacy again (no now=/was=/prov=/facet= anywhere)" \
        || no "(9) the strip left ${STRIPPED} row(s) still carrying provenance — the fixture is not legacy"

    ( cd "$BF" && "$BIN" . --quality-delta --quality-ack="backfill fixture" >/dev/null 2>"$WORK/bf1.err" )
    BFROW="$( grep '^ack duplication ' "$BF/.ripwire_quality_acks" 2>/dev/null )"
    case "$BFROW" in
        *" prov=recon facet=threshold-ladder "*) ok "(9) a stripped legacy clone row was reconstructed from the current tree — prov=recon plus the recomputed idiom" ;;
        *" prov=recon "*)                        no "(9) the reconstruction lost the idiom arm 8 measured on this same tree (expected facet=threshold-ladder)"; printf '%s\n' "$BFROW" ;;
        *) no "(9) the legacy duplication row was NOT backfilled — no prov=recon on it"; printf '%s\n' "$BFROW" ;;
    esac
    grep -q 'ack provenance backfill' "$WORK/bf1.err" \
        && ok "(9) …and the run DISCLOSED the backfill on stderr (reconstructed / left-legacy / ineligible counts)" \
        || no "(9) the backfill healed rows without disclosing it — a weaker claim must never land silently"

    cp "$BF/.ripwire_quality_acks" "$WORK/bf.once"
    ( cd "$BF" && "$BIN" . --quality-delta --quality-ack="backfill fixture" >/dev/null 2>&1 )
    if cmp -s "$WORK/bf.once" "$BF/.ripwire_quality_acks"; then
        ok "(9) the backfill is IDEMPOTENT — a second pass over the healed ledger produced a byte-identical file"
    else
        no "(9) a second backfill pass changed the ledger — the pass is not idempotent"
        diff "$WORK/bf.once" "$BF/.ripwire_quality_acks" | head -4
    fi

    # (c) drop the row's ratchet floor to 1 so the SAME finding is no longer suppressed and re-fires; the fold
    # then measures it, and the reconstruction it was carrying must not survive that.
    python3 - "$BF/.ripwire_quality_acks" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r'^(ack duplication [0-9a-f]{16}) \d+ ', r'\1 1 ', s, flags=re.M)
open(p, 'w').write(s)
PYEOF
    ( cd "$BF" && "$BIN" . --quality-delta --quality-ack="live re-ack over a reconstructed row" >/dev/null 2>&1 )
    LIVEROW="$( grep '^ack duplication ' "$BF/.ripwire_quality_acks" 2>/dev/null )"
    case "$LIVEROW" in
        *" prov=recon "*) no "(9) a live re-ack left prov=recon on the row — a measurement must outrank a reconstruction"; printf '%s\n' "$LIVEROW" ;;
        *" now="*" was="*) ok "(9) a live re-ack UPGRADED the row to measured — prov= is gone, now=/was= remain" ;;
        *) no "(9) the live re-ack left the row without provenance at all"; printf '%s\n' "$LIVEROW" ;;
    esac
    # (e) ABSENCE IS A FLOOR. When the clone group is no longer found, the reconstruction must be left ALONE
    # and reported as unverified — not deleted. A run can fail to find a group because the scan was scoped or
    # capped, or because the ledger is sitting next to a different tree (arm 7's transplant probe is exactly
    # that, and it is what caught an earlier draft that withdrew the row instead). Deleting derived data on
    # the strength of a floor is irreversible and is the guess the honesty contract forbids.
    # Re-stripped first so the row is reconstructed (not measured) going in.
    strip_prov "$BF/.ripwire_quality_acks"
    ( cd "$BF" && "$BIN" . --quality-delta --quality-ack="re-reconstruct before withdrawal" >/dev/null 2>&1 )
    case "$( grep '^ack duplication ' "$BF/.ripwire_quality_acks" 2>/dev/null )" in
        *" prov=recon "*) : ;;
        *) no "(9) withdrawal precondition: the row is not reconstructed going in" ;;
    esac
    rm -f "$BF/b/pick.cpp"
    ( cd "$BF" && "$BIN" . --quality-delta --quality-ack="withdrawal probe" >/dev/null 2>"$WORK/bf2.err" )
    GONEROW="$( grep '^ack duplication ' "$BF/.ripwire_quality_acks" 2>/dev/null )"
    case "$GONEROW" in
        *" prov=recon "*) ok "(9) a reconstruction whose group was not found is LEFT INTACT — absence is a floor, and derived data is never deleted on one" ;;
        "")               no "(9) the clone ack row was DELETED when its group stopped being found — absence is a floor, not a verdict" ;;
        *)                no "(9) a reconstruction was stripped when its group was not found — it must be left alone and reported unverified"; printf '%s\n' "$GONEROW" ;;
    esac
    grep -q 'UNVERIFIED' "$WORK/bf2.err" \
        && ok "(9) …and the run SAID so — the unverified count is what makes leaving the value honest" \
        || no "(9) the run left an unverifiable reconstruction in place without disclosing it"
else
    no "(9) no fixture ledger to strip — arm 8's --quality-ack produced none"
fi

# ── (9h) HEAL SURVIVES A REFUSED --ack-only (M1 follow-up, rv-ack-provenance-backfill.md) ────────────────
# backfillCloneAckProvenance runs BEFORE --ack-only's selection and BEFORE the "matched none" refusal — so a
# refusal used to discard the healing this run already computed in memory along with the (correctly) refused
# acceptance. `--ack-only=zzz-no-such-finding` matches nothing in this fixture on purpose: the run must still
# exit 1 (nothing was ACCEPTED — the refusal itself is unchanged) but the ledger must come out healed anyway,
# the same canonical-bytes heal H10's ackNothingToAccept already performs when there is nothing to accept at
# all. RED on the pre-fix binary: it returns 1 before ever calling writeAckRecords, so the stripped-legacy
# fixture ledger is byte-IDENTICAL to what strip_prov produced — no prov=recon anywhere.
BFH="$WORK/backfillheal"; cp -R "$PROV" "$BFH" 2>/dev/null
if [ -f "$BFH/.ripwire_quality_acks" ]; then
    strip_prov "$BFH/.ripwire_quality_acks"
    ( cd "$BFH" && "$BIN" . --quality-delta --ack-only=zzz-no-such-finding --quality-ack="heal-only probe" >/dev/null 2>"$WORK/bfh.err" )
    BFH_RC=$?
    if [ "$BFH_RC" != 1 ]; then
        no "(9h) --ack-only=zzz-no-such-finding did not refuse (exit $BFH_RC) — the refusal itself must be unchanged"
    else
        ok "(9h) a refused --ack-only still exits 1 — nothing was ACCEPTED"
    fi
    case "$( grep '^ack duplication ' "$BFH/.ripwire_quality_acks" 2>/dev/null )" in
        *" prov=recon "*) ok "(9h) …but the ledger was healed anyway — the backfill this run computed survives a refused --ack-only" ;;
        *)                no "(9h) the refusal discarded the in-memory backfill — the ledger is still legacy after a matched-none --ack-only"; printf '%s\n' "$( grep '^ack duplication ' "$BFH/.ripwire_quality_acks" 2>/dev/null )" ;;
    esac
    grep -q 'matched none' "$WORK/bfh.err" \
        && ok "(9h) …and the refusal still says so on stderr" \
        || no "(9h) the refusal stopped naming --ack-only's own reason"
else
    no "(9h) no fixture ledger to strip — the shared PROV fixture produced none"
fi

# ── (9f) THE LEDGER-TEXT ROUND TRIP ───────────────────────────────────────────────────────────────────
# The write-path ENSURES re-scores the in-memory AckRecord right after it is built; it never goes through
# renderAckRecords/readAckRecords, so it cannot catch a SERIALISATION or PARSING bug — see the corrected
# wording in verbs_quality.h. Every new thing the provenance axis adds (the prov= token, the tri-state, the
# omitted-when-Measured rule) is squarely in that uncovered class, so it is covered here instead, through
# the real file: hand-write a ledger, let the shipping binary read and rewrite it, and read the result back.
#
# Hand-writing a FIXTURE ledger is the only way to produce shapes the binary never emits — a permuted token
# order from a 3-way merge, a prov= value from some later binary, a row hand-truncated to half a pair. The
# committed ledger is a build product and is still only ever healed through the binary.
RT="$WORK/roundtrip"; mkdir -p "$RT"
cat > "$RT/x.py" <<'EOF'
def solo(a):
    return a
EOF
( cd "$RT" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init >/dev/null 2>&1 )
# key 1: canonical order. key 2: PERMUTED (facet before now/was, prov last) — a 3-way merge can produce it.
# key 3: prov= with a value no binary here writes. key 4: now= with NO was= — half a pair, never provenance.
# key 5: a p= path containing a ':' — split on the LAST colon, so the path must survive intact.
cat > "$RT/.ripwire_quality_acks" <<'EOF'
# ripwire quality acks v1 — hand-written fixture
ack duplication 1111111111111111 7 now=7 was=0 prov=recon facet=threshold-ladder canonical order
ack duplication 2222222222222222 7 facet=switch-name-table was=0 now=7 prov=recon permuted order
ack duplication 3333333333333333 7 now=7 was=0 prov=from-the-future facet=builder-chain unknown prov value, clone kind, group not in this tree
ack complexity  4444444444444444 9 now=9 half a pair: the second token is absent
ack complexity  5555555555555555 9 now=9 was=2 p=src/a:b/c.py:41 colon inside the path
ack complexity  6666666666666666 9 now=9 was=2 prov=weird unknown prov value, numeric kind — never eligible for the backfill
EOF
( cd "$RT" && "$BIN" . --quality-delta --quality-ack="round-trip probe" >/dev/null 2>&1 )
rt_row(){ grep "^ack [a-z-]* $1 " "$RT/.ripwire_quality_acks" 2>/dev/null; }

# NON-DISCRIMINATING ON ITS OWN, said out loud rather than left for a reviewer to notice: a reader that does
# not know prov= leaves the token sitting in the reason text, so the string still appears and this arm passes
# on the pre-backfill binary too. It is kept because it documents the canonical spelling — but the
# discrimination in this sub-arm lives in its two neighbours, the PERMUTED-order and unknown-prov= cases,
# which the old reader fails. An unlabelled assertion that proves nothing is how a gate becomes decorative.
case "$( rt_row 1111111111111111 )" in
    *" now=7 was=0 prov=recon facet=threshold-ladder "*) ok "(9f) a canonical prov=recon row round-trips through the ledger text unchanged (documents the spelling; see the note — its neighbours carry the discrimination)" ;;
    *) no "(9f) the canonical prov=recon row did not survive a read+rewrite"; printf '%s\n' "$( rt_row 1111111111111111 )" ;;
esac
case "$( rt_row 2222222222222222 )" in
    *" now=7 was=0 prov=recon facet=switch-name-table "*) ok "(9f) a PERMUTED token order is read and re-emitted in canonical order, losing no field" ;;
    *) no "(9f) a permuted token order lost or reordered a field on rewrite"; printf '%s\n' "$( rt_row 2222222222222222 )" ;;
esac
# An unknown prov= must never be promoted into either real claim. Reading it as Measured would silently
# promote a spelling this binary does not understand into the audited-as-measured population; reading it as
# Reconstructed (rewriting it to prov=recon, the pre-fix bug — review finding L3) FALSELY claims
# backfillCloneAckProvenance verified this row from the current tree, which it did not: this key's member set
# is not in the fixture tree at all (RED on the pre-fix binary, which reads any unrecognized value as
# Reconstructed and then leaves it exactly that way when the group is not found — see the "unverified" arm
# above for the same not-found path on a value it DID recognize). GREEN: the exact bytes round-trip.
case "$( rt_row 3333333333333333 )" in
    *" prov=from-the-future "*) ok "(9f) an unrecognized prov= value on a clone-kind row round-trips verbatim when its group is not found here — never promoted to measured, never rewritten to recon" ;;
    *" prov=recon "*)           no "(9f) an unrecognized prov= value was rewritten to prov=recon — a false claim of a reconstruction this run never performed (L3)"; printf '%s\n' "$( rt_row 3333333333333333 )" ;;
    *" now="*)                  no "(9f) an unrecognized prov= was read as MEASURED — an unknown confidence must never become the strongest one"; printf '%s\n' "$( rt_row 3333333333333333 )" ;;
    *)                          no "(9f) the unknown-prov row lost its provenance entirely"; printf '%s\n' "$( rt_row 3333333333333333 )" ;;
esac
# THE L3 REPRO, verbatim: an unrecognized prov= on a NUMERIC row (never eligible for the clone backfill at
# all — base != duplication/new-clone-of-reused-helper short-circuits to `ineligible` before the clone lookup
# even runs) must round-trip exactly as written. RED on the pre-fix binary: ackProvenanceFor mapped ANY
# unrecognized token to Reconstructed unconditionally, and ineligible rows are left untouched by the backfill
# loop, so the row kept that (wrong) Reconstructed state and renderAckRecords serialized it as the canonical
# `prov=recon` — a numeric row silently gained a claim the code comment two lines above it says only the two
# clone kinds can ever earn.
case "$( rt_row 6666666666666666 )" in
    *" prov=weird "*) ok "(9f) an unrecognized prov= value on a NUMERIC row round-trips verbatim (L3: never rewritten to recon on an ineligible kind)" ;;
    *" prov=recon "*) no "(9f) L3 REGRESSION: a numeric row's unrecognized prov= was rewritten to prov=recon — the ledger now falsely claims a clone-idiom reconstruction on a kind the backfill never touches"; printf '%s\n' "$( rt_row 6666666666666666 )" ;;
    *" now="*)        no "(9f) an unrecognized prov= on a numeric row was read as MEASURED — an unknown confidence must never become the strongest one"; printf '%s\n' "$( rt_row 6666666666666666 )" ;;
    *)                no "(9f) the numeric unknown-prov row lost its provenance entirely"; printf '%s\n' "$( rt_row 6666666666666666 )" ;;
esac
# now= without was= is half the pair rescoreAckRecord needs; it must read as NO provenance rather than as a
# half-answer, so the rewrite carries neither token and the stray text stays in the reason.
# Pinned to the TOKEN RUN the writer emits (`now=<n> was=<n>`, adjacent and right after the magnitude and
# any cid=/by=), not to a bare substring: `was=` can legitimately appear later inside a reason, and a gate
# that cannot tell a token from prose fails on correct behaviour — which is what it did before this line.
# The row must EXIST before its absence of provenance means anything: a rewrite that dropped it would leave
# the grep below with nothing to match and read as a pass. Its siblings above fail on a missing row through
# their case fall-through; this one is a negative check, so it says so explicitly.
RT_HALF="$( rt_row 4444444444444444 )"
if [ -z "$RT_HALF" ]; then
    no "(9f) the half-pair row is missing after the rewrite — a legacy row must survive, and an absent row proves nothing about how it was read"
elif printf '%s\n' "$RT_HALF" | grep -qE '^ack [a-z-]+ 4444444444444444 [0-9]+ (cid=[0-9a-f]+ )?(by=[^ ]+ )?(now=[0-9]+ was=|prov=)'; then
    no "(9f) a half-pair row was treated as provenance-bearing"; printf '%s\n' "$RT_HALF"
else
    ok "(9f) a row with now= but no was= reads as legacy — half a pair is never provenance"
fi
case "$( rt_row 5555555555555555 )" in
    *" p=src/a:b/c.py:41 "*) ok "(9f) a p= path containing ':' survives the round trip — split on the LAST colon" ;;
    *) no "(9f) a p= path containing ':' was mangled on rewrite"; printf '%s\n' "$( rt_row 5555555555555555 )" ;;
esac
# THE UNREACHABILITY CLAIM, proven from bytes rather than argued from ordering: no row anywhere in this
# ledger may carry prov= alongside a live measurement. The backfill runs BEFORE the fold, so the fold
# overwrites the whole record; if that ever stopped holding, a row would show both.
BOTH="$( grep '^ack ' "$RT/.ripwire_quality_acks" | grep -c ' prov=recon .*prov=' || true )"
MIXED="$( grep -c '^ack .* prov=[^ ]* .*\( now=\| was=\).*prov=' "$RT/.ripwire_quality_acks" 2>/dev/null || true )"
[ "${BOTH:-0}" = 0 ] && [ "${MIXED:-0}" = 0 ] \
    && ok "(9f) no row carries a doubled or mixed provenance stamp — measured and reconstructed stay exclusive in the bytes" \
    || no "(9f) a row carries more than one provenance stamp (doubled=$BOTH mixed=$MIXED)"

BFN="$WORK/backfillnum"; cp -R "$NUM" "$BFN" 2>/dev/null
if [ -f "$BFN/.ripwire_quality_acks" ]; then
    strip_prov "$BFN/.ripwire_quality_acks"
    ( cd "$BFN" && "$BIN" . --quality-delta --quality-ack="numeric backfill fixture" >/dev/null 2>&1 )
    NUMROW="$( grep '^ack complexity ' "$BFN/.ripwire_quality_acks" 2>/dev/null )"
    # prov= is the ONLY thing the backfill could have added. A live re-measure of this same finding would
    # legitimately restore now=/was= WITHOUT a prov= stamp, so testing for was= here would fail on correct
    # behaviour; the reconstructed stamp is the thing that must never appear on a numeric row.
    case "$NUMROW" in
        "")         no "(9) the legacy COMPLEXITY row is missing after the re-ack — an absent row proves nothing about the refusal" ;;
        *" prov="*) no "(9) a legacy COMPLEXITY row was given reconstructed provenance — its was= cannot be recovered from this tree and must not be invented"; printf '%s\n' "$NUMROW" ;;
        *) ok "(9) a legacy numeric row was never given a reconstructed was= — the honest refusal" ;;
    esac
else
    no "(9) no numeric fixture ledger to strip"
fi

# ── (10) ledger tokens are external input ───────────────────────────────────────────────────────────────
# (10a) hand-written rows a binary could not have written. Each must come back with its bad value still visible
# and never narrowed: the now= rows keep their text verbatim (no provenance is taken), and the p= rows keep the
# whole token as the path rather than inventing a line.
XT="$WORK/extinput"; mkdir -p "$XT"
printf 'def solo(a):\n    return a\n' > "$XT/x.py"
( cd "$XT" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init >/dev/null 2>&1 )
cat > "$XT/.ripwire_quality_acks" <<'EOF'
# ripwire quality acks v1 — hand-written fixture
ack complexity  a666666666666666 9 now=4294967296 was=0 overflowing now
ack complexity  a777777777777777 9 now=-1 was=2 negative now
ack complexity  a888888888888888 9 now=9 was=2 p=src/a.py:4294967296 overflowing line
ack complexity  a999999999999999 9 now=9 was=2 p=src/a.py:-1 negative line
EOF
( cd "$XT" && "$BIN" . --quality-delta --quality-ack="external-input probe" >/dev/null 2>"$WORK/xt.err" ); xtrc=$?
xt_row(){ grep "^ack [a-z-]* $1 " "$XT/.ripwire_quality_acks" 2>/dev/null; }
[ "$xtrc" = 0 ] || no "(10a) the probe ack exited $xtrc"
case "$( xt_row a666666666666666 )" in
    "") no "(10a) the overflowing-now= row is missing after the rewrite" ;;
    *" now=4294967296 was=0 overflowing now") ok "(10a) now= past 32 bits stays visible text — never narrowed to 0" ;;
    *) no "(10a) now=4294967296 was narrowed or lost"; xt_row a666666666666666 ;;
esac
case "$( xt_row a777777777777777 )" in
    "") no "(10a) the negative-now= row is missing after the rewrite" ;;
    *" now=-1 was=2 negative now") ok "(10a) a negative now= stays visible text — never wrapped to 4294967295" ;;
    *) no "(10a) now=-1 was wrapped or lost"; xt_row a777777777777777 ;;
esac
case "$( xt_row a888888888888888 )" in
    "") no "(10a) the overflowing-line row is missing after the rewrite" ;;
    *" p=src/a.py:4294967296"*) ok "(10a) a p= line past 32 bits stays part of the path text — never narrowed to line 0" ;;
    *) no "(10a) p=src/a.py:4294967296 was narrowed or lost"; xt_row a888888888888888 ;;
esac
case "$( xt_row a999999999999999 )" in
    "") no "(10a) the negative-line row is missing after the rewrite" ;;
    *" p=src/a.py:-1"*) ok "(10a) a negative p= line stays part of the path text — never wrapped to 4294967295" ;;
    *) no "(10a) p=src/a.py:-1 was wrapped or lost"; xt_row a999999999999999 ;;
esac

# (10b) a LIVE finding on a path with a space: the first ack must not write a p= it cannot read back, and a
# second ack must leave the ledger byte-identical (the damage used to land on the second write).
SP="$WORK/spacepath"; mkdir -p "$SP/my dir"
printf 'def grow(a):\n    return a\n' > "$SP/my dir/a b.py"
( cd "$SP" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init >/dev/null 2>&1 )
python3 - "$SP/my dir/a b.py" <<'PY'
import sys
lines = [ "def grow(a):", "    t = 0" ]
for i in range( 40 ):
    lines += [ f"    if a > {i}:", f"        for j in range({i}):", f"            if j % 3 == {i % 3}:", f"                t += j * {i}" ]
lines.append( "    return t" )
open( sys.argv[1], "w" ).write( "\n".join( lines ) + "\n" )
PY
( cd "$SP" && "$BIN" . --quality-delta --quality-ack="space probe" >/dev/null 2>"$WORK/sp1.err" ); sprc1=$?
cp "$SP/.ripwire_quality_acks" "$WORK/sp_first.acks" 2>/dev/null
( cd "$SP" && "$BIN" . --quality-delta --quality-ack="space probe" >/dev/null 2>"$WORK/sp2.err" ); sprc2=$?
SPROWS="$( grep -c '^ack complexity ' "$SP/.ripwire_quality_acks" 2>/dev/null || true )"
if [ "$sprc1" != 0 ] || [ "$sprc2" != 0 ]; then
    no "(10b) the space-path acks exited $sprc1 / $sprc2"
elif [ "${SPROWS:-0}" = 0 ]; then
    no "(10b) no complexity row was acked on the space-path fixture — the probe did not run"
elif grep '^ack ' "$SP/.ripwire_quality_acks" | grep -q ' p=my '; then
    no "(10b) a path with a space was written as a p= token and read back truncated to 'my'"; grep '^ack ' "$SP/.ripwire_quality_acks"
elif ! cmp -s "$WORK/sp_first.acks" "$SP/.ripwire_quality_acks"; then
    no "(10b) a second ack rewrote a space-path row — the ledger does not round-trip"; diff "$WORK/sp_first.acks" "$SP/.ripwire_quality_acks" | head -6
elif grep '^ack complexity ' "$SP/.ripwire_quality_acks" | grep -q ' now=[0-9]* was=[0-9]* space probe$'; then
    ok "(10b) a finding on a path with a space keeps now=/was= and its reason, omits the unspellable locator, and round-trips"
else
    no "(10b) the space-path row lost its now=/was= or its reason"; grep '^ack ' "$SP/.ripwire_quality_acks"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"

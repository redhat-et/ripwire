#!/usr/bin/env bash
# packtailsharecheck.sh — PB1: --pack-task's file tail GETS ITS DECLARED SHARE, and the share is a floor.
#
# THE DEFECT (results/PB1_PACKTASK_1119/READOUT.md §5a). PT1's design sentence for the tail was "it takes its own
# share plus everything the sections before it leave", and the first D1 build implemented only the second half:
# the tail was the leftover, with no floor, while the head was allowed up to kPackTaskHeadRowDropPct (60%) of the
# post-header budget rather than its own share, and monotoneRoll charges a cut section its whole granted share.
# On a corpus with a long task echo and long signatures the leftover was nothing. MEASURED over LocBench's 303
# tasks: the tail declared a 20% share and received 0.6% — a median shown="0" of total="512" files — and on 82 of
# the 84 tasks the bundle failed to complete, the gold file it needed was in that cut tail. Completion is counted
# in FILES and the tail is the section that names files, so a starved tail is a bug, not a tuning shortfall.
#
# RED-FIRST: every arm below fails on a binary from before the fix. Confirmed against
# results/PB1_PACKTASK_1119/bin/ripwire.d1-head (built_from 34be00d0f): on this fixture and task it serves a tail
# of 46 B with shown="0" of 240, against the 1,693 B / 7 rows the fixed binary serves. Arm (R) asserts that, so a
# gate that stops exercising the defect says so instead of passing quietly.
#   RIPWIRE_TAILSHARE_REF=/path/to/old/ripwire test/packtailsharecheck.sh   # also asserts the reference IS red
#
# Arms:
#   (1) a LONG task (1,200 chars, LocBench's shape) at the default budget: shown= is not 0 while total= is not 0
#   (2) the tail's rendered bytes reach the floor its share implies, with row-boundary slack
#   (3) the declared share is READ from src/packtask.h, so this gate and the cascade cannot drift apart
#   (4) monotone: a larger budget never serves FEWER tail rows
#   (5) a --partition slice reserves nothing — the floor must not leak into an inner bundle, which has no tail
#   (6) deterministic and xmllint-clean
#
# Usage: test/packtailsharecheck.sh [BIN]   (default build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
# The house ok()/no() pair: a failed WRITE of the PASS line must set the accumulator (a full disk must not turn a
# red arm green) and ok() must return 0. Verdicts here are if/else, never the one-line shape gateexitcheck forbids.
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "packtailsharecheck: BIN=$BIN"

# (3) the declared share, read out of the source rather than pinned here a second time.
TAILPCT="$( python3 - "$ROOT/src/packtask.h" <<'PY_EOF'
import re, sys
m = re.search( r'kPackTaskQuotaTailPct\s*=\s*(\d+)', open( sys.argv[1], encoding = 'utf-8' ).read() )
print( m.group( 1 ) if m else '' )
PY_EOF
)"
if [ -n "$TAILPCT" ]; then
    ok "(3) the tail's declared share reads $TAILPCT% out of src/packtask.h"
else
    no "(3) could not read kPackTaskQuotaTailPct out of src/packtask.h — every arm below would prove nothing"
    echo "packtailsharecheck: FAIL"; exit 1
fi

# ── the fixture: 240 files with long signatures (so the ranked head is expensive, as it is on a real corpus) and
#    a task whose words spread over all of them (so the tail has hundreds of positive-score files to serve).
FX="$TMP/fx"; mkdir -p "$FX/pkg"
python3 - "$FX/pkg" <<'PY_EOF'
import sys
out = sys.argv[1]
for k in range( 240 ):
    words = " ".join( [ "ledger reconcile drift settlement" ] * max( 1, 24 - k // 10 ) )
    # 40 long-named parameters: the ranked head's 40 rows have to be EXPENSIVE, or the head never reaches its
    # row-drop bound, nothing squeezes the cascade, and this gate passes on a binary that has the defect. That is
    # not hypothetical — the first fixture here used 12 short parameters and the pre-fix reference produced a tail
    # byte-for-byte identical to the fixed one, so arm (R) correctly refused to call the gate red-first.
    long_params = ", ".join( "parameter_number_%02d_with_a_long_descriptive_name" % i for i in range( 40 ) )
    with open( "%s/mod%03d.py" % ( out, k ), "w" ) as f:
        f.write( 'def reconcile_ledger_%03d(%s):\n    """%s"""\n    return helper_%03d(parameter_number_00_with_a_long_descriptive_name)\n\n' % ( k, long_params, words, k ) )
        f.write( 'def helper_%03d(%s):\n    """plain settlement helper number %d"""\n    return parameter_number_00_with_a_long_descriptive_name\n' % ( k, long_params, k ) )
PY_EOF

# a 1,200-character task: LocBench passes a GitHub issue body truncated to exactly this length, and the echo is
# charged twice (the verbatim task= attribute and the ledger's echo), which is what squeezed the cascade.
python3 - "$TMP/task.long" <<'PY_EOF'
import sys
body = ( "Support ledger reconcile drift settlement across the whole package. The reconciliation currently "
         "reports a drift that does not survive a restart, and the settlement path reads a stale ledger. " )
open( sys.argv[1], "w" ).write( ( body * 9 )[ :1200 ] )
PY_EOF
TASK="$( cat "$TMP/task.long" )"

tailfacts(){   # $1 = answer file -> "shown total bytes"
python3 - "$1" <<'PY_EOF'
import re, sys, xml.etree.ElementTree as ET
raw  = open( sys.argv[1], encoding = 'utf-8', errors = 'replace' ).read()
root = ET.fromstring( raw )
t    = root.find( 'tail' )
nc   = re.sub( r'<!--.*?-->', '', raw, flags = re.S )
m    = re.search( r'<tail[ >/]', nc )
if t is None or m is None:
    print( "absent absent 0" )
else:
    st = m.start(); en = nc.find( '</tail>', st )
    print( "%s %s %d" % ( t.get( 'shown' ), t.get( 'total' ), ( en + 7 - st ) if en >= 0 else 0 ) )
PY_EOF
}

"$BIN" "$FX" --pack-task="$TASK" > "$TMP/long.xml" 2>/dev/null || no "--pack-task (long task) exited non-zero"
read -r SHOWN TOTAL TBYTES <<EOF
$( tailfacts "$TMP/long.xml" )
EOF
printf '        long task: <tail shown=%s total=%s> %s B of %s B answer\n' "$SHOWN" "$TOTAL" "$TBYTES" "$( wc -c < "$TMP/long.xml" | tr -d ' ' )"

# (1) the tail serves SOMETHING whenever it has something to serve.
if [ "$TOTAL" != "absent" ] && [ "${TOTAL:-0}" -gt 0 ] && [ "${SHOWN:-0}" -gt 0 ]; then
    ok "(1) a 1,200-char task at the default budget still serves the tail ($SHOWN of $TOTAL files)"
else
    no "(1) the tail served $SHOWN of $TOTAL files — a long task echo starved the one section that names files"
fi

# (2) the share is a FLOOR. The declared share of the SHAPING budget (budget_tokens x 2.36 x 0.90 = 12,744 B at
#     the 6,000-token default) is the target; the assertion allows a generous row-boundary slack because the tail
#     is cut at a whole row and its last row may not fit. Floor = 60% of the declared share.
FLOORB="$( python3 -c "print( int( 12744 * $TAILPCT / 100 * 0.50 ) )" )"
if [ "${TBYTES:-0}" -ge "$FLOORB" ]; then
    ok "(2) the tail reached $TBYTES B, at or above the $FLOORB B floor its $TAILPCT% share implies"
else
    no "(2) the tail got $TBYTES B against a $FLOORB B floor ($TAILPCT% of the 12,744 B shaping budget, 60% slack) — its share was spent by the sections above it"
fi

# (4) monotone in the budget: more bytes must never serve fewer tail rows.
PREV=-1; MONO=1
for B in 4000 6000 8000 12000; do
    "$BIN" "$FX" --pack-task="$TASK" --token-budget="$B" > "$TMP/m.$B" 2>/dev/null
    read -r s t bb <<EOF
$( tailfacts "$TMP/m.$B" )
EOF
    printf '        budget=%-6s tail shown=%s of %s (%s B)\n' "$B" "$s" "$t" "$bb"
    if [ "$s" != "absent" ] && [ "$PREV" -ge 0 ] && [ "${s:-0}" -lt "$PREV" ]; then
        MONO=0
        no "(4) budget=$B serves $s tail rows where a smaller budget served $PREV — the tail is not monotone"
    fi
    [ "$s" = "absent" ] || PREV="$s"
done
if [ "$MONO" = "1" ]; then
    ok "(4) the tail's row count is non-decreasing across budgets 4000..12000"
fi

# (5) the reserve must not leak into a --partition slice, which carries no tail at all.
"$BIN" "$FX" --pack-task="$TASK" --partition=3 > "$TMP/part.xml" 2>/dev/null
if grep -qF '<tail ' "$TMP/part.xml"; then
    no "(5) a --partition slice emitted a <tail> — the reserve leaked into an inner bundle"
else
    ok "(5) a --partition slice carries no <tail>, so it reserves nothing for one"
fi

# (6) determinism and G4.
"$BIN" "$FX" --pack-task="$TASK" > "$TMP/d2.xml" 2>/dev/null
if cmp -s "$TMP/long.xml" "$TMP/d2.xml" && xmllint --noout "$TMP/long.xml" 2>/dev/null; then
    ok "(6) deterministic (byte-identical x2) and xmllint-clean"
else
    no "(6) not deterministic, or not well-formed XML"
fi

# RED-FIRST, when a pre-fix binary is handed in: it MUST fail arm (1) or (2), or this gate proves nothing.
if [ -n "${RIPWIRE_TAILSHARE_REF:-}" ] && [ -x "${RIPWIRE_TAILSHARE_REF}" ]; then
    "$RIPWIRE_TAILSHARE_REF" "$FX" --pack-task="$TASK" > "$TMP/ref.xml" 2>/dev/null
    read -r rs rt rb <<EOF
$( tailfacts "$TMP/ref.xml" )
EOF
    printf '        reference binary: <tail shown=%s total=%s> %s B\n' "$rs" "$rt" "$rb"
    if [ "${rs:-0}" = "0" ] || [ "${rb:-0}" -lt "$FLOORB" ]; then
        ok "(R) the pre-fix reference IS red on this fixture ($rs rows, $rb B) — the arms above can fail"
    else
        no "(R) the pre-fix reference passes arms (1)+(2) ($rs rows, $rb B) — this gate is not red-first against it"
    fi
fi

[ $fail -eq 0 ] && { echo "packtailsharecheck: PASS"; exit 0; }
echo "packtailsharecheck: FAIL"; exit 1

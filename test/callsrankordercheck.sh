#!/usr/bin/env bash
# callsrankordercheck.sh — the <calls> callee rows under an emitted BODY are ordered by QUERY RELEVANCE on
# every route that has a query to rank by, and stay in node-id order on the routes that do not.
#
# WHAT WAS WRONG. serialize.h's calleeWalkOrder already sorted a callee listing by rank — but only under
# `namesOnly && rank`, and the ONLY caller that supplied a rank was packHops (the compact --for <hops>
# route). Every packBodies caller built a CalleeCallsSink with no rank, so the walk fell back to the CSR's
# own node-id order and the 16-row cap (kCalleeRowCap) kept the sixteen LOWEST node ids. That is --for's
# auto/--detail bodies, --pack-task's <bodies> and --from-trace's rank-1 body: the three highest-traffic
# verbs in the tool, and the three that always have a query in scope.
#
# The disclosure was never wrong — `<calls total="21" shown="16" capped="1"/>` is exactly honest about the
# COUNT. It is silent about the CHOICE, which is what makes this the worst shape of cap: the reader gets a
# complete-looking, correctly-labelled answer with the one row they asked about missing. The identical
# defect was already found by measurement and FIXED once on the compact route (see CalleeCallsSink::rank's
# own comment: `split_exclude`'s nine callees cut to the first four by node id, dropping `build_filter`,
# the one callee that query was about) and left standing on the route these verbs actually take.
#
# THE CONTRACT THIS PINS (arms 1, 2 and 6b were run RED against the pre-fix binary):
#   (1) --pack-task: a body whose callee listing is CUT keeps the callee the TASK NAMES. The fixture's
#       target callee has the HIGHEST node id of the twenty-one, so the pre-fix node-id cut is guaranteed
#       to drop it — and did.
#   (2) --from-trace: the trace names two frames; the innermost frame's <calls> keeps the OTHER frame.
#       Pre-fix it dropped it, i.e. the tool hid the edge the stack trace had just walked.
#   (3) the comparator is TOTAL — (rank desc, id asc). Every leaf scores zero on the task, so the rows
#       after the target must be leaf_00…leaf_14 in ASCENDING node-id order, not any order a sort
#       implementation happens to produce. Non-negotiable #2: determinism is a contract.
#   (4) THE CENSUS ARM: --expand has NO query in scope and must stay byte-identical — its <calls> rows are
#       still leaf_00…leaf_15 in node-id order and the target is still ABSENT. This arm is what stops the
#       fix leaking a ranking into a listing that never asked for one; it pins the pre-fix bytes exactly.
#   (5) THE COMPACT ROUTE keeps its already-correct ordering. Worth an arm because a search of test/ for
#       calleeWalkOrder / CalleeCallsSink / namesOnly / the measurement's own symbol names finds NOTHING:
#       compactroutecheck asserts the <hops><calls><c n= SHAPE and no gate asserts the ORDER, so the
#       earlier measured fix was ungated and could regress silently.
#   (6) mutation control: the checker rejects a canned pre-fix listing and accepts a canned fixed one —
#       and 6b re-runs arm 1's extraction over a MUTATED bundle to prove the extraction itself has teeth.
#   (7) two runs byte-identical on all four routes; every bundle xmllint-clean.
#
# The fixture is generated into a temp dir rather than committed under test/: it is 22 C++ symbols whose
# only job is to overflow a 16-row cap, and adding them to this repo's own index would move byte-pinned
# numbers in unrelated gates for no gain here.
#
# Usage:  bash test/callsrankordercheck.sh   |   RIPWIRE_BIN=asan/ripwire bash test/callsrankordercheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "callsrankordercheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FX="$TMP/fx"

# ── the fixture ───────────────────────────────────────────────────────────────────────────────────────────
# Node ids are assigned in sorted crawl order, so file order fixes id order: aaa_leaves.cpp holds the twenty
# LOW-id callees, zzz_target.cpp holds the ONE callee the task is about at the HIGHEST id of the twenty-one.
# hub_dispatch calls all twenty-one, so its listing is cut at 16 and a node-id cut cannot keep the target.
mkdir -p "$FX/src"
{
    echo '// twenty low-id leaves: filler callees that no query in this gate mentions'
    for i in $( seq -w 0 19 ); do
        printf 'int leaf_%s( int v ) { return v + %d; }\n' "$i" "$(( 10#$i ))"
    done
} > "$FX/src/aaa_leaves.cpp"
{
    echo 'int hub_dispatch( int v )'
    echo '{'
    echo '    int a = 0;'
    for i in $( seq -w 0 19 ); do
        printf '    a += leaf_%s( v );\n' "$i"
    done
    echo '    a += quarantine_ledger_sweep( v );'
    echo '    return a;'
    echo '}'
} > "$FX/src/hub.cpp"
cat > "$FX/src/zzz_target.cpp" <<'EOF'
// Sweeps the quarantine ledger and reconciles quarantined entries.
int quarantine_ledger_sweep( int v )
{
    return v * 3;
}
EOF
# an ASan-shaped trace naming BOTH frames: hub_dispatch innermost, the target callee one frame out
printf '    #0 0x000102 in hub_dispatch(int) src/hub.cpp:5:9\n    #1 0x000104 in main src/zzz_target.cpp:3:5\n' > "$TMP/trace.txt"

TASK="reconcile the quarantine ledger sweep"
CONC="how are ledger entries reconciled during a sweep"

# ── the checker: ONE <calls> block per bundle by construction (only hub_dispatch has out-edges in this
# fixture), so it asserts that and prints the block's attrs plus its <c n=> names in DOCUMENT order.
# It parses the emitted bytes, never a fabricated string — arm 6b re-runs it over a mutated bundle.
cat > "$TMP/calls.py" <<'PY'
import re, sys
s = sys.stdin.read()
blocks = re.findall( r'(<calls\b[^>]*>)(.*?)</calls>', s, re.S )
if len( blocks ) != 1:
    print( "FAIL expected exactly one <calls> block, found %d" % len( blocks ) ); sys.exit( 1 )
hdr, body = blocks[0]
names = re.findall( r'<c n="([^"]*)"', body )
if not names:
    print( "FAIL the <calls> block carries no <c n=> rows" ); sys.exit( 1 )
total = re.search( r'\btotal="(\d+)"', hdr )
shown = re.search( r'\bshown="(\d+)"', hdr )
capped = re.search( r'\bcapped="(\d+)"', hdr )
if not total:
    print( "FAIL <calls> carries no total=" ); sys.exit( 1 )
if not shown or not capped:
    print( "FAIL the listing is NOT cut (no shown=/capped=) — this arm measures nothing: %s" % hdr ); sys.exit( 1 )
if int( shown.group( 1 ) ) != len( names ):
    print( "FAIL shown=%s but %d rows printed" % ( shown.group( 1 ), len( names ) ) ); sys.exit( 1 )
if int( shown.group( 1 ) ) >= int( total.group( 1 ) ):
    print( "FAIL shown >= total on a capped listing: %s" % hdr ); sys.exit( 1 )
print( "OK total=%s shown=%s rows=%s" % ( total.group( 1 ), shown.group( 1 ), " ".join( names ) ) )
PY
rows_of(){ printf '%s' "$1" | python3 "$TMP/calls.py"; }
seq_of(){ printf '%s' "$1" | sed -n 's/.*rows=//p'; }

# the (rank desc, id asc) sequence arm 1/2 expect: the target first, then every zero-scoring leaf in
# ASCENDING node-id order. Spelled out rather than pattern-matched, so a partial order cannot pass.
EXPECT_RANKED="quarantine_ledger_sweep"
for i in $( seq -w 0 14 ); do EXPECT_RANKED="$EXPECT_RANKED leaf_$i"; done
# the node-id (census) sequence arm 4 expects: the first sixteen by node id, target absent.
EXPECT_NODEID=""
for i in $( seq -w 0 15 ); do EXPECT_NODEID="${EXPECT_NODEID:+$EXPECT_NODEID }leaf_$i"; done

# ── (1) --pack-task keeps the callee the task NAMES ───────────────────────────────────────────────────────
PT="$( "$BIN" "$FX" --pack-task="$TASK" --token-budget=9000 2>/dev/null )"
V="$( rows_of "$PT" )"
if [ -z "$V" ] || [ "${V#OK}" = "$V" ]; then
    no "(1) --pack-task: $V"
else
    S="$( seq_of "$V" )"
    case " $S " in
        *" quarantine_ledger_sweep "*) ok "(1) --pack-task: the cut <calls> KEEPS the callee the task names ($V)" ;;
        *) no "(1) --pack-task DROPPED quarantine_ledger_sweep from a cut <calls>: $V" ;;
    esac
    # (3) the comparator is total: target first, then leaf_00…leaf_14 ascending
    if [ "$S" = "$EXPECT_RANKED" ]; then
        ok "(3) --pack-task rows are (rank desc, id asc) exactly: target first, then leaf_00…leaf_14 ascending"
    else
        no "(3) --pack-task row order is not (rank desc, id asc)"
        printf '        want: %s\n        got:  %s\n' "$EXPECT_RANKED" "$S"
    fi
fi

# ── (2) --from-trace keeps the OTHER frame of the same trace ──────────────────────────────────────────────
TR="$( "$BIN" "$FX" --from-trace="$TMP/trace.txt" 2>/dev/null )"
V="$( rows_of "$TR" )"
if [ -z "$V" ] || [ "${V#OK}" = "$V" ]; then
    no "(2) --from-trace: $V"
else
    S="$( seq_of "$V" )"
    case " $S " in
        *" quarantine_ledger_sweep "*) ok "(2) --from-trace: the innermost frame's cut <calls> KEEPS the trace's other frame ($V)" ;;
        *) no "(2) --from-trace DROPPED the trace's own second frame from the innermost frame's <calls>: $V" ;;
    esac
    [ "$S" = "$EXPECT_RANKED" ] \
        && ok "(3) --from-trace rows are (rank desc, id asc) exactly" \
        || { no "(3) --from-trace row order is not (rank desc, id asc)"; printf '        want: %s\n        got:  %s\n' "$EXPECT_RANKED" "$S"; }
fi

# ── (4) THE CENSUS ARM: --expand has no query — byte-identical node-id order, target still absent ─────────
# --top-k=0 is only there to take the bundle route: an --expand this small auto-serves the whole file
# (mode="whole-file"), which emits no <calls> at all and would measure nothing.
EX="$( "$BIN" "$FX" --expand=hub_dispatch --top-k=0 2>/dev/null )"
V="$( rows_of "$EX" )"
if [ -z "$V" ] || [ "${V#OK}" = "$V" ]; then
    no "(4) --expand: $V"
else
    S="$( seq_of "$V" )"
    if [ "$S" = "$EXPECT_NODEID" ]; then
        ok "(4) census: --expand keeps the CSR's own node-id order, leaf_00…leaf_15, unchanged"
    else
        no "(4) --expand's callee order CHANGED — a ranking leaked into a listing with no query"
        printf '        want: %s\n        got:  %s\n' "$EXPECT_NODEID" "$S"
    fi
    case " $S " in
        *" quarantine_ledger_sweep "*) no "(4) --expand surfaced the target — the census route was reordered" ;;
        *) ok "(4) census: the target stays absent from --expand (no query ⇒ no ranking)" ;;
    esac
fi

# ── (5) the compact --for route keeps its already-correct ordering (previously UNGATED) ───────────────────
FC="$( "$BIN" "$FX" --for="$CONC" 2>/dev/null )"
if ! printf '%s' "$FC" | grep -q '<hops'; then
    no "(5) the conceptual --for query did not take the compact <hops> route — this arm measured nothing"
else
    V="$( rows_of "$FC" )"
    if [ -z "$V" ] || [ "${V#OK}" = "$V" ]; then
        no "(5) compact <hops>: $V"
    else
        S="$( seq_of "$V" )"
        case "$S " in
            "quarantine_ledger_sweep "*) ok "(5) compact route: the ranked callee is still row 1 of the cut <hops> listing ($V)" ;;
            *) no "(5) the compact packHops route lost its rank ordering: $V" ;;
        esac
    fi
fi

# ── (6) mutation control — the checker must have teeth ────────────────────────────────────────────────────
# each canned block is SELF-CONSISTENT (shown= equals its row count, shown < total, capped="1") so the
# checker reaches a verdict on it rather than refusing it — a refusal would read as "target absent" and
# give arm 6 a false pass, which is exactly the shape CONTRIBUTING §2 calls "empty equals agreement".
PRECUT='<ctx><b n="hub_dispatch"><calls total="21" shown="2" capped="1"><c n="leaf_00" l="2">s</c><c n="leaf_01" l="3">s</c></calls></b></ctx>'
FIXED='<ctx><b n="hub_dispatch"><calls total="21" shown="2" capped="1"><c n="quarantine_ledger_sweep" l="2">s</c><c n="leaf_00" l="3">s</c></calls></b></ctx>'
UNCUT='<ctx><b n="hub_dispatch"><calls total="2"><c n="leaf_00" l="2">s</c><c n="leaf_01" l="3">s</c></calls></b></ctx>'
V="$( rows_of "$PRECUT" )"
if [ "${V#OK}" = "$V" ]; then
    no "(6) the checker could not read a well-formed canned pre-fix listing: $V"
else
    S="$( seq_of "$V" )"
    case " $S " in *" quarantine_ledger_sweep "*) no "(6) the checker read a target out of a pre-fix listing — no teeth" ;;
                   *) ok "(6) mutation control: a canned pre-fix listing reads as target-absent" ;; esac
fi
V="$( rows_of "$FIXED" )"
if [ "${V#OK}" = "$V" ]; then
    no "(6) the checker could not read a well-formed canned FIXED listing: $V"
else
    S="$( seq_of "$V" )"
    case " $S " in *" quarantine_ledger_sweep "*) ok "(6) …and a canned fixed listing reads as target-present" ;;
                   *) no "(6) the checker cannot see the target in a canned FIXED listing — it can never go green honestly" ;; esac
fi
rows_of "$UNCUT" >/dev/null 2>&1 \
    && no "(6) the checker ACCEPTED an UNCUT listing — every arm above would pass on a listing that was never capped" \
    || ok "(6) …and it refuses an uncut listing, so no arm can pass by measuring a complete one"
# (6b) the same extraction, over a MUTATED copy of arm 1's REAL bundle: rename the target in the emitted
# bytes and the arm must flip. This is the control over real input CONTRIBUTING §2 rule 1 asks for.
MUT="$( printf '%s' "$PT" | sed 's/quarantine_ledger_sweep/quarxntine_ledger_sweep/g' )"
if [ "$MUT" = "$PT" ]; then
    no "(6b) the mutation did not take — the control proves nothing"
else
    V="$( rows_of "$MUT" )"; S="$( seq_of "$V" )"
    case " $S " in *" quarantine_ledger_sweep "*) no "(6b) arm 1's extraction still finds the target after it was renamed away — no teeth" ;;
                   *) ok "(6b) arm 1's extraction, re-run over a mutated real bundle, goes red" ;; esac
fi

# ── (7) determinism + well-formedness on all four routes ──────────────────────────────────────────────────
det_fail=0
d(){ A="$( eval "$1" )"; B="$( eval "$1" )"; [ "$A" = "$B" ] || { no "(7) not byte-identical across two runs: $2"; det_fail=1; }; }
d "\"$BIN\" \"$FX\" --pack-task=\"$TASK\" --token-budget=9000 2>/dev/null" "--pack-task"
d "\"$BIN\" \"$FX\" --from-trace=\"$TMP/trace.txt\" 2>/dev/null" "--from-trace"
d "\"$BIN\" \"$FX\" --expand=hub_dispatch --top-k=0 2>/dev/null" "--expand"
d "\"$BIN\" \"$FX\" --for=\"$CONC\" 2>/dev/null" "--for compact"
[ "$det_fail" = 0 ] && ok "(7) all four bundles byte-identical across two runs"
if command -v xmllint >/dev/null 2>&1; then
    wf=0
    for v in "$PT" "$TR" "$EX" "$FC"; do
        printf '%s' "$v" | xmllint --noout - 2>/dev/null || wf=1
    done
    if [ "$wf" = 0 ]; then ok "(7) all four bundles are well-formed"; else no "(7) a bundle is not well-formed"; fi
else
    printf '  SKIP  xmllint (not installed)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"

#!/usr/bin/env bash
# metriclegendcheck.sh — two metric labels say what they measure, and the quality bars say what they are (lane metric-labels,
# research audit 2026-11-26 items 2, 4 and 10).
#
# WHY. Two attributes read as more than they are:
#   tested=1 means an indexed test REACHES the row over call edges. Reaching is not asserting: Veritas (arXiv 2610.33708,
#     11 Java projects, 51,382 branch outcomes) found 18% of covered branch outcomes could change with no test failing. A
#     legend that leaves "reached" unqualified lets a reader take tested=1 as "checked".
#   cbo= is OUT-coupling: distinct in-repo targets a symbol calls or composes (graph.h computeQMetrics). in= is its
#     in-coupling. Arif, Kuutila & Ralph (arXiv 2609.20411; EFA on Maven, CFA on 22 projects) found in- and out-coupling load
#     as SEPARATE factors, so a legend that calls cbo "coupled types" and a score that adds cbo to in= both measure a construct
#     that does not exist.
# And the quality-delta size/complexity bars are delta heuristics, not smell detectors; the one human-labelled length reference
# (MLCQ Long Method >= 26 lines, MCC 0.777, arXiv 2611.01636, single author) is recorded beside them, with no default moved.
#
# ARMS. Every legend arm is RED on the base this lane branched from (5f4b50415): the readings said "transitively reaches" with
# no qualifier and "coupled types". The grep arm (G) is a prohibition, so it carries its own mutation control (G0): the matcher
# must flag a planted `cbo + callerCount` line, or a pass of (G) proves nothing.
#   (T1) compact <s tested=1> reading (--callees, --metrics)       (T2) compact <d tested=1> reading (--pack-task --metrics)
#   (T3) compact <tested> column reading (--format=columnar)        (T4) full-dialect row and column readings (graphlegend.h)
#   (C1) compact --metrics: cbo= reads as out-coupling, never summed with in=
#   (G0) the matcher flags a planted composite (mutation control)   (G) no src/ line sums cbo with an in-degree
#   (D1) docs/METHODOLOGY.md §9.3 and the src/quality.h bar comment carry the delta-heuristic wording and the MLCQ reference
#
# Usage: bash test/metriclegendcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "metriclegendcheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# The corpus compactlegendcheck (D31)/(D33) reads: test_run reaches run, and run reaches helper, so both carry tested=1.
COR="$TMP/tested"; mkdir -p "$COR/src"
printf 'def helper():\n    return 1\n\n\ndef run():\n    return helper()\n' >"$COR/src/lib.py"
printf 'from src.lib import run\n\n\ndef test_run():\n    assert run() == 1\n' >"$COR/test_lib.py"

# answer FILE args... — one run over the corpus; a probe that fails to answer is a FAIL, never an empty pass
answer(){ local out="$1"; shift; ( cd "$COR" && perl -e 'alarm 60; exec @ARGV' "$BIN" . "$@" --no-cache >"$out" 2>/dev/null </dev/null ); }
# clause FILE MARKER — the legend sentence (comments only) that starts at MARKER, up to the next ". " or the comment's end
clause(){ python3 - "$1" "$2" <<'PY'
import re, sys
doc = open( sys.argv[1], encoding = "utf-8", errors = "replace" ).read()
legend = " ".join( re.findall( r"<!--(.*?)-->", doc, flags = re.S ) )
i = legend.find( sys.argv[2] )
if i < 0:
    sys.exit( 0 )
rest = legend[i:]
j = rest.find( ". " )
print( rest if j < 0 else rest[:j] )
PY
}
# reads LABEL FILE MARKER NEEDLE... — the clause at MARKER exists and holds every NEEDLE
reads(){
    local label="$1" file="$2" marker="$3" c n; shift 3
    c="$( clause "$file" "$marker" )"
    if [ -z "$c" ]; then no "$label: no legend clause starting '$marker' (premise: the answer carries the attribute)"; return; fi
    for n in "$@"; do
        case "$c" in *"$n"*) ;; *) no "$label: the clause does not say '$n': $c"; return ;; esac
    done
    ok "$label: $c"
}

echo "=== (T) tested= reads REACHED, not asserted ==="
answer "$TMP/callees.c" --callees=run
grep -q 'tested="1"' "$TMP/callees.c" || no "(T1) premise: --callees=run carries no tested=\"1\" row"
reads "(T1) compact --callees=run <s tested=1>" "$TMP/callees.c" "<s tested=1>:" "over call edges" "reached, not asserted"
answer "$TMP/metrics.c" --metrics
reads "(T1) compact --metrics <s tested=1>" "$TMP/metrics.c" "<s tested=1>:" "over call edges" "reached, not asserted"
answer "$TMP/pack.c" --pack-task=helper --metrics
grep -q '<d [^>]*tested="1"' "$TMP/pack.c" || no "(T2) premise: --pack-task=helper --metrics carries no <d tested=\"1\"> row"
reads "(T2) compact --pack-task=helper --metrics <d tested=1>" "$TMP/pack.c" "<d tested=1>:" "over call edges" "reached, not asserted"
answer "$TMP/col.c" --callers=helper --format=columnar
grep -q '<tested>' "$TMP/col.c" || no "(T3) premise: --callers=helper --format=columnar carries no <tested> column"
reads "(T3) compact columnar <tested> column" "$TMP/col.c" "<tested> column:" "over call edges" "reached, not asserted"
answer "$TMP/callees.f" --callees=run --legend=full
reads "(T4) full --callees=run row reading" "$TMP/callees.f" 'tested="1" on a row means' "over call edges" "reached, not asserted"
answer "$TMP/col.f" --callers=helper --format=columnar --legend=full
reads "(T4) full columnar column reading" "$TMP/col.f" "tested= is a dense column" "over call edges" "reached, not asserted"
# The payload is unchanged by a legend edit: tested="1" still rides the same rows (a reading fix, not a predicate change).
rowsTested(){ perl -0pe 's/<!--.*?-->//gs' "$1" | grep -o '<s [^>]*tested="1"' | wc -l | tr -d ' '; }   # payload rows only, never the legend
[ "$( rowsTested "$TMP/callees.c" )" -gt 0 ] && [ "$( rowsTested "$TMP/callees.c" )" = "$( rowsTested "$TMP/callees.f" )" ] \
    && ok "(T) the tested=\"1\" rows are the same under both dialects" || no "(T) compact and full disagree on the tested=\"1\" rows"

echo "=== (C) cbo= reads as OUT-coupling, apart from in= ==="
reads "(C1) compact --metrics cbo= reading" "$TMP/metrics.c" "s in= out= cx=" "out-coupling" "never summed with in="
grep -q ' cbo="' "$TMP/metrics.c" || no "(C1) premise: --metrics carries no cbo= attribute"

echo "=== (G) no composite score sums cbo with an in-degree ==="
# A code line (comments stripped) that names cbo AND an in-degree source AND an arithmetic operator between identifiers. The
# in-degree sources are the names this tree spells it by: fanIn, callerCount, inDegree/in_degree, inEdges, the in-edge row
# offsets (inRo/inOff). Emitters that hand both to a serializer side by side (`.fanIn = fanIn, .cbo = cbo`) carry no operator.
matcher(){ python3 - "$@" <<'PY'
import re, sys
IN = re.compile( r"\b(fanIn|callerCount|inDegree|in_degree|inEdges|inRo|inOff|in_deg)\b" )
CBO = re.compile( r"\bcbo\b" )
OP = re.compile( r"[\w\])]\s*[-+*]\s*[\w(*]|\+=|-=" )
hits = 0
for path in sys.argv[1:]:
    try:
        text = open( path, encoding = "utf-8", errors = "replace" ).read()
    except OSError:
        continue
    text = re.sub( r"/\*.*?\*/", lambda m: "\n" * m.group( 0 ).count( "\n" ), text, flags = re.S )
    for n, line in enumerate( text.split( "\n" ), 1 ):
        code = re.sub( r'"(?:\\.|[^"\\])*"', '""', line.split( "//", 1 )[0] )
        if CBO.search( code ) and IN.search( code ) and OP.search( code ):
            hits += 1
            print( "%s:%d: %s" % ( path, n, line.strip()[:160] ) )
sys.exit( 1 if hits else 0 )
PY
}
printf 'inline double couplingScore( const QMetrics& q, std::size_t i )\n{\n    return q.cbo[i] + q.callerCount[i];   // the composite\n}\n' >"$TMP/planted.h"
printf '    const MainDispatch d{ cfg, &fanIn, &qmetrics.cbo };\n    // cbo + fanIn in a comment is not code\n' >"$TMP/benign.h"
if ! matcher "$TMP/planted.h" >/dev/null && matcher "$TMP/benign.h" >/dev/null; then
    ok "(G0) mutation control: the matcher flags a planted cbo + callerCount composite and passes a side-by-side hand-off and a comment"
else
    no "(G0) mutation control: the matcher missed the planted composite or flagged the benign lines — (G) would prove nothing"
fi
gsrc="$( cd "$ROOT" && ls src/*.h src/*.cpp src/infra/*.h 2>/dev/null | wc -l | tr -d ' ' )"
if [ "$gsrc" -gt 0 ] && gout="$( cd "$ROOT" && matcher src/*.h src/*.cpp src/infra/*.h )"; then
    ok "(G) no line in $gsrc src/ files sums cbo with an in-degree"
else
    no "(G) a composite sums cbo with an in-degree (in- and out-coupling are separate factors, 2609.20411) — report it, do not re-rank silently: $gout"
fi

echo "=== (D) the size/complexity bars are delta heuristics, not smell detectors ==="
for f in docs/METHODOLOGY.md src/quality.h; do
    t="$( tr '\n' ' ' <"$ROOT/$f" | tr -s ' ' )"
    miss=""
    for n in "delta heuristics, not smell detectors" "MLCQ" "26 lines" "0.777" "2611.01636" "single author"; do
        case "$t" in *"$n"*) ;; *) miss="$miss '$n'" ;; esac
    done
    [ -z "$miss" ] && ok "(D1) $f records the bars as delta heuristics with the MLCQ Long Method reference" || no "(D1) $f lacks:$miss"
done
grep -q '^### 9\.3 ' "$ROOT/docs/METHODOLOGY.md" && ok "(D1) the wording lives in METHODOLOGY §9 (a 9.3 addendum)" || no "(D1) docs/METHODOLOGY.md has no §9.3 addendum"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILURES"; exit 1; }

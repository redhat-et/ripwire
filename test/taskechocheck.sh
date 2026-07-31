#!/usr/bin/env bash
# taskechocheck.sh — gate for §B1.6 + §B1.7: the two header facts the XML and JSON dialects reported
# differently.
#
# Usage:
#   test/taskechocheck.sh                       # uses build/ctxpack
#   test/taskechocheck.sh asan/ctxpack
#   CTXPACK_BIN=build_base/ctxpack test/taskechocheck.sh   # red-first: both families MUST fail here
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# DO NOT edit regression.sh — this is a standalone gate invoked from there.
#
# §B1.6 — --pack-task's XML header states three budget facts ("budget=N bytes (T-token target, ceiling C)")
#   and the JSON tail carried only two: budget_tokens and budget_bytes. The CEILING — the hard byte limit
#   the token target implies, and the number a consumer actually checks a bundle against — had no JSON key.
#
# §B1.7 — the header prose lives in an XML COMMENT, where "--" is ill-formed, so the echo of the user's own
#   query is dash-collapsed ("--for's" -> "-for's") before it goes in. That scrub is right and unchanged;
#   what was wrong is that the collapsed text was XML's ONLY copy, so the two dialects disagreed about the
#   string the user typed (--json echoes it raw). Attributes are not comments and are not scrubbed, so the
#   verbatim task (and route note) now ride on the root element beside the readable scrubbed echo.
#
# The query below deliberately contains a real double-hyphen flag name: that is the exact input that used
# to come back altered.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${CTXPACK_BIN:-$ROOT/build/ctxpack}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
CORPUS="$TMP/corpus"
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "taskechocheck: no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "taskechocheck: python3 is required (JSON + XML-attribute arms)"; exit 2; }

echo "taskechocheck: BIN=$BIN"

mkdir -p "$CORPUS/src" || { echo "taskechocheck: cannot create corpus under $TMP"; exit 2; }
cat > "$CORPUS/src/budget.py" <<'PY_EOF'
def ceilingArithmetic( tokenTarget, bytesPerToken ):
    """Derive the hard byte ceiling a token target implies."""
    return int( tokenTarget * bytesPerToken )


def headroomBudget( ceilingBytes, headroom ):
    """The working budget, always at or below the ceiling."""
    return int( ceilingBytes * headroom )
PY_EOF

# the input that used to come back altered: a real double-hyphen flag name inside the query
TASK="audit the --token-budget ceiling arithmetic"

# read one attribute off the ROOT element. The XML parser un-escapes it, so this compares the same
# characters the user typed rather than their escaped spelling.
rootAttr(){ python3 -c '
import sys, xml.etree.ElementTree as ET
root = ET.fromstring( sys.stdin.read() )
sys.stdout.write( root.attrib.get( sys.argv[1], "@@MISSING@@" ) )
' "$1" 2>/dev/null; }

jsonKeyStr(){ python3 -c 'import sys,json; sys.stdout.write(str(json.load(sys.stdin).get(sys.argv[1],"@@MISSING@@")))' "$1" 2>/dev/null; }

# the STATED ceiling out of the XML header. Deliberately anchored on "ceiling <digits>": the probe task
# below contains the word "ceiling" itself, and a `grep -o 'ceiling [0-9]*'` happily matches that first,
# digitless occurrence and reports an empty number.
xmlCeilingOf(){ python3 -c '
import sys, re
m = re.search( r"ceiling ([0-9]+)", sys.stdin.read() )
sys.stdout.write( m.group( 1 ) if m else "" )
' 2>/dev/null; }

XMLFOR="$(  "$BIN" "$CORPUS" --for="$TASK" 2>/dev/null )"
XMLPT="$(   "$BIN" "$CORPUS" --pack-task="$TASK" 2>/dev/null )"
JSONFOR="$( "$BIN" "$CORPUS" --for="$TASK" --json 2>/dev/null )"
JSONPT="$(  "$BIN" "$CORPUS" --pack-task="$TASK" --json 2>/dev/null )"

[ -n "$XMLFOR" ] && [ -n "$XMLPT" ] && [ -n "$JSONFOR" ] && [ -n "$JSONPT" ] \
  || { echo "taskechocheck: one of the four probe runs produced nothing — the gate cannot observe its contract"; exit 2; }

# ── §B1.7 arm 1: the XML root carries the VERBATIM query ───────────────────────────────────────────
xfor="$( printf '%s' "$XMLFOR" | rootAttr task )"
xpt="$(  printf '%s' "$XMLPT"  | rootAttr task )"
for pair in "for|$xfor" "pack-task|$xpt"; do
    verb="${pair%%|*}"; got="${pair#*|}"
    if   [ "$got" = "$TASK" ];        then ok "--$verb XML root task= is the verbatim query"
    elif [ "$got" = "@@MISSING@@" ];  then no "--$verb XML root has no task= attribute — the verbatim query is unrecoverable from XML"
    else                                   no "--$verb XML root task= was rewritten: '$got' != '$TASK'"; fi
done

# ── §B1.7 arm 2: XML and JSON agree on the user's own string ───────────────────────────────────────
jfor="$( printf '%s' "$JSONFOR" | jsonKeyStr task )"
jpt="$(  printf '%s' "$JSONPT"  | jsonKeyStr task )"
if [ "$jfor" = "$xfor" ]; then ok "--for: the two dialects report the SAME task string"; else no "--for: XML task='$xfor' vs JSON task='$jfor'"; fi
if [ "$jpt"  = "$xpt"  ]; then ok "--pack-task: the two dialects report the SAME task string"; else no "--pack-task: XML task='$xpt' vs JSON task='$jpt'"; fi

# ── §B1.7 arm 3: the route note is recoverable verbatim too ────────────────────────────────────────
rfor="$( printf '%s' "$XMLFOR" | rootAttr route )"
case "$rfor" in
    "@@MISSING@@") no "--for XML root has no route= attribute";;
    *"--for"*)     ok "--for XML root route= keeps its double-hyphen flag names verbatim";;
    *"-for"*)      no "--for XML root route= is still dash-collapsed ('$rfor')";;
    *)             no "--for XML root route= names no ranker flag at all ('$rfor')";;
esac

# ── §B1.7 arm 4: the SCRUB itself is untouched — the comment echo is still collapsed and G4-legal ──
case "$XMLFOR" in
    *'<!-- ctxpack lens for "audit the -token-budget ceiling arithmetic"'*)
        ok "the comment echo is still dash-collapsed (the G4 scrub was not weakened)";;
    *)  no "the comment echo no longer carries the collapsed form — the scrub was changed instead of bypassed";;
esac
if command -v xmllint >/dev/null 2>&1; then
    for pair in "for|$XMLFOR" "pack-task|$XMLPT"; do
        verb="${pair%%|*}"; doc="${pair#*|}"
        if printf '%s' "$doc" | xmllint --noout - 2>/dev/null; then ok "--$verb XML with the new root attrs is well-formed (G4)"
        else no "--$verb XML with the new root attrs fails xmllint"; fi
    done
else
    no "xmllint is required for the G4 arms (install libxml2) — the gate does not skip"
fi

# ── §B1.7 arm 5: verbs that echo no task keep a BARE root (no empty attributes) ────────────────────
case "$( "$BIN" "$CORPUS" --lego=ceilingArithmetic 2>/dev/null | head -c 5 )" in
    "<ctx>") ok "a task-less verb still opens with a bare <ctx> (no empty task=/route=)";;
    *)       no "a task-less verb's root gained an attribute it has no value for";;
esac

# ── §B1.6 arm 1: the JSON tail carries the CEILING the XML header states ───────────────────────────
xmlCeiling="$( printf '%s' "$XMLPT" | xmlCeilingOf )"
jsonCeiling="$( printf '%s' "$JSONPT" | jsonKeyStr budget_ceiling_bytes )"
jsonBytes="$(   printf '%s' "$JSONPT" | jsonKeyStr budget_bytes )"
jsonTokens="$(  printf '%s' "$JSONPT" | jsonKeyStr budget_tokens )"
[ -n "$xmlCeiling" ] || no "the XML header states no 'ceiling N' — the reference value is gone"
if   [ "$jsonCeiling" = "@@MISSING@@" ]; then no "--pack-task --json has no budget_ceiling_bytes key — the one budget fact with no JSON key"
elif [ "$jsonCeiling" = "$xmlCeiling" ]; then ok "budget_ceiling_bytes ($jsonCeiling) equals the XML header's ceiling"
else                                          no "budget_ceiling_bytes ($jsonCeiling) disagrees with the XML header's ceiling ($xmlCeiling)"; fi

# ── §B1.6 arm 2: the three budget keys are mutually consistent ────────────────────────────────────
if [ "$jsonCeiling" != "@@MISSING@@" ] && [ "$jsonBytes" != "@@MISSING@@" ] && [ "$jsonBytes" -le "$jsonCeiling" ] 2>/dev/null; then
    ok "budget_bytes ($jsonBytes) is the working budget at or below the ceiling ($jsonCeiling)"
else
    no "budget_bytes ($jsonBytes) is not at or below budget_ceiling_bytes ($jsonCeiling)"
fi
if [ "$jsonCeiling" != "@@MISSING@@" ] && [ "$jsonTokens" != "@@MISSING@@" ] && [ "$jsonCeiling" -gt "$jsonTokens" ] 2>/dev/null; then
    ok "budget_ceiling_bytes reads as a BYTE count, not a restated token count ($jsonCeiling > $jsonTokens)"
else
    no "budget_ceiling_bytes ($jsonCeiling) does not read as a byte ceiling for budget_tokens ($jsonTokens)"
fi

# ── §B1.6 arm 3: an explicit --token-budget moves the ceiling, and both dialects track it together ─
xc2="$( "$BIN" "$CORPUS" --pack-task="$TASK" --token-budget=2000 2>/dev/null | xmlCeilingOf )"
jc2="$( "$BIN" "$CORPUS" --pack-task="$TASK" --token-budget=2000 --json 2>/dev/null | jsonKeyStr budget_ceiling_bytes )"
if [ -n "$xc2" ] && [ "$xc2" = "$jc2" ] && [ "$xc2" != "$xmlCeiling" ]; then
    ok "--token-budget=2000 moves the ceiling and both dialects report the same new value ($jc2)"
else
    no "--token-budget=2000: xml ceiling='$xc2' json='$jc2' (default was '$xmlCeiling') — the two do not track"
fi

# ── §B4 (capture-audit-4): --query's ROUTED comment is the SEVENTH echo site ──────────────────────
# xmlCommentText's header claimed it was "a drop-in at all six echo sites"; main.cpp's queryRouteNote was a
# seventh that hand-rolled the std::unique dash collapse and scrubbed neither control bytes nor invalid
# UTF-8 — while RouteChoice::reason embeds the user's own query token. So a 0x01 or a 0xFF in --query put
# that byte inside an XML comment, ctxpack exited 0, and xmllint rejected the whole document: a G4 breach at
# exit 0. This lives HERE rather than in xmlwellformed.sh because it is the same task-ECHO family the arms
# above pin, and it asserts BOTH halves — the document parses AND the scrub did not eat the echo.
if command -v xmllint >/dev/null 2>&1; then
    # $'\001' is a C0 control (illegal XML even escaped); $'\377' is an invalid UTF-8 lead byte. Both reach
    # the comment through identifierHit. The plain query is the CONTROL: if it failed too, the arms below
    # would be measuring a broken --query rather than the scrub.
    for probe in "control:ceilingArithmetic" "c0:$( printf 'ceilingArithmetic\001x' )" "utf8:$( printf 'ceilingArithmetic\377x' )"; do
        label="${probe%%:*}"; q="${probe#*:}"
        "$BIN" "$CORPUS" --query="$q" > "$TMP/route.$label.xml" 2>/dev/null; qrc=$?
        if [ "$qrc" -ne 0 ]; then
            no "§B4 --query ($label) exited $qrc — expected 0"
        elif xmllint --noout "$TMP/route.$label.xml" 2>/dev/null; then
            ok "§B4 --query ($label) is well-formed XML at exit 0 (G4)"
        else
            no "§B4 --query ($label) exits 0 with a document xmllint rejects — the routed comment is unscrubbed"
        fi
        # the echo must still be THERE: a scrub that deleted the note would pass xmllint for the wrong reason
        grep -q '<!-- routed: ' "$TMP/route.$label.xml" \
            && ok "§B4 --query ($label) still carries its routed comment" \
            || no "§B4 --query ($label) lost the routed comment entirely — scrubbed away, not scrubbed"
    done
    # the scrub is LOSSY BY DESIGN and the note says which bytes it eats: a control byte becomes a space and
    # an invalid sequence becomes '?'. Asserting the substitution (not just well-formedness) is what stops a
    # future "fix" from silently dropping the byte and shortening the user's own token.
    grep -q 'names a symbol (ceilingArithmetic x)' "$TMP/route.c0.xml" \
        && ok "§B4 the C0 byte became a SPACE inside the comment (xmlCommentText rule 2)" \
        || no "§B4 the C0 byte was not replaced by a space: [$( head -c 90 "$TMP/route.c0.xml" )]"
    grep -q 'names a symbol (ceilingArithmetic?x)' "$TMP/route.utf8.xml" \
        && ok "§B4 the invalid UTF-8 byte became '?' inside the comment (xmlCommentText rule 3)" \
        || no "§B4 the invalid UTF-8 byte was not replaced by '?': [$( head -c 90 "$TMP/route.utf8.xml" )]"
else
    no "xmllint is required for the §B4 arms (install libxml2) — the gate does not skip"
fi

# ── determinism ───────────────────────────────────────────────────────────────────────────────────
if [ "$( "$BIN" "$CORPUS" --for="$TASK" 2>/dev/null )" = "$XMLFOR" ]; then ok "--for XML is byte-identical run-to-run"; else no "--for XML is not deterministic"; fi
if [ "$( "$BIN" "$CORPUS" --pack-task="$TASK" --json 2>/dev/null )" = "$JSONPT" ]; then ok "--pack-task JSON is byte-identical run-to-run"; else no "--pack-task JSON is not deterministic"; fi

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES PRESENT"; exit 1

#!/usr/bin/env bash
# receiptpostcheck.sh — the gate for "the edit receipt already knows what it tells you to run next".
#
# capture-audit 2026-09-04, finding P9 (lens 8 #9 and §(4)).
#
# THE DEFECT. Every edit verb printed a receipt and a stderr line saying
#   ripwire edit: applied atomically; verify with --edit-check=F:S, then --affected=F
# — two more calls the tool already knows it wants, both milliseconds warm on an index it has just
# invalidated and is about to rebuild anyway. Claude Code's own policy makes an agent Read before it edits;
# other agents do not, and the receipt is the one document an editing agent is guaranteed to read. It also
# reported a BYTE span while every other verb in the tool speaks FILE:LINE.
#
# THE PROPERTY. After a successful edit the receipt carries, in the SAME call:
#   lines        — the post-edit LINE range of the applied text, beside the byte span
#   edit_check   — status/callers/incompatible/sites, EQUAL to a separate --edit-check on the same target
#   tests_to_run — EQUAL to --affected=<the receipt's own file> row for row, run recipe included
# and --no-post-check (MCP post_check:false) opts out, leaving the receipt exactly as it was plus lines.
# Equality against the standalone verbs is the whole assertion: a receipt that answered the same question
# differently would be worse than one that stayed silent.
#
# The sandbox is a throwaway `git clone --local` under this script's own temp dir. The edit verbs WRITE, so
# they are never pointed at the checkout that runs the gate.
#
# Usage:  test/receiptpostcheck.sh              # uses build/ripwire
#         RIPWIRE_BIN=asan/ripwire test/receiptpostcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "git required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "receiptpostcheck: BIN=$BIN"

# ── the sandbox ────────────────────────────────────────────────────────────────────────────────────────
# geo.py holds the edit target and two callers (one with TWO call sites, so sites is not degenerate);
# test/area_spec.py is a third caller in a test path, and test/area_spec.sh gives it a derivable runner so
# the tests_to_run rows carry a real run= rather than only the not-derivable disclosure.
SB="$TMP/sandbox"
mkdir -p "$SB/test"
cat > "$SB/geo.py" <<'EOF'
def area_of_triangle(base, height):
    return 0.5 * base * height


def report():
    first = area_of_triangle(3, 4)
    second = area_of_triangle(6, 8)
    return first + second


def summarize():
    return area_of_triangle(1, 2)
EOF
cat > "$SB/test/area_spec.py" <<'EOF'
from geo import area_of_triangle


def test_area():
    assert area_of_triangle(2, 2) == 2.0
EOF
cat > "$SB/test/area_spec.sh" <<'EOF'
#!/usr/bin/env bash
python3 -m pytest test/area_spec.py
EOF
chmod +x "$SB/test/area_spec.sh"
( cd "$SB" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm init >/dev/null 2>&1 )

# the payload: a WIDENED arity, so the edit is a real contract-change with provably incompatible callers.
cat > "$TMP/payload.py" <<'EOF'
def area_of_triangle(base, height, scale):
    return 0.5 * base * height * scale
EOF

# a per-run pristine copy (the verbs WRITE — every arm below starts from the committed state).
fresh(){ rm -rf "$TMP/w"; git clone --local -q "$SB" "$TMP/w" 2>/dev/null; }

jq_field(){ python3 -c '
import sys, json
d = json.load(sys.stdin)
for k in sys.argv[1].split("."):
    if isinstance(d, list): d = d[int(k)]
    elif k in d:            d = d[k]
    else:                   print("__ABSENT__"); sys.exit(0)
print(json.dumps(d, sort_keys=True, separators=(",",":")))
' "$1"; }

# ── ARM 1 — the receipt carries the post-edit LINE range beside the byte span ──────────────────────────
fresh
R1="$( cd "$TMP/w" && "$BIN" . --replace-symbol-body=area_of_triangle --edit-payload="$TMP/payload.py" 2>/dev/null )"
printf '%s' "$R1" > "$TMP/r1.json"
L1="$( jq_field lines < "$TMP/r1.json" )"
if [ "$L1" = "__ABSENT__" ]; then
    no "(1) the receipt carries a byte span and no line range — every other verb in the tool speaks FILE:LINE"
else
    # the range must actually bracket the applied text in the file on disk, not merely be present.
    python3 - "$TMP/w/geo.py" "$TMP/r1.json" <<'PY'
import sys, json
lines = open(sys.argv[1]).read().split("\n")
r = json.load(open(sys.argv[2]))["lines"]
body = "\n".join(lines[r["start"]-1:r["end"]])
assert "def area_of_triangle(base, height, scale):" in body, "range %r does not bracket the applied text: %r" % (r, body)
assert "def report():" not in body, "range %r overshoots into the next definition" % (r,)
print("OK")
PY
    [ $? -eq 0 ] \
        && ok "(1) the receipt's lines={start,end} brackets exactly the applied text ($L1)" \
        || no "(1) the receipt's line range does not bracket the applied text"
fi

# ── ARM 2 — edit_check is folded in, and it EQUALS the separate --edit-check ───────────────────────────
EC_XML="$( cd "$TMP/w" && "$BIN" . --edit-check=geo.py:area_of_triangle 2>/dev/null | sed 's/.*-->//' )"
# the ROOT tag alone: the document is one line, so a greedy `.*incompatible="` reaches the LAST occurrence,
# which is a <c> row's per-caller flag ("1") and not the root's count.
EC_ROOT="$( printf '%s' "$EC_XML" | grep -oE '<edit-check [^>]*>' )"
EC_STATUS="$( printf '%s' "$EC_ROOT" | sed -nE 's/.* status="([^"]*)".*/\1/p' )"
EC_CALLERS="$( printf '%s' "$EC_ROOT" | sed -nE 's/.* callers="([0-9]*)".*/\1/p' )"
EC_INCOMP="$( printf '%s' "$EC_ROOT" | sed -nE 's/.* incompatible="([0-9]*)".*/\1/p' )"
[ "$EC_STATUS" = "contract-change" ] && [ "${EC_INCOMP:-0}" -ge 2 ] \
    || no "(2) fixture degenerate: the standalone --edit-check reads status=$EC_STATUS incompatible=$EC_INCOMP"
GOT_EC="$( jq_field edit_check < "$TMP/r1.json" )"
if [ "$GOT_EC" = "__ABSENT__" ]; then
    no "(2) the receipt carries no edit_check — the agent is told to run a second call the tool already ran"
else
    python3 - "$TMP/r1.json" "$EC_STATUS" "$EC_CALLERS" "$EC_INCOMP" "$EC_XML" <<'PY'
import sys, json, re
r  = json.load(open(sys.argv[1]))["edit_check"]
st, ca, inc, xml = sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
assert r["status"]       == st,  "receipt status %r != --edit-check %r" % (r["status"], st)
assert int(r["callers"]) == ca,  "receipt callers %r != --edit-check %r" % (r["callers"], ca)
assert int(r["incompatible"]) == inc, "receipt incompatible %r != --edit-check %r" % (r["incompatible"], inc)
# the sites, row for row, against the XML's own flagged rows
want = {}
for m in re.finditer(r'<c n="([^"]*)" p="([^"]*)" incompatible="1"(?: sites_l="([^"]*)")?/>', xml):
    want[m.group(1)] = (m.group(2), [int(x) for x in (m.group(3) or "").split(",") if x])
got = { s["n"]: (s["p"], [int(x) for x in s["l"]]) for s in r["sites"] }
assert got == want, "receipt sites %r != --edit-check flagged rows %r" % (got, want)
assert want, "the fixture flagged no callers — the sites assertion would be vacuous"
print("OK")
PY
    [ $? -eq 0 ] \
        && ok "(2) receipt edit_check == a separate --edit-check (status, callers, incompatible, and every call site)" \
        || no "(2) the receipt's edit_check disagrees with the verb it replaces"
fi

# ── ARM 3 — tests_to_run is folded in, and it EQUALS --affected=<the receipt's own file> ───────────────
AFF="$( cd "$TMP/w" && "$BIN" . --affected=geo.py 2>/dev/null )"
GOT_T="$( jq_field tests_to_run < "$TMP/r1.json" )"
if [ "$GOT_T" = "__ABSENT__" ]; then
    no "(3) the receipt carries no tests_to_run — the second call the stderr hint asks for"
else
    python3 - "$TMP/r1.json" "$AFF" <<'PY'
import sys, json, re
rows = json.load(open(sys.argv[1]))["tests_to_run"]
aff  = sys.argv[2]
want = []
for m in re.finditer(r'<test p="([^"]*)"(?: run="([^"]*)")?(?: run_unknown="1")?/>', aff):
    want.append((m.group(1), m.group(2)))
got = [ (t["p"], t.get("run")) for t in rows ]
assert got == want, "receipt tests_to_run %r != --affected rows %r" % (got, want)
assert want, "the fixture reached no test file — the assertion would be vacuous"
print("OK")
PY
    [ $? -eq 0 ] \
        && ok "(3) receipt tests_to_run == --affected=<the receipt's own file>, path and run recipe" \
        || no "(3) the receipt's tests_to_run disagrees with the verb it replaces"
fi

# ── ARM 3b — the FOLD carries the COMPLETENESS KEYS its standalone twin carries (verify-wave2 F3) ──────
# Arms 2 and 3 compare the fields the fold COPIES, and that is exactly where the gap was: the standalone
# roots carry the resolver gauge and the floor marker, and the folded objects did not.
#
#   receipt : "edit_check":{"status":…,"callers":2,"incompatible":2,"sites":[…]}, "tests_to_run":[]
#   twin    : <edit-check … callers="2" incompatible="2" graph_ambiguous="5923" graph_unresolved="2952" counts_floor="1">
#   twin    : <affected … tests="0" reached="105" script_gates_unmodelled="558" counts_floor="1" graph_ambiguous=…>
#
# So `"tests_to_run":[]` was an UNLABELLED ZERO — the twin says "0 modelled tests, 558 shell gates the walk
# cannot see, counts are floors"; the fold said `[]`. That is H5/H14's own rule (a CSR-derived count carries
# counts_floor; a disclosure survives into every sibling surface or is DECLARED) missed on the surface this
# wave built. THE RULE: a folded sub-result carries the same completeness keys its standalone twin carries.
#
# MECHANICAL, not a hand-written list of the four keys we happen to have fixed: the wanted set is read off
# the TWIN'S OWN ROOT at run time and filtered to the honesty vocabulary below, so a disclosure a future
# round adds to --edit-check or --affected reds this arm until the fold carries it too.
DISCLOSURE_VOCAB='counts_floor graph_ambiguous graph_unresolved script_gates_unmodelled tests'
python3 - "$TMP/r1.json" "$EC_ROOT" "$AFF" "$DISCLOSURE_VOCAB" <<'F3_EOF' >"$TMP/f3.res" 2>&1
import sys, json, re
receipt = json.load( open( sys.argv[1] ) )
vocab   = set( sys.argv[4].split() )

def rootAttrs( tag ):
    return dict( re.findall( r'([a-z_]+)="([^"]*)"', tag ) )

ecRoot  = rootAttrs( sys.argv[2] )
affTag  = re.search( r"<affected [^>]*>", sys.argv[3] )
if not affTag:
    print( "the --affected root did not parse — this arm has no twin to compare against" ); raise SystemExit( 1 )
affRoot = rootAttrs( affTag.group( 0 ) )

def agrees( have, want ):
    return str( have ).lower() == want.lower() or ( want == "1" and str( have ).lower() == "true" )

bad = []
# (i) edit_check: the fold is an OBJECT, so the keys belong inside it
ec = receipt.get( "edit_check", {} )
for k in sorted( set( ecRoot ) & vocab ):
    if k not in ec:
        bad.append( "edit_check is missing %s (the standalone --edit-check root carries %s=%r)" % ( k, k, ecRoot[k] ) )
    elif not agrees( ec[k], ecRoot[k] ):
        bad.append( "edit_check %s=%r disagrees with the twin's %r" % ( k, ec[k], ecRoot[k] ) )
# (ii) tests_to_run is an ARRAY and cannot carry attributes, so its completeness keys are its SIBLINGS on
#      the receipt root — the same place --affected puts them relative to its own <test> rows.
for k in sorted( set( affRoot ) & vocab ):
    if k not in receipt:
        bad.append( "the receipt is missing %s beside tests_to_run (--affected carries %s=%r) — an unlabelled zero"
                    % ( k, k, affRoot[k] ) )
    elif not agrees( receipt[k], affRoot[k] ):
        bad.append( "receipt %s=%r disagrees with --affected's %r" % ( k, receipt[k], affRoot[k] ) )
if bad:
    print( "\n".join( "    " + b for b in bad ) ); raise SystemExit( 1 )
print( "OK: edit_check carries %s; the receipt carries %s beside tests_to_run"
       % ( ",".join( sorted( set( ecRoot ) & vocab ) ), ",".join( sorted( set( affRoot ) & vocab ) ) ) )
F3_EOF
if [ $? -eq 0 ]; then ok "(3b) $( cat "$TMP/f3.res" )"; else no "(3b) the folded sub-results drop disclosures their standalone twins carry:"; cat "$TMP/f3.res"; fi

# ── ARM 4 — the loop is ONE call ───────────────────────────────────────────────────────────────────────
# The point of the finding, stated as an assertion rather than left implied: edit -> verify -> tests-to-run
# used to be three invocations, and all three answers must now come out of the first one.
python3 - "$TMP/r1.json" <<'PY'
import sys, json
r = json.load(open(sys.argv[1]))
missing = [k for k in ("applied","span","lines","edit_check","tests_to_run") if k not in r]
assert not missing, "the single receipt is missing %r" % (missing,)
print("OK")
PY
[ $? -eq 0 ] \
    && ok "(4) edit -> verify -> tests-to-run is ONE call: the receipt holds all three answers" \
    || no "(4) the receipt still does not close the loop in one call"

# ── ARM 5 — --no-post-check opts out, and costs the receipt nothing else ───────────────────────────────
fresh
R5="$( cd "$TMP/w" && "$BIN" . --replace-symbol-body=area_of_triangle --edit-payload="$TMP/payload.py" --no-post-check 2>/dev/null )"
printf '%s' "$R5" > "$TMP/r5.json"
python3 - "$TMP/r5.json" <<'PY'
import sys, json
r = json.load(open(sys.argv[1]))
assert "edit_check"   not in r, "--no-post-check still ran the contract check"
assert "tests_to_run" not in r, "--no-post-check still ran the affected-tests lookup"
for k in ("applied","symbol","file","span","lines","replaced_bytes","stale_index","note"):
    assert k in r, "--no-post-check dropped %r, which is not part of the post-check" % (k,)
print("OK")
PY
[ $? -eq 0 ] \
    && ok "(5) --no-post-check omits edit_check and tests_to_run and nothing else (lines stays: it is free)" \
    || no "(5) --no-post-check is missing, ignored, or drops more than the post-check"

# ── ARM 6 — the family: the two insert verbs carry it too ──────────────────────────────────────────────
printf 'def area_of_square(side):\n    return side * side\n\n\n' > "$TMP/insert.py"
fresh
R6="$( cd "$TMP/w" && "$BIN" . --insert-before-symbol=report --edit-payload="$TMP/insert.py" 2>/dev/null )"
printf '%s' "$R6" | python3 -c '
import sys, json
r = json.load(sys.stdin)
for k in ("lines","edit_check","tests_to_run"):
    assert k in r, "insert_before_symbol receipt has no %r" % (k,)
print("OK")
' >/dev/null 2>&1 \
    && ok "(6) --insert-before-symbol carries the same folded receipt (the family, not one verb)" \
    || { no "(6) an insert verb's receipt does not carry the post-check"; printf '%s\n' "$R6" | head -c 400; echo; }

# ── ARM 7 — MCP parity: the same receipt, and post_check:false opts out ────────────────────────────────
fresh
MCP_IN(){ printf '%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
  "$1"; }
M7="$( MCP_IN '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"replace_symbol_body","arguments":{"path":"'"$TMP/w"'","symbol":"area_of_triangle","new_body":"def area_of_triangle(base, height, scale):\n    return 0.5 * base * height * scale\n"}}}' \
      | "$BIN" --mcp 2>/dev/null | tail -1 )"
printf '%s' "$M7" | python3 -c '
import sys, json
r = json.load(sys.stdin)
t = json.loads(r["result"]["content"][0]["text"])
for k in ("lines","edit_check","tests_to_run"):
    assert k in t, "MCP replace_symbol_body receipt has no %r" % (k,)
print("OK")
' >/dev/null 2>&1 \
    && ok "(7) MCP replace_symbol_body carries the same folded receipt" \
    || { no "(7) the MCP edit receipt does not carry the post-check"; printf '%s\n' "$M7" | head -c 500; echo; }
fresh
M7B="$( MCP_IN '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"replace_symbol_body","arguments":{"path":"'"$TMP/w"'","symbol":"area_of_triangle","post_check":false,"new_body":"def area_of_triangle(base, height, scale):\n    return 0.5 * base * height * scale\n"}}}' \
      | "$BIN" --mcp 2>/dev/null | tail -1 )"
printf '%s' "$M7B" | python3 -c '
import sys, json
r = json.load(sys.stdin)
assert "error" not in r, "post_check:false was refused: %r" % (r["error"],)
t = json.loads(r["result"]["content"][0]["text"])
assert "edit_check"   not in t, "post_check:false still ran the contract check"
assert "tests_to_run" not in t, "post_check:false still ran the affected-tests lookup"
print("OK")
' >/dev/null 2>&1 \
    && ok "(7) MCP post_check:false opts out, as --no-post-check does on the CLI" \
    || { no "(7) MCP post_check:false is unknown or ignored"; printf '%s\n' "$M7B" | head -c 400; echo; }

# ── ARM 8 — --edit-plan: dry-run resolves each op to file:line + its 1-hop callers; apply carries edit_check
fresh
mkdir -p "$TMP/w/plans"
cp "$TMP/payload.py" "$TMP/w/plans/body.py"
# `file` disambiguates: the payload itself lives under the plan's own directory and is INDEXED, so it
# defines a second area_of_triangle and a bare target is honestly ambiguous.
cat > "$TMP/w/plans/p.json" <<'EOF'
{"version":1,"edits":[{"op":"replace_symbol_body","target":"area_of_triangle","file":"geo.py","payload":"body.py"}]}
EOF
DRY="$( cd "$TMP/w" && "$BIN" . --edit-plan=plans/p.json --dry-run 2>/dev/null )"
printf '%s' "$DRY" | python3 -c '
import sys, json
op = json.load(sys.stdin)["operations"][0]
assert "at" in op, "dry-run op carries no resolved file:line"
assert ":" in op["at"] and op["at"].split(":")[-1].isdigit(), "at=%r is not file:line" % (op["at"],)
assert "callers" in op, "dry-run op carries no 1-hop caller union"
assert int(op["callers"]) >= 2, "callers=%r — the fixture has three callers, this is not the union" % (op["callers"],)
print("OK")
' >/dev/null 2>&1 \
    && ok "(8) --edit-plan --dry-run resolves each op to file:line and names its 1-hop caller union" \
    || { no "(8) the dry-run receipt still cannot be judged before --apply"; printf '%s\n' "$DRY" | head -c 500; echo; }
APPLY="$( cd "$TMP/w" && "$BIN" . --edit-plan=plans/p.json --apply 2>/dev/null )"
printf '%s' "$APPLY" | python3 -c '
import sys, json
op = json.load(sys.stdin)["operations"][0]
assert "edit_check" in op, "apply op carries no per-op edit_check"
assert op["edit_check"]["status"] == "contract-change", "per-op edit_check says %r" % (op["edit_check"]["status"],)
print("OK")
' >/dev/null 2>&1 \
    && ok "(8) --edit-plan --apply carries the per-op edit_check" \
    || { no "(8) the apply receipt carries no per-op edit_check"; printf '%s\n' "$APPLY" | head -c 500; echo; }

# (8b) F3, the same rule on the PLAN receipt: callers= and callers_union= are read off the same name-based
# CSR --edit-check's callers= is, so they carry the same floor and the same gauge. The per-op edit_check
# object goes through postCheckJson, so it inherits the fold's keys; the root's callers_union= is the plan
# receipt's OWN CSR-derived count and needs its own.
for MODE in --dry-run --apply; do
    fresh
    mkdir -p "$TMP/w/plans"; cp "$TMP/payload.py" "$TMP/w/plans/body.py"
    cat > "$TMP/w/plans/p.json" <<'PLAN_EOF'
{"version":1,"edits":[{"op":"replace_symbol_body","target":"area_of_triangle","file":"geo.py","payload":"body.py"}]}
PLAN_EOF
    R="$( cd "$TMP/w" && "$BIN" . --edit-plan=plans/p.json "$MODE" 2>/dev/null )"
    printf '%s' "$R" | python3 -c '
import sys, json
r = json.load( sys.stdin )
bad = []
if "callers_union" in r and "counts_floor" not in r:
    bad.append( "callers_union=%r on the root with no counts_floor — a CSR-derived count read as a total" % ( r[ "callers_union" ], ) )
for i, op in enumerate( r.get( "operations", [] ) ):
    if "callers" in op and "counts_floor" not in op and "counts_floor" not in r:
        bad.append( "operations[%d].callers=%r carries no floor" % ( i, op[ "callers" ] ) )
    ec = op.get( "edit_check" )
    if ec is not None and "counts_floor" not in ec:
        bad.append( "operations[%d].edit_check drops counts_floor its standalone twin carries" % ( i, ) )
if bad:
    print( "; ".join( bad ) ); raise SystemExit( 1 )
print( "OK" )
' >"$TMP/f3b.res" 2>&1 \
        && ok "(8b) --edit-plan $MODE: every CSR-derived count on the receipt carries the floor its twin carries" \
        || { no "(8b) --edit-plan $MODE receipt: $( cat "$TMP/f3b.res" )"; }
done

# ── ARM 9 — every receipt is still valid JSON, and the write half is untouched ─────────────────────────
for f in "$TMP/r1.json" "$TMP/r5.json"; do
    python3 -c 'import sys,json; json.load(open(sys.argv[1]))' "$f" >/dev/null 2>&1 \
        || no "(9) $( basename "$f" ) is not valid JSON"
done
grep -q 'scale' "$TMP/w/geo.py" 2>/dev/null \
    && ok "(9) the receipts parse as JSON and the edits actually landed on disk" \
    || no "(9) the edit did not land — every assertion above described a write that did not happen"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"

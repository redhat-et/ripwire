#!/usr/bin/env bash
# routingcheck.sh — THE ROUTING SWITCH (src/forrouteswitch.h, lane ROUTING 11-25) and the first of its two defaults, the FILE-GAP
# GROUND of `--for`'s confidence= (src/lexical.h headFileGapPct + deriveForConfidence): when the best row of any other file trails
# r=1 by 20 % or more, confidence="high" even without a 20 % adjacent step, and the header says why with file_gap_pct="N".
# The second default (the θ17 edit-file body form) has its own gate, test/bodyeditcheck.sh; arm (T) here only pins that it is on.
# ARMS (every one NEW: a binary without the switch serves no file_gap_pct=, so G1/G2/T fail)
#   (G0)  not vacuous: the GAP question answers confidence="low" with the switch off and "high" with it on
#   (G1)  ON, GAP question: the header has confidence="high" margin_pct="0" file_gap_pct="N", N >= 20; the default (compact) legend
#         and --legend=compact carry the compact clause exactly once, --legend=full its full definition exactly once; MCP carries it too
#   (G2)  PRESENT ONLY WHEN IT GROUNDS: a low answer and a sharp/complete high answer carry no file_gap_pct= and no clause
#   (O)   OFF SWITCH: RIPWIRE_ROUTING=0 answers carry no file_gap_pct=, no clause, no body_form="edit"; with RIPWIRE_PARENT_BIN set (a
#         binary from before the switch) every OFF answer is the parent's default byte for byte (GAP, LOW, NAMED, EDIT, EDIT page 2,
#         EDIT whole, GAP --legend=compact, GAP --legend=full, GAP over MCP)
#   (T)   θ17 default: the EDIT question's default page has body_form="edit"; RIPWIRE_ROUTING=0 has none
#   (D)   well formed (xmllint) and deterministic (two ON runs)
#   (M)   MUTATION NEGATIVE CONTROLS: G1's detector FAILS on the OFF GAP page; G2's detector FAILS on the ON GAP page
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-${1:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "routingcheck: python3 required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "routingcheck: xmllint required"; exit 2; }
PARENT="${RIPWIRE_PARENT_BIN:-}"
echo "routingcheck: BIN=$BIN${PARENT:+ PARENT=$PARENT}"
cd "$ROOT" || exit 2
unset RIPWIRE_ROUTING RIPWIRE_BODIES_EDIT RIPWIRE_BODY_POINTERS
exec python3 - "$BIN" "$PARENT" <<'PY'
import json, os, re, subprocess, sys
BIN, PARENT = sys.argv[1], sys.argv[2]
GAP   = "where is the adaptive cut computed"            # no 20 % adjacent step; the 2nd file trails r=1 by >= 20 %
LOW   = "tiny shape detector"                           # low either way
NAMED = "headFileGapPct"                                # high on its own (complete), no file-gap ground needed
EDIT  = "fix the act line insertion in a for answer"    # an edit task: θ17's form
fail = 0
def ok(m): print("  PASS  " + m)
def no(m):
    global fail; fail = 1; print("  FAIL  " + m)
def run(argv, off=False, binary=None):
    env = dict(os.environ)
    if off: env["RIPWIRE_ROUTING"] = "0"
    return subprocess.run([binary or BIN, "src", "--no-cache"] + argv, capture_output=True, env=env, stdin=subprocess.DEVNULL).stdout.decode("utf8", "replace")
def mcp(args, off=False, binary=None):
    env = dict(os.environ)
    if off: env["RIPWIRE_ROUTING"] = "0"
    req = [{"jsonrpc": "2.0", "id": 0, "method": "initialize"}, {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "for", "arguments": args}}]
    p = subprocess.run([binary or BIN, "src", "--mcp"], input="".join(json.dumps(r) + "\n" for r in req).encode(), capture_output=True, env=env)
    for line in p.stdout.decode("utf8", "replace").splitlines():
        try: r = json.loads(line)
        except ValueError: continue
        if r.get("id") == 1: return "".join(c.get("text", "") for c in r.get("result", {}).get("content", []))
    return ""
root = lambda t: t.split(">", 1)[0]
attr = lambda t, k: (re.search(r' ' + k + r'="([^"]*)"', root(t)) or [None, None])[1]
FULL_DEF = "file_gap_pct= how far the best row of any other file trails r=1"
COMPACT_DEF = "file_gap_pct=: other files trail r=1"
def grounded(t, compact=False):   # G1's detector
    n = attr(t, "file_gap_pct")
    return (attr(t, "confidence") == "high" and attr(t, "margin_pct") == "0" and n is not None and n.isdigit() and int(n) >= 20
            and t.count(COMPACT_DEF if compact else FULL_DEF) == 1)
def absent(t):                     # G2's detector
    return "file_gap_pct" not in t
A = {k: run(["--for=" + q]) for k, q in (("gap", GAP), ("low", LOW), ("named", NAMED), ("edit", EDIT))}
O = {k: run(["--for=" + q], off=True) for k, q in (("gap", GAP), ("low", LOW), ("named", NAMED), ("edit", EDIT))}
gapc, gapc_off = run(["--for=" + GAP, "--legend=compact"]), run(["--for=" + GAP, "--legend=compact"], off=True)
gapf, gapf_off = run(["--for=" + GAP, "--legend=full"]), run(["--for=" + GAP, "--legend=full"], off=True)
gapm, gapm_off = mcp({"task": GAP}), mcp({"task": GAP}, off=True)
p2, p2_off = run(["--for=" + EDIT, "--page-bytes=12000:2"]), run(["--for=" + EDIT, "--page-bytes=12000:2"], off=True)
wh_off = run(["--for=" + EDIT, "--page-bytes=0"], off=True)
# G0
if attr(O["gap"], "confidence") == "low" and attr(A["gap"], "confidence") == "high": ok("(G0) GAP: low with the switch off, high with it on")
else: no(f"(G0) vacuous: GAP off={attr(O['gap'], 'confidence')} on={attr(A['gap'], 'confidence')}")
# G1
if grounded(A["gap"], compact=True): ok(f"(G1) GAP: confidence=high margin_pct=0 file_gap_pct={attr(A['gap'], 'file_gap_pct')}, its clause once")
else: no("(G1) GAP: no grounded high header, or the clause is missing / repeated")
if grounded(gapf): ok("(G1) GAP --legend=full: the full definition once")
else: no("(G1) GAP --legend=full: the full definition is missing or repeated")
if grounded(gapc, compact=True): ok("(G1) GAP --legend=compact: the compact clause once")
else: no("(G1) GAP --legend=compact: the compact clause is missing or repeated")
if re.search(r' file_gap_pct="\d+"', gapm) and attr(A["gap"], "file_gap_pct") in gapm: ok("(G1) GAP over MCP carries file_gap_pct= (same value)")
else: no("(G1) GAP over MCP has no file_gap_pct= (or another value)")
# G2
for k in ("low", "named"):
    if absent(A[k]): ok(f"(G2) {k.upper()} ({attr(A[k], 'confidence')}): no file_gap_pct=, no clause")
    else: no(f"(G2) {k.upper()}: file_gap_pct= or its clause where it does not ground the level")
if attr(A["named"], "confidence") == "high": ok("(G2) NAMED is high on its own (the present-only arm is not vacuous)")
else: no("(G2) NAMED is not high: the present-only arm on a high answer is vacuous")
# O
offs = list(O.values()) + [gapc_off, gapf_off, gapm_off, p2_off, wh_off]
if all(absent(t) and 'body_form="edit"' not in t for t in offs) and all(t for t in offs): ok("(O) RIPWIRE_ROUTING=0: no file_gap_pct=, no clause, no edit form")
else: no("(O) an OFF answer is empty or carries a routing default")
if PARENT:
    P = {k: run(["--for=" + q], binary=PARENT) for k, q in (("gap", GAP), ("low", LOW), ("named", NAMED), ("edit", EDIT))}
    pairs = [(k, O[k], P[k]) for k in P] + [("gap compact", gapc_off, run(["--for=" + GAP, "--legend=compact"], binary=PARENT)),
             ("gap full", gapf_off, run(["--for=" + GAP, "--legend=full"], binary=PARENT)),
             ("gap mcp", gapm_off, mcp({"task": GAP}, binary=PARENT)), ("edit p2", p2_off, run(["--for=" + EDIT, "--page-bytes=12000:2"], binary=PARENT)),
             ("edit whole", wh_off, run(["--for=" + EDIT, "--page-bytes=0"], binary=PARENT))]
    for k, a, b in pairs:
        if a and a == b: ok(f"(O) {k}: the OFF answer is the parent's default byte for byte")
        else: no(f"(O) {k}: the OFF answer moved against the parent")
else: ok("(O) no RIPWIRE_PARENT_BIN: parent comparison skipped (the lane runs it)")
# T
if 'body_form="edit"' in root(A["edit"]) and 'body_form="edit"' not in root(O["edit"]): ok("(T) EDIT: the edit-file form is the default, off under RIPWIRE_ROUTING=0")
else: no("(T) EDIT: the edit-file form is not the default (or not off under the switch)")
# D
for k, t in (("gap", A["gap"]), ("edit", A["edit"]), ("gap compact", gapc), ("gap full", gapf)):
    if subprocess.run(["xmllint", "--noout", "-"], input=t.encode(), capture_output=True).returncode == 0: ok(f"(D) {k}: well formed")
    else: no(f"(D) {k}: xmllint rejects it")
if run(["--for=" + GAP]) == A["gap"]: ok("(D) two ON runs byte-identical")
else: no("(D) two ON runs differ")
# M
if not grounded(O["gap"], compact=True) and not grounded(gapf_off): ok("(M) mutation: G1's detector fails on the OFF GAP page")
else: no("(M) G1's detector passed the OFF GAP page")
if not absent(A["gap"]): ok("(M) mutation: G2's detector fails on the ON GAP page")
else: no("(M) G2's detector passed the ON GAP page")
print("routingcheck: " + ("PASS" if fail == 0 else "FAIL"))
sys.exit(fail)
PY

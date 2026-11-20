#!/usr/bin/env bash
# packlocatecheck.sh — PB1 (PT1 design D1): --pack-task names the files --for page 1 names.
#
# THE DEFECT (PT1_PACKTASK_1119 READOUT §1): --pack-task called --for's ranker but showed a fixed 12-row window in
# raw score order and had no file-grain tail, so a needed file ranked 13-40, or ranked only at file grain, was
# never named — 56 of the 165 gold files on SUB1's 52 tasks. The budget cut no ranking row in any of them.
# D1 takes the locating surface from --for: its 40-row head (round robin by file included) and its <tail>,
# the tail filled LAST, cut at a row boundary to the bundle's one ceiling, and the cut disclosed.
#
# Arms, on a 300-file fixture whose task words spread over every file with falling frequency:
#   (1) the file --for ranks at r=25 is named by --pack-task            (red on the 12-row window)
#   (2) the first and the tenth file of --for's <tail> are named        (red: pack had no tail)
#   (3) the first 40 <sigs> rows (r, name, path) equal --for's first 40 (red: 12 rows, raw score order)
#   (4) the tail is cut (the fixture's tail cannot fit): <tail capped="1" next=…> on the pack answer
#   (5) the answer stays under the default ceiling (declaredByteCeiling(6000) = 14160 B) with no over_ceiling
#   (6) well-formed, deterministic (two runs byte-identical)
#
# Usage: test/packlocatecheck.sh [BIN]   (default build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
# The house ok()/no() pair (every other gate spells it this way, and test/gateexitcheck.sh G1/G2 pin it):
# a FAILED WRITE of the PASS line must set the accumulator, or a full disk turns a red arm green, and ok()
# must return 0, so a verdict chain cannot report an ARM as failed because the write did. Verdicts in this
# gate are if/else and never the one-line `cond AND-ok OR-no` shape, which gateexitcheck G2 forbids outright.
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "packlocatecheck: BIN=$BIN"

FX="$TMP/loc"; mkdir -p "$FX/pkg"
python3 - "$FX/pkg" <<'EOF'
import sys
out = sys.argv[1]
for k in range(300):
    words = " ".join(["ledger reconcile drift"] * max(1, 30 - k // 10))
    with open(f"{out}/mod{k:03d}.py", "w") as f:
        f.write(f'def reconcile_ledger_{k:03d}(rows):\n    """{words}"""\n    return helper_{k:03d}(rows)\n\n')
        f.write(f'def helper_{k:03d}(rows):\n    """plain helper number {k}"""\n    return len(rows) + {k}\n')
EOF

TASK="ledger reconcile drift"
"$BIN" "$FX" --for="$TASK"       > "$TMP/for.xml"   2>/dev/null || { no "--for exited non-zero"; }
"$BIN" "$FX" --pack-task="$TASK" > "$TMP/pack.xml"  2>/dev/null || { no "--pack-task exited non-zero"; }
"$BIN" "$FX" --pack-task="$TASK" > "$TMP/pack2.xml" 2>/dev/null

python3 - "$TMP/for.xml" "$TMP/pack.xml" <<'EOF' > "$TMP/verdict.txt"
import sys, xml.etree.ElementTree as ET
fr = ET.parse(sys.argv[1]).getroot()
pk = ET.parse(sys.argv[2]).getroot()
def rows(root):
    s = root.find('sigs')
    out = []
    if s is None:
        return out
    for c in s:
        if c.get('r') is None:
            continue
        out.append((int(c.get('r')), c.get('n') or c.get('sym') or '', (c.get('p') or '').split(':')[0]))
    return sorted(out)
def named(root):
    ps = set()
    for e in root.iter():
        p = e.get('p')
        if p:
            ps.add(p.split(':')[0])
    return ps
fs, ps_ = rows(fr), rows(pk)
r25 = [p for (r, n, p) in fs if r == 25]
ftail = fr.find('tail')
trows = [t.get('p') for t in ftail] if ftail is not None else []
pn = named(pk)
print('R25', r25[0] if r25 else '', 'named' if r25 and r25[0] in pn else 'missing')
print('TAIL1', trows[0] if trows else '', 'named' if trows and trows[0] in pn else 'missing')
print('TAIL10', trows[9] if len(trows) > 9 else '', 'named' if len(trows) > 9 and trows[9] in pn else 'missing')
print('HEAD40', 'equal' if len(fs) >= 40 and fs[:40] == ps_[:40] else 'differ for=%d pack=%d' % (len(fs), len(ps_)))
pt = pk.find('tail')
print('TAILCUT', 'yes' if pt is not None and pt.get('capped') == '1' and (pt.get('next') or '') != '' else 'no')
print('OVER', pk.get('over_ceiling') or '0')
EOF
cat "$TMP/verdict.txt" | sed 's/^/        /'
if grep -q '^R25 .* named$'    "$TMP/verdict.txt"; then
    ok "(1) --for's r=25 file is named"
else
    no "(1) --for's r=25 file is not named by --pack-task"
fi
if grep -q '^TAIL1 .* named$'  "$TMP/verdict.txt"; then
    ok "(2a) --for's first tail file is named"
else
    no "(2a) --for's first tail file is not named"
fi
if grep -q '^TAIL10 .* named$' "$TMP/verdict.txt"; then
    ok "(2b) --for's tenth tail file is named"
else
    no "(2b) --for's tenth tail file is not named"
fi
if grep -q '^HEAD40 equal$'    "$TMP/verdict.txt"; then
    ok "(3) the first 40 ranking rows equal --for's"
else
    no "(3) the first 40 ranking rows differ from --for's"
fi
if grep -q '^TAILCUT yes$'     "$TMP/verdict.txt"; then
    ok "(4) the cut tail says capped=\"1\" and carries next="
else
    no "(4) no disclosed tail cut"
fi
bytes=$( wc -c < "$TMP/pack.xml" | tr -d ' ' )
if [ "$bytes" -le 14160 ] && grep -q '^OVER 0$' "$TMP/verdict.txt"; then ok "(5) $bytes B <= 14160 B ceiling, no over_ceiling"; else no "(5) $bytes B against the 14160 B ceiling (or over_ceiling set)"; fi
if xmllint --noout "$TMP/pack.xml" 2>/dev/null && cmp -s "$TMP/pack.xml" "$TMP/pack2.xml"; then
    ok "(6) well-formed and deterministic"
else
    no "(6) malformed or non-deterministic"
fi

[ $fail -eq 0 ] && { echo "packlocatecheck: PASS"; exit 0; }
echo "packlocatecheck: FAIL"; exit 1

#!/usr/bin/env bash
# packkeybodycheck.sh — PB1 (PT1 design D1): --pack-task serves ONE body, the key one; every other body candidate
# is a pointer the reader can follow.
#
# THE MEASUREMENT (PT1_PACKTASK_1119 READOUT §2): on SUB1's 52 tasks body 1's file was a changed file in 28/52, body 2's
# in 20/45, bodies 3-6 in 26/117 — the five lesser bodies took 35% of the answer's bytes for a 22% hit rate, and the
# bytes they cost are the ones the file tail needs. D1 keeps the key body (KB1's choice: the symbol the question
# names in backticks, else the top positive-score head) and turns each dropped candidate into a bodyless
# <b … next="--expand=…"/> pointer, counted in the section's total= and in the ledger.
#
# Arms:
#   (1) exactly one <b> in <bodies> carries a body (CDATA text)                     (red: four bodies today)
#   (2) a task naming `round_invoice_tax` in backticks serves THAT body (KB1's rule), not the rank-1 head
#   (3) every other candidate is a self-closed <bn> with next="--expand=…"; the ledger counts them and capped="0":
#       they are a DESIGN choice, not a budget cut, and the truncation vocabulary reads capped= against shown=/total=
#   (4) the ledger reads "bodies: kept 1 of 1, N as next="
#   (5) a task naming no symbol serves the r=1 ranking row's body
#   (6) the callers section lists callers of the key body only (rel="caller"; no callee rows)
#
# Usage: test/packkeybodycheck.sh [BIN]   (default build/ripwire)
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
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "packkeybodycheck: BIN=$BIN"

FX="$TMP/kb"; mkdir -p "$FX/billing"
python3 - "$FX/billing" <<'EOF'
import sys
out = sys.argv[1]
names = ["compute_invoice_tax", "invoice_tax_table", "invoice_tax_rate", "apply_invoice_tax", "round_invoice_tax",
         "invoice_tax_report", "invoice_tax_audit"]
for i, n in enumerate(names):
    reps = 8 - i
    words = " ".join(["invoice tax rounding"] * reps)
    with open(f"{out}/{n}.py", "w") as f:
        f.write(f'def {n}(amount):\n    """{words}"""\n    total = scale_amount(amount) * 0.2\n    total = total + {i}\n    return total\n\n')
        f.write(f'def caller_of_{n}(x):\n    """uses it"""\n    return {n}(x)\n')
with open(f"{out}/scale.py", "w") as f:
    f.write('def scale_amount(a):\n    """scales"""\n    return a * 100\n')
EOF

verdict(){   # $1 = pack xml, $2 = expected key body name ("" = the r=1 row's name)
python3 - "$1" "$2" <<'EOF'
import sys, re, xml.etree.ElementTree as ET
raw = open(sys.argv[1], encoding='utf-8').read()
root = ET.fromstring(raw)
want = sys.argv[2]
if not want:
    s = root.find('sigs')
    r1 = [c for c in s if c.get('r') == '1'] if s is not None else []
    want = (r1[0].get('n') or '') if r1 else ''
b = root.find('bodies')
full = [e for e in (b if b is not None else []) if e.tag == 'b']
ptrs = [e for e in (b if b is not None else []) if e.tag == 'bn']
print('FULL', len(full))
print('KEY', full[0].get('n') if full else '', 'want', want, 'ok' if full and full[0].get('n') == want else 'bad')
nexts = all((p.get('next') or '').startswith('--expand=') for p in ptrs)
tot = int(b.get('total') or 0) if b is not None else 0
print('PTRS', len(ptrs), 'next' if nexts and ptrs else 'nonext', 'total', tot, 'capped', b.get('capped') if b is not None else '')
print('PTROK', 'yes' if ptrs and nexts and tot == len(full) and b.get('capped') == '0' else 'no')
m = re.search(r'bodies: kept 1 of (\d+)[^|]*?(\d+) as next=', raw)
print('LEDGER', 'yes' if m and int(m.group(1)) == tot and int(m.group(2)) == len(ptrs) else 'no')
c = root.find('callers')
rels = set(e.get('rel') for e in (c if c is not None else []))
print('CALLERS', 'callers-only' if c is not None and rels == {'caller'} else 'other:' + ','.join(sorted(r or '' for r in rels)))
EOF
}

"$BIN" "$FX" --pack-task='fix `round_invoice_tax` invoice tax rounding' > "$TMP/named.xml" 2>/dev/null || no "--pack-task (named) exited non-zero"
"$BIN" "$FX" --pack-task='invoice tax rounding'                         > "$TMP/plain.xml" 2>/dev/null || no "--pack-task (plain) exited non-zero"
verdict "$TMP/named.xml" round_invoice_tax > "$TMP/v1.txt"
verdict "$TMP/plain.xml" ""                 > "$TMP/v2.txt"
sed 's/^/        named: /' "$TMP/v1.txt"; sed 's/^/        plain: /' "$TMP/v2.txt"

if grep -q '^FULL 1$'   "$TMP/v1.txt" && grep -q '^FULL 1$' "$TMP/v2.txt"; then
    ok "(1) exactly one body served"
else
    no "(1) not exactly one body served"
fi
if grep -q '^KEY .* ok$' "$TMP/v1.txt"; then
    ok "(2) the backtick-named symbol's body is the key body"
else
    no "(2) the key body is not the backtick-named symbol"
fi
if grep -q '^PTROK yes$' "$TMP/v1.txt" && grep -q '^PTROK yes$' "$TMP/v2.txt"; then
    ok "(3) every candidate not served is a <bn next=--expand=…/> pointer; total= counts served bodies and capped=\"0\" (no budget cut)"
else
    no "(3) candidates not served lack <bn next=--expand> pointers, or total=/capped= disagree"
fi
if grep -q '^LEDGER yes$' "$TMP/v1.txt"; then
    ok "(4) the ledger counts the kept body and the pointers"
else
    no "(4) the ledger does not count the pointers"
fi
if grep -q '^KEY .* ok$' "$TMP/v2.txt"; then
    ok "(5) no named symbol: the r=1 row's body"
else
    no "(5) no named symbol: the key body is not the r=1 row"
fi
if grep -q '^CALLERS callers-only$' "$TMP/v1.txt"; then
    ok "(6) <callers> holds the key body's callers only"
else
    no "(6) <callers> is not the key body's callers only"
fi

[ $fail -eq 0 ] && { echo "packkeybodycheck: PASS"; exit 0; }
echo "packkeybodycheck: FAIL"; exit 1

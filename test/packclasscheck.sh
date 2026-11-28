#!/usr/bin/env bash
# packclasscheck.sh — PACK-TASK-BY-CLASS (VERB-AUDIT-2, 11-27): --pack-task sized by question class (src/packtask.h
# packTaskClassOf / packTaskFoldHead / packTaskPathOnlyTail).
#
# THE MEASUREMENT (DEV only, tmp/orch-1127/pack-task-class): pack-task served 12.2-12.5 KB on every question, its budget binding
# in 8/8 audit cells. Step 1 folds <sigs> rows past rank 12 into one <t p= sym= r=/> per file not named above (0 of 104 DEV items
# lost; a plain cut lost 1). Step 2 serves a one-name question (where / what / who calls) its ranking and tail as path rows under
# a short class legend (12.2 -> ~5 KB, 93 of 93 DEV items). Neither step re-spends a byte: every row is one the full bundle cut.
#
# Arms (each counts what it saw and FAILS on zero cases):
#   (A) fold disclosure: a conceptual task whose head has > 12 rows prints 12 <d> rows, fold=N on <sigs> (N = the full head's
#       rows past 12), next= the --for call, and every file the full head names is still named in <sigs>
#   (B) equivalence twin vs RIPWIRE_PACK_CLASS=0: the 12 kept rows are the full head's first 12 byte for byte; on the conceptual
#       task bodies/callers/tests are OFF's and the tail is OFF's rows then more of the same order (the fold's bytes, re-spent);
#       on a several-names task (a full bundle) everything outside <sigs> is OFF's byte for byte
#   (C) name class: `where is \`NAME\` defined and who calls it` — ledger class=name; bodies, callers and tests byte-identical
#       to OFF; the tail lists the same files in the same order with no sym=/tsym= (p_only= = shown=); every file OFF's <sigs>
#       names is named in ON's; the <d> rows are pointer rows
#   (D) tight-size arm: the name-class answer is at most 85 % of the OFF answer's bytes on this fixture (its whole tail fits; DEV: ~42 %), and an explicit
#       other --token-budget (12000: the escape hatch the class legend names) is the full bundle again (no class=name, no fold=);
#       an explicit --token-budget=6000 IS the default (forsoftbudgetcheck P2): byte-identical to no budget
#   (E) the classes that keep the full bundle: two names, a long question, a path question, --json (ON == OFF byte for byte)
#   (F) the off switch: RIPWIRE_PACK_CLASS=0 prints no fold=, no class=, and the head past 12 rows
#   (W) every XML answer above is well-formed (the class's legend and ledger clauses ride comments: no "--")
#
# Usage: test/packclasscheck.sh [BIN]   (default build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
unset RIPWIRE_PACK_CLASS

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "packclasscheck: BIN=$BIN"

# A fixture whose conceptual head is long (30 files, each two functions on the task's words) and whose named symbol has callers
# in four other files and a test.
FX="$TMP/fx"; mkdir -p "$FX/ledger" "$FX/tests"
python3 - "$FX" <<'EOF'
import sys
root = sys.argv[1]
for i in range(30):
    reps = 1 + (i % 7)
    words = " ".join(["ledger balance reconcile"] * reps)
    with open(f"{root}/ledger/part_{i:02d}.py", "w") as f:
        f.write(f'def reconcile_part_{i:02d}(rows):\n    """{words}"""\n    return settle_ledger_balance(rows) + {i}\n\n')
        f.write(f'def balance_part_{i:02d}(rows):\n    """balance {words}"""\n    return len(rows) * {i}\n')
with open(f"{root}/ledger/settle.py", "w") as f:
    f.write('def settle_ledger_balance(rows):\n    """settle the ledger balance of rows"""\n    total = 0\n    for r in rows:\n        total += r\n    return total\n')
with open(f"{root}/tests/test_settle.py", "w") as f:
    f.write('from ledger.settle import settle_ledger_balance\n\ndef test_settle():\n    assert settle_ledger_balance([1, 2]) == 3\n')
EOF

run(){   # $1 = out file, $2 = RIPWIRE_PACK_CLASS value ("" = unset), rest = args
    local out="$1" v="$2"; shift 2
    if [ -n "$v" ]; then RIPWIRE_PACK_CLASS="$v" "$BIN" "$FX" "$@" > "$out" 2>/dev/null; else "$BIN" "$FX" "$@" > "$out" 2>/dev/null; fi
}
CONC='how is the ledger balance reconciled across parts'
NAME='where is `settle_ledger_balance` defined and who calls it'
run "$TMP/conc_on.xml"  ""  --pack-task="$CONC"  || no "--pack-task (conceptual, on) exited non-zero"
run "$TMP/conc_off.xml" "0" --pack-task="$CONC"  || no "--pack-task (conceptual, off) exited non-zero"
run "$TMP/name_on.xml"  ""  --pack-task="$NAME"  || no "--pack-task (name, on) exited non-zero"
run "$TMP/name_off.xml" "0" --pack-task="$NAME"  || no "--pack-task (name, off) exited non-zero"
run "$TMP/name_tb.xml"  ""  --pack-task="$NAME" --token-budget=12000 || no "--pack-task (name, --token-budget=12000) exited non-zero"
run "$TMP/name_6k.xml"  ""  --pack-task="$NAME" --token-budget=6000 || no "--pack-task (name, --token-budget=6000) exited non-zero"
TWO='where are `settle_ledger_balance` and `reconcile_part_03` defined'
run "$TMP/two_on.xml"   ""  --pack-task="$TWO" || no "two names (on) exited non-zero"
run "$TMP/two_off.xml"  "0" --pack-task="$TWO" || no "two names (off) exited non-zero"
run "$TMP/long_on.xml"  ""  --pack-task='where is `settle_ledger_balance` defined and who calls it from the reconcile parts of the ledger' || no "long (on) exited non-zero"
run "$TMP/path_on.xml"  ""  --pack-task='trace the call path from `reconcile_part_03` to `settle_ledger_balance`' || no "path (on) exited non-zero"
run "$TMP/json_on.json"  ""  --pack-task="$NAME" --json || no "--json (on) exited non-zero"
run "$TMP/json_off.json" "0" --pack-task="$NAME" --json || no "--json (off) exited non-zero"

python3 - "$TMP" <<'EOF' > "$TMP/verdict.txt"
import os, re, sys
T = sys.argv[1]
rd = lambda n: open(os.path.join(T, n), encoding='utf-8').read()
def sec(doc, tag):
    m = re.search(r'<' + tag + r'(?: [^>]*)?>.*?</' + tag + '>', re.sub(r'<!--.*?-->', '', doc, flags=re.S), re.S)
    return m.group(0) if m else ''
def sigs_rows(doc):
    s = sec(doc, 'sigs'); body = s[s.find('>') + 1:-len('</sigs>')] if s else ''
    return re.findall(r'<d [^>]*/>|<d [^>]*>.*?</d>|<t [^>]*/>', body, re.S), (s[:s.find('>') + 1] if s else '')
files = lambda rows: [re.search(r' p="([^"]*)"', r).group(1) for r in rows if re.search(r' p="([^"]*)"', r)]
con, coff, non, noff = rd('conc_on.xml'), rd('conc_off.xml'), rd('name_on.xml'), rd('name_off.xml')
# (A)
on_rows, on_tag = sigs_rows(con); off_rows, off_tag = sigs_rows(coff)
d_on = [r for r in on_rows if r.startswith('<d')]
fold = re.search(r' fold="(\d+)"', on_tag)
print('A-premise', len(off_rows))
print('A', 'ok' if len(off_rows) > 12 and len(d_on) == 12 and fold and int(fold.group(1)) == len(off_rows) - 12
      and 'next="--for=' in on_tag and set(files(off_rows)) <= set(files(on_rows)) else 'bad',
      len(d_on), fold.group(1) if fold else None, sorted(set(files(off_rows)) - set(files(on_rows)))[:3])
# (B) the conceptual class hands the tail what the fold freed: its rows are OFF's rows then more of the same order; the
#     several-names class (a full bundle) re-spends nothing: everything but <sigs> is OFF's byte for byte
tw, twoff = rd('two_on.xml'), rd('two_off.xml')
t_on, t_off = re.findall(r'<t p="[^"]*"[^>]*/>', sec(con, 'tail')), re.findall(r'<t p="[^"]*"[^>]*/>', sec(coff, 'tail'))
same = all(sec(con, t) == sec(coff, t) for t in ('bodies', 'callers', 'tests')) and t_on[:len(t_off)] == t_off and len(t_on) >= len(t_off)
same2 = all(sec(tw, t) == sec(twoff, t) for t in ('bodies', 'callers', 'tests', 'tail')) and ' fold="' in tw
w_on, _ = sigs_rows(tw); w_off, _ = sigs_rows(twoff)
print('B-premise', len(t_off) * len(w_off))
print('B', 'ok' if same and same2 and on_rows[:12] == off_rows[:12] and w_on[:12] == w_off[:12] else 'bad', same, same2, len(t_on), len(t_off))
# (C)
cls = 'class=name' in non
same_c = all(sec(non, t) == sec(noff, t) for t in ('bodies', 'callers', 'tests'))
tl_on, tl_off = sec(non, 'tail'), sec(noff, 'tail')
tf_on, tf_off = re.findall(r'<t p="([^"]*)"', tl_on), re.findall(r'<t p="([^"]*)"', tl_off)
shown = re.search(r' shown="(\d+)"', tl_on); ponly = re.search(r' p_only="(\d+)"', tl_on)
nrows, _ = sigs_rows(non); orows, _ = sigs_rows(noff)
ptr = all(r.endswith('/>') and '<doc>' not in r for r in nrows)
print('C-premise', len(tf_off), len(orows))
print('C', 'ok' if cls and same_c and tf_on == tf_off and ' sym="' not in tl_on and ' tsym="' not in tl_on
      and (not tf_on or (shown and ponly and shown.group(1) == ponly.group(1))) and set(files(orows)) <= set(files(nrows)) and ptr else 'bad',
      cls, same_c, tf_on == tf_off, ptr)
# (D)
print('D-premise', len(noff.encode()))
print('D', 'ok' if len(non.encode()) <= 0.85 * len(noff.encode()) and 'class=name' not in rd('name_tb.xml') and ' fold="' not in rd('name_tb.xml')
      and rd('name_6k.xml') == non else 'bad', len(non.encode()), len(noff.encode()))
# (E)
neg = [('two', rd('two_on.xml')), ('long', rd('long_on.xml')), ('path', rd('path_on.xml'))]
print('E-premise', sum(1 for _, d in neg if d.startswith('<ctx')))
print('E', 'ok' if all('class=name' not in d for _, d in neg) and rd('json_on.json') == rd('json_off.json') else 'bad',
      [n for n, d in neg if 'class=name' in d])
# (W) every XML answer parses (a legend or ledger clause rides a comment, where "--" is not allowed)
import xml.etree.ElementTree as ET
xs = sorted(n for n in os.listdir(T) if n.endswith('.xml'))
bad = []
for n in xs:
    try: ET.fromstring(rd(n))
    except ET.ParseError as e: bad.append(n + ': ' + str(e))
print('W-premise', len(xs))
print('W', 'ok' if not bad else 'bad', bad[:2])
# (F)
print('F-premise', len(off_rows))
print('F', 'ok' if ' fold="' not in coff and 'class=name' not in noff and len(off_rows) > 12 else 'bad')
EOF
sed 's/^/        /' "$TMP/verdict.txt"
for arm in A B C D E F W; do
    prem="$( grep "^$arm-premise " "$TMP/verdict.txt" | awk '{print $2}' )"
    if [ -z "$prem" ] || [ "$prem" = "0" ]; then
        no "($arm) premise: saw zero cases (a vacuous arm is a red arm)"
    elif grep -q "^$arm ok" "$TMP/verdict.txt"; then
        case $arm in
            A) ok "(A) the head folds past 12 rows: fold= counts them, next= is the --for call, no file the full head names is lost" ;;
            B) ok "(B) equivalence twin: 12 rows = OFF first 12; conceptual tail = OFF rows + more; full-bundle class = OFF outside <sigs>" ;;
            C) ok "(C) name class: class=name, bodies/callers/tests as OFF, the same tail files p= only, every head file named" ;;
            D) ok "(D) tight size: name class <= 85 % of OFF bytes; --token-budget=12000 is the full bundle; an explicit 6000 is the default" ;;
            E) ok "(E) two names / long / path questions keep the full bundle; --json ON == OFF" ;;
            F) ok "(F) RIPWIRE_PACK_CLASS=0: no fold=, no class=, the head past 12 rows" ;;
            W) ok "(W) every XML answer is well-formed" ;;
        esac
    else
        no "($arm) $( grep "^$arm " "$TMP/verdict.txt" )"
    fi
done

[ $fail -eq 0 ] && { echo "packclasscheck: PASS"; exit 0; }
echo "packclasscheck: FAIL"; exit 1

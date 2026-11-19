#!/usr/bin/env bash
# forsigxcheck.sh — SIGX (src/forsigx.h; lane TL1 M1, AF3's frozen C2(10)): on the unbudgeted answer-first --for answer, every
# direct-child <d> row of <sigs> with r above 10 keeps l= n= p= r= on the page, and its other attributes and its text ride after the
# rows, verbatim, in ONE <sigx> block as <x r="R" …>text</x>.
#
# The contract is LOSSLESS: put every <x>'s attributes and text back on its <d r=R>, delete the block and its legend, and the answer
# is the RIPWIRE_NO_SIGX=1 twin byte for byte (est_tokens= aside, re-priced over the added bytes).
# ARMS
#   (S0)  presence: the answer carries <sigx>, the twin does not, and the twin has a <d> row with r > 10 (else every arm is vacuous)
#   (S1)  rebuild: the moved bytes put back reproduce the twin byte for byte (est_tokens= masked)
#   (S1n) the rebuild CAN fail: drop one moved attribute and S1's comparison differs
#   (S2)  every <d> with r > 10 in <sigs> is self-closing and carries only l n p r
#   (S3)  every <d> with r <= 10 is byte-identical to the twin's
#   (S4)  one <x> per row that had something to move, in sigs order; <sigx> follows the last row block, its legend comment right
#         before it, and only comments after it
#   (S5)  well formed (xmllint) and deterministic (two runs byte-identical)
#   (S6)  not applied: --legend=first, --signatures-only and a budget that sheds (--token-budget=4000) are byte-identical with and
#         without the knob; (S6b) a budget the compacted answer fits returns it byte for byte (TOKEN-BUDGET-MONOTONE rule 4)
#   (S7)  est_tokens= rises by the added bytes at the emitter's markup rate (the render's ledger, serialize.h repriceRootAfterCut)
#   (S8)  the default PAGE 1 carries the short rows: its first r > 10 <d> is self-closing with l n p r only
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-${1:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "forsigxcheck: python3 required"; exit 2; }
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "forsigxcheck: BIN=$BIN"
cd "$ROOT" || exit 2
unset RIPWIRE_NO_SIGX
TASK="rank symbols by pagerank and serialize the map"
rw(){ "$BIN" src --no-cache --for="$TASK" "$@" 2>/dev/null; }
rw --page-bytes=0                          >"$WORK/on.xml"
RIPWIRE_NO_SIGX=1 rw --page-bytes=0        >"$WORK/off.xml"
rw --page-bytes=0                          >"$WORK/on2.xml"
rw                                         >"$WORK/page1.xml"
for arm in "--legend=first" "--signatures-only" "--token-budget=4000"; do
    tag="$( printf '%s' "$arm" | tr -c 'a-z0-9' '_' )"
    rw $arm >"$WORK/n_$tag.on"; RIPWIRE_NO_SIGX=1 rw $arm >"$WORK/n_$tag.off"
    if [ -s "$WORK/n_$tag.on" ] && cmp -s "$WORK/n_$tag.on" "$WORK/n_$tag.off" && ! grep -q '<sigx>' "$WORK/n_$tag.on"; then
        ok "(S6) $arm: byte-identical with and without RIPWIRE_NO_SIGX, no <sigx>"
    else no "(S6) $arm: the answer changed with the knob or carries <sigx>"; fi
done
# (S6b) TOKEN-BUDGET-MONOTONE rule 4: a budget the (compacted) answer fits returns it byte for byte, <sigx> included
rw --token-budget=100000 >"$WORK/b_big.xml"
if grep -q '<sigx>' "$WORK/b_big.xml" && cmp -s "$WORK/b_big.xml" "$WORK/on.xml"; then ok "(S6b) --token-budget=100000 returns the --page-bytes=0 answer byte for byte, <sigx> included"
else no "(S6b) a budget the answer fits does not return it byte for byte"; fi
if xmllint --noout "$WORK/on.xml" 2>/dev/null; then ok "(S5) well formed"; else no "(S5) xmllint rejects the answer"; fi
if cmp -s "$WORK/on.xml" "$WORK/on2.xml"; then ok "(S5) two runs byte-identical"; else no "(S5) two runs differ"; fi
python3 - "$WORK" <<'PY'
import re, sys, os, math
W = sys.argv[1]; bad = 0
def rd(n): return open(os.path.join(W, n), "rb").read().decode("latin-1")
def say(ok, msg):
    global bad
    print("  %s  %s" % ("PASS" if ok else "FAIL", msg)); bad += 0 if ok else 1
ATTR = re.compile(r' ([A-Za-z_][\w-]*)="([^"]*)"')
on, off, p1 = rd("on.xml"), rd("off.xml"), rd("page1.xml")
def sigs(d):
    i = d.find("<sigs"); return d[i:d.find("</sigs>", i) + 7]
def drows(s):
    """direct-child <d> rows of a <sigs> block: self-closing or with text up to the matching </d>"""
    out = []; i = s.find(">") + 1
    for m in re.finditer(r"<d [^>]*?/>|<d [^>]*>.*?</d>", s[i:], re.S): out.append(m.group(0))
    return out
def rank(row):
    m = re.search(r' r="(\d+)"', row[:row.find(">") + 1]); return int(m.group(1)) if m else 0
mask = lambda d: re.sub(r' est_tokens="\d+"', ' est_tokens="#"', d, count=1)
on_rows, off_rows = drows(sigs(on)), drows(sigs(off))
say("<sigx>" in on and "<sigx>" not in off and any(rank(r) > 10 for r in off_rows),
    "(S0) the answer carries <sigx>, the twin does not, and the twin has %d sigs rows with r > 10" % sum(rank(r) > 10 for r in off_rows))
xs = re.findall(r'<x r="(\d+)"([^>]*?)(/>|>(.*?)</x>)', on[on.find("<sigx>"):on.find("</sigx>")], re.S)
def merged(kept, moved, text, twin_row):
    names = [k for k, _ in ATTR.findall(twin_row[:twin_row.find(">") + 1])]
    av = dict(ATTR.findall(kept)); av.update(ATTR.findall(moved))
    if sorted(av) != sorted(names): return None
    head = "<d" + "".join(' %s="%s"' % (k, av[k]) for k in names)
    return head + ("/>" if twin_row.endswith("/>") and not text else ">" + text + "</d>")
def rebuild_doc(xs):
    twin_by_r = {rank(r): r for r in off_rows}
    s = sigs(on); out = s
    for r, attrs, tail, text in xs:
        m = re.search(r'<d [^>]*? r="%s"[^>]*?/>' % r, out)
        if not m or int(r) not in twin_by_r: return None
        row = merged(m.group(0)[2:-2], attrs, text if tail != "/>" else "", twin_by_r[int(r)])
        if row is None: return None
        out = out[:m.start()] + row + out[m.end():]
    a = on.find("<!-- sigx:"); b = on.find("</sigx>") + len("</sigx>")
    return (on[:a] + on[b:]).replace(s, out, 1)
rb = rebuild_doc(xs)
say(rb is not None and mask(rb) == mask(off), "(S1) %d <x> rows put back on their <d r=R> rebuild the RIPWIRE_NO_SIGX=1 twin byte for byte (est_tokens= masked)" % len(xs))
xs_bad = list(xs)
for i, (r, attrs, tail, text) in enumerate(xs_bad):
    if ATTR.search(attrs):
        m = ATTR.search(attrs); xs_bad[i] = (r, attrs[:m.start()] + attrs[m.end():], tail, text); break
rbn = rebuild_doc(xs_bad)
say(rbn is None or mask(rbn) != mask(off), "(S1n) dropping one moved attribute breaks the rebuild -- S1 can fail")
bad2 = [r for r in on_rows if rank(r) > 10 and (not r.endswith("/>") or sorted(k for k, _ in ATTR.findall(r)) != sorted(set(k for k, _ in ATTR.findall(r)) & {"l", "n", "p", "r"}))]
say(not bad2 and any(rank(r) > 10 for r in on_rows), "(S2) every <d> with r > 10 is self-closing with l n p r only (%d rows; offenders %d)" % (sum(rank(r) > 10 for r in on_rows), len(bad2)))
say([r for r in on_rows if 0 < rank(r) <= 10] == [r for r in off_rows if 0 < rank(r) <= 10], "(S3) the <d> rows with r <= 10 are byte-identical to the twin's")
moved = [rank(r) for r in off_rows if rank(r) > 10 and (r.endswith("</d>") or set(k for k, _ in ATTR.findall(r)) - {"l", "n", "p", "r"})]
xi = on.find("<sigx>"); after = on[on.find("</sigx>") + 7:on.rfind("</ctx>")]
say([int(x[0]) for x in xs] == moved, "(S4) one <x> per row that had something to move, in sigs order (%d)" % len(moved))
say(on[:xi].endswith("-->") and on.rfind("<!-- sigx:", 0, xi) > on.rfind("</tail>") and re.fullmatch(r"(?:<!--.*?-->)*", after, re.S) is not None,
    "(S4) <sigx> follows the rows (after </tail>), its legend comment directly before it, only comments after it")
est = lambda d: int(re.search(r' est_tokens="(\d+)"', d[:d.find(">")]).group(1))
added = len(on) - len(off)
say(est(on) > est(off) and abs(est(on) - est(off) - round(added / 2.50)) <= 1,
    "(S7) est_tokens %d -> %d for %d added markup bytes (the emitter's own markup rate: %d / 2.50 = %d, +-1 for the fixpoint's rounding)" % (est(off), est(on), added, added, round(added / 2.50)))
p1rows = [r for r in drows(sigs(p1) if "</sigs>" in p1 else p1[p1.find("<sigs"):]) if rank(r) > 10]
say(bool(p1rows) and p1rows[0].endswith("/>") and set(k for k, _ in ATTR.findall(p1rows[0])) <= {"l", "n", "p", "r"},
    "(S8) the default page 1's first r > 10 <d> row is the short form: %s" % (p1rows[0][:120] if p1rows else "none"))
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] || fail=1
if [ "$fail" -ne 0 ]; then echo "forsigxcheck: FAILURES"; exit 1; fi
echo "forsigxcheck: ALL PASS"

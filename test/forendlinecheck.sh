#!/usr/bin/env bash
# forendlinecheck.sh — END LINES ON THE SHORT ROWS (lane ER1; src/forsigx.h kSigxKeptAttrs): every `--for` sigs row that prints a
# start line l= also prints its end line e= when the extent is known, in BOTH row forms — the element form (<d l= e= n= p= r=/>) and
# the line form (P:L-E N) — so a reader can range-read the span from page 1 without a second call.
#
# "Known" is not this gate's opinion: the oracle is the RIPWIRE_NO_SIGX=1 twin of the same binary, whose rows carry e= by serialize.h's
# rule (defEndLine: a code definition with a trusted span). A row whose twin has no e= (a markdown heading, a config key) must have
# none here either: the absence is pinned too, never a silent pass.
# ARMS — each says which proof it carries (a NEW arm is red on a binary whose short rows keep l n p r only; an UNCHANGED invariant
# carries a mutation negative control instead, because the old binary satisfies it by construction)
#   (E0)  presence: on the fixture and on this repo's src/, the twin has at least 4 <d> rows with r > 10 that carry e=, the answer
#         carries <sigx>, and the fixture's twin has a row with l= and no e= (else the arms below are vacuous)
#   (E1)  NEW. element form: every <d> row of <sigs> carries e= IF AND ONLY IF the twin's row of the same rank does, with the same
#         value — the whole answer and page 1, both trees
#   (E1n) MUTATION NEGATIVE CONTROL: the same predicate FAILS on the answer with one short row's e= removed (the removal is asserted)
#   (E2)  NEW. line form: read with test/rowlines.py's own grammar, every definition line spells -E IF AND ONLY IF the twin's row of
#         that rank carries e=; at least 4 lines with r > 10 do
#   (E3)  UNCHANGED invariant. lossless: rowlines.decode(answer) == the RIPWIRE_NO_ROWLINES=1 twin byte for byte (whole, page 1,
#         page 2, fixture) — e= round-trips through the decoder
#   (E3n) MUTATION NEGATIVE CONTROL: the same comparison FAILS when one r > 10 line's -E is dropped (the drop is asserted)
#   (E4)  NEW (known-count arm). on the fixture every code row's l= and e= are the generator's own first and last line, for r <= 10
#         and r > 10 alike (at least 4 of the latter), and the markdown heading row has l= and NO e= in both forms
#   (E5)  NEW. e= is said once: no <x> of <sigx> carries e= (it stayed on its row), and putting each <x> back on its row rebuilds a
#         row whose attribute NAMES are the twin's
#   (E6)  well formed (xmllint) and no newline outside CDATA (G4), on every answer above
#   (E7)  deterministic: two runs byte-identical, both forms
#   (E8)  NEW. legend: the sigx legend names e= among the attributes a short row keeps; an element-form page 1 whose rows carry e=
#         defines it (the "d e=" clause), and a line-form page 1 carries the lines clause that spells P:L-E
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-${1:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "forendlinecheck: python3 required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "forendlinecheck: xmllint required"; exit 2; }
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "forendlinecheck: BIN=$BIN"
cd "$ROOT" || exit 2
unset RIPWIRE_NO_ROWLINES RIPWIRE_NO_SIGX RIPWIRE_FOR_ENDLINES

# the fixture: 16 files, one function each (same-file siblings would be demoted to <t> pointers, which carry no line at all), every
# first and last line known by construction, and one markdown heading (a row with l= whose extent is NOT known)
mkdir -p "$WORK/fx"
python3 - "$WORK/fx" <<'PY'
import json, os, sys
d = sys.argv[1]; truth = {}
for i, n in enumerate("alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa".split()):
    pad = i % 3                      # blank lines above the def, so l= varies
    body = i % 4 + 1                 # statements in the body, so e - l varies
    src = "\n" * pad + "def endline_probe_%s(widget, scale=%d):\n    \"\"\"endline probe: compute the %s widget value\"\"\"\n" % (n, i + 1, n)
    src += "".join("    widget = widget + %d\n" % k for k in range(body)) + "    return widget * scale\n"
    open(os.path.join(d, "probe_%s.py" % n), "w").write(src)
    truth["probe_%s.py" % n] = [pad + 1, pad + 1 + 1 + body + 1]
open(os.path.join(d, "README.md"), "w").write("# endline probe widgets\n\nThe endline probe computes each widget value.\n")
json.dump(truth, open(os.path.join(d, "..", "truth.json"), "w"))
PY
FXTASK="endline probe compute widget value"
TASK="rank symbols by pagerank and serialize the map"
# run NAME TREE TASK [flags]: the answer (.on, line form), its element form (.el), and the SIGX-off element twin (.tw)
run(){ name="$1"; tree="$2"; task="$3"; shift 3
    "$BIN" "$tree" --no-cache --for="$task" "$@" >"$WORK/$name.on" 2>/dev/null
    RIPWIRE_NO_ROWLINES=1 "$BIN" "$tree" --no-cache --for="$task" "$@" >"$WORK/$name.el" 2>/dev/null
    RIPWIRE_NO_ROWLINES=1 RIPWIRE_NO_SIGX=1 "$BIN" "$tree" --no-cache --for="$task" "$@" >"$WORK/$name.tw" 2>/dev/null; }
run fx    "$WORK/fx" "$FXTASK" --page-bytes=0
run whole src "$TASK" --page-bytes=0
run page1 src "$TASK"
run page2 src "$TASK" --page-bytes=12000:2
"$BIN" src --no-cache --for="$TASK" --page-bytes=0 >"$WORK/whole.on2" 2>/dev/null
RIPWIRE_NO_ROWLINES=1 "$BIN" src --no-cache --for="$TASK" --page-bytes=0 >"$WORK/whole.el2" 2>/dev/null

for f in fx whole page1 page2; do for x in on el; do
    if [ -s "$WORK/$f.$x" ] && xmllint --noout "$WORK/$f.$x" 2>/dev/null; then ok "(E6) $f.$x is well-formed XML"; else no "(E6) $f.$x is empty or not well-formed"; fi
done; done
if [ -s "$WORK/whole.on" ] && cmp -s "$WORK/whole.on" "$WORK/whole.on2" && cmp -s "$WORK/whole.el" "$WORK/whole.el2"; then ok "(E7) two runs byte-identical, line form and element form"
else no "(E7) two runs differ (or the answer is empty)"; fi

python3 - "$WORK" "$ROOT/test" <<'PY'
import json, os, re, sys
W, T = sys.argv[1], sys.argv[2]
sys.path.insert(0, T)
import rowlines
bad = 0
def rd(n): return open(os.path.join(W, n), "rb").read()
def say(ok, msg):
    global bad
    print("  %s  %s" % ("PASS" if ok else "FAIL", msg)); bad += 0 if ok else 1
ATTR = re.compile(rb' ([A-Za-z_][\w.:-]*)="([^"]*)"')
def sigs_body(d):
    """the top-level <sigs> body of an element-form answer (b'' when there is none)"""
    i = d.find(b"<sigs"); j = d.find(b"</sigs>", i)
    return d[d.find(b">", i) + 1:j] if i >= 0 and j >= 0 else b""
def drows(d):
    """{rank: attribute dict} of the direct <d> rows of <sigs>, read with the decoder's own row scanner"""
    body = sigs_body(d); out = {}
    for s, e, name in rowlines.rows_of(body):
        if name != b"d": continue
        _, attrs, _, _ = rowlines.open_tag(body, s); a = dict(attrs)
        if b"r" in a: out[int(a[b"r"])] = a
    return out
def agree(el, tw):
    """(E1)'s predicate: the rows of `el` whose e= is not exactly the twin's (present iff present, same value) -> offenders"""
    R, Tw = drows(el), drows(tw)
    return [r for r in R if r not in Tw or R[r].get(b"l") != Tw[r].get(b"l") or R[r].get(b"e") != Tw[r].get(b"e")], R, Tw

# (E0) presence
for name in ("fx", "whole", "page1"):
    off, R, Tw = agree(rd(name + ".el"), rd(name + ".tw"))
    deep = [r for r in Tw if r > 10 and b"e" in Tw[r]]
    say(len(deep) >= 4 and (name == "page1" or b"<sigx>" in rd(name + ".el")) and b"<sigx>" not in rd(name + ".tw"),
        "(E0) %s: the twin has %d <d> rows with r > 10 carrying e= (need >= 4); the answer has <sigx>, the twin does not" % (name, len(deep)))
    # (E1) NEW
    say(bool(R) and sorted(R) == sorted(Tw) and not off,
        "(E1) %s element form: %d <d> rows, e= present iff the twin's row has it, same value (offenders: %s)" % (name, len(R), off[:6]))
_, _, fxtw = agree(rd("fx.el"), rd("fx.tw"))
say(any(b"l" in a and b"e" not in a for a in fxtw.values()), "(E0) fixture twin: a row with l= and NO e= exists (the unknown-extent case is in the population)")

# (E1n) mutation control on real output
el = rd("whole.el"); m = re.search(rb'(<d l="\d+") e="\d+"( n="[^"]*" p="[^"]*" r="(?:1[1-9]|[2-9]\d)"/>)', el)
mut = el[:m.start()] + m.group(1) + m.group(2) + el[m.end():] if m else el
say(m is not None and mut != el and len(mut) < len(el) and bool(agree(mut, rd("whole.tw"))[0]),
    "(E1n) MUTATION CONTROL: one short row's e= removed (removal took: %s) -> (E1)'s predicate fails" % (m is not None and mut != el))

# (E2) NEW line form, read with the decoder's own grammar
for name in ("fx", "whole", "page1"):
    on = rd(name + ".on"); tw = drows(rd(name + ".tw")); i = on.find(b"<sigs"); j = on.find(b"</sigs>", i)
    body = on[on.find(b">", i) + 1:j]; lines = body[9:-3].split(b"\n") if body.startswith(b"<![CDATA[") and body.endswith(b"]]>") else []
    dec = drows(rowlines.decode(on)); offenders = []; spelled = 0; rank = 0; seq = b' rseq="1"' in on[i:on.find(b">", i) + 1]
    for ln in lines:
        row = rowlines.parse_line(ln); _, attrs, _, _ = rowlines.open_tag(row, 0); a = dict(attrs)
        rank = int(a[b"r"]) if b"r" in a else rank + 1 if seq else 0
        if row[:3] != b"<d " or ln.startswith(b"<") or rank not in tw: continue
        h = rowlines.D_HEAD.match(ln); has = h is not None and h.group(3) is not None
        if has != (b"e" in tw[rank]) or (has and h.group(3) != tw[rank][b"e"]): offenders.append(rank)
        spelled += has and rank > 10
    say(bool(lines) and spelled >= 4 and not offenders and not agree(rowlines.decode(on), rd(name + ".tw"))[0],
        "(E2) %s line form: every definition line spells -E iff the twin's row has e= (%d lines with r > 10 spell it; offenders %s)" % (name, spelled, offenders[:6]))

# (E3) lossless, (E3n) its control
for name in ("fx", "whole", "page1", "page2"):
    say(len(rd(name + ".on")) > 0 and rowlines.decode(rd(name + ".on")) == rd(name + ".el"), "(E3) %s: rowlines.decode(answer) == the RIPWIRE_NO_ROWLINES=1 twin, byte for byte" % name)
on = rd("whole.on"); i = on.find(b"<sigs"); j = on.find(b"</sigs>", i); head, body, rest = on[:i], on[i:j], on[j:]
lines = body.split(b"\n"); k = next((n for n, ln in enumerate(lines) if n > 12 and re.match(rb"[^<][^ ]*:\d+-\d+ ", ln)), None)
if k is not None: lines[k] = re.sub(rb":(\d+)-\d+ ", rb":\1 ", lines[k], count=1)
mut = head + b"\n".join(lines) + rest
say(k is not None and mut != on and rowlines.decode(mut) != rd("whole.el"), "(E3n) MUTATION CONTROL: -E dropped from one line past row 12 (drop took: %s) -> decode != the twin" % (k is not None and mut != on))

# (E4) NEW known values on the fixture
truth = json.load(open(os.path.join(W, "truth.json"))); deep = 0; wrong = []
for form, doc in (("element", rd("fx.el")), ("line", rowlines.decode(rd("fx.on")))):
    for r, a in drows(doc).items():
        p = a.get(b"p", b"").decode()
        if p in truth:
            got = [int(a.get(b"l", b"0")), int(a.get(b"e", b"0"))]
            if got != truth[p]: wrong.append((form, r, p, got, truth[p]))
            deep += r > 10 and got == truth[p]
    md = [a for a in drows(doc).values() if a.get(b"p") == b"README.md"]
    say(bool(md) and all(b"l" in a and b"e" not in a for a in md), "(E4) fixture, %s form: the markdown heading row has l= and NO e= (extent unknown stays absent)" % form)
say(deep >= 8 and not wrong, "(E4) fixture: every code row's l=/e= is the generator's first/last line; %d checks on rows with r > 10 across both forms (need >= 8); wrong: %s" % (deep, wrong[:4]))

# (E5) NEW e= is said once
for name in ("fx", "whole"):
    el = rd(name + ".el"); a = el.find(b"<sigx>"); b = el.find(b"</sigx>")
    xs = re.findall(rb'<x r="(\d+)"([^>]*?)/?>', el[a:b]) if a >= 0 else []
    R = drows(el); Tw = drows(rd(name + ".tw"))
    dup = [int(r) for r, attrs in xs if re.search(rb' e="', attrs)]
    names = [int(r) for r, attrs in xs if sorted(set(R[int(r)]) | set(k for k, _ in ATTR.findall(attrs))) != sorted(Tw[int(r)])]
    say(len(xs) >= 1 and not dup and not names, "(E5) %s: %d <x> rows, none carries e=, and row + x attribute names == the twin's row (dup %s, mismatched %s)" % (name, len(xs), dup[:5], names[:5]))

# (E6) G4: no newline outside CDATA
for name in ("fx", "whole", "page1", "page2"):
    for x in ("on", "el"):
        d = re.sub(rb"<!\[CDATA\[.*?\]\]>", b"", rd(name + "." + x), flags=re.S).rstrip(b"\n")
        say(b"\n" not in d, "(E6) %s.%s: no newline outside CDATA" % (name, x))

# (E8) NEW legend
el = rd("whole.el"); lg = re.search(rb"<!-- sigx:.*?-->", el, re.S)
say(lg is not None and re.search(rb"keeps l= e= n= p= r=", lg.group(0)) is not None, "(E8) the sigx legend names e= among the attributes a short row keeps")
p1e, p1 = rd("page1.el"), rd("page1.on")
say(re.search(rb"<!--[^>]*\bd e= its last line", p1e) is not None or re.search(rb"<!--[^>]*; e= on a d row", p1e) is not None, "(E8) element-form page 1 defines e=")
say(b"'P:L-E N k=v.. | SIG' is <d p=P l=L e=E n=N k=v..>" in p1, "(E8) line-form page 1 carries the lines clause that spells P:L-E")
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] || fail=1
if [ "$fail" -ne 0 ]; then echo "forendlinecheck: FAILURES"; exit 1; fi
echo "forendlinecheck: ALL PASS"

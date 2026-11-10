#!/usr/bin/env bash
# forsizetrimcheck.sh — SIZE-1 and SIZE-3: --for answer bytes that carry nothing are not printed.
#
# SIZE-1: a legend clause rides only when the final rows carry its attribute (d layer=, iface implementors=, field name=, the
# fold's slice members=, the <syms> test=1 and files= head= readings). SIZE-3a: a <d> row whose doc+signature text repeats an
# earlier row's prints same_as=<n> instead of the text (every attribute kept), with its clause. SIZE-3b: a tail row's sym= lists
# a name once. (SIZE-2, the tail fold, is test/fortailfoldcheck.sh.)
#
# Arms (each reads the exit code of the command it parses; an empty or crashed answer fails every arm):
#   1  present-only: over every answer below, each clause rides iff its attribute does (absence and presence both checked)
#   2  layer twin: a ranked file under test/ carries layer= and the answer defines it (the positive twin of arm 1's absence)
#   3  same_as: two methods with one doc+signature text: the second <d> row is <d … same_as="A.run"></d>, keeps n= p= l= r=,
#      and the clause rides; the first row keeps its text (positive twin: the first row's text is printed)
#   4  same_as absent: a fixture with distinct texts prints no same_as= and no clause
#   5  sym once: no tail row's sym= repeats a name, on a fixture whose tail files each hold two same-named methods
#      (positive twin: such a tail row lists that name)
#   6  block clauses (round 2): inside each task block, a row clause rides iff the block's rows carry its attribute, in both
#      dialects: exemplar_family oversized=/unread=, lit body=/longer=/try=, shortkey's rungs (n=leaf, n=substring, held=lit,
#      floor=1), reexports glob=/cands=/ns=/q=/q_by=/q_unmatched=/as_skipped=, dotted_strings sink=/loader=/tmpl=, doc_body
#      held="budget". Non-vacuous: the exemplar, lit, shortkey and reexports blocks each print, and each misses some attribute.
#   7  same_as unambiguous (CodeRabbit 4505000660, 2026-11-08): a fold names its source by n=, so it folds only when every
#      earlier row with that n= prints the same text; on a fixture of four top-level run() functions (two texts, two files each)
#      no same_as= row has an earlier same-n= row of another text (positive twin: both texts print under n="run")
#   8  same_as dictionary (CodeRabbit 4505000658, 2026-11-08): `--legend-dict` defines the same_as= clause, and the MCP `for`
#      verb, asked twice in one session on arm 3's fixture, carries same_as= both times and the clause only the first time
#
# Usage: test/forsizetrimcheck.sh [BIN]   (default build/ripwire; RIPWIRE_BIN also honoured)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "forsizetrimcheck: BIN=$BIN"

# P: plain functions, no layer dir, no classes
P="$TMP/plain"; mkdir -p "$P"
for n in 1 2 3 4 5; do printf 'def widget_frobnicate_%s(x):\n    """frobnicate widget %s"""\n    return x + %s\n' "$n" "$n" "$n" > "$P/w$n.py"; done
# L: one ranked file under test/ (built-in layer)
L="$TMP/layer"; mkdir -p "$L/test"
printf 'def widget_frobnicate(x):\n    """frobnicate the widget"""\n    return x\n' > "$L/test/wf.py"
printf 'def widget_other(x):\n    return x\n' > "$L/other.py"
# S: two classes whose run() share one docstring and signature
S="$TMP/same"; mkdir -p "$S"
printf 'class A:\n    def run(self, widget_frobnicate_value, step_parameter_name):\n        """Run the widget frobnicate step for this one."""\n        return widget_frobnicate_value\n' > "$S/a.py"
printf 'class B:\n    def run(self, widget_frobnicate_value, step_parameter_name):\n        """Run the widget frobnicate step for this one."""\n        return widget_frobnicate_value + 1\n' > "$S/b.py"
# A: four top-level run() functions sharing one n=: two with one doc+signature text, two with another (arm 7)
A="$TMP/ambig"; mkdir -p "$A"
for f in a b; do printf 'def run(widget_frobnicate_value, step_parameter_name):\n    """Run the widget frobnicate step for this one."""\n    return widget_frobnicate_value\n' > "$A/$f.py"; done
for f in c d; do printf 'def run(widget_frobnicate_value, other_parameter_name):\n    """Run the widget frobnicate step for the other one."""\n    return widget_frobnicate_value\n' > "$A/$f.py"; done
# T: 60 files, each with two classes holding a same-named method: the tail rows past the head name it
T="$TMP/tail"; mkdir -p "$T"
i=0
while [ $i -lt 60 ]; do
    n=$( printf '%02d' $i )
    printf 'class P%s:\n    def widget_frobnicate(self):\n        return 1\n\nclass Q%s:\n    def widget_frobnicate(self):\n        return 2\n' "$n" "$n" > "$T/t$n.py"
    i=$(( i + 1 ))
done

run() {   # run DIR OUTFILE ARGS... -> rc file beside the output
    local d="$1" o="$2"; shift 2
    ( cd "$d" || exit 9; HOME="$TMP/home" TMPDIR="$TMP/" "$BIN" "$d" --no-cache "$@" ) > "$o" 2> "$o.err"
    echo $? > "$o.rc"
}
mkdir -p "$TMP/home"
run "$P" "$TMP/p.xml" "--for=widget frobnicate"
run "$P" "$TMP/p.full" "--for=widget frobnicate" --legend=full
run "$L" "$TMP/l.xml" "--for=widget frobnicate"
run "$S" "$TMP/s.xml" "--for=run the widget frobnicate step"
run "$S" "$TMP/s.full" "--for=run the widget frobnicate step" --legend=full
run "$T" "$TMP/t.xml" "--for=widget frobnicate"
run "$A" "$TMP/a.xml" "--for=run the widget frobnicate step"
( cd "$S" || exit 9; for id in 1 2; do printf '{"jsonrpc":"2.0","id":%s,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' "$id" "$S" "run the widget frobnicate step"; done \
    | HOME="$TMP/home" TMPDIR="$TMP/" "$BIN" --mcp ) > "$TMP/m.two" 2> "$TMP/m.two.err"
echo $? > "$TMP/m.two.rc"
( cd "$S" || exit 9; HOME="$TMP/home" TMPDIR="$TMP/" "$BIN" --legend-dict ) > "$TMP/dict" 2> "$TMP/dict.err"
echo $? > "$TMP/dict.rc"
# X: a handler family, a dotted key and a TS re-export (arm 6's blocks)
X="$TMP/blocks"; mkdir -p "$X/widgets"
printf 'class WidgetHandler:\n    """base of every widget handler"""\n    def handle(self, w):\n        return w\n\n' > "$X/widgets/registry.py"
for k in Foo Bar Baz; do printf 'class %sWidgetHandler(WidgetHandler):\n    def handle(self, w):\n        return "%s"\n\n' "$k" "$k" >> "$X/widgets/registry.py"; done
printf 'HANDLERS = ["widgets.registry.FooWidgetHandler"]\nWIDGET_KEY = "widget.handler.default"\n\ndef load_handler(name):\n    return HANDLERS[0]\n' > "$X/widgets/settings.py"
Y="$TMP/reexp"; mkdir -p "$Y/src"
printf 'export function frobWidget(x: number): number { return x + 1; }\n' > "$Y/src/a.ts"
printf "export { frobWidget } from './a';\n" > "$Y/src/index.ts"
for lg in compact full; do
    run "$X" "$TMP/x1.$lg" "--for=add a new widget handler like FooWidgetHandler" --legend=$lg
    run "$X" "$TMP/x2.$lg" "--for=where is \`widget.handler.default\` read" --legend=$lg
    run "$Y" "$TMP/y1.$lg" "--for=which module re-exports frobWidget" --legend=$lg
done

python3 - "$TMP" <<'PY'
import html, json, re, sys
T = sys.argv[1]; fails = 0
def say(ok, msg):
    global fails
    print(("PASS " if ok else "FAIL ") + msg)
    fails += 0 if ok else 1
def load(name):
    try:
        rc = open(f"{T}/{name}.rc").read().strip(); tx = open(f"{T}/{name}", errors="replace").read()
    except OSError:
        return None
    return tx if rc == "0" and "<ctx" in tx else None
ans = {n: load(n) for n in ("p.xml", "p.full", "l.xml", "s.xml", "s.full", "t.xml", "a.xml")}
say(all(ans.values()), "0 every answer ran (rc 0, a <ctx> root): " + ",".join(n for n, v in ans.items() if not v))
body = lambda t: re.sub(r"<!--.*?-->", "", t, flags=re.S)
PAIRS = [("; d layer=:", ' layer="'), ("; iface implementors=N", ' implementors="'), ("; field name= type= owner= rel=", "<field "),
         ("slice members= of=", ' members="'), ("test=1 test code; ", ' test="1"'), ('test="1": a test or fixture symbol; ', ' test="1"')]
bad = [(n, c) for n, t in ans.items() if t for c, a in PAIRS if (c in t) != (a in body(t))]
say(not bad and any(ans.values()), f"1 present-only: each clause rides iff its attribute does ({bad[:4]})")
l = ans["l.xml"] or ""
say(' layer="test"' in body(l) and "; d layer=:" in l, "2 layer twin: a test/ row carries layer= and the clause defines it")
s, sf = ans["s.xml"] or "", ans["s.full"] or ""
rows = re.findall(r'<d ([^>]*)>(.*?)</d>', s, re.S)
same = [(a, t) for a, t in rows if 'same_as="' in a]
first = [(a, t) for a, t in rows if 'same_as="' not in a and "def run(self, widget_frobnicate_value" in t]
say(len(same) == 1 and same[0][1] == "" and all(re.search(r'(^|\s)' + k + '="', same[0][0]) for k in ("n", "p", "l", "r"))
    and re.search(r'same_as="(A|B)\.run"', same[0][0]) is not None, f"3 same_as: one folded row, attributes kept, text empty ({[a for a, _ in same]})")
say(len(first) == 1, "3 twin: the first row prints the shared text")
say("; d same_as=N:" in s and "; d same_as=N:" in sf and 'same_as="' in sf, "3 legend: the clause rides in both dialects")
p = ans["p.xml"] or ""
say(p != "" and 'same_as="' not in p and "same_as=N" not in p, "4 same_as absent on distinct texts, no clause")
t = ans["t.xml"] or ""
syms = [s.split(",") for s in re.findall(r'<t p="[^"]*" sym="([^"]*)"', t)]
say(bool(syms) and all(len(v) == len(set(v)) for v in syms), f"5 sym once: {sum(len(v) != len(set(v)) for v in syms)} of {len(syms)} tail rows repeat a name")
say(any("widget_frobnicate" in v for v in syms), "5 twin: a tail row lists the shared method name")
# arm 7: a same_as= row's n= names exactly one earlier text
def ambiguous(tx):
    seen, bad = [], []   # (n=, text) of each earlier row that printed its text
    for a, t in re.findall(r'<d ([^>]*)>(.*?)</d>', tx, re.S):
        n = re.search(r'(?:^|\s)n="([^"]*)"', a); src = re.search(r'same_as="([^"]*)"', a)
        if src:
            if len({txt for m, txt in seen if m == src.group(1)}) != 1:
                bad.append(src.group(1))
        elif n:
            seen.append((n.group(1), t))
    return bad, seen
amb = ans["a.xml"] or ""
bad7 = [(nm, b) for nm in ("s.xml", "s.full", "a.xml") for b in ambiguous(ans[nm] or "")[0]]
say(amb != "" and not bad7, f"7 same_as unambiguous: no fold names an n= shared by another text ({bad7[:4]})")
say(len({t for m, t in ambiguous(amb)[1] if m == "run"}) == 2, "7 twin: both run() texts print under n=\"run\"")
# arm 8: the same_as= clause is a session-dictionary entry
def raw(name):
    try:
        return open(f"{T}/{name}", errors="replace").read() if open(f"{T}/{name}.rc").read().strip() == "0" else ""
    except OSError:
        return ""
texts = []
for line in raw("m.two").splitlines():
    try:
        texts.append("".join(c.get("text", "") for c in json.loads(line)["result"]["content"]))
    except (ValueError, KeyError, TypeError):
        pass
say("for: d same_as=N:" in raw("dict"), "8 dictionary: --legend-dict defines the same_as= clause")
shape8 = [('same_as="' in t, "d same_as=N:" in t) for t in texts]
say(len(texts) == 2 and all('same_as="' in t for t in texts) and "d same_as=N:" in texts[0] and "d same_as=N:" not in texts[1],
    f"8 served once: both MCP answers fold, only the first carries the clause ({shape8})")
# arm 6: per block, (clause text in the legend) == (attribute on the block's rows)
BLOCKS = {
    "exemplar_family": (r"<!-- ripwire for exemplar_family.*?</exemplar_family>", [
        ("oversized=N registry candidates over 4000 lines", r"<exemplar_family [^>]*(oversized|unread)=\""),
        ("oversized=N counts the registry candidates", r"<exemplar_family [^>]*(oversized|unread)=\"")]),
    "lit": (r"<!-- ripwire for lit.*</lit>", [
        ("body=above|held: printed above", r' body="'), ("body=above: printed above, held:", r' body="'),
        ("longer= source sites inside a longer name", r' longer="'), ("anchored; the ones before it had no source site or were not scanned", r' try="')]),
    "shortkey": (r"<!-- shortkey:.*?</shortkey>", [
        ("rung n=leaf: X written Q.leaf", r'<rung n="leaf"'), ("rung n=substring: definitions", r'<rung n="substring"'),
        ("held=lit: the lit block lists this key", r' held="lit"'), ("floor=1: the scan stopped early, counts are floors", r'<rung [^>]*floor="1"')]),
    "reexports": (r"<reexports>.*?</reexports>", [
        ("glob=1 a glob/star hop", r' glob="1"'), ("cands=N the path names N same-named crates", r' cands="'), ("ns= a namespace hop", r' ns="'),
        ("def q= the qualifier the task wrote", r' q="'), ("q_by=alias only a consumer", r' q_by="'), ("q_unmatched=1 no chain proves Q", r' q_unmatched="'),
        ("as_skipped=N renamed re-exports", r' as_skipped="')]),
    "dotted_strings": (r"<!-- ripwire for dotted_strings.*?</dotted_strings>", [
        ("sink= it is the argument of a call", r' sink="'), ("loader= lp= a function in which", r' loaders?(_floor)?="'), ("tmpl= a %-template", r' tmpl="')]),
    "doc_body": (r"<!-- ripwire for doc_body.*?</doc_body>", [("held_bytes=: a token budget kept", r' held="budget"')]),
}
seen = {k: 0 for k in BLOCKS}; absent = {k: 0 for k in BLOCKS}; bad6 = []
for name in ("x1", "x2", "y1"):
    for lg in ("compact", "full"):
        tx = load(f"{name}.{lg}")
        if tx is None:
            bad6.append((name, lg, "no answer")); continue
        for blk, (rx, pairs) in BLOCKS.items():
            for m in re.finditer(rx, tx, re.S):
                seen[blk] += 1
                leg = " ".join(re.findall(r"<!--(.*?)-->", m.group(0), re.S)); rows = body(m.group(0))
                for clause, attr in pairs:
                    has = re.search(attr, rows) is not None
                    absent[blk] += 0 if has else 1
                    if clause in leg and not has:
                        bad6.append((name, lg, blk, clause))                 # a clause with no row to define
                    elif has and not any(c in leg for c, a in pairs if a == attr):
                        bad6.append((name, lg, blk, "undefined " + attr))    # a row attribute its legend lost
say(not bad6, f"6 block clauses: each rides iff its attribute does ({bad6[:4]})")
need = ("exemplar_family", "lit", "shortkey", "reexports")
say(all(seen[k] > 0 and absent[k] > 0 for k in need), f"6 non-vacuous: blocks printed {seen}, attributes missing {absent}")
print("forsizetrimcheck:", "FAIL" if fails else "PASS", f"({fails} failing)")
sys.exit(1 if fails else 0)
PY

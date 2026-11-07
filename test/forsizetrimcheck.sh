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

python3 - "$TMP" <<'PY'
import html, re, sys
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
ans = {n: load(n) for n in ("p.xml", "p.full", "l.xml", "s.xml", "s.full", "t.xml")}
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
print("forsizetrimcheck:", "FAIL" if fails else "PASS", f"({fails} failing)")
sys.exit(1 if fails else 0)
PY

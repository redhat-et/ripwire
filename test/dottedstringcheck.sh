#!/usr/bin/env bash
# dottedstringcheck.sh — STRING-IMPORT: dotted-string literals naming a shown Python definition (src/fordottedstring.h; the facts:
# src/ingest_valuerefs.h dottedStringAt; the resolver: src/pydottedpath.h).
#
# THE CONTRACT THIS PINS (arms tagged [P] are RED on the pre-change binary 26e0fefc; [G] are twins and near-miss negatives that hold on
# both binaries and must keep holding):
#   K1 [P] constant tuple + loader loop: s= tn= tp= p= l= in=CONST loader= lp=
#   K2 [P] direct import_string("a.b.C"): sink=import_string in=function, no loader=
#   K3 [P] import_module of a package __init__: mod=pkg/sub/__init__.py sink=import_module
#   K4 [P] a class attribute list: in=Cls.ATTR; a dict VALUE qualifies
#   K5 [P] a method's class named by a string: a shown method's owner matches through the whole path
#   E1 [P] external module: external= counts it, no <ds> for it   E2 [P] module present, attribute missing: unresolved= counts it
#   E3 [G] two modules of one path (a/b.py and src/a/b.py): nothing      E4 [G] `pkg.both` both a module and a name in pkg: nothing
#   N1 [G] a docstring mention, a comment, a log-call argument, a comparison, a dict KEY, a local scalar, a keyword scalar, a default,
#          an f-string, bytes, a concatenation: no row
#   N2 [G] bare name: a string spelling another module's same name resolves to that module, never this shown row
#   N3 [G] two owners of one method name: `mod.A.run` names A.run, not B.run   N4 [G] a sink's second argument
#   N5 [G] a function whose word only STARTS with the constant, or a test function, is no loader   N6 [G] over 3 loaders: none named   E5 [G] two definitions of the name
#   T1 [P] a site in a test path is counted (tests=), never a row; test-only keeps s= next=
#   C1 [P] the cap: 4 sites show 3, rows_capped="1" next="--grep=…" (a target's non-test sites first)
#   F1 [P] a %-template filled by three sibling shown directories: tmpl= cand= cands=3 sink=      F2 [G] filled by one, or by three directories under different parents: no row   F3/F4 [G] second argument, test path: no row
#   R1 [G] --json, --token-budget, RIPWIRE_NO_DOTTED_STRINGS=1: no element   R2 [G] the answer minus the element == the OFF answer byte for byte
#   R3 [G] other languages: a JS file with the same shapes records no fact: no element
#   V1 [P] --callers carries it, the caller rows byte-identical to OFF   V2 [G] callees carries none
#   G1 [P] on the first cut of this lane, [G] since: a fact's fields are no name evidence (graph.h file evidence)
#   S-D1 [P] every attribute the element prints (mod=, loaders= over 3, a tests-only s= next=, ...) is defined in the legend of --callers and --for; a sweep over every answer here
#   S-D2 [P] loader= / tmpl= claim only "a call whose tail name is an import sink's"   S-D3 [P] the import check compares the WHOLE module (b.conf is not a/conf.py)
#   S-D4 [P] with-as, except-as, lambda parameter and a same-file other-module import are no loader (twins [G]: free name, from-import, lazy local import)
#   S-D5 [P] a ternary condition decides, it does not flow   S-D6 [P] the extension list: py/log/conf/sh and upper case
#   X1 [G] determinism   X2 [G] xmllint well-formed when present   X3 [G] no "--" inside the legend comment   X5 [P] a tests-only answer's compact legend entry has no "--" (cr-prepass 43b)
#
# Usage:  bash test/dottedstringcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/dottedstringcheck.sh
# BIN is $1, else RIPWIRE_BIN, else build/ripwire; the first output line names the binary used. Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_DOTTED_STRINGS
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "dottedstringcheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

# fx PATH <<TEXT: write one fixture file
fx(){ mkdir -p "$( dirname "$1" )"; cat > "$1"; }
# run DIR OUT [args...]: stdout + rc; a run that fails is a FAIL, never an absence
run(){ local dir="$1" out="$2"; shift 2; ( cd "$dir" || exit 97; "$BIN" "$dir" --no-cache "$@" >"$out" 2>"$out.err" </dev/null ); local rc=$?; [ "$rc" = 0 ] && [ -s "$out" ] || no "run failed rc=$rc: $* (in $dir)"; }
# has FILE TEXT LABEL / hasnt FILE TEXT LABEL: fixed-string presence in the answer
has(){ if grep -qF -- "$2" "$1"; then ok "$3"; else no "$3 (missing: $2)"; fi; }
hasnt(){ if grep -qF -- "$2" "$1"; then no "$3 (found: $2)"; else ok "$3"; fi; }
# dsrows FILE: the <ds> rows only, one per line (an absence is read only off an answer that succeeded: run checks it)
dsrows(){ python3 - "$1" <<'PY'
import re,sys
print("\n".join(re.findall(r'<ds [^>]*/>', open(sys.argv[1], encoding="utf-8").read())))
PY
}

# ── K: the shapes that qualify ────────────────────────────────────────────────────────────────────────────────────────────────
K="$TMP/k"
fx "$K/pkg/__init__.py" <<'P'
P
fx "$K/pkg/procs.py" <<'P'
def csrfproc(request):
    return {"token": request}
class Fmt:
    def render(self, x):
        return x
P
fx "$K/pkg/context.py" <<'P'
_builtin_procs = ("pkg.procs.csrfproc",)
P
fx "$K/pkg/engine.py" <<'P'
from importlib import import_module
from pkg.context import _builtin_procs
from pkg.loading import import_string

class Engine:
    default_mods = ["pkg.plain", "pkg.sub"]
    table = {"fmt": "pkg.procs.Fmt"}

    def processors(self, extra):
        paths = _builtin_procs + tuple(extra)
        return tuple(import_string(path) for path in paths)

def direct():
    return import_string("pkg.direct_target.direct_thing")

def package():
    return import_module("pkg.sub")
P
fx "$K/pkg/loading.py" <<'P'
def import_string(path):
    return path
P
fx "$K/pkg/plain.py" <<'P'
def plainfn():
    return 1
P
fx "$K/pkg/direct_target.py" <<'P'
def direct_thing():
    return 2
P
fx "$K/pkg/sub/__init__.py" <<'P'
def subfn():
    return 3
P
run "$K" "$TMP/k1" '--for=csrfproc'
has "$TMP/k1" 's="pkg.procs.csrfproc" tn="csrfproc" tp="pkg/procs.py:1" p="pkg/context.py" l="1" in="_builtin_procs" loader="Engine.processors" lp="pkg/engine.py:9"' "K1 constant tuple + loader loop"
run "$K" "$TMP/k2" '--for=direct_thing'
has "$TMP/k2" 's="pkg.direct_target.direct_thing" tn="direct_thing" tp="pkg/direct_target.py:1" p="pkg/engine.py" l="14" in="direct" sink="import_string"' "K2 direct import_string"
if dsrows "$TMP/k2" | grep -qF 'loader='; then no "K2 a direct sink needs no loader="; else ok "K2 a direct sink needs no loader="; fi
run "$K" "$TMP/k3" '--for=subfn'
has "$TMP/k3" 's="pkg.sub" mod="pkg/sub/__init__.py" p="pkg/engine.py" l="17" in="package" sink="import_module"' "K3 package __init__ through import_module"
has "$TMP/k3" 's="pkg.sub" mod="pkg/sub/__init__.py" p="pkg/engine.py" l="6" in="Engine.default_mods"' "K4 class attribute list element"
run "$K" "$TMP/k4" '--for=Fmt'
has "$TMP/k4" 's="pkg.procs.Fmt" tn="Fmt" tp="pkg/procs.py:3" p="pkg/engine.py" l="7" in="Engine.table"' "K4 dict value"
run "$K" "$TMP/k5" '--for=Fmt.render'
has "$TMP/k5" 's="pkg.procs.Fmt" tn="Fmt"' "K5 a shown method's class named through the whole path"

# ── FL [P] (CR 4431867587): a sink call whose flow tokens are over the cap (400 bytes) traces no names, so a loader it would have been is
# not counted; the row of a constant it could name says loaders_floor="1". A short flow keeps loader= and says nothing.
FL="$TMP/fl"
fx "$FL/pkg/__init__.py" <<'P'
P
fx "$FL/pkg/procs.py" <<'P'
def shortproc(request):
    return request
def longproc(request):
    return request
P
python3 - "$FL/pkg/cfg.py" <<'PY'
import sys
names = ["chain_link_%03d" % i for i in range(60)]
out = ["from importlib import import_module", "", "LONG_PROCS = [\"pkg.procs.longproc\"]", "",
       "def load_long():", "    %s = LONG_PROCS" % names[0]]
for a, b in zip(names[1:], names):
    out.append("    %s = %s" % (a, b))
out.append("    return import_module(%s)" % names[-1])
open(sys.argv[1], "w").write("\n".join(out) + "\n")
PY
run "$FL" "$TMP/fl1" '--for=longproc'
has "$TMP/fl1" 's="pkg.procs.longproc"' "FL1 the over-cap fixture's row prints"
has "$TMP/fl1" 'loaders_floor="1"' "FL1 loaders_floor=1: the over-cap sink call is disclosed, not dropped"
hasnt "$TMP/fl1" 'loader="load_long"' "FL1 the over-cap sink call joins no constant"
FS="$TMP/fs"
fx "$FS/pkg/__init__.py" <<'P'
P
fx "$FS/pkg/procs.py" <<'P'
def shortproc(request):
    return request
P
fx "$FS/pkg/cfg.py" <<'P'
from importlib import import_module

SHORT_PROCS = ["pkg.procs.shortproc"]

def load_short():
    p = SHORT_PROCS
    return import_module(p)
P
run "$FS" "$TMP/fl2" '--for=shortproc'
has "$TMP/fl2" 'loader="load_short"' "FL2 a short flow keeps its loader="
hasnt "$TMP/fl2" 'loaders_floor="1"' "FL2 and says no floor"

# ── E: what resolves to no target ─────────────────────────────────────────────────────────────────────────────────────────────
E="$TMP/e"
fx "$E/pkg/__init__.py" <<'P'
P
fx "$E/pkg/mod.py" <<'P'
def thing():
    return 1
CONFIG = ["requests.sessions.thing", "pkg.mod.absent", "pkg.mod.thing", "pkg.other.thing"]
P
fx "$E/pkg/other.py" <<'P'
def unrelated():
    return 2
P
run "$E" "$TMP/e1" '--for=thing'
has "$TMP/e1" 'external="1"' "E1 external counted"
hasnt "$TMP/e1" 'requests.sessions' "E1 external never printed"
run "$E" "$TMP/e2" '--for=absent thing'
has "$TMP/e1" 's="pkg.mod.thing" tn="thing"' "E2 the resolved twin prints"
has "$TMP/e1" 'unresolved="1"' "E2 module present, attribute missing: unresolved= counts it"
hasnt "$TMP/e1" 's="pkg.other.thing"' "E2 an unresolved string prints no row"
hasnt "$TMP/e2" 's="pkg.mod.absent"' "E2 attribute missing prints no target"
E3="$TMP/e3"
fx "$E3/a/b.py" <<'P'
def twin():
    return 1
P
fx "$E3/src/a/b.py" <<'P'
def twin():
    return 2
P
fx "$E3/use.py" <<'P'
NAMES = ["a.b.twin"]
P
run "$E3" "$TMP/e3o" '--for=twin'
if [ -z "$( dsrows "$TMP/e3o" )" ]; then ok "E3 two modules of one path: nothing"; else no "E3 printed a row"; fi
E4="$TMP/e4"
fx "$E4/pkg/__init__.py" <<'P'
def both():
    return 1
P
fx "$E4/pkg/both.py" <<'P'
def inner():
    return 2
P
fx "$E4/use.py" <<'P'
NAMES = ["pkg.both"]
P
run "$E4" "$TMP/e4o" '--for=both inner'
if [ -z "$( dsrows "$TMP/e4o" )" ]; then ok "E4 both a module and a name: nothing"; else no "E4 printed a row"; fi

E5="$TMP/e5"
fx "$E5/pkg/__init__.py" <<'P'
P
fx "$E5/pkg/mod.py" <<'P'
try:
    def dup():
        return 1
except ImportError:
    def dup():
        return 2
P
fx "$E5/use.py" <<'P'
NAMES = ["pkg.mod.dup"]
P
run "$E5" "$TMP/e5o" '--for=dup'
if [ -z "$( dsrows "$TMP/e5o" )" ]; then ok "E5 two definitions of the name in its module: nothing"; else no "E5 printed a row"; fi

# ── N: strings that are not facts, and names that are not this row ────────────────────────────────────────────────────────────
N="$TMP/n"
fx "$N/pkg/__init__.py" <<'P'
P
fx "$N/pkg/mod.py" <<'P'
def thing():
    return 1
P
fx "$N/pkg/near.py" <<'P'
"""pkg.mod.thing in a module docstring."""
import logging
log = logging.getLogger("pkg.mod.thing")
SCALARS = {"pkg.mod.thing": 1}   # a dict KEY; and pkg.mod.thing in a comment
BYTES = b"pkg.mod.thing"
FSTR = f"pkg.mod.thing"
JOINED = "pkg.mod." "thing"
PRE = "pkg.mod.thing!"
def near(x, default="pkg.mod.thing"):
    """pkg.mod.thing in a docstring."""
    local = "pkg.mod.thing"
    log.info("pkg.mod.thing")
    configure(path="pkg.mod.thing")
    return x == "pkg.mod.thing"
P
run "$N" "$TMP/n1" '--for=thing'
if [ -z "$( dsrows "$TMP/n1" )" ]; then ok "N1 docstring, comment, log arg, key, bytes, f-string, concatenation, default, local, keyword, comparison: no row"; else no "N1 printed: $( dsrows "$TMP/n1" | head -3 )"; fi
hasnt "$TMP/n1" '<dotted_strings' "N1 no element at all"
N2="$TMP/n2"
fx "$N2/pkg/__init__.py" <<'P'
P
fx "$N2/pkg/one.py" <<'P'
def same():
    return 1
P
fx "$N2/pkg/two.py" <<'P'
def same():
    return 2
P
fx "$N2/use.py" <<'P'
NAMES = ["pkg.two.same"]
P
run "$N2" "$TMP/n2o" '--for=same'
has "$TMP/n2o" 'tp="pkg/two.py:1"' "N2 the string names two.py's same"
hasnt "$TMP/n2o" 'tp="pkg/one.py' "N2 never one.py's same (no bare name)"
N3="$TMP/n3"
fx "$N3/mod.py" <<'P'
class A:
    def run(self):
        return 1
class B:
    def run(self):
        return 2
NAMES = ["mod.A.run"]
P
run "$N3" "$TMP/n3o" '--for=run'
has "$TMP/n3o" 'tn="A.run" tp="mod.py:2"' "N3 the owner chain picks A.run"
hasnt "$TMP/n3o" 'tp="mod.py:5"' "N3 never B.run"

N4="$TMP/n4"
fx "$N4/pkg/__init__.py" <<'P'
P
fx "$N4/pkg/mod.py" <<'P'
def thing():
    return 1
P
fx "$N4/pkg/second.py" <<'P'
from importlib import import_module
def second(x):
    return import_module(x, "pkg.mod.thing")
P
run "$N4" "$TMP/n4o" '--for=thing'
if [ -z "$( dsrows "$TMP/n4o" )" ]; then ok "N4 a sink's second argument is no fact"; else no "N4 printed a row"; fi
N5="$TMP/n5"
fx "$N5/pkg/__init__.py" <<'P'
P
fx "$N5/pkg/mod.py" <<'P'
def thing():
    return 1
P
fx "$N5/pkg/conf.py" <<'P'
PROCS = ["pkg.mod.thing"]
P
fx "$N5/pkg/near_loader.py" <<'P'
from importlib import import_module
def near_loader(PROCS2):
    return import_module(PROCS2)
P
fx "$N5/tests/test_loader.py" <<'P'
from importlib import import_module
from pkg.conf import PROCS
def load_in_test():
    return [import_module(p) for p in PROCS]
P
run "$N5" "$TMP/n5o" '--for=thing'
has "$TMP/n5o" 's="pkg.mod.thing" tn="thing"' "N5 the string prints"
if dsrows "$TMP/n5o" | grep -qF 'loader='; then no "N5 a longer word or a test function is no loader"; else ok "N5 a longer word or a test function is no loader"; fi

N6="$TMP/n6"
fx "$N6/pkg/__init__.py" <<'P'
P
fx "$N6/pkg/mod.py" <<'P'
def thing():
    return 1
P
fx "$N6/pkg/conf.py" <<'P'
class Conf:
    name = "pkg.mod.thing"
P
for i in 1 2 3 4; do fx "$N6/pkg/load$i.py" <<'P'
from importlib import import_module
def load(cfg):
    return import_module(cfg.name)
P
done
run "$N6" "$TMP/n6o" '--for=thing'
has "$TMP/n6o" 'in="Conf.name" loaders="4"' "N6 a constant every loader spells: the count"
if dsrows "$TMP/n6o" | grep -qF ' loader='; then no "N6 and no named loader"; else ok "N6 and no named loader"; fi

# ── T / C: test paths, the cap ────────────────────────────────────────────────────────────────────────────────────────────────
T="$TMP/t"
fx "$T/pkg/__init__.py" <<'P'
P
fx "$T/pkg/mod.py" <<'P'
def thing():
    return 1
def alone():
    return 2
P
fx "$T/tests/test_x.py" <<'P'
NAMES = ["pkg.mod.thing", "pkg.mod.alone"]
P
fx "$T/pkg/conf.py" <<'P'
NAMES = ["pkg.mod.thing"]
P
run "$T" "$TMP/t1" '--for=thing'
has "$TMP/t1" 'tests="1"' "T1 the test site is counted"
hasnt "$TMP/t1" 'p="tests/test_x.py"' "T1 and never a row"
run "$T" "$TMP/t2" '--for=alone'
has "$TMP/t2" 'sites="0" rows="0" hedge="a string in the source names this symbol; whether any import sink loads it is not traced" tests="1" s="pkg.mod.alone" next="--grep=pkg.mod.alone"' "T1 test-only: the count, the string, next="
C="$TMP/c"
fx "$C/pkg/__init__.py" <<'P'
P
fx "$C/pkg/mod.py" <<'P'
def thing():
    return 1
P
for i in 1 2 3 4; do fx "$C/pkg/conf$i.py" <<'P'
NAMES = ["pkg.mod.thing"]
P
done
run "$C" "$TMP/c1" '--for=thing'
has "$TMP/c1" 'sites="4" rows="3"' "C1 the cap counts"
has "$TMP/c1" 'rows_capped="1" next="--grep=pkg.mod.thing"' "C1 cap and next="
if [ "$( dsrows "$TMP/c1" | wc -l | tr -d ' ' )" = 3 ]; then ok "C1 three rows"; else no "C1 row count"; fi

# ── F: a %-template ───────────────────────────────────────────────────────────────────────────────────────────────────────────
F="$TMP/f"
fx "$F/pkg/__init__.py" <<'P'
P
fx "$F/pkg/utils.py" <<'P'
from importlib import import_module
def load_backend(name):
    return import_module("%s.base" % name)
P
for b in one two three; do
fx "$F/pkg/$b/__init__.py" <<'P'
P
fx "$F/pkg/$b/base.py" <<'P'
class W:
    pass
P
fx "$F/pkg/$b/ops.py" <<'P'
class Ops:
    def quote_it(self):
        return 1
P
done
run "$F" "$TMP/f1" '--for=quote_it'
has "$TMP/f1" 'tmpl="%s.base" cand="pkg/one/base.py,pkg/three/base.py,pkg/two/base.py" cands="3" p="pkg/utils.py" l="3" in="load_backend" sink="import_module"' "F1 template with three sibling fills"
F2="$TMP/f2"
fx "$F2/pkg/__init__.py" <<'P'
P
fx "$F2/pkg/utils.py" <<'P'
from importlib import import_module
def load_backend(name):
    return import_module("%s.base" % name)
P
fx "$F2/pkg/one/__init__.py" <<'P'
P
fx "$F2/pkg/one/base.py" <<'P'
class W:
    pass
P
fx "$F2/pkg/one/ops.py" <<'P'
def quote_it():
    return 1
P
run "$F2" "$TMP/f2o" '--for=quote_it'
hasnt "$TMP/f2o" 'tmpl=' "F2 one directory fills it: no row"
F5="$TMP/f5"
cp -R "$F2" "$F5"
for b in x/a y/b z/c; do
fx "$F5/pkg/$b/__init__.py" <<'P'
P
fx "$F5/pkg/$b/base.py" <<'P'
class W:
    pass
P
fx "$F5/pkg/$b/ops.py" <<'P'
def quote_it():
    return 1
P
done
run "$F5" "$TMP/f5o" '--for=quote_it'
hasnt "$TMP/f5o" 'tmpl=' "F2 three directories under different parents: no row"

F3="$TMP/f3"
cp -R "$F" "$F3"
fx "$F3/pkg/utils.py" <<'P'
from importlib import import_module
def load_backend(name):
    return import_module(name, "%s.base" % name)
P
run "$F3" "$TMP/f3o" '--for=quote_it'
hasnt "$TMP/f3o" 'tmpl=' "F3 a template in a sink's second argument: no row"
F4="$TMP/f4"
cp -R "$F" "$F4"
mkdir -p "$F4/tests"; mv "$F4/pkg/utils.py" "$F4/tests/utils.py"
run "$F4" "$TMP/f4o" '--for=quote_it'
hasnt "$TMP/f4o" 'tmpl=' "F4 a template in a test path: no row"

# ── R: regimes, byte identity, other languages ────────────────────────────────────────────────────────────────────────────────
run "$K" "$TMP/rj" '--for=csrfproc' --json
hasnt "$TMP/rj" 'dotted_strings' "R1 --json carries none"
run "$K" "$TMP/rb" '--for=csrfproc' --token-budget=3000
hasnt "$TMP/rb" 'dotted_strings' "R1 --token-budget carries none"
RIPWIRE_NO_DOTTED_STRINGS=1 run "$K" "$TMP/roff" '--for=csrfproc'
hasnt "$TMP/roff" 'dotted_strings' "R1 RIPWIRE_NO_DOTTED_STRINGS=1 carries none"
if python3 - "$TMP/k1" "$TMP/roff" <<'PY'
import re,sys
a=open(sys.argv[1],encoding="utf-8").read(); b=open(sys.argv[2],encoding="utf-8").read()
s=re.sub(r'<(?:dotted_strings|ds) [^>]*>: .*?\. ','',a)   # the --callers legend layer's clauses for the element (S-B3)
s=re.sub(r'(<!-- ripwire for dotted_strings:.*?-->)?<dotted_strings .*?</dotted_strings>','',s,flags=re.S)
sys.exit(0 if s!=a and s==b else 1)
PY
then ok "R2 the answer minus the element == the OFF answer"; else no "R2 the element moved other bytes"; fi
J="$TMP/j"
fx "$J/pkg/mod.js" <<'P'
export function thing() { return 1; }
export const NAMES = ["pkg.mod.thing"];
P
run "$J" "$TMP/j1" '--for=thing'
hasnt "$TMP/j1" 'dotted_strings' "R3 JavaScript records no fact"

# ── V: --callers ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
run "$K" "$TMP/v1" '--callers=csrfproc'
has "$TMP/v1" 's="pkg.procs.csrfproc" tn="csrfproc"' "V1 --callers carries the row"
has "$TMP/v1" 'hedge="a string in the source names this symbol' "V1 and its hedge (the verb's legend layer keeps no comment)"
RIPWIRE_NO_DOTTED_STRINGS=1 run "$K" "$TMP/v1off" '--callers=csrfproc'
if python3 - "$TMP/v1" "$TMP/v1off" <<'PY'
import re,sys
a=open(sys.argv[1],encoding="utf-8").read(); b=open(sys.argv[2],encoding="utf-8").read()
a=re.sub(r'<(?:dotted_strings|ds) [^>]*>: .*?\. ','',a)
sys.exit(0 if re.sub(r'(<!-- ripwire for dotted_strings:.*?-->)?<dotted_strings .*?</dotted_strings>','',a,flags=re.S)==b else 1)
PY
then ok "V1 the caller answer is otherwise byte-identical"; else no "V1 the element moved caller bytes"; fi
run "$K" "$TMP/v2" '--callees=csrfproc'
hasnt "$TMP/v2" 'dotted_strings' "V2 --callees carries none"

# ── G: a fact is no name evidence: its qualifier "%" must not read as this file naming class D (cpython: sys.path.insert bound by name) ──
G="$TMP/g"
fx "$G/other.py" <<'P'
class D:
    def insert(self, a, b):
        return a
P
fx "$G/runner.py" <<'P'
import sys
def go(x):
    sys.path.insert(0, x)
    return __import__(x)
P
run "$G" "$TMP/g1" '--callees=go'
hasnt "$TMP/g1" 'n="D.insert"' "G1 a dotted-string fact is no evidence for class D's insert"

# ── S: fix round 1 (the two reviews of c434dc34). Each [P] arm is RED on the pre-fix binary c434dc34 ─────────────────────────────────
#   S-F1 [P] the fact's scope is no type name: a C++ struct D is neither promoted into --for's dispatch by a Python string, nor demoted to a test double
#   S-F1t [G] twin: a type D that production really names still lists    S-B2 [P] loader= only where the constant's NAME reaches a sink's argument
#   S-B2t [G] twins: attribute, imported-bare and own-function-local joins keep their loader=    S-B3 [P] --callers defines every attribute it prints
#   S-B5 [P] a file name is no dotted path    S-B5t [G] a module named html still resolves    S-M1 [P] a container that is compared/asserted/raised/logged records nothing
SD="$TMP/sd"
for v in a b c; do
fx "$SD/$v/source.h" <<'P'
#pragma once
struct Source
{
    virtual ~Source() {}
    virtual int Fetch( int k ) = 0;
};
struct DiskSource : Source
{
    int Fetch( int k ) override;
};
P
fx "$SD/$v/loader.cc" <<'P'
#include "source.h"
struct Loader
{
    Source* src_;
    explicit Loader( Source* s ) : src_( s ) {}
    int Load( int k );
};
int Loader::Load( int k )
{
    int v = src_->Fetch( k );
    return v + 1;
}
int DiskSource::Fetch( int k )
{
    int doubled = k * 2;
    return doubled;
}
P
fx "$SD/$v/double.h" <<'P'
#pragma once
#include "source.h"
struct D : Source
{
    int Fetch( int k ) override { return k + 100; }
};
P
done
fx "$SD/a/main.cc" <<'P'
#include "source.h"
int RunAll() { DiskSource disk; return disk.Fetch( 1 ); }
P
fx "$SD/a/tests/loader_test.cc" <<'P'
#include "../double.h"
int TestLoad() { D f; return f.Fetch( 3 ); }
P
fx "$SD/a/settings.py" <<'P'
APPS = ["pkg.pg.Pg", "pkg.mem.Mem"]
P
fx "$SD/b/main.cc" <<'P'
#include "source.h"
int RunAll() { DiskSource disk; return disk.Fetch( 1 ); }
P
fx "$SD/b/tests/test_a.py" <<'P'
PATHS = ["a.b.C"]
def test_x():
    assert PATHS
P
fx "$SD/c/main.cc" <<'P'
#include "double.h"
int RunAll() { D disk; return disk.Fetch( 1 ); }
P
fx "$SD/c/settings.py" <<'P'
APPS = ["pkg.pg.Pg", "pkg.mem.Mem"]
P
for v in a b c; do run "$SD/$v" "$TMP/sd$v" '--for=Loader::Load src_->Fetch'; done
hasnt "$TMP/sda" 'n="D::Fetch"' "S-F1 a Python string is not a production use of the test double D"
has "$TMP/sda" 'test="1"' "S-F1 the double stays counted as a test double with the Python file present"
hasnt "$TMP/sdb" 'test="1"' "S-F1 a type D named by nothing is not turned into a test double by a Python string in a test"
has "$TMP/sdc" 'D::Fetch' "S-F1t a type D that production really names is still listed beside the Python strings"
RIPWIRE_NO_DOTTED_STRINGS=1 run "$SD/a" "$TMP/sdaoff" '--for=Loader::Load src_->Fetch'
python3 - "$TMP/sda" "$TMP/sdaoff" <<'PY'
import re,sys
a=open(sys.argv[1],encoding="utf-8").read(); b=open(sys.argv[2],encoding="utf-8").read()
n=lambda t: re.sub(r'(<!-- ripwire for dotted_strings:.*?-->)?<dotted_strings .*?</dotted_strings>','',re.sub(r' (at|est_tokens)="[^"]*"','',t),flags=re.S)
sys.exit(0 if n(a)==n(b) else 1)
PY
if [ $? = 0 ]; then ok "S-F1 the answer needs no RIPWIRE_NO_DOTTED_STRINGS: it equals the OFF answer apart from the element"; else no "S-F1 the Python string moved the C++ dispatch answer"; fi

B2="$TMP/b2"
fx "$B2/core/__init__.py" <<'P'
P
fx "$B2/core/apps.py" <<'P'
class CoreConfig:
    name = "core.plug.hook"
P
fx "$B2/core/plug/__init__.py" <<'P'
P
fx "$B2/core/plug/hook.py" <<'P'
def hook():
    return 1
P
fx "$B2/other/unrelated.py" <<'P'
from importlib import import_module
def resolve(name):
    return import_module(name)
P
fx "$B2/p/__init__.py" <<'P'
P
fx "$B2/p/t.py" <<'P'
def one(): return 1
def two(): return 2
def three(): return 3
def four(): return 4
def five(): return 5
def six(): return 6
def seven(): return 7
def eight(): return 8
def nine(): return 9
def ten(): return 10
def eleven(): return 11
P
fx "$B2/p/consts.py" <<'P'
from importlib import import_module
ONE = ["p.t.one"]
TWO = ["p.t.two"]
THREE = ["p.t.three"]
FOUR = ["p.t.four"]
FIVE = ["p.t.five"]
EIGHT = ["p.t.eight"]
NINE = ["p.t.nine"]
def comment_only(x):
    # ONE is documented here
    return import_module(x)
def doc_only(x):
    """see TWO."""
    return import_module(x)
def string_only(x):
    print("THREE is deprecated")
    return import_module(x)
def shadow(x):
    FOUR = x
    return import_module(FOUR)
def configure(logging_config):
    if logging_config:
        fn = import_module(logging_config)
    print(FIVE)
    return fn
def reaches(x):
    for path in EIGHT:
        import_module(path)
class Holder:
    ATTR = ["p.t.nine"]
def via_attr(h):
    return import_module(h.NINE)
class Holder2:
    SEL = ["p.t.eleven"]
def bare_sel():
    return import_module(SEL)
P
fx "$B2/p/other.py" <<'P'
from importlib import import_module
def load_other():
    return [import_module(q) for q in PLUGS]
P
fx "$B2/p/locals.py" <<'P'
from importlib import import_module
def build():
    loaders = ["p.t.six"]
    return find(loaders)
def find(loaders):
    if not loaders:
        raise ValueError("Invalid value in loaders configuration")
    return import_module(loaders)
def own():
    paths = ["p.t.seven"]
    for p in paths:
        import_module(p)
P
fx "$B2/p/conf.py" <<'P'
PLUGS = ["p.t.ten"]
P
fx "$B2/p/user.py" <<'P'
from importlib import import_module
from .conf import PLUGS
def load_all():
    return [import_module(p) for p in PLUGS]
P
for n in one two three four five six; do run "$B2" "$TMP/b2$n" "--callers=$n"; done
for n in one two three four five; do hasnt "$TMP/b2$n" 'loader=' "S-B2 --callers=$n: a comment, docstring, string, shadow or call-argument mention is no loader"; done
hasnt "$TMP/b2six" 'loader="find"' "S-B2 a function-local constant is joined by no other function (a word in an error string)"
run "$B2" "$TMP/b2seven" '--callers=seven'; has "$TMP/b2seven" 'loader="own"' "S-B2t a function-local constant joins the loop in its own function"
run "$B2" "$TMP/b2ten" '--callers=ten'; has "$TMP/b2ten" 'loader="load_all"' "S-B2t a bare name imported with from-import joins the sink it reaches through a comprehension"
if dsrows "$TMP/b2ten" | grep -qF 'loaders='; then no "S-B2 a function that spells PLUGS without importing it from the constant's module is a second loader"; else ok "S-B2 a function that spells PLUGS without importing it from the constant's module is no second loader"; fi
run "$B2" "$TMP/b2eight" '--callers=eight'; has "$TMP/b2eight" 'loader="reaches"' "S-B2t a same-file constant reaching a sink through a for target keeps its loader"
run "$B2" "$TMP/b2eleven" '--callers=eleven'; hasnt "$TMP/b2eleven" 'loader=' "S-B2 a class-level constant is reached by no bare name (only .NAME)"
run "$B2" "$TMP/b2hook" '--callers=hook'; hasnt "$TMP/b2hook" 'loader="resolve"' "S-B2 a parameter of the same spelling in a file that never imports the constant is no loader"
run "$B2" "$TMP/b2nine" '--callers=nine'; has "$TMP/b2nine" 'loader="via_attr"' "S-B2t an attribute NINE reaching a sink joins any constant of that name"

# S-B3: every attribute the default --callers element prints is defined in that answer
run "$B2" "$TMP/b3" '--callers=ten'
python3 - "$TMP/b3" <<'PY'
import re,sys
t=open(sys.argv[1],encoding="utf-8").read()
body=re.search(r'<dotted_strings sites="\d+".*?</dotted_strings>',t,re.S)
if not body: sys.exit(1)
legend=t.replace(body.group(0),'')
bad=[]
for tag in re.findall(r'<(dotted_strings|ds) ([^>]*)>',body.group(0)):
    for a in re.findall(r'(\w+)="',tag[1]):
        if not re.search(r'<%s [^>]*\b%s='%(tag[0],a),legend) and not re.search(r'\b%s='%a,legend): bad.append(tag[0]+"."+a)
print("undefined:",sorted(set(bad)))
sys.exit(0 if not bad else 1)
PY
if [ $? = 0 ]; then ok "S-B3 --callers defines every dotted_strings/ds attribute it prints in its own legend"; else no "S-B3 --callers prints an attribute with no legend clause"; fi

# S-D1: EVERY attribute the element can print is defined in the legend of the verb that prints it. legchk walks the printed
# attributes against the legend text: --callers' schema clauses (head or body of an element's clause), --for's own comment. Fixtures
# reach mod=, loaders= (over 3), a tests-only s= next=, tmpl= cand= cands=, sink=, loader= lp=, rows_capped= next=. A sweep at the end
# of this file runs it over every dotted answer this file produced, so a NEW attribute cannot go undefined.
legchk(){ python3 - "$1" <<'PY'
import re,sys
t=open(sys.argv[1],encoding="utf-8").read()
m=re.search(r'<dotted_strings sites="\d+".*?</dotted_strings>',t,re.S)
if not m: print("no element"); sys.exit(1)
legend=t[:m.start()]
bad=[]
forc=re.search(r'<!-- ripwire for dotted_strings:.*?-->',legend,re.S)
for tag,attrs in re.findall(r'<(dotted_strings|ds) ([^>]*)>',m.group(0)):
    for a in sorted(set(re.findall(r'(\w+)="',attrs))):
        if forc:
            ok=re.search(r'\b%s='%a,forc.group(0)) is not None
        else:
            ok=False
            heads=list(re.finditer(r'<(dotted_strings|ds) ([^>]*)>:',legend))
            for i,h in enumerate(heads):
                if h.group(1)!=tag: continue
                body=legend[h.end():(heads[i+1].start() if i+1<len(heads) else h.end()+500)]
                if re.search(r'\b%s='%a,h.group(2)) or re.search(r'\b%s='%a,body[:500]): ok=True
        if not ok: bad.append(tag+"."+a)
print("undefined:",sorted(set(bad)))
sys.exit(1 if bad else 0)
PY
}
lc(){ if legchk "$1" >"$1.lc" 2>&1; then ok "S-D1 $2: every attribute it prints is defined in its legend"; else no "S-D1 $2: $(tr '\n' ' ' <"$1.lc")"; fi }
run "$K" "$TMP/d1k3" '--callers=subfn';   lc "$TMP/d1k3" "--callers mod= (a whole module)"
has "$TMP/d1k3" 'mod="pkg/sub/__init__.py"' "S-D1 the mod= fixture prints mod="
run "$N6" "$TMP/d1n6" '--callers=thing';  lc "$TMP/d1n6" "--callers loaders= over 3"
has "$TMP/d1n6" 'loaders="4"' "S-D1 the over-3 fixture prints loaders="
run "$T" "$TMP/d1t2" '--callers=alone';   lc "$TMP/d1t2" "--callers tests-only s= next="
has "$TMP/d1t2" 'tests="1" s="pkg.mod.alone"' "S-D1 the tests-only fixture prints s="
run "$K" "$TMP/d1k1" '--callers=csrfproc'; lc "$TMP/d1k1" "--callers loader= lp="
run "$K" "$TMP/d1k2" '--callers=direct_thing'; lc "$TMP/d1k2" "--callers sink="
run "$K" "$TMP/d1k3f" '--for=subfn';      lc "$TMP/d1k3f" "--for mod="
run "$T" "$TMP/d1t2f" '--for=alone';      lc "$TMP/d1t2f" "--for tests-only s= next="
run "$N6" "$TMP/d1n6f" '--for=thing';     lc "$TMP/d1n6f" "--for loaders="

# S-D2: the loader= wording claims only what is known: a call whose TAIL name is an import sink's (the callee is not resolved)
has "$TMP/d1k1" 'tail name is an import sink' "S-D2 --callers loader= says tail name"
has "$TMP/k1" 'tail name is an import sink' "S-D2 --for loader= says tail name"

# S-D3 / S-D4 / S-D5 fixtures
B6="$TMP/b6"
fx "$B6/pkg6/__init__.py" <<'P'
P
fx "$B6/pkg6/t6.py" <<'P'
def tgt_same(): return 1
def tgt_true(): return 2
def tgt_px(): return 3
def tgt_rel(): return 4
def d4w(): return 5
def d4e(): return 6
def d4l(): return 7
def d4i(): return 8
def d4r(): return 9
def d4lz(): return 10
def d5t(): return 11
def d5u(): return 12
P
fx "$B6/a/conf.py" <<'P'
P_SAME = ["pkg6.t6.tgt_same"]
P_TRUE = ["pkg6.t6.tgt_true"]
P
fx "$B6/b/conf.py" <<'P'
P_SAME = ["elsewhere.thing"]
P
fx "$B6/pkgx/sub/__init__.py" <<'P'
PX = ["pkg6.t6.tgt_px"]
P
fx "$B6/other/three.py" <<'P'
from importlib import import_module
from b.conf import P_SAME
def sametail():
    return [import_module(p) for p in P_SAME]
P
fx "$B6/other/four.py" <<'P'
from importlib import import_module
from a.conf import P_TRUE
from pkgx.sub import PX
def truejoin():
    return [import_module(p) for p in P_TRUE]
def initjoin():
    return [import_module(p) for p in PX]
P
fx "$B6/rel/__init__.py" <<'P'
P
fx "$B6/rel/conf.py" <<'P'
PR = ["pkg6.t6.tgt_rel"]
P
fx "$B6/rel/use.py" <<'P'
from importlib import import_module
from .conf import PR
def reljoin():
    return [import_module(p) for p in PR]
P
fx "$B6/binders.py" <<'P'
from importlib import import_module
BW = ["pkg6.t6.d4w"]
BE = ["pkg6.t6.d4e"]
BL = ["pkg6.t6.d4l"]
BI = ["pkg6.t6.d4i"]
BR = ["pkg6.t6.d4r"]
TERN = ["pkg6.t6.d5t"]
TERN2 = ["pkg6.t6.d5u"]
def withas():
    with open("x") as BW:
        return import_module(BW)
def exc():
    try:
        pass
    except Exception as BE:
        return import_module(BE)
def lam():
    f = lambda BL: import_module(BL)
    return f
def locimp():
    from os.path import BI
    return import_module(BI)
def real():
    return import_module(BR)
def tern(a, b):
    return import_module(a if TERN else b)
def tern2(a, b):
    return import_module(TERN2 if a else b)
P
fx "$B6/lazy/__init__.py" <<'P'
P
fx "$B6/lazy/c.py" <<'P'
LZ = ["pkg6.t6.d4lz"]
P
fx "$B6/lazy/use.py" <<'P'
from importlib import import_module
def lazy():
    from lazy.c import LZ
    return [import_module(p) for p in LZ]
P
for n in tgt_same tgt_true tgt_px tgt_rel d4w d4e d4l d4i d4r d4lz d5t d5u; do run "$B6" "$TMP/b6$n" "--callers=$n"; done
hasnt "$TMP/b6tgt_same" 'loader=' "S-D3 from b.conf import P_SAME is not a/conf.py's P_SAME (the whole module, not its last segment)"
has "$TMP/b6tgt_true" 'loader="truejoin"' "S-D3t from a.conf import P_TRUE keeps its loader"
has "$TMP/b6tgt_px" 'loader="initjoin"' "S-D3t from pkgx.sub import (an __init__.py) keeps its loader"
has "$TMP/b6tgt_rel" 'loader="reljoin"' "S-D3t from .conf import keeps its loader"
hasnt "$TMP/b6d4w" 'loader=' "S-D4 a with-as name that spells a module constant is no loader"
hasnt "$TMP/b6d4e" 'loader=' "S-D4 an except-as name that spells a module constant is no loader"
hasnt "$TMP/b6d4l" 'loader=' "S-D4 a lambda parameter that spells a module constant is no loader"
hasnt "$TMP/b6d4i" 'loader=' "S-D4 a local import of another module's name is no loader of this file's constant"
has "$TMP/b6d4r" 'loader="real"' "S-D4t a name no statement binds still joins"
has "$TMP/b6d4lz" 'loader="lazy"' "S-D4t a function-local import of the constant's own module still joins"
hasnt "$TMP/b6d5t" 'loader=' "S-D5 a ternary condition decides, it does not flow"
has "$TMP/b6d5u" 'loader="tern2"' "S-D5t a ternary branch still flows"

# S-D6: the file-extension list: case-insensitive, and py/log/conf/sh
D6="$TMP/d6"
fx "$D6/web/__init__.py" <<'P'
P
fx "$D6/web/index.py" <<'P'
def py(): return 1
def HTML(): return 2
P
fx "$D6/web/cfg.py" <<'P'
A = ["web.index.py"]
B = ["web.index.HTML"]
P
run "$D6" "$TMP/d6py" '--callers=py'; hasnt "$TMP/d6py" 'tn="py"' "S-D6 web.index.py names a file, not the def py"
run "$D6" "$TMP/d6html" '--callers=HTML'; hasnt "$TMP/d6html" 'tn="HTML"' "S-D6 web.index.HTML names a file (upper case), not the def html"

B5="$TMP/b5"
fx "$B5/index.py" <<'P'
def html():
    return 1
P
fx "$B5/cfg.py" <<'P'
TEMPLATES = ["index.html"]
PAGE = "index.html"
P
fx "$B5/pkg/__init__.py" <<'P'
P
fx "$B5/pkg/html.py" <<'P'
def render(): return 1
P
fx "$B5/pkg/use.py" <<'P'
MODS = ["pkg.html"]
P
run "$B5" "$TMP/b5a" '--callers=html'
hasnt "$TMP/b5a" 'tn="html"' "S-B5 a file name (index.html) is not read as the definition html of index.py"
run "$B5" "$TMP/b5b" '--callers=render'
has "$TMP/b5b" 'mod="pkg/html.py"' "S-B5t a real module named html still resolves"

M1="$TMP/m1"
fx "$M1/m1/__init__.py" <<'P'
P
fx "$M1/m1/t.py" <<'P'
def tgt(): return 1
P
fx "$M1/neg1.py" <<'P'
import logging
log = logging.getLogger("x")
def f():
    log.info("%s", ["m1.t.tgt"])
    print(("m1.t.tgt", 1))
P
fx "$M1/neg2.py" <<'P'
def f(x):
    assert x == ("m1.t.tgt",)
    return x in {"m1.t.tgt"}
def g(x):
    raise ValueError(("m1.t.tgt",))
P
fx "$M1/twin.py" <<'P'
ALL = ["m1.t.tgt"]
P
run "$M1" "$TMP/m1a" '--callers=tgt'
dsrows "$TMP/m1a" > "$TMP/m1a.rows"
if [ "$( wc -l < "$TMP/m1a.rows" | tr -d ' ' )" = 1 ] && grep -qF 'p="twin.py"' "$TMP/m1a.rows"; then ok "S-M1 a container that is logged, printed, compared, asserted or raised records nothing; the plain list is the one row"; else no "S-M1 rows: $( tr '\n' ' ' < "$TMP/m1a.rows" )"; fi

# S-B4: the house container, not std::map
if grep -q 'std::map<' "$ROOT/src/fordottedstring.h"; then no "S-B4 std::map in src/fordottedstring.h"; else ok "S-B4 no std::map in src/fordottedstring.h"; fi
# S-U1: no ORDERED container keyed on string_view: libstdc++ 14's string_view ordering wraps an unsigned subtraction the sanitizer
# ignorelist does not cover (CI run 41124745324, mcpreloadasancheck, asan ubuntu); std::string keys are covered
if grep -Eq '(set|map)<[^;]*string_view' "$ROOT/src/fordottedstring.h"; then no "S-U1 an ordered container keyed on string_view in src/fordottedstring.h"; else ok "S-U1 no ordered container keyed on string_view in src/fordottedstring.h"; fi

# ── X ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
run "$K" "$TMP/k1b" '--for=csrfproc'
if cmp -s "$TMP/k1" "$TMP/k1b"; then ok "X1 deterministic"; else no "X1 two runs differ"; fi
# the capped element too: its attributes switch on no shared legend clause of the verb or --for (checklist 23)
minus(){ python3 - "$1" "$2" <<'PY'
import re,sys
a=open(sys.argv[1],encoding="utf-8").read(); b=open(sys.argv[2],encoding="utf-8").read()
s=re.sub(r'<(?:dotted_strings|ds) [^>]*>: .*?\. ','',a)   # the --callers legend layer's clauses for the element (S-B3)
s=re.sub(r'(<!-- ripwire for dotted_strings:.*?-->)?<dotted_strings .*?</dotted_strings>','',s,flags=re.S)
sys.exit(0 if s!=a and s==b else 1)
PY
}
RIPWIRE_NO_DOTTED_STRINGS=1 run "$C" "$TMP/c1off" '--for=thing'
if minus "$TMP/c1" "$TMP/c1off"; then ok "X4 --for capped: minus the element == OFF"; else no "X4 --for capped element moved other bytes"; fi
run "$C" "$TMP/c2" '--callers=thing'
RIPWIRE_NO_DOTTED_STRINGS=1 run "$C" "$TMP/c2off" '--callers=thing'
# the verb's legend layer documents a *_capped attribute it meets: that one present-only clause is the element's own
python3 - "$TMP/c2" <<'PY'
import sys
p=sys.argv[1]; a=open(p,encoding="utf-8").read(); c=" rows_capped=: 1 = cut."
sys.exit(0 if c in a and open(p,"w",encoding="utf-8").write(a.replace(c,"",1)) else 1)
PY
if [ $? = 0 ]; then ok "X4 --callers capped: the legend layer documents rows_capped="; else no "X4 --callers capped: rows_capped= clause missing"; fi
if minus "$TMP/c2" "$TMP/c2off"; then ok "X4 --callers capped: minus the element and its clause == OFF"; else no "X4 --callers capped element moved other bytes"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/k1" 2>/dev/null; then ok "X2 xmllint well-formed"; else no "X2 not well-formed"; fi
else
    ok "X2 SKIP xmllint absent"
fi
# X5 [P] (CR pre-pass 43b): a tests-only fact in the DEFAULT --callers legend splices the compact dictionary entry for `s=` into the header comment; its
# text said "a --grep= for it", a double hyphen in an XML comment, so the whole answer was ill-formed (RED on 506801bd)
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/d1t2" 2>/dev/null && xmllint --noout "$TMP/d1t2f" 2>/dev/null; then ok "X5 the tests-only s= next= answers (--callers, --for) are well-formed"; else no "X5 a tests-only answer is not well-formed XML ($( xmllint --noout "$TMP/d1t2" 2>&1 | head -1 | cut -c1-120 ))"; fi
else
    ok "X5 SKIP xmllint absent (the always-on check below still runs)"
fi
if python3 - "$TMP/d1t2" "$TMP/d1t2f" <<'PY'
import re,sys
bad=[c for p in sys.argv[1:] for c in re.findall(r'<!--(.*?)-->',open(p,encoding="utf-8").read(),re.S) if "--" in c]
sys.exit(1 if bad else 0)
PY
then ok "X5 no -- inside any comment of the tests-only answers (needs no xmllint)"; else no "X5 a tests-only answer's comment holds --"; fi
if python3 - "$TMP/k1" <<'PY'
import re,sys
m=re.search(r'<!-- ripwire for dotted_strings:(.*?)-->',open(sys.argv[1],encoding="utf-8").read(),re.S)
sys.exit(0 if m and "--" not in m.group(1) else 1)
PY
then ok "X3 no -- inside the legend comment"; else no "X3 legend comment missing or holds --"; fi

# S-D1 sweep: every dotted answer this file produced defines every attribute it prints (c2 is rewritten by X4 above)
swept=0; sweepbad=""
for f in "$TMP"/*; do
    case "$f" in *.err|*.lc|"$TMP/c2"|*off) continue;; esac
    [ -f "$f" ] && grep -q '<dotted_strings sites=' "$f" 2>/dev/null || continue
    swept=$((swept+1))
    legchk "$f" >"$f.lc" 2>&1 || sweepbad="$sweepbad $(basename "$f"):$(tr '\n' ' ' <"$f.lc")"
done
if [ "$swept" -ge 20 ] && [ -z "$sweepbad" ]; then ok "S-D1 sweep: $swept dotted answers define every attribute they print"; else no "S-D1 sweep ($swept answers):$sweepbad"; fi

[ "$fail" = 0 ] && echo "dottedstringcheck: PASS" || echo "dottedstringcheck: FAIL"
exit "$fail"

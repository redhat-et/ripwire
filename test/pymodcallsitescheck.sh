#!/usr/bin/env bash
# pymodcallsitescheck.sh — PY-MOD-CALL-SITES: `from p import y` binds y to p's SUBMODULE (p/y.py, p/y/__init__.py) when p's own
# namespace does not bind y, so `y.f()` is a call of that module's module-scope f (graph.h Rule 2d, ExternalVetoTables::submoduleBindFile).
# Accepted spellings: `from . import y`, `from .. import y`, `from .sub import y`, `from pkg import y`, `from pkg import y as z`
# (and `import pkg.y as y`, which Rule 2d already read). Withheld, and counted as declined_calls=, never picked: the package binds y
# itself, y is rebound or bound to two modules, the submodule writes its namespace dynamically or defines f conditionally, f is not a
# module-scope def there (a re-export, a method namesake). A local or parameter named y is never the module.
# Fixtures are built at runtime. usage: bash test/pymodcallsitescheck.sh [BIN]   (BIN falls back to RIPWIRE_BIN, then build/ripwire)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-${RIPWIRE_BIN:-$HERE/../build/ripwire}}
case "$BIN" in /*) ;; *) BIN=$PWD/$BIN ;; esac
echo "pymodcallsitescheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "pymodcallsitescheck: no binary at $BIN"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "pymodcallsitescheck: python3 required"; exit 2; }
T=$(mktemp -d "${TMPDIR:-/tmp}/pymodcallsitescheck.XXXXXX")
trap 'rm -rf "$T"' EXIT
fail=0
w() { mkdir -p "$(dirname "$1")"; printf '%b' "$2" > "$1"; }
# row ID CALLEE PATH CALLER WANT: in `--callers=CALLEE`, the caller row CALLER at file PATH is `proven` (no via), `name` (via="name")
# or `none`; WANT `declined` = no such row AND the header counts at least one declined call. A run that exits nonzero or prints no
# schema is `failed-run`, an answer with no CALLEE definition (defs="0") is `no-callee`: neither passes any arm.
row() {
    local id=$1 callee=$2 path=$3 caller=$4 want=$5 got out rc
    out=$( cd "$P" && "$BIN" "$P" "--callers=$callee" --no-cache --legend=compact </dev/null 2>/dev/null )
    rc=$?
    if [ "$rc" != 0 ]; then
        got="failed-run"
    else
        got=$( printf '%s' "$out" | python3 -I -c '
import re,sys
path,name,want=sys.argv[1],sys.argv[2],sys.argv[3]
doc=sys.stdin.read()
if "schema=" not in doc: print("failed-run"); sys.exit()
d=re.search(r" defs=\"([0-9]+)\"",doc)
if not d or d.group(1)=="0": print("no-callee"); sys.exit()
got="none"
for m in re.finditer(r"<s [^>]*>",doc):
    t=m.group(0)
    n=re.search(r" n=\"([^\"]*)\"",t); p=re.search(r" p=\"([^\":]*)",t)
    if n and p and p.group(1)==path and (n.group(1)==name or n.group(1).endswith("."+name)):
        got="name" if " via=\"name\"" in t else "proven"
dc=re.search(r" declined_calls=\"([0-9]+)\"",doc)
if want=="declined" and got=="none" and dc and int(dc.group(1))>0: got="declined"
print(got)' "$path" "$caller" "$want" )
    fi
    if [ "$got" = "$want" ]; then echo "PASS $id"; else echo "FAIL $id --callers=$callee row $path:$caller want $want got $got"; fail=1; fi
}

P=$T/py
w "$P/app/__init__.py" ''
w "$P/app/boot.py" 'def setup_a(x):\n    return x\n\ndef setup_b(x):\n    return x\n\ndef setup_c(x):\n    return x\n\ndef setup_h(x):\n    return x\n\ndef setup_local(x):\n    return x\n\ndef setup_tc(x):\n    return x\n\ndef setup_rebind(x):\n    return x\n\ndef setup_value(x):\n    return x\n\ndef setup_nest(x):\n    return x\n\ndef setup_late(x):\n    return x\n\nclass K:\n    def only_meth(self):\n        return 1\n'
w "$P/app/sub/__init__.py" ''
w "$P/app/sub/deep.py" 'def deep_f(x):\n    return x\n'
w "$P/app/use_a.py" 'from . import boot\n\ndef run_a():\n    return boot.setup_a(1)\n'
w "$P/app/use_b.py" 'from app import boot\n\ndef run_b():\n    return boot.setup_b(1)\n'
w "$P/app/use_c.py" 'import app.boot as boot\n\ndef run_c():\n    return boot.setup_c(1)\n'
w "$P/app/use_h.py" 'from app import boot as bt\n\ndef run_h():\n    return bt.setup_h(1)\n'
w "$P/app/use_d.py" 'from .sub import deep\n\ndef run_d():\n    return deep.deep_f(1)\n'
w "$P/app/sub/use_e.py" 'from .. import boot\n\ndef run_e():\n    return boot.setup_a(2)\n'
w "$P/app/use_nest.py" 'from . import boot\n\nclass Runner:\n    def go(self):\n        def inner():\n            return boot.setup_nest(1)\n        return inner()\n'
w "$P/app/use_late.py" 'def run_late():\n    return boot.setup_late(1)\n\nfrom . import boot\n'
w "$P/app/use_local.py" 'from . import boot\n\ndef run_local(boot):\n    return boot.setup_local(1)\n\ndef run_local2():\n    boot = make()\n    return boot.setup_local(2)\n'
w "$P/app/use_tc.py" 'from typing import TYPE_CHECKING\nif TYPE_CHECKING:\n    from . import boot\n\ndef run_tc():\n    return boot.setup_tc(1)\n'
w "$P/app/use_rebind.py" 'from . import boot\nboot = object()\n\ndef run_rebind():\n    return boot.setup_rebind(1)\n'
w "$P/app/use_value.py" 'from . import boot\n\ndef run_value():\n    cb = boot.setup_value\n    return cb\n'
w "$P/app/use_meth.py" 'from . import boot\n\ndef run_meth():\n    return boot.only_meth()\n'
w "$P/app/boot2.py" 'from . import use_circ\n\ndef circ_f(x):\n    return use_circ.circ_g(x)\n'
w "$P/app/use_circ.py" 'from . import boot2\n\ndef circ_g(x):\n    return x\n\ndef run_circ():\n    return boot2.circ_f(1)\n'
# a submodule named like a stdlib module and a builtin-method name: the in-tree file still answers
w "$P/app/json.py" 'def dumps(x):\n    return x\n'
w "$P/app/use_json.py" 'from . import json\n\ndef run_json():\n    return json.dumps(1)\n'
# a second def of setup_a in a sibling module: a file-qualified --callers names only its own callers (CodeRabbit review 5745701293)
w "$P/app/boot_alt.py" 'def setup_a(x):\n    return x\n'
w "$P/app/use_alt.py" 'from . import boot_alt\n\ndef run_alt():\n    return boot_alt.setup_a(1)\n'
# two bindings of one name to two modules: neither is the receiver
w "$P/app/other.py" 'def two_f(x):\n    return x\n'
w "$P/app/two.py" 'def two_f(x):\n    return x\n'
w "$P/app/use_two.py" 'import app.other as two\nfrom . import two\n\ndef run_two():\n    return two.two_f(1)\n'
# the package's own `from . import y` binds y to the same submodule: still proven
w "$P/self/__init__.py" 'from . import mod\n'
w "$P/self/mod.py" 'def self_f(x):\n    return x\n'
w "$P/use_self.py" 'from self import mod\n\ndef run_self():\n    return mod.self_f(1)\n'
# ambiguous: the package binds the name x itself AND submodule amb/x.py exists
w "$P/amb/__init__.py" 'from other_pkg.thing import x\n'
w "$P/amb/x.py" 'def x_f(v):\n    return v\n'
w "$P/other_pkg/__init__.py" ''
w "$P/other_pkg/thing.py" 'def x_f(v):\n    return v\n'
w "$P/use_amb.py" 'from amb import x\n\ndef run_amb():\n    return x.x_f(1)\n'
# a package `__getattr__` answers `from p import y` before the submodule loads
w "$P/lazy/__init__.py" 'def __getattr__(name):\n    return None\n'
w "$P/lazy/m.py" 'def lazy_f(v):\n    return v\n'
w "$P/other_pkg/lazy2.py" 'def lazy_f(v):\n    return v\n'
w "$P/use_lazy.py" 'from lazy import m\n\ndef run_lazy():\n    return m.lazy_f(1)\n'
# dynamic submodules: `def __getattr__` beside an unconditional def (PEP 562: the def answers), a `globals()` write, a conditional def
w "$P/dyn/__init__.py" ''
w "$P/dyn/gmod.py" 'def dyn_f(v):\n    return v\n\ndef __getattr__(name):\n    return dyn_f\n'
w "$P/dyn/wmod.py" 'def dyn_w(v):\n    return v\nglobals()["dyn_w"] = len\n'
w "$P/dyn/cmod.py" 'import os\nif os.name == "nt":\n    def dyn_c(v):\n        return v\nelse:\n    dyn_c = len\n'
w "$P/dyn/smod.py" 'def dyn_s(v):\n    return v\n\ntry:\n    from _speedups import *\nexcept ImportError:\n    pass\n'
w "$P/other_pkg/dyn3.py" 'def dyn_w(v):\n    return v\n\ndef dyn_c(v):\n    return v\n\ndef dyn_s(v):\n    return v\n'
w "$P/use_dyn.py" 'from dyn import gmod, wmod, cmod, smod\n\ndef run_dyn():\n    return gmod.dyn_f(1)\n\ndef run_dynw():\n    return wmod.dyn_w(2)\n\ndef run_dync():\n    return cmod.dyn_c(1)\n\ndef run_dyns():\n    return smod.dyn_s(1)\n'
# a package __init__ that re-exports the function: not read through yet (a floor, declined)
w "$P/reexp/__init__.py" ''
w "$P/reexp/inner/__init__.py" 'from .impl import re_f\n'
w "$P/reexp/inner/impl.py" 'def re_f(v):\n    return v\n'
w "$P/use_re.py" 'from reexp import inner\n\ndef run_re():\n    return inner.re_f(1)\n'
# MF1 (rv-py-mod): the submodule's def of f must be f's ONLY module-scope binding — a later assignment, a named accelerator import under
# try, an import of f from another module (plain or `as`), a `del`, or a package submodule that re-imports f all withhold; the twin
# (an assignment of ANOTHER name from f, a decorated def) still proves
w "$P/app/m1a.py" 'def m1a_f(x):\n    return x\n\ndef m1a_g(x):\n    return x\n\nm1a_f = m1a_g\n'
w "$P/app/m1i.py" 'def m1i_f(x):\n    return x\n\ntry:\n    from _m1speed import m1i_f\nexcept ImportError:\n    pass\n'
w "$P/app/m1r.py" 'def m1r_f(x):\n    return x\n\nfrom ._m1impl import m1r_f\n'
w "$P/app/m1s.py" 'def m1s_f(x):\n    return x\n\nfrom ._m1impl import m1s_g as m1s_f\n'
w "$P/app/_m1impl.py" 'def m1r_f(x):\n    return x * 2\n\ndef m1s_g(x):\n    return x * 3\n'
w "$P/app/m1d.py" 'def m1d_f(x):\n    return x\n\ndel m1d_f\n'
w "$P/app/m1p/__init__.py" 'def m1p_f(x):\n    return x\n\nfrom .impl import m1p_f\n'
w "$P/app/m1p/impl.py" 'def m1p_f(x):\n    return x * 2\n'
w "$P/app/m1ok.py" 'import functools\n\ndef deco(fn):\n    @functools.wraps(fn)\n    def w(*a):\n        return fn(*a)\n    return w\n\ndef m1ok_f(x):\n    return x\n\nm1ok_alias = m1ok_f\n\n@deco\ndef m1ok_d(x):\n    return x\n'
w "$P/app/use_m1.py" 'from . import m1a, m1i, m1r, m1s, m1d, m1p, m1ok\n\ndef run_m1a():\n    return m1a.m1a_f(1)\n\ndef run_m1i():\n    return m1i.m1i_f(1)\n\ndef run_m1r():\n    return m1r.m1r_f(1)\n\ndef run_m1s():\n    return m1s.m1s_f(1)\n\ndef run_m1d():\n    return m1d.m1d_f(1)\n\ndef run_m1p():\n    return m1p.m1p_f(1)\n\ndef run_m1ok():\n    return m1ok.m1ok_f(1)\n\ndef run_m1okd():\n    return m1ok.m1ok_d(1)\n'
# MF2: a FUNCTION-LOCAL from-import binds a local, so it neither contests a module-level binding (base's `import a.b as mod` edge, a
# module-level `from . import x as rm`) nor makes a package bind the name (`def lazy(): from . import other as ly` in the __init__)
w "$P/app/real_i.py" 'def i_f(x):\n    return x\n'
w "$P/app/alt_i.py" 'def i_f(x):\n    return x\n'
w "$P/app/use_i.py" 'import app.real_i as mod\n\ndef run_itop():\n    return mod.i_f(1)\n\ndef run_iloc():\n    from . import alt_i as mod\n    return mod.i_f(2)\n'
w "$P/app/use_i3.py" 'from . import real_i as rm\n\ndef run_i3top():\n    return rm.i_f(4)\n\ndef run_i3loc():\n    from . import alt_i as rm\n    return rm.i_f(5)\n'
w "$P/lzp/__init__.py" 'def lazy():\n    from . import other as ly\n    return ly\n'
w "$P/lzp/ly.py" 'def ly_f(x):\n    return x\n'
w "$P/lzp/other.py" 'def ly_f(x):\n    return x\n'
w "$P/use_lzp.py" 'from lzp import ly\n\ndef run_lzp():\n    return ly.ly_f(1)\n'
# MF2 disclosed floor: `if TYPE_CHECKING: from . import y` / `else: import app.y_rt as y` — two module-scope bindings of y to two files,
# the guard is not read, so the call is declined and counted (base proved the runtime one; no wrong edge either way)
w "$P/app/tm_a.py" 'def t_f(x):\n    return x\n'
w "$P/app/tm_b.py" 'def t_f(x):\n    return x\n'
w "$P/app/use_t.py" 'from typing import TYPE_CHECKING\nif TYPE_CHECKING:\n    from . import tm_a as tm\nelse:\n    import app.tm_b as tm\n\ndef run_t():\n    return tm.t_f(1)\n'
# MF3: p/y.py beside p/y/__init__.py — Python's FileFinder binds the package
w "$P/app/dual.py" 'def dual_f(x):\n    return x\n'
w "$P/app/dual/__init__.py" 'def dual_f(x):\n    return x\n'
w "$P/app/use_dual.py" 'from . import dual\n\ndef run_dual():\n    return dual.dual_f(1)\n'
# MF5 (rv-py-mod2): a star import in the IMPORTER after `from p import y` may rebind y — when its in-tree source binds y at module
# scope (a def, an `as` alias's name), or when it is outside the tree (it may bind anything). Twins keep the edge: a star whose source
# binds y only inside a function or not at all, a star BEFORE the from-import (the from-import wins at run time), an outside star before it
for k in n12 n13 n14 n15 n16 n17 n18; do w "$P/sp/$k.py" "def ${k}_f():\n    return 1\n"; done
w "$P/sp/__init__.py" ''
w "$P/sp/other12.py" 'def n12():\n    return 3\n'
w "$P/sp/other13.py" 'def n13():\n    return 3\n'
w "$P/sp/other14.py" 'def nz():\n    return 3\n'
w "$P/sp/consts.py" 'LIMIT = 3\n\ndef helper():\n    n15 = 2\n    return n15\n'
w "$P/use_sp.py" 'from sp.other13 import *\nfrom tkinter import *\nfrom sp import n12, n13, n15, n16\nfrom sp import n14 as nz\nfrom sp.consts import *\nfrom sp.other12 import *\nfrom sp.other14 import *\n\ndef run_n12():\n    return n12.n12_f()\n\ndef run_n13():\n    return n13.n13_f()\n\ndef run_n14():\n    return nz.n14_f()\n\ndef run_n15():\n    return n15.n15_f()\n\ndef run_n16():\n    return n16.n16_f()\n'
w "$P/use_sp2.py" 'from sp import n17\nfrom tkinter import *\n\ndef run_n17():\n    return n17.n17_f()\n'
w "$P/sp/use_rel.py" 'from . import n18\nfrom .other18 import *\n\ndef run_n18():\n    return n18.n18_f()\n'
w "$P/sp/other18.py" 'from . import n13 as n18\n'
# MF7 (rv-py-mod3): an earlier star is skipped only when the from-import always runs. A from-import under `if`/`else`, `except`, a loop
# or a one-line `if` may not run, so a star before it that binds y declines (N19-N22); a conditional from-import with no star keeps it (N23)
for k in n19 n20 n21 n22 n23; do w "$P/sp/$k.py" "def ${k}_f():\n    return 1\n"; w "$P/sp/other${k#n}.py" "def ${k}():\n    return 3\n"; done
w "$P/use_c19.py" 'import sys\nif sys.argv:\n    from sp.other19 import *\nelse:\n    from sp import n19\n\ndef run_n19():\n    return n19.n19_f()\n'
w "$P/use_c20.py" 'try:\n    from sp.other20 import *\nexcept ImportError:\n    from sp import n20\n\ndef run_n20():\n    return n20.n20_f()\n'
w "$P/use_c21.py" 'from sp.other21 import *\nfor _ in ():\n    from sp import n21\n\ndef run_n21():\n    return n21.n21_f()\n'
w "$P/use_c22.py" 'import sys\nfrom sp.other22 import *\nif not sys.argv: from sp import n22\n\ndef run_n22():\n    return n22.n22_f()\n'
w "$P/use_c23.py" 'import sys\nif sys.argv:\n    from sp import n23\n\ndef run_n23():\n    return n23.n23_f()\n'
( cd "$P" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm fx ) || { echo "pymodcallsitescheck: fixture git init failed"; exit 2; }

# ---- S: the accepted spellings bind the call (S3 is the module form Rule 2d already read: the twin)
row S1.fromdot      setup_a  app/use_a.py      run_a     proven
row S2.frompkg      setup_b  app/use_b.py      run_b     proven
row S3.importas     setup_c  app/use_c.py      run_c     proven
row S4.frompkgas    setup_h  app/use_h.py      run_h     proven
row S5.fromdotsub   deep_f   app/use_d.py      run_d     proven
row S6.fromdotdot   setup_a  app/sub/use_e.py  run_e     proven
row S7.nested       setup_nest app/use_nest.py inner     proven
row S8.lateimport   setup_late app/use_late.py run_late  proven
row S9.circular1    circ_f   app/use_circ.py   run_circ  proven
row S9.circular2    circ_g   app/boot2.py      circ_f    proven
row S10.stdlibname  dumps    app/use_json.py   run_json  proven
row S11.pkgselfimp  self_f   use_self.py       run_self  proven
row S12.typecheck   setup_tc app/use_tc.py     run_tc    proven
row S13.getattrdef  dyn_f    use_dyn.py        run_dyn   proven
# ---- N: never the module, or withheld and counted (N10: a method namesake keeps the ladder's hedge, via="name", as at base)
row N1.param        setup_local app/use_local.py run_local  none
row N1.local        setup_local app/use_local.py run_local2 none
row N2.rebind       setup_rebind app/use_rebind.py run_rebind declined
row N3.value        setup_value app/use_value.py run_value none
row N4.ambiguous    x_f      use_amb.py        run_amb   declined
row N5.pkggetattr   lazy_f   use_lazy.py       run_lazy  declined
row N6.globals      dyn_w    use_dyn.py        run_dynw  declined
row N7.conddef      dyn_c    use_dyn.py        run_dync  declined
row N7.starimport   dyn_s    use_dyn.py        run_dyns  declined
row N8.reexport     re_f     use_re.py         run_re    declined
row N9.twomodules   two_f    app/use_two.py    run_two   declined
row N10.method      only_meth app/use_meth.py  run_meth  name
# ---- MF1: f's one module-scope binding (the twin M1.ok/M1.deco proves)
row M1.assign       app/m1a.py:m1a_f  app/use_m1.py run_m1a declined
row M1.tryimport    app/m1i.py:m1i_f  app/use_m1.py run_m1i declined
row M1.reimport     app/m1r.py:m1r_f  app/use_m1.py run_m1r declined
row M1.reimport2    app/_m1impl.py:m1r_f app/use_m1.py run_m1r none
row M1.asimport     app/m1s.py:m1s_f  app/use_m1.py run_m1s declined
row M1.del          app/m1d.py:m1d_f  app/use_m1.py run_m1d declined
row M1.pkgsub       app/m1p/__init__.py:m1p_f app/use_m1.py run_m1p declined
row M1.ok           app/m1ok.py:m1ok_f app/use_m1.py run_m1ok proven
row M1.deco         app/m1ok.py:m1ok_d app/use_m1.py run_m1okd proven
# ---- MF2: function-local from-imports do not poison
row M2.modform      app/real_i.py:i_f app/use_i.py   run_itop  proven
row M2.fromform     app/real_i.py:i_f app/use_i3.py  run_i3top proven
row M2.localnone    app/alt_i.py:i_f  app/use_i.py   run_iloc  none
row M2.pkglocal     lzp/ly.py:ly_f    use_lzp.py     run_lzp   proven
row M2.typecheck    app/tm_b.py:t_f   app/use_t.py   run_t     declined
# ---- MF3: the package directory wins
row M3.pkgfirst     app/dual/__init__.py:dual_f app/use_dual.py run_dual proven
row M3.notmodule    app/dual.py:dual_f app/use_dual.py run_dual none
# ---- MF5: a star import in the importer after the from-import (N12/N14/N17 declined; N13/N15/N16 twins proven)
row N12.starafter   sp/n12.py:n12_f   use_sp.py  run_n12  declined
row N13.starbefore  sp/n13.py:n13_f   use_sp.py  run_n13  proven
row N14.staralias   sp/n14.py:n14_f   use_sp.py  run_n14  declined
row N15.starnobind  sp/n15.py:n15_f   use_sp.py  run_n15  proven
row N16.extbefore   sp/n16.py:n16_f   use_sp.py  run_n16  proven
row N17.extafter    sp/n17.py:n17_f   use_sp2.py run_n17  declined
row N18.relimport   sp/n18.py:n18_f   sp/use_rel.py run_n18 declined
# ---- MF7: a conditional from-import after a star that binds y (N19-N22 declined; N23 and N13 twins proven)
row N19.ifelse      sp/n19.py:n19_f   use_c19.py run_n19  declined
row N20.tryexcept   sp/n20.py:n20_f   use_c20.py run_n20  declined
row N21.loop        sp/n21.py:n21_f   use_c21.py run_n21  declined
row N22.oneline     sp/n22.py:n22_f   use_c22.py run_n22  declined
row N23.condnostar  sp/n23.py:n23_f   use_c23.py run_n23  proven
# ---- S pinned by file (the arms above match the caller by name across every def of the callee name)
row S1.pinned       app/boot.py:setup_a app/use_a.py run_a proven
row S2.pinned       app/boot.py:setup_b app/use_b.py run_b proven
row S1.alt          app/boot_alt.py:setup_a app/use_alt.py run_alt proven
row S1.notalt       app/boot.py:setup_a app/use_alt.py run_alt none

# ---- X: PATH-FROM-UPSTREAM (src/forgraphverb.h applyPathFromUpstreamCut). In `--for=path from A to B`, a caller of A that a new
# from-import edge reaches (`core.alpha_entry()`) is upstream of the asked path: it never pushes A's own callees past the ranked head's
# cap (--pack-top-n=3 stands in for the default 40). The twin, the same words without `path from ... to`, keeps the plain ranking.
# forrow ID WANT_NOTE(1|0) WANT_NAMES FORBID_NAMES TASK: rc 0 and a schema, the note present or absent, every WANT name printed as a
# <d> row, no FORBID name printed as one
X=$T/pathfrom
w "$X/pkg/__init__.py" ''
w "$X/pkg/core.py" 'def alpha_entry(argv):\n    return beta_step(argv)\n\ndef beta_step(x):\n    return gamma_handle(x)\n\ndef gamma_handle(x):\n    return x\n'
w "$X/main_mod.py" 'from pkg import core\n\ndef run_alpha_entry_main():\n    """alpha entry handle"""\n    return core.alpha_entry([])\n\ndef alpha_entry_handle_twice():\n    """alpha entry handle"""\n    core.alpha_entry([])\n    return core.alpha_entry([1])\n'
( cd "$X" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm fx ) || { echo "pymodcallsitescheck: fixture git init failed"; exit 2; }
forrow() {
    local id=$1 note=$2 want=$3 forbid=$4 task=$5 out rc got
    local root=${FROOT:-$X}
    out=$( cd "$root" && "$BIN" "$root" --no-cache --legend=compact "--pack-top-n=${FTOPN:-3}" "--for=$task" </dev/null 2>/dev/null )
    rc=$?
    if [ "$rc" != 0 ]; then
        got="failed-run rc=$rc"
    else
        got=$( printf '%s' "$out" | python3 -I -c '
import re,sys
note,want,forbid=sys.argv[1],sys.argv[2].split(","),[x for x in sys.argv[3].split(",") if x]
doc=sys.stdin.read()
if "schema=" not in doc: print("failed-run no schema"); sys.exit()
names=set(re.findall(r"<d [^>]*? n=\"([^\"]*)\"",doc))
bad=[]
has="path from: " in doc
if has!=(note=="1"): bad.append("note=%d" % has)
bad+=["missing "+n for n in want if n not in names]
bad+=["printed "+n for n in forbid if n in names]
print(";".join(bad) or "ok")' "$note" "$want" "$forbid" )
    fi
    if [ "$got" = ok ]; then echo "PASS $id"; else echo "FAIL $id: $got"; fail=1; fi
}
forrow X1.pathfrom  1 alpha_entry,beta_step,gamma_handle run_alpha_entry_main,alpha_entry_handle_twice 'path from alpha_entry to the gamma handle'
forrow X2.twin      0 alpha_entry,alpha_entry_handle_twice,run_alpha_entry_main beta_step 'alpha_entry and the gamma handle'
forrow X3.unparsed  0 gamma_handle '' 'path from nothing_named_this to the gamma handle'
# X5-X10 (rv-py-mod2 MF6, S7): a 6-hop chain a_start -> c1..c4 -> c5_step -> b_end where c5_step and b_end call back to a_start, two
# upstream callers, 24 filler defs named like the endpoints, at --pack-top-n=6. A's whole forward reach keeps c5_step (X6, 5 hops out)
# and b_end (X5); B itself never moves even when no resolved edge joins it to A (X5b: b_orphan calls a_start, nothing reaches it).
# The rule fires only on a path question: not when the task also asks who calls A (X7), not on `path from` inside other prose (X8);
# the lead-ins `trace the call path from` / `what is the execution path from` fire (X9, X10); nor when a callers question follows (X7b, X7c)
XP=$T/pathchain
w "$XP/pkg/__init__.py" ''
w "$XP/pkg/chain.py" 'def a_start(x):\n    return c1_step(x)\n\ndef c1_step(x):\n    return c2_step(x)\n\ndef c2_step(x):\n    return c3_step(x)\n\ndef c3_step(x):\n    return c4_step(x)\n\ndef c4_step(x):\n    return c5_step(x)\n\ndef c5_step(x):\n    if x > 3:\n        return a_start(x - 1)\n    return b_end(x)\n\ndef b_end(x):\n    if x < 0:\n        return a_start(-x)\n    return x\n\ndef b_orphan(x):\n    return a_start(x)\n'
w "$XP/pkg/up.py" 'from pkg.chain import a_start\n\ndef upstream_one():\n    return a_start(1)\n\ndef upstream_two():\n    return a_start(2)\n'
python3 -I -c '
import sys
o=[]
for i in range(12):
    for n in ("b_end_variant_%d" % i, "a_start_variant_%d" % i, "b_orphan_variant_%d" % i): o+=["def %s(x):" % n,"    return x",""]
open(sys.argv[1],"w").write("\n".join(o)+"\n")' "$XP/pkg/filler.py"
( cd "$XP" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm fx ) || { echo "pymodcallsitescheck: fixture git init failed"; exit 2; }
FROOT=$XP FTOPN=6 forrow X5.bcallsa   1 b_end,a_start '' 'path from a_start to b_end'
FROOT=$XP FTOPN=6 forrow X6.deepchain 1 c5_step '' 'path from a_start to b_end'
FROOT=$XP FTOPN=6 forrow X5b.borphan  1 b_orphan '' 'path from a_start to b_orphan'
FROOT=$XP FTOPN=40 forrow X7.whocalls 0 upstream_one,upstream_two '' 'who calls a_start and what is the path from a_start to b_end'
# X7b/X7c (G5): `path from` opens the task and a callers question follows: the who-calls refusal (not the lead-in) keeps the callers
FROOT=$XP FTOPN=40 forrow X7b.thencalls 0 upstream_one,upstream_two '' 'path from a_start to b_end and who calls a_start'
FROOT=$XP FTOPN=40 forrow X7c.thenask   0 upstream_one,upstream_two '' 'path from a_start to b_end. Who calls a_start?'
FROOT=$XP FTOPN=6 forrow X8.prose     0 a_start '' 'strip the directory path from a_start() to shorten the log line'
FROOT=$XP FTOPN=6 forrow X9.trace     1 b_end,c5_step '' 'Trace the call path from a_start to b_end'
FROOT=$XP FTOPN=6 forrow X10.whatis   1 b_end,c5_step '' 'what is the execution path from a_start to b_end'
# X11 (S9): pack-task under the default compact legend carries the clause as its own data comment, beside the rows it moved
out=$( cd "$XP" && "$BIN" "$XP" --no-cache "--pack-task=path from a_start to b_end" </dev/null 2>/dev/null ); rc=$?
case "$rc:$out" in
    0:*schema=*'<!-- [path from: '[0-9]*' callers of the from endpoint scored below'*'n="b_end"'*) echo "PASS X11.packtask" ;;
    *) echo "FAIL X11.packtask: rc=$rc, no schema, no path-from data comment or no b_end row"; fail=1 ;;
esac
# X4: A reaches over 4096 symbols (70 x 70 fan-out): the walk stops, nothing moves, and the note says path_from_capped=1
XC=$T/pathcap
w "$XC/pkg/__init__.py" ''
python3 -I -c '
import sys
o=["def alpha_wide(argv):"]+["    hop_%d(argv)" % i for i in range(70)]+["    return argv",""]
for i in range(70):
    o+=["def hop_%d(x):" % i]+["    leaf_%d_%d(x)" % (i,k) for k in range(70)]+["    return x",""]
    for k in range(70): o+=["def leaf_%d_%d(x):" % (i,k),"    return x",""]
open(sys.argv[1],"w").write("\n".join(o)+"\n")' "$XC/pkg/wide.py"
w "$XC/main_wide.py" 'from pkg import wide\n\ndef run_alpha_wide_main():\n    """alpha wide"""\n    return wide.alpha_wide([])\n'
( cd "$XC" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm fx ) || { echo "pymodcallsitescheck: fixture git init failed"; exit 2; }
out=$( cd "$XC" && "$BIN" "$XC" --no-cache --legend=compact "--for=path from alpha_wide to the leaf" </dev/null 2>/dev/null ); rc=$?
case "$rc:$out" in
    0:*schema=*path_from_capped=1*) echo "PASS X4.capped" ;;
    *) echo "FAIL X4.capped: rc=$rc, no schema or no path_from_capped=1 note"; fail=1 ;;
esac

if [ "$fail" = 0 ]; then echo "pymodcallsitescheck: PASS"; else echo "pymodcallsitescheck: FAIL"; fi
exit "$fail"

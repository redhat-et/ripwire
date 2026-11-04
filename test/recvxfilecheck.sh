#!/usr/bin/env bash
# recvxfilecheck.sh — RECV-XFILE (receiverevidence.h ReceiverEvidence::receiverProof): a member call whose receiver's class is STATED in
# another file binds to the one class that answers the method. Stated types only, size-1 only:
#   RET  the receiver is a call (`c->getList().insert()`, `p.get_app().post()`), the inner call PROVEN to one function, whose declared
#        return type resolves to exactly one in-tree class that answers the method (bases included)
#   PROP a Python `@property` read (`pilot.app.post()`) whose return annotation names that class
#   FLD  a Python field assigned from an annotated parameter (`def __init__(self, app: App): self._app = app`)
# A C++ local initialised from a call stays untyped (C3: a FLOOR — C++ call-result typing is off since fix round 6's macro traps);
# Python and TS locals take the inner call's class. The two classes in each fixture share the method name, so name resolution alone hedges. U arms: an unproven inner call, a size-2 class
# name and an unannotated parameter keep today's via="name" hedge (or no edge) — never a guess.
# Fixtures are built at runtime. usage: bash test/recvxfilecheck.sh [BIN]   (BIN falls back to RIPWIRE_BIN, then build/ripwire)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-${RIPWIRE_BIN:-$HERE/../build/ripwire}}
case "$BIN" in /*) ;; *) BIN=$PWD/$BIN ;; esac
echo "recvxfilecheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "recvxfilecheck: no binary at $BIN"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "recvxfilecheck: python3 required"; exit 2; }
T=$(mktemp -d "${TMPDIR:-/tmp}/recvxfilecheck.XXXXXX")
trap 'rm -rf "$T"' EXIT
fail=0
w() { mkdir -p "$(dirname "$1")"; printf '%b' "$2" > "$1"; }
# row ID ROOT VERB CALLER PATH NAME WANT: the row of --VERB=CALLER at file PATH named NAME is `proven` (no via), `name` (via="name"), `none` (absent), or `notproven` (name or none).
# A run that exits nonzero or prints no schema is `failed-run`, and an answer that found no CALLER (defs="0") is `no-caller`: neither passes any arm.
row() {
    local id=$1 root=$2 verb=$3 caller=$4 path=$5 name=$6 want=$7 got out rc
    out=$( cd "$root" && "$BIN" "$root" "--$verb=$caller" --no-cache --legend=compact </dev/null 2>/dev/null )
    rc=$?
    if [ "$rc" != 0 ]; then
        got="failed-run"
    else
        got=$( printf '%s' "$out" | python3 -I -c '
import re,sys
path,name=sys.argv[1],sys.argv[2]
got="none"
doc=sys.stdin.read()
if "schema=" not in doc: print("failed-run"); sys.exit()
d=re.search(r" defs=\"([0-9]+)\"",doc)
if not d or d.group(1)=="0": print("no-caller"); sys.exit()
for m in re.finditer(r"<s [^>]*>",doc):
    t=m.group(0)
    n=re.search(r" n=\"([^\"]*)\"",t); p=re.search(r" p=\"([^\":]*)",t)
    if n and p and p.group(1)==path and (n.group(1)==name or n.group(1).endswith("::"+name) or n.group(1).endswith("."+name)):
        got="name" if " via=\"name\"" in t else "proven"
print(got)' "$path" "$name" )
    fi
    [ "$want" = notproven ] && { [ "$got" = name ] || [ "$got" = none ]; } && got=notproven
    if [ "$got" = "$want" ]; then echo "PASS $id"; else echo "FAIL $id $caller -> $path:$name want $want got $got"; fail=1; fi
}


# ---- C++: ProcessList and Column share `insert`; Context states ProcessList& in ctx.h, the calls live in use.cpp.
C=$T/cpp
w "$C/proc.h" '#pragma once\nclass ProcessList {\npublic:\n    void insert(int q);\n};\n'
w "$C/proc.cpp" '#include "proc.h"\nvoid ProcessList::insert(int q) {}\n'
w "$C/col.h" '#pragma once\nclass Column {\npublic:\n    void insert(int v);\n};\n'
w "$C/col.cpp" '#include "col.h"\nvoid Column::insert(int v) {}\n'
w "$C/box.h" '#pragma once\nnamespace a { class Box { public: void insert(int v); }; }\nnamespace b { class Box { public: void insert(int v); }; }\n'
w "$C/box.cpp" '#include "box.h"\nvoid a::Box::insert(int v) {}\nvoid b::Box::insert(int v) {}\n'
w "$C/ctx.h" '#pragma once\n#include "proc.h"\n#include "box.h"\nclass Context {\npublic:\n    ProcessList & getProcessList();\n    static Context & instance();\n    a::Box & getBox();\n};\n'
w "$C/ctx.cpp" '#include "ctx.h"\nProcessList & Context::getProcessList() { static ProcessList p; return p; }\nContext & Context::instance() { static Context c; return c; }\na::Box & Context::getBox() { static a::Box b; return b; }\n'
w "$C/use.cpp" '#include "ctx.h"\n#include "col.h"\nvoid runArrow(Context * c) { c->getProcessList().insert(1); }\nvoid runStatic() { Context::instance().getProcessList().insert(2); }\nvoid runLocal(Context * c) { auto & pl = c->getProcessList(); pl.insert(3); }\nvoid runUnknown(Context * c) { c->notInTree().insert(4); }\nvoid runSize2(Context * c) { c->getBox().insert(5); }\nvoid runCol(Column & k) { k.insert(6); }\n'
row C1.ret      "$C" callees runArrow   proc.cpp insert proven
row C1.not      "$C" callees runArrow   col.cpp  insert none
row C2.chain    "$C" callees runStatic  proc.cpp insert proven
row C2.not      "$C" callees runStatic  col.cpp  insert none
row C3.local    "$C" callees runLocal   proc.cpp insert notproven   # [FLOOR] a C++ LOCAL stays untyped (CallResultFamily C++ off, fix round 6)
row C3.not      "$C" callees runLocal   col.cpp  insert none
row U1.unknown  "$C" callees runUnknown proc.cpp insert notproven
row U2.size2    "$C" callees runSize2   box.cpp  insert notproven
row C4.typed    "$C" callees runCol     col.cpp  insert proven

# ---- Python: App and Widget share `post_message`; Pilot (pilot.py) and Driver (driver.py) state App, the calls live elsewhere.
P=$T/py
w "$P/app.py" 'class App:\n    def post_message(self, m):\n        return m\n'
w "$P/widget.py" 'class Widget:\n    def post_message(self, m):\n        return m\n'
w "$P/pilot.py" 'from app import App\n\nclass Pilot:\n    def __init__(self, app: App):\n        self._app = app\n\n    @property\n    def app(self) -> App:\n        return self._app\n\n    def get_app(self) -> App:\n        return self._app\n'
w "$P/driver.py" 'from app import App\n\nclass Driver:\n    def __init__(self, app: App, other):\n        self._app = app\n        self._other = other\n\n    def run(self):\n        self._app.post_message(1)\n\n    def run_other(self):\n        self._other.post_message(2)\n'
w "$P/use.py" 'from pilot import Pilot\n\ndef t_ret(pilot: Pilot):\n    pilot.get_app().post_message(1)\n\ndef t_prop(pilot: Pilot):\n    pilot.app.post_message(2)\n\ndef t_local(pilot: Pilot):\n    a = pilot.get_app()\n    a.post_message(3)\n\ndef t_untyped(x):\n    x.get_app().post_message(4)\n'
row P1.ret      "$P" callees t_ret      app.py    post_message proven
row P1.not      "$P" callees t_ret      widget.py post_message none
row P2.prop     "$P" callees t_prop     app.py    post_message proven
row P2.not      "$P" callees t_prop     widget.py post_message none
row P3.local    "$P" callees t_local    app.py    post_message proven
row P4.field    "$P" callees run        app.py    post_message proven
row P4.not      "$P" callees run        widget.py post_message none
row U3.untyped  "$P" callees t_untyped  app.py    post_message notproven
row U4.unann    "$P" callees run_other  app.py    post_message notproven

# ---- TypeScript: Router and Other share `match`; Hono (hono.ts) states Router, the calls live in use.ts.
S=$T/ts
w "$S/router.ts" 'export class Router {\n  match(m: string) { return m; }\n}\n'
w "$S/other.ts" 'export class Other {\n  match(m: string) { return m; }\n}\n'
w "$S/hono.ts" 'import { Router } from "./router";\nexport class Hono {\n  router!: Router;\n  getRouter(): Router { return this.router; }\n}\n'
w "$S/use.ts" 'import { Hono } from "./hono";\nexport function tRet(app: Hono) { return app.getRouter().match("a"); }\nexport function tField(app: Hono) { return app.router.match("b"); }\nexport function tLocal(app: Hono) { const r = app.getRouter(); return r.match("c"); }\nexport function tUntyped(app: any) { return app.getRouter().match("d"); }\n'
row S1.ret      "$S" callees tRet       router.ts match proven
row S1.not      "$S" callees tRet       other.ts  match none
row S2.field    "$S" callees tField     router.ts match proven
row S3.local    "$S" callees tLocal     router.ts match proven
row U5.untyped  "$S" callees tUntyped   router.ts match notproven

[ "$fail" = 0 ] && echo "recvxfilecheck: PASS" || echo "recvxfilecheck: FAIL"
exit "$fail"

#!/usr/bin/env bash
# importprovedsplitscheck.sh — IMPORT-PROVED-SPLITS: a call on same-named classes in two or more files, written with the class as
# its receiver (`C.m()`), binds the ONE class the caller file's import of C proves (src/receiverevidence.h pathOwners, the shared
# hook; its per-language resolver src/graph.h ImportProvedClass). Before: the receiver rule kept every same-named class's member,
# a split (or, with a third namesake in the caller's directory, that namesake alone).
#
# The fixtures are written at test time (no committed tree a whole-repo run would index). Rows are read from --pin-census.
#   TypeScript (fixture ts/):  a/uri.ts and b/uri.ts each `export class URI { static file(); static parse() }`
#     POSITIVE  app.ts      import { URI } from './a/uri'; URI.file()                       → a/uri.ts::file only
#               both.ts     import { URI } from a + { URI as URI2 } from b; URI.file(); URI2.parse()  → a's file, b's parse
#               shadow.ts   a closure inside the importing function: URI.parse()             → a's parse
#               tslocal/    app.ts as above beside a THIRD, unexported URI in local.ts      → a's file (base: local.ts's, unhedged)
#               tscascade/  const u = URI.file( 'x' ) (annotated `: URI`); u.toString()      → a's toString (base: no row); URI.file / URI.plain → a's
#     NEGATIVE  neither.ts  no import of URI                                                → still the split of both
#               viabarrel.ts import { URI } from './reexp' (export { URI } from './a/uri')   → still the split (a re-export is not followed)
#     (each arm below imports a's URI AND b's as U2, so a pin to a's would show)
#               shadow.ts   namespace N { const URI: any = U2; URI.file() }                 → still the split (FC3 shadow span; guard off: a's)
#               tsshadow/   const X = class URI { static go() { URI.file() } }              → still the split (guard off: a's)
#               shadow.ts   a parameter named URI: URI.file()                               → declined (dc row), never bound
#               loose.ts    this.u.file() / v.file() / URI.inner.file()                     → declined (dc rows), never bound
#               tscascade/  const w = URI.plain( 'y' ) (no return annotation); w.toString()  → declined (dc row): nothing types w
#               tslocal/local.ts  the class of the caller's own file                       → its own file's file, unchanged
#               ren.ts      import { helper as h }; h()                                     → the renamed import still pins (mech import)
#   Python (fixture py/):  pa/client.py and pb/client.py each `class Client: @staticmethod make()`; pk/timer.py and pk/events.py each `class Timer`
#     POSITIVE  app.py      from pa.client import Client; Client.make(1)                   → pa's make
#               renamed.py  from pb.client import Client as BClient; BClient.make(6)      → pb's make
#               pk/pump.py  from pk.timer import Timer (events.py imported too); Timer(..)  → pk/timer.py's Timer (prov import; base: split)
#               pylocal/    app.py as above beside a THIRD Client in local.py              → pa's make (base: local.py's, unhedged)
#               pyown/      BClient.make() beside the file's own class Client              → pb's make (base: the own class's, a locality pick)
#     NEGATIVE  neither.py  no import of Client                                            → still the split
#               star.py     `from pa.client import *` and `from pb.client import *`         → still the split
#               pk/nopump.py `from pk import timer` (a module, not the class): Timer(..)    → still the split
#               pk/repump.py from pk.retimer import Timer, where retimer.py rebinds Timer   → still the split (m's binding is not only the class)
#     (each arm below imports pa's Client AND pb's as BClient, so a pin to pa's would show)
#               shadow.py   [Client.make() for Client in xs] / lambda Client: Client.make()  → still the split (guard off: pa's)
#               shadow.py   def shadowed(Client): Client.make()                             → declined (dc row), never bound
#               loose.py    self.c.make() / v.make() / Client.inner.make()                  → declined (dc rows), never bound
#               pyalt/      try/except or if/else imports of pa's and pb's Client           → still the split (two modules bind the name)
#               pyassign/   module-scope `Client = BClient` after the import               → still the split (guard off: pa's)
#               pyown/      the caller file's own module-level `class Client`             → its own make (guard off: pa's)
#               pyfn/       from pk.ftimer import Timer, a def there (a class in 2 other files) → unchanged receiver-rule (guard off: mech import)
#               fn.py       from pc.other import helper; helper()                          → unchanged (a plain import pins only a class)
#               renamed.py  from pc.other import helper as h; h()                         → the renamed import still pins (mech import)
#               pylocal/local.py  the class of the caller's own file                       → its own make, unchanged
# Every negative arm counts the rows it read and fails when it read none (a vacuous arm proves nothing). The "guard off" arms were
# checked red against a build with the arm's guard removed (the shadow / local-binding test, the module-scope rebind test, the
# own-file test, the class-only test of a plain import); the declined arms never reach the import hook (a pin would add a caller row).
#
# Usage: bash test/importprovedsplitscheck.sh [BIN]     (default build/ripwire; exits non-zero on any failure)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "FAIL: no binary at $BIN"; exit 1; }
echo "importprovedsplitscheck: $( "$BIN" --version 2>/dev/null )"   # status: banner only; every arm below checks its own run

# ── fixtures ──
TS="$TMP/ts"; mkdir -p "$TS/a" "$TS/b" "$TS/c"
cat >"$TS/a/uri.ts" <<'EOF'
export class URI {
    static file( p: string ): URI { return new URI(); }
    static parse( p: string ): URI { return new URI(); }
}
EOF
cp "$TS/a/uri.ts" "$TS/b/uri.ts"
printf 'export function helper(): number { return 1; }\n' >"$TS/c/other.ts"
printf "export { URI } from './a/uri';\n" >"$TS/reexp.ts"
cat >"$TS/app.ts" <<'EOF'
import { URI } from './a/uri';
export function open(): URI {
    return URI.file( 'x' );
}
EOF
cat >"$TS/both.ts" <<'EOF'
import { URI } from './a/uri';
import { URI as URI2 } from './b/uri';
export function twice(): number {
    URI.file( 'x' );
    return URI2.parse( 'y' ) ? 1 : 0;
}
EOF
cat >"$TS/shadow.ts" <<'EOF'
import { URI } from './a/uri';
import { URI as U2 } from './b/uri';
export function shadowed( URI: any ): number {
    return URI.file( 's' ) ? 1 : 0;
}
export function inner(): number {
    const run = () => URI.parse( 'i' );
    return run() ? 1 : 0;
}
export namespace N {
    const URI: any = U2;
    export function go(): number { return URI.file( 'nv' ); }
}
EOF
TH="$TMP/tsshadow"; mkdir -p "$TH/a" "$TH/b"
cp "$TS/a/uri.ts" "$TH/a/"; cp "$TS/b/uri.ts" "$TH/b/"
cat >"$TH/classexpr.ts" <<'EOF'
import { URI } from './a/uri';
import { URI as U2 } from './b/uri';
export const X = class URI {
    static file( p: string ): number { return 1; }
    static go(): number { U2.parse( 'y' ); return URI.file( 'ce' ); }
};
EOF
cat >"$TS/neither.ts" <<'EOF'
import { helper } from './c/other';
export function none(): number {
    helper();
    return URI.file( 'z' ) ? 1 : 0;
}
EOF
cat >"$TS/viabarrel.ts" <<'EOF'
import { URI } from './reexp';
export function fromBarrel(): number {
    return URI.file( 'rb' ) ? 1 : 0;
}
EOF
cat >"$TS/loose.ts" <<'EOF'
import { URI } from './a/uri';
import { URI as U2 } from './b/uri';
class Holder {
    private u = pick();
    run(): void {
        this.u.file( 'q' );
        const v = pick();
        v.file( 'r' );
    }
}
function pick() { return Math.random() > 0.5 ? URI : U2; }
export function deep(): number {
    return URI.inner.file( 'd' ) ? 1 : 0;
}
EOF
cat >"$TS/ren.ts" <<'EOF'
import { helper as h } from './c/other';
export function viaRen(): number {
    return h();
}
EOF
TL="$TMP/tslocal"; mkdir -p "$TL/a" "$TL/b"
cp "$TS/a/uri.ts" "$TL/a/"; cp "$TS/b/uri.ts" "$TL/b/"; cp "$TS/app.ts" "$TL/"
cat >"$TL/local.ts" <<'EOF'
class URI {
    static file( p: string ): URI { return new URI(); }
}
export function same(): URI {
    return URI.file( 'l' );
}
EOF

PY="$TMP/py"; mkdir -p "$PY/pa" "$PY/pb" "$PY/pc" "$PY/pk"
touch "$PY/pa/__init__.py" "$PY/pb/__init__.py" "$PY/pc/__init__.py" "$PY/pk/__init__.py"
printf 'class Client:\n    @staticmethod\n    def make(n):\n        return Client()\n\n    def run(self):\n        return 1\n' >"$PY/pa/client.py"
cp "$PY/pa/client.py" "$PY/pb/client.py"
printf 'def helper():\n    return 1\n' >"$PY/pc/other.py"
printf 'from pa.client import Client\n\n\ndef open_one():\n    return Client.make(1)\n' >"$PY/app.py"
printf 'from pb.client import Client as BClient\nfrom pc.other import helper as h\n\n\ndef ren():\n    h()\n    return BClient.make(6)\n' >"$PY/renamed.py"
printf 'from pc.other import helper\n\n\ndef none():\n    helper()\n    return Client.make(2)\n' >"$PY/neither.py"
printf 'from pa.client import *\nfrom pb.client import *\n\n\ndef starred():\n    return Client.make(3)\n' >"$PY/star.py"
printf 'from pa.client import Client\nfrom pb.client import Client as BClient\n\n\ndef shadowed(Client):\n    return Client.make(10)\n\n\ndef comp(xs):\n    return [Client.make(11) for Client in xs]\n\n\ndef lam():\n    g = lambda Client: Client.make(12)\n    return g, BClient\n' >"$PY/shadow.py"
printf 'from pc.other import helper\n\n\ndef plain_fn():\n    return helper()\n' >"$PY/fn.py"
printf 'from pa.client import Client\nfrom pb.client import Client as BClient\n\n\nclass Holder:\n    def __init__(self, c):\n        self.c = c\n\n    def go(self, v):\n        self.c.make(4)\n        v.make(5)\n        Client.inner.make(12)\n        return BClient\n' >"$PY/loose.py"
printf 'class Timer:\n    def __init__(self, owner, delay):\n        self.owner = owner\n        self.delay = delay\n' >"$PY/pk/timer.py"
cp "$PY/pk/timer.py" "$PY/pk/events.py"; printf '\n\nclass Event:\n    pass\n' >>"$PY/pk/events.py"
cp "$PY/pk/timer.py" "$PY/pk/retimer.py"; printf '\n\nTimer = type("Timer", (Timer,), {})\n' >>"$PY/pk/retimer.py"
printf 'from pk import events\nfrom pk.events import Event\nfrom pk.timer import Timer\n\n\nclass Pump:\n    def set_timer(self, delay):\n        return Timer(self, delay), events, Event\n' >"$PY/pk/pump.py"
printf 'from pk import events\nfrom pk import timer\n\n\nclass NoPump:\n    def set_timer(self, delay):\n        return Timer(self, delay), events, timer\n' >"$PY/pk/nopump.py"
printf 'from pk import events\nfrom pk.events import Event\nfrom pk.retimer import Timer\n\n\nclass RePump:\n    def set_timer(self, delay):\n        return Timer(self, delay), events, Event\n' >"$PY/pk/repump.py"
PL="$TMP/pylocal"; mkdir -p "$PL"; cp -R "$PY/pa" "$PY/pb" "$PY/app.py" "$PL/"
printf 'class Client:\n    @staticmethod\n    def make(n):\n        return Client()\n\n\ndef same():\n    return Client.make(7)\n' >"$PL/local.py"

# (a) the call-result typing cascade: `const u = URI.file( 'x' )` types u by file's return annotation, so u.toString() binds a's
TC="$TMP/tscascade"; mkdir -p "$TC/a" "$TC/b"
cat >"$TC/a/uri.ts" <<'EOF'
export class URI {
    static file( p: string ): URI { return new URI(); }
    static plain( p: string ) { return new URI(); }
    toString(): string { return 'u'; }
}
EOF
cp "$TC/a/uri.ts" "$TC/b/uri.ts"
cat >"$TC/app.ts" <<'EOF'
import { URI } from './a/uri';
import { URI as U2 } from './b/uri';
export function cascade(): number {
    const u = URI.file( 'x' );
    const w = URI.plain( 'y' );
    const n = u.toString();
    const m = w.toString();
    return n.length + m.length + ( U2 ? 1 : 0 );
}
EOF
# (b) (c) two modules' Client under one name, or the caller's own module-scope binding of it
PA="$TMP/pyalt"; mkdir -p "$PA"; cp -R "$PY/pa" "$PY/pb" "$PA/"
printf 'try:\n    from pa.client import Client\nexcept ImportError:\n    from pb.client import Client\n\n\ndef f():\n    return Client.make(1)\n' >"$PA/viatry.py"
printf 'import sys\nif sys.version_info > (3,):\n    from pa.client import Client\nelse:\n    from pb.client import Client\n\n\ndef f():\n    return Client.make(2)\n' >"$PA/viaif.py"
PS="$TMP/pyassign"; mkdir -p "$PS"; cp -R "$PY/pa" "$PY/pb" "$PS/"
printf 'from pa.client import Client\nfrom pb.client import Client as BClient\n\nClient = BClient\n\n\ndef f():\n    return Client.make(3)\n' >"$PS/assign.py"
PO="$TMP/pyown"; mkdir -p "$PO"; cp -R "$PY/pa" "$PY/pb" "$PO/"
printf 'from pa.client import Client\nfrom pb.client import Client as BClient\n\n\nclass Client:\n    @staticmethod\n    def make(n):\n        return n\n\n\ndef f():\n    BClient.make(5)\n    return Client.make(4)\n' >"$PO/owncls.py"
# (d) Timer is a class in two files, but the module the caller imports it from defines it as a def
PF="$TMP/pyfn"; mkdir -p "$PF/pk"; touch "$PF/pk/__init__.py"
cp "$PY/pk/timer.py" "$PY/pk/events.py" "$PF/pk/"
printf 'def Timer(owner, delay):\n    return (owner, delay)\n' >"$PF/pk/ftimer.py"
printf 'from pk.ftimer import Timer\n\n\ndef go():\n    return Timer(None, 1)\n' >"$PF/pk/fpump.py"

# census DIR → $TMP/<name>.census (rc checked: a failed run would make every arm below vacuous)
census(){ ( cd "$1" && "$BIN" . --no-cache --pin-census="$TMP/$2.census" >/dev/null 2>"$TMP/$2.err" ); local rc=$?
          [ "$rc" -eq 0 ] || { no "$2: the --pin-census run failed (rc=$rc)"; return 1; }; return 0; }
# row NAME CALLER_FILE CALLEE LINE → "mech<TAB>targets" of the one C row (empty when none); the row count goes to $TMP/rows
row(){ awk -F'\t' -v f="$2" -v c="$3" -v l="$4" '$1=="C" && index($6,f"::")==1 && $7==c && $9==l { print $2"\t"$8; n++ } END { print n+0 > "'"$TMP"'/rows" }' "$TMP/$1.census"; }
targets(){ printf '%s' "$1" | cut -f2 | tr '|' '\n' | sed 's/#[0-9]*$//' | sort | tr '\n' ' ' | sed 's/ $//'; }
seen=0   # rows the negative arms read
# expect NAME FILE CALLEE LINE WANT_TARGETS [MECH] — the site's one row has exactly these targets (and this mechanism)
expect(){ local r; r=$( row "$1" "$2" "$3" "$4" ); local n; n=$( cat "$TMP/rows" ); local t; t=$( targets "$r" )
          if [ "$n" = 1 ] && [ "$t" = "$5" ] && { [ -z "${6:-}" ] || [ "$( printf '%s' "$r" | cut -f1 )" = "$6" ]; }; then ok "$1 $2:$4 $3 -> $5${6:+ ($6)}"
          else no "$1 $2:$4 $3: want $5${6:+ ($6)}, got rows=$n [$r]"; fi; }

census "$TS" ts || exit 1
census "$TL" tslocal || exit 1
census "$PY" py || exit 1
census "$PL" pylocal || exit 1
census "$TC" tscascade || exit 1
census "$PA" pyalt || exit 1
census "$PF" pyfn || exit 1
census "$PS" pyassign || exit 1
census "$PO" pyown || exit 1
census "$TH" tsshadow || exit 1
# declined NAME DIR CALLEE FILE:LINE... — each site is a declined call (one `<dc via="declined">` row of --callers) and has no census C
# row (a pin would add one; --callers' sites_at= lists a declined site too, so the census is what says "never bound")
declined(){ local nm="$1" d="$2" c="$3"; shift 3; local out="$TMP/declined.$c.$nm"
            "$BIN" "$d" --no-cache --callers="$c" --legend=compact >"$out" 2>/dev/null || { no "declined: the --callers=$c run on $nm failed"; return 0; }
            local p n
            for p in "$@"; do
                n=$( grep -o "<dc [^>]*p=\"$p\"[^>]*>" "$out" | grep -c 'via="declined"' )
                row "$nm" "${p%%:*}" "$c" "${p##*:}" >/dev/null
                if [ "$n" -eq 1 ] && [ "$( cat "$TMP/rows" )" = 0 ]; then ok "$nm $p $c stays declined (1 dc row, no C row)"
                else no "$nm $p $c: want 1 declined site and no C row, got $n dc rows, $( cat "$TMP/rows" ) C rows"; fi
                seen=$(( seen + n ))
            done; }

echo "── TypeScript: the import proves one class ──"
expect ts app.ts file 3 "a/uri.ts::file"
expect ts both.ts file 4 "a/uri.ts::file"
expect ts both.ts parse 5 "b/uri.ts::parse"
expect ts shadow.ts parse 7 "a/uri.ts::parse" receiver-rule
expect tslocal app.ts file 3 "a/uri.ts::file"
expect tscascade app.ts file 4 "a/uri.ts::file" receiver-rule
expect tscascade app.ts plain 5 "a/uri.ts::plain" receiver-rule
expect tscascade app.ts toString 6 "a/uri.ts::toString" receiver-rule

echo "── TypeScript: nothing proves one class, or the receiver is not the class ──"
neg(){ expect "$@"; seen=$(( seen + $( cat "$TMP/rows" ) )); }
neg ts neither.ts file 4 "a/uri.ts::file b/uri.ts::file" split
neg ts viabarrel.ts file 3 "a/uri.ts::file b/uri.ts::file" split
neg ts shadow.ts file 12 "a/uri.ts::file b/uri.ts::file" split
neg tsshadow classexpr.ts file 5 "a/uri.ts::file b/uri.ts::file" split
neg tslocal local.ts file 5 "local.ts::file"
neg ts ren.ts h 3 "c/other.ts::helper" import
declined ts "$TS" file shadow.ts:4 loose.ts:6 loose.ts:8 loose.ts:13
declined tscascade "$TC" toString app.ts:7

echo "── Python: the import proves one class ──"
expect py app.py make 5 "pa/client.py::Client::make"
expect py renamed.py make 7 "pb/client.py::Client::make"
expect py pk/pump.py Timer 8 "pk/timer.py::Timer::Timer" import
expect pylocal app.py make 5 "pa/client.py::Client::make"
expect pyown owncls.py make 12 "pb/client.py::Client::make" receiver-rule

echo "── Python: nothing proves one class, or the receiver is not the class ──"
neg py neither.py make 6 "pa/client.py::Client::make pb/client.py::Client::make" split
neg py star.py make 6 "pa/client.py::Client::make pb/client.py::Client::make" split
neg py pk/nopump.py Timer 7 "pk/events.py::Timer::Timer pk/retimer.py::Timer::Timer pk/timer.py::Timer::Timer" split
neg py pk/repump.py Timer 8 "pk/events.py::Timer::Timer pk/retimer.py::Timer::Timer" split
neg py shadow.py make 10 "pa/client.py::Client::make pb/client.py::Client::make" split
neg py shadow.py make 14 "pa/client.py::Client::make pb/client.py::Client::make" split
declined py "$PY" make shadow.py:6 loose.py:10 loose.py:11 loose.py:12
neg pyalt viatry.py make 8 "pa/client.py::Client::make pb/client.py::Client::make" split
neg pyalt viaif.py make 9 "pa/client.py::Client::make pb/client.py::Client::make" split
neg pyassign assign.py make 8 "pa/client.py::Client::make pb/client.py::Client::make" split
neg pyown owncls.py make 13 "owncls.py::Client::make" receiver-rule
neg pyfn pk/fpump.py Timer 5 "pk/ftimer.py::Timer" receiver-rule
neg py fn.py helper 5 "pc/other.py::helper" unique
neg py renamed.py h 6 "pc/other.py::helper" import
neg pylocal local.py make 8 "local.py::Client::make"

if [ "$seen" -ge 29 ]; then ok "the negative arms read $seen rows (premise: none vacuous)"; else no "the negative arms read only $seen rows (want >= 29)"; fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"

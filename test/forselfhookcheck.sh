#!/usr/bin/env bash
# forselfhookcheck.sh — THE SELF HOOK of a --for answer (lane self-hook; src/forselfhook.h): a served Python override names where its
# base classes reach it through self or cls, as a hedged list that adds no edge and costs no other byte of the answer.
#
# Fixtures are built here at runtime. Arms, in fixture order:
#   A   base + two overrides, one calling super(): the override names the base site and the base definition; a sibling's site never rides.
#   B   a hook only subclasses define, under hasattr: hook=1, guarded=1; a reference without a call is form=ref.
#   B2  getattr(self, "x"): a site with no reference at all, form=getattr; a commented-out one is none. B3: its line under decorators.
#   G   near misses of guarded=: hasattr on another receiver, on another name, and after the site.
#   N   two `Command`s in two modules with no relation: nothing crosses, in the site list or in defs=. N3: a by-name base: silent.
#   S   one definition with a base-class call, or an override with no site: silent.
#   T   an override on a test path is counted in test= and never named; a served test override carries no element.
#   V   self.x as an attribute (no method of that name; a write): silent.
#   C   cls.x() in a classmethod is recv=cls; a local named cls is no site.
#   I   a base spelled by a renamed import (absolute and relative): bases are read; an ambiguous module or a second binding leaves it silent.
#   K   a fourth site: shown=3 capped=1 next=--callers=. Non-test sites come first.
#   M   more served methods than the element carries: capped=1 on the wrapper.
#   E   the clause rides both legends and defines every attribute; RIPWIRE_NO_SELF_HOOK=1 is the answer minus the element and clause; est_tokens prices it.
#   L   JavaScript `this.x()` is not the family's row: silent. --json and --token-budget carry no element.
#   W   the name-exact auto body carries the element (W0); the MCP `for` twin carries the element and its clause on a name-exact route.
#   D   two runs are byte-identical.
# Usage:  bash test/forselfhookcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/forselfhookcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_SELF_HOOK
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "forselfhookcheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
F="$TMP/fx"

mk(){ mkdir -p "$( dirname "$F/$1" )"; cat >"$F/$1"; }
run(){ local d="$1"; shift; ( cd "$F/$d" && "$BIN" "$F/$d" --no-cache "$@" 2>/dev/null </dev/null ); }
hook(){ python3 -c 'import re,sys; print("".join(re.findall(r"<selfhooks [^>]*>.*?</selfhooks>", sys.stdin.read(), re.S)))'; }
has(){ printf '%s' "$1" | grep -qF -- "$2"; }
want(){ local id="$1" text="$2"; shift 2; local p; for p in "$@"; do has "$text" "$p" || { no "($id) expected [$p] in: [$text]"; return; }; done; ok "($id) ${#} attributes present"; }
lack(){ local id="$1" text="$2"; shift 2; local p; for p in "$@"; do has "$text" "$p" && { no "($id) did not expect [$p] in: [$text]"; return; }; done; ok "($id) ${#} absences hold"; }
silent(){ if [ -z "$2" ]; then ok "($1) silent"; else no "($1) expected no element: [$2]"; fi; }

# ── A ─────────────────────────────────────────────────────────────────────────────────────────────────────────
mk a/base.py <<'E'
class Base:
    def run(self):
        return self.step()

    def step(self):
        return 0
E
mk a/one.py <<'E'
from base import Base

class One(Base):
    def step(self):
        return super().step() + 1
E
mk a/two.py <<'E'
from base import Base

class Two(Base):
    def step(self):
        return 2

    def again(self):
        return self.step()
E
H="$( run a "--for=what calls One.step" | hook )"
want A1 "$H" 'n="One.step" p="one.py:4"' 'overrides="Base.step" op="base.py:5"' 'defs="3"' 'sites="1" shown="1" capped="0"' '<s n="Base.run" p="base.py:3"/>'
lack A2 "$H" 'Two.again' 'guarded' 'hook="1"' 'next='

# ── B ─────────────────────────────────────────────────────────────────────────────────────────────────────────
mk b/mix.py <<'E'
def wrap(f):
    return f

class Mix:
    def go(self):
        if hasattr(self, "before"):
            self.before()
        return 1

    def later(self):
        if hasattr(self, "before"):
            wrap(self.before)
E
mk b/x.py <<'E'
from mix import Mix

class X(Mix):
    def before(self):
        return "x"
E
mk b/y.py <<'E'
from mix import Mix

class Y(Mix):
    def before(self):
        return "y"
E
H="$( run b "--for=what calls X.before" | hook )"
want B1 "$H" 'n="X.before"' 'hook="1"' 'defs="2"' 'n="Mix.go" p="mix.py:7" guarded="1"' 'n="Mix.later" p="mix.py:12" form="ref" guarded="1"'
lack B1n "$H" 'overrides='

# ── B2 ────────────────────────────────────────────────────────────────────────────────────────────────────────
mk b2/mix.py <<'E'
class Mix:
    def go(self):
        h = getattr(self, 'before', None)
        # h = getattr(self, 'before', None) stays a comment
        return h() if h else None
E
mk b2/x.py <<'E'
from mix import Mix

class X(Mix):
    def before(self):
        return "x"
E
mk b2/y.py <<'E'
from mix import Mix

class Y(Mix):
    def before(self):
        return "y"
E
H="$( run b2 "--for=what calls X.before" | hook )"
want B2 "$H" 'sites="1"' 'n="Mix.go" p="mix.py:3" form="getattr" guarded="1"'

mk b3/mix.py <<'E'
def deco(f):
    return f

class Mix:
    @deco
    @deco
    def go(self):
        h = getattr(self, 'before', None)
        return h
E
mk b3/x.py <<'E'
from mix import Mix

class X(Mix):
    def before(self):
        return "x"

class Y(Mix):
    def before(self):
        return "y"
E
H="$( run b3 "--for=what calls X.before" | hook )"
want B3 "$H" 'n="Mix.go" p="mix.py:8" form="getattr"'

# ── G ─────────────────────────────────────────────────────────────────────────────────────────────────────────
mk g/mix.py <<'E'
class Mix:
    def other_recv(self, o):
        if hasattr(o, "before"):
            self.before()

    def other_name(self):
        if hasattr(self, "beforehand"):
            self.before()

    def after_site(self):
        self.before()
        return hasattr(self, "before")
E
mk g/x.py <<'E'
from mix import Mix

class X(Mix):
    def before(self):
        return "x"
E
mk g/y.py <<'E'
from mix import Mix

class Y(Mix):
    def before(self):
        return "y"
E
H="$( run g "--for=what calls X.before" | hook )"
want G1 "$H" 'n="Mix.other_recv" p="mix.py:4"' 'n="Mix.other_name" p="mix.py:8"' 'n="Mix.after_site" p="mix.py:11"'
lack G2 "$H" 'guarded'

# ── N ─────────────────────────────────────────────────────────────────────────────────────────────────────────
mk n/alpha/__init__.py </dev/null
mk n/beta/__init__.py </dev/null
mk n/alpha/base.py <<'E'
class Runner:
    def start(self):
        return self.handler()

    def handler(self):
        return 0
E
mk n/alpha/command.py <<'E'
from alpha.base import Runner

class Command(Runner):
    def handler(self):
        return 1
E
mk n/beta/command.py <<'E'
class Command:
    def boot(self):
        return self.handler()

    def handler(self):
        return 2
E
H="$( run n "--for=what calls alpha/command.py Command.handler" | hook )"
want N1 "$H" 'p="alpha/command.py:4"' 'overrides="Runner.handler"' 'defs="2"' 'n="Runner.start"'
lack N2 "$H" 'boot' 'beta/'

# no import names the base and two classes hold its name: the by-name edges prove neither, so the walk stops
mk n2/r1.py <<'E'
class Runner:
    def start(self):
        return self.handler()

    def handler(self):
        return 0
E
mk n2/r2.py <<'E'
class Runner:
    def begin(self):
        return self.handler()

    def handler(self):
        return 0
E
mk n2/d.py <<'E'
class Driver(Runner):
    def handler(self):
        return 1
E
silent N3 "$( run n2 "--for=what calls Driver.handler" | hook )"

# ── S ─────────────────────────────────────────────────────────────────────────────────────────────────────────
mk s/base.py <<'E'
class Base:
    def run(self):
        return self.only()

class Mid(Base):
    def only(self):
        return 1

class P:
    def solo(self):
        return 1

class Q(P):
    def solo(self):
        return 2
E
silent S1 "$( run s "--for=what calls Mid.only" | hook )"
silent S2 "$( run s "--for=what calls Q.solo" | hook )"

# ── T ─────────────────────────────────────────────────────────────────────────────────────────────────────────
mk t/base.py <<'E'
class Base:
    def run(self):
        return self.step()

    def step(self):
        return 0
E
mk t/real.py <<'E'
from base import Base

class Real(Base):
    def step(self):
        return 1
E
mk t/tests/test_base.py <<'E'
from base import Base

class Fake(Base):
    def step(self):
        return 2
E
H="$( run t "--for=what calls Real.step" | hook )"
want T1 "$H" 'n="Real.step"' 'defs="3" test="1"' 'n="Base.run"'
lack T2 "$H" 'Fake' 'test_base'
silent T3 "$( run t "--for=what calls Fake.step" | hook )"

# ── V ─────────────────────────────────────────────────────────────────────────────────────────────────────────
mk v/base.py <<'E'
class Base:
    def __init__(self):
        self.val = 1
        self.step = None

    def show(self):
        return self.val

    def step(self):
        return 0
E
mk v/d.py <<'E'
from base import Base

class D(Base):
    def val2(self):
        return self.val

    def step(self):
        return 1
E
H="$( run v "--for=what calls D.step" | hook )"
silent V1 "$H"
silent V2 "$( run v "--for=what calls D.val2" | hook )"

# ── C ─────────────────────────────────────────────────────────────────────────────────────────────────────────
mk c/base.py <<'E'
def pick():
    return Base

class Base:
    @classmethod
    def make(cls):
        return cls.build()

    def notclass(self):
        cls = pick()
        return cls.build()

    @classmethod
    def build(cls):
        return 0
E
mk c/d.py <<'E'
from base import Base

class D(Base):
    @classmethod
    def build(cls):
        return 1
E
H="$( run c "--for=what calls D.build" | hook )"
want C1 "$H" 'overrides="Base.build"' 'sites="1"' 'n="Base.make" p="base.py:7" recv="cls"'
lack C2 "$H" 'notclass'

# ── I ─────────────────────────────────────────────────────────────────────────────────────────────────────────
mk i/pkg/__init__.py </dev/null
mk i/pkg/core.py <<'E'
class Command:
    def serve(self):
        return self.handler()

    def handler(self):
        return 0
E
mk i/pkg/plug.py <<'E'
from pkg.core import Command as CoreCommand

class Command(CoreCommand):
    def handler(self):
        return 1
E
mk i/pkg/rel.py <<'E'
from .core import Command as Near

class Relative(Near):
    def handler(self):
        return 2
E
H="$( run i "--for=what calls pkg/plug.py Command.handler" | hook )"
want I1 "$H" 'p="pkg/plug.py:4"' 'overrides="Command.handler" op="pkg/core.py:5"' 'n="Command.serve" p="pkg/core.py:3"'
H="$( run i "--for=what calls Relative.handler" | hook )"
want I2 "$H" 'n="Relative.handler"' 'overrides="Command.handler" op="pkg/core.py:5"'
mk i2/lib1/core.py <<'E'
class Command:
    def serve(self):
        return self.handler()

    def handler(self):
        return 0
E
mk i2/lib2/core.py <<'E'
class Command:
    def boot(self):
        return self.handler()

    def handler(self):
        return 0
E
mk i2/plug.py <<'E'
from core import Command as CoreCommand

class Plugin(CoreCommand):
    def handler(self):
        return 1
E
silent I3 "$( run i2 "--for=what calls Plugin.handler" | hook )"
mk i3/pkg/core.py <<'E'
class Command:
    def serve(self):
        return self.handler()

    def handler(self):
        return 0
E
mk i3/pkg/other.py <<'E'
class Other:
    def handler(self):
        return 0
E
mk i3/plug.py <<'E'
from pkg.core import Command as Chosen
from pkg.other import Other as Chosen

class Plugin(Chosen):
    def handler(self):
        return 1
E
silent I4 "$( run i3 "--for=what calls Plugin.handler" | hook )"

# ── K ─────────────────────────────────────────────────────────────────────────────────────────────────────────
mk k/tests/test_k.py <<'E'
from base import Base

class FakeBase(Base):
    def a_test_site(self):
        return self.step()
E
mk k/base.py <<'E'
class Top:
    def a(self):
        return self.step()

    def b(self):
        return self.step()

    def c(self):
        return self.step()

    def e(self):
        return self.step()

class Base(Top):
    def step(self):
        return 0
E
mk k/d.py <<'E'
from base import Base

class D(Base):
    def step(self):
        return 1
E
H="$( run k "--for=what calls D.step" | hook )"
want K1 "$H" 'sites="4" shown="3" capped="1" next="--callers=D.step"' 'n="Top.a"' 'n="Top.b"' 'n="Top.c"'
lack K2 "$H" 'n="Top.e"'

# ── M ─────────────────────────────────────────────────────────────────────────────────────────────────────────
mk m/base.py <<'E'
class Base:
    def run(self):
        self.widgetalpha()
        self.widgetbeta()
        self.widgetgamma()
        self.widgetdelta()
        self.widgetomega()

    def widgetalpha(self):
        return 0

    def widgetbeta(self):
        return 0

    def widgetgamma(self):
        return 0

    def widgetdelta(self):
        return 0

    def widgetomega(self):
        return 0
E
mk m/d.py <<'E'
from base import Base

class WidgetD(Base):
    def widgetalpha(self):
        return 1

    def widgetbeta(self):
        return 1

    def widgetgamma(self):
        return 1

    def widgetdelta(self):
        return 1

    def widgetomega(self):
        return 1
E
H="$( run m "--for=widgetalpha widgetbeta widgetgamma widgetdelta widgetomega of WidgetD" | hook )"
want M1 "$H" 'total="5" shown="4" capped="1"'

# ── E ─────────────────────────────────────────────────────────────────────────────────────────────────────────
run a "--for=what calls One.step" --legend=full >"$TMP/full"
run a "--for=what calls One.step" >"$TMP/compact"
for a in total shown capped n p overrides op tied abstract hook defs test sites next recv form guarded; do
    grep -qE "; selfhooks ([^;]*[ (,])?$a=" "$TMP/full" || no "(E1) the full clause does not define $a="
    grep -qE "; selfhooks ([^;]*[ (,])?$a=" "$TMP/compact" || no "(E1) the compact clause does not define $a="
done
grep -q 'never an edge' "$TMP/full" && grep -q 'other subclasses may run' "$TMP/full" && grep -q 'other subclasses may run' "$TMP/compact" && ok "(E2) both clauses carry the hedge" || no "(E2) the hedge is missing from a clause"
( cd "$F/a" && RIPWIRE_NO_SELF_HOOK=1 "$BIN" "$F/a" --no-cache "--for=what calls One.step" 2>/dev/null </dev/null ) >"$TMP/off"
python3 - "$TMP/compact" "$TMP/off" <<'PY' && ok "(E3) the answer minus the element and its clause is the switched-off answer byte for byte; est_tokens grew" || no "(E3) a byte other than the element, the clause and est_tokens moved"
import re, sys
on, off = ( open( f, encoding="utf-8", errors="replace" ).read() for f in sys.argv[1:3] )
s = re.sub( r'<selfhooks [^>]*>.*?</selfhooks>', '', on, flags=re.S )
s = re.sub( r'; selfhooks total=.*?never an edge', '', s, flags=re.S )
e = lambda t: int( re.search( r'est_tokens="(\d+)"', t ).group( 1 ) )
m = lambda t: re.sub( r' est_tokens="\d+"', '', t )
sys.exit( 0 if m( s ) == m( off ) and e( on ) > e( off ) else 1 )
PY
if has "$( run a "--for=what calls One.step" --legend=full | hook )" '<selfhook n="One.step"'; then ok "(E4) the element rides with --legend=full"; else no "(E4) no element under --legend=full"; fi
# abstract=1 reads the base definition; tied= reads two bases at one depth
mk e/base.py <<'E'
class Left:
    def run(self):
        return self.step()

    def step(self):
        raise NotImplementedError

class Right:
    def step(self):
        return 0
E
mk e/d.py <<'E'
from base import Left, Right

class D(Left, Right):
    def step(self):
        return 1
E
H="$( run e "--for=what calls D.step" | hook )"
want E5 "$H" 'tied="1"' 'overrides=' 'n="Left.run"'
mk e2/base.py <<'E'
class Left:
    def run(self):
        return self.step()

    def step(self):
        raise NotImplementedError
E
mk e2/d.py <<'E'
from base import Left

class D(Left):
    def step(self):
        return 1
E
H="$( run e2 "--for=what calls D.step" | hook )"
want E6 "$H" 'abstract="1"' 'overrides="Left.step"'

# ── L ─────────────────────────────────────────────────────────────────────────────────────────────────────────
mk l/base.js <<'E'
class Base {
  run() { return this.step(); }
  step() { return 0; }
}
class D extends Base {
  step() { return 1; }
}
module.exports = { Base, D };
E
silent L1 "$( run l "--for=what calls D.step" | hook )"
if run a "--for=what calls One.step" --json | grep -q 'selfhook'; then no "(L2) --json carries the element"; else ok "(L2) --json carries no element"; fi
silent L3 "$( run a "--for=what calls One.step" --token-budget=4000 | hook )"

# ── W ─────────────────────────────────────────────────────────────────────────────────────────────────────────
mk w/base.py <<'E'
class BaseThing:
    def run_all(self):
        return self.process_item()

    def process_item(self):
        return 0
E
mk w/one.py <<'E'
from base import BaseThing

class SpecialThing(BaseThing):
    def process_item(self):
        return 1
E
run w "--for=what calls SpecialThing.process_item" >"$TMP/w"
if grep -q 'route="name-exact(' "$TMP/w" && has "$( hook <"$TMP/w" )" 'n="SpecialThing.process_item" p="one.py:4"'; then ok "(W0) the name-exact route's auto body carries the element"; else no "(W0) no element on the name-exact route"; fi
printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' "$F/w" "what calls SpecialThing.process_item" \
    | "$BIN" --mcp 2>/dev/null | python3 -c '
import json, sys
for line in sys.stdin:
    line = line.strip()
    if line.startswith( "{" ):
        d = json.loads( line )
        for c in d.get( "result", {} ).get( "content", [] ):
            print( c.get( "text", "" ) )
' >"$TMP/mcp"
if grep -q '<selfhook n="SpecialThing.process_item"' "$TMP/mcp" && grep -q 'ripwire for; selfhooks total=' "$TMP/mcp"; then ok "(W) the MCP for twin carries the element and its clause"; else no "(W) the MCP for twin lacks the element or its clause"; fi

# ── D ─────────────────────────────────────────────────────────────────────────────────────────────────────────
run a "--for=what calls One.step" >"$TMP/d2"
if cmp -s "$TMP/compact" "$TMP/d2"; then ok "(D) two runs are byte-identical"; else no "(D) two runs differ"; fi

if [ "$fail" -eq 0 ]; then echo "forselfhookcheck: PASS"; else echo "forselfhookcheck: FAIL"; fi
exit "$fail"

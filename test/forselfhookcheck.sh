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
#   K   a fourth site: shown=3 capped=1 next=--callers=. K3: a non-test site comes before a nearer test-path one.
#   U   an auto-body candidate the allowance cut carries no row.
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
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
F="$TMP/fx"

mk(){ mkdir -p "$( dirname "$F/$1" )"; cat >"$F/$1"; }
run(){ local d="$1" rc; shift; ( cd "$F/$d" && "$BIN" "$F/$d" --no-cache "$@" 2>/dev/null </dev/null ); rc=$?; [ "$rc" -eq 0 ] || printf '[[rc=%s]]' "$rc"; return 0; }
hook(){ python3 -c 'import re,sys; t=sys.stdin.read(); print("".join(re.findall(r"<selfhooks [^>]*/>|<selfhooks [^>]*>.*?</selfhooks>|\[\[rc=\d+\]\]", t, re.S)) + ("" if t.strip() else "[[empty]]"))'; }
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
    def other_recv(self, cell):
        if hasattr(cell, "before"):
            self.before()

    def foreign(self, cell):
        return cell.before()

    @classmethod
    def foreign_cls(cls, cell):
        return cell.before()

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
want G1 "$H" 'n="Mix.other_recv" p="mix.py:4"' 'n="Mix.other_name" p="mix.py:15"'
lack G2 "$H" 'guarded' 'Mix.foreign' 'foreign_cls'
want G3 "$( run g "--for=what calls Y.before" | hook )" 'sites="3"'

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

    def fire(self):
        return self.step()

    def step(self):
        return 0

    def set_step(self):
        self.step = 1

    def bump(self):
        self.step += 1
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
want V1 "$H" 'sites="1"' 'n="Base.fire"'
lack V1n "$H" '__init__' 'set_step' 'bump'
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
want K1 "$H" 'sites="4" shown="3" capped="1" next="--callers=Base.step"' 'n="Top.a"' 'n="Top.b"' 'n="Top.c"'
lack K2 "$H" 'n="Top.e"'
nx="$( printf '%s' "$H" | python3 -c 'import re,sys; print(re.search(r"n=.D.step.[^>]*? next=.([^\"]+).", sys.stdin.read()).group(1))' )"
if [ "$nx" = "--callers=Base.step" ] && has "$( run k "$nx" )" 'Top.e'; then ok "(K4) the printed next= ($nx) names the base's definition and lists the hidden site"; else no "(K4) the printed next= ($nx) is not --callers=Base.step or does not list Top.e"; fi
# K7: base and overrides in different directories, where a by-name hop does not bind: the printed next= still lists the hidden site
mk k7/lib/base.py <<'E2'
class Mix:
    def a(self):
        return self.hk()

    def b(self):
        return self.hk()

    def c(self):
        return self.hk()

    def e(self):
        return self.hk()

    def hk(self):
        return 0
E2
mk k7/a/x.py <<'E2'
from lib.base import Mix

class X(Mix):
    def hk(self):
        return 1
E2
mk k7/b/y.py <<'E2'
from lib.base import Mix

class Y(Mix):
    def hk(self):
        return 2
E2
H="$( run k7 "--for=what calls X.hk" | hook )"
nx="$( printf '%s' "$H" | python3 -c 'import re,sys; print(re.search(r"n=.X.hk.[^>]*? next=.([^\"]+).", sys.stdin.read()).group(1))' )"
if has "$( run k7 "$nx" )" 'lib/base.py:12'; then ok "(K7) the printed next= ($nx) lists the hidden site across directories"; else no "(K7) the printed next= ($nx) does not list lib/base.py:12"; fi
mk k5/base.py <<'E2'
class Base:
    def a(self):
        return self.hk()

    def b(self):
        return self.hk()

    def c(self):
        return self.hk()

    def e(self):
        return self.hk()
E2
mk k5/x.py <<'E2'
from base import Base

class X(Base):
    def hk(self):
        return 1
E2
mk k5/y.py <<'E2'
from base import Base

class Y(Base):
    def hk(self):
        return 2
E2
H="$( run k5 "--for=what calls X.hk" | hook )"
nx="$( printf '%s' "$H" | python3 -c 'import re,sys; print(re.search(r"n=.X.hk.[^>]*? next=.([^\"]+).", sys.stdin.read()).group(1))' )"
want K5 "$H" 'hook="1"' 'capped="1"' 'next="--uses=hk"'
if has "$( run k5 "$nx" )" 'base.py:12'; then ok "(K6) the hook form's next= ($nx) lists the hidden site"; else no "(K6) the hook form's next= ($nx) does not list base.py:12"; fi

mk k2/base.py <<'E'
class Root:
    def far(self):
        return self.step()

    def step(self):
        return 0
E
mk k2/tests/helpers.py <<'E'
from base import Root

class Helper(Root):
    def near(self):
        return self.step()
E
mk k2/d.py <<'E'
from tests.helpers import Helper

class Driven(Helper):
    def step(self):
        return 1
E
H="$( run k2 "--for=what calls Driven.step" | hook )"
want K3 "$H" 'sites="2"' '<s n="Root.far" p="base.py:3"/><s n="Helper.near"'

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

# an auto-body candidate the allowance cut is not served, so it carries no row
python3 - "$F/u" <<'PY'
import os, sys
root = sys.argv[1]; os.makedirs( root, exist_ok=True )
filler = "".join( f"        total += {i}\n" for i in range( 150 ) )
open( f"{root}/base.py", "w" ).write( "class Base:\n    def run_it(self):\n        return self.process_item()\n" )
for k in range( 6 ):
    open( f"{root}/impl{k}.py", "w" ).write( f"from base import Base\n\nclass Impl{k}(Base):\n    def process_item(self):\n        total = 0\n{filler}        return total\n" )
PY
run u "--for=how do impl classes process items" --auto-bodies >"$TMP/u"
python3 - "$TMP/u" <<'PY'
import re, sys
t = open( sys.argv[1], encoding="utf-8", errors="replace" ).read()
hooks = set( re.findall( r'<selfhook n="[^"]*" p="([^":]+):', t ) )
bodies = set( re.findall( r'<b [^>]*p="([^"]+)" n="process_item"', t ) )
sys.exit( 0 if hooks and hooks <= bodies and len( bodies ) < 6 else 1 )
PY
if [ $? -eq 0 ]; then ok "(U) every selfhook row names a body the answer printed, and one candidate was cut"; else no "(U) a selfhook row names a body the answer did not print, or the fixture no longer cuts one"; fi

# ── X (fix round 1) ────────────────────────────────────────────────────────────────────────────────────────────
# B1: a docstring, a string, a local class's method and a nested def are no sites; the one real call is, and an unguarded call under a docstring
# that mentions hasattr is not guarded. skipped= counts the nested def (spelled like a site, not proven).
mk x1/base.py <<'E'
class Base:
    def doc(self):
        """Fetches getattr(self, 'hk', None) and hasattr(self, 'hk')."""
        return 1

    def text(self):
        return "getattr(self, 'hk')"

    def local(self):
        class Local:
            def g(self):
                return getattr(self, 'hk', None)
        return Local

    def nested(self):
        def inner(self):
            return self.hk()
        return inner

    def plain(self):
        '''Older versions used hasattr(self, 'hk') here.'''
        return self.hk()
E
mk x1/d.py <<'E'
from base import Base

class X(Base):
    def hk(self):
        return 1

class Y(Base):
    def hk(self):
        return 2
E
H="$( run x1 "--for=what calls X.hk" | hook )"
want X1 "$H" 'sites="1"' 'n="Base.plain" p="base.py:22"' 'skipped="1"'
lack X1n "$H" 'Base.doc' 'Base.text' 'Base.local' 'Local' 'inner' 'getattr' 'guarded'
# B2: a rebound self, a loop or with target, a comprehension target, a lambda parameter and a static method are no sites; `good` is
mk x2/base.py <<'E'
class Base:
    def rebind(self):
        self = Helper()
        return self.hk()

    def loop(self, xs):
        for self in xs:
            self.hk()

    def comp(self, xs):
        return [self.hk() for self in xs]

    def lam(self):
        return lambda self: self.hk()

    def wth(self, xs):
        with xs as self:
            self.hk()

    @staticmethod
    def stat(self):
        return self.hk()

    def good(self):
        return self.hk()
E
mk x2/d.py <<'E'
from base import Base

class X(Base):
    def hk(self):
        return 1

class Y(Base):
    def hk(self):
        return 2
E
H="$( run x2 "--for=what calls X.hk" | hook )"
want X2 "$H" 'sites="1"' 'n="Base.good"' 'skipped="6"'
lack X2n "$H" 'Base.rebind' 'Base.loop' 'Base.comp' 'Base.lam' 'Base.wth' 'Base.stat'
# B3: the written name is rebound, a class of that name sits beside it, a plain import is the other reading, a nested class is no module member
for c in rebound local both nested; do
mk x3$c/m.py <<'E'
class Base:
    def run(self):
        return self.step()

    def step(self):
        return 0

class Outer:
    class Inner:
        def run(self):
            return self.step()

        def step(self):
            return 0
E
done
mk x3rebound/d.py <<'E'
from m import Base as B
B = other.Thing

class D(B):
    def step(self):
        return 1
E
mk x3local/d.py <<'E'
from m import Base as B

class B:
    pass

class E(B):
    def step(self):
        return 1
E
mk x3both/d.py <<'E'
try:
    from m import Base as B
except ImportError:
    from n import B

class F(B):
    def step(self):
        return 1
E
mk x3nested/d.py <<'E'
from m import Inner as I

class G(I):
    def step(self):
        return 1
E
mk x3clean/m.py <<'E'
class Base:
    def run(self):
        return self.step()

    def step(self):
        return 0
E
mk x3clean/d.py <<'E'
from m import Base as B

class H(B):
    def step(self):
        return 1
E
silent X3a "$( run x3rebound "--for=what calls D.step" | hook )"
silent X3b "$( run x3local "--for=what calls E.step" | hook )"
silent X3c "$( run x3both "--for=what calls F.step" | hook )"
silent X3d "$( run x3nested "--for=what calls G.step" | hook )"
want X3t "$( run x3clean "--for=what calls H.step" | hook )" 'n="H.step"' 'overrides="Base.step"' 'n="Base.run"'
# F3: an absolute module needs its whole path: `logging` is the standard library's, not a vendored compat/logging.py
mk x4/compat/logging.py <<'E'
class Handler:
    def emit_all(self):
        return self.emit()

    def emit(self):
        return 0
E
mk x4/app.py <<'E'
from logging import Handler as H

class Eff(H):
    def emit(self):
        return 1
E
silent X4 "$( run x4 "--for=what calls Eff.emit" | hook )"
# F5: depth is not the method resolution order. Two unrelated bases define it: candidates=, no winner. A definition whose class derives from the
# other definitions' classes IS provably the pick, whatever the depth.
mk x5/a.py <<'E'
class Root:
    def go(self):
        return self.step()

    def step(self):
        return 0

class L(Root):
    pass

class R:
    def step(self):
        return 1

class D(L, R):
    def step(self):
        return 2

class Mid(Root):
    def step(self):
        return 3

class T(Mid):
    def step(self):
        return 4
E
H="$( run x5 "--for=what calls D.step" | hook )"
want X5 "$H" 'n="D.step"' 'candidates="R.step,Root.step"'
lack X5n "$H" 'overrides=' 'tied='
mk x5b/a.py <<'E'
class Root:
    def go(self):
        return self.step()

    def step(self):
        return 0

class Mid(Root):
    def step(self):
        return 3

class T(Mid):
    def step(self):
        return 4
E
H="$( run x5b "--for=what calls T.step" | hook )"
want X5t "$H" 'n="T.step"' 'overrides="Mid.step"'
lack X5tn "$H" 'candidates=' 'tied='
# C3: a stub overload is not the definition, `except NotImplementedError` is not abstract
mk x6/a.py <<'E'
from typing import overload

class Base:
    @overload
    def hk(self, x: int) -> int: ...
    @overload
    def hk(self, x: str) -> str: ...
    def hk(self, x):
        try:
            return x
        except NotImplementedError:
            return None

    def run(self):
        return self.hk(1)

class D(Base):
    def hk(self, x):
        return 0
E
H="$( run x6 "--for=what calls D.hk" | hook )"
want X6 "$H" 'overrides="Base.hk" op="a.py:8"' 'n="Base.run"'
lack X6n "$H" 'tied=' 'abstract='
# F7: a site in a base on a test path says so
mk x7/tests/helpers.py <<'E'
class TestHelperBase:
    def go(self):
        return self.tested()

    def tested(self):
        return 0
E
mk x7/prod.py <<'E'
from tests.helpers import TestHelperBase

class Prod(TestHelperBase):
    def tested(self):
        return 1
E
want X7 "$( run x7 "--for=what calls Prod.tested" | hook )" '<s n="TestHelperBase.go" p="tests/helpers.py:3" test="1"/>'

# ── E ─────────────────────────────────────────────────────────────────────────────────────────────────────────
run a "--for=what calls One.step" --legend=full >"$TMP/full"
run a "--for=what calls One.step" >"$TMP/compact"
for a in total shown capped held n p overrides op candidates abstract hook defs test sites next skipped recv form guarded; do
    grep -qE "; selfhooks ([^;]*[ (,])?$a=" "$TMP/full" || no "(E1) the full clause does not define $a="
    grep -qE "; selfhooks ([^;]*[ (,])?$a=" "$TMP/compact" || no "(E1) the compact clause does not define $a="
done
if grep -q 'guarded=1 a hasattr or getattr on that name' "$TMP/full" && grep -q 'guarded=1 a hasattr or getattr on the name' "$TMP/compact" && grep -q 'text order only' "$TMP/full" && grep -q 'text order only' "$TMP/compact"; then ok "(E1g) both clauses define guarded= as a text-order fact"; else no "(E1g) a clause does not define guarded= as text order"; fi
if grep -q 'neither listed nor counted' "$TMP/full"; then ok "(E1f) the full clause discloses the silent floor"; else no "(E1f) the full clause does not disclose the silent floor"; fi
if grep -q 'never an edge' "$TMP/full" && grep -q 'other subclasses may run' "$TMP/full" && grep -q 'other subclasses may run' "$TMP/compact"; then ok "(E2) both clauses carry the hedge"; else no "(E2) the hedge is missing from a clause"; fi
( cd "$F/a" && RIPWIRE_NO_SELF_HOOK=1 "$BIN" "$F/a" --no-cache "--for=what calls One.step" 2>/dev/null </dev/null ) >"$TMP/off"
python3 - "$TMP/compact" "$TMP/off" <<'PY'
import re, sys
on, off = ( open( f, encoding="utf-8", errors="replace" ).read() for f in sys.argv[1:3] )
s = re.sub( r'<selfhooks [^>]*>.*?</selfhooks>', '', on, flags=re.S )
s = re.sub( r'; selfhooks total=.*?never an edge', '', s, flags=re.S )
e = lambda t: int( re.search( r'est_tokens="(\d+)"', t ).group( 1 ) )
m = lambda t: re.sub( r' est_tokens="\d+"', '', t )
sys.exit( 0 if m( s ) == m( off ) and e( on ) > e( off ) else 1 )
PY
if [ $? -eq 0 ]; then ok "(E3) the answer minus the element and its clause is the switched-off answer byte for byte; est_tokens grew"; else no "(E3) a byte other than the element, the clause and est_tokens moved"; fi
if has "$( run a "--for=what calls One.step" --legend=full | hook )" '<selfhook n="One.step"'; then ok "(E4) the element rides with --legend=full"; else no "(E4) no element under --legend=full"; fi
# abstract=1 reads the base definition; two unrelated bases define it: candidates=, no winner
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
want E5 "$H" 'candidates="Left.step,Right.step"' 'n="Left.run"'
lack E5n "$H" 'tied=' 'overrides=' 'abstract='
lack E5n "$H" 'tied=' 'overrides=' 'abstract='
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
H="$( run w "--for=what calls SpecialThing.process_item" --token-budget=40000 | hook )"
want L3 "$H" '<selfhooks held="budget" total="1"/>'
lack L3n "$H" '<selfhook n=' '<s n='

# ── W ─────────────────────────────────────────────────────────────────────────────────────────────────────────
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

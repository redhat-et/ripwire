#!/usr/bin/env bash
# regsitecheck.sh — REGISTRAR <reg> rows on a compact-route --for answer (src/regindex.h; model.h kRegLangs; the Python registrar
# facts of src/ingest_valuerefs.h paramRegFact).
#
# THE CONTRACT THIS PINS (arms tagged [P] are RED on the pre-change binary 3cb89d54; [G] arms are twins and near-miss negatives
# that hold on both binaries and must keep holding — PROCESS rule 4, no gate erosion). Fixtures are written at runtime.
#   P1 [P] Python module-variable signal `request_finished = Signal()` (Signal re-exported by a package __init__), whose
#          Signal.connect appends its parameter (inside a tuple) to self.receivers: the question names the key → ONE row
#          key="request_finished" by="Signal.connect" n="2" tests="1", r rows close_caches (`from m import K`) and
#          close_old_connections (`mod.K.connect`), consumers= HttpResponseBase.close (the send site)
#   P2 [P] TS `{ provide: EVENT_MANAGER_PLUGINS, useClass: X, multi: true }` x2 + a test provider; EventManager (whose constructor
#          does `@Inject( EVENT_MANAGER_PLUGINS )`) is a shown row; the question never names the token → the row prints with
#          as="useClass", tests="1", consumers="EventManager.constructor"
#   P3 [P] NestJS-shaped `@Module( { providers: [ { provide: CACHE_STORE, useClass: RedisStore }, { provide: CACHE_STORE,
#          useFactory: makeStore } ] } )`, consumer `@Inject( CACHE_STORE )` in CacheService's constructor
#   G1 [G] a same-named `connect` of an unrelated class (`pool = Pool()`, Pool.connect returns its argument): no row, even with
#          the question naming `pool`
#   G2 [G] a token with ONE provider, named by the question (LONE_TOKEN): no row (a registry needs >= 2 non-test registrations)
#   G3 [G] a lookalike literal `{ name: EVENT_MANAGER_PLUGINS, useClass: LoneThing }` (no provide): LoneThing never listed
#   G4 [G] a decorator registration `@register.filter` (not this slice): no row
#   G5 [G] a question that names neither key nor registered name, with no consumer shown: no row
#   G6 [G] the consumer (EventManager) is shown but the question shares no word with the key's name: no row (fire-table rule:
#          Angular DI tokens and sibling signals fired through a shown consumer alone)
#   FIX ROUND 1 (reviews rv-registrar + rv-registrar-lens; every [P] arm below is RED on 73ae931f):
#   I1 [P] `import pkg; pkg.sig.connect( f )` with pkg/__init__.py AND pkg/pkg.py defining `sig`: the row is keyed to pkg/__init__.py and
#          lists ITS receivers only (the old code tried the submodule pkg.pkg first); I1d [P] `from b import signals as bsig;
#          bsig.K.connect( f )` lists under b's key (the old code tried `b.bsig`); I1c [P] `from pkg import signals` where pkg/__init__.py
#          binds `signals` itself: no row
#   I2 [P] a parameter / loop variable / local named like the key is not the key: only the module-level receivers list
#   R1 [P] a registrar that also stores `sender=None`: a positional sender (`saved.connect( on_foo, Foo )`) is never a receiver; R1b [P] a
#          registrar storing two parameters without a default (which is the receiver?) gives no row
#   T1 [P] repeated `makeProviders( [ { … } ] )` / `register( { … } )` calls share an into= prefix: a value is never paired with another
#          object's `provide`
#   D1 [P]/[G] disclosure (the clause, d1c and d1d are [P]; consumers_more= and the shell-safe next= are [G] twins of what 73ae931f printed): the clause says n= is a floor and defines consumers_more= reg_more= cut=; a keyword-argument registration is not
#          counted; a third key past kRegRowCap=2 is counted in reg_more=; a 4+ hop re-export chain sets cut=1; a capped row's next= is
#          one shell-safe argv element (sh -n)
#   F1 [G] RIPWIRE_NO_REG_ROWS=1: no <reg> and no clause; the P1 answer minus its <reg> rows and clause equals it (est_tokens masked)
#   F2 [G] --json carries no <reg>
#   L1 [P] the clause defines reg when a row prints; L2 [G] absent when none does
#   FIX ROUND 4 (review rv-registrar-delta3; the [P] arms are RED on 5fb82f85):
#   P4 [P] Python: a site counts only when its value resolves to a def: an event class (BUS.on( Foo, h1 )), a label (tag( h1, Foo )) or a class
#          registry (REG.register( PluginA )) is never listed (the class registry is lost by design); a function-only registrar still lists
#   T4 [P] TS: a spread / duplicate / computed / accessor / method entry, reg.remove( { … } ), console.log( { … } ), a mutable const object and
#          reg.configure( { excluded: [ { … } ] } ) never list a class; only a plain literal that is an ARRAY element (const / call argument /
#          providers / viewProviders) counts; F2r4/TA/TB/T1 pin the rows lost by design (a bare call argument, a const object)
#   T3 [P] TS: a function-local `function K(){}` in a file that imports K gives no row (the sites are not filed under the local symbol)
#   GF1 [P] a registrar fact's scope char "g" is no name evidence for a class g in another file (graph.h file evidence; cr-prepass 43b F-G1); GF2-GF4 [G] twins
#   X1 [G] determinism   X2 [G] xmllint well-formed (when xmllint is present)
#
# Usage:  bash test/regsitecheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/regsitecheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_REG_ROWS
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "regsitecheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

# ── fixtures (runtime) ──────────────────────────────────────────────────────────────────────────────────────────────────────
PY="$TMP/py"; mkdir -p "$PY/dispatch" "$PY/core" "$PY/db" "$PY/http" "$PY/tests" "$PY/tpl"
cat > "$PY/dispatch/dispatcher.py" <<'EOF'
class Signal:
    def __init__(self):
        self.receivers = []

    def connect(self, receiver, sender=None, weak=True, dispatch_uid=None):
        lookup_key = (id(receiver), id(sender))
        self.receivers.append((lookup_key, receiver, sender))

    def send(self, sender, **named):
        return [r(sender) for _, r, _ in self.receivers]
EOF
printf 'from dispatch.dispatcher import Signal\n' > "$PY/dispatch/__init__.py"
printf 'from dispatch import Signal\n\nrequest_finished = Signal()\n' > "$PY/core/signals.py"
cat > "$PY/db/__init__.py" <<'EOF'
from core import signals

def close_old_connections(**kwargs):
    pass

signals.request_finished.connect(close_old_connections)
EOF
cat > "$PY/core/cache.py" <<'EOF'
from core.signals import request_finished

def close_caches(**kwargs):
    pass

request_finished.connect(close_caches)
EOF
cat > "$PY/http/response.py" <<'EOF'
from core import signals

class HttpResponseBase:
    def close(self):
        signals.request_finished.send(sender=self)
EOF
cat > "$PY/tests/test_client.py" <<'EOF'
from core.signals import request_finished

def on_done(**kw):
    pass

request_finished.connect(on_done)
EOF
cat > "$PY/pool.py" <<'EOF'
class Pool:
    def connect(self, cb):
        return cb

pool = Pool()

def handler_one():
    pass

def handler_two():
    pass

pool.connect(handler_one)
pool.connect(handler_two)
EOF
cat > "$PY/tpl/library.py" <<'EOF'
class Library:
    def __init__(self):
        self.filters = {}

    def filter(self, func):
        self.filters[func.__name__] = func
        return func

register = Library()

@register.filter
def upper(value):
    return value.upper()

@register.filter
def lower(value):
    return value.lower()
EOF

TS="$TMP/ts"; mkdir -p "$TS/events" "$TS/test" "$TS/nest"
cat > "$TS/events/di.ts" <<'EOF'
export class InjectionToken<T> { constructor(public desc: string) {} }
export function Inject(token: any): any { return () => token; }
export function Module(meta: any): any { return () => meta; }
EOF
cat > "$TS/events/event_manager.ts" <<'EOF'
import {Inject, InjectionToken} from './di';

export const EVENT_MANAGER_PLUGINS = new InjectionToken<EventManagerPlugin[]>('EventManagerPlugins');
export const LONE_TOKEN = new InjectionToken<string>('lone');

export abstract class EventManagerPlugin {
  abstract supports(eventName: string): boolean;
}

export class EventManager {
  private _plugins: EventManagerPlugin[];
  constructor(@Inject(EVENT_MANAGER_PLUGINS) plugins: EventManagerPlugin[]) {
    this._plugins = plugins.slice().reverse();
  }
  findPluginFor(eventName: string): EventManagerPlugin {
    return this._plugins.find((p) => p.supports(eventName))!;
  }
}
EOF
printf "import {EventManagerPlugin} from './event_manager';\nexport class DomEventsPlugin extends EventManagerPlugin { supports(e: string) { return true; } }\n" > "$TS/events/dom_events.ts"
printf "import {EventManagerPlugin} from './event_manager';\nexport class KeyEventsPlugin extends EventManagerPlugin { supports(e: string) { return e.startsWith('key'); } }\nexport class LoneThing {}\n" > "$TS/events/key_events.ts"
cat > "$TS/browser.ts" <<'EOF'
import {EVENT_MANAGER_PLUGINS, LONE_TOKEN} from './events/event_manager';
import {DomEventsPlugin} from './events/dom_events';
import {KeyEventsPlugin, LoneThing} from './events/key_events';

export const BROWSER_MODULE_PROVIDERS = [
  {
    provide: EVENT_MANAGER_PLUGINS,
    useClass: DomEventsPlugin,
    multi: true,
  },
  {provide: EVENT_MANAGER_PLUGINS, useClass: KeyEventsPlugin, multi: true},
  {provide: LONE_TOKEN, useClass: LoneThing},
  {name: EVENT_MANAGER_PLUGINS, useClass: LoneThing},
];
EOF
cat > "$TS/test/spec.ts" <<'EOF'
import {EVENT_MANAGER_PLUGINS} from '../events/event_manager';
import {DomEventsPlugin} from '../events/dom_events';
export const TEST_PROVIDERS = [{provide: EVENT_MANAGER_PLUGINS, useClass: DomEventsPlugin, multi: true}];
EOF
cat > "$TS/nest/cache.ts" <<'EOF'
import {Inject, InjectionToken, Module} from '../events/di';

export const CACHE_STORE = new InjectionToken<Store>('store');
export interface Store { get(k: string): string; }
export class RedisStore implements Store { get(k: string) { return k; } }
export function makeStore(): Store { return new RedisStore(); }

export class CacheService {
  constructor(@Inject(CACHE_STORE) private readonly store: Store) {}
  lookup(k: string) { return this.store.get(k); }
}

@Module({
  providers: [{provide: CACHE_STORE, useClass: RedisStore}, {provide: CACHE_STORE, useFactory: makeStore}],
})
export class CacheModule {}
EOF

Q_PY="which receivers run when request_finished is sent"
Q_TS="how does the EventManager find the plugin for an event"
Q_NEST="how does CacheService lookup reach its store"

run(){
    local name="$1" root="$2"; shift 2
    local envs=()
    while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=( "$1" ); shift; done
    shift
    ( cd "$root" || exit 1; env ${envs[@]+"${envs[@]}"} "$BIN" "$root" "$@" --cache="$TMP/$name.cache" >"$TMP/$name.xml" 2>"$TMP/$name.err" ) \
        || no "$name: ripwire exited non-zero ($( head -c 200 "$TMP/$name.err" | tr '\n' ' ' ))"
}

cat > "$TMP/chk.py" <<'PY'
import html, re, sys
cmd, args = sys.argv[1], sys.argv[2:]
t = open(args[0], "rb").read().decode("utf-8", "replace")
regs = re.findall(r'<reg [^>]*>.*?</reg>', t)
def attr(r, a):
    m = re.search(r'\b%s="([^"]*)"' % a, r)
    return html.unescape(m.group(1)) if m else None
if cmd == "row":            # FILE KEY ATTR=VAL... SYM...: one row for KEY with exactly these attrs and exactly these r sym= in order
    key = args[1]
    mine = [r for r in regs if attr(r.split('>')[0], "key") == key]
    if len(mine) != 1: print("rows for %s: %d (all: %r)" % (key, len(mine), regs)); sys.exit(1)
    head = mine[0].split('>')[0]; syms = re.findall(r'<r sym="([^"]*)"', mine[0])
    want = [a for a in args[2:] if '=' in a]; wsyms = [a for a in args[2:] if '=' not in a]
    for w in want:
        k, v = w.split('=', 1)
        if attr(head, k) != v: print("%s: %s=%r want %r (%s)" % (key, k, attr(head, k), v, mine[0])); sys.exit(1)
    if syms != wsyms: print("%s: syms %r want %r" % (key, syms, wsyms)); sys.exit(1)
elif cmd == "rowat":        # FILE KEY PATHPREFIX|- ATTR=VAL... SYM...: the ONE row for KEY defined under PATHPREFIX, exactly these attrs and r syms
    key, pp = args[1], args[2]
    mine = [r for r in regs if attr(r.split('>')[0], "key") == key and (pp == "-" or (attr(r.split('>')[0], "p") or "").startswith(pp))]
    if len(mine) != 1: print("rows for %s@%s: %d (all: %r)" % (key, pp, len(mine), regs)); sys.exit(1)
    head = mine[0].split('>')[0]; syms = re.findall(r'<r sym="([^"]*)"', mine[0])
    want = [a for a in args[3:] if '=' in a]; wsyms = [a for a in args[3:] if '=' not in a]
    for w in want:
        k, v = w.split('=', 1)
        if attr(head, k) != v: print("%s: %s=%r want %r (%s)" % (key, k, attr(head, k), v, mine[0])); sys.exit(1)
    if syms != wsyms: print("%s: syms %r want %r" % (key, syms, wsyms)); sys.exit(1)
elif cmd == "attr":         # FILE KEY NAME: print the attribute NAME of the ONE row for KEY
    mine = [r for r in regs if attr(r.split('>')[0], "key") == args[1]]
    if len(mine) != 1: print("rows for %s: %d" % (args[1], len(mine))); sys.exit(1)
    v = attr(mine[0].split('>')[0], args[2])
    if v is None: print("no %s on %s" % (args[2], args[1])); sys.exit(1)
    print(v)
elif cmd == "legend":       # FILE WORD...: the reg clause defines every WORD
    m = re.search(r'; reg (key= p=|rows:).*?(?=; |-->|<)', t)
    if not m: print("no reg clause"); sys.exit(1)
    miss = [w for w in args[1:] if w not in m.group(0)]
    if miss: print("clause lacks %r: %s" % (miss, m.group(0))); sys.exit(1)
elif cmd == "nokey":        # FILE KEY: no row for KEY
    if any(attr(r.split('>')[0], "key") == args[1] for r in regs): print("a row for %s: %r" % (args[1], regs)); sys.exit(1)
elif cmd == "nosym":        # FILE SYM: SYM never listed
    if any(('sym="%s"' % args[1]) in r for r in regs): print("%s listed: %r" % (args[1], regs)); sys.exit(1)
elif cmd == "none":         # FILE: no <reg> and no clause
    if regs or "; reg " in t: print("reg rows or clause present"); sys.exit(1)
elif cmd == "clause":       # FILE: the clause is there
    if "; reg key= p=" not in t and "; reg rows:" not in t: print("no reg clause"); sys.exit(1)
elif cmd == "strip":        # FILE OUT: the answer without <reg> rows, their clause and est_tokens
    t = re.sub(r'<reg [^>]*>.*?</reg>', '', t)
    t = re.sub(r'; reg (key= p=|rows:)[^;<]*?(?=; |-->)', '', t)
    t = re.sub(r'est_tokens="\d+"', 'est_tokens=""', t)
    open(args[1], "w").write(t)
PY
chk(){ python3 "$TMP/chk.py" "$@"; }

run p1 "$PY" -- --for="$Q_PY"
if out=$( chk row "$TMP/p1.xml" request_finished by=Signal.connect n=2 tests=1 consumers=HttpResponseBase.close close_caches close_old_connections ); then ok "P1 Python signal row"; else no "P1 $out"; fi
if out=$( chk nosym "$TMP/p1.xml" on_done ); then ok "P1b test registration counted, not listed"; else no "P1b $out"; fi
if out=$( chk clause "$TMP/p1.xml" ); then ok "L1 clause beside the row"; else no "L1 $out"; fi

run p2 "$TS" -- --for="$Q_TS"
if grep -q '<d [^>]*n="EventManager' "$TMP/p2.xml"; then
    if out=$( chk row "$TMP/p2.xml" EVENT_MANAGER_PLUGINS n=2 tests=1 consumers=EventManager.constructor DomEventsPlugin KeyEventsPlugin ); then ok "P2 TS provider row via shown consumer"; else no "P2 $out"; fi
else no "P2 vacuous: EventManager not a shown row"; fi
if out=$( chk nosym "$TMP/p2.xml" LoneThing ); then ok "G3 lookalike literal without provide never listed"; else no "G3 $out"; fi

run g6 "$TS" -- --for="how does EventManager findPluginFor reverse its list"
if grep -q '<d [^>]*n="EventManager' "$TMP/g6.xml"; then
    if out=$( chk nokey "$TMP/g6.xml" EVENT_MANAGER_PLUGINS ); then ok "G6 shown consumer but no word of the key in the question: no row"; else no "G6 $out"; fi
else no "G6 vacuous: EventManager not a shown row"; fi

run p3 "$TS" -- --for="$Q_NEST"
if out=$( chk row "$TMP/p3.xml" CACHE_STORE n=2 consumers=CacheService.constructor RedisStore makeStore ); then ok "P3 NestJS-shaped providers"; else no "P3 $out"; fi

run g1 "$PY" -- --for="which handlers does pool connect"
if out=$( chk nokey "$TMP/g1.xml" pool ); then ok "G1 same-named connect of a non-storing class: no row"; else no "G1 $out"; fi
run g2 "$TS" -- --for="which class is provided for LONE_TOKEN"
if out=$( chk nokey "$TMP/g2.xml" LONE_TOKEN ); then ok "G2 one provider, no shown consumer: no row"; else no "G2 $out"; fi
run g4 "$PY" -- --for="how are upper and lower registered as template filters with register"
if out=$( chk nokey "$TMP/g4.xml" register ); then ok "G4 decorator registration: no row (not this slice)"; else no "G4 $out"; fi
run g5 "$PY" -- --for="how does the pool hand back its callback"
if out=$( chk none "$TMP/g5.xml" ); then ok "G5/L2 key not named, no consumer shown: no row, no clause"; else no "G5 $out"; fi

# ── fix round 1 (reviews rv-registrar, rv-registrar-lens): fixtures at runtime, one tree each so no arm disturbs another's key ──
SIGPY='class Signal:
    def __init__(self):
        self.receivers = []

    def connect(self, receiver, sender=None, weak=True, dispatch_uid=None):
        self.receivers.append((id(receiver), receiver, sender))

    def send(self, sender, **named):
        return [r(sender) for _, r, _ in self.receivers]
'
mk(){ mkdir -p "$TMP/$1"; printf '%s' "$SIGPY" > "$TMP/$1/dispatch.py"; }

# I1: both pkg/__init__.py and pkg/pkg.py define sig; `import pkg` names the package's own file
mk i1; mkdir -p "$TMP/i1/pkg"
printf 'from dispatch import Signal\n\nsig = Signal()\n' > "$TMP/i1/pkg/__init__.py"
printf 'from dispatch import Signal\n\nsig = Signal()\n' > "$TMP/i1/pkg/pkg.py"
printf 'import pkg\n\ndef p1(): pass\ndef p2(): pass\n\npkg.sig.connect(p1)\npkg.sig.connect(p2)\n' > "$TMP/i1/use.py"
printf 'from pkg.pkg import sig\n\ndef q1(): pass\ndef q2(): pass\n\nsig.connect(q1)\nsig.connect(q2)\n' > "$TMP/i1/use_inner.py"
run i1 "$TMP/i1" -- --for="which receivers are connected to sig"
if out=$( chk rowat "$TMP/i1.xml" sig pkg/__init__.py n=2 p1 p2 ) && out=$( chk rowat "$TMP/i1.xml" sig pkg/pkg.py n=2 q1 q2 ); then ok "I1 import pkg keys to the package's own file, not pkg/pkg.py"; else no "I1 $out"; fi

# I1d: an aliased from-import of a module
mk i1d; mkdir -p "$TMP/i1d/b"
: > "$TMP/i1d/b/__init__.py"
printf 'from dispatch import Signal\n\nrequest_done = Signal()\n' > "$TMP/i1d/b/signals.py"
printf 'from b import signals as bsig\n\ndef f1(): pass\ndef f2(): pass\n\nbsig.request_done.connect(f1)\nbsig.request_done.connect(f2)\n' > "$TMP/i1d/send.py"
run i1d "$TMP/i1d" -- --for="which receivers are connected to request_done"
if out=$( chk row "$TMP/i1d.xml" request_done n=2 f1 f2 ); then ok "I1d aliased module from-import lists under the module's key"; else no "I1d $out"; fi

# I1c: the package's own attribute `signals` wins over the submodule pkg/signals.py
mk i1c; mkdir -p "$TMP/i1c/pkg"
printf 'signals = None\n' > "$TMP/i1c/pkg/__init__.py"
printf 'from dispatch import Signal\n\nrequest_done = Signal()\n' > "$TMP/i1c/pkg/signals.py"
printf 'from pkg import signals\n\ndef f1(): pass\ndef f2(): pass\n\nsignals.request_done.connect(f1)\nsignals.request_done.connect(f2)\n' > "$TMP/i1c/send.py"
run i1c "$TMP/i1c" -- --for="which receivers are connected to request_done"
if out=$( chk nokey "$TMP/i1c.xml" request_done ); then ok "I1c a package attribute shadowing the submodule: no row"; else no "I1c $out"; fi

# I2: a shadowing parameter / loop variable / local
mk i2; mkdir -p "$TMP/i2/core"
printf 'from dispatch import Signal\n\nrequest_finished = Signal()\nother = Signal()\n' > "$TMP/i2/core/signals.py"
cat > "$TMP/i2/use.py" <<'EOF'
from core.signals import request_finished, other

def h1(): pass
def h2(): pass
def param_h(): pass
def loop_h(): pass
def local_h(): pass

request_finished.connect(h1)
request_finished.connect(h2)

def wire(request_finished):
    request_finished.connect(param_h)

def wire_loop():
    for request_finished in (other,):
        request_finished.connect(loop_h)

def wire_local():
    request_finished = other
    request_finished.connect(local_h)
EOF
run i2 "$TMP/i2" -- --for="which receivers are connected to request_finished"
if out=$( chk row "$TMP/i2.xml" request_finished n=2 h1 h2 ); then ok "I2 shadowing parameter / loop variable / local never listed under the module key"; else no "I2 $out"; fi

# R1: a positional sender stored beside the receiver is not a receiver
mk r1
printf 'from dispatch import Signal\n\nsaved = Signal()\n' > "$TMP/r1/sigs.py"
printf 'class Foo:\n    pass\n\nclass Bar:\n    pass\n' > "$TMP/r1/models.py"
printf 'from sigs import saved\nfrom models import Foo, Bar\n\ndef on_foo(sender): pass\ndef on_bar(sender): pass\n\nsaved.connect(on_foo, Foo)\nsaved.connect(on_bar, Bar)\n' > "$TMP/r1/reg.py"
run r1 "$TMP/r1" -- --for="which receivers run when saved is sent"
if out=$( chk row "$TMP/r1.xml" saved n=2 on_foo on_bar ); then ok "R1 a positional sender (stored beside the receiver) is not a receiver"; else no "R1 $out"; fi

# R1b: two stored parameters without a default: which is the receiver is not provable
mk r1b
printf 'class Strict:\n    def __init__(self):\n        self.table = []\n\n    def connect(self, sender, receiver):\n        self.table.append((sender, receiver))\n\nstrict = Strict()\n' > "$TMP/r1b/strict.py"
printf 'from strict import strict\n\nclass Foo:\n    pass\n\ndef cb1(): pass\ndef cb2(): pass\n\nstrict.connect(Foo, cb1)\nstrict.connect(Foo, cb2)\n' > "$TMP/r1b/use.py"
run r1b "$TMP/r1b" -- --for="which callbacks are connected to strict"
if out=$( chk nokey "$TMP/r1b.xml" strict ); then ok "R1b two stored parameters without a default: no row"; else no "R1b $out"; fi

# T1: repeated calls share an into= prefix
mkdir -p "$TMP/t1"
printf "export class InjectionToken<T> { constructor(public desc: string) {} }\nexport function Inject(t: any): any { return () => {}; }\nexport const PLUGINS = new InjectionToken<any>('plugins');\nexport const OTHER = new InjectionToken<any>('other');\n" > "$TMP/t1/tokens.ts"
printf 'export class A {}\nexport class B {}\nexport class C {}\nexport class D {}\nexport class G {}\nexport class H {}\nexport class Z1 {}\n' > "$TMP/t1/plugins.ts"
cat > "$TMP/t1/providers.ts" <<'EOF'
import { PLUGINS } from './tokens';
import * as T from './tokens';
import { A, B, C, D, G, H, Z1 } from './plugins';

export function makeProviders(p: any[]) { return p; }
export function register(p: any) { return p; }
export const BASE = [{ provide: PLUGINS, useClass: D, multi: true }];
export const MORE = [{ provide: PLUGINS, useClass: Z1, multi: true }];
export function provideAll() {
  makeProviders([{ provide: PLUGINS, useClass: A, multi: true }]);
  makeProviders([{ provide: 'plugins-by-string', useClass: B, multi: true }]);
  return makeProviders([{ provide: T.OTHER, useClass: C, multi: true }]);
}
export function wire() {
  register({ provide: PLUGINS, useClass: G, multi: true });
  register({ useClass: H });
}
EOF
run t1 "$TMP/t1" -- --for="which classes are provided for PLUGINS"
# fix round 3: a pair is its OWN literal's (not the call count), so A and G (each a complete { provide: PLUGINS, useClass: X } literal in a repeated
# callee) now list; B, C and H (a string provide, another token, no provide) must never join PLUGINS
if out=$( chk row "$TMP/t1.xml" PLUGINS n=3 D Z1 A ); then ok "T1 a value is never paired with another object's provide (array-held literals only: D Z1 A list; B C never; the bare register( { … } ) literal G no longer counts: fix round 4)"; else no "T1 $out"; fi

# D1: floor + keyword registration + consumers_more
mk d1
printf 'from dispatch import Signal\n\nev = Signal()\n' > "$TMP/d1/sigs.py"
cat > "$TMP/d1/use.py" <<'EOF'
import sigs

def a1(): pass
def a2(): pass
def kw_h(): pass

sigs.ev.connect(a1)
sigs.ev.connect(a2)
sigs.ev.connect(receiver=kw_h)

def s1(): sigs.ev.send(sender=1)
def s2(): sigs.ev.send(sender=2)
def s3(): sigs.ev.send(sender=3)
EOF
run d1 "$TMP/d1" -- --for="which receivers run when ev is sent from s1 s2 s3"
if out=$( chk row "$TMP/d1.xml" ev n=2 consumers=s1,s2 consumers_more=1 a1 a2 ); then ok "D1 consumers_more= printed, the keyword registration is not counted"; else no "D1 $out"; fi
if out=$( chk legend "$TMP/d1.xml" "AT LEAST" "floor" "keyword-argument" "consumers_more=" "reg_more=" "cut=1" ); then ok "D1 the clause says n= is a floor and defines consumers_more= reg_more= cut="; else no "D1 $out"; fi

# D1c: the 2-key cap is counted, not silent
mk d1c; mkdir -p "$TMP/d1c/a" "$TMP/d1c/b" "$TMP/d1c/c"
for k in a b c; do
    : > "$TMP/d1c/$k/__init__.py"
    printf 'from dispatch import Signal\n\nrequest_finished = Signal()\n' > "$TMP/d1c/$k/signals.py"
    printf 'from %s.signals import request_finished\n\ndef h_%s1(): pass\ndef h_%s2(): pass\n\nrequest_finished.connect(h_%s1)\nrequest_finished.connect(h_%s2)\n' "$k" "$k" "$k" "$k" "$k" > "$TMP/d1c/$k/use.py"
done
run d1c "$TMP/d1c" -- --for="which receivers are connected to request_finished"
if [ "$( grep -o '<reg ' "$TMP/d1c.xml" | wc -l | tr -d ' ' )" = 2 ] && [ "$( grep -o 'reg_more="1"' "$TMP/d1c.xml" | wc -l | tr -d ' ' )" = 1 ]; then ok "D1c a third key is counted in reg_more=, never silent"; else no "D1c 2 rows + reg_more=\"1\" expected: $( grep -o '<reg [^>]*>' "$TMP/d1c.xml" | head -5 )"; fi

# D1d: a re-export chain longer than the follow limit
mk d1d; mkdir -p "$TMP/d1d/d0" "$TMP/d1d/d1" "$TMP/d1d/d2" "$TMP/d1d/d3" "$TMP/d1d/d4" "$TMP/d1d/d5"
printf 'from dispatch import Signal\n\nck = Signal()\n' > "$TMP/d1d/d0/__init__.py"
prev=d0; for n in d1 d2 d3 d4 d5; do printf 'from %s import ck\n' "$prev" > "$TMP/d1d/$n/__init__.py"; prev=$n; done
printf 'from d0 import ck\n\ndef a1(): pass\n\nck.connect(a1)\n' > "$TMP/d1d/use_a.py"
printf 'from d1 import ck\n\ndef b1(): pass\n\nck.connect(b1)\n' > "$TMP/d1d/use_b.py"
printf 'from d5 import ck\n\ndef c1(): pass\n\nck.connect(c1)\n' > "$TMP/d1d/use_c.py"
run d1d "$TMP/d1d" -- --for="which receivers are connected to ck"
if out=$( chk row "$TMP/d1d.xml" ck n=2 cut=1 a1 b1 ); then ok "D1d a chain over the hop limit sets cut=1 and is not counted"; else no "D1d $out"; fi

# D1e: a capped row's next= is one shell-safe argv element
mk d1e
printf 'from dispatch import Signal\n\nbus = Signal()\n' > "$TMP/d1e/sigs.py"
{ printf 'from sigs import bus\n\n'; for i in 1 2 3 4 5 6; do printf 'def h%s(): pass\n' "$i"; done; for i in 1 2 3 4 5 6; do printf 'bus.connect(h%s)\n' "$i"; done; } > "$TMP/d1e/use.py"
run d1e "$TMP/d1e" -- --for="which receivers are connected to bus"
if nx=$( chk attr "$TMP/d1e.xml" bus next ) && [ "$nx" = "--grep=bus" ] && sh -n -c "x $nx" 2>/dev/null && [ "$( chk attr "$TMP/d1e.xml" bus capped )" = 1 ]; then ok "D1e capped row: next=--grep=bus, sh -n clean"; else no "D1e next= ($( chk attr "$TMP/d1e.xml" bus next 2>&1 ))"; fi

# ── fix round 2 (review rv-registrar-delta; every [P] arm below is RED on 820946ee) ─────────────────────────────────────────────
# F1 [P]: an aliased Python from-import is looked up under the written name in its module, never under the alias
mk f1a
printf 'from dispatch import Signal\n\npre_save = Signal()\npost_save = Signal()\n' > "$TMP/f1a/s.py"
printf 'from s import post_save as pre_save\n\ndef h1(): pass\ndef h2(): pass\n\npre_save.connect(h1)\npre_save.connect(h2)\n' > "$TMP/f1a/app.py"
printf 'from s import pre_save\n\ndef h3(): pass\ndef h4(): pass\n\npre_save.connect(h3)\npre_save.connect(h4)\n' > "$TMP/f1a/other.py"
run f1a "$TMP/f1a" -- --for="which receivers are connected to pre_save and post_save"
if out=$( chk row "$TMP/f1a.xml" pre_save n=2 h3 h4 ) && out=$( chk row "$TMP/f1a.xml" post_save n=2 h1 h2 ); then ok "F1 aliased from-import: post_save's handlers never list under pre_save (and list under post_save)"; else no "F1 $out"; fi
mk f1b
printf '\nclass Plain:\n    def connect(self, cb):\n        return cb\n' >> "$TMP/f1b/dispatch.py"
printf 'from dispatch import Plain as Signal\n\nK = Signal()\n\ndef a1(): pass\ndef a2(): pass\n\nK.connect(a1)\nK.connect(a2)\n' > "$TMP/f1b/use.py"
run f1b "$TMP/f1b" -- --for="which receivers are connected to K"
if out=$( chk nokey "$TMP/f1b.xml" K ); then ok "F1b 'from dispatch import Plain as Signal': Plain's connect stores nothing, no row and no false by="; else no "F1b $out"; fi

mk f1c
printf 'from dispatch import Signal\n\nK = Signal()\n' > "$TMP/f1c/other.py"
printf 'import other as K\n\ndef a1(): pass\ndef a2(): pass\n\nK.connect(a1)\nK.connect(a2)\n' > "$TMP/f1c/use.py"
run f1c "$TMP/f1c" -- --for="which receivers are connected to K"
if out=$( chk nokey "$TMP/f1c.xml" K ); then ok "F1c 'import other as K' binds the module: K.connect( a1 ) is not other.K's registration"; else no "F1c $out"; fi

# F2 [P]: a value is never paired with another object's provide, whatever the other object's value looks like (a literal, an arrow, none)
mkdir -p "$TMP/f2"
printf "export class InjectionToken<T> { constructor(public desc: string) {} }\n" > "$TMP/f2/it.ts"
printf "import { InjectionToken } from './it';\n" > "$TMP/f2/tokens.ts"
: > "$TMP/f2/cl.ts"
printf "import { PA, PB, PC, PD, PE, PF } from './tokens';\nimport { HA, HB, HC, HD, HE, GF } from './cl';\nexport function register(p: any) { return p; }\nexport function makeProviders(p: any[]) { return p; }\nexport const svc = { register(p: any) { return p; } };\n" > "$TMP/f2/app.ts"
for t in A B C D E F; do
    printf "export const P%s = new InjectionToken<any>('p%s');\n" "$t" "$t" >> "$TMP/f2/tokens.ts"
    printf "export class D%s {}\nexport class Z%s {}\nexport class H%s {}\nexport class G%s {}\n" "$t" "$t" "$t" "$t" >> "$TMP/f2/cl.ts"
    printf "import { P%s } from './tokens';\nimport { D%s, Z%s } from './cl';\nexport const BASE_%s = [{ provide: P%s, useClass: D%s, multi: true }];\nexport const MORE_%s = [{ provide: P%s, useClass: Z%s, multi: true }];\n" "$t" "$t" "$t" "$t" "$t" "$t" "$t" "$t" "$t" > "$TMP/f2/base_$t.ts"
done
cat >> "$TMP/f2/app.ts" <<'EOF'
export function wireA() {
  register({ provide: PA, useValue: 42 });
  register({ provide: 'str', useClass: HA });
}
export function wireB() {
  register({ provide: PB, useFactory: () => 1 });
  register({ useClass: HB });
}
export function wireC() {
  makeProviders([{ provide: PC, useValue: 'x' }]);
  makeProviders([{ provide: 'other', useClass: HC }]);
}
export function wireD() {
  register({ provide: PD });
  register({ useClass: HD });
}
export function wireE() {
  svc.register({ provide: PE, useValue: 1 });
  svc.register({ useClass: HE });
}
export function wireF() {
  register({ provide: PF, useClass: GF, multi: true });
}
EOF
f2bad=""
for t in A B C D E F; do run "f2$t" "$TMP/f2" -- --for="which classes are provided for P$t"; done
for t in A B C D E; do out=$( chk row "$TMP/f2$t.xml" P$t n=2 D$t Z$t ) || f2bad="$f2bad P$t: $out;"; done
if [ -z "$f2bad" ]; then ok "F2 a value never pairs with another object's provide (literal useValue, arrow useFactory, bare provide, array form, member call)"; else no "F2 $f2bad"; fi
if out=$( chk row "$TMP/f2F.xml" PF n=2 DF ZF ); then ok "F2b a bare register( { … } ) call in a function no longer lists its class (fix round 4: only array-held literals count; lost by design)"; else no "F2b $out"; fi

# F3 [P]: binders with no assignment-shaped fact (function-local import, comprehension target, lambda parameter), and module-level for / with
mkf3(){   # NAME BODY: mod.py defines K = Signal(), connects h1 h2, then BODY
    mk "f3_$1"
    printf 'from dispatch import Signal\n\nK = Signal()\nZ = Signal()\n' > "$TMP/f3_$1/other.py"
    printf 'from dispatch import Signal\n\ndef h1(): pass\ndef h2(): pass\ndef h3(): pass\n\nK = Signal()\nK.connect(h1)\nK.connect(h2)\n%b' "$2" > "$TMP/f3_$1/mod.py"
}
mkf3 base ''
mkf3 localimp '\ndef f():\n    from other import K\n    K.connect(h3)\n'
mkf3 localimpas '\ndef f():\n    from other import Z as K\n    K.connect(h3)\n'
mkf3 localimpmod '\ndef f():\n    import other as K\n    K.connect(h3)\n'
mkf3 compr '\ndef f(xs):\n    return [K.connect(h3) for K in xs]\n'
mkf3 lam '\nlam = lambda K: K.connect(h3)\n'
mkf3 modfor '\nfor K in (Signal(), Signal()):\n    K.connect(h3)\n'
mkf3 modwith '\nwith open("x") as K:\n    K.connect(h3)\n'
f3bad=""
for c in base localimp localimpas localimpmod compr lam modfor modwith; do
    run "f3_$c" "$TMP/f3_$c" -- --for="which receivers are connected to K"
done
if out=$( chk row "$TMP/f3_base.xml" K n=2 h1 h2 ); then ok "F3 twin: module-level connects list (h1 h2)"; else no "F3 twin $out"; fi
for c in localimp localimpas localimpmod compr lam; do out=$( chk row "$TMP/f3_$c.xml" K n=2 h1 h2 ) || f3bad="$f3bad $c: $out;"; done
if [ -z "$f3bad" ]; then ok "F3 a function-local import / comprehension target / lambda parameter named like the key is not the key (h3 never listed)"; else no "F3 $f3bad"; fi
f3bad=""
for c in modfor modwith; do out=$( chk nosym "$TMP/f3_$c.xml" h3 ) || f3bad="$f3bad $c: $out;"; done
if [ -z "$f3bad" ]; then ok "F3 a module-level for / with target named like the key: h3 never listed under the module key"; else no "F3 $f3bad"; fi

# F4 [P]: a required stored parameter beside a wrapped one is not the receiver
mk f4
printf 'import weakref\n\ndef wrap(f):\n    return f\n\nclass Reg:\n    def __init__(self):\n        self.rx = []\n        self.fl = []\n\n    def connect(self, receiver, sender):\n        self.rx.append(wrap(receiver))\n        self.fl.append(sender)\n\nclass Reg2:\n    def __init__(self):\n        self.rx = []\n        self.fl = []\n\n    def connect(self, receiver, sender):\n        self.rx.append(weakref.ref(receiver))\n        self.fl.append(sender)\n\nclass Reg3:\n    def __init__(self):\n        self.rx = []\n\n    def connect(self, receiver, tag):\n        self.rx.append(receiver)\n' > "$TMP/f4/reg.py"
printf 'from reg import Reg, Reg2, Reg3\n\nclass Foo: pass\nclass Bar: pass\ndef h1(): pass\ndef h2(): pass\ndef h3(): pass\ndef h4(): pass\ndef h5(): pass\ndef h6(): pass\n\nsaved = Reg()\nsaved.connect(h1, Foo)\nsaved.connect(h2, Bar)\nweak = Reg2()\nweak.connect(h3, Foo)\nweak.connect(h4, Bar)\nplain = Reg3()\nplain.connect(h5, 1)\nplain.connect(h6, 2)\n' > "$TMP/f4/use.py"
for k in saved weak plain; do run "f4$k" "$TMP/f4" -- --for="which receivers are connected to $k"; done
if out=$( chk nokey "$TMP/f4saved.xml" saved ); then ok "F4 a required stored sender beside wrap( receiver ): no row (Foo, Bar never receivers)"; else no "F4 $out"; fi
if out=$( chk nokey "$TMP/f4weak.xml" weak ); then ok "F4w a required stored sender beside weakref.ref( receiver ): no row"; else no "F4w $out"; fi
if out=$( chk row "$TMP/f4plain.xml" plain n=2 h5 h6 ); then ok "F4b twin: an unused extra parameter does not block the registrar"; else no "F4b $out"; fi

# N1: `from . import signals` in the package __init__ binds the submodule itself: the row is kept
mk n1; mkdir -p "$TMP/n1/pkg"
printf 'from . import signals\n' > "$TMP/n1/pkg/__init__.py"
printf 'from dispatch import Signal\n\nK = Signal()\n' > "$TMP/n1/pkg/signals.py"
printf 'from pkg import signals\n\ndef h1(): pass\ndef h2(): pass\n\nsignals.K.connect(h1)\nsignals.K.connect(h2)\n' > "$TMP/n1/use.py"
run n1 "$TMP/n1" -- --for="which receivers are connected to K"
if out=$( chk row "$TMP/n1.xml" K n=2 h1 h2 ); then ok "N1 'from . import signals' in the package __init__ keeps the submodule row"; else no "N1 $out"; fi

# ── fix round 3 (review rv-registrar-delta2; every [P] arm below is RED on a1c95819): ALLOWLISTS, not refusal lists ─────────────────
# F2r3 [P]: a provider value pairs only through the SAME object literal, and only when that literal is a direct call argument or a `const`
# initialiser. Each bad shape below puts a `useClass: H<t>` object beside the `provide: T<t>` one without a second call of one callee.
mkdir -p "$TMP/f2r"
printf "export class InjectionToken<T> { constructor(public desc: string) {} }\n" > "$TMP/f2r/it.ts"
printf "import { InjectionToken } from './it';\n" > "$TMP/f2r/tokens.ts"
: > "$TMP/f2r/cl.ts"
printf "import { T1, T2, T3, T4, T5, T6, T7, T8, T9, TA, TB, TC, TD } from './tokens';\nimport { H1, H2, H3, H4, H5, H6, H7, H8, DB, ZB, HA9, HB9, HC, HD } from './cl';\nexport function register(p: any) { return p; }\ndeclare const flag: any;\n" > "$TMP/f2r/app.ts"
for t in 1 2 3 4 5 6 7 8 9 A B C D; do
    printf "export const T%s = new InjectionToken<any>('t%s');\n" "$t" "$t" >> "$TMP/f2r/tokens.ts"
    printf "export class D%s {}\nexport class Z%s {}\nexport class H%s {}\n" "$t" "$t" "$t" >> "$TMP/f2r/cl.ts"
    case "$t" in A|B) continue ;; esac
    printf "import { T%s } from './tokens';\nimport { D%s, Z%s } from './cl';\nexport const BASE_%s = [{ provide: T%s, useClass: D%s, multi: true }];\nexport const MORE_%s = [{ provide: T%s, useClass: Z%s, multi: true }];\n" "$t" "$t" "$t" "$t" "$t" "$t" "$t" "$t" "$t" > "$TMP/f2r/base_$t.ts"
done
cat >> "$TMP/f2r/app.ts" <<'EOF'
export function w1() { register(flag ? { provide: T1, useValue: 1 } : { provide: 'x', useClass: H1 }); }
export function w2() { register(flag ? { provide: T2 } : { useClass: H2 }); }
export function w3() { register(flag && { provide: T3, useValue: 1 } || { useClass: H3 }); }
export function w4() { const v = flag ? { provide: T4, useValue: 1 } : { provide: 'x', useClass: H4 }; return v; }
export function w5() { let v: any; v = { provide: T5, useValue: 1 }; v = { useClass: H5 }; return v; }
export function w6(o: any) { o.x = { provide: T6, useValue: 1 }; o.x = { useClass: H6 }; }
export function w7() { if (flag) return { provide: T7, useValue: 1 }; return { provide: 'x', useClass: H7 }; }
export function w8() { { const v = { provide: T8, useValue: 1 }; register(v); } { const v = { useClass: H8 }; register(v); } }
export function w9() { register(flag ? { provide: T9, useClass: HA9 } : { provide: T9, useClass: HB9 }); }
export function wc() { return [{ provide: TC, useClass: HC }]; }
export function wd() { let v = { provide: TD, useClass: HD }; return v; }
export const CA = { provide: TA, useClass: DA };
export const CB = { provide: TA, useClass: ZA };
export function wb() { register({ provide: TB, useClass: DB }); register({ provide: TB, useClass: ZB }); }
EOF
printf "import { DA, ZA } from './cl';\n" >> "$TMP/f2r/app.ts"
f2rbad=""
for t in 1 2 3 4 5 6 7 8 9 A B C D; do run "f2r$t" "$TMP/f2r" -- --for="which classes are provided for T$t"; done
for t in 1 2 3 4 5 6 7 8 9 C D; do out=$( chk row "$TMP/f2r$t.xml" T$t n=2 D$t Z$t ) || f2rbad="$f2rbad T$t: $out;"; done
if [ -z "$f2rbad" ]; then ok "F2r3 a ternary / || / const-ternary / reassigned / property / return / second-block literal never lends its class to another object's provide; two COMPLETE literals in a ternary, a returned literal and a 'let' literal are conditional / unbound and not listed"; else no "F2r3 $f2rbad"; fi
# fix round 4: a literal outside an array (a bare call argument, a `const X = { … }`) is NOT counted (reg.remove( { … } ), console.log( { … } ) and o.provide = … are not registrations): rows lost by design
if out=$( chk nokey "$TMP/f2rA.xml" TA ); then ok "F2r4 const-bound provider OBJECTS (not an array element) are not counted (lost by design: o.provide = … can rebind them)"; else no "F2r4 TA $out"; fi
if out=$( chk nokey "$TMP/f2rB.xml" TB ); then ok "F2r4 a bare register( { … } ) call argument is not counted (lost by design: reg.remove( { … } ) has the same shape)"; else no "F2r4 TB $out"; fi

# F4r3 [P] / B1 [P]: the registrar's other parameters are an allowlist
mk f4r
cat > "$TMP/f4r/reg.py" <<'EOF'
def wrap(f):
    return f

class Reg:
    def __init__(self):
        self.rx = []
        self.fl = []
        self.d = {}
        self.names = []

    def conn_dflt(self, sender, receiver=None):
        self.fl.append(sender)
        self.rx.append(wrap(receiver))

    def on(self, ev, fn=None):
        self.fl.append(ev)
        if fn is not None:
            self.rx.append(fn)

    def keyed(self, name, handler):
        self.d[name] = handler

    def keyed_first(self, handler, name):
        self.d[name] = handler

    def keyed_twice(self, name, handler):
        self.d[name] = handler
        self.names.append(name)

    def keyed_use(self, name, handler):
        self.d[name] = handler
        print(name)

    def django(self, receiver, sender=None, weak=True):
        key = (id(receiver), id(sender))
        self.rx.append((key, receiver))
EOF
cat > "$TMP/f4r/use.py" <<'EOF'
from reg import Reg

class Foo: pass
class Bar: pass
def h1(): pass
def h2(): pass
def h3(): pass
def h4(): pass

r1 = Reg()
r1.conn_dflt(Foo, h1)
r1.conn_dflt(Bar, h2)
r2 = Reg()
r2.on(Foo, h1)
r2.on(Bar, h2)
r3 = Reg()
r3.keyed('a', h1)
r3.keyed('b', h2)
r4 = Reg()
r4.keyed_first(h3, 'a')
r4.keyed_first(h4, 'b')
r5 = Reg()
r5.keyed_twice('a', h1)
r5.keyed_twice('b', h2)
r6 = Reg()
r6.keyed_use('a', h3)
r6.keyed_use('b', h4)
r7 = Reg()
r7.django(h1)
r7.django(h2, Foo)
EOF
for k in r1 r2 r3 r4 r5 r6 r7; do run "f4r$k" "$TMP/f4r" -- --for="which handlers are connected to $k"; done
if out=$( chk nokey "$TMP/f4rr1.xml" r1 ) && out=$( chk nosym "$TMP/f4rr1.xml" Foo ); then ok "F4r3 the receiver is the DEFAULTED parameter (conn_dflt( sender, receiver=None )): Foo / Bar never listed"; else no "F4r3 dflt-receiver $out"; fi
if out=$( chk nokey "$TMP/f4rr2.xml" r2 ) && out=$( chk nosym "$TMP/f4rr2.xml" Foo ); then ok "F4r3 on( ev, fn=None ) stores the event and (conditionally) fn: no row, Foo / Bar never listed"; else no "F4r3 on() $out"; fi
if out=$( chk row "$TMP/f4rr3.xml" r3 n=2 h1 h2 ); then ok "B1 a key parameter used only as the subscript of the store ( self.d[ name ] = handler ) is a registrar again"; else no "B1 keyed $out"; fi
if out=$( chk row "$TMP/f4rr4.xml" r4 n=2 h3 h4 ); then ok "B1 the same with the handler first ( keyed_first( handler, name ) )"; else no "B1 keyed_first $out"; fi
if out=$( chk nokey "$TMP/f4rr5.xml" r5 ); then ok "F4r3 twin: the key parameter ALSO stored elsewhere is not provably beside the point: no row"; else no "F4r3 keyed_twice $out"; fi
if out=$( chk nokey "$TMP/f4rr6.xml" r6 ); then ok "F4r3 twin: a required parameter used beyond the subscript key (print( name )) stays a no-row"; else no "F4r3 keyed_use $out"; fi
if out=$( chk row "$TMP/f4rr7.xml" r7 n=2 h1 h2 ); then ok "F4r3 twin: Django's shape ( receiver, sender=None, weak=True used in a local key ) still lists"; else no "F4r3 django $out"; fi
if out=$( chk legend "$TMP/f4rr3.xml" "only exact shapes are listed" "absent row" ); then ok "D3 the clause says listing is exact-shape only and an absent row proves nothing"; else no "D3 $out"; fi

# ── fix round 4 (review rv-registrar-delta3; every [P] arm below is RED on 5fb82f85): the value must be a function; plain array-held literals ──
# P4 [P]: Python — the site's value must resolve to a def (an event class / constant / dict key is not a receiver)
mkdir -p "$TMP/p4"
cat > "$TMP/p4/reg.py" <<'EOF'
from collections import defaultdict
class Reg:
    def __init__(self):
        self.events = []
        self.subs = defaultdict(list)
        self.rx = []
        self.names = {}
        self.items = []
    def on(self, ev, fn=None):
        self.events.append(ev)
        self.subs[ev].append(fn)
    def conn(self, ev, fn=None):
        self.rx.append((ev, fn))
    def tag(self, fn, label):
        self.names[fn] = label
    def plain(self, fn):
        self.rx.append(fn)
    def register(self, cls):
        self.items.append(cls)
EOF
cat > "$TMP/p4/use.py" <<'EOF'
from reg import Reg

class Foo: pass
class Bar: pass
class PluginA: pass
class PluginB: pass
def h1(): pass
def h2(): pass

BUS = Reg()
BUS.on(Foo, h1)
BUS.on(Bar, h2)
CON = Reg()
CON.conn(Foo, h1)
CON.conn(Bar, h2)
TAG = Reg()
TAG.tag(h1, Foo)
TAG.tag(h2, Bar)
PLN = Reg()
PLN.plain(h1)
PLN.plain(h2)
CLS = Reg()
CLS.register(PluginA)
CLS.register(PluginB)
EOF
for k in BUS CON TAG PLN CLS; do run "p4$k" "$TMP/p4" -- --for="which handlers are connected to $k"; done
for k in BUS CON TAG; do
    if out=$( chk nokey "$TMP/p4$k.xml" $k ) && out=$( chk nosym "$TMP/p4$k.xml" Foo ) && out=$( chk nosym "$TMP/p4$k.xml" Bar ); then ok "P4 $k: the event / label (a class) is never listed as the registered handler"; else no "P4 $k $out"; fi
done
if out=$( chk row "$TMP/p4PLN.xml" PLN n=2 h1 h2 ); then ok "P4 twin: a registrar storing only its function parameter still lists module-level defs"; else no "P4 twin PLN $out"; fi
if out=$( chk nokey "$TMP/p4CLS.xml" CLS ); then ok "P4 a class registry ( REG.register( PluginA ) ) is not counted (lost by design: the value must be a function)"; else no "P4 CLS $out"; fi

# T4 [P]: TS — a later spread / duplicate / computed / accessor / method entry can override the pair; a bare call argument or a mutable const object is no registration
mkdir -p "$TMP/t4"
printf "export class InjectionToken<T> { constructor(public desc: string) {} }\nexport const OTHER = new InjectionToken<any>('other');\n" > "$TMP/t4/tokens.ts"
: > "$TMP/t4/cl.ts"
for t in 1 2 3 4 5 6 7 8 9 A B C D; do
    printf "export const S%s = new InjectionToken<any>('s%s');\n" "$t" "$t" >> "$TMP/t4/tokens.ts"
    printf "export class D%s {}\nexport class Z%s {}\nexport class H%s {}\n" "$t" "$t" "$t" >> "$TMP/t4/cl.ts"
    printf "import { OTHER, S%s } from './tokens';\nimport { D%s, Z%s, H%s } from './cl';\ndeclare const o: any; declare const reg: any; declare const register: any; declare const makeProviders: any;\n" "$t" "$t" "$t" "$t" > "$TMP/t4/u_$t.ts"
    printf "export const BASE_%s = [{ provide: S%s, useClass: D%s }, { provide: S%s, useClass: Z%s }];\n" "$t" "$t" "$t" "$t" "$t" >> "$TMP/t4/u_$t.ts"
done
w4(){ printf '%s\n' "$2" >> "$TMP/t4/u_$1.ts"; }
w4 1 "export const B1 = [{ provide: S1, useClass: H1, ...o }];"
w4 2 "export const B2 = [{ provide: S2, useClass: H2, useClass: null }];"
w4 3 "export const B3 = [{ provide: S3, useClass: H3, [\"provide\"]: OTHER }];"
w4 4 "export const B4 = [{ provide: S4, get provide() { return OTHER; }, useClass: H4 }];"
w4 5 "export const B5 = [{ provide: S5, useClass: H5, useClass() {} }];"
w4 6 "export const B6 = [{ provide: S6, /* a comment */ useClass: H6, multi: true, deps: [OTHER] }];"
w4 7 "reg.remove({ provide: S7, useClass: H7 });"
w4 8 "console.log({ provide: S8, useClass: H8 });"
w4 9 "const O9 = { provide: S9, useClass: H9 }; O9.provide = OTHER; register(O9);"
w4 A "reg.configure({ excluded: [{ provide: SA, useClass: HA }] });"
w4 B "register({ provide: SB, useClass: HB });"
w4 C "makeProviders([{ provide: SC, useClass: HC }]);"
w4 D "export const VP = { viewProviders: [{ provide: SD, useClass: HD }] };"
for t in 1 2 3 4 5 6 7 8 9 A B C D; do run "t4$t" "$TMP/t4" -- --for="which classes are provided for S$t"; done
t4bad=""
for t in 1 2 3 4 5 7 8 9 A B; do out=$( chk row "$TMP/t4$t.xml" S$t n=2 D$t Z$t ) || t4bad="$t4bad S$t: $out;"; done
if [ -z "$t4bad" ]; then ok "T4 a spread / duplicate / computed / accessor / method entry, reg.remove( { … } ), console.log( { … } ), a const object rebound by o.provide = …, reg.configure( { excluded: [ { … } ] } ) and a bare register( { … } ) never list their class (only the two plain array-held literals count)"; else no "T4 $t4bad"; fi
if out=$( chk row "$TMP/t46.xml" S6 n=3 D6 Z6 H6 ); then ok "T4 twin: a plain literal with a comment, multi and deps (an array element in a const) still lists"; else no "T4 twin S6 $out"; fi
if out=$( chk row "$TMP/t4C.xml" SC n=3 DC ZC HC ); then ok "T4 twin: a literal in an array passed to a call lists"; else no "T4 twin SC $out"; fi
if out=$( chk row "$TMP/t4D.xml" SD n=3 DD ZD HD ); then ok "T4 twin: a literal in a viewProviders property lists"; else no "T4 twin SD $out"; fi

# T3 [P]: a function-local `function K() {}` in a file that imports K must not move the file's sites off the imported key
mkdir -p "$TMP/t3" "$TMP/t3b"
printf "export class InjectionToken<T> { constructor(public desc: string) {} }\nexport const HJ = new InjectionToken<any>('hj');\n" > "$TMP/t3/tokens.ts"
printf "export class D {}\nexport class G {}\n" > "$TMP/t3/cl.ts"
cp "$TMP/t3/tokens.ts" "$TMP/t3/cl.ts" "$TMP/t3b/"
printf "import { HJ } from './tokens';\nimport { D, G } from './cl';\nexport const PS = [{ provide: HJ, useClass: D }, { provide: HJ, useClass: G }];\nexport function make() { function HJ() {} return HJ; }\n" > "$TMP/t3/hijack.ts"
printf "import { HJ } from './tokens';\nimport { D, G } from './cl';\nexport const PS = [{ provide: HJ, useClass: D }, { provide: HJ, useClass: G }];\n" > "$TMP/t3b/hijack.ts"
run t3 "$TMP/t3" -- --for="which classes are provided for HJ"
run t3b "$TMP/t3b" -- --for="which classes are provided for HJ"
if out=$( chk nokey "$TMP/t3.xml" HJ ); then ok "T3 a local function HJ in a file that imports HJ: no row (the key is not provable; the sites are not filed under the local symbol)"; else no "T3 $out"; fi
if out=$( chk rowat "$TMP/t3b.xml" HJ tokens.ts n=2 D G ); then ok "T3 twin: the same file without the local function lists D G under the imported key"; else no "T3 twin $out"; fi

# ── CR pre-pass 43b: a registrar FACT is no name evidence (graph.h file-evidence loop). Its qualifier is the scope char "g" and its recvVar the
# registrar METHOD's name, neither a class the file names: read as evidence the scope char made `sys.path.insert` bind by name to an unrelated class `g`
# in another file (GF1 [P], RED on 506801bd). The method's name as recvVar adds nothing the def does not already (GF2 pins that equality); twins GF3 and GF4
# prove real evidence still binds ──────────────────────────────────────────
GF="$TMP/gf"; mkdir -p "$GF/a" "$GF/b" "$GF/c" "$GF/d"
for v in a b c d; do
    printf 'import sys\n\nclass Bus:\n    def on(self, fn):\n        self.subs.append(fn)\n\ndef boot(p):\n    sys.path.insert(0, p)\n' > "$GF/$v/reg.py"
done
printf 'class g:\n    def insert(self, i, v):\n        return (i, v)\n' > "$GF/a/kinds.py"      # the scope char as a class name
printf 'class on:\n    def insert(self, i, v):\n        return (i, v)\n' > "$GF/b/kinds.py"     # the method name as a class name: the DEF is evidence on its own (main, no registrar fact needed)
mkdir -p "$GF/e"; cp "$GF/b/kinds.py" "$GF/e/kinds.py"
printf 'import sys\n\nclass Bus:\n    def on(self, fn):\n        return fn\n\ndef boot(p):\n    sys.path.insert(0, p)\n' > "$GF/e/reg.py"   # the same file with a method that stores nothing: no fact
printf 'class g:\n    def insert(self, i, v):\n        return (i, v)\n' > "$GF/c/kinds.py"      # twin: reg.py really names the class
printf 'class Other:\n    pass\n' > "$GF/d/kinds.py"
printf '\nfrom kinds import g\n\ndef mk():\n    return g()\n' >> "$GF/c/reg.py"
for v in a b c d e; do run "gf$v" "$GF/$v" -- --callees=boot; done
if ! grep -q 'n="g.insert"' "$TMP/gfa.xml"; then ok "GF1 [P] a registrar fact's scope char is no evidence for a class g (sys.path.insert not bound by name)"; else no "GF1 g.insert bound by name: $( grep -o '<s t="[^>]*>' "$TMP/gfa.xml" | head -2 )"; fi
if cmp -s <( sed "s#$GF/b#R#g" "$TMP/gfb.xml" ) <( sed "s#$GF/e#R#g" "$TMP/gfe.xml" ); then ok "GF2 the registrar method's name adds nothing: the answer is byte-identical to the same file whose method stores nothing (a def named like a class is evidence on its own, on main; carded)"; else no "GF2 the fact moved the answer: $( diff <( sed "s#$GF/b#R#g" "$TMP/gfb.xml" | tr '>' '\n' ) <( sed "s#$GF/e#R#g" "$TMP/gfe.xml" | tr '>' '\n' ) | head -3 )"; fi
if grep -q 'n="g.insert"' "$TMP/gfc.xml"; then ok "GF3 twin: a file that really names class g (import + call) still binds g.insert by name"; else no "GF3 twin lost the by-name edge: $( head -c 300 "$TMP/gfc.xml" )"; fi
if ! grep -q 'n="insert"' "$TMP/gfd.xml" || grep -q 'declined' "$TMP/gfd.xml"; then ok "GF4 twin: no class of that method name: the builtin call stays declined"; else no "GF4 $( grep -o '<[sd][c ] [^>]*>' "$TMP/gfd.xml" | head -2 )"; fi

run f1 "$PY" RIPWIRE_NO_REG_ROWS=1 -- --for="$Q_PY"
chk strip "$TMP/p1.xml" "$TMP/p1.strip"; chk strip "$TMP/f1.xml" "$TMP/f1.strip"
if chk none "$TMP/f1.xml" >/dev/null && cmp -s "$TMP/p1.strip" "$TMP/f1.strip"; then ok "F1 handle off: no rows, the rest byte-identical"; else no "F1 handle-off answer differs beyond the rows"; diff <( tr '>' '\n' <"$TMP/p1.strip" ) <( tr '>' '\n' <"$TMP/f1.strip" ) | head -5; fi
run f2 "$PY" -- --for="$Q_PY" --json
if ! grep -q '<reg ' "$TMP/f2.xml"; then ok "F2 --json carries no <reg>"; else no "F2 --json carries <reg>"; fi

run x1 "$PY" -- --for="$Q_PY"
if cmp -s "$TMP/p1.xml" "$TMP/x1.xml"; then ok "X1 deterministic"; else no "X1 two runs differ"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/p1.xml" 2>/dev/null && xmllint --noout "$TMP/p2.xml" 2>/dev/null; then ok "X2 well-formed"; else no "X2 xmllint rejects an answer"; fi
fi

[ "$fail" -eq 0 ] && echo "regsitecheck: PASS" || echo "regsitecheck: FAIL"
exit "$fail"

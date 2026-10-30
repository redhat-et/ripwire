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
#   G2 [G] a token with ONE provider and no shown consumer, named by the question (LONE_TOKEN): no row
#   G3 [G] a lookalike literal `{ name: EVENT_MANAGER_PLUGINS, useClass: LoneThing }` (no provide): LoneThing never listed
#   G4 [G] a decorator registration `@register.filter` (not this slice): no row
#   G5 [G] a question that names neither key nor registered name, with no consumer shown: no row
#   F1 [G] RIPWIRE_NO_REG_ROWS=1: no <reg> and no clause; the P1 answer minus its <reg> rows and clause equals it (est_tokens masked)
#   F2 [G] --json carries no <reg>
#   L1 [P] the clause defines reg when a row prints; L2 [G] absent when none does
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

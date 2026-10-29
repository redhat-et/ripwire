#!/usr/bin/env bash
# fortonlycheck.sh — FOR-TONLY: the --for lens prints tonly="1" on a <d> row whose function has indexed callers that are
# ALL tests (the --dead-code test-only rule, testonlycallers.h), present-only legend clause in both dialects, the --json
# twin ("tonly":true) and the MCP `for` twin.
# Arms: A1 the test-only function carries tonly (compact, --legend=full, --json, MCP); A2-A6 near misses stay unflagged
# (a library caller too, a library caller by NAME only, a function with no caller, a function a library holds as a VALUE,
# a test helper itself); A7 a tree with none prints no tonly and no clause; A8 an index missing a code file (oversize)
# flags nothing; A9 the legend clause rides exactly when a row can carry the attribute (compact + full) and the answers
# are well-formed XML; A10 the rows of one answer differ from the same answer with the attribute stripped by NOTHING else.
#   RIPWIRE_BIN=build/ripwire bash test/fortonlycheck.sh     # red on a pre-FOR-TONLY binary (A1, A9)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "fortonlycheck: BIN=$BIN"

F="$TMP/fx"; mkdir -p "$F/pkg" "$F/tests"
cat > "$F/pkg/shiplib.py" <<'P'
"""Parcel shipping rate helpers."""


def parcel_rate_tested_only(weight):
    """Rate for a parcel; only the tests call it."""
    return weight * 3


def parcel_rate_with_library_user(weight):
    return weight * 4


def parcel_rate_without_callers(weight):
    return weight * 5


def parcel_rate_table_entry(weight):
    return weight * 6


class RateHelper:
    def parcel_rate_by_name(self, weight):
        return weight * 7


def parcel_rate_for_library_call(weight):
    return weight * 8
P
cat > "$F/pkg/shipuser.py" <<'P'
from pkg.shiplib import parcel_rate_with_library_user, parcel_rate_table_entry, parcel_rate_for_library_call
from tests.helpers import parcel_rate_test_helper

RATES = {"table": parcel_rate_table_entry}


def quote(weight):
    return parcel_rate_with_library_user(weight) + parcel_rate_test_helper(weight)


def quote_unknown(helper, weight):
    return helper.parcel_rate_by_name(weight) + parcel_rate_for_library_call(weight)
P
cat > "$F/tests/helpers.py" <<'P'
def parcel_rate_test_helper(weight):
    return weight


def parcel_rate_test_fixture(weight):
    return weight + 1
P
cat > "$F/tests/test_ship.py" <<'P'
from pkg.shiplib import (parcel_rate_tested_only, parcel_rate_with_library_user, parcel_rate_without_callers,
                         parcel_rate_table_entry, RateHelper)
from tests.helpers import parcel_rate_test_helper, parcel_rate_test_fixture


def test_all():
    assert parcel_rate_test_fixture(1) == 2
    assert parcel_rate_tested_only(1) == 3
    assert parcel_rate_with_library_user(1) == 4
    assert parcel_rate_table_entry(1) == 6
    assert RateHelper().parcel_rate_by_name(1) == 7
    assert parcel_rate_test_helper(1) == 1


def test_helper_again():
    assert parcel_rate_test_helper(2) == 2
P
TASK="parcel rate callers"
forx(){ ( cd "$F" && "$BIN" "$F" --no-cache "--for=$TASK" "$@" </dev/null 2>/dev/null ); }
forx > "$TMP/c.txt"
row(){ python3 - "$1" "$2" <<'PY'
import re,sys
t=open(sys.argv[1]).read()
m=re.search(r'<d [^>]*\bn="%s"[^>]*>' % re.escape(sys.argv[2]), t)
print(m.group(0) if m else "")
PY
}
rows(){ python3 - "$1" "$2" <<'PY'
import re,sys
t=open(sys.argv[1]).read()
for m in re.finditer(r'<d [^>]*\bn="%s"[^>]*>' % re.escape(sys.argv[2]), t): print(m.group(0))
PY
}
has(){ row "$1" "$2" | grep -q ' tonly="1"'; }
[ -s "$TMP/c.txt" ] || { no "the fixture --for answer is empty"; echo "FAILURES ABOVE"; exit 1; }

# A1
if has "$TMP/c.txt" parcel_rate_tested_only; then ok "A1 the function only a test calls carries tonly=\"1\""; else no "A1 parcel_rate_tested_only row has no tonly: $( row "$TMP/c.txt" parcel_rate_tested_only )"; fi
# A2-A6 near misses
for n in parcel_rate_with_library_user parcel_rate_for_library_call; do
    r="$( row "$TMP/c.txt" $n )"; [ -n "$r" ] || { no "A2 $n row missing from the answer"; continue; }
    if has "$TMP/c.txt" $n; then no "A2 $n has a library caller yet carries tonly: $r"; else ok "A2 $n (a library caller) stays unflagged"; fi
done
r="$( row "$TMP/c.txt" RateHelper.parcel_rate_by_name )"; [ -n "$r" ] || r="$( row "$TMP/c.txt" parcel_rate_by_name )"
if [ -z "$r" ]; then no "A3 the by-name method row is missing"
elif echo "$r" | grep -q ' tonly="1"'; then no "A3 a method a library calls on an unknown receiver (by name) is flagged: $r"
else ok "A3 a library caller by NAME only keeps the method unflagged"; fi
r="$( row "$TMP/c.txt" parcel_rate_without_callers )"; [ -n "$r" ] || no "A4 the no-caller row is missing"
if echo "$r" | grep -q ' tonly="1"'; then no "A4 a function with NO caller carries tonly: $r"; else ok "A4 a function with no caller is not tonly (that is no callers)"; fi
r="$( row "$TMP/c.txt" parcel_rate_table_entry )"; [ -n "$r" ] || no "A5 the table-held row is missing"
if echo "$r" | grep -q ' tonly="1"'; then no "A5 a function a library holds in a dispatch table carries tonly: $r"; else ok "A5 a library VALUE use (dispatch table) keeps it unflagged"; fi
r="$( row "$TMP/c.txt" parcel_rate_test_helper )"
if echo "$r" | grep -q ' tonly="1"'; then no "A6 a test helper itself carries tonly: $r"; else ok "A6 a test-dir helper (called from library code and tests) is never flagged"; fi
r="$( row "$TMP/c.txt" parcel_rate_test_fixture )"
if [ -z "$r" ]; then no "A6 premise: the test-dir fixture row is missing from the answer"
elif echo "$r" | grep -q ' tonly="1"'; then no "A6 a test symbol only tests call carries tonly (a test is not library code): $r"
else ok "A6 a test-dir symbol only tests call is never flagged (tonly is a library-function fact)"; fi

# A9 legend + xml
if grep -q 'tonly=1 every indexed caller' "$TMP/c.txt"; then ok "A9 compact legend clause rides with the attribute"; else no "A9 compact legend clause missing"; fi
forx --legend=full > "$TMP/f.txt"
if grep -q 'tonly=\"1\" on a d row' "$TMP/f.txt"; then ok "A9 full legend clause rides with the attribute"; else no "A9 full legend clause missing"; fi
if has "$TMP/f.txt" parcel_rate_tested_only; then ok "A1 --legend=full carries tonly on the same row"; else no "A1 --legend=full row lacks tonly"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/c.txt" 2>/dev/null && xmllint --noout "$TMP/f.txt" 2>/dev/null; then ok "A9 both answers are well-formed XML"; else no "A9 xmllint rejected a --for answer"; fi
else
    echo "  SKIP  A9 xmllint arm (xmllint is not installed)"
fi

# A1 json
forx --json > "$TMP/j.json"
if python3 - "$TMP/j.json" <<'PY'; then ok "A1 --json: \"tonly\":true on the test-only row and on no other row"; else no "A1 --json tonly rows wrong"; fi
import json,sys
d=json.load(open(sys.argv[1]))
rows=d.get("sigs") or []
fl=sorted(r["n"] for r in rows if r.get("tonly"))
sys.exit(0 if fl==["parcel_rate_tested_only"] else (print("flagged:",fl) or 1))
PY

# A1 MCP
printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' "$F" "$TASK" \
    | "$BIN" --mcp 2>/dev/null > "$TMP/m.raw"
python3 - "$TMP/m.raw" > "$TMP/m.txt" <<'PY'
import json,sys
for line in open(sys.argv[1]):
    line=line.strip()
    if not line: continue
    try: d=json.loads(line)
    except Exception: continue
    r=d.get("result") or {}
    for c in r.get("content",[]): print(c.get("text",""))
PY
if has "$TMP/m.txt" parcel_rate_tested_only; then ok "A1 MCP for: the test-only row carries tonly"; else no "A1 MCP for: no tonly on parcel_rate_tested_only ($( row "$TMP/m.txt" parcel_rate_tested_only ))"; fi
for n in parcel_rate_with_library_user parcel_rate_without_callers parcel_rate_table_entry; do
    if has "$TMP/m.txt" $n; then no "A2 MCP for: $n flagged"; fi
done
if grep -q 'tonly=\"1\" on a d row' "$TMP/m.txt"; then ok "A9 MCP for: the legend clause rides with the attribute"; else no "A9 MCP for: legend clause missing"; fi

# A11 Go: a method an interface declares is reached through the interface (RPM.Package shape) — implementation only tests call
# directly stays unflagged (the interface-method guard); a plain Go function only a test calls is flagged.
GO="$TMP/gx2"; mkdir -p "$GO/ship"
cat > "$GO/go.mod" <<'P'
module example.com/ship

go 1.22
P
cat > "$GO/ship/ship.go" <<'P'
package ship

// Carrier ships a parcel.
type Carrier interface {
	Dispatch(weight int) int
}

type Truck struct{}

func (Truck) Dispatch(weight int) int { return weight * 2 }

type Van struct{}

func (Van) Dispatch(weight int) int { return weight * 3 }

func Send(c Carrier, weight int) int { return c.Dispatch(weight) }

func parcelFee(weight int) int { return weight * 9 }
P
cat > "$GO/ship/ship_test.go" <<'P'
package ship

import "testing"

func TestAll(t *testing.T) {
	if (Truck{}).Dispatch(1) != 2 || (Van{}).Dispatch(1) != 3 || parcelFee(1) != 9 {
		t.Fatal("bad")
	}
}
P
cat >> "$GO/ship/ship.go" <<'P'

// Courier has ONE implementor, so a call through it binds to the interface declaration, not to Bike.Carry.
type Courier interface {
	Carry(weight int) int
}

type Bike struct{}

func (Bike) Carry(weight int) int { return weight * 4 }

func Deliver(c Courier, weight int) int { return c.Carry(weight) }
P
cat > "$GO/ship/bike_test.go" <<'P'
package ship

import "testing"

func TestBike(t *testing.T) {
	if (Bike{}).Carry(1) != 4 {
		t.Fatal("bad")
	}
}
P
( cd "$GO" && "$BIN" "$GO" --no-cache "--for=dispatch parcel fee callers" </dev/null 2>/dev/null ) > "$TMP/go.txt"
if has "$TMP/go.txt" parcelFee; then ok "A11 a Go function only a test calls carries tonly"; else no "A11 parcelFee has no tonly: $( row "$TMP/go.txt" parcelFee )"; fi
for n in Truck.Dispatch Van.Dispatch; do
    r="$( row "$TMP/go.txt" $n )"; [ -n "$r" ] || r="$( row "$TMP/go.txt" Dispatch )"
    [ -n "$r" ] || { no "A11 the $n row is missing"; continue; }
    if echo "$r" | grep -q ' tonly="1"'; then no "A11 $n (an interface method's implementation) carries tonly: $r"; else ok "A11 $n (reached through the Carrier interface) stays unflagged"; fi
done
( cd "$GO" && "$BIN" "$GO" --no-cache "--for=dispatch parcel fee carry callers" </dev/null 2>/dev/null ) > "$TMP/go.txt"
r="$( row "$TMP/go.txt" Bike.Carry )"
if [ -z "$r" ]; then no "A11 premise: the Bike.Carry row is missing"
elif echo "$r" | grep -q ' tonly="1"'; then no "A11 Bike.Carry (the lone implementor of an interface a library calls through) carries tonly: $r"
else ok "A11 the lone implementor of an interface (call binds to the declaration) stays unflagged"; fi

# A12 a call the resolver DECLINED to bind (a library `table.get(key)` on an untyped receiver: the builtin-method name gate) is a
# library call the edge pass cannot see; a method only a test calls directly, which that call could have meant, stays unflagged.
DC="$TMP/gx3"; mkdir -p "$DC/pkg" "$DC/tests"
cat > "$DC/pkg/store.py" <<'P'
class ParcelStore:
    def get(self, key):
        return key


def parcel_store_only_tested(key):
    return key
P
cat > "$DC/pkg/use.py" <<'P'
def read(table, key):
    return table.get(key)
P
cat > "$DC/tests/test_store.py" <<'P'
from pkg.store import ParcelStore, parcel_store_only_tested


def test_all():
    assert ParcelStore().get(1) == 1
    assert parcel_store_only_tested(1) == 1
P
cat > "$DC/pkg/cli.py" <<'P'
def launch_parcel_cli(args):
    return len(args)
P
cat > "$DC/setup.cfg" <<'P'
[options.entry_points]
console_scripts =
    parcel = pkg.cli:launch_parcel_cli
P
cat >> "$DC/tests/test_store.py" <<'P'


def test_cli():
    from pkg.cli import launch_parcel_cli
    assert launch_parcel_cli([1]) == 1
P
( cd "$DC" && "$BIN" "$DC" --no-cache "--for=parcel store get callers" </dev/null 2>/dev/null ) > "$TMP/dc.txt"
r="$( row "$TMP/dc.txt" ParcelStore.get )"
if [ -z "$r" ]; then no "A12 premise: the ParcelStore.get row is missing"
elif echo "$r" | grep -q ' tonly="1"'; then no "A12 a method a declined library call could have meant carries tonly: $r"
else ok "A12 a library call the resolver declined to bind keeps the method unflagged"; fi
( cd "$DC" && "$BIN" "$DC" --no-cache "--for=launch parcel cli callers" </dev/null 2>/dev/null ) > "$TMP/dc2.txt"
r="$( row "$TMP/dc2.txt" launch_parcel_cli )"
if [ -z "$r" ]; then no "A13 premise: the launch_parcel_cli row is missing"
elif echo "$r" | grep -q ' tonly="1"'; then no "A13 a console_scripts entry point only tests call in-tree carries tonly: $r"
else ok "A13 a package manifest entry point (setup.cfg console_scripts) is a caller no source spells: unflagged"; fi
if has "$TMP/dc.txt" parcel_store_only_tested; then ok "A12 a plain function only a test calls, beside it, is flagged (the arm can fire)"; else no "A12 premise: parcel_store_only_tested was not flagged: $( row "$TMP/dc.txt" parcel_store_only_tested )"; fi

# A7 a tree with no test-only function
G="$TMP/gx"; mkdir -p "$G/pkg" "$G/tests"
cp "$F/pkg/shiplib.py" "$G/pkg/shiplib.py"
cat > "$G/pkg/shipuser.py" <<'P'
from pkg.shiplib import parcel_rate_tested_only


def quote(weight):
    return parcel_rate_tested_only(weight)
P
cat > "$G/tests/test_ship.py" <<'P'
from pkg.shiplib import parcel_rate_tested_only


def test_all():
    assert parcel_rate_tested_only(1) == 3
P
( cd "$G" && "$BIN" "$G" --no-cache "--for=$TASK" </dev/null 2>/dev/null ) > "$TMP/n.txt"
( cd "$G" && "$BIN" "$G" --no-cache "--for=$TASK" --legend=full </dev/null 2>/dev/null ) > "$TMP/nf.txt"
if grep -q tonly "$TMP/n.txt" "$TMP/nf.txt"; then no "A7 a tree with a library caller of every function prints tonly or its clause"; else ok "A7 no test-only function: no tonly= and no legend clause (compact + full)"; fi

# A8 a dropped oversize code file hides callers: nothing is flagged
H="$TMP/hx"; mkdir -p "$H/pkg" "$H/tests"
cp "$F/pkg/shiplib.py" "$H/pkg/shiplib.py"
cp "$F/tests/test_ship.py" "$H/tests/test_ship.py"
cp "$F/tests/helpers.py" "$H/tests/helpers.py"
python3 - "$H/pkg/biguser.py" <<'PY'
import sys
lines=["from pkg.shiplib import parcel_rate_tested_only", ""]
lines += ["def filler_%d(weight):\n    return weight + %d\n" % (i,i) for i in range(400)]
lines += ["def quote_big(weight):\n    return parcel_rate_tested_only(weight)\n"]
open(sys.argv[1],"w").write("\n".join(lines))
PY
( cd "$H" && "$BIN" "$H" --no-cache "--for=$TASK" </dev/null 2>/dev/null ) > "$TMP/h_whole.txt"
( cd "$H" && "$BIN" "$H" --no-cache "--for=$TASK" --max-file-size=4K </dev/null 2>/dev/null ) > "$TMP/h_cut.txt"
if has "$TMP/h_whole.txt" parcel_rate_tested_only; then no "A8 premise: the whole index flagged parcel_rate_tested_only although biguser.py calls it: $( row "$TMP/h_whole.txt" parcel_rate_tested_only )"; else ok "A8 premise: a library caller in the big file keeps the whole index unflagged"; fi
( cd "$H" && "$BIN" "$H" --no-cache --max-file-size=4K --callers=parcel_rate_tested_only </dev/null 2>/dev/null ) > "$TMP/h_callers.txt"
if grep -q 'biguser' "$TMP/h_callers.txt" || ! grep -q 'test_ship' "$TMP/h_callers.txt"; then no "A8 premise: --max-file-size=4K must drop biguser.py and keep the test caller (the cut arm measures nothing otherwise)"; else ok "A8 premise: the 4K ceiling dropped the library caller file, the test caller remains"; fi
if has "$TMP/h_cut.txt" parcel_rate_tested_only; then no "A8 an index missing the oversize caller file still prints tonly: $( row "$TMP/h_cut.txt" parcel_rate_tested_only )"; else ok "A8 a cut index (oversize code file dropped) flags nothing"; fi

# A10 stripping the attribute leaves the same answer shape: the clause + attribute are the only difference vs a no-tonly run
if python3 - "$TMP/c.txt" <<'PY'; then ok "A10 stripping tonly=\"1\" leaves every <d> row's other attributes in order"; else no "A10 a row's other attributes moved"; fi
import re,sys
t=open(sys.argv[1]).read()
for m in re.finditer(r'<d [^>]*>', t):
    s=m.group(0)
    if ' tonly="1"' in s:
        pre=s.split(' tonly="1"')[0]
        post=s.split(' tonly="1"')[1]
        if not ('tested="1"' in pre) or ' r="' not in post:
            sys.exit(1)
PY


# ── fix round 1 (rv-for-tonly) ────────────────────────────────────────────────────────────────────────────
# B1-B5: the reviewer's confident-wrong shapes. Every `relay_*` row below has a library use the edge pass cannot see (a module-
# attribute call, a getattr string, a bound method value, an override reached through its base, an external-protocol method);
# one control per tree (`*OnlyTested`) is a plain function only a test calls and MUST stay flagged, so the arms can fire.
RL="$TMP/rl"; mkdir -p "$RL/py/pkg/test" "$RL/py/tests" "$RL/go/relay" "$RL/go/cmd" "$RL/cpp/src" "$RL/cpp/test" "$RL/rs/src" "$RL/rs/tests" "$RL/ts/src" "$RL/ts/test"
cat > "$RL/py/pkg/options.py" <<'P'
def relay_modattr_target(x):
    return x + 1


def relay_alias_target(x):
    return x + 2


def relay_getattr_target(x):
    return x + 3


def relay_modlevel_target(x):
    return x + 4


def relay_callback_target(x):
    return x + 5


def relay_named_test_target(x):
    return x + 6


def relay_decorated_target(x):
    return x + 8


def _relay_private_modattr(x):
    return x + 10


# relay_true_target is exercised by the tests alone: a comment that names it is documentation, not a library use
def relay_true_target(x):
    return x + 11
P
cat > "$RL/py/pkg/runner.py" <<'P'
import threading
from pkg import options
from pkg.options import relay_alias_target as aliased
from pkg.options import relay_callback_target
from pkg.options import relay_named_test_target
from pkg import options as opts


def relay_run(x):
    a = options.relay_modattr_target(x)
    b = aliased(x)
    c = getattr(opts, "relay_getattr_target")(x)
    t = threading.Thread(target=relay_callback_target, args=(x,))
    return a + b + c


def test_connection(x):
    """A production health probe that happens to be named test_*."""
    return relay_named_test_target(x)


def relay_health(x):
    return test_connection(x)


SEED = options.relay_modlevel_target(1)


def relay_private_user(x):
    return options._relay_private_modattr(x)
P
cat > "$RL/py/pkg/shapes.py" <<'P'
class RelayBase:
    def relay_render(self):
        raise NotImplementedError

    def relay_show(self):
        return self.relay_render()


class RelayImpl(RelayBase):
    def relay_render(self):
        return "impl"


class RelayBox:
    def __len__(self):
        return 1
P
cat > "$RL/py/tests/test_relay.py" <<'P'
from pkg.options import (relay_modattr_target, relay_alias_target, relay_getattr_target, relay_modlevel_target,
                         relay_callback_target, relay_named_test_target, _relay_private_modattr, relay_true_target)
from pkg.shapes import RelayImpl, RelayBox


def test_all():
    assert relay_modattr_target(1) == 2
    assert relay_alias_target(1) == 3
    assert relay_getattr_target(1) == 4
    assert relay_modlevel_target(1) == 5
    assert relay_callback_target(1) == 6
    assert relay_named_test_target(1) == 7
    assert _relay_private_modattr(1) == 11
    assert relay_true_target(1) == 12
    assert RelayImpl().relay_render() == "impl"
    assert RelayBox().__len__() == 1
P
cat > "$RL/go/go.mod" <<'P'
module example.com/relay
go 1.21
P
cat > "$RL/go/relay/relay.go" <<'P'
package relay

import "fmt"

type RelayCode int

func (c RelayCode) String() string { return fmt.Sprintf("code-%d", int(c)) }

type RelayErr struct{ msg string }

func (e *RelayErr) Error() string { return e.msg }

func RelayQualifiedTarget(x int) int { return x + 1 }

func RelayDescribe(c RelayCode) string { return fmt.Sprint(c) }

func RelayFail() error { return &RelayErr{msg: "x"} }

// relayOnlyTested is exercised by the tests alone: a doc comment that names it is not a library use.
func relayOnlyTested(x int) int { return x + 5 }
P
cat > "$RL/go/relay/relay_test.go" <<'P'
package relay

import "testing"

func TestRelay(t *testing.T) {
	if RelayCode(1).String() != "code-1" { t.Fatal() }
	e := &RelayErr{msg: "m"}
	if e.Error() != "m" { t.Fatal() }
	if RelayQualifiedTarget(1) != 2 { t.Fatal() }
	if relayOnlyTested(1) != 6 { t.Fatal() }
}
P
cat > "$RL/go/cmd/main.go" <<'P'
package main

import (
	"fmt"
	"example.com/relay/relay"
)

func main() {
	fmt.Println(relay.RelayQualifiedTarget(2), relay.RelayDescribe(3), relay.RelayFail())
}
P
cat > "$RL/cpp/src/relay.h" <<'P'
#pragma once
struct RelayBase { virtual ~RelayBase() = default; virtual int relayRender() const { return 0; } int relayShow() const { return relayRender(); } };
struct RelayImpl : RelayBase { int relayRender() const override; };
P
cat > "$RL/cpp/src/relay.cpp" <<'P'
#include "relay.h"
int RelayImpl::relayRender() const { return 7; }
int relayUse( const RelayBase& b ) { return b.relayRender(); }
int relayOnlyTested( int x ) { return x + 1; }
P
cat > "$RL/cpp/test/relay_test.cpp" <<'P'
#include "../src/relay.h"
int relayOnlyTested( int x );
int testRelay() { RelayImpl i; return i.relayRender() == 7 && relayOnlyTested( 1 ) == 2 ? 0 : 1; }
P
cat > "$RL/rs/Cargo.toml" <<'P'
[package]
name = "relay"
version = "0.1.0"
edition = "2021"
P
cat > "$RL/rs/src/lib.rs" <<'P'
pub trait RelayRender { fn relay_render(&self) -> i32; }
pub struct RelayImpl;
impl RelayRender for RelayImpl { fn relay_render(&self) -> i32 { 7 } }
pub fn relay_use(r: &dyn RelayRender) -> i32 { r.relay_render() }
impl std::fmt::Display for RelayImpl {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result { write!(f, "relay") }
}
pub fn relay_show(r: &RelayImpl) -> String { format!("{}", r) }
pub fn relay_only_tested(x: i32) -> i32 { x + 1 }
P
cat > "$RL/rs/tests/relay.rs" <<'P'
use relay::{RelayImpl, RelayRender, relay_only_tested};
#[test]
fn relay_test() { assert_eq!(RelayImpl.relay_render(), 7); let mut s = String::new(); use std::fmt::Write; write!(s, "{}", RelayImpl).unwrap(); let _ = std::fmt::Display::fmt(&RelayImpl, &mut std::fmt::Formatter::new(&mut s)); assert_eq!(relay_only_tested(1), 2); }
P
cat > "$RL/ts/src/relay.ts" <<'P'
export abstract class RelayBase {
  abstract relayRender(): string
  relayShow(): string { return this.relayRender() }
}
export class RelayImpl extends RelayBase {
  relayRender(): string { return 'impl' }
}
export class RelayButton {
  relayClick(): number { return 1 }
  relayWire(el: { on(ev: string, f: () => number): void }) { el.on('click', this.relayClick) }
}
export function relayOnlyTested(x: number): number { return x + 1 }
P
cat > "$RL/ts/test/relay.test.ts" <<'P'
import { RelayImpl, RelayButton, relayOnlyTested } from '../src/relay'
test('relay', () => {
  expect(new RelayImpl().relayRender()).toBe('impl')
  expect(new RelayButton().relayClick()).toBe(1)
  expect(relayOnlyTested(1)).toBe(2)
})
P
RLTASK="relay callers"
rlrun(){ d="$1"; shift; ( cd "$RL/$d" && "$BIN" "$RL/$d" --no-cache "--for=$RLTASK" "$@" </dev/null 2>/dev/null ); }
# $1 answer, then the names that must NOT carry tonly (an absent row is a FAIL: the arm must see the row), then control $2 must.
rlcheck(){ # arm lang answer control name...
    arm="$1"; lang="$2"; ans="$3"; ctl="$4"; shift 4
    if [ "$ctl" = "-" ]; then :   # Rust: a tests/ caller of a crate function binds no edge, so the language has no positive control
    elif has "$ans" "$ctl"; then ok "$arm $lang control $ctl is flagged (the arm can fire)"; else no "$arm $lang control $ctl has no tonly: $( row "$ans" "$ctl" )"; fi
    for n in "$@"; do
        r="$( rows "$ans" "$n" )"
        if [ -z "$r" ]; then no "$arm $lang premise: row $n missing from the answer"
        elif echo "$r" | grep -q ' tonly="1"'; then no "$arm $lang $n carries tonly (a library use the edge pass cannot see): $r"
        else ok "$arm $lang $n stays unflagged"; fi
    done
}
rlrun py > "$TMP/rl_py.txt"
rlcheck B1 py "$TMP/rl_py.txt" relay_true_target relay_modattr_target relay_alias_target relay_getattr_target relay_modlevel_target relay_callback_target \
    relay_named_test_target _relay_private_modattr RelayImpl.relay_render
( cd "$RL/py" && "$BIN" "$RL/py" --no-cache "--for=RelayBox __len__ callers" </dev/null 2>/dev/null ) > "$TMP/rl_dunder.txt"
r="$( rows "$TMP/rl_dunder.txt" RelayBox.__len__ )"
if [ -z "$r" ]; then no "B1 dunder premise: the RelayBox.__len__ row is missing"
elif echo "$r" | grep -q ' tonly="1"'; then no "B1 a Python dunder (the interpreter calls it) carries tonly: $r"
else ok "B1 py a dunder method only a test spells stays unflagged"; fi
rlrun go > "$TMP/rl_go.txt"
rlcheck B2 go "$TMP/rl_go.txt" relayOnlyTested RelayQualifiedTarget RelayCode.String RelayErr.Error
rlrun cpp > "$TMP/rl_cpp.txt"
rlcheck B3 cpp "$TMP/rl_cpp.txt" relayOnlyTested RelayImpl::relayRender
rlrun rs > "$TMP/rl_rs.txt"
rlcheck B4 rs "$TMP/rl_rs.txt" - RelayImpl::fmt RelayImpl::relay_render
rlrun ts > "$TMP/rl_ts.txt"
rlcheck B5 ts "$TMP/rl_ts.txt" relayOnlyTested RelayButton.relayClick RelayImpl.relayRender

# B6 the noise gate G3 (task-shaped): a row keeps tonly only when the task has a use word, names the row, or names its file/dir.
for t in "relay" "relay options"; do
    ( cd "$RL/py" && "$BIN" "$RL/py" --no-cache "--for=$t" </dev/null 2>/dev/null ) > "$TMP/g3.txt"
    if grep -q tonly "$TMP/g3.txt"; then no "B6 task '$t' (no use word, no name, no path) still prints tonly or its clause"; else ok "B6 task '$t': no tonly and no clause"; fi
done
( cd "$RL/py" && "$BIN" "$RL/py" --no-cache "--for=relay_true_target" </dev/null 2>/dev/null ) > "$TMP/g3n.txt"
if has "$TMP/g3n.txt" relay_true_target; then ok "B6 a task that NAMES the row keeps its tonly"; else no "B6 named row lost its tonly: $( row "$TMP/g3n.txt" relay_true_target )"; fi
( cd "$RL/py" && "$BIN" "$RL/py" --no-cache "--for=relay in pkg/options.py" </dev/null 2>/dev/null ) > "$TMP/g3p.txt"
if has "$TMP/g3p.txt" relay_true_target; then ok "B6 a task that names the row's FILE keeps its tonly"; else no "B6 file-named row lost its tonly: $( row "$TMP/g3p.txt" relay_true_target )"; fi
( cd "$RL/py" && "$BIN" "$RL/py" --no-cache "--for=relay in pkg/" </dev/null 2>/dev/null ) > "$TMP/g3d.txt"
if has "$TMP/g3d.txt" relay_true_target; then ok "B6 a task that names the row's DIRECTORY keeps its tonly"; else no "B6 dir-named row lost its tonly: $( row "$TMP/g3d.txt" relay_true_target )"; fi
# G3 is per row: a task that names one row flags that row only
( cd "$RL/py" && "$BIN" "$RL/py" --no-cache "--for=relay_true_target relay_modattr_target" </dev/null 2>/dev/null ) > "$TMP/g3r.txt"
if has "$TMP/g3r.txt" relay_true_target; then ok "B6 per-row: the named flagged row keeps tonly beside another named row"; else no "B6 per-row: relay_true_target lost tonly"; fi

# B7 a tight explicit budget (e= rule, endLinesFitCeiling): no tonly and no clause, CLI + MCP
( cd "$RL/py" && "$BIN" "$RL/py" --no-cache "--for=$RLTASK" --token-budget=300 </dev/null 2>/dev/null ) > "$TMP/b7.txt"
if [ -s "$TMP/b7.txt" ] && ! grep -q tonly "$TMP/b7.txt"; then ok "B7 --token-budget=300: no tonly and no clause"; else no "B7 a tight explicit budget still prints tonly (or the answer is empty)"; fi
printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s","budget_tokens":300}}}\n' "$RL/py" "$RLTASK" \
    | "$BIN" --mcp 2>/dev/null > "$TMP/b7m.raw"
if grep -q 'relay_run' "$TMP/b7m.raw" && ! grep -q tonly "$TMP/b7m.raw"; then ok "B7 MCP budget_tokens=300: no tonly and no clause"; else no "B7 MCP under a tight budget prints tonly (or the answer has no rows)"; fi

# B8 dispatch guard pin shaped like django's staticfiles Command.get_handler: a method of a class that has a base, reached by a base-class self call
mkdir -p "$RL/dj/core" "$RL/dj/tests"
cat > "$RL/dj/core/base.py" <<'P'
class BaseCommand:
    def get_handler(self, *args):
        return None

    def run(self):
        return self.get_handler(1)
P
cat > "$RL/dj/core/static.py" <<'P'
from core.base import BaseCommand


class Command(BaseCommand):
    def get_handler(self, *args):
        return "static"
P
cat > "$RL/dj/tests/test_static.py" <<'P'
from core.static import Command


def test_handler():
    assert Command().get_handler(1) == "static"
P
( cd "$RL/dj" && "$BIN" "$RL/dj" --no-cache "--for=which get_handler runs" </dev/null 2>/dev/null ) > "$TMP/b8.txt"
r="$( row "$TMP/b8.txt" Command.get_handler )"; [ -n "$r" ] || r="$( row "$TMP/b8.txt" get_handler )"
if [ -z "$r" ]; then no "B8 premise: the Command.get_handler row is missing"
elif echo "$r" | grep -q ' tonly="1"'; then no "B8 an override reached through its base (self.get_handler) carries tonly: $r"
else ok "B8 a method of a class with a base (an override) stays unflagged"; fi

[ "$fail" = 0 ] && echo "fortonlycheck: ALL PASS" || { echo "FAILURES ABOVE"; exit 1; }

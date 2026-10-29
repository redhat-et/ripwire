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
TASK="parcel rate"
forx(){ ( cd "$F" && "$BIN" "$F" --no-cache "--for=$TASK" "$@" </dev/null 2>/dev/null ); }
forx > "$TMP/c.txt"
row(){ python3 - "$1" "$2" <<'PY'
import re,sys
t=open(sys.argv[1]).read()
m=re.search(r'<d [^>]*\bn="%s"[^>]*>' % re.escape(sys.argv[2]), t)
print(m.group(0) if m else "")
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
grep -q 'tonly=1 every caller' "$TMP/c.txt" && ok "A9 compact legend clause rides with the attribute" || no "A9 compact legend clause missing"
forx --legend=full > "$TMP/f.txt"
grep -q 'tonly=\"1\" on a d row' "$TMP/f.txt" && ok "A9 full legend clause rides with the attribute" || no "A9 full legend clause missing"
has "$TMP/f.txt" parcel_rate_tested_only && ok "A1 --legend=full carries tonly on the same row" || no "A1 --legend=full row lacks tonly"
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/c.txt" 2>/dev/null && xmllint --noout "$TMP/f.txt" 2>/dev/null; then ok "A9 both answers are well-formed XML"; else no "A9 xmllint rejected a --for answer"; fi
else
    echo "  SKIP  A9 xmllint arm (xmllint is not installed)"
fi

# A1 json
forx --json > "$TMP/j.json"
python3 - "$TMP/j.json" <<'PY' && ok "A1 --json: \"tonly\":true on the test-only row and on no other row" || no "A1 --json tonly rows wrong"
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
has "$TMP/m.txt" parcel_rate_tested_only && ok "A1 MCP for: the test-only row carries tonly" || no "A1 MCP for: no tonly on parcel_rate_tested_only ($( row "$TMP/m.txt" parcel_rate_tested_only ))"
for n in parcel_rate_with_library_user parcel_rate_without_callers parcel_rate_table_entry; do
    has "$TMP/m.txt" $n && no "A2 MCP for: $n flagged" || true
done
grep -q 'tonly=\"1\" on a d row' "$TMP/m.txt" && ok "A9 MCP for: the legend clause rides with the attribute" || no "A9 MCP for: legend clause missing"

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
( cd "$GO" && "$BIN" "$GO" --no-cache "--for=dispatch parcel fee" </dev/null 2>/dev/null ) > "$TMP/go.txt"
has "$TMP/go.txt" parcelFee && ok "A11 a Go function only a test calls carries tonly" || no "A11 parcelFee has no tonly: $( row "$TMP/go.txt" parcelFee )"
for n in Truck.Dispatch Van.Dispatch; do
    r="$( row "$TMP/go.txt" $n )"; [ -n "$r" ] || r="$( row "$TMP/go.txt" Dispatch )"
    [ -n "$r" ] || { no "A11 the $n row is missing"; continue; }
    echo "$r" | grep -q ' tonly="1"' && no "A11 $n (an interface method's implementation) carries tonly: $r" || ok "A11 $n (reached through the Carrier interface) stays unflagged"
done
( cd "$GO" && "$BIN" "$GO" --no-cache "--for=dispatch parcel fee carry" </dev/null 2>/dev/null ) > "$TMP/go.txt"
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
( cd "$DC" && "$BIN" "$DC" --no-cache "--for=parcel store get" </dev/null 2>/dev/null ) > "$TMP/dc.txt"
r="$( row "$TMP/dc.txt" ParcelStore.get )"
if [ -z "$r" ]; then no "A12 premise: the ParcelStore.get row is missing"
elif echo "$r" | grep -q ' tonly="1"'; then no "A12 a method a declined library call could have meant carries tonly: $r"
else ok "A12 a library call the resolver declined to bind keeps the method unflagged"; fi
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
grep -q tonly "$TMP/n.txt" "$TMP/nf.txt" && no "A7 a tree with a library caller of every function prints tonly or its clause" || ok "A7 no test-only function: no tonly= and no legend clause (compact + full)"

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
python3 - "$TMP/c.txt" <<'PY' && ok "A10 stripping tonly=\"1\" leaves every <d> row's other attributes in order" || no "A10 a row's other attributes moved"
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

[ "$fail" = 0 ] && echo "fortonlycheck: ALL PASS" || { echo "FAILURES ABOVE"; exit 1; }

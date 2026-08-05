#!/usr/bin/env bash
# lintscopecheck.sh — built-in lint findings stay inside the AST construct that owns them.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIXTURE="$TMP/fixture"
mkdir -p "$FIXTURE"

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

cat >"$FIXTURE/scope.cpp" <<'CPP'
int cleanContexts( int n )
{
    auto stop = []()
    {
        return;
    };
    constexpr int kLimit = 42;
    const int threshold = 100;
    int out = n; int sum = 0;
    out = threshold; sum += out;
    stop();
    return out + sum + kLimit;
}

int badReturn( int n )
{
    if( n < 0 )
    {
        return;
    }
    return n * 1;
}

int subscriptedConditionReturn( const int* flags )
{
    if( flags[0] )
    {
        return;
    }
    return 1;
}

void badSelfAssign( int n )
{
    n = n;
}

int badMagic( int n )
{
    return n * 99;
}
CPP

"$BIN" "$FIXTURE" --lint --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$FIXTURE" --lint --no-cache >"$TMP/b" 2>/dev/null
cmp -s "$TMP/a" "$TMP/b" || { echo "FAIL lint scope output is not deterministic"; exit 1; }

python3 - "$TMP/a" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()

def findings(rule):
    return [node for node in root.findall("f") if node.get("rule") == rule]

expected = {
    "inconsistent-return": ("badReturn", "subscriptedConditionReturn"),
    "self-assign": ("badSelfAssign",),
    "magic-number": ("badMagic",),
}
for rule, owners in expected.items():
    found = findings(rule)
    got = tuple(node.get("in") for node in found)
    if got != owners:
        detail = [(node.get("in"), node.get("p"), node.text) for node in found]
        raise SystemExit(f"FAIL {rule}: expected owners {owners}, found {detail}")

print("PASS nested-callable, assignment-parent, and constant-initializer scopes are precise")
PY

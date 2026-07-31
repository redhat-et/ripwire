#!/usr/bin/env bash
# isolateprovenancecheck.sh — A5 exact-degree and provenance-reporting gate.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIXTURE="$TMP/fixture"
mkdir -p "$FIXTURE"

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

cat >"$FIXTURE/api.h" <<'CPP'
int declarationOnly( int value );
inline int headerBody( int value ) { return value + 7; }
CPP
cat >"$FIXTURE/main.cpp" <<'CPP'
#include "api.h"
static int sourceOrphan( int value ) { return value + 9; }
static int connectedLeaf( int value ) { return value + 1; }
int connectedRoot( int value ) { return connectedLeaf( value ); }
CPP
cat >"$FIXTURE/notes.md" <<'MD'
# Standalone Design Note
MD

for verb in communities report; do
    "$BIN" "$FIXTURE" "--$verb" --no-cache >"$TMP/$verb.a" 2>/dev/null
    "$BIN" "$FIXTURE" "--$verb" --no-cache >"$TMP/$verb.b" 2>/dev/null
    diff -q "$TMP/$verb.a" "$TMP/$verb.b" >/dev/null || { echo "FAIL $verb is not deterministic"; exit 1; }
done

python3 - "$TMP/communities.a" "$TMP/report.a" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET

community_path, report_path = sys.argv[1:]
root = ET.parse(community_path).getroot()
names = ("isolated_decl", "isolated_header", "isolated_source", "isolated_doc")
values = []
for name in names:
    value = root.get(name)
    if value is None:
        raise SystemExit(f"FAIL communities missing {name}")
    values.append(int(value))
if any(value < 1 for value in values):
    raise SystemExit(f"FAIL fixture must exercise every mutually-exclusive provenance bucket: {values}")
if sum(values) != int(root.get("isolated", "-1")):
    raise SystemExit("FAIL isolate provenance buckets do not sum to exact isolated total")
if root.get("connected_singletons") is None:
    raise SystemExit("FAIL communities missing connected_singletons distinction")

report = open(report_path, encoding="utf-8").read()
match = re.search(
    r"Call-graph isolate provenance: (\d+) declaration, (\d+) header, (\d+) source, (\d+) document",
    report,
)
if not match or [int(value) for value in match.groups()] != values:
    raise SystemExit("FAIL report provenance line is absent or disagrees with XML")

print(f"PASS isolated={sum(values)} provenance={values} connected_singletons={root.get('connected_singletons')}")
PY

#!/usr/bin/env bash
# lintcatalogcheck.sh — L7 gate: the built-in --lint rule registry (src/lintcatalog.h, --lint-catalog).
#
#   1) every rule name --lint's own tally emits appears in --lint-catalog, and vice versa (no drift
#      between the registry and the actual built-in rule set).
#   2) every --lint-catalog row has non-empty severity/category/rationale/languages/since.
#
#   RIPWIRE_BIN=build/ripwire bash test/lintcatalogcheck.sh
#   RIPWIRE_BIN=asan/ripwire  bash test/lintcatalogcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

# --lint-catalog needs no corpus at all — but the CLI still takes a positional dir, so pass one.
"$BIN" "$ROOT" --lint-catalog >"$TMP/catalog1" 2>/dev/null
"$BIN" "$ROOT" --lint-catalog >"$TMP/catalog2" 2>/dev/null
cmp -s "$TMP/catalog1" "$TMP/catalog2" && ok "--lint-catalog is deterministic (byte-identical run-to-run)" \
    || no "--lint-catalog is NOT deterministic"

# A tiny multi-language corpus (own-repo dir would work too, but this keeps --lint's own run fast and
# guarantees every one of the 39 built-in rows appears in the tally regardless of corpus content — the
# tally is emitted for EVERY declared rule name whether or not the rule ever matches).
"$BIN" "$ROOT/test/lintfix" --lint --no-cache >"$TMP/lintrun" 2>/dev/null

python3 - "$TMP/catalog1" "$TMP/lintrun" <<'PY'
import sys
import xml.etree.ElementTree as ET

catalogPath, lintPath = sys.argv[1], sys.argv[2]
fail = 0
def ok(m): print("  PASS  " + m)
def no(m):
    global fail; fail = 1; print("  FAIL  " + m)

catalogRoot = ET.parse(catalogPath).getroot()
catalogRows = catalogRoot.findall("rule")
catalogNames = set(r.get("name") for r in catalogRows)

if catalogRoot.get("rules") == str(len(catalogRows)):
    ok(f"root rules=\"{catalogRoot.get('rules')}\" matches the row count ({len(catalogRows)})")
else:
    no(f"root rules=\"{catalogRoot.get('rules')}\" does not match the row count ({len(catalogRows)})")

# every row has non-empty severity/category/rationale/languages/since
missing = []
for r in catalogRows:
    for attr in ("sev", "cat", "lang", "since"):
        if not (r.get(attr) or "").strip():
            missing.append((r.get("name"), attr))
    if not (r.text or "").strip():
        missing.append((r.get("name"), "rationale"))
if missing:
    no(f"catalog rows missing a required field: {missing[:10]}")
else:
    ok(f"every catalog row ({len(catalogRows)}) has non-empty sev/cat/rationale/lang/since")

# severity is one of the closed set --lint-rules validates (info|warn|error)
badSev = [r.get("name") for r in catalogRows if r.get("sev") not in ("info", "warn", "error")]
if badSev:
    no(f"catalog rows with an invalid sev= (want info|warn|error): {badSev}")
else:
    ok("every catalog row's sev= is info|warn|error")

lintRoot = ET.parse(lintPath).getroot()
builtinNames = set(r.get("name") for r in lintRoot.findall("rule") if r.get("sev") is None)

onlyInLint = builtinNames - catalogNames
onlyInCatalog = catalogNames - builtinNames
if onlyInLint:
    no(f"--lint emits rule name(s) with NO --lint-catalog row: {sorted(onlyInLint)}")
else:
    ok("every --lint built-in rule name has a --lint-catalog row")
if onlyInCatalog:
    no(f"--lint-catalog has row(s) --lint's own tally never emits: {sorted(onlyInCatalog)}")
else:
    ok("every --lint-catalog row is a real --lint built-in rule name")

sys.exit(fail)
PY
py_rc=$?
[ "$py_rc" -ne 0 ] && fail=1

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

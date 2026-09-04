#!/usr/bin/env bash
# lintprecisioncheck.sh — A5 numeric semantics and pagination-honesty gate.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIXTURE="$TMP/fixture"
mkdir -p "$FIXTURE"

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

cat >"$FIXTURE/numeric.cpp" <<'CPP'
int numericContexts( int n )
{
    double zero = 0.0;
    float one = 1.0f;
    double two = 2.0;
    int minusOne = -1;
    unsigned mask = unsigned( n ) & 0x80;
    int realFinding = n * 42;
    return int( zero + one + two ) + minusOne + int( mask ) + realFinding;
}
CPP

"$BIN" "$FIXTURE" --lint --no-cache >"$TMP/numeric.a" 2>/dev/null
"$BIN" "$FIXTURE" --lint --no-cache >"$TMP/numeric.b" 2>/dev/null
diff -q "$TMP/numeric.a" "$TMP/numeric.b" >/dev/null || { echo "FAIL numeric lint is not deterministic"; exit 1; }

"$BIN" "$ROOT/src" --lint --limit=3 --offset=0 --no-cache >"$TMP/page1" 2>/dev/null
"$BIN" "$ROOT/src" --lint --limit=3 --offset=3 --no-cache >"$TMP/page2" 2>/dev/null
# "full" must be a limit no real corpus can reach: src/ crossed 1000 findings once §P0.2 gave each rule its
# own budget (664 → 1175), and a "full" page that silently truncates makes the seam assertions vacuous.
"$BIN" "$ROOT/src" --lint --limit=1000000 --offset=0 --no-cache >"$TMP/full" 2>/dev/null
"$BIN" "$ROOT/src" --lint --no-cache >"$TMP/default" 2>/dev/null

python3 - "$TMP/numeric.a" "$TMP/page1" "$TMP/page2" "$TMP/full" "$TMP/default" <<'PY'
import sys
import xml.etree.ElementTree as ET

numeric_path, page1_path, page2_path, full_path, default_path = sys.argv[1:]

numeric = ET.parse(numeric_path).getroot()
magic = [node for node in numeric.findall("f") if node.get("rule") == "magic-number"]
if len(magic) != 1 or magic[0].text != "42":
    found = [(node.text, node.get("p")) for node in magic]
    raise SystemExit(f"FAIL expected exactly one semantic magic number 42, found {found}")

roots = [ET.parse(path).getroot() for path in (page1_path, page2_path, full_path, default_path)]
page1, page2, full, default = roots
required = ("shown", "total", "has_more", "next_offset", "offset", "limit")
for page in (page1, page2, full):
    missing = [name for name in required if page.get(name) is None]
    if missing:
        raise SystemExit(f"FAIL paginated lint missing honesty attrs {missing}")
    if int(page.get("shown")) != len(page.findall("f")):
        raise SystemExit("FAIL lint shown does not equal emitted finding count")

if int(page1.get("shown")) != 3 or page1.get("has_more") != "1" or page1.get("next_offset") != "3":
    raise SystemExit("FAIL first lint page has dishonest shown/has_more/next_offset")
if page1.get("total") != page2.get("total") or page1.get("total") != full.get("total"):
    raise SystemExit("FAIL lint total changed across pages")

def rows(root):
    return [ET.tostring(node, encoding="unicode") for node in root.findall("f")]

if rows(page1) + rows(page2) != rows(full)[:6]:
    raise SystemExit("FAIL lint page seam dropped, duplicated, or reordered findings")

# W3-S item 1 (2026-08-19): the DEFAULT (unpaged) run now carries a byte-budget default cap
# (kLintDefaultPayloadBytes, src/main.cpp runLint) — the fix for E6's uncapped ~2MB --lint payload. This
# changes the two assertions the pre-fix gate made here, deliberately:
#   - it used to require NO pagination-vocabulary attr on the default run at all; W3-S made it REQUIRE
#     shown=/capped= (pageview.h THE TRUNCATION VOCABULARY rule 3: shown= always rides with capped=) while
#     the explicit-paging half stayed ABSENT, on the reasoning that a default-capped run "never claims to BE
#     a page". Re-pinned 2026-09-04 (capture-audit lane L4 finding 3, PLAN_CAPTURE_AUDIT §1 "M2 paging
#     quintet only under an explicit --limit"): that posture left the very run a loop STARTS with — the bare
#     default — with no next_offset= to continue from. pageview.h computePageDisclosure now reads
#     capped="1" ⇒ total= has_more= next_offset= offset= limit=, HOWEVER the window was set; limit="0" is the
#     documented no-explicit-limit sentinel. The new contract is asserted precisely below, not loosened:
#     the quintet is PRESENT, limit="0" offset="0" spell the default window, total= is the same true total
#     findings= and the full run report, has_more="1" (shown < findings here), next_offset= equals shown=.
#   - it used to require default == full byte-for-byte; it now requires default to be the sorted PREFIX of
#     full, truthfully short of it (shown < findings) on a corpus this large, and requires findings= to
#     still agree across default/full (both see the SAME true total, they just show different amounts).
paging = ("total", "has_more", "next_offset", "offset", "limit")
if default.get("shown") is None or default.get("capped") is None:
    raise SystemExit("FAIL default lint is missing shown=/capped= (the W3-S default-cap disclosure)")
missing = [name for name in paging if default.get(name) is None]
if missing:
    raise SystemExit(f"FAIL default lint is capped=\"1\" but lacks the M2 paging quintet {missing} (pageview.h: capped ⇒ quintet on every window)")
if default.get("limit") != "0" or default.get("offset") != "0":
    raise SystemExit(f"FAIL default lint must spell the default window limit=\"0\" offset=\"0\", got limit={default.get('limit')} offset={default.get('offset')}")
if default.get("total") != default.get("findings") or default.get("total") != full.get("total"):
    raise SystemExit("FAIL default lint total= must equal its own findings= and the full run's total= (one true total, three spellings)")
if default.get("has_more") != "1" or default.get("next_offset") != default.get("shown"):
    raise SystemExit("FAIL default lint cut its rows but has_more=/next_offset= do not say so (expected has_more=\"1\", next_offset=shown)")
if len(rows(default)) != int(default.get("shown", "-1")):
    raise SystemExit("FAIL default lint shown= does not equal its emitted finding count")
if default.get("findings") != full.get("findings"):
    raise SystemExit("FAIL default lint and --limit=1000000 disagree on the true findings= total")
if rows(default) != rows(full)[: len(rows(default))]:
    raise SystemExit("FAIL default lint rows are not the sorted PREFIX of the full result")
if int(default.get("shown")) >= int(default.get("findings")):
    raise SystemExit("FAIL default lint on src/ did not actually engage its default cap (shown >= findings) — "
                      "re-anchor this arm, it no longer exercises the capped case it exists to check")
if default.get("capped") != "1":
    raise SystemExit("FAIL default lint capped its rows but did not say capped=\"1\"")

print(f"PASS magic=1 shown={page1.get('shown')} total={page1.get('total')}")
PY

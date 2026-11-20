#!/usr/bin/env bash
# impactfirstwindowcheck.sh — IM1: --impact's FIRST window carries the rows a blast-radius question needs.
#
# THE DEFECT (dev diagnosis, results/IM1_IMPACT_1119/READOUT.md). Two orders decided what the 40-row first window held,
# and both let a row that answers nothing push out one that does:
#   * SYMBOL rows: depth first, then PageRank within a depth. A test helper that many tests call out-ranks a production
#     caller at the same depth, so a depth's test="1" rows filled the window ahead of its production rows (django
#     --impact=salted_hmac: two depth-3 production files sat past row 40, behind depth-3 tests).
#   * IMPORT tier (<f> rows): tier, then importer fan-in, then path. An importer the answer ALSO has evidence for — a
#     file holding a reached symbol, a declined call the answer counts, or one of SYM's value bindings — ranked like any
#     file that only #includes the header (envoy --impact=chargeResponseStat: router.cc and ratelimit.cc, each holding a
#     counted <dc> site, sat past importer 40 of 141).
# THE FIX ORDERS, IT DROPS NOTHING. Symbol rows: depth, then non-test before test (filter.h isTestSymbol, the predicate
# behind test="1"), then PageRank. Import rows: tier, then evidence before none, then fan-in, then path. Every count,
# window attribute and continuation is unchanged; the pages stay slices of ONE total order.
#
# FIXTURE (written below, Python): core.target() is called by prod_direct (prod.py) and by tests/test_core.py's helper(),
# which five tests call, so helper out-ranks prod_direct at depth 1. 45 files a00..a44 only `import core`; zz_bind.py
# binds target as a value (a <vr> row); prod.py and tests/test_core.py import it and hold reached symbols. 50 more files
# import only `os`, so core.py is not an umbrella header. On the pre-fix binary arms (1) and (4) are RED.
#
# ARMS (each counts its premise and FAILS on zero)
#   (1) TESTS LAST WITHIN A DEPTH: --limit=1 prints prod_direct (not helper); in the full listing no test="1" row
#       precedes a non-test row of the same depth; depths never decrease.
#   (2) A PERMUTATION: the rows per depth equal the hand-derived sets; by_depth="1:2,2:6" sums to reaches=8.
#   (3) PAGING: --limit=3 at offsets 0, 3, 6 concatenate to the --limit=100 listing; has_more=/next_offset= on a cut page.
#   (4) EVIDENCE FIRST IN THE IMPORT TIER: zz_bind.py (a <vr> binding) and prod.py (reached rows) are among the 40 shown
#       importers, and every evidence importer of the source tier precedes every evidence-free one.
#   (5) THE TIER STAYS HONEST: importers="48" shown_importers="40" importers_capped="1" importers_next= unchanged, and
#       --limit=48 lists each of the 48 importers exactly once (test tier last).
#   (6) DIALECTS AND TWIN: --json rows and import_reach, the columnar <name> column, and the MCP impact twin all carry
#       the same order as the XML.
#   (7) determinism: two runs are byte-identical.
#
# Usage: bash test/impactfirstwindowcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/impactfirstwindowcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIXD="$TMP/fix"; mkdir -p "$FIXD/tests"
cat >"$FIXD/core.py" <<'EOF'
def target():
    return 1
EOF
cat >"$FIXD/prod.py" <<'EOF'
from core import target
def prod_direct():
    return target()
def prod_two():
    return prod_direct()
EOF
cat >"$FIXD/tests/test_core.py" <<'EOF'
from core import target
def helper():
    return target()
def test_a():
    helper()
def test_b():
    helper()
def test_c():
    helper()
def test_d():
    helper()
def test_e():
    helper()
EOF
cat >"$FIXD/zz_bind.py" <<'EOF'
from core import target
def install(registry):
    registry.append(target)
EOF
for i in $( seq -w 0 44 ); do printf 'import core\ndef f%s():\n    return 0\n' "$i" >"$FIXD/a$i.py"; done
for i in $( seq -w 0 49 ); do printf 'import os\ndef g%s():\n    return os.sep\n' "$i" >"$FIXD/o$i.py"; done

echo "impactfirstwindowcheck: $BIN"
BIN="$BIN" FIXD="$FIXD" python3 - <<'PY'
import json, os, re, subprocess, sys

BIN, FIXD = os.environ["BIN"], os.environ["FIXD"]
fail = [0]
def ok(m): print("  PASS  " + m)
def no(m): print("  FAIL  " + m); fail[0] = 1

def run(*args):
    return subprocess.run([BIN, ".", "--no-cache"] + list(args), cwd=FIXD, capture_output=True, text=True, timeout=300).stdout

def root_attrs(doc):
    m = re.search(r"<impact ([^>]*)>", doc)
    return dict(re.findall(r'(\w[\w-]*)="([^"]*)"', m.group(1))) if m else {}

def rows(doc):
    """[(name, depth, is_test)] of the <s> rows in document order, d= run-length expanded"""
    body = doc[doc.index("<impact "):] if "<impact " in doc else ""
    out, cur = [], None
    for r in re.findall(r"<s [^>]*/>", body):
        d = re.search(r' d="(\d+)"', r)
        cur = int(d.group(1)) if d else cur
        out.append((re.search(r' n="([^"]*)"', r).group(1), cur, ' test="1"' in r))
    return out

def importers(doc):
    return re.findall(r'<f p="([^"]*)"', doc)

TRUE = {1: {"prod_direct", "helper"}, 2: {"prod_two", "test_a", "test_b", "test_c", "test_d", "test_e"}}
TESTS = {"helper", "test_a", "test_b", "test_c", "test_d", "test_e"}
EVIDENCE = {"zz_bind.py", "prod.py", "tests/test_core.py"}

full = run("--impact=target", "--limit=100", "--legend=full")
rs = rows(full)

# (1)
head = rows(run("--impact=target", "--limit=1"))
inverted = [(a[0], b[0]) for a, b in zip(rs, rs[1:]) if a[1] == b[1] and a[2] and not b[2]]
mono = all(rs[i][1] <= rs[i + 1][1] for i in range(len(rs) - 1))
labelled = {n for n, _d, t in rs if t} == TESTS
if [n for n, _d, _t in head] == ["prod_direct"] and rs and not inverted and mono and labelled:
    ok("(1) --limit=1 prints prod_direct; no test row precedes a non-test row of its depth (%d rows); depths never decrease" % len(rs))
else:
    no("(1) head=%s inverted=%s non-decreasing=%s test labels=%s" % (head, inverted, mono, sorted(n for n, _d, t in rs if t)))

# (2)
ra = root_attrs(full)
per = {d: {n for n, dd, _t in rs if dd == d} for d in TRUE}
if per == TRUE and ra.get("by_depth") == "1:2,2:6" and ra.get("reaches") == "8" and len(rs) == 8:
    ok('(2) the rows per depth are the hand-derived sets; by_depth="1:2,2:6" partitions reaches="8"')
else:
    no("(2) per-depth %s by_depth=%r reaches=%r rows=%d" % (per, ra.get("by_depth"), ra.get("reaches"), len(rs)))

# (3)
pages = [run("--impact=target", "--limit=3", "--offset=%d" % o) for o in (0, 3, 6)]
cat = [r[0] for p in pages for r in rows(p)]
p0 = root_attrs(pages[0])
if cat and cat == [r[0] for r in rs] and p0.get("has_more") == "1" and p0.get("next_offset") == "3":
    ok("(3) --limit=3 pages at offsets 0/3/6 are slices of the --limit=100 order; page 1 says has_more=1 next_offset=3")
else:
    no("(3) pages %s vs full %s; page 1 has_more=%r next_offset=%r" % (cat, [r[0] for r in rs], p0.get("has_more"), p0.get("next_offset")))

# (4)
dflt = run("--impact=target")
shown = importers(dflt)
src_tier = [f for f in importers(run("--impact=target", "--limit=48")) if not f.startswith("tests/")]
ev_pos = [i for i, f in enumerate(src_tier) if f in EVIDENCE]
noev_pos = [i for i, f in enumerate(src_tier) if f not in EVIDENCE]
if ev_pos and "zz_bind.py" in shown and "prod.py" in shown and max(ev_pos) < min(noev_pos):
    ok("(4) the source-tier evidence importers %s lead the tier and are among the %d shown" % ([src_tier[i] for i in ev_pos], len(shown)))
else:
    no("(4) shown=%d zz_bind.py shown=%s prod.py shown=%s; evidence positions %s, first evidence-free %s" % (
        len(shown), "zz_bind.py" in shown, "prod.py" in shown, ev_pos, min(noev_pos) if noev_pos else None))

# (5)
da = root_attrs(dflt)
alltier = importers(run("--impact=target", "--limit=48"))
if (da.get("importers"), da.get("shown_importers"), da.get("importers_capped"), da.get("importers_next")) == ("48", "40", "1", "--impact=target --limit=48") \
        and len(alltier) == 48 == len(set(alltier)) and alltier[-1] == "tests/test_core.py" and len(shown) == 40:
    ok('(5) importers="48" shown_importers="40" importers_capped="1" importers_next= intact; --limit=48 lists each importer once, test tier last')
else:
    no("(5) root %s; --limit=48 rows=%d distinct=%d last=%r" % ({k: da.get(k) for k in ("importers", "shown_importers", "importers_capped", "importers_next")},
                                                            len(alltier), len(set(alltier)), alltier[-1] if alltier else None))

# (6)
try:
    j = json.loads(run("--impact=target", "--limit=100", "--json"))
    jrows = [r["n"] for r in j["impact"]]
    jimp = [r["p"] for r in json.loads(run("--impact=target", "--json"))["import_reach"]]
    col = run("--impact=target", "--limit=100", "--format=columnar")
    cn = re.search(r"<name>([^<]*)</name>", col)
    req = "\n".join([json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize"}),
                     json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "impact",
                                "arguments": {"path": FIXD, "symbol": "target", "limit": 100}}})]) + "\n"
    p = subprocess.run([BIN, "--mcp"], input=req, capture_output=True, text=True, timeout=300)
    mt = json.loads(p.stdout.strip().splitlines()[-1])["result"]["content"][0]["text"]
    names = [r[0] for r in rs]
    if jrows == names and jimp == shown and cn and cn.group(1).split(",") == names and [r[0] for r in rows(mt)] == names:
        ok("(6) --json rows and import_reach, the columnar <name> column and the MCP twin carry the XML order")
    else:
        no("(6) json %s / import %s / columnar %s / mcp %s vs %s" % (jrows, jimp[:3], cn and cn.group(1), [r[0] for r in rows(mt)], names))
except Exception as e:
    no("(6) a dialect or the MCP twin answered nothing parseable: %s" % e)

# (7)
if run("--impact=target", "--limit=100") == run("--impact=target", "--limit=100") and run("--impact=target") == dflt:
    ok("(7) two runs are byte-identical")
else:
    no("(7) two runs differ")

print("impactfirstwindowcheck: " + ("FAILURES" if fail[0] else "ALL PASS"))
sys.exit(fail[0])
PY

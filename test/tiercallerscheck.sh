#!/usr/bin/env bash
# tiercallerscheck.sh — TIER-FOLLOWUP: the test-tier defect class IMPACT-TEST-TIER fixed on --impact, finished on the verbs
# beside it. Found in the 0.7.0 comparison rehearsal on the M5.
#
# THE DEFECT, three more places. graph.h isTestedByReach never counts a test symbol (a test is a SEED of the tested lens,
# never a covered row), so any "untested" count derived as `rows - tested` puts every TEST row into untested production:
#   --callers / --callees  hop_untested= was count= - hop_tested=: a symbol called by ten tests and one production caller
#                          read hop_untested="10"-plus, and no row said which callers were tests.
#   --safe-delete          risk="untested-radius" ("NONE of the transitive blast radius is test-covered") fired when every
#                          member of the radius WAS a test: a test-only helper read as untested production risk.
#   columnar --impact      radius_tests= rode the root, but no column said which rows were the tests (<tested> reads 0 on a
#                          test row and on an untested production row alike).
#
# THE FIX TIERS AND LABELS, as IMPACT-TEST-TIER did (graph.h radiusTiers, the same isTestSymbol predicate): hop_tests=K on the
# callers/callees root (absent at 0, the three sum to count=), test="1" on the XML row and "test":true on the JSON/MCP row;
# risk="tests-only" when the radius holds only tests; a present-only <test> column in the columnar forms.
#
# FIXTURE (Python, written below): target() is called by prod_tested (a test reaches it), prod_untested (none does) and two
# TEST definitions (test_target, and the non-test_-named helper make_case in the test file). only_for_tests() is called by a
# test alone. test_uses_case() calls make_case(), so its callees hold a test definition. lonely() and prod_untested() have
# production callers only (the negative arms).
#
# ARMS (each counts its premise and FAILS on zero)
#   (1) CALLERS COUNTS: --callers=target carries hop_tests= equal to the test-file rows it lists; hop_tested=1 hop_untested=1
#       count the production rows only; the three sum to count=.
#   (2) CALLERS ROWS: every test-file row carries test="1", no production row does, no row carries both test= and tested=;
#       --json says "hop_tests" and "test":true on the same rows; the MCP twin find_referencing_symbols likewise.
#   (3) CALLEES: --callees=test_uses_case counts make_case in hop_tests=, not in hop_untested=.
#   (4) LEGEND: the full and compact callers legends define hop_tests= and test=1 where they ride.
#   (5) SAFE-DELETE: --safe-delete=only_for_tests (every radius member a test) is not risk=untested-radius; it is
#       risk=tests-only, and the legend states that reading. prod_untested (a production-only radius) keeps untested-radius.
#   (6) COLUMNAR: --impact=target and --callers=target --format=columnar name test in fields= and carry a <test> column that
#       is 1 exactly on the test-file rows; the legend reads the column (full and compact).
#   (7) NEGATIVE: no test in reach (--callers=lonely in three dialects, columnar --impact=lonely, --safe-delete=prod_untested):
#       no hop_tests=, no test= row or key, no <test> column, no test-tier clause. With REF_BIN set (the parent lane's binary,
#       lane/impact-test-tier) each of those answers is byte-identical to it: stdout, stderr and rc.
#
# Usage: bash test/tiercallerscheck.sh [BIN]   |   REF_BIN=parent/ripwire bash test/tiercallerscheck.sh build/ripwire

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
REF_BIN="${REF_BIN:-}"
[ -n "$REF_BIN" ] && [ "${REF_BIN#/}" = "$REF_BIN" ] && REF_BIN="$PWD/$REF_BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIXD="$TMP/fix"; mkdir -p "$FIXD/geom" "$FIXD/tests"
cat >"$FIXD/geom/shapes.py" <<'EOF'
def target(x):
    return x + 1


def prod_tested(x):
    return target(x)


def prod_untested(x):
    return target(x) * 2


def prod_untested2(x):
    return prod_untested(x) - 1


def only_for_tests(x):
    return x * 3


def lonely(x):
    return x


def lonely_caller(x):
    return lonely(x)
EOF
cat >"$FIXD/tests/test_shapes.py" <<'EOF'
from geom.shapes import target, prod_tested, only_for_tests


def test_target():
    assert target(1) == 2


def test_prod_tested():
    assert prod_tested(1) == 2


def make_case():
    return target(3)


def test_only():
    assert only_for_tests(1) == 3


def test_uses_case():
    assert make_case() == 4
EOF

echo "tiercallerscheck: $BIN${REF_BIN:+ (ref $REF_BIN)}"
BIN="$BIN" REF_BIN="$REF_BIN" FIXD="$FIXD" python3 - <<'PY'
import json, os, re, subprocess, sys
BIN, REF, FIXD = os.environ["BIN"], os.environ["REF_BIN"], os.environ["FIXD"]
fail = [0]
def ok(m): print("  PASS  " + m)
def no(m): print("  FAIL  " + m); fail[0] = 1

def runp(binary, *args):
    p = subprocess.run([binary, ".", "--no-cache"] + list(args), cwd=FIXD, capture_output=True, text=True, timeout=300)
    return p

def run(*args):
    return runp(BIN, *args).stdout

def root_attrs(doc, tag):
    m = re.search(r"<%s ([^>]*)>" % re.escape(tag), doc)
    return dict(re.findall(r'(\w[\w-]*)="([^"]*)"', m.group(1))) if m else {}

def srows(doc, tag):
    """[(name, path, test_label, tested_label)] for the <s> rows inside <tag>"""
    at = doc.find("<%s " % tag)
    body = doc[at:] if at >= 0 else ""
    out = []
    for r in re.findall(r"<s [^>]*/>", body):
        out.append((re.search(r' n="([^"]*)"', r).group(1), re.search(r' p="([^"]*)"', r).group(1).split(":")[0],
                    ' test="1"' in r, ' tested="1"' in r))
    return out

def legend(doc, tag):
    at = doc.find("<%s " % tag)
    return "".join(re.findall(r"<!--.*?-->", doc[:at] if at >= 0 else doc, re.S))

def is_test_path(p):
    return p.startswith("tests/") or "/tests/" in p

def columnar(doc, tag):
    """(fields list, {column: [values]}, [path per row]) of the columnar <cols>"""
    m = re.search(r'<cols n="(\d+)" fields="([^"]*)">(.*?)</cols>', doc, re.S)
    if not m:
        return [], {}, []
    fields = m.group(2).split(",")
    cols = {f: v.split(",") if v else [] for f, v in re.findall(r"<(\w+)>([^<]*)</\1>", m.group(3))}
    pm = re.search(r"<paths>([^<]*)</paths>", doc)   # <paths>0=a.py 1=tests/b.py</paths>: I=path, space-separated
    paths = dict(item.split("=", 1) for item in pm.group(1).split(" ") if "=" in item) if pm else {}
    rowpaths = [paths.get(i, "") for i in cols.get("path", [])]
    return fields, cols, rowpaths

def mcp_call(tool, args):
    req = "\n".join([json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize"}),
                     json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": tool, "arguments": dict(args, path=FIXD)}})]) + "\n"
    p = subprocess.run([BIN, "--mcp"], input=req, capture_output=True, text=True, timeout=300)
    return json.loads(p.stdout.strip().splitlines()[-1])["result"]["content"][0]["text"]

# ── (1) callers counts ───────────────────────────────────────────────────────────────────────────────────────────
full = run("--callers=target", "--legend=full")
ca = root_attrs(full, "callers")
crows = srows(full, "callers")
ctest = [r for r in crows if is_test_path(r[1])]
cprod = [r for r in crows if not is_test_path(r[1])]
count = int(ca.get("count", "-1"))
ht, hu, hx = (int(ca.get(k, "0")) for k in ("hop_tested", "hop_untested", "hop_tests"))
if len(ctest) == 0 or len(cprod) == 0:
    no("(1) premise: --callers=target lists %d test-file and %d production rows (want both >= 1): %r" % (len(ctest), len(cprod), crows))
elif ca.get("hop_tests") == str(len(ctest)) and (ht, hu) == (1, 1) and ht + hu == len(cprod) and ht + hu + hx == count:
    ok('(1) --callers=target: hop_tests="%d" == the test-file rows %s; hop_tested=1 hop_untested=1 are production only; sum == count=%d'
       % (hx, sorted(r[0] for r in ctest), count))
else:
    no("(1) --callers=target root %r: hop_tests=%r for %d test rows, hop_tested=%d hop_untested=%d (want 1/1), count=%d"
       % (ca, ca.get("hop_tests"), len(ctest), ht, hu, count))

# ── (2) callers rows: XML labels, JSON, MCP ──────────────────────────────────────────────────────────────────────
if len(ctest) == 0:
    no("(2a) premise: no test-file caller row to label")
elif all(r[2] for r in ctest) and not any(r[2] for r in cprod) and not any(r[2] and r[3] for r in crows):
    ok('(2a) every one of the %d test-file caller rows carries test="1"; none of the %d production rows does; never beside tested="1"'
       % (len(ctest), len(cprod)))
else:
    no("(2a) caller row labels wrong: %r" % crows)
js = run("--callers=target", "--json")
try:
    jd = json.loads(js)
    jrows = jd.get("callers", [])
    jtest = sorted(r.get("n", "") for r in jrows if r.get("test") is True)
    if len(ctest) > 0 and jd.get("hop_tests") == len(ctest) and jd.get("hop_untested") == 1 and jtest == sorted(r[0] for r in ctest):
        ok('(2b) --json: "hop_tests":%d, "hop_untested":1, and the test rows %s carry "test":true' % (jd.get("hop_tests"), jtest))
    else:
        no("(2b) --json hop_tests=%r hop_untested=%r test rows=%r (want %d / 1 / %r)"
           % (jd.get("hop_tests"), jd.get("hop_untested"), jtest, len(ctest), sorted(r[0] for r in ctest)))
except Exception as e:
    no("(2b) --json did not parse: %s / %s" % (e, js[:300]))
try:
    md = json.loads(mcp_call("find_referencing_symbols", {"symbol": "target"}))
    mtest = sorted(r.get("name", "") for r in md.get("calledBy", []) if r.get("test") is True)
    if len(ctest) > 0 and md.get("hop_tests") == len(ctest) and md.get("hop_untested") == 1 and mtest == sorted(r[0] for r in ctest):
        ok('(2c) MCP find_referencing_symbols: "hop_tests":%d, "hop_untested":1, the same rows carry "test":true' % md.get("hop_tests"))
    else:
        no("(2c) MCP find_referencing_symbols hop_tests=%r hop_untested=%r test rows=%r" % (md.get("hop_tests"), md.get("hop_untested"), mtest))
except Exception as e:
    no("(2c) MCP find_referencing_symbols answered nothing parseable: %s" % e)

# ── (3) callees ──────────────────────────────────────────────────────────────────────────────────────────────────
ce = run("--callees=test_uses_case", "--legend=full")
cea = root_attrs(ce, "callees")
cerows = srows(ce, "callees")
cetest = [r for r in cerows if is_test_path(r[1])]
if len(cetest) == 0:
    no("(3) premise: --callees=test_uses_case lists no test-file callee (%r)" % cerows)
elif cea.get("hop_tests") == str(len(cetest)) and cea.get("hop_untested") == str(len(cerows) - len(cetest) - int(cea.get("hop_tested", "0"))) \
        and all(r[2] for r in cetest):
    ok('(3) --callees=test_uses_case: hop_tests="%s" (%s, labelled test="1"), hop_untested="%s"' % (cea.get("hop_tests"), cetest[0][0], cea.get("hop_untested")))
else:
    no("(3) --callees=test_uses_case root %r rows %r" % (cea, cerows))

# ── (4) legend ───────────────────────────────────────────────────────────────────────────────────────────────────
comp = run("--callers=target")
lf, lc = legend(full, "callers"), legend(comp, "callers")
if len(ctest) == 0:
    no("(4) premise: no test caller rides, nothing for the legend to define")
elif "hop_tests=" in lf and 'test="1"' in lf and "hop_tests" in lc and "test=1" in lc:
    ok("(4) full and compact callers legends define hop_tests= and the row's test=1 where they ride")
else:
    no("(4) full defines hop_tests=%s test=%s; compact hop_tests=%s test=%s" % ("hop_tests=" in lf, 'test="1"' in lf, "hop_tests" in lc, "test=1" in lc))

# ── (5) safe-delete risk ─────────────────────────────────────────────────────────────────────────────────────────
sd = run("--safe-delete=only_for_tests", "--legend=full")
sa = root_attrs(sd, "safe-delete")
reach = int(sa.get("impact_reaches", "0"))
if reach == 0 or sa.get("radius_tests") != str(reach):
    no("(5) premise: --safe-delete=only_for_tests should have a radius made only of tests (impact_reaches=%d radius_tests=%r)" % (reach, sa.get("radius_tests")))
elif sa.get("risk") == "tests-only" and "tests-only:" in legend(sd, "safe-delete") and sa.get("radius_untested") == "0":
    ok('(5a) --safe-delete=only_for_tests: radius_tests="%d" == impact_reaches=, risk="tests-only" (not untested-radius), its sentence in the legend' % reach)
else:
    no("(5a) --safe-delete=only_for_tests risk=%r radius_untested=%r; legend reads tests-only: %s" % (sa.get("risk"), sa.get("radius_untested"), "tests-only:" in legend(sd, "safe-delete")))
sdc = run("--safe-delete=only_for_tests")
if reach > 0 and root_attrs(sdc, "safe-delete").get("risk") == "tests-only" and "tests-only" in legend(sdc, "safe-delete"):
    ok("(5b) compact --safe-delete=only_for_tests: risk=tests-only and its reading rides")
else:
    no("(5b) compact --safe-delete=only_for_tests root %r; legend reads tests-only: %s" % (root_attrs(sdc, "safe-delete"), "tests-only" in legend(sdc, "safe-delete")))
pu = root_attrs(run("--safe-delete=prod_untested"), "safe-delete")
if int(pu.get("impact_reaches", "0")) == 0:
    no("(5c) premise: --safe-delete=prod_untested has no radius (%r)" % pu)
elif pu.get("risk") == "untested-radius" and "radius_tests" not in pu:
    ok('(5c) --safe-delete=prod_untested (production-only radius) keeps risk="untested-radius"')
else:
    no("(5c) --safe-delete=prod_untested root %r" % pu)

# ── (6) columnar test column ─────────────────────────────────────────────────────────────────────────────────────
for verb, tag in (("--impact=target", "impact"), ("--callers=target", "callers")):
    for posture in ("full", "compact"):
        doc = run(verb, "--format=columnar", "--limit=100", "--legend=" + posture)
        fields, cols, rowpaths = columnar(doc, tag)
        want = ["1" if is_test_path(p) else "0" for p in rowpaths]
        lg = legend(doc, tag)
        reads = ("test column" in lg) if posture == "full" else ("<test> column" in lg)
        if want.count("1") == 0:
            no("(6) premise: %s --format=columnar lists no test-file row (paths %r)" % (verb, rowpaths))
        elif "test" in fields and cols.get("test") == want and reads:
            ok("(6) %s --format=columnar --legend=%s: fields= names test, <test> is 1 on exactly the %d test-file rows, the legend reads it"
               % (verb, posture, want.count("1")))
        else:
            no("(6) %s --format=columnar --legend=%s: fields=%r test=%r want %r; legend reads it: %s" % (verb, posture, fields, cols.get("test"), want, reads))

# ── (7) negative: no test in reach ───────────────────────────────────────────────────────────────────────────────
NEG = [("--callers=lonely", "--legend=full"), ("--callers=lonely",), ("--callers=lonely", "--json"),
       ("--callers=lonely", "--format=columnar"), ("--impact=lonely", "--format=columnar"), ("--impact=lonely", "--format=columnar", "--legend=full"),
       ("--safe-delete=prod_untested", "--legend=full"), ("--safe-delete=prod_untested",)]
seen = 0
for args in NEG:
    p = runp(BIN, *args)
    out = p.stdout
    if len(out) < 40:
        no("(7) premise: %s printed nothing to compare (%r)" % (" ".join(args), out[:200]))
        continue
    seen += 1
    leaks = [k for k in ("hop_tests", "radius_tests", ' test="1"', '"test":true', "tests-only", "<test>", ",test\"", "test column") if k in out]
    if leaks:
        no("(7) %s carries test-tier vocabulary with no test in reach: %r" % (" ".join(args), leaks))
        continue
    if REF:
        q = runp(REF, *args)
        if (q.stdout, q.stderr, q.returncode) != (p.stdout, p.stderr, p.returncode):
            no("(7) %s differs from the parent lane's binary (stdout %s, stderr %s, rc %d vs %d)"
               % (" ".join(args), q.stdout == p.stdout, q.stderr == p.stderr, p.returncode, q.returncode))
            continue
    ok("(7) %s: no test-tier vocabulary%s" % (" ".join(args), "; stdout+stderr+rc byte-identical to the parent lane" if REF else ""))
if seen == 0:
    no("(7) premise: no negative answer was compared")

print("ALL PASS" if not fail[0] else "FAILED")
sys.exit(fail[0])
PY

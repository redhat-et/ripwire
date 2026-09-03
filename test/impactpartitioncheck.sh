#!/usr/bin/env bash
# impactpartitioncheck.sh — A6 (survey card A6, agent-lsp): --impact/--callers' new tested= row partition
# must agree, symbol for symbol, with --test-gate's own untested= determination — the correctness band
# registered in docs/EVALS.md before this gate was written. Two verbs disagreeing about what a test
# reaches is a BUG on whichever is wrong; this gate is the arithmetic that would catch it, not a human
# eyeballing two outputs.
#
# WHY THIS SAMPLE IS A FAIR COMPARISON. transitiveCallers(g, SEEDS) is the identical traversal --impact
# runs from ONE seed and --test-gate runs from its WHOLE changed-symbol set (situ.h::computeTestGateFor
# calls the same rw::transitiveCallers --impact calls). BFS reachability is seed-set-monotone-additive:
# reach(union of seeds) == union of reach(each seed) — so unioning N separate `--impact=SEED` calls over a
# symbol set S is architecturally IDENTICAL to --test-gate's blast radius when its "changed" set is
# EXACTLY S. --test-gate's CLI only accepts FILES (not a bare symbol list), so S is chosen as EVERY
# symbol src/graph.h defines — a real, non-synthetic, deterministic (`file(all,"src/graph\.h")` is a
# fixed query against a file whose defined-symbol COUNT does not depend on run order) sample of this
# repo's own src/, comfortably over the registered 50-symbol floor (139 measured at kParserVer of this
# lane), and `--test-gate=src/graph.h` then marks EXACTLY that same symbol set as changed — one file, no
# broader superset of "changed" to reconcile.
#
# THE JOIN KEY. --impact rows spell p="path:line"; --test-gate's <u> rows spell p="./path" (no line,
# leading "./"). Both are normalized to a bare root-relative path (leading "./" stripped, ":line" cut)
# before comparison — the identity a reader would recognize as "the same symbol", not a byte-exact
# string a formatting difference between two unrelated emitters would spuriously break.
#
# THE THREE ASSERTIONS:
#   (1) SET EQUALITY — the union of every --impact=src/graph.h:SYM call's UNTESTED rows (no tested=
#       attribute, excluding rows in src/graph.h itself — the changed file, excluded from impacted the
#       same way --test-gate excludes it — and rows in any file --test-gate's own <t> listing names, since
#       those are its test-file exclusion, never its <u> listing) equals --test-gate=src/graph.h's <u>
#       row set, exactly. The complementary direction (a TESTED row never appearing in test-gate's <u>) is
#       asserted too — the same claim from the other side.
#   (2) ROW-COUNT INVARIANCE — a partition is a rearrangement, never a filter: each --impact call's
#       printed row count equals its own reaches=, and radius_tested= + radius_untested= == reaches=. The
#       new attribute changed what a row DISCLOSES, never how many rows there are.
#   (3) MUTATION CONTROL — one entry is deliberately dropped from a COPY of the untested set and the
#       equality check is re-run against that copy, proving assertion (1) can actually FAIL and is not
#       comparing two accidentally-always-equal sets.
#
# Usage:  bash test/impactpartitioncheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/impactpartitioncheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

cd "$ROOT"

python3 - "$BIN" <<'PY'
import re, subprocess, sys

BIN = sys.argv[1]
fail = [0]

def ok(msg):
    print("  PASS  " + msg)

def no(msg):
    print("  FAIL  " + msg)
    fail[0] = 1

def run(args):
    p = subprocess.run([BIN, "."] + args, capture_output=True, text=True, timeout=60)
    return p.stdout

def norm_path(p):
    p = p.split(":", 1)[0]           # drop ":line" if present
    if p.startswith("./"):
        p = p[2:]
    return p

SAMPLE_FILE = "src/graph.h"

# ── the sample: every symbol src/graph.h defines, name-deduplicated (an --impact=path:name selector
#    unions every same-named def within that one file on its own, so a within-file duplicate name is
#    handled by the resolver, not by this script). ──────────────────────────────────────────────────────
gq = run(["--graph-query=file(all,\"%s\")" % SAMPLE_FILE.replace(".", r"\."), "--limit=2000"])
seed_names = sorted(set(m.group(1) for m in re.finditer(r'<s t="\w+" n="([^"]+)" p="[^"]+"', gq)))
if len(seed_names) < 50:
    no("sample: %s defines only %d symbols (need >= 50) — pick a bigger file" % (SAMPLE_FILE, len(seed_names)))
    print("impactpartitioncheck: FAILURES"); sys.exit(1)
ok("sample: %s defines %d symbols (>= 50 registered band floor)" % (SAMPLE_FILE, len(seed_names)))

# ── --test-gate=src/graph.h, once, at a limit comfortably above the measured 646 untested rows ─────────
tg = run(["--test-gate=%s" % SAMPLE_FILE, "--limit=5000"])
tg_root = re.search(r'<test-gate ([^>]*)>', tg)
if not tg_root:
    no("--test-gate=%s produced no <test-gate> root" % SAMPLE_FILE)
    print("impactpartitioncheck: FAILURES"); sys.exit(1)
tg_attrs = dict(re.findall(r'(\w[\w-]*)="([^"]*)"', tg_root.group(1)))
if tg_attrs.get("untested_capped") != "0":
    no("--test-gate=%s: untested_capped=%s at --limit=5000 — raise the limit in this script" % (SAMPLE_FILE, tg_attrs.get("untested_capped")))
else:
    ok("--test-gate=%s: untested_capped=0 (the full %s-row list is in this document)" % (SAMPLE_FILE, tg_attrs.get("untested")))

testgate_untested_raw = re.findall(r'<u sym="([^"]+)" p="([^"]+)"', tg)
testgate_untested = set((n, norm_path(p)) for n, p in testgate_untested_raw)
# <u> carries no line number, so two DIFFERENT symbols sharing one (name, file) — a real, pre-existing
# shape (e.g. two overloads) — collapse to one key on BOTH sides of this comparison alike; that is a
# known limit of --test-gate's own row identity, not a parsing bug here, so it is disclosed as INFO
# rather than failing a check this script does not need for the SET EQUALITY claim below.
dup_count = len(testgate_untested_raw) - len(testgate_untested)
if dup_count:
    print("  INFO  --test-gate=%s: %d row(s) share a (name,file) key with another row (no line= on <u> to disambiguate) — collapses identically on both sides" % (SAMPLE_FILE, dup_count))
ok("--test-gate=%s: parsed %d <u> rows into %d distinct (name,file) keys (shown_untested=%s)" % (SAMPLE_FILE, len(testgate_untested_raw), len(testgate_untested), tg_attrs.get("shown_untested")))

testgate_testfiles = set(norm_path(m.group(1)) for m in re.finditer(r'<t p="([^"]+)"', tg))

# ── union every --impact=src/graph.h:SYM call's rows, keyed (name, normalized path) -> tested bool ─────
impact_rows = {}          # key -> tested (bool)
row_count_ok = True
radius_sum_ok = True
for name in seed_names:
    doc = run(["--impact=%s:%s" % (SAMPLE_FILE, name), "--limit=5000"])
    root = re.search(r'<impact ([^>]*)>', doc)
    if not root:
        no("--impact=%s:%s produced no <impact> root" % (SAMPLE_FILE, name))
        continue
    attrs = dict(re.findall(r'(\w[\w-]*)="([^"]*)"', root.group(1)))
    rows = re.findall(r'<s t="\w+" n="([^"]+)" p="([^"]+)"( tested="1")?/>', doc)
    reaches = int(attrs.get("reaches", "-1"))
    if len(rows) != reaches:
        row_count_ok = False
        no("--impact=%s:%s: printed %d rows but reaches=%s (row-count invariance broken)" % (SAMPLE_FILE, name, len(rows), attrs.get("reaches")))
    rt, ru = int(attrs.get("radius_tested", "-1")), int(attrs.get("radius_untested", "-1"))
    if rt + ru != reaches:
        radius_sum_ok = False
        no("--impact=%s:%s: radius_tested(%d) + radius_untested(%d) != reaches(%d)" % (SAMPLE_FILE, name, rt, ru, reaches))
    if attrs.get("capped") not in ("0", None):
        no("--impact=%s:%s: capped=%s at --limit=5000 — raise the limit in this script" % (SAMPLE_FILE, name, attrs.get("capped")))
    for rn, rp, rtested in rows:
        np = norm_path(rp)
        if np == SAMPLE_FILE:
            continue                       # the changed file's own symbols — excluded, as --test-gate excludes them
        if np in testgate_testfiles:
            continue                       # a test-file row — --test-gate folds these into <t>, never <u>
        key = (rn, np)
        tested = bool(rtested)
        if key in impact_rows and impact_rows[key] != tested:
            no("internal inconsistency: %s is tested=%s from one seed and tested=%s from another" % (str(key), impact_rows[key], tested))
        impact_rows[key] = tested

if row_count_ok:
    ok("row-count invariance: every --impact call's printed row count equals its own reaches=")
if radius_sum_ok:
    ok("row-count invariance: radius_tested= + radius_untested= == reaches= on every call")

impact_untested = set(k for k, t in impact_rows.items() if not t)
impact_tested    = set(k for k, t in impact_rows.items() if t)

# ── (1) SET EQUALITY ─────────────────────────────────────────────────────────────────────────────────
missing = testgate_untested - impact_untested   # test-gate says untested, --impact disagrees (or never saw it)
extra   = impact_untested - testgate_untested    # --impact says untested, test-gate does not list it
if not missing and not extra:
    ok("SET EQUALITY: --impact's union of untested rows == --test-gate's <u> rows, exactly (%d rows)" % len(testgate_untested))
else:
    no("SET EQUALITY broken: %d in test-gate not in impact, %d in impact not in test-gate" % (len(missing), len(extra)))
    for k in list(missing)[:5]:
        print("    test-gate-only:", k)
    for k in list(extra)[:5]:
        print("    impact-only:   ", k)

overlap = impact_tested & testgate_untested
if not overlap:
    ok("complementary check: no row --impact marks tested=1 appears in --test-gate's untested list")
else:
    no("complementary check broken: %d rows --impact marks tested=1 are in --test-gate's untested list" % len(overlap))

# ── (3) MUTATION CONTROL — prove the equality check above can actually fail ─────────────────────────────
if testgate_untested:
    mutated = set(testgate_untested)
    dropped = mutated.pop()
    still_equal = (mutated == impact_untested)
    if not still_equal:
        ok("MUTATION CONTROL: dropping one row (%s) from the untested set makes the equality check FAIL, as expected" % str(dropped))
    else:
        no("MUTATION CONTROL: dropping a row did NOT break equality — the assertion above is vacuous")
else:
    no("MUTATION CONTROL: testgate_untested is empty, nothing to mutate — the sample is not exercising real cases")

print()
if fail[0]:
    print("impactpartitioncheck: FAILURES")
else:
    print("impactpartitioncheck: ALL PASS")
sys.exit(fail[0])
PY

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

ROOT="$ROOT" python3 - "$BIN" <<'PY'
import html, os, re, subprocess, sys
sys.path.insert(0, os.path.join(os.environ.get("ROOT", "."), "test"))
import testrowpaths                                   # THE shared tests_to_run row reader

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
# n= is an XML attribute: a name such as `operator<=>` arrives as `operator&lt;=&gt;`, and the selector below is argv, so
# each name is unescaped back to the identifier the binary indexes. Passed escaped, the selector matches nothing
# (found="0", no reaches=) and the row-count arm below reads that as a broken partition (train 26a: a defaulted
# operator<=>, and the <file-scope> owner a namespace-scope static_assert creates, were the first such names in src/graph.h).
seed_names = sorted(set(html.unescape(m.group(1)) for m in re.finditer(r'<s t="\w+" n="([^"]+)" p="[^"]+"', gq)))
escaped = [n for n in seed_names if any(c in n for c in '<>&"\'')]
if escaped:
    ok("sample: %d name(s) carry an XML-escaped character and are passed unescaped: %s" % (len(escaped), " ".join(escaped)))
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

# E1 / review of #214: a tests_to_run row may name SEVERAL files (`<g … p="a,b,c" run_unknown="1"/>`),
# and this set was built from the single rows alone — on a corpus where the rows group, a grouped test file
# was missing from the set and its <s> row was then counted as an untested one. Read through the shared
# reader (test/testrowpaths.py), which knows both shapes in every dialect.
testgate_testfiles = set(norm_path(p) for p in testrowpaths.xml_paths(tg))

# ── union every --impact=src/graph.h:SYM call's rows ─────────────────────────────────────────────────────
# KEYED PER DEFINITION, (name, file, line), for the consistency check. Keyed (name, file) it read two OVERLOADS as one
# symbol: on train 1b quality.h's readAckRecords( path ) (untested) and readAckRecords( path, badLines ) (tested)
# were reported as "tested=True from one seed and tested=False from another" on every leg (#277). A per-definition
# key makes that check mean what it says: ONE definition read two ways by two seeds. The set comparison with
# --test-gate below is still over (name, file), because <u> carries no line: the projection is a key being untested
# when ANY of its overloads is (exactly how <u> collapses them), and tested only when ALL of them are.
def observe(store, def_key, tested):
    """record one --impact observation; True when THIS definition was already seen with the other tested= value"""
    if def_key in store and store[def_key] != tested:
        return True
    store[def_key] = tested
    return False

impact_rows = {}          # (name, file, line) -> tested (bool)
row_count_ok = True
radius_sum_ok = True
for name in seed_names:
    doc = run(["--impact=%s:%s" % (SAMPLE_FILE, name), "--limit=5000"])
    root = re.search(r'<impact ([^>]*)>', doc)
    if not root:
        no("--impact=%s:%s produced no <impact> root" % (SAMPLE_FILE, name))
        continue
    attrs = dict(re.findall(r'(\w[\w-]*)="([^"]*)"', root.group(1)))
    if attrs.get("found") == "0":
        no("--impact=%s:%s: the selector matched no definition (found=0) — a seed this sample listed must resolve" % (SAMPLE_FILE, name))
        continue
    # t= is captured (not just matched) so the loop below can single out t="modscope" — #324's <file-scope>
    # exclusion — without changing what THIS list counts: reaches= still counts every caller row, module
    # scope included, so len(rows) == reaches stays the row-count invariance it always was.
    # 0.6.5 (depth-labelled --impact): a row may carry d= (its hop depth, run-length) between p= and tested=; the
    # row COUNT this invariance reads is unchanged by it (test/impactdepthcheck.sh gates the depths themselves).
    # FE-B: a row reached only through a by-name edge carries via="name" after tested= — it DISCLOSES how the row was
    # reached, never whether it is one, so the row count this invariance reads must take it like d= above.
    rows = re.findall(r'<s t="(\w+)" n="([^"]+)" p="([^"]+)"(?: d="\d+")?( tested="1")?(?: via="name")?/>', doc)
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
    for rkind, rn, rp, rtested in rows:
        np = norm_path(rp)
        if np == SAMPLE_FILE:
            continue                       # the changed file's own symbols — excluded, as --test-gate excludes them
        if np in testgate_testfiles:
            continue                       # a test-file row — --test-gate folds these into <t>, never <u>
        if rkind == "modscope":
            continue                       # #324: a synthetic <file-scope> owner is a legitimate CALLER row
                                            # here (t="modscope", unchanged) but --test-gate's <u> listing now
                                            # excludes it on purpose — nothing can call it, so no test can ever
                                            # be written FOR it, and situ.h's computeTestGateFor drops it before
                                            # <u> is built (model.h::isUntestableOwner). Keeping it on THIS side
                                            # of the comparison would fail assertion (1) on a correct fix, not a
                                            # real regression — it stays counted in reaches=/row-count above,
                                            # only excluded from the untested/tested SET EQUALITY projection.
        line = rp.split(":", 1)[1] if ":" in rp else ""
        def_key = (rn, np, line)
        tested = bool(rtested)
        previous = impact_rows.get(def_key)
        if observe(impact_rows, def_key, tested):
            no("internal inconsistency: %s is tested=%s from one seed and tested=%s from another" % (str(def_key), previous, tested))

if row_count_ok:
    ok("row-count invariance: every --impact call's printed row count equals its own reaches=")
if radius_sum_ok:
    ok("row-count invariance: radius_tested= + radius_untested= == reaches= on every call")

# the (name, file) projection --test-gate's <u> can be compared with (see the keying note above the loop)
impact_by_file = {}
for (n, f, _line), t in impact_rows.items():
    impact_by_file.setdefault((n, f), []).append(t)
impact_untested = set(k for k, ts in impact_by_file.items() if not all(ts))   # any overload untested
impact_tested    = set(k for k, ts in impact_by_file.items() if all(ts))      # every overload tested
mixed_overloads = sorted(k for k, ts in impact_by_file.items() if any(ts) and not all(ts))
if mixed_overloads:
    print("  INFO  %d (name,file) key(s) hold overloads with DIFFERENT tested= (e.g. %s) — compared per definition above, projected as untested below" % (len(mixed_overloads), str(mixed_overloads[0])))

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

# ── (3b) OVERLOAD CONTROL — the per-definition key tells one definition from two overloads ───────────────
# The same observe() the loop uses, fed planted rows: one definition seen tested and then untested MUST be an
# inconsistency (so the consistency check can still fail), and two same-named overloads in one file with different
# tested= must NOT be (the #277 false alarm), while the projection still reads that (name, file) as untested.
probe = {}
observe(probe, ("f", "a.h", "10"), True)
same_def_conflict = observe(probe, ("f", "a.h", "10"), False)
overload_conflict = observe(probe, ("f", "a.h", "20"), False)
if same_def_conflict and not overload_conflict:
    ok("OVERLOAD CONTROL: one definition read tested and untested is flagged; two overloads with different tested= are not")
else:
    no("OVERLOAD CONTROL: same-definition conflict flagged=%s (want True), overload conflict flagged=%s (want False)" % (same_def_conflict, overload_conflict))

# ── (4) F-02 — THE LENS'S BLIND SPOT IS DISCLOSED WHERE THE PARTITION IS READ, AND NOWHERE ELSE ────────
# testSymbolForwardReach only sees a caller through a CALL EDGE from an indexed test symbol, so a shell or
# CLI-level test that drives the built binary as a subprocess contributes nothing to it. On this repo's own
# src/ — tested almost entirely by ~500 test/*.sh gates — that made --impact report radius_untested="48" and
# --callers hop_untested="9" with NOTHING in either legend saying what "untested" meant there; grepping the
# pre-fix callers legend for subprocess|shell|CLI-level|process boundary|script_literal returned zero hits.
# Assertions (1)-(3) above validate the partition against --test-gate's own determination, which is
# SELF-CONSISTENCY between two verbs sharing one definition of "tested" — it can never catch a caveat that is
# missing from both. This arm is that check.
#
# Scoped both ways, because "add the sentence everywhere" would be the wrong fix: it must appear on every
# document that CARRIES the partition, and cost 0 bytes on every document that does not (uses has no tested
# lens at all; the for lens carries only the per-row tested="1" form).
BLIND_ANCHORS = [ "SUBPROCESS", "CALL EDGE from an INDEXED test symbol", "not as no test covers it" ]

def legend_of(doc):
    m = re.match(r"\A(?:\s*<!--.*?-->)+", doc, re.S)
    return m.group(0) if m else ""

CARRIES = [ ("--impact=isPublicApi",  "radius_tested="),
            ("--callers=buildGraph",  "hop_tested="),
            ("--callees=buildGraph",  "hop_tested=") ]
# L1 (2026-09-19): the CLI default legend is compact; arms (4)/(5) read the FULL legend's caveat and row reading, so the XML
# runs ask for it (the inertness arm too: the full legend is where a stray caveat would ride).
for flag, partition_attr in CARRIES:
    doc = run([flag, "--legend=full"])
    lg  = legend_of(doc)
    if partition_attr not in doc:
        no("(4) %s no longer carries %s — this arm measured nothing" % (flag, partition_attr))
        continue
    missing = [a for a in BLIND_ANCHORS if a not in lg]
    if missing:
        no("(4) %s carries %s but its legend is missing the process-boundary caveat: %s" % (flag, partition_attr, missing))
    else:
        ok("(4) %s: the partition and its process-boundary caveat travel together" % flag)

INERT = [ "--uses=rootRelPathsLegend", "--for=resolve call edges by name" ]
for flag in INERT:
    doc = run([flag, "--legend=full"])
    if "radius_tested=" in doc or "hop_tested=" in doc:
        no("(4) %s unexpectedly carries a tested PARTITION — the inertness arm's premise is gone" % flag)
    elif any(a in doc for a in BLIND_ANCHORS):
        no("(4) %s pays for the partition caveat without carrying the partition (should be 0 bytes)" % flag)
    else:
        ok("(4) %s pays 0 bytes for the caveat (no tested partition on it)" % flag)

# ── (5) EACH FORM'S LEGEND READS THE TESTED LENS AS THAT FORM PRINTS IT (2026-09-12) ─────────────────────────────────────
# kTestedRowLegend says tested="1" is "never 0, omitted when it does not", which is true of the XML rows: they print the
# attribute only where the lens holds. The columnar form of the same three verbs carries the lens as a DENSE <tested> column
# (columnar.h emitColumnarTestedColumn), one value per row and 0 on every row the lens does not accept, a test row included,
# and it printed the row sentence anyway: test/fixture's --callers=distance --format=columnar read "never 0" beside
# <tested>0,0</tested>. So the columnar legend must read the column and not carry the row sentence, and the XML legend must
# keep the row sentence, carry no column reading, and print no <s tested="0">. test/fixture holds no test, so every value in
# its columns is 0 and the control is certain. The needles are the two readings' own words (graphlegend.h).
# RED on 036c827d (plain): the three columnar rows FAILed and nothing else did, for example
#   FAIL  (5) --callers=distance --format=columnar: prints <tested>0,0</tested> under a legend that says tested is never 0
ROW_READING = "never 0, omitted when it does not"
COL_READING = "0 = none found, or a test row"

def run_fixture(args):
    p = subprocess.run([BIN, "test/fixture"] + args, capture_output=True, text=True, timeout=60)
    return p.stdout

for args in (["--callers=distance", "--format=columnar"], ["--callees=total_area", "--format=columnar"], ["--impact=distance", "--format=columnar"]):
    doc, label = run_fixture(args), " ".join(args)
    lg     = legend_of(doc)
    fields = re.search(r'<cols [^>]*fields="([^"]*)"', doc)
    col    = re.search(r'<tested>([^<]*)</tested>', doc)
    if not fields or "tested" not in fields.group(1).split(",") or not col or "0" not in col.group(1).split(","):
        no("(5) %s: control broken — no tested column holding a 0, so the legend has nothing to disagree with" % label)
    elif ROW_READING in lg:
        no("(5) %s: prints <tested>%s</tested> under a legend that says tested is never 0" % (label, col.group(1)))
    elif COL_READING not in lg:
        no("(5) %s: prints <tested>%s</tested> and its legend never reads the column's 0" % (label, col.group(1)))
    else:
        ok("(5) %s: the legend reads the column it prints (<tested>%s</tested>)" % (label, col.group(1)))

for args in (["--callers=distance", "--legend=full"], ["--impact=distance", "--legend=full"]):
    doc, label = run_fixture(args), " ".join(args)
    lg = legend_of(doc)
    if not re.search(r'<s [^>]*>', doc):
        no("(5) %s: control broken — no <s> row, so the row reading has nothing to agree with" % label)
    elif re.search(r'<s [^>]* tested="0"', doc):
        no("(5) %s: an <s> row prints tested=\"0\" beside a row reading that says never 0" % label)
    elif ROW_READING not in lg or COL_READING in lg:
        no("(5) %s: the XML legend %s" % (label, "lost the row reading" if ROW_READING not in lg else "reads a column this form does not print"))
    else:
        ok("(5) %s: the row reading rides the XML form, whose rows never print tested=\"0\", and the column reading does not" % label)

print()
if fail[0]:
    print("impactpartitioncheck: FAILURES")
else:
    print("impactpartitioncheck: ALL PASS")
sys.exit(fail[0])
PY

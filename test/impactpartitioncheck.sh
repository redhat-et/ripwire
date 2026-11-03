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
# L7 (type-use impact). A TYPE seed's --impact (its <files> carries type_users=) also walks from the symbols that NAME
# the type, which --test-gate's call-edge blast radius does not, so its rows may be ones <u> lacks. Assertion (1) is
# split so that never loosens the FUNCTION path:
#   (1-fn)   EXACT, no exemption: the untested rows of the FUNCTION seeds alone (no type_users=) are a subset of <u>;
#            `missing` (<u> rows no seed printed) is still computed on the full union.
#   (1-type) TIGHT, per seed and per file: a row (name, F) <u> lacks is excused only when THAT type seed printed it, its
#            uncut rollup (files_capped="0") marks F via="type" or by_type=K, and the seed excuses at most K rows in F
#            (syms= for via="type"). Every other extra row FAILs; a function seed's extra row is never excused by a type seed.
#   (1-mention) the type users themselves (a type seed's d=1 rows in F) are at most the number of times F spells the
#            name — an independent bound, so a type tier that names more users than the source has mentions FAILs
#            even when its own by_type= count agrees with it.
#   (3) runs on the POST-exemption set, and a planted extra row in a file with no via=/by_type= must FAIL (1-type).
# FLOORS this gate cannot see (the type tier has no clause to read, so no row and no extra): a Python STRING annotation
# (`c: "Cell"`), a Go type satisfying an interface IMPLICITLY (no implements clause), a qualified Python base (`mod.Base`).
#
# ONE INDEX FOR THE SEED LOOP (CI-FLAKES-2, 2026-10-27). src/graph.h now defines 577 distinct names, and the loop used to spawn
# one `ripwire . --impact=` PROCESS per name: 577 cache loads + graph builds of the 4,400-file repo, ~1.7 s each on an idle
# 10-core Mac (1980 s with the host loaded, ~870 s on a macos-26 runner, against a 1200 s budget: CI run 40481639494 killed it).
# The loop now asks ONE persistent `ripwire . --mcp` server (parse once, many warm queries) for the same `impact` document. That
# is a different front door onto the identical renderer, so three things keep it honest: (a) the doc the loop reads has its
# root= attribute (the only byte that differs, absolute vs ".") normalized and nothing else; (b) a deterministic sample of seeds
# (every 15th, plus the first 3 type seeds) is ALSO run through the CLI and must be byte-identical to the MCP doc -- a PASS/FAIL
# arm of its own, with a planted-difference control; (c) IMPACTPARTITION_CLI=1 runs every seed through the CLI exactly as before
# (the slow deep path, for a local audit). Every assertion below is unchanged and reads the same documents.
# WHY NOT THE CLI WITH ONE SHARED WARM --cache=FILE (measured, plain binary, same host, interleaved): that keeps the CLI path for
# all 577 seeds but not the cost, because a warm CLI call still loads the cache and rebuilds the call graph every time (the parse is
# not what is slow). 577 calls with one shared cache file: 547 / 684 / 998 s (load avg 6-9) against 156-210 / 106 / 111 s for
# this MCP loop, 3.3x-9x, past the 2x bar this choice was held to, and the 998 s run is the slow-runner shape that was killed at
# 1200 s. So the CLI keeps 42 seeds here and the byte-parity arm above is what ties the two doors together.
#
# Usage:  bash test/impactpartitioncheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/impactpartitioncheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "impactpartitioncheck: BIN=$BIN"

cd "$ROOT"

ROOT="$ROOT" python3 - "$BIN" <<'PY'
import html, os, re, select, subprocess, sys, json, time
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

# ── ONE persistent MCP server answers the per-seed `impact` calls (see the header) ────────────────────────────────────────
CLI_ONLY = os.environ.get("IMPACTPARTITION_CLI") == "1"
# A hang guard, not a speed gate: a warm query is milliseconds, the first one may parse the repo cold (the cache may be absent).
try:
    _scale = float(os.environ.get("PARGATES_BUDGET_SCALE", "1"))
except ValueError:
    _scale = 1.0
MCP_WAIT = 120.0 * max(_scale, 1.0)

class McpImpact:
    def __init__(self):
        # --mcp-legend=inline: the default "session" posture sends the legend once and then trims later answers (the <impact>
        # root loses its attributes), which is a DIFFERENT document; inline prints every answer as the CLI does.
        self.p = subprocess.Popen([BIN, ".", "--mcp", "--mcp-legend=inline"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, bufsize=0)
        self.buf = b""
        self.nid = 0
        self.call("initialize", {})
    def _line(self):
        end = time.time() + MCP_WAIT
        while b"\n" not in self.buf:
            left = end - time.time()
            if left <= 0 or not select.select([self.p.stdout], [], [], left)[0]:
                raise TimeoutError("no answer from the --mcp server within %.0f s" % MCP_WAIT)
            chunk = os.read(self.p.stdout.fileno(), 1 << 20)
            if not chunk:
                raise EOFError("the --mcp server closed its stdout")
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        return line.decode("utf-8", "replace")
    def call(self, method, params):
        self.nid += 1
        self.p.stdin.write((json.dumps({"jsonrpc": "2.0", "id": self.nid, "method": method, "params": params}) + "\n").encode())
        while True:
            msg = json.loads(self._line())
            if msg.get("id") == self.nid:
                return msg
    def impact(self, symbol):
        msg = self.call("tools/call", {"name": "impact", "arguments": {"symbol": symbol, "limit": 5000}})
        try:
            return msg["result"]["content"][0]["text"]
        except (KeyError, IndexError, TypeError):
            return ""
    def close(self):
        try:
            self.p.stdin.close()
            self.p.wait(timeout=30)
        except Exception:
            self.p.kill()

def twin_norm(doc):
    """the one byte the two front doors spell differently: root= is the absolute crawl root over MCP, "." on the CLI"""
    return re.sub(r' root="[^"]*"', ' root="."', doc, count=1)

def same_doc(a, b):
    return twin_norm(a) == twin_norm(b)

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
fn_rows = {}              # the same, from FUNCTION seeds only — assertion (1-fn), exact
# L7: per TYPE seed (its <files> carries type_users=), what (1-type) and (1-mention) read: its name, its rollup row
# per file, its compared rows (after the exclusions below) and its d=1 rows per file (every file, none excluded).
type_seed_recs = []
qualified_rows = [0]      # QUALNAME-1 floor: how many --impact rows printed an `Owner::` prefix (see the join-key note)
row_count_ok = True
radius_sum_ok = True
TWIN_STRIDE = 15            # every 15th seed is ALSO run through the CLI and compared byte-for-byte (the twin arm below)
TWIN_TYPE_EXTRA = 3         # ... plus the first 3 type seeds, whose rollup rows are the richest part of the document
twin_checked, twin_bad, twin_type_seen = [0], [], [0]
mcp = None
if not CLI_ONLY:
    try:
        mcp = McpImpact()
    except Exception as e:
        no("could not start `%s . --mcp --mcp-legend=inline` for the seed loop: %s (IMPACTPARTITION_CLI=1 runs the CLI path)" % (BIN, e))
        print("impactpartitioncheck: FAILURES"); sys.exit(1)
for seed_i, name in enumerate(seed_names):
    sel = "%s:%s" % (SAMPLE_FILE, name)
    if mcp is not None:
        try:
            doc = twin_norm(mcp.impact(sel))
        except Exception as e:
            no("--impact=%s over --mcp: %s" % (sel, e))
            print("impactpartitioncheck: FAILURES"); sys.exit(1)
    else:
        doc = run(["--impact=%s" % sel, "--limit=5000"])
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
    # attrib-multidef: a row of a multi-definition selector carries of_def= (which definition it is a dependant of) last — it
    # attributes the row, never adds or removes one, so the count this invariance reads takes it like via= above.
    rows = re.findall(r'<s t="(\w+)" n="([^"]+)" p="([^"]+)"(?: d="\d+")?( tested="1")?(?: via="name")?(?: of_def="[^"]*")?/>', doc)
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
    files_hdr = re.search(r'<files ([^>]*)>', doc)
    files_attrs = dict(re.findall(r'(\w[\w-]*)="([^"]*)"', files_hdr.group(1))) if files_hdr else {}
    is_type_seed = "type_users" in files_attrs
    if mcp is not None:
        if is_type_seed:
            twin_type_seen[0] += 1
        if seed_i % TWIN_STRIDE == 0 or (is_type_seed and twin_type_seen[0] <= TWIN_TYPE_EXTRA):
            twin_checked[0] += 1
            if not same_doc(doc, run(["--impact=%s" % sel, "--limit=5000"])):
                twin_bad.append(sel)
    rec = None
    if is_type_seed:
        if files_attrs.get("files_capped") != "0":
            no("--impact=%s:%s: a type seed's rollup is cut (files_capped=%s) at --limit=5000 — (1-type) needs every rf row" % (SAMPLE_FILE, name, files_attrs.get("files_capped")))
        rf = {}
        for m in re.finditer(r'<rf ([^>]*)/>', doc):
            a = dict(re.findall(r'(\w[\w-]*)="([^"]*)"', m.group(1)))
            rf[html.unescape(a.get("p", ""))] = a
        rec = { "seed": name, "rf": rf, "rows": [], "d1": {} }
        type_seed_recs.append(rec)
    depth = None
    for m in re.finditer(r'<s t="(\w+)" n="([^"]+)" p="([^"]+)"(?: d="(\d+)")?( tested="1")?', doc):
        if m.group(4):
            depth = int(m.group(4))      # run-length: d= is set where it changes
        if rec is not None and depth == 1:
            f1 = norm_path(m.group(3))
            rec["d1"][f1] = rec["d1"].get(f1, 0) + 1
    for rkind, rn, rp, rtested in rows:
        np = norm_path(rp)
        # QUALNAME-1: a C++ member row prints n="Owner::name"; --test-gate's <u sym=> is the BARE name (its emitter is
        # not owner-qualified), so the join key drops the `Owner::` prefix — spelling only, the (name, file) identity
        # the comparison always used. The floor below proves the prefix really is printed (not silently dropped).
        qn, rn = rn, rn.rsplit("::", 1)[-1]
        if qn != rn:
            qualified_rows[0] += 1
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
        if rec is not None:
            rec["rows"].append((rn, np, tested))
        else:
            observe(fn_rows, def_key, tested)

if mcp is not None:
    mcp.close()
    if twin_bad:
        no("TWIN: %d of %d CLI-compared seeds differ from the --mcp document (first: %s) — the loop above read a different document than --impact prints" % (len(twin_bad), twin_checked[0], twin_bad[0]))
    elif twin_checked[0] < 20:
        no("TWIN: only %d seeds were compared with the CLI (floor 20) — the sample went inert" % twin_checked[0])
    else:
        ok("TWIN: %d seeds (every %dth + the first %d type seeds) are byte-identical over --mcp and the CLI, root= aside" % (twin_checked[0], TWIN_STRIDE, TWIN_TYPE_EXTRA))
    # control: the comparison can FAIL — a planted one-byte change and a planted dropped row are both seen
    probe = run(["--impact=%s:%s" % (SAMPLE_FILE, "Graph" if "Graph" in seed_names else seed_names[-1]), "--limit=5000"])
    planted = re.sub(r'reaches="(\d+)"', lambda m: 'reaches="%d"' % (int(m.group(1)) + 1), probe, count=1)
    dropped = re.sub(r'<s [^>]*/>', '', probe, count=1)
    if probe and same_doc(probe, probe) and not same_doc(probe, planted) and not same_doc(probe, dropped) \
       and same_doc(probe, probe.replace(' root=".', ' root="/abs/where.', 1)):
        ok("MUTATION CONTROL (TWIN): a bumped reaches= and a dropped row are NOT the same document; a different root= spelling is")
    else:
        no("MUTATION CONTROL (TWIN): the byte comparison cannot tell a planted change from the identical document")
else:
    ok("TWIN: skipped — IMPACTPARTITION_CLI=1 ran every seed through the CLI itself")

if qualified_rows[0] > 0:
    ok("QUALNAME-1: %d --impact row(s) printed an Owner::-qualified n= (the join below strips it to --test-gate's bare <u sym=>)" % qualified_rows[0])
else:
    no("QUALNAME-1: no --impact row printed an Owner::name — the member-owner spelling this gate's join strips is gone, re-check the join key")

if row_count_ok:
    ok("row-count invariance: every --impact call's printed row count equals its own reaches=")
if radius_sum_ok:
    ok("row-count invariance: radius_tested= + radius_untested= == reaches= on every call")

# the (name, file) projection --test-gate's <u> can be compared with (see the keying note above the loop)
def project(rows):
    """(untested, tested, mixed) (name, file) keys: untested when ANY overload is, tested only when ALL are"""
    by_file = {}
    for (n, f, _line), t in rows.items():
        by_file.setdefault((n, f), []).append(t)
    return (set(k for k, ts in by_file.items() if not all(ts)),
            set(k for k, ts in by_file.items() if all(ts)),
            sorted(k for k, ts in by_file.items() if any(ts) and not all(ts)))

impact_untested, impact_tested, mixed_overloads = project(impact_rows)
impact_untested_fn = project(fn_rows)[0]
if mixed_overloads:
    print("  INFO  %d (name,file) key(s) hold overloads with DIFFERENT tested= (e.g. %s) — compared per definition above, projected as untested below" % (len(mixed_overloads), str(mixed_overloads[0])))

def tight_exempt(recs, extra_rows):
    """(1-type): the extra rows each type seed may excuse, per file, bounded by ITS rollup row there. -> (exempt, violations)"""
    exempt, violations = set(), []
    for rec in recs:
        per_file = {}
        for rn, np, _t in rec["rows"]:
            if (rn, np) in extra_rows:
                per_file.setdefault(np, set()).add((rn, np))
        for f, keys in sorted(per_file.items()):
            a = rec["rf"].get(f, {})
            bound = int(a.get("syms", "0")) if a.get("via") == "type" else int(a.get("by_type", "0"))
            if len(keys) <= bound:
                exempt |= keys
            else:
                violations.append("%s: %d extra row(s) in %s, rollup allows %d (rf %s)" % (rec["seed"], len(keys), f, bound,
                                  " ".join("%s=%s" % kv for kv in sorted(a.items()) if kv[0] != "p") or "absent"))
    return exempt, violations

def mention_violations(recs):
    """(1-mention): a type seed's d=1 rows in F never outnumber F's spellings of the name"""
    out, texts = [], {}
    for rec in recs:
        pat = re.compile(r'(?<![\w$])%s(?![\w$])' % re.escape(rec["seed"].split("::")[-1]))
        for f, n in sorted(rec["d1"].items()):
            if f not in texts:
                try:
                    texts[f] = open(f, encoding="utf-8", errors="replace").read()
                except OSError:
                    texts[f] = ""
            spelled = len(pat.findall(texts[f]))
            if n > spelled:
                out.append("%s: %d d=1 row(s) in %s, the file spells the name %d time(s)" % (rec["seed"], n, f, spelled))
    return out

# ── (1) SET EQUALITY ─────────────────────────────────────────────────────────────────────────────────
missing  = testgate_untested - impact_untested      # test-gate says untested, --impact disagrees (or never saw it) — FULL union
extra_fn = impact_untested_fn - testgate_untested   # (1-fn) a FUNCTION seed's untested row test-gate does not list: never excused
extra_all = impact_untested - testgate_untested     # every seed's
exempt_tight, type_violations = tight_exempt(type_seed_recs, extra_all)
extra = extra_all - exempt_tight                    # (1-type) what no type seed's own rollup bounds
if not missing and not extra_fn:
    ok("SET EQUALITY (1-fn): the FUNCTION seeds' untested rows are exactly --test-gate's (no exemption), and every one of its %d <u> rows is printed" % len(testgate_untested))
else:
    no("SET EQUALITY broken: %d in test-gate not in impact, %d from a FUNCTION seed's impact not in test-gate" % (len(missing), len(extra_fn)))
    for k in sorted(missing)[:5]:
        print("    test-gate-only:", k)
    for k in sorted(extra_fn)[:5]:
        print("    fn-impact-only:", k)
if not extra and not type_violations:
    ok("SET EQUALITY (1-type): %d row(s) beyond <u>, every one bounded by its own type seed's rollup row (via=\"type\" syms= / by_type=) — %d type seed(s)"
       % (len(exempt_tight), len(type_seed_recs)))
else:
    no("SET EQUALITY (1-type) broken: %d extra row(s) no type seed's rollup bounds, %d file(s) over their bound" % (len(extra), len(type_violations)))
    for v in type_violations[:8]:
        print("    over-bound:    ", v)
    for k in sorted(extra)[:5]:
        print("    impact-only:   ", k)
mention_bad = mention_violations(type_seed_recs)
d1_total = sum(sum(r["d1"].values()) for r in type_seed_recs)
if not mention_bad:
    ok("(1-mention): %d d=1 row(s) over %d type seed(s), no file holding more than it spells the type's name" % (d1_total, len(type_seed_recs)))
else:
    no("(1-mention) broken: %d (seed, file) pair(s) name more type users than the file spells the name" % len(mention_bad))
    for v in mention_bad[:8]:
        print("    over-mention:  ", v)

overlap = impact_tested & testgate_untested
if not overlap:
    ok("complementary check: no row --impact marks tested=1 appears in --test-gate's untested list")
else:
    no("complementary check broken: %d rows --impact marks tested=1 are in --test-gate's untested list" % len(overlap))

# ── (3) MUTATION CONTROL — prove the equality checks above can actually fail ────────────────────────────
# On the POST-exemption set: before L7 this compared against the raw union, which a type seed's extra rows already made
# unequal, so it could never fire.
if testgate_untested:
    mutated = set(testgate_untested)
    dropped = sorted(mutated)[0]
    mutated.discard(dropped)
    still_equal = (mutated == (impact_untested - exempt_tight))
    if not still_equal:
        ok("MUTATION CONTROL: dropping one row (%s) from the untested set makes the post-exemption equality FAIL, as expected" % str(dropped))
    else:
        no("MUTATION CONTROL: dropping a row did NOT break equality — the assertion above is vacuous")
else:
    no("MUTATION CONTROL: testgate_untested is empty, nothing to mutate — the sample is not exercising real cases")
if type_seed_recs:
    planted = dict(type_seed_recs[0])
    planted["rows"] = list(planted["rows"]) + [("plantedExtra", "src/planted_no_type_row.h", False)]
    _ex, pv = tight_exempt([planted], extra_all | {("plantedExtra", "src/planted_no_type_row.h")})
    if pv:
        ok("MUTATION CONTROL (1-type): a planted extra row in a file the seed's rollup does not mark is NOT excused")
    else:
        no("MUTATION CONTROL (1-type): a planted extra row was excused — the type exemption is unbounded")
    inflated = dict(type_seed_recs[0])
    inflated["d1"] = { "src/graph.h": 10 ** 6 }
    if mention_violations([inflated]):
        ok("MUTATION CONTROL (1-mention): a seed naming more users than the file spells is flagged")
    else:
        no("MUTATION CONTROL (1-mention): an inflated d=1 count passed — the mention bound is vacuous")
else:
    no("MUTATION CONTROL (1-type): no type seed in the sample — the type arms measured nothing")

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

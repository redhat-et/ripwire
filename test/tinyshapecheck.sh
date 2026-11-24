#!/usr/bin/env bash
# tinyshapecheck.sh — THETA6, the named-location tiny shape (src/fortinyshape.h; dev knob RIPWIRE_TINY_SHAPE, default OFF).
#
#   (I)  KNOB OFF IS THE BASE: with RIPWIRE_TINY_SHAPE unset no answer carries shape="tiny"; with BASE_BIN= given, the knob-off answer
#        is BASE_BIN's answer byte for byte on 3 questions (the named-location one, the call-path one, the low-confidence one)
#   (T)  KNOB ON, A NAMED LOCATION: a backticked symbol that resolves, confidence="high", no relational cue -> shape="tiny", <= 2048 B,
#        the act line, >= 1 sigs line "P:L-E N" whose N is the symbol, the tiny clause, one <more next=>, no <bodies>/<tail>/<fold>/
#        <hops>, no page= / pages= (one page: no continuation token to break), xmllint clean, no newline outside CDATA
#   (M)  ESCALATION IN ONE CALL: the <more next=> call, run with the knob ON, returns the knob-OFF default answer byte for byte
#   (R)  A RELATIONAL QUESTION STAYS FULL: a call-path question naming the same symbol (RT3 keeps it on --for) is the knob-off answer
#   (L)  A LOW-CONFIDENCE QUESTION STAYS FULL: confidence="low" with a code-shaped span -> the knob-off answer; non-vacuous: under
#        RIPWIRE_TINY_SHAPE_FORCE=1 (the detector skipped) the same call IS tiny, so only the detector kept it full
#   (P)  PAGING AND ROW-FORM CONTRACTS: under the knob, an explicit --page-bytes=N:2, --page-bytes=0 and --rows=elements are the
#        knob-off answers byte for byte (every call here must exit 0 with output: run() FAILs a call that does not)
#   (V)  --version says tiny=on only under the knob, and its knob-off line has no tiny=
#   (X)  MUTATION CONTROL: the (T) checker reds the knob-off (full) answer of the same question, so (T) can fail
#   (G)  A CALLER IN ANOTHER FILE IS NAMED (lanes THETA6-GUARD, THETA6-FINISH): a named symbol with a 1-hop caller in ANOTHER
#        non-test file is tiny and its <edges> line says "called by <that file>:L <caller>"; non-vacuous: the knob-off answer's
#        <callers> holds such a caller (counted, FAIL on 0)
#   (G7) TOO SPREAD TO NAME: a named symbol with more other-file callers than the edges line lists in full (kSpreadEdgeMax 6) stays
#        the full answer; non-vacuous: the knob-off <callers> shows >= 7 such callers (counted, FAIL on fewer) and the call IS tiny
#        under force
#   (E)  THE EDGES LINE (θ6b): a named symbol whose body calls a function in another non-test file is tiny and its <edges> line says
#        "calls <file>:L <callee>"; non-vacuous: the knob-off body's <calls> holds >= 1 <c p=> in another file (counted, FAIL on 0)
#   (E0) NO CROSS-FILE EDGE, NO LINE: a named symbol whose body's only callee is in its own file is tiny with no <edges>;
#        non-vacuous: the knob-off body's <calls> holds >= 1 same-file <c> (counted, FAIL on 0) and none in another file
#   (E4) THE CAP: a body calling 5 functions in 5 other files lists the first 4 and says "(+1 more)", shown="4" total="5";
#        non-vacuous: the knob-off <calls> holds >= 5 other-file <c> (counted, FAIL on fewer)
#   (N)  EXACT EDGES FIRST (θ6e): a body whose first call is a name-only match (via="name") and whose second is exact lists the exact
#        one first; non-vacuous: the knob-off <calls> holds a via="name" other-file <c> before an exact other-file <c> (FAIL if not)
#   (B)  G13: "How does `X` work?" (a breadth word) stays the full answer; non-vacuous: confidence="high" and tiny under force
#   (C)  CAPS: a question that is one ALL-CAPS constant stays the full answer; non-vacuous: confidence="high" and tiny under force
#   (G0) A TEST-FILE CALLER DOES NOT TRIP IT: a symbol whose only other-file callers are test files is tiny (the knob-off <callers>
#        holds >= 1 test-file caller and 0 other non-test-file callers, counted, FAIL on 0)
#   (F)  A CUT CALLERS BLOCK IS A FLOOR (CodeRabbit on #742): a symbol whose <callers> block is cut (d2_capped="1") and has
#        cross-file edges is tiny and its <edges> carries floor="1"; non-vacuous: the knob-off <callers> is cut (FAIL if not)
#   (F0) A CUT BLOCK WITH NO EDGE TO NAME STAYS FULL: the callers are all in the named file, the block is cut -> the full answer;
#        non-vacuous: the knob-off <callers> is cut, confidence="high", and the call IS tiny under force
#   (Q)  AN EDGE THE LINE CANNOT CARRY STAYS FULL: a caller in a directory named with "]]>" -> the full answer; non-vacuous: the
#        knob-off <callers> holds that caller (FAIL on 0) and confidence="high"
#   (S)  SAME-NAME COMPLETION: a function defined in 12 files is listed once per file past row 8 (the knob-off <sigs> holds >= 9
#        same-name rows, counted, FAIL on fewer); every tiny line names the method; <= 16 lines
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-${1:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "tinyshapecheck: python3 required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "tinyshapecheck: xmllint required"; exit 2; }
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "tinyshapecheck: BIN=$BIN${BASE_BIN:+ BASE_BIN=$BASE_BIN}"
unset RIPWIRE_TINY_SHAPE RIPWIRE_TINY_SHAPE_FORCE
export HOME="$WORK/home" TMPDIR="$WORK/tmp/"; mkdir -p "$HOME" "$TMPDIR"

F="$WORK/fx"; mkdir -p "$F/pkg" "$F/ev"
printf 'def frobnicate_cache(widgets):\n    """Flush every widget in the cache."""\n    for w in widgets:\n        w.flush()\n    return len(widgets)\n\n\ndef warm_cache(widgets):\n    for w in widgets:\n        w.load()\n' >"$F/pkg/cache.py"
printf 'from pkg.cache import frobnicate_cache, warm_cache\n\n\ndef render_page(widgets):\n    warm_cache(widgets)\n    return [w.draw() for w in widgets]\n\n\ndef refresh(widgets):\n    frobnicate_cache(widgets)\n    return render_page(widgets)\n' >"$F/pkg/render.py"
printf 'def page_title(name):\n    return name.title()\n\n\ndef page_slug(name):\n    return name.lower().replace(" ", "-")\n' >"$F/pkg/util.py"
printf 'def fmt_line(row):\n    """Format one report row."""\n    return str(row).strip()\n\n\ndef fmt_all(rows):\n    return [fmt_line(r) for r in rows]\n' >"$F/pkg/fmt.py"
printf 'from pkg.fmt import fmt_line\n\n\ndef build_report(rows):\n    """Build the report lines."""\n    out = [fmt_line(r) for r in rows]\n    return out\n' >"$F/pkg/report.py"
mkdir -p "$F/pkg/tests" "$F/shapes"
printf 'from pkg.util import page_title\n\n\ndef test_page_title():\n    assert page_title("a b") == "A B"\n' >"$F/pkg/tests/test_util.py"
printf 'def notify_hub(x):\n    return x\n' >"$F/pkg/hub.py"
for i in 1 2 3 4 5; do
    printf 'def stage_%d(x):\n    return x + %d\n' "$i" "$i" >"$F/pkg/st$i.py"
done
printf 'from pkg.st1 import stage_1\nfrom pkg.st2 import stage_2\nfrom pkg.st3 import stage_3\nfrom pkg.st4 import stage_4\nfrom pkg.st5 import stage_5\n\n\ndef fan_out(x):\n    """Run every stage."""\n    return stage_1(x) + stage_2(x) + stage_3(x) + stage_4(x) + stage_5(x)\n' >"$F/pkg/fan.py"
# (N): execute_step is reached by name only (untyped receiver) and ranks above log_line (12 callers), so the page lists it first
printf 'class Worker:\n    def execute_step(self):\n        return 1\n' >"$F/pkg/aworker.py"
for i in $( seq 1 12 ); do
    printf 'def use_worker_%d(w):\n    return w.execute_step()\n' "$i" >"$F/pkg/wu$i.py"
done
printf 'def log_line(x):\n    return x\n' >"$F/pkg/zhelpers.py"
printf 'from pkg.zhelpers import log_line\n\n\ndef run_job(job):\n    """Run one job and log it."""\n    r = job.execute_step()\n    log_line(job)\n    return r\n' >"$F/pkg/job.py"
printf 'MAX_ROWS_PER_PAGE = 10\n' >"$F/pkg/config.py"
# (F): deep_leaf <- mid_hop (another file) <- 6 second-hop callers, more than the block shows; (F0): the same chain in one file
printf 'def deep_leaf(x):\n    return x\n' >"$F/pkg/leaf.py"
printf 'from pkg.leaf import deep_leaf\n\n\ndef mid_hop(x):\n    return deep_leaf(x)\n' >"$F/pkg/mid.py"
for i in $( seq 1 6 ); do
    printf 'from pkg.mid import mid_hop\n\n\ndef top_caller_%d(x):\n    return mid_hop(x)\n' "$i" >"$F/pkg/top$i.py"
done
{ printf 'def solo_leaf(x):\n    return x\n\n\ndef solo_mid(x):\n    return solo_leaf(x)\n'
  for i in $( seq 1 6 ); do printf '\n\ndef solo_caller_%d(x):\n    return solo_mid(x)\n' "$i"; done; } >"$F/pkg/solo.py"
# (Q): a caller in a directory whose name holds the CDATA terminator
printf 'def quote_leaf(x):\n    return x\n' >"$F/pkg/quote.py"
mkdir -p "$F/pkg/q]]>d"; printf 'from pkg.quote import quote_leaf\n\n\ndef quote_user(x):\n    return quote_leaf(x)\n' >"$F/pkg/q]]>d/quser.py"
for i in $( seq 1 8 ); do
    printf 'from pkg.hub import notify_hub\n\n\ndef call_hub_%d(x):\n    return notify_hub(x)\n' "$i" >"$F/pkg/hubc$i.py"
done
for i in $( seq 1 12 ); do
    printf 'def area_of_shape(x):\n    return x * %d\n' "$i" >"$F/shapes/s$i.py"
done
for i in $( seq 1 40 ); do
    printf 'def on_event_%d(event):\n    """Handle the event and dispatch it."""\n    return dispatch_event(event, %d)\n\n\ndef dispatch_event(event, n):\n    return n\n' "$i" "$i" >"$F/ev/h$i.py"
done

BIN="$BIN" BASE="${BASE_BIN:-}" F="$F" W="$WORK" python3 - <<'PY'
import os, re, shlex, subprocess, sys
BIN, BASE, F, W = os.environ["BIN"], os.environ["BASE"], os.environ["F"], os.environ["W"]
bad = 0
def ok(m): print("  ok   " + m)
def no(m):
    global bad; bad += 1; print("  FAIL " + m)
def run(b, args, knob=None):
    env = {k: v for k, v in os.environ.items() if not k.startswith("RIPWIRE_TINY_SHAPE")}
    if knob == "force": env["RIPWIRE_TINY_SHAPE_FORCE"] = "1"
    elif knob is not None: env["RIPWIRE_TINY_SHAPE"] = knob
    p = subprocess.run([b, F, "--no-cache"] + args, cwd=F, env=env, capture_output=True)
    if p.returncode != 0 or not p.stdout:   # a failed call must not compare equal to another failed call (CodeRabbit on #742)
        no("ripwire %s (knob %s) exited %d with %d B of output: %s" % (" ".join(args), knob, p.returncode, len(p.stdout), p.stderr.decode("utf-8", "replace").strip()[:300]))
    return p.stdout.decode("utf-8", "replace")
def xml_ok(t):
    p = subprocess.run(["xmllint", "--noout", "-"], input=t.encode(), capture_output=True); return p.returncode == 0
def outside_cdata_newline(t):
    return "\n" in re.sub(r"<!\[CDATA\[.*?\]\]>", "", t, flags=re.S).rstrip("\n")

NAMED = "Where is `page_slug` defined?"
PATHQ = "the call path from `refresh` to `frobnicate_cache`"
LOWQ  = "how is an event handled and dispatched by `dispatch_event`"
Q = [NAMED, PATHQ, LOWQ]
off = {q: run(BIN, ["--for=" + q]) for q in Q}
on  = {q: run(BIN, ["--for=" + q], "1") for q in Q}

# (I)
if any('shape="tiny"' in off[q] for q in Q): no("(I) a knob-off answer carries shape=\"tiny\"")
else: ok("(I) no knob-off answer carries shape=\"tiny\" (%d questions)" % len(Q))
if BASE:
    same = sum(run(BASE, ["--for=" + q]) == off[q] for q in Q)
    (ok if same == len(Q) else no)("(I) knob-off == BASE_BIN byte for byte on %d/%d questions" % (same, len(Q)))
else:
    print("  skip (I) BASE_BIN not given: the byte-for-byte base comparison is not run")

# (T)
def tiny_problems(t, sym):
    p = []
    if 'shape="tiny"' not in t.split(">", 1)[0]: p.append("no shape=tiny on the root")
    if len(t.encode()) > 2048: p.append("%d B > 2048" % len(t.encode()))
    if not re.search(r'<act read="[^"]+"/>', t): p.append("no act line")
    m = re.search(r"<sigs[^>]*><!\[CDATA\[(.*?)\]\]></sigs>", t, re.S)
    lines = m.group(1).split("\n") if m else []
    if not lines or not all(re.fullmatch(r"\S+:\d+(-\d+)? \S+", l) for l in lines): p.append("sigs lines are not P:L-E N")
    if not any(l.split(" ")[1].split(".")[-1].split("::")[-1] == sym for l in lines): p.append("no line names " + sym)
    if t.count("<more next=") != 1: p.append("not exactly one <more next=>")
    if "<!-- tiny shape" not in t: p.append("no tiny clause")
    for el in ("<bodies", "<tail", "<fold", "<hops", " page=\"", " pages=\""):
        if el in t: p.append("carries " + el.strip())
    if not xml_ok(t): p.append("xmllint")
    if outside_cdata_newline(t): p.append("newline outside CDATA")
    return p
pr = tiny_problems(on[NAMED], "page_slug")
(no if pr else ok)("(T) named location is tiny (%d B)%s" % (len(on[NAMED].encode()), ": " + "; ".join(pr) if pr else ""))
# (X)
(ok if tiny_problems(off[NAMED], "page_slug") else no)("(X) the (T) checker reds the full (knob-off) answer")

# (M)
m = re.search(r'<more next="([^"]+)"/>', on[NAMED])
if not m: no("(M) no more next=")
else:
    call = shlex.split(m.group(1).replace("&apos;", "'").replace("&quot;", '"').replace("&amp;", "&"))
    (ok if run(BIN, call, "1") == off[NAMED] else no)("(M) the more next= call (knob ON) returns the knob-off default answer byte for byte")

# (R)
if 'shape="tiny"' in run(BIN, ["--for=" + PATHQ], "force") and on[PATHQ] == off[PATHQ] and 'confidence="high"' in off[PATHQ]:
    ok("(R) the call-path question (high confidence, tiny under force) stays the full answer")
else: no("(R) the call-path question: on==off %s, high %s" % (on[PATHQ] == off[PATHQ], 'confidence="high"' in off[PATHQ]))

# (L)
forced = run(BIN, ["--for=" + LOWQ], "force")
if 'confidence="low"' in off[LOWQ] and 'shape="tiny"' in forced and on[LOWQ] == off[LOWQ]:
    ok("(L) the low-confidence question stays the full answer (and is tiny under force: only the detector kept it full)")
else: no("(L) low %s, forced tiny %s, on==off %s" % ('confidence="low"' in off[LOWQ], 'shape="tiny"' in forced, on[LOWQ] == off[LOWQ]))

# (P)
for pb in ("--page-bytes=400:2", "--page-bytes=0", "--rows=elements"):
    a = run(BIN, ["--for=" + NAMED, pb], "1"); b = run(BIN, ["--for=" + NAMED, pb])
    (ok if a == b and 'shape="tiny"' not in a else no)("(P) %s under the knob is the knob-off answer" % pb)

# (V)
v_on = subprocess.run([BIN, "--version"], env=dict(os.environ, RIPWIRE_TINY_SHAPE="1"), capture_output=True, text=True).stdout
v_off = subprocess.run([BIN, "--version"], env={k: v for k, v in os.environ.items() if not k.startswith("RIPWIRE_TINY_SHAPE")}, capture_output=True, text=True).stdout
(ok if "tiny=on, " in v_on and "tiny=" not in v_off else no)("(V) --version tiny=on only under the knob")

# (G) / (G0): the spread guard, against what the knob-off answer's <callers> block holds
def callers_files(t):
    m = re.search(r"<callers [^>]*>(.*?)</callers>", t, re.S)
    rows = re.findall(r"<s ([^>]*?)/?>", m.group(1)) if m else []
    out = []
    for a in rows:
        a = dict(re.findall(r'(\w+)="([^"]*)"', a))
        if a.get("d") != "2" and "p" in a: out.append(a["p"].rsplit(":", 1)[0])
    return out
SPREADQ = "Where is `frobnicate_cache` defined?"
TESTQ = "Where is `page_title` defined?"
s_off, s_on = run(BIN, ["--for=" + SPREADQ]), run(BIN, ["--for=" + SPREADQ], "1")
xf = [f for f in callers_files(s_off) if f != "pkg/cache.py" and "/tests/" not in f]
def edges_text(t):
    m = re.search(r'<edges shown="\d+" total="\d+"><!\[CDATA\[(.*?)\]\]></edges>', t)
    return m.group(1) if m else None
if not xf: no("(G) vacuous: the knob-off answer has 0 other-file callers of frobnicate_cache")
else:
    e = edges_text(s_on)
    good = 'shape="tiny"' in s_on.split(">", 1)[0] and e is not None and re.search(r"called by pkg/render\.py:\d+ refresh\b", e) and xml_ok(s_on)
    (ok if good else no)("(G) %d other-file caller(s) (%s) -> tiny, named on the edges line: %s" % (len(xf), ",".join(xf), e))
# (G7)
HUBQ = "Where is `notify_hub` defined?"
h_off, h_on, h_force = run(BIN, ["--for=" + HUBQ]), run(BIN, ["--for=" + HUBQ], "1"), run(BIN, ["--for=" + HUBQ], "force")
hx = [f for f in callers_files(h_off) if f != "pkg/hub.py" and "/tests/" not in f]
if len(hx) < 7: no("(G7) vacuous: the knob-off answer shows %d other-file callers of notify_hub (< 7)" % len(hx))
elif 'shape="tiny"' not in h_force: no("(G7) vacuous: the too-spread question is not tiny even under force")
else: (ok if h_on == h_off and 'confidence="high"' in h_off else no)("(G7) %d other-file callers (> 6) -> the full answer" % len(hx))
# (E) / (E0): the body's callees, against the knob-off answer's <calls>
def callees(t):
    return [dict(re.findall(r'(\w+)="([^"]*)"', c)) for c in re.findall(r"<c ([^>]*)>", re.sub(r"<!\[CDATA\[.*?\]\]>", "", t, flags=re.S))]
EDGEQ, SAMEFQ = "Where is `build_report` defined?", "Where is `fmt_all` defined?"
e_off, e_on = run(BIN, ["--for=" + EDGEQ]), run(BIN, ["--for=" + EDGEQ], "1")
xc = [c for c in callees(e_off) if c.get("p", "pkg/report.py") != "pkg/report.py"]
if not xc: no("(E) vacuous: the knob-off body of build_report calls 0 other-file functions")
else:
    e = edges_text(e_on)
    good = 'shape="tiny"' in e_on.split(">", 1)[0] and e is not None and "calls pkg/fmt.py:1 fmt_line" in e and len(e_on.encode()) <= 2048 and xml_ok(e_on) and not outside_cdata_newline(e_on)
    (ok if good else no)("(E) %d other-file callee(s) -> tiny, named on the edges line: %s" % (len(xc), e))
f_off, f_on = run(BIN, ["--for=" + SAMEFQ]), run(BIN, ["--for=" + SAMEFQ], "1")
cs = callees(f_off); same_f = [c for c in cs if "p" not in c]; other_f = [c for c in cs if "p" in c]
if not same_f: no("(E0) vacuous: the knob-off body of fmt_all calls 0 same-file functions")
elif other_f: no("(E0) the fixture's fmt_all calls %d other-file functions" % len(other_f))
else: (ok if 'shape="tiny"' in f_on.split(">", 1)[0] and "<edges" not in f_on else no)("(E0) %d same-file callee(s), 0 other-file -> tiny with no <edges>" % len(same_f))
# (E4)
CAPQ = "Where is `fan_out` defined?"
c_off, c_on = run(BIN, ["--for=" + CAPQ]), run(BIN, ["--for=" + CAPQ], "1")
cx = [c for c in callees(c_off) if c.get("p", "pkg/fan.py") != "pkg/fan.py"]
if len(cx) < 5: no("(E4) vacuous: the knob-off body of fan_out calls %d other-file functions (< 5)" % len(cx))
else:
    m = re.search(r'<edges shown="(\d+)" total="(\d+)"><!\[CDATA\[(.*?)\]\]></edges>', c_on)
    good = bool(m) and m.group(1) == "4" and m.group(2) == str(len(cx)) and m.group(3).endswith("(+%d more)" % (len(cx) - 4)) and m.group(3).count("pkg/st") == 4
    (ok if good else no)("(E4) %d other-file callees -> 4 listed: %s" % (len(cx), m.group(0) if m else None))
# (N)
NQ = "Where is `run_job` defined?"
n_off, n_on = run(BIN, ["--for=" + NQ]), run(BIN, ["--for=" + NQ], "1")
nc = [c for c in callees(n_off) if c.get("p", "pkg/job.py") != "pkg/job.py"]
first_name = next((j for j, c in enumerate(nc) if c.get("via") == "name"), None)
first_exact = next((j for j, c in enumerate(nc) if c.get("via") != "name"), None)
if first_name is None or first_exact is None or first_name > first_exact:
    no("(N) vacuous: the knob-off <calls> of run_job lacks a name-only other-file callee before an exact one: %s" % nc)
else:
    e = edges_text(n_on) or ""
    good = e.startswith("calls pkg/zhelpers.py:1 log_line") and "execute_step" in e
    (ok if good else no)("(N) the exact callee is listed before the name-only one: %s" % e)
# (B) / (C)
for arm, q in (("(B)", "How does `build_report` work?"), ("(C)", "MAX_ROWS_PER_PAGE")):
    q_off, q_on, q_force = run(BIN, ["--for=" + q]), run(BIN, ["--for=" + q], "1"), run(BIN, ["--for=" + q], "force")
    if 'confidence="high"' not in q_off or 'shape="tiny"' not in q_force: no("%s vacuous: confidence high %s, tiny under force %s" % (arm, 'confidence="high"' in q_off, 'shape="tiny"' in q_force))
    else: (ok if q_on == q_off else no)("%s %r stays the full answer (high confidence, tiny under force)" % (arm, q))
t_off, t_on = run(BIN, ["--for=" + TESTQ]), run(BIN, ["--for=" + TESTQ], "1")
cf = callers_files(t_off); tf = [f for f in cf if "/tests/" in f]; nf = [f for f in cf if f != "pkg/util.py" and "/tests/" not in f]
if not tf: no("(G0) vacuous: the knob-off answer has 0 test-file callers of page_title")
elif nf: no("(G0) the fixture has %d non-test other-file callers: %s" % (len(nf), nf))
else: (ok if 'shape="tiny"' in t_on.split(">", 1)[0] else no)("(G0) a symbol called only from a test file (%d) is tiny" % len(tf))
# (F) / (F0): a cut <callers> block
def callers_cut(t):
    m = re.search(r"<callers [^>]*>", t)
    return bool(m) and ('capped="1"' in m.group(0) or 'd2_capped="1"' in m.group(0))
d_off, d_on = run(BIN, ["--for=Where is `deep_leaf` defined?"]), run(BIN, ["--for=Where is `deep_leaf` defined?"], "1")
if not callers_cut(d_off): no("(F) vacuous: the knob-off <callers> of deep_leaf is not cut")
else:
    m = re.search(r'<edges shown="\d+" total="\d+" floor="1"><!\[CDATA\[(.*?)\]\]></edges>', d_on)
    good = 'shape="tiny"' in d_on.split(">", 1)[0] and bool(m) and "pkg/mid.py" in m.group(1) and xml_ok(d_on)
    (ok if good else no)("(F) a cut callers block -> tiny, edges floor=\"1\": %s" % (m.group(0) if m else None))
SOLOQ = "Where is `solo_leaf` defined?"
o_off, o_on, o_force = run(BIN, ["--for=" + SOLOQ]), run(BIN, ["--for=" + SOLOQ], "1"), run(BIN, ["--for=" + SOLOQ], "force")
if not callers_cut(o_off) or 'confidence="high"' not in o_off or 'shape="tiny"' not in o_force:
    no("(F0) vacuous: cut %s, confidence high %s, tiny under force %s" % (callers_cut(o_off), 'confidence="high"' in o_off, 'shape="tiny"' in o_force))
else: (ok if o_on == o_off else no)("(F0) a cut callers block with no cross-file edge stays the full answer")
# (Q)
QQ = "Where is `quote_leaf` defined?"
q_off, q_on = run(BIN, ["--for=" + QQ]), run(BIN, ["--for=" + QQ], "1")
qx = [f for f in callers_files(q_off) if "]]&gt;" in f or "]]>" in f]
if not qx or 'confidence="high"' not in q_off: no("(Q) vacuous: %d callers under a ]]> directory, confidence high %s" % (len(qx), 'confidence="high"' in q_off))
else: (ok if q_on == q_off else no)("(Q) a caller path holding ]]> (%s) -> the full answer" % qx[0])
# (S)
SAMEQ = "area_of_shape"   # the bare-symbol form NL1 asks (a backticked sentence over 12 same-name defs resolves none)
a_off, a_on = run(BIN, ["--for=" + SAMEQ]), run(BIN, ["--for=" + SAMEQ], "1")
m = re.search(r"<sigs[^>]*><!\[CDATA\[(.*?)\]\]>", a_off, re.S)
same_off = sum(1 for l in (m.group(1).split("\n") if m else []) if "area_of_shape" in l.split(" | ")[0])
m = re.search(r"<sigs[^>]*><!\[CDATA\[(.*?)\]\]></sigs>", a_on, re.S)
lines = m.group(1).split("\n") if m else []
if same_off < 9: no("(S) vacuous: the knob-off sigs hold %d same-name rows (< 9)" % same_off)
elif 'shape="tiny"' not in a_on.split(">", 1)[0]: no("(S) the same-name question is not tiny (%s)" % (re.search(r'confidence="\w+"', a_off) or [""])[0])
else:
    good = len(lines) == min(same_off, 16) and all(l.endswith("area_of_shape") for l in lines) and xml_ok(a_on)
    (ok if good else no)("(S) %d same-name rows in the full answer -> %d tiny lines, all area_of_shape" % (same_off, len(lines)))
print("tinyshapecheck: %s" % ("PASS" if bad == 0 else "FAIL (%d)" % bad))
sys.exit(1 if bad else 0)
PY

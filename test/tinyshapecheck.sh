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
#   (P)  PAGING CONTRACTS: under the knob, an explicit --page-bytes=N:2 and --page-bytes=0 are the knob-off answers byte for byte
#   (V)  --version says tiny=on only under the knob, and its knob-off line has no tiny=
#   (X)  MUTATION CONTROL: the (T) checker reds the knob-off (full) answer of the same question, so (T) can fail
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
for pb in ("--page-bytes=400:2", "--page-bytes=0"):
    a = run(BIN, ["--for=" + NAMED, pb], "1"); b = run(BIN, ["--for=" + NAMED, pb])
    (ok if a == b and 'shape="tiny"' not in a else no)("(P) %s under the knob is the knob-off answer" % pb)

# (V)
v_on = subprocess.run([BIN, "--version"], env=dict(os.environ, RIPWIRE_TINY_SHAPE="1"), capture_output=True, text=True).stdout
v_off = subprocess.run([BIN, "--version"], env={k: v for k, v in os.environ.items() if not k.startswith("RIPWIRE_TINY_SHAPE")}, capture_output=True, text=True).stdout
(ok if "tiny=on, " in v_on and "tiny=" not in v_off else no)("(V) --version tiny=on only under the knob")
print("tinyshapecheck: %s" % ("PASS" if bad == 0 else "FAIL (%d)" % bad))
sys.exit(1 if bad else 0)
PY

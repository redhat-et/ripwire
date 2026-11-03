#!/usr/bin/env bash
# hopbodycheck.sh — THE BODY OF A MIDDLE HOP (lane path-hop-body, train 41; src/hopbody.h).
#
# THE CONTRACT THIS PINS (arms tagged [P] are RED on the pre-change binary 5163ffbdb; [G] arms are twins and near-miss negatives
# that hold on both binaries and must keep holding — PROCESS rule 4, no gate erosion):
#
#   PATH-HOP-BODY  a reached --path (and MCP path_between) whose shown chain has 2 hops prints, after its hop rows,
#                  <bodies of="hops" shown= total= capped=> holding the body of its INTERMEDIATE hop (never an endpoint), each
#                  the --expand body element (b t= l= p= n=, CDATA = the definition's source text, no callee rows). A body
#                  over 4000 B is cut at a line end and says so (truncated="1" lines="1-K/T" next= serves the rest). A chain of
#                  more hops prints no body and its root carries next= (the first middle hop's --expand). Inside a --for answer's
#                  graph-verb block a middle hop whose text the answer already carries (a served class holding it) prints no copy.
#   WRAPPER-FOLLOW a --for fold body that is a THIN DELEGATOR (one proven callee, no other call, at most 3 statement lines) is
#                  followed by its callee's body <b follow_of="WRAPPER">, at most 2 levels, never a text the answer already
#                  carries; a by-name edge, a second call, or a fourth statement line is not a delegator.
#   LEGEND         every new reading is present-only: the compact path reading `bodies of=hops`, the full path clause, the
#                  fold's follow_of= clause ride exactly when the element/attribute does.
#   A/B            RIPWIRE_NO_HOP_BODY=1 is the answer without either mechanism.
#
# Arms (colour on 5163ffbdb in brackets):
#   P1 [P] fetch -> dispatch -> compose: one <bodies of="hops"> with dispatch's body, CDATA = its source text; no endpoint body
#   P2 [P] a 3-hop chain (past the gate) prints no body; root next="--expand=src/chain.ts:5:stepTwo"
#   P3 [P] a 4-hop chain prints no body; root next="--expand=src/chain.ts:5:stepTwo", and that call serves stepTwo's body
#   P9 [P] the --for graph-verb block: gatewayEntry -> relayHop prints relayHop's body (P9a); Server.fetch's twin, whose
#          answer already serves the Server class holding dispatch, prints no copy (P9b) — kills a NodeId-only dedupe
#   P4 [P] a middle body over the guard: truncated="1" lines="1-K/T" next=, capped="1", served text <= 4000 B, next= serves the rest
#   P5 [G] a 1-hop chain and an unreached pair: no <bodies>, no next=
#   P6 [P] legend present-only, compact and full: the reading rides iff the element does; the past-the-gate next= reading in full
#   P7 [P] MCP path_between prints the CLI's <bodies of="hops"> element byte for byte (P1, P4) and the 3- and 4-hop next=
#   P8 [G] RIPWIRE_NO_HOP_BODY=1: the path answer is the head answer minus the element, its clause and the 4-hop next=
#   F1 [P] the 2-level follow: handleRequest -> forwardInput -> runPipeline, each <b follow_of=> right after its wrapper,
#          CDATA = the source text; the follow_of clause rides
#   F2 [G] a one-call body of four statement lines (handleTimedRequest) is never followed
#   F3 [G] a two-call body (listen) is never followed; a delegate inside a served body (fetch -> dispatch in Server) prints no copy
#   F4 [G] a by-name delegate (worker.crunchInput, via=name) is never followed
#   F5 [G] each text once: no two <b> of one answer share p= and l=
#   F6 [G] RIPWIRE_NO_HOP_BODY=1: no follow_of=, no clause, answer == head minus the follow bodies and clause
#   X1 [G] determinism   X2 [G] xmllint well-formed   X3 [G] no "--" inside a legend comment
#   I  [optional, RIPWIRE_BASE_BIN=<pre-change binary>] RIPWIRE_NO_HOP_BODY=1 head == the base binary on every question here
#
# FIX1 arms (lane path-hop-body-fix1; [M] = RED on the path-hop-body head 5351fbbb / the merge binary, the review's findings):
#   H1 [M] a BY-NAME middle hop (P1.process / P2.process): its body carries via="name" cands="2" on the <b> (F1), the hedge clause
#          rides; a proven middle hop (P1's dispatch) carries none
#   H2 [M] a declined iface call (ts15 m.match) or an undefined call (missingHelperCall) beside the one proven call: never followed (F2)
#   H3 [M] a call bound only through a pybind11 binding (amb=, one call site): never followed — pins the ambOut guard (review mutant MA)
#   H4 [M] C stores `*out = …` are statement lines: scale_and_store is not a thin wrapper (F3)
#   H5 [M] a documented Python delegator is followed (F4), follow_of names the wrapper as Owner.name (F7)
#   H6 [M] a class with a field initializer is never a wrapper (F5)
#   H7 [M] logic beside one call (computeScoreTotal) and a .filter().map().reduce() pipeline are not delegators (F2/F6)
#   H8 [M] a one-line wrapper over a > 4000 B callee: the follow is cut, truncated="1" lines= next= (kills the review's mutant MB)
#   H9 [M] the answer-wide follow guard: 3 follow bodies, then <follow_cut n="2" next=> naming the first unfollowed callee
#   R1 [M] BODY-ON-ROUTE: a reachable=0 poster -> queue -> dispatch answer prints <bodies of="route" proven="0"> with post_message,
#          _process_messages_loop (via="queue" cands="2"), _dispatch_message and the hrd reader _on_message (via="name-key"), CDATA =
#          source; never the to= row (on_event); reachable= and hops= unchanged; the of=route clause rides (compact and full)
#   R2 [M] the route spew guard: a fifth route body is cut, capped="1" next="--expand=pump.py:45:_trace_message"
#   R3 [M] the hop bound: the 4-hop bridge press -> on_event prints its rows 0..2 only (press, post_message, the loop)
#   H4b[M] three `*p =` stores before the one call: 4 statement lines, never followed (pins the * comment rule alone)
#   R6-R9 [M] FIX2 (review rv-phbf1): R6 a by-name bridge edge row's body carries via=name cands=2 (G1); R7 a > 4000 B route body is cut,
#          truncated=1 lines= next= (G2); R8 a reader that is also a bridge row prints once (G3); R9 a slot crossing's body carries slot_fns=
#          and the bare-b reading rides (S1, S4)
#   R10 [M] CR pre-pass 41: a route/hop body prints a definition, <alts> never lists it again (post_message bound to no definition because
#          a second class defines it too): <alts side="from"> lists the other class's post_message, not the pump.py:10 the route body
#          printed; the same on MCP path_between; [G] a definition no body printed is still listed
#   R5 [G] the gain gate: inside a --for answer's graph-verb block the unreached path prints no route bodies
#   R4 [G] RIPWIRE_NO_HOP_BODY=1: no route element; MCP path_between prints the CLI's route element byte for byte
#
# Usage:  bash test/hopbodycheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/hopbodycheck.sh
# BIN is $1, else RIPWIRE_BIN, else build/ripwire; the first output line names the binary used. Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_HOP_BODY RIPWIRE_NO_BODY_FOLD RIPWIRE_NO_BODY_SLOT
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "hopbodycheck: BIN=$BIN"
fail=0
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
cd "$ROOT"
WEB="test/hopbodyfix/web"; FOL="test/hopbodyfix/follow"; LOO="test/hopbodyfix/loose"
[ -d "$WEB/src" ] && [ -d "$FOL/src" ] && [ -d "$LOO/src" ] || { echo "fixture test/hopbodyfix missing"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
run(){ local d="$1"; shift; ( cd "$d" || exit 1; "$BIN" "$ROOT/$d" --no-cache "$@" 2>/dev/null ); }

T_FOLLOW="How is a request handled?"
T_TIMED="How does handling a request work?"
T_WEB="How does a request flow from fetch to its Response?"
T_LISTEN="How does the server listen for a request?"
T_LOOSE="How is a loose request handled?"

run "$WEB" --path=fetch,compose        >"$TMP/p1"
run "$WEB" --path=stepOne,stepFour     >"$TMP/p2"
run "$WEB" --path=stepOne,stepFive     >"$TMP/p3"
run "$WEB" --path=bigEntry,bigSink     >"$TMP/p4"
run "$WEB" --path=stepFour,stepFive    >"$TMP/p5a"
run "$WEB" --path=compose,fetch        >"$TMP/p5b"
run "$WEB" --for="Trace the path from gatewayEntry() to finalStage()" >"$TMP/p9a"
run "$WEB" --for="Trace the path from Server.fetch to compose()"  >"$TMP/p9b"
run "$WEB" --path=fetch,compose --legend=full    >"$TMP/p1f"
run "$WEB" --path=stepOne,stepFive --legend=full >"$TMP/p3f"
run "$WEB" --path=stepFour,stepFive --legend=full >"$TMP/p5af"
RIPWIRE_NO_HOP_BODY=1 run "$WEB" --path=fetch,compose    >"$TMP/p1.off"
RIPWIRE_NO_HOP_BODY=1 run "$WEB" --path=stepOne,stepFour >"$TMP/p2.off"
RIPWIRE_NO_HOP_BODY=1 run "$WEB" --path=stepOne,stepFive >"$TMP/p3.off"
RIPWIRE_NO_HOP_BODY=1 run "$WEB" --path=bigEntry,bigSink >"$TMP/p4.off"
run "$FOL" --for="$T_FOLLOW"           >"$TMP/f1"
run "$FOL" --for="$T_FOLLOW" --legend=full >"$TMP/f1f"
RIPWIRE_NO_HOP_BODY=1 run "$FOL" --for="$T_FOLLOW" >"$TMP/f1.off"
run "$FOL" --for="$T_TIMED"            >"$TMP/f2"
run "$WEB" --for="$T_WEB"              >"$TMP/f3a"
run "$WEB" --for="$T_LISTEN"           >"$TMP/f3b"
run "$LOO" --for="$T_LOOSE"            >"$TMP/f4"
run "$LOO" --callees=handleLooseRequest >"$TMP/f4c"

# FIX1 fixtures (the route ones run from a copy outside test/: a reader under a test path is not a handler_rule reader)
HB="test/hopbodyfix"
cp -R "$HB/route" "$HB/routecap" "$HB/routeslot" "$TMP/"
run "$HB/byname" --path=startJ,sinkJ >"$TMP/h1"
run "$HB/byname" --path=startJ,sinkJ --legend=full >"$TMP/h1f"
run "$HB/declined" --for="how does relayWorkItem relay a work item" >"$TMP/h2a"
run "$HB/declined" --callees=relayWorkItem >"$TMP/h2c"
run "$HB/external" --for="how does relayWorkItem relay a work item" >"$TMP/h2b"
run "$HB/ffi" --for="How does relay_transform relay a value?" >"$TMP/h3"
run "$HB/ffi" --callees=relay_transform >"$TMP/h3c"
run "$HB/cstore" --for="how does scale_and_store scale and store" >"$TMP/h4"
run "$HB/cstore" --for="how does prime_then_fill prime the buffers then fill" >"$TMP/h4b"
run "$HB/pydoc" --for="how does Widget post_message post a message" >"$TMP/h5a"
run "$HB/pydoc" --for="how does Widget post_message_plain post a message" >"$TMP/h5b"
run "$HB/klass" --for="how does PanelHolder compute the panel size for the holder" >"$TMP/h6"
run "$HB/klass" --for="how does ChildRunner launch the runner" >"$TMP/h6b"
run "$HB/logic" --for="how does computeScoreTotal compute the score total" >"$TMP/h7a"
run "$HB/logic" --for="how does pipelineScore score the pipeline items" >"$TMP/h7b"
run "$HB/bigfollow" --for="how does relayWorkItem relay a work item" >"$TMP/h8"
run "$HB/many" --for="How does shipOrder ship an order?" >"$TMP/h9"
run "$HB/many" --for="How does shipOrder ship an order?" --legend=full >"$TMP/h9f"
rrun(){ local d="$1"; shift; ( cd "$TMP/$d" || exit 1; "$BIN" "$TMP/$d" --no-cache "$@" 2>/dev/null ); }
rrun route '--path=post_message,on_*' >"$TMP/r1"
rrun route '--path=post_message,on_*' --legend=full >"$TMP/r1f"
rrun routecap '--path=post_message,on_*' >"$TMP/r2"
rrun route '--path=press,on_event' >"$TMP/r3"
rrun route --for="Trace the path from post_message() to on_event()" >"$TMP/r5"
# the R6-R8 fixtures are the route fixture with one edit each (so no committed clone): R6 a by-name call (two same-named routers), R7 four bodies
# over 4000 B, R8 the reader _on_message is also reached as a bridge row (the loop calls it by way of _dispatch_message)
python3 - "$TMP" <<'PY'
import os, shutil, sys
T = sys.argv[1]; src = open(os.path.join(T, "route", "pump.py")).read().split("\n")
def make(name, lines):
    shutil.copytree(os.path.join(T, "route"), os.path.join(T, name)); open(os.path.join(T, name, "pump.py"), "w").write("\n".join(lines))
by = [l.replace("self._dispatch_message(message)", "self.router.dispatch_message(message)") for l in src]
make("routename", by + ["", "", "class RouterA:", "    def dispatch_message(self, message):", "        self.pump.on_event(message)", "", "", "class RouterB:", "    def dispatch_message(self, message):", "        return message", ""])
ded = list(src); ded[26:26] = ["        name = message.handler_name", "        getattr(self, name)(message)"]
make("routededupe", ded)
big = list(src)
for at in (33, 25, 20, 12): big[at:at] = ["        x%d = len(str(message)) + %d" % (i, i) for i in range(160)]
make("routebig", big)
shutil.copytree(os.path.join(T, "route"), os.path.join(T, "routealt"))
open(os.path.join(T, "routealt", "other.py"), "w").write("class Other:\n    def post_message(self, message):\n        return message\n")
PY
rrun routename '--path=post_message,on_*' >"$TMP/r6"
rrun routebig '--path=post_message,on_*' >"$TMP/r7"
rrun routededupe '--path=post_message,on_*' >"$TMP/r8"
rrun routealt '--path=post_message,on_*' >"$TMP/r10"
rrun routeslot '--path=start_job,sink_write' >"$TMP/r9"
rrun routeslot '--path=start_job,sink_write' --legend=full >"$TMP/r9f"
( cd "$TMP/route" && RIPWIRE_NO_HOP_BODY=1 "$BIN" "$TMP/route" --no-cache '--path=post_message,on_*' 2>/dev/null ) >"$TMP/r1.off"

cat > "$TMP/chk.py" <<'PY'
import html, re, shlex, shutil, subprocess, sys, os
T, BIN, ROOT = sys.argv[1], sys.argv[2], sys.argv[3]
fails = 0
def rd(n): return open(os.path.join(T, n), "rb").read().decode("utf-8", "replace")
def ok(m): print("  PASS  " + m)
def no(m):
    global fails; fails += 1; print("  FAIL  " + m)
def check(c, m): ok(m) if c else no(m)
def attrs(s): return dict((k, html.unescape(v)) for k, v in re.findall(r'(\w+)="([^"]*)"', s))
def cdata(x): return "".join(re.findall(r'<!\[CDATA\[(.*?)\]\]>', x, re.S))
def bodies(x): return [(attrs(m.group(1)), cdata(m.group(2)), m.group(0)) for m in re.finditer(r'<b ([^>]*)>(.*?)</b>', x, re.S)]
def hopel(t):
    m = re.search(r'<bodies of="hops"[^>]*>.*?</bodies>', t, re.S); return m.group(0) if m else ""
def root(t):
    m = re.search(r'<path ([^>]*)>', t); return attrs(m.group(1)) if m else {}
def legend(t): return " ".join(re.findall(r'<!--(.*?)-->', t, re.S))
def is_source(b, d):
    """the body's CDATA is its definition's source text: a substring of the file p= starting on line l="""
    a, cd = b[0], b[1]
    try: src = open(os.path.join(ROOT, d, a.get("p", "")), encoding="utf-8").read()
    except OSError: return False
    i = src.find(cd)
    return cd != "" and i >= 0 and src[:i].count("\n") + 1 == int(a.get("l", "0"))
def paste(nxt, d):
    argv = shlex.split(nxt)
    return subprocess.run([BIN, os.path.join(ROOT, d), "--no-cache"] + argv, cwd=os.path.join(ROOT, d), capture_output=True).stdout.decode("utf-8", "replace")
WEB, FOL = "test/hopbodyfix/web", "test/hopbodyfix/follow"

# P1
p1 = rd("p1"); el = hopel(p1); bs = bodies(el)
check(len(bs) == 1 and bs[0][0].get("n") == "dispatch" and bs[0][0].get("l") == "10", "(P1) one middle-hop body: dispatch l=10")
check(bs and is_source(bs[0], WEB) and "return composed(request)" in bs[0][1], "(P1) its CDATA is the definition's source text, whole")
check(not re.search(r'<b [^>]*n="(fetch|compose)"', el) and "<calls" not in el and "sibs=" not in el, "(P1) no endpoint body, no callee rows, no file context")
check('of="hops" shown="1" total="1" capped="0"' in el, "(P1) envelope shown=1 total=1 capped=0")
# P2
p2 = rd("p2"); r2 = root(p2)
check(hopel(p2) == "" and r2.get("hops") == "3", "(P2) a 3-hop chain (past the gate) prints no body")
check(r2.get("next") == "--expand=src/chain.ts:5:stepTwo", "(P2) its root next= is the first middle hop's --expand: %r" % r2.get("next"))
# P9: the --for graph-verb block
gv = lambda t: (re.search(r'<graph_verb .*?</graph_verb>', t, re.S) or re.search(r'$', t)).group(0)
g9a, g9b = gv(rd("p9a")), gv(rd("p9b"))
b9a = bodies(hopel(g9a))
check(g9a != "" and len(b9a) == 1 and b9a[0][0].get("n") == "relayHop" and is_source(b9a[0], WEB), "(P9a) the graph-verb path block prints the middle hop's body")
check(re.search(r'<b [^>]*n="Server"', rd("p9b")) and g9b != "" and hopel(g9b) == "", "(P9b) a middle hop inside a body the answer serves prints no copy")
# P3
p3 = rd("p3"); r = root(p3)
check(hopel(p3) == "" and r.get("hops") == "4", "(P3) a 4-hop chain prints no body")
check(r.get("next") == "--expand=src/chain.ts:5:stepTwo", "(P3) root next= is the first middle hop's --expand: %r" % r.get("next"))
check(r.get("next") and "return stepThree(n * 2)" in cdata(paste(r["next"], WEB)), "(P3) the pasted next= serves stepTwo's body")
# P4
el = hopel(rd("p4")); bs = bodies(el); a = bs[0][0] if bs else {}
check(a.get("truncated") == "1" and re.fullmatch(r'1-\d+/\d+', a.get("lines", "")) and a.get("next", "").startswith("--expand=src/big.ts:5:bigMiddle:"), "(P4) the long middle body is cut and says so: %r" % {k: a.get(k) for k in ("truncated", "lines", "next")})
check('capped="1"' in el and bs and len(bs[0][1].encode()) <= 4000, "(P4) capped=1 and the served text is <= 4000 B")
if bs and a.get("next"):
    rest = cdata(paste(a["next"], WEB)); hi = int(a["lines"].split("-")[1].split("/")[0]); tot = int(a["lines"].split("/")[1])
    check(rest.count("\n") + 1 == tot - hi and bs[0][1].endswith("\n") is False, "(P4) next= serves exactly the lines the cut left (%d of %d)" % (tot - hi, tot))
# P5
for f in ("p5a", "p5b"):
    t = rd(f); check(hopel(t) == "" and "next=" not in (re.search(r'<path [^>]*>', t).group(0) if re.search(r'<path [^>]*>', t) else ""), "(P5) %s: no <bodies>, no root next=" % f)
check('reachable="0"' in rd("p5b"), "(P5) compose,fetch is the unreached twin")
# P6
check("bodies of=hops" in legend(p1) and "bodies of=hops" not in legend(rd("p3")) and "bodies of=hops" not in legend(rd("p5a")), "(P6) compact: the reading rides iff the element does")
check("bodies of=hops" in legend(rd("p1f")) and "bodies of=hops" not in legend(rd("p5af")), "(P6) full: the clause rides iff the element does")
check("first middle hop" in legend(rd("p3f")) and "first middle hop" not in legend(rd("p1f")), "(P6) full: the 4-hop next= reading rides iff that next= does")
# P8
for f in ("p1", "p4"):
    on, off = rd(f), rd(f + ".off")
    strip = re.sub(r'<bodies of="hops".*?</bodies>', '', on, flags=re.S)
    strip = re.sub(r' bodies of=hops: .*?(?= -->|\. (?=[a-z_]+[=:])|$)\.?', '', strip, flags=re.S)
    check(hopel(off) == "" and re.sub(r'<!--.*?-->', '', strip, flags=re.S) == re.sub(r'<!--.*?-->', '', off, flags=re.S), "(P8) %s: RIPWIRE_NO_HOP_BODY=1 == head minus the element (payload)" % f)
check('next=' not in re.search(r'<path [^>]*>', rd("p3.off")).group(0) and 'next=' not in re.search(r'<path [^>]*>', rd("p2.off")).group(0), "(P8) RIPWIRE_NO_HOP_BODY=1: no past-the-gate next=")
# F1
f1 = rd("f1"); bs = bodies(f1); names = [b[0].get("n") for b in bs]
fo = {b[0].get("n"): b for b in bs if "follow_of" in b[0]}
check(fo.get("forwardInput", [{}])[0].get("follow_of") == "handleRequest" and fo.get("runPipeline", [{}])[0].get("follow_of") == "forwardInput", "(F1) the 2-level follow: %r" % {k: v[0].get("follow_of") for k, v in fo.items()})
check("handleRequest" in names and names.index("forwardInput") == names.index("handleRequest") + 1 and names.index("runPipeline") == names.index("forwardInput") + 1 if "forwardInput" in names and "runPipeline" in names and "handleRequest" in names else False, "(F1) each follow right after its wrapper")
check("forwardInput" in fo and is_source(fo["forwardInput"], FOL) and "runPipeline" in fo and is_source(fo["runPipeline"], FOL) and "segments.length === 0" in fo["runPipeline"][1], "(F1) follow CDATA are the definitions' source text, whole")
check("follow_of=W" in legend(f1) and "follow_of=W" in legend(rd("f1f")), "(F1) the follow_of clause rides in both legends")
# F2-F4
check(not re.search(r'follow_of="handleTimedRequest"', rd("f2")) and re.search(r'<b [^>]*n="handleTimedRequest"', rd("f2")) and not re.search(r'<b [^>]*n="stampInput"', rd("f2")), "(F2) the 4-statement-line wrapper is served and never followed (its callee stampInput never prints)")
check("follow_of=" not in rd("f3a") and "follow_of=W" not in legend(rd("f3a")), "(F3) fetch's delegate lies inside the served Server body: no copy, no clause")
check(re.search(r'<b [^>]*n="listen"', rd("f3b")) and 'follow_of="listen"' not in rd("f3b"), "(F3) the two-call listen is never followed")
check('via="name"' in rd("f4c") and re.search(r'<b [^>]*n="handleLooseRequest"', rd("f4")) and "follow_of=" not in rd("f4"), "(F4) a by-name delegate is never followed")
# F5
for f in ("f1", "f2", "f3a", "f3b", "f4", "p1", "p9a", "p9b"):
    keys = [(b[0].get("p"), b[0].get("l")) for b in bodies(rd(f))]
    check(len(keys) == len(set(keys)), "(F5) %s: each text once" % f)
# F6
off = rd("f1.off")
check("follow_of" not in off, "(F6) RIPWIRE_NO_HOP_BODY=1: no follow_of= and no clause")
strip = re.sub(r'<b [^>]*follow_of="[^"]*"[^>]*>.*?</b>', '', f1, flags=re.S)
mask = lambda t: re.sub(r' est_tokens="\d+"', '', re.sub(r'<!--.*?-->', '', t, flags=re.S))
check(mask(strip) == mask(off), "(F6) the --for answer minus the follow bodies == the RIPWIRE_NO_HOP_BODY=1 answer (payload, est_tokens masked)")
# FIX1 H1-H9: the review's findings
el = hopel(rd("h1")); bs = bodies(el)
check(len(bs) == 1 and bs[0][0].get("n") == "process" and bs[0][0].get("via") == "name" and bs[0][0].get("cands") == "2", "(H1) a by-name middle hop's body carries via=name cands=2: %r" % [b[0] for b in bs])
check("b via= cands=" in legend(rd("h1")) and "no proven call" in legend(rd("h1f")), "(H1) the hedge clause rides, compact and full")
check(bodies(hopel(rd("p1"))) and "via" not in bodies(hopel(rd("p1")))[0][0] and "b via= cands=" not in legend(rd("p1")), "(H1) a proven middle hop carries no hedge and no clause")
fol = lambda t: [b[0].get("follow_of") for b in bodies(t) if "follow_of" in b[0]]
check('via="declined"' in rd("h2c") and re.search(r'<b [^>]*n="relayWorkItem"', rd("h2a")) and fol(rd("h2a")) == [], "(H2) a declined call beside the proven one: relayWorkItem served, never followed")
check(re.search(r'<b [^>]*n="relayWorkItem"', rd("h2b")) and fol(rd("h2b")) == [], "(H2) an undefined call beside the proven one: never followed")
check('graph_ambiguous="1"' in rd("h3c") and re.search(r'<b [^>]*n="relay_transform"', rd("h3")) and fol(rd("h3")) == [] and not re.search(r'<b [^>]*n="scale_impl"', rd("h3")), "(H3) a binding-only call (amb=) is never followed")
check(re.search(r'<b [^>]*n="scale_and_store"', rd("h4")) and fol(rd("h4")) == [], "(H4) C *out stores count as statements: no follow")
check(re.search(r'<b [^>]*n="prime_then_fill"', rd("h4b")) and fol(rd("h4b")) == [], "(H4b) three *p stores + the call = 4 statement lines: no follow (pins the * rule alone)")
check(fol(rd("h5a")) == ["Widget.post_message"] and fol(rd("h5b")) == ["Widget.post_message_plain"], "(H5) documented and plain Python delegators both followed, follow_of=Owner.name: %r %r" % (fol(rd("h5a")), fol(rd("h5b"))))
check(re.search(r'<b [^>]*n="PanelHolder"', rd("h6")) and fol(rd("h6")) == [], "(H6) a class is never a wrapper")
check(fol(rd("h6b")) == ["ChildRunner.launch"], "(H5/F7) a super-override follow names its wrapper Owner.name: %r" % fol(rd("h6b")))
check(re.search(r'<b [^>]*n="computeScoreTotal"', rd("h7a")) and fol(rd("h7a")) == [] and fol(rd("h7b")) == [], "(H7) logic beside one call and a builtin pipeline are not delegators: %r %r" % (fol(rd("h7a")), fol(rd("h7b"))))
fb = [b for b in bodies(rd("h8")) if "follow_of" in b[0]]; fa = fb[0][0] if fb else {}
check(fa.get("follow_of") == "relayWorkItem" and fa.get("truncated") == "1" and re.fullmatch(r'1-\d+/\d+', fa.get("lines", "")) and fa.get("next", "").startswith("--expand=src/work.ts:") and len(fb[0][1].encode()) <= 4000, "(H8) the follow of a > 4000 B callee is cut and says so: %r" % {k: fa.get(k) for k in ("follow_of", "truncated", "lines", "next")})
h9 = rd("h9"); fc = re.search(r'<follow_cut ([^>]*)/>', h9)
check(len(fol(h9)) == 3 and fc and attrs(fc.group(1)) == {"n": "2", "next": "--expand=src/ship.ts:19:sealOrder2"}, "(H9) 3 follow bodies, then <follow_cut n=2 next=>: %r %r" % (fol(h9), fc.group(0) if fc else None))
check("follow_cut n= next=" in legend(h9) and "follow_cut n= next=" in legend(rd("h9f")), "(H9) the follow_cut reading rides, compact and full")
# FIX1 R1-R4: BODY-ON-ROUTE
routel = lambda t: (re.search(r'<bodies of="route".*?</bodies>', t, re.S) or re.search(r'$', t)).group(0)
r1 = rd("r1"); el = routel(r1); bs = bodies(el); rt = root(r1)
check(rt.get("reachable") == "0" and rt.get("hops") == "0" and re.search(r'<bridge [^>]*>', r1), "(R1) reachable=0 hops=0 and the bridge stay")
check([b[0].get("n") for b in bs] == ["post_message", "_process_messages_loop", "_dispatch_message", "_on_message"], "(R1) the route bodies in order: %r" % [b[0].get("n") for b in bs])
check(el.startswith('<bodies of="route" proven="0" shown="4" total="4" capped="0">'), "(R1) envelope proven=0 shown=4 total=4 capped=0")
hed = {b[0].get("n"): (b[0].get("via"), b[0].get("cands")) for b in bs}
check(hed.get("_process_messages_loop") == ("queue", "2") and hed.get("_on_message") == ("name-key", None) and hed.get("post_message") == (None, None) and hed.get("_dispatch_message") == (None, None), "(R1) each body carries its hop's hedge: %r" % hed)
check(all(is_source((b[0], b[1]), os.path.join(T, "route")) for b in bs) and "put_nowait" in el and "self._parent.post_message" in el, "(R1) CDATA = source text (the put, the bubble)")
check('n="on_event"' not in el, "(R1) never the to= row's body")
check("bodies of=route proven=0" in legend(r1) and "bodies of=route proven=0" in legend(rd("r1f")) and "b via= cands=" in legend(r1), "(R1) the of=route and hedge clauses ride, compact and full")
el2 = routel(rd("r2"))
check(el2.startswith('<bodies of="route" proven="0" shown="4" total="5" capped="1" next="--expand=pump.py:45:_trace_message">') and len(bodies(el2)) == 4, "(R2) a fifth route body is cut: capped=1, next= the first unshown")
b3 = [b[0].get("n") for b in bodies(routel(rd("r3")))]
check(b3 == ["press", "post_message", "_process_messages_loop"], "(R3) a 4-hop bridge prints rows 0..2 only: %r" % b3)
g5 = (re.search(r'<graph_verb .*?</graph_verb>', rd("r5"), re.S) or re.search(r'$', rd("r5"))).group(0)
check(g5 != "" and 'reachable="0"' in g5 and routel(g5) == "" and "bodies of=route" not in legend(rd("r5")), "(R5) a --for graph-verb path block prints no route bodies (the gain gate)")
check(routel(rd("r1.off")) == "" and "bodies of=route" not in legend(rd("r1.off")), "(R4) RIPWIRE_NO_HOP_BODY=1: no route element, no clause")
# FIX2 R6-R9 (lane path-hop-body-fix1, review rv-phbf1 G1/G2/G3/S1/S4: each arm is RED on its review mutant)
rb = lambda f: {b[0].get("n"): b[0] for b in bodies(routel(rd(f)))}
b6 = rb("r6")
check(b6.get("dispatch_message", {}).get("via") == "name" and b6.get("dispatch_message", {}).get("cands") == "2", "(R6) a by-name edge row inside the bridge: its route body carries via=name cands=2, never bare (the edge-row hedge): %r" % b6.get("dispatch_message"))
b7 = bodies(routel(rd("r7")))
check(len(b7) == 4 and all(b[0].get("truncated") == "1" and re.fullmatch(r'1-\d+/\d+', b[0].get("lines", "")) and b[0].get("next", "").startswith("--expand=pump.py:") and len(b[1].encode()) <= 4000 for b in b7) and routel(rd("r7")).startswith('<bodies of="route" proven="0" shown="4" total="4" capped="1">'), "(R7) a route body over 4000 B is cut: truncated=1 lines= next=, <= 4000 B each, capped=1")
b8 = bodies(routel(rd("r8"))); n8 = [b[0].get("n") for b in b8]
check(n8 == ["post_message", "_process_messages_loop", "_dispatch_message", "_on_message"] and len(set(n8)) == len(n8), "(R8) a reader that is also a bridge row prints once and the true reader _on_message is still shown: %r" % n8)
b9 = rb("r9")
check(b9.get("run_fast", {}).get("via") == "slot" and b9.get("run_fast", {}).get("slot_callers") == "1" and b9.get("run_fast", {}).get("slot_fns") == "3", "(R9) a slot-crossing route body carries slot_fns= beside slot_callers= (S1): %r" % b9.get("run_fast"))
check("proven call from the row above" in legend(rd("r9")) and "proven call from the row above" in legend(rd("r9f")), "(R9) the bare-b reading rides beside a hedged route, compact and full (S4)")
# R10 (CR pre-pass 41): defs-lookup's <alts> must not list a definition the route body printed (pathAltsOf's bodyIds)
def alts_p(t): return re.findall(r'<d p="([^"]*)"', (re.search(r'<alts side="from" of="post_message">.*?</alts>', t, re.S) or re.search(r'$', t)).group(0))
r10 = rd("r10"); printed10 = {(b[0].get("p"), b[0].get("l")) for b in bodies(routel(r10))}
check(("pump.py", "10") in printed10 and root(r10).get("from_defs") == "2", "(R10pre) the route body prints pump.py:10 post_message and the endpoint binds 2 definitions")
check(alts_p(r10) == ["other.py:2"], "(R10) <alts side=from> lists the other class's post_message only, never the one a route body printed: %r" % alts_p(r10))
check(all(a.split(":")[0] + ":" + a.split(":")[1] not in {p + ":" + l for p, l in printed10} for a in alts_p(r10)), "(R10) no <alts> row repeats a printed <b>")
if shutil.which("xmllint"):   # CR 4408459933: the shell X2 arm below skips cleanly without xmllint; so does this one
    for f in ("h1", "r1", "r2", "r3"):
        check(subprocess.run(["xmllint", "--noout", os.path.join(T, f)], capture_output=True).returncode == 0, "(X2) %s well-formed" % f)
else:
    print("  SKIP  (X2) xmllint absent")
# X3
for f in ("p1", "p1f", "p3f", "p4", "f1", "f1f", "h1f", "r1f", "h9f"):
    check(all("--" not in c for c in re.findall(r'<!--(.*?)-->', rd(f), re.S)), "(X3) %s: no -- inside a legend comment" % f)
sys.exit(1 if fails else 0)
PY
python3 "$TMP/chk.py" "$TMP" "$BIN" "$ROOT" || fail=1

# P7: MCP path_between twin
python3 - "$BIN" "$ROOT/$WEB" "$TMP" <<'PY' || fail=1
import json, re, subprocess, sys
binp, web, tmp = sys.argv[1], sys.argv[2], sys.argv[3]
cases = [("fetch", "compose", "p1"), ("stepOne", "stepFour", "p2"), ("bigEntry", "bigSink", "p4"), ("stepOne", "stepFive", "p3")]
reqs = [{"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "g", "version": "1"}}}]
for i, (a, b, _) in enumerate(cases):
    reqs.append({"jsonrpc": "2.0", "id": i + 1, "method": "tools/call", "params": {"name": "path_between", "arguments": {"path": web, "from": a, "to": b}}})
p = subprocess.run([binp, "--mcp", "--mcp-legend=inline"], input="".join(json.dumps(r) + "\n" for r in reqs), capture_output=True, text=True, timeout=120, cwd=web)
resp = {}
for line in p.stdout.splitlines():
    try: o = json.loads(line)
    except ValueError: continue
    if isinstance(o.get("id"), int) and o["id"] > 0:
        resp[o["id"]] = "".join(c.get("text", "") for c in o.get("result", {}).get("content", []))
bad = 0
el = lambda t: (re.search(r'<bodies of="hops".*?</bodies>', t, re.S) or re.search(r'$', t)).group(0)
for i, (a, b, f) in enumerate(cases):
    cli = open(tmp + "/" + f).read(); mcp = resp.get(i + 1, "")
    if f in ("p2", "p3"):
        m = re.search(r'<path [^>]*next="([^"]*)"', mcp); good = bool(m) and m.group(1) == "--expand=src/chain.ts:5:stepTwo" and el(mcp) == ""
    else:
        good = el(mcp) != "" and el(mcp) == el(cli)
    print("  %s  (P7) MCP path_between %s,%s: %s" % ("PASS" if good else "FAIL", a, b, "the CLI's element" if f not in ("p2", "p3") else "the past-the-gate next="))
    bad += 0 if good else 1
sys.exit(1 if bad else 0)
PY

# R4: MCP path_between prints the CLI's route element byte for byte
python3 - "$BIN" "$TMP/route" "$TMP" <<'PY' || fail=1
import json, re, subprocess, sys
binp, d, tmp = sys.argv[1], sys.argv[2], sys.argv[3]
reqs = [{"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "g", "version": "1"}}},
        {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "path_between", "arguments": {"path": d, "from": "post_message", "to": "on_*"}}}]
p = subprocess.run([binp, "--mcp", "--mcp-legend=inline"], input="".join(json.dumps(r) + "\n" for r in reqs), capture_output=True, text=True, timeout=120, cwd=d)
mcp = ""
for line in p.stdout.splitlines():
    try: o = json.loads(line)
    except ValueError: continue
    if o.get("id") == 1: mcp = "".join(c.get("text", "") for c in o.get("result", {}).get("content", []))
el = lambda t: (re.search(r'<bodies of="route".*?</bodies>', t, re.S) or re.search(r'$', t)).group(0)
good = el(mcp) != "" and el(mcp) == el(open(tmp + "/r1").read())
print("  %s  (R4) MCP path_between post_message,on_*: the CLI's route element" % ("PASS" if good else "FAIL"))
sys.exit(0 if good else 1)
PY

# R10m: MCP path_between lists the same <alts> (the route body's definition is not listed again)
python3 - "$BIN" "$TMP/routealt" "$TMP" <<'PY' || fail=1
import json, re, subprocess, sys
binp, d, tmp = sys.argv[1], sys.argv[2], sys.argv[3]
reqs = [{"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "g", "version": "1"}}},
        {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "path_between", "arguments": {"path": d, "from": "post_message", "to": "on_*"}}}]
p = subprocess.run([binp, "--mcp", "--mcp-legend=inline"], input="".join(json.dumps(r) + "\n" for r in reqs), capture_output=True, text=True, timeout=120, cwd=d)
mcp = ""
for line in p.stdout.splitlines():
    try: o = json.loads(line)
    except ValueError: continue
    if o.get("id") == 1: mcp = "".join(c.get("text", "") for c in o.get("result", {}).get("content", []))
al = lambda t: (re.search(r'<alts side="from".*?</alts>', t, re.S) or re.search(r'$', t)).group(0)
good = '<alts side="from" of="post_message">' in mcp and al(mcp) == al(open(tmp + "/r10").read()) and 'p="pump.py:10"' not in al(mcp) and '<b t="fn" l="10" p="pump.py" n="post_message"' in mcp
print("  %s  (R10m) MCP path_between post_message,on_*: the CLI's <alts>, without the route body's definition" % ("PASS" if good else "FAIL"))
sys.exit(0 if good else 1)
PY

# X1 determinism, X2 well-formed
run "$WEB" --path=fetch,compose >"$TMP/x1"; run "$FOL" --for="$T_FOLLOW" >"$TMP/x2"
if cmp -s "$TMP/p1" "$TMP/x1" && cmp -s "$TMP/f1" "$TMP/x2"; then echo "  PASS  (X1) deterministic"; else echo "  FAIL  (X1) two runs differ"; fail=1; fi
if command -v xmllint >/dev/null 2>&1; then
    for f in p1 p2 p3 p4 p1f f1 f1f p9a p9b; do
        if xmllint --noout "$TMP/$f" 2>/dev/null; then echo "  PASS  (X2) $f well-formed"; else echo "  FAIL  (X2) $f not well-formed"; fail=1; fi
    done
else
    echo "  SKIP  (X2) xmllint absent"
fi

# I: optional base-binary identity of the A/B handle
if [ -n "${RIPWIRE_BASE_BIN:-}" ] && [ -x "${RIPWIRE_BASE_BIN}" ]; then
    i=0
    while IFS='|' read -r d a; do
        i=$(( i + 1 ))
        ( cd "$d" || exit 1; "$RIPWIRE_BASE_BIN" "$ROOT/$d" --no-cache "$a" 2>/dev/null ) | sed 's/ at="[^"]*"//' >"$TMP/i.base"
        ( cd "$d" || exit 1; RIPWIRE_NO_HOP_BODY=1 "$BIN" "$ROOT/$d" --no-cache "$a" 2>/dev/null ) | sed 's/ at="[^"]*"//' >"$TMP/i.head"
        if [ -s "$TMP/i.base" ] && cmp -s "$TMP/i.base" "$TMP/i.head"; then echo "  PASS  (I$i) RIPWIRE_NO_HOP_BODY=1 == base: $d $a"; else echo "  FAIL  (I$i) differs from base: $d $a"; fail=1; fi
    done <<ARGV
$WEB|--path=fetch,compose
$WEB|--path=stepOne,stepFive
$WEB|--path=bigEntry,bigSink
$FOL|--for=$T_FOLLOW
$WEB|--for=$T_WEB
ARGV
else
    echo "  SKIP  (I) RIPWIRE_BASE_BIN unset or not executable — base-binary identity not run here"
fi
exit $fail

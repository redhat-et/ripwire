#!/usr/bin/env bash
# forbodyfoldcheck.sh — the BODY-TAIL FOLD of a compact-route --for answer (lane body-fold, train 31; src/forfold.h).
#
# THE CONTRACT THIS PINS (arms tagged [P] are RED on the pre-change binary fc0745a0; [G] arms are twins and near-miss
# negatives that hold on both binaries and must keep holding — PROCESS rule 4, no gate erosion):
#
#   TRIGGER  CLI --for (XML, compact and full legends) on the compact route (root bundle="compact"), in the DEFAULT regime.
#            No fold: --signatures-only, --json, --auto-bodies, --detail=N, an explicit --token-budget=N, the name-exact route,
#            RIPWIRE_NO_BODY_FOLD=1 (the A/B handle) — each byte-identical to the fold-off answer. --max-tokens=N is not read by
#            this answer (its notice says so): the fold rides and the answer is the flagless one byte for byte (FIX1 B1).
#   WHAT     after the unchanged answer: <fold kind="bodies" budget_bytes="4000" served=K total=T>, T = the first three ranked
#            <d> rows not already bodied (the body slot's owner never twice) that have a body. In rank order each body is whole
#            or not served: a body whose element fits what is left of 4000 B is a <b t= l= p= n=> in the --expand shape WITHOUT
#            sibs=/inc= and WITHOUT <calls>; one that does not is <skip p= n= l= bytes= next="--expand=P:L:N"/> and the walk goes
#            on (a later, smaller body still rides).
#   C3       the <sigs> continuation, when a body was skipped: next= becomes the first skip's next=, and the signatures-only
#            re-call the fold-off answer carried as <sigs next=> moves to sigs_next= (its reading renamed with it); a fold that
#            skipped nothing leaves the <sigs> tag as it was.
#   PRICE    est_tokens prices the fold (bodies at the body rate).
#   RIDERS   (R1) a compact <hops> row whose <calls> listing is cut (16 of 20 callees) carries next="--callees=…" (rule 5:
#            the per-hop cap was disclosed but not recoverable — forbudget-soft N3); (R2) the --for --limit=N file page
#            legend says n= counts this task's positive-score symbols, not the expand flag's sibs_total= file count.
#
# Arms (colour on fc0745a0 in brackets):
#   S1 [P] V1 MEMBER SLICE: the 4.9 KB JobScheduler class (over what is left) rides as <slice p= n= l= members= of=>: its
#          constructor first unless a ranked row already served it (never twice), the members whose name or body holds a
#          question word (drain), never one without (counter_00), source order; then the class's own <skip bytes= next=>
#   S2 [G] slice members whole (their definitions' source text), the fold <= 4000 B, no body twice
#   S3 [P] of= counts the class's direct members only (a function nested in a member is inside that member's text)
#   S4 [G] (FIX1 N4, kills mutant M2) a TS class whose constructor is NOT a ranked row and holds no question word: the slice still
#          serves the constructor first (by name), then lineOfDay (a question word in its body), never member00
#   S5 [P] (FIX1 N3) a Go struct whose methods all carry the receiver (s *Scheduler): a question naming the scheduler slices only the
#          members whose name or body past the signature holds a question word — never Counter01 (r5, not a fold candidate), never all of them (members < of=)
#   N1 [P] (FIX1 N2) each text once: no fold body (top-level or slice member) lies inside another fold body — a class and its own
#          method both ranked (nest/lane.py Lane + schedule_lane) ride as the class alone, served= still counting both
#   L1 [P] (FIX1 B2) the fold's legend coverage, both dialects: the legend defines b t= n= p= l= and every attribute of the
#          <fold>, <slice> and <skip> elements the answer carries
#   F1 [P] the router question: a <fold> holds SmartRouter's whole body (router.match.bind(router), UnsupportedPathError)
#   F2 [P] the respond question: respond's body served, the 7.5 KB renderResponseBodyPage SKIPPED with bytes= > 4000 and
#          next=--expand=lib/render.js:6:renderResponseBodyPage, and Application (r3) still served after the skip;
#          the skip's next= pasted (shlex) serves that body whole
#   F3 [P] C3: on the respond answer <sigs next=> equals the first skip's next=; on a src/ answer whose fold-off <sigs> carried
#          next=, the fold answer carries it as sigs_next= byte for byte and the legend reads [sigs sigs_next=: …]
#   F4 [G] whole-or-none: each fold <b> CDATA equals the --expand=P:L:N body CDATA byte for byte; served <b> elements sum
#          <= 4000 B; no sibs=/inc=/<calls>/<c> inside the fold; served= counts the <b>, served + skips = total
#   F5 [G] prefix identity: the answer minus the fold, its legend clause and the C3 pair, est_tokens masked, equals the
#          RIPWIRE_NO_BODY_FOLD=1 answer — both legends, three questions (checklist 23); member names (mem=, its clause) masked on
#          both sides (train 32, by design: an owner the fold carries gets none); F5n the same unmasked with RIPWIRE_NO_MEMBER_NAMES=1, on all six
#   F6 [P] est_tokens(fold) - est_tokens(off) >= 0.9 x the served body bytes / 3.80 (the body rate)
#   F7 [P] the fold clause rides in both legends when the fold does, and never when it does not
#   F8 [G] no fold, byte-identical to RIPWIRE_NO_BODY_FOLD=1: --signatures-only, --json, --auto-bodies, --detail=1,
#          --token-budget=3000, the name-exact route (--for=SmartRouter)
#   F8m [P] (FIX1 B1) --max-tokens=3000 is inert on this answer, as its notice says: byte-identical to the flagless answer
#   F9 [G] the body slot's owner (bodies="1" reason="owner") is never repeated in the fold
#   R1 [P] the dispatcher question: <h n=dispatchRequest><calls total=20 shown=16 capped=1 next="--callees=src/dispatch.ts:dispatchRequest">
#          and the pasted next= lists all 20 callees;  R1b [G] an uncut <calls> carries no next=;  R1c [P] its legend clause
#          rides exactly when a ranked hop's listing is cut (present-only: an answer without one keeps its bytes);
#          R1d [P] under a file name holding a space the next= is quoted (nextFlag) and pastes as one argument
#   R2 [P] the file page legend (full and compact) carries the n= vs sibs_total= reading
#   X1 [G] determinism   X2 [G] xmllint well-formed   X3 [G] no "--" inside a legend comment
#   I0-I* [optional, RIPWIRE_BASE_BIN=<pre-change binary>] byte identity where the fold must not fire, and RIPWIRE_NO_BODY_FOLD=1
#          == the base binary on the fold questions modulo the R1 rider
#
# Usage:  bash test/forbodyfoldcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/forbodyfoldcheck.sh
# BIN is $1, else RIPWIRE_BIN, else build/ripwire; the first output line names the binary used.
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_BODY_FOLD RIPWIRE_NO_BODY_SLOT RIPWIRE_NO_OWNER_HOP RIPWIRE_NO_MEMBER_NAMES
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "forbodyfoldcheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; return 0; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
cd "$ROOT"
FIX="test/forbodyfoldfix/web"     # the TS/JS answers (router, response, slot, hops)
FIXPY="test/forbodyfoldfix/py"    # the Python member-slice answers (a root of its own: its words would re-rank the web answers)
[ -d "$FIX/src" ] && [ -d "$FIXPY" ] || { echo "fixture test/forbodyfoldfix missing"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

T_ROUTER="How does the app choose its router, and how does SmartRouter work?"
T_RESP="How does the application send the response body to the client?"
T_SLOT="How does the application respond to the client?"
T_HOPS="How is a request dispatched?"
T_SRC="How does the for lens fold the bodies of its top ranked rows?"
T_SLICE="How are jobs scheduled onto workers?"

cat > "$TMP/chk.py" <<'PY'
import html, re, shlex, subprocess, sys
cmd, args = sys.argv[1], sys.argv[2:]
def load(p):
    return open(p, "rb").read().decode("utf-8", "replace")
def attrs(s):
    return dict((k, html.unescape(v)) for k, v in re.findall(r'(\w+)="([^"]*)"', s))
def root(t):
    m = re.search(r'<ctx ([^>]*)>', t)
    return attrs(m.group(1)) if m else {}
def sigs_tag(t):
    m = re.search(r'<sigs\b([^>]*)>', t)
    return attrs(m.group(1)) if m else {}
def fold(t):
    m = re.search(r'<fold ([^>]*)>(.*?)</fold>', t, re.S)
    return (attrs(m.group(1)), m.group(2), m.group(0)) if m else (None, "", "")
def bodies(x):
    out = []
    for m in re.finditer(r'<b ([^>]*)>(.*?)</b>', x, re.S):
        cd = "".join(re.findall(r'<!\[CDATA\[(.*?)\]\]>', m.group(2), re.S))
        out.append((attrs(m.group(1)), cd, m.group(0)))
    return out
def skips(x):
    return [attrs(m.group(1)) for m in re.finditer(r'<skip ([^>]*)/>', x)]
def legend(t):
    return " ".join(re.findall(r'<!--(.*?)-->', t, re.S))
FOLD_CLAUSE = re.compile(r'; fold kind=bodies:.*?sigs_next= the signatures-only re-call', re.S)
def strip_fold(t):
    """the answer minus everything the fold may add: the element, its legend clause, the C3 pair, est_tokens"""
    t = re.sub(r'<fold .*?</fold>', '', t, flags=re.S)
    t = FOLD_CLAUSE.sub('', t)
    m = re.search(r'<sigs\b[^>]*>', t)
    if m:   # the C3 pair (a skip's --expand as next=, the re-call as sigs_next=) rides only when a body was skipped
        tag = m.group(0)
        tag2 = re.sub(r' next="--expand=[^"]*"', '', tag).replace(' sigs_next="', ' next="')
        t = t[:m.start()] + tag2 + t[m.end():]
    t = t.replace('[sigs sigs_next=: one', '[sigs next=: one')
    return re.sub(r' est_tokens="\d+"', '', t)
# member-names (train 32; rule 4, by design): the fold now also decides which owner rows carry mem= (an owner the fold serves, or
# slices, carries none — formembernamescheck (C1)/(C2) owns that), so the fold-off twin carries mem= the fold answer does not.
# (F5) reads both answers with the names masked; (F5n) keeps the exact pre-names premise with RIPWIRE_NO_MEMBER_NAMES=1 on both sides.
MEM_CLAUSE = re.compile(r'; (d mem=|mem= on an owner d row:)[^;]*?mem_more= (names cut|the member names not listed)')
def strip_mem(t):
    return MEM_CLAUSE.sub('', re.sub(r' mem="[^"]*"( mem_more="\d+")?', '', t))
def fail(msg):
    print(msg); sys.exit(1)
if cmd == "has_body":          # FILE NAME NEEDLE... : the fold serves NAME's body holding every NEEDLE
    t = load(args[0]); a, x, _ = fold(t)
    if a is None: fail("no <fold> element")
    for ba, cd, _ in bodies(x):
        if ba.get("n") == args[1]:
            miss = [n for n in args[2:] if n not in cd]
            if miss: fail(f"{args[1]}'s fold body lacks {miss}")
            sys.exit(0)
    fail(f"no fold body named {args[1]}: {[b[0].get('n') for b in bodies(x)]}")
elif cmd == "skip_then_serve":  # FILE SKIPNAME LATERNAME
    t = load(args[0]); a, x, _ = fold(t)
    if a is None: fail("no <fold>")
    sk = [s for s in skips(x) if s.get("n") == args[1]]
    if not sk: fail(f"{args[1]} not skipped: {skips(x)}")
    s = sk[0]
    if int(s.get("bytes", "0")) <= 4000: fail(f"skip bytes={s.get('bytes')} not over the budget")
    if s.get("next") != f"--expand={s['p']}:{s['l']}:{s['n']}": fail(f"skip next= {s.get('next')!r}")
    if args[2] not in [b[0].get("n") for b in bodies(x)]: fail(f"{args[2]} not served after the skip")
    print(s["next"])
elif cmd == "c3_skip":           # FILE : sigs next= == the first skip's next=
    t = load(args[0]); a, x, _ = fold(t); sk = skips(x)
    if not sk: fail("no skip to lead the continuation")
    n = sigs_tag(t).get("next")
    if n != sk[0]["next"]: fail(f"sigs next={n!r}, first skip next={sk[0]['next']!r}")
elif cmd == "c3_pair":           # FOLD OFF : off's <sigs next=> == fold's sigs_next=; legend renamed
    t, o = load(args[0]), load(args[1])
    on, off = sigs_tag(t), sigs_tag(o)
    a, x, _ = fold(t)
    if a is None: fail("no fold on the src answer")
    if not skips(x):   # every candidate served: the <sigs> tag is the fold-off answer's, untouched
        tt, ot = re.search(r'<sigs\b[^>]*>', t), re.search(r'<sigs\b[^>]*>', o)
        if not tt or not ot or tt.group(0) != ot.group(0): fail("no skip, yet the <sigs> tag differs from the fold-off answer's")
        print("no skip: <sigs> untouched"); sys.exit(0)
    if "next" not in off: print("SKIPPED: the fold-off <sigs> carries no next= here"); sys.exit(0)
    if on.get("sigs_next") != off["next"]: fail(f"sigs_next={on.get('sigs_next')!r} vs off next={off['next']!r}")
    if on.get("next") != skips(x)[0]["next"]: fail(f"sigs next={on.get('next')!r} is not the first skip's")
    if "[sigs sigs_next=: one call serving all total= rows uncut]" not in legend(t): fail("legend not renamed to sigs_next=")
    if "[sigs next=: one call serving" in legend(t): fail("legend still reads [sigs next=: …] beside sigs_next=")
elif cmd == "whole":             # FILE BIN DIR : every fold body == its --expand CDATA; budget; no sibs/inc/calls; counts
    t = load(args[0]); a, x, _ = fold(t)
    if a is None: fail("no <fold>")
    bs, sk = bodies(x), skips(x)
    if a.get("kind") != "bodies" or a.get("budget_bytes") != "4000": fail(f"fold attrs {a}")
    top = bodies(re.sub(r'<slice .*?</slice>', '', x, flags=re.S))
    if int(a["served"]) < len(top) or int(a["served"]) + len(sk) != int(a["total"]): fail(f"served={a['served']} bodies={len(top)} skips={len(sk)} total={a['total']}")
    ids = [(b[0].get("p"), b[0].get("l")) for b in bs]
    if len(ids) != len(set(ids)): fail(f"a body rides twice in the fold: {ids}")
    if sum(len(b[2].encode()) for b in bs) > 4000: fail("served bodies exceed 4000 B")
    if re.search(r'<calls\b|<c |sibs=|inc=', x): fail("callee rows or file context inside the fold")
    # whole: each CDATA is the definition's own source bytes, and for a ranked row (its <d> carries e=, the def's last line) every
    # line of it — never a head-cut fragment (no truncated=, no lines=)
    ends = {(da.get("p"), da.get("l")): da.get("e") for da in (attrs(m.group(1)) for m in re.finditer(r'<d ([^>]*)>', t))}
    for ba, cd, _ in bs:
        if "truncated" in ba or "lines" in ba: fail(f"{ba['p']}:{ba['n']} is a cut body")
        src = open(args[2] + "/" + ba["p"], encoding="utf-8").read()
        k = src.find(cd)
        if k < 0: fail(f"{ba['p']}:{ba['l']}:{ba['n']} is not its definition's source text")
        first = src[:k].count("\n") + 1; last = first + cd.count("\n")
        e = ends.get((ba["p"], ba["l"]))
        if e and int(e) != last: fail(f"{ba['p']}:{ba['l']}:{ba['n']} ends at line {last}, its row says e={e}")
elif cmd == "slice":             # FILE CLASS CTOR MATCH NOTMATCH : the class's member slice, then its skip
    t = load(args[0]); a, x, _ = fold(t)
    if a is None: fail("no <fold>")
    m = re.search(r'<slice ([^>]*)>(.*?)</slice>', x, re.S)
    if not m: fail("no <slice>")
    sa = attrs(m.group(1)); names = [b[0].get("n") for b in bodies(m.group(2))]
    if sa.get("n") != args[1]: fail(f"slice of {sa.get('n')}")
    topn = [b[0].get("n") for b in bodies(re.sub(r'<slice .*?</slice>', '', x, flags=re.S))]
    if args[2] in topn:
        if args[2] in names: fail(f"the constructor {args[2]} rides twice (a ranked row and a slice member)")
    elif not names or names[0] != args[2]: fail(f"the constructor {args[2]} is not first: {names}")
    if args[3] not in names: fail(f"{args[3]} (names a question word) not in the slice: {names}")
    if args[4] in names: fail(f"{args[4]} (no question word) is in the slice")
    if int(sa["members"]) != len(names) or int(sa["of"]) <= len(names): fail(f"members={sa['members']} of={sa['of']} for {len(names)} served")
    sk = [s for s in skips(x) if s.get("n") == args[1]]
    if not sk or int(sk[0]["bytes"]) <= 4000: fail(f"the class is not skipped whole after its slice: {sk}")
    lines = [int(b[0]["l"]) for b in bodies(m.group(2))]
    if lines != sorted(lines): fail(f"slice members not in source order: {lines}")
elif cmd == "prefix":            # FOLD OFF : strip_fold(fold) == off (est_tokens masked)
    t, o = load(args[0]), load(args[1])
    if fold(t)[0] is None: fail("no fold to strip")
    if strip_mem(strip_fold(t)) != strip_mem(re.sub(r' est_tokens="\d+"', '', o)): fail("the answer before the fold is not the fold-off answer")
elif cmd == "prefix_raw":        # FOLD OFF : the pre-names (F5) exactly, for answers run with RIPWIRE_NO_MEMBER_NAMES=1 (F5n)
    t, o = load(args[0]), load(args[1])
    if fold(t)[0] is None: fail("no fold to strip")
    if re.search(r' mem="', t + o): fail("an answer carries mem= although RIPWIRE_NO_MEMBER_NAMES=1")
    if strip_fold(t) != re.sub(r' est_tokens="\d+"', '', o): fail("the answer before the fold is not the fold-off answer")
elif cmd == "est":               # FOLD OFF
    t, o = load(args[0]), load(args[1]); a, x, _ = fold(t)
    if a is None: fail("no <fold> to price")
    served = sum(len(b[2].encode()) for b in bodies(x))
    d = int(root(t)["est_tokens"]) - int(root(o)["est_tokens"])
    if d < 0.9 * served / 3.80: fail(f"est_tokens grew {d} for {served} B of bodies")
elif cmd == "legend":            # FILE yes|no
    has = "; fold kind=bodies:" in legend(load(args[0]))
    if (args[1] == "yes") != has: fail(f"fold clause present={has}, expected {args[1]}")
elif cmd == "nofold":
    if fold(load(args[0]))[0] is not None or "<fold" in load(args[0]): fail("a fold rode")
elif cmd == "slot":              # FILE : the slot owner's body is not repeated in the fold
    t = load(args[0])
    if root(t).get("reason") != "owner": fail(f"no owner slot here: reason={root(t).get('reason')}")
    m = re.search(r'<bodies [^>]*>(.*?)</bodies>', t, re.S)
    own = {(b[0].get("p"), b[0].get("l")) for b in bodies(m.group(1))} if m else set()
    a, x, _ = fold(t)
    if a is None: fail("no fold beside the slot")
    rep = own & {(b[0].get("p"), b[0].get("l")) for b in bodies(x)}
    if rep: fail(f"the slot owner is repeated in the fold: {rep}")
elif cmd == "hopnext":           # FILE BIN DIR NAME TOTAL
    t = load(args[0])
    m = re.search(r'<h [^>]*n="' + re.escape(args[3]) + r'"[^>]*><calls ([^>]*)>', t)
    if not m: fail(f"no hop row {args[3]}")
    a = attrs(m.group(1))
    if a.get("capped") != "1" or a.get("total") != args[4]: fail(f"calls {a}")
    if not a.get("next", "").startswith("--callees="): fail(f"no --callees next= on the cut listing: {a}")
    out = subprocess.run([args[1], args[2], "--no-cache"] + shlex.split(a["next"]), capture_output=True).stdout.decode()
    n = len(set(re.findall(r'<c [^>]*n="(stage\d+)"', out)) | set(re.findall(r'n="(stage\d+)"', out)))
    if n < int(args[4]): fail(f"the pasted next= lists {n} of {args[4]} callees")
    for mm in re.finditer(r'<calls ([^>]*)>', t):
        ca = attrs(mm.group(1))
        if ca.get("capped") != "1" and "next" in ca: fail(f"an uncut <calls> carries next=: {ca}")
elif cmd == "nested":           # FILE DIR : no fold body's source text lies inside another fold body's (each text once)
    t = load(args[0]); a, x, _ = fold(t)
    if a is None: fail("no <fold>")
    spans = []
    for ba, cd, _ in bodies(x):
        src = open(args[1] + "/" + ba["p"], encoding="utf-8").read(); k = src.find(cd)
        if k < 0: fail(f"{ba['p']}:{ba['n']} is not its source text")
        spans.append((ba["p"], k, k + len(cd), ba["n"]))
    for i, (p1, s1, e1, n1) in enumerate(spans):
        for j, (p2, s2, e2, n2) in enumerate(spans):
            if i != j and p1 == p2 and s2 <= s1 and e1 <= e2: fail(f"{n1} rides inside {n2} as well as on its own")
elif cmd == "cover":            # FILE : the legend defines what the fold carries
    t = load(args[0]); a, x, el = fold(t)
    if a is None: fail("no <fold>")
    leg = legend(t)
    if not re.search(r'(?<![\w])b t= n= p= l=', leg): fail("the legend does not define b t= n= p= l=")
    for name in ("fold", "slice", "skip"):
        for m in re.finditer(r'<' + name + r' ([^>]*)>', el):
            if not re.search(r'(?<![\w])' + name + r'\b', leg): fail(f"<{name}> is not named by the legend")
            for k in attrs(m.group(1)):
                if not re.search(r'(?<![\w])' + k + '=', leg): fail(f"<{name} {k}=> is not defined by the legend")
elif cmd == "noword":           # FILE CLASS DROP : CLASS is skipped and DROP (no question word past its signature) is in no slice of it
    t = load(args[0]); a, x, _ = fold(t)
    if a is None: fail("no <fold>")
    if not [s for s in skips(x) if s.get("n") == args[0 + 1]]: fail(f"{args[1]} is not skipped: the premise (a class too big) is gone")
    for m in re.finditer(r'<slice ([^>]*)>(.*?)</slice>', x, re.S):
        sa = attrs(m.group(1)); names = [b[0].get("n") for b in bodies(m.group(2))]
        if sa.get("n") == args[1] and args[2] in names: fail(f"{args[2]} (no question word past its signature) is in the slice: members={sa.get('members')} of={sa.get('of')}")
        if sa.get("n") == args[1] and int(sa["members"]) >= int(sa["of"]): fail(f"members={sa['members']} of={sa['of']}: every member matched")
elif cmd == "unranked":         # FILE NAME : NAME is not one of the first three ranked <d> rows (the premise of S4)
    names = [attrs(m.group(1)).get("n") for m in re.finditer(r'<d ([^>]*)>', load(args[0]))][:3]
    if args[1] in names: fail(f"{args[1]} is a top-3 ranked row here: {names}")
elif cmd == "pagelegend":
    if "sibs_total=" not in legend(load(args[0])): fail("the file page legend lacks the n= vs sibs_total= reading")
elif cmd == "nodash":
    for c in re.findall(r'<!--(.*?)-->', load(args[0]), re.S):
        if "--" in c: fail("a legend comment holds '--'")
else:
    fail("unknown check " + cmd)
PY
chk(){ python3 "$TMP/chk.py" "$@"; }
run(){ local out="$1"; shift; "$BIN" "${ROOTDIR:-$FIX}" --no-cache "$@" >"$out" 2>"$out.err"; }
off(){ local out="$1"; shift; RIPWIRE_NO_BODY_FOLD=1 "$BIN" "${ROOTDIR:-$FIX}" --no-cache "$@" >"$out" 2>"$out.err"; }

run "$TMP/router" --for="$T_ROUTER";            off "$TMP/router.off" --for="$T_ROUTER"
run "$TMP/resp"   --for="$T_RESP";              off "$TMP/resp.off"   --for="$T_RESP"
run "$TMP/respf"  --for="$T_RESP" --legend=full; off "$TMP/respf.off" --for="$T_RESP" --legend=full
run "$TMP/slot"   --for="$T_SLOT";              off "$TMP/slot.off"   --for="$T_SLOT"
run "$TMP/hops"   --for="$T_HOPS"
ROOTDIR="$FIXPY" run "$TMP/slice" --for="$T_SLICE"; ROOTDIR="$FIXPY" off "$TMP/slice.off" --for="$T_SLICE"
FIXCTOR="test/forbodyfoldfix/ctor"; FIXGO="test/forbodyfoldfix/go"; FIXNEST="test/forbodyfoldfix/nest"   # FIX1: one root each
T_CTOR="How are the ledger totals reconciled?"
T_GO="what state fields does the scheduler struct keep and what are the counters"
T_NEST="How does a lane schedule its jobs?"
ROOTDIR="$FIXCTOR" run "$TMP/ctor" --for="$T_CTOR"
ROOTDIR="$FIXGO"   run "$TMP/go"   --for="$T_GO"
ROOTDIR="$FIXNEST" run "$TMP/nest" --for="$T_NEST"

# F1
if r=$( chk has_body "$TMP/router" SmartRouter "router.match.bind(router)" "UnsupportedPathError" ); then ok "(F1) the router question folds SmartRouter's whole body"; else no "(F1) $r"; fi
# S1 (V1 member slice)
if r=$( chk slice "$TMP/slice" JobScheduler __init__ drain counter_00 ); then ok "(S1) the over-budget class is served as a member slice (constructor first, the question-word members, source order) and skipped whole"; else no "(S1) $r"; fi
if r=$( chk whole "$TMP/slice" "$BIN" "$FIXPY" ); then ok "(S2) slice members whole, the fold <= 4000 B, no body twice"; else no "(S2) $r"; fi
if grep -q '<slice p="scheduler.py" n="JobScheduler" l="1" members="[0-9]*" of="49">' "$TMP/slice"; then ok "(S3) of= counts the class's 49 direct members: hand_off, nested in drain, is not one"; else no "(S3) of= is not 49 (a nested function counted as a member?)"; fi
# S4 (N4): the constructor by name, not by rank
if r=$( chk unranked "$TMP/ctor" constructor ) && r=$( chk slice "$TMP/ctor" LedgerBook constructor lineOfDay member00 ); then
    ok "(S4) an unranked constructor with no question word still leads LedgerBook's slice (by name), then lineOfDay; never member00"
else no "(S4) $r"; fi
# S5 (N3): the receiver and parameter names are the signature's, not the body's
if r=$( chk noword "$TMP/go" Scheduler Counter01 ); then ok "(S5) the Go receiver (s *Scheduler) no longer makes every method a question-word member"; else no "(S5) $r"; fi
# N1 (N2): each text once
for q in router resp slot slice ctor go nest; do
    d="$FIX"; case $q in slice) d="$FIXPY";; ctor) d="$FIXCTOR";; go) d="$FIXGO";; nest) d="$FIXNEST";; esac
    if r=$( chk nested "$TMP/$q" "$d" ); then ok "(N1) $q: no fold body rides inside another"; else no "(N1) $q: $r"; fi
done
if grep -q '<fold kind="bodies" budget_bytes="4000" served="3" total="3"><b t="cls" l="1" p="lane.py" n="Lane">' "$TMP/nest"; then
    ok "(N1b) nest: Lane rides once with schedule_lane inside it, served= counts both"
else no "(N1b) nest: the fold does not open with Lane served once (served=3 of 3)"; fi
# L1 (B2): the legend defines every part of the fold, in both dialects
for q in router resp respf slice ctor; do
    if r=$( chk cover "$TMP/$q" ); then ok "(L1) $q: the legend defines b t= n= p= l= and every fold/slice/skip attribute"; else no "(L1) $q: $r"; fi
done
# F2
if r=$( chk skip_then_serve "$TMP/resp" renderResponseBodyPage Application ); then
    ok "(F2) renderResponseBodyPage skipped with bytes>4000 and its --expand next=; Application still served after it"
    if r2=$( chk has_body "$TMP/resp" respond "res.end(body)" "body.pipe(res)" ); then ok "(F2b) respond's whole body served"; else no "(F2b) $r2"; fi
    eval "set -- $r"
    "$BIN" "$FIX" --no-cache "$@" >"$TMP/skipnext" 2>/dev/null
    if grep -q 'function renderResponseBodyPage (ctx, err) {' "$TMP/skipnext" && grep -q "return ctx.body" "$TMP/skipnext"; then ok "(F2c) the skip's pasted next= serves the skipped body"; else no "(F2c) the skip's next= does not serve renderResponseBodyPage"; fi
else no "(F2) $r"; fi
# F3
if r=$( chk c3_skip "$TMP/resp" ); then ok "(F3a) <sigs next=> is the first skip's --expand"; else no "(F3a) $r"; fi
"$BIN" "$ROOT/src" --no-cache --for="$T_SRC" >"$TMP/src" 2>/dev/null
RIPWIRE_NO_BODY_FOLD=1 "$BIN" "$ROOT/src" --no-cache --for="$T_SRC" >"$TMP/src.off" 2>/dev/null
if r=$( chk c3_pair "$TMP/src" "$TMP/src.off" ); then ok "(F3b) the signatures-only re-call moved to sigs_next= with its reading ${r:+($r)}"; else no "(F3b) $r"; fi
# F4
for q in router resp; do
    if r=$( chk whole "$TMP/$q" "$BIN" "$FIX" ); then ok "(F4) $q: every fold body whole (== --expand), <= 4000 B, no sibs/inc/calls, counts agree"; else no "(F4) $q: $r"; fi
done
# F5
for q in router resp respf slot slice; do
    if r=$( chk prefix "$TMP/$q" "$TMP/$q.off" ); then ok "(F5) $q: the answer before the fold == RIPWIRE_NO_BODY_FOLD=1"; else no "(F5) $q: $r"; fi
done
if r=$( chk prefix "$TMP/src" "$TMP/src.off" ); then ok "(F5) src: the answer before the fold == RIPWIRE_NO_BODY_FOLD=1"; else no "(F5) src: $r"; fi
# F5n (member-names twin): with the names off on both sides the pre-names premise holds byte for byte (est_tokens masked)
# (train 32a, N1: all six of F5's questions, each with F5's own root and legend)
namesoff(){ local q="$1" rd="$2" qq="$3"; shift 3
    RIPWIRE_NO_MEMBER_NAMES=1 "$BIN" "$rd" --no-cache --for="$qq" "$@" >"$TMP/$q.n" 2>/dev/null
    RIPWIRE_NO_MEMBER_NAMES=1 RIPWIRE_NO_BODY_FOLD=1 "$BIN" "$rd" --no-cache --for="$qq" "$@" >"$TMP/$q.n.off" 2>/dev/null; }
for q in router resp respf slot slice src; do
    case "$q" in
        router) namesoff "$q" "$FIX" "$T_ROUTER";;
        resp)   namesoff "$q" "$FIX" "$T_RESP";;
        respf)  namesoff "$q" "$FIX" "$T_RESP" --legend=full;;
        slot)   namesoff "$q" "$FIX" "$T_SLOT";;
        slice)  namesoff "$q" "$FIXPY" "$T_SLICE";;
        src)    namesoff "$q" "$ROOT/src" "$T_SRC";;
    esac
    if r=$( chk prefix_raw "$TMP/$q.n" "$TMP/$q.n.off" ); then ok "(F5n) $q: names off, the answer before the fold == RIPWIRE_NO_BODY_FOLD=1 unmasked"; else no "(F5n) $q: $r"; fi
done
# F6
if r=$( chk est "$TMP/resp" "$TMP/resp.off" ); then ok "(F6) est_tokens prices the fold's bodies"; else no "(F6) $r"; fi
# F7
for q in resp respf; do
    if chk legend "$TMP/$q" yes >/dev/null && chk legend "$TMP/$q.off" no >/dev/null; then ok "(F7) $q: the fold clause rides exactly with the fold"; else no "(F7) $q: fold clause presence wrong"; fi
done
# F8
i=0
while IFS= read -r line; do
    i=$(( i + 1 ))
    IFS='|' read -r -a argv <<<"$line"
    run "$TMP/p$i" "${argv[@]}"; off "$TMP/p$i.off" "${argv[@]}"
    if chk nofold "$TMP/p$i" >/dev/null && chk legend "$TMP/p$i" no >/dev/null && [ -s "$TMP/p$i" ] && cmp -s "$TMP/p$i" "$TMP/p$i.off"; then
        ok "(F8.$i) no fold, byte-identical to fold-off: $line"
    else
        no "(F8.$i) a fold or a byte difference on: $line"
    fi
done <<ARGV
--for=$T_RESP|--signatures-only
--for=$T_RESP|--json
--for=$T_RESP|--auto-bodies
--for=$T_RESP|--detail=1
--for=$T_RESP|--token-budget=3000
--for=SmartRouter
ARGV
# F8m (B1): --max-tokens is not read by this answer, so it changes no byte of it
run "$TMP/mt" --for="$T_RESP" --max-tokens=3000
if [ -s "$TMP/mt" ] && cmp -s "$TMP/mt" "$TMP/resp"; then ok "(F8m) --max-tokens=3000 is inert, as its notice says: the flagless answer, fold included"; else no "(F8m) --max-tokens=3000 changed the answer its notice says it does not read"; fi
# F9
if r=$( chk slot "$TMP/slot" ); then ok "(F9) the body slot's owner is not repeated in the fold"; else no "(F9) $r"; fi
# R1
if r=$( chk hopnext "$TMP/hops" "$BIN" "$FIX" dispatchRequest 20 ); then ok "(R1) a cut hop <calls> names --callees, which lists all 20; uncut listings carry no next="; else no "(R1) $r"; fi
if grep -q 'h calls capped=1 next= the call listing every callee' "$TMP/hops" && ! grep -q 'h calls capped=1 next=' "$TMP/resp"; then
    ok "(R1c) the hop calls next= clause rides exactly when a ranked hop's listing is cut"
else
    no "(R1c) the hop calls next= clause is missing beside a cut listing, or rides without one"
fi
# R1d: the next= is a pasteable argument under a file name a shell would split (nextFlag quotes it; checklist 34)
mkdir -p "$TMP/sp/src" && cp "$FIX/src/dispatch.ts" "$TMP/sp/src/dis patch.ts"
"$BIN" "$TMP/sp" --no-cache --for="$T_HOPS" >"$TMP/sp.out" 2>/dev/null
if r=$( chk hopnext "$TMP/sp.out" "$BIN" "$TMP/sp" dispatchRequest 20 ); then ok "(R1d) the cut listing's next= splits to one argument under a spaced file name and lists all 20"; else no "(R1d) $r"; fi
# R2
run "$TMP/page"  --for="$T_RESP" --limit=40
run "$TMP/pagef" --for="$T_RESP" --limit=40 --legend=full
for q in page pagef; do
    if r=$( chk pagelegend "$TMP/$q" ); then ok "(R2) $q: the file page legend reads n= against sibs_total="; else no "(R2) $q: $r"; fi
done
# X1-X3
run "$TMP/resp2" --for="$T_RESP"
if cmp -s "$TMP/resp" "$TMP/resp2"; then ok "(X1) deterministic"; else no "(X1) two runs differ"; fi
if command -v xmllint >/dev/null 2>&1; then
    bad=0
    for f in router resp respf slot hops src; do xmllint --noout "$TMP/$f" 2>/dev/null || { bad=1; no "(X2) $f is not well-formed XML"; }; done
    [ $bad = 0 ] && ok "(X2) well-formed (six answers)"
else
    skip "(X2) xmllint not installed"
fi
for f in router resp respf; do
    if r=$( chk nodash "$TMP/$f" ); then ok "(X3) $f: no '--' in a legend comment"; else no "(X3) $f: $r"; fi
done

# I: optional base-binary byte identity
if [ -n "${RIPWIRE_BASE_BIN:-}" ] && [ -x "$RIPWIRE_BASE_BIN" ]; then
    strip_at(){ sed -e 's/ at="[^"]*"//g' -e 's/"at":"[^"]*",\{0,1\}//g'; }
    i=0
    while IFS= read -r line; do
        i=$(( i + 1 ))
        IFS='|' read -r -a argv <<<"$line"
        "$RIPWIRE_BASE_BIN" "$FIX" --no-cache "${argv[@]}" 2>/dev/null | strip_at >"$TMP/i.base"
        "$BIN"              "$FIX" --no-cache "${argv[@]}" 2>/dev/null | strip_at >"$TMP/i.head"
        if [ ! -s "$TMP/i.base" ]; then no "(I$i) the base binary answered nothing for: $line"; continue; fi
        if cmp -s "$TMP/i.base" "$TMP/i.head"; then ok "(I$i) byte-identical to the base binary: $line"; else no "(I$i) differs from the base binary: $line"; fi
    done <<ARGV
--for=$T_RESP|--signatures-only
--for=$T_RESP|--json
--for=$T_RESP|--auto-bodies
--for=$T_RESP|--detail=1
--for=$T_RESP|--token-budget=3000
--for=SmartRouter
--expand=lib/application.js:respond
--callers=respond
ARGV
    for q in "$T_ROUTER" "$T_RESP"; do
        # the same switches on both sides: a pre-fold base ignores them (the arm's original premise), a base that already folds
        # is compared fold-off against fold-off (else every post-fold base fails this arm by construction)
        RIPWIRE_NO_BODY_FOLD=1 RIPWIRE_NO_MEMBER_NAMES=1 "$RIPWIRE_BASE_BIN" "$FIX" --no-cache --for="$q" 2>/dev/null | strip_at >"$TMP/i.base"
        RIPWIRE_NO_BODY_FOLD=1 RIPWIRE_NO_MEMBER_NAMES=1 "$BIN" "$FIX" --no-cache --for="$q" 2>/dev/null | strip_at >"$TMP/i.head"   # member-names off: the base has none
        if [ -s "$TMP/i.base" ] && cmp -s "$TMP/i.base" "$TMP/i.head"; then ok "(I-off) RIPWIRE_NO_BODY_FOLD=1 == the base binary: $q"; else no "(I-off) RIPWIRE_NO_BODY_FOLD=1 differs from the base binary: $q"; fi
    done
else
    skip "(I) RIPWIRE_BASE_BIN unset or not executable — base-binary byte identity not run here"
fi

exit $fail

#!/usr/bin/env bash
# forbodyslotcheck.sh — the ONE owner body of an explanatory --for question (the "body slot"), on top of the
# stop-when-complete budget semantics (lane/for-body-slot, train 28; design D of lane/for-noise-body-slot
# re-expressed: the body is a SECTION of a complete how-does answer, never paid by dropping sig rows).
#
# THE CONTRACT THIS PINS (arms tagged [P] were RED on the pre-change binary 974dd5b1; [G] arms are twins and
# near-miss negatives that hold on both binaries and must keep holding — PROCESS rule 4, no gate erosion):
#
#   TRIGGER  CLI --for (XML, full and compact legends) and MCP `for`, on the compact posture of the
#            subtoken+body route (root bundle="compact"), when the task carries an explanatory cue
#            (taskroute.h kExplanatoryCues, word-bounded: how does/do/is/are, what does, implementation of).
#            No slot: no cue, --signatures-only, --json (the JSON dialect carries no bodies in any posture —
#            a named floor), --auto-bodies and --detail=N (the caller chose the bodies), --format=candidates,
#            the name-exact route (the auto bundle already serves the anchor's body).
#   OWNER    owner-hop's predicate (verbs_for.h forOwnerHopPlan): a callable definition (Function/Method,
#            isDefinitionNotDeclaration, so never a .d.ts / header / overload / pure-virtual / interface-method
#            declaration), not a test symbol, inside the ranked head, whose whole folded name equals a question
#            word; common words after the rest. Among owners the one with a call edge (resolved or by name) to
#            an owner named by ANOTHER question word wins (the entry point; a self-edge, a recursion or a
#            same-named callee such as super().refresh() never makes one), else the best rank (pick="name").
#            No name owner: the MEMBER owner (Phase B, owner ruling Q1) — the first head-tier class/struct/
#            interface row (rank <= 24) with a callable definition that is its member (the parser's scope= equals
#            the class name, or the class's own byte span contains it in the same file) and whose folded name is
#            a non-common question word (pick="member"); a Go receiver method qualifies through its receiver
#            scope (#403; it was a named floor before Go carried one). None: no slot — the answer is the slot-off answer byte for byte (FIX1, owner ruling
#            2026-10-15: the subtoken fallback, pick="subtoken", is DROPPED; a callable that only shares a word with
#            the question is not its owner). Classes/structs/types are never the owner.
#   RENDER   one <bodies><b t= l= p= n=> in the --expand shape (packBodies), <calls> kept. A body over
#            kForBodySlotMaxBytes (6000) is head-cut at a line end: truncated="1" lines="lo-hi/T"
#            next="--expand=P:L:N:A-B" (the cutfix-bodies vocabulary), bodies capped="1"; a FIRST line longer
#            than the cap is served whole with over_ceiling="1" (packBodies' existing rule). Root bodies="1".
#   BUDGETS  default (no explicit budget): the body is a required section of the complete answer. <sigs>,
#            <hops>, <tail> are byte-identical to the slot-off answer (RIPWIRE_NO_BODY_SLOT=1, the A/B handle,
#            as RIPWIRE_NO_OWNER_HOP); est_tokens prices the body; the runaway guard (30,000 B) is unchanged
#            and never fires because of the body. Explicit --token-budget=N / MCP budget_tokens:
#            reserve-sections-first — the body is reserved with the trailing sections at the cut, rows past
#            the cut fill what is left; rows stay a rank prefix, monotone in N, never more than slot-off;
#            the body never shrinks as N grows and equals the default body at a wide N; when its share cannot
#            hold it the slot is skipped with bodies="0" reason="budget" and the owner stays recoverable
#            through a next= naming --expand of it.
#   MCP      `for` serves the same body (parity decision, design D open question 4); budget_tokens as above.
#
# Arms (colour on 974dd5b1 in brackets):
#   D1 [P] T_D: bodies=1 reason=owner, <bodies pick=name>, <b n=jwt> holds getCookie / HTTPException(401 /
#          ctx.set('jwtPayload'; <calls> with verify
#   D2 [G] T_D: not verify's body (jwt is r1 here, so this is NOT an entry-point discriminator — L1 and EP1 are)
#   D3 [P] est_tokens prices the body at no less than 0.2 token per body byte (the body rate is 3.80 B/token)
#   D4 [G] sigs/hops/tail byte-identical slot vs slot-off on every fixture question (checklist 23); slot-off has no body
#   D5 [P] legends: full answer explains bodies=1; compact legend defines b t= n= p= l= when a body rides; R3 (FIX1) [P] the
#          compact clause reads pick=name / pick=member and says reason=owner is not necessarily the subject nor the whole answer
#   D6 [G] no explanatory cue (where / show documentation / bare noun phrase): bodies=0, no <b
#   D7 [G] postures: --signatures-only, --json, --auto-bodies, --detail=1, --format=candidates, name-exact unchanged
#   D8 [P] Python: body of the METHOD apply, never the class Stylesheet (r1)
#   D9 [P] C: body of cmd_find_target (identifier word)
#   D9b [G] only a SUBTOKEN match exists ("target" ~ cmd_find_target, ranked): NO slot, byte-identical to slot-off.
#          BY-DESIGN BREAK (rule 4, FIX1): this arm pinned the subtoken fallback's body (pick="subtoken") through
#          66cc4b63; the owner ruling of 2026-10-15 dropped the fallback, so it now pins its absence — red on 66cc4b63
#   D10 [P] oversized C owner: head-cut at a line end, lines= next=; the next= serves the rest; no over_ceiling root;
#          the kept lines hold 2- and 3-byte UTF-8 (bytes exceed characters by > 10%), so a cap counted in
#          characters fails the <= 6000 B check (review R7)
#   D11 [P] one 7.7 KB line of multibyte text: served whole, over_ceiling="1" on the <b>, valid UTF-8
#   L1 [P] Rust: entry point index (calls walk) beats walk at r1     L2 [P] C++: Builder::Build DEFINITION (.cc), not the r1 header declaration
#   L3 [P] Go: method Package, never the type Packager
#   N1 [P] TS: negotiate's definition, not the r1 .d.ts declaration; [G] a .d.ts-only name never yields a .d.ts body
#   N2 [G] the only name owner is a tests/ helper: NO slot (no fallback since FIX1 — by-design break, rule 4: through
#          66cc4b63 the subtoken fallback served a non-test body here; red on 66cc4b63), never a tests/ body
#   N3 [P] two equal owners in two files: ONE body, the better-ranked one (p= and l= of the r1 row)
#   N4 [P] two same-named methods of two classes in ONE file: ONE body, the r1 row's (entity identity, checklist 16)
#   N5 [G] a struct named by the question is never the body; every <b t=> is fn/method
#   E1 [P] --token-budget=5000: the body rides; rows a rank prefix of the default rows, >= 4, no over_ceiling (re-anchored
#          from 3000 in Phase B: the reserve-first share the rows at the cut leave holds the 2.7 KB jwt body from N=4800 on
#          this fixture; below it the slot is skipped and disclosed — E2, E3)
#   E2 [P] --token-budget=400: bodies=0 reason=budget; the skipped slot discloses itself on <bodies … next=--expand=…jwt.ts:…>
#   E2b [P] the same skip under a directory whose name holds a space: next= is quoted (nextFlag) and splits to one argument
#   E3 [G/P] N sweep: rows monotone + rank prefix + <= slot-off; body bytes monotone; [P] at 1000000 body == default body
#   E4 [P] T_REF at --token-budget=800 and MCP budget_tokens=800 (slot-off serves rows past the cut there, and the share
#          the rows at the cut leave holds the small refresh body): the body is paid INSIDE N — rows(slot) < rows(off),
#          <sigs shown=K next_offset=K next=> names the displaced rows, est_tokens(slot) - est_tokens(off) <= the room slot-off
#          left under N + (legend + root delta + one row) / 2.5 (a body appended after the row cut fails both; M5)
#   MC1-MC4 MCP for: [P] body parity with the CLI; [P] budget_tokens=400 recoverable; [G] no cue, no body
#   MC5 [P] MCP for on the cut owner (T_BIG: same truncated=/lines=/next= and CDATA as the CLI) and on the Rust
#          entry point (T_RS: index) — MCP/CLI drift on the cut or on the pick
#   EV1 [P] RIPWIRE_NO_OWNER_HOP=1 leaves T_D's <bodies> byte-identical (the owner-hop env never reaches the slot)
#   EP1 [P] namesake: ModalScreen.refresh (r4) calls Screen.refresh (r3) through super(): not an entry point,
#          the r3 row's body is served;  EP2 [P] a recursive owner (flatten r2) never outranks normalize (r1)
#   DS1-DS4 [P] the definition, never the declaration row that outranks it: TS overload signatures, C++ pure
#          virtual + in-class override declaration, Go interface method spec, TS abstract method
#   Q1 [P] member owner, the head-tier class's member defined outside the head tier: C++ out of line (sc=),
#          Rust impl (sc=), Python (sc=), TS class (span containment), Go receiver (sc=, #403); pick="member"
#      [G] near misses: a common-word member (run); a class past the head tier (r31); another class's
#          same-named method that outranks the member is not served (entity identity); never the class/type
#   M1-M4 mutation controls (canned pre-change shapes are rejected)   X1-X3 determinism, xmllint, no '--' in comments
#   I0-I10 [optional, RIPWIRE_BASE_BIN=<pre-change binary>] byte identity where the slot must not fire (I0: slot off
#          == base; I10: --token-budget=3000 with RIPWIRE_NO_BODY_SLOT=1 == base — no reserve without the slot)
#
# Usage:  bash test/forbodyslotcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/forbodyslotcheck.sh
# BIN is $1, else RIPWIRE_BIN, else build/ripwire; the first output line names the binary used.
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_BODY_SLOT RIPWIRE_NO_OWNER_HOP RIPWIRE_NO_HEAD_RR
export RIPWIRE_TESTLIB="$ROOT/test/lib"   # softbudget.py set_prefix: the head round-robin set-prefix twin (lane hrr)
# body-fold (train 31; rule 4, by design): a compact answer now ends with <fold kind="bodies"> — the top ranked bodies, which may be a
# class, a .d.ts or a test body by rank (forbodyfoldcheck owns that contract). Every arm here is about the ONE owner body, so the
# answers are read fold-off; arm (FX), before the optional (I) arms, pins that the fold changes nothing of the slot on the default answer.
export RIPWIRE_NO_BODY_FOLD=1
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "forbodyslotcheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; return 0; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
cd "$ROOT"
FIX="$ROOT/test/forbodyslotfix"
[ -d "$FIX/src" ] || { echo "fixture $FIX missing"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# ── the checker: one Python reader of a --for answer, one verdict per call (exit 0 = holds) ─────────────────
cat > "$TMP/chk.py" <<'PY'
import html, json, os, re, sys
cmd, args = sys.argv[1], sys.argv[2:]
def load(p):
    return open(p, "rb").read().decode("utf-8", "replace")
def attrs(s):
    return dict((k, html.unescape(v)) for k, v in re.findall(r'(\w+)="([^"]*)"', s))
def root(t):
    m = re.search(r'<ctx ([^>]*)>', t)
    return attrs(m.group(1)) if m else {}
def sigs(t):
    m = re.search(r'<sigs\b([^>]*)>', t)
    return attrs(m.group(1)) if m else {}
def rows(t):
    m = re.search(r'<sigs\b[^>]*>(.*?)</sigs>', t, re.S)
    out = []
    for d in re.finditer(r'<d ([^>]*)>', m.group(1) if m else ""):
        a = attrs(d.group(1))
        out.append((int(a.get("r", "0") or 0), a.get("n", ""), a.get("p", ""), a))
    return sorted(out, key=lambda x: x[0])
def bodies(t):
    """every <b …><![CDATA[…]]>…</b>: (attrs, cdata bytes, the whole element)"""
    out = []
    for m in re.finditer(r'<b ([^>]*)>(.*?)</b>', t, re.S):
        cd = "".join(re.findall(r'<!\[CDATA\[(.*?)\]\]>', m.group(2), re.S))
        out.append((attrs(m.group(1)), cd, m.group(0)))
    return out
def legend(t):
    return " ".join(re.findall(r'<!--(.*?)-->', t, re.S))
def fail(msg):
    print(msg); sys.exit(1)
def bare(n):
    """a <d> row prints Owner::name / Owner.name (QUALNAME-1); a <b n=> body row keeps the BARE name"""
    return re.split(r"::|\.|#", n)[-1]
def first_row(t, name, rowname=None):
    for r, n, p, a in rows(t):
        if n == (rowname or name) or (rowname is None and bare(n) == name):
            return a
    return None
def defstart(a, cd):
    """the def's first source line: l= is the NAME's line, and the CDATA starts at the def (a C return type sits above it)"""
    lines = cd.split("\n")
    k = next((i for i, x in enumerate(lines) if a.get("n", "") in x), 0)
    return int(a["l"]) - k
def strip_slot(t):
    """the answer minus everything the body slot may add: legend comments, the <bodies> element, root bodies=/reason=/est_tokens="""
    t = re.sub(r'<!--.*?-->', '', t, flags=re.S)
    t = re.sub(r'<bodies\b.*?</bodies>', '', t, flags=re.S)
    t = re.sub(r'<bodies\b[^>]*/>', '', t)
    t = re.sub(r' (bodies|reason|est_tokens)="[^"]*"', '', t)
    return t
def est(t):
    v = root(t).get("est_tokens", "")
    if not v.isdigit(): fail("est_tokens missing or not numeric: %r" % v)
    return int(v)
if cmd == "rootattr":                   # rootattr FILE ATTR REGEX
    t = load(args[0]); v = root(t).get(args[1])
    if v is None or not re.fullmatch(args[2], v): fail("root %s=%r, wanted %s" % (args[1], v, args[2]))
    print("%s=%s" % (args[1], v))
elif cmd == "noroot":                   # noroot FILE ATTR : the root carries no ATTR=
    t = load(args[0]); v = root(t).get(args[1])
    if v is not None: fail("root carries %s=%r" % (args[1], v))
elif cmd == "bodycount":                # bodycount FILE N : exactly N <b> and root bodies=N
    t = load(args[0]); n = len(bodies(t)); v = root(t).get("bodies")
    if n != int(args[1]) or v != args[1]: fail("<b> count=%d root bodies=%r, wanted %s" % (n, v, args[1]))
    print("bodies=%s" % v)
elif cmd == "nobody":                   # nobody FILE : no <bodies and no <b
    t = load(args[0])
    if "<bodies" in t or re.search(r'<b ', t): fail("a bodies element rides: %s" % [b[0].get("n") for b in bodies(t)])
elif cmd == "body":                     # body FILE NAME PATH STR... : one <b n=NAME p=PATH> whose CDATA holds every STR
    t = load(args[0]); bs = bodies(t)
    hit = [b for b in bs if b[0].get("n") == args[1] and b[0].get("p") == args[2]]
    if not hit: fail("no <b n=%s p=%s> (bodies: %s)" % (args[1], args[2], [(b[0].get("n"), b[0].get("p")) for b in bs]))
    a, cd, el = hit[0]
    miss = [s for s in args[3:] if s not in cd]
    if miss: fail("body %s lacks %s" % (args[1], miss))
    print("<b n=%s p=%s l=%s> %d B" % (args[1], args[2], a.get("l"), len(cd.encode())))
elif cmd == "nobodyof":                 # nobodyof FILE NAME : no <b n=NAME>
    t = load(args[0])
    if any(b[0].get("n") == args[1] for b in bodies(t)): fail("a <b n=%s> rides" % args[1])
elif cmd == "nobodyat":                 # nobodyat FILE REGEX : no <b p=~REGEX>
    t = load(args[0]); bad = [b[0].get("p") for b in bodies(t) if re.search(args[1], b[0].get("p", ""))]
    if bad: fail("<b p=> matched %s: %s" % (args[1], bad))
elif cmd == "callsin":                  # callsin FILE NAME CALLEE : the <b n=NAME> carries <calls> with <c n=CALLEE>
    t = load(args[0]); hit = [b for b in bodies(t) if b[0].get("n") == args[1]]
    if not hit: fail("no <b n=%s>" % args[1])
    el = hit[0][2]
    if "<calls" not in el or ('<c n="%s"' % args[2]) not in el: fail("<b n=%s> has no <calls> naming %s" % (args[1], args[2]))
elif cmd == "bodyattr":                 # bodyattr FILE NAME ATTR REGEX
    t = load(args[0]); hit = [b for b in bodies(t) if b[0].get("n") == args[1]]
    if not hit: fail("no <b n=%s>" % args[1])
    v = hit[0][0].get(args[2])
    if v is None or not re.search(args[3], v): fail("<b n=%s %s=%r>, wanted %s" % (args[1], args[2], v, args[3]))
    print("<b %s %s=%s>" % (args[1], args[2], v[:90]))
elif cmd == "bodyisrow":                # bodyisrow FILE NAME : the one <b n=NAME> has the p= and l= of the best-ranked NAME row
    t = load(args[0]); hit = [b[0] for b in bodies(t) if b[0].get("n") == args[1]]
    if len(hit) != 1: fail("%d <b n=%s>, wanted exactly 1" % (len(hit), args[1]))
    r = first_row(t, args[1])
    if r is None: fail("no <d n=%s> row to compare against" % args[1])
    rp = r.get("p", ""); bp = hit[0].get("p", "")
    if (bp, hit[0].get("l")) != (rp, r.get("l")): fail("<b p=%s l=%s> is not the best-ranked row p=%s l=%s r=%s" % (bp, hit[0].get("l"), rp, r.get("l"), r.get("r")))
    print("<b p=%s l=%s> = r%s" % (bp, hit[0].get("l"), r.get("r")))
elif cmd == "bodykinds":                # bodykinds FILE : every <b t=> is a callable kind
    t = load(args[0]); bad = [(b[0].get("n"), b[0].get("t")) for b in bodies(t) if b[0].get("t") not in ("fn", "method")]
    if bad: fail("non-callable bodies: %s" % bad)
elif cmd == "rowis":                    # rowis FILE R NAME PATH : the row at rank R is NAME in PATH (an arm's premise)
    t = load(args[0]); hit = [x for x in rows(t) if x[0] == int(args[1])]
    if not hit or hit[0][1] != args[2] or hit[0][2] != args[3]: fail("premise: r%s is %s, wanted %s %s" % (args[1], hit[0][1:3] if hit else None, args[2], args[3]))
elif cmd == "cutatline":                # cutatline FILE NAME MAXB : a head-cut body that is the def's first K whole source lines, <= MAXB
    t = load(args[0]); hit = [b for b in bodies(t) if b[0].get("n") == args[1]]
    if not hit: fail("no <b n=%s>" % args[1])
    a, cd, el = hit[0]
    if len(cd.encode()) > int(args[2]): fail("CDATA %d B > %s" % (len(cd.encode()), args[2]))
    m = re.fullmatch(r'(\d+)-(\d+)/(\d+)', a.get("lines", ""))
    if not m: fail("lines=%r is not lo-hi/T" % a.get("lines"))
    lo, hi, tot = map(int, m.groups())
    src = open(os.path.join(os.environ["FIX"], a["p"]), encoding="utf-8").read().split("\n")
    l0 = defstart(a, cd)
    want = "\n".join(src[l0 - 1: l0 - 1 + (hi - lo + 1)])
    if cd.rstrip("\n") != want.rstrip("\n"): fail("CDATA is not source lines %d..%d of %s (a cut inside a line?)" % (l0, l0 + hi - lo, a["p"]))
    if not (lo == 1 and hi < tot): fail("lines=%s does not describe a head cut" % a.get("lines"))
    print("cut %s lines=%s %d B" % (args[1], a["lines"], len(cd.encode())))
elif cmd == "defline":                  # defline FILE NAME : print the def's first source line of the <b n=NAME>
    hit = [b for b in bodies(load(args[0])) if b[0].get("n") == args[1]]
    if not hit: fail("no <b n=%s>" % args[1])
    print(defstart(hit[0][0], hit[0][1]))
elif cmd == "nextof":                   # nextof FILE NAME : print the <b n=NAME next=> value
    t = load(args[0]); hit = [b for b in bodies(t) if b[0].get("n") == args[1]]
    if not hit or not hit[0][0].get("next"): fail("no <b n=%s next=>" % args[1])
    print(hit[0][0]["next"])
elif cmd == "startsat":                 # startsat FILE PATH LINE : the first <b> CDATA begins with source line LINE of PATH
    t = load(args[0]); bs = bodies(t)
    if not bs: fail("the continuation served no body")
    src = open(os.path.join(os.environ["FIX"], args[1]), encoding="utf-8").read().split("\n")
    want = src[int(args[2]) - 1]
    if not bs[0][1].startswith(want): fail("continuation begins %r, wanted source line %s %r" % (bs[0][1][:60], args[2], want[:60]))
elif cmd == "utf8whole":                # utf8whole FILE NAME TAIL : the <b n=NAME> CDATA is valid UTF-8 and ends with TAIL
    raw = open(args[0], "rb").read()
    m = re.search(rb'<b [^>]*n="' + re.escape(args[1].encode()) + rb'"[^>]*><!\[CDATA\[(.*?)\]\]>', raw, re.S)
    if not m: fail("no <b n=%s> CDATA" % args[1])
    try: cd = m.group(1).decode("utf-8", "strict")
    except UnicodeDecodeError as e: fail("CDATA is not valid UTF-8: %s" % e)
    if args[2] not in cd: fail("the line is not whole: %r missing" % args[2])
    print("%s %d B valid UTF-8" % (args[1], len(m.group(1))))
elif cmd == "sectionsame":              # sectionsame FILE_SLOT FILE_OFF : identical once the slot's own bytes are removed
    a, b = strip_slot(load(args[0])), strip_slot(load(args[1]))
    if a != b:
        i = next((k for k in range(min(len(a), len(b))) if a[k] != b[k]), min(len(a), len(b)))
        fail("sections differ at byte %d: slot %r | off %r" % (i, a[max(0, i - 40): i + 60], b[max(0, i - 40): i + 60]))
elif cmd == "estdelta":                 # estdelta FILE_SLOT FILE_OFF : est_tokens(slot) - est_tokens(off) >= 0.2 x body element bytes
    ts, to = load(args[0]), load(args[1])
    es, eo = est(ts), est(to)
    m = re.search(r'<bodies\b.*?</bodies>', ts, re.S)
    eb = len(m.group(0).encode()) if m else 0
    if eb == 0: fail("no <bodies> element to price (est %s vs %s)" % (es, eo))
    if es - eo < eb // 5: fail("est_tokens %s - %s < %d B x 0.2 (the body rate is 3.80 B/token)" % (es, eo, eb))
    print("est_tokens %s vs %s (+%d for %d B)" % (es, eo, es - eo, eb))
elif cmd == "paidinside":               # paidinside FILE_SLOT FILE_OFF N : E4 — the body is paid inside the target N, the displaced rows named
    ts, to = load(args[0]), load(args[1])
    if not bodies(ts): fail("premise: no body rides the budgeted answer")
    ns, no_ = len(rows(ts)), len(rows(to))
    if not ns < no_: fail("rows(slot)=%d is not below rows(off)=%d: the body was not paid inside the target" % (ns, no_))
    sa = sigs(ts)
    if not (sa.get("shown", "").isdigit() and sa.get("total", "").isdigit()): fail("<sigs> lacks numeric shown=/total=: %s" % sa)
    if int(sa["shown"]) != ns or int(sa["total"]) <= ns: fail("<sigs shown=%s total=%s> with %d rows: the cut is not disclosed" % (sa["shown"], sa["total"], ns))
    # the CLI names the continuation as an argv (next=), the MCP twin as the re-call's budget (next_budget_tokens=); both resume at next_offset=
    if sa.get("next_offset") != str(ns) or not (sa.get("next") or sa.get("next_budget_tokens", "").isdigit()):
        fail("<sigs next_offset=%r next=%r next_budget_tokens=%r>: the displaced rows are not recoverable" % (sa.get("next_offset"), sa.get("next"), sa.get("next_budget_tokens")))
    es, eo = est(ts), est(to)
    lg = len(legend(ts).encode()) - len(legend(to).encode())
    rd = len(re.search(r'<ctx [^>]*>', ts).group(0).encode()) - len(re.search(r'<ctx [^>]*>', to).group(0).encode())
    mrow = max(len(d.group(0).encode()) for d in re.finditer(r'<d [^>]*>.*?</d>', to, re.S))
    room = max(0, int(args[2]) - eo)   # what slot-off left unused under N: a body may fill it without displacing a row
    bound = room + (max(lg, 0) + max(rd, 0) + mrow) / 2.5 + 4
    if es - eo > bound: fail("est_tokens %d - %d = %d > %.0f (room %d, legend %+d B, root %+d B, one row %d B): the body rides on top of the target" % (es, eo, es - eo, bound, room, lg, rd, mrow))
    print("rows %d < %d, <sigs shown=%s next_offset=%s>, est %d vs %d (bound +%.0f)" % (ns, no_, sa["shown"], sa["next_offset"], es, eo, bound))
elif cmd == "bodyat":                   # bodyat FILE NAME PATH LINE : exactly one <b>, it is n=NAME p=PATH l=LINE
    bs = bodies(load(args[0]))
    if len(bs) != 1: fail("%d <b> elements, wanted 1: %s" % (len(bs), [(b[0].get("n"), b[0].get("p"), b[0].get("l")) for b in bs]))
    a = bs[0][0]
    if (a.get("n"), a.get("p"), a.get("l")) != (args[1], args[2], args[3]): fail("<b n=%s p=%s l=%s>, wanted n=%s p=%s l=%s" % (a.get("n"), a.get("p"), a.get("l"), args[1], args[2], args[3]))
    print("<b n=%s p=%s l=%s>" % (args[1], args[2], args[3]))
elif cmd == "bodiesattr":               # bodiesattr FILE ATTR REGEX : the <bodies> element's ATTR
    m = re.search(r'<bodies\b([^>]*)>', load(args[0]))
    if not m: fail("no <bodies> element")
    v = attrs(m.group(1)).get(args[1])
    if v is None or not re.fullmatch(args[2], v): fail("<bodies %s=%r>, wanted %s" % (args[1], v, args[2]))
    print("<bodies %s=%s>" % (args[1], v))
elif cmd == "rowline":                  # rowline FILE R : print the l= of the row at rank R ("" when none)
    hit = [a for r, n, p, a in rows(load(args[0])) if r == int(args[1])]
    print(hit[0].get("l", "") if hit else "")
elif cmd == "rankof":                   # rankof FILE NAME PATH : print the rank of the row n=NAME p=PATH (0 = not among the rows)
    # the row may print Owner::name (QUALNAME-1): the rank of the symbol is read by its bare name as well, never 0 for a spelling change
    hit = [r for r, n, p, a in rows(load(args[0])) if (n == args[1] or bare(n) == args[1]) and p == args[2]]
    print(hit[0] if hit else 0)
elif cmd == "bodiessec":                # bodiessec FILE : the <bodies>…</bodies> element verbatim
    m = re.search(r'<bodies\b.*?</bodies>', load(args[0]), re.S)
    if not m: fail("no <bodies> element")
    sys.stdout.write(m.group(0))
elif cmd == "mbcut":                    # mbcut FILE NAME PCT : the <b n=NAME> CDATA's UTF-8 bytes exceed its characters by > PCT %
    hit = [b for b in bodies(load(args[0])) if b[0].get("n") == args[1]]
    if not hit: fail("no <b n=%s>" % args[1])
    cd = hit[0][1]; nb = len(cd.encode()); nc = len(cd)
    if nb == 0 or 100.0 * (nb - nc) / nb <= float(args[2]): fail("CDATA %d B vs %d characters: not > %s%% multibyte" % (nb, nc, args[2]))
    print("CDATA %d B = %d characters (+%.1f%%)" % (nb, nc, 100.0 * (nb - nc) / nb))
elif cmd == "legend":                   # legend FILE STR... : every STR appears inside the XML comments
    lg = legend(load(args[0])); miss = [s for s in args[1:] if s not in lg]
    if miss: fail("legend lacks %s" % miss)
elif cmd == "nodashes":                 # nodashes FILE : no "--" inside any XML comment
    bad = [c[:60] for c in re.findall(r'<!--(.*?)-->', load(args[0]), re.S) if "--" in c]
    if bad: fail("'--' inside an XML comment: %s" % bad)
elif cmd == "rowkeys":                  # rowkeys FILE : print "n|p" per row in rank order (one per line)
    print("\n".join("%s|%s" % (n, p) for r, n, p, a in rows(load(args[0]))))
elif cmd == "prefix":                   # prefix FILE_A FILE_B : A's rows are a rank prefix of B's, A has >= 4 rows
    ra = [(n, p) for r, n, p, a in rows(load(args[0]))]; rb = [(n, p) for r, n, p, a in rows(load(args[1]))]
    if len(ra) < 4: fail("only %d rows (the rank 1..4 floor)" % len(ra))
    if ra != rb[:len(ra)]: fail("rows are not a rank prefix of the default answer (first diff at %d)" % next(i for i in range(len(ra)) if i >= len(rb) or ra[i] != rb[i]))
    print("%d rows, a prefix of %d" % (len(ra), len(rb)))
elif cmd == "setprefix":                # setprefix A ON OFF : head round-robin on (lane hrr, rule 4): A's rows (>= 4) are, as a SET,
    # the first rows of OFF (the RIPWIRE_NO_HEAD_RR=1 default: score ranks 1..K), and ON (the reordered default) serves OFF's rows
    sys.path.insert(0, os.environ["RIPWIRE_TESTLIB"]); from softbudget import set_prefix
    ra, ron, roff = ([(n, p) for r, n, p, a in rows(load(x))] for x in args[:3])
    if len(ra) < 4: fail("only %d rows (the rank 1..4 floor)" % len(ra))
    if not set_prefix(ra, ron, roff): fail("rows are not a SET prefix of the default answer (score ranks 1..%d of the RIPWIRE_NO_HEAD_RR=1 twin)" % len(ra))
    print("%d rows, a set prefix of %d" % (len(ra), len(ron)))
elif cmd == "nrows":                    # nrows FILE
    print(len(rows(load(args[0]))))
elif cmd == "bodybytes":                # bodybytes FILE : CDATA bytes of every <b>
    print(sum(len(b[1].encode()) for b in bodies(load(args[0]))))
elif cmd == "cdata":                    # cdata FILE NAME : the <b n=NAME> CDATA, verbatim
    hit = [b for b in bodies(load(args[0])) if b[0].get("n") == args[1]]
    if not hit: fail("no <b n=%s>" % args[1])
    sys.stdout.write(hit[0][1])
elif cmd == "bodiesnext":               # bodiesnext FILE REGEX : a <bodies> element (the slot's own disclosure) carries next=~REGEX
    m = re.search(r'<bodies\b([^>]*)>', load(args[0]))
    if not m: fail("no <bodies> element (a skipped slot discloses itself there)")
    a = attrs(m.group(1))
    if not re.search(args[1], a.get("next", "")): fail("<bodies %s> has no next= matching %s" % (m.group(1)[:120], args[1]))
    print("<bodies next=%s>" % a.get("next"))
elif cmd == "over":                     # over FILE : the root carries no over_ceiling="1"
    if root(load(args[0])).get("over_ceiling") == "1": fail("over_ceiling=\"1\" on the root")
elif cmd == "sigsopen":                 # sigsopen FILE : the answer has a <sigs block (premise)
    if "<sigs" not in load(args[0]): fail("no <sigs>")
else:
    fail("unknown check " + cmd)
PY
export FIX
chk(){ python3 "$TMP/chk.py" "$@"; }
run(){ "$BIN" "$FIX" --cache="$TMP/rw.cache" "$@" 2>/dev/null; }       # a fresh cache per gate run: this binary's own parse
runoff(){ RIPWIRE_NO_BODY_SLOT=1 "$BIN" "$FIX" --cache="$TMP/rw.cache" "$@" 2>/dev/null; }
strip_at(){ sed -e 's/ at="[^"]*"//g' -e 's/"at":"[^"]*",\{0,1\}//g'; }
cat > "$TMP/mcptext.py" <<'PY'
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try: d = json.loads(line)
    except Exception: continue
    for c in (d.get("result") or {}).get("content") or []:
        if c.get("type") == "text": sys.stdout.write(c["text"])
PY
mcpfor(){   # mcpfor TASK [EXTRA_JSON_MEMBERS] > FILE
    python3 -c 'import json,sys; a={"path":sys.argv[1],"task":sys.argv[2]}; a.update(json.loads(sys.argv[3] or "{}")); print(json.dumps({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":a}}))' "$FIX" "$1" "${2:-}" \
        | "$BIN" --mcp 2>/dev/null | python3 "$TMP/mcptext.py"
}
mcpforoff(){ RIPWIRE_NO_BODY_SLOT=1 mcpfor "$@"; }   # the exported env reaches the --mcp process inside mcpfor

# ── the runtime roots (written under $TMP: outside the indexed tree, so the repository's own --for corpus is unchanged) ──
# Q1 member owner — the ninja shape: a head-tier class whose member that the question names is defined OUTSIDE the head tier.
# 45 helpers named by two question words, each body naming the member word, lower that word's weight; the member's long body
# names no question word. EP / DS: entry-point and declaration-sibling near misses (premises checked below, never assumed).
cat > "$TMP/gen.py" <<'PY'
import itertools, os, sys
out = sys.argv[1]
W = ["kiln", "glaze", "firing", "queue", "batch", "track", "schedule", "record", "result", "job"]
def w(p, s):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write(s)
def fillers(root, verb, alt=None):
    xs = []
    for k, (a, b) in enumerate(itertools.combinations(W, 2)):
        xs.append("int %s_%s_%d( int x )\n{\n    // %s the %s %s\n    return x + %d;\n}" % (a, b, k, alt if alt and k % 3 == 0 else verb, a, b, k))
    w(root + "/src/fillers.c", "\n".join(xs) + "\n")
def longbody(ind, n=90):
    return "\n".join("%stotal += step_value( left, %d ) * weight_of( %d );" % (ind, i, i) for i in range(n))
def cpp(root, verb="Assemble", other=None):
    fillers(root, verb.lower())
    w(root + "/src/forge.h", "// the forge: schedules kiln jobs, tracks firing queues and glaze batches\nstruct KilnJob;\nstruct GlazeBatch;\nclass Forge\n{\npublic:\n"
      "    // %s every queued kiln job: schedule glaze batches, track firing queues, record kiln results\n    bool %s( KilnJob* job );\n"
      "    void ScheduleGlaze( GlazeBatch* batch );\n    void TrackFiring( KilnJob* job );\n    KilnJob* NextKilnJob();\n"
      "    int kiln_slots_;\n    int glaze_batches_;\n    int firing_queues_;\n};\n" % (verb.lower(), verb))
    w(root + "/src/forge.cc", '#include "forge.h"\nint step_value( int a, int b );\nint weight_of( int a );\nbool Forge::%s( KilnJob* job )\n{\n    int left = 3;\n    int total = 0;\n%s\n    return job != nullptr && total > 0;\n}\n' % (verb, longbody("    ")))
    if other:
        w(root + "/src/smelter.cc", "class %s\n{\npublic:\n    bool %s( int job );\n};\nint step_value( int a, int b );\nbool %s::%s( int job )\n{\n    int total = 0;\n%s\n    return total > job;\n}\n" % (other, verb, other, verb, longbody("    ", 40)))
def deep(root):
    fillers(root, "assemble", alt="assemble forge")
    w(root + "/src/forge.h", "class Forge\n{\npublic:\n    bool Assemble( int a );\n    int  width_ = 0;\n};\n")
    w(root + "/src/forge.cc", '#include "forge.h"\nint step_value( int a, int b );\nint weight_of( int a );\nbool Forge::Assemble( int a )\n{\n    int left = 3;\n    int total = 0;\n%s\n    return total > a;\n}\n' % longbody("    "))
def rs(root):
    fillers(root, "assemble")
    w(root + "/src/forge.rs", "/// the forge: schedules kiln jobs, tracks firing queues and glaze batches, records kiln results\npub struct Forge {\n    pub kiln_slots: u32,\n    pub glaze_batches: u32,\n    pub firing_queues: u32,\n    pub kiln_results: u32,\n}\n\nimpl Forge {\n    pub fn assemble(&mut self, job: u32) -> bool {\n        let left = 3;\n        let mut total = 0;\n%s\n        total > job\n    }\n}\n" % longbody("        "))
def py(root):
    fillers(root, "assemble")
    body = "\n".join("        total += step_value(left, %d) * weight_of(%d)" % (i, i) for i in range(90))
    w(root + "/src/forge.py", 'class Forge:\n    """the forge: schedules kiln jobs, tracks firing queues and glaze batches, records kiln results"""\n\n    kiln_slots = 0\n    glaze_batches = 0\n    firing_queues = 0\n\n    def track_firing(self, job):\n        return job\n\n    def assemble(self, job):\n        left = 3\n        total = 0\n%s\n        return total > job\n' % body)
def ts(root):
    fillers(root, "assemble")
    w(root + "/src/forge.ts", "// the forge: schedules kiln jobs, tracks firing queues and glaze batches, records kiln results\nexport class Forge {\n  kilnSlots = 0;\n  glazeBatches = 0;\n  firingQueues = 0;\n  trackFiring(job: number): number {\n    return job;\n  }\n  assemble(job: number): boolean {\n    const left = 3;\n    let total = 0;\n%s\n    return total > job;\n  }\n}\n" % longbody("    "))
def go(root):
    fillers(root, "assemble")
    w(root + "/src/forge.go", "package forge\n\n// Forge schedules kiln jobs, tracks firing queues and glaze batches, records kiln results\ntype Forge struct {\n\tKilnSlots    int\n\tGlazeBatches int\n\tFiringQueues int\n\tKilnResults  int\n}\n\nfunc stepValue(a, b int) int { return a + b }\nfunc weightOf(a int) int     { return a }\n\nfunc (f *Forge) Assemble(job int) bool {\n\tleft := 3\n\ttotal := 0\n%s\n\treturn total > job\n}\n" % "\n".join("\ttotal += stepValue(left, %d) * weightOf(%d)" % (i, i) for i in range(90)))
cpp(out + "/cpp"); rs(out + "/rs"); py(out + "/py"); ts(out + "/ts"); go(out + "/go")
cpp(out + "/common", verb="Run"); deep(out + "/deep"); cpp(out + "/other", other="Smelter")
# EP1 namesake (super().refresh() is a by-name edge to a same-named owner) and EP2 recursion
w(out + "/name/src/screens.py", '"""Screens that repaint their regions."""\n\n\nclass Screen:\n    """A full screen: repaint every region of the screen, then refresh the cursor."""\n\n    def refresh(self):\n        """Repaint the screen: every region of the screen, top to bottom, then the cursor."""\n        self.painted = True\n        return self\n\n\nclass ModalScreen(Screen):\n    """A modal dialog drawn over another screen."""\n\n    def refresh(self):\n        """Repaint the dialog, then its parent."""\n        super().refresh()\n        self.dialog = True\n        return self\n')
w(out + "/self/src/tree.py", '"""Tree helpers: normalize a parsed tree, flatten nested nodes."""\n\n\ndef normalize(tree):\n    """Normalize the tree: strip blank labels and lower-case every tag."""\n    tree["tag"] = tree.get("tag", "").lower()\n    tree["label"] = tree.get("label", "").strip()\n    return tree\n\n\ndef flatten(tree):\n    """Flatten nested children into one list, depth first."""\n    out = [tree]\n    for child in tree.get("children", []):\n        out.extend(flatten(child))\n    return out\n')
# DS1-DS4: a declaration row (documented, so it outranks) and its definition (undocumented)
w(out + "/tsover/src/format.ts", '/** format renders the value: a number value is grouped for display */\nexport function format(value: number): string;\n/** format renders the value: a string value is trimmed for display */\nexport function format(value: string): string;\nexport function format(v: number | string): string {\n  if (typeof v === "number") {\n    return v.toLocaleString("en-US");\n  }\n  return v.trim();\n}\n')
w(out + "/cppvirt/src/dispatch.h", "struct Edge;\nclass Dispatcher\n{\npublic:\n    virtual ~Dispatcher() {}\n    /// dispatch: the pool dispatch of one ready edge to an idle pool worker; false when the pool has no idle worker\n    virtual bool Dispatch( Edge* edge ) = 0;\n};\nclass PoolDispatcher : public Dispatcher\n{\npublic:\n    /// dispatch: the pool dispatch of one ready edge to an idle pool worker\n    bool Dispatch( Edge* edge ) override;\n    int  idle_ = 4;\n};\n")
w(out + "/cppvirt/src/dispatch.cc", '#include "dispatch.h"\nbool PoolDispatcher::Dispatch( Edge* e )\n{\n    if( idle_ == 0 || e == nullptr )\n    {\n        return false;\n    }\n    --idle_;\n    return true;\n}\n')
w(out + "/goiface/src/packer.go", "package packer\n\ntype Packer interface {\n\t// Pack: the tar packer packs the files into one archive, every file in order\n\tPack(files []string) error\n}\n\ntype tarStream struct{ count int }\n\nfunc (t *tarStream) Pack(xs []string) error {\n\tfor range xs {\n\t\tt.count++\n\t}\n\treturn nil\n}\n")
w(out + "/tsabs/src/printer.ts", 'export abstract class Base {\n  /** print: the html printer prints a document as html */\n  abstract print(doc: string): string;\n}\nexport class Out extends Base {\n  print(d: string): string {\n    return "<p>" + d + "</p>";\n  }\n}\n')
PY
python3 "$TMP/gen.py" "$TMP/rt" || { echo "the runtime-root generator failed"; exit 2; }
rrun(){ local r="$1"; shift; "$BIN" "$TMP/rt/$r" --cache="$TMP/rt.$r.cache" "$@" 2>/dev/null; }   # one cache per runtime root

T_D="How does the JWT middleware verify a token?"
T_PY="How does Stylesheet apply the parsed rules to a widget?"
T_C="How does cmd_find_target resolve the session, window and pane of a command?"
T_SUB="How does tmux resolve which session, window and pane a command targets (the -t target)?"
T_BIG="How does render_screen draw the screen?"
T_HYD="How does hydrate restore the state?"
T_RS="How does the indexer walk the module tree breadth-first to index the crate source paths?"
T_CPP="How does the C++ builder build the plan and run its commands?"
T_GO="How does the packager package the files into an archive?"
T_DTS="How does negotiate pick the content type?"
T_DTS2="How does handshake upgrade the socket?"
T_TEST="How does roundtrip encode a token string?"
T_TWO="How does render produce the view markup?"
T_REF="How does refresh repaint a widget?"
T_STRUCT="How is the screen struct laid out?"
T_WHERE="Where does the JWT middleware verify a token?"
T_SHOW="show documentation of the JWT middleware token check"
T_NOCUE="JWT middleware token verification"

# key|task — every question the gate asks, answered with the slot on and with RIPWIRE_NO_BODY_SLOT=1
QUESTIONS="d|$T_D
py|$T_PY
c|$T_C
sub|$T_SUB
big|$T_BIG
hyd|$T_HYD
rs|$T_RS
cpp|$T_CPP
go|$T_GO
dts|$T_DTS
dts2|$T_DTS2
test|$T_TEST
two|$T_TWO
ref|$T_REF
struct|$T_STRUCT
where|$T_WHERE
show|$T_SHOW
nocue|$T_NOCUE"
# fail fast: a binary that cannot answer the first question answers none of the ~90 below (binoverridecheck's sentinel)
run --for="$T_D" >"$TMP/probe.xml"
if ! grep -q '<sigs' "$TMP/probe.xml"; then no "(0) $BIN answered no <sigs> on the fixture — every arm would be vacuous"; exit 1; fi
while IFS='|' read -r k q; do
    run --for="$q" >"$TMP/$k.xml"
    runoff --for="$q" >"$TMP/$k.off.xml"
    for f in "$k" "$k.off"; do
        if r="$( chk sigsopen "$TMP/$f.xml" )"; then :; else no "(0) $f.xml: $r — the fixture answered nothing, every arm reading it would be vacuous"; fi
    done
done <<<"$QUESTIONS"
run --for="$T_D" --legend=compact >"$TMP/d.c.xml"
# head round-robin (lane hrr, train 31; rule 4): the score-order twin of the default answer, read by the E1-E3 order-prefix twins
RIPWIRE_NO_HEAD_RR=1 run --for="$T_D" >"$TMP/d.so.xml"

# ── D: the body slot in the default regime ─────────────────────────────────────────────────────────────────
if r="$( chk rootattr "$TMP/d.xml" bundle compact )"; then ok "(D1) T-D premise: $r"; else no "(D1) T-D premise: $r"; fi
if r="$( chk bodycount "$TMP/d.xml" 1 )"; then ok "(D1) T-D: exactly one body, root $r"; else no "(D1) T-D: $r"; fi
if r="$( chk body "$TMP/d.xml" jwt src/middleware/jwt/jwt.ts "getCookie" "HTTPException(401" "ctx.set('jwtPayload'" )"; then ok "(D1) T-D: $r holds the three kill strings"; else no "(D1) T-D: $r"; fi
if r="$( chk callsin "$TMP/d.xml" jwt verify )"; then ok "(D1) T-D: the body keeps <calls> (names verify)"; else no "(D1) T-D: $r"; fi
if r="$( chk rootattr "$TMP/d.xml" reason owner )"; then ok "(D1) T-D: root $r (bodies=1 is never read beside reason=compact-route)"; else no "(D1) T-D: $r"; fi
if r="$( chk bodiesattr "$TMP/d.xml" pick name )"; then ok "(D1) T-D: $r"; else no "(D1) T-D: $r"; fi
if r="$( chk nobodyof "$TMP/d.xml" verify )"; then ok "(D2) T-D: not verify's body (jwt is r1: a rank fact, not the entry-point discriminator)"; else no "(D2) T-D: $r"; fi
if r="$( chk estdelta "$TMP/d.xml" "$TMP/d.off.xml" )"; then ok "(D3) T-D: $r"; else no "(D3) T-D: $r"; fi
while IFS='|' read -r k q; do
    if r="$( chk sectionsame "$TMP/$k.xml" "$TMP/$k.off.xml" )"; then ok "(D4) $k: sigs/hops/tail identical slot vs RIPWIRE_NO_BODY_SLOT=1 (not paid in rows)"; else no "(D4) $k: $r"; fi
    if r="$( chk nobody "$TMP/$k.off.xml" )"; then ok "(D4) $k: RIPWIRE_NO_BODY_SLOT=1 serves no body"; else no "(D4) $k: RIPWIRE_NO_BODY_SLOT=1: $r"; fi
done <<<"$QUESTIONS"
if r="$( chk legend "$TMP/d.xml" 'bodies=1' )"; then ok "(D5) full legend explains bodies=1 (the owner body)"; else no "(D5) full legend: $r"; fi
if r="$( chk bodycount "$TMP/d.c.xml" 1 )"; then ok "(D5) compact dialect: the body rides too"; else no "(D5) compact dialect: $r"; fi
if r="$( chk legend "$TMP/d.c.xml" 'b t= n= p= l=' )"; then ok "(D5) compact legend defines b t= n= p= l= when a body rides"; else no "(D5) compact legend: $r"; fi
# R3 (FIX1, checklist 3): the compact reading says what each pick= means and what reason=owner does NOT mean — a pick=name
# body (d) and a pick=member body (Q1 C++) alike; red on 66cc4b63 ("ONE owner body, by name not resolved (pick=…)" only)
R3_STRS=( 'pick=name: its name is a question word' 'pick=member: a method so named of a ranked class' 'not necessarily the subject' 'not a claim it is the whole answer' )
if r="$( chk legend "$TMP/d.c.xml" "${R3_STRS[@]}" )"; then ok "(D5/R3) pick=name body: the compact legend reads pick= and says what reason=owner does not mean"; else no "(D5/R3) pick=name body: $r"; fi
for k in where show nocue; do
    if r="$( chk rootattr "$TMP/$k.xml" bodies 0 )"; then ok "(D6) $k (no explanatory cue): $r"; else no "(D6) $k: $r"; fi
    if r="$( chk nobody "$TMP/$k.xml" )"; then ok "(D6) $k: no <bodies> element"; else no "(D6) $k: $r"; fi
done

# postures that never take the slot: identical with the slot on and off
run --for="$T_D" --signatures-only >"$TMP/p.sig.xml"
if r="$( chk nobody "$TMP/p.sig.xml" )" && r2="$( chk noroot "$TMP/p.sig.xml" bodies )"; then ok "(D7) --signatures-only: no body, no bodies="; else no "(D7) --signatures-only: ${r:-} ${r2:-}"; fi
run --for="$T_D" --json >"$TMP/p.json"
if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if 'bodies' not in d and len(d.get('sigs',[]))>=1 else 1)" "$TMP/p.json"; then
    ok "(D7) --json: no bodies key, sigs served (the JSON dialect carries no bodies: named floor)"
else
    no "(D7) --json: a bodies key rides the JSON dialect (or no sigs)"
fi
for a in --auto-bodies --detail=1 --format=candidates; do
    run --for="$T_D" "$a" >"$TMP/p.on.xml"; runoff --for="$T_D" "$a" >"$TMP/p.off.xml"
    if [ -s "$TMP/p.on.xml" ] && cmp -s "$TMP/p.on.xml" "$TMP/p.off.xml"; then ok "(D7) $a: byte-identical with and without the slot"; else no "(D7) $a: differs from RIPWIRE_NO_BODY_SLOT=1 (or empty)"; fi
done
if r="$( chk rootattr "$TMP/p.on.xml" bodies '.*' 2>/dev/null )"; then no "(D7) --format=candidates carries bodies="; else ok "(D7) --format=candidates carries no bodies="; fi
run --for=verify >"$TMP/p.ne.xml"; runoff --for=verify >"$TMP/p.ne.off.xml"
if grep -q 'route="name-exact' "$TMP/p.ne.xml" && cmp -s "$TMP/p.ne.xml" "$TMP/p.ne.off.xml"; then ok "(D7) name-exact --for=verify: auto bundle, identical with and without the slot"; else no "(D7) name-exact: not name-exact, or differs from RIPWIRE_NO_BODY_SLOT=1"; fi

# languages, owners, near misses
if r="$( chk rowis "$TMP/py.xml" 1 Stylesheet src/textual/css/stylesheet.py )"; then :; else no "(D8) premise: $r"; fi
if r="$( chk body "$TMP/py.xml" apply src/textual/css/stylesheet.py "_check_rule(" "widget.refresh()" )"; then ok "(D8) Python: $r (the method)"; else no "(D8) Python: $r"; fi
if r="$( chk nobodyof "$TMP/py.xml" Stylesheet )"; then ok "(D8) Python: the class Stylesheet (r1) is never the body"; else no "(D8) Python: $r"; fi
if r="$( chk body "$TMP/c.xml" cmd_find_target src/c/cmd-find.c "cmd_find_get_session(" "cmd_find_valid_state(" )"; then ok "(D9) C: $r"; else no "(D9) C: $r"; fi
# D9b premise: the subtoken match the dropped fallback served IS a ranked row here — so "no slot" is the rule, not a miss
if grep -q '<d [^>]*n="cmd_find_target"' "$TMP/sub.xml"; then :; else no "(D9b) premise: cmd_find_target is not a ranked row on T_SUB"; fi
if r="$( chk nobody "$TMP/sub.xml" )" && cmp -s "$TMP/sub.xml" "$TMP/sub.off.xml"; then ok "(D9b) only a subtoken match (cmd_find_target ~ 'target'): no slot, byte-identical to RIPWIRE_NO_BODY_SLOT=1"; else no "(D9b) only a subtoken match: a body rides or the answer differs from slot-off ${r:-}"; fi
if grep -q 'pick="subtoken"' "$TMP/sub.xml"; then no "(D9b) pick=\"subtoken\" still rides"; else ok "(D9b) no pick=\"subtoken\""; fi
if r="$( chk bodyattr "$TMP/big.xml" render_screen truncated '^1$' )"; then ok "(D10) oversized owner: $r"; else no "(D10) oversized: $r"; fi
if r="$( chk cutatline "$TMP/big.xml" render_screen 6000 )"; then ok "(D10) oversized owner: $r (whole lines, <= 6000 B)"; else no "(D10) oversized: $r"; fi
if nx="$( chk nextof "$TMP/big.xml" render_screen )" && printf '%s' "$nx" | grep -q '^--expand=src/c/render.c:'; then
    ok "(D10) oversized owner: next=$nx"
    hi="$( grep -o '<b [^>]*n="render_screen"[^>]*' "$TMP/big.xml" | grep -o 'lines="[0-9]*-[0-9]*' | sed 's/.*-//' )"
    l0="$( chk defline "$TMP/big.xml" render_screen )"   # the def's first line (l= names the name's line, one below 'void')
    if [ -n "$hi" ] && [ -n "$l0" ]; then
        run "$nx" >"$TMP/big.next.xml"
        if r="$( chk startsat "$TMP/big.next.xml" src/c/render.c $(( l0 + hi )) )"; then ok "(D10) the next= serves the rest, from source line $(( l0 + hi ))"; else no "(D10) next=: $r"; fi
    else
        no "(D10) could not read lines=/l= off the cut body"
    fi
else
    no "(D10) oversized: no <b n=render_screen next=--expand=src/c/render.c:…> (${nx:-none})"
fi
if r="$( chk over "$TMP/big.xml" )"; then ok "(D10) oversized owner: no over_ceiling on the root (the guard never fires for the body)"; else no "(D10) $r"; fi
if r="$( chk mbcut "$TMP/big.xml" render_screen 10 )"; then ok "(D10) the kept lines are multibyte: $r — a cap counted in characters would pass 6000 B"; else no "(D10) multibyte premise: $r"; fi
if r="$( chk bodyattr "$TMP/hyd.xml" hydrate over_ceiling '^1$' )"; then ok "(D11) one line over the cap: $r (served whole)"; else no "(D11) one line over the cap: $r"; fi
if r="$( chk utf8whole "$TMP/hyd.xml" hydrate 'restored: true' )"; then ok "(D11) one line over the cap: $r, the whole line"; else no "(D11) $r"; fi
if r="$( chk rowis "$TMP/rs.xml" 1 walk src/rs/indexer.rs )"; then :; else no "(L1) premise: $r"; fi
if r="$( chk body "$TMP/rs.xml" index src/rs/indexer.rs "let order = walk(" )"; then ok "(L1) Rust: $r — the entry point (index calls walk) beats walk at r1"; else no "(L1) Rust: $r"; fi
if r="$( chk nobodyof "$TMP/rs.xml" walk )"; then ok "(L1) Rust: not walk's body"; else no "(L1) Rust: $r"; fi
if r="$( chk rowis "$TMP/cpp.xml" 1 Builder::Build src/cpp/build.h )"; then :; else no "(L2) premise: $r"; fi
if r="$( chk body "$TMP/cpp.xml" Build src/cpp/build.cc "cannot make progress" )"; then ok "(L2) C++: $r — the out-of-line definition, not the r1 header declaration"; else no "(L2) C++: $r"; fi
if r="$( chk nobodyat "$TMP/cpp.xml" '\.h$' )" && r2="$( chk nobodyof "$TMP/cpp.xml" Builder )"; then ok "(L2) C++: no header declaration, no class body"; else no "(L2) C++: ${r:-} ${r2:-}"; fi
if r="$( chk body "$TMP/go.xml" Package src/go/packager.go "guessing packager from target file extension" )"; then ok "(L3) Go: $r (the method)"; else no "(L3) Go: $r"; fi
if r="$( chk nobodyof "$TMP/go.xml" Packager )"; then ok "(L3) Go: the type Packager is never the body"; else no "(L3) Go: $r"; fi
# N1 re-anchored (lane hrr, train 31; rule 4): the declaration-twin tier ranks a .d.ts x0.7 when its package ships an
# implementation, so on the fixture as it is negotiate.ts now outranks global.d.ts (the premise "r1 is the .d.ts" broke by
# design). The premise is restored the tier's own way: a copy whose src/types is a types-only package (its own package.json,
# no implementation), where the .d.ts keeps 1.0 and is r1 again — the arms below then run unchanged on it. (N1r) keeps the
# fixture as it is: the tier's r1 is the definition, and its body is the one served.
rm -rf "$TMP/dtsfix"; cp -R "$FIX" "$TMP/dtsfix" && printf '{"name":"@forbodyslot/types","types":"global.d.ts"}\n' >"$TMP/dtsfix/src/types/package.json"
"$BIN" "$TMP/dtsfix" --no-cache --for="$T_DTS" >"$TMP/dts.tonly.xml" 2>/dev/null
"$BIN" "$TMP/dtsfix" --no-cache --for="$T_DTS2" >"$TMP/dts2.tonly.xml" 2>/dev/null
if r="$( chk rowis "$TMP/dts.tonly.xml" 1 negotiate src/types/global.d.ts )"; then :; else no "(N1) premise (types-only package): $r"; fi
if r="$( chk body "$TMP/dts.tonly.xml" negotiate src/negotiate.ts "negotiate fallback" )"; then ok "(N1) TS: $r — the definition, not the r1 .d.ts declaration"; else no "(N1) TS: $r"; fi
for k in dts dts2; do
    if r="$( chk nobodyat "$TMP/$k.tonly.xml" '\.d\.ts$' )"; then ok "(N1) $k (types-only package): no body from a .d.ts declaration"; else no "(N1) $k (types-only package): $r"; fi
    if r="$( chk nobodyat "$TMP/$k.xml" '\.d\.ts$' )"; then ok "(N1) $k: no body from a .d.ts declaration"; else no "(N1) $k: $r"; fi
done
if r="$( chk rowis "$TMP/dts.xml" 1 negotiate src/negotiate.ts )" && r2="$( chk body "$TMP/dts.xml" negotiate src/negotiate.ts "negotiate fallback" )"; then
    ok "(N1r) the fixture as it is: the declaration-twin tier ranks the definition r1, and its body is served: $r2"
else no "(N1r) the fixture as it is: ${r:-} ${r2:-}"; fi
if r="$( chk nobody "$TMP/test.xml" )" && cmp -s "$TMP/test.xml" "$TMP/test.off.xml"; then ok "(N2) the only name owner is a tests/ helper: no slot, byte-identical to RIPWIRE_NO_BODY_SLOT=1"; else no "(N2) a body rides, or the answer differs from slot-off ${r:-}"; fi
if r="$( chk nobodyat "$TMP/test.xml" '(^|/)tests?/' )" && r2="$( chk nobodyof "$TMP/test.xml" roundtrip )"; then ok "(N2) no body from tests/ (roundtrip is a test symbol)"; else no "(N2) ${r:-} ${r2:-}"; fi
if r="$( chk bodycount "$TMP/two.xml" 1 )"; then ok "(N3) two equal owners: one body"; else no "(N3) $r"; fi
if r="$( chk bodyisrow "$TMP/two.xml" render )"; then ok "(N3) two equal owners: $r (the better-ranked)"; else no "(N3) $r"; fi
run --for="$T_TWO" >"$TMP/two2.xml"
if cmp -s "$TMP/two.xml" "$TMP/two2.xml"; then ok "(N3) two equal owners: deterministic x2"; else no "(N3) two equal owners: two runs differ"; fi
if r="$( chk bodycount "$TMP/ref.xml" 1 )"; then ok "(N4) two refresh methods in one file: one body"; else no "(N4) $r"; fi
if r="$( chk bodyisrow "$TMP/ref.xml" refresh )"; then ok "(N4) $r (entity identity: the ranked row's own definition)"; else no "(N4) $r"; fi
if r="$( chk nobodyof "$TMP/struct.xml" screen )"; then ok "(N5) the struct screen (r1) is never the body"; else no "(N5) $r"; fi
while IFS='|' read -r k q; do
    if r="$( chk bodykinds "$TMP/$k.xml" )"; then :; else no "(N5) $k: $r"; fi
done <<<"$QUESTIONS"
ok "(N5) every <b t=> on the fixture answers is fn/method (FAIL lines above otherwise)"

# ── EP / DS / Q1: the runtime roots (each premise read off this binary's own answer, never assumed) ─────────────
Q_FORGE="How does the forge assemble a kiln job: scheduling glaze batches, tracking firing queues and recording kiln results?"
Q_RUN="How does the forge run a kiln job: scheduling glaze batches, tracking firing queues and recording kiln results?"
for r in cpp rs py ts go deep other; do rrun "$r" --for="$Q_FORGE" >"$TMP/q1.$r.xml"; done
rrun common --for="$Q_RUN" >"$TMP/q1.common.xml"
# Q1 premises re-anchored (lane hrr, train 31; rule 4): each premise is a SCORE rank (the class in the head tier 1..24, the
# member past it), which the head round-robin may display elsewhere (a distinct file's best row moves into r=1..8). The
# premises read the RIPWIRE_NO_HEAD_RR=1 twin of the same answer; every body / no-body assertion still reads the answer as served.
for r in cpp rs py ts go deep other; do RIPWIRE_NO_HEAD_RR=1 rrun "$r" --for="$Q_FORGE" >"$TMP/q1.$r.so.xml"; done
RIPWIRE_NO_HEAD_RR=1 rrun common --for="$Q_RUN" >"$TMP/q1.common.so.xml"
rrun cpp --for="$Q_FORGE" --legend=compact >"$TMP/q1.cpp.c.xml"
if r="$( chk bodiesattr "$TMP/q1.cpp.c.xml" pick member )" && r2="$( chk legend "$TMP/q1.cpp.c.xml" "${R3_STRS[@]}" )"; then
    ok "(D5/R3) pick=member body (C++): the compact legend reads pick= and says what reason=owner does not mean"
else no "(D5/R3) pick=member body (C++): ${r:-} ${r2:-}"; fi
rrun name --for="How does refresh repaint the screen?" >"$TMP/ep.name.xml"
rrun self --for="How does normalize flatten the tree?" >"$TMP/ep.self.xml"
rrun tsover --for="How does format render the value?" >"$TMP/ds.tsover.xml"
rrun cppvirt --for="How does the pool dispatch an edge?" >"$TMP/ds.cppvirt.xml"
rrun goiface --for="How does the tar packer pack the files?" >"$TMP/ds.goiface.xml"
rrun tsabs --for="How does the html printer print a document?" >"$TMP/ds.tsabs.xml"
for f in q1.cpp q1.rs q1.py q1.ts q1.go q1.deep q1.other q1.common ep.name ep.self ds.tsover ds.cppvirt ds.goiface ds.tsabs; do
    if r="$( chk sigsopen "$TMP/$f.xml" )"; then :; else no "(0) $f.xml: $r — the runtime root answered nothing"; fi
done
# EP1 namesake: ModalScreen.refresh's only edge is super().refresh() — a same-named owner, never an entry point
if r="$( chk rowis "$TMP/ep.name.xml" 3 Screen.refresh src/screens.py )" && [ "$( chk rankof "$TMP/ep.name.xml" refresh src/screens.py )" = 3 ] \
   && "$BIN" "$TMP/rt/name" --no-cache --callees=ModalScreen.refresh 2>/dev/null | grep -q '<s t="fn" n="Screen.refresh" p="src/screens.py:7"/>'; then
    if r="$( chk bodyat "$TMP/ep.name.xml" refresh src/screens.py 7 )"; then ok "(EP1) namesake: $r — the r3 row; r4's super().refresh() edge names the same word"; else no "(EP1) namesake: $r"; fi
else
    no "(EP1) premise: r3 Screen.refresh (l=7) and ModalScreen.refresh's edge to it — ${r:-not read}"
fi
# EP2 recursion: flatten (r2) calls only itself (the graph carries no self-edge: --callees count=0), normalize (r1) calls nothing
if r="$( chk rowis "$TMP/ep.self.xml" 1 normalize src/tree.py )" && r2="$( chk rowis "$TMP/ep.self.xml" 2 flatten src/tree.py )"; then
    if r="$( chk bodyat "$TMP/ep.self.xml" normalize src/tree.py 4 )"; then ok "(EP2) recursion: $r — flatten's recursion makes no entry point"; else no "(EP2) recursion: $r"; fi
else
    no "(EP2) premise: ${r:-} ${r2:-}"
fi
# DS1-DS4: the declaration outranks its definition; the body is the definition's
ds(){   # ds KEY ARM DECL_NAME DECL_PATH DECL_RANK DEF_PATH DEF_LINE [DECL_ROW_NAME]  (the <d> row spelling; the <b n=> body keeps DECL_NAME)
    local k="$1" arm="$2" n="$3" p="$4" dr="$5" dp="$6" dl="$7" rn="${8:-$3}"
    if ! r="$( chk rowis "$TMP/ds.$k.xml" "$dr" "$rn" "$p" )"; then no "($arm) premise: $r"; return; fi
    if [ "$( chk rowline "$TMP/ds.$k.xml" "$dr" )" = "$dl" ] && [ "$p" = "$dp" ]; then no "($arm) premise: the r$dr row IS the definition (l=$dl): no declaration outranks it"; return; fi
    if r="$( chk bodyat "$TMP/ds.$k.xml" "$n" "$dp" "$dl" )"; then ok "($arm) $k: $r — the definition, not the r$dr declaration"; else no "($arm) $k: $r"; fi
}
ds tsover DS1 format src/format.ts 1 src/format.ts 5
ds cppvirt DS2 Dispatch src/dispatch.h 1 src/dispatch.cc 2 PoolDispatcher::Dispatch
ds goiface DS3 Pack src/packer.go 1 src/packer.go 10 Packer.Pack
ds tsabs DS4 print src/printer.ts 1 src/printer.ts 6 Base.print   # js-def-naming: the TS declaration row names its class; the <b n=> body keeps print
# Q1 member owner: the head-tier class's member, defined past the head tier (no name owner exists)
q1(){   # q1 KEY CLASS_RANK_MAX CLASS CLASS_PATH MEMBER MEMBER_PATH MEMBER_LINE LANG
    local k="$1" cmax="$2" c="$3" cp="$4" m="$5" mp="$6" ml="$7" lang="$8" cr mr
    cr="$( chk rankof "$TMP/q1.$k.so.xml" "$c" "$cp" )"; mr="$( chk rankof "$TMP/q1.$k.so.xml" "$m" "$mp" )"   # score ranks (the twin)
    case "$cr$mr" in *[!0-9]*|'') no "(Q1) $k premise: unreadable ranks class=$cr member=$mr"; return;; esac
    if [ "$cr" -lt 1 ] || [ "$cr" -gt "$cmax" ] || { [ "$mr" -ge 1 ] && [ "$mr" -le 24 ]; }; then
        no "(Q1) $k premise: class $c r$cr (wanted 1..$cmax), member $m r$mr (wanted past the head tier)"; return
    fi
    if r="$( chk bodyat "$TMP/q1.$k.xml" "$m" "$mp" "$ml" )" && r2="$( chk bodiesattr "$TMP/q1.$k.xml" pick member )"; then
        ok "(Q1) $lang: $r ($r2; class r$cr, member r${mr/#0/>40})"
    else
        no "(Q1) $lang: ${r:-} ${r2:-}"
    fi
    if r="$( chk nobodyof "$TMP/q1.$k.xml" "$c" )"; then :; else no "(Q1) $lang: the class/type is served: $r"; fi
}
q1 cpp 24 Forge src/forge.h Assemble src/forge.cc 4 "C++ out of line (sc=)"
q1 rs 24 Forge src/forge.rs assemble src/forge.rs 10 "Rust impl (sc=)"
q1 py 24 Forge src/forge.py assemble src/forge.py 11 "Python (sc=)"
q1 ts 24 Forge src/forge.ts assemble src/forge.ts 9 "TS class (span)"
# Go receiver (#403): this was the named Go floor (no member body while Go methods carried no scope); with the receiver
# scope the member owner applies to Go as to the rows above, and q1 still asserts the type itself is never served.
q1 go 24 Forge src/forge.go Assemble src/forge.go 14 "Go receiver (sc=)"
# near misses
cr="$( chk rankof "$TMP/q1.common.so.xml" Forge src/forge.h )"; mr="$( chk rankof "$TMP/q1.common.so.xml" Run src/forge.cc )"
if [ "$cr" = 1 ] && [ "$mr" -gt 24 ] 2>/dev/null; then
    if r="$( chk nobodyof "$TMP/q1.common.xml" Run )"; then ok "(Q1) near miss: a common-word member (Run, 'run') is never the member owner"; else no "(Q1) common-word member: $r"; fi
else
    no "(Q1) common-word premise: Forge r$cr Run r$mr"
fi
cr="$( chk rankof "$TMP/q1.deep.so.xml" Forge src/forge.h )"
if [ "$cr" -gt 24 ] 2>/dev/null; then
    if r="$( chk nobodyof "$TMP/q1.deep.xml" Assemble )"; then ok "(Q1) near miss: class Forge r$cr (in the pool, past the head tier) donates no member"; else no "(Q1) class past the head tier: $r"; fi
else
    no "(Q1) deep premise: Forge r$cr, wanted 25..40"
fi
sr="$( chk rankof "$TMP/q1.other.so.xml" Assemble src/smelter.cc )"; fr="$( chk rankof "$TMP/q1.other.so.xml" Assemble src/forge.cc )"
if [ "$sr" -gt 24 ] 2>/dev/null && [ "$fr" -gt "$sr" ] 2>/dev/null && [ "$( chk rankof "$TMP/q1.other.so.xml" Forge src/forge.h )" = 1 ]; then
    if r="$( chk bodyat "$TMP/q1.other.xml" Assemble src/forge.cc 4 )"; then ok "(Q1) entity identity: $r — Forge's member, not Smelter::Assemble (r$sr, outranks it at r$fr)"; else no "(Q1) entity identity: $r"; fi
else
    no "(Q1) other-class premise: Smelter::Assemble r$sr, Forge::Assemble r$fr"
fi

# ── E: explicit targets (reserve-sections-first) ───────────────────────────────────────────────────────────
run --for="$T_D" --token-budget=5000 >"$TMP/e5000.xml"
if r="$( chk body "$TMP/e5000.xml" jwt src/middleware/jwt/jwt.ts "getCookie" )"; then ok "(E1) --token-budget=5000: $r"; else no "(E1) --token-budget=5000: $r"; fi
# E1-E3 order-prefix clauses (lane hrr, train 31; rule 4): each runs UNCHANGED as a RIPWIRE_NO_HEAD_RR=1 twin (against d.so.xml);
# with the reorder on, "h" asserts the rows are a SET prefix of the default (score ranks 1..K: no gap, no repeat on next=)
RIPWIRE_NO_HEAD_RR=1 run --for="$T_D" --token-budget=5000 >"$TMP/e5000.so.xml"
if r="$( chk prefix "$TMP/e5000.so.xml" "$TMP/d.so.xml" )"; then ok "(E1) [RIPWIRE_NO_HEAD_RR=1 twin] --token-budget=5000: $r"; else no "(E1) [RIPWIRE_NO_HEAD_RR=1 twin] --token-budget=5000: $r"; fi
if r="$( chk setprefix "$TMP/e5000.xml" "$TMP/d.xml" "$TMP/d.so.xml" )"; then ok "(E1h) head round-robin on, --token-budget=5000: $r"; else no "(E1h) head round-robin on, --token-budget=5000: $r"; fi
if r="$( chk over "$TMP/e5000.xml" )"; then ok "(E1) --token-budget=5000: no over_ceiling"; else no "(E1) $r"; fi
run --for="$T_D" --token-budget=400 >"$TMP/e400.xml"
if r="$( chk rootattr "$TMP/e400.xml" bodies 0 )" && r2="$( chk rootattr "$TMP/e400.xml" reason budget )"; then ok "(E2) --token-budget=400: bodies=0 reason=budget"; else no "(E2) --token-budget=400: ${r:-} ${r2:-}"; fi
if r="$( chk bodiesnext "$TMP/e400.xml" '^--expand=src/middleware/jwt/jwt\.ts:' )"; then ok "(E2) --token-budget=400: the skipped slot discloses itself, recoverable: $r"; else no "(E2) --token-budget=400: $r"; fi
RIPWIRE_NO_HEAD_RR=1 run --for="$T_D" --token-budget=400 >"$TMP/e400.so.xml"
if r="$( chk prefix "$TMP/e400.so.xml" "$TMP/d.so.xml" )"; then ok "(E2) [RIPWIRE_NO_HEAD_RR=1 twin] --token-budget=400: $r"; else no "(E2) [RIPWIRE_NO_HEAD_RR=1 twin] --token-budget=400: $r"; fi
if r="$( chk setprefix "$TMP/e400.xml" "$TMP/d.xml" "$TMP/d.so.xml" )"; then ok "(E2h) head round-robin on, --token-budget=400: $r"; else no "(E2h) head round-robin on, --token-budget=400: $r"; fi
# E2b (CodeRabbit, #413): the skipped slot's next= is built by nextFlag, so a path a shell would split pastes as ONE argument
rm -rf "$TMP/spc"; cp -R "$FIX" "$TMP/spc" && mv "$TMP/spc/src/middleware/jwt" "$TMP/spc/src/middleware/j wt"
"$BIN" "$TMP/spc" --no-cache --for="$T_D" --token-budget=400 >"$TMP/e400spc.xml" 2>/dev/null
if r="$( chk bodiesnext "$TMP/e400spc.xml" "^--expand='src/middleware/j wt/jwt\.ts:[0-9]+:jwt'\$" )" \
   && [ "$( python3 -c 'import html,re,shlex,sys; m=re.search(r"<bodies\b[^>]*\snext=\"([^\"]*)\"", open(sys.argv[1]).read()); print(len(shlex.split(html.unescape(m.group(1)))) if m else 0)' "$TMP/e400spc.xml" )" = 1 ]; then
    ok "(E2b) a path with a space: the skipped slot's next= is quoted and splits to one argument: $r"
else no "(E2b) a path with a space: ${r:-the next= splits into more than one argument}"; fi
prev_rows=0; prev_b=0; mono=1; nflag=""
for n in 300 500 800 1200 2000 3000 5000 8000 1000000; do
    run --for="$T_D" --token-budget=$n >"$TMP/s$n.xml"; runoff --for="$T_D" --token-budget=$n >"$TMP/s$n.off.xml"
    rws="$( chk nrows "$TMP/s$n.xml" )"; rwo="$( chk nrows "$TMP/s$n.off.xml" )"; bb="$( chk bodybytes "$TMP/s$n.xml" )"
    case "$rws$rwo$bb" in *[!0-9]*|'') no "(E3) N=$n: unreadable counts rows=$rws off=$rwo body=$bb"; mono=0; continue;; esac
    RIPWIRE_NO_HEAD_RR=1 run --for="$T_D" --token-budget=$n >"$TMP/s$n.so.xml"
    if ! chk prefix "$TMP/s$n.so.xml" "$TMP/d.so.xml" >/dev/null; then no "(E3) [RIPWIRE_NO_HEAD_RR=1 twin] N=$n: rows are not a rank prefix of the default rows"; mono=0; fi
    if ! chk setprefix "$TMP/s$n.xml" "$TMP/d.xml" "$TMP/d.so.xml" >/dev/null; then no "(E3h) head round-robin on, N=$n: rows are not a SET prefix of the default rows"; mono=0; fi
    if ! chk over "$TMP/s$n.xml" >/dev/null; then no "(E3) N=$n: over_ceiling on the root"; mono=0; fi
    [ "$rws" -lt "$prev_rows" ] && { no "(E3) N=$n: rows $rws < $prev_rows at the smaller N"; mono=0; }
    [ "$bb" -lt "$prev_b" ] && { no "(E3) N=$n: body $bb B < $prev_b B at the smaller N"; mono=0; }
    [ "$rws" -gt "$rwo" ] && { no "(E3) N=$n: rows $rws > slot-off $rwo (the body is reserved first, it never adds rows)"; mono=0; }
    prev_rows=$rws; prev_b=$bb; nflag="$nflag $n:$rws/$rwo/${bb}B"
done
if [ "$mono" = 1 ]; then ok "(E3) sweep rows(slot)/rows(off)/body:$nflag — rank prefix ([RIPWIRE_NO_HEAD_RR=1 twin]) and set prefix (E3h, reorder on), monotone, <= slot-off, no over_ceiling"; fi
cdw=0; cdd=0
chk cdata "$TMP/s1000000.xml" jwt >"$TMP/cd.wide" 2>/dev/null || cdw=1
chk cdata "$TMP/d.xml" jwt >"$TMP/cd.default" 2>/dev/null || cdd=1
if [ "$cdw$cdd" = "00" ] && [ -s "$TMP/cd.wide" ] && cmp -s "$TMP/cd.wide" "$TMP/cd.default"; then ok "(E3) N=1000000: the body equals the default answer's body"; else no "(E3) N=1000000: no body, or it differs from the default answer's"; fi

# E4: T_REF at N=800 — slot-off serves rows past the cut there and the share the rows at the cut leave holds the small body:
# the body is reserved first and the rows give way (review R3). (T_D's 2.7 KB jwt body is skipped below N=4800: its own arm, E2/E3.)
run --for="$T_REF" --token-budget=800 >"$TMP/e4.xml"; runoff --for="$T_REF" --token-budget=800 >"$TMP/e4.off.xml"
if r="$( chk paidinside "$TMP/e4.xml" "$TMP/e4.off.xml" 800 )"; then ok "(E4) --token-budget=800: $r"; else no "(E4) --token-budget=800: $r"; fi

# ── MC: MCP for parity ─────────────────────────────────────────────────────────────────────────────────────
mcpfor "$T_D" >"$TMP/m.d.xml"; mcpfor "$T_NOCUE" >"$TMP/m.nocue.xml"; mcpfor "$T_D" '{"budget_tokens":400}' >"$TMP/m.d400.xml"
for f in m.d m.nocue m.d400; do
    if r="$( chk sigsopen "$TMP/$f.xml" )"; then :; else no "(MC0) MCP $f answered nothing: $r"; fi
done
if r="$( chk body "$TMP/m.d.xml" jwt src/middleware/jwt/jwt.ts "getCookie" "HTTPException(401" "ctx.set('jwtPayload'" )"; then ok "(MC1) MCP for: $r"; else no "(MC1) MCP for: $r"; fi
cdm=0; chk cdata "$TMP/m.d.xml" jwt >"$TMP/cd.mcp" 2>/dev/null || cdm=1
if [ "$cdm$cdd" = "00" ] && [ -s "$TMP/cd.mcp" ] && cmp -s "$TMP/cd.mcp" "$TMP/cd.default"; then ok "(MC2) MCP for: the body equals the CLI body byte for byte"; else no "(MC2) MCP for: no body, or it differs from the CLI's"; fi
if r="$( chk nobody "$TMP/m.nocue.xml" )"; then ok "(MC3) MCP for, no cue: no body"; else no "(MC3) $r"; fi
if r="$( chk nobodyof "$TMP/m.d400.xml" jwt )" && r2="$( chk bodiesnext "$TMP/m.d400.xml" '^--expand=src/middleware/jwt/jwt\.ts:' )"; then ok "(MC4) MCP budget_tokens=400: no body, the owner recoverable by next=--expand"; else no "(MC4) MCP budget_tokens=400: ${r:-} ${r2:-}"; fi

# MC5: MCP/CLI drift on the cut and on the pick (review R4)
mcpfor "$T_BIG" >"$TMP/m.big.xml"; mcpfor "$T_RS" >"$TMP/m.rs.xml"
for f in m.big m.rs; do if r="$( chk sigsopen "$TMP/$f.xml" )"; then :; else no "(MC0) MCP $f answered nothing: $r"; fi; done
mc5=0
for a in truncated lines next; do
    vc="$( grep -o '<b [^>]*n="render_screen"[^>]*' "$TMP/big.xml" | grep -o " $a=\"[^\"]*\"" )"; vm="$( grep -o '<b [^>]*n="render_screen"[^>]*' "$TMP/m.big.xml" | grep -o " $a=\"[^\"]*\"" )"
    if [ -z "$vc" ] || [ "$vc" != "$vm" ]; then no "(MC5) MCP cut: <b render_screen$vm> vs CLI <b render_screen$vc>"; mc5=1; fi
done
cbc=0; cbm=0
chk cdata "$TMP/big.xml" render_screen >"$TMP/cd.big.cli" 2>/dev/null || cbc=1
chk cdata "$TMP/m.big.xml" render_screen >"$TMP/cd.big.mcp" 2>/dev/null || cbm=1
if [ "$cbc$cbm" = "00" ] && [ -s "$TMP/cd.big.cli" ] && cmp -s "$TMP/cd.big.cli" "$TMP/cd.big.mcp"; then :; else no "(MC5) MCP cut body differs from the CLI's (or is absent)"; mc5=1; fi
[ "$mc5" = 0 ] && ok "(MC5) MCP T_BIG: the same head cut as the CLI (truncated=/lines=/next= and CDATA)"
r=""; r2=""
if r="$( chk body "$TMP/m.rs.xml" index src/rs/indexer.rs "let order = walk(" )" && r2="$( chk nobodyof "$TMP/m.rs.xml" walk )"; then ok "(MC5) MCP T_RS: $r — the entry point, as the CLI"; else no "(MC5) MCP T_RS: ${r:-} ${r2:-}"; fi
# E4 on MCP: budget_tokens=800 pays the body inside the target too
mcpfor "$T_REF" '{"budget_tokens":800}' >"$TMP/m.e4.xml"; mcpforoff "$T_REF" '{"budget_tokens":800}' >"$TMP/m.e4.off.xml"
if r="$( chk paidinside "$TMP/m.e4.xml" "$TMP/m.e4.off.xml" 800 )"; then ok "(E4) MCP budget_tokens=800: $r"; else no "(E4) MCP budget_tokens=800: $r"; fi
# EV1: the owner-hop env never reaches the slot (review R6: the shared owner helper carries no early return)
RIPWIRE_NO_OWNER_HOP=1 "$BIN" "$FIX" --cache="$TMP/rw.cache" --for="$T_D" 2>/dev/null >"$TMP/d.noown.xml"
bs1=0; bs2=0
chk bodiessec "$TMP/d.xml" >"$TMP/bs.default" 2>/dev/null || bs1=1
chk bodiessec "$TMP/d.noown.xml" >"$TMP/bs.noown" 2>/dev/null || bs2=1
if [ "$bs1$bs2" = "00" ] && cmp -s "$TMP/bs.default" "$TMP/bs.noown"; then ok "(EV1) RIPWIRE_NO_OWNER_HOP=1: <bodies> byte-identical to the default"; else no "(EV1) RIPWIRE_NO_OWNER_HOP=1 changed or dropped the <bodies> element"; fi

# ── M: mutation controls — the checkers reject canned pre-change shapes ─────────────────────────────────────
printf '%s' '<ctx task="t" bundle="compact" bodies="0" reason="compact-route" est_tokens="10"><!-- l --><sigs><d l="12" n="jwt" p="src/middleware/jwt/jwt.ts" r="1">x</d></sigs></ctx>' >"$TMP/c1.xml"
if chk body "$TMP/c1.xml" jwt src/middleware/jwt/jwt.ts getCookie >/dev/null 2>&1; then no "(M1) the body checker accepted a canned no-body answer"; else ok "(M1) the body checker rejects a canned no-body answer"; fi
printf '%s' '<ctx task="t" bodies="1"><sigs><d l="4" n="roundtrip" p="tests/test_tokens.py" r="1">x</d></sigs><bodies shown="1" total="1" capped="0"><b t="fn" l="4" p="tests/test_tokens.py" n="roundtrip"><![CDATA[def roundtrip(text):]]></b></bodies></ctx>' >"$TMP/c2.xml"
if chk nobodyat "$TMP/c2.xml" '(^|/)tests?/' >/dev/null 2>&1; then no "(M2) the tests/ checker accepted a canned tests/ body"; else ok "(M2) the tests/ checker rejects a canned tests/ body"; fi
printf '%s' '<ctx task="t" bodies="1"><sigs><d l="7" n="render_screen" p="src/c/render.c" r="1">x</d></sigs><bodies shown="1" total="1" capped="0"><b t="fn" l="7" p="src/c/render.c" n="render_screen"><![CDATA[void]]></b></bodies></ctx>' >"$TMP/c3.xml"
if chk bodyattr "$TMP/c3.xml" render_screen truncated '^1$' >/dev/null 2>&1 || chk nextof "$TMP/c3.xml" render_screen >/dev/null 2>&1; then no "(M3) the cut checkers accepted a silent partial body"; else ok "(M3) the cut checkers reject a partial body with no truncated=/next="; fi
sed 's/<hops /<hops x="1" /' "$TMP/d.off.xml" >"$TMP/c4.xml"
if grep -q '<hops ' "$TMP/d.off.xml"; then
    if chk sectionsame "$TMP/c4.xml" "$TMP/d.off.xml" >/dev/null 2>&1; then no "(M4) the section checker missed a changed <hops>"; else ok "(M4) the section checker sees a changed <hops>"; fi
else
    no "(M4) premise: T-D has no <hops> element to mutate"
fi

# M5: a body appended AFTER the row cut (rows unchanged, est_tokens grown by the body) is rejected by the E4 checker
python3 - "$TMP/e4.off.xml" "$TMP/c5.xml" <<'PY2'
import re, sys
t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
body = '<bodies shown="1" total="1" capped="0" pick="name"><b t="fn" l="12" p="src/middleware/jwt/jwt.ts" n="jwt"><![CDATA[' + "x" * 3000 + ']]></b></bodies>'
t = t.replace("</ctx>", body + "</ctx>")
t = re.sub(r'est_tokens="(\d+)"', lambda m: 'est_tokens="%d"' % (int(m.group(1)) + 790), t, count=1)
open(sys.argv[2], "w", encoding="utf-8").write(t)
PY2
if chk paidinside "$TMP/c5.xml" "$TMP/e4.off.xml" 800 >/dev/null 2>&1; then no "(M5) the E4 checker accepted a body appended after the row cut"; else ok "(M5) the E4 checker rejects a body appended after the row cut"; fi

# ── X: hygiene ──────────────────────────────────────────────────────────────────────────────────────────────
run --for="$T_D" >"$TMP/d2.xml"
if cmp -s "$TMP/d.xml" "$TMP/d2.xml"; then ok "(X1) T-D deterministic x2"; else no "(X1) T-D differs between two runs"; fi
if command -v xmllint >/dev/null 2>&1; then
    for f in d d.c q1.cpp.c big hyd py rs cpp go m.d e400; do
        if xmllint --noout "$TMP/$f.xml" 2>/dev/null; then ok "(X2) $f.xml is well-formed XML"; else no "(X2) $f.xml failed xmllint"; fi
    done
else
    skip "(X2) xmllint not installed — well-formedness not checked here"
fi
for f in d d.c big hyd e400; do
    if r="$( chk nodashes "$TMP/$f.xml" )"; then ok "(X3) $f.xml: no '--' inside an XML comment"; else no "(X3) $f.xml: $r"; fi
done

# ── I: optional byte identity against the pre-change binary where the slot must not fire ─────────────────────
# (FX) [G] body-fold: with the fold on (the default), the slot's <bodies> element is byte-identical to the fold-off answer's and the
#      owner's body is never repeated inside the <fold>
( unset RIPWIRE_NO_BODY_FOLD; "$BIN" "$FIX" --no-cache --for="$T_D" ) >"$TMP/fx.on" 2>/dev/null
"$BIN" "$FIX" --no-cache --for="$T_D" >"$TMP/fx.off" 2>/dev/null
if python3 - "$TMP/fx.on" "$TMP/fx.off" <<'PYFX'
import re, sys
on, off = open(sys.argv[1]).read(), open(sys.argv[2]).read()
b_on, b_off = re.search(r'<bodies .*?</bodies>', on, re.S), re.search(r'<bodies .*?</bodies>', off, re.S)
f = re.search(r'<fold .*?</fold>', on, re.S)
if not (b_on and b_off and f) or b_on.group(0) != b_off.group(0): sys.exit(1)
own = re.search(r'<b t="[^"]*" l="(\d+)" p="([^"]*)"', b_on.group(0))
sys.exit(1 if own and f'l="{own.group(1)}" p="{own.group(2)}"' in f.group(0) else 0)
PYFX
then ok "(FX) fold on: the slot's <bodies> is the fold-off answer's byte for byte, and the owner is not repeated in the fold"; else no "(FX) the fold changed the slot's <bodies>, repeated the owner, or rode no <fold>"; fi

if [ -n "${RIPWIRE_BASE_BIN:-}" ] && [ -x "${RIPWIRE_BASE_BIN}" ]; then
    RIPWIRE_NO_BODY_SLOT=1 "$BIN" "$FIX" --no-cache --for="$T_D" 2>/dev/null | strip_at >"$TMP/i.head"
    "$RIPWIRE_BASE_BIN" "$FIX" --no-cache --for="$T_D" 2>/dev/null | strip_at >"$TMP/i.base"
    if [ -s "$TMP/i.base" ] && cmp -s "$TMP/i.base" "$TMP/i.head"; then ok "(I0) RIPWIRE_NO_BODY_SLOT=1 T-D == the base binary byte for byte"; else no "(I0) RIPWIRE_NO_BODY_SLOT=1 T-D differs from the base binary"; fi
    i=0
    while IFS= read -r line; do              # one argv per line, arguments separated by '|' (values may hold spaces)
        i=$(( i + 1 ))
        IFS='|' read -r -a argv <<<"$line"
        "$RIPWIRE_BASE_BIN" "$FIX" --no-cache "${argv[@]}" 2>/dev/null | strip_at >"$TMP/i.base"
        "$BIN"              "$FIX" --no-cache "${argv[@]}" 2>/dev/null | strip_at >"$TMP/i.head"
        if [ ! -s "$TMP/i.base" ]; then no "(I$i) the base binary answered nothing for: $line"; continue; fi
        if cmp -s "$TMP/i.base" "$TMP/i.head"; then ok "(I$i) byte-identical: $line"; else no "(I$i) differs from the base binary: $line"; fi
    done <<'ARGV'
--for=JWT middleware token verification
--for=Where does the JWT middleware verify a token?
--for=How does the JWT middleware verify a token?|--signatures-only
--for=How does the JWT middleware verify a token?|--json
--for=How does the JWT middleware verify a token?|--auto-bodies
--for=How does the JWT middleware verify a token?|--detail=1
--for=verify
--callers=verify
--expand=src/middleware/jwt/jwt.ts:jwt
ARGV
    RIPWIRE_NO_BODY_SLOT=1 "$BIN" "$FIX" --no-cache --for="$T_D" --token-budget=3000 2>/dev/null | strip_at >"$TMP/i.head"
    "$RIPWIRE_BASE_BIN" "$FIX" --no-cache --for="$T_D" --token-budget=3000 2>/dev/null | strip_at >"$TMP/i.base"
    if [ -s "$TMP/i.base" ] && cmp -s "$TMP/i.base" "$TMP/i.head"; then ok "(I10) --token-budget=3000 with RIPWIRE_NO_BODY_SLOT=1 == the base binary (no reserve without the slot)"; else no "(I10) --token-budget=3000 RIPWIRE_NO_BODY_SLOT=1 differs from the base binary"; fi
else
    skip "(I) RIPWIRE_BASE_BIN unset or not executable — base-binary byte identity not run here"
fi

exit $fail

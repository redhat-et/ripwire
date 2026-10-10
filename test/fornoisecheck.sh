#!/usr/bin/env bash
# fornoisecheck.sh — --for on the SUBTOKEN route: task-frame words, evidence tiers, vendored/benchmark
# tiers, and the ONE body slot of a "how does" question (lane/for-noise-body-slot, train 27 #4;
# pre-registered in $ORCH/reports/for-noise-body-slot.md BEFORE the ranking code; reports/ideas-fable-26b.md idea #2).
#
# SCOPE NOW (lane/for-noise, train 27, owner plan 2026-10-10): A and C ship; B (evidence tier) and D (body slot) are
# OUT of scope and their contract arms are DEFERRED — kept here, written to the early gates review's 8 changes, and
# run only with FORNOISE_BD=1 (otherwise each block SKIPs by name). Their GREEN twins (no body without a cue, none
# under --signatures-only/--json/MCP, ...) stay ACTIVE: they hold for a binary with no body slot too, and a leaked
# body would turn them red. Premises re-shown on the 26c head 4c38d363 (checklist 28).
#
# THE FOUR CONTRACTS THIS PINS (every lettered arm marked RED was run red on the pre-change binary
# 0852bc0f; the GREEN ones are twins of what must still hold — PROCESS rule 4, no gate erosion):
#
#   A  TASK-FRAME WORDS. On the subtoken+body route the question's own frame — "how does", "I want to
#      write a new", "which existing … should I read first" — is scored at kTaskFrameTermWeight (a quarter),
#      never dropped (the LB-1/LB-3/term-margin lesson: a reduced-weight term is the only shape with an
#      unexhausted path, docs/EVALS.md). The sole-anchor guard: when EVERY present term is a frame word the
#      ranking is the historical one byte for byte. Disclosed on the root as frame_terms=N (present-only,
#      N = frame words that were actually present and down-weighted) and defined in both legend dialects.
#      Name-exact route, --no-route, --query, --recall, --pack-task: byte-identical.
#   B  EVIDENCE TIER. A head candidate (positive score, within the kForLensDefaultTopN pool, re-audited
#      until the head is stable) whose NAME carries no kept task word and whose kept task words occur ONLY
#      inside its doc comment, comments or string literals (tree-sitter span tiers, ingest.h spanTiersOfFiles;
#      an unparsed file counts as code = never demoted) scores at kRankTierDemoMul. A name match is never
#      demoted. Disclosed as evidence_demoted=N on the root (and on --format=candidates).
#   C  TIERS AND DUPLICATES. benchmarks/, benchmark/, examples/, docs/examples/ and *.d.ts rows take the §P4
#      tier factor on --for unless the task names that family; a row whose file is BYTE-IDENTICAL to another
#      row's file with the same name/kind/signature is collapsed into the better-placed copy (not-demoted,
#      then fewer path segments, then a src/|lib/ first segment, then path order) with also="OTHER PATH"
#      and <sigs dups_collapsed=N>. Two same-named symbols in DIFFERENT files are two rows (entity identity).
#      tests/ keeps its existing tier (twin).
#   D  THE BODY SLOT. A how-does question (taskroute.h kExplanatoryCues, word-bounded) on the CLI XML
#      compact route serves ONE body: the OWNER — a callable, non-test, body-carrying head candidate whose
#      whole folded name equals a kept task word; among owners the one that calls another owner wins (the
#      entry point), else the best rank; with no owner, the best-ranked callable sharing a task subtoken.
#      <bodies shown="1"><b t= l= p= n=> via packBodies, the expand shape; larger than kForBodySlotMaxBytes
#      → head-cut at a line end with truncated="1" lines= next=--expand= (cutfix-bodies vocabulary). PAID IN
#      SIG ROWS: the body's bytes come off the sig budget before the ladder runs, the displaced rows stay
#      recoverable through the capped <sigs next=> (knob-honesty-068). Under an explicit ceiling the same
#      payment applies inside the ceiling; when the ceiling leaves no room past the top-4 rows the slot is
#      skipped with bodies="0" reason="budget". Root: bundle="compact" bodies="1". No slot without a cue,
#      under --signatures-only / --json / MCP for (signature postures — a named floor), or on --auto-bodies.
#
# Arms (colour on the pre-change binary in brackets):
#   A1 [RED]  T-A: no write* row at r<=25 (idea #2 kill (3))        A2 [RED]  T-A: Router (src/router.ts) r<=3
#   A3 [RED]  T-D: SAMPLE_QUESTIONS (frame words in strings) not r<=10   A4 [GREEN] sole-anchor: "how do I write" keeps write r=1, no frame_terms
#   A5 [RED]  T-A root frame_terms=12 EXACT + legend (full and compact) A6/A7/A8 [GREEN] name-exact / --no-route / --query carry none of the new attributes
#   A9 [RED]  R2 twin: "how does `write` flush the stream" keeps write r=1 WITH frame_terms riding (a backticked frame word stays)
#   A10 [GREEN] demotion is not a cut: the down-weighted / demoted rows still carry s>0 in --format=candidates --top-k=60
#   B1 [RED]  T-B: listProjectFiles and filterFiles both r<=3          B2 [RED]  T-B: the three doc/string-only rows rank below both
#   B3 [RED]  T-B root evidence_demoted>=3 + legend                   B4 [GREEN] SCANNER_NOTE (name match) is not demoted: r<=5
#   B5 [RED]  --format=candidates carries frame_terms= and evidence_demoted=
#   C1 [RED]  T-A: benchmarks RouterInterface below Router/SmartRouter  C2 [RED] T-A: RouterLike (.d.ts) below Router
#   C3 [RED]  twin matcher: src/ copy ranks above the examples/ copy    C4 [RED] T-A: upgradeWebSocket ONE row + also= + dups_collapsed
#   C5 [GREEN] two `match` methods in different files stay two rows    C6 [GREEN] tests/ row below the src/ owner (T-PY)
#   C4 also pins the KEEPER: p="src/adapter/deno/websocket.ts" (the src/ rule) and also="adapters/deno/src/websocket.ts"
#   C7 [GREEN] family lift: "how does the benchmarks tool wrap a router" keeps RouterInterface not below Router
#   D1 [RED]  T-D: bodies="1", <b n="jwt"> holding getCookie / HTTPException(401 / ctx.set('jwtPayload' (idea #2 kill (1))
#   D2 [RED]  T-D: the body is jwt (calls verify), not verify (r=1)     D3 [RED] T-D: sigs shown < --signatures-only shown; capped next= present
#   D4 [RED]  --token-budget=3000: bodies="1", est_tokens within 1.15x  D5 [GREEN] --token-budget=400: bodies="0", no <b, >=1 row
#   D6 [GREEN] no cue -> bodies="0" reason="compact-route", no <bodies>  D7 [GREEN] --signatures-only / --json / --auto-bodies shapes unchanged
#   D8 [RED]  T-PY: body of `apply` (method; the class is not callable)  D9 [RED] T-C: body of cmd_find_target (identifier word = content)
#   D10 [RED] oversized owner: truncated="1" lines= next=--expand=       D11 [GREEN] MCP for: no body slot
#   D12 [RED] compact legend defines b t= n= p= l= when a body rides; new attributes defined wherever they ride
#   M1-M3     mutation controls: the checkers reject canned pre-change shapes (a gate that cannot go red is none)
#   X1-X3     determinism x2, xmllint on both dialects, no `--` inside an XML comment (checklist 25)
#   I1-I10    [optional, RIPWIRE_BASE_BIN=<pre-change binary>] byte identity on the untouched verbs (+ --grep/--uses: pathTierOf leak)
#   deferred (FORNOISE_BD=1): B1-B3, B5b, B6 (parser-vs-heuristic shapes), D1 body + l=, D3' (re-anchored), D4, D5 reason=budget,
#             D8-D10 (+ p= of the .c file, never the .h prototype), D12 compact legend, D13 fallback owner (a)-(c),
#             D14 named identifier (`verify`), D15 sole-anchor bodies, D16 body_next= on --json / MCP
#
# Usage:  bash test/fornoisecheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/fornoisecheck.sh
# BIN is $1, else RIPWIRE_BIN, else build/ripwire; the first output line names the binary used.
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "fornoisecheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; return 0; }
BD="${FORNOISE_BD:-0}"   # 1 = run the deferred B/D contract arms (lane/for-noise ships A and C only)

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
cd "$ROOT"
FIX="$ROOT/test/fornoisefix"
[ -d "$FIX/src" ] || { echo "fixture $FIX missing"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# ── the checker: one Python reader of a --for answer, one verdict per call (exit 0 = holds) ─────────────────
cat > "$TMP/chk.py" <<'PY'
import html, json, re, sys
cmd, path = sys.argv[1], sys.argv[-1]      # the answer FILE is always the last argument
args = sys.argv[2:-1]
t = open(path, encoding="utf-8", errors="replace").read()
def root():
    m = re.search(r'<ctx ([^>]*)>', t)
    return dict(re.findall(r'(\w+)="([^"]*)"', m.group(1))) if m else {}
def sigs():
    m = re.search(r'<sigs ([^>]*)>', t)
    return dict(re.findall(r'(\w+)="([^"]*)"', m.group(1))) if m else {}
def rows():
    out = []
    for d in re.finditer(r'<d ([^>]*)>', t):
        a = dict(re.findall(r'(\w+)="([^"]*)"', d.group(1)))
        out.append((int(a.get("r", "0") or 0), a.get("n", ""), a.get("p", ""), a))
    return out
def rank(name, p=None):
    for r, n, pp, a in rows():
        if n == name and (p is None or pp == p):
            return r
    return 0
def legend():
    return " ".join(re.findall(r'<!--(.*?)-->', t, re.S))
def fail(msg):
    print(msg); sys.exit(1)
if cmd == "norow":                      # norow REGEX MAXR : no <d n=~REGEX> with r<=MAXR
    rx, maxr = re.compile(args[0]), int(args[1])
    bad = [(r, n) for r, n, p, a in rows() if rx.search(n) and r <= maxr]
    if bad: fail("rows matched %s at r<=%d: %s" % (args[0], maxr, bad))
elif cmd == "rankle":                   # rankle NAME MAXR [PATH]
    r = rank(args[0], args[2] if len(args) > 2 else None)
    if r == 0 or r > int(args[1]): fail("%s rank=%s, wanted <=%s" % (args[0], r, args[1]))
    print(r)
elif cmd == "below":                    # below NAME1 NAME2 [PATH1] : NAME1 absent or ranked below NAME2 (both present => strict)
    r1 = rank(args[0], args[2] if len(args) > 2 else None); r2 = rank(args[1])
    if r2 == 0: fail("%s absent — nothing to compare %s against" % (args[1], args[0]))
    if r1 != 0 and r1 < r2: fail("%s r=%d is ABOVE %s r=%d" % (args[0], r1, args[1], r2))
    print("%s r=%s below %s r=%d" % (args[0], r1 or "absent", args[1], r2))
elif cmd == "rootattr":                 # rootattr ATTR [REGEX]
    v = root().get(args[0])
    if v is None: fail("root has no %s=" % args[0])
    if len(args) > 1 and not re.fullmatch(args[1], v): fail("%s=%r does not match %s" % (args[0], v, args[1]))
    print("%s=%s" % (args[0], v))
elif cmd == "rootattrge":               # rootattrge ATTR N
    v = root().get(args[0])
    if v is None or not v.isdigit() or int(v) < int(args[1]): fail("root %s=%r, wanted >= %s" % (args[0], v, args[1]))
    print("%s=%s" % (args[0], v))
elif cmd == "noattr":                   # noattr ATTR... : none of these on the root OR the sigs tag OR any row
    present = [a for a in args if a in root() or a in sigs() or any(a in row[3] for row in rows())]
    if present: fail("attributes present: %s" % present)
elif cmd == "sigsattrge":               # sigsattrge ATTR N
    v = sigs().get(args[0])
    if v is None or not v.isdigit() or int(v) < int(args[1]): fail("<sigs %s=%r>, wanted >= %s" % (args[0], v, args[1]))
    print("%s=%s" % (args[0], v))
elif cmd == "sigsattr":                 # sigsattr ATTR [REGEX]
    v = sigs().get(args[0])
    if v is None: fail("<sigs> has no %s=" % args[0])
    if len(args) > 1 and not re.search(args[1], v): fail("<sigs %s=%r> does not match %s" % (args[0], v, args[1]))
    print("%s=%s" % (args[0], v[:80]))
elif cmd == "shown":                    # shown : prints <sigs shown=> or the <d> count
    s = sigs().get("shown"); print(s if s is not None else len(rows()))
elif cmd == "count":                    # count NAME : number of <d n=NAME> rows
    print(sum(1 for r, n, p, a in rows() if n == args[0]))
elif cmd == "rowattr":                  # rowattr NAME ATTR [REGEX]
    hit = [a for r, n, p, a in rows() if n == args[0]]
    if not hit: fail("no row n=%s" % args[0])
    v = hit[0].get(args[1])
    if v is None: fail("row %s has no %s=" % (args[0], args[1]))
    if len(args) > 2 and not re.search(args[2], v): fail("row %s %s=%r does not match %s" % (args[0], args[1], v, args[2]))
    print("%s %s=%s" % (args[0], args[1], v))
elif cmd == "body":                     # body NAME PATH STR... : one <b n=NAME p=PATH> whose CDATA holds every STR
    bs = re.findall(r'<b ([^>]*)><!\[CDATA\[(.*?)\]\]>', t, re.S)
    hit = [(dict(re.findall(r'(\w+)="([^"]*)"', a)), c) for a, c in bs]
    hit = [(a, c) for a, c in hit if a.get("n") == args[0] and a.get("p") == args[1]]
    if not hit: fail("no <b n=%s p=%s> (bodies present: %s)" % (args[0], args[1], [dict(re.findall(r'(\w+)="([^"]*)"', a)).get("n") for a, c in bs]))
    a, c = hit[0]
    miss = [s for s in args[2:] if s not in c]
    if miss: fail("body %s lacks %s" % (args[0], miss))
    print("body %s l=%s bytes=%d" % (args[0], a.get("l"), len(c)))
elif cmd == "bodyattr":                 # bodyattr NAME ATTR [REGEX]
    bs = [dict(re.findall(r'(\w+)="([^"]*)"', a)) for a in re.findall(r'<b ([^>]*)>', t)]
    hit = [a for a in bs if a.get("n") == args[0]]
    if not hit: fail("no <b n=%s>" % args[0])
    v = hit[0].get(args[1])
    if v is None: fail("<b n=%s> has no %s=" % (args[0], args[1]))
    if len(args) > 2 and not re.search(args[2], v): fail("<b %s %s=%r> does not match %s" % (args[0], args[1], v, args[2]))
    print("b %s %s=%s" % (args[0], args[1], v[:80]))
elif cmd == "nobody":                   # nobody : no <bodies and no <b
    if "<bodies" in t or re.search(r'<b ', t): fail("a bodies element rides this answer")
elif cmd == "bodycount":                # bodycount N : exactly N <b elements and root bodies=N
    n = len(re.findall(r'<b ', t)); v = root().get("bodies")
    if n != int(args[0]) or v != args[0]: fail("<b count=%d root bodies=%r, wanted %s" % (n, v, args[0]))
elif cmd == "legend":                   # legend STR... : every STR appears inside the XML comments
    lg = legend(); miss = [s for s in args if s not in lg]
    if miss: fail("legend lacks %s" % miss)
elif cmd == "defined":                  # defined : every new attribute that rides this answer is named ATTR= in the legend
    lg = legend(); r = root(); s = sigs(); rowattrs = set(k for row in rows() for k in row[3])
    riding = [a for a in ("frame_terms", "evidence_demoted", "evidence_unparsed") if a in r] \
           + [a for a in ("dups_collapsed",) if a in s] + [a for a in ("also",) if a in rowattrs]
    miss = [a for a in riding if (a + "=") not in lg]
    if miss: fail("attributes riding without a legend reading: %s" % miss)
    print("defined: %s" % (riding or "none ride"))
elif cmd == "nodashes":                 # nodashes : no "--" inside any XML comment (xmllint rejects it)
    bad = [c[:60] for c in re.findall(r'<!--(.*?)-->', t, re.S) if "--" in c]
    if bad: fail("'--' inside an XML comment: %s" % bad)
elif cmd == "est":                      # est MAXTOKENS : est_tokens <= MAX and no over_ceiling
    r = root(); e = int(r.get("est_tokens", "0") or 0)
    if e == 0 or e > int(args[0]) or r.get("over_ceiling") == "1": fail("est_tokens=%s over_ceiling=%s (max %s)" % (r.get("est_tokens"), r.get("over_ceiling"), args[0]))
    print("est_tokens=%d" % e)
elif cmd == "candpos":                  # candpos NAME [PATH] : a --format=candidates <cand n=NAME> with s>0 (demoted, never cut)
    hit = [dict(re.findall(r'(\w+)="([^"]*)"', c)) for c in re.findall(r'<cand ([^>]*)>', t)]
    hit = [a for a in hit if a.get("n") == args[0] and (len(args) < 2 or a.get("p") == args[1])]
    if not hit: fail("no <cand n=%s%s>" % (args[0], (" p=" + args[1]) if len(args) > 1 else ""))
    try: sv = float(hit[0].get("s", "0"))
    except ValueError: fail("cand %s s=%r is not a number" % (args[0], hit[0].get("s")))
    if not sv > 0: fail("cand %s s=%s, wanted > 0" % (args[0], sv))
    print("%s r=%s s=%s" % (args[0], hit[0].get("r"), hit[0].get("s")))
elif cmd == "rowsge":                   # rowsge N
    if len(rows()) < int(args[0]): fail("only %d rows" % len(rows()))
else:
    fail("unknown check " + cmd)
PY
chk(){ python3 "$TMP/chk.py" "$@"; }
strip_at(){ sed -e 's/ at="[^"]*"//g' -e 's/"at":"[^"]*",\{0,1\}//g'; }
run(){ "$BIN" "$FIX" --no-cache "$@" 2>/dev/null; }

T_A="I want to write a new router. What interface must it implement, and which existing routers should I read first?"
T_B="how does the scanner pick which files to check"
T_D="How does the JWT middleware verify a token?"
T_D_NOCUE="JWT middleware token verification"
T_PY="How does Stylesheet apply the parsed rules to a widget?"
T_C="How does cmd_find_target resolve the session, window and pane of a command?"
T_BIG="How does render_screen draw the screen?"
T_TWIN="how does the matcher match a route"
T_SOLE="how do I write"
T_MATCH="match method path handlers"
T_R2="how does \`write\` flush the stream"
T_BENCH="how does the benchmarks tool wrap a router"
T_FB1="How does pane resolution work?"            # D13 (a): no whole-name owner, ONE head callable shares a kept subtoken (pane)
T_FB2="How does the garbage collector work?"      # D13 (b): a cue, no head callable shares a kept subtoken
T_FB3="How does the client window get chosen?"    # D13 (c): several sharers (client / window) — premise re-checked when D lands
T_NAMED="How does \`verify\` check the token?"   # D14: a NAMED identifier is the owner, not the callee-edge entry point

run --for="$T_A" >"$TMP/a.xml";   run --for="$T_A" --legend=compact >"$TMP/a.c.xml"
run --for="$T_B" >"$TMP/b.xml";   run --for="$T_B" --format=candidates --top-k=40 >"$TMP/b.cand.xml"
run --for="$T_D" >"$TMP/d.xml";   run --for="$T_D" --legend=compact >"$TMP/d.c.xml"
run --for="$T_D" --signatures-only >"$TMP/d.sig.xml"
run --for="$T_D_NOCUE" >"$TMP/d.nocue.xml"
run --for="$T_PY" >"$TMP/py.xml"; run --for="$T_C" >"$TMP/c.xml"; run --for="$T_BIG" >"$TMP/big.xml"
run --for="$T_TWIN" >"$TMP/twin.xml"; run --for="$T_SOLE" >"$TMP/sole.xml"; run --for="$T_MATCH" >"$TMP/match.xml"
run --for="$T_R2" >"$TMP/r2.xml"; run --for="$T_BENCH" >"$TMP/bench.xml"
run --for="$T_A" --format=candidates --top-k=60 >"$TMP/a.cand.xml"
for f in a b d d.sig d.nocue py c big twin sole match r2 bench; do
    [ -s "$TMP/$f.xml" ] && grep -q '<sigs' "$TMP/$f.xml" || { no "(0) $f.xml: no <sigs> block — the fixture answered nothing, every arm below would be vacuous"; }
done

# ── A: task-frame words ─────────────────────────────────────────────────────────────────────────────────────
if r="$( chk norow '^write' 25 "$TMP/a.xml" )"; then ok "(A1) T-A: no write* row at r<=25 (kill 3)"; else no "(A1) T-A: $r"; fi
if r="$( chk rankle Router 3 src/router.ts "$TMP/a.xml" )"; then ok "(A2) T-A: Router (src/router.ts) r=$r"; else no "(A2) T-A: $r"; fi
if r="$( chk norow '^SAMPLE_QUESTIONS$' 10 "$TMP/d.xml" )"; then ok "(A3) T-D: SAMPLE_QUESTIONS (frame words in strings) not at r<=10"; else no "(A3) T-D: $r"; fi
if r="$( chk rankle write 1 "$TMP/sole.xml" )"; then ok "(A4) sole-anchor guard: '$T_SOLE' keeps write at r=1"; else no "(A4) sole-anchor: $r"; fi
if r="$( chk noattr frame_terms "$TMP/sole.xml" )"; then ok "(A4) sole-anchor guard: no frame_terms= rides (nothing was down-weighted)"; else no "(A4) sole-anchor: $r"; fi
# A5 EXACT (rv-gates CHANGE 8): T-A's unique >=2-byte terms that are on the frozen frame list AND occur in this fixture
# (each probed alone with --no-route --format=candidates on 4c38d363: s>0) — want to write new must it implement and which
# existing read first = 12; `what` and `should` are on the list but absent from the fixture (s=0), so they are not counted.
if r="$( chk rootattr frame_terms '12' "$TMP/a.xml" )"; then ok "(A5) T-A root $r (exact)"; else no "(A5) T-A: $r"; fi
if r="$( chk legend 'frame_terms=' "$TMP/a.xml" )"; then ok "(A5) full legend defines frame_terms="; else no "(A5) full legend: $r"; fi
if r="$( chk legend 'frame_terms=' "$TMP/a.c.xml" )"; then ok "(A5) compact legend defines frame_terms="; else no "(A5) compact legend: $r"; fi
run --for=TrieRouter >"$TMP/ne.xml"
if grep -q 'route="name-exact' "$TMP/ne.xml"; then ok "(A6) --for=TrieRouter still routes name-exact"; else no "(A6) --for=TrieRouter did not route name-exact"; fi
if r="$( chk noattr frame_terms evidence_demoted dups_collapsed also "$TMP/ne.xml" )"; then ok "(A6) name-exact route carries none of the new attributes"; else no "(A6) name-exact: $r"; fi
run --for="$T_A" --no-route >"$TMP/nr.xml"
if r="$( chk noattr frame_terms evidence_demoted dups_collapsed also "$TMP/nr.xml" )"; then ok "(A7) --no-route carries none of the new attributes"; else no "(A7) --no-route: $r"; fi
run --query="$T_A" >"$TMP/q.xml"
if grep -q 'frame_terms=\|evidence_demoted=\|dups_collapsed=' "$TMP/q.xml"; then no "(A8) --query carries a --for-only attribute"; else ok "(A8) --query carries none of the new attributes"; fi
if r="$( chk rankle write 1 src/utils/stream.ts "$TMP/r2.xml" )"; then ok "(A9) R2 twin: a backticked frame word keeps its row: write r=$r"; else no "(A9) R2 twin: $r"; fi
if r="$( chk rootattrge frame_terms 1 "$TMP/r2.xml" )"; then ok "(A9) R2 twin: $r rides (the other frame words were weighted)"; else no "(A9) R2 twin: $r"; fi
# A10 (rv-gates CHANGE 7, rule 5): a quarter weight / the tier factor is a DOWN-weight — every such row is still ranked
for n in write writeFile writeTextFile writeSSE RouterInterface RouterLike; do
    if r="$( chk candpos "$n" "$TMP/a.cand.xml" )"; then ok "(A10) T-A candidates: $r (down-weighted, not cut)"; else no "(A10) T-A candidates: $r"; fi
done
for n in MAXIMUM_FILE_LINES SAMPLE_QUESTIONS PLAN_REFERENCE_RES; do
    if r="$( chk candpos "$n" "$TMP/b.cand.xml" )"; then ok "(A10) T-B candidates: $r (down-weighted, not cut)"; else no "(A10) T-B candidates: $r"; fi
done
if grep -q '<candidates [^>]*frame_terms="[0-9]*"' "$TMP/b.cand.xml"; then ok "(A11) --format=candidates carries frame_terms= (provenance)"; else no "(A11) --format=candidates lacks frame_terms= on its root"; fi

# ── B: evidence tier — DEFERRED (out of lane/for-noise scope; FORNOISE_BD=1 runs it) ──────────────────────────
if [ "$BD" = "1" ]; then
    if r="$( chk rankle listProjectFiles 3 "$TMP/b.xml" )"; then ok "(B1) T-B: listProjectFiles r=$r"; else no "(B1) T-B: $r"; fi
    if r="$( chk rankle filterFiles 3 "$TMP/b.xml" )"; then ok "(B1) T-B: filterFiles r=$r"; else no "(B1) T-B: $r"; fi
    for noise in MAXIMUM_FILE_LINES SAMPLE_QUESTIONS PLAN_REFERENCE_RES; do
        if r="$( chk below "$noise" listProjectFiles "$TMP/b.xml" )"; then ok "(B2) T-B: $r"; else no "(B2) T-B: $r"; fi
        if r="$( chk below "$noise" filterFiles "$TMP/b.xml" )"; then ok "(B2) T-B: $r"; else no "(B2) T-B: $r"; fi
    done
    if r="$( chk rootattrge evidence_demoted 3 "$TMP/b.xml" )"; then ok "(B3) T-B root $r"; else no "(B3) T-B: $r"; fi
    if r="$( chk legend 'evidence_demoted=' "$TMP/b.xml" )"; then ok "(B3) full legend defines evidence_demoted="; else no "(B3) legend: $r"; fi
    if r="$( chk rankle SCANNER_NOTE 5 "$TMP/b.xml" )"; then ok "(B4) T-B: SCANNER_NOTE (its NAME matches) is not demoted: r=$r"; else no "(B4) T-B: $r"; fi
    if grep -q '<candidates [^>]*evidence_demoted="[0-9]*"' "$TMP/b.cand.xml"; then
        ok "(B5b) --format=candidates carries evidence_demoted= (provenance; frame_terms= is A11)"
    else
        no "(B5b) --format=candidates lacks evidence_demoted= on its root"
    fi
    # B6 (rv-gates CHANGE 6, checklist 29): the parser decides the tier — a kept word inside a template SUBSTITUTION and after a
    # `//` inside a string literal is CODE; a text heuristic (backtick/quote counting, `//`) would demote both.
    for n in selectionSummary remoteProbe; do
        for noise in MAXIMUM_FILE_LINES SAMPLE_QUESTIONS PLAN_REFERENCE_RES; do
            if r="$( chk below "$noise" "$n" "$TMP/b.xml" )"; then ok "(B6) T-B: $r (not demoted)"; else no "(B6) T-B: $r"; fi
        done
    done
    if r="$( chk rootattr evidence_demoted '3' "$TMP/b.xml" )"; then ok "(B6) T-B root $r (exact: the three doc/string-only rows)"; else no "(B6) T-B: $r"; fi

else
    skip "(B1-B3, B5b, B6) evidence tier: deferred — B is out of lane/for-noise's scope (owner plan 2026-10-10); FORNOISE_BD=1 runs these"
fi

# ── C: tiers and duplicates ────────────────────────────────────────────────────────────────────────────────
for above in Router SmartRouter; do
    if r="$( chk below RouterInterface "$above" benchmarks/routers/src/tool.mts "$TMP/a.xml" )"; then ok "(C1) T-A: $r"; else no "(C1) T-A: $r"; fi
done
if r="$( chk below RouterLike Router "$TMP/a.xml" )"; then ok "(C2) T-A: $r (a .d.ts declaration takes the tier)"; else no "(C2) T-A: $r"; fi
if rs="$( chk rankle sourceMatcher 1 src/matcher.ts "$TMP/twin.xml" )"; then ok "(C3) twin: src/matcher.ts sourceMatcher r=$rs"; else no "(C3) twin: $rs"; fi
if r="$( chk below exampleMatcher sourceMatcher examples/matcher.ts "$TMP/twin.xml" )"; then ok "(C3) twin: $r"; else no "(C3) twin: $r"; fi
n="$( chk count upgradeWebSocket "$TMP/a.xml" )"
if [ "$n" = "1" ]; then ok "(C4) T-A: upgradeWebSocket is ONE row (two byte-identical files)"; else no "(C4) T-A: upgradeWebSocket rows=$n, wanted 1"; fi
# rv-gates CHANGE 8: pin the KEEPER (the src/ first-segment rule) and the exact also= — a first-seen-copy keeper goes red
if r="$( chk rowattr upgradeWebSocket p '^src/adapter/deno/websocket\.ts$' "$TMP/a.xml" )"; then ok "(C4) T-A: keeper $r"; else no "(C4) T-A: keeper $r"; fi
if r="$( chk rowattr upgradeWebSocket also '^adapters/deno/src/websocket\.ts$' "$TMP/a.xml" )"; then ok "(C4) T-A: $r"; else no "(C4) T-A: $r"; fi
if r="$( chk sigsattrge dups_collapsed 1 "$TMP/a.xml" )"; then ok "(C4) T-A: <sigs $r>"; else no "(C4) T-A: $r"; fi
if r="$( chk legend 'dups_collapsed=' 'also=' "$TMP/a.xml" )"; then ok "(C4) full legend defines dups_collapsed= and also="; else no "(C4) legend: $r"; fi
n="$( chk count match "$TMP/match.xml" )"
if [ "${n:-0}" -ge 2 ]; then ok "(C5) two same-named match methods in different files stay $n rows"; else no "(C5) match rows=$n, wanted >=2 (entity identity)"; fi
if r="$( chk noattr dups_collapsed also "$TMP/match.xml" )"; then ok "(C5) nothing collapsed on non-identical files"; else no "(C5) $r"; fi
if r="$( chk below test_css_parsed_and_applied_to_widgets apply "$TMP/py.xml" )"; then ok "(C6) T-PY: $r (tests/ tier unchanged)"; else no "(C6) T-PY: $r"; fi
if r="$( chk below Router RouterInterface "$TMP/bench.xml" )"; then ok "(C7) family lift: '$T_BENCH' names the family — $r"; else no "(C7) family lift: $r"; fi

# ── D: the body slot ────────────────────────────────────────────────────────────────────────────────────────
# ACTIVE here: the GREEN twins — they hold for a binary with no body slot and go red if a body leaks where none may ride.
if r="$( chk rootattr bundle compact "$TMP/d.xml" )"; then ok "(D1) T-D: $r"; else no "(D1) T-D: $r"; fi
if grep -q '<b [^>]*n="verify"' "$TMP/d.xml"; then no "(D2) T-D: verify's body was served — the entry point (jwt calls verify) must win"; else ok "(D2) T-D: no verify body (the entry point jwt, or no slot)"; fi
run --for="$T_D" --token-budget=400 >"$TMP/d.tb400.xml"
if r="$( chk rootattr bodies 0 "$TMP/d.tb400.xml" )"; then ok "(D5) --token-budget=400: bodies=\"0\" (no room past the top rows)"; else no "(D5) --token-budget=400: $r"; fi
if r="$( chk nobody "$TMP/d.tb400.xml" )"; then ok "(D5) --token-budget=400: no <b"; else no "(D5) --token-budget=400: $r"; fi
if r="$( chk rowsge 1 "$TMP/d.tb400.xml" )"; then ok "(D5) --token-budget=400: the sigs survive"; else no "(D5) --token-budget=400: $r"; fi
if r="$( chk rootattr reason compact-route "$TMP/d.nocue.xml" )"; then ok "(D6) no cue: $r"; else no "(D6) no cue: $r"; fi
if r="$( chk rootattr bodies 0 "$TMP/d.nocue.xml" )"; then ok "(D6) no cue: $r"; else no "(D6) no cue: $r"; fi
if r="$( chk nobody "$TMP/d.nocue.xml" )"; then ok "(D6) no cue: no <bodies> element"; else no "(D6) no cue: $r"; fi
if r="$( chk nobody "$TMP/d.sig.xml" )"; then ok "(D7) --signatures-only: no bodies"; else no "(D7) --signatures-only: $r"; fi
if r="$( chk noattr bundle bodies "$TMP/d.sig.xml" )"; then ok "(D7) --signatures-only: no bundle=/bodies="; else no "(D7) --signatures-only: $r"; fi
run --for="$T_D" --json >"$TMP/d.json"
if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if 'bodies' not in d and len(d.get('sigs',[]))>=1 else 1)" "$TMP/d.json"; then
    ok "(D7) --json: no bodies key, sigs served"
else
    no "(D7) --json: a bodies key rides the JSON dialect (or no sigs)"
fi
run --for="$T_D" --auto-bodies >"$TMP/d.auto.xml"
if r="$( chk rootattr bundle auto "$TMP/d.auto.xml" )"; then ok "(D7) --auto-bodies: $r (the rank-first walk, unchanged)"; else no "(D7) --auto-bodies: $r"; fi
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
printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' "$FIX" "$T_D" \
    | "$BIN" --mcp 2>/dev/null | python3 "$TMP/mcptext.py" >"$TMP/d.mcp.xml"
if grep -q '<sigs' "$TMP/d.mcp.xml"; then
    if r="$( chk nobody "$TMP/d.mcp.xml" )"; then ok "(D11) MCP for: no body slot (signature posture, a named floor)"; else no "(D11) MCP for: $r"; fi
else
    no "(D11) MCP for answered nothing — the floor could not be checked"
fi
for f in a a.c b d d.c py c big twin match r2 bench; do
    if r="$( chk defined "$TMP/$f.xml" )"; then ok "(D12) $f.xml: $r"; else no "(D12) $f.xml: $r"; fi
done

# DEFERRED (FORNOISE_BD=1): the body-slot contracts, with the early gates review's changes 3, 4, 5 and 8 applied.
if [ "$BD" = "1" ]; then
    if r="$( chk bodycount 1 "$TMP/d.xml" )"; then ok "(D1) T-D: exactly one body, root bodies=\"1\""; else no "(D1) T-D: $r"; fi
    if r="$( chk body jwt src/middleware/jwt/jwt.ts "getCookie" "HTTPException(401" "ctx.set('jwtPayload'" "$TMP/d.xml" )"; then
        ok "(D1) T-D: $r holds the three kill-(1) strings"
    else
        no "(D1) T-D: $r"
    fi
    if r="$( chk bodyattr jwt l '^12$' "$TMP/d.xml" )"; then ok "(D1) T-D: $r (CHANGE 5: the definition line)"; else no "(D1) T-D: $r"; fi
    if r="$( chk legend 'bodies=1' "$TMP/d.xml" )"; then ok "(D1) full legend explains the compact body (bodies=1)"; else no "(D1) legend: $r"; fi
    # D3' (CHANGE 3, checklist 22/28): re-anchored. The old "shown default < --signatures-only shown" held on the base binary of
    # a CLEAN tree (39 < 40). On 4c38d363: default est_tokens=3900, shown=39/40; jwt's body = 2,660 B, the largest
    # --signatures-only row = 434 B -> an honest payment displaces >= ceil(2660/434) = 7 rows: shown <= 33, est <= 4100 (+5%).
    # Run from the absolute root AND a SHORT relative root (header bytes move the budget boundary).
    ( cd "$ROOT/test" && "$BIN" fornoisefix --no-cache --for="$T_D" 2>/dev/null ) >"$TMP/d.rel.xml"
    for f in d d.rel; do
        if r="$( chk est 4100 "$TMP/$f.xml" )"; then ok "(D3) $f: $r (the body is paid, not added)"; else no "(D3) $f: $r"; fi
        sd="$( chk shown "$TMP/$f.xml" )"
        if [ -n "$sd" ] && [ "$sd" -le 33 ] 2>/dev/null; then ok "(D3) $f: shown=$sd <= 33 (the body displaced rows)"; else no "(D3) $f: shown=$sd, wanted <= 33"; fi
        if r="$( chk sigsattr next 'signatures-only' "$TMP/$f.xml" )"; then ok "(D3) $f: displaced rows recoverable: <sigs $r>"; else no "(D3) $f: $r"; fi
    done
    run --for="$T_D" --token-budget=3000 >"$TMP/d.tb3000.xml"
    ( cd "$ROOT/test" && "$BIN" fornoisefix --no-cache --for="$T_D" --token-budget=3000 2>/dev/null ) >"$TMP/d.tb3000.rel.xml"
    ( cd "$ROOT/test" && "$BIN" fornoisefix --no-cache --for="$T_D" --token-budget=400 2>/dev/null ) >"$TMP/d.tb400.rel.xml"
    for f in d.tb3000 d.tb3000.rel; do
        if r="$( chk bodycount 1 "$TMP/$f.xml" )"; then ok "(D4) $f: the slot is served inside the ceiling"; else no "(D4) $f: $r"; fi
        if r="$( chk est 3450 "$TMP/$f.xml" )"; then ok "(D4) $f: $r within 1.15x"; else no "(D4) $f: $r"; fi
    done
    for f in d.tb400 d.tb400.rel; do
        if r="$( chk rootattr reason budget "$TMP/$f.xml" )"; then ok "(D5) $f: $r (CHANGE 8: the reason is the budget)"; else no "(D5) $f: $r"; fi
    done
    if r="$( chk body apply src/textual/css/stylesheet.py "_check_rule(" "widget.refresh()" "$TMP/py.xml" )"; then ok "(D8) T-PY: $r (the method, not the class)"; else no "(D8) T-PY: $r"; fi
    if r="$( chk body cmd_find_target src/c/cmd-find.c "cmd_find_get_session(" "cmd_find_valid_state(" "$TMP/c.xml" )"; then ok "(D9) T-C: $r"; else no "(D9) T-C: $r"; fi
    if grep -q '<b [^>]*p="src/c/cmd-find.h"' "$TMP/c.xml"; then no "(D9) T-C: the header PROTOTYPE was chosen as the owner (CHANGE 5)"; else ok "(D9) T-C: the .h prototype is never the owner"; fi
    if r="$( chk bodyattr render_screen truncated 1 "$TMP/big.xml" )"; then ok "(D10) oversized owner: <b $r> (head-cut, never dropped)"; else no "(D10) oversized: $r"; fi
    if r="$( chk bodyattr render_screen next '^--expand=' "$TMP/big.xml" )"; then ok "(D10) oversized owner: $r"; else no "(D10) oversized: $r"; fi
    if r="$( chk bodyattr render_screen lines '^[0-9]+-[0-9]+/[0-9]+$' "$TMP/big.xml" )"; then ok "(D10) oversized owner: $r"; else no "(D10) oversized: $r"; fi
    if r="$( chk bodyattr render_screen p '^src/c/render\.c$' "$TMP/big.xml" )"; then ok "(D10) oversized owner: $r (the .c definition, not render.h)"; else no "(D10) oversized: $r"; fi
    if r="$( chk legend 'b t= n= p= l=' "$TMP/d.c.xml" )"; then ok "(D12) compact legend defines b t= n= p= l= when a body rides"; else no "(D12) compact legend: $r"; fi
    # D13 (CHANGE 4): the fallback owner, conservative — (a) one sharer fires, (b) no sharer and (c) several sharers none of
    # which is the best-ranked callable serve NO slot (bodies="0" reason="compact-route"). (c)'s premise (no sharer is the
    # best-ranked callable of the head) is re-shown on the D binary when D lands — it cannot be shown before D's owner choice exists.
    run --for="$T_FB1" >"$TMP/fb1.xml"; run --for="$T_FB2" >"$TMP/fb2.xml"; run --for="$T_FB3" >"$TMP/fb3.xml"
    if r="$( chk body cmd_find_get_pane src/c/cmd-find.c "$TMP/fb1.xml" )"; then ok "(D13a) one sharer: $r"; else no "(D13a) one sharer: $r"; fi
    for f in fb2 fb3; do
        if r="$( chk nobody "$TMP/$f.xml" )"; then ok "(D13) $f: no body"; else no "(D13) $f: $r"; fi
        if r="$( chk rootattr reason compact-route "$TMP/$f.xml" )"; then ok "(D13) $f: $r"; else no "(D13) $f: $r"; fi
    done
    # D14 (ruling R6): a NAMED identifier beats the callee-edge rule — `verify` is the body, not jwt
    run --for="$T_NAMED" >"$TMP/named.xml"
    if r="$( chk body verify src/utils/jwt/jwt.ts "$TMP/named.xml" )"; then ok "(D14) named identifier: $r"; else no "(D14) named identifier: $r"; fi
    # D15 (ruling R7): sole-anchor + cue — nothing was down-weighted, `write` is an owner, D fires on it
    if r="$( chk body write src/utils/stream.ts "$TMP/sole.xml" )"; then ok "(D15) sole anchor: $r"; else no "(D15) sole anchor: $r"; fi
    # D16 (ruling R4): --json / MCP carry the clue, not the body
    if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if str(d.get('body_next','')).endswith('src/middleware/jwt/jwt.ts:jwt') else 1)" "$TMP/d.json"; then
        ok "(D16) --json: body_next names src/middleware/jwt/jwt.ts:jwt"
    else
        no "(D16) --json: no body_next= naming jwt"
    fi
    if r="$( chk rootattr body_next '.*src/middleware/jwt/jwt\.ts:jwt$' "$TMP/d.mcp.xml" )"; then ok "(D16) MCP for: $r"; else no "(D16) MCP for: $r"; fi
else
    skip "(D1 body, D3', D4, D5 reason, D8-D10, D12 legend, D13-D16) body slot: deferred — D is out of lane/for-noise's scope (owner plan 2026-10-10); FORNOISE_BD=1 runs these"
fi

# ── M: mutation controls — the checkers reject canned pre-change shapes ─────────────────────────────────────
printf '%s' '<ctx task="t" route="subtoken+body" bundle="compact" bodies="0" reason="compact-route"><!-- legend --><sigs shown="2" total="2"><d l="1" n="verify" p="src/utils/jwt/jwt.ts" r="1">x</d><d l="2" n="jwt" p="src/middleware/jwt/jwt.ts" r="2">y</d></sigs><hops shown="0" total="0" capped="0"></hops></ctx>' >"$TMP/m1.xml"
if chk body jwt src/middleware/jwt/jwt.ts "getCookie" "$TMP/m1.xml" >/dev/null 2>&1; then no "(M1) the body checker accepted a canned answer with no body"; else ok "(M1) the body checker rejects a canned no-body answer"; fi
printf '%s' '<ctx task="t"><sigs shown="2" total="2"><d l="1" n="writeFile" p="src/adapter/deno/deno.d.ts" r="3">x</d><d l="2" n="Router" p="src/router.ts" r="9">y</d></sigs></ctx>' >"$TMP/m2.xml"
if chk norow '^write' 25 "$TMP/m2.xml" >/dev/null 2>&1; then no "(M2) the write-row checker accepted a canned writeFile row"; else ok "(M2) the write-row checker rejects a canned writeFile row"; fi
if chk rankle Router 3 "$TMP/m2.xml" >/dev/null 2>&1; then no "(M2) the rank checker accepted Router at r=9"; else ok "(M2) the rank checker rejects Router at r=9"; fi
printf '%s' '<ctx task="t"><sigs shown="2" total="2"><d l="1" n="upgradeWebSocket" p="adapters/deno/src/websocket.ts" r="2">x</d><d l="1" n="upgradeWebSocket" p="src/adapter/deno/websocket.ts" r="3">x</d></sigs></ctx>' >"$TMP/m3.xml"
if [ "$( chk count upgradeWebSocket "$TMP/m3.xml" )" = "1" ]; then no "(M3) the dup counter saw one row where two ride"; else ok "(M3) the dup counter sees both canned uncollapsed rows"; fi
if chk rowattr upgradeWebSocket also "$TMP/m3.xml" >/dev/null 2>&1; then no "(M3) the also= checker accepted a row without also="; else ok "(M3) the also= checker rejects a row without also="; fi

# ── X: hygiene ──────────────────────────────────────────────────────────────────────────────────────────────
run --for="$T_D" >"$TMP/d2.xml"
if cmp -s "$TMP/d.xml" "$TMP/d2.xml"; then ok "(X1) T-D is deterministic (x2 byte-identical)"; else no "(X1) T-D differs between two runs"; fi
if command -v xmllint >/dev/null 2>&1; then
    for f in a a.c b d d.c py c big twin r2 bench; do
        if xmllint --noout "$TMP/$f.xml" 2>/dev/null; then ok "(X2) $f.xml is well-formed XML"; else no "(X2) $f.xml failed xmllint"; fi
    done
else
    skip "(X2) xmllint not installed — well-formedness not checked here"
fi
for f in a a.c b d d.c big; do
    if r="$( chk nodashes "$TMP/$f.xml" )"; then ok "(X3) $f.xml: no '--' inside an XML comment"; else no "(X3) $f.xml: $r"; fi
done

# ── I: optional byte identity against the pre-change binary on the untouched verbs ──────────────────────────
if [ -n "${RIPWIRE_BASE_BIN:-}" ] && [ -x "${RIPWIRE_BASE_BIN}" ]; then
    i=0
    while IFS= read -r line; do              # one argv per line, arguments separated by '|' (values may hold spaces)
        i=$(( i + 1 ))
        IFS='|' read -r -a argv <<<"$line"
        "$RIPWIRE_BASE_BIN" "$FIX" --no-cache "${argv[@]}" 2>/dev/null | strip_at >"$TMP/i.base"
        "$BIN"              "$FIX" --no-cache "${argv[@]}" 2>/dev/null | strip_at >"$TMP/i.head"
        if [ ! -s "$TMP/i.base" ]; then no "(I$i) the base binary answered nothing for: $line"; continue; fi
        if cmp -s "$TMP/i.base" "$TMP/i.head"; then ok "(I$i) byte-identical: $line"; else no "(I$i) differs from the base binary: $line"; fi
    done <<'ARGV'
--for=TrieRouter
--for=verify|--legend=compact
--query=write a new router
--callers=verify
--grep=jwtPayload
--expand=src/middleware/jwt/jwt.ts:jwt
--pack-task=how does the JWT middleware verify a token
--for=How does the JWT middleware verify a token?|--no-route
--grep=match
--uses=exampleMatcher
ARGV
else
    skip "(I) RIPWIRE_BASE_BIN unset or not executable — base-binary byte identity not run here"
fi

exit $fail

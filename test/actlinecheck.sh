#!/usr/bin/env bash
# actlinecheck.sh — THE ACT LINE (src/foractline.h; lane BR1, owner ruling 178): a `--for` page lists the ranges an agent reads next in
# one element, <act read="P:L-E,…"/>, right after its <sigs> (after the key-body group when that follows <sigs>), when the answer's top
# kActRows (3) sigs <d> rows by rank all carry l= and e= (BR1b: a function of the ranked rows only — no fold, slot or page cut moves it). The ORACLE below re-derives that rule in Python from the RIPWIRE_NO_ACTLINE=1 twin of the same call
# (its rows decoded by test/rowlines.py), so the binary is checked against the rule as written, not against itself.
#
#   (A)  PRESENT IFF THE CONDITION HOLDS: on every answer, the act line is there exactly when the oracle says the condition holds, and
#        its read= is the oracle's value byte for byte. Non-vacuous both ways: >= 4 answers carry it, and >= 1 answer is one where the
#        oracle says no line BECAUSE a candidate lacks e= (the markdown fixture), not because the page has no rows
#   (B)  EVERY LISTED RANGE IS A ROW OF THE SAME PAGE: each P:L-E equals the p= l= e= of a top-level <sigs> <d> row of the answer itself
#   (C)  ORDER = RANK: the listed rows' r= ascend
#   (D)  BYTE BUDGET + PLACE: at most 3 entries; the element is exactly <act read="…"/> around them (no other byte), right after <sigs>
#        or after the key-body group that directly follows it (forkeybodycheck K3's order); the clause is <= 200 B
#   (E)  DISCLOSED: the clause is in the answer iff the line is, once, BEFORE the row-line clauses (test/rowlines.py strips those from
#        the end); act/read= are defined where a reader can obtain them (the answer's legend, and `--legend-dict` holds the clause)
#   (F)  THE A/B HANDLE: on a WHOLE answer (--page-bytes=0, or one page) RIPWIRE_NO_ACTLINE=1 is the answer minus exactly three things
#        — the element, the clause, and the est_tokens= rise — and est_tokens= rose by the added bytes at 2.5 B/token as a difference
#        of two round-to-nearest prices: floor..ceil of bytes/2.5 (the document is never under-read by more than the half token
#        rounding allows, nor over-read past it), on the CLI and on MCP `for` alike; with BASE_BIN= given, the knob-off answer is BASE_BIN's default answer byte for byte. (A paged page 1 is checked
#        by (A)-(E) only: the line is a block of the row stream, so it can move a page's cut by its own bytes.)
#   (G)  THE CONTRACTS IT KEEPS (BR1b): an explicit --token-budget the answer fits returns the unbudgeted answer byte for byte, line
#        included (TOKEN-BUDGET-MONOTONE); --legend=first carries the same read= with its clause in the leading legend and is a byte
#        permutation of the answer-first whole answer; the fold-off twin (RIPWIRE_NO_BODY_FOLD=1) carries the same read=; page 2
#        carries no line when page 1 holds all of <sigs>; --json is byte-identical with and without the knob
#   (M)  MCP PARITY: MCP `for` follows the same rule on its own bundle (oracle against its knob-off twin) — (F)'s est_tokens= rise
#        two-sided as on the CLI — carries the line on >= 2 tasks, and not under budget_tokens; its clause joins the bundle's LEADING legend run (MCP `for` is legend-first)
#   (S)  --legend-seen=FILE holding the clause's dictionary line: the act line stays and the clause is left out (a dictionary entry)
#   (V)  --version discloses act=on, and act=off under RIPWIRE_NO_ACTLINE=1
#   (H)  determinism (two runs byte-identical), xmllint clean, no newline outside CDATA (G4), on every answer
#   (X)  MUTATION CONTROLS: the checker reds a dropped line, swapped entries, a moved e=, a 4th entry, a dropped clause, and a line on
#        an answer the oracle says has none — so (A)-(E) can fail
# Red on a binary without the pass (81703e5fe): (A) finds no line where the oracle says one, (E) finds no clause, (V) finds no act=.
set -u
# θ5 (src/forpages.h): this gate reads the FULL page-1 legend of a default --for answer (or pins its bytes/rows); the default's
# core legend is pinned by test/corelegendcheck.sh, so the full legend is switched back on here.
export RIPWIRE_NO_CORE_LEGEND=1
# ACT-EDGES (src/foractedges.h): this gate pins the act line's top-3 rule, its 200 B clause and its dictionary entry; the default's
# wide line (up to 8 ranges, the first 3 this gate's) and the edges line are pinned by test/actedgescheck.sh, so the lane is
# switched off here.
export RIPWIRE_ACT_EDGES=0
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-${1:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "actlinecheck: python3 required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "actlinecheck: xmllint required"; exit 2; }
fail=0
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "actlinecheck: BIN=$BIN${BASE_BIN:+ BASE_BIN=$BASE_BIN}"
cd "$ROOT" || exit 2
unset RIPWIRE_NO_ACTLINE RIPWIRE_NO_ROWLINES

# the markdown fixture: a heading row (no e=) ranks inside the top 3 undelivered rows, so the page has rows and no act line
mkdir -p "$WORK/md/docs" "$WORK/md/pkg"
printf '# Guide\n\n## Frobnicate the widget cache\n\nCall frobnicate to flush the widget cache.\n\n## Other\n\ntext\n' >"$WORK/md/docs/guide.md"
printf 'def frobnicate_cache(widgets):\n    """Frobnicate the widget cache."""\n    for w in widgets:\n        w.flush()\n    return len(widgets)\n\n\ndef helper():\n    return 1\n' >"$WORK/md/pkg/widget.py"

BIN="$BIN" BASE="${BASE_BIN:-}" W="$WORK" REPO="$ROOT" python3 - <<'PY'
import json, os, re, subprocess, sys
BIN, BASE, W, REPO = os.environ["BIN"], os.environ["BASE"], os.environ["W"], os.environ["REPO"]
sys.path.insert(0, os.path.join(REPO, "test"))
from rowlines import decode
bad = 0
N = 3
CLAUSE_LEAD = b"<!-- the act line: "
ROW_CLAUSES = (b"<!-- sigs rseq=1:", b"<!-- sigs/tail rows are lines:")


def say(okay, msg):
    global bad
    print("  %s  %s" % ("PASS" if okay else "FAIL", msg))
    bad += 0 if okay else 1


def run(argv, off=False, binary=None):
    env = dict(os.environ)
    env.pop("RIPWIRE_NO_ACTLINE", None)
    if off: env["RIPWIRE_NO_ACTLINE"] = "1"
    return subprocess.run([binary or BIN] + argv, capture_output=True, env=env, stdin=subprocess.DEVNULL).stdout


def mcp(root, args, off=False):
    env = dict(os.environ)
    env.pop("RIPWIRE_NO_ACTLINE", None)
    if off: env["RIPWIRE_NO_ACTLINE"] = "1"
    req = [{"jsonrpc": "2.0", "id": 0, "method": "initialize"}, {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "for", "arguments": args}}]
    p = subprocess.run([BIN, root, "--mcp"], input="".join(json.dumps(r) + "\n" for r in req).encode(), capture_output=True, env=env)
    for line in p.stdout.decode("utf8", "replace").splitlines():
        try: r = json.loads(line)
        except ValueError: continue
        if r.get("id") == 1:
            return "".join(c.get("text", "") for c in r.get("result", {}).get("content", [])).encode("utf8")
    return b""


# ── the ORACLE: the rule in foractline.h's header, read off an element-form page
TAG = re.compile(rb'<([A-Za-z_][\w.:-]*)((?: [A-Za-z_][\w.:-]*="[^"]*")*)\s*(/?)>')
ATTR = re.compile(rb' ([A-Za-z_][\w.:-]*)="([^"]*)"')


def children(b, i, j):
    """the direct children of b[i:j] as (name|None, attrs, start, end); comments as None, CDATA skipped"""
    out = []; depth = 0; k = i; start = name = attrs = None
    while k < j:
        if b.startswith(b"<!--", k):
            e = b.index(b"-->", k) + 3
            if depth == 0: out.append((None, {}, k, e))
            k = e
        elif b.startswith(b"<![CDATA[", k): k = b.index(b"]]>", k) + 3
        elif b.startswith(b"</", k):
            depth -= 1; k = b.index(b">", k) + 1
            if depth == 0: out.append((name, attrs, start, k))
        elif b[k:k + 1] == b"<":
            m = TAG.match(b, k); assert m, b[k:k + 80]
            if depth == 0: start, name, attrs = k, m.group(1), dict(ATTR.findall(m.group(2)))
            if m.group(3) and depth == 0: out.append((name, attrs, k, m.end()))
            depth += 0 if m.group(3) else 1; k = m.end()
        else: k += 1
    return out


def root_children(b):
    i = b.index(b">", b.index(b"<ctx")) + 1; j = b.rindex(b"</ctx>")
    return children(b, i, j)


def page_rows(b):
    """(sigs <d> rows as dicts with rank, delivered (p, l) set) of an element-form page"""
    kids = root_children(b); rows = []; delivered = set()
    for name, attrs, s, e in kids:
        if name in (b"fold", b"bodies"):
            o = b.index(b">", s) + 1; c = b.rindex(b"</", s, e)
            for n2, a2, _, _ in children(b, o, c):
                if n2 == b"b" and b"truncated" not in a2: delivered.add((a2.get(b"p"), a2.get(b"l")))
    sigs = [k for k in kids if k[0] == b"sigs"]
    if not sigs: return None, delivered
    name, attrs, s, e = sigs[0]
    o = b.index(b">", s) + 1; c = b.rindex(b"</", s, e); prev = 0
    for n2, a2, _, _ in children(b, o, c):
        if n2 is None: continue
        rank = int(a2[b"r"]) if b"r" in a2 else prev + 1; prev = rank
        if n2 == b"d": rows.append(dict(a2, rank=rank))
    return rows, delivered


def oracle(off_dec):
    """(value | None, why) — why in {'listed', 'no-sigs', 'no-candidate', 'no-e'}"""
    if not off_dec.startswith(b"<ctx"): return None, "no-root"
    m = re.search(rb' page="(\d+)"', off_dec[:off_dec.index(b">")])
    if m and m.group(1) != b"1": return None, "later-page"
    rows, _ = page_rows(off_dec)
    if rows is None: return None, "no-sigs"
    cand = sorted(rows, key=lambda r: r["rank"])[:N]
    if not cand: return None, "no-candidate"
    if not all(r.get(b"e") and r.get(b"l") and r.get(b"p") and b"," not in r[b"p"] for r in cand): return None, "no-e"
    return b",".join(b"%s:%s-%s" % (r[b"p"], r[b"l"], r[b"e"]) for r in cand), "listed"


def act_of(dec):
    """[(value, start, end)] of every top-level <act> of the root"""
    if not dec.startswith(b"<ctx"): return []
    return [(a.get(b"read"), s, e) for n, a, s, e in root_children(dec) if n == b"act"]


def pages_of(b):
    m = re.search(rb' pages="(\d+)"', b[:b.index(b">")]) if b.startswith(b"<ctx") else None
    return int(m.group(1)) if m else 1


def placed(don, s):
    """the element at byte s follows <sigs> directly, or the key-body group (its comment, then <bodies of=key>) that follows <sigs>"""
    kids = root_children(don); i = next((k for k, c in enumerate(kids) if c[2] == s), -1)
    if i < 1: return False
    if kids[i - 1][0] == b"sigs": return True
    return i >= 3 and kids[i - 1][0] == b"bodies" and kids[i - 2][0] is None and don[kids[i - 2][2]:].startswith(b"<!-- bodies of=key:") \
        and kids[i - 3][0] == b"sigs"


def check(on, off, label):
    """the (A)-(F) verdicts on one (answer, knob-off twin) pair: a list of (ok, msg)"""
    out = []
    don, doff = decode(on), decode(off)
    want, why = oracle(doff)
    acts = act_of(don)
    got = acts[0][0] if len(acts) == 1 else None
    out.append((len(acts) <= 1 and got == want, "(A) %s: line %s, oracle %s (%s)" % (label, got, want, why)))
    if got is not None:
        rows, _ = page_rows(don)
        ents = got.split(b",")
        lookup = {(r[b"p"], r[b"l"], r.get(b"e")): r for r in rows or []}
        hits = []
        for ent in ents:
            p, _, le = ent.rpartition(b":"); l, _, e = le.partition(b"-")
            hits.append(lookup.get((p, l, e)))
        out.append((all(hits), "(B) %s: every listed range is a sigs <d> row's p:l-e on the same page" % label))
        ranks = [h["rank"] for h in hits if h]
        out.append((ranks == sorted(set(ranks)), "(C) %s: ranks %s ascend" % (label, ranks)))
        s, e = acts[0][1], acts[0][2]
        out.append((len(ents) <= N and don[s:e] == b'<act read="' + got + b'"/>' and placed(don, s),
                    "(D) %s: %d entries, the element is the bare <act read=\"...\"/>, %d B, right after <sigs> (or its key group)" % (label, len(ents), e - s)))
    tail = on[:on.rindex(b"</ctx>")]
    n_cl = tail.count(CLAUSE_LEAD)
    first_row_clause = min([tail.find(c) for c in ROW_CLAUSES if tail.find(c) >= 0] or [len(tail)])
    out.append((n_cl == (1 if got is not None else 0) and (n_cl == 0 or tail.find(CLAUSE_LEAD) < first_row_clause),
                "(E) %s: the clause %d time(s), before the row-line clauses" % (label, n_cl)))
    if pages_of(don) > 1: return out, want, why   # (F) is a whole-answer arm: on a paged page 1 the line moves the cut by its bytes
    # (F) on minus element, clause and est_tokens rise == the twin
    strip = don
    if acts: strip = strip[:acts[0][1]] + strip[acts[0][2]:]
    k = strip.find(CLAUSE_LEAD)
    if k >= 0: strip = strip[:k] + strip[strip.index(b"-->", k) + 3:]
    est = lambda b: re.search(rb' est_tokens="(\d+)"', b[:b.index(b">")]) if b.startswith(b"<ctx") else None
    e_on, e_off = est(strip), est(doff)
    added = len(don) - len(strip)
    if e_on and e_off:
        rise = int(e_on.group(1)) - int(e_off.group(1))
        strip = strip.replace(e_on.group(0), e_off.group(0), 1)
        # BR1C: est_tokens= is ONE round-to-nearest price of the whole document (serialize.h tokensForEmittedBytes, "rounds to
        # nearest so the number never systematically under-reads"), so the rise is a DIFFERENCE of two rounded prices: for priced
        # bytes b = the added bytes plus the attribute's own digit growth, at 2.5 B/token, it is floor(b/2.5) or ceil(b/2.5) — never
        # always the ceiling. The old bound (rise*2.5 >= added) demanded the ceiling and failed a correct price whenever the old
        # price's fraction fell low (MEASURED on 565645db5: 4 of 10 GA1 DEV whole answers, and src.whole on an integration tree).
        # Integer arithmetic: floor = 2b//5, ceil = -(-2b//5). Bounded from above too, which the old bound never did, on every arm:
        # BR1D made MCP `for` two-sided as well — it had re-priced without a ledger and charged the blocks spliced after its price
        # along with the line (MEASURED on c58dec374: mcp.pagerank rose 490 for 264 B, ceiling 106).
        b = added + len(e_on.group(1)) - len(e_off.group(1))
        lo, hi = 2 * b // 5, -(-2 * b // 5)
        ok = lo <= rise <= hi and (added > 0) == (rise > 0)
        out.append((ok, "(F) %s: est_tokens= rose %d for %d B priced, the round-to-nearest difference is %d..%d" % (label, rise, b, lo, hi)))
    out.append((strip == doff, "(F) %s: knob off == the answer minus the element, the clause and the est_tokens= rise" % label))
    return out, want, why


def wellformed(doc):
    r = subprocess.run(["xmllint", "--noout", "-"], input=doc, capture_output=True)
    return r.returncode == 0 and b"\n" not in re.sub(rb"<!\[CDATA\[.*?\]\]>", b"", doc, flags=re.S)


SRC = os.path.join(REPO, "src"); TESTS = os.path.join(REPO, "test"); MD = os.path.join(W, "md")
CALLS = [("src.pagerank", SRC, "rank symbols by pagerank and serialize the map", []),
         ("src.legend", SRC, "legend dictionary entries for the --for document legend", []),
         ("src.routing", SRC, "edit routing ranged read wrap hook brief", []),
         ("src.whole", SRC, "rank symbols by pagerank and serialize the map", ["--page-bytes=0"]),
         ("test.decode", TESTS, "decode row lines back to elements", []),
         ("md.fixture", MD, "frobnicate the widget cache guide", [])]
ans = {}
for label, root, task, extra in CALLS:
    argv = [root, "--no-cache", "--for=" + task] + extra
    ans[label] = (run(argv), run(argv, off=True), run(argv))
whys = []; present = 0; allres = []
for label, (on, off, on2) in ans.items():
    res, want, why = check(on, off, label)
    whys.append(why); present += want is not None; allres += res
    for okay, msg in res: say(okay, msg)
    say(on == on2 and wellformed(on), "(H) %s: two runs byte-identical, xmllint clean, no newline outside CDATA" % label)
say(present >= 4, "(A) non-vacuous: %d answers carry the line (need >= 4)" % present)
say(ans["md.fixture"][0].startswith(b"<ctx") and oracle(decode(ans["md.fixture"][1]))[1] == "no-e",
    "(A) non-vacuous: the markdown fixture has rows and NO line because a top candidate lacks e= (%s)" % oracle(decode(ans["md.fixture"][1]))[1])
if BASE:
    for label, root, task, extra in CALLS[:5]:
        argv = [root, "--no-cache", "--for=" + task] + extra
        say(run(argv, off=True) == run(argv, binary=BASE), "(F) %s: RIPWIRE_NO_ACTLINE=1 == BASE_BIN's default answer, byte for byte" % label)

# (G) the contracts it keeps
TASK = "rank symbols by pagerank and serialize the map"
whole = ans["src.whole"][0]; wact = act_of(decode(whole))
p2 = run([SRC, "--no-cache", "--for=" + TASK, "--page-bytes=12000:2"])
p1 = run([SRC, "--no-cache", "--for=" + TASK])
say(p2.startswith(b"<ctx") and b' page="2"' in p2[:p2.index(b">")] and b'continued="sigs"' not in p1[:p1.index(b">")] and act_of(decode(p1))
    and not act_of(decode(p2)), "(G) page 1 holds all of <sigs> and the line; page 2 carries none")
for lab, root, task in (("fixture", os.path.join(REPO, "test", "fixture"), "geometry distance"),):   # one page: the budget's whole answer IS page 1
    unb = run([root, "--no-cache", "--for=" + task]); bud = run([root, "--no-cache", "--for=" + task, "--token-budget=100000"])
    say(len(unb) > 0 and bud == unb and b"<act " in unb, "(G) %s: --token-budget=100000 (fits) returns the unbudgeted answer byte for byte, act line included" % lab)
lf = run([SRC, "--no-cache", "--for=" + TASK, "--legend=first"])   # never paged (--page-bytes is refused with it)
lfa = act_of(decode(lf)) if lf.startswith(b"<ctx") else []
lhead = re.match(rb"<ctx[^>]*>((?:<!--(?:(?!-->).)*-->)+)", lf, re.S)
say(bool(wact) and bool(lfa) and lfa[0][0] == wact[0][0] and lhead is not None and CLAUSE_LEAD in lhead.group(1),
    "(G) --legend=first carries the same read= as the answer-first whole answer, its clause in the leading legend")
nosx = dict(RIPWIRE_NO_SIGX="1", RIPWIRE_NO_TAIL_SAMEDIR="1", RIPWIRE_NO_ROWLINES="1")
def runenv(argv, **env):
    e = dict(os.environ); e.pop("RIPWIRE_NO_ACTLINE", None); e.update(env)
    return subprocess.run([BIN] + argv, capture_output=True, env=e, stdin=subprocess.DEVNULL).stdout
a1 = runenv([SRC, "--no-cache", "--for=" + TASK, "--page-bytes=0"], **nosx); a2 = runenv([SRC, "--no-cache", "--for=" + TASK, "--legend=first"], **nosx)
say(len(a1) > 0 and a1 != a2 and sorted(a1) == sorted(a2), "(G) --legend=first is a byte permutation of the answer-first whole answer (no SIGX/TAIL_SAMEDIR/ROWLINES), line and clause included")
nf = runenv([SRC, "--no-cache", "--for=" + TASK, "--page-bytes=0"], RIPWIRE_NO_BODY_FOLD="1")
say(bool(wact) and act_of(decode(nf)) and act_of(decode(nf))[0][0] == wact[0][0], "(G) the fold-off twin carries the same read= (the line reads the ranked rows only)")
for flag in ("--json",):
    a, b = run([SRC, "--no-cache", "--for=" + TASK, flag]), run([SRC, "--no-cache", "--for=" + TASK, flag], off=True)
    say(len(a) > 0 and a == b and b"<act " not in a, "(G) %s: byte-identical with and without RIPWIRE_NO_ACTLINE, no act line" % flag)

# (M) MCP parity
mres = 0
for label, root, task in (("mcp.pagerank", SRC, "rank symbols by pagerank and serialize the map"), ("mcp.routing", SRC, "edit routing ranged read wrap hook brief"),
                          ("mcp.md", MD, "frobnicate the widget cache guide")):
    on, off = mcp(root, {"task": task}), mcp(root, {"task": task}, off=True)
    res, want, why = check(on, off, label)
    mres +=want is not None and act_of(decode(on)) != []
    for okay, msg in res: say(okay, "(M) " + msg)
    say(wellformed(on), "(H) %s: xmllint clean, no newline outside CDATA" % label)
    if want is not None:
        head = re.match(rb"<ctx[^>]*>((?:<!--(?:(?!-->).)*-->)+)", on, re.S)
        say(head is not None and CLAUSE_LEAD in head.group(1), "(M) %s: the clause sits in the legend-first bundle's LEADING legend run (where its reader looks)" % label)
say(mres >= 2, "(M) MCP `for` carries the line on %d tasks (need >= 2)" % mres)
mb = mcp(SRC, {"task": TASK, "budget_tokens": 3000})
mest = re.search(rb' est_tokens="(\d+)"', mb[:mb.index(b">")]) if mb.startswith(b"<ctx") else None
say(mb.startswith(b"<ctx") and (not act_of(decode(mb)) or (mest is not None and int(mest.group(1)) <= 3000)),
    "(M) MCP `for` under budget_tokens=3000 carries the line only while its est_tokens= stays within the budget")

# (E) the dictionary holds the clause; act/read= are defined in the answer's own legend
d = subprocess.run([BIN, "--legend-dict"], capture_output=True).stdout
on = ans["src.pagerank"][0]
body = on[on.index(CLAUSE_LEAD) + 5:on.index(b"-->", on.index(CLAUSE_LEAD)) - 1] if CLAUSE_LEAD in on else b"<absent>"
say(body in d and len(body) + 9 <= 200, "(E) the clause (%d B) is a --legend-dict entry and within 200 B" % (len(body) + 9))
cl = on[on.index(CLAUSE_LEAD):on.index(b"-->", on.index(CLAUSE_LEAD))] if CLAUSE_LEAD in on else b""
say(b"act line" in cl and re.search(rb"(?<![\w:.-])read=", cl) is not None,
    "(E) the act line and its read= are defined in the answer's own legend (the house name= form legendcoveragecheck reads)")

# (S) --legend-seen: a caller that holds the clause's dictionary line gets the line without the clause (the element stays)
plain = run([SRC, "--no-cache", "--for=" + TASK])
held = subprocess.run([BIN, "--legend-dict=seen"], input=plain, capture_output=True).stdout
heldf = os.path.join(W, "held"); open(heldf, "wb").write(held)
red = run([SRC, "--no-cache", "--for=" + TASK, "--legend-seen=" + heldf])
say(bool(act_of(decode(plain))) and act_of(decode(red)) and act_of(decode(red))[0][0] == act_of(decode(plain))[0][0] and CLAUSE_LEAD in plain
    and CLAUSE_LEAD not in red, "(S) --legend-seen holding the clause's hash: the act line stays, the clause is left out")

# (V) --version
v_on, v_off = run(["--version"]), run(["--version"], off=True)
say(b"act=on" in v_on and b"act=off" in v_off, "(V) --version discloses act=on, and act=off under RIPWIRE_NO_ACTLINE=1")

# (X) mutation controls on the first answer that carries a line with >= 2 entries
pick = next((l for l, (on, off, _) in ans.items() if (oracle(decode(off))[0] or b"").count(b",") >= 1
             and act_of(decode(on)) and CLAUSE_LEAD in on), None)
if pick is None:
    say(False, "(X) no answer carries a line of >= 2 entries (and its clause) to mutate")
else:
    on, off, _ = ans[pick]; val = oracle(decode(off))[0]; ents = val.split(b",")
    p0, _, le0 = ents[0].rpartition(b":"); l0, _, e0 = le0.partition(b"-")
    mut = {"dropped line": on.replace(b'<act read="' + val + b'"/>', b"", 1),
           "swapped entries": on.replace(val, b",".join([ents[1], ents[0]] + ents[2:]), 1),
           "moved e=": on.replace(val, b",".join([p0 + b":" + l0 + b"-" + str(int(e0) + 1).encode()] + ents[1:]), 1),
           "4th entry": on.replace(val, val + b"," + ents[0], 1),
           "dropped clause": on[:on.index(CLAUSE_LEAD)] + on[on.index(b"-->", on.index(CLAUSE_LEAD)) + 3:]}
    md_on, md_off, _ = ans["md.fixture"]
    k = md_on.index(b"<sigs")
    mut_md = md_on[:k] + b'<act read="pkg/widget.py:8-9"/>' + md_on[k:]   # placed wrong too; (A) catches it first
    for name, m in mut.items():
        res, _, _ = check(m, off, pick + "/" + name)
        say(m != on and not all(ok for ok, _ in res), "(X) mutation '%s' on %s is caught" % (name, pick))
    res, _, _ = check(mut_md, md_off, "md/line-where-none")
    say(not all(ok for ok, _ in res), "(X) mutation 'a line where the oracle says none' on the markdown fixture is caught")
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] || fail=1
if [ "$fail" -eq 0 ]; then echo "actlinecheck: all arms PASS"; else echo "actlinecheck: FAILED"; fi
exit "$fail"

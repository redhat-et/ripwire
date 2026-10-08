#!/usr/bin/env bash
# legendrefcheck.sh — the SESSION legend dictionary and the legend="ref" posture (src/legenddict.h; round-2 LO + L6).
#
# THE CONTRACT. An MCP stdio session answers with inline legends (today's compact posture) until it reads the resource
# ripwire://legend-dict. From then on a verb whose legend the dictionary holds answers rows first, keeps on its root only
# the answer's identity (task= changed= from= to=), carries every other root attribute on a LAST child
# <about … legend="ref" dict= dictv=/>, and sends each definition once per session: a definition this process already sent
# is dropped, one it has not is kept in a comment after the rows. Every arm below asserts one clause of that:
#
#   (A) THE DICTIONARY RESOLVES. `--legend-dict` prints it; its dictv= is FNV-1a 64 of its body, recomputed here; the
#       roster (`--legend-dict=roster`) is non-empty and every attribute on it is spelled `attr=` in the dictionary; a
#       bad `--legend-dict=` value refuses. `initialize` carries the same dictv in at most 1,000 bytes of instructions,
#       resources/list names both resources, and an unknown uri refuses with -32002.
#   (B) REF ONLY AFTER SERVE. Before the read, every answer is byte-identical to the same call in a session that never
#       reads it — `legend:"ref"` included — and none carries <about legend="ref">. After the read, the second call of a verb
#       carries it, with the dictionary's dictv, and its root's open tag is followed by a ROW, not a comment.
#   (C) SERVED ONCE. After the read, every dictionary entry reaches the session at most once through the resource and the
#       ref answers: counted over their comments (CDATA excluded), no entry body appears twice. A repeated call carries no
#       definition at all. An answer whose ref form would be longer than its inline one (F) is served inline, byte-identical
#       to the pre-read answer — the one place a definition can reach the session a second time, priced in the lane report.
#   (D) NOTHING HONESTY-BEARING MOVES OUT. Each ref answer and the same call under legend:"full" carry the same multiset of
#       attribute name="value" pairs (schema=/legend=/dict=/dictv= aside; a <g> group counted as its rows); `for`, which takes
#       no legend argument, against its pre-read answer. The root keeps only identity attributes; <about> is its last child.
#   (E) ROSTER HONESTY. In both MCP postures (the pre-read inline answer, ref), every roster attribute an answer
#       carries on an element the roster names is defined where the reader holds it: the answer's own comments for an
#       inline answer; for a ref answer, the resource text plus every comment this session has carried so far. The
#       roster is the binary's (LEGENDREF_ROSTER_BIN overrides it, so a base binary can be read against the new roster).
#       The FULL dialect is prose that defines by mention, not by `attr=`; its debt is test/legendcoveragecheck.sh's ratchet.
#   (F) BUDGET RESERVE. Every ref answer is at most as long as the same call's inline answer (the budget that answer met
#       still holds), with and without an explicit budget_tokens.
#   (G) CLI UNCHANGED. `--legend=ref` refuses on the CLI (no session), naming the resource; the CLI default and
#       --legend=compact carry no <about legend="ref">.
#   (H) L6 UN-GROUPING. On a fixture whose tests have no runner, the inline pack-task answer carries a <g n= p=> group of
#       n <= 8; its ref twin carries the same paths as single <test> rows, each run_unknown="1", and no <g>.
#   (I) G4. Every ref answer parses as XML and has no newline outside CDATA.
#
#   bash test/legendrefcheck.sh "$PWD/build/ripwire"

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
ROSTER_BIN="${LEGENDREF_ROSTER_BIN:-$BIN}"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "legendrefcheck: BIN=$BIN"
fail=0
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# The arms, one python process (the MCP sessions are its subprocesses); written first, run after the fixture exists.
cat >"$TMP/arms.py" <<'PY'
import json, re, subprocess, sys
BIN, ROSTER_BIN, FX, TMP = sys.argv[1:5]
fails = []
def ok(m):  print(f"  PASS  {m}")
def no(m):  print(f"  FAIL  {m}"); fails.append(m)
def check(c, m): (ok if c else no)(m)

# lean-answers lane: the stdio default now OPENS the session on its first reducible answer. Arms (A)-(I) assert the
# pre-lane contract ("ref only after the read") and run it where it still lives, --mcp-legend=inline; arm (J) is their
# twin on the default posture.
OLD_POSTURE = ["--mcp-legend=inline"]
def session(calls, server=None):
    """One stdio MCP session. calls: [(tool, args)] or ('@method', params). Returns [(kind, text)]."""
    server = OLD_POSTURE if server is None else server
    reqs = [{"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}}]
    for i, (name, args) in enumerate(calls, 1):
        if name.startswith("@"):
            reqs.append({"jsonrpc": "2.0", "id": i, "method": name[1:], "params": args})
        else:
            a = dict(args); a.setdefault("path", FX)
            reqs.append({"jsonrpc": "2.0", "id": i, "method": "tools/call", "params": {"name": name, "arguments": a}})
    p = subprocess.run([BIN, "--mcp"] + server, input="".join(json.dumps(r) + "\n" for r in reqs).encode(), capture_output=True, cwd=FX)
    out = []
    for line in p.stdout.decode(errors="replace").splitlines():
        if not line.strip(): continue
        j = json.loads(line); r = j.get("result")
        if r is None:                 out.append(("error", json.dumps(j.get("error"))))
        elif "content" in r:          out.append(("text", r["content"][0]["text"]))
        elif "contents" in r:         out.append(("resource", r["contents"][0]["text"]))
        elif "instructions" in r:     out.append(("init", r["instructions"]))
        else:                         out.append(("json", json.dumps(r)))
    return out

def strip_cdata(t): return re.sub(r'<!\[CDATA\[.*?\]\]>', '', t, flags=re.S)
def comments(t):    return re.findall(r'<!--.*?-->', strip_cdata(t), flags=re.S)
def tags(t):
    body = re.sub(r'<!--.*?-->', '', strip_cdata(t), flags=re.S)
    return [(m.group(1), m.group(2)) for m in re.finditer(r'<([A-Za-z_][\w.-]*)((?:\s+[\w:-]+="[^"]*")*)\s*/?>', body)]
def attrs(s): return re.findall(r'\s([\w:-]+)="([^"]*)"', s)
def pairs(t):
    """Multiset of name=value over every element, a <g n= p=a,b> group counted as its rows (the L6 un-grouping keeps it)."""
    out = []
    for el, a in tags(t):
        av = attrs(a)
        if el == "g" and any(k == "p" for k, _ in av) and any(k == "run_unknown" for k, _ in av):
            ps = dict(av)["p"].split(","); rest = [(k, v) for k, v in av if k not in ("n", "p")]
            for p in ps: out += [("p", p)] + rest
            continue
        out += av
    return sorted((k, v) for k, v in out if k not in ("schema", "legend", "dict", "dictv", "est_tokens"))
def is_ref(t): return '<about ' in t and ' legend="ref"' in t

# ── (A) the dictionary ─────────────────────────────────────────────────────────────────────────────────────────────
print("=== (A) the dictionary resolves ===")
d = subprocess.run([BIN, "--legend-dict"], capture_output=True, text=True)
roster_p = subprocess.run([ROSTER_BIN, "--legend-dict=roster"], capture_output=True, text=True)
bad = subprocess.run([BIN, "--legend-dict=bogus"], capture_output=True, text=True)
DICT = d.stdout if d.returncode == 0 else ""
m = re.match(r'ripwire legend dictionary ripwire\.dict/v1 dictv=([0-9a-f]{16}) entries=(\d+)\n', DICT)
check(d.returncode == 0 and m is not None, f"(A) --legend-dict prints the dictionary with a dictv= header (rc={d.returncode})")
DICTV = m.group(1) if m else "?"
body = DICT[m.end():] if m else ""
h = 14695981039346656037
for b in body.encode():
    h = ((h ^ b) * 1099511628211) & 0xFFFFFFFFFFFFFFFF
check(m is not None and f"{h:016x}" == DICTV, f"(A) dictv= is FNV-1a 64 of the dictionary body ({DICTV} vs {h:016x})")
check(m is not None and int(m.group(2)) == body.count("\n"), f"(A) entries= counts the dictionary's lines")
ROSTER = [l.split("\t") for l in roster_p.stdout.splitlines() if l.strip()] if roster_p.returncode == 0 else []
check(len(ROSTER) >= 40, f"(A) the roster lists the completeness attributes ({len(ROSTER)} rows)")
undefined = sorted({a for a, _, _ in ROSTER if not re.search(r'(?<![\w])' + re.escape(a) + r'=', DICT)}) if DICT else ["<no dictionary>"]
check(not undefined, f"(A) every roster attribute is spelled attr= in the dictionary (undefined: {undefined[:8]})")
check(bad.returncode != 0 and "roster" in bad.stderr, f"(A) --legend-dict=bogus refuses, naming roster (rc={bad.returncode})")
s0 = session([("@resources/list", {}), ("@resources/read", {"uri": "ripwire://nope"})])
init = s0[0][1] if s0 and s0[0][0] == "init" else ""
check(len(init.encode()) <= 1000 and f"dictv={DICTV}" in init and "ripwire://legend-dict" in init,
      f"(A) initialize carries the pointer and the same dictv in <= 1,000 B ({len(init.encode())} B)")
check(len(s0) > 1 and "ripwire://legend-dict/full" in s0[1][1] and "ripwire://legend-dict\"" in s0[1][1], "(A) resources/list names both resources")
check(len(s0) > 2 and s0[2][0] == "error" and "-32002" in s0[2][1], "(A) an unknown resource uri refuses with -32002")

# ── the session every later arm reads ──────────────────────────────────────────────────────────────────────────────
CALLS = [
    ("impact",       {"symbol": "helper"}),
    ("uses",         {"symbol": "helper"}),
    ("path_between", {"from": "caller", "to": "helper"}),
    ("connect",      {"symbols": ["caller", "helper", "work"]}),
    ("explore",      {"task": "work doubles the helper"}),
    ("from_trace",   {"trace": "#0 helper core.c:2\n#1 work core.c:4"}),
    ("edit_check",   {"symbol": "work"}),
    ("lego",         {"type": "Shape"}),
    ("exemplar",     {"task": "doubles a value"}),
    ("slice",        {"symbol": "caller", "var": "acc"}),
    ("analyze",      {}),
    ("owners",       {}),
    ("whereis",      {"symbol": "work"}),
    ("batch",        {"queries": [{"verb": "uses", "symbol": "work"}, {"verb": "impact", "symbol": "work"}]}),
    ("for",          {"task": "work doubles the helper"}),
    ("for",          {"task": "helper"}),
]
N = len(CALLS)
READ = ("@resources/read", {"uri": "ripwire://legend-dict"})
S = session(CALLS + [READ] + CALLS + CALLS)
ctrl = session(CALLS)                               # never reads the dictionary
refarg = session([(v, dict(a, legend="ref")) if v not in ("for",) else (v, a) for v, a in CALLS])
FULL = session([(v, dict(a, legend="full")) for v, a in CALLS if v != "for"])
full_by = {i: t for (i, (v, a)), (_, t) in zip([(i, c) for i, c in enumerate(CALLS) if c[0] != "for"], FULL[1:])}
check(len(S) == 1 + 3 * N + 1, f"(setup) the session answered every request ({len(S) - 1} of {3 * N + 1})")
pre, res, second, third = S[1:1 + N], S[1 + N], S[2 + N:2 + 2 * N], S[2 + 2 * N:]

# ── (B) ref only after serve ───────────────────────────────────────────────────────────────────────────────────────
print("=== (B) ref only after the dictionary was served in this process ===")
check(all(not is_ref(t) for _, t in pre), "(B) no answer before the read carries <about legend=\"ref\">")
check([t for _, t in pre] == [t for _, t in ctrl[1:]], "(B) every pre-read answer is byte-identical to a session that never reads the dictionary")
check(all(not is_ref(t) for _, t in refarg[1:]) and [t for _, t in refarg[1:]] == [t for _, t in ctrl[1:]],
      "(B) legend:\"ref\" before the read is the inline answer, byte-identical")
check(res[0] == "resource" and f"dictv={DICTV}" in res[1], "(B) the resource read serves the core with the same dictv")
refs = [(i, t) for i, (_, t) in enumerate(third) if t.lstrip().startswith("<")]
nonref = [CALLS[i][0] for i, t in refs if not is_ref(t)]
check(not nonref, f"(B) every XML answer of a repeated call after the read is ref (not ref: {nonref})")
NREF = sum(1 for _, t in refs if is_ref(t))
bad_v = [CALLS[i][0] for i, t in refs if is_ref(t) and f'dictv="{DICTV}"' not in t]
check(not bad_v, f"(B) every ref answer names the dictionary's dictv ({bad_v})")
def row_first(t):
    m = re.match(r'\s*<[A-Za-z][\w.-]*(?:\s+[\w:-]+="[^"]*")*\s*>(.)', t, re.S)
    return m is not None and m.group(1) == "<" and not t[m.end() - 1:].startswith("<!--")
check(all(row_first(t) for _, t in refs if is_ref(t)), "(B) a ref answer's root is followed by a row (or <about>), never a comment")

# An explicit inline posture after the read is exactly that posture: legend:"compact" the pre-read answer, legend:"full"
# the full answer of a session that never read the dictionary.
inl = [(v, dict(a, legend="compact")) for v, a in CALLS if v != "for"] + [(v, dict(a, legend="full")) for v, a in CALLS if v != "for"]
SI = session([READ] + inl)
nfor = sum(1 for v, _ in CALLS if v != "for")
pre_nf = [t for (v, _), (_, t) in zip(CALLS, pre) if v != "for"]
check([t for _, t in SI[2:2 + nfor]] == pre_nf, "(B) legend:\"compact\" after the read is the pre-read inline answer, byte-identical")
check([t for _, t in SI[2 + nfor:]] == [t for _, t in FULL[1:]], "(B) legend:\"full\" after the read is the full answer, byte-identical")

# ── (C) served once ────────────────────────────────────────────────────────────────────────────────────────────────
print("=== (C) every definition reaches the session once ===")
entries = []
for line in body.splitlines():
    if line.startswith("ripwire.") and "/v1 <" in line: entries.append(line.split(">: ", 1)[1])
    elif line.startswith("for: "):                         entries.append(line[5:])
    else:                                                  entries.append(line)
post = res[1] + "".join("".join(comments(t)) for _, t in second + third if is_ref(t))
twice = [e[:60] for e in entries if len(e) > 12 and post.count(e) > 1]
check(NREF >= 12 and not twice, f"(C) over {NREF} ref answers, no dictionary entry reaches the session twice through the resource or a ref answer ({len(twice)}: {twice[:3]})")
# An answer whose ref form would be LONGER than its inline one is served inline (F's budget reserve) and repeats its own
# legend: that answer must be byte-identical to the pre-read inline answer, never a third shape.
kept = [CALLS[i][0] for i, (_, t) in enumerate(second) if t.lstrip().startswith("<") and not is_ref(t) and t != pre[i][1]]
check(not kept, f"(C) an answer kept inline after the read is the inline answer, byte-identical ({kept})")
legend_in_third = [CALLS[i][0] for i, t in refs if is_ref(t) and any(c.startswith("<!-- ripwire ") and "/v1: " in c for c in comments(t))]
check(not legend_in_third, f"(C) a repeated call's ref answer carries no legend ({legend_in_third})")

# ── (D) nothing honesty-bearing moves out ──────────────────────────────────────────────────────────────────────────
print("=== (D) the trailer carries every root attribute; the rows keep theirs ===")
diffs = []
for i, t in refs:
    if not is_ref(t): continue
    twin = full_by.get(i) if CALLS[i][0] != "for" else pre[i][1]
    if twin is None or pairs(t) != pairs(twin): diffs.append(CALLS[i][0])
check(NREF >= 12 and not diffs, f"(D) over {NREF} ref answers, each ref answer carries the same attribute name=value multiset as its inline twin (differ: {diffs})")
# est_tokens= is the answer's DELIVERED price (L1's budget work), not a fact about the corpus: it must track the bytes
# this answer actually carries, so it is the one attribute that SHOULD differ between a ref answer and its longer twin.
# Excluded from the multiset above and asserted here instead — present in both, and never priced above the twin.
def est(t):
    m = re.search(r'\sest_tokens="(\d+)"', t)
    return int(m.group(1)) if m else None
badprice = []
for i, t in refs:
    if not is_ref(t): continue
    twin = full_by.get(i) if CALLS[i][0] != "for" else pre[i][1]
    er, ef = est(t), est(twin) if twin else None
    if (er is None) != (ef is None) or (er is not None and er > ef): badprice.append((CALLS[i][0], er, ef))
check(not badprice, f"(D) est_tokens= is the answer's own delivered price: present in both postures, never above the twin ({badprice[:3]})")
KEEP = {"task", "changed", "from", "to"}
badroot, badlast = [], []
for i, t in refs:
    if not is_ref(t): continue
    m = re.match(r'\s*<([A-Za-z][\w.-]*)((?:\s+[\w:-]+="[^"]*")*)\s*>', t)
    if not m or any(k not in KEEP for k, _ in attrs(m.group(2))): badroot.append(CALLS[i][0])
    if not re.search(r'<about [^>]*/></' + re.escape(m.group(1) if m else "x") + r'>\s*$', t): badlast.append(CALLS[i][0])
check(not badroot, f"(D) a ref root keeps only task=/changed=/from=/to= ({badroot})")
check(not badlast, f"(D) <about …/> is the root's last child ({badlast})")
hon = {a for a, _, _ in ROSTER}
cnt = lambda t: sum(1 for k, _ in pairs(t) if k in hon)
cdiff = [CALLS[i][0] for i, t in refs if is_ref(t) and cnt(t) != cnt(full_by.get(i) or pre[i][1])]
check(not cdiff, f"(D) the per-answer honesty-attribute count is equal between ref and full ({cdiff})")

# ── (E) roster honesty, every posture ──────────────────────────────────────────────────────────────────────────────
print("=== (E) every roster attribute an answer carries is defined where the reader holds it (inline and ref) ===")
def roster_hits(t):
    hits = set()
    for el, a in tags(t):
        for k, _ in attrs(a):
            for ra, rel, _src in ROSTER:
                if ra == k and (rel == "*" or rel == el): hits.add(k)
    return hits
def defined(name, text): return re.search(r'(?<![\w])' + re.escape(name) + r'=', text) is not None
gaps = []
for label, answers in (("inline", [(i, t) for i, (_, t) in enumerate(pre)]),):
    for i, t in answers:
        if not t.lstrip().startswith("<"): continue
        own = "".join(comments(t))
        gaps += [f"{label}:{CALLS[i][0]}@{a}" for a in sorted(roster_hits(t)) if not defined(a, own)]
held = res[1]
for i, (_, t) in enumerate(second + third):
    held += "".join(comments(t))
    if t.lstrip().startswith("<") and is_ref(t):
        gaps += [f"ref:{CALLS[i % N][0]}@{a}" for a in sorted(roster_hits(t)) if not defined(a, held)]
check(NREF >= 12 and not gaps, f"(E) over {NREF} ref answers and every inline one, no roster attribute rides undefined in any posture ({len(gaps)}: {gaps[:6]})")

# ── (F) budget reserve ─────────────────────────────────────────────────────────────────────────────────────────────
print("=== (F) a ref answer is never longer than its inline twin ===")
longer = [f"{CALLS[i][0]} {len(t)}>{len(pre[i][1])}" for i, t in refs if is_ref(t) and len(t) > len(pre[i][1])]
check(NREF >= 12 and not longer, f"(F) over {NREF} ref answers, every ref answer <= the inline answer it replaces ({longer})")
bud = [("explore", {"task": "work doubles the helper", "budget_tokens": 300}), ("for", {"task": "work doubles the helper", "budget_tokens": 300})]
SB = session(bud + [READ] + bud + bud)
blong = [f"{bud[k][0]} {len(SB[2 + 2 * len(bud) + k][1])}>{len(SB[1 + k][1])}" for k in range(len(bud))
         if is_ref(SB[2 + 2 * len(bud) + k][1]) and len(SB[2 + 2 * len(bud) + k][1]) > len(SB[1 + k][1])]
bref = sum(1 for k in range(len(bud)) if is_ref(SB[2 + 2 * len(bud) + k][1]))
check(bref == len(bud) and not blong, f"(F) under budget_tokens=300 the ref answers ({bref}/{len(bud)}) stay within the inline ones ({blong})")

# ── (G) CLI unchanged ──────────────────────────────────────────────────────────────────────────────────────────────
print("=== (G) the CLI has no session: no ref ===")
r = subprocess.run([BIN, FX, "--callers=helper", "--legend=ref"], capture_output=True, text=True)
check(r.returncode != 0 and "ripwire://legend-dict" in r.stderr and not r.stdout, f"(G) --legend=ref refuses on the CLI, naming the resource (rc={r.returncode})")
for flags in ([], ["--legend=compact"]):
    r = subprocess.run([BIN, FX, "--callers=helper"] + flags, capture_output=True, text=True)
    check(r.returncode == 0 and "<about " not in r.stdout, f"(G) CLI --callers {' '.join(flags) or '(default)'} carries no <about>")

# --legend-dict reads the WHOLE argv before it prints, so one command line has one verdict whatever the order.
# Answering at the first occurrence made `--legend-dict=roster --legend-dict=bad` exit 0 and print the roster while
# the same two flags reversed exited 1 — a typo honoured or refused depending on where it sat (CodeRabbit 4056670839).
for argv, wantRc, why in (
    (["--legend-dict"],                                  0, "bare prints the dictionary"),
    (["--legend-dict=roster"],                           0, "=roster prints the roster"),
    (["--legend-dict", "--legend-dict"],                 0, "the same form twice is one answer, not a conflict"),
    (["--legend-dict=bad"],                              1, "an unknown value is refused"),
    (["--legend-dict=bad", "--legend-dict=roster"],      1, "an unknown value BEFORE a good one is refused"),
    (["--legend-dict=roster", "--legend-dict=bad"],      1, "an unknown value AFTER a good one is refused too"),
    (["--legend-dict", "--legend-dict=roster"],          1, "two different forms are a conflict, not a preference"),
):
    r = subprocess.run([BIN] + argv, capture_output=True, text=True)
    good = r.returncode == wantRc and (bool(r.stdout) if wantRc == 0 else (not r.stdout and "--legend-dict" in r.stderr))
    check(good, f"(G) {' '.join(argv)} -> rc {r.returncode} (want {wantRc}): {why}")

# ── (H) L6 un-grouping ─────────────────────────────────────────────────────────────────────────────────────────────
print("=== (H) a small runner-less group prints as its rows under ref ===")
ei = [i for i, (v, _) in enumerate(CALLS) if v == "explore"][0]
g = re.search(r'<g [^>]*n="(\d)" p="([^"]*)"[^>]*/>', pre[ei][1])
check(g is not None and int(g.group(1)) <= 8, "(H) the inline explore answer carries a <g n<=8 p=> group")
t3 = third[ei][1]
if g:
    rows = re.findall(r'<test p="([^"]*)"[^>]*run_unknown="1"/>', t3)
    check(is_ref(t3) and "<g " not in t3 and all(p in rows for p in g.group(2).split(",")),
          f"(H) its ref twin carries those {g.group(1)} paths as single <test run_unknown=\"1\"> rows and no <g>")

# ── (I) G4 holds in the ref posture ────────────────────────────────────────────────────────────────────────────
print("=== (I) a ref answer is well-formed XML with no newline outside CDATA (G4) ===")
import xml.etree.ElementTree as ET
illformed = []
for i, t in refs:
    if not is_ref(t): continue
    try:
        ET.fromstring(t)
        if "\n" in strip_cdata(t).rstrip("\n"): illformed.append(CALLS[i][0] + ":newline")
    except ET.ParseError as e:
        illformed.append(f"{CALLS[i][0]}:{e}")
check(NREF >= 12 and not illformed, f"(I) over {NREF} ref answers, every one parses and keeps its newlines inside CDATA ({illformed})")

# ── (J) THE DEFAULT SESSION (lean-answers lane): the twin of (A)-(F)/(I) on the stdio default ─────────────────────────────
# The session opens on its first answer the dictionary can reduce: that answer is the inline answer, byte for byte;
# every later reducible answer is ref (or, where ref would be longer, the inline answer); the core reaches the session
# once, in its first ref answer; no entry is sent twice; every roster attribute is defined where the reader holds it.
print("=== (J) the default session: first answer inline, later answers ref ===")
DEF = []
D = session(CALLS + CALLS, server=DEF)
check(len(D) == 1 + 2 * N, f"(J) the default session answered every request ({len(D) - 1} of {2 * N})")
dinit = D[0][1] if D and D[0][0] == "init" else ""
check(len(dinit.encode()) <= 1000 and f"dictv={DICTV}" in dinit and "ripwire://legend-dict/full" in dinit,
      f"(J) the default initialize names the posture, the same dictv and the full dictionary in <= 1,000 B ({len(dinit.encode())} B)")
dans = D[1:]
check(dans[0][1] == pre[0][1] and not is_ref(dans[0][1]), "(J) the session's first answer is the inline answer, byte-identical to the pre-read one")
drefs = [(i, t) for i, (_, t) in enumerate(dans) if i > 0 and t.lstrip().startswith("<")]
DNREF = sum(1 for _, t in drefs if is_ref(t))
dinline = [CALLS[i % N][0] for i, t in drefs if not is_ref(t) and t != pre[i % N][1]]
check(DNREF >= 12 and not dinline, f"(J) every later XML answer is ref ({DNREF}) or the inline answer byte for byte (third shapes: {dinline})")
core0 = "<about legend=\"ref\" dict= dictv=>"
firstref = next((t for _, t in drefs if is_ref(t)), "")
check(core0 in "".join(comments(firstref)), "(J) the first ref answer carries the dictionary core (the reading of <about legend=\"ref\">)")
dpost = "".join("".join(comments(t)) for _, t in drefs if is_ref(t))
dtwice = [e[:60] for e in entries if len(e) > 12 and dpost.count(e) > 1]
check(not dtwice and dpost.count(core0) == 1, f"(J) no dictionary entry reaches the session twice through its ref answers ({dtwice[:3]})")
ddiff = [CALLS[i % N][0] for i, t in drefs if is_ref(t) and pairs(t) != pairs(full_by.get(i % N) if CALLS[i % N][0] != "for" else pre[i % N][1])]
check(not ddiff, f"(J) each ref answer carries the same attribute name=value multiset as its inline twin ({ddiff})")
dheld, dgaps = "", []
for i, (_, t) in enumerate(dans):
    dheld += "".join(comments(t))
    if t.lstrip().startswith("<") and is_ref(t):
        dgaps += [f"{CALLS[i % N][0]}@{a}" for a in sorted(roster_hits(t)) if not defined(a, dheld)]
check(not dgaps, f"(J) no roster attribute of a ref answer rides undefined by the bytes this session sent ({dgaps[:6]})")
dlong = [f"{CALLS[i % N][0]} {len(t)}>{len(pre[i % N][1])}" for i, t in drefs if is_ref(t) and len(t) > len(pre[i % N][1])]
check(not dlong, f"(J) every ref answer <= the inline answer it replaces ({dlong})")
dill = []
for i, t in drefs:
    if not is_ref(t): continue
    try:
        ET.fromstring(t)
        if "\n" in strip_cdata(t).rstrip("\n"): dill.append(CALLS[i % N][0] + ":newline")
    except ET.ParseError as e:
        dill.append(f"{CALLS[i % N][0]}:{e}")
check(not dill, f"(J) every default-session ref answer is well-formed G4 XML ({dill})")
DI = session([CALLS[0]] + [(v, dict(a, legend="compact")) for v, a in CALLS if v != "for"], server=DEF)
check([t for _, t in DI[2:]] == pre_nf, "(J) legend:\"compact\" in an open default session keeps that answer inline, byte-identical")
r = subprocess.run([BIN, "--mcp-legend=inline"], capture_output=True, text=True)
r2 = subprocess.run([BIN, "--mcp", "--mcp-legend=bogus"], capture_output=True, text=True, input="")
check(r.returncode != 0 and r2.returncode != 0, f"(J) --mcp-legend without --mcp, and an unknown value, refuse (rc={r.returncode}/{r2.returncode})")

print(f"legendrefcheck: {'FAIL' if fails else 'PASS'} ({len(fails)} failing)")
sys.exit(1 if fails else 0)
PY

# ── the fixture: a git tree with a call chain, an interface, and three runner-less C tests (so pack-task groups them) ──
FX="$TMP/fx"
mkdir -p "$FX/src" "$FX/tests" "$FX/docs"
cat >"$FX/src/core.c" <<'EOF'
/* helper adds one */
int helper(int x) { return x + 1; }
/* work doubles the helper */
int work(int y) { return helper(y) * 2; }
int caller(void) { int acc = 0; acc = work(3); acc += helper(acc); return acc; }
EOF
cat >"$FX/src/shape.h" <<'EOF'
struct Shape { virtual int area() const = 0; virtual ~Shape() {} };
struct Square : Shape { int s; int area() const override { return s * s; } };
struct Circle : Shape { int r; int area() const override { return 3 * r * r; } };
EOF
for n in one two three; do
    printf 'int work(int);\nint test_%s(void) { return work(1) == 4; }\n' "$n" >"$FX/tests/test_$n.c"
done
printf '# Notes\nThe `work` function doubles `helper`.\n' >"$FX/docs/README.md"
( cd "$FX" && git init -q . && git -c user.name=t -c user.email=t@t add -A && git -c user.name=t -c user.email=t@t commit -qm init ) \
    || no "could not build the git fixture"

if [ "$fail" -eq 0 ]; then
    python3 "$TMP/arms.py" "$BIN" "$ROSTER_BIN" "$FX" "$TMP" || fail=1
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "legendrefcheck: FAILURES ABOVE"
exit "$fail"

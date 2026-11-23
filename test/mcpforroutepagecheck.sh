#!/usr/bin/env bash
# mcpforroutepagecheck.sh — a routed MCP `for` answer is held to the page (lane MR1, owner ruling 168): RL1's seam
# (src/verbs_forroute.h, test/forroutepagecheck.sh) on the MCP twin, continued through the MCP paging contract.
#
#   test/mcpforroutepagecheck.sh [BIN]     # BIN defaults to $RIPWIRE_BIN, then build/ripwire; BASE_BIN= adds arm (N3)
#
# WHY. MCP `for` routes a question that names its symbol and asks a call-graph question to the CLI's routed answer (RT2 parity,
# mcpForVerbRoute), and a warned one carries MCP's own `for` bundle — unpaged — as its last child. RL1 held the CLI's routed answer
# to 12,000 B; the MCP twin was left unpaged (forkeybody.h:27, verbs_forroute.h's MCP note). MEASURED on 36a95d732 on the fixtures
# below: a routed MCP answer printed up to 48,582 B.
#
# THE RULE. Count an answer from its root's open tag on, comments (outside CDATA) and KB1's key group set aside: <= 12,000 B,
# and <= 24,000 characters as printed. What does not fit is one MCP call away and LOSSLESS, in MCP's own paging contract:
#   * the verb's rows are WINDOWED (root shown= total= has_more="1" next_offset=K): `for` with offset=K continues them (RT3-F1's
#     mcpForVerbContinue), each window held to the page too;
#   * the carried page is MCP's whole `for` bundle when it fits what the verb's part left, else MCP's FILE PAGE of the same ranking
#     (`for` limit=L, a <files> root with has_more="1" next_offset=K) cut to fit: `for` limit=L offset=K continues it — MCP has no
#     byte page of the bundle, and limit/offset is the paging contract its `for` already answers.
# Arm classes (LANE_CONSTRAINTS §17): [P] NEW — red on 36a95d732; [C] holds on every binary; [N] must not change; [M] mutation control.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "mcpforroutepagecheck: python3 required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "mcpforroutepagecheck: xmllint required"; exit 2; }
DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
echo "mcpforroutepagecheck: BIN=$BIN${BASE_BIN:+ BASE_BIN=$BASE_BIN}"

BIN="$BIN" BASE="${BASE_BIN:-}" DIR="$DIR" ROWLINES="$ROOT/test" python3 - <<'PY'
import html, json, os, re, subprocess, sys
BIN, BASE, W = os.environ["BIN"], os.environ["BASE"], os.environ["DIR"]
sys.path.insert(0, os.environ["ROWLINES"])
from rowlines import decode          # MCP `for` may serve its bundle rows as lines (mcpforrowscheck); decoded wherever rows are read

PAGE, kInlineChars = 12000, 24000    # the page size (foranswerfirst.h kAnswerPageBytesDefault); forroutepagecheck's inline bar
bad = 0


def say(okay, msg):
    global bad
    print("  %s  %s" % ("PASS" if okay else "FAIL", msg))
    bad += 0 if okay else 1


# ── forroutepagecheck's corpus, written here: wide/ 240 callers, deep/ 280 commented callers + a registered callback (warns), small/ fits
def corpus(name, mods, fns, rich, cb):
    d = os.path.join(W, name)
    os.makedirs(d)
    open(d + "/lib.h", "w").write("int compute_total( int a );\n")
    open(d + "/lib.c", "w").write('#include "lib.h"\nint compute_total( int a )\n{\n    return a + 1;\n}\n')
    for m in range(mods):
        s = '#include "lib.h"\n'
        for f in range(fns):
            if rich:
                s += "// step %d of module %d: folds one value into the running total\n" % (f, m)
            s += "int mod_%02d_step_%d( int v )\n{\n    return compute_total( v + %d );\n}\n" % (m, f, f)
            if rich:
                s += "static int mod_%02d_scale_%d( int v )\n{\n    return v * %d;\n}\n" % (m, f, f + 2)
        open(d + "/mod_%02d.c" % m, "w").write(s)
    if cb:
        open(d + "/cb.c", "w").write('#include "lib.h"\nstruct ops\n{\n    int ( *on_total )( int );\n};\nstatic int total_hook( int c )\n{\n'
                                     '    return compute_total( c );\n}\nstatic struct ops table = { total_hook };\nint dispatch( int c )\n{\n'
                                     '    return table.on_total( c );\n}\n')
    return d


# many/ (MR1's own): 400 modules x 1 caller and the registered callback — a warned route whose file page (402 files) cannot fit whole
FX = {"wide": corpus("wide", 30, 8, False, False), "deep": corpus("deep", 70, 4, True, True), "small": corpus("small", 6, 4, False, False),
      "many": corpus("many", 400, 1, False, True)}
Q = {"who": "Who calls `compute_total`?", "uses": "Where is `compute_total` used?", "imp": "Trace the transitive callers of `compute_total`.",
     "none": "How does the step total get computed?"}
VERB = {"who": "--callers=compute_total", "uses": "--uses=compute_total", "imp": "--impact=compute_total"}


def mcp(fx, calls, binary=None, env_off=False):
    env = dict(os.environ)
    env.pop("RIPWIRE_NO_ROWLINES", None)
    if env_off:
        env["RIPWIRE_NO_ROWLINES"] = "1"
    req = [{"jsonrpc": "2.0", "id": 0, "method": "initialize"}]
    req += [{"jsonrpc": "2.0", "id": i, "method": "tools/call", "params": {"name": "for", "arguments": a}} for i, a in enumerate(calls, 1)]
    p = subprocess.run([binary or BIN, FX[fx], "--mcp", "--mcp-legend=inline"], input="".join(json.dumps(r) + "\n" for r in req).encode(),
                       capture_output=True, env=env)
    got = {}
    for line in p.stdout.decode("utf8", "replace").splitlines():
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if isinstance(r.get("id"), int) and r["id"] > 0:
            got[r["id"]] = "".join(c.get("text", "") for c in r.get("result", {}).get("content", [])).encode("utf8")
    return [got.get(i, b"") for i in range(1, len(calls) + 1)]


def one(fx, **kw):
    return mcp(fx, [dict(task=kw.pop("task"), **kw)])[0]


TOK = re.compile(rb'<!\[CDATA\[.*?\]\]>|<!--.*?-->|<(/?)([A-Za-z_][\w.-]*)((?:"[^"]*"|[^>"])*?)(/?)>', re.S)


def blocks(doc):
    """(root open tag match, [(name, begin, end, open tag)] of the root's children; a comment's name is '!')."""
    out, stack, root, cur = [], [], None, None
    for m in TOK.finditer(doc):
        t = m.group(0)
        if t.startswith(b"<![CDATA["):
            continue
        if t.startswith(b"<!--"):
            if len(stack) == 1:
                out.append((b"!", m.start(), m.end(), b""))
            continue
        if m.group(1):
            stack.pop()
            if len(stack) == 1 and cur:
                out.append((cur[0], cur[1], m.end(), cur[2]))
                cur = None
            continue
        if not stack:
            root = m
        elif len(stack) == 1:
            if m.group(4):
                out.append((m.group(2), m.start(), m.end(), t))
            else:
                cur = (m.group(2), m.start(), t)
        if not m.group(4):
            stack.append(m.group(2))
    return root, out


def counted(doc):
    """from the root on, every comment outside CDATA and KB1's key group set aside"""
    root, bl = blocks(doc)
    body = doc[root.start():] if root else doc
    for nm, b, e, t in bl:
        if nm == b"bodies" and b'of="key"' in t:
            body = body.replace(doc[b:e], b"", 1)
    n = len(body)
    for m in re.finditer(rb"<!\[CDATA\[.*?\]\]>|<!--.*?-->", body, re.S):
        n -= len(m.group(0)) if m.group(0).startswith(b"<!--") else 0
    return n


def attr(tag, name):
    m = re.search(rb'(?<![\w])' + name.encode() + rb'="([^"]*)"', tag)
    return html.unescape(m.group(1).decode()) if m else ""


FIXED = (b"!", b"route", b"text_only", b"def", b"bodies", b"ctx", b"files")   # (callers/uses: a <files> child is only ever the carried page)


def verb_rows(doc):
    root, bl = blocks(doc)
    if root.group(2) != b"impact":
        return [doc[b:e] for nm, b, e, _ in bl if nm not in FIXED]
    rows, d = [], b""
    for r in [doc[b:e] for nm, b, e, _ in bl if nm == b"s"]:
        m = re.search(rb' d="[^"]*"', r)
        d = m.group(0) if m else d
        rows.append(r if m else r[:-2] + d + b"/>")
    return rows


def carried(doc):
    """the carried page: the root's LAST element child when it is a <ctx>/<files> answer of its own (task= on it); --impact's own
    <files> sections carry no task="""
    root, bl = blocks(doc)
    el = [b for b in bl if b[0] != b"!"]
    return doc[el[-1][1]:el[-1][2]] if el and el[-1][0] in (b"ctx", b"files") and b' task="' in el[-1][3] else b""


def well(doc):
    return subprocess.run(["xmllint", "--noout", "-"], input=doc, capture_output=True).returncode == 0 \
        and b"\n" not in re.sub(rb"<!\[CDATA\[.*?\]\]>", b"", doc.rstrip(b"\n"), flags=re.S)


ANS = {(fx, k): one(fx, task=Q[k]) for fx in FX for k in Q}
routed = [c for c in ANS if c[1] != "none"]
say(all(blocks(ANS[c])[1] and blocks(ANS[c])[1][0][0] == b"route" for c in routed) and all(blocks(ANS[c, "none"])[0].group(2) == b"ctx" for c in FX),
    "(R0) [C] the nine named questions are ROUTED on MCP (<route> first) and the three unnamed ones are MCP's `for` bundle")

over = ["%s/%s %d" % (c[0], c[1], counted(ANS[c])) for c in sorted(routed) if counted(ANS[c]) > PAGE]
say(not over, "(R1) [P] every routed MCP `for` answer counts <= %d B (largest: %d B)" % (PAGE, max(counted(ANS[c]) for c in routed))
    if not over else "(R1) [P] over the %d B page: %s" % (PAGE, ", ".join(over)))
chars = {c: len(ANS[c].decode("utf8", "replace")) for c in routed}
over = ["%s/%s %d" % (c[0], c[1], n) for c, n in sorted(chars.items()) if n > kInlineChars]
say(not over, "(R2) [P] every routed MCP `for` answer prints <= %d characters (largest: %d)" % (kInlineChars, max(chars.values()))
    if not over else "(R2) [P] over %d characters: %s" % (kInlineChars, ", ".join(over)))

win = [c for c in routed if attr(blocks(ANS[c])[0].group(0), "has_more") == "1" and attr(blocks(ANS[c])[0].group(0), "limit") not in ("", "0")]
fpage = [c for c in routed if blocks(carried(ANS[c]))[0] is not None and blocks(carried(ANS[c]))[0].group(2) == b"files"]
whole = [c for c in routed if blocks(carried(ANS[c]))[0] is not None and blocks(carried(ANS[c]))[0].group(2) == b"ctx"]
say(win and fpage, "(R3) [P] non-vacuous: %d answers window the verb's rows, %d carry a fitted file page, %d carry the whole bundle"
    % (len(win), len(fpage), len(whole)))
def fp_open(c):
    return blocks(carried(ANS[c]))[0].group(0)


cutfp = [c for c in fpage if attr(fp_open(c), "has_more") == "1"]
say(cutfp and all(attr(fp_open(c), "offset") == "0" and int(attr(fp_open(c), "limit") or 0) > 0
                  and (c not in cutfp or int(attr(fp_open(c), "next_offset") or 0) == int(attr(fp_open(c), "shown"))) for c in fpage),
    "(R3b) [P] a carried file page is limit=L offset=0, and %d of %d are cut short: has_more=\"1\" next_offset=shown= (MCP's paging contract)"
    % (len(cutfp), len(fpage)))

# (L1) [C] the verb's windows: page 1 + every `for` offset=K = the verb's unwindowed rows, each window inside the page
chains = {}
for c in routed:
    fx, k = c
    rows, doc, hops, okc = verb_rows(ANS[c]), ANS[c], 0, True
    while attr(blocks(doc)[0].group(0), "has_more") == "1" and hops < 300:
        doc = one(fx, task=Q[k], offset=int(attr(blocks(doc)[0].group(0), "next_offset")))
        hops += 1
        if not doc or counted(doc) > PAGE or not well(doc) or blocks(doc)[1][0][0] != b"route":
            okc = False
            break
        rows += verb_rows(doc)
    full = subprocess.run([BIN, FX[fx], VERB[k], "--limit=100000"], capture_output=True).stdout
    chains[c] = (rows, verb_rows(full), hops, okc)
badc = ["%s/%s (%d rows of %d, %d calls%s)" % (c[0], c[1], len(v[0]), len(v[1]), v[2], "" if v[3] else ", a window broke or is over the page")
        for c, v in sorted(chains.items()) if not v[3] or v[0] != v[1] or not v[1]]
say(not badc, "(L1) [C] the routed verb's rows continue losslessly at `for` offset=K, each window inside the page: %s"
    % ", ".join("%s/%s %d rows in %d calls" % (c[0], c[1], len(v[1]), v[2] + 1) for c, v in sorted(chains.items())) if not badc
    else "(L1) [C] the windows do not rebuild the verb's rows: " + "; ".join(badc))
c0 = max(chains, key=lambda c: chains[c][2])
say(chains[c0][2] > 0 and chains[c0][0][:-1] != chains[c0][1], "(L1m) [M] the same comparison fails when one row is dropped from %s/%s's chain" % c0)

# (L2) [C] a carried file page continues at `for` limit=L offset=K: the chain's <f> rows = the file page at limit=100000
F = re.compile(rb"<f [^>]*/>")
l2 = {}
for c in fpage:
    fx, k = c
    pg = carried(ANS[c])
    rows, doc, hops, okc = F.findall(pg), pg, 0, True
    lim = int(attr(blocks(pg)[0].group(0), "limit"))
    while attr(blocks(doc)[0].group(0), "has_more") == "1" and hops < 400:
        doc = one(fx, task=Q[k], limit=lim, offset=int(attr(blocks(doc)[0].group(0), "next_offset")))
        hops += 1
        if not doc or not well(doc) or blocks(doc)[0].group(2) != b"files":
            okc = False
            break
        rows += F.findall(doc)
    l2[c] = (rows, F.findall(one(fx, task=Q[k], limit=100000, offset=0)), hops, okc)
badc = ["%s/%s" % c for c, v in sorted(l2.items()) if not v[3] or v[0] != v[1] or not v[1]]
say(l2 and not badc, "(L2) [C] the carried file page continues losslessly at `for` limit=L offset=K: %s"
    % ", ".join("%s/%s %d rows in %d calls" % (c[0], c[1], len(v[1]), v[2] + 1) for c, v in sorted(l2.items())) if l2 and not badc
    else "(L2) [C] the carried file page does not rebuild the whole file page: " + (", ".join(badc) or "no file page carried"))
if l2:
    c0 = max(l2, key=lambda c: l2[c][2])
    say(l2[c0][0][:-1] != l2[c0][1], "(L2m) [M] the same comparison fails when one <f> row is dropped from %s/%s's chain" % c0)

# (M1) [M] the count's own control: doubled verb rows go over
c0 = max(routed, key=lambda c: counted(ANS[c]))
vr = verb_rows(ANS[c0])
fat = ANS[c0].replace(vr[0], b"".join(vr) + vr[0], 1) if vr else ANS[c0]
say(counted(ANS[c0]) <= PAGE < counted(fat), "(M1) [M] (R1)'s count goes over the page when %s/%s's rows are doubled (%d -> %d B)"
    % (c0[0], c0[1], counted(ANS[c0]), counted(fat)))

# (D1) (X1) [C]
say(all(one(c[0], task=Q[c[1]]) == ANS[c] for c in routed), "(D1) [C] every routed answer is byte-identical across two runs")
say(all(well(ANS[c]) for c in ANS), "(X1) [C] every answer is well-formed XML with no newline outside CDATA")
# (N1) [N] a shaped call never routes: no_verb_route, budget_tokens, limit=
say(all(b"<route " not in re.sub(rb"<!--.*?-->", b"", d, flags=re.S) for d in
        (one("deep", task=Q["who"], no_verb_route=True), one("deep", task=Q["who"], budget_tokens=4000), one("deep", task=Q["who"], limit=5))),
    "(N1) [N] no_verb_route, budget_tokens and limit= are never routed")
# (N2) [N] a routed answer that fits is unwindowed and carries no file page
small = [c for c in routed if c[0] == "small"]   # every routed answer on small/ fits
say(all(attr(blocks(ANS[c])[0].group(0), "has_more") != "1" and c not in fpage for c in small),
    "(N2) [N] a routed answer that fits the page is unwindowed and carries no file page (small/: %d answers)" % len(small))
# (N3) [N] against BASE_BIN, both in element rows (the row form is mcpforrowscheck's): what fitted before is byte-identical
if BASE:
    mine = {c: mcp(c[0], [dict(task=Q[c[1]])], env_off=True)[0] for c in ANS}
    base = {c: mcp(c[0], [dict(task=Q[c[1]])], binary=BASE, env_off=True)[0] for c in ANS}
    kept = [c for c in sorted(ANS) if counted(base[c]) <= PAGE]
    diff = [c for c in kept if base[c] != mine[c]]
    say(kept and not diff, "(N3) [N] every MCP `for` answer BASE_BIN already kept inside the page is byte-identical (%d of %d)" % (len(kept), len(ANS))
        if not diff else "(N3) [N] changed although BASE_BIN's answer fitted: %s" % diff)
print("mcpforroutepagecheck: %s" % ("PASS" if bad == 0 else "FAIL (%d)" % bad))
sys.exit(1 if bad else 0)
PY

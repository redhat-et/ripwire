#!/usr/bin/env bash
# forroutepagecheck.sh — RL1: a default `--for` answer never prints more than one page of rows, ROUTED OR NOT.
#
#   test/forroutepagecheck.sh [BIN]     # BIN defaults to $RIPWIRE_BIN, then build/ripwire; BASE_BIN= adds arm (N3)
#
# WHY. A bare `--for=Q` that names a symbol and asks a call-graph question is answered by --callers / --uses / --impact
# (src/verbs_forroute.h), and on evidence the verb may be partial the first --for page rides along. Before RL1 neither part
# was held to the page: the verb printed its own window (240 caller rows, 14 KB, on the fixture below) and the carried page was
# a full 12,000 B page on top of it. MEASURED (results/RL1_ROUTED_PAGING_1121): GA1 DEV ga-zod-12 printed 30,325 B, and in a live
# agent session (TR1 D/ga-zod-12) Claude Code's Bash tool persisted the 30,849 B answer to a file and showed the agent a 2 KB
# preview — the answer never reached the context it was written for.
#
# THE RULE THIS GATE PINS. Count a page the way src/forpages.h counts one: every byte from the root's open tag on that is not the
# legend (a --for page's trailing document legend, a verb answer's comments), not KB1's key-body group (no page counts it), and
# not the page disclosure the pager adds after the cut (page= pages= withheld_bytes= continued= deferred= next= and the close of
# a section left open). A block-local legend inside a --for page counts, as it does for the pager. That count is <= the page size
# (12,000 B) on every default answer, and the whole answer as printed stays under the client's inline limit with a margin
# (kInlineChars below). What does not fit is one pasteable call away and LOSSLESS: the verb's rows continue at
# `--for=Q --offset=K` (RT3-F1), the carried page at `--for=Q --page-bytes=S:2` (AF1).
#
# Arm classes (LANE_CONSTRAINTS §17): [P] a NEW bar — RED on the parent a0c020bb6, that is its control; [C] holds on every
# binary; [N] must NOT change; [M] a mutation control: the same check FAILS when one row is dropped or one page is inflated.
set -u
# θ5 (src/forpages.h): this gate reads the FULL page-1 legend of a default --for answer (or pins its bytes/rows); the default's
# core legend is pinned by test/corelegendcheck.sh, so the full legend is switched back on here.
export RIPWIRE_NO_CORE_LEGEND=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
BASE="${BASE_BIN:-}"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "forroutepagecheck: python3 required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "forroutepagecheck: xmllint required"; exit 2; }
DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
echo "forroutepagecheck: BIN=$BIN${BASE:+ BASE_BIN=$BASE}"

BIN="$BIN" BASE="$BASE" DIR="$DIR" ROWLINES="$ROOT/test" python3 - <<'PY'
import html, os, re, shlex, subprocess, sys
BIN, BASE, W = os.environ["BIN"], os.environ["BASE"], os.environ["DIR"]
sys.path.insert(0, os.environ["ROWLINES"])
from rowlines import decode          # FMT2's decoder: the default answer serves <sigs>/<tail> rows as lines

PAGE = 12000           # src/foranswerfirst.h kAnswerPageBytesDefault
INLINE = 30000         # Claude Code's Bash tool persists a larger output and shows a 2 KB preview (MEASURED once, TR1 D/ga-zod-12; the
                       # documented BASH_MAX_OUTPUT_LENGTH default — UNVERIFIED against the docs by this lane)
kInlineChars = 24000   # the bar: 20 % under INLINE
bad = 0


def say(okay, msg):
    global bad
    print("  %s  %s" % ("PASS" if okay else "FAIL", msg))
    bad += 0 if okay else 1


# ── the corpus, written here ─────────────────────────────────────────────────────────────────────────────────────────
# wide/   lib.c defines compute_total(); 30 modules x 8 functions call it (240 callers, 14 KB of caller rows unwindowed).
# deep/   70 modules x 4 callers, each beside a static helper and under a doc comment (a --for answer of three 6 KB pages),
#         plus cb.c: total_hook() calls compute_total() and is REGISTERED as a value (W1's value-hop: the route warns).
# small/  6 modules x 4 callers: every routed answer fits the page whole.
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


FX = {"wide": corpus("wide", 30, 8, False, False), "deep": corpus("deep", 70, 4, True, True), "small": corpus("small", 6, 4, False, False)}
Q = {"who": "Who calls `compute_total`?", "uses": "Where is `compute_total` used?", "imp": "Trace the transitive callers of `compute_total`.",
     "none": "How does the step total get computed?"}
VERB = {"who": "--callers=compute_total", "uses": "--uses=compute_total", "imp": "--impact=compute_total"}


def run(fx, args, binary=None):
    r = subprocess.run([binary or BIN, FX[fx]] + args, stdin=subprocess.DEVNULL, capture_output=True)
    return r.returncode, r.stdout


# ── reading an answer ────────────────────────────────────────────────────────────────────────────────────────────────
TOK = re.compile(rb'<!\[CDATA\[.*?\]\]>|<!--.*?-->|<(/?)([A-Za-z_][\w.-]*)((?:"[^"]*"|[^>"])*?)(/?)>', re.S)


def blocks(doc):
    """(root open tag match, [(name, begin, end, open tag bytes)] of the root's children; a comment's name is '!')."""
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


def is_key(b):
    return b[0] == b"bodies" and b'of="key"' in b[3]


DISCLOSURE = re.compile(rb' (?:page|pages|withheld_bytes|continued|deferred|next)="[^"]*"')


def uncounted_of_page(ctx):
    """Bytes of one --for page the pager does not count: comments, the key group, its own disclosure, a continued section's close."""
    root, bl = blocks(ctx)
    last = max([i for i, b in enumerate(bl) if b[0] != b"!"], default=-1)   # the comments after the last row block: the document legend
    n = sum(b[2] - b[1] for i, b in enumerate(bl) if is_key(b) or (b[0] == b"!" and (i > last or (i + 1 < len(bl) and is_key(bl[i + 1])))))
    n += sum(len(x) for x in DISCLOSURE.findall(root.group(0)))
    m = re.search(rb' continued="([^"]*)"', root.group(0))
    return n + (len(m.group(1)) + 3 if m else 0)


def counted(doc):
    """The page rule's count of a default answer (see the header)."""
    root, bl = blocks(doc)
    if root.group(2) == b"ctx":
        return len(doc) - root.start() - uncounted_of_page(doc[root.start():])
    n = len(doc.rstrip(b"\n")) - root.start()
    for b in bl:
        if b[0] == b"!" or is_key(b):
            n -= b[2] - b[1]
        elif b[0] == b"ctx":
            n -= uncounted_of_page(doc[b[1]:b[2]])
    return n


def attr(tag, name):
    m = re.search(rb'(?<![\w])' + name.encode() + rb'="([^"]*)"', tag)
    return html.unescape(m.group(1).decode()) if m else ""


FIXED = (b"!", b"route", b"text_only", b"def", b"bodies", b"ctx")


def verb_rows(doc):
    """The verb's WINDOWED rows. --impact's root also carries per-answer sections every window repeats (<files>, the importer
    <f> rows): its windowed rows are the <s> rows, and only those are compared."""
    root, bl = blocks(doc)
    if root.group(2) != b"impact":
        return [doc[b:e] for nm, b, e, _ in bl if nm not in FIXED]
    rows, d = [], b""   # an <s> row spells d= (its depth) only where it changes, and again on a window's first row: spell it on every row
    for r in [doc[b:e] for nm, b, e, _ in bl if nm == b"s"]:
        m = re.search(rb' d="[^"]*"', r)
        d = m.group(0) if m else d
        rows.append(r if m else r[:-2] + d + b"/>")
    return rows


def carried(doc):
    root, bl = blocks(doc)
    c = [doc[b:e] for nm, b, e, _ in bl if nm == b"ctx"]
    return c[0] if c else b""


def page_tokens(ctx):
    """One --for page as row tokens: every start tag and text run below the root, the key group and comments set aside. A section's
    own open tag is returned apart (a continuation page re-opens the section it starts inside)."""
    d = decode(ctx)
    root, bl = blocks(d)
    toks = []
    for b in bl:
        if b[0] == b"!" or is_key(b) or b[0] == b"about":
            continue
        inner = re.sub(rb"<!--.*?-->", b"", d[b[1]:b[2]], flags=re.S)
        m = re.match(rb"<[^>]*>", inner)
        close = b"</" + b[0] + b">"
        body = inner[m.end():-len(close)] if inner.endswith(close) else inner[m.end():]   # a continued section's close is the pager's
        rows = re.findall(rb"<!\[CDATA\[.*?\]\]>|</?[A-Za-z][^>]*>|[^<]+", body, re.S)
        toks.append((m.group(0), rows))
    return toks


def join_pages(pages):
    """Concatenate pages: a section re-opened at a page's start continues the one the page before left open."""
    out = []
    for p in pages:
        for k, (opn, rows) in enumerate(p):
            if k == 0 and out and out[-1][0] == opn:
                out[-1][1].extend(rows)
            else:
                out.append((opn, list(rows)))
    return out


def follow(fx, nxt, limit=80):
    """Run a pasteable next= (split the way a shell would)."""
    return run(fx, shlex.split(nxt))


# ── the default answers ──────────────────────────────────────────────────────────────────────────────────────────────
ANS = {}
for fx in ("wide", "deep", "small"):
    for k in Q:
        rc, out = run(fx, ["--for=" + Q[k]])
        ANS[fx, k] = out
        if rc != 0 or not out:
            say(False, "(setup) %s/%s: rc=%d, %d B" % (fx, k, rc, len(out)))
routed = [c for c in ANS if c[1] != "none"]
say(all(blocks(ANS[c])[1] and blocks(ANS[c])[1][0][0] == b"route" for c in routed) and all(blocks(ANS[c, "none"])[0].group(2) == b"ctx" for c in FX),
    "(R0) [C] the nine named questions are ROUTED (<route> is the root's first child) and the three unnamed ones are --for answers")

# (R1) [P] the page rule, on every default answer
over = ["%s/%s %d" % (c[0], c[1], counted(ANS[c])) for c in sorted(ANS) if counted(ANS[c]) > PAGE]
say(not over, "(R1) [P] every default --for answer counts <= %d B the way the pager counts a page (largest: %d B)"
    % (PAGE, max(counted(a) for a in ANS.values())) if not over else "(R1) [P] over the %d B page: %s" % (PAGE, ", ".join(over)))
# (R2) [P] and the answer as printed stays inline
chars = {c: len(ANS[c].decode("utf8", "replace")) for c in ANS}
over = ["%s/%s %d" % (c[0], c[1], n) for c, n in sorted(chars.items()) if n > kInlineChars]
say(not over, "(R2) [P] every default --for answer prints <= %d characters, legends included (largest: %d; the client's inline limit is %d)"
    % (kInlineChars, max(chars.values()), INLINE) if not over else "(R2) [P] over %d characters: %s" % (kInlineChars, ", ".join(over)))

# (R3) [P] not vacuous: the fixtures need both halves of the mechanism
win = [c for c in routed if attr(blocks(ANS[c])[0].group(0), "has_more") == "1"]
paged = [c for c in routed if carried(ANS[c]) and int(attr(blocks(carried(ANS[c]))[0].group(0), "pages") or 1) > 1]
shrunk = [c for c in win if attr(blocks(ANS[c])[0].group(0), "limit") not in ("", "0")]
say(shrunk and paged, "(R3) [P] the fixtures exercise both halves: %d routed answers window the verb's rows to fit, %d carry a --for page cut short of 12,000 B"
    % (len(shrunk), len(paged)))
sizes = sorted({attr(blocks(carried(ANS[c]))[0].group(0), "next").rsplit("--page-bytes=", 1)[-1] for c in paged})
say(paged and all(re.fullmatch(r"[0-9]+:2", s) and 0 < int(s[:-2]) < PAGE for s in sizes),
    "(R3b) [P] a cut carried page's next= is page 2 at ITS size (%s): a page of the same --for answer" % ", ".join(sizes))

# (L1) [C] (it held before RL1 too; RL1 adds windows cut by a row limit, and (L1m) is its control) the verb's rows are a WINDOW: page 1 + every `--for=Q --offset=K` = the verb's own unwindowed rows, in order
chains = {}
for c in routed:
    fx, k = c
    rows, doc, hops, okc = verb_rows(ANS[c]), ANS[c], 0, True
    while attr(blocks(doc)[0].group(0), "has_more") == "1" and hops < 300:
        nxt = attr(blocks(doc)[0].group(0), "next")
        if not nxt.startswith("--for=") or "--offset=" not in nxt:
            okc = False
            break
        rc, doc = follow(fx, nxt)
        hops += 1
        if rc != 0 or counted(doc) > PAGE or subprocess.run(["xmllint", "--noout", "-"], input=doc, capture_output=True).returncode != 0:
            okc = False
            break
        rows += verb_rows(doc)
    rc, whole = run(fx, [VERB[k], "--limit=100000"])
    chains[c] = (rows, verb_rows(whole), hops, okc)
badc = ["%s/%s (%d rows of %d, %d calls%s)" % (c[0], c[1], len(v[0]), len(v[1]), v[2], "" if v[3] else ", chain broke or a window is over the page")
        for c, v in sorted(chains.items()) if not v[3] or v[0] != v[1] or not v[1]]
say(not badc, "(L1) [C] the routed verb's rows continue losslessly at next= (`--for=Q --offset=K`), every window well-formed and inside the page: %s"
    % ", ".join("%s/%s %d rows in %d calls" % (c[0], c[1], len(v[1]), v[2] + 1) for c, v in sorted(chains.items())) if not badc
    else "(L1) [C] the routed windows do not rebuild the verb's rows: " + "; ".join(badc))
c0 = max(chains, key=lambda c: chains[c][2])
say(chains[c0][2] > 0 and chains[c0][0][:-1] != chains[c0][1], "(L1m) [M] the same comparison fails when one row is dropped from %s/%s's chain" % c0)

# (L2) [C] the carried page is a WINDOW too: it + every page its next= names = the unpaged --for answer's rows
l2 = {}
for c in routed:
    fx, k = c
    pg = carried(ANS[c])
    if not pg:
        continue
    pages, doc, okc = [page_tokens(pg)], pg, True
    while attr(blocks(doc)[0].group(0), "next") and len(pages) < 80:
        rc, doc = follow(fx, attr(blocks(doc)[0].group(0), "next"))
        if rc != 0 or blocks(doc)[0].group(2) != b"ctx" or subprocess.run(["xmllint", "--noout", "-"], input=doc, capture_output=True).returncode != 0:
            okc = False
            break
        pages.append(page_tokens(doc))
    rc, whole = run(fx, ["--for=" + Q[k], "--page-bytes=0"])
    l2[c] = (join_pages(pages), join_pages([page_tokens(whole)]), len(pages), okc, pages)
badc = ["%s/%s" % c for c, v in sorted(l2.items()) if not v[3] or v[0] != v[1] or not v[1]]
say(l2 and not badc, "(L2) [C] the carried --for page continues losslessly at its next=: %s"
    % ", ".join("%s/%s %d page%s" % (c[0], c[1], v[2], "" if v[2] == 1 else "s") for c, v in sorted(l2.items())) if l2 and not badc
    else "(L2) [C] the carried page and its continuation do not rebuild --page-bytes=0: " + (", ".join(badc) or "no carried page on any fixture"))
if l2:
    c0 = max(l2, key=lambda c: l2[c][2])
    cut = [[(o, list(r)) for o, r in p] for p in l2[c0][4]]
    cut[-1][-1][1].pop()
    say(l2[c0][2] > 1 and join_pages(cut) != l2[c0][1], "(L2m) [M] the same comparison fails when one row is dropped from %s/%s's last page" % c0)

# (M1) [M] the page rule's own control: the same count is over the page once an answer's rows are doubled
c0 = max(routed, key=lambda c: counted(ANS[c]))
rows = verb_rows(ANS[c0])
fat = ANS[c0].replace(rows[0], b"".join(rows) + rows[0], 1)
say(counted(ANS[c0]) <= PAGE < counted(fat), "(M1) [M] (R1)'s count goes over the page when %s/%s's rows are doubled (%d -> %d B)"
    % (c0[0], c0[1], counted(ANS[c0]), counted(fat)))

# (D1) [C] determinism, (X1) [C] well-formedness, no newline outside CDATA (G4)
same = all(run(c[0], ["--for=" + Q[c[1]]])[1] == ANS[c] for c in ANS)
say(same, "(D1) [C] every default answer is byte-identical across two runs")
illf = [c for c in ANS if subprocess.run(["xmllint", "--noout", "-"], input=ANS[c], capture_output=True).returncode != 0
        or b"\n" in re.sub(rb"<!\[CDATA\[.*?\]\]>", b"", ANS[c].rstrip(b"\n"), flags=re.S)]
say(not illf, "(X1) [C] every default answer is well-formed XML with no newline outside CDATA" if not illf else "(X1) [C] ill-formed: %s" % illf)

# (N1) [N] a spelled --page-bytes never routes — the carried page's next= and ES's next= are pages of the --for answer because of it
rc, spelled = run("deep", ["--for=" + Q["who"], "--page-bytes=12000"])
say(rc == 0 and blocks(spelled)[0].group(2) == b"ctx" and b"<route " not in re.sub(rb"<!--.*?-->", b"", spelled, flags=re.S),
    "(N1) [N] --page-bytes=12000 (the default size, spelled) is the --for answer, never routed")
# (N2) [N] an answer that fits is not windowed: no limit on the verb, the carried page (when there is one) whole or at most the default page
small = [c for c in routed if c[0] == "small"]
say(all(attr(blocks(ANS[c])[0].group(0), "limit") in ("", "0") and attr(blocks(ANS[c])[0].group(0), "has_more") != "1" for c in small),
    "(N2) [N] a routed answer that fits the page is the verb's own answer, unwindowed (small/: %d answers)" % len(small))
# (N3) [N] against the parent binary: what fitted before is byte-identical
if BASE:
    # "kept inside the page": it counts <= PAGE and its carried page, if any, is the whole --for answer (a carried page the pager
    # had to cut at 12,000 B was a full page on top of the verb's rows)
    def fitted(doc):
        pg = carried(doc)
        return counted(doc) <= PAGE and not (pg and attr(blocks(pg)[0].group(0), "pages"))
    base = {c: run(c[0], ["--for=" + Q[c[1]]], BASE)[1] for c in ANS}
    kept = [c for c in sorted(ANS) if fitted(base[c])]
    diff = [c for c in kept if base[c] != ANS[c]]
    say(kept and not diff, "(N3) [N] every answer the parent already kept inside the page is byte-identical (%d of %d)" % (len(kept), len(ANS))
        if not diff else "(N3) [N] changed although the parent's answer fitted: %s" % diff)
print("forroutepagecheck: %s" % ("PASS" if bad == 0 else "FAIL (%d)" % bad))
sys.exit(1 if bad else 0)
PY

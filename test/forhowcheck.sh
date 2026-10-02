#!/usr/bin/env bash
# forhowcheck.sh — the how-it-works answer (fix #10): on a task the frozen trigger fires on, with default arguments and one
# root, `--for`, `--pack-task`, MCP `for` and MCP `explore` serve the shape="how" sections (<path>, <h> hops, <b> selected
# body lines, <names>) — byte-identical across the four surfaces — and every other input keeps the pre-change answer.
#
# WRITTEN BEFORE THE CODE IT MEASURES (CLAUDE.md non-negotiable #1); arms (C)/(U) and the near misses joined at the gates
# review, before any table run. Arms:
#   (T) the TEXT trigger, on all four surfaces: each registered prefix fires, case-, quote- and space-insensitively (curly
#       quotes, a backtick, tab/newline-led, ALL CAPS); near misses — a prefix without its trailing space ("how isolated",
#       "what happens whenever", "how-does", "how  does", a bare "how does"), a prefix inside the sentence, the excluded
#       openers — do not.
#   (A) DEFAULT ARGUMENTS ONLY: any shaping flag, a second root, --json, --format=candidates, --limit, a budget or --no-route
#       keeps the pre-change shape, on the CLI and on MCP (for: limit/offset/budget_tokens/no_route/sections/paths;
#       explore: budget_tokens/partition/no_route/paths — `paths` even with ONE root, any key besides task/path/legend);
#       --legend=full and the cache, and explore's legend:"full"|"compact", keep the trigger.
#   (P) PARITY: the bytes from `<path` to `</names>` are identical on CLI --for, CLI --pack-task, MCP for and MCP explore
#       (fixture, this repo's src/, and an answer the ceiling trims), each root spelled the same way.
#   (D) LEGEND + COUNTS: every attribute of every element is defined `name=` in the answer's leading comments (compact, full,
#       MCP); shown <= total and capped="1" iff shown < total; lines_shown <= sel <= lines_total and the CDATA holds exactly
#       lines_shown numbered lines; each body <= 1,024 B of lines and <= 2,048 B in all.
#   (F) FOLLOW-UPS: each next= returns every row it cut — a hop's callees, a seed's callers (every shown row among them too),
#       a body's lines (its --expand chain or whole-file serving covering p= .. +lines_total), <names>' window rows.
#   (S) SEEDS: a backticked identifier is the first seed; a qualified one (`.`, `::`, `#`, `->`) picks the definition its
#       qualifier names among two same-named ones; an unmatched qualifier falls back to every definition of the last
#       segment; a conceptual question's first seed is the definition whose NAME carries the question's terms.
#   (R) REF POSTURE (Gate D's dictionary leg), on `for` and on `explore`: in a session that read the legend dictionary, the
#       second triggered answer defines every attribute it carries in its own comments or in the dictionary text the session
#       read, and carries none of the how clauses the first answer already sent.
#   (C) THE CEILING, on the whole first answer (8,192 B, the CLI default document): names are cut first, then deeper hops'
#       callee rows, then body lines; <path> and every seed row are untouched; each cut is counted (cut_*= on <path>, and the
#       element's own shown=/lines_shown=); the cut rows plus the shown rows are the uncapped answer's rows, and each cut row
#       is returned by its element's next=; over_ceiling="1" iff the answer is still over 8,192 B.
#   (U) F2-uncapped (RIPWIRE_HOW_UNCAPPED=1) is byte-identical to the answer whenever the answer is under the ceiling.
#   (X) xmllint well-formed and two runs byte-identical.
#
# Usage: bash test/forhowcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/forhowcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
cd "$ROOT"
echo "forhowcheck: BIN=$BIN"
TMP="$( mktemp -d )"
trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP/" XDG_CACHE_HOME="$TMP/xdg" BIN
unset RIPWIRE_HOW_UNCAPPED
FIX="$ROOT/test/forhowfix"
Q="how does the router dispatch a request"

# ── the helpers every arm reads ───────────────────────────────────────────────────────────────────────────────────────
cat >"$TMP/h.py" <<'PY'
import html, json, os, re, shlex, subprocess, sys
BIN = os.environ["BIN"]
def mcp(path, calls, ref=False):
    """one MCP session: initialize, optionally read the dictionary, then the calls; returns (texts, dictionary text)"""
    msgs = [{"jsonrpc": "2.0", "id": 1, "method": "initialize"}]
    if ref:
        msgs.append({"jsonrpc": "2.0", "id": 9, "method": "resources/read", "params": {"uri": "ripwire://legend-dict"}})
    for i, (tool, args) in enumerate(calls):
        a = dict(args) if "paths" in args else dict(path=path, **args)
        msgs.append({"jsonrpc": "2.0", "id": 100 + i, "method": "tools/call", "params": {"name": tool, "arguments": a}})
    p = subprocess.run([BIN, "--mcp"], input="".join(json.dumps(m) + "\n" for m in msgs).encode(), capture_output=True, timeout=900)
    res, dic = {}, ""
    for line in p.stdout.decode("utf-8", "replace").splitlines():
        try: j = json.loads(line)
        except ValueError: continue
        if j.get("id") == 9 and j.get("result"):
            dic = "".join(c.get("text", "") for c in j["result"].get("contents", []))
        if isinstance(j.get("id"), int) and j["id"] >= 100:
            r = j.get("result")
            res[j["id"]] = r["content"][0]["text"] if r else "ERROR " + json.dumps(j.get("error"))
    return [res.get(100 + i, "") for i in range(len(calls))], dic
def cli(path, *args, env=None):
    e = dict(os.environ); e.update(env or {})
    return subprocess.run([BIN, path, "--no-cache", *args], capture_output=True, env=e).stdout.decode("utf-8", "replace")
REGION = re.compile(r"<path[ >/].*?</names>", re.S)
def region(doc):
    m = REGION.search(doc); return m.group(0) if m else None
def is_how(doc): return region(doc) is not None
def lead(doc):
    m = re.match(r"\s*<[A-Za-z][^>]*>", doc)
    if not m: return ""
    i, out = m.end(), []
    while doc.startswith("<!--", i):
        j = doc.find("-->", i); out.append(doc[i:j + 3]); i = j + 3
    return "".join(out)
def nocdata(doc): return re.sub(r"<!\[CDATA\[.*?\]\]>", "", doc, flags=re.S)
def attrs(doc):
    s = set()
    for t in re.finditer(r"<([A-Za-z][\w-]*)((?:\s+[\w:-]+=\"[^\"]*\")*)\s*/?>", nocdata(re.sub(r"<!--.*?-->", "", doc, flags=re.S))):
        for a in re.finditer(r"([\w:-]+)=\"", t.group(2)): s.add((t.group(1), a.group(1)))
    return s
def undefined(doc, legend=None):
    lg = lead(doc) if legend is None else legend
    return sorted("%s@%s" % (e, a) for e, a in attrs(doc) if not re.search(r"(?<![\w-])" + re.escape(a) + "=", lg))
def A(s): return dict(re.findall(r"([\w-]+)=\"([^\"]*)\"", s))
def counts(doc):
    bad = []
    for m in re.finditer(r"<(\w+)((?:\s+[\w-]+=\"[^\"]*\")*)\s*/?>", nocdata(doc)):
        a = A(m.group(2))
        if "shown" in a and "total" in a:
            s, t, c = int(a["shown"]), int(a["total"]), a.get("capped", "0")
            if s > t or (c == "1") != (s < t): bad.append("<%s shown=%d total=%d capped=%s>" % (m.group(1), s, t, c))
    tot = 0; nb = 0
    rg = region(doc)
    if rg is None: return ["no <path…</names> region (vacuous)"]
    for m in re.finditer(r"<b ([^>]*)><!\[CDATA\[(.*?)\]\]></b>", rg, re.S):
        a = A(m.group(1)); nb += 1
        if not all(k in a for k in ("lines_shown", "sel", "lines_total", "next")):
            bad.append("<b n=%s> lacks lines_shown/sel/lines_total/next" % a.get("n")); continue
        ls, sel, lt = int(a["lines_shown"]), int(a["sel"]), int(a["lines_total"])
        lines = [x for x in m.group(2).split("\n") if x]
        nums = [int(x.split(":", 1)[0]) for x in lines if re.match(r"\d+: ", x)]
        if not (0 <= ls <= sel <= lt) or len(nums) != ls or len(lines) != ls or nums != sorted(nums):
            bad.append("<b n=%s> ls=%d sel=%d lt=%d lines=%d" % (a.get("n"), ls, sel, lt, len(lines)))
        if len(m.group(2).encode()) > 1024: bad.append("<b n=%s> %d B of lines > 1024" % (a.get("n"), len(m.group(2).encode())))
        tot += len(m.group(2).encode())
    if tot > 2048: bad.append("bodies %d B > 2048" % tot)
    if nb > 3: bad.append("%d bodies > 3" % nb)
    for m in re.finditer(r"<h ([^>]*)>(.*?)</h>", nocdata(doc), re.S):
        a = A(m.group(1)); body = re.sub(r"<us .*?</us>", "", m.group(2), flags=re.S)
        if "shown" in a and int(a["shown"]) != len(re.findall(r"<c ", body)): bad.append("<h n=%s> shown=%s rows=%d" % (a.get("n"), a["shown"], len(re.findall(r"<c ", body))))
        for u in re.finditer(r"<us ([^>]*)>(.*?)</us>", m.group(2), re.S):
            if int(A(u.group(1))["shown"]) != len(re.findall(r"<u ", u.group(2))): bad.append("<us> of %s" % a.get("n"))
    nm = re.search(r"<names ([^>]*)>(.*?)</names>", doc, re.S)
    if nm and int(A(nm.group(1))["shown"]) != len([x for x in nm.group(2).split(";") if x.strip()]): bad.append("<names> shown= vs rows")
    return bad
SROWS = lambda got: set(re.findall(r"<s [^>]*?n=\"([^\"]*)\" p=\"([^\"]*)\"", got))
def body_lines_returned(path, b):
    """every source line of <b>'s body that its next= returns: the --expand chain's numbered body (ours among the
    same-named definitions it serves), or the whole-file serving's lines covering p= .. p= + lines_total - 1"""
    f, line = b["p"].rsplit(":", 1); first, total = int(line), int(b["lines_total"])
    nxt, got_lines = html.unescape(b["next"]), set()
    while nxt:
        got = cli(path, "--top-k=0", *shlex.split(nxt)); nxt = None
        for bm in re.finditer(r"<b ([^>]*)><!\[CDATA\[(.*?)\]\]>", got, re.S):
            ba = A(bm.group(1))
            if ba.get("p") == f and ba.get("l") == line:
                lo = int(ba["lines"].split("-")[0]) if "lines" in ba else 1
                for k, _ in enumerate(bm.group(2).rstrip("\n").split("\n")): got_lines.add(first + lo - 1 + k)
                nxt = html.unescape(ba["next"]) if ba.get("truncated") == "1" else None
        sm = re.search(r"<src p=\"" + re.escape(f) + r"\"[^>]*><!\[CDATA\[(.*?)\]\]>", got, re.S)
        if sm:
            got_lines |= set(range(1, len(sm.group(1).split("\n")) + 1))
    return all(l in got_lines for l in range(first, first + total))
def follow(path, doc):
    bad = []
    doc = region(doc)
    if doc is None: return ["no <path…</names> region (vacuous)"]
    for m in re.finditer(r"<h ([^>]*)>(.*?)</h>", nocdata(doc), re.S):
        a = A(m.group(1))
        if a.get("capped") == "1":
            got = cli(path, *shlex.split(html.unescape(a["next"])))
            rows = SROWS(got); names = {n for n, _ in rows}
            shown = re.findall(r"<c n=\"([^\"]*)\"", re.sub(r"<us .*?</us>", "", m.group(2), flags=re.S))
            if len(rows) < int(a["total"]) or 'has_more="1"' in got or any(html.unescape(n) not in names for n in shown):
                bad.append("hop %s %s" % (a.get("n"), a["next"]))
        for u in re.finditer(r"<us ([^>]*)>(.*?)</us>", m.group(2), re.S):
            ua = A(u.group(1))
            if ua.get("capped") == "1":
                got = cli(path, *shlex.split(html.unescape(ua["next"])))
                rows = SROWS(got)
                shown = set(re.findall(r"<u n=\"([^\"]*)\" p=\"([^\"]*)\"", u.group(2)))
                if len(rows) < int(ua["total"]) or 'has_more="1"' in got or not all((html.unescape(n), p) in rows for n, p in shown):
                    bad.append("callers %s" % ua["next"])
    for m in re.finditer(r"<b ([^>]*)>", doc):
        a = A(m.group(1))
        if not body_lines_returned(path, a): bad.append("body %s" % a["next"])
    nm = re.search(r"<names ([^>]*)>(.*?)</names>", doc, re.S)
    if nm:
        a = A(nm.group(1))
        got = cli(path, *shlex.split(html.unescape(a["next"])))
        cands = set("%s %s:%s" % c for c in re.findall(r"<cand [^>]*?n=\"([^\"]*)\"[^>]*?p=\"([^\"]*)\"[^>]*?l=\"(\d+)\"", got))
        for row in [x.strip() for x in nm.group(2).split(";") if x.strip()]:
            if html.unescape(row) not in cands: bad.append("names row %s not in %s" % (row, a["next"]))
        if len(cands) < int(a["total"]): bad.append("names next= %d rows < total=%s" % (len(cands), a["total"]))
    return bad
PY

# ── (T) the text trigger, on all four surfaces ─────────────────────────────────────────────────────────────────────────
python3 - "$TMP" "$FIX" <<'PY' >"$TMP/t.out" 2>&1
import sys; sys.path.insert(0, sys.argv[1]); from h import *
fix = sys.argv[2]
fires = ["how does the router dispatch a request", "How do routes match a path", "how is a request validated",
         "how are responses rendered", "how can a handler raise", "explain how the router dispatches",
         "walk me through dispatching a request", "what happens when a route is missing", '  "How does the router dispatch',
         "'how is a response encoded'", "“How does the router dispatch a request”", "`how does the router dispatch a request`",
         "\thow does the router dispatch", "\nhow does the router dispatch", "HOW DOES THE ROUTER DISPATCH A REQUEST"]
quiet = ["how many routes are there", "how much does dispatch cost", "how often is a route matched", "how long does dispatch take",
         "where does the router dispatch a request", "router dispatch: how does it work", "howdoes the router dispatch",
         "how isolated are routes", "what happens whenever a route is missing", "how to dispatch a request",
         "how-does the router dispatch", "how  does the router dispatch", "how does", "so how does the router dispatch",
         "explain the router dispatch", "walk me throughput of the router", "how dose the router dispatch", "how\tdoes the router dispatch"]
bad = []
calls = [("for", {"task": q}) for q in fires + quiet] + [("explore", {"task": q}) for q in fires + quiet]
texts, _ = mcp(fix, calls)
n = len(fires) + len(quiet)
for i, q in enumerate(fires + quiet):
    want = i < len(fires)
    got = {"cli-for": is_how(cli(fix, "--for=" + q)), "cli-packtask": is_how(cli(fix, "--pack-task=" + q)),
           "mcp-for": is_how(texts[i]), "mcp-explore": is_how(texts[n + i])}
    for k, v in got.items():
        if v != want: bad.append("%s %s %r" % (k, "missed" if want else "fired on", q))
print("BAD " + "; ".join(bad) if bad else "OK %d fire, %d near misses quiet, on 4 surfaces" % (len(fires), len(quiet)))
PY
grep -q '^OK' "$TMP/t.out" && ok "(T) $( sed 's/^OK //' "$TMP/t.out" ) (case, curly/straight quotes, backtick, tab/newline-led)" \
                            || { no "(T) trigger:"; cut -c1-600 "$TMP/t.out"; }

# ── (A) default arguments only ──────────────────────────────────────────────────────────────────────────────────────────
python3 - "$TMP" "$FIX" "$ROOT/test/archfix" <<'PY' >"$TMP/a.out" 2>&1
import sys; sys.path.insert(0, sys.argv[1]); from h import *
fix, two = sys.argv[2], sys.argv[3]
Q = "how does the router dispatch a request"
bad = []
for extra in ["--token-budget=3000", "--format=candidates", "--json", "--signatures-only", "--limit=5", "--no-route", "--detail=2",
              "--sections=lego,compose", "--adaptive", "--auto-bodies"]:
    if is_how(cli(fix, "--for=" + Q, extra)): bad.append("CLI --for %s fired" % extra)
if is_how(subprocess.run([BIN, fix, two, "--no-cache", "--for=" + Q], capture_output=True).stdout.decode()): bad.append("two roots fired")
if is_how(cli(fix, "--pack-task=" + Q, "--token-budget=3000")): bad.append("pack-task budget fired")
for extra in ["--legend=full", "--legend=compact"]:
    if not is_how(cli(fix, "--for=" + Q, extra)): bad.append("CLI %s did not fire" % extra)
if not is_how(subprocess.run([BIN, fix, "--for=" + Q], capture_output=True).stdout.decode()): bad.append("default cache did not fire")
quiet = [("for", {"task": Q, "limit": 5}), ("for", {"task": Q, "offset": 5}), ("for", {"task": Q, "budget_tokens": 3000}),
         ("for", {"task": Q, "no_route": True}), ("for", {"task": Q, "sections": "lego,compose"}),
         ("for", {"task": Q, "paths": [fix, two]}), ("for", {"task": Q, "paths": [fix]}),
         ("explore", {"task": Q, "budget_tokens": 3000}), ("explore", {"task": Q, "partition": 2}), ("explore", {"task": Q, "no_route": True}),
         ("explore", {"task": Q, "paths": [fix, two]}), ("explore", {"task": Q, "paths": [fix]})]
loud = [("explore", {"task": Q, "legend": "full"}), ("explore", {"task": Q, "legend": "compact"}), ("explore", {"task": Q}), ("for", {"task": Q})]
texts, _ = mcp(fix, quiet + loud)
for k, ((tool, args), t) in enumerate(zip(quiet + loud, texts)):
    want = k >= len(quiet)
    if is_how(t) != want: bad.append("MCP %s %s %s" % (tool, json.dumps({x: v for x, v in args.items() if x != "task"}), "fired" if not want else "did not fire"))
print("BAD " + "; ".join(bad) if bad else "OK")
PY
grep -q '^OK' "$TMP/a.out" && ok "(A) CLI shaping flags, two roots, MCP limit/offset/budget/no_route/sections/partition/paths (1 or 2 roots) keep the pre-change answer; --legend, the cache and explore's legend keep the trigger" \
                            || { no "(A) default-arguments rule:"; cut -c1-800 "$TMP/a.out"; }

# ── (C) the big fixture: an answer the ceiling must trim, and one it cannot bring under ───────────────────────────────
python3 - "$TMP/big" <<'PY'
import os, sys
d = sys.argv[1]; os.makedirs(d, exist_ok=True)
params = ", ".join("argument_number_%02d_with_a_rather_long_name" % k for k in range(2))
out = []
for i in range(14):
    out.append("def run_pipeline_stage_%02d(%s):" % (i, params))
    out.append("    if argument_number_00_with_a_rather_long_name is None:")
    out.append("        return None")
    for j in range(6):
        out.append("    value_%d = pipeline_stage_helper_%02d_%d(argument_number_%02d_with_a_rather_long_name, argument_number_01_with_a_rather_long_name)" % (j, i, j, j % 2))
    out.append("    return run_pipeline_stage_%02d(%s)" % ((i + 1) % 14, params))
    out.append("")
    for j in range(6):
        out.append("def pipeline_stage_helper_%02d_%d(first_argument_of_the_helper, second_argument_of_the_helper):" % (i, j))
        out.append("    if first_argument_of_the_helper:")
        out.append("        return pipeline_stage_leaf_%02d(second_argument_of_the_helper)" % ((i * 9 + j) % 20))
        out.append("    return second_argument_of_the_helper")
        out.append("")
for k in range(20):
    out.append("def pipeline_stage_leaf_%02d(value):" % k)
    out.append("    return value")
    out.append("")
open(os.path.join(d, "pipeline.py"), "w").write("\n".join(out) + "\n")
PY
BIGQ="how does the pipeline run each stage"
LONGQ="how does the pipeline run each stage $( python3 -c 'print(" ".join("considering every detail of stage %d of the pipeline" % k for k in range(80)))' )"
python3 - "$TMP" "$TMP/big" "$BIGQ" "$LONGQ" <<'PY' >"$TMP/c.out" 2>&1
import sys; sys.path.insert(0, sys.argv[1]); from h import *
big, q, longq = sys.argv[2], sys.argv[3], sys.argv[4]
bad, notes = [], []
def rows(doc):
    rg = region(doc); p = re.search(r"<path ([^>]*)>(.*?)</path>", rg, re.S)
    hops = []
    for m in re.finditer(r"<h ([^>]*)>(.*?)</h>", nocdata(rg), re.S):
        hops.append((A(m.group(1)), re.findall(r"<c n=\"([^\"]*)\"", re.sub(r"<us .*?</us>", "", m.group(2), flags=re.S)), re.sub(r"<c [^>]*/>", "", m.group(2))))
    bodies = [(A(m.group(1)), [x for x in m.group(2).split("\n") if x]) for m in re.finditer(r"<b ([^>]*)><!\[CDATA\[(.*?)\]\]></b>", rg, re.S)]
    nm = re.search(r"<names ([^>]*)>(.*?)</names>", rg, re.S)
    return A(p.group(1)), p.group(2), hops, bodies, A(nm.group(1)), [x for x in nm.group(2).split(";") if x]
for label, task in (("trimmed", q), ("still-over", longq)):
    cap = cli(big, "--for=" + task); unc = cli(big, "--for=" + task, env={"RIPWIRE_HOW_UNCAPPED": "1"})
    pa, pt, hops, bodies, na, names = rows(cap)
    ua, ut, uhops, ubodies, una, unames = rows(unc)
    size, usize = len(cap.encode()), len(unc.encode())
    notes.append("%s %d B (uncapped %d B)" % (label, size, usize))
    seeds = int(pa["seeds"])
    if usize <= 8192: bad.append("%s: the uncapped answer is only %d B — the fixture no longer exercises the ceiling" % (label, usize))
    if ("over_ceiling" in pa) != (size > 8192): bad.append("%s: over_ceiling=%s at %d B" % (label, pa.get("over_ceiling"), size))
    if pt != ut or {k: v for k, v in pa.items() if not k.startswith("cut_") and k != "over_ceiling"} != ua: bad.append("%s: <path> moved" % label)
    cn = int(una["shown"]) - len(names)
    cc = sum(len(u[1]) - len(h[1]) for h, u in zip(hops, uhops))
    cl = sum(len(u[1]) - len(b[1]) for b, u in zip(bodies, ubodies))
    if (int(pa.get("cut_names", 0)), int(pa.get("cut_callees", 0)), int(pa.get("cut_lines", 0))) != (cn, cc, cl):
        bad.append("%s: cut_*= %s/%s/%s but the uncapped answer differs by %d/%d/%d" % (label, pa.get("cut_names", 0), pa.get("cut_callees", 0), pa.get("cut_lines", 0), cn, cc, cl))
    if label == "trimmed" and not (cn > 0 and cc > 0 and cl > 0 and size <= 8192): bad.append("trimmed: the fixture should cut names, callee rows AND lines and fit (%d/%d/%d, %d B)" % (cn, cc, cl, size))
    if label == "still-over" and not (size > 8192 and "over_ceiling" in pa): bad.append("still-over: want over_ceiling=1 past 8,192 B (%d B)" % size)
    deeper_left = sum(len(h[1]) for h in hops[seeds:])
    if (cc > 0 and len(names) > 0) or (cl > 0 and (len(names) > 0 or deeper_left > 0)):
        bad.append("%s: trim order (names, then deeper callee rows, then body lines) broken" % label)
    for i in range(seeds):
        if hops[i] != uhops[i]: bad.append("%s: seed row %s moved" % (label, hops[i][0].get("n")))
    # round trip: the cut rows are the uncapped answer's rows the capped one lacks, and each comes back from its next=
    if cn > 0:
        got = cli(big, *shlex.split(html.unescape(na["next"])))
        cands = set("%s %s:%s" % c for c in re.findall(r"<cand [^>]*?n=\"([^\"]*)\"[^>]*?p=\"([^\"]*)\"[^>]*?l=\"(\d+)\"", got))
        if names != unames[:len(names)] or not all(html.unescape(x) in cands for x in unames[len(names):int(una["shown"])]):
            bad.append("%s: a cut name is not in <names> next=" % label)
    for h, u in zip(hops, uhops):
        if h[1] != u[1][:len(h[1])]: bad.append("%s: hop %s shows rows the uncapped answer does not lead with" % (label, h[0]["n"]))
        cut = u[1][len(h[1]):]
        if cut:
            if h[0].get("capped") != "1": bad.append("%s: hop %s lost rows without capped=1" % (label, h[0]["n"])); continue
            got = {n for n, _ in SROWS(cli(big, *shlex.split(html.unescape(h[0]["next"]))))}
            if not all(html.unescape(x) in got for x in cut): bad.append("%s: hop %s next= misses a cut callee" % (label, h[0]["n"]))
    for b, u in zip(bodies, ubodies):
        if set(b[1]) - set(u[1]): bad.append("%s: body %s shows a line the uncapped body does not" % (label, b[0]["n"]))
        if len(b[1]) < len(u[1]) and not body_lines_returned(big, b[0]): bad.append("%s: body %s next= misses cut lines" % (label, b[0]["n"]))
print("BAD " + "; ".join(bad) if bad else "OK " + ", ".join(notes))
PY
grep -q '^OK' "$TMP/c.out" && ok "(C) the 8,192 B answer ceiling: $( sed 's/^OK //' "$TMP/c.out" ); names, then deeper callee rows, then lines; path and seeds intact; cut_*= agree with the uncapped answer; every cut row comes back from its next=; over_ceiling iff still over" \
                            || { no "(C) ceiling:"; cut -c1-900 "$TMP/c.out"; }

# ── (P) parity, (D) legend + counts, (F) follow-ups — fixture, src/, and the trimmed big answer ────────────────────────
python3 - "$TMP" "$TMP/big" <<'PY' >"$TMP/pdf.out" 2>&1
import os, sys
sys.path.insert(0, sys.argv[1]); from h import *
root = os.getcwd()
cases = [(os.path.join(root, "test/forhowfix"), "how does the router dispatch a request"), (os.path.join(root, "test/forhowfix"), "how is `call_handler` used"),
         (os.path.join(root, "src"), "how does the lens ranking pick its top rows"), (os.path.join(root, "src"), "what happens when a cached index is stale"),
         (sys.argv[2], "how does the pipeline run each stage")]
for path, q in cases:
    f, pt = cli(path, "--for=" + q), cli(path, "--pack-task=" + q)
    (mf, me), _ = mcp(path, [("for", {"task": q}), ("explore", {"task": q})])
    full = cli(path, "--for=" + q, "--legend=full")
    rs = {"cli-for": region(f), "cli-packtask": region(pt), "mcp-for": region(mf), "mcp-explore": region(me)}
    tag = os.path.basename(path)
    if None in rs.values() or len(set(rs.values())) != 1:
        print("P %s|%s: %s" % (tag, q, " ".join("%s=%s" % (k, "absent" if v is None else len(v)) for k, v in rs.items())))
    for lbl, d in (("cli-for", f), ("cli-packtask", pt), ("mcp-for", mf), ("mcp-explore", me), ("cli-for full", full)):
        u = undefined(d)
        if u: print("D %s|%s %s undefined: %s" % (tag, q, lbl, " ".join(u)))
        c = counts(d)
        if c: print("D %s|%s %s counts: %s" % (tag, q, lbl, "; ".join(c)))
    fb = follow(path, f)
    if fb: print("F %s|%s: %s" % (tag, q, "; ".join(fb)))
print("DONE")
PY
if ! grep -q '^DONE' "$TMP/pdf.out"; then no "(P/D/F) the probe did not finish:"; tail -5 "$TMP/pdf.out"; else
grep -q '^P ' "$TMP/pdf.out" && { no "(P) parity <path…</names> across CLI --for/--pack-task and MCP for/explore:"; grep '^P ' "$TMP/pdf.out" | head -6; } \
                             || ok "(P) <path…</names> byte-identical on CLI --for, CLI --pack-task, MCP for, MCP explore (fixture, src, a trimmed answer)"
grep -q '^D ' "$TMP/pdf.out" && { no "(D) legend/counts:"; grep '^D ' "$TMP/pdf.out" | head -8; } \
                             || ok "(D) every attribute defined name= in its own legend (compact, full, MCP); counts and body caps agree"
grep -q '^F ' "$TMP/pdf.out" && { no "(F) a next= did not return every row it cut:"; grep '^F ' "$TMP/pdf.out" | head -6; } \
                             || ok "(F) every next= (callees, callers, body lines, names) returns every row it cut, shown rows included"
fi

# ── (S) seeds ──────────────────────────────────────────────────────────────────────────────────────────────────────────
sbad=""
first_hop(){ "$BIN" "$FIX" --no-cache --for="$1" 2>/dev/null | grep -o '<h n="[^"]*" p="[^"]*"' | head -1 | sed 's/<h n="//;s/" p="/@/;s/"$//'; }
[ "$( first_hop "how does the router dispatch a request" )" = "dispatch@router.py:11" ] || sbad="$sbad [conceptual: $( first_hop "how does the router dispatch a request" )]"
[ "$( first_hop 'how is `call_handler` used' )" = "call_handler@handlers.py:5" ] || sbad="$sbad [backticked: $( first_hop 'how is `call_handler` used' )]"
for qq in 'Router.add_route' 'Router::add_route' 'Router#add_route' 'Router->add_route' '`Router.add_route`'; do
    [ "$( first_hop "how does $qq store a handler" )" = "add_route@router.py:8" ] || sbad="$sbad [qualified $qq: $( first_hop "how does $qq store a handler" )]"
done
[ "$( first_hop 'how does AdminRouter.add_route store a handler' )" = "add_route@admin.py:5" ] || sbad="$sbad [qualified AdminRouter: $( first_hop 'how does AdminRouter.add_route store a handler' )]"
[ "$( first_hop 'how does app.dispatch route a request' )" = "dispatch@router.py:11" ] || sbad="$sbad [unmatched qualifier: $( first_hop 'how does app.dispatch route a request' )]"
"$BIN" "$FIX" --no-cache --for="how does the router dispatch a request" 2>/dev/null | grep -q '<path seeds="[1-3]"' || sbad="$sbad [<path seeds=> missing]"
"$BIN" "$FIX" --no-cache --for="how does zzqx frobnicate" 2>/dev/null | grep -q '<path seeds="0"' || sbad="$sbad [no seed: want <path seeds=\"0\">]"
[ -z "$sbad" ] && ok "(S) identifier, qualified identifier (. :: # ->, two same-named defs), unmatched qualifier and term-named seeds come first; no match is seeds=\"0\"" || no "(S) seeds:$sbad"

# ── (R) the ref posture — the dictionary leg of Gate D, on for and on explore ──────────────────────────────────────────
python3 - "$TMP" "$FIX" <<'PY' >"$TMP/r.out" 2>&1
import sys; sys.path.insert(0, sys.argv[1]); from h import *
fix = sys.argv[2]
CLAUSES = ["shape=how: a call path answer", "path seeds= hops=:", "h n= p=file:line:", "b n= p= lines_shown=", "names shown= total= past= next=:"]
bad = []
for tool in ("for", "explore"):
    (a, b), dic = mcp(fix, [(tool, {"task": "how does the router dispatch a request"}), (tool, {"task": "how is a request validated"})], ref=True)
    if not dic: bad.append("%s: the session read no dictionary text" % tool)
    if not all(c in a for c in CLAUSES): bad.append("%s: the first answer lacks a how clause" % tool)
    if any(c in b for c in CLAUSES): bad.append("%s: the second answer repeats a how clause the session was already sent" % tool)
    if 'legend="ref"' not in b or not b.rstrip().endswith("</ctx>"): bad.append("%s: the second answer is not in the ref posture" % tool)
    comments = "".join(re.findall(r"<!--.*?-->", b, re.S))
    about = re.search(r"<about [^>]*/>", b)
    u = undefined(b, comments + dic + a + (about.group(0) if about else ""))   # a definition the session was already sent counts
    if u: bad.append("%s: second answer attributes defined nowhere the session saw: %s" % (tool, " ".join(u)))
print("BAD " + "; ".join(bad) if bad else "OK")
PY
grep -q '^OK' "$TMP/r.out" && ok "(R) under legend=ref (for, explore) the how clauses are sent once per session and every attribute of the second answer is defined in its comments or the dictionary the session read" \
                            || { no "(R) ref posture:"; cut -c1-600 "$TMP/r.out"; }

# ── (U) F2-uncapped equals the answer under the ceiling ─────────────────────────────────────────────────────────────────
ubad=""
for q in "$Q" "how is \`call_handler\` used"; do
    "$BIN" "$FIX" --no-cache --for="$q" >"$TMP/u1" 2>/dev/null; RIPWIRE_HOW_UNCAPPED=1 "$BIN" "$FIX" --no-cache --for="$q" >"$TMP/u2" 2>/dev/null
    [ "$( wc -c <"$TMP/u1" )" -le 8192 ] && { cmp -s "$TMP/u1" "$TMP/u2" || ubad="$ubad [$q]"; }
done
"$BIN" src --no-cache --for="how does the lens ranking pick its top rows" >"$TMP/u1" 2>/dev/null
RIPWIRE_HOW_UNCAPPED=1 "$BIN" src --no-cache --for="how does the lens ranking pick its top rows" >"$TMP/u2" 2>/dev/null
[ "$( wc -c <"$TMP/u1" )" -le 8192 ] && { cmp -s "$TMP/u1" "$TMP/u2" || ubad="$ubad [src lens]"; }
[ -z "$ubad" ] && ok "(U) RIPWIRE_HOW_UNCAPPED=1 is byte-identical to the answer whenever the answer is under 8,192 B" || no "(U) uncapped arm differs under the ceiling:$ubad"

# ── (X) well-formed + deterministic ─────────────────────────────────────────────────────────────────────────────────────
"$BIN" "$FIX" --no-cache --for="$Q" >"$TMP/x1" 2>/dev/null; "$BIN" "$FIX" --no-cache --for="$Q" >"$TMP/x2" 2>/dev/null
"$BIN" src --no-cache --pack-task="how does the lens ranking pick its top rows" >"$TMP/x3" 2>/dev/null
"$BIN" "$TMP/big" --no-cache --for="how does the pipeline run each stage" >"$TMP/x4" 2>/dev/null
if grep -q 'shape="how"' "$TMP/x1" && cmp -s "$TMP/x1" "$TMP/x2" \
   && { ! command -v xmllint >/dev/null 2>&1 || { xmllint --noout "$TMP/x1" && xmllint --noout "$TMP/x3" && xmllint --noout "$TMP/x4"; }; }; then
    ok "(X) the how answer is well-formed XML and byte-identical across runs"
else
    no "(X) well-formedness / determinism"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

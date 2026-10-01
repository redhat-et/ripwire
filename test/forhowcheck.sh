#!/usr/bin/env bash
# forhowcheck.sh — the how-it-works answer (fix #10): on a task the frozen trigger fires on, with default arguments and one
# root, `--for`, `--pack-task`, MCP `for` and MCP `explore` serve the shape="how" sections (<path>, <h> hops, <b> selected
# body lines, <names>) — byte-identical across the four surfaces — and every other input keeps the pre-change answer.
#
# WRITTEN BEFORE THE CODE IT MEASURES (CLAUDE.md non-negotiable #1). Arms:
#   (T) the TEXT trigger: each registered prefix fires, case- and leading-quote/space-insensitively; the four excluded
#       openers and a non-prefix question do not.
#   (A) DEFAULT ARGUMENTS ONLY: any shaping flag, a second root, --json, --format=candidates, --limit, a budget or
#       --no-route keeps the pre-change shape (no shape="how"); --legend=full and --no-cache keep the trigger.
#   (P) PARITY (prereg Gate P): the bytes from `<path` to `</names>` are identical on CLI --for, CLI --pack-task, MCP for
#       and MCP explore — on the fixture and on this repo's src/.
#   (D) LEGEND + COUNTS (prereg Gate D): every attribute of every element is defined `name=` in the answer's leading
#       comments (compact, full, MCP); shown <= total and capped="1" iff shown < total; lines_shown <= sel <= lines_total
#       and the CDATA holds exactly lines_shown numbered lines; each body <= 1,024 B of lines and <= 2,048 B in all.
#   (F) FOLLOW-UPS (prereg Gate D): each next= returns every row it cut — a hop's --callees=, a seed's --callers=, a
#       body's --expand=, <names>' candidates export (every window row).
#   (S) SEEDS: a backticked identifier is the first seed; a qualified one picks the definition its qualifier names; a
#       conceptual question's first seed is the definition whose NAME carries the question's terms.
#   (R) REF POSTURE: in a session that read the legend dictionary, a second triggered `for` answer no longer carries the
#       F2 clauses the first one served, and ends with <about legend="ref">.
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
export TMPDIR="$TMP/" XDG_CACHE_HOME="$TMP/xdg"
FIX="test/forhowfix"
Q="how does the router dispatch a request"

is_how(){ grep -q '<ctx [^>]*shape="how"' "$1"; }

# ── (T) the text trigger ────────────────────────────────────────────────────────────────────────────────────────
tbad=""
for q in "how does the router dispatch a request" "How do routes match a path" "how is a request validated" "how are responses rendered" \
         "how can a handler raise" "explain how the router dispatches" "walk me through dispatching a request" \
         "what happens when a route is missing" '  "How does the router dispatch' "'how is a response encoded'"; do
    "$BIN" "$FIX" --no-cache --for="$q" >"$TMP/t.xml" 2>/dev/null
    is_how "$TMP/t.xml" || tbad="$tbad [fires? $q]"
done
for q in "how many routes are there" "how much does dispatch cost" "how often is a route matched" "how long does dispatch take" \
         "where does the router dispatch a request" "router dispatch: how does it work" "howdoes the router dispatch"; do
    "$BIN" "$FIX" --no-cache --for="$q" >"$TMP/t.xml" 2>/dev/null
    is_how "$TMP/t.xml" && tbad="$tbad [must not fire: $q]"
done
[ -z "$tbad" ] && ok "(T) the 8 prefixes fire (case, leading quotes and spaces trimmed); excluded openers and non-prefix questions do not" \
               || no "(T) trigger:$tbad"

# ── (A) default arguments only ──────────────────────────────────────────────────────────────────────────────────
abad=""
for extra in "--token-budget=3000" "--format=candidates" "--json" "--signatures-only" "--limit=5" "--no-route" "--detail=2" \
             "--sections=lego,compose" "--adaptive" "--auto-bodies"; do
    "$BIN" "$FIX" --no-cache --for="$Q" $extra >"$TMP/a.xml" 2>/dev/null
    is_how "$TMP/a.xml" && abad="$abad [$extra fired]"
done
"$BIN" "$FIX" test/archfix --no-cache --for="$Q" >"$TMP/a.xml" 2>/dev/null; is_how "$TMP/a.xml" && abad="$abad [two roots fired]"
"$BIN" "$FIX" --no-cache --pack-task="$Q" --token-budget=3000 >"$TMP/a.xml" 2>/dev/null; is_how "$TMP/a.xml" && abad="$abad [pack-task budget fired]"
for extra in "--legend=full" "--legend=compact" "--cache=$TMP/c.bin"; do
    "$BIN" "$FIX" --for="$Q" $extra >"$TMP/a.xml" 2>/dev/null
    is_how "$TMP/a.xml" || abad="$abad [$extra did not fire]"
done
[ -z "$abad" ] && ok "(A) any non-default argument or a second root keeps the pre-change answer; --legend/--cache keep the trigger" \
               || no "(A) default-arguments rule:$abad"

# ── shared python helpers ───────────────────────────────────────────────────────────────────────────────────────
cat >"$TMP/h.py" <<'PY'
import html, json, os, re, shlex, subprocess, sys
BIN = os.environ["BIN"]
def mcp(path, calls, ref=False):
    msgs = [{"jsonrpc": "2.0", "id": 1, "method": "initialize"}]
    if ref:
        msgs.append({"jsonrpc": "2.0", "id": 9, "method": "resources/read", "params": {"uri": "ripwire://legend-dict"}})
    for i, (tool, args) in enumerate(calls):
        a = dict(path=path); a.update(args)
        msgs.append({"jsonrpc": "2.0", "id": 100 + i, "method": "tools/call", "params": {"name": tool, "arguments": a}})
    p = subprocess.run([BIN, "--mcp"], input="".join(json.dumps(m) + "\n" for m in msgs).encode(), capture_output=True, timeout=600)
    res = {}
    for line in p.stdout.decode("utf-8", "replace").splitlines():
        try: j = json.loads(line)
        except ValueError: continue
        if isinstance(j.get("id"), int) and j["id"] >= 100:
            r = j.get("result")
            res[j["id"]] = r["content"][0]["text"] if r else "ERROR " + json.dumps(j.get("error"))
    return [res.get(100 + i, "") for i in range(len(calls))]
def cli(path, *args):
    return subprocess.run([BIN, path, "--no-cache", *args], capture_output=True).stdout.decode("utf-8", "replace")
REGION = re.compile(r"<path[ >/].*?</names>", re.S)
def region(doc):
    m = REGION.search(doc); return m.group(0) if m else None
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
def undefined(doc):
    lg = lead(doc)
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
def follow(path, doc):
    bad = []
    doc = region(doc)
    if doc is None: return ["no <path…</names> region (vacuous)"]
    rows = lambda got: set(re.findall(r"<s [^>]*?n=\"([^\"]*)\" p=\"([^\"]*)\"", got))
    for m in re.finditer(r"<h ([^>]*)>", doc):
        a = A(m.group(1))
        if a.get("capped") == "1":
            got = cli(path, *shlex.split(html.unescape(a["next"])))   # one page: next= carries --limit= when the list is long
            if len(rows(got)) < int(a["total"]) or 'has_more="1"' in got: bad.append("hop %s %s" % (a.get("n"), a["next"]))
    for m in re.finditer(r"<us ([^>]*)>", doc):
        a = A(m.group(1))
        if a.get("capped") == "1":
            got = cli(path, *shlex.split(html.unescape(a["next"])))
            if len(rows(got)) < int(a["total"]) or 'has_more="1"' in got: bad.append("callers %s" % a["next"])
    for m in re.finditer(r"<b ([^>]*)>", doc):
        a = A(m.group(1))
        f, line = a["p"].rsplit(":", 1)
        # --expand=FILE:NAME serves every same-named definition in the file; ours is the one at p=. A long body comes back
        # in pages, each truncated row naming the next range: follow that chain, it is the deterministic continuation.
        nxt, lines = html.unescape(a["next"]), 0
        while nxt:
            got = cli(path, "--top-k=0", *shlex.split(nxt))
            nxt = None
            for bm in re.finditer(r"<b ([^>]*)><!\[CDATA\[(.*?)\]\]>", got, re.S):
                ba = A(bm.group(1))
                if ba.get("p") == f and ba.get("l") == line:
                    lines += len(bm.group(2).rstrip("\n").split("\n"))
                    nxt = html.unescape(ba["next"]) if ba.get("truncated") == "1" else None
            if "<src " in got and lines == 0:
                lines = int(a["lines_total"])   # the whole file was served (expand's whole-file mode): the body is in it
        if lines < int(a["lines_total"]): bad.append("body %s: %d of %s lines" % (a["next"], lines, a["lines_total"]))
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
export BIN

# ── (P) parity, (D) legend + counts, (F) follow-ups — on the fixture and on src/ ─────────────────────────────────────
python3 - "$TMP" <<'PY' >"$TMP/pdf.out" 2>&1
import os, sys
sys.path.insert(0, sys.argv[1]); from h import *
root = os.getcwd()
cases = [("test/forhowfix", "how does the router dispatch a request"), ("test/forhowfix", "how is `call_handler` used"),
         ("src", "how does the lens ranking pick its top rows"), ("src", "what happens when a cached index is stale")]
for path, q in cases:
    ap = os.path.join(root, path)
    f, pt = cli(path, "--for=" + q), cli(path, "--pack-task=" + q)
    mf, me = mcp(ap, [("for", {"task": q}), ("explore", {"task": q})])
    full = cli(path, "--for=" + q, "--legend=full")
    rs = {"cli-for": region(f), "cli-packtask": region(pt), "mcp-for": region(mf), "mcp-explore": region(me)}
    if None in rs.values() or len(set(rs.values())) != 1:
        print("P %s|%s: %s" % (path, q, " ".join("%s=%s" % (k, "absent" if v is None else len(v)) for k, v in rs.items())))
    for lbl, d in (("cli-for", f), ("cli-packtask", pt), ("mcp-for", mf), ("mcp-explore", me), ("cli-for full", full)):
        u = undefined(d)
        if u: print("D %s|%s %s undefined: %s" % (path, q, lbl, " ".join(u)))
        c = counts(d)
        if c: print("D %s|%s %s counts: %s" % (path, q, lbl, "; ".join(c)))
    fb = follow(path, f)
    if fb: print("F %s|%s: %s" % (path, q, "; ".join(fb)))
print("DONE")
PY
if ! grep -q '^DONE' "$TMP/pdf.out"; then no "(P/D/F) the probe did not finish:"; tail -5 "$TMP/pdf.out"; else
grep -q '^P ' "$TMP/pdf.out" && { no "(P) parity <path…</names> across CLI --for/--pack-task and MCP for/explore:"; grep '^P ' "$TMP/pdf.out" | head -6; } \
                             || ok "(P) <path…</names> byte-identical on CLI --for, CLI --pack-task, MCP for, MCP explore (fixture + src)"
grep -q '^D ' "$TMP/pdf.out" && { no "(D) legend/counts:"; grep '^D ' "$TMP/pdf.out" | head -8; } \
                             || ok "(D) every attribute defined name= in its own legend (compact, full, MCP); counts and body caps agree"
grep -q '^F ' "$TMP/pdf.out" && { no "(F) a next= did not return every row it cut:"; grep '^F ' "$TMP/pdf.out" | head -6; } \
                             || ok "(F) every next= (callees, callers, body, names) returns every row it cut"
fi

# ── (S) seeds ──────────────────────────────────────────────────────────────────────────────────────────────────────
sbad=""
first_hop(){ "$BIN" "$FIX" --no-cache --for="$1" 2>/dev/null | grep -o '<h n="[^"]*"' | head -1 | sed 's/<h n="//;s/"$//'; }
[ "$( first_hop "how does the router dispatch a request" )" = "dispatch" ] || sbad="$sbad [conceptual: first seed $( first_hop "how does the router dispatch a request" ), want dispatch]"
[ "$( first_hop 'how is `call_handler` used' )" = "call_handler" ] || sbad="$sbad [backticked: $( first_hop 'how is `call_handler` used' )]"
[ "$( first_hop 'how does Router.add_route store a handler' )" = "add_route" ] || sbad="$sbad [qualified: $( first_hop 'how does Router.add_route store a handler' )]"
"$BIN" "$FIX" --no-cache --for="how does the router dispatch a request" 2>/dev/null | grep -q '<path seeds="[1-3]"' || sbad="$sbad [<path seeds=> missing]"
"$BIN" "$FIX" --no-cache --for="how does zzqx frobnicate" 2>/dev/null | grep -q '<path seeds="0"' || sbad="$sbad [no seed: want <path seeds=\"0\">]"
[ -z "$sbad" ] && ok "(S) identifier, qualified identifier and term-named seeds come first; no match is seeds=\"0\"" || no "(S) seeds:$sbad"

# ── (R) the ref posture ─────────────────────────────────────────────────────────────────────────────────────────────
python3 - "$TMP" <<'PY' >"$TMP/r.out" 2>&1
import os, sys
sys.path.insert(0, sys.argv[1]); from h import *
ap = os.path.join(os.getcwd(), "test/forhowfix")
a, b = mcp(ap, [("for", {"task": "how does the router dispatch a request"}), ("for", {"task": "how is a request validated"})], ref=True)
la, lb = lead(a) + a[a.rfind("<!--"):], lead(b) + b[b.rfind("<!--"):]
print("first-has-hop-clause", "<h n= p=" in a or "h n= p=" in a)
print("second-ends-about", b.rstrip().endswith("</ctx>") and '<about ' in b and 'legend="ref"' in b)
print("second-repeats", "h n= p=" in b)
PY
grep -q 'first-has-hop-clause True' "$TMP/r.out" && grep -q 'second-ends-about True' "$TMP/r.out" && grep -q 'second-repeats False' "$TMP/r.out" \
    && ok "(R) under legend=ref the F2 clauses are sent once per session; the second answer ends with <about legend=\"ref\">" \
    || { no "(R) ref posture:"; cat "$TMP/r.out" | head -5; }

# ── (X) well-formed + deterministic ─────────────────────────────────────────────────────────────────────────────────
"$BIN" "$FIX" --no-cache --for="$Q" >"$TMP/x1" 2>/dev/null; "$BIN" "$FIX" --no-cache --for="$Q" >"$TMP/x2" 2>/dev/null
"$BIN" src --no-cache --pack-task="how does the lens ranking pick its top rows" >"$TMP/x3" 2>/dev/null
if is_how "$TMP/x1" && cmp -s "$TMP/x1" "$TMP/x2" && { ! command -v xmllint >/dev/null 2>&1 || { xmllint --noout "$TMP/x1" && xmllint --noout "$TMP/x3"; }; }; then
    ok "(X) the how answer is well-formed XML and byte-identical across runs"
else
    no "(X) well-formedness / determinism"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

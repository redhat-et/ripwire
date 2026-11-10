#!/usr/bin/env bash
# fortailwidecheck.sh — FOR-TAIL-WIDE: the --for <tail> walks 4 pages of the file page, not 1.
#
# WHY. A broad --for answer cuts its file tail at the rank rows plus page 0 of `--for=TASK --limit=40`; on the R-ladder
# rows 6 of 7 items the raised page (`--limit=100000`) recovered sat at file-page rank 57-177, past that cut. The tail now
# keeps its rank rows (the files of trimmed head rows first, unchanged) and then lists the file page's first 160 rows
# (kForFileTailPageWalk) not listed above, in the page's own order: one ranking for the page part, the one the raised page
# prints. sym= rides the rank rows and page rows 1-40 (the old cut); a page row past it is path-only, so the extra rows cost
# a third to a half of a full row. The cut stays disclosed: total= every positive-score file, shown=, capped=1, next= the page
# from the first row not walked.
#
# Arms (each reads the exit code of the command it parses; an empty or crashed answer fails every arm):
#   1  widened:  the page part is exactly page[0:160] minus the rank rows, in page order (red before: page[0:40])
#   2  counts:   shown = rows printed, capped=1, total = the page's total, next= continues at --offset=160
#   3  sym:      no page row at page index >= 40 carries sym=  (absence)  /  every rank row and page row < 40 carries the
#                page row's own sym=  (positive twin)
#   4  no cut:   a fixture with fewer files than one page: capped=0, no next=, every row with sym=, and the tail element is
#                byte-identical to the one rebuilt from the page (rank rows + page rows, all with sym=); with arm 7's absence,
#                such an answer is byte-identical to the 40-row walk's
#   5  JSON:     "tail".files is the XML rows in order; "sym" is "" exactly where the XML row has no sym=
#   6  budget:   under --token-budget the tail is a prefix of the default tail and still carries capped=1 and next=
#   7  legend:   the walk clause (kForFileTailWideLegend / its compact twin) rides the wide answer and not the one whose page
#                fits page 0, in both dialects
#   8  code first: code and markdown files interleaved, a code question: the old walk's rows come first (code, then its doc
#                rows), then the widened rows; sym= sheds past the old walk's cut, which counts CODE rows (a code row within
#                the first 40 code rows keeps sym= even past page index 40, the positive twin), and doc rows keep sym= within
#                page index 40 only
#   Fix round 1 (review rv-ftw F1-F4):
#   9  budget order (F2): under --token-budget a p=-only row is shown only once every sym= row of the default tail is shown
#                (fixture D at 3000 / 4000: the old walk's doc rows were cut while widened code rows rode)
#   10 sigs funding (F1): two fixtures that differ only in the length of the directory holding the files past page 0 (so the
#                widened rows' bytes differ, the ranking and the head do not): under --token-budget, where the head is cut
#                (past the target), <sigs> is byte-identical across the two, XML and JSON (positive twin: the tails differ)
#   11 head files (F4): no widened row names a file the head shows (positive twin: the page holds such a file past page 0)
#   13 MCP twin (F8): the `for` verb with budget_tokens serves the old walk's tail (every row with sym=, no p_only=, no walk
#                clause); without a budget it serves the widened tail (p_only= and the clause, the positive twin)
#   12 p_only (F3): p_only= / "p_only" = the shown rows without sym= past the old prefix, with "p_only_why" in JSON; absent
#                when no such row is shown
#
# Usage: test/fortailwidecheck.sh [BIN]   (default build/ripwire; RIPWIRE_BIN also honoured)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "fortailwidecheck: BIN=$BIN"

# fixture W: 300 files in three classes, so the file page's union-share order and the best-symbol order differ
W="$TMP/wide"; mkdir -p "$W"
i=0
while [ $i -lt 300 ]; do
    n=$( printf '%03d' $i )
    case $(( i % 3 )) in
        0) printf 'def widget_frobnicate_%s():\n    """widget frobnicate helper"""\n    return 1\n' "$n" > "$W/m$n.py" ;;
        1) printf 'def widget_%s():\n    """widget only"""\n    return 2\n\ndef helper_%s():\n    return 3\n' "$n" "$n" > "$W/m$n.py" ;;
        2) printf 'def frobnicate_%s():\n    """frobnicate"""\n    return 4\n' "$n" > "$W/m$n.py" ;;
    esac
    i=$(( i + 1 ))
done
# fixture S: 12 files, fewer than one page: the tail is whole
S="$TMP/small"; mkdir -p "$S"
for n in 01 02 03 04 05 06 07 08 09 10 11 12; do
    printf 'def widget_frobnicate_%s():\n    """widget frobnicate helper"""\n    return 1\n' "$n" > "$S/s$n.py"
done
# fixture D: code and markdown files interleaved in the page, a code question: the code-first walk (docs after code)
DD="$TMP/docs"; mkdir -p "$DD"
FILL="$( k=1; while [ $k -le 120 ]; do printf '    zzq_%s = %s\n' $k $k; k=$(( k + 1 )); done )"
i=0
while [ $i -lt 150 ]; do   # 10 code files cover the query tightly, 50 cover it with a long body (they rank under the docs), the rest
    n=$( printf '%03d' $i )   # cover two of its three words; 75 markdown pages cover it
    if [ $i -lt 10 ]; then
        printf 'def widget_frobnicate_%s():\n    """widget frobnicate helper"""\n    return 1\n' "$n" > "$DD/c$n.py"
    elif [ $i -lt 60 ]; then
        { printf 'def widget_frobnicate_%s():\n    """widget frobnicate helper"""\n' "$n"; printf '%s\n' "$FILL"; printf '    return 1\n'; } > "$DD/c$n.py"
    else
        printf 'def widget_frobnicate_%s():\n    return 1\n' "$n" > "$DD/c$n.py"
    fi
    [ $(( i % 2 )) -eq 0 ] && printf '# Widget frobnicate helper %s\n\nThe widget frobnicate helper %s notes.\n' "$n" "$n" > "$DD/a$n.md"
    i=$(( i + 1 ))
done
Q="widget frobnicate helper"
# fixtures P1 / P2 (arm 10): 80 files with long signatures (the head is cut under a budget) and 120 files matching one word under
# a directory whose name is 1 or 40 characters long: the widened rows' bytes differ, the ranking and the head's bytes do not
mkP() {
    local d="$1" w="$2" i n
    local A="alpha_parameter_one, beta_parameter_two, gamma_parameter_three, delta_parameter_four, epsilon_parameter_five, zeta_parameter_six"
    mkdir -p "$d/$w"; i=0
    while [ $i -lt 80 ]; do n=$( printf '%03d' $i )
        printf 'def widget_frobnicate_helper_%s(%s):\n    """widget frobnicate helper"""\n    return 1\n' "$n" "$A" > "$d/s$n.py"; i=$(( i + 1 )); done
    i=0
    while [ $i -lt 120 ]; do n=$( printf '%03d' $i )
        printf 'def helper_%s():\n    return 3\n' "$n" > "$d/$w/h$n.py"; i=$(( i + 1 )); done
}
P1="$TMP/p1"; P2="$TMP/p2"
mkP "$P1" w
mkP "$P2" wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww

run() {   # run DIR OUTFILE ARGS... -> rc file beside the output; HOME/TMPDIR private, cwd = the fixture
    local d="$1" o="$2"; shift 2
    ( cd "$d" || exit 9; HOME="$TMP/home" TMPDIR="$TMP/" "$BIN" "$d" --no-cache "$@" ) > "$o" 2> "$o.err"
    echo $? > "$o.rc"
}
mkdir -p "$TMP/home"
run "$W" "$TMP/w.xml"   "--for=$Q"
run "$W" "$TMP/w.page"  "--for=$Q" --limit=100000
run "$W" "$TMP/w.json"  "--for=$Q" --json
run "$W" "$TMP/w.bud"   "--for=$Q" --token-budget=3000
run "$S" "$TMP/s.xml"   "--for=$Q"
run "$S" "$TMP/s.page"  "--for=$Q" --limit=100000
run "$W" "$TMP/w.full"  "--for=$Q" --legend=full
run "$S" "$TMP/s.full"  "--for=$Q" --legend=full
# fixture D measures the code-first WALK (arms 8, 9): run with SIZE-2's fold off, which counts the widened doc rows instead of
# listing them (test/fortailfoldcheck.sh is that fold's gate)
( export RIPWIRE_NO_TAIL_FOLD=1
run "$DD" "$TMP/d.xml"  "--for=$Q"
run "$DD" "$TMP/d.page" "--for=$Q" --limit=100000
run "$DD" "$TMP/d.json" "--for=$Q" --json
run "$DD" "$TMP/d.b3000" "--for=$Q" --token-budget=3000
run "$DD" "$TMP/d.b4000" "--for=$Q" --token-budget=4000 )
for tb in 5000 6000 8000; do
    run "$P1" "$TMP/p1.$tb" "--for=$Q" --token-budget=$tb
    run "$P2" "$TMP/p2.$tb" "--for=$Q" --token-budget=$tb
done
mcpfor() {   # mcpfor OUTFILE [BUDGET]: the MCP `for` verb on fixture W -> the JSON-RPC reply, rc beside it
    local o="$1" args
    args="$( printf '"path":"%s","task":"%s"' "$W" "$Q" )"; [ -n "${2:-}" ] && args="$args,\"budget_tokens\":$2"
    ( cd "$W" || exit 9; printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{%s}}}\n' "$args" \
        | HOME="$TMP/home" TMPDIR="$TMP/" "$BIN" --mcp ) > "$o" 2> "$o.err"
    echo $? > "$o.rc"
}
mcpfor "$TMP/m.def"
mcpfor "$TMP/m.bud" 3000
run "$P1" "$TMP/p1.j6000" "--for=$Q" --token-budget=6000 --json
run "$P2" "$TMP/p2.j6000" "--for=$Q" --token-budget=6000 --json

python3 - "$TMP" <<'PY'
import html, json, re, sys
T = sys.argv[1]; fails = 0
def say(ok, msg):
    global fails
    print(("  PASS  " if ok else "  FAIL  ") + msg); fails += 0 if ok else 1
def load(name):
    rc = open(f"{T}/{name}.rc").read().strip(); txt = open(f"{T}/{name}", encoding="utf8", errors="replace").read()
    return rc, txt
def tail_of(txt):
    m = re.search(r'<tail total="(\d+)" shown="(\d+)" capped="(\d)"( next="[^"]*")?(?: p_only="(\d+)")?>(.*?)</tail>', txt, re.S)
    if not m: return None
    rows = [(html.unescape(p), None if not s else html.unescape(s)) for p, s in re.findall(r'<t p="([^"]*)"(?: sym="([^"]*)")?/>', m.group(6))]
    return dict(total=int(m.group(1)), shown=int(m.group(2)), capped=m.group(3), next=html.unescape(m.group(4) or ""), rows=rows, raw=m.group(0),
                p_only=None if m.group(5) is None else int(m.group(5)))
def head_files(txt):
    m = re.search(r'<sigs[ >].*?</sigs>', txt, re.S)
    return set() if not m else {html.unescape(p) for p in re.findall(r'<d [^>]*?\bp="([^"]*)"', m.group(0))}
def page_of(txt):
    return [(html.unescape(p), html.unescape(s) if s is not None else "") for p, s in re.findall(r'<f p="([^"]*)"[^>]*?(?: sym="([^"]*)")?/>', txt)]
def split(rows, page, walk, head=frozenset()):
    """R = the shortest prefix (<= 24 rows) for which the rest is exactly page[0:walk] minus R, in page order — past the old
    cut (page index 40) minus the head's files too (F4)."""
    for k in range(0, min(24, len(rows)) + 1):
        R = {p for p, _ in rows[:k]}
        if [p for p, _ in rows[k:]] == [p for j, (p, _) in enumerate(page[:walk]) if p not in R and (j < 40 or p not in head)]:
            return k
    return None
rcs = {n: load(n) for n in ("w.xml", "w.page", "w.json", "w.bud", "s.xml", "s.page", "d.xml", "d.page", "w.full", "s.full", "d.json", "d.b3000", "d.b4000",
                            "p1.5000", "p2.5000", "p1.6000", "p2.6000", "p1.8000", "p2.8000", "p1.j6000", "p2.j6000")}
for n, (rc, txt) in rcs.items():
    say(rc == "0" and len(txt) > 200, f"{n}: exit 0 and a non-empty answer (rc={rc}, {len(txt)} B)")
wt, page = tail_of(rcs["w.xml"][1]), page_of(rcs["w.page"][1])
say(wt is not None and len(page) >= 200, f"wide fixture: a <tail> and a raised page of >= 200 rows ({len(page)})")
if wt is None or len(page) < 200:
    print("fortailwidecheck: FAIL (no tail or short page)"); sys.exit(1)
pidx = {p: k for k, (p, _) in enumerate(page)}; psym = dict(page)
whead = head_files(rcs["w.xml"][1])
k = split(wt["rows"], page, 160, whead)
say(k is not None, f"1 widened: the page part is page[0:160] minus the rank rows (and, past index 40, the head's files), in page order (rank rows={k}; old walk 40 split={split(wt['rows'], page, 40)})")
kv = k is not None
if k is None: k = 0
pagepart = wt["rows"][k:]
say(kv and any(pidx.get(p, -1) >= 40 for p, _ in pagepart), "1 widened: rows past page index 40 are listed")
say(wt["shown"] == len(wt["rows"]) and wt["capped"] == "1" and wt["total"] == len(page), f"2 counts: shown={wt['shown']} rows={len(wt['rows'])} capped={wt['capped']} total={wt['total']} page={len(page)}")
wh_past = [p for j, (p, _) in enumerate(page[40:160]) if p in whead]
say(len(whead) > 0 and not any(p in whead for p, _ in pagepart if pidx[p] >= 40), f"11 head files: no widened row names one of the head's {len(whead)} files")
# (twin) the small fixtures rank the head's files inside page 0 (the head and the page order agree here), so the skip itself is
# pinned on the in-sample calls (fix round 1: 1183 widened rows named a head file before, 0 after); the twin here proves the
# arm reads a non-empty head and a non-empty widened part, so it cannot pass on an empty answer.
say(len(whead) > 0 and any(pidx[p] >= 40 for p, _ in pagepart), f"11 head files (twin): {len(whead)} head files and {len(wh_past)} of them at page index 40-159; widened rows present")
say("--offset=160" in wt["next"] and "--limit=40" in wt["next"], f"2 counts: next= continues the page at offset 160 ({wt['next'][-40:]!r})")
past = [(p, s) for p, s in pagepart if pidx[p] >= 40]; within = [(p, s) for p, s in pagepart if pidx[p] < 40]
say(kv and len(past) > 0 and all(s is None for _, s in past), f"3 sym absence: {len(past)} page rows past index 40, none with sym=")
say(kv and len(within) > 0 and all(s == psym[p] and s for p, s in within), f"3 sym twin: {len(within)} page rows within index 40 carry the page row's sym=")
say(k > 0 and all(s == psym[p] and s for p, s in wt["rows"][:k]), f"3 sym twin: {k} rank rows carry the page row's sym=")
st, spage = tail_of(rcs["s.xml"][1]), page_of(rcs["s.page"][1])
ok4 = st is not None and st["capped"] == "0" and not st["next"] and st["shown"] == st["total"] == len(spage) and all(s for _, s in st["rows"]) and st["p_only"] is None
say(ok4, "4 no cut: capped=0, no next=, shown=total=page rows, every row with sym=")
if st is not None:
    ks = split(st["rows"], spage, 160)
    rebuilt = f'<tail total="{len(spage)}" shown="{len(st["rows"])}" capped="0">' + "".join(
        f'<t p="{html.escape(p, quote=True)}" sym="{html.escape(psym_s, quote=True)}"/>' for p, psym_s in
        [(p, dict(spage)[p]) for p, _ in st["rows"]]) + "</tail>"
    say(ks is not None and st["raw"].replace("&apos;", "'").replace("&#x27;", "'") == rebuilt.replace("&#x27;", "'"), "4 no cut: the tail element is byte-identical to the one rebuilt from the page")
try:
    j = json.loads(rcs["w.json"][1]); jt = j.get("tail") or {}
except Exception as e:
    jt = {}; print("  json parse error:", e)
say(jt.get("files") == [p for p, _ in wt["rows"]], f"5 JSON: tail.files is the XML rows in order ({len(jt.get('files') or [])} vs {len(wt['rows'])})")
say(jt.get("sym") == [s or "" for _, s in wt["rows"]] and "" in (jt.get("sym") or []), "5 JSON: sym is \"\" exactly where the XML row has no sym=")
nosym = sum(1 for _, s in wt["rows"] if s is None)
say(wt["p_only"] == nosym > 0 and all(s is None for _, s in wt["rows"][len(wt["rows"]) - nosym:]), f"12 p_only: XML p_only={wt['p_only']} = the {nosym} trailing rows without sym=")
say(jt.get("p_only") == nosym and bool(jt.get("p_only_why")) and jt.get("sym", []).count("") == nosym, f"12 p_only: JSON p_only={jt.get('p_only')} with p_only_why, = its \"\" sym entries")
bt = tail_of(rcs["w.bud"][1])
say(bt is not None and 0 < len(bt["rows"]) < len(wt["rows"]) and [p for p, _ in bt["rows"]] == [p for p, _ in wt["rows"][:len(bt["rows"])]] and bt["capped"] == "1" and "--limit=40" in bt["next"],
    f"6 budget: the --token-budget tail is a non-empty strict prefix with capped=1 and next= ({0 if bt is None else len(bt['rows'])} rows)")
dt, dpage = tail_of(rcs["d.xml"][1]), page_of(rcs["d.page"][1])
if dt is None:
    say(False, "8 code first: the docs fixture has a <tail>")
else:
    isdoc = lambda p: p.endswith(".md")
    code = [p for p, _ in dpage if not isdoc(p)]; crank = {p: k for k, p in enumerate(code)}; drank = {p: k for k, (p, _) in enumerate(dpage)}
    rows = dt["rows"]; k8 = 0
    while k8 < len(rows) and k8 < 24 and rows[k8][1] is not None and not isdoc(rows[k8][0]): k8 += 1   # rank rows lead, all with sym=
    crow = [(p, s) for p, s in rows[k8:] if not isdoc(p)]; drow = [(p, s) for p, s in rows if isdoc(p)]
    nsym = sum(1 for _, s in rows if s is not None); symrows = rows[:nsym]; wide = rows[nsym:]
    firstdoc = next((j for j, (p, _) in enumerate(symrows) if isdoc(p)), len(symrows))
    say(all(s is None for _, s in wide) and len(wide) > 0 and any(isdoc(p) for p, _ in symrows) and all(isdoc(p) for p, _ in symrows[firstdoc:]),
        f"8 code first: the old walk's {nsym} rows lead (its doc rows after its code rows), then {len(wide)} p=-only rows")
    say([drank[p] for p, _ in wide] == sorted(drank[p] for p, _ in wide) and any(isdoc(p) for p, _ in wide) and any(not isdoc(p) for p, _ in wide),
        "8 code first: the widened rows (code and doc) follow in page order")
    say(dt["p_only"] == len(wide), f"12 p_only: code first p_only={dt['p_only']} = {len(wide)} widened rows")
    try:
        djt = json.loads(rcs["d.json"][1]).get("tail") or {}
    except Exception:
        djt = {}
    say(djt.get("files") == [p for p, _ in rows] and djt.get("p_only") == len(wide), f"12 p_only: code first JSON files = XML rows, p_only={djt.get('p_only')}")
    dsym = [p for p, s in rows if s is not None]
    for nm in ("d.b3000", "d.b4000"):
        bt9 = tail_of(rcs[nm][1])
        if bt9 is None:
            say(False, f"9 budget order {nm}: a <tail>"); continue
        shown9 = {p for p, _ in bt9["rows"]}; bare = sum(1 for _, s in bt9["rows"] if s is None); miss = [p for p in dsym if p not in shown9]
        say(bare == 0 or not miss, f"9 budget order {nm}: {len(bt9['rows'])} rows, {bare} p=-only shown while {len(miss)} sym= rows of the default tail are cut")
        say(bt9["p_only"] == (bare or None), f"12 p_only: {nm} p_only={bt9['p_only']} = {bare} shown p=-only rows (absent at 0)")
        say([p for p, _ in bt9["rows"]] == [p for p, _ in rows[:len(bt9["rows"])]], f"9 budget order {nm}: the budgeted tail is a prefix of the default tail")
    late = [(p, s) for p, s in crow if crank[p] >= 40]; early = [(p, s) for p, s in crow if crank[p] < 40 and drank[p] >= 40]
    say(len(late) > 0 and all(s is None for _, s in late), f"8 code first: {len(late)} code rows past the page's first 40 code rows carry no sym=")
    say(len(early) > 0 and all(s for _, s in early), f"8 code first (twin): {len(early)} code rows within the first 40 code rows but past page index 40 keep sym=")
    dl = [(p, s) for p, s in drow if drank[p] >= 40]; de = [(p, s) for p, s in drow if drank[p] < 40]
    dls = sum(1 for _, s in dl if s)   # a doc the rank walk listed (at most kForFileTailShownCap of them) keeps its rank row's sym=
    say(len(de) > 0 and all(s for _, s in de), f"8 code first (twin): {len(de)} doc rows within page index 40 keep sym=")
    say(len(dl) - dls > 0 and dls <= 24, f"8 code first: doc rows past page index 40: {len(dl) - dls} without sym=, {dls} with it (rank-walk docs, <= 24)")
def sigs_el(txt):
    m = re.search(r'<sigs[ >].*?</sigs>', txt, re.S); return None if not m else m.group(0)
cutseen = 0
for tb in ("5000", "6000", "8000"):
    a10, b10 = sigs_el(rcs["p1." + tb][1]), sigs_el(rcs["p2." + tb][1])
    t1, t2 = tail_of(rcs["p1." + tb][1]), tail_of(rcs["p2." + tb][1])
    cutseen += a10 is not None and "next_offset=" in a10
    say(a10 is not None and a10 == b10, f"10 sigs funding {tb}: <sigs> byte-identical when only the widened rows' bytes differ ({None if a10 is None else len(a10)} vs {None if b10 is None else len(b10)} B)")
    say(t1 is not None and t2 is not None and t1["raw"] != t2["raw"] and any("wwwwwwwwww" in p for p, _ in t2["rows"]),
        f"10 sigs funding {tb} (twin): the tails differ (P2 lists the long directory)")
say(cutseen > 0, f"10 sigs funding: the head is cut past the target at {cutseen} of 3 budgets (the refill ran)")
try:
    j1, j2 = json.loads(rcs["p1.j6000"][1]), json.loads(rcs["p2.j6000"][1])
    say(j1.get("sigs") is not None and j1.get("sigs") == j2.get("sigs") and j1.get("tail") != j2.get("tail"), f"10 sigs funding JSON 6000: sigs equal ({len(j1.get('sigs') or [])} rows), tails differ")
except Exception as e:
    say(False, f"10 sigs funding JSON: parse error {e}")
def mcp_text(name):
    try:
        rc = open(f"{T}/{name}.rc").read().strip()
        line = next(l for l in open(f"{T}/{name}", encoding="utf8", errors="replace") if l.strip())
        return rc, json.loads(line)["result"]["content"][0]["text"]
    except Exception as e:
        return "parse", f"{e}"
for nm, budgeted in (("m.bud", True), ("m.def", False)):
    rc13, tx13 = mcp_text(nm); t13 = tail_of(tx13) if rc13 == "0" else None
    if t13 is None:
        say(False, f"13 MCP {nm}: rc={rc13} and a <tail> ({tx13[:80]!r})"); continue
    nos = sum(1 for _, s in t13["rows"] if s is None); clause = "tail walk:" in tx13
    if budgeted:
        say(len(t13["rows"]) > 0 and nos == 0 and t13["p_only"] is None and not clause and t13["capped"] == "1" and "--limit=40" in t13["next"],
            f"13 MCP budget_tokens: {len(t13['rows'])} rows, all with sym=, no p_only=, no walk clause, cut with next=")
    else:
        say(nos > 0 and t13["p_only"] == nos and clause, f"13 MCP default (twin): {len(t13['rows'])} rows, p_only={t13['p_only']} = {nos}, walk clause present")
lg = rcs["w.xml"][1]
say("t page rows go on to file-page row 160" in lg, "7 legend: the wide answer's compact legend carries the walk clause (present)")
say("file-page row 160" not in rcs["s.xml"][1] and "tail walk:" not in rcs["s.xml"][1], "7 legend: the no-cut answer (page fits page 0) carries no walk clause (absent)")
say("tail walk: the page rows go on to the file page's first 160 rows" in rcs["w.full"][1] and "tail walk:" not in rcs["s.full"][1],
    "7 legend: --legend=full carries the full walk clause on the wide answer only")
print("fortailwidecheck:", "PASS" if fails == 0 else f"FAIL ({fails})")
sys.exit(1 if fails else 0)
PY

#!/usr/bin/env bash
# fortailwidecheck.sh — FOR-TAIL-WIDE: the --for <tail> walks 4 pages of the file page, not 1.
#
# WHY. A broad --for answer cuts its file tail at the rank rows plus page 0 of `--for=TASK --limit=40`; on the R-ladder
# rows 6 of 7 items the raised page (`--limit=100000`) recovered sat at file-page rank 57-177, past that cut. The tail now
# keeps its rank rows (the files of trimmed head rows first, unchanged) and then lists the file page's first 160 rows
# (kForFileTailPageWalk) not listed above, in the page's own order: one ranking for the page part, the one the raised page
# prints. sym= rides the rank rows and page rows 1-40 (the old cut); a page row past it is path-only, so the extra rows cost
# about a third of a full row. The cut stays disclosed: total= every positive-score file, shown=, capped=1, next= the page
# from the first row not walked.
#
# Arms (each reads the exit code of the command it parses; an empty or crashed answer fails every arm):
#   1  widened:  the page part is exactly page[0:160] minus the rank rows, in page order (red before: page[0:40])
#   2  counts:   shown = rows printed, capped=1, total = the page's total, next= continues at --offset=160
#   3  sym:      no page row at page index >= 40 carries sym=  (absence)  /  every rank row and page row < 40 carries the
#                page row's own sym=  (positive twin)
#   4  no cut:   a fixture with fewer files than one page: capped=0, no next=, every row with sym=, and the tail element is
#                byte-identical to the one rebuilt from the page (rank rows + page rows, all with sym=)
#   5  JSON:     "tail".files is the XML rows in order; "sym" is "" exactly where the XML row has no sym=
#   6  budget:   under --token-budget the tail is a prefix of the default tail and still carries capped=1 and next=
#   7  legend:   the tail clause names the 160-row walk and the sym= scope (present with every tail)
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
Q="widget frobnicate helper"

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
    m = re.search(r'<tail total="(\d+)" shown="(\d+)" capped="(\d)"( next="[^"]*")?>(.*?)</tail>', txt, re.S)
    if not m: return None
    rows = [(html.unescape(p), None if not s else html.unescape(s)) for p, s in re.findall(r'<t p="([^"]*)"(?: sym="([^"]*)")?/>', m.group(5))]
    return dict(total=int(m.group(1)), shown=int(m.group(2)), capped=m.group(3), next=html.unescape(m.group(4) or ""), rows=rows, raw=m.group(0))
def page_of(txt):
    return [(html.unescape(p), html.unescape(s) if s is not None else "") for p, s in re.findall(r'<f p="([^"]*)"[^>]*?(?: sym="([^"]*)")?/>', txt)]
def split(rows, page, walk):
    """R = the shortest prefix (<= 24 rows) for which the rest is exactly page[0:walk] minus R, in page order."""
    for k in range(0, min(24, len(rows)) + 1):
        R = {p for p, _ in rows[:k]}
        if [p for p, _ in rows[k:]] == [p for p, _ in page[:walk] if p not in R]:
            return k
    return None
rcs = {n: load(n) for n in ("w.xml", "w.page", "w.json", "w.bud", "s.xml", "s.page")}
for n, (rc, txt) in rcs.items():
    say(rc == "0" and len(txt) > 200, f"{n}: exit 0 and a non-empty answer (rc={rc}, {len(txt)} B)")
wt, page = tail_of(rcs["w.xml"][1]), page_of(rcs["w.page"][1])
say(wt is not None and len(page) >= 200, f"wide fixture: a <tail> and a raised page of >= 200 rows ({len(page)})")
if wt is None or len(page) < 200:
    print("fortailwidecheck: FAIL (no tail or short page)"); sys.exit(1)
pidx = {p: k for k, (p, _) in enumerate(page)}; psym = dict(page)
k = split(wt["rows"], page, 160)
say(k is not None, f"1 widened: the page part is page[0:160] minus the rank rows, in page order (rank rows={k}; old walk 40 split={split(wt['rows'], page, 40)})")
kv = k is not None
if k is None: k = 0
pagepart = wt["rows"][k:]
say(kv and any(pidx.get(p, -1) >= 40 for p, _ in pagepart), "1 widened: rows past page index 40 are listed")
say(wt["shown"] == len(wt["rows"]) and wt["capped"] == "1" and wt["total"] == len(page), f"2 counts: shown={wt['shown']} rows={len(wt['rows'])} capped={wt['capped']} total={wt['total']} page={len(page)}")
say("--offset=160" in wt["next"] and "--limit=40" in wt["next"], f"2 counts: next= continues the page at offset 160 ({wt['next'][-40:]!r})")
past = [(p, s) for p, s in pagepart if pidx[p] >= 40]; within = [(p, s) for p, s in pagepart if pidx[p] < 40]
say(kv and len(past) > 0 and all(s is None for _, s in past), f"3 sym absence: {len(past)} page rows past index 40, none with sym=")
say(kv and len(within) > 0 and all(s == psym[p] and s for p, s in within), f"3 sym twin: {len(within)} page rows within index 40 carry the page row's sym=")
say(k > 0 and all(s == psym[p] and s for p, s in wt["rows"][:k]), f"3 sym twin: {k} rank rows carry the page row's sym=")
st, spage = tail_of(rcs["s.xml"][1]), page_of(rcs["s.page"][1])
ok4 = st is not None and st["capped"] == "0" and not st["next"] and st["shown"] == st["total"] == len(spage) and all(s for _, s in st["rows"])
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
bt = tail_of(rcs["w.bud"][1])
say(bt is not None and 0 < len(bt["rows"]) < len(wt["rows"]) and [p for p, _ in bt["rows"]] == [p for p, _ in wt["rows"][:len(bt["rows"])]] and bt["capped"] == "1" and "--limit=40" in bt["next"],
    f"6 budget: the --token-budget tail is a non-empty strict prefix with capped=1 and next= ({0 if bt is None else len(bt['rows'])} rows)")
lg = rcs["w.xml"][1]
say("first 160 rows" in lg and "page rows 1-40 only" in lg, "7 legend: the tail clause (default dialect) names the 160-row walk and the sym= scope")
print("fortailwidecheck:", "PASS" if fails == 0 else f"FAIL ({fails})")
sys.exit(1 if fails else 0)
PY

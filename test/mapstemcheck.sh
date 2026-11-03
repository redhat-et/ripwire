#!/usr/bin/env bash
# mapstemcheck.sh — the map scope reserves one row per shown file for its STEM-NAMESAKE type (card MAP-STEM;
# src/serialize.h addMapStemRows).
#
# THE CONTRACT THIS PINS (arms tagged [P] are RED on the pre-change binary 0b2734a7; [G] arms hold on both binaries):
#   WHAT     on the default map (and --json twin), a shown file whose top-K rows leave out the class/struct/interface with the
#            most name subtokens inside the file's stem gains that type as one more row, after its kept rows, stem="1"
#            (JSON "stem":1), counted in shown=. No kept row is dropped.
#   NOT ON   a file whose kept rows hold a complete namesake with as many shared subtokens; a test file (layer="test"); a map that keeps
#            every symbol; RIPWIRE_NO_MAP_STEM=1; a --for answer.
# Arms:
#   A1 [P] --top-k=3: pkg/widgetparsers.py shows WidgetError then WidgetParser stem="1"
#   A2 [P] the stats comment's shown= is 4 (3 kept + 1 stem row)
#   A3 [P] --json twin: the same rows, WidgetParser "stem":1, "shown":4
#   B1 [G] --top-k=4: pkg/helpers.py keeps HelperRegistry (it holds the stem) and gains nothing
#   B2 [G] --top-k=6: tests/test_widgetparsers.py is shown and gains no stem row (TestWidgetParsersSuite stays out)
#   B3 [G] the default top-k keeps every symbol: no stem="1", no clause
#   C1 [G] no row lost: the --top-k=3 answer minus the stem row, its clause and shown= equals RIPWIRE_NO_MAP_STEM=1's
#   L1 [P] the clause rides when a row carries stem="1"; L2 [G] RIPWIRE_NO_MAP_STEM=1 carries neither
#   X1 [G] determinism   X2 [G] xmllint well-formed (when present)
#   D1 [P] --max-tokens=1060 (fix round 1, CI 40206090157 readmedriftcheck G4): the stem rows are the FIRST to go under a budget -
#          the budgeted map prints exactly the ranked rows RIPWIRE_NO_MAP_STEM=1 prints at the same budget (a stem row never displaces
#          one) and no stem="1" row
#   D2 [P] at --max-tokens=1000 (WidgetParser is cut, its stem row would have been added) it says what it left out: stem_cut=1 on the root, defined by its legend clause, shown= = the rows printed
#   D3 [P] --json twin: "stem_cut":1, no "stem":1 row   D4 [G] no budget (A1) and RIPWIRE_NO_MAP_STEM=1 carry no stem_cut
#   E1-E8 (lane map-stem-tight, owner 2026-10-25: MAP-STEM cost +16.9 KB over 14 rows for 1): a stem row must be a COMPLETE namesake -
#          >= 2 of the class name's >= 3-byte subtokens and ALL of them inside the file stem. Fixture test/mapstemtightfix, --top-k=7:
#   E1 [P] pkg/cache.py (CacheBackendFactory: 1 of 3 subtokens) gains no stem row   E2 [P] pkg/widgetstore.py (WidgetRegistryStore: 2 of 3) gains none
#   E3 [G] pkg/widgetparsers.py keeps WidgetParser stem="1" (2 of 2: the strong match stays)
#   E4 [P] pkg/gizmoloader.py shows GizmoLoader (2 of 2), not the larger GizmoLoaderBase (2 of 3): an incomplete class does not shadow the complete one
#   E5 [G] pkg/sinkwriter.py keeps IOSinkWriter (`io` is under 3 bytes: it never counts against completeness)
#   E6 [P] --json twin: the same stem rows (no cache/widgetstore row, GizmoLoader)   E7 [G] RIPWIRE_NO_MAP_STEM_TIGHT=1 restores the loose rows
#   E8 [P] shown= counts exactly the rows printed (3 stem rows, not 5)
#   E9-E12 (CodeRabbit 4381174514) the stem legend (full and compact dialects; the map keeps the XML clause in both) states the rule the run selected: tight = 2+ name words all in the file name, RIPWIRE_NO_MAP_STEM_TIGHT=1 = 1+ name word
#   F1-F3 (cr-prepass-37a, "already held" check): a KEPT class holds the slot only if it is itself a complete namesake. Fixture
#          test/mapstemheldfix, --top-k=3: pkg/formparsers.py keeps FormParserError (form+parser of form+parser+error: incomplete)
#   F1 [P] the complete FormParser still gains its stem="1" row behind the kept FormParserError   F2 [P] --json twin
#   F3 [G] a kept COMPLETE namesake still holds the slot (no stem row): --top-k=5 keeps FormParser itself
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_MAP_STEM RIPWIRE_NO_MAP_STEM_TIGHT
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "mapstemcheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
FIX="$ROOT/test/mapstemfix"
FIXT="$ROOT/test/mapstemtightfix"
FIXH="$ROOT/test/mapstemheldfix"
[ -f "$FIX/pkg/widgetparsers.py" ] || { echo "fixture $FIX missing"; exit 2; }
[ -f "$FIXT/pkg/widgetparsers.py" ] || { echo "fixture $FIXT missing"; exit 2; }
[ -f "$FIXH/pkg/formparsers.py" ] || { echo "fixture $FIXH missing"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

run(){
    local name="$1"; shift
    local envs=()
    while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=( "$1" ); shift; done
    shift
    ( cd "$FIX" || exit 1; env ${envs[@]+"${envs[@]}"} "$BIN" "$FIX" "$@" --cache="$TMP/$name.cache" >"$TMP/$name.out" 2>"$TMP/$name.err" ) \
        || no "$name: ripwire exited non-zero ($( head -c 200 "$TMP/$name.err" | tr '\n' ' ' ))"
}
run a1 -- --top-k=3
run a1off RIPWIRE_NO_MAP_STEM=1 -- --top-k=3
run a3 -- --top-k=3 --json
run b1 -- --top-k=4
run b2 -- --top-k=6
run b3 --
# The budget arms root at `.`, not the absolute fixture path: the path's length is charged against the byte ceiling, so an
# absolute root would move the cut with the checkout's location.
runrel(){
    local name="$1"; shift
    local envs=()
    while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=( "$1" ); shift; done
    shift
    ( cd "$FIX" || exit 1; env ${envs[@]+"${envs[@]}"} "$BIN" . "$@" --cache="$TMP/$name.cache" >"$TMP/$name.out" 2>"$TMP/$name.err" ) \
        || no "$name: ripwire exited non-zero ($( head -c 200 "$TMP/$name.err" | tr '\n' ' ' ))"
}
runt(){
    local name="$1"; shift
    local envs=()
    while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=( "$1" ); shift; done
    shift
    ( cd "$FIXT" || exit 1; env ${envs[@]+"${envs[@]}"} "$BIN" "$FIXT" "$@" --cache="$TMP/$name.cache" >"$TMP/$name.out" 2>"$TMP/$name.err" ) \
        || no "$name: ripwire exited non-zero ($( head -c 200 "$TMP/$name.err" | tr '\n' ' ' ))"
}
runh(){
    local name="$1"; shift
    shift   # the "--" separator
    ( cd "$FIXH" || exit 1; "$BIN" "$FIXH" "$@" --cache="$TMP/$name.cache" >"$TMP/$name.out" 2>"$TMP/$name.err" ) \
        || no "$name: ripwire exited non-zero ($( head -c 200 "$TMP/$name.err" | tr '\n' ' ' ))"
}
runh f1 -- --top-k=3
runh f2 -- --top-k=3 --json
runh f3 -- --top-k=5
runt e1 -- --top-k=7
runt e6 -- --top-k=7 --json
runt e7 RIPWIRE_NO_MAP_STEM_TIGHT=1 -- --top-k=7
runt e9 RIPWIRE_NO_MAP_STEM_TIGHT=1 -- --top-k=7 --legend=full
runt e10 -- --top-k=7 --legend=full
runt e11 RIPWIRE_NO_MAP_STEM_TIGHT=1 -- --top-k=7 --legend=compact
runt e12 -- --top-k=7 --legend=compact
runrel d1 -- --max-tokens=1060
runrel d1off RIPWIRE_NO_MAP_STEM=1 -- --max-tokens=1060
runrel d2 -- --max-tokens=1000
runrel d3 -- --max-tokens=1000 --json
run x1 -- --top-k=3

cat > "$TMP/chk.py" <<'PY'
import json, re, sys
cmd, a = sys.argv[1], sys.argv[2:]
t = open(a[0], encoding="utf-8").read() if a else ""
def file_rows(t, p):
    m = re.search(r'<f p="%s"[^>]*>(.*?)</f>' % re.escape(p), t, re.S)
    return None if m is None else re.findall(r'<s [^>]*>', m.group(1))
def name(r): return re.search(r'\bn="([^"]*)"', r).group(1)
if cmd == "a1":
    rows = file_rows(t, "pkg/widgetparsers.py") or []
    got = [(name(r), 'stem="1"' in r) for r in rows]
    if got != [("WidgetError", False), ("WidgetParser", True)]: print(got); sys.exit(1)
elif cmd == "shown":
    m = re.search(r' shown=(\d+) ', t)
    if not m or m.group(1) != a[1]: print("shown=%s" % (m and m.group(1))); sys.exit(1)
elif cmd == "json":
    d = json.loads(t)
    f = [x for x in d["r"] if x["p"] == "pkg/widgetparsers.py"]
    got = [(s["n"], s.get("stem")) for s in f[0]["s"]] if f else None
    if got != [("WidgetError", None), ("WidgetParser", 1)] or d.get("shown") != 4: print(got, d.get("shown")); sys.exit(1)
elif cmd == "budget":
    off = open(a[1], encoding="utf-8").read()
    rows = lambda x: re.findall(r'<s [^>]*\bk="', x)
    if 'stem="1"' in re.sub(r"<!-- .*?-->", "", t, flags=re.S): print("a stem row under a budget"); sys.exit(1)
    if len(rows(t)) != len(rows(off)) or len(rows(t)) < 2: print("rows %d vs the no-stem run's %d" % (len(rows(t)), len(rows(off)))); sys.exit(1)
elif cmd == "cut":
    sh = re.search(r' shown=(\d+) ', t); n = len(re.findall(r'<s [^>]*\bk="', t))
    if ' stem_cut="1"' not in t or "<!-- stem_cut=" not in t: print("no stem_cut=1 / clause"); sys.exit(1)
    if not sh or int(sh.group(1)) != n: print("shown=%s but %d rows" % (sh and sh.group(1), n)); sys.exit(1)
elif cmd == "cutjson":
    d = json.loads(t)
    if d.get("stem_cut") != 1 or any(s.get("stem") for x in d["r"] for s in x["s"]): print(d.get("stem_cut")); sys.exit(1)
elif cmd == "nocut":
    if "stem_cut" in t: print("stem_cut present"); sys.exit(1)
elif cmd == "stemset":   # stemset OUT FILE EXPECTED(comma list, empty = none): the stem="1" row names of that file
    want = sorted(x for x in a[2].split(",") if x)
    rows = file_rows(t, a[1])
    if rows is None: print("%s not shown (vacuous)" % a[1]); sys.exit(1)
    got = sorted(name(r) for r in rows if 'stem="1"' in r)
    if got != want: print("%s stem rows %s, want %s" % (a[1], got, want)); sys.exit(1)
elif cmd == "stemsetjson":
    d = json.loads(t); want = sorted(x for x in a[2].split(",") if x)
    f = [x for x in d["r"] if x["p"] == a[1]]
    if not f: print("%s not shown (vacuous)" % a[1]); sys.exit(1)
    got = sorted(s["n"] for s in f[0]["s"] if s.get("stem"))
    if got != want: print("%s stem rows %s, want %s" % (a[1], got, want)); sys.exit(1)
elif cmd == "keptstem":   # keptstem OUT FILE KEPT_NAME STEM_NAME(empty = none): the kept (non-stem) row and the stem="1" row of that file
    rows = file_rows(t, a[1])
    if rows is None: print("%s not shown (vacuous)" % a[1]); sys.exit(1)
    kept = [name(r) for r in rows if 'stem="1"' not in r]; stem = [name(r) for r in rows if 'stem="1"' in r]
    if a[2] not in kept or stem != ([a[3]] if a[3] else []): print("%s kept %s stem %s, want %s / %s" % (a[1], kept, stem, a[2], a[3] or "none")); sys.exit(1)
elif cmd == "keptstemjson":
    d = json.loads(t); f = [x for x in d["r"] if x["p"] == a[1]]
    if not f: print("%s not shown (vacuous)" % a[1]); sys.exit(1)
    kept = [s["n"] for s in f[0]["s"] if not s.get("stem")]; stem = [s["n"] for s in f[0]["s"] if s.get("stem")]
    if a[2] not in kept or stem != ([a[3]] if a[3] else []): print("%s kept %s stem %s" % (a[1], kept, stem)); sys.exit(1)
elif cmd == "shownrows":
    sh = re.search(r' shown=(\d+) ', t); n = len(re.findall(r'<s [^>]*\bk="', t)); st = len(re.findall(r'<s [^>]*stem="1"', t))
    if not sh or int(sh.group(1)) != n or st != int(a[1]): print("shown=%s rows=%d stem rows=%d want %s" % (sh and sh.group(1), n, st, a[1])); sys.exit(1)
elif cmd == "nostemin":
    rows = file_rows(t, a[1])
    if rows is None: print("%s not shown (vacuous)" % a[1]); sys.exit(1)
    if any('stem="1"' in r for r in rows): print("stem row in %s" % a[1]); sys.exit(1)
elif cmd == "nostem":
    if 'stem="1"' in t or "<!-- stem=" in t: print("stem= present"); sys.exit(1)
elif cmd == "clause":
    if "<!-- stem=" not in t: print("no clause"); sys.exit(1)
elif cmd == "prefix":
    off = open(a[1], encoding="utf-8").read()
    on = re.sub(r'<s [^>]*stem="1"[^>]*></s>', "", t)
    on = re.sub(r"<!-- stem=.*?-->", "", on, flags=re.S)
    mask = lambda s: re.sub(r'est_tokens="?\d+"?', "E", re.sub(r" shown=\d+ ", " shown=N ", s))
    if mask(on) != mask(off): print("rows beyond the stem row differ"); sys.exit(1)
PY
chk(){ python3 "$TMP/chk.py" "$@"; }
if m="$( chk a1 "$TMP/a1.out" )"; then ok "A1 WidgetParser rides after WidgetError, stem=\"1\""; else no "A1 $m"; fi
if m="$( chk shown "$TMP/a1.out" 4 )"; then ok "A2 shown=4 counts the stem row"; else no "A2 $m"; fi
if m="$( chk json "$TMP/a3.out" )"; then ok "A3 --json twin: \"stem\":1, \"shown\":4"; else no "A3 $m"; fi
if m="$( chk nostemin "$TMP/b1.out" pkg/helpers.py )"; then ok "B1 a file whose kept rows hold its stem type gains nothing"; else no "B1 $m"; fi
if m="$( chk nostemin "$TMP/b2.out" tests/test_widgetparsers.py )"; then ok "B2 a test file gains no stem row"; else no "B2 $m"; fi
if m="$( chk nostem "$TMP/b3.out" )"; then ok "B3 every symbol kept: no stem row, no clause"; else no "B3 $m"; fi
if m="$( chk stemset "$TMP/e1.out" pkg/cache.py "" )"; then ok "E1 a 1-of-3 subtoken class (CacheBackendFactory) gains no stem row"; else no "E1 $m"; fi
if m="$( chk stemset "$TMP/e1.out" pkg/widgetstore.py "" )"; then ok "E2 a 2-of-3 subtoken class (WidgetRegistryStore) gains no stem row"; else no "E2 $m"; fi
if m="$( chk stemset "$TMP/e1.out" pkg/widgetparsers.py WidgetParser )"; then ok "E3 the strong 2-of-2 match (WidgetParser) stays"; else no "E3 $m"; fi
if m="$( chk stemset "$TMP/e1.out" pkg/gizmoloader.py GizmoLoader )"; then ok "E4 the complete GizmoLoader, not the larger incomplete GizmoLoaderBase"; else no "E4 $m"; fi
if m="$( chk stemset "$TMP/e1.out" pkg/sinkwriter.py IOSinkWriter )"; then ok "E5 a sub-3-byte subtoken (io) does not count against completeness"; else no "E5 $m"; fi
if m="$( chk stemsetjson "$TMP/e6.out" pkg/cache.py "" )" && m="$( chk stemsetjson "$TMP/e6.out" pkg/widgetstore.py "" )" && m="$( chk stemsetjson "$TMP/e6.out" pkg/gizmoloader.py GizmoLoader )" && m="$( chk stemsetjson "$TMP/e6.out" pkg/widgetparsers.py WidgetParser )"; then ok "E6 --json twin: the same stem rows"; else no "E6 $m"; fi
if m="$( chk stemset "$TMP/e7.out" pkg/cache.py CacheBackendFactory )" && m="$( chk stemset "$TMP/e7.out" pkg/widgetstore.py WidgetRegistryStore )" && m="$( chk stemset "$TMP/e7.out" pkg/gizmoloader.py GizmoLoaderBase )"; then ok "E7 RIPWIRE_NO_MAP_STEM_TIGHT=1 restores the loose rows"; else no "E7 $m"; fi
if m="$( chk keptstem "$TMP/f1.out" pkg/formparsers.py FormParserError FormParser )"; then ok "F1 a kept incomplete FormParserError does not suppress the complete FormParser"; else no "F1 $m"; fi
if m="$( chk keptstemjson "$TMP/f2.out" pkg/formparsers.py FormParserError FormParser )"; then ok "F2 --json twin: the same rows"; else no "F2 $m"; fi
if m="$( chk keptstem "$TMP/f3.out" pkg/formparsers.py FormParser "" )"; then ok "F3 a kept complete namesake still holds the slot (FormParser kept, no stem row)"; else no "F3 $m"; fi
# E9-E12 (CodeRabbit 4381174514): the legend states the rule the run selected - the tight clause ("2+ name words, all in the file name") is false under the loose rule
leg(){ python3 -c "import re,sys; print(' '.join(re.findall(r'<!--(.*?)-->', open(sys.argv[1], encoding='utf-8').read(), flags=re.S)))" "$1"; }
L9="$( leg "$TMP/e9.out" )"; L10="$( leg "$TMP/e10.out" )"; L11="$( leg "$TMP/e11.out" )"; L12="$( leg "$TMP/e12.out" )"
case "$L9" in *'stem="1" (loose rule'*'1+ name word in the file name'*) case "$L9" in *'2+ name words, all in the file name'*) no "E9 the loose run still carries the tight claim" ;; *) ok "E9 loose rule, full legend: states 1+ name word, not the tight claim" ;; esac ;; *) no "E9 the loose run carries no loose stem clause" ;; esac
case "$L10" in *'2+ name words, all in the file name'*) case "$L10" in *'loose rule'*) no "E10 the tight run names the loose rule" ;; *) ok "E10 tight rule, full legend: 2+ name words, all in the file name" ;; esac ;; *) no "E10 the tight run lost its stem clause" ;; esac
case "$L11" in *'stem="1" (loose rule'*'1+ name word in the file name'*) case "$L11" in *'2+ name words, all in the file name'*|*'s stem=1: the type the file is named for (2+'*) no "E11 the loose compact legend carries a tight claim" ;; *) ok "E11 loose rule, compact legend: the stem clause says 1+ name word (no tight reading)" ;; esac ;; *) no "E11 the loose compact legend has no loose stem clause" ;; esac
case "$L12" in *'2+ name words, all in the file name'*) case "$L12" in *'loose rule'*) no "E12 the tight compact legend names the loose rule" ;; *) ok "E12 tight rule, compact legend: 2+ name words, all in the file name" ;; esac ;; *) no "E12 the tight compact legend lost its stem clause" ;; esac
if m="$( chk shownrows "$TMP/e1.out" 3 )"; then ok "E8 shown= counts the 3 stem rows and the ranked rows printed, no more"; else no "E8 $m"; fi
if m="$( chk prefix "$TMP/a1.out" "$TMP/a1off.out" )"; then ok "C1 no kept row lost or moved: only the stem row, its clause and shown= differ"; else no "C1 $m"; fi
if m="$( chk budget "$TMP/d1.out" "$TMP/d1off.out" )"; then ok "D1 --max-tokens=1060: no stem row, the same ranked rows as the no-stem run"; else no "D1 $m"; fi
if m="$( chk cut "$TMP/d2.out" )"; then ok "D2 stem_cut=1 + its clause, shown= = rows printed"; else no "D2 $m"; fi
if m="$( chk cutjson "$TMP/d3.out" )"; then ok "D3 --json twin: \"stem_cut\":1, no stem row"; else no "D3 $m"; fi
if m="$( chk nocut "$TMP/a1.out" )" && m="$( chk nocut "$TMP/d1off.out" )"; then ok "D4 no budget / RIPWIRE_NO_MAP_STEM=1: no stem_cut"; else no "D4 $m"; fi
if m="$( chk clause "$TMP/a1.out" )"; then ok "L1 the clause defines stem="; else no "L1 $m"; fi
if m="$( chk nostem "$TMP/a1off.out" )"; then ok "L2 RIPWIRE_NO_MAP_STEM=1: no stem row, no clause"; else no "L2 $m"; fi
if cmp -s "$TMP/a1.out" "$TMP/x1.out"; then ok "X1 determinism"; else no "X1 two runs differ"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/a1.out" 2>/dev/null; then ok "X2 xmllint well-formed"; else no "X2 not well-formed"; fi
else
    echo "  SKIP  X2 xmllint not installed"
fi
[ "$fail" = 0 ] && echo "mapstemcheck: PASS" || echo "mapstemcheck: FAIL"
exit "$fail"

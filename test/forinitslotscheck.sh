#!/usr/bin/env bash
# forinitslotscheck.sh — INITIALIZER SLOTS on the shown table rows of a compact-route --for answer (card FOR-SLOTS;
# src/forslots.h).
#
# THE CONTRACT THIS PINS (arms tagged [P] are RED on the pre-change binary 0b2734a7; [G] arms are twins and near-miss negatives
# that hold on both binaries and must keep holding — PROCESS rule 4, no gate erosion):
#   TRIGGER  CLI --for (XML) on the compact route, in the DEFAULT regime (the mem= posture). Not on: the name-exact route, --json,
#            an explicit --token-budget=N, RIPWIRE_NO_INIT_SLOTS=1 (the A/B handle).
#   WHAT     a SHOWN variable/constant row whose initializer binds functions by the index gains slots="k=fn,…" (<= 16 pairs,
#            source order, k = the slot as into= spells it less the row name) and slots_more="N" (pairs not listed).
#   NOT ON   a row whose text the fold or the body slot serves; a struct/class row; a function row.
#
# Arms:
#   A1 [P] C designated initializer `{ .run = f, .stop = g }`: slots="run=f,stop=g" (fold off)
#   A2 [P] C positional initializer `{ f, g }`: slots="[0]=f,[1]=g" — the position, never a guessed field name
#   A3 [P] Python dict literal: slots= names both handlers under the into= key spelling
#   A4 [P] the cap: 20 designated slots print 16 pairs and slots_more="4"
#   B1 [G] the fold serves the initializer's body: no slots= on it (the `.f = fn` text is on screen)
#   B2 [G] the struct row `ops` and the function row `dispatch` never carry slots=
#   F1 [G] RIPWIRE_NO_INIT_SLOTS=1: no slots= and no clause; the answer minus slots= and its clause equals the handle-off answer
#          (est_tokens masked); name-exact --for=o and --json carry none
#   L1 [P] the clause defines slots= and slots_more= in both dialects when a row carries slots=; L2 [G] absent when none does
#   X1 [G] determinism   X2 [G] xmllint well-formed (when xmllint is present)
#
# Usage:  bash test/forinitslotscheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/forinitslotscheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_INIT_SLOTS RIPWIRE_NO_MEMBER_NAMES RIPWIRE_NO_BODY_FOLD RIPWIRE_NO_BODY_SLOT RIPWIRE_NO_OWNER_HOP
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "forinitslotscheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
FIX="$ROOT/test/forinitslotsfix"
for d in c py cap; do [ -d "$FIX/$d" ] || { echo "fixture $FIX/$d missing"; exit 2; }; done
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

Q_C="how does the positional ops table run and stop?"
Q_PY="how does the handler table dispatch run and stop handlers?"
Q_CAP="how does the big optable dispatch its slots?"

# run NAME ROOT [ENV=V ...] -- ARGS... : one answer into $TMP/NAME.xml, a fresh cache per run, cwd = the fixture root
run(){
    local name="$1" root="$2"; shift 2
    local envs=()
    while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=( "$1" ); shift; done
    shift
    ( cd "$root" || exit 1; env ${envs[@]+"${envs[@]}"} "$BIN" "$root" "$@" --cache="$TMP/$name.cache" >"$TMP/$name.xml" 2>"$TMP/$name.err" ) \
        || no "$name: ripwire exited non-zero ($( head -c 200 "$TMP/$name.err" | tr '\n' ' ' ))"
}

cat > "$TMP/chk.py" <<'PY'
import html, json, re, sys
cmd, args = sys.argv[1], sys.argv[2:]
def load(p): return open(p, "rb").read().decode("utf-8", "replace")
def row(t, n):
    m = re.search(r'<d [^>]*\bn="%s"[^>]*>' % re.escape(n), t)
    return m.group(0) if m else None
def attr(r, a):
    m = re.search(r'\b%s="([^"]*)"' % a, r or "")
    return html.unescape(m.group(1)) if m else None
if cmd == "slots":          # FILE NAME EXPECTED [MORE]: the row exists and its slots= (and slots_more=) are exactly these
    t = load(args[0]); r = row(t, args[1])
    if r is None: print("row %s not shown" % args[1]); sys.exit(1)
    got, more = attr(r, "slots"), attr(r, "slots_more")
    want_more = args[3] if len(args) > 3 else None
    if got != args[2] or more != want_more: print("slots=%r slots_more=%r, want %r %r" % (got, more, args[2], want_more)); sys.exit(1)
elif cmd == "none":         # FILE NAME...: each named row is shown and carries no slots=
    t = load(args[0])
    for n in args[1:]:
        r = row(t, n)
        if r is None: print("row %s not shown (vacuous)" % n); sys.exit(1)
        if "slots=" in r: print("row %s carries slots=" % n); sys.exit(1)
elif cmd == "noattr":       # FILE: no slots= anywhere and no clause
    t = load(args[0])
    if "slots=" in t: print("slots= present"); sys.exit(1)
elif cmd == "jsonnone":     # FILE ROW PREFIX: a LIVE --json answer (parses; sigs[] holds ROW) in which no key starts with PREFIX
    # JSON spells an attribute as a key ("slots":...), never `slots=`: the XML-spelled needle cannot appear in it, so a
    # noattr arm over JSON passes on any output at all. This one reads the keys, and first proves the answer is live.
    try: d = json.loads(load(args[0]))
    except ValueError as e: print("not JSON: %s" % e); sys.exit(1)
    if not any(isinstance(x, dict) and x.get("n") == args[1] for x in d.get("sigs", [])): print("sigs[] holds no row %s (vacuous)" % args[1]); sys.exit(1)
    def keys(x):
        if isinstance(x, dict):
            for k, v in x.items():
                yield k
                yield from keys(v)
        elif isinstance(x, list):
            for v in x: yield from keys(v)
    bad = sorted({k for k in keys(d) if k.startswith(args[2])})
    if bad: print("JSON keys %r" % bad); sys.exit(1)
elif cmd == "clause":       # FILE PRESENT(0|1): the compact or full clause rides iff a row carries slots=
    t = load(args[0]); present = args[1] == "1"
    has = "d slots=" in t or "; slots= on a variable" in t
    if has != present: print("clause present=%s want %s" % (has, present)); sys.exit(1)
    if present and "slots_more=" not in t.split("-->")[0]: print("clause does not define slots_more="); sys.exit(1)
elif cmd == "prefix":       # ON OFF: ON less slots=/slots_more= and the clause, est_tokens masked, equals OFF
    on, off = load(args[0]), load(args[1])
    on = re.sub(r' slots="[^"]*"( slots_more="\d+")?', "", on)
    on = re.sub(r"; d slots= [^;]*?slots_more= pairs cut", "", on)
    on = re.sub(r"; slots= on a variable [^;]*?slots_more= the pairs not listed", "", on)
    mask = lambda s: re.sub(r'est_tokens="\d+"', 'est_tokens=""', s)
    if mask(on) != mask(off): print("the answer changed beyond slots="); sys.exit(1)
elif cmd == "nocomment-dash":
    t = load(args[0])
    for c in re.findall(r"<!--(.*?)-->", t, re.S):
        if "--" in c: print("'--' inside a comment"); sys.exit(1)
PY
chk(){ python3 "$TMP/chk.py" "$@"; }

run a1 "$FIX/c" RIPWIRE_NO_BODY_FOLD=1 -- "--for=$Q_C"
run a1f "$FIX/c" RIPWIRE_NO_BODY_FOLD=1 -- "--for=$Q_C" --legend=full
run a3 "$FIX/py" RIPWIRE_NO_BODY_FOLD=1 -- "--for=$Q_PY"
run a4 "$FIX/cap" RIPWIRE_NO_BODY_FOLD=1 -- "--for=$Q_CAP"
run b1 "$FIX/c" -- "--for=$Q_C"
run f1 "$FIX/c" RIPWIRE_NO_BODY_FOLD=1 RIPWIRE_NO_INIT_SLOTS=1 -- "--for=$Q_C"
run f1f "$FIX/c" RIPWIRE_NO_BODY_FOLD=1 RIPWIRE_NO_INIT_SLOTS=1 -- "--for=$Q_C" --legend=full
run f2 "$FIX/c" RIPWIRE_NO_BODY_FOLD=1 -- "--for=o"
run f3 "$FIX/c" RIPWIRE_NO_BODY_FOLD=1 -- "--for=$Q_C" --json
run x1 "$FIX/c" RIPWIRE_NO_BODY_FOLD=1 -- "--for=$Q_C"

if m="$( chk slots "$TMP/a1.xml" o "run=f,stop=g" )"; then ok "A1 designated initializer: slots=\"run=f,stop=g\""; else no "A1 $m"; fi
if m="$( chk slots "$TMP/a1.xml" positional_ops "[0]=f,[1]=g" )"; then ok "A2 positional initializer: slots=\"[0]=f,[1]=g\""; else no "A2 $m"; fi
if m="$( chk slots "$TMP/a3.xml" HANDLER_TABLE '["run"]=run_handler,["stop"]=stop_handler' )"; then ok "A3 Python dict literal: both handlers by key"; else no "A3 $m"; fi
CAPW="$( python3 -c 'print(",".join("s%02d=op%02d" % (i, i) for i in range(16)))' )"
if m="$( chk slots "$TMP/a4.xml" big_optable "$CAPW" 4 )"; then ok "A4 cap: 16 pairs, slots_more=\"4\""; else no "A4 $m"; fi
if grep -q '<fold ' "$TMP/b1.xml" && grep -q 'n="o"><!\[CDATA\[const struct ops o' "$TMP/b1.xml"; then
    if m="$( chk none "$TMP/b1.xml" o )"; then ok "B1 the fold serves o's body: no slots= on o"; else no "B1 $m"; fi
else
    no "B1 vacuous: the fold did not serve o's body"
fi
if m="$( chk none "$TMP/a1.xml" ops dispatch )"; then ok "B2 struct row and function row carry no slots="; else no "B2 $m"; fi
if m="$( chk noattr "$TMP/f1.xml" )" && m2="$( chk clause "$TMP/f1.xml" 0 )"; then ok "F1 RIPWIRE_NO_INIT_SLOTS=1: no slots=, no clause"; else no "F1 $m ${m2:-}"; fi
if m="$( chk prefix "$TMP/a1.xml" "$TMP/f1.xml" )"; then ok "F1 prefix identity: only slots= and its clause differ (compact)"; else no "F1 compact $m"; fi
if m="$( chk prefix "$TMP/a1f.xml" "$TMP/f1f.xml" )"; then ok "F1 prefix identity: only slots= and its clause differ (full legend)"; else no "F1 full $m"; fi
if m="$( chk noattr "$TMP/f2.xml" )"; then ok "F1 name-exact --for=o carries no slots="; else no "F1 name-exact $m"; fi
if m="$( chk jsonnone "$TMP/f3.xml" positional_ops slots )"; then ok "F1 --json carries no slots key (a live answer that holds the initializer row)"; else no "F1 json $m"; fi
if m="$( chk clause "$TMP/a1.xml" 1 )" && m2="$( chk clause "$TMP/a1f.xml" 1 )"; then ok "L1 the clause defines slots= and slots_more= (compact and full)"; else no "L1 $m ${m2:-}"; fi
if m="$( chk clause "$TMP/b1.xml" 0 )"; then ok "L2 no row carries slots=: no clause"; else no "L2 $m"; fi
if cmp -s "$TMP/a1.xml" "$TMP/x1.xml"; then ok "X1 determinism"; else no "X1 two runs differ"; fi
if command -v xmllint >/dev/null 2>&1; then
    bad=0; for f in a1 a1f a3 a4 b1; do xmllint --noout "$TMP/$f.xml" 2>/dev/null || { bad=1; no "X2 $f.xml not well-formed"; }; done
    [ "$bad" = 0 ] && ok "X2 xmllint well-formed"
else
    echo "  SKIP  X2 xmllint not installed"
fi
if m="$( chk nocomment-dash "$TMP/a1f.xml" )"; then ok "X3 no '--' inside the legend comment"; else no "X3 $m"; fi

[ "$fail" = 0 ] && echo "forinitslotscheck: PASS" || echo "forinitslotscheck: FAIL"
exit "$fail"

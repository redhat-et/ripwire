#!/usr/bin/env bash
# forctorhopcheck.sh — the OWNER'S CONSTRUCTOR on the r=1 method row of a compact-route --for answer (card OWNER-CTOR-HOP;
# src/forctorhop.h).
#
# THE CONTRACT THIS PINS (arms tagged [P] are RED on the pre-change binary 0b2734a7; [G] arms hold on both binaries):
#   WHAT     when the r=1 row is a method whose innermost enclosing class defines a constructor (JS `constructor`, Python
#            `__init__`, ...), that row gains ctor_l="N" (the constructor's line), ctor_calls="a,b" (<= 16 resolved callee names)
#            and ctor_calls_more="N" (names cut). Posture: mem='s (compact route, XML, default regime).
#   NOT ON   a class with no constructor; an r=1 row that is the class itself; a constructor the fold serves (the class body).
# Arms:
#   A1 [P] JS: create (r=1) carries ctor_l="10" ctor_calls="makeLogger,makeStore" (name order; fold off)
#   A1b [P] cap over NAME order: a constructor calling 18 distinct names (9 zeta* in the earlier-sorting file, 9 alpha* in the
#            later one, alpha9 defined twice) keeps alpha1..alpha9,zeta1..zeta7 and ctor_calls_more="2" (zeta8, zeta9): the kept
#            16 do not follow which file defines each, and the twice-defined cut name is counted once
#   A2 [P] Python control: Registry.create carries ctor_l="6" ctor_calls="make_store" — the same rule on `__init__` (fold off)
#   B1 [G] a class with no constructor: create carries no ctor_l=
#   B2 [G] fold on: the fold serves Registry's body (it holds the constructor): no ctor_l=
#   B3 [G] r=1 is the class Registry: no ctor_l= on any row
#   F1 [G] RIPWIRE_NO_CTOR_HOP=1: none and no clause; prefix identity (compact and full legends); --json and name-exact none
#   L1 [P] the clause rides in both dialects when a row carries ctor_l=; L2 [G] absent when none does
#   X1 [G] determinism   X2 [G] xmllint well-formed (when present)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_CTOR_HOP RIPWIRE_NO_INIT_SLOTS RIPWIRE_NO_MEMBER_NAMES RIPWIRE_NO_BODY_FOLD RIPWIRE_NO_BODY_SLOT RIPWIRE_NO_OWNER_HOP
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "forctorhopcheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
FIX="$ROOT/test/ownerctorfix"
for d in js py noctor many; do [ -d "$FIX/$d" ] || { echo "fixture $FIX/$d missing"; exit 2; }; done
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
Q="how does create make an entry from the store?"
Q_CLS="how does the registry create an entry?"

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
def rows(t): return re.findall(r'<d [^>]*>', t)
def attr(r, a):
    m = re.search(r'\b%s="([^"]*)"' % a, r or "")
    return html.unescape(m.group(1)) if m else None
if cmd == "ctor":      # FILE NAME LINE CALLS [MORE]
    rs = rows(load(args[0]))
    if not rs or attr(rs[0], "n") != args[1] or attr(rs[0], "r") != "1": print("r=1 is %r" % (rs and attr(rs[0], "n"))); sys.exit(1)
    got = (attr(rs[0], "ctor_l"), attr(rs[0], "ctor_calls"), attr(rs[0], "ctor_calls_more"))
    if got != (args[2], args[3], args[4] if len(args) > 4 else None): print("got %r" % (got,)); sys.exit(1)
elif cmd == "none":    # FILE [R1NAME]: no row carries ctor_l=; the r=1 row is R1NAME (non-vacuous)
    t = load(args[0]); rs = rows(t)
    if len(args) > 1 and (not rs or attr(rs[0], "n") != args[1]): print("r=1 is %r, want %s" % (rs and attr(rs[0], "n"), args[1])); sys.exit(1)
    if "ctor_l=" in t: print("ctor_l= present"); sys.exit(1)
elif cmd == "jsonnone":  # FILE ROW PREFIX: a LIVE --json answer (parses; sigs[] holds ROW) in which no key starts with PREFIX
    # JSON spells an attribute as a key ("ctor_l":...), never `ctor_l=`: the XML-spelled needle cannot appear in it, so a
    # `none` arm over JSON passes on any output at all. This one reads the keys, and first proves the answer is live.
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
elif cmd == "clause":  # FILE 0|1
    t = load(args[0]); has = "d ctor_l= ctor_calls=" in t or "; ctor_l= on the r=1" in t
    if has != (args[1] == "1"): print("clause present=%s" % has); sys.exit(1)
    if has and "ctor_calls_more=" not in t.split("-->")[0]: print("clause does not define ctor_calls_more="); sys.exit(1)
elif cmd == "prefix":  # ON OFF
    on, off = load(args[0]), load(args[1])
    on = re.sub(r' ctor_l="\d+" ctor_calls="[^"]*"( ctor_calls_more="\d+")?', "", on)
    on = re.sub(r"; d ctor_l= ctor_calls= [^;]*?ctor_calls_more= cut", "", on)
    on = re.sub(r"; ctor_l= on the r=1 method row[^;]*?not a claim they answer", "", on)
    mask = lambda s: re.sub(r'est_tokens="\d+"', 'est_tokens=""', s)
    if mask(on) != mask(off): print("the answer changed beyond ctor_l=/ctor_calls="); sys.exit(1)
PY
chk(){ python3 "$TMP/chk.py" "$@"; }

run a1 "$FIX/js" RIPWIRE_NO_BODY_FOLD=1 -- "--for=$Q"
run a1f "$FIX/js" RIPWIRE_NO_BODY_FOLD=1 -- "--for=$Q" --legend=full
run a1b "$FIX/many" RIPWIRE_NO_BODY_FOLD=1 -- "--for=$Q"
run a2 "$FIX/py" RIPWIRE_NO_BODY_FOLD=1 -- "--for=$Q"
run b1 "$FIX/noctor" RIPWIRE_NO_BODY_FOLD=1 -- "--for=$Q"
run b2 "$FIX/js" -- "--for=$Q"
run b3 "$FIX/js" RIPWIRE_NO_BODY_FOLD=1 -- "--for=$Q_CLS"
run f1 "$FIX/js" RIPWIRE_NO_BODY_FOLD=1 RIPWIRE_NO_CTOR_HOP=1 -- "--for=$Q"
run f1f "$FIX/js" RIPWIRE_NO_BODY_FOLD=1 RIPWIRE_NO_CTOR_HOP=1 -- "--for=$Q" --legend=full
run f2 "$FIX/js" RIPWIRE_NO_BODY_FOLD=1 -- "--for=create"
run f3 "$FIX/js" RIPWIRE_NO_BODY_FOLD=1 -- "--for=$Q" --json
run x1 "$FIX/js" RIPWIRE_NO_BODY_FOLD=1 -- "--for=$Q"

# js-def-naming: a JS/TS method row names its class (Registry.create), so the r=1 row is pinned under that name
if m="$( chk ctor "$TMP/a1.xml" Registry.create 10 makeLogger,makeStore )"; then ok "A1 JS constructor: ctor_l=\"10\" ctor_calls=\"makeLogger,makeStore\" (name order)"; else no "A1 $m"; fi
if m="$( chk ctor "$TMP/a1b.xml" Registry.create 2 alpha1,alpha2,alpha3,alpha4,alpha5,alpha6,alpha7,alpha8,alpha9,zeta1,zeta2,zeta3,zeta4,zeta5,zeta6,zeta7 2 )"; then ok "A1b 18 distinct callees: the 16 kept are the first 16 by NAME, ctor_calls_more=\"2\" (the twice-defined alpha9 is kept, not double counted)"; else no "A1b $m"; fi
if m="$( chk ctor "$TMP/a2.xml" Registry.create 6 make_store )"; then ok "A2 Python __init__: ctor_l=\"6\" ctor_calls=\"make_store\""; else no "A2 $m"; fi
if m="$( chk none "$TMP/b1.xml" Registry.create )"; then ok "B1 no constructor: no ctor_l="; else no "B1 $m"; fi
if grep -q '<b t="cls" l="9" p="store.js" n="Registry">' "$TMP/b2.xml"; then
    if m="$( chk none "$TMP/b2.xml" Registry.create )"; then ok "B2 the fold serves the class body: no ctor_l="; else no "B2 $m"; fi
else
    no "B2 vacuous: the fold did not serve Registry"
fi
if m="$( chk none "$TMP/b3.xml" Registry )"; then ok "B3 r=1 is the class: no ctor_l="; else no "B3 $m"; fi
if m="$( chk none "$TMP/f1.xml" )" && m2="$( chk clause "$TMP/f1.xml" 0 )"; then ok "F1 RIPWIRE_NO_CTOR_HOP=1: none, no clause"; else no "F1 $m ${m2:-}"; fi
if m="$( chk prefix "$TMP/a1.xml" "$TMP/f1.xml" )"; then ok "F1 prefix identity (compact)"; else no "F1 compact $m"; fi
if m="$( chk prefix "$TMP/a1f.xml" "$TMP/f1f.xml" )"; then ok "F1 prefix identity (full legend)"; else no "F1 full $m"; fi
if m="$( chk none "$TMP/f2.xml" )"; then ok "F1 name-exact --for=create carries none"; else no "F1 name-exact $m"; fi
if m="$( chk jsonnone "$TMP/f3.xml" create ctor_ )"; then ok "F1 --json carries no ctor_ key (a live answer that holds the r=1 row)"; else no "F1 json $m"; fi
if m="$( chk clause "$TMP/a1.xml" 1 )" && m2="$( chk clause "$TMP/a1f.xml" 1 )"; then ok "L1 the clause rides in both dialects"; else no "L1 $m ${m2:-}"; fi
if m="$( chk clause "$TMP/b1.xml" 0 )"; then ok "L2 no ctor_l=: no clause"; else no "L2 $m"; fi
if cmp -s "$TMP/a1.xml" "$TMP/x1.xml"; then ok "X1 determinism"; else no "X1 two runs differ"; fi
if command -v xmllint >/dev/null 2>&1; then
    bad=0; for f in a1 a1f a2 b1 b2 b3; do xmllint --noout "$TMP/$f.xml" 2>/dev/null || { bad=1; no "X2 $f.xml not well-formed"; }; done
    [ "$bad" = 0 ] && ok "X2 xmllint well-formed"
else
    echo "  SKIP  X2 xmllint not installed"
fi
[ "$fail" = 0 ] && echo "forctorhopcheck: PASS" || echo "forctorhopcheck: FAIL"
exit "$fail"

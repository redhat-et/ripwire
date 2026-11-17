#!/usr/bin/env bash
# safedeletecheck.sh — gate for --safe-delete=SYM: "can I delete this?" answered as FACTS (never a
# verdict), composed from signals the tool already computes elsewhere — 1-hop callers (--callers'
# in-edge walk), the transitive blast radius (--impact's transitiveCallers), every read/write/import/
# call/extends use-site (--uses' own resolveUsesSelector/collectUseSites), the tested= lens (an indexed
# test transitively reaching the symbol / its blast radius), and --dead-code's own high-confidence shape
# at defs=1.
#
# Needs no git repo (the verb never compares against HEAD) — a plain temp source tree, hand-shaped so
# each risk= arm is unambiguous:
#
#   src/a.cpp:
#     static leafUnused( int )     — no caller, no use anywhere               -> risk="none-found"
#                                     (also the dead_code_candidate="1" shape: static, zero callers)
#     helperCalled( int )          — one caller (callerOfHelper), which a     -> risk="uses-exist"
#                                     test file transitively reaches
#     callerOfHelper( int )        — calls helperCalled
#     untestedRadius( int )        — one caller (callerOfUntested), which     -> risk="untested-radius"
#                                     NO test reaches
#     callerOfUntested( int )      — calls untestedRadius
#   test/fixture_test.cpp:
#     runTests()                   — calls callerOfHelper (a test-path file, so runTests is a test SEED —
#                                     isTestSymbol via isTestPath — and its forward reach marks
#                                     callerOfHelper/helperCalled tested_self="1"/radius_tested>0)
#
# Arms, per the plan's gate spec:
#   (1) leaf symbol, zero uses                 -> risk="none-found", callers="0" uses="0"
#   (2) symbol with live (tested) callers      -> risk="uses-exist", callers="1", radius_tested > 0
#   (3) symbol with an untested radius         -> risk="untested-radius", radius_untested == impact_reaches
#   (4) unknown-symbol refusal                 -> nonzero exit, did-you-mean stderr
#   (5) determinism (x3, byte-identical)
#   (6) xmllint pipe (well-formed XML)
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/safedeletecheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/src" "$WORK/test"
cat > "$WORK/src/a.cpp" <<'EOF'
static int leafUnused( int x ) { return x + 1; }

int helperCalled( int x ) { return x + 2; }
int callerOfHelper( int a ) { return helperCalled( a ); }

int untestedRadius( int x ) { return x + 3; }
int callerOfUntested( int a ) { return untestedRadius( a ); }
EOF
cat > "$WORK/test/fixture_test.cpp" <<'EOF'
int runTests() { return callerOfHelper( 1 ); }
EOF

echo "safedeletecheck: BIN=$BIN  (temp corpus, no git)"

sd(){ ( cd "$WORK" && "$BIN" . --safe-delete="$1" --no-cache 2>/dev/null ); }
sdrc(){ ( cd "$WORK" && "$BIN" . --safe-delete="$1" --no-cache >/dev/null 2>&1 ); echo $?; }
sderr(){ ( cd "$WORK" && "$BIN" . --safe-delete="$1" --no-cache 2>&1 >/dev/null ); }
# The leading <!-- ... --> legend(s) prose-describe every attribute with a worked example in quotes (e.g.
# `tested_self="1" means...`), so a naive whole-output grep for an attribute can false-positive on the
# LEGEND's own example instead of the real value on the <safe-delete ...> element itself — the same trap
# test/editcheckcheck.sh's own `rows()` helper documents. Strip everything up to the element's own opening
# tag before reading any attribute out of it.
elem(){ printf '%s' "$1" | sed 's/.*--><safe-delete/<safe-delete/'; }
attr(){ printf '%s' "$( elem "$1" )" | grep -oE "$2=\"[^\"]*\"" | head -1; }

# ── (1) leaf symbol, zero uses anywhere -> none-found ────────────────────────────────────────────────
OUT1="$( sd leafUnused )"
[ "$( attr "$OUT1" callers )" = 'callers="0"' ] && [ "$( attr "$OUT1" uses )" = 'uses="0"' ] \
    && ok "(1) leafUnused(): callers=0 uses=0" \
    || { no "(1) leafUnused() should carry callers=0 uses=0"; printf '%s\n' "$OUT1"; }
[ "$( attr "$OUT1" risk )" = 'risk="none-found"' ] \
    && ok "(1) leafUnused(): risk=none-found" \
    || { no "(1) leafUnused() should carry risk=none-found"; printf '%s\n' "$OUT1"; }
[ "$( attr "$OUT1" dead_code_candidate )" = 'dead_code_candidate="1"' ] \
    && ok "(1) leafUnused(): also a --dead-code high-confidence candidate (static, zero callers)" \
    || { no "(1) leafUnused() should carry dead_code_candidate=1 (static free function, zero callers)"; printf '%s\n' "$OUT1"; }
if [ "$( sdrc leafUnused )" = 0 ]; then ok "(1) exits 0 (a report, not a gate)"; else no "(1) unexpected nonzero exit"; fi

# ── (2) symbol with a live, test-reached caller -> uses-exist, radius partly tested ────────────────────
OUT2="$( sd helperCalled )"
[ "$( attr "$OUT2" callers )" = 'callers="1"' ] \
    && ok "(2) helperCalled(): callers=1 (callerOfHelper)" \
    || { no "(2) helperCalled() should carry callers=1"; printf '%s\n' "$OUT2"; }
printf '%s' "$OUT2" | grep -oE '<c [^>]*/>' | grep -q 'n="callerOfHelper"' \
    && ok "(2) helperCalled(): the caller row names callerOfHelper" \
    || { no "(2) helperCalled(): expected a <c n=\"callerOfHelper\"/> row"; printf '%s\n' "$OUT2"; }
[ "$( attr "$OUT2" tested_self )" = 'tested_self="1"' ] \
    && ok "(2) helperCalled(): tested_self=1 (a test transitively calls it)" \
    || { no "(2) helperCalled() should carry tested_self=1"; printf '%s\n' "$OUT2"; }
RT2="$( attr "$OUT2" radius_tested )"
[ "$RT2" != 'radius_tested="0"' ] && [ -n "$RT2" ] \
    && ok "(2) helperCalled(): radius_tested > 0 ($RT2)" \
    || { no "(2) helperCalled() should carry radius_tested > 0"; printf '%s\n' "$OUT2"; }
[ "$( attr "$OUT2" risk )" = 'risk="uses-exist"' ] \
    && ok "(2) helperCalled(): risk=uses-exist" \
    || { no "(2) helperCalled() should carry risk=uses-exist"; printf '%s\n' "$OUT2"; }

# ── (3) symbol with a live caller that NO test reaches -> untested-radius ───────────────────────────────
OUT3="$( sd untestedRadius )"
[ "$( attr "$OUT3" callers )" = 'callers="1"' ] \
    && ok "(3) untestedRadius(): callers=1 (callerOfUntested)" \
    || { no "(3) untestedRadius() should carry callers=1"; printf '%s\n' "$OUT3"; }
[ "$( attr "$OUT3" tested_self )" = 'tested_self="0"' ] \
    && ok "(3) untestedRadius(): tested_self=0" \
    || { no "(3) untestedRadius() should carry tested_self=0"; printf '%s\n' "$OUT3"; }
IR3="$( attr "$OUT3" impact_reaches | grep -oE '[0-9]+' )"
RU3="$( attr "$OUT3" radius_untested | grep -oE '[0-9]+' )"
[ -n "$IR3" ] && [ "$IR3" != 0 ] && [ "$IR3" = "$RU3" ] \
    && ok "(3) untestedRadius(): radius_untested == impact_reaches ($RU3 == $IR3) — the whole radius is untested" \
    || { no "(3) untestedRadius(): expected radius_untested == impact_reaches (got impact_reaches=$IR3 radius_untested=$RU3)"; printf '%s\n' "$OUT3"; }
[ "$( attr "$OUT3" risk )" = 'risk="untested-radius"' ] \
    && ok "(3) untestedRadius(): risk=untested-radius" \
    || { no "(3) untestedRadius() should carry risk=untested-radius"; printf '%s\n' "$OUT3"; }

# ── (4) unknown symbol -> refuses loudly, names a near-miss ─────────────────────────────────────────────
[ "$( sdrc totallyMadeUpSymbolXYZ )" != 0 ] \
    && ok "(4) unknown symbol: nonzero exit" \
    || no "(4) unknown symbol should refuse (nonzero exit)"
ERR4="$( sderr helperCalled_typo_xyz )"
printf '%s' "$ERR4" | grep -qi 'not found\|did you mean' \
    && ok "(4) unknown symbol: stderr names the refusal" \
    || { no "(4) unknown symbol: expected a not-found/did-you-mean message on stderr"; printf '%s\n' "$ERR4"; }

# ── (5) determinism (x3, byte-identical) ─────────────────────────────────────────────────────────────
D1="$( sd helperCalled )"; D2="$( sd helperCalled )"; D3="$( sd helperCalled )"
[ "$D1" = "$D2" ] && [ "$D2" = "$D3" ] \
    && ok "(5) determinism: 3 runs byte-identical" \
    || no "(5) determinism: runs differ"

# ── (6) well-formed XML (xmllint, when available) ────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    ( cd "$WORK" && "$BIN" . --safe-delete=helperCalled --no-cache 2>/dev/null | xmllint --noout - ) \
        && ok "(6) xmllint: --safe-delete=helperCalled output is well-formed XML" \
        || no "(6) xmllint: --safe-delete=helperCalled output is NOT well-formed XML"
    ( cd "$WORK" && "$BIN" . --safe-delete=leafUnused --no-cache 2>/dev/null | xmllint --noout - ) \
        && ok "(6) xmllint: --safe-delete=leafUnused output is well-formed XML" \
        || no "(6) xmllint: --safe-delete=leafUnused output is NOT well-formed XML"
else
    echo "  SKIP  (6) xmllint not installed — well-formedness not checked"
fi

# ── (7) CALLSITE-AT (2026-10-09): a caller row's sites_at= is its call sites as pasteable file:line tokens, cut at 16 per
#    row with sites_total= and a next= that lists them all (the uses verb) even when no floor named one. RED on the base
#    binary (it printed bare sites_l= lines, uncut). Near miss: an uncut answer carries neither sites_total= nor that next=.
SD7="$( mktemp -d )"; trap 'rm -rf "$WORK" "$SD7"' EXIT
{ printf 'static int sdmany( int x ) { return x; }\nint sdcaller( void )\n{\n    int s = 0;\n'; i=0; while [ $i -lt 20 ]; do printf '    s += sdmany( %d );\n' $i; i=$((i+1)); done; printf '    return s;\n}\n'; } > "$SD7/m.c"
printf 'static int sdone( int x ) { return x; }\nint sdonecaller( void ) { return sdone( 1 ) + sdone( 2 ); }\n' > "$SD7/o.c"
SD7_OUT="$( "$BIN" "$SD7" --no-cache --safe-delete=sdmany 2>/dev/null )"
SD7_ROW="$( printf '%s' "$SD7_OUT" | sed 's/<!--.*-->//' | grep -oE '<c n="sdcaller"[^>]*/>' )"
SD7_AT="$( printf '%s' "$SD7_ROW" | grep -oE ' sites_at="[^"]*"' | sed -e 's/^ sites_at="//' -e 's/"$//' )"
{ [ "$( printf '%s' "$SD7_AT" | wc -w | tr -d ' ' )" = 16 ] && [ "${SD7_AT%% *}" = "m.c:5" ] && printf '%s' "$SD7_ROW" | grep -q ' sites_total="20"' \
  && printf '%s' "$SD7_OUT" | grep -o '<safe-delete [^>]*>' | grep -q ' next="--uses=sdmany"'; } \
    && ok "(7) a 20-site caller lists 16 file:line sites, sites_total=\"20\", and next=\"--uses=sdmany\" lists every one" \
    || no "(7) cut safe-delete row/root: $SD7_ROW $( printf '%s' "$SD7_OUT" | grep -o '<safe-delete [^>]*>' )"
SD7_FULL="$( "$BIN" "$SD7" --no-cache --safe-delete=sdmany --legend=full 2>/dev/null )"
{ printf '%s' "$SD7_FULL" | grep -o '<!--.*-->' | grep -q 'next= is that uses call' && printf '%s' "$SD7_FULL" | grep -q 'sites_total=N' \
  && printf '%s' "$SD7_OUT" | grep -o '<!--.*-->' | grep -q 'next=: ' && printf '%s' "$SD7_FULL" | xmllint --noout - 2>/dev/null; } \
    && ok "(7) both legends define that next= and sites_total= where they ride (full: well-formed)" || no "(7) next=/sites_total= undefined in a legend of the cut answer"
SD7_ONE="$( "$BIN" "$SD7" --no-cache --safe-delete=sdone 2>/dev/null )"
{ printf '%s' "$SD7_ONE" | grep -q '<c n="sdonecaller" p="o.c:2" sites_at="o.c:2"/>' \
  && ! printf '%s' "$SD7_ONE" | grep -o '<safe-delete [^>]*>' | grep -q ' next=' && ! printf '%s' "$SD7_ONE" | grep -q 'sites_total'; } \
    && ok "(7) near miss: an uncut answer carries sites_at= with neither sites_total= nor a next=" \
    || no "(7) uncut answer: $SD7_ONE"

# (8) fix round 1 (review item 1), the --callers SA12 twin: in a caller that also holds a real call, a value use, &f, a
#     block-scope prototype, a string and two comments spelled like the name are NOT call sites. RED when the call-role
#     filter (editcheck.h forEachCallSite) is dropped.
cat > "$SD7/n.c" <<'SDEOF'
typedef int (*sdfp)( int );
static int sdnoise( int x ) { return x; }
int sdnoisecaller( void )
{
    /* sdnoise( 3 ) in a comment */
    // sdnoise( 4 ) in a line comment
    const char *s = "sdnoise( 5 ) in a string";
    int sdnoise( int );
    sdfp p = sdnoise;
    sdfp q = &sdnoise;
    return sdnoise( 6 ) + ( s != 0 ) + p( 0 ) + q( 0 );
}
SDEOF
SD8="$( "$BIN" "$SD7" --no-cache --safe-delete=sdnoise 2>/dev/null )"
SD8_ALL="$( printf '%s' "$SD8" | sed 's/<!--.*-->//' | grep -oE ' sites_at="[^"]*"' | sed -e 's/^ sites_at="//' -e 's/"$//' | tr '\n' ' ' | sed 's/ $//' )"
if ! printf '%s' "$SD8" | grep -q '<c n="sdnoisecaller"'; then
    no "(8) premise: --safe-delete=sdnoise printed no sdnoisecaller row: $SD8"
elif [ "$SD8_ALL" = "n.c:11" ]; then
    ok "(8) near miss: a value use, &f, a local prototype, a string and comments are not sites (only n.c:11)"
else
    no "(8) non-call references printed as call sites: every sites_at= is \"$SD8_ALL\", want \"n.c:11\""
fi

# (9)-(17) IX-3 name-template dispatch (lane name-template-dispatch): a method a template lookup can name is no
#     none-found. RED on main (risk="none-found", no pattern_dispatch=). Python: getattr with an f-string prefix
#     (the textual watch_ shape), a self receiver narrowed to the class family, a bare-variable getattr (no row), a
#     literal getattr (no template, no row), a too-wide f"_{m}" (pattern_too_wide=1, no row); JS: this['compile' + t]
#     (the nunjucks shape). Dead-code membership is unchanged: dead_code_candidate= is not read from these rows.
#     (14)/(15) the same rows on --callers / --impact (red on main: count 0, no hedge); (16) --callers of a too-wide-only
#     method carries pattern_too_wide=1 and no row; (17) a too-wide-only method WITH a caller keeps its evidence reading
#     (no <pdw>, risk unchanged) — (12) is the honesty fix: too wide for a candidate list is still never none-found.
PD="$WORK/pd"; mkdir -p "$PD"
cat > "$PD/react.py" <<'PDEOF'
class Node:
    pass

def check_watchers(obj, name):
    fn = getattr(obj, f"watch_{name}", None)
    return fn

def bare_lookup(obj, name):
    return getattr(obj, name)

def literal_lookup(obj):
    return getattr(obj, "plain_handler")

def wide_lookup(obj, m):
    return getattr(obj, f"_{m}")

class Builder:
    def run(self, rule):
        return getattr(self, f"process_{rule}", None)

    def process_color(self):
        return 1

class Unrelated:
    def process_width(self):
        return 2

class Widget(Node):
    def watch_value(self, v):
        return v

    def bare_target(self):
        return 0

    def plain_handler(self):
        return 0

    def _hidden(self):
        return 0

    def _called(self):
        return 0

def call_it(w):
    return w._called()
PDEOF
cat > "$PD/comp.js" <<'PDEOF'
class Compiler {
  compile(node) {
    var fn = this['compile' + node.typename];
    return fn.call(this, node);
  }
  compileSuper(node) {
    return node;
  }
}
module.exports = { Compiler };
PDEOF
pdsd(){ "$BIN" "$PD" --no-cache --safe-delete="$1" 2>/dev/null | sed 's/<!--.*-->//'; }
PD9="$( pdsd react.py:watch_value )"
if printf '%s' "$PD9" | grep -q 'risk="hedged" pattern_dispatch="1"' && printf '%s' "$PD9" | grep -q '<pd in="check_watchers" p="react.py:5" pattern="watch_\*"/>'; then
    ok "(9) getattr(obj, f\"watch_{name}\") names watch_value: risk=hedged, pattern_dispatch=1, <pd> at react.py:5"
else
    no "(9) watch_value is not hedged by the template lookup: $PD9"
fi
PD10a="$( pdsd Builder.process_color )"; PD10b="$( pdsd Unrelated.process_width )"
if printf '%s' "$PD10a" | grep -q 'pattern_dispatch="1"' && printf '%s' "$PD10b" | grep -q 'risk="none-found"' && ! printf '%s' "$PD10b" | grep -q 'pattern_dispatch='; then
    ok "(10) a self receiver keeps only the class family: Builder.process_color hedged, Unrelated.process_width not"
else
    no "(10) self-receiver family narrowing: in-family=[$PD10a] out-of-family=[$PD10b]"
fi
PD11a="$( pdsd Widget.bare_target )"; PD11b="$( pdsd Widget.plain_handler )"
if printf '%s' "$PD11a$PD11b" | grep -q 'pattern_dispatch='; then
    no "(11) a bare-variable or literal getattr made a template row: [$PD11a] [$PD11b]"
else
    ok "(11) near miss: getattr(obj, name) and getattr(obj, \"plain_handler\") make no pattern row"
fi
PD12="$( pdsd Widget._hidden )"
if printf '%s' "$PD12" | grep -q 'risk="hedged" pattern_too_wide="1"' && printf '%s' "$PD12" | grep -q '<pdws total="1" shown="1"><pdw in="wide_lookup" p="react.py:15" pattern="_\*"/></pdws>' \
    && ! printf '%s' "$PD12" | grep -q 'pattern_dispatch=\|<pd '; then
    ok "(12) f\"_{m}\" is too wide: risk=hedged, pattern_too_wide=1, the site as <pdw> at react.py:15, no candidate list"
else
    no "(12) the too-wide template must hedge (never none-found) and name its site: $PD12"
fi
PD13="$( pdsd compileSuper )"
PD13c="$( "$BIN" "$PD" --no-cache --callees=comp.js:compile 2>/dev/null | sed 's/<!--.*-->//' )"
if printf '%s' "$PD13" | grep -q 'risk="hedged" pattern_dispatch="1"' && printf '%s' "$PD13c" | grep -q '<pd l="3" pattern="compile\*" cands="1" shown="1"><t n="compileSuper" p="comp.js:6"/></pd>'; then
    ok "(13) JS this['compile' + t]: compileSuper hedged; --callees=compile lists it as a <pd> candidate"
else
    no "(13) the JS computed-member template: safe-delete=[$PD13] callees=[$PD13c]"
fi

PD14="$( "$BIN" "$PD" --no-cache --callers=compileSuper 2>/dev/null | sed 's/<!--.*-->//' )"
PDROWS='<pds total="1" shown="1"><pd in="compile" p="comp.js:3" pattern="compile\*"/></pds>'
if printf '%s' "$PD14" | grep -q 'count="0"' && printf '%s' "$PD14" | grep -q 'pattern_dispatch="1"' && printf '%s' "$PD14" | grep -q "$PDROWS"; then
    ok "(14) --callers=compileSuper: count=0 plus pattern_dispatch=1 and the <pd> row naming compile at comp.js:3"
else
    no "(14) --callers=compileSuper lost the template-lookup hedge: $PD14"
fi
PD15="$( "$BIN" "$PD" --no-cache --impact=compileSuper 2>/dev/null | sed 's/<!--.*-->//' )"
if printf '%s' "$PD15" | grep -q 'reaches="0"' && printf '%s' "$PD15" | grep -q 'pattern_dispatch="1"' && printf '%s' "$PD15" | grep -q "$PDROWS"; then
    ok "(15) --impact=compileSuper: reaches=0 plus pattern_dispatch=1 and the <pd> row"
else
    no "(15) --impact=compileSuper lost the template-lookup hedge: $PD15"
fi
PD16="$( "$BIN" "$PD" --no-cache --callers=Widget._hidden 2>/dev/null | sed 's/<!--.*-->//' )"
if printf '%s' "$PD16" | grep -q 'pattern_too_wide="1"' && ! printf '%s' "$PD16" | grep -q 'pattern_dispatch=\|<pd \|<pdw '; then
    ok "(16) --callers=Widget._hidden: pattern_too_wide=1, no row"
else
    no "(16) --callers of a too-wide-only method: $PD16"
fi
PD17="$( pdsd Widget._called )"
if printf '%s' "$PD17" | grep -q 'pattern_too_wide="1"' && ! printf '%s' "$PD17" | grep -q 'risk="hedged"\|risk="none-found"\|<pdw'; then
    ok "(17) near miss: a too-wide-only method with a caller keeps its evidence reading, no <pdw>"
else
    no "(17) a too-wide site overrode real evidence: $PD17"
fi

# (18) N-A: a template with NO literal side (`codes[sc + '']`, f"{m}") carries no name information: it makes no
#     Pattern ref at all (like bare obj[x] in (11)), so a method nothing calls stays none-found — no pattern_too_wide,
#     no <pdw>. RED on c72f9c81 (the fastify statusCodes[statusCode + ''] shape read as pattern="*" and hedged every
#     none-found method). A 1-2 char side (f"_{m}", (12)) is still a too-wide hedge.
PE="$WORK/pe"; mkdir -p "$PE"
cat > "$PE/codes.js" <<'PEEOF'
const statusCodes = { 404: 'Not Found' };
class Reply {
  text(statusCode) {
    return statusCodes[statusCode + ''];
  }
  orphan() {
    return 0;
  }
}
module.exports = { Reply };
PEEOF
cat > "$PE/codes.py" <<'PEEOF'
def by_name(obj, m):
    return getattr(obj, f"{m}")

class Thing:
    def lonely(self):
        return 0
PEEOF
PD18a="$( "$BIN" "$PE" --no-cache --safe-delete=codes.js:orphan 2>/dev/null | sed 's/<!--.*-->//' )"
PD18b="$( "$BIN" "$PE" --no-cache --safe-delete=Thing.lonely 2>/dev/null | sed 's/<!--.*-->//' )"
PD18c="$( "$BIN" "$PE" --no-cache --callees=codes.js:text 2>/dev/null | sed 's/<!--.*-->//' )"
if printf '%s' "$PD18a" | grep -q 'risk="none-found"' && printf '%s' "$PD18b" | grep -q 'risk="none-found"' \
    && ! printf '%s' "$PD18a$PD18b$PD18c" | grep -q 'pattern_too_wide=\|pattern_dispatch=\|<pdw\|<pd \|pattern="\*"'; then
    ok "(18) a zero-literal template (codes[sc + ''], f\"{m}\") makes no pattern ref: codes.js:orphan / Thing.lonely stay none-found"
else
    no "(18) a zero-literal template made a pattern ref: [$PD18a] [$PD18b] callees=[$PD18c]"
fi

# (19) train 30 CR pre-pass A3: a name template is a glob, never a name — --external-surface lists no `watch_*` / `compile*`
PD19="$( "$BIN" "$PD" --no-cache --external-surface 2>/dev/null | sed 's/<!--.*-->//' )"
if [ -n "$PD19" ] && ! printf '%s' "$PD19" | grep -qE '<x n="[^"]*\*"'; then ok "(19) --external-surface lists no name template as an external name"
else no "(19) --external-surface lists a template glob (or produced nothing): $( printf '%s' "$PD19" | grep -oE '<x n="[^"]*\*"[^>]*>' | head -3 )"; fi

# (20) train 30 CodeRabbit: the pattern counts ride on EVERY dialect of --callers/--impact, and --impact carries the too-wide
#     count. RED on ad8af71e: the --json roots had no pattern_dispatch/pattern_too_wide key (a silent count 0), the
#     columnar --impact root had neither attribute, and --impact passed a literal 0 for pattern_too_wide (a too-wide-only
#     method read reaches="0" with no hedge and no legend clause). Near miss: a literal getattr makes no key.
pdjson(){ "$BIN" "$PD" --no-cache "$@" --json 2>/dev/null | python3 -c '
import json, sys
try: d = json.load( sys.stdin )
except ValueError: print( "NOT-JSON" ); sys.exit( 0 )
print( "count=%s reaches=%s pd=%s pw=%s" % ( d.get( "count", "-" ), d.get( "reaches", "-" ), d.get( "pattern_dispatch", "-" ), d.get( "pattern_too_wide", "-" ) ) )'; }
PD20a="$( pdjson --callers=compileSuper )"
[ "$PD20a" = "count=0 reaches=- pd=1 pw=-" ] && ok "(20a) --callers=compileSuper --json: count 0 plus pattern_dispatch 1 ($PD20a)" \
                                          || no "(20a) --callers=compileSuper --json lost the template-lookup count: $PD20a"
PD20b="$( pdjson --impact=compileSuper )"
[ "$PD20b" = "count=- reaches=0 pd=1 pw=-" ] && ok "(20b) --impact=compileSuper --json: reaches 0 plus pattern_dispatch 1 ($PD20b)" \
                                           || no "(20b) --impact=compileSuper --json lost the template-lookup count: $PD20b"
PD20c="$( "$BIN" "$PD" --no-cache --impact=compileSuper --format=columnar 2>/dev/null | grep -o '<impact [^>]*>' )"
case "$PD20c" in *' reaches="0" '*'pattern_dispatch="1"'*) ok "(20c) --impact=compileSuper --format=columnar: the root carries pattern_dispatch=1" ;;
                 *) no "(20c) columnar --impact root lost pattern_dispatch=: ${PD20c:-no root}" ;; esac
PD20d="$( "$BIN" "$PD" --no-cache --legend=full --impact=Widget._hidden 2>/dev/null )"; pdrc=$?
if [ "$pdrc" -eq 0 ] && printf '%s' "$PD20d" | grep -q '<impact [^>]* reaches="0"[^>]* pattern_too_wide="1"' && printf '%s' "$PD20d" | grep -q 'pattern_too_wide=K: K templates' \
   && ! printf '%s' "$PD20d" | perl -0pe 's/<!--.*?-->//gs' | grep -q 'pattern_dispatch="\|<pd \|<pdw '; then   # rows only: the legend names <pd
    ok "(20d) --impact=Widget._hidden: pattern_too_wide=1 and its legend clause, no row"
else no "(20d) --impact of a too-wide-only method (rc=$pdrc): $( printf '%s' "$PD20d" | grep -o '<impact [^>]*>' )"; fi
if command -v xmllint > /dev/null 2>&1; then
    printf '%s' "$PD20d" > "$WORK/pd20d.xml"
    if xmllint --noout "$WORK/pd20d.xml" 2> "$WORK/pd20d.err"; then ok "(20d) xmllint parses the --legend=full answer"; else no "(20d) xmllint: $( head -c 300 "$WORK/pd20d.err" )"; fi
else
    printf '  SKIP  (20d) xmllint not installed — XML parse not checked\n'
fi
PD20e="$( pdjson --impact=Widget._hidden )"; PD20f="$( "$BIN" "$PD" --no-cache --impact=Widget._hidden --format=columnar 2>/dev/null | grep -o '<impact [^>]*>' )"
case "$PD20e|$PD20f" in "count=- reaches=0 pd=- pw=1|"*'pattern_too_wide="1"'*) ok "(20e) --impact=Widget._hidden: pattern_too_wide on the --json and columnar roots too ($PD20e)" ;;
                         *) no "(20e) --impact too-wide count missing on --json/columnar: [$PD20e] [${PD20f:-no root}]" ;; esac
PD20g="$( pdjson --callers=Widget.plain_handler )"
[ "$PD20g" = "count=0 reaches=- pd=- pw=-" ] && ok "(20g) near miss: a literal getattr makes no pattern key on --json ($PD20g)" \
                                           || no "(20g) --callers=Widget.plain_handler --json: expected count 0 and no pattern keys, got $PD20g"

# (21) CR676-USES-EXIST-EMPTY: a function used only as a value (a designated initialiser, no caller) reads risk=uses-exist over
#      an EMPTY radius (impact_reaches=0, radius_tested=0). The full legend's sentence for it must not claim "at least part of the
#      radius is test-covered" there; it states the empty radius instead. Near miss: helperCalled (a tested radius) keeps the
#      coverage sentence byte-for-byte. RED on the base binary (it printed the coverage claim on the empty radius).
SD21="$( mktemp -d )"; trap 'rm -rf "$WORK" "$SD7" "$SD21"' EXIT
printf 'static int viaTableOnly( int x ) { return x + 4; }\nstruct ops { int (*open)( int ); };\nstruct ops table = { .open = viaTableOnly };\n' > "$SD21/b.c"
SD21_OUT="$( "$BIN" "$SD21" --no-cache --safe-delete=viaTableOnly --legend=full 2>/dev/null )"   # status: the root element is the premise; a refusal prints none and the premise FAILs
SD21_ROOT="$( printf '%s' "$SD21_OUT" | grep -o '<safe-delete [^>]*>' )"
SD21_LEG="$( printf '%s' "$SD21_OUT" | grep -o '<!--.*-->' )"
if ! { printf '%s' "$SD21_ROOT" | grep -q ' risk="uses-exist"' && printf '%s' "$SD21_ROOT" | grep -q ' impact_reaches="0"' \
       && printf '%s' "$SD21_ROOT" | grep -q ' radius_tested="0"'; }; then
    no "(21) premise: viaTableOnly should read risk=uses-exist with impact_reaches=0 radius_tested=0: $SD21_ROOT"
elif printf '%s' "$SD21_LEG" | grep -q 'at least part of the radius is test-covered'; then
    no "(21) an empty radius (impact_reaches=0) still claims part of it is test-covered"
elif printf '%s' "$SD21_LEG" | grep -q 'uses-exist: callers or uses exist, but the transitive blast radius is empty (impact_reaches=0), so it claims no test coverage'; then
    ok "(21) uses-exist over an empty radius states the empty radius, no coverage claim"
else
    no "(21) uses-exist over an empty radius carries no sentence for its value"
fi
SD21_NEAR="$( sd helperCalled )"   # status: its risk=/radius_tested= attributes are the verdict; a refusal prints none and the arm FAILs
SD21_NFULL="$( cd "$WORK" && "$BIN" . --safe-delete=helperCalled --no-cache --legend=full 2>/dev/null )"; sd21rc=$?
[ "$sd21rc" = 0 ] && printf '%s' "$SD21_NFULL" | grep -q 'uses-exist: callers or uses exist, and at least part of the radius is test-covered\. ' \
    && [ "$( attr "$SD21_NEAR" risk )" = 'risk="uses-exist"' ] && [ "$( attr "$SD21_NEAR" radius_tested )" != 'radius_tested="0"' ] \
    && ok "(21) near miss: helperCalled (a tested radius) keeps the coverage sentence" \
    || no "(21) near miss: helperCalled lost its uses-exist coverage sentence"

[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"

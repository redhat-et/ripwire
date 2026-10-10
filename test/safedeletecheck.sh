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

[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"

#!/usr/bin/env bash
# langordercheck.sh — task D gate: language-first order for name answers.
#
# The rule (owner's): exact matching language > its edge-family (langCompatible's class) > the
# kind ladder > foreign languages last — levels decide WITHIN a group, never across it. The
# fixtures in test/langorderfix/ + test/langorderjvmfix/ are the collision matrix; their file
# comments carry the tier each line demonstrates. Everything here is RED until D1-D4 land:
# today the bare-name lane is rank-first with a path-accident reference language.
#
# Arms:
#   (A1) corpus anchor (no context): langorderfix leads with the C++ fn despite rank 2 vs 3/4
#   (A2) @rs suffix pins the foreign trait exact-first          (A3) @c makes the struct exact
#   (A4) @bogus refuses, naming the known tags                  (A5) foreign fallback SAYS so
#   (A6) JVM corpus: kt wins the count, jv/ never fronts on id  (A7) determinism x2
#
# Usage:  bash test/langordercheck.sh [path/to/ripwire]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
FIX="$ROOT/test/langorderfix"
JVM="$ROOT/test/langorderjvmfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# ── (A1) corpus anchor: exact C++ function fronts struct/trait/module despite ranks ──────────────────
A1="$( "$BIN" --around=Shape "$FIX" 2>/dev/null )"
first="$( printf '%s' "$A1" | grep -m1 -o '<s [^>]*' )"
case "$first" in
    *'t="fn"'*'n="Shape"'*)
        fp="$( printf '%s' "$A1" | grep -m1 -o '<f p="[^"]*"' | head -1 )"
        case "$fp" in *'p="widget.cpp"'*)
            printf '%s' "$A1" | grep -q 'reflang="cpp"' \
                && ok "(A1) corpus anchor: <f widget.cpp> t=fn Shape fronts the tree, reflang=\"cpp\" disclosed" \
                || no "(A1) right pick but no reflang=: $( printf '%s' "$A1" | grep -m1 -o '<r [^>]*>' | head -c 200 )"
        ;; *) no "(A1) focus file wrong: $fp / first row: $first" ;; esac
    ;; *) no "(A1) focus row wrong (rank-first path accident?): $first" ;;
esac

# ── (A2/A3) @lang suffix: explicit anchor is exact-tier, byte-pinned per family ─────────────────────
A2="$( "$BIN" --around=Shape@rs "$FIX" 2>/dev/null | grep -m1 -o '<s [^>]*' )"
A2F="$( "$BIN" --around=Shape@rs "$FIX" 2>/dev/null | grep -m1 -o '<f p="[^"]*"' )"
case "$A2$A2F" in *'t="iface"'*'p="widget.rs"'*) ok "(A2) Shape@rs pins the Rust trait exact-first" ;;
                                                  *) no "(A2) Shape@rs wrong: $A2 | $A2F" ;; esac
A3="$( "$BIN" --around=Shape@c "$FIX" 2>/dev/null | grep -m1 -o '<s [^>]*' )"
case "$A3" in *'t="struct"'*) ok "(A3) Shape@c anchors to C — the struct is exact regardless of rank" ;;
                              *) no "(A3) Shape@c wrong: $A3" ;; esac

# ── (A4) unknown language tag is refused with the known set (never silently ignored) ────────────────
A4E="$( "$BIN" --around=Shape@bogus "$FIX" 2>&1 >/dev/null )"; A4RC=$?
if [ "$A4RC" = 0 ]; then
    no "(A4) Shape@bogus exit 0 — an unknown anchor must refuse"
elif printf '%s' "$A4E" | grep -q 'cpp' && printf '%s' "$A4E" | grep -qi 'unknown language\|known languages'; then
    ok "(A4) Shape@bogus refused, naming the known tags"
else
    no "(A4) refusal wrong: rc=$A4RC $( printf '%s' "$A4E" | head -c 200 )"
fi

# ── (A5) foreign fallback is DISCLOSED, never a silent cross-language pick ──────────────────────────
A5E="$( "$BIN" --around=Extra@cpp "$JVM" 2>&1 >/dev/null )"; A5RC=$?
A5S="$( "$BIN" --around=Extra@cpp "$JVM" 2>/dev/null | grep -m1 -o '<s [^>]*' )"
if [ "$A5RC" = 0 ] && printf '%s' "$A5E" | grep -q 'holds no definition' \
   && case "$A5S" in *'n="Extra"'*) true ;; *) false ;; esac; then
    ok "(A5) cpp-anchored Extra: fallback served AND said ('holds no definition')"
else
    no "(A5) fallback not disclosed or row wrong: rc=$A5E[$A5RC] $( printf '%s' "$A5E" | head -c 160 ) / $A5S"
fi

# ── (A6) JVM pair: the corpus count anchors Kotlin; the jv/ id accident cannot win ─────────────────
A6="$( "$BIN" --around=Marker "$JVM" 2>/dev/null )"
A6F="$( printf '%s' "$A6" | grep -m1 -o '<f p="[^"]*"' )"
case "$A6F" in *'p="kt/Marker.kt"'*) printf '%s' "$A6" | grep -q 'reflang="kt"' \
    && ok "(A6) Marker fronts kt/Marker.kt under the corpus anchor (reflang=kt)" \
    || no "(A6) right file, missing reflang=: $( printf '%s' "$A6" | grep -m1 -o '<r [^>]*>' | head -c 200 )" ;;
                                *) no "(A6) Marker front wrong (path-order accident): $A6F" ;; esac

# ── (A7) determinism x2 on the anchor-bearing outputs (house pattern) ──────────────────────────────
"$BIN" --around=Shape "$FIX" > /dev/null 2>&1
d1="$( "$BIN" --around=Shape "$FIX" 2>/dev/null )"; d2="$( "$BIN" --around=Shape "$FIX" 2>/dev/null )"
[ -n "$d1" ] && [ "$d1" = "$d2" ] && ok "(A7) --around byte-stable x2" || no "(A7) anchor output not deterministic"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

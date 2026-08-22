#!/usr/bin/env bash
# layerquerycheck.sh — gate for the layer(SET, NAME) filter in --graph-query (P0-5).
#
# WHY THIS GATE EXISTS. The default map already tags every file node with an architecture layer
# (`layer="render"`, arch.h's built-in directory-name taxonomy — src/serialize.h emits it), but the
# composable query language could not see it: there was no way to ask "which functions in the render
# layer have 10+ callers?" even though the map prints the answer's first half on every run. layer() closes
# that, and this gate pins the three things a new predicate in a CLOSED expression language must get right:
#
#   1  it SELECTS the same set the map's layer= attribute names (one taxonomy, two surfaces — a second
#      definition of "layer" is the drift this gate exists to prevent);
#   2  it COMPOSES with the existing filters/joins (that is the whole point of a closed language);
#   3  it REFUSES loudly instead of returning count="0". A predicate that answers "0" for a misspelled
#      layer, or for a tree that has no layer taxonomy at all, tells an agent "there is no such code"
#      when the truth is "you cannot ask that here" — the exact honesty failure §P0.5b fixed for name().
#      Two refusal arms, because the two causes are different facts and must not be spelled the same way.
#
# FIXTURE NOTE (and it is load-bearing): the layer taxonomy matches DIRECTORY COMPONENTS of the indexed
# path, and `test/` is itself a built-in layer dir — so any fixture committed under test/ has EVERY file
# tagged layer="test" and cannot discriminate. The fixtures are therefore built in a temp dir outside the
# repo. That is not a convenience; a committed fixture would make arms 1-2 pass for the wrong reason.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/layerquerycheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "layerquerycheck: BIN=$BIN"

# ── fixtures ─────────────────────────────────────────────────────────────────────────────────────────
# corp/  — two LAYERED dirs (render, infra) plus one unlayered dir (lib), so "layered" and "in layer X"
#          are distinguishable facts.
# flat/  — no directory component matches any built-in layer ⇒ NO taxonomy at all (refusal arm 4).
mkdir -p "$WORK/corp/render" "$WORK/corp/infra" "$WORK/corp/lib" "$WORK/flat/pkg"
printf 'def draw_frame():\n    return 1\n\ndef submit_pass():\n    return 2\n' > "$WORK/corp/render/gpu.py"
printf 'def pool_alloc():\n    return 3\n'                                     > "$WORK/corp/infra/pool.py"
printf 'def helper_only():\n    return 4\n'                                    > "$WORK/corp/lib/util.py"
printf 'def plain_fn():\n    return 5\n'                                       > "$WORK/flat/pkg/mod.py"

q(){ "$BIN" "$1" --graph-query="$2" --no-cache 2>"$WORK/err"; }
names(){ printf '%s' "$1" | grep -oE '<s [^>]*n="[^"]*"' | grep -oE 'n="[^"]*"' | sed 's/n="//;s/"//' | sort | tr '\n' ' '; }

# PRESENCE GUARD (CONTRIBUTING §2): the arms below assert things about a layer= tag that the MAP must
# already be emitting. If it is not, every layer() arm would be measuring an absent taxonomy, not a
# broken filter — so assert the precondition first and say which one failed.
MAP="$( "$BIN" "$WORK/corp" --no-cache 2>/dev/null )"
if printf '%s' "$MAP" | grep -q 'layer="render"' && printf '%s' "$MAP" | grep -q 'layer="infra"'; then
    ok "guard: the map already tags the fixture with layer=\"render\" and layer=\"infra\""
else
    no "guard: the map does NOT tag the fixture (layer= missing) — the layer() arms below would be inert"
fi

# ── arm 1: layer(all,render) selects exactly the render-layer symbols ────────────────────────────────
R="$( q "$WORK/corp" 'layer(all,render)' )"; ec=$?
got="$( names "$R" )"
if [ "$ec" = 0 ] && [ "$got" = "draw_frame submit_pass " ]; then
    ok "arm 1: layer(all,render) selects exactly the render symbols ($got)"
else
    no "arm 1: layer(all,render) → exit=$ec, symbols='$got' (expected 'draw_frame submit_pass ')"; sed 's/^/    /' "$WORK/err" | head -3
fi

# ── arm 2: a second layer is DISJOINT (the filter partitions, it does not pass everything through) ───
I="$( q "$WORK/corp" 'layer(all,infra)' )"; ec=$?
goti="$( names "$I" )"
if [ "$ec" = 0 ] && [ "$goti" = "pool_alloc " ]; then
    ok "arm 2a: layer(all,infra) selects exactly the infra symbols ($goti)"
else
    no "arm 2a: layer(all,infra) → exit=$ec, symbols='$goti' (expected 'pool_alloc ')"
fi
[ "$got" != "$goti" ] && ok "arm 2b: render and infra select DIFFERENT sets (the filter is not a pass-through)" \
                      || no "arm 2b: render and infra select the SAME set — layer() is not filtering"
# the unlayered file must appear in NEITHER
case "$got$goti" in
    *helper_only*) no "arm 2c: an UNLAYERED symbol (helper_only) leaked into a layer() result" ;;
    *)             ok "arm 2c: the unlayered lib/ symbol appears in no layer() result" ;;
esac

# ── arm 3: composition with the existing closed operators ────────────────────────────────────────────
Cq="$( q "$WORK/corp" 'and(layer(all,render),kind(all,fn))' )"; ec=$?
gotc="$( names "$Cq" )"
if [ "$ec" = 0 ] && [ "$gotc" = "draw_frame submit_pass " ]; then
    ok "arm 3a: and(layer(...),kind(...)) composes ($gotc)"
else
    no "arm 3a: and(layer(all,render),kind(all,fn)) → exit=$ec, symbols='$gotc'"; sed 's/^/    /' "$WORK/err" | head -3
fi
Nq="$( q "$WORK/corp" 'not(all,layer(all,render))' )"; ec=$?
gotn="$( names "$Nq" )"
case "$gotn" in
    *draw_frame*) no "arm 3b: not(all,layer(all,render)) still contains draw_frame" ;;
    *pool_alloc*) ok "arm 3b: not(all,layer(all,render)) excludes render, keeps the rest ($gotn)" ;;
    *)            no "arm 3b: not(all,layer(all,render)) → exit=$ec, symbols='$gotn'" ;;
esac

# ── arm 4: REFUSAL 1 — a layer word outside the closed vocabulary ────────────────────────────────────
Uq="$( q "$WORK/corp" 'layer(all,frontend)' )"; ec=$?
if [ "$ec" != 0 ] && grep -q "unknown layer 'frontend'" "$WORK/err" && ! printf '%s' "$Uq" | grep -q '<query'; then
    ok "arm 4: an unknown layer word is REFUSED (exit $ec, no <query> emitted, vocabulary listed)"
else
    no "arm 4: layer(all,frontend) should refuse loudly — exit=$ec, stdout has query=$( printf '%s' "$Uq" | grep -c '<query' )"; sed 's/^/    /' "$WORK/err" | head -3
fi

# ── arm 5: REFUSAL 2 — a well-spelled layer against a tree with NO taxonomy at all ───────────────────
# This is the "never empty-as-zero" arm: `flat/` has no layer dirs, so count="0" would read as
# "no render code here" when the truth is "this tree has no layers to ask about".
Fq="$( q "$WORK/flat" 'layer(all,render)' )"; ec=$?
if [ "$ec" != 0 ] && grep -qi 'no layer taxonomy' "$WORK/err" && ! printf '%s' "$Fq" | grep -q '<query'; then
    ok "arm 5a: an unlayered tree REFUSES layer() instead of answering 0 (exit $ec)"
else
    no "arm 5a: layer() on an unlayered tree should refuse — exit=$ec, stdout has query=$( printf '%s' "$Fq" | grep -c '<query' )"; sed 's/^/    /' "$WORK/err" | head -3
fi
# MUTATION: the same tree, the same binary, a NON-layer query still answers — so arm 5a is refusing the
# predicate, not failing the corpus (a gate that cannot tell those apart is green while inert).
Kq="$( q "$WORK/flat" 'kind(all,fn)' )"; ec=$?
[ "$ec" = 0 ] && printf '%s' "$Kq" | grep -q 'plain_fn' \
    && ok "arm 5b: the SAME unlayered tree answers kind(all,fn) normally — the refusal is layer()-specific" \
    || no "arm 5b: the unlayered tree fails a plain query too (exit=$ec) — arm 5a proves nothing"

# ── arm 6: a well-spelled layer that is simply absent from a LAYERED tree is a MEASUREMENT ───────────
# The §P0.5b rule, applied consistently: a valid literal that legitimately selects nothing reports
# count="0"; only an unaskable question refuses.
Aq="$( q "$WORK/corp" 'layer(all,audio)' )"; ec=$?
if [ "$ec" = 0 ] && printf '%s' "$Aq" | grep -q 'count="0"'; then
    ok "arm 6: a valid layer with no members in a LAYERED tree reports count=\"0\" (measurement, not refusal)"
else
    no "arm 6: layer(all,audio) on a layered tree → exit=$ec (expected exit 0 with count=\"0\")"; sed 's/^/    /' "$WORK/err" | head -3
fi

# ── arm 7: determinism + well-formedness ─────────────────────────────────────────────────────────────
R2="$( q "$WORK/corp" 'layer(all,render)' )"
if [ -z "$R" ]; then
    no "arm 7a: EMPTY output — 0 B is vacuously identical, not deterministic"
elif [ "$R" = "$R2" ]; then
    ok "arm 7a: two runs byte-identical (determinism)"
else
    no "arm 7a: two runs DIFFER"
fi
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$R" | xmllint --noout - 2>"$WORK/xl" && ok "arm 7b: output is well-formed XML" || { no "arm 7b: xmllint rejected the output"; sed 's/^/    /' "$WORK/xl" | head -3; }
else
    no "arm 7b: xmllint missing — cannot verify well-formedness (install libxml2-utils)"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

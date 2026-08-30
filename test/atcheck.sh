#!/usr/bin/env bash
# atcheck.sh — gate for the line-seeded selector: bare --at=FILE:LINE (the enclosing-scope-chain report)
# and the @FILE:LINE spelling accepted by every SYM-taking selector (ARISE get_enclosing_scopes parity +
# line-seeded addressing; design registered in the 2026-08-30 open-ranked round, lane C report §three-tier).
#
# The gap this closes: an agent holds FILE:LINE (a compiler error, a diff hunk, a profiler frame) but every
# seeded verb demanded a NAME. The selector grammar already accepted `file:line:name` (§P8 seam 2); this is
# the no-name half, spelled with an explicit `@` because a bare `file:line` cannot be told apart from the
# `file:name` form for a numeric name (JSON config keys can be all digits) — an inference there would be a
# guess, and a guess is refused by house rule.
#
# RED-FIRST PROOF SHAPE: every arm asserts at-specific bytes (the <at> root element, a chain row, a refusal
# sentence only this arm prints) — never a bare exit code. The baseline binary refuses `--at=…` as an
# unknown flag with none of these bytes, and resolves `@…` selectors to the shared not-found refusal WITHOUT
# the at-diagnosis clause, so each arm fails against it.
#
# Arms:
#   (1)  bare --at inside a method body: chain outermost->innermost (struct row BEFORE method row),
#        root carries p= (resolved root-relative path), l= (echoed line), sym= (innermost name), chain=
#   (2)  --at on the signature line resolves to that definition, not its parent
#   (3)  --at in a top-level function: chain of exactly 1
#   (4)  --at on a blank line INSIDE a struct: resolves to the struct (the enclosing scope is a fact,
#        not a refusal)
#   (5)  refusal: top-level blank line — "no indexed symbol spans", exit 1
#   (6)  refusal: line beyond EOF — names the file's real line count, exit 1
#   (7)  refusals: malformed specs (no colon / non-numeric / line 0) — the grammar sentence, exit 1
#   (8)  refusal: ambiguous file half — lists every matching indexed path, exit 1
#   (9)  refusal: two definitions sharing the seed line — names both, suggests file:line:name, exit 1
#   (10) @ in --callers: same caller row as the name-selector run
#   (11) @ in --expand: the resolved body is served
#   (12) @ in --edit-check: resolves to the definition at the seed
#   (13) @ in --slice: bare @F:L = inventory of that fn's locals; @F:L:VAR = the VAR slice
#   (14) @ refusal THROUGH a verb: the shared clause carries the at-diagnosis, exit 1
#   (15) determinism (x2, byte-identical bare --at)
#   (16) xmllint well-formedness (bare --at)
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/atcheck.sh   |   bash test/atcheck.sh path/to/ripwire

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/src" "$WORK/dup"

# C++ fixture — line numbers below are load-bearing (the arms address them):
#   L2  blank, top level            -> refusal (5)
#   L6  struct Frame                -> chain outer row (1)
#   L9  blank inside Frame          -> resolves to Frame (4)
#   L10 shift() signature           -> shift (2)
#   L12 inside shift()              -> chain Frame->shift (1), verb seeds (10..13)
#   L22 inside standalone()         -> chain of 1 (3)
#   L25 tiny1 and tiny2 share it    -> sibling refusal (9)
cat > "$WORK/src/geo.cpp" <<'EOF'
// geometry fixture

namespace geo
{

struct Frame
{
    int origin = 0;

    int shift( int d )
    {
        int moved = origin + d;
        moved = moved * 2;
        return moved;
    }
};

}   // namespace geo

int standalone( int a )
{
    return a + 1;
}

int tiny1(){ return 1; } int tiny2(){ return 2; }

int useAll()
{
    geo::Frame f;
    return f.shift( 2 ) + standalone( 3 ) + tiny1() + tiny2();
}
EOF

# same basename in a second dir — the ambiguity arm's fuel (8)
cat > "$WORK/dup/geo.cpp" <<'EOF'
int duplicated() { return 0; }
EOF

echo "atcheck: BIN=$BIN  (temp corpus $WORK)"

# ── (1) bare --at inside the method body: the chain, outermost first ────────────────────────────────
O1="$( "$BIN" "$WORK" --at=src/geo.cpp:12 --no-cache 2>/dev/null )"
printf '%s' "$O1" | grep -q '<at ' \
    && ok "(1) bare at: <at> root element emitted" \
    || { no "(1) bare at: no <at> root element"; printf '%s\n' "$O1" | head -c 300; }
printf '%s' "$O1" | grep -q 'p="src/geo.cpp"' \
    && ok "(1) bare at: p= carries the resolved root-relative path" \
    || no "(1) bare at: p= missing or not root-relative"
printf '%s' "$O1" | grep -q 'l="12"' \
    && ok "(1) bare at: l= echoes the seed line" \
    || no "(1) bare at: l= missing"
printf '%s' "$O1" | grep -q 'sym="shift"' \
    && ok "(1) bare at: sym= names the innermost enclosing definition" \
    || no "(1) bare at: sym= wrong or missing"
printf '%s' "$O1" | grep -q 'chain="2"' \
    && ok "(1) bare at: chain= counts both enclosing definitions" \
    || no "(1) bare at: chain= wrong (expected 2: Frame, shift)"
# outermost BEFORE innermost — Frame's row must precede shift's
printf '%s' "$O1" | tr '<' '\n' | grep -n 'n="Frame"\|n="shift"' | head -2 | paste -sd, - | grep -q 'Frame.*shift' \
    && ok "(1) bare at: chain rows are outermost->innermost (Frame before shift)" \
    || no "(1) bare at: chain row order wrong"
printf '%s' "$O1" | grep -q 'n="shift" t="method" l="10" el="15"' \
    && ok "(1) bare at: innermost row carries kind + start line + end line" \
    || { no "(1) bare at: shift row attrs wrong (expected t=method l=10 el=15)"; printf '%s\n' "$O1" | tr '<' '\n' | grep 'n="shift"'; }

# ── (2) the signature line resolves to that definition, not the parent ──────────────────────────────
O2="$( "$BIN" "$WORK" --at=src/geo.cpp:10 --no-cache 2>/dev/null )"
printf '%s' "$O2" | grep -q 'sym="shift"' \
    && ok "(2) signature line: resolves to shift itself" \
    || no "(2) signature line: did not resolve to shift"

# ── (3) top-level function: a chain of exactly one ──────────────────────────────────────────────────
O3="$( "$BIN" "$WORK" --at=src/geo.cpp:22 --no-cache 2>/dev/null )"
printf '%s' "$O3" | grep -q 'sym="standalone"' && printf '%s' "$O3" | grep -q 'chain="1"' \
    && ok "(3) top-level fn: sym=standalone, chain=1" \
    || no "(3) top-level fn: wrong sym/chain"

# ── (4) blank line INSIDE the struct: the enclosing scope is the answer, not a refusal ───────────────
O4="$( "$BIN" "$WORK" --at=src/geo.cpp:9 --no-cache 2>/dev/null )"
printf '%s' "$O4" | grep -q 'sym="Frame"' \
    && ok "(4) blank-in-struct: resolves to the enclosing struct" \
    || no "(4) blank-in-struct: did not resolve to Frame"

# ── (5) top-level blank line: refusal, exit 1 ──────────────────────────────────────────────────────
E5="$( "$BIN" "$WORK" --at=src/geo.cpp:2 --no-cache 2>&1 >/dev/null )"; R5=$?
[ "$R5" = 1 ] && printf '%s' "$E5" | grep -q 'no indexed symbol spans line 2' \
    && ok "(5) top-level blank: refused with the no-coverer sentence, exit 1" \
    || { no "(5) top-level blank: expected exit 1 + 'no indexed symbol spans line 2' (got exit $R5)"; printf '%s\n' "$E5"; }

# ── (6) line beyond EOF: refusal names the file's real length ───────────────────────────────────────
E6="$( "$BIN" "$WORK" --at=src/geo.cpp:999 --no-cache 2>&1 >/dev/null )"; R6=$?
[ "$R6" = 1 ] && printf '%s' "$E6" | grep -q 'has only' \
    && ok "(6) beyond EOF: refused, names the real line count, exit 1" \
    || { no "(6) beyond EOF: expected exit 1 + 'has only' (got exit $R6)"; printf '%s\n' "$E6"; }

# ── (7) malformed specs: the grammar sentence, all exit 1 ───────────────────────────────────────────
for BADSPEC in "src/geo.cpp" "src/geo.cpp:abc" "src/geo.cpp:0"; do
    E7="$( "$BIN" "$WORK" "--at=$BADSPEC" --no-cache 2>&1 >/dev/null )"; R7=$?
    [ "$R7" = 1 ] && printf '%s' "$E7" | grep -q 'FILE:LINE' \
        && ok "(7) malformed '$BADSPEC': refused with the FILE:LINE grammar, exit 1" \
        || { no "(7) malformed '$BADSPEC': expected exit 1 + grammar sentence (got exit $R7)"; printf '%s\n' "$E7"; }
done

# ── (8) ambiguous file half: every matching path is named ───────────────────────────────────────────
E8="$( "$BIN" "$WORK" --at=geo.cpp:1 --no-cache 2>&1 >/dev/null )"; R8=$?
[ "$R8" = 1 ] && printf '%s' "$E8" | grep -q 'src/geo.cpp' && printf '%s' "$E8" | grep -q 'dup/geo.cpp' \
    && ok "(8) ambiguous file: refused, both matching paths named, exit 1" \
    || { no "(8) ambiguous file: expected exit 1 naming both paths (got exit $R8)"; printf '%s\n' "$E8"; }

# ── (9) two definitions sharing the seed line: refused, both named, the qualified retry offered ─────
E9="$( "$BIN" "$WORK" --at=src/geo.cpp:25 --no-cache 2>&1 >/dev/null )"; R9=$?
[ "$R9" = 1 ] && printf '%s' "$E9" | grep -q 'tiny1' && printf '%s' "$E9" | grep -q 'tiny2' \
    && printf '%s' "$E9" | grep -q 'file:line:name' \
    && ok "(9) same-line siblings: refused, both named, file:line:name retry offered, exit 1" \
    || { no "(9) same-line siblings: expected exit 1 naming tiny1+tiny2 and the retry form (got exit $R9)"; printf '%s\n' "$E9"; }

# ── (10) @ in --callers: identical caller row to the name-selector run ──────────────────────────────
CAT="$( "$BIN" "$WORK" --callers=@src/geo.cpp:12 --no-cache 2>/dev/null )"
printf '%s' "$CAT" | grep -q 'n="useAll"' \
    && ok "(10) callers @seed: useAll caller row present" \
    || { no "(10) callers @seed: useAll row missing"; printf '%s\n' "$CAT" | head -c 300; }

# ── (11) @ in --expand: the body is served ──────────────────────────────────────────────────────────
XAT="$( "$BIN" "$WORK" --expand=@src/geo.cpp:12 --no-cache 2>/dev/null )"
printf '%s' "$XAT" | grep -q 'moved = moved \* 2' \
    && ok "(11) expand @seed: shift's body text served" \
    || no "(11) expand @seed: body text missing"

# ── (12) @ in --edit-check: resolves to the definition at the seed ──────────────────────────────────
ECAT="$( "$BIN" "$WORK" --edit-check=@src/geo.cpp:12 --no-cache 2>/dev/null )"
printf '%s' "$ECAT" | grep -q 'p="src/geo.cpp:10"' \
    && ok "(12) edit-check @seed: resolved to the definition at src/geo.cpp:10" \
    || { no "(12) edit-check @seed: wrong definition"; printf '%s\n' "$ECAT" | tail -c 300; }

# ── (13) @ in --slice: inventory bare, VAR slice with the :VAR tail ────────────────────────────────
SAT="$( "$BIN" "$WORK" --slice=@src/geo.cpp:12 --no-cache 2>/dev/null )"
printf '%s' "$SAT" | grep -q 'n="moved"' \
    && ok "(13) slice @seed: inventory lists the local 'moved'" \
    || no "(13) slice @seed: inventory missing 'moved'"
SVAT="$( "$BIN" "$WORK" --slice=@src/geo.cpp:12:moved --no-cache 2>/dev/null )"
printf '%s' "$SVAT" | grep -q 'v="moved"\|var="moved"' \
    && ok "(13) slice @seed:VAR: the VAR slice ran on 'moved'" \
    || { no "(13) slice @seed:VAR: no slice rows for 'moved'"; printf '%s\n' "$SVAT" | head -c 300; }

# ── (14) @ refusal THROUGH a verb: the shared clause carries the at-diagnosis ───────────────────────
E14="$( "$BIN" "$WORK" --callers=@src/geo.cpp:2 --no-cache 2>&1 >/dev/null )"; R14=$?
[ "$R14" = 1 ] && printf '%s' "$E14" | grep -q 'no indexed symbol spans line 2' \
    && ok "(14) verb @refusal: the at-diagnosis reaches the shared selector clause, exit 1" \
    || { no "(14) verb @refusal: expected exit 1 + the at-diagnosis (got exit $R14)"; printf '%s\n' "$E14"; }

# ── (15) determinism ────────────────────────────────────────────────────────────────────────────────
D1="$( "$BIN" "$WORK" --at=src/geo.cpp:12 --no-cache 2>/dev/null )"
D2="$( "$BIN" "$WORK" --at=src/geo.cpp:12 --no-cache 2>/dev/null )"
[ "$D1" = "$D2" ] && [ -n "$D1" ] \
    && ok "(15) determinism: two bare-at runs byte-identical" \
    || no "(15) determinism: runs differ or empty"

# ── (16) xmllint ────────────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$O1" | xmllint --noout - 2>/dev/null \
        && ok "(16) xmllint: bare-at output well-formed" \
        || no "(16) xmllint: bare-at output malformed"
else
    ok "(16) xmllint unavailable — skipped (well-formedness still pinned by the suite-wide gate)"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

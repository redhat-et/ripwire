#!/usr/bin/env bash
# degradedhintcheck.sh — the parse-health facts must reach the reader AT THE POINT OF FAILURE.
#
# The health pass (test/parsehealthcheck.sh) already computes per-file degraded-parse facts and
# --skipped discloses them — but nothing ROUTED a reader there from the interactions that actually go
# wrong in a degraded file. Measured live 2026-08-30 (the looksObjC misroute, pre-kParserVer-74):
# --skipped knew src/ingest_model.h was why="degraded-parse" err="190", while --edit-check answered a
# bare "symbol not found" for a symbol sitting in that file and --grep returned its hits with no in=
# — whose legend then CLAIMED "absent ⇒ no symbol encloses the hit", a statement that is unknowable
# over a shredded parse. The diagnosis took a --match='(ERROR) @e' sweep; these two hints make it one
# glance. Two routes, both joining ing.fileHealth (already computed, already cached — no new pass):
#
#   grep:     an <f> element whose file's parse is degraded carries parse_degraded="1", and the legend
#             says what that does to the in=-absent claim.
#   refusals: the shared selector not-found message (selectorrefuse.h) appends a clause when the
#             missing name occurs as a WHOLE WORD in a parse-degraded file's bytes — precise, so an
#             ordinary typo never triggers it (this repo carries 65 deliberately-degraded fixtures; a
#             blanket "there are degraded files" clause would fire on every misspelling).
#
# RED-FIRST: recorded 2026-08-30 against the pre-hint binary — arms (2)(3)(5) FAIL (no attribute, no
# legend entry, bare refusal), arms (1)(4)(6) already PASS (they pin the surfaces that must not move).
#
# Fixture (generated, mktemp): victim.cpp defines victimFn/callerFn, then an unclosed paren makes the
# tail an ERROR region; ghostFn sits INSIDE that region — textually present, never extracted (the
# presence guard asserts both). clean.cpp is the healthy control.
#
# Usage:  test/degradedhintcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/degradedhintcheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "degradedhintcheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/corpus"

cat > "$TMP/corpus/victim.cpp" <<'EOF'
int victimFn( int x ) { return x + 1; }
int callerFn( int x ) { return victimFn( x ); }
int brokenFn( int x ) { return ( x +
EOF
printf 'int ghostFn( int x ) { return x + 3; }\n' >> "$TMP/corpus/victim.cpp"
cat > "$TMP/corpus/clean.cpp" <<'EOF'
int cleanFn( int x ) { return x + 4; }
EOF

# ── (1) presence guards: victim.cpp IS degraded, ghostFn is text-present but NOT extracted ──────────
SKIP="$( "$BIN" "$TMP/corpus" --no-cache --skipped 2>/dev/null )"
printf '%s' "$SKIP" | grep -q 'p="victim.cpp" why="degraded-parse"' \
    && ok "(1) victim.cpp flagged degraded-parse by --skipped (precondition)" \
    || { no "(1) fixture no longer parses as degraded — every later arm is vacuous"; printf '%s\n' "$SKIP" | tail -1; }
MAP="$( "$BIN" "$TMP/corpus" --no-cache 2>/dev/null )"
if printf '%s' "$MAP" | grep -q 'n="ghostFn"'; then
    no "(1) ghostFn got extracted — the fixture's ERROR region no longer hides it, rebuild the fixture"
else
    ok "(1) ghostFn is textually present yet unextracted (the gap the hint discloses)"
fi

# ── (2) grep: the degraded file's <f> row carries parse_degraded="1" ────────────────────────────────
GOUT="$( "$BIN" "$TMP/corpus" --no-cache --grep="return x + 1" 2>/dev/null )"
printf '%s' "$GOUT" | grep -q '<f p="victim.cpp" parse_degraded="1"' \
    && ok "(2) grep marks victim.cpp's file row parse_degraded=\"1\"" \
    || { no "(2) grep's file row carries no parse_degraded attribute"; printf '%s\n' "$GOUT" | tr '<' '\n<' | grep '^f p=' | head -2; }

# ── (3) the attribute is defined in grep's legend ───────────────────────────────────────────────────
printf '%s' "$GOUT" | grep -oE '<!--.*-->' | grep -q 'parse_degraded' \
    && ok "(3) grep's legend defines parse_degraded" \
    || no "(3) parse_degraded is emitted but never defined in the legend"

# ── (4) precision: a healthy file's row carries NO parse_degraded attribute ─────────────────────────
COUT="$( "$BIN" "$TMP/corpus" --no-cache --grep="return x + 4" 2>/dev/null )"
if printf '%s' "$COUT" | grep -q '<f p="clean.cpp"' && ! printf '%s' "$COUT" | grep -q 'clean.cpp" parse_degraded'; then
    ok "(4) clean.cpp's row is unmarked — the flag means degraded, not merely scanned"
else
    no "(4) the healthy control row moved"; printf '%s\n' "$COUT" | tr '<' '\n<' | grep '^f p=' | head -2
fi

# ── (5) refusal hint: a name that exists only as TEXT in the degraded region names the file ─────────
ROUT="$( "$BIN" "$TMP/corpus" --no-cache --callers=ghostFn 2>&1 >/dev/null )"
if printf '%s' "$ROUT" | grep -q 'victim.cpp' && printf '%s' "$ROUT" | grep -qi 'degraded'; then
    ok "(5) --callers=ghostFn's refusal names victim.cpp's degraded parse"
else
    no "(5) the refusal is still blind to the degraded file that contains the name"; printf '%s\n' "$ROUT" | tail -2
fi

# ── (6) precision: a name found NOWHERE stays a plain refusal ───────────────────────────────────────
NOUT="$( "$BIN" "$TMP/corpus" --no-cache --callers=zzzNowhereFn 2>&1 >/dev/null )"
if printf '%s' "$NOUT" | grep -qi 'degraded'; then
    no "(6) a nowhere-name refusal mentions degraded parses — the hint fires on ordinary typos"
else
    ok "(6) a nowhere-name refusal stays plain (the hint is precise, not blanket)"
fi

# ── (7) determinism with the new attribute ──────────────────────────────────────────────────────────
"$BIN" "$TMP/corpus" --no-cache --grep="return x + 1" >"$TMP/g1" 2>/dev/null
"$BIN" "$TMP/corpus" --no-cache --grep="return x + 1" >"$TMP/g2" 2>/dev/null
diff -q "$TMP/g1" "$TMP/g2" >/dev/null && ok "(7) grep output deterministic" || no "(7) grep output differs run-to-run"

exit $fail

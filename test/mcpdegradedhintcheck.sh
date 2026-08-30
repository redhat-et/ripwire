#!/usr/bin/env bash
# mcpdegradedhintcheck.sh — degradedhintcheck's MCP sibling: the parse-health facts must reach an
# MCP-ONLY reader at the point of failure too.
#
# test/degradedhintcheck.sh proved the CLI selector refusals route a not-found name to the degraded
# file that textually contains it (selectorrefuse.h degradedParseClause). The MCP refusal surface
# (mcprefusal.h) has its OWN vocabulary and did not gain the clause — so an MCP find_symbol /
# find_referencing_symbols / edit_check miss over a shredded file still answered a bare
# "symbol not found", on the one surface whose reader has no --skipped habit to fall back on. The
# port shares the scan (src/degradedscan.h degradedTextHit — the same whole-word budget-bounded byte
# scan the CLI clause reads) and words it in MCP vocabulary inside mcprefuse::notFound, so every
# verb on BOTH dispatch arms (live tools/call and batch sub-queries) inherits it from the one seam.
#
# RED-FIRST: recorded 2026-08-30 against the pre-port binary (base 871d724, CLI clause in, MCP arm
# not) — arms (2)(3)(4)(5) FAIL (bare "symbol not found" on all four), arms (1)(6)(7) already PASS
# (fixture guards, precision, determinism pin the surfaces that must not move).
#
# Fixture: identical to degradedhintcheck.sh — victim.cpp's unclosed paren makes its tail an ERROR
# region and ghostFn sits INSIDE it (textually present, never extracted); clean.cpp is the healthy
# control. No git required: edit_check on a non-git tree still routes a miss through notFound.
#
# Usage:  test/mcpdegradedhintcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/mcpdegradedhintcheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "mcpdegradedhintcheck: BIN=$BIN"
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

# one tools/call request per line, a fresh server per call (state-free, like the CLI gate's runs)
mcp_verb() {   # $1=verb  $2=extra argument JSON fields (already comma-led or empty)
    printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"%s","arguments":{"path":"%s"%s}}}\n' \
        "$1" "$TMP/corpus" "$2" | "$BIN" --mcp 2>/dev/null
}

# ── (1) presence guards: the fixture parses degraded, and ghostFn is text-present yet unextracted ───
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

# ── (2) live arm, find_symbol: the -32602 refusal names the degraded file ───────────────────────────
FS="$( mcp_verb find_symbol ',"symbol":"ghostFn"' )"
if printf '%s' "$FS" | grep -q 'victim.cpp' && printf '%s' "$FS" | grep -qi 'degraded'; then
    ok "(2) find_symbol ghostFn's refusal names victim.cpp's degraded parse"
else
    no "(2) find_symbol's refusal is still blind to the degraded file that contains the name"; printf '%s\n' "$FS" | tail -1
fi

# ── (3) live arm, find_referencing_symbols (the MCP spelling of --callers) ──────────────────────────
FR="$( mcp_verb find_referencing_symbols ',"symbol":"ghostFn"' )"
if printf '%s' "$FR" | grep -q 'victim.cpp' && printf '%s' "$FR" | grep -qi 'degraded'; then
    ok "(3) find_referencing_symbols ghostFn's refusal names the degraded file"
else
    no "(3) find_referencing_symbols' refusal is still blind"; printf '%s\n' "$FR" | tail -1
fi

# ── (4) live arm, edit_check: the just-edited-symbol reflex gets routed too ─────────────────────────
EC="$( mcp_verb edit_check ',"symbol":"ghostFn"' )"
if printf '%s' "$EC" | grep -q 'victim.cpp' && printf '%s' "$EC" | grep -qi 'degraded'; then
    ok "(4) edit_check ghostFn's refusal names the degraded file"
else
    no "(4) edit_check's refusal is still blind"; printf '%s\n' "$EC" | tail -1
fi

# ── (5) batch arm: the sub-query err= carries the same routing (one seam, both arms) ────────────────
BA="$( mcp_verb batch ',"queries":[{"verb":"find_symbol","symbol":"ghostFn"}]' )"
if printf '%s' "$BA" | grep -q 'victim.cpp' && printf '%s' "$BA" | grep -qi 'degraded'; then
    ok "(5) the batch arm's find_symbol err= carries the degraded routing"
else
    no "(5) the batch arm still serves the chopped refusal — the two arms disagree"; printf '%s\n' "$BA" | tail -1
fi

# ── (6) precision: a name found NOWHERE stays a plain refusal on this surface too ───────────────────
NW="$( mcp_verb find_symbol ',"symbol":"zzzNowhereFn"' )"
if printf '%s' "$NW" | grep -qi 'degraded'; then
    no "(6) a nowhere-name refusal mentions degraded parses — the hint fires on ordinary typos"
else
    ok "(6) a nowhere-name refusal stays plain (the hint is precise, not blanket)"
fi

# ── (7) determinism: the enriched refusal is byte-identical across two fresh servers ────────────────
mcp_verb find_symbol ',"symbol":"ghostFn"' > "$TMP/r1"
mcp_verb find_symbol ',"symbol":"ghostFn"' > "$TMP/r2"
diff -q "$TMP/r1" "$TMP/r2" >/dev/null && ok "(7) refusal deterministic across runs" || no "(7) refusal differs run-to-run"

exit $fail

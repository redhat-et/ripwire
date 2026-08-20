#!/usr/bin/env bash
# forrootlegendcheck.sh — gate for W3-S item 5: --for's first screen must DEFINE root= when it emits it,
# on BOTH dialects (CLI and MCP), without busting the --token-budget=800 ceiling fornotesbudgetcheck.sh
# already pins.
#
# W2-E gave --for (and 29 other verbs) a root= attribute on <ctx> but no legend clause explaining it —
# "an attribute the document never explains", the mirror-image of the honesty contract ("a zero means
# none found, never none exists"). Eighteen OTHER verbs closed this via the shared rw::kRootRelPathsLegend
# (graphlegend.h); --for could not adopt it verbatim (159 B pushed a real --token-budget=800 fixture from
# est_tokens=799 to 811, red fornotesbudgetcheck.sh — a real "a disclosure has BYTES" trap). The fix is a
# shorter, --for-specific spelling (rw::kForRootRelPathsLegendShort, 126 B) shared by both dialects.
#
# Usage:
#   test/forrootlegendcheck.sh                      # uses build/ripwire
#   test/forrootlegendcheck.sh asan/ripwire
#   RIPWIRE_BIN=build_base/ripwire test/forrootlegendcheck.sh   # red-first: arms 1/2/4 MUST fail here —
#     a pre-fix binary emits root= on --for's <ctx> with no legend defining it, in EITHER dialect.
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# DO NOT edit regression.sh — this is a standalone gate invoked from there.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "forrootlegendcheck: no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "forrootlegendcheck: python3 is required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "forrootlegendcheck: xmllint is required"; exit 2; }
echo "forrootlegendcheck: BIN=$BIN"

CLAUSE_SNIPPET='root= is the crawl root; p= below is RELATIVE to it'

# ── arm 1: CLI --for on a single-root corpus -- root= present AND defined on the first screen ─────────
OUT1="$( "$BIN" "$ROOT" --for="rank symbols by pagerank" --no-cache 2>/dev/null )"
[ -n "$OUT1" ] || { echo "forrootlegendcheck: CLI --for produced no output"; exit 2; }
if printf '%s' "$OUT1" | grep -qE '<ctx [^>]*root="[^"]*"'; then
    ok "arm1: CLI --for's <ctx> carries root="
else
    no "arm1: CLI --for's <ctx> carries no root= at all (fixture assumption broke — re-anchor this arm)"
fi
if printf '%s' "$OUT1" | grep -qF "$CLAUSE_SNIPPET"; then
    ok "arm1: CLI --for's first screen DEFINES root= (the short legend clause is present)"
else
    no "arm1: CLI --for's <ctx> carries root= but nothing on the first screen defines it"
fi

# ── arm 2: the clause must not bust the --token-budget=800 ceiling fornotesbudgetcheck.sh already pins ─
# (this is the exact regression the W3-S commit message records: pasting the FULL 159 B
# kRootRelPathsLegend verbatim took a real fixture from est_tokens=799 to 811 at this budget.) Uses a
# SMALL synthetic fixture, same spirit as fornotesbudgetcheck.sh's own corpus: a real query against this
# whole repo legitimately trips over_ceiling at 800 tokens regardless of this clause (too much content),
# which would make this arm meaningless — the point here is specifically the clause's OWN fixed cost.
mkdir -p "$TMP/tiny/src"
for i in 0 1 2; do
  for j in 0 1 2 3; do
    printf 'def widgetRoutine%d_%d( alpha, beta ):\n    """Route stage %d.%d."""\n    return alpha + beta\n\n\n' \
      "$i" "$j" "$i" "$j" >> "$TMP/tiny/src/mod$i.py"
  done
done
( cd "$TMP/tiny" && git init -q . && git add -A && git -c user.email=gate@example.invalid -c user.name=gate commit -qm init ) \
  || { echo "forrootlegendcheck: could not create the tiny corpus git repo"; exit 2; }
OUT2="$( "$BIN" "$TMP/tiny" --for="widget routine dispatcher" --token-budget=800 --no-cache 2>/dev/null )"
EST2="$( printf '%s' "$OUT2" | grep -o 'est_tokens="[0-9]*"' | head -1 | tr -dc '0-9' )"
if [ -n "$EST2" ] && [ "$EST2" -le 800 ]; then
    ok "arm2: --token-budget=800 fits the ceiling (est_tokens=$EST2)"
else
    no "arm2: --token-budget=800 est_tokens=${EST2:-unreadable} exceeds the ceiling — the legend clause is too expensive"
fi
if printf '%s' "$OUT2" | grep -qF "$CLAUSE_SNIPPET"; then
    ok "arm2: the clause SURVIVES at --token-budget=800 (not dropped by the ceiling ladder)"
else
    no "arm2: the clause is missing at --token-budget=800 — it was silently dropped instead of fitting"
fi
printf '%s' "$OUT2" | xmllint --noout - 2>/dev/null && ok "arm2: tight-budget output is well-formed (G4)" || no "arm2: tight-budget output fails xmllint"

# ── arm 3: multi-root -- root= (and the clause) must be ABSENT, never a false claim about a root that
#    does not exist (single-root only, per the clause's own text and every other verb's rootArg contract)
mkdir -p "$TMP/mr/a" "$TMP/mr/b"
printf 'int mrFnA(){ return 1; }\n' > "$TMP/mr/a/a.cpp"
printf 'int mrFnB(){ return 2; }\n' > "$TMP/mr/b/b.cpp"
OUT3="$( "$BIN" "$TMP/mr/a" "$TMP/mr/b" --for="mrFnA mrFnB" --no-cache 2>/dev/null )"
[ -n "$OUT3" ] || { echo "forrootlegendcheck: multi-root CLI --for produced no output"; exit 2; }
if printf '%s' "$OUT3" | grep -qE '<ctx [^>]*root="'; then
    no "arm3: multi-root <ctx> carries root= (should be absent -- single-root only)"
else
    ok "arm3: multi-root <ctx> carries no root= (correct)"
fi
if printf '%s' "$OUT3" | grep -qF "$CLAUSE_SNIPPET"; then
    no "arm3: multi-root output carries the root= clause with no root= attribute to define (a false claim)"
else
    ok "arm3: multi-root output carries no root= clause either (no attribute, no false claim about one)"
fi

# ── arm 4: the MCP `for` twin carries the SAME clause -- byte-consistency between dialects ─────────────
python3 - "$BIN" "$ROOT" "$CLAUSE_SNIPPET" <<'PY_EOF' \
    && ok "arm4: MCP \`for\` twin's <ctx> defines root= with the same clause the CLI carries" \
    || no "arm4: MCP \`for\` twin is missing the root= legend clause (dialects have drifted)"
import json, sys, subprocess
BIN, CORPUS, SNIPPET = sys.argv[1], sys.argv[2], sys.argv[3]
reqs = [
    { "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {} },
    { "jsonrpc": "2.0", "id": 2, "method": "tools/call",
      "params": { "name": "for", "arguments": { "task": "rank symbols by pagerank" } } },
]
blob = ''.join( json.dumps( r ) + '\n' for r in reqs ).encode( 'utf-8' )
proc = subprocess.run( [ BIN, '--mcp', CORPUS ], input=blob, capture_output=True, timeout=30 )
body = ''
for line in proc.stdout.decode( 'utf-8', 'replace' ).splitlines():
    line = line.strip()
    if not line.startswith( '{' ):
        continue
    try:
        reply = json.loads( line )
    except Exception:
        continue
    if reply.get( 'id' ) == 2:
        try:
            body = reply['result']['content'][0]['text']
        except Exception:
            body = ''
        break
sys.exit( 0 if ( body and SNIPPET in body and 'root="' in body ) else 1 )
PY_EOF

# ── arm 5: determinism ───────────────────────────────────────────────────────────────────────────────
OUT1B="$( "$BIN" "$ROOT" --for="rank symbols by pagerank" --no-cache 2>/dev/null )"
[ "$OUT1" = "$OUT1B" ] && ok "arm5: CLI --for output is byte-identical run-to-run" || no "arm5: CLI --for output is not deterministic"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES PRESENT"; exit 1

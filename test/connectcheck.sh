#!/usr/bin/env bash
# connectcheck.sh — gate for the --connect=A,B,C CLI verb + the `connect` MCP verb
# (; the core algorithm is gated separately by connectcorecheck.sh).
#
# Scratch corpus (OUTSIDE test/, so test/golden.xml is untouched): orch() calls a() and b();
# b() calls c(); island() calls nothing and is uncalled. Assertions (design §7):
#   1  connected triple --connect=a,b,c → ONE <g>; nodes {a,b,c,orch}; orch is the Steiner <s> WITH sig=;
#      edges exactly orch→a, orch→b, b→c
#   2  direction correctness: orch→a reported f="orch" t="a" even though the a-leg walked it caller-ward
#   3  unconnected: island lands in <unconnected> (never dropped, never an empty <connect/>)
#   4  determinism: 3 runs byte-identical; warm == --no-cache cold
#   5  G4: xmllint --noout clean
#   6  golden-neutrality: default map on test/fixture byte-identical to test/golden.xml
#   7  radius bound: a dist-8 chain splits at the default R=6, connects at --connect-radius=8
#   8  MUTATION self-tests: a swapped-f/t output MUST trip the direction assertion; an output with the
#      <unconnected> block removed MUST trip the unconnected assertion (the gate can catch both bugs)
#   9  MCP verb smoke: tools/list carries `connect`; tools/call connect {path,symbols} returns the same
#      <connect> payload, deterministic across two calls
#
# Usage:  test/connectcheck.sh              # uses build/ripwire
#         RIPWIRE_BIN=asan/ripwire test/connectcheck.sh
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"
echo "connectcheck: BIN=$BIN"

# ── scratch corpus: shared-caller triple + island ──────────────────────────────────────────────────────
SC="$TMP/proj"; mkdir -p "$SC"
cat >"$SC/lib.cpp" <<'CPP'
// scratch corpus for --connect: orch is the shared caller joining a and b; b feeds c; island is alone.
void a() {}
void c() {}
void b() { c(); }
void orch() { a(); b(); }
void island() {}
CPP

# ── 1) connected triple: one <g>, Steiner node orch (as <s> with sig=), the exact 3 edges ──────────────
OUT="$( "$BIN" "$SC" --no-cache --connect=a,b,c 2>/dev/null )"
printf '%s' "$OUT" | grep -q '<connect '            && ok "--connect emits a <connect> root"          || no "no <connect> root: $( printf '%s' "$OUT" | head -c 200 )"
[ "$( printf '%s' "$OUT" | grep -o '<g ' | wc -l | tr -d ' ' )" = "1" ] \
    && ok "connected triple forms exactly ONE group" || no "expected exactly one <g>: $OUT"
printf '%s' "$OUT" | grep -q '<s n="orch"[^>]* sig="' \
    && ok "orch is the Steiner <s> node and carries sig=" || no "orch missing as <s> with sig=: $OUT"
for e in '<e f="orch" t="a"/>' '<e f="orch" t="b"/>' '<e f="b" t="c"/>'; do
    printf '%s' "$OUT" | grep -qF "$e" && ok "edge present: $e" || no "edge missing: $e in $OUT"
done
[ "$( printf '%s' "$OUT" | grep -o '<e f="' | wc -l | tr -d ' ' )" = "3" ] \
    && ok "exactly 3 edges (no spurious edges)" || no "edge count != 3: $OUT"
for t in a b c; do
    printf '%s' "$OUT" | grep -q "<t n=\"$t\"" && ok "terminal <t n=\"$t\"> present" || no "terminal $t missing: $OUT"
done
printf '%s' "$OUT" | grep -q 'est_tokens="' && ok "root carries est_tokens=" || no "est_tokens missing: $OUT"

# ── 2) direction correctness is covered by the exact-attribute greps above (f=\"orch\" t=\"a\") ────────

# ── 3) unconnected island: always present, never an empty <connect/> ───────────────────────────────────
OUT2="$( "$BIN" "$SC" --no-cache --connect=a,b,island 2>/dev/null )"
printf '%s' "$OUT2" | grep -q '<unconnected radius="[0-9]*"><t n="island"' \
    && ok "island lands in <unconnected> (with the radius that was tried)" || no "island not in <unconnected>: $OUT2"
printf '%s' "$OUT2" | grep -q '<g ' && ok "the a,b pair still forms a connected <g> beside the island" || no "a,b group missing: $OUT2"
# a fully-disconnected pair: BOTH terminals appear, in <unconnected>, and the output is never empty
OUT3="$( "$BIN" "$SC" --no-cache --connect=a,island 2>/dev/null )"
printf '%s' "$OUT3" | grep -q '<t n="a"' && printf '%s' "$OUT3" | grep -q '<t n="island"' \
    && ok "a,island: both terminals present (honest partitions, no silent empty)" || no "a,island lost a terminal: $OUT3"

# ── 4) determinism: 3 cold runs byte-identical; warm == cold ───────────────────────────────────────────
"$BIN" "$SC" --no-cache --connect=a,b,c >"$TMP/d1" 2>/dev/null
"$BIN" "$SC" --no-cache --connect=a,b,c >"$TMP/d2" 2>/dev/null
"$BIN" "$SC" --no-cache --connect=a,b,c >"$TMP/d3" 2>/dev/null
diff -q "$TMP/d1" "$TMP/d2" >/dev/null && diff -q "$TMP/d2" "$TMP/d3" >/dev/null \
    && ok "determinism: 3 runs byte-identical" || no "non-deterministic --connect output"
"$BIN" "$SC" --connect=a,b,c >"$TMP/w1" 2>/dev/null     # first cached run
"$BIN" "$SC" --connect=a,b,c >"$TMP/w2" 2>/dev/null     # warm run
diff -q "$TMP/d1" "$TMP/w2" >/dev/null && ok "warm == cold (cache-neutral)" || no "warm run differs from cold"

# ── 5) G4: well-formed XML ──────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$OUT2" | xmllint --noout - 2>/dev/null && ok "xml well-formed (xmllint)" || no "xml malformed"
else
    ok "xmllint absent — skipped"
fi

# ── 6) golden-neutrality: the default map is untouched ─────────────────────────────────────────────────
if [ -f "$ROOT/test/golden.xml" ]; then
    "$BIN" test/fixture --no-cache 2>/dev/null | diff -q - "$ROOT/test/golden.xml" >/dev/null \
        && ok "golden-neutral: default map byte-identical to test/golden.xml" \
        || no "default map drifted from golden.xml (--connect leaked into the default run)"
else
    ok "golden.xml absent — skipped"
fi

# ── 7) radius bound: dist-8 chain splits at default R=6, connects at --connect-radius=8 ────────────────
CH="$TMP/chain"; mkdir -p "$CH"
{
    echo "void n8() {}"
    for i in 7 6 5 4 3 2 1 0; do echo "void n$i() { n$(( i + 1 ))(); }"; done
} >"$CH/chain.cpp"
R6="$( "$BIN" "$CH" --no-cache --connect=n0,n8 2>/dev/null )"
printf '%s' "$R6" | grep -q '<unconnected' && ! printf '%s' "$R6" | grep -q '<g ' \
    && ok "dist-8 pair splits at the default radius 6" || no "radius bound not honored at R=6: $R6"
R8="$( "$BIN" "$CH" --no-cache --connect=n0,n8 --connect-radius=8 2>/dev/null )"
printf '%s' "$R8" | grep -q '<g ' && printf '%s' "$R8" | grep -q '<s n="n4"' \
    && ok "the pair connects at --connect-radius=8 (bound is real, not decorative)" || no "did not connect at R=8: $R8"

# ── degrade: unresolvable symbol → did-you-mean on stderr, exit 1 ───────────────────────────────────────
ERR="$( "$BIN" "$SC" --no-cache --connect=a,orcj 2>&1 >/dev/null )"; RC=$?
[ "$RC" -ne 0 ] && printf '%s' "$ERR" | grep -qi 'not found' \
    && ok "unresolvable terminal → hard error (exit $RC)" || no "bad terminal did not fail cleanly: rc=$RC err=$ERR"
printf '%s' "$ERR" | grep -q 'orch' && ok "did-you-mean suggests 'orch' for 'orcj'" || no "no did-you-mean suggestion: $ERR"
# terminal-count usage errors: 1 symbol / >16 symbols
"$BIN" "$SC" --no-cache --connect=a >/dev/null 2>&1 && no "single terminal accepted (usage error expected)" || ok "single terminal rejected (needs 2..16)"
MANY="a,b,c,orch,island,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12"
"$BIN" "$SC" --no-cache --connect="$MANY" >/dev/null 2>&1 && no ">16 terminals accepted (usage error expected)" || ok ">16 terminals rejected"

# ── 8) MUTATION self-tests: the two most plausible bugs MUST trip their assertions ─────────────────────
# (a) swapped edge direction: transform the good output as the bug would emit it; the exact-attribute grep must FAIL on it.
MUT_DIR="$( printf '%s' "$OUT" | sed 's/<e f="\([^"]*\)" t="\([^"]*\)"\/>/<e f="\2" t="\1"\/>/g' )"
if printf '%s' "$MUT_DIR" | grep -qF '<e f="orch" t="a"/>'; then
    no "mutation self-test (direction): swapped f/t output still passes the direction grep — assertion is decoration"
else
    ok "mutation self-test (direction): swapped f/t output correctly FAILS the direction assertion"
fi
# (b) dropped <unconnected> handling: strip the block; the unconnected assertion must FAIL on it.
MUT_UNC="$( printf '%s' "$OUT2" | sed 's/<unconnected[^>]*>.*<\/unconnected>//g' )"
if printf '%s' "$MUT_UNC" | grep -q '<unconnected radius="[0-9]*"><t n="island"'; then
    no "mutation self-test (unconnected): stripped output still passes — assertion is decoration"
else
    ok "mutation self-test (unconnected): stripped <unconnected> correctly FAILS the assertion"
fi

# ── 9) MCP verb smoke (the mcpverbscheck.sh server-harness pattern) ────────────────────────────────────
if command -v python3 >/dev/null 2>&1; then
    mcp_call() { printf '%s\n' "$@" | "$BIN" --mcp 2>/dev/null; }
    LIST_OUT="$( mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
                          '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | tail -1 )"
    printf '%s' "$LIST_OUT" | python3 -c '
import sys, json
r = json.load(sys.stdin)
names = [t["name"] for t in r["result"]["tools"]]
sys.exit(0 if "connect" in names else 1)
' && ok "tools/list carries the connect verb" || no "connect missing from tools/list"

    CMSG='{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"connect","arguments":{"path":"'"$SC"'","symbols":["a","b","c"]}}}'
    mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$CMSG" >"$TMP/m1"
    mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$CMSG" >"$TMP/m2"
    INNER="$( tail -1 "$TMP/m1" | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__:" + json.dumps(r["error"]) if "error" in r else r["result"]["content"][0]["text"])
' )"
    case "$INNER" in
        __ERROR__*) no "connect verb returned error: ${INNER#__ERROR__:}";;
        *'<connect '*) ok "connect verb returns a <connect> payload";;
        *) no "connect verb payload malformed: $( printf '%s' "$INNER" | head -c 200 )";;
    esac
    printf '%s' "$INNER" | grep -q '<s n="orch"' && ok "MCP payload carries the orch Steiner node" || no "MCP payload missing orch: $INNER"
    diff -q "$TMP/m1" "$TMP/m2" >/dev/null && ok "connect verb deterministic across two MCP calls" || no "connect verb non-deterministic"
    # comma-string symbols form + radius arg accepted
    CMSG2='{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"connect","arguments":{"path":"'"$SC"'","symbols":"a,b","radius":3}}}'
    INNER2="$( mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$CMSG2" | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__" if "error" in r else r["result"]["content"][0]["text"])
' )"
    printf '%s' "$INNER2" | grep -q 'radius="3"' && ok "comma-string symbols + radius arg honored" || no "comma-string/radius form failed: $INNER2"
else
    ok "python3 absent — MCP smoke skipped"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"

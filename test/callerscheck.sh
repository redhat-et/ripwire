#!/usr/bin/env bash
# callerscheck.sh — RANKING-CORE gate for --callers=SYM (inverse call direction: 1-hop in-edges). Zero
# prior coverage before this gate. Reuses test/queryfix (no new fixture — its call graph is already
# hand-verified by querycheck.sh):
#
#   chain.cpp:  d1 -> d2 -> d3 -> d4                     (linear chain)
#   util.cpp:   hot() called by BOTH caller_a() and caller_b()  (the known unambiguous multi-caller edge)
#               rec()  is SELF-recursive and has NO external callers
#
# Investigated first, not assumed:  §"drop self-loops (src == dst) — in the Google matrix they act
# as rank sinks" 130) — buildGraph's comment confirms self/unresolved/file-scope refs are DROPPED
# by design (src/graph.h ~ buildGraph). Verified directly: even a plain `if(n>0) return f(n-1);`
# self-recursive call produces ZERO edges in the call graph (edges= count in the default map). So rec()
# correctly has --callers count=0 — this is intentional PageRank hygiene, NOT a caller-resolution bug, and
# is exactly why rec() is the fixture's "no callers" case rather than a false negative to chase.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/callerscheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/queryfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no test/queryfix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "callerscheck: BIN=$BIN  CORPUS=test/queryfix"

c(){ perl -e 'alarm 15; exec @ARGV' "$BIN" "$FIX" --callers="$1" --no-cache 2>/dev/null; }
ec(){ perl -e 'alarm 8; exec @ARGV' "$BIN" "$FIX" --callers="$1" --no-cache >/dev/null 2>&1; echo $?; }
cnt(){ printf '%s' "$1" | grep -oE 'count="[0-9]+"' | grep -oE '[0-9]+'; }

# ── #1: --callers=hot lists exactly the 2 known callers, with correct p="....file:line" (R-E, 2026-08-17
#    harvest: --callers is now root-relative, so a single-root run's p= never carries the crawl root's OWN
#    directory name at all — "queryfix/src/..." became bare "src/..." — match the root-relative spelling
#    directly rather than a "queryfix/" suffix that used to tolerate an absolute-or-./-relative FIX path) ──
OUT_HOT="$( c hot )"
{ [ "$( cnt "$OUT_HOT" )" = 2 ] \
    && printf '%s' "$OUT_HOT" | grep -qE '<s t="fn" n="caller_a" p="src/util\.cpp:3"/>' \
    && printf '%s' "$OUT_HOT" | grep -qE '<s t="fn" n="caller_b" p="src/util\.cpp:4"/>'; } \
    && ok "--callers=hot: exactly caller_a (util.cpp:3) + caller_b (util.cpp:4), count=2" \
    || no "--callers=hot: wrong callers/lines — got: $OUT_HOT"

# ── #2: --callers=d3 lists exactly its one known caller (d2), correct file:line ─────────────────────────
OUT_D3="$( c d3 )"
{ [ "$( cnt "$OUT_D3" )" = 1 ] && printf '%s' "$OUT_D3" | grep -qE '<s t="fn" n="d2" p="src/chain\.cpp:3"/>'; } \
    && ok "--callers=d3: exactly d2 (chain.cpp:3), count=1" \
    || no "--callers=d3: wrong caller/line — got: $OUT_D3"

# ── #3: --callers of a never-called symbol → empty/zero result, no crash. Two witnesses:
#    d1 (head of the chain, nothing calls it) and rec (self-recursive only; self-loops are DROPPED by
#    design — see header note — so it also has count=0, not a caller-resolution miss). ──────────────────
OUT_D1="$( c d1 )"
if [ "$( cnt "$OUT_D1" )" = 0 ]; then ok "--callers=d1: count=0 (head of chain, never called)"; else no "--callers=d1 should be count=0, got: $OUT_D1"; fi
OUT_REC="$( c rec )"
if [ "$( cnt "$OUT_REC" )" = 0 ]; then ok "--callers=rec: count=0 (self-recursive only; self-loops dropped by design)"; else no "--callers=rec should be count=0, got: $OUT_REC"; fi
if [ "$( ec d1 )" = 0 ]; then ok "--callers=d1 exits 0 (empty result is not an error)"; else no "--callers=d1 should exit 0"; fi

# ── #4: --callers of a nonexistent symbol exits cleanly (non-zero) with a clear message on stderr ───────
BOGUS_MSG="$( "$BIN" "$FIX" --callers=totally_bogus_symbol_zzz --no-cache 2>&1 1>/dev/null )"
BOGUS_EC="$( ec totally_bogus_symbol_zzz )"
{ [ "$BOGUS_EC" != 0 ] && printf '%s' "$BOGUS_MSG" | grep -qi "not found"; } \
    && ok "--callers of a nonexistent symbol exits non-zero ($BOGUS_EC) with a 'not found' message" \
    || no "--callers of nonexistent symbol: expected non-zero exit + 'not found' message, got exit=$BOGUS_EC msg='$BOGUS_MSG'"

# ── #5: determinism — twice, byte-identical ──────────────────────────────────────────────────────────
A="$( c hot )"; B="$( c hot )"
if [ "$A" = "$B" ]; then ok "determinism: --callers=hot byte-identical run-to-run"; else no "non-deterministic --callers output"; fi

# ── xml well-formed ──────────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    if c hot | xmllint --noout - 2>/dev/null; then ok "xml well-formed"; else no "xml malformed"; fi
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

# §P10.6: --callers/--callees silently unioned overloads — the only symbol verbs with no defs=. Now the
# root carries defs= (resolved definitions the name matched) and it must AGREE with --uses's defs=.
cdefs="$( "$BIN" "$ROOT" --callers=empty 2>/dev/null | grep -oE 'defs="[0-9]+"' | head -1 )"
udefs="$( "$BIN" "$ROOT" --uses=empty    2>/dev/null | grep -oE 'defs="[0-9]+"' | head -1 )"
if [ -n "$cdefs" ] && [ "$cdefs" = "$udefs" ]; then
    ok "P10.6: --callers defs= present and agrees with --uses ($cdefs)"
else
    no "P10.6: --callers defs= '$cdefs' missing or disagrees with --uses '$udefs'"
fi
# L1 (2026-09-19): the CLI default is the compact posture, whose root leads with schema=; this arm reads the
# full-posture `<callees of= defs=` root shape, so it asks for --legend=full (rows identical across postures).
if "$BIN" "$ROOT" --callees=empty --legend=full 2>/dev/null | grep -qE '<callees of="empty" defs="[0-9]+"'; then ok "P10.6: --callees carries defs= (a count=0 is now a measurement over N known defs)"; else no "P10.6: --callees root missing defs="; fi

# ── X: cross_kind= — a bare name whose definitions are of different KINDS (comparison table hono-07) ────────────────
# `getPath` was a free function in src/utils/url.ts AND ten `protected getPath` methods of unrelated classes; the
# rows unioned their callers under nothing but defs="11", so `createRequest` (which calls this.getPath) read as a
# caller of the utils function. RED on main 953818d6: no cross_kind= anywhere.
XK="$( mktemp -d )"; trap 'rm -rf "$XK"' EXIT
mkdir -p "$XK/src/utils" "$XK/src/adapter"
cat >"$XK/src/utils/url.ts" <<'EOF'
export const getPath = (request: Request): string => {
  return request.url
}

export const getPathNoStrict = (request: Request): string => {
  return getPath(request)
}
EOF
cat >"$XK/src/adapter/handler.ts" <<'EOF'
export abstract class EventProcessor<E> {
  protected abstract getPath(event: E): string

  createRequest(event: E): string {
    return this.getPath(event)
  }
}

export class V2Processor extends EventProcessor<string> {
  protected getPath(event: string): string {
    return event
  }
}
EOF
XK_OUT="$( "$BIN" "$XK" --no-cache --callers=getPath --legend=full 2>/dev/null )"
xk_root="$( printf '%s' "$XK_OUT" | grep -o '<callers [^>]*>' | head -1 )"
printf '%s' "$xk_root" | grep -q 'cross_kind="fn:1,method:2"' \
    && ok "X: a bare name over 1 function + 2 methods carries cross_kind=\"fn:1,method:2\"" \
    || no "X: expected cross_kind=\"fn:1,method:2\" on the root, got: $xk_root"
printf '%s' "$XK_OUT" | grep -o '<!--.*-->' | grep -q 'cross_kind=kind:N' \
    && ok "X: the legend defines cross_kind= in the answer that carries it" \
    || no "X: cross_kind= emitted without its legend clause"
"$BIN" "$XK" --no-cache --callers=src/utils/url.ts:getPath 2>/dev/null | grep -q 'cross_kind=' \
    && no "X: a file:name selector that resolved to ONE kind still carries cross_kind=" \
    || ok "X: the file-qualified selector (one kind) carries no cross_kind="
"$BIN" "$XK" --no-cache --callees=getPath 2>/dev/null | grep -o '<callees [^>]*>' | grep -q 'cross_kind="fn:1,method:2"' \
    && ok "X: --callees carries the same cross_kind= (one resolution, both directions)" \
    || no "X: --callees missing cross_kind="
"$BIN" "$XK" --no-cache --callers=getPath --json 2>/dev/null | grep -q '"cross_kind":"fn:1,method:2"' \
    && ok "X: --json carries the cross_kind key" || no "X: --json missing cross_kind"
"$BIN" "$XK" --no-cache --callers=getPath --format=columnar 2>/dev/null | grep -q 'cross_kind="fn:1,method:2"' \
    && ok "X: --format=columnar carries cross_kind=" || no "X: --format=columnar missing cross_kind="
XK_MCP="$( printf '%s\n%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_referencing_symbols","arguments":{"path":"'"$XK"'","symbol":"getPath"}}}' \
    | "$BIN" "$XK" --mcp --no-cache 2>/dev/null | tail -1 )"
printf '%s' "$XK_MCP" | grep -q 'cross_kind' && printf '%s' "$XK_MCP" | grep -q 'fn:1,method:2' \
    && ok "X: the MCP twin find_referencing_symbols carries cross_kind" \
    || { no "X: the MCP twin dropped cross_kind"; printf '%s\n' "$XK_MCP" | cut -c1-300; }
# Same-kind overloads keep their bytes: queryfix's hot() is one function.
c hot | grep -q 'cross_kind=' && no "X: a single-kind answer grew cross_kind=" || ok "X: a single-kind answer carries no cross_kind="

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

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
    && printf '%s' "$OUT_HOT" | grep -qE '<s t="fn" n="caller_a" p="src/util\.cpp:3" sites_at="src/util\.cpp:3"/>' \
    && printf '%s' "$OUT_HOT" | grep -qE '<s t="fn" n="caller_b" p="src/util\.cpp:4" sites_at="src/util\.cpp:4"/>'; } \
    && ok "--callers=hot: exactly caller_a (util.cpp:3) + caller_b (util.cpp:4), count=2, each with its call site (CALLSITE-AT)" \
    || no "--callers=hot: wrong callers/lines — got: $OUT_HOT"

# ── #2: --callers=d3 lists exactly its one known caller (d2), correct file:line ─────────────────────────
OUT_D3="$( c d3 )"
{ [ "$( cnt "$OUT_D3" )" = 1 ] && printf '%s' "$OUT_D3" | grep -qE '<s t="fn" n="d2" p="src/chain\.cpp:3" sites_at="src/chain\.cpp:3"/>'; } \
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

# ── SA: CALLSITE-AT (2026-10-09) — every caller row carries its call sites as pasteable file:line (sites_at=), so
#    "every call site that must change" is answered by the FIRST call, not a --uses follow-up (tmux-19 / hono-19 /
#    textual-19 shape: 15 def rows, the 23 sites only in the follow-up). RED on the base binary (no sites_at= at all).
#    Arms: multi-site rows, a file-scope (<file-scope>) caller expanded to its sites, two calls on one line = one site,
#    a near-miss row with NO call spelled like the name (an aliased import) carries none, --callees never carries it,
#    equality with --uses role="call" per caller, the page window (offset), the per-row cap (sites_total= + next=),
#    present-only legend (compact + full, xmllint), escaping (& in a path; ',' in a columnar cell), and the
#    JSON / columnar / MCP (find_referencing_symbols, find_symbol calledBy) twins.
echo "=== SA: caller rows carry their call sites as file:line (sites_at=) ==="
SA="$( mktemp -d "${TMPDIR:-/tmp}/callerscheck-sa.XXXXXX" )"
trap 'rm -rf "$SA"' EXIT
mkdir -p "$SA/t" "$SA/a&b"
cat > "$SA/lib.c" <<'SAEOF'
int target(int x) { return x + 1; }
int two_lines(int y) {
    int a = target(y);
    int b = target(a); int c = target(b);
    return target(c);
}
int one_call(int z) { return target(z); }
SAEOF
cat > "$SA/t/test_mod.py" <<'SAEOF'
def pyhelper(x):
    return x

def py_caller():
    return pyhelper(1) + pyhelper(2)

pyhelper(3)
pyhelper(4)
SAEOF
cat > "$SA/k.ts" <<'SAEOF'
export function tsHelper(x: number): number { return x; }
export function tsDirect(): number { return tsHelper(1); }
SAEOF
cat > "$SA/j.ts" <<'SAEOF'
import { tsHelper as aliased } from "./k";
export function tsCaller(): number { return aliased(1); }
SAEOF
{ printf 'def many(x):\n    return x\n\n'; i=0; while [ $i -lt 20 ]; do printf 'many(%d)\n' $i; i=$((i+1)); done; } > "$SA/m.py"
printf 'int amp_target(int x) { return x; }\nint amp_caller(int y) { return amp_target(y); }\n' > "$SA/a&b/amp.c"
sa(){ perl -e 'alarm 15; exec @ARGV' "$BIN" "$SA" --no-cache "$@" 2>/dev/null; }
row(){ printf '%s' "$1" | sed 's/<!--.*-->//' | grep -oE "<s [^>]*n=\"$2\"[^>]*/>" | head -1; }
sat(){ printf '%s' "$1" | grep -oE ' sites_at="[^"]*"' | head -1 | sed -e 's/^ sites_at="//' -e 's/"$//'; }

SA_T="$( sa --callers=target )"
[ "$( sat "$( row "$SA_T" two_lines )" )" = "lib.c:3 lib.c:4 lib.c:5" ] \
    && ok "SA1: four calls on three lines -> sites_at=\"lib.c:3 lib.c:4 lib.c:5\" (two calls on one line are one site)" \
    || no "SA1: two_lines row: $( row "$SA_T" two_lines )"
[ "$( sat "$( row "$SA_T" one_call )" )" = "lib.c:7" ] && row "$SA_T" one_call | grep -q ' p="lib.c:7"' \
    && ok "SA1: a one-line caller keeps p= (its definition) and lists its one site" \
    || no "SA1: one_call row: $( row "$SA_T" one_call )"
SA_P="$( sa --callers=pyhelper )"
[ "$( sat "$( row "$SA_P" '&lt;file-scope&gt;' )" )" = "t/test_mod.py:7 t/test_mod.py:8" ] \
    && ok "SA2: a test file's <file-scope> caller expands to its sites (t/test_mod.py:7 t/test_mod.py:8)" \
    || no "SA2: modscope row: $( row "$SA_P" '&lt;file-scope&gt;' )"
SA_TS="$( sa --callers=tsHelper )"
{ row "$SA_TS" tsCaller | grep -q 'p="j.ts:2"' && ! row "$SA_TS" tsCaller | grep -q 'sites_at='; } \
    && ok "SA3: near miss: a caller whose call is spelled through an aliased import carries no sites_at=" \
    || no "SA3: tsCaller row: $( row "$SA_TS" tsCaller )"
[ "$( sat "$( row "$SA_TS" tsDirect )" )" = "k.ts:2" ] && ok "SA3: its direct sibling caller does (k.ts:2)" || no "SA3: tsDirect row: $( row "$SA_TS" tsDirect )"
sa --callees=two_lines | sed 's/<!--.*-->//' | grep -q 'sites_at=' && no "SA4: a --callees row carries sites_at=" || ok "SA4: --callees rows carry no sites_at="
# SA5: sites_at= equals the --uses role="call" lines inside that caller, for every row of the answer (one question, two documents).
SA5_BAD=0; SA5_N=0
for nm in target pyhelper; do
    ans="$( sa --callers=$nm )"; uses="$( sa --uses=$nm --limit=1000 )"
    for r in $( printf '%s' "$ans" | sed 's/<!--.*-->//' | grep -oE '<s [^>]*/>' | sed -E 's/.* n="([^"]*)".*/\1/' ); do
        got="$( sat "$( row "$ans" "$r" )" )"
        want="$( printf '%s' "$uses" | grep -oE "<u role=\"call\" p=\"[^\"]*\"[^>]*in_id=\"$r\"" | sed -E 's/.* p="([^"]*)".*/\1/' | sort -t: -k2,2n -u | tr '\n' ' ' | sed 's/ $//' )"
        SA5_N=$((SA5_N+1)); [ "$got" = "$want" ] || { SA5_BAD=1; printf '        %s/%s: sites_at="%s" but --uses role=call sites "%s"\n' "$nm" "$r" "$got" "$want"; }
    done
done
[ "$SA5_BAD" = 0 ] && [ "$SA5_N" -ge 4 ] && ok "SA5: every row's sites_at= equals its --uses role=call sites ($SA5_N rows)" || no "SA5: sites_at= != --uses call sites ($SA5_N rows)"
SA_O="$( sa --callers=target --limit=1 --offset=1 )"
{ [ "$( printf '%s' "$SA_O" | sed 's/<!--.*-->//' | grep -oE '<s ' | wc -l | tr -d ' ' )" = 1 ] && sat "$( printf '%s' "$SA_O" | sed 's/<!--.*-->//' | grep -oE '<s [^>]*/>' )" | grep -qE '^lib\.c:[0-9]'; } \
    && ok "SA6: a paged window (offset=1) still carries its row's sites" || no "SA6: paged answer: $SA_O"
SA_M="$( sa --callers=many )"; MROW="$( row "$SA_M" '&lt;file-scope&gt;' )"
{ [ "$( sat "$MROW" | wc -w | tr -d ' ' )" = 16 ] && printf '%s' "$MROW" | grep -q ' sites_total="20"' \
  && [ "$( sat "$MROW" | cut -d' ' -f1 )" = "m.py:4" ] && printf '%s' "$SA_M" | grep -q 'next="--uses=many"'; } \
    && ok "SA7: a 20-site row lists the first 16 (ascending) with sites_total=\"20\"; next= (--uses=many) lists all" \
    || no "SA7: capped row: $MROW"
printf '%s' "$SA_M" | grep -o '<!--.*-->' | grep -q 'sites_total=' && ok "SA7: the compact legend defines sites_total= where it rides" || no "SA7: sites_total= undefined"
printf '%s' "$SA_T" | grep -o '<!--.*-->' | grep -q 'sites_total=' && no "SA7: present-only: an uncut answer defines sites_total=" || ok "SA7: present-only: an uncut answer pays nothing for sites_total="
printf '%s' "$SA_T" | grep -o '<!--.*-->' | grep -q 'sites_at=' && ok "SA8: the compact legend defines sites_at= where it rides" || no "SA8: sites_at= undefined in the compact legend"
SA_F="$( sa --callers=many --legend=full )"
{ printf '%s' "$SA_F" | grep -o '<!--.*-->' | grep -q 'sites_at= on a caller row' && printf '%s' "$SA_F" | grep -q 'sites_total=N' \
  && printf '%s' "$SA_F" | xmllint --noout - 2>/dev/null; } \
    && ok "SA8: --legend=full carries the sites_at=/sites_total= clauses and stays well-formed (no -- in the comment)" || no "SA8: full legend: $( printf '%s' "$SA_F" | head -c 300 )"
sa --callers=d1 >/dev/null; "$BIN" "$FIX" --callers=d1 --no-cache 2>/dev/null | grep -q 'sites_at' && no "SA8: a zero-row answer mentions sites_at" || ok "SA8: present-only: a zero-row answer carries no sites_at reading"
SA_AMP="$( sa --callers=amp_target )"
{ printf '%s' "$SA_AMP" | grep -q 'sites_at="a&amp;b/amp.c:2"' && printf '%s' "$SA_AMP" | xmllint --noout - 2>/dev/null; } \
    && ok "SA9: a path holding & is escaped inside sites_at= (well-formed)" || no "SA9: amp answer: $SA_AMP"
SA_J="$( sa --callers=target --json )"
printf '%s' "$SA_J" | python3 -c '
import json, sys
d = json.load( sys.stdin ); r = { x["n"]: x.get( "sites_at" ) for x in d["callers"] }
sys.exit( 0 if r.get( "two_lines" ) == [ "lib.c:3", "lib.c:4", "lib.c:5" ] and r.get( "one_call" ) == [ "lib.c:7" ] else 1 )' \
    && ok "SA10: --json rows carry \"sites_at\":[file:line,...] (the XML row's list)" || no "SA10: --json: $SA_J"
sa --callers=many --json | python3 -c '
import json, sys
d = json.load( sys.stdin ); r = d["callers"][0]
sys.exit( 0 if len( r.get( "sites_at", [] ) ) == 16 and r.get( "sites_total" ) == 20 else 1 )' \
    && ok "SA10: a cut --json row carries sites_total" || no "SA10: --json cut row"
SA_C="$( sa --callers=target --format=columnar )"
{ printf '%s' "$SA_C" | grep -q 'fields="path,name,line,kind,tested,sites_at"' && printf '%s' "$SA_C" | grep -q '<sites_at>[^<]*lib.c:3 lib.c:4 lib.c:5' \
  && printf '%s' "$SA_C" | xmllint --noout - 2>/dev/null; } \
    && ok "SA10: --format=columnar carries the sites_at column (fields= names it)" || no "SA10: columnar: $( printf '%s' "$SA_C" | sed 's/<!--.*-->//' )"
sa --callers=many --format=columnar | grep -q '<sites_total>20</sites_total>' && ok "SA10: a cut columnar row carries the sites_total column" || no "SA10: columnar cut row"
sa --callers=target --format=columnar | grep -q 'sites_total' && no "SA10: present-only: an uncut columnar answer carries sites_total" || ok "SA10: present-only: no sites_total column when nothing was cut"
sa_mcp(){ printf '%s\n%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"'"$1"'","arguments":{"path":"'"$SA"'","symbol":"'"$2"'"}}}' \
    | perl -e 'alarm 20; exec @ARGV' "$BIN" "$SA" --mcp --no-cache 2>/dev/null | tail -1; }
for tool in find_referencing_symbols find_symbol; do
    sa_mcp "$tool" target | python3 -c '
import json, sys
env = json.loads( sys.stdin.read() ); d = json.loads( env["result"]["content"][0]["text"] )
r = { x["name"]: x.get( "sites_at" ) for x in d["calledBy"] }
calls_clean = all( "sites_at" not in x for x in d.get( "calls", [] ) )
sys.exit( 0 if r.get( "two_lines" ) == [ "lib.c:3", "lib.c:4", "lib.c:5" ] and "sites_note" in d and calls_clean else 1 )' \
        && ok "SA11: MCP $tool calledBy rows carry sites_at (== CLI) and the answer carries sites_note" \
        || no "SA11: MCP $tool: $( sa_mcp "$tool" target | head -c 400 )"
done
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

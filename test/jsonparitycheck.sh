#!/usr/bin/env bash
# jsonparitycheck.sh — gate for: the XML honesty ladder must
# reach every MACHINE mode, not just the XML one. Nine arms, each one a defect the audit found:
#
#   §A4a  --for --json honors --token-budget (it was byte-identical at 1000 and 20000 while the XML
#         sibling shrank 4.7x) and SAYS what it did: "capped" + "est_tokens".
#   §A4b  multi-root --json carries roots_count + the label->path roots table (paths were unresolvable).
#   §A4c  ONE page-disclosure vocabulary across the JSON verbs: shown/capped/total/has_more/next_offset/
#         offset/limit — including the past-end empty page, which must be a MEASUREMENT (has_more:false),
#         not a mystery. The JSON siblings had forked into two strict-subset dialects with no has_more.
#   §A4d  the JSON map collapses overloads (it emitted byte-identical duplicate rows for a const/non-const
#         pair, so a consumer keying on "id" silently lost one) and discloses "overloads":N.
#   §A4e  the §P5 weak-query signal reaches --json ("weak":true) and --format=candidates (weak="1") —
#         it used to be string-spliced into an XML comment, structurally unreachable from either.
#   §A4f  the <candidates> root carries its ranking provenance: route=/anchored=/total=/capped=.
#   §A5a  --batch joins the --limit/--offset REFUSING set (it accepted and ignored both).
#   §A5b  --format=columnar on a non-flat-list verb refuses (it was accepted and silently ignored).
#   §A5c  --pr-context is gone from --help's columnar list (an advertised no-op: prcontext.h has no
#         columnar code at all).
#
# Every JSON payload asserted here is first validated with python3 json.load — a shape claim about output
# that does not parse is worthless.
#
# Usage:  test/jsonparitycheck.sh   |   RIPWIRE_BIN=build_base/ripwire test/jsonparitycheck.sh
# Exits non-zero on any failure. Never mutates the checked-in fixture. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
# ok/no print to STDERR: several arms capture a verb's raw --json payload through jsonok(), which reports
# AND returns that payload, so stdout must stay reserved for the payload or the PASS/FAIL lines corrupt it
# (jsoncheck.sh learned this the same way). `fail` is still set in the parent shell — jsonok is called in a
# command substitution, so its own `no` cannot; every arm re-asserts on the returned payload anyway.
ok(){ printf '  PASS  %s\n' "$*" >&2; }
no(){ printf '  FAIL  %s\n' "$*" >&2; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }
echo "jsonparitycheck: BIN=$BIN"

# ── the fixture: TWO roots (for §A4b), a const/non-const overload pair (§A4d), and a helper with enough
#    callers to page (§A4c). Self-contained so no arm depends on the live tree's shifting contents.
mkdir -p "$TMP/rootA/src" "$TMP/rootB/lib"
cat > "$TMP/rootA/src/vec.h" <<'EOF'
#pragma once
// A tiny vector with a const/non-const accessor pair — the two canonicalize to the SAME id.
struct Vec
{
    int*       buf()       { return storage; }
    const int* buf() const { return storage; }
    int        size() const { return count; }
    int storage[ 8 ];
    int count = 0;
};
// The shared helper every caller below reaches for.
int clampIndex( int i, int n );
EOF
cat > "$TMP/rootA/src/vec.cpp" <<'EOF'
#include "vec.h"
int clampIndex( int i, int n ) { return i < 0 ? 0 : ( i >= n ? n - 1 : i ); }
int readFirst ( Vec& v ) { return v.buf()[ clampIndex( 0, v.size() ) ]; }
int readSecond( Vec& v ) { return v.buf()[ clampIndex( 1, v.size() ) ]; }
int readThird ( Vec& v ) { return v.buf()[ clampIndex( 2, v.size() ) ]; }
int readFourth( Vec& v ) { return v.buf()[ clampIndex( 3, v.size() ) ]; }
int readFifth ( Vec& v ) { return v.buf()[ clampIndex( 4, v.size() ) ]; }
EOF
cat > "$TMP/rootB/lib/report.cpp" <<'EOF'
#include "../../rootA/src/vec.h"
// A second root, so the multi-root prologue has something to label.
int reportSpan( Vec& v ) { return clampIndex( v.size(), 8 ); }
int reportHead( Vec& v ) { return clampIndex( 0, v.size() ); }
EOF
A="$TMP/rootA"
B="$TMP/rootB"

# valid JSON or bust — every arm below routes its payload through this first. It runs inside a command
# substitution, so a `fail=1` here would be lost with the subshell: the verdict is recorded in a MARKER FILE
# the parent re-reads at the end (a gate that can silently forget a failure is worse than no gate).
PARSEFAIL="$TMP/jsonparsefail"
jsonok(){ # $1 = description, stdin = payload
    local desc="$1" payload
    payload="$( cat )"
    if printf '%s' "$payload" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
        ok "$desc: payload is valid JSON"
    else
        no "$desc: payload is NOT valid JSON"
        printf '%s: %s\n' "$desc" "$( printf '%s' "$payload" | head -c 200 )" >> "$PARSEFAIL"
    fi
    printf '%s' "$payload"
}
# jq-less dotted getter (a.b[0].c); prints nothing when the path is absent.
jget(){ python3 -c '
import json, sys
cur = json.load(sys.stdin)
for part in sys.argv[1].split("."):
    if part.endswith("]"):
        name, idx = part[:-1].split("[")
        cur = (cur[name] if name else cur)[int(idx)]
    else:
        cur = cur[part]
print(json.dumps(cur) if isinstance(cur,(dict,list,bool)) else cur)
' "$1" 2>/dev/null; }

# ═══ §A4a — --for --json honors --token-budget, and discloses capped/est_tokens ═════════════════════════
echo
echo "=== §A4a --for --json honors --token-budget ==="
SMALL="$( "$BIN" "$A" --for="clamp an index into a vector" --json --token-budget=400 --no-cache 2>/dev/null | jsonok "--for --json (budget 400)" )"
BIG="$(   "$BIN" "$A" --for="clamp an index into a vector" --json --token-budget=20000 --no-cache 2>/dev/null | jsonok "--for --json (budget 20000)" )"
SB="${#SMALL}"; BB="${#BIG}"
[ -n "$SMALL" ] && [ -n "$BIG" ] && [ "$SB" -lt "$BB" ] \
    && ok "§A4a: a small --token-budget produces a SMALLER bundle ($SB < $BB bytes)" \
    || no "§A4a: --token-budget is a no-op under --json (small=$SB big=$BB bytes)"
SCAP="$( printf '%s' "$SMALL" | jget capped )"
BCAP="$( printf '%s' "$BIG"   | jget capped )"
[ "$SCAP" = "true" ] \
    && ok "§A4a: the trimmed bundle says so — \"capped\":true" \
    || no "§A4a: the trimmed bundle carries no honest \"capped\" key (got '$SCAP')"
[ "$BCAP" = "false" ] \
    && ok "§A4a: the untrimmed bundle says \"capped\":false (never a MISSING key to read as 'fine')" \
    || no "§A4a: the untrimmed bundle's \"capped\" is '$BCAP', expected false"
SEST="$( printf '%s' "$BIG" | jget est_tokens )"
case "$SEST" in ''|*[!0-9]*) no "§A4a: \"est_tokens\" missing or non-numeric (got '$SEST')";;
                          *) ok "§A4a: \"est_tokens\":$SEST reports the delivered size";; esac

# ═══ §A4b — multi-root --json carries the roots table ═══════════════════════════════════════════════════
echo
echo "=== §A4b multi-root --json roots table ==="
MR="$( "$BIN" "$A" "$B" --json --no-cache 2>/dev/null | jsonok "multi-root --json" )"
MRC="$( printf '%s' "$MR" | jget roots_count )"
[ "$MRC" = "2" ] \
    && ok "§A4b: \"roots_count\":2 joins the header gauges (the XML roots= sibling)" \
    || no "§A4b: \"roots_count\" missing/wrong (got '$MRC') — the JSON drops the multi-root signal"
MRL="$( printf '%s' "$MR" | jget 'roots[0].label' )"
# V1-6: the key is "p", mirroring the XML <root label= p=/> sibling ("--help promises keys mirror attrs").
MRP="$( printf '%s' "$MR" | jget 'roots[0].p' )"
{ [ -n "$MRL" ] && [ -n "$MRP" ]; } \
    && ok "§A4b: roots[0] maps a label to a path ($MRL -> $MRP), so every \"p\" resolves" \
    || no "§A4b: the label->path roots table is missing (label='$MRL' path='$MRP')"
SR="$( "$BIN" "$A" --json --no-cache 2>/dev/null | jsonok "single-root --json" )"
[ -z "$( printf '%s' "$SR" | jget roots_count )" ] \
    && ok "§A4b: single-root output carries NO roots table (additive, N>=2 only)" \
    || no "§A4b: single-root output grew a roots table it has no business emitting"

# ═══ §A4c — ONE page vocabulary across the JSON verbs, incl. the past-end empty page ════════════════════
echo
echo "=== §A4c the seven-key JSON page vocabulary ==="
PAGEKEYS="shown capped total has_more next_offset offset limit"
checkpage(){ # $1 = label, $2 = payload
    local label="$1" payload="$2" k missing=""
    for k in $PAGEKEYS; do
        [ -z "$( printf '%s' "$payload" | jget "$k" )" ] && missing="$missing $k"
    done
    [ -z "$missing" ] \
        && ok "§A4c: $label carries all seven page keys" \
        || no "§A4c: $label is missing page key(s):$missing"
}
CJ="$( "$BIN" "$A" --callers=clampIndex --json --limit=2 --no-cache 2>/dev/null | jsonok "--callers --json --limit" )"
checkpage "--callers --json --limit=2" "$CJ"
[ "$( printf '%s' "$CJ" | jget has_more )" = "true" ] \
    && ok "§A4c: --callers page 0 of many says has_more:true" \
    || no "§A4c: --callers page 0 does not say has_more:true"
IJ="$( "$BIN" "$A" --impact=clampIndex --json --limit=2 --no-cache 2>/dev/null | jsonok "--impact --json --limit" )"
checkpage "--impact --json --limit=2" "$IJ"
EJ="$( "$BIN" "$A" --callers=clampIndex --json --offset=99 --no-cache 2>/dev/null | jsonok "--callers --json --offset=99" )"
checkpage "--callers --json --offset=99 (past the end)" "$EJ"
{ [ "$( printf '%s' "$EJ" | jget has_more )" = "false" ] && [ "$( printf '%s' "$EJ" | jget shown )" = "0" ]; } \
    && ok "§A4c: the past-end empty page is a MEASUREMENT (shown:0 has_more:false), not a mystery" \
    || no "§A4c: the past-end empty page still cannot be told apart from a failure"
EIJ="$( "$BIN" "$A" --impact=clampIndex --json --offset=99 --no-cache 2>/dev/null | jsonok "--impact --json --offset=99" )"
[ "$( printf '%s' "$EIJ" | jget has_more )" = "false" ] \
    && ok "§A4c: --impact's past-end empty page says has_more:false too" \
    || no "§A4c: --impact's past-end empty page carries no has_more"

# ═══ §A4d — the JSON map collapses overloads and discloses the count ════════════════════════════════════
echo
echo "=== §A4d JSON map overload collapse ==="
MAPJ="$( "$BIN" "$A" --json --no-cache 2>/dev/null | jsonok "default map --json" )"
DUPS="$( printf '%s' "$MAPJ" | python3 -c '
import json, sys, collections
d = json.load(sys.stdin)
keys = [ (f["p"], s.get("id", s["n"]), s["t"]) for f in d["r"] for s in f["s"] ]
print(sum(1 for _, n in collections.Counter(keys).items() if n > 1))
' 2>/dev/null )"
[ "$DUPS" = "0" ] \
    && ok "§A4d: no duplicate (path,id,kind) rows in the JSON map" \
    || no "§A4d: the JSON map emits $DUPS duplicate id row(s) — a consumer keying on id loses one silently"
OVL="$( printf '%s' "$MAPJ" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(max([ s.get("overloads", 0) for f in d["r"] for s in f["s"] ] + [0]))
' 2>/dev/null )"
[ -n "$OVL" ] && [ "$OVL" -ge 2 ] 2>/dev/null \
    && ok "§A4d: the collapsed row discloses \"overloads\":$OVL" \
    || no "§A4d: no \"overloads\" key on the collapsed row (got max '$OVL') — the collapse would be a silent drop"

# ═══ §A4e — the weak signal reaches --json and --format=candidates ══════════════════════════════════════
echo
echo "=== §A4e the §P5 weak signal in both machine modes ==="
WQ="qqzzxx wubblefrotz"
WJ="$( "$BIN" "$A" --for="$WQ" --json --no-cache 2>/dev/null | jsonok "--for --json (nonsense query)" )"
[ "$( printf '%s' "$WJ" | jget weak )" = "true" ] \
    && ok "§A4e: --for --json on a nonsense query carries \"weak\":true" \
    || no "§A4e: --for --json hides the weak-result signal (XML-only)"
WC="$( "$BIN" "$A" --for="$WQ" --format=candidates --top-k=3 --no-cache 2>/dev/null )"
printf '%s' "$WC" | grep -q '<candidates[^>]* weak="1"' \
    && ok "§A4e: the <candidates> root carries weak=\"1\" on a nonsense query" \
    || no "§A4e: <candidates> exports a fabricated candidate set with no weak= signal"
GC="$( "$BIN" "$A" --for="clamp an index into a vector" --format=candidates --top-k=3 --no-cache 2>/dev/null )"
# V1-3 made the legend COMMENT explain weak="1", so the absence assertion must read the root TAG, not the
# whole document (grepping the document now always matches the legend's own explanatory text).
printf '%s' "$GC" | grep -q '<candidates[^>]* weak=' \
    && no "§A4e: a CONFIDENT query grew a weak= attribute (absent must mean 'fine')" \
    || ok "§A4e: a confident query emits no weak= (never a fabricated weak=\"0\")"

# ═══ §A4f — <candidates> ranking provenance ═════════════════════════════════════════════════════════════
echo
echo "=== §A4f <candidates> ranking provenance ==="
CROOT="$( printf '%s' "$GC" | grep -o '<candidates[^>]*>' | head -1 )"
for attr in route anchored total capped; do
    printf '%s' "$CROOT" | grep -q " $attr=\"" \
        && ok "§A4f: <candidates> carries $attr=" \
        || no "§A4f: <candidates> has no $attr= — root was: $CROOT"
done
NE="$( "$BIN" "$A" --for="clampIndex" --format=candidates --top-k=3 --no-cache 2>/dev/null | grep -o '<candidates[^>]*>' )"
printf '%s' "$NE" | grep -q 'route="name-exact"' \
    && ok "§A4f: a symbol-name query reports route=\"name-exact\" (a different score SCALE, now disclosed)" \
    || no "§A4f: route= does not distinguish the name-exact ranker — root was: $NE"

# ═══ §A5a — --batch refuses --limit/--offset ════════════════════════════════════════════════════════════
echo
echo "=== §A5a --batch joins the paging REFUSING set ==="
printf 'callers:clampIndex\n' > "$TMP/b.txt"
"$BIN" "$A" --batch="$TMP/b.txt" --limit=2 --no-cache >/dev/null 2>"$TMP/e_batch"; rc=$?
{ [ "$rc" -eq 1 ] && grep -q 'honored only by' "$TMP/e_batch"; } \
    && ok "§A5a: --batch --limit refuses (exit 1, the standard honoring-set text)" \
    || no "§A5a: --batch --limit exit=$rc — still accept-and-ignore. stderr: $( head -c 120 "$TMP/e_batch" )"
"$BIN" "$A" --batch="$TMP/b.txt" --no-cache >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] \
    && ok "§A5a: plain --batch (no --limit) still works — the refusal is scoped to the ignored flags" \
    || no "§A5a: plain --batch broke (exit=$rc)"

# ═══ §A5b/§A5c — --format=columnar refuses off the flat-list verbs; --pr-context struck from --help ═════
echo
echo "=== §A5b/§A5c --format=columnar honesty ==="
for verb in --hotspots --clones --lint --tree; do
    "$BIN" "$A" "$verb" --format=columnar --no-cache >/dev/null 2>"$TMP/e_col"; rc=$?
    { [ "$rc" -eq 1 ] && grep -q 'format=columnar' "$TMP/e_col"; } \
        && ok "§A5b: $verb --format=columnar refuses (exit 1, names the flag)" \
        || no "§A5b: $verb --format=columnar exit=$rc — accepted and silently ignored"
done
"$BIN" "$A" --pr-context --format=columnar --no-cache >/dev/null 2>"$TMP/e_pr"; rc=$?
{ [ "$rc" -eq 1 ] && grep -q 'callers/--callees/--uses/--impact' "$TMP/e_pr"; } \
    && ok "§A5c: --pr-context --format=columnar refuses and names the four verbs that DO support it" \
    || no "§A5c: --pr-context --format=columnar exit=$rc — the advertised no-op survives"
"$BIN" "$A" --callers=clampIndex --format=columnar --no-cache 2>/dev/null | grep -q 'format="columnar"' \
    && ok "§A5b: --callers --format=columnar still emits the columnar form (the refusal is scoped)" \
    || no "§A5b: the guard broke a SUPPORTED columnar verb"
HELPCOL="$( "$BIN" --help 2>&1 | grep -A1 -- '--format=xml|columnar|rows' | head -2 )"
printf '%s' "$HELPCOL" | grep -q -- '--pr-context' \
    && no "§A5c: --help still advertises --pr-context in the columnar list: $HELPCOL" \
    || ok "§A5c: --help's columnar list no longer claims --pr-context"

# ═══ §B1.3 (capture-audit-4, 2026-07-30) — --with-graph warns under --json instead of silent no-op ═══════
echo
echo "=== §B1.3 --with-graph warns under --json (--for / --pack-task) ==="
"$BIN" "$A" --for="clamp an index into a vector" --json --with-graph --no-cache >/dev/null 2>"$TMP/e_wg_for"
grep -q -- '--with-graph is not applied under --json' "$TMP/e_wg_for" \
    && ok "§B1.3: --for --json --with-graph warns on stderr" \
    || no "§B1.3: --for --json --with-graph is still a silent no-op: $( cat "$TMP/e_wg_for" )"
WGJ="$( "$BIN" "$A" --for="clamp an index into a vector" --json --with-graph --no-cache 2>/dev/null | jsonok "--for --json --with-graph" )"
printf '%s' "$WGJ" | grep -qF '"graph' \
    && no "§B1.3: --for --json --with-graph payload unexpectedly grew a graph-shaped key" \
    || ok "§B1.3: --for --json --with-graph payload carries no graph key (the mermaid block stays XML-only)"
"$BIN" "$A" --pack-task="clamp an index into a vector" --json --with-graph --no-cache >/dev/null 2>"$TMP/e_wg_pack"
grep -q -- '--with-graph is not applied under --json' "$TMP/e_wg_pack" \
    && ok "§B1.3: --pack-task --json --with-graph warns on stderr" \
    || no "§B1.3: --pack-task --json --with-graph is still a silent no-op: $( cat "$TMP/e_wg_pack" )"
# the warning is --json-SCOPED — the XML feature itself (already gated by withgraphcheck.sh) must be unaffected
"$BIN" "$A" --for="clamp an index into a vector" --with-graph --no-cache 2>/dev/null | grep -qF '<graph fmt="mermaid"' \
    && ok "§B1.3: --for --with-graph (XML, no --json) still emits the mermaid block — the warning did not regress it" \
    || no "§B1.3: --for --with-graph (XML) regressed — no <graph> block"

# ═══ §B1.4 (capture-audit-4, 2026-07-30) — --for --json discloses lego_total/compose_total/routes_total ══
# the notes_total precedent, verbatim: a consumer must be able to tell 0 (genuinely absent on this surface)
# from a key that was never there at all (dropped). Real fixtures, not synthetic ones: test/legofix (real
# interfaces), src/ (a real HAS-A compose edge), test/routeedgefix (a real B6.3 client->server route edge) —
# each cross-checked against ITS OWN XML sibling's row count so the assertion survives repo content drift.
echo
echo "=== §B1.4 --for --json lego_total/compose_total/routes_total ==="
LOFF="$( "$BIN" "$ROOT" --for="cache invalidation" --json --no-cache 2>/dev/null | jsonok "--for --json (off-task, no lego surface)" )"
for k in lego_total compose_total routes_total; do
    V="$( printf '%s' "$LOFF" | jget "$k" )"
    case "$V" in ''|*[!0-9]*) no "§B1.4: off-task payload's \"$k\" is missing or non-numeric (got '$V')" ;;
                          *)  ok "§B1.4: off-task payload always carries \"$k\":$V (never omitted)" ;; esac
done
[ "$( printf '%s' "$LOFF" | jget lego_total )" = "0" ] \
    && ok "§B1.4: an off-task surface with no interfaces reports lego_total:0 (genuinely absent)" \
    || no "§B1.4: off-task lego_total is '$( printf '%s' "$LOFF" | jget lego_total )', expected 0"

LON="$( "$BIN" "$ROOT" --for="Circle Square shape area implementors" --json --no-cache 2>/dev/null | jsonok "--for --json (on-task, real lego surface)" )"
LON_LEGO="$( printf '%s' "$LON" | jget lego_total )"
{ [ -n "$LON_LEGO" ] && [ "$LON_LEGO" -gt 0 ]; } 2>/dev/null \
    && ok "§B1.4: an on-task surface (Shape/Circle/Square) reports lego_total:$LON_LEGO (dropped, not absent)" \
    || no "§B1.4: on-task lego_total is '$LON_LEGO', expected > 0 — Shape/Circle/Square exist in test/legofix"
# lego_total is deliberately PRE-dedup/pre-cap (the notes_total "what matched" convention) — packLego then
# dedups same-named interfaces and caps at topN=12, so it must be >= the XML sibling's own row count, never <.
XML_IFACES="$( "$BIN" "$ROOT" --for="Circle Square shape area implementors" --no-cache 2>/dev/null | grep -oE '<iface ' | wc -l | tr -d ' ' )"
# >0 guard on the XML side (2026-08-23 serving-shape sweep): without it this arm degrades to N>=0 the
# moment the XML sibling stops emitting <iface> rows at all — an under-count is unobservable against an
# empty roster, so the comparison must first prove the roster is non-empty (the routes arm below already
# does this; the compose arm gains the same guard).
{ [ -n "$XML_IFACES" ] && [ "$XML_IFACES" -gt 0 ]; } 2>/dev/null \
    && ok "§B1.4 presence: the XML sibling emits $XML_IFACES <iface> row(s) (the roster the >= below compares against)" \
    || no "§B1.4 presence: the XML sibling emits NO <iface> rows — the under-count comparison below is vacuous"
{ [ -n "$LON_LEGO" ] && [ "$LON_LEGO" -ge "$XML_IFACES" ]; } 2>/dev/null \
    && ok "§B1.4: lego_total ($LON_LEGO) >= the XML sibling's own <iface> row count ($XML_IFACES) — never UNDER-counts" \
    || no "§B1.4: lego_total ($LON_LEGO) is LESS than the XML row count ($XML_IFACES) — would hide a real interface"

CJ2="$( "$BIN" "$ROOT/src" --for="parse arguments" --json --no-cache 2>/dev/null | jsonok "--for --json (compose surface)" )"
COMPOSE_TOTAL="$( printf '%s' "$CJ2" | jget compose_total )"
XML_FIELDS="$( "$BIN" "$ROOT/src" --for="parse arguments" --no-cache 2>/dev/null | grep -oE '<field name=' | wc -l | tr -d ' ' )"
# same >0 guard as the lego arm above: 0==0 is parity of two absences, not parity of a surface.
{ [ -n "$COMPOSE_TOTAL" ] && [ "$COMPOSE_TOTAL" = "$XML_FIELDS" ] && [ "$COMPOSE_TOTAL" -gt 0 ]; } 2>/dev/null \
    && ok "§B1.4: compose_total ($COMPOSE_TOTAL) matches the XML sibling's <field> row count exactly, and is > 0" \
    || no "§B1.4: compose_total ($COMPOSE_TOTAL) != XML sibling's <field> count ($XML_FIELDS), or both zero"

# LB-A (relevance floor, r10 round): the query names the route fixture's own handlers. It used to be the
# bare word "test", which scores ZERO on every symbol there — the surface the <routes> block is scoped to
# existed only as quota padding. test/routeedgecheck.sh moved for the same reason and to the same query.
RQ="load user order widget register item"
RJ="$( "$BIN" "$ROOT/test/routeedgefix" --for="$RQ" --json --no-cache 2>/dev/null | jsonok "--for --json (route-edge surface)" )"
ROUTES_TOTAL="$( printf '%s' "$RJ" | jget routes_total )"
XML_ROUTES="$( "$BIN" "$ROOT/test/routeedgefix" --for="$RQ" --no-cache 2>/dev/null | grep -oE '<route method=' | wc -l | tr -d ' ' )"
{ [ -n "$ROUTES_TOTAL" ] && [ "$ROUTES_TOTAL" = "$XML_ROUTES" ] && [ "$ROUTES_TOTAL" -gt 0 ]; } 2>/dev/null \
    && ok "§B1.4: routes_total ($ROUTES_TOTAL) matches the XML sibling's <route> row count exactly, and is > 0" \
    || no "§B1.4: routes_total ($ROUTES_TOTAL) != XML sibling's <route> count ($XML_ROUTES), or both zero"

# ── R1 (terminality round A, verify-wave1): the BUDGET keys reach this dialect too ────────────────────────
# This gate's whole premise is that the XML honesty ladder must reach every MACHINE mode. The ladder's
# budget rung had reached only the XML one. `--for --token-budget=N --json` carried NO budget_tokens key at
# all — a caller could not even perform the comparison itself — and labelled over_ceiling on a DIFFERENT
# unit from its twin: bytes against ceilingAllowanceBytes (N x 2.36 x 1.15 = 2.714 N) while est_tokens
# prices at bytes / 2.50, so every document in 2.50 N < bytes <= 2.714 N printed est_tokens > N with nothing
# on the root. RED, MEASURED on 4b722433, this repo's own src/: at --token-budget=880 the JSON root reads
# "est_tokens":886 — 6 over the stated ceiling, no over_ceiling — and at EVERY rung that root carries no
# budget_tokens key at all, beside an XML root reading budget_tokens="880" est_tokens=… over_ceiling="1".
# 880 is carried as a rung BECAUSE it is where this corpus sits inside the silent band today; the durable,
# corpus-independent statement of the same rule is fornotesbudgetcheck arm 6's 700..2000 sweep over a
# GENERATED fixture. Should src/ grow past this rung the clause here goes vacuous (never falsely red) and
# that sweep is what still holds the line. Three clauses, per rung:
#   • budget_tokens is on the JSON root whenever it is on the XML root, and names the SAME N;
#   • est_tokens is served in both (the price a budget shapes against is never withheld);
#   • est_tokens > N implies over_ceiling in that dialect's own spelling — ONE unit, both dialects.
# The XML side is asserted here too rather than assumed: this is a PARITY arm, and a parity that only ever
# reads one side cannot tell a fixed dialect from a regressed reference.
echo
echo "=== R1 --for --token-budget: the budget keys are the same in both dialects ==="
for BTB in 880 900 1500; do
    BX="$( "$BIN" "$ROOT/src" --for="parse arguments" --token-budget="$BTB" --no-cache 2>/dev/null )"
    BJ="$( "$BIN" "$ROOT/src" --for="parse arguments" --token-budget="$BTB" --json --no-cache 2>/dev/null \
           | jsonok "--for --json --token-budget=$BTB" )"
    XE="$( printf '%s' "$BX" | grep -o 'est_tokens="[0-9]*"' | head -1 | tr -dc '0-9' )"
    JE="$( printf '%s' "$BJ" | jget est_tokens )"
    case "$BX" in *"budget_tokens=\"$BTB\""*) XB=1 ;; *) XB=0 ;; esac
    case "$BJ" in *"\"budget_tokens\":$BTB"*)  JB=1 ;; *) JB=0 ;; esac
    case "$BX" in *'over_ceiling="1"'*)        XL=1 ;; *) XL=0 ;; esac
    case "$BJ" in *'"over_ceiling":true'*)     JL=1 ;; *) JL=0 ;; esac
    if [ "$XB" -eq 0 ]; then
        no "R1: the XML root does not echo budget_tokens=\"$BTB\" — the reference this parity is measured against is gone"
    elif [ "$JB" -eq 1 ]; then
        ok "R1: budget_tokens=$BTB is on BOTH roots (the ceiling the bundle was shaped against is readable in either dialect)"
    else
        no "R1: budget_tokens=$BTB rides the XML root and is ABSENT from the JSON root — a machine caller cannot check the answer against the ceiling it stated"
    fi
    if [ -n "$XE" ] && [ -n "$JE" ]; then
        ok "R1: budget=$BTB — the price is SERVED in both dialects (xml est_tokens=$XE, json est_tokens=$JE)"
    else
        no "R1: budget=$BTB — est_tokens missing (xml='$XE' json='$JE'); a budget that shapes a bundle must price it"
    fi
    { [ -n "$XE" ] && { [ "$XE" -le "$BTB" ] || [ "$XL" -eq 1 ]; }; } 2>/dev/null \
        && ok "R1: budget=$BTB xml — est_tokens=$XE is inside the ceiling or labelled (over_ceiling=$XL)" \
        || no "R1: budget=$BTB xml — est_tokens=$XE exceeds the stated ceiling with NO over_ceiling"
    { [ -n "$JE" ] && { [ "$JE" -le "$BTB" ] || [ "$JL" -eq 1 ]; }; } 2>/dev/null \
        && ok "R1: budget=$BTB json — est_tokens=$JE is inside the ceiling or labelled (over_ceiling=$JL)" \
        || no "R1: budget=$BTB json — est_tokens=$JE exceeds the stated ceiling with NO over_ceiling — the XML twin's unit did not reach this dialect"
done

echo
if [ -s "$PARSEFAIL" ]; then
    fail=1
    echo "  FAIL  at least one --json payload did not parse:"
    cat "$PARSEFAIL"
fi
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME CHECKS FAILED"
exit "$fail"

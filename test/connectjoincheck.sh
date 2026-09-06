#!/usr/bin/env bash
# connectjoincheck.sh — gate for WHICH join --connect reports when several joins are equally short,
# and for the join's own disclosure (the CLI --connect verb + its `connect` MCP twin).
#
# THE DEFECT THIS PINS. connectSubgraph()'s per-terminal BFS records the FIRST-discovered parent, and
# discovery order is out-edges-then-in-edges, each ascending by node id — an id assigned in crawl order,
# which is sorted by PATH. So among several equally-short joins the reported one was decided by file
# NAME. Measured over an 869-pair population of this repo's own call graph, 186 of the 201 wrong joins
# (92.5%) were an STL or hub name: `empty` 79 times, `VERIFY` 27, `DYNMAP_VERIFY` 26, `push_back` 22,
# `reserve` 20, `size` 18. A join node that connects everything connects nothing — this is the --connect
# analogue of IDF, and the verb did not apply it.
#
# The gate pins BEHAVIOUR, not the mechanism: the same logical graph laid out under two different file
# names must report the same join, and that join must be the one that connects FEWER things.
#
# Scratch corpus (OUTSIDE test/, so test/golden.xml is untouched), built TWICE with the file names
# swapped so path order cannot be what decides:
#     hub()   — called by left(), right() and 40 fillers  → 42 connections (a hub)
#     mid()   — called by left() and right() only         →  2 connections (informative)
#     left(), right() — the terminals; BOTH call hub() AND mid(), so the two joins are at the SAME
#                       distance and produce the SAME subgraph size (3 nodes, 2 edges) either way.
#
# Assertions:
#   A  informativeness: --connect=left,right reports mid, never hub, in the layout where hub sorts FIRST
#      (the arm that was RED: pre-fix this reported hub)
#   B  crawl-order invariance: the mirrored layout (mid sorts first) reports the SAME join — one graph,
#      one answer, whatever the files are called
#   C  minimality preserved: nodes="3" edges="2" in both layouts (same distance, same subgraph size —
#      the tie-break changes WHICH equally-short answer, never how big it is)
#   D  disclosure, always: every Steiner <s> row carries connects="N" and the root carries hub_floor="N"
#   E  disclosure, hub case: when the ONLY join available IS the hub, the row is served WITH hub="1" —
#      an honest "the join found connects N other things" instead of a confident bare name
#   F  the informative join is NOT labelled a hub (the label discriminates; it is not decoration)
#   G  determinism: 3 runs byte-identical, warm == cold
#   H  G4: xmllint --noout clean
#   I  MUTATION self-tests — the three most plausible regressions (join reverts to the hub; hub="1"
#      stops being emitted; connects= stops being emitted) must each trip their own assertion
#   J  legend: the three new attribute names are DEFINED (name=) on the verb's own first screen
#   K  MCP twin parity: the `connect` verb emits the same connects=/hub=/hub_floor= as the CLI
#
# Usage:  test/connectjoincheck.sh              # uses build/ripwire
#         RIPWIRE_BIN=asan/ripwire test/connectjoincheck.sh
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
echo "connectjoincheck: BIN=$BIN"

# ── the corpus builder: same graph, caller-chosen file names ───────────────────────────────────────────
# hubFile carries hub() plus the 40 fillers that make it a hub; midFile carries mid(); the terminals live
# in their own file and call BOTH, so hub and mid are equally-short joins by construction.
mkcorpus(){
    d="$1"; hubFile="$2"; midFile="$3"
    mkdir -p "$d"
    {
        echo "void hub() {}"
        i=1
        while [ "$i" -le 40 ]; do printf 'void filler%d() { hub(); }\n' "$i"; i=$(( i + 1 )); done
    } > "$d/$hubFile"
    echo "void mid() {}" > "$d/$midFile"
    {
        echo "void hub(); void mid();"
        echo "void left()  { hub(); mid(); }"
        echo "void right() { hub(); mid(); }"
    } > "$d/m_terms.cpp"
}
mkcorpus "$TMP/hubfirst" a_hub.cpp z_mid.cpp     # hub sorts FIRST → the lower node id → the pre-fix winner
mkcorpus "$TMP/midfirst" z_hub.cpp a_mid.cpp     # the mirror: only the file names differ

HUBFIRST="$( "$BIN" "$TMP/hubfirst" --no-cache --connect=left,right 2>/dev/null )"
MIDFIRST="$( "$BIN" "$TMP/midfirst" --no-cache --connect=left,right 2>/dev/null )"

steinerOf(){ printf '%s' "$1" | grep -o '<s n="[^"]*"' | sed 's/<s n="//;s/"//' | sort | tr '\n' ' ' | sed 's/ $//'; }
# failure messages quote the DOCUMENT, not its ~1 KB legend — the legend is identical in every failure and
# scrolls the one differing byte off the screen.
brief(){ printf '%s' "$1" | sed 's/^.*<connect /<connect /' | head -c 420; }
SH="$( steinerOf "$HUBFIRST" )"
SM="$( steinerOf "$MIDFIRST" )"

# ── A) informativeness: the join that connects FEWER things wins the equal-distance tie ────────────────
[ "$SH" = "mid" ] \
    && ok "(A) hub-sorts-first layout joins through mid (2 connections), not hub (42)" \
    || no "(A) expected the Steiner join to be 'mid', got '$SH': $( brief "$HUBFIRST" )"

# ── B) crawl-order invariance: one graph, one answer, whatever the files are called ────────────────────
[ "$SH" = "$SM" ] \
    && ok "(B) the mirrored file layout reports the SAME join ('$SM') — path order does not decide" \
    || no "(B) the join changed with the file names: hub-first='$SH' mid-first='$SM'"

# ── C) minimality preserved: same distance, same subgraph size ────────────────────────────────────────
for pair in "hubfirst:$HUBFIRST" "midfirst:$MIDFIRST"; do
    lbl="${pair%%:*}"; doc="${pair#*:}"
    printf '%s' "$doc" | grep -q 'nodes="3"' && printf '%s' "$doc" | grep -q 'edges="2"' \
        && ok "(C) $lbl: nodes=\"3\" edges=\"2\" — the tie-break changed WHICH join, not how big the answer is" \
        || no "(C) $lbl: subgraph size moved (expected nodes=3 edges=2): $( brief "$doc" )"
done

# ── D) disclosure, always: connects= on every Steiner row, hub_floor= on the root ──────────────────────
sCount="$( printf '%s' "$HUBFIRST" | grep -o '<s ' | wc -l | tr -d ' ' )"
sWithConnects="$( printf '%s' "$HUBFIRST" | grep -o '<s [^>]*connects="[0-9][0-9]*"' | wc -l | tr -d ' ' )"
[ "$sCount" -gt 0 ] && [ "$sCount" = "$sWithConnects" ] \
    && ok "(D) every Steiner row ($sCount) carries connects=\"N\"" \
    || no "(D) $sWithConnects of $sCount Steiner rows carry connects=: $( brief "$HUBFIRST" )"
printf '%s' "$HUBFIRST" | grep -q 'hub_floor="[0-9][0-9]*"' \
    && ok "(D) the root discloses hub_floor=\"N\" (the derived threshold connects= is read against)" \
    || no "(D) no hub_floor= on the <connect> root: $( brief "$HUBFIRST" )"

# ── E) disclosure, hub case: the only join available is the hub, and it is SERVED AS ONE ───────────────
# a() and b() share ONLY hub() — there is no informative alternative, so the honest answer is the hub
# together with the count of what it connects.
HO="$TMP/hubonly"; mkdir -p "$HO"
{
    echo "void hub() {}"
    i=1
    while [ "$i" -le 40 ]; do printf 'void filler%d() { hub(); }\n' "$i"; i=$(( i + 1 )); done
    echo "void a() { hub(); }"
    echo "void b() { hub(); }"
} > "$HO/only.cpp"
HUBONLY="$( "$BIN" "$HO" --no-cache --connect=a,b 2>/dev/null )"
[ "$( steinerOf "$HUBONLY" )" = "hub" ] \
    && ok "(E) hub-only corpus still answers (the hub is the only join there is)" \
    || no "(E) expected the hub as the only available join: $( brief "$HUBONLY" )"
printf '%s' "$HUBONLY" | grep -q '<s n="hub"[^>]* connects="4[0-9]"' \
    && ok "(E) the hub row carries its own connection count" \
    || no "(E) hub row missing connects=: $( brief "$HUBONLY" )"
printf '%s' "$HUBONLY" | grep -q '<s n="hub"[^>]* hub="1"' \
    && ok "(E) the hub row is LABELLED hub=\"1\" instead of served as a confident bare name" \
    || no "(E) hub row missing hub=\"1\": $( brief "$HUBONLY" )"

# ── F) the label discriminates: the informative join is NOT labelled a hub ─────────────────────────────
printf '%s' "$HUBFIRST" | grep -q '<s n="mid"[^>]* hub="1"' \
    && no "(F) the 2-connection join 'mid' was labelled hub=\"1\" — the label is decoration" \
    || ok "(F) the informative join carries no hub=\"1\" (the label discriminates)"

# ── G) determinism: 3 cold runs byte-identical; warm == cold ───────────────────────────────────────────
"$BIN" "$TMP/hubfirst" --no-cache --connect=left,right >"$TMP/d1" 2>/dev/null
"$BIN" "$TMP/hubfirst" --no-cache --connect=left,right >"$TMP/d2" 2>/dev/null
"$BIN" "$TMP/hubfirst" --no-cache --connect=left,right >"$TMP/d3" 2>/dev/null
diff -q "$TMP/d1" "$TMP/d2" >/dev/null && diff -q "$TMP/d2" "$TMP/d3" >/dev/null \
    && ok "(G) determinism: 3 runs byte-identical" || no "(G) non-deterministic join choice"
"$BIN" "$TMP/hubfirst" --connect=left,right >/dev/null 2>&1          # prime the cache
"$BIN" "$TMP/hubfirst" --connect=left,right >"$TMP/w2" 2>/dev/null
diff -q "$TMP/d1" "$TMP/w2" >/dev/null && ok "(G) warm == cold (cache-neutral)" || no "(G) warm run differs from cold"

# ── H) G4: well-formed XML ─────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$HUBONLY" | xmllint --noout - 2>/dev/null && ok "(H) xml well-formed (xmllint)" || no "(H) xml malformed"
else
    ok "(H) xmllint absent — skipped"
fi

# ── I) MUTATION self-tests: each assertion must be able to see its own regression ──────────────────────
MUT_A="$( printf '%s' "$HUBFIRST" | sed 's/<s n="mid"/<s n="hub"/' )"
[ "$( steinerOf "$MUT_A" )" = "mid" ] \
    && no "(I) mutation (join reverts to hub): the rewritten output still passes (A) — assertion is decoration" \
    || ok "(I) mutation (join reverts to hub) correctly FAILS assertion (A)"
MUT_E="$( printf '%s' "$HUBONLY" | sed 's/ hub="1"//g' )"
printf '%s' "$MUT_E" | grep -q '<s n="hub"[^>]* hub="1"' \
    && no "(I) mutation (hub label dropped): still passes (E) — assertion is decoration" \
    || ok "(I) mutation (hub label dropped) correctly FAILS assertion (E)"
MUT_D="$( printf '%s' "$HUBFIRST" | sed 's/ connects="[0-9]*"//g' )"
mutCount="$( printf '%s' "$MUT_D" | grep -o '<s [^>]*connects="[0-9][0-9]*"' | wc -l | tr -d ' ' )"
[ "$mutCount" = "0" ] \
    && ok "(I) mutation (connects= dropped) correctly FAILS assertion (D)" \
    || no "(I) mutation (connects= dropped): still passes (D) — assertion is decoration"

# ── J) legend: the reader meets connects=/hub=/hub_floor= on the first screen, defined there ───────────
LEGEND="$( printf '%s' "$HUBONLY" | sed 's/<connect .*//' )"
for attr in 'connects=' 'hub=' 'hub_floor='; do
    printf '%s' "$LEGEND" | grep -qF "$attr" \
        && ok "(J) the --connect legend defines $attr" || no "(J) $attr is undefined in the --connect legend"
done

# ── K) MCP twin parity: the `connect` verb is the SAME emitter, so it must carry the same attributes ───
if command -v python3 >/dev/null 2>&1; then
    mcp_call(){ printf '%s\n' "$@" | "$BIN" --mcp 2>/dev/null; }
    CMSG='{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"connect","arguments":{"path":"'"$TMP/hubfirst"'","symbols":["left","right"]}}}'
    INNER="$( mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$CMSG" | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__:" + json.dumps(r["error"]) if "error" in r else r["result"]["content"][0]["text"])
' )"
    case "$INNER" in
        __ERROR__*) no "(K) connect verb returned error: ${INNER#__ERROR__:}";;
        *) [ "$( steinerOf "$INNER" )" = "mid" ] \
               && ok "(K) MCP connect verb picks the same informative join as the CLI" \
               || no "(K) MCP connect verb join differs from the CLI: $( brief "$INNER" )"
           printf '%s' "$INNER" | grep -q 'hub_floor="[0-9][0-9]*"' \
               && ok "(K) MCP connect verb discloses hub_floor=" || no "(K) MCP payload missing hub_floor=: $( brief "$INNER" )"
           printf '%s' "$INNER" | grep -q '<s [^>]*connects="[0-9][0-9]*"' \
               && ok "(K) MCP connect verb discloses connects= on the Steiner row" || no "(K) MCP payload missing connects=: $( brief "$INNER" )";;
    esac
else
    ok "(K) python3 absent — MCP parity skipped"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"

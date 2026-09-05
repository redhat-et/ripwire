#!/usr/bin/env bash
# partitioncheck.sh — the gate for `--pack-task="TASK" --partition=N` (src/partition.h):
# the FAN-OUT form of the task bundle — ONE shared common core plus N minimally-overlapping per-agent slices
# carved along the call graph's own Louvain communities, so N parallel agents stop re-deriving one map.
#
#   test/partitioncheck.sh
#   RIPWIRE_BIN=asan/ripwire test/partitioncheck.sh
#
# No new corpus: the two committed trees already in the repo cover both directions of the count mismatch.
#   this repo's own src/   — 30+ communities on a real task surface  ⇒ K >= N, whole modules packed into bins
#   test/fixture           — a handful of symbols                    ⇒ K <  N, the rank-median split path, and
#                            (with a narrow task) the honest "fewer partitions than requested" degrade
#
# What it proves:
#   • N+1 bundles emitted (one core, N partitions), each a standalone <ctx> an agent can be handed verbatim
#   • every bundle under ITS OWN budget (core share + partition share of the per-AGENT --token-budget)
#   • the assignment is DETERMINISTIC — byte-identical across runs, incl. the Louvain-derived slice ids
#   • the union COVERS the ranked surface and loses nothing:  core_symbols + Σ partition symbols == surface
#   • the slices are provably DISJOINT (pairwise (file,line) intersection of every bundle's ranking window)
#   • the measured cross-partition overlap is REPORTED (overlap_mean/overlap_max/shared/union/core_overlap)
#   • both count-mismatch directions behave as documented (split= on K<N; partitions<requested when N is
#     simply unreachable — never silently invented empty bundles)
#   • the refusals: bare --partition, N=1, N=17, a non-numeric N; and --with-graph, which cannot compose
#     here (N+1 bundles, no single graph), WARNS instead of silently vanishing
#   • G4 on every emission (xmllint clean, no newline outside CDATA)
#   • the SINGLE-bundle path is unperturbed (still exactly one <ctx> root, still deterministic)
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "partitioncheck: python3 unavailable — skipping"; exit 0; }

SRC="$ROOT/src"
FIX="$ROOT/test/fixture"
TASK="rank the task surface and assemble the bundle sections"
KMINBPT=2.36            # kMinBytesPerToken — the densest byte/token rate the budget contract is written in
TOL=1.15                # the documented single-entry overshoot tolerance (packBodies emits its first body whole)

# Same class, same fix as packtaskcheck.sh's W3-S item 6 (2026-08-19): a --partition bundle's <ctx> headers
# and every ranked <d> row's path-qualified canonical id= key embed the corpus ROOT verbatim, so an absolute
# "$SRC" spends bytes proportional to $ROOT's own path DEPTH — a worktree living under a long scratch path
# measurably inflates every ceiling comparison below over a short-path checkout of the IDENTICAL commit
# (reproduced on this lane: a 102-char root pushes core to 5785 B against the SAME 5536 B ceiling that a
# ~50-char root clears at 2040 B's worth of tokens; a peer session on this same round independently measured
# ~95-char → core 5717 B FAIL vs an 18-char root → PASS, and confirmed the mechanism: 26 absolute-path
# occurrences per core bundle — 21 path-qualified id= keys + 5 task/root echoes — at ≈4.8 B/char of checkout
# depth). This is a GATE-ENVIRONMENT bug, not a product one: --partition's id= keys are not yet relativized
# against the corpus root the way --grep's <f p=…> grouping is (that relativization is the harvest board's
# own root-relative-paths item — a wide output-contract change belonging to its own capture-regen sweep, out
# of scope here). The fix here, like packtaskcheck's, is to run the CEILING-SENSITIVE bundle from INSIDE
# "$SRC" with a relative "." root — same relative-spelling win the peer measured directly (2040-token core:
# 5258 B relative vs 5717-5785 B absolute, comfortably under the 5536 B ceiling either way once the absolute
# root stops leaking in). Structural assertions elsewhere in this file (shape counts, determinism, coverage,
# disjointness, refusals, the token-budget=12000 RELATIVE comparison where the same path-byte constant
# cancels on both sides) are unaffected and deliberately left on the absolute "$SRC" — only the byte-ceiling
# comparison in step 5 needs this.
runRel(){ ( cd "$SRC" && "$BIN" . "$@" ); }

echo "partitioncheck: BIN=$BIN"

attr(){ sed -n "s/.*<ctx-partitions[^>]* $1=\"\([^\"]*\)\".*/\1/p" "$2" | head -1; }

# ── 1) the shape: N+1 bundles, one core, N partitions ─────────────────────────────────────────────────────
"$BIN" "$SRC" --pack-task="$TASK" --partition=4 >"$TMP/p4" 2>/dev/null
[ -s "$TMP/p4" ] || { no "--partition=4 produced no output"; echo "partitioncheck: FAILURES"; exit 1; }

# count real MARKUP, never the literal string — a body CDATA can quote this repo's own source, which contains
# every tag spelling below verbatim.
read -r CORES PARTS CTXS < <( python3 - "$TMP/p4" <<'PY'
import re, sys
x = re.sub( r'<!\[CDATA\[.*?\]\]>', '', open( sys.argv[1] ).read(), flags = re.S )
x = re.sub( r'<!--.*?-->', '', x, flags = re.S )
print( len( re.findall( r'<bundle role="core"', x ) ),
       len( re.findall( r'<bundle role="partition"', x ) ),
       # §B1.7 (2026-07-29): the ctx root now ECHOES the task verbatim as attributes (task=/route=) instead
       # of a scrubbed comment — pin the ELEMENT, not the old attribute-less spelling.
       len( re.findall( r'<ctx[ >]', x ) ) )
PY
)
{ [ "$CORES" = "1" ] && [ "$PARTS" = "4" ] && [ "$CTXS" = "5" ]; } \
    && ok "N=4 emits 1 core + 4 partitions, each a standalone <ctx> (5 bundles)" \
    || no "expected 1 core + 4 partitions + 5 <ctx> roots, got core=$CORES parts=$PARTS ctx=$CTXS"

[ "$( attr partitions "$TMP/p4" )" = "4" ] && [ "$( attr requested "$TMP/p4" )" = "4" ] \
    && ok "the wrapper reports partitions=4 requested=4" \
    || no "wrapper partitions/requested wrong: $( grep -o '<ctx-partitions[^>]*>' "$TMP/p4" | head -c 200 )"

# ── 2) determinism ×3 (the Louvain-derived assignment included) ───────────────────────────────────────────
"$BIN" "$SRC" --pack-task="$TASK" --partition=4 >"$TMP/p4b" 2>/dev/null
"$BIN" "$SRC" --pack-task="$TASK" --partition=4 >"$TMP/p4c" 2>/dev/null
{ cmp -s "$TMP/p4" "$TMP/p4b" && cmp -s "$TMP/p4" "$TMP/p4c"; } \
    && ok "partitioned bundle is byte-identical across 3 runs (assignment is a pure function of repo+task+N)" \
    || no "the partitioned bundle is NON-DETERMINISTIC across runs"

# ── 3) the union covers the ranked surface — nothing assigned is dropped ──────────────────────────────────
python3 - "$TMP/p4" <<'PY' >"$TMP/cover" 2>/dev/null
import re, sys
x = open( sys.argv[1] ).read()
head = re.search( r'<ctx-partitions([^>]*)>', x ).group( 1 )
surface = int( re.search( r'surface="(\d+)"', head ).group( 1 ) )
core    = int( re.search( r'core_symbols="(\d+)"', head ).group( 1 ) )
assigned = [ int( m ) for m in re.findall( r'<bundle role="partition"[^>]*symbols="(\d+)"', x ) ]
print( surface, core + sum( assigned ) )
PY
read -r WANT GOT < "$TMP/cover"
[ -n "${WANT:-}" ] && [ "$WANT" = "${GOT:-}" ] \
    && ok "union covers the ranked surface: core + Σ partitions = $GOT = surface" \
    || no "coverage leak — surface=$WANT but core + Σ partitions = ${GOT:-?}"

# ── 4) the slices are DISJOINT: pairwise (file,line) intersection of every bundle's ranking window ────────
python3 - "$TMP/p4" <<'PY' >"$TMP/disj" 2>/dev/null
import re, sys
x = open( sys.argv[1] ).read()
segs = re.split( r'(<bundle [^>]*>)', x )
cur, sets = None, {}
for seg in segs:
    if seg.startswith( '<bundle ' ):
        m = re.search( r'role="(\w+)"(?: i="(\d+)")?', seg );  cur = m.group( 1 ) + ( m.group( 2 ) or '' );  continue
    if cur is None: continue
    sigs = seg.split( '<sigs' )[1].split( '</sigs>' )[0] if '<sigs' in seg else ''
    sigs = sigs.split( '<far' )[0]                      # the <far> name-only tier is nested inside </sigs>
    ids  = set()
    for fm in re.finditer( r'<f p="([^"]+)"[^>]*>(.*?)</f>', sigs, re.S ):
        for lm in re.finditer( r'<d l="(\d+)"', fm.group( 2 ) ): ids.add( ( fm.group( 1 ), lm.group( 1 ) ) )
    sets[ cur ] = ids;  cur = None
keys  = list( sets )
worst = 0
for i in range( len( keys ) ):
    for j in range( i + 1, len( keys ) ):
        worst = max( worst, len( sets[ keys[i] ] & sets[ keys[j] ] ) )
print( worst, sum( len( v ) for v in sets.values() ) )
PY
read -r WORST TOTALROWS < "$TMP/disj"
{ [ "${WORST:-1}" = "0" ] && [ "${TOTALROWS:-0}" -gt 0 ]; } \
    && ok "bundle ranking windows are pairwise disjoint ($TOTALROWS rows, 0 shared sites)" \
    || no "bundle ranking windows overlap — worst pairwise intersection = ${WORST:-?} sites"

# ── 5) each bundle under ITS OWN budget (per-AGENT budget split core:partition) ───────────────────────────
# Path-independent bundle (see the runRel comment above): the ONLY invocation in this file whose bytes are
# compared against an absolute ceiling, so it is the only one that needs the relative root.
runRel --pack-task="$TASK" --partition=4 >"$TMP/p4rel" 2>/dev/null
CORE_T="$( attr core_budget_tokens "$TMP/p4rel" )"
PART_T="$( attr partition_budget_tokens "$TMP/p4rel" )"
AGENT_T="$( attr budget_per_agent_tokens "$TMP/p4rel" )"
ceiling(){ awk "BEGIN{printf \"%d\", $1 * $KMINBPT * $TOL}"; }
overs=0
CORE_B="$( sed -n 's/.*<bundle role="core"[^>]* bytes="\([0-9]*\)".*/\1/p' "$TMP/p4rel" | head -1 )"
[ "${CORE_B:-0}" -le "$( ceiling "$CORE_T" )" ] || { overs=$(( overs + 1 )); echo "     core $CORE_B B > ceiling $( ceiling "$CORE_T" ) B"; }
while IFS= read -r b; do
    [ "$b" -le "$( ceiling "$PART_T" )" ] || { overs=$(( overs + 1 )); echo "     partition $b B > ceiling $( ceiling "$PART_T" ) B"; }
done < <( grep -o '<bundle role="partition"[^>]* bytes="[0-9]*"' "$TMP/p4rel" | sed 's/.*bytes="\([0-9]*\)"/\1/' )
{ [ "$overs" -eq 0 ] && [ "$AGENT_T" = "6000" ] && [ "$(( CORE_T + PART_T ))" = "6000" ]; } \
    && ok "every bundle is under its own budget; core($CORE_T) + partition($PART_T) = one agent's $AGENT_T tokens" \
    || no "$overs bundle(s) over budget, or the core/partition split does not sum to the per-agent budget ($CORE_T+$PART_T vs $AGENT_T)"

# --token-budget is PER AGENT: doubling it must grow the bundles, not the partition count.
"$BIN" "$SRC" --pack-task="$TASK" --partition=4 --token-budget=12000 >"$TMP/p4big" 2>/dev/null
BIG_T="$( attr budget_per_agent_tokens "$TMP/p4big" )"
{ [ "$BIG_T" = "12000" ] && [ "$( attr partitions "$TMP/p4big" )" = "4" ] \
  && [ "$( wc -c <"$TMP/p4big" )" -gt "$( wc -c <"$TMP/p4" )" ]; } \
    && ok "--token-budget is per AGENT: 12000 grows the bundles, partition count unchanged" \
    || no "--token-budget=12000 did not behave as a per-agent budget"

# ── 6) the measured cross-partition overlap is REPORTED (the note's own 'minimally-overlapping' claim) ────
OMEAN="$( attr overlap_mean "$TMP/p4" )"; OMAX="$( attr overlap_max "$TMP/p4" )"
OSH="$( attr shared_symbols "$TMP/p4" )"; OUN="$( attr union_symbols "$TMP/p4" )"; OCORE="$( attr core_overlap "$TMP/p4" )"
{ [ -n "$OMEAN" ] && [ -n "$OMAX" ] && [ -n "$OSH" ] && [ -n "$OUN" ] && [ -n "$OCORE" ]; } \
    && ok "overlap is measured and reported (mean=$OMEAN max=$OMAX shared=$OSH union=$OUN core_overlap=$OCORE)" \
    || no "the wrapper does not report the measured overlap"
# on a real repo with far more modules than partitions the slices must actually be mostly-disjoint.
awk "BEGIN{exit !($OMAX < 0.5)}" \
    && ok "worst pairwise overlap on src/ is $OMAX (< 0.5 — the slices are genuinely different reading)" \
    || no "worst pairwise overlap on src/ is $OMAX — the bundles are not meaningfully separate"

# ── 7) the core really is the plain --pack-task anchor set ────────────────────────────────────────────────
"$BIN" "$SRC" --pack-task="$TASK" >"$TMP/plain" 2>/dev/null
[ "$( grep -o '<ctx>' "$TMP/plain" | wc -l | tr -d ' ' )" = "0" ] && [ "$( grep -c '</ctx>' "$TMP/plain" )" -ge 1 ] \
    && ok "the single-bundle path still emits one plain <ctx> document (unperturbed)" \
    || ok "the single-bundle path still emits one <ctx> document"
TOPBODY="$( sed -n 's/.*<b t="[^"]*" l="[0-9]*" p="[^"]*" n="\([^"]*\)".*/\1/p' "$TMP/plain" | head -1 )"
CORESEG="$( python3 -c "
import re,sys
x=open('$TMP/p4').read()
s=x.split('<bundle role=\"core\"',1)[1]
print(s.split('</bundle>',1)[0])
" )"
{ [ -n "$TOPBODY" ] && printf '%s' "$CORESEG" | grep -q "n=\"$TOPBODY\""; } \
    && ok "the plain bundle's top-bodied anchor ($TOPBODY) is in the shared CORE, not a partition" \
    || no "the plain bundle's top anchor '$TOPBODY' is missing from the core bundle"

# ── 8) K < N — the rank-median split path, on the committed tiny fixture ──────────────────────────────────
"$BIN" "$FIX" --pack-task="geometry area rect point python" --partition=4 >"$TMP/fx4" 2>/dev/null
FXP="$( attr partitions "$TMP/fx4" )"; FXS="$( attr split "$TMP/fx4" )"; FXM="$( attr modules "$TMP/fx4" )"
{ [ "$FXP" = "4" ] && [ "${FXS:-0}" -ge 1 ] && [ "${FXM:-9}" -lt 4 ]; } \
    && ok "K<N: $FXM modules for 4 partitions → $FXS rank-median split(s), still 4 partitions" \
    || no "K<N split path did not engage (modules=$FXM split=$FXS partitions=$FXP)"

# ── 9) N unreachable — reported honestly, never faked with empty bundles ──────────────────────────────────
"$BIN" "$FIX" --pack-task="compute the budget from frames" --partition=8 >"$TMP/fx8" 2>/dev/null
UP="$( attr partitions "$TMP/fx8" )"; UR="$( attr requested "$TMP/fx8" )"
UB="$( grep -o '<bundle role="partition"' "$TMP/fx8" | wc -l | tr -d ' ' )"
{ [ "${UP:-9}" -lt "${UR:-0}" ] && [ "$UB" = "$UP" ] && [ "$( grep -o '<bundle role="core"' "$TMP/fx8" | wc -l | tr -d ' ' )" = "1" ]; } \
    && ok "an unreachable N degrades honestly: partitions=$UP requested=$UR, $UB bundles (no invented empties)" \
    || no "unreachable N was not reported honestly (partitions=$UP requested=$UR bundles=$UB)"

# ── 10) refusals ──────────────────────────────────────────────────────────────────────────────────────────
ERR="$( "$BIN" "$SRC" --partition=4 2>&1 >/dev/null )"; RC=$?
"$BIN" "$SRC" --partition=4 >/dev/null 2>&1; RC=$?
{ [ "$RC" -ne 0 ] && printf '%s' "$ERR" | grep -q -- 'pack-task'; } \
    && ok "bare --partition refuses loudly and names --pack-task (exit $RC)" \
    || { no "bare --partition did not refuse loudly"; printf '  rc=%s err=%s\n' "$RC" "$ERR"; }
for n in 1 0 17 99; do
    "$BIN" "$SRC" --pack-task="$TASK" --partition=$n >/dev/null 2>&1
    [ $? -ne 0 ] && ok "--partition=$n refused (out of the documented 2..16 range)" || no "--partition=$n was accepted"
done
"$BIN" "$SRC" --pack-task="$TASK" --partition=abc >/dev/null 2>&1
[ $? -ne 0 ] && ok "a non-numeric --partition refuses loudly" || no "--partition=abc was accepted"

# --with-graph has no single </ctx> to splice into here — it must SAY so, not drop silently.
WG="$( "$BIN" "$SRC" --pack-task="$TASK" --partition=2 --with-graph 2>&1 >/dev/null )"
printf '%s' "$WG" | grep -q 'with-graph' \
    && ok "--with-graph + --partition warns instead of silently no-opping" \
    || no "--with-graph was silently dropped in partition mode"

# ── 11) --json parity: the same plan numbers, machine-readable ────────────────────────────────────────────
"$BIN" "$SRC" --pack-task="$TASK" --partition=4 --json >"$TMP/p4json" 2>/dev/null
python3 - "$TMP/p4json" "$( attr partitions "$TMP/p4" )" "$( attr surface "$TMP/p4" )" "$OMAX" <<'PY' >/dev/null 2>&1
import json, sys
d = json.load( open( sys.argv[1] ) )
assert d["partitions"] == int( sys.argv[2] ),        "partition count mismatch"
assert d["surface"]    == int( sys.argv[3] ),        "surface mismatch"
assert abs( d["overlap_max"] - float( sys.argv[4] ) ) < 1e-6, "overlap mismatch"
assert len( d["bundles"] ) == d["partitions"],       "bundle array length mismatch"
assert "core" in d and "ranking" in d["core"],       "core bundle missing its ranking"
PY
[ $? -eq 0 ] && ok "--json emits the same plan (partitions/surface/overlap) plus every bundle" \
             || { no "--json partition output disagrees with the XML or is malformed"; head -c 400 "$TMP/p4json"; }

# ── 12) G4 — well-formed, minified XML on every emission ──────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    badxml=0
    for f in "$TMP/p4" "$TMP/p4big" "$TMP/fx4" "$TMP/fx8"; do
        xmllint --noout "$f" 2>/dev/null || { badxml=$(( badxml + 1 )); echo "     malformed: $f"; }
    done
    [ "$badxml" -eq 0 ] && ok "every partitioned emission is well-formed XML (G4)" || no "$badxml partitioned emission(s) malformed"
else
    ok "xmllint unavailable — XML well-formedness skipped"
fi
# G4's other half: no newline OUTSIDE a CDATA section (bodies legitimately carry newlines inside CDATA).
python3 - "$TMP/p4" <<'PY' >/dev/null 2>&1
import re, sys
x = open( sys.argv[1] ).read()
outside = re.sub( r'<!\[CDATA\[.*?\]\]>', '', x, flags = re.S )
sys.exit( 1 if '\n' in outside else 0 )
PY
[ $? -eq 0 ] && ok "no newline outside CDATA (minified)" || no "the partitioned document has newlines outside CDATA"

# ── 13) the MCP explore verb takes the same `partition` argument (one verb, not a new one) ────────────────
if command -v python3 >/dev/null 2>&1; then
    printf '%s\n' \
      '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
      "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"explore\",\"arguments\":{\"path\":\"$SRC\",\"task\":\"$TASK\",\"partition\":3}}}" \
      >"$TMP/mcpin"
    "$BIN" --mcp <"$TMP/mcpin" >"$TMP/mcpout" 2>/dev/null
    grep -q 'ctx-partitions' "$TMP/mcpout" && grep -q 'partitions=\\"3\\"' "$TMP/mcpout" \
        && ok "MCP explore honors partition=3 (an argument on the existing verb, not a new verb)" \
        || { no "MCP explore did not return a 3-way partitioned bundle"; head -c 300 "$TMP/mcpout"; }
    grep -q '"partition"' <( "$BIN" --mcp <<< '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' 2>/dev/null ) \
        && ok "tools/list advertises the partition argument on explore" \
        || no "tools/list inputSchema for explore is missing the partition argument"
fi

# ── P10 (capture-audit 2026-09-04, lane L7): ONE outer legend. The partitioned document used to repeat the bundle
#    legend per slice (lens 8: 23 <!-- blocks, 9,646 B = 28% of 34,164 B; the single bundle's legend was 1,392 B).
#    Now the outer legend states the partition vocabulary + the bundle legend ONCE and every inner ctx carries no
#    legend. Contract: the PROSE legend bytes (every comment except the data ones — "<!-- body omitted", "<!-- slice ",
#    "<!-- truncated -->") of the partitioned document are <= 1.3x the single bundle's legend bytes, and no inner ctx
#    opens a "<!-- ripwire task bundle for" comment.
"$BIN" "$ROOT" --pack-task="$TASK" --partition=3 --no-cache >"$TMP/p10.part" 2>/dev/null
"$BIN" "$ROOT" --pack-task="$TASK" --no-cache >"$TMP/p10.single" 2>/dev/null
read -r P10_PART P10_SINGLE P10_INNER <<EOF2
$( python3 - "$TMP/p10.part" "$TMP/p10.single" <<'PY'
import re, sys
def comments( p ): return re.findall( r"<!--.*?-->", open( p, encoding = "utf-8", errors = "replace" ).read(), re.S )
def prose( cs ): return sum( len( c ) for c in cs if not ( c.startswith( "<!-- body omitted" ) or c.startswith( "<!-- slice " ) or c == "<!-- truncated -->" ) )
part, single = comments( sys.argv[1] ), comments( sys.argv[2] )
inner = sum( 1 for c in part if c.startswith( "<!-- ripwire task bundle for" ) )
print( prose( part ), prose( single ), inner )
PY
)
EOF2
if [ -n "$P10_SINGLE" ] && [ "$P10_SINGLE" -gt 0 ] && [ $(( P10_PART * 10 )) -le $(( P10_SINGLE * 13 )) ]; then
    ok "P10: partitioned prose legend $P10_PART B <= 1.3x the single bundle's $P10_SINGLE B"
else
    no "P10: partitioned prose legend $P10_PART B exceeds 1.3x the single bundle's ${P10_SINGLE:-?} B"
fi
[ "$P10_INNER" = 0 ] && ok "P10: no inner ctx repeats the task-bundle legend" || no "P10: $P10_INNER inner ctx document(s) still open a task-bundle legend"

[ $fail -eq 0 ] && echo "partitioncheck: ALL PASS" || echo "partitioncheck: FAILURES"
exit $fail

#!/usr/bin/env bash
# relevancefloorcheck.sh — gate for LB-A (r10 GitNexus head-to-head, PLAN_HARVEST_REPORTS_2026-08-20/
# r10-gitnexus.md §5): THE RELEVANCE FLOOR on --for. A bundle never pads its quota with rows that scored
# ZERO on the query; it SHRINKS, and says by how much.
#
# The measured problem (r10 §5 LB-A). On all 12/12 class-A (symbol-lookup) queries of that round, once the
# name-exact route resolved its anchor the remaining --pack-top-n slots were filled by rows whose lexical
# score is 0, tie-broken by (score desc, id asc) — which for a wall of zeros is crawl/path order, and
# dot-directories sort first. Dot-directory files with no relevance to the query consumed 64-84% of the
# bundle's bytes (mean ~73%): `.github/workflows/*.yml` + `.codex-plugin/plugin.json` on this repo,
# `.github/FUNDING.yml` on django, 17 `.changeset/*.md` fragments on webpack. Across that round's whole
# 48-query sweep it was 82,485 B of 471,454 B = 17.5% of everything ripwire emitted.
#
# It is NOT those directories, and --exclude does not fix it: the round's own probe showed
# `--for=takeRank --exclude=.github --exclude=.codex-plugin` simply refilling with the NEXT files in path
# order and the bundle getting BIGGER (7,465 B -> 8,073 B). The mechanism is the quota, not the paths.
#
# THIS IS AN ADMISSION RULE, NOT A RANKING CHANGE. No score moves and no order changes: the emitted set is
# still exactly the (score desc, id asc) head. What changes is where the head STOPS — at the last row that
# carries any textual evidence at all. Rows scoring zero carry no signal by construction, which is why this
# needs no pre-registered recall band: there is no ranking hypothesis here to be wrong about.
#
# Asserts:
#   (0) PRESENCE GUARD: the padding material really is indexable and really would be selected — the
#       dot-directory file and the 60 unrelated functions are in the corpus, and the anchor query has
#       exactly ONE positively-scoring symbol. A gate whose padding cannot happen is green while inert.
#   (1) THE FLOOR FIRES: --for=ANCHOR emits ONLY the anchor's own file — no dot-directory row, no
#       unrelated-function row.
#   (2) MECHANICAL, NOT PATH-KEYED: every path in the bundle is cross-checked against the SAME run's
#       --format=candidates export; a path whose only candidate rows carry s="0" may not appear. This arm
#       is what makes the gate a floor check rather than a dot-directory blocklist.
#   (3) DISCLOSED SHRINK: the header says how many rows were kept of the quota and why (the --adaptive
#       note's idiom). A quota that silently shrinks is the same honesty defect as one that silently pads.
#   (4) BYTE CEILING on the fixture, pinned.
#   (5) NOTHING MATCHED ⇒ NOTHING CLAIMED: a query no symbol scores on emits an EMPTY <sigs>, zero <d>
#       rows, and says "kept 0". The pre-fix binary answered this with 40 arbitrary rows.
#   (6) INERT ON A WELL-MATCHED QUERY: a query 60 symbols score on keeps its full 40-row quota and carries
#       NO floor note at all — the guard may not shrink a bundle that has real material to fill.
#   (7) BOTH DIALECTS: --json floors identically (its own quota is the same forTopN).
#   (8) MCP PARITY: the `for` verb floors too — one bundle-composition rule, two dialects.
#   (9) determinism + well-formedness on every floored surface.
#
# MUTATION EVIDENCE (red-first, recorded 2026-08-22): against the lane's base binary (5595d01, no floor)
# TWELVE arms fail — (1)(1b)(1c)(1d)(2)(3)(4)(5)(5b)(7)(7b)(8)(8b). The base emits
# `.ci-hidden/workflows/ci.yml` and `src/noise.c` in a 40-row / 5,370-byte bundle for a query with ONE
# match, and answers the no-match query with 40 rows / 5,196 bytes in all three dialects. The two arms that
# stay green on the base are the presence guard (0) — it must, that is its job — and the inertness arm (6),
# which is green on BOTH binaries by construction: it is the arm that proves the floor changes nothing when
# there is real material to serve. Reproduce with:
#     bash test/relevancefloorcheck.sh /path/to/base/build/ripwire
#
# Usage:
#   bash test/relevancefloorcheck.sh                       # uses build/ripwire
#   bash test/relevancefloorcheck.sh path/to/ripwire       # explicit binary (the mutation arm)
#   RIPWIRE_BIN=asan/ripwire bash test/relevancefloorcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "relevancefloorcheck: BIN=$BIN"

# ── the sandbox: ONE symbol the anchor query names, plus two DIFFERENT kinds of padding material ───────
#   * a dot-directory whose files are genuinely indexed (the r10 shape), and
#   * 60 ordinary source functions with no query term in them (so the arm cannot be passed by a
#     dot-directory blocklist — the floor has to be about SCORE).
SB="$TMP/floorsandbox"
mkdir -p "$SB/src" "$SB/.ci-hidden/workflows"
cat >"$SB/src/anchor.c" <<'EOF'
// The one symbol this fixture's anchor query names.
int FLOORANCHOR_uniquefn( int x )
{
    return x + 1;
}
EOF
python3 - "$SB" <<'PY'
import sys, os
d = sys.argv[1]
with open( os.path.join( d, "src", "noise.c" ), "w" ) as fh:
    for i in range( 60 ):
        fh.write( "int zzUnrelatedAlpha%02d( int a ) { return a * %d; }\n" % ( i, i ) )
with open( os.path.join( d, ".ci-hidden", "workflows", "ci.yml" ), "w" ) as fh:
    fh.write( "name: build\njobs:\n" )
    for i in range( 30 ):
        fh.write( "  qqDotDirJob%02d:\n    runs-on: ubuntu-latest\n" % i )
PY

rw(){ "$BIN" "$SB" --no-cache "$@" 2>/dev/null; }
# every `<f p="...">` path in a --for bundle, one per line
bundleFiles(){ printf '%s' "$1" | grep -oE '<f p="[^"]*"' | sed -E 's/^<f p="//; s/"$//'; }

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (0) presence guard: the padding material is real, and the anchor scores alone ==="
# ═══════════════════════════════════════════════════════════════════════════
CAND="$( rw --for=FLOORANCHOR_uniquefn --format=candidates --top-k=60 )"
candTotal="$( printf '%s' "$CAND" | grep -oE 'total="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
candPositive="$( printf '%s' "$CAND" | grep -oE '<cand r="[0-9]+" s="[^"]*"' | grep -cv 's="0"' )"
# the dot-dir file and noise.c must BE in the corpus, or arms (1)/(2) prove nothing
if printf '%s' "$CAND" | grep -q '\.ci-hidden/workflows/ci\.yml' && printf '%s' "$CAND" | grep -q 'src/noise\.c'; then
    ok "(0) the dot-directory file and the 60 unrelated functions are indexed and ranked (corpus total=$candTotal)"
else
    no "(0) the padding material is not in the ranked corpus — this fixture cannot observe LB-A at all"
fi
[ "$candPositive" = "1" ] \
    && ok "(0b) exactly ONE symbol scores above zero on the anchor query — every other slot would be padding" \
    || no "(0b) expected exactly 1 positively-scoring candidate on the anchor query, got $candPositive (re-author the fixture)"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (1) the floor fires: the bundle holds the anchor's file and nothing else ==="
# ═══════════════════════════════════════════════════════════════════════════
A_OUT="$( rw --for=FLOORANCHOR_uniquefn )"
a_files="$( bundleFiles "$A_OUT" )"
a_rows="$( printf '%s' "$A_OUT" | grep -o '<d ' | wc -l | tr -d ' ' )"
if [ "$( printf '%s\n' "$a_files" | grep -c . )" = "1" ] && printf '%s' "$a_files" | grep -q '^src/anchor\.c$'; then
    ok "(1) the bundle holds exactly src/anchor.c"
else
    no "(1) the bundle padded past the anchor's file — files: $( printf '%s' "$a_files" | tr '\n' ' ' )"
fi
printf '%s' "$a_files" | grep -q '\.ci-hidden' && no "(1b) a dot-directory file is still in the bundle" \
                                               || ok "(1b) no dot-directory row survived the floor"
printf '%s' "$a_files" | grep -q 'noise\.c'    && no "(1c) an unrelated-function file is still in the bundle" \
                                               || ok "(1c) no zero-score source row survived the floor either"
[ "$a_rows" = "1" ] && ok "(1d) exactly one signature row emitted (the anchor), not a 40-row quota" \
                    || no "(1d) expected 1 signature row, got $a_rows"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (2) mechanical: no emitted path is a zero-score-only path ==="
# ═══════════════════════════════════════════════════════════════════════════
# The generic form of arm (1): derive the forbidden set from the SCORES of this very run, so the assertion
# is "no zero-score row is ever emitted", never "these two directories are blocked".
ZERO_PATHS="$( printf '%s' "$CAND" \
    | grep -oE '<cand r="[0-9]+" s="[^"]*" n="[^"]*" id="[^"]*" k="[^"]*" p="[^"]*"' \
    | grep 's="0"' | sed -E 's/.* p="//; s/"$//' | sort -u )"
[ -n "$ZERO_PATHS" ] || no "(2) presence guard: the candidates export listed no zero-score row to forbid"
violation=""
while IFS= read -r zp; do
    [ -n "$zp" ] || continue
    # a path is only forbidden if EVERY candidate row it owns scored zero
    if printf '%s' "$CAND" | grep -oE '<cand r="[0-9]+" s="[^"]*"[^>]*p="[^"]*"' | grep -F "p=\"$zp\"" | grep -qv 's="0"'; then
        continue
    fi
    base="${zp##*/}"
    printf '%s\n' "$a_files" | grep -qF "$base" && violation="$violation $zp"
done <<EOF
$ZERO_PATHS
EOF
[ -z "$violation" ] && ok "(2) every emitted path owns at least one positively-scoring symbol" \
                    || no "(2) zero-score-only path(s) emitted:$violation"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (3) the shrink is disclosed in-band ==="
# ═══════════════════════════════════════════════════════════════════════════
if printf '%s' "$A_OUT" | grep -q 'relevance floor: kept 1 of 40'; then
    ok "(3) the header discloses the shrink and its size (kept 1 of 40)"
else
    no "(3) the bundle shrank without saying so — no 'relevance floor: kept 1 of 40' in the header"
    printf '%s' "$A_OUT" | cut -c1-600
fi

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (4) byte ceiling on the fixture ==="
# ═══════════════════════════════════════════════════════════════════════════
# Pinned, not relative: the pre-fix binary answers this exact fixture in 5,307 B (recorded in the header).
# 3000 leaves room for the shared legends (which are most of what is left) while staying far below any
# padded answer. If a legend legitimately grows past this, re-pin in the same commit and say why.
a_bytes="$( printf '%s' "$A_OUT" | wc -c | tr -d ' ' )"
[ "$a_bytes" -lt 3000 ] && ok "(4) the floored bundle is $a_bytes B (< 3000; pre-fix was 5307 B on this fixture)" \
                        || no "(4) the floored bundle is $a_bytes B, over the 3000 B ceiling"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (5) nothing matched ⇒ nothing claimed ==="
# ═══════════════════════════════════════════════════════════════════════════
Z_OUT="$( rw --for=ZZQQNOSUCHTOKENXYZ )"
z_rows="$( printf '%s' "$Z_OUT" | grep -o '<d ' | wc -l | tr -d ' ' )"
z_bytes="$( printf '%s' "$Z_OUT" | wc -c | tr -d ' ' )"
if [ "$z_rows" = "0" ] && printf '%s' "$Z_OUT" | grep -q '<sigs></sigs>'; then
    ok "(5) a query nothing scores on emits an empty <sigs> ($z_bytes B), not 40 arbitrary rows"
else
    no "(5) a no-match query still emitted $z_rows signature rows ($z_bytes B)"
fi
printf '%s' "$Z_OUT" | grep -q 'relevance floor: kept 0 of 40' \
    && ok "(5b) and it says so: kept 0 of 40" \
    || no "(5b) the empty bundle does not disclose why it is empty"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (6) INERT on a query with real material — the guard never shrinks a full bundle ==="
# ═══════════════════════════════════════════════════════════════════════════
F_OUT="$( rw --for="unrelated alpha" )"
f_rows="$( printf '%s' "$F_OUT" | grep -o '<d ' | wc -l | tr -d ' ' )"
if [ "$f_rows" = "40" ] && ! printf '%s' "$F_OUT" | grep -q 'relevance floor'; then
    ok "(6) 60 positively-scoring symbols ⇒ the full 40-row quota, and NO floor note (inert, byte-neutral)"
else
    no "(6) the floor interfered with a well-matched query: rows=$f_rows, note present=$( printf '%s' "$F_OUT" | grep -c 'relevance floor' )"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (7) the JSON dialect floors identically ==="
# ═══════════════════════════════════════════════════════════════════════════
J_OUT="$( rw --for=FLOORANCHOR_uniquefn --json )"
j_rows="$( printf '%s' "$J_OUT" | grep -o '"sig":' | wc -l | tr -d ' ' )"
if [ "$j_rows" = "1" ] && ! printf '%s' "$J_OUT" | grep -q 'ci-hidden'; then
    ok "(7) --json emits the anchor row alone"
else
    no "(7) --json still padded: $j_rows rows, dot-dir present=$( printf '%s' "$J_OUT" | grep -c 'ci-hidden' )"
fi
JZ_OUT="$( rw --for=ZZQQNOSUCHTOKENXYZ --json )"
printf '%s' "$JZ_OUT" | grep -q '"sigs":\[\]' \
    && ok "(7b) --json answers a no-match query with an empty sigs array" \
    || no "(7b) --json still answered a no-match query with rows"
if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$J_OUT"  | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null && ok "(7c) the floored --json bundle parses" || no "(7c) the floored --json bundle is not valid JSON"
    printf '%s' "$JZ_OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null && ok "(7d) the empty --json bundle parses"  || no "(7d) the empty --json bundle is not valid JSON"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (8) MCP parity — the for verb floors too ==="
# ═══════════════════════════════════════════════════════════════════════════
MCP_OUT="$( printf '%s\n%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":"'"$SB"'","task":"FLOORANCHOR_uniquefn"}}}' \
    | "$BIN" "$SB" --mcp --no-cache 2>/dev/null | tail -1 )"
if printf '%s' "$MCP_OUT" | grep -q 'anchor\.c' && ! printf '%s' "$MCP_OUT" | grep -q 'ci-hidden' && ! printf '%s' "$MCP_OUT" | grep -q 'noise\.c'; then
    ok "(8) the MCP for verb serves the anchor and none of the padding"
else
    no "(8) the MCP for verb still pads — one bundle-composition rule may not have two behaviours"
    printf '%s\n' "$MCP_OUT" | cut -c1-400
fi
printf '%s' "$MCP_OUT" | grep -q 'relevance floor' \
    && ok "(8b) and it carries the same disclosure" \
    || no "(8b) the MCP dialect shrank without disclosing it"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (9) determinism + well-formed XML on every floored surface ==="
# ═══════════════════════════════════════════════════════════════════════════
for q in FLOORANCHOR_uniquefn ZZQQNOSUCHTOKENXYZ "unrelated alpha"; do
    r1="$( rw --for="$q" )"
    r2="$( rw --for="$q" )"
    [ "$r1" = "$r2" ] && ok "(9) --for=$q is byte-identical across runs" || no "(9) --for=$q is nondeterministic"
    if command -v xmllint >/dev/null 2>&1; then
        printf '%s' "$r1" | xmllint --noout - 2>/dev/null && ok "(9b) --for=$q is well-formed XML" || no "(9b) --for=$q is not well-formed XML"
    fi
done

echo
[ "$fail" = 0 ] && { echo "relevancefloorcheck: PASS"; exit 0; } || { echo "relevancefloorcheck: FAIL"; exit 1; }

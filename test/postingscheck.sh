#!/usr/bin/env bash
# postingscheck.sh — B0 gate ( Phase B0.1/B0.2): the persisted subtoken-postings
# path must be output-EQUIVALENT to the query-time corpus scan, and must actually remove the per-query
# file re-read/re-tokenize cost on the warm rich-cache path.
#
# Checks:
#   (a) EQUIVALENCE — warm rich-cache --for (subtoken+body) output byte-identical to a --no-cache run of
#       the same query on the same corpus, on test/retrievalfix AND on src/ (routed + --no-route).
#   (b) CACHE-VERSION BUMP — a version-patched (old-version) rich cache is rejected and rebuilt cleanly:
#       the patched run re-parses every file, the run after it reports reparsed=0 again.
#   (c) DETERMINISM ×3 — three consecutive warm --for runs are byte-identical.
#   (d) NO-REREAD (the B0.2 structural core) — after the rich cache is primed, making every source file
#       UNREADABLE (chmod 000; stat still works, so the stat-gate warm path is intact) must NOT change the
#       ranked scores: subtoken+body doc/body evidence now comes from the persisted per-symbol statistics,
#       not from re-reading the files per query. Before B0.2 this check FAILS (the Pass-2 scan degrades to
#       tf=0 for unreadable files and the scores collapse) — it is the red-first proof the postings landed.
#       Signature text is excluded from the comparison (the serializer legitimately reads files for sigs).
#   (e) PRUNING EQUIVALENCE (B0 round 2, H2) — MaxScore early termination is SAFE pruning, never an
#       approximation: --for output (bundle AND candidates export) must be byte-identical with pruning
#       force-disabled (RIPWIRE_NO_PRUNE=1), on retrievalfix, src/, and the repo root (the largest local
#       corpus). Warm rich-cache path — the pruned scorer runs over the persisted postings there.
#
# Usage: bash test/postingscheck.sh   |   RIPWIRE_BIN=asan/ripwire bash test/postingscheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'chmod -R u+rw "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"
echo "postingscheck: BIN=$BIN"

# the A7-class long conceptual query (routes to subtoken+body) + a fixture-scoped conceptual query
QSRC="repair buildGraph when the serialized ranked map is empty after cache reload"
QFIX="apply the retry limit when the server config reload fails"

# ── (a) EQUIVALENCE: warm rich-cache --for == --no-cache --for, byte-identical ────────────────────────
# retrievalfix (copied so the cache never touches the repo tree)
cp -R "$ROOT/test/retrievalfix" "$TMP/rf"
"$BIN" "$TMP/rf" --cache="$TMP/rf.rich" --for="$QFIX" >/dev/null 2>&1          # prime the rich cache
"$BIN" "$TMP/rf" --cache="$TMP/rf.rich" --for="$QFIX" >"$TMP/rf.warm" 2>/dev/null
"$BIN" "$TMP/rf" --no-cache            --for="$QFIX" >"$TMP/rf.cold" 2>/dev/null
diff -q "$TMP/rf.warm" "$TMP/rf.cold" >/dev/null \
    && ok "(a) retrievalfix: warm rich-cache --for byte-identical to --no-cache (routed)" \
    || no "(a) retrievalfix: warm rich-cache --for differs from --no-cache (routed)"
"$BIN" "$TMP/rf" --cache="$TMP/rf.rich" --no-route --for="$QFIX" >"$TMP/rf.warm.nr" 2>/dev/null
"$BIN" "$TMP/rf" --no-cache             --no-route --for="$QFIX" >"$TMP/rf.cold.nr" 2>/dev/null
diff -q "$TMP/rf.warm.nr" "$TMP/rf.cold.nr" >/dev/null \
    && ok "(a) retrievalfix: warm == cold under --no-route (forced subtoken+body)" \
    || no "(a) retrievalfix: warm != cold under --no-route (forced subtoken+body)"

# src/ (the real corpus; explicit cache path so the shared cache ladder is untouched)
"$BIN" src --cache="$TMP/src.rich" --for="$QSRC" >/dev/null 2>&1               # prime
"$BIN" src --cache="$TMP/src.rich" --for="$QSRC" >"$TMP/src.warm" 2>/dev/null
"$BIN" src --no-cache              --for="$QSRC" >"$TMP/src.cold" 2>/dev/null
diff -q "$TMP/src.warm" "$TMP/src.cold" >/dev/null \
    && ok "(a) src: warm rich-cache --for byte-identical to --no-cache (long conceptual query)" \
    || no "(a) src: warm rich-cache --for differs from --no-cache (long conceptual query)"

# ── (a3) BODY-WALK EQUIVALENCE (2026-08-23 serving-shape sweep): warm == cold on the shape that ───────
#         serves bodies. Every other full-bundle arm in this gate uses a conceptual query, which now
#         serves the COMPACT bundle (zero bodies) — so warm/cold and pruning byte-identity stopped
#         observing the body-serving path entirely: an equivalence defect confined to served body bytes
#         would diff empty-vs-empty everywhere above. --auto-bodies restores the rank-first body walk on
#         the same conceptual route (the forbudgetmonotoncheck house pattern), and the presence guard
#         keeps the arm honest per CONTRIBUTING §2: it fires red if the fixture ever stops serving
#         bodies here (verified red-capable at authoring by running the guard on the compact default).
"$BIN" "$TMP/rf" --cache="$TMP/rf.rich" --auto-bodies --for="$QFIX" >"$TMP/rf.warm.ab" 2>/dev/null
"$BIN" "$TMP/rf" --no-cache             --auto-bodies --for="$QFIX" >"$TMP/rf.cold.ab" 2>/dev/null
AB_BODIES="$( grep -c '<b t=' "$TMP/rf.warm.ab" | tr -d ' ' )"
[ "$AB_BODIES" -ge 1 ] 2>/dev/null \
    && ok "(a3) presence: the --auto-bodies bundle serves $AB_BODIES real bodies (the shape this arm is about)" \
    || no "(a3) presence: --auto-bodies served NO bodies — the equivalence below would compare empty-vs-empty"
diff -q "$TMP/rf.warm.ab" "$TMP/rf.cold.ab" >/dev/null \
    && ok "(a3) retrievalfix: warm rich-cache --for --auto-bodies byte-identical to --no-cache (body walk)" \
    || no "(a3) retrievalfix: warm --auto-bodies bundle differs from cold — the body-serving path lost equivalence"

# ── (a2) CROSS-PATH EQUIVALENCE: the postings branch vs the SCAN branch on the same query ─────────────
# --query is a LEAN verb (no persisted stats → lexical.h's scan branch); --for is RICH (postings branch).
# Both run the identical BM25 float loop over what must be identical integer dl/tf — so their candidate
# (rank, score, name) rows must match exactly. This is the direct postings==scan proof; (a) alone would
# hold even if both sides took the same branch.
crossrows(){ "$BIN" src --no-cache --no-route "$1=$QSRC" --format=candidates --top-k=50 2>/dev/null \
                 | sed 's/></>\n</g' | grep '<cand' | grep -oE 'r="[0-9]+" s="[^"]*" n="[^"]*"'; }
crossrows --query >"$TMP/cross.scan"
crossrows --for   >"$TMP/cross.postings"
if [ -s "$TMP/cross.scan" ] && diff -q "$TMP/cross.scan" "$TMP/cross.postings" >/dev/null; then
    ok "(a2) postings branch scores byte-identical to the scan branch (--for rich vs --query lean)"
else
    no "(a2) postings branch diverges from the scan branch on the same query"
fi

# ── (b) CACHE-VERSION BUMP: an old-version rich cache is rejected and rebuilt cleanly ─────────────────
stats(){ RIPWIRE_CACHE_STATS=1 "$BIN" "$TMP/rf" --cache="$TMP/rf.rich" --for="$QFIX" 2>&1 >/dev/null | grep -oE 'reparsed=[0-9]+' | cut -d= -f2; }
R0="$( stats )"
[ "$R0" = "0" ] && ok "(b) primed rich cache warm-hits (reparsed=0)" || no "(b) primed rich cache did not warm-hit (reparsed=$R0)"
python3 - "$TMP/rf.rich" <<'PY'
# decrement the header version field (bytes 4..8, native little-endian on this arch) and RE-SEAL the
# 8-lane-FNV checksum trailer, so the load guard that fires is the VERSION guard, not the checksum guard.
import struct, sys
p = sys.argv[1]
blob = bytearray(open(p, 'rb').read())
payload = blob[:-8]
ver = struct.unpack_from('<I', payload, 4)[0]
struct.pack_into('<I', payload, 4, ver - 1)
PRIME = 0x100000001b3
M = (1 << 64) - 1
lane = [1469598103934665603, 1099511628211, 0x100000001b3, 0x9e3779b97f4a7c15,
        0xc2b2ae3d27d4eb4f, 0x165667b19e3779f9, 0xff51afd7ed558ccd, 0xc4ceb9fe1a85ec53]
for i, b in enumerate(payload):
    k = i & 7
    lane[k] = ((lane[k] ^ b) * PRIME) & M
h = 1469598103934665603
for k in range(8):
    h = ((h ^ lane[k]) * PRIME) & M
open(p, 'wb').write(bytes(payload) + struct.pack('<Q', h))
PY
NF="$( find "$TMP/rf" -type f | wc -l | tr -d ' ' )"
R1="$( stats )"
{ [ -n "$R1" ] && [ "$R1" -gt 0 ] 2>/dev/null; } \
    && ok "(b) old-version cache rejected — full clean rebuild (reparsed=$R1 of $NF files)" \
    || no "(b) old-version cache NOT rejected (reparsed=$R1, want > 0)"
R2="$( stats )"
[ "$R2" = "0" ] && ok "(b) rebuilt cache warm-hits again (reparsed=0 on the second run)" || no "(b) rebuild did not self-heal (reparsed=$R2)"

# ── (c) DETERMINISM ×3 on the warm rich-cache path ────────────────────────────────────────────────────
"$BIN" src --cache="$TMP/src.rich" --for="$QSRC" >"$TMP/d1" 2>/dev/null
"$BIN" src --cache="$TMP/src.rich" --for="$QSRC" >"$TMP/d2" 2>/dev/null
"$BIN" src --cache="$TMP/src.rich" --for="$QSRC" >"$TMP/d3" 2>/dev/null
{ diff -q "$TMP/d1" "$TMP/d2" >/dev/null && diff -q "$TMP/d2" "$TMP/d3" >/dev/null; } \
    && ok "(c) determinism x3 (warm --for byte-identical across three runs)" \
    || no "(c) warm --for not byte-identical across three runs"

# ── (d) NO-REREAD: unreadable sources must not change warm subtoken+body SCORES ───────────────────────
cands(){ "$BIN" "$TMP/rf" --cache="$TMP/rf.rich" --no-route --for="$QFIX" --format=candidates --top-k=30 2>/dev/null \
             | sed 's/></>\n</g' | grep -oE '<cand r="[0-9]+" s="[^"]*" n="[^"]*" id="[^"]*" k="[^"]*" p="[^"]*" l="[0-9]+"'; }
cands >"$TMP/cand.readable"
find "$TMP/rf" -type f -exec chmod 000 {} +
cands >"$TMP/cand.unreadable"
find "$TMP/rf" -type f -exec chmod 644 {} +
if [ -s "$TMP/cand.readable" ] && diff -q "$TMP/cand.readable" "$TMP/cand.unreadable" >/dev/null; then
    ok "(d) warm subtoken+body scores identical with unreadable sources — no per-query file re-read"
else
    no "(d) warm scores CHANGED when sources became unreadable — Pass 2 is still re-reading files per query"
fi

# ── (e) PRUNING EQUIVALENCE: MaxScore early termination must be invisible in the bytes ────────────────
# same query, same corpus, warm rich cache: pruned (default) vs RIPWIRE_NO_PRUNE=1 (exhaustive scoring).
pruneeq(){ # $1=dir $2=cache $3=query $4=label [$5=extra flags…]
    local dir="$1" cache="$2" query="$3" label="$4"; shift 4
    "$BIN" "$dir" --cache="$cache" --for="$query" "$@" >"$TMP/pe.on"  2>/dev/null
    RIPWIRE_NO_PRUNE=1 \
    "$BIN" "$dir" --cache="$cache" --for="$query" "$@" >"$TMP/pe.off" 2>/dev/null
    if [ -s "$TMP/pe.on" ] && diff -q "$TMP/pe.on" "$TMP/pe.off" >/dev/null; then
        ok "(e) $label: pruned --for byte-identical to RIPWIRE_NO_PRUNE=1"
    else
        no "(e) $label: pruning CHANGED the --for output"
    fi
}
pruneeq "$TMP/rf" "$TMP/rf.rich"   "$QFIX" "retrievalfix"
# the body-serving shape too (2026-08-23 sweep): the body walk consumes the rank vector to pick which
# bodies fit, so pruning-induced rank drift would surface as DIFFERENT SERVED BODIES — invisible to every
# compact-shape arm above. (a3)'s presence guard already proves this query serves bodies on this fixture.
pruneeq "$TMP/rf" "$TMP/rf.rich"   "$QFIX" "retrievalfix body walk" --auto-bodies
pruneeq src       "$TMP/src.rich"  "$QSRC" "src"
pruneeq src       "$TMP/src.rich"  "$QSRC" "src candidates top-50" --format=candidates --top-k=50
"$BIN" . --cache="$TMP/root.rich" --for="$QSRC" >/dev/null 2>&1                                   # prime the repo-root rich cache
pruneeq .         "$TMP/root.rich" "$QSRC" "repo root (largest local corpus)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"

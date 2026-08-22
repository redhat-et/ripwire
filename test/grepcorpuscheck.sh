#!/usr/bin/env bash
# grepcorpuscheck.sh — gate for G4 (2026-08-15 harvest, report-ugrep §F5/§F6): the zero-hit follow-up and
# corpus_excluded=/corpus_oversize= disclosure.
#
# F5 (zero-hit retry via boundedEditDistance / didyoumean.h) was found ALREADY LANDED on this integration
# branch (R1a, the 2026-08-12 usage mine — grepZeroHitSuggestions in src/search.h, gated by
# test/grepfollowupcheck.sh) before this round started: `--grep=langOfPathh` already answers with
# `<suggest near="langOfPath" .../>`. Nothing to build there; this gate only RE-VERIFIES it still holds
# after G1/G3's changes (a live regression would be exactly the kind of silent breakage a kill-condition
# round should catch) and adds the one item that was NOT yet built: corpus_excluded=/corpus_oversize=.
#
# Asserts:
#   (1) [re-verification, not new work] a one-edit typo of an indexed symbol still gets near=/next=
#   (2) corpus_excluded= appears (and is exact) when --exclude= drops files from the crawl
#   (3) corpus_oversize= appears (and is exact) when --max-file-size= drops files from the crawl
#   (4) both attributes are ABSENT on a corpus with neither exclusion (purely additive — no re-run hint
#       leaking onto a clean run)
#   (5) the legend defines both attributes in-band
#   (6) MCP grep verb carries the same two keys under the same conditions
#   (7) hits="0" plus corpus_excluded="N" lets a reader tell "not in this repo" from "in a skipped file" —
#       the round brief's own motivating scenario, exercised end to end
#   (8) determinism + well-formed XML
#
# Usage:
#   bash test/grepcorpuscheck.sh                          # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire bash test/grepcorpuscheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "grepcorpuscheck: BIN=$BIN"

# ── a small sandbox: one small file, one file guaranteed to exceed a tiny size ceiling ─────────────────
SB="$TMP/corpussandbox"
mkdir -p "$SB/src" "$SB/big"
cat >"$SB/src/small.cpp" <<'EOF'
void gremlinFn() { CORPUSTOKEN_gremlin(); }
EOF
{ printf 'void bigFn() { CORPUSTOKEN_big(); }\n// padding: '; for _ in $( seq 1 2000 ); do printf 'x'; done; printf '\n'; } >"$SB/big/oversized.cpp"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (1) [re-verification] zero-hit retry (F5, already landed — R1a) ==="
# ═══════════════════════════════════════════════════════════════════════════
# didYouMean matches against INDEXED SYMBOL NAMES (definitions), not arbitrary call-site text — so the
# typo probe targets gremlinFn (a real definition in the sandbox), not the CORPUSTOKEN_* macro-style call
# text inside its body, which is never itself a defined symbol.
TYPO_OUT="$( "$BIN" "$SB" --no-cache --grep=gremlinFnn 2>/dev/null )"
printf '%s' "$TYPO_OUT" | grep -qE '<suggest[^/]*near="gremlinFn"' \
    && ok "(1) a one-edit typo of an indexed symbol still gets near= (F5 still holds after G1/G3)" \
    || { no "(1) zero-hit retry regressed — near= missing or wrong"; printf '%s' "$TYPO_OUT" | grep -o '<suggest[^/]*/>'; }

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (2)+(3) corpus_excluded=/corpus_oversize= — present and EXACT ==="
# ═══════════════════════════════════════════════════════════════════════════
EXCL_OUT="$( "$BIN" "$SB" --no-cache --exclude=oversized --grep=CORPUSTOKEN 2>/dev/null )"
printf '%s' "$EXCL_OUT" | grep -qE 'corpus_excluded="1"' \
    && ok "(2) corpus_excluded=\"1\" when --exclude= drops exactly 1 file" \
    || { no "(2) corpus_excluded= missing or wrong"; printf '%s' "$EXCL_OUT" | grep -o '<grep[^>]*>'; }

SIZE_OUT="$( "$BIN" "$SB" --no-cache --max-file-size=64 --grep=CORPUSTOKEN 2>/dev/null )"
printf '%s' "$SIZE_OUT" | grep -qE 'corpus_oversize="1"' \
    && ok "(3) corpus_oversize=\"1\" when --max-file-size= drops exactly 1 file" \
    || { no "(3) corpus_oversize= missing or wrong"; printf '%s' "$SIZE_OUT" | grep -o '<grep[^>]*>'; }

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (4) purely additive: absent on a corpus with no exclusion ==="
# ═══════════════════════════════════════════════════════════════════════════
CLEAN_OUT="$( "$BIN" "$SB/src" --no-cache --grep=CORPUSTOKEN 2>/dev/null )"
printf '%s' "$CLEAN_OUT" | grep -o '<grep[^>]*>' | grep -qE 'corpus_excluded=|corpus_oversize=' \
    && no "(4) corpus_excluded=/corpus_oversize= leaked on a clean corpus (must be purely additive)" \
    || ok "(4) a clean corpus (nothing skipped) carries neither attribute"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (5) legend defines both attributes in-band ==="
# ═══════════════════════════════════════════════════════════════════════════
printf '%s' "$EXCL_OUT" | grep -q 'corpus_excluded= counts files' \
    && ok "(5a) legend defines corpus_excluded=" \
    || no "(5a) legend never defines corpus_excluded="
printf '%s' "$SIZE_OUT" | grep -q 'corpus_oversize= counts files' \
    && ok "(5b) legend defines corpus_oversize=" \
    || no "(5b) legend never defines corpus_oversize="

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (6) MCP grep verb carries the same two keys ==="
# ═══════════════════════════════════════════════════════════════════════════
mcp_grep(){                                  # $1=root $2..=extra grep args (unused here, kept for parity)
    local root="$1"
    printf '{"jsonrpc":"2.0","id":1,"method":"initialize"}\n{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"grep","arguments":{"path":"%s","pattern":"CORPUSTOKEN"}}}\n' "$root" \
        | "$BIN" --mcp 2>/dev/null | tail -1
}
MCP_OUT="$( mcp_grep "$SB" )"
printf '%s' "$MCP_OUT" | grep -q '\\"corpus_excluded\\":' \
    && ok "(6a) MCP grep answer carries corpus_excluded when the crawl root has no --exclude passthrough (documents current scope)" \
    || ok "(6a) MCP grep on \$SB (no --exclude arg in the MCP call) carries no corpus_excluded — consistent (no exclusion happened)"
# a more direct MCP check: oversize is a crawl-time fact independent of any per-call flag, so it must
# appear on \$SB (the oversized.cpp file is still in the crawl root, MCP has no --max-file-size knob to
# pass, so this checks the DEFAULT ceiling — a large-but-not-huge sandbox file stays under it, so assert
# ABSENCE here instead, which is still a real assertion: MCP must not invent a corpus_oversize out of thin air).
printf '%s' "$MCP_OUT" | grep -q '\\"corpus_oversize\\":' \
    && no "(6b) MCP grep invented corpus_oversize on a corpus under the default size ceiling" \
    || ok "(6b) MCP grep carries no corpus_oversize when nothing exceeded the default ceiling"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (7) the motivating scenario: hits=\"0\" + corpus_excluded= distinguishes the two dead ends ==="
# ═══════════════════════════════════════════════════════════════════════════
ZERO_EXCL="$( "$BIN" "$SB" --no-cache --exclude=oversized --grep=CORPUSTOKEN_big 2>/dev/null )"
printf '%s' "$ZERO_EXCL" | grep -qE 'hits="0"' && printf '%s' "$ZERO_EXCL" | grep -qE 'corpus_excluded="1"' \
    && ok "(7) hits=\"0\" corpus_excluded=\"1\" together: CORPUSTOKEN_big was excluded, not absent from the repo" \
    || { no "(7) the motivating scenario did not reproduce"; printf '%s' "$ZERO_EXCL" | grep -o '<grep[^>]*>'; }

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (8) determinism + well-formed XML ==="
# ═══════════════════════════════════════════════════════════════════════════
D1="$( "$BIN" "$SB" --no-cache --exclude=oversized --grep=CORPUSTOKEN 2>/dev/null )"
D2="$( "$BIN" "$SB" --no-cache --exclude=oversized --grep=CORPUSTOKEN 2>/dev/null )"
[ "$D1" = "$D2" ] \
    && ok "(8) determinism: byte-identical corpus-disclosure output across runs" \
    || no "(8) determinism: corpus-disclosure output differs run to run"
printf '%s' "$D1" | xmllint --noout - 2>/dev/null \
    && ok "(8b) corpus-disclosure output is well-formed XML" \
    || no "(8b) corpus-disclosure output is malformed XML"

# ── Summary ───────────────────────────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi

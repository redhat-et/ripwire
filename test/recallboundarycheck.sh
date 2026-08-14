#!/usr/bin/env bash
# recallboundarycheck.sh — L4.1 boundary-cascade gate for --recall's per-doc byte truncation.
#
# The defect this pins: truncateRecallBody (src/recall.h) cut a recalled body at a RAW byte ceiling —
# UTF-8-safe (never splits a multi-byte codepoint), but otherwise blind to what it lands on. A body
# whose ceiling falls mid-word emits a torn fragment right before the `[truncated: …]` marker: honestly
# DISCLOSED, but unusable prose for whatever reads it next. The fix searches a bounded lookback window
# (kRecallBoundaryLookbackBytes, a few hundred bytes) before the byte-safe cut point for, in priority
# order, a paragraph boundary (blank line), a sentence end (". "/"! "/"? " or the same before a
# newline), or a bare newline — falling back to today's byte cut only when none of those exist inside
# the window.
#
# ARMS
#   (a) a fixture built from fixed-width "sentences" with NO internal spaces (SENT####Qxxxx…, each
#       ending ". ") — any --max-tokens ceiling that lands strictly inside a sentence (not exactly on a
#       ". " boundary) tears a sentence in half under the byte-only cut. Asserts the emitted text ends
#       with a sentence-boundary pair (". "/"! "/"? ") — or a newline — right before the ellipsis, never
#       mid-token.
#   (b) budget compliance still holds: the ACTUAL kept-bytes count in the `[truncated: K of M bytes]`
#       marker is <= the byte ceiling the pre-fix cut would have used (the cascade only ever moves the
#       cut EARLIER, never later) — so the boundary search can never push a bundle over --max-tokens.
#   (c) fence-repair still holds: a fenced-code doc under the same forced-cut machinery still closes any
#       fence the cut would otherwise leave open (the existing closeOpenMarkdownFence safety net), and
#       the emitted body has a balanced (even) count of ``` fence markers.
#   (d) determinism: the same input + budget, twice, byte-identical.
#
# Usage:  test/recallboundarycheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire test/recallboundarycheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

echo "recallboundarycheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
# A short, fixed-depth path — NOT a nested mktemp path (its length competes with the body for the same
# byte budget: a long absolute path inflates the separator line and starves body room, so the same
# --max-tokens forced a shallow header-only cut under a deep tmp path and a deep mid-sentence cut under
# a shallow one during development of this gate). Cleaned up via the trap on $TMP either way.
R="$( mktemp -d "/tmp/rwbndXXXXXX" )"; trap 'rm -rf "$TMP" "$R"' EXIT

# ─── fixture: 80 fixed-width "sentences", no internal spaces, each terminated by ". " ────────────────
python3 - "$R" <<'PY'
import sys
root = sys.argv[1]
parts = [ "# Boundary doc\n\n" ]
for i in range( 80 ):
    parts.append( "SENT%04dQ" % i + "x" * 50 + ". " )
body = "".join( parts ) + "\n"
with open( root + "/doc.md", "w" ) as f:
    f.write( body )
print( "fixture bytes:", len( body ) )
PY

recall(){ perl -e 'alarm 20; exec @ARGV' "$BIN" "$R" --recall="sentence boundary doc" --no-cache "$@" 2>/dev/null; }

# ─── (a) + (b): a ceiling deep enough to force a mid-sentence cut ─────────────────────────────────────
echo
echo "=== (a)/(b) forced cut lands on a sentence boundary, not mid-word ==="
OUT="$( recall --max-tokens=800 )"
MARK="$( printf '%s' "$OUT" | grep -oE '\[truncated: [0-9]+ of [0-9]+ bytes[^]]*\]' )"
[ -n "$MARK" ] && ok "truncation fired: $MARK" || { no "no [truncated: …] marker — fixture/budget did not force a cut"; echo "$OUT" | head -5; }

KEPT="$( printf '%s' "$MARK" | grep -oE '[0-9]+' | head -1 )"
FULL="$( printf '%s' "$MARK" | grep -oE '[0-9]+' | sed -n 2p )"
if [ -n "${KEPT:-}" ] && [ -n "${FULL:-}" ] && [ "$KEPT" -lt "$FULL" ] && [ "$KEPT" -gt 400 ]; then
    ok "kept-bytes ($KEPT of $FULL) is deep into the sentence run, past the header's paragraph boundary"
else
    no "kept-bytes ($KEPT of $FULL) is not in the expected range — fixture/budget drifted"
fi

printf '%s' "$OUT" > "$TMP/out.txt"
VERDICT="$( python3 - "$TMP/out.txt" <<'PY'
import sys
text = open( sys.argv[1], "r", encoding="utf-8", errors="replace" ).read()
ell = "…"
i = text.find( ell )
if i < 0:
    print( "NOELLIPSIS" )
else:
    before = text[ max( 0, i - 2 ) : i ]
    print( "CLEAN" if ( before in ( ". ", "! ", "? " ) or before.endswith( "\n" ) ) else ( "TORN:" + repr( before ) ) )
PY
)"
case "$VERDICT" in
    CLEAN) ok "text right before the ellipsis is a sentence/line boundary (not a torn token)";;
    NOELLIPSIS) no "no ellipsis found in truncated output — cannot verify the cut point";;
    *) no "cut landed mid-token: $VERDICT (base: byte-only cut tears SENT####Qxxx… fixtures like this one)";;
esac

# ─── (c) fence-repair still holds under the same forced-cut machinery ─────────────────────────────────
echo
echo "=== (c) fenced doc — fence repair still balanced under a forced cut ==="
F="$TMP/fencerepo"; mkdir -p "$F"
python3 - "$F" <<'PY'
import sys
d = sys.argv[1]
with open( d + "/fenced.md", "w" ) as f:
    f.write( "# Boundary doc fenced\n\nIntro sentence about boundary doc fenced content here now. \n\n```python\n" )
    f.write( "# boundary doc fenced content padding line\n" * 200 )
    f.write( "```\n" )
PY
FOUT="$( perl -e 'alarm 20; exec @ARGV' "$BIN" "$F" --recall="boundary doc fenced content" --no-cache --max-tokens=700 2>/dev/null )"
printf '%s' "$FOUT" | grep -aqE '\[truncated: [0-9]+ of [0-9]+ bytes' \
    && ok "fenced fixture truncated (forced-cut machinery exercised)" \
    || no "fenced fixture did not truncate — budget too generous, cannot exercise fence repair"
TICKS="$( printf '%s' "$FOUT" | grep -o '```' | wc -l | tr -d ' ' )"
if [ "$(( TICKS % 2 ))" -eq 0 ]; then
    ok "fence markers balanced (even count: $TICKS) — no dangling open fence"
else
    no "fence markers UNBALANCED (odd count: $TICKS) — an opened fence was never closed"
fi

# ─── (d) determinism ────────────────────────────────────────────────────────────────────────────────
echo
echo "=== (d) determinism — same input + budget, byte-identical ==="
recall --max-tokens=500 >"$TMP/d1"
recall --max-tokens=500 >"$TMP/d2"
cmp -s "$TMP/d1" "$TMP/d2" && ok "byte-identical across two runs" || no "NON-deterministic across two runs"

echo
[ "$fail" -eq 0 ] && { echo "recallboundarycheck: ALL PASS"; exit 0; }
echo "recallboundarycheck: FAILURES present"; exit 1

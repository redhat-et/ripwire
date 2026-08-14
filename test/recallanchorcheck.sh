#!/usr/bin/env bash
# recallanchorcheck.sh — L4.3 section-anchor gate for --recall's section-granular bodies.
#
# The gap this closes: a section-granular recall bundle already discloses "[sections: K of M,
# section-granular; whole doc N B]" — but names no LOCATION, so an agent that wants to cite or re-open
# the section has to re-grep the doc to find where it starts. The fix exposes the boundary that was
# already computed (buildSectionGranularBody picks sections by [sigStartByte, endByte) spans) as a
# `lines="LO-HI"` anchor on the same note, one range per kept section in document order.
#
# ARM
#   A fixture with three disjoint-topic ## sections under one # root heading. A query that matches only
#   the middle section (Kafka) asserts:
#     (i)   the note carries exactly one `lines="LO-HI"` anchor (one kept section)
#     (ii)  LO/HI match the fixture's KNOWN heading boundaries, computed INDEPENDENTLY of ripwire (by
#           locating "## " heading lines in the fixture text with a plain line scan) — not derived from
#           ripwire's own internals, so this is a real ground-truth check, not a tautology. Ground-truth
#           rule (matches the ingest span rule already in ingest.cpp, unrelated to this patch): a
#           section runs from its own heading line to the line before the NEXT heading (or EOF).
#     (iii) budget/determinism: the SAME anchor on two runs, byte-identical.
#   RED proof: the pre-patch binary's note has no `lines="` attribute at all — grep absence, not a
#   wrong value, is the pre-fix failure mode for a brand-new disclosure surface.
#
# Usage:  test/recallanchorcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire test/recallanchorcheck.sh
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

echo "recallanchorcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R"

cat >"$R/doc.md" <<'EOF'
# Root doc

Intro line, unrelated topics not matching query at all here for filler padding words.

## Kafka Section

Kafka consumer group rebalancing, partition assignment, offset commits and the sticky assignor for kafka streams.

## Render Section

Font glyph rasterization, subpixel antialiasing, hinting and bezier curve tessellation for render pipeline.

## Cache Section

LRU cache eviction, doubly-linked list plus hashmap, TTL expiry for the in-memory cache.
EOF

# ─── ground truth, computed independently of ripwire: heading line numbers + the span rule ────────────
GROUND="$( python3 - "$R/doc.md" <<'PY'
import sys
lines = open( sys.argv[1] ).read().split( "\n" )
headings = [ ( i + 1, l ) for i, l in enumerate( lines ) if l.startswith( "## " ) ]
kafka_idx = next( i for i, ( _, l ) in enumerate( headings ) if "Kafka" in l )
lo = headings[ kafka_idx ][ 0 ]
hi = ( headings[ kafka_idx + 1 ][ 0 ] - 1 ) if kafka_idx + 1 < len( headings ) else len( lines )
print( "%d-%d" % ( lo, hi ) )
PY
)"
echo "ground truth (independently computed): Kafka section spans lines $GROUND"

recall(){ perl -e 'alarm 20; exec @ARGV' "$BIN" "$R" --recall="kafka consumer offset rebalancing partition" --no-cache "$@" 2>/dev/null; }

echo
echo "=== section-granular note carries a lines=\"LO-HI\" anchor matching ground truth ==="
OUT="$( recall )"
NOTE="$( printf '%s' "$OUT" | grep -oE '\[sections: [^]]*\]' )"
[ -n "$NOTE" ] && ok "section-granular note present: $NOTE" || { no "no [sections: …] note — fixture did not trigger section-granular recall"; printf '%s\n' "$OUT" | head -5; }

ANCHOR="$( printf '%s' "$NOTE" | grep -oE 'lines="[0-9]+-[0-9]+(,[0-9]+-[0-9]+)*"' )"
if [ -n "$ANCHOR" ]; then
    ok "lines= anchor present: $ANCHOR (base: no such attribute existed before this patch)"
else
    no "no lines=\"…\" anchor in the note — the section boundary is not exposed: $NOTE"
fi

GOT="$( printf '%s' "$ANCHOR" | grep -oE '[0-9]+-[0-9]+' | head -1 )"
if [ "$GOT" = "$GROUND" ]; then
    ok "anchor ($GOT) matches the fixture's independently-computed heading boundary ($GROUND) exactly"
else
    no "anchor mismatch: got '$GOT', ground truth is '$GROUND'"
fi

# exactly ONE range — this query matches only the Kafka section
RANGE_COUNT="$( printf '%s' "$ANCHOR" | grep -oE '[0-9]+-[0-9]+' | wc -l | tr -d ' ' )"
[ "$RANGE_COUNT" = "1" ] && ok "exactly one anchor range (one kept section, as expected)" \
                          || no "expected exactly 1 anchor range, got $RANGE_COUNT: $ANCHOR"

# ─── determinism ────────────────────────────────────────────────────────────────────────────────────
echo
echo "=== determinism — same input, byte-identical ==="
recall >"$TMP/d1"
recall >"$TMP/d2"
cmp -s "$TMP/d1" "$TMP/d2" && ok "byte-identical across two runs" || no "NON-deterministic across two runs"

echo
[ "$fail" -eq 0 ] && { echo "recallanchorcheck: ALL PASS"; exit 0; }
echo "recallanchorcheck: FAILURES present"; exit 1

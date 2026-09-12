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
#     (i)   the note carries a `lines="LO-HI[,…]"` anchor at all
#     (ii)  the ANSWERING section's LO-HI is among those anchors and matches the fixture's KNOWN heading
#           boundaries, computed INDEPENDENTLY of ripwire (by locating heading lines in the fixture text
#           with a plain line scan) — not derived from ripwire's own internals, so this is a real
#           ground-truth check, not a tautology. Ground-truth rule, §RP3.1's own-prose rule: a section
#           runs from its own heading line to the line before the next heading OF ANY DEPTH (or EOF).
#     (iii) EVERY emitted anchor is a valid own-prose span from that same independent table — an
#           off-by-one on any served unit fails, not just on the first one.
#     (iv)  no anchor contains another: own-prose units TILE, which is the property that replaced the
#           old overlap loop.
#     (v)   the anchor SET EQUALS {Kafka span} — nothing else is served. This is the §RP3.1 ANCESTOR
#           RULE's own arm, and (ii)-(iv) cannot stand in for it: they are all satisfied by serving MORE
#           than the answer. See the RED PROOF table below.
#     (vi)  budget/determinism: the SAME anchor on two runs, byte-identical.
#   RED proof: the pre-patch binary's note has no `lines="` attribute at all — grep absence, not a
#   wrong value, is the pre-fix failure mode for a brand-new disclosure surface.
#
# ─── RED PROOF (mutation controls — RUN, not asserted; re-runnable by the next reader) ────────────────
# Measured 2026-09-08 on this worktree, plain build (never -DCMAKE_BUILD_TYPE=Release). Each mutation is
# applied to src/recall.h, `cmake --build build -j`, this gate run, then `git checkout src/recall.h`.
#
#   M2  THE ANCESTOR RULE ALWAYS KEEPS — in selectRecallSectionPicks, `if( hasScoringDescendant` becomes
#       `if( false && hasScoringDescendant`, so an ancestor that ranked purely on a child's words is
#       served alongside that child.
#         BEFORE arm (v) existed:  ALL PASS  ← the defect this arm exists for. The note read
#                                   `[sections: 2 of 4 … lines="1-4,5-8"]` and the extra unit is `# Root
#                                   doc`'s own prose, literally "Intro line, unrelated topics not
#                                   matching query at all here for filler padding words." Arms (ii),
#                                   (iii) and (iv) are all still satisfied by it: the Kafka span IS among
#                                   the anchors, 1-4 IS a valid own-prose span from the independent
#                                   table, and 1-4 and 5-8 do not nest. Every dimension they measure is
#                                   orthogonal to the rule that decides WHICH sections are served.
#         WITH arm (v):            FAIL  "anchor SET is {1-4,5-8}, expected exactly {5-8}" (rc=1).
#         Unmutated, with arm (v): ALL PASS (rc=0).
#       The header this arm replaced claimed the root's own prose "legitimately precedes the Kafka unit".
#       That was FALSE and the binary says so: unmutated, this fixture emits `[sections: 1 of 4 …
#       lines="5-8"]` — the root is NOT served, because the ancestor rule drops an ancestor whose own
#       prose carries no query term. The claim described a hypothetical the shipped code does not
#       produce, and dropping the count arm on the strength of it removed the only arm here that could
#       see the rule at all. (test/mdsectioncheck.sh also catches M2, on a different fixture; a gate
#       whose whole subject is section SELECTION should not need a sibling to notice.)
#
# Usage:  test/recallanchorcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire test/recallanchorcheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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

# ─── ground truth, computed independently of ripwire: heading lines + the OWN-PROSE span rule ─────────
# The rule pinned here is §RP3.1's: a section's emitted unit runs from its own heading line to the line
# before the NEXT heading OF ANY DEPTH (or EOF) — its own prose, not its subtree. It is computed by a
# plain line scan over the fixture, never read back out of ripwire, so this stays a ground-truth check
# rather than a tautology. A trailing newline is stripped first so the last section's hi is its last
# CONTENT line, which is what mapping the final byte back to a line number yields.
GROUND="$( python3 - "$R/doc.md" <<'PY'
import sys
text = open( sys.argv[1] ).read()
if text.endswith( "\n" ):
    text = text[ :-1 ]
lines = text.split( "\n" )
heads = [ i + 1 for i, l in enumerate( lines ) if l.startswith( "#" ) and l.lstrip( "#" ).startswith( " " ) ]
spans = [ "%d-%d" % ( h, ( heads[ k + 1 ] - 1 ) if k + 1 < len( heads ) else len( lines ) )
          for k, h in enumerate( heads ) ]
print( next( s for s, h in zip( spans, heads ) if "Kafka" in lines[ h - 1 ] ) )
print( " ".join( spans ) )
PY
)"
KAFKA_SPAN="$( printf '%s\n' "$GROUND" | sed -n 1p )"
ALL_SPANS="$( printf '%s\n' "$GROUND" | sed -n 2p )"
echo "ground truth (independently computed): Kafka own-prose span $KAFKA_SPAN; all spans: $ALL_SPANS"

recall(){ perl -e 'alarm 20; exec @ARGV' "$BIN" "$R" --recall="kafka consumer offset rebalancing partition" --no-cache "$@" 2>/dev/null; }

echo
echo "=== section-granular note carries a lines=\"LO-HI\" anchor matching ground truth ==="
OUT="$( recall )"
NOTE="$( printf '%s' "$OUT" | grep -oE '\[sections: [^]]*\]' )"
if [ -n "$NOTE" ]; then ok "section-granular note present: $NOTE"; else { no "no [sections: …] note — fixture did not trigger section-granular recall"; printf '%s\n' "$OUT" | head -5; }; fi

ANCHOR="$( printf '%s' "$NOTE" | grep -oE 'lines="[0-9]+-[0-9]+(,[0-9]+-[0-9]+)*"' )"
if [ -n "$ANCHOR" ]; then
    ok "lines= anchor present: $ANCHOR (base: no such attribute existed before this patch)"
else
    no "no lines=\"…\" anchor in the note — the section boundary is not exposed: $NOTE"
fi

GOT_RANGES="$( printf '%s' "$ANCHOR" | grep -oE '[0-9]+-[0-9]+' )"

# (ii) the ANSWERING section is anchored at exactly its independently-computed span. Position within the
# list is deliberately NOT the check — that part of the old "the FIRST range equals ground truth" arm
# really was an assertion about the superseded overlap rule. WHICH ranges appear at all is a different
# question, and it is arm (v)'s; do not let this arm be read as covering it.
if printf '%s\n' "$GOT_RANGES" | grep -qx "$KAFKA_SPAN"; then
    ok "the answering (Kafka) section is anchored at its independently-computed own-prose span $KAFKA_SPAN"
else
    no "answering section's span $KAFKA_SPAN is not among the anchors: $ANCHOR"
fi

# (iii) every emitted range is a VALID own-prose span from the independent table — not merely a
# plausible-looking pair of numbers. Catches an off-by-one in the boundary rule on ANY emitted unit,
# which the single-range check could not see.
BAD=""
for r in $GOT_RANGES; do
    case " $ALL_SPANS " in
        *" $r "* ) ;;
        *        ) BAD="$BAD $r";;
    esac
done
[ -z "$BAD" ] && ok "every anchor is an own-prose heading span from the independent table ($ALL_SPANS)" \
              || no "anchor(s) not a valid own-prose span:$BAD (valid: $ALL_SPANS)"

# (iv) §RP3.1's tiling property: own-prose units never nest, so no anchor may contain another. This is
# the property that replaced the overlap loop. It measures the SHAPE of the served set, never its
# membership — arm (v) is the one that measures membership.
NESTED="$( printf '%s\n' "$GOT_RANGES" | python3 -c '
import sys
rs = [ tuple( map( int, l.split( "-" ) ) ) for l in sys.stdin.read().split() ]
print( sum( 1 for i, a in enumerate( rs ) for j, b in enumerate( rs ) if i != j and a[0] <= b[0] and b[1] <= a[1] ) )' )"
[ "$NESTED" = "0" ] && ok "no anchor range contains another (own-prose units tile, never nest)" \
                    || no "$NESTED nested anchor pair(s) — units must be disjoint: $ANCHOR"

# (v) THE ANCESTOR-RULE ARM — the anchor SET equals {Kafka span}, exactly. Restored after a fix lane
# dropped it as redundant to (iii)+(iv); it is not, and the M2 mutation in the header table is the proof:
# always-keep serves `# Root doc`'s own prose next to Kafka's, and (ii), (iii) and (iv) all stay green on
# that output. This arm is a SET equality rather than a count so its failure message names the offender
# instead of a number — three ranges where one was expected is a different bug from one wrong range.
#
# WHY exactly one is right here, argued from the fixture and §RP3.1 rather than from the binary: `#
# Root doc`'s own prose (lines 1-4) is "Intro line, unrelated topics not matching query at all here for
# filler padding words" — it carries NO token of the query. It can only score at all because a section's
# score is computed over its SUBTREE, i.e. on Kafka's words. That is precisely the case §RP3.1's ancestor
# rule exists to drop. `## Render Section` and `## Cache Section` are disjoint topics that never score.
# So {Kafka span} is the answer the rule dictates, not merely the answer today's binary gives.
EXPECTED_SET="$KAFKA_SPAN"
GOT_SET="$( printf '%s\n' "$GOT_RANGES" | sort -t- -k1,1n -k2,2n | tr '\n' ',' | sed 's/,$//' )"
if [ "$GOT_SET" = "$EXPECTED_SET" ]; then
    ok "anchor SET is exactly {$EXPECTED_SET} — the ancestor rule dropped '# Root doc', whose own prose carries no query term"
else
    no "anchor SET is {$GOT_SET}, expected exactly {$EXPECTED_SET} — a section whose OWN prose carries no query term was served (the §RP3.1 ancestor rule is not holding); note: $NOTE"
fi

# ─── determinism ────────────────────────────────────────────────────────────────────────────────────
echo
echo "=== determinism — same input, byte-identical ==="
recall >"$TMP/d1"
recall >"$TMP/d2"
if cmp -s "$TMP/d1" "$TMP/d2"; then ok "byte-identical across two runs"; else no "NON-deterministic across two runs"; fi

echo
[ "$fail" -eq 0 ] && { echo "recallanchorcheck: ALL PASS"; exit 0; }
echo "recallanchorcheck: FAILURES present"; exit 1

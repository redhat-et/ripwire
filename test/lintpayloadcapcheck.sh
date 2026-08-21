#!/usr/bin/env bash
# lintpayloadcapcheck.sh — gate for W3-S item 1: --lint must not be able to silently dump an unbounded
# payload on a large corpus (a G4 token-density violation with none of the other verbs' safety net).
#
# E6 (2026-08-19, PLAN_WAVE2_REPORTS_2026-08-17/exp-e6.md R3) recorded --lint on LightRAG emitting
# 2,037,645 B / findings="6169" with NO --limit given and no way for a caller to see it coming — every
# other capped verb in the catalog has a display default (--hotspots 40, --grep 100, --impact 40, …);
# --lint alone had none, so its own `<lint>` root could grow without bound. The fix (src/main.cpp
# runLint) gives the DEFAULT (unpaged) run a byte budget (kLintDefaultPayloadBytes=100000, chosen from
# measurements recorded at its definition site: this repo 367,924 B/3,213 findings, ctxpack (1,033
# tracked files) 254,445 B/2,312 findings, both ~110-115 B/finding, against E6's ~330 B/finding), and
# reuses src/pageview.h's shared pageDisclosure() so the default run now says shown=/capped= the same
# way every other capped verb already does — an explicit --limit=N still always beats the default cap
# (effectiveRowCap's existing rule; unchanged by this gate).
#
# wave-4 item 12 (six-smalls round recorded liability 1, docs/EVALS.md): the root's shown=/capped= pair
# above is a ROW-COUNT total — it never said WHICH of the firing rules those printed rows belonged to.
# Because the byte cap keeps a sorted PREFIX (sortLintRows: file path, then byte offset), a rule whose
# findings all sort past the cut lost every locator row while its count= (over the full, uncapped set)
# stayed a truthful total — indistinguishable, from the root alone, from a rule with rows just below the
# fold. The fix adds a per-rule shown= (printLintRuleTallyRow, src/main.cpp) so that shape now reads
# count="N" shown="0" instead of silently looking like every other un-capped rule. Arms 7-9 below cover it.
#
# Usage:
#   test/lintpayloadcapcheck.sh                      # uses build/ripwire
#   test/lintpayloadcapcheck.sh asan/ripwire
#   RIPWIRE_BIN=build_base/ripwire test/lintpayloadcapcheck.sh   # red-first: arms 1-3 and 7-8 MUST fail
#     here — a binary built before the W3-S fix has no default cap at all (uncapped default run, capped=
#     absent or "0" with every finding printed, blowing arm 1's byte ceiling) and a binary built before
#     THIS (wave-4 item 12) fix has no per-rule shown= attribute at all (arm 7 fails outright; arm 8's
#     goto row carries no shown= to read).
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# DO NOT edit regression.sh — this is a standalone gate invoked from there.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
CORPUS="$TMP/corpus"
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "lintpayloadcapcheck: no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "lintpayloadcapcheck: python3 is required"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "lintpayloadcapcheck: git is required"; exit 2; }

echo "lintpayloadcapcheck: BIN=$BIN"

# ── the sandbox corpus: 250 tiny C files x 12 magic-number literals each = ~3000 findings, comfortably
#    past the default byte cap (the same order of magnitude as E6's 6,169-finding LightRAG run) but built
#    fresh here rather than depending on a cloned corpus this gate cannot carry.
mkdir -p "$CORPUS/src" || { echo "lintpayloadcapcheck: cannot create corpus under $TMP"; exit 2; }
python3 - "$CORPUS" <<'PY_EOF'
import os, sys
root = sys.argv[1]
for i in range( 250 ):
    with open( os.path.join( root, "src", "u%d.c" % i ), "w" ) as f:
        f.write( "int magicPile%d( int seed )\n{\n    int acc = seed;\n" % i )
        for j in range( 12 ):
            f.write( "    acc += %d;\n" % ( 10000 + i * 100 + j ) )
        f.write( "    return acc;\n}\n" )
PY_EOF
# ── wave-4 item 12's fixture: ONE lone finding of a DIFFERENT rule ("goto"), planted in a file whose path
#    sorts after every "src/uNNN.c" magic-number file (sortLintRows' key is file path FIRST) — the magic-
#    number flood alone already exhausts the byte budget well before reaching this file (arm 1's 693-of-
#    3213 shown on the real corpus, arm 8 below re-confirms the analogous fact on this sandbox corpus), so
#    this rule's one-and-only row is guaranteed to fall entirely outside the printed <f> window: count=1,
#    shown=0 — the exact "count>0, zero visible rows" shape the recorded liability is about.
cat > "$CORPUS/src/zzz_lonely.c" <<'EOF'
int lonelyGoto( int seed )
{
    if( seed > 0 )
    {
        goto out;
    }
    seed = -seed;
out:
    return seed;
}
EOF

( cd "$CORPUS" && git init -q . && git add -A && git -c user.email=gate@example.invalid -c user.name=gate commit -qm init ) \
  || { echo "lintpayloadcapcheck: could not create the corpus git repo"; exit 2; }

# ── the TINY corpus: one file, three magic numbers, nowhere near any cap — the only way to prove the
#    default cap does not fire on an ordinary small run (a cap that is ALWAYS on proves nothing).
TINY="$TMP/tiny"
mkdir -p "$TINY"
cat > "$TINY/a.c" <<'EOF'
int compute()
{
    int x = 12345;
    int y = 67890;
    return x + y + 42424;
}
EOF

DEFAULT_OUT="$( "$BIN" "$CORPUS" --lint 2>/dev/null )"
DEFAULT_BYTES="${#DEFAULT_OUT}"
TAG="$( printf '%s' "$DEFAULT_OUT" | grep -o '<lint [^>]*>' | head -1 )"
FINDINGS="$( printf '%s' "$TAG" | sed -n 's/.*findings="\([0-9]*\)".*/\1/p' )"
SHOWN="$(    printf '%s' "$TAG" | sed -n 's/.*[^_]shown="\([0-9]*\)".*/\1/p' )"
CAPPED="$(   printf '%s' "$TAG" | sed -n 's/.*[^_]capped="\([01]\)".*/\1/p' )"
ROWS="$( printf '%s' "$DEFAULT_OUT" | grep -o '<f ' | wc -l | tr -d ' ' )"

# ── arm 1: the default (unpaged) payload is byte-capped. 150,000 gives headroom over the internal
#    100,000 B estimate (the estimate is conservative, and the header/legend/rule-tally bytes ride
#    alongside the capped <f> rows) while staying nowhere near the ~2 MB E6 recorded.
if [ -n "$DEFAULT_BYTES" ] && [ "$DEFAULT_BYTES" -le 150000 ]; then
    ok "arm1: default --lint on a ${FINDINGS:-?}-finding corpus is $DEFAULT_BYTES B (<= 150000 B ceiling)"
else
    no "arm1: default --lint is $DEFAULT_BYTES B — blows the 150000 B ceiling (no default cap engaged)"
fi

# ── arm 2: the cap is DISCLOSED — findings= (the true total) + shown= + capped="1", and shown= is
#    strictly less than findings= (a cap that dropped nothing is not a cap).
if [ -z "$FINDINGS" ] || [ -z "$SHOWN" ] || [ -z "$CAPPED" ]; then
    no "arm2: default --lint root tag is missing findings=/shown=/capped= ($TAG)"
elif [ "$CAPPED" != "1" ]; then
    no "arm2: default --lint says capped=\"$CAPPED\" (want 1) on a $FINDINGS-finding corpus"
elif [ "$SHOWN" -ge "$FINDINGS" ]; then
    no "arm2: shown=$SHOWN >= findings=$FINDINGS — capped=\"1\" but nothing was actually dropped"
else
    ok "arm2: findings=$FINDINGS shown=$SHOWN capped=\"1\" — the drop is disclosed and arithmetic"
fi

# ── arm 3: the disclosure is ARITHMETIC — shown= equals the <f> rows actually printed, and the per-rule
#    tally (magic-number's count=) still reports the TRUE total, not the capped row count (the row cap
#    must never corrupt the rule statistics that made --lint's per-rule counts trustworthy in the first
#    place — lintbudgetcheck.sh's whole reason to exist).
if [ -n "$SHOWN" ] && [ "$SHOWN" = "$ROWS" ]; then
    ok "arm3a: shown=$SHOWN matches $ROWS <f> rows actually emitted"
else
    no "arm3a: shown=$SHOWN but $ROWS <f> rows were emitted — the disclosure is not arithmetic"
fi
RULE_COUNT="$( printf '%s' "$DEFAULT_OUT" | grep -o '<rule name="magic-number" count="[0-9]*"' | sed -n 's/.*count="\([0-9]*\)".*/\1/p' )"
# findings= is magic-number's own total PLUS the one lone "goto" finding wave-4 item 12's fixture plants
# (src/zzz_lonely.c, added below) — so the equality is against findings-1, not findings, now that the
# corpus fires two distinct rules instead of one.
if [ -n "$RULE_COUNT" ] && [ -n "$FINDINGS" ] && [ "$RULE_COUNT" = "$(( FINDINGS - 1 ))" ]; then
    ok "arm3b: magic-number rule count=$RULE_COUNT still equals findings-1=$(( FINDINGS - 1 )) (row cap did not shrink the rule tally)"
else
    no "arm3b: magic-number rule count=${RULE_COUNT:-?} vs findings-1=$(( ${FINDINGS:-0} - 1 )) — the row cap leaked into the rule tally"
fi

# ── arm 4: explicit --limit=N overrides the default cap (effectiveRowCap's existing tool-wide rule) —
#    a caller who already knows to page past a cap sees strictly MORE rows, proving the default arm 1-3
#    behaviour is a DEFAULT, not a hard ceiling nobody can raise.
LIMIT_OUT="$( "$BIN" "$CORPUS" --lint --limit=100000 2>/dev/null )"
LIMIT_TAG="$( printf '%s' "$LIMIT_OUT" | grep -o '<lint [^>]*>' | head -1 )"
LIMIT_SHOWN="$( printf '%s' "$LIMIT_TAG" | sed -n 's/.*[^_]shown="\([0-9]*\)".*/\1/p' )"
if [ -n "$LIMIT_SHOWN" ] && [ -n "$SHOWN" ] && [ "$LIMIT_SHOWN" -gt "$SHOWN" ]; then
    ok "arm4: --limit=100000 raises shown= from $SHOWN to $LIMIT_SHOWN — the default cap is raisable, not a ceiling"
else
    no "arm4: --limit=100000 shown=${LIMIT_SHOWN:-?} did not exceed the default shown=$SHOWN"
fi

# ── arm 5 (the decisive-arm / untruncated proof): the TINY corpus is nowhere near the byte budget, so
#    the default run must show capped="0" — a cap that is unconditionally "1" proves nothing about
#    whether the mechanism is live rather than hardwired.
TINY_OUT="$( "$BIN" "$TINY" --lint 2>/dev/null )"
TINY_TAG="$( printf '%s' "$TINY_OUT" | grep -o '<lint [^>]*>' | head -1 )"
TINY_CAPPED="$( printf '%s' "$TINY_TAG" | sed -n 's/.*[^_]capped="\([01]\)".*/\1/p' )"
TINY_FINDINGS="$( printf '%s' "$TINY_TAG" | sed -n 's/.*findings="\([0-9]*\)".*/\1/p' )"
TINY_SHOWN="$( printf '%s' "$TINY_TAG" | sed -n 's/.*[^_]shown="\([0-9]*\)".*/\1/p' )"
if [ "$TINY_CAPPED" = "0" ] && [ -n "$TINY_FINDINGS" ] && [ "$TINY_SHOWN" = "$TINY_FINDINGS" ]; then
    ok "arm5: tiny corpus (findings=$TINY_FINDINGS) is capped=\"0\" with shown==findings — the bit is reachable both ways"
else
    no "arm5: tiny corpus reports capped=\"${TINY_CAPPED:-?}\" shown=${TINY_SHOWN:-?} findings=${TINY_FINDINGS:-?} (want capped=0, shown==findings)"
fi

# ── arm 6: still well-formed and deterministic after the accounting change ─────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$DEFAULT_OUT" | xmllint --noout - 2>/dev/null; then ok "arm6: capped default output is well-formed (G4)"; else no "arm6: capped default output fails xmllint"; fi
else
    no "arm6: xmllint is required for the G4 arm (install libxml2) — the gate does not skip"
fi
REPEAT_OUT="$( "$BIN" "$CORPUS" --lint 2>/dev/null )"
if [ "$REPEAT_OUT" = "$DEFAULT_OUT" ]; then ok "arm6: output is byte-identical run-to-run"; else no "arm6: output is not deterministic"; fi

# ── wave-4 item 12: recorded liability 1 from the six-smalls round (docs/EVALS.md) — the root's shown=/
#    capped= pair (arms 1-6 above) only ever proved the ROW-COUNT total was honest; it said nothing about
#    WHICH of the 31 firing rules those printed rows belonged to. A rule whose findings all sort past the
#    byte cut lost every locator row while its own count= (computed over the full, uncapped set) stayed
#    truthful — indistinguishable, from the root alone, from a rule with real rows just below the fold.
#    Each <rule> row now carries its own shown= for exactly this reason.
RULE_LINES="$( printf '%s' "$DEFAULT_OUT" | grep -o '<rule name="[^"]*"[^/]*/>' )"
# grep -c (not wc -l) on both sides: $(...) strips the trailing newline from a multi-line capture, so
# `wc -l` undercounts a set with no trailing blank line by exactly one — grep -c counts MATCHING lines
# regardless of a trailing newline and is what both sides need to compare apples to apples.
RULE_COUNT_LINES="$( printf '%s' "$RULE_LINES" | grep -c '<rule name=' )"
RULE_SHOWN_LINES="$( printf '%s' "$RULE_LINES" | grep -c ' shown="[0-9]*"' )"

# ── arm 7: shown= is present on EVERY <rule> row, not just some — the whole point is that a fully-capped
#    rule's row still carries the attribute (reading "0"), never omits it (an absent attribute here would
#    silently reopen the exact ambiguity this item exists to close).
if [ -n "$RULE_LINES" ] && [ "$RULE_COUNT_LINES" -gt 0 ] && [ "$RULE_SHOWN_LINES" = "$RULE_COUNT_LINES" ]; then
    ok "arm7: all $RULE_COUNT_LINES <rule> rows carry shown= (default --lint run)"
else
    no "arm7: only $RULE_SHOWN_LINES of $RULE_COUNT_LINES <rule> rows carry shown= — per-rule disclosure is not universal"
fi

# ── arm 8 (the decisive arm): "goto" fires exactly once in the whole corpus, planted in src/zzz_lonely.c —
#    a path that sorts after all 250 src/uNNN.c magic-number files, so the byte cap (already shown to stop
#    well short of the full corpus) never reaches it. count="1" (the true total: --lint's own tally never
#    lies) but shown="0" (that row never made it into the printed window) is the exact liability shape:
#    a rule with findings > 0 and ZERO visible locator rows.
GOTO_RULE_TAG="$( printf '%s' "$DEFAULT_OUT" | grep -o '<rule name="goto"[^/]*/>' | head -1 )"
GOTO_COUNT="$( printf '%s' "$GOTO_RULE_TAG" | sed -n 's/.*count="\([0-9]*\)".*/\1/p' )"
GOTO_SHOWN="$( printf '%s' "$GOTO_RULE_TAG" | sed -n 's/.*shown="\([0-9]*\)".*/\1/p' )"
GOTO_ROWS_PRINTED="$( printf '%s' "$DEFAULT_OUT" | grep -c '<f rule="goto"' )"
if [ "$GOTO_COUNT" = "1" ] && [ "$GOTO_SHOWN" = "0" ] && [ "$GOTO_ROWS_PRINTED" = "0" ]; then
    ok "arm8: goto count=1 shown=0 (0 <f rule=\"goto\"> rows actually printed) — a fully-capped-away rule says so, not a silent locator-less zero"
else
    no "arm8: goto count=${GOTO_COUNT:-?} shown=${GOTO_SHOWN:-?} rows_printed=$GOTO_ROWS_PRINTED — want count=1 shown=0 rows_printed=0"
fi

# ── arm 9: on an UNCAPPED run (TINY corpus, arm 5's fixture — nowhere near the byte budget), every rule's
#    shown= equals its own count= — the per-rule attribute tracks the printed window honestly in both
#    directions, not just when something was actually cut.
TINY_RULE_LINES="$( printf '%s' "$TINY_OUT" | grep -o '<rule name="[^"]*"[^/]*/>' )"
TINY_MISMATCH=0
while IFS= read -r rl; do
    [ -z "$rl" ] && continue
    rc="$( printf '%s' "$rl" | sed -n 's/.*count="\([0-9]*\)".*/\1/p' )"
    rs="$( printf '%s' "$rl" | sed -n 's/.*shown="\([0-9]*\)".*/\1/p' )"
    [ "$rc" = "$rs" ] || TINY_MISMATCH=$(( TINY_MISMATCH + 1 ))
done <<EOF_RL
$TINY_RULE_LINES
EOF_RL
if [ -n "$TINY_RULE_LINES" ] && [ "$TINY_MISMATCH" -eq 0 ]; then
    ok "arm9: every <rule> row on the uncapped TINY run has shown==count"
else
    no "arm9: $TINY_MISMATCH <rule> row(s) on the uncapped TINY run have shown != count"
fi

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES PRESENT"; exit 1

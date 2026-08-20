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
# Usage:
#   test/lintpayloadcapcheck.sh                      # uses build/ripwire
#   test/lintpayloadcapcheck.sh asan/ripwire
#   RIPWIRE_BIN=build_base/ripwire test/lintpayloadcapcheck.sh   # red-first: arms 1-3 MUST fail here —
#     a binary built before this fix has no default cap at all, so the default run is uncapped
#     (capped= absent or "0" with every finding printed) and blows the byte ceiling arm 1 checks.
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
if [ -n "$RULE_COUNT" ] && [ -n "$FINDINGS" ] && [ "$RULE_COUNT" = "$FINDINGS" ]; then
    ok "arm3b: magic-number rule count=$RULE_COUNT still equals findings=$FINDINGS (row cap did not shrink the rule tally)"
else
    no "arm3b: magic-number rule count=${RULE_COUNT:-?} vs findings=${FINDINGS:-?} — the row cap leaked into the rule tally"
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

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES PRESENT"; exit 1

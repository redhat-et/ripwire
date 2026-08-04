#!/usr/bin/env bash
# nameboostcheck.sh — R5/PREREG (bench/locbench/results/r5_nameboost/PREREG.md, incl. the 2026-08-04
# pre-run amendments): env-gated query-noun-in-name lift under the CONCEPTUAL (subtoken+body) route.
# RIPWIRE_NAMEBOOST="<minTokLen>,<maxLifted>": after routing + mention boost, a symbol fires when a RAW
# query token (maximal [A-Za-z0-9_]+ run, lowercased) of length >= minTokLen matches the symbol's WHOLE
# name at camel/snake subtoken boundaries (the token's subtoken sequence is a CONTIGUOUS run of the
# name's subtokens: "match" -> ResolverMatch, "is_valid" -> is_valid) AND the symbol carries positive
# BODY/DOC evidence (>= 1 query subtoken in its doc-comment+body postings row — the anti-noise guard:
# name-only evidence never lifts). Fired symbols are walked by (current score desc, id asc); one that
# already sits at-or-above the next ladder slot is SKIPPED WITHOUT consuming a slot (max() would no-op);
# the first maxLifted below-slot symbols land on the slot ladder BELOW the mention band
# (top*(1 - kMentionTopGapStep*(kMentionMaxFiles+1+j))). #1 is NEVER displaced. Env unset -> byte-identical.
#
# THE FEATURE DOES NOT EXIST YET. This gate is written first, against the current (inert) binary: red on
# the SIGNAL assertion today, green the moment RIPWIRE_NAMEBOOST is implemented.
#
#   test/nameboostcheck.sh                       # uses build/ripwire on an inline fixture
#   RIPWIRE_BIN=asan/ripwire test/nameboostcheck.sh
#
# Sections:
#   (i)   INERT            — env UNSET == RIPWIRE_NAMEBOOST="" == today's binary, byte-identical. PASSES today.
#   (ii)  SIGNAL           — RIPWIRE_NAMEBOOST="4,2": ResolverMatch (name fires on query token "match",
#                             weak-but-positive body evidence, baseline rank outside the top 10) must enter
#                             the --format=candidates top 10. RED today.
#   (iii) BODY/DOC GUARD   — MatchLever (name fires on "match" but ZERO query subtokens in its doc/body)
#                             must never IMPROVE on its baseline rank under any config. Holds today (inert)
#                             and must keep holding after implementation.
#   (iv)  minTokLen        — RIPWIRE_NAMEBOOST="6,2": "match" (5 bytes) is below minTokLen, so
#                             ResolverMatch must not improve on its baseline rank.
#   (v)   ROUTE SCOPE      — a name-exact-routed query (single snake_case token) with the env set is
#                             byte-identical to the same query with the env unset. Holds today; must hold after.
#   (vi)  #1 STABILITY     — the r=1 candidate row is identical with the env set and unset. Hard invariant.
#   (vii) determinism x2 with the env set + xmllint --noout clean (skipped if xmllint absent).
#   Malformed env values ("0,0", "99,99", "banana", ",", "4") must not crash: exit 0 only.
#
# Exits non-zero if ANY assertion fails (inertness included) — a gate, not a status report.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "nameboostcheck: BIN=$BIN"

# ── fixture ──────────────────────────────────────────────────────────────────────────────────────────
# pkg/alpha.py: 3 functions rich in the query's words — the clear top block (their names FIRE the trigger
# too, but they already sit above the ladder slots, so the skip-without-consuming rule must pass over
# them). pkg/target.py: class ResolverMatch — name fires on the query token "match"; its doc carries ONE
# weak query word ("object"), so body/doc evidence is positive but the total score leaves it outside the
# top 10 behind the mid/ fillers. pkg/noise.py: class MatchLever — name fires on "match" but its doc/body
# share ZERO subtokens with the query (no "the"/"where"/"does" either — the guard's test hinges on that).
# mid/filler*.py: doc-evidence-only distractors (names deliberately share NO query subtoken, so they never
# fire) that pin ResolverMatch's baseline rank outside the top 10.
FIX="$TMP/fix"
mkdir -p "$FIX/pkg" "$FIX/mid"

cat > "$FIX/pkg/alpha.py" <<'PY'
def frobnicate_pipeline_produce(records):
    """Produce the frobnicate object where the pipeline emits records."""
    return [r for r in records if r]

def pipeline_produce_frobnicate(records):
    """Where does the pipeline produce the frobnicate object for records."""
    return records

def produce_frobnicate_object(records):
    """Produce a frobnicate object from the pipeline records."""
    return len(records)
PY

cat > "$FIX/pkg/target.py" <<'PY'
class ResolverMatch:
    """Holds one resolved object."""

    def describe(self):
        return "resolved"
PY

cat > "$FIX/pkg/noise.py" <<'PY'
class MatchLever:
    """Lever arm gauge used during calibration duty."""

    def torque(self):
        return 42
PY

# The fillers deliberately contain the word "match" in prose: that DILUTES the token's idf (the exact
# q08 failure shape this round attacks — name evidence drowned in a common token) so ResolverMatch's
# name field cannot carry it into the top 10 on its own, while the fillers' several-word doc evidence
# pins them above it.
i=1
while [ "$i" -le 12 ]; do
cat > "$FIX/mid/filler$i.py" <<PY
def stage_batch_runner_$i(items):
    """Produce pipeline output records that match the object emitted, variant $i."""
    return items

def stage_batch_helper_$i(items):
    """Where the pipeline does produce records that match an object, helper $i."""
    return items
PY
i=$(( i + 1 ))
done

QUERY="where does the pipeline produce the frobnicate match object"
NAMEQ="frobnicate_pipeline_produce"

cands(){ "$BIN" "$FIX" --for="$QUERY" --format=candidates --top-k=40 --no-cache 2>/dev/null; }
candsNb(){ RIPWIRE_NAMEBOOST="$1" "$BIN" "$FIX" --for="$QUERY" --format=candidates --top-k=40 --no-cache 2>/dev/null; }
forXml(){ "$BIN" "$FIX" --for="$QUERY" --no-cache 2>/dev/null; }
forXmlNb(){ RIPWIRE_NAMEBOOST="$1" "$BIN" "$FIX" --for="$QUERY" --no-cache 2>/dev/null; }
rankOf(){ printf '%s' "$1" | grep -o "<cand r=\"[0-9]*\" [^>]*n=\"$2\"" | grep -o 'r="[0-9]*"' | grep -o '[0-9]*' | head -1; }
top1row(){ printf '%s' "$1" | grep -o '<cand r="1" [^>]*>' | head -1; }

BASE_CAND="$( cands )"
[ -n "$BASE_CAND" ] || { echo "nameboostcheck: baseline --format=candidates produced no output — fixture or binary broken"; exit 2; }
printf '%s' "$BASE_CAND" | grep -q 'route="subtoken+body"' \
    || { echo "nameboostcheck: fixture query did not route subtoken+body — fixture broken"; exit 2; }

rTargetBase="$( rankOf "$BASE_CAND" ResolverMatch )"
rNoiseBase="$( rankOf "$BASE_CAND" MatchLever )"
[ -n "$rTargetBase" ] && [ -n "$rNoiseBase" ] \
    || { echo "nameboostcheck: ResolverMatch/MatchLever absent from the baseline ranking — fixture broken"; echo "$BASE_CAND"; exit 2; }
if [ "$rTargetBase" -gt 10 ]; then
    ok "fixture shape (ResolverMatch baseline rank $rTargetBase is outside top 10; MatchLever rank $rNoiseBase)"
else
    no "fixture shape unexpected (ResolverMatch rank=$rTargetBase expected >10) — the SIGNAL assertion below may be vacuous"
fi

# ── (i) INERT — env UNSET == RIPWIRE_NAMEBOOST="" (byte-identical). PASSES today; the inert-default contract. ──
BASE_FOR="$( forXml )"
EMPTYENV_FOR="$( forXmlNb "" )"
[ -n "$BASE_FOR" ] && [ "$BASE_FOR" = "$EMPTYENV_FOR" ] \
    && ok "INERT: --for output, env UNSET == RIPWIRE_NAMEBOOST=\"\" (byte-identical)" \
    || no "INERT: --for output changed between env UNSET and RIPWIRE_NAMEBOOST=\"\""
EMPTYENV_CAND="$( candsNb "" )"
[ "$BASE_CAND" = "$EMPTYENV_CAND" ] \
    && ok "INERT: --format=candidates, env UNSET == RIPWIRE_NAMEBOOST=\"\" (byte-identical)" \
    || no "INERT: --format=candidates changed between env UNSET and RIPWIRE_NAMEBOOST=\"\""

# ── (ii) SIGNAL (RED today — nothing reads RIPWIRE_NAMEBOOST yet) ────────────────────────────────────
SIG_CAND="$( candsNb "4,2" )"
rTargetSig="$( rankOf "$SIG_CAND" ResolverMatch )"
if [ -n "$rTargetSig" ] && [ "$rTargetSig" -le 10 ]; then
    ok "SIGNAL: RIPWIRE_NAMEBOOST=4,2 lifts ResolverMatch into the top 10 (rank $rTargetSig, baseline $rTargetBase)"
else
    no "SIGNAL: RIPWIRE_NAMEBOOST=4,2 did not lift ResolverMatch into the top 10 (rank ${rTargetSig:-absent}, baseline $rTargetBase)"
fi

# ── (iii) BODY/DOC GUARD — name-only evidence never lifts (rank must not IMPROVE; ordinal may worsen
#     because legitimately lifted rows land above it) ────────────────────────────────────────────────
SIG44_CAND="$( candsNb "4,4" )"
rNoiseSig="$( rankOf "$SIG44_CAND" MatchLever )"
if [ -n "$rNoiseSig" ] && [ "$rNoiseSig" -ge "$rNoiseBase" ]; then
    ok "GUARD: MatchLever (zero doc/body query overlap) is not lifted above its baseline rank $rNoiseBase under RIPWIRE_NAMEBOOST=4,4 (now $rNoiseSig)"
else
    no "GUARD: MatchLever improved from baseline rank $rNoiseBase to ${rNoiseSig:-absent} under RIPWIRE_NAMEBOOST=4,4 — name-only evidence must never lift"
fi

# ── (iv) minTokLen respected — "match" (5 bytes) is below minTokLen=6 ────────────────────────────────
MT6_CAND="$( candsNb "6,2" )"
rTargetMt6="$( rankOf "$MT6_CAND" ResolverMatch )"
if [ -n "$rTargetMt6" ] && [ "$rTargetMt6" -ge "$rTargetBase" ]; then
    ok "MINTOK: ResolverMatch is not lifted above baseline rank $rTargetBase at minTokLen=6 (now $rTargetMt6; \"match\" is 5 bytes)"
else
    no "MINTOK: ResolverMatch improved from baseline rank $rTargetBase to ${rTargetMt6:-absent} at minTokLen=6"
fi

# ── (v) ROUTE SCOPE — a name-exact-routed query is untouched by the env ──────────────────────────────
NX_BASE="$( "$BIN" "$FIX" --for="$NAMEQ" --format=candidates --top-k=40 --no-cache 2>/dev/null )"
printf '%s' "$NX_BASE" | grep -q 'route="name-exact"' \
    || { echo "nameboostcheck: $NAMEQ did not route name-exact — fixture broken"; exit 2; }
NX_ENV="$( RIPWIRE_NAMEBOOST="4,4" "$BIN" "$FIX" --for="$NAMEQ" --format=candidates --top-k=40 --no-cache 2>/dev/null )"
[ -n "$NX_BASE" ] && [ "$NX_BASE" = "$NX_ENV" ] \
    && ok "ROUTE SCOPE: name-exact-routed query is byte-identical with RIPWIRE_NAMEBOOST=4,4 set" \
    || no "ROUTE SCOPE: name-exact-routed query output changed under RIPWIRE_NAMEBOOST=4,4"

# ── (vi) #1 STABILITY — the top candidate row never changes ──────────────────────────────────────────
T1_BASE="$( top1row "$BASE_CAND" )"
T1_SIG="$( top1row "$SIG44_CAND" )"
[ -n "$T1_BASE" ] && [ "$T1_BASE" = "$T1_SIG" ] \
    && ok "#1 STABILITY: r=1 row identical with and without RIPWIRE_NAMEBOOST=4,4" \
    || no "#1 STABILITY: r=1 row changed under RIPWIRE_NAMEBOOST=4,4 (was: $T1_BASE, now: $T1_SIG)"

# ── (vii) determinism x2 + well-formedness with the env set ──────────────────────────────────────────
FOR_A="$( forXmlNb "4,2" )"
FOR_B="$( forXmlNb "4,2" )"
[ -n "$FOR_A" ] && [ "$FOR_A" = "$FOR_B" ] \
    && ok "determinism: two RIPWIRE_NAMEBOOST=4,2 --for runs are byte-identical" \
    || no "determinism: two RIPWIRE_NAMEBOOST=4,2 --for runs differ"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$FOR_A" | xmllint --noout - 2>/dev/null \
        && ok "well-formedness: --for output with the env set pipes clean through xmllint" \
        || no "well-formedness: --for output with the env set fails xmllint"
else
    echo "  SKIP  xmllint not present"
fi

# malformed env values must not crash (exit 0 only — behavior is byte-exact-inert once implemented,
# but pre-implementation this section only pins "does not crash")
for v in "0,0" "99,99" "banana" "," "4" "4,;" "-4,2"; do
    RIPWIRE_NAMEBOOST="$v" "$BIN" "$FIX" --for="$QUERY" --no-cache >/dev/null 2>&1 \
        && ok "malformed env \"$v\" exits 0" \
        || no "malformed env \"$v\" crashed"
done

echo
if [ "$fail" -eq 0 ]; then echo "nameboostcheck: ALL PASS"; else echo "nameboostcheck: FAILURES"; fi
exit "$fail"

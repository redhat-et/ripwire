#!/usr/bin/env bash
# liftdisclosurecheck.sh — gate for two OUTPUT-class silent caps in src/expand.h and src/siblift.h.
#
# THE DEFECT (both files, same shape): RIPWIRE_EXPAND="<S>,<N>" / RIPWIRE_SIBLIFT="<S>,<N>" are two
# EXPERIMENTAL, env-gated re-rankers on the routed --for lens (r6 structural expansion, r4 sibling lift).
# Before this gate:
#   (a) a SUCCESSFUL lift silently re-ranked the served set — no note, no attribute, nothing distinguishing
#       a plain routed ranking from one a graph walk had reshaped.
#   (b) a malformed/out-of-range env value (a typo, a value past kExpandMaxSeeds/kSibliftMaxSeed, …)
#       returned exactly the same (0,0) "off" pair as the env being UNSET — so a caller who set
#       RIPWIRE_EXPAND="99,99" got a plain ranking with no way to tell that apart from never having set the
#       var at all.
#
# THE FIX. (a) applyStructuralExpansion/applySiblingLift now take an optional *LiftInfo* out-param; when
# the lift actually promotes a symbol, computeLensRanking (verbs_for.h) builds a prose note — "[sibling
# lift: promoted N symbols in M files …]" / "[structural expansion: …]" — spliced into --for's header
# comment and --json's own key, exactly like the existing mentionNote/boostNote precedent (present only
# when the boost actually fired; absent and byte-free otherwise). (b) expandParams()/sibliftParams() now
# call DEGRADED_PATH_ALERT (stderr, once per site) when the env var is SET but rejected — CONTRIBUTING §3's
# degrade shape (clamp/fall back to OFF, and say so) — leaving the env-UNSET case wordless on purpose (this
# experiment has no default behavior to be silent about).
#
# Every arm below asserts the three things a disclosure gate must (test/capdisclosurecheck.sh's own
# discipline, copied here): CROSSING (the fixture really engages the lift / really sets the env), DISCLOSURE
# (the answer — or stderr — carries the marker), SILENCE (the SAME verb, uncrossed, carries nothing).
#
# MUTATION CONTROL: run this gate with RIPWIRE_BIN pointed at a binary built from the parent commit (before
# this round) and every DISCLOSURE assertion must FAIL while every CROSSING assertion still passes — the
# lift mechanism itself is pre-existing, only the disclosure is new.
#
# Usage:
#   test/liftdisclosurecheck.sh
#   RIPWIRE_BIN=build_base/ripwire test/liftdisclosurecheck.sh     # the RED run
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "liftdisclosurecheck: BIN=$BIN"

# ===================================================================================================
# fixtures
# ===================================================================================================

# ---- siblift fixture: pkg/alpha.py is the clear #1 file; pkg/beta.py (SAME dir) shares one weak token
#      ("widget") — a positive but low score, so RIPWIRE_SIBLIFT="1,1" has something to lift.
SIB="$TMP/sib"
mkdir -p "$SIB/pkg" "$SIB/mid"
cat > "$SIB/pkg/alpha.py" <<'PY'
def widget_pipeline_process(records):
    """Process widget records through the pipeline stage."""
    return [r for r in records if r]

def widget_records_pipeline(records):
    """Pipeline stage: validate widget records for processing."""
    return records

def process_widget_records(records):
    """Process the widget records for each stage in the pipeline."""
    return len(records)
PY
cat > "$SIB/pkg/beta.py" <<'PY'
def unrelated_cache_flush(entries):
    """Flush the widget cache once entries go stale."""
    return [e for e in entries if e.fresh]
PY
for i in 1 2 3; do
cat > "$SIB/mid/filler$i.py" <<PY
def build_pipeline_stage_$i(items):
    """Build a processing pipeline stage for the batch, filler $i."""
    return items
PY
done
SIBQ="widget pipeline process records"

# ---- expand fixture: pkg/alpha.c is the clear #1 file; pkg/linked.h is reached by a RESOLVED
#      #include edge (not a same-directory sibling — proves the edge is structural, not siblift's).
EXP="$TMP/exp"
mkdir -p "$EXP/pkg" "$EXP/other" "$EXP/mid"
cat > "$EXP/pkg/alpha.c" <<'EOF'
#include "../other/linked.h"
int widget_pipeline_process( int* records, int n ) { return n; }
int widget_records_pipeline( int* records, int n ) { return n; }
int process_widget_records( int* records, int n ) { return n; }
EOF
cat > "$EXP/other/linked.h" <<'EOF'
static inline int unrelated_widget_helper( int x ) { return x; }
EOF
for i in 1 2 3; do
cat > "$EXP/mid/filler$i.c" <<EOF
int build_pipeline_stage_$i( int* items, int n ) { return n; }
EOF
done
EXPQ="widget pipeline process records"

run_sib(){ "$BIN" "$SIB" --for="$SIBQ" --no-cache 2>/dev/null; }
run_sib_env(){ RIPWIRE_SIBLIFT="$1" "$BIN" "$SIB" --for="$SIBQ" --no-cache 2>/dev/null; }
run_exp(){ "$BIN" "$EXP" --for="$EXPQ" --no-cache 2>/dev/null; }
run_exp_env(){ RIPWIRE_EXPAND="$1" "$BIN" "$EXP" --for="$EXPQ" --no-cache 2>/dev/null; }

# ===================================================================================================
# (A) siblift — a SUCCESSFUL lift discloses; the uncrossed default does not
# ===================================================================================================
echo "-- (A) sibling lift (RIPWIRE_SIBLIFT)"

BASE_SIB="$( run_sib )"
[ -n "$BASE_SIB" ] || { echo "liftdisclosurecheck: baseline --for on the siblift fixture produced no output — fixture broken"; exit 2; }
printf '%s' "$BASE_SIB" | grep -q 'sibling lift:' \
    && no "A0 SILENCE (env unset): baseline --for already carries a sibling-lift note (probe broken)" \
    || ok "A0 SILENCE (env unset): baseline --for carries no sibling-lift note"

# CROSSING — proved independently of the note text: unrelated_cache_flush's (beta.py) --format=candidates
# score must genuinely rise under RIPWIRE_SIBLIFT=1,1, not merely have a note claiming it did. This is what
# makes the mutation control meaningful: the base commit's siblift MECHANISM already moves this score (it
# predates this round), so this assertion passes on BOTH binaries — only the note text below is new.
scoreOf(){ printf '%s' "$1" | grep -o "<cand r=\"[0-9]*\" s=\"[0-9.]*\"[^>]*n=\"$2\"" | grep -o 's="[0-9.]*"' | grep -o '[0-9.]*' | head -1; }
BASE_SIB_CAND="$( "$BIN" "$SIB" --for="$SIBQ" --format=candidates --top-k=30 --no-cache 2>/dev/null )"
LIFT_SIB_CAND="$( RIPWIRE_SIBLIFT="1,1" "$BIN" "$SIB" --for="$SIBQ" --format=candidates --top-k=30 --no-cache 2>/dev/null )"
sBase="$( scoreOf "$BASE_SIB_CAND" unrelated_cache_flush )"
sLift="$( scoreOf "$LIFT_SIB_CAND" unrelated_cache_flush )"
if [ -n "$sBase" ] && [ -n "$sLift" ] && awk -v a="$sLift" -v b="$sBase" 'BEGIN{exit !(a>b)}'; then
    ok "A1 CROSSING: unrelated_cache_flush's score rises under RIPWIRE_SIBLIFT=1,1 ($sBase -> $sLift)"
else
    no "A1 CROSSING: unrelated_cache_flush's score did not rise under RIPWIRE_SIBLIFT=1,1 (baseline=${sBase:-absent} lifted=${sLift:-absent}) — fixture broken"
fi

LIFT_SIB="$( run_sib_env "1,1" )"
printf '%s' "$LIFT_SIB" | grep -qE 'sibling lift: promoted [1-9][0-9]* symbol' \
    && ok "A1b DISCLOSURE: RIPWIRE_SIBLIFT=1,1 note claims a nonzero symbol promotion" \
    || no "A1b DISCLOSURE: RIPWIRE_SIBLIFT=1,1 did not disclose a nonzero promotion — $( printf '%s' "$LIFT_SIB" | grep -o 'sibling lift:[^]]*]' )"
printf '%s' "$LIFT_SIB" | grep -q 'RIPWIRE_SIBLIFT=1,1' \
    && ok "A2 DISCLOSURE: the note echoes the env value that produced it" \
    || no "A2 DISCLOSURE: the note does not echo RIPWIRE_SIBLIFT=1,1"

# SILENCE — an env value that parses but lifts nothing (a single-file corpus: no sibling CAN exist) must
# carry no note either: disclosure is conditional on MOVEMENT, not on the env var merely being set.
mkdir -p "$TMP/onefile_sib"
cat > "$TMP/onefile_sib/only.py" <<'PY'
def lonely_widget_fn(x):
    """The only widget-matching function in a single-file corpus — nothing to lift."""
    return x
PY
NOOP_SIB="$( RIPWIRE_SIBLIFT="4,4" "$BIN" "$TMP/onefile_sib" --for="widget" --no-cache 2>/dev/null )"
printf '%s' "$NOOP_SIB" | grep -q 'sibling lift:' \
    && no "A3 SILENCE (fired but moved nothing): a single-file corpus still carries a sibling-lift note" \
    || ok "A3 SILENCE (fired but moved nothing): a single-file corpus carries no sibling-lift note"

# ===================================================================================================
# (B) structural expansion — a SUCCESSFUL lift discloses; the uncrossed default does not
# ===================================================================================================
echo "-- (B) structural expansion (RIPWIRE_EXPAND)"

BASE_EXP="$( run_exp )"
[ -n "$BASE_EXP" ] || { echo "liftdisclosurecheck: baseline --for on the expand fixture produced no output — fixture broken"; exit 2; }
printf '%s' "$BASE_EXP" | grep -q 'structural expansion:' \
    && no "B0 SILENCE (env unset): baseline --for already carries a structural-expansion note (probe broken)" \
    || ok "B0 SILENCE (env unset): baseline --for carries no structural-expansion note"

# CROSSING — proved independently of the note text, same discipline as A1: linked.h's
# unrelated_widget_helper (reached only via the resolved #include edge, not a directory sibling) must
# genuinely rise under RIPWIRE_EXPAND=1,1. The underlying expansion mechanism predates this round, so this
# assertion passes on BOTH binaries — only the note text below is new.
BASE_EXP_CAND="$( "$BIN" "$EXP" --for="$EXPQ" --format=candidates --top-k=30 --no-cache 2>/dev/null )"
LIFT_EXP_CAND="$( RIPWIRE_EXPAND="1,1" "$BIN" "$EXP" --for="$EXPQ" --format=candidates --top-k=30 --no-cache 2>/dev/null )"
sBaseE="$( scoreOf "$BASE_EXP_CAND" unrelated_widget_helper )"
sLiftE="$( scoreOf "$LIFT_EXP_CAND" unrelated_widget_helper )"
if [ -n "$sBaseE" ] && [ -n "$sLiftE" ] && awk -v a="$sLiftE" -v b="$sBaseE" 'BEGIN{exit !(a>b)}'; then
    ok "B1 CROSSING: unrelated_widget_helper's score rises under RIPWIRE_EXPAND=1,1 ($sBaseE -> $sLiftE)"
else
    no "B1 CROSSING: unrelated_widget_helper's score did not rise under RIPWIRE_EXPAND=1,1 (baseline=${sBaseE:-absent} lifted=${sLiftE:-absent}) — fixture broken"
fi

LIFT_EXP="$( run_exp_env "1,1" )"
printf '%s' "$LIFT_EXP" | grep -qE 'structural expansion: promoted [1-9][0-9]* symbol' \
    && ok "B1b DISCLOSURE: RIPWIRE_EXPAND=1,1 note claims a nonzero symbol promotion" \
    || no "B1b DISCLOSURE: RIPWIRE_EXPAND=1,1 did not disclose a nonzero promotion — $( printf '%s' "$LIFT_EXP" | grep -o 'structural expansion:[^]]*]' )"
printf '%s' "$LIFT_EXP" | grep -q 'RIPWIRE_EXPAND=1,1' \
    && ok "B2 DISCLOSURE: the note echoes the env value that produced it" \
    || no "B2 DISCLOSURE: the note does not echo RIPWIRE_EXPAND=1,1"

mkdir -p "$TMP/onefile_exp"
cat > "$TMP/onefile_exp/only.c" <<'EOF'
int lonely_widget_fn( int x ) { return x; }
EOF
NOOP_EXP="$( RIPWIRE_EXPAND="8,8" "$BIN" "$TMP/onefile_exp" --for="widget" --no-cache 2>/dev/null )"
printf '%s' "$NOOP_EXP" | grep -q 'structural expansion:' \
    && no "B3 SILENCE (fired but moved nothing): a single-file corpus still carries a structural-expansion note" \
    || ok "B3 SILENCE (fired but moved nothing): a single-file corpus carries no structural-expansion note"

# ===================================================================================================
# (C) --json dialect carries the same two notes under their own keys (same absent-unless-present rule)
# ===================================================================================================
echo "-- (C) --json dialect parity"
LIFT_SIB_JSON="$( RIPWIRE_SIBLIFT="1,1" "$BIN" "$SIB" --for="$SIBQ" --json --no-cache 2>/dev/null )"
python3 - "$LIFT_SIB_JSON" <<'PY' > "$TMP/c1.res" 2>&1
import json, sys
try:
    d = json.loads(sys.argv[1])
except Exception as e:
    print("C1 NO --json did not parse: %s" % e); raise SystemExit
v = d.get("siblift", "")
print("C1 %s --json carries \"siblift\" naming a promotion (got %r)" % ("OK" if "promoted" in v and "sibling lift" in v else "NO", v))
PY
if grep -qE '^C1 OK' "$TMP/c1.res"; then ok "$( grep '^C1' "$TMP/c1.res" | cut -d' ' -f3- )"; else no "$( cat "$TMP/c1.res" )"; fi

BASE_SIB_JSON="$( "$BIN" "$SIB" --for="$SIBQ" --json --no-cache 2>/dev/null )"
printf '%s' "$BASE_SIB_JSON" | grep -q '"siblift"' \
    && no "C2 SILENCE: the default --json carries a \"siblift\" key it should not" \
    || ok "C2 SILENCE: the default --json carries no \"siblift\" key"

LIFT_EXP_JSON="$( RIPWIRE_EXPAND="1,1" "$BIN" "$EXP" --for="$EXPQ" --json --no-cache 2>/dev/null )"
python3 - "$LIFT_EXP_JSON" <<'PY' > "$TMP/c3.res" 2>&1
import json, sys
try:
    d = json.loads(sys.argv[1])
except Exception as e:
    print("C3 NO --json did not parse: %s" % e); raise SystemExit
v = d.get("expand", "")
print("C3 %s --json carries \"expand\" naming a promotion (got %r)" % ("OK" if "promoted" in v and "structural expansion" in v else "NO", v))
PY
if grep -qE '^C3 OK' "$TMP/c3.res"; then ok "$( grep '^C3' "$TMP/c3.res" | cut -d' ' -f3- )"; else no "$( cat "$TMP/c3.res" )"; fi

# ===================================================================================================
# (D) rejected env values — SET but malformed/out-of-range degrades to OFF and SAYS SO (stderr), never
#     crashes, and never disclosed as if a lift had happened.
# ===================================================================================================
echo "-- (D) malformed/out-of-range env values"

for bad in "99,99" "banana" "3," ",3"; do
    RIPWIRE_SIBLIFT="$bad" "$BIN" "$SIB" --for="$SIBQ" --no-cache >"$TMP/bad_sib.xml" 2>"$TMP/bad_sib.err"
    rc=$?
    [ $rc -eq 0 ] && ok "D1 RIPWIRE_SIBLIFT=\"$bad\" exits 0 (degrades, no crash)" \
                  || no "D1 RIPWIRE_SIBLIFT=\"$bad\" exited non-zero (rc=$rc)"
    grep -q 'sibling lift:' "$TMP/bad_sib.xml" \
        && no "D2 RIPWIRE_SIBLIFT=\"$bad\": rejected value still disclosed a lift (should be OFF)" \
        || ok "D2 RIPWIRE_SIBLIFT=\"$bad\": rejected value carries no lift note (correctly OFF)"
    grep -qi 'RIPWIRE_SIBLIFT' "$TMP/bad_sib.err" \
        && ok "D3 RIPWIRE_SIBLIFT=\"$bad\": stderr names the rejected variable" \
        || no "D3 RIPWIRE_SIBLIFT=\"$bad\": no stderr note naming the rejected variable"
done

for bad in "99,99" "banana" "3," ",3"; do
    RIPWIRE_EXPAND="$bad" "$BIN" "$EXP" --for="$EXPQ" --no-cache >"$TMP/bad_exp.xml" 2>"$TMP/bad_exp.err"
    rc=$?
    [ $rc -eq 0 ] && ok "D4 RIPWIRE_EXPAND=\"$bad\" exits 0 (degrades, no crash)" \
                  || no "D4 RIPWIRE_EXPAND=\"$bad\" exited non-zero (rc=$rc)"
    grep -q 'structural expansion:' "$TMP/bad_exp.xml" \
        && no "D5 RIPWIRE_EXPAND=\"$bad\": rejected value still disclosed a lift (should be OFF)" \
        || ok "D5 RIPWIRE_EXPAND=\"$bad\": rejected value carries no lift note (correctly OFF)"
    grep -qi 'RIPWIRE_EXPAND' "$TMP/bad_exp.err" \
        && ok "D6 RIPWIRE_EXPAND=\"$bad\": stderr names the rejected variable" \
        || no "D6 RIPWIRE_EXPAND=\"$bad\": no stderr note naming the rejected variable"
done

# a well-formed, IN-RANGE value must NOT trip the rejection alert (positive control on D3/D6 above).
RIPWIRE_SIBLIFT="1,1" "$BIN" "$SIB" --for="$SIBQ" --no-cache >/dev/null 2>"$TMP/good_sib.err"
grep -qi 'RIPWIRE_SIBLIFT' "$TMP/good_sib.err" \
    && no "D7 an ACCEPTED RIPWIRE_SIBLIFT=1,1 wrongly logged a rejection alert" \
    || ok "D7 an accepted RIPWIRE_SIBLIFT=1,1 logs no rejection alert"
RIPWIRE_EXPAND="1,1" "$BIN" "$EXP" --for="$EXPQ" --no-cache >/dev/null 2>"$TMP/good_exp.err"
grep -qi 'RIPWIRE_EXPAND' "$TMP/good_exp.err" \
    && no "D8 an ACCEPTED RIPWIRE_EXPAND=1,1 wrongly logged a rejection alert" \
    || ok "D8 an accepted RIPWIRE_EXPAND=1,1 logs no rejection alert"

# ===================================================================================================
# (E) determinism + well-formedness of every document this gate produced
# ===================================================================================================
echo "-- (E) determinism + well-formedness"
run_sib_env "1,1" >"$TMP/e_a.xml"
run_sib_env "1,1" >"$TMP/e_b.xml"
if cmp -s "$TMP/e_a.xml" "$TMP/e_b.xml"; then ok "E1 RIPWIRE_SIBLIFT=1,1 output is deterministic"; else no "E1 RIPWIRE_SIBLIFT=1,1 output is non-deterministic"; fi
run_exp_env "1,1" >"$TMP/e_c.xml"
run_exp_env "1,1" >"$TMP/e_d.xml"
if cmp -s "$TMP/e_c.xml" "$TMP/e_d.xml"; then ok "E2 RIPWIRE_EXPAND=1,1 output is deterministic"; else no "E2 RIPWIRE_EXPAND=1,1 output is non-deterministic"; fi
if command -v xmllint >/dev/null 2>&1; then
    xmlfail=0
    for f in "$TMP/e_a.xml" "$TMP/e_c.xml"; do
        xmllint --noout "$f" >/dev/null 2>&1 || { xmlfail=1; echo "      ill-formed: $f"; }
    done
    if [ "$xmlfail" -eq 0 ]; then ok "E3 every lifted document is well-formed XML"; else no "E3 a lifted document is ill-formed"; fi
else
    ok "E3 (skipped: no xmllint)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"

#!/usr/bin/env bash
# sibliftcheck.sh — R4/PREREG (bench/locbench/results/r4_siblift/PREREG.md): env-gated sibling lift on
# the --for lens. RIPWIRE_SIBLIFT="<seedFiles>,<sibPerSeed>" (e.g. "2,1"): after ranking + mention boost,
# take the top seedFiles FILES by best-symbol score; for each, lift the sibPerSeed same-immediate-directory
# sibling files with the highest existing POSITIVE lexical score (a zero-scored sibling never lifts) into
# the slot ladder just below the existing top block. max() semantics — anything already ranked higher
# stays where it is; #1 is NEVER displaced. Env unset -> byte-identical output (inert default).
#
# THE FEATURE DOES NOT EXIST YET. This gate is written first, against the current (inert) binary, so it is
# red on the signal/guard assertions today and turns green the moment RIPWIRE_SIBLIFT is implemented.
#
#   test/sibliftcheck.sh                       # uses build/ripwire on an inline fixture
#   RIPWIRE_BIN=asan/ripwire test/sibliftcheck.sh
#
# Sections:
#   (i)   INERT           — env UNSET == RIPWIRE_SIBLIFT="" == today's binary, byte-identical. PASSES today.
#   (ii)  SIGNAL           — RIPWIRE_SIBLIFT="1,1": beta.py (weak same-dir sibling of the #1 file) must
#                             enter the --format=candidates top 5; gamma.py (weak, DIFFERENT dir) must not
#                             move off its plain rank. RED today (env is a no-op, so nothing lifts).
#   (iii) ZERO-EVIDENCE GUARD — RIPWIRE_SIBLIFT="2,2": the legit positive-scored sibling (beta.py, ranked
#                             well outside the top 10 at baseline) must be pulled into the top 10 (proof the
#                             mechanism actually engaged for this config — RED today, since nothing engages
#                             yet) AND the zero-scored sibling (zero.py) must never be pulled into the top 10
#                             even though sibPerSeed=2 leaves it a nominal second slot (holds both today and
#                             after — a zero-scored sibling never lifts).
#   (iv)  #1 STABILITY     — with the env set, the r=1 candidate is identical to the env-unset r=1. This is
#                             a hard invariant (#1 is NEVER displaced), so it already holds today (the env is
#                             inert) and must keep holding after implementation — recorded here as a
#                             regression pin, not expected to go red.
#   (v)   determinism x2 with the env set + xmllint --noout clean (skipped if xmllint absent).
#   Malformed env values ("0,0", "9,9", "banana") must not crash: assert exit 0 only (pre-implementation,
#   byte-exact behavior for these is not asserted — only "does not crash").
#
# Exits non-zero if ANY assertion fails (inertness assertions included) — that is what makes this a gate,
# not just a today's-status report. Run it once to see today's expected red spots, then again after the
# candidate lands to confirm they turned green.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "sibliftcheck: BIN=$BIN"

# ── fixture ──────────────────────────────────────────────────────────────────────────────────────────
# pkg/alpha.py holds 3 functions strongly matching the query — the clear #1 file. pkg/beta.py (SAME dir
# as alpha.py) shares exactly one weak token ("widget") with the query: a positive but low score, ranked
# well outside the top 10 at baseline. other/gamma.py (DIFFERENT dir) shares that SAME weak token, so its
# raw score is comparable to beta.py's, but same-dir-only scoping must never lift it. pkg/zero.py (SAME
# dir as alpha.py) shares NO token at all — score 0, must never lift under any config. mid/filler{1..9}.py
# are mid-strength distractors that establish a real ranked middle so beta.py's baseline rank is
# unambiguously outside both the top 5 and the top 10 (making the SIGNAL/GUARD lift assertions meaningful
# rather than vacuous).
FIX="$TMP/fix"
mkdir -p "$FIX/pkg" "$FIX/mid" "$FIX/other"

cat > "$FIX/pkg/alpha.py" <<'PY'
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

cat > "$FIX/pkg/beta.py" <<'PY'
def unrelated_cache_flush(entries):
    """Flush the widget cache once entries go stale."""
    return [e for e in entries if e.fresh]
PY

cat > "$FIX/pkg/zero.py" <<'PY'
def totally_unrelated_math(a, b):
    """Multiply two numbers together for the accounting report."""
    return a * b
PY

cat > "$FIX/other/gamma.py" <<'PY'
def totally_different_thing(x):
    """A widget appears here too, but nothing else about it matches."""
    return x
PY

cat > "$FIX/mid/filler1.py" <<'PY'
def build_pipeline_stage(items):
    """Build a processing pipeline stage for the batch."""
    return items
PY

cat > "$FIX/mid/filler2.py" <<'PY'
def process_batch_items(items):
    """Process a batch of items through several stages."""
    return items
PY

cat > "$FIX/mid/filler3.py" <<'PY'
def record_pipeline_metrics(records):
    """Record pipeline metrics for later inspection."""
    return records
PY

cat > "$FIX/mid/filler4.py" <<'PY'
def process_pipeline_records(records):
    """Process pipeline records before the final stage."""
    return records
PY

cat > "$FIX/mid/filler5.py" <<'PY'
def records_process_pipeline(records):
    """Records processed through the pipeline in order."""
    return records
PY

cat > "$FIX/mid/filler6.py" <<'PY'
def stage_pipeline_builder(x):
    """Builder for a pipeline stage configuration object."""
    return x
PY

cat > "$FIX/mid/filler7.py" <<'PY'
def pipeline_config_loader(x):
    """Loader for pipeline configuration, no processing here."""
    return x
PY

cat > "$FIX/mid/filler8.py" <<'PY'
def archive_stored_records(x):
    """Archive stored records for later review, no other overlap."""
    return x
PY

cat > "$FIX/mid/filler9.py" <<'PY'
def process_incoming_signal(x):
    """Process an incoming signal from the sensor bus."""
    return x
PY

QUERY="widget pipeline process records"

cands(){ "$BIN" "$FIX" --for="$QUERY" --format=candidates --top-k=30 --no-cache 2>/dev/null; }
candsSib(){ RIPWIRE_SIBLIFT="$1" "$BIN" "$FIX" --for="$QUERY" --format=candidates --top-k=30 --no-cache 2>/dev/null; }
forXml(){ "$BIN" "$FIX" --for="$QUERY" --no-cache 2>/dev/null; }
forXmlSib(){ RIPWIRE_SIBLIFT="$1" "$BIN" "$FIX" --for="$QUERY" --no-cache 2>/dev/null; }
rankOf(){ printf '%s' "$1" | grep -o "<cand r=\"[0-9]*\" [^>]*n=\"$2\"" | grep -o 'r="[0-9]*"' | grep -o '[0-9]*' | head -1; }
top1n(){ printf '%s' "$1" | grep -o '<cand r="1" [^>]*n="[a-zA-Z_0-9]*"' | grep -o 'n="[a-zA-Z_0-9]*"' | head -1; }

BASE_CAND="$( cands )"
[ -n "$BASE_CAND" ] || { echo "sibliftcheck: baseline --format=candidates produced no output — fixture or binary broken"; exit 2; }

rBetaBase="$( rankOf "$BASE_CAND" unrelated_cache_flush )"
rGammaBase="$( rankOf "$BASE_CAND" totally_different_thing )"
rZeroBase="$( rankOf "$BASE_CAND" totally_unrelated_math )"
[ -n "$rBetaBase" ] && [ -n "$rGammaBase" ] && [ -n "$rZeroBase" ] \
    || { echo "sibliftcheck: could not locate beta/gamma/zero symbols in the baseline ranking — fixture broken"; echo "$BASE_CAND"; exit 2; }
if [ "$rBetaBase" -gt 10 ] && [ "$rGammaBase" -le 12 ]; then
    ok "fixture shape (beta.py baseline rank $rBetaBase is outside top 10; gamma.py baseline rank $rGammaBase)"
else
    no "fixture shape unexpected (beta rank=$rBetaBase expected >10, gamma rank=$rGammaBase) — lift assertions below may be vacuous"
fi

# ── (i) INERT — env UNSET == RIPWIRE_SIBLIFT="" == today's binary, byte-identical. Labeled clearly: this
#     half PASSES today (and must keep passing after the candidate lands — it is the inert-default contract). ──
BASE_FOR="$( forXml )"
EMPTYENV_FOR="$( forXmlSib "" )"
[ -n "$BASE_FOR" ] && [ "$BASE_FOR" = "$EMPTYENV_FOR" ] \
    && ok "INERT: --for output, env UNSET == RIPWIRE_SIBLIFT=\"\" (byte-identical)" \
    || no "INERT: --for output changed between env UNSET and RIPWIRE_SIBLIFT=\"\""

EMPTYENV_CAND="$( candsSib "" )"
[ "$BASE_CAND" = "$EMPTYENV_CAND" ] \
    && ok "INERT: --format=candidates, env UNSET == RIPWIRE_SIBLIFT=\"\" (byte-identical)" \
    || no "INERT: --format=candidates changed between env UNSET and RIPWIRE_SIBLIFT=\"\""

# a nontrivial-looking but still-unset-equivalent baseline: today's binary simply never reads the var, so
# any value must currently be behaviorally inert on this SAME assertion shape — checked again below via the
# malformed-value section (exit-0-only there; this section is the strict byte-identity half).

# ── (ii) SIGNAL (RED today — RIPWIRE_SIBLIFT is not implemented, so nothing lifts) ────────────────────
SIG11_CAND="$( candsSib "1,1" )"
rBetaSig="$( rankOf "$SIG11_CAND" unrelated_cache_flush )"
rGammaSig="$( rankOf "$SIG11_CAND" totally_different_thing )"
if [ -n "$rBetaSig" ] && [ "$rBetaSig" -le 5 ]; then
    ok "SIGNAL: RIPWIRE_SIBLIFT=1,1 lifts beta.py's function into the top 5 (rank $rBetaSig)"
else
    no "SIGNAL: RIPWIRE_SIBLIFT=1,1 did not lift beta.py's function into the top 5 (rank ${rBetaSig:-absent}, baseline was $rBetaBase)"
fi
# PREREG contract: a different-dir file must never be LIFTED (rank must not IMPROVE). Its ordinal may
# legitimately worsen by the rows lifted above it — pinning "rank unchanged" would forbid the lift itself.
if [ -n "$rGammaSig" ] && [ "$rGammaSig" -ge "$rGammaBase" ]; then
    ok "SIGNAL: gamma.py (different dir) is not lifted above its plain rank $rGammaBase under RIPWIRE_SIBLIFT=1,1 (now $rGammaSig; same-dir-only scoping)"
else
    no "SIGNAL: gamma.py IMPROVED under RIPWIRE_SIBLIFT=1,1 (baseline=$rGammaBase now=${rGammaSig:-absent}) — same-dir scoping violated"
fi

# ── (iii) ZERO-EVIDENCE GUARD (the engagement half is RED today; the exclusion half holds always) ──────
SIG22_CAND="$( candsSib "2,2" )"
rBetaG="$( rankOf "$SIG22_CAND" unrelated_cache_flush )"
rZeroG="$( rankOf "$SIG22_CAND" totally_unrelated_math )"
if [ -n "$rBetaG" ] && [ "$rBetaG" -le 10 ]; then
    ok "GUARD: RIPWIRE_SIBLIFT=2,2 pulls the legit positive-scored sibling (beta.py) into the top 10 (rank $rBetaG) — mechanism engaged"
else
    no "GUARD: RIPWIRE_SIBLIFT=2,2 did not pull beta.py into the top 10 (rank ${rBetaG:-absent}, baseline was $rBetaBase) — mechanism not engaged"
fi
if [ -n "$rZeroG" ] && [ "$rZeroG" -gt 10 ]; then
    ok "GUARD: zero-scored sibling (zero.py) stays outside the top 10 under RIPWIRE_SIBLIFT=2,2 (rank $rZeroG) — a zero score never lifts"
else
    no "GUARD: zero-scored sibling (zero.py) entered the top 10 under RIPWIRE_SIBLIFT=2,2 (rank ${rZeroG:-absent}) — zero-evidence guard violated"
fi

# ── (iv) #1 STABILITY — #1 is NEVER displaced. A hard invariant: it already holds today (the env is a
#     no-op) and must keep holding once the candidate lands. Recorded as a pin, not expected to regress. ──
t1Base="$( top1n "$BASE_CAND" )"
t1Sib="$( top1n "$SIG22_CAND" )"
[ -n "$t1Base" ] && [ "$t1Base" = "$t1Sib" ] \
    && ok "#1 STABILITY: r=1 under RIPWIRE_SIBLIFT=2,2 ($t1Sib) identical to env-unset r=1 ($t1Base)" \
    || no "#1 STABILITY: r=1 displaced by RIPWIRE_SIBLIFT=2,2 (env-unset=$t1Base, env-set=$t1Sib)"

# ── (v) determinism x2 with the env set + xmllint --noout clean ────────────────────────────────────────
forXmlSib "2,2" >"$TMP/d1.xml"
forXmlSib "2,2" >"$TMP/d2.xml"
[ -s "$TMP/d1.xml" ] && cmp -s "$TMP/d1.xml" "$TMP/d2.xml" \
    && ok "determinism x2 with RIPWIRE_SIBLIFT=2,2 set" \
    || no "non-deterministic (or empty) output with RIPWIRE_SIBLIFT=2,2 set"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/d1.xml" 2>/dev/null && ok "RIPWIRE_SIBLIFT=2,2 output is xmllint-clean (G4)" || no "RIPWIRE_SIBLIFT=2,2 output not well-formed"
else
    ok "xmllint not present — skipped (G4 covered elsewhere)"
fi

# ── malformed env values must not crash — exit 0 only, no byte-equality asserted pre-implementation ────
for bad in "0,0" "9,9" "banana"; do
    RIPWIRE_SIBLIFT="$bad" "$BIN" "$FIX" --for="$QUERY" --format=candidates --top-k=30 --no-cache >/dev/null 2>"$TMP/bad.err"
    rc=$?
    [ $rc -eq 0 ] && ok "malformed RIPWIRE_SIBLIFT=\"$bad\" does not crash (exit 0)" \
                  || no "malformed RIPWIRE_SIBLIFT=\"$bad\" exited non-zero (rc=$rc): $( head -2 "$TMP/bad.err" )"
done

[ "$fail" = 0 ] && echo 'ALL PASS' || echo 'FAILURES ABOVE'
exit "$fail"

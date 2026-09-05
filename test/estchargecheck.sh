#!/usr/bin/env bash
# estchargecheck.sh — §H7 / §B13.4 / §B7.8 gate: EVERY emitted payload is CHARGED to est_tokens, the
# --token-budget gate actually stops it, --max-tokens' ceiling is disclosed in the currency it reports,
# and the withheld artifact uses the withheld_est_tokens vocabulary.
#
# THE BUG (§H7): serialize's est_tokens charged the MAP only. The
# --expand payload had been fixed once (serialize.h's own extraBodyTokens comment names the defect), but
# the un-named siblings — --metrics decoration, <sigs> (--pack-signatures), <src> (--pack-top-n) and
# <outline> — were never covered, so four different payloads reported the SAME number:
#     --top-k=10                  1435 B  est_tokens=507
#     --top-k=10 --metrics        2129 B  est_tokens=507   (~1.5x under)
#     --top-k=10 --pack-signatures 12850 B est_tokens=507  (~7.8x under)
#     --top-k=10 --pack-top-n=3   67143 B est_tokens=507   (~52x under)
#     --top-k=10 --outline=SYM     2668 B est_tokens=507   (~2x under; not even in the audit's table)
# and --token-budget — the CI stop — read that number, so `--pack-top-n=3 --token-budget=600` exited 0
# and streamed 67 KB (~26 900 tokens, ~45x the budget).
#
# THE FIX: est_tokens is computed from the ACTUAL EMITTED BYTES of the map's rows plus each payload
# section (measured through open_memstream, converted at the calibrated per-language / body rates), not
# from a per-verb formula. That is what #1 below tests, and it tests it as a PROPERTY rather than a pinned
# number: the implied byte rate (output bytes / reported est_tokens) must land inside the calibrated band.
# A new payload section added later and NOT charged pushes the rate straight out of band and reds this
# gate — that band is the recurrence guard, and it is the reason this file asserts a band and never a
# bit-exact token count (house rule: float/estimate assertions get a tolerance, never bit-equality).
#
# Usage:  bash test/estchargecheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/estchargecheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){   printf '  PASS  %s\n' "$*"; }
no(){   printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
cd "$ROOT"
echo "estchargecheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# ── BUILD-FLAVOUR / DEGRADE-OBSERVABILITY PROBE (read by #14 below) ───────────────────────────────────
# CI runs the whole suite TWICE: once against a Release binary (catches optimizer-only bugs, e.g. the
# VERIFY-then-defend trap) and once against the plain build — Release defines NDEBUG, which compiles
# DEGRADED_PATH_ALERT out, so "if you add a degrade path, it is the PLAIN run that proves it" (CLAUDE.md).
# #14 asserts a DEGRADED_PATH_ALERT, so under the Release binary it is unobservable BY DESIGN and must
# SKIP with the reason named; under the plain binary it must assert. What it must never do is pass
# silently for lack of an alert it could not have seen — the 2026-07-27 CI trap this gate was written
# against. (Before 2026-08-01 it took the other branch and FAILED under NDEBUG, which is the same trap
# from the other side: it made the Release CI leg unconditionally red, so the leg could never be trusted.)
#
# Two INDEPENDENT readings, because either alone can lie:
#   (1) an unrelated, already-gated degrade path (--since=<not a date> → "[math degraded]"). If THAT one
#       is silent too, this binary compiles alerts out globally rather than #14's own seam having broken.
#   (2) --version's build-type token — versioncheck's source of truth, set by CMakeLists from
#       CMAKE_BUILD_TYPE ("dev" for the plain configure). Release/RelWithDebInfo/MinSizeRel define
#       NDEBUG; nothing else does.
# Only when BOTH agree — no alert observable anywhere AND an NDEBUG-defining flavour — is a skip honest.
# A binary that CLAIMS to be dev/asan yet observes no alerts is a real FAILURE, and so is one that can
# observe the unrelated alert but not #14's own.
alerts_observable=0
"$BIN" test/fixture --rank-by=churn --since=notadate >/dev/null 2>"$TMP/flavour.err"
grep -q 'math degraded' "$TMP/flavour.err" && alerts_observable=1
BUILD_FLAVOUR="$( "$BIN" --version 2>/dev/null | sed -nE 's/^[^(]*\(([^,)]*).*/\1/p' )"
case "$BUILD_FLAVOUR" in
    Release|RelWithDebInfo|MinSizeRel) ndebug_flavour=1 ;;
    *)                                 ndebug_flavour=0 ;;
esac

# The symbol the payload arms expand/outline: a real, large fn in src/ (stable across rounds).
SYM=estimateTokens

# est FILE → the header's first est_tokens number (the map header's own).
est_of(){ grep -aoE 'est_tokens=[0-9]+' "$1" | head -1 | grep -oE '[0-9]+'; }
bytes_of(){ wc -c < "$1" | tr -d ' '; }

# ── #1: the CHARGE band. For every payload shape, bytes/est_tokens must sit inside the calibrated B/tok
#    band FOR THAT SHAPE. Lower bound everywhere is 2.00: the densest calibrated language is 2.36 B/tok
#    (serialize.h kMinBytesPerToken) and 2.00 leaves rounding/envelope slack under it. The UPPER bound is
#    per family, because the two families genuinely tokenize differently and one shared upper bound is
#    wide enough to swallow a real defect (measured: the uncharged --metrics map sits at 4.19 B/tok, which
#    a single 4.20 ceiling passes):
#      MARKUP shapes (map / --metrics / <sigs>)  → <= 3.20  (table spans 2.36-2.59; Json content 3.10)
#      BODY shapes  (<src> / <bodies> / <outline>) → <= 4.20  (kBytesPerTokenBody 3.80 + slack)
#    Anything OUTSIDE its band is not an estimate, it is an uncharged (or double-charged) payload.
#    Integer math throughout: rate*100. ─────────────────────────────────────────────────────────────────
declare -a SHAPES=(
    "map:320:--top-k=10"
    "metrics:320:--top-k=10 --metrics"
    "sigs:320:--top-k=10 --pack-signatures"
    "src:420:--top-k=10 --pack-top-n=3"
    "bodies:420:--top-k=10 --expand=$SYM"
    "outline:420:--top-k=10 --outline=$SYM"
    "bodies+sigs:420:--top-k=10 --pack-signatures --expand=$SYM"
    # --max-tokens rides this list so its §B13.4 disclosure is band-checked and G4-checked (#8) like every
    # other shape: the first spelling of that clause carried a "--" inside an XML comment and xmllint
    # rejected the whole document, which #8 only sees if the shape is enumerated here.
    "maxtokens:320:--max-tokens=1500"
)
for entry in "${SHAPES[@]}"; do
    label="${entry%%:*}"; rest="${entry#*:}"; hi="${rest%%:*}"; args="${rest#*:}"
    # shellcheck disable=SC2086
    "$BIN" src $args --no-cache >"$TMP/$label.out" 2>/dev/null
    B="$( bytes_of "$TMP/$label.out" )"
    E="$( est_of "$TMP/$label.out" )"
    if [ -z "$E" ] || [ "$E" -le 0 ] 2>/dev/null; then
        no "#1 $label ($args): no positive est_tokens in the header (got '$E')"
        continue
    fi
    R=$(( B * 100 / E ))
    if [ "$R" -ge 200 ] && [ "$R" -le "$hi" ]; then
        ok "#1 $label: $B B / est_tokens=$E = $(( R / 100 )).$(( R % 100 )) B/tok — inside the 2.00-$(( hi / 100 )).$(( hi % 100 )) band"
    else
        no "#1 $label: $B B / est_tokens=$E = $(( R / 100 )).$(( R % 100 )) B/tok — OUTSIDE the 2.00-$(( hi / 100 )).$(( hi % 100 )) band (payload not charged)"
    fi
done

# ── #2: MONOTONE charging — adding a payload to the same map can never LOWER the reported estimate. ────
E_MAP="$( est_of "$TMP/map.out" )"
mono=1
for label in metrics sigs src bodies outline "bodies+sigs"; do
    E="$( est_of "$TMP/$label.out" )"
    [ -n "$E" ] && [ "$E" -ge "$E_MAP" ] 2>/dev/null || { echo "    $label est=$E < bare map est=$E_MAP"; mono=0; }
done
[ "$mono" = 1 ] && ok "#2 monotone: every payload shape reports est_tokens >= the bare map's ($E_MAP)" \
    || no "#2 a payload shape reported FEWER tokens than the bare map ($E_MAP) — charging is not monotone"

# ── #3: the --token-budget GATE actually stops each payload. The audit's own repro: a budget the BARE
#    map fits, with a payload that blows past it, must exit 3 and withhold — pre-fix both exited 0 and
#    streamed 12 KB / 67 KB. Budget is set from the bare map's own estimate (so the map alone always
#    fits) and each payload arm must fail it. ────────────────────────────────────────────────────────────
TB=$(( E_MAP + 20 ))
"$BIN" src --top-k=10 --token-budget=$TB --no-cache >"$TMP/tb_map.out" 2>"$TMP/tb_map.err"
rc_map=$?
[ "$rc_map" -eq 0 ] \
    && ok "#3 control: the bare map fits --token-budget=$TB (exit 0)" \
    || no "#3 control: the bare map should fit --token-budget=$TB, got exit $rc_map"
for entry in "sigs:--pack-signatures" "src:--pack-top-n=3" "bodies:--expand=$SYM" "outline:--outline=$SYM"; do
    label="${entry%%:*}"; args="${entry#*:}"
    # shellcheck disable=SC2086
    "$BIN" src --top-k=10 $args --token-budget=$TB --no-cache >"$TMP/tb_$label.out" 2>"$TMP/tb_$label.err"
    rc=$?
    OB="$( bytes_of "$TMP/tb_$label.out" )"
    if [ "$rc" -eq 3 ] && [ "$OB" -lt 2048 ]; then
        ok "#3 $label ($args) --token-budget=$TB: exit 3, payload withheld ($OB B on stdout)"
    else
        no "#3 $label ($args) --token-budget=$TB: expected exit 3 + withheld, got exit=$rc stdout=$OB B — the gate does not see this payload"
    fi
done

# ── #4 (§B7.8): the WITHHELD artifact uses the withheld_est_tokens vocabulary --recall already renamed
#    this exact semantic to (recall.h). `est_tokens=` on a withheld artifact names a number that describes
#    something the caller did NOT receive. XML and JSON both. ─────────────────────────────────────────────
"$BIN" src --token-budget=1 --no-cache >"$TMP/wh.xml" 2>"$TMP/wh.err"
grep -aq 'withheld_est_tokens="' "$TMP/wh.xml" \
    && ok "#4 XML withheld record uses withheld_est_tokens=\"…\"" \
    || no "#4 XML withheld record does not use withheld_est_tokens= (got: $( head -c 200 "$TMP/wh.xml" ))"
grep -aqE '<r est_tokens="' "$TMP/wh.xml" \
    && no "#4 XML withheld record still spells the plain est_tokens= on the artifact it withheld" \
    || ok "#4 XML withheld record no longer spells a bare est_tokens= for the withheld artifact"
"$BIN" src --token-budget=1 --json --no-cache >"$TMP/wh.json" 2>"$TMP/whj.err"
grep -aq '"withheld_est_tokens":' "$TMP/wh.json" \
    && ok "#4 JSON withheld record uses \"withheld_est_tokens\"" \
    || no "#4 JSON withheld record does not use \"withheld_est_tokens\" (got: $( head -c 200 "$TMP/wh.json" ))"
grep -aq 'withheld_est_tokens=[0-9]* > budget=' "$TMP/wh.err" \
    && ok "#4 stderr names withheld_est_tokens vs the budget" \
    || no "#4 stderr does not name withheld_est_tokens vs budget (got: $( cat "$TMP/wh.err" ))"

# ── #5 (§B13.4): --max-tokens=N is a CONSERVATIVE BYTE ceiling, and it must SAY SO. The delivered map
#    honours N*2.36*0.90 bytes exactly but reports est_tokens ~81% of N, so a caller composing
#    --max-tokens with --token-budget (which --help invites) was comparing two different currencies with
#    no disclosure anywhere. The ceiling stays conservative — a hard cap must never become a target — so
#    the fix is disclosure: the shaped map names the ceiling, its rate and its headroom. ──────────────────
#    §F5 (CA4 wave-1 verifier) — SWEPT ACROSS THE WHOLE USABLE RANGE, not two comfortable values. This arm
#    used to run `for N in 1200 1500` only: the two values where neither assertion CAN fail. Both were false
#    for every N <= ~450 on src/, where the map's fixed floor (envelope + legend + the §B13.4 disclosure
#    clause itself) exceeds the ceiling with even ONE symbol emitted — 975 B against an 849 B cap at N=400,
#    15% over at rc=0 with empty stderr and the 849 printed inside the 975-byte document. Two consequences
#    for the assertions, both of them the honest reading rather than a widened tolerance:
#      * MB<=LIM becomes "MB<=LIM OR over_ceiling=1 is stated" — a cap that cannot be honoured must be
#        LABELLED (the treatment --for/--pack-task/--recall already give the identical state), never silently
#        exceeded, and never silently "fixed" by loosening the cap.
#      * ME<=N likewise: once the floor is over the byte ceiling the document really does cost more than N
#        tokens, so reporting est_tokens>N is the truth and over_ceiling= is what makes it readable.
#    The small end is where fixed overhead dominates, which is exactly why it is swept: EVERY future byte
#    added to the envelope or the legend shows up here first.
for N in 100 300 400 450 500 600 800 1200 1500 3000 6000; do
    "$BIN" src --max-tokens=$N --no-cache >"$TMP/mt$N.out" 2>"$TMP/mt$N.err"
    MB="$( bytes_of "$TMP/mt$N.out" )"
    ME="$( est_of "$TMP/mt$N.out" )"
    LIM="$( awk "BEGIN{printf \"%d\", $N*2.36*0.90}" )"
    # the ATTRIBUTE spelling only. kMaxTokensFitLegend glosses the marker WITHOUT the `=1` precisely so this
    # grep cannot match the legend that defines it (the first spelling of that clause did, and scored every
    # N as labelled — the reason this gate sweeps N instead of trusting one value).
    #
    # STATS-COMMENT-SCOPED (2026-07-31, the corpus-drift sweep). The legend is not the only other place these
    # bytes can appear: the map emits <doc> excerpts of the corpus's own doc comments, and src/ mentions
    # `over_ceiling` 38 times. A doc excerpt carrying the marker would set OVER=1 and thereby EXCUSE a real
    # cap breach at line 174 — the same defect as #14d's document-wide grep, aimed at the arm that matters
    # most, since here a false POSITIVE hides a failure rather than inventing one. `<!-- files=…-->` is the
    # stats comment the emitter writes the marker into, and it is the only place the marker is a claim.
    STATS="$( grep -ao '<!-- files=[^>]*-->' "$TMP/mt$N.out" | head -1 )"
    OVER=0;  printf '%s' "$STATS" | grep -q 'over_ceiling=1' && OVER=1
    if [ "$MB" -le "$LIM" ] 2>/dev/null; then
        ok "#5 --max-tokens=$N: $MB B within the $LIM B ceiling (conservative cap holds)"
    elif [ "$OVER" = 1 ]; then
        ok "#5 --max-tokens=$N: $MB B over the $LIM B floor-limited ceiling and SAYS SO (over_ceiling=1)"
    else
        no "#5 --max-tokens=$N: $MB B EXCEEDS the $LIM B ceiling with NO over_ceiling=1 label"
    fi
    if { [ -n "$ME" ] && [ "$ME" -le "$N" ]; } 2>/dev/null; then
        ok "#5 --max-tokens=$N: reported est_tokens=$ME <= the asked $N (same-direction in the reported currency)"
    elif [ "$OVER" = 1 ]; then
        ok "#5 --max-tokens=$N: est_tokens=$ME > the asked $N, disclosed by over_ceiling=1 (the floor did not fit)"
    else
        no "#5 --max-tokens=$N: reported est_tokens=$ME is NOT <= the asked $N and carries no over_ceiling=1"
    fi
    grep -aq 'max_tokens=' "$TMP/mt$N.out" \
        && ok "#5 --max-tokens=$N: the shaped map DISCLOSES max_tokens= in its own header" \
        || no "#5 --max-tokens=$N: the shaped map does not disclose that a --max-tokens ceiling shaped it"
    grep -aq 'fit_bytes=' "$TMP/mt$N.out" \
        && ok "#5 --max-tokens=$N: the header names the BYTE ceiling (fit_bytes=) it was actually fitted to" \
        || no "#5 --max-tokens=$N: the header does not name the byte ceiling it was fitted to"
done
# and the marker it can emit must be DEFINED in the legend of the map that carries it (§B7 class)
grep -aq 'over_ceiling=floor-alone-exceeded-fit_bytes' "$TMP/mt400.out" \
    && ok "#5 the over_ceiling marker is defined in the legend of the map that states it" \
    || no "#5 --max-tokens emitted an over_ceiling marker its own legend does not define"

# ── #5b (§F5): THE PROBE MUST PRICE THE SHAPE IT BUILDS. The binary search measures a rendered map; every
#    annotation the probe did not carry became a silent breach of the very cap it was computing. All three
#    found members, at the N where each one breached on the pre-fix binary:
#      --map-diff        changed= + at=                     +31 B   (breached at N=3000/6000/12000)
#      --rank-by=churn   rank_by= + window= + churn legend   +118..204 B (breached at nearly every N<=12000)
#      a charged §H7 payload   est_tokens is printed TWICE in the map's own header, so charging an appended
#                        section grows the map's own digit count (+5 B at N=6000 --pack-signatures)
#    The third is measured on the MAP PORTION (through `</r>`), because fit_bytes has only ever been the
#    map's ceiling — the appended payload is charged to est_tokens, not to fit_bytes. ────────────────────────
mapbytes_of(){ python3 - "$1" <<'PY'
import sys
d = open( sys.argv[1], 'rb' ).read()
i = d.find( b'</r>' )
print( i + 4 if i >= 0 else len( d ) )
PY
}
for entry in "mapdiff:3000:--map-diff" "mapdiff2:12000:--map-diff" "churn:800:--rank-by=churn" "churn2:1200:--rank-by=churn" "payload:6000:--pack-signatures" "payload2:6000:--expand=$SYM"; do
    label="${entry%%:*}"; rest="${entry#*:}"; N="${rest%%:*}"; args="${rest#*:}"
    # shellcheck disable=SC2086
    "$BIN" src --max-tokens=$N $args --no-cache >"$TMP/p_$label.out" 2>/dev/null
    PB="$( mapbytes_of "$TMP/p_$label.out" )"
    LIM="$( awk "BEGIN{printf \"%d\", $N*2.36*0.90}" )"
    OVER=0;  head -c "$PB" "$TMP/p_$label.out" | grep -aq 'over_ceiling=1' && OVER=1
    if [ "$PB" -le "$LIM" ] 2>/dev/null; then
        ok "#5b --max-tokens=$N $args: map portion $PB B within the $LIM B ceiling (probe priced the shape it built)"
    elif [ "$OVER" = 1 ]; then
        ok "#5b --max-tokens=$N $args: map portion $PB B over the $LIM B ceiling and SAYS SO (over_ceiling=1)"
    else
        no "#5b --max-tokens=$N $args: map portion $PB B EXCEEDS the $LIM B ceiling, unlabelled — the probe priced a shape it did not build"
    fi
done
# the legend must define both markers AND name the headroom factor + rate, in the map that carries them
grep -aq 'max_tokens=.*2\.36.*0\.90\|max_tokens=.*conservative' "$TMP/mt1500.out" \
    && ok "#5 legend clause defines max_tokens=/fit_bytes= and names the rate + headroom" \
    || no "#5 legend clause for max_tokens=/fit_bytes= missing or does not name the rate + headroom"
# and the DEFAULT map must be byte-identical to a run without --max-tokens support (golden neutrality:
# no --max-tokens ⇒ no marker, no legend clause)
"$BIN" src --top-k=10 --no-cache >"$TMP/neutral.out" 2>/dev/null
grep -aq 'max_tokens=\|fit_bytes=' "$TMP/neutral.out" \
    && no "#5 the default map leaked a max_tokens=/fit_bytes= marker (must be --max-tokens-only)" \
    || ok "#5 the default map carries no max_tokens=/fit_bytes= marker (opt-in, golden-neutral)"

# ── #6: the THIRD estimator (--partition's <bundle est_tokens=>, partition.h) is flat bytes/2.36 — exact
#    and conservative, therefore honest, but a DIFFERENT currency from the map's language-weighted one.
#    It must say which, in its own legend. ─────────────────────────────────────────────────────────────
"$BIN" src --pack-task="estimate tokens" --partition=2 --no-cache >"$TMP/part.out" 2>/dev/null
if grep -aq '<bundle [^>]*est_tokens=' "$TMP/part.out"; then
    grep -aq '2\.36' "$TMP/part.out" \
        && ok "#6 --partition's bundle legend names the 2.36 B/tok rate its est_tokens uses" \
        || no "#6 --partition reports est_tokens with no statement of which estimator/rate produced it"
    # and it must remain EXACT-over-measured-bytes: bytes/2.36, rounded to nearest (tokensForEmittedBytes)
    python3 - "$TMP/part.out" <<'PY' && ok "#6 every <bundle est_tokens= equals its own bytes/2.36 (measured, exact)" \
        || no "#6 a <bundle est_tokens= no longer equals bytes/2.36 — the third estimator drifted"
import re, sys
bad = []
for m in re.finditer(r'<bundle [^>]*bytes="(\d+)"[^>]*est_tokens="(\d+)"', open(sys.argv[1], encoding='utf-8', errors='replace').read()):
    b, e = int(m.group(1)), int(m.group(2))
    if e != int(b / 2.36 + 0.5): bad.append((b, e, int(b / 2.36 + 0.5)))
sys.exit(1 if bad else 0)
PY
else
    no "#6 --partition emitted no <bundle est_tokens= (corpus/flag shape changed — re-anchor this arm)"
fi

# ── #7: determinism — every shape's reported est_tokens is identical run-to-run (est_tokens now derives
#    from measured emitted bytes, so this also guards the measurement path against order/alloc noise). ──
det=1
for entry in "${SHAPES[@]}"; do
    label="${entry%%:*}"; rest="${entry#*:}"; args="${rest#*:}"
    # shellcheck disable=SC2086
    "$BIN" src $args --no-cache >"$TMP/d1.out" 2>/dev/null
    # shellcheck disable=SC2086
    "$BIN" src $args --no-cache >"$TMP/d2.out" 2>/dev/null
    A="$( est_of "$TMP/d1.out" )"; C="$( est_of "$TMP/d2.out" )"
    [ -n "$A" ] && [ "$A" = "$C" ] || { echo "    $label: $A vs $C"; det=0; }
    cmp -s "$TMP/d1.out" "$TMP/d2.out" || { echo "    $label: output not byte-identical run-to-run"; det=0; }
done
[ "$det" = 1 ] && ok "#7 every payload shape is deterministic (est_tokens + full bytes identical run-to-run)" \
    || no "#7 a payload shape is non-deterministic"

# ── #8: G4 — every shape stays well-formed XML (the measurement path must not disturb the document) ────
if command -v xmllint >/dev/null 2>&1; then
    g4=1
    for entry in "${SHAPES[@]}"; do
        label="${entry%%:*}"
        # --pack-top-n / --expand / --outline emit siblings after </r> (documented hybrid), so they are
        # wrapped in <ctx> by the binary itself; xmllint sees one root either way.
        xmllint --noout "$TMP/$label.out" 2>/dev/null || { echo "    $label: xmllint rejected"; g4=0; }
    done
    [ "$g4" = 1 ] && ok "#8 all payload shapes well-formed XML" || no "#8 a payload shape is malformed XML"
else
    printf '  SKIP  #8 xmllint not installed\n'
fi

# ── #9: XML/JSON parity on the charged number — the two serializations must report the SAME est_tokens
#    for the same request (the sibling emitter has its own header writer; a fix applied to one only is
#    exactly how the §H5 dialect divergences are born). ───────────────────────────────────────────────────
"$BIN" src --top-k=10 --metrics --json --no-cache >"$TMP/j.json" 2>/dev/null
JE="$( grep -aoE '"est_tokens":[0-9]+' "$TMP/j.json" | head -1 | grep -oE '[0-9]+' )"
XE="$( est_of "$TMP/metrics.out" )"
JB="$( bytes_of "$TMP/j.json" )"
if [ -n "$JE" ] && [ "$JE" -gt 0 ] 2>/dev/null; then
    JR=$(( JB * 100 / JE ))
    { [ "$JR" -ge 200 ] && [ "$JR" -le 320 ]; } \
        && ok "#9 --json --metrics: $JB B / est_tokens=$JE = $(( JR / 100 )).$(( JR % 100 )) B/tok — inside the markup band" \
        || no "#9 --json --metrics: $JB B / est_tokens=$JE = $(( JR / 100 )).$(( JR % 100 )) B/tok — OUTSIDE the markup band (JSON sibling uncharged)"
    # the two dialects encode the same map with different punctuation, so they are allowed to differ by
    # the encoding overhead — but not by a factor. Within 25% of each other.
    #
    # CA4 (trap #28): compared RAW, this arm asserts a COINCIDENCE — that the two documents are similarly
    # sized — and that stops holding the moment XML gets more honest, because XML carries flag-conditional
    # LEGEND COMMENTS that JSON structurally cannot (JSON has no comment syntax). kChurnRankLegend and
    # kMaxTokensFitLegend already create that asymmetry; the --metrics row legend made it big enough to see.
    # The property actually wanted is "neither dialect is UNCHARGED", so the comparison is now like-for-like:
    # discount the XML-only comment bytes at the document's OWN measured rate, and compare the CONTENT charge
    # against JSON's (all of whose bytes are content). Strictly stronger than the raw form on the thing that
    # matters — an uncharged dialect still fails, and a legend can no longer make a correct binary red.
    XCOMMENT="$( python3 - "$TMP/metrics.out" <<'PYX'
import re,sys
d=open(sys.argv[1],'rb').read()
print(sum(len(m) for m in re.findall(rb'<!--.*?-->',d,re.S)))
PYX
)"
    XB="$( bytes_of "$TMP/metrics.out" )"
    # tokens attributable to NON-comment bytes, at this document's own bytes/token rate
    XE_CONTENT=$(( XE - ( XCOMMENT * XE / XB ) ))
    DIFF=$(( JE - XE_CONTENT )); [ "$DIFF" -lt 0 ] && DIFF=$(( -DIFF ))
    BAR=$(( XE_CONTENT * 25 / 100 )); [ "$(( JE * 25 / 100 ))" -gt "$BAR" ] && BAR=$(( JE * 25 / 100 ))
    { [ "$DIFF" -le "$BAR" ]; } \
        && ok "#9 XML content est_tokens=$XE_CONTENT (of $XE, minus $XCOMMENT B of XML-only legend) and JSON est_tokens=$JE agree within 25%" \
        || no "#9 XML content est_tokens=$XE_CONTENT (of $XE, minus $XCOMMENT B of XML-only legend) and JSON est_tokens=$JE disagree by more than 25% — one dialect is uncharged"
else
    no "#9 --json --metrics reported no est_tokens"
fi

# ── #10: (optional) tiktoken accuracy report over every shape — informational, never gates ─────────────
if python3 -c 'import tiktoken' >/dev/null 2>&1; then
    for entry in "${SHAPES[@]}"; do
        label="${entry%%:*}"
        python3 - "$TMP/$label.out" "$label" <<'PY'
import sys, re, tiktoken
p, label = sys.argv[1], sys.argv[2]
out = open(p, encoding='utf-8', errors='replace').read()
m = re.search(r'est_tokens=(\d+)', out)
if not m: sys.exit(0)
est = int(m.group(1)); real = len(tiktoken.get_encoding("o200k_base").encode(out))
print(f"  INFO  {label}: est_tokens={est} vs real o200k={real}  (err {abs(est-real)/real*100:.1f}%)")
PY
    done
else
    printf '  SKIP  #10 tiktoken accuracy report (tiktoken not installed)\n'
fi

# ── #11 (§F1, CA4 wave-1 verifier): THE NON-MAP EMITTERS. §H7 gave runDefaultMap the property "a section
#    cannot be APPENDED without being charged" and stopped there. Four more emitters appended sections AFTER
#    their own size was finalized. ONE ARM PER MEMBER of the enumeration in the §F1 commit message, so a
#    member that regresses names itself:
#      A7  --for --detail=N bodies    (was 68 035 B against a 4 248 B ceiling at --token-budget=2000, 16x)
#      A8  --for --with-graph block   (was +391 B uncharged)
#      A9  --for header weak="1"      (was +9 B spliced in after the number describing the document)
#      A10 --for header est_tokens="" (the attribute is part of the document it measures)
#      A11 --pack-task --with-graph   (was 12.6% past its allowance with NO over_ceiling)
#      A12 --around <compose>/<routes>(was 804 B at est_tokens=262 = 3.07 B/tok, outside the markup band)
#    Each is a BAND or an IDENTITY, never a pinned token count (house rule: estimates get a tolerance). ─────
FOR_TASK="serialize the map"

# The --for lens spells est_tokens="N" QUOTED in its header comment, where the map spells it bare in its
# stats comment — and est_of() matches the bare form, so on --for it silently read nothing. Worse, a --detail
# bundle EMBEDS serialize.h's own comments as body text, which contain the literal `est_tokens=507` from
# §H7's bug repro: a document-wide grep returns 507 and every rate arm scores 146 B/tok against a number
# that came out of a quoted source file. So this extractor is HEADER-SCOPED (everything before the first
# payload element) and takes the quoted spelling. Trap worth keeping: on a verb that emits source text,
# grepping the whole document for your own marker reads your own source back at you.
# The payload-element list is a denylist and therefore incomplete by construction — a bundle that emits some
# OTHER element first (or none at all) falls back to `len(d)`, i.e. straight back into the trap. `-->` closes
# the header comment the attribute is spliced into (main.cpp inserts it at the header's own rfind(" -->")).
# W3-S item 5 (2026-08-19): --for's header can now legitimately hold TWO trailing comments — the main lens
# comment, then a second, standalone "<!-- root= is the crawl root ... -->" clause (forRootRelPathsLegendShort,
# main.cpp) appended after it closes, the same "second small comment after the first one closes" shape
# kRootRelPathsLegend already uses at eighteen OTHER call sites (e.g. --cochange's kCochangeRepoLegend +
# rootRelPathsLegend()). est_tokens is spliced into whichever comment is LAST (main.cpp's own
# `headerStr.rfind(" -->")`, exactly as this comment already said), so this extractor must find the LAST
# "-->" that precedes the payload boundary, not the FIRST — a plain `d.find(b'-->')` stopped scanning right
# after the FIRST comment closed and missed est_tokens sitting inside the second one entirely.
forest_of(){ python3 - "$1" <<'PYX'
import sys, re
d = open( sys.argv[1], 'rb' ).read()
payload = min( ( i for i in ( d.find( b'<sigs' ), d.find( b'<lego' ), d.find( b'<bodies' ) ) if i >= 0 ), default=len( d ) )
close = d.rfind( b'-->', 0, payload )
cut = close + 3 if close >= 0 else payload
m = re.search( rb'est_tokens="(\d+)"', d[ :cut ] )
print( m.group( 1 ).decode() if m else '' )
PYX
}

# A7/A8 — the two appended --for sections must be INSIDE the delivered document's rate band. The --detail
# shape is a BODY shape (bodies dominate the bytes and are charged at kBytesPerTokenBody), so it takes the
# 4.20 body ceiling; the graph block is markup. An uncharged section pushes the rate straight out of band.
for entry in "for:320:" "for_graph:320:--with-graph" "for_detail:420:--detail=20" "for_both:420:--detail=20 --with-graph"; do
    label="${entry%%:*}"; rest="${entry#*:}"; hi="${rest%%:*}"; args="${rest#*:}"
    # shellcheck disable=SC2086
    "$BIN" src --for="$FOR_TASK" $args --no-cache >"$TMP/f_$label.out" 2>/dev/null
    B="$( bytes_of "$TMP/f_$label.out" )"
    E="$( forest_of "$TMP/f_$label.out" )"
    if [ -z "$E" ] || [ "$E" -le 0 ] 2>/dev/null; then
        no "#11 A7/A8 --for $args: no positive est_tokens in the header (got '$E')"
        continue
    fi
    R=$(( B * 100 / E ))
    { [ "$R" -ge 200 ] && [ "$R" -le "$hi" ]; } \
        && ok "#11 A7/A8 --for $args: $B B / est_tokens=$E = $(( R / 100 )).$(( R % 100 )) B/tok — inside the 2.00-$(( hi / 100 )).$(( hi % 100 )) band" \
        || no "#11 A7/A8 --for $args: $B B / est_tokens=$E = $(( R / 100 )).$(( R % 100 )) B/tok — OUTSIDE the band (an appended --for section is uncharged)"
done

# A7 monotone: adding bodies/graph to the SAME bundle can never leave the estimate unchanged — that is the
# exact signature of the defect (est_tokens="1674" identical with and without a 64 KB body block).
E_FOR="$( forest_of "$TMP/f_for.out" )"
for label in for_graph for_detail for_both; do
    E="$( forest_of "$TMP/f_$label.out" )"
    [ -n "$E" ] && [ "$E" -gt "$E_FOR" ] 2>/dev/null \
        && ok "#11 A7/A8 $label: est_tokens=$E STRICTLY exceeds the bare bundle's $E_FOR (the section is charged)" \
        || no "#11 A7/A8 $label: est_tokens=$E did not move above the bare bundle's $E_FOR — that section is uncharged"
done

# A7 — and --token-budget must SHAPE the bodies, not just the signatures. D10: --for trims to fit, exit 0.
# The pre-fix binary streamed 68 035 B here against a 4 248 B ceiling; the bar is the stated ceiling plus the
# documented single-entry overshoot tolerance (serialize.h kCeilingFirstEntryTolerance = 1.15).
TBF=2000
ALLOW="$( awk "BEGIN{printf \"%d\", $TBF*2.36*1.15}" )"
"$BIN" src --for="$FOR_TASK" --token-budget=$TBF --detail=20 --with-graph --no-cache >"$TMP/f_tb.out" 2>"$TMP/f_tb.err"
rc_ftb=$?
FTB="$( bytes_of "$TMP/f_tb.out" )"
{ [ "$rc_ftb" -eq 0 ] && [ "$FTB" -le "$ALLOW" ]; } 2>/dev/null \
    && ok "#11 A7 --for --token-budget=$TBF --detail=20 --with-graph: $FTB B within the $ALLOW B allowance (exit 0, SHAPED)" \
    || no "#11 A7 --for --token-budget=$TBF --detail=20 --with-graph: $FTB B vs the $ALLOW B allowance, exit $rc_ftb — the budget does not bound the appended sections"
# and without an explicit --token-budget the bodies keep their own budget: the bundle must NOT have shrunk
{ [ "$( bytes_of "$TMP/f_for_detail.out" )" -gt "$ALLOW" ]; } 2>/dev/null \
    && ok "#11 A7 no --token-budget: --detail keeps its --pack-budget-bytes budget (unbudgeted bundle unshrunk)" \
    || no "#11 A7 no --token-budget: --detail was trimmed anyway — the budget bound leaked into the default path"

# A9/A10 — the header's own spliced attributes are inside the number. IDENTITY, not a band: for a bundle with
# no --detail bodies, est_tokens is markup-only, so it must equal round(delivered bytes / 2.50) EXACTLY
# (kBytesPerTokenDefault). Pre-fix the est_tokens attribute (~19 B) and weak="1" (9 B) sat outside the sum,
# which is precisely why the delivered rate measured 2.5063 where the emitter's own rate is 2.50.
selfconsistent(){ python3 - "$1" <<'PY'
import sys, re
d = open( sys.argv[1], 'rb' ).read()
m = re.search( rb'est_tokens="(\d+)"', d )
if not m: sys.exit( 2 )
est      = int( m.group( 1 ) )
expected = int( len( d ) / 2.50 + 0.5 )
print( f"{len(d)} {est} {expected}" )
sys.exit( 0 if est == expected else 1 )
PY
}
# T3 (contract update, same wave): the bare --for is terminal by default and carries auto BODIES at the
# 3.80 body rate, so the markup-only 2.50 identity now lives on the --signatures-only shape…
"$BIN" src --for="$FOR_TASK" --signatures-only --no-cache >"$TMP/f_sigonly.out" 2>/dev/null
if out="$( selfconsistent "$TMP/f_sigonly.out" )"; then
    ok "#11 A9/A10 --for --signatures-only: est_tokens is self-consistent — bytes/est/expected = $out (its own attributes are charged)"
else
    ok_out="$( selfconsistent "$TMP/f_sigonly.out" 2>/dev/null || true )"
    no "#11 A9/A10 --for --signatures-only: est_tokens != round(bytes/2.50) — bytes/est/expected = ${ok_out:-unreadable} (a header splice is outside the sum)"
fi
# …and the DEFAULT bundle must satisfy the MIXED-rate identity exactly: markup at 2.50 plus the auto
# <bodies> span at kBytesPerTokenBody=3.80, each rounded the way the emitter rounds them (a wrong-rate or
# uncharged auto section cannot pass this identity).
mixedconsistent(){ python3 - "$1" <<'PY'
import sys, re
d = open( sys.argv[1], 'rb' ).read()
m = re.search( rb'est_tokens="(\d+)"', d )
if not m: sys.exit( 2 )
est = int( m.group( 1 ) )
a = d.find( b'<bodies ' ); b = d.find( b'</bodies>' )
if a < 0 or b < 0: sys.exit( 3 )                       # arm requires the auto section to be present
span     = ( b + 9 ) - a
expected = int( ( len( d ) - span ) / 2.50 + 0.5 ) + int( span / 3.80 + 0.5 )
print( f"{len(d)} {span} {est} {expected}" )
sys.exit( 0 if est == expected else 1 )
PY
}
# COMPACT conceptual serving (docs/EVALS.md, the T3 route-narrowing round) made "$FOR_TASK" — a
# multi-word conceptual query — serve <hops> instead of <bodies> by default, so the AUTO-BODY shape this
# arm is about now lives behind --auto-bodies. Re-anchored there rather than deleted: the mixed-rate
# identity is the only arm that can catch a mis-rated body span.
"$BIN" src --for="$FOR_TASK" --auto-bodies --no-cache >"$TMP/f_forauto.out" 2>/dev/null
if out="$( mixedconsistent "$TMP/f_forauto.out" )"; then
    ok "#11 A9/A10 --for --auto-bodies: est_tokens matches markup@2.50 + bodies@3.80 — bytes/span/est/expected = $out"
else
    mix_out="$( mixedconsistent "$TMP/f_forauto.out" 2>/dev/null || true )"
    no "#11 A9/A10 --for --auto-bodies: mixed-rate identity broken — bytes/span/est/expected = ${mix_out:-unreadable} (the auto section is mischarged)"
fi

# …and the COMPACT default satisfies the FLAT identity, which is the whole point of charging <hops> at the
# markup rate: that bundle carries no source text at all, so every byte in it — the section included —
# tokenizes like markup. A <hops> span priced at the body rate would under-report and this arm would fail.
if out="$( selfconsistent "$TMP/f_for.out" )"; then
    ok "#11 A9/A10 --for (compact route): est_tokens = round(bytes/2.50) — bytes/est/expected = $out (the <hops> section is charged at the markup rate)"
else
    flat_out="$( selfconsistent "$TMP/f_for.out" 2>/dev/null || true )"
    no "#11 A9/A10 --for (compact route): flat-rate identity broken — bytes/est/expected = ${flat_out:-unreadable} (the compact section is mischarged)"
fi
grep -aq '<hops ' "$TMP/f_for.out" \
    && ok "#11 A9/A10 presence: the compact arm really did serve a <hops> section (the arm is not inert)" \
    || no "#11 A9/A10 presence: no <hops> in the default --for bundle — re-anchor this arm, it proves nothing"
# the weak="1" path: a nonsense query trips the weak-score threshold, so the 9-byte attribute is present and
# the same identity must still hold with it in the document. R9 fix (W3-S, 2026-08-19): a query this weak
# also has no positive-score body candidates, so buildForAutoBodies now ALWAYS emits the honest
# "<bodies shown="0" total="0" capped="0"></bodies>" shell here (it used to be entirely absent) — a real,
# if tiny, body-rate (3.80) span inside an otherwise markup-rate (2.50) document, so this arm uses
# mixedconsistent (already proven above for the non-weak auto-bodies case) instead of the flat-rate
# selfconsistent, which cannot see the mixed rate and would false-positive on a span the emitter prices
# correctly.
# The weak query is a single nonsense word, which routes subtoken+body and therefore goes COMPACT: the
# R9 shell it emits is <hops shown="0" total="0" capped="0">, markup-rate like the rest of that document,
# so the FLAT identity is the right one here now (mixedconsistent would exit on the absent <bodies>).
"$BIN" src --for="zzqqxx" --no-cache >"$TMP/f_weak.out" 2>/dev/null
if grep -aq 'weak="1"' "$TMP/f_weak.out"; then
    if out="$( selfconsistent "$TMP/f_weak.out" )"; then
        ok "#11 A9 --for with weak=\"1\": est_tokens self-consistent — bytes/est/expected = $out (the 9 B attr + the R9 <hops> shell are both charged)"
    else
        no "#11 A9 --for with weak=\"1\": est_tokens != flat expected — the weak attr or the R9 <hops> shell is spliced in outside the sum"
    fi
else
    no "#11 A9 could not produce a weak=\"1\" bundle (threshold or query shape changed — re-anchor this arm)"
fi

# M11 (2026-09-04): the pack-task legend now DEFINES over_ceiling= in prose, so the three greps below read the
# LABEL — the root attribute over_ceiling="1" or the ladder's colon note — never the bare word.
# A11 — --pack-task --with-graph. The graph block is a FIXED cost with no trim knob, so at a budget where the
# bare bundle is conformant and the block pushes it past the allowance, the bundle must SAY over_ceiling.
# MEASURED pre-fix: bare 2 046 B conformant, +graph 2 437 B against a 2 171 B allowance, 12.6% over, silent.
# CA4: PT_TB used to be a hard-coded 800, and the arm's own CONTROL — the bare bundle must be conformant and
# unlabelled, or "the graph block pushed it over" proves nothing — depends on the header FLOOR staying under
# that budget. Any legend the header gains moves that floor, so a fixed budget guarantees this arm rots into
# a false failure sooner or later (it did, the first time a row-key dictionary grew). The arm now SEARCHES for
# the smallest budget at which the bare bundle is conformant and unlabelled, and runs the comparison there.
# The property under test is unchanged; only the operating point tracks the floor instead of being asserted
# to sit above it. If no budget in the ladder qualifies, that is a real failure and it says so.
PT_TB=""
for _tb in 800 1000 1200 1500 2000 3000; do
    "$BIN" src --pack-task="$FOR_TASK" --token-budget=$_tb --no-cache >"$TMP/pt_probe.out" 2>/dev/null
    _b="$( bytes_of "$TMP/pt_probe.out" )"
    _a="$( awk "BEGIN{printf \"%d\", $_tb*2.36*1.15}" )"
    if [ "$_b" -le "$_a" ] 2>/dev/null && ! grep -aqE 'over_ceiling(="1"|:)' "$TMP/pt_probe.out"; then PT_TB=$_tb; break; fi
done
if [ -z "$PT_TB" ]; then
    no "#11 A11: no budget in 800..3000 leaves the bare --pack-task conformant AND unlabelled — the header floor has outgrown the ladder"
    PT_TB=3000
fi
PT_ALLOW="$( awk "BEGIN{printf \"%d\", $PT_TB*2.36*1.15}" )"
"$BIN" src --pack-task="$FOR_TASK" --token-budget=$PT_TB --no-cache >"$TMP/pt_bare.out" 2>/dev/null
"$BIN" src --pack-task="$FOR_TASK" --token-budget=$PT_TB --with-graph --no-cache >"$TMP/pt_graph.out" 2>/dev/null
PTB="$( bytes_of "$TMP/pt_bare.out" )";  PTG="$( bytes_of "$TMP/pt_graph.out" )"
if [ "$PTG" -le "$PT_ALLOW" ] 2>/dev/null; then
    ok "#11 A11 --pack-task --token-budget=$PT_TB --with-graph: $PTG B within the $PT_ALLOW B allowance"
elif grep -aqE 'over_ceiling(="1"|:)' "$TMP/pt_graph.out"; then
    ok "#11 A11 --pack-task --token-budget=$PT_TB --with-graph: $PTG B over the $PT_ALLOW B allowance and SAYS SO (over_ceiling)"
else
    no "#11 A11 --pack-task --token-budget=$PT_TB --with-graph: $PTG B EXCEEDS the $PT_ALLOW B allowance unlabelled (bare form is $PTB B) — the spliced block is uncharged"
fi
# control: the bare form at the same budget must NOT be labelled, or the label means nothing
{ [ "$PTB" -le "$PT_ALLOW" ] && ! grep -aqE 'over_ceiling(="1"|:)' "$TMP/pt_bare.out"; } 2>/dev/null \
    && ok "#11 A11 control: the bare --pack-task at the same budget is conformant AND unlabelled" \
    || no "#11 A11 control: the bare --pack-task at --token-budget=$PT_TB is $PTB B / labelled — the A11 arm proves nothing"

# A12 — --around's appended <compose>/<routes>. Pick a focus whose ego-graph is SMALL, so the sibling blocks
# are a large fraction of the document and an uncharged block moves the rate hard (base: 3.07 B/tok).
"$BIN" src --around=Config --no-cache >"$TMP/around.out" 2>/dev/null
AB="$( bytes_of "$TMP/around.out" )"
AE="$( est_of "$TMP/around.out" )"
if grep -aq '<compose\|<routes' "$TMP/around.out" && [ -n "$AE" ] && [ "$AE" -gt 0 ] 2>/dev/null; then
    AR=$(( AB * 100 / AE ))
    # TIGHTER than #1's shared 3.20 markup ceiling, and deliberately: --around emits XML markup ONLY (no body
    # text, so no kBytesPerTokenBody bytes and no JSON 3.10 content to accommodate), and every map-family
    # shape measured on src/ sits at 2.46-2.50 because a small map's bytesPerToken() falls back to
    # kBytesPerTokenDefault=2.50. 2.70 leaves the envelope's share of a tiny ego-graph room and still reds the
    # defect: the pre-fix binary measures 3.07 here and PASSES a 3.20 ceiling, which is the whole reason a
    # per-member arm exists instead of one shared band. A band, never a pinned count (house rule).
    { [ "$AR" -ge 200 ] && [ "$AR" -le 270 ]; } \
        && ok "#11 A12 --around=Config: $AB B / est_tokens=$AE = $(( AR / 100 )).$(( AR % 100 )) B/tok — inside the 2.00-2.70 markup-only band (the sibling block is charged)" \
        || no "#11 A12 --around=Config: $AB B / est_tokens=$AE = $(( AR / 100 )).$(( AR % 100 )) B/tok — OUTSIDE the 2.00-2.70 markup-only band (the appended <compose>/<routes> is uncharged)"
else
    no "#11 A12 --around=Config emitted no <compose>/<routes> or no est_tokens — re-anchor this arm on a focus that has one"
fi

# ── #12 (bucket B of the enumeration): the two DELIBERATE non-conventions, pinned so a future change to them
#    is a decision rather than a drift. Neither is a defect; both are things a reader could mistake for one. ─
"$BIN" src --top-k=10 --stable --pack-signatures --no-cache >"$TMP/stable.out" 2>/dev/null
grep -aqE '<r est_tokens="' "$TMP/stable.out" \
    && no "#12 B3 --stable emitted est_tokens on the root — it is deliberately omitted (volatile prefix)" \
    || ok "#12 B3 --stable omits est_tokens by design (the root element is the cacheable prefix)"
# B4 --top-k=0: no header exists to carry est_tokens, but the gate must still SEE the payload
"$BIN" src --top-k=0 --pack-top-n=3 --token-budget=600 --no-cache >"$TMP/k0.out" 2>"$TMP/k0.err"
rc_k0=$?
{ [ "$rc_k0" -eq 3 ] && [ "$( bytes_of "$TMP/k0.out" )" -lt 2048 ]; } 2>/dev/null \
    && ok "#12 B4 --top-k=0 --pack-top-n=3 --token-budget=600: exit 3, payload withheld (mapEstTokens = payloadTokens)" \
    || no "#12 B4 --top-k=0 --pack-top-n=3 --token-budget=600: exit $rc_k0, $( bytes_of "$TMP/k0.out" ) B — the gate does not see a payload-only document"

# ── #13 (Owner ruling 3): the CALL GRAPH must not move. est_tokens is a reporting concern; if any of these
#    five counts changed, this lane touched something it had no business touching. Pinned as a SELF-COMPARISON
#    against $RIPWIRE_BASE when one is supplied (that is the only honest form — the numbers are corpus-
#    dependent), and otherwise as an internal-consistency check that they are present and non-degenerate. ────
GRAPH_KEYS='files=[0-9]+ symbols=[0-9]+ edges=[0-9]+'
counts_of(){ grep -aoE 'files=[0-9]+|symbols=[0-9]+|edges=[0-9]+|ambiguous=[0-9]+|unresolved=[0-9]+' "$1" | tr '\n' ' '; }
# MEASURED ON test/fixture, NOT src/: src/ is this binary's own source, so adding a function to it moves
# symbols=/edges= legitimately and the arm would red on every future edit. test/fixture is a frozen corpus,
# which is what makes "the graph did not move" a statement about the CHANGE rather than about the diff size.
"$BIN" test/fixture --no-cache >"$TMP/g_new.out" 2>/dev/null
NEWC="$( counts_of "$TMP/g_new.out" )"
if [ -n "${RIPWIRE_BASE:-}" ] && [ -x "${RIPWIRE_BASE:-}" ]; then
    "$RIPWIRE_BASE" test/fixture --no-cache >"$TMP/g_base.out" 2>/dev/null
    BASEC="$( counts_of "$TMP/g_base.out" )"
    [ "$NEWC" = "$BASEC" ] \
        && ok "#13 ruling 3: files=/symbols=/edges=/ambiguous=/unresolved= unmoved vs RIPWIRE_BASE — [$NEWC]" \
        || no "#13 ruling 3 VIOLATED: [$NEWC] vs base [$BASEC] — this change moved the call graph"
else
    echo "$NEWC" | grep -qE "$GRAPH_KEYS" \
        && ok "#13 ruling 3: the five graph counts are present [$NEWC] (set RIPWIRE_BASE to diff them against the pre-change binary)" \
        || no "#13 ruling 3: the graph counts are missing or malformed [$NEWC]"
fi

# ── #14 (the CA4 coverage debt, trap #3): THE open_memstream DEGRADE PATH. The wave-1 verifier declared these
#    paths never exercised: `open_memstream` fails on ALLOCATION, so no `ulimit -n` harness reaches them. The
#    fault switch RIPWIRE_FAULT_CHARGE_BUFFER=1 exists ONLY on the non-NDEBUG flavour — the same flavour
#    DEGRADED_PATH_ALERT exists on — so this arm establishes that flavour with its OWN observability probe
#    rather than assuming it, and it must never pass for lack of an alert it could not have seen.
#
#    (a) OBSERVABILITY PROBE. If the switch has no effect, exactly one of two things is true, and the
#        preamble's two independent readings tell them apart: either this is an NDEBUG build, where the
#        arm is unobservable BY DESIGN and the plain-flavour CI leg is what proves it (→ SKIP, reason
#        named), or the seam regressed on a flavour that CAN see alerts (→ FAILURE). ─────────────────────
RIPWIRE_FAULT_CHARGE_BUFFER=1 "$BIN" src --top-k=10 --pack-signatures --no-cache >"$TMP/dg.out" 2>"$TMP/dg.err"
rc_dg=$?
if grep -aq 'chargeSection: open_memstream failed' "$TMP/dg.err"; then
    ok "#14a observability probe: this flavour CAN observe DEGRADED_PATH_ALERT (the fault switch is live)"

    #    (b) the alert names the CONSEQUENCE, on both the section and the document
    grep -aq 'streams uncharged' "$TMP/dg.err" \
        && ok "#14b the chargeSection alert says the section streams UNCHARGED" \
        || no "#14b the chargeSection alert fired but does not say the section is uncharged"
    grep -aq 'serialize: open_memstream failed .* MODELLED bytes, not the emitted ones' "$TMP/dg.err" \
        && ok "#14b the serialize alert says est_tokens reports MODELLED, not emitted, bytes" \
        || no "#14b serialize degraded without saying est_tokens switched to the MODELLED number"

    #    (c) THE BYTES ARE STILL COMPLETE AND CORRECT. The whole point of the degrade: the caller loses the
    #        charge, never the content. Byte-compare the payload against the undegraded run.
    "$BIN" src --top-k=10 --pack-signatures --no-cache >"$TMP/dg_ctl.out" 2>/dev/null
    if python3 - "$TMP/dg_ctl.out" "$TMP/dg.out" <<'PY'
import sys
ctl = open( sys.argv[1], 'rb' ).read()
deg = open( sys.argv[2], 'rb' ).read()
i, j = ctl.find( b'<sigs' ), deg.find( b'<sigs' )
sys.exit( 0 if i >= 0 and j >= 0 and ctl[i:] == deg[j:] else 1 )
PY
    then ok "#14c degraded run: the <sigs> payload is BYTE-IDENTICAL to the undegraded run (charge lost, content intact)"
    else no "#14c degraded run: the <sigs> payload DIFFERS from the undegraded run — the degrade path lost or corrupted content"
    fi
    [ "$rc_dg" -eq 0 ] \
        && ok "#14c degraded run still exits 0 (a measurement failure is not a run failure)" \
        || no "#14c degraded run exited $rc_dg — an open_memstream failure must degrade, not fail the run"
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$TMP/dg.out" 2>/dev/null \
            && ok "#14c degraded run is still well-formed XML (G4 holds on the degrade path)" \
            || no "#14c degraded run emitted malformed XML"
    fi

    #    (d) est_tokens FALLS BACK TO THE MODELLED NUMBER and is therefore visibly different — never silently
    #        the same number, and never absent-without-saying-so. The modelled number is the pre-§H7 estimate,
    #        so it is LOWER than the charged one for any shape carrying a payload.
    DGE="$( est_of "$TMP/dg.out" )";  CTLE="$( est_of "$TMP/dg_ctl.out" )"
    { [ -n "$DGE" ] && [ -n "$CTLE" ] && [ "$DGE" -lt "$CTLE" ]; } 2>/dev/null \
        && ok "#14d degraded est_tokens=$DGE is the MODELLED number, below the charged $CTLE (documented fallback, not a fabrication)" \
        || no "#14d degraded est_tokens=$DGE vs charged $CTLE — the fallback is not observable in the document"

    #    and the --for lens's own contract is the OTHER honest answer: it omits est_tokens rather than
    #    fabricate one it cannot compute. Both are acceptable; silently keeping a stale number is not.
    #
    #    HEADER-SCOPED, via this file's own forest_of(). The first spelling of this arm grepped the WHOLE
    #    document for `est_tokens=` — the exact trap forest_of() was written 240 lines above to close, left
    #    un-swept when it was introduced (trap #6: a fix that produces a helper sweeps the helper's callers,
    #    not the surface). A --detail bundle embeds src/'s own comments as body text, and this round's §H7
    #    work put the literals `est_tokens=1216` and `est_tokens=619` into those comments, so the arm went red
    #    on 2026-07-31 reading ripwire's source back at itself while the header was correctly bare. Diagnosis
    #    (a): no code defect — the header attribute has never been emitted on this path — and CORPUS DRIFT,
    #    since what changed was src/, not serialize.h.
    #
    #    The negative assertion is paired with a POSITIVE CONTROL on the identical shape, because "no
    #    est_tokens in the header region" is also what an extractor pointed at the wrong bytes reports: the
    #    UNDEGRADED run of the same command must find one there, or the anchor is dead and the arm is vacuous.
    "$BIN" src --for="$FOR_TASK" --detail=5 --no-cache >"$TMP/dgf_ctl.out" 2>/dev/null
    FCTL="$( forest_of "$TMP/dgf_ctl.out" )"
    { [ -n "$FCTL" ] && [ "$FCTL" -gt 0 ]; } 2>/dev/null \
        && ok "#14d anchor control: the UNDEGRADED --for --detail=5 header does carry est_tokens=\"$FCTL\" (the probe is live)" \
        || no "#14d anchor control: the undegraded --for --detail=5 header has no est_tokens (got '$FCTL') — the omission probe below is vacuous"
    RIPWIRE_FAULT_CHARGE_BUFFER=1 "$BIN" src --for="$FOR_TASK" --detail=5 --no-cache >"$TMP/dgf.out" 2>"$TMP/dgf.err"
    FDG="$( forest_of "$TMP/dgf.out" )"
    [ -z "$FDG" ] \
        && ok "#14d degraded --for OMITS est_tokens entirely (never a fabricated number)" \
        || no "#14d degraded --for still printed an est_tokens=\"$FDG\" it could not measure"
    grep -aq 'est_tokens omitted from the header' "$TMP/dgf.err" \
        && ok "#14d degraded --for says on stderr that est_tokens was omitted" \
        || no "#14d degraded --for omitted est_tokens without saying so"
    #    (e) CA4 w1fix2-verifier G4: the switch is a SWITCH, not a prefix test. It read `value[0] == '1'`, so
    #        `=10`, `=1x` and `=1000000` all injected the fault — a caller who wrote `=1000000` meaning "a large
    #        number of something" got a degraded document at exit 0. Only the exact string "1" may inject; every
    #        other value, including the ones that merely START with '1', must be byte-identical to unset. The
    #        control (`$TMP/dg_ctl.out`, no switch in the environment) is the reference.
    g4fail=0
    for badval in 10 1x 1000000 11 '1 ' 0 true ''; do
        RIPWIRE_FAULT_CHARGE_BUFFER="$badval" "$BIN" src --top-k=10 --pack-signatures --no-cache >"$TMP/dg_g4.out" 2>"$TMP/dg_g4.err"
        if grep -aq 'chargeSection: open_memstream failed' "$TMP/dg_g4.err"; then
            no "#14e RIPWIRE_FAULT_CHARGE_BUFFER='$badval' INJECTED the fault — only the exact value \"1\" may (prefix test, verifier G4)"
            g4fail=1
        elif ! cmp -s "$TMP/dg_g4.out" "$TMP/dg_ctl.out"; then
            no "#14e RIPWIRE_FAULT_CHARGE_BUFFER='$badval' changed the document vs the unset control"
            g4fail=1
        fi
    done
    [ "$g4fail" = 0 ] && ok "#14e the fault switch is exact-match: 8 non-\"1\" values (incl. 10 / 1x / 1000000) are byte-identical to unset"
elif [ "$alerts_observable" -eq 0 ] && [ "$ndebug_flavour" -eq 1 ]; then
    skip "#14 open_memstream degrade arms — DEGRADED_PATH_ALERT is compiled out of this binary (--version says build type \"$BUILD_FLAVOUR\", which defines NDEBUG; the unrelated --since=notadate degrade path is silent here too, so alerts are unobservable globally rather than this seam having broken). The RIPWIRE_FAULT_CHARGE_BUFFER switch does not exist on this flavour either. These arms are proven by the PLAIN-flavour run of the same suite, which CI executes as a second leg for exactly this reason."
else
    no "#14a observability probe FAILED: RIPWIRE_FAULT_CHARGE_BUFFER=1 produced no DEGRADED_PATH_ALERT on a build that CAN observe alerts (--version build type \"$BUILD_FLAVOUR\", unrelated-degrade-path observable=$alerts_observable) — the openChargeBuffer seam regressed. This is a FAILURE, not a skip."
fi

# ── §C1 + §C2 (capture-audit-4, wave 3): --for --json's ENVELOPE is charged, and so is over_ceiling ─────
#
# emitForLensJson reserved a flat 40 bytes for `,"capped":false,"est_tokens":NNNNN,"sigs":}` — 38 fixed plus
# the digits, so 40 held only up to a TWO-digit est_tokens and under-reserved from five digits up, which is
# every real bundle. And `,"over_ceiling":true` (20 B) was WRITTEN to stdout while being left OUT of
# bundleBytes, so est_tokens did not charge the key describing the fact that est_tokens had blown its
# ceiling — §H7's self-reference shape at the one place it is most misleading.
#
# Asserted as a PROPERTY, like #1 above: est_tokens x the default rate must reproduce the ACTUAL emitted byte
# count to within one token's rounding. That catches an under-charge of 8 bytes as readily as one of 8 KB,
# and it cannot be satisfied by a pinned number that drifts with the corpus.
JSON_TASK="add retry to the http client"
jsonEnvelopeCase()
{
    local label="$1"; shift
    "$BIN" src --for="$JSON_TASK" --json --no-cache "$@" > "$TMP/fj.out" 2>/dev/null || true
    python3 - "$TMP/fj.out" "$label" <<'PYEOF'
import json, sys
raw = open( sys.argv[1], "rb" ).read()
label = sys.argv[2]
try:
    doc = json.loads( raw )
except Exception as exc:
    print( "  FAIL  §C1 %s: --for --json is not parseable JSON (%s)" % ( label, exc ) ); sys.exit( 1 )
est   = doc.get( "est_tokens" )
if est is None:
    print( "  FAIL  §C1 %s: no est_tokens key" % label ); sys.exit( 1 )
# kBytesPerTokenDefault; the charge rounds to the nearest token, so one token of slack is the whole tolerance
rate  = 2.5
delta = abs( est * rate - len( raw ) )
if delta <= rate:
    print( "  PASS  §C1 %s: est_tokens=%d charges the WHOLE emitted document (%d B, |delta|=%.1f B <= one token)"
           % ( label, est, len( raw ), delta ) )
else:
    print( "  FAIL  §C1 %s: est_tokens=%d implies %.0f B but %d B were emitted (off by %.0f B) - a section or "
           "envelope member is not charged" % ( label, est, est * rate, len( raw ), est * rate - len( raw ) ) )
    sys.exit( 1 )
# §C2: when the key IS present it must have been part of what est_tokens charged. The check above already
# proves that (its 20 bytes are in len(raw)); this arm just makes the over_ceiling case explicit rather than
# leaving it to whichever budget the loop happened to pick.
if doc.get( "over_ceiling" ) is True:
    print( "  PASS  §C2 %s: over_ceiling is present AND inside the charged byte count" % label )
PYEOF
    [ $? -eq 0 ] || fail=1
}
jsonEnvelopeCase "no budget"
jsonEnvelopeCase "--token-budget=200"   --token-budget=200
jsonEnvelopeCase "--token-budget=600"   --token-budget=600
jsonEnvelopeCase "--token-budget=3000"  --token-budget=3000
jsonEnvelopeCase "--token-budget=16000" --token-budget=16000

# the over_ceiling key must actually FIRE somewhere in that sweep, or the §C2 arm above is vacuous.
"$BIN" src --for="$JSON_TASK" --json --no-cache --token-budget=200 > "$TMP/fj200.out" 2>/dev/null || true
grep -q '"over_ceiling":true' "$TMP/fj200.out" \
    && ok "§C2 control: over_ceiling DOES fire at a small budget (the charge arm above is not vacuous)" \
    || no "§C2 control: no budget in the sweep produced over_ceiling - the §C2 arms proved nothing"

# ── §C4 (capture-audit-4, wave 3): the --max-tokens ceiling VERDICT measures the EMITTED dialect ────────
#
# The top-K binary search prices the XML rendering (main.cpp's measureMapBytes calls serialize()), and under
# --json the document that reaches stdout is serializeJson()'s. The over_ceiling LABEL was decided from the
# XML measurement too, so a JSON map could exceed the fit_bytes printed in its own header and still call the
# cap honoured. MEASURED on src/: under the ceiling to N~6000, over it from N~6500 (+49 B), +319 B at 10000,
# +1545 B at 20000 — all unlabelled. The verdict now measures the emitted dialect.
#
# The SEARCH still prices XML; that is disclosed by fit_measured_in="xml" and routed, so this gate asserts
# LABELLING, not fitting: wherever the emitted JSON exceeds fit_bytes, over_ceiling MUST be present. Written
# as an implication over a sweep rather than pinned to an N, because the crossover moves with the corpus.
c4any=0; c4bad=0
for n in 500 1000 3000 6000 6500 10000 20000; do
    "$BIN" src --max-tokens="$n" --json --no-cache > "$TMP/c4.json" 2>/dev/null || true
    verdict="$( python3 - "$TMP/c4.json" <<'PYEOF'
import json, sys
raw = open( sys.argv[1], "rb" ).read()
try:    doc = json.loads( raw )
except Exception: print( "UNPARSEABLE" ); raise SystemExit
fit = doc.get( "fit_bytes" )
if fit is None: print( "NOFIT" ); raise SystemExit
over = len( raw ) > fit
print( "%s %s %d %d" % ( "OVER" if over else "UNDER", doc.get( "over_ceiling" ) is True, len( raw ), fit ) )
PYEOF
)"
    set -- $verdict
    case "${1:-}" in
        OVER)  [ "${2:-}" = True ] && { c4any=$(( c4any + 1 )); ok "§C4 N=$n: JSON ${3} B exceeds fit_bytes ${4} and IS labelled over_ceiling"; } \
                                  || { c4bad=1; no "§C4 N=$n: JSON ${3} B exceeds fit_bytes ${4} with NO over_ceiling — a cap that can be overshot in silence"; } ;;
        UNDER) [ "${2:-}" = True ] && { c4bad=1; no "§C4 N=$n: JSON ${3} B is WITHIN fit_bytes ${4} but claims over_ceiling"; } \
                                  || ok "§C4 N=$n: JSON ${3} B is within fit_bytes ${4}, no label (correct)" ;;
        *)     c4bad=1; no "§C4 N=$n: could not read fit_bytes out of the JSON map ($verdict)" ;;
    esac
done
[ "$c4any" -ge 1 ] && ok "§C4 control: the sweep DOES reach an over-ceiling N ($c4any of them) — the implication is not vacuous" \
                   || no "§C4 control: no N in the sweep exceeded fit_bytes, so the labelling arms proved nothing"
[ "$c4bad" = 0 ] || fail=1

# and the XML dialect must be untouched by all of this: its verdict already measured its own rendering.
for n in 200 1000 6000; do
    "$BIN" src --max-tokens="$n" --no-cache > "$TMP/c4.xml" 2>/dev/null || true
    xb="$( wc -c < "$TMP/c4.xml" | tr -d ' ' )"
    # the XML states its fit inside the header COMMENT (serialize.h writes ` fit_bytes=N`, unquoted prose,
    # not an attribute) — and the legend line also carries the literal `fit_bytes=honoured:`, so take the
    # first NUMERIC occurrence rather than the first occurrence.
    xfit="$( grep -o 'fit_bytes=[0-9][0-9]*' "$TMP/c4.xml" | head -1 | cut -d= -f2 )"
    if [ -z "$xfit" ]; then no "§C4 XML N=$n states no numeric fit_bytes= in its header"
    elif [ "$xb" -gt "$xfit" ] && ! grep -q 'over_ceiling=1' "$TMP/c4.xml"; then
        no "§C4 XML N=$n: $xb B exceeds fit_bytes $xfit with no over_ceiling=1"
    else ok "§C4 XML N=$n: $xb B vs fit_bytes $xfit, label consistent"; fi
done

# ── #15 (capture-audit 2026-09-04, M11 / lens 7 F-EST-1/2/3, lens 1 F10, lens 4): EVERY --token-budget consumer
#    prices its ROOT. The audited binary took a budget on --pack-task (header prose said `budget=12744 bytes`),
#    --from-trace, --handoff (--token-budget=100 delivered 521 payload bytes with no est_tokens=/over_ceiling=)
#    and --expand --top-k=0 (the estimate lived on the <r> header the flag suppresses) and priced nothing an
#    XML parser can read. RULE: the root carries est_tokens= (tokens — the unit budget_tokens=/budget= are in),
#    over_ceiling="1" when the un-trimmable floor exceeds the ceiling, and `withheld=` is a BOOLEAN with the
#    dropped-row COUNT under withheld_rows= (the map already spelled withheld="1" + withheld_est_tokens=;
#    --handoff spelled the count under the boolean's name). Bands, not pins (house rule for estimates); an
#    IDENTITY only where the number is by construction the one --token-budget gates on. ──────────────────
root_est(){ perl -0pe 's#<!--.*?-->##gs' "$1" | grep -oE "<$2( [^>]*)?>" | head -1 | grep -oE ' est_tokens="[0-9]+"' | head -1 | tr -dc '0-9'; }
root_attr(){ perl -0pe 's#<!--.*?-->##gs' "$1" | grep -oE "<$2( [^>]*)?>" | head -1 | grep -oE " $3=\"[^\"]*\"" | head -1 | sed -E 's/.*="([^"]*)"/\1/'; }
band15(){   # $1 label $2 file $3 root-element $4 hi*100
    local label="$1" f="$2" el="$3" hi="$4" E B R
    E="$( root_est "$f" "$el" )"; B="$( bytes_of "$f" )"
    if [ -z "$E" ] || [ "$E" -eq 0 ] 2>/dev/null; then
        no "#15 $label: <$el> root carries no est_tokens= ($( perl -0pe 's#<!--.*?-->##gs' "$f" | grep -oE "<$el( [^>]*)?>" | head -1 | cut -c1-140 ))"; return
    fi
    R=$(( B * 100 / E ))
    { [ "$R" -ge 200 ] && [ "$R" -le "$hi" ]; } \
        && ok "#15 $label: $B B / est_tokens=$E = $(( R / 100 )).$(( R % 100 )) B/tok — inside the 2.00-$(( hi / 100 )).$(( hi % 100 )) band" \
        || no "#15 $label: $B B / est_tokens=$E = $(( R / 100 )).$(( R % 100 )) B/tok — OUTSIDE the band (the root's number does not price the delivered document)"
}
# (a) --pack-task: a comfortable budget prices; a tiny one labels over_ceiling on the ROOT, not only in prose
"$BIN" src --pack-task="$FOR_TASK" --token-budget=1500 --no-cache >"$TMP/p15_pt.xml" 2>/dev/null
band15 "--pack-task --token-budget=1500" "$TMP/p15_pt.xml" ctx 420
[ "$( root_attr "$TMP/p15_pt.xml" ctx budget_tokens )" = "1500" ] \
    && ok "#15 --pack-task: root budget_tokens=\"1500\" — the ceiling in the SAME unit as est_tokens=" \
    || no "#15 --pack-task: root carries no budget_tokens=\"1500\" beside est_tokens= (got '$( root_attr "$TMP/p15_pt.xml" ctx budget_tokens )')"
"$BIN" src --pack-task="$FOR_TASK" --token-budget=50 --no-cache >"$TMP/p15_pt50.xml" 2>/dev/null
[ "$( root_attr "$TMP/p15_pt50.xml" ctx over_ceiling )" = "1" ] \
    && ok "#15 --pack-task --token-budget=50: root over_ceiling=\"1\" (the header floor exceeds the ceiling)" \
    || no "#15 --pack-task --token-budget=50: no over_ceiling=\"1\" on the root while the ledger prose says the floor exceeds the budget"
E50="$( root_est "$TMP/p15_pt50.xml" ctx )"
[ -n "$E50" ] && [ "$E50" -gt 50 ] 2>/dev/null \
    && ok "#15 --pack-task --token-budget=50: est_tokens=$E50 > 50 — the label and the number agree" \
    || no "#15 --pack-task --token-budget=50: est_tokens='$E50' does not exceed the budget it is labelled over"
# (b) --from-trace: the same two shapes on a name-resolved frame
printf 'Traceback (most recent call last):\n  File "src/graph.h", line 1, in rankGraphTeleport\n' >"$TMP/p15_trace.txt"
"$BIN" src --from-trace="$TMP/p15_trace.txt" --token-budget=1500 --no-cache >"$TMP/p15_ft.xml" 2>/dev/null
band15 "--from-trace --token-budget=1500" "$TMP/p15_ft.xml" ctx 420
[ "$( root_attr "$TMP/p15_ft.xml" ctx budget_tokens )" = "1500" ] \
    && ok "#15 --from-trace: root budget_tokens=\"1500\"" \
    || no "#15 --from-trace: root carries no budget_tokens=\"1500\" (got '$( root_attr "$TMP/p15_ft.xml" ctx budget_tokens )')"
"$BIN" src --from-trace="$TMP/p15_trace.txt" --token-budget=50 --no-cache >"$TMP/p15_ft50.xml" 2>/dev/null
[ "$( root_attr "$TMP/p15_ft50.xml" ctx over_ceiling )" = "1" ] \
    && ok "#15 --from-trace --token-budget=50: root over_ceiling=\"1\"" \
    || no "#15 --from-trace --token-budget=50: no over_ceiling=\"1\" on the root (the prose label alone is what a parser discards)"
# (d) --for (verify-wave1 N1): after M11 the flagship budgeted verb was the ONE outlier — est_tokens="N" lived
#     inside its header COMMENT (a comment-stripping parser reads nothing) and the ladder's over_ceiling verdict
#     was a bracket note in the same comment, never an attribute: `--for … --token-budget=300` shipped 1,243
#     tokens at exit 0 with a bare <ctx>. SWEPT across the usable range like arm #5 (the small end is where the
#     fixed floor dominates): the root carries est_tokens=; delivered bytes sit inside the ladder's own
#     allowance (N x kMinBytesPerToken x kCeilingFirstEntryTolerance = N x 2.36 x 1.15, serialize.h) OR the
#     root says over_ceiling="1"; and a labelled root's est_tokens exceeds N (the label and the number agree).
for N in 100 300 400 600 800 1200 1500 3000; do
    "$BIN" src --for="$FOR_TASK" --token-budget=$N --no-cache >"$TMP/p15_for$N.xml" 2>/dev/null
    FB="$( bytes_of "$TMP/p15_for$N.xml" )"
    FE="$( root_est "$TMP/p15_for$N.xml" ctx )"
    FO="$( root_attr "$TMP/p15_for$N.xml" ctx over_ceiling )"
    FLIM="$( awk "BEGIN{printf \"%d\", $N*2.36*1.15}" )"
    if [ -z "$FE" ]; then
        no "#15 --for --token-budget=$N: <ctx> root carries no est_tokens= ($FB B delivered; the price is not where a parser reads it)"
    else
        ok "#15 --for --token-budget=$N: root est_tokens=\"$FE\" ($FB B)"
    fi
    if [ "$FB" -le "$FLIM" ] 2>/dev/null; then
        ok "#15 --for --token-budget=$N: $FB B within the $FLIM B ladder allowance"
    elif [ "$FO" = "1" ]; then
        ok "#15 --for --token-budget=$N: $FB B over the $FLIM B allowance and the ROOT says so (over_ceiling=\"1\")"
        { [ -n "$FE" ] && [ "$FE" -gt "$N" ]; } 2>/dev/null \
            && ok "#15 --for --token-budget=$N: est_tokens=$FE > $N — the label and the number agree" \
            || no "#15 --for --token-budget=$N: root over_ceiling=\"1\" but est_tokens='$FE' does not exceed the budget it is labelled over"
    else
        no "#15 --for --token-budget=$N: $FB B EXCEEDS the $FLIM B allowance with NO over_ceiling=\"1\" on the root (over_ceiling on root='$FO')"
    fi
done
# the two root attributes must be DEFINED by the legend of the document that carries them (§B7 class)
perl -0pe 's#<!--(.*?)-->#\1#gs' "$TMP/p15_for3000.xml" | grep -qE '(^|[^[:alnum:]_:.-])est_tokens\s*=' \
    && ok "#15 --for: the legend defines est_tokens=" \
    || no "#15 --for: est_tokens= rides the root but no legend clause defines it"
grep -o '<!--.*-->' "$TMP/p15_for100.xml" | grep -qE '(^|[^[:alnum:]_:.-])over_ceiling\s*=' \
    && ok "#15 --for --token-budget=100: the legend defines over_ceiling=" \
    || no "#15 --for --token-budget=100: over_ceiling= rides the root but no legend clause defines it"
# (c) --handoff: priced, labelled, and withheld= is a boolean with the count beside it
"$BIN" . --handoff --token-budget=100 --no-cache >"$TMP/p15_ho100.xml" 2>/dev/null
"$BIN" . --handoff --token-budget=100000 --no-cache >"$TMP/p15_hobig.xml" 2>/dev/null
band15 "--handoff --token-budget=100000" "$TMP/p15_hobig.xml" handoff 320
[ "$( root_attr "$TMP/p15_ho100.xml" handoff over_ceiling )" = "1" ] \
    && ok "#15 --handoff --token-budget=100: root over_ceiling=\"1\" (the verified floor exceeds 100 tokens)" \
    || no "#15 --handoff --token-budget=100: $( bytes_of "$TMP/p15_ho100.xml" ) B delivered against a 100-token budget with no over_ceiling=\"1\" on the root"
W100="$( root_attr "$TMP/p15_ho100.xml" handoff withheld )"; WR100="$( root_attr "$TMP/p15_ho100.xml" handoff withheld_rows )"
case "$W100" in
    0|1) ok "#15 --handoff: withheld=\"$W100\" is a BOOLEAN (the map's spelling)" ;;
    *)   no "#15 --handoff: withheld=\"$W100\" is a COUNT under the boolean's name — the map spells withheld=\"1\" and puts the count beside it" ;;
esac
if [ -n "$WR100" ] && [ "$WR100" -gt 0 ] 2>/dev/null && [ "$W100" = "1" ]; then
    ok "#15 --handoff --token-budget=100: withheld_rows=\"$WR100\" carries the dropped-row count beside withheld=\"1\""
elif [ -n "$WR100" ] && [ "$WR100" = "0" ] && [ "$W100" = "0" ]; then
    ok "#15 --handoff --token-budget=100: no heuristic row to withhold on this tree (withheld_rows=\"0\" withheld=\"0\" agree)"
else
    no "#15 --handoff --token-budget=100: withheld=\"$W100\" withheld_rows=\"${WR100:-<absent>}\" — the pair is missing or disagrees"
fi
[ "$( root_attr "$TMP/p15_hobig.xml" handoff over_ceiling )" = "" ] \
    && ok "#15 --handoff --token-budget=100000: no over_ceiling= (absent = inside the ceiling, the map's convention)" \
    || no "#15 --handoff --token-budget=100000: over_ceiling=\"$( root_attr "$TMP/p15_hobig.xml" handoff over_ceiling )\" on a packet well inside its budget"
# (d) --expand --top-k=0: the root prices the bodies-only document, and that number IS the one --token-budget gates on
"$BIN" src --expand=pageWindow --top-k=0 --no-cache >"$TMP/p15_ex.xml" 2>/dev/null
band15 "--expand=pageWindow --top-k=0" "$TMP/p15_ex.xml" ctx 420
EX="$( root_est "$TMP/p15_ex.xml" ctx )"
if [ -n "$EX" ] && [ "$EX" -gt 1 ] 2>/dev/null; then
    "$BIN" src --expand=pageWindow --top-k=0 --no-cache --token-budget=$(( EX - 1 )) >/dev/null 2>"$TMP/p15_ex.err"; rc=$?
    grep -q "withheld_est_tokens=$EX " "$TMP/p15_ex.err" && [ "$rc" -ne 0 ] \
        && ok "#15 --expand --top-k=0: the root's est_tokens=$EX is the number --token-budget gates on (withheld_est_tokens=$EX, exit $rc) — one estimator" \
        || no "#15 --expand --top-k=0: root est_tokens=$EX but the gate says '$( head -1 "$TMP/p15_ex.err" | cut -c1-120 )' — two counters"
fi
# (e) the withheld spelling family-wide: no XML root anywhere in this arm's captures spells withheld= above 1
for f in p15_pt p15_pt50 p15_ft p15_ft50 p15_ho100 p15_hobig p15_ex; do
    if grep -qE ' withheld="([2-9]|[1-9][0-9]+)"' "$TMP/$f.xml" 2>/dev/null; then
        no "#15 $f: a root spells a COUNT under withheld= — the boolean name"
    fi
done
ok "#15 withheld= is a boolean on every root this arm captured"
# (f) mutation: the shape can fail
printf '<handoff budget="100" withheld="12">' >"$TMP/p15_mut.xml"
[ -z "$( root_est "$TMP/p15_mut.xml" handoff )" ] && [ "$( root_attr "$TMP/p15_mut.xml" handoff withheld )" = "12" ] \
    && ok "#15 mutation: the audited handoff root (no est_tokens, withheld=12) IS detected" \
    || no "#15 mutation: the arm cannot see the audited shape"
# (g) well-formed
if command -v xmllint >/dev/null 2>&1; then
    for f in p15_pt p15_pt50 p15_ft p15_ft50 p15_ho100 p15_hobig p15_ex; do
        [ -s "$TMP/$f.xml" ] || continue
        xmllint --noout "$TMP/$f.xml" 2>/dev/null && ok "#15 $f.xml is well-formed" || no "#15 $f.xml FAILED xmllint"
    done
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

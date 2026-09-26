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
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){   printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
cd "$ROOT"
echo "estchargecheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# ── BUILD-FLAVOUR / DEGRADE-OBSERVABILITY PROBE (read by #14 below) ───────────────────────────────────
# CI runs the whole suite TWICE: once against a Release binary (catches optimizer-only bugs, e.g. the
# ASSUME-then-defend trap) and once against the plain build — Release defines NDEBUG, which compiles
# DISCLOSE out, so "if you add a degrade path, it is the PLAIN run that proves it" (CLAUDE.md).
# #14 asserts a DISCLOSE, so under the Release binary it is unobservable BY DESIGN and must
# SKIP with the reason named; under the plain binary it must assert. What it must never do is pass
# silently for lack of an alert it could not have seen — the 2026-07-27 CI trap this gate was written
# against. (Before 2026-08-01 it took the other branch and FAILED under NDEBUG, which is the same trap
# from the other side: it made the Release CI leg unconditionally red, so the leg could never be trusted.)
#
# Two INDEPENDENT readings, because either alone can lie:
#   (1) an unrelated degrade path: a --scip index that OPENS and fails to DECODE ("[math degraded] --scip:
#       corrupt/truncated index"). If THAT one is silent too, this binary compiles alerts out globally
#       rather than #14's own seam having broken.
#   (2) --version's build-type token — versioncheck's source of truth, set by CMakeLists from
#       CMAKE_BUILD_TYPE ("dev" for the plain configure). Release/RelWithDebInfo/MinSizeRel define
#       NDEBUG; nothing else does.
# Only when BOTH agree — no alert observable anywhere AND an NDEBUG-defining flavour — is a skip honest.
# A binary that CLAIMS to be dev/asan yet observes no alerts is a real FAILURE, and so is one that can
# observe the unrelated alert but not #14's own.
#
# RE-POINTED 2026-09-16. Reading (1) used to be `--rank-by=churn --since=notadate`, which e7688981 (M8,
# 2026-09-04) made a refusal that exits 1 before any degrade path runs: silent on EVERY flavour, so the two
# readings had collapsed into one — measured: a Release-labelled binary that still printed every alert except
# #14's SKIPPED #14 instead of failing it. The replacement is the probe qualitystalecheck.sh uses; its index
# file lives in $TMP, outside the checkout, and --no-cache keeps the probe from writing next to test/fixture.
alerts_observable=0
printf 'not a scip index at all\n' > "$TMP/flavour.scip"
"$BIN" test/fixture --scip="$TMP/flavour.scip" --top-k=1 --no-cache >/dev/null 2>"$TMP/flavour.err"
grep -qF '[math degraded] --scip: corrupt/truncated index' "$TMP/flavour.err" && alerts_observable=1
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
# L1 (2026-09-19): the CLI default legend is compact; #5's legend arms read the FULL legend's max_tokens=/over_ceiling= prose
# from this sweep, so it asks for the full legend (byte-identical to the old default, and the larger envelope).
for N in 100 300 400 450 500 600 800 1200 1500 3000 6000; do
    "$BIN" src --max-tokens=$N --no-cache --legend=full >"$TMP/mt$N.out" 2>"$TMP/mt$N.err"
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
#    An ambiguous --expand bundle (issue #289) serves its <bodies> BEFORE the map, so "through `</r>`" would
#    count the bodies and their legend as map bytes. The map portion is then the root's open tag plus
#    everything after `</bodies>` through `</r>` — the same bytes the appended shape measures (measured on
#    --expand=estimateTokens at N=6000: the map legend and the <r> element are byte-identical in both orders).
mapbytes_of(){ python3 - "$1" <<'PY'
import sys
d = open( sys.argv[1], 'rb' ).read()
i = d.find( b'</r>' )
end = i + 4 if i >= 0 else len( d )
b0, r0, b1 = d.find( b'<bodies' ), d.find( b'<r ' ), d.find( b'</bodies>' )
if 0 <= b0 < r0 and b0 < b1 < r0:
    # CodeRabbit PR #292 finding 4052087945, VERIFIED AND REFINED (its own one-line suggestion —
    # subtracting from b0, the literal "<bodies" position, instead of rootTagEnd — was checked against the
    # real emission and found to overcorrect: everything between the root tag's '>' and the literal
    # "<bodies" is NOT uniformly a root disclosure. src/main.cpp's ctxOpenStr (map-charged: the §F5 verdict
    # bills it via + ctxUnprovenBytes / the note=/mapCtxOpenBytes terms) carries at most ONE thing there,
    # ctxUnprovenLegend, appended with NOTHING between it and the tag's '>' when ctxUnprovenDefs > 0. But
    # packBodies (serialize.h) ALSO writes kBodiesLegend — the <bodies> section's OWN "sibs=/inc=/calls"
    # legend, ~1 KB, gated on withFileContext (always on for --expand) — immediately before the literal
    # "<bodies" tag, and THAT is payload (bundleDoc.payloadBytes = bodiesSection.xml.size(), never a term in
    # the §F5 verdict). A flat b0 anchor folds kBodiesLegend into the "map portion" the probe reports,
    # overcounting by ~1 KB relative to what production actually bills to fit_bytes — measured on
    # --expand=estimateTokens --max-tokens=6000: a synthetic three-way check (rootTagEnd anchor / b0 anchor /
    # this fix) against a fixture carrying an unproven-legend AND a bodies-legend distinguishes all three;
    # only this anchor matches what src/main.cpp's own verdict prices.
    #
    # ctxOpenStr's real end: the tag's own '>' (rootTagEnd), pushed past ctxUnprovenLegend's whole comment
    # when one is present. Matched by its EXACT known literal opener ("<!-- ripwire expand: ",
    # unprovenDefsVerbComment's one call site in main.cpp — shared by --expand and --outline, the only two
    # verbs that reach this bodies-first shape), not by "any comment right here": kBodiesLegend is ALSO a
    # comment starting immediately at rootTagEnd with no gap (measured on the real corpus — see above), so
    # "starts with <!--" alone cannot tell the two apart; the literal opener can. FULL legend only — under
    # --legend=compact this opener is itself rewritten (graphlegend.h's own comment on
    # unprovenDefsVerbComment: "compactlegend.h strips it as the prose it is"), which this gate's #5/#5b/#5c
    # arms never invoke.
    rootTagEnd = d.find( b'>' ) + 1
    ctxAttrEnd = rootTagEnd
    if d[ rootTagEnd : rootTagEnd + len( b'<!-- ripwire expand: ' ) ] == b'<!-- ripwire expand: ':
        close = d.find( b'-->', rootTagEnd )
        if close != -1:
            ctxAttrEnd = close + 3
    end -= ( b1 + len( b'</bodies>' ) ) - ctxAttrEnd
print( end )
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

# ── #5c: mapbytes_of must keep a root disclosure that sits between the root tag and <bodies> (a REAL
#    root-priced clause) while still EXCLUDING the bodies section's own legend, which ALSO sits between the
#    root tag and the literal "<bodies" tag but is payload, not map — CodeRabbit PR #292 finding 4052087945,
#    verified against the real emission and refined (see mapbytes_of's own comment above for why the
#    finding's literal one-line suggestion — subtract from b0 — overcorrects: MEASURED on
#    --expand=estimateTokens --max-tokens=6000, src/, that anchor folds packBodies' ~1 KB kBodiesLegend into
#    the reported "map portion", which the real §F5 verdict never bills to fit_bytes). Three anchors, one
#    fixture, one number each:
#      rootTagEnd (the old bug)   → drops BOTH the root disclosure and the bodies legend
#      b0 (the finding's own diff) → keeps BOTH — wrongly keeps the bodies legend too
#      this fix (comment-aware)   → keeps ONLY the root disclosure — the one production actually bills
python3 - <<'PY' >"$TMP/synth_5c.xml"
import sys
prefix      = b'<ctx est_tokens="9">'
rootlegend  = b'<!-- ripwire expand: unproven_defs=2 (absent when 0) -- two internal-linkage definitions were dropped -->'
bodieslegend = b'<!-- a body legend not billed to fit_bytes: sibs=/inc=/calls, priced as payload -->'
bodies      = b'<bodies><b p="x.cpp" n="f">CODE</b></bodies>'
mapr        = b'<r est_tokens="5"><f p="y.cpp"><s n="g"/></f></r>'
sys.stdout.buffer.write( prefix + rootlegend + bodieslegend + bodies + mapr )
PY
GOT_5C="$( mapbytes_of "$TMP/synth_5c.xml" )"
WANT_5C="$( python3 -c '
prefix       = b"<ctx est_tokens=\"9\">"
rootlegend   = b"<!-- ripwire expand: unproven_defs=2 (absent when 0) -- two internal-linkage definitions were dropped -->"
mapr         = b"<r est_tokens=\"5\"><f p=\"y.cpp\"><s n=\"g\"/></f></r>"
print( len( prefix ) + len( rootlegend ) + len( mapr ) )
' )"
if [ "$GOT_5C" = "$WANT_5C" ]; then
    ok "#5c mapbytes_of: keeps the root disclosure, excludes the bodies-section legend ($GOT_5C B)"
else
    no "#5c mapbytes_of: got $GOT_5C B, want $WANT_5C B — either the root disclosure was dropped or the bodies legend leaked into the map charge"
fi

# ── #5d (§F5): CHARGE note= TO THE --max-tokens CEILING — CodeRabbit PR #292 finding 4052087920. The
#    bundle selector (bundleDoc.rootAttrBytes) already counted noteBytes, but neither the binary-search
#    that PICKS mapTopK nor the final over_ceiling verdict did — both land inside the same `<ctx ...>` open
#    tag mapCtxOpenBytes already charges, so a near-limit map could pick a topK whose real emission (with
#    note= riding along) overran the ceiling, unlabelled. A small isolated fixture (25 same-named,
#    ambiguous `run` definitions — deterministic ~52 B/topK growth, easy to land exactly on the boundary)
#    found the real one: MEASURED on the pre-fix binary at N=990, --expand=run picked top-8 and delivered
#    2224 B against a 2102 B ceiling (over by 122 B, the exact size of the missing note=), with no
#    over_ceiling label. Fixed, the same command picks top-5 (2082 B, within budget). Both figures pasted
#    in the lane report; this arm re-derives them live rather than trusting the snapshot.
F5D="$TMP/f5d_repo"; mkdir -p "$F5D"
for i in $( seq 1 25 ); do printf 'int run() { return %d; }\n' "$i" >"$F5D/f$i.cpp"; done
git -C "$F5D" init -q
git -C "$F5D" config user.email ripwire@example.invalid
git -C "$F5D" config user.name ripwire-gate
git -C "$F5D" add -A
git -C "$F5D" commit -qm base
"$BIN" "$F5D" --max-tokens=990 --expand=run --no-cache >"$TMP/f5d.out" 2>/dev/null
PB_5D="$( mapbytes_of "$TMP/f5d.out" )"
LIM_5D=$(( 990 * 2124 / 1000 ))   # N*2.36*0.90, integer (awk's earlier "%d" truncation, same formula every other arm uses)
OVER_5D=0; head -c "$PB_5D" "$TMP/f5d.out" | grep -aq 'over_ceiling=1' && OVER_5D=1
if [ "$PB_5D" -le "$LIM_5D" ] 2>/dev/null; then
    ok "#5d --max-tokens=990 --expand=run: map portion $PB_5D B within the $LIM_5D B ceiling (note= charged to the search)"
elif [ "$OVER_5D" = 1 ]; then
    ok "#5d --max-tokens=990 --expand=run: map portion $PB_5D B over the $LIM_5D B ceiling and SAYS SO (over_ceiling=1)"
else
    no "#5d --max-tokens=990 --expand=run: map portion $PB_5D B EXCEEDS the $LIM_5D B ceiling, unlabelled — note= was not charged to the search/verdict"
fi
# and the wording is payload-neutral (CodeRabbit finding 4052087924) — no "bodies" literal on an ambiguous
# --expand's ride-along note, which the fixture above already exercises.
if grep -aq 'note="[^"]*bodies' "$TMP/f5d.out"; then
    no "#5d note= still assumes bodies-only wording"
else
    ok "#5d note= wording does not assume the payload is bodies"
fi

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
    # NON-VACUOUS (L1 fix round, the iter1a measurement): the rate must be stated in the answer's own COMMENTS. A document-wide
    # grep passed on a ranked body that merely quoted "2.36" in its CDATA, while the compact legend never said it.
    python3 -c 'import re, sys
d = open( sys.argv[ 1 ], encoding = "utf-8", errors = "replace" ).read()
d = re.sub( r"<!\[CDATA\[.*?\]\]>", "", d, flags = re.S )
sys.exit( 0 if any( "2.36" in c for c in re.findall( r"<!--.*?-->", d, re.S ) ) else 1 )' "$TMP/part.out" \
        && ok "#6 --partition's bundle legend names the 2.36 B/tok rate its est_tokens uses (in a comment, outside CDATA)" \
        || no "#6 --partition reports est_tokens with no statement (in its legend comments) of which estimator/rate produced it"
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
    if [ "$g4" = 1 ]; then ok "#8 all payload shapes well-formed XML"; else no "#8 a payload shape is malformed XML"; fi
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

# A7 SWEEP (PR #135 CI, 2026-09-11) — the budget must bound the document at EVERY budget, not at the one operating
# point above. That arm went red at 5 429 B against its 5 428 B allowance when a merge moved the live src/ corpus,
# and the main binary emits the same 5 429 bytes on the same tree, so the corpus only exposed it. The defect: the
# ceiling ladder priced the document WITHOUT the root over_ceiling="1" (17 B) and the legend clause defining it
# (53 B), which runForLens splices on AFTER the ladder whenever est_tokens exceeds budget_tokens. est_tokens prices
# markup at 2.50 B/tok and the allowance is sized at 2.36 x 1.15 = 2.714 B/tok, so every bundle in that band
# carries 70 unpriced bytes, and one the ladder fitted within 70 B of the allowance is pushed past it with no rung
# fired. One budget on the live tree only sees that when the corpus lands a bundle in the 70 B window, so this arm
# builds its OWN git-less corpus in $TMP and runs it from a relative path (no at=, no churn, a fixed root=, nothing
# read from the live repo) and SWEEPS the budget in 10-token steps: the window recurs with every trimmed row
# (~50 tokens), so a sweep this dense crosses it whatever the legend lengths are. Two shapes — the default bundle
# and A7's own --detail=20 --with-graph. THE PROPERTY: delivered bytes <= N x 2.36 x 1.15 at exit 0, or the
# ladder's LAST rung fired and says so (the header floor alone exceeds the budget — the one overshoot it documents).
A7S="$TMP/a7sweep"
mkdir -p "$A7S/corpus"
python3 - "$A7S/corpus" <<'PYG'
import os, sys
out = sys.argv[1]
for i in range( 4 ):
    lines = []
    for j in range( 8 ):
        nxt = f"serializeRow{i}_{j + 1}( map, row )" if j + 1 < 8 else "0"
        lines += [ f"// serializeRow{i}_{j}: serialize one map row into the output buffer the map writer flushes",
                   f"int serializeRow{i}_{j}( int map, int row )", "{",
                   f"    int acc = map + row + {i * 7 + j};",
                   f"    for( int k = 0; k < {j + 3}; ++k )", "    {",
                   f"        acc += k * {i + 1} - row;", "    }",
                   f"    return acc + {nxt};", "}", "" ]
    with open( os.path.join( out, f"mod{i}.cpp" ), "w" ) as fh:
        fh.write( "\n".join( lines ) )
PYG
a7s_bad=""; a7s_badn=0; a7s_runs=0; a7s_inside_labelled=0
# RE-ANCHORED 2026-09-13 (PR #215): the default sweep starts at 760, not 1200. --for's rung zero now triggers on the
# EXACT ceiling (verbs_for.h), so a document 1..15% over its budget drops its three explanatory clauses before the
# allowance is consulted; on this corpus the late-label band (over_ceiling="1" INSIDE the allowance — the residual
# after that drop) therefore sits at 780..810 instead of inside 1200..1500, and the control below would otherwise be
# inert. Swept 700..3300 step 10 on the new binary: default hits at 780 790 800 810, none on the --detail=20 arm.
for spec in "default:760:1500:" "detail_graph:2880:3080:--detail=20 --with-graph"; do
    s_label="${spec%%:*}"; s_rest="${spec#*:}"; s_from="${s_rest%%:*}"; s_rest="${s_rest#*:}"; s_to="${s_rest%%:*}"; s_args="${s_rest#*:}"
    for (( N = s_from; N <= s_to; N += 10 )); do
        # shellcheck disable=SC2086
        ( cd "$A7S" && "$BIN" corpus --for="serialize the map" --token-budget=$N $s_args --no-cache ) >"$A7S/o.xml" 2>/dev/null
        s_rc=$?
        a7s_runs=$(( a7s_runs + 1 ))
        s_b="$( bytes_of "$A7S/o.xml" )"
        s_a="$( awk "BEGIN{printf \"%d\", $N*2.36*1.15}" )"
        s_root="$( grep -aoE '^<ctx [^>]*>' "$A7S/o.xml" | head -1 )"
        if [ "$s_rc" -ne 0 ] || { [ "$s_b" -gt "$s_a" ] && ! grep -aqF '[over_ceiling= is 1 on the root: the header floor' "$A7S/o.xml"; }; then
            a7s_badn=$(( a7s_badn + 1 ))
            [ "$a7s_badn" -le 6 ] && a7s_bad="$a7s_bad $s_label@$N=${s_b}/${s_a}B(exit $s_rc)"
        elif [ "$s_b" -le "$s_a" ] && [ "${s_root#* over_ceiling=\"1\"}" != "$s_root" ]; then
            a7s_inside_labelled=$(( a7s_inside_labelled + 1 ))
        fi
    done
done
[ "$a7s_badn" -eq 0 ] \
    && ok "#11 A7 sweep: $a7s_runs budgets over a git-less corpus (default 760..1500, --detail=20 --with-graph 2880..3080, step 10) — every document within N x 2.36 x 1.15 at exit 0, or on the ladder's disclosed last rung" \
    || no "#11 A7 sweep: $a7s_badn of $a7s_runs budgets deliver past the allowance with no ladder rung fired (first:$a7s_bad) — a byte spliced in after the ladder priced the document"
# control: the sweep must cross the band the defect lives in — a root that says over_ceiling="1" while the document
# still fits the allowance (est_tokens > N at 2.50 B/tok, bytes <= 2.714 B/tok). No such budget = inert, re-anchor.
[ "$a7s_inside_labelled" -gt 0 ] \
    && ok "#11 A7 sweep control: $a7s_inside_labelled budget(s) carry a root over_ceiling=\"1\" INSIDE the allowance — the sweep crosses the late-label band" \
    || no "#11 A7 sweep control: no budget carried over_ceiling=\"1\" inside the allowance — the sweep no longer reaches the est_tokens > N band, re-anchor its ranges"

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
#    DISCLOSE exists on — so this arm establishes that flavour with its OWN observability probe
#    rather than assuming it, and it must never pass for lack of an alert it could not have seen.
#
#    (a) OBSERVABILITY PROBE. If the switch has no effect, exactly one of two things is true, and the
#        preamble's two independent readings tell them apart: either this is an NDEBUG build, where the
#        arm is unobservable BY DESIGN and the plain-flavour CI leg is what proves it (→ SKIP, reason
#        named), or the seam regressed on a flavour that CAN see alerts (→ FAILURE). ─────────────────────
# L1 (2026-09-19): the compact legend spells <sigs> inside its comment, so #14c's find(<sigs) would start in the legend; both runs ask for the full legend.
RIPWIRE_FAULT_CHARGE_BUFFER=1 "$BIN" src --top-k=10 --pack-signatures --no-cache --legend=full >"$TMP/dg.out" 2>"$TMP/dg.err"
rc_dg=$?
if grep -aq 'chargeSection: open_memstream failed' "$TMP/dg.err"; then
    ok "#14a observability probe: this flavour CAN observe DISCLOSE (the fault switch is live)"

    #    (b) the alert names the CONSEQUENCE, on both the section and the document
    grep -aq 'streams uncharged' "$TMP/dg.err" \
        && ok "#14b the chargeSection alert says the section streams UNCHARGED" \
        || no "#14b the chargeSection alert fired but does not say the section is uncharged"
    grep -aq 'serialize: open_memstream failed .* MODELLED bytes, not the emitted ones' "$TMP/dg.err" \
        && ok "#14b the serialize alert says est_tokens reports MODELLED, not emitted, bytes" \
        || no "#14b serialize degraded without saying est_tokens switched to the MODELLED number"

    #    (c) THE BYTES ARE STILL COMPLETE AND CORRECT. The whole point of the degrade: the caller loses the
    #        charge, never the content. Byte-compare the payload against the undegraded run.
    "$BIN" src --top-k=10 --pack-signatures --no-cache --legend=full >"$TMP/dg_ctl.out" 2>/dev/null
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

    #    (d2) RE-PIN 2026-09-19 (owner decision, lane/disclose-sink-form): the modelled fallback STAYS (the number
    #         above) and is LABELLED — before, "the fallback is observable" meant only that the number was lower,
    #         which a reader cannot tell from a smaller map. est_measured="0" rides beside it in every build flavour
    #         (the MapEstimate / ChargedSection DISCLOSE sinks set it), defined in the same document, and the
    #         undegraded control carries none. One arm per site class, each isolating the buffer that failed:
    #         the XML map's own children buffer, the JSON map's rows + header-probe buffers, and a payload section
    #         on a map-less (--top-k=0) document, where the est rests on the section alone.
    grep -aq '<r [^>]* est_tokens="[0-9]*" est_measured="0"' "$TMP/dg.out" \
        && ok "#14d2 [XML map buffer] the modelled est_tokens is labelled est_measured=\"0\" on <r>" \
        || no "#14d2 [XML map buffer] the modelled est_tokens carries no est_measured=\"0\": $( grep -aoE '<r [^>]*>' "$TMP/dg.out" | head -1 | head -c 200 )"
    grep -aq 'est_measured=0: ' "$TMP/dg.out" \
        && ok "#14d2 [XML map buffer] est_measured= is defined in the same document" || no "#14d2 [XML map buffer] est_measured= rides undefined"
    grep -aq 'est_measured' "$TMP/dg_ctl.out" \
        && no "#14d2 control: the undegraded map carries est_measured" || ok "#14d2 control: the undegraded map carries no est_measured (measured is the default)"
    RIPWIRE_FAULT_CHARGE_BUFFER=1 "$BIN" test/fixture --json --no-cache >"$TMP/dgj.out" 2>/dev/null
    "$BIN" test/fixture --json --no-cache >"$TMP/dgj_ctl.out" 2>/dev/null
    { grep -aq '"est_tokens":[0-9]*,.*"est_measured":false' "$TMP/dgj.out" && ! grep -aq 'est_measured' "$TMP/dgj_ctl.out"; } \
        && ok "#14d2 [JSON map + header probe] \"est_measured\":false on the degrade, absent on the control (XML parity)" \
        || no "#14d2 [JSON map + header probe] the JSON map's modelled est_tokens is unlabelled: $( head -c 200 "$TMP/dgj.out" )"
    FXSYM="$( "$BIN" test/fixture --no-cache 2>/dev/null | grep -aoE ' n="[A-Za-z_]+"' | head -1 | sed 's/ n="//; s/"//' )"
    RIPWIRE_FAULT_CHARGE_BUFFER=1 "$BIN" test/fixture --top-k=0 --expand="$FXSYM" --no-cache >"$TMP/dgk0.out" 2>/dev/null
    "$BIN" test/fixture --top-k=0 --expand="$FXSYM" --no-cache >"$TMP/dgk0_ctl.out" 2>/dev/null
    { grep -aq '<ctx [^>]*est_tokens="[0-9]*" est_measured="0"' "$TMP/dgk0.out" && grep -aq 'est_measured=0: ' "$TMP/dgk0.out" \
      && ! grep -aq 'est_measured' "$TMP/dgk0_ctl.out"; } \
        && ok "#14d2 [payload section, --top-k=0 --expand=$FXSYM] the section-only est_tokens is labelled and defined; the control carries none" \
        || no "#14d2 [payload section] the uncharged section's est_tokens is unlabelled: $( grep -aoE '<ctx [^>]*>' "$TMP/dgk0.out" | head -1 )"

    RIPWIRE_FAULT_CHARGE_BUFFER=1 "$BIN" test/fixture --pack-task="parse the config" --with-graph --no-cache >"$TMP/dgpt.out" 2>/dev/null
    "$BIN" test/fixture --pack-task="parse the config" --with-graph --no-cache >"$TMP/dgpt_ctl.out" 2>/dev/null
    { grep -aq '<ctx [^>]*est_measured="0"' "$TMP/dgpt.out" && grep -aq 'est_measured=0: ' "$TMP/dgpt.out" \
      && ! grep -aq 'est_measured' "$TMP/dgpt_ctl.out"; } \
        && ok "#14d2 [trailing section, --pack-task --with-graph] the graph block streamed uncharged and the root says est_measured=\"0\"" \
        || no "#14d2 [trailing section] the pack-task est_tokens that left the graph block out is unlabelled: $( grep -aoE '<ctx [^>]*>' "$TMP/dgpt.out" | head -1 )"

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
        RIPWIRE_FAULT_CHARGE_BUFFER="$badval" "$BIN" src --top-k=10 --pack-signatures --no-cache --legend=full >"$TMP/dg_g4.out" 2>"$TMP/dg_g4.err"
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
    skip "#14 open_memstream degrade arms — DISCLOSE is compiled out of this binary (--version says build type \"$BUILD_FLAVOUR\", which defines NDEBUG; the unrelated --scip decode degrade path is silent here too, so alerts are unobservable globally rather than this seam having broken). The RIPWIRE_FAULT_CHARGE_BUFFER switch does not exist on this flavour either. These arms are proven by the PLAIN-flavour run of the same suite, which CI executes as a second leg for exactly this reason."
else
    no "#14a observability probe FAILED: RIPWIRE_FAULT_CHARGE_BUFFER=1 produced no DISCLOSE on a build that CAN observe alerts (--version build type \"$BUILD_FLAVOUR\", unrelated-degrade-path observable=$alerts_observable) — the openChargeBuffer seam regressed. This is a FAILURE, not a skip."
fi

# ── #14f THE MEMSTREAM FINISH DEGRADE: a buffer that opened and then lost a write takes the SAME path a failed open
#    takes, and never prints the short bytes. A memstream records a lost write in its error flag, and on macOS fflush and
#    fclose both return 0 afterwards (measured: 19 of 19 injected realloc failures; src/infra/emit.h MemoryStream).
#    Every site used to read buf/sz after an unchecked close. INFRA_FAULT_MEMSTREAM_FINISH=1 (non-NDEBUG only, like the
#    switch above) makes every finish report failure after really closing the stream, so each caller's degrade runs. The
#    observability rule is #14's: a flavour that CAN see alerts and sees none of these is a FAILURE, NDEBUG is a SKIP.
#    (a) the alert fires for the section AND the document;
#    (b) THE DOCUMENT IS STILL WHOLE: byte-identical to the undegraded run once every est_tokens number is masked. The
#        document was already spent into the buffer when the finish failed, so this proves the re-render, not a replay;
#    (c) exit 0 and well-formed XML; (d) est_tokens is the MODELLED number, below the charged one;
#    (e) --json: the same whole-document identity on the other serializer, and the document parses;
#    (f) --token-budget, where the buffer IS the answer and nothing can render it again: nothing reaches stdout, exit 1,
#        and stderr says the map was withheld — against an undegraded control that prints the map at exit 0.
#    (g) --from-trace, whose <trace> map and signature/body section are rendered only into their buffers: the same
#        refusal as (f). It used to print the bundle without either block at exit 0, which a Release build never told.
#    (h) the MCP `uses` verb answers -32603 under the fault, never a success with empty text;
#    (i) the --for lens (XML and --json) reports each redacted secret once when a degraded pre-render renders again.
#    These arms cover those surfaces, not every MemoryStream holder; #14g is the fence over the rest.
# RE-PIN 2026-09-19 (lane/disclose-sink-form, owner decision): the degraded document now LABELS its modelled number —
# est_measured="0" on the root, est_measured=0 in the header comment, "est_measured":false in JSON, and the one legend
# comment defining it. Those four spellings are the disclosure (asserted present by #14f(b2)), so they are masked with
# est_tokens: "byte-identical outside the estimate" is still the claim, and the estimate now carries its own label.
# L1 fix round (iter1a found item): the COMPACT default carries est_measured='s reading inside its one legend comment (a
# present-only term, compactlegend.h), not as the full dialect's own comment, so the mask drops that sentence too.
mask_est(){ sed -E 's/<!-- est_measured=0: [^>]*-->//g; s/ est_measured=0: est_tokens is the MODELLED estimate[^.]*\.//g; s/est_tokens(="?|":)[0-9]+/est_tokens\1N/g; s/ est_measured="0"//g; s/ est_measured=0//g; s/"est_measured":false,//g' "$1"; }
INFRA_FAULT_MEMSTREAM_FINISH=1 "$BIN" src --top-k=10 --pack-signatures --no-cache >"$TMP/mf.out" 2>"$TMP/mf.err"
rc_mf=$?
if grep -aq 'chargeSection: the charge buffer did not finish whole' "$TMP/mf.err"; then
    ok "#14f observability probe: INFRA_FAULT_MEMSTREAM_FINISH=1 reached the chargeSection finish"
    grep -aq 'serialize: the charge buffer did not finish whole .* MODELLED bytes' "$TMP/mf.err" \
        && ok "#14f(a) the serialize finish alert fired and says est_tokens reports the MODELLED bytes" \
        || no "#14f(a) serialize's finish degraded without its alert (or the alert lost the MODELLED clause)"
    "$BIN" src --top-k=10 --pack-signatures --no-cache >"$TMP/mf_ctl.out" 2>/dev/null
    if [ -s "$TMP/mf_ctl.out" ] && cmp -s <( mask_est "$TMP/mf_ctl.out" ) <( mask_est "$TMP/mf.out" ); then
        ok "#14f(b) the degraded document is byte-identical to the undegraded one outside est_tokens ($( bytes_of "$TMP/mf.out" ) B) — rendered again, whole"
    else
        no "#14f(b) the degraded document DIFFERS from the undegraded one outside est_tokens — a finish failure lost or corrupted content"
    fi
    grep -aq '<r [^>]* est_measured="0"' "$TMP/mf.out" && ! grep -aq 'est_measured' "$TMP/mf_ctl.out" \
        && ok "#14f(b2) the finish-degraded map labels its modelled est_tokens est_measured=\"0\"; the control carries none" \
        || no "#14f(b2) the finish-degraded map's modelled est_tokens is unlabelled"
    if [ "$rc_mf" -eq 0 ]; then
        ok "#14f(c) the degraded run exits 0"
    else
        no "#14f(c) the degraded run exited $rc_mf — a measurement buffer failure must degrade, not fail"
    fi
    if command -v xmllint >/dev/null 2>&1; then
        if xmllint --noout "$TMP/mf.out" 2>/dev/null; then
            ok "#14f(c) the degraded document is well-formed XML"
        else
            no "#14f(c) the degraded document is malformed XML"
        fi
    fi
    MFE="$( est_of "$TMP/mf.out" )";  MFC="$( est_of "$TMP/mf_ctl.out" )"
    { [ -n "$MFE" ] && [ -n "$MFC" ] && [ "$MFE" -lt "$MFC" ]; } 2>/dev/null \
        && ok "#14f(d) degraded est_tokens=$MFE is the MODELLED number, below the charged $MFC" \
        || no "#14f(d) degraded est_tokens=$MFE vs charged $MFC — the modelled fallback is not observable"
    INFRA_FAULT_MEMSTREAM_FINISH=1 "$BIN" src --top-k=10 --json --no-cache >"$TMP/mfj.out" 2>"$TMP/mfj.err"
    "$BIN" src --top-k=10 --json --no-cache >"$TMP/mfj_ctl.out" 2>/dev/null
    if grep -aq 'serializeJson: the charge buffer did not finish whole' "$TMP/mfj.err" && [ -s "$TMP/mfj_ctl.out" ] \
       && cmp -s <( mask_est "$TMP/mfj_ctl.out" ) <( mask_est "$TMP/mfj.out" ) \
       && python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TMP/mfj.out" 2>/dev/null; then
        ok "#14f(e) --json: the finish alert fired, and the document parses and is byte-identical outside est_tokens"
    else
        no "#14f(e) --json under the finish fault: no alert, a different document outside est_tokens, or JSON that does not parse"
    fi
    "$BIN" test/fixture --token-budget=100000 --no-cache >"$TMP/mft_ctl.out" 2>/dev/null; rc_mft_ctl=$?
    INFRA_FAULT_MEMSTREAM_FINISH=1 "$BIN" test/fixture --token-budget=100000 --no-cache >"$TMP/mft.out" 2>"$TMP/mft.err"; rc_mft=$?
    if [ "$rc_mft_ctl" -eq 0 ] && [ -s "$TMP/mft_ctl.out" ] && [ "$rc_mft" -eq 1 ] && [ ! -s "$TMP/mft.out" ] \
       && grep -aq 'the map is withheld, not printed short' "$TMP/mft.err"; then
        ok "#14f(f) --token-budget: the control prints $( bytes_of "$TMP/mft_ctl.out" ) B at exit 0; under the fault stdout is EMPTY, exit 1, and stderr says the map was withheld"
    else
        no "#14f(f) --token-budget under the finish fault: control rc=$rc_mft_ctl ($( bytes_of "$TMP/mft_ctl.out" ) B), faulted rc=$rc_mft with $( bytes_of "$TMP/mft.out" ) B on stdout — want 0/non-empty and 1/empty with the withheld line"
    fi
    printf 'Traceback (most recent call last):\n  File "test/fixture/app.py", line 10, in total_area\n    return sum(area_of_triangle(b, h) for b, h in triangles)\n  File "test/fixture/app.py", line 5, in area_of_triangle\n    return 0.5 * base * height\nZeroDivisionError: boom\n' >"$TMP/mftr.txt"
    "$BIN" test/fixture --from-trace="$TMP/mftr.txt" --no-cache >"$TMP/mftr_ctl.out" 2>/dev/null; rc_mftr_ctl=$?
    INFRA_FAULT_MEMSTREAM_FINISH=1 "$BIN" test/fixture --from-trace="$TMP/mftr.txt" --no-cache >"$TMP/mftr.out" 2>"$TMP/mftr.err"; rc_mftr=$?
    if [ "$rc_mftr_ctl" -eq 0 ] && grep -aq '<trace ' "$TMP/mftr_ctl.out" && [ "$rc_mftr" -eq 1 ] && [ ! -s "$TMP/mftr.out" ] \
       && grep -aq 'a --from-trace buffer lost bytes; the bundle is withheld' "$TMP/mftr.err"; then
        ok "#14f(g) --from-trace: the control prints its <trace> bundle ($( bytes_of "$TMP/mftr_ctl.out" ) B) at exit 0; under the fault stdout is EMPTY, exit 1, and stderr says the bundle was withheld"
    else
        no "#14f(g) --from-trace under the finish fault: control rc=$rc_mftr_ctl ($( bytes_of "$TMP/mftr_ctl.out" ) B), faulted rc=$rc_mftr with $( bytes_of "$TMP/mftr.out" ) B on stdout — want 0 with a <trace> block, then 1/empty with the withheld line (a bundle without its blocks is the defect)"
    fi
    # (h) the MCP verbs whose answer buffer IS the answer: under the fault each answers the internal error, -32603 —
    #     never a SUCCESS with empty text (an empty answer reads as "no use sites") and never the verb's not-found refusal
    #     (-32602, "no symbols found" / an unknown symbol), which is what impact, exemplar, path_between and for answered
    #     until CodeRabbit on #277: their builders collapsed a lost buffer into "" and the dispatch read "" as not-found.
    #     One control per verb proves the fixture answers its element with the fault OFF, so a -32603 below is the fault.
    python3 - "$BIN" "$ROOT/test/fixture" >"$TMP/mfuses.txt" 2>&1 <<'PY'
import json, os, subprocess, sys
b, root = sys.argv[1], sys.argv[2]
verbs = [ ( "uses",         { "symbol": "distance" },                     "<uses " ),
          ( "impact",       { "symbol": "distance" },                     "<impact " ),
          ( "exemplar",     { "kind": "fn" },                             "<exemplar " ),
          ( "path_between", { "from": "total_area", "to": "distance" },   "<path " ),
          ( "for",          { "task": "area distance" },                  "<ctx " ) ]
init = { "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": { "protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": { "name": "g", "version": "0" } } }
calls = [ { "jsonrpc": "2.0", "id": 2 + i, "method": "tools/call", "params": { "name": v, "arguments": dict( { "path": root }, **a ) } } for i, ( v, a, _ ) in enumerate( verbs ) ]
inp = ''.join( json.dumps( m ) + '\n' for m in [ init ] + calls )
for label, extra in ( ( 'ctl', {} ), ( 'fault', { 'INFRA_FAULT_MEMSTREAM_FINISH': '1' } ) ):
    out = subprocess.run( [ b, '--mcp' ], input=inp, capture_output=True, text=True, env=dict( os.environ, **extra ), timeout=120 ).stdout
    replies = { json.loads( l ).get( 'id' ): json.loads( l ) for l in out.splitlines() if l.strip().startswith( '{' ) }
    for i, ( v, _, element ) in enumerate( verbs ):
        reply = replies.get( 2 + i, {} )
        text = ( ( reply.get( 'result' ) or {} ).get( 'content' ) or [ {} ] )[ 0 ].get( 'text', '' )
        print( f"{label} verb={v} error={( reply.get( 'error' ) or {} ).get( 'code', 'none' )} result_text_bytes={len( text )} element={int( element in text )}" )
PY
    for mfVerb in uses impact exemplar path_between for; do
        if grep -q "^ctl verb=$mfVerb error=none result_text_bytes=[1-9][0-9]* element=1\$" "$TMP/mfuses.txt" && grep -q "^fault verb=$mfVerb error=-32603 " "$TMP/mfuses.txt"; then
            ok "#14f(h) MCP $mfVerb: the control answers its element; under the fault it answers -32603, not an empty success or a not-found"
        else
            no "#14f(h) MCP $mfVerb under the finish fault: $( grep " verb=$mfVerb " "$TMP/mfuses.txt" | tr '\n' ';' ) — want the control's element, then error -32603"
        fi
    done
    # (i) one redaction tally per secret: a degraded pre-render renders its rows again, and the stderr summary must
    #     count what was emitted once. XML --for and --json, each against its own undegraded control.
    mkdir -p "$TMP/mfred"
    printf 'def probeVaultHelper( token = "%s" ):\n    return token\n\ndef probeVaultLoader( key = "%s", label = "rotate-quarterly" ):\n    return probeVaultHelper( key )\n' \
        "ghp_""ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" "AKIA""IOSFODNN7EXAMPLE" > "$TMP/mfred/app.py"
    for mfredMode in xml json; do
        mfredFlag=""; [ "$mfredMode" = json ] && mfredFlag="--json"
        "$BIN" "$TMP/mfred" --for="probe vault loader helper" $mfredFlag --no-cache >/dev/null 2>"$TMP/mfred_ctl.err"
        INFRA_FAULT_MEMSTREAM_FINISH=1 "$BIN" "$TMP/mfred" --for="probe vault loader helper" $mfredFlag --no-cache >/dev/null 2>"$TMP/mfred_f.err"
        mfredCtl="$( grep -a '^ripwire: redacted ' "$TMP/mfred_ctl.err" )"; mfredF="$( grep -a '^ripwire: redacted ' "$TMP/mfred_f.err" )"
        if [ -n "$mfredCtl" ] && [ "$mfredCtl" = "$mfredF" ]; then
            ok "#14f(i) --for ($mfredMode): the redaction summary under the fault equals the control's ($mfredCtl)"
        else
            no "#14f(i) --for ($mfredMode): control says [${mfredCtl:-no summary}], faulted run says [${mfredF:-no summary}] — a re-rendered block counted its secrets twice"
        fi
    done
elif [ "$alerts_observable" -eq 0 ] && [ "$ndebug_flavour" -eq 1 ]; then
    skip "#14f memstream finish degrade arms — this NDEBUG binary has neither DISCLOSE nor the INFRA_FAULT_MEMSTREAM_FINISH switch (build type \"$BUILD_FLAVOUR\"); the PLAIN-flavour CI leg proves them"
else
    no "#14f observability probe FAILED: INFRA_FAULT_MEMSTREAM_FINISH=1 produced no finish alert on a build that CAN observe alerts (build type \"$BUILD_FLAVOUR\", observable=$alerts_observable) — the MemoryStream seam or its switch regressed"
fi

# ── #14g THE FENCE, over the source: every memstream is owned by rw::MemoryStream ─────────────────────────────────────
#    [[nodiscard]] on MemoryStream::finish makes a caller that IGNORES the answer a compiler warning; it cannot stop a
#    caller from opening a stream by hand, which is how twenty-two sites read buf/sz after an unchecked close. So, over
#    src/, with comments stripped:
#      (A) `open_memstream(` appears only inside `class MemoryStream` (src/infra/emit.h) and inside the one opener it is
#          handed, serialize.h's fault-injectable openChargeBuffer;
#      (B) openChargeBuffer is called only by openChargeStream, which hands it to MemoryStream::openWith;
#      (C) no fflush/fclose names a FILE* that came from a memory stream (`= x.open(…)` or `x.openWith(…)`, `= openChargeStream(…)` or
#          `= open_memstream(…)`, spelled bare, `::`, `os::` or `rw::os::`).
#    Presence guards first (the class and its [[nodiscard]] finish exist, and the population is real), then the rule,
#    then a POSITIVE CONTROL: the same scan over a copy of src/ with one real site turned back into the hand-written
#    open and close it replaced must report exactly that site — a scan that cannot fail is not a fence.
memstream_scan(){ python3 - "$1" <<'PY'
import os, re, sys
src = sys.argv[1]
texts = {}
for dirpath, _, files in os.walk( src ):
    for fn in sorted( files ):
        if fn.endswith( ( '.h', '.cpp', '.hpp', '.inl' ) ):
            path = os.path.join( dirpath, fn )
            texts[ os.path.relpath( path, src ) ] = open( path, encoding='utf-8', errors='replace' ).read().split( '\n' )
code = lambda line: line.split( '//', 1 )[0]
def region( rel, head, close ):
    lines = texts.get( rel, [] )
    start = next( ( i for i, l in enumerate( lines ) if re.match( head, l ) ), None )
    end   = next( ( i for i in range( start, len( lines ) ) if lines[i] == close ), None ) if start is not None else None
    return ( start, end )
def region_oneline( rel, head ):
    # a self-contained one-line definition ( `{ ... }` on its own line): the region is that single line.
    lines = texts.get( rel, [] )
    start = next( ( i for i, l in enumerate( lines ) if re.match( head, l ) ), None )
    return ( start, start ) if start is not None else ( None, None )
emit, ser = os.path.join( 'infra', 'emit.h' ), 'serialize.h'
cls  = region( emit, r'class MemoryStream\b', '};' )
opnr = region( ser, r'inline std::FILE\* openChargeBuffer\s*\(', '}' )
strm = region( ser, r'inline std::FILE\* openChargeStream\s*\(', '}' )
# src/infra/os.h is THE seam (infra/os.h's own header comment): its open_memstream is the ONE place the raw libc
# call is still spelled bare — every other opener in this tree now goes through os::open_memstream / rw::os::open_memstream
# (MemoryStream::open and serialize.h's openChargeBuffer both call it that way, so (A) never sees them). That one
# wrapper definition is exempt by name, not by a widened pattern — a NEW hand-written open_memstream anywhere else,
# os.h included, still fires.
osh    = os.path.join( 'infra', 'os.h' )
osOpen = region_oneline( osh, r'\[\[gnu::always_inline\]\] inline std::FILE\* open_memstream\(' )
# The same seam's Windows half: os.h's Windows branch DECLARES open_memstream (one line), and src/infra/os_win32.cpp
# DEFINES it (a temporary file whose bytes os::fflush / os::fclose publish). Both are the seam itself, exempt by name.
osWin  = os.path.join( 'infra', 'os_win32.cpp' )
osDecl = region_oneline( osh, r'std::FILE\* open_memstream\( char\*\* buffer, std::size_t\* size \);' )
winDef = region( osWin, r'std::FILE\* open_memstream\(', '}' )
inside = lambda rel, i, r, want: rel == want and r[0] is not None and r[1] is not None and r[0] <= i <= r[1]
finish = cls[1] is not None and any( re.search( r'\[\[nodiscard\]\]\s*MemoryStreamBytes\s+finish\s*\(', l ) for l in texts[ emit ][ cls[0]:cls[1] ] )
holders, violations = 0, []
OPENED = re.compile( r'([A-Za-z_]\w*)\s*=\s*(?:[A-Za-z_]\w*\.open(?:With)?\s*\(|(?:::)?(?:rw::)?(?:os::)?(?:open_memstream|openChargeStream)\s*\()' )
for rel, lines in sorted( texts.items() ):
    holders += sum( len( re.findall( r'\bMemoryStream\s+[A-Za-z_]\w*\s*;', code( l ) ) ) for l in lines )
    names = { m.group( 1 ) for l in lines for m in OPENED.finditer( code( l ) ) }
    closes = re.compile( r'\b(?:std::)?(fflush|fclose)\s*\(\s*(' + '|'.join( re.escape( n ) for n in sorted( names ) ) + r')\s*\)' ) if names else None
    for i, l in enumerate( lines ):
        c = code( l )
        if re.search( r'\bopen_memstream\s*\(', c ) and not inside( rel, i, cls, emit ) and not inside( rel, i, opnr, ser ) and not inside( rel, i, osOpen, osh ) \
           and not inside( rel, i, osDecl, osh ) and not inside( rel, i, winDef, osWin ):
            violations.append( f'{rel}:{i + 1}: (A) open_memstream outside MemoryStream' )
        if re.search( r'\bopenChargeBuffer\s*\(', c ) and not inside( rel, i, opnr, ser ) and not inside( rel, i, strm, ser ):
            violations.append( f'{rel}:{i + 1}: (B) openChargeBuffer called outside openChargeStream' )
        if closes and not inside( rel, i, cls, emit ):
            for m in closes.finditer( c ):
                violations.append( f'{rel}:{i + 1}: (C) {m.group( 1 )}( {m.group( 2 )} ) on a memory stream' )
print( f'holders={holders} class={int( cls[1] is not None )} finish_nodiscard={int( finish )} opener={int( opnr[1] is not None and strm[1] is not None )} violations={len( violations )}' )
for v in violations:
    print( 'VIOLATION ' + v )
PY
}
memstream_scan "$ROOT/src" >"$TMP/ms_live.txt" 2>&1
MS_SUMMARY="$( head -1 "$TMP/ms_live.txt" )"
MS_HOLDERS="$( sed -nE 's/^holders=([0-9]+).*/\1/p' "$TMP/ms_live.txt" )"
MS_VIOL="$( sed -nE 's/.* violations=([0-9]+)$/\1/p' "$TMP/ms_live.txt" )"
{ [ -n "$MS_HOLDERS" ] && [ "$MS_HOLDERS" -ge 10 ]; } 2>/dev/null \
    && ok "#14g presence: $MS_HOLDERS MemoryStream holders under src/ ($MS_SUMMARY)" \
    || no "#14g presence: '${MS_HOLDERS:-no}' MemoryStream holders — the population is gone or the pattern stopped matching ($MS_SUMMARY)"
grep -q 'class=1 finish_nodiscard=1 opener=1' "$TMP/ms_live.txt" \
    && ok "#14g presence: class MemoryStream with a [[nodiscard]] finish(), and serialize.h's openChargeBuffer and openChargeStream, all found" \
    || no "#14g presence: MemoryStream, its [[nodiscard]] finish(), openChargeBuffer or openChargeStream is missing — the exemptions would exempt nothing ($MS_SUMMARY)"
[ "$MS_VIOL" = "0" ] \
    && ok "#14g the rule: 0 hand-written open_memstream / openChargeBuffer / fflush / fclose of a memory stream outside MemoryStream" \
    || no "#14g a memory stream handled by hand outside MemoryStream: $( grep '^VIOLATION' "$TMP/ms_live.txt" | tr '\n' ';' )"
#    positive control: turn tracelocus.h's first MemoryStream back into the hand-written open and close it replaced, once
#    per spelling of the opener a call site can use — (C) keys the close on the name the open assigned, so a spelling the
#    OPENED pattern does not know hides the close even while (A) still reports the open. The hand-opened FILE* gets a
#    name no other site in the file assigns (`hand`): (C)'s names are per file, and tracelocus.h's other holders all
#    call theirs `m`, so a control that reused `m` would pass on a sibling's open and prove nothing about this one.
for MS_SPELL in open_memstream ::open_memstream os::open_memstream rw::os::open_memstream; do
    rm -rf "$TMP/ms_src"; cp -R "$ROOT/src" "$TMP/ms_src"
    python3 - "$TMP/ms_src/tracelocus.h" "$MS_SPELL" <<'PY'
import sys
p, spell = sys.argv[1], sys.argv[2]; t = open( p ).read()
t = t.replace( 'rw::MemoryStream stream;\n    std::FILE* const m = stream.open();', 'char* buf = nullptr;  std::size_t sz = 0;\n    std::FILE* hand = ' + spell + '( &buf, &sz );\n    std::FILE* const m = hand;', 1 )
t = t.replace( 'const rw::MemoryStreamBytes block = stream.finish();', 'std::fclose( hand );  const rw::MemoryStreamBytes block{ std::string_view( buf, sz ), buf != nullptr };', 1 )
open( p, 'w' ).write( t )
PY
    if cmp -s "$ROOT/src/tracelocus.h" "$TMP/ms_src/tracelocus.h"; then
        no "#14g positive control ($MS_SPELL): the mutation did not take (tracelocus.h unchanged) — the control proves nothing"
        continue
    fi
    memstream_scan "$TMP/ms_src" >"$TMP/ms_ctl.txt" 2>&1
    MS_CA="$( grep -c '^VIOLATION tracelocus.h:[0-9]*: (A)' "$TMP/ms_ctl.txt" )"
    MS_CC="$( grep -c '^VIOLATION tracelocus.h:[0-9]*: (C) fclose( hand )' "$TMP/ms_ctl.txt" )"
    MS_CT="$( grep -c '^VIOLATION' "$TMP/ms_ctl.txt" )"
    if [ "$MS_CA" = "1" ] && [ "$MS_CC" = "1" ] && [ "$MS_CT" = "2" ]; then
        ok "#14g positive control ($MS_SPELL): the same scan over a copy with one site hand-opened and hand-closed again reports exactly those two lines ($( grep '^VIOLATION' "$TMP/ms_ctl.txt" | sed 's/^VIOLATION //' | tr '\n' ' '))"
    else
        no "#14g positive control ($MS_SPELL): expected tracelocus.h (A)=1 (C)=1 and 2 in total, got $MS_CA, $MS_CC and $MS_CT — the scan cannot see the defect it exists for"
    fi
done

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
band15(){   # $1 label $2 file $3 root-element $4 hi*100 [$5 arm tag, default #15]
    local label="$1" f="$2" el="$3" hi="$4" tag="${5:-#15}" E B R
    E="$( root_est "$f" "$el" )"; B="$( bytes_of "$f" )"
    if [ -z "$E" ] || [ "$E" -eq 0 ] 2>/dev/null; then
        no "$tag $label: <$el> root carries no est_tokens= ($( perl -0pe 's#<!--.*?-->##gs' "$f" | grep -oE "<$el( [^>]*)?>" | head -1 | cut -c1-140 ))"; return
    fi
    R=$(( B * 100 / E ))
    { [ "$R" -ge 200 ] && [ "$R" -le "$hi" ]; } \
        && ok "$tag $label: $B B / est_tokens=$E = $(( R / 100 )).$(( R % 100 )) B/tok — inside the 2.00-$(( hi / 100 )).$(( hi % 100 )) band" \
        || no "$tag $label: $B B / est_tokens=$E = $(( R / 100 )).$(( R % 100 )) B/tok — OUTSIDE the band (the root's number does not price the delivered document)"
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
#     verify-wave2 F2: the byte half above cannot see the defect it was written for. At --token-budget=1600
#     the bundle is 3,485 B against a 4,342 B allowance — so the allowance arm PASSES — while the very same
#     root says budget_tokens="1600" est_tokens="1665" and withholds the one attribute that reconciles them.
#     over_ceiling= fired only on the ladder's LAST RUNG, so a bundle that overshoots by a little (the common
#     case) was silently unlabelled while one that overshoots by a lot was labelled. The property is about the
#     two NUMBERS the root itself prints, in the unit it prints them in: est_tokens <= N OR over_ceiling="1",
#     on EVERY rung. 1600/1700 are in the sweep because they are the rungs that were red.
for N in 100 300 400 600 800 1200 1500 1600 1700 2000 2500 3000; do
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
    # F2 — the TOKEN property, independent of the byte allowance above: the root prints budget_tokens= and
    # est_tokens= in the same unit, so a reader can subtract them. Whenever it does and the answer is
    # positive, the root must say over_ceiling="1"; silence there means "inside the budget".
    if [ -n "$FE" ] && [ "$FE" -gt "$N" ] 2>/dev/null; then
        [ "$FO" = "1" ] \
            && ok "#15 --for --token-budget=$N: est_tokens=$FE > $N and the root says over_ceiling=\"1\"" \
            || no "#15 --for --token-budget=$N: root prints budget_tokens=$N est_tokens=$FE (over by $(( FE - N ))) with NO over_ceiling= — the two numbers contradict each other on one root"
    elif [ -n "$FE" ]; then
        [ "$FO" = "1" ] \
            && no "#15 --for --token-budget=$N: root says over_ceiling=\"1\" but est_tokens=$FE is inside the $N budget — the label is a lie in the other direction" \
            || ok "#15 --for --token-budget=$N: est_tokens=$FE <= $N and the root is silent (absent = inside the budget)"
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
        if xmllint --noout "$TMP/$f.xml" 2>/dev/null; then ok "#15 $f.xml is well-formed"; else no "#15 $f.xml FAILED xmllint"; fi
    done
fi

# ── #16 (F5, terminality round A 2026-09-05): the MCP `for` bundle PRICES itself ────────────────────────
# The MCP twin used to DECLARE est_tokens absent — `lens="churn,amp,tested,est_tokens"`, with a legend
# sentence saying "this bundle is capped by the server, not priced". Declaring an absence is honest about
# a hole; it is not an answer. The bundle is fully rendered in memory before it is returned, so it can be
# priced, and a client that gets no number cannot budget the call it just paid for (capture-audit
# merge-wave2 "found, not fixed" #2). Same property this whole gate asserts everywhere else: the reported
# est_tokens must PRICE the delivered document, checked as a byte-rate band, never as a pinned number.
#
# `legend` is passed only if the server accepts it (lane M is adding it in parallel): the arm must not
# depend on whichever legend dialect is the default on the day it runs, and must not fail on a server that
# has no such field yet.
mcp_for_text(){   # $1 task, $2 extra JSON arguments (may be empty) → the tool's text payload on stdout
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
                  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"for\",\"arguments\":{\"task\":\"$1\"$2}}}" \
        | ( cd "$ROOT" && "$BIN" --mcp 2>/dev/null ) | tail -1 | python3 -c '
import sys, json
r = json.load( sys.stdin )
sys.stdout.write( r["result"]["content"][0]["text"] if "result" in r else "" )
'
}
LEGARG=""
[ -n "$( mcp_for_text "rank graph teleport" ',"legend":"full"' )" ] && LEGARG=',"legend":"full"'
mcp_for_text "rank graph teleport" "$LEGARG" >"$TMP/f5_mcp.xml"
if [ ! -s "$TMP/f5_mcp.xml" ]; then
    no "#16 MCP for returned nothing (legend arg '${LEGARG:-none}') — the arm cannot measure what it cannot fetch"
else
    ok "#16 MCP for answered $( bytes_of "$TMP/f5_mcp.xml" ) B (legend arg: ${LEGARG:-none})"
    band15 "MCP for (server-side bundle)" "$TMP/f5_mcp.xml" ctx 320 "#16"
    # the declaration must go when the thing is served: an attribute named as NOT MEASURED while the root
    # carries it is worse than either state alone (a reader believes the declaration).
    LENS="$( root_attr "$TMP/f5_mcp.xml" ctx lens )"
    case "$LENS" in
        *est_tokens*) no "#16 MCP for still declares est_tokens absent (lens=\"$LENS\") while the root serves it — the declaration contradicts the document" ;;
        *)            ok "#16 MCP for's lens= declaration no longer names est_tokens (lens=\"$LENS\") — it is served, not declared" ;;
    esac
    grep -q 'this bundle is capped by the server, not priced' "$TMP/f5_mcp.xml" \
        && no "#16 MCP for's legend still says the bundle is 'not priced' while the root prices it" \
        || ok "#16 MCP for's legend no longer claims the bundle is unpriced"
    # CLI/MCP agreement in KIND, not in bytes: the two dialects deliberately serve different payload (the
    # CLI folds the git/clone lens columns, the server runs no such pass), so the assertion is that both
    # numbers are the same estimator applied to their own bytes — i.e. both land in the same markup band.
    "$BIN" "$ROOT" --for="rank graph teleport" --no-cache >"$TMP/f5_cli.xml" 2>/dev/null
    band15 "CLI --for (same task, same repo)" "$TMP/f5_cli.xml" ctx 320 "#16"
    if command -v xmllint >/dev/null 2>&1; then
        if xmllint --noout "$TMP/f5_mcp.xml" 2>/dev/null; then ok "#16 the priced MCP for bundle is well-formed XML"; else no "#16 the priced MCP for bundle is malformed XML"; fi
    fi
fi

# ── #17 (0.6.1, M2): --connect must charge its CONDITIONAL legend comment, and stay CONSERVATIVE ────────
# packConnect emits THREE things ahead of its payload — kConnectHeader, the #66 graph_unindexed legend
# comment (emitted exactly when graph_unindexed= rides the root), and the shared root-relative legend — and
# connectExtraBytes charged only two of them. PR #72 (issue #66, 382e66e6) raised kConnectRootBytes 260 -> 285 for the
# ATTRIBUTE and missed the 185 B COMMENT beside it, so on the two corpora below — identical but for one file
# no grammar can read — the delivered document grew 205 B (185 B comment + the 20 B attribute) while
# est_tokens did not move by a single token:
#     0 unindexed files  2503 B   est_tokens=1049   modelled 2622 B   -119 B  (conservative)
#     1 unindexed file   2708 B   est_tokens=1049   modelled 2622 B    +86 B  (OPTIMISTIC — the defect)
# The printed est_tokens, the --max-tokens fit check and the over_ceiling="1" verdict then all measure a
# smaller document than the caller receives, which is precisely what connectEstTokens' own header and
# kConnectRootBytes' ("short is the ONE direction this constant may not be") say must never happen.
#
# WHY THIS IS NOT ALREADY COVERED by #1/#15's band arms: 2503/1049 = 2.38 B/tok and 2708/1049 = 2.58 B/tok
# sit comfortably INSIDE the 2.00-3.20 markup band, so a band arm is green on both sides of the defect. The
# separating property is the DIRECTION, not the magnitude — the delivered document must fit inside
# est_tokens x kBytesPerTokenDefault (2.50) — and it must be asserted on a corpus that HAS an unindexed
# file, because that is the only arm the uncharged comment reaches. Both corpora are asserted so the arm
# cannot pass by measuring the side that was never broken.
#
# THE FIXTURE NAMES ARE THE SAME LENGTH ON PURPOSE, and that is not cosmetic. The first spelling of this
# arm used "clean" and "unindexed": four extra path bytes land inside root="...", connectExtraBytes DOES
# charge root=, and the estimate therefore moved 1047 -> 1048 across the mutation (observed, on the binary
# this arm was written red against). The monotone arm (c)
# passed on that ONE token while the defect it names was fully present — CONTRIBUTING §2 shape 5, a control
# whose two arms differ in something other than the thing under test. Equal-length names make the legend
# comment the only byte source that can move the estimate.
C17="$TMP/c17"
mkdir -p "$C17/unindexed_0/src" "$C17/unindexed_1/src"
for d in unindexed_0 unindexed_1; do
    printf 'export function greet( name: string ): string\n{\n    return `hello ${name}`;\n}\n'                        >"$C17/$d/src/util.ts"
    printf 'import { greet } from "./util.ts";\nexport function render(): string\n{\n    return greet( "world" );\n}\n' >"$C17/$d/src/consumer.ts"
done
# THE ONE DIFFERENCE between the two corpora: a file no grammar in this build can read (real input, really
# mutated — the identical extraction runs over both).
# `.vue`, NOT `.astro`: issue #67 made .astro indexable (it rides the TypeScript grammar over its `---`
# frontmatter), which is exactly the "if .astro ever became indexable" case the presence guards below were
# written for — they fired, and this is the update they asked for.
printf -- '<script setup lang="ts">\nconst x = 1;\n</script>\n<template><p>{{ x }}</p></template>\n' >"$C17/unindexed_1/src/page.vue"
for d in unindexed_0 unindexed_1; do
    # L1 (2026-09-19): #17 measures the FULL legend's #66 comment (graph_unindexed= prose), so it asks for the full legend.
    "$BIN" "$C17/$d" --connect=render,greet --no-cache --legend=full >"$TMP/c17_$d.xml" 2>/dev/null
done
C17_LEGEND='graph_unindexed=N is a third gauge'
# (a) presence guards — assert the mutation TOOK before trusting any number derived from it. Without these
#     the arm is the "wrong population" shape: if .vue ever became indexable, or the legend moved, the two
#     corpora would be identical and the comparison below would prove nothing while staying green.
C17_CLEAN_U="$(  root_attr "$TMP/c17_unindexed_0.xml" connect graph_unindexed )"
C17_UNIDX_U="$(  root_attr "$TMP/c17_unindexed_1.xml" connect graph_unindexed )"
{ [ -z "$C17_CLEAN_U" ] && [ "$C17_UNIDX_U" = "1" ]; } \
    && ok "#17 mutation took: the clean corpus carries no graph_unindexed= and the mutated one carries graph_unindexed=\"1\"" \
    || no "#17 mutation did NOT take: graph_unindexed= is '${C17_CLEAN_U:-<absent>}' clean vs '${C17_UNIDX_U:-<absent>}' mutated — the arm is measuring two identical corpora"
{ ! grep -q "$C17_LEGEND" "$TMP/c17_unindexed_0.xml" && grep -q "$C17_LEGEND" "$TMP/c17_unindexed_1.xml"; } \
    && ok "#17 the #66 legend comment is emitted on the mutated corpus and absent on the clean one (the uncharged bytes are really there)" \
    || no "#17 the #66 legend comment is not where this arm needs it — present on clean, or missing from the mutated corpus"
C17_BC="$( bytes_of "$TMP/c17_unindexed_0.xml" )"; C17_EC="$( root_est "$TMP/c17_unindexed_0.xml" connect )"
C17_BU="$( bytes_of "$TMP/c17_unindexed_1.xml" )"; C17_EU="$( root_est "$TMP/c17_unindexed_1.xml" connect )"
{ [ -n "$C17_EC" ] && [ -n "$C17_EU" ] && [ "$C17_EC" -gt 0 ] && [ "$C17_EU" -gt 0 ]; } 2>/dev/null \
    || no "#17 a <connect> root carries no positive est_tokens= (clean '$C17_EC', mutated '$C17_EU')"
[ "$C17_BU" -gt "$C17_BC" ] 2>/dev/null \
    && ok "#17 the mutated document is $(( C17_BU - C17_BC )) B larger than the clean one ($C17_BC -> $C17_BU B)" \
    || no "#17 the mutated document did not grow ($C17_BC -> $C17_BU B) — there is nothing for est_tokens to have missed"
# (b) THE PROPERTY, on both corpora: the WHOLE delivered document fits inside est_tokens x 2.50 B/tok.
#     Integer math, no tolerance added: kConnectRootBytes deliberately OVER-covers the start tag, so a
#     correctly charged document sits ~100 B clear of this line and only an uncharged section crosses it.
#     The 2.50 is serialize.h's kBytesPerTokenDefault, the rate connectEstTokens divides by — if that
#     constant ever moves, this arm's 25/10 moves with it, the same hand-pinned coupling #1's bands carry.
for entry in "0 unindexed files:$C17_BC:$C17_EC" "1 unindexed file:$C17_BU:$C17_EU"; do
    lab="${entry%%:*}"; rest="${entry#*:}"; b="${rest%%:*}"; e="${rest#*:}"
    [ -n "$e" ] && [ "$e" -gt 0 ] 2>/dev/null || continue
    m=$(( e * 25 / 10 ))
    [ $(( b * 10 )) -le $(( e * 25 )) ] \
        && ok "#17 --connect ($lab): $b B delivered against est_tokens=$e x 2.50 = $m B modelled — CONSERVATIVE by $(( m - b )) B" \
        || no "#17 --connect ($lab): $b B delivered against est_tokens=$e x 2.50 = $m B modelled — OPTIMISTIC by $(( b - m )) B; a section of the document is not charged to est_tokens"
done
# (c) MONOTONE, the same property #2/#11 assert elsewhere: the two corpora share a payload byte for byte, so
#     the ONLY thing that moved is the legend comment — and an estimate that does not move when the document
#     does is the signature of the defect (est_tokens=1049 on both sides of a 205 B growth).
{ [ -n "$C17_EU" ] && [ -n "$C17_EC" ] && [ "$C17_EU" -gt "$C17_EC" ]; } 2>/dev/null \
    && ok "#17 --connect: est_tokens rose $C17_EC -> $C17_EU when the document grew (the conditional legend is charged)" \
    || no "#17 --connect: est_tokens stayed at '$C17_EC' -> '$C17_EU' across a $(( C17_BU - C17_BC )) B growth — the conditional legend comment is uncharged"
# (d) G4 — the two captures stay well-formed (this arm reads bytes, so it must not be reading a broken doc)
if command -v xmllint >/dev/null 2>&1; then
    for f in c17_unindexed_0 c17_unindexed_1; do
        if xmllint --noout "$TMP/$f.xml" 2>/dev/null; then ok "#17 $f.xml is well-formed"; else no "#17 $f.xml FAILED xmllint"; fi
    done
fi

# ── #18 (PR #215 review): RUNG ZERO PRICES THE DOCUMENT IT WOULD EMIT, IN THE ROOT'S OWN MIXED RATE ────
#
# THE DEFECT. --for's ceiling ladder has a rung ZERO below its own three rungs: the droppable legend trio
# (the confidence reading, the r=/<tail> reading, the sc=/route= reading). It fires when the header does not
# fit "the ceiling the root promises", and it used to spell that ceiling in BYTES — the raw document total
# against budget x 2.50 — while the promise itself, est_tokens <= budget_tokens, is a MIXED rate: markup at
# 2.50 B/tok and the --detail / auto bodies at 3.80 B/tok (serialize.h, finishForLensHeader). Every body byte
# was therefore charged 1.52x what the root charges it. The same test also priced the candidate through a sum
# built from RESERVES and from the auto section whether or not that section was rendered — not the document
# stdout receives. Both errors point one way: a document its own root says fits was judged not to, and three
# definitions the reader has no other source for were spent to buy headroom that was already there.
#
# WHAT IS ASSERTED, and why it needs no magic budget. A document that prices at est_tokens=E fits EVERY budget
# >= E, by the root's own arithmetic — so this arm READS E off a wide run where nothing is dropped and probes
# just above it. No pinned byte count: if the corpus or the legend moves, E moves with it and the probe follows.
# Both guards against an empty pass are asserted rather than assumed — the wide run must carry the clauses (else
# there is no E), and the control below must still DROP them (else the rung is gone, not fixed).
# GIT-LESS and relative, the #11 A7 sweep's discipline: no at=, no churn, a fixed root=, nothing from the live
# repo. --detail=1 is what puts bytes at the BODY rate, which is the half of the defect a bodiless bundle cannot
# see; the fixture's one long body exceeds the tight budget's residual, so the first-entry-whole floor emits a
# truncated ~190 B of it at every budget in the band and the band's width is that floor x (1/2.50 - 1/3.80).
# MEASURED on the c4478402 binary: the band is 1069..1099 — 31 budgets at which the kept document prices at
# est_tokens=1069 with no over_ceiling=, and the pre-fix rung dropped all three clauses and delivered 715.
RZ="$TMP/rungzero"
mkdir -p "$RZ/corpus"
python3 - "$RZ/corpus" <<'PYRZ'
import os, sys
out   = sys.argv[ 1 ]
lines = [ "def widgetPingBoxRouter( alpha, beta ):",
          '    """Widget ping box router: route every alpha reading onto the beta box."""',
          "    total = 0" ]
for j in range( 26 ):
    lines.append( f"    total = total + alpha * {j} - beta * {j} + widgetPingStep{j % 4}( total, {j} )" )
lines.append( "    return total" )
with open( os.path.join( out, "router.py" ), "w" ) as fh:
    fh.write( "\n".join( lines ) + "\n" )
with open( os.path.join( out, "steps.py" ), "w" ) as fh:
    for j in range( 4 ):
        fh.write( f'def widgetPingStep{j}( total, step ):\n    """Step {j}."""\n    return total + step\n\n' )
PYRZ
# L1 (2026-09-19): #18 counts the FULL legend's droppable clauses (confidence=/tail:/route= prose), so rz_run asks for the full legend.
rz_run(){ ( cd "$RZ" && "$BIN" corpus --for="widget ping box router" --detail=1 --token-budget="$1" --no-cache --legend=full ) >"$RZ/o.xml" 2>/dev/null; }
rz_est(){ grep -aoE 'est_tokens="[0-9]+"' "$RZ/o.xml" | head -1 | tr -dc '0-9'; }
rz_note(){ grep -acF '[legend clauses:' "$RZ/o.xml"; }
RZ_WIDE=1200
rz_run "$RZ_WIDE"; RZ_E="$( rz_est )"; RZ_WIDE_NOTE="$( rz_note )"
# THE CLAUSES THIS ARM COUNTS — all THREE of the droppable trio (CodeRabbit, PR #215). It counted two: the
# confidence reading and the tail reading, but not the route= reading the arm's own paragraph above names.
# A clause that is asserted in neither direction is not pinned, and the consequence is measured: with the
# route= reading removed from the binary (forIdRouteLegendParts returning an empty route part), the wide
# control still read clauses=2/2 and the whole arm reported PASS. Counted in all three runs now — the wide
# control, the probe, and the tight control that must have dropped every one of them — so a clause can only
# disappear by failing the wide run or by surviving the control.
RZ_CLAUSE_ROUTE='route= name-exact(X)|subtoken+body'
RZ_CLAUSES=0
grep -aqF 'confidence= derives from the ranked head' "$RZ/o.xml" && RZ_CLAUSES=$(( RZ_CLAUSES + 1 ))
grep -aqF 'tail: file-grain tail' "$RZ/o.xml"                    && RZ_CLAUSES=$(( RZ_CLAUSES + 1 ))
grep -aqF "$RZ_CLAUSE_ROUTE" "$RZ/o.xml"                         && RZ_CLAUSES=$(( RZ_CLAUSES + 1 ))
if [ -z "$RZ_E" ] || [ "$RZ_WIDE_NOTE" != "0" ] || [ "$RZ_CLAUSES" != "3" ]; then
    no "#18 rung zero: the wide control (--token-budget=$RZ_WIDE) does not carry its legend (est='${RZ_E:-unreadable}' dropped-note=$RZ_WIDE_NOTE clauses=$RZ_CLAUSES/3) — there is no price to probe against; re-anchor the fixture"
else
    RZ_PROBE=$(( RZ_E + 5 ))
    if [ "$RZ_PROBE" -ge "$RZ_WIDE" ]; then
        no "#18 rung zero: the probe budget $RZ_PROBE is not strictly below the wide control $RZ_WIDE — the two runs are the same run and the arm proves nothing; raise RZ_WIDE"
    else
        rz_run "$RZ_PROBE"; RZ_PE="$( rz_est )"; RZ_PN="$( rz_note )"; RZ_PB="$( bytes_of "$RZ/o.xml" )"
        RZ_PC=0
        grep -aqF 'confidence= derives from the ranked head' "$RZ/o.xml" && RZ_PC=$(( RZ_PC + 1 ))
        grep -aqF 'tail: file-grain tail' "$RZ/o.xml"                    && RZ_PC=$(( RZ_PC + 1 ))
        grep -aqF "$RZ_CLAUSE_ROUTE" "$RZ/o.xml"                         && RZ_PC=$(( RZ_PC + 1 ))
        # the ROOT's verdict only (read off the <ctx …> open tag): since lane/cutfix-bodies a <b over_ceiling="1"> marks
        # a --detail body whose first line alone exceeds the BODY allowance, which is not the root's est_tokens claim,
        # and a CDATA body can spell the literal too.
        RZ_PO=0; grep -aoE '^<ctx [^>]*>' "$RZ/o.xml" | grep -qF 'over_ceiling="1"' && RZ_PO=1
        if [ "$RZ_PN" = "0" ] && [ "$RZ_PC" = "3" ] && [ -n "$RZ_PE" ] && [ "$RZ_PE" -le "$RZ_PROBE" ] && [ "$RZ_PO" = "0" ]; then
            ok "#18 rung zero at --token-budget=$RZ_PROBE (5 tokens above the $RZ_E this document prices at): all three droppable clauses ride, est_tokens=$RZ_PE <= $RZ_PROBE, no over_ceiling=, $RZ_PB B"
        else
            no "#18 rung zero at --token-budget=$RZ_PROBE dropped a legend it could afford: dropped-note=$RZ_PN clauses=$RZ_PC/3 est_tokens=${RZ_PE:-unreadable} over_ceiling=$RZ_PO ($RZ_PB B) — the same document prices at $RZ_E at --token-budget=$RZ_WIDE, so it fits every budget >= $RZ_E"
        fi
    fi
    # …and the rung must still FIRE where the kept document genuinely does not fit. Without this, deleting
    # rung zero outright would turn the arm above green.
    RZ_CTRL=$(( RZ_E - 200 ))
    rz_run "$RZ_CTRL"; RZ_CN="$( rz_note )"; RZ_CE="$( rz_est )"
    # …and the tight control asserts the ABSENCE of the same three, route= included: a present-in-wide /
    # unchecked-in-tight assertion is the one-sided shape that let the missing clause through.
    RZ_CC=0
    grep -aqF 'confidence= derives from the ranked head' "$RZ/o.xml" && RZ_CC=$(( RZ_CC + 1 ))
    grep -aqF 'tail: file-grain tail' "$RZ/o.xml"                    && RZ_CC=$(( RZ_CC + 1 ))
    grep -aqF "$RZ_CLAUSE_ROUTE" "$RZ/o.xml"                         && RZ_CC=$(( RZ_CC + 1 ))
    if [ "$RZ_CN" != "0" ] && [ "$RZ_CC" = "0" ]; then
        ok "#18 rung zero control at --token-budget=$RZ_CTRL (200 under the $RZ_E the full document prices at): all three clauses dropped and the note says so (est_tokens=$RZ_CE) — the rung still fires when the drop is real"
    else
        no "#18 rung zero control at --token-budget=$RZ_CTRL: dropped-note=$RZ_CN clauses still riding=$RZ_CC/3 (est_tokens=${RZ_CE:-unreadable}) — rung zero no longer fires at all, so the arm above is green for the wrong reason"
    fi
fi

# ── #19 (CodeRabbit 4054594308, train 8): THE <hdr> ROWS ARE PRICED ─────────────────────────────────────
#
# THE DEFECT. --for's <hdr p= of=/> rows (R2-AF: the named file's decl/impl partner, printed first inside the
# root) were rendered AFTER finishForLensHeader had computed est_tokens= and over_ceiling=, and were in none of
# the budget sums — not est_tokens, not the ceiling ladder, not the residual the bodies/tail are sized from.
# One row is ~50 B on a short path, so every existing fixture stayed inside its band; a task naming SIX files
# under a long directory carried ~1.6 KB of rows its root never priced. MEASURED on the 71d27d07 binary with
# this arm's fixture: --signatures-only printed est_tokens=2616 over 8183 B (round(bytes/2.50) = 3273), and at
# --token-budget=1500 the root said est_tokens=1360 with no over_ceiling= over a 5043 B document (2017 tokens).
# WHAT IS ASSERTED: the #11 identities (markup at 2.50, bodies at 3.80), exact, on three shapes of a document
# that really carries six <hdr> rows — and under the explicit ceiling, est_tokens > budget iff over_ceiling="1".
# Git-less and relative (#18's discipline): nothing from the live repo, a fixed root=.
HX="$TMP/hdrprice"
mkdir -p "$HX"
python3 - "$HX" <<'PYHX'
import os, sys
d = os.path.join( sys.argv[ 1 ], "corpus", "very_long_subsystem_directory_name_alpha", "deeply_nested_component_module_path" )
os.makedirs( d, exist_ok=True )
for i in range( 6 ):
    s = f"widget_pinger_component_number_{i}_with_a_long_stem"
    open( os.path.join( d, s + ".h" ), "w" ).write( f"#pragma once\nint widgetPing{i}( int n );\n" )
    open( os.path.join( d, s + ".cc" ), "w" ).write( f'#include "{s}.h"\nint widgetPing{i}( int n ) {{ return n + {i}; }}\n' )
PYHX
HX_DIR="corpus/very_long_subsystem_directory_name_alpha/deeply_nested_component_module_path"
HX_TASK="fix widget ping in"
for i in 0 1 2 3 4 5; do HX_TASK="$HX_TASK $HX_DIR/widget_pinger_component_number_${i}_with_a_long_stem.cc"; done
hx_identity(){ python3 - "$1" <<'PYHXI'
import sys, re
d = open( sys.argv[1], 'rb' ).read()
m = re.search( rb'est_tokens="(\d+)"', d )
if not m: sys.exit( 2 )
est = int( m.group( 1 ) )
a = d.find( b'<bodies ' ); b = d.find( b'</bodies>' )
span = ( b + 9 - a ) if a >= 0 and b >= 0 else 0
expected = int( ( len( d ) - span ) / 2.50 + 0.5 ) + ( int( span / 3.80 + 0.5 ) if span else 0 )
print( f"{len(d)} {span} {est} {expected} hdr={d.count(b'<hdr ')}" )
sys.exit( 0 if est == expected and d.count( b'<hdr ' ) == 6 else 1 )
PYHXI
}
for hx_mode in "--signatures-only" "" "--token-budget=1500"; do
    ( cd "$HX" && "$BIN" corpus --for="$HX_TASK" $hx_mode --no-cache ) >"$HX/o.xml" 2>/dev/null
    hx_label="${hx_mode:-default}"
    if hx_out="$( hx_identity "$HX/o.xml" )"; then
        ok "#19 <hdr> rows priced ($hx_label): est_tokens matches markup@2.50 + bodies@3.80 with six rows present — bytes/span/est/expected = $hx_out"
    else
        hx_out="$( hx_identity "$HX/o.xml" 2>/dev/null || true )"
        no "#19 <hdr> rows unpriced ($hx_label): bytes/span/est/expected = ${hx_out:-unreadable} (six <hdr> rows required; a gap of ~bytes-of-rows/2.50 is the defect)"
    fi
    if [ "$hx_mode" = "--token-budget=1500" ]; then
        HX_E="$( grep -aoE 'est_tokens="[0-9]+"' "$HX/o.xml" | head -1 | tr -dc '0-9' )"
        HX_O=0; grep -aqF 'over_ceiling="1"' "$HX/o.xml" && HX_O=1
        if [ -n "$HX_E" ] && { { [ "$HX_E" -gt 1500 ] && [ "$HX_O" = 1 ]; } || { [ "$HX_E" -le 1500 ] && [ "$HX_O" = 0 ]; }; }; then
            ok "#19 --token-budget=1500: over_ceiling=$HX_O agrees with est_tokens=$HX_E (the ceiling verdict sees the <hdr> rows)"
        else
            no "#19 --token-budget=1500: over_ceiling=$HX_O disagrees with est_tokens=${HX_E:-unreadable} — the ceiling verdict was made without the <hdr> rows"
        fi
    fi
done

# …and the MCP `for` twin (mcpverbs.h forTaskText) on the same task: it prices the FINISHED document
# (priceForTaskRoot), so it already counted the rows — pinned here so the two surfaces cannot drift apart.
python3 - "$HX_TASK" "$HX/corpus" >"$HX/mcp.in" <<'PYHXM'
import json, sys
print( json.dumps( { "jsonrpc": "2.0", "id": 1, "method": "initialize" } ) )
print( json.dumps( { "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                     "params": { "name": "for", "arguments": { "path": sys.argv[2], "task": sys.argv[1] } } } ) )
PYHXM
"$BIN" --mcp <"$HX/mcp.in" >"$HX/mcp.json" 2>/dev/null
HX_M="$( python3 - "$HX/mcp.json" <<'PYHXR'
import json, re, sys
try:
    t = json.loads( [ l for l in open( sys.argv[1] ) if l.strip() ][-1] )["result"]["content"][0]["text"].encode()
    e = int( re.search( rb'est_tokens="(\d+)"', t ).group( 1 ) )
except Exception:
    print( "unreadable" ); sys.exit( 0 )
print( f"{len(t)} {e} {int( len( t ) / 2.50 + 0.5 )} hdr={t.count( b'<hdr ' )}" )
PYHXR
)"
set -- $HX_M
if [ "$#" = 4 ] && [ "$2" = "$3" ] && [ "$4" = "hdr=6" ]; then
    ok "#19 MCP for twin: est_tokens = round(bytes/2.50) with six <hdr> rows — bytes/est/expected = $HX_M"
else
    no "#19 MCP for twin: bytes/est/expected = ${HX_M:-unreadable} (six <hdr> rows required and priced)"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

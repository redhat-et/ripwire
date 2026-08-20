#!/usr/bin/env bash
# packtaskcheck.sh — gate for L4 the budget-shared task bundle (B11):
# `--pack-task="TASK"` — ONE call assembling the 3-5 call orientation dance (ranking → bodies → 1-hop callers
# → field notes → tests_to_run) under ONE deterministic byte budget, in a FIXED section order, with a header
# that reports EVERY truncation (no silent caps).
#
# Covers, per the plan's gate spec:
#   • refuse loudly WITHOUT a task string (bare --pack-task and --pack-task=)
#   • the 5 sections appear in the FIXED byte order  ranking < bodies < callers < notes < tests
#   • the field note on a top-ranked symbol surfaces in section 4; the reaching test surfaces in section 5;
#     a 1-hop caller surfaces in section 3 (a real fixture graph exercises all three)
#   • measured output BYTES <= ceiling × the documented tolerance (ceiling = tokens × kMinBytesPerToken=2.36),
#     across several --token-budget values, on the real src/ tree (exercises the trim ladder)
#   • a TINY budget degrades to ranking-only WITH the truncation note (bodies/callers reported "omitted")
#   • determinism ×3, xmllint (G4) on every emission
#   • --for is UNPERTURBED by the feature: the pack-task ranking is the SAME ranking --for emits (top-file
#     parity) — pack-task reuses computeLensRanking, it does not fork it. (Full --for byte-identity vs the
#     pre-feature binary is additionally guarded by forlenscheck/golden in the full regression.)
#   • HOSTILE note text (XML metachars + a "]]>" CDATA-close) stays xmllint-clean in the bundle
#
# Operates on a private temp git repo + the repo's own src/ (read-only). Needs git + xmllint.
# Usage:  RIPWIRE_BIN=build/ripwire bash test/packtaskcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # make BIN absolute BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "git required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "packtaskcheck: BIN=$BIN"

# ── the documented budget ceiling: tokens × kMinBytesPerToken (the densest byte/token rate) × a small
#    tolerance for the single-entry overshoot packBodies can add (it emits its first body whole). ───────────
KMINBPT=2.36
TOL=1.15
ceiling_bytes(){ awk "BEGIN{printf \"%d\", $1 * $KMINBPT * $TOL}"; }
byte_off(){ grep -boF -- "$2" "$1" 2>/dev/null | head -1 | cut -d: -f1; }   # first byte offset of a literal, or empty

# ── 1) refuse loudly WITHOUT a task string ────────────────────────────────────────────────────────────────
for arg in "--pack-task" "--pack-task="; do
    ERR="$( "$BIN" "$ROOT/src" --no-cache "$arg" 2>&1 >/dev/null )"
    RC="$( "$BIN" "$ROOT/src" --no-cache "$arg" >/dev/null 2>&1; echo $? )"
    { [ "$RC" -ne 0 ] && printf '%s' "$ERR" | grep -qi 'task string'; } \
        && ok "refuses loudly without a task string ($arg → exit $RC)" \
        || { no "expected a loud refusal for '$arg'"; printf '  rc=%s err=%s\n' "$RC" "$ERR"; }
done

# ── 2) the fixture: a scoped method graph so callers/notes/tests all have something to surface. Sized so
#    R2's distance tiers each get a genuine, distinct member: kPackTaskBodyCandidates caps d0 (the anchors)
#    at 6, so the 6 decoys below fill that cap, pushing run_budget_tests OUT of d0 despite calling an anchor
#    (applyBudget) — it lands at d1 instead. decoyBudgetThree..Six + unrelatedHelper have no call edge to any
#    anchor, so they land at d2+ (the <far> name-only tier). auxiliaryInvoker is a 2nd, weaker caller of the
#    parseBudget anchor that DOES make the d0 cut (graph+lexical score both favor it) — its presence proves
#    d0 membership is about the FINAL rank, not merely "calls an anchor".
WORK="$TMP/repo"; mkdir -p "$WORK/src" "$WORK/test"
cat > "$WORK/src/pipeline.cpp" <<'EOF'
struct BudgetPlanner {
    int parseBudget( int raw ) { return raw > 0 ? raw : 6000; }
    int applyBudget( int raw ) { return parseBudget( raw ) * 2; }
};
int decoyBudgetOne( int y )   { return y + 1; }
int decoyBudgetTwo( int y )   { return y + 2; }
int decoyBudgetThree( int y ) { return y + 3; }
int decoyBudgetFour( int y )  { return y + 4; }
int decoyBudgetFive( int y )  { return y + 5; }
int decoyBudgetSix( int y )   { return y + 6; }
int unrelatedHelper( int y )  { return y - 1; }
int auxiliaryInvoker()        { BudgetPlanner p; return p.parseBudget( 7 ); }
EOF
cat > "$WORK/test/test_budget.cpp" <<'EOF'
#include "../src/pipeline.cpp"
int run_budget_tests() { BudgetPlanner p; return p.applyBudget( 10 ); }
EOF
( cd "$WORK" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm init >/dev/null 2>&1 )
runw(){ ( cd "$WORK" && "$BIN" . --no-cache "$@" 2>/dev/null ); }

# discover the scoped canonical id EXACTLY as serialization spells it (id= is emitted only when scoped)
PID="$( runw | grep -oE 'id="[^"]*BudgetPlanner::parseBudget"' | head -1 | sed -E 's/id="([^"]*)"/\1/' )"
[ -n "$PID" ] && ok "discovered scoped canonical id: $PID" || no "could not discover BudgetPlanner::parseBudget id"
# D5: --note-add normalizes a target's path component to ROOT-RELATIVE on write (strips the crawl's leading
# "./"), and --pack-task's notes section keys on that same normalized form — see notescheck.sh for the full
# root-relative-notes gate.
NORM_PID="${PID#./}"

runw --note-add="$PID: watch integer overflow when raw is INT_MAX" >/dev/null
GIT_DATE="$( cd "$WORK" && git log -1 --format=%cs HEAD )"

BUN="$TMP/bundle.xml"
runw --pack-task="parse budget planner decoy" > "$BUN"

# section presence
for tag in "<sigs" "<bodies " "<callers " "<notes " "<tests "; do
    grep -qF -- "$tag" "$BUN" && ok "section present: ${tag}…" || no "section missing: ${tag}"
done

# section ORDER (fixed): ranking < bodies < callers < notes < tests, by first byte offset
p_sigs="$(   byte_off "$BUN" "<sigs" )"
p_bodies="$( byte_off "$BUN" "<bodies " )"
p_callers="$(byte_off "$BUN" "<callers " )"
p_notes="$(  byte_off "$BUN" "<notes " )"
p_tests="$(  byte_off "$BUN" "<tests " )"
if [ -n "$p_sigs" ] && [ -n "$p_bodies" ] && [ -n "$p_callers" ] && [ -n "$p_notes" ] && [ -n "$p_tests" ] \
   && [ "$p_sigs" -lt "$p_bodies" ] && [ "$p_bodies" -lt "$p_callers" ] \
   && [ "$p_callers" -lt "$p_notes" ] && [ "$p_notes" -lt "$p_tests" ]; then
    ok "sections emitted in the FIXED order ranking < bodies < callers < notes < tests"
else
    no "section order is wrong (sigs=$p_sigs bodies=$p_bodies callers=$p_callers notes=$p_notes tests=$p_tests)"
fi

# section 3: a 1-hop caller of the top symbols surfaces (run_budget_tests calls applyBudget, an anchor,
# but the 6-decoy fixture keeps run_budget_tests itself OUT of the d0/bodies cap — so it's a genuine d1)
grep -oE '<callers[^>]*>.*</callers>' "$BUN" | grep -qF 'n="run_budget_tests"' \
    && ok "section 3 (callers) surfaces the 1-hop caller run_budget_tests" || no "callers section did not surface run_budget_tests"

# ── R2: distance-aware detail allocation ──────────────────────────────────────────────────────────────────
# d0 (anchors): parseBudget/BudgetPlanner get a FULL BODY (section 2) — the deepest tier.
# NOTE: <bodies> embeds raw multi-line source verbatim (CDATA) — a plain single-line grep -oE can't bridge
# an embedded newline, so flatten a throwaway copy of the bundle to one line for these block extractions.
FLAT="$( tr '\n' ' ' < "$BUN" )"
CALLERS_BLOCK="$( printf '%s' "$FLAT" | grep -oE '<callers[^>]*>.*</callers>' )"
BODIES_BLOCK="$(  printf '%s' "$FLAT" | grep -oE '<bodies [^>]*>.*</bodies>'   )"
FAR_BLOCK="$(     printf '%s' "$FLAT" | grep -oE '<far[^>]*>.*</far>'          )"
printf '%s' "$BODIES_BLOCK" | grep -qF 'n="parseBudget"' \
    && ok "R2 d0: parseBudget (an anchor) has a FULL BODY" || no "R2 d0: parseBudget missing from <bodies>"

# d1 (run_budget_tests, a 1-hop caller of the applyBudget anchor): a SIGNATURE (rel= + real signature text),
# and — the "no d1 bodies" half of the contract — it must NEVER also appear in <bodies>.
printf '%s' "$CALLERS_BLOCK" | grep -qE '<s[^>]*n="run_budget_tests"[^>]*rel="caller"[^>]*>int run_budget_tests\(\)</s>' \
    && ok "R2 d1: run_budget_tests carries a real one-line SIGNATURE + rel=\"caller\" (not a bare name row)" \
    || no "R2 d1: run_budget_tests missing its signature/rel in <callers>"
printf '%s' "$BODIES_BLOCK" | grep -qF 'n="run_budget_tests"' \
    && no "R2 REGRESSION: run_budget_tests (d1) got a FULL BODY too — d1 must stay signature-only" \
    || ok "R2 d1: run_budget_tests never gets a body, even though the budget could afford one"

# d2+ (decoyBudgetSix / unrelatedHelper: no call edge to any anchor): a bare NAME-ONLY row in <far>, nested
# just inside </sigs> (still section 1, not a 6th top-level section) — no signature, no doc, no body anywhere.
printf '%s' "$FAR_BLOCK" | grep -qE '<s t="fn" n="unrelatedHelper" p="[^"]*"/>' \
    && ok "R2 d2+: unrelatedHelper is a bare NAME-ONLY row in <far>" || no "R2 d2+: unrelatedHelper missing/not name-only in <far>"
printf '%s' "$BODIES_BLOCK"  | grep -qF 'n="unrelatedHelper"' && no "R2 REGRESSION: unrelatedHelper (d2+) got a body"  || ok "R2 d2+: unrelatedHelper has no body"
printf '%s' "$CALLERS_BLOCK" | grep -qF 'n="unrelatedHelper"' && no "R2 REGRESSION: unrelatedHelper (d2+) got a signature row in <callers>" || ok "R2 d2+: unrelatedHelper has no signature row"
grep -qF '<far ' "$BUN" && grep -oE '<sigs.*</sigs>' "$BUN" | grep -qF '<far ' \
    && ok "R2: <far> nests INSIDE <sigs> (section 1), not a 6th top-level section" || no "R2: <far> is not nested inside <sigs>"

# section 4: the field note surfaces as a dated CDATA <note> on the top symbol
grep -oE '<notes[^>]*>.*</notes>' "$BUN" \
    | grep -qF '<note d="'"$GIT_DATE"'"><![CDATA[watch integer overflow when raw is INT_MAX]]></note>' \
    && ok "section 4 (notes) surfaces the field note (dated, CDATA-wrapped)" || no "notes section did not surface the field note"
grep -oE '<notes[^>]*>.*</notes>' "$BUN" | grep -qF 'id="'"$NORM_PID"'"' \
    && ok "section 4 targets the D5-normalized (root-relative) scoped canonical id" || no "notes section target id mismatch"

# section 5: the reaching test file surfaces (test_budget.cpp reaches applyBudget/parseBudget)
grep -oE '<tests[^>]*>.*</tests>' "$BUN" | grep -qF 'test/test_budget.cpp' \
    && ok "section 5 (tests) surfaces the reaching test file" || no "tests section did not surface the reaching test"

# xmllint on the fixture bundle
xmllint --noout "$BUN" 2>/dev/null && ok "fixture bundle is xmllint-clean (G4)" || no "fixture bundle is not well-formed"

# the header names every truncation (no silent caps): it must carry the per-section report line
grep -q 'sections in FIXED order ranking > bodies > callers > notes > tests' "$BUN" \
    && grep -qE 'ranking: (full|capped) \| bodies: .* \| callers: .* \| notes: .* \| tests: ' "$BUN" \
    && ok "header carries the per-section truncation report (no silent caps)" || no "header truncation report missing/incomplete"

# determinism ×3 (fixed notes file + fixed HEAD)
D1="$( runw --pack-task="parse budget planner decoy" )"
D2="$( runw --pack-task="parse budget planner decoy" )"
D3="$( runw --pack-task="parse budget planner decoy" )"
{ [ "$D1" = "$D2" ] && [ "$D2" = "$D3" ]; } && ok "bundle is deterministic (byte-identical ×3)" || no "bundle is non-deterministic"

# ── 3) TINY budget → ranking-only, <bodies> present with shown="0" (R9 fix, W3-S 2026-08-19) ───────────────
# Before the fix, a budget too tight for the bodies section left bodiesStr empty and the WHOLE <bodies>
# element absent — "a zero means none found, never none exists" (CONTRIBUTING #3) says that is a lie by
# omission when real candidates existed (total=6 here). packTaskListSection's <callers>/<tests> siblings
# still degrade to fully absent (that is THEIR own, separately-scoped defect — not this item), so this arm
# only tightens the <bodies> assertion, from "absent" to "present with shown=0/capped=1/the true total".
TINY="$TMP/tiny.xml"
"$BIN" "$ROOT/src" --no-cache --pack-task="serialize signatures budget" --token-budget=50 > "$TINY" 2>/dev/null
if grep -qF '<sigs' "$TINY" \
   && grep -qE '<bodies shown="0" total="[1-9][0-9]*" capped="1"></bodies>' "$TINY" \
   && ! grep -qF '<callers ' "$TINY" && ! grep -qF '<tests ' "$TINY" \
   && grep -qE 'bodies: kept 0 of [1-9]' "$TINY"; then
    ok "tiny budget: <sigs> survives, <bodies shown=\"0\"> is PRESENT (not absent), other sections omitted"
else
    no "tiny-budget degradation wrong (expected <sigs> + <bodies shown=\"0\" total=\"N\" capped=\"1\">)"
    head -c 400 "$TINY"; echo
fi
xmllint --noout "$TINY" 2>/dev/null && ok "tiny-budget bundle is xmllint-clean" || no "tiny-budget bundle is not well-formed"

# ── 4) budget ceiling respected across several --token-budget values (real src/ tree, exercises trimming) ──
for tb in 2000 4000 8000; do
    OUT="$TMP/b$tb.xml"
    "$BIN" "$ROOT/src" --no-cache --pack-task="serialize signatures budget payload trim" --token-budget=$tb > "$OUT" 2>/dev/null
    bytes="$( wc -c < "$OUT" | tr -d ' ' )"
    ceil="$( ceiling_bytes "$tb" )"
    { [ "$bytes" -le "$ceil" ]; } \
        && ok "budget respected: --token-budget=$tb → $bytes B <= ceiling×tol=$ceil B" \
        || no "budget EXCEEDED: --token-budget=$tb → $bytes B > ceiling×tol=$ceil B"
    xmllint --noout "$OUT" 2>/dev/null || no "bundle at --token-budget=$tb is not well-formed"
done

# default (6K) budget is xmllint-clean + within its own ceiling
DEF="$TMP/def.xml"
"$BIN" "$ROOT/src" --no-cache --pack-task="serialize signatures budget payload trim" > "$DEF" 2>/dev/null
defbytes="$( wc -c < "$DEF" | tr -d ' ' )"; defceil="$( ceiling_bytes 6000 )"
{ [ "$defbytes" -le "$defceil" ]; } && ok "default 6K-token budget within ceiling ($defbytes <= $defceil)" || no "default budget exceeded ceiling ($defbytes > $defceil)"
xmllint --noout "$DEF" 2>/dev/null && ok "default bundle is xmllint-clean" || no "default bundle is not well-formed"

# ── 5) --for is UNPERTURBED: pack-task's ranking is the SAME ranking --for emits (shared computeLensRanking) ─
#
# THE ARM USED TO BE BLIND (PR #1, run 30732976779, asan (ubuntu-24.04)). It piped both runs straight into
# grep with `2>/dev/null`, so it kept ONE bit — the extracted path — and threw away the exit code, stderr,
# and the emitted bytes. CI reported exactly `for= pack=…/src/serialize.h` and nothing else, which is the
# SAME observation for at least four different causes:
#   (a) --for aborted (a sanitizer report / a VERIFY panic) and wrote nothing — rc and stderr both discarded;
#   (b) --for emitted an EMPTY payload, `<sigs capped="1"></sigs>` (serialize.h's ladder drops every <f>
#       once sigsBudget clamps toward 1), which is a real product defect and a real thing to see;
#   (c) the <sigs>/<f> shape changed and only the EXTRACTOR broke — a gate bug, not a product bug;
#   (d) the ranking genuinely diverged — the only cause the message actually named.
# Not reproducible on macos-14/arm64 or on ubuntu-24.04/aarch64 under the identical ASan stack and the
# identical env (checked at this commit, in a clean clone at the CI path), so the next run has to identify
# itself. Keep BOTH runs' rc, stderr and bytes, and report whichever of (a)-(d) the evidence shows.
Q="serialize signatures budget payload"
run_lens(){                                    # $1 = tag, $2… = the flags; sets rc_<tag>, and leaves $TMP/<tag>.{xml,err}
    local tag="$1"; shift
    "$BIN" "$ROOT/src" --no-cache "$@" >"$TMP/$tag.xml" 2>"$TMP/$tag.err"
    printf '%s' "$?"
}
top_file(){ grep -oE '<sigs[^>]*><f p="[^"]*"' "$1" | head -1 | sed -E 's/.*<f p="([^"]*)"/\1/'; }
lens_evidence(){                               # the four-way discriminator, printed only on failure
    local tag="$1" rc="$2"
    printf '    [%s] rc=%s  bytes=%s\n' "$tag" "$rc" "$( wc -c <"$TMP/$tag.xml" | tr -d ' ' )"
    [ -s "$TMP/$tag.err" ] && { printf '    [%s] stderr:\n' "$tag"; sed -n '1,12p' "$TMP/$tag.err" | sed "s/^/      /"; }
    printf '    [%s] sigs region: %s\n' "$tag" "$( grep -oE '<sigs[^>]*>.{0,120}' "$TMP/$tag.xml" | head -1 )"
    return 0
}
FOR_RC="$(  run_lens forlens  --for="$Q" )"
PACK_RC="$( run_lens packlens --pack-task="$Q" )"
FOR_TOPF="$(  top_file "$TMP/forlens.xml" )"
PACK_TOPF="$( top_file "$TMP/packlens.xml" )"
if [ "$FOR_RC" -ne 0 ] || [ "$PACK_RC" -ne 0 ]; then
    # cause (a): name the crash instead of mis-reporting it as a ranking divergence
    no "--for/--pack-task did not exit 0 (for rc=$FOR_RC pack rc=$PACK_RC) — the ranking comparison below is moot"
    lens_evidence forlens "$FOR_RC"; lens_evidence packlens "$PACK_RC"
elif [ -z "$FOR_TOPF" ] || [ -z "$PACK_TOPF" ]; then
    # causes (b)/(c): both exited 0, so the payload really is empty or the shape really did move
    no "no top file extractable (for='$FOR_TOPF' pack='$PACK_TOPF') — empty <sigs> payload, or the <sigs>/<f> shape moved"
    lens_evidence forlens "$FOR_RC"; lens_evidence packlens "$PACK_RC"
elif [ "$FOR_TOPF" = "$PACK_TOPF" ]; then
    ok "--for ranking is unperturbed: pack-task's top file == --for's top file ($FOR_TOPF)"
else
    # cause (d): the real assertion, now the only thing this message can mean
    no "pack-task ranking diverges from --for (for=$FOR_TOPF pack=$PACK_TOPF)"
fi
# --for is itself deterministic + well-formed with the feature compiled in. NOTE: two EMPTY outputs are
# byte-identical, so this arm passed vacuously in the run above — require non-empty before comparing.
F1="$( "$BIN" "$ROOT/src" --no-cache --for="$Q" 2>/dev/null )"; F2="$( "$BIN" "$ROOT/src" --no-cache --for="$Q" 2>/dev/null )"
{ [ -n "$F1" ] && [ "$F1" = "$F2" ]; } && ok "--for stays deterministic with --pack-task compiled in" \
    || no "--for non-deterministic or empty (bytes: ${#F1} vs ${#F2})"

# ── 6) hostile note text stays xmllint-clean in the bundle ────────────────────────────────────────────────
runw --note-add="$PID: danger ]]> <script>alpha & beta --> end" >/dev/null
runw --pack-task="parse budget planner decoy" | xmllint --noout - 2>/dev/null \
    && ok "hostile note text (incl. ]]>) keeps the bundle xmllint-clean" || no "hostile note text broke bundle well-formedness"

# ── 7) F4 — a --token-budget=1 ranking-section share must NOT invert into an unlimited section: cap(frac) can
#    floor a tiny bundleBudget × 0.45 to 0, and 0 means "no cap" to packSignatures downstream (its own "0 = no
#    budget" convention) — so an UNFLOORED cap() at budget=1 produced a BIGGER bundle than budget=2. Gate:
#    budget=1 output <= budget=2 output, in bytes, on the real src/ tree (exercises the trim ladder for real).
B1="$TMP/budget1.xml"; B2="$TMP/budget2.xml"
"$BIN" "$ROOT/src" --no-cache --pack-task="serialize signatures budget payload trim" --token-budget=1 > "$B1" 2>/dev/null
"$BIN" "$ROOT/src" --no-cache --pack-task="serialize signatures budget payload trim" --token-budget=2 > "$B2" 2>/dev/null
b1bytes="$( wc -c < "$B1" | tr -d ' ' )"; b2bytes="$( wc -c < "$B2" | tr -d ' ' )"
{ [ "$b1bytes" -le "$b2bytes" ]; } \
    && ok "F4: --token-budget=1 ($b1bytes B) <= --token-budget=2 ($b2bytes B) — no 0-floor inversion" \
    || no "F4 REGRESSION: --token-budget=1 ($b1bytes B) > --token-budget=2 ($b2bytes B) — the 0-floor inversion is back"
xmllint --noout "$B1" 2>/dev/null && ok "F4: --token-budget=1 bundle is xmllint-clean" || no "F4: --token-budget=1 bundle is not well-formed"
xmllint --noout "$B2" 2>/dev/null && ok "F4: --token-budget=2 bundle is xmllint-clean" || no "F4: --token-budget=2 bundle is not well-formed"

# ── 8) F5 — --token-budget beyond INT_MAX must not go negative / crash (UBSan aborts on the size_t->int
#    narrowing this used to do; release wrapped negative and read as effectively unlimited). Sanity-only: the
#    binary must still exit cleanly with a well-formed, non-huge bundle (a real "ceiling" ceiling is meaningless
#    at this scale — the point is no negative/garbage header and no crash).
HUGE="$TMP/huge.xml"
"$BIN" "$ROOT/src" --no-cache --pack-task="serialize signatures budget payload trim" --token-budget=3000000000 > "$HUGE" 2>/dev/null
HUGE_RC=$?
{ [ "$HUGE_RC" = 0 ]; } && ok "F5: --token-budget=3000000000 exits cleanly (rc=$HUGE_RC, no UBSan abort)" \
    || no "F5: --token-budget=3000000000 exited abnormally (rc=$HUGE_RC)"
grep -qE 'budget="-|target, ceiling -' "$HUGE" \
    && no "F5 REGRESSION: header carries a negative budget/ceiling value" \
    || ok "F5: header carries no negative budget/ceiling value"
xmllint --noout "$HUGE" 2>/dev/null && ok "F5: --token-budget=3000000000 bundle is xmllint-clean" || no "F5: --token-budget=3000000000 bundle is not well-formed"

echo
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }

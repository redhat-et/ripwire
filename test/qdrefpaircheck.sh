#!/usr/bin/env bash
# qdrefpaircheck.sh — R-I: `--quality-delta=A..B`, the WAVE-level form.
#
# WHY THIS VERB EXISTS. Every per-lane quality check compares a lane against the lane's own baseline, so a
# regression the WAVE introduced — one that no single lane owns — is invisible to all of them. The 2026-08-15
# six-repo harvest round shipped 18 gating regressions to its merge head for exactly that reason, and the
# verifier only found them by hand-building an overlay: a scratch worktree at the baseline sha, a pinned
# `--quality-baseline`, a `git checkout <head> -- .` on top, then a working-tree `--quality-delta`. This flag
# form makes that a first-class question.
#
# ── THE ORACLE, AND WHY IT IS INDEPENDENT ────────────────────────────────────────────────────────────────
# Arm (E) does NOT trust a number this lane wrote down. It RE-RUNS the hand-built overlay recipe above, live,
# with the same binary, and requires the new code path to agree with it row for row. The overlay reaches its
# answer through a completely different mechanism — a real checked-out git worktree, a serialized
# `.ripwire_quality_baseline` sidecar round-tripped through disk, and the ordinary working-tree comparison —
# and shares no code with the ref-pair path beyond computeDelta itself. It also cannot go stale, because it
# is recomputed on every run rather than pinned as a literal.
#
# Two literals ARE pinned, and only as a cross-check that the two shas still name the round the comment
# above describes: the harvest round record (PLAN_HARVEST_REPORTS_2026-08-15/ROUTING_LEDGER.md) states
# `--dmm=4b9386c..ba380b5` = 0.530 and 18 gating rows. Both reproduce.
#
# ── THE ONE DEFENSIBLE DISCREPANCY: 18 vs 11 ─────────────────────────────────────────────────────────────
# The overlay reports 18 gating rows; the ref-pair form reports 11. The difference is exactly the 7
# short-horizon-churn rows, and it is a property of the QUESTION, not a bug:
#
#   The churn kind needs git history AT THE TREE BEING JUDGED — it counts commits per file in a recent
#   window and compares body hashes against a window-reference commit. The overlay's judged tree is a real
#   worktree with a real .git, so churn evaluates there (against HEAD = the BASE commit, which is itself a
#   quirk of the overlay: the window is anchored at the wrong end of the range). The ref-pair form
#   materializes BOTH trees out of the object store into temp dirs that are not repositories at all, so the
#   kind cannot be computed and the report says so — `churn="unavailable"` on the root element, which arm
#   (A) asserts is present and arm (E) asserts is TRUE (zero churn rows emitted).
#
# So the gate pins the ref-pair form to the overlay's rows MINUS the churn kind, and separately pins that
# churn is disclosed-and-empty. Pinning "11" alone would be a number with no argument attached; pinning the
# row SET, derived live from the other method, is the check that can actually fail for the right reason.
#
# RED BEFORE GREEN: run against a binary built before this lane's feature commit, arms (A)-(F) fail at the
# first step — `--quality-delta=...` is rejected as an unknown flag (verified on the round baseline
# ab59ca8 binary: "ripwire: unknown flag '--quality-delta=4b9386c..ba380b5'").

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"
WT=""
cleanup(){ [ -n "$WT" ] && git -C "$ROOT" worktree remove --force "$WT" >/dev/null 2>&1; rm -rf "$TMP"; git -C "$ROOT" worktree prune >/dev/null 2>&1; }
trap cleanup EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN"; exit 2; }

echo "qdrefpaircheck: BIN=$BIN"

# root attribute of the <quality-delta> element, and one attribute out of it
hdr(){ grep -o '<quality-delta [^>]*>' "$1" | head -1; }
attr(){ hdr "$1" | grep -o " $2=\"[^\"]*\"" | head -1 | sed -E "s/.*=\"([^\"]*)\"/\1/"; }
# the gating rows as a sorted, comparable set: kind|sym
gatingRows(){ sed 's/<r /\n<r /g' "$1" | grep '^<r ' | grep 'gating="1"' \
                | sed -E 's/.*kind="([^"]*)".*sym="([^"]*)".*/\1|\2/' | LC_ALL=C sort; }

# ── (A) synthetic repo: a KNOWN regression between two commits ────────────────────────────────────────────
# Independent of ripwire's own history shape, so the contract is gated even in a checkout where arm (E)
# cannot run at all.
R="$TMP/repo"; mkdir -p "$R"
cd "$R"; git init -q .; git config user.email t@t; git config user.name t
cat > lib.h <<'EOF'
#pragma once
inline int tangle( int a )
{
    return a + 1;
}
EOF
git add lib.h; git commit -qm base
A_SHA="$( git rev-parse HEAD )"

# commit B makes tangle markedly more complex AND markedly longer — a complexity + verbosity regression on a
# PREEXISTING symbol, i.e. the gating kind, not the never-gating new-symbol kind.
cat > lib.h <<'EOF'
#pragma once
inline int tangle( int a )
{
    int t = 0;
    for( int i = 0; i < a; ++i )
    {
        if( i % 2 == 0 )       { if( i % 3 == 0 ) { t += i * 2; } else { t += i; } }
        else if( i % 5 == 0 )  { if( i % 7 == 0 ) { t -= i * 2; } else { t -= i; } }
        else if( i % 11 == 0 ) { if( i > 50 )     { t += 4; }     else { t += 1; } }
        else if( i % 13 == 0 ) { if( i > 60 )     { t -= 4; }     else { t -= 1; } }
        else if( i % 17 == 0 ) { if( i > 70 )     { t += 6; }     else { t += 3; } }
        else if( i % 19 == 0 ) { if( i > 80 )     { t -= 6; }     else { t -= 3; } }
        else                   { if( i > 90 )     { t += 9; }     else { t += 7; } }
    }
    return t;
}
EOF
git add lib.h; git commit -qm worse
B_SHA="$( git rev-parse HEAD )"

"$BIN" . "--quality-delta=$A_SHA..$B_SHA" >"$TMP/syn.xml" 2>"$TMP/syn.err"; synRc=$?
[ "$synRc" = 2 ] && ok "(A) synthetic A..B exits 2 on a gating regression" \
                 || no "(A) synthetic A..B exit was $synRc, expected 2"
[ "$( attr "$TMP/syn.xml" gating )" -ge 1 ] 2>/dev/null \
    && ok "(A) synthetic A..B reports the planted regression (gating=$( attr "$TMP/syn.xml" gating ))" \
    || { no "(A) synthetic A..B reported no gating row"; hdr "$TMP/syn.xml"; }
gatingRows "$TMP/syn.xml" | grep -q '^complexity|' \
    && ok "(A) the planted complexity regression is named" \
    || { no "(A) no complexity row in the synthetic delta"; gatingRows "$TMP/syn.xml"; }

# disclosure on the root element: which floor, the two RESOLVED shas, and the unmeasurable kind
[ "$( attr "$TMP/syn.xml" baseline )" = "ref-pair" ] \
    && ok "(A) baseline= names the ref-pair floor" \
    || no "(A) baseline= was '$( attr "$TMP/syn.xml" baseline )', expected ref-pair"
[ "$( attr "$TMP/syn.xml" base_ref )" = "$A_SHA" ] && [ "$( attr "$TMP/syn.xml" target_ref )" = "$B_SHA" ] \
    && ok "(A) base_ref=/target_ref= disclose both RESOLVED shas" \
    || no "(A) ref disclosure wrong: base_ref=$( attr "$TMP/syn.xml" base_ref ) target_ref=$( attr "$TMP/syn.xml" target_ref )"
[ "$( attr "$TMP/syn.xml" churn )" = "unavailable" ] \
    && ok "(A) churn= discloses the one kind this form cannot measure" \
    || no "(A) churn= was '$( attr "$TMP/syn.xml" churn )', expected unavailable"
hdr "$TMP/syn.xml" | grep -q ' at="' \
    && no "(A) at= must be OMITTED for a ref pair (the two refs are the anchor)" \
    || ok "(A) at= omitted, never faked, for a ref pair"

# G4 well-formedness, and determinism on the exact same question
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/syn.xml" 2>/dev/null && ok "(A) output is well-formed XML" || no "(A) xmllint rejected the output"
else
    skip "(A) xmllint not installed"
fi
"$BIN" . "--quality-delta=$A_SHA..$B_SHA" >"$TMP/syn2.xml" 2>/dev/null
cmp -s "$TMP/syn.xml" "$TMP/syn2.xml" && ok "(A) two runs are byte-identical (determinism)" \
                                      || { no "(A) DETERMINISM: two runs of the same A..B differ"; diff "$TMP/syn.xml" "$TMP/syn2.xml" | head -6; }
# the materialized temp roots carry a pid — none of it may reach stdout, or "byte-identical" is luck
grep -q 'qdpair' "$TMP/syn.xml" \
    && { no "(A) a materialized temp path leaked into stdout"; grep -o '[^"]*qdpair[^"]*' "$TMP/syn.xml" | head -2; } \
    || ok "(A) no materialized temp path in the output"

# ── (B) A==B is a legal, empty, exit-0 comparison ─────────────────────────────────────────────────────────
"$BIN" . "--quality-delta=$B_SHA..$B_SHA" >"$TMP/same.xml" 2>/dev/null; sameRc=$?
[ "$sameRc" = 0 ] && ok "(B) A==B exits 0" || no "(B) A==B exit was $sameRc, expected 0"
[ "$( attr "$TMP/same.xml" regressions )" = "0" ] && [ "$( attr "$TMP/same.xml" gating )" = "0" ] \
    && ok "(B) A==B is an empty delta" || { no "(B) A==B was not empty"; hdr "$TMP/same.xml"; }
[ "$( attr "$TMP/same.xml" base_ref )" = "$( attr "$TMP/same.xml" target_ref )" ] \
    && ok "(B) A==B still discloses both refs" || no "(B) A==B ref disclosure inconsistent"

# ── (C) refusals: a bad ref, the three-dot form, and a half-typed value ───────────────────────────────────
"$BIN" . --quality-delta=nosuchref..HEAD >/dev/null 2>"$TMP/badrev.err"; badRc=$?
[ "$badRc" = 1 ] && ok "(C) an unresolvable ref exits 1" || no "(C) unresolvable ref exit was $badRc, expected 1"
grep -q "nosuchref" "$TMP/badrev.err" && ok "(C) the refusal NAMES the offending token" \
                                      || { no "(C) refusal does not name the bad token"; head -2 "$TMP/badrev.err"; }
grep -qi "rev-parse" "$TMP/badrev.err" && ok "(C) the refusal offers an adjacent probe to run" \
                                       || no "(C) refusal gives no did-you-mean-adjacent help"

"$BIN" . "--quality-delta=$A_SHA...$B_SHA" >/dev/null 2>"$TMP/dots.err"; dotRc=$?
[ "$dotRc" = 1 ] && grep -q 'three-dot' "$TMP/dots.err" \
    && ok "(C) A...B is REFUSED, not silently read as A..B" \
    || { no "(C) three-dot form not refused (rc=$dotRc)"; head -2 "$TMP/dots.err"; }

"$BIN" . --quality-delta= >/dev/null 2>"$TMP/empty.err"; emptyRc=$?
[ "$emptyRc" = 1 ] && ok "(C) a half-typed --quality-delta= is refused, not run as the bare form" \
                   || { no "(C) empty value was not refused (rc=$emptyRc)"; head -2 "$TMP/empty.err"; }

# ── (D) the BARE form is untouched by all of this ─────────────────────────────────────────────────────────
"$BIN" . --quality-delta >"$TMP/bare.xml" 2>/dev/null
hdr "$TMP/bare.xml" | grep -q 'base_ref=' \
    && no "(D) the bare form leaked a base_ref= attribute" \
    || ok "(D) the bare form emits no ref-pair attributes"
[ "$( attr "$TMP/bare.xml" baseline )" != "ref-pair" ] \
    && ok "(D) the bare form still names its own floor ($( attr "$TMP/bare.xml" baseline ))" \
    || no "(D) the bare form reported baseline=ref-pair"

# ── (E) DECISIVE: ripwire's own recorded harvest wave, against the live-recomputed overlay oracle ─────────
WAVE_A=4b9386c
WAVE_B=ba380b5
if ! git -C "$ROOT" rev-parse -q --verify "$WAVE_A^{commit}" >/dev/null 2>&1 \
   || ! git -C "$ROOT" rev-parse -q --verify "$WAVE_B^{commit}" >/dev/null 2>&1; then
    skip "(E) $WAVE_A..$WAVE_B not in this checkout (shallow clone or foreign repo) — the wave-level arm needs ripwire's own history"
else
    WT="$TMP/wave"
    if ! git -C "$ROOT" worktree add --detach "$WT" "$WAVE_A" >/dev/null 2>&1; then
        WT=""
        skip "(E) could not create a scratch worktree at $WAVE_A"
    else
        # --- the INDEPENDENT oracle: the hand-built overlay, recomputed here, sharing no code path with A..B
        "$BIN" "$WT" --quality-baseline >/dev/null 2>&1
        git -C "$WT" checkout "$WAVE_B" -- . >/dev/null 2>&1
        "$BIN" "$WT" --quality-delta >"$TMP/overlay.xml" 2>/dev/null
        # --- the new code path, in the SAME directory so BOTH read the same .ripwire_quality_acks ledger
        "$BIN" "$WT" "--quality-delta=$WAVE_A..$WAVE_B" >"$TMP/pair.xml" 2>/dev/null

        gatingRows "$TMP/overlay.xml" | grep -v '^short-horizon-churn|' >"$TMP/oracle.rows"
        gatingRows "$TMP/pair.xml"                                      >"$TMP/pair.rows"
        oracleN="$( wc -l <"$TMP/oracle.rows" | tr -d ' ' )"
        pairN="$( wc -l <"$TMP/pair.rows" | tr -d ' ' )"

        if [ "$oracleN" = 0 ]; then
            no "(E) the overlay oracle produced NO gating rows — it cannot be an oracle; check the recipe"
            hdr "$TMP/overlay.xml"
        elif diff -q "$TMP/oracle.rows" "$TMP/pair.rows" >/dev/null; then
            ok "(E) A..B reproduces the hand-built overlay's gating rows EXACTLY ($pairN rows, row for row)"
        else
            no "(E) A..B disagrees with the overlay oracle (oracle=$oracleN, pair=$pairN)"
            diff "$TMP/oracle.rows" "$TMP/pair.rows" | head -12
        fi

        # the disclosed discrepancy, asserted rather than merely commented: the overlay CAN measure churn
        # here and does; the ref-pair form says it cannot, and emits none.
        overlayChurn="$( gatingRows "$TMP/overlay.xml" | grep -c '^short-horizon-churn|' )"
        pairChurn="$( grep -o '<r kind="short-horizon-churn"' "$TMP/pair.xml" | wc -l | tr -d ' ' )"
        [ "$pairChurn" = 0 ] && [ "$( attr "$TMP/pair.xml" churn )" = "unavailable" ] \
            && ok "(E) churn is disclosed unavailable AND emits nothing (overlay measured $overlayChurn there)" \
            || no "(E) churn disclosure is FALSE: churn=$( attr "$TMP/pair.xml" churn ) but $pairChurn rows emitted"

        # the two RECORDED literals from the round record — a cross-check that these shas still name that wave
        overlayTotal=$(( oracleN + overlayChurn ))
        [ "$overlayTotal" = 18 ] \
            && ok "(E) the overlay reproduces the RECORDED 18 gating rows (= $oracleN + $overlayChurn churn)" \
            || no "(E) the overlay gave $overlayTotal gating rows; the round record states 18 — the shas or the corpus moved"
        dmmVal="$( "$BIN" "$ROOT" "--dmm=$WAVE_A..$WAVE_B" 2>/dev/null | grep -o ' dmm="[0-9.]*"' | head -1 | sed -E 's/.*"([0-9.]*)".*/\1/' )"
        # tolerance band, not equality: dmm is a float printed to 3 places (house float rule).
        if [ -n "$dmmVal" ] && awk -v v="$dmmVal" 'BEGIN{ exit !(v > 0.525 && v < 0.535) }'; then
            ok "(E) the RECORDED dmm 0.530 reproduces for the same pair (got $dmmVal)"
        else
            no "(E) dmm for $WAVE_A..$WAVE_B was '$dmmVal'; the round record states 0.530"
        fi
    fi
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

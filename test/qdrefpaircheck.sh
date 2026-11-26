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
# answer through a completely different mechanism — a real checked-out git tree, a serialized
# `.ripwire_quality_baseline` sidecar round-tripped through disk, and the ordinary working-tree comparison —
# and shares no code with the ref-pair path beyond computeDelta itself. It also cannot go stale, because it
# is recomputed on every run rather than pinned as a literal.
#
# Two literals ARE pinned, and only as a cross-check that the two shas still name the round the comment
# above describes: the harvest round record (PLAN_HARVEST_REPORTS_2026-08-15/ROUTING_LEDGER.md) states
# `--dmm=4b9386c..ba380b5` = 0.530 and 18 gating rows.
#
# THE 18 IS A HISTORICAL READING, AND IT MOVED — 2026-09-10, the per-kind dial round (test/qddialscheck.sh).
# 18 is what the kinds reported when churn="self" gated on its own, when verbosity counted physical lines,
# when any growth over the bar was major, and when every new export was a row. Four of those changed on
# purpose, so the same two shas now report 8. The literal is re-pinned to 8 rather than deleted, because what
# it checks is unchanged: that these shas still name a wave with regressions in it. dmm is a different
# instrument and does not read the gating tiers, so 0.530 is untouched — which is itself the cross-check that
# the CORPUS did not move, only the tiers.
#
# ── THE ONE DEFENSIBLE DISCREPANCY: the overlay's total exceeds the ref-pair form's ───────────────────────
# The overlay's gating total is higher than the ref-pair form's, and the difference is exactly the
# short-horizon-churn rows (7 of the historical 18; the dial round left fewer). It is a property of the
# QUESTION, not a bug:
#
#   The churn kind needs git history AT THE TREE BEING JUDGED — it counts commits per file in a recent
#   window and compares body hashes against a window-reference commit. The overlay's judged tree is a real
#   checkout with a real .git, so churn evaluates there (against HEAD = the BASE commit, which is itself a
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
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
. "$ROOT/test/lib/headbinlib.sh"                       # ripwire_private_checkout, for arm (E)'s scratch tree
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT        # (E)'s tree is a private clone in here: nothing registered, nothing to prune
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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
    if xmllint --noout "$TMP/syn.xml" 2>/dev/null; then ok "(A) output is well-formed XML"; else no "(A) xmllint rejected the output"; fi
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
if [ "$sameRc" = 0 ]; then ok "(B) A==B exits 0"; else no "(B) A==B exit was $sameRc, expected 0"; fi
[ "$( attr "$TMP/same.xml" regressions )" = "0" ] && [ "$( attr "$TMP/same.xml" gating )" = "0" ] \
    && ok "(B) A==B is an empty delta" || { no "(B) A==B was not empty"; hdr "$TMP/same.xml"; }
[ "$( attr "$TMP/same.xml" base_ref )" = "$( attr "$TMP/same.xml" target_ref )" ] \
    && ok "(B) A==B still discloses both refs" || no "(B) A==B ref disclosure inconsistent"

# ── (B2) D3 QD-STALE-HEADER: stale_tree= says when the files on disk are not the tree the range judged ─────────
# A range answer is about target_ref as COMMITTED. Run before the last edit (or on a commit HEAD has left), its green
# exit cannot pass for the current files, and the root now says so: stale_tree="1", present only when true.
# Premise: (A) ran A..B with B = HEAD on a clean tree, which is the one case it must be ABSENT.
hdr "$TMP/syn.xml" | grep -q ' stale_tree=' \
    && no "(B2) a clean tree whose HEAD is target_ref carries stale_tree= (it is present only when true)" \
    || ok "(B2) clean tree at target_ref: no stale_tree="
"$BIN" . "--quality-delta=$A_SHA..$A_SHA" >"$TMP/stale_head.xml" 2>"$TMP/stale_head.err"; staleHeadRc=$?
[ "$( attr "$TMP/stale_head.xml" stale_tree )" = "1" ] \
    && ok "(B2) target_ref is not HEAD's tree: stale_tree=\"1\"" \
    || { no "(B2) target_ref A is not HEAD (B), yet stale_tree= is '$( attr "$TMP/stale_head.xml" stale_tree )'"; hdr "$TMP/stale_head.xml"; }
if [ "$staleHeadRc" = 0 ]; then ok "(B2) stale_tree= never gates (A..A still exits 0)"; else no "(B2) A..A exit was $staleHeadRc, expected 0"; fi
if grep -q 'stale_tree=1' "$TMP/stale_head.err"; then ok "(B2) the stale note is on stderr"; else no "(B2) no stale_tree note on stderr: $( head -c 300 "$TMP/stale_head.err" )"; fi
printf '// an edit after the commit\n' >> lib.h
"$BIN" . "--quality-delta=$A_SHA..$B_SHA" >"$TMP/stale_dirty.xml" 2>/dev/null; staleDirtyRc=$?
"$BIN" . "--quality-delta=$A_SHA..$B_SHA" --legend=full >"$TMP/stale_dirty_full.xml" 2>/dev/null   # status: exits 2 like the run above (same rows); only its legend is read
git checkout -q -- lib.h
[ "$( attr "$TMP/stale_dirty.xml" stale_tree )" = "1" ] \
    && ok "(B2) an uncommitted edit after target_ref: stale_tree=\"1\"" \
    || { no "(B2) a dirty working tree, yet stale_tree= is '$( attr "$TMP/stale_dirty.xml" stale_tree )'"; hdr "$TMP/stale_dirty.xml"; }
[ "$staleDirtyRc" = "$synRc" ] && [ "$( attr "$TMP/stale_dirty.xml" gating )" = "$( attr "$TMP/syn.xml" gating )" ] \
    && ok "(B2) the same rows and exit ($staleDirtyRc) with and without stale_tree= (a disclosure, never a gate)" \
    || no "(B2) stale_tree= moved the answer: exit $staleDirtyRc vs $synRc, gating $( attr "$TMP/stale_dirty.xml" gating ) vs $( attr "$TMP/syn.xml" gating )"
if grep -q 'stale_tree=1:' "$TMP/stale_dirty.xml"; then ok "(B2) the compact legend defines stale_tree="; else no "(B2) the compact legend never defines stale_tree="; fi
if grep -qF 'stale_tree="1" means' "$TMP/stale_dirty_full.xml"; then ok "(B2) the full legend defines stale_tree="; else no "(B2) the full legend never defines stale_tree="; fi
grep -q 'stale_tree' "$TMP/syn.xml" && no "(B2) a document without stale_tree= pays for its legend" || ok "(B2) no stale_tree legend without the attribute"

# ── (C) refusals: a bad ref, the three-dot form, and a half-typed value ───────────────────────────────────
"$BIN" . --quality-delta=nosuchref..HEAD >/dev/null 2>"$TMP/badrev.err"; badRc=$?
if [ "$badRc" = 1 ]; then ok "(C) an unresolvable ref exits 1"; else no "(C) unresolvable ref exit was $badRc, expected 1"; fi
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

# ── (G) #387: the range form indexes its two commits and never the working tree ──────────────────────────
# A 20,000-file repository's HEAD~1..HEAD was OOM-killed at 8 GiB because main() indexed and graphed the working tree
# before dispatch, beside the two commits the range form indexes itself. Two observables, neither of them a timing:
# RIPWIRE_STATS prints its [stats] line only at the working-tree ingest site in main(), and RIPWIRE_CACHE_STATS prints
# one line per ingest that parsed anything, with files=. An untracked file makes the working tree's count differ from
# both commits' (1 file each). RED on a binary before #387: three cache-stats lines, one of them files=2, and [stats].
printf 'int wt_only( void ) { return 0; }\n' >"$R/wt_only.c"
RIPWIRE_STATS=1 RIPWIRE_CACHE_STATS=1 "$BIN" "$R" "--quality-delta=$A_SHA..$B_SHA" --no-cache >"$TMP/g.xml" 2>"$TMP/g.err"; gRc=$?
gLines="$( grep -c '^ripwire: cache-stats ' "$TMP/g.err" )"
gWt="$( grep -c '^ripwire: cache-stats .* files=2 ' "$TMP/g.err" )"
if [ "$gRc" = 2 ] && [ "$gLines" = 2 ] && [ "$gWt" = 0 ] && ! grep -q '^\[stats\]' "$TMP/g.err"; then
    ok "(G) A..B ingests its two commits only (2 cache-stats lines, none of the 2-file working tree, no [stats])"
else
    no "(G) A..B rc=$gRc cache-stats lines=$gLines (want 2), working-tree lines=$gWt (want 0), [stats]=$( grep -c '^\[stats\]' "$TMP/g.err" ) (want 0)"
fi
RIPWIRE_STATS=1 RIPWIRE_CACHE_STATS=1 "$BIN" "$R" "--quality-delta=$B_SHA..$B_SHA" --no-cache >/dev/null 2>"$TMP/g2.err"
[ "$( grep -c '^ripwire: cache-stats ' "$TMP/g2.err" )" = 1 ] && ! grep -q '^\[stats\]' "$TMP/g2.err" \
    && ok "(G) A==B ingests its one commit once" \
    || no "(G) A==B cache-stats lines=$( grep -c '^ripwire: cache-stats ' "$TMP/g2.err" ) (want 1), [stats]=$( grep -c '^\[stats\]' "$TMP/g2.err" )"
RIPWIRE_STATS=1 RIPWIRE_CACHE_STATS=1 "$BIN" "$R" --quality-delta --no-cache >/dev/null 2>"$TMP/g3.err"
grep -q '^\[stats\]' "$TMP/g3.err" && grep -q '^ripwire: cache-stats .* files=2 ' "$TMP/g3.err" \
    && ok "(G) control: the bare form still indexes the 2-file working tree, and both observables see it" \
    || no "(G) control: the bare form showed no working-tree ingest — the two observables above prove nothing"
"$BIN" . "--quality-delta=$A_SHA..$B_SHA" >"$TMP/g4.xml" 2>/dev/null
# D3 (QD-STALE-HEADER): the untracked file makes the tree on disk differ from B's, which the root now DISCLOSES —
# stale_tree="1" and its one compact-legend reading. Everything else (rows, counts, the rest of the legend) must be
# byte-identical: the range form still never reads the working tree's CONTENT.
[ "$( attr "$TMP/g4.xml" stale_tree )" = "1" ] \
    && ok "(G) the untracked file is disclosed as stale_tree=\"1\"" \
    || no "(G) an untracked working-tree file, yet no stale_tree=\"1\" on the root"
sed -e 's/ stale_tree="1"//' -e 's/ stale_tree=1: [^.]*; never gating\.//' "$TMP/g4.xml" >"$TMP/g4.nostale.xml"
cmp -s "$TMP/syn.xml" "$TMP/g4.nostale.xml" \
    && ok "(G) an untracked working-tree file does not change the A..B answer (stale_tree= and its legend aside)" \
    || { no "(G) an untracked working-tree file changed the A..B answer"; diff "$TMP/syn.xml" "$TMP/g4.nostale.xml" | head -4; }
"$BIN" "$R" "--for=tangle" "--quality-delta=$A_SHA..$B_SHA" >/dev/null 2>"$TMP/g5.err"; g5Rc=$?
[ "$g5Rc" = 0 ] && grep -q 'IGNORED this run: --quality-delta' "$TMP/g5.err" \
    && ok "(G) a verb that outranks --quality-delta still answers from the working tree (--for wins, the range is disclosed as ignored)" \
    || no "(G) --for beside A..B: rc=$g5Rc stderr: $( head -c 200 "$TMP/g5.err" )"
rm -f "$R/wt_only.c"
# The .ripwire_config disclosure reads the JUDGED tree's index (commit B). Both commits use the configured macro and the
# working tree does not, so a disclosure that read the working tree, or an empty index, would call the name inert.
# RED on 0.6.7, which read the working tree. The control names a macro no tree uses.
RC="$TMP/rcfg"; mkdir -p "$RC"
( cd "$RC" && git init -q . && git config user.email t@t && git config user.name t
  printf 'static void liveHelper() { }\nMY_CUSTOM_TEST( MySuite, MyCase ) { liveHelper(); }\nint main() { liveHelper(); return 0; }\n' >sample.cpp
  printf 'register_macros = MY_CUSTOM_TEST\n' >.ripwire_config
  git add -A && git commit -qm base
  printf 'static void liveHelper() { }\nMY_CUSTOM_TEST( MySuite, MyCase ) { liveHelper(); }\nint main() { liveHelper(); liveHelper(); return 0; }\n' >sample.cpp
  git commit -qam target
  printf 'static void liveHelper() { }\nint main() { liveHelper(); return 0; }\n' >sample.cpp )
grep -q MY_CUSTOM_TEST "$RC/sample.cpp" \
    && no "(G) premise: the working tree still uses MY_CUSTOM_TEST, so it cannot tell the trees apart" \
    || ok "(G) premise: both commits use MY_CUSTOM_TEST and the working tree does not"
"$BIN" "$RC" --quality-delta=HEAD~1..HEAD >"$TMP/g6.xml" 2>"$TMP/g6.err"; g6Rc=$?
if [ "$g6Rc" != 0 ] || [ -z "$( hdr "$TMP/g6.xml" )" ]; then
    no "(G) the judged-tree config arm got no report (rc=$g6Rc): $( head -c 200 "$TMP/g6.err" )"
elif hdr "$TMP/g6.xml" | grep -q 'config-warnings=' || grep -q 'matching no indexed symbol' "$TMP/g6.err"; then
    no "(G) a register_macros= name used in the judged tree was called inert: $( hdr "$TMP/g6.xml" | head -c 200 )"
else
    ok "(G) a register_macros= name used in the judged tree, and not in the working tree, is not called inert"
fi
printf 'register_macros = NOPE_NEVER_USED\n' >"$RC/.ripwire_config"
"$BIN" "$RC" --quality-delta=HEAD~1..HEAD >"$TMP/g7.xml" 2>"$TMP/g7.err"; g7Rc=$?
[ "$g7Rc" = 0 ] && hdr "$TMP/g7.xml" | grep -q 'config-warnings=' && grep -q 'NOPE_NEVER_USED' "$TMP/g7.err" \
    && ok "(G) control: a name no tree uses is still disclosed as inert" \
    || no "(G) control: an unused register_macros= name drew no disclosure (rc=$g7Rc): $( hdr "$TMP/g7.xml" | head -c 200 )"

# ── (E) DECISIVE: ripwire's own recorded harvest wave, against the live-recomputed overlay oracle ─────────
# RE-PIN LOG for the recorded literal below (it is a bare number, so its justification has to live here).
# 2026-11-21, lane QD-LESSONS-2a (TANGLE-GATE-B / QD-RATCHET-BASE): 8 → 10 gating rows on this wave. Both new rows are
#   tangle rows the kind now gates by design (it was report-only):
#     <r kind="tangle" sym="src/serialize.h::rw::packBodies" was="14.8" now="15.5" .../>   (over the bar and grew: deep 45->49, 257->277 lines)
#     <r kind="tangle" sym="collectSources" was="5.8" now="7.4" .../>                        (crossed the bar: deep 14->22, 182->213 lines)
#   The eight rows before are unchanged, and (E)'s row-for-row oracle comparison stays green (7 rows = the 5 before + these 2),
#   so 7 + 3 churn = 10.
# 2026-09-20, integration/train-13 (lane/t13-honesty-fixes fix 2): 9 → 8 gating rows on this wave, and the
#   row that left is EXACTLY the row train 12 added below. Fix 2 gives `reuse-decline`
#   (new-clone-of-reused-helper) the two demotions its sibling `duplication` already had, one of which is
#   the ALL-TEST-SCRIPT skip. Train 12's extra row was
#     <r kind="new-clone-of-reused-helper" sym="curl | http_call" p="test/mcpremotecheck.sh:51" .../>
#   whose every member is a `test/`-pathed `.sh` gate script — precisely the population the skip exempts,
#   and precisely the shape research-ai-smells measured as the kind's one real-history firing. `duplication`
#   was already silent on that group; the two reporters now agree on it. Checked on the merged binary: the
#   overlay carries NO new-clone-of-reused-helper row at all, and arm (E)'s row-for-row oracle comparison
#   (5 rows) and its churn disclosure arm (3) both stayed green, so 5 + 3 = 8. Nothing else moved: the
#   recorded dmm 0.530 reproduces unchanged.
#   FOUND LATE, and worth recording as such: this gate greps src/quality.h and was missed by train 13's
#   first-round gate selection, then caught by the wider sweep in the fix round.
# 2026-09-20, integration/train-12 (issue #60, lane/t12-filescope-calls): 8 → 9 gating rows on this wave.
#   The message below offers three candidate causes — "the shas, the corpus or a kind's tier moved". It was a
#   FOURTH: a kind's EVIDENCE moved, in the direction #60 exists to move it. The extra row is
#     <r kind="new-clone-of-reused-helper" sym="curl | http_call" p="test/mcpremotecheck.sh:51" was="0" now="6"/>
#   and the cause is checkable in one command on the wave's B tree: --callers=http_call reports count="0" on
#   755f9026 and count="1" on this train. The kind fires only when the clone group's maxFanin reaches
#   kReusedHelperMinFanin (3); a shell top-level call had no caller node before #60, so those call sites
#   conferred no fan-in and the group never qualified. The clone is not new and no bar moved — only the
#   evidence that the helper it duplicates is REUSED. The row-for-row oracle comparison and the churn
#   disclosure arm above both stayed green across the change (6 non-churn + 3 churn = 9).
WAVE_A=4b9386c
WAVE_B=ba380b5
if ! git -C "$ROOT" rev-parse -q --verify "$WAVE_A^{commit}" >/dev/null 2>&1 \
   || ! git -C "$ROOT" rev-parse -q --verify "$WAVE_B^{commit}" >/dev/null 2>&1; then
    skip "(E) $WAVE_A..$WAVE_B not in this checkout (shallow clone or foreign repo) — the wave-level arm needs ripwire's own history"
else
    WT="$TMP/wave"                                  # a private clone, never a registered worktree (test/worktreeleakcheck.sh)
    if ! ripwire_private_checkout "$ROOT" "$WAVE_A" "$WT" >/dev/null 2>&1; then
        skip "(E) could not check out a scratch tree at $WAVE_A"
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
        [ "$overlayTotal" = 10 ] \
            && ok "(E) the overlay reproduces the pinned 10 gating rows (= $oracleN + $overlayChurn churn; 8 before tangle gated, 9 between #60 and reuse-decline's test-script skip, 8 before #60, 18 pre-dial)" \
            || no "(E) the overlay gave $overlayTotal gating rows; this binary is pinned at 10 (8 before tangle gated (QD-LESSONS-2a), 9 between #60's file-scope callers and reuse-decline's all-test-script skip, 8 before #60, 18 before the 2026-09-10 dial round) — the shas, the corpus, a kind's tier or a kind's EVIDENCE moved; the RE-PIN LOG above arm (E) records how the last move was justified"
        dmmVal="$( "$BIN" "$ROOT" "--dmm=$WAVE_A..$WAVE_B" 2>/dev/null | grep -o ' dmm="[0-9.]*"' | head -1 | sed -E 's/.*"([0-9.]*)".*/\1/' )"
        # tolerance band, not equality: dmm is a float printed to 3 places (house float rule).
        if [ -n "$dmmVal" ] && awk -v v="$dmmVal" 'BEGIN{ exit !(v > 0.525 && v < 0.535) }'; then
            ok "(E) the RECORDED dmm 0.530 reproduces for the same pair (got $dmmVal)"
        else
            no "(E) dmm for $WAVE_A..$WAVE_B was '$dmmVal'; the round record states 0.530"
        fi

        # ── (F) the AMBIENT-GIT-CONFIG seam — the arm that would have caught the 19-vs-18 divergence ──────
        # Arm (E) above compares two mechanisms; it does NOT ask whether either one answers the same way on
        # a machine configured differently. It did not, and that is how this gate stayed green on every
        # developer's tree while it was red on every CI leg: the churn SELF/AMBIENT split blames lines,
        # `git blame` honors `blame.ignoreRevsFile` from REPO-LOCAL config, and git config is never cloned.
        # Configured worktrees read the mechanical brace sweep through to the real author (AMBIENT, 18
        # rows); CI's empty config counted the sweep itself as in-window thrash (SELF, 19). Nothing was
        # stale and nothing had moved — the number was simply a function of an input nobody had written
        # down. So the property to gate is not a count, it is INVARIANCE: the same shas and the same tree
        # must produce the same rows no matter what the ambient git config says.
        #
        # GIT_CONFIG_* is the non-destructive way to say "a developer had this configured" — it injects
        # config for the spawned git without writing to $ROOT's real config file, which a `git config` call
        # in a gate would clobber (it did while this scratch tree was a worktree sharing the developer's config; as
        # a private clone it has its own, and GIT_CONFIG_* still writes no config file at all).
        # Both directions are pinned: pointing AT this repo's ignore list (the exact value that caused the
        # incident) and at an empty list (the CI-shaped value). RED BEFORE GREEN: against a binary built
        # before the pin, the first of the two differs from the unconfigured run by exactly the one
        # short-horizon-churn row on src/docdrift.h::computeDocDrift.
        gatingRows "$TMP/overlay.xml" >"$TMP/ambient_base.rows"
        for ignoreVal in "$WT/.git-blame-ignore-revs" "/dev/null"; do
            env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=blame.ignoreRevsFile GIT_CONFIG_VALUE_0="$ignoreVal" \
                "$BIN" "$WT" --quality-delta >"$TMP/overlay_ambient.xml" 2>/dev/null
            gatingRows "$TMP/overlay_ambient.xml" >"$TMP/ambient.rows"
            if diff -q "$TMP/ambient_base.rows" "$TMP/ambient.rows" >/dev/null; then
                ok "(F) gating rows are invariant to an ambient blame.ignoreRevsFile=$ignoreVal"
            else
                no "(F) ambient blame.ignoreRevsFile=$ignoreVal MOVED the gating rows — the measurement inherits developer config"
                diff "$TMP/ambient_base.rows" "$TMP/ambient.rows" | head -6
            fi
        done
    fi
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

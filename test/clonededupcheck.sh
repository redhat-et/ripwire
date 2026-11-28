#!/usr/bin/env bash
# clonededupcheck.sh — P5W2 gate for the working-tree clone-pass DEDUP in quality.h::computeDelta.
#
# BACKGROUND (the investigation this gate defends). Profiling --quality-delta on a large private C++ corpus
# showed the working-tree clone pass is the dominant cost (~8 s), and it was RECOMPUTED TWICE per call: computeDelta had
# two independent consumers of the clone groups — the `duplication`/`new-clone-of-reused-helper` new-group
# report AND the reuse-connectivity report — and EACH called findClones()+findClonesType3() itself. On
# that corpus the Type-3 pass alone is ~2.7-3.2 s (60 M intra-bucket pair-visits; per-file TOKENIZATION is only
# ~3 %, which is why a token-stream cache was measured and REJECTED — it would save <90 ms). The fix computes
# each clone pass ONCE and feeds both consumers. Because findClones/findClonesType3 are deterministic pure
# functions of the ingest, the single result is field-for-field the value both call sites received before, so
# --quality-delta output is BYTE-IDENTICAL — this gate proves exactly that (the house bar: "faster must never
# change the answer"), plus determinism and that BOTH clone consumers still fire.
#
# What this gate asserts:
#   (a) BYTE-IDENTITY vs a golden binary — --clones (the shared clones.h path, unchanged) and --quality-delta
#       (the deduped path) produce output identical to $GOLD_BIN on the same corpus.
#   (b) EDIT-CORRECTNESS — introducing a NEW exact clone of an EXISTING, WELL-REUSED (high-fan-in) helper into
#       the working tree makes --quality-delta report BOTH a `duplication` regression AND a
#       `new-clone-of-reused-helper` regression — proving BOTH consumers of the now-shared clone vectors still
#       receive them (a dedup that dropped one consumer would silently lose a whole regression kind).
#   (b2) OVERLAP — only gating exact rows and their directly overlapping gating near rows merge.
#       Acks cover component findings, and a single-kind selection preserves the per-group rows.
#   (c) DETERMINISM — --quality-delta on a fixed tree is byte-stable across repeated runs.
#   (d) MUTATION TEST — a deliberately-wrong assertion fails, proving (a)-(c) are non-vacuous.
#
# Usage:
#   test/clonededupcheck.sh                        # BIN=build/ripwire, GOLD_BIN=build/ripwire (self — (a) trivially holds)
#   RIPWIRE_BIN=build_p5w2/ripwire GOLD_BIN=build/ripwire test/clonededupcheck.sh   # deduped vs golden
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
GOLD="${GOLD_BIN:-$ROOT/build/ripwire}"
[ "${GOLD#/}" = "$GOLD" ] && GOLD="$ROOT/$GOLD"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ]  || { echo "no ripwire binary at $BIN — build first (cmake --build build_p5w2 -j)"; exit 2; }
[ -x "$GOLD" ] || { echo "no golden binary at $GOLD"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

echo "clonededupcheck: BIN=$BIN  GOLD=$GOLD"

# ── Build a self-contained git corpus with a REUSED helper (high fan-in) so the reuse-connectivity kind can
#    fire when it is later duplicated. calc() is called from many sites (fan-in >= kReusedHelperMinFanin=3).
REPO="$TMP/repo"; mkdir -p "$REPO/src"
cat > "$REPO/src/util.cpp" <<'EOF'
// a well-reused helper: several callers give it a high fan-in.
int calc( int a, int b )
{
    int total = 0;
    for( int i = 0; i < a; ++i )
    {
        total += b;
        total ^= ( total << 1 );
        total -= i;
    }
    return total;
}
int callA( int x ) { return calc( x, 2 ); }
int callB( int x ) { return calc( x, 4 ); }
int callC( int x ) { return calc( x, 6 ); }
EOF
cat > "$REPO/src/main.cpp" <<'EOF'
int callA( int );
int callB( int );
int callC( int );
int run( int n ) { return callA( n ) + callB( n ) + callC( n ); }
EOF
printf 'int calcChain( int a, int b ) { return a + b; }\n' > "$REPO/src/chain.cpp"

( cd "$REPO" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm base ) || { no "git fixture setup failed"; echo; echo "SOME CHECKS FAILED"; exit 1; }

export TMPDIR="$TMP/cache"; mkdir -p "$TMPDIR"    # isolate qsnap/head caches from the real machine cache

# ── (a) BYTE-IDENTITY on the clean tree: --clones and --quality-delta vs golden ──────────────────────────────
"$GOLD" "$REPO" --clones >"$TMP/g_clones" 2>/dev/null; rcGold=$?
"$BIN"  "$REPO" --clones >"$TMP/n_clones" 2>/dev/null; rcClones=$?
[ "$rcGold" -eq 0 ] && [ "$rcClones" -eq 0 ] && cmp -s "$TMP/g_clones" "$TMP/n_clones" \
    && ok "(a) --clones byte-identical to golden (shared clones.h path unchanged)" \
    || no "(a) --clones DIFFERS from golden: $(diff <(head -c 200 "$TMP/g_clones") <(head -c 200 "$TMP/n_clones") | head -3)"

"$GOLD" "$REPO" --quality-delta >"$TMP/g_qd_clean" 2>/dev/null; rcGold=$?
"$BIN"  "$REPO" --quality-delta >"$TMP/n_qd_clean" 2>/dev/null; rcClean=$?
[ "$rcGold" -eq 0 ] && [ "$rcClean" -eq 0 ] && cmp -s "$TMP/g_qd_clean" "$TMP/n_qd_clean" \
    && ok "(a) --quality-delta byte-identical to golden on the clean tree (dedup changes no output)" \
    || no "(a) --quality-delta DIFFERS from golden (clean): $(diff "$TMP/g_qd_clean" "$TMP/n_qd_clean" | head -3)"

# ── (b) EDIT-CORRECTNESS: add a NEW exact clone of the reused helper calc() into the working tree ─────────────
# calcDup has an IDENTICAL body to calc (Type-1/2 exact clone); calc has fan-in>=3, so the new group is BOTH a
# `duplication` regression AND a `new-clone-of-reused-helper` regression. --quality-delta auto-baselines vs HEAD
# (the committed tree with no dup), so the dup is genuinely NEW vs baseline. Both kinds must appear, and the new
# binary must match the golden binary apart from the full clone legend (the compact dictionary is not in this comparison).
cat >> "$REPO/src/util.cpp" <<'EOF'
int calcDup( int a, int b )
{
    int total = 0;
    for( int i = 0; i < a; ++i )
    {
        total += b;
        total ^= ( total << 1 );
        total -= i;
    }
    return total;
}
EOF

"$GOLD" "$REPO" --quality-delta --legend=full >"$TMP/g_qd_edit" 2>/dev/null; rcGold=$?
"$BIN"  "$REPO" --quality-delta --legend=full >"$TMP/n_qd_edit" 2>/dev/null; rcEdit=$?
normalize_clone_legend(){ awk '{ sub(/CLONE ROWS .*idiom= alone changes nothing;/, "CLONE ROWS idiom= alone changes nothing;"); print }' "$1"; }

[ "$rcGold" -eq 2 ] && [ "$rcEdit" -eq 2 ] && cmp -s <(normalize_clone_legend "$TMP/g_qd_edit") <(normalize_clone_legend "$TMP/n_qd_edit") \
    && ok "(b) --quality-delta matches golden after introducing an exact clone, apart from the revised clone legend" \
    || no "(b) --quality-delta failed or changed the exact-clone report (exits $rcGold/$rcEdit): $(diff <(normalize_clone_legend "$TMP/g_qd_edit") <(normalize_clone_legend "$TMP/n_qd_edit") | head -5)"

grep -q '<r kind="duplication"' "$TMP/n_qd_edit" \
    && ok "(b) new binary reports a 'duplication' regression for the new clone (consumer #1 fires)" \
    || no "(b) new binary MISSED the 'duplication' regression: $(cat "$TMP/n_qd_edit")"

grep -q '<r kind="new-clone-of-reused-helper"' "$TMP/n_qd_edit" \
    && ok "(b) new binary reports 'new-clone-of-reused-helper' (consumer #2 fires — dedup kept BOTH consumers)" \
    || no "(b) new binary MISSED 'new-clone-of-reused-helper' (a dropped consumer): $(cat "$TMP/n_qd_edit")"

# ── (b2) MINOR: a near row demoted by different parameter types must not consume the exact rows ──
cat > "$REPO/src/zminor.cpp" <<'EOF'
int calcMinor( long a, int b )
{
    int total = 0;
    for( int i = 0; i < a; ++i )
    {
        total += b;
        total ^= ( total << 1 );
        total -= i;
    }
    int scratch;
    return total;
}
EOF
"$BIN" "$REPO" --quality-delta >"$TMP/n_overlap_minor" 2>/dev/null; rcMinor=$?
if [ "$rcMinor" -eq 2 ] \
   && grep -q '<r kind="duplication" members="calc | calcDup"[^>]*gating="1"' "$TMP/n_overlap_minor" \
   && grep -Eq '<r kind="duplication" members="calc(Dup)? \| calcMinor"[^>]*sev="minor"[^>]*why="different parameter types"' "$TMP/n_overlap_minor"; then
    ok "(b2) minor near pair stays separate from the gating exact group"
else
    no "(b2) expected a minor near pair next to the still-gating exact group"
fi
rm "$REPO/src/zminor.cpp"

# ── (b2) OVERLAP: exact and near reports for one reused helper become one gating row ────────────────
cp "$REPO/src/util.cpp" "$TMP/exact_only.cpp"
"$BIN" "$REPO" --quality-delta --ack-only=gating --quality-ack="fixture: accepted exact copies" >/dev/null 2>&1; rcAcceptExact=$?
cat >> "$REPO/src/util.cpp" <<'EOF'
int calcNear( int a, int b )
{
    int total = 0;
    for( int i = 0; i < a; ++i )
    {
        total += b;
        total ^= ( total << 1 );
        total -= i;
    }
    int scratch = ( total + a ) ^ b;
    return total;
}
EOF
"$BIN" "$REPO" --quality-delta >"$TMP/n_exact_acked" 2>/dev/null; rcExactAcked=$?
if [ "$rcAcceptExact" -eq 0 ] && [ "$rcExactAcked" -eq 2 ] \
   && grep -q '<quality-delta[^>]*acked="2"' "$TMP/n_exact_acked" \
   && grep -Eq '<r kind="(duplication|new-clone-of-reused-helper)"[^>]*calcNear[^>]*gating="1"' "$TMP/n_exact_acked" \
   && ! grep -Fq 'calc | calcDup | calcNear' "$TMP/n_exact_acked"; then
    ok "(b2) acknowledging the exact copies does not hide a later near copy"
else
    no "(b2) expected an unacknowledged gating calcNear row after accepting the exact copies"
fi
rm -f "$REPO/.ripwire_quality_acks"

"$BIN" "$REPO" --clones >"$TMP/n_overlap_raw" 2>/dev/null; rcRaw=$?
"$BIN" "$REPO" --quality-delta >"$TMP/n_overlap_qd" 2>/dev/null; rcOverlap=$?
if [ "$rcRaw" -eq 0 ] && [ "$rcOverlap" -eq 2 ] && python3 - "$TMP/n_overlap_raw" "$TMP/n_overlap_qd" <<'PY'
import sys
import xml.etree.ElementTree as ET

groups = {(g.get("type"), frozenset(f.get("n") for f in g.findall("f")))
          for g in ET.parse(sys.argv[1]).iter("group")}
assert ("2", frozenset({"calc", "calcDup"})) in groups, groups
assert any(("3", frozenset({name, "calcNear"})) in groups for name in ("calc", "calcDup")), groups
rows = [r.attrib for r in ET.parse(sys.argv[2]).iter("r")
        if r.get("kind") in {"duplication", "new-clone-of-reused-helper"}]
assert len(rows) == 1, rows
row = rows[0]
assert row["kind"] == "new-clone-of-reused-helper" and row.get("gating") == "1", row
assert row["sym"].split(" | ") == ["calc", "calcDup", "calcNear"], row
PY
then
    ok "(b2) raw exact and near groups survive; quality-delta shows one gating reused-helper report"
else
    no "(b2) expected one gating reused-helper report for the exact/near overlap"
fi

# ── (c) DETERMINISM: repeated --quality-delta on the fixed (edited) working tree is byte-stable ──────────────
"$BIN" "$REPO" --quality-delta >"$TMP/n_qd_det" 2>/dev/null; rcDet=$?
[ "$rcDet" -eq 2 ] && cmp -s "$TMP/n_overlap_qd" "$TMP/n_qd_det" \
    && ok "(c) --quality-delta deterministic (two runs byte-identical)" \
    || no "(c) --quality-delta failed or changed bytes on repeat (exit $rcDet): $(diff "$TMP/n_overlap_qd" "$TMP/n_qd_det" | head -3)"

# A copied displayed symbol list selects the entire overlap, even though no component has that name.
"$BIN" "$REPO" --quality-delta --ack-only="calc | calcDup | calcNear" --quality-ack="fixture: selected displayed overlap" >/dev/null 2>&1; rcSelectOverlap=$?
"$BIN" "$REPO" --quality-delta >"$TMP/n_selected_overlap" 2>/dev/null; rcSelectedOverlap=$?
if [ "$rcSelectOverlap" -eq 0 ] && [ "$rcSelectedOverlap" -eq 0 ] \
   && ! grep -Eq '<r kind="(duplication|new-clone-of-reused-helper)"' "$TMP/n_selected_overlap"; then
    ok "(b2) selecting the merged row by its displayed symbol list acknowledges every component"
else
    no "(b2) expected the displayed symbol list to select all findings in the overlap"
fi
rm -f "$REPO/.ripwire_quality_acks"

# Accept the report, then remove the near copy: the two exact findings must stay acknowledged.
"$BIN" "$REPO" --quality-delta --ack-only=gating --quality-ack="fixture: accepted overlap" >/dev/null 2>&1; rcAccept=$?
"$BIN" "$REPO" --quality-delta --show-stale >"$TMP/n_overlap_acked" 2>/dev/null; rcAcked=$?
cp "$REPO/src/util.cpp" "$TMP/with_near.cpp"
cp "$TMP/exact_only.cpp" "$REPO/src/util.cpp"
"$BIN" "$REPO" --quality-delta >"$TMP/n_exact_still_acked" 2>/dev/null; rcExactStillAcked=$?
mv "$TMP/with_near.cpp" "$REPO/src/util.cpp"
if [ "$rcAccept" -eq 0 ] && [ "$rcAcked" -eq 0 ] && [ "$rcExactStillAcked" -eq 0 ] \
   && grep -q '^ack duplication ' "$REPO/.ripwire_quality_acks" \
   && grep -q '^ack new-clone-of-reused-helper ' "$REPO/.ripwire_quality_acks" \
   && grep -q '<quality-delta[^>]*stale="0"' "$TMP/n_overlap_acked" \
   && grep -q '<quality-delta[^>]*acked="2"' "$TMP/n_exact_still_acked" \
   && ! grep -Eq '<sa |<r kind="(duplication|new-clone-of-reused-helper)"' "$TMP/n_overlap_acked"; then
    ok "(b2) acknowledging an overlap records its component findings and survives removing the overlap"
else
    no "(b2) expected live acks for all findings in the overlap and for both remaining exact findings"
fi
rm -f "$REPO/.ripwire_quality_acks"

# Drop one of the three callers temporarily: the same overlap is now a duplication row, not reuse erosion.
cp "$REPO/src/util.cpp" "$TMP/with_callers.cpp"
awk '!/^int callC\(/' "$TMP/with_callers.cpp" > "$REPO/src/util.cpp"
"$BIN" "$REPO" --quality-delta >"$TMP/n_overlap_no_reuse" 2>/dev/null; rcNoReuse=$?
if [ "$rcNoReuse" -eq 2 ] \
   && grep -q '<r kind="duplication" members="calc | calcDup | calcNear"[^>]*gating="1"' "$TMP/n_overlap_no_reuse" \
   && [ "$(grep -o '<r kind="duplication"' "$TMP/n_overlap_no_reuse" | wc -l)" -eq 1 ] \
   && ! grep -q '<r kind="new-clone-of-reused-helper"' "$TMP/n_overlap_no_reuse"; then
    ok "(b2) without a reused helper, one gating duplication row names all three members"
else
    no "(b2) expected exactly one clone row after removing reuse evidence"
fi
mv "$TMP/with_callers.cpp" "$REPO/src/util.cpp"

# calcChain existed in the baseline, so its pair with the new calcNear can gate. Each insertion
# preserves similarity to its immediate predecessor; both take calcChain outside calc's band.
cat > "$REPO/src/chain.cpp" <<'EOF'
int calcChain( int a, int b )
{
    int total = 0;
    for( int i = 0; i < a; ++i )
    {
        total += b;
        total ^= ( total << 1 );
        total -= i;
    }
    int scratch = ( total + a ) ^ b;
    if( a > 10 )
    {
        total *= a;
        total /= b;
        total += a;
    }
    return total;
}
EOF
"$BIN" "$REPO" --quality-delta >"$TMP/n_overlap_chain" 2>/dev/null; rcChain=$?
if [ "$rcChain" -eq 2 ] && python3 - "$TMP/n_overlap_chain" <<'PY'
import sys
import xml.etree.ElementTree as ET

rows = [r.attrib for r in ET.parse(sys.argv[1]).iter("r")
        if r.get("kind") in {"duplication", "new-clone-of-reused-helper"}]
assert len(rows) == 2, rows
assert rows[0].get("members") == "calcChain | calcNear" and rows[0].get("gating") == "1", rows
assert rows[1].get("sym") == "calc | calcDup | calcNear" and rows[1].get("gating") == "1", rows
PY
then
    ok "(b2) only the directly overlapping near pair joins the exact group"
else
    no "(b2) expected a separate gating calcChain/calcNear pair and a three-member reused-helper row"
fi

# The selector is only available on REF..REF, not on the working tree.
git -C "$REPO" add src && git -C "$REPO" commit -qm overlap \
    || { no "(b2) could not commit the overlap fixture for the kind selector"; exit 1; }
"$BIN" "$REPO" --quality-delta=HEAD~1..HEAD --quality-kinds=duplication >"$TMP/n_overlap_dup" 2>/dev/null; rcDup=$?
if [ "$rcDup" -eq 2 ] \
   && grep -q '<r kind="duplication" members="calc | calcDup"[^>]*gating="1"' "$TMP/n_overlap_dup" \
   && grep -Eq '<r kind="duplication" members="calc(Dup)? \| calcNear"[^>]*gating="1"' "$TMP/n_overlap_dup" \
   && ! grep -q '<r kind="new-clone-of-reused-helper"' "$TMP/n_overlap_dup"; then
    ok "(b2) duplication-only selection reports exact and near groups separately"
else
    no "(b2) duplication-only selection lost an exact or near group"
fi

# ── (d) MUTATION TEST: a wrong expectation must fail ─────────────────────────────────────────────────────────
if grep -q 'kind="THIS_KIND_NEVER_EXISTS_zzz"' "$TMP/n_qd_edit"; then
    no "(d) mutation-test: matched a kind that can never exist (assertions are broken)"
else
    ok "(d) mutation-test: a deliberately-wrong grep correctly finds no match (assertions above are non-vacuous)"
fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi

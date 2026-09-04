#!/usr/bin/env bash
# historyoraclecheck.sh — the gate for the NAME-HISTORY ORACLE (src/gitoracle.h) and its two consumers,
# --doc-drift and --whereis, under --with-history.
#
#   test/historyoraclecheck.sh
#   RIPWIRE_BIN=asan/ripwire test/historyoraclecheck.sh
#
# The fixture is BUILT here, not committed: the whole question is "what does git HISTORY say", so the corpus
# has to be a real repository with a real commit that really deleted something. Fixed author/committer dates
# keep it byte-reproducible.
#
# The two names the oracle exists to SEPARATE, both looking identical to the pre-flag verb (defined nowhere,
# so both were why="undefined"):
#   vanishedContourWalker    — added in the base commit, DELETED in a later one  -> why="deleted", naming that
#                              commit, its date and the file (real rot)
#   neverBuiltPhantomWalker  — named only by a plan doc, never written at all    -> unchecked
#                              r="never-in-history" (expected absence, NOT rot)
# …plus stableAnchorHelper, which is still defined and must stay silent in every mode.
#
# And the invariant a cache can break: WARM output must be byte-identical to COLD output. Both runs are
# pinned to their own TMPDIR (the cache-dir ladder's first rung), so "cold" is genuinely cold.
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "historyoraclecheck: git unavailable — skipping"; exit 0; }

R="$TMP/repo"; mkdir -p "$R"
export GIT_AUTHOR_NAME=ripwire GIT_AUTHOR_EMAIL=ripwire@example.invalid
export GIT_COMMITTER_NAME=ripwire GIT_COMMITTER_EMAIL=ripwire@example.invalid
export GIT_AUTHOR_DATE="2026-02-03T00:00:00Z" GIT_COMMITTER_DATE="2026-02-03T00:00:00Z"
g(){ git -C "$R" "$@" >/dev/null 2>&1; }

g init -q -b main
g config commit.gpgsign false

# ── the base commit: both helpers exist ───────────────────────────────────────────────────────────────
cat > "$R/relief.h" <<'EOF'
#pragma once

namespace hofix
{

inline int stableAnchorHelper( int value )
{
    return value + 1;
}

inline int vanishedContourWalker( int value )
{
    return value * 3;
}

}   // namespace hofix
EOF
g add relief.h
g commit -qm "base: both helpers"

# ── the doc: it names all three, each corroborated by a live name on its own line ─────────────────────
# (the mention lane requires a name this repo DOES define on the SAME line — docdrift::kCorroborateWin = 0)
cat > "$R/PLAN_relief.md" <<'EOF'
# relief plan

- DELETED — `stableAnchorHelper` used to hand off to `vanishedContourWalker`, which is gone.
- NEVER BUILT — `stableAnchorHelper` will one day call `neverBuiltPhantomWalker`, which was never written.
- HOLDS — `stableAnchorHelper` is still the entry point.
EOF
g add PLAN_relief.md
g commit -qm "the plan doc"

# ── the deletion: vanishedContourWalker leaves the tree ───────────────────────────────────────────────
export GIT_AUTHOR_DATE="2026-02-09T00:00:00Z" GIT_COMMITTER_DATE="2026-02-09T00:00:00Z"
cat > "$R/relief.h" <<'EOF'
#pragma once

namespace hofix
{

inline int stableAnchorHelper( int value )
{
    return value + 1;
}

}   // namespace hofix
EOF
g commit -qam "remove the contour walker"
DEL_SHA="$( git -C "$R" rev-parse --short=9 HEAD 2>/dev/null )"

echo "historyoraclecheck: BIN=$BIN  REPO=$R  deletion=$DEL_SHA"

rows(){ tr '<' '\n' < "$1" | grep '^a k='; }

# ── 1) WITHOUT the flag: the pre-flag behaviour is preserved exactly (both names read "undefined") ────
C1="$TMP/t1"; mkdir -p "$C1"
TMPDIR="$C1" "$BIN" "$R" --doc-drift --detail=999 >"$TMP/plain" 2>/dev/null
n_undef="$( rows "$TMP/plain" | grep -c 'why="undefined"' )"
[ "$n_undef" = "2" ] \
    && ok "without --with-history both names still report why=\"undefined\" (pre-flag behaviour intact)" \
    || { no "expected 2 undefined rows without the flag, got $n_undef"; rows "$TMP/plain"; }
rows "$TMP/plain" | grep -q 'why="deleted"' \
    && no "why=\"deleted\" emitted without --with-history (the probe must be opt-in)" \
    || ok "no history verdict leaks into the default path"
grep -q '<history ' "$TMP/plain" \
    && no "a <history> element was emitted without --with-history" \
    || ok "no <history> element on the default path"

# ── 2) WITH the flag: the two names separate ──────────────────────────────────────────────────────────
TMPDIR="$C1" "$BIN" "$R" --doc-drift --with-history --detail=999 >"$TMP/hist" 2>/dev/null
rc=$?
[ "$rc" = "0" ] && ok "--doc-drift --with-history exits 0 (a report, not a gate)" || no "exited $rc, expected 0"

rows "$TMP/hist" | grep -q "why=\"deleted\" ref=\"vanishedContourWalker\" got=\"removed in $DEL_SHA " \
    && ok "vanishedContourWalker -> why=\"deleted\", naming the commit that removed it ($DEL_SHA)" \
    || { no "the deleted name was not attributed to $DEL_SHA"; rows "$TMP/hist" | grep -i vanished; }

# tgt=, not at=: the row attribute was renamed because at= already meant the root element's git sha stamp,
# so one document was using one name for two things (a commit and a file path). at= is now the sha, always.
rows "$TMP/hist" | grep -q 'ref="vanishedContourWalker".*tgt="relief.h"' \
    && ok "the deleted row cites the FILE the removal happened in (tgt=)" \
    || { no "the deleted row has no tgt= evidence"; rows "$TMP/hist" | grep -i vanished; }

rows "$TMP/hist" | grep -q 'ref="vanishedContourWalker"[^>]*[^_a-z]at="' \
    && no "a row still carries at= — that name is reserved for the root sha stamp" \
    || ok "no row reuses at= (reserved for the root element's commit stamp)"

rows "$TMP/hist" | grep -q 'got="removed in [0-9a-f]* (2026-02-09)"' \
    && ok "the deleted row carries the removing commit's COMMITTER date (git's clock, not the wall clock)" \
    || { no "no committer date on the deleted row"; rows "$TMP/hist" | grep -i vanished; }

rows "$TMP/hist" | grep -q 'neverBuiltPhantomWalker' \
    && { no "neverBuiltPhantomWalker still reported as drift — it was NEVER here, so it is not rot"; rows "$TMP/hist" | grep -i phantom; } \
    || ok "neverBuiltPhantomWalker is no longer drift (never in this repo's history)"

grep -q '<unchecked r="never-in-history" n="1"' "$TMP/hist" \
    && ok "…and it is COUNTED, with its reason, in an <unchecked> row (nothing dropped silently)" \
    || { no "the reclassified name did not land in an <unchecked r=\"never-in-history\"> row"; tr '<' '\n' < "$TMP/hist" | grep '^unchecked'; }

rows "$TMP/hist" | grep -q 'stableAnchorHelper' \
    && no "stableAnchorHelper reported, but it is still defined" \
    || ok "the still-defined name stays silent — true negative preserved"

# The TRUE POSITIVE must survive the reclassification: drift drops by exactly the never-here row.
d_plain="$( sed -n 's/.*<doc-drift[^>]* drift="\([0-9]*\)".*/\1/p' "$TMP/plain" )"
d_hist="$(  sed -n 's/.*<doc-drift[^>]* drift="\([0-9]*\)".*/\1/p' "$TMP/hist"  )"
{ [ "$d_plain" = "2" ] && [ "$d_hist" = "1" ]; } \
    && ok "drift $d_plain -> $d_hist: the false positive left, the true positive stayed" \
    || no "drift went $d_plain -> $d_hist, expected 2 -> 1"

# ── 3) the honesty invariant still holds with the new lane in play ────────────────────────────────────
A="$( sed -n 's/.*<doc-drift[^>]* anchors="\([0-9]*\)".*/\1/p' "$TMP/hist" )"
C="$( sed -n 's/.*<doc-drift[^>]* checked="\([0-9]*\)".*/\1/p' "$TMP/hist" )"
U="$( sed -n 's/.*<doc-drift[^>]* unchecked="\([0-9]*\)".*/\1/p' "$TMP/hist" )"
{ [ -n "$A" ] && [ "$(( C + U ))" = "$A" ]; } \
    && ok "checked($C) + unchecked($U) == anchors($A) — the invariant survives reclassification" \
    || no "the honesty invariant broke: checked=$C unchecked=$U anchors=$A"

grep -q '<history probed="1" head="[0-9a-f]\{9\}" commits="[0-9]*" removed-names="[0-9]*"/>' "$TMP/hist" \
    && ok "<history> states what the probe actually walked" \
    || { no "the <history> element is missing or malformed"; tr '<' '\n' < "$TMP/hist" | grep '^history'; }

# ── 4) WARM == COLD (the cache must not be able to change the answer) ─────────────────────────────────
C2="$TMP/t2"; mkdir -p "$C2"
TMPDIR="$C2" "$BIN" "$R" --doc-drift --with-history --detail=999 >"$TMP/cold" 2>/dev/null
TMPDIR="$C2" "$BIN" "$R" --doc-drift --with-history --detail=999 >"$TMP/warm" 2>/dev/null
cmp -s "$TMP/cold" "$TMP/warm" \
    && ok "doc-drift: warm (cached probe) == cold, byte-identical" \
    || { no "warm and cold disagree — a cached field changed the answer"; diff <(tr '<' '\n' <"$TMP/cold") <(tr '<' '\n' <"$TMP/warm") | head -6; }

blob="$( find "$C2" -name 'ripwire-qhist-*.bin' | head -1 )"
[ -n "$blob" ] && ok "the probe memoized itself into a sha-keyed cache blob" \
               || no "no ripwire-qhist-*.bin blob was written (the probe would re-walk every run)"

# A CORRUPT blob must be a clean MISS (recompute), never a wrong answer.
if [ -n "$blob" ]; then
    printf 'not a ripwire cache blob at all' > "$blob"
    TMPDIR="$C2" "$BIN" "$R" --doc-drift --with-history --detail=999 >"$TMP/corrupt" 2>/dev/null
    cmp -s "$TMP/cold" "$TMP/corrupt" \
        && ok "a corrupt cache blob recomputes to the same answer (magic/scheme/checksum guards hold)" \
        || { no "a corrupt cache blob changed the output"; diff <(tr '<' '\n' <"$TMP/cold") <(tr '<' '\n' <"$TMP/corrupt") | head -6; }
fi

# ── 5) --whereis: the lane a TREE scan structurally cannot have ───────────────────────────────────────
C3="$TMP/t3"; mkdir -p "$C3"
TMPDIR="$C3" "$BIN" "$R" --whereis=vanishedContourWalker --with-history >"$TMP/w1" 2>/dev/null
tr '<' '\n' < "$TMP/w1" | grep -q "^fate sym=\"vanishedContourWalker\" v=\"removed\" commit=\"$DEL_SHA\"" \
    && ok "whereis: a name no tree still carries reports v=\"removed\" with its commit" \
    || { no "whereis did not report the deleted name's fate"; tr '<' '\n' < "$TMP/w1" | grep -E '^(whereis|fate|history)'; }

tr '<' '\n' < "$TMP/w1" | grep -q '^fate .*p="relief.h"' \
    && ok "whereis: the fate row names the file the removal happened in" \
    || no "whereis fate row carries no path evidence"

TMPDIR="$C3" "$BIN" "$R" --whereis=neverBuiltPhantomWalker --with-history >"$TMP/w2" 2>/dev/null
tr '<' '\n' < "$TMP/w2" | grep -q '^fate .*v="never"' \
    && ok "whereis: a name this repo never had reports v=\"never\" (not conflated with deleted)" \
    || { no "whereis did not report v=\"never\""; tr '<' '\n' < "$TMP/w2" | grep -E '^(whereis|fate)'; }

TMPDIR="$C3" "$BIN" "$R" --whereis=vanishedContourWalker >"$TMP/w3" 2>/dev/null
grep -q '<fate ' "$TMP/w3" \
    && no "whereis emitted a <fate> row without --with-history (the probe must be opt-in)" \
    || ok "whereis: no fate row on the default path"

# whereis warm == cold too (it shares the same blob — and reuses whatever doc-drift already built)
C4="$TMP/t4"; mkdir -p "$C4"
TMPDIR="$C4" "$BIN" "$R" --whereis=vanishedContourWalker --with-history >"$TMP/wc" 2>/dev/null
TMPDIR="$C4" "$BIN" "$R" --whereis=vanishedContourWalker --with-history >"$TMP/ww" 2>/dev/null
cmp -s "$TMP/wc" "$TMP/ww" && ok "whereis: warm == cold, byte-identical" || no "whereis warm/cold disagree"

# ONE blob serves both verbs: doc-drift built it above in t2; whereis must not write a second family member.
nblob="$( find "$C4" -name 'ripwire-qhist-*.bin' | wc -l | tr -d ' ' )"
[ "$nblob" = "1" ] && ok "one (repo, HEAD sha) blob serves every question on that commit" \
                   || no "expected 1 qhist blob for one HEAD, found $nblob"

# ── 6) degrade: a NON-GIT root must fall back, loudly, never answer "never" for everything ────────────
mkdir -p "$TMP/plainroot"
cp "$R/relief.h" "$R/PLAN_relief.md" "$TMP/plainroot/" 2>/dev/null
C5="$TMP/t5"; mkdir -p "$C5"
TMPDIR="$C5" "$BIN" "$TMP/plainroot" --doc-drift --with-history --detail=999 >"$TMP/nogit" 2>"$TMP/nogit.err"
grep -q '<history probed="0" r="not-a-git-repo"/>' "$TMP/nogit" \
    && ok "a non-git root reports probed=\"0\" instead of pretending to know" \
    || { no "no probed=0 history element on a non-git root"; tr '<' '\n' < "$TMP/nogit" | grep '^history'; }
grep -q 'with-history' "$TMP/nogit.err" \
    && ok "…and says so on stderr" || no "the non-git degrade was silent on stderr"
rows "$TMP/nogit" | grep -q 'why="undefined"' \
    && ok "…and the mention lane falls back to why=\"undefined\", not to a false \"never\"" \
    || { no "the non-git fallback did not preserve the pre-flag verdict"; rows "$TMP/nogit"; }

# ── 7) G4: well-formed, minified XML for both verbs under the flag ────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/hist" 2>/dev/null && ok "doc-drift --with-history XML well-formed" || no "doc-drift --with-history XML malformed"
    xmllint --noout "$TMP/w1"   2>/dev/null && ok "whereis --with-history XML well-formed"   || no "whereis --with-history XML malformed"
else
    ok "xmllint unavailable — well-formedness skipped"
fi
[ "$( grep -c '' "$TMP/hist" )" -le 1 ] && ok "output is minified (no stray newlines)" || no "output contains newlines outside CDATA"

# ── 8) L10: a symbol still on HEAD must never carry <fate v="removed"> ─────────────────────────────────
# The oracle's line-removal walk cannot tell "the SYMBOL left" from "a DOC QUOTING the symbol left" — both
# are a removed line carrying the name. A stale capture/plan file that once quoted a live helper and was
# later deleted is exactly that: the symbol is untouched on HEAD, but the oracle's newest removal is the
# doc's deletion, and it used to be printed verbatim as v="removed" underneath on-head="1" — a symbol that
# plainly still exists reported as gone. --whereis's own TREE scan already knows better (on-head=); the fix
# makes the fate row defer to it instead of contradicting it.
R2="$TMP/repo2"; mkdir -p "$R2"
export GIT_AUTHOR_DATE="2026-02-03T00:00:00Z" GIT_COMMITTER_DATE="2026-02-03T00:00:00Z"
git -C "$R2" init -q -b main
git -C "$R2" config commit.gpgsign false
cat > "$R2/relief.h" <<'EOF'
inline int stableOnHeadHelper( int value )
{
    return value + 1;
}
EOF
cat > "$R2/docs_capture.md" <<'EOF'
`stableOnHeadHelper` shows up in the capture as a quoted example.
EOF
git -C "$R2" add -A >/dev/null
git -C "$R2" commit -qm "base: helper + a doc quoting it"
export GIT_AUTHOR_DATE="2026-02-09T00:00:00Z" GIT_COMMITTER_DATE="2026-02-09T00:00:00Z"
rm "$R2/docs_capture.md"
git -C "$R2" commit -qam "drop the stale capture doc (the helper itself is untouched)"

C6="$TMP/t6"; mkdir -p "$C6"
TMPDIR="$C6" "$BIN" "$R2" --whereis=stableOnHeadHelper --with-history >"$TMP/w4" 2>/dev/null
grep -q 'on-head="1"' "$TMP/w4" \
    && ok "L10 fixture sanity: stableOnHeadHelper is on-head=1 (it is still defined in relief.h)" \
    || { no "L10 fixture broken: expected on-head=1"; cat "$TMP/w4"; }
grep -q 'head_labels="index"' "$TMP/w4" \
    && ok "L10 fixture sanity: head_labels=\"index\" (the parsed index, not just text, confirms the def)" \
    || { no "L10 fixture broken: expected head_labels=\"index\""; cat "$TMP/w4"; }
grep -q '<fate ' "$TMP/w4" \
    && { no "whereis emitted <fate> for an index-confirmed HEAD definition (the doc deletion was mistaken for the symbol's)"; tr '<' '\n' < "$TMP/w4" | grep fate; } \
    || ok "L10: no <fate> row for an index-confirmed HEAD definition"

# …and the ORIGINAL fixture's true positive (vanishedContourWalker: deleted from relief.h, only a still-live
# PLAN doc quotes it — on-head=1 lexically, but the index confirms no def) must still fire, unchanged: this
# is real rot (a plan pointing at dead code) and the fix must not silence it along with the false positive.
grep -q 'head_labels="lexical"' "$TMP/w1" \
    && ok "L10 regression check: the PLAN-doc-only fixture stays head_labels=\"lexical\" (no index-confirmed def)" \
    || { no "L10 regression check: expected head_labels=\"lexical\" on the PLAN-doc-only fixture"; cat "$TMP/w1"; }

if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/w4" 2>/dev/null && ok "L10 fixture: whereis --with-history XML well-formed" || no "L10 fixture: whereis --with-history XML malformed"
fi

[ $fail -eq 0 ] && echo "historyoraclecheck: ALL PASS" || echo "historyoraclecheck: FAILURES"
exit $fail

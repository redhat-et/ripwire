#!/usr/bin/env bash
# crossrefdegradecheck.sh — the gate for the ways --stray-content / --whereis / --plan (src/crossref.h,
# src/landingplan.h) can report a CONFIDENT answer they did not earn.
#
#   test/crossrefdegradecheck.sh
#   CTXPACK_BIN=asan/ctxpack test/crossrefdegradecheck.sh
#
# Five independent claims, each of which was FALSE before this gate existed:
#
#   1) A ref whose analysis FAILED must not render as the reassuring answer. `analyzeRef` returns early
#      with ok=false when there is no merge-base, and the emitter then printed RefRow::verdict's default —
#      Verdict::Merged. A SHALLOW clone has no merge-base for any branch, and actions/checkout is shallow by
#      default, so in CI that read as "every branch is fully merged, nothing to see". Now: v="unknown".
#   2) The header counters must RECONCILE with refs=. A degraded ref landed in none of the three buckets, so
#      unmerged+superseded+merged silently failed to add up. Now there is a fourth bucket, unknown=.
#   3) --plan must SURFACE such a ref. It selected `verdict == Unmerged`, so a degraded ref was neither
#      scouted, nor bounded, nor emitted as <excluded> (that fires only for Superseded), nor counted — a
#      branch with real orphan work appearing NOWHERE in the report whose entire purpose is "which branches
#      still hold real work". Now: an explicit <undetermined> row plus undetermined= on the root element.
#   4) The <more N=> contract must be ARITHMETICALLY TRUE: shown + dropped == the total, always. The loop
#      did `if( shown++ >= cap ) break;` and then subtracted `shown` (= cap+1), under-reporting every drop by
#      exactly one; and at exactly cap+1 items `size > shown` went false, so the element vanished ENTIRELY
#      and one row disappeared unmarked. Both the general case and that boundary are pinned here — nothing
#      in test/ pinned any more= count before, which is why the bug survived.
#   5) Two adjacent ways a real hit is reported as no hit at all: a symbol defined on an UNTERMINATED final
#      line (the scan only evaluated on '\n', so hits="0" — which the help text says means "this repo never
#      had the name"), and a branch whose name legally contains '|' (the for-each-ref parse split on it and
#      handed the wrong field back as the tip sha, routing the ref into claim 1's degraded path).
#
# Plus: --stray-content's per-ref git plumbing now runs on a thread pool, so DETERMINISM is re-pinned here
# over repeated runs rather than assumed.
#
# The fixtures are BUILT here, not committed: these verbs read git refs, so the corpus has to be a real
# repository with a real ref graph. Fixed author/committer dates keep it byte-reproducible.
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "crossrefdegradecheck: git unavailable — skipping"; exit 0; }

export GIT_AUTHOR_NAME=ctxpack GIT_AUTHOR_EMAIL=ctxpack@example.invalid
export GIT_COMMITTER_NAME=ctxpack GIT_COMMITTER_EMAIL=ctxpack@example.invalid
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

# attr NAME < file  — the value of XML attribute NAME on the first ELEMENT that carries it. The comment
# filter is load-bearing, not tidiness: these verbs' help comments quote attribute syntax verbatim (whereis's
# says `hits="0" on its own does not distinguish...`), so an unfiltered scan reads the PROSE, not the answer.
attr(){ tr '<' '\n' | grep -v '^!--' | sed -n "s/.* $1=\"\([^\"]*\)\".*/\1/p" | head -1; }
# count TAG < file  — how many times element TAG opens
count_of(){ tr '<' '\n' | grep -v '^!--' | grep -c "^$1 "; }

echo "crossrefdegradecheck: BIN=$BIN"

# ══ fixture A: a SHALLOW clone — the CI default, and the case that reported every branch as merged ═══════
#
# `side` carries two lines of genuinely unmerged work. The shallow clone keeps one commit per ref, so the
# two histories share no commit and `merge-base side HEAD` fails — exactly the state actions/checkout
# produces without fetch-depth: 0.
SRC="$TMP/src"; mkdir -p "$SRC"
s(){ git -C "$SRC" "$@" >/dev/null 2>&1; }
s init -q -b main
s config commit.gpgsign false
printf 'int base( void )\n{\n    return 1;\n}\n' > "$SRC/a.c"
s add a.c
s commit -qm base
s checkout -qb side
printf 'int base( void )\n{\n    return 1;\n}\n\nint sideOnlyThing( void )\n{\n    return 42;\n}\n' > "$SRC/a.c"
s commit -qam "side-only work"
s checkout -q main
printf 'int base( void )\n{\n    return 1;\n}\n\nint mainWork( void )\n{\n    return 7;\n}\n' > "$SRC/a.c"
s commit -qam "live-line work"

SHALLOW="$TMP/shallow"
git clone -q --depth 1 "file://$SRC" "$SHALLOW" >/dev/null 2>&1
git -C "$SHALLOW" fetch -q --depth 1 origin side:side >/dev/null 2>&1

if git -C "$SHALLOW" merge-base side HEAD >/dev/null 2>&1; then
    echo "  SKIP  this git built a merge-base for the shallow fixture — the degrade path is unreachable here"
else
    "$BIN" "$SHALLOW" --stray-content >"$TMP/shallow.xml" 2>/dev/null
    SX="$( cat "$TMP/shallow.xml" )"

    # 1) the verdict itself — the whole point: NOT "merged"
    V="$( printf '%s' "$SX" | tr '<' '\n' | grep '^ref name="side"' | sed -n 's/.* v="\([a-z]*\)".*/\1/p' )"
    OKA="$( printf '%s' "$SX" | tr '<' '\n' | grep '^ref name="side"' | sed -n 's/.* ok="\([01]\)".*/\1/p' )"
    [ "$V" = "unknown" ] && ok "shallow clone: a ref with no merge-base reports v=\"unknown\"" \
                         || no "shallow clone: ref side reports v=\"$V\" (want unknown — never the reassuring answer)"
    [ "$OKA" = "0" ]     && ok "shallow clone: the failed analysis is flagged ok=\"0\"" \
                         || no "shallow clone: ok=\"$OKA\" (want 0)"
    printf '%s' "$SX" | grep -q 'v="merged"' && no "shallow clone: something still claims v=\"merged\"" \
                                             || ok "shallow clone: nothing claims v=\"merged\""

    # 2) the counters must reconcile with refs= — the first visible symptom was that they did not
    R_REFS="$( printf '%s' "$SX" | attr refs )"
    R_UNM="$(  printf '%s' "$SX" | attr unmerged )"
    R_SUP="$(  printf '%s' "$SX" | attr superseded )"
    R_MRG="$(  printf '%s' "$SX" | attr merged )"
    R_UNK="$(  printf '%s' "$SX" | attr unknown )"
    if [ -z "$R_UNK" ]; then
        no "shallow clone: the header carries no unknown= bucket, so the counters cannot reconcile"
    else
        SUM=$(( R_UNM + R_SUP + R_MRG + R_UNK ))
        [ "$SUM" = "$R_REFS" ] && ok "header buckets reconcile: unmerged+superseded+merged+unknown = $SUM = refs=$R_REFS" \
                               || no "header buckets do NOT reconcile: $R_UNM+$R_SUP+$R_MRG+$R_UNK = $SUM but refs=$R_REFS"
        [ "$R_UNK" -ge 1 ] && ok "the degraded ref is COUNTED (unknown=$R_UNK), not silently bucketless" \
                           || no "unknown=$R_UNK — the degraded ref landed in no bucket"
    fi

    # 3) --plan must surface it rather than dropping it out of every list
    "$BIN" "$SHALLOW" --stray-content --plan >"$TMP/plan.xml" 2>/dev/null
    PX="$( cat "$TMP/plan.xml" )"
    P_UND="$( printf '%s' "$PX" | attr undetermined )"
    printf '%s' "$PX" | tr '<' '\n' | grep -q '^undetermined name="side"' \
        && ok "plan: the unanalysable ref is surfaced as its own <undetermined> row" \
        || no "plan: ref side appears in NO list — the report whose purpose is \"which branches hold real work\" hides it"
    [ "${P_UND:-0}" -ge 1 ] 2>/dev/null && ok "plan: undetermined=$P_UND on the root element" \
                                        || no "plan: undetermined=\"${P_UND:-<absent>}\" (want >=1)"
    # and it must NOT be miscounted as a clean/handled ref
    [ "$( printf '%s' "$PX" | attr merged )" = "0" ] && ok "plan: the unanalysable ref is not counted as merged" \
                                                     || no "plan: merged= counts a ref that was never analysed"
fi

# ══ fixture B: the <more N=> contract, including the exact cap+1 boundary ════════════════════════════════
#
# kWhereisHits = 60. Two repos: one with exactly 61 hits (the boundary at which the element used to vanish
# outright) and one with 82 (the general case, which used to under-report by exactly one).
morecheck(){
    hitcount="$1"; label="$2"
    W="$TMP/w$hitcount"; mkdir -p "$W"
    w(){ git -C "$W" "$@" >/dev/null 2>&1; }
    w init -q -b main
    w config commit.gpgsign false
    : > "$W/hits.c"
    i=0
    while [ "$i" -lt "$hitcount" ]; do printf 'int slot%d = boundaryProbeSym;\n' "$i" >> "$W/hits.c"; i=$(( i + 1 )); done
    w add hits.c
    w commit -qm hits

    "$BIN" "$W" --whereis=boundaryProbeSym >"$TMP/more.$hitcount.xml" 2>/dev/null
    MX="$( cat "$TMP/more.$hitcount.xml" )"
    H="$( printf '%s' "$MX" | attr hits )"
    SHOWN="$( printf '%s' "$MX" | count_of hit )"
    MORE="$( printf '%s' "$MX" | tr '<' '\n' | grep -v '^!--' | sed -n 's/^more hits="\([0-9]*\)".*/\1/p' | head -1 )"
    MORE="${MORE:-0}"

    [ "$H" = "$hitcount" ] || no "$label: hits=\"$H\" but the fixture has $hitcount occurrences"
    if [ "$(( SHOWN + MORE ))" = "$H" ]; then
        ok "$label: shown($SHOWN) + more($MORE) == hits($H) — nothing dropped without a number"
    else
        no "$label: shown($SHOWN) + more($MORE) = $(( SHOWN + MORE )) != hits($H) — rows dropped unmarked"
    fi
    [ "$SHOWN" -le 60 ] || no "$label: $SHOWN rows printed, above the 60 cap"
}
morecheck 61 "whereis <more> at the cap+1 boundary"
morecheck 82 "whereis <more> in the general case"

# --detail lifts the cap: every row present, and NO <more/> claiming a phantom drop
"$BIN" "$TMP/w82" --whereis=boundaryProbeSym --detail=1 >"$TMP/more.detail.xml" 2>/dev/null
DX="$( cat "$TMP/more.detail.xml" )"
D_SHOWN="$( printf '%s' "$DX" | count_of hit )"
D_HITS="$(  printf '%s' "$DX" | attr hits )"
[ "$D_SHOWN" = "$D_HITS" ] && ok "whereis --detail: all $D_SHOWN rows shown" \
                           || no "whereis --detail: $D_SHOWN of $D_HITS rows shown"
printf '%s' "$DX" | tr '<' '\n' | grep -q '^more ' && no "whereis --detail: a <more/> element claims a drop that did not happen" \
                                                   || ok "whereis --detail: no phantom <more/>"

# ══ fixture C: a symbol on an UNTERMINATED final line, and a branch name containing a legal '|' ══════════
C="$TMP/c"; mkdir -p "$C"
c(){ git -C "$C" "$@" >/dev/null 2>&1; }
c init -q -b main
c config commit.gpgsign false
printf 'int anchor( void )\n{\n    return 0;\n}\n' > "$C/base.c"
c add base.c
c commit -qm base

# NO trailing newline on the last line — legal git content, and the line the definition lives on
printf 'int leading( void )\n{\n    return 1;\n}\nint tailDefinedSym( void ) { return 2; }' > "$C/tail.c"
c add tail.c
c commit -qm "a definition on an unterminated final line"

"$BIN" "$C" --whereis=tailDefinedSym >"$TMP/tail.xml" 2>/dev/null
TXH="$( cat "$TMP/tail.xml" | attr hits )"
[ "${TXH:-0}" -ge 1 ] 2>/dev/null \
    && ok "whereis finds a symbol on an unterminated final line (hits=$TXH)" \
    || no "whereis reports hits=\"${TXH:-?}\" for a symbol on an unterminated final line — indistinguishable from \"this repo never had the name\""

# a branch whose name legally contains '|' (git forbids space ~ ^ : ? * [ \ and control bytes — not the pipe)
c checkout -qb 'feat|piped'
printf 'int pipedBranchOnly( void )\n{\n    return 99;\n}\n' > "$C/piped.c"
c add piped.c
c commit -qm "work that only the pipe-named branch has"
c checkout -q main

if git -C "$C" rev-parse --verify 'feat|piped' >/dev/null 2>&1; then
    "$BIN" "$C" --stray-content >"$TMP/piped.xml" 2>/dev/null
    PIX="$( cat "$TMP/piped.xml" )"
    PV="$( printf '%s' "$PIX" | tr '<' '\n' | grep '^ref name="feat|piped"' | sed -n 's/.* v="\([a-z]*\)".*/\1/p' )"
    POK="$( printf '%s' "$PIX" | tr '<' '\n' | grep '^ref name="feat|piped"' | sed -n 's/.* ok="\([01]\)".*/\1/p' )"
    [ "$PV" = "unmerged" ] && ok "a branch named with a legal '|' is analysed correctly (v=\"unmerged\")" \
                           || no "branch feat|piped reports v=\"$PV\" (want unmerged — the ref name parse split on a legal byte)"
    [ "$POK" = "1" ]       && ok "a branch named with a legal '|' does not fall into the degraded path" \
                           || no "branch feat|piped reports ok=\"$POK\" — its tip sha was mis-parsed"
else
    echo "  SKIP  this git/filesystem refused a branch name containing '|'"
fi

# ══ the stray-file <more files=> contract, and determinism under the threaded plumbing ═══════════════════
# 13 changed files on one branch, against a per-ref display cap of kStrayFilesPerRef = 12.
F="$TMP/f"; mkdir -p "$F"
f(){ git -C "$F" "$@" >/dev/null 2>&1; }
f init -q -b main
f config commit.gpgsign false
printf 'int anchor( void )\n{\n    return 0;\n}\n' > "$F/anchor.c"
f add anchor.c
f commit -qm base
f checkout -qb wide
i=0
while [ "$i" -lt 13 ]; do printf 'int wideOnly%d( void )\n{\n    return %d;\n}\n' "$i" "$i" > "$F/w$i.c"; i=$(( i + 1 )); done
f add .
f commit -qm "13 files of stray work"
f checkout -q main

"$BIN" "$F" --stray-content >"$TMP/wide.xml" 2>/dev/null
WX="$( cat "$TMP/wide.xml" )"
W_FILES="$( printf '%s' "$WX" | tr '<' '\n' | grep '^ref name="wide"' | sed -n 's/.* files="\([0-9]*\)".*/\1/p' )"
W_SHOWN="$( printf '%s' "$WX" | count_of file )"
W_MORE="$( printf '%s' "$WX" | tr '<' '\n' | sed -n 's/^more files="\([0-9]*\)".*/\1/p' | head -1 )"
W_MORE="${W_MORE:-0}"
[ "$(( W_SHOWN + W_MORE ))" = "${W_FILES:-0}" ] \
    && ok "stray-content <more files=>: shown($W_SHOWN) + more($W_MORE) == files($W_FILES)" \
    || no "stray-content <more files=>: shown($W_SHOWN) + more($W_MORE) != files(${W_FILES:-?})"

# determinism: the per-ref git plumbing is now threaded, so this is a real claim, not a formality
"$BIN" "$F" --stray-content >"$TMP/d1" 2>/dev/null
"$BIN" "$F" --stray-content >"$TMP/d2" 2>/dev/null
"$BIN" "$F" --stray-content >"$TMP/d3" 2>/dev/null
if cmp -s "$TMP/d1" "$TMP/d2" && cmp -s "$TMP/d1" "$TMP/d3"; then
    ok "stray-content is byte-identical across runs with the threaded git plumbing"
else
    no "stray-content is NON-DETERMINISTIC under the threaded git plumbing"
fi

# ══ no crossref verb may WRITE anything, anywhere ═══════════════════════════════════════════════════════
# The sibling bug this mirrors: --pr-context handed a raw user ref to `git diff`, which honours
# --output=FILE, and a file OUTSIDE the repo was truncated and overwritten at exit 0. Every revision token
# crossref.h passes to git is git's own output, so the exposure is latent — this pins it that way. A
# regression that reintroduces an unvalidated token into `git diff`/`ls-tree`/`merge-base` trips this.
VICTIM="$TMP/victim.txt"
printf 'untouched sentinel\n' > "$VICTIM"
VICTIM_BEFORE="$( cksum < "$VICTIM" )"
WT_BEFORE="$( git -C "$C" status --porcelain 2>/dev/null | cksum )"
REFS_BEFORE="$( git -C "$C" for-each-ref --format='%(refname) %(objectname)' 2>/dev/null | cksum )"

"$BIN" "$C" --stray-content              >/dev/null 2>&1
"$BIN" "$C" --stray-content --plan       >/dev/null 2>&1
"$BIN" "$C" --whereis=pipedBranchOnly    >/dev/null 2>&1

[ "$( cksum < "$VICTIM" )" = "$VICTIM_BEFORE" ] && ok "read-only: a file outside the repo is untouched" \
                                                || no "read-only: a crossref verb WROTE to a file outside the repo"
[ "$( git -C "$C" status --porcelain 2>/dev/null | cksum )" = "$WT_BEFORE" ] \
    && ok "read-only: the working tree is unchanged" || no "read-only: a crossref verb mutated the working tree"
[ "$( git -C "$C" for-each-ref --format='%(refname) %(objectname)' 2>/dev/null | cksum )" = "$REFS_BEFORE" ] \
    && ok "read-only: no ref was created, moved or deleted" || no "read-only: a crossref verb wrote a ref"

# G4: every emitted document must survive xmllint
if command -v xmllint >/dev/null 2>&1; then
    g4=0
    for x in "$TMP"/*.xml; do xmllint --noout "$x" >/dev/null 2>&1 || { g4=1; echo "     bad: $x"; }; done
    [ "$g4" = "0" ] && ok "G4: every emitted document is xmllint-clean" || no "G4: some emitted document is malformed"
fi

[ "$fail" = "0" ] && echo "crossrefdegradecheck: ALL PASS" || echo "crossrefdegradecheck: FAILURES"
exit "$fail"

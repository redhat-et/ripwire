#!/usr/bin/env bash
# sincecochangecheck.sh — gate for --since=REV|DATE (196e695) scoping verbs OTHER than --hotspots.
# test/sincecheck.sh proves --since=HEAD~3 scopes --hotspots correctly (its own gate, not duplicated
# here). --help says --since also scopes --cochange and --rank-by=churn — this gate proves those two,
# PLUS the DATE form (not just REV), PLUS the "--since legitimately matches zero commits" corner (which
# turns out to behave INCONSISTENTLY across verbs — see the REAL BUG below).
#
# REAL BUG FOUND — NOW FIXED in d98ffed. WAS: when --since scopes to a window with ZERO matching
# commits (a valid, deterministic outcome — not "git is broken"), repo-wide --cochange (src/main.cpp:
# 1124) and --hotspots (src/main.cpp:~1017) both checked `if (sets.empty())` and printed the SAME
# message as an actual missing-git-repo error — "ctxpack --VERB: git unavailable / no history (need a
# git repo)" — and exit 1, conflating "there is no git repository at all" with "there IS a git repo,
# --since is valid, it just matched nothing." The single-file form (`--cochange=FILE`) never had this
# bug (it degraded to `commits="0" partners="0"` exit 0). FIX (d98ffed): the empty-window case now
# emits a clean empty result — repo-wide --cochange → `<cochange pairs="0" commits="0">` exit 0, and
# --hotspots → `<hotspots ... ranked="0" commits="0">` exit 0 — matching the single-file path. A
# GENUINE no-repo / no-history dir still errors with "git unavailable / no history" + exit 1 (asserted
# below). This gate now asserts the consistent empty-window behavior across --hotspots and --cochange.
#
# §P8 UPDATE (2026-07-28): both empty-window roots this gate pins now also carry ` shown="0" capped="0"`
# — `<cochange pairs="0" commits="0" shown="0" capped="0">` and `<hotspots ... ranked="0" commits="0"
# shown="0" capped="0">`. That is the same §P8 rule the non-empty runs got (the root element always states
# how many rows follow, so total-vs-emitted reconciles); on an empty window it is trivially 0 of 0, and
# capped="0" is the positive statement that NOTHING was dropped, which is exactly the claim this gate cares
# about. The assertions below grep the individual attributes (`pairs="0"`, `commits="0"`, `ranked="0"`)
# rather than whole opening tags, so they were unaffected — keep them attribute-wise if you edit them.
#
# DATE-form gotcha discovered while building this gate: `git log --since=2999-01-01` (Apple Git 2.39.5)
# does NOT correctly exclude all commits — it appears to mis-parse far-future 4-digit years starting
# around 2100 and returns ALL commits (a git/approxidate quirk, not a ctxpack bug). This gate therefore
# uses 2030-01-01 (safely future relative to any real commit date, safely below the ~2100 wrap) as its
# "zero commits in window" date — a value that will need bumping well before 2030 arrives.
#
# Fixture: a throwaway git repo (mktemp, never committed) with two co-changing pairs in DISJOINT commit
# windows — A+B in the first 3 commits, C+D in the last 3 — built fresh here per run.
#
# Usage:  test/sincecochangecheck.sh   |   CTXPACK_BIN=asan/ctxpack test/sincecochangecheck.sh
# Exits non-zero on any FAIL. Does NOT edit regression.sh, sincecheck.sh, or any existing test file.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "sincecochangecheck: BIN=$BIN"

REPO="$( mktemp -d )"; trap 'rm -rf "$REPO"' EXIT
cd "$REPO" || exit 1
git init -q; git config user.email x@y; git config user.name x
# A+B co-change in 3 EARLY commits (edited together each time)
for i in 1 2 3; do
    printf 'int a(int x){ return x+%d; }\n' "$i" > A.cpp
    printf 'int b(int x){ return x+%d; }\n' "$i" > B.cpp
    git add A.cpp B.cpp; git commit -qm "AB$i"
done
# C+D co-change in the LAST 3 commits — disjoint window from A/B
for i in 1 2 3; do
    printf 'int c(int x){ return x+%d; }\n' "$i" > C.cpp
    printf 'int d(int x){ return x+%d; }\n' "$i" > D.cpp
    git add C.cpp D.cpp; git commit -qm "CD$i"
done
cd "$ROOT" || exit 1

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --cochange --since=HEAD~3 (REV form) scopes to only the in-window pair ==="
# ═══════════════════════════════════════════════════════════════════════════
CC_ALL="$( "$BIN" "$REPO" --cochange --no-cache 2>/dev/null )"
printf '%s' "$CC_ALL" | grep -q 'a="[^"]*A.cpp" b="[^"]*B.cpp"' && printf '%s' "$CC_ALL" | grep -q 'a="[^"]*C.cpp" b="[^"]*D.cpp"' \
    && ok "all-history --cochange: both A+B and C+D pairs present" \
    || no "all-history --cochange should list both pairs: $CC_ALL"

CC_WIN="$( "$BIN" "$REPO" --cochange --since=HEAD~3 --no-cache 2>/dev/null )"
if printf '%s' "$CC_WIN" | grep -q 'a="[^"]*C.cpp" b="[^"]*D.cpp"' && ! printf '%s' "$CC_WIN" | grep -q 'A.cpp'; then
    ok "--cochange --since=HEAD~3 scopes to the window (C+D only, A/B's earlier commits dropped)"
else
    no "--cochange --since=HEAD~3 should keep only C+D: $CC_WIN"
fi
printf '%s' "$CC_WIN" | grep -q 'pairs="1"' && ok "--cochange --since=HEAD~3 reports exactly pairs=1" || no "--cochange --since=HEAD~3 pair count wrong: $CC_WIN"

# determinism of the REV-form window
CC_WIN2="$( "$BIN" "$REPO" --cochange --since=HEAD~3 --no-cache 2>/dev/null )"
[ "$CC_WIN" = "$CC_WIN2" ] && ok "--cochange --since=HEAD~3 deterministic run-to-run" || no "--cochange --since=HEAD~3 non-deterministic"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --rank-by=churn --since=HEAD~3 scopes churn to the window ==="
# ═══════════════════════════════════════════════════════════════════════════
# Under all-history, A/B/C/D each have exactly 3 touching commits -> equal churn -> equal k (symmetric fixture).
# Under --since=HEAD~3, ONLY C/D's commits are in-window -> A/B get ZERO in-window churn while C/D get 3.
k_of(){ printf '%s' "$1" | grep -oE "n=\"$2\"[^/]*k=\"[0-9.]+\"" | grep -oE 'k="[0-9.]+"' | grep -oE '[0-9.]+' | head -1; }

RB_ALL="$( "$BIN" "$REPO" --rank-by=churn --no-cache 2>/dev/null )"
ka_all="$( k_of "$RB_ALL" a )"; kc_all="$( k_of "$RB_ALL" c )"
[ -n "$ka_all" ] && [ -n "$kc_all" ] && ok "all-history --rank-by=churn: parsed k for both a and c (ka=$ka_all kc=$kc_all)" || no "could not parse all-history churn k values"

RB_WIN="$( "$BIN" "$REPO" --rank-by=churn --since=HEAD~3 --no-cache 2>/dev/null )"
ka_win="$( k_of "$RB_WIN" a )"; kc_win="$( k_of "$RB_WIN" c )"
if [ -n "$ka_win" ] && [ -n "$kc_win" ]; then
    # a() has ZERO in-window commits, c() has 3 -> under the windowed churn prior, c's share must be
    # strictly greater than a's (the window changed the ranking signal), whereas in all-history they tied.
    awk -v ka="$ka_win" -v kc="$kc_win" 'BEGIN{ exit !(kc > ka) }' \
        && ok "--rank-by=churn --since=HEAD~3: c (in-window, 3 commits) outranks a (0 in-window commits): ka=$ka_win kc=$kc_win" \
        || no "--rank-by=churn --since=HEAD~3 did not favor the in-window file: ka=$ka_win kc=$kc_win"
    awk -v ka1="$ka_all" -v ka2="$ka_win" 'BEGIN{ exit !(ka2 < ka1) }' \
        && ok "--rank-by=churn --since=HEAD~3: a's k DROPPED vs all-history (window excludes its only commits): all=$ka_all win=$ka_win" \
        || no "--rank-by=churn --since=HEAD~3: a's k should drop when its commits fall outside the window: all=$ka_all win=$ka_win"
else
    no "could not parse windowed churn k values: $RB_WIN"
fi

# determinism of the windowed churn ranking
RB_WIN2="$( "$BIN" "$REPO" --rank-by=churn --since=HEAD~3 --no-cache 2>/dev/null )"
[ "$RB_WIN" = "$RB_WIN2" ] && ok "--rank-by=churn --since=HEAD~3 deterministic run-to-run" || no "--rank-by=churn --since=HEAD~3 non-deterministic"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --since=DATE form (not just REV) on --cochange ==="
# ═══════════════════════════════════════════════════════════════════════════
# A safely-past date (well before any commit in this freshly-created repo) must include ALL commits —
# deterministically true for any repo created "now", regardless of when "now" is.
CC_PAST="$( "$BIN" "$REPO" --cochange --since=2000-01-01 --no-cache 2>/dev/null )"
printf '%s' "$CC_PAST" | grep -q 'pairs="2"' \
    && ok "--since=2000-01-01 (DATE form, safely past) includes ALL commits: pairs=2" \
    || no "--since=2000-01-01 should include everything (pairs=2): $CC_PAST"

# A safely-future date (2030 — see the header note on the ~2100 git approxidate wraparound quirk) must
# exclude every commit in this repo (all created "now"). FIXED (d98ffed): git IS available and history
# DOES exist, so this is NOT an error — repo-wide --cochange degrades to an honest empty result
# (pairs="0" commits="0") with exit 0, matching the single-file --cochange=FILE path.
CC_FUT="$( "$BIN" "$REPO" --cochange --since=2030-01-01 --no-cache 2>/dev/null )"; CC_FUT_RC=$?
CC_FUT_ERR="$( "$BIN" "$REPO" --cochange --since=2030-01-01 --no-cache 2>&1 >/dev/null )"
if [ "$CC_FUT_RC" -eq 0 ] && printf '%s' "$CC_FUT" | grep -q 'commits="0"' && printf '%s' "$CC_FUT" | grep -q 'pairs="0"'; then
    ok "repo-wide --cochange --since=2030-01-01 (empty window, git available) degrades cleanly to pairs=0 commits=0, exit 0"
else
    no "repo-wide --cochange --since=2030-01-01 should degrade cleanly (pairs=\"0\" commits=\"0\", exit 0), NOT error: rc=$CC_FUT_RC out=$CC_FUT err=$CC_FUT_ERR"
fi
# and it must NOT print the missing-repo error — the empty window is not a git-unavailable failure.
printf '%s' "$CC_FUT_ERR" | grep -q 'git unavailable / no history' \
    && no "repo-wide --cochange --since=2030-01-01 still prints the misleading 'git unavailable / no history' error on a valid empty window: $CC_FUT_ERR" \
    || ok "repo-wide --cochange --since=2030-01-01 does NOT conflate the empty window with a missing-repo error"

# SAME empty-window case on --hotspots — the fix wired it identically: honest empty result, exit 0.
HS_FUT="$( "$BIN" "$REPO" --hotspots --since=2030-01-01 --no-cache 2>/dev/null )"; HS_FUT_RC=$?
HS_FUT_ERR="$( "$BIN" "$REPO" --hotspots --since=2030-01-01 --no-cache 2>&1 >/dev/null )"
if [ "$HS_FUT_RC" -eq 0 ] && printf '%s' "$HS_FUT" | grep -q 'commits="0"' && printf '%s' "$HS_FUT" | grep -q 'ranked="0"'; then
    ok "repo-wide --hotspots --since=2030-01-01 (empty window, git available) degrades cleanly to ranked=0 commits=0, exit 0"
else
    no "repo-wide --hotspots --since=2030-01-01 should degrade cleanly (ranked=\"0\" commits=\"0\", exit 0), NOT error: rc=$HS_FUT_RC out=$HS_FUT err=$HS_FUT_ERR"
fi
printf '%s' "$HS_FUT_ERR" | grep -q 'git unavailable / no history' \
    && no "repo-wide --hotspots --since=2030-01-01 still prints the misleading 'git unavailable / no history' error on a valid empty window: $HS_FUT_ERR" \
    || ok "repo-wide --hotspots --since=2030-01-01 does NOT conflate the empty window with a missing-repo error"

# CONSISTENCY: the single-file --cochange=FILE form has ALWAYS handled the identical zero-commits case
# correctly (commits=0/partners=0, exit 0). The fix brought the repo-wide --cochange/--hotspots paths
# into line with it — assert the single-file baseline still holds.
CC_FUT_SINGLE="$( "$BIN" "$REPO" --cochange=A.cpp --since=2030-01-01 --no-cache 2>/dev/null )"; CC_FUT_SINGLE_RC=$?
[ "$CC_FUT_SINGLE_RC" -eq 0 ] && printf '%s' "$CC_FUT_SINGLE" | grep -q 'commits="0"' && printf '%s' "$CC_FUT_SINGLE" | grep -q 'partners="0"' \
    && ok "single-file --cochange=A.cpp --since=2030-01-01 degrades cleanly (commits=0 partners=0, exit 0) — repo-wide path now matches it" \
    || no "single-file --cochange=FILE --since=2030-01-01 regressed: rc=$CC_FUT_SINGLE_RC out=$CC_FUT_SINGLE"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== a GENUINE non-git dir still errors + exits nonzero (the fix preserved this) ==="
# ═══════════════════════════════════════════════════════════════════════════
# The fix must NOT have turned every git failure into a silent empty result: a dir with NO git repo
# and NO history is a real error and must still exit nonzero with the 'git unavailable' message.
NOGIT="$( mktemp -d )"
printf 'int q(int x){ return x+1; }\n' > "$NOGIT/q.cpp"
NG_CC="$( "$BIN" "$NOGIT" --cochange --no-cache 2>&1 >/dev/null )"; NG_CC_RC=$( "$BIN" "$NOGIT" --cochange --no-cache >/dev/null 2>&1; echo $? )
[ "$NG_CC_RC" -ne 0 ] && printf '%s' "$NG_CC" | grep -q 'git unavailable / no history' \
    && ok "non-git dir --cochange still errors (exit $NG_CC_RC, 'git unavailable / no history') — genuine no-repo not masked by the empty-window fix" \
    || no "non-git dir --cochange should still error nonzero with 'git unavailable': rc=$NG_CC_RC err=$NG_CC"
NG_HS="$( "$BIN" "$NOGIT" --hotspots --no-cache 2>&1 >/dev/null )"; NG_HS_RC=$( "$BIN" "$NOGIT" --hotspots --no-cache >/dev/null 2>&1; echo $? )
[ "$NG_HS_RC" -ne 0 ] && printf '%s' "$NG_HS" | grep -q 'git unavailable / no history' \
    && ok "non-git dir --hotspots still errors (exit $NG_HS_RC, 'git unavailable / no history') — genuine no-repo not masked by the empty-window fix" \
    || no "non-git dir --hotspots should still error nonzero with 'git unavailable': rc=$NG_HS_RC err=$NG_HS"
rm -rf "$NOGIT"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --since with an empty / minimal repo (no matching commits at all) ==="
# ═══════════════════════════════════════════════════════════════════════════
MINI="$( mktemp -d )"
( cd "$MINI" && git init -q && git config user.email x@y && git config user.name x
  echo 'int x(){return 1;}' > x.cpp && git add x.cpp && git commit -qm init )
# HEAD~3 doesn't resolve (only 1 commit exists) -> resolveSinceScope degrades to inactive -> all-history fallback.
MINI_CC="$( "$BIN" "$MINI" --cochange --since=HEAD~3 --no-cache 2>/dev/null )"; MINI_CC_RC=$?
[ "$MINI_CC_RC" -eq 0 ] && printf '%s' "$MINI_CC" | grep -q 'pairs="0"' \
    && ok "minimal repo: --cochange --since=HEAD~3 (unresolvable rev) degrades cleanly to pairs=0, exit 0" \
    || no "minimal repo --cochange --since=HEAD~3 should degrade cleanly: rc=$MINI_CC_RC out=$MINI_CC"
MINI_RB="$( "$BIN" "$MINI" --rank-by=churn --since=HEAD~3 --no-cache 2>/dev/null )"; MINI_RB_RC=$?
# §P8 (2026-07-28) — REPINNED from '<r>' to '<r[ >]': the map root now carries est_tokens="N" as a real
# attribute (the flagship map's own size used to be reachable only inside an XML comment). The literal
# '<r>' match had nothing to do with this gate's subject (an unresolvable --since rev degrading cleanly);
# it was just the cheapest "a map came out" probe, and it silently became a false FAIL. Attribute-agnostic
# now, so a future root attribute cannot break it again.
[ "$MINI_RB_RC" -eq 0 ] && printf '%s' "$MINI_RB" | grep -q '<r[ >]' \
    && ok "minimal repo: --rank-by=churn --since=HEAD~3 (unresolvable rev) still produces a valid ranked map, exit 0" \
    || no "minimal repo --rank-by=churn --since=HEAD~3 should degrade cleanly: rc=$MINI_RB_RC"
rm -rf "$MINI"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== shell safety: --since value with metacharacters, on --cochange (not just --hotspots) ==="
# ═══════════════════════════════════════════════════════════════════════════
rm -f "$REPO/PWNED_CC"
"$BIN" "$REPO" --cochange --since='HEAD~3; touch '"$REPO"'/PWNED_CC' --no-cache >/dev/null 2>&1
[ ! -f "$REPO/PWNED_CC" ] && ok "shell-metacharacter --since on --cochange executes nothing (quoted safely)" || no "shell injection via --since on --cochange!"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== xml well-formed ==="
# ═══════════════════════════════════════════════════════════════════════════
command -v xmllint >/dev/null 2>&1 && {
    printf '%s' "$CC_WIN" | xmllint --noout - 2>/dev/null && ok "xml well-formed (--cochange --since=HEAD~3)" || no "xml malformed (--cochange --since=HEAD~3)"
    printf '%s' "$RB_WIN" | xmllint --noout - 2>/dev/null && ok "xml well-formed (--rank-by=churn --since=HEAD~3)" || no "xml malformed (--rank-by=churn --since=HEAD~3)"
}

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== MUTATION: prove the assertions are load-bearing ==="
# ═══════════════════════════════════════════════════════════════════════════
MUT="$( ok(){ :; }; no(){ echo TRIPPED; }
        if printf '%s' "$CC_WIN" | grep -q 'pairs="99"'; then ok; else no; fi )"
[ "$MUT" = "TRIPPED" ] && ok "mutation self-test (asserting --cochange --since=HEAD~3 pairs=99 when it is really 1 correctly fails)" \
                       || no "mutation self-test broke — the pairs= assertion is not live"

MUT2="$( ok(){ :; }; no(){ echo TRIPPED; }
        awk -v ka="$ka_win" -v kc="$kc_win" 'BEGIN{ exit !(ka > kc) }' && ok || no )"
[ "$MUT2" = "TRIPPED" ] && ok "mutation self-test (asserting a>c churn ranking, the reverse of reality, correctly fails)" \
                        || no "mutation self-test broke — the churn ranking comparison is not live"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME CHECKS FAILED"
exit "$fail"

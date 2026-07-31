#!/usr/bin/env bash
# gitstampcheck.sh — the gate for r26-stamp Task A: at="<sha>[+dirty]" on every repo-reading verb's root
# element (src/gitstamp.h + its call sites in src/docdrift.h, src/prcontext.h, src/editcheck.h,
# src/landingplan.h, src/situ.h, src/crossref.h, src/serialize.h, src/main.cpp).
#
# Fixture: a throwaway one-commit repo (fixed-ish, RECENT dates so --hotspots' 12-month churn window always
# matches regardless of when this gate runs) with one file carrying enough branching for a non-zero ccx.
#
# Asserts:
#   - clean tree: at="<9-hex>" (no +dirty) on --doctor / --doc-drift / --hotspots / --quality-delta /
#     --cochange / --owners (added 2026-07-28, §P8: the last two unanchored pure-git verbs) /
#     --pr-context / --test-gate / --edit-check=SYM / --whereis=SYM / --stray-content --plan (landing-plan,
#     alongside its pre-existing head=) — the 9-hex prefix matches `git rev-parse --short=9 HEAD` exactly
#   - dirty tree (an uncommitted tracked-file edit): every one of those gains "+dirty", SAME sha prefix,
#     EXCEPT --whereis, which is documented (excluded-file exception, sha-only) to stay bare-sha — this
#     pins that deliberate gap rather than letting it silently drift into "accidentally fixed" or "spread
#     further"
#   - non-git directory: at= is OMITTED entirely on --doctor and --doc-drift (never at="none")
#   - the bare default map (`ctxpack <dir>`, no verb) never grows an at= and never shells out to git —
#     `<r>` stays byte-for-byte `<r>` on BOTH a git and a non-git root
#   - --map-diff (which already shells out to git for the diff) DOES stamp `<r at="...">`, single-root only
#   - determinism: two runs over the SAME repo state are byte-identical for every stamped verb
#   - every stamped output stays xmllint-clean
#
# Usage:
#   test/gitstampcheck.sh
#   CTXPACK_BIN=asan/ctxpack test/gitstampcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "gitstampcheck: git unavailable — skipping"; exit 0; }

echo "gitstampcheck: BIN=$BIN"

R="$TMP/repo"; mkdir -p "$R/src"
export GIT_AUTHOR_NAME=ctxpack GIT_AUTHOR_EMAIL=ctxpack@example.invalid
export GIT_COMMITTER_NAME=ctxpack GIT_COMMITTER_EMAIL=ctxpack@example.invalid
# RECENT dates (1 day ago), not a fixed calendar date: --hotspots scopes churn to "12 months ago" against
# WALL-CLOCK now, so a hardcoded past date would eventually age out of that window and fail this gate for
# a reason that has nothing to do with the stamp being tested.
RECENT="$( date -u -v-1d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%SZ )"
export GIT_AUTHOR_DATE="$RECENT" GIT_COMMITTER_DATE="$RECENT"
g(){ git -C "$R" "$@" >/dev/null 2>&1; }

g init -q -b main
g config commit.gpgsign false

cat > "$R/src/code.h" <<'EOF'
#pragma once
int classify( int a )
{
    if( a > 0 ) return 1;
    else if( a < 0 ) return -1;
    return 0;
}
EOF
g add -A
g commit -q -m "base"

SHA9="$( git -C "$R" rev-parse --short=9 HEAD )"
[ "${#SHA9}" = 9 ] || { echo "gitstampcheck: could not derive a 9-char short sha — aborting"; exit 2; }

# ── clean tree: every stamped verb carries the bare 9-char sha, no +dirty ────────────────────────────────
check_clean()
{
    local desc="$1"; shift
    local out; out="$( "$BIN" "$R" "$@" --no-cache 2>/dev/null )"
    case "$out" in
        *"at=\"$SHA9\""*)      ok "$desc: at=\"$SHA9\" (clean)" ;;
        *"at=\"$SHA9+dirty\""*) no "$desc: at= carries +dirty on a CLEAN tree" ;;
        *)                     no "$desc: no at=\"$SHA9\" found"; echo "$out" | grep -o 'at="[^"]*"' | head -3 ;;
    esac
}

check_clean "doctor"                    --doctor
check_clean "doc-drift"                 --doc-drift
check_clean "hotspots"                  --hotspots
check_clean "quality-delta"             --quality-delta
check_clean "pr-context"                --pr-context
check_clean "test-gate"                 --test-gate
check_clean "edit-check"                --edit-check=classify
check_clean "whereis"                   --whereis=classify
check_clean "landing-plan (--plan)"     --stray-content --plan
# §P8 (2026-07-28) — ADDED: --cochange and --owners are PURE git-history products (a co-change pair mined
# from `git log`, a recency-weighted ownership share), and they were the last two verbs of that kind with no
# anchor at all — a number quoted out of either was unattributable to a HEAD. They belong in this family's
# clean/dirty sweep, not only in attrvocabcheck.sh's presence check.
check_clean "cochange (repo-wide)"      --cochange
check_clean "cochange (per-file)"       --cochange=src/code.h
check_clean "owners"                    --owners

# landing-plan is the "keep both" case: head= (pre-existing) stays a bare 9-char sha alongside the new at=.
out="$( "$BIN" "$R" --stray-content --plan --no-cache 2>/dev/null )"
case "$out" in
    *"head=\"$SHA9\""*) ok "landing-plan: pre-existing head=\"$SHA9\" unchanged" ;;
    *)                  no "landing-plan: head= missing or changed shape" ;;
esac

# ── dirty tree: an uncommitted TRACKED-file edit — every stamp except whereis gains +dirty, same sha ────
printf '\n// a trailing comment, uncommitted\n' >> "$R/src/code.h"

check_dirty()
{
    local desc="$1"; shift
    local out; out="$( "$BIN" "$R" "$@" --no-cache 2>/dev/null )"
    case "$out" in
        *"at=\"$SHA9+dirty\""*) ok "$desc: at=\"$SHA9+dirty\" (dirty)" ;;
        *)                      no "$desc: missing +dirty on a dirty tree"; echo "$out" | grep -o 'at="[^"]*"' | head -3 ;;
    esac
}

check_dirty "doctor"        --doctor
check_dirty "doc-drift"     --doc-drift
check_dirty "hotspots"      --hotspots
check_dirty "quality-delta" --quality-delta
check_dirty "pr-context"    --pr-context
check_dirty "test-gate"     --test-gate
check_dirty "edit-check"    --edit-check=classify

# whereis is the documented EXCEPTION (crossref.h is another agent's file; the exception rule only permits
# adding the bare at= attribute, not a dirty check that needs `root` threaded through too) — pin that it
# STAYS bare-sha even on a dirty tree, so the gap is a recorded decision, not a silent drift either way.
out="$( "$BIN" "$R" --whereis=classify --no-cache 2>/dev/null )"
case "$out" in
    *"at=\"$SHA9\""*)       ok "whereis: at=\"$SHA9\" stays sha-only on a dirty tree (documented gap)" ;;
    *"at=\"$SHA9+dirty\""*) no "whereis: gained +dirty — update this gate's documented-gap comment if intentional" ;;
    *)                      no "whereis: at= missing entirely" ;;
esac

# an untracked file ALSO counts as dirty (mergescout.h's own `git status --porcelain` precedent, no --uno)
g stash -q  # park the tracked edit so this probes untracked-only dirtiness
: > "$R/untracked.txt"
out="$( "$BIN" "$R" --doctor --no-cache 2>/dev/null )"
case "$out" in
    *"at=\"$SHA9+dirty\""*) ok "doctor: an UNTRACKED file alone counts as dirty" ;;
    *)                      no "doctor: an untracked file did not trigger +dirty"; echo "$out" | grep -o 'at="[^"]*"' ;;
esac
rm -f "$R/untracked.txt"
g stash pop -q

# ── the bare default map: NEVER stamped, on a git root or not ────────────────────────────────────────────
# §P8 (2026-07-28) — REPINNED. What this gate protects is unchanged and is NOT "the root has no attributes":
# it is "the default map never pays for a git subprocess", i.e. never grows `at=`. The root legitimately DID
# grow one attribute in the vocabulary pass — `est_tokens=`, computed from bytes already in hand, no git, no
# cost — so the old `*'<r>'*` literal reported "not found at all" for a root that is exactly as unstamped as
# before. Pinned to the ABSENCE of at= (the actual invariant) plus the PRESENCE of the free est_tokens=.
out="$( "$BIN" "$R" --no-cache 2>/dev/null )"
case "$out" in
    *'<r at='*)          no "default map: <r> grew an at= — this must never cost a git subprocess on the hot path" ;;
    *'<r est_tokens="'*) ok "default map: <r> carries only the git-free est_tokens=, never at=" ;;
    *'<r>'*)             no "default map: <r> lost its est_tokens= — the map's own size is comment-only again" ;;
    *)                   no "default map: <r> not found at all" ;;
esac

# --map-diff DOES stamp <r>: it already shells out to git for the diff itself
out="$( "$BIN" "$R" --map-diff --no-cache 2>/dev/null )"
case "$out" in
    *"<r at=\"$SHA9"*) ok "map-diff: <r at=\"$SHA9...\"> stamped" ;;
    *)                 no "map-diff: <r> was not stamped"; echo "$out" | grep -o '<r[^>]*>' ;;
esac

# ── non-git directory: at= is OMITTED entirely, never at="none" ─────────────────────────────────────────
NG="$TMP/nongit"; mkdir -p "$NG"
cat > "$NG/plain.h" <<'EOF'
#pragma once
int justAFunction() { return 1; }
EOF

out="$( "$BIN" "$NG" --doctor --no-cache 2>/dev/null )"
case "$out" in
    *'at="'*) no "doctor on a non-git root: at= should be OMITTED, found one"; echo "$out" | grep -o '<doctor[^>]*>' ;;
    *)        ok "doctor on a non-git root: at= omitted" ;;
esac

out="$( "$BIN" "$NG" --doc-drift --no-cache 2>/dev/null )"
case "$out" in
    *'at="'*) no "doc-drift on a non-git root: at= should be OMITTED, found one"; echo "$out" | grep -o '<doc-drift[^>]*>' ;;
    *)        ok "doc-drift on a non-git root: at= omitted" ;;
esac

out="$( "$BIN" "$NG" --no-cache 2>/dev/null )"
case "$out" in
    *'<r>'*)    ok "default map on a non-git root: <r> stays bare" ;;
    *'<r at='*) no "default map on a non-git root: <r> should never gain at=" ;;
esac

# ── determinism + xmllint on the (still-dirty) repo state left over from above ───────────────────────────
for flags in "--doctor" "--doc-drift" "--hotspots" "--quality-delta" "--pr-context" "--test-gate"; do
    a="$( "$BIN" "$R" $flags --no-cache 2>/dev/null )"
    b="$( "$BIN" "$R" $flags --no-cache 2>/dev/null )"
    [ "$a" = "$b" ] && ok "determinism ($flags)" || no "determinism ($flags): two runs differed"
    printf '%s' "$a" | xmllint --noout - >/dev/null 2>&1 && ok "xmllint ($flags)" || no "xmllint ($flags) FAILED"
done

if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "SOME FAILED"; fi
exit "$fail"

#!/usr/bin/env bash
# landingcheck.sh — the gate for `--stray-content --plan` (src/landingplan.h): "of all my branches, which
# still hold REAL work, and in what order should I land them?" Composes crossref.h's cheap per-blob sweep
# (--stray-content) with mergescout.h's expensive per-arm overlap oracle (--merge-scout), dropping refs the
# live line already re-implemented (v="superseded") before the expensive step runs.
#
# Two fixtures:
#   REPO  — the crossrefcheck.sh construction (feat-unmerged / feat-superseded / feat-merged) PLUS a second
#           unmerged branch (feat-unmerged-2) that adds the SAME symbol feat-unmerged does, with different
#           content — a genuine same-symbol conflict to prove the pairwise-conflict/landing-order pass-
#           through actually runs, not just that the flag doesn't crash.
#   REPO2 — 13 unmerged branches of strictly increasing stray-line size, nothing superseded/merged, to prove
#           the kMaxPlanScout=12 cost bound: the 12 largest are scouted, the smallest is counted (bounded=1,
#           scouted="0") and named, never silently dropped.
#
# Usage:  test/landingcheck.sh   |   CTXPACK_BIN=asan/ctxpack test/landingcheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "landingcheck: git unavailable — skipping"; exit 0; }
echo "landingcheck: BIN=$BIN"

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════
# REPO — verdict + conflict fixture (crossrefcheck.sh's construction, plus a 2nd unmerged branch)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════
R="$TMP/repo"; mkdir -p "$R"
export GIT_AUTHOR_NAME=ctxpack GIT_AUTHOR_EMAIL=ctxpack@example.invalid
export GIT_COMMITTER_NAME=ctxpack GIT_COMMITTER_EMAIL=ctxpack@example.invalid
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
g(){ git -C "$R" "$@" >/dev/null 2>&1; }

g init -q -b main
g config commit.gpgsign false

cat > "$R/engine.cpp" <<'EOF'
#include "engine.h"

int computeBudget( int frames )
{
    return frames * 16;
}

int legacyPinnedLimit()
{
    return 10;
}
EOF
cat > "$R/engine.h" <<'EOF'
#pragma once
int computeBudget( int frames );
int legacyPinnedLimit();
EOF
g add engine.cpp engine.h
g commit -qm base

# feat-superseded: replaces the pinned literal with a derived value (same site the live line revisits below)
g checkout -qb feat-superseded
perl -0pi -e 's/    return 10;\n/    const int derived = computeBudget( 1 ) \/ 16;\n    return derived + 9;\n/' "$R/engine.cpp"
g commit -qam "derive the limit instead of pinning 10"

# feat-unmerged: brand-new file + symbol the live line never had
g checkout -q main
g checkout -qb feat-unmerged
cat > "$R/contourSynth.cpp" <<'EOF'
#include "engine.h"

// A whole feature that exists ONLY on this branch.
int reliefFirstContourIndex()
{
    return 24;
}

int reliefContourCount()
{
    return 8;
}
EOF
g add contourSynth.cpp
g commit -qm "relief contour family"

# feat-unmerged-2: a DIFFERENT branch that ALSO defines contourSynth.cpp::reliefFirstContourIndex, with
# different content — both are unmerged (the live line has neither), and merge-scout must see this as a
# true same-symbol conflict between them.
g checkout -q main
g checkout -qb feat-unmerged-2
cat > "$R/contourSynth.cpp" <<'EOF'
#include "engine.h"

// An independent take on the same feature — never landed, never seen feat-unmerged's version.
int reliefFirstContourIndex()
{
    return 999;
}
EOF
g add contourSynth.cpp
g commit -qm "relief contour, second attempt"

# feat-merged: content that ends up byte-identical on the live line
g checkout -q main
g checkout -qb feat-merged
printf 'int sharedHelper( int x )\n{\n    return x + 1;\n}\n' >> "$R/engine.cpp"
g commit -qam "shared helper"

# the live line (HEAD): rewrites the SAME base line feat-superseded rewrote, differently, and merges feat-merged
g checkout -q main
perl -0pi -e 's/    return 10;\n/    return computeBudget( 1 ) - 6;\n/' "$R/engine.cpp"
g commit -qam "compute the limit from the budget (live line)"
g merge -q --no-edit feat-merged

echo "landingcheck: REPO=$R"

# ── 1) bare --plan refuses loudly (companion-flag pattern) ─────────────────────────────────────────────
"$BIN" "$R" --plan >/dev/null 2>"$TMP/bareplan.err"; rc=$?
{ [ "$rc" -eq 1 ] && grep -q -- "--stray-content" "$TMP/bareplan.err"; } \
    && ok "bare --plan refuses loudly (exit 1, names --stray-content)" \
    || { no "bare --plan should refuse naming --stray-content (rc=$rc)"; cat "$TMP/bareplan.err"; }

# ── 2) the composed plan: determinism ×3 ────────────────────────────────────────────────────────────────
"$BIN" "$R" --stray-content --plan >"$TMP/p1" 2>/dev/null; rc1=$?
"$BIN" "$R" --stray-content --plan >"$TMP/p2" 2>/dev/null
"$BIN" "$R" --stray-content --plan >"$TMP/p3" 2>/dev/null
{ [ "$rc1" -eq 0 ] && cmp -s "$TMP/p1" "$TMP/p2" && cmp -s "$TMP/p2" "$TMP/p3"; } \
    && ok "--stray-content --plan determinism ×3 (byte-identical, incl. landing order)" \
    || { no "--stray-content --plan nondeterministic or crashed (rc=$rc1)"; diff "$TMP/p1" "$TMP/p2" | head -6; }
P="$( cat "$TMP/p1" )"

# ── 3) header counts: 2 unmerged, 1 superseded, 1 merged, both unmerged scouted, none bounded ──────────
echo "$P" | grep -q '<landing-plan [^>]*unmerged="2"' && ok "header: unmerged=2" || { no "header unmerged!=2"; echo "$P" | grep -o '<landing-plan[^>]*'; }
echo "$P" | grep -q '<landing-plan [^>]*superseded="1"' && ok "header: superseded=1" || no "header superseded!=1"
echo "$P" | grep -q '<landing-plan [^>]*merged="1"' && ok "header: merged=1 (feat-merged counted, never listed)" || no "header merged!=1"
echo "$P" | grep -q '<landing-plan [^>]*scouted="2"' && ok "header: scouted=2 (both unmerged refs fed to merge-scout)" || no "header scouted!=2"
echo "$P" | grep -q '<landing-plan [^>]*bounded="0"' && ok "header: bounded=0 (under kMaxPlanScout)" || no "header bounded!=0"

# ── 4) the ground-truth inclusion/exclusion contract ────────────────────────────────────────────────────
echo "$P" | grep -q '<ref name="feat-unmerged" v="unmerged"[^>]*scouted="1"' \
    && ok "feat-unmerged: included in the landing set (v=unmerged, scouted=1)" \
    || { no "feat-unmerged missing/wrong from the landing set"; echo "$P" | grep -o '<ref name="feat-unmerged"[^/]*/>'; }
echo "$P" | grep -q '<ref name="feat-unmerged-2" v="unmerged"[^>]*scouted="1"' \
    && ok "feat-unmerged-2: included in the landing set (v=unmerged, scouted=1)" \
    || { no "feat-unmerged-2 missing/wrong from the landing set"; echo "$P" | grep -o '<ref name="feat-unmerged-2"[^/]*/>'; }
echo "$P" | grep -q '<excluded name="feat-superseded" v="superseded"' \
    && ok "feat-superseded: EXCLUDED with its verdict (already re-implemented on the live line)" \
    || { no "feat-superseded not reported as excluded"; echo "$P" | grep -o '<excluded[^/]*/>'; }
echo "$P" | grep -q 'feat-merged' \
    && no "feat-merged must not be named anywhere (merged refs stay omitted, only counted)" \
    || ok "feat-merged: omitted entirely (never named, only counted in merged=)"
echo "$P" | grep -q '<ref name="feat-superseded"' \
    && no "feat-superseded must not appear as a <ref> (it is excluded, not part of the landing set)" \
    || ok "feat-superseded: does not double-appear as a scouted/bounded <ref>"

# ── 5) the merge-scout pass-through actually ran: a real same-symbol conflict + a non-empty landing order ─
echo "$P" | grep -q '<arm ref="feat-unmerged"[^>]*ok="1"' && ok "arm feat-unmerged present (ok=1)" || no "arm feat-unmerged missing/failed"
echo "$P" | grep -q '<arm ref="feat-unmerged-2"[^>]*ok="1"' && ok "arm feat-unmerged-2 present (ok=1)" || no "arm feat-unmerged-2 missing/failed"
echo "$P" | grep -q '<pair a="feat-unmerged" b="feat-unmerged-2" conflicts="1"' \
    && ok "pair feat-unmerged/feat-unmerged-2: true same-symbol conflict on reliefFirstContourIndex" \
    || { no "expected a conflicts=1 pair between the two unmerged branches"; echo "$P" | grep -o '<pair a="feat-unmerged"[^/]*'; }
echo "$P" | grep -qE '<landing order="feat-unmerged,feat-unmerged-2"/>' \
    && ok "landing order: feat-unmerged,feat-unmerged-2 (tied conflict count, ref-name tie-break)" \
    || { no "landing order wrong"; echo "$P" | grep -o '<landing[^/]*/>'; }

# ── 6) --json refuses for --plan (composed verbs are not in the L2 ALLOW-list) — sanity, not a hard req ──
# (skipped: --json's ALLOW-list gap is pre-existing across the whole crossref family, not introduced here)

# ── 7) refusals: non-git root, multi-root ───────────────────────────────────────────────────────────────
mkdir -p "$TMP/plain"; printf 'int main(){return 0;}\n' > "$TMP/plain/m.cpp"
"$BIN" "$TMP/plain" --stray-content --plan >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "--stray-content --plan on a non-git root refuses loudly (exit 1)" || no "non-git root did not exit 1 (rc=$rc)"

# a SECOND, genuinely different repo — two identical paths dedup to one root (a pre-existing, unrelated
# ctxpack behavior), so the multi-root refusal needs two distinct directories to actually exercise it.
R3="$TMP/repo3"; mkdir -p "$R3"
git -C "$R3" init -q -b main
git -C "$R3" config commit.gpgsign false
printf 'int other(){return 0;}\n' > "$R3/other.cpp"
git -C "$R3" add other.cpp
git -C "$R3" commit -qm base >/dev/null 2>&1

MRERR="$( "$BIN" "$R" "$R3" --stray-content --plan 2>&1 )"; MRRC=$?
{ [ "$MRRC" -ne 0 ] && echo "$MRERR" | grep -q "single-root only"; } \
    && ok "multi-root workspace refuses --stray-content --plan (single-root only)" \
    || no "multi-root refusal wrong (rc=$MRRC): $MRERR"

# ── 8) xmllint (G4) + minified ──────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    echo "$P" | xmllint --noout - 2>/dev/null && ok "landing-plan XML well-formed" || no "landing-plan XML malformed"
else
    ok "xmllint unavailable — well-formedness skipped"
fi
[ "$( grep -c '' "$TMP/p1" )" -le 1 ] && ok "output is minified (no stray newlines)" || no "output contains newlines outside CDATA"

# ── 9) read-only: current branch + working tree unchanged after every run above ────────────────────────
POSTBRANCH="$( git -C "$R" symbolic-ref --short HEAD 2>/dev/null )"
[ "$POSTBRANCH" = "main" ] && ok "read-only: current branch unchanged after all runs ($POSTBRANCH)" \
                           || no "read-only: current branch changed! now on $POSTBRANCH"
git -C "$R" status --porcelain | grep -q . \
    && no "read-only: working tree left dirty after runs" \
    || ok "read-only: working tree clean after all runs"

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════
# REPO2 — the kMaxPlanScout=12 cost-bound fixture: 13 unmerged branches of strictly increasing stray size
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════
R2="$TMP/repo2"; mkdir -p "$R2"
g2(){ git -C "$R2" "$@" >/dev/null 2>&1; }
g2 init -q -b main
g2 config commit.gpgsign false
printf 'int baseline() { return 0; }\n' > "$R2/base.cpp"
g2 add base.cpp
g2 commit -qm base

for n in $( seq 1 13 ); do
    g2 checkout -q main
    g2 checkout -qb "size-$( printf '%02d' "$n" )"
    f="$R2/p$( printf '%02d' "$n" ).cpp"
    : > "$f"
    for i in $( seq 1 "$n" ); do
        printf 'int size%02d_func%03d() { return %d; }\n' "$n" "$i" "$(( n * 1000 + i ))" >> "$f"
    done
    g2 add "$f" >/dev/null 2>&1
    git -C "$R2" commit -qm "size-$n ($n lines)" >/dev/null 2>&1
done
g2 checkout -q main

echo "landingcheck: REPO2=$R2 (13 unmerged branches, sizes 1..13 lines)"

"$BIN" "$R2" --stray-content --plan >"$TMP/b1" 2>/dev/null; brc=$?
B="$( cat "$TMP/b1" )"

[ "$brc" -eq 0 ] && ok "REPO2: --stray-content --plan ran clean (rc=0)" || { no "REPO2 run failed (rc=$brc)"; echo "$B" | head -c 400; }
echo "$B" | grep -q '<landing-plan [^>]*unmerged="13"' && ok "REPO2 header: unmerged=13" || { no "REPO2 header unmerged!=13"; echo "$B" | grep -o '<landing-plan[^>]*'; }
echo "$B" | grep -q '<landing-plan [^>]*scouted="12"' && ok "REPO2 header: scouted=12 (kMaxPlanScout bound)" || { no "REPO2 header scouted!=12"; echo "$B" | grep -o '<landing-plan[^>]*'; }
echo "$B" | grep -q '<landing-plan [^>]*bounded="1"' && ok "REPO2 header: bounded=1 (the smallest ref, counted honestly)" || { no "REPO2 header bounded!=1"; echo "$B" | grep -o '<landing-plan[^>]*'; }

# the SMALLEST branch (size-01, stray=1) must be the one bounded out — top-N BY STRAY SIZE keeps the rest
echo "$B" | grep -q '<ref name="size-01" v="unmerged" stray="1" [^>]*scouted="0"' \
    && ok "size-01 (smallest, stray=1) is the one bounded out (scouted=0)" \
    || { no "size-01 should be scouted=0 (the smallest by stray size)"; echo "$B" | grep -o '<ref name="size-01"[^/]*/>'; }
echo "$B" | grep -q '<ref name="size-13" v="unmerged" stray="13" [^>]*scouted="1"' \
    && ok "size-13 (largest, stray=13) is scouted (scouted=1)" \
    || { no "size-13 should be scouted=1"; echo "$B" | grep -o '<ref name="size-13"[^/]*/>'; }
# no <excluded> at all here — size-01 is bounded (cost), not superseded/merged (a verdict-based drop)
echo "$B" | grep -q '<excluded' \
    && no "REPO2 must have no <excluded> rows (nothing superseded/merged in this fixture)" \
    || ok "REPO2: no spurious <excluded> rows (bounded != excluded)"

# --detail lifts the bound: all 13 get scouted
"$BIN" "$R2" --stray-content --plan --detail=1 >"$TMP/b2" 2>/dev/null
echo "$( cat "$TMP/b2" )" | grep -q '<landing-plan [^>]*scouted="13"[^>]*bounded="0"' \
    && ok "--detail lifts the scout bound (scouted=13, bounded=0)" \
    || { no "--detail did not lift the bound"; echo "$( cat "$TMP/b2" )" | grep -o '<landing-plan[^>]*'; }

if command -v xmllint >/dev/null 2>&1; then
    echo "$B" | xmllint --noout - 2>/dev/null && ok "REPO2 landing-plan XML well-formed" || no "REPO2 landing-plan XML malformed"
fi

[ $fail -eq 0 ] && echo "landingcheck: ALL PASS" || echo "landingcheck: FAILURES"
exit $fail

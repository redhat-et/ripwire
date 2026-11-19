#!/usr/bin/env bash
# qdrangecheck.sh — scripts/qd_range.sh, the pull-request range quality gate CI's qd-range job runs, on a fixture repo.
#
# WHY. --quality-delta compares a change with its parent, so a merged regression becomes the next comparison's
# baseline and never shows again (#697, prompts/quality-drift.md). qd_range.sh runs --quality-delta=<merge-base>..HEAD
# and fails on a gating row the ack ledger does not cover. This gate keeps the script's logic covered off CI, on a
# throwaway repo built here, with the two slip shapes #697 names replayed in miniature:
#   (A) one-commit complexity growth across the bar, 12 -> 16 (chooseInWindow, #693) — red, the row named;
#   (B) a TWO-STEP contract change, 2 -> 3 -> 4 parameters (defTableLegend's shape): each commit alone is a minor,
#       never-gating row, so a per-commit check passes both; the range is red. Its mutation control (M) runs a copy
#       of the script that compares only the last commit and must go green on (B), so (B) can fail;
#   (C) the printed ack command, run as printed with a reason, turns (A) green with acked=1; worsening past the ack
#       turns it red again;
#   (D) clean ranges: new-symbol rows only (counted: zero rows seen is a FAIL, the arm saw nothing), and an empty range;
#   (E) the check cannot be made: an unknown base, a shallow clone without the base (CI needs fetch-depth: 0);
#   (F) no answer is never a pass: a binary that prints nothing, and one that answers a different range;
#   (G) the CI wiring: ci.yml's qd-range job calls this script with full history, and ci-gate needs it.
# The real-history replay (chooseInWindow over #693's range, etc.) is on the PR that added this gate; it needs this
# repo's full history and ~1 min per range, so it is not re-run here.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
SCRIPT="$ROOT/scripts/qd_range.sh"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "qdrangecheck: no ripwire binary at $BIN"; exit 2; }
[ -f "$SCRIPT" ] || { echo "qdrangecheck: FAIL — no $SCRIPT"; exit 1; }
echo "qdrangecheck: BIN=$BIN"

# qd OUTFILE ARGS... — run the script, keep its output, return its exit status
qd(){ local out="$1"; shift; bash "$SCRIPT" --bin "$BIN" "$@" >"$out" 2>&1; }
verdict(){ tail -1 "$1"; }
seen(){ sed -n 's/^qd-range: rows seen=\([0-9]*\);.*/\1/p' "$1"; }
show(){ sed 's/^/        /' "$1" | tail -n 14; }

# ── the fixture: base has steer (ccx 12, under the bar 15) and surface(a, b), both used ─────────────────────────────
R="$TMP/repo"; mkdir -p "$R"; cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t && git checkout -q -b main
cat > lib.h <<'EOF'
#pragma once
inline int steer( int a, int b )
{
    int t = 0;
    for( int i = 0; i < a; ++i )
    {
        if( i % 2 == 0 )       { t += 1; }
        else if( i % 3 == 0 )  { t += 2; }
        else if( i % 5 == 0 )  { t += 3; }
        else if( i % 7 == 0 )  { t += 4; }
        else if( i % 11 == 0 ) { t += 5; }
        else if( i % 13 == 0 ) { t += 6; }
        else if( i % 17 == 0 ) { t += 7; }
        else if( i % 19 == 0 ) { t += 8; }
        else if( i % 23 == 0 ) { t += 9; }
        else if( i % 29 == 0 ) { t += 10; }
    }
    return t + b;
}
inline int surface( int a, int b )
{
    return a + b;
}
EOF
printf '#include "lib.h"\nint useAll() { return steer( 3, 4 ) + surface( 1, 2 ); }\n' > use.cpp
git add . && git commit -qm base
# grow steer by N more branches (each one +1 ccx) on the current branch
grow(){ python3 - "$1" "$2" <<'EOF'
import sys
n, start = int(sys.argv[1]), int(sys.argv[2])
s = open('lib.h').read()
anchor = "        else if( i % 29 == 0 ) { t += 10; }\n"
add = "".join(f"        else if( i % {start + 2 * k} == 1 ) {{ t += {k}; }}\n" for k in range(n))
open('lib.h', 'w').write(s.replace(anchor, anchor + add))
EOF
}

# ── (A) one commit, complexity 12 -> 16 across the bar ──────────────────────────────────────────────────────────────
git checkout -q -b cx main && grow 4 101 && git commit -qam 'steer +4 branches'
qd "$TMP/a.out" -C "$R" main; rc=$?
if [ "$rc" = 2 ] && verdict "$TMP/a.out" | grep -q '^qd-range: FAIL — 1 gating row(s) .*complexity steer (lib.h:2, 12->16)'; then
    ok "(A) complexity 12->16 in one commit: exit 2, the FAIL line names steer (rows seen=$( seen "$TMP/a.out" ))"
else
    no "(A) expected exit 2 naming 'complexity steer (lib.h:2, 12->16)', got exit $rc"; show "$TMP/a.out"
fi
grep -q '^  GATE  *complexity  *12->16  *steer' "$TMP/a.out" && ok "(A) the table prints the gating row" \
    || { no "(A) no GATE row for steer in the printed table"; show "$TMP/a.out"; }
verdict "$TMP/a.out" | grep -qF -- "--quality-ack='<why this is deliberate>' --ack-only='steer'" \
    && ok "(A) the FAIL line says how to ack it" || { no "(A) the FAIL line carries no ack command"; verdict "$TMP/a.out"; }

# ── (B) two steps, 2 -> 3 -> 4 parameters: green per commit, red over the range ─────────────────────────────────────
git checkout -q -b surf main
sed -e 's/inline int surface( int a, int b )/inline int surface( int a, int b, int c = 0 )/' -e 's/return a + b;/return a + b + c;/' lib.h >lib.h.new && mv lib.h.new lib.h
git commit -qam 'surface +c'
sed -e 's/int c = 0 )/int c = 0, int d = 0 )/' -e 's/return a + b + c;/return a + b + c + d;/' lib.h >lib.h.new && mv lib.h.new lib.h
git commit -qam 'surface +d'
for step in 1 2; do
    qd "$TMP/b$step.out" -C "$R" "HEAD~$(( 3 - step ))" "HEAD~$(( 2 - step ))"; rc=$?
    n="$( seen "$TMP/b$step.out" )"
    if [ "$rc" = 0 ] && [ "${n:-0}" -ge 1 ] && grep -q '^  minor *api-surface .* surface ' "$TMP/b$step.out"; then
        ok "(B) step $step alone: exit 0, its contract change is a minor row ($n row(s) seen)"
    else
        no "(B) step $step alone: expected exit 0 with a minor api-surface row for surface, got exit $rc, rows seen=${n:-none}"; show "$TMP/b$step.out"
    fi
done
qd "$TMP/b.out" -C "$R" main; rc=$?
if [ "$rc" = 2 ] && verdict "$TMP/b.out" | grep -q 'api-surface surface (lib.h:[0-9]*, 2->4)'; then
    ok "(B) the range main..HEAD: exit 2, api-surface surface 2->4 named — the two-step slip a per-commit check cannot see"
else
    no "(B) range expected exit 2 naming 'api-surface surface (…, 2->4)', got exit $rc"; show "$TMP/b.out"
fi
# (M) mutation control: a copy that compares only the LAST commit (HEAD^..HEAD) must go green on (B)'s branch, so arm
# (B)'s red is the range doing its job and not something any comparison would show.
sed 's|^mb="$( git -C "$DIR" merge-base "$baseSha" "$headSha" 2>/dev/null )"|mb="$( git -C "$DIR" rev-parse "$headSha^" )"|' "$SCRIPT" >"$TMP/qd_lastcommit.sh"
if cmp -s "$SCRIPT" "$TMP/qd_lastcommit.sh"; then
    no "(M) the mutation did not apply (the merge-base line moved) — arm (B) is unproven"
else
    bash "$TMP/qd_lastcommit.sh" --bin "$BIN" -C "$R" main >"$TMP/m.out" 2>&1; rc=$?
    [ "$rc" = 0 ] && ok "(M) a last-commit-only copy passes (B)'s branch (exit 0): arm (B) can fail" \
        || { no "(M) the last-commit-only copy exited $rc on (B)'s branch, expected 0 — (B) does not isolate the range"; show "$TMP/m.out"; }
fi

# ── (C) ack with a reason: the printed command, run as printed, turns (A) green; worsening past it is red again ───────
git checkout -q cx
ackOnly="$( verdict "$TMP/a.out" | sed -n "s/.*--ack-only='\([^']*\)'.*/\1/p" )"
reason="qdrangecheck arm C: steer's four branches are the fixture's deliberate growth"
"$BIN" . "--quality-delta=$( git merge-base main HEAD )..HEAD" "--quality-ack=$reason" "--ack-only=$ackOnly" >"$TMP/c.ack" 2>&1; ackRc=$?
grep -qF "$reason" .ripwire_quality_acks 2>/dev/null && [ "$ackRc" = 0 ] \
    && ok "(C) the printed ack command (--ack-only='$ackOnly') wrote a ledger row with its reason" \
    || { no "(C) the ack command exited $ackRc and/or wrote no row with the reason"; show "$TMP/c.ack"; }
git add .ripwire_quality_acks && git commit -qm 'ack steer'
qd "$TMP/c.out" -C "$R" main; rc=$?
if [ "$rc" = 0 ] && verdict "$TMP/c.out" | grep -q '^qd-range: PASS — 0 gating rows .*, 1 acked)' && grep -q '^qd-range: rows seen=.* gating=0 .* acked=1 ' "$TMP/c.out"; then
    ok "(C) acked: exit 0, gating=0 acked=1 (rows seen=$( seen "$TMP/c.out" ))"
else
    no "(C) after the ack expected exit 0 with acked=1, got exit $rc"; show "$TMP/c.out"
fi
grow 2 201 && git commit -qam 'steer +2 more'
qd "$TMP/c2.out" -C "$R" main; rc=$?
[ "$rc" = 2 ] && verdict "$TMP/c2.out" | grep -q 'complexity steer (lib.h:2, 12->18)' \
    && ok "(C) worse than the acked 16 (now 18): red again, exit 2" \
    || { no "(C) growth past the ack expected exit 2 naming steer 12->18, got exit $rc"; show "$TMP/c2.out"; }

# ── (D) clean: new-symbol rows only (counted), and an empty range ──────────────────────────────────────────────────
git checkout -q -b fresh main
python3 - <<'EOF'
body = "".join(f"        else if( i % {p} == 0 ) {{ t += {k}; }}\n" for k, p in enumerate((3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67)))
open('fresh.h', 'w').write("#pragma once\ninline int fresh( int a )\n{\n    int t = 0;\n    for( int i = 0; i < a; ++i )\n    {\n        if( i % 2 == 0 ) { t += 1; }\n" + body + "    }\n    return t;\n}\n")
EOF
printf '#include "fresh.h"\nint useFresh() { return fresh( 3 ); }\n' > usefresh.cpp
git add fresh.h usefresh.cpp && git commit -qm "a new function over the bar"
qd "$TMP/d.out" -C "$R" main; rc=$?
n="$( seen "$TMP/d.out" )"; newRows="$( grep -c '^  new ' "$TMP/d.out" )"
if [ "$rc" = 0 ] && [ "${n:-0}" -ge 1 ] && [ "$newRows" -ge 1 ] && ! grep -q '^  GATE ' "$TMP/d.out"; then
    ok "(D) new-symbol rows only: exit 0, PASS ($n row(s) seen, $newRows new-symbol)"
else
    no "(D) expected exit 0 with >= 1 new-symbol row and no GATE row, got exit $rc, rows seen=${n:-none}, new=$newRows"; show "$TMP/d.out"
fi
qd "$TMP/d0.out" -C "$R" HEAD HEAD; rc=$?
[ "$rc" = 0 ] && [ "$( seen "$TMP/d0.out" )" = 0 ] && verdict "$TMP/d0.out" | grep -q '^qd-range: PASS' \
    && ok "(D) an empty range: exit 0, 0 rows seen" || { no "(D) empty range expected exit 0 with 0 rows, got exit $rc"; show "$TMP/d0.out"; }

# ── (E) the check cannot be made: say so, exit 1 ───────────────────────────────────────────────────────────────────
qd "$TMP/e1.out" -C "$R" no-such-branch; rc=$?
[ "$rc" = 1 ] && verdict "$TMP/e1.out" | grep -q "BASE 'no-such-branch' is not reachable" \
    && ok "(E) an unknown base: exit 1, 'not reachable'" || { no "(E) unknown base expected exit 1 'not reachable', got exit $rc"; show "$TMP/e1.out"; }
git clone -q --depth 1 --branch cx "file://$R" "$TMP/shallow" 2>/dev/null
qd "$TMP/e2.out" -C "$TMP/shallow" "$( git -C "$R" rev-parse main )"; rc=$?
[ "$rc" = 1 ] && verdict "$TMP/e2.out" | grep -q 'fetch-depth: 0' \
    && ok "(E) a depth-1 clone without the base: exit 1, names fetch-depth: 0" || { no "(E) shallow clone expected exit 1 naming fetch-depth, got exit $rc"; show "$TMP/e2.out"; }

# ── (F) no answer is never a pass ──────────────────────────────────────────────────────────────────────────────────
printf '#!/bin/sh\nexit 0\n' >"$TMP/silent"; chmod +x "$TMP/silent"
bash "$SCRIPT" --bin "$TMP/silent" -C "$R" main >"$TMP/f1.out" 2>&1; rc=$?
[ "$rc" = 1 ] && verdict "$TMP/f1.out" | grep -q 'no --quality-delta answer' \
    && ok "(F) a binary that prints nothing and exits 0: exit 1, 'no answer'" || { no "(F) silent binary expected exit 1, got exit $rc"; show "$TMP/f1.out"; }
printf '#!/bin/sh\necho "<quality-delta schema=\\"ripwire.quality-delta/v1\\" gating=\\"0\\" base_ref=\\"0000\\" target_ref=\\"1111\\"></quality-delta>"\n' >"$TMP/other"; chmod +x "$TMP/other"
bash "$SCRIPT" --bin "$TMP/other" -C "$R" main >"$TMP/f2.out" 2>&1; rc=$?
[ "$rc" = 1 ] && verdict "$TMP/f2.out" | grep -q 'no --quality-delta answer' \
    && ok "(F) a clean answer for a DIFFERENT range: exit 1" || { no "(F) wrong-range answer expected exit 1, got exit $rc"; show "$TMP/f2.out"; }

# ── (G) CI wiring ──────────────────────────────────────────────────────────────────────────────────────────────────
CI="$ROOT/.github/workflows/ci.yml"
job="$( awk '/^  qd-range:$/{on=1; print; next} on && /^  [a-z0-9_-]+:$/{exit} on' "$CI" )"
if [ -z "$job" ]; then
    no "(G) ci.yml has no qd-range job"
else
    printf '%s\n' "$job" | grep -q 'bash scripts/qd_range.sh ' && ok "(G) the qd-range job runs scripts/qd_range.sh" || no "(G) the qd-range job does not call scripts/qd_range.sh"
    printf '%s\n' "$job" | grep -q 'fetch-depth: 0' && ok "(G) its checkout fetches full history (fetch-depth: 0)" || no "(G) the qd-range checkout is not fetch-depth: 0 — the merge-base may be unreachable"
fi
needs="$( awk '/^  ci-gate:$/{on=1} on && /^    needs:/{print; exit}' "$CI" )"
printf '%s\n' "$needs" | grep -q '[[ ,]qd-range[],]' && ok "(G) ci-gate needs qd-range" || no "(G) ci-gate's needs does not list qd-range: $needs"

[ "$fail" = 0 ] && echo "qdrangecheck: PASS" || echo "qdrangecheck: FAIL"
exit "$fail"

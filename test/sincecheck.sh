#!/usr/bin/env bash
# sincecheck.sh — gate for the global --since=REV|DATE time-window scope on the git-history verbs
# (--hotspots / churn). Builds a synthetic git repo where file A's commits ALL precede a clean
# HEAD~3 boundary and file B's are the last 3, and asserts:
#   - all-history --hotspots:      both A and B present (both churned, both have cognitive cx > 0)
#   - --hotspots --since=HEAD~3:   ONLY B (its 3 commits are in-window); A drops out — the regression lens
#   - bad --since=garbage:         REFUSES (exit 1, names the value, no <hotspots> element). §P0.5c: this
#                                  case used to assert "degrades to all-history", which meant stdout printed
#                                  window="12mo" over an all-history scan and the only honest signal was a
#                                  stderr degrade note — a false NON-zero. --hotspots' window is part of its
#                                  measurement. Other --since consumers (--cochange, --rank-by=churn) still
#                                  degrade; see test/sincecochangecheck.sh.
#   - determinism:                 --since=HEAD~3 (REV form) is byte-identical run-to-run
#   - shell safety:                a --since value with shell metacharacters executes nothing
# Usage:  test/sincecheck.sh   |   CTXPACK_BIN=asan/ctxpack test/sincecheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh. Needs git.
set -u
BIN="${CTXPACK_BIN:-./build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"
fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1"; fail=1; }

REPO="$(mktemp -d)"; trap 'rm -rf "$REPO"' EXIT
cd "$REPO" || exit 1
git init -q; git config user.email x@y; git config user.name x
# A: 3 EARLY commits (branch body → cognitive cx > 0 so hotspots keeps it)
for i in 1 2 3; do printf 'int a(int x){ if(x>%d){return 1;} else {return 2;} }\n' "$i" > A.cpp; git add A.cpp; git commit -qm "A$i"; done
# B: 3 RECENT commits — the last 3, so HEAD~3.. selects exactly B
for i in 1 2 3; do printf 'int b(int x){ if(x>%d){return 1;} else {return 2;} }\n' "$i" > B.cpp; git add B.cpp; git commit -qm "B$i"; done

allhx="$("$BIN" "$REPO" --hotspots --no-cache 2>/dev/null)"
echo "$allhx" | grep -q '/A.cpp"' && echo "$allhx" | grep -q '/B.cpp"' \
  && ok "all-history --hotspots: both A and B present" \
  || no "all-history --hotspots should list both A and B"

win="$("$BIN" "$REPO" --hotspots --since=HEAD~3 --no-cache 2>/dev/null)"
if echo "$win" | grep -q '/B.cpp"' && ! echo "$win" | grep -q '/A.cpp"'; then
  ok "--since=HEAD~3 scopes churn to the window (B only, A dropped)"
else
  no "--since=HEAD~3 should keep only B (A's commits predate the window)"; echo "     got: $(echo "$win" | grep -oE '/[AB].cpp" churn="[0-9]"' | tr '\n' ' ')"
fi

baderr="$(mktemp)"
bad="$("$BIN" "$REPO" --hotspots --since=not-a-rev-or-date --no-cache 2>"$baderr")"; brc=$?
[ "$brc" -eq 1 ] && ! echo "$bad" | grep -q '<hotspots' && grep -q 'not-a-rev-or-date' "$baderr" \
  && ok "bad --since refuses (exit 1, names the value, no <hotspots> element)" \
  || no "bad --since should refuse naming the value, not measure (rc=$brc, stderr=$(head -c 120 "$baderr"))"
rm -f "$baderr"

r1="$("$BIN" "$REPO" --hotspots --since=HEAD~3 --no-cache 2>/dev/null)"
r2="$("$BIN" "$REPO" --hotspots --since=HEAD~3 --no-cache 2>/dev/null)"
[ "$r1" = "$r2" ] && ok "--since=HEAD~3 deterministic run-to-run" || no "--since=HEAD~3 not deterministic"

rm -f "$REPO/PWNED"
"$BIN" "$REPO" --hotspots --since='HEAD~3; touch '"$REPO"'/PWNED' --no-cache >/dev/null 2>&1
[ ! -f "$REPO/PWNED" ] && ok "shell-metacharacter --since executes nothing (quoted safely)" || no "shell injection via --since!"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }

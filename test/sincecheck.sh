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
#                                  measurement.
#   - THE FOUR HOSTS (M8, capture-audit 2026-09-04, lens 6 F7 / lens 7 F-SINCE-1). --since is a GLOBAL flag
#                                  with four consumers, and the §P0.5c fix landed on one of them. --hotspots
#                                  and --slice refused an unresolvable value; --cochange and --rank-by=churn
#                                  emitted at exit 0 under window="18mo" with only a stderr note — the exact
#                                  false window §P0.5c's own header says was fixed. A window is part of every
#                                  one of these measurements, so all four refuse and all four are asserted
#                                  below.
#   - an IMPOSSIBLE date:          --since=2026-13-45 was stamped into window= and reported as a legitimately
#                                  empty window (commits="0", "not an error"). Month 13 / day 45 is not a
#                                  date. The ISO-shaped forms are now range-checked; relative forms
#                                  ("2 weeks ago", "yesterday") are still git's approxidate to parse.
#   - ONE message per refusal:     the unresolvable-value path used to print three lines that contradict
#                                  each other — an internal "[math degraded] … ignoring it" alert, then
#                                  "ignoring it; the verb's own default window applies", then the host's
#                                  "refusing rather than…". Only the last was true. Nothing is ignored now,
#                                  so nothing says so.
#   - determinism:                 --since=HEAD~3 (REV form) is byte-identical run-to-run
#   - shell safety:                a --since value with shell metacharacters executes nothing
# Usage:  test/sincecheck.sh   |   RIPWIRE_BIN=asan/ripwire test/sincecheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh. Needs git.
set -u
BIN="${1:-${RIPWIRE_BIN:-./build/ripwire}}"
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
# RE-PINNED 2026-08-19 (R-E CORRECTION): p= is root-relative, so a file at the crawl root spells
# p="A.cpp" with no leading slash. Anchored on p=" instead, which is a STRICTER selector than the old
# substring, not a looser one.
echo "$allhx" | grep -q 'p="A.cpp"' && echo "$allhx" | grep -q 'p="B.cpp"' \
  && ok "all-history --hotspots: both A and B present" \
  || no "all-history --hotspots should list both A and B"

win="$("$BIN" "$REPO" --hotspots --since=HEAD~3 --no-cache 2>/dev/null)"
if echo "$win" | grep -q 'p="B.cpp"' && ! echo "$win" | grep -q 'p="A.cpp"'; then
  ok "--since=HEAD~3 scopes churn to the window (B only, A dropped)"
else
  no "--since=HEAD~3 should keep only B (A's commits predate the window)"; echo "     got: $(echo "$win" | grep -oE 'p="[AB].cpp" churn="[0-9]"' | tr '\n' ' ')"
fi

baderr="$(mktemp)"
bad="$("$BIN" "$REPO" --hotspots --since=not-a-rev-or-date --no-cache 2>"$baderr")"; brc=$?
[ "$brc" -eq 1 ] && ! echo "$bad" | grep -q '<hotspots' && grep -q 'not-a-rev-or-date' "$baderr" \
  && ok "bad --since refuses (exit 1, names the value, no <hotspots> element)" \
  || no "bad --since should refuse naming the value, not measure (rc=$brc, stderr=$(head -c 120 "$baderr"))"
rm -f "$baderr"

# ── M8: all FOUR --since hosts refuse an unresolvable value, with ONE message ────────────────────────────
for host in "--hotspots" "--rank-by=churn" "--cochange" "--slice=a"; do
  err="$(mktemp)"
  out="$("$BIN" "$REPO" $host --since=not-a-rev-or-date --no-cache 2>"$err")"; rc=$?
  if [ "$rc" -ne 0 ] && grep -q 'not-a-rev-or-date' "$err"; then
    ok "M8 $host --since=<garbage>: refuses naming the value (exit $rc)"
  else
    no "M8 $host --since=<garbage>: exit $rc, stderr=$(head -c 160 "$err") stdout=$(printf '%s' "$out" | head -c 80)"
  fi
  if grep -q 'ignoring it' "$err" || grep -qF '[math degraded]' "$err"; then
    no "M8 $host: the refusal still says 'ignoring' (or logs a degrade) on its way to refusing: $(head -c 200 "$err")"
  else
    ok "M8 $host: ONE message — nothing claims the value was ignored"
  fi
  rm -f "$err"
done

# ── M8: an impossible calendar date is not a date ────────────────────────────────────────────────────────
for badday in 2026-13-45 2026-02-30 2026-00-10; do
  err="$(mktemp)"
  out="$("$BIN" "$REPO" --hotspots --since=$badday --no-cache 2>"$err")"; rc=$?
  [ "$rc" -ne 0 ] && ! printf '%s' "$out" | grep -q "window=\"$badday\"" \
    && ok "M8 --since=$badday refuses (an impossible date is not an empty window)" \
    || no "M8 --since=$badday: exit $rc, stdout=$(printf '%s' "$out" | grep -o 'window="[^"]*"' | head -1)"
  rm -f "$err"
done
# ... and a REAL ISO date still parses
"$BIN" "$REPO" --hotspots --since=2020-01-01 --no-cache >/dev/null 2>&1 \
  && ok "M8 --since=2020-01-01 (a real ISO date) still resolves" || no "M8 a valid ISO date was refused"
"$BIN" "$REPO" --hotspots --since='2 weeks ago' --no-cache >/dev/null 2>&1 \
  && ok "M8 --since='2 weeks ago' (relative form) still resolves" || no "M8 a relative date form was refused"

r1="$("$BIN" "$REPO" --hotspots --since=HEAD~3 --no-cache 2>/dev/null)"
r2="$("$BIN" "$REPO" --hotspots --since=HEAD~3 --no-cache 2>/dev/null)"
[ "$r1" = "$r2" ] && ok "--since=HEAD~3 deterministic run-to-run" || no "--since=HEAD~3 not deterministic"

rm -f "$REPO/PWNED"
"$BIN" "$REPO" --hotspots --since='HEAD~3; touch '"$REPO"'/PWNED' --no-cache >/dev/null 2>&1
[ ! -f "$REPO/PWNED" ] && ok "shell-metacharacter --since executes nothing (quoted safely)" || no "shell injection via --since!"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }

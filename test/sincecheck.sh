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
#   - A DATE THE HISTORY NEVER REACHES (verify-wave1 N4): --since=1999-01-01 is a real date that resolves to
#                                  no commit. The three WINDOW hosts (--hotspots, --cochange, --rank-by=churn)
#                                  answer — 1999.. is all of history, stamped window="1999-01-01" — and the
#                                  BASELINE host (--slice, which compares against a commit) refuses: there is
#                                  no commit at or before it. Both are honest; what was not one policy is WHERE
#                                  the decision lived — slicediff.h resolved the baseline itself, so a fifth
#                                  consumer could inherit a different rule by omission. Now: resolveSinceScope
#                                  resolves the value ONCE (SinceScope::baselineSha: a rev is its own sha, a
#                                  date is the newest commit at or before it), main.cpp refuses beside the M8
#                                  shape/range validation for the hosts that need a baseline, and the sentence
#                                  is spelled in gitmine.h alone. Asserted: the three answer with the window
#                                  stamped, --slice refuses naming the value with the shared sentence, --slice
#                                  with a reachable baseline still answers, and the SOURCE carries the sentence
#                                  once (gitmine.h) with the decision in main.cpp.
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
SRCDIR="$( cd "$( dirname "$0" )/.." && pwd )/src"   # N4 source arm reads src/; resolve it before leaving this dir
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

# ── N4: a date the history never reaches — window hosts answer, the baseline host refuses, ONE place decides ──
for host in "--hotspots" "--rank-by=churn" "--cochange=A.cpp"; do
  err="$(mktemp)"
  out="$("$BIN" "$REPO" $host --since=1999-01-01 --no-cache 2>"$err")"; rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | perl -0pe 's#<!--.*?-->##gs' | grep -q 'window="1999-01-01"'; then
    ok "N4 $host --since=1999-01-01: answers (exit 0) with the window it was given stamped (1999.. is all of history)"
  else
    no "N4 $host --since=1999-01-01: exit $rc, window=$(printf '%s' "$out" | grep -o 'window="[^"]*"' | head -1) stderr=$(head -c 160 "$err")"
  fi
  rm -f "$err"
done
err="$(mktemp)"
out="$("$BIN" "$REPO" --slice=a:x --since=1999-01-01 --no-cache 2>"$err")"; rc=$?
if [ "$rc" -eq 1 ] && [ -z "$out" ] && grep -q 'resolves to no commit' "$err" && grep -q '1999-01-01' "$err"; then
  ok "N4 --slice=a:x --since=1999-01-01: refuses (exit 1, empty stdout) — no commit at or before the date to compare against"
else
  no "N4 --slice=a:x --since=1999-01-01: exit $rc stdout=$(printf '%s' "$out" | head -c 80) stderr=$(head -c 200 "$err")"
fi
rm -f "$err"
"$BIN" "$REPO" --slice=a:x --since=HEAD~1 --no-cache >/dev/null 2>&1 \
  && ok "N4 --slice=a:x --since=HEAD~1 (a reachable baseline) still answers" \
  || no "N4 --slice=a:x --since=HEAD~1 was refused — the baseline rule swallowed a working case"
# SOURCE PROPERTY: the sentence lives once, in gitmine.h; the decision sits in main.cpp beside the M8 block
SRC="$SRCDIR"   # anchored at the top of this gate, BEFORE the cd into the fixture repo
nSent="$( grep -l 'resolves to no commit in' "$SRC"/*.h "$SRC"/*.cpp 2>/dev/null | wc -l | tr -d ' ' )"
if [ "$nSent" = "1" ] && grep -q 'resolves to no commit in' "$SRC/gitmine.h"; then
  ok "N4 source: the no-baseline sentence is spelled in exactly one file (gitmine.h) — hosts print it, nobody re-words it"
else
  no "N4 source: 'resolves to no commit in' is spelled in $nSent file(s): $( grep -l 'resolves to no commit in' "$SRC"/*.h "$SRC"/*.cpp 2>/dev/null | xargs -n1 basename | tr '\n' ' ')— one policy needs one sentence"
fi
if grep -q 'baselineSha' "$SRC/main.cpp" && grep -q 'baselineSha' "$SRC/gitmine.h"; then
  ok "N4 source: the baseline decision (SinceScope::baselineSha) is read in main.cpp beside the M8 validation"
else
  no "N4 source: main.cpp does not read SinceScope::baselineSha — the resolve-to-no-commit decision is not beside the M8 validation"
fi

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

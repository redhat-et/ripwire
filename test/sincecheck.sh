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
#   - the git SINK (2026-09-10):   git is handed the RESOLVED commit, never the caller's --since string, and a
#                                  value beginning with '-' reaches no git argv at all. shSingleQuote stops the
#                                  shell, not git: a leading '-' is an OPTION to git whatever the quoting. Arms
#                                  S0-S4 at the bottom, with what the pre-fix binary did.
#   - rows that can FAIL:          the N4b rows ran inside `printf | while` — a subshell — so a FAIL row set
#                                  fail=1 where the exit code never saw it, and the gate exited 0 under it
#                                  (CONTRIBUTING §2 shape 6). Every table-driven loop reads its rows on fd 3 now.
# Usage:  test/sincecheck.sh   |   RIPWIRE_BIN=asan/ripwire test/sincecheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh. Needs git.
set -u
BIN="${1:-${RIPWIRE_BIN:-./build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"
fail=0
ok(){ echo "  PASS  $1" || { fail=1; echo "  FAIL  could not write the PASS line for: $1"; }; return 0; }
no(){ echo "  FAIL  $1"; fail=1; }

REPO="$(mktemp -d)"; SHIMDIR="$(mktemp -d)"; trap 'rm -rf "$REPO" "$SHIMDIR"' EXIT
# SHIMDIR holds S2/S3's git PATH shim OUTSIDE the fixture: a file inside $REPO is crawled and would move the bytes S1 compares
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

# ── N4b (verify-wave2): EVERY host, driven off cli.h's kSinceHosts table — one declaration, one policy ────
# verify-wave2 re-opened N4: wave 1 closed it at the SOURCE (one resolver, one sentence) while the four hosts
# still answered a bad value differently, and the arms above pinned THREE named hosts by hand plus --slice —
# which is a list, not a policy, and a list is what a fifth consumer joins without anyone noticing. cli.h now
# DECLARES each host's class in kSinceHosts, both decisions read it (the alone-refusal in checkFlagPairings,
# the no-baseline refusal in main.cpp), and this arm re-derives the rows FROM THAT TABLE. A host added to the
# source without a probe here is caught by the enumeration; a host given the wrong class is caught by the
# behaviour. `--rank-by=churn-decay` is exactly such a host — a --since consumer since P0-4, never once
# asserted by the hand-written list above.
SINCE_ROWS="$( python3 - "$SRCDIR/cli.h" <<'N4_EOF'
import re, sys
src = open( sys.argv[1] ).read()
m = re.search( r"inline constexpr SinceHost kSinceHosts\[\]\s*=\s*\{(.*?)\n\};", src, re.S )
if not m:
    print( "__NOTABLE__" ); raise SystemExit
for line in m.group( 1 ).splitlines():
    row = line.split( "//" )[ 0 ].strip()
    g = re.match( r'\{\s*"([^"]+)"\s*,\s*(true|false)\s*\},?', row )
    if g:
        print( "%s %s" % ( g.group( 1 ), g.group( 2 ) ) )
N4_EOF
)"
# the argv that SELECTS a kSinceHosts row (the table names the flag; a value-taking flag needs one) — N4b and S1-S4 share it
sinceHostArgv(){ case "$1" in --slice) printf '%s' "--slice=a:x" ;; *) printf '%s' "$1" ;; esac; }
case "$SINCE_ROWS" in
  *__NOTABLE__*|"") no "N4b: kSinceHosts is unreadable in src/cli.h — fix this gate's parser before trusting any arm below" ;;
  *)
    nRows="$( printf '%s\n' "$SINCE_ROWS" | grep -c . )"
    [ "$nRows" -ge 5 ] \
      && ok "N4b: read $nRows --since host rows off cli.h's kSinceHosts table" \
      || no "N4b: only $nRows host row(s) parsed — the table shrank or the parser drifted"
    # rows on fd 3, in THIS shell. This loop used to be `printf | while` — a subshell — so its fail=1 never reached
    # the exit code: every row below could print FAIL into a gate that still exited 0.
    while read -r flag needsBaseline <&3; do
      [ -z "$flag" ] && continue
      argv="$( sinceHostArgv "$flag" )"
      # (i) a REACHABLE value: every host, both classes, answers
      "$BIN" "$REPO" $argv --since=HEAD~1 --no-cache >/dev/null 2>&1 \
        && ok "N4b $flag --since=HEAD~1 (reachable): answers, whatever its class" \
        || no "N4b $flag --since=HEAD~1 (reachable) was refused — the baseline rule swallowed a working case"
      # (ii) an IMPOSSIBLE value: every host, both classes, refuses with the SAME shape sentence
      err="$( mktemp )"
      "$BIN" "$REPO" $argv --since=2026-13-45 --no-cache >/dev/null 2>"$err"; rc=$?
      { [ "$rc" -ne 0 ] && grep -q 'neither a git revision nor a real calendar date' "$err"; } \
        && ok "N4b $flag --since=2026-13-45 (impossible): refuses with the ONE shape sentence" \
        || no "N4b $flag --since=2026-13-45: exit $rc / stderr=$( head -c 140 "$err" ) — the hosts do not answer a bad value the same way"
      rm -f "$err"
      # (iii) an UNREACHABLE-but-real value: the answer is decided by the host's DECLARED CLASS, and by
      #       nothing else. This is the half wave 1 left behaviourally split.
      err="$( mktemp )"
      out="$( "$BIN" "$REPO" $argv --since=1999-01-01 --no-cache 2>"$err" )"; rc=$?
      if [ "$needsBaseline" = "true" ]; then
        { [ "$rc" -eq 1 ] && [ -z "$out" ] && grep -q 'resolves to no commit' "$err" && grep -q '1999-01-01' "$err"; } \
          && ok "N4b $flag (BASELINE class) --since=1999-01-01: refuses with the shared no-baseline sentence naming the value" \
          || no "N4b $flag is declared needsBaseline=true but --since=1999-01-01 gave exit $rc / stderr=$( head -c 140 "$err" ) — declared class and behaviour disagree"
      else
        { [ "$rc" -eq 0 ] && printf '%s' "$out" | perl -0pe 's#<!--.*?-->##gs' | grep -q 'window="1999-01-01'; } \
          && ok "N4b $flag (WINDOW class) --since=1999-01-01: answers with the window stamped as given (1999.. is all of history)" \
          || no "N4b $flag is declared needsBaseline=false but --since=1999-01-01 gave exit $rc, window=$( printf '%s' "$out" | grep -o 'window=\"[^\"]*\"' | head -1 ) — declared class and behaviour disagree"
      fi
      rm -f "$err"
    done 3<<< "$SINCE_ROWS"
    ;;
esac
# SOURCE: the host list is spelled ONCE. main.cpp used to carry its own copy (`!cfg.sliceSpec.empty()`), which
# is how "one policy" could mean "one resolver" while a sixth consumer inherited the window class by omission.
grep -q 'activeSinceHostNeedsBaseline' "$SRCDIR/main.cpp" \
  && ok "N4b source: main.cpp reads the class off kSinceHosts (no second copy of the host list)" \
  || no "N4b source: main.cpp decides the baseline class without kSinceHosts — the host list is spelled twice again"
grep -qE '!c\.since\.empty\(\) && !anySinceHostActive' "$SRCDIR/cli.h" \
  && ok "N4b source: the alone-refusal reads the same table (one enumeration, two decisions)" \
  || no "N4b source: checkFlagPairings re-spells the host list instead of reading kSinceHosts"

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
if [ "$r1" = "$r2" ]; then ok "--since=HEAD~3 deterministic run-to-run"; else no "--since=HEAD~3 not deterministic"; fi

rm -f "$REPO/PWNED"
"$BIN" "$REPO" --hotspots --since='HEAD~3; touch '"$REPO"'/PWNED' --no-cache >/dev/null 2>&1
if [ ! -f "$REPO/PWNED" ]; then ok "shell-metacharacter --since executes nothing (quoted safely)"; else no "shell injection via --since!"; fi

# ── the git SINK (2026-09-10): git is handed the RESOLVED commit, never the caller's --since string ────────────
# resolveSinceScope proved a revision with `rev-parse --verify --quiet '<val>^{commit}'`, kept the RAW value, and
# sinceLogArgs spliced it into `git log '<val>..'` as its own argv entry. shSingleQuote stops the SHELL, not git:
# git reads a leading '-' as an OPTION (prrefsafecheck.sh's --pr-context=--output=FILE is the shipped instance of
# the class). Nothing in ripwire refused one; git's rev-parse happened to. The house rule is gitResolveCommitSha's:
# refuse a leading '-', trust only a bare-sha answer, hand git THAT. Measured on the pre-fix binary (b3b70d7a):
#   --since='-17 days ago'   passed looksLikeDate; git got `--before=-17 days ago` and `--since=-17 days ago`; exit 0
#   --since='^HEAD~3'        rev-parse --verify answers '^<sha>' at rc 0; stamped window="^HEAD~3" commits="0", exit 0
#   --since=<branch>         git log got '<branch>..': the caller's string, not the sha rev-parse had just resolved
# S0 fixture presence. S1 a branch and an annotated tag give bytes identical to the same run given the sha, on every
# kSinceHosts row, once the echoed value (window=, <since rev=>) is normalised; the names are sha-length, so
# est_tokens= cannot move with the spelling. S2 through a PATH shim, every WINDOW host's git log range is '<sha>..',
# never '<ref>..'. S3 a value beginning with '-' refuses on every host AND reaches no git argv. S4 '^HEAD~3' refuses
# on every host: a rev-parse answer that is not a bare object name is not a revision.
SHA3="$( git -C "$REPO" rev-parse HEAD~3 )"
padToSha(){ s="$1"; while [ "${#s}" -lt "${#SHA3}" ]; do s="${s}x"; done; printf '%s' "$s"; }
BR="$( padToSha sinceprobe-branch- )"; TG="$( padToSha sinceprobe-tag- )"
git -C "$REPO" branch "$BR" HEAD~3; git -C "$REPO" tag -a "$TG" -m probe HEAD~3
{ [ "$( git -C "$REPO" rev-parse "$BR^{commit}" )" = "$SHA3" ] && [ "$( git -C "$REPO" rev-parse "$TG^{commit}" )" = "$SHA3" ] \
  && [ "$( git -C "$REPO" cat-file -t "$TG" )" = "tag" ] && [ "${#BR}" -eq "${#SHA3}" ] && [ "${#TG}" -eq "${#SHA3}" ]; } \
  && ok "S0 fixture: a branch and an annotated TAG OBJECT both peel to HEAD~3; both names are ${#SHA3} bytes, like the sha" \
  || no "S0 fixture: the probe refs do not peel to HEAD~3 or are not sha-length — S1-S4 cannot conclude"

normSince(){ sed -e "s/$BR/@SINCE/g" -e "s/$TG/@SINCE/g" -e "s/$SHA3/@SINCE/g"; }
s1Rows=0
while read -r flag needsBaseline <&3; do
  [ -z "$flag" ] && continue
  argv="$( sinceHostArgv "$flag" )"
  outSha="$( "$BIN" "$REPO" $argv --since="$SHA3" --no-cache 2>/dev/null </dev/null )"; rcSha=$?
  for ref in "$BR" "$TG"; do
    outRef="$( "$BIN" "$REPO" $argv --since="$ref" --no-cache 2>/dev/null </dev/null )"; rcRef=$?
    # presence: both runs answered, and the ref run really ECHOES the ref — the one difference normSince removes
    if [ "$rcSha" -eq 0 ] && [ "$rcRef" -eq 0 ] && [ -n "$outSha" ] && printf '%s' "$outRef" | grep -qF -- "$ref" \
       && [ "$( printf '%s' "$outRef" | normSince )" = "$( printf '%s' "$outSha" | normSince )" ]; then
      ok "S1 $flag --since=${ref%%x*}…: byte-identical to --since=<sha> apart from the echoed value"
    else
      no "S1 $flag --since=$ref vs --since=$SHA3: exit $rcRef/$rcSha, diff: $( diff <( printf '%s' "$outRef" | normSince ) <( printf '%s' "$outSha" | normSince ) | head -3 | tr '\n' ' ' | head -c 240 )"
    fi
  done
  s1Rows=$(( s1Rows + 1 ))
done 3<<< "$SINCE_ROWS"
if [ "$s1Rows" -ge 5 ]; then ok "S1 covered $s1Rows kSinceHosts rows"; else no "S1 covered only $s1Rows host row(s) — the table enumeration did not run"; fi

REALGIT="$( command -v git )"
SHIMLOG="$SHIMDIR/argv.log"
cat > "$SHIMDIR/git" <<EOF
#!/bin/bash
{ printf 'CALL\n'; for a in "\$@"; do printf 'ARG %s\n' "\$a"; done; } >> "$SHIMLOG"
exec "$REALGIT" "\$@"
EOF
chmod +x "$SHIMDIR/git"
shimSawRef=0
while read -r flag needsBaseline <&3; do
  [ "$needsBaseline" = "false" ] || continue            # --slice compares against baselineSha itself; it builds no log range
  argv="$( sinceHostArgv "$flag" )"
  rm -f "$SHIMLOG"
  PATH="$SHIMDIR:$PATH" "$BIN" "$REPO" $argv --since="$BR" --no-cache >/dev/null 2>&1 </dev/null; rc=$?
  grep -qxF "ARG $BR^{commit}" "$SHIMLOG" 2>/dev/null && shimSawRef=1   # the resolve probe carried the ref: the shim is live
  if [ "$rc" -eq 0 ] && grep -qxF "ARG $SHA3.." "$SHIMLOG" 2>/dev/null && ! grep -qF "ARG $BR.." "$SHIMLOG"; then
    ok "S2 $flag --since=<branch>: git log's range is '<sha>..' (the resolved commit), never '<branch>..'"
  else
    no "S2 $flag --since=<branch>: exit $rc; git saw $( grep -F -e "$BR" -e "$SHA3" "$SHIMLOG" 2>/dev/null | sort -u | tr '\n' ' ' | head -c 240 )"
  fi
done 3<<< "$SINCE_ROWS"
[ "$shimSawRef" -eq 1 ] \
  && ok "S2 control: the shim logged the ref in git's resolve probe, so an ABSENCE in S3 is evidence, not a dead shim" \
  || no "S2 control: the shim never logged the ref — PATH did not reach git, and S3's absence arm cannot conclude"

for val in "-17 days ago" "--output=$SHIMDIR/PWNED"; do
  label="${val%%=*}"
  while read -r flag needsBaseline <&3; do
    [ -z "$flag" ] && continue
    argv="$( sinceHostArgv "$flag" )"
    rm -f "$SHIMLOG" "$SHIMDIR/PWNED"; err="$( mktemp )"
    out="$( PATH="$SHIMDIR:$PATH" "$BIN" "$REPO" $argv --since="$val" --no-cache 2>"$err" </dev/null )"; rc=$?
    if [ "$rc" -eq 1 ] && [ -z "$out" ] && grep -qF -- "$val" "$err" && ! grep -qF -- "$val" "$SHIMLOG" 2>/dev/null && [ ! -e "$SHIMDIR/PWNED" ]; then
      ok "S3 $flag --since='$label': refused before git (exit 1, empty stdout, value named, in no git argv)"
    else
      no "S3 $flag --since='$label': exit $rc, stdout $( printf '%s' "$out" | grep -o 'window="[^"]*"' | head -1 ), git saw: $( grep -F -- "$val" "$SHIMLOG" 2>/dev/null | sort -u | tr '\n' ' ' | head -c 200 )"
    fi
    rm -f "$err"
  done 3<<< "$SINCE_ROWS"
done

caret="$( git -C "$REPO" rev-parse --verify --quiet '^HEAD~3^{commit}' 2>/dev/null )"; crc=$?
{ [ "$crc" -eq 0 ] && [ "$caret" = "^$SHA3" ]; } \
  && ok "S4 presence: git itself answers '^HEAD~3^{commit}' with '^<sha>' at rc 0 — a non-sha answer ripwire must distrust" \
  || no "S4 presence: git answered '^HEAD~3^{commit}' with '$caret' (rc $crc) — the rows below cannot tell ripwire's check from git's"
while read -r flag needsBaseline <&3; do
  [ -z "$flag" ] && continue
  argv="$( sinceHostArgv "$flag" )"
  err="$( mktemp )"
  out="$( "$BIN" "$REPO" $argv --since='^HEAD~3' --no-cache 2>"$err" </dev/null )"; rc=$?
  { [ "$rc" -eq 1 ] && [ -z "$out" ] && grep -qF -- "'^HEAD~3'" "$err"; } \
    && ok "S4 $flag --since='^HEAD~3': refused — '^<sha>' is not a bare object name, so not a revision" \
    || no "S4 $flag --since='^HEAD~3': exit $rc, $( printf '%s' "$out" | grep -o 'window="[^"]*"\|commits="[^"]*"' | head -2 | tr '\n' ' ' )— a non-sha rev-parse answer was trusted as a revision"
  rm -f "$err"
done 3<<< "$SINCE_ROWS"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }

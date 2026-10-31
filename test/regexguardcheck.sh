#!/usr/bin/env bash
# regexguardcheck.sh — src/regexguard.h is THE owner of every user-authored regular expression, and this gate
# is what keeps it the only one.
#
# WHY THIS EXISTS. `--regex` was protected: src/search.h screened the pattern structurally (non-portable
# escapes, the nested-quantifier backtracking family) and refused it by name before either standard library's
# engine saw it (test/regexbombcheck.sh). Three other entry points hand a user's pattern to the same engine and
# skipped that screen, and none of them guarded the MATCH either:
#
#     ripwire rx --graph-query='file(all,"(a+)+z")'          rc=134  libc++abi: uncaught std::regex_error
#     ripwire rx --arch=rules   (deny path zz/.* -> (a+)+z)   rc=134  same abort
#     ripwire rx --match='… (#match? @id "(a+)+z")'           rc=0    the throw was swallowed: a row the
#                                                                     predicate never decided is KEPT
#
# (Apple libc++, whose engine throws error_complexity; on libstdc++, which has no budget, the same calls
# backtrack without end.) And `file()` matched the path WITH the checkout directory in front of it, so
# `file(all,"alpha")` selected every symbol in a clone named `repo_alpha` and none in `repo_beta` — an answer
# decided by where the tree was cloned, which --arch fixed for its own rules long ago and --graph-query never
# got.
#
# ARMS
#   (a) SCREEN AT EVERY ENTRY POINT — a catastrophic pattern through --graph-query file(), an --arch path-rule
#       (FROM and TO), a --match #match? predicate, a --lint-rules #match? predicate and --regex is REFUSED:
#       exit 1, bounded time, never a signal death, the pattern and the construct named on stderr. Each entry
#       point also has a POSITIVE CONTROL: an ordinary pattern on the same fixture still answers.
#   (b) MATCH-TIME EXHAUSTION IS DISCLOSED, NEVER SILENT — the screen is a static approximation, so a regex_error
#       thrown DURING a match must refuse the answer by name rather than abort or report a count the engine never
#       finished measuring. (b1) is portable: the non-NDEBUG fault switch RIPWIRE_FAULT_REGEX_MATCH=1 makes every
#       guarded match throw, on every standard library, and each entry point must refuse. The flavour is ASKED of the
#       binary with a sibling fault switch whose alert is independent of this seam (prcontextcheck's idiom), so a
#       Release build reports the arm unobservable instead of passing or failing it for a switch it compiled out.
#       (b2) is RE-SCOPED (Q7, 2026-10-12): the screen used to ADMIT the overlapping-alternation bomb (a|a)+z and
#       leave it to libc++'s engine to abandon mid-match; Phase 1 now REFUSES it statically at every entry point, so
#       (b2) asserts that closure instead. The abandonment path itself stays proven by (b1).
#   (c) STATIC — no std::regex construction, match, iterator, result type or <regex> include in src/ outside
#       src/regexguard.h, over source with comments and string literals blanked (so the words in prose do not
#       count). The allowlist carries a reason per row, a stale row FAILS, and the detector is proved on a
#       planted file (fires) and on a planted clean file (silent) before its verdict on the tree is believed. The
#       allowlist is EMPTY since src/redact.h stopped spelling the engine (arm (o)).
#   (e) AN --arch TO PATTERN THAT ONLY FAILS AFTER SUBSTITUTION IS REFUSED, NOT INERT — `a{2,\1}` is a well-formed
#       template that passes the screen, and on an edge whose FROM captured "1" it becomes `a{2,1}`, an invalid
#       interval on every standard library. That rule used to be skipped silently for the edge (exit 0, violations
#       unreported); it must refuse by name, quoting the substituted text, with the other edges' rules still judged.
#   (f) THE SKILL SCANNER READS UNTRUSTED FILES, so its constant patterns go through the same boundary: (f1) the
#       linear EXFILTRATE:net-exfil decision agrees line for line with the regex it replaced (plus #353's destination
#       rule, re-specified in the oracle), over generated lines
#       judged by an independent oracle (python's re, with `.` spelled [^\r\n] as ECMAScript reads it); (f2) a 200,000-byte
#       fenced `curl curl …` line scans in bounded time (the regex was quadratic: >60 s); (f3) an abandoned match
#       fails CLOSED — a CRITICAL SCAN-INCOMPLETE:regex-abandoned finding at exit 2, never a clean exit 0 and never an
#       abort inside wrap's noexcept scan.
#   (g) THE STACK BOUND — std::regex compiles by recursion, and a 20,000-byte literal --regex died with SIGBUS in a
#       512 KiB grep worker. A pattern over kRegexMaxPatternBytes (2,048) or nesting groups deeper than
#       kRegexMaxGroupDepth (64) is refused by name; exactly at each limit it still compiles.
#   (h) AN UNDECIDED #match? SAYS WHY — a capture-typed `(#match? @f @s)` compiles each match's own text, and three
#       different things can stop it: the screen refuses the captured text, the text does not compile, or the engine
#       abandons the match. One counter and one sentence ("the regex engine abandoned the match") used to cover all
#       three. Each cause now has its own run, fixture and wording; the refusal names the FIRST site (lowest file, then
#       byte) with the captured text, is byte-identical run to run, and --lint-rules says the same.
#   (i) --arch DECIDES DENY FIRST — an allow that cannot be judged must not turn a determinable "no deny can forbid
#       this edge" into a refusal; an undecided allow matters only when a deny fires and no allow matches, and a
#       later allow that matches still permits the edge. RE-SCOPED (Q7, 2026-10-12): the vehicle is now a
#       substituted-TO match-time refusal (portable on every standard library), because the screen now refuses the
#       old (a|a)+z vehicle at LOAD — see arm (b2).
#   (j) THE LITERAL PATHS ARE THE ENGINE — src/regexguard.h answers a literal (or `|`-joined literals, one optionally
#       `^`/`$`-anchored) with byte kernels, and never hands the engine a line holding none of a pattern's required
#       literals. test/regexlines_harness.cpp diffs both, and the long-line skip policy, against std::regex itself over
#       adversarial, generated and corpus patterns (every --regex the docs/skills/gates spell, every #match? a query or
#       lint pack carries) × CRLF/LF/empty-line texts, under both syntax sets; 0 mismatches and its coverage floors, and
#       a mutated copy of the header (an alternation that resumes one byte past a match) must go red.
#   (k) A LONG LINE ANSWERS OR SAYS IT WAS SKIPPED — libstdc++'s matcher recurses once per state it visits, and
#       `--regex='a*b'` died with SIGSEGV on a ~26–45 KB matching line on Linux. A 300 KB matching line now exits 0: matched
#       in full where the engine does not recurse (libc++), or skipped and disclosed (regex_lines_skipped=, regex_line_max=,
#       counts_floor, and the legend definition of both IN THE DIALECT THAT ANSWER CARRIES — the default posture's compact
#       readings, the `LONG LINES:` block under --legend=full) where it does. A 2 MB line with no 'b' is ruled out by the required
#       literal on every engine (it crashed libstdc++ and ran quadratic on libc++), a literal alternation over a 3 MB line
#       never reaches the engine, and a literal --grep answer is unchanged.
#   (l) THE BOUND HOLDS WHERE IT EXISTS — on a recursing engine, for three shapes (a plain repeat, an alternation loop, a
#       loop before a lookahead), a line of exactly regex_line_max bytes is matched at exit 0 and one byte more is skipped.
#   (m) THE SKIP PATH ON EVERY ENGINE — the non-NDEBUG fault switch RIPWIRE_FAULT_REGEX_LINE_BOUND=1 caps the bound at 64
#       bytes: a 104-byte line is skipped, counted and floored, and the DEFAULT, compact and full legends each define both
#       attributes in their own wording (the only place a libc++ host checks them, since (k) never skips there); a literal
#       pattern and a line lacking the required literal are never skipped; the exact-"1" control changes nothing.
#   (n) ONE STACK FOR THE WHOLE SCAN — the scan threads settle one size (the smallest any got) before a single file is
#       read, so no file's skip-or-match depends on which thread took it. The fault switch RIPWIRE_FAULT_SCAN_STACK_MIXED=1
#       gives odd threads half the stack; with RIPWIRE_FAULT_REGEX_LINE_BOUND=1 (bound = stack >> 22) 48 files of a 50-byte
#       line are then all skipped at regex_line_max 32, five runs byte-identical, and regex_stack_bytes= discloses the
#       smaller stack even at 0 skips. The per-thread bound this replaced skipped 24-27 of the 48, varying run to run.
#   (o) REDACTION HAS NO ENGINE TO OVERFLOW — src/redact.h's nine prefixed rules are matched structurally;
#       test/redactshape_harness.cpp diffs each against its own table regex (0 mismatches, every rule matched), a mutated
#       threshold goes red, and --expand over a file holding "sk-" and a 200 KB token run exits 0 with the key redacted
#       (libstdc++'s regex overflowed the stack on it).
#   (d) file() IS ROOT-RELATIVE — two clones of one tree at different directory names, each run with an
#       absolute and a relative root spelling, must give the SAME count for a pattern naming one clone's
#       directory, and an anchored `^src/` must select the src/ symbols (it selected nothing under an
#       absolute root, because the path began with the checkout's own directories).
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/regexguardcheck.sh
#         RIPWIRE_BIN=<origin/main binary> bash test/regexguardcheck.sh    # must FAIL: (a) rc=134, (b), (c), (d)
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "regexguardcheck: python3 required for the static arm"; exit 2; }
echo "regexguardcheck: BIN=$BIN"

# A refusal must be BOUNDED — on libstdc++ an unguarded bomb backtracks without end — so every run that could
# reach an engine is wall-clock capped. No timeout(1) on a stock macOS: background run plus a polling wait.
capRun(){                        # capRun <seconds> <outfile> <errfile> <args…> -> echoes the exit status, or TIMEOUT
    local capSeconds="$1" outPath="$2" errPath="$3"; shift 3
    "$BIN" "$@" >"$outPath" 2>"$errPath" &
    local runPid=$! waitedTenths=0 capTenths=$(( capSeconds * 10 ))
    while kill -0 "$runPid" 2>/dev/null; do
        [ "$waitedTenths" -ge "$capTenths" ] && { kill -9 "$runPid" 2>/dev/null; wait "$runPid" 2>/dev/null; echo TIMEOUT; return; }
        sleep 0.1; waitedTenths=$(( waitedTenths + 1 ))
    done
    wait "$runPid"; echo $?
}

# ── the fixture: a directory whose NAME is a long run of 'a' (the backtracking bait lives in the PATH, which is
#    what file() and --arch match), an include edge from zz/ into it, a C++ file whose identifiers a #match?
#    predicate can select and whose string literal (88 'a') a real-engine #match? arm can exhaust on, and a
#    markdown line of 4000 'a' for --regex. Each bait run is followed by a non-'a' byte and then a 'z': a subject
#    holding no 'z' is ruled out by (a|a)+z's required literal before the engine is asked (src/regexguard.h), so
#    the real-engine arms need the 'z' present for the engine to have anything to abandon. Written here so it cannot
#    drift; the rules files sit OUTSIDE it. ────
RUNA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
FIX="$TMP/rxfix"
mkdir -p "$FIX/$RUNA" "$FIX/zz" "$TMP/rules_bomb" "$TMP/rules_ok"
printf 'int aaaa_one() { return 1; }\nint aaaa_two() { return aaaa_one(); }\n' >"$FIX/$RUNA/${RUNA}_z.h"
printf '#include "%s_z.h"\nint aaaa_three() { return aaaa_two(); }\n' "$RUNA" >"$FIX/$RUNA/$RUNA.c"
printf '#include "../%s/%s_z.h"\nint zz_caller() { return aaaa_one(); }\n' "$RUNA" "$RUNA" >"$FIX/zz/b.c"
printf '#include "../%s/%s_z.h"\nint zz_digit() { return aaaa_two(); }\n' "$RUNA" "$RUNA" >"$FIX/zz/d1.c"
printf 'int foo_alpha() { return 0; }\nint foo_beta() { return foo_alpha(); }\nconst char* bait = "%s_z";\n' "$RUNA$RUNA" >"$FIX/zz/q.cpp"
{ printf '# bait\n'; head -c 4000 /dev/zero | tr '\0' 'a'; printf '_z\nzz marker line\n'; } >"$FIX/zz/bait.md"
cat >"$TMP/rules_bomb/bomb.yml" <<'YML'
- id: rx-bomb
  language: cpp
  severity: warn
  message: a catastrophic predicate
  query: |
    (function_declarator declarator: (identifier) @fn (#match? @fn "(a+)+z")) @hit
YML
cat >"$TMP/rules_ok/ok.yml" <<'YML'
- id: rx-ok
  language: cpp
  severity: warn
  message: an ordinary predicate
  query: |
    (function_declarator declarator: (identifier) @fn (#match? @fn "^foo_")) @hit
YML
printf 'deny path zz/.* -> (a+)+z\n'         >"$TMP/arch_to_bomb.txt"
printf 'deny path (a+)+z -> .*\n'            >"$TMP/arch_from_bomb.txt"
printf 'deny path zz/.* -> a+/\n'            >"$TMP/arch_ok.txt"
printf 'deny path zz/.* -> (a|a)+z\n'        >"$TMP/arch_alt.txt"
printf '%s\n' 'deny path zz/d(\d)\.c -> a{2,\1}'  >"$TMP/arch_subst.txt"
printf '%s\n' 'deny path zz/(\w+)/.* -> (\1'      >"$TMP/arch_to_unbalanced.txt"
printf '%s\n' 'deny path zz/d(\d)\.c -> a{1,\1}'  >"$TMP/arch_subst_ok.txt"

MATCH_BOMB='(function_declarator declarator: (identifier) @fn (#match? @fn "(a+)+z"))'
MATCH_OK='(function_declarator declarator: (identifier) @fn (#match? @fn "^foo_"))'
MATCH_ALT='((string_literal) @s (#match? @s "(a|a)+z"))'   # the literal holds 88 'a': a capture long enough to exhaust

# ── (a) the screen, at every entry point ──────────────────────────────────────────────────────────────────────
refusedByName(){                 # refusedByName <label> <pattern> <args…>
    local label="$1" pat="$2"; shift 2
    local rc; rc="$( capRun 20 "$TMP/a.out" "$TMP/a.err" "$FIX" --no-cache "$@" )"
    if [ "$rc" = TIMEOUT ]; then
        no "(a) $label: still running after 20 s — the pattern was handed to an engine with no budget"
        return
    fi
    if [ "$rc" -ge 128 ]; then
        no "(a) $label: signal death, exit $rc ($( grep -m1 -o 'terminating.*' "$TMP/a.err" | head -c 120 ))"
        return
    fi
    if [ "$rc" -eq 1 ]; then ok "(a) $label: refused at exit 1"; else no "(a) $label: exit $rc (expected a refusal at exit 1)"; fi
    grep -qF -- "$pat" "$TMP/a.err" && ok "(a) $label: the refusal names the pattern" \
        || no "(a) $label: stderr does not name the pattern: $( head -c 200 "$TMP/a.err" )"
    grep -qi 'backtrack' "$TMP/a.err" && ok "(a) $label: the refusal names the construct (catastrophic backtracking)" \
        || no "(a) $label: stderr does not name the construct: $( head -c 200 "$TMP/a.err" )"
    grep -qE 'count="|hits="|<lint|<arch ' "$TMP/a.out" && no "(a) $label: an answer element was printed beside the refusal" \
        || ok "(a) $label: no answer element on stdout"
}
answers(){                       # answers <label> <expected rc> <stdout ERE that proves an answer> <args…>
    local label="$1" wantRc="$2" proof="$3"; shift 3
    local rc; rc="$( capRun 20 "$TMP/c.out" "$TMP/c.err" "$FIX" --no-cache "$@" )"
    if [ "$rc" = "$wantRc" ] && grep -qE -- "$proof" "$TMP/c.out"; then
        ok "(a) control, $label: an ordinary pattern still answers (exit $rc)"
    else
        no "(a) control, $label: exit $rc, answer proof /$proof/ $( grep -qE -- "$proof" "$TMP/c.out" && echo present || echo ABSENT ): $( head -c 200 "$TMP/c.err" )"
    fi
}

refusedByName "--graph-query file()"      '(a+)+z' --graph-query='file(all,"(a+)+z")'
answers       "--graph-query file()" 0    'count="[1-9]' --graph-query='file(all,"q\.cpp")'
refusedByName "--arch path-rule TO"       '(a+)+z' --arch="$TMP/arch_to_bomb.txt"
refusedByName "--arch path-rule FROM"     '(a+)+z' --arch="$TMP/arch_from_bomb.txt"
answers       "--arch path-rule" 2        'fromLayer="path"' --arch="$TMP/arch_ok.txt"
refusedByName "--match #match?"           '(a+)+z' "--match=$MATCH_BOMB"
answers       "--match #match?" 0         'hits="[1-9]' "--match=$MATCH_OK"
refusedByName "--lint-rules #match?"      '(a+)+z' --lint-rules="$TMP/rules_bomb"
answers       "--lint-rules #match?" 0    'rule="rx-ok"' --lint-rules="$TMP/rules_ok"
refusedByName "--regex (regression)"      '(a+)+z' --regex='(a+)+z'
answers       "--regex" 0                 'hits="[1-9]' --regex='zz marker'

# determinism of a refusal: stderr is a pure function of the pattern
rc1="$( capRun 20 /dev/null "$TMP/d1.err" "$FIX" --no-cache --graph-query='file(all,"(a+)+z")' )"
rc2="$( capRun 20 /dev/null "$TMP/d2.err" "$FIX" --no-cache --graph-query='file(all,"(a+)+z")' )"
if [ "$rc1" = 1 ] && [ "$rc2" = 1 ] && [ -s "$TMP/d1.err" ] && cmp -s "$TMP/d1.err" "$TMP/d2.err"; then ok "(a) the file() refusal is byte-identical run to run"
else no "(a) the file() refusal is not a deterministic refusal (exit $rc1/$rc2, stderr identical: $( cmp -s "$TMP/d1.err" "$TMP/d2.err" && echo yes || echo no ))"; fi

# ── (b1) match-time exhaustion through the fault switch — every standard library, non-NDEBUG flavour ───────────
RIPWIRE_FAULT_CHARGE_BUFFER=1 "$BIN" "$FIX" --top-k=5 --pack-signatures --no-cache >/dev/null 2>"$TMP/probe.err"
if grep -aq 'open_memstream failed' "$TMP/probe.err"; then FAULTS=1; else FAULTS=0; fi

# The whole exhaustion contract, for every entry point, in one helper shared by (b1) and (b2): a bounded exit 1, never
# a signal death; stderr says the engine abandoned the match AND names what the reader must fix — the pattern, or for
# --lint-rules the rule id (the per-evaluation counter is kept per rule group, so the rules are what can be named);
# and no answer element on stdout. Each check is its own row, so a refusal that names nothing cannot pass.
abandonedContract(){             # abandonedContract <arm> <label> <rc> <out> <err> <needle>
    local arm="$1" label="$2" rc="$3" out="$4" err="$5" needle="$6"
    if [ "$rc" = TIMEOUT ] || [ "$rc" -ge 128 ]; then
        no "$arm $label: exit $rc (expected a bounded refusal at exit 1)$( grep -m1 -o 'terminating.*' "$err" | head -c 120 )"
        return
    fi
    if [ "$rc" -eq 1 ]; then ok "$arm $label: an abandoned match refuses at exit 1"
    else no "$arm $label: exit $rc — an abandoned match was answered anyway (silent)"; fi
    if grep -q 'abandoned the match' "$err"; then ok "$arm $label: the refusal says the engine abandoned the match"
    else no "$arm $label: stderr does not disclose the abandoned match: $( head -c 200 "$err" )"; fi
    if grep -qF -- "$needle" "$err"; then ok "$arm $label: the refusal names $needle"
    else no "$arm $label: the refusal does not name $needle: $( head -c 200 "$err" )"; fi
    if grep -qE 'count="|hits="|<lint|<arch |<match ' "$out"; then no "$arm $label: an answer element was printed beside the refusal"
    else ok "$arm $label: no answer element on stdout"; fi
}
exhaustedByName(){               # exhaustedByName <label> <needle> <args…>   (run under RIPWIRE_FAULT_REGEX_MATCH=1)
    local label="$1" needle="$2"; shift 2
    local rc; rc="$( RIPWIRE_FAULT_REGEX_MATCH=1 capRun 20 "$TMP/b.out" "$TMP/b.err" "$FIX" --no-cache "$@" )"
    abandonedContract "(b1)" "$label" "$rc" "$TMP/b.out" "$TMP/b.err" "$needle"
}
if [ "$FAULTS" -eq 1 ]; then
    exhaustedByName "--graph-query file()" 'q\.cpp'    --graph-query='file(all,"q\.cpp")'
    # The abandonment branch raises the same DISCLOSE its compile-refusal sibling does (CodeRabbit on #277):
    # read from the run just above, on this fault-switch (non-NDEBUG) flavour, where the alert is compiled in.
    grep -qF 'query: file() regex match abandoned by the engine' "$TMP/b.err" \
        && ok "(b1) --graph-query file(): the abandonment branch raises its DISCLOSE, like the refusal branch" \
        || no "(b1) --graph-query file(): no DISCLOSE on the abandonment branch: $( head -c 200 "$TMP/b.err" )"
    exhaustedByName "--arch path-rule"     'a+/'       --arch="$TMP/arch_ok.txt"
    exhaustedByName "--match #match?"      '^foo_'     "--match=$MATCH_OK"
    exhaustedByName "--lint-rules #match?" 'rx-ok'     --lint-rules="$TMP/rules_ok"
    exhaustedByName "--regex"              'zz marker' --regex='zz marker'
    # the switch is exact "1", like every fault switch in this tree: anything else leaves the answer alone
    RIPWIRE_FAULT_REGEX_MATCH=10 "$BIN" "$FIX" --no-cache --graph-query='file(all,"q\.cpp")' >"$TMP/b10.out" 2>/dev/null
    grep -q 'count="[1-9]' "$TMP/b10.out" && ok "(b1) control: RIPWIRE_FAULT_REGEX_MATCH=10 is not ON (exact \"1\" only)" \
        || no "(b1) control: RIPWIRE_FAULT_REGEX_MATCH=10 changed the answer"
else
    printf '  INFO  (b1) this binary compiles fault switches out (NDEBUG): the injected exhaustion is unobservable BY DESIGN here; the plain-flavour leg proves it\n'
    RIPWIRE_FAULT_REGEX_MATCH=1 "$BIN" "$FIX" --no-cache --graph-query='file(all,"q\.cpp")' >"$TMP/bn.out" 2>/dev/null
    grep -q 'count="[1-9]' "$TMP/bn.out" && ok "(b1) consistency: with the switch compiled out, file() still answers" \
        || no "(b1) consistency: a flavour without fault switches changed its answer under RIPWIRE_FAULT_REGEX_MATCH=1"
fi

# ── (b2) the STATIC CLOSURE of the formerly-documented gap (RE-SCOPED 2026-10-12, Q7, PM-authorised) ───────────
# This arm used to assert the OPPOSITE of what it asserts now: that `(a|a)+z` PASSES the structural screen and is
# abandoned mid-match by the real engine on libc++. Phase 1 closes exactly that gap — `(a|a)+z` is now refused
# STATICALLY at every entry point, before a byte reaches an engine, on every platform — which is the spec's Objective.
# The arm is re-scoped to assert that closure. It is a strict IMPROVEMENT: the same pattern is stopped by the screen
# rather than by a match-time catch only libc++ has.
#
# NO GUARANTEE LOSES ITS ARM (PM re-scope rule): the real-engine abandonment path is still proven, portably, by (b1)'s
# fault switch above (every entry point, every standard library) and by test/regexbombcheck.sh (7). (The guard's
# per-file match budget — round 5's second cause, whose (b2) note pointed at regexbombcheck (6) — was removed in the
# PR #397 review; a stopped scan has one cause again.) What changes here is only the MECHANISM that catches `(a|a)+z`:
# a match-time catch -> a static refusal. ROUND 6 re-vehicles the real-engine leg: the wrapped alternation forms it
# used to ride are refused at admission since M2-d/M2-e, so the leg rides a pattern the screen still admits —
# see the vehicle note at FIVESTAR below for why it is `(a*){20}b` and not the `a*a*a*a*a*b` round 6 chose.
LINKS_LIBCXX=0
if command -v otool >/dev/null 2>&1 && otool -L "$BIN" 2>/dev/null | grep -q 'libc++'; then LINKS_LIBCXX=1; fi
if command -v ldd >/dev/null 2>&1 && ldd "$BIN" 2>/dev/null | grep -q 'libc++\.so'; then LINKS_LIBCXX=1; fi
closedStatically(){              # closedStatically <label> <pattern> <args…>
    local label="$1" pat="$2"; shift 2
    local rc; rc="$( capRun 20 "$TMP/r.out" "$TMP/r.err" "$FIX" --no-cache "$@" )"
    if [ "$rc" = TIMEOUT ]; then
        no "(b2) $label: still running after 20 s — the pattern reached an engine with no budget"
        return
    fi
    if [ "$rc" -ge 128 ]; then
        no "(b2) $label: signal death, exit $rc ($( grep -m1 -o 'terminating.*' "$TMP/r.err" | head -c 120 ))"
        return
    fi
    if [ "$rc" -eq 1 ]; then ok "(b2) $label: refused STATICALLY at exit 1 (the gap is closed before the engine)"
    else no "(b2) $label: exit $rc (expected a static refusal at exit 1)"; fi
    grep -qF -- "$pat" "$TMP/r.err" && ok "(b2) $label: the refusal names the pattern" \
        || no "(b2) $label: stderr does not name the pattern: $( head -c 200 "$TMP/r.err" )"
    grep -qi 'backtrack' "$TMP/r.err" && ok "(b2) $label: the refusal names the construct (catastrophic backtracking)" \
        || no "(b2) $label: stderr does not name the construct: $( head -c 200 "$TMP/r.err" )"
    grep -qE 'count="|hits="|<lint|<arch |<match ' "$TMP/r.out" && no "(b2) $label: an answer element was printed beside the refusal" \
        || ok "(b2) $label: no answer element on stdout"
}
if [ "$LINKS_LIBCXX" -eq 1 ]; then
    ok "(b2) this binary links libc++ (where the old gap was observable mid-match); the closure is asserted at every entry point below"
else
    printf '  INFO  (b2) this binary does not link libc++; the closure is asserted at every entry point below regardless\n'
fi
closedStatically "--graph-query file((a|a)+z)" '(a|a)+z' --graph-query='file(all,"(a|a)+z")'
closedStatically "--arch TO (a|a)+z"           '(a|a)+z' --arch="$TMP/arch_alt.txt"
closedStatically "--match #match? (a|a)+z"     '(a|a)+z' "--match=$MATCH_ALT"
closedStatically "--regex (a|a)+z"             '(a|a)+z' --regex='(a|a)+z'

# The REAL-ENGINE leg of (b2), re-vehicled TWICE. The arm used to prove what a REAL engine does with a pattern the
# screen LETS THROUGH; the wrapped-alternation forms that first rode it are refused at admission since M2-d/M2-e,
# so round 6 moved it to `a*a*a*a*a*b` — then the multi-quantifier residual, ADMITTED by the screen by
# construction (docs/LIMITS.md, regex-screen-multiquantifier). THIS SPEC CLOSES THAT RESIDUAL, so that vehicle is
# now refused at admission too and the leg went red — correctly: a vehicle is only a vehicle while the screen
# admits it, and the arm's guarantee (the ENGINE abandons, and the verb refuses rather than report a floor) must
# not be lost with it. `(a*){20}b` is the replacement, and it is admitted for a NON-accidental reason: it is one
# bounded repeat of a group containing one unbounded quantifier, which neither the nested arm (the OUTER `{20}` is
# bounded), nor the alternation arm (no top-level '|'), nor multi-quantifier clause 1 (one quantified atom in the
# scope) nor clause 2 (no unproven alternation) refuses. Its cost is the counted repetition of an inner star over
# a 4000-byte line — the same real-engine abandonment the leg exists to exercise.
# libc++'s engine throws error_complexity on bait.md's 4000-a line (--no-prefilter: the line must reach the
# engine, and the required-literal prefilter would rule it out); libstdc++ has no budget and would backtrack
# without end, so the no-switch leg runs where the engine has a budget, and the fault-switch leg carries the
# refuse-don't-silence contract on every flavour.
FIVESTAR='(a*){20}b'
if [ "$LINKS_LIBCXX" -eq 1 ]; then
    rc="$( capRun 30 "$TMP/r5.out" "$TMP/r5.err" "$FIX" --no-cache --no-prefilter "--regex=$FIVESTAR" )"
    abandonedContract "(b2)" "--regex $FIVESTAR (real libc++ engine)" "$rc" "$TMP/r5.out" "$TMP/r5.err" "$FIVESTAR"
else
    printf '  INFO  (b2) real-engine leg: this binary links libstdc++, whose engine has no complexity budget —\n'
    printf '        admitting %s over the 4000-a bait is the documented hang, not an assertable verdict\n' "$FIVESTAR"
fi
if [ "$FAULTS" -eq 1 ]; then
    # abandonedContract directly, NOT exhaustedByName: that helper labels every row (b1), and an arm's output must
    # name the arm that ran it — a (b1) line in the (b2) section would read as the wrong guarantee being proven.
    b2rc="$( RIPWIRE_FAULT_REGEX_MATCH=1 capRun 20 "$TMP/r2f.out" "$TMP/r2f.err" "$FIX" --no-cache --no-prefilter "--regex=$FIVESTAR" )"
    abandonedContract "(b2)" "--regex $FIVESTAR (screen-admitted, fault-injected)" "$b2rc" "$TMP/r2f.out" "$TMP/r2f.err" "$FIVESTAR"
else
    printf '  INFO  (b2) fault-switch leg: fault switches are compiled out (NDEBUG); (b1) proves the contract on this flavour\n'
fi

# ── (c) static: the engine is spelled in src/regexguard.h and nowhere else ─────────────────────────────────────
python3 - "$ROOT" "$TMP" <<'PY' >"$TMP/static.txt" 2>&1
import os, re, sys
root, tmp = sys.argv[1], sys.argv[2]
OWNER = "src/regexguard.h"
ALLOW = {
    # empty: src/redact.h, the last row, matches its rules structurally now (arm (o) is its oracle)
}
TOKENS = re.compile(r"\bstd::(?:w?regex|basic_regex)\b|\b(?:regex_(?:search|match|replace|iterator|token_iterator|error|constants|traits)|[cs]regex_(?:token_)?iterator|w[cs]?regex_(?:token_)?iterator|[cs]match|w[cs]match|[cs]sub_match|w[cs]sub_match|sub_match|match_results)\b")
INCLUDE = re.compile(r"^[ \t]*#[ \t]*include[ \t]*<regex>", re.M)

def blank(text):
    """Blank comments and string/char literals (raw strings included) to spaces, keeping every offset and newline."""
    out, i, n = list(text), 0, len(text)
    def wipe(a, b):
        for k in range(a, b):
            if out[k] != "\n":
                out[k] = " "
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i); j = n if j < 0 else j
            wipe(i, j); i = j; continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2); j = n if j < 0 else j + 2
            wipe(i, j); i = j; continue
        m = re.match(r'(?:u8|[uUL])?R"([^()\\ ]{0,16})\(', text[i:])
        if m and (i == 0 or not (text[i - 1].isalnum() or text[i - 1] == "_")):
            close = ")" + m.group(1) + '"'
            j = text.find(close, i + m.end()); j = n if j < 0 else j + len(close)
            wipe(i, j); i = j; continue
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            wipe(i, min(j + 1, n)); i = j + 1; continue
        if c == "'":
            k = i - 1
            while k >= 0 and (text[k].isalnum() or text[k] in "_."):
                k -= 1
            if k + 1 < i and text[k + 1].isdigit():
                i += 1; continue                       # a digit separator: 1'000
            j = i + 1
            while j < n and text[j] != "'":
                j += 2 if text[j] == "\\" else 1
            wipe(i, min(j + 1, n)); i = j + 1; continue
        i += 1
    s = "".join(out)
    assert len(s) == len(text) and all((a == "\n") == (b == "\n") for a, b in zip(s, text)), "blanker moved an offset"
    return s

def hits(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    s = blank(text)
    found = [(s.count("\n", 0, m.start()) + 1, m.group(0)) for m in TOKENS.finditer(s)]
    found += [(s.count("\n", 0, m.start()) + 1, "#include <regex>") for m in INCLUDE.finditer(text) if s[m.start():m.end()].strip()]
    return sorted(found)

# controls first: a detector that cannot fire, or fires on prose, decides nothing
planted = os.path.join(tmp, "planted.h")
with open(planted, "w") as fh:
    fh.write('#include <regex>\nstd::regex re( pat );\nbool b = std::regex_search( s, m, re );\n'
             'for( auto it = std::cregex_iterator( a, z, re ); it != std::cregex_iterator(); ++it ) {}\nstd::smatch caps;\n')
clean = os.path.join(tmp, "clean.h")
with open(clean, "w") as fh:
    fh.write('// std::regex_search( s, re ) in a comment\n/* std::regex r( x ); #include <regex> */\n'
             'const char* a = "std::regex_match( s, re )";\nconst char* b = R"x(std::sregex_iterator)x";\n'
             "int n = 1'000'000; char q = '\"';\nGuardedRegex guarded; RegexCaptures caps;\n")
ph, ch = hits(planted), hits(clean)
print(("PASS" if len(ph) >= 6 else "FAIL") + f"  (c) control: the detector fires on a planted file ({len(ph)} sites)")
print(("PASS" if not ch else "FAIL") + f"  (c) control: the detector is silent on engine words inside comments/strings/raw strings ({len(ch)} sites{': ' + str(ch) if ch else ''})")

scanned, violations, owner_hits, allow_hits = 0, [], 0, {k: 0 for k in ALLOW}
for dp, dn, fn in os.walk(os.path.join(root, "src")):
    dn.sort()
    for f in sorted(fn):
        if not f.endswith((".h", ".hpp", ".cpp", ".inl", ".cc", ".mm")):
            continue
        rel = os.path.relpath(os.path.join(dp, f), root)
        scanned += 1
        h = hits(os.path.join(dp, f))
        if rel == OWNER:
            owner_hits = len(h)
        elif rel in ALLOW:
            allow_hits[rel] = len(h)
        else:
            violations += [f"{rel}:{ln}: {tok}" for ln, tok in h]
print(("PASS" if scanned >= 50 else "FAIL") + f"  (c) population: {scanned} src files scanned")
print(("PASS" if owner_hits > 0 else "FAIL") + f"  (c) the owner {OWNER} exists and spells the engine ({owner_hits} sites)")
for rel, cnt in sorted(allow_hits.items()):
    print(("PASS" if cnt > 0 else "FAIL") + f"  (c) allowlist row is live: {rel} ({cnt} sites) — {ALLOW[rel]}")
if violations:
    print(f"FAIL  (c) std::regex spelled outside {OWNER} and the allowlist ({len(violations)} sites):")
    for v in violations[:40]:
        print(f"FAIL        {v}")
else:
    print(f"PASS  (c) no std::regex construction, match, iterator, result type or <regex> include outside {OWNER} and the allowlist")
PY
if ! grep -q '(c) population' "$TMP/static.txt"; then
    no "(c) the static scanner did not run to its verdict: $( head -c 300 "$TMP/static.txt" )"
fi
while IFS= read -r line; do
    case "$line" in
        PASS*) ok "${line#PASS  }" ;;
        FAIL*) no "${line#FAIL  }" ;;
        *)     no "(c) unexpected scanner output: $line" ;;
    esac
done <"$TMP/static.txt"

# ── (e) an --arch TO pattern refused only AFTER backreference substitution is refused by name ────────────────
# (e0) first, the template no capture can repair — `(\1` is unbalanced whatever lands in \1 — rejects the rules file
# at PARSE, with the line named, instead of being stored and skipped on every edge.
rc="$( capRun 20 "$TMP/e0.out" "$TMP/e0.err" "$FIX" --no-cache --arch="$TMP/arch_to_unbalanced.txt" )"
if [ "$rc" = 1 ] && grep -qF "TO path-regex '(\1' refused" "$TMP/e0.err" && grep -q 'rules file rejected' "$TMP/e0.err"; then
    ok "(e0) a TO template that compiles for no capture rejects the rules file at parse, naming the template"
else
    no "(e0) exit $rc — an unbalanced TO template was not rejected at parse: $( head -c 240 "$TMP/e0.err" )"
fi
rc="$( capRun 20 "$TMP/e.out" "$TMP/e.err" "$FIX" --no-cache --arch="$TMP/arch_subst.txt" )"
if [ "$rc" = 1 ]; then ok "(e) a TO pattern that becomes invalid after substitution refuses at exit 1"
else no "(e) exit $rc — a rule its own substitution broke was not refused (inert rules report exit 0 over edges they never judged)"; fi
if grep -qF "a{2,1}" "$TMP/e.err" && grep -q 'refused' "$TMP/e.err"; then ok "(e) the refusal quotes the substituted pattern a{2,1} and says it is refused"
else no "(e) stderr does not quote the substituted pattern: $( head -c 240 "$TMP/e.err" )"; fi
if grep -q '<arch ' "$TMP/e.out"; then no "(e) an <arch> answer was printed beside the refusal"; else ok "(e) no <arch> answer on stdout"; fi
# control: the same rule shape whose substitution stays valid (a{1,1}) is judged, not refused — the refusal is the
# substituted TEXT's, not the backreference's
rc="$( capRun 20 "$TMP/e2.out" "$TMP/e2.err" "$FIX" --no-cache --arch="$TMP/arch_subst_ok.txt" )"
if [ "$rc" != 1 ] && [ "$rc" != TIMEOUT ] && grep -q '<arch ' "$TMP/e2.out"; then ok "(e) control: a{1,\\1} substitutes to a valid a{1,1} and the rule is judged (exit $rc)"
else no "(e) control: exit $rc — $( head -c 200 "$TMP/e2.err" )"; fi

# ── (h) an undecided capture-typed #match? is reported BY CAUSE, naming the first site and the captured text ─────
CAPQ='((call_expression function: (identifier) @f arguments: (argument_list (string_literal) @s)) (#match? @f @s))'
HS="$TMP/cap_screen"; HC="$TMP/cap_compile"; HA="$TMP/cap_abandon"; mkdir -p "$HS" "$HC" "$HA" "$TMP/rules_cap"
printf 'int g(const char* s);\nint f(void)\n{\n    return g("(a+)+z");\n}\n' >"$HS/a.c"
printf 'int g(const char* s);\nint k(void) { return g("(b+)+z"); }\n' >"$HS/b.c"
printf 'int g(const char* s);\nint h(void) { return g("foo("); }\n' >"$HC/c.c"
printf 'int g(const char* s);\nint x(void) { return g("x"); }\n' >"$HA/x.c"
cat >"$TMP/rules_cap/cap.yml" <<'YML'
- id: rx-capture
  language: c
  severity: warn
  message: a capture-typed predicate
  query: |
    ((call_expression function: (identifier) @f arguments: (argument_list (string_literal) @s)) (#match? @f @s)) @hit
YML
causeArm(){                      # causeArm <label> <corpus> <needle cause> <needle text> <args…>
    local label="$1" corpus="$2" cause="$3" text="$4"; shift 4
    local rc; rc="$( capRun 20 "$TMP/h.out" "$TMP/h.err" "$corpus" --no-cache "$@" )"
    if [ "$rc" = 1 ]; then ok "(h) $label: refused at exit 1"; else no "(h) $label: exit $rc — $( head -c 200 "$TMP/h.err" )"; fi
    if grep -qF -- "$cause" "$TMP/h.err"; then ok "(h) $label: the refusal gives the cause ($cause)"
    else no "(h) $label: the refusal does not give the cause '$cause': $( head -c 260 "$TMP/h.err" )"; fi
    if grep -qF -- "$text" "$TMP/h.err"; then ok "(h) $label: the refusal names the captured text / site ($text)"
    else no "(h) $label: the refusal does not name '$text': $( head -c 260 "$TMP/h.err" )"; fi
    if [ "$cause" != "the regex engine abandoned" ] && grep -q 'abandoned the match' "$TMP/h.err"; then
        no "(h) $label: the refusal blames an abandoned match that never happened"
    else
        ok "(h) $label: no cause is claimed that did not happen"
    fi
    if grep -qE '<match |<lint' "$TMP/h.out"; then no "(h) $label: an answer element was printed beside the refusal"; else ok "(h) $label: no answer element on stdout"; fi
}
causeArm "screen-refused text"   "$HS" "captured text(s) the structural screen refused" "a.c:4, used the captured text '\"(a+)+z\"'" "--match=$CAPQ"
grep -qF '2 captured text(s) the structural screen refused' "$TMP/h.err" \
    && ok "(h) screen-refused text: both files' texts are counted, and the FIRST site named is the lowest file (a.c, not b.c)" \
    || no "(h) screen-refused text: count or first site wrong: $( head -c 260 "$TMP/h.err" )"
cp "$TMP/h.err" "$TMP/h1.err"
capRun 20 /dev/null "$TMP/h1b.err" "$HS" --no-cache "--match=$CAPQ" >/dev/null
if cmp -s "$TMP/h1.err" "$TMP/h1b.err"; then ok "(h) the by-cause refusal is byte-identical run to run"; else no "(h) the by-cause refusal differs run to run"; fi
causeArm "uncompilable text"     "$HC" "captured text(s) that do not compile" "c.c:2, used the captured text '\"foo(\"'" "--match=$CAPQ"
causeArm "--lint-rules, uncompilable text" "$HC" "captured text(s) that do not compile" "rx-capture" --lint-rules="$TMP/rules_cap"
if [ "$FAULTS" -eq 1 ]; then
    rc="$( RIPWIRE_FAULT_REGEX_MATCH=1 capRun 20 "$TMP/h.out" "$TMP/h.err" "$HA" --no-cache "--match=$CAPQ" )"
    if [ "$rc" = 1 ] && grep -qF "match(es) the regex engine abandoned" "$TMP/h.err" && grep -qF "x.c:2, ran the pattern '\"x\"'" "$TMP/h.err" \
       && grep -q 'abandoned the match' "$TMP/h.err" && ! grep -q 'captured text(s)' "$TMP/h.err"; then
        ok "(h) abandoned match: reported as abandoned, naming x.c:2 and the pattern, and no text cause"
    else
        no "(h) abandoned match: exit $rc — $( head -c 260 "$TMP/h.err" )"
    fi
else
    printf '  INFO  (h) fault switches compiled out (NDEBUG): the abandoned cause is proved on the plain-flavour leg\n'
fi

# ── (i) --arch decides deny first: an allow that cannot be judged matters only when a deny fires ────────────────────
# RE-SCOPED (2026-10-12, Q7, PM-authorised). This arm used to prove deny-first with an allow whose pattern the ENGINE
# abandons mid-match (`(a|a)+z` on libc++). Phase 1 closes that gap STATICALLY — `(a|a)+z` is now refused at LOAD
# (--arch rejects the whole rules file, arm (b2)) — so that vehicle can no longer load. The GUARANTEE is preserved
# with a PORTABLE match-time-undecided vehicle instead: a TO template that only fails once an edge's captures are
# substituted (`a{2,\1}` -> an invalid interval on every standard library — arm (e)). pathRuleForbids treats that
# exactly as it treats an abandoned allow (undecidedPathRule), so all three legs below prove the SAME deny-first
# property — and now on EVERY platform, not only where libc++ is linked (a strict widening of the arm's coverage).
# NOTE: printf '%s\n' — NOT printf '...'. A bare printf interprets `\1` as an octal escape (byte 0x01), which would
# mangle the backreference into a literal control byte and make the TO template `a{2,}` (unbalanced) rather than the
# intended `a{2,\1}`. Arm (e) writes its fixtures the same way for the same reason.
printf '%s\n' 'allow path zz/(.*) -> a{2,\1}' 'deny path nomatch/.* -> .*' >"$TMP/arch_allow_nodeny.txt"
rc="$( capRun 20 "$TMP/i.out" "$TMP/i.err" "$FIX" --no-cache --arch="$TMP/arch_allow_nodeny.txt" )"
if [ "$rc" = 0 ] && grep -q '<arch ' "$TMP/i.out"; then
    ok "(i) no deny matches, so the edge is permitted without consulting the undecided allow (exit 0)"
else
    no "(i) exit $rc — an allow nobody needed refused a determinable answer: $( head -c 200 "$TMP/i.err" )"
fi
printf '%s\n' 'allow path zz/(.*) -> a{2,\1}' 'allow path zz/.* -> .*' 'deny path zz/.* -> .*' >"$TMP/arch_allow_later.txt"
rc="$( capRun 20 "$TMP/i2.out" "$TMP/i2.err" "$FIX" --no-cache --arch="$TMP/arch_allow_later.txt" )"
if [ "$rc" = 0 ] && grep -q '<arch ' "$TMP/i2.out"; then ok "(i) a deny fires, the first allow is undecided, a later allow matches: permitted (exit 0)"
else no "(i) later matching allow after an undecided one: exit $rc — $( head -c 200 "$TMP/i2.err" )"; fi
printf '%s\n' 'allow path zz/(.*) -> a{2,\1}' 'deny path zz/.* -> .*' >"$TMP/arch_allow_only.txt"
rc="$( capRun 20 "$TMP/i3.out" "$TMP/i3.err" "$FIX" --no-cache --arch="$TMP/arch_allow_only.txt" )"
if [ "$rc" = 1 ] && grep -qF "path-rule 'zz/(.*) -> a{2,\1}'" "$TMP/i3.err"; then ok "(i) a deny fires and the only allow is undecided: refused, naming the ALLOW rule (exit 1)"
else no "(i) deny fires, allow undecided: exit $rc — $( head -c 200 "$TMP/i3.err" )"; fi

# ── (f) the skill scanner: linear net-exfil agrees with its regex, bounded time, and undecided fails closed ───────
SK="$TMP/skills"; mkdir -p "$SK"
python3 - "$SK" <<'PY'
import random, re, sys
sk = sys.argv[1]
oracle = re.compile(r"(\b(curl|wget|nc)\b[^\r\n]*(\$[A-Za-z_][A-Za-z0-9_]*|base64))|((\$[A-Za-z_][A-Za-z0-9_]*|base64)[^\r\n]*\b(curl|wget|nc)\b)", re.ASCII)
# #353 R1: the rule also needs a network command that NAMES A DESTINATION (src/skillscan.h netFlow). This is that scan,
# written again from its specification — segments at | ; & and line breaks, a verb in command position, a destination-
# shaped argument after it — so the whole decision stays differential, not only the regex half.
SEP = ' \t"\'`|;&()<>\r\n'
# Runner words that leave the next word in command position (`sudo curl`, `stdbuf -oL curl`, `command curl`), each with
# the options of theirs that take the NEXT word as a value. `command` is a prefix ONLY when not followed by -v/-V.
PREFIX = {"sudo": {"-u", "-g", "-C", "-D", "-h", "-p", "-r", "-t", "-U", "-T"}, "doas": {"-u", "-C"}, "run0": {"-u", "-g", "-D"},
          "exec": {"-a"}, "time": {"-f", "-o"}, "nohup": set(), "nice": {"-n"}, "timeout": {"-s", "-k"},
          "xargs": {"-I", "-n", "-P", "-L", "-s", "-d", "-E", "-a"}, "env": {"-u", "-C"}, "stdbuf": {"-o", "-e", "-i"},
          "setsid": set(), "eval": set(), "builtin": set(), "command": set(),
          "then": set(), "do": set(), "else": set(), "if": set(), "elif": set(), "while": set(), "until": set(), "!": set()}
def ident_start(ch): return ch.isascii() and (ch.isalpha() or ch == "_")
def ident_char(ch): return ch.isascii() and (ch.isalnum() or ch == "_")
SOCKET = ("tcp:", "tcp4:", "tcp6:", "udp:", "udp4:", "udp6:", "openssl:", "ssl:", "tcp-connect:", "openssl-connect:")
NETCAT = ("nc", "ncat", "netcat")
def digits(t): return all("0" <= ch <= "9" for ch in t)
def is_dest(t):
    if not t: return False
    if "://" in t or t.startswith(SOCKET): return True
    if t[0] == "$": return len(t) > 1 and (t[1] == "{" or ident_start(t[1]))
    if t[0] == "[": return True
    if not ident_char(t[0]): return False
    if t == "localhost" or t.startswith("localhost:") or "@" in t: return True
    return "." in t and not t.endswith(".")
def has_dest(line):
    # Mirror src/skillscan.h NetFlowScan: a network segment (curl/wget/nc/ncat/netcat/socat in COMMAND position, or a
    # /dev/tcp redirect) that also NAMES a destination. Destination: is_dest, a netcat HOST PORT pair, or a bare word
    # after curl/wget (a single-label host). The corpus carries no sensitive/credential tokens, so R2/credential grades
    # cannot fire here and the invariant is exercised by the fixture rows in test/skillfix/netexfil_severity.md.
    low = line.lower(); found = False
    expect = seg_net = seg_dest = rin = rout = netcat = curlwget = bare = skip_value = False
    expect = True
    active = None   # the active runner-prefix word, or None
    def end():
        nonlocal expect, seg_net, seg_dest, rin, rout, netcat, curlwget, bare, skip_value, active, found
        found = found or (seg_net and seg_dest)
        expect = True
        seg_net = seg_dest = rin = rout = netcat = curlwget = bare = skip_value = False
        active = None
    i = 0
    while i < len(line):
        c = line[i]; nx = line[i + 1] if i + 1 < len(line) else ""
        if c == "|": end(); i += 2 if nx == "|" else 1; continue
        if c in ";\r\n" or (c == "&" and nx != ">"): end(); i += 2 if (c == "&" and nx == "&") else 1; continue
        if c in "<>" and nx == "(":   # `<( )` / `>( )` process substitution: a nested command, not a redirect
            if not expect: expect = True; active = None; skip_value = False
            else: active = None; skip_value = False
            i += 2; continue
        if c in ">&": rout = True; i += 2 if nx in ("&", ">") else 1; continue
        if c == "<": rin = True; i += 1; continue
        if c in "(`" or (c in "\"'" and (i == 0 or line[i - 1] in " \t")):
            if not expect: expect = True; active = None; skip_value = False
            i += 1; continue
        if c in SEP: i += 1; continue
        j = i
        while j < len(line) and line[j] not in SEP: j += 1
        t = low[i:j]
        if "/dev/tcp/" in t or "/dev/udp/" in t: seg_net = seg_dest = True   # raw-socket redirect: sink and destination
        if rout: rout = False; bare = False; i = j; continue
        # command position: is this still the prefix, or the command itself?
        was_cmd = False
        if expect and not rin:
            if skip_value:
                skip_value = False
            elif t in PREFIX:
                active = t
            elif t.startswith("-"):
                if active == "command" and t in ("-v", "-V"):
                    expect = False   # `command -v curl` names the tool; nothing runs
                elif active is not None and t in PREFIX[active]:
                    skip_value = True
            elif "=" in t or digits(t):
                pass
            else:
                was_cmd = True
        d = digits(t)
        netcat_hop = netcat and bare and d and len(t) <= 5
        bare_host = curlwget and not was_cmd and len(t) > 0 and ident_char(t[0])
        if seg_net and not rin and (is_dest(t) or netcat_hop or bare_host): seg_dest = True
        if was_cmd:
            expect = False; active = None
            verb = t.rsplit("/", 1)[-1]
            seg_net = seg_net or verb in ("curl", "wget", "socat") + NETCAT
            netcat = netcat or verb in NETCAT
            curlwget = curlwget or verb in ("curl", "wget")
        bare = not was_cmd and not rin and not d and not t.startswith("-")
        rin = False
        i = j
    end()
    return found
tokens = ["curl", "wget", "nc", "ncx", "xnc", "curl_", "_wget", "$A", "$_b", "$1", "$", "$$x", "base64", "xbase64y", "base6",
          " ", " ", "|", "-", "\r", "a", "_", "0", "=", "'", '"', "$nc", "nc$", "base64nc", "c\rurl", "\t",
          # #353 R1: destinations and command-position shapes, so the destination half of the oracle is exercised both ways
          "curl ", "nc ", " $H", " https://h.example", " h.example", " localhost", "; ", " && ", "command -v ", "echo ", "(", "<", ">",
          # the netcat HOST PORT pair, a -l listener, ncat/socat, a socat address and a /dev/tcp redirect
          " attacker", " 4444", " -l", "ncat ", "socat ", " TCP:h:1", " /dev/tcp/h/80",
          "echo $A | ", "; nc attacker 4444", "; nc -l 4444", "| nc h 80", "; curl attacker 4444"]
rng = random.Random(20260916)
expected = []
shapeOnly = [0]
for chunk in range(20):
    lines = []
    while len(lines) < 150:
        line = "".join(rng.choice(tokens) for _ in range(rng.randint(1, 16)))
        if "\n" in line or line.strip() in ("", "```") or line.lstrip(" \t").startswith(("```", "~~~")):
            continue
        lines.append(line)
    # every generated line sits inside one bash fence; line numbers start at 3 (heading, fence)
    with open(f"{sk}/chunk{chunk}.md", "w", newline="") as fh:
        fh.write("# probe\n```bash\n" + "\n".join(lines) + "\n```\n")
    for i, line in enumerate(lines):
        if oracle.search(line):
            shapeOnly[0] += 1
            if has_dest(line):
                expected.append(f"chunk{chunk}.md:{i + 3}")
with open(f"{sk}/expected.txt", "w") as fh:
    fh.write("\n".join(sorted(expected)) + "\n")
with open(f"{sk}/shape.txt", "w") as fh:
    fh.write(str(shapeOnly[0]) + "\n")
PY
: >"$SK/got.txt"
for f in "$SK"/chunk*.md; do
    "$BIN" --scan-skill="$f" 2>/dev/null | grep -o '<f p="[^"]*" rule="EXFILTRATE:net-exfil"' | sed -E 's#<f p="[^"]*/([^/"]*)" rule=.*#\1#' >>"$SK/got.txt"
done
sort -o "$SK/got.txt" "$SK/got.txt"
expectedCount="$( grep -c . "$SK/expected.txt" )"; gotCount="$( grep -c . "$SK/got.txt" )"
shapeCount="$( cat "$SK/shape.txt" )"
if [ "$expectedCount" -ge 100 ] && [ "$shapeCount" -gt "$expectedCount" ] && cmp -s "$SK/expected.txt" "$SK/got.txt"; then
    ok "(f1) net-exfil agrees with the regex-plus-destination oracle on all 3,000 generated fenced lines ($expectedCount positives; $shapeCount regex hits, $(( shapeCount - expectedCount )) without a destination)"
else
    no "(f1) net-exfil disagrees with the regex oracle: expected $expectedCount positives, got $gotCount — $( diff "$SK/expected.txt" "$SK/got.txt" | head -4 | tr '\n' ' ' )"
fi
python3 -c "import sys; sys.stdout.write('# probe\n\x60\x60\x60bash\n' + 'curl ' * 40000 + '\n\x60\x60\x60\n')" >"$SK/dos.md"
python3 -c "import sys; sys.stdout.write('# probe\n\x60\x60\x60bash\n' + 'curl ' * 40000 + '\$SECRET\n\x60\x60\x60\n')" >"$SK/dos_hit.md"
rc="$( capRun 20 "$TMP/f2.out" "$TMP/f2.err" --scan-skill="$SK/dos.md" )"
if [ "$rc" = 0 ]; then ok "(f2) a 200,000-byte fenced curl-run line scans clean within 20 s (the quadratic regex ran past 60 s)"
else no "(f2) the 200,000-byte curl-run line: exit $rc (TIMEOUT means the scan is still quadratic)"; fi
rc="$( capRun 20 "$TMP/f2h.out" "$TMP/f2h.err" --scan-skill="$SK/dos_hit.md" )"
if [ "$rc" = 2 ] && grep -q 'rule="EXFILTRATE:net-exfil"' "$TMP/f2h.out"; then ok "(f2) the same line ending in \$SECRET is still caught as net-exfil (exit 2), bounded"
else no "(f2) the long net-exfil line: exit $rc, finding $( grep -o 'rule="[^"]*"' "$TMP/f2h.out" | head -1 )"; fi
printf '# probe\n\nplain prose line\n' >"$SK/clean.md"
if [ "$FAULTS" -eq 1 ]; then
    rc="$( RIPWIRE_FAULT_REGEX_MATCH=1 capRun 20 "$TMP/f3.out" "$TMP/f3.err" --scan-skill="$SK/clean.md" )"
    if [ "$rc" = 2 ] && grep -q 'rule="SCAN-INCOMPLETE:regex-abandoned" sev="critical"' "$TMP/f3.out"; then
        ok "(f3) an abandoned match fails closed: CRITICAL SCAN-INCOMPLETE:regex-abandoned, exit 2"
    else
        no "(f3) an abandoned match in the skill scanner: exit $rc, $( head -c 200 "$TMP/f3.out" )"
    fi
    rc="$( capRun 20 "$TMP/f3c.out" "$TMP/f3c.err" --scan-skill="$SK/clean.md" )"
    if [ "$rc" = 0 ] && grep -q 'verdict="clean"' "$TMP/f3c.out"; then ok "(f3) control: the same file without the fault scans clean at exit 0"
    else no "(f3) control: exit $rc"; fi
else
    printf '  INFO  (f3) fault switches compiled out (NDEBUG): the fail-closed path is proved on the plain-flavour leg\n'
fi

# ── (g) the stack bound: a pattern too long or too deeply nested is refused by name, the limit itself still compiles ──
LIT2048="$( python3 -c "print('a' * 2048)" )"; LIT2049="$( python3 -c "print('a' * 2049)" )"
NEST64="$( python3 -c "print('(' * 64 + 'q' + ')' * 64)" )"; NEST65="$( python3 -c "print('(' * 65 + 'q' + ')' * 65)" )"
BIG="$( python3 -c "print('a' * 20000)" )"
rc="$( capRun 20 "$TMP/g1.out" "$TMP/g1.err" "$FIX" --no-cache --regex="$BIG" )"
if [ "$rc" = 1 ] && grep -q 'bytes and the limit is 2048' "$TMP/g1.err"; then ok "(g) a 20,000-byte --regex is refused by name at exit 1 (it died with SIGBUS in a 512 KiB grep worker)"
else no "(g) a 20,000-byte --regex: exit $rc — $( head -c 160 "$TMP/g1.err" )"; fi
rc="$( capRun 20 "$TMP/g2.out" "$TMP/g2.err" "$FIX" --no-cache --graph-query="file(all,\"$LIT2049\")" )"
if [ "$rc" = 1 ] && grep -q 'is 2049 bytes and the limit is 2048' "$TMP/g2.err"; then ok "(g) 2,049 bytes: refused, naming the size and the limit"
else no "(g) 2,049 bytes: exit $rc — $( head -c 160 "$TMP/g2.err" )"; fi
rc="$( capRun 20 "$TMP/g3.out" "$TMP/g3.err" "$FIX" --no-cache --graph-query="file(all,\"$LIT2048\")" )"
if [ "$rc" = 0 ] && grep -q '<query ' "$TMP/g3.out"; then ok "(g) exactly 2,048 bytes still compiles and answers"
else no "(g) 2,048 bytes: exit $rc — $( head -c 160 "$TMP/g3.err" )"; fi
rc="$( capRun 20 "$TMP/g4.out" "$TMP/g4.err" "$FIX" --no-cache --graph-query="file(all,\"$NEST65\")" )"
if [ "$rc" = 1 ] && grep -q 'groups nest 65 deep and the limit is 64' "$TMP/g4.err"; then ok "(g) groups nested 65 deep: refused, naming the depth and the limit"
else no "(g) 65 nested groups: exit $rc — $( head -c 160 "$TMP/g4.err" )"; fi
rc="$( capRun 20 "$TMP/g5.out" "$TMP/g5.err" "$FIX" --no-cache --graph-query="file(all,\"$NEST64\")" )"
if [ "$rc" = 0 ] && grep -q '<query ' "$TMP/g5.out"; then ok "(g) groups nested exactly 64 deep still compile and answer"
else no "(g) 64 nested groups: exit $rc — $( head -c 160 "$TMP/g5.err" )"; fi

# ── (j) the literal paths ARE the engine: a differential harness, then a mutation it must see ──────────────────────
# The corpus is every --regex pattern the docs, skills and gates spell, and every #match? predicate a lint pack or query
# file carries, on top of the harness's own adversarial and generated patterns.
CXX="${CXX:-c++}"
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
{
    grep -rhoE -- "--regex='[^']+'" "$ROOT/docs" "$ROOT/skills" "$ROOT/test" "$ROOT/README.md" 2>/dev/null | sed -e "s/^--regex='//" -e "s/'\$//"
    grep -rhoE '#(not-)?match\? @[A-Za-z_.]+ "([^"\\]|\\.)+"' "$ROOT/src" "$ROOT/queries" "$ROOT/test" 2>/dev/null \
        | sed -e 's/^#[a-z-]*? @[A-Za-z_.]* "//' -e 's/"$//' -e 's/\\\\/\\/g'
} | LC_ALL=C sort -u >"$TMP/rx_corpus.txt"
corpusLines="$( wc -l <"$TMP/rx_corpus.txt" | tr -d ' ' )"
if "$CXX" "$CXXSTD" -O2 -Wall -Wextra -I"$ROOT/src" "$ROOT/test/regexlines_harness.cpp" -o "$TMP/rxlines" 2>"$TMP/rxlines.cc"; then
    "$TMP/rxlines" "$TMP/rx_corpus.txt" >"$TMP/rxlines.out" 2>&1; rxRc=$?
    summary="$( grep -m1 '^regexlines:' "$TMP/rxlines.out" )"
    if [ "$rxRc" -eq 0 ] && printf '%s' "$summary" | grep -q ' mismatches=0 coverage=met'; then
        ok "(j) literal plan, required-literal prefilter and skip policy agree with std::regex ($CXX, corpus $corpusLines): $summary"
    else
        no "(j) the literal paths disagree with std::regex (rc $rxRc): $summary $( grep -m2 '^MISMATCH' "$TMP/rxlines.out" | head -c 400 )"
    fi
    # can the harness go red? A plan that resumes one byte after a match instead of after its end reports overlaps.
    mkdir -p "$TMP/rxmut"
    python3 - "$ROOT/src/regexguard.h" "$TMP/rxmut/regexguard.h" <<'PY'
import sys
s = open(sys.argv[1]).read()
old = "k = at + chosen->size();"
assert s.count(old) == 1, "mutation site moved"
open(sys.argv[2], "w").write(s.replace(old, "k = at + 1;"))
PY
    if "$CXX" "$CXXSTD" -O2 -w -I"$TMP/rxmut" -I"$ROOT/src" "$ROOT/test/regexlines_harness.cpp" -o "$TMP/rxlinesmut" 2>"$TMP/rxmut.cc"; then
        "$TMP/rxlinesmut" "$TMP/rx_corpus.txt" >"$TMP/rxmut.out" 2>&1; mutRc=$?
        if [ "$mutRc" -ne 0 ] && grep -q '^MISMATCH' "$TMP/rxmut.out"; then ok "(j) mutation control: an overlapping literal alternation is caught ($( grep -m1 -o 'mismatches=[0-9]*' "$TMP/rxmut.out" ))"
        else no "(j) mutation control: the harness passed a literal plan that reports overlapping matches (rc $mutRc)"; fi
    else
        no "(j) mutation control did not compile: $( head -c 300 "$TMP/rxmut.cc" )"
    fi
else
    no "(j) test/regexlines_harness.cpp did not compile with $CXX: $( head -c 400 "$TMP/rxlines.cc" )"
fi

# ── (k) a long line answers or says it was skipped — never a signal death, never a silent zero ─────────────────────
attrOf(){ grep -o "<grep [^>]*>" "$2" | head -1 | grep -o " $1=\"[^\"]*\"" | head -1 | sed -e 's/.*="//' -e 's/"$//'; }
# THE LONG-LINE DISCLOSURE IS READ IN EACH DIALECT'S OWN WORDING. Since train 9 the DEFAULT posture is the
# compact dialect, which reads the two attributes as `regex_lines_skipped=N: ` and `regex_line_max=: `, while
# `--legend=full` carries the prose `LONG LINES:` block defining the same two. This arm used to pin the FULL
# spelling against a DEFAULT answer, so it went red on every libstdc++ CI leg while every macOS run stayed
# green: libc++ does not recurse per character, its 300 KB line is never skipped, and the branch below is
# never entered there. The disclosure was complete throughout — only the gate was reading for the other
# dialect's words. (m) asserts the same two readings through the fault bound, so a libc++ host reaches them.
defReadsLongLines(){ grep -q 'regex_lines_skipped=N: ' "$1" && grep -q 'regex_line_max=: ' "$1"; }
yn(){ if "$@"; then echo 1; else echo 0; fi; }
FIXL="$TMP/longfix"; FIXN="$TMP/nobfix"; FIXP="$TMP/litfix"
mkdir -p "$FIXL" "$FIXN" "$FIXP"
python3 - "$FIXL" "$FIXN" "$FIXP" <<'PY'
import sys
l, n, p = sys.argv[1:4]
open(f"{l}/long.md", "w").write("a" * 300000 + "b\nok ab\n")          # 300 KB: past libstdc++'s 8 MiB crash (26-45 KB) and its 256 MiB bound
open(f"{l}/small.md", "w").write("# small\nab\n")
open(f"{n}/nob.txt", "w").write("a" * 2000000 + "\n")                  # no 'b' anywhere: the required literal rules the line out
open(f"{n}/small.md", "w").write("# small\nab\n")
open(f"{p}/lit.txt", "w").write("x" * 3000000 + "needle\n")            # a literal alternation over a 3 MB line
open(f"{p}/small.md", "w").write("# small\npin\n")
PY
rc="$( capRun 60 "$TMP/k1.out" "$TMP/k1.err" "$FIXL" --no-cache --regex='a*b' )"
skipped="$( attrOf regex_lines_skipped "$TMP/k1.out" )"
if [ "$rc" != 0 ]; then
    no "(k) --regex='a*b' over a 300 KB matching line: exit $rc (a signal death is 128+N) — $( head -c 160 "$TMP/k1.err" )"
elif [ -z "$skipped" ]; then
    no "(k) --regex='a*b' answered without regex_lines_skipped= on its root"
elif [ "$skipped" = 0 ]; then
    if grep -q '<f p="long.md"><hit l="1"' "$TMP/k1.out"; then ok "(k) a 300 KB matching line is matched in full (this engine does not recurse per byte): regex_lines_skipped=\"0\""
    else no "(k) regex_lines_skipped=\"0\" but the 300 KB line's hit is missing — a silent zero"; fi
else
    lineMax="$( attrOf regex_line_max "$TMP/k1.out" )"
    if [ "$skipped" = 1 ] && [ -n "$lineMax" ] && grep -q 'counts_floor="1"' "$TMP/k1.out" && grep -q '<f p="long.md"><hit l="2"' "$TMP/k1.out" \
       && defReadsLongLines "$TMP/k1.out"; then
        ok "(k) the 300 KB line is skipped and disclosed (regex_lines_skipped=\"1\" regex_line_max=\"$lineMax\" counts_floor=\"1\", the DEFAULT legend reads both), line 2 still answered"
    else
        # Name the conjunct that failed: the CI red this replaces printed only the three that had passed.
        no "(k) a skipped line is not fully disclosed: skipped=$skipped line_max=[$lineMax] floor=$( grep -c 'counts_floor="1"' "$TMP/k1.out" ) line2=$( yn grep -q '<f p="long.md"><hit l="2"' "$TMP/k1.out" ) default_legend_reads_both=$( yn defReadsLongLines "$TMP/k1.out" )"
    fi
    capRun 60 "$TMP/k1f.out" /dev/null "$FIXL" --no-cache --regex='a*b' --legend=full >/dev/null
    if grep -q 'LONG LINES:' "$TMP/k1f.out" && grep -q 'regex_line_max=' "$TMP/k1f.out"; then
        ok "(k) --legend=full defines the same two in its own wording (the LONG LINES block)"
    else
        no "(k) --legend=full dropped the LONG LINES block on an answer that skipped a line"
    fi
fi
rc="$( capRun 30 "$TMP/k2.out" "$TMP/k2.err" "$FIXN" --no-cache --regex='a*b' )"
if [ "$rc" = 0 ] && [ "$( attrOf regex_lines_skipped "$TMP/k2.out" )" = 0 ] && ! grep -q 'p="nob.txt"' "$TMP/k2.out"; then
    ok "(k) a 2 MB line holding no 'b' is ruled out without the engine: exit 0 inside 30 s, regex_lines_skipped=\"0\", no hit"
else
    no "(k) --regex='a*b' over a 2 MB line with no 'b': exit $rc, regex_lines_skipped=[$( attrOf regex_lines_skipped "$TMP/k2.out" )]"
fi
rc="$( capRun 30 "$TMP/k3.out" "$TMP/k3.err" "$FIXP" --no-cache --regex='needle|pin' )"
if [ "$rc" = 0 ] && [ "$( attrOf regex_lines_skipped "$TMP/k3.out" )" = 0 ] && grep -q '<hit l="1"' "$TMP/k3.out" && grep -q '<hit l="2"' "$TMP/k3.out"; then
    ok "(k) a literal alternation over a 3 MB line never reaches the engine: both hits, regex_lines_skipped=\"0\""
else
    no "(k) --regex='needle|pin' over a 3 MB line: exit $rc, regex_lines_skipped=[$( attrOf regex_lines_skipped "$TMP/k3.out" )]"
fi
"$BIN" "$FIXP" --no-cache --grep=needle >"$TMP/k4.out" 2>/dev/null
if grep -q '<grep ' "$TMP/k4.out" && ! grep -q 'regex_lines_skipped\|regex_line_max\|LONG LINES:' "$TMP/k4.out"; then ok "(k) a literal --grep answer carries no long-line attribute or clause, in either dialect"
else no "(k) a literal --grep answer changed: $( grep -o '<grep [^>]*>' "$TMP/k4.out" | head -c 300 )"; fi

# ── (l) the bound holds on the engine it protects: exactly at regex_line_max the engine runs, one byte past it skips ───
# Only a recursing engine has a finite bound; (k) above read it from the binary. Each shape builds its own bound first.
boundShape(){                    # boundShape <label> <pattern> <unit> <suffix>
    local label="$1" pat="$2" unit="$3" suffix="$4" dir="$TMP/bound_$5"
    mkdir -p "$dir"
    python3 -c "import sys; open(sys.argv[1],'w').write(sys.argv[2]*(1000000//len(sys.argv[2])) + sys.argv[3] + '\n')" "$dir/huge.txt" "$unit" "$suffix"
    capRun 60 "$TMP/l0.out" /dev/null "$dir" --no-cache --regex="$pat" >/dev/null
    local max; max="$( attrOf regex_line_max "$TMP/l0.out" )"
    if [ -z "$max" ]; then
        no "(l) $label: a 1 MB line was not skipped on an engine whose 300 KB line was — no regex_line_max= to test"
        return
    fi
    rm -f "$dir/huge.txt"
    local body=$(( max - ${#suffix} )) at past
    python3 -c "import sys; u=sys.argv[2]; n=int(sys.argv[3]); s=(u*(n//len(u)+1))[:n]; open(sys.argv[1],'w').write(s + sys.argv[4] + '\n')" "$dir/at.txt" "$unit" "$body" "$suffix"
    at="$( capRun 60 "$TMP/l1.out" "$TMP/l1.err" "$dir" --no-cache --regex="$pat" )"
    rm -f "$dir/at.txt"
    python3 -c "import sys; u=sys.argv[2]; n=int(sys.argv[3]); s=(u*(n//len(u)+1))[:n]; open(sys.argv[1],'w').write(s + sys.argv[4] + '\n')" "$dir/past.txt" "$unit" "$(( body + 1 ))" "$suffix"
    past="$( capRun 60 "$TMP/l2.out" /dev/null "$dir" --no-cache --regex="$pat" )"
    if [ "$at" = 0 ] && [ "$( attrOf regex_lines_skipped "$TMP/l1.out" )" = 0 ] && grep -q '<hit l="1"' "$TMP/l1.out"; then
        ok "(l) $label: a line of exactly regex_line_max=$max bytes is handed to the engine and matched, exit 0"
    else
        no "(l) $label: at the bound ($max bytes) exit $at, regex_lines_skipped=[$( attrOf regex_lines_skipped "$TMP/l1.out" )] — $( head -c 160 "$TMP/l1.err" )"
    fi
    if [ "$past" = 0 ] && [ "$( attrOf regex_lines_skipped "$TMP/l2.out" )" = 1 ]; then ok "(l) $label: one byte past the bound the line is skipped and counted"
    else no "(l) $label: one byte past the bound: exit $past, regex_lines_skipped=[$( attrOf regex_lines_skipped "$TMP/l2.out" )]"; fi
}
if [ -n "$( attrOf regex_line_max "$TMP/k1.out" )" ]; then
    boundShape "a*b"                "a*b"             a   b 1
    boundShape "(a|b)*c"            "(a|b)*c"         ab  c 2
    boundShape "(?:x|y|a)*(?=b)b"   "(?:x|y|a)*(?=b)b" a  b 3
else
    printf '  INFO  (l) (k) disclosed no regex_line_max= on this binary (an engine with no per-byte recursion has no finite line bound), so there is no bound to test\n'
fi

# ── (m) the skip path and its disclosure on EVERY engine: RIPWIRE_FAULT_REGEX_LINE_BOUND=1 caps the bound at 64 bytes ──
if [ "$FAULTS" -eq 1 ]; then
    FIXF="$TMP/faultfix"; mkdir -p "$FIXF"
    { head -c 100 /dev/zero | tr '\0' 'x'; printf ' aab\naab\n'; } >"$FIXF/f.md"
    RIPWIRE_FAULT_REGEX_LINE_BOUND=1 "$BIN" "$FIXF" --no-cache --regex='a+b' >"$TMP/m1.out" 2>/dev/null
    if [ "$( attrOf regex_lines_skipped "$TMP/m1.out" )" = 1 ] && [ "$( attrOf regex_line_max "$TMP/m1.out" )" = 64 ] \
       && grep -q 'counts_floor="1"' "$TMP/m1.out" && grep -q '<hit l="2"' "$TMP/m1.out" && ! grep -q '<hit l="1"' "$TMP/m1.out"; then
        ok "(m) a 104-byte line past the 64-byte fault bound is skipped, counted and floored; the short line still answers"
    else
        no "(m) fault bound: $( grep -o '<grep [^>]*>' "$TMP/m1.out" | head -c 300 )"
    fi
    # m1 is the DEFAULT posture, and the fault bound reaches the skip path on EVERY engine — which is what
    # makes this the platform-independent twin of (k)'s disclosure assertion. (k) can only enter that branch
    # where the engine recurses per character (libstdc++), so on a libc++ host this is the only place the
    # default dialect's long-line readings are checked at all. Both dialects are asserted, each in its own
    # wording, on the same fixture.
    if defReadsLongLines "$TMP/m1.out"; then ok "(m) the DEFAULT legend reads both long-line attributes on a skipped line (every engine, via the fault bound)"
    else no "(m) the DEFAULT legend does not read regex_lines_skipped=N: / regex_line_max=: on a skipped line: $( head -c 300 "$TMP/m1.out" )"; fi
    RIPWIRE_FAULT_REGEX_LINE_BOUND=1 "$BIN" "$FIXF" --no-cache --regex='a+b' --legend=full >"$TMP/m1f.out" 2>/dev/null
    if grep -q 'LONG LINES:' "$TMP/m1f.out"; then ok "(m) --legend=full carries the LONG LINES block on the same answer"
    else no "(m) --legend=full dropped the LONG LINES block on a skipped line: $( head -c 300 "$TMP/m1f.out" )"; fi
    RIPWIRE_FAULT_REGEX_LINE_BOUND=1 "$BIN" "$FIXF" --no-cache --regex='a+b' --legend=compact >"$TMP/m2.out" 2>/dev/null
    if defReadsLongLines "$TMP/m2.out"; then ok "(m) the compact legend reads both long-line attributes"
    else no "(m) the compact legend does not read regex_lines_skipped=/regex_line_max=: $( head -c 300 "$TMP/m2.out" )"; fi
    RIPWIRE_FAULT_REGEX_LINE_BOUND=1 "$BIN" "$FIXF" --no-cache --regex='aab' >"$TMP/m3.out" 2>/dev/null
    if [ "$( attrOf regex_lines_skipped "$TMP/m3.out" )" = 0 ] && grep -q '<hit l="1"' "$TMP/m3.out" && grep -q 'hits="2"' "$TMP/m3.out"; then
        ok "(m) a literal pattern is never skipped, even past the fault bound: both lines answer"
    else no "(m) --regex='aab' under the fault bound: $( grep -o '<grep [^>]*>' "$TMP/m3.out" | head -c 300 )"; fi
    RIPWIRE_FAULT_REGEX_LINE_BOUND=1 "$BIN" "$FIXF" --no-cache --regex='a+q' >"$TMP/m4.out" 2>/dev/null
    if [ "$( attrOf regex_lines_skipped "$TMP/m4.out" )" = 0 ]; then ok "(m) a long line holding none of the pattern's required literal is ruled out, not skipped"
    else no "(m) --regex='a+q' skipped a line that cannot match: $( grep -o '<grep [^>]*>' "$TMP/m4.out" | head -c 300 )"; fi
    RIPWIRE_FAULT_REGEX_LINE_BOUND=10 "$BIN" "$FIXF" --no-cache --regex='a+b' >"$TMP/m5.out" 2>/dev/null
    if [ "$( attrOf regex_lines_skipped "$TMP/m5.out" )" = 0 ] && grep -q 'hits="2"' "$TMP/m5.out"; then ok "(m) control: RIPWIRE_FAULT_REGEX_LINE_BOUND=10 is not ON, and both lines answer"
    else no "(m) control: RIPWIRE_FAULT_REGEX_LINE_BOUND=10 changed the answer: $( grep -o '<grep [^>]*>' "$TMP/m5.out" | head -c 300 )"; fi
else
    printf '  INFO  (m) this binary compiles fault switches out (NDEBUG); the skip path is observable through (k)/(l) on a recursing engine\n'
fi

# ── (n) one stack for the whole scan: a degraded start holds every thread to the same size, and says so ──────────────
if [ "$FAULTS" -eq 1 ]; then
    FIXS="$TMP/stackfix"; mkdir -p "$FIXS"
    for i in $( seq -w 1 48 ); do printf '# f%s\n%s aab\n' "$i" "$( head -c 46 /dev/zero | tr '\0' x )" >"$FIXS/f$i.md"; done
    : >"$TMP/n.sums"
    for run in 1 2 3 4 5; do
        RIPWIRE_FAULT_SCAN_STACK_MIXED=1 RIPWIRE_FAULT_REGEX_LINE_BOUND=1 "$BIN" "$FIXS" --no-cache --regex='a+b' >"$TMP/n$run.out" 2>/dev/null
        cksum <"$TMP/n$run.out" >>"$TMP/n.sums"
    done
    distinctRuns="$( sort -u "$TMP/n.sums" | wc -l | tr -d ' ' )"
    cpuCount="$( getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2 )"
    if [ "$cpuCount" -lt 2 ]; then
        printf '  INFO  (n) one CPU: the scan runs one thread, so no second stack size can be mixed in\n'
    elif [ "$distinctRuns" = 1 ] && [ "$( attrOf regex_lines_skipped "$TMP/n1.out" )" = 48 ] && [ "$( attrOf regex_line_max "$TMP/n1.out" )" = 32 ] \
         && [ "$( attrOf regex_stack_bytes "$TMP/n1.out" )" = 134217728 ]; then
        ok "(n) mixed stacks: every thread held to the smallest (regex_stack_bytes=\"134217728\"), all 48 lines skipped at regex_line_max=\"32\", 5 runs byte-identical"
    else
        no "(n) mixed stacks: $distinctRuns distinct outputs over 5 runs; root $( grep -o '<grep [^>]*>' "$TMP/n1.out" | head -c 300 )"
    fi
    RIPWIRE_FAULT_SCAN_STACK_MIXED=1 "$BIN" "$FIXS" --no-cache --regex='a+b' >"$TMP/n6.out" 2>/dev/null
    if [ "$cpuCount" -ge 2 ] && [ "$( attrOf regex_stack_bytes "$TMP/n6.out" )" = 134217728 ] && [ "$( attrOf regex_lines_skipped "$TMP/n6.out" )" = 0 ] \
       && grep -q 'hits="48"' "$TMP/n6.out"; then
        ok "(n) the smaller stack is disclosed even when no line was skipped (regex_stack_bytes= beside regex_lines_skipped=\"0\")"
    elif [ "$cpuCount" -ge 2 ]; then
        no "(n) a degraded stack with 0 skips is not disclosed: $( grep -o '<grep [^>]*>' "$TMP/n6.out" | head -c 300 )"
    fi
    "$BIN" "$FIXS" --no-cache --regex='a+b' >"$TMP/n7.out" 2>/dev/null
    if grep -q '<grep ' "$TMP/n7.out" && [ -z "$( attrOf regex_stack_bytes "$TMP/n7.out" )" ]; then ok "(n) control: a full-size scan's root carries no regex_stack_bytes="
    else no "(n) control: regex_stack_bytes= without the fault switch: $( grep -o '<grep [^>]*>' "$TMP/n7.out" | head -c 300 )"; fi
else
    printf '  INFO  (n) this binary compiles fault switches out (NDEBUG); the settled-stack arm needs RIPWIRE_FAULT_SCAN_STACK_MIXED\n'
fi

# ── (o) redaction has no regex engine to overflow: the structural shapes ARE the table's regexes ─────────────────────
if "$CXX" "$CXXSTD" -O2 -Wall -Wextra -I"$ROOT/src" "$ROOT/test/redactshape_harness.cpp" -o "$TMP/rxshape" 2>"$TMP/rxshape.cc"; then
    "$TMP/rxshape" >"$TMP/rxshape.out" 2>&1; shapeRc=$?
    shapeSummary="$( grep -m1 '^redactshape: texts=' "$TMP/rxshape.out" )"
    if [ "$shapeRc" -eq 0 ] && printf '%s' "$shapeSummary" | grep -q ' mismatches=0 coverage=met'; then
        ok "(o) every redaction shape gives its table regex's match length ($CXX): $shapeSummary"
    else
        no "(o) a redaction shape disagrees with its regex (rc $shapeRc): $shapeSummary $( grep -m2 '^MISMATCH' "$TMP/rxshape.out" | head -c 400 )"
    fi
    mkdir -p "$TMP/rxshapemut"
    python3 - "$ROOT/src/redact.h" "$TMP/rxshapemut/redact.h" <<'PY'
import sys
s = open(sys.argv[1]).read()
old = 'case 7: return shapePrefixRun( in, pos, "sk-", ShapeClass::KeyBody, 20,'
assert s.count(old) == 1, "mutation site moved"
open(sys.argv[2], "w").write(s.replace(old, 'case 7: return shapePrefixRun( in, pos, "sk-", ShapeClass::KeyBody, 19,'))
PY
    if "$CXX" "$CXXSTD" -O2 -w -I"$TMP/rxshapemut" -I"$ROOT/src" "$ROOT/test/redactshape_harness.cpp" -o "$TMP/rxshapemutbin" 2>"$TMP/rxshapemut.cc"; then
        "$TMP/rxshapemutbin" >"$TMP/rxshapemut.out" 2>&1; mutRc=$?
        if [ "$mutRc" -ne 0 ] && grep -q '^MISMATCH' "$TMP/rxshapemut.out"; then ok "(o) mutation control: an sk- key one byte short of its threshold is caught ($( grep -m1 -o 'mismatches=[0-9]*' "$TMP/rxshapemut.out" ))"
        else no "(o) mutation control: the harness passed a shape whose threshold drifted from its regex (rc $mutRc)"; fi
    else
        no "(o) mutation control did not compile: $( head -c 300 "$TMP/rxshapemut.cc" )"
    fi
else
    no "(o) test/redactshape_harness.cpp did not compile with $CXX: $( head -c 400 "$TMP/rxshape.cc" )"
fi
FIXR="$TMP/redactfix"; mkdir -p "$FIXR"
python3 -c "import sys; open(sys.argv[1],'w').write('def leaky_config():\n    return \"sk-' + 'A' * 200000 + '\"\n')" "$FIXR/leak.py"
rc="$( capRun 60 "$TMP/o1.out" "$TMP/o1.err" "$FIXR" --no-cache --expand=leaky_config )"
if [ "$rc" = 0 ] && grep -q 'openai/anthropic-key=1' "$TMP/o1.err" && ! grep -q 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' "$TMP/o1.out"; then
    ok "(o) --expand over a file holding sk- and a 200 KB token run exits 0, the key is redacted (stderr tally) and no run of it is printed"
else
    no "(o) --expand over a 200 KB sk- token: exit $rc, redacted=$( grep -c 'REDACTED:openai-key' "$TMP/o1.out" ) — $( head -c 160 "$TMP/o1.err" )"
fi

# ── (d) file() matches the ROOT-RELATIVE path, so the checkout's directory name cannot select anything ─────────
mkTree(){
    mkdir -p "$1/src" "$1/lib"
    printf 'int one() { return 1; }\nint two() { return one(); }\n' >"$1/src/one.cpp"
    printf 'int three() { return 3; }\n' >"$1/lib/three.cpp"
}
mkTree "$TMP/clone_alpha/repo_alpha"
mkTree "$TMP/clone_beta/repo_beta"
countOf(){                       # countOf <cwd> <root spelling> <expr>
    ( cd "$1" && "$BIN" "$2" --no-cache --graph-query="$3" 2>/dev/null ) | grep -oE '<query [^>]*count="[0-9]+"' | grep -oE 'count="[0-9]+"' | grep -oE '[0-9]+'
}
for expr in 'file(all,"alpha")' 'file(all,"^src/")' 'file(all,"three")'; do
    ca="$( countOf "$TMP" "$TMP/clone_alpha/repo_alpha" "$expr" )"
    cb="$( countOf "$TMP" "$TMP/clone_beta/repo_beta" "$expr" )"
    cr="$( countOf "$TMP/clone_alpha" "repo_alpha" "$expr" )"
    cd_="$( countOf "$TMP/clone_alpha" "./repo_alpha/" "$expr" )"
    if [ -n "$ca" ] && [ "$ca" = "$cb" ] && [ "$ca" = "$cr" ] && [ "$ca" = "$cd_" ]; then
        ok "(d) $expr: count=$ca in both clones and under absolute, relative and ./-with-slash root spellings"
    else
        no "(d) $expr: counts differ by checkout — alpha abs '$ca', beta abs '$cb', alpha rel '$cr', alpha ./rel/ '$cd_'"
    fi
done
[ "$( countOf "$TMP" "$TMP/clone_alpha/repo_alpha" 'file(all,"alpha")' )" = "0" ] \
    && ok "(d) file(all,\"alpha\") selects nothing: no root-relative path contains the clone's directory name" \
    || no "(d) file(all,\"alpha\") selected symbols in repo_alpha — the pattern matched the checkout directory"
[ "$( countOf "$TMP" "$TMP/clone_alpha/repo_alpha" 'file(all,"^src/")' )" = "2" ] \
    && ok "(d) an anchored ^src/ selects the two src/ symbols under an ABSOLUTE root" \
    || no "(d) ^src/ did not select exactly the two src/ symbols under an absolute root"
( cd "$TMP" && "$BIN" "$TMP/clone_alpha/repo_alpha" --no-cache --graph-query='file(all,"one")' 2>/dev/null ) >"$TMP/rows.xml"
rowsTotal="$( grep -o '<s [^>]*p="[^"]*"' "$TMP/rows.xml" | wc -l | tr -d ' ' )"
rowsOff="$( grep -o '<s [^>]*p="[^"]*"' "$TMP/rows.xml" | grep -vc 'p="src/one\.cpp:' )"
if [ "$rowsTotal" -gt 0 ] && [ "$rowsOff" = "0" ]; then
    ok "(d) every row file(all,\"one\") selects prints p=\"src/one.cpp:…\" — the path matched is the path shown ($rowsTotal rows)"
else
    no "(d) file(all,\"one\") rows: $rowsTotal total, $rowsOff not under src/one.cpp"
fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi

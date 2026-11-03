#!/usr/bin/env bash
# regexbombcheck.sh — A4-F10 gate: a catastrophic-backtracking --regex pattern must produce the SAME,
# BOUNDED, named refusal on every platform — never a crash, and never an unbounded hang.
#
# WHAT THIS GATE USED TO ASSERT, AND WHY IT CHANGED (M2, 2026-08-01). The original contract was "degrade,
# don't die": `(a+)+b` over a long run of 'a' made std::sregex_iterator throw regex_error MID-MATCH,
# src/search.h caught it, skipped the file and kept going, so the run still exited 0 with well-formed XML
# and the rest of the candidate set still matched. That contract was true — but only on Apple libc++,
# whose backtracker gives up fast with regex_error(error_complexity). The header of this file said so in
# as many words, and treated it as the toolchain.
#
# The first real Linux run (Ubuntu 24.04, clang 18 + libstdc++) proved the assumption load-bearing:
#
#     $ ripwire test/regexbombfix --regex='(a+)+b' --no-prefilter --no-cache
#     … CPU-bound, still running at 560 s, killed by the harness
#
# libstdc++ has NO complexity budget. It never throws, so the catch that the whole "degrade" contract
# rested on is never reached: the process backtracks exponentially, unbounded. A user's pathological
# --regex does not degrade on Linux — it hangs the tool, and this gate reds by timeout.
#
# THE NEW CONTRACT — one verdict, both platforms, decided before either engine runs. Exactly the shape of
# the L5 escape fix in src/search.h: the pattern is screened STRUCTURALLY at the single chokepoint
# (regexCompileError), ahead of the compile probe and ahead of any scanning, and a nested-unbounded
# quantifier is REFUSED by name with a workaround. Refusal is a first-class outcome here, not a
# consolation prize: it is bounded, it is identical everywhere, it names what is wrong, and — unlike a
# silently skipped file — it can never be mistaken for a measurement.
#
# test/regexbombfix/ has:
#   bomb.md     — a long line of 4000 'a's, no 'b' — the catastrophic-backtracking bait for `(a+)+b`.
#                 (.md, not .txt — ripwire only ingests files with a recognized extension into ing.files,
#                 and grep only scans ingested files; .md has no tree-sitter grammar but its raw bytes are
#                 still stored for grep, which is all this fixture needs.)
#   normal.cpp  — two ordinary EASY (a+)+b matches ("aab", "aaab"). Under the new contract these are what
#                 the PRECISION arms below match with safe patterns, proving the guard refuses the bomb
#                 SHAPE and not the corpus.
#
# Arms: (1) the bomb battery is refused — exit 1, bounded time, named construct, no hits= on stdout;
#       (2) the refusal is structural — same verdict against a corpus with no bomb file in it at all;
#       (3) the precision battery is NOT refused — safe patterns still scan the same fixture at exit 0;
#       (4) determinism — stdout AND stderr byte-identical run to run;
#       (5) informational — the mid-match catch survives as belt-and-braces (a refusal by name since
#           src/regexguard.h; test/regexguardcheck.sh arm (b) asserts it on every entry point).
#
# Usage: RIPWIRE_BIN=build/ripwire bash test/regexbombcheck.sh
# Exits non-zero on any failure. Does NOT touch regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/regexbombfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "no test/regexbombfix dir — fixture missing"; exit 2; }

echo "regexbombcheck: BIN=$BIN  CORPUS=test/regexbombfix"

# A refusal must be BOUNDED, and "bounded" is the half of this contract a Mac could not have caught: on
# libstdc++ the pre-fix binary is still backtracking after 560 s. Every bomb run below is wrapped in a
# hard wall-clock cap so a regression shows up as a FAILURE rather than as a hung suite. No external
# timeout(1) is assumed (it is not on a stock macOS): a background run plus a polling wait does the same
# job in portable POSIX shell.
capRun(){                        # capRun <seconds> <outfile> <errfile> <args…> -> echoes the exit status, or 'TIMEOUT'
    local capSeconds="$1" outPath="$2" errPath="$3"; shift 3
    "$BIN" "$@" >"$outPath" 2>"$errPath" &
    local runPid=$! waitedTenths=0 capTenths=$(( capSeconds * 10 ))
    while kill -0 "$runPid" 2>/dev/null; do
        [ "$waitedTenths" -ge "$capTenths" ] && { kill -9 "$runPid" 2>/dev/null; wait "$runPid" 2>/dev/null; echo TIMEOUT; return; }
        sleep 0.1; waitedTenths=$(( waitedTenths + 1 ))
    done
    wait "$runPid"; echo $?
}

# ── (1) the BOMB BATTERY: every nested-unbounded-quantifier shape must be refused, fast and by name ──────
#   (a+)+b     the classic, and the one the Linux smoke actually hung on
#   (a*)*b     the nullable-inner twin
#   (a+)*b     unbounded outer over unbounded inner, star flavour
#   (a{2,})+b  the counted-but-unbounded interval — {n,} is as unbounded as +
#   ((a+))+b   the inner repetition one group deeper than the outer quantifier
#   ((a)+)+b   the repetition is on the INNER GROUP, not on an atom inside it
#   (a+|b)+c   alternation is no defence when a branch repeats without bound
#   (a?)+b     M2-b — BOUNDED inner under an unbounded outer (see the block below)
#   (a{1,3})+b M2-b — the interval flavour of the same
#   ((a)?)+b   M2-b — the bounded repetition is ON the inner group, not on an atom inside it
#   (a{3})+b   M2-b — exact {n} is a quantifier too; deliberately in, see the block below
#
# ── M2-b (2026-08-01): TWO OF THESE ARMS USED TO BE "MUST STILL SCAN" CONTROLS ──────────────────────────
# `(a?)+b` and `(a{1,3})+b` were arms of the PRECISION battery below. The screen only refused an unbounded
# quantifier over a group that repeated WITHOUT bound inside it, on the reasoning that '?' and '{m,n}' are
# bounded and so cannot drive the blowup. That reasoning encoded libc++ behaviour. The re-smoke ran the
# gate's own control set on Ubuntu 24.04 / clang 18 / libstdc++ and BOTH controls HUNG — killed by this
# harness's wall-clock cap, exactly like the (a+)+b bomb they were supposed to contrast with. Bounded is
# not the same as unambiguous: '(a?)+' can split a run of 'a' in as many ways as '(a+)+' can, because the
# inner may also match EMPTY, and '(a{1,3})+' because the inner's width varies. On libc++ the same two
# patterns return in milliseconds (and '(a{1,3})+b' even trips the mid-match complexity degrade), which is
# why this repo shipped them as controls for as long as it only ever ran on a Mac.
#
# Cross-platform-identical behaviour is the standing law and it admits exactly one verdict per pattern, so
# the screen was WIDENED rather than the controls re-labelled per platform: an unbounded quantifier
# ('*', '+', '{n,}') applied to a group that contains ANY quantifier at all — '?', '{m,n}' and exact '{n}'
# included — is refused. Exact '{n}' is in on purpose: a fixed-count inner is only unambiguous when what it
# repeats is itself fixed-width, and '((ab|c){2})+d' is a genuine bomb that reading the quantifier alone
# cannot tell apart from '(a{3})+b'. A structural screen that must return the same verdict on two different
# backtrackers cannot make that call, so it refuses — bounded, named, with a workaround — rather than hand
# either engine a pattern one of them never comes back from.
bombCase(){
    local label="$1" pat="$2"
    local rc; rc="$( capRun 20 "$TMP/out" "$TMP/err" "$CORPUS" --regex="$pat" --no-prefilter --no-cache )"
    if [ "$rc" = TIMEOUT ]; then
        no "$label: still running after 20 s — the bomb was HANDED TO THE ENGINE (this is the Linux hang)"
        return
    fi
    [ "$rc" -ge 128 ] && { no "$label: CRASHED (signal death, exit $rc)"; return; }
    if [ "$rc" -eq 1 ]; then ok "$label: refused at exit 1 (bounded, no scan)"; else no "$label: exit $rc (expected 1)"; fi
    grep -q 'hits=' "$TMP/out" && no "$label: printed a hits= element — a scan happened" || ok "$label: no hits= element on stdout"
    if grep -qF -- "$pat" "$TMP/err"; then ok "$label: refusal names the pattern"; else no "$label: refusal does not name the pattern"; fi
    grep -qi 'backtrack' "$TMP/err" && ok "$label: refusal names the construct (catastrophic backtracking)" \
        || no "$label: refusal does not name the construct: $( head -c 200 "$TMP/err" )"
}

bombCase "(a+)+b"    '(a+)+b'
bombCase "(a*)*b"    '(a*)*b'
bombCase "(a+)*b"    '(a+)*b'
bombCase "(a{2,})+b" '(a{2,})+b'
bombCase "((a+))+b"  '((a+))+b'
bombCase "((a)+)+b"  '((a)+)+b'
bombCase "(a+|b)+c"  '(a+|b)+c'
bombCase "(a?)+b"    '(a?)+b'
bombCase "(a{1,3})+b" '(a{1,3})+b'
bombCase "((a)?)+b"  '((a)?)+b'
bombCase "(a{3})+b"  '(a{3})+b'
bombCase "(?:a+)+b"  '(?:a+)+b'
bombCase "(a|a*)+"   '(a|a*)+'

# The refusal must carry a WORKAROUND, not just a complaint — the L5 refusal set that bar and this one
# keeps it. (Checked once; the sentence is shared by every construct.)
#
# PM-2 (2026-10-12): this used to read `grep -qi 'collapse\|bounded'`. `\|` is GNU BRE alternation, which BSD
# grep (every stock macOS) treats as a LITERAL pipe — so the arm silently failed on any Mac, with the pristine
# upstream binary as much as ours (the message demonstrably contains both words). -E selects ERE, where `|` is
# the alternation every grep agrees on. A portability repair on an arm this round already owns, not a scope
# change; Linux CI (GNU grep) was never affected.
"$BIN" "$CORPUS" --regex='(a+)+b' --no-cache >/dev/null 2>"$TMP/err"
grep -qiE 'collapse|bounded' "$TMP/err" && ok "refusal offers a workaround" \
    || no "refusal offers no workaround: $( head -c 300 "$TMP/err" )"

# ── (2) the refusal is STRUCTURAL, not corpus-triggered ─────────────────────────────────────────────────
# The old behaviour depended on reaching the bomb FILE: no long run of 'a' in the tree, no blowup, no
# degrade. The guard reads the pattern and nothing else, so the same verdict must come back from a corpus
# that contains no bait at all — this is what makes the outcome identical on every machine and every tree.
BENIGN="$TMP/benign"; mkdir -p "$BENIGN"; printf 'int quietFunction() { return 0; }\n' >"$BENIGN/quiet.cpp"
rc="$( capRun 20 "$TMP/out" "$TMP/err" "$BENIGN" --regex='(a+)+b' --no-cache )"
# same TIMEOUT-vs-verdict distinction as safeCase() above: a kill is not a corpus-dependence finding either.
if [ "$rc" = TIMEOUT ]; then
    no "corpus without bait: TIMEOUT/KILLED after 20s — not a verdict, the scan never finished"
else
    { [ "$rc" = 1 ] && [ -s "$TMP/err" ]; } \
        && ok "refused identically over a corpus with no bomb file (structural, not corpus-triggered)" \
        || no "corpus without bait: exit $rc — the verdict depends on the corpus"
fi

# ── (3) PRECISION: the guard must catch the nested-unbounded class and nothing wider ─────────────────────
# Over-refusal is the failure mode a structural guard invites. Each of these is quantifier-free inside its
# group, or unquantified on the outside, or BOUNDED on the outside, or has its '+' in a character class or
# behind a backslash — and every one of them must still SCAN.
#
# M2-b left this list SHORTER on one axis and longer on another. The two bounded-inner arms moved to the
# bomb battery (they hang libstdc++ — see the block above), and three arms were added to pin down what the
# widened screen must NOT touch: a non-capturing group, because '(?:' opens a group with a '?' that is a
# MODIFIER and not a quantifier and a screen reading it as one would refuse every '(?:abc)+' in the world;
# a BOUNDED outer quantifier over a group stuffed with unbounded ones, which is the refusal message's own
# suggested workaround and would be a self-contradiction to refuse; and a bounded inner under an
# UNQUANTIFIED outer, which proves the verdict turns on the outer quantifier and not on the inner.
safeCase(){
    local label="$1" pat="$2"
    local rc; rc="$( capRun 20 "$TMP/out" "$TMP/err" "$CORPUS" --regex="$pat" --no-cache )"
    # W1-V4 (2026-08-11): rc="TIMEOUT" is capRun's own sentinel for "still running after the cap, killed by
    # this harness" -- it is NOT an engine exit code, and it is emphatically not exit 0. Before this check the
    # fall-through below sent it straight to the else branch and printed "OVER-REFUSED: ... exit TIMEOUT",
    # asserting a refusal VERDICT that was never reached: the process never returned, it was SIGKILLed. A
    # killed/timed-out scan must report as TIMEOUT/KILLED and nothing else -- distinguish it before the verdict
    # check runs, the same way bombCase() already does two screens up.
    if [ "$rc" = TIMEOUT ]; then
        no "$label: TIMEOUT/KILLED after 20s — not a refusal verdict, the scan never finished (raise the harness budget or investigate a real hang, don't read this as over-refusal)"
        return
    fi
    { [ "$rc" = 0 ] && grep -q 'hits=' "$TMP/out"; } \
        && ok "not over-refused: $label still scans at exit 0" \
        || no "OVER-REFUSED: $label exit $rc — $( head -c 200 "$TMP/err" )"
}

safeCase "a+b (no group)"          'a+b'
safeCase "(a)+b (empty inner)"     '(a)+b'
safeCase "(abc)+ (literal group)"  '(abc)+'
safeCase "(a|b)+ (plain alt)"      '(a|b)+'
safeCase "((a|b))+ (nested disjoint alt)" '((a|b))+'
safeCase "[a+]+b ('+' in class)"   '[a+]+b'
safeCase "(a+)b (outer unquant.)"  '(a+)b'
safeCase "(a+)(b)+ (siblings)"     '(a+)(b)+'
safeCase "(?:abc)+ (non-capturing)" '(?:abc)+'
safeCase "(\s*\w+){1,20} (bounded outer)" '(\s*\w+){1,20}'
safeCase "(a?)b (bounded, outer unquant.)" '(a?)b'

# ── M2-e (round 6, PR #397): PROVEN DISJOINT BY FIRST CHARACTER — the multi-character class M2-c refused unread ─
# A branch that is an unquantified sequence of width-one atoms has a fixed width and matches deterministically
# once started, so the only remaining ambiguity is WHICH branch starts a position — and the branch's first
# character answers that in one. Pairwise-disjoint first-character sets across every branch end the question: the
# repetition cannot multiply, and these are admitted where M2-c refused them wholesale.
safeCase "^(ab|cd)+e$ (disjoint multi-char)" '^(ab|cd)+e$'
safeCase "(cat|dog)+ (keyword pair)"         '(cat|dog)+'
safeCase "(foo|bar)+ (prefix-free words)"    '(foo|bar)+'
safeCase "quoted-string JSON walker"         '"([^"\\]|\\.)*"'
safeCase "(\r\n|\n)+ (CRLF walker)"          '"(\r\n|\n)+"'

# and the point of the fixture survives: a safe pattern still finds normal.cpp's ordinary matches while
# bomb.md sits in the very same candidate set, scanned harmlessly.
"$BIN" "$CORPUS" --regex='a+b' --no-prefilter --no-cache >"$TMP/normal" 2>/dev/null
grep -q 'normal.cpp' "$TMP/normal" \
    && ok "normal.cpp's matches still land with a safe pattern (bomb.md in the same candidate set)" \
    || { no "normal.cpp matches missing under a safe pattern"; head -40 "$TMP/normal"; }

if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/normal" 2>/dev/null; then ok "well-formed XML on the safe path"; else { no "malformed XML"; cat "$TMP/normal"; }; fi
else
    printf '  SKIP  xmllint (not installed)\n'
fi

# ── (4) DETERMINISM — the refusal is a pure function of the pattern, so stderr too, not just stdout ──────
"$BIN" "$CORPUS" --regex='(a+)+b' --no-cache >"$TMP/d1" 2>"$TMP/e1"
"$BIN" "$CORPUS" --regex='(a+)+b' --no-cache >"$TMP/d2" 2>"$TMP/e2"
{ diff -q "$TMP/d1" "$TMP/d2" >/dev/null && diff -q "$TMP/e1" "$TMP/e2" >/dev/null; } \
    && ok "deterministic (two refusals byte-identical on stdout AND stderr)" || no "non-deterministic"
"$BIN" "$CORPUS" --regex='a+b' --no-prefilter --no-cache >"$TMP/s1" 2>/dev/null
"$BIN" "$CORPUS" --regex='a+b' --no-prefilter --no-cache >"$TMP/s2" 2>/dev/null
if diff -q "$TMP/s1" "$TMP/s2" >/dev/null; then ok "deterministic on the safe scanning path too"; else no "non-deterministic (safe path)"; fi

# ── (5) the ALTERNATION battery: the screen's documented gap, CLOSED statically (Phase 1; first characters, M2-e) ─
# This section used to print an INFO line — `(a|a)+b` "ran past 30 s — a KNOWN gap in the static guard". Phase 1
# closes that gap, so the gap line is REPLACED by real arms: every shape the screen now refuses is asserted here —
# bounded, by name, no hits= on stdout — the same contract bombCase() holds the nested battery to.
#
#   (a|a)+b      the audit's own PoC shape — two IDENTICAL branches, the simplest semantic overlap
#   (a|aa)+      the same overlap, taken at the FIRST CHARACTER: both branches start with the same set, so no
#                proof — whole-footprint or first-character — can break the split ambiguity (round 6, PR #397)
#   ^(a|aa)+b$   the audit's live bypass — a branch that is a PREFIX of another
#   (x|xy)+c$    the prefix shape again, with a trailing literal
#   (\w|\d)+$    two character classes that INTERSECT (\d is a subset of \w)
#   (get|getResponse)+  the shape that reads as innocent: both branches start with 'g', so which one matches a
#                byte is still ambiguous and the repetition can still split the input both ways (M2-e)
#   ((a|aa))+b$  M2-d — the PAREN BYPASS: the alternation sits one group deeper and closes under NO quantifier,
#                so only the flag it hands the parent frame tells the outer '+' what it repeats (round 6, PR #397)
#   (?:(?:a|aa))+b$  M2-d — the same bypass through non-capturing groups, whose modifiers must not be read as body
#
# The mid-match catch the old INFO line described is NOT gone — it is asserted portably by test/regexguardcheck.sh
# arm (b1) through the fault switch, and for the stopped-scan refusal by section (7) below. Nothing here claims
# otherwise. (The guard's per-file MATCH BUDGET — round 5's second cause of a stopped scan — is gone: the PR #397
# review removed it, sections (6)/(7) assert the removal and the single-cause refusal that is left.)
altCase(){
    local label="$1" pat="$2"
    local rc; rc="$( capRun 20 "$TMP/out" "$TMP/err" "$CORPUS" --regex="$pat" --no-cache )"
    if [ "$rc" = TIMEOUT ]; then
        no "$label: still running after 20 s — the alternation bomb was HANDED TO THE ENGINE (the Phase 1 gap is open again)"
        return
    fi
    [ "$rc" -ge 128 ] && { no "$label: CRASHED (signal death, exit $rc)"; return; }
    if [ "$rc" -eq 1 ]; then ok "$label: refused at exit 1 (bounded, no scan)"; else no "$label: exit $rc (expected 1)"; fi
    grep -q 'hits=' "$TMP/out" && no "$label: printed a hits= element — a scan happened" || ok "$label: no hits= element on stdout"
    if grep -qF -- "$pat" "$TMP/err"; then ok "$label: refusal names the pattern"; else no "$label: refusal does not name the pattern"; fi
    grep -qi 'backtrack' "$TMP/err" && ok "$label: refusal names the construct (catastrophic backtracking)" \
        || no "$label: refusal does not name the construct: $( head -c 200 "$TMP/err" )"
    # PM-1: the alternation refusal must say it cannot PROVE disjointness, NOT that the branches overlap (false for
    # disjoint branches — the refusal fires because no PROOF (whole-footprint or first-character) can read them).
    # 'backtrack' and a workaround word are the pinned pair; this asserts the honest wording too, so a future
    # rewording that regresses to the false claim reds here.
    grep -qiE 'prove|disjoint' "$TMP/err" && ok "$label: refusal is honest about the false-positive class (cannot PROVE disjoint)" \
        || no "$label: refusal does not state the screen cannot PROVE disjointness: $( head -c 200 "$TMP/err" )"
}

altCase "(a|a)+b"     '(a|a)+b'
altCase "(a|aa)+"     '(a|aa)+'
altCase "^(a|aa)+b$"  '^(a|aa)+b$'
altCase "(x|xy)+c$"   '(x|xy)+c$'
altCase "(\w|\d)+$"   '(\w|\d)+$'
altCase "(get|getResponse)+" '(get|getResponse)+'
altCase "((a|aa))+b$" '((a|aa))+b$'
altCase "(?:(?:a|aa))+b$" '(?:(?:a|aa))+b$'
# A non-ASCII literal branch must not be proven disjoint from a set that matches every non-ASCII byte: the first-
# character proof used to record 'é' (0xC3 0xA9) as the ASCII aliases {C} / {i}, so a complement or shorthand set that
# merely excluded 'C' looked disjoint from it (round 6, PR #397 review N-A). libc++ abandons both; libstdc++ goes
# exponential (\W|é)+b$ over "é"*n+"!" .
altCase "(\W|é)+b$"   '(\W|é)+b$'
altCase "([^C]|é)+b$" '([^C]|é)+b$'
# (a|a*)+ (a branch that can match EMPTY) is refused by the NESTED arm, not this one: its group contains '*', so the
# first arm fires and its message is the nested-repetition one. It is asserted as a bombCase above, where that
# message belongs. The PM-1 honesty assertion below applies only to patterns the ALTERNATION arm actually catches.

# ── (6) the MATCH BUDGET IS REMOVED — the fault switch that keyed it is inert ─────────────────────────────
# Round 5 added a per-file match budget (kRegexFileMatchBudget, keyed by RIPWIRE_FAULT_REGEX_BUDGET) as a libstdc++
# backstop. The PR #397 review removed it (round 6): it counted line-MATCH ATTEMPTS, so a file of fast linear
# answers (^9\d\d$ under --no-prefilter, \d{4}-\d{2}-\d{2} over logs) exhausted it and was refused although every
# attempt was cheap; and one std::regex call is atomic to its caller, so a counter BETWEEN calls bounded nothing
# inside one — the single-match hole was open either way (docs/LIMITS.md, `regex-screen-multiquantifier`). A
# first-class removal, asserted, not a silent one: these arms prove the switch is no longer read and the fixture
# the budget used to stop mid-scan now scans cleanly with it SET.
#
# many.md holds 10 candidate lines (each carries the required literal 'x'); hit.md one, so a scan that continued
# past a budgeted file still had something to find — the old arm's own fixture, kept so the removal is proven
# against exactly what used to stop. `x+` is ADMITTED by the screen and is NOT a literal plan, so every candidate
# line reaches the engine — the counter the budget used to read. The switch is a plain environment variable the
# binary no longer consults, so this runs on every flavour without asking (there is no NDEBUG-leg asymmetry left).
BUDGET_DIR="$TMP/budgetfix"; mkdir -p "$BUDGET_DIR"
: >"$BUDGET_DIR/many.md"
for _i in 1 2 3 4 5 6 7 8 9 10; do printf 'x line %s\n' "$_i" >>"$BUDGET_DIR/many.md"; done
printf 'x marker\n' >"$BUDGET_DIR/hit.md"

# control: with no switch the corpus scans cleanly, so what (6) pins below is the switch, not the corpus.
rc="$( capRun 20 "$TMP/out" "$TMP/err" "$BUDGET_DIR" --regex='x+' --no-cache )"
if [ "$rc" = 0 ] && grep -q 'hits="[1-9]' "$TMP/out"; then ok "budget removal control: with no switch the corpus scans cleanly at exit 0 (hits present)"
else no "budget removal control: exit $rc — the corpus does not scan cleanly even with nothing to stop it: $( head -c 200 "$TMP/err" )"; fi

# the removal itself: RIPWIRE_FAULT_REGEX_BUDGET=1 — the exact value that stopped this corpus at exit 1 with
# kRegexBudgetReason on stderr — now changes nothing at all, and the answer is byte-identical to the control's.
rc="$( RIPWIRE_FAULT_REGEX_BUDGET=1 capRun 20 "$TMP/b.out" "$TMP/b.err" "$BUDGET_DIR" --regex='x+' --no-cache )"
if [ "$rc" = 0 ] && grep -q 'hits="[1-9]' "$TMP/b.out"; then
    ok "budget: RIPWIRE_FAULT_REGEX_BUDGET=1 is inert (the budget is removed): the corpus still scans at exit 0"
else
    no "budget: RIPWIRE_FAULT_REGEX_BUDGET=1 still changes the answer (exit $rc) — removed machinery still live?"
fi
if cmp -s "$TMP/out" "$TMP/b.out"; then ok "budget: stdout byte-identical with the switch set (nothing reads it)"
else no "budget: stdout differs with the switch set — something still consumes the removed switch"; fi
grep -q 'match budget' "$TMP/b.err" && no "budget: stderr still names a match budget the guard no longer has" \
    || ok "budget: no match-budget sentence anywhere on stderr"

# ── (7) A STOPPED SCAN HAS ONE CAUSE — THE ENGINE'S — and the refusal says so, once ──────────────────────
# The round-4 fix split a stopped --regex scan per cause, each with its own count, reason, file and advice,
# because one run could stop files BOTH ways: the engine abandoning a match in one file, the guard's per-file
# budget (section (6)'s removed machinery) stopping others. The PR #397 review removed the budget, so a stop is
# the ENGINE abandoning a match (RegexVerdict::Exhausted from std::regex) and nothing else, and the split carried
# nothing: one sentence again, the whole stopped count, the first (lowest-fileId) file, kRegexAbandonedReason and
# the outer-quantifier advice. (7) drives the one remaining cause over a three-file fixture and asserts the whole
# single-cause contract: the count is the run's total (there is no per-cause subtraction any more), exactly ONE
# refusal sentence prints, and the stderr is byte-identical run to run.
#
# Fault switches are compiled out under NDEBUG, so ASK the binary (the prcontextcheck idiom) before asserting.
RIPWIRE_FAULT_CHARGE_BUFFER=1 "$BIN" "$CORPUS" --top-k=5 --pack-signatures --no-cache >/dev/null 2>"$TMP/probe.err"
if grep -aq 'open_memstream failed' "$TMP/probe.err"; then FAULTS=1; else FAULTS=0; fi

if [ "$FAULTS" -eq 1 ]; then
    MIX_DIR="$TMP/mixfix"; mkdir -p "$MIX_DIR"
    # three files, each with candidate lines for 'x+' (every line carries the required literal 'x'), in an order the
    # sorted crawl fixes: the refusal must name aa.md, the lowest fileId, and count all three.
    for _f in aa mm zz; do
        : >"$MIX_DIR/$_f.md"; for _i in 1 2 3 4 5; do printf 'x line\n' >>"$MIX_DIR/$_f.md"; done
    done

    rc="$( RIPWIRE_FAULT_REGEX_MATCH=1 capRun 20 "$TMP/m.out" "$TMP/m.err" "$MIX_DIR" --regex='x+' --no-prefilter --no-cache )"
    if [ "$rc" = TIMEOUT ]; then
        no "stopped scan: TIMEOUT/KILLED after 20 s"
    elif [ "$rc" -eq 1 ]; then ok "stopped scan: the engine abandoning every candidate file refuses at exit 1 (bounded)"
    else no "stopped scan: exit $rc (expected a refusal at exit 1)"; fi
    grep -q 'hits=' "$TMP/m.out" && no "stopped scan: printed a hits= element — a stopped scan was reported as a measurement" \
        || ok "stopped scan: no hits= element on stdout"

    # Isolate the refusal sentence: the DISCLOSE lines on stderr mention the same words, so match the refusal head.
    refusals="$( grep -F 'no hit is reported:' "$TMP/m.err" )"
    # ONE CAUSE, ONE SENTENCE: the round-4 message printed one sentence per cause; with the budget gone there is
    # exactly one, whoever runs it — asserting the count of sentences pins the removal as hard as (6) does.
    if [ "$( printf '%s\n' "$refusals" | grep -c . )" = 1 ]; then
        ok "stopped scan: exactly ONE refusal sentence (a stopped scan has one cause)"
    else
        no "stopped scan: expected exactly one refusal sentence, got $( printf '%s\n' "$refusals" | grep -c . ): $( printf '%s\n' "$refusals" | head -c 260 )"
    fi
    engineLine="$refusals"
    # the whole stopped count, and the first file the sorted crawl fixes
    if printf '%s\n' "$engineLine" | grep -qF 'in 3 file(s), first' && printf '%s\n' "$engineLine" | grep -qF 'first aa.md'; then
        ok "stopped scan: the refusal carries the whole stopped count (3) and names the lowest-fileId file (aa.md)"
    else
        no "stopped scan: the refusal does not count 3 files naming aa.md: $( printf '%s\n' "$engineLine" | head -c 320 )"
    fi
    # the reason is the ENGINE's own — no second sentence, no budget reason left to quote
    printf '%s\n' "$engineLine" | grep -qF 'std::regex gave up part-way through it' \
        && ok "stopped scan: the refusal quotes kRegexAbandonedReason" \
        || no "stopped scan: the refusal does not quote kRegexAbandonedReason: $( printf '%s\n' "$engineLine" | head -c 260 )"
    printf '%s\n' "$engineLine" | grep -qF 'match budget' && no "stopped scan: the refusal still names the removed budget" \
        || ok "stopped scan: no match-budget sentence anywhere in the refusal"
    # determinism: the refused stderr is a pure function of the corpus, byte for byte
    RIPWIRE_FAULT_REGEX_MATCH=1 "$BIN" "$MIX_DIR" --regex='x+' --no-prefilter --no-cache >"$TMP/m2.out" 2>"$TMP/m2.err"
    { diff -q "$TMP/m.out" "$TMP/m2.out" >/dev/null && diff -q "$TMP/m.err" "$TMP/m2.err" >/dev/null; } \
        && ok "stopped scan: deterministic (two refusals byte-identical on stdout AND stderr)" || no "stopped scan: non-deterministic"
else
    printf '  INFO  stopped scan: this binary compiles fault switches out (NDEBUG): the injected abandonment is unobservable BY DESIGN here\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

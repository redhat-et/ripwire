#!/usr/bin/env bash
# regexmultiquantcheck.sh — `regex-screen-multiquantifier` gate: the MULTI-QUANTIFIER family is REFUSED by the
# structural screen, not left to the engine.
#
# WHAT THIS GATE EXISTS FOR. Two structural families have been closed in this file's neighbourhood. `(a+)+b` was
# closed by regex-screen-hardening's nested-repetition rule, and `(a|a)+b` by its unproven-alternation rule. Both
# read a group that closes under an UNBOUNDED quantifier. Every pattern below is admitted by both, by
# construction, and each one costs the ENGINE time that grows with the SUBJECT while the screen says nothing:
#
#   shape (i)    a*a*a*a*a*b                      group-free flat — no group for either rule to inspect
#   shape (ii)   ^(a)*(a)*(a)*(a)*(a)*$           grouped, no top-level '|' — nothing for the alternation rule
#   shape (iii)  ^(ab\w|((.|.){1,3}){1,3}){1,3}$  bounded-nested — the outer {1,3} is BOUNDED, so the
#                                                 unbounded-outer rule never fires on the (.|.) overlap
#
# THE CONTRACT THESE ARMS HOLD: for each shape, `--regex=<shape>` over a NON-MATCHING subject on the shape's own
# alphabet is a STRUCTURAL REFUSAL — exit 1 with the refusal naming the construct — and NOT an engine
# abandonment, which is what happens today.
#
# ── THE DISCRIMINATOR IS THE LEAD-IN, AND THIS WAS MEASURED, NOT ASSUMED ─────────────────────────────────────
# Every arm here discriminates REFUSAL from ABANDONMENT on the message's LEAD-IN. Four candidate tokens were
# measured against both messages on the pre-change binary and three of them are unusable — recording them here
# because each is a dud arm someone will otherwise reach for:
#
#   ✗ exit status      refusal → exit 1 / stdout 0 B ; abandonment → exit 1 / stdout 0 B. IDENTICAL. An arm
#                      asserting `exit != 0` passes on the pre-change binary and proves nothing.
#   ✗ `refused`        prefixes BOTH messages (`refused, nothing was scanned:` / `refused, no hit is reported:`).
#                      A `grep refused` arm passes on an abandonment.
#   ✗ `catastrophic backtracking`
#                      the ABANDONMENT path prints it too — as the hedged parenthetical `(catastrophic
#                      backtracking?)` in the `[math degraded]` DISCLOSE at search.h:1236. A presence test on it
#                      passes on an abandonment.
#   ✗ `abandoned`      the structural message contains `abandons the match` (present tense, inside
#                      catastrophicRegexMessage's own wording) and the abandonment contains `abandoned the
#                      match`. A negative test happens to pass — but on ONE LETTER, a copy-edit accident, not
#                      a contract.
#   ✓ the LEAD-IN      `refused, nothing was scanned:`  → structural refusal  (verbs_grep.h:991, one site)
#                      `refused, no hit is reported:`   → engine abandonment   (verbs_grep.h:899, one site)
#                      Mutually exclusive: neither emitter can produce the other's, and the lead-in is the
#                      load-bearing semantic ("did a scan happen?") rather than a wording flourish.
#
# ── THE FIXTURES ARE PINNED AT MEASURED THRESHOLDS, NOT AT "SMALL" ───────────────────────────────────────────
# A shape needs a subject long enough to make the ENGINE give up, because the red baseline for this gate is
# precisely "the engine did the work". Measured on the pre-change binary (AppleClang 16 / libc++, macOS), the
# first abandoning length per shape:
#
#   shape (i)   b + 'a'×400          abandons from n≈20   (n=10 clean, n=20 abandoned) — fixture uses 400
#   shape (ii)  'a'×60 + 'z'         abandons from n=20   (n=10 clean, n=20 abandoned) — fixture uses 60
#   shape (iii) 'abw' + '.'×19 + 'Z' abandons from n≈18   (n=16 clean, n=18 abandoned) — fixture uses 19
#
# A shorter subject would be ADMITTED AND CLEAN, and the arm would be green on the pre-change binary — the
# dud-arm class this tree already has a rule for. The thresholds are stated so a future editor who "tidies" a
# fixture down knows exactly what they are breaking.
#
# Note that shape (i)'s subject puts the required literal FIRST (`b` then the run of `a`). That is deliberate:
# holdsRequired() only asks whether the literal is present, so a subject whose 'b' precedes the run still
# reaches the engine and still abandons — whereas a subject of pure 'a' contains no 'b' at all and the
# PREFILTER would drop it, making the run clean for a reason that has nothing to do with this family. Measured:
# `--no-prefilter` and default-prefilter both abandon on this fixture, so the arms pass either way and the flag
# is written down rather than left to a default.
#
# Usage: RIPWIRE_BIN=build/ripwire bash test/regexmultiquantcheck.sh
# Exits non-zero on any failure. Does NOT touch regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "regexmultiquantcheck: BIN=$BIN"

# The two lead-ins. Named once, used everywhere: an arm that spells these inline is an arm that can drift.
READ_REFUSED='refused, nothing was scanned:'
READ_ABANDONED='refused, no hit is reported:'

# A run must be BOUNDED, and "bounded" is the half of this contract a Mac cannot otherwise see: on libstdc++
# the pre-fix binary is still working long after this harness's cap. Every run is wrapped in a hard wall-clock
# cap so a regression is a FAILURE rather than a hung suite. No timeout(1) on a stock macOS: background run plus
# a polling wait does the same job in portable POSIX shell (the regexbombcheck.sh idiom, inherited).
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

# ── fixtures ─────────────────────────────────────────────────────────────────────────────────────────────────
# One directory per shape, ONE file each — so "the subject" is unambiguous and a later arm cannot be polluted by
# a neighbour's file (this gate's own evidence bundle carries the story of a probe dir that stopped being the
# fixture it claimed to be).
FIX="$TMP/fix"; mkdir -p "$FIX/i" "$FIX/ii" "$FIX/iii" "$FIX/clean"

python3 - "$FIX" <<'PY'
import sys, os
root = sys.argv[1]
# shape (i): required literal 'b' FIRST, then the run. Non-matching (a*a*a*a*a*b needs the b to FOLLOW).
open(os.path.join(root, 'i', 'b_then_a.c'), 'w').write('b' + 'a' * 400 + '\n')
# shape (ii): run of 'a' then a 'z' the anchored $ refuses. Non-matching.
open(os.path.join(root, 'ii', 'a_then_z.c'), 'w').write('a' * 60 + 'z\n')
# shape (iii): required literal 'abw' then dots, then 'Z'. Non-matching.
open(os.path.join(root, 'iii', 'dots.c'), 'w').write('abw' + '.' * 19 + 'Z\n')
# the clean control: must stay CLEAN under the very patterns the arms above refuse with.
open(os.path.join(root, 'clean', 'plain.c'), 'w').write('int plainFunction() { return 0; }\n')
PY

[ -f "$FIX/i/b_then_a.c" ] || { echo "fixture generation failed — python3 missing?"; exit 2; }

# ── (1) THE THREE SHAPES ARE REFUSED, NOT ABANDONED ──────────────────────────────────────────────────────────
# Each arm asserts, in this order and for the reason recorded at the top of this file:
#   • the run returned at all (a TIMEOUT is the Linux hang, not a verdict)
#   • the verdict is a STRUCTURAL REFUSAL — the refusal lead-in is present ...
#   • ... and it is NOT an abandonment — the abandonment lead-in is ABSENT
#   • the refusal names the construct (content check, never the discriminator)
#   • no hits= element reached stdout (a refusal that still reported a measurement would be worse than neither)
shapeCase(){
    local label="$1" pat="$2" subjectDir="$3"
    local rc; rc="$( capRun 25 "$TMP/out" "$TMP/err" "$subjectDir" --regex="$pat" --no-cache )"
    if [ "$rc" = TIMEOUT ]; then
        no "$label: still running after 25 s — the shape was HANDED TO THE ENGINE and never came back (this is the libstdc++ hang)"
        return
    fi
    [ "$rc" -ge 128 ] && { no "$label: CRASHED (signal death, exit $rc)"; return; }

    # the discriminator: lead-in present, its twin absent. Asserted as a PAIR — one without the other is not a
    # verdict, it is a message that changed shape.
    local got_refusal=0 got_abandoned=0
    grep -qF -- "$READ_REFUSED"   "$TMP/err" && got_refusal=1
    grep -qF -- "$READ_ABANDONED" "$TMP/err" && got_abandoned=1
    if [ "$got_refusal" = 1 ] && [ "$got_abandoned" = 0 ]; then
        ok "$label: STRUCTURAL refusal (lead-in '$READ_REFUSED', no abandonment lead-in)"
    elif [ "$got_abandoned" = 1 ]; then
        no "$label: engine ABANDONMENT, not a structural refusal — the screen admitted it and the engine did the work: $( head -c 200 "$TMP/err" )"
        return
    else
        no "$label: neither refusal lead-in on stderr (exit $rc) — the verdict is unrecognised: $( head -c 200 "$TMP/err" )"
        return
    fi

    [ "$rc" -eq 1 ] && ok "$label: exit 1" || no "$label: exit $rc (a structural refusal is exit 1)"
    grep -q 'hits=' "$TMP/out" && no "$label: printed a hits= element — a refusal was reported as a measurement" \
        || ok "$label: no hits= element on stdout"
    if grep -qF -- "$pat" "$TMP/err"; then ok "$label: refusal names the pattern"; else no "$label: refusal does not name the pattern"; fi
    # the construct, as CONTENT (not discriminator): every refusal in this family opens on the same phrase.
    grep -qiF 'catastrophic backtracking' "$TMP/err" && ok "$label: refusal names the construct" \
        || no "$label: refusal does not name the construct: $( head -c 200 "$TMP/err" )"
}

# shape (i) — group-free flat. The audit's own PoC.
shapeCase "shape (i) a*a*a*a*a*b (group-free flat)"   'a*a*a*a*a*b' "$FIX/i"
# shape (ii) — grouped, no top-level '|', so the alternation arm has nothing to read and the groups close under
# a bounded-or-unbounded star that is NOT nested (arm (1) needs a quantifier INSIDE the group; 'a' has none).
shapeCase "shape (ii) ^(a)*(a)*(a)*(a)*(a)*\$ (grouped, no top-level |)" '^(a)*(a)*(a)*(a)*(a)*$' "$FIX/ii"
# shape (iii) — rendered spelling ONLY. The dispatch note's `(.\|.)` is a LITERAL backslash-pipe: a different,
# harmless pattern that is ADMITTED and returns in 0.0 ms at every length. An arm authored from that spelling
# would be GREEN on the pre-change binary and would "prove" the gap exists by measuring a pattern that has none.
shapeCase "shape (iii) ^(ab\w|((.|.){1,3}){1,3}){1,3}\$ (bounded-nested, RENDERED)" '^(ab\w|((.|.){1,3}){1,3}){1,3}$' "$FIX/iii"

# ── (2) THE SPELLING CONTROL — the inert twin must STILL BE ADMITTED ─────────────────────────────────────────
# This is the arm that stops a future editor "fixing" shape (iii) by refusing the literal-pipe spelling. It is a
# different pattern (it matches a literal '|'), it is not a family member, and refusing it would be an
# over-refusal with a body count: `\|` inside an alternation is ordinary sed/awk-shaped usage.
rc="$( capRun 25 "$TMP/out" "$TMP/err" "$FIX/iii" --regex='^(ab\w|((.\|.){1,3}){1,3}){1,3}$' --no-cache )"
if [ "$rc" = TIMEOUT ]; then
    no "iii-A literal-pipe spelling: TIMEOUT after 25 s — it was handed to the engine, which it never should be"
else
    { [ "$rc" = 0 ] && grep -q 'hits=' "$TMP/out"; } \
        && ok "iii-A literal backslash-pipe spelling still SCANS at exit 0 (a different pattern, correctly admitted)" \
        || no "iii-A literal-pipe spelling: exit $rc — the inert twin was refused, which is an over-refusal: $( head -c 200 "$TMP/err" )"
fi

# ── (3) THE ADMIT SET IS UNCHANGED ────────────────────────────────────────────────────────────────────────────
# Over-refusal is the failure mode a structural screen invites, and this spec's primary risk. These patterns are
# either quantifier-free inside their group, or carry ONE quantifier where the family needs adjacent ones, or are
# provably disjoint — every one must still scan at exit 0. `TODO|FIXME` and `foo.*bar` are the two most likely
# casualties of a rule that reads '|' or '*' too eagerly; `(\s*\w+){1,20}` is the spec's own bound-and-repeat
# control and is ALSO the workaround the refusal message teaches, so refusing it would be a self-contradiction.
safeCase(){
    local label="$1" pat="$2"
    local rc; rc="$( capRun 25 "$TMP/out" "$TMP/err" "$FIX/clean" --regex="$pat" --no-cache )"
    if [ "$rc" = TIMEOUT ]; then
        no "$label: TIMEOUT/KILLED after 25 s — not a refusal verdict, the scan never finished"
        return
    fi
    { [ "$rc" = 0 ] && grep -q 'hits=' "$TMP/out"; } \
        && ok "admit-set unchanged: $label still scans at exit 0" \
        || no "OVER-REFUSED: $label exit $rc — $( head -c 200 "$TMP/err" )"
}
safeCase "(a|b)+ (disjoint alternation under repetition)" '(a|b)+'
safeCase "(abc)+ (one literal atom repeated)"             '(abc)+'
safeCase "TODO|FIXME (top-level alternation, no quantifier)" 'TODO|FIXME'
safeCase "foo.*bar (one quantifier, not adjacent to another)" 'foo.*bar'
safeCase "(\s*\w+){1,20} (the refusal's own suggested workaround)" '(\s*\w+){1,20}'
# and the atom-repeat pair the rule must NOT confuse with the family: '(a)*' is ONE quantified atom, so there is
# no adjacent pair to unpick — the family needs two or more in the same scope.
safeCase "ab*c (single quantified atom between literals)"  'ab*c'
safeCase "^\w+$ (one unbounded atom, anchored)"            '^\w+$'

# ── (4) THE FAMILY IS REFUSED ON A CORPUS WITH NO BAIT IN IT ─────────────────────────────────────────────────
# The pre-change behaviour depends on REACHING a long line: no run of 'a' in the tree, no blowup, no abandonment,
# and the run looks clean for a reason that is an accident of the corpus. A structural screen reads the PATTERN,
# so the verdict must come back from a directory with nothing in it that the shape could chew on. This is what
# makes the outcome identical on every machine and every tree, and it is the reason refusal is the fix rather
# than a shorter line limit.
rc="$( capRun 25 "$TMP/out" "$TMP/err" "$FIX/clean" --regex='a*a*a*a*a*b' --no-cache )"
if [ "$rc" = TIMEOUT ]; then
    no "corpus without bait: TIMEOUT/KILLED after 25 s — not a verdict, the scan never finished"
else
    { [ "$rc" = 1 ] && grep -qF -- "$READ_REFUSED" "$TMP/err" && ! grep -qF -- "$READ_ABANDONED" "$TMP/err"; } \
        && ok "shape (i) refused identically over a corpus with no bait (structural, not corpus-triggered)" \
        || no "corpus without bait: exit $rc, wrong verdict — the outcome depends on the corpus: $( head -c 200 "$TMP/err" )"
fi

# ── (5) THE VERDICT IS A PURE FUNCTION OF (file, pattern) ────────────────────────────────────────────────────
# This spec's AC5, and the AC that forbids the obvious "cap the wall time" fix: a clock-reading bound would make
# the verdict depend on the machine and the run. Refusal is a pure function, so stdout AND stderr are
# byte-identical across runs.
"$BIN" "$FIX/i" --regex='a*a*a*a*a*b' --no-cache >"$TMP/d1" 2>"$TMP/e1"
"$BIN" "$FIX/i" --regex='a*a*a*a*a*b' --no-cache >"$TMP/d2" 2>"$TMP/e2"
{ diff -q "$TMP/d1" "$TMP/d2" >/dev/null && diff -q "$TMP/e1" "$TMP/e2" >/dev/null; } \
    && ok "deterministic: two refusals byte-identical on stdout AND stderr" || no "non-deterministic refusal"

# ── (6) THE VOCABULARY IS EXTENDED, NOT BLURRED (AC8) ────────────────────────────────────────────────────────
# A structural refusal must not be spelled as an engine abandonment. Since both exit 1, this is a MESSAGE
# assertion and nothing else: the refusal's own words name the construct and the quantifier it objects to, and
# the string this spec must NOT reintroduce (`kRegexBudgetReason`'s per-file match budget, removed by the PR #397
# review) stays absent from every message this gate provokes.
"$BIN" "$FIX/i" --regex='a*a*a*a*a*b' --no-cache >/dev/null 2>"$TMP/refuse.err"
grep -qF 'the unbounded quantifier' "$TMP/refuse.err" \
    && ok "the refusal names the construct as a quantifier ('the unbounded quantifier ...')" \
    || no "the refusal does not name the quantifier: $( head -c 300 "$TMP/refuse.err" )"
grep -qiE 'collapse|bounded|workaround' "$TMP/refuse.err" \
    && ok "the refusal offers a workaround" \
    || no "the refusal offers no workaround: $( head -c 300 "$TMP/refuse.err" )"
grep -qi 'match budget' "$TMP/refuse.err" \
    && no "the refusal names a match budget — the PR #397 removal is being reintroduced under another name" \
    || ok "no match-budget sentence anywhere in the refusal (the removal stands)"

# ── (7) THE PRECEDING FAMILIES STILL REFUSE WITH THEIR OWN MESSAGES ──────────────────────────────────────────
# AC3, in miniature and inside this gate: the two families closed BEFORE this spec must be untouched by it. Both
# are asserted on the lead-in (structural) — their full wording is pinned by test/regexguardcheck.sh, which this
# gate does not duplicate. What it protects is the ORDER of the arms: a widened screen that starts catching
# `(a+)+b` with the NEW message would break every downstream arm that pins the nested-repetition sentence.
legacyCase(){
    local label="$1" pat="$2"
    local rc; rc="$( capRun 25 "$TMP/out" "$TMP/err" "$FIX/clean" --regex="$pat" --no-cache )"
    if [ "$rc" = TIMEOUT ]; then no "$label: TIMEOUT/KILLED after 25 s"; return; fi
    { [ "$rc" = 1 ] && grep -qF -- "$READ_REFUSED" "$TMP/err" && ! grep -qF -- "$READ_ABANDONED" "$TMP/err"; } \
        && ok "$label still refused structurally (this spec did not displace it)" \
        || no "$label: exit $rc, verdict changed: $( head -c 200 "$TMP/err" )"
}
legacyCase "nested-repetition (a+)+b"  '(a+)+b'
legacyCase "unproven-alternation (a|a)+b" '(a|a)+b'

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

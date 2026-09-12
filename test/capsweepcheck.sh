#!/usr/bin/env bash
# capsweepcheck.sh — the cap-sensitivity harness and the document it generates.
#
# WHY. docs/LIMITS.md says a cap EXISTS. It cannot say what the cap DOES. bench/capsweep answers that
# by measuring — and a measuring instrument gets exactly one thing checked about it: whether it is
# measuring the subject or measuring itself. This gate exists for the second question first.
#
# THE DEFECT THIS GATE IS BUILT AROUND. The first sweep ran against the LIVE worktree, which holds the
# harness and the JSON it writes. The harness dir grew between the baseline pass and the probe passes,
# so 18-21 invocations "responded" to every cap — including caps that touch nothing those verbs read.
# Systematic, not random, right units, plausible magnitudes: it read exactly like signal, and it cost a
# night. The fix was a corpus frozen with `git archive HEAD` plus every byte of harness state kept
# outside it. Arm (B) is that fix, held down by a control that can actually fail.
#
# NO BUILD. Every arm here is source-level: the patcher runs against a SYNTHETIC tree, the corpus
# assertion against a SYNTHETIC corpus, and the document is compared against the committed json. That
# is deliberate — the sweep itself needs a patched build and thousands of invocations, so a gate that
# re-ran it would never run. What is gated is the part that can rot silently.
#
# ARMS
#   (A) THE PATCHER, on a synthetic tree: a cap declaration is rewritten into the env-read shape, and a
#       declaration that is NOT a cap is left byte-identical. Both halves matter — a patcher that
#       rewrote everything would also "pass" the first half.
#   (B) THE CORPUS-FREEZE ASSERTION can go red: a synthetic corpus containing bench/capsweep must be
#       REFUSED, and the same corpus without it must be accepted. Contrast, not a one-sided assertion.
#   (C) THE DOCUMENT: `emit --check` reproduces docs/TUNING.md byte-for-byte from the committed
#       bench/capsweep/*.tsv plus the live cap census in src/. The committed doc came out of the same
#       generator, so on its own this is a round trip and proves nothing (see the self-referential-
#       baseline trap). The control is what makes it real: mutate ONE number in a COPY of sweep.tsv,
#       re-run against that copy, and require the comparison to fail. The doc is then demonstrably a
#       function of the data rather than a file that happens to sit next to it.
#   (D) the document says "Generated — do not edit" — a generated file that does not say so gets
#       hand-edited exactly once, and the edit is lost on the next regeneration with no diff to read.
#   (E) the harness refuses to patch the repository itself (the G3/G5 line: production keeps constexpr).
#   (F) THE RECORDS ARE NOT JSON. Arm (B) keeps the harness out of the TREE it measures and says nothing
#       about the FORMAT it writes in — and ripwire INDEXES `.json` as config keys (src/ingest_crawl.h)
#       while `.tsv` is unindexed prose (src/docparse.h, kUnindexedProseExts, beside `.txt`). The first
#       round of this harness committed screen/sweep/tunable as json and they entered the repo's own
#       index: measured on this tree, `--for="incremental cache invalidation"` — the README's headline
#       example — answered confidence="low" margin_pct="0" with them present and confidence="high"
#       margin_pct="22" without, and `--for=kMaxExpandSibs` surfaced bench/capsweep/sweep.json in an
#       answer about a cap. So a json file under bench/capsweep is a failure by its extension alone,
#       held down by a control that finds one in a SYNTHETIC copy — never in the real tree.
#   (G) AN UNBALANCED QUOTE is recorded UNPARSEABLE and the rows after it still run.
#   (H) A NON-ZERO EXIT is a distinct state carrying no byte count — never "0 bytes", which is what made
#       a refusal and an answer-of-nothing the same measurement.
#   (I) THE DENOMINATOR is the rows that ANSWERED, the records say so, and a run in which NOTHING
#       answered REFUSES to report a split or write records (the green-while-inert class).
#   (J) $VARS expand from the environment handed to the child, an UNDEFINED one is refused rather than
#       passed through as a literal, and the destination resolves outside the corpus.
#   (K) A CORPUS FINGERPRINT taken before the arms and re-checked after each one: a file created inside
#       the corpus mid-run aborts and names the path. (B) guards one directory name; this guards the class.
#   (K2) …and the fingerprint carries each entry's TYPE and CONTENT DIGEST, so a file OVERWRITTEN in
#       place aborts too. A name list sees a creation and is blind to a rewrite of the same path.
#   (L) A GIT REPOSITORY ABOVE the corpus is refused — ripwire walks up for .git in its own code.
#   (M) THE HISTORY FIXTURE: `git archive HEAD` leaves no .git, so the git verbs measured their degraded
#       path. Three commits over the same files plus a dirty tree; a tree missing them is REFUSED.
#
# G-L run the production screen_core through the `run-corpus` phase against a STUB binary, so they still
# cost no build. Arms A-F never executed a single corpus row, which is precisely how four defects
# shipped inside the phase they were meant to guard.
#
# This gate binds no ripwire binary: its subjects are a python harness, a source tree and a markdown
# file. It is pinned in test/binoverridecheck.sh's exemption list for that reason.
#
# Usage:  bash test/capsweepcheck.sh
# Exit:   0 = clean · 1 = at least one arm failed · 2 = usage / missing prerequisite
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
GEN="$ROOT/bench/capsweep/capsweep.py"
DOC="$ROOT/docs/TUNING.md"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v python3 >/dev/null 2>&1 || { echo "capsweepcheck: python3 is required"; exit 2; }
[ -f "$GEN" ] || { echo "capsweepcheck: no bench/capsweep/capsweep.py"; exit 2; }
[ -f "$DOC" ] || { echo "capsweepcheck: no docs/TUNING.md — run: python3 bench/capsweep/capsweep.py emit"; exit 2; }
for j in tunable.tsv sweep.tsv screen.tsv corpus.txt; do
    [ -f "$ROOT/bench/capsweep/$j" ] || {
        echo "capsweepcheck: bench/capsweep/$j is missing — the records are TSV, not json (see arm (F)):"
        echo "               ripwire indexes .json, so the harness must not publish itself in that format"
        exit 2; }
done

# A content snapshot of src/, not `git diff`: a developer with legitimate uncommitted work in src/ must
# not read as an escaped patcher. This compares the tree to ITSELF across this gate's own runtime.
srcsum(){ find "$ROOT/src" -type f -print0 | sort -z | xargs -0 cat 2>/dev/null | wc -c; }
src_before="$( srcsum )"

# ── (A) the patcher, on a synthetic tree ────────────────────────────────────────────────────────────
# Two declarations, one a cap by the harness's own rule (a k-name matching its KEY vocabulary) and one
# not. A presence guard runs first: if the fixture stopped containing what the arm greps for, the arm
# would compare nothing against nothing and pass.
mkdir -p "$TMP/synth/src"
cat > "$TMP/synth/src/synth.h" <<'EOF'
#pragma once
inline constexpr std::size_t kSynthRowCap = 7;      // a cap: bounds how many rows survive
inline constexpr double kSynthPlainConstant = 3.5;  // NOT a cap: no cap-vocabulary token in the name
EOF
grep -q 'kSynthRowCap' "$TMP/synth/src/synth.h" && grep -q 'kSynthPlainConstant' "$TMP/synth/src/synth.h" || {
    no "(A) fixture guard: the synthetic header lost its own declarations"; }
before_plain="$( grep 'kSynthPlainConstant' "$TMP/synth/src/synth.h" )"

if ! python3 "$GEN" patch --root "$TMP/synth" > "$TMP/patch.out" 2>&1; then
    no "(A) patcher exited non-zero on a synthetic tree: $( head -3 "$TMP/patch.out" | tr '\n' ' ' )"
else
    after_cap="$( grep 'kSynthRowCap' "$TMP/synth/src/synth.h" )"
    after_plain="$( grep 'kSynthPlainConstant' "$TMP/synth/src/synth.h" )"
    a_ok=0; b_ok=0
    case "$after_cap" in
        *'rwcapsweep::envOr'*'RWCAP_kSynthRowCap'*'7'*) a_ok=1 ;;
    esac
    case "$after_cap" in *constexpr*) a_ok=0 ;; esac      # it must no longer be constexpr, or nothing is tunable
    [ "$after_plain" = "$before_plain" ] && b_ok=1
    if [ "$a_ok" = 1 ] && [ "$b_ok" = 1 ]; then
        ok "(A) patcher rewrites a cap into the env-read shape and leaves a non-cap declaration untouched"
    else
        [ "$a_ok" = 1 ] || no "(A) the cap declaration was not rewritten into the env-read shape: $after_cap"
        [ "$b_ok" = 1 ] || no "(A) a NON-cap declaration was rewritten — the patcher is too greedy: $after_plain"
    fi
fi

# ── (B) the corpus-freeze assertion, both directions ────────────────────────────────────────────────
mkdir -p "$TMP/clean/src" "$TMP/dirty/src" "$TMP/dirty/bench/capsweep"
: > "$TMP/clean/src/a.h"; : > "$TMP/dirty/src/a.h"; : > "$TMP/dirty/bench/capsweep/capsweep.py"
if python3 "$GEN" check-corpus --corpus "$TMP/dirty" >/dev/null 2>&1; then
    no "(B) a corpus containing bench/capsweep was ACCEPTED — the self-measurement guard cannot fire"
elif ! python3 "$GEN" check-corpus --corpus "$TMP/clean" >/dev/null 2>&1; then
    no "(B) a clean corpus was REFUSED — the guard rejects everything, so its refusals mean nothing"
else
    ok "(B) corpus guard refuses a corpus holding the harness and accepts one without it"
fi

# ── (C) the document is a function of the committed data ────────────────────────────────────────────
if out="$( cd "$ROOT" && python3 "$GEN" emit --check 2>&1 )"; then
    ok "(C) docs/TUNING.md matches bench/capsweep/*.tsv + src/ — ${out#*: }"
else
    no "(C) docs/TUNING.md is STALE: $out — run: python3 bench/capsweep/capsweep.py emit"
fi

# the control. Without it (C) is a round trip through the artifact it is checking, which is green
# forever. Mutate one measured byte count in a COPY of the data and require the comparison to notice.
mkdir -p "$TMP/data"
cp "$ROOT/bench/capsweep/tunable.tsv" "$TMP/data/"
# probe_bytes is column 6 of sweep.tsv, and +4242 is a delta no real run produced. The `#` provenance
# line passes through untouched, so the copy stays a well-formed record file.
awk -F'\t' -v OFS='\t' '/^#/ { print; next } !d { $6 = $6 + 4242; d = 1 } { print }' \
    "$ROOT/bench/capsweep/sweep.tsv" > "$TMP/data/sweep.tsv"
if cmp -s "$ROOT/bench/capsweep/sweep.tsv" "$TMP/data/sweep.tsv"; then
    no "(C) mutation control: the mutation was a no-op, so the control below proves nothing"
elif ( cd "$ROOT" && python3 "$GEN" emit --check --data "$TMP/data" >/dev/null 2>&1 ); then
    no "(C) mutation control: a changed byte count in sweep.tsv did NOT change the document — (C) is inert"
else
    ok "(C) mutation control: a changed measurement makes --check fail, so the doc IS derived from the data"
fi

# ── (D) the generated document says it is generated ─────────────────────────────────────────────────
if grep -Fq '**Generated — do not edit.**' "$DOC"; then
    ok "(D) docs/TUNING.md declares itself generated"
else
    no "(D) docs/TUNING.md does not carry the 'Generated — do not edit' banner"
fi

# ── (E) the harness refuses to patch production source ──────────────────────────────────────────────
if python3 "$GEN" patch --root "$ROOT" >/dev/null 2>&1; then
    no "(E) the patcher accepted the REPOSITORY as its target — production must keep its constexpr (G3/G5)"
else
    ok "(E) the patcher refuses to rewrite the repository itself"
fi
if [ "$( srcsum )" = "$src_before" ]; then
    ok "(E) src/ is byte-identical to what it was when this gate started"
else
    no "(E) src/ CHANGED while this gate ran — the patcher escaped its scratch tree"
fi

# ── (F) the records are TSV, because a harness must not enter the index it measures ─────────────
# Not a style preference. ripwire indexes `.json` as config keys (src/ingest_crawl.h's extension table);
# `.tsv` is unindexed prose (src/docparse.h, kUnindexedProseExts), which is why corpus.txt beside these
# records never polluted anything. Committed as json, the same numbers changed this repo's own answers
# — the header carries the measurement.
jsonrecords(){ find "$1" -type f -name '*.json' 2>/dev/null | sort; }
stray="$( jsonrecords "$ROOT/bench/capsweep" )"
if [ -n "$stray" ]; then
    # repo-relative: a gate's own failure text lands in a public CI log, and an operator's absolute path
    # is machine layout nobody asked to publish (the same rule capsweep.py's rel() follows).
    no "(F) bench/capsweep holds json record(s), which ripwire INDEXES — the harness is inside the index it measures: $( echo "$stray" | sed "s|^$ROOT/||" | tr '\n' ' ' )"
else
    ok "(F) bench/capsweep holds no .json — the records are TSV, which src/docparse.h leaves unindexed"
fi
# The control, on a SYNTHETIC copy. A scan that can never see a json record is a green line meaning
# nothing; running it against the real tree would drop a probe file into the population other gates read.
mkdir -p "$TMP/synthjson"; : > "$TMP/synthjson/sweep.json"; : > "$TMP/synthjson/keep.tsv"
case "$( jsonrecords "$TMP/synthjson" )" in
    *sweep.json) ok "(F) control: the same scan reports a json record in a synthetic copy, so (F) can go red" ;;
    *)           no "(F) control: the scan did not see a json record in a synthetic copy — (F) is inert" ;;
esac

# ── (G..K) THE HARNESS'S OWN HONESTY, driven through the real screen_core with a stub binary ─────────
# Arms A-F are source-level and none of them ever executes a corpus row, which is exactly how four
# defects shipped inside the phase they were supposed to guard: shlex raising on an unbalanced quote
# (a hard crash of `screen`), a refusal recorded as "0 bytes" and indistinguishable from an answer, a
# 100%-inert run printing a clean 0% and exiting 0, and $RIPWIRE_CAPSWEEP_TMP expanded from os.environ
# instead of the child env so nine rows wrote a 10.4 MB cache blob INTO the frozen corpus.
#
# `run-corpus` runs the production screen_core against a STUB binary, so these arms cost no build.
mkdir -p "$TMP/stub" "$TMP/rc/src"
cat > "$TMP/stub/ripwire" <<'STUBEOF'
#!/bin/sh
# A stand-in for the binary: enough behaviour to exercise every row state the harness must tell apart.
for a in "$@"; do
    case "$a" in
    --stub-ok)      printf '%0100d' 0; exit 0 ;;
    --stub-cap)     if [ -n "${RWCAP_kStubRowCap:-}" ]; then printf '%0400d' 0; else printf '%0100d' 0; fi; exit 0 ;;
    --stub-refuse)  exit 3 ;;
    --stub-tmp=*)   d="${a#--stub-tmp=}"; mkdir -p "$d" 2>/dev/null; : > "$d/wrote-here"; printf 'tmp=%s' "$d"; exit 0 ;;
    --stub-litter)  : > "capsweep-litter.txt"; printf '%050d' 0; exit 0 ;;
    # The two STATE TRANSITIONS the split must not read as byte sensitivity (#127 / 3985249659).
    # --stub-lose: answers 100 B at the DEFAULT and REFUSES when the cap is bumped. base=100, allb=None,
    #   "different" — the raw comparison counted it as cap-sensitive, inflating the numerator with a
    #   regression the bump introduced.
    # --stub-zero: refuses at the DEFAULT and exits 0 with ZERO bytes when bumped. base=None, allb=0,
    #   "different" — counted as "answers only when a cap is bumped", about a row that still answers
    #   nothing; answered() has defined zero bytes as no answer all along.
    --stub-lose)    if [ -n "${RWCAP_kStubRowCap:-}" ]; then exit 3; else printf '%0100d' 0; exit 0; fi ;;
    --stub-zero)    if [ -n "${RWCAP_kStubRowCap:-}" ]; then exit 0; else exit 3; fi ;;
    --stub-edit=*)  printf 'x' > "${a#--stub-edit=}"; printf '%050d' 0; exit 0 ;;
    esac
done
printf 'x'; exit 0
STUBEOF
chmod +x "$TMP/stub/ripwire"
: > "$TMP/rc/src/a.h"
cat > "$TMP/rc/corpus.txt" <<'CORPEOF'
# a synthetic corpus: one row per state the harness has to distinguish
. --stub-ok
. --stub-cap
. --stub-refuse
. --stub-unbalanced="oops
. --stub-tmp=$RIPWIRE_CAPSWEEP_TMP
. --stub-undefined=$RIPWIRE_CAPSWEEP_NO_SUCH_VAR
. --stub-ok --stub-metavar='fn($A, $B, $C)'
. --stub-lose
. --stub-zero
CORPEOF
rc_out="$TMP/rc.out"
# env -u, not `VAR=`: an empty binding is not the operator's normal case, and it used to resolve to the
# process CWD — the run then wrote into the checkout it was launched from.
if env -u RIPWIRE_CAPSWEEP_TMP python3 "$GEN" run-corpus --binary "$TMP/stub/ripwire" --corpus "$TMP/rc" \
        --corpus-file "$TMP/rc/corpus.txt" --bump RWCAP_kStubRowCap=64 \
        --records "$TMP/rc-screen.tsv" > "$rc_out" 2>&1; then
    g_ok=1
else
    g_ok=0
fi
if [ "$g_ok" != 1 ]; then
    no "(G) run-corpus failed on the synthetic corpus: $( tail -3 "$rc_out" | tr '\n' ' ' )"
else
    # (G) the unbalanced-quote row is UNPARSEABLE, and the rows AFTER it still ran. The second half is
    # the F1b control: `except ValueError as e` shadows run_corpus's env dict `e`, and Python deletes an
    # except-name at block end, so the obvious repair kills the NEXT row with UnboundLocalError.
    if grep -q 'unparseable' "$rc_out" && grep -Eq '^EXECUTABILITY.*: 5/9 answered' "$rc_out"; then
        ok "(G) an unbalanced quote is recorded UNPARSEABLE and the rows after it still run"
    else
        no "(G) unparseable row not classified, or the rows after it did not run: $( grep -m1 EXECUTABILITY "$rc_out" )"
    fi
    # (H) a refusal is a state, never a byte count of zero.
    if grep -q 'rc=3' "$TMP/rc-screen.tsv" && \
       awk -F'\t' '/--stub-refuse/ { exit !($1 == "-" && $4 == "rc=3") }' "$TMP/rc-screen.tsv"; then
        ok "(H) a non-zero exit is recorded as rc=3 with NO byte count, not as 0 bytes"
    else
        no "(H) the refusing row was not recorded as a distinct state: $( grep -- '--stub-refuse' "$TMP/rc-screen.tsv" )"
    fi
    # (I) the denominator is the ANSWERING rows, never every row in the file.
    if grep -q 'cap-sensitive: 1 of 5 answering rows' "$rc_out"; then
        ok "(I) the split is reported over the 5 answering rows, not over all 9"
    else
        no "(I) the split was not reported over the answering rows: $( grep -m1 'cap-sensitive' "$rc_out" )"
    fi

    # (I/#127-3985249659) THE SPLIT IS OVER EXECUTION STATES. Two rows in the corpus above change STATE
    # between the arms and neither is byte sensitivity. The numerator must be 1 — the --stub-cap row —
    # and each transition must be named for what it is:
    #   --stub-lose  answered 100 B at the default, refused when bumped  → LOST, never counted
    #   --stub-zero  refused at the default, exit 0 / 0 bytes when bumped → NOT an answer (answered()),
    #                so it is neither cap-sensitive nor a BY-CAP row
    # The pre-change spelling `base.get(c) != allb.get(c)` put --stub-lose in the numerator (cap-sensitive
    # 2 of 5) and --stub-zero in the BY-CAP list.
    if awk -F'\t' '/--stub-lose/ { exit !($3 == "0") }' "$TMP/rc-screen.tsv"; then
        ok "(I) a row that answered at the default and STOPPED when bumped is not marked cap-sensitive"
    else
        no "(I) --stub-lose was marked cap-sensitive — a bump regression counted as byte sensitivity: $( grep -- '--stub-lose' "$TMP/rc-screen.tsv" )"
    fi
    if awk -F'\t' '/--stub-zero/ { exit !($3 == "0") }' "$TMP/rc-screen.tsv"; then
        ok "(I) a row whose bumped arm exits 0 with ZERO bytes is not marked cap-sensitive"
    else
        no "(I) --stub-zero was marked cap-sensitive — zero bytes counted as an answer: $( grep -- '--stub-zero' "$TMP/rc-screen.tsv" )"
    fi
    if grep -Eq '^ +LOST .*--stub-lose' "$rc_out"; then
        ok "(I) the lost row is REPORTED, with both states, rather than silently dropped"
    else
        no "(I) --stub-lose was excluded from the ratio AND from the screen — a change nobody is told about"
    fi
    if grep -Eq '^ +BY-CAP .*--stub-zero' "$rc_out"; then
        no "(I) --stub-zero was listed as BY-CAP — a zero-byte exit 0 is not an answer"
    else
        ok "(I) a zero-byte bumped arm is not reported as a row that 'answers only when a cap is bumped'"
    fi
    if grep -q 'NUMERATOR = rows where BOTH arms answered' "$TMP/rc-screen.tsv"; then
        ok "(I) the records state the state rule the numerator was computed under"
    else
        no "(I) the screen records do not say that the numerator needs BOTH arms to have answered"
    fi
    if grep -q 'split recipe: DENOMINATOR' "$TMP/rc-screen.tsv"; then
        ok "(I) the records carry the recipe the ratio was computed by"
    else
        no "(I) the screen records do not state their denominator — a published ratio with an unstated recipe"
    fi
    # (J) $VARS expand from the environment the harness hands the child, and an UNDEFINED one is refused
    # rather than passed through as a literal path (that literal is what wrote 10.4 MB into the corpus).
    if grep -q 'unexpanded: \$RIPWIRE_CAPSWEEP_NO_SUCH_VAR' "$rc_out"; then
        ok "(J) an undefined variable in the HARNESS's namespace is REFUSED, not run with the literal \$NAME"
    else
        no "(J) an undefined variable was passed through as a literal — the F17 shape"
    fi
    if [ -f "$TMP/corpus-tmp/wrote-here" ] && [ ! -e "$TMP/rc/corpus-tmp" ]; then
        ok "(J) \$RIPWIRE_CAPSWEEP_TMP expanded from the child env, to a path OUTSIDE the corpus"
    else
        no "(J) the corpus-tmp destination was not written outside the corpus: $( grep -m1 stub-tmp "$rc_out" )"
    fi
    # (J) A $NAME OUTSIDE THE HARNESS'S NAMESPACE IS NOT AN ENVIRONMENT REFERENCE. The first cut of the
    # rule above refused `--pattern='rankGraphTeleport($A, $B, $C)'` — a tree-sitter pattern whose $A/$B/$C
    # are METAVARIABLES — as "unexpanded", turning a legitimate corpus row into a non-answer. shlex.split
    # has already dropped the quoting by then, so single-quoted and double-quoted cannot be told apart:
    # naming the namespace is what makes the rule decidable.
    #
    # INSIDE the g_ok branch (CodeRabbit #127 / 3985249719): it reads $TMP/rc-screen.tsv, which only a
    # successful run-corpus writes. Indented as if it belonged here but sitting after the `fi`, it ran on a
    # FAILED run too — awk then failed on a missing file and the gate printed a second, invented "(J) the
    # metavariable row did not answer" for a run that never produced one record.
    if grep -q 'unexpanded: \$A' "$rc_out"; then
        no "(J) a tree-sitter metavariable was refused as an unexpanded environment variable"
    elif awk -F'\t' '/stub-metavar/ { exit !($4 == "ok") }' "$TMP/rc-screen.tsv"; then
        ok "(J) a \$A metavariable outside the RIPWIRE_ namespace is passed through and the row ANSWERS"
    else
        no "(J) the metavariable row did not answer: $( grep -- 'stub-metavar' "$TMP/rc-screen.tsv" )"
    fi
fi

# (J) control — a destination that resolves INSIDE the corpus is refused. `--cache=`, `--export=` and
# `--html=` all take one, and run_corpus runs with cwd=corpus, so this is the surface that put a 10.4 MB
# cache blob in the frozen tree.
if out="$( RIPWIRE_CAPSWEEP_TMP="$TMP/rc/inside" python3 "$GEN" run-corpus --binary "$TMP/stub/ripwire" \
             --corpus "$TMP/rc" --corpus-file "$TMP/rc/corpus.txt" --records "$TMP/rcin.tsv" 2>&1 )"; then
    no "(J) control: a scratch destination INSIDE the corpus was accepted — rows would write into the subject"
else
    case "$out" in
        *'resolves INSIDE the corpus'*) ok "(J) control: a scratch destination inside the corpus is refused" ;;
        *) no "(J) control: the inside-the-corpus run failed for the wrong reason: $( echo "$out" | tail -2 | tr '\n' ' ' )" ;;
    esac
fi

# (I) control — a corpus in which NOTHING answers must refuse, not print a clean 0%.
mkdir -p "$TMP/rcinert/src"; : > "$TMP/rcinert/src/a.h"
cat > "$TMP/rcinert/corpus.txt" <<'CORPEOF'
. --stub-refuse
. --stub-unbalanced="oops
CORPEOF
if out="$( python3 "$GEN" run-corpus --binary "$TMP/stub/ripwire" --corpus "$TMP/rcinert" \
             --corpus-file "$TMP/rcinert/corpus.txt" --records "$TMP/rcinert-screen.tsv" 2>&1 )"; then
    no "(I) control: a corpus where NO row answered still reported a split and exited 0 — green-while-inert"
elif [ -f "$TMP/rcinert-screen.tsv" ]; then
    no "(I) control: the inert run refused but still WROTE records — a record of a measurement that did not happen"
else
    case "$out" in
        *'REFUSING to write records'*) ok "(I) control: a run in which no row answered refuses and writes nothing" ;;
        *) no "(I) control: the inert run failed for the wrong reason: $( echo "$out" | tail -2 | tr '\n' ' ' )" ;;
    esac
fi

# (K) the corpus fingerprint: a file created INSIDE the corpus mid-run aborts the run and names the path.
# assert_corpus_clean guards one hardcoded directory name; this guards the class.
mkdir -p "$TMP/rclitter/src"; : > "$TMP/rclitter/src/a.h"
cat > "$TMP/rclitter/corpus.txt" <<'CORPEOF'
. --stub-ok
. --stub-litter
CORPEOF
if out="$( python3 "$GEN" run-corpus --binary "$TMP/stub/ripwire" --corpus "$TMP/rclitter" \
             --corpus-file "$TMP/rclitter/corpus.txt" --records "$TMP/rclitter-screen.tsv" 2>&1 )"; then
    no "(K) a row that wrote a file into the corpus was measured anyway — the fingerprint cannot fire"
else
    case "$out" in
        *'corpus CHANGED'*capsweep-litter.txt*)
            ok "(K) a file created inside the corpus mid-run aborts the run and names the path" ;;
        *)  no "(K) the litter run failed for the wrong reason: $( echo "$out" | tail -2 | tr '\n' ' ' )" ;;
    esac
fi
# (K2/#127-3985249656) A NAME LIST CANNOT SEE AN OVERWRITE. The fingerprint carries each entry's type and
# content digest, so a row that rewrites an EXISTING corpus file in place — the same shape that put a
# 10.4 MB cache blob in the frozen tree, on its second run — aborts and names the path with `~`. A
# creation (arm K above) was already caught; this is the half the file list was blind to.
mkdir -p "$TMP/rcedit/src"; printf 'original\n' > "$TMP/rcedit/src/a.h"
cat > "$TMP/rcedit/corpus.txt" <<'CORPEOF'
. --stub-ok
. --stub-edit=src/a.h
CORPEOF
if out="$( python3 "$GEN" run-corpus --binary "$TMP/stub/ripwire" --corpus "$TMP/rcedit" \
             --corpus-file "$TMP/rcedit/corpus.txt" --records "$TMP/rcedit-screen.tsv" 2>&1 )"; then
    no "(K2) a row that OVERWROTE a corpus file was measured anyway — the fingerprint is name-only"
else
    case "$out" in
        *'corpus CHANGED'*'~ src/a.h'*)
            ok "(K2) a corpus file overwritten IN PLACE aborts the run and names it as changed, not added" ;;
        *)  no "(K2) the overwrite run failed for the wrong reason: $( echo "$out" | tail -3 | tr '\n' ' ' )" ;;
    esac
fi
# the control: the same corpus with only the non-writing row is measured, so (K2) is not refusing everything
cat > "$TMP/rcedit/corpus.txt" <<'CORPEOF'
. --stub-ok
CORPEOF
printf 'original\n' > "$TMP/rcedit/src/a.h"
if python3 "$GEN" run-corpus --binary "$TMP/stub/ripwire" --corpus "$TMP/rcedit" \
        --corpus-file "$TMP/rcedit/corpus.txt" --records "$TMP/rcedit-screen2.tsv" >/dev/null 2>&1; then
    ok "(K2) control: a corpus whose bytes hold still is measured — the digest is not refusing everything"
else
    no "(K2) control: a corpus that did not change was refused — the content fingerprint is over-firing"
fi

# and the control: the SAME corpus without the littering row must be measured, or (K) refuses everything
cat > "$TMP/rclitter/corpus.txt" <<'CORPEOF'
. --stub-ok
CORPEOF
rm -f "$TMP/rclitter/capsweep-litter.txt"
if python3 "$GEN" run-corpus --binary "$TMP/stub/ripwire" --corpus "$TMP/rclitter" \
        --corpus-file "$TMP/rclitter/corpus.txt" --records "$TMP/rclitter-screen2.tsv" >/dev/null 2>&1; then
    ok "(K) control: a corpus that holds still is measured — the fingerprint is not refusing everything"
else
    no "(K) control: a corpus that did NOT change was refused, so (K)'s refusals mean nothing"
fi

# ── (L) a git repository ABOVE the corpus is refused ────────────────────────────────────────────────
# ripwire walks UP for .git in its own code and honours no ceiling variable, so a frozen corpus inside
# somebody's checkout measures THAT checkout: the 2026-09-10 round recorded `--stray-content=lane/ --plan`
# at 11,670,369 B on a `git archive` corpus, which has no branches at all.
mkdir -p "$TMP/anc/.git" "$TMP/anc/inner/corpus/src"; : > "$TMP/anc/inner/corpus/src/a.h"
if python3 "$GEN" check-corpus --corpus "$TMP/anc/inner/corpus" >/dev/null 2>&1; then
    no "(L) a corpus with a git repository two levels ABOVE it was ACCEPTED — every git verb would measure it"
else
    rm -rf "$TMP/anc/.git"
    if python3 "$GEN" check-corpus --corpus "$TMP/anc/inner/corpus" >/dev/null 2>&1; then
        ok "(L) the ancestor scan refuses a corpus under a git repository and accepts one that is not"
    else
        no "(L) the ancestor scan refused a corpus with no .git above it — it rejects everything"
    fi
fi
# the corpus's OWN .git is the history fixture and must not trip the ancestor scan
mkdir -p "$TMP/anc/inner/corpus/.git"
if python3 "$GEN" check-corpus --corpus "$TMP/anc/inner/corpus" >/dev/null 2>&1; then
    ok "(L) the corpus's own .git — the history fixture — is not mistaken for an ancestor repository"
else
    no "(L) the corpus's own .git was refused; the history fixture could never be planted"
fi

# ── (M) the git history fixture, on a synthetic tree ────────────────────────────────────────────────
# `git archive HEAD` produces a tree with NO .git, so every git-dependent corpus row measures its
# degraded path: --handoff reports changed="0" with no <f> rows, and --cochange/--situ/--map-diff/
# --quality-delta exit 1 with 0 bytes. ~20 rows scored "responds to NO cap" while measuring a refusal.
mkdir -p "$TMP/hist/docs" "$TMP/hist/src"
printf '# doc\n\ncontent\n' > "$TMP/hist/CONTRIBUTING.md"
printf '# doc\n\ncontent\n' > "$TMP/hist/docs/ARCHITECTURE.md"
printf '# doc\n\ncontent\n' > "$TMP/hist/docs/METHODOLOGY.md"
printf '# doc\n\ncontent\n' > "$TMP/hist/docs/EVALS.md"
: > "$TMP/hist/src/a.h"
if python3 "$GEN" plant-history --root "$TMP/hist" > "$TMP/hist.out" 2>&1; then
    commits="$( git -C "$TMP/hist" rev-list --count HEAD 2>/dev/null )"
    dirty="$( git -C "$TMP/hist" diff --name-only 2>/dev/null | wc -l | tr -d ' ' )"
    if [ "$commits" = 3 ] && [ "$dirty" = 4 ]; then
        ok "(M) the history fixture plants 3 commits over the same files and leaves a dirty working tree"
    else
        no "(M) the history fixture planted $commits commit(s) and $dirty dirty file(s) — expected 3 and 4"
    fi
else
    no "(M) plant-history failed: $( tail -3 "$TMP/hist.out" | tr '\n' ' ' )"
fi
# the control: a tree missing the fixture's files must REFUSE rather than plant an empty history, or
# every git row goes back to measuring a refusal with nothing saying so.
mkdir -p "$TMP/histbare/src"; : > "$TMP/histbare/src/a.h"
if python3 "$GEN" plant-history --root "$TMP/histbare" >/dev/null 2>&1; then
    no "(M) control: a tree with none of the fixture's files still planted a history — the fixture is inert"
else
    ok "(M) control: a tree missing the fixture's files is refused, not silently given an empty history"
fi

[ $fail -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

#!/usr/bin/env bash
# pargatescheck.sh — W1-V4 (2026-08-11) gate for test/pargates.py's PER-GATE timeout-budget mechanism.
#
# pargates.py itself is not a *check.sh gate (it's the parallel harness, not a subject under test) so
# nothing in test/regression.sh's own loop ever exercised its logic. That was fine while every gate
# shared one flat 300 s cap — there was no per-gate behaviour to drift — but W1-V4 replaced the flat cap
# with a declared override table (GATE_BUDGET_SEC: gate name -> budget seconds) after cppbenchcheck.sh
# (~856 s) and regexbombcheck.sh (~804 s) were timing out under ASan on a cold cache and being read as
# unhealthy. A table like that CAN drift silently (an entry deleted, a typo in a gate name that makes an
# override a silent no-op, the message format losing the budget number) with nothing catching it. This
# gate is that catch.
#
# Two layers:
#   STATIC  — read test/pargates.py's own source and assert the known-long entries and the default are
#             the declared values, and that the TimeoutExpired message embeds the numeric budget (so a
#             red names its own budget, per the W1-V4 contract).
#   FUNCTIONAL — run the REAL pargates.py logic (not a reimplementation) against a synthetic corpus with
#             one deliberately slow gate, through two throwaway patched copies that only change the
#             NUMBERS (DEFAULT_TIMEOUT_SEC, and one extra GATE_BUDGET_SEC entry) — never the mechanism —
#             so the timeout math and the override lookup are exercised for real, at second-scale instead
#             of the production 300/1200 s values. Proves both that a budget is enforced AND that a
#             per-gate override actually changes the outcome, not just the printed number.
#
# Usage: bash test/pargatescheck.sh   (no ripwire binary needed — this tests test/pargates.py, not the
#                                       binary under test)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
PARGATES="$ROOT/test/pargates.py"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -f "$PARGATES" ] || { echo "no test/pargates.py at $PARGATES"; exit 2; }
command -v python3 >/dev/null || { echo "python3 required"; exit 2; }

echo "pargatescheck: PARGATES=$PARGATES"

# ── STATIC: the declared budget table has the two W1-V4 entries and the honest default ──────────────────
grep -qE '^DEFAULT_TIMEOUT_SEC = 300$' "$PARGATES" \
    && ok "static: DEFAULT_TIMEOUT_SEC is 300 (the flat cap everything NOT overridden still gets)" \
    || no "static: DEFAULT_TIMEOUT_SEC is not the expected 300 — check for an accidental global raise"

grep -qE '"cppbenchcheck\.sh":\s*1200' "$PARGATES" \
    && ok "static: cppbenchcheck.sh has an honest 1200s budget" \
    || no "static: cppbenchcheck.sh missing (or wrong) from GATE_BUDGET_SEC"

grep -qE '"bodydialectcheck\.sh":\s*900' "$PARGATES" \
    && ok "static: bodydialectcheck.sh has an honest 900s budget (T3 body assembly outgrew the flat cap on plain CI builds)" \
    || no "static: bodydialectcheck.sh missing (or wrong) from GATE_BUDGET_SEC"

grep -qE '"regexbombcheck\.sh":\s*1200' "$PARGATES" \
    && ok "static: regexbombcheck.sh has an honest 1200s budget" \
    || no "static: regexbombcheck.sh missing (or wrong) from GATE_BUDGET_SEC"

# the pre-existing six git-HEAD-build gates must survive the refactor from a flat SLOW_TIMEOUT_SEC set to
# the GATE_BUDGET_SEC dict unchanged — a drift guard, not new behaviour.
for g in crossdirincludecheck nestedimportcheck preproccondcheck pyimportprecisecheck rustimportprecisecheck tsimportprecisecheck; do
    grep -qE "\"${g}\.sh\":\s*900" "$PARGATES" \
        && ok "static: ${g}.sh still budgeted at 900s (git-HEAD-build gates unaffected by the refactor)" \
        || no "static: ${g}.sh lost its 900s override in the GATE_BUDGET_SEC refactor"
done

grep -qE '\{limit\}s' "$PARGATES" \
    && ok "static: the TimeoutExpired message embeds the numeric budget (a red names its own budget)" \
    || no "static: the timeout message no longer includes the declared limit — a red would not name its budget"

# ── FUNCTIONAL: exercise the REAL mechanism at second-scale via two throwaway patched copies ─────────────
# Only DEFAULT_TIMEOUT_SEC (and, in the second copy, one extra dict entry) are rewritten — the timeout
# selection, the subprocess call, and the message formatting are byte-identical to the production script.
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
CORPUSROOT="$TMP/corpus"; mkdir -p "$CORPUSROOT/test"
cat > "$CORPUSROOT/test/probequickgate.sh" <<'EOF'
#!/usr/bin/env bash
sleep 4
echo "probequickgate: slept 4s"
exit 0
EOF
chmod +x "$CORPUSROOT/test/probequickgate.sh"
FAKEBIN="$TMP/fakebin"; printf '#!/usr/bin/env bash\ntrue\n' > "$FAKEBIN"; chmod +x "$FAKEBIN"

patchPargates(){    # patchPargates <outfile> <extra-GATE_BUDGET_SEC-entry-or-empty>
    python3 - "$PARGATES" "$1" "$2" <<'PYEOF'
import sys
src, dst, extra = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(src).read()
assert "DEFAULT_TIMEOUT_SEC = 300" in text, "DEFAULT_TIMEOUT_SEC = 300 not found verbatim — static check above should already have failed"
text = text.replace("DEFAULT_TIMEOUT_SEC = 300", "DEFAULT_TIMEOUT_SEC = 2", 1)
if extra:
    marker = "GATE_BUDGET_SEC = {"
    assert marker in text, "GATE_BUDGET_SEC = { not found verbatim"
    text = text.replace(marker, marker + "\n    " + extra, 1)
open(dst, "w").write(text)
PYEOF
}

# Copy A: DEFAULT_TIMEOUT_SEC patched to 2s, no override for probequickgate.sh — it must inherit the
# (patched) default and get killed by it, and the printed message must name that exact 2s budget.
COPYA="$TMP/pargates_a.py"
patchPargates "$COPYA" ""
outA="$( python3 "$COPYA" "$CORPUSROOT" "$FAKEBIN" --only probequickgate 2>&1 )"
rcA=$?
echo "$outA" | grep -q 'TIMEOUT after 2s (declared budget=2s)' \
    && ok "functional: a gate with NO override is killed at the (patched) DEFAULT_TIMEOUT_SEC and the message names 2s" \
    || { no "functional: expected 'TIMEOUT after 2s (declared budget=2s)' in output — got:"; echo "$outA" | sed 's/^/    /'; }
[ "$rcA" -ne 0 ] && ok "functional: pargates.py exits non-zero when a gate times out at its declared budget" \
    || no "functional: pargates.py exited 0 despite a timed-out gate (rc=$rcA)"

# Copy B: SAME DEFAULT_TIMEOUT_SEC=2s patch, PLUS a real GATE_BUDGET_SEC override entry for
# probequickgate.sh at 6s. The gate still sleeps 4s — under the override's 6s, over the default's 2s — so
# this proves the override is actually consulted and actually changes the outcome, not just the number in
# a message nobody acts on.
COPYB="$TMP/pargates_b.py"
patchPargates "$COPYB" '"probequickgate.sh": 6,'
outB="$( python3 "$COPYB" "$CORPUSROOT" "$FAKEBIN" --only probequickgate 2>&1 )"
rcB=$?
echo "$outB" | grep -q 'TIMEOUT' \
    && { no "functional: probequickgate.sh timed out even WITH a 6s override (>4s sleep) — override not honored:"; echo "$outB" | sed 's/^/    /'; } \
    || ok "functional: the SAME 4s-sleeping gate, given a 6s override, does NOT time out — GATE_BUDGET_SEC lookup is honored"
[ "$rcB" -eq 0 ] && ok "functional: pargates.py exits 0 once the override covers the gate's real runtime" \
    || no "functional: pargates.py exited $rcB even though the overridden gate should have passed"

# ── F2 (terminality round A, 2026-09-05): a failing gate's report must NAME the arm that failed ─────────
# The summary used to print a failing gate's last 12 non-blank lines. This repo's gates announce a failure
# where it happens (`  FAIL  arm (X) …`) and then keep running their remaining arms, so those last 12 lines
# are a wall of PASS rows plus a closing `SOME CHECKS FAILED` and the one line a reader needs is gone.
# That is not a hypothesis: V1, V2 and the capture-audit close each recorded the same loss for
# `gitstampcheck`, three rounds running, and the failing arm was never identified. Note that printing FEWER
# trailing lines cannot fix it — the fix is SELECTING the failure-carrying lines, and these arms assert the
# selection, the retained full log, and the tail, over the REAL script (no reimplementation).
#
# The fixture is built to be exactly the shape that used to defeat the report: the needle is line 1 and 41
# lines of noise follow it.
cat > "$CORPUSROOT/test/probefaillinegate.sh" <<'EOF'
#!/usr/bin/env bash
echo "  FAIL  arm (Z) NEEDLE-4f2a the line that names the failing arm"
for i in $( seq 1 40 ); do echo "  PASS  filler arm $i"; done
echo "probefaillinegate: SOME CHECKS FAILED"
exit 1
EOF
chmod +x "$CORPUSROOT/test/probefaillinegate.sh"

grep -qE '^FAIL_TAIL_LINES = 5$' "$PARGATES" \
    && ok "static: FAIL_TAIL_LINES is the declared 5 (the tail a failing gate always shows)" \
    || no "static: FAIL_TAIL_LINES is not the declared 5 — the failing-gate report contract moved"

outC="$( python3 "$PARGATES" "$CORPUSROOT" "$FAKEBIN" --only probefaillinegate 2>&1 )"
rcC=$?
echo "$outC" | grep -q 'NEEDLE-4f2a' \
    && ok "functional: the failing arm's own line survives into the report, 41 noise lines below it" \
    || { no "functional: the FAILING ARM'S LINE IS MISSING from the report — the reader is left with the tail only:"; echo "$outC" | sed -n '/FAILURES/,$p' | sed 's/^/    /'; }
echo "$outC" | grep -qE '^ +L[0-9]+: ' \
    && ok "functional: reported lines carry their transcript line number" \
    || no "functional: the report has no L<n>: line numbers — a reader cannot find the line in the full log"
echo "$outC" | grep -q 'probefaillinegate: SOME CHECKS FAILED' \
    && ok "functional: the transcript's last lines are still shown alongside the failure lines" \
    || no "functional: the report dropped the gate's closing lines"
[ "$rcC" -ne 0 ] && ok "functional: pargates.py still exits non-zero for a failing gate" \
    || no "functional: pargates.py exited 0 for a gate that exited 1 (rc=$rcC)"

# the FULL transcript is kept on disk and the report says where — the summary destroys nothing
fullLog="$( echo "$outC" | sed -n 's/.*full output: \(.*\)$/\1/p' | tail -1 )"
if [ -n "${fullLog:-}" ] && [ -f "$fullLog" ]; then
    logLines="$( wc -l <"$fullLog" | tr -d ' ' )"
    if [ "$logLines" -ge 42 ] && grep -q 'NEEDLE-4f2a' "$fullLog" && grep -q 'filler arm 40' "$fullLog"; then
        ok "functional: the failing gate's FULL output ($logLines lines) is retained at the path the report names"
    else
        no "functional: the retained log at $fullLog is not the full transcript ($logLines lines)"
    fi
else
    no "functional: the report names no readable full-output path (got '${fullLog:-}')"
fi

# a gate KILLED at its budget keeps what it printed before the kill — the TIMEOUT line used to be the
# ENTIRE report, so an arm that had already failed at 30 s was invisible at 300 s.
cat > "$CORPUSROOT/test/probeslowfailgate.sh" <<'EOF'
#!/usr/bin/env bash
echo "  FAIL  arm (Y) NEEDLE-9c17 printed before the budget expired"
sleep 5
EOF
chmod +x "$CORPUSROOT/test/probeslowfailgate.sh"
COPYD="$TMP/pargates_d.py"
patchPargates "$COPYD" ""
outD="$( python3 "$COPYD" "$CORPUSROOT" "$FAKEBIN" --only probeslowfailgate 2>&1 )"
echo "$outD" | grep -q 'TIMEOUT after 2s' && echo "$outD" | grep -q 'NEEDLE-9c17' \
    && ok "functional: a gate killed at its budget still reports what it printed before the kill" \
    || { no "functional: the timeout report lost the gate's own pre-kill output:"; echo "$outD" | sed -n '/FAILURES/,$p' | sed 's/^/    /'; }

# ── THE SHARED-TREE TRIPWIRE (2026-09-09, CI run 34298150602) ───────────────────────────────────────────
# pargates.py samples `git status --porcelain` on the checkout while the suite runs and fails the run when
# a gate leaves a NEW untracked/modified path there, naming the gates in flight. Every stamped verb reads
# that same command, from ANY crawl root inside the checkout, for its at="<sha>+dirty" bit, so a writer
# flips every determinism arm running beside it -- tokenbudgetcheck's `--for` arm got est_tokens 3949
# then 3947 while gateexitcheck's probe copy sat in test/gateexitfix/, and the issue thread blamed a
# third gate. Three functional arms on the REAL script (unpatched), each on its own synthetic corpus:
#   WRITER   a git corpus whose one gate holds an untracked file for 1.5 s -> tree_writes=1, the path and
#            the gate named, rc != 0 -- although the gate itself PASSED. The arm that has been seen red.
#   CONTROL  the same gate writing into its own mktemp instead -> tree_writes=0, rc 0. Mutation control:
#            the only difference between the two corpora is where the file lands.
#   UNWATCHED a corpus that is not a git repository -> the tripwire says so (tree_writes=unwatched), and a
#            git-less run is never turned red by a sampler that cannot see anything.
# The sampler is honest about being a sampler: its report calls the list a floor. 1.5 s against a 0.25 s
# poll is six samples of margin, chosen so the WRITER arm cannot flake on a loaded CI runner.
grep -qE 'PARGATES_DIRT_POLL_SEC", "0\.25"' "$PARGATES" \
    && ok "static: the tree tripwire samples every 0.25 s by default (PARGATES_DIRT_POLL_SEC)" \
    || no "static: PARGATES_DIRT_POLL_SEC default is not 0.25 -- the WRITER arm's 1.5 s margin below assumes it"
grep -qE 'sys\.exit\(1 if fails or dirt_seen else 0\)' "$PARGATES" \
    && ok "static: a tree write fails the run (sys.exit reads dirt_seen)" \
    || no "static: the exit status no longer reads dirt_seen -- a writer would be reported but not fail the run"

mkTreeCorpus(){   # mkTreeCorpus <dir> <where-the-gate-writes: checkout|mktemp> [git]
    local d="$1" where="$2" git="${3:-}"
    mkdir -p "$d/test"
    if [ -n "$git" ]; then
        ( cd "$d" && git init -q . && git config user.email t@t && git config user.name t \
          && printf 'base\n' > README.md && git add README.md && git commit -qm base ) >/dev/null 2>&1 \
          || { no "functional(tree): could not init the synthetic git corpus at $d"; return 1; }
    fi
    if [ "$where" = checkout ]; then
        cat > "$d/test/treeprobecheck.sh" <<'EOF'
#!/usr/bin/env bash
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
printf 'probe\n' > "$ROOT/test/tree.probe.tmp"; sleep 1.5; rm -f "$ROOT/test/tree.probe.tmp"
ok "held an untracked file inside the checkout for 1.5 s, then removed it"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
EOF
    else
        cat > "$d/test/treeprobecheck.sh" <<'EOF'
#!/usr/bin/env bash
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
T="$( mktemp -d )"; trap 'rm -rf "$T"' EXIT
printf 'probe\n' > "$T/tree.probe.tmp"; sleep 1.5
ok "held a file inside its own mktemp for 1.5 s"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
EOF
    fi
    chmod +x "$d/test/treeprobecheck.sh"
}

WRITER="$TMP/treewriter";   mkTreeCorpus "$WRITER"   checkout git
CONTROL="$TMP/treecontrol"; mkTreeCorpus "$CONTROL"  mktemp   git
NOGIT="$TMP/treenogit";     mkTreeCorpus "$NOGIT"    checkout

outW="$( python3 "$PARGATES" "$WRITER" "$FAKEBIN" --only treeprobecheck 2>&1 )"; rcW=$?
printf '%s\n' "$outW" | grep -qE '^gates=1 pass=1 .* tree_writes=1$' \
    && ok "functional(tree): WRITER -- the gate passed, and the run still counts tree_writes=1" \
    || { no "functional(tree): WRITER -- expected 'gates=1 pass=1 ... tree_writes=1', got: $( printf '%s\n' "$outW" | grep -E '^gates=' )"; printf '%s\n' "$outW" | sed 's/^/    /' | head -20; }
printf '%s\n' "$outW" | grep -qE '^\*\*\* +\?\? test/tree\.probe\.tmp .*running then: treeprobecheck\.sh' \
    && ok "functional(tree): WRITER -- the report names the path AND the gate in flight when it was seen" \
    || no "functional(tree): WRITER -- the report does not name '?? test/tree.probe.tmp' with 'running then: treeprobecheck.sh'"
printf '%s\n' "$outW" | grep -q 'a floor, not a total' \
    && ok "functional(tree): WRITER -- the report calls its list a floor (a sampler never claims a total)" \
    || no "functional(tree): WRITER -- the report no longer says the list is a floor"
[ "$rcW" -ne 0 ] \
    && ok "functional(tree): WRITER -- a tree write fails the run (rc=$rcW) even though every gate passed" \
    || no "functional(tree): WRITER -- pargates.py exited 0 with a gate writing into the shared checkout"

outC="$( python3 "$PARGATES" "$CONTROL" "$FAKEBIN" --only treeprobecheck 2>&1 )"; rcC=$?
printf '%s\n' "$outC" | grep -qE '^gates=1 pass=1 .* tree_writes=0$' && [ "$rcC" -eq 0 ] \
    && ok "functional(tree): CONTROL -- the same gate writing into its own mktemp: tree_writes=0, rc 0" \
    || no "functional(tree): CONTROL -- expected tree_writes=0 and rc 0, got rc=$rcC: $( printf '%s\n' "$outC" | grep -E '^gates=' )"
printf '%s\n' "$outC" | grep -q 'WROTE INTO THE SHARED CHECKOUT' \
    && no "functional(tree): CONTROL -- a mktemp write was reported as a tree write (false positive)" \
    || ok "functional(tree): CONTROL -- no tree-write report for a gate that never touched the checkout"

outN="$( python3 "$PARGATES" "$NOGIT" "$FAKEBIN" --only treeprobecheck 2>&1 )"; rcN=$?
printf '%s\n' "$outN" | grep -qE '^gates=1 pass=1 .* tree_writes=unwatched$' && [ "$rcN" -eq 0 ] \
    && ok "functional(tree): UNWATCHED -- a non-git corpus reports tree_writes=unwatched and stays rc 0" \
    || no "functional(tree): UNWATCHED -- expected tree_writes=unwatched and rc 0, got rc=$rcN: $( printf '%s\n' "$outN" | grep -E '^gates=' )"
printf '%s\n' "$outN" | grep -q 'tree tripwire: DISARMED' \
    && ok "functional(tree): UNWATCHED -- the run says the tripwire is disarmed rather than implying a clean tree" \
    || no "functional(tree): UNWATCHED -- no DISARMED disclosure on a corpus git cannot see"

# ── A WRITE THE TRIPWIRE CANNOT SEE: PYTHON'S BYTECODE CACHE (2026-09-10, CI runs 34534320580, 34536435376) ──
# The tripwire reads `git status`, so it sees what git sees and nothing else. A gate that imports a module
# straight out of the checkout makes Python write __pycache__/ beside it -- agentlooplockcheck into
# bench/agentloop/ and bench/locbench/, aiderbytescheck into bench/headtohead/r4-2026-08-06/. That name is
# gitignored, so the run reports tree_writes=0; it is also on the crawl's built-in denylist, so every crawl of
# the live repo counts it (grep's corpus_pruned_dirs= goes 3 -> 4 on a fresh checkout). #118 moved both
# importers into pagingsweepcheck's shard 1/4, and its cold grep (G) pair -- two full re-crawls seconds apart --
# went red twice on main with "paged page NOT deterministic" on a tree clean by every measure the harness had.
# run() now gives every gate PYTHONDONTWRITEBYTECODE=1. Two functional arms on one corpus shape:
#   BYTECODE  the REAL script: a git corpus (__pycache__/ gitignored, as in this repo) whose one gate imports a
#             committed module -> the gate passes, tree_writes=0, rc 0, and no __pycache__ exists afterwards.
#   MUTANT    a copy with ONLY that variable removed from run()'s env -> the same gate leaves __pycache__ behind
#             and the run STILL reports tree_writes=0. That proves the probe really caches bytecode (so BYTECODE
#             is not vacuous on a Python that never does), and it pins the blind spot the variable closes.
grep -qE '^    env = dict\(os\.environ, RIPWIRE_BIN=binp, PYTHONDONTWRITEBYTECODE="1"\)$' "$PARGATES" \
    && ok "static: run() gives every gate PYTHONDONTWRITEBYTECODE=1" \
    || no "static: run() no longer sets PYTHONDONTWRITEBYTECODE=1 -- a gate importing from the checkout leaves a __pycache__/ the crawl counts and git cannot see"

mkPycCorpus(){   # mkPycCorpus <dir>
    local d="$1"
    mkdir -p "$d/test/pyprobe"
    printf '__pycache__/\n' > "$d/.gitignore"
    printf 'VALUE = 1\n' > "$d/test/pyprobe/pycprobemod.py"
    cat > "$d/test/pycprobecheck.sh" <<'EOF'
#!/usr/bin/env bash
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
if python3 - "$ROOT" <<'PY'
import sys
sys.path.insert( 0, sys.argv[1] + "/test/pyprobe" )
import pycprobemod
sys.exit( 0 if pycprobemod.VALUE == 1 else 1 )
PY
then printf '  PASS  %s\n' "imported a committed module out of the checkout"; echo "ALL PASS"; exit 0
else printf '  FAIL  %s\n' "could not import test/pyprobe/pycprobemod.py"; echo "FAILURES ABOVE"; exit 1
fi
EOF
    chmod +x "$d/test/pycprobecheck.sh"
    ( cd "$d" && git init -q . && git config user.email t@t && git config user.name t \
      && git add -A && git commit -qm base ) >/dev/null 2>&1 \
      || { no "functional(bytecode): could not init the synthetic git corpus at $d"; return 1; }
}
pycDirs(){ find "$1" -name __pycache__ -type d 2>/dev/null | wc -l | tr -d ' '; }

PYC="$TMP/pyc";       mkPycCorpus "$PYC"
PYCMUT="$TMP/pycmut"; mkPycCorpus "$PYCMUT"
NOPYC="$TMP/pargates_nopyc.py"
python3 - "$PARGATES" "$NOPYC" 2>/dev/null <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
needle = 'env = dict(os.environ, RIPWIRE_BIN=binp, PYTHONDONTWRITEBYTECODE="1")'
assert needle in text, "run()'s env line not found verbatim -- the static arm above should already have failed"
open(dst, "w").write(text.replace(needle, 'env = dict(os.environ, RIPWIRE_BIN=binp)', 1))
PYEOF

# `env -u`: an outer PYTHONDONTWRITEBYTECODE (a developer's shell, a CI image) would make both arms pass for the
# wrong reason -- the variable under test must come from pargates.py or from nowhere.
outP="$( env -u PYTHONDONTWRITEBYTECODE python3 "$PARGATES" "$PYC" "$FAKEBIN" --only pycprobecheck 2>&1 )"; rcP=$?
printf '%s\n' "$outP" | grep -qE '^gates=1 pass=1 .* tree_writes=0$' && [ "$rcP" -eq 0 ] && [ "$( pycDirs "$PYC" )" = 0 ] \
    && ok "functional(bytecode): BYTECODE -- a gate importing from the checkout passes and leaves no __pycache__ (tree_writes=0, rc 0)" \
    || { no "functional(bytecode): BYTECODE -- expected pass, tree_writes=0, rc 0, 0 __pycache__ dirs; got rc=$rcP, $( pycDirs "$PYC" ) dir(s): $( printf '%s\n' "$outP" | grep -E '^gates=' )"; printf '%s\n' "$outP" | sed 's/^/    /' | head -20; }

if [ ! -s "$NOPYC" ]; then
    no "functional(bytecode): MUTANT -- could not build the mutant: run()'s env line is not verbatim (the static arm above says why)"
else
    outM="$( env -u PYTHONDONTWRITEBYTECODE python3 "$NOPYC" "$PYCMUT" "$FAKEBIN" --only pycprobecheck 2>&1 )"; rcM=$?
    [ "$( pycDirs "$PYCMUT" )" != 0 ] \
        && ok "functional(bytecode): MUTANT -- without the variable the same gate leaves __pycache__ behind (the probe is live)" \
        || no "functional(bytecode): MUTANT -- without the variable the probe still wrote no __pycache__: this Python never caches bytecode, so BYTECODE proves nothing"
    printf '%s\n' "$outM" | grep -qE '^gates=1 pass=1 .* tree_writes=0$' \
        && ok "functional(bytecode): MUTANT -- and the run still reports tree_writes=0: git cannot see this write, only the variable prevents it" \
        || no "functional(bytecode): MUTANT -- expected tree_writes=0 for a gitignored write the tripwire cannot see; got rc=$rcM: $( printf '%s\n' "$outM" | grep -E '^gates=' )"
fi

# ── THE DECLARED BUDGET IS A FLOOR, NOT A CEILING (2026-09-10, CI run 34479806177) ───────────────────────
# GATE_BUDGET_SEC entries were originally exempt from --budget-scale, on the reasoning that each was derived
# from a CI measurement and should stand as declared. Under CI's --budget-scale 4 that inverted the table's
# meaning: the gates it names as HEAVY became the only gates in the job running on LESS time than an unnamed
# one. crossdirincludecheck -- which builds a whole second ripwire from git HEAD -- was killed at 900.1 s in
# a macos-14 shard where xmlwellformed (one map piped through xmllint) was allowed 1200 s and took 585.8 s.
#
# Every arm above checks a declared NUMBER. None compared a declared number against what saying nothing
# would have bought, so nothing in the suite could see the inversion. This section gates the POPULATION
# instead: at the scale ci.yml actually passes, no declared budget may sit below the effective default. Both
# inputs come from their real sources -- the table AND run()'s own prologue lifted out of pargates.py by ast
# (never reimplemented, the same rule the FUNCTIONAL section follows), the scale out of the workflow -- so
# moving --budget-scale re-evaluates the invariant instead of quietly re-opening the hole.
CI_YML="$ROOT/.github/workflows/ci.yml"
FLOORSCAN="$TMP/floorscan.py"
rm -f "$TMP/floorfail"
cat > "$FLOORSCAN" <<'PYEOF'
# floorscan.py PARGATES SCALE -- re-runs pargates.py's OWN budget selection for every declared gate at a
# given --budget-scale. The selection is lifted out of run() by ast, never reimplemented here: a copy of
# the logic would keep passing after the original changed, which is the failure mode this gate exists for.
import ast, io, os, sys

pargates, scale = sys.argv[1], float(sys.argv[2])
tree = ast.parse(io.open(pargates, encoding="utf-8").read())

consts = {}
for n in tree.body:
    if isinstance(n, ast.Assign) and isinstance(n.targets[0], ast.Name) \
       and n.targets[0].id in ("DEFAULT_TIMEOUT_SEC", "GATE_BUDGET_SEC"):
        consts[n.targets[0].id] = ast.literal_eval(n.value)
if set(consts) != {"DEFAULT_TIMEOUT_SEC", "GATE_BUDGET_SEC"}:
    print("ERROR could not read DEFAULT_TIMEOUT_SEC / GATE_BUDGET_SEC as literals"); sys.exit(2)

runfn = next((n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "run"), None)
if runfn is None:
    print("ERROR no def run(g) in pargates.py"); sys.exit(2)
cut = next((i for i, st in enumerate(runfn.body)
            if isinstance(st, ast.Assign) and getattr(st.targets[0], "id", "") == "t0"), None)
if cut is None:
    print("ERROR could not find the t0 = time.time() boundary in run()"); sys.exit(2)
block = ast.unparse(ast.Module(body=runfn.body[:cut], type_ignores=[]))
if "limit" not in block:
    print("ERROR the pre-t0 prologue of run() no longer computes 'limit'"); sys.exit(2)

def limit_for(g):
    ns = dict(consts, budget_scale=scale, g=g, os=os, binp="")
    exec(block, {"max": max, "int": int, "round": round, "dict": dict}, ns)
    return ns["limit"]

undeclared = limit_for("a-gate-that-is-not-in-the-table.sh")
print("SCALED_DEFAULT %d" % undeclared)
print("DECLARED_COUNT %d" % len(consts["GATE_BUDGET_SEC"]))
eff = {}
for g, declared in sorted(consts["GATE_BUDGET_SEC"].items()):
    e = limit_for(g); eff[g] = e
    if e < undeclared:
        print("VIOLATION %s declared=%d effective=%d undeclared_gets=%d" % (g, declared, e, undeclared))
    if e < declared:
        print("LOWERED %s declared=%d effective=%d" % (g, declared, e))
print("MIN_EFFECTIVE %d" % min(eff.values()))
PYEOF

# the scale is whatever the workflow really passes -- not a number retyped into this gate. Kept as a
# newline-separated string, not an array: macOS ships bash 3.2, which has no mapfile, and an empty array
# expanded under `set -u` there is an error rather than nothing.
CI_SCALES="$( grep -oE -- '--budget-scale[[:space:]]+[0-9]+(\.[0-9]+)?' "$CI_YML" \
              | awk '{print $2}' | LC_ALL=C sort -u )"
FIRST_SCALE="$( printf '%s\n' "$CI_SCALES" | head -1 )"
if [ -z "$CI_SCALES" ]; then
    no "floor: .github/workflows/ci.yml passes no --budget-scale -- this gate cannot know what CI gives an undeclared gate"
    FIRST_SCALE=1.0
else
    ok "floor: ci.yml passes --budget-scale $( printf '%s' "$CI_SCALES" | tr '\n' ',' ) (read from the workflow, not retyped here)"
fi

# every scale CI actually uses, plus 1.0 -- the bare regression.sh regime, where a declared entry must
# still come out exactly as declared.
printf '%s\n1.0\n' "$CI_SCALES" | grep -v '^$' | LC_ALL=C sort -u | while IFS= read -r S; do
    scanOut="$( python3 "$FLOORSCAN" "$PARGATES" "$S" 2>&1 )" || {
        printf '  FAIL  floor: could not evaluate run() budget prologue at --budget-scale %s: %s\n' "$S" "$scanOut"
        printf 'x' >> "$TMP/floorfail"; continue; }
    nDeclared="$( printf '%s\n' "$scanOut" | awk '/^DECLARED_COUNT /{print $2}' )"
    scaledDef="$( printf '%s\n' "$scanOut" | awk '/^SCALED_DEFAULT /{print $2}' )"
    violations="$( printf '%s\n' "$scanOut" | grep -c '^VIOLATION ' || true )"
    lowered="$(   printf '%s\n' "$scanOut" | grep -c '^LOWERED '   || true )"

    if [ "$violations" -eq 0 ]; then
        printf '  PASS  floor: at --budget-scale %s all %s declared budgets are >= the %ss an UNDECLARED gate gets\n' "$S" "$nDeclared" "$scaledDef"
    else
        printf '  FAIL  floor: at --budget-scale %s, %s of %s declared gates get LESS than the %ss an undeclared gate gets -- the table is buying them less time than saying nothing would\n' "$S" "$violations" "$nDeclared" "$scaledDef"
        printf '%s\n' "$scanOut" | grep '^VIOLATION ' | sed 's/^/    /'
        printf 'x' >> "$TMP/floorfail"
    fi

    if [ "$lowered" -eq 0 ]; then
        printf '  PASS  floor: at --budget-scale %s no declared budget is reduced below its declared value (a floor never lowers)\n' "$S"
    else
        printf '  FAIL  floor: at --budget-scale %s, %s declared budgets came out BELOW their declared value\n' "$S" "$lowered"
        printf '%s\n' "$scanOut" | grep '^LOWERED ' | sed 's/^/    /'
        printf 'x' >> "$TMP/floorfail"
    fi
done
# that loop is a pipeline, so it ran in a subshell: its verdict travels through the filesystem, not $fail.
if [ -s "$TMP/floorfail" ]; then fail=1; fi

# headbinlib's waiter must still expire with the gate's own assertions able to run. That coupling is stated
# in both files; measuring it against the MINIMUM effective declared budget means raising --budget-scale can
# only widen it, and lowering a declared entry cannot silently close it.
HEADBINLIB="$ROOT/test/lib/headbinlib.sh"
waitBudget="$( grep -oE 'while \[ "\$_t" -lt [0-9]+ \]' "$HEADBINLIB" | grep -oE '[0-9]+' | head -1 )"
minEff="$( python3 "$FLOORSCAN" "$PARGATES" "$FIRST_SCALE" 2>/dev/null | awk '/^MIN_EFFECTIVE /{print $2}' )"
if [ -n "$waitBudget" ] && [ -n "$minEff" ]; then
    [ "$waitBudget" -lt "$minEff" ] \
        && ok "floor: headbinlib.sh waits ${waitBudget}s, strictly under the ${minEff}s smallest effective declared budget (a waiter cannot burn a whole gate budget and be killed as its wait expires)" \
        || no "floor: headbinlib.sh waits ${waitBudget}s against a smallest effective declared budget of ${minEff}s -- the two budgets must not be equal or inverted"
else
    no "floor: could not read headbinlib.sh's wait budget (${waitBudget:-unset}) or the minimum effective budget (${minEff:-unset})"
fi

# MUTATION: the section must be able to go red. The mutation is to the CODE, not the table -- reverting
# run() to the pre-floor form is exactly the regression this section exists to catch, and lowering a TABLE
# entry would no longer prove anything, because the floor repairs one automatically. That is the point.
MUTANT="$TMP/pargates_prefloor.py"
python3 - "$PARGATES" "$MUTANT" <<'PYEOF'
import io, sys
src, dst = sys.argv[1], sys.argv[2]
t = io.open(src, encoding="utf-8").read()
old = "limit = max( declared, scaled_default )"
assert old in t, "the floor expression is not in run() verbatim -- the arms above should already have failed"
io.open(dst, "w", encoding="utf-8").write(t.replace(old, "limit = declared", 1))
PYEOF
mutOut="$( python3 "$FLOORSCAN" "$MUTANT" "$FIRST_SCALE" 2>&1 )"
mutHits="$( printf '%s\n' "$mutOut" | grep -c '^VIOLATION ' || true )"
if [ "$mutHits" -gt 0 ]; then
    ok "floor(mutation): reverting run() to the pre-floor 'limit = declared' is caught ($mutHits violations at --budget-scale $FIRST_SCALE) -- this section is not vacuous"
else
    no "floor(mutation): a pre-floor run() produced NO violation at --budget-scale $FIRST_SCALE -- this whole section is vacuous"
    printf '%s\n' "$mutOut" | sed 's/^/    /' | head -8
fi

# ── A STOPPED GATE IS STOPPED WHOLE: ITS PROCESS GROUP (2026-09-10) ──────────────────────────────────────────────
# A gate's work runs in its children -- ripwire over whole trees, and on the unstaged path headbinlib.sh's parallel
# `cmake --build`. The budget used to be subprocess.run(timeout=), which expires into Popen.kill(): SIGKILL to the gate's
# bash and to nothing else, and SIGKILL runs no trap. Measured the day it was fixed, on a probe gate under a copy of the
# script with a 2 s budget: its background child and the child it waited on inside $( ) were both alive, reparented to
# pid 1, after pargates had printed TIMEOUT -- still running beside the next gates, on a runner whose contention the
# budget table above calls super-linear. pargates.py now starts every gate in a session of its own and stops it by
# signalling that group: TERM, then KILL after KILL_GRACE_SEC. A session of its own also takes the gate out of reach of
# the terminal's Ctrl-C, so pargates forwards SIGINT/SIGTERM/SIGHUP to every running gate the same way.
#
# One probe gate, under copies of the REAL script with only numbers patched (budget, grace), starts five processes in the
# shapes a gate waits in -- a background child, one that ignores TERM and holds the output pipe, one with a grandchild of
# its own, and the $( ) it waits inside -- records every pid, and has an EXIT trap that prints and records. A second, the
# grace probe, leaves exactly one process alive past TERM: a child with its output redirected away whose TERM trap takes
# a second to clean up, so the gate's bash and its output pipe are gone at once while its process group is not. A third,
# the admission probe, records one line 0.3 s into its run.
#   (T) TIMEOUT    killed at a 6 s budget: the TIMEOUT line and the pre-stop output are kept, the gate led its own group,
#                  TERM came first (its EXIT trap ran, and what the trap printed is in the transcript), and after the grace
#                  nothing it started is alive and its process group is empty.
#   (T) GRACE      the grace probe killed at its budget: the grace is the whole group's, not the pipe's -- the cleaning
#                  child finishes. CodeRabbit on #129: the first version KILLed it the moment the gate's bash was reaped.
#   (I) INTERRUPT  a 120 s budget, and pargates itself signalled mid-gate -- Ctrl-C (SIGINT to pargates' process group) and
#                  SIGTERM to its pid: pargates exits 128+signal within 15 s, the trap ran, nothing the gate started survives.
#   (I) ADMISSION  a copy that records its own SIGTERM between run()'s admission check and the spawn -- the window
#                  CodeRabbit named on #129, made deterministic: the gate so admitted is stopped before its first read and
#                  never reaches its 0.3 s mark. No check can close the window itself against an asynchronous signal.
# Controls, each a copy with ONE mutation, each required to show the defect its arm exists for:
#   pre-fix     run_gate() put back to the subprocess.run(timeout=) call it replaced -> processes survive the TIMEOUT
#   TERM only   the stop sends no KILL -> the child ignoring TERM survives
#   KILL only   the stop sends no TERM -> the gate's EXIT trap never runs
#   leader only _stop_group() put back to that first version -> the grace probe's cleaning child is KILLed mid-cleanup
#   read first  run_gate() put back to the loop that read for STOP_POLL_SEC before checking the stop -> the admission
#               probe reaches its 0.3 s mark
#   no handler  pargates installs no signal handler -> after Ctrl-C or SIGTERM the gate's processes are still running
# Liveness is read from the process table with zombies counted as dead (a container's pid 1 may never reap them). The
# harness's own cleanup signals a group only while a recorded member of it is alive, so a reused pid is never hit, and it
# never signals a recorded pid on its own: no probe leaves its group, so the group kill already reached every one.
grep -q 'start_new_session=True' "$PARGATES" \
    && ok "static(group): a gate starts in a session of its own (start_new_session=True)" \
    || no "static(group): no start_new_session=True in pargates.py -- a gate shares pargates' process group and a stop cannot reach its children as one group"
grep -qE '^KILL_GRACE_SEC = 10$' "$PARGATES" \
    && ok "static(group): KILL_GRACE_SEC is the declared 10 s between a stop's TERM and its KILL (the arms below patch it to 3 s)" \
    || no "static(group): KILL_GRACE_SEC is not the declared 10 -- the stop's TERM-to-KILL grace moved"
grep -qE '^STOP_POLL_SEC = 0\.5$' "$PARGATES" \
    && ok "static(group): STOP_POLL_SEC is the declared 0.5 s a running gate takes to notice pargates was signalled" \
    || no "static(group): STOP_POLL_SEC is not the declared 0.5 -- the (I) arms' 15 s bound assumes it"

GROUPPY="$TMP/groupstop.py"
cat > "$GROUPPY" <<'PYEOF'
# groupstop.py PARGATES WORK FAKEBIN -> ROW PASS|FAIL text ...; DONE n
import ast, io, os, re, signal, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor

PARGATES, WORK, FAKEBIN = sys.argv[1], sys.argv[2], sys.argv[3]
LABELS = ("gate", "bg", "noterm", "mid", "grandchild", "fg")
CLEAN_LABELS = ("gate", "cleaner", "fg")
BUDGET_T, BUDGET_I, GRACE = 6, 120, 3
REACH_SEC, FINISH_SEC, STOP_BOUND_SEC, CONTROL_WAIT_SEC, SETTLE_SEC = 20, 30, 15, 8, 3
TIMEOUT_LINE = "TIMEOUT after %ds (declared budget=%ds)" % (BUDGET_T, BUDGET_T)

GATE = r'''#!/usr/bin/env bash
# pargatescheck's process-group probe: every process it starts records "LABEL pid" in pids, then it waits past any budget
D="$( cd "$( dirname "$0" )/.." && pwd )"; P="$D/pids"; C="$D/bin/probechild.sh"
trap 'echo "PROBE-EXIT-TRAP-5e1d the EXIT trap ran"; echo "exittrap $$" >> "$P"' EXIT
echo "gate $$" >> "$P"
echo "PROBE-PRESTOP-7b3c printed before any stop"
sh "$C" bg "$P" &
sh "$C" noterm "$P" &
sh "$C" mid "$P" &
out="$( sh "$C" fg "$P" )"
echo "never reached: $out"
'''

CLEANGATE = r'''#!/usr/bin/env bash
# pargatescheck's grace probe: the one process that outlives TERM writes nowhere near the gate's output and is still
# cleaning up when the gate's bash and its pipe are already gone
D="$( cd "$( dirname "$0" )/.." && pwd )"; P="$D/pids"; C="$D/bin/probechild.sh"
echo "gate $$" >> "$P"
sh "$C" cleaner "$P" >/dev/null 2>&1 &
out="$( sh "$C" fg "$P" )"
echo "never reached: $out"
'''

LATEGATE = r'''#!/usr/bin/env bash
# pargatescheck's admission probe: records "late" 0.3 s into its run, which a gate stopped at its spawn never reaches
D="$( cd "$( dirname "$0" )/.." && pwd )"; P="$D/pids"
echo "gate $$" >> "$P"
sleep 0.3
echo "late $$" >> "$P"
exec sleep 30
'''

CHILD = r'''#!/bin/sh
# probechild.sh LABEL PIDS: records "LABEL pid", then waits the way LABEL says. noterm ignores TERM (and so does the
# sleep it execs) while holding the gate's output pipe; mid waits on a grandchild of its own; cleaner answers TERM with
# a second of cleanup and records "cleaned" when it is done.
label="$1"; pids="$2"
case "$label" in
    noterm)  trap '' TERM ;;
    mid)     sh "$0" grandchild "$pids" & ;;
    cleaner) trap 'sleep 1; echo "cleaned $$" >> "$pids"; exit 0' TERM ;;
esac
echo "$label $$" >> "$pids"
if [ "$label" = mid ]; then wait; exit 0; fi
if [ "$label" = cleaner ]; then while :; do sleep 1; done; fi
exec sleep 30
'''

# the call run_gate() replaced, as it stood in run() before 2026-09-10 -- the control the (T) arm must be able to see
PREFIX = '''def run_gate(argv, env, limit):
    try:
        p = subprocess.run(argv, cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=limit)
        return p.returncode, p.stdout, "exited"
    except subprocess.TimeoutExpired as e:
        return 124, e.stdout or b"", "timeout"
'''

# _stop_group() as #129 first shipped it: its grace ended as soon as the gate's bash was reaped, rather than running
# until the whole process group was empty. Re-spelled 2026-09-11 against the file-backed capture -- the defect is the
# LEADER-ONLY wait, which is what KILLs the grace probe's cleaning child mid-cleanup; the old spelling expressed the
# same wait through p.communicate() only because stdout was still a pipe then.
PREREVIEW = '''def _stop_group(p):
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(p.pid, sig)
        except OSError:
            pass
        _wait_for(p, KILL_GRACE_SEC)
'''
# run_gate() as e442a5d8 had it: the stop was checked only after a STOP_POLL_SEC wait, so a gate admitted as the signal
# was recorded ran that long before anything looked. Re-spelled 2026-09-11 against the file-backed capture; the defect is
# the ORDER of the two checks, not how the output is collected.
READFIRST = '''def run_gate(argv, env, limit):
    deadline = time.monotonic() + limit
    fd, capture = tempfile.mkstemp(prefix="ripwire-pargates-capture-", suffix=".out")
    os.close(fd)
    try:
        with open(capture, "wb") as fh, \
             subprocess.Popen(argv, cwd=root, env=env, stdout=fh, stderr=subprocess.STDOUT,
                              start_new_session=True) as p:
            while True:
                if _wait_for(p, max(0.0, min(STOP_POLL_SEC, deadline - time.monotonic()))):
                    return p.returncode, _capture_read(capture), "exited"
                if stop_signal is not None:
                    _stop_group(p)
                    return 128 + stop_signal, _capture_read(capture), "stopped"
                if time.monotonic() >= deadline:
                    _stop_group(p)
                    return 124, _capture_read(capture), "timeout"
    finally:
        try:
            os.unlink(capture)
        except OSError:
            pass
'''
TEMPLATES = {"prefix": ("run_gate", PREFIX), "prereview": ("_stop_group", PREREVIEW), "readfirst": ("run_gate", READFIRST)}

# the admission race made deterministic: pargates signals itself after run()'s admission check and waits for its own
# handler to record it (bounded), then spawns
INJECT = ('rc, raw, how = run_gate(["bash", os.path.join(testdir, g)], env, limit)',
          'os.kill(os.getpid(), signal.SIGTERM); [time.sleep(0.01) for _ in range(500) if stop_signal is None]; '
          'rc, raw, how = run_gate(["bash", os.path.join(testdir, g)], env, limit)')

MUTATIONS = {
    "termonly":  ("(signal.SIGTERM, signal.SIGKILL)", "(signal.SIGTERM,)"),
    "killonly":  ("(signal.SIGTERM, signal.SIGKILL)", "(signal.SIGKILL,)"),
    "nohandler": ("signal.signal(_sig, _on_stop_signal)", "pass"),
}
SCENARIOS = (
    dict(name="t-fix",             mode="timeout", mutation=None,        gate="probegroupgate"),
    dict(name="t-prefix",          mode="timeout", mutation="prefix",    gate="probegroupgate"),
    dict(name="t-termonly",        mode="timeout", mutation="termonly",  gate="probegroupgate"),
    dict(name="t-killonly",        mode="timeout", mutation="killonly",  gate="probegroupgate"),
    dict(name="t-grace-fix",       mode="timeout", mutation=None,        gate="probecleangate"),
    dict(name="t-grace-prereview", mode="timeout", mutation="prereview", gate="probecleangate"),
    dict(name="i-late-fix",        mode="injected", mutation=None,        gate="probelategate", inject=True),
    dict(name="i-late-readfirst",  mode="injected", mutation="readfirst", gate="probelategate", inject=True),
    dict(name="i-int-fix",         mode="SIGINT",  mutation=None,        gate="probegroupgate"),
    dict(name="i-term-fix",        mode="SIGTERM", mutation=None,        gate="probegroupgate"),
    dict(name="i-int-nohandler",   mode="SIGINT",  mutation="nohandler", gate="probegroupgate"),
    dict(name="i-term-nohandler",  mode="SIGTERM", mutation="nohandler", gate="probegroupgate"),
)
TRACK = []          # (pargates copy, corpus, result) for every copy started: cleanup must reach all of them


def read(path):
    return io.open(path, encoding="utf-8", errors="replace").read()


def tail(text):
    return " | ".join([l for l in text.split("\n") if l.strip()][-3:])


def build(sc):
    text = read(PARGATES)
    budget = BUDGET_T if sc["mode"] == "timeout" else BUDGET_I
    for old, new in (("DEFAULT_TIMEOUT_SEC = 300", "DEFAULT_TIMEOUT_SEC = %d" % budget), ("KILL_GRACE_SEC = 10", "KILL_GRACE_SEC = %d" % GRACE)):
        if text.count(old) != 1:
            raise ValueError("'%s' occurs %d times in pargates.py, not once -- the numbers patch has nothing to patch" % (old, text.count(old)))
        text = text.replace(old, new)
    m = sc["mutation"]
    if m in TEMPLATES:
        name, body = TEMPLATES[m]
        fn = next((n for n in ast.parse(text).body if isinstance(n, ast.FunctionDef) and n.name == name), None)
        if fn is None:
            raise ValueError("pargates.py defines no %s() to put the %s version back into" % (name, m))
        lines = text.split("\n")
        text = "\n".join(lines[:fn.lineno - 1] + body.rstrip("\n").split("\n") + lines[fn.end_lineno:])
    elif m:
        old, new = MUTATIONS[m]
        if text.count(old) != 1:
            raise ValueError("the %s mutation's target '%s' occurs %d times in pargates.py, not once" % (m, old, text.count(old)))
        text = text.replace(old, new)
    if sc.get("inject"):
        if text.count(INJECT[0]) != 1:
            raise ValueError("run()'s run_gate call occurs %d times in pargates.py, not once -- the admission race cannot be injected" % text.count(INJECT[0]))
        text = text.replace(INJECT[0], INJECT[1])
    dst = os.path.join(WORK, sc["name"] + ".pargates.py")
    compile(text, dst, "exec")
    io.open(dst, "w", encoding="utf-8").write(text)
    return dst


def recorded(corpus):
    rec = {}
    path = os.path.join(corpus, "pids")
    for line in (read(path).split("\n") if os.path.isfile(path) else []):
        f = line.split()
        if len(f) == 2 and f[1].isdigit():
            rec.setdefault(f[0], int(f[1]))
    return rec


def procs():
    """pid -> (pgid, state) for every process on the machine."""
    table = {}
    if os.path.isdir("/proc/self"):
        for name in os.listdir("/proc"):
            if name.isdigit():
                try:
                    stat = read("/proc/%s/stat" % name)
                except OSError:
                    continue
                f = stat[stat.rfind(")") + 2:].split()
                if len(f) > 2:
                    table[int(name)] = (int(f[2]), f[0])
        return table
    ps = subprocess.run(["ps", "-A", "-o", "pid=,pgid=,stat="], stdout=subprocess.PIPE, universal_newlines=True).stdout
    for line in ps.split("\n"):
        f = line.split()
        if len(f) >= 3 and f[0].isdigit() and f[1].isdigit():
            table[int(f[0])] = (int(f[1]), f[2])
    return table


def alive(table, pid):
    e = table.get(pid)
    return e is not None and not e[1].startswith("Z")


def cleanup(p, corpus, pgid):
    """SIGKILL whatever a scenario left, never a stranger. The gate's group is signalled only while a recorded member of it
    is alive -- a live member pins the group's id, so it cannot have been reused. No recorded pid is signalled on its own:
    no probe leaves its group, so the group kill has already reached every one of them, and a pid KILLed a moment ago is
    the one kind a reuse could turn into a stranger. The pargates copy's own group is signalled only while the copy is
    unreaped, which pins its pid too."""
    rec = recorded(corpus)
    table = procs()
    if pgid is not None and any(alive(table, pid) and table[pid][0] == pgid for pid in rec.values()):
        try:
            os.killpg(pgid, signal.SIGKILL)
        except OSError:
            pass
    if p is not None:
        if p.returncode is None:
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except OSError:
                pass
        try:
            p.wait(timeout=10)
        except subprocess.TimeoutExpired:
            pass


def run_scenario(sc):
    r = dict(sc, labels={"probecleangate": CLEAN_LABELS, "probelategate": ()}.get(sc["gate"], LABELS), err=None, reached=False, exited=False, rc=None, secs=None, pgid=None, own=False, rec={}, survivors=[], members=[], text="", full="")
    d = os.path.join(WORK, sc["name"])
    corpus = os.path.join(d, "corpus")
    p = None
    try:
        script = build(sc)
        for sub in (os.path.join(corpus, "test"), os.path.join(corpus, "bin"), os.path.join(d, "tmp")):
            os.makedirs(sub)
        for rel, body in (("test/probegroupgate.sh", GATE), ("test/probecleangate.sh", CLEANGATE), ("test/probelategate.sh", LATEGATE),
                          ("bin/probechild.sh", CHILD)):
            io.open(os.path.join(corpus, rel), "w").write(body)
            os.chmod(os.path.join(corpus, rel), 0o755)
        log = os.path.join(d, "pargates.out")
        with open(log, "wb") as fh:
            p = subprocess.Popen([sys.executable, script, corpus, FAKEBIN, "--only", sc["gate"]], stdout=fh, stderr=subprocess.STDOUT,
                                 env=dict(os.environ, TMPDIR=os.path.join(d, "tmp")), start_new_session=True)
        TRACK.append((p, corpus, r))
        t0 = time.time()
        while time.time() - t0 < REACH_SEC and p.poll() is None:
            rec = recorded(corpus)
            if r["pgid"] is None and "gate" in rec:
                try:
                    r["pgid"] = os.getpgid(rec["gate"])
                except OSError:
                    pass
            if all(label in rec for label in r["labels"]):
                r["reached"] = True
                break
            time.sleep(0.05)
        wait, ts = 0, None
        if sc["mode"] == "timeout":
            wait = FINISH_SEC
        elif sc["mode"] == "injected":
            wait = STOP_BOUND_SEC           # the copy signals itself
        elif r["reached"]:
            sig = getattr(signal, sc["mode"])
            ts = time.time()
            if sig == signal.SIGINT:
                os.killpg(p.pid, sig)       # Ctrl-C: the terminal signals pargates' whole foreground group
            else:
                os.kill(p.pid, sig)
            wait = STOP_BOUND_SEC if sc["mutation"] is None else CONTROL_WAIT_SEC
        try:
            r["rc"] = p.wait(timeout=wait)
            r["exited"] = True
            if ts is not None:
                r["secs"] = time.time() - ts
        except subprocess.TimeoutExpired:
            pass
        rec = recorded(corpus)
        r["rec"] = rec
        r["own"] = r["pgid"] is not None and r["pgid"] == rec.get("gate")
        end = time.time() + SETTLE_SEC      # a killed process takes a moment to leave the table
        while True:
            table = procs()
            r["survivors"] = [label for label in (r["labels"] or ("gate",)) if label in rec and alive(table, rec[label])]
            r["members"] = sorted(pid for pid, (pg, st) in table.items() if r["own"] and pg == rec["gate"] and not st.startswith("Z"))
            if (not r["survivors"] and not r["members"]) or time.time() >= end:
                break
            time.sleep(0.1)
        r["text"] = read(log)
        m = re.search(r"full output: (.*)", r["text"])
        if m and os.path.isfile(m.group(1).strip()):
            r["full"] = read(m.group(1).strip())
    except Exception as e:
        r["err"] = "%s: %s" % (type(e).__name__, e)
    finally:
        cleanup(p, corpus, r["pgid"])
    return r


def rows(r):
    labels = r["labels"]
    what = {"timeout": "killed at its %d s budget" % BUDGET_T, "SIGINT": "Ctrl-C to pargates' process group mid-gate",
            "SIGTERM": "SIGTERM to pargates mid-gate",
            "injected": "admitted as pargates' own SIGTERM was recorded (after run()'s admission check, before the spawn)"}[r["mode"]]
    mut = {None: "", "prefix": ", run_gate() put back to the pre-fix subprocess.run(timeout=)", "termonly": ", the stop sending TERM only",
           "killonly": ", the stop sending KILL only", "nohandler": ", no signal handler installed",
           "prereview": ", _stop_group() put back to #129's first version (its grace ends when the gate's bash is reaped)",
           "readfirst": ", run_gate() put back to e442a5d8's loop (the stop checked only after a first wait)"}[r["mutation"]]
    head = "(%s%s) %s %s%s" % ("T" if r["mode"] == "timeout" else "I", "" if r["mutation"] is None else " control",
                              {"probecleangate": "grace probe gate", "probelategate": "admission probe gate"}.get(r["gate"], "probe gate"), what, mut)
    if r["err"]:
        return [("FAIL", "%s: the harness itself failed: %s" % (head, r["err"]))]
    if not r["reached"]:
        return [("FAIL", "%s: the probe never had all %d processes running (recorded: %s) -- nothing was stopped mid-flight, so nothing is proven; last output: %s"
                 % (head, len(labels), " ".join(sorted(r["rec"])) or "none", tail(r["text"])))]
    gone = "none of the %d processes the gate started survives" % len(labels)
    left = "%d of %d alive (%s)" % (len(r["survivors"]), len(labels), ", ".join(r["survivors"]))
    trap = "exittrap" in r["rec"]
    if r["mode"] == "timeout" and not (r["exited"] and TIMEOUT_LINE in r["text"]):
        return [("FAIL", "%s: pargates did not report '%s' within %d s (exited=%s rc=%s): %s" % (head, TIMEOUT_LINE, FINISH_SEC, r["exited"], r["rc"], tail(r["text"])))]
    if r["gate"] == "probelategate":
        late = "late" in r["rec"]
        if r["mutation"] is None:
            want = 128 + signal.SIGTERM
            good = r["exited"] and r["rc"] == want and not late and not r["survivors"]
            return [("PASS" if good else "FAIL",
                     "%s: stopped before its first read -- it never reached its 0.3 s mark (late recorded: %s), pargates exited %s (want %d), "
                     "and the gate's process is %s" % (head, late, r["rc"], want, "gone" if not r["survivors"] else "still alive"))]
        return [("PASS" if late else "FAIL",
                 "%s: the gate ran past its 0.3 s mark before the stop was noticed (late recorded: %s) -- %s"
                 % (head, late, "this arm sees the window it exists for" if late else "the (I) admission arm cannot tell a check before the read from one after it"))]
    if r["gate"] == "probecleangate":
        cleaned = "cleaned" in r["rec"]
        if r["mutation"] is None:
            return [("PASS" if cleaned and not r["survivors"] and not r["members"] else "FAIL",
                     "%s: the child still cleaning up after TERM, its output redirected away, got the group's whole grace -- its cleanup "
                     "finished (%s) after the gate's bash and pipe were gone -- and %s" % (head, cleaned, gone if not r["survivors"] else left))]
        return [("PASS" if not cleaned and not r["survivors"] and not r["members"] else "FAIL",
                 "%s: the cleaning child %s -- %s" % (head, ("was KILLed mid-cleanup and " + (gone if not r["survivors"] else left)) if not cleaned else "still finished its cleanup",
                 "this arm sees the defect it exists for" if not cleaned else "the (T) grace arm cannot tell the group's grace from the pipe's"))]
    if r["mutation"] is None and r["mode"] == "timeout":
        return [
            ("PASS" if r["rc"] != 0 and "PROBE-PRESTOP-7b3c" in r["full"] else "FAIL",
             "%s: '%s', and the line the gate printed before the stop is in its full output (rc=%s)" % (head, TIMEOUT_LINE, r["rc"])),
            ("PASS" if r["own"] else "FAIL",
             "%s: the gate led its own process group (pgid %s, gate pid %s) -- a stop can reach its children as one group" % (head, r["pgid"], r["rec"].get("gate"))),
            ("PASS" if trap and "PROBE-EXIT-TRAP-5e1d" in r["full"] else "FAIL",
             "%s: TERM came first -- the gate's EXIT trap ran (recorded=%s) and what it printed during the stop is in the transcript (%s)"
             % (head, trap, "PROBE-EXIT-TRAP-5e1d" in r["full"])),
            ("PASS" if r["own"] and not r["survivors"] and not r["members"] else "FAIL",
             "%s: after the grace %s, and %s" % (head, gone + " (the one ignoring TERM included)" if not r["survivors"] else left,
             ("its process group is empty" if not r["members"] else "its process group still holds %s" % " ".join(map(str, r["members"])))
             if r["own"] else "its process group is not its own, so nothing can be said about it")),
        ]
    if r["mutation"] is None:
        want = 128 + getattr(signal, r["mode"])
        good = r["exited"] and r["rc"] == want and trap and not r["survivors"] and not r["members"] and ("stopped by " + r["mode"]) in r["text"]
        return [("PASS" if good else "FAIL",
                 "%s: pargates exited %s (want %d) %s s after the signal (bound %d s), said it stopped by %s (%s), the gate's EXIT trap ran (%s), and %s; group members left: %s"
                 % (head, r["rc"], want, "%.1f" % r["secs"] if r["secs"] is not None else "never", STOP_BOUND_SEC, r["mode"],
                    ("stopped by " + r["mode"]) in r["text"], trap, gone if not r["survivors"] else left, " ".join(map(str, r["members"])) or "none"))]
    if r["mutation"] == "prefix":
        return [("PASS" if r["survivors"] else "FAIL",
                 "%s: %s after pargates reported the TIMEOUT -- %s" % (head, left if r["survivors"] else gone,
                 "this section sees the defect it exists for" if r["survivors"] else "the (T) arm cannot tell the fix from its absence"))]
    if r["mutation"] == "termonly":
        return [("PASS" if "noterm" in r["survivors"] else "FAIL",
                 "%s: %s -- %s" % (head, left if r["survivors"] else gone,
                 "the KILL after the grace is what stops a child that ignores TERM" if "noterm" in r["survivors"] else "the probe's TERM-ignoring child proves nothing about the KILL"))]
    if r["mutation"] == "killonly":
        return [("PASS" if not trap else "FAIL",
                 "%s: the gate's EXIT trap %s -- %s" % (head, "never ran" if not trap else "still ran",
                 "TERM first is what lets it clean up" if not trap else "the trap arm cannot tell TERM-first from KILL alone"))]
    return [("PASS" if r["survivors"] else "FAIL",
             "%s: %s %d s after the signal (pargates %s) -- %s" % (head, left if r["survivors"] else gone, CONTROL_WAIT_SEC,
             "exited rc=%s" % r["rc"] if r["exited"] else "still running",
             "without the handler a signal to pargates stops no gate" if r["survivors"] else "the (I) arm cannot tell the handler from its absence"))]


def on_term(signum, _frame):
    raise SystemExit(128 + signum)


signal.signal(signal.SIGTERM, on_term)
signal.signal(signal.SIGINT, signal.default_int_handler)    # a copy must not inherit an ignored SIGINT: its Ctrl-C arm needs a live one
os.makedirs(WORK)
results = []
ex = ThreadPoolExecutor(max_workers=len(SCENARIOS))
try:
    results = list(ex.map(run_scenario, SCENARIOS))
finally:
    for p, corpus, r in list(TRACK):
        cleanup(p, corpus, r["pgid"])
    ex.shutdown(wait=True)
for r in results:
    for verdict, text in rows(r):
        print("ROW %s %s" % (verdict, text))
print("DONE %d" % len(results))
PYEOF

python3 "$GROUPPY" "$PARGATES" "$TMP/groupstop" "$FAKEBIN" >"$TMP/groupstop.out" 2>&1; groupRc=$?
while IFS= read -r line; do
    case "$line" in
        "ROW PASS "*) ok "group: ${line#ROW PASS }" ;;
        "ROW FAIL "*) no "group: ${line#ROW FAIL }" ;;
    esac
done < "$TMP/groupstop.out"
if [ "$groupRc" -ne 0 ] || ! grep -q '^DONE 12$' "$TMP/groupstop.out"; then
    no "group: the harness did not finish all 12 scenarios (rc=$groupRc): $( grep -v '^ROW ' "$TMP/groupstop.out" | tail -6 | tr '\n' '|' )"
fi

# ── (H) A GATE'S STDOUT MUST NOT BE A PIPE ────────────────────────────────────────────────────────────
# The harness half of the fix in test/gateexitcheck.sh arm (G). A gate writes its verdict lines with
# printf; whether that printf SUCCEEDS is a property of whatever the harness hands it as stdout.
#
# A pipe can refuse a write. This harness used to pass stdout=subprocess.PIPE, and the gate's fd 1 was
# then a blocking pipe with a ~16 KiB kernel buffer, read by one Python thread per gate. If that reader
# stalls -- GIL contention at -j 6, or the macOS runner starvation this repo has hit before -- a verbose
# gate fills the buffer and its next printf BLOCKS inside write(2). bash installs its SIGCHLD handler
# without SA_RESTART (set_signal_handler: sa_flags gets SA_RESTART only for sig != SIGCHLD), and a gate
# forks constantly, so that blocked write comes back EINTR. Measured 2026-09-11 on a plain blocking pipe
# with a deliberately stalled reader: 600 arms produced 600 PASS lines AND 21 spurious FAILs, errno
# `Interrupted system call` on all 21. Contention alone was not enough -- 1500 arms with the pipe drained
# one byte at a time produced none -- so it is specifically the BLOCKED write that fails.
#
# A regular file cannot do any of that: a write to it never blocks, so it can never be interrupted, and
# there is no reader whose absence breaks the descriptor. Capturing into one removes the whole errno
# family for every gate at once, verbose or not, whatever the runner is doing.
#
# This arm asserts the property rather than the spelling: run a real gate under the REAL harness and have
# it report what kind of file its own fd 1 is. On the PIPE version it reports fifo and this arm is red --
# that is the red this arm was written from. It also pins that stderr still arrives MERGED into the same
# description, because that ordering is what makes a gate's stderr land beside the FAIL row it explains.
cat > "$CORPUSROOT/test/probestdoutkindgate.sh" <<'EOF'
#!/usr/bin/env bash
# Reports what the harness handed it as stdout, then fails on purpose: pargates prints a gate's
# transcript only when the gate is red, so a passing probe would report nothing at all.
python3 -c 'import os, stat
m = os.fstat( 1 ).st_mode
print( "STDOUT_KIND=" + ( "fifo" if stat.S_ISFIFO( m ) else "regular" if stat.S_ISREG( m ) else "other" ) )
print( "STDERR_SHARES_STDOUT=" + str( os.fstat( 2 ) == os.fstat( 1 ) ).lower() )'
echo "to stderr, in write order" >&2
echo "probestdoutkindgate: SOME CHECKS FAILED"
exit 1
EOF
chmod +x "$CORPUSROOT/test/probestdoutkindgate.sh"

outH="$( python3 "$PARGATES" "$CORPUSROOT" "$FAKEBIN" --only probestdoutkindgate 2>&1 )"
if printf '%s\n' "$outH" | grep -q 'STDOUT_KIND=regular'; then
    ok "stdout: the harness hands a gate a REGULAR FILE — its writes cannot block, so they cannot be interrupted"
else
    no "stdout: a gate's fd 1 is $( printf '%s\n' "$outH" | grep -o 'STDOUT_KIND=[a-z]*' | head -1 )
        — a pipe write can return EINTR/EAGAIN and a gate's printf then reports a failure that never happened"
fi
if printf '%s\n' "$outH" | grep -q 'STDERR_SHARES_STDOUT=true'; then
    ok "stdout: stderr is still the SAME description as stdout — a gate's stderr keeps landing beside the row it explains"
else
    no "stdout: stderr is no longer merged into stdout's description — write-order interleaving is lost"
fi
if printf '%s\n' "$outH" | grep -q 'to stderr, in write order'; then
    ok "stdout: what a gate wrote to stderr still reaches the captured transcript"
else
    no "stdout: the gate's stderr line is missing from the transcript"
fi

[ "$fail" -eq 0 ] && echo "pargatescheck: ALL PASS" || { echo "pargatescheck: SOME CHECKS FAILED"; exit 1; }

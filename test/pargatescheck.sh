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
ok(){ printf '  PASS  %s\n' "$*"; }
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

[ "$fail" -eq 0 ] && echo "pargatescheck: ALL PASS" || { echo "pargatescheck: SOME CHECKS FAILED"; exit 1; }

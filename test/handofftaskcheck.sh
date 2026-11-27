#!/usr/bin/env bash
# handofftaskcheck.sh — gate for `--handoff=TASK` (lane SUBAGENT-PRIMER, 2026-11-27; HANDOFF-TASKCOND, BRIEF-LESSONS 1): the
# continuation packet, then the --brief page for the next session's task.
#
# WHY. A bare --handoff knows the diff, not the task: on a clean tree it names branch/sha and docs, and nothing about where
# the next session's change goes. The --brief page carries exactly those slots (entries by reach, build/test commands quoted
# from manifests, act ranges, where-else, conventions, class-capped). --handoff=TASK prints both, side by side, never spliced
# (editing serialized XML is a bug class, COMPARE_LOOP_LESSONS 11-27 #8), through the one brief pipeline --brief uses (#9).
#
# ARMS (each runs unconditionally; an arm with nothing to compare FAILs, never skips)
#   (T)  twin: the --handoff=TASK stdout is byte-equal to the packet followed by `--brief=TASK` stdout, on a dirty tree (a real
#        <verified> row) and on a clean one; exit 0 both times. The packet is read on the task's index, the one --brief builds,
#        which also records value uses; `--handoff --metrics` is a bare packet on that same index, so it is the reference. (On
#        real repos a lean bare --handoff differs from it only in heuristic doc s=, candidates= and est_tokens=: holdout-4 DEV,
#        2026-11-27.) Its <verified> section is byte-equal to a bare --handoff's as well.
#   (O)  OFF arm: RIPWIRE_HANDOFF_TASK=0 --handoff=TASK is byte-equal to a bare --handoff (stdout and exit code), and a
#        bare --handoff is unchanged by the switch.
#   (B)  --brief-bytes=1024 sizes the brief part: its root says budget="1024", and the whole answer is byte-equal to the
#        bare packet followed by `--brief=TASK --brief-bytes=1024` (that page's own over= discloses a fixed-section overrun).
#   (R)  refusals, exit != 0 and stdout empty: with --for, with --brief, with --pack-task, and an empty --handoff=.
#   (S)  no stderr notice names --for as having won or --handoff as ignored (the dispatch table keeps --for dark for it).
#
# Usage: test/handofftaskcheck.sh [PATH_TO_RIPWIRE]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_HANDOFF_TASK
# No git budget: under host load a 20 s `git diff` budget can end one run's probe and not the next (gitok="0" in one packet only), and
# the twin arms compare packets from separate runs. The budget's own behaviour is gated elsewhere; here it would only add noise.
export RIPWIRE_GIT_WALK_SECONDS=0
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "handofftaskcheck: no ripwire binary at $BIN"; exit 2; }
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
REPO="$TMP/repo"; mkdir -p "$REPO/src" "$REPO/tests"
cat >"$REPO/src/engine.py" <<'SRC'
def engine_run(job):
    return job.step() + 1

def engine_stop(job):
    return job.halt()
SRC
cat >"$REPO/src/scheduler.py" <<'SRC'
from engine import engine_run

def schedule(job):
    return engine_run(job)
SRC
cat >"$REPO/tests/test_engine.py" <<'SRC'
from engine import engine_run

def test_engine_run():
    assert engine_run is not None
SRC
printf '[project]\nname = "fixture"\n[tool.pytest.ini_options]\ntestpaths = ["tests"]\n' >"$REPO/pyproject.toml"
git -C "$REPO" init -q && git -C "$REPO" add . \
    && git -C "$REPO" -c user.name=t -c user.email=t@t commit -qm "engine and scheduler" || { echo "handofftaskcheck: fixture"; exit 2; }
TASK="add an engine_pause beside engine_stop, called from schedule"

run(){ ( cd "$REPO" && "$BIN" . "$@" ); }

echo "(T) twin: --handoff=TASK == --handoff then --brief=TASK"
for state in clean dirty; do
    [ "$state" = dirty ] && printf '\ndef engine_reset(job):\n    return 0\n' >>"$REPO/src/engine.py"
    run --handoff >"$TMP/h.$state" 2>/dev/null; rh=$?
    run --handoff --metrics >"$TMP/hm.$state" 2>/dev/null   # status: a reference packet; the twin cmp below judges it byte for byte
    run --brief="$TASK" >"$TMP/b.$state" 2>/dev/null; rb=$?
    run --handoff="$TASK" >"$TMP/ht.$state" 2>"$TMP/ht.$state.err"; rt=$?
    cat "$TMP/hm.$state" "$TMP/b.$state" >"$TMP/hb.$state"
    if [ "$rh$rb$rt" = 000 ] && [ -s "$TMP/h.$state" ] && grep -q '^<brief ' "$TMP/b.$state" && cmp -s "$TMP/hb.$state" "$TMP/ht.$state"; then
        ok "$state tree: byte-equal ($( wc -c <"$TMP/ht.$state" | tr -d ' ' ) B = packet $( wc -c <"$TMP/hm.$state" | tr -d ' ' ) + brief $( wc -c <"$TMP/b.$state" | tr -d ' ' )), exit 0"
    else
        no "$state tree: rc $rh/$rb/$rt, twin differs ($( cmp "$TMP/hb.$state" "$TMP/ht.$state" 2>&1 | head -1 ))"
    fi
done
ver(){ sed -n 's/.*\(<verified.*<\/verified>\).*/\1/p' "$1"; }
[ -n "$( ver "$TMP/h.dirty" )" ] && [ "$( ver "$TMP/h.dirty" )" = "$( ver "$TMP/ht.dirty" )" ] \
    && ok "the <verified> section equals a bare --handoff's" || no "<verified> differs from a bare --handoff's (or is missing)"
if grep -q 'engine_reset' "$TMP/ht.dirty"; then ok "the dirty packet names the changed symbol"; else no "dirty packet lacks engine_reset"; fi

echo "(O) OFF arm"
( cd "$REPO" && RIPWIRE_HANDOFF_TASK=0 "$BIN" . --handoff="$TASK" >"$TMP/off" 2>/dev/null ); ro=$?
[ "$ro" = 0 ] && cmp -s "$TMP/off" "$TMP/h.dirty" \
    && ok "RIPWIRE_HANDOFF_TASK=0: byte-equal to a bare --handoff" \
    || no "OFF arm: rc $ro, differs from --handoff"
( cd "$REPO" && RIPWIRE_HANDOFF_TASK=0 "$BIN" . --handoff >"$TMP/off2" 2>/dev/null )   # status: a reference packet; the cmp beside it judges it byte for byte
if cmp -s "$TMP/off2" "$TMP/h.dirty"; then ok "a bare --handoff ignores the switch"; else no "the switch changed a bare --handoff"; fi

echo "(B) --brief-bytes sizes the brief part"
run --handoff="$TASK" --brief-bytes=1024 >"$TMP/bb" 2>/dev/null; rbb=$?
run --brief="$TASK" --brief-bytes=1024 >"$TMP/bb.brief" 2>/dev/null   # status: a reference page; the twin cmp beside it judges it byte for byte
cat "$TMP/hm.dirty" "$TMP/bb.brief" | cmp -s - "$TMP/bb" && tw=1 || tw=0
grep -q '^<brief [^>]*budget="1024"' "$TMP/bb" && bud=1 || bud=0
[ "$rbb" = 0 ] && [ "$tw" = 1 ] && [ "$bud" = 1 ] \
    && ok "budget=\"1024\" on the brief part; byte-equal to --handoff then --brief=TASK --brief-bytes=1024" \
    || no "--brief-bytes: rc $rbb twin=$tw budget1024=$bud"

echo "(R) refusals"
nr=0
for extra in "--for=engine" "--brief=other task" "--pack-task" ""; do
    if [ -z "$extra" ]; then run --handoff= >"$TMP/r.out" 2>"$TMP/r.err"; rr=$?; label="--handoff= (empty)"
    else run --handoff="$TASK" "$extra" >"$TMP/r.out" 2>"$TMP/r.err"; rr=$?; label="--handoff=TASK $extra"; fi
    if [ "$rr" != 0 ] && [ ! -s "$TMP/r.out" ]; then nr=$(( nr + 1 )); else no "$label: rc $rr, stdout $( wc -c <"$TMP/r.out" | tr -d ' ' ) B"; fi
done
if [ "$nr" = 4 ]; then ok "four refusals: exit != 0, stdout empty"; else no "refusals $nr of 4"; fi

echo "(S) no dispatch-precedence notice"
if grep -qiE 'ignored|takes precedence' "$TMP/ht.dirty.err"; then no "stderr names a precedence collision: $( grep -iE 'ignored|takes precedence' "$TMP/ht.dirty.err" | head -1 )"
else ok "stderr has no ignored/precedence notice"; fi

[ "$fail" = 0 ] && echo "handofftaskcheck: PASS" || echo "handofftaskcheck: FAIL"
exit "$fail"

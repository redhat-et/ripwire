#!/usr/bin/env bash
# helptaskdeadlinecheck.sh — gate for `--help-task --deadline-ms=N` (issue #594, reported by @WingedGuardian).
#
# The prompt hooks run --help-task under the harness's hard timeout (Claude Code: 8 s). A cold index killed at the
# timeout saved no cache, so every prompt in a fresh worktree timed out forever. --deadline-ms=N answers in time or
# prints the ordinary abstention by N, while a detached child (forked before any thread) finishes the index and writes
# the cache; src/helpdeadline.h holds the design. Arms (red on a binary without the flag: it refuses --deadline-ms):
#   (A)  modifier contract: --deadline-ms without --help-task, =0 and =abc refuse with exit 1
#   (B)  NO REGRESSION: on a small fixture the in-time run's stdout and exit code are byte-identical to the run without
#        the flag, for a recommend, an abstain and a --legend=full task; an in-time run writes no meter row
#   (C)  slow index (the test-only RIPWIRE_TEST_HELPTASK_DELAY_MS knob): exit 0 by N + slack with status="abstain",
#        well-formed XML, a `deferred` cause=overrun row; the child then finishes (status file state=finished rc=0),
#        appends `warm-done` with rc=0 files=1, the root's cache blob exists, and the next call is the plain answer
#   (D)  a second prompt while the deferred child still runs abstains at once (cause=busy), not after its own deadline
#   (E)  two concurrent cold calls: both exit 0 (never 2), both abstain, ONE overrun row, ONE warm-done row (one index)
#   (F)  a child killed mid-index is visible: the next call writes `warm-crashed` and answers like the plain run
#   (G)  a stale `running` record (started long ago) with the lock held is ignored: the call waits for the lock up to
#        its deadline (cause=lock-wait), never takes the busy shortcut
#   (H)  no call in this gate exited 2
#
# TEST KNOB, test-only: RIPWIRE_TEST_HELPTASK_DELAY_MS=N makes the deadline child sleep N ms before the verb runs.
# Each arm runs under its own TMPDIR (the cache dir) and RIPWIRE_HOME (the meter log) inside a private temp tree.
# Usage:  test/helptaskdeadlinecheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/helptaskdeadlinecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "helptaskdeadlinecheck: no ripwire binary at $BIN — build first"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "helptaskdeadlinecheck: xmllint required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "helptaskdeadlinecheck: python3 required"; exit 2; }
echo "helptaskdeadlinecheck: BIN=$BIN"

WORK="$( mktemp -d )"
SLACK_MS=3000          # exit-by-N+slack: the abstention's git facts and process start under a loaded CI runner
saw2=0

now_ms(){ python3 -c 'import time; print(int(time.time() * 1000))'; }
status_file(){ find "$1/ripwire/locks" -name 'ripwire-warm-*.status' 2>/dev/null | head -1; }
# Wait (bounded) for every deadline child under TMPDIR $1 to leave state=running, so nothing outlives the gate.
wait_children(){
    local st i
    st="$( status_file "$1" )"
    [ -n "$st" ] || return 0
    for i in $( seq 1 300 ); do
        grep -q '^state=running' "$st" 2>/dev/null || return 0
        kill -0 "$( sed -n 's/^pid=//p' "$st" )" 2>/dev/null || return 0   # a planted or crashed record names no live child
        sleep 0.2
    done
    return 1
}
cleanup(){
    for d in "$WORK"/env*/tmp; do [ -d "$d" ] && wait_children "$d"; done
    rm -rf "$WORK"
}
trap cleanup EXIT

# a small git fixture: one caller and one callee, so the router has a symbol to resolve
mkdir -p "$WORK/repo"
cat >"$WORK/repo/a.c" <<'EOF'
int parseConfig( int x ) { return x + 1; }
int main( void ) { return parseConfig( 2 ); }
EOF
git -C "$WORK/repo" init -q
git -C "$WORK/repo" add a.c
git -C "$WORK/repo" -c user.email=gate@example.invalid -c user.name=gate commit -qm fixture

# fresh_env NAME: a private cache dir + meter home; exports TMPDIR / RIPWIRE_HOME for the calls that follow
fresh_env(){
    E="$WORK/env-$1"
    mkdir -p "$E/tmp" "$E/home"
    export TMPDIR="$E/tmp" RIPWIRE_HOME="$E/home"
    unset RIPWIRE_ROUTE_METER RIPWIRE_TEST_HELPTASK_DELAY_MS
}
rows(){ grep -c "\"status\":\"$1\"" "$RIPWIRE_HOME/routing.jsonl" 2>/dev/null || true; }
causes(){ grep -c "\"cause\":\"$1\"" "$RIPWIRE_HOME/routing.jsonl" 2>/dev/null || true; }
note_rc(){ [ "$1" = 2 ] && saw2=1; return 0; }
TASK_NAMED="who calls parseConfig"
TASK_RECOMMEND="plan a feature"

# ── (A) modifier contract ─────────────────────────────────────────────────────────────────────────────────────────
fresh_env a
"$BIN" "$WORK/repo" --deadline-ms=500 >"$E/a1.out" 2>"$E/a1.err"; rc=$?; note_rc $rc
if [ "$rc" = 1 ] && grep -q -- '--deadline-ms' "$E/a1.err" && grep -q -- '--help-task' "$E/a1.err"; then
    ok "(A) --deadline-ms without --help-task refuses (exit 1) naming both flags"
else
    no "(A) --deadline-ms alone: exit $rc, stderr: $( head -c 200 "$E/a1.err" )"
fi
for bad in 0 abc 600001; do
    "$BIN" "$WORK/repo" --help-task="$TASK_NAMED" --deadline-ms=$bad >/dev/null 2>"$E/a2.err"; rc=$?; note_rc $rc
    if [ "$rc" = 1 ] && grep -q -- '--deadline-ms' "$E/a2.err"; then
        ok "(A) --deadline-ms=$bad refuses (exit 1)"
    else
        no "(A) --deadline-ms=$bad: exit $rc"
    fi
done

# ── (B) in time = byte-identical ──────────────────────────────────────────────────────────────────────────────────
fresh_env b
"$BIN" "$WORK/repo" --help-task="$TASK_NAMED" >/dev/null 2>&1   # warm the cache; (C) covers the cold path
for spec in "recommend|$TASK_RECOMMEND|" "named|$TASK_NAMED|" "abstain|hello there|" "full|$TASK_RECOMMEND|--legend=full"; do
    name="${spec%%|*}"; rest="${spec#*|}"; task="${rest%%|*}"; extra="${rest#*|}"
    # shellcheck disable=SC2086
    "$BIN" "$WORK/repo" --help-task="$task" $extra >"$E/$name.plain" 2>/dev/null; rcP=$?; note_rc $rcP
    # shellcheck disable=SC2086
    "$BIN" "$WORK/repo" --help-task="$task" $extra --deadline-ms=120000 >"$E/$name.dl" 2>/dev/null; rcD=$?; note_rc $rcD
    if [ "$rcP" = "$rcD" ] && [ -s "$E/$name.plain" ] && cmp -s "$E/$name.plain" "$E/$name.dl"; then
        ok "(B) $name: stdout byte-identical with and without --deadline-ms (exit $rcP, $( wc -c <"$E/$name.plain" | tr -d ' ' ) B)"
    else
        no "(B) $name: plain exit $rcP vs deadline exit $rcD; $( cmp "$E/$name.plain" "$E/$name.dl" 2>&1 | head -1 )"
    fi
done
grep -q 'status="recommend"' "$E/recommend.plain" && ok "(B) the recommend task recommends (the identity covers a real answer)" \
                                                  || no "(B) the recommend task did not recommend: $( head -c 300 "$E/recommend.plain" )"
if [ ! -s "$RIPWIRE_HOME/routing.jsonl" ]; then
    ok "(B) in-time runs wrote no meter row"
else
    no "(B) in-time runs wrote meter rows: $( cat "$RIPWIRE_HOME/routing.jsonl" )"
fi

# ── (C) slow index: abstain by N + slack, the child finishes and the cache appears ────────────────────────────────
fresh_env c
N=1000
t0=$( now_ms )
RIPWIRE_TEST_HELPTASK_DELAY_MS=4000 "$BIN" "$WORK/repo" --help-task="$TASK_NAMED" --deadline-ms=$N >"$E/c.out" 2>"$E/c.err"; rc=$?; note_rc $rc
t1=$( now_ms ); wall=$(( t1 - t0 ))
if [ "$rc" = 0 ] && [ "$wall" -lt $(( N + SLACK_MS )) ] && grep -q '<task-route[^>]* status="abstain"' "$E/c.out"; then
    ok "(C) slow index: exit 0 in ${wall} ms (N=$N, slack $SLACK_MS) with status=\"abstain\""
else
    no "(C) slow index: exit $rc in ${wall} ms; stdout: $( head -c 300 "$E/c.out" )"
fi
xmllint --noout "$E/c.out" 2>/dev/null && ok "(C) the abstention is well-formed XML" || no "(C) the abstention fails xmllint"
[ "$( causes overrun )" = 1 ] && ok "(C) one deferred cause=overrun meter row" || no "(C) overrun rows: $( causes overrun )"
if ! grep -q '"agent":"claude"' "$RIPWIRE_HOME/routing.jsonl" && grep -q '"agent":"ripwire","router":"warm"' "$RIPWIRE_HOME/routing.jsonl"; then
    ok "(C) the rows are agent=ripwire router=warm (never pooled into the agent=claude A/B readout)"
else
    no "(C) row identity wrong: $( head -1 "$RIPWIRE_HOME/routing.jsonl" )"
fi
if grep -q -- "$WORK" "$RIPWIRE_HOME/routing.jsonl" || grep -q 'parseConfig' "$RIPWIRE_HOME/routing.jsonl"; then
    no "(C) a meter row carries the root path or task text"
else
    ok "(C) the meter rows carry neither the root path nor the task text"
fi
st="$( status_file "$TMPDIR" )"
if [ -n "$st" ] && grep -q '^state=running' "$st"; then
    ok "(C) the status file says running while the child indexes"
else
    no "(C) status while running: $( cat "$st" 2>/dev/null | tr '\n' ' ' )"
fi
# (D) belongs here: the child is still running
t0=$( now_ms )
"$BIN" "$WORK/repo" --help-task="$TASK_NAMED" --deadline-ms=60000 >"$E/d.out" 2>/dev/null; rc=$?; note_rc $rc
t1=$( now_ms ); wall=$(( t1 - t0 ))
if [ "$rc" = 0 ] && [ "$wall" -lt "$SLACK_MS" ] && grep -q 'status="abstain"' "$E/d.out" && [ "$( causes busy )" = 1 ]; then
    ok "(D) a second prompt while the child runs abstains at once (${wall} ms of a 60000 ms deadline, cause=busy)"
else
    no "(D) second prompt: exit $rc in ${wall} ms, busy rows $( causes busy )"
fi
if wait_children "$TMPDIR"; then
    ok "(C) the child finished"
else
    no "(C) the child never left state=running"
fi
if grep -q '^state=finished' "$st" && grep -q '^rc=0' "$st" && grep -q '^files=1' "$st"; then
    ok "(C) status file: state=finished rc=0 files=1"
else
    no "(C) status file after: $( tr '\n' ' ' <"$st" )"
fi
if [ "$( rows warm-done )" = 1 ] && grep '"status":"warm-done"' "$RIPWIRE_HOME/routing.jsonl" | grep -q '"rc":0,"files":1'; then
    ok "(C) one warm-done row with rc=0 files=1"
else
    no "(C) warm-done rows: $( grep warm-done "$RIPWIRE_HOME/routing.jsonl" )"
fi
blobs=$( find "$TMPDIR/ripwire" -name 'ripwire-*.bin' -not -path '*/locks/*' 2>/dev/null | wc -l | tr -d ' ' )
[ "$blobs" -ge 1 ] && ok "(C) the child wrote the root's cache ($blobs blob)" || no "(C) no cache blob after the child finished"
"$BIN" "$WORK/repo" --help-task="$TASK_NAMED" >"$E/c.plain" 2>/dev/null
"$BIN" "$WORK/repo" --help-task="$TASK_NAMED" --deadline-ms=120000 >"$E/c.after" 2>/dev/null; rc=$?; note_rc $rc
cmp -s "$E/c.plain" "$E/c.after" && ok "(C) the next call answers in time, byte-identical to the plain run" \
                                 || no "(C) the next call differs from the plain run"

# ── (E) two concurrent cold calls index once ──────────────────────────────────────────────────────────────────────
fresh_env e
for k in 1 2; do
    ( RIPWIRE_TEST_HELPTASK_DELAY_MS=3000 "$BIN" "$WORK/repo" --help-task="$TASK_NAMED" --deadline-ms=800 >"$E/e$k.out" 2>/dev/null
      echo $? >"$E/e$k.rc" ) &
done
wait
rc1=$( cat "$E/e1.rc" ); rc2=$( cat "$E/e2.rc" ); note_rc "$rc1"; note_rc "$rc2"
if [ "$rc1" = 0 ] && [ "$rc2" = 0 ] && grep -q 'status="abstain"' "$E/e1.out" && grep -q 'status="abstain"' "$E/e2.out"; then
    ok "(E) both concurrent cold calls exit 0 with the abstention"
else
    no "(E) concurrent calls: exit $rc1 / $rc2"
fi
[ "$( causes overrun )" = 1 ] && ok "(E) exactly one call started an index (one overrun row)" || no "(E) overrun rows: $( causes overrun )"
wait_children "$TMPDIR" || no "(E) the child never finished"
[ "$( rows warm-done )" = 1 ] && ok "(E) exactly one warm-done row (one index)" || no "(E) warm-done rows: $( rows warm-done )"

# ── (F) a crashed child is visible, and the next call recovers ────────────────────────────────────────────────────
fresh_env f
RIPWIRE_TEST_HELPTASK_DELAY_MS=60000 "$BIN" "$WORK/repo" --help-task="$TASK_NAMED" --deadline-ms=300 >/dev/null 2>&1; note_rc $?
st="$( status_file "$TMPDIR" )"
pid="$( sed -n 's/^pid=//p' "$st" 2>/dev/null )"
if [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null; then
    for i in $( seq 1 50 ); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
    "$BIN" "$WORK/repo" --help-task="$TASK_NAMED" >"$E/f.plain" 2>/dev/null
    "$BIN" "$WORK/repo" --help-task="$TASK_NAMED" --deadline-ms=120000 >"$E/f.out" 2>/dev/null; rc=$?; note_rc $rc
    if [ "$( rows warm-crashed )" = 1 ] && grep -q '^state=finished' "$st" && cmp -s "$E/f.plain" "$E/f.out"; then
        ok "(F) the killed child is recorded (warm-crashed) and the next call answers like the plain run"
    else
        no "(F) after the crash: warm-crashed rows $( rows warm-crashed ), status $( tr '\n' ' ' <"$st" )"
    fi
else
    no "(F) no running child pid to kill (status: $( tr '\n' ' ' <"$st" 2>/dev/null ))"
fi

# ── (G) a stale running record is ignored ─────────────────────────────────────────────────────────────────────────
# One deferred run leaves the lock, status and marker files; then a planted `running` record + a marker naming the same
# pid, with the lock held by a stand-in. A FRESH record takes the busy shortcut (the control); a STALE one does not.
fresh_env g
RIPWIRE_TEST_HELPTASK_DELAY_MS=1000 "$BIN" "$WORK/repo" --help-task="$TASK_NAMED" --deadline-ms=200 >/dev/null 2>&1; note_rc $?
wait_children "$TMPDIR" || no "(G) the setup child never finished"
st="$( status_file "$TMPDIR" )"
lock="$( find "$TMPDIR/ripwire/locks" -name 'ripwire-warm-*.lock' | head -1 )"
marker="$( find "$TMPDIR/ripwire/locks" -name 'ripwire-warm-*.deferred' | head -1 )"
held_call(){   # held_call STARTED OUTNAME DEADLINE -> wall ms in $wall, exit in $rc
    printf 'state=running\npid=999999\nstarted=%s\nrc=-1\nms=-1\nfiles=-1\n' "$1" >"$st"
    printf '999999\n' >"$marker"
    rm -f "$E/held"
    python3 -c 'import fcntl, sys, time; f = open(sys.argv[1], "a"); fcntl.flock(f, fcntl.LOCK_EX); open(sys.argv[2], "w").close(); time.sleep(3)' \
        "$lock" "$E/held" &
    holder=$!
    for i in $( seq 1 50 ); do [ -f "$E/held" ] && break; sleep 0.1; done
    t0=$( now_ms )
    "$BIN" "$WORK/repo" --help-task="$TASK_NAMED" --deadline-ms="$3" >"$E/$2.out" 2>/dev/null; rc=$?; note_rc $rc
    t1=$( now_ms ); wall=$(( t1 - t0 ))
    wait "$holder"
}
if [ -n "$st" ] && [ -n "$lock" ] && [ -n "$marker" ]; then
    held_call "$( date +%s )" gfresh 20000
    if [ "$rc" = 0 ] && [ "$( causes busy )" = 1 ] && [ "$wall" -lt "$SLACK_MS" ]; then
        ok "(G) control: a fresh running record with the lock held takes the busy shortcut (${wall} ms of a 20000 ms deadline)"
    else
        no "(G) control: exit $rc in ${wall} ms, busy rows $( causes busy )"
    fi
    held_call 1 gstale 700
    if [ "$rc" = 0 ] && [ "$wall" -ge 650 ] && [ "$( causes lock-wait )" = 1 ] && [ "$( causes busy )" = 1 ]; then
        ok "(G) a stale running record is ignored: the call waited for the lock (${wall} ms, cause=lock-wait)"
    else
        no "(G) stale record: exit $rc in ${wall} ms, lock-wait $( causes lock-wait ) busy $( causes busy )"
    fi
else
    no "(G) setup: status '$st' lock '$lock' marker '$marker'"
fi

# ── (H) ──────────────────────────────────────────────────────────────────────────────────────────────────────────
[ "$saw2" = 0 ] && ok "(H) no call in this gate exited 2" || no "(H) a call exited 2"

echo
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

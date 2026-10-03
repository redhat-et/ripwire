#!/usr/bin/env bash
# gatebound.sh — run a gate's compiled harness under a wall-clock cap, and take it down with the gate.
#
# Sourced, not executed:   . "$ROOT/scripts/gatebound.sh";   gate_bounded_arm
#                          gate_bounded SECS CMD ARGS...      (stdout and stderr are the caller's, rc is CMD's)
#
# WHY. A harness built under -fsanitize=address can hang on macOS BEFORE main(): the ASan runtime's own init
# re-enters its allocator through dyld (AsanInitFromRtl -> MemoryRangeIsAvailable -> get_dyld_hdr ->
# dyld_shared_cache_iterate_text_swift -> Block_copy -> malloc -> AsanInitFromRtl) and spins on its own
# StaticSpinMutex in sched_yield() -- ~60% CPU, forever, no stack of ours in it. No check inside the harness can
# help, because none of its code has run. The gate that launched it only waited, in the foreground, so when the
# gate was killed (a suite timeout) the harness was re-parented to launchd and kept spinning for hours.
#
# TWO LAYERS, because a gate can be stopped in two ways:
#   1. perl `alarm`, the house idiom (test/bm25check.sh), survives exec: SIGALRM kills the harness SECS after it
#      starts, whatever happens to the gate -- including SIGKILL, which runs no trap.
#   2. The harness runs in the background and the gate `wait`s on it, so a TERM/INT/HUP that reaches the gate is
#      handled at once (a foreground child would defer the trap until it exited) and the EXIT trap kills it.
# RIPWIRE_GATE_HARNESS_CAP_SEC overrides the cap a caller passes (pargatescheck arm I sets it to seconds).

GATE_BOUNDED_PID=""

gate_bounded()   # $1 = default cap in seconds, rest = the command
{
    local cap="${RIPWIRE_GATE_HARNESS_CAP_SEC:-$1}" rc
    shift
    perl -e 'alarm shift; exec @ARGV or exit 127' "$cap" "$@" &
    GATE_BOUNDED_PID=$!
    wait "$GATE_BOUNDED_PID"; rc=$?
    GATE_BOUNDED_PID=""
    return "$rc"
}

gate_bounded_reap()   # kill the harness a stop caught mid-run; safe to call when none is running
{
    if [ -n "$GATE_BOUNDED_PID" ]; then
        kill -KILL "$GATE_BOUNDED_PID" 2>/dev/null
    fi
    return 0
}

# A caller's own EXIT trap must call gate_bounded_reap first; this installs the signal half: a stop becomes an
# `exit`, which runs that EXIT trap.
gate_bounded_arm()
{
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
}

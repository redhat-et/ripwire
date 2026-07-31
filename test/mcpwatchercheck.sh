#!/usr/bin/env bash
# mcpwatchercheck.sh — gate for A3-F4: FsWatcher's `healthy` flag must honor its own contract
# ("true only when kq is open AND every dir fd registered cleanly"). Pre-fix, arm() set healthy=true
# even when a per-dir ::open failed, so the dir-mtime sweep — the ONLY detector of file ADDITIONS —
# was skipped for exactly the dirs the watcher could not see: a permanent new-file blind spot. With
# one fd per dir and no cap, fd exhaustion past RLIMIT_NOFILE makes this the COMMON case past a few
# hundred dirs.
#
# Two scenarios, both on a long-lived --mcp server over a FIFO (mcpstalecheck/mcpreloadcheck pattern):
#
#   A (deterministic pre-fix reproducer) — one UNOPENABLE dir (mode 0333: no read → ::open fails, but
#     w+x → files can still be created inside). Pre-fix: healthy stayed true, the unregistered dir
#     produced no kqueue event, the sweep was skipped, and a file added there was NEVER detected.
#     Post-fix: any registration failure ⇒ unhealthy ⇒ the FULL dir sweep runs on every verb ⇒ the
#     add is detected (the exact pre-Feature-1 degrade path).
#
#   B (fd-pressure regression guard) — MORE dirs than the fd soft limit (ulimit -n), the audited
#     common case. At least one dir registration MUST fail, so post-fix the watcher must degrade to
#     the always-sweep path and a new file in an existing dir must be detected. (Which specific dirs
#     lose their fds is iteration-order-dependent, so only Scenario A is a deterministic PRE-fix
#     reproducer; this scenario pins the POST-fix behavior against regressions.)
#
# Usage:
#   test/mcpwatchercheck.sh
#   RIPWIRE_BIN=asan/ripwire test/mcpwatchercheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# Does NOT edit regression.sh or golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }

echo "mcpwatchercheck: BIN=$BIN"

# ─── helpers (mcpreloadcheck pattern) ─────────────────────────────────────────────────────────────
inner_for_id() {
    grep -E "\"id\":$2[,}]" "$1" | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r: print("__ERROR__:" + r["error"].get("message",""))
else:            print(r["result"]["content"][0]["text"])
'
}
stamp_for_id() {
    grep -E "\"id\":$2[,}]" "$1" | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin); print(r.get("result",{}).get("_index",""))
'
}
wait_for_id() {
    local i
    for i in $( seq 1 200 ); do
        grep -Eq "\"id\":$2[,}]" "$1" 2>/dev/null && return 0
        sleep 0.05
    done
    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== Scenario A: one unopenable dir (mode 0333) — new file there MUST still be detected ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
if [ "$( id -u )" = "0" ]; then
    echo "  (running as root — mode 0333 does not block open(); skipping scenario A)"
else
    WORK="$TMP/worka"
    mkdir -p "$WORK/alpha" "$WORK/blind"
    printf 'def alpha_probe():\n    return 1\n' >"$WORK/alpha/a.py"
    chmod 0333 "$WORK/blind"          # no read → watcher ::open fails; w+x → creating files inside still works

    FIFO="$WORK/in.fifo"; mkfifo "$FIFO"
    "$BIN" --mcp <"$FIFO" >"$WORK/out.txt" 2>/dev/null &
    SRV=$!
    exec 9>"$FIFO"

    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' >&9
    # warm the index (arms the watcher; blind/ fails to register) and probe the not-yet-existing symbol.
    printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$WORK\",\"symbol\":\"zzz_watcher_probe\"}}}" >&9
    wait_for_id "$WORK/out.txt" 2 || no "scenario A: server never answered the warm-up probe (id=2)"
    case "$( inner_for_id "$WORK/out.txt" 2 )" in
        __ERROR__*) ok "scenario A warm-up: 'zzz_watcher_probe' correctly absent before the add";;
        *)          no "scenario A warm-up: probe unexpectedly found before the add";;
    esac
    STAMP_BEFORE="$( stamp_for_id "$WORK/out.txt" 2 )"

    # the ADD the pre-fix server permanently missed: restore perms, create a new file in the blind dir.
    chmod 0755 "$WORK/blind"
    printf 'def zzz_watcher_probe():\n    return 42\n' >"$WORK/blind/new.py"

    printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$WORK\",\"symbol\":\"zzz_watcher_probe\"}}}" >&9
    wait_for_id "$WORK/out.txt" 3 || no "scenario A: server never answered the post-add probe (id=3)"
    case "$( inner_for_id "$WORK/out.txt" 3 )" in
        __ERROR__*) no "scenario A: new file in the unwatchable dir NOT detected (the A3-F4 blind spot)";;
        "")         no "scenario A: post-add probe returned empty text";;
        *)          ok "scenario A: new file in the unwatchable dir detected — degraded watcher fell back to the full sweep";;
    esac
    STAMP_AFTER="$( stamp_for_id "$WORK/out.txt" 3 )"
    [ -n "$STAMP_AFTER" ] && [ "$STAMP_BEFORE" != "$STAMP_AFTER" ] \
        && ok "scenario A: _index stamp moved (a real rebuild happened)" \
        || no "scenario A: _index stamp did not move (no rebuild — answered from the stale warm index)"

    exec 9>&-
    kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== Scenario B: more dirs than the fd limit — degrade to always-sweep, adds still detected ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
WORKB="$TMP/workb"
mkdir -p "$WORKB"
# 400 dirs (+ root = 401 watch candidates) against a 128-fd soft limit: at least one dir registration
# MUST fail, whatever the iteration order — post-fix the watcher must therefore report unhealthy and
# every verb must run the full dir sweep.
for i in $( seq -w 0 399 ); do
    mkdir "$WORKB/d$i"
    printf 'def fn_%s():\n    return %s\n' "$i" "$i" >"$WORKB/d$i/f.py"
done

FIFOB="$WORKB/in.fifo"; mkfifo "$FIFOB"
( ulimit -n 128; exec "$BIN" --mcp ) <"$FIFOB" >"$WORKB/out.txt" 2>/dev/null &
SRVB=$!
exec 8>"$FIFOB"

printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' >&8
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$WORKB\",\"symbol\":\"zzz_pressure_probe\"}}}" >&8
wait_for_id "$WORKB/out.txt" 2 || no "scenario B: server never answered the warm-up probe (id=2) — fd limit too tight for normal operation?"
case "$( inner_for_id "$WORKB/out.txt" 2 )" in
    __ERROR__*) ok "scenario B warm-up: 'zzz_pressure_probe' correctly absent before the add";;
    *)          no "scenario B warm-up: probe unexpectedly found before the add";;
esac

# add a NEW file to an EXISTING dir (an add in a fresh dir would bump the always-watched root and be
# caught even by a broken watcher — the blind spot is precisely adds inside existing, unwatched dirs).
printf 'def zzz_pressure_probe():\n    return 7\n' >"$WORKB/d377/new.py"

printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$WORKB\",\"symbol\":\"zzz_pressure_probe\"}}}" >&8
wait_for_id "$WORKB/out.txt" 3 || no "scenario B: server never answered the post-add probe (id=3)"
case "$( inner_for_id "$WORKB/out.txt" 3 )" in
    __ERROR__*) no "scenario B: new file NOT detected under fd pressure (watcher claimed health it does not have)";;
    "")         no "scenario B: post-add probe returned empty text";;
    *)          ok "scenario B: new file detected under fd pressure (degraded watcher → full sweep)";;
esac

exec 8>&-
kill "$SRVB" 2>/dev/null; wait "$SRVB" 2>/dev/null

# ─── Summary ──────────────────────────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi

# headbinlib.sh — shared, sha-keyed cache of a ripwire binary built from git HEAD. SOURCED, not run.
#
# Four monotonicity gates (crossdirincludecheck, pyimportprecisecheck, rustimportprecisecheck,
# tsimportprecisecheck) each need a PRE-CHANGE comparison binary built from HEAD. Each used to
# configure+build one from scratch on every run (~50 s apiece, ~200 s of the suite's tail for four
# copies of the same binary). The binary is a pure function of (HEAD sha, -DRIPWIRE_NATIVE=ON) — the
# committed goldens are machine-independent, so its output is too — therefore ONE build per sha
# serves every gate and every rerun until HEAD moves.
#
# Usage (inside a gate, after its own git/cmake presence checks):
#     . "$ROOT/test/lib/headbinlib.sh"
#     OLDBIN="$( ripwire_head_binary "$ROOT" "$TMP" )" || { skip "…: pre-change build failed"; return; }
#
# Contract:
#   - prints the path of an executable ripwire built from HEAD with -DRIPWIRE_NATIVE=ON; exit 0.
#   - exit non-zero (nothing printed) when HEAD can't be resolved or the build fails — callers keep
#     their existing skip path, so failure behavior is unchanged from the pre-cache gates.
#   - concurrency-safe: parallel gates (test/pargates.py) elect ONE builder via an atomic mkdir lock;
#     the rest wait for the winner's binary. A waiter that times out (stale lock from a killed
#     builder) builds PRIVATELY into the caller's $2 — uncached, but the gate still proves what it
#     always proved. NEVER a silent skip because of lock contention.
#   - sets NO traps (gates own their EXIT trap) and cleans its own worktree/build dirs inline.
#   - the cache lives under the per-user temp dir; a reboot or tmp-clean just costs one rebuild.
#     Stale shas are left for the OS tmp cleaner — another session on a different branch may be
#     using its own sha's binary concurrently, so pruning siblings here would be a race.

# ripwire_head_binary ROOT FALLBACK_DIR  →  stdout: path to the HEAD binary
ripwire_head_binary()
{
    local _root="$1" _fb="$2" _sha _dir _bin _lock _t
    _sha="$( cd "$_root" && git rev-parse --verify HEAD 2>/dev/null )" || return 1
    _dir="${TMPDIR:-/tmp}/ripwire-headbin-$( id -u )/$_sha"
    _bin="$_dir/ripwire"
    [ -x "$_bin" ] && { printf '%s\n' "$_bin"; return 0; }

    _lock="$_dir.lock"
    mkdir -p "${_dir%/*}" 2>/dev/null
    if mkdir "$_lock" 2>/dev/null; then
        # we are the elected builder — build in a private dir, install atomically, release the lock.
        if [ -x "$_bin" ]; then rmdir "$_lock" 2>/dev/null; printf '%s\n' "$_bin"; return 0; fi
        mkdir -p "$_dir"
        if _headbin_build "$_root" "$_sha" "$_lock/work" "$_dir/.ripwire.$$"; then
            mv -f "$_dir/.ripwire.$$" "$_bin"
            rm -rf "$_lock"
            printf '%s\n' "$_bin"; return 0
        fi
        rm -rf "$_lock"
        return 1
    fi

    # another process holds the lock — wait for its binary (build is ~50 s on the dev machine).
    #
    # THE WAIT BUDGET MUST STAY STRICTLY UNDER test/pargates.py's PER-GATE TIMEOUT, with room left over for
    # the gate's own assertions after the wait returns. It used to be 300 s, which was EXACTLY pargates'
    # timeout — so on a runner where the build is slow, a waiter could not possibly finish: it burned the
    # whole gate budget waiting and was killed at the same instant its wait expired. That is what reddened
    # crossdirincludecheck on all four Linux legs of CI run 31182301976 (rc=124 at 300.1 s) while macOS,
    # where the build fits in ~60 s, stayed green. Two coupled budgets that must not be equal.
    #
    # 240 s here against pargates' 900 s for the six head-binary gates (its `slow` set) leaves 660 s of
    # headroom. If either number moves, move it with the other one: pargates.py's `slow` comment names this
    # file, and this comment names pargates.py, so neither can drift alone unnoticed.
    _t=0
    while [ "$_t" -lt 240 ]; do
        [ -x "$_bin" ] && { printf '%s\n' "$_bin"; return 0; }
        [ -d "$_lock" ] || break            # builder finished (or failed) — stop waiting either way
        sleep 2; _t=$(( _t + 2 ))
    done
    [ -x "$_bin" ] && { printf '%s\n' "$_bin"; return 0; }
    # stale lock or failed builder: build privately into the caller's tmp (cleaned by ITS trap).
    _headbin_build "$_root" "$_sha" "$_fb/headbin.wt" "$_fb/headbin.ripwire" || return 1
    printf '%s\n' "$_fb/headbin.ripwire"
}

# _headbin_build ROOT SHA WORKDIR OUT  →  builds HEAD into a throwaway worktree, copies the binary to OUT
_headbin_build()
{
    local _root="$1" _sha="$2" _work="$3" _out="$4" _wt _bld _rc=1
    _wt="$_work/head"; _bld="$_work/build"
    mkdir -p "$_work" || return 1
    if ( cd "$_root" && git worktree add -q --detach "$_wt" "$_sha" ) 2>/dev/null; then
        if cmake -S "$_wt" -B "$_bld" -DRIPWIRE_NATIVE=ON >/dev/null 2>&1 \
           && cmake --build "$_bld" -j >/dev/null 2>&1 \
           && [ -x "$_bld/ripwire" ]; then
            cp "$_bld/ripwire" "$_out" && chmod +x "$_out" && _rc=0
        fi
        ( cd "$_root" && git worktree remove --force "$_wt" ) >/dev/null 2>&1
    fi
    rm -rf "$_work" 2>/dev/null
    return $_rc
}

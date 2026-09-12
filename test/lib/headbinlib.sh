# headbinlib.sh — shared, sha-keyed cache of a ripwire binary built from git HEAD. SOURCED, not run.
#
# Six monotonicity gates (crossdirincludecheck, nestedimportcheck, preproccondcheck, pyimportprecisecheck,
# rustimportprecisecheck, tsimportprecisecheck) each need a PRE-CHANGE comparison binary built from HEAD, and
# binoverridecheck re-runs all six. Each used to configure+build one from scratch on every run (~50 s apiece on the
# dev machine). The binary is a pure function of (HEAD sha, -DRIPWIRE_NATIVE=ON) — the committed goldens are
# machine-independent, so its output is too — therefore ONE build per sha serves every gate and every rerun until
# HEAD moves.
#
# Usage (inside a gate, after its own git/cmake presence checks):
#     . "$ROOT/test/lib/headbinlib.sh"
#     OLDBIN="$( ripwire_head_binary "$ROOT" "$TMP" )" || { headbin_refusal $? "monotonicity"; return; }
#
# TWO MODES, chosen by whether RIPWIRE_HEADBIN is set at all.
#
# STAGED (RIPWIRE_HEADBIN set — CI). The binary was built BEFORE the suite, in its own workflow step
# (.github/workflows/ci.yml, "Stage the HEAD comparison binary"), and RIPWIRE_HEADBIN names it. This mode never builds
# and never waits. It returns that path only if the file is executable and its --version says built_from=<a prefix of
# HEAD's sha> without +dirty; anything else prints one `headbinlib:` line on stderr and returns 3, which
# headbin_refusal turns into a FAIL.
#   Why the build had to leave the gates: under test/pargates.py it ran inside whichever head-binary gate started
#   first — inside a wall-clock budget, beside -j 3 neighbours — and a parallel cmake build degrades super-linearly
#   under contention. On macos-14 Release shard 2/2 the xmlwellformed runner-speed probe moved 4.6x across five draws
#   while crossdirincludecheck moved more than 15x, and it was killed at 900 s and then at 1200 s with the budget floor
#   already applied (run 34495265793). No budget survives the next slow draw. A quiet fallback to building here would
#   put that defect back where nobody sees it, so a broken staging pipeline fails the gate that asked for the binary.
#
# UNSTAGED (RIPWIRE_HEADBIN unset — a developer's test/regression.sh or local pargates.py run). Unchanged:
#   - prints the path of an executable ripwire built from HEAD with -DRIPWIRE_NATIVE=ON; exit 0.
#   - exit 1 (nothing printed) when HEAD can't be resolved or the build fails — headbin_refusal keeps the historic
#     skip for that, so failure behavior is unchanged from the pre-cache gates.
#   - concurrency-safe: parallel gates (test/pargates.py) elect ONE builder via an atomic mkdir lock; the rest wait
#     for the winner's binary. A waiter that times out (stale lock from a killed builder) builds PRIVATELY into the
#     caller's $2 — uncached, but the gate still proves what it always proved. NEVER a silent skip because of lock
#     contention.
#   - the cache lives under the per-user temp dir; a reboot or tmp-clean just costs one rebuild. Stale shas are left
#     for the OS tmp cleaner — another session on a different branch may be using its own sha's binary concurrently,
#     so pruning siblings here would be a race.
#   - RIPWIRE_HEADBIN_BUILD_LOG, when set, receives the checkout and cmake output that otherwise goes to /dev/null
#     (CI's staging step prints it when that build fails).
#
# Both modes set NO traps (gates own their EXIT trap) and clean up their own checkout/build dirs inline.
# test/headbinstagecheck.sh gates both modes, every caller's use of headbin_refusal, and CI's staging step.
#
# CHECKING OUT A COMMIT. ripwire_private_checkout is the one way a gate checks out a commit of the repository under
# test: the monotonicity gates' held-constant input tree, _headbin_build's build tree, qdrefpaircheck's wave commit. It
# is a `git clone --shared`, never `git worktree add`. A worktree is registered in the repository's .git/worktrees,
# which every session on the machine shares, and a caller killed before its cleanup leaves that registration behind:
# no trap sees SIGKILL (test/pargates.py's whole budget until 2026-09-10, and still its last resort after a TERM and a
# grace), and macOS bash 3.2 skips its EXIT trap on Ctrl-C. Twenty such leftovers were found on 2026-09-10. The clone
# writes nothing into the source repository, so a killed caller —
# a builder killed mid-cmake included — leaves only a directory under its temp dir. test/worktreeleakcheck.sh kills
# every caller mid-flight and asserts the repository's .git/worktrees stays empty.

# ripwire_head_binary ROOT FALLBACK_DIR  →  stdout: path to the HEAD binary
ripwire_head_binary()
{
    local _root="$1" _fb="$2" _sha _dir _bin _lock _t
    _sha="$( cd "$_root" && git rev-parse --verify HEAD 2>/dev/null )" || return 1
    [ -n "${RIPWIRE_HEADBIN+set}" ] && { _headbin_staged "$_sha"; return $?; }      # STAGED: never build, never wait
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
    #
    # Since 2026-09-10 pargates spends max(declared, DEFAULT x --budget-scale) on a declared gate, so the
    # headroom can only GROW from 660 s under CI's scale -- it never shrinks. The invariant to preserve is
    # still the strict inequality, not the arithmetic difference: this wait must expire with the gate's own
    # assertions still able to run, so raise this number only alongside the 900 s it is measured against.
    # STAGED mode never reaches this loop, which is why CI no longer depends on the coupling at all; it still
    # protects the unstaged path, where a developer's parallel run elects one builder and the rest wait here.
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

# _headbin_staged SHA  →  stdout: $RIPWIRE_HEADBIN when it names a binary built from SHA; otherwise exit 3
_headbin_staged()
{
    ripwire_headbin_verify "$RIPWIRE_HEADBIN" "$1" || return 3
    printf '%s\n' "$RIPWIRE_HEADBIN"
}

# ripwire_headbin_verify BIN SHA  →  exit 0 when BIN is an executable ripwire whose --version says it was built from
# SHA on a clean tree; otherwise one `headbinlib:` line on stderr naming what is wrong, and exit 3. The stamp is
# cmake/version_stamp.cmake's `git rev-parse --short=9 HEAD` (git lengthens it when 9 would be ambiguous), so it must
# be a prefix of SHA, at least 7 long. CI's staging step calls this too, so a wrong binary fails there, before any gate.
ripwire_headbin_verify()
{
    local _b="$1" _sha="$2" _stamp
    if [ -z "$_b" ]; then
        echo "headbinlib: RIPWIRE_HEADBIN is set but empty — staged mode names no binary, and it does not build one" >&2
        return 3
    fi
    if [ ! -f "$_b" ] || [ ! -x "$_b" ]; then
        echo "headbinlib: RIPWIRE_HEADBIN=$_b is not an executable file — the staging step did not produce it, and staged mode does not build one" >&2
        return 3
    fi
    _stamp="$( "$_b" --version 2>/dev/null | sed -n 's/.*built_from=\([^ )]*\).*/\1/p' | head -1 )"
    case "$_stamp" in
        *+dirty)
            echo "headbinlib: RIPWIRE_HEADBIN=$_b was built from a dirty tree (built_from=$_stamp) — a comparison binary must be HEAD exactly" >&2
            return 3 ;;
    esac
    case "$_sha" in
        "$_stamp"*) [ "${#_stamp}" -ge 7 ] && return 0 ;;
    esac
    echo "headbinlib: RIPWIRE_HEADBIN=$_b reports built_from=${_stamp:-<none>}, but HEAD is $_sha — it is not the binary this tree's gates compare against" >&2
    return 3
}

# headbin_refusal RC CONTEXT — the verdict on a failed ripwire_head_binary, rendered in the CALLER's shell: it calls
# the gate's own no()/skip(), so it belongs in the `||` branch and never inside $( ). RC 3 is a staged binary that is
# missing or wrong — a broken pipeline — and that FAILS: test/pargates.py counts a SKIP printed past a gate's first
# 400 bytes as a pass, so a skip here would hide it. Any other RC is the unstaged build failing, which keeps its skip.
headbin_refusal()
{
    if [ "$1" -eq 3 ]; then
        no "$2: RIPWIRE_HEADBIN=${RIPWIRE_HEADBIN:-<empty>} is declared but is not a HEAD binary (the headbinlib: line above says why) — a staged comparison binary that is missing or wrong fails this gate; it never falls back to building inside the gate's budget"
    else
        skip "$2: pre-change build failed"
    fi
}

# ripwire_private_checkout ROOT REV DEST  →  DEST becomes a private clone of ROOT's repository with REV checked out,
# detached, whole history included (`--cochange` and a quality-delta over a ref pair read it). `--shared` borrows the
# objects through DEST's own alternates file, so nothing is written into ROOT's .git (see CHECKING OUT A COMMIT above).
# --shared rather than --local: a hardlinking clone left behind by a kill would keep ROOT's replaced pack files (106 MiB
# here) on disk past its next repack. Prints nothing on stdout; sets no trap and never removes DEST, which the caller's
# temp-dir cleanup does. Non-zero, with the reason on stderr, when REV names no commit or the clone fails.
ripwire_private_checkout()
{
    local _root="$1" _rev="$2" _dest="$3" _sha _common
    _sha="$( cd "$_root" && git rev-parse -q --verify "$_rev^{commit}" )"
    case "$_sha" in
        ""|*[!0-9a-f]*) echo "headbinlib: '$_rev' names no commit in $_root" >&2; return 1 ;;
    esac
    _common="$( cd "$_root" && cd "$( git rev-parse --git-common-dir )" && pwd )" || return 1
    git clone -q --shared --no-checkout "$_common" "$_dest" && git -C "$_dest" checkout -q --detach "$_sha"
}

# _headbin_build ROOT SHA WORKDIR OUT  →  builds SHA from a private checkout under WORKDIR, copies the binary to OUT
_headbin_build()
{
    local _root="$1" _sha="$2" _work="$3" _out="$4" _wt _bld _rc=1 _log="${RIPWIRE_HEADBIN_BUILD_LOG:-/dev/null}"
    _wt="$_work/head"; _bld="$_work/build"
    mkdir -p "$_work" || return 1
    # stdout to the log as well: ripwire_head_binary runs inside $( ), where a stray line would become the binary path.
    if ripwire_private_checkout "$_root" "$_sha" "$_wt" >>"$_log" 2>&1; then
        # --target ripwire: the comparison needs that one binary. The default target also builds ripwire_probe and the
        # three doctest binaries, which took another 18 s after a 90 s ripwire-only build (dev machine, 2026-09-10).
        if cmake -S "$_wt" -B "$_bld" -DRIPWIRE_NATIVE=ON >>"$_log" 2>&1 \
           && cmake --build "$_bld" -j --target ripwire >>"$_log" 2>&1 \
           && [ -x "$_bld/ripwire" ]; then
            cp "$_bld/ripwire" "$_out" && chmod +x "$_out" && _rc=0
        fi
    fi
    rm -rf "$_work" 2>/dev/null
    return $_rc
}

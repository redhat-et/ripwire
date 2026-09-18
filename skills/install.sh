#!/usr/bin/env bash
# skills/install.sh — thin wrapper. As of redhat-et/ripwire#225, skills/hooks are embedded in the
# ripwire binary itself; this script only locates a built/installed binary and delegates to
# `ripwire skills install`. Kept so `bash skills/install.sh [flags]` (existing docs, CI scripts,
# muscle memory) keeps working — the real logic lives in src/skillsinstall.h.
set -eu

# Checkout build FIRST, a bare PATH lookup only as the fallback. `command -v ripwire` can resolve to
# a mise/aqua SHIM whose selected version depends on the CURRENT DIRECTORY this script happens to be
# invoked from — the same "must never decide by something cwd-dependent" principle #225 is built
# around (see doctor's shim recognition, Task 14). A checkout build sitting right beside this script
# has no such ambiguity, so it wins whenever one exists.
find_ripwire()
{
    local here; here="$( cd "$( dirname "$0" )/.." && pwd )"
    for candidate in "$here/build/ripwire" "$here/build-release/ripwire"; do
        [ -x "$candidate" ] && { echo "$candidate"; return; }
    done
    command -v ripwire >/dev/null 2>&1 && { command -v ripwire; return; }
    return 1
}

ripwire_bin="$( find_ripwire )" || {
    echo "skills/install.sh: no built or installed ripwire binary found." >&2
    echo "  Build one first: cmake -S . -B build && cmake --build build -j" >&2
    echo "  Or install a release: see README.md's Quickstart." >&2
    exit 1
}

# An explicit destination path positional is passed straight through — `ripwire skills install` (the
# binary this wrapper delegates to) supports it natively as of the fix landed alongside redhat-et/
# ripwire#225 Task 15: a bare, non-"--"-prefixed argument installs into that literal path, refusing
# loudly (not silently falling back to the caller's default agent home) on anything ambiguous, such as
# a second positional or `--hook` combined with one.
exec "$ripwire_bin" skills install "$@"

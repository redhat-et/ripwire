#!/usr/bin/env bash
# reuse_decline_example.sh — the worked example for docs/research/ai-smells-reuse-decline.md.
#
# Builds three throwaway git fixtures and prints the real `--quality-delta` output for each, so the
# documented behaviour of the `new-clone-of-reused-helper` (reuse-decline) kind can be re-derived by
# anyone with the binary. Nothing here touches the repository.
#
#   A  POSITIVE     a new copy of a PRE-EXISTING helper that already has 3 callers  -> reuse-decline fires
#   B  NEGATIVE     an all-new helper with 3 all-new callers, duplicated            -> duplication only
#   C  NEGATIVE     the same copy, but the helper has only 1 caller (fan-in < 3)    -> duplication only
#
# The generated helper body is deliberately NOT the accumulate-loop shape test/cloneidiomfix and
# test/clonededupcheck already use, and the git setup is inlined rather than wrapped in a helper:
# two fixtures that share a body land in one clone group, which is the finding this document is
# about. The first draft of this script produced three duplication rows against those fixtures.
#
# Usage: bash bench/aismells/reuse_decline_example.sh [path/to/ripwire]

set -u
ROOT="$( cd "$( dirname "$0" )/../.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
case "$BIN" in /*) ;; *) BIN="$ROOT/$BIN" ;; esac
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — cmake --build build -j first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP/cache"     # isolate the snapshot cache from the real machine cache
mkdir -p "$TMPDIR"

emit_helper()      # $1 = file, $2 = helper name
{
    cat >> "$1" <<EOF
int $2( int a, int b )
{
    int acc = b;
    while( a > 0 )
    {
        acc = acc * 3 + a;
        a = a - 1;
    }
    return acc % 1000;
}
EOF
}

emit_callers()     # $1 = file, $2 = helper name, $3 = how many callers
{
    n=0
    while [ "$n" -lt "$3" ]; do
        n=$(( n + 1 ))
        printf 'int call%s%d( int x ) { return %s( x, %d ); }\n' "$2" "$n" "$2" "$(( n * 2 ))" >> "$1"
    done
}

show()             # $1 = label, $2 = repo dir
{
    printf '\n===== %s =====\n' "$1"
    "$BIN" "$2" --quality-delta --legend=compact 2>/dev/null \
        | tr '<' '\n' | grep -E '^(quality-delta schema|r kind=")' | sed 's/^/  /'
    printf '  (exit %d)\n' "${PIPESTATUS[0]:-0}"
}

# ── A. POSITIVE: the helper and its three callers are in the BASELINE; the copy is new ────────────────
A="$TMP/a"; mkdir -p "$A/src"
( cd "$A" && git init -q && git config user.email t@t && git config user.name t ) || exit 2
emit_helper  "$A/src/util.cpp" calc
emit_callers "$A/src/util.cpp" calc 3
( cd "$A" && git add -A && git commit -qm base ) || exit 2
emit_helper "$A/src/feature.cpp" calcDup          # the agent re-implements calc() instead of calling it
show "A  POSITIVE — new copy of a pre-existing helper with fan-in 3 (three distinct callers)" "$A"

# ── B. NEGATIVE: helper, callers AND copy are all new in this change (the baseline precondition) ──────
B="$TMP/b"; mkdir -p "$B/src"
( cd "$B" && git init -q && git config user.email t@t && git config user.name t ) || exit 2
printf 'int seed( int x ) { return x; }\n' > "$B/src/seed.cpp"
( cd "$B" && git add -A && git commit -qm base ) || exit 2
emit_helper  "$B/src/util.cpp" calc
emit_callers "$B/src/util.cpp" calc 3
emit_helper  "$B/src/feature.cpp" calcDup
show "B  NEGATIVE — helper, callers and copy all NEW: no pre-existing reuse was eroded" "$B"

# ── C. NEGATIVE: pre-existing helper, but fan-in below kReusedHelperMinFanin ──────────────────────────
C="$TMP/c"; mkdir -p "$C/src"
( cd "$C" && git init -q && git config user.email t@t && git config user.name t ) || exit 2
emit_helper  "$C/src/util.cpp" calc
emit_callers "$C/src/util.cpp" calc 1
( cd "$C" && git add -A && git commit -qm base ) || exit 2
emit_helper "$C/src/feature.cpp" calcDup
show "C  NEGATIVE — pre-existing helper with fan-in 1: below kReusedHelperMinFanin=3" "$C"

printf '\n(fixtures were built under %s and are now removed)\n' "$TMP"

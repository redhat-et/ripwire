#!/usr/bin/env bash
# forscopecheck.sh — the --for answer's phase map: every PROFILE_SCOPE in src/verbs_for.h and
# src/forpage.h sits at a BLOCK ENTRY, fires on a real invocation, and costs the default binary
# nothing (lane/verbfor-attrib, 2026-11-27).
#
# WHY. A warm `--for` on llvm-project spent ~80% of its time in one unlabelled bucket inside
# verbs_for.h. The owner ruled that the bucket gets a permanent phase map rather than a one-off
# sampling pass, so these scopes stay in the tree for whoever measures next. That makes two
# failures expensive in a way a throwaway probe's would not be:
#
#   * A MISPLACED scope. PROFILE_SCOPE lives to the end of its ENCLOSING BLOCK. A scope declared
#     beside the code someone suspects therefore also times everything below it, and reports a
#     large number that reads as confirmation of the suspicion. The LARGE-REPO-PERF lane came one
#     step from designing a change against a 0.03 ms target for exactly this reason. Every scope in
#     these two files is at a block entry — the line after `{` — so its extent IS the block it
#     names and the inclusive reading is the intended one. Arm A asserts that invariant for every
#     scope, not for a hand-kept list that can go stale.
#   * A scope that NEVER FIRES. It reports nothing, which a reader cannot distinguish from "no time
#     here", and sends the next person to optimise the wrong block. Arm D requires calls>=1 for
#     every scope in these files, across the postures one --for answer cannot cover alone.
#
# Both arms carry their own control, because neither can be trusted on a green run otherwise: a
# placement matcher that says "fine" to every line would pass arm A, and a firing matcher that
# never reports a miss would pass arm D. Arms B and E make each one fail on purpose.
#
#   (A) PLACEMENT, in the source: every PROFILE_SCOPE_DESCRIBE in these two files is preceded by a
#       line whose content is `{`.
#   (B) CONTROL for A: the same matcher, run over a POISONED copy in which one scope has been moved
#       off the block entry, must report that scope as misplaced.
#   (C) ZERO COST WHEN OFF, in the binary: the default build emits no profiler text on any stream.
#   (D) BEHAVIOUR: with a profile build, every scope declared in these files fires with calls>=1 on
#       at least one of the invocations below. Skipped with a reason when there is no profile tree,
#       in the pmccheck.sh manner.
#   (E) CONTROL for D: a description that is NOT in the source must be reported as never-firing by
#       the same matcher.
#
# Usage:  bash test/forscopecheck.sh [path/to/ripwire]
#         RIPWIRE_BIN=… RIPWIRE_PROF_BIN=build_prof/ripwire bash test/forscopecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
PROF_BIN="${RIPWIRE_PROF_BIN:-$ROOT/build_prof/ripwire}"

echo "forscopecheck: BIN=$BIN $( "$BIN" --version 2>/dev/null | head -1 )"

fail=0
note() { echo "  FAIL  $*"; fail=1; }
ok()   { echo "  ok    $*"; }

[ -x "$BIN" ] || { echo "  FAIL  no binary at $BIN"; exit 2; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT

FILES="src/verbs_for.h src/forpage.h"

# ── the matcher, shared by arms A and B ──────────────────────────────────────────────────────────────
# Prints one "line:description" per scope whose PRECEDING source line is not exactly `{`. Silence
# means every scope in the file sits at a block entry. Shared with the control in B on purpose, so
# B exercises the same code path A relies on.
misplaced() {
    awk '
        index( $0, "PROFILE_SCOPE_DESCRIBE(" ) && !index( $0, "#define" ) && !index( $0, "//" ) {
            if ( prev != "{" ) { print FILENAME ":" NR ": " $0 }
        }
        { gsub( /^[ \t]+|[ \t]+$/, "" ); prev = $0 }
    ' "$1"
}

# ── Arm A: every scope in these files is at a block entry ────────────────────────────────────────────
total_scopes=0
for f in $FILES; do
    [ -f "$ROOT/$f" ] || { note "arm A: $f is missing — this gate's file list is stale, which is a gate bug, not a pass"; continue; }
    n="$( grep -c 'PROFILE_SCOPE_DESCRIBE(' "$ROOT/$f" )"
    total_scopes=$(( total_scopes + n ))
    bad="$( misplaced "$ROOT/$f" )"
    if [ -n "$bad" ]; then
        note "arm A: $f has scopes that are NOT at a block entry — each one also times everything below it to the end of its block:"
        echo "$bad" | sed 's/^/          /'
    else
        ok "arm A: all $n scopes in $f sit at a block entry (the line after {)"
    fi
done

# A deletion must not read as a pass either: the map is only useful while it is complete.
if [ "$total_scopes" -lt 41 ]; then
    note "arm A: only $total_scopes scopes across $FILES, expected at least 41 — the --for phase map has lost blocks"
else
    ok "arm A: $total_scopes scopes across $FILES (floor 41)"
fi

# ── Arm B: the control. A deliberately misplaced scope must be REPORTED misplaced ────────────────────
# Without this, a matcher that approves every line on earth would pass arm A.
cp "$ROOT/src/forpage.h" "$WORK/poisoned.h"
# Append a scope that is NOT preceded by `{`: a free function whose first body statement precedes it.
cat >> "$WORK/poisoned.h" <<'POISON'
inline int forScopeCheckPoison( int x )
{
    int y = x + 1;
    PROFILE_SCOPE_DESCRIBE( "poison: this scope is not at a block entry" );
    return y;
}
POISON
if misplaced "$WORK/poisoned.h" | grep -q 'poison: this scope is not at a block entry'; then
    ok "arm B: the matcher reports a scope moved off the block entry (arm A is not vacuous)"
else
    note "arm B: the matcher did NOT report a deliberately misplaced scope — it says yes to anything, so arm A proved nothing"
fi

# ── Arm C: zero cost when off, in the shipped default build ──────────────────────────────────────────
"$BIN" "$ROOT/test/largescalefix" --for="resolve a symbol reference" > "$WORK/off.xml" 2> "$WORK/off.err"
leak=0
for pat in '#PROF_TSV' 'hottest scopes' 'for/pass:' 'for/tail:' 'for/rank:'; do
    if grep -qF "$pat" "$WORK/off.xml" "$WORK/off.err" 2>/dev/null; then
        note "arm C: the DEFAULT build emitted profiler text ($pat) — PROFILE_SCOPE is not compiling out"
        leak=1
    fi
done
[ "$leak" -eq 0 ] && ok "arm C: the default build emits no profiler text on stdout or stderr"

# ── the firing matcher, shared by arms D and E ───────────────────────────────────────────────────────
# calls= for one scope description, summed over every #PROF_TSV block in the collected stderr. 0 when
# the description never appears.
calls_for() {
    awk -F'\t' -v s="$1" '
        /^#PROF_TSV_BEGIN/ { f = 1; next }
        /^#PROF_TSV_END/   { f = 0 }
        f && $1 == s       { n += $4 }
        END                { print n + 0 }
    ' "$WORK/prof.all"
}

# ── Arm D: every scope fires ─────────────────────────────────────────────────────────────────────────
if [ ! -x "$PROF_BIN" ]; then
    echo "  SKIP  arms D+E (do the scopes fire?): no profile build at $PROF_BIN — configure one with"
    echo "        cmake -S . -B build_prof -DRIPWIRE_PROFILE=ON && cmake --build build_prof -j"
    echo "        Arms A-C asserted; the behavioural arm is the one this machine did not express."
else
    # The arena the runs use must EXIST. A gate that points the binary at a directory it never
    # created gets a silent snapshot-write failure, an empty second run, and every scope reading as
    # absent — which it then blames on the source. (LARGE-REPO-PERF, 2026-11-27.)
    mkdir -p "$WORK/cache" "$WORK/tmp"
    : > "$WORK/prof.all"
    # One --for answer cannot reach every dialect, so the postures are enumerated: default XML
    # bundle, JSON, candidates, an explicit token budget (the fitted re-render), bodies, and the
    # file page. Each appends its own #PROF_TSV block; calls_for sums across them.
    run_posture() {
        XDG_CACHE_HOME="$WORK/cache" TMPDIR="$WORK/tmp" "$PROF_BIN" "$ROOT/src" "$@" \
            > /dev/null 2>> "$WORK/prof.all"
    }
    run_posture --for="resolve a symbol reference into the call graph"
    run_posture --for="resolve a symbol reference into the call graph" --json
    run_posture --for="resolve a symbol reference into the call graph" --format=candidates
    run_posture --for="resolve a symbol reference into the call graph" --format=candidates --limit=10 --offset=0
    run_posture --for="resolve a symbol reference into the call graph" --token-budget=2000
    run_posture --for="resolve a symbol reference into the call graph" --detail=1
    run_posture --for="resolve a symbol reference into the call graph" --signatures-only
    run_posture --for="who calls resolveReference" --legend=last
    run_posture --for="src/resolve.h" --limit=10 --offset=0

    if ! grep -q '^#PROF_TSV_BEGIN' "$WORK/prof.all"; then
        note "arm D: no #PROF_TSV block in any run's stderr — the profile build emitted no report, so nothing below could be checked"
    else
        blocks="$( grep -c '^#PROF_TSV_BEGIN' "$WORK/prof.all" )"
        ok "arm D: collected $blocks #PROF_TSV blocks from 9 postures"
        silent=""
        checked=0
        # The scope list is DERIVED from the source, so this arm cannot go stale against it.
        while IFS= read -r desc; do
            [ -n "$desc" ] || continue
            checked=$(( checked + 1 ))
            c="$( calls_for "$desc" )"
            if [ "$c" -lt 1 ] 2>/dev/null; then
                silent="$silent
          $desc"
            fi
        done <<EOF
$( sed -n 's/.*PROFILE_SCOPE_DESCRIBE( "\(.*\)" ).*/\1/p' $( for f in $FILES; do echo "$ROOT/$f"; done ) | sort -u )
EOF
        if [ -n "$silent" ]; then
            note "arm D: $( echo "$silent" | grep -c . ) of $checked scopes never fired on any posture — a scope that reads zero because it never ran is indistinguishable from \"no time here\":$silent"
        else
            ok "arm D: all $checked scopes in $FILES fired with calls>=1"
        fi

        # ── Arm E: the control for D ──────────────────────────────────────────────────────────────
        if [ "$( calls_for 'for/absent: a description no scope in the tree carries' )" -eq 0 ]; then
            ok "arm E: the firing matcher reports a description that is not in the tree as never-firing (arm D is not vacuous)"
        else
            note "arm E: the firing matcher found calls for a description no scope carries — it reports firing for anything, so arm D proved nothing"
        fi
    fi
fi

if [ "$fail" -ne 0 ]; then
    echo "forscopecheck: FAIL"
    exit 1
fi
echo "forscopecheck: PASS"

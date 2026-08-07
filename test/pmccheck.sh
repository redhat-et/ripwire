#!/usr/bin/env bash
# pmccheck.sh — honesty gate for the PROFILE_SCOPE hardware-counter backend (src/infra/profilePmc.h).
#
# Compiles test/pmccheck_harness.cpp with -DPROFILE_ENABLED=1 and runs it. The backend must land in one
# of exactly two truthful states — ACTIVE (counters armed, plausible deltas, named slots) or INACTIVE
# (zero events, zero reads, no stderr noise — the quiet-degrade contract). The harness asserts whichever
# state it observes from the inside; this script additionally enforces:
#   * the prof::report() output renders on STDERR and never on stdout (stdout is the data stream — for
#     the real binary it carries the XML map, and a report trailing it would break every >file / | xmllint
#     workflow and G4's well-formedness expectation for the profile flavour),
#   * stderr carries NOTHING besides that report when INACTIVE (an unprivileged/vPMU-less run must not
#     spam arming noise), and
#   * the prof::report() output carries counter columns IFF the state was ACTIVE.
#
# Runs meaningfully everywhere: unprivileged macOS and vPMU-less VMs exercise the degrade arm; a Linux
# box with an exposed PMU (bare metal, *.metal) exercises the live arm. Neither arm is optional where it
# applies, so the gate is never vacuous — it just proves a different half of the contract per machine.
#
# Usage:  bash test/pmccheck.sh            (compiles with c++/clang++)
#         CXX=clang++ bash test/pmccheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
CXX="${CXX:-c++}"

. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
HARNESS="$ROOT/test/pmccheck_harness.cpp"
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/pmccheckharness"

echo "pmccheck: CXX=$CXX"

# ── compile: profileScope.h + profilePmc.h, profiling ON, auto-report OFF (the harness calls report()).
#    -pthread for the registry mutex/thread identity; O2 so the busy loop's codegen is realistic. ────────
if ! "$CXX" "$CXXSTD" -O2 -g -Wall -Wextra -pthread \
        -DPROFILE_ENABLED=1 -DPROFILE_AUTO_REPORT=0 \
        -I"$ROOT/src/infra" -I"$ROOT/src" -I"$ROOT/third_party" \
        "$HARNESS" -o "$BIN" 2> "$WORK/cc.log"; then
    echo "  FAIL  harness failed to compile"; sed 's/^/    /' "$WORK/cc.log"; exit 2
fi
echo "  PASS  harness compiled (PROFILE_ENABLED=1)"

# ── run with the streams split: stdout carries the arm results, stderr carries the report ───────────────
if ! "$BIN" > "$WORK/out.log" 2> "$WORK/err.log"; then
    echo "pmccheck: FAIL (harness contract violation)"
    grep 'FAIL\|pmc state' "$WORK/out.log" | sed 's/^/    /' | head -10
    exit 2
fi
STATE="$( grep -o 'pmc state: [A-Z]*' "$WORK/out.log" | awk '{ print $3 }' )"
echo "  PASS  harness contract ($STATE arm)"

# ── stream contract: the report renders on STDERR, and stdout stays clean of it ─────────────────────────
if ! grep -q 'PROFILE REPORT' "$WORK/err.log"; then
    echo "  FAIL  report stream (prof::report() did not render on stderr)"
    exit 2
fi
if grep -q 'PROFILE REPORT\|PROF_TSV' "$WORK/out.log"; then
    echo "  FAIL  report stream (report leaked onto stdout — it would trail the XML map)"
    exit 2
fi
echo "  PASS  report stream (report on stderr, stdout clean of it)"

# ── quiet-degrade: an INACTIVE run writes NOTHING to stderr before the report (no arming spam) ──────────
if [ "$STATE" = "INACTIVE" ]; then
    sed -n '/PROFILE REPORT/q;p' "$WORK/err.log" > "$WORK/prelude.log"
    if grep -q . "$WORK/prelude.log"; then
        echo "  FAIL  quiet degrade (INACTIVE run wrote to stderr besides the report):"
        sed 's/^/    /' "$WORK/prelude.log" | head -5
        exit 2
    fi
    echo "  PASS  quiet degrade (INACTIVE, stderr carries only the report)"
fi

echo "pmccheck: PASS"

#!/usr/bin/env bash
# extractparity.sh — does a CANDIDATE binary print byte-identical output to a BASELINE binary?
#
# The harness for a behaviour-preserving decomposition (lane resolve-parallel, Series A-D: buildGraph
# is 4,043 lines reached by 79 symbols with radius_tested=0, so it is being cut into its own 22
# PROFILE_SCOPE-declared phases one commit at a time). Extraction must move no byte. This asks that.
#
# It lives in test/lib/ and is NOT a registered gate, deliberately: its baseline is a binary built
# from the commit before a series started, which CI cannot reproduce. test/manifestcheck.sh owns
# top-level test/*.sh only. Run it by hand, per commit or per small group.
#
#   test/lib/extractparity.sh <baseline-binary> [candidate-binary] [extra corpus ...]
#
# "BYTE-IDENTICAL" PROVES NOTHING UNLESS THIS HARNESS CAN FAIL. Two guards, because a parity check
# is the easiest thing in the world to make vacuous:
#   * it REFUSES when the two binaries are the same file (or compare equal) — then parity is a
#     tautology, not a measurement;
#   * it REFUSES when either run prints nothing, since cmp calls two empty files equal (the same
#     shape --quality-delta's vacuous-assert caught in test/ownedasksitescheck.sh's first draft).
# Neither guard replaces the external proof: point it at a binary with a DELIBERATE one-line
# behaviour change and watch it go red. Until that has been seen, a green run means nothing.
#
# A RUST TREE IS IN THE DEFAULT SWEEP ON PURPOSE. rustGlobFiles, rustForeignGlob, rustPathOwnerMemo
# and the chain tables are Rust-only lazy builds: they are never touched on llvm-project or on this
# repo, so a torn or mis-extracted one escapes a C++-only sweep entirely.
#
# THE STANDING ANTI-VACUITY PROBE IS "POISON 2": swap `scope` and `name` in buildGraph/1a's
# `canonicalId` call. It feeds serialize's `id=`, so it moves bytes on every corpus — measured red at
# char 3114 of the first corpus on 2026-11-27. Run it, or something like it, whenever this harness
# changes: a green sweep means nothing until a deliberate behaviour change has been seen to go red.
#
# "POISON 1" IS RECORDED AS A BAD PROBE, because what it cost to find out is the lesson. Flipping
# buildGraph/1a's `if( s.scope.empty() )` makes `localityKeyAt` return canonicalId's BARE NAME instead
# of `path::name` for every UNSCOPED symbol, reintroducing the defect resolve.h localityKeyOf
# documents ("it gave a module-level function zero shared segments with every caller, so it could
# never survive the tie-break against a same-file class method": 10 of 23 disconfirmed pins on
# astropy). It looks like the perfect probe and it changes NO OUTPUT anywhere measurable here:
# byte-identical over 282 fixture corpora, over this repo — which reports locality_pinned=15, so its
# tie-break demonstrably FIRES — and over two corpora built on purpose from the mechanism. The reason
# is in the gate at graph.h:14215: S6-C needs a SCOPED caller and `!nameOnly`, and an unscoped
# candidate surviving to there occurs on no corpus available here. (Caveat: astropy, where the
# original evidence was taken, is not one of them.) So this harness's ALL PASS on poison 1 was
# CORRECT, not blind — the first diagnosis, mine included, had that backwards.
#
# COVERAGE IS STILL WORTH ASSERTING, and this repo is the proof of why it is NECESSARY BUT NOT
# SUFFICIENT: locality_pinned=15, and it still cannot detect poison 1. A sweep that fires the
# tie-break nowhere cannot see a localityKey regression at all; one that fires it may still miss a
# particular regression. Matched as a VALUE against the BASELINE output:
#   * locality_pinned= / lpin= (pincensus.h: Graph::locPinOut) — the tie-break decided >= 1 call.
# Observed spelling, not assumed: this repo emits `locality_pinned=15` UNQUOTED, so the optional quote
# in the pattern below is load-bearing — a mandatory-quote grep is silent on every real corpus.
# Every run is --no-cache: a warm run replays a snapshot and never enters buildGraph at all.
set -u
ROOT="$( cd "$( dirname "$0" )/../.." && pwd )"
BASE="${1:-}"
CAND="${2:-$ROOT/build/ripwire}"
[ -n "$BASE" ] || { echo "usage: $0 <baseline-binary> [candidate-binary] [extra corpus ...]"; exit 2; }
shift || true
shift || true

fail=0
# Same accumulator rule as a registered gate (test/gateexitcheck.sh arm G1): a PASS line that fails to
# write must not leave the run exiting 0 with a finding missing from its output.
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

for b in "$BASE" "$CAND"; do
    [ -x "$b" ] || { echo "extractparity: not executable: $b"; exit 2; }
done
echo "BASE=$BASE $( "$BASE" --version 2>&1 | head -1 )"
echo "CAND=$CAND $( "$CAND" --version 2>&1 | head -1 )"

# ── guard 1: the two binaries must differ ────────────────────────────────────────────────────────
if [ "$( cd "$( dirname "$BASE" )" && pwd )/$( basename "$BASE" )" = "$( cd "$( dirname "$CAND" )" && pwd )/$( basename "$CAND" )" ]; then
    echo "extractparity: BASE and CAND are the same file — parity would be a tautology. Snapshot the baseline first."
    exit 2
fi
if cmp -s "$BASE" "$CAND"; then
    echo "extractparity: BASE and CAND are byte-identical binaries — nothing was rebuilt, so this run would prove nothing."
    exit 2
fi
ok "the two binaries differ, so a parity result is a measurement and not a tautology"

WORK="$( mktemp -d )"
trap 'rm -rf "$WORK"' EXIT

# C++, mixed-language, and two Rust trees. Extra corpora may be appended on the command line
# (envoy / llvm-project for a final pass; too slow for a per-commit loop).
CORPORA="$ROOT $ROOT/test/receiverevidencefix $ROOT/test/rustpathownerfix $ROOT/test/rustmacropathfix $ROOT/test/ifacedispatchfix"
for extra in "$@"; do CORPORA="$CORPORA $extra"; done

for corpus in $CORPORA; do
    [ -d "$corpus" ] || { no "no such corpus: $corpus"; continue; }
    tag="$( echo "$corpus" | tr -c 'A-Za-z0-9' '_' )"
    "$BASE" "$corpus" --no-cache > "$WORK/$tag.base" 2>"$WORK/$tag.base.err"
    "$CAND" "$corpus" --no-cache > "$WORK/$tag.cand" 2>"$WORK/$tag.cand.err"

    # ── guard 2: an empty comparison is not a comparison ─────────────────────────────────────────
    if [ ! -s "$WORK/$tag.base" ] || [ ! -s "$WORK/$tag.cand" ]; then
        no "$( basename "$corpus" ): one of the runs printed nothing — comparing empty output proves nothing"
        continue
    fi

    if cmp -s "$WORK/$tag.base" "$WORK/$tag.cand"; then
        ok "$( basename "$corpus" ): byte-identical ($( wc -c < "$WORK/$tag.base" ) bytes)"
    else
        no "$( basename "$corpus" ): OUTPUT MOVED — $( cmp "$WORK/$tag.base" "$WORK/$tag.cand" 2>&1 | head -1 )"
    fi

    # the candidate must also be self-consistent: two runs, same bytes
    "$CAND" "$corpus" --no-cache > "$WORK/$tag.cand2" 2>/dev/null
    cmp -s "$WORK/$tag.cand" "$WORK/$tag.cand2" \
        && ok "$( basename "$corpus" ): candidate is deterministic across two runs" \
        || no "$( basename "$corpus" ): candidate differs from itself between runs"

    command -v xmllint >/dev/null 2>&1 && {
        xmllint --noout "$WORK/$tag.cand" 2>/dev/null \
            && ok "$( basename "$corpus" ): candidate output is well-formed XML" \
            || no "$( basename "$corpus" ): candidate output is not well-formed XML"
    }
done

# ── coverage: does this sweep touch the S6-C locality tie-break at all? ──────────────────────────
# Asserted against the BASELINE outputs, so it describes the corpus set rather than the change under
# test. A sweep that never fires the tie-break cannot see a localityKey regression, which is exactly
# how poison 1 escaped. Matched as a VALUE (`k="?[1-9]`), never a bare key: `locality_pinned` and
# `lpin` both appear in legend text and in disclosure prose, so a key match would pass on a run that
# reported zero. The quote is OPTIONAL because a counter can be emitted UNQUOTED inside a trailing
# XML comment — a grep for `bots_[a-z]+="[0-9]+"` found nothing for exactly that reason on 11-27.
coverageHasPin(){ grep -qE 'locality_pinned="?[1-9]|[ <]lpin="?[1-9]' "$1"; }

# THE COVERAGE ARM IS ITSELF AN INSTRUMENT, so it is checked in BOTH directions before its verdict is
# allowed to steer anything. A grep asserting presence passes trivially when it is wrong in the
# permissive direction, and nobody notices, because every corpus one adds is one believed to have
# coverage — `trap-prohibition-check-is-vacuous-by-default` with the sign flipped. So:
#   (+) it must FIRE on a value that is present;
#   (-) it must STAY SILENT on a zero value sitting beside legend prose that names the same keys.
# These run every time, need no binary, and fail the harness if the pattern ever drifts either way.
selfWork="$WORK/coverage-selftest"
mkdir -p "$selfWork"
printf '%s\n' '<map locality_pinned="3" amb="0"/><d n="f" lpin="2"/>'                 > "$selfWork/present-quoted"
printf '%s\n' '<!-- counters locality_pinned=7 ambiguous=4 -->'                       > "$selfWork/present-unquoted"
printf '%s\n' '<map locality_pinned="0" amb="0"/><d n="f" lpin="0"/>'                 > "$selfWork/zero-quoted"
printf '%s\n' '<!-- legend: locality_pinned=N: the S6-C locality tie-break pinned N calls; lpin="K": per-symbol. locality_pinned=0 means none found, never none exists. -->' > "$selfWork/zero-with-legend-prose"
selfFail=0
for f in present-quoted present-unquoted; do
    coverageHasPin "$selfWork/$f" || { no "coverage self-test (+): the pattern does NOT fire on $f — its silence on a real corpus would prove nothing"; selfFail=1; }
done
for f in zero-quoted zero-with-legend-prose; do
    if coverageHasPin "$selfWork/$f"; then
        no "coverage self-test (-): the pattern fires on $f, where the value is ZERO — it is matching the key or the prose, so it cannot detect a zero-coverage sweep"
        selfFail=1
    fi
done
[ "$selfFail" -eq 0 ] && ok "coverage self-test: the pattern fires on a present value (quoted and unquoted) and stays silent on a zero beside legend prose naming the same keys"

pinned=0
for f in "$WORK"/*.base; do
    [ -s "$f" ] || continue
    coverageHasPin "$f" && pinned=$(( pinned + 1 ))
done
if [ "$selfFail" -ne 0 ]; then
    no "coverage: verdict WITHHELD — the arm failed its own self-test above, so its reading of the corpora means nothing either way"
elif [ "$pinned" -gt 0 ]; then
    ok "coverage: the S6-C locality tie-break fires in $pinned corpus/corpora of this sweep (necessary for a localityKey regression to be visible; not sufficient on its own)"
else
    no "coverage: NO corpus in this sweep fires the S6-C locality tie-break (no locality_pinned/lpin > 0) — a localityKey regression is invisible here, which is how poison 1 escaped on 2026-11-27"
fi

[ "$fail" -eq 0 ] && echo "extractparity: ALL PASS" || echo "extractparity: FAILURES"
exit "$fail"

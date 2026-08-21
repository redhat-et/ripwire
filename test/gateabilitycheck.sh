#!/usr/bin/env bash
# gateabilitycheck.sh — the gate for r26-stamp Task B: `--doc-drift --gateability` (src/docdrift.h's
# writeDocDrift gateability block + the --gateability flag in src/cli.h).
#
# Fixture: test/gateabilityfix/ — one code.h defining `liveFn`, and four docs pinning the three cases the
# projection has to get right:
#   UNDATED.md — no date anywhere -> both its failing mentions stay LIVE               -> live=2, IN the list
#   DATED.md   — H1 carries an ISO date -> both its failing mentions are dated away     -> live=0, NOT listed
#   MIXED.md   — undated overall, but ONE line hedges "As of 2026-01-01" (Record::Line)
#                -> that one is dated, the other stays live                            -> live=1, IN the list
#   CLEAN.md   — its one mention holds (liveFn is real)                                -> no drift row at all
#
# Repo-wide: drift = 2 (UNDATED) + 0 (DATED) + 1 (MIXED) = 3; dated = 0 + 2 + 1 = 3. gateability must list
# exactly {MIXED.md: live=1, UNDATED.md: live=2} and compute projected_drift = drift(3) - (1+2) = 0 — i.e.
# annotating BOTH listed docs would account for every currently-live row (the invariant writeDocDrift's own
# VERIFY pins: liveTotal == res.drift). DATED.md and CLEAN.md must be ABSENT from the list.
#
# Also asserts: --gateability alone (no --doc-drift) refuses loudly (exit != 0, no XML on stdout); the
# gateability block is present ONLY under the flag (bare --doc-drift omits it); xmllint-clean; determinism.
#
# Usage:
#   test/gateabilitycheck.sh
#   RIPWIRE_BIN=asan/ripwire test/gateabilitycheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/gateabilityfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "no fixture at $CORPUS"; exit 2; }

echo "gateabilitycheck: BIN=$BIN  CORPUS=$CORPUS"

# ── plain --doc-drift: no gateability block at all, and the repo-wide tallies are what the fixture pins ──
plain="$( "$BIN" "$CORPUS" --doc-drift --no-cache 2>/dev/null )"
case "$plain" in
    *'<gateability'*) no "bare --doc-drift emitted a <gateability> block — should require the flag" ;;
    *)                ok "bare --doc-drift: no <gateability> block" ;;
esac
printf '%s' "$plain" | grep -q '<doc-drift docs="4" clean="1" anchors="13" checked="13" unchecked="0" drift="3" dated="3"' \
    && ok "repo tallies: docs=4 clean=1 drift=3 dated=3" \
    || { no "repo tallies drifted from the fixture's pinned numbers"; printf '%s' "$plain" | grep -o '<doc-drift[^>]*>'; }

# ── --gateability alone (no --doc-drift): refused loudly, no XML ──────────────────────────────────────
out_alone="$( "$BIN" "$CORPUS" --gateability --no-cache 2>/dev/null )"
rc_alone=$?
if [ "$rc_alone" != "0" ] && [ -z "$out_alone" ]; then
    ok "--gateability alone: refused (exit $rc_alone, no stdout)"
else
    no "--gateability alone: should refuse loudly — got exit=$rc_alone, stdout=$(printf '%.60s' "$out_alone")"
fi

# ── --doc-drift --gateability: the block itself ────────────────────────────────────────────────────────
full="$( "$BIN" "$CORPUS" --doc-drift --gateability --no-cache 2>/dev/null )"
rc=$?
[ "$rc" = "0" ] && ok "exits 0 (a report, not a gate)" || no "--doc-drift --gateability exited $rc, expected 0"

block="$( printf '%s' "$full" | tr '<' '\n' | sed -n '/^gateability /,/^\/gateability/p' )"

printf '%s' "$full" | grep -q '<gateability docs="2" projected_drift="0">' \
    && ok "gateability docs=\"2\" projected_drift=\"0\"" \
    || { no "gateability header wrong"; printf '%s' "$full" | grep -o '<gateability[^>]*>'; }

printf '%s' "$block" | grep -q 'fix p="UNDATED.md" live="2"' \
    && ok "UNDATED.md listed with live=\"2\"" || no "UNDATED.md missing or wrong live= count"

printf '%s' "$block" | grep -q 'fix p="MIXED.md" live="1"' \
    && ok "MIXED.md listed with live=\"1\" (its dated line is excluded)" || no "MIXED.md missing or wrong live= count"

printf '%s' "$block" | grep -q 'fix p="DATED.md"' && no "DATED.md listed — it is fully dated, live=0, must be ABSENT" \
                                                    || ok "DATED.md correctly absent (fully dated, nothing left to fix)"

printf '%s' "$block" | grep -q 'CLEAN.md' && no "CLEAN.md listed — it has no drift at all" \
                                           || ok "CLEAN.md correctly absent (no drift)"

# ── determinism + xmllint ──────────────────────────────────────────────────────────────────────────────
full2="$( "$BIN" "$CORPUS" --doc-drift --gateability --no-cache 2>/dev/null )"
# Compare everything EXCEPT the root's at= git stamp, the same carve-out pagingsweepcheck's identity arm
# makes for root disclosure attributes. at= is `<sha>` plus a `+dirty` marker derived from the WORKING TREE,
# not from the corpus this verb measured — so a suite-mate that transiently creates or removes a file
# anywhere under $ROOT flips it between these two runs and reddens an assertion about doc-drift's output.
# That is exactly what happened on release (ubuntu-24.04, plain, gcc) of CI run 31185013910: this gate the
# only failure on the leg, "non-deterministic" in 0.7 s, and 5/5 byte-identical when run alone. The tool is
# deterministic given identical inputs; the input moved underneath it. Stripping the stamp keeps the arm
# asserting what it is named for — that the MEASUREMENT is reproducible — instead of also asserting that no
# other gate touched the checkout while it ran, which is not this gate's business and is not in its control.
strip_at(){ printf '%s' "$1" | sed -E 's/ at="[^"]*"//g'; }
[ "$( strip_at "$full" )" = "$( strip_at "$full2" )" ] \
    && ok "determinism (byte-identical, modulo the at= working-tree stamp)" \
    || no "--doc-drift --gateability is non-deterministic"
printf '%s' "$full" | xmllint --noout - >/dev/null 2>&1 && ok "xmllint clean" || no "xmllint FAILED"

if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "SOME FAILED"; fi
exit "$fail"

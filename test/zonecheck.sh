#!/usr/bin/env bash
# zonecheck.sh — gate for the Martin Zone-of-Pain / Zone-of-Uselessness classification on --arch's
# per-module <m zone="pain|useless|ok"> attribute (src/arch.h::computeModuleMetrics).
#
# HONESTY LABEL (do not lose this in a rewrite): Martin I/A/D and the derived zone classification are
# FOLKLORE — widely implemented (NDepend, Sonargraph, ctxpack) but with no independent outcome-based
# study validating that D (or the pain/useless corners) predicts defects or maintenance cost. See
# src/arch.h's "EVIDENCE NOTE" above computeModuleMetrics, and RESEARCH_agentQuality2026.md §1a. This
# gate checks the classification is computed CORRECTLY and DETERMINISTICALLY from I/A — it is not, and
# cannot be, a check that the classification is "right" in any predictive sense.
#
# Thresholds (named constexpr in src/arch.h, computeModuleMetrics(..., distThreshold = 0.5)):
#   zone is only assigned past the distance threshold: D > 0.5 (main-sequence distance).
#   Past that threshold, the (A, I) point is split by which side of the main sequence (A+I=1) it falls:
#     A + I <  1.0  -> "pain"     (the low-I/low-A corner: concrete AND stable/depended-on -> rigid)
#     A + I >= 1.0  -> "useless"  (the high-I/high-A corner: abstract AND nothing depends on it)
#   D <= 0.5                       -> "ok" (near the main sequence)
#   Tie-break: D exactly == distThreshold (0.5) falls on the "ok" side (strict '>' in the comparison,
#   src/arch.h computeModuleMetrics: `if( mm.distance > distThreshold )`) — deterministic, documented.
#
# Fixture test/zonefix/ (hand-verified expected I/A/D — see each header's comment for the derivation).
# Module-level Ca/Ce counts DISTINCT MODULES (not files) that cross a module boundary — see arch.h's
# APPROXIMATION DISCLAIMER above computeModuleMetrics.
#   pain     — concrete leaf (Util has a method BODY, not abstract). THREE other modules include
#              pain/util.h (consumer, balanced, useless) and pain depends on nothing ->
#              Ca=3 Ce=0 I=0.00 A=0.00 D=1.00 -> zone="pain"
#   useless  — pure-abstract interface (Shape::area has NO body), depends on pain/util.h. Deliberately
#              included by NOTHING else in the fixture (consumer does NOT include it — that's the whole
#              point: an abstraction nothing depends on) -> Ca=0 Ce=1 I=1.00 A=1.00 D=1.00 ->
#              zone="useless". Ca==0 also makes it a reachability DAG-root entry point (not a dead
#              island) — asserted below too.
#   balanced — one abstract (Mixed, no body) + one concrete (Concrete, has body) type; depended on by
#              consumer, depends on pain -> Ca=1 Ce=1 I=0.50 A=0.50 D=0.00 -> zone="ok"
#   consumer — drives the pain+balanced edges + supplies `main` (reachability entry); Ca=0 Ce=2 I=1.00,
#              ZERO types -> A=0.00 (forced, not measured), D=|0+1-1|=0.00. §P6.5: a typeless module's A
#              is never a real abstractness measurement, so its zone is "n/a" regardless of what D happens
#              to land on (here D=0.00 would coincidentally read "ok" under the old logic — that
#              coincidence is exactly why the exclusion has to be unconditional, not "only when D is bad").
#
# Usage:  CTXPACK_BIN=build/ctxpack bash test/zonecheck.sh   |   CTXPACK_BIN=asan/ctxpack bash test/zonecheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/zonefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no test/zonefix dir — fixture missing"; exit 2; }
[ -f "$FIX/zone.arch" ] || { echo "no test/zonefix/zone.arch — fixture rules file missing"; exit 2; }
cd "$ROOT"

echo "zonecheck: BIN=$BIN  CORPUS=test/zonefix"

arch(){ perl -e 'alarm 20; exec @ARGV' "$BIN" "$FIX" --arch="$1" --no-cache 2>/dev/null; }
mod(){ printf '%s' "$1" | tr '>' '\n' | grep '<m ' | grep "/$2\""; }
hasall(){ local line="$1"; shift; for a in "$@"; do printf '%s' "$line" | grep -q "$a" || return 1; done; return 0; }

OUT="$( arch "$FIX/zone.arch" )"

[ -n "$OUT" ] && printf '%s' "$OUT" | grep -q '<arch' \
    && ok "produced well-formed <arch> output" || { no "no/empty --arch output"; }

# ── 1) pain: concrete + heavily-depended-on -> zone="pain" ────────────────────────────────────────────
m="$( mod "$OUT" pain )"
hasall "$m" 'ca="3"' 'ce="0"' 'I="0.00"' 'A="0.00"' 'D="1.00"' 'zone="pain"' \
    && ok "pain     = concrete leaf, Ca3 Ce0 I0.00 A0.00 D1.00 -> zone=pain" || no "pain metrics wrong: $m"

# ── 2) useless: abstract + depended-on-by-nothing -> zone="useless" (and still reachable: Ca==0 -> DAG root) ──
m="$( mod "$OUT" useless )"
hasall "$m" 'ca="0"' 'ce="1"' 'I="1.00"' 'A="1.00"' 'D="1.00"' 'zone="useless"' 'reachable="1"' \
    && ok "useless  = abstract root, Ca0 Ce1 I1.00 A1.00 D1.00 -> zone=useless (reachable=1, DAG-root entry)" || no "useless metrics wrong: $m"

# ── 3) balanced: near the main sequence -> zone="ok" ───────────────────────────────────────────────────
m="$( mod "$OUT" balanced )"
hasall "$m" 'ca="1"' 'ce="1"' 'I="0.50"' 'A="0.50"' 'D="0.00"' 'zone="ok"' \
    && ok "balanced = half-abstract half-coupled, Ca1 Ce1 I0.50 A0.50 D0.00 -> zone=ok" || no "balanced metrics wrong: $m"

# ── 4) consumer: driver module, ZERO types -> zone=n/a regardless of D (§P6.5) ──────────────────────────
m="$( mod "$OUT" consumer )"
hasall "$m" 'ca="0"' 'ce="2"' 'types="0"' 'I="1.00"' 'A="0.00"' 'D="0.00"' 'zone="n/a"' \
    && ok "consumer = driver module, ZERO types, Ca0 Ce2 I1.00 A0.00 D0.00 -> zone=n/a (not the old accidental 'ok')" \
    || no "consumer metrics wrong: $m"

# ── 4b) zone_pain / zone_useless summary counts on <metrics> — exactly 1 pain + 1 useless in this fixture ──
printf '%s' "$OUT" | grep -q 'zone_pain="1"' && printf '%s' "$OUT" | grep -q 'zone_useless="1"' \
    && ok "metrics summary zone_pain=1 zone_useless=1 (matches the one pain + one useless module)" \
    || no "metrics zone_pain/zone_useless summary counts wrong"

# §P6.5: consumer is the only typeless module in this fixture -> zone_na=1, typed_modules=3 (pain/useless/balanced).
printf '%s' "$OUT" | grep -q 'zone_na="1"' && printf '%s' "$OUT" | grep -q 'typed_modules="3"' \
    && ok "metrics summary zone_na=1 typed_modules=3 (consumer excluded, the other 3 modules carry types)" \
    || { no "metrics zone_na/typed_modules summary counts wrong"; printf '%s' "$OUT" | grep -o '<metrics[^>]*>'; }

# ── 5) determinism — the zone attribute (and full metrics block) is byte-identical run-to-run ─────────
OUT2="$( arch "$FIX/zone.arch" )"
[ "$OUT" = "$OUT2" ] && ok "deterministic (zone + full --arch metrics byte-identical across runs)" \
    || no "non-deterministic --arch output"

# ── 6) mutation: give Shape::area() a BODY (no longer a bodyless/pure-virtual decl) -> useless's A flips
#      1.00 -> 0.00; I stays 1.00 (Ca/Ce untouched) -> D = |0+1-1| = 0.00, past the threshold no longer
#      -> zone flips useless -> ok. Proves the classification tracks the computed A/I (not a hardcoded
#      per-path label) — a single-type-body edit changes ONLY A, and that alone moves the zone. ────────
cp -R "$FIX" "$TMP/mut"
cat > "$TMP/mut/src/useless/shape.h" <<'EOF'
#pragma once
// mutated: Shape::area now has a BODY -> no longer abstract -> A flips 1.00 -> 0.00.
#include "../pain/util.h"

struct Shape
{
    virtual double area() { return 0.0; }
};
EOF
MOUT="$( "$BIN" "$TMP/mut" --arch="$TMP/mut/zone.arch" --no-cache 2>/dev/null )"
mm="$( mod "$MOUT" useless )"
hasall "$mm" 'ca="0"' 'ce="1"' 'I="1.00"' 'A="0.00"' 'D="0.00"' 'zone="ok"' \
    && ok "mutation: Shape::area() gains a body -> useless's A flips 1.00->0.00 -> zone flips useless->ok (tracks A/I, not path)" \
    || no "mutation did not flip zone as expected: $mm"

# ── 7) xml well-formed (G4) ─────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$OUT" | xmllint --noout - 2>/dev/null && ok "xml well-formed (arch + metrics + zone)" || no "xml malformed"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

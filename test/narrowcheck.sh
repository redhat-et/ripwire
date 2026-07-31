#!/usr/bin/env bash
# narrowcheck.sh — gate for P2-D Rule 2 receiver-VARIABLE type narrowing (ABS-1 / locals-style scoping).
#
# The narrow: `Foo x; x.run()` and `auto y = Bar(); y.run()` resolve run to Foo::run / Bar::run ONLY
# (the var's type is known), instead of the bare §2a ladder's WRONG 1/k split across every same-named
# `run`. The soundness discipline (resolve.h::rule2RecvVarType) is "a wrong narrow is worse than no
# narrow": it fires ONLY when the var has a known, non-tombstoned type binding whose class actually
# DEFINES the called method (canonByName hit) — otherwise it degrades to §2a unchanged.
#
# The fixture pairs each narrowed caller with a NEGATIVE CONTROL of the SAME call shape whose receiver
# is a function PARAMETER (`Foo* p; p->run()`) — no local var→type binding, so Rule 2 can't fire and the
# call stays HONESTLY AMBIGUOUS. The narrowed-vs-control contrast is the proof the narrow is REAL (a
# binding-driven resolution, not a vacuously-unambiguous fixture).
#
# Usage:
#   CTXPACK_BIN=build/ctxpack bash test/narrowcheck.sh
#   CTXPACK_BIN=asan/ctxpack  bash test/narrowcheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative CTXPACK_BIN
FIX="$ROOT/test/narrowfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/narrowfix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "narrowcheck: BIN=$BIN  CORPUS=test/narrowfix"

"$BIN" "$FIX" --no-cache >"$TMP/map" 2>/dev/null

# ── 1) headline: exactly ONE ambiguous call remains — the parameter control. The two local-var callers
#       (cpp g, py g) narrowed away their ambiguity entirely. ─────────────────────────────────────────
amb="$( grep -o 'ambiguous=[0-9]*' "$TMP/map" | head -1 | grep -o '[0-9]*' )"
[ "$amb" = "1" ] && ok "exactly one ambiguous call remains (ambiguous=1 — only the param control)" \
                 || no "ambiguous=$amb (expected 1: the two local-var calls should narrow, the param stays split)"

# ── 2) the parameter control `h` (Foo* p; p->run()) MUST stay ambiguous — no var→type binding for a param,
#       so Rule 2 cannot fire and the call honestly splits to BOTH run defs. ──────────────────────────────
grep -q 'n="h" amb="1"' "$TMP/map" \
    && ok "param control h() stays AMBIGUOUS (amb=1 — proves the narrow needs a real binding)" \
    || { no "param control h() is not amb=1 (the negative control failed — narrow may be vacuous)"; grep -o 'n="h"[^>]*' "$TMP/map" | head; }

# ── 3) the local-var callers `g` (cpp `Foo x`/`auto y=Bar()`, py `x=Foo()`) MUST be narrowed → NO amb= marker.
#       (Same call shape as the control; the ONLY difference is the local binding ⇒ this is the real-narrow proof.)
if grep -oE 'n="g"[^>]*' "$TMP/map" | grep -q 'amb='; then
    no "a local-var caller g() is still marked ambiguous (narrow did not fire)"; grep -oE 'n="g"[^>]*' "$TMP/map"
else
    ok "local-var callers g() are NARROWED (no amb= — x.run→Foo::run, y.run→Bar::run resolved 1:1)"
fi

# ── 4) under-link guard: the narrow must RESOLVE the calls, not DROP them. The cpp caller still has BOTH
#       run edges, pointing at the two distinct run DEFS (Foo::run and Bar::run) — one each, not zero, not 4. ─
ce="$( "$BIN" "$FIX" --callees=g --no-cache 2>/dev/null )"
nruncpp="$( printf '%s' "$ce" | grep -o 'n="run"[^>]*cpp/recv.cpp:[0-9]*' | sort -u | wc -l | tr -d ' ' )"
[ "$nruncpp" = "2" ] \
    && ok "cpp g() keeps BOTH run edges to distinct defs (no edge dropped, no cross-edge — $nruncpp targets)" \
    || { no "cpp g() has $nruncpp distinct run targets (want 2: Foo::run + Bar::run)"; printf '%s\n' "$ce" | tr '>' '\n' | grep run; }

# ── 5) determinism — the binding capture + narrow must be byte-stable run-to-run. ───────────────────────
"$BIN" "$FIX" --no-cache >"$TMP/map2" 2>/dev/null
diff -q "$TMP/map" "$TMP/map2" >/dev/null \
    && ok "deterministic (narrowfix map byte-identical across two runs)" \
    || { no "non-deterministic narrowfix map"; diff "$TMP/map" "$TMP/map2" | head -6; }

# ── 6) cache transparency — narrowing facts (RawBind) survive the incremental cache: warm == cold. ──────
rm -f "$TMP/nc"
"$BIN" "$FIX" --cache="$TMP/nc" >/dev/null 2>&1
"$BIN" "$FIX" --cache="$TMP/nc" >"$TMP/warm" 2>/dev/null
"$BIN" "$FIX" --no-cache        >"$TMP/cold" 2>/dev/null
diff -q "$TMP/warm" "$TMP/cold" >/dev/null \
    && ok "cache-transparent (bindings round-trip: warm == cold)" \
    || { no "binding cache changes output (warm != cold)"; diff "$TMP/cold" "$TMP/warm" | head -6; }

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

#!/usr/bin/env bash
# resolvecheck.sh — the P2-D one-hop type-narrowing gate (Rule 1: class membership).
#
#   test/resolvecheck.sh                       # uses build/ctxpack on test/resolvefix
#   CTXPACK_BIN=asan/ctxpack test/resolvecheck.sh
#
# The fixture test/resolvefix/shapes.cpp has two classes A and B that BOTH define process();
# A::run() calls this->process(). Under the bare §2a ladder `process` is ambiguous and run gets
# an edge to BOTH A::process and B::process (amb=1). With Rule 1, this->process() resolves to the
# caller's enclosing class A only → one callee edge, ambiguous=0. The script asserts that narrowed
# result AND determinism (run twice, byte-identical). Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative CTXPACK_BIN
CORPUS="$ROOT/test/resolvefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "resolvecheck: BIN=$BIN  CORPUS=$CORPUS"

# 1) determinism — same input, byte-identical output run-to-run (narrowing must stay deterministic)
"$BIN" "$CORPUS" --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$CORPUS" --no-cache >"$TMP/b" 2>/dev/null
diff -q "$TMP/a" "$TMP/b" >/dev/null && ok "determinism (byte-identical, $(wc -c <"$TMP/a" | tr -d ' ') B)" || no "determinism (non-deterministic output)"

# 2) Rule 1 — this->process() narrows: run has EXACTLY ONE callee, pointing at A::process (line 25),
#    NOT B::process (line 30). --callees lists the resolved out-edges with file:line.
CALLEES="$( "$BIN" "$CORPUS" --callees=run --no-cache 2>/dev/null )"
NEDGE="$( printf '%s' "$CALLEES" | grep -o 'count="[0-9]*"' | grep -o '[0-9]*' )"
[ "$NEDGE" = "1" ] && ok "Rule 1: run has exactly one callee edge (was 2)" || { no "Rule 1: run callee count = ${NEDGE:-?} (expected 1)"; printf '    %s\n' "$CALLEES"; }
printf '%s' "$CALLEES" | grep -q 'shapes.cpp:25' && ok "Rule 1: the edge points at A::process (shapes.cpp:25)" || { no "Rule 1: edge does not point at A::process (shapes.cpp:25)"; printf '    %s\n' "$CALLEES"; }
printf '%s' "$CALLEES" | grep -q 'shapes.cpp:30' && { no "Rule 1: a WRONG edge to B::process (shapes.cpp:30) survived"; printf '    %s\n' "$CALLEES"; } || ok "Rule 1: no wrong edge to B::process (shapes.cpp:30)"

# 3) ambiguous= header count is zero on the fixture (the narrow removed the only ambiguous call)
AMB="$( "$BIN" "$CORPUS" --no-cache 2>/dev/null | grep -o 'ambiguous=[0-9]*' | grep -o '[0-9]*' )"
[ "$AMB" = "0" ] && ok "ambiguous=0 on the fixture (was 1)" || no "ambiguous=$AMB on the fixture (expected 0)"

# 4) the narrow did not delete the run symbol or corrupt the map (still well-formed, run still present)
MAP="$( "$BIN" "$CORPUS" --no-cache 2>/dev/null )"
printf '%s' "$MAP" | grep -q 'n="run"' && ok "run symbol still present (no symbol loss)" || no "run symbol vanished"
command -v xmllint >/dev/null 2>&1 && { printf '%s' "$MAP" | xmllint --noout - 2>/dev/null && ok "xml well-formed" || no "xml malformed"; } || ok "xml well-formed (xmllint absent — skipped)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"

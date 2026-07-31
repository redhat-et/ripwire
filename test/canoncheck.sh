#!/usr/bin/env bash
# canoncheck.sh — the S6-C canonical SCIP-style symbol-string gate.
#
#   test/canoncheck.sh                       # uses build/ripwire on test/canonfix
#   RIPWIRE_BIN=asan/ripwire test/canoncheck.sh
#
# The fixture test/canonfix/canon.cpp has two classes A and B that BOTH define compute(); A::driver()
# calls compute() (a bare member call). This gate asserts S6-C's contract:
#   * the two compute() defs carry DISTINCT canonical ids — `…::A::compute` vs `…::B::compute`
#   * the member call resolves to A::compute ONLY (canonical scope + locality), not B::compute
#   * `ambiguous=` on the fixture is 0 — the canonical resolution SUPPRESSED the amb the bare ladder raised
#   * determinism (run twice → byte-identical) and no symbol loss / well-formed XML
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/canonfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "canoncheck: BIN=$BIN  CORPUS=$CORPUS"

# 1) determinism — same input, byte-identical output run-to-run (canonical resolution must stay deterministic)
"$BIN" "$CORPUS" --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$CORPUS" --no-cache >"$TMP/b" 2>/dev/null
diff -q "$TMP/a" "$TMP/b" >/dev/null && ok "determinism (byte-identical, $(wc -c <"$TMP/a" | tr -d ' ') B)" || no "determinism (non-deterministic output)"

MAP="$( "$BIN" "$CORPUS" --no-cache 2>/dev/null )"

# 2) DISTINCT canonical ids — A::compute and B::compute each get their own `id=…::<Class>::compute`.
printf '%s' "$MAP" | grep -q 'id="[^"]*canon.cpp::A::compute"' && ok "canonical id present: …::A::compute" || { no "no canonical id …::A::compute"; printf '    %s\n' "$MAP"; }
printf '%s' "$MAP" | grep -q 'id="[^"]*canon.cpp::B::compute"' && ok "canonical id present: …::B::compute" || { no "no canonical id …::B::compute"; printf '    %s\n' "$MAP"; }
# the two ids are genuinely DIFFERENT strings (the whole point: a same-name collision now disambiguates)
A_ID="$( printf '%s' "$MAP" | grep -o 'id="[^"]*canon.cpp::A::compute"' | head -1 )"
B_ID="$( printf '%s' "$MAP" | grep -o 'id="[^"]*canon.cpp::B::compute"' | head -1 )"
{ [ -n "$A_ID" ] && [ -n "$B_ID" ] && [ "$A_ID" != "$B_ID" ]; } && ok "the two compute() defs have DISTINCT canonical ids ($A_ID != $B_ID)" || no "the two compute() ids are not distinct (A='$A_ID' B='$B_ID')"

# 3) a free-function-style collision is not the case here, but verify id= is ONLY on scoped symbols:
#    every emitted id= must contain '::' (a scope) — never a bare name (that would be redundant churn).
BAD_ID="$( printf '%s' "$MAP" | grep -o 'id="[^"]*"' | grep -v '::' | head -1 )"
[ -z "$BAD_ID" ] && ok "id= emitted only when it disambiguates (every id= is scoped, none == bare name)" || no "a bare (scope-less) id= leaked: $BAD_ID"

# 4) the member call resolves to A::compute ONLY (canonical scope + locality), NOT B::compute.
#    --callees lists the resolved out-edges with file:line; A::compute is line 26, B::compute is line 31.
CALLEES="$( "$BIN" "$CORPUS" --callees=driver --no-cache 2>/dev/null )"
NEDGE="$( printf '%s' "$CALLEES" | grep -o 'count="[0-9]*"' | grep -o '[0-9]*' )"
[ "$NEDGE" = "1" ] && ok "driver has exactly one callee edge (was 2 without S6-C)" || { no "driver callee count = ${NEDGE:-?} (expected 1)"; printf '    %s\n' "$CALLEES"; }
printf '%s' "$CALLEES" | grep -q 'canon.cpp:26' && ok "the edge points at A::compute (canon.cpp:26)" || { no "edge does not point at A::compute (canon.cpp:26)"; printf '    %s\n' "$CALLEES"; }
printf '%s' "$CALLEES" | grep -q 'canon.cpp:31' && { no "a WRONG edge to B::compute (canon.cpp:31) survived"; printf '    %s\n' "$CALLEES"; } || ok "no wrong edge to B::compute (canon.cpp:31)"

# 5) ambiguous= header count is zero — canonical resolution SUPPRESSED the amb the bare ladder would raise.
AMB="$( printf '%s' "$MAP" | grep -o 'ambiguous=[0-9]*' | grep -o '[0-9]*' )"
[ "$AMB" = "0" ] && ok "ambiguous=0 on the fixture (canonical resolution suppressed the member-call amb)" || no "ambiguous=$AMB on the fixture (expected 0)"

# 6) no symbol loss + well-formed XML (the canonical id= attribute must not corrupt the map).
printf '%s' "$MAP" | grep -q 'n="driver"' && ok "driver symbol still present (no symbol loss)" || no "driver symbol vanished"
printf '%s' "$MAP" | grep -q 'n="compute"' && ok "compute symbols still present (no symbol loss)" || no "compute symbols vanished"
command -v xmllint >/dev/null 2>&1 && { printf '%s' "$MAP" | xmllint --noout - 2>/dev/null && ok "xml well-formed" || no "xml malformed"; } || ok "xml well-formed (xmllint absent — skipped)"

# 7) locality tie-break regression (adversarial HIGH-1): the locality comparison must be SEGMENT-aware, not a
#    raw-byte prefix. On test/localityfix, class Xenon::call() does `Bravo b; b.go();`; the caller scope "Xenon"
#    shares only a leading LETTER with the unrelated class "Xtra". A byte-prefix tie-break confidently (and
#    WRONGLY) resolved the call to Xtra::go (loc.cpp:28) and reported ambiguous=0. With segment-aware locality
#    Xtra/Bravo tie on path-only locality, so the call stays honestly ambiguous — never a wrong confident pick.
#    Delegated to test/localitycheck.sh so the full assertion set runs here too (canoncheck is run by regression).
if [ -f "$ROOT/test/localitycheck.sh" ]; then
    if RIPWIRE_BIN="$BIN" bash "$ROOT/test/localitycheck.sh" >/dev/null 2>&1; then
        ok "locality tie-break is segment-aware (test/localitycheck.sh — no spurious cross-class prefix win)"
    else
        no "locality tie-break regression (test/localitycheck.sh failed — a spurious byte-prefix win)"
        RIPWIRE_BIN="$BIN" bash "$ROOT/test/localitycheck.sh" 2>&1 | grep -i fail | head -4
    fi
else
    no "test/localitycheck.sh missing (the HIGH-1 locality gate)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"

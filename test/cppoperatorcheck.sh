#!/usr/bin/env bash
# cppoperatorcheck.sh — C++ operator-method capture gate.
#
# WHY THIS EXISTS: ctxpack is run mostly on C++ codebases, yet before this gate every C++ OPERATOR
# method was INVISIBLE — the upstream C++ tags.scm captures methods only via identifier /
# field_identifier / qualified_identifier declarators, but an operator's declarator is a DIFFERENT
# tree-sitter node kind (`operator_name` for symbolic/subscript/call/arrow ops, `operator_cast` for
# conversion ops), so no pattern matched them. `operator==`, `operator=`, `operator[]`, `operator<<`,
# `operator<=>`, `operator bool`, … never appeared as symbols → absent from --metrics,
# --pack-signatures, --callees, ranking and the Lego <m> contract.
#
# THE FIX (what this gate pins):
#   1. queries/cpp/tags.scm gained three @definition.method patterns — one per operator declarator kind
#      (member `operator_name`, out-of-line `qualified_identifier name:(operator_name)`, and the
#      conversion `operator_cast`).
#   2. src/ingest.cpp: finalSegment() no longer truncates an operator name at its first '<' (the
#      generic-type-arg strip was eating `operator<` / `operator<<` / `operator<=>` down to bare
#      `operator`); and the operator_cast declarator's name is trimmed to `operator <type>` (its raw
#      span is the whole `operator bool() const`).
#
# EMPIRICALLY-CONFIRMED node kinds (tree-sitter-cpp v0.23.4), verified with `ctxpack --match` before
# any assertion below was written:
#   bool operator==(...) / operator= / operator+ / operator[] / operator() / operator-> / operator</
#   operator<< / operator<= / operator<=> / operator& / operator&& / operator>   → declarator kind
#     `operator_name` (the @name span is the whole token, e.g. `operator<<`).
#   operator bool() / operator double()  → declarator kind `operator_cast` (a DISTINCT node; its own
#     text spans `operator bool() const`, trimmed by ingest to the `operator <type>` name).
#   Vec::operator==(...) { ... } out-of-line  → `qualified_identifier name:(operator_name)`.
#
# CRITICAL PROPERTY — XML SAFETY: operators whose NAME contains XML-special chars (`operator<<`,
# `operator<=>`, `operator<`, `operator&`, `operator&&`, `operator>`) MUST appear XML-ESCAPED in the
# output (`operator&lt;&lt;`, `operator&lt;=&gt;`, `operator&amp;`, …) and `xmllint --noout` must be
# CLEAN. This is the #1 correctness risk and is asserted explicitly below.
#
# CALL-EDGE LIMITATION (documented, out of scope, NOT tested as a positive): `a == b` parses as a
# binary_expression, not a call_expression, so ctxpack cannot resolve the implicit call to operator==
# without semantic overload resolution (outside the tool's contract). Operators are captured as
# DEFINITIONS only; their fan-in stays low. This gate does NOT assert an implicit-operator call edge.
#
# FAILS-ON-HEAD: run against a pre-fix binary (operators absent), the operator-name and escaping
# assertions FAIL — this is a real regression test, not a tautology. (Verified during development:
# a HEAD build reports `symbols=1` on this fixture — only the Vec class, zero operators.)
#
# Usage:
#   test/cppoperatorcheck.sh
#   CTXPACK_BIN=asan/ctxpack test/cppoperatorcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success. Does NOT edit
# regression.sh. Uses --no-cache throughout so a stale warm cache can never mask a real change.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/cppopfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required for the escaping proof"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "cppoperatorcheck: BIN=$BIN  FIX=$FIX"

MAP="$TMP/map.xml"
"$BIN" --no-cache "$FIX" >"$MAP" 2>"$TMP/map.err"
MAP_EXIT=$?
[ "$MAP_EXIT" -eq 0 ] && ok "default map: exits 0 on operator fixture" || no "default map: exited $MAP_EXIT: $( cat "$TMP/map.err" )"

# ── the escaping proof: xmllint MUST be clean on every view that names operators ─────────────────
for FLAG in "" "--pack-signatures" "--metrics"; do
    "$BIN" --no-cache $FLAG "$FIX" 2>/dev/null | xmllint --noout - 2>/dev/null \
        && ok "xmllint --noout CLEAN on operator output [${FLAG:-default}]" \
        || no "xmllint --noout DIRTY on operator output [${FLAG:-default}] — XML escaping is broken"
done

# grep the emitted symbol names once (from --pack-signatures; every captured symbol appears there).
SIG="$TMP/sig.xml"
"$BIN" --no-cache --pack-signatures "$FIX" >"$SIG" 2>/dev/null

# has_name <literal n="..."> — assert an operator symbol with EXACTLY this (already-escaped) name exists.
has_name(){ grep -q "n=\"$1\"" "$SIG"; }

echo
echo "=== symbolic / subscript / call / arrow operators captured (operator_name declarator) ==="
has_name 'operator=='       && ok "operator== captured"       || no "operator== NOT captured"
has_name 'operator='        && ok "operator= captured"        || no "operator= NOT captured"
has_name 'operator+'        && ok "operator+ captured"        || no "operator+ NOT captured"
has_name 'operator\[\]'     && ok "operator[] captured"       || no "operator[] NOT captured"
has_name 'operator()'       && ok "operator() captured"       || no "operator() NOT captured"
has_name 'operator-&gt;'    && ok "operator-> captured (escaped operator-&gt;)" || no "operator-> NOT captured / not escaped"

echo
echo "=== XML-SPECIAL operator names — MUST be present AND XML-escaped ==="
has_name 'operator&lt;'         && ok "operator<  -> escaped operator&lt;"          || no "operator< missing or unescaped"
has_name 'operator&lt;&lt;'     && ok "operator<< -> escaped operator&lt;&lt;"       || no "operator<< missing or unescaped"
has_name 'operator&lt;='        && ok "operator<= -> escaped operator&lt;="          || no "operator<= missing or unescaped"
has_name 'operator&lt;=&gt;'    && ok "operator<=> (spaceship) -> escaped operator&lt;=&gt;" || no "operator<=> missing or unescaped"
has_name 'operator&amp;'        && ok "operator&  -> escaped operator&amp;"          || no "operator& missing or unescaped"
has_name 'operator&amp;&amp;'   && ok "operator&& -> escaped operator&amp;&amp;"      || no "operator&& missing or unescaped"
has_name 'operator&gt;'         && ok "operator>  -> escaped operator&gt;"           || no "operator> missing or unescaped"

# a bare `operator` (name truncated at '<') is the pre-fix regression — assert it NEVER appears.
grep -q 'n="operator"' "$SIG" \
    && no "a bare n=\"operator\" leaked — an operator name was truncated (finalSegment '<'-strip regression)" \
    || ok "no bare n=\"operator\" — no operator name truncated at '<'"

echo
echo "=== conversion operator (operator_cast declarator) captured with 'operator <type>' name ==="
has_name 'operator bool'    && ok "operator bool captured (conversion, operator_cast)"   || no "operator bool NOT captured"
has_name 'operator double'  && ok "operator double captured (conversion, operator_cast)" || no "operator double NOT captured"
# the conversion name must NOT carry the param list / const from the operator_cast span.
grep -q 'n="operator bool()' "$SIG" \
    && no "operator bool name includes the param list — operator_cast trim failed" \
    || ok "operator bool name trimmed to 'operator bool' (no param list)"

echo
echo "=== out-of-line qualified operator definitions (vec.cpp: Vec::operator==, Vec::operator=) ==="
# The .cpp out-of-line def is captured (in addition to the header decl) — assert operator== appears
# with vec.cpp as a source file somewhere in the map. Use the raw map (carries file paths + symbols).
"$BIN" --no-cache "$FIX" 2>/dev/null | grep -q 'vec.cpp' \
    && ok "vec.cpp (out-of-line operator defs) present in the map" \
    || no "vec.cpp not present in the map"
# operator== and operator= must EACH appear at least twice (header decl + out-of-line def).
CNT_EQEQ="$( grep -o 'n="operator=="' "$SIG" | wc -l | tr -d ' ' )"
CNT_EQ="$( grep -o 'n="operator="' "$SIG" | wc -l | tr -d ' ' )"
[ "$CNT_EQEQ" -ge 2 ] && ok "operator== appears >=2x (header decl + out-of-line Vec::operator== def): $CNT_EQEQ" \
                      || no "expected operator== >=2 (decl + out-of-line def), got $CNT_EQEQ"
[ "$CNT_EQ" -ge 2 ]   && ok "operator= appears >=2x (header decl + out-of-line Vec::operator= def): $CNT_EQ" \
                      || no "expected operator= >=2 (decl + out-of-line def), got $CNT_EQ"

echo
echo "=== Lego <m> contract lists operators for a base type that has them ==="
# A conversion + comparison operators on a base with an implementor must show up in the <m> contract,
# XML-escaped, alongside regular methods. Build a tiny throwaway fixture for this (needs an implementor
# for the type to be surfaced as an <iface>).
LEGO="$TMP/lego"; mkdir -p "$LEGO"
cat > "$LEGO/shape.h" <<'EOF'
struct Shape
{
    virtual double area() const = 0;
    bool operator==( const Shape& o ) const;
    bool operator<( const Shape& o ) const;
};
struct Circle : Shape { double area() const override; };
EOF
LEGO_OUT="$( "$BIN" --no-cache --lego=Shape "$LEGO" 2>/dev/null )"
echo "$LEGO_OUT" | grep -q '<m[^>]*>bool operator==(' \
    && ok "Lego <m> contract lists operator== for Shape" \
    || no "Lego <m> contract missing operator== for Shape"
echo "$LEGO_OUT" | grep -q '<m[^>]*>bool operator&lt;(' \
    && ok "Lego <m> contract lists operator< (escaped operator&lt;) for Shape" \
    || no "Lego <m> contract missing/unescaped operator< for Shape"
echo "$LEGO_OUT" | xmllint --noout - 2>/dev/null \
    && ok "Lego view xmllint --noout CLEAN" || no "Lego view xmllint DIRTY"

echo
echo "=== determinism: default map twice (no-cache), byte-identical ==="
"$BIN" --no-cache "$FIX" >"$TMP/det_a" 2>/dev/null
"$BIN" --no-cache "$FIX" >"$TMP/det_b" 2>/dev/null
diff -q "$TMP/det_a" "$TMP/det_b" >/dev/null \
    && ok "determinism: operator map byte-identical across two runs" \
    || no "determinism: operator map differs across runs"

echo
echo "=== mutation self-test: rename an operator method → its symbol name changes ==="
# Proves the assertions above are wired to the actual fixture, not passing vacuously: copy the fixture,
# turn `operator<<` into `operator>>` and confirm the emitted name set changes accordingly.
MUT="$TMP/mut"; mkdir -p "$MUT"
sed 's/operator<<( int n ) const/operator>>( int n ) const/' "$FIX/vec.h" >"$MUT/vec.h"
MUT_SIG="$( "$BIN" --no-cache --pack-signatures "$MUT" 2>/dev/null )"
echo "$MUT_SIG" | grep -q 'n="operator&gt;&gt;"' \
    && ok "mutation: operator>> now captured (escaped operator&gt;&gt;)" \
    || no "mutation: operator>> not captured after rename — assertions may be vacuous"
# and the original file (unmutated) must still NOT have operator>>
grep -q 'n="operator&gt;&gt;"' "$SIG" \
    && no "mutation self-test invalid: original fixture already had operator>>" \
    || ok "mutation self-test valid: original fixture had no operator>>"

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi

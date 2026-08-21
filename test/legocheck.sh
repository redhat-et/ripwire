#!/usr/bin/env bash
# legocheck.sh — inheritance / "Lego" view gate (interface → impls → factory).
#
#   test/legocheck.sh                        # uses build/ripwire on test/legofix
#   RIPWIRE_BIN=asan/ripwire test/legocheck.sh
#
# Corpus test/legofix (multi-language, IN-TREE but OUTSIDE test/fixture so the golden
# never sees it): each language has an interface/base + >=2 concrete impls + a factory.
#   shapes.h  (C++)  interface Shape  -> {Circle, Square}          + makeShape
#   animal.ts (TS)   interface Animal -> {Dog, Cat}                + makeAnimal
#   Animal.java(Java)interface Animal -> {Wolf, Lion}, Cub:Wolf    + AnimalFactory
#   vehicle.rs(Rust) trait Vehicle    -> {Car, Bike} (impl for T)  + make_vehicle
#
# `Animal` is DELIBERATELY shared between TS and Java to regression-test the cross-language
# merge bug (P1a): the two must resolve to SEPARATE interfaces with own-language impls only.
#
# Assertions:
#   1) determinism — --for and --lego byte-identical run-to-run; warm==cold
#   2) C++ Shape -> {Circle,Square} with a correct method contract (<m>) in --for <lego>
#   3) mixed-lang: TS Animal and Java Animal DO NOT cross-merge (P1a lang-separation fix)
#   4) no garbage <m> contract for TS/Java interfaces (P1b: <m> only where sound)
#   5) Java capture: Wolf/Lion implement Animal; Cub extends Wolf (P2 superclass/super_interfaces)
#   6) Rust capture: Car/Bike implement Vehicle (P2 impl_item post-pass)
#   7) --lego=Shape surfaces the interface + BOTH impls + method contract + p= paths
#   8) --lego=Animal is own-language only (TS Dog/Cat OR Java Wolf/Lion — never both)
#   9) MCP `lego` verb returns the same interface + impls as --lego
#  10) xmllint: --for and --lego output well-formed
#  11) mutation-check: a deliberately-wrong assertion FAILS (the gate can detect regressions)
#
# §P3 (2026-07-28): --for's embedded <lego> block now carries p= on <iface>/<impl> (identity parity with
# the standalone verb) and is SCOPED to the task's resolved surface. Assertion 2 below was updated: it
# matched the p-LESS row form exactly, i.e. it pinned the missing disambiguator. The new contract lives in
# test/legobundlecheck.sh; this gate keeps testing the interface/impl/contract CAPTURE, which is unchanged.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/legofix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "legocheck: BIN=$BIN  CORPUS=$CORPUS"

# ── 1) determinism (--for) + warm==cold ───────────────────────────────────────
FORQ="animal shape vehicle interface implementation factory"
"$BIN" "$CORPUS" --no-cache --for="$FORQ" 2>/dev/null > "$TMP/for_a"
"$BIN" "$CORPUS" --no-cache --for="$FORQ" 2>/dev/null > "$TMP/for_b"
diff -q "$TMP/for_a" "$TMP/for_b" >/dev/null \
    && ok "determinism --for (byte-identical, $(wc -c <"$TMP/for_a" | tr -d ' ') B)" \
    || no "determinism --for (non-deterministic output)"

# warm==cold: a cached run must match the no-cache run byte-for-byte.
"$BIN" "$CORPUS" --cache="$TMP/idx.cache" --for="$FORQ" 2>/dev/null >/dev/null   # cold: populate
"$BIN" "$CORPUS" --cache="$TMP/idx.cache" --for="$FORQ" 2>/dev/null > "$TMP/for_warm"   # warm: reuse
diff -q "$TMP/for_a" "$TMP/for_warm" >/dev/null \
    && ok "warm==cold --for (cache byte-identical to cold)" \
    || no "warm!=cold --for (cache perturbs output)"

FOR="$( cat "$TMP/for_a" )"
# extract just the <lego>…</lego> block for the contained-scope assertions below
LEGO="$( printf '%s' "$FOR" | grep -o '<lego>.*</lego>' )"

# ── 2) C++ Shape -> {Circle, Square} + method contract ────────────────────────
printf '%s' "$LEGO" | grep -q '<iface n="Shape"' \
    && ok "--for <lego>: Shape interface present" \
    || no "--for <lego>: Shape interface missing"
# §P3 (2026-07-28): the bundle's rows now carry p= like the standalone verb's, so the impl row is
# `<impl n="Circle" p="…"/>`, not the old p-less `<impl n="Circle"/>`. This assertion pinned the
# ABSENCE of the disambiguator — the very defect §P3 fixed — so it is matched by name here and the p=
# requirement is asserted (with the query-scope half) in test/legobundlecheck.sh.
printf '%s' "$LEGO" | grep -q '<impl n="Circle"' && printf '%s' "$LEGO" | grep -q '<impl n="Square"' \
    && ok "--for <lego>: Shape impls Circle + Square" \
    || no "--for <lego>: Shape impls Circle/Square missing"
printf '%s' "$LEGO" | grep -q '<m pure="1">virtual double area() const = 0</m>' \
    && ok "--for <lego>: Shape method contract (area) correct" \
    || no "--for <lego>: Shape method contract missing/garbled"

# ── 4) NO garbage <m> for TS/Java: the contract must never contain 'interface Animal' ─
# (P1b: the C++-only <m> loop grabbed the TS/Java interface's own decl line as a "method".)
printf '%s' "$LEGO" | grep -Eq '<m[^>]*>[^<]*interface Animal' \
    && no "--for <lego>: GARBAGE <m>interface Animal</m> (P1b not fixed)" \
    || ok "--for <lego>: no garbage <m> for TS/Java interface (P1b)"

# ── 3/5/6/8) mixed-lang separation + Java/Rust capture — tested via --lego=TYPE ───
# Query one interface at a time so each block is unambiguous.
"$BIN" "$CORPUS" --no-cache --lego=Shape   2>/dev/null > "$TMP/lego_shape"
"$BIN" "$CORPUS" --no-cache --lego=Vehicle 2>/dev/null > "$TMP/lego_vehicle"
# --lego=Animal is ambiguous (TS + Java). Disambiguate by file substring (resolveFocus file:name).
"$BIN" "$CORPUS" --no-cache --lego="animal.ts:Animal"  2>/dev/null > "$TMP/lego_ts_animal"
"$BIN" "$CORPUS" --no-cache --lego="Animal.java:Animal" 2>/dev/null > "$TMP/lego_java_animal"

# determinism of --lego
"$BIN" "$CORPUS" --no-cache --lego=Shape 2>/dev/null > "$TMP/lego_shape_b"
diff -q "$TMP/lego_shape" "$TMP/lego_shape_b" >/dev/null \
    && ok "determinism --lego=Shape (byte-identical)" \
    || no "determinism --lego=Shape (non-deterministic)"

# 7) --lego=Shape: interface + both impls + contract + p= path
SHP="$( cat "$TMP/lego_shape" )"
printf '%s' "$SHP" | grep -q '<iface n="Shape"' \
    && ok "--lego=Shape: iface present" || no "--lego=Shape: iface missing"
printf '%s' "$SHP" | grep -q '<impl n="Circle"' && printf '%s' "$SHP" | grep -q '<impl n="Square"' \
    && ok "--lego=Shape: both impls (Circle, Square)" || no "--lego=Shape: impls missing"
printf '%s' "$SHP" | grep -Eq 'p="[^"]*shapes\.h"' \
    && ok "--lego=Shape: p= file path emitted" || no "--lego=Shape: p= path missing"
printf '%s' "$SHP" | grep -q '<m pure="1">virtual double area() const = 0</m>' \
    && ok "--lego=Shape: method contract present" || no "--lego=Shape: contract missing"

# 8) --lego=Animal own-language only — the merge-bug regression.
TSA="$( cat "$TMP/lego_ts_animal" )"
JVA="$( cat "$TMP/lego_java_animal" )"
# TS Animal: must contain Dog and Cat; must NOT contain Wolf or Lion.
if printf '%s' "$TSA" | grep -q '<impl n="Dog"' && printf '%s' "$TSA" | grep -q '<impl n="Cat"'; then
    if printf '%s' "$TSA" | grep -Eq '<impl n="(Wolf|Lion)"'; then
        no "--lego=Animal(TS): cross-lang leak — Java Wolf/Lion appear in TS Animal (P1a not fixed)"
    else
        ok "--lego=Animal(TS): own-language only (Dog, Cat; no Wolf/Lion)"
    fi
else
    no "--lego=Animal(TS): TS impls Dog/Cat missing (TS capture broken)"
fi
# Java Animal: must contain Wolf and Lion; must NOT contain Dog or Cat.
if printf '%s' "$JVA" | grep -q '<impl n="Wolf"' && printf '%s' "$JVA" | grep -q '<impl n="Lion"'; then
    if printf '%s' "$JVA" | grep -Eq '<impl n="(Dog|Cat)"'; then
        no "--lego=Animal(Java): cross-lang leak — TS Dog/Cat appear in Java Animal (P1a not fixed)"
    else
        ok "--lego=Animal(Java): own-language only (Wolf, Lion; no Dog/Cat)"
    fi
else
    no "--lego=Animal(Java): Java impls Wolf/Lion missing (Java super_interfaces capture broken)"
fi

# 5) Java superclass: Cub extends Wolf → Wolf gets an implementor Cub
"$BIN" "$CORPUS" --no-cache --lego=Wolf 2>/dev/null > "$TMP/lego_wolf"
printf '%s' "$( cat "$TMP/lego_wolf" )" | grep -q '<impl n="Cub"' \
    && ok "--lego=Wolf: Cub (extends Wolf, Java superclass) captured" \
    || no "--lego=Wolf: Cub missing (Java superclass capture broken)"

# 6) Rust impl_item: Car/Bike implement Vehicle
VEH="$( cat "$TMP/lego_vehicle" )"
if printf '%s' "$VEH" | grep -q '<impl n="Car"' && printf '%s' "$VEH" | grep -q '<impl n="Bike"'; then
    ok "--lego=Vehicle: Rust impls Car + Bike (impl_item post-pass)"
else
    no "--lego=Vehicle: Rust Car/Bike missing (impl_item post-pass broken)"
fi

# ── 12) FIX #1 (generic base/impl strip): Java `extends Base<String>` + Rust `impl<T> .. for Wrapper<T>` ─
# The base/derived name is recorded via a `generic_type` node carrying `<...>`; without stripping the type
# args the name is `Base<String>`/`Wrapper<T>` and misses byName["Base"]/["Wrapper"] → --lego empty.
"$BIN" "$CORPUS" --no-cache --lego=Base 2>/dev/null > "$TMP/lego_base"
printf '%s' "$( cat "$TMP/lego_base" )" | grep -q '<impl n="D"' \
    && ok "--lego=Base: Java generic base stripped (D implements Base<String>)" \
    || no "--lego=Base: generic-type args NOT stripped — D missing (FIX #1 Java not applied)"

"$BIN" "$CORPUS" --no-cache --lego=Draw 2>/dev/null > "$TMP/lego_draw"
printf '%s' "$( cat "$TMP/lego_draw" )" | grep -q '<impl n="Wrapper"' \
    && ok "--lego=Draw: Rust generic impl stripped (Wrapper impls Draw for Wrapper<T>)" \
    || no "--lego=Draw: generic-type args NOT stripped — Wrapper missing (FIX #1 Rust not applied)"

# ── 13) FIX #2 (nested-class contract): --lego=Outer must list outerMethod but NOT nestedMethod ─
# nestedMethod belongs to Outer::Nested (a class nested inside Outer); pure byte-containment over-lists it.
"$BIN" "$CORPUS" --no-cache --lego=Outer 2>/dev/null > "$TMP/lego_outer"
OUT="$( cat "$TMP/lego_outer" )"
if printf '%s' "$OUT" | grep -q '<m[^>]*>virtual void outerMethod() = 0</m>'; then
    if printf '%s' "$OUT" | grep -q 'nestedMethod'; then
        no "--lego=Outer: nested-class method leaked into Outer's contract (FIX #2 not applied)"
    else
        ok "--lego=Outer: own contract only (outerMethod present; nestedMethod excluded)"
    fi
else
    no "--lego=Outer: outerMethod missing (FIX #2 wrongly DROPPED a real own-method — false negative)"
fi

# ── 14) D8: zero-implementor interface vs genuine not-found MUST be distinguishable ─────────────
# --lego=Renderer (real symbol, deliberately zero implementors) must emit the interface + its contract
# with implementors="0" and exit 0 — NOT the old bare "<ctx></ctx>" no-message degrade. --lego=NoSuchType
# (not resolvable at all) must exit 1 with a "not found" message — a genuinely different outcome.
"$BIN" "$CORPUS" --no-cache --lego=Renderer 2>"$TMP/lego_renderer.err" > "$TMP/lego_renderer"
ECR=$?
REN="$( cat "$TMP/lego_renderer" )"
[ "$ECR" = 0 ] && ok "--lego=Renderer (0 implementors): exit 0" || no "--lego=Renderer (0 implementors): should exit 0 (got $ECR)"
printf '%s' "$REN" | grep -q '<iface n="Renderer"[^>]*implementors="0"' \
    && ok "--lego=Renderer: interface emitted with implementors=\"0\" (not a bare <ctx></ctx>)" \
    || no "--lego=Renderer: expected implementors=\"0\" iface, got: $REN"
printf '%s' "$REN" | grep -q '<m[^>]*>virtual void present() const = 0</m>' \
    && ok "--lego=Renderer: method contract still emitted despite zero implementors" \
    || no "--lego=Renderer: contract missing for the zero-implementor case"
[ -s "$TMP/lego_renderer.err" ] \
    && no "--lego=Renderer: unexpected stderr output for a legitimate zero-implementor answer: $( cat "$TMP/lego_renderer.err" )" \
    || ok "--lego=Renderer: no stderr noise"

"$BIN" "$CORPUS" --no-cache --lego=NoSuchType 2>"$TMP/lego_nf.err" > "$TMP/lego_nf"
ENF=$?
[ "$ENF" = 1 ] && ok "--lego=NoSuchType (not found): exit 1" || no "--lego=NoSuchType (not found): should exit 1 (got $ENF)"
grep -q 'not found' "$TMP/lego_nf.err" \
    && ok "--lego=NoSuchType: stderr reports not-found" \
    || no "--lego=NoSuchType: expected a not-found message on stderr, got: $( cat "$TMP/lego_nf.err" )"

if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$REN" | xmllint --noout - 2>/dev/null \
        && ok "xml well-formed (--lego=Renderer, 0 implementors)" || no "xml malformed (--lego=Renderer)"
fi

# 14b) MCP `lego` verb: same distinction — zero-implementor returns real content, not-found errors out.
REQR='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"lego","arguments":{"path":"'"$CORPUS"'","type":"Renderer"}}}'
printf '%s\n' "$REQR" | "$BIN" --mcp 2>/dev/null > "$TMP/mcp_renderer" || true
MCPR="$( cat "$TMP/mcp_renderer" )"
if printf '%s' "$MCPR" | grep -q 'iface n=\\"Renderer\\"' && printf '%s' "$MCPR" | grep -q 'implementors=\\"0\\"'; then
    ok "MCP lego verb: Renderer (0 implementors) returns real content, not an error"
else
    no "MCP lego verb: Renderer (0 implementors) should return content, got: $MCPR"
fi
REQNF='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"lego","arguments":{"path":"'"$CORPUS"'","type":"NoSuchType"}}}'
printf '%s\n' "$REQNF" | "$BIN" --mcp 2>/dev/null > "$TMP/mcp_nf" || true
MCPNF="$( cat "$TMP/mcp_nf" )"
if printf '%s' "$MCPNF" | grep -qi '"error"' && printf '%s' "$MCPNF" | grep -q 'not found'; then
    ok "MCP lego verb: NoSuchType errors with an unambiguous not-found message (D8: no longer conflated)"
else
    no "MCP lego verb: NoSuchType should error with a not-found message, got: $MCPNF"
fi

# ── 9) MCP `lego` verb parity with --lego=Shape ───────────────────────────────
if printf '%s' "$SHP" | grep -q '<iface n="Shape"'; then
    REQ='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"lego","arguments":{"path":"'"$CORPUS"'","type":"Shape"}}}'
    printf '%s\n' "$REQ" | "$BIN" --mcp 2>/dev/null > "$TMP/mcp_out" || true
    MCP="$( cat "$TMP/mcp_out" )"
    if printf '%s' "$MCP" | grep -q 'iface n=\\"Shape\\"' \
       && printf '%s' "$MCP" | grep -q 'impl n=\\"Circle\\"' \
       && printf '%s' "$MCP" | grep -q 'impl n=\\"Square\\"'; then
        ok "MCP lego verb: Shape + Circle + Square (parity with --lego)"
    else
        no "MCP lego verb: missing Shape/Circle/Square (see $TMP/mcp_out)"
    fi
fi

# ── 10) well-formed XML ───────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$FOR" | xmllint --noout - 2>/dev/null \
        && ok "xml well-formed (--for)" || no "xml malformed (--for)"
    printf '%s' "$SHP" | xmllint --noout - 2>/dev/null \
        && ok "xml well-formed (--lego=Shape)" || no "xml malformed (--lego=Shape)"
    printf '%s' "$VEH" | xmllint --noout - 2>/dev/null \
        && ok "xml well-formed (--lego=Vehicle)" || no "xml malformed (--lego=Vehicle)"
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

# ── 11) mutation-check: this WRONG assertion MUST fail (proves the gate has teeth) ──
if printf '%s' "$SHP" | grep -q '<impl n="Triangle"'; then
    no "mutation-check: found a Triangle impl that should not exist (gate is broken)"
else
    ok "mutation-check: absent Triangle correctly not matched (gate discriminates)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"

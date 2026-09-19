#!/usr/bin/env bash
# jsxcallcheck.sh — #285: a JSX element invocation (`<Foo />`, `<Foo>…</Foo>`) is a call to Foo, exactly
# like `Foo()`, in .tsx/.jsx/.js — but before this gate's fix it was invisible to --callers/--uses/
# --test-gate entirely (queries/typescript/tags.scm and queries/javascript/tags.scm captured
# call_expression/new_expression only, never a JSX element name).
#
# MEASURED RED at e54b688e (origin/main, before the fix), fixture test/jsxcallfix/isolate/jsx.tsx:
#   ripwire . --callers=UniqueWidget  ->  <callers of="UniqueWidget" defs="1" count="0" .../>
# even though `<UniqueWidget />` sits right there in Wrapper's body — this gate's §1 pins the GREEN
# (count="1") the fix produces on the same fixture.
#
# WHY A NEW GATE, not an extra arm on tsshapecheck/jsshapecheck. Those pin DEFINITION shapes (what
# becomes a symbol); this is a REFERENCE shape (what becomes an edge to an existing symbol), across
# TWO query files and a C++ capture-time filter, plus cross-verb propagation (--affected/--test-gate)
# and an import-precision requirement no shape gate currently exercises. One cohesive fixture set below
# it is.
#
# Fixture (test/jsxcallfix/):
#   isolate/jsx.tsx    issue #285 case 1, verbatim — UniqueWidget invoked via <UniqueWidget/>
#   isolate/plain.ts   issue #285 case 2, verbatim — the anonymous-callback CONTROL (must stay unaffected)
#   pair.tsx           a paired <Panel>…</Panel> — one edge, not two (jsx_closing_element uncaptured)
#   qualified.tsx      <Foo.Bar /> — a member-expression tag, kept regardless of case (member_expression
#                      shape, never the identifier shape the intrinsic filter tests)
#   intrinsic.tsx      <div>/<h1>/<svg:rect>/a `<>` fragment — must mint NO edge and NO phantom symbol
#   decoy/{real,other,renderer}.tsx  an import-bound component vs. a same-named, unimported decoy —
#                      the JSX call path must not spray onto the decoy any more than a plain call would
#   testgate/Comp.tsx + testgate/tests/widget_render.tsx   a component reached ONLY via a real
#                      call-graph edge through JSX from a NAMED test helper — the test file's name
#                      deliberately does not match Comp's stem, so the filename "partner" convention
#                      cannot explain a pass; only the JSX call edge can
#
# Usage:
#   test/jsxcallcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/jsxcallcheck.sh
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="test/jsxcallfix"        # relative — cd "$ROOT" below, so emitted p="..." matches this
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$ROOT/$FIX" ] || { echo "no fixture at $ROOT/$FIX"; exit 2; }
cd "$ROOT"

echo "jsxcallcheck: BIN=$BIN  FIX=$FIX"

# attr NAME <<<"$xml"  ->  the value of NAME="..." on the first tag that carries it
attr(){ grep -oE "$1=\"[^\"]*\"" | head -1 | sed -E "s/^$1=\"([^\"]*)\"$/\1/"; }

# ── §1 case 1 — the issue's minimal repro ──────────────────────────────────────────────────────────
c1="$( "$BIN" "$FIX" --no-cache --callers=UniqueWidget 2>"$TMP/err1" )"
n1="$( printf '%s' "$c1" | attr count )"
[ "$n1" = "1" ] && ok "case 1: <UniqueWidget /> resolves as a call (--callers count=1)" \
                || no "case 1: --callers=UniqueWidget count=$n1 (want 1) — stderr: $( cat "$TMP/err1" )"

# ── §2 case 2 — the issue's control: an anonymous-callback plain call must stay exactly as before ──
c2="$( "$BIN" "$FIX" --no-cache --callers=helper 2>"$TMP/err2" )"
n2="$( printf '%s' "$c2" | attr count )"
[ "$n2" = "1" ] && ok "case 2 control: plain call through helper() unaffected (--callers count=1)" \
                || no "case 2 control REGRESSED: --callers=helper count=$n2 (want 1) — stderr: $( cat "$TMP/err2" )"

# ── §3 paired element — <Panel>…</Panel> is ONE call, not two ──────────────────────────────────────
n3c="$( "$BIN" "$FIX" --no-cache --callers=Panel 2>/dev/null | attr count )"
n3u="$( "$BIN" "$FIX" --no-cache --uses=Panel    2>/dev/null | attr count )"
[ "$n3c" = "1" ] && ok "paired <Panel>…</Panel>: --callers count=1 (not double-counted)" \
                 || no "paired element: --callers=Panel count=$n3c (want 1 — 0 = still missed, 2 = jsx_closing_element wrongly captured too)"
[ "$n3u" = "1" ] && ok "paired <Panel>…</Panel>: --uses count=1 (one call SITE, not two)" \
                 || no "paired element: --uses=Panel count=$n3u (want 1)"

# ── §4 qualified tag — <Foo.Bar /> binds through member_expression like Foo.Bar() ──────────────────
n4="$( "$BIN" "$FIX" --no-cache --callers=Bar 2>/dev/null | attr count )"
[ "$n4" = "1" ] && ok "qualified <Foo.Bar />: --callers=Bar count=1 (member_expression tag resolves)" \
                || no "qualified tag: --callers=Bar count=$n4 (want 1)"

# ── §5 intrinsic tags + fragment — NO edge, NO phantom symbol ───────────────────────────────────────
for sym in div h1; do
    out="$( "$BIN" "$FIX" --no-cache --uses="$sym" 2>&1 )"
    case "$out" in
        *"selector matched no indexed definition"*) ok "intrinsic <$sym>: mints no symbol (--uses refuses: not indexed)" ;;
        *) no "intrinsic <$sym> OVER-CAPTURED — --uses=$sym did not refuse as unindexed: $out" ;;
    esac
done
# the namespaced tag and the fragment prove themselves structurally (a distinct grammar node / no
# name: field at all — see queries/tsx/tags.scm) rather than through a symbol lookup: the whole
# intrinsic.tsx file must still parse clean and contribute its OWN real symbol (IntrinsicHost).
mapout="$( "$BIN" "$FIX" --no-cache --top-k=500 2>/dev/null )"
printf '%s' "$mapout" | grep -q 'n="IntrinsicHost"' && ok "intrinsic.tsx still yields its real symbol IntrinsicHost (svg:rect/fragment did not break the file)" \
                                                     || no "IntrinsicHost missing from the map — intrinsic.tsx failed to extract at all"

# ── §6 decoy — import binding, not name spray ────────────────────────────────────────────────────────
n6real="$( "$BIN" "$FIX" --no-cache --callers='decoy/real.tsx:Widget'  2>/dev/null | attr count )"
n6decoy="$( "$BIN" "$FIX" --no-cache --callers='decoy/other.ts:Widget' 2>/dev/null | attr count )"
[ "$n6real" = "1" ]  && ok "decoy: the IMPORTED Widget (decoy/real.tsx) is credited with the JSX call (count=1)" \
                      || no "decoy: decoy/real.tsx:Widget count=$n6real (want 1) — the import-bound component lost its caller"
[ "$n6decoy" = "0" ] && ok "decoy: the UNIMPORTED same-named Widget (decoy/other.ts) gets no caller (count=0)" \
                      || no "decoy: decoy/other.ts:Widget count=$n6decoy (want 0) — the JSX call sprayed onto a same-named decoy"

# ── §7 --affected / --test-gate — a component reached ONLY via a real CALL-GRAPH edge through JSX ──
# testgate/tests/widget_render.tsx deliberately does NOT share Comp.tsx's filename stem, so the
# filename "test partner" convention (testmap.h::isTestPartnerOf) cannot fire — partners="0" below
# proves it. The ONLY way --affected/--test-gate can find this test is the real call edge
# renderModuleWidget --(JSX)--> ModuleWidget, i.e. exactly what this fix adds to the graph.
aff="$( "$BIN" "$FIX" --no-cache --affected=testgate/Comp.tsx 2>/dev/null )"
apartners="$( printf '%s' "$aff" | attr partners )"
areached="$( printf '%s' "$aff" | attr reached )"
[ "$apartners" = "0" ] || no "--affected=testgate/Comp.tsx: partners=$apartners (want 0 — fixture must NOT match by filename convention, or this arm proves nothing)"
[ "${areached:-0}" -ge 1 ] 2>/dev/null && ok "--affected=testgate/Comp.tsx: reached=$areached via the call graph alone (partners=0 — JSX edge is the only path)" \
                                       || no "--affected=testgate/Comp.tsx: reached=$areached (want >=1) — JSX-only call-graph reach not propagating to --affected"

tg="$( "$BIN" "$FIX" --no-cache --test-gate=testgate/Comp.tsx 2>/dev/null )"
tgimpacted="$( printf '%s' "$tg" | attr impacted )"
tgtests="$( printf '%s' "$tg" | attr tests )"
[ "${tgimpacted:-0}" -ge 1 ] 2>/dev/null && ok "--test-gate=testgate/Comp.tsx: impacted=$tgimpacted (renderModuleWidget now counted as a caller of the change)" \
                                         || no "--test-gate=testgate/Comp.tsx: impacted=$tgimpacted (want >=1)"
[ "${tgtests:-0}" -ge 1 ] 2>/dev/null && ok "--test-gate=testgate/Comp.tsx: tests=$tgtests (widget_render.tsx surfaces with no filename-convention help)" \
                                      || no "--test-gate=testgate/Comp.tsx: tests=$tgtests (want >=1)"

# ── §8 determinism + well-formedness on this fixture ────────────────────────────────────────────────
"$BIN" "$FIX" --no-cache --top-k=500 >"$TMP/map1" 2>/dev/null
"$BIN" "$FIX" --no-cache --top-k=500 >"$TMP/map2" 2>/dev/null
if cmp -s "$TMP/map1" "$TMP/map2"; then ok "two cold runs byte-identical"; else no "cold runs DIFFER on the JSX-call fixture"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/map1" 2>/dev/null; then ok "map is well-formed XML"; else no "map is not well-formed XML"; fi
else
    ok "xmllint absent — well-formedness check skipped"
fi

# ── §9 no adoption outside the target — a pre-existing plain-call shape stays untouched ────────────
n9="$( "$BIN" test/jsshapefix --no-cache --callers='#push' 2>/dev/null | grep -c '<caller' )"
[ "${n9:-0}" -ge 1 ] && ok "pre-existing shape untouched: #private call sites (jsshapefix) still resolve" \
                     || no "REGRESSION: jsshapefix's #push callers dropped to $n9"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"

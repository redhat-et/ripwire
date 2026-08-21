#!/usr/bin/env bash
# jsshapecheck.sh — the gate for JavaScript DEFINITION SHAPES that only a real repo produces.
#
#   test/jsshapecheck.sh
#   RIPWIRE_BIN=asan/ripwire test/jsshapecheck.sh
#
# WHY THIS EXISTS. langcheck proves JS ingest works at all; it cannot prove COVERAGE, because a
# fixture written from memory only contains the shapes its author thought to write. This gate was
# derived the other way round — the tsshapecheck.sh method applied to JavaScript: ripwire was run
# over webpack (github.com/webpack/webpack @957bf3a — 11 654 .js files) and node lib/
# (github.com/nodejs/node @427d2e1 — 406 files) on 2026-08-04, and the maps' `n="` sets were
# diffed against a ground truth enumerated by grep over BLANKED source (comments, strings and
# template literals removed — fixtures embed other languages in templates), then confirmed at AST
# level with SINGLE-capture `--match` queries (hits= counts CAPTURES, not matches — a two-capture
# query reports exactly double; and the legend comment itself contains the literal string
# hits_capped="1", so parse the <match> element, never grep the whole output).
#
# MEASURED at HEAD (kParserVer 38) before the fix; all counts hits_capped="0", i.e. exact:
#
#   field_definition bound to arrow/function        4 (webpack) + 3 (node/lib)   0 extracted  §1
#   method_definition name=private_property_ident   3 (webpack) + 232 (node/lib) 0 extracted  §2
#   Foo.prototype.bar = anonymous fn/arrow          332 sites node/lib          163 invisible §3
#     (the 169 that DID show rode the INNER name of a NAMED function expression, not the pattern)
#   module.exports.NAME / exports.NAME = fn/arrow   486+ sites webpack/lib, 47 minting a NEW
#                                                   function                      0 extracted  §4
#
# §5 pins the DISCLOSED KNOWN LIMITS in BOTH directions (a limit that quietly becomes a capture is
# as much a surprise as the reverse). §6 pins .jsx (the corpus's four .jsx files were one-line
# string exports — this fixture actually exercises JSX). §7 is the no-adoption arm.
#
# Fixture (test/jsshapefix/): transport.js (arrow fields, #private methods, data-field scope line),
# legacy.js (prototype assignment + the a.b=fn decoys), cjs.js (export assignments + decoys +
# defineProperty limit), anonmodule.js (whole-module anonymous export containment), widget.jsx.
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/jsshapefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "jsshapecheck: BIN=$BIN  FIX=$FIX"

"$BIN" "$FIX" --no-cache --top-k=500 >"$TMP/map" 2>/dev/null
MAP="$( cat "$TMP/map" )"

has(){ printf '%s' "$MAP" | grep -q "n=\"$1\""; }
rows(){ printf '%s' "$MAP" | grep -o "n=\"$1\"" | wc -l | tr -d ' '; }

# ── 1) class fields bound to an arrow/function are the class's callable surface ───────────────────
# `send = async payload => {…}` is reachable as `obj.send(...)` exactly like a method_definition —
# the same idiom the TS round closed (d2854f4), which does NOT cover JS: separate tags.scm.
for sym in send close reset makeDefault; do
    has "$sym" && ok "class-field arrow/function extracted: $sym" \
                || no "class-field arrow MISSING: $sym (field_definition value=arrow/function)"
done
# the modifier arms are not decoration: send is async, close is bare, reset is a function
# expression, makeDefault is static. A pattern matching only the bare arrow passes 1 of 4.
has "#drain" && ok "#private arrow field extracted: #drain" \
             || no "#private arrow field MISSING: #drain (property: private_property_identifier)"

# a NON-callable field must stay out — the same scope line tsshapecheck §1 pins: data fields are
# a >5000-site floor on a real corpus and would bury the map (98 webpack / 542 node-lib sites,
# overwhelmingly data).
for sym in label limit kindName; do
    has "$sym" && no "over-capture: plain data field '$sym' became a symbol (pattern must require a callable value)" \
                || ok "plain data field correctly NOT a symbol: $sym"
done

# ── 2) #private methods — 232 invisible methods in node/lib alone ─────────────────────────────────
for sym in '#push' '#register'; do
    has "$sym" && ok "#private method extracted: $sym" \
                || no "#private method MISSING: $sym (method_definition name=private_property_identifier)"
done
# and the matching REFERENCE: this.#push(…) / Transport.#register(…) must produce call edges,
# or the defs land in the graph as unreachable islands.
CALLS="$( "$BIN" "$FIX" --no-cache --callers='#push' 2>/dev/null | grep -c '<caller' )"
[ "${CALLS:-0}" -ge 1 ] && ok "#private call site resolves (callers of #push: $CALLS)" \
                        || no "#private calls produce no edges — reference pattern missing property: private_property_identifier"

# ── 3) prototype assignment — the pre-class idiom node/lib still carries 332 sites of ─────────────
for sym in setNoDelay unref destroySoon; do
    has "$sym" && ok "prototype method extracted: $sym" \
                || no "prototype method MISSING: $sym (Foo.prototype.$sym = anonymous fn/arrow)"
done
# a NAMED function expression on the prototype was already visible through its inner name; the
# assignment pattern is !name-scoped to anonymous values, so it must stay exactly ONE row.
[ "$( rows connect )" = "1" ] && ok "named fn-expression on prototype stays ONE row: connect" \
                             || no "connect has $( rows connect ) rows — the !name scope on the prototype pattern broke (0 = lost, 2 = double-captured)"

# the decoys: structurally identical assignments that are NOT prototype members.
for sym in onclose handler; do
    has "$sym" && no "over-capture: instance-slot assignment '$sym' became a symbol (the C++ gate must require the .prototype. segment)" \
                || ok "instance-slot assignment correctly NOT a symbol: $sym"
done

# ── 4) CommonJS export assignments — functions minted ON the export object ────────────────────────
for sym in getInnerGraphHelpers resolveMatchedTable emitPortMessage parseRuntimeVersion; do
    has "$sym" && ok "CJS export assignment extracted: $sym" \
                || no "CJS export assignment MISSING: $sym (module.exports.NAME / exports.NAME = fn/arrow)"
done
[ "$( rows formatRuntimeVersion )" = "1" ] && ok "named fn-expression export stays ONE row: formatRuntimeVersion" \
                                           || no "formatRuntimeVersion has $( rows formatRuntimeVersion ) rows (0 = lost, 2 = double-captured)"
[ "$( rows attachPort )" = "1" ] && ok "identifier re-export stays ONE row (the const decl): attachPort" \
                                || no "attachPort has $( rows attachPort ) rows — re-export of an existing binding must not mint a second def"
has defaultPortName && no "over-capture: data export 'defaultPortName' became a symbol (RHS must be callable)" \
                    || ok "data export correctly NOT a symbol: defaultPortName"
for sym in notAnExport alsoNotAnExport; do
    has "$sym" && no "over-capture: '$sym' became a symbol — the C++ gate must require the object to BE exports/module.exports, not merely shaped like it" \
                || ok "non-exports assignment correctly NOT a symbol: $sym"
done

# ── 5) DISCLOSED KNOWN LIMITS — pinned in BOTH directions ─────────────────────────────────────────
# 5a. computed-name methods: the name is a runtime expression ([Symbol.asyncIterator] — 18 sites in
#     node/lib). There is no honest static name; extracting the expression text would be a guess.
has asyncIterator && no "KNOWN LIMIT CHANGED: computed-name method surfaced as 'asyncIterator' — that name is a guess; update this gate only if the naming is deliberate and disclosed" \
                  || ok "KNOWN LIMIT holds: computed-name method not extracted ([Symbol.asyncIterator])"
# 5b. Object.defineProperty: the accessor BODIES extract as methods; the defined property NAME is a
#     string literal and does not (30 sites webpack/lib).
has definedAccessorProp && no "KNOWN LIMIT CHANGED: defineProperty property name 'definedAccessorProp' extracted — string-literal names were a documented gap" \
                        || ok "KNOWN LIMIT holds: defineProperty property name not extracted"
# 5c. a whole-module anonymous export has no name; its BODY's definitions must survive.
has normalizeAnonConfig && ok "anonymous module export: inner definition survives (normalizeAnonConfig)" \
                        || no "anonymous module export swallowed its body — normalizeAnonConfig lost"

# ── 6) JSX — the .jsx route through the JS grammar, exercised for real ────────────────────────────
for sym in WidgetPanel WidgetBadge WidgetFrame render; do
    has "$sym" && ok "JSX shape extracted: $sym" \
                || no "JSX shape MISSING: $sym (.jsx routes to tree-sitter-javascript, which parses JSX natively)"
done

# ── 7) no adoption outside the target — shapes that were already right ────────────────────────────
for sym in Transport Socket size entries; do
    has "$sym" && ok "pre-existing shape untouched: $sym" \
                || no "REGRESSION: previously-extracted symbol lost: $sym"
done

# ── 8) determinism + well-formedness on this fixture ──────────────────────────────────────────────
"$BIN" "$FIX" --no-cache --top-k=500 >"$TMP/map2" 2>/dev/null
cmp -s "$TMP/map" "$TMP/map2" && ok "two cold runs byte-identical" || no "cold runs DIFFER on the JS shape fixture"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/map" 2>/dev/null && ok "map is well-formed XML" || no "map is not well-formed XML"
else
    ok "xmllint absent — well-formedness check skipped"
fi

exit "$fail"

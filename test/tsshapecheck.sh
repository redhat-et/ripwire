#!/usr/bin/env bash
# tsshapecheck.sh — the gate for TypeScript DEFINITION SHAPES that only a real repo produces.
#
#   test/tsshapecheck.sh
#   RIPWIRE_BIN=asan/ripwire test/tsshapecheck.sh
#
# WHY THIS EXISTS. langcheck.sh proves TypeScript ingest works at all (a.ts: two functions, one call
# edge). It cannot prove COVERAGE, because a fixture written from memory only ever contains the
# shapes its author thought to write. This gate was derived the other way round: ripwire was run
# over openclaw (github.com/openclaw/openclaw @1aedd8f3 — 24 658 .ts files, 261 760 symbols) on
# 2026-08-04 and its `n="` set was diffed against a ground truth enumerated independently, first by
# grep over blanked source (comments and template literals removed — the repo embeds Kotlin, Swift
# and JS fixtures inside String.raw templates, which otherwise fake thousands of phantom hits) and
# then confirmed at AST level with `--match`. Three shapes came back at ~0 % recall. All three are
# things a TypeScript codebase leans on and none of them were in any fixture.
#
# MEASURED at HEAD before the fix. Site counts are --match totals over openclaw with hits_capped="0",
# so they are exact rather than floors — and taken from SINGLE-capture queries, because --match's
# hits= counts CAPTURES, not matches: a two-capture query reports double, which is how the first
# pass of this measurement briefly read 574/152/206.
#
#   public_field_definition bound to an arrow      287 sites    0 extracted   §1
#   abstract_method_signature                       76 sites    0 extracted   §2
#   declarator value = as/satisfies(paren(arrow))  105 sites    0 extracted   §3
#
# §3 is the highest-value of the three despite being nearly the smallest: openclaw's entire public
# `src/plugin-sdk/` surface is written that way, so every one of those 105 was an exported API
# entry point that `--for` structurally could not surface.
#
# §4 pins the DISCLOSED KNOWN LIMITS. A limit that quietly becomes a capture is as much a surprise
# as a capture that quietly becomes a limit, so both directions are assertions here.
#
# §5 is the no-adoption arm: the shapes that were already right must be untouched by §1–§3.
#
# Fixture (test/tsshapefix/): service.ts (abstract contract + arrow-bound fields + plain fields),
# facade.ts (the lazy-facade cast idiom), limits.d.ts (ambient containers and bindings),
# typeimport.ts (the vendored-grammar parse hole and its containment), objectliteral.ts (the
# deliberate non-capture).
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/tsshapefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "tsshapecheck: BIN=$BIN  FIX=$FIX"

"$BIN" "$FIX" --no-cache --top-k=500 >"$TMP/map" 2>/dev/null
MAP="$( cat "$TMP/map" )"

has(){ printf '%s' "$MAP" | grep -q "n=\"$1\""; }

# ── 1) class fields bound to an arrow are the class's callable surface ────────────────────────────
# `send = async (payload) => {…}` is reachable as `obj.send(...)` exactly like a method_definition
# is; before this round it produced no row at all, so a service class written in the bound-method
# style contributed only its own class name to the map.
for sym in send close makeDefault; do
    has "$sym" && ok "class-field arrow extracted: $sym" \
                || no "class-field arrow MISSING: $sym (public_field_definition value=arrow_function)"
done
# the modifier arms above are not decoration: `send` is async, `close` is bare, `makeDefault` is
# `static readonly`. A pattern that only matched the bare form would pass on one of three.

# a NON-callable field must stay out — this is the scope line between 287 sites and a >5000 floor
for sym in label limit; do
    has "$sym" && no "over-capture: plain data field '$sym' became a symbol (pattern must require an arrow value)" \
                || ok "plain data field correctly NOT a symbol: $sym"
done

# ── 2) abstract method signatures are the contract, and --lego reads exactly this ─────────────────
# An abstract class whose contract is invisible is an abstract class you cannot navigate: --lego=I
# lists an interface's method contract plus its implementors, and abstract bases are the other half
# of that story.
for sym in send close describeTransport; do
    has "$sym" && ok "abstract/concrete member present: $sym" \
                || no "abstract_method_signature MISSING: $sym"
done
# TransportBase declares send/close/describeTransport abstractly and SocketTransport defines all
# three, so §2 alone cannot distinguish "extracted" from "riding on the subclass". isReady is
# concrete-only on the base, and describeTransport is proof the protected modifier does not block
# the pattern; the discriminating assertion is the defs= count below.
DEFS="$( "$BIN" "$FIX" --no-cache --uses=describeTransport 2>/dev/null | grep -oE 'defs="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
[ "${DEFS:-0}" -ge 2 ] && ok "describeTransport resolves to BOTH the abstract signature and the override (defs=$DEFS)" \
                       || no "describeTransport defs=${DEFS:-0} — the abstract signature is not a definition (expected >=2)"

# ── 3) the lazy-facade cast idiom — an exported arrow wrapped in as/satisfies ──────────────────────
# `export const f: M["f"] = ((...args) => …) as M["f"];` puts an as_expression where tags.scm was
# looking for an arrow_function. Every one of openclaw's 105 sites is a public entry point.
for sym in buildProviderConfig resolveGatewayEndpoint isFeatureAvailable; do
    has "$sym" && ok "as-wrapped arrow export extracted: $sym" \
                || no "as-wrapped arrow export MISSING: $sym (value=as_expression(parenthesized_expression(arrow_function)))"
done
has describeFacade && ok "satisfies-wrapped arrow export extracted: describeFacade" \
                   || no "satisfies-wrapped arrow export MISSING: describeFacade (value=satisfies_expression)"

# ── 4) DISCLOSED KNOWN LIMITS — pinned in BOTH directions ─────────────────────────────────────────
# 4a. Ambient CONTAINERS are not symbols; their MEMBERS are. The container's name is a module
#     specifier string (`declare module "vendor-qrcode"`) or a type-only namespace — neither is a
#     name a reader looks up — and the members are what navigation needs. Members must be present:
for sym in ambientToString AmbientOptions ambientCompile; do
    has "$sym" && ok "ambient container MEMBER extracted: $sym" \
                || no "ambient container member MISSING: $sym — the container limit has widened into its contents"
done
# 4b. Ambient VALUE bindings are a real (small) loss: unlike 4a there is no member to fall back on.
#     37 sites in openclaw, mostly build flags and test globals. Disclosed, not silent.
for sym in AMBIENT_BUILD_FLAG ambientMutableGlobal; do
    has "$sym" && no "KNOWN LIMIT CHANGED: '$sym' is now extracted — ambient declare bindings were a documented gap; update this gate and the README if that is deliberate" \
                || ok "KNOWN LIMIT holds: ambient value binding not extracted ($sym)"
done
# 4c. Object-literal properties bound to arrows stay out. Same syntax as §1, different thing:
#     >5000 sites in openclaw (a --match FLOOR — the engine cap), overwhelmingly inline callbacks.
for sym in onConnect onDisconnect onRetry; do
    has "$sym" && no "KNOWN LIMIT CHANGED: object-literal arrow '$sym' became a symbol — that is the >5000-site (floor) flood §1 was deliberately scoped away from" \
                || ok "KNOWN LIMIT holds: object-literal arrow not extracted ($sym)"
done
has HANDLER_TABLE_LIMITS && ok "SCREAMING_SNAKE settings const still carries the module (HANDLER_TABLE_LIMITS)" \
                         || no "HANDLER_TABLE_LIMITS missing — the r3 q10 constant capture regressed"
# 4d. The vendored-grammar parse hole, and — the part worth pinning — its CONTAINMENT. The broken
#     declaration is lost; its neighbours on both sides are not. If a future grammar bump fixes the
#     parse, BrokenParenthesized starts extracting and this arm fires: that is a good failure.
has BrokenParenthesized && no "KNOWN LIMIT CHANGED: '(typeof import(…))[…]' now parses — the tree-sitter-typescript pin moved; re-measure the 1 222-file blast radius and update this gate" \
                        || ok "KNOWN LIMIT holds: parenthesized typeof-import declaration not parsed"
for sym in survivesBeforeTypeImport alsoSurvivesBeforeTheHole survivesAfterTypeImport ControlTypeofImport ControlImportType; do
    has "$sym" && ok "parse hole stays LOCAL — neighbour survives: $sym" \
                || no "parse hole WIDENED: '$sym' lost; error recovery no longer contains the typeof-import break to its own declaration"
done
has brokenTypeArgument && ok "type-ARGUMENT form costs nothing — enclosing function still extracted: brokenTypeArgument" \
                       || no "type-argument typeof-import now costs its enclosing function — the 2 087-site shape just became expensive"

# ── 5) no adoption outside the target — shapes that were already right ────────────────────────────
for sym in TransportBase SocketTransport PlainFields isReady deliver FacadeModule loadFacadeModule plainArrowExport; do
    has "$sym" && ok "pre-existing shape untouched: $sym" \
                || no "REGRESSION: previously-extracted symbol lost: $sym"
done

# ── 6) determinism + well-formedness on this fixture ──────────────────────────────────────────────
"$BIN" "$FIX" --no-cache --top-k=500 >"$TMP/map2" 2>/dev/null
cmp -s "$TMP/map" "$TMP/map2" && ok "two cold runs byte-identical" || no "cold runs DIFFER on the TS shape fixture"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/map" 2>/dev/null && ok "map is well-formed XML" || no "map is not well-formed XML"
else
    ok "xmllint absent — well-formedness check skipped"
fi

exit "$fail"

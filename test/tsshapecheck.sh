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
# §7 is a CALL-SITE shape, not a definition: `await f<T>(x)`, which the grammar parses as `(await f)<T>(x)`,
# checked in .ts and .tsx on a fixture of its own.
#
# Fixture (test/tsshapefix/): service.ts (abstract contract + arrow-bound fields + plain fields),
# facade.ts (the lazy-facade cast idiom), limits.d.ts (ambient containers and bindings),
# typeimport.ts (the vendored-grammar parse hole and its containment), objectliteral.ts (the
# deliberate non-capture).
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/tsshapefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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

# ── 7) CALL-SITE shape: `await f<T>(x)` and `!f<T>(x)` are calls (TS and TSX) ──────────────────────
# tree-sitter-typescript parses an await before an explicit type-argument call as `(await f)<T>(x)`: the
# call_expression's function: is the await_expression, so a query that only looks for function: (identifier) or
# (member_expression) never sees the callee and the site was no reference at all — no edge, and no declined or
# unresolved count either, so a callers answer was silently short. Measured on hono @6abd35b0: 5 sites, among
# them the method-override middleware's `await parseBody<Record<string, string>>(c.req)`, whose function never
# appeared as a parseBody caller. Each grammar has its own query file (queries/typescript, queries/tsx), so the
# arm runs once per extension. The fixture is written here rather than under tsshapefix/ so §1-§5's map is
# untouched. RED before the await patterns: a1, a2, a3, a5 and methodOverride are absent; a4 (no await) is the
# control that was always found. The unary operators (`!`, `typeof`, `void`, `-`) bind the same way, `(!f)<T>(x)`, and
# were missed the same way (RED before the unary patterns: u1-u6). The negatives pin that a comparison chain, an
# instantiation expression and a type argument stay at zero edges.
AW="$TMP/await"
for ext in ts tsx; do
    D="$AW/$ext"; mkdir -p "$D"
    cat >"$D/calls.$ext" <<'EOF'
export const f = async <T>(x: number): Promise<T> => x as unknown as T;
export class Svc { async g<T>(x: number): Promise<T> { return x as unknown as T; } }
export class K {
  async #p<T>(x: number): Promise<T> { return x as unknown as T; }
  async a3() { return await this.#p<number>(1); }
}
export const pending = Promise.resolve(1);
export async function a1() { return await f<number>(1); }
export async function a2(o: { svc: Svc }) { return await o.svc.g<number>(1); }
export function a4() { return f<number>(1); }
export async function a5() { return await f<Map<string, Array<Record<string, number>>>>(1); }
export async function a6() { const v = await pending; return v; }
export async function a7() { return !await f<number>(1); }
export async function a8() { return await await f<number>(1); }
EOF
    cat >"$D/override.$ext" <<'EOF'
export const parseBody = async <T>(r: { json(): Promise<unknown> }): Promise<T> => (await r.json()) as T;
export const methodOverride = (options: { app: unknown }) =>
  async function methodOverride(c: { req: { json(): Promise<unknown> } }) {
    const form = await parseBody<Record<string, string>>(c.req);
    return form && options;
  };
EOF
    # The unary operators share the quirk: `!f<T>(x)` parses as `(!f)<T>(x)`, the call's function: a unary_expression.
    cat >"$D/unary.$ext" <<'EOF'
export function fw<T>(x: number): T { return x as unknown as T; }
export class Q {
  fm<T>(x: number): T { return x as unknown as T; }
  #fq<T>(x: number): T { return x as unknown as T; }
  u6() { return !this.#fq<number>(1); }
}
export function u1() { return !fw<number>(1); }
export function u2() { return typeof fw<number>(1); }
export function u3() { return void fw<number>(1); }
export function u4() { return -fw<number>(1); }
export function u5(o: { q: Q }) { return !o.q.fm<number>(1); }
EOF
    # NEGATIVES the await/unary patterns must not turn into calls: a comparison chain with and without parentheses,
    # an instantiation expression (type arguments, no call), a name used only as a type argument, and a bare name under
    # `!`, `typeof`, `await` or `-` with no call at all (n6, the near miss a pattern without its call_expression would take).
    cat >"$D/negatives.$ext" <<'EOF'
export function na() { return 1; }
export function nb() { return 2; }
export function nc() { return 3; }
export function nd<T>(x: T) { return x; }
export function ne<T>(x: number) { return x as unknown as T; }
export function nf() { return 4; }
export async function n1() { return await (na < nb) > (nc); }
export async function n2() { return await na < nb > nc; }
export async function n3() { return await nd<number>; }
export async function n4() { return await ne<typeof nf>(1); }
export function n5() { return !(na < nb) > (nc); }
export async function n6() { return !na || typeof nb === "function" || (await nc) === 3 || -nd; }
EOF
    rowsOf(){ "$BIN" "$D" --no-cache --callers="$1" --limit=100 2>/dev/null | grep -oE '<s [^>]*n="[^"]*"' | grep -oE 'n="[^"]*"' | sed 's/n="//;s/"$//' | sort | tr '\n' ' ' | sed 's/ $//'; }
    got="$( rowsOf f )"
    [ "$got" = "a1 a4 a5 a7 a8" ] && ok "$ext: --callers=f is a1 a4 a5 a7 a8 (await f<T>(), the plain f<T>() control, nested type arguments, !await and await await)" \
                                  || no "$ext: --callers=f got [$got], want [a1 a4 a5 a7 a8] — an \`await f<T>(x)\` site is no reference"
    got="$( rowsOf g )"
    [ "$got" = "a2" ] && ok "$ext: --callers=g is a2 (await o.svc.g<T>(), the member form)" \
                      || no "$ext: --callers=g got [$got], want [a2] — the member form of await-with-type-arguments is no reference"
    got="$( rowsOf '#p' )"
    [ "$got" = "a3" ] && ok "$ext: --callers=#p is a3 (await this.#p<T>(), the private form)" \
                      || no "$ext: --callers=#p got [$got], want [a3] — the private form of await-with-type-arguments is no reference"
    got="$( rowsOf parseBody )"
    [ "$got" = "methodOverride" ] && ok "$ext: --callers=parseBody is methodOverride (the hono middleware shape: a named function expression returned by an arrow)" \
                                  || no "$ext: --callers=parseBody got [$got], want [methodOverride]"
    got="$( rowsOf pending )"
    [ -z "$got" ] && ok "$ext: a bare \`await pending\` (no call) mints no call reference" \
                  || no "$ext: --callers=pending got [$got] — an await of a value became a call"
    got="$( rowsOf fw )"
    [ "$got" = "u1 u2 u3 u4" ] && ok "$ext: --callers=fw is u1 u2 u3 u4 (!, typeof, void and unary - before f<T>())" \
                               || no "$ext: --callers=fw got [$got], want [u1 u2 u3 u4] — a unary operator before f<T>(x) hides the call"
    got="$( rowsOf fm )"
    [ "$got" = "u5" ] && ok "$ext: --callers=fm is u5 (!o.q.fm<T>(), the member form)" \
                      || no "$ext: --callers=fm got [$got], want [u5] — the member form under a unary operator is no reference"
    got="$( rowsOf '#fq' )"
    [ "$got" = "u6" ] && ok "$ext: --callers=#fq is u6 (!this.#fq<T>(), the private form)" \
                      || no "$ext: --callers=#fq got [$got], want [u6] — the private form under a unary operator is no reference"
    for neg in na nb nc nd nf; do
        got="$( rowsOf "$neg" )"
        [ -z "$got" ] && ok "$ext: --callers=$neg is empty (a comparison operand, an instantiation expression or a type argument is no call)" \
                      || no "$ext: --callers=$neg got [$got] — a comparison, an instantiation expression or a type argument became a call"
    done
    got="$( rowsOf ne )"
    [ "$got" = "n4" ] && ok "$ext: --callers=ne is n4 (await ne<typeof nf>(1) calls ne, not its type argument)" \
                      || no "$ext: --callers=ne got [$got], want [n4]"
done

# ── 6) determinism + well-formedness on this fixture ──────────────────────────────────────────────
"$BIN" "$FIX" --no-cache --top-k=500 >"$TMP/map2" 2>/dev/null
if cmp -s "$TMP/map" "$TMP/map2"; then ok "two cold runs byte-identical"; else no "cold runs DIFFER on the TS shape fixture"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/map" 2>/dev/null; then ok "map is well-formed XML"; else no "map is not well-formed XML"; fi
else
    ok "xmllint absent — well-formedness check skipped"
fi

exit "$fail"

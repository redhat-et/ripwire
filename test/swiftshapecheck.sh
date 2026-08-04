#!/usr/bin/env bash
# swiftshapecheck.sh — the gate for Swift DEFINITION SHAPES that only a real repo produces.
#
#   test/swiftshapecheck.sh
#   RIPWIRE_BIN=asan/ripwire test/swiftshapecheck.sh
#
# WHY THIS EXISTS. langcheck proves Swift ingest works at all; it cannot prove COVERAGE — the
# tags.scm carried 8 def-patterns with no enum-case / typealias / protocol-property /
# associatedtype / operator-function coverage. This gate was derived the pyshapecheck way:
# ripwire was run over Alamofire (github.com/Alamofire/Alamofire @0455bfb — 98 .swift files) and
# swift-nio (github.com/apple/swift-nio @7297328 — 554 .swift files) on 2026-08-04, the maps'
# (file, n=") sets were diffed against a ground truth from a comment/string-blanking scan
# (swiftblank.py — Swift has no stdlib parser to shell to, unlike Python's ast) cross-checked at
# AST level with SINGLE-capture `--match` queries (hits= counts CAPTURES, not matches; parse the
# <match> element, never grep the stream — its legend contains the literal string hits_capped="1";
# the engine 5000-cap is HARD, split big corpora per subdir).
#
# MEASURED at HEAD (kParserVer 40) before the fix; counts are exact:
#
#   enum case (raw/bare/comma-list/indirect/assoc)   247 (Alamofire) + 1 209 (nio)   ~0%   §1
#     (partial %s in the raw report are same-name set collisions, not extraction)
#   typealias (incl. generic)                        39 (Alamofire) + 962 (nio)      ~0%   §2
#     (a swift-nio ChannelHandler's InboundIn/OutboundIn IS its wire contract)
#   protocol property requirement (var/static var)   12 (Alamofire) + 65 (nio)        0%   §3
#     (nio's Channel declares 30+: allocator, closeFuture, pipeline, ...)
#   associatedtype                                   7 (Alamofire) + 35 (nio)          0%   §3
#   operator function (all BUILTIN tokens here)      4 (Alamofire) + 62 (nio)          0%   §4
#     ((custom_operator) matched ZERO corpus sites — the alternation of anonymous
#      tokens `"==" "<" "+" ...` is what carries the real weight)
#
# 100% on BOTH corpora at HEAD, pinned unchanged in §5: computed properties (get/set and
# shorthand, incl. backticked names like `default`), extension members (methods, computed
# props, statics), protocol-extension default impls, protocol method requirements, lazy vars,
# willSet/didSet owning vars, subscripts/init/deinit (per-file), property wrappers, actors,
# async funcs, nested types + funcs, global let/var, #if-conditional defs.
#
# §6 pins the BY-DESIGN non-goals in BOTH directions: `infix operator X:` DECLARATION lines mint
# no def (the operator FUNCTION is the callable surface; 0 decl sites in both corpora);
# tuple bindings `let (a, b) = ...` stay ONE verbatim-named row (0 corpus sites — not worth a
# splitter); local `let`/`var` inside executable blocks stay out (isSwiftLocalBinding); an
# extension CONTAINER mints no row of its own (members attach normally).
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/swiftshapefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "swiftshapecheck: BIN=$BIN  FIX=$FIX"

"$BIN" "$FIX" --no-cache --top-k=500 >"$TMP/map" 2>/dev/null
MAP="$( cat "$TMP/map" )"

# scoped to <s symbol rows — a call edge <c n="X"/> to a same-named symbol must not count
has(){ printf '%s' "$MAP" | grep -q "<s [^>]*n=\"$1\""; }
rows(){ printf '%s' "$MAP" | grep -o "<s [^>]*n=\"$1\"" | wc -l | tr -d ' '; }

# ── 1) enum cases — the value tables agents grep for ──────────────────────────────────────────────
# Alamofire's AFError alone is 200+ of these; before the (enum_entry) pattern every one was
# invisible. Comma lists yield one def per NAME; associated/raw values change nothing.
for sym in crimson teal ochre umber blend sized pallet empty_slot verbose_knob; do
    has "$sym" && ok "enum case extracted: $sym" \
                || no "enum case MISSING: $sym ((enum_entry name:) pattern)"
done
has grabbed_val && no "over-capture: switch-arm pattern binding 'grabbed_val' became a symbol (case ARMS are not enum cases)" \
                || ok "switch-arm binding correctly NOT a symbol: grabbed_val"

# ── 2) typealiases — a nio ChannelHandler's InboundIn IS its wire contract ────────────────────────
for sym in FrameHandler PairOf; do
    has "$sym" && ok "typealias extracted: $sym" \
                || no "typealias MISSING: $sym (typealias_declaration pattern)"
done

# ── 3) protocol property requirements + associatedtype — the contract's other half ────────────────
for sym in lane_id default_capacity; do
    has "$sym" && ok "protocol property requirement extracted: $sym" \
                || no "protocol property requirement MISSING: $sym (protocol_property_declaration pattern)"
done
has Freight && ok "associatedtype extracted: Freight" \
            || no "associatedtype MISSING: Freight (associatedtype_declaration pattern)"

# ── 4) operator functions — callable surface named by a token, not an identifier ──────────────────
# The corpora's 66 sites are ALL builtin tokens (==, <, +, ...); (custom_operator) alone measured
# zero. Both the alternation and the custom node are needed.
has "==" && ok "builtin operator func extracted: ==" \
         || no "builtin operator func MISSING: == (anonymous-token alternation in the name: field)"
has "\&lt;+\&gt;" && ok "custom operator func extracted: <+>" \
                  || no "custom operator func MISSING: <+> ((custom_operator) name — XML-escaped in the map)"

# ── 5) the shapes measured at 100% at HEAD stay at 100% ───────────────────────────────────────────
for sym in doubled_stock stock_gauge audited_stock lazy_manifest ext_audit ext_ratio ext_make \
           lane_banner open_lane pump_relay close_books inner_probe css_hex \
           GLOBAL_SPOOL linux_only_probe not_linux_probe LINUX_SPOOL DebugKnob \
           Depot RelayHub Manifest Ledger ledger_rows relay_count stock_count TransportLane \
           PaintColor Cargo routeCargo localHost subscript init deinit; do
    has "$sym" && ok "pre-existing shape untouched: $sym" \
                || no "REGRESSION: previously-extracted symbol lost: $sym"
done
has "\`default\`" && ok "backticked computed property untouched: \`default\`" \
                  || no "REGRESSION: backticked name lost: \`default\` (map stores the source spelling)"

# ── 6) BY-DESIGN non-goals, pinned in BOTH directions ─────────────────────────────────────────────
[ "$( rows "\&lt;+\&gt;" )" = "1" ] && ok "operator DECLARATION line mints no def: <+> stays ONE row (the func)" \
                                   || no "<+> has $( rows "\&lt;+\&gt;" ) rows — the 'infix operator' declaration must not mint a second def"
has local_shadow && no "over-capture: local binding 'local_shadow' became a symbol (isSwiftLocalBinding must hold)" \
                 || ok "local binding correctly NOT a symbol: local_shadow"
has "(tuple_left, tuple_right)" && ok "KNOWN LIMIT holds: tuple binding stays one verbatim row: (tuple_left, tuple_right)" \
                                || no "KNOWN LIMIT CHANGED: tuple binding row '(tuple_left, tuple_right)' gone — update the gate only if a splitter landed deliberately"
has tuple_left && no "KNOWN LIMIT CHANGED: tuple element 'tuple_left' became its own symbol — update the gate only if that deepened deliberately" \
               || ok "KNOWN LIMIT holds: tuple elements not split: tuple_left"
[ "$( rows Depot )" = "1" ] && ok "extension container mints no extra row: Depot stays ONE row" \
                           || no "Depot has $( rows Depot ) rows — 'extension Depot' must not mint a container def"

# ── 7) determinism + well-formedness on this fixture ──────────────────────────────────────────────
"$BIN" "$FIX" --no-cache --top-k=500 >"$TMP/map2" 2>/dev/null
cmp -s "$TMP/map" "$TMP/map2" && ok "two cold runs byte-identical" || no "cold runs DIFFER on the Swift shape fixture"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/map" 2>/dev/null && ok "map is well-formed XML" || no "map is not well-formed XML"
else
    ok "xmllint absent — well-formedness check skipped"
fi

exit "$fail"

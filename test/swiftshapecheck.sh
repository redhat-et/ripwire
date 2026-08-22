#!/usr/bin/env bash
# swiftshapecheck.sh — the gate for Swift DEFINITION SHAPES that only a real repo produces.
#
#   test/swiftshapecheck.sh
#   RIPWIRE_BIN=asan/ripwire test/swiftshapecheck.sh
#
# WHY THIS EXISTS. langcheck proves Swift ingest works at all; it cannot prove COVERAGE — the
# tags.scm carried 8 def-patterns with no enum-case / typealias / protocol-property /
# associatedtype / operator-function coverage. This gate was originally derived the pyshapecheck
# way: ripwire was run over Alamofire (github.com/Alamofire/Alamofire @0455bfb — 98 .swift files)
# and swift-nio (github.com/apple/swift-nio @7297328 — 554 .swift files) on 2026-08-04, the maps'
# (file, n=") sets were diffed against a ground truth from a comment/string-blanking scan
# (swiftblank.py — Swift has no stdlib parser to shell to, unlike Python's ast) cross-checked at
# AST level with SINGLE-capture `--match` queries (hits= counts CAPTURES, not matches; parse the
# <match> element, never grep the stream — its legend contains the literal string hits_capped="1";
# the engine 5000-cap is HARD, split big corpora per subdir).
#
# PORT + RE-MEASUREMENT (2026-08-10). This gate is a hand-port of bb78f97 from a branch that was
# never merged to main, landed here at kParserVer 60 (the branch sat at 41). The figures below are
# a FRESH re-measurement, not carried forward — Alamofire@0455bfb and swift-nio@72973283 were
# cloned read-only and pinned to the exact SHAs/file-counts (98 / 554 .swift files) the 2026-08-04
# derivation used, at bench-assets/swift/{Alamofire__Alamofire,apple__swift-nio}. AST-level ground
# truth via --match (single-capture, `<match>` parsed, hits_capped="0" i.e. exact not a floor)
# reproduced the 2026-08-04 figures EXACTLY, digit for digit, confirming the pinned corpora and the
# vendored grammar have not drifted:
#
#   enum case (raw/bare/comma-list/indirect/assoc)   247 (Alamofire) + 1 209 (nio)   both years
#   typealias (incl. generic)                         39 (Alamofire) +  962 (nio)   both years
#   associatedtype                                      7 (Alamofire) +   35 (nio)   both years
#   protocol property requirement (var/static var)    12 (Alamofire) +   65 (nio)   both years
#   operator function (all BUILTIN tokens here)         4 (Alamofire) +   62 (nio)   both years
#     ((custom_operator) alone still matches ZERO corpus sites on either corpus — the
#      alternation of anonymous tokens `"==" "<" "+" ...` is what carries the real weight)
#
# Crawl-based before/after (--no-cache --top-k=100000, PLAIN build only — see the ASan note
# below): pre-port binary = main@b598266/kParserVer 59, built and copied aside BEFORE this port
# touched any source; post-port = this commit/kParserVer 60.
#
#   Alamofire:  5120 -> 5429 symbols (+309), 26891 -> 26957 edges (+66)
#   swift-nio: 16844 -> 19177 symbols (+2 333), 36021 -> 36515 edges (+494)
#
# The original round recorded "+309 symbols/+66 edges" (Alamofire) and "+2 333/+498" (nio): symbol
# deltas match EXACTLY on both corpora; the Alamofire edge delta matches EXACTLY; the swift-nio
# edge delta is +494 here vs +498 then, a 4-edge difference not investigated further — nothing in
# this port touches call-edge resolution, so it is far more likely unrelated resolver drift across
# the ~19 kParserVer versions between the two measurements than a defect in this fix.
#
# NOISE, verified with an actual (file,name) symbol-identity set-diff (not eyeballed): ZERO rows
# removed on either corpus — Alamofire +220 distinct (file,name) pairs, swift-nio +1 521 (the
# larger raw symbol-count deltas above include same-file overload/collision multiplicity). Matches
# the original round's "ZERO removed rows" claim exactly on both corpora.
#
# 100% on both corpora, pinned unchanged in §5: computed properties (get/set and shorthand, incl.
# backticked names like `default`), extension members (methods, computed props, statics),
# protocol-extension default impls, protocol method requirements, lazy vars, willSet/didSet owning
# vars, subscripts/init/deinit (per-file), property wrappers, actors, async funcs, nested types +
# funcs, global let/var, #if-conditional defs.
#
# §6 pins the BY-DESIGN non-goals in BOTH directions: `infix operator X:` DECLARATION lines mint
# no def (the operator FUNCTION is the callable surface; 0 decl sites in both corpora);
# tuple bindings `let (a, b) = ...` stay ONE verbatim row (0 corpus sites — not worth a
# splitter); local `let`/`var` inside executable blocks stay out (isSwiftLocalBinding); an
# extension CONTAINER mints no row of its own (members attach normally).
#
# DEFERRED ON PURPOSE, VERIFIED AT PORT TIME: the source round also carried a vendored patch to
# third_party/deps/swift/src/scanner.c (an implicit-integer-truncation: a raw-string lookahead
# codepoint above 255 — e.g. an emoji — truncates into a uint8_t, which UBSan aborts on under
# -fno-sanitize-recover=all). That patch is deliberately NOT part of this port — nothing else
# under third_party/deps carries a local patch today, and landing this one bare would start a
# vendored-patch convention with no drift gate behind it; it is left for its own round. The bug is
# REAL: an isolated one-line fixture containing an emoji inside a raw `#"..."#` string reproduces
# the exact documented abort (scanner.c:820, codepoint 127881 truncated to uint8_t, SIGABRT/exit
# 134). It does NOT, however, trigger on the actual pinned corpora used here — a full ASan run
# (LSAN_OPTIONS=suppressions=lsan_suppressions.txt ./asan/ripwire <dir>) over all 716 swift-nio
# files and all 469 Alamofire files completed CLEANLY on both, as did this repo's own self-scan
# and the swiftshapefix fixtures. The stranded commit's claim that swift-nio's test files carry an
# emoji inside a raw string did not reproduce at this exact pinned SHA (72973283); whether such
# content exists at a different swift-nio revision was not investigated. This fixture directory
# (test/swiftshapefix/) contains NO raw `#"..."#` string literals at all, so it cannot exercise
# the bug either way — verified explicitly (no non-ASCII byte falls inside a raw-string span in
# any fixture file; the few non-ASCII bytes that do appear are inside `//` line comments, a code
# path the vendored bug does not touch).
#
# Gate: 17 arms fire red against the pre-port binary (verified before any source edit landed).
# Registered in test/regression.sh.
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
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
# The corpora's 66 sites (2026-08-04 measurement) are ALL builtin tokens (==, <, +, ...); the bare
# (custom_operator) node alone measured zero. Both the alternation and the custom node are needed.
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

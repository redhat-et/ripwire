#!/usr/bin/env bash
# archmetricscheck.sh — gate for ABS-4: regex path-rules (capture-group sibling isolation) + Robert C.
# Martin package metrics (Ca/Ce/I/A/D + zone) + reachability/orphan. All additive under --arch=FILE.
#
# Fixture test/archmetricsfix/ has KNOWN coupling (hand-computed expected values):
#   core   — free functions, depended-on by app, depends on nothing → Ca1 Ce0 I0 A0 D1  zone=n/a   leaf
#   iface  — one pure-virtual class (Shape) → abstract                → Ca1 Ce0 I0 A1 D0  zone=ok    leaf
#   app    — #includes core + iface                                   → Ca0 Ce2 I1 A0 D0  zone=ok
#   orphan — no deps in or out                                        → Ca0 Ce0           isolated, zone=n/a
#   ringA <-> ringB — a dependency CYCLE with no external entry       → Ca1 Ce1 I0.5      reachable=0 (island)
#
# §P6.5: core/orphan/ringA/ringB have ZERO types (free functions or nothing) — abstractness (A) is forced to
# 0 by definition for a typeless module (arch.h), which pins D close to 1 for any low-instability module and
# reads every one of them as zone="pain" regardless of real coupling (the real repo: 132 of 163 modules,
# nearly all typeless doc/bench dirs). zone="n/a" says "not classifiable", not "classified and bad" — and is
# excluded from the header's zone_pain/zone_useless tally (typed_modules is the honest denominator: only
# iface + app here, both types>0, so the fixture's typed_modules="2").
# The \1 backreference precision is checked implicitly: intra-module edges (core/math.cpp→core/math.h,
# ringA/a.cpp→ringA/a.h, …) must NOT trip the cross-sibling deny — so the violation count is EXACTLY the
# four cross-sibling edges, not more.
#
# Floats are asserted to 2dp (the serializer's fixed precision) — a tolerance band, not bit-exact math.
#
# Usage:  bash test/archmetricscheck.sh [BIN]  |  RIPWIRE_BIN=build/ripwire bash test/archmetricscheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
# BOTH seams. `bash test/<gate>.sh asan/ripwire` is how regression.sh and every differential run pass a
# binary; this gate read only RIPWIRE_BIN, so a positional argument was accepted and silently ignored and
# a red-first run against a BASE binary came back ALL PASS against the binary already in build/.
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/archmetricsfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no test/archmetricsfix dir — fixture missing"; exit 2; }
[ -f "$FIX/sibling.arch" ] || { echo "no test/archmetricsfix/sibling.arch — fixture config missing"; exit 2; }
cd "$ROOT"

echo "archmetricscheck: BIN=$BIN  CORPUS=test/archmetricsfix"

# full --arch output for a given rules file
arch(){ perl -e 'alarm 20; exec @ARGV' "$BIN" "$FIX" --arch="$1" --no-cache 2>/dev/null; }
# one module's <m .../> element, selected by the path's final segment
mod(){ printf '%s' "$1" | tr '>' '\n' | grep '<m ' | grep "/$2\""; }
# assert every space-separated attr=val token is present in the module line $1 (order-independent)
hasall(){ local line="$1"; shift; for a in "$@"; do printf '%s' "$line" | grep -q "$a" || return 1; done; return 0; }

OUT="$( arch "$FIX/sibling.arch" )"

# ── 1) regex path-rule: the \1 backreference fires on EXACTLY the 4 cross-sibling edges ───────────────
nv="$( printf '%s' "$OUT" | grep -o '<v ' | wc -l | tr -d ' ' )"
[ "$nv" = 4 ] \
    && ok "sibling-backreference deny fires on the 4 cross-sibling edges only (intra-module \\1 NOT flagged)" \
    || { no "expected 4 cross-sibling violations, got $nv (\\1 backreference precision broken)"; printf '%s' "$OUT" | tr '>' '\n' | grep '<v '; }

# ── 2) allow overrides deny (allow-listed) → 0 violations ─────────────────────────────────────────────
printf 'allow path src/(\\w+)/.* -> src/.*\ndeny path src/(\\w+)/.* -> src/(?!\\1/).*\n' > "$TMP/allow.arch"
na="$( arch "$TMP/allow.arch" | grep -o '<v ' | wc -l | tr -d ' ' )"
[ "$na" = 0 ] && ok "allow rule overrides deny (allow-listed → 0 violations)" || no "allow override failed ($na violations)"

# ── 3) malformed path-regex DEGRADES — rule skipped, no hang, no crash (guarded by alarm in arch()) ───
printf 'deny path src/(\\w+/.* -> src/[\n' > "$TMP/bad.arch"
perl -e 'alarm 8; exec @ARGV' "$BIN" "$FIX" --arch="$TMP/bad.arch" --no-cache >"$TMP/bad.out" 2>/dev/null; rc=$?
{ [ "$rc" = 0 ] || [ "$rc" = 2 ]; } && grep -q '<arch' "$TMP/bad.out" \
    && ok "malformed path-regex degrades (skipped, no hang/crash, well-formed output, exit $rc)" \
    || no "malformed path-regex did not degrade cleanly (exit $rc)"

# ── 4) Martin metrics, per module (2dp tolerance) ────────────────────────────────────────────────────
# §P6.5: core has ZERO types (free functions only) — D would compute to 1.00 (the pathological "every
# typeless module is pain" bug) but zone must read "n/a" (not classifiable), not "pain" (classified bad).
m="$( mod "$OUT" core )"
hasall "$m" 'ca="1"' 'ce="0"' 'types="0"' 'I="0.00"' 'A="0.00"' 'D="1.00"' 'zone="n/a"' 'leaf="1"' \
    && ok "core  = stable concrete leaf, ZERO types → zone=n/a, not the pre-fix pathological 'pain' (Ca1 Ce0 I0 A0 D1 leaf)" || no "core metrics wrong: $m"

m="$( mod "$OUT" iface )"
hasall "$m" 'ca="1"' 'ce="0"' 'abstract="1"' 'A="1.00"' 'I="0.00"' 'zone="ok"' \
    && ok "iface = abstract (A=1 via the pure-virtual proxy) + stable → on the main sequence (zone=ok, has types)" || no "iface metrics wrong: $m"

m="$( mod "$OUT" app )"
hasall "$m" 'ca="0"' 'ce="2"' 'I="1.00"' \
    && ok "app   = unstable consumer (Ca0 Ce2 I1 — depends on core+iface, nothing depends on it)" || no "app metrics wrong: $m"

m="$( mod "$OUT" orphan )"
hasall "$m" 'ca="0"' 'ce="0"' 'isolated="1"' 'types="0"' 'zone="n/a"' \
    && ok "orphan = isolated module (Ca0 Ce0 isolated), ZERO types → zone=n/a" || no "orphan metrics wrong: $m"

# ── 4b) §P6.5: header zone tally excludes typeless (zone=n/a) modules — typed_modules is the honest
#       denominator. Fixture: only iface + app carry types (2 of 6 modules); core/orphan/ringA/ringB are
#       typeless (4 modules) → zone_na="4" typed_modules="2".
hasall "$OUT" 'typed_modules="2"' 'zone_na="4"' \
    && ok "header: typed_modules=2 zone_na=4 (6 modules total, only iface+app carry types)" \
    || { no "header zone tally wrong"; printf '%s' "$OUT" | grep -o '<metrics[^>]*>'; }
printf '%s' "$OUT" | grep -o '<metrics[^>]*>' | grep -q 'zone_pain="0"' \
    && ok "header: zone_pain=0 (core's pre-fix pathological 'pain' no longer inflates the tally)" \
    || { no "zone_pain should be 0 once typeless modules are excluded"; printf '%s' "$OUT" | grep -o '<metrics[^>]*>'; }

# ── 5) reachability: the ringA<->ringB cycle has no external entry → reachable=0 (dead island); a
#       normally-connected module is reachable=1. ─────────────────────────────────────────────────────
ra="$( mod "$OUT" ringA )"; rb="$( mod "$OUT" ringB )"
{ printf '%s' "$ra" | grep -q 'reachable="0"' && printf '%s' "$rb" | grep -q 'reachable="0"'; } \
    && ok "cycle island ringA<->ringB → reachable=0 (no acyclic entry reaches it)" \
    || { no "cycle should be reachable=0"; printf '  ringA: %s\n  ringB: %s\n' "$ra" "$rb"; }
printf '%s' "$( mod "$OUT" core )" | grep -q 'reachable="1"' \
    && ok "connected module core → reachable=1" || no "core should be reachable=1"

# ── 6) determinism — metrics + violations byte-identical run-to-run ───────────────────────────────────
[ "$OUT" = "$( arch "$FIX/sibling.arch" )" ] \
    && ok "deterministic (--arch metrics + violations byte-identical across runs)" || no "non-deterministic --arch output"

# ── 8) A RULE'S MEANING MUST NOT DEPEND ON THE DIRECTORY THE TREE WAS CHECKED OUT INTO ───────────────
# Check 1 above asserts "4", and until this arm existed it asserted 4 only because THIS repo happens to sit
# at a path with no `src` in it. The rule is `deny path src/(\w+)/.* -> src/(?!\1/).*`, matched with
# regex_search against whatever path the corpus was spelled with. Check the identical fixture out into a
# directory named e.g. `wt-cf2src` and the leftmost `src/` regex_search finds is the one inside the CHECKOUT
# NAME: \1 captures `test` for every file, the sibling-isolation lookahead is then asking the wrong question,
# and the three intra-module edges the backreference exists to spare are flagged too — 7 violations instead
# of 4, same fixture, same rules, same binary. A CI gate whose verdict is a function of the clone directory
# is not a gate.
#
# So this arm does not assert a number. It copies the fixture to TWO checkouts — one whose absolute path
# contains a literal `src/` segment, one that contains no `src` at all — and asserts the two runs agree with
# each other AND with the in-repo run, on the COUNT and on the violation SET (normalised to the fixture-
# relative spelling, since the absolute paths necessarily differ). That is the property; the number is a
# consequence, and it holds wherever the gate itself happens to live.
COPLAIN="$TMP/checkout/quiet"
COSRC="$TMP/checkout/wt-cf2src"          # ends in `src`, so the absolute path contains the segment `…src/`
mkdir -p "$COPLAIN" "$COSRC"
cp -R "$FIX" "$COPLAIN/fixture"
cp -R "$FIX" "$COSRC/fixture"
archat(){ perl -e 'alarm 20; exec @ARGV' "$BIN" "$1" --arch="$1/sibling.arch" --no-cache 2>/dev/null; }
OP="$( archat "$COPLAIN/fixture" )"
OS="$( archat "$COSRC/fixture" )"
vcount(){ printf '%s' "$1" | grep -o '<v ' | wc -l | tr -d ' '; }
# the violation SET, made comparable: strip each checkout's own prefix so only the fixture-relative edge remains
vset(){ printf '%s' "$1" | tr '>' '\n' | grep '<v ' | sed "s#$2/##g" | sort; }
np="$( vcount "$OP" )"; ns="$( vcount "$OS" )"
[ "$np" = "$ns" ] && [ "$np" = "$nv" ] \
    && ok "path-rule verdict is independent of the checkout directory (quiet=$np, …src/=$ns, in-repo=$nv)" \
    || { no "the same fixture gives different verdicts from different checkouts (quiet=$np, …src/=$ns, in-repo=$nv) — an unanchored rule bound to the checkout PATH"
         printf '%s' "$OS" | tr '>' '\n' | grep '<v ' | head -8; }
[ "$( vset "$OP" "$COPLAIN/fixture" )" = "$( vset "$OS" "$COSRC/fixture" )" ] \
    && ok "…and the violation SET is identical, not merely the count" \
    || { no "the two checkouts flag DIFFERENT edges"; diff <( vset "$OP" "$COPLAIN/fixture" ) <( vset "$OS" "$COSRC/fixture" ) | head -8; }

# ── 7) XML well-formed (G4) — the whole --arch document incl. <metrics> ──────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$OUT" | xmllint --noout - 2>/dev/null && ok "xml well-formed (arch + metrics)" || no "xml malformed"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

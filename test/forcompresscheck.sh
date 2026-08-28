#!/usr/bin/env bash
# forcompresscheck.sh — gate for the paper-shape lane: --compress composes with the BODY-SERVING bundles
# (--for's auto/anchor bodies, --pack-task), disclosed per bundle as compress="1" on the <bodies> element.
#
# Motivation (recorded result-free in docs/EVALS.md): arXiv 2607.09691 measured that with localization
# fixed, compressed SOURCE matches whole files for acting at ~1/3 the tokens — so the tokens spent on
# SERVED BODIES are the ones worth compressing, and the bundles that serve bodies terminally (--for auto
# mode, --pack-task) must accept the SAME --compress the --expand rung already has.
#
# What is measured:
#   arm 1  bare `--for TASK --compress` is ACCEPTED (the old guard refused it; red-first vs 1dc7b01)
#   arm 2  the compressed --for auto bundle drops the fixture's comments; the plain one keeps them
#   arm 3  identical symbol set with and without --compress (compression shapes bytes, never selection)
#   arm 4  compressed bodies are smaller, and the <bodies> element carries compress="1" ONLY under the flag
#   arm 5  same disclosure on --pack-task (composition already worked there; the DISCLOSURE is new)
#   arm 6  flagless honesty: no compress= attribute anywhere without the flag (purely additive surface)
#   arm 7  determinism + xmllint on the new shapes
#
# The residual, stated: on the COMPACT (conceptual) --for route no bodies are served, so --compress has
# nothing to strip there and no attribute appears — the flag is accepted because the route is chosen at
# run time, after parse. The auto-bodies flag puts the bodies (and the disclosure) back.
#
# Usage:
#   test/forcompresscheck.sh                          # uses build/ripwire on test/compressfix
#   RIPWIRE_BIN=asan/ripwire test/forcompresscheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/compressfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "no test/compressfix directory"; exit 2; }

echo "forcompresscheck: BIN=$BIN  CORPUS=$CORPUS"

# ── arm 1: bare --for + --compress is accepted (name-exact query → bundle=auto serves the body) ────────
"$BIN" "$CORPUS" --for=computeArea --compress --no-cache >"$TMP/for_c.xml" 2>"$TMP/for_c.err"
rc=$?
[ $rc -eq 0 ] && ok "--for --compress exits 0 (guard accepts the body-serving lens)" \
              || { no "--for --compress refused (rc=$rc)"; head -2 "$TMP/for_c.err"; }

"$BIN" "$CORPUS" --for=computeArea --no-cache >"$TMP/for_p.xml" 2>/dev/null

# NON-VACUITY (the regression.sh determinism arm's own rule): an empty document strips every comment,
# beats every size bar and diffs identical to itself — a refused run must not green the arms below.
[ -s "$TMP/for_c.xml" ] && ok "--for --compress produced a document (non-vacuity)" \
                        || no "--for --compress produced NO output — the arms below would be vacuous"

# ── arm 2: the served auto body is actually compressed ─────────────────────────────────────────────────
grep -q 'block comment inside function' "$TMP/for_p.xml" \
    && ok "plain --for auto body keeps the fixture comment (baseline OK)" \
    || no "plain --for auto body is missing the fixture comment (fixture or auto bundle broken)"
grep -q 'block comment inside function' "$TMP/for_c.xml" \
    && no "--for --compress still carries the block comment (bodies not compressed)" \
    || ok "--for --compress strips the block comment from the served body"
grep -q 'http://example.com' "$TMP/for_c.xml" \
    && ok "string-literal comment lookalike survives (compressBody semantics, not a new stripper)" \
    || no "string literal corrupted — --for is NOT going through the same compressBody --expand uses"

# ── arm 3: identical symbol set (selection is untouched; only body bytes shrink) ───────────────────────
grep -o '<b [^>]*n="[^"]*"' "$TMP/for_p.xml" | sed 's/.*n="//' | LC_ALL=C sort >"$TMP/set_p"
grep -o '<b [^>]*n="[^"]*"' "$TMP/for_c.xml" | sed 's/.*n="//' | LC_ALL=C sort >"$TMP/set_c"
if [ -s "$TMP/set_p" ] && diff -q "$TMP/set_p" "$TMP/set_c" >/dev/null; then
    ok "identical served-body symbol set with and without --compress"
else
    no "served-body symbol set differs under --compress (selection must not move)"
fi

# ── arm 4: smaller bytes + per-bundle disclosure ───────────────────────────────────────────────────────
sz_c="$( wc -c <"$TMP/for_c.xml" | tr -d ' ' )"
sz_p="$( wc -c <"$TMP/for_p.xml" | tr -d ' ' )"
[ "$sz_c" -lt "$sz_p" ] && ok "compressed --for bundle is smaller ($sz_c B < $sz_p B)" \
                        || no "compressed --for bundle is not smaller ($sz_c B >= $sz_p B)"
grep -q '<bodies [^>]*compress="1"' "$TMP/for_c.xml" \
    && ok '--for --compress <bodies> carries compress="1"' \
    || no '--for --compress <bodies> is missing the compress="1" disclosure'

# ── arm 5: --pack-task discloses too ───────────────────────────────────────────────────────────────────
"$BIN" "$CORPUS" --pack-task=computeArea --compress --no-cache >"$TMP/pt_c.xml" 2>/dev/null \
    && ok "--pack-task --compress exits 0" || no "--pack-task --compress failed"
"$BIN" "$CORPUS" --pack-task=computeArea --no-cache >"$TMP/pt_p.xml" 2>/dev/null
grep -q '<bodies [^>]*compress="1"' "$TMP/pt_c.xml" \
    && ok '--pack-task --compress <bodies> carries compress="1"' \
    || no '--pack-task --compress <bodies> is missing the compress="1" disclosure'
grep -q 'block comment inside function' "$TMP/pt_c.xml" \
    && no "--pack-task --compress still carries the block comment" \
    || ok "--pack-task --compress strips the block comment"

# ── arm 6: flagless honesty — the attribute exists ONLY under the flag ─────────────────────────────────
if grep -q 'compress="1"' "$TMP/for_p.xml" || grep -q 'compress="1"' "$TMP/pt_p.xml"; then
    no 'compress="1" appears on a flagless run (the disclosure must ride the flag, nothing else)'
else
    ok 'flagless --for/--pack-task carry no compress= attribute'
fi

# ── arm 7: determinism + well-formedness on the new shapes ─────────────────────────────────────────────
"$BIN" "$CORPUS" --for=computeArea --compress --no-cache >"$TMP/for_c2.xml" 2>/dev/null
diff -q "$TMP/for_c.xml" "$TMP/for_c2.xml" >/dev/null \
    && ok "--for --compress deterministic (byte-identical)" || no "--for --compress nondeterministic"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/for_c.xml" 2>/dev/null && ok "--for --compress pipes clean through xmllint" \
                                                 || no "--for --compress is not well-formed XML"
    xmllint --noout "$TMP/pt_c.xml" 2>/dev/null && ok "--pack-task --compress pipes clean through xmllint" \
                                                || no "--pack-task --compress is not well-formed XML"
else
    ok "xmllint not installed — well-formedness arms skipped"
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi

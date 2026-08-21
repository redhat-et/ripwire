#!/usr/bin/env bash
# expandtopk0check.sh — V1 gate (ugrep routing note RN2, 2026-08-15 harvest): --expand=SYMBOL for an
# EXACT-NAME request (one token, one unambiguous match) now DEFAULTS its own ranked map to top-k=0 — the
# caller already named the exact target, so the ~200-row orientation map is pure overhead in front of the
# one body it exists to summarize. "Cheapest complete answer in one call."
#
# THE CONTRACT:
#   - one token, ONE match, no explicit --top-k: NO <r> map rows, and the root discloses the default with
#     topk_default="0" (self-describing — the change can be seen without reading source).
#   - one token, MULTIPLE matches (a genuinely ambiguous name): the caller's ORDINARY default still
#     applies — the ranked map rides along (there IS something to disambiguate) and the pre-existing
#     "ranked top-N map rides along" stderr note still fires. NO topk_default= on this shape.
#   - an EXPLICIT --top-k=N (0 included) always overrides the new default and keeps the classic shape —
#     no topk_default= attribute either way, since the caller made the choice, not the tool.
#   - the default composes with M6's bundle-vs-whole-file auto-serving (test/expandmodecheck.sh): whichever
#     mode M6 picks, topk_default="0" still rides on the root when the exact-name default applied.
#
# Fixtures: test/expandtopk0fix/unique.c (uniqueTarget, one def) + dupA.c/dupB.c (dupTarget, two defs, the
# ambiguous control) — both tiny, so M6 serves whole-file; test/expandmodefix/big.c (bigProbe007, one def
# in a file too large for whole-file) exercises the SAME default composed with mode="bundle".
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/expandtopk0check.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/expandtopk0fix"
MODEFIX="$ROOT/test/expandmodefix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ]     || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ]     || { echo "no test/expandtopk0fix directory"; exit 2; }
[ -d "$MODEFIX" ] || { echo "no test/expandmodefix directory"; exit 2; }
cd "$ROOT"
echo "expandtopk0check: BIN=$BIN  FIX=$FIX"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# ── (A) exact-name, no --top-k: topk_default="0", NO ranked map, NO ride-along stderr note ──────────────
"$BIN" "$FIX" --expand=uniqueTarget --no-cache >"$TMP/uniq.xml" 2>"$TMP/uniq.err"
grep -q 'topk_default="0"' "$TMP/uniq.xml" \
    && ok "(A) exact-name --expand discloses topk_default=\"0\" on the root" \
    || no "(A) exact-name --expand carries no topk_default= disclosure"
if grep -q '<r ' "$TMP/uniq.xml"; then
    no "(A) exact-name --expand still shipped the ranked map"
else
    ok "(A) exact-name --expand emits NO ranked map rows"
fi
grep -q 'uniqueTarget' "$TMP/uniq.xml" \
    && ok "(A) the one body is still present" || no "(A) the body itself is missing"
if grep -qi 'rides along' "$TMP/uniq.err"; then
    no "(A) the ride-along stderr note fired even though no map rides (mapTopK==0 guard missing)"
else
    ok "(A) no ride-along stderr note (nothing is riding along to warn about)"
fi

# ── (B) ambiguous name (2 defs), no --top-k: the ORDINARY default applies — map rides, note fires ────────
# --pack-budget-bytes=10 forces M6's whole-file candidate over budget (dupA.c+dupB.c together are well
# over 10 B), so chooseExpandServe picks mode="bundle" deterministically regardless of this tiny fixture's
# absolute byte counts — the note only ever fires in bundle mode ("never in whole-file mode" is the
# pre-existing, correct rule; this arm needs bundle mode to observe it at all).
"$BIN" "$FIX" --expand=dupTarget --top-k=5 --no-cache >"$TMP/dup5.xml" 2>/dev/null
grep -q '<r ' "$TMP/dup5.xml" \
    && ok "(B) --top-k=5 sanity: dupTarget's map is reachable at all" \
    || no "(B) --top-k=5 sanity failed — fixture cannot exercise this arm"
"$BIN" "$FIX" --expand=dupTarget --pack-budget-bytes=10 --no-cache >"$TMP/dup.xml" 2>"$TMP/dup.err"
grep -q 'mode="bundle"' "$TMP/dup.xml" \
    && ok "(B) sanity: the ambiguous probe landed in bundle mode (the note's only firing ground)" \
    || no "(B) sanity failed: --pack-budget-bytes=10 did not force bundle mode — arm proves nothing"
if grep -q 'topk_default="0"' "$TMP/dup.xml"; then
    no "(B) ambiguous --expand (2 matches) wrongly got the exact-name default"
else
    ok "(B) ambiguous --expand carries NO topk_default= — the multi-match case is untouched"
fi
grep -qi 'rides along' "$TMP/dup.err" \
    && ok "(B) the pre-existing ride-along stderr note still fires on the ambiguous shape" \
    || no "(B) ride-along note missing on the ambiguous shape (V1 regression)"

# ── (C) explicit --top-k=5 on the exact-name target: overrides the default, classic undecorated shape ───
"$BIN" "$FIX" --expand=uniqueTarget --top-k=5 --no-cache >"$TMP/tk5.xml" 2>/dev/null
grep -q '<r ' "$TMP/tk5.xml" \
    && ok "(C) explicit --top-k=5 forces the map back even on an exact-name match" \
    || no "(C) explicit --top-k=5 lost the map"
if grep -q 'topk_default=' "$TMP/tk5.xml"; then
    no "(C) explicit --top-k=5 still carries topk_default= — override must keep the caller's plain shape"
else
    ok "(C) explicit --top-k=5 carries no topk_default= (the caller chose, not the tool)"
fi

# ── (D) explicit --top-k=0: the pre-existing legacy undecorated lean form, unchanged ─────────────────────
"$BIN" "$FIX" --expand=uniqueTarget --top-k=0 --no-cache >"$TMP/tk0.xml" 2>/dev/null
if grep -qE '<r |topk_default=|mode="' "$TMP/tk0.xml"; then
    no "(D) explicit --top-k=0 picked up new decoration — must stay the pre-existing byte shape"
else
    ok "(D) explicit --top-k=0 stays the pre-existing undecorated lean form"
fi

# ── (E) composes with M6 bundle mode: bigProbe007 (large file, exact match) — mode="bundle" AND
#        topk_default="0" AND no <r> map, all at once (test/expandmodecheck.sh arm 2 pins the mode= side;
#        this arm is the topk_default= side of the SAME document). ───────────────────────────────────────
"$BIN" "$MODEFIX" --expand=bigProbe007 --no-cache >"$TMP/big.xml" 2>/dev/null
grep -q 'mode="bundle"' "$TMP/big.xml" && grep -q 'topk_default="0"' "$TMP/big.xml" \
    && ok "(E) bundle mode AND the exact-name default compose on one root" \
    || no "(E) bundle mode / topk_default= did not compose: $( grep -oE '<ctx[^>]*>' "$TMP/big.xml" )"
if grep -q '<r ' "$TMP/big.xml"; then
    no "(E) bundle mode still shipped the ranked map"
else
    ok "(E) bundle mode ships no ranked map either"
fi

# ── (G) V1 fix regression guard (verifier finding 1, 2026-08-15) — the shape (B) and (E) both
#        structurally could not exercise. (B) forces bundle mode via --pack-budget-bytes=10, so the
#        estimator's own value never gets compared against a real whole-file candidate. (E)'s
#        bigProbe007 fixture is tiny and hand-built, so even a wildly wrong bundle estimate happens not
#        to flip the mode there. Neither arm runs at the DEFAULT budget on a REAL, non-trivial repo — the
#        one place the defect actually manifested: measureEmittedMapBytes(mapTopK, …) was called
#        UNGUARDED for the bundle-size estimate, and mapTopK==0 means UNLIMITED inside serialize() (not
#        "no map"), so the estimator priced a ~1 MB whole-repo map that the emitter never intended to
#        print. chooseExpandServe then compared that phantom bundle against the real whole-file candidate
#        and picked mode="whole-file" — serving the ENTIRE 48 KB src/darkflags.h in place of the ~1 KB
#        body the exact-name default promises. RED on the pre-fix binary
#        (reason="file 48222B &lt; bundle 1054283B", mode="whole-file"); GREEN once the estimator is
#        guarded exactly like its two siblings at the ceiling verdict and the topK>0 emission gate
#        (`mapTopK > 0 ? measureEmittedMapBytes(...) : 0`).
"$BIN" "$ROOT" --expand=endsWithView --no-cache >"$TMP/real_default.xml" 2>"$TMP/real_default.err"
"$BIN" "$ROOT" --expand=endsWithView --no-cache --top-k=0 >"$TMP/real_tk0.xml" 2>/dev/null
realTk0Bytes=$( wc -c < "$TMP/real_tk0.xml" | tr -d ' ' )

if grep -q 'mode="whole-file"' "$TMP/real_default.xml"; then
    no "(G) default --expand=endsWithView on the real repo wrongly served whole-file: $( grep -oE '<ctx[^>]*>' "$TMP/real_default.xml" )"
else
    ok "(G) default --expand=endsWithView on the real repo correctly stays in bundle mode"
fi

# (G-a) the SERVED BODY (everything but the <ctx ...> opening tag's own mode=/reason= decoration, which
#       composing with M6 is the documented, (E)-gated contract) must be byte-identical to explicit
#       --top-k=0's — proving the estimator and the emitter now agree on what mapTopK==0 means.
sed 's/<ctx[^>]*>//' "$TMP/real_default.xml" > "$TMP/real_default_body.xml"
sed 's/<ctx[^>]*>//' "$TMP/real_tk0.xml"      > "$TMP/real_tk0_body.xml"
diff -q "$TMP/real_default_body.xml" "$TMP/real_tk0_body.xml" >/dev/null \
    && ok "(G-a) default's served body is byte-identical to explicit --top-k=0's" \
    || no "(G-a) default's served body diverges from explicit --top-k=0's — the estimator or the emitter disagree on what mapTopK==0 means"

# (G-b) when topk_default="0" is in effect and a reason= fires, the bundle byte count it PRICES must be
#       the REAL served size (== the --top-k=0 byte count), never a phantom map-inclusive estimate. This
#       is the precise, load-bearing number the V1 defect corrupted.
pricedBundle=$( grep -oE 'reason="bundle [0-9]+B' "$TMP/real_default.xml" | grep -oE '[0-9]+' )
if [ -n "$pricedBundle" ]; then
    if [ "$pricedBundle" = "$realTk0Bytes" ]; then
        ok "(G-b) reason= prices the bundle at exactly the --top-k=0 byte count (${pricedBundle}B) — no phantom map"
    else
        no "(G-b) reason= priced the bundle at ${pricedBundle}B but --top-k=0 actually serves ${realTk0Bytes}B — the reason= string still prices a map that mapTopK==0 will never emit"
    fi
else
    no "(G-b) no reason=\"bundle NNNB ...\" clause found on the real-repo default root — unexpected mode, see (G) above: $( grep -oE '<ctx[^>]*>' "$TMP/real_default.xml" )"
fi

# ── (F) well-formedness + determinism ─────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    for f in uniq dup5 dup tk5 tk0 big real_default real_tk0; do
        xmllint --noout "$TMP/$f.xml" 2>/dev/null && ok "(F) $f.xml well-formed" || no "(F) $f.xml fails xmllint"
    done
else
    printf '  SKIP  xmllint not installed\n'
fi
"$BIN" "$FIX" --expand=uniqueTarget --no-cache >"$TMP/uniq2.xml" 2>/dev/null
diff -q "$TMP/uniq.xml" "$TMP/uniq2.xml" >/dev/null \
    && ok "(F) exact-name default output byte-identical across two runs" \
    || no "(F) exact-name default output non-deterministic"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

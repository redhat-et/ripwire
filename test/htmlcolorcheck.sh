#!/usr/bin/env bash
# htmlcolorcheck.sh — gate for --color-by=MODE on the --html export (lang|community|cx|churn|tested).
#
# WHAT IT PINS. The --html page used to colour nodes by LANGUAGE only. --color-by bakes an initial
# lens and the page embeds all five with a live selector, so this gate has to hold three separate
# contracts at once:
#
#   1) PAYLOAD — every lens' data is actually in the emitted document (per-node cx/ts, the file-keyed
#      FCHURN array, CHURN_OK, COLOR_MODE, the selector and its five options, renderLegend). A lens
#      whose data never shipped renders a uniform colour that reads as a real answer.
#   2) REFUSALS — the flag names a value SET, so a bad value, an empty value, and the flag without
#      its --html host each refuse loudly and name what was wrong (r27-emitters T5: a bad VALUE must
#      never be reported as an unknown FLAG).
#   3) HONESTY (repo non-negotiable #3) — the two traps this feature was built around, both of which
#      paint a "not measured" as a measured value:
#        • NULL testedPtr. QMetrics is computed upstream only under --metrics/--for/--exemplar, so a
#          bare `--html` run had no tested vector and every node would read ts:0 — "not computed"
#          masquerading as "untested". Arms (6a)/(6b) pin that the bare path measures it, and pin it
#          AGAINST the upstream path so a future refactor cannot quietly drop back to zeros.
#        • NO GIT HISTORY. With no commits there is no churn evidence, and painting the resulting
#          zeros with the green "0 commits" bucket is a fabricated fact. Arms (6c)-(6e) pin that the
#          page carries CHURN_OK=0 and a legend that SAYS churn is unavailable — and, as the control
#          that keeps that arm from passing on a hardwired zero, that a git-backed corpus reads 1.
#      Community's moduleless singletons (comm<0) get the same treatment: an explicit "none" swatch
#      rather than bucket 0's colour.
#   4) THE ZERO-VIEWPORT SEED. A hidden tab/iframe boots the canvas at W=H=0, so a spread of
#      min(W,H)*0.7 seeded every node at the SAME point — and coincident nodes have dx=dy=0, so the
#      repulsion force is zero forever and the layout can never separate (the "one dot" render).
#      Arm (7) pins the 300-world-unit floor and the ABSENCE of the unfloored expression.
#
# Usage:
#   test/htmlcolorcheck.sh                          # uses build/ripwire on test/fixture
#   RIPWIRE_BIN=asan/ripwire test/htmlcolorcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

echo "htmlcolorcheck: BIN=$BIN  CORPUS=$CORPUS"

# ── 1) baseline payload: --html with no --color-by still carries the machinery, defaulted to lang ────
"$BIN" "$CORPUS" --html --no-cache >"$TMP/out.html" 2>/dev/null
count="$( grep -c '"id"' "$TMP/out.html" 2>/dev/null || echo 0 )"
[ "$count" -ge 3 ]                             && ok "NODES array has >= 3 entries (found $count)"        || no "NODES array has < 3 entries (found $count)"
grep -q '"cx":'                "$TMP/out.html" && ok "output contains \"cx\": per-node field"              || no "output missing \"cx\": per-node field"
grep -q '"ts":'                "$TMP/out.html" && ok "output contains \"ts\": per-node field"              || no "output missing \"ts\": per-node field"
grep -q 'const FCHURN'         "$TMP/out.html" && ok "output contains const FCHURN"                        || no "output missing const FCHURN"
grep -q 'const CHURN_OK'       "$TMP/out.html" && ok "output contains const CHURN_OK"                      || no "output missing const CHURN_OK"
grep -q 'id="colorMode"'       "$TMP/out.html" && ok "output contains <select id=\"colorMode\">"           || no "output missing <select id=\"colorMode\">"
grep -q 'value="lang"'         "$TMP/out.html" && ok "colorMode select has value=\"lang\" option"          || no "colorMode select missing value=\"lang\" option"
grep -q 'value="community"'    "$TMP/out.html" && ok "colorMode select has value=\"community\" option"     || no "colorMode select missing value=\"community\" option"
grep -q 'value="cx"'           "$TMP/out.html" && ok "colorMode select has value=\"cx\" option"            || no "colorMode select missing value=\"cx\" option"
grep -q 'value="churn"'        "$TMP/out.html" && ok "colorMode select has value=\"churn\" option"         || no "colorMode select missing value=\"churn\" option"
grep -q 'value="tested"'       "$TMP/out.html" && ok "colorMode select has value=\"tested\" option"        || no "colorMode select missing value=\"tested\" option"
grep -q 'renderLegend'         "$TMP/out.html" && ok "output contains renderLegend function"               || no "output missing renderLegend function"
grep -q 'const COLOR_MODE = "lang"' "$TMP/out.html" && ok "default COLOR_MODE is \"lang\" when --color-by omitted" || no "default COLOR_MODE is not \"lang\" when --color-by omitted"

# ── 2) explicit mode: --color-by=cx bakes COLOR_MODE = "cx" into the page ────────────────────────────
"$BIN" "$CORPUS" --html --color-by=cx --no-cache >"$TMP/cx.html" 2>/dev/null
grep -q 'const COLOR_MODE = "cx"' "$TMP/cx.html" && ok "--color-by=cx: COLOR_MODE = \"cx\" baked in" || no "--color-by=cx: COLOR_MODE = \"cx\" not baked in"

# ── 3) determinism: two runs of --html --color-by=community are byte-identical ───────────────────────
#      NON-EMPTY is part of the assertion: two empty outputs from a refusing binary also "match".
"$BIN" "$CORPUS" --html --color-by=community --no-cache >"$TMP/comm_a.html" 2>/dev/null
"$BIN" "$CORPUS" --html --color-by=community --no-cache >"$TMP/comm_b.html" 2>/dev/null
if [ -s "$TMP/comm_a.html" ] && diff -q "$TMP/comm_a.html" "$TMP/comm_b.html" >/dev/null 2>&1; then
    ok "determinism: byte-identical run-to-run (and non-empty)"
else
    no "determinism: non-identical or empty output"
fi

# ── 4) refusals ──────────────────────────────────────────────────────────────────────────────────────

# 4a) --color-by without --html must refuse, naming --html in stderr.
"$BIN" "$CORPUS" --color-by=community --no-cache >"$TMP/4a.out" 2>"$TMP/4a.err"
rc=$?
if [ "$rc" -ne 0 ] && grep -q -- '--html' "$TMP/4a.err"; then
    ok "--color-by without --html refuses (rc=$rc) and names --html"
else
    no "--color-by without --html did not refuse-and-name --html (rc=$rc)"
    sed 's/^/    /' "$TMP/4a.err"
fi

# 4b) --color-by=bogus must refuse, naming the bad value and the allowed set.
"$BIN" "$CORPUS" --color-by=bogus --html --no-cache >"$TMP/4b.out" 2>"$TMP/4b.err"
rc=$?
if [ "$rc" -ne 0 ] && grep -q 'unknown value' "$TMP/4b.err" && grep -q 'lang|community|cx|churn|tested' "$TMP/4b.err"; then
    ok "--color-by=bogus refuses (rc=$rc), names \"unknown value\" and the allowed set"
else
    no "--color-by=bogus did not refuse-and-explain correctly (rc=$rc)"
    sed 's/^/    /' "$TMP/4b.err"
fi

# 4c) --color-by= (empty value) must refuse as a bad VALUE, not as an unknown FLAG (r27-emitters T5).
"$BIN" "$CORPUS" --color-by= --html --no-cache >"$TMP/4c.out" 2>"$TMP/4c.err"
rc=$?
if [ "$rc" -ne 0 ] && grep -q 'unknown value' "$TMP/4c.err"; then
    ok "--color-by= (empty value) refuses as a bad VALUE (rc=$rc)"
else
    no "--color-by= (empty value) did not refuse as a bad value (rc=$rc)"
    sed 's/^/    /' "$TMP/4c.err"
fi

# ── 5) self-containment (no CDN) on the coloured output ──────────────────────────────────────────────
"$BIN" "$CORPUS" --html --color-by=community --no-cache >"$TMP/colored.html" 2>/dev/null
if grep -qE '<script[^>]+src=' "$TMP/colored.html" 2>/dev/null; then
    no "self-contained: external <script src= found"
else
    ok "self-contained: no external <script src=>"
fi
if grep -qE '<link[^>]+href=' "$TMP/colored.html" 2>/dev/null; then
    no "self-contained: external <link href= found"
else
    ok "self-contained: no external <link href=>"
fi
# zero external http(s):// resource references anywhere (CSP-safe) — the only http(s) text allowed is
# inside an xmlns attribute (none expected in HTML, but written generically so a future one is fine).
if grep -oE 'https?://[^"'"'"' <>]+' "$TMP/colored.html" 2>/dev/null | grep -vq 'xmlns'; then
    no "self-contained: found http(s):// reference outside xmlns"
else
    ok "self-contained: no http(s):// resource references beyond xmlns"
fi

# ── 6) HONESTY: "not measured" must never render as a measured value ─────────────────────────────────

# A corpus whose test/ file reaches a src/ symbol, so `tested` has something true to say, and which
# has NO git history at all (mktemp is not a work tree) — the churn-disclosure case.
NOGIT="$TMP/nogit"; mkdir -p "$NOGIT/src" "$NOGIT/test"
printf 'int covered() { return 1; }\n'        > "$NOGIT/src/covered.cpp"
printf 'void test_covered() { covered(); }\n' > "$NOGIT/test/test_covered.cpp"
printf 'int lonely() { return 2; }\n'         > "$NOGIT/src/lonely.cpp"

# 6a) the NULL testedPtr trap: a bare --html run (no --metrics/--for/--exemplar) must MEASURE tested.
"$BIN" "$NOGIT" --html --no-cache >"$TMP/ts_bare.html" 2>/dev/null
if grep -q '"ts":1' "$TMP/ts_bare.html"; then
    ok "(6a) bare --html measures tested (a covered symbol reads ts:1, not a null-pointer 0)"
else
    no "(6a) bare --html has no ts:1 — 'not computed' is masquerading as 'untested'"
fi

# 6b) ... and it agrees with the path that computes QMetrics upstream. Without this control (6a) could
#     pass on any accidental 1, and a regression to null could hide behind a differently-seeded lens.
"$BIN" "$NOGIT" --html --metrics --no-cache >"$TMP/ts_metrics.html" 2>/dev/null
tsBare="$(    grep -oE '"ts":[01]' "$TMP/ts_bare.html"    | tr '\n' ',' )"
tsMetrics="$( grep -oE '"ts":[01]' "$TMP/ts_metrics.html" | tr '\n' ',' )"
if [ -n "$tsBare" ] && [ "$tsBare" = "$tsMetrics" ]; then
    ok "(6b) bare --html ts= matches --html --metrics ts= (same measured fact on both paths)"
else
    no "(6b) ts= disagrees between bare (--html) and upstream (--html --metrics) paths"
    printf '    bare=%s\n    metrics=%s\n' "$tsBare" "$tsMetrics"
fi

# 6c) no git history ⇒ CHURN_OK = 0. The zeros are not evidence and must not be published as facts.
if grep -q 'const CHURN_OK = 0;' "$TMP/ts_bare.html"; then
    ok "(6c) no git history: CHURN_OK = 0 (zeros are disclosed, not published)"
else
    no "(6c) no git history: CHURN_OK is not 0 — churn zeros would paint as measured commits"
fi

# 6d) ... and the legend SAYS so, rather than drawing the 5-step ramp over fabricated zeros.
if grep -q 'churn unavailable (no git history)' "$TMP/ts_bare.html"; then
    ok "(6d) the churn legend discloses 'churn unavailable (no git history)'"
else
    no "(6d) no churn-unavailable legend text — an empty lens would read as a real one"
fi

# 6e) CONTROL for (6c): a git-backed corpus must read CHURN_OK = 1, so (6c) cannot be passing on a
#     hardwired zero (the failure mode that makes an honesty arm inert).
GITC="$TMP/gitc"; mkdir -p "$GITC/src"
printf 'int alpha() { return 1; }\n'          > "$GITC/src/alpha.cpp"
printf 'int beta() { return alpha(); }\n'     > "$GITC/src/beta.cpp"
( cd "$GITC" && git init -q . && git config user.email g@e && git config user.name g \
    && git config commit.gpgsign false && git add -A && git commit -qm base ) >/dev/null 2>&1
"$BIN" "$GITC" --html --no-cache >"$TMP/gitc.html" 2>/dev/null
if grep -q 'const CHURN_OK = 1;' "$TMP/gitc.html"; then
    ok "(6e) control: a git-backed corpus reads CHURN_OK = 1 (the flag is measured, not hardwired)"
else
    no "(6e) control: git-backed corpus did not read CHURN_OK = 1 — the disclosure flag is inert"
fi

# 6f) community: a symbol with no surviving module (comm < 0) gets its OWN swatch and a 'none' label,
#     not module 0's colour. Same rule as the churn disclosure, applied per node.
if grep -q "n.comm < 0" "$TMP/out.html" && grep -q "'none'" "$TMP/out.html"; then
    ok "(6f) community lens gives moduleless nodes (comm<0) a distinct swatch labelled 'none'"
else
    no "(6f) community lens has no comm<0 'none' case — moduleless nodes would read as module 0"
fi

# ── 7) the ZERO-VIEWPORT seed: spread floored so a W=H=0 boot cannot seed every node coincident ──────
if grep -q 'Math.max(Math.min(W,H)\*0.7, 300)' "$TMP/out.html"; then
    ok "(7a) seed spread is floored at 300 world units"
else
    no "(7a) seed spread is not floored — a zero-sized viewport seeds every node coincident (one-dot render)"
fi
if grep -q '(rng()-0.5)\*Math.min(W,H)\*0.7' "$TMP/out.html"; then
    no "(7b) the UNFLOORED seed expression survives — the floor is dead code next to it"
else
    ok "(7b) no unfloored seed expression remains"
fi

# ── 8) G5 additivity: the flagless map is untouched by any of this ───────────────────────────────────
"$BIN" "$CORPUS" --no-cache >"$TMP/plain.xml" 2>/dev/null
if [ -s "$TMP/plain.xml" ] && ! grep -q 'COLOR_MODE\|colorMode\|CHURN_OK' "$TMP/plain.xml"; then
    ok "(8) the flagless XML map carries no colour-mode payload (purely additive)"
else
    no "(8) the flagless XML map is empty or leaked colour-mode payload"
fi

# ── 9) PALETTE — the shared cx/churn ramp reads as a blue→orange TEMPERATURE spectrum (the owner's own
#      framing: "hotspots... colour spectrum from dark blue to orange"), not a green→red traffic light.
#      Green→red leans entirely on red-green hue discrimination, which protanopia/deuteranopia (~8% of
#      men) cannot make — the two ends can look alike. A blue→azure→aqua→amber→gold ramp keeps
#      every step on the blue-yellow axis those forms of colour-blindness do NOT impair, and every stop
#      is bright enough (worst stop 4.75:1 against the canvas's #111 background, measured) to read on the
#      dark canvas — a literal navy/near-black "dark blue" would vanish there instead.
#
#      THIS ARM PINS THE IDENTITY, NOT THE PROPERTIES. The five stops changed on 2026-09-06 because the
#      ramp that shipped before was not monotone in luminance (its dark→light order was [4,3,1,0,2], so
#      the brightest swatch was the MIDDLE bucket) and its first two stops were 29/441 apart under
#      deuteranopia. Those are measured properties and a hex pin is the wrong instrument for them — it
#      passes for any five colours somebody typed. They are re-derived from the stops the page actually
#      emits by test/htmlrendercheck.sh arm (Q): luminance monotonicity, contrast against the ground, and
#      a Brettel/Viénot CVD simulation, each with its own mutation control. What stays here is what this
#      file is for — that the emitted ramp is the one the colour payload is documented to carry, and that
#      neither the old green nor the old red stop survives on THIS ramp specifically. rampColor is
#      grepped as its own line; the 'tested' mode's own two fills (a different, deliberately-binary
#      convention, colorForNode's 'tested' branch + its legend) are untouched by this arm on purpose,
#      not by omission.
rampLine="$( grep -m1 'var rampColor' "$TMP/out.html" )"
if printf '%s' "$rampLine" | grep -qF "['#4b81c9','#0fa3ff','#2bccc0','#ffce1c','#fff794']"; then
    ok "(9a) rampColor is the cool-to-hot 5-stop heat ramp"
else
    no "(9a) rampColor is not the expected cool-to-hot ramp"
    printf '    got: %s\n' "$rampLine"
fi
if printf '%s' "$rampLine" | grep -q '#2ecc71\|#e74c3c'; then
    no "(9b) rampColor still carries the old green/red traffic-light stop"
else
    ok "(9b) rampColor carries neither the old green nor the old red stop"
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi

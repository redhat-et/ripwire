#!/usr/bin/env bash
# scipjoincheck.sh — the SCIP JOIN gate: how a SCIP occurrence binds to a ripwire site, and how the
# census transcribes a SCIP resolution that is NOT a ripwire definition.
#
#   test/scipjoincheck.sh                    # uses build/ripwire on test/scipjoinfix
#   RIPWIRE_BIN=asan/ripwire test/scipjoincheck.sh
#
# WHY THIS GATE EXISTS (docs/EVALS.md, "Phase 3 — the SCIP join diagnosed", registered 2026-09-03).
# `src/scip.h::buildScipOverlay` used to bind a SCIP definition occurrence to whatever ripwire symbol
# was FIRST on that exact line, keyed by the raw symbol string. Two consequences on astropy: `local N`
# (document-scoped in SCIP) bound one file's symbol for every same-numbered local in every other file
# — 48,705 phantom "internal" occurrences and phantom precise edges — and a parameter's definition
# (on the `def` line) bound the enclosing function itself, 63,989 self-loop "internal" occurrences.
# The honesty line's 47% was a ratio of those two polluted counts. Separately, a SCIP resolution to
# something that is not a ripwire definition (a builtin, a parameter, an attribute ripwire does not
# extract) was indistinguishable from SCIP silence, so the census could not count it as the
# disconfirmation the registration says it is.
#
# THE FIXTURE (test/scipjoinfix/: a.py, b.py, index.scip from make_index.py — line numbers there):
#   * local trap      `local 0` def on a.py:2 (sum's line) + `local 0` ref on b.py:6 (inside K.run)
#   * parameter trap  `Box#go().(model)` def on a.py:9 (go's own line); `model(1)` on a.py:10 resolves
#                     to that PARAMETER in SCIP, while ripwire's tier {Box.model, model} is S6-C-pinned
#   * external        `sum(vals)` on a.py:8 resolves to `builtins/sum().` in SCIP; ripwire -> a.py::sum
#   * control         `helper()` on b.py:6 resolves to b.py::helper in both
#
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/scipjoinfix"
IDX="$CORPUS/index.scip"
EXC="--exclude=make_index.py"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -f "$IDX" ] || { echo "fixture index missing: $IDX (python3 test/scipjoinfix/make_index.py)"; exit 2; }
echo "scipjoincheck: BIN=$BIN  CORPUS=$CORPUS"

# ── (A) the fixture reproduces the shapes: a locality pin and two unique resolutions ──────────────
"$BIN" "$CORPUS" $EXC --no-cache --pin-census="$TMP/plain.tsv" >"$TMP/plain.xml" 2>"$TMP/plain.err" || no "(A) plain run failed"
awk -F'\t' '$1=="C" && $2=="locality" && $6 ~ /^a\.py::Box::go#/ && $7=="model" && $8 ~ /^a\.py::Box::model#/' "$TMP/plain.tsv" | grep -q . \
    && ok "(A) Box.go -> model is S6-C locality-pinned to Box.model (the shape under audit)" \
    || { no "(A) Box.go -> model is not a locality pin to Box.model"; grep '^C' "$TMP/plain.tsv" | sed 's/^/          /'; }
awk -F'\t' '$1=="C" && $2=="unique" && $6 ~ /^a\.py::Box::total#/ && $7=="sum"' "$TMP/plain.tsv" | grep -q . \
    && ok "(A) Box.total -> sum resolves uniquely to a.py::sum" || no "(A) Box.total -> sum is not a unique resolution"
awk -F'\t' '$1=="C" && $6 ~ /^b\.py::K::run#/ && $7=="helper"' "$TMP/plain.tsv" | grep -q . \
    && ok "(A) K.run -> helper is decided" || no "(A) no decided K.run -> helper row"

# ── (B) the control: an ordinary in-repo resolution is transcribed as before ─────────────────────
"$BIN" "$CORPUS" $EXC --no-cache --scip="$IDX" --pin-census="$TMP/scip.tsv" >"$TMP/scip.xml" 2>"$TMP/scip.err" || no "(B) --scip run failed"
awk -F'\t' '$1=="O" && $2 ~ /^b\.py::K::run#/ && $3=="helper" && $4 ~ /^b\.py::helper#/' "$TMP/scip.tsv" | grep -q . \
    && ok "(B) O row K.run -> helper names b.py::helper (in-repo oracle, unchanged)" \
    || { no "(B) no in-repo O row for K.run -> helper"; grep '^O' "$TMP/scip.tsv" | sed 's/^/          /'; }

# ── (C) the LOCAL trap: `local N` is document-scoped and never binds ──────────────────────────────
if awk -F'\t' '$1=="O" && $2 ~ /^b\.py::K::run#/ && $3=="sum"' "$TMP/scip.tsv" | grep -q .; then
    no "(C) phantom O row K.run -> sum: a b.py \`local 0\` reference bound a.py::sum through a global local key"
else
    ok "(C) no phantom K.run -> sum row — \`local 0\` did not bind across files"
fi
grep -q 'prov="scip"' "$TMP/scip.xml" && ok "(C) the map still carries prov=\"scip\" edges (the control pinned)" || no "(C) no prov=\"scip\" edge at all"
N_SUM_EDGE="$( tr '>' '\n' <"$TMP/scip.xml" | awk '/id="b.py::K::run"/{f=1} f&&/n="sum"/{c++} /\/s/{if(f)exit} END{print c+0}' )"
[ "$N_SUM_EDGE" = 0 ] && ok "(C) K.run emits no phantom edge to sum" || no "(C) K.run carries $N_SUM_EDGE phantom sum edge(s) from the local collision"

# ── (D) the PARAMETER trap: a parameter never binds its function; the call is a NON-DEF resolution ─
PARAM_ROW="$( awk -F'\t' '$1=="O" && $2 ~ /^a\.py::Box::go#/ && $3=="model" {print $4}' "$TMP/scip.tsv" )"
[ "$PARAM_ROW" = "@nondef" ] && ok "(D) O row Box.go -> model carries the @nondef sentinel (SCIP: the parameter)" \
    || no "(D) Box.go -> model O row target is '${PARAM_ROW:-<absent>}', want @nondef"

# ── (E) an EXTERNAL resolution is transcribed, not dropped as silence ─────────────────────────────
EXT_ROW="$( awk -F'\t' '$1=="O" && $2 ~ /^a\.py::Box::total#/ && $3=="sum" {print $4}' "$TMP/scip.tsv" )"
[ "$EXT_ROW" = "@external" ] && ok "(E) O row Box.total -> sum carries the @external sentinel (SCIP: builtins/sum)" \
    || no "(E) Box.total -> sum O row target is '${EXT_ROW:-<absent>}', want @external"
# the sentinel is census-only: the shipped map must NOT drop or replace the name-based edge for it
tr '>' '\n' <"$TMP/scip.xml" | awk '/id="a.py::Box::total"/{f=1} f&&/n="sum"/{c++} /\/s/{if(f)exit} END{exit !(c==1)}' \
    && ok "(E) the map keeps Box.total's name-based sum edge (a sentinel never edits the graph)" \
    || no "(E) Box.total's sum edge changed under --scip"
grep -c 'prov="scip"' "$TMP/scip.xml" >/dev/null
N_PREC="$( grep -o 'precise=[0-9]*' "$TMP/scip.xml" | head -1 | cut -d= -f2 )"
[ "$N_PREC" = 1 ] && ok "(E) precise=1 — exactly the control edge is pinned; sentinels pin nothing" \
    || no "(E) precise=$N_PREC, want 1 (only K.run -> helper is an in-repo resolution)"

# ── (F) the honesty line counts only what can bind ────────────────────────────────────────────────
LINE="$( grep 'SCIP matched' "$TMP/scip.err" )"
printf '%s' "$LINE" | grep -q '(1/1)' && ok "(F) stderr: SCIP matched 1/1 internal occurrences (the local ref is not internal)" \
    || no "(F) stderr honesty line: ${LINE:-<none>} — want (1/1)"

# ── (G) the harness reads both definitions ────────────────────────────────────────────────────────
python3 "$ROOT/bench/scip_pin_precision.py" --bin "$BIN" --repo "$CORPUS" --scip "$IDX" --exclude make_index.py \
        --workdir "$TMP" --label join --json "$TMP/join.json" >"$TMP/harness.out" 2>&1 || no "(G) harness failed: $( tail -3 "$TMP/harness.out" )"
python3 - "$TMP/join.json" <<'PY' && ok "(G) harness: locality covered=1 precision=0.000 (full oracle), in-repo-only covered=0" || no "(G) harness readout wrong: $( cat "$TMP/harness.out" | tail -12 )"
import json, sys
j = json.load( open( sys.argv[ 1 ] ) )
loc = j[ "rows" ][ "locality" ]
assert loc[ "covered" ] == 1 and loc[ "confirmed" ] == 0, loc
assert loc[ "covered_inrepo" ] == 0, loc
assert loc[ "sentinel_nondef" ] == 1 and loc[ "sentinel_external" ] == 0, loc
uni = j[ "rows" ][ "unique" ]
assert uni[ "sentinel_external" ] == 1, uni
PY

# ── (H) G5 additivity + determinism + well-formedness ─────────────────────────────────────────────
"$BIN" "$CORPUS" $EXC --no-cache --scip="$IDX" >"$TMP/scip2.xml" 2>/dev/null
cmp -s "$TMP/scip.xml" "$TMP/scip2.xml" && ok "(H) stdout byte-identical with and without --pin-census under --scip" \
    || no "(H) --pin-census changed stdout under --scip"
"$BIN" "$CORPUS" $EXC --no-cache --scip="$IDX" --pin-census="$TMP/scip3.tsv" >"$TMP/scip3.xml" 2>/dev/null
cmp -s "$TMP/scip.tsv" "$TMP/scip3.tsv" && ok "(H) the census is byte-identical run to run" || no "(H) census differs between two armed runs"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/scip.xml" 2>/dev/null && ok "(H) --scip map is well-formed XML" || no "(H) --scip map fails xmllint"
fi

[ "$fail" = 0 ] && { echo "scipjoincheck: OK"; exit 0; }
echo "scipjoincheck: FAILURES ABOVE"; exit 1

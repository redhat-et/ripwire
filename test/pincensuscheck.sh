#!/usr/bin/env bash
# pincensuscheck.sh — the S6-C SILENT-PIN CENSUS surface gate (`--pin-census=FILE`).
#
#   test/pincensuscheck.sh                    # uses build/ripwire on test/pincensusfix
#   RIPWIRE_BIN=asan/ripwire test/pincensuscheck.sh
#
# WHY THIS GATE EXISTS. `src/graph.h`'s S6-C locality tie-break resolves a still-ambiguous call to the
# candidate whose canonical id shares the longest whole-SEGMENT prefix with the caller's, and when that
# leaves exactly one survivor it emits a CONFIDENT edge and deliberately does NOT increment `amb=`. The
# map's serialized form is `<c n="NAME"/>` — a callee NAME with no target identity — so nothing in the
# shipped output distinguishes a locality-pinned guess from a qualified, receiver-narrowed or otherwise
# evidence-backed resolution. `bench/scip_amb_precision.py` inherits that blindness: it groups by name
# collision, and a pinned site scores 1.0 by construction whether the pin was right or wrong.
#
# The census is the instrument that ends the blindness: an eval-only, flag-gated side file naming, per
# decided call site, the caller's canonical id, the callee name, the MECHANISM that decided it, and the
# canonical id of every surviving target. Arms (A) and (D) pin the SILENCE itself so a future change that
# quietly starts (or stops) counting these pins in `amb=` cannot pass; arms (C)/(D) pin the label's
# discrimination; (E)/(F) pin G5 additivity and determinism; (G) pins the oracle side of the join.
#
# THE FIXTURE (test/pincensusfix/, 2 files, ~30 lines) reproduces both shapes in the smallest form:
#   pinned.py — `Alpha.run` bare-calls `helper()`; `Alpha.helper` and `Beta.helper` both live in this
#               file, so tier 1 keeps BOTH and S6-C decides: `pinned.py::Alpha::` beats `pinned.py::`.
#               ONE edge, NO `amb=` — the silent pin.
#   tied.py   — `Eps.go` bare-calls `other()`; `Gamma.other` and `Delta.other` are SIBLINGS, so both
#               share exactly `tied.py::` and NEITHER is more local. The tier stays full, the call
#               splits, `amb=` counts it — the honest control.
#
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/pincensusfix"
SCIPFIX="$ROOT/test/scipfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "fixture missing: $CORPUS"; exit 2; }

echo "pincensuscheck: BIN=$BIN  CORPUS=$CORPUS"

# ── (A) THE SILENCE, reproduced — the subject of the census, asserted on the shipped map ───────────
# This arm is deliberately about CURRENT behaviour: the locality pin emits one confident edge and does
# not raise `amb=`. It is the documented S6-C contract; a change that alters it must come with its own
# registered justification, and this arm is where that shows up.
MAP="$( "$BIN" "$CORPUS" --no-cache 2>/dev/null )"
RUN_ROW="$( printf '%s' "$MAP" | tr '<' '\n' | grep 'id="pinned.py::Alpha::run"' )"
GO_ROW="$( printf '%s' "$MAP" | tr '<' '\n' | grep 'id="tied.py::Eps::go"' )"
if printf '%s' "$RUN_ROW" | grep -q 'amb='; then
    no "(A) pinned.py::Alpha::run carries amb= — the locality pin is no longer silent: $RUN_ROW"
else
    ok "(A) the locality pin is SILENT — pinned.py::Alpha::run carries no amb="
fi
N_HELPER="$( printf '%s' "$MAP" | tr '>' '\n' | awk '/id="pinned.py::Alpha::run"/{f=1} f{print} /\/s/{if(f)exit}' | grep -c 'n="helper"' )"
[ "$N_HELPER" = 1 ] && ok "(A) the pin emitted ONE confident edge (not a split)" \
    || no "(A) pinned.py::Alpha::run emitted $N_HELPER helper edges, want 1"
printf '%s' "$GO_ROW" | grep -q 'amb="1"' && ok "(A) the tied control is HONEST — tied.py::Eps::go carries amb=\"1\"" \
    || no "(A) tied.py::Eps::go does not carry amb=\"1\": $GO_ROW"
printf '%s' "$MAP" | grep -q 'ambiguous=1 ' && ok "(A) header ambiguous=1 — the pin contributes ZERO to the disclosed gauge" \
    || no "(A) header ambiguous= is not 1: $( printf '%s' "$MAP" | grep -o 'ambiguous=[0-9]*' | head -1 )"

# ── (B) the census surface exists and declares itself ─────────────────────────────────────────────
"$BIN" "$CORPUS" --pin-census="$TMP/c1.tsv" --no-cache >"$TMP/map1" 2>"$TMP/err1"
rc=$?
[ "$rc" = 0 ] && ok "(B) --pin-census exits 0" || { no "(B) --pin-census exited $rc"; sed 's/^/          /' "$TMP/err1"; }
if [ -s "$TMP/c1.tsv" ]; then
    ok "(B) census file written ($( wc -l <"$TMP/c1.tsv" | tr -d ' ' ) lines)"
else
    no "(B) no census file at $TMP/c1.tsv"
fi
head -1 "$TMP/c1.tsv" 2>/dev/null | grep -q '^# ripwire pin-census v2' \
    && ok "(B) census declares its own format in a header line" \
    || no "(B) census header line missing/unrecognized: $( head -1 "$TMP/c1.tsv" 2>/dev/null )"

# ── (C) THE POINT — the census names the pinned site, its mechanism, and its TARGET IDENTITY ──────
# The map says `<c n="helper"/>`. The census must say WHICH helper, and that locality is what decided.
PIN_ROW="$( grep -E '^C	locality	' "$TMP/c1.tsv" 2>/dev/null | grep 'pinned.py::Alpha::run' )"
if [ -n "$PIN_ROW" ]; then
    ok "(C) the locality-pinned site is labelled: $PIN_ROW"
else
    no "(C) no 'C<TAB>locality' row for pinned.py::Alpha::run — the census cannot see the pin"
    grep -n 'Alpha::run' "$TMP/c1.tsv" 2>/dev/null | sed 's/^/          /'
fi
printf '%s' "$PIN_ROW" | grep -q 'pinned.py::Alpha::helper' \
    && ok "(C) the census carries the pinned TARGET's canonical id (the identity <c n=.../> omits)" \
    || no "(C) the pinned row does not name pinned.py::Alpha::helper — no identity to join an oracle against"
printf '%s' "$PIN_ROW" | grep -q 'pinned.py::Beta::helper' \
    && no "(C) the pinned row also lists Beta::helper — that candidate was DROPPED, not emitted" \
    || ok "(C) the pinned row lists exactly the surviving target"

# ── (D) mutation control — the label DISCRIMINATES (a tie is not a pin) ───────────────────────────
TIE_ROW="$( grep -E '^C	split	' "$TMP/c1.tsv" 2>/dev/null | grep 'tied.py::Eps::go' )"
if [ -n "$TIE_ROW" ]; then
    ok "(D) the full-tie site is labelled split, not locality: $TIE_ROW"
else
    no "(D) no 'C<TAB>split' row for tied.py::Eps::go — the label does not discriminate, so (C) means nothing"
    grep -n 'Eps::go' "$TMP/c1.tsv" 2>/dev/null | sed 's/^/          /'
fi
printf '%s' "$TIE_ROW" | grep -q 'tied.py::Gamma::other' && printf '%s' "$TIE_ROW" | grep -q 'tied.py::Delta::other' \
    && ok "(D) the split row lists BOTH surviving targets" \
    || no "(D) the split row does not list both Gamma::other and Delta::other"
grep -E '^C	locality	' "$TMP/c1.tsv" 2>/dev/null | grep -q 'tied.py::Eps::go' \
    && no "(D) tied.py::Eps::go is ALSO labelled locality — the label is not exclusive" \
    || ok "(D) no locality label on the tied site"

# ── (E) G5 — the flag is purely additive: stdout is byte-identical with and without it ────────────
"$BIN" "$CORPUS" --no-cache >"$TMP/map0" 2>/dev/null
if cmp -s "$TMP/map0" "$TMP/map1"; then
    ok "(E) stdout byte-identical with and without --pin-census (G5: every flag is purely additive)"
else
    no "(E) --pin-census CHANGED the map — the census surface is not output-invariant"
    diff <( fold -w120 "$TMP/map0" ) <( fold -w120 "$TMP/map1" ) | head -6 | sed 's/^/          /'
fi

# ── (F) determinism — the census is a contract, not a nicety ──────────────────────────────────────
"$BIN" "$CORPUS" --pin-census="$TMP/c2.tsv" --no-cache >/dev/null 2>&1
"$BIN" "$CORPUS" --pin-census="$TMP/c3.tsv" --no-cache >/dev/null 2>&1
if cmp -s "$TMP/c1.tsv" "$TMP/c2.tsv" && cmp -s "$TMP/c2.tsv" "$TMP/c3.tsv"; then
    ok "(F) three census runs are byte-identical"
else
    no "(F) the census is not deterministic across runs"
    diff "$TMP/c1.tsv" "$TMP/c2.tsv" | head -6 | sed 's/^/          /'
fi

# ── (G) the ORACLE side — under --scip the census carries SCIP's covered sites in the SAME id space ─
# Without this the census has one side of the join and nothing to join it to. test/scipfix ships a
# generated index whose `run` -> `handler` site SCIP pins to alpha.cpp.
if [ -f "$SCIPFIX/index.scip" ]; then
    "$BIN" "$SCIPFIX" --exclude=make_index.py --scip="$SCIPFIX/index.scip" --pin-census="$TMP/o.tsv" --no-cache >/dev/null 2>&1
    ORA="$( grep -E '^O	' "$TMP/o.tsv" 2>/dev/null | grep 'handler' )"
    if [ -n "$ORA" ]; then
        ok "(G) the census carries SCIP oracle rows: $ORA"
    else
        no "(G) no 'O' oracle rows under --scip — the census cannot be joined against ground truth"
        head -5 "$TMP/o.tsv" 2>/dev/null | sed 's/^/          /'
    fi
    printf '%s' "$ORA" | grep -q 'alpha.cpp' \
        && ok "(G) the oracle row names SCIP's target by canonical id (alpha.cpp), not by name" \
        || no "(G) the oracle row does not carry alpha.cpp's canonical id"
    grep -cE '^O	' "$TMP/o.tsv" >/dev/null 2>&1 && grep -qE '^C	' "$TMP/o.tsv" \
        && ok "(G) both sides (C decisions + O oracle) are present in one census" \
        || no "(G) the --scip census is missing one of the two row kinds"
else
    no "(G) test/scipfix/index.scip missing — the oracle arm cannot run (regenerate: python3 test/scipfix/make_index.py test/scipfix/index.scip)"
fi

# ── (I) the join's load-bearing assumption: identities are STABLE across the two runs ─────────────
# The census is measured by joining a PLAIN run (what the resolver decided) to a --scip run (what the
# index says). That join is only meaningful if a symbol carries the same identity in both, so the
# assumption is asserted here rather than assumed: NodeIds come from the sorted crawl at ingest, before
# any resolution, and --scip changes nothing upstream of that. If this arm ever goes red, every precision
# number joined this way is void — which is why it is a gate and not a comment.
if [ -f "$SCIPFIX/index.scip" ]; then
    "$BIN" "$SCIPFIX" --exclude=make_index.py --pin-census="$TMP/plain.tsv" --no-cache >/dev/null 2>&1
    PLAIN_ID="$( awk -F'\t' '$1=="C" && $7=="handler" {print $6; exit}' "$TMP/plain.tsv" 2>/dev/null )"
    SCIP_ID="$( awk -F'\t' '$1=="O" && $3=="handler" {print $2; exit}' "$TMP/o.tsv" 2>/dev/null )"
    if [ -n "$PLAIN_ID" ] && [ "$PLAIN_ID" = "$SCIP_ID" ]; then
        ok "(I) the caller identity is byte-identical in the plain and --scip censuses ($PLAIN_ID)"
    else
        no "(I) caller identity DIFFERS between runs — plain='$PLAIN_ID' scip='$SCIP_ID'; the join is void"
    fi
    printf '%s' "$PLAIN_ID" | grep -q '#' \
        && ok "(I) identities carry the #NODEID handle (not a bare, name-keyed id)" \
        || no "(I) identity '$PLAIN_ID' has no #NODEID handle — the join degrades to name matching"
fi

# ── (J) the call-site LINE rides on every C row (format v2) ───────────────────────────────────────
# WHY. Phase-3 of the census (docs/EVALS.md "The census, RUN") found coverage — SCIP speaking on only
# 38% of locality-pinned sites — to be the binding constraint on n, and the loss sits in the (file,line)
# join `src/scip.h::buildScipOverlay` performs. Diagnosing WHICH lines fail needs the resolver's own
# 1-based call-site line beside each decision; without it the census cannot be joined to a SCIP
# occurrence at all and the failure classes can only be guessed. The line is the LAST column so every
# v1 consumer (`awk $6/$7`, `parts[7]`) keeps reading unchanged.
RUN_LINE="$( awk -F'\t' '$1=="C" && $6 ~ /^pinned\.py::Alpha::run#/ && $7=="helper" {print $9; exit}' "$TMP/c1.tsv" 2>/dev/null )"
[ "$RUN_LINE" = 15 ] && ok "(J) the pinned site carries its call-site line as column 9 (15)" \
    || no "(J) column 9 of the pinned-site row is '$RUN_LINE', want 15 (pinned.py:15 is \`return helper()\`)"
GO_LINE="$( awk -F'\t' '$1=="C" && $7=="other" {print $9; exit}' "$TMP/c1.tsv" 2>/dev/null )"
[ "$GO_LINE" = "$( grep -n 'return other()' "$CORPUS/tied.py" | cut -d: -f1 )" ] \
    && ok "(J) the tied control carries its call-site line too ($GO_LINE)" \
    || no "(J) tied.py::Eps::go row column 9 is '$GO_LINE', want the \`return other()\` line"
head -1 "$TMP/c1.tsv" 2>/dev/null | grep -q 'line' \
    && ok "(J) the header line names the new column" \
    || no "(J) the header does not declare the line column: $( head -1 "$TMP/c1.tsv" )"

# ── (K) the definition universe rides along as S rows (format v2) ─────────────────────────────────
# WHY. The other half of the SCIP join is the DEF side: `buildScipOverlay` maps a SCIP definition
# occurrence to a ripwire symbol by exact (file, line). Classifying a def-side miss needs every symbol
# ripwire holds with its line — a table no shipped surface lists in full (`--pack-signatures` is a
# top-50 payload). One `S` row per symbol: id (with #NODEID), kind tag, 1-based def line.
S_RUN="$( awk -F'\t' '$1=="S" && $2 ~ /^pinned\.py::Alpha::run#/ {print $3 "/" $4; exit}' "$TMP/c1.tsv" 2>/dev/null )"
[ "$S_RUN" = "fn/14" ] && ok "(K) S row for pinned.py::Alpha::run carries kind and def line (fn/14)" \
    || no "(K) S row for pinned.py::Alpha::run is '$S_RUN', want fn/14"
N_S="$( grep -c '^S	' "$TMP/c1.tsv" )"
N_SYM="$( printf '%s' "$MAP" | grep -o 'symbols=[0-9]*' | head -1 | cut -d= -f2 )"
[ "$N_S" = "$N_SYM" ] && ok "(K) one S row per symbol ($N_S == header symbols=$N_SYM)" \
    || no "(K) $N_S S rows but the map header says symbols=$N_SYM"
grep -q "symbols=$N_SYM" <( tail -1 "$TMP/c1.tsv" ) && ok "(K) the summary line counts the S rows" \
    || no "(K) summary line lacks symbols=$N_SYM: $( tail -1 "$TMP/c1.tsv" )"

# ── (H) an empty value is REFUSED, never silently treated as "no census" ──────────────────────────
"$BIN" "$CORPUS" --pin-census= --no-cache >/dev/null 2>"$TMP/empty.err"
rc=$?
if [ "$rc" != 0 ] && grep -qi 'pin-census' "$TMP/empty.err"; then
    ok "(H) --pin-census= (empty) is refused by name"
else
    no "(H) --pin-census= (empty) was not refused (rc=$rc): $( head -1 "$TMP/empty.err" )"
fi

[ "$fail" = 0 ] && { echo "pincensuscheck: OK"; exit 0; }
echo "pincensuscheck: FAILURES ABOVE"; exit 1

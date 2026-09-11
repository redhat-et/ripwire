#!/usr/bin/env bash
# lpincheck.sh — the S6-C pin DISCLOSURE gate: `lpin="K"` / `locality_pinned=N` + the localityKey tie-break.
#
#   test/lpincheck.sh                    # uses build/ripwire on test/lpinfix
#   RIPWIRE_BIN=asan/ripwire test/lpincheck.sh
#
# WHY THIS GATE EXISTS. The S6-C locality tie-break (src/graph.h) resolves a still-ambiguous call to the
# candidate whose canonical id shares the longest whole-segment prefix with the caller's, and when ONE
# survivor remains it emits a confident edge and does NOT count the site in `amb=`. The full-oracle census
# (docs/EVALS.md "Phase 3, RUN") put that pin's precision at 0.368 on astropy: a prior's guess, shipped
# with the same face as a qualified resolution. Phase 4 discloses it WITHOUT inflating `amb=`: a per-row
# `lpin="K"` and a header `locality_pinned=N`, both absent when zero, both in the legend. The same phase
# re-applies the `Graph::localityKey` tie-break (an unscoped def is compared as `path::name`, not its bare
# name) so a module-level function is no longer auto-lost to a same-file class method.
#
# THE FIXTURE (test/lpinfix/, 3 files):
#   pinned.py   — `Alpha.run` -> `helper()`; `Alpha.helper` beats `Beta.helper` by scope: ONE edge, `lpin="1"`, no `amb=`.
#   tied.py     — `Eps.go` -> `other()`; sibling classes tie: split, `amb="1"`, no `lpin=`.
#   modlevel.py — `Caller.go` -> `compute()`; `Helper.compute` vs module-level `compute`: a full tie under
#                 localityKey ⇒ split, `amb="1"`, no `lpin=` (was a silent pin on Helper::compute).
#
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/lpinfix"
FIXTURE="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "fixture missing: $CORPUS"; exit 2; }

echo "lpincheck: BIN=$BIN  CORPUS=$CORPUS"

"$BIN" "$CORPUS" --pin-census="$TMP/c.tsv" --no-cache >"$TMP/map.xml" 2>"$TMP/err" || { no "the map run exited non-zero"; sed 's/^/          /' "$TMP/err"; }
MAP="$( cat "$TMP/map.xml" )"
row(){ printf '%s' "$MAP" | tr '<' '\n' | grep "id=\"$1\"" | head -1; }

# ── (A) the pin is DISCLOSED on its row, and it is still not an amb ──────────────────────────────
RUN_ROW="$( row 'pinned.py::Alpha::run' )"
printf '%s' "$RUN_ROW" | grep -q 'lpin="1"' && ok "(A) pinned.py::Alpha::run carries lpin=\"1\" — the locality pin is disclosed" \
    || no "(A) pinned.py::Alpha::run has no lpin=\"1\": $RUN_ROW"
printf '%s' "$RUN_ROW" | grep -q 'amb=' && no "(A) pinned.py::Alpha::run carries amb= — the marker inflated amb=: $RUN_ROW" \
    || ok "(A) the pin still contributes nothing to amb="
N_HELPER="$( printf '%s' "$MAP" | tr '>' '\n' | awk '/id="pinned.py::Alpha::run"/{f=1} f{print} /\/s/{if(f)exit}' | grep -c 'n="helper"' )"
[ "$N_HELPER" = 1 ] && ok "(A) the pin still emits ONE confident edge" || no "(A) $N_HELPER helper edges on Alpha::run, want 1"

# ── (B) the tied control — a split is not a pin ───────────────────────────────────────────────────
GO_ROW="$( row 'tied.py::Eps::go' )"
printf '%s' "$GO_ROW" | grep -q 'amb="1"' && ok "(B) tied.py::Eps::go carries amb=\"1\" (the honest split)" \
    || no "(B) tied.py::Eps::go lacks amb=\"1\": $GO_ROW"
printf '%s' "$GO_ROW" | grep -q 'lpin=' && no "(B) tied.py::Eps::go carries lpin= — a split labelled as a pin: $GO_ROW" \
    || ok "(B) no lpin= on the split"

# ── (C) the module-level shape — a full tie under localityKey, not a silent pin ──────────────────
CALLER_ROW="$( row 'modlevel.py::Caller::go' )"
printf '%s' "$CALLER_ROW" | grep -q 'amb="1"' && ok "(C) modlevel.py::Caller::go is an honest split (amb=\"1\") — the module-level def is no longer auto-lost" \
    || no "(C) modlevel.py::Caller::go is not amb=\"1\" — Helper::compute still silently wins: $CALLER_ROW"
printf '%s' "$CALLER_ROW" | grep -q 'lpin=' && no "(C) modlevel.py::Caller::go carries lpin= — still pinned: $CALLER_ROW" \
    || ok "(C) no lpin= on the module-level site"
grep -E '^C	locality	' "$TMP/c.tsv" | grep -q 'modlevel.py::Caller::go' \
    && no "(C) the census still labels modlevel.py::Caller::go locality-pinned" \
    || ok "(C) the census agrees: no locality row for modlevel.py::Caller::go"

# ── (D) the header counter, and its equality with the census ──────────────────────────────────────
HDR="$( printf '%s' "$MAP" | grep -o '<!-- files=[^>]*-->' | head -1 )"
printf '%s' "$HDR" | grep -q ' locality_pinned=1 ' && ok "(D) header locality_pinned=1" || no "(D) header lacks locality_pinned=1: $HDR"
printf '%s' "$HDR" | grep -q ' ambiguous=2 ' && ok "(D) header ambiguous=2 — the marker added nothing, the tie-break added exactly the module-level split" \
    || no "(D) header ambiguous= is not 2: $HDR"
N_LOC="$( grep -cE '^C	locality	' "$TMP/c.tsv" )"
HDR_LP="$( printf '%s' "$HDR" | grep -o 'locality_pinned=[0-9]*' | cut -d= -f2 )"
[ -n "$HDR_LP" ] && [ "$HDR_LP" = "$N_LOC" ] && ok "(D) locality_pinned=$HDR_LP == $N_LOC census 'C<TAB>locality' rows — marker and census name one population" \
    || no "(D) locality_pinned='$HDR_LP' but the census holds $N_LOC locality rows"

# ── (E) zero bytes where nothing fires (the dropped_positive= rule) ───────────────────────────────
( cd "$ROOT" && "$BIN" test/fixture --no-cache >"$TMP/fix.xml" 2>/dev/null )   # repo-relative, exactly how the golden is derived
grep -q 'lpin=' <( grep -v '^<!-- ripwire v1' "$TMP/fix.xml" ) && no "(E) test/fixture emits lpin= — it has no locality pin" \
    || ok "(E) test/fixture: no lpin= outside the legend"
grep -q 'locality_pinned=[0-9]' "$TMP/fix.xml" && no "(E) test/fixture header carries locality_pinned= — want absent when 0" \
    || ok "(E) test/fixture: no locality_pinned= (absent when 0)"
cmp -s "$TMP/fix.xml" "$ROOT/test/golden.xml" && ok "(E) test/golden.xml byte-identical — the marker costs the pin-free map nothing" \
    || no "(E) test/fixture map differs from test/golden.xml"

# ── (F) the legend defines both names (legendcoveragecheck's definitional predicate) ─────────────
LEGEND="$( printf '%s' "$MAP" | grep -o '<!-- ripwire v1[^>]*-->' | head -1 )"
printf '%s' "$LEGEND" | grep -q ' lpin=' && ok "(F) legend defines lpin=" || no "(F) legend lacks lpin=: $LEGEND"
printf '%s' "$LEGEND" | grep -q 'locality_pinned=' && ok "(F) legend defines locality_pinned=" || no "(F) legend lacks locality_pinned="

# ── (G) the --json dialect carries the same two facts ─────────────────────────────────────────────
"$BIN" "$CORPUS" --json --no-cache >"$TMP/map.json" 2>/dev/null
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TMP/map.json" 2>/dev/null && ok "(G) --json parses" || no "(G) --json output does not parse"
grep -q '"lpin":1' "$TMP/map.json" && ok "(G) --json carries \"lpin\":1" || no "(G) --json lacks \"lpin\":1"
grep -q '"locality_pinned":1' "$TMP/map.json" && ok "(G) --json header carries \"locality_pinned\":1" || no "(G) --json header lacks \"locality_pinned\":1"
"$BIN" "$FIXTURE" --json --no-cache 2>/dev/null | grep -q '"lpin"\|"locality_pinned"' && no "(G) --json on test/fixture emits the keys with nothing to disclose" \
    || ok "(G) --json on test/fixture: both keys absent"

# ── (I) the caller never wins its own locality tie-break — the LANGUAGE-AGNOSTIC arm ──────────────
# src/graph.h scores a tier candidate that IS the caller `c == r.fromSymbol` as locality ZERO. Without it the
# caller's own def matches itself on every segment, wins the tie-break alone, and emission then drops it as a
# self-loop: the site produces NO edge at all, silently. Found through Ruby (test/rubyscopecheck.sh's facade
# arm) but nothing about it is Ruby — the fixture below is PYTHON and was measured RED before the fix (edges=0)
# and GREEN after (2 split edges, amb="1"). This arm is the reason a revert of that one line goes red for the
# right reason, in a language the Ruby gates never touch.
#
# STATED FLOOR, pinned here so it stays a decision rather than an oversight: the fix is the TIE-BREAK only.
# Tier 1 admits same-FILE candidates and stops when any exist, so a caller that is the only same-file candidate
# is still selected alone and still dropped as a self-loop — the second fixture below (two files) is that
# residual, asserted to produce NOTHING. Widening tier 1 past the caller would mint a cross-file edge the
# same-file tier already outranked; a call on another instance of the caller's own class is a real self-loop.
SELFD="$TMP/selfwin"; mkdir -p "$SELFD"
cat > "$SELFD/facade.py" <<'PYEOF'
class Facade:
    def publish_event(self, event):
        return notifier.publish_event(event)


class Fanout:
    def publish_event(self, event):
        return 1


class Subscriber:
    def publish_event(self, event):
        return 2
PYEOF
"$BIN" "$SELFD" --no-cache >"$TMP/selfwin.xml" 2>/dev/null
SW="$( sed 's/></>\n</g' "$TMP/selfwin.xml" | awk '/id="facade.py::Facade::publish_event"/{f=1;print;next} /^<s /{f=0} f' )"
[ "$( printf '%s' "$SW" | grep -c '<c n="publish_event"' )" = 2 ] \
    && ok "(I) the facade keeps BOTH real targets (2 edges) — the caller no longer wins its own tie-break" \
    || no "(I) facade.py::Facade::publish_event has $( printf '%s' "$SW" | grep -c '<c n="publish_event"' ) publish_event edges, want 2: $SW"
printf '%s' "$SW" | grep -q 'amb="1"' && ok "(I) …disclosed as an honest split (amb=\"1\")" \
    || no "(I) the facade split is not marked amb=\"1\": $( printf '%s' "$SW" | head -1 )"
printf '%s' "$SW" | grep -q 'lpin=' && no "(I) the facade carries lpin= — a two-way tie was pinned: $( printf '%s' "$SW" | head -1 )" \
    || ok "(I) …and no lpin= (a tie is left a tie)"
printf '%s' "$SW" | grep -q 'prov="split"' && ok "(I) …and the edges carry prov=\"split\"" \
    || no "(I) the split edges lack prov=\"split\": $SW"
# the residual: caller alone in the same-file tier ⇒ still nothing, by design
RESD="$TMP/selfwin_resid"; mkdir -p "$RESD"
cat > "$RESD/a.py" <<'PYEOF'
class Alpha:
    def ping(self, other):
        return other.ping(1)
PYEOF
cat > "$RESD/b.py" <<'PYEOF'
class Beta:
    def ping(self, n):
        return n
PYEOF
RESH="$( "$BIN" "$RESD" --no-cache 2>/dev/null | grep -o '<!-- files=[^>]*-->' | head -1 )"
printf '%s' "$RESH" | grep -q ' edges=0 ' \
    && ok "(I) stated floor holds: a caller alone in the SAME-FILE tier still yields no edge (tier 1 is untouched)" \
    || no "(I) the tier-1 residual moved — update this arm AND src/graph.h's stated floor: $RESH"

# ── (H) determinism + well-formedness ─────────────────────────────────────────────────────────────
"$BIN" "$CORPUS" --no-cache >"$TMP/map2.xml" 2>/dev/null
cmp -s "$TMP/map.xml" "$TMP/map2.xml" && ok "(H) two runs byte-identical" || no "(H) the map is not deterministic"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/map.xml" 2>/dev/null && ok "(H) well-formed XML" || no "(H) xmllint rejects the map"
fi

[ "$fail" = 0 ] && { echo "lpincheck: OK"; exit 0; }
echo "lpincheck: FAILURES ABOVE"; exit 1

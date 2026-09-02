#!/usr/bin/env bash
# fieldusescheck.sh — the MEMBER-VARIABLE (t="field") gate: field symbols + `--uses=Owner.field` per-site
# resolution (ARISE bibliography RANK-A card A3 / CodexGraph's FIELD schema element).
#
#   test/fieldusescheck.sh                        # uses build/ripwire on test/fieldusesfix
#   RIPWIRE_BIN=asan/ripwire test/fieldusescheck.sh
#
# WHY A HAND-DERIVED GOLDEN. A per-site owner resolution looks plausible whether or not it is right — a
# name-matched union of every `count` in the tree and a resolved answer both print rows with roles and
# lines. Every expected set below is derived BY HAND from the fixture (test/fieldusesfix; line numbers are
# load-bearing there), so a wrong pin, a leaked sibling-owner site, or a claimed write that is really an
# alias miss all go RED here.
#
# THE DERIVATION (shapes.cpp; Counter and Gauge BOTH declare `count` and `label`).
#   Counter.count : 11 w (bare `count += step`, inside the owner)  · 12 w (this->count++)
#                   17 w (this->count = count — the bare rhs is the PARAMETER, shadowed, never the field)
#                   22 r (bare, inside the owner)  · 33 w (inner.count — `inner` is a Gauge FIELD of type Counter)
#                   38 w (c.count, c: Counter&)   · 41 r (&c.count — address-of is a READ, the write is NOT claimed)
#                   48 r (a.count, a: const Counter&)  · 54 r amb=2 (x.count, T& x — type unknown, both owners)
#                   NOT 28 (Gauge's own bare count) · NOT 39 (g->count) · NOT 42 (the alias write — THE KNOWN MISS)
#                   NOT 59 (the file-scope global `count` in a free function)
#                   ⇒ count=9, pinned=8, amb_sites=1, owners_of_name=2
#   Gauge.count   : 28 w (bare, inside Gauge) · 39 w (g->count, g: Gauge*) · 48 r (b.count) · 54 r amb=2  ⇒ count=4
#   Gauge.level   : 27 w + 27 r (level = level + amount) · 43 r (g->level)                                ⇒ count=3
#   Counter.step  : 11 r                       Counter.label : 40 w
#   tally.py      : Tally.total 13 w (augmented) · 17 r · 25 r amb=2 — NOT 9 (the defining assignment is the DEF, not a use)
#                   Meter.total 25 w · 25 r amb=2 (other.total — an untyped receiver is a candidate site of BOTH owners)
#                   Tally.hits 14 r (receiver of a method call) · Tally.limit: a def with zero use-sites
#   shapes.go     : Box.width is NOT served (Go) — the selector must REFUSE naming the language
#
# Arms:
#   (A) symbols     — every instance field is a t="field" row with id=path::Owner::field; a class-static constant
#                     stays t="var"; a static data member and a Go struct field are NOT fields
#   (B) golden      — the exact (role, file:line[, amb]) set for Counter.count / Gauge.count / Gauge.level /
#                     Counter.step / Counter.label, plus the root pinned=/amb_sites=/owners_of_name= arithmetic
#   (C) known miss  — the alias write (line 42) is ABSENT from BOTH owners' answers (disclosed, never widened)
#   (D) refusal     — a bare field name shared by two owners refuses (exit 1) listing the Owner.field spellings;
#                     a bare name with ONE owner still answers; an unserved language refuses naming the language;
#                     an unknown owner refuses
#   (E) spellings   — Owner::field and the canonical id give the same rows as Owner.field
#   (F) python      — the self.x / annotated-attribute contract above
#   (G) nonlocal    — --nonlocal-state charges the GLOBAL `count` only to the free function that touches it,
#                     never to a method touching the same-named FIELD (precision)
#   (H) additive    — the flagless map carries the field rows with NO <c> edges; determinism, warm==cold, xmllint
#   (I) legend      — the member-form legend defines every attribute it emits and states the alias limit
#
# Exits non-zero on any failure. Does NOT edit test/regression.sh (listed there by hand, same commit).

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fieldusesfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/fieldusesfix dir — fixture missing"; exit 2; }
echo "fieldusescheck: BIN=$BIN  FIX=$FIX"

# one "role basename:line[ amb=K]" line per <u> row, sorted — paths reduced to basenames so the
# assertions hold wherever the checkout lives.
rows(){ "$BIN" "$FIX" --uses="$1" --no-cache 2>/dev/null | grep -o '<u [^>]*/>' \
        | sed -E 's/.*role="([a-z]*)" p="([^"]*\/)?([^"/]*)"( in_id="[^"]*")?( amb="([0-9]+)")?.*/\1 \3 \6/; s/ +$//; s/ ([0-9]+)$/ amb=\1/' | sort; }
attr(){ printf '%s' "$2" | grep -o "<uses [^>]*>" | grep -o " $1=\"[^\"]*\"" | head -1 | sed -E 's/.*="([^"]*)"/\1/'; }
expect_rows(){  # $1 selector, $2 label, $3.. expected lines
    sel="$1"; label="$2"; shift 2
    want="$( printf '%s\n' "$@" | sort )"; got="$( rows "$sel" )"
    if [ "$got" = "$want" ]; then ok "$label: --uses=$sel rows exact"; else no "$label: --uses=$sel row set mismatch"; printf '    want:\n%s\n    got:\n%s\n' "$want" "$got"; fi
}

MAP="$( "$BIN" "$FIX" --no-cache 2>/dev/null )"

# ── (A) symbols ──────────────────────────────────────────────────────────────────────────────────────────
for id in Counter::count Counter::step Counter::label Gauge::count Gauge::level Gauge::label Gauge::inner \
          Tally::limit Tally::total Tally::hits Meter::total; do
    n="${id##*::}"
    printf '%s' "$MAP" | grep -q "<s t=\"field\"[^>]* n=\"$n\" id=\"[^\"]*::$id\"" \
        && ok "(A) field symbol $id (t=\"field\", owner-qualified id)" || no "(A) field symbol $id missing or not t=\"field\""
done
printf '%s' "$MAP" | grep -q '<s t="var"[^>]* n="kMax"'   && ok '(A) class-static constant kMax stays t="var"' || no '(A) kMax is no longer t="var"'
printf '%s' "$MAP" | grep -q '<s t="field"[^>]* n="live"' && no '(A) static data member live wrongly a field' || ok '(A) static data member live is not a field (disclosed)'
printf '%s' "$MAP" | grep -q '<s t="[a-z]*"[^>]* n="width"' && no '(A) Go struct field `width` became a symbol (Go is not served)' || ok '(A) Go struct field `width` is not a symbol (unserved language)'
# one symbol per Python field even though Tally.total/Meter.total are assigned in several methods
NTOTAL="$( printf '%s' "$MAP" | grep -o '<s t="field"[^>]* n="total"' | wc -l | tr -d ' ' )"
[ "$NTOTAL" = "2" ] && ok "(A) Python self.total: exactly one field per owner (2 rows)" || no "(A) Python self.total field rows = $NTOTAL (want 2: Tally, Meter)"

# ── (B) golden ───────────────────────────────────────────────────────────────────────────────────────────
expect_rows Counter.count "(B) Counter.count" \
    "write shapes.cpp:11" "write shapes.cpp:12" "write shapes.cpp:17" "read shapes.cpp:22" "write shapes.cpp:33" \
    "write shapes.cpp:38" "read shapes.cpp:41" "read shapes.cpp:48" "read shapes.cpp:54 amb=2"
expect_rows Gauge.count   "(B) Gauge.count"   "write shapes.cpp:28" "write shapes.cpp:39" "read shapes.cpp:48" "read shapes.cpp:54 amb=2"
expect_rows Gauge.level   "(B) Gauge.level"   "write shapes.cpp:27" "read shapes.cpp:27" "read shapes.cpp:43"
expect_rows Counter.step  "(B) Counter.step"  "read shapes.cpp:11"
expect_rows Counter.label "(B) Counter.label" "write shapes.cpp:40"
CC="$( "$BIN" "$FIX" --uses=Counter.count --no-cache 2>/dev/null )"
[ "$( attr count "$CC" )" = "9" ]          && ok '(B) Counter.count count="9"'          || no "(B) Counter.count count=$( attr count "$CC" ) (want 9)"
[ "$( attr pinned "$CC" )" = "8" ]         && ok '(B) Counter.count pinned="8"'         || no "(B) Counter.count pinned=$( attr pinned "$CC" ) (want 8)"
[ "$( attr amb_sites "$CC" )" = "1" ]      && ok '(B) Counter.count amb_sites="1"'      || no "(B) Counter.count amb_sites=$( attr amb_sites "$CC" ) (want 1)"
[ "$( attr owners_of_name "$CC" )" = "2" ] && ok '(B) Counter.count owners_of_name="2"' || no "(B) Counter.count owners_of_name=$( attr owners_of_name "$CC" ) (want 2)"
[ "$( attr defs "$CC" )" = "1" ]           && ok '(B) Counter.count defs="1"'           || no "(B) Counter.count defs=$( attr defs "$CC" ) (want 1)"
printf '%s' "$CC" | grep -q 'counts_floor="1"' && ok '(B) counts_floor="1" on the member form' || no '(B) member form lacks counts_floor="1"'

# ── (C) the known miss ───────────────────────────────────────────────────────────────────────────────────
rows Counter.count | grep -q 'shapes.cpp:42' && no "(C) alias write (line 42) CLAIMED for Counter.count — no alias analysis exists, this is a false row" \
                                            || ok "(C) alias write (line 42) is a disclosed miss on Counter.count"
rows Gauge.count   | grep -q 'shapes.cpp:42' && no "(C) alias write (line 42) CLAIMED for Gauge.count" || ok "(C) alias write (line 42) absent from Gauge.count too"
rows Counter.count | grep -q 'shapes.cpp:59' && no "(C) the free-function global write (line 59) leaked into Counter.count" || ok "(C) global count write (line 59) is not a field use-site"

# ── (D) refusals ─────────────────────────────────────────────────────────────────────────────────────────
"$BIN" "$FIX" --uses=count --no-cache >"$TMP/bare.out" 2>"$TMP/bare.err"; rc=$?
[ "$rc" = "1" ] && ok "(D) bare --uses=count (two owners) refuses, exit 1" || no "(D) bare --uses=count exit $rc (want 1)"
[ ! -s "$TMP/bare.out" ] && ok "(D) the refusal writes nothing to stdout" || no "(D) refusal wrote stdout bytes"
grep -q 'Counter.count' "$TMP/bare.err" && grep -q 'Gauge.count' "$TMP/bare.err" \
    && ok "(D) refusal lists the Owner.field spellings (Counter.count, Gauge.count)" || { no "(D) refusal does not list both spellings"; cat "$TMP/bare.err"; }
LV="$( "$BIN" "$FIX" --uses=level --no-cache 2>/dev/null )"; rc=$?
[ "$rc" = "0" ] && [ "$( attr count "$LV" )" = "3" ] && ok "(D) bare --uses=level (ONE owner) answers with the member form (count=3)" \
    || no "(D) bare --uses=level rc=$rc count=$( attr count "$LV" ) (want 0 / 3)"
"$BIN" "$FIX" --uses=Box.width --no-cache >"$TMP/go.out" 2>"$TMP/go.err"; rc=$?
[ "$rc" = "1" ] && grep -q 'lang=go' "$TMP/go.err" && ok "(D) --uses=Box.width refuses naming the language (lang=go)" \
    || { no "(D) --uses=Box.width rc=$rc, stderr does not name lang=go"; cat "$TMP/go.err"; }
"$BIN" "$FIX" --uses=Nope.count --no-cache >/dev/null 2>"$TMP/nope.err"; rc=$?
[ "$rc" = "1" ] && ok "(D) --uses=Nope.count (unknown owner) refuses, exit 1" || no "(D) --uses=Nope.count exit $rc (want 1)"

# ── (E) spellings agree ──────────────────────────────────────────────────────────────────────────────────
[ "$( rows Counter::count )" = "$( rows Counter.count )" ] && ok "(E) Counter::count rows == Counter.count rows" || no "(E) Counter::count and Counter.count disagree"
CANON="$( printf '%s' "$MAP" | grep -o '<s t="field"[^>]* n="count" id="[^"]*::Counter::count"' | sed -E 's/.*id="([^"]*)".*/\1/' )"
[ -n "$CANON" ] && [ "$( rows "$CANON" )" = "$( rows Counter.count )" ] && ok "(E) canonical id rows == Counter.count rows" || no "(E) canonical id '$CANON' disagrees with Counter.count"

# ── (F) python ───────────────────────────────────────────────────────────────────────────────────────────
expect_rows Tally.total "(F) Tally.total" "write tally.py:13" "read tally.py:17" "read tally.py:25 amb=2"
expect_rows Meter.total "(F) Meter.total" "write tally.py:25" "read tally.py:25 amb=2"
expect_rows Tally.hits  "(F) Tally.hits"  "read tally.py:14"
rows Tally.total | grep -q 'tally.py:9' && no "(F) the defining assignment (line 9) counted as a use of Tally.total" || ok "(F) defining assignment (line 9) is a def, not a use"
LIM="$( "$BIN" "$FIX" --uses=Tally.limit --no-cache 2>/dev/null )"; rc=$?
[ "$rc" = "0" ] && [ "$( attr defs "$LIM" )" = "1" ] && [ "$( attr count "$LIM" )" = "0" ] \
    && ok "(F) Tally.limit: a def with zero use-sites answers count=\"0\" (exit 0)" || no "(F) Tally.limit rc=$rc defs=$( attr defs "$LIM" ) count=$( attr count "$LIM" )"

# ── (G) nonlocal-state precision ─────────────────────────────────────────────────────────────────────────
NLS="$( "$BIN" "$FIX" --nonlocal-state --no-cache 2>/dev/null )"
NROWS="$( printf '%s' "$NLS" | grep -o '<fn [^>]*n="[A-Za-z_]*"' | wc -l | tr -d ' ' )"
printf '%s' "$NLS" | grep -q '<fn [^>]*n="reset_global"' && ok "(G) the free function writing the GLOBAL count is a nonlocal-state row" || no "(G) reset_global row missing"
for fn in bump set peek fill reset total relay; do
    printf '%s' "$NLS" | grep -q "<fn [^>]*n=\"$fn\"" && no "(G) $fn touches only the FIELD count/level, yet is charged to the global cell" || ok "(G) $fn (field-only) is not charged to the global"
done
[ "$NROWS" = "1" ] && ok "(G) exactly one nonlocal-state row (the global's one writer)" || no "(G) nonlocal-state rows = $NROWS (want 1)"
printf '%s' "$NLS" | grep -q 'field' && ok "(G) the nonlocal-state legend discloses the instance-field exclusion" || no "(G) nonlocal-state legend does not mention fields"

# ── (H) additive / determinism / well-formedness ─────────────────────────────────────────────────────────
printf '%s' "$MAP" | grep -q '<s t="field"[^>]*>[^<]*<c ' && no "(H) a field row carries a <c> edge (fields never enter the call graph)" || ok "(H) field rows carry no <c> edges"
"$BIN" "$FIX" --uses=Counter.count --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$FIX" --uses=Counter.count --no-cache >"$TMP/b" 2>/dev/null
cmp -s "$TMP/a" "$TMP/b" && ok "(H) determinism: two --no-cache runs byte-identical" || no "(H) --uses=Counter.count is not deterministic"
"$BIN" "$FIX" --uses=Counter.count --cache="$TMP/c.bin" >/dev/null 2>&1
"$BIN" "$FIX" --uses=Counter.count --cache="$TMP/c.bin" >"$TMP/w" 2>/dev/null
cmp -s "$TMP/a" "$TMP/w" && ok "(H) warm cache == cold (field refs round-trip the cache)" || no "(H) warm --uses=Counter.count differs from cold"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/a" 2>/dev/null && ok "(H) --uses=Counter.count is well-formed XML" || no "(H) --uses=Counter.count is not well-formed XML"
    printf '%s' "$MAP" | xmllint --noout - 2>/dev/null && ok "(H) the map with field rows is well-formed XML" || no "(H) the map is not well-formed XML"
fi

# ── (I) legend ───────────────────────────────────────────────────────────────────────────────────────────
LEG="$( printf '%s' "$CC" | sed 's/-->.*//' )"
for a in amb pinned amb_sites owners_of_name; do
    printf '%s' "$LEG" | grep -q "$a=" && ok "(I) legend defines $a=" || no "(I) legend does not define $a="
done
printf '%s' "$LEG" | grep -qi 'alias' && ok "(I) legend states the no-alias-analysis limit" || no "(I) legend does not state the alias limit"
printf '%s' "$LEG" | grep -qi 'macro' && ok "(I) legend states the macro limit" || no "(I) legend does not state the macro limit"

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; fi
echo "SOME CHECKS FAILED"; exit 1

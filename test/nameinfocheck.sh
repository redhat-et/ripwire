#!/usr/bin/env bash
# nameinfocheck.sh — naming-uninformative (the corpus-IDF name-informativeness lens, src/naminglens.h
# §9.0a candidate 1) fires ONLY when a name is built ENTIRELY from corpus-ubiquitous subtokens AND its
# body clears the size gate — never on a rare/distinctive name, and never on a short body, no matter how
# ubiquitous the name. This is the successor to the withdrawn naming-body-mismatch rule: unlike that
# rule, this one's direction is defensible (fires ONLY at the low end of informativeness; a high-idf name
# is never penalised — see the WITHDRAWN note atop src/naminglens.h).
#
# The corpus is HAND-CONTROLLED so document frequencies (and therefore idf) are exactly derivable:
#   * "process" and "data" are made ubiquitous by ten one-line filler functions that each spell both —
#     df(process) = df(data) = 11 of 14 eligible symbols (the fillers plus one long-body test function
#     each), comfortably past the n >= S/2 "majority of the corpus" bar (idf = ln2 at exactly S/2).
#   * "zylofoo" and "quixotrope" each appear in exactly ONE symbol — idf close to its ceiling.
# Four probes, same 20+-line body shape except where the body-size gate itself is under test:
#   informLong        name="process"            (bare, wholly ubiquitous)      long body  -> FIRES
#   rareLong          name="zylofoo"             (bare, wholly rare)            long body  -> silent (control: identical shape to informLong, opposite corpus frequency)
#   mixedLong         name="processQuixotrope"   (one ubiquitous + one rare)    long body  -> silent ("entirely" ubiquitous is required, not just partly — MAX, not MIN/mean)
#   informShort       name="data"                (bare, wholly ubiquitous)      3-line body -> silent (body-size gate; the design doc's own "a 3-line `fill` is fine" example)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIXTURE="$TMP/fixture"
mkdir -p "$FIXTURE"

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

# ── the hand-controlled corpus (test/nameinfocheck.sh) ──────────────────────────────────────────────
cat >"$FIXTURE/nameinfo.cpp" <<'CPP'
// hand-controlled corpus for the naming-uninformative gate (test/nameinfocheck.sh) — every filler
// spells BOTH "process" and "data" so those two subtokens are the corpus MAJORITY; "zylofoo" and
// "quixotrope" each appear exactly once so they sit near the idf ceiling. One-line bodies throughout
// the fillers so none of them can clear the body-size gate regardless of how common their names are.
int processAlphaData( int amount )   { return amount + 1; }
int processBetaData( int amount )    { return amount + 2; }
int processGammaData( int amount )   { return amount + 3; }
int processDeltaData( int amount )   { return amount + 4; }
int processEpsilonData( int amount ) { return amount + 5; }
int processZetaData( int amount )    { return amount + 6; }
int processEtaData( int amount )     { return amount + 7; }
int processThetaData( int amount )   { return amount + 8; }
int processIotaData( int amount )    { return amount + 9; }
int processKappaData( int amount )   { return amount + 10; }

// informLong — name is the single bare token "process": WHOLLY corpus-ubiquitous, and the body clears
// the size gate (well over 20 lines). Must FIRE naming-uninformative.
int process( int amount )
{
    int total = amount;
    total += 1;
    total += 2;
    total += 3;
    total += 4;
    total += 5;
    total += 6;
    total += 7;
    total += 8;
    total += 9;
    total += 10;
    total += 11;
    total += 12;
    total += 13;
    total += 14;
    total += 15;
    total += 16;
    total += 17;
    total += 18;
    total += 19;
    total += 20;
    total += 21;
    total += 22;
    return total;
}

// rareLong — IDENTICAL body shape to process() above, but the name is the single bare token "zylofoo",
// which appears NOWHERE else in this corpus (idf near its ceiling). Must stay silent — the direct
// rare-token-same-shape control the gate exists to prove.
int zylofoo( int amount )
{
    int total = amount;
    total += 1;
    total += 2;
    total += 3;
    total += 4;
    total += 5;
    total += 6;
    total += 7;
    total += 8;
    total += 9;
    total += 10;
    total += 11;
    total += 12;
    total += 13;
    total += 14;
    total += 15;
    total += 16;
    total += 17;
    total += 18;
    total += 19;
    total += 20;
    total += 21;
    total += 22;
    return total;
}

// mixedLong — same long body again, but the name pairs the ubiquitous "process" with the rare
// "Quixotrope". A name is only uninformative when it is built ENTIRELY of common parts (MAX idf over
// its subtokens, not MIN or mean) — one real word is enough to earn the name its silence.
int processQuixotrope( int amount )
{
    int total = amount;
    total += 1;
    total += 2;
    total += 3;
    total += 4;
    total += 5;
    total += 6;
    total += 7;
    total += 8;
    total += 9;
    total += 10;
    total += 11;
    total += 12;
    total += 13;
    total += 14;
    total += 15;
    total += 16;
    total += 17;
    total += 18;
    total += 19;
    total += 20;
    total += 21;
    total += 22;
    return total;
}

// informShort — name is the single bare token "data": WHOLLY corpus-ubiquitous, exactly as
// uninformative as process() above, but the body is only 3 lines (the design doc's own "a 3-line
// `fill` is fine" example). Must stay silent — the body-size half of the gate, isolated from the
// informativeness half.
int data( int amount )
{
    int total = amount;
    total += 1;
    return total;
}
CPP

fail=0
ok(){ printf '  PASS  %s\n' "$1"; }
no(){ printf '  FAIL  %s\n' "$1"; fail=1; }

# ── determinism + non-vacuity ───────────────────────────────────────────────────────────────────────
"$BIN" "$FIXTURE" --lint --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$FIXTURE" --lint --no-cache >"$TMP/b" 2>/dev/null
[ -s "$TMP/a" ] || { no "lint output is empty — nothing was measured"; exit 1; }
if cmp -s "$TMP/a" "$TMP/b"; then ok "naming-uninformative output is deterministic"; else no "naming-uninformative output is not deterministic"; fi

# ── well-formedness + G5: only under --lint ─────────────────────────────────────────────────────────
if xmllint --noout "$TMP/a" 2>/dev/null; then ok "well-formed XML"; else no "not well-formed XML"; fi
"$BIN" "$FIXTURE" --no-cache >"$TMP/flagless" 2>/dev/null
if grep -q "naming-uninformative" "$TMP/flagless"; then no "flagless run mentions naming-uninformative (G5: the lens must be additive)"; else ok "flagless run is untouched by naming-uninformative"; fi

# ── the four probes ─────────────────────────────────────────────────────────────────────────────────
python3 - "$TMP/a" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()   # parsing IS the well-formedness assertion
findings = [ n for n in root.findall("f") if n.get("rule") == "naming-uninformative" ]
fired = { n.get("in") for n in findings }

expect_fired  = { "process" }
expect_silent = { "zylofoo", "processQuixotrope", "data",
                   "processAlphaData", "processBetaData", "processGammaData", "processDeltaData",
                   "processEpsilonData", "processZetaData", "processEtaData", "processThetaData",
                   "processIotaData", "processKappaData" }

missing = expect_fired - fired
if missing:
    raise SystemExit(f"FAIL naming-uninformative did not fire on the ubiquitous long-body name(s): {missing}")

falsePos = fired & expect_silent
if falsePos:
    raise SystemExit(f"FAIL naming-uninformative fired on a name that must stay silent: {falsePos}")

extra = fired - expect_fired
if extra:
    raise SystemExit(f"FAIL naming-uninformative fired on unexpected symbol(s) not modelled by this gate: {extra}")

# the rule row itself must exist and its count must equal the emitted rows (no silent floor here)
rules = { n.get("name"): n for n in root.findall("rule") }
if "naming-uninformative" not in rules:
    raise SystemExit("FAIL no <rule name=\"naming-uninformative\"> tally row emitted")
stated = int(rules["naming-uninformative"].get("count"))
if stated != len(findings):
    raise SystemExit(f"FAIL <rule count=\"{stated}\"> disagrees with {len(findings)} emitted rows")
if rules["naming-uninformative"].get("capped") is not None:
    raise SystemExit("FAIL naming-uninformative capped= on a fixture nowhere near the per-rule budget")

print(f"PASS naming-uninformative fired exactly on {sorted(fired)}")
PY
[ $? -eq 0 ] && ok "corpus-IDF probes: ubiquitous+long fires, rare+long silent, mixed+long silent, ubiquitous+short silent" \
             || no "corpus-IDF probes (see FAIL line above)"

exit "$fail"

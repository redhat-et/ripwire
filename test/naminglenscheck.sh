#!/usr/bin/env bash
# naminglenscheck.sh — the identifier-naming lens (naming-* built-in lint rules) fires on planted
# violations, stays SILENT on every near-miss negative, and only ever fires when its needed fact is
# KNOWN (unknown return type ⇒ naming-predicate / naming-setter say nothing). Deterministic output,
# well-formed XML, and G5: the lens exists only under --lint — a flagless run never spells "naming-".

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIXTURE="$TMP/fixture"
mkdir -p "$FIXTURE"

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

# ── fixture: every planted violation is hand-derivable, every near-miss proves a silence ──────────
cat >"$FIXTURE/naming.cpp" <<'CPP'
// planted violations + near-miss negatives for the naming-* lens (test/naminglenscheck.sh)

int computeTotalWeightedAverageScoreValue( int amount )   // naming-wordy: 6 split tokens
{
    return amount + 100;
}

int handle__relay( int amount )                           // naming-underscore: internal consecutive __
{
    return amount + 200;
}

int _Reserved( int amount )                               // naming-underscore: C++ reserved _Capital form
{
    return amount + 300;
}

int fetch_remoteCount( int amount )                       // naming-case: snake_case and camelCase mixed in one name
{
    return amount + 400;
}

bool isValidState( int amount )                           // near-miss: predicate returning bool -> silent
{
    return amount > 0;
}

int isBrokenState( int amount )                           // naming-predicate: is-prefix, known non-bool return
{
    return amount + 500;
}

auto isMysteryState( int amount )                         // near-miss: auto return type is UNKNOWN -> silent
{
    return amount;
}

void setSpeedValue( int amount )                          // near-miss: setter returning void -> silent
{
    static int sink = 0;
    sink = amount;
}

int setLimitValue( int amount )                           // naming-setter: set-prefix, known non-void return
{
    return amount + 600;
}

int receiveBuffer( int amount )                           // naming-confusable pair: edit distance 1 vs receiveBuffed
{
    for( int i = 0; i < 3; ++i )                          // near-miss: idiomatic loop i is a local, not indexed -> silent
    {
        amount += i;
    }
    return amount;
}

int receiveBuffed( int amount )
{
    return amount + 700;
}

int q( int amount )                                       // naming-short: single-letter function name
{
    return amount + 800;
}

int stageAlpha1( int amount )                             // naming-series: stageAlpha1/stageAlpha2 in one scope
{
    return amount + 900;
}

int stageAlpha2( int amount )                             // naming-series sibling
{
    return amount + 901;
}

int orchestrateMigrationWave( int amount )                // naming-body-mismatch: >=10-line body, zero shared vocabulary
{
    int total = amount;
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
    return total;
}

int accumulateStreamTotals( int amount )                  // near-miss: long body but "stream" is shared vocabulary -> silent
{
    int streamTotal = amount;
    streamTotal += 21;
    streamTotal += 22;
    streamTotal += 23;
    streamTotal += 24;
    streamTotal += 25;
    streamTotal += 26;
    streamTotal += 27;
    streamTotal += 28;
    streamTotal += 29;
    streamTotal += 30;
    return streamTotal;
}
CPP

cat >"$FIXTURE/naming.py" <<'PY'
"""planted violations + near-miss negatives for the naming-* lens (test/naminglenscheck.sh)"""

M = 3

module_capacity = 7

alpha1 = 1
alpha2 = 2

def is_missing_marker(records) -> int:
    return len(records)

def is_present_marker(records) -> bool:
    return bool(records)

def is_untyped_marker(records):
    return records

def set_capacity_level(level) -> int:
    return level

def set_velocity_level(level):
    return level

def totally__spaced(level):
    return level

def weave_cadence_report(rows):
    left = 0
    left += 31
    left += 32
    left += 33
    left += 34
    left += 35
    left += 36
    left += 37
    left += 38
    left += 39
    left += 40
    return left + len(rows)

class Snapshot:
    def __init__(self, level):
        self.level = level
PY

fail=0
ok(){ printf '  PASS  %s\n' "$1"; }
no(){ printf '  FAIL  %s\n' "$1"; fail=1; }

# ── determinism: two cold runs must be byte-identical, and non-empty (non-vacuity) ────────────────
"$BIN" "$FIXTURE" --lint --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$FIXTURE" --lint --no-cache >"$TMP/b" 2>/dev/null
[ -s "$TMP/a" ] || { no "lint output is empty — nothing was measured"; exit 1; }
if cmp -s "$TMP/a" "$TMP/b"; then ok "naming lens output is deterministic"; else no "naming lens output is not deterministic"; fi

# ── G5: the lens lives only under --lint — the flagless map never spells a naming- rule ───────────
"$BIN" "$FIXTURE" --no-cache >"$TMP/flagless" 2>/dev/null
if grep -q "naming-" "$TMP/flagless"; then no "flagless run mentions naming- (G5: the lens must be additive)"; else ok "flagless run is untouched by the naming lens"; fi

# ── the findings themselves: exact owners per rule, exact counts, and every near-miss silent ──────
python3 - "$TMP/a" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()          # parsing IS the well-formedness assertion

rules = { node.get("name"): node for node in root.findall("rule") }
findings = [ node for node in root.findall("f") if node.get("rule", "").startswith("naming-") ]

# presence guard: assert the rows we are about to count actually exist (a gate must be able to
# observe what it asserts — an absent rule row would make every count-0 check pass for the wrong reason)
expected_rules = [ "naming-short", "naming-wordy", "naming-series", "naming-underscore", "naming-case",
                   "naming-predicate", "naming-setter", "naming-confusable", "naming-body-mismatch" ]
missing = [ r for r in expected_rules if r not in rules ]
if missing:
    raise SystemExit(f"FAIL missing <rule> tally rows for {missing}")

expected_owners = {
    "naming-short":         { "q", "M" },
    "naming-wordy":         { "computeTotalWeightedAverageScoreValue" },
    "naming-series":        { "stageAlpha1", "stageAlpha2", "alpha1", "alpha2" },
    "naming-underscore":    { "handle__relay", "_Reserved", "totally__spaced" },
    "naming-case":          { "fetch_remoteCount" },
    "naming-predicate":     { "isBrokenState", "is_missing_marker" },
    "naming-setter":        { "setLimitValue", "set_capacity_level" },
    "naming-confusable":    { "receiveBuffed" },
    "naming-body-mismatch": { "orchestrateMigrationWave", "weave_cadence_report" },
}
for rule, owners in expected_owners.items():
    got = { node.get("in") for node in findings if node.get("rule") == rule }
    if got != owners:
        detail = [ (node.get("in"), node.get("p"), node.text) for node in findings if node.get("rule") == rule ]
        raise SystemExit(f"FAIL {rule}: expected owners {sorted(owners)}, found {detail}")
    stated = int(rules[rule].get("count"))
    actual = sum(1 for node in findings if node.get("rule") == rule)
    if stated != actual:
        raise SystemExit(f"FAIL {rule}: <rule count=\"{stated}\"> disagrees with {actual} emitted rows")
    if rules[rule].get("capped") is not None:
        raise SystemExit(f"FAIL {rule}: capped= on a fixture nowhere near the per-rule budget")

# near-miss negatives: each proves a specific silence (bool-returning predicate, void setter, unknown
# return type, descriptive names, shared body vocabulary, dunder underscores, un-indexed loop local)
never_flagged = [ "isValidState", "isMysteryState", "setSpeedValue", "is_present_marker", "is_untyped_marker",
                  "set_velocity_level", "module_capacity", "accumulateStreamTotals", "__init__", "Snapshot" ]
for name in never_flagged:
    hits = [ (node.get("rule"), node.get("p")) for node in findings if node.get("in") == name ]
    if hits:
        raise SystemExit(f"FAIL near-miss {name} was flagged: {hits}")

# the weakest-confidence rule says so on the row itself
for node in findings:
    if node.get("rule") == "naming-body-mismatch" and "weakest-confidence" not in (node.text or ""):
        raise SystemExit(f"FAIL naming-body-mismatch row is not labeled weakest-confidence: {node.text}")

print("PASS planted violations flagged, every near-miss silent, tallies truthful")
PY
[ $? -eq 0 ] && ok "owners + counts + near-miss silences" || no "owners/counts/near-miss assertions (see FAIL line above)"

exit "$fail"

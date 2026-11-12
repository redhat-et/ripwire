#!/usr/bin/env bash
# qdmonstercheck.sh — QD-MONSTER-GROWTH gate: a complexity row on a function over kMonsterMul × kCcxBar (ccx 75) that grew by
# kMonsterGrowthCcx (10) or more in one change is MAJOR whatever the percentage, and carries monster="1" (quality.h isMonsterGrowth).
#
# Why: the 25 % growth tier made every tangle added to a giant function minor forever (buildGraph 1950 -> 1968 = +0.9 %).
# Measured on 47 first-parent merges (reports/qd-ge-card-verify-1112.md § E3): Δccx >= 10 is 17 % of merges, 6 of 7 sampled tangle.
#
#   (s1) SEEDED FLAT: 20 sequential lines with no branch added to a ccx >= 75 fixture function: no complexity row (0 ccx added).
#   (s2) SEEDED TANGLE: one 3-deep nested loop block (with an inner if, +10 ccx) added to the same function: major, monster="1".
#   (s3) SEEDED SMALL: +3 ccx on the same function stays sev="minor", no monster= (under kMonsterGrowthCcx).
#   (p*) POSITIVE, real merges (minor before the card): buildGraph 1950->1968, applyMentionBoost 77->92, lexicalScoresTiered 421->443.
#   (n*) NEGATIVE, real merges (flat growth under 10 ccx, stay minor): runMaintenanceViews 231->236, serialize 278->282,
#        runArchViews 127->131.
#   (d)  determinism: (s2) twice is byte-identical.
#   PREMISE: every arm counts the complexity rows with was >= 75 it saw on its symbol and FAILS on 0 (a vacuous arm is a FAIL).
#   KNOWN FALSE ROW, not fixed here: 0852bc0f6 parseArgs 201->213 (two flat `else if( --flag= )` arms) turns major.
#
# The real-merge arms need this repository's history (one 20-60 s ingest per merge, run one at a time). Without the commits (a
# shallow clone) they SKIP, said so on their own line; the seeded arms always run. QDMONSTER_REPO names another clone to replay on.
# Usage: test/qdmonstercheck.sh [BIN]   (default build/ripwire). Red before the card: (s2) and (p1)-(p3).
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
REPO="${QDMONSTER_REPO:-$ROOT}"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP/cache"; mkdir -p "$TMPDIR"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "qdmonstercheck: BIN=$BIN"
G=( git -c user.name=t -c user.email=t@t -c commit.gpgsign=false )

# row FILE SYM — the complexity row for SYM (exact sym=), or empty
row(){ grep -oE "<r kind=\"complexity\" sym=\"$2\"[^>]*>" "$1" | head -1; }
attr(){ printf '%s' "$1" | sed -nE "s/.* $2=\"([^\"]*)\".*/\1/p"; }

# judge LABEL FILE SYM WANT(major|minor|absent) — one arm: the row's severity and monster= mark, with the premise count
judge(){
    local label="$1" f="$2" sym="$3" want="$4" r was now sev mon seen
    r="$( row "$f" "$sym" )"
    was="$( attr "$r" was )"; now="$( attr "$r" now )"; sev="$( attr "$r" sev )"; mon="$( attr "$r" monster )"
    seen=0; [ -n "$was" ] && [ "$was" -ge 75 ] && seen=1
    if [ "$want" = absent ]; then
        if [ -z "$r" ]; then ok "($label) $sym: no complexity row"; else no "($label) $sym: want no complexity row, got $r"; fi
        return
    fi
    if [ "$seen" = 0 ]; then no "($label) PREMISE: saw 0 complexity rows with was>=75 on $sym (row: '${r:-none}')"; return; fi
    if [ "$want" = major ]; then
        if [ -z "$sev" ] && [ "$mon" = 1 ] && printf '%s' "$r" | grep -q 'gating="1"'; then
            ok "($label) $sym $was->$now: major, gating, monster=\"1\" (premise: 1 row with was>=75)"
        else no "($label) $sym $was->$now: want major + gating + monster=\"1\", got $r"; fi
    else
        if [ "$sev" = minor ] && [ -z "$mon" ]; then
            ok "($label) $sym $was->$now: sev=\"minor\", no monster= (premise: 1 row with was>=75)"
        else no "($label) $sym $was->$now: want sev=\"minor\" and no monster=, got $r"; fi
    fi
}

memok(){ command -v memory_pressure >/dev/null 2>&1 || return 0
    local free; free="$( memory_pressure | tail -1 | grep -oE '[0-9]+%' | tr -d % )"; [ -z "$free" ] || [ "$free" -ge 40 ]; }

# ── seeded arms: a Python function at ccx 81 (one loop, 40 ifs at nesting 1) ──────────────────────────────────────────
S="$TMP/seed"; mkdir -p "$S"; "${G[@]}" -C "$S" init -q
body(){   # body EXTRA — the monster function, with EXTRA spliced in before its return
    printf 'def monster(xs):\n    total = 0\n    for x in xs:\n'
    local k; for k in $( seq 1 40 ); do printf '        if x == %d:\n            total += %d\n' "$k" "$k"; done
    printf '%s' "$1"
    printf '    return total\n'
}
flat=""; for k in $( seq 1 20 ); do flat="$flat    total = total + $k\n"; done
flat="$( printf "$flat" )
"
nested='    for a in xs:
        for b in xs:
            for c in xs:
                if a == b:
                    total += c
'
small='    if total > 1:
        total -= 1
    if total > 2:
        total -= 2
    if total > 3:
        total -= 3
'
body "" > "$S/m.py";               "${G[@]}" -C "$S" add -A; "${G[@]}" -C "$S" commit -qm base
body "$flat" > "$S/m.py";          "${G[@]}" -C "$S" add -A; "${G[@]}" -C "$S" commit -qm flat
body "$flat$nested" > "$S/m.py";   "${G[@]}" -C "$S" add -A; "${G[@]}" -C "$S" commit -qm nested
body "$flat$nested$small" > "$S/m.py"; "${G[@]}" -C "$S" add -A; "${G[@]}" -C "$S" commit -qm small
qd(){ ( cd "$1" && "$BIN" . --quality-delta="$2" --quality-kinds=complexity,nesting ) > "$3" 2> "$3.err"; }
qd "$S" HEAD~3..HEAD~2 "$TMP/s1.xml"
qd "$S" HEAD~2..HEAD~1 "$TMP/s2.xml"
qd "$S" HEAD~1..HEAD   "$TMP/s3.xml"
# (s1) the base row must exist for the premise: read it off the flat commit's own baseline (was= of s2 is the flat commit's ccx)
r2="$( row "$TMP/s2.xml" 'monster' )"; w2="$( attr "$r2" was )"
if [ -n "$w2" ] && [ "$w2" -ge 75 ]; then
    judge s1 "$TMP/s1.xml" 'monster' absent
    ok "(s1) PREMISE: the flat commit's monster is ccx $w2 (>= 75), so (s1)'s silence is about the flat lines, not a small function"
else no "(s1) PREMISE: the fixture function is not ccx >= 75 (row: '${r2:-none}'); stderr: $( head -c 300 "$TMP/s2.xml.err" )"; fi
judge s2 "$TMP/s2.xml" 'monster' major
judge s3 "$TMP/s3.xml" 'monster' minor
grep -q 'monster="1" marks a complexity row\|r monster=1:' "$TMP/s2.xml" && ok "(s2) the legend defines monster=" || no "(s2) no monster= reading in the legend"
qd "$S" HEAD~2..HEAD~1 "$TMP/s2b.xml"
cmp -s "$TMP/s2.xml" "$TMP/s2b.xml" && ok "(d) the seeded tangle run twice is byte-identical" || no "(d) the seeded tangle run is not deterministic"

# ── real-merge replays: one process at a time, memory guarded ─────────────────────────────────────────────────────────
ARMS=(
  "p1 2f1f0425c src/graph\\.h::rw::buildGraph major"
  "p2 87268ce34 src/mention\\.h::rw::applyMentionBoost major"
  "p3 f6a271672 src/lexical\\.h::rw::lexicalScoresTiered major"
  "n1 953818d6f runMaintenanceViews minor"
  "n2 cd11226a6 src/serialize\\.h::rw::serialize minor"
  "n3 92bc055ee runArchViews minor"
)
for a in "${ARMS[@]}"; do
    set -- $a; label="$1"; sha="$2"; sym="$3"; want="$4"
    if ! git -C "$REPO" cat-file -e "$sha^1^{commit}" 2>/dev/null || ! git -C "$REPO" cat-file -e "$sha^{commit}" 2>/dev/null; then
        echo "  SKIP  ($label) $sha or its first parent is not in $REPO (shallow clone?) — set QDMONSTER_REPO to a full clone"
        continue
    fi
    if ! memok; then echo "  SKIP  ($label) memory_pressure free below 40 %: not starting a whole-repo replay"; continue; fi
    qd "$REPO" "$sha^1..$sha" "$TMP/$label.xml"
    judge "$label" "$TMP/$label.xml" "$sym" "$want"
done

[ "$fail" = 0 ] && echo "qdmonstercheck: PASS" || echo "qdmonstercheck: FAIL"
exit "$fail"

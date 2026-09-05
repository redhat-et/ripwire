#!/usr/bin/env bash
# packcallersharecheck.sh — corroboration-weighted caller ranking in --pack-task's <callers> section
# (PLAN_HARVEST_REPORTS_2026-08-20/graphrag-recon.md idea #1, adapted from nano-graphrag's `relation_counts`).
#
# THE FEATURE: a d1 caller/callee reached from SEVERAL of the bundle's top-K anchor symbols now sorts ahead of
# one reached from only a single anchor — a pure, deterministic re-sort of the SAME edges the callers section
# already collected (no new graph walk, no pooling, no change to --for's own ranking formula). Each row
# discloses the count as shared="N" (like amp=/in=, a count, never a judgment), omitted at the uncorroborated
# default of 1 so a bundle with only one anchor costs not one extra byte. Ties keep the pre-existing (site)
# order — the minimal, stable re-sort the brief asked for.
#
# Usage:  RIPWIRE_BIN=build/ripwire test/packcallersharecheck.sh   |   RIPWIRE_BIN=asan/ripwire test/…
#         RIPWIRE_BIN=build_base/ripwire test/packcallersharecheck.sh   # red-first: arm (1) MUST fail here —
#         a binary from before this lane (cd30104) has no shared-anchor re-sort, so the corroborated caller
#         stays in plain site order instead of sorting first. Confirmed manually against a cd30104 build
#         2026-08-21 (lane/corroborated-callers): baseline puts onlyAHelper first; this binary promotes
#         sharedHelper (shared="2") ahead of it.
#
# Exits non-zero on any failure. Does NOT edit regression.sh — listed there separately.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # make BIN absolute BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "git required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "packcallersharecheck: BIN=$BIN"

callersBlock(){   # $1 = xml file -> prints the <callers …>…</callers> substring
    python3 -c "
s = open('$1', encoding='utf-8').read()
i = s.find('<callers')
j = s.find('</callers>', i)
print(s[i:j+len('</callers>')] if i != -1 and j != -1 else '')
"
}

# ── fixture A: TWO ranked anchors (anchorAlpha, anchorBeta) sharing one callee (sharedHelper) and one caller
#    (callerOfBoth) — each also has an anchor-private helper. sharedHelper/callerOfBoth are DECLARED AFTER
#    the two private helpers, so plain site order puts a single-anchor row (onlyAHelper) first; only the
#    corroboration re-sort can promote the two-anchor rows ahead of it. Content-stable (no repo dependency).
WORKA="$TMP/two_anchor"; mkdir -p "$WORKA"
cat > "$WORKA/lib.py" <<'EOF'
def onlyAHelper():
    """called only by anchorAlpha."""
    pass

def onlyBHelper():
    """called only by anchorBeta."""
    pass

def anchorAlpha():
    """anchorAlpha calls onlyAHelper and sharedHelper."""
    onlyAHelper()
    sharedHelper()

def anchorBeta():
    """anchorBeta calls onlyBHelper and sharedHelper."""
    onlyBHelper()
    sharedHelper()

def sharedHelper():
    """reached from BOTH anchorAlpha and anchorBeta -- the corroborated caller."""
    pass

def callerOfBoth():
    anchorAlpha()
    anchorBeta()
EOF
( cd "$WORKA" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm init >/dev/null 2>&1 )
runA(){ ( cd "$WORKA" && "$BIN" . --no-cache "$@" 2>/dev/null ); }

TASKA="anchorAlpha anchorBeta"
runA --pack-task="$TASKA" --token-budget=6000 > "$TMP/a.xml"
BLOCKA="$( callersBlock "$TMP/a.xml" )"

# arm (1) — RED-FIRST: the two-anchor corroborated rows (sharedHelper, callerOfBoth) must sort AHEAD of the
# single-anchor row (onlyAHelper) that plain site order would otherwise put first. This is the exact defect
# a pre-lane (cd30104) binary reproduces — see the usage comment above for the confirmed baseline transcript.
POS_SHARED="$( printf '%s' "$BLOCKA" | grep -bo 'n="sharedHelper"' | head -1 | cut -d: -f1 )"
POS_ONLYA="$(  printf '%s' "$BLOCKA" | grep -bo 'n="onlyAHelper"'  | head -1 | cut -d: -f1 )"
if [ -n "$POS_SHARED" ] && [ -n "$POS_ONLYA" ] && [ "$POS_SHARED" -lt "$POS_ONLYA" ]; then
    ok "corroborated caller (sharedHelper, 2 anchors) sorts AHEAD of the one-anchor caller (onlyAHelper) that plain site order put first"
else
    no "corroborated caller did NOT sort ahead of the one-anchor caller (POS_SHARED=$POS_SHARED POS_ONLYA=$POS_ONLYA) — the re-sort is not wired up"
fi

# arm (1b) — of_top=2 (both anchors ranked) is the precondition the arm above needs to mean anything.
printf '%s' "$BLOCKA" | grep -q 'of_top="2"' \
    && ok "fixture armed: of_top=\"2\" (both anchors ranked, corroboration is possible)" \
    || no "fixture never armed: of_top != 2 — arm (1) proves nothing"

# arm (2) — shared= present and CORRECT: the two callers reached from BOTH anchors carry shared="2"; the two
# reached from only one anchor carry NO shared attribute at all (economy default, see buildD1Row's comment).
check_shared(){   # $1=name $2=expected ("2" or "absent")
    local row; row="$( printf '%s' "$BLOCKA" | grep -o "<s[^>]*n=\"$1\"[^>]*>" )"
    if [ "$2" = "absent" ]; then
        if printf '%s' "$row" | grep -q 'shared='; then
            no "$1: expected NO shared= attribute (uncorroborated default), row: $row"
        else
            ok "$1: shared= correctly omitted (uncorroborated default)"
        fi
    else
        if printf '%s' "$row" | grep -q "shared=\"$2\""; then
            ok "$1: shared=\"$2\" is correct"
        else
            no "$1: expected shared=\"$2\", row: $row"
        fi
    fi
}
check_shared sharedHelper 2
check_shared callerOfBoth 2
check_shared onlyAHelper  absent
check_shared onlyBHelper  absent

# arm (2b) — the JSON dialect carries the same fact (mirrors the XML per --help's "keys mirror ... 1:1").
runA --pack-task="$TASKA" --token-budget=6000 --json > "$TMP/a.json"
if python3 - "$TMP/a.json" <<'PY'
import json, sys
d = json.load( open( sys.argv[1] ) )
byname = { c["n"]: c for c in d.get( "callers", [] ) }
assert byname["sharedHelper"].get( "shared" ) == 2, byname["sharedHelper"]
assert byname["callerOfBoth"].get( "shared" ) == 2, byname["callerOfBoth"]
assert "shared" not in byname["onlyAHelper"], byname["onlyAHelper"]
assert "shared" not in byname["onlyBHelper"], byname["onlyBHelper"]
PY
then
    ok "JSON dialect: callers[].shared matches the XML twin (2/2/absent/absent)"
else
    no "JSON callers[] shared field wrong or missing"
fi

# arm (3) — determinism ×3, byte-identical, on the corroborated fixture.
D1="$( runA --pack-task="$TASKA" --token-budget=6000 )"
D2="$( runA --pack-task="$TASKA" --token-budget=6000 )"
D3="$( runA --pack-task="$TASKA" --token-budget=6000 )"
if [ "$D1" = "$D2" ] && [ "$D2" = "$D3" ]; then
    ok "corroborated bundle is deterministic (byte-identical x3)"
else
    no "corroborated bundle is NOT deterministic across 3 runs"
fi

# arm (3b) — well-formed (G4).
printf '%s' "$D1" | xmllint --noout - 2>/dev/null && ok "corroborated bundle is xmllint-clean (G4)" \
                                                    || no "corroborated bundle is NOT well-formed XML"

# ── fixture B: ONE ranked anchor (anchorSolo) — no corroboration is POSSIBLE (of_top=1, every d1 row can
#    only ever reach the one anchor). The re-sort must therefore be a total no-op and shared= must never
#    appear: the <callers> section's bytes — and so what fits under a fixed budget — must be UNCHANGED from
#    the pre-lane renderer. Content-stable, independent of fixture A.
WORKB="$TMP/one_anchor"; mkdir -p "$WORKB"
cat > "$WORKB/lib.py" <<'EOF'
def anchorSolo():
    """anchorSolo calls helperOne and helperTwo."""
    helperOne()
    helperTwo()

def helperOne():
    """helperOne only reachable from anchorSolo."""
    pass

def helperTwo():
    """helperTwo only reachable from anchorSolo."""
    pass

def callerOfSolo():
    anchorSolo()
EOF
( cd "$WORKB" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm init >/dev/null 2>&1 )
runB(){ ( cd "$WORKB" && "$BIN" . --no-cache "$@" 2>/dev/null ); }

runB --pack-task="anchorSolo" --token-budget=6000 > "$TMP/b.xml"
BLOCKB="$( callersBlock "$TMP/b.xml" )"
# the exact pre-lane rendering of this content-stable fixture (captured 2026-08-21 against both a cd30104
# baseline binary and this lane's binary — byte-identical on both, confirming the re-sort is an inert no-op
# and the economy-of-attributes rule adds nothing when shared is never > 1).
EXPECTB='<callers of_top="1" shown="3" total="3" capped="0"><s t="fn" n="helperOne" p="lib.py:6" rel="callee">def helperOne():</s><s t="fn" n="helperTwo" p="lib.py:10" rel="callee">def helperTwo():</s><s t="fn" n="callerOfSolo" p="lib.py:14" rel="caller">def callerOfSolo():</s></callers>'
if [ "$BLOCKB" = "$EXPECTB" ]; then
    ok "arm (4) budget behavior unchanged: single-anchor <callers> section is BYTE-IDENTICAL to the pre-lane rendering (no shared= bytes spent when corroboration is impossible)"
else
    no "arm (4) single-anchor <callers> section changed shape — expected:
    $EXPECTB
  got:
    $BLOCKB"
fi

# arm (4b) — same property holds at a TIGHT (genuinely CAPPED) budget too: the number of caller rows a fixed
# budget admits must be identical to the pre-lane behavior (no extra bytes silently spent on an uninformative
# shared="1" that would starve a row a smaller-footprint renderer could still afford). budget=950 is the
# specific rung, on this content-stable fixture, where <callers> is capped (shown < total) rather than empty
# or fully-fit — confirmed byte-identical against a cd30104 baseline binary 2026-08-21.
# RE-PINNED 950 -> 1225 (2026-09-04, capture-audit M11): kPackTaskHeaderReserve went 1024 -> 1600 (the header
# had outgrown it) and the <ctx> root gained est_tokens=/budget_tokens=, so the section budgets moved by a
# fixed ~640 B and the capped rung with it — swept 800..2000: empty <= 1205, shown="1" on 1210..1240,
# shown="2" at 1245, fully fit from 1300. 1225 sits mid-window; the PROPERTY (one row admitted, two withheld,
# no bytes spent on an uninformative shared="1") is unchanged.
# RE-PINNED 1225 -> 1235 (2026-09-05, capture-audit P3, lane L7): the r=1 <d> row now carries next="--expand=FILE:NAME"
# (nextverb.h), 45 B the rank section spends first; at 1225 that pushed the callers quota under one row and the
# SECTION was omitted (the pre-existing zeroed-section shape — recorded in lane-L7.md), at 1235 the pinned
# shown="1"/total="3"/capped="1" row is back. Measured on this fixture: base 1225 -> shown=1; new 1225 -> none, 1235 -> shown=1.
# RE-PINNED 1235 -> 1255 (2026-09-05, terminality round A, lane R, P7): the ranking section is FLAT now — every <d>
# row carries p= (+16..20 B apiece) and the <f> wrappers are gone (-24 B apiece) — so on this fixture the rank
# section grew by a few dozen bytes and the callers quota moved with it. Swept 1225..1400 on the new binary:
# section omitted <= 1235, shown="1" on 1240..1270, shown="2" on 1275..1300, fully fit from 1320. 1255 sits
# mid-window; the PROPERTY (one row admitted, two withheld, no bytes spent on an uninformative shared="1") is unchanged.
runB --pack-task="anchorSolo" --token-budget=1255 > "$TMP/b_tight.xml"
TIGHT_TAG="$( grep -o '<callers[^>]*>' "$TMP/b_tight.xml" )"
[ "$TIGHT_TAG" = '<callers of_top="1" shown="1" total="3" capped="1">' ] \
    && ok "arm (4b) capped-budget single-anchor callers: shown=\"1\"/total=\"3\"/capped=\"1\" unchanged from the pre-lane rendering" \
    || no "arm (4b) capped-budget single-anchor callers tag unexpected: $TIGHT_TAG"

if [ "$fail" = "0" ]; then
    echo "ALL PASS"
else
    echo "FAILURES ABOVE"
fi
exit "$fail"

#!/usr/bin/env bash
# gatecountcheck.sh — the published gate count is a BUILD PRODUCT of test/regression.sh's absorb loop,
# and this gate says so.
#
# WHY. The number lived, hand-written, at eight sites across three files. Two lanes that each add one
# gate both write N+1; git auto-merges the IDENTICAL text CLEAN, and the tree then publishes N+1 against
# a loop of N+2. Every existing check stays green through it: "my count equals my own loop" holds on
# each branch, "my loop equals main's loop" holds after the merge, and the member SETS differ at the same
# number. That collided seven times in one night on 2026-09-10 and forced every gate-adding lane to land
# strictly one at a time. The fix is the docs/COMMANDS.md and docs/LIMITS.md fix: stop writing the number
# by hand, derive it, and gate the derivation.
#
# The marker is what makes the derivation enforceable. A count claim on a line carrying the marker is a
# site the generator OWNS and rewrites; a count claim on a line WITHOUT it is a hand-written number, and
# the generator refuses the tree rather than silently leaving it behind — the same "enumerate the family,
# assert over ALL of it" rule test/manifestcheck.sh's sibling arm was widened for, moved one step earlier
# so the sites are WRITTEN right instead of caught wrong.
#
# ARMS
#   (A) the generator exists, runs, and reports a non-zero count derived from the loop.
#   (B) THE GATE: every marked site states exactly what the loop names right now (`--check`).
#   (C) CAN-GO-RED, on the REAL mechanism: a SYNTHETIC tree (real regression.sh + real site files, one
#       extra gate name in the loop) must make --check fail, and regenerating must clear it. It runs
#       against --root on a temp tree, never by dropping a probe file into this one — a probe copy
#       perturbs the very crawl other gates measure.
#   (D) a site that LOST its marker fails loudly: an unmarked count is a hand-written count, so the
#       generator must refuse the tree in BOTH --check and write mode rather than skip the line.
#   (E) the generator refuses a tree whose loop it cannot parse, instead of writing a fabricated number.
#   (F) the three hand-kept copies of the site list (generator, this gate, manifestcheck) agree.
#
# This is a pure source-text check — it does not build or run the ripwire binary.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
GEN="$ROOT/docs/gatecount_build.py"
REGRESSION="$ROOT/test/regression.sh"
MARKER='<!-- gatecount -->'
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

[ -f "$GEN" ]        || { echo "gatecountcheck: no docs/gatecount_build.py"; exit 2; }
[ -f "$REGRESSION" ] || { echo "gatecountcheck: no test/regression.sh"; exit 2; }

# the sites the generator owns, declared here ONLY so this gate can build a synthetic tree from real
# files. The authoritative list lives in the generator (SITES) and arm (B) reads it from there.
SITE_FILES=( "README.md" "docs/EVALS.md" "present/deck5_ripwire_build.js" )

# ── (A) the generator runs and derives a count ──────────────────────────────────────────────────────
genN="$( python3 "$GEN" --check 2>&1 | grep -oE 'names [0-9]+' | head -1 | grep -oE '[0-9]+' )"
loopN="$( python3 -c "
import re, sys
t = open( sys.argv[ 1 ] ).read()
m = re.search( r'for _g in (.*?); do', t, re.S )
sys.exit( 'no loop' ) if not m else print( len( m.group( 1 ).split() ) )
" "$REGRESSION" 2>/dev/null )"
if [ -n "$genN" ] && [ -n "$loopN" ] && [ "$genN" = "$loopN" ]; then
    ok "(A) generator derives $genN from the for-loop in test/regression.sh (independently derived here: $loopN)"
else
    no "(A) generator did not report a count matching an independent derivation (generator='$genN', loop='$loopN')"
fi

# ── (B) every marked site states the loop's length ──────────────────────────────────────────────────
if out="$( python3 "$GEN" --check 2>&1 )"; then
    ok "(B) ${out#*: }"
else
    no "(B) $out"
fi

# ── (C) CAN-GO-RED on a real loop change, in a synthetic tree ───────────────────────────────────────
mkdir -p "$TMP/synth/test" "$TMP/synth/docs" "$TMP/synth/present"
cp "$GEN" "$TMP/synth/docs/gatecount_build.py"
for s in "${SITE_FILES[@]}"; do
    mkdir -p "$TMP/synth/$( dirname "$s" )"
    cp "$ROOT/$s" "$TMP/synth/$s"
done
# add one gate name INSIDE the loop, exactly the way a lane that adds a gate does
awk '/^for _g in /{ sub( /; do$/, " synthonecheck; do" ); print; next } { print }' \
    "$REGRESSION" > "$TMP/synth/test/regression.sh"
if ! grep -q 'synthonecheck; do' "$TMP/synth/test/regression.sh"; then
    no "(C) synthetic setup: could not inject a gate name into the copied loop — the arm would be vacuous"
elif python3 "$TMP/synth/docs/gatecount_build.py" --root "$TMP/synth" --check >/dev/null 2>&1; then
    no "(C) a gate ADDED to the loop did not make --check fail — this gate cannot go red"
else
    python3 "$TMP/synth/docs/gatecount_build.py" --root "$TMP/synth" >/dev/null 2>&1
    if ! python3 "$TMP/synth/docs/gatecount_build.py" --root "$TMP/synth" --check >/dev/null 2>&1; then
        no "(C) regenerating the synthetic tree did not clear the failure"
    else
        # and again, to prove the SECOND lane's identical-text merge is what the gate catches
        awk '/^for _g in /{ sub( /; do$/, " synthtwocheck; do" ); print; next } { print }' \
            "$TMP/synth/test/regression.sh" > "$TMP/synth/test/regression.sh.new"
        mv "$TMP/synth/test/regression.sh.new" "$TMP/synth/test/regression.sh"
        if python3 "$TMP/synth/docs/gatecount_build.py" --root "$TMP/synth" --check >/dev/null 2>&1; then
            no "(C) a SECOND added gate did not make --check fail — the arm goes red only once"
        else
            ok "(C) mutation control: each gate added to the loop goes RED, and regenerating clears it"
        fi
    fi
fi

# ── (D) a site that lost its marker is a hand-written number, and must be refused ────────────────────
mkdir -p "$TMP/unmarked"
cp -R "$TMP/synth/." "$TMP/unmarked/" 2>/dev/null
python3 "$TMP/unmarked/docs/gatecount_build.py" --root "$TMP/unmarked" >/dev/null 2>&1
stripped=0
for s in "${SITE_FILES[@]}"; do
    p="$TMP/unmarked/$s"
    grep -Fq "$MARKER" "$p" 2>/dev/null || continue
    # remove the marker but LEAVE the claim: exactly what a hand edit that drops the comment looks like
    perl -pi -e "s/\\Q$MARKER\\E//" "$p" && stripped=1
    break
done
if [ "$stripped" != 1 ]; then
    no "(D) setup: no markdown site in the synthetic tree carried the marker — the arm is vacuous"
elif python3 "$TMP/unmarked/docs/gatecount_build.py" --root "$TMP/unmarked" --check >/dev/null 2>&1; then
    no "(D) --check accepted a site whose marker was stripped — an unmarked count would ship unnoticed"
elif python3 "$TMP/unmarked/docs/gatecount_build.py" --root "$TMP/unmarked" >/dev/null 2>&1; then
    no "(D) the generator WROTE over a tree carrying an unmarked count claim instead of refusing"
else
    ok "(D) a count claim on an unmarked line is refused, in both --check and write mode"
fi

# ── (E) an unparseable loop is a refusal, not a fabricated number ────────────────────────────────────
mkdir -p "$TMP/noloop/test" "$TMP/noloop/docs" "$TMP/noloop/present"
cp "$GEN" "$TMP/noloop/docs/gatecount_build.py"
for s in "${SITE_FILES[@]}"; do
    mkdir -p "$TMP/noloop/$( dirname "$s" )"
    cp "$ROOT/$s" "$TMP/noloop/$s"
done
printf '#!/usr/bin/env bash\n# the absorb loop has been reshaped and no longer matches\nfor gate in a b c\ndo\n  :\ndone\n' \
    > "$TMP/noloop/test/regression.sh"
if python3 "$TMP/noloop/docs/gatecount_build.py" --root "$TMP/noloop" >/dev/null 2>&1; then
    no "(E) generator wrote a count for a tree whose loop it cannot parse instead of refusing"
else
    ok "(E) generator refuses a tree whose absorb loop it cannot parse"
fi

# ── (F) the three hand-kept copies of the site list name the same files ─────────────────────────────
# The generator owns SITES, this gate keeps SITE_FILES to build its synthetic tree, and
# test/manifestcheck.sh keeps gateCountSites for its post-hoc derived-vs-stated arms. Three copies of
# one list is exactly the shape that let present/deck5_ripwire_build.js:735 go unscanned for a whole
# round while a slide claiming the count "cannot go stale" shipped stale in a public PDF. Nothing
# compared them, so this arm does.
genSites="$( python3 "$GEN" --sites 2>/dev/null | LC_ALL=C sort | tr '\n' ' ' )"
gateSites="$( printf '%s\n' "${SITE_FILES[@]}" | LC_ALL=C sort | tr '\n' ' ' )"
manSites="$( sed -n 's/^gateCountSites=(\(.*\))[[:space:]]*$/\1/p' "$ROOT/test/manifestcheck.sh" \
             | tr -d '"' | tr ' ' '\n' | grep . | LC_ALL=C sort | tr '\n' ' ' )"
if [ -z "$genSites" ] || [ -z "$manSites" ]; then
    no "(F) could not extract a site list (generator='$genSites', manifestcheck='$manSites')"
elif [ "$genSites" = "$gateSites" ] && [ "$genSites" = "$manSites" ]; then
    ok "(F) generator, this gate and manifestcheck name the same sites: $genSites"
else
    no "(F) the site lists disagree — generator [$genSites] gate [$gateSites] manifestcheck [$manSites]"
fi

[ $fail -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

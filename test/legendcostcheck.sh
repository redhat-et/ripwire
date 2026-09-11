#!/usr/bin/env bash
# legendcostcheck.sh — the saving --help ADVERTISES for --legend=compact is the saving it delivers.
#
# WHY. A third-party evaluation (callstack/agent-device #2400, 2026-09-08) measured ripwire as spending
# ~10% MORE tokens than grep-and-read, and traced it to "a fixed per-call preamble, 62% of --callers'
# whole response". That preamble is the legend, `--legend=compact` removes it, and the CLI defaults to
# full. The information was already in --help — buried four lines into a schema description, in KB, after
# an MCP digression — so nobody extracted it. It now LEADS that entry, with a percentage and a claim that
# the payload is byte-identical.
#
# A published percentage rots. This gate READS THE RANGE OUT OF --help and measures against it, so the
# claim and the check cannot drift apart: edit the sentence and this gate re-derives from the new one;
# let the legend grow past what the sentence promises and it fails.
#
# NOT a legend-content gate. The 2026-08-28 density audit capped these legends and
# test/graphlegendbudgetcheck.sh defends that cap; an earlier draft of THIS work tried to add a 205 B
# disclosure clause to the legends themselves and was correctly refused by that gate. Nothing here adds
# a byte to any response.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FAILED=0
fail() { printf '  FAIL  %s\n' "$*"; FAILED=$(( FAILED + 1 )); }
ok()   { printf '  PASS  %s\n' "$*"; }
[ -x "$BIN" ] || { echo "legendcostcheck: no binary at $BIN — build first"; exit 2; }

"$BIN" --help=all >"$TMP/help" 2>/dev/null

# ── the published claim, read from the binary's own help text ──────────────────────────────────
LO="$( grep -oE 'at least [0-9]+% of a' "$TMP/help" | head -1 | grep -oE '[0-9]+' )"
[ -n "$LO" ] || { echo "legendcostcheck: --help no longer advertises a compact saving floor — update this gate WITH the sentence"; exit 1; }
ok "(A) --help publishes an 'at least ${LO}%' floor — measured against the published claim, not a hardcoded one"

# NORMALISE root="<absolute path>" OUT before measuring. It appears once in BOTH postures, so a longer
# checkout path inflates both totals and DEFLATES the percentage: review measured --impact at 50.4% in CI
# (33-char path), 50.3% here, and 49.99% at a 90-char path — i.e. this gate would have gone red on an
# UNMODIFIED binary purely because of where the tree was checked out. A percentage that depends on the
# absolute path is not a property of the tool. (See the partitioncheck path artifact for the same class.)
norm_bytes() { perl -0pe 's/ root="[^"]*"//g' "$1" | wc -c | tr -d " "; }

# The payload comparison must strip comments as a SPAN, not by line: G4 minifies every answer to ONE line
# with no newline outside CDATA, so the `grep -v "^<!--"` this gate used at first deleted the WHOLE
# document in both postures and compared two empty files. It passed with count="999" injected into the
# compact payload. A gate that cannot fail is not a gate.
payload() { perl -0pe 's/<!--.*?-->//gs; s/ root="[^"]*"//g' "$1"; }

# the verbs the sentence names, parsed from the same sentence so the two cannot disagree
VERBS="$( grep -oE '\-\-callers/--uses/--impact/--affected' "$TMP/help" | head -1 | tr '/' '\n' | sed 's/^--//' )"
[ -n "$VERBS" ] || fail "(A) --help names no verbs for the claim"

SEL="lookupLang"
seen=0
for v in $VERBS; do
    case "$v" in
        affected) arg="--affected=src/wrap.h" ;;
        *)        arg="--$v=$SEL" ;;
    esac
    "$BIN" "$ROOT" "$arg"                   >"$TMP/full" 2>/dev/null
    "$BIN" "$ROOT" "$arg" --legend=compact  >"$TMP/comp" 2>/dev/null
    [ -s "$TMP/full" ] && [ -s "$TMP/comp" ] || { fail "(0) '$arg' produced no output in one posture"; continue; }
    seen=$(( seen + 1 ))

    fb=$( norm_bytes "$TMP/full" ); cb=$( norm_bytes "$TMP/comp" )
    pct=$(( ( fb - cb ) * 100 / fb ))

    # (B) A FLOOR ONLY. The sentence says "at least"; a ceiling arm would red on ~130 B of legend growth,
    #     which is graphlegendbudgetcheck's job, not this gate's.
    [ "$pct" -ge "$LO" ] || fail "(B) --$v saves ${pct}% of normalised bytes, below the ${LO}% --help promises"

    # (C) "Every ROW is byte-identical; the only payload change is a schema= the root GAINS." Both halves
    #     asserted: strip comments as spans, drop the ONE schema= attribute compact adds, and what remains
    #     must match exactly. An earlier wording claimed the whole payload was byte-identical, which is
    #     false — compactlegend.h:10 states the root gains schema="ripwire.<verb>/v1".
    payload "$TMP/full" >"$TMP/pf"
    payload "$TMP/comp" | perl -0pe 's/ schema="[^"]*"//' >"$TMP/pc"
    cmp -s "$TMP/pf" "$TMP/pc" || fail "(C) --$v rows DIFFER between postures beyond the schema= attribute — --help says only that changes"
done

# (D) MUTATION CONTROL. Four verbs are named; if the loop measured fewer, the arms above asserted less
#     than they appear to.
if [ "$seen" -ge 4 ]; then
    ok "(D) $seen verbs measured against the published range, payloads identical"
else
    fail "(D) only $seen verb(s) measurable — the arms above asserted almost nothing"
fi

if [ "$FAILED" -ne 0 ]; then
    echo "legendcostcheck: $FAILED failure(s) above"
    exit 1
fi
echo "legendcostcheck: ALL PASS — --help's 'at least ${LO}%' floor holds on all $seen named verbs; rows identical but for the schema= the root gains"

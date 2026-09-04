#!/usr/bin/env bash
# panellegendcheck.sh — G4: the --quality-panel legend must not out-weigh the report it introduces.
#
#   test/panellegendcheck.sh                        # uses build/ripwire on the repo itself
#   RIPWIRE_BIN=asan/ripwire test/panellegendcheck.sh
#
# WHY (density audit 2026-08-08, lane D finding M4). The panel's legend was a single ~7.3 KB prose ESSAY,
# re-emitted on EVERY call — at audit time it exceeded the panel's own payload on this very repo (7,350 B
# legend vs 7,176 B of rows: 35% of the bundle was the same fixed text every reader had already seen).
# The fix: a terse legend that still DEFINES every attribute (the house name= convention, what
# test/legendcoveragecheck.sh derives mechanically) and keeps every HONESTY disclosure — floors, caps,
# unavailability, the join, the per-file historical unit — while the explanatory essay lives once, in
# docs/COMMANDS.md, not in every emission. Two arms:
#   (a) THE AUDIT CRITERION, durable: on the repo's own panel, total comment bytes <= payload bytes
#       (payload = the document minus its comments). The live tree's payload has grown since the audit
#       measured, so (a) alone is not what makes this gate red-first; it is the invariant that must never
#       regress again.
#   (b) THE RATCHET, red pre-fix: the LEADING legend comment is <= 4200 B. The legend is a compile-time
#       constant, so this is a budget on a fixed string, not a flaky corpus measurement (pre-fix: 7,350 B).
#       Re-based 4096 -> 4200 on 2026-09-04 (capture-audit lane L4, PLAN_CAPTURE_AUDIT §1 H8): the legend
#       measured 4,087 B at ec5e3c3 and 4,123 B after the ONE honesty clause H8 requires — findings_capped=1
#       now floors the ROOT's counts too, and the root attribute it introduces (counts_floor=1) must be
#       defined where it is emitted (legendcoveragecheck). A definition the document needs outranks the
#       ratchet; 4200 leaves 77 B for one more such clause and no room for an essay.
#   (c) the terse legend still carries the honesty vocabulary a reader must meet FIRST: the per-file
#       historical unit (qualitypanelcheck N2 pins the exact phrase), floors, unavailability semantics,
#       and the join's denominators.
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN (build first)"; exit 1; }

"$BIN" "$ROOT" --quality-panel >"$TMP/panel.xml" 2>/dev/null
grep -q '<quality_panel ' "$TMP/panel.xml" || { echo "no <quality_panel> in output — cannot measure"; exit 1; }

# Split comment bytes from payload bytes (the audit's own method: comments vs rest).
read -r commentBytes payloadBytes legendBytes <<EOF
$( python3 - "$TMP/panel.xml" <<'PYEOF'
import re, sys
doc = open( sys.argv[1], 'rb' ).read().decode( 'utf-8' )
comments = re.findall( r'<!--.*?-->', doc, re.S )
cb = sum( len( c.encode() ) for c in comments )
total = len( doc.encode() )
lead = len( comments[0].encode() ) if comments else 0   # the LEADING legend comment (the panel's own)
print( cb, total - cb, lead )
PYEOF
)
EOF

# (a) audit criterion: comments never out-weigh the payload on the repo's own panel.
if [ "$commentBytes" -le "$payloadBytes" ]; then
    ok "(a) comment bytes ($commentBytes) <= payload bytes ($payloadBytes) on the repo's own panel"
else
    no "(a) the legend out-weighs the report again: $commentBytes comment B vs $payloadBytes payload B — the M4 finding re-fired"
fi

# (b) the ratchet that made this gate red-first: the leading legend comment fits a 4200 B budget (see header).
if [ "$legendBytes" -le 4200 ]; then
    ok "(b) leading legend comment is $legendBytes B (<= 4200 B budget)"
else
    no "(b) leading legend comment is $legendBytes B (> 4200 B budget) — the essay belongs in docs/COMMANDS.md, not in every emission"
fi

# (c) the honesty vocabulary survives the trim — these are contract, not prose.
sed 's/-->/-->\n/' "$TMP/panel.xml" | sed -n '1,/-->/p' >"$TMP/legend.txt"
for phrase in \
    'historical (git change frequency, measured PER FILE' \
    'inherited by the row' \
    'unavailable=' 'unavailable_why=' 'cut_reachable=' \
    'findings_capped=' 'floor_rules=' 'state_floor=' 'unreadable_files=' \
    'join=' 'tested_scope=' 'deep_untested=' \
    'shown=' 'capped=' 'docs/COMMANDS.md'
do
    if grep -qF "$phrase" "$TMP/legend.txt"; then
        ok "(c) legend keeps: $phrase"
    else
        no "(c) legend lost the honesty marker: $phrase"
    fi
done

# The document must still be well-formed and deterministic after any legend change.
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/panel.xml" 2>/dev/null && ok "(d) panel is well-formed XML" || no "(d) panel fails xmllint"
fi
"$BIN" "$ROOT" --quality-panel >"$TMP/panel2.xml" 2>/dev/null
diff -q "$TMP/panel.xml" "$TMP/panel2.xml" >/dev/null && ok "(d) panel deterministic (byte-identical twice)" || no "(d) panel differs across two runs"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

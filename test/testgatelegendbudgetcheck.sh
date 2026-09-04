#!/usr/bin/env bash
# testgatelegendbudgetcheck.sh — G4: --test-gate's legend must not re-inflate past its ABSOLUTE byte budget.
#
#   test/testgatelegendbudgetcheck.sh                        # uses build/ripwire on the repo itself
#   RIPWIRE_BIN=asan/ripwire test/testgatelegendbudgetcheck.sh
#
# WHY (density audit, lane/fa-legend 2026-08-28, finding C2). On the empty-diff case (a clean working tree,
# bare `--test-gate`), the pre-fix legend was 1689 B against a 299 B payload — 84.7% of the document was the
# same fixed essay repeated on every invocation, root cause src/situ.h kTestGateLegend.
#
# WHY THE RATCHET IS ABSOLUTE BYTES, NOT legend<=payload (unlike graphlegendbudgetcheck.sh's arm a2, which
# CAN use a relative measure because --callers/--impact/--uses payload is real row content). A genuinely
# empty diff has a near-zero payload BY CONSTRUCTION (changed="0" tests="0" untested="0" is the document's
# own honest report of "nothing to say") — a legend<=payload invariant would be unsatisfiable on exactly the
# case this verb exists to handle well, so panellegendcheck.sh's arm (a) shape does not transfer here. An
# absolute byte budget is the correct ratchet.
#
# Exits non-zero on a budget or honesty-marker failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN (build first)"; exit 1; }

# A FIXED file argument (never the bare git-diff default): --test-gate=src/model.h reports the SAME facts
# regardless of the caller's own working-tree dirtiness, which a bare `--test-gate` does not — this repo's
# own worktree may carry uncommitted work while this gate runs. src/model.h is chosen because it is stable,
# widely depended on, and unrelated to this lane's own edits (src/graphlegend.h, src/situ.h).
"$BIN" "$ROOT" --test-gate=src/model.h >"$TMP/tg.xml" 2>/dev/null
grep -q '<test-gate ' "$TMP/tg.xml" || { echo "no <test-gate> in output — cannot measure"; exit 1; }

read -r total legend payload <<EOF
$( python3 - "$TMP/tg.xml" <<'PY'
import re, sys
doc = open( sys.argv[1], 'rb' ).read().decode( 'utf-8' )
m = re.match( r'\A(?:\s*<!--.*?-->)+', doc, re.S )
lead = m.group( 0 ) if m else ''
rest = doc[ len( lead ): ]
print( len( doc.encode() ), len( lead.encode() ), len( rest.encode() ) )
PY
)
EOF

# (a) the ratchet: pre-fix was 1689 B on this exact src/model.h fixture (1dc7b01), post-fix 1332 B. 1500 B
#     gives headroom for a future honest addition without permitting the essay to grow back toward 1689 B.
# RE-PINNED 1500 -> 1750 (2026-09-04, capture-audit M15): the legend gained ONE sentence defining the
# graph_ambiguous=/graph_unresolved= gauge pair every graph-floored root now carries — new content, not the
# essay re-inflating (the pre-fix 1689 B was a different, longer essay).
# RE-PINNED 1750 -> 1900 (2026-09-04, capture-audit wave-1 close, lane L9 M12): the rows-bearing document
# gained root= (what every <t p=>/<u p=> is relative to) and the ONE clause defining it, row-gated with the
# attribute so a zero-row report pays nothing (situ.h tgRootAttr). Measured on this fixture: 1752 B with
# the gauge sentence trimmed to its shortest honest form and L4's M2 trio clause moved into the row legend
# it is a rule about; 1900 leaves ~148 B for one more honest clause and still forbids the 1689 B essay.
if [ "$legend" -le 1900 ]; then
    ok "(a) --test-gate legend is $legend B (<= 1900 B budget; total=$total payload=$payload)"
else
    no "(a) --test-gate legend is $legend B (> 1900 B budget) — the essay re-inflated"
fi

# (b) the honesty vocabulary + the §B12.5 cross-verb UNIT-collision anchors (test/testgatecheck.sh arm (g)
#     already gates these exact phrases tool-wide; this arm is the lane's own quick check on this one verb).
L="$( sed -n '1,/-->/p' "$TMP/tg.xml" )"
for phrase in \
    'UNIT: untested= here counts impacted SYMBOLS' 'call EDGES' 'defs a gate lights' \
    'shown_tests=' 'shown_untested=' 'script_gates_unmodelled=' 'script_gates_registered=' \
    'script_gates_mapped=' 'script_gates_unresolved_dynamic=' 'evidence=script_literal' \
    'evidence=manifest_declared' 'counts_floor=1' 'REPEAT VERBATIM' 'exit 4'
do
    case "$L" in
        *"$phrase"*) ok "(b) legend keeps: $phrase" ;;
        *)           no "(b) legend lost the honesty marker: $phrase" ;;
    esac
done

# (c) well-formed + deterministic, unchanged by a prose-only edit.
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/tg.xml" 2>/dev/null && ok "(c) well-formed XML" || no "(c) fails xmllint"
fi
"$BIN" "$ROOT" --test-gate=src/model.h >"$TMP/tg2.xml" 2>/dev/null
diff -q "$TMP/tg.xml" "$TMP/tg2.xml" >/dev/null && ok "(c) deterministic (byte-identical twice)" || no "(c) differs across two runs"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

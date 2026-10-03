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
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN (build first)"; exit 1; }

# A FIXED file argument (never the bare git-diff default): --test-gate=src/model.h reports the SAME facts
# regardless of the caller's own working-tree dirtiness, which a bare `--test-gate` does not — this repo's
# own worktree may carry uncommitted work while this gate runs. src/model.h is chosen because it is stable,
# widely depended on, and unrelated to this lane's own edits (src/graphlegend.h, src/situ.h).
# L1 (2026-09-19): the CLI default legend is compact; every arm here budgets and reads the FULL legend, so the runs ask for it.
"$BIN" "$ROOT" --test-gate=src/model.h --legend=full >"$TMP/tg.xml" 2>/dev/null
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
# RE-PINNED 1900 -> 2050 (2026-09-04, capture-audit wave-2, lane L8 M21(b)). TWO new FACTS, both row-gated
# (the zero-row report still pays nothing — donelegendcheck.sh's tg_empty ratchet is untouched at 1297 B):
#   +178 B  the run=/run_unknown= rule, spliced from testmap.h's ONE constant (kRunHintLegendClause) so the
#           seven emitters of a tests_to_run row cannot drift into seven wordings. It is what makes the
#           not-derivable case SAYABLE instead of an absence the reader has to notice.
#   + 47 B  the <u> row's own shape, now that those rows carry l= (the line their --flags --flip siblings
#           have always had) — legendcoveragecheck.sh forbids an attribute no legend defines.
# Measured on this fixture: 1752 -> 2002 B. Both clauses were written long, measured, and cut to the
# shortest honest form before the pin moved; 2050 leaves ~48 B and still forbids the 1689 B essay.
# RE-PINNED 2050 -> 2170 (2026-09-05, capture-audit wave-3, lane L7 P3). ONE new FACT on every test-gate root:
#   +106 B  next= — the one pasteable follow-up (the first <t> row's run=, else a ripwire invocation), defined
#           where the reader meets it (legendcoveragecheck). Written long, measured, cut to the shortest honest
#           form (nextverb.h owns the shared half; this is the verb's own reading).
# Measured on this fixture: 2002 -> 2108 B. 2170 leaves ~62 B — the same posture as the 2050 pin.
# RE-PINNED 2170 -> 2260 (2026-09-05, lane L7 P8): ONE more FACT on every test-gate root, ccx_bar= (the cognitive-
# complexity bar a <u> row's ccx= is read against — quality-delta's own, mirrored from quality.h), defined where the
# reader meets it: +97 B. Measured 2108 -> 2205 B; 2260 leaves ~55 B, the same posture again.
# RE-PINNED 2540 -> 2720 (2026-09-08, issue #66). ONE new FACT on the root: graph_unindexed=, the third gauge
# beside graph_ambiguous=/graph_unresolved= — files no grammar in this build could read at all, the blind spot
# that made a `count="0"` indistinguishable from "none exists" on a tree whose callers all lived in .astro.
# +177 B, defined where the reader meets it (legendcoveragecheck). The sentence is CONDITIONAL — emitted only
# when the attribute is (graphlegend.h graphUnindexedLegend( bool )), so a corpus with nothing unindexed pays
# 0 B and this budget is the WITH-attribute case, which is what this repository's own tree exercises.
# Measured on this fixture: 2486 -> 2663 B; 2720 leaves ~57 B — the same posture as every pin below.
# RE-PINNED 2260 -> 2540 (2026-09-07, head-to-head vs Graft, F1). THREE new FACTS on every <t> row, row-gated
# (the zero-row report still pays nothing): changed= (the test file is IN the change set — before this a diff
# of {src, its test} exited 0 with nothing to run, the test's own symbols skipped as "the change"), partner=
# (a test NAMED after a changed file, listed by convention when the graph never reaches it: rocksdb's
# tiered_secondary_cache_test.cc builds through a factory) and hops= (caller-walk depth; 1 = a direct call),
# plus the evidence ORDER the rows now come in. One clause, testmap.h's kTestRowEvidenceLegend, spliced by
# --affected/--situ/--test-gate alike so the emitters cannot drift. Written long (477 B), measured, cut to
# the shortest honest form (281 B). Measured on this fixture: 2205 -> 2486 B; 2540 leaves ~54 B — the same
# posture as every pin above.
# RE-PINNED 2720 -> 2900 (2026-09-12, output-routing loop E1 / A4-2, owner call). ONE new FACT, in the SAME
# row-gated clause (testmap.h kRunHintLegendClause, so the zero-row report still pays nothing):
#   +180 B  the <g> group row — 2+ runner-less rows with equal evidence attributes served as ONE row, n= how
#           many, p= their paths in list order, every path verbatim. It is what lets the not-derivable
#           disclosure be said once per GROUP instead of once per row (rocksdb, 127 rows: 126
#           `run_unknown="1"` -> 10, test-gate 13,242 -> 9,633 B) and legendcoveragecheck wants n= defined
#           wherever a document carries it.
# Measured on this fixture: 2663 -> 2843 B.
# RE-PINNED 2900 -> 3000 (2026-09-13, review of #214). TWO facts a consumer of a <g> row cannot do without,
# both in the same row-gated clause, so a zero-row report still pays nothing:
#   +65 B   a path holding ',' is NEVER grouped, so p= splits into exactly n= paths. The seam used to spell
#           such a path &#44; and say so here; every XML parser undoes that entity BEFORE a consumer splits
#           on the delimiter, so the escape was a promise the format could not keep. Refusing to group the
#           row is the only spelling that is right in all three dialects, and this sentence is what makes
#           `split( p, "," )` a safe thing for a reader to write.
#   +49 B   a section's shown=/total= over these rows count test FILES, so a <g n=N> row is N of them. Same
#           finding from the other side: --pack-task prints <tests shown="54" total="109"> above 30-odd
#           RENDERED rows, and the bundle legend's own "shown=rows kept" sentence flatly contradicted it.
#           Said HERE rather than in that always-on bundle legend, which is charged against the ceiling it
#           describes: unconditional it put packtaskcheck's 2000-token arm 5620 B over a 5428 B ceiling
#           (measured), and a bundle with no <tests> section has no use for it.
# Measured on this fixture: 2843 -> 2957 B; 3000 leaves ~43 B — the same posture as every pin above.
# RE-PINNED 3000 -> 3070 (2026-09-13, review of #219). ONE new FACT, in the same row-gated clause, and
# CONDITIONAL on top of that (testmap.h kRunRootRelSentence, spliced only when runsAreRootRelative — a
# multi-root run declares no root= and pays 0 B):
#   +56 B   "A run= command is relative to root=: run it from there." The run= commands themselves became
#           root-relative in this lane, which is what makes the document independent of where the tree is
#           checked out — and a relative command whose anchor is not stated is a command the reader cannot
#           paste. The rule is said where it is consumed, beside the rows it is about.
# Measured on this fixture: 2957 -> 3013 B; 3070 leaves ~57 B — the same posture as every pin above.
# RE-PINNED 3070 -> 3400 (rv-test-gate-tsjs fix round, F3). ONE new FACT, row-gated on untested_modscope=N > 0
# (this fixture's own blast radius over src/model.h has real <file-scope> callers reaching it, so the clause
# fires here, not just on a synthetic fixture):
#   "untested_modscope=N counts <file-scope> owners excluded from untested= ... read this as the excluded
#   count alone, not a sum term." — the disclosure #324 owed once it started excluding a real obligation
#   from untested= without saying so (a silent pass a review caught: exit 0 with nothing explaining why).
# Measured on this fixture: 3013 -> 3305 B; 3400 leaves ~95 B — the same posture as every pin above.
# RE-PINNED 3400 -> 3730 (lane/builtin-bind-065 fix round, review finding M1). ONE new FACT, gated on declined_calls=K > 0:
# the radius over src/model.h is reached by call sites the resolver declined to bind (tier-3 splits, and on this tree the
# builtin-method gate's declines in bench/ and test/ scripts), and a test behind one of them is in no row — --test-gate
# was the one caller-reading verb that said nothing about them. The clause is --test-gate's own short form
# (graphlegend.h kDeclinedCallsTestGateLegend, 186 B, not the 620 B shared one) plus the gate sentence (143 B) that rides
# only a graph where the builtin-method gate declined a call. Measured on this fixture: 3305 -> 3634 B; 3730 leaves ~95 B.
# RE-PINNED 3730 -> 3930 (lane/answer-honesty-067, comparison table hono-20/textual-20). ONE new FACT, gated on
# run_first=N being on the root (it rides only when the run-first tier splits the <t> rows, as it does over src/model.h):
# testmap.h kRunFirstLegend, 237 B (renamed from must_run= in review, with the not-a-skip-list reading). Measured on this fixture: 3634 -> 3871 B; 3930 leaves
# ~59 B — the same posture as every pin above.
if [ "$legend" -le 3930 ]; then
    ok "(a) --test-gate legend is $legend B (<= 3930 B budget; total=$total payload=$payload)"
else
    no "(a) --test-gate legend is $legend B (> 3930 B budget) — the essay re-inflated"
fi

# (b) the honesty vocabulary + the §B12.5 cross-verb UNIT-collision anchors (test/testgatecheck.sh arm (g)
#     already gates these exact phrases tool-wide; this arm is the lane's own quick check on this one verb).
L="$( sed -n '1,/-->/p' "$TMP/tg.xml" )"
for phrase in \
    'UNIT: untested= here counts impacted SYMBOLS' 'call EDGES' 'defs a gate lights' \
    'shown_tests=' 'shown_untested=' 'script_gates_unmodelled=' 'script_gates_registered=' \
    'script_gates_mapped=' 'script_gates_unresolved_dynamic=' 'evidence=script_literal' \
    'evidence=manifest_declared' 'counts_floor=1' 'REPEAT VERBATIM' 'exit 4' \
    'untested_modscope=N counts <file-scope> owners excluded from untested='
do
    case "$L" in
        *"$phrase"*) ok "(b) legend keeps: $phrase" ;;
        *)           no "(b) legend lost the honesty marker: $phrase" ;;
    esac
done

# (c) well-formed + deterministic, unchanged by a prose-only edit.
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/tg.xml" 2>/dev/null; then ok "(c) well-formed XML"; else no "(c) fails xmllint"; fi
fi
"$BIN" "$ROOT" --test-gate=src/model.h --legend=full >"$TMP/tg2.xml" 2>/dev/null
if diff -q "$TMP/tg.xml" "$TMP/tg2.xml" >/dev/null; then ok "(c) deterministic (byte-identical twice)"; else no "(c) differs across two runs"; fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

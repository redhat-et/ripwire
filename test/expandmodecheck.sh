#!/usr/bin/env bash
# expandmodecheck.sh — M6 (density audit 2026-08-08, lane D): cheapest-complete-answer serving for --expand.
#
#   test/expandmodecheck.sh                        # uses build/ripwire on test/expandmodefix
#   RIPWIRE_BIN=asan/ripwire test/expandmodecheck.sh
#
# WHY. A bare `--expand=SYM` always carried the full global ranked map: on a symbol in a SMALL file the
# bundle was 5.65x LARGER than the whole file it was summarizing (this repo: --expand=pageRankDouble
# 27,890 B vs src/pagerank.cpp 4,936 B — and still 1.08x the file at --top-k=0), while on a big file the
# same bundle saves ~26x over reading the file. Owner directive: ONE call does the smart thing, no
# "read the stderr note, re-run with --top-k=0" two-step. So --expand now compares, BEFORE emitting, the
# byte cost of the default bundle (map + bodies) against the whole file(s) the requested symbols live in,
# and serves the smaller, disclosing the choice deterministically on the <ctx> root:
#   mode="whole-file" reason="file NB < bundle MB"   — the file(s), CDATA-wrapped, symbol line anchors kept
#   mode="bundle"     reason="bundle MB <= file NB"  — today's map+bodies bundle, now labelled
# An EXPLICIT --top-k=N overrides auto-selection entirely (the agent asked for the map; N=0 is the lean
# bodies-only form) and keeps the legacy byte-shape: no mode= attribute at all.
# The lean (--top-k=0) form deliberately does NOT compete in auto-selection: it is a strict byte-subset of
# the bundle, so a three-way minimum could never serve the map and a bare --expand would silently lose its
# orientation value; lean stays what it has always been — the caller's explicit choice.
#
# Arms (all three of the audit's RED assertions):
#   (1) small-file symbol -> mode="whole-file", the full file in CDATA with the symbol's line anchor, and
#       total bytes <= file bytes + 700 B envelope slack;
#   (2) large-file symbol -> mode="bundle": the ranked map and <bodies> both still present;
#   (3) explicit --top-k=5 forces the map back with NO mode= attribute (override semantics), and explicit
#       --top-k=0 stays the undecorated lean form.
# Plus: xmllint well-formedness on every mode, determinism on the auto modes, and the disclosed byte
# comparison must agree with reality (whole-file total < the bundle total actually measured in arm 2's
# world). The fixture is copied to a tmp dir OUTSIDE any git repo and scanned via a RELATIVE path, so
# output carries no churn attrs and no absolute paths. Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN (build first)"; exit 1; }

mkdir -p "$TMP/fix"
cp "$ROOT"/test/expandmodefix/*.c "$TMP/fix/"
cd "$TMP"
fileBytes="$( wc -c <"$TMP/fix/small.c" | tr -d ' ' )"

# ── (1) small-file symbol: the whole file is the cheapest complete answer ─────────────────────────────
# V1 fix (verifier finding 1, 2026-08-15): smallProbe is an EXACT-NAME match, so its own default bundle
# is now the LEAN (topk_default="0") body — not map+body — per the same V1 default arm (2) already
# accounts for on bigProbe007. That makes small.c's fixture genuinely byte-minimal a REQUIREMENT, not
# cosmetic: with the estimator's phantom-map bug fixed, a lean body beats any file bytes it does not
# have to pay a descriptive header comment for, so small.c carries NO leading comment (unlike big.c,
# whose bulk swamps a header either way) — a comment here was previously masking the correct comparison
# by inflating the file side just enough to keep mode="whole-file" for the wrong reason.
# L1 (2026-09-19): the CLI default legend is compact. Arm (4)'s identity — reason='s served price IS the delivered
# byte count — is priced by chooseExpandServe in the FULL dialect (both candidates, before any compaction), so the four
# documents arm (4) reads ask for the full legend; under the compact default reason= keeps the full-dialect candidate
# prices, recorded as a found item in the L1 lane report rather than hidden by moving one of the two numbers.
"$BIN" fix --expand=smallProbe --no-cache --legend=full >"$TMP/small.xml" 2>/dev/null
grep -q 'mode="whole-file"' "$TMP/small.xml" \
    && ok "(1) small-file --expand serves mode=\"whole-file\"" \
    || no "(1) small-file --expand did not serve mode=\"whole-file\" (the 5.65x-over-file bundle again)"
grep -q 'reason="file [0-9]*B &lt; bundle [0-9]*B"' "$TMP/small.xml" \
    && ok "(1) the choice is disclosed as reason=\"file NB &lt; bundle MB\" (escaped '<' — a raw one is ill-formed in an attribute)" \
    || no "(1) no deterministic reason= disclosure on the whole-file form"
grep -q 'CDATA' "$TMP/small.xml" \
    && ok "(1) whole-file body is CDATA-wrapped (G4 well-formedness)" \
    || no "(1) whole-file form carries no CDATA section"
grep -q 'smallProbe:' "$TMP/small.xml" \
    && ok "(1) the symbol's line anchor survives (sym name:line)" \
    || no "(1) whole-file form lost the symbol's line anchor"
total="$( wc -c <"$TMP/small.xml" | tr -d ' ' )"
if [ "$total" -le $(( fileBytes + 700 )) ]; then
    ok "(1) total $total B <= file $fileBytes B + 700 B envelope slack"
else
    no "(1) whole-file form costs $total B against a $fileBytes B file — envelope slack blown"
fi
if grep -q '<r ' "$TMP/small.xml"; then
    no "(1) the ranked map still rides along in whole-file mode"
else
    ok "(1) no ranked map in whole-file mode"
fi

# ── (2) large-file symbol: the bundle stays the cheapest complete answer ──────────────────────────────
# V1 (2026-08-15, ugrep RN2): bigProbe007 is an EXACT-NAME, unambiguous --expand (one token, one match), so
# it now ALSO defaults its own map to top-k=0 — the ranked map that used to ride inside "bundle" mode is
# gone, and the root discloses the default with topk_default="0" (test/expandtopk0check.sh is the dedicated
# gate for that mechanism; this arm just keeps M6's bundle-vs-whole-file byte comparison honest under it).
"$BIN" fix --expand=bigProbe007 --no-cache --legend=full >"$TMP/big.xml" 2>/dev/null
grep -q 'mode="bundle"' "$TMP/big.xml" \
    && ok "(2) large-file --expand keeps mode=\"bundle\"" \
    || no "(2) large-file --expand lost the bundle mode"
grep -q 'topk_default="0"' "$TMP/big.xml" \
    && ok "(2) bundle mode discloses the V1 exact-name top-k=0 default" \
    || no "(2) bundle mode lost the topk_default=\"0\" disclosure"
if grep -q '<r ' "$TMP/big.xml"; then
    no "(2) the ranked map still rides along in bundle mode (V1 regression: exact-name --expand must default to top-k=0)"
else
    ok "(2) no ranked map in bundle mode (V1: exact-name default)"
fi
grep -q '<bodies' "$TMP/big.xml" \
    && ok "(2) the <bodies> payload is present in bundle mode" \
    || no "(2) bundle mode lost the <bodies> payload"
grep -q 'reason="bundle [0-9]*B &lt;= file [0-9]*B"' "$TMP/big.xml" \
    && ok "(2) bundle mode discloses the comparison it won" \
    || no "(2) bundle mode carries no reason= disclosure"

# ── the disclosed comparison agrees with reality ──────────────────────────────────────────────────────
bundleTotal="$( wc -c <"$TMP/big.xml" | tr -d ' ' )"
if [ "$total" -lt "$bundleTotal" ]; then
    ok "(1v2) whole-file total ($total B) < bundle total ($bundleTotal B) on this fixture — the choice saved bytes"
else
    no "(1v2) whole-file mode ($total B) did not beat the bundle ($bundleTotal B)"
fi

# ── (3) explicit --top-k overrides auto-selection, legacy byte-shape ──────────────────────────────────
"$BIN" fix --expand=smallProbe --top-k=5 --no-cache >"$TMP/topk5.xml" 2>/dev/null
grep -q '<r ' "$TMP/topk5.xml" \
    && ok "(3) --top-k=5 forces the map back" \
    || no "(3) --top-k=5 did not restore the ranked map"
if grep -q 'mode="' "$TMP/topk5.xml"; then
    no "(3) explicit --top-k=5 still carries a mode= attribute — override must keep the legacy shape"
else
    ok "(3) explicit --top-k=5 output is undecorated (no mode= attribute)"
fi
"$BIN" fix --expand=smallProbe --top-k=0 --no-cache >"$TMP/topk0.xml" 2>/dev/null
if grep -q '<r \|mode="' "$TMP/topk0.xml"; then
    no "(3) explicit --top-k=0 must stay the undecorated lean form (no map, no mode=)"
else
    ok "(3) explicit --top-k=0 stays the undecorated lean form"
fi

# ── (3b) a RANGE slice is an explicit narrowing: serving the whole file would invert the ask ──────────
"$BIN" fix --expand=smallProbe:2-3 --no-cache >"$TMP/range.xml" 2>/dev/null
if grep -q 'mode="' "$TMP/range.xml"; then
    no "(3b) a ranged --expand=SYM:2-3 must keep the legacy shape (no mode= auto-selection)"
else
    ok "(3b) a ranged --expand=SYM:2-3 keeps the legacy shape (slice contract untouched)"
fi
grep -q 'lines="' "$TMP/range.xml" \
    && ok "(3b) the slice marker (lines=) survives" \
    || no "(3b) the ranged request lost its lines= slice marker"

# ── well-formedness + determinism ─────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    for f in small big topk5 topk0; do
        if xmllint --noout "$TMP/$f.xml" 2>/dev/null; then ok "(G4) $f.xml well-formed"; else no "(G4) $f.xml fails xmllint"; fi
    done
fi
"$BIN" fix --expand=smallProbe --no-cache --legend=full >"$TMP/small2.xml" 2>/dev/null
diff -q "$TMP/small.xml" "$TMP/small2.xml" >/dev/null \
    && ok "(det) whole-file mode byte-identical twice" \
    || no "(det) whole-file mode differs across two runs"
"$BIN" fix --expand=bigProbe007 --no-cache --legend=full >"$TMP/big2.xml" 2>/dev/null
diff -q "$TMP/big.xml" "$TMP/big2.xml" >/dev/null \
    && ok "(det) bundle mode byte-identical twice" \
    || no "(det) bundle mode differs across two runs"


# ── (4) THE PRICE IS THE DOCUMENT, AND ONE FUNCTION PRICES BOTH CANDIDATES (CodeRabbit, PR #215) ──────
#
# THE DEFECT. The two candidates were priced by two hand-built counters. The bundle side was charged its
# `<ctx>` envelope, its root attributes, the unproven residue, the map and the rendered <bodies>; the file
# side was charged `wf.rawBytes + the whole-file legend` — no envelope, no root attributes, no `</ctx>`, and
# the file's RAW bytes rather than the `<src p= sym=>` blocks that actually carry them. Measured on a 864 B
# file: reason= said "file 1100B" for a document that came out 1263 B. Two consequences, one cause:
#   * the reported number is not the document's, so an agent budgeting the next call is told the wrong price;
#   * inside a 163 B band the tool chose — and DISCLOSED — the whole-file form while the bundle it rejected
#     was the smaller document. Measured on the pre-fix binary at this fixture's 800 B padding: served
#     1262 B under reason="file 1100B &lt; bundle 1193B".
# This was the SECOND asymmetry found in this one comparison (the first, one review round earlier, was the
# whole-file legend), which is the tell: the bug is the two counters, not the missing addends. Both candidates
# now describe themselves as an ExpandServeDocument and are priced by priceExpandServeDocument (main.cpp), so
# the comparison is symmetric by construction and a third candidate cannot be added asymmetrically.
#
# WHAT IS PINNED. (4a)/(4b) the identity — in each mode, the number reason= attributes to the mode that WON
# equals the delivered document's byte count, exactly. That is the assertion two hand-built counters cannot
# satisfy, and it holds whatever the corpus does, so it pins no magic byte count. (4c) the CHOICE: across a
# padding sweep that straddles the decision boundary in both directions, the document served is never larger
# than the number reason= attributes to the candidate it rejected. (4c) is what goes red inside the band.
reason_num(){ # $1 = xml file, $2 = the word the number follows ("file" or "bundle")
    grep -o "$2 [0-9]*B" "$1" | head -1 | tr -dc '0-9'
}
wf_num="$( reason_num "$TMP/small.xml" file )"
if [ -n "$wf_num" ] && [ "$wf_num" = "$total" ]; then
    ok "(4a) whole-file mode: reason=\"file ${wf_num}B\" IS the delivered document ($total B) — one price, one document"
else
    no "(4a) whole-file mode prices a document it does not serve: reason=\"file ${wf_num:-unreadable}B\" against $total B delivered — the envelope, the root attributes, the <src> wrapper and </ctx> are uncharged on this side"
fi
bd_num="$( reason_num "$TMP/big.xml" bundle )"
if [ -n "$bd_num" ] && [ "$bd_num" = "$bundleTotal" ]; then
    ok "(4b) bundle mode: reason=\"bundle ${bd_num}B\" IS the delivered document ($bundleTotal B) — the same price the file side is compared against"
else
    no "(4b) bundle mode prices a document it does not serve: reason=\"bundle ${bd_num:-unreadable}B\" against $bundleTotal B delivered"
fi

# (4c) the decision boundary, swept. Padding is a block comment, so it grows the FILE without growing the
# body the bundle would serve — which walks the two candidates past each other. The file name and the fixture
# dir are fixed-length on purpose: root="…" rides in both prices, and a length that moves with a mktemp name
# would move the band with it (the fixture-path-length trap this suite records elsewhere).
mkdir -p "$TMP/narrow"
sweep_n=0; sweep_bad=0; sweep_wf=0; sweep_bun=0
for pad in 600 700 800 900 1000 1100 1200; do
    rm -f "$TMP/narrow/n.c"
    {   printf 'int narrowProbe( int value )\n{\n    return value * 2 + 1;\n}\n/*'
        python3 -c "import sys; sys.stdout.write( 'x' * $pad )"
        printf '*/\n'
    } > "$TMP/narrow/n.c"
    ( cd "$TMP" && "$BIN" narrow --expand=narrowProbe --no-cache --legend=full ) >"$TMP/narrow.xml" 2>/dev/null
    got="$( wc -c <"$TMP/narrow.xml" | tr -d ' ' )"
    sweep_n=$(( sweep_n + 1 ))
    if grep -q 'mode="whole-file"' "$TMP/narrow.xml"; then
        sweep_wf=$(( sweep_wf + 1 ))
        rejected="$( reason_num "$TMP/narrow.xml" bundle )"; label="rejected bundle"
    elif grep -q 'mode="bundle"' "$TMP/narrow.xml"; then
        sweep_bun=$(( sweep_bun + 1 ))
        rejected="$( reason_num "$TMP/narrow.xml" file )"; label="rejected whole-file"
    else
        sweep_bad=$(( sweep_bad + 1 ))
        printf '        pad=%s: no mode= disclosure at all\n' "$pad"
        continue
    fi
    if [ -z "$rejected" ] || [ "$got" -gt "$rejected" ]; then
        sweep_bad=$(( sweep_bad + 1 ))
        printf '        pad=%s: served %s B, larger than the %s it priced at %s B — %s\n' \
               "$pad" "$got" "$label" "${rejected:-unreadable}" "$( grep -o 'reason="[^"]*"' "$TMP/narrow.xml" | head -1 )"
    fi
done
[ "$sweep_wf" -gt 0 ] && [ "$sweep_bun" -gt 0 ] \
    && ok "(4c) the $sweep_n-point sweep straddles the decision boundary ($sweep_wf whole-file, $sweep_bun bundle) — the arm below is not vacuous" \
    || no "(4c) the sweep chose one mode at every padding ($sweep_wf whole-file, $sweep_bun bundle) — it never crosses the boundary, so it proves nothing; re-anchor the padding band"
[ "$sweep_bad" -eq 0 ] \
    && ok "(4c) at all $sweep_n paddings the served document is no larger than the candidate it rejected — the comparison is symmetric" \
    || no "(4c) $sweep_bad of $sweep_n paddings served a document LARGER than the candidate they rejected (listed above) — the two candidates are priced on different accounting"

# (4d) the AMBIGUOUS name (two definitions). Until expand-lean-k64 (2026-10-08) this arm was the only one to exercise the
# bundle price's mapBytes term: a multi-definition name kept the ranked map, and the bundle then won carrying it. A name whose
# definitions are ALL served now ships no map (the bodies already answer it), so the CLI no longer reaches a bundle that rides a
# map under mode= selection (a composed --outline/--max-tokens/--query owns the map and opts out of mode= selection). The map
# term is therefore 0 on this shape too, and the identity this arm pins is the same one (4a)/(4b) pin, now on the
# multi-definition document: reason="bundle NB" IS the delivered document, and no ranked map rides.
mkdir -p "$TMP/ambig"
for f in a b; do
    {   printf 'int dupSym( int a ) { return a + 1; }\n/*'
        python3 -c "import sys; sys.stdout.write( 'y' * 4000 )"
        printf '*/\nint other_%s( void ) { return dupSym( 1 ); }\n' "$f"
    } > "$TMP/ambig/$f.c"
done
( cd "$TMP" && "$BIN" ambig --expand=dupSym --no-cache --legend=full ) >"$TMP/ambig.xml" 2>/dev/null
ambTotal="$( wc -c <"$TMP/ambig.xml" | tr -d ' ' )"
amb_num="$( reason_num "$TMP/ambig.xml" bundle )"
if grep -q '<r ' "$TMP/ambig.xml"; then
    no "(4d) the ambiguous --expand=dupSym (all definitions served) still carried a ranked map"
elif [ -n "$amb_num" ] && [ "$amb_num" = "$ambTotal" ]; then
    ok "(4d) bundle mode on a multi-definition name, no map: reason=\"bundle ${amb_num}B\" IS the delivered document ($ambTotal B)"
else
    no "(4d) bundle mode on a multi-definition name prices a document it does not serve: reason=\"bundle ${amb_num:-unreadable}B\" against $ambTotal B delivered"
fi
# (4d-twin) the explicit-top-k path keeps its map, and mode= selection stands aside there (the agent asked for the map)
( cd "$TMP" && "$BIN" ambig --expand=dupSym --top-k=5 --no-cache --legend=full ) >"$TMP/ambig5.xml" 2>/dev/null
if grep -q '<r ' "$TMP/ambig5.xml" && ! grep -q 'mode="' "$TMP/ambig5.xml"; then
    ok "(4d-twin) explicit --top-k=5 on the ambiguous name keeps the map and the undecorated shape"
else
    no "(4d-twin) explicit --top-k=5 on the ambiguous name: map or mode= wrong: $( grep -oE '<ctx[^>]*>' "$TMP/ambig5.xml" )"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

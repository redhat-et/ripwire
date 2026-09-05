#!/usr/bin/env bash
# droppedpositivecheck.sh — A2 (survey card, 2026-09-03): dropped_positive="N" on the --for and --pack-task
# roots (CLI XML/JSON and their MCP twins for/pack_task). See docs/EVALS.md's A2 registration for the band.
#
# THE COUNT. How many symbols scored ABOVE the relevance floor (positives by the ranker's own cut — LB-A's
# admission rule, serialize.h relevanceFloorCut/relevanceFlooredKeep) within the kept head, and were then
# removed by the PAYLOAD ceiling rather than a content reason (an unreadable file, an out-of-range signature
# span, an empty cleaned signature). Computed once, shared by the XML and JSON dialects, in
# serialize.h::droppedPositiveCount (packSignatures / packSignaturesJson's droppedPositiveOut param).
#
# VERIFICATION METHOD (the round's own prescription): for each shape, run the SAME query at a budget wide
# enough to serve the whole kept head without any ladder trim ("the reference run"), then run it again at a
# tight budget ("the capped run"). The reference run's own <d>/{"r":…} rows are exactly the kept head's
# survivors when nothing drops (every positive candidate reaches a row — this gate's arm 0 below checks that
# precondition holds before trusting a shape as a reference), so `reference_rows - capped_rows` (matched by
# r=, the 1-based GLOBAL rank assigned once before any trim, invariant across budgets for the SAME query) is
# the ground truth the reported attribute must equal exactly. Getting this wrong is worse than not shipping
# the attribute at all — a floor label (`_floor`/`_capped`) is for a count that admits it might be short;
# this one has no such hedge (docs/EVALS.md A2 band).
#
# TRAP RECORDED DURING DEVELOPMENT: --for's AUTO-BUNDLE sig-side ceiling (forSigSideCeiling, verbs_for.h) is
# frozen at kForPayloadBudgetBytes regardless of how large an explicit --token-budget is — a huge
# --token-budget alone does NOT make <sigs> unbounded in that mode, and using it as a "reference" run without
# --signatures-only silently produces a reference that is ITSELF still capped, which reads as a false
# mismatch (looks like the attribute over-counts by the reference's own hidden shortfall). The fix: pair the
# reference and capped runs under the SAME serving shape (both --signatures-only, or both --json, or both
# --pack-task) so forSigSideCeiling's clamp — present or absent — is identical on both sides, and additionally
# use a --token-budget wide enough (tens of millions of bytes-equivalent) that the reference is provably past
# any real corpus's kept-head size.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/droppedpositivecheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
cd "$ROOT"
echo "droppedpositivecheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
CORPUS="$ROOT/src"
CONC="tree-sitter parse of a source file"       # a broad conceptual query — many symbols score>0, budget bites

# ── shared verification: (reference_file, capped_file, dialect) -> exact-match assertion ──────────────────
# dialect: xml | json — how rows/ranks are extracted and how the attribute is spelled.
verify_exact(){
    local label="$1" ref="$2" capped="$3" dialect="$4"
    python3 - "$ref" "$capped" "$dialect" <<'PY'
import sys, re, json
ref_path, capped_path, dialect = sys.argv[1], sys.argv[2], sys.argv[3]
ref = open(ref_path, encoding='utf-8', errors='replace').read()
cap = open(capped_path, encoding='utf-8', errors='replace').read()

if dialect == 'xml':
    def sigs_block(doc):
        a = doc.find('<sigs'); b = doc.find('</sigs>')
        return doc[a:b+7] if a >= 0 and b >= 0 else ''
    ref_ranks = sorted(int(m) for m in re.findall(r'<d [^>]*r="(\d+)"', sigs_block(ref)))
    cap_ranks = sorted(int(m) for m in re.findall(r'<d [^>]*r="(\d+)"', sigs_block(cap)))
    m = re.search(r'dropped_positive="(\d+)"', cap)
    reported = int(m.group(1)) if m else 0
    ref_has_attr = 'dropped_positive="' in ref
else:
    refd = json.loads(ref); capd = json.loads(cap)
    def ranks(doc):
        out = []
        for s in doc.get('sigs', []):          # P7: the JSON sigs array is FLAT (one row object per ranked symbol)
            if 'r' in s:
                out.append(s['r'])
        return out
    ref_ranks = sorted(ranks(refd))
    cap_ranks = sorted(ranks(capd))
    reported = capd.get('dropped_positive', 0)
    ref_has_attr = 'dropped_positive' in refd

if set(cap_ranks) - set(ref_ranks):
    print("FAIL capped run served a rank the reference never did — the reference is not wide enough")
    sys.exit(1)
if ref_has_attr:
    print("FAIL the reference run itself carries dropped_positive= — it is not a valid ground truth (still capped)")
    sys.exit(1)
if len(ref_ranks) == 0:
    print("FAIL reference run served zero rows — no signal to verify against")
    sys.exit(1)
true_dropped = len(set(ref_ranks) - set(cap_ranks))
if true_dropped == reported:
    print(f"OK true={true_dropped} reported={reported} (ref={len(ref_ranks)} capped={len(cap_ranks)})")
    sys.exit(0)
print(f"FAIL true={true_dropped} reported={reported} (ref={len(ref_ranks)} capped={len(cap_ranks)})")
sys.exit(1)
PY
}

# ── #0: presence guard — the padding this gate needs really exists (a wide gap between ref and capped) ────
"$BIN" "$CORPUS" --for="$CONC" --signatures-only --token-budget=10000000 --no-cache >"$TMP/for_xml_ref" 2>/dev/null
"$BIN" "$CORPUS" --for="$CONC" --signatures-only --token-budget=1500     --no-cache >"$TMP/for_xml_cap" 2>/dev/null
REFROWS=$( grep -o '<d ' "$TMP/for_xml_ref" | wc -l | tr -d ' ' )
CAPROWS=$( grep -o '<d ' "$TMP/for_xml_cap" | wc -l | tr -d ' ' )
if [ "${REFROWS:-0}" -gt "${CAPROWS:-0}" ]; then
    ok "#0 presence guard: reference ($REFROWS rows) wider than capped ($CAPROWS rows) — padding exists to detect"
else
    no "#0 presence guard: reference not wider than capped (ref=$REFROWS cap=$CAPROWS) — fixture/budgets need revisiting"
fi

# ── #1: --for XML (--signatures-only, so forSigSideCeiling's auto-bundle clamp cannot make the "wide" run
#    a hidden second capped run — see the trap note above) ────────────────────────────────────────────────
if out=$( verify_exact "for-xml" "$TMP/for_xml_ref" "$TMP/for_xml_cap" xml ); then
    ok "#1 --for XML (--signatures-only): $out"
else
    no "#1 --for XML (--signatures-only): $out"
fi
grep -q 'dropped_positive="[0-9]*"' "$TMP/for_xml_cap" \
    && ok "#1b bare attribute rides the header (no bracket note — shrunk to fit fornotesbudgetcheck's/w3fixbudgetcheck's tight-fixture headroom; docs/EVALS.md A2 entry has the reasoning)" \
    || no "#1b attribute missing entirely"

# ── #2: --for XML, AUTO route (bodies attached) — both sides pass --pack-top-n so forSigSideCeiling takes
#    its "explicit sig posture" branch (verbs_for.h) and honors the full --token-budget on the sig side
#    instead of clamping it to kForPayloadBudgetBytes; without this the "reference" run is itself still
#    capped (the trap recorded in this file's header) and every comparison here would be structurally
#    unable to pass — verify_exact's own ground-truth guard catches that shape rather than silently trusting it.
"$BIN" "$CORPUS" --for="$CONC" --pack-top-n=40 --token-budget=10000000 --no-cache >"$TMP/for_auto_ref" 2>/dev/null
"$BIN" "$CORPUS" --for="$CONC" --pack-top-n=40 --token-budget=1500     --no-cache >"$TMP/for_auto_cap" 2>/dev/null
if out=$( verify_exact "for-auto" "$TMP/for_auto_ref" "$TMP/for_auto_cap" xml ); then
    ok "#2 --for XML (auto route): $out"
else
    no "#2 --for XML (auto route): $out"
fi

# ── #3: --for --json ─────────────────────────────────────────────────────────────────────────────────────
"$BIN" "$CORPUS" --for="$CONC" --json --token-budget=10000000 --no-cache >"$TMP/for_json_ref" 2>/dev/null
"$BIN" "$CORPUS" --for="$CONC" --json --token-budget=1500     --no-cache >"$TMP/for_json_cap" 2>/dev/null
if out=$( verify_exact "for-json" "$TMP/for_json_ref" "$TMP/for_json_cap" json ); then
    ok "#3 --for --json: $out"
else
    no "#3 --for --json: $out"
fi

# ── #4: --pack-task XML ──────────────────────────────────────────────────────────────────────────────────
"$BIN" "$CORPUS" --pack-task="$CONC" --token-budget=10000000 --no-cache >"$TMP/pt_ref" 2>/dev/null
"$BIN" "$CORPUS" --pack-task="$CONC" --token-budget=1200     --no-cache >"$TMP/pt_cap" 2>/dev/null
if out=$( verify_exact "pack-task" "$TMP/pt_ref" "$TMP/pt_cap" xml ); then
    ok "#4 --pack-task XML: $out"
else
    no "#4 --pack-task XML: $out"
fi
grep -q 'dropped_positive="[0-9]*"' "$TMP/pt_cap" && ok "#4b pack-task report clause carries the attribute" \
    || no "#4b pack-task report clause missing the attribute on a shape that should carry it"

# ── #5: no-drop paths carry NO attribute at all (0 bytes — the pr_converged precedent) ─────────────────────
NODROP_QUERIES=( "pageRankDouble" "escapeXml" "cleanSig" "packSignatures" "relevanceFloorCut" )
nodrop_fail=0
for q in "${NODROP_QUERIES[@]}"; do
    for extra in "" "--json"; do
        out=$( "$BIN" "$CORPUS" --for="$q" $extra --no-cache 2>/dev/null )
        case "$out" in
            *dropped_positive*) no "#5 --for=$q $extra unexpectedly carries dropped_positive= (no-drop path must be silent)"; nodrop_fail=1 ;;
        esac
    done
    out=$( "$BIN" "$CORPUS" --pack-task="$q" --no-cache 2>/dev/null )
    case "$out" in
        *dropped_positive*) no "#5 --pack-task=$q unexpectedly carries dropped_positive="; nodrop_fail=1 ;;
    esac
done
[ "$nodrop_fail" = 0 ] && ok "#5 all no-drop shapes (5 queries x for/for-json/pack-task) carry no attribute at all"

# ── #6: MCP for / pack_task parity — same exact count, same no-drop silence ──────────────────────────────
mcp_call(){ printf '%s\n' "$@" | "$BIN" --mcp 2>/dev/null; }
result_text(){ python3 -c '
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    r = json.loads(line)
    if r.get("id") == 2:
        if "error" in r: print("__ERR__:" + json.dumps(r["error"])); sys.exit(0)
        print(r["result"]["content"][0]["text"])
'; }
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize"}'
# RE-DERIVED for round-4 finding F-03. This arm used to run "$CONC" and the MCP verb dropped on it — because
# the MCP `for` verb was being handed the SERVER-WIDE --top-k (default 200) as its lens cap while the CLI
# --for served 40, so its bundle started from a 5x wider head and the ceiling always bit. With the two
# dialects now sharing serialize.h's kForLensDefaultTopN, the MCP bundle for "$CONC" over src/ fits under
# the default budget with nothing dropped, and the old assertion pinned the DEFECT rather than the contract.
# The arm's intent — "the attribute is present when the payload ceiling genuinely bites on the MCP dialect"
# — is unchanged; it needs a query whose 40-symbol head is doc-heavy enough to overflow 7,500 bytes, and
# MCPCONC is that query (measured on src/: MCP dropped_positive="14", CLI "16" on the same head; the two
# dialects differ in the NUMBER dropped because the CLI folds churn=/amp=/tested= onto each row and reserves
# for auto <bodies>, which is exactly why this arm asserts presence and test/mcpforparitycheck.sh asserts the
# candidate POOL both ladders start from).
MCPCONC="resolve call edges by name"
mcp_call "$INIT" "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"for\",\"arguments\":{\"path\":\"$CORPUS\",\"task\":\"$MCPCONC\"}}}" \
    | result_text >"$TMP/mcp_for.xml"
grep -q 'dropped_positive="[0-9]*"' "$TMP/mcp_for.xml" \
    && ok "#6 MCP for verb: dropped_positive= present on a query wide enough to drop" \
    || no "#6 MCP for verb: no dropped_positive= at all (the default MCP budget should trim this broad a query)"
mcp_call "$INIT" "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"for\",\"arguments\":{\"path\":\"$CORPUS\",\"task\":\"pageRankDouble\"}}}" \
    | result_text | grep -q 'dropped_positive=' \
    && no "#6 MCP for verb: dropped_positive= present on a narrow, non-dropping query" \
    || ok "#6 MCP for verb: silent on a narrow query (no drop)"
mcp_call "$INIT" "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"pack_task\",\"arguments\":{\"path\":\"$CORPUS\",\"task\":\"$CONC\",\"budget_tokens\":300}}}" \
    | result_text | grep -q 'dropped_positive="[0-9]*"' \
    && ok "#6 MCP pack_task verb: dropped_positive= present at a tight budget" \
    || no "#6 MCP pack_task verb: no dropped_positive= at a tight budget on a broad query"

# ── #7: well-formedness + determinism on a drop-case shape ─────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/for_xml_cap" 2>/dev/null && xmllint --noout "$TMP/pt_cap" 2>/dev/null \
        && ok "#7 drop-case XML shapes are well-formed (G4)" || no "#7 malformed XML on a drop-case shape"
else
    printf '  SKIP  xmllint (not installed)\n'
fi
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TMP/for_json_cap" 2>/dev/null \
    && ok "#7 drop-case JSON parses" || no "#7 drop-case JSON does not parse"
"$BIN" "$CORPUS" --for="$CONC" --token-budget=1500 --no-cache >"$TMP/d1" 2>/dev/null
"$BIN" "$CORPUS" --for="$CONC" --token-budget=1500 --no-cache >"$TMP/d2" 2>/dev/null
diff -q "$TMP/d1" "$TMP/d2" >/dev/null && ok "#7 drop-case shape deterministic (byte-identical x2)" \
    || no "#7 drop-case shape NON-deterministic"

echo
if [ "$fail" = 0 ]; then
    echo "droppedpositivecheck: ALL PASS"
else
    echo "droppedpositivecheck: FAILURES ABOVE"
fi
exit "$fail"

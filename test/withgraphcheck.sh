#!/usr/bin/env bash
# withgraphcheck.sh — gate for R8: --with-graph — a compact MERMAID
# flowchart of the --for/--pack-task bundle's top-N (<=8) ranked anchors + their 1-hop call edges among
# themselves, appended as <graph fmt="mermaid"><![CDATA[...]]></graph> right before </ctx>.
#
# Covers, per the task's gate spec:
#   • WITHOUT the flag: --for and --pack-task are byte-identical to their pre-feature shape (G5: additive) —
#     2-run self-diff on each, and neither output contains a <graph> block at all.
#   • WITH the flag: well-formed XML (xmllint), the mermaid block parses structurally — "flowchart LR",
#     node count <= 8, the CDATA section is properly closed ("]]></graph>" present, exactly one CDATA open
#     per graph block) — for both --for and --pack-task.
#   • det-gate x2 on the --with-graph output itself (own determinism, not just the flag-off path).
# • §P8: the flag REFUSES on the default map — before this fix it was
#     silently inert there (accepted, byte-identical, no signal), the same failure mode as the other five
#     "(with X)" modifiers that plan audited; cli.h's validateConfig now refuses --with-graph without --for/
#     --pack-task, naming both, exactly like --detail/--adaptive already do for their own companions.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/withgraphcheck.sh
# Exits non-zero on any failure. Does NOT edit regression.sh (the orchestrator's absorb list does that).

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # make BIN absolute BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "withgraphcheck: BIN=$BIN"

CORPUS="$ROOT/src"
Q="signature ranking bundle packSignatures"

# ── 1) WITHOUT the flag: --for / --pack-task are byte-identical run-to-run AND carry no <graph> block ───────
FOR_A="$( "$BIN" "$CORPUS" --no-cache --for="$Q" 2>/dev/null )"
FOR_B="$( "$BIN" "$CORPUS" --no-cache --for="$Q" 2>/dev/null )"
[ "$FOR_A" = "$FOR_B" ] && ok "--for (no flag): 2-run byte-identical" || no "--for (no flag): non-deterministic"
printf '%s' "$FOR_A" | grep -qF '<graph fmt="mermaid"' && no "--for (no flag): unexpectedly emitted a <graph> block" \
    || ok "--for (no flag): no <graph> block emitted (G5: additive, off by default)"

PACK_A="$( "$BIN" "$CORPUS" --no-cache --pack-task="$Q" 2>/dev/null )"
PACK_B="$( "$BIN" "$CORPUS" --no-cache --pack-task="$Q" 2>/dev/null )"
[ "$PACK_A" = "$PACK_B" ] && ok "--pack-task (no flag): 2-run byte-identical" || no "--pack-task (no flag): non-deterministic"
printf '%s' "$PACK_A" | grep -qF '<graph fmt="mermaid"' && no "--pack-task (no flag): unexpectedly emitted a <graph> block" \
    || ok "--pack-task (no flag): no <graph> block emitted (G5: additive, off by default)"

# §P8: --with-graph on the default map (no --for/--pack-task) used to be a SILENT no-op — byte-identical,
# exit 0, no stderr, indistinguishable from a typo'd flag. It now refuses loudly, naming both companions.
"$BIN" "$CORPUS" --no-cache --with-graph >/dev/null 2>"$TMP/withgraph_bare.err"; RC_BARE=$?
{ [ "$RC_BARE" -ne 0 ] && grep -qF -- '--with-graph modifies --for=TASK or --pack-task=TASK' "$TMP/withgraph_bare.err"; } \
    && ok "--with-graph on the default map: refuses loudly (exit $RC_BARE), names --for/--pack-task" \
    || no "--with-graph on the default map: did not refuse cleanly (rc=$RC_BARE): $( cat "$TMP/withgraph_bare.err" )"

# ── 2) WITH the flag: --for ──────────────────────────────────────────────────────────────────────────────
FORG="$TMP/for_graph.xml"
"$BIN" "$CORPUS" --no-cache --for="$Q" --with-graph > "$FORG" 2>/dev/null

xmllint --noout "$FORG" 2>/dev/null && ok "--for --with-graph: xmllint-clean (G4)" || { no "--for --with-graph: NOT well-formed"; xmllint --noout "$FORG" 2>&1 | head -5; }

grep -qF '<graph fmt="mermaid"><![CDATA[' "$FORG" && ok "--for --with-graph: <graph fmt=\"mermaid\"> block present, CDATA opened" \
    || no "--for --with-graph: <graph> block missing or malformed open tag"
grep -qF ']]></graph>' "$FORG" && ok "--for --with-graph: CDATA closed (]]></graph>)" \
    || no "--for --with-graph: CDATA not closed"
grep -qF '</graph></ctx>' "$FORG" && ok "--for --with-graph: <graph> sits immediately before </ctx>" \
    || no "--for --with-graph: <graph> is not the last child before </ctx>"

MERM_FOR="$( perl -0777 -ne 'print $1 if /<graph fmt="mermaid"><!\[CDATA\[(.*?)\]\]><\/graph>/s' "$FORG" )"
printf '%s' "$MERM_FOR" | grep -qF 'flowchart LR' && ok "--for --with-graph: mermaid body starts 'flowchart LR'" \
    || no "--for --with-graph: mermaid body missing 'flowchart LR'"
NODES_FOR="$( printf '%s' "$MERM_FOR" | grep -cE '^n[0-9]+\["' )"
{ [ "$NODES_FOR" -ge 1 ] && [ "$NODES_FOR" -le 8 ]; } \
    && ok "--for --with-graph: node count in [1,8] (got $NODES_FOR)" \
    || no "--for --with-graph: node count out of range (got $NODES_FOR)"
printf '%s' "$MERM_FOR" | grep -qE '^n[0-9]+\[".* \(.*:[0-9]+\)"\]$' \
    && ok "--for --with-graph: node labels look like 'name (file:line)'" \
    || no "--for --with-graph: node label shape wrong"

# ── 3) WITH the flag: --pack-task ────────────────────────────────────────────────────────────────────────
PACKG="$TMP/pack_graph.xml"
"$BIN" "$CORPUS" --no-cache --pack-task="$Q" --with-graph > "$PACKG" 2>/dev/null

xmllint --noout "$PACKG" 2>/dev/null && ok "--pack-task --with-graph: xmllint-clean (G4)" || { no "--pack-task --with-graph: NOT well-formed"; xmllint --noout "$PACKG" 2>&1 | head -5; }

grep -qF '<graph fmt="mermaid"><![CDATA[' "$PACKG" && ok "--pack-task --with-graph: <graph fmt=\"mermaid\"> block present, CDATA opened" \
    || no "--pack-task --with-graph: <graph> block missing or malformed open tag"
grep -qF ']]></graph>' "$PACKG" && ok "--pack-task --with-graph: CDATA closed (]]></graph>)" \
    || no "--pack-task --with-graph: CDATA not closed"
grep -qF '</graph></ctx>' "$PACKG" && ok "--pack-task --with-graph: <graph> sits immediately before </ctx>" \
    || no "--pack-task --with-graph: <graph> is not the last child before </ctx>"

MERM_PACK="$( perl -0777 -ne 'print $1 if /<graph fmt="mermaid"><!\[CDATA\[(.*?)\]\]><\/graph>/s' "$PACKG" )"
printf '%s' "$MERM_PACK" | grep -qF 'flowchart LR' && ok "--pack-task --with-graph: mermaid body starts 'flowchart LR'" \
    || no "--pack-task --with-graph: mermaid body missing 'flowchart LR'"
NODES_PACK="$( printf '%s' "$MERM_PACK" | grep -cE '^n[0-9]+\["' )"
{ [ "$NODES_PACK" -ge 1 ] && [ "$NODES_PACK" -le 8 ]; } \
    && ok "--pack-task --with-graph: node count in [1,8] (got $NODES_PACK)" \
    || no "--pack-task --with-graph: node count out of range (got $NODES_PACK)"

# edges (if any) reference only declared node ids — a structural sanity check, not a graph-theory proof
EDGE_BAD=0
for tgt in $( printf '%s' "$MERM_PACK" | grep -oE '^n[0-9]+ --> n[0-9]+' | sed -E 's/.* --> n([0-9]+)/\1/' ); do
    printf '%s' "$MERM_PACK" | grep -qE "^n${tgt}\[\"" || EDGE_BAD=1
done
[ "$EDGE_BAD" = 0 ] && ok "--pack-task --with-graph: every edge target references a declared node" \
    || no "--pack-task --with-graph: an edge targets an undeclared node id"

# ── 4) det-gate x2 on the --with-graph output itself ─────────────────────────────────────────────────────
D1="$( "$BIN" "$CORPUS" --no-cache --for="$Q" --with-graph 2>/dev/null )"
D2="$( "$BIN" "$CORPUS" --no-cache --for="$Q" --with-graph 2>/dev/null )"
[ "$D1" = "$D2" ] && ok "--for --with-graph: det-gate (2-run byte-identical)" || no "--for --with-graph: non-deterministic"

D3="$( "$BIN" "$CORPUS" --no-cache --pack-task="$Q" --with-graph 2>/dev/null )"
D4="$( "$BIN" "$CORPUS" --no-cache --pack-task="$Q" --with-graph 2>/dev/null )"
[ "$D3" = "$D4" ] && ok "--pack-task --with-graph: det-gate (2-run byte-identical)" || no "--pack-task --with-graph: non-deterministic"

echo
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }

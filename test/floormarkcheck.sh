#!/usr/bin/env bash
# floormarkcheck.sh — the gate for PLAN_h4QualifiedCalls_2026-07-30.md §3.4: the FLOOR MARKER on every
# GRAPH-COUNT surface, in one vocabulary, on every transport, with the retired absolutism provably gone.
#
# THE SURFACE LIST IS THE GATE'S REAL CONTENT, and it grew twice under adversarial review, both times because
# someone enumerated the verbs they remembered: §3.4 named five (--uses / --callers / --callees / --impact /
# --edit-check), V3 found --graph-query counting off the identical CSR with no marker, and V4 found
# --pr-context emitting HUNDREDS of per-symbol callers= attributes with none either. Seven now. A verb that
# reports a number derived from the call graph belongs in this list ON THE DAY it is added — that is the
# §B4 echo-site rule, and this list is the only thing enforcing it.
#
# WHY A SEPARATE FILE AND NOT MORE ARMS IN legendcoveragecheck.sh. That gate is a RATCHET over a baseline
# file: it asks "is any first-screen attribute undefined by its own legend?" and answers with a set
# difference. It is structurally unable to ask the three questions this round needs — (i) does a NAMED
# attribute appear on a NAMED verb, (ii) do the CLI and MCP transports carry the SAME sentence byte for
# byte, (iii) is a retired phrase absent from the tree. Adding those to the ratchet would give one file two
# unrelated failure meanings, and the ratchet's own header warns that a flaky ratchet is one nobody re-pins.
# legendcoveragecheck still covers this change from its own angle (counts_floor= must be DEFINED wherever it
# is emitted); the two gates are complements, and both were run red-first against the pre-marker binary.
#
# WHAT IT ASSERTS
#   (1) PRESENCE — counts_floor="1" on the root element of all SEVEN graph-count surfaces, XML form.
#   (2) DIALECTS — the same marker in --format=columnar (four verbs) and in --json (three verbs), spelled
#       "counts_floor":true there, because JSON spells booleans as booleans (src/pageview.h's PageSyntax
#       table already decided that for the paging half). --uses and --edit-check REFUSE --json today; the
#       gate pins the refusal so "the marker is missing from the JSON --uses" can never be true silently —
#       either there is no JSON form, or it carries the marker.
#   (3) LEGEND — the floor SENTENCE and the counting-unit CLAUSE on all seven first screens, matched on
#       hand-chosen literal anchors (never on a whole paragraph: a wording touch-up must not red this).
#   (4) CLI ≡ MCP — the shared disclosure TAIL is byte-identical between each CLI verb and its MCP twin.
#       This is the round-series' standing law and the §B4 echo-site failure family: a clause that lands on
#       3 of its 5 emitters is the defect, not a partial fix. Compared as BYTES, because that is the only
#       comparison the class cannot slip through.
#   (5) ABSENCE — the retired "every use-site" absolutism appears nowhere: not in src/, not in the shipped
#       --help, not in the seven surfaces' live output, not in README.md or skills/. A greppable absence arm,
#       because the phrase's whole problem was that it was true-sounding and everywhere.
#   (6) G4 — every XML document this gate captures, INCLUDING the MCP payloads, is xmllint-clean. This arm
#       is not decoration: the pre-marker MCP `uses` legend contained the literal "--uses", i.e. a "--"
#       digraph inside an XML comment, which xmllint rejects. No gate looked at the MCP payload's
#       well-formedness before this one, so that shipped.
#   (7) MUTATION — each of the three assertion SHAPES is shown to be able to fail.
#
# RED-FIRST, AND WHAT IT CANNOT COVER. Against build/ctxpack_base (main before this lane) the gate reports
# 50 FAIL / 18 PASS: every arm of (1)(2)(3), six of (4), three of (5), and (6)'s MCP-payload row. The 18
# passes are (7)'s mutants, (2)'s two refusal pins, and the well-formedness of documents that were already
# well-formed. The ONE arm that is structurally NOT binary-sensitive is (5)'s source grep: it reads the
# working tree, so swapping the binary cannot red it. It is a source-absence assertion by design (a phrase
# deleted from a string literal cannot be observed in output that no longer contains it either way), and
# (5)'s three OTHER arms — the shipped --help, the live documents — are binary-sensitive and did go red.
#
# Usage:
#   bash test/floormarkcheck.sh                              # build/ctxpack
#   bash test/floormarkcheck.sh build/ctxpack_base           # the RED run (base binary lacks the marker)
#   CTXPACK_BIN=asan/ctxpack bash test/floormarkcheck.sh
#
# Exits non-zero on any failure. Does NOT edit test/regression.sh or any golden file.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${CTXPACK_BIN:-$ROOT/build/ctxpack}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "floormarkcheck: python3 required"; exit 2; }
cd "$ROOT"
echo "floormarkcheck: BIN=$BIN"

# ── the literals. HAND-CHOSEN by reading src/graphlegend.h, never derived from it (trap #7-1: a gate that
#    computes its expectation the way the code does cannot catch the derivation). Short anchors, so a
#    wording touch-up is a review question and not a red gate; long enough that no other legend contains them.
MARK_XML='counts_floor="1"'
# V5 MED-1: the pr-context marker arms must match the ROOT ELEMENT's attribute, never the legend prose
# (the legend comment also contains the literal counts_floor="1" — the cppqualcheck §9 prose trap).
PR_ROOT_MARK='<pr-context [^>]*counts_floor="1"'
MARK_JSON='"counts_floor":true'
FLOOR_ANCHOR='is a FLOOR, never a total'
FLOOR_CAUSE='most-vexing-parse'
UNIT_ANCHOR='COUNTING UNIT'
# V3 H-1: these two literals REPLACE the single 'DISTINCT (caller,callee) PAIRS' anchor the first version
# pinned. That anchor made the gate green over a sentence that was FALSE for four of the six verbs (only the
# map header's edges= is pair-counted; callers/callees/edit-check/graph-query count distinct SYMBOLS and
# impact counts a reach SET). Pinning both halves is what stops the unit claim from silently collapsing back
# onto one word: UNIT_SYMBOL is the claim the emitters implement, UNIT_SITE is the contrast that makes it
# useful. The pair-count fact survives only where it is true — see UNIT_MAP below.
UNIT_SYMBOL='counts are DISTINCT SYMBOLS'
UNIT_SITE='counts call SITES'
UNIT_REACH='the size of a transitive reach SET'
# V4 MED-3: pr-context is the seventh surface, and its two units are the two already named — per-symbol
# callers= is a distinct-SYMBOL count off the same in-edge CSR, dependents= is a reach SET. Pinned as a
# literal so the shared clause cannot quietly stop naming the verb whose document carries it most often.
UNIT_PRCONTEXT='graph-query and pr-context counts are DISTINCT SYMBOLS'
UNIT_DEPENDENTS="pr-context's dependents="
UNIT_MAP='distinct (caller,callee) PAIRS'
RETIRED='every use-site'

# The probe symbols: real, stable, and each one exercises the verb it is passed to on this tree.
SYM=pageWindow             # 24 callers in src/, a def in src/pageview.h
SYMC=pageDisclosure        # has callees

# ── capture helper. `$2...` are the verb args; the document lands in $TMP/$1. ──────────────────────────
cap(){ local name="$1"; shift; "$BIN" "$@" >"$TMP/$name" 2>"$TMP/$name.err"; }

# MCP: one tools/call, payload text extracted from the last JSON-RPC line (the mcpclidiffcheck pattern).
mcp_text(){
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        "$( printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"%s","arguments":%s}}' "$1" "$2" )" \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__:" + r["error"].get("message","") if "error" in r else r["result"]["content"][0]["text"], end="")
'
}

# leadComment FILE — the LEADING XML comment block, i.e. the legend a reader meets first. Same shape
# legendcoveragecheck's legendOf() uses, kept independent on purpose (two gates deriving the legend the same
# way through a shared helper would fail together on a shared mistake).
leadComment(){ python3 -c '
import re, sys
t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.match(r"\A(?:\s*<!--.*?-->)+", t, re.S)
sys.stdout.write(m.group(0) if m else "")
' "$1"; }

echo
echo "=== (1) PRESENCE — the marker on all SEVEN graph-count roots, XML form ==="
cap callers.xml     src --callers="$SYM"
cap callees.xml     src --callees="$SYMC"
cap uses.xml        src --uses="$SYM"
cap impact.xml      src --impact="$SYM"
cap editcheck.xml   .   --edit-check="$SYM"
# V3 M-1: --graph-query is the SIXTH surface counting off the identical graph — `callers(name("X"),1)`
# reports the same number --callers does — and it shipped with neither the marker nor either sentence.
# Enumerated here BY NAME, because the §B4 echo-site class is exactly "the clause landed on the surfaces
# someone remembered". If a seventh graph-count verb is added, it belongs in this list on the same day.
cap graphquery.xml  src --graph-query="callers(name(\"$SYM\"),1)"
# V4 MED-3: the SEVENTH. --pr-context emits hundreds of per-symbol callers= attributes read from the same
# in-edge CSR --callers reads, plus <impact dependents=> reach counts, and shipped with no marker at all.
# Pinned to HEAD~1 for the same reason legendcoveragecheck's roster is: the bare working-tree form's element
# set depends on whether the agent running the suite has uncommitted edits, which is a flake.
cap prcontext.xml   .   --pr-context=HEAD~1

for v in callers callees uses impact editcheck graphquery prcontext; do
    ROOTTAG="$( grep -o "<[a-z-]*[^>]*$MARK_XML[^>]*>" "$TMP/$v.xml" | head -1 )"
    if [ -n "$ROOTTAG" ]; then ok "(1) $v root carries $MARK_XML"
    else no "(1) $v root has NO $MARK_XML: $( grep -oE '<(callers|callees|uses|impact|edit-check|query|pr-context) [^>]*' "$TMP/$v.xml" | head -1 )"; fi
done
# pr-context's callers= attributes must be the SAME numbers --callers reports, or the shared clause is
# describing a different graph than the one the document counts off.
PRSYM="$( grep -oE '<s [^>]*n="graphCountDisclosure"[^>]*callers="[0-9]+"' "$TMP/prcontext.xml" | grep -oE 'callers="[0-9]+"' | head -1 )"
if [ -n "$PRSYM" ]; then
    CLN="$( "$BIN" . --callers=graphCountDisclosure 2>/dev/null | grep -o 'count="[0-9]*"' | head -1 | tr -dc '0-9' )"
    [ "$PRSYM" = "callers=\"$CLN\"" ] \
        && ok "(1) pr-context per-symbol $PRSYM equals the --callers count ($CLN) — one graph, one floor" \
        || no "(1) pr-context says $PRSYM but --callers says count=\"$CLN\" — the shared clause describes a graph this document is not counting off"
else
    ok "(1) pr-context: no probe symbol in this diff — the cross-check is shape-dependent and skipped (the marker arm above still asserted)"
fi
# --graph-query must agree with --callers on the SAME question: same graph, same number, same marker.
GQC="$( grep -o 'count="[0-9]*"' "$TMP/graphquery.xml" | head -1 )"
CLC="$( grep -o 'count="[0-9]*"' "$TMP/callers.xml"    | head -1 )"
[ -n "$GQC" ] && [ "$GQC" = "$CLC" ] \
    && ok "(1) graph-query callers(name(SYM),1) reports the same $GQC as --callers — one graph, one floor" \
    || no "(1) graph-query ($GQC) and --callers ($CLC) disagree on the same question — the probe no longer proves they share a graph"

echo
echo "=== (2) DIALECTS — columnar and json carry the same marker (or there is no such form) ==="
for v in callers callees uses impact; do
    case "$v" in callers) A="--callers=$SYM";; callees) A="--callees=$SYMC";; uses) A="--uses=$SYM";; *) A="--impact=$SYM";; esac
    cap "$v.col" src "$A" --format=columnar
    grep -q "$MARK_XML" "$TMP/$v.col" \
        && ok "(2) $v --format=columnar carries $MARK_XML" \
        || no "(2) $v --format=columnar is MISSING $MARK_XML — a dialect that drops the marker is the dialect-divergence class"
done
for v in callers callees impact; do
    case "$v" in callers) A="--callers=$SYM";; callees) A="--callees=$SYMC";; *) A="--impact=$SYM";; esac
    cap "$v.json" src "$A" --json
    python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if d.get("counts_floor") is True else 1)
' "$TMP/$v.json" \
        && ok "(2) $v --json carries counts_floor:true (a JSON boolean, not the string \"1\")" \
        || no "(2) $v --json has no counts_floor:true key: $( head -c 200 "$TMP/$v.json" )"
done
# --uses / --edit-check have no JSON form. PINNED, so "the marker is missing there" can never be silently
# true: either the refusal stands, or a JSON form was added and this arm demands the marker with it.
for spec in "uses:--uses=$SYM" "edit-check:--edit-check=$SYM"; do
    v="${spec%%:*}"; A="${spec#*:}"
    OUT="$( "$BIN" . "$A" --json 2>&1 >/dev/null )"
    case "$OUT" in
        *"--json is not yet supported"*) ok "(2) $v has no JSON dialect (refused, as documented) — nothing to carry the marker" ;;
        *) no "(2) $v now ACCEPTS --json — that new dialect must carry $MARK_JSON; add the arm. stderr: $( printf '%s' "$OUT" | head -c 160 )" ;;
    esac
done

echo
echo "=== (3) LEGEND — the floor sentence + counting-unit clause on all seven first screens ==="
for v in callers callees uses impact editcheck graphquery prcontext; do
    L="$( leadComment "$TMP/$v.xml" )"
    for anchor in "$MARK_XML" "$FLOOR_ANCHOR" "$FLOOR_CAUSE" "$UNIT_ANCHOR" "$UNIT_SYMBOL" "$UNIT_SITE" "$UNIT_REACH" \
                  "$UNIT_PRCONTEXT" "$UNIT_DEPENDENTS"; do
        case "$L" in
            *"$anchor"*) ok "(3) $v legend states: $anchor" ;;
            *)           no "(3) $v legend does NOT state: $anchor" ;;
        esac
    done
done

# (3b) V3 H-1's ACTUAL defect, gated as a defect and not just as a wording: the first version's unit claim
# CONTRADICTED the callers/callees opener printed 300 bytes earlier in the SAME comment, and both greens sat
# in one document. So the contradiction is asserted directly — the pair-count fact may appear ONLY as a
# statement about the map header's edges=, never as a description of these verbs' own rows.
for v in callers callees editcheck graphquery prcontext; do
    L="$( leadComment "$TMP/$v.xml" )"
    ROWCLAIM="$( printf '%s' "$L" | grep -c "$UNIT_SYMBOL" || true )"
    MAPCLAIM="$( printf '%s' "$L" | grep -c "map header's edges= is a unit again different — $UNIT_MAP" || true )"
    if [ "$ROWCLAIM" != "0" ] && [ "$MAPCLAIM" != "0" ]; then
        ok "(3b) $v: the rows are called distinct SYMBOLS and the PAIR count is attributed to the map header only — the two sentences agree"
    else
        no "(3b) $v: rows-are-symbols=$ROWCLAIM map-owns-the-pair-count=$MAPCLAIM — the unit claim contradicts the opener in the same comment (V3 H-1)"
    fi
done
# and the verb whose unit is NEITHER: impact counts a reach SET, so a rows-are-symbols claim would be wrong there too.
case "$( leadComment "$TMP/impact.xml" )" in
    *"$UNIT_REACH"*) ok "(3b) impact: its unit is named as the transitive reach SET, not rows and not pairs" ;;
    *)               no "(3b) impact: the reach-SET unit is not stated" ;;
esac

echo
echo "=== (4) CLI ≡ MCP — the shared disclosure tail is byte-identical across transports ==="
# tail FILE — everything from the floor anchor's sentence start to the end of the leading comment. That is
# exactly the shared constant's contribution, isolated from each surface's own (legitimately different) body.
sharedTail(){ python3 -c '
import re, sys
t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.match(r"\A(?:\s*<!--.*?-->)+", t, re.S)
lead = m.group(0) if m else ""
i = lead.find("counts_floor=")
sys.stdout.write(lead[i:] if i >= 0 else "__NOTAIL__")
' "$1"; }

SRC="$ROOT/src"
mcp_text uses    "{\"path\":\"$SRC\",\"symbol\":\"$SYM\"}"  >"$TMP/mcp_uses.xml"
mcp_text impact  "{\"path\":\"$SRC\",\"symbol\":\"$SYM\"}"  >"$TMP/mcp_impact.xml"
mcp_text edit_check "{\"path\":\"$ROOT\",\"symbol\":\"$SYM\"}" >"$TMP/mcp_editcheck.xml"

for pair in "uses:uses" "impact:impact" "editcheck:editcheck"; do
    c="${pair%%:*}"; m="${pair#*:}"
    A="$( sharedTail "$TMP/$c.xml" )"; B="$( sharedTail "$TMP/mcp_$m.xml" )"
    if [ "$A" = "__NOTAIL__" ] || [ -z "$A" ]; then
        no "(4) $c: the CLI probe produced no shared tail — the probe is broken, fix it before trusting this row"
    elif [ "$A" = "$B" ]; then
        ok "(4) $c: CLI and MCP legends carry a byte-identical disclosure tail ($( printf '%s' "$A" | wc -c | tr -d ' ' ) B)"
    else
        no "(4) $c: CLI and MCP disclosure tails DIFFER — the §B4 echo-site class. CLI[${#A}B] vs MCP[${#B}B]"
    fi
    grep -q "$MARK_XML" "$TMP/mcp_$m.xml" \
        && ok "(4) MCP $m payload root carries $MARK_XML" \
        || no "(4) MCP $m payload has no $MARK_XML"
done
# --impact's WHOLE legend is shared now, not just the tail: the two used to differ in the paging clause too.
if cmp -s <( leadComment "$TMP/impact.xml" ) <( leadComment "$TMP/mcp_impact.xml" ); then
    ok "(4) impact: the ENTIRE legend is byte-identical CLI vs MCP"
else
    no "(4) impact: the CLI and MCP legends are not byte-identical (they share the tail but diverge elsewhere)"
fi
# the callers/callees MCP twins are JSON-only (find_symbol / find_referencing_symbols): the marker must
# reach them as the key, since there is no comment node to carry the sentence.
for spec in "find_symbol:calls+calledBy" "find_referencing_symbols:calledBy"; do
    verb="${spec%%:*}"
    mcp_text "$verb" "{\"path\":\"$SRC\",\"symbol\":\"$SYM\"}" >"$TMP/mcp_$verb.json"
    python3 -c '
import json, sys
d = json.loads(open(sys.argv[1]).read())
sys.exit(0 if d.get("counts_floor") is True else 1)
' "$TMP/mcp_$verb.json" \
        && ok "(4) MCP $verb (the callers/callees twin) carries counts_floor:true" \
        || no "(4) MCP $verb has no counts_floor:true — the callers/callees marker did not reach the MCP transport"
done

echo
echo "=== (5) ABSENCE — the retired absolutism is gone from every surface ==="
# src/ is filtered to NON-COMMENT lines. The rule the round actually wants is "no string the tool EMITS
# says it", and a C++ comment recording that the promise was retired — which three files now carry, because
# the fix is only legible with the old wording quoted — is documentation, not a claim to a user. Comments
# are `//`-led or inside a `/* */` block in this tree's style, so the leading-token filter is exact for it.
# README.md and skills/ get NO exemption: every line there is prose a reader meets.
# CASE-INSENSITIVE (-i), and that is not a nicety. The first version of this arm was case-SENSITIVE and the
# very defect V3 M-5 reported — test/showcase_capture.py's "Every use-site (call/read/write/import/extends)"
# — sails straight past `grep "every use-site"` because the sentence starts a caption. Adding the file to the
# sweep without this flag would have produced a green gate over the exact line it was added to catch,
# measured live during this fix.
HITS="$( grep -rni "$RETIRED" "$ROOT/src" 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*|/\*)' || true )"
HITS="$HITS$( grep -rni "$RETIRED" "$ROOT/README.md" "$ROOT/skills" 2>/dev/null || true )"
# V3 M-5: the GENERATOR, and only the generator. test/showcase_capture.py:100 authored the retired phrase
# into every capture it produces, so the next regeneration would have reintroduced the absolutism into a
# shipped document with this gate green — the sweep read src/, README.md and skills/ and never test/.
# Scoped to this ONE file rather than all of test/ on purpose: gates legitimately quote retired wording in
# their justification comments (this file does), and a blanket test/ sweep would forbid explaining a fix.
HITS="$HITS$( grep -ni "$RETIRED" "$ROOT/test/showcase_capture.py" 2>/dev/null | sed 's|^|test/showcase_capture.py:|' || true )"
[ -z "$HITS" ] \
    && ok "(5) the phrase \"$RETIRED\" appears in no emitted string in src/, and nowhere at all in README.md or skills/" \
    || { no "(5) the retired phrase \"$RETIRED\" is still in the tree:"; printf '%s\n' "$HITS" | sed 's/^/          /' | head -8; }
"$BIN" --help >"$TMP/help.txt" 2>&1
grep -qi "$RETIRED" "$TMP/help.txt" \
    && no "(5) --help still promises \"$RETIRED\"" \
    || ok "(5) --help does not promise \"$RETIRED\""
grep -q "$MARK_XML" "$TMP/help.txt" \
    && ok "(5) --help documents $MARK_XML (the marker a reader meets in the output is explained in the manual too)" \
    || no "(5) --help never mentions $MARK_XML"
LIVE="$( cat "$TMP/callers.xml" "$TMP/callees.xml" "$TMP/uses.xml" "$TMP/impact.xml" "$TMP/editcheck.xml" \
              "$TMP/graphquery.xml" "$TMP/prcontext.xml" "$TMP/mcp_uses.xml" "$TMP/mcp_impact.xml" 2>/dev/null | grep -ci "$RETIRED" || true )"
[ "$LIVE" = "0" ] \
    && ok "(5) no captured document (CLI or MCP) contains \"$RETIRED\"" \
    || no "(5) $LIVE captured document(s) still say \"$RETIRED\""

echo
echo "=== (6) G4 — every captured XML document is well-formed, MCP payloads included ==="
# V3 H-3: a MISSING xmllint is a FAIL, not a PASS. The first version printed a green line for a check that
# did not run, which is the exact shape argvdiffcheck's own header legislates against ("a gate that cannot
# run must say so rather than pretend to pass") — and it is worse here than anywhere, because this arm is the
# only thing in the tree that validates an MCP payload, and it is what caught the "--" digraph the pre-marker
# MCP uses legend shipped. A silent skip would have re-hidden exactly that.
if ! command -v xmllint >/dev/null 2>&1; then
    no "(6) xmllint is NOT INSTALLED — the G4 arm could not run, so this gate cannot claim well-formedness (install libxml2's xmllint; this arm is the tree's only MCP-payload validator)"
else
    for f in callers.xml callees.xml uses.xml impact.xml editcheck.xml graphquery.xml prcontext.xml \
             callers.col callees.col uses.col impact.col \
             mcp_uses.xml mcp_impact.xml mcp_editcheck.xml; do
        [ -s "$TMP/$f" ] || { no "(6) $f is empty — nothing was validated"; continue; }
        xmllint --noout "$TMP/$f" 2>"$TMP/xl.err" \
            && ok "(6) $f is well-formed" \
            || { no "(6) $f FAILED xmllint: $( head -1 "$TMP/xl.err" )"; }
    done
fi

echo
echo "=== (8) BUDGET FLAGS — a byte budget on these verbs is honoured or REFUSED, never silently ignored ==="
# V3 M-4. This lane's own byte-cost claim was a half-truth: --max-tokens is refused by the five paging surfaces, but
# --token-budget was ACCEPTED at exit 0 with an empty stderr and the full document emitted, while the default
# map on the same flag refuses rc=3 with a withheld_est_tokens= body. Accepted-and-ignored is a named failure
# family, and it bites hardest on the flag a caller reaches for to bound the disclosure this lane added.
for spec in "callers:--callers=$SYM" "callees:--callees=$SYMC" "uses:--uses=$SYM" "impact:--impact=$SYM" \
            "graph-query:--graph-query=callers(name(\"$SYM\"),1)"; do
    v="${spec%%:*}"; A="${spec#*:}"
    for flag in --token-budget=200 --max-tokens=200; do
        ERR="$( "$BIN" src "$A" "$flag" 2>&1 >/dev/null )"; rc=$?
        if [ "$rc" != 0 ] && [ -n "$ERR" ]; then
            ok "(8) $v $flag: refused loudly (rc=$rc, message present)"
        else
            no "(8) $v $flag: rc=$rc with $( printf '%s' "$ERR" | wc -c | tr -d ' ' ) B of stderr — accepted-and-ignored"
        fi
    done
done
# --edit-check sits OUTSIDE the --limit/--offset family, so it takes the §B9.2 NOTICE instead of a refusal.
# That asymmetry is DELIBERATE (R12: disclose, do not refuse, out here — refusing would break
# `--for=X --max-tokens=5000`), so the gate pins the notice rather than demanding a refusal it should not get.
for flag in --token-budget=200 --max-tokens=200; do
    ERR="$( "$BIN" . --edit-check="$SYM" "$flag" 2>&1 >/dev/null )"; rc=$?
    OUT="$( "$BIN" . --edit-check="$SYM" "$flag" 2>/dev/null | wc -c | tr -d ' ' )"
    case "$rc:$ERR" in
        0:*"is not read by --edit-check"*)
            [ "$OUT" -gt 0 ] \
                && ok "(8) edit-check $flag: warns and emits ($OUT B, rc=0) — the deliberate outside-the-family shape" \
                || no "(8) edit-check $flag: warned but emitted nothing" ;;
        *)  no "(8) edit-check $flag: rc=$rc and no 'is not read by' notice — it is silently ignoring the flag: $( printf '%s' "$ERR" | head -c 120 )" ;;
    esac
done
# V4 MED-3, the byte half. --pr-context is the ONE marked surface that HONOURS --max-tokens (it is in the
# honoring set the M-4 work above derived from the read sites), so its marker bytes are not free the way the
# refusing six's are: they land inside a document a budget shapes. Trap #8 says every byte added to a
# budgeted document must be charged — so the budget must still BIND (the trimmed document is materially
# smaller) and the ladder must still disclose its cut. A marker that pushed a bundle past its own ceiling,
# or that rode in uncharged, would both show here.
# WHAT IS ASSERTED, AND WHY IT IS NOT A RAW BYTE ALLOWANCE. Writing this arm against
# `bytes <= tokens x kMinBytesPerToken` immediately red-flagged --pr-context at 8000/1500/600 — and the SAME
# rows are over on the PRE-MARKER binary (19487/5959/5980 B against 18880/3540/1416), so the raw form would
# have blamed this lane for a floor that predates it. Two different things live in that overshoot, and only
# one is assertable here:
#   * the DISCLOSED floor — the ladder cannot go below a structural minimum and says so with
#     truncated="…;budget-floor-exceeded". Honest; accepted below.
#   * an UNDISCLOSED under-charge — at --max-tokens=1500 the verb reports est_tokens="1400", believes it fits,
#     and emits ~7.3 KB (~3100 tokens at 2.36 B/tok). That is the §H7 uncharged-payload class on a verb
#     estchargecheck does not cover, it reproduces IDENTICALLY on the pre-marker binary (5959 B under the same
#     1400-token claim), and it is not this lane's to fix — fixing an estimator moves every pr-context budget
#     shape and wants its own round. Recorded as INFO with the live ratio so it cannot stay invisible, and
#     reported up rather than asserted, because a gate that fails on another lane's debt is a gate that gets
#     disabled.
# So the assertions are the verb's OWN contract (fit your estimate, or say you could not) plus the one claim
# this lane is answerable for: the budget the ladder CAN meet must still be met with the marker in it.
PRFULL="$( "$BIN" . --pr-context=HEAD~1 2>/dev/null | wc -c | tr -d ' ' )"
for t in 4000 1500 600; do
    OUTF="$TMP/pr_$t.xml"
    "$BIN" . --pr-context=HEAD~1 --max-tokens="$t" >"$OUTF" 2>/dev/null
    B="$( wc -c <"$OUTF" | tr -d ' ' )"
    EST="$( grep -oE 'est_tokens="[0-9]+"' "$OUTF" | head -1 | tr -dc '0-9' )"
    if [ -n "$EST" ] && [ "$EST" -le "$t" ]; then
        ok "(8) pr-context --max-tokens=$t: est_tokens=$EST is inside the $t budget (the verb's own fit contract holds)"
    elif grep -q 'budget-floor-exceeded' "$OUTF"; then
        ok "(8) pr-context --max-tokens=$t: cannot reach the budget and SAYS so (budget-floor-exceeded) — a disclosed floor, not a silent breach"
    else
        no "(8) pr-context --max-tokens=$t: est_tokens=${EST:-<none>} over the $t budget with NO budget-floor-exceeded — silently over its own ceiling"
    fi
    ALLOW=$(( t * 236 / 100 ))
    [ "$B" -gt "$ALLOW" ] && printf '  ..    (8) INFO pr-context --max-tokens=%s emits %s B against a %s B allowance (est_tokens=%s) — the pre-existing §H7 under-charge on this verb, identical in kind on the pre-marker binary; not asserted, reported\n' "$t" "$B" "$ALLOW" "${EST:-?}"
done
# NO ABSOLUTE BYTE PIN HERE, and that is a correction to this arm's first draft. It asserted
# `--max-tokens=4000 <= 9440 B` to pin "the marker did not push a meetable budget over"; the number held
# when written and RED two commits later, because --pr-context's document is a function of the diff and
# HEAD~1 means something different after every commit. An assertion that reds because the tree moved is the
# flake the ratchet gates warn about, and it would have been blamed on the marker. The bounded claim it was
# reaching for lives in the commit message as a MEASUREMENT (at a fixed tree, 4000 went 6259 -> 7629 B,
# both inside 9440); what the gate asserts is the content-independent property instead: the verb's own fit
# contract at every budget (the loop above) and the marker surviving to the tightest one (below).
printf '  ..    (8) INFO pr-context --max-tokens=4000 emits %s B (diff-dependent, deliberately not pinned)\n' \
       "$( wc -c <"$TMP/pr_4000.xml" | tr -d ' ' )"
# the marker survives whatever the live tree's budget does — cheap, content-independent, kept as-is.
"$BIN" . --pr-context=HEAD~1 --max-tokens=600 2>/dev/null | grep -qE "$PR_ROOT_MARK" \
    && ok "(8) pr-context keeps $MARK_XML ON THE ROOT under a tight budget on the live tree" \
    || no "(8) pr-context DROPPED $MARK_XML from the root under --max-tokens=600 — a budget must not silently buy back the false claim"

# ── (8f) THE SHRINK HALF, on a DETERMINISTIC FIXTURE REPO ──────────────────────────────────────────────
# This assertion — "the budget actually BINDS, so the arms above are not vacuous" — is the one part of (8)
# that needs a document big enough to trim, and it is therefore the one part that must not read the LIVE
# repo. It did, against `--pr-context=HEAD~1`, and the 310-gate suite caught it: after a run of doc-only
# commits HEAD~1's diff was ONE file, the whole bundle came to 4900 B / est_tokens=422 — comfortably inside
# a 600 budget — so nothing trimmed, the budgeted form came out LARGER than the un-budgeted one (it adds the
# budget disclosure attributes), and the arm reported its own inertness as a FAIL. Correct detection, wrong
# verdict, and the SECOND time this lane hit the class the byte-pin already taught it: --pr-context's
# document is a function of the diff, so nothing about its SIZE may be asserted against a live tree.
#
# The fixture is mergechurchcheck's convention: a throwaway git repo built in $TMP with a synthetic
# multi-file diff whose size is a property of this script, not of the repo it happens to run in. 14 modules
# x 4 functions, every one of them calling into a shared core, all 14 changed in the second commit — so the
# bundle carries 14 <file> sections with real callers=/impact= nested lists and cannot fit 600 tokens on any
# tree, any day, forever. Deterministic: fixed content, fixed identity/date env, no network, no user config.
if ! command -v git >/dev/null 2>&1; then
    no "(8f) git is NOT INSTALLED — the shrink half could not run, so this gate cannot claim the budget binds"
else
    FIX="$TMP/prfix"
    mkdir -p "$FIX/src"
    {
        echo "#pragma once"
        for f in Alpha Beta Gamma Delta Epsilon Zeta; do echo "int core$f( int x );"; done
    } > "$FIX/src/core.h"
    {
        echo '#include "core.h"'
        for f in Alpha Beta Gamma Delta Epsilon Zeta; do echo "int core$f( int x ) { return x + 1; }"; done
    } > "$FIX/src/core.cpp"
    m=1
    while [ "$m" -le 14 ]; do
        {
            echo '#include "core.h"'
            echo "int mod${m}One( int x )   { return coreAlpha( x ) + coreBeta( x ); }"
            echo "int mod${m}Two( int x )   { return mod${m}One( x ) + coreGamma( x ); }"
            echo "int mod${m}Three( int x ) { return mod${m}Two( x ) + mod${m}One( x ) + coreDelta( x ); }"
        } > "$FIX/src/mod$m.cpp"
        m=$(( m + 1 ))
    done
    (
        cd "$FIX" || exit 1
        export GIT_AUTHOR_NAME=floormark GIT_AUTHOR_EMAIL=floormark@example.invalid
        export GIT_COMMITTER_NAME=floormark GIT_COMMITTER_EMAIL=floormark@example.invalid
        export GIT_AUTHOR_DATE="2026-01-01T00:00:00+0000" GIT_COMMITTER_DATE="2026-01-01T00:00:00+0000"
        git init -q . >/dev/null 2>&1
        git add -A >/dev/null 2>&1
        git -c commit.gpgsign=false commit -q -m "base" >/dev/null 2>&1
        # the CHANGED half: every module gains a fourth function, so all 14 files are in the diff and each
        # carries indexed symbols with callers — the shape --pr-context has the most to say about.
        m=1
        while [ "$m" -le 14 ]; do
            echo "int mod${m}Four( int x )  { return mod${m}Three( x ) + coreEpsilon( x ) + coreZeta( x ); }" >> "src/mod$m.cpp"
            m=$(( m + 1 ))
        done
        git add -A >/dev/null 2>&1
        git -c commit.gpgsign=false commit -q -m "widen every module" >/dev/null 2>&1
    )
    FIXFULL="$( "$BIN" "$FIX" --pr-context=HEAD~1 2>/dev/null | wc -c | tr -d ' ' )"
    "$BIN" "$FIX" --pr-context=HEAD~1 --max-tokens=600 >"$TMP/fix600.xml" 2>/dev/null
    FIX600="$( wc -c <"$TMP/fix600.xml" | tr -d ' ' )"
    FIXFILES="$( grep -oE '<pr-context [^>]*files="[0-9]+"' "$TMP/fix600.xml" | grep -oE 'files="[0-9]+"' | head -1 )"

    # (i) the fixture must actually be the big multi-file diff this script built — if the repo failed to
    #     construct, every assertion below would pass or fail for reasons that have nothing to do with the
    #     budget. Checked FIRST, and loudly: a broken fixture is a broken gate, not a green one.
    if [ "$FIXFILES" = 'files="14"' ] && [ "$FIXFULL" -gt 20000 ]; then
        ok "(8f) fixture repo built: 14 changed files, ${FIXFULL} B un-budgeted — a document a 600-token budget MUST trim"
    else
        no "(8f) fixture repo did NOT build as specified (${FIXFILES:-<no root>}, ${FIXFULL} B) — the shrink assertion below would prove nothing"
    fi
    # (ii) the assertion the live tree could not carry: the budget BINDS.
    [ "$FIX600" -lt "$FIXFULL" ] \
        && ok "(8f) pr-context --max-tokens BINDS on the fixture: ${FIXFULL} B -> ${FIX600} B" \
        || no "(8f) pr-context --max-tokens did not shrink the fixture's ${FIXFULL} B document — the allowance arms are inert and prove nothing"
    # (iii) and it says what it cut. A trim that shrinks silently is the §P8 class this whole round is about.
    grep -qE 'trim_level="[1-9]' "$TMP/fix600.xml" && ! grep -q 'truncated="none"' "$TMP/fix600.xml" \
        && ok "(8f) the fixture's trim DISCLOSES itself ($( grep -oE 'trim_level="[0-9]+"' "$TMP/fix600.xml" | head -1 ), truncated= names the cut)" \
        || no "(8f) the fixture shrank but reports trim_level=0 / truncated=\"none\" — a silent cut"
    # (iv) the marker survives a REAL deep trim, which is what the live-tree copy of this check could not
    #      prove on a diff that never trimmed.
    grep -qE "$PR_ROOT_MARK" "$TMP/fix600.xml" \
        && ok "(8f) $MARK_XML survives a real deep trim ON THE ROOT — a budget must not silently buy back the false claim" \
        || no "(8f) pr-context DROPPED $MARK_XML from the root on the trimmed fixture"
    # (v) the §H7 under-charge INFO, re-measured on the fixture so the class is visible on a shape that
    #     genuinely trims (the live-tree INFO above is measured on whatever the day's diff happens to be).
    FIXEST="$( grep -oE 'est_tokens="[0-9]+"' "$TMP/fix600.xml" | head -1 | tr -dc '0-9' )"
    FIXALLOW=$(( 600 * 236 / 100 ))
    [ "$FIX600" -gt "$FIXALLOW" ] \
        && printf '  ..    (8f) INFO fixture --max-tokens=600 emits %s B against a %s B allowance (est_tokens=%s) — the same pre-existing §H7 under-charge, now on a deterministic shape\n' \
                  "$FIX600" "$FIXALLOW" "${FIXEST:-?}" \
        || printf '  ..    (8f) INFO fixture --max-tokens=600 emits %s B, inside the %s B allowance (est_tokens=%s)\n' \
                  "$FIX600" "$FIXALLOW" "${FIXEST:-?}"
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$TMP/fix600.xml" && ok "(8f) the trimmed fixture bundle is well-formed" \
                                          || no "(8f) the trimmed fixture bundle failed xmllint"
    fi
fi

# and the honouring side must still honour, or the refusals above are just a blanket ban.
"$BIN" src --token-budget=50 >/dev/null 2>"$TMP/tb.err"; rc=$?
[ "$rc" != 0 ] && grep -q 'withheld_est_tokens' "$TMP/tb.err" \
    && ok "(8) the default map still GATES on --token-budget (rc=$rc, withheld_est_tokens named)" \
    || no "(8) the default map no longer gates on --token-budget (rc=$rc) — the refusals above would then be a blanket ban, not a boundary"

echo
echo "=== (7) MUTATION — each assertion shape can actually fail ==="
printf '<callers of="x" count="3">' >"$TMP/mut_root.xml"
grep -q "$MARK_XML" "$TMP/mut_root.xml" \
    && no "(7) the presence assertion cannot see a root WITHOUT the marker" \
    || ok "(7) presence: a marker-less root IS detected"
printf '<!-- ctxpack callers: nothing disclosed --><callers/>' >"$TMP/mut_leg.xml"
case "$( leadComment "$TMP/mut_leg.xml" )" in
    *"$FLOOR_ANCHOR"*) no "(7) the legend assertion matches a legend that lacks the sentence" ;;
    *)                 ok "(7) legend: a legend without the floor sentence IS detected" ;;
esac
printf '<!-- x counts_floor="1" DIFFERENT -->' >"$TMP/mut_tail.xml"
[ "$( sharedTail "$TMP/mut_tail.xml" )" = "$( sharedTail "$TMP/uses.xml" )" ] \
    && no "(7) the CLI≡MCP comparison cannot see two different tails" \
    || ok "(7) transport equality: two different tails ARE detected"
# the absence arm's mutant is a CODE line, not a comment line — the exemption above must not swallow the
# defect it is meant to let through. Both halves are exercised: the emitted-string form must be caught, the
# comment form must not.
# The emitted mutant is CAPITALISED on purpose: "Every use-site …" is the spelling V3 M-5 actually found in
# test/showcase_capture.py, and it is the spelling a case-sensitive sweep misses. Measured during this fix —
# the arm was added to catch that line and, until -i went on, passed over it.
printf 'src/x.h:1:    std::printf( "Every use-site of SYM" );\n' >"$TMP/mut_abs.txt"
printf 'src/x.h:2:    // it used to say every use-site of SYM\n' >>"$TMP/mut_abs.txt"
KEPT="$( grep -i "$RETIRED" "$TMP/mut_abs.txt" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*|/\*)' )"
case "$KEPT" in
    *'std::printf'*) case "$KEPT" in
                         *'// it used to say'*) no "(7) the comment exemption is not filtering — it would fail on documentation" ;;
                         *)                     ok "(7) absence: a reintroduced EMITTED \"$RETIRED\" IS detected, a comment about it is not" ;;
                     esac ;;
    *) no "(7) the absence grep cannot see the emitted phrase it forbids" ;;
esac

echo
[ "$fail" -eq 0 ] && { echo "floormarkcheck: ALL PASS"; exit 0; }
echo "floormarkcheck: FAILURES"; exit 1

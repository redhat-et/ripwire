#!/usr/bin/env bash
# mcpforparitycheck.sh — round-4 finding F-03: the MCP `for` verb and the CLI `--for` lens must serve the
# SAME ranked candidate pool under defaults.
#
# WHAT BROKE. `forTaskText` (src/mcpverbs.h) took an `int topK` and both of its call sites — the `for`
# dispatch arm in src/mcp.h and the `batch` sub-verb — fed it the SERVER-WIDE `--top-k`, whose default is
# 200. That is the ranked MAP's row cap; the --for lens is documented to IGNORE it (cli.h honorsTopK, and
# --help's own --top-k paragraph), and the CLI lens accordingly caps its head at 40. So every MCP `for` call
# an agent could make ranked a 5x wider candidate pool than its CLI twin, and the `for` tool schema exposes
# no cap of its own, so no argument could reach the CLI's behavior. Measured on this repo before the fix:
# `parse arguments` reported dropped_positive="169" through MCP against the CLI's "11", off a 200-symbol head
# against a 40-symbol one, with a substantially different served symbol set.
#
# WHAT THIS GATE ASSERTS, and why it is these facts and not "byte-identical bundles". The two dialects
# deliberately serve DIFFERENT PAYLOAD: the CLI --for folds the Q3 quality lens onto each row (churn=/amp=/
# tested=) and reserves budget for the auto <bodies> block, while the MCP verb runs no git/clone pass. So
# their bundles differ in bytes by design, and the H1 trim ladder therefore drops a different NUMBER of rows
# on each side. What must NOT differ is the ranked candidate pool the ladder starts from:
#
#   (1) served + dropped_positive == the shared cap (serialize.h kForLensDefaultTopN) on BOTH dialects, for
#       every conceptual task. This is exactly droppedPositiveCount's three-bucket partition read back out:
#       the pool is the kept head, and both sides must have kept the same head.
#   (2) no CLI-served row is missing from the MCP set — the ladder drops tail-first, so the heavier CLI
#       bundle serves a SUBSET, never a different selection.
#   (3) on a narrow name-exact query, where neither bundle reaches its ceiling, the served sets are EXACTLY
#       equal and dropped_positive is absent on both — the exact-value parity arm.
#   (4) the server-wide `--top-k` is INERT for the MCP `for` verb, exactly as it is for the CLI `--for`.
#       This is the bug itself, asserted directly: `--mcp --top-k=5` and `--mcp --top-k=400` must produce
#       byte-identical `for` output, and so must the CLI at the same two values.
#
# Every arm was run RED against the pre-fix binary before the fix landed.
#
# Usage:  bash test/mcpforparitycheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/mcpforparitycheck.sh
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
echo "mcpforparitycheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
CORPUS="src"

# THE SHARED CAP, read out of the source rather than re-typed here: a gate that hardcodes 40 goes quietly
# inert the day the constant moves, and this whole file exists because two spellings of one number drifted.
CAP="$( sed -n 's/^inline constexpr int kForLensDefaultTopN *= *\([0-9]*\);.*/\1/p' src/serialize.h )"
if [ -z "$CAP" ]; then
    no "could not read kForLensDefaultTopN out of src/serialize.h — every arm below would measure nothing"
    echo "FAILURES ABOVE"; exit 1
fi
ok "shared cap read from source: kForLensDefaultTopN=$CAP"

# ── the two dialects, and the two facts read off each ────────────────────────────────────────────────────
# The served set is (file, line, name) per <d> row inside <sigs> — NOT id=, which the emitter omits whenever
# it would equal the bare name, so an id-keyed comparison silently undercounts the scope-less rows (measured
# while writing this gate: 24 of 29 CLI rows on one task). RE-PINNED: P7 (terminality round A, lane R, 2026-09-05): the lens <sigs> is FLAT — <d … p="FILE" … r=N> rows in rank order, no <f p=> wrapper (test/forrankordercheck.sh) — the file is the row's own p=.
cat > "$TMP/rows.py" <<'PY'
import re, sys
s = sys.stdin.read()
m = re.search( r'<sigs[^>]*>(.*?)</sigs>', s, re.S )
body = m.group( 1 ) if m else ''
out = []
for d in re.finditer( r'<d ([^>]*)>', body ):
    a = d.group( 1 )
    p = re.search( r'\bp="([^"]*)"', a )
    n = re.search( r'\bn="([^"]*)"', a )
    l = re.search( r'\bl="([^"]*)"', a )
    out.append( ( p.group( 1 ) if p else "?" ) + ":" + ( l.group( 1 ) if l else "?" ) + ":" + ( n.group( 1 ) if n else "?" ) )
print( "\n".join( sorted( out ) ) )
PY
cat > "$TMP/mcptext.py" <<'PY'
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try: d = json.loads( line )
    except Exception: continue
    c = d.get( "result", {} ).get( "content" )
    if c: print( c[0].get( "text", "" ) )
PY
dropped(){ python3 -c '
import re, sys
m = re.search( r"dropped_positive=\"([0-9]+)\"", sys.stdin.read() )
print( m.group( 1 ) if m else "0" )
'; }
cli_for(){ "$BIN" "$CORPUS" --for="$1" ${2:-} 2>/dev/null; }
mcp_for(){ printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' \
                  "$CORPUS" "$1" | "$BIN" --mcp ${2:-} 2>/dev/null | python3 "$TMP/mcptext.py"; }

# ── (1)+(2) the candidate pool, on four conceptual tasks ─────────────────────────────────────────────────
CONCEPTUAL=( "resolve call edges by name"
             "budget the emitted payload bytes"
             "cache the ingest result on disk"
             "quality delta baseline snapshot" )
pool_fail=0
subset_fail=0
for q in "${CONCEPTUAL[@]}"; do
    cli_for "$q"  >"$TMP/c.xml"
    mcp_for "$q"  >"$TMP/m.xml"
    if ! grep -q '<sigs' "$TMP/c.xml" || ! grep -q '<sigs' "$TMP/m.xml"; then
        no "(1) '$q' produced no <sigs> block on one of the two dialects — this task measured nothing"
        pool_fail=1; continue
    fi
    python3 "$TMP/rows.py" <"$TMP/c.xml" >"$TMP/c.rows"
    python3 "$TMP/rows.py" <"$TMP/m.xml" >"$TMP/m.rows"
    cserved=$( grep -c . "$TMP/c.rows" ); mserved=$( grep -c . "$TMP/m.rows" )
    cdrop=$( dropped <"$TMP/c.xml" );     mdrop=$( dropped <"$TMP/m.xml" )
    cpool=$(( cserved + cdrop ));         mpool=$(( mserved + mdrop ))
    if [ "$cpool" != "$CAP" ] || [ "$mpool" != "$CAP" ]; then
        no "(1) '$q': candidate pool CLI=$cpool MCP=$mpool, both must equal the shared cap $CAP (CLI $cserved+$cdrop, MCP $mserved+$mdrop)"
        pool_fail=1
    fi
    only_cli=$( comm -23 "$TMP/c.rows" "$TMP/m.rows" | grep -c . )
    if [ "$only_cli" != 0 ]; then
        no "(2) '$q': $only_cli row(s) served by the CLI are absent from the MCP set — the two ladders started from different heads"
        comm -23 "$TMP/c.rows" "$TMP/m.rows" | head -5
        subset_fail=1
    fi
done
[ "$pool_fail"   = 0 ] && ok "(1) served+dropped_positive == $CAP on BOTH dialects, all ${#CONCEPTUAL[@]} conceptual tasks"
[ "$subset_fail" = 0 ] && ok "(2) every CLI-served row is present in the MCP set on all ${#CONCEPTUAL[@]} tasks (the heavier bundle serves a subset)"

# ── (3) exact-value parity where neither bundle reaches its ceiling ──────────────────────────────────────
# A name-exact query serves a handful of rows, so the H1 ladder never fires and the two dialects have
# nothing left to differ about: identical sets, and dropped_positive absent on both. This is the arm that
# pins the VALUE, which the pre-existing droppedpositivecheck arm #6 (presence/absence only) could not.
NARROW=( "relevanceFloorCut" "editCheckContractVsHead" "adaptiveCut" )
exact_fail=0
for q in "${NARROW[@]}"; do
    cli_for "$q" >"$TMP/c.xml"
    mcp_for "$q" >"$TMP/m.xml"
    python3 "$TMP/rows.py" <"$TMP/c.xml" >"$TMP/c.rows"
    python3 "$TMP/rows.py" <"$TMP/m.xml" >"$TMP/m.rows"
    if [ "$( grep -c . "$TMP/c.rows" )" = 0 ]; then
        no "(3) '$q' resolved to nothing on the CLI — this arm measured nothing"
        exact_fail=1; continue
    fi
    if ! cmp -s "$TMP/c.rows" "$TMP/m.rows"; then
        no "(3) '$q': the served sets differ on a query neither bundle's ceiling touches"
        diff "$TMP/c.rows" "$TMP/m.rows" | head -6
        exact_fail=1
    fi
    if grep -q 'dropped_positive=' "$TMP/c.xml" || grep -q 'dropped_positive=' "$TMP/m.xml"; then
        no "(3) '$q': dropped_positive= present on a non-dropping query (CLI or MCP) — this arm's premise is gone"
        exact_fail=1
    fi
done
[ "$exact_fail" = 0 ] && ok "(3) identical served sets and no dropped_positive= on either dialect, all ${#NARROW[@]} narrow queries"

# ── (4) the server-wide --top-k is inert for BOTH surfaces (the bug, asserted directly) ──────────────────
INERT_Q="resolve call edges by name"
mcp_for "$INERT_Q" "--top-k=5"   >"$TMP/mk5.xml"
mcp_for "$INERT_Q" "--top-k=400" >"$TMP/mk400.xml"
if [ ! -s "$TMP/mk5.xml" ] || [ ! -s "$TMP/mk400.xml" ]; then
    no "(4) one of the --top-k MCP runs produced nothing — the inertness arm measured nothing"
elif cmp -s "$TMP/mk5.xml" "$TMP/mk400.xml"; then
    ok "(4) MCP for: --mcp --top-k=5 and --top-k=400 are byte-identical (the map's row cap does not reach this lens)"
else
    no "(4) MCP for honors the server-wide --top-k: $( wc -c <"$TMP/mk5.xml" ) vs $( wc -c <"$TMP/mk400.xml" ) bytes — the F-03 defect"
fi
cli_for "$INERT_Q" "--top-k=5"   >"$TMP/ck5.xml"
cli_for "$INERT_Q" "--top-k=400" >"$TMP/ck400.xml"
cmp -s "$TMP/ck5.xml" "$TMP/ck400.xml" \
    && ok "(4) CLI --for: --top-k is inert too (the documented behavior the MCP twin now matches)" \
    || no "(4) CLI --for moved with --top-k — the reference this parity is measured against is not what it claims"

# ── (5) budget_tokens on this twin is never a SILENT overshoot — the CLI rule, stated for the dialect ─────
# THE FAMILY RULE (METHODOLOGY §9 #2 + #4, and the CLI half of it: fornotesbudgetcheck arm 6). A caller who
# states a ceiling gets one of exactly two honest answers, never a third:
#   • the price is SERVED — est_tokens= on the root — and then est_tokens <= budget_tokens, or the root
#     carries over_ceiling="1" saying it does not (the CLI's rule, verbs_for.h, F2);
#   • the price is DECLARED ABSENT — est_tokens named in this dialect's lens= list — which is the posture
#     this twin holds today: it is shaped by the server's payload byte cap, not priced against the caller's
#     ceiling, so it says so on the root instead of printing a number it did not compute.
# Silence is the third answer and the one this arm forbids: no price, no declaration, and a budget_tokens=
# the caller cannot check the answer against. The disjunction is written so lane F's F5 (pricing this bundle
# rather than declaring it) LANDS THROUGH this gate instead of needing it rewritten — the day est_tokens is
# served here, the first clause takes over and the overshoot must be labelled exactly as the CLI labels it.
# Also asserted: the stated ceiling is echoed at all (H9's budget_tokens= on the root); a bundle shaped
# against a ceiling nobody can read is the defect H9 closed on the CLI and this twin inherited.
# RED, MEASURED, three ways: on 77004e5c (pre-F2) the served-price clause fails the moment a price is served
# unlabelled; dropping the lens= declaration while still not serving the number fails the second clause; and
# removing the budget_tokens= splice (mcpverbs.h, the H9 insert) fails the echo clause on every rung.
mcp_for_budget(){ printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s","budget_tokens":%s}}}\n' \
                         "$CORPUS" "$1" "$2" | "$BIN" --mcp 2>/dev/null | python3 "$TMP/mcptext.py"; }
for tb in 900 1200 1600 2000 6000; do
    b="$( mcp_for_budget "$INERT_Q" "$tb" )"
    root="$( printf '%s' "$b" | sed -n 's/^\(<[^>]*>\).*/\1/p' | head -1 )"
    if [ -z "$root" ]; then
        no "(5) budget_tokens=$tb: the MCP for verb produced no root element — nothing to check the ceiling against"
        continue
    fi
    case "$root" in
        *"budget_tokens=\"$tb\""*) ;;
        *) no "(5) budget_tokens=$tb: the stated ceiling is not echoed on the root — a bundle shaped against a ceiling nobody can read (H9)"; continue ;;
    esac
    est="$( printf '%s' "$root" | grep -o 'est_tokens="[0-9]*"' | head -1 | tr -dc '0-9' )"
    if [ -n "$est" ]; then
        case "$root" in *'over_ceiling="1"'*) lab=1 ;; *) lab=0 ;; esac
        if [ "$est" -le "$tb" ] || [ "$lab" -eq 1 ]; then
            ok "(5) budget_tokens=$tb: price SERVED and honest (est_tokens=$est, over_ceiling=$lab)"
        else
            no "(5) budget_tokens=$tb: est_tokens=$est exceeds the stated ceiling by $(( est - tb )) with NO over_ceiling — a silent overshoot on the MCP twin"
        fi
    else
        case "$root" in
            *'lens="'*'est_tokens'*'"'*) ok "(5) budget_tokens=$tb: price DECLARED ABSENT in lens= (shaped by the server's byte cap, not priced) — not silent" ;;
            *) no "(5) budget_tokens=$tb: no est_tokens= and no est_tokens in lens= — the caller cannot tell the bundle fits the ceiling it stated" ;;
        esac
    fi
done

# ── determinism + well-formedness on the MCP dialect ─────────────────────────────────────────────────────
mcp_for "$INERT_Q" >"$TMP/d1.xml"; mcp_for "$INERT_Q" >"$TMP/d2.xml"
cmp -s "$TMP/d1.xml" "$TMP/d2.xml" \
    && ok "MCP for output is byte-identical across two runs" \
    || no "MCP for output is not deterministic"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/d1.xml" 2>/dev/null \
        && ok "MCP for output is well-formed XML (G4)" || no "MCP for output is not well-formed"
else
    printf '  SKIP  xmllint (not installed)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"

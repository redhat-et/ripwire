#!/usr/bin/env bash
# recallparitycheck.sh — CLI `--recall` and MCP `memory_recall` are ONE verb: same corpus + same task
# ⇒ same bundle, byte for byte.
#
# THE REGRESSION CLASS THIS GATE CLOSES. `--recall` has two front doors and they were ranked by two
# different calls. The CLI passed `lexicalScores( …, pathFieldDefaultW=1, rootPrefix )`; mcpverbs.h's
# `recallText` passed `lexicalScores( ix.ing, …, task )` — weight 0, no prefix — under a comment claiming
# the two "share lexicalScores". The consequence was not a rounding difference: a document findable only
# by its PATH (its directory naming the query word) was RETRIEVED by the CLI and answered
# "no relevant documents" over MCP, and every score the two doors did share moved anyway, because the path
# tokens change each document's BM25 length normalization. Registered as known debt in docs/EVALS.md
# §"`--recall` ranks by where the repo sits on disk" (2026-08-25): "`mcpverbs.h::recallText` calls
# `lexicalScores( ix.ing, …, task )` with no `pathFieldDefaultW`, i.e. 0, while the CLI `--recall` passes 1
# — so MCP `memory_recall` and CLI `--recall` already rank the same query differently".
#
# Both doors now go through recall.h's `recallFor` (rank + build in one call; the lens decision lives
# there, not at either call site). This gate is what keeps that true: a future edit that re-introduces a
# per-door argument has to make these arms red to land.
#
# Invariants frozen here:
#   1. PARITY — for every probe query, the MCP text payload is BYTE-IDENTICAL to CLI stdout (header
#      included). Not "similar ranking": the same bytes, since it is the same bundle.
#   2. PARITY under the shaping knobs — top_k and the body ceiling are the same two levers on both doors.
#   3. The NAMED regression — the path-only query is retrieved on BOTH doors. An MCP reply reading
#      "no relevant documents" for a document the CLI returns is the exact pre-fix symptom.
#   4. KILL TRIPWIRE (outranks 1-3, mirroring recallrankdepthcheck.sh ARM 4) — parity must be reached by
#      giving MCP the recall lens, NEVER by removing the path field from the CLI. The path-only document
#      must still be RETRIEVED. If arms 1-3 go green while this one goes red, the "unification" deleted a
#      measured retrieval feature (bench/recalleval: +0.03 lenient MRR) and is wrong regardless.
#   5. Both doors are deterministic run to run.
#
# Usage:
#   test/recallparitycheck.sh                                    # uses build/ripwire
#   test/recallparitycheck.sh /path/to/other/ripwire             # positional binary
#   RIPWIRE_BIN=build_base/ripwire test/recallparitycheck.sh      # env binary (the RED run)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for the MCP arm"; exit 2; }
echo "recallparitycheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R/telemetry" "$R/notes"

# ── the corpus. Two documents carry the query word ONLY in their path — one in a DIRECTORY component,
# one in a FILENAME — which is precisely what the recall lens's path field exists to reach and precisely
# what a weight-0 door cannot see. The rest are body-only matches and neutral filler, so the ranking has
# something to order rather than a single trivially-top hit.
printf '# Zeta\nA short note about counters and sampling of emitted events.\n'                      > "$R/telemetry/zeta.md"
printf '# Alpha\nThe subsystem coordinates worker threads and a bounded queue.\n'                    > "$R/notes/scheduler_design.md"
printf '# Beta\nGeneral remarks on the ordering and dispatch of work items.\n'                       > "$R/notes/beta.md"
printf '# Gamma\nMore remarks about ordering, dispatch, work items, threads and queues.\n'           > "$R/notes/gamma.md"
printf '# Delta\nUnrelated glyph rasterization, subpixel antialiasing and hinting.\n'                > "$R/notes/delta.md"
printf '# Epsilon\nCounters and sampling appear here in the BODY, not in the path.\n'                > "$R/notes/epsilon.md"

# CLI door. --no-cache so the probe never reads a warm index built by another gate.
cli(){ perl -e 'alarm 60; exec @ARGV' "$BIN" "$R" --recall="$1" --no-cache "${@:2}" 2>/dev/null; }

# MCP door. One initialize + one tools/call; the reply's text payload is written VERBATIM (no trailing
# newline of its own), because a byte comparison against CLI stdout is the whole point of this gate.
mcp(){
    python3 - "$BIN" "$R" "$@" <<'PY'
import json, subprocess, sys
binp, root, task = sys.argv[1], sys.argv[2], sys.argv[3]
args = { "path": root, "task": task }
for kv in sys.argv[4:]:
    k, v = kv.split( "=", 1 )
    args[k] = int( v )
msgs = [ { "jsonrpc": "2.0", "id": 1, "method": "initialize" },
         { "jsonrpc": "2.0", "id": 2, "method": "tools/call",
           "params": { "name": "memory_recall", "arguments": args } } ]
p = subprocess.run( [ binp, "--mcp" ], input = "\n".join( json.dumps( m ) for m in msgs ) + "\n",
                    capture_output = True, text = True, timeout = 120 )
for line in p.stdout.splitlines():
    try:
        d = json.loads( line )
    except ValueError:
        continue
    if d.get( "id" ) == 2:
        if "error" in d:
            sys.stdout.write( "__ERROR__:" + d[ "error" ].get( "message", "" ) )
        else:
            sys.stdout.write( d[ "result" ][ "content" ][ 0 ][ "text" ] )
PY
}

# ── 1 + 3. parity across the probe set, INCLUDING the path-only queries ──────────────────────────────
# "telemetry" and "scheduler" appear in no BODY in this corpus — only in a directory name and a file name.
# Pre-fix, those two rows are the ones that differ; the rest differ in score digits (path tokens move every
# document's length normalization), which is why the whole set is compared and not just the interesting two.
probes=( "telemetry" "scheduler" "scheduler design" "ordering dispatch work items" "counters sampling" )
for q in "${probes[@]}"; do
    cli "$q"  > "$TMP/cli.out"
    mcp "$q"  > "$TMP/mcp.out"
    cmp -s "$TMP/cli.out" "$TMP/mcp.out" \
        && ok "parity \"$q\": MCP memory_recall is byte-identical to CLI --recall" \
        || { no "parity \"$q\": the two front doors of one verb disagree"; diff "$TMP/cli.out" "$TMP/mcp.out" | head -6; }
done

# ── 3 (named). the pre-fix symptom, asserted as itself so a failure reads as the bug it is ───────────
mcp "telemetry" > "$TMP/mcp_path.out"
grep -q 'no relevant documents' "$TMP/mcp_path.out" \
    && no "MCP memory_recall answers 'no relevant documents' for a doc the CLI retrieves by its PATH — the registered divergence is back" \
    || ok "MCP memory_recall retrieves the path-only document (not 'no relevant documents')"

# ── 4. KILL TRIPWIRE: parity must not be bought by disabling the path field ─────────────────────────
# Both doors must RETRIEVE the two documents whose query word lives only in their path. Byte-parity is
# trivially satisfiable by scoring no path tokens anywhere, which would silently delete a measured
# retrieval feature; if this arm is red the change is reverted regardless of every arm above.
for pair in "telemetry:telemetry/zeta.md" "scheduler:notes/scheduler_design.md"; do
    q="${pair%%:*}"; want="${pair#*:}"
    cli "$q" > "$TMP/cli.out"; mcp "$q" > "$TMP/mcp.out"
    { grep -q "$want" "$TMP/cli.out" && grep -q "$want" "$TMP/mcp.out"; } \
        && ok "path field LIVE on both doors: \"$q\" retrieves $want (body never spells the query)" \
        || no "path field DEAD: \"$q\" no longer reaches $want — parity was reached by removing the feature, not by sharing it"
done

# ── 2. parity under the shaping knobs — one lever, two spellings, same bundle ────────────────────────
cli "ordering dispatch work items" --top-k=2                 > "$TMP/cli_k.out"
mcp "ordering dispatch work items" "top_k=2"                 > "$TMP/mcp_k.out"
cmp -s "$TMP/cli_k.out" "$TMP/mcp_k.out" \
    && ok "parity under top-k: --top-k=2 and top_k:2 return the same bundle" \
    || { no "parity under top-k: --top-k=2 and top_k:2 diverge"; diff "$TMP/cli_k.out" "$TMP/mcp_k.out" | head -6; }

cli "ordering dispatch work items" --max-tokens=1000000      > "$TMP/cli_b.out"
mcp "ordering dispatch work items" "budget_tokens=1000000"   > "$TMP/mcp_b.out"
cmp -s "$TMP/cli_b.out" "$TMP/mcp_b.out" \
    && ok "parity under the body ceiling: --max-tokens=1000000 and budget_tokens:1000000 agree" \
    || { no "parity under the body ceiling: the two budget spellings diverge"; diff "$TMP/cli_b.out" "$TMP/mcp_b.out" | head -6; }

# ── 5. determinism on both doors ────────────────────────────────────────────────────────────────────
cli "ordering dispatch work items" > "$TMP/cli2.out"
mcp "ordering dispatch work items" > "$TMP/mcp2.out"
cli "ordering dispatch work items" > "$TMP/cli3.out"
mcp "ordering dispatch work items" > "$TMP/mcp3.out"
cmp -s "$TMP/cli2.out" "$TMP/cli3.out" && ok "CLI --recall deterministic (byte-identical run to run)" \
                                       || no "CLI --recall non-deterministic"
cmp -s "$TMP/mcp2.out" "$TMP/mcp3.out" && ok "MCP memory_recall deterministic (byte-identical run to run)" \
                                       || no "MCP memory_recall non-deterministic"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail

#!/usr/bin/env bash
# mcplisttrimcheck.sh: lane P2 (0.7.0 token-efficiency push, 2026-11-18). The tools/list trim is LOSSLESS
# with respect to the contract, and stays so.
#
# THE COST. Clients that load MCP schemas eagerly (Cursor, Codex, others) pay for tools/list in EVERY
# session, before the first question. On the base of this lane (82ed4c8bf) it was 47,411 B by
# mcpmanifestcheck's metric, more than a whole `for` answer. 17,365 B of that was description prose AFTER
# the pinned routing sentences, and that prose is what P2 trimmed.
#
# WHAT A TRIM MAY NOT TOUCH, and what this gate pins:
#   (1) STRUCTURE. Every stanza minus its tool-level `description` (the name, the order, the whole inputSchema:
#       property names, types, items, the property descriptions, which are the refusal text, `required`,
#       and the annotations) is byte-identical to test/mcplist_structure_golden.txt. A trim that drops or
#       retypes an argument, or rewords a refusal, fails here. It does not merely move a byte count.
#   (2) CEILING. The manifest, measured the way mcpmanifestcheck measures it (json.dumps of {"tools":...},
#       ensure_ascii), stays at or under CEILING. This is a ratchet: lower it whenever the manifest drops,
#       and raise it only for a DECLARED argument or tool, in the commit that lands it, with its bytes
#       attributed. That is mcpmanifestcheck's rule (1), which carries the full re-anchor history.
#   (3) DETERMINISM. Two servers answer tools/list byte-identically.
#   (4) MUTATION CONTROL. The structure comparator is run on a copy with one property removed, and must
#       report it. A comparator that cannot fail proves nothing.
#
# The routing first sentences are pinned by mcpmanifestcheck (2), not here, so one pin is not kept twice.
#
# Usage:
#   bash test/mcplisttrimcheck.sh                                 # uses build/ripwire
#   RIPWIRE_BIN=/path/to/ripwire bash test/mcplisttrimcheck.sh
#   RIPWIRE_MCPLIST_REGEN=1 bash test/mcplisttrimcheck.sh         # rewrite the golden (deliberate contract change)
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
GOLDEN="$ROOT/test/mcplist_structure_golden.txt"
echo "mcplisttrimcheck: BIN=$BIN"

python3 - "$BIN" "$ROOT" "$GOLDEN" <<'PY'
import json, os, subprocess, sys

BIN, ROOT, GOLDEN = sys.argv[1], sys.argv[2], sys.argv[3]
fails = 0
def check( cond, msg ):
    global fails
    print( ( "  PASS  " if cond else "  FAIL  " ) + msg )
    if not cond: fails += 1

REQ = ( '{"jsonrpc":"2.0","id":1,"method":"initialize"}\n'
        '{"jsonrpc":"2.0","method":"notifications/initialized"}\n'
        '{"jsonrpc":"2.0","id":2,"method":"tools/list"}\n' )
def toolsListLine():
    r = subprocess.run( [ BIN, ROOT, "--mcp" ], input = REQ, capture_output = True, text = True, cwd = ROOT )
    lines = [ l for l in r.stdout.splitlines() if '"id":2' in l ]
    return lines[ -1 ] if lines else ""

first = toolsListLine()
try:
    tools = json.loads( first )[ "result" ][ "tools" ]
except ( ValueError, KeyError, TypeError ):
    print( "  FAIL  tools/list did not answer with a parseable tools array: %r" % first[ :200 ] )
    sys.exit( 1 )

def structureRows( toolList ):
    return [ ( t[ "name" ], json.dumps( { k: v for k, v in t.items() if k != "description" },
                                        separators = ( ",", ":" ), ensure_ascii = False ) ) for t in toolList ]

if os.environ.get( "RIPWIRE_MCPLIST_REGEN" ):
    head = [ l for l in open( GOLDEN, encoding = "utf-8" ) if l.startswith( "#" ) ] if os.path.exists( GOLDEN ) else []
    with open( GOLDEN, "w", encoding = "utf-8" ) as fh:
        fh.writelines( head )
        for name, row in structureRows( tools ):
            fh.write( name + "\t" + row + "\n" )
    print( "  INFO  rewrote %s (%d tools); say why in the commit" % ( GOLDEN, len( tools ) ) )

golden = []
for line in open( GOLDEN, encoding = "utf-8" ):
    line = line.rstrip( "\n" )
    if line and not line.startswith( "#" ):
        name, _, row = line.partition( "\t" )
        golden.append( ( name, row ) )

def compare( liveRows, goldRows ):
    """Every difference between two structure lists, as readable strings (empty = identical)."""
    diffs = []
    liveNames = [ n for n, _ in liveRows ]
    goldNames = [ n for n, _ in goldRows ]
    if liveNames != goldNames:
        diffs.append( "tool list/order differs: only-live=%s only-golden=%s"
                      % ( sorted( set( liveNames ) - set( goldNames ) ), sorted( set( goldNames ) - set( liveNames ) ) ) )
    gold = dict( goldRows )
    for name, row in liveRows:
        if name in gold and gold[ name ] != row:
            diffs.append( "%s: stanza structure moved (schema, property description or annotations)" % name )
    return diffs

# ── (1) STRUCTURE ────────────────────────────────────────────────────────────────────────────────────
live = structureRows( tools )
diffs = compare( live, golden )
for d in diffs[ :8 ]:
    print( "        " + d )
check( not diffs, "(1) every stanza minus its description is byte-identical to the golden (%d tools)" % len( golden ) )
check( all( t.get( "description", "" ).strip() for t in tools ), "(1) every tool still carries a non-empty description" )

# ── (2) CEILING ──────────────────────────────────────────────────────────────────────────────────────
# P2 2026-11-18: 47,411 B at base (82ed4c8bf) -> 39,940 B measured after the trim (-7,471 B, -15.8%),
# descriptions 22,498 -> 15,133 B (UTF-8), no schema byte moved. Ceiling = measured + 30 B, the #214-sized margin.
# RT2 MCP parity (2026-11-19): +90 B, every byte attributed — `for` gains the no_verb_route boolean (the CLI --no-verb-route twin,
# the opt-out a routed `for` answer's next= names): measured 39,940 -> 40,030 B, descriptions unchanged at 15,133 B, the 33 first
# sentences unchanged. Ceiling = measured + 30 B, the same margin.
# RT2 batch parity (2026-11-19): +35 B — the batch item schema gains no_verb_route (the batch `for` item routes like the live
# verb, so its opt-out rides the item too): measured 40,030 -> 40,065 B, descriptions unchanged. Ceiling = measured + 30 B.
# MR1 (2026-11-21, owner ruling 168): +73 B over the 40,073 B base 36a95d732 — `for` gains the `rows` string (the CLI --rows= twin):
# schemas 20,391 -> 20,464 B, descriptions unchanged; measured 40,146 B. Ceiling = measured + 30 B (mcpmanifestcheck's figure).
# BRIEF-VERB (2026-11-25, lane/brief-verb): +905 B over the 40,146 B base d847bd3f3, every byte attributed — ONE NEW ADVERTISED
#   TOOL, `brief` (the CLI --brief= twin): description 339 B (routing sentence pinned in mcpmanifest_first_sentences.txt; trimmed
#   from 485 B before landing) + schema 428 B (path, task, bytes, paths) + 131 B tool envelope and separator = 898 B; batch's
#   description +7 B (", brief": the NOT-batchable list names every excluded verb, now 18). Descriptions 15,117 -> 15,463 B,
#   schemas 20,464 -> 20,892 B, the other 33 stanzas unchanged. Measured 41,051 B; ceiling = measured + 30 B, the same margin.
CEILING = 41081
manifest = len( json.dumps( { "tools": tools }, separators = ( ",", ":" ) ) )
print( "  INFO  manifest %d B (ensure_ascii metric), wire line %d B, descriptions %d B"
       % ( manifest, len( first.encode( "utf-8" ) ), sum( len( t[ "description" ].encode( "utf-8" ) ) for t in tools ) ) )
check( manifest <= CEILING, "(2) tools/list is %d B, within the %d B ceiling" % ( manifest, CEILING ) )

# ── (3) DETERMINISM ──────────────────────────────────────────────────────────────────────────────────
second = toolsListLine()
check( first == second, "(3) tools/list is byte-identical across two servers (%d B)" % len( first.encode( "utf-8" ) ) )

# ── (4) MUTATION CONTROL ─────────────────────────────────────────────────────────────────────────────
mutated = json.loads( json.dumps( tools ) )
victim = next( t for t in mutated if t[ "inputSchema" ].get( "properties" ) )
dropped = sorted( victim[ "inputSchema" ][ "properties" ] )[ -1 ]
del victim[ "inputSchema" ][ "properties" ][ dropped ]
check( compare( structureRows( mutated ), golden ) != [],
       "(4) mutation control: dropping %s.%s is reported by the structure comparator" % ( victim[ "name" ], dropped ) )

print( "" )
if fails == 0: print( "ALL PASS" )
else:          print( "%d CHECK(S) FAILED" % fails )
sys.exit( 1 if fails else 0 )
PY

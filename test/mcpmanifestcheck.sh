#!/usr/bin/env bash
# mcpmanifestcheck.sh — capture-audit 2026-09-04 P11: the MCP manifest is a PER-SESSION BILL, and it is gated.
#
# THE FINDING. `tools/list` was 44,951 B — about 11.2K tokens every MCP client pays before it asks anything,
# on a tool whose whole pitch is that it costs an agent fewer tokens than reading files. 26,226 B of that was
# descriptions, and the largest ones were not routing information: the LIMITS paragraphs of slice / grep /
# impact duplicated, sentence for sentence, prose the response legend already carries in-band — so a caller
# paid for it once in the manifest and again in every answer. (This gate was written when the working tree
# had grown it further, to 48,262 B, by adding real disclosures. Both facts are the same fact: nothing was
# charging for the manifest, so it only ever went up.)
#
# WHAT IS GATED, and why these three together:
#   1. SIZE — a ceiling on the whole tools/list payload. Alone this would invite cutting the routing text,
#      which is the one part that must not go, so:
#   2. FIRST SENTENCES — every tool's opening sentence is byte-identical to the pinned list below. That is
#      the ROUTING sentence: the text an agent reads to choose a verb. It is what the skill-routing eval
#      measures and what the hedges lane (L10) put its corrections into. Trimming is allowed everywhere
#      EXCEPT there.
#   3. ROUTING SCORE — `ripwire skills --eval-skills` re-run, so a cut that keeps every first sentence and
#      still makes the tool harder to choose is caught by measurement rather than by reading.
#
# The pinned sentences live in this file rather than in a generated fixture on purpose: a pin whose expected
# value is regenerated from the binary cannot fail, and this gate exists to make one specific kind of edit
# — "shorten the descriptions" — provably safe for the routing half.
#
# Usage:
#   bash test/mcpmanifestcheck.sh                                 # uses build/ripwire
#   RIPWIRE_BIN=build_base/ripwire bash test/mcpmanifestcheck.sh   # the RED run (pre-trim binary)
#   RIPWIRE_MANIFEST_DUMP=1 bash test/mcpmanifestcheck.sh          # print the per-tool table (before/after work)
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "mcpmanifestcheck: BIN=$BIN"

# ── the pinned FIRST SENTENCES ────────────────────────────────────────────────────────────────────────
# One `name<TAB>sentence` row per advertised tool. "First sentence" = up to and including the first
# sentence-ending period followed by a space, with the same abbreviation exceptions the extractor below
# applies. Regenerate ONLY when a routing sentence is deliberately rewritten, and say so in the commit.
PINS="$ROOT/test/mcpmanifest_first_sentences.txt"
[ -f "$PINS" ] || { echo "missing $PINS — this gate's pin file (see the header)"; exit 2; }

python3 - "$BIN" "$ROOT" "$PINS" <<'PY'
import json, os, re, subprocess, sys

BIN, ROOT, PINS = sys.argv[1], sys.argv[2], sys.argv[3]
fails = 0
def check( cond, msg ):
    global fails
    print( ( "  PASS  " if cond else "  FAIL  " ) + msg )
    if not cond: fails += 1

req = ( '{"jsonrpc":"2.0","id":1,"method":"initialize"}\n'
        '{"jsonrpc":"2.0","id":2,"method":"tools/list"}\n' )
out = subprocess.run( [ BIN, "--mcp" ], input = req, capture_output = True, text = True ).stdout
line = [ l for l in out.splitlines() if l.strip() ][ -1 ]
tools = json.loads( line )[ "result" ][ "tools" ]

# ── 1. SIZE ───────────────────────────────────────────────────────────────────────────────────────────
# The measured unit is the tools array as it goes on the wire (minified JSON), which is what the client's
# context actually pays for.
#
# WHY 39,000 AND NOT P11'S 25,000, with the arithmetic (measured 2026-09-04, this lane):
#   descriptions   19,383 B   = 4,716 B of routing sentences (pinned below, untouchable) + the spliced
#                               @FILE:LINE / exemplar-rule constants (~1,800 B, shared verbatim with the
#                               CLI) + one argument list per tool
#   schemas        15,006 B   = 8,888 B of irreducible JSON Schema STRUCTURE over 137 declared properties
#                               (~65 B each for the "name":{"type":…,"description":…} envelope) + 6,020 B
#                               of property descriptions
#   envelope        ~4,400 B   = tool names, the tools array, the JSON-RPC frame
# The one remaining lever big enough to reach 25,000 is deleting the property descriptions — and those are
# the SAME bytes the bad-value refusals speak ("invalid value for field: limit — needs a positive integer
# (omit for the default window)"), read at exactly the moment a caller is stuck, and mcpcontractcheck's
# (A/M12) arm requires every declared property to carry one. P11's own "after" shape (a routing sentence
# plus an argument list, <=600 B per tool) is what this lane implemented, and that shape arrives at ~38 KB,
# not 25 KB: the 25,000 figure was set without the schema half in the sum. OWNER DECISION registered rather
# than silently resolved: drop the schema descriptions (cheaper manifest, poorer refusals) or accept ~38 KB.
#
# 39,000 was a RATCHET, not a target: it sat ~180 B above the measured 38,816, which is roughly what one
# new argument's schema entry costs. Lower it whenever the manifest drops; never raise it to fit a change.
#
# RE-ANCHORED 2026-09-04 (capture-audit wave-2 merge): 39,000 → 39,450, measured 39,273. Two lanes that could
# not see each other landed in one wave: this gate (lane L6) and lane L8's P9, whose folded edit receipt adds
# ONE declared optional argument, `post_check`, to each of the three edit verbs — +134 B apiece (the ~65 B
# schema envelope plus the description mcpcontractcheck (A/M12) requires every declared property to carry),
# +402 B in all — plus +46 B for the merged batch stanza (L6's two-grammar sentence beside L8's served set).
# Attributed tool by tool against a build of the pre-L8 merge head (c7ed07f): batch +46, insert_after_symbol
# +134, insert_before_symbol +134, replace_symbol_body +134, nothing else moved. The rule above stands with
# one precision: a ceiling moves UP only for a DECLARED argument the contract obliges to carry a description,
# in the commit that lands it, with its bytes attributed here — never for prose. The new ceiling keeps the
# same posture (177 B of headroom, one more argument entry); L7's compaction lane is where it goes back DOWN.
#
# RE-ANCHORED 2026-09-05 (lane L7, P1): 39,450 → 41,000, measured 40,841 (from 39,273). ONE declared optional
# argument, `legend` (the opt-in compact posture, §5a decision 3), on each of the SIXTEEN verbs that answer XML:
# analyze lego owners batch exemplar impact uses path_between connect explore from_trace edit_check whereis
# stray_content flags doc_drift — +98 B apiece (the ~35 B schema envelope plus the 63 B description the contract
# obliges), +1,568 B in all; nothing else moved. The same rule (a DECLARED argument, its bytes attributed, never
# prose) and the same posture (159 B of headroom). What this buys back per session: every XML answer under
# legend:"compact" drops 2.9–5.2 KB of repeated legend (compactlegendcheck (M): edit_check 5,561 → 582 B).
# ── THE CEILING, DECIDED 2026-09-05 (terminality round A, lane M / M2): IT STAYS 41,000. ─────────────
# Registered as an OWNER DECISION with the arithmetic, so it can be overruled with numbers rather than
# re-litigated. Measured on this tree at the M1 commit: manifest 40,841 B (~10,210 tokens), descriptions
# 19,353 B over 31 tools (mean 624), schemas 17,061 B — of which 7,190 B are the 157 declared properties'
# descriptions (mean 45) and 9,871 B is irreducible JSON Schema STRUCTURE (types, required, property names,
# braces) — plus a 4,427 B envelope (tool names, annotations, the tools array). Headroom: 159 B.
#
# THE SIX LINES.
#  1. COST. tools/list is 40,841 B ~ 10,210 tokens, paid ONCE per session, before the first call.
#  2. IT IS NOT WHERE THE RECURRING COST LIVES. M1 (the compact MCP legend default) cut the per-CALL legend
#     bill on a ten-verb edit loop from 30,839 B to 2,866 B: ONE loop now saves 27,973 B, 68% of the whole
#     manifest, and it saves it again on the next loop. The manifest amortizes; the legend never did.
#  3. 25,000 IS NOT AVAILABLE AT THE STATED QUALITY, and here is the subtraction rather than an assertion:
#     deleting ALL 157 property descriptions saves 7,190 B and lands at 33,651 — still 8,651 B over — so
#     25,000 additionally requires cutting ~45% of the tool descriptions.
#  4. WHAT THOSE BYTES BUY. The property descriptions ARE the bad-value refusals ("invalid value for field:
#     limit — needs a positive integer (omit for the default window)"), read exactly when a caller is stuck,
#     and arm (A/M12) of mcpcontractcheck requires every declared property to carry one. The tool
#     descriptions are what the router scores: --eval-skills is 25/26 today (arm 3 below), so a cut there is
#     measured as routing loss, immediately, in this gate.
#  5. THE HEADROOM IS THE DISCIPLINE. 159 B is LESS than one declared argument on one verb (~98-134 B: the
#     ~65 B schema envelope plus the description the contract obliges), so the next lane that declares an
#     argument re-anchors deliberately, in its own commit, with its bytes attributed here. That is the rule
#     working, not a ceiling set too tight.
#  6. DECISION: KEEP 41,000. Nothing dropped this round to ratchet against — M1 cost ZERO manifest bytes,
#     because the flip is stated in the `legend` FIELD description ("compact (the default) or full"), spliced
#     into all seventeen declaring stanzas, in the same 54 bytes the old wording spent; a clause in seventeen
#     tool descriptions would have cost ~680 B against 159 B of headroom and would have been prose, which the
#     rule above forbids raising for. The owner may overrule toward ~33,650 (drop every property description,
#     lose the refusals) or ~25,000 (that, plus 45% of the routing text, with the routing score as the
#     receipt). Recorded in PLAN_TERMINALITY_2026-09-05.md §3a.
#
CEILING = 41000
manifest = len( json.dumps( { "tools": tools }, separators = ( ",", ":" ) ) )
descBytes   = sum( len( t[ "description" ] ) for t in tools )
schemaBytes = sum( len( json.dumps( t[ "inputSchema" ], separators = ( ",", ":" ) ) ) for t in tools )
print( "  INFO  %d tools, manifest %d B (~%d tokens): descriptions %d B, schemas %d B"
       % ( len( tools ), manifest, manifest // 4, descBytes, schemaBytes ) )
check( manifest <= CEILING,
       "(1) tools/list is %d B, within the %d B per-session ceiling" % ( manifest, CEILING ) )

if os.environ.get( "RIPWIRE_MANIFEST_DUMP" ):
    for db, sb, n in sorted( ( ( len( t[ "description" ] ),
                                 len( json.dumps( t[ "inputSchema" ], separators = ( ",", ":" ) ) ),
                                 t[ "name" ] ) for t in tools ), reverse = True ):
        print( "  DUMP  %-28s desc=%5d schema=%5d" % ( n, db, sb ) )

# ── 2. FIRST SENTENCES, byte-identical ────────────────────────────────────────────────────────────────
# Abbreviations that end in a period and are NOT sentence ends. Kept tiny and explicit: a clever splitter
# that silently mis-cuts turns this pin into a pin on the wrong bytes.
ABBREV = ( "e.g.", "i.e.", "vs.", "arXiv.", "etc." )
def firstSentence( d ):
    i = 0
    while True:
        j = d.find( ". ", i )
        if j == -1:
            return d.strip()
        head = d[ : j + 1 ]
        if any( head.endswith( a ) for a in ABBREV ):
            i = j + 2
            continue
        return head

pins = {}
for row in open( PINS, encoding = "utf-8" ):
    row = row.rstrip( "\n" )
    if not row or row.startswith( "#" ):
        continue
    name, _, sentence = row.partition( "\t" )
    pins[ name ] = sentence

live = { t[ "name" ]: firstSentence( t[ "description" ] ) for t in tools }
check( set( live ) == set( pins ),
       "(2) the pin file covers exactly the advertised tool set (only-live: %s / only-pinned: %s)"
       % ( sorted( set( live ) - set( pins ) ), sorted( set( pins ) - set( live ) ) ) )
drift = [ n for n in sorted( set( live ) & set( pins ) ) if live[ n ] != pins[ n ] ]
for n in drift[ :5 ]:
    print( "  FAIL  (2) %s first sentence moved:\n          pinned: %s\n          live:   %s"
           % ( n, pins[ n ][ :180 ], live[ n ][ :180 ] ) )
check( not drift, "(2) every routing sentence is byte-identical to its pin (%d checked)" % len( pins ) )

# A description that is ONLY its first sentence has nothing left to say about its arguments; a description
# whose first sentence is most of its bytes has not been trimmed, it has been truncated. Both are shapes a
# size ceiling alone would reward, so the ceiling is paired with a floor.
thin = [ t[ "name" ] for t in tools if len( t[ "description" ] ) < len( live[ t[ "name" ] ] ) + 20 ]
check( not thin, "(2) no description was reduced to its routing sentence alone (%s)" % ( ",".join( thin ) or "none" ) )

# ── 3. ROUTING SCORE, re-measured ─────────────────────────────────────────────────────────────────────
# The manifest exists to make an agent pick the right verb. --eval-skills is the harness that measures
# that on the shipped prompt set; a trim that keeps every sentence and still hurts routing fails here.
fixture = os.path.join( ROOT, "test", "skillevalfix", "prompts.tsv" )
if not os.path.exists( fixture ):
    print( "  SKIP  (3) routing eval: %s absent" % fixture )
else:
    r = subprocess.run( [ BIN, "skills", "--eval-skills=" + fixture ], capture_output = True, text = True, cwd = ROOT )
    m = re.search( r"(\d+)\s*/\s*(\d+)", r.stdout + r.stderr )
    if not m:
        print( "  SKIP  (3) routing eval produced no N/M score to read" )
    else:
        got, tot = int( m.group( 1 ) ), int( m.group( 2 ) )
        print( "  INFO  (3) --eval-skills routing score %d/%d" % ( got, tot ) )
        check( r.returncode == 0, "(3) --eval-skills exits 0 (its own pass bar) at %d/%d" % ( got, tot ) )

print( "" )
if fails == 0: print( "ALL PASS" )
else:          print( "%d CHECK(S) FAILED" % fails )
sys.exit( 1 if fails else 0 )
PY

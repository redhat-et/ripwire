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
# RE-ANCHORED 2026-09-10 (--edit-check answer-safe window): 41,000 → 41,300, measured 41,129 (from 40,895).
# TWO declared optional arguments, `limit` and `offset`, on ONE verb — `edit_check`, which now honors them
# (it windows its UNFLAGGED caller rows; the flagged callers, their sites_l= and the def census are never
# paged, so the verdict cannot be paged away). Attributed against a build of the parent commit: edit_check
# +234 B and nothing else moved — 92 B for the `limit` property entry and 92 B for `offset` (the schema
# envelope plus the description arm (A/M12) obliges every declared property to carry), plus the 49 B clause
# in the tool description that says WHAT they page, without which a router reads a paging verb whose page is
# undefined. Same rule as the two re-anchors above (a DECLARED argument, its bytes attributed here, in the
# commit that lands it, never prose) and the same posture: 171 B of headroom, less than one more argument.
# RE-ANCHORED 2026-09-10 (C1 F-07/F-10, the listing-paging round): 41,300 -> 42,000, measured 41,830 (from
# 41,220). TWO declared optional arguments, `limit` and `offset`, on TWO verbs — `flags` and
# `situational_awareness`, which joined cli.h's honorsPaging set in the same commit (--flags windows the read
# SITES under a gate and --flip its six context listings; --situ windows its blast-radius and co-change
# sections — in both, the answer rows, the gate rows and tests_to_run, are never paged). Attributed tool by
# tool against a build of the parent commit (6afaa457), by this gate's own metric:
#   flags                  +329 = +184 B schema (92 for the `limit` property entry, 92 for `offset`: the
#                                 envelope plus the description arm (A/M12) obliges every declared property
#                                 to carry) +145 B of description, the clause saying WHAT they page — this
#                                 verb has TWO lenses (the gate table and --flip), and a router that cannot
#                                 tell which rows page from which rows are the answer has an undefined page
#   situational_awareness  +281 = +184 B schema, same two entries, +97 B of description — shorter because
#                                 the clause has one lens to describe, and it has to say the DEFAULT differs
#                                 from the CLI's (unbounded here; the payload always served every row, so
#                                 limit is relief for a caller who wants less, never a new cut)
#   nothing else moved.
# Same rule as the three re-anchors above (a DECLARED argument, its bytes attributed here, in the commit
# that lands it, never prose) and the same posture: 170 B of headroom, less than one more argument entry.
#
# RE-ANCHORED 2026-09-10 (MCP no_route, audit F-R1-07): 41,300 → 41,650, measured 41,474 (from 41,220).
# ONE declared optional argument, `no_route`, on the TWO verbs that ROUTE — `for` and `explore` (and its
# `pack_task` alias, which shares explore's stanza) — the MCP twin of the CLI --no-route. Attributed against
# a build of the parent commit: schemas 17,161 → 17,415 B (+254, two property stanzas at +127 each: the
# schema envelope plus the description every declared property is obliged to carry) and DESCRIPTIONS
# BYTE-IDENTICAL at 19,632 B. A first draft added a pointer clause to both tool descriptions (+43 B after
# trimming to one); it was removed rather than re-anchored around, because this file's rule is that the
# ceiling moves for a declared argument's obliged bytes and never for prose, and the schema property is
# where a client renders an argument anyway. Same posture as the three re-anchors above: 176 B of headroom.
# What it buys: `for`'s header names WHICH ranker answered and why, and until now an agent that read route=
# and disagreed had no way to ask for the other one — the CLI's own recovery from a route mis-fire was
# unreachable from MCP (measured: --for="parse tree" on this repo routes name-exact and returns three rows
# from bench/ and test/, missing parseTree, which --no-route finds at rank 1).
#
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
#     receipt). Also recorded for the owner in the round's local plan notes, which are never tracked here.
#
# RE-MEASURED 2026-09-07 (issue #48), CEILING UNMOVED at 41,000 — recorded because this file's rule is that
# the arithmetic gets written down, not because anything was spent. The fix that removed exemplar's
# top-level `anyOf` (the Anthropic tool-schema validator refuses oneOf/allOf/anyOf at the top level of a
# tool input schema, so that one stanza made the server un-registerable in opencode and every other
# strict client) lands NET NEGATIVE. Attributed tool by tool against a build of the pre-fix head
# (93b7525a), on this gate's own metric:
#   exemplar     +28 = +96 B of description prefix (the requiredness the keyword used to express, now on
#                      each of the two members — see src/mcprefusal.h anyOfDescriptionPrefix, and it is
#                      the ONLY surface a strict client can still read it from) −54 B keyword −14 B
#                      empty `required`
#   nine verbs   −14 each = −126 B: analyze situational_awareness owners quality_delta quality_baseline
#                      stray_content flags doc_drift (and exemplar, counted above) now OMIT `required`
#                      instead of emitting `[]` — identical meaning from draft-06 on, and the empty array
#                      is what draft-04-strict validators reject
#   TOTAL        40,986 -> 40,902 B; nothing else moved. Raw wire bytes (this gate measures json.dumps
#                      with ensure_ascii, which spends 6 for each em dash instead of 3): 40,901 -> 40,811.
# Headroom goes back UP, 14 B -> 98 B. That is item 5 below working, not a new allowance.
# RE-ANCHORED 2026-09-10 (the string/perf round's integration, two lanes each declaring arguments):
#   for, explore      +127 B each = +254 B: `no_route` (mirrors the CLI --no-route so an MCP agent that reads
#                      route= and disagrees has a recovery path — R1 finding F-R1-07)
#   flags             +329 B (+145 B description, `limit`/`offset` properties): the dark-flag site listing and
#                      the six --flip listings join the paging family and disclose their cuts (C1 F-07)
#   situational_awareness +281 B (+97 B description, `limit`/`offset`): --situ's blast-radius and co-change
#                      listings page instead of cutting silently at 8 (C1 F-10)
#   TOTAL             41,220 -> 42,084 B on the merged tree, attributed tool by tool against main's binary
#                      (both lanes had re-anchored alone — 41,650 and 42,000 — and the sum is what ships).
# Headroom after this line: 116 B, less than one declared argument, which is rule 5 above working.
# RE-ANCHORED 2026-09-12 (lane for-widen, L-W): 42,200 → 42,384 = +184 B, EXACTLY the two declared optional arguments
# `limit`/`offset` on `for` (the `for` schema 525 → 709 B in this arm's own json.dumps metric: the envelope plus the
# description the contract obliges each property to carry), measured against a build of the lane's base (1cf3086e:
# 42,177 B here, 23 B under the old ceiling) — the file-grain widening page (forpage.h) joins the paging family on
# this twin. Its description gained NO prose: a first draft named coverage= and the page there (+109 B) and was
# removed rather than re-anchored around, the L7 precedent above — the schema properties are where a client renders
# an argument, and the answer's own legend defines coverage= and the page. Headroom after this line: 23 B.
#   RE-ANCHORED 2026-09-13 (PR #215, owner question "how does an agent ask for the longer answer"): 42,200 -> 42,700,
#   measured 42,636 B. The `legend` field's description gains one clause — "full (restores the full legend)",
#   +32 B on each of the 17 tools that declare the field (+544 B) — so the schema an agent reads when choosing the
#   argument's value says what "full" does. This is PROSE on a declared argument, which rule 5 above does not move
#   the ceiling for; the owner asked for exactly this clause and authorized moving the pin with the measured number
#   (2026-09-13 06:30), and that authority and this attribution are the whole justification. Headroom after: 64 B.
#   MERGED 2026-09-13 (lane/sc-legend + lane/for-widen): both anchors above are real and they add. 42,200 -> 42,900,
#   RE-MEASURED on the merged tree at 42,820 B (descriptions 19,967, schemas 18,426, 31 tools), not summed from the two
#   lanes' separate anchors (42,384 and 42,700), because neither lane could see the other's bytes. Headroom after this
#   line: 80 B, less than one declared argument, which is rule 5 above working.
# RE-ANCHORED 2026-09-13 (review of #214): 42,384 → 42,800 = +416 B, EXACTLY the one 207-byte clause plus the
# single space that separates it from the sentence before it (208 B), spliced into EACH of the TWO tool
# descriptions that serve tests_to_run rows as JSON — `situational_awareness` and `explore`; 2 × 208 = 416
# (measured against a build of ff8d77a1: 42,361 B here, 23 B under the old ceiling). It is NOT the L7 case the
# line above declines. That one removed prose describing an ARGUMENT, because the schema properties are where a
# client renders an argument and the answer's own legend defines the rest. This clause describes the RESPONSE:
# E1 made a tests_to_run row's `p` a path string OR an array of paths beside `n`, and these two answers carry
# no legend of any kind — `situational_awareness` returns bare JSON with no vocabulary block — so a caller that
# parses `p` as a string has nowhere else to learn otherwise before it breaks. ONE wording (mcp.h
# kTestRowJsonShapeClause), spliced twice, never a third paraphrase. Headroom after this line: 23 B.
# RE-ANCHORED 2026-09-13 (CodeRabbit on #214): 42,800 -> 43,000 = +200 B for a MEASURED +196, the clause 207
# -> 305 B plus its one-space separator, in each of the same two descriptions (2 x 98). The first wording
# named the key `p` and only one of the three producers spells it that way: situational_awareness emits
# `test` (mcpverbs.h), explore (packtask.h) and the edit receipt (mcpedit.h) emit `p`. A clause that names
# the wrong key is worse than no clause, because a caller reads it as a contract — so it now names both, per
# producer, and everything the three DO share (string-or-array, `n` beside an array, run/run_unknown) is
# still said once. The quotes around the two keys are SINGLE: this string is spliced straight into the
# tools/list JSON, and the first draft's double quotes made the manifest unparseable — which this gate
# caught as a JSONDecodeError, not as a byte count. Measured 42,973. Headroom after this line: 27 B.
# MERGED 2026-09-14 (lane/sc-legend + main at 0b118ac1): 43,000 -> 43,500, RE-MEASURED on the merged tree at
# 43,432 B (descriptions 20,579, schemas 18,426, 31 tools). NEITHER side's ceiling holds and neither is wrong:
# this lane re-anchored to 42,900 from a measurement of 42,820, #214 re-anchored to 43,000 from 42,973, and
# the two clauses are DIFFERENT bytes in different stanzas, so they add. Not summed from the two anchors —
# the lanes did not share a base and neither could see the other's bytes — and not derived from the deltas
# either; measured on the tree that ships, the 2026-09-10 two-lane precedent above verbatim. No NEW allowance
# is taken here: both adds were justified where they landed (this lane's is prose on a declared argument the
# owner authorized on 2026-09-13 with the measured number; #214's names the response shape for two answers
# that carry no legend at all), and the merge only makes them visible together. Headroom after this line:
# 68 B, again less than one declared argument, which is rule 5 above working.
# RE-ANCHORED 2026-09-19 (lane/t10-mcp-coverage): 43,500 -> 46,600, measured 46,371 (from 43,432, 31 tools).
# TWO NEW ADVERTISED TOOLS, not a prose trim: `rank_by` (the --rank-by=pagerank|authority|hub|rrf MCP twin)
# and `affected` (the --affected=F1,F2|SYM MCP twin) — closing the exact ref-eligibility gap
# graft-iter2a.md §9 measured (these two verbs had no MCP form at all). Each carries a routing sentence
# (pinned below) plus its own declared argument list, same as every tool already in the manifest.
# Attributed tool by tool against a build of origin/main (561636336): rank_by +636 B description +481 B
# schema = 1,117 B; affected +790 B description +610 B schema = 1,400 B; the remaining +422 B is JSON
# envelope structure (two more {"name":…,"annotations":{…}} objects in the tools array, not counted in
# either sum above) — 2,939 B in all, nothing else moved. Same rule as every entry above: the ceiling moves
# UP only for a DECLARED tool or argument the contract obliges to carry a description, in the commit that
# lands it, with its bytes attributed here — never for prose. Headroom after this line: 229 B.
# RE-MEASURED 2026-09-19, TRAIN 10 (integration/train-10 on main 59b241d7): 46,371 B on the merged tree —
# the lane's number reproduces exactly, and the ceiling is unmoved at 46,600 with the same 229 B of headroom.
# The BASE reading in the line above is the one that does not reproduce. Measured here with THIS file's own
# formula against three builds — 56163633 (the lane's base), 1b772eac and 59b241d7 (main) — all three answer
# 43,500 B, descriptions 20,579, schemas 18,494, 31 tools. The 43,432 B / schemas 18,426 B pair has been
# carried in this block since 2026-09-14 and the lane copied it forward; descriptions match to the byte on
# every build, so the 68 B sits in the schemas alone and predates both sides of this train. Two consequences,
# neither of them a defect in the lane: the pre-lane manifest was sitting EXACTLY on the 43,500 ceiling with
# zero headroom rather than the 68 B this block claimed (the arm asserts <=, so it passed on the number, not
# on the margin), and the delta this train lands is 2,871 B rather than 2,939. The per-tool attribution above
# is unaffected — it was measured tool by tool, not as a difference of two totals.
# TRAIN 10 FIX ROUND (CodeRabbit 4056211645): 46,371 -> 46,493 B, the ceiling UNMOVED at 46,600. The rank_by
# description claimed its default was "byte-identical to 'analyze'", which is false on a tree with uncommitted
# changes — `analyze` serves the warm index's working-set-PERSONALIZED rank and rankByText deliberately does
# not, which is the divergence that lane fixed. +122 B of description to say what is true instead; no schema
# byte moved and no tool was added. Spent from the 229 B this block already held, not from a raise: correcting
# a claim the manifest itself makes is what headroom is for. Headroom after this line: 107 B.
# RE-ANCHORED 2026-10-03 (lane/refval-edges, reference-as-value rows): 46,600 -> 46,750, measured 46,722 (from 46,581,
# 33 tools). The #214 precedent above, not the L7 one: these clauses describe the RESPONSE of two answers that carry no
# legend of any kind. find_symbol and find_referencing_symbols now serve `valueRefs` (and find_symbol `valueCallees`):
# a function USED AS A VALUE — stored in a dispatch table or passed as an argument — which is NOT a call. A JSON client
# that met those keys with no reading would sum them into its callers; the one place an MCP client reads prose is this
# description, so each says "value uses (tables, args), not a proven call" (+70 B and +71 B, 141 B in all, no schema
# byte moved, no tool added). Headroom after this line: 28 B (the final review tightened a first 46,800 anchor to the
# #214-sized margin: 78 B of unattributed headroom was wider than any re-anchor here has taken).
# RE-ANCHORED 2026-10-04 (lane/lean-answers-068): 46,750 -> 46,850, measured 46,828 (from 46,732, 33 tools). ONE DECLARED
# ARGUMENT, no prose: whereis takes `listing` (defs|refs|all, the CLI --whereis-listing= twin), whose default (defs) lists the
# definitions and counts the references. Attributed: whereis schema 714 -> 810 B (+96 B, the field and its obliged
# description), whereis description unchanged at 701 B, every other tool unchanged. Headroom after this line: 22 B.
# RE-MEASURED 2026-10-07 (lane/lean-answers-068 fix round 1), CEILING UNMOVED at 46,850: 46,828 -> 46,846 B. The listing
# field's description now says what its default does ("defs (refs counted), refs or all; default: the shorter page":
# absent `listing` serves the defs page only when it is strictly shorter than the all page), +18 B in whereis's schema;
# every other tool unchanged. Headroom after this line: 4 B.
# RE-ANCHORED 2026-10-08 (lane/lean-answers-068 fix round 2, review D1): 46,850 -> 46,890, measured 46,869 (from 46,846,
# 33 tools). The default `listing` is no longer "the shorter page": absent `listing` serves the defs page when it lists MORE
# definitions than the all page under the row cap (a capped all page can list fewer), whatever its bytes, and otherwise the
# strictly shorter of the two. The field's description follows the mechanism, "default: the shorter page" ->
# "default: more defs listed, else the shorter page" (+23 B, the minimum that is true). Attributed: whereis schema 828 -> 851 B
# (+23 B), whereis description unchanged at 701 B, every other tool unchanged. Headroom after this line: 21 B. The twin below
# (1c) pins what must not move with it: whereis's description stays 701 B and the listing field says the exact rule.
# RE-ANCHORED 2026-10-07 (lane/cr-qd-kinds-068, the twelfth --quality-delta kind): 46,750 -> 46,800, measured 46,793 (from
# 46,732, 33 tools). The #214 precedent again: the clause describes the RESPONSE. quality_delta's description now
# counts 12 kinds (its "11 measured failure modes" became "12 kinds", -16 B), names the new kind ("a defect shape",
# +16 B), and states the one row family that gates on new code — "new-symbol rows never gate, except defect-shape
# format-arity" (+61 B) — because an MCP client reading "gating" would otherwise take a gating new-symbol row for a
# contradiction of the description. No schema byte moved, no tool added. Headroom after this line: 7 B.
# RE-ANCHORED 2026-10-08 (train 26b, the final regeneration): 46,890 -> 46,950, measured 46,930 (33 tools). The two
# re-anchors above were measured on different bases — lean-answers 46,869 (whereis `listing`), cr-qd-kinds 46,793 (from
# 46,732: the quality_delta description's twelfth kind, +61 B) — and the merged tree carries both: 46,869 + 61 = 46,930,
# every byte attributed (whereis schema 851 B and quality_delta's description as their lanes measured them; no other
# tool moved; knob-honesty and the path-gap fix touch no tool description or schema). Headroom after this line: 20 B.
# RE-MEASURED 2026-10-10 (lane whereis-defs-fix fix round 2), CEILING UNMOVED: 46,930 -> 46,925 B. whereis's description says
# what labels another ref's row now (a parser, not a lexical heuristic) in the same 701 characters — (1c) holds — and the
# sentence it replaced carried an em dash, six bytes as JSON. Every other tool unchanged. Headroom after this line: 25 B.
CEILING = 46950
manifest = len( json.dumps( { "tools": tools }, separators = ( ",", ":" ) ) )
descBytes   = sum( len( t[ "description" ] ) for t in tools )
schemaBytes = sum( len( json.dumps( t[ "inputSchema" ], separators = ( ",", ":" ) ) ) for t in tools )
print( "  INFO  %d tools, manifest %d B (~%d tokens): descriptions %d B, schemas %d B"
       % ( len( tools ), manifest, manifest // 4, descBytes, schemaBytes ) )
check( manifest <= CEILING,
       "(1) tools/list is %d B, within the %d B per-session ceiling" % ( manifest, CEILING ) )

# (1c) TWIN of the ceiling re-anchor (PROCESS rule 4): the growth is the listing field's description and nothing else.
whereisTool = [ t for t in tools if t[ "name" ] == "whereis" ]
check( len( whereisTool ) == 1 and len( whereisTool[ 0 ][ "description" ] ) == 701,
       "(1c) whereis's own description is still 701 B (the re-anchor was spent in the listing field, not in prose)" )
listingDesc = whereisTool[ 0 ][ "inputSchema" ].get( "properties", {} ).get( "listing", {} ).get( "description", "" ) if whereisTool else ""
check( listingDesc.endswith( "default: more defs listed, else the shorter page" ),
       "(1c) whereis's listing field states the default rule exactly (got: %r)" % listingDesc )

# ── (1b) the CHANGELOG's own copy of this figure does not silently rot ──────────────────────────────
# train10.md's "manifest anchor" finding: the byte figure above lives in two places — this file's own
# RE-ANCHORED/RE-MEASURED comment history (checked live, every run) and CHANGELOG.md's prose restating it
# for readers. The comment history is self-correcting because it is this script; the CHANGELOG copy is not
# — it sat wrong for five days (43,432 carried forward as 43,500) before a lane happened to re-derive it by
# hand. While the entry is still under [Unreleased] (mutable — later work can still move the manifest before
# release), assert the CHANGELOG's stated post-change byte count against the SAME live measurement above, so
# a future change that moves the manifest without updating CHANGELOG's prose is a red here, not a rediscovery.
# Once the entry rolls under a dated release heading it is a historical record of what was true when it was
# measured, same as the dated blocks train10.md declined to touch, so this only reads inside [Unreleased].
changelog = open( os.path.join( ROOT, "CHANGELOG.md" ), encoding = "utf-8" ).read()
_, _, afterHeading = changelog.partition( "## [Unreleased]" )
unreleased = afterHeading.split( "\n## [", 1 )[ 0 ]  # [Unreleased]'s body, up to the next dated heading
m = re.search( r"tools/list.? manifest grows [\d,]+[^\d]+([\d,]+) B", unreleased )
if m is None:
    print( "  INFO  (1b) no 'tools/list manifest grows N -> N B' claim in CHANGELOG's [Unreleased] section (nothing to check)" )
else:
    claimed = int( m.group( 1 ).replace( ",", "" ) )
    check( claimed == manifest,
           "(1b) CHANGELOG's [Unreleased] manifest-growth claim (%d B) matches the live tools/list measurement (%d B)"
           % ( claimed, manifest ) )

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

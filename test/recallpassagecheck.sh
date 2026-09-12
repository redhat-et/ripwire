#!/usr/bin/env bash
# recallpassagecheck.sh — the passage-serving gate for --recall. The defect it pins: a document's
# ranked sections are picked correctly, then thrown away by a document-order prefix cut before the
# reader ever sees them (see the per-arm table below). WRITTEN BEFORE THE FIX EXISTED — CLAUDE.md non-negotiable #1 ("write the gate before the code it measures"). Lane L1 builds
# src/recall.h's section path against this gate as the contract; this file and
# test/fixtures/recallpassage/** are that lane's whole footprint.
#
# MEASURED against build/ripwire at 113c7aea (the main tip this design branched from), 2026-09-08, on
# macOS/AppleClang — reproduced with the exact commands each arm below runs. Recorded here so a future
# reader (L1, or anyone re-running this gate) can tell a REAL fix from a gate that was always green:
#
#   ARM  TODAY   WHAT HAPPENED
#   P1   FAIL    large_late_answer.md (340,821 B; one matching file), target section (890 B, heading at
#                line 858) sits at the 95th percentile of 300 headed sections, all of which score > 0.
#                --max-tokens=2000: 3,963 B emitted, the answer sentinel is ABSENT. buildSectionGranularBody
#                keeps 300 of 301 sections (all positive-scoring, none overlap — flat H2 structure), then
#                RE-SORTS them to document order and concatenates; truncateRecallBody prefix-cuts that
#                document-ordered string, landing inside "Section 0000" — nowhere near "Section 0285",
#                even though ranking (verified via --for) puts Section 0285 at r=1.
#   P2   FAIL    same fixture, --max-tokens in {1500,3000,8000,40000}: sentinel ABSENT at ALL FOUR —
#                even 84,658 B (40000 tok, ~95x the 890 B the answer alone would need) does not reach it.
#                Not "present only at large budgets" — present at NONE of them.
#   P3   PASS    small_fits.md (261 B; the matched content is comfortably under the 8000-tok default):
#                output is byte-identical to test/fixtures/recallpassage/small_fits.golden.
#
#                THE ORIGINAL SPEC FOR THIS ARM WAS WRONG, and the arm is the evidence. It asked for
#                byte-identity against the PRE-FIX binary whenever the budget does not bind — but the
#                fix redefines what a unit IS, so the two cannot both hold. On this very fixture the pre-fix overlap loop
#                dropped `# Widget cache notes` because its span (1-9) contained the matching
#                subsection; that heading's own prose carries "widget" and "cache" and was unreachable
#                at ANY budget. Post-fix it is a two-line unit of its own and the output legitimately
#                grows by those two lines. The golden is therefore re-captured from the POST-fix
#                binary, and what this arm pins now is the property that is both available and worth
#                having: a non-binding budget is byte-STABLE — no unit selection, note form or lines=
#                list may move while nothing is being cut. That still fails loudly on accidental
#                drift; it just no longer asserts the equivalence the fix was commissioned to break.
#   P4   FAIL    the disclosed `lines="..."` attribute on large_late_answer.md is BYTE-IDENTICAL at
#                --max-tokens=3000 and --max-tokens=200000 (299 ranges, same text, both times) — it is
#                computed once in LOAD before the budget is known (the pre-fix LOAD path), so it
#                never moves regardless of how much the budget grows.
#   P5   FAIL    (a) NO --recall output today carries a `dropped_by_budget=` attribute or the
#                "S of R selected (N in doc)" note shape the disclosure contract specifies — grep absence, not a wrong
#                value: the disclosure surface does not exist yet.
#                (b) at --max-tokens=2000, `lines=` names 300 ranges; checked against the fixture file
#                DIRECTLY (ground truth independent of ripwire, matching recallanchorcheck.sh's
#                convention) only 1 of the 300 named ranges (Section 0000, the document's first) is
#                actually present in the emitted body. 299 named ranges describe text that was never sent.
#   P6   PASS    the same command run twice at --max-tokens=4000 is byte-identical — the standing
#                determinism contract (unrelated to this defect) and it must stay green throughout.
#   P7   FAIL    nested_headings.md, --max-tokens=1000000 (budget not binding — isolates defect B from
#                defect A): the one kept range is `lines="11-23"` ("### Beacon module") and it CONTAINS
#                line 16 ("#### Vortex tuning procedure", Beacon's own child, and the section that
#                literally contains the query's exact phrase). Vortex ranks #2 by --for and gets dropped
#                by buildSectionGranularBody's overlap-drop as "overlapping" its kept parent — whose span
#                reaches to EOF because nothing follows it at an equal-or-shallower heading depth, so it
#                swallows every descendant it has (the ancestor-swallows-descendants root cause).
#   P8   PASS    degenerate_single.md, --max-tokens=500 (the doc's one matching section is bigger than
#                its share): shown=1, `[truncated: 422 of 15866 bytes]` is disclosed — nothing is silently
#                dropped to shown=0. A single-candidate document has no "front matter vs top-ranked unit"
#                distinction to get wrong, so today's document-order cut and the fix's rank-order cut
#                degenerate to the same cut here. Deliberately NOT where the defect shows; must stay
#                green after the fix too (the fix's own degenerate case).
#
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# P9 / P10 / P11 — added 2026-09-08 after an adversarial review PROVED the arms above cannot see three
# further defects. Each new arm ships with a mutation that was RUN, not reasoned about (CLAUDE.md
# non-negotiable #1: a gate you did not observe fail is not evidence). Re-run any of them by editing
# src/recall.h as shown, `cmake --build build -j`, `bash test/recallpassagecheck.sh`, then
# `git checkout src/recall.h`. Plain build only — never -DCMAKE_BUILD_TYPE=Release.
#
#   MUTATION AND THE STATE EVERY ARM WAS OBSERVED IN         RUN 2026-09-08, THIS WORKTREE, PLAIN BUILD
#   M1  admitRecallUnits walks document order instead of rank order:
#         `for( const std::uint32_t u : sec.rankOrder )`
#           -> `for( std::uint32_t u = 0; u < sec.units.size(); ++u )`
#       RED: P1 (reachability — the pre-existing arm, still doing its job), P2, and P10's CONTROL half
#       (the keyword phrasing stops serving the answer too, so P10 says the control failed and refuses
#       to draw a parity conclusion — which is the behaviour that arm owes).
#       GREEN, and correctly so: P4 (a document-ordered admission is still monotone in the budget) and
#       P9 (the note's arithmetic is honest about a WRONG selection — exactly the seam P9 is not for,
#       and P1 is).
#   M2  the §RP3.1 ancestor rule always keeps:
#         `if( hasScoringDescendant` -> `if( false && hasScoringDescendant`
#       GREEN: P1 through P9, every one of them. P7 measures NESTING, and a tiling satisfies it whatever
#       the rule keeps; P9 measures arithmetic, which stays self-consistent over a wrong selection.
#       RED: test/recallanchorcheck.sh arm (v), restored in the same commit as these arms, and the
#       pre-existing test/mdsectioncheck.sh. THIS GATE DOES NOT COVER THE ANCESTOR RULE — recorded so
#       nobody re-derives that it does. (P10's control half also goes red under M2, but P10 is red
#       today for its own reason, so it is not evidence until lane F1 lands.)
#   M3  the disclosure number lies by one:
#         `note += "; dropped_by_budget=" + std::to_string( selectedCount - emittedCount );`
#           -> `... std::to_string( selectedCount - emittedCount + 1 );`
#       BEFORE P9 existed: the whole gate stayed GREEN — the reason P9 exists. P5a only regex-matches
#       the FORMAT `dropped_by_budget=[0-9]+`, so any integer at all satisfied it, and a 1,380-run
#       sweep confirming the shipped value is correct proved nothing about the gate that measured it.
#       WITH P9: RED at 9 of the 14 swept cases, each named — e.g. "[P1 large@2000]:
#       dropped_by_budget=298, expected R-S=297 (S=3 R=300)". P5a stayed GREEN throughout, which is
#       the point: a format arm cannot stand in for an identity arm. No other arm changed state.
#   M4  the lines= list stops naming exactly the emitted units — one extra range, added at the end of
#       composeRecallUnits on the line before its `return`:
#         `if( !linesAttr.empty() ) { linesAttr += ",1-1"; }`
#       WITH P9: RED at 11 of the 14 swept cases, on the identity, named — e.g. "[P1 large@2000]:
#       lines= names 4 ranges, expected S=3". P3 and P5b also go red INCIDENTALLY (a bogus range
#       perturbs a golden and a presence scan) but neither states the identity, and neither fires on M3.
#       The three cases M4 does NOT reach are the degenerate prefix cuts (P8, P11, and — today — P10's
#       keyword control): that branch builds lines= itself and never calls composeRecallUnits.
#   SIM  lane F1's fix for P11, simulated here to prove the arm is SATISFIABLE and not merely red — in
#       emitRecallSectionUnits, `keptHi` stops counting the kept prefix's trailing newline as opening a
#       further line:
#         `const std::uint32_t keptHi = top.lineLo + count( kept, '\n' );`
#           -> `nl = count( kept, '\n' ); if( nl > 0 && kept.back() == '\n' ) --nl; keptHi = lineLo + nl;`
#       P11 goes GREEN ("lines= ends at 8, the line containing the last served byte"), P1-P9 stay green,
#       and all eleven sibling recall gates plus mdsectioncheck stay green. Reverted; this is a
#       measurement, not a proposal — src/recall.h belongs to lane F1.
#
#   P9   PASS    (post-fix; M3/M4 above are the RED runs) the two disclosure IDENTITIES, swept over
#                every section-granular note this gate produces: `dropped_by_budget == R - S`, and
#                `S == the number of ranges in lines=`. P5a checks the fields EXIST; P9 checks they are
#                the numbers they claim to be.
#   P10  FAIL    NATURAL-LANGUAGE PARITY — lane F1's fix, landing concurrently; this arm is EXPECTED RED
#                until it does. docs/ARCHITECTURE.md alone in a directory, --max-tokens=800:
#                  --recall="crawl order sorted before ids assigned"                -> lines="353-369"
#                  --recall="how does the crawl order get sorted before the ids are assigned"
#                                                                                   -> lines="1-11,12-20"
#                Same question, one phrased in keywords and one in English, and the English one drops
#                the answer entirely — it also selects 13 of 13 sections instead of 8, i.e. the stopwords
#                make every section score. The arm is phrased against the ANSWER'S OWN SOURCE LINE, found
#                by scanning the fixture copy, so it says "both phrasings serve the unit that CONTAINS
#                the answer" rather than pinning a line number that doc drift would silently move.
#                CORPUS PINNED 2026-09-11: the document is now ARCHITECTURE.md as of blob P10_CORPUS_BLOB
#                (c166bb4f, the file at d752d953), not the live file; the ranges above were measured on the
#                live copy of 2026-09-08. Line drift turned out not to be the only drift — see the P10 corpus note.
#   P11  FAIL    DEGENERATE-CUT HONESTY — also F1's, also EXPECTED RED until it lands. The one surviving
#                prefix cut (emitRecallSectionUnits' `admittedCount == 0` branch) recomputes lines= by
#                counting the '\n' bytes in what survived and adding that to lineLo. A kept prefix that
#                ends ON a newline — which every boundary-aligned cut does — therefore names one line
#                MORE than it served. Measured: `## Only matching section` at line 3 followed by 400
#                two-line paragraphs, --max-tokens=400, claims lines="3-9" while `[truncated: 162 of
#                27226 bytes]` puts the last served byte on line 8.
#                A note on the correct value, because it is a real fork and this arm hard-codes an answer:
#                hi is the line CONTAINING THE LAST SERVED BYTE (8), not the last line with visible text
#                on it (7). That is the rule the non-degenerate path already uses — RecallSectionUnit's
#                `lineHi = layout::lineOf( raw, p.ownEndByte - 1 )` — and test/recallanchorcheck.sh's
#                independently-computed ground truth agrees: its Kafka span is 5-8, where line 8 is the
#                BLANK line before the next heading. A degenerate cut answering 7 would be the only place
#                in the system where a trailing blank line stops counting.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/recallpassagecheck.sh    (no positional arguments — this
#         repo's gates take none; see test/regression.sh's absorb loop, which is how this gate is run)
#         RIPWIRE_BIN=build_base/ripwire bash test/recallpassagecheck.sh   # a pre-fix binary must show
#                                                                           # the FAIL table above

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fixtures/recallpassage"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
for f in large_late_answer.md nested_headings.md small_fits.md degenerate_single.md small_fits.golden; do
    [ -f "$FIX/$f" ] || { echo "missing fixture: $FIX/$f — regenerate test/fixtures/recallpassage/"; exit 2; }
done
# P10's corpus: docs/ARCHITECTURE.md as it stood at d752d953, read by BLOB id — see the P10 corpus note below.
P10_CORPUS_BLOB="c166bb4f5f723face414844539c4e51dbabaff62"
git -C "$ROOT" cat-file -e "$P10_CORPUS_BLOB^{blob}" 2>/dev/null || { echo "missing git blob $P10_CORPUS_BLOB (docs/ARCHITECTURE.md at commit d752d953) — P10's corpus is that blob; CI checks out full history (fetch-depth: 0), so run this gate from a full clone, not a shallow one or a copy without .git"; exit 2; }

echo "recallpassagecheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# run DIR QUERY [extra ripwire flags...] — stdout is returned by the caller's redirect; stderr parked
# at $TMP/err. alarm-wrapped like every sibling recall*check.sh (a hung run must not hang the suite).
run(){
    local dir="$1" q="$2"
    shift 2
    perl -e 'alarm 60; exec @ARGV' "$BIN" "$dir" --recall="$q" --no-cache "$@" 2>"$TMP/err"
}

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# P9's checker, defined here so every arm below can enrol its own output as it produces it. `discl LABEL
# FILE` parses EVERY `[sections: …]` note in FILE and asserts the two identities the note's numbers must
# satisfy. A failure is reported at the point of use, where the label says WHICH case broke; the running
# tallies feed P9's summary at the end, which is what states the COVERAGE.
#
# Why identities and not a format match: P5a already greps `dropped_by_budget=[0-9]+`, and an adversarial
# review showed that mutating the source to emit R-S+1 leaves this whole gate green. A disclosure the
# reader cannot check is worth less than no disclosure, because it is believed.
#
# The two forms formatRecallSectionNote can print, and what each owes:
#   unbound  `[sections: R of N, section-granular; whole doc W B; lines="…"]`
#            R ranges in lines=, R <= N, and NO dropped_by_budget (silence means nothing was dropped).
#   bound    `[sections: S of R selected (N in doc), …; lines="…"; dropped_by_budget=D]`
#            S ranges in lines=, D == R - S, S < R <= N.
# A note matching NEITHER shape is itself a failure — that is how a mutation which deletes the attribute
# outright is caught, rather than being read as "the unbound form, which owes nothing".
DISCL_LABELS=""
DISCL_N=0
DISCL_FAIL=0
discl(){
    local label="$1" file="$2"
    DISCL_LABELS="$DISCL_LABELS
        $label"
    DISCL_N=$(( DISCL_N + 1 ))
    local res
    res="$( python3 - "$label" "$file" <<'PY'
import re, sys

label, path = sys.argv[1], sys.argv[2]
text  = open( path, encoding = "utf-8" ).read()
notes = re.findall( r'\[sections: [^\]]*\]', text )
if not notes:
    print( "NONOTE" )
    raise SystemExit

BOUND   = re.compile( r'^\[sections: (\d+) of (\d+) selected \((\d+) in doc\), section-granular; '
                      r'whole doc (\d+) B; lines="([^"]*)"; dropped_by_budget=(\d+)\]$' )
UNBOUND = re.compile( r'^\[sections: (\d+) of (\d+), section-granular; whole doc (\d+) B; lines="([^"]*)"\]$' )

def ranges_of( s ):
    return [ r for r in s.split( "," ) if r ]

bad = []
for n in notes:
    mb, mu = BOUND.match( n ), UNBOUND.match( n )
    if mb:
        S, R, N, _W, lines, D = int( mb[1] ), int( mb[2] ), int( mb[3] ), int( mb[4] ), mb[5], int( mb[6] )
        rs = ranges_of( lines )
        if D != R - S:      bad.append( f"dropped_by_budget={D}, expected R-S={R - S} (S={S} R={R})" )
        if len( rs ) != S:  bad.append( f'lines= names {len(rs)} ranges, expected S={S}' )
        if not S < R:       bad.append( f"bound form printed with S={S} not < R={R}" )
        if R > N:           bad.append( f"selected R={R} exceeds N={N} sections in doc" )
    elif mu:
        R, N, _W, lines = int( mu[1] ), int( mu[2] ), int( mu[3] ), mu[4]
        rs = ranges_of( lines )
        if len( rs ) != R:  bad.append( f'lines= names {len(rs)} ranges, expected R={R}' )
        if R > N:           bad.append( f"selected R={R} exceeds N={N} sections in doc" )
    else:
        bad.append( f"note matches neither the bound nor the unbound shape: {n}" )
        continue
    for r in ranges_of( mb[5] if mb else mu[4] ):
        lo, hi = ( int( x ) for x in r.split( "-" ) )
        if lo > hi or lo < 1:
            bad.append( f"malformed range {r}" )

print( "OK n=%d" % len( notes ) if not bad else "BAD " + " | ".join( bad ) )
PY
)"
    case "$res" in
        OK*     ) return;;
        NONOTE  ) no "P9 disclosure identities [$label]: no [sections: …] note in the output at all — this case is not section-granular any more";;
        *       ) no "P9 disclosure identities [$label]: ${res#BAD }";;
    esac
    DISCL_FAIL=$(( DISCL_FAIL + 1 ))
}

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# Fixture corpora — each arm gets its OWN single-file directory so "1 relevant of 1 document files" is
# unambiguous and a separator's displayed path is always the fixture's bare filename, regardless of
# where $TMP happens to land.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
LARGE="$TMP/large"; mkdir -p "$LARGE"; cp "$FIX/large_late_answer.md" "$LARGE/"
NEST="$TMP/nest";   mkdir -p "$NEST";  cp "$FIX/nested_headings.md"  "$NEST/"
SMALL="$TMP/small"; mkdir -p "$SMALL"; cp "$FIX/small_fits.md"       "$SMALL/"
DEGEN="$TMP/degen"; mkdir -p "$DEGEN"; cp "$FIX/degenerate_single.md" "$DEGEN/"

# P10's corpus is a REAL repo document, written out so the corpus holds exactly one file — which is what
# makes "which unit was served" an unambiguous question at a binding budget. It is
# deliberately not a synthetic fixture: the natural-language regression is a property of a many-sectioned
# document's scoring, and a hand-built fixture would be tuned until it reproduced, which is circular.
#
# PINNED, not live: the document is ARCHITECTURE.md as of blob P10_CORPUS_BLOB (c166bb4f, the file at
# d752d953). Observed 2026-09-11 on PR #126: a 27-line Kotlin paragraph inserted at line 160, unrelated to
# the answer, moved the document's section statistics, and at --max-tokens=800 the KEYWORD control stopped
# serving the answer — both phrasings served lines="21-33" ("### ingest — crawl and parse", also about a
# sorted crawl) while the answer sat on line 405. The same binary on this blob serves 372-387 (keyword)
# and 372-382 (English), both holding the answer on line 378. The sentinel scan kept the LINE honest
# across edits; it cannot hold section statistics still, and which of two relevant sections wins one
# unit's worth of budget is live-document ranking. This arm measures phrasing parity, so the document is
# held fixed and only the binary is free to move. The answer is still located by content inside the pinned
# copy, and the drift guard stays for the day the blob is re-pinned — re-pin only with the header's M1
# run repeated on the new blob, so the control is seen to go red before its green is believed.
ARCH="$TMP/arch"; mkdir -p "$ARCH"; git -C "$ROOT" cat-file blob "$P10_CORPUS_BLOB" > "$ARCH/ARCHITECTURE.md"

# P11's corpus, GENERATED rather than committed: the generation rule below IS the ground truth this arm
# checks against (heading on line 3, then 400 two-line paragraphs of a fixed 66-column width), and a
# 27 KB committed blob would hide it. Deterministic — no randomness, no clock, no locale.
DCUT="$TMP/dcut"; mkdir -p "$DCUT"
python3 - "$DCUT/degen_cut.md" <<'PY'
import sys
lines = [ "# Degenerate cut doc", "", "## Only matching section", "" ]
for i in range( 400 ):
    stem = "Zylonic quarrel drift %04d" % i
    lines.append( stem + " " + "x" * ( 66 - len( stem ) - 1 ) )   # 66-column body line
    lines.append( "" )                                            # ...then a blank: two-line paragraphs
open( sys.argv[1], "w", encoding = "utf-8" ).write( "\n".join( lines ) + "\n" )
PY

Q_LARGE="turbine flux calibration offset drift"
Q_NEST="zephyr cascade beacon vortex"
Q_SMALL="widget cache eviction policy"
Q_DEGEN="granite orbital lumen cascade"
SENTINEL="answers the query exactly"

# ── P1 — reachability: the last-decile answer must be IN the output at a share far below the doc size
echo "  ---- P1 reachability ----"
run "$LARGE" "$Q_LARGE" --max-tokens=2000 > "$TMP/p1.out"; P1_RC=$?
discl "P1 large@2000" "$TMP/p1.out"
P1_BYTES=$( wc -c < "$TMP/p1.out" | tr -d ' ' )
if [ "$P1_RC" = 0 ] && grep -q "$SENTINEL" "$TMP/p1.out"; then
    ok "P1 reachability: the answering section (rank #1, last decile of 300 sections) IS in the --max-tokens=2000 output ($P1_BYTES B of a 340821 B doc)"
else
    no "P1 reachability: --max-tokens=2000 (exit=$P1_RC, $P1_BYTES B) does not contain the answering section — ranked #1 by --for, never served"
fi
if [ "$P1_BYTES" -gt 0 ] && [ "$P1_BYTES" -lt 20000 ]; then
    ok "P1 share check: $P1_BYTES B is far below the 340821 B document — the reachability claim is not vacuous (a real, small budget was applied)"
else
    no "P1 share check: $P1_BYTES B is not a meaningfully small share of the 340821 B document"
fi

# ── P2 — ceiling sweep: present starting from the smallest budget that fits it, never only at large ones
echo "  ---- P2 ceiling sweep ----"
firstPresent=""
gapAfterFirst=0
for mt in 1500 3000 8000 40000; do
    run "$LARGE" "$Q_LARGE" --max-tokens="$mt" > "$TMP/p2_$mt.out"
    discl "P2 large@$mt" "$TMP/p2_$mt.out"
    if grep -q "$SENTINEL" "$TMP/p2_$mt.out"; then
        present=yes
        [ -z "$firstPresent" ] && firstPresent="$mt"
    else
        present=no
        [ -n "$firstPresent" ] && gapAfterFirst=1
    fi
    printf '      max-tokens=%-7s answer_present=%s\n' "$mt" "$present"
done
if [ "$firstPresent" = "1500" ] && [ "$gapAfterFirst" = 0 ]; then
    ok "P2 ceiling sweep: the answer is present starting at the smallest swept budget (1500) and stays present at every larger one"
else
    no "P2 ceiling sweep: expected present from 1500 upward with no gaps; first_present=${firstPresent:-none} gap_after_first=$gapAfterFirst — see the per-budget rows above"
fi

# ── P3 — stability: a document whose units all fit is byte-identical to the captured golden. See the
# header note on P3 for why this golden is captured POST-fix and what the original spec for it got wrong.
echo "  ---- P3 stability (budget not binding) ----"
run "$SMALL" "$Q_SMALL" > "$TMP/p3.out"
discl "P3 small@default" "$TMP/p3.out"
if cmp -s "$TMP/p3.out" "$FIX/small_fits.golden"; then
    ok "P3 stability: small_fits.md (all matched content fits under the default 8000-tok ceiling) is byte-identical to test/fixtures/recallpassage/small_fits.golden"
else
    no "P3 stability: output differs from test/fixtures/recallpassage/small_fits.golden — with nothing being cut, not a byte may move"
    diff "$FIX/small_fits.golden" "$TMP/p3.out" | head -10 | sed 's/^/        | /'
fi

# ── P4 — monotonicity: the disclosed line-range set must be a non-shrinking, actually-growing chain
echo "  ---- P4 monotonicity of the disclosed lines= across budgets ----"
run "$LARGE" "$Q_LARGE" --max-tokens=3000   > "$TMP/p4_small.out"
run "$LARGE" "$Q_LARGE" --max-tokens=200000 > "$TMP/p4_big.out"
discl "P4 large@3000"   "$TMP/p4_small.out"
discl "P4 large@200000" "$TMP/p4_big.out"
P4_LINE="$( python3 - "$TMP/p4_small.out" "$TMP/p4_big.out" <<'PY'
import sys, re
def ranges_of(path):
    text = open(path, encoding="utf-8").read()
    m = re.search(r'lines="([^"]*)"', text)
    return set(m.group(1).split(",")) if m and m.group(1) else set()
small = ranges_of(sys.argv[1])
big   = ranges_of(sys.argv[2])
print(f"subset={int(small.issubset(big))} grew={int(len(big) > len(small))} small_n={len(small)} big_n={len(big)}")
PY
)"
echo "      $P4_LINE"
if printf '%s' "$P4_LINE" | grep -q '^subset=1 grew=1 '; then
    ok "P4 monotonicity: the emitted line-range set only grows as --max-tokens grows (3000 -> 200000): $P4_LINE"
else
    no "P4 monotonicity: the disclosed lines= set does not strictly grow with the budget (3000 vs 200000): $P4_LINE — a set that never moves is not a chain, it is a constant pre-truncation dump"
fi

# ── P5 — disclosure: S/R/N and dropped_by_budget= must exist and be self-consistent with the body
echo "  ---- P5 disclosure self-consistency ----"
run "$LARGE" "$Q_LARGE" --max-tokens=2000 > "$TMP/p5.out"
discl "P5 large@2000" "$TMP/p5.out"
if grep -qE 'sections: [0-9]+ of [0-9]+ selected \([0-9]+ in doc\)' "$TMP/p5.out" && grep -qE 'dropped_by_budget=[0-9]+' "$TMP/p5.out"; then
    ok "P5a format: the note carries the disclosure contract's 'S of R selected (N in doc)' and dropped_by_budget= fields"
else
    no "P5a format: the note does not carry the disclosure contract's 'S of R selected (N in doc)' / dropped_by_budget= fields — the disclosure surface does not exist"
fi
P5_LINE="$( python3 - "$FIX/large_late_answer.md" "$TMP/p5.out" <<'PY'
import sys, re
fixlines = open(sys.argv[1], encoding="utf-8").read().split("\n")
out = open(sys.argv[2], encoding="utf-8").read()
m = re.search(r'lines="([^"]*)"', out)
ranges = m.group(1).split(",") if m and m.group(1) else []
present = 0
for r in ranges:
    lo = int(r.split("-")[0])
    heading = fixlines[lo - 1] if 0 < lo <= len(fixlines) else None
    if heading and heading in out:
        present += 1
print(f"claimed={len(ranges)} actually_present={present}")
PY
)"
echo "      $P5_LINE"
P5_CLAIMED="$( printf '%s' "$P5_LINE" | grep -oE 'claimed=[0-9]+'         | grep -oE '[0-9]+' )"
P5_PRESENT="$( printf '%s' "$P5_LINE" | grep -oE 'actually_present=[0-9]+' | grep -oE '[0-9]+' )"
if [ -n "$P5_CLAIMED" ] && [ "$P5_CLAIMED" -gt 0 ] && [ "$P5_PRESENT" = "$P5_CLAIMED" ]; then
    ok "P5b consistency: every one of the $P5_CLAIMED lines= ranges is actually present in the emitted body (ground truth read from the fixture file directly)"
else
    no "P5b consistency: lines= claims $P5_CLAIMED ranges but only $P5_PRESENT are actually present in the emitted body — the disclosure names content that was never served"
fi

# ── P6 — determinism: the standing contract, re-asserted on the section-passage path
echo "  ---- P6 determinism ----"
run "$LARGE" "$Q_LARGE" --max-tokens=4000 > "$TMP/p6a.out"
run "$LARGE" "$Q_LARGE" --max-tokens=4000 > "$TMP/p6b.out"
if cmp -s "$TMP/p6a.out" "$TMP/p6b.out"; then
    ok "P6 determinism: two runs at --max-tokens=4000 are byte-identical"
else
    no "P6 determinism: two runs at --max-tokens=4000 differ"
fi

# ── P7 — nesting: with §3.1 in place, no emitted range may contain another heading's line
echo "  ---- P7 nesting (defect B) ----"
run "$NEST" "$Q_NEST" --max-tokens=1000000 > "$TMP/p7.out"
discl "P7 nested@1000000" "$TMP/p7.out"
# ground truth, computed independently of ripwire (matches recallanchorcheck.sh's convention): every
# markdown heading's own line number, via a plain scan of the fixture text.
HEAD_LINES="$( grep -n '^#' "$FIX/nested_headings.md" | cut -d: -f1 | tr '\n' ' ' )"
P7_LINE="$( python3 - "$TMP/p7.out" "$HEAD_LINES" <<'PY'
import sys, re
out = open(sys.argv[1], encoding="utf-8").read()
headings = [int(x) for x in sys.argv[2].split()]
m = re.search(r'lines="([^"]*)"', out)
ranges = []
if m and m.group(1):
    for r in m.group(1).split(","):
        lo, hi = r.split("-")
        ranges.append((int(lo), int(hi)))
violations = [(lo, hi, h) for lo, hi in ranges for h in headings if h != lo and lo < h <= hi]
if violations:
    print("VIOLATION " + ";".join(f"{lo}-{hi}_contains_heading@{h}" for lo, hi, h in violations))
else:
    print("CLEAN ranges=" + ",".join(f"{lo}-{hi}" for lo, hi in ranges))
PY
)"
echo "      $P7_LINE"
if printf '%s' "$P7_LINE" | grep -q '^CLEAN'; then
    ok "P7 nesting: $P7_LINE — no emitted range swallows another heading's line"
else
    no "P7 nesting: $P7_LINE — an emitted range CONTAINS a nested heading's line (defect B: the ancestor swallowed its descendant)"
fi

# ── P8 — degenerate: a single unit bigger than the whole share is prefix-cut, never dropped to zero
echo "  ---- P8 degenerate ----"
run "$DEGEN" "$Q_DEGEN" --max-tokens=500 > "$TMP/p8.out"
discl "P8 degenerate@500" "$TMP/p8.out"
SHOWN="$( head -1 "$TMP/p8.out" | grep -oE ' shown=[0-9]+' | grep -oE '[0-9]+' )"
if [ "$SHOWN" = "1" ] && grep -qE '\[truncated: [0-9]+ of [0-9]+ bytes' "$TMP/p8.out"; then
    ok "P8 degenerate: shown=1 and the oversized single unit is disclosed as [truncated: N of M bytes], never silently dropped to shown=0"
else
    no "P8 degenerate: shown=${SHOWN:-<none>} and/or no [truncated: ...] disclosure: $( head -1 "$TMP/p8.out" )"
fi

# ── P10 — NATURAL-LANGUAGE PARITY. EXPECTED RED until lane F1's fix lands; see the header table.
#
# The property: a question asked in ENGLISH must serve the same answering unit as the same question
# asked in keywords. Stopwords may not decide whether the answer is reachable.
#
# Ground truth is the ANSWER'S SOURCE LINE, located by scanning the fixture copy for a sentence that
# only the answering section contains — never read back out of ripwire, and never a hard-coded line
# number. The fixture copy is ARCHITECTURE.md as of blob P10_CORPUS_BLOB, not the live file. The scan was
# meant to let ordinary edits to ARCHITECTURE.md move the ground truth with the document, and it did move
# the line — but on 2026-09-11 (PR #126) an unrelated paragraph elsewhere in the live document shifted its
# section statistics enough that the keyword control stopped serving the answer at 800 tokens: a tripwire
# on an unrelated file after all. The arm measures phrasing parity, not live-document ranking; see the P10
# corpus note above. If the sentence stops being unique the arm says the FIXTURE drifted, which is a
# different failure from the one it is here to catch.
echo "  ---- P10 natural-language parity (EXPECTED RED until lane F1 lands) ----"
P10_SENTINEL="assigned in sorted crawl order"
P10_LINE="$( grep -n "$P10_SENTINEL" "$ARCH/ARCHITECTURE.md" | cut -d: -f1 )"
P10_HITS="$( printf '%s\n' "$P10_LINE" | grep -c . )"
if [ "$P10_HITS" != "1" ]; then
    no "P10 fixture drift: \"$P10_SENTINEL\" occurs $P10_HITS times in docs/ARCHITECTURE.md (expected exactly 1) — re-pick the sentinel; this is NOT the recall defect"
else
    echo "      ground truth: the answer sentence is on source line $P10_LINE of ARCHITECTURE.md"
    run "$ARCH" "crawl order sorted before ids assigned"                        --max-tokens=800 > "$TMP/p10_kw.out"
    run "$ARCH" "how does the crawl order get sorted before the ids are assigned" --max-tokens=800 > "$TMP/p10_nl.out"
    discl "P10 arch@800 keyword" "$TMP/p10_kw.out"
    discl "P10 arch@800 english" "$TMP/p10_nl.out"
    # p10_serves FILE -> "yes <ranges>" | "no <ranges>". BOTH halves must hold: an emitted range covers the
    # answer's source line AND the answer's own words are in the served text. Checking only the range would
    # rest this arm on the lines= attribute, and P11 in this very file proves that attribute can overclaim;
    # checking only the text would pass on an output that stumbled onto the sentence inside some other unit.
    p10_serves(){ python3 - "$1" "$P10_LINE" "$P10_SENTINEL" <<'PY'
import sys, re
out  = open( sys.argv[1], encoding = "utf-8" ).read()
line = int( sys.argv[2] )
want = sys.argv[3]
m    = re.search( r'lines="([^"]*)"', out )
rs   = [ tuple( int( x ) for x in r.split( "-" ) ) for r in ( m.group( 1 ).split( "," ) if m and m.group( 1 ) else [] ) ]
body = out.split( "]", 1 )[ -1 ]                       # everything past the header and the section note
hit  = any( lo <= line <= hi for lo, hi in rs ) and want in body
print( ( "yes " if hit else "no " ) + ( m.group( 1 ) if m else "<no lines= at all>" )
       + ( "" if want in body else " [and the answer's own words are ABSENT from the served body]" ) )
PY
    }
    P10_KW="$( p10_serves "$TMP/p10_kw.out" )"
    P10_NL="$( p10_serves "$TMP/p10_nl.out" )"
    printf '      keyword phrasing: serves_answer=%s\n      english phrasing: serves_answer=%s\n' "$P10_KW" "$P10_NL"
    case "$P10_KW" in
        yes* ) ok "P10 control: the KEYWORD phrasing serves the unit containing line $P10_LINE (${P10_KW#yes }) — the corpus and budget do admit the answer" ;;
        *    ) no "P10 control: even the KEYWORD phrasing does not serve the unit containing line $P10_LINE ($P10_KW) — the control failed, so the parity result below means nothing" ;;
    esac
    case "$P10_NL" in
        yes* ) ok "P10 parity: the ENGLISH phrasing of the same question also serves the unit containing line $P10_LINE (${P10_NL#yes })" ;;
        *    ) no "P10 parity: the ENGLISH phrasing serves ${P10_NL#no } and DROPS the answer on line $P10_LINE, which the keyword phrasing of the same question serves — stopwords decided reachability" ;;
    esac
fi

# ── P11 — DEGENERATE-CUT HONESTY. EXPECTED RED until lane F1's fix lands; see the header table for why
# the correct hi is the line containing the last served BYTE (blank trailing line included), which is the
# rule RecallSectionUnit::lineHi already uses on the non-degenerate path.
#
# Ground truth uses only (a) the fixture's own bytes and (b) K from the binary's `[truncated: K of M
# bytes]` disclosure — never the lines= attribute under test. The unit's first byte is the start of the
# `## Only matching section` heading line, found by a plain scan; the last served byte is K-1 past it;
# the line containing that byte is counted directly out of the file.
echo "  ---- P11 degenerate-cut lines= hi (EXPECTED RED until lane F1 lands) ----"
run "$DCUT" "zylonic quarrel drift" --max-tokens=400 > "$TMP/p11.out"
discl "P11 degencut@400" "$TMP/p11.out"
P11_LINE="$( python3 - "$DCUT/degen_cut.md" "$TMP/p11.out" <<'PY'
import sys, re

raw = open( sys.argv[1], "rb" ).read()
out = open( sys.argv[2], encoding = "utf-8" ).read()

# (a) the unit's first byte: the start of the `## Only matching section` heading line, by a plain scan
srclines = raw.split( b"\n" )
headIdx  = next( i for i, l in enumerate( srclines ) if l.startswith( b"## Only matching section" ) )
start    = sum( len( l ) + 1 for l in srclines[ :headIdx ] )
headLine = headIdx + 1

# (b) K and M, from the truncation disclosure — the binary's own statement of how many SOURCE bytes it kept
mt = re.search( r'\[truncated: (\d+) of (\d+) bytes', out )
ml = re.search( r'lines="(\d+)-(\d+)"', out )
if not mt or not ml:
    print( "SHAPE truncated=%s lines=%s" % ( bool( mt ), bool( ml ) ) )
    raise SystemExit
K, M       = int( mt.group( 1 ) ), int( mt.group( 2 ) )
gotLo, hi  = int( ml.group( 1 ) ), int( ml.group( 2 ) )
expectedHi = raw[ : start + K - 1 ].count( b"\n" ) + 1     # the line CONTAINING the last served byte
lastText   = max( ( n + 1 for n, l in enumerate( srclines[ :expectedHi ] ) if l.strip() ), default = expectedHi )
print( "K=%d M=%d unit_bytes=%d head_line=%d got=%d-%d expected_hi=%d last_text_line=%d"
       % ( K, M, len( raw ) - start, headLine, gotLo, hi, expectedHi, lastText ) )
PY
)"
echo "      $P11_LINE"
P11_GOT_HI="$(  printf '%s' "$P11_LINE" | grep -oE 'got=[0-9]+-[0-9]+'    | grep -oE '[0-9]+$' )"
P11_GOT_LO="$(  printf '%s' "$P11_LINE" | grep -oE 'got=[0-9]+'           | grep -oE '[0-9]+'  )"
P11_EXP_HI="$(  printf '%s' "$P11_LINE" | grep -oE 'expected_hi=[0-9]+'   | grep -oE '[0-9]+'  )"
P11_HEAD="$(    printf '%s' "$P11_LINE" | grep -oE 'head_line=[0-9]+'     | grep -oE '[0-9]+'  )"
P11_M="$(       printf '%s' "$P11_LINE" | grep -oE ' M=[0-9]+'            | grep -oE '[0-9]+'  )"
P11_UNIT="$(    printf '%s' "$P11_LINE" | grep -oE 'unit_bytes=[0-9]+'    | grep -oE '[0-9]+'  )"
if [ -z "$P11_EXP_HI" ]; then
    no "P11 degenerate cut: the output has no single lines=\"LO-HI\" plus [truncated: K of M bytes] pair to check — $P11_LINE"
else
    if [ "$P11_GOT_LO" = "$P11_HEAD" ]; then
        ok "P11 lo: the cut unit is anchored at its own heading line $P11_HEAD"
    else
        no "P11 lo: lines= starts at $P11_GOT_LO but the unit's heading is on line $P11_HEAD"
    fi
    if [ "$P11_M" = "$P11_UNIT" ]; then
        ok "P11 scope: [truncated: … of $P11_M bytes] measures the UNIT ($P11_UNIT B from its heading to EOF), not the whole document"
    else
        no "P11 scope: [truncated: … of $P11_M bytes] does not match the unit's own $P11_UNIT bytes — the truncation marker is measuring something else"
    fi
    if [ "$P11_GOT_HI" = "$P11_EXP_HI" ]; then
        ok "P11 hi: lines= ends at $P11_GOT_HI, the line containing the last served byte — the degenerate cut names only what it sent"
    else
        if [ "$P11_GOT_HI" -gt "$P11_EXP_HI" ]; then
            no "P11 hi: lines= claims up to line $P11_GOT_HI but the last served byte is on line $P11_EXP_HI — the cut names $(( P11_GOT_HI - P11_EXP_HI )) line(s) it never sent (counting the kept prefix's trailing newline as opening a further line)"
        else
            no "P11 hi: lines= stops at line $P11_GOT_HI but the cut served through line $P11_EXP_HI — the disclosure UNDER-names what was sent by $(( P11_EXP_HI - P11_GOT_HI )) line(s); $P11_LINE"
        fi
    fi
fi

# ── P9 — the disclosure IDENTITIES, over EVERY section-granular output this gate produced. The per-case
# failures were already reported by `discl` at the point each output was made; this block names the
# COVERAGE, so a green line here says what was checked and not merely that nothing complained. The
# enrolment floor is the arm that keeps it honest: silently checking fewer cases is the way a sweep like
# this rots, and it fails loudly instead.
echo "  ---- P9 disclosure identities (dropped_by_budget == R-S; S == |lines=|) ----"
echo "      swept ($DISCL_N cases):$DISCL_LABELS"
if [ "$DISCL_N" -lt 14 ]; then
    no "P9 disclosure identities: only $DISCL_N cases enrolled (expected >= 14) — an arm above stopped feeding its output to discl, so the sweep is narrower than it reads"
elif [ "$DISCL_FAIL" = 0 ]; then
    ok "P9 disclosure identities: $DISCL_N section-granular cases swept; every note's dropped_by_budget equals R-S and every lines= list names exactly S ranges"
else
    no "P9 disclosure identities: $DISCL_FAIL of $DISCL_N swept cases carry a note whose numbers do not add up — the per-case lines above name each one"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"

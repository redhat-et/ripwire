#!/usr/bin/env bash
# legendcoveragecheck.sh — THE FIRST-SCREEN LEGEND-COVERAGE RATCHET (capture-audit-4, §B7 lane).
#
# Why this gate exists. Every round of this audit has re-found the same shape: an attribute or marker string
# a reader meets on the first screen with NO definition where they meet it. §B7.8 alone was found in some
# form in eight consecutive rounds. Each time it was found by a human reading output; each time the fix
# closed one attribute and the class stayed open. This gate closes the CLASS by making it mechanical.
#
# What it measures. For every verb in the roster below: run it, split the LEADING comment block (the legend
# the reader actually meets first) from the document, enumerate the attribute names on the root element and
# on the first instance of EVERY distinct child element, and report which of those names the legend fails to
# define.
#
# TWO PREDICATES, ONE PER ARM — and this is the whole design, so read it before editing either.
# The gate makes two DIFFERENT claims, and they are negations of each other, so a single predicate is
# conservative in one and reckless in the other:
#
#   (A) "here is a NEW gap"    -> FAILS the suite. Being wrong here is a false alarm, so (A) uses the
#       GENEROUS predicate `mentioned`: an attribute counts as covered if its bare name appears anywhere in
#       the legend, in any form. A gap (A) reports is therefore real — the legend does not contain the word.
#   (B) "this gap is CLOSED"   -> instructs a future agent to delete a line from the ratchet FLOOR. Being
#       wrong here silently DISCARDS recorded debt, so (B) uses the DEFINITIONAL predicate `defined`: the
#       attribute name immediately followed by `=`, which is the house convention every legend in this tree
#       already uses (`churn=commits touching the file`, `at= is the git commit`, `files= is the indexed
#       corpus`). A closure (B) reports is therefore real — the legend really defines the attribute.
#
# So the gate UNDER-reports in BOTH directions and over-reports in NEITHER. That symmetry is the fix for
# CA4-F5.F1: the header used to disclose the generosity cost for arm (A) only — "it never over-reports" —
# while arm (B), the negation of the same predicate, inherited the OPPOSITE error undisclosed. Live proof
# it was not theoretical: (B) reported `edit-check | edit-check@at` as closed because §B11.3's sentence
# contains the English word — "defs= is how many DEFINITIONS *at* this site" — while `at=`, the git stamp,
# is still undefined on --edit-check's first screen, and test/legendcoverage_baseline.txt:36-38, committed
# by the same lane in the same wave, says so correctly in prose. Same shape on `stray-content@head` ("only
# the checked out one has a local head") and `test-gate@impacted` ("untested= here counts impacted SYMBOLS").
# Short attribute names that are also English words — at, in, of, k, p, n, head, total — cannot be settled
# by a bare word-boundary search, and they are exactly the ones this audit keeps re-finding.
#
# The residual, stated rather than discovered later. Between the two predicates sits a GREY ZONE: an
# attribute the legend discusses in prose but never spells `name=` (`of_top denominator is per-section`).
# Those are not failed by (A) and not credited by (B); the count is printed as INFO so the class is visible
# without either arm asserting on it, and LEGENDCOV_LIST=1 lists them. The residual OF THE RESIDUAL, measured
# by mutation rather than reasoned about: a baseline line in the grey zone is not protected by (A) either —
# deleting `edit-check | edit-check@at` from the floor by hand leaves the gate green, because (A) asks the
# generous question and the word is there. What the fix buys is that the gate no longer TELLS anyone to
# delete it, which is the failure mode F1 recorded. Deleting a grey-zone line is a review question, not a
# gate question, and the baseline header names the three that are in it.
#
# NO CAP. The enumeration used to stop at the first six distinct element tags (`if len(order) >= 6: break`)
# with no header disclosing it, which is CA4-F5.F2: it hid 8 real gaps, and two of them were §B8.3 verbatim
# — --pack-task emits `<bodies shown="4" total="6" capped="1">` as its 8th distinct tag, and its legend
# contained the words `shown` and `total` zero times. Removing the cap took the live count 146 -> 154. The
# cap bought nothing measurable: the regex already walks the whole document either way.
#
# The RATCHET. test/legendcoverage_baseline.txt records the gaps that exist today, one "verb | element@attr"
# per line. This gate FAILS on any gap NOT in that file — i.e. a NEW undefined attribute cannot be added to
# any first screen without a red gate naming it. Gaps that have been CLOSED are printed as shrink candidates
# with the exact lines to delete; they are not a failure, because a verb that emits fewer rows in a different
# environment would otherwise flake. Arm (B) splits them by CAUSE, because the two need different evidence:
# a line closed because the legend now DEFINES the attribute is deleted with that legend text, and a line
# closed because the verb no longer EMITS the attribute has no legend text to cite. The baseline may only be
# edited DOWNWARD; the one exception on record is the F2 re-derivation above, which widened the WINDOW rather
# than the debt, and it is annotated in the baseline header.
#
# ELEMENT-BLINDNESS — the limit this gate cannot assert away, named where a reader meets it (CONTRIBUTING §2
# shape 7: a gate whose NAME promises more than its CODE delivers is fixed by asserting the missing property,
# or, where that is impossible, by naming the limit). Both predicates take an attribute NAME and a legend
# STRING. Neither knows which ELEMENT the attribute was on. So a document carrying `total=` on two elements
# has ONE coverage verdict for both, and a clause written about one of them credits the other. That is live
# and measured, not hypothetical: `<sigs total= shown= capped=>` is defined by the bundle=auto/compact legend
# and `<tail total= shown= capped=>` by the tail legend, and on every --for row in this roster — before the
# 0.6.1 rung-zero lane and independently of it — whichever of those two clauses is present closes BOTH
# elements' trios. Consequence to hold on to: a baseline line naming one of a SHARED name can be closed by a
# clause written for the other element, so `sigs@total` has never been separately visible here. Closing that
# needs an element-aware predicate (the legends would have to name the element, which most do not), which is
# a change to the contract rather than to this gate. Until then the limit is not merely written down: arm (F)
# CENSUSES it — every key whose only definition is the rung-zero note under a name the same document carries
# twice is printed on every run and pinned, so a future clause drop that a shared name papers over reds here
# instead of arriving as a quieter baseline.
#
# "What would make this pass without the property holding?" (the round's own lens, trap #20). Three things,
# not one — the earlier "Exactly one thing" was wrong, and the cap above was the second. (i) a roster verb
# that stops producing output has no elements, no attributes and no gaps: arm (C) names every silent verb
# and fails. (ii) the two predicates drifting apart so that `mentioned` stops being the weaker of the two,
# which would make (A) fail on something (B) had just called closed: arm (D) asserts they still nest.
# (iii) a legend that CLOSES ITS OWN GAPS by naming attributes nothing defines — the shape rung zero's
# dropped-legend note has by construction, since it spells every name it discloses as `name=`: arm (E)
# re-asks each of those names against the same query at a budget where no clause was dropped, and arm (F)
# pins which of those closures land on a name the document carries on more than one element.
#
#   bash test/legendcoveragecheck.sh                       # build/ripwire
#   bash test/legendcoveragecheck.sh build_base/ripwire    # or RIPWIRE_BIN=... — both seams honored
#   LEGENDCOV_LIST=1 bash test/legendcoveragecheck.sh      # print the full per-verb table (the audit view)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative binary
BASELINE="$ROOT/test/legendcoverage_baseline.txt"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
# HERMETIC HOME (0.6.6 review M2): every run below inherits this environment, and a bare --scan-skills (or any verb that reads
# the Claude/Codex homes) would otherwise answer from the caller's real HOME — different bytes on every machine, and a read of
# the real home. Each run gets an empty HOME of its own.
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR CODEX_HOME
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -f "$BASELINE" ] || { echo "missing $BASELINE — this gate is a ratchet and cannot run without its floor"; exit 2; }

echo "legendcoveragecheck: BIN=$BIN"

# THE CALL RUNNER both sweeps below share (2026-10-13, lane/legendcov-speed). The roster is ~170 independent read-only
# calls, and the gate used to run them ONE AT A TIME: 394 s on the dev machine, and over its 1200 s budget (rc=124) on the
# macOS plain shard twice in three days. Two of them (--pr-context=HEAD~30, ±budget) are ~40% of that on their own — the
# cost is inside ripwire (prcontext/cochangePartners), not here. So the calls run on a small pool, the heaviest submitted
# FIRST so they overlap everything else instead of finishing last. Nothing a row asserts changed: every row still runs its
# own command, once, and is judged in roster order exactly as before. Why concurrency is safe here: no roster call writes
# into the corpus (the roster comment says so), and the warm-by-default TMPDIR cache publishes by exclusive temp file +
# rename (ingest_cache.h saveCache), one blob per (root, lean/rich) — two calls racing on a cold root both parse and the
# last rename wins with an equal blob. The ONE exception is --doctor, whose answer reads that cache directory: it runs
# serially after the pool has drained, as it did before (late, on a warm and quiescent cache dir).
# Every call now has a budget (LEGENDCOV_CALL_TIMEOUT, default 600 s), and a call that times out or dies on a signal
# is a TIMEOUT/ERROR row of its own — never an empty document judged as "silent", and never a partial one judged at all
# (CHECKLIST 14). A non-zero EXIT (--quality-delta 2, --doctor 1) is a verdict the verb returns, judged as before.
# LEGENDCOV_JOBS=1 restores the serial run.
cat > "$TMP/lcrun.py" <<'PYR'
import os, subprocess, concurrent.futures as cf
JOBS         = max( 1, int( os.environ.get( "LEGENDCOV_JOBS" ) or min( 4, os.cpu_count() or 1 ) ) )
CALL_TIMEOUT = max( 1, int( os.environ.get( "LEGENDCOV_CALL_TIMEOUT" ) or 600 ) )
def call( BIN, args ):
    """-> (stdout, None) on a completed call (any exit code), (None, reason) on a timeout / signal / no start."""
    try:
        p = subprocess.run( [ BIN ] + args, capture_output = True, timeout = CALL_TIMEOUT )
    except subprocess.TimeoutExpired:
        return None, f"TIMEOUT (no answer within {CALL_TIMEOUT}s)"
    except OSError as e:
        return None, f"ERROR (could not start: {e})"
    if p.returncode < 0:
        return None, f"ERROR (killed by signal {-p.returncode})"
    return p.stdout, None
def runAll( BIN, argvs, first = lambda a: False, last = lambda a: False ):
    """Run argvs[i] once each; -> list of (stdout, reason) by index. `first` calls are submitted ahead of the rest;
    `last` calls run serially once the pool has drained."""
    res    = [ None ] * len( argvs )
    pooled = sorted( ( i for i, a in enumerate( argvs ) if not last( a ) ), key = lambda i: not first( argvs[ i ] ) )
    with cf.ThreadPoolExecutor( JOBS ) as ex:
        futs = { ex.submit( call, BIN, argvs[ i ] ): i for i in pooled }
        for f in cf.as_completed( futs ): res[ futs[ f ] ] = f.result()
    for i, a in enumerate( argvs ):
        if last( a ): res[ i ] = call( BIN, a )
    return res
def isDoctor( a ): return "--doctor" in a
PYR

python3 - "$BIN" "$ROOT" "$BASELINE" "$TMP" <<'PY' > "$TMP/out" 2>"$TMP/pyerr"
import subprocess, re, sys, os

BIN, ROOT, BASELINE, TMP = sys.argv[1:5]
sys.path.insert( 0, TMP )
from lcrun import runAll, isDoctor, JOBS, CALL_TIMEOUT
SMALL = os.path.join( ROOT, "src" )

# The roster: one runnable invocation per first-screen shape. Value-taking verbs get a symbol that exists in
# this tree; nothing here writes into the corpus (no --quality-baseline / --quality-ack / --note-add /
# --index-out / --export), so the sweep leaves no state behind for the next differential run (trap #24).
ROSTER = [
    ("default-map",        [SMALL]),
    ("map-metrics",        [SMALL, "--metrics"]),
    ("map-churn",          [ROOT,  "--rank-by=churn"]),
    ("map-authority",      [SMALL, "--rank-by=authority"]),
    ("map-hub",            [SMALL, "--rank-by=hub"]),
    ("map-rrf",            [SMALL, "--rank-by=rrf"]),
    ("map-diff",           [ROOT,  "--map-diff"]),
    ("map-max-tokens",     [SMALL, "--max-tokens=3000"]),
    # TWO --for rows, one per SERVING SHAPE (2026-08-23 sweep): the conceptual row serves the COMPACT
    # bundle (<hops>), the name-exact row serves the AUTO body walk (<bodies>/<b>). With only the
    # conceptual row, a new undefined attribute on the auto shape's first screen could land unseen —
    # the exact decay class the chip-trio merge found in forbudgetmonotoncheck/fordisclosurecheck.
    ("for",                [SMALL, "--for=rank symbols by pagerank"]),
    ("for-auto",           [SMALL, "--for=escapeXml"]),
    # …and a BUDGETED one (0.6.1, the L1 lane). Both rows above run unbudgeted, so no run in this roster
    # ever climbed a rung of the --for ceiling ladder — and the ladder is where legend clauses get DROPPED.
    # Rung zero drops the confidence=/margin_pct=/budget_tokens= clause and the r=/tail clause to buy the
    # bytes back, which is the right trade (METHODOLOGY §9: inside the budget beats over it) and was
    # entirely silent: the attributes stayed on the root with nothing defining them and nothing saying so.
    # THE BUDGET IS 900, AND THE OLD 1300 WAS A KNIFE-EDGE. The band recorded here was "~1100 to ~1340",
    # measured only on a developer worktree — and the rung's top edge is a function of the CHECKOUT PATH
    # LENGTH, because the document charges its own `root="…"` bytes. Measured on this tree at two roots:
    # a 38-character root fires rung zero at 1287 and NOT at 1288; a 137-character root fires at 1323 and not
    # at 1324 (bisected, same commit and binary). CI checks the tree out into the runner's work directory,
    # which is 33 characters on the Linux
    # runners and 34 on the macOS ones (this file may not spell either path: ripwirepubliccheck arm 2 refuses
    # an absolute home path in a tracked file, and it is right to, since it cannot tell a runner's home from
    # a person's). So 1300 was INSIDE the band on a long local path and OUTSIDE it on every CI runner — green
    # here, red on three shards. The band's floor is flat: from 100 up to the top edge the note's text and arm
    # (F)'s census are byte-identical, so 900 is mid-rung by ~390 tokens of headroom rather than a widened
    # tolerance, and arm (E) now GATES that headroom instead of trusting a comment (see MARGIN below).
    ("for-budgeted",       [SMALL, "--for=rank symbols by pagerank", "--token-budget=900"]),
    # …and the same rung in the COMPACT DIALECT, which has its own legend strings for every clause the rung
    # drops (kForCompactConfidenceClause, kForFileTailLegendCompact) and had no roster row at all. A dialect
    # with no row is a dialect where the ratchet cannot see a gap, and this one carries `schema=` that the
    # default dialect does not emit.
    ("for-budgeted-compact", [SMALL, "--legend=compact", "--for=rank symbols by pagerank", "--token-budget=900"]),
    # …and the FILE PAGE (L-W, forpage.h): --for --limit=N answers with its own <files> root and <f> rows, a
    # first screen no other row here reaches; both dialects, since the compact one carries its own short legend.
    ("for-page",           [SMALL, "--for=rank symbols by pagerank", "--limit=10"]),
    ("for-page-compact",   [SMALL, "--legend=compact", "--for=rank symbols by pagerank", "--limit=10"]),
    # …and the RESTORED lego/compose dialect (L2, round-1 lever B1, 2026-09-19): --sections=lego,compose
    # opts back into the full <lego><iface…>/<compose><field…> render the ranked bundle collapses to a
    # counted stub by default — a first screen (<iface>/<impl>/<m>/<field> attributes) no other row here
    # reaches, since every plain "for" row above stays at the default stub. ROOT (this repo), not SMALL:
    # this lane already confirmed this exact query reaches a real interface AND a real compose edge on it.
    ("for-sections",       [ROOT, "--for=shape interface implementors", "--sections=lego,compose"]),
    ("pack-task",          [SMALL, "--pack-task=rank symbols by pagerank"]),
    ("exemplar",           [SMALL, "--exemplar=rank symbols"]),
    ("hotspots",           [ROOT,  "--hotspots"]),
    ("clones",             [ROOT,  "--clones"]),
    ("biggest-first",      [SMALL, "--biggest-first"]),
    ("ensemble",           [SMALL, "--ensemble"]),
    ("context-ratio",      [SMALL, "--context-ratio"]),
    ("naming-consistency", [SMALL, "--naming-consistency"]),
    ("cochange",           [ROOT,  "--cochange"]),
    ("cochange-file",      [ROOT,  "--cochange=src/cli.h"]),
    ("owners",             [ROOT,  "--owners"]),
    ("deps",               [SMALL, "--deps"]),
    ("dead-code",          [SMALL, "--dead-code"]),
    ("quality-delta",      [ROOT,  "--quality-delta"]),
    ("test-gate",          [ROOT,  "--test-gate"]),
    ("edit-check",         [SMALL, "--edit-check=escapeXml"]),
    # lane/at-seed: line 100 of cli.h sits deep inside the Config struct, so the seed stays covered
    # across ordinary drift; arm (C) below flags it if it ever escapes every definition.
    ("at",                 [SMALL, "--at=cli.h:100"]),
    ("callers",            [SMALL, "--callers=escapeXml"]),
    ("callees",            [SMALL, "--callees=serialize"]),
    ("callers-columnar",   [SMALL, "--callers=escapeXml", "--format=columnar"]),
    ("uses",               [SMALL, "--uses=escapeXml"]),
    ("impact",             [SMALL, "--impact=escapeXml"]),
    ("mentions",           [SMALL, "--mentions=escapeXml"]),
    ("around",             [SMALL, "--around=escapeXml"]),
    ("path",               [SMALL, "--path=serialize,escapeXml"]),
    ("connect",            [SMALL, "--connect=serialize,escapeXml,rankGraph"]),
    ("affected",           [ROOT,  "--affected=src/cli.h"]),
    ("exercises",          [ROOT,  "--exercises=test/clicheck.sh"]),
    ("communities",        [SMALL, "--communities"]),
    ("community",          [SMALL, "--community=5"]),
    ("zoom",               [SMALL, "--zoom"]),
    ("seams",              [SMALL, "--seams"]),
    ("report",             [SMALL, "--report"]),
    ("tree",               [SMALL, "--tree"]),
    ("grep",               [SMALL, "--grep=escapeXml"]),
    ("lint",               [SMALL, "--lint"]),
    ("external-surface",   [SMALL, "--external-surface"]),
    # PINNED TO A REF, and it has to be. The bare working-tree form emits its <file>/<cochange>/<owners>
    # children only when something is uncommitted, so with the 6-element cap gone its gap set would swing on
    # whether the agent running the suite happens to have edits open — a ratchet that reds because you have
    # unstaged work is a ratchet nobody keeps. HEAD~1 is deterministic AND strictly wider: 14 distinct tags
    # vs 13, 4 gaps vs 2 (it adds no-ref-work@note and pr-context@base_sha), so pinning costs no coverage.
    ("pr-context",         [ROOT,  "--pr-context=HEAD~1"]),
    ("merge-scout",        [ROOT,  "--merge-scout=HEAD~1"]),
    ("whereis",            [ROOT,  "--whereis=escapeXml"]),
    ("stray-content",      [ROOT,  "--stray-content"]),
    ("doc-drift",          [SMALL, "--doc-drift"]),
    ("layout",             [SMALL, "--layout=MapAnnotations"]),
    ("notes",              [ROOT,  "--notes"]),
    # 0.6.6 (review M2/M5/S4): an explicit DIR with finding rows, so the row attributes (rule= sev= why=) are read and the run
    # does not depend on the cwd or HOME (bare --scan-skills walks cwd/.agents/skills and the HOME skill homes).
    ("scan-skills",        [ROOT,  "--scan-skills=" + os.path.join( ROOT, "test", "skillfix" )]),
    # 2026-09-13: the router's own document was outside this roster, and it was the one shape with NO
    # legend in the default dialect at all — every attribute on its only screen undefined. The probe is a
    # RECOMMEND, not an abstain: an abstain carries no <choice>, so half the vocabulary would be unseen.
    ("help-task",          [SMALL, "--help-task=find the code responsible for this retry timeout bug"]),
]

# L1 (round 1 of the answer-size loop, 2026-09-19): THE CLI DEFAULT BECAME COMPACT, so a roster row that names no
# posture would silently have become a compact row and the FULL dialect — every row this ratchet has ever recorded,
# test/legendcoverage_baseline.txt line for line — would have lost its ratchet. So every row above is re-spelled as a
# FULL row (the name unchanged, `--legend=full` appended: the baseline's lines keep meaning exactly what they meant,
# and that file did not gain a line), and gets a DEFAULT TWIN, `<name>-default`, run with no posture flag at all —
# whatever the default is today (compact) and whatever round 2 makes it.
# THE DEFAULT TWINS HAVE NO FLOOR (L1 fix round, rv-r1-L1 HIGH-1). L1 seeded one — 269 "<row>-default" lines, called
# descriptive attributes the compact dialect "leaves to --legend=full" — and ~25 of them were cut/floor/cap terms
# (renames_window_truncated=, script_gates_unmodelled=, more files=, hcut=/rcut= …): the ratchet RATIFIED the gap instead
# of closing it. Owner ruling: compact shortens the dictionary, never a meaning, so the default answer defines every
# attribute it emits. Arm (G) below holds that with the DEFINITIONAL predicate (`name=`, arm (B)'s), not the generous
# one, and with an empty floor: a default first screen that emits one attribute its own legend does not define fails.
# Two kinds of row keep their spelling: a row that already names a posture (the *-compact rows, whose own lines stay theirs), and a run with
# no XML legend (--report), which refuses an ASKED posture and has no default twin to take.
NON_XML_ROWS = { "report" }
def withPostureTwins( roster ):
    out = []
    for name, args in roster:
        if name in NON_XML_ROWS or any( a.startswith( "--legend=" ) for a in args ):
            out.append( ( name, args ) )
            continue
        out.append( ( name, args + [ "--legend=full" ] ) )
        out.append( ( name + "-default", args ) )
    return out
ROSTER = withPostureTwins( ROSTER )

# L1 fix round: DEFAULT-ONLY rows — verbs outside the roster above, run in the default posture alone and judged by arm (G) alone
# (every attribute defined, no floor). They have no full twin because the full dialect's floor for them was never recorded and a
# ratchet may only shrink; arm (G) is the contract the default owes, and these widen its reach to every verb class the review
# probed (the expand servings, the envelopes, the trace lens, the reports with their own roots).
open( os.path.join( TMP, "trace.txt" ), "w" ).write( "#0 0x1 in escapeXml serialize.h:147\n#1 0x2 in main main.cpp:10\n" )
open( os.path.join( TMP, "batch.txt" ), "w" ).write( "callers escapeXml\nuses escapeXml\n" )
# …and the STATES a clean checkout reaches that a developer's does not (rv-r1-L1-2): a DETACHED HEAD (how CI checks out:
# --handoff says detached=), a trace whose frames are stale or outside every root, an older --pr-context base with
# author/partner/caller rows, a --quality-delta ref pair. The detached repo is built here, so the row does not depend on
# how this tree happens to be checked out.
DET = os.path.join( TMP, "detached" )
os.makedirs( os.path.join( DET, "src" ), exist_ok = True )
open( os.path.join( DET, "src", "a.c" ), "w" ).write( "int alpha( int n ) { return n + 1; }\n" )
gitc = [ "git", "-c", "user.email=g@example.invalid", "-c", "user.name=g" ]
subprocess.run( [ "git", "init", "-q", DET ], capture_output = True )
subprocess.run( gitc + [ "-C", DET, "add", "-A" ], capture_output = True )
subprocess.run( gitc + [ "-C", DET, "commit", "-qm", "one" ], capture_output = True )
open( os.path.join( DET, "src", "a.c" ), "a" ).write( "int beta( int n ) { return alpha( n ) * 2; }\n" )
subprocess.run( gitc + [ "-C", DET, "commit", "-qam", "two" ], capture_output = True )
subprocess.run( [ "git", "-C", DET, "checkout", "-q", "--detach", "HEAD" ], capture_output = True )
CYC = os.path.join( TMP, "cycle", "src" )
os.makedirs( CYC, exist_ok = True )
open( os.path.join( CYC, "a.h" ), "w" ).write( '#include "b.h"\nint fa();\n' )
open( os.path.join( CYC, "b.h" ), "w" ).write( '#include "a.h"\nint fb();\n' )
open( os.path.join( CYC, "c.py" ), "w" ).write( 'def f():\n    import json\n    return json\n' )
open( os.path.join( TMP, "stale.txt" ), "w" ).write( "#0 0x1 in escapeXml serialize.h:900\n#1 0x2 in emitTo main.cpp:3\n#2 0x3 in nosuch /usr/lib/x.so:1\n" )
ROSTER += [
    ( "handoff-detached-default", [ DET,   "--handoff" ] ),
    ( "deps-cycle-default",       [ CYC,   "--deps" ] ),
    ( "pr-context-wide-default",  [ ROOT,  "--pr-context=HEAD~30", "--token-budget=60000" ] ),
    ( "stale-line-trace-default", [ SMALL, "--from-trace=" + os.path.join( TMP, "stale.txt" ), "--token-budget=4000" ] ),
    ( "from-trace-stale-default", [ SMALL, "--from-trace=" + os.path.join( TMP, "stale.txt" ) ] ),
    ( "pr-context-old-default",   [ ROOT,  "--pr-context=HEAD~30" ] ),
    ( "quality-delta-refs-default", [ ROOT, "--quality-delta=HEAD~5..HEAD" ] ),
    ( "doctor-root-default",      [ ROOT,  "--doctor" ] ),
    ( "quality-panel-default",    [ SMALL, "--quality-panel" ] ),
    ( "comment-coherence-default",[ SMALL, "--comment-coherence" ] ),
    ( "dmm-default",              [ ROOT,  "--dmm=HEAD~5" ] ),
    ( "naming-calibration-default", [ SMALL, "--naming-calibration" ] ),
    ( "query-default",            [ SMALL, "--query=rank symbols" ] ),
    ( "regex-default",            [ SMALL, "--regex=esc.*Xml" ] ),
    ( "expand-split-default",     [ os.path.join( ROOT, "test", "zoomfix" ), "--expand=mathStepF1" ] ),
]
# TRAIN 9 (rv-r1-L1-3's LOW): six more states an all-instances probe reached and the rows above do not. Each one
# was RED here before the readings that close it. A LAYERED tree (a directory component matching a built-in arch
# layer) is what puts layer= on a from-trace <d> row and on the ride-along map's <f> rows; ambiguity plus a tiny
# pack budget is the cheapest way to make --expand serve a bundle WITH that map. --handoff needs a budget that
# actually cuts heuristic rows before budget=/withheld_rows= exist, --run-trace's <run>/<lines> record is a whole
# element family the compact posture answers for under from-trace's key, and --field-affinity's per-cause refusals
# and --external-surface's builtins_excluded= are nonzero only on a corpus the size of this repository.
LAY = os.path.join( TMP, "layered" )
for d, f, body in [ ( "render", "engine.h", '#include "math/tick.h"\nint ambFn(){ return utilTick(); }\nint engineStep(){ return ambFn(); }\n' ),
                    ( "math",   "tick.h",   'int utilTick(){ return 1; }\nint ambFn(){ return 2; }\n' ),
                    ( "game",   "main.cc",  '#include "render/engine.h"\nint appMain(){ return engineStep(); }\n' ) ]:
    os.makedirs( os.path.join( LAY, d ), exist_ok = True )
    open( os.path.join( LAY, d, f ), "w" ).write( body )
open( os.path.join( TMP, "layered.txt" ), "w" ).write( "#0 0x1 in utilTick math/tick.h:1\n#1 0x2 in engineStep render/engine.h:3\n" )
ROSTER += [
    ( "handoff-budget-default",     [ ROOT, "--handoff", "--token-budget=800" ] ),
    ( "run-trace-default",          [ SMALL, "--run-trace=echo ripwire-legend-probe" ] ),
    ( "field-affinity-root-default",[ ROOT, "--field-affinity" ] ),
    ( "external-surface-root-default", [ ROOT, "--external-surface" ] ),
    ( "from-trace-layered-default", [ LAY,  "--from-trace=" + os.path.join( TMP, "layered.txt" ) ] ),
    ( "expand-layered-map-default", [ LAY,  "--expand=ambFn", "--pack-budget-bytes=80" ] ),
]
ROSTER += [
    ( "expand-bundle-default",    [ SMALL, "--expand=pageWindow" ] ),
    ( "expand-file-default",      [ SMALL, "--expand=emitTo" ] ),
    ( "lego-default",             [ SMALL, "--lego=Config" ] ),
    ( "slice-default",            [ SMALL, "--slice=escapeXml" ] ),
    ( "flags-default",            [ SMALL, "--flags" ] ),
    ( "doctor-default",           [ ROOT,  "--doctor" ] ),
    ( "partition-default",        [ SMALL, "--pack-task=estimate tokens", "--partition=2" ] ),
    ( "pack-task-budget-default", [ SMALL, "--pack-task=rank symbols by pagerank", "--token-budget=1200" ] ),
    ( "from-trace-default",       [ SMALL, "--from-trace=" + os.path.join( TMP, "trace.txt" ) ] ),
    ( "from-trace-budget-default",[ SMALL, "--from-trace=" + os.path.join( TMP, "trace.txt" ), "--token-budget=600" ] ),
    ( "batch-default",            [ SMALL, "--batch=" + os.path.join( TMP, "batch.txt" ) ] ),
    ( "withheld-map-default",     [ SMALL, "--token-budget=50" ] ),
    ( "pack-signatures-default",  [ SMALL, "--pack-signatures" ] ),
    ( "pack-top-n-default",       [ SMALL, "--pack-top-n=2" ] ),
    ( "lint-catalog-default",     [ SMALL, "--lint-catalog" ] ),
    ( "skipped-default",          [ SMALL, "--skipped" ] ),
    ( "nonlocal-state-default",   [ SMALL, "--nonlocal-state" ] ),
    ( "field-affinity-default",   [ SMALL, "--field-affinity" ] ),
    ( "safe-delete-default",      [ SMALL, "--safe-delete=escapeXml" ] ),
    ( "handoff-default",          [ ROOT,  "--handoff" ] ),
    ( "graph-query-default",      [ SMALL, "--graph-query=all" ] ),
    ( "match-default",            [ SMALL, "--match=(function_definition)" ] ),
    ( "verify-default",           [ SMALL, "--verify=calls(main,escapeXml)" ] ),
    ( "impact-columnar-default",  [ SMALL, "--impact=escapeXml", "--format=columnar" ] ),
]

# the v1 core row keys, defined verbatim in every map legend and re-stated in the row dictionaries — excluded
# so the report is about the attributes that genuinely have no home, not about the seven everyone knows.
CORE = { "p", "n", "t", "id", "l", "k", "c" }

LEAD = re.compile( rb'\A(?:\s*<!--.*?-->)+', re.S )
ATTR = re.compile( rb'<([a-zA-Z][\w-]*)((?:\s+[\w:.-]+="[^"]*")*)\s*/?>' )

def legendOf( doc, anyRoot = False ):
    m    = LEAD.match( doc )
    lead = m.group( 0 ) if m else b""
    rest = doc[ len( lead ): ]
    # <ctx …><!-- legend --> wrappers; <files> = the --for file page (forpage.h). The DEFAULT rows (arm G) read the comments
    # right after ANY root's open tag — where the compact layer writes the legend of a verb whose full dialect put its prose
    # inside the root (--batch): the first thing a reader meets either way. The full rows keep the narrower read their floor
    # was recorded with.
    wrap = rb'[\w-]+' if anyRoot else rb'(?:ctx|files)'
    m2   = re.match( rb'\A\s*<' + wrap + rb'\b[^>]*>((?:\s*<!--.*?-->)+)', rest, re.S )
    if m2: lead += m2.group( 1 )
    return lead.decode( 'utf-8', 'replace' )

# The two predicates. `mentioned` is the generous one (arm A); `defined` is the house definition shape
# `name=` (arm B). The lookbehind is what makes `defined` mean the attribute rather than a suffix of some
# other one: it stops `top=` matching inside `of_top=` and `total=` inside `subtotal=`. `mentioned` implies
# nothing about `defined`, but `defined` must imply `mentioned` — arm (D) asserts that, since an attribute
# name spelled `name=` always contains the name.
def mentioned( a, legend ): return re.search( r'\b' + re.escape( a ) + r'\b', legend ) is not None
def defined  ( a, legend ): return re.search( r'(?<![\w:.-])' + re.escape( a ) + r'\s*=', legend ) is not None

# The heaviest calls go first (measured 2026-10-13, dev machine: --pr-context=HEAD~30 ±budget 50-105 s, --quality-delta
# 12-16 s, --naming-calibration 9 s, --merge-scout / --dmm 5-8 s; everything else <= 5 s). Scheduling only — no verdict.
HEAVY   = ( "--pr-context=HEAD~30", "--quality-delta", "--naming-calibration", "--merge-scout", "--dmm" )
RESULTS = runAll( BIN, [ args for _, args in ROSTER ],
                  first = lambda a: any( x.startswith( HEAVY ) for x in a ), last = isDoctor )

emitted, gapsMentioned, gapsDefined, silent, table, callfail = set(), set(), set(), [], [], []
for ( name, args ), ( doc, err ) in zip( ROSTER, RESULTS ):
    if err is not None:
        callfail.append( f"{name}: {err}: ripwire {' '.join( args )}" );  continue
    if not doc.strip():
        silent.append( name );  table.append( ( name, 0, [], [] ) );  continue
    isDefault = name.endswith( "-default" )
    legend, seen, order = legendOf( doc, anyRoot = isDefault ), {}, []
    # A DEFAULT row reads EVERY instance of every element (rv-r1-L1-2: a rare conditional attribute on the second <c> row, or
    # a row only a detached HEAD prints, escaped a first-instance sample), outside comments and CDATA. The full rows keep the
    # first-instance window their floor was recorded with.
    scan = re.sub( rb'<!--.*?-->', b'', re.sub( rb'<!\[CDATA\[.*?\]\]>', b'', doc, flags = re.S ), flags = re.S ) if isDefault else doc
    for m in ATTR.finditer( scan ):
        tag = m.group( 1 ).decode()
        attrs = [ a.decode() for a in re.findall( rb'\s([\w:.-]+)="', m.group( 2 ) ) ]
        if tag in seen:
            if isDefault:
                seen[ tag ] += [ a for a in attrs if a not in seen[ tag ] ]
            continue
        seen[ tag ] = attrs
        order.append( tag )
    keys = sorted( { f"{tag}@{a}" for tag in order for a in seen[ tag ] if a not in CORE } )
    gm   = [ k for k in keys if not mentioned( k.split( '@', 1 )[1], legend ) ]
    gd   = [ k for k in keys if not defined  ( k.split( '@', 1 )[1], legend ) ]
    for k in keys: emitted.add( f"{name} | {k}" )
    for g in gm:   gapsMentioned.add( f"{name} | {g}" )
    for g in gd:   gapsDefined.add(   f"{name} | {g}" )
    # .encode(), not len() — trap #17 / §B12.10, and this field was printing "legend=963B" for a legend of
    # 969 BYTES: three em-dashes in the --pack-task legend cost 2 bytes each over their character count.
    # Unasserted INFO, but it is labelled B and this round has already paid a MED for exactly this.
    table.append( ( name, len( legend.encode( 'utf-8' ) ), gm, gd ) )

base = { l.strip() for l in open( BASELINE, encoding = 'utf-8' )
         if l.strip() and not l.startswith( '#' ) }
# L1 fix round: the DEFAULT rows are judged by arm (G) alone — every attribute defined (`name=`), no floor. They leave the
# ratchet's sets, so (A)/(B) keep meaning exactly what they meant for the full dialect's rows.
isDefaultRow  = lambda line: line.split( ' | ', 1 )[ 0 ].endswith( '-default' )
defaultGaps   = { g for g in gapsDefined if isDefaultRow( g ) }
defaultRows   = { e.split( ' | ', 1 )[ 0 ] for e in emitted if isDefaultRow( e ) }
defaultKeys   = sum( 1 for e in emitted if isDefaultRow( e ) )
gapsMentioned = { g for g in gapsMentioned if not isDefaultRow( g ) }
gapsDefined   = { g for g in gapsDefined if not isDefaultRow( g ) }
emitted       = { e for e in emitted if not isDefaultRow( e ) }
if any( isDefaultRow( l ) for l in base ):
    print( "the full dialect's floor holds <row>-default lines — the default posture has no floor", file = sys.stderr )

# every list is written LINE-TERMINATED: a final line with no "\n" makes `wc -l` under-count by one, and
# the first draft of this gate reported "0 NEW" while printing one (its own §B12.10, one file over).
def writeLines( path, items ):
    with open( os.path.join( TMP, path ), "w" ) as f:
        for it in sorted( items ): f.write( it + "\n" )
grey = gapsDefined - gapsMentioned                   # discussed in prose, never spelled `name=`
writeLines( "new",       gapsMentioned - base )                   # (A) fails
writeLines( "definedby", ( base & emitted ) - gapsDefined )       # (B1) the legend now defines it
writeLines( "gone",      base - emitted )                         # (B2) the verb no longer emits it
writeLines( "notnested", gapsMentioned - gapsDefined )            # (D) must be empty by construction
writeLines( "silent",    silent )
writeLines( "callfail",  callfail )                               # TIMEOUT/ERROR rows fail on their own
writeLines( "defaultgaps", defaultGaps )                          # (G) fails
with open( os.path.join( TMP, "defaultcount" ), "w" ) as f: f.write( f"{len( defaultRows )} {defaultKeys}\n" )
closed = len( ( base & emitted ) - gapsDefined ) + len( base - emitted )
print( f"COUNTS live={len(gapsMentioned)} baseline={len(base)} new={len(gapsMentioned-base)} "
       f"closed={closed} grey={len(grey)} silent={len(silent)}" )
if os.environ.get( "LEGENDCOV_LIST" ):
    for name, lb, gm, gd in table:
        print( f"  {name:20s} legend={lb:5d}B undefined={len(gm):2d} grey={len(gd)-len(gm):2d}  {' '.join(gm)}" )
    print( "  GREY (prose-only, asserted by neither arm): " + " · ".join( sorted( grey ) ) )
PY

if [ -s "$TMP/pyerr" ]; then no "the sweep itself failed: $( head -c 300 "$TMP/pyerr" )"; echo "$fail" >/dev/null; fi
cat "$TMP/out"

# A roster call that TIMED OUT or died on a signal has no document to judge: it is named here as what it is, and the gate
# fails on it — it is neither "silent" (C) nor a document with no gaps (A)/(G).
if [ -s "$TMP/callfail" ]; then
    while IFS= read -r l; do no "$l"; done <"$TMP/callfail"
elif [ ! -f "$TMP/callfail" ]; then
    no "the roster sweep did not record its call outcomes — no verdict below can be trusted"
fi

# (A) the ratchet: no NEW undefined attribute on any first screen.
if [ -s "$TMP/new" ]; then
    no "(A) $( wc -l < "$TMP/new" | tr -d ' ' ) NEW undefined first-screen attribute(s) — define them in that verb's own legend, or add the line to $BASELINE with the reason:"
    sed 's/^/          /' "$TMP/new"
else
    ok "(A) no new undefined first-screen attribute (ratchet holds)"
fi

# (B) shrink candidates — an improvement, printed with the exact lines to delete. NOT a failure: a verb that
#     legitimately emits fewer rows in another environment would make this flake, and a flaky ratchet is a
#     ratchet nobody re-pins. Judged by `defined` (name=), NOT by `mentioned`, so a line is only called closed
#     when the legend really defines it — see the TWO PREDICATES block at the top. Split by CAUSE: (B1) needs
#     the legend text quoted in the deleting commit, (B2) has none to quote.
if [ -s "$TMP/definedby" ]; then
    printf '  ..    (B1) %s baseline line(s) are now DEFINED in that verb'"'"'s legend — delete them from the baseline, quoting the legend text that closed them:\n' "$( wc -l < "$TMP/definedby" | tr -d ' ' )"
    sed 's/^/          /' "$TMP/definedby"
fi
if [ -s "$TMP/gone" ]; then
    printf '  ..    (B2) %s baseline line(s) are no longer EMITTED at all (tree/shape dependent — verify before deleting; there is no legend text to cite):\n' "$( wc -l < "$TMP/gone" | tr -d ' ' )"
    sed 's/^/          /' "$TMP/gone"
fi
if [ ! -s "$TMP/definedby" ] && [ ! -s "$TMP/gone" ]; then
    ok "(B) every baseline line still reproduces (the floor is not stale)"
fi

# (G) THE DEFAULT POSTURE DEFINES EVERYTHING IT EMITS (L1 fix round, rv-r1-L1 HIGH-1). Every <row>-default twin — the answer
#     a caller gets without asking for a posture — must define, in its own leading legend and in the `name=` form, every
#     attribute its first screen carries (the root and the first instance of every element). No floor. Guarded against
#     passing emptily: the default twins must have run and emitted attributes.
read -r nDefRows nDefKeys < "$TMP/defaultcount" 2>/dev/null || { nDefRows=0; nDefKeys=0; }
if [ "${nDefRows:-0}" -lt 40 ] || [ "${nDefKeys:-0}" -lt 400 ]; then
    no "(G) only ${nDefRows:-0} default rows / ${nDefKeys:-0} attributes were read — the default twins did not run, so (G) proves nothing"
elif [ -s "$TMP/defaultgaps" ]; then
    no "(G) $( wc -l < "$TMP/defaultgaps" | tr -d ' ' ) attribute(s) a DEFAULT answer emits with no definition (name=) in its own legend — define each in src/compactlegend.h (kCompactCompletenessTerms, key-qualified) or the verb's native compact legend:"
    sed 's/^/          /' "$TMP/defaultgaps"
else
    ok "(G) every attribute the default posture emits is defined in its own legend: $nDefKeys attributes over $nDefRows default rows, no floor"
fi

# (C) the one way (A) could pass without the property holding: a roster verb that emits nothing has no
#     attributes and therefore no gaps. Silent entries are named, and any beyond the known-silent set fail.
KNOWN_SILENT=""
if [ -s "$TMP/silent" ]; then
    UNEXPECTED="$( grep -vxF -e "$KNOWN_SILENT" "$TMP/silent" 2>/dev/null || cat "$TMP/silent" )"
    if [ -n "$UNEXPECTED" ]; then
        no "(C) roster verb(s) produced NO output — a silent verb has no attributes and would pass (A) for the wrong reason: $( printf '%s' "$UNEXPECTED" | tr '\n' ' ' )"
    else
        ok "(C) every roster verb produced a document"
    fi
else
    ok "(C) every roster verb produced a document"
fi

# (D) the two predicates must NEST: `defined` (name=) is strictly stronger than `mentioned` (bare name), so
#     every gap arm (A) reports must also be a gap under arm (B)'s predicate. If that ever inverts, (A) could
#     fail on the very line (B) had just told someone to delete. Empty by construction — asserted, not assumed.
if [ -s "$TMP/notnested" ]; then
    no "(D) the two predicates no longer nest — $( wc -l < "$TMP/notnested" | tr -d ' ' ) attribute(s) are a gap under 'mentioned' but not under 'defined', which is impossible unless one predicate changed:"
    sed 's/^/          /' "$TMP/notnested"
else
    ok "(D) predicates nest (every 'mentioned' gap is also a 'defined' gap) — arm (A) can never fail a line arm (B) just closed"
fi

# (E) A DROPPED-LEGEND NOTE MAY ONLY NAME ATTRIBUTES ITS OWN DIALECT REALLY DEFINED (0.6.1, the L1 lane).
#
# The roster above answers "is this attribute defined here?". It cannot answer the question rung zero
# introduced, which is the opposite one: the ceiling ladder's rung zero DROPS legend clauses and splices a
# sentence naming the attributes whose definitions just went (verbs_for.h kForLegendDroppedNote). That
# sentence is the ONE place a budgeted reader is told where a definition went, and it is self-defeating in
# two ways the roster is blind to:
#
#   (i)  it spells each name as `name=`, which is the roster's own `defined` shape — so the note closes its
#        own gaps, and arm (A) goes green on the very run where the legend was cut. A note naming an
#        attribute nothing ever defined would look exactly like a note that told the truth.
#   (ii) the two dialects do not carry the same clauses. `--legend=compact` never defined budget_tokens= or
#        max_tokens= at all, so telling a compact reader those were "dropped (ceiling)" is a false statement
#        about a missing feature — the precise confusion the note exists to prevent.
#
# THE ASSERTION, which needs no knowledge of which clause holds which name: run the SAME query in the SAME
# dialect at a budget wide enough that no rung fires, and require that every `name=` the note spelled is
# defined there. A definition that comes back when the budget is lifted was dropped by the ceiling; one that
# does not was never in that dialect, and the note is claiming a cut that never happened. Both guards that
# keep this from passing emptily are asserted, not assumed: the note must be PRESENT on the tight run (else
# the probe budget has drifted off the rung) and ABSENT on the wide one (else "wider" proves nothing).
# (F) …and the census that keeps ELEMENT-BLINDNESS from turning into a silent closure. Rung zero's note spells
# `total= shown= capped=` about the <tail>, and the budgeted document carries those same three names on <sigs>
# too, whose own clause (the bundle=auto/compact legend) the enrichment's `legendOff` dropped independently. The
# predicate cannot tell the two apart, so the note closes six keys while describing three. That is not this
# note's doing — measured on the base binary, whichever of the two clauses survives closes BOTH elements' trios
# on every other --for row, so the pair has never been separately visible — but it must not be invisible either.
# So the exact set is PINNED below, printed on every run, and a key ENTERING it fails: the next time a legend
# clause is dropped somewhere and a shared name papers over it, the census names the key. A key LEAVING is a
# shrink candidate, not a failure (arm (B)'s discipline: the budgeted document's shape moves with the corpus).
python3 - "$BIN" "$ROOT" "$TMP" <<'PY' > "$TMP/noteout" 2>"$TMP/noteerr"
import subprocess, re, sys, os

BIN, ROOT, TMP = sys.argv[1:4]
SMALL = os.path.join( ROOT, "src" )
QUERY = "--for=rank symbols by pagerank"
# TIGHT is MID-RUNG, and MARGIN is what proves it. The rung-zero band's top edge moves with the length of
# the checkout path, because the document charges its own `root="…"` bytes. Bisected on this tree, same commit
# and binary, only the root differing: a 38-character root fires rung zero at 1287 and NOT at 1288; a
# 137-character root fires at 1323 and not at 1324. The old TIGHT of 1300 sat BETWEEN those two numbers, so
# this arm was green on a developer worktree and red on every CI runner (CI checks out at 33-34 characters).
# A budget that only fires on the machine that chose it is not a probe. TIGHT=900 sits 387 tokens below the
# SHORTEST measured edge, and the band is flat beneath it — from 100 up to the edge the note's text and arm
# (F)'s census do not change — so this is mid-rung, not a tolerance. Both edges move when src/ changes (this
# lane re-measured them across a merge that added a 385-line file, and the short one moved by a single token),
# which is the other reason the headroom is gated below rather than trusted here.
# MARGIN re-runs the same query 200 tokens ABOVE TIGHT and requires the note there too, which turns "the
# probe has headroom" from a claim in this comment into a row that fails when it stops being true.
TIGHT, MARGIN, WIDE = "--token-budget=900", "--token-budget=1100", "--token-budget=8000"
CORE = { "p", "n", "t", "id", "l", "k", "c" }

# The (F) floor: keys whose ONLY definition on the budgeted document is the rung-zero note, AND whose attribute
# name the document carries on more than one element — so the closure cannot be attributed to a clause. Both
# elements' trios are here because `defined` sees one name: <tail>'s three are what the note is ABOUT, <sigs>'s
# three are legendOff's and are closed by the same three words. Do not add a line here to make a red go away
# without saying, in the commit, which clause was dropped and why it is not worth a sentence of its own.
# SHRUNK 2026-09-13 (PR #215 review item 10): the compact dialect's four lines stopped reproducing and the arm
# had been printing "verify, then shrink the FLOOR in this file" for four runs without anyone shrinking it — a
# floor that outlives its findings is a floor nobody reads. They are gone because this dialect's rung zero no
# longer fires on these documents: it is taken only when the drop PAYS (verbs_for.h), and in the compact dialect
# the note was longer than the clauses it replaced, so the readings ride and close their own attributes.
# L1: "default" named the FULL dialect until the CLI default became compact; the dialect is now asked for by name, and
# its floor moved with it unchanged. The default posture is checked as its own row with the floor of the dialect it
# resolves to (compact today), so a default that changes cannot inherit a floor written for another dialect.
FLOOR = { "full":    { "sigs@capped", "sigs@shown", "sigs@total", "tail@capped", "tail@shown", "tail@total" },
          "compact": set(),
          "default": set() }

LEAD = re.compile( rb'\A(?:\s*<!--.*?-->)+', re.S )
ATTR = re.compile( rb'<([a-zA-Z][\w-]*)((?:\s+[\w:.-]+="[^"]*")*)\s*/?>' )
NOTE = re.compile( r'\[legend clauses:[^\]]*\]' )
NAME = re.compile( r'(?<![\w:.-])([A-Za-z_][\w]*)=' )

def legendOf( doc ):
    m    = LEAD.match( doc )
    lead = m.group( 0 ) if m else b""
    rest = doc[ len( lead ): ]
    m2   = re.match( rb'\A\s*<ctx\b[^>]*>((?:\s*<!--.*?-->)+)', rest, re.S )
    if m2: lead += m2.group( 1 )
    return lead.decode( 'utf-8', 'replace' )

def defined( a, legend ): return re.search( r'(?<![\w:.-])' + re.escape( a ) + r'\s*=', legend ) is not None

# The nine calls below (3 dialects x TIGHT/WIDE/MARGIN) run up front on the shared pool; doc() serves them. A call that
# timed out or died has NO document: doc() raises, and the dialect's verdict is that TIMEOUT/ERROR line — never the
# "note ABSENT" an empty string would otherwise read as.
sys.path.insert( 0, TMP )
from lcrun import runAll
class CallFailed( Exception ): pass
DIALECTS = ( ( "full", [ "--legend=full" ] ), ( "compact", [ "--legend=compact" ] ), ( "default", [] ) )
ARGVS    = [ [ SMALL, QUERY, b ] + extra for _, extra in DIALECTS for b in ( TIGHT, WIDE, MARGIN ) ]
DOCS     = { tuple( a ): r for a, r in zip( ARGVS, runAll( BIN, ARGVS ) ) }
def doc( args ):
    out, err = DOCS[ tuple( args ) ]
    if err is not None: raise CallFailed( f"{err}: ripwire {' '.join( args )}" )
    return out

def attrsOf( d ):
    seen, order = {}, []
    for m in ATTR.finditer( d ):
        tag = m.group( 1 ).decode()
        if tag in seen: continue
        seen[ tag ] = [ a.decode() for a in re.findall( rb'\s([\w:.-]+)="', m.group( 2 ) ) ]
        order.append( tag )
    return order, seen

bad, checked, entered, left, census = [], 0, [], [], []
for dialect, extra in DIALECTS:
    # Each of the three calls is judged on its own, so two failed calls report two lines, not the first only.
    docs, fails = [], []
    for b in ( TIGHT, WIDE, MARGIN ):
        try:
            docs.append( doc( [ SMALL, QUERY, b ] + extra ) )
        except CallFailed as e:
            fails.append( f"{dialect}: {e}" )
    if fails:
        bad.extend( fails )
        continue
    dt, dw, dm = docs
    tight, wide = legendOf( dt ), legendOf( dw )
    mt, mw      = NOTE.search( tight ), NOTE.search( wide )
    if not mt:
        bad.append( f"{dialect}: the dropped-legend note is ABSENT at {TIGHT} — the probe no longer climbs rung zero, so this arm checks nothing; re-anchor the budget" )
        continue
    if mw:
        bad.append( f"{dialect}: the dropped-legend note is STILL THERE at {WIDE} — 'a wider token-budget' is not wide enough to be the control, so nothing below is evidence" )
        continue
    # HEADROOM, gated rather than asserted in a comment: the same query 200 tokens above TIGHT must still
    # climb rung zero. This is the arm that would have caught the old 1300 on the machine that chose it —
    # a probe one step from the rung's top edge passes locally and fails wherever the charged bytes differ,
    # and the checkout path length alone is enough to move them.
    if not NOTE.search( legendOf( dm ) ):
        bad.append( f"{dialect}: the note is present at {TIGHT} but ABSENT at {MARGIN} — the probe is within 200 tokens of the rung's TOP edge, so it no longer fires on a document any smaller (a shorter checkout path is enough). Re-anchor TIGHT to the middle of the measured band, do not widen a tolerance" )
        continue
    names = sorted( set( NAME.findall( mt.group( 0 ) ) ) )
    if not names:
        bad.append( f"{dialect}: the note names no attribute at all ({mt.group(0)[:80]}…) — it cannot tell a reader which definition went" )
        continue
    for a in names:
        checked += 1
        if not defined( a, wide ):
            bad.append( f"{dialect}: the note says {a}= was dropped (ceiling), but the same query at {WIDE} does not define {a}= either — that definition is not in this dialect, so the note reports a cut that never happened" )
    # (F): sole-closure ∩ shared-name, against this dialect's floor.
    bare        = tight.replace( mt.group( 0 ), "" )
    order, seen = attrsOf( dt )
    onElements  = {}
    for tag in order:
        for a in seen[ tag ]:
            onElements.setdefault( a, set() ).add( tag )
    live = { f"{tag}@{a}" for tag in order for a in seen[ tag ]
             if a not in CORE and len( onElements[ a ] ) > 1 and defined( a, tight ) and not defined( a, bare ) }
    census.append( f"{dialect}: {' '.join( sorted( live ) ) if live else '(none)'}" )
    entered += [ f"{dialect} | {k}" for k in sorted( live - FLOOR[ dialect ] ) ]
    left    += [ f"{dialect} | {k}" for k in sorted( FLOOR[ dialect ] - live ) ]

def writeLines( path, items ):
    with open( os.path.join( TMP, path ), "w" ) as f:
        for it in items: f.write( it + "\n" )
writeLines( "notegaps", bad )
writeLines( "censusnew", entered )
writeLines( "censusgone", left )
print( f"NOTECOUNTS names_checked={checked} bad={len(bad)}" )
for line in census: print( f"  SHARED-NAME SOLE CLOSURE  {line}" )
PY

if [ -s "$TMP/noteerr" ]; then no "(E) the dropped-note sweep itself failed: $( head -c 300 "$TMP/noteerr" )"; fi
cat "$TMP/noteout"
# forbudget-soft (owner decisions 2026-10-14; rule 4): an explicit --token-budget on --for is a SOFT target, so no ceiling
# ladder runs and rung zero's note can no longer ride: at the tight probe budget the legend must be WHOLE in every dialect
# (HL) — the note ABSENT, which is exactly what the sweep reports as "ABSENT". Every first-screen attribute of that answer is
# still defined by its own legend (arm (A) runs the same roster). A note that rides again is the regression this now catches.
ABSENT_ONLY=0
if [ -s "$TMP/notegaps" ] && ! grep -qv 'the dropped-legend note is ABSENT at --token-budget=' "$TMP/notegaps"; then ABSENT_ONLY=1; fi
if [ "$ABSENT_ONLY" = 1 ] && [ "$( wc -l < "$TMP/notegaps" | tr -d ' ' )" -ge 3 ]; then
    ok "(E) no dropped-legend note in any dialect at the tight probe budget — a soft target never sheds a legend clause (HL; full, compact, default)"
elif [ ! -s "$TMP/notegaps" ] && grep -q 'names_checked=[1-9]' "$TMP/noteout" 2>/dev/null; then
    no "(E) a dropped-legend note rides a soft --for target again — the header was shed (HL)"
elif [ ! -s "$TMP/notegaps" ] && ! grep -q 'names_checked=[1-9]' "$TMP/noteout" 2>/dev/null; then
    no "(E) the dropped-note sweep checked ZERO attribute names — a sweep with an empty population passes for the wrong reason"
elif [ -s "$TMP/notegaps" ]; then
    no "(E) $( wc -l < "$TMP/notegaps" | tr -d ' ' ) dropped-legend note problem(s) — the note names a definition its own dialect does not have, or the probe has drifted off the rung:"
    sed 's/^/          /' "$TMP/notegaps"
else
    ok "(E) every attribute the rung-zero note names is defined by the same query at a wider budget, in both dialects (the note reports real cuts, not missing features)"
fi

if [ -s "$TMP/censusnew" ]; then
    no "(F) $( wc -l < "$TMP/censusnew" | tr -d ' ' ) key(s) newly closed ONLY by the rung-zero note, under a name the same document carries on another element — which clause really dropped, and does it need a sentence of its own?"
    sed 's/^/          /' "$TMP/censusnew"
elif [ -s "$TMP/censusgone" ]; then
    printf '  ..    (F) %s pinned shared-name closure(s) no longer reproduce (shape-dependent — verify, then shrink the FLOOR in this file):\n' "$( wc -l < "$TMP/censusgone" | tr -d ' ' )"
    sed 's/^/          /' "$TMP/censusgone"
    ok "(F) no NEW shared-name sole closure (the census above is the pinned set, minus the lines just listed)"
else
    ok "(F) the shared-name sole-closure census is exactly its pinned floor — nothing new hides behind a name this document carries twice"
fi

# (H) A BINARY FILE ON AN UNMERGED BRANCH (0.6.6). --stray-content reports a path it cannot line-diff (a binary or oversized
#     blob on some side) as a <file … diffable="0"/> row with its counts zeroed. The row is conditional on the TREE, so the
#     roster rows above see it only when the checkout they run in happens to hold a local branch with a binary on it — which
#     is how it was found: arm (G) went red in a developer clone and green on CI, and no legend defined diffable=. This arm
#     builds that state in a throwaway repo so the property is checked on every run: a text file AND a binary on an unmerged
#     branch, then every attribute the CLI default answer and its MCP twin (stray_content, default legend) emit must be
#     defined (`name=`, arm (B)'s predicate) in the answer's own legend, and the full legend must define diffable= too.
#     (H0) is the precondition: an answer with no diffable="0" row proves nothing.
BR="$TMP/binref"
mkdir -p "$BR/src"
gitb(){ env -u GIT_DIR -u GIT_WORK_TREE git -c user.email=g@example.invalid -c user.name=g -c commit.gpgsign=false -C "$BR" "$@"; }
gitb init -q
printf 'int alpha( int n ) { return n + 1; }\n' >"$BR/src/a.c"
gitb add -A; gitb commit -qm one
gitb checkout -q -b side
printf '\211PNG\r\n\032\n\000\000\000\rIHDR\000\001\002' >"$BR/logo.png"
printf 'int beta( int n ) { return n * 2; }\n' >"$BR/src/b.c"
gitb add -A; gitb commit -qm two
gitb checkout -q -
"$BIN" "$BR" --stray-content >"$TMP/h_def" 2>/dev/null
"$BIN" "$BR" --stray-content --legend=full >"$TMP/h_full" 2>/dev/null
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"stray_content","arguments":{"path":"'"$BR"'"}}}' \
    | "$BIN" --mcp 2>/dev/null | tail -1 >"$TMP/h_mcp.json"
python3 - "$TMP" <<'PYH' >"$TMP/h_out" 2>&1
import json, os, re, sys
T = sys.argv[1]
def rd( p ): return open( os.path.join( T, p ), "rb" ).read().decode( "utf-8", "replace" )
def legendOf( doc ):
    m = re.match( r'\A(?:\s*<!--.*?-->)+', doc, re.S )
    return m.group( 0 ) if m else ""
def defined( a, legend ): return re.search( r'(?<![\w:.-])' + re.escape( a ) + r'\s*=', legend ) is not None
def gaps( doc ):
    legend = legendOf( doc )
    body   = re.sub( r'<!--.*?-->', '', re.sub( r'<!\[CDATA\[.*?\]\]>', '', doc, flags = re.S ), flags = re.S )
    keys   = set()
    for m in re.finditer( r'<([a-zA-Z][\w-]*)((?:\s+[\w:.-]+="[^"]*")*)\s*/?>', body ):
        for a in re.findall( r'\s([\w:.-]+)="', m.group( 2 ) ):
            if a not in { "p", "n", "t", "id", "l", "k", "c" }: keys.add( m.group( 1 ) + "@" + a )
    return sorted( k for k in keys if not defined( k.split( "@", 1 )[ 1 ], legend ) )
dflt, full = rd( "h_def" ), rd( "h_full" )
try:
    r   = json.loads( rd( "h_mcp.json" ) )
    mcp = r[ "result" ][ "content" ][ 0 ][ "text" ]
except Exception as e:
    mcp = ""
row = re.compile( r'<file [^>]*diffable="0"' )
print( "H0 %d %d %d" % ( bool( row.search( dflt ) ), bool( row.search( full ) ), bool( row.search( mcp ) ) ) )
print( "H1 " + " ".join( gaps( dflt ) ) )
print( "H2 " + ( "" if defined( "diffable", legendOf( full ) ) else "file@diffable" ) )
print( "H3 " + " ".join( gaps( mcp ) ) )
PYH
hline(){ sed -n "s/^$1 //p" "$TMP/h_out"; }
if [ "$( hline H0 )" = "1 1 1" ]; then
    ok "(H0) a binary on an unmerged branch is reported as a diffable=\"0\" row by the CLI default, --legend=full and the MCP twin"
else
    no "(H0) no diffable=\"0\" row (default/full/mcp = $( hline H0 )) — the fixture no longer reaches the undiffable path, so (H1)-(H3) prove nothing: $( head -c 300 "$TMP/h_out" )"
fi
[ -z "$( hline H1 )" ] && ok "(H1) the CLI default --stray-content answer defines every attribute it emits, diffable= included" \
                       || no "(H1) the CLI default --stray-content legend does not define: $( hline H1 )"
[ -z "$( hline H2 )" ] && ok "(H2) the --legend=full --stray-content legend defines diffable=" \
                       || no "(H2) the --legend=full --stray-content legend does not define: $( hline H2 )"
[ -z "$( hline H3 )" ] && ok "(H3) the MCP stray_content twin defines every attribute it emits, diffable= included" \
                       || no "(H3) the MCP stray_content legend does not define: $( hline H3 )"

# ── (S) slot bridge / hedged ring (train 34, rv-hop1-delta1 D1): HOP1's slot crossings print via= / slot_callers= /
#     slot_fns= on a SECOND <s> row and the hedged ring on <ring>/<rh>, which the roster's first-instance sweep never
#     enumerates. A C slot chain (hop1check's c3 fixture): every attribute ANY element of the answer carries must be
#     defined (`name=`) in the leading legend of --path and --impact, default and compact. (S0) is the precondition: the
#     answer really holds a via="slot" row with slot_fns= (else the arm proves nothing); (S5) is the mutation control: the
#     same probe over a copy of the legend without its slot_fns= definition reports that gap (the arm can fail).
SF="$TMP/slotfix"; mkdir -p "$SF"
cat > "$SF/chain.c" <<'CEOF'
struct entry { const char *name; void (*exec)( void ); };
struct mode { const char *name; void (*command)( int ); };
struct cmdt { const char *name; void (*f)( void ); };
struct wme { const struct mode *mode; };
struct wme *current_wme( void );
static void cancel_cmd( void ) { }
static void other_cmd( void ) { }
static const struct cmdt cmd_table[] = { { "cancel", cancel_cmd }, { "other", other_cmd } };
void copy_command( int i ) { cmd_table[i].f(); }
const struct mode copy_mode = { .name = "copy", .command = copy_command };
void send_keys_exec( void ) { struct wme *w = current_wme(); w->mode->command( 0 ); }
const struct entry send_keys_entry = { .name = "send-keys", .exec = send_keys_exec };
void fire_command( struct entry *e ) { e->exec(); }
CEOF
( cd "$SF" && "$BIN" "$SF" --no-cache --path=fire_command,cancel_cmd >"$TMP/s_pdef" 2>/dev/null
  "$BIN" "$SF" --no-cache --path=fire_command,cancel_cmd --legend=compact >"$TMP/s_pcmp" 2>/dev/null
  "$BIN" "$SF" --no-cache --impact=cancel_cmd >"$TMP/s_idef" 2>/dev/null
  "$BIN" "$SF" --no-cache --impact=cancel_cmd --legend=compact >"$TMP/s_icmp" 2>/dev/null )
python3 - "$TMP" <<'PYS' >"$TMP/s_out" 2>&1
import os, re, sys
T = sys.argv[1]
def rd( p ): return open( os.path.join( T, p ), "rb" ).read().decode( "utf-8", "replace" )
def legendOf( doc ):
    m = re.match( r'\A(?:\s*<!--.*?-->)+', doc, re.S )
    return m.group( 0 ) if m else ""
def defined( a, legend ): return re.search( r'(?<![\w:.-])' + re.escape( a ) + r'\s*=', legend ) is not None
def gaps( doc, legend = None ):
    legend = legendOf( doc ) if legend is None else legend
    body   = re.sub( r'<!--.*?-->', '', re.sub( r'<!\[CDATA\[.*?\]\]>', '', doc, flags = re.S ), flags = re.S )
    keys   = set()
    for m in re.finditer( r'<([a-zA-Z][\w-]*)((?:\s+[\w:.-]+="[^"]*")*)\s*/?>', body ):
        for a in re.findall( r'\s([\w:.-]+)="', m.group( 2 ) ):
            if a not in { "p", "n", "t", "id", "l", "k", "c" }: keys.add( m.group( 1 ) + "@" + a )
    return sorted( k for k in keys if not defined( k.split( "@", 1 )[ 1 ], legend ) )
docs = { k: rd( "s_" + k ) for k in ( "pdef", "pcmp", "idef", "icmp" ) }
slot = re.compile( r'<s [^>]*via="slot"[^>]*slot_fns="\d+"' )
ring = re.compile( r'<rh [^>]*via="slot"' )
print( "S0 %d %d %d %d" % ( bool( slot.search( docs[ "pdef" ] ) ), bool( slot.search( docs[ "pcmp" ] ) ),
                            bool( ring.search( docs[ "idef" ] ) ), bool( ring.search( docs[ "icmp" ] ) ) ) )
for k in ( "pdef", "pcmp", "idef", "icmp" ): print( "S-" + k + " " + " ".join( gaps( docs[ k ] ) ) )
cut = re.sub( r'(?<![\w:.-])slot_fns\s*=', 'slot-fns ', legendOf( docs[ "pdef" ] ) )
print( "S5 " + " ".join( gaps( docs[ "pdef" ], cut ) ) )
PYS
sline(){ sed -n "s/^$1 //p" "$TMP/s_out"; }
if [ "$( sline S0 )" = "1 1 1 1" ]; then
    ok "(S0) the slot fixture answers --path with a via=\"slot\" slot_fns= row and --impact with a <rh via=\"slot\"> ring, default and compact"
else
    no "(S0) no slot row (path def/cmp, impact def/cmp = $( sline S0 )) — (S1)-(S5) prove nothing: $( head -c 300 "$TMP/s_out" )"
fi
for k in "pdef:1:--path default" "pcmp:2:--path --legend=compact" "idef:3:--impact default" "icmp:4:--impact --legend=compact"; do
    key=${k%%:*}; rest=${k#*:}; n=${rest%%:*}; what=${rest#*:}
    if [ -z "$( sline "S-$key" )" ]; then
        ok "(S$n) the $what slot answer defines every attribute it emits (via= slot_callers= slot_fns= reaches_hedged= ring)"
    else
        no "(S$n) the $what slot answer's legend does not define: $( sline "S-$key" )"
    fi
done
case " $( sline S5 ) " in
    *" s@slot_fns "*) ok "(S5) mutation control: the probe reports s@slot_fns once the legend loses its slot_fns= definition" ;;
    *)                no "(S5) mutation control: a legend without slot_fns= still read as covered ($( sline S5 ))" ;;
esac

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "legendcoveragecheck: FAILURES ABOVE"
exit "$fail"

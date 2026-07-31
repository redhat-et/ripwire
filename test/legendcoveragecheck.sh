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
# "What would make this pass without the property holding?" (the round's own lens, trap #20). Two things,
# not one — the earlier "Exactly one thing" was wrong, and the cap above was the second. (i) a roster verb
# that stops producing output has no elements, no attributes and no gaps: arm (C) names every silent verb
# and fails. (ii) the two predicates drifting apart so that `mentioned` stops being the weaker of the two,
# which would make (A) fail on something (B) had just called closed: arm (D) asserts they still nest.
#
#   bash test/legendcoveragecheck.sh                       # build/ctxpack
#   bash test/legendcoveragecheck.sh build_base/ctxpack    # or CTXPACK_BIN=... — both seams honored
#   LEGENDCOV_LIST=1 bash test/legendcoveragecheck.sh      # print the full per-verb table (the audit view)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${CTXPACK_BIN:-$ROOT/build/ctxpack}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative binary
BASELINE="$ROOT/test/legendcoverage_baseline.txt"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -f "$BASELINE" ] || { echo "missing $BASELINE — this gate is a ratchet and cannot run without its floor"; exit 2; }

echo "legendcoveragecheck: BIN=$BIN"

python3 - "$BIN" "$ROOT" "$BASELINE" "$TMP" <<'PY' > "$TMP/out" 2>"$TMP/pyerr"
import subprocess, re, sys, os

BIN, ROOT, BASELINE, TMP = sys.argv[1:5]
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
    ("for",                [SMALL, "--for=rank symbols by pagerank"]),
    ("pack-task",          [SMALL, "--pack-task=rank symbols by pagerank"]),
    ("exemplar",           [SMALL, "--exemplar=rank symbols"]),
    ("hotspots",           [ROOT,  "--hotspots"]),
    ("clones",             [ROOT,  "--clones"]),
    ("cochange",           [ROOT,  "--cochange"]),
    ("cochange-file",      [ROOT,  "--cochange=src/cli.h"]),
    ("owners",             [ROOT,  "--owners"]),
    ("deps",               [SMALL, "--deps"]),
    ("dead-code",          [SMALL, "--dead-code"]),
    ("quality-delta",      [ROOT,  "--quality-delta"]),
    ("test-gate",          [ROOT,  "--test-gate"]),
    ("edit-check",         [SMALL, "--edit-check=escapeXml"]),
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
    ("scan-skills",        [ROOT,  "--scan-skills"]),
]

# the v1 core row keys, defined verbatim in every map legend and re-stated in the row dictionaries — excluded
# so the report is about the attributes that genuinely have no home, not about the seven everyone knows.
CORE = { "p", "n", "t", "id", "l", "k", "c" }

LEAD = re.compile( rb'\A(?:\s*<!--.*?-->)+', re.S )
ATTR = re.compile( rb'<([a-zA-Z][\w-]*)((?:\s+[\w:.-]+="[^"]*")*)\s*/?>' )

def legendOf( doc ):
    m    = LEAD.match( doc )
    lead = m.group( 0 ) if m else b""
    rest = doc[ len( lead ): ]
    m2   = re.match( rb'\A\s*<ctx\b[^>]*>((?:\s*<!--.*?-->)+)', rest, re.S )   # <ctx …><!-- legend --> wrappers
    if m2: lead += m2.group( 1 )
    return lead.decode( 'utf-8', 'replace' )

# The two predicates. `mentioned` is the generous one (arm A); `defined` is the house definition shape
# `name=` (arm B). The lookbehind is what makes `defined` mean the attribute rather than a suffix of some
# other one: it stops `top=` matching inside `of_top=` and `total=` inside `subtotal=`. `mentioned` implies
# nothing about `defined`, but `defined` must imply `mentioned` — arm (D) asserts that, since an attribute
# name spelled `name=` always contains the name.
def mentioned( a, legend ): return re.search( r'\b' + re.escape( a ) + r'\b', legend ) is not None
def defined  ( a, legend ): return re.search( r'(?<![\w:.-])' + re.escape( a ) + r'\s*=', legend ) is not None

emitted, gapsMentioned, gapsDefined, silent, table = set(), set(), set(), [], []
for name, args in ROSTER:
    doc = subprocess.run( [ BIN ] + args, capture_output = True ).stdout
    if not doc.strip():
        silent.append( name );  table.append( ( name, 0, [], [] ) );  continue
    legend, seen, order = legendOf( doc ), {}, []
    for m in ATTR.finditer( doc ):
        tag = m.group( 1 ).decode()
        if tag in seen: continue
        seen[ tag ] = [ a.decode() for a in re.findall( rb'\s([\w:.-]+)="', m.group( 2 ) ) ]
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

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "legendcoveragecheck: FAILURES ABOVE"
exit "$fail"

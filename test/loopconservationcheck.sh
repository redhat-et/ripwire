#!/usr/bin/env bash
# loopconservationcheck.sh — CONSERVATION ACROSS HISTORY for test/regression.sh's absorb loop.
#
# WHY THIS EXISTS (trap found live landing the 4692076 merge, 2026-08-22 — see that commit's own
# message). manifestcheck.sh proves the loop (the single `for _g in NAME NAME ...; do` line in
# test/regression.sh) and docs/EVALS.md's pinned counts AGREE with each other. But a merge conflict
# resolution can drop an entry from the loop while regenerating EVALS's count from that SAME damaged
# list — both sides then derive from the same wrong file, and manifestcheck passes at a
# wrong-but-consistent count. Consistency is not conservation. Landing lane/t3-anchor-only, an initial
# conflict resolution left test/anchorbodycheck.sh present on disk but absent from the loop (443, not
# 444, dropping the one entry lane/t3-anchor-only had added) — caught only by hand-counting before the
# commit landed, because nothing re-derived what the loop was SUPPOSED to contain: the union of what
# both sides of the merge already had. Reconstructed here as red-first evidence against the real
# history (see test/loopconservationcheck_selftest.sh) using the real 4692076 parents, 4b94e85 and
# 5cedd36 — a synthetic merge built from git-tree objects that already exist in this repo's history,
# not a fabricated fixture.
#
# THE CHECK: when HEAD (or the ref passed as $1) is a merge commit, the set of loop entries must equal
# the UNION of every parent's loop entries, minus any entry RETIRED with an explicit tombstone (below).
# Any entry present in a parent's loop but silently absent from the merge's own loop, and not declared
# retired, is named and fails. A non-merge ref (the overwhelming common case: an ordinary commit, or a
# repo's very first commit) passes trivially — there is no "the parents" to conserve against. An octopus
# merge (>2 parents) is handled the same way: union over ALL parents, not just the first two.
#
# THE TOMBSTONE CONVENTION: a deliberate removal is not a violation, but it must be DECLARED, not merely
# absent. In the SAME commit that drops NAME from the loop, add a standalone comment line anywhere in
# test/regression.sh of the exact form
#     # retired: NAME — reason
# This gate reads every such line from the ref's regression.sh and subtracts those names from "vanished"
# before failing on what is left. Two failure modes are checked, not just one: a name that vanished
# without a tombstone (the trap this gate exists for), and a tombstone that does not correspond to an
# actual vanish (either NAME is still in the loop, or NAME was never in any parent's loop to begin with)
# — a tombstone nobody needed is itself worth noticing, because it means the removal it documents either
# never happened or was reverted without removing the marker.
#
# WHY docs/EVALS.md's gate-count pins do NOT get this same treatment (deliberately, not an oversight):
# manifestcheck.sh already ties every "N gate scripts" / "loop ... names N" claim in EVALS.md to the
# LOOP's ACTUAL length, derived by regex from test/regression.sh, never hand-copied (see manifestcheck.sh
# — the docs/EVALS.md §8 arm and the "SIBLINGS of that number" arm below it). A silently-dropped loop
# entry changes the loop's length, which those two arms catch automatically the moment EVALS.md is
# regenerated from the (now-shorter) loop — there is no separate "did EVALS.md conserve its count"
# question, because EVALS.md's count is a pure function of the loop this gate already guards, not an
# independent fact that could drift on its own. Building a second conservation check for EVALS.md would
# check the same underlying fact twice under two names.
#
# EXEMPT FROM binoverridecheck.sh: this gate reads git history (`git show REF:test/regression.sh`) and
# never invokes the ripwire binary under test — see binoverridecheck.sh's EXEMPT table, which pins this
# file with that reason so a broken RIPWIRE_BIN sentinel cannot be expected to turn it red.
#
# USAGE: test/loopconservationcheck.sh [REF]   (default REF: HEAD). The optional ref argument exists
# for exactly one reason — testing this gate itself against a specific historical or synthetic commit
# (see the selftest) — and is never passed by regression.sh's absorb loop, which invokes every gate with
# no positional argument at all.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
REF="${1:-HEAD}"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

cd "$ROOT"
git rev-parse --verify --quiet "${REF}^{commit}" >/dev/null || { no "ref '$REF' does not resolve to a commit"; echo "FAILURES ABOVE"; exit 1; }

python3 - "$REF" <<'PY' || fail=1
import re, subprocess, sys

REF = sys.argv[1]
bad = 0
def ok( m ): print( "  PASS  %s" % m )
def no( m ):
    global bad; bad = 1; print( "  FAIL  %s" % m )

def blob( ref, path ):
    p = subprocess.run( [ "git", "show", "%s:%s" % ( ref, path ) ], capture_output=True, text=True )
    return p.stdout if p.returncode == 0 else None

def loop_names( text ):
    if text is None:
        return None
    m = re.search( r'for _g in (.*?); do', text, re.S )
    return set( m.group( 1 ).split() ) if m else None

def tombstones( text ):
    if text is None:
        return set()
    # "# retired: NAME — reason" (also tolerates a plain "-" in place of the em-dash)
    return set( re.findall( r'^\s*#\s*retired:\s*(\S+)', text, re.M ) )

parents = subprocess.run(
    [ "git", "rev-list", "--parents", "-n1", REF ], capture_output=True, text=True, check=True
).stdout.split()
parents = parents[1:]   # [0] is REF's own sha

if len( parents ) < 2:
    ok( "%s has %d parent(s) — not a merge, conservation trivially satisfied" % ( REF, len( parents ) ) )
    sys.exit( 0 )

headText = blob( REF, "test/regression.sh" )
headLoop = loop_names( headText )
if headLoop is None:
    no( "%s:test/regression.sh has no `for _g in ...; do` loop to check (file missing or shape changed)" % REF )
    sys.exit( bad )

unionParents = set()
missingParentFile = []
for par in parents:
    parText = blob( par, "test/regression.sh" )
    parLoop = loop_names( parText )
    if parLoop is None:
        missingParentFile.append( par )
        continue
    unionParents |= parLoop

if missingParentFile:
    print( "  NOTE  parent(s) with no test/regression.sh loop (pre-dates the file, or the shape changed there): %s" % ", ".join( missingParentFile ) )

retired = tombstones( headText )

vanished = unionParents - headLoop
silentlyVanished = sorted( vanished - retired )
declaredRetired = sorted( vanished & retired )

if silentlyVanished:
    no( "%d entr%s silently vanished from the loop at merge %s (present in a parent, absent from HEAD, no `# retired:` tombstone): %s" % (
        len( silentlyVanished ), "y" if len( silentlyVanished ) == 1 else "ies", REF, ", ".join( silentlyVanished ) ) )
else:
    ok( "no undeclared vanish — merge %s's loop (%d) covers the union of its %d parent(s)' loops (%d), minus %d declared retirement(s)" % (
        REF, len( headLoop ), len( parents ), len( unionParents ), len( declaredRetired ) ) )

if declaredRetired:
    ok( "retirement tombstone(s) matched an actual vanish: %s" % ", ".join( declaredRetired ) )

staleTombstones = sorted( retired - vanished )
if staleTombstones:
    no( "%d tombstone(s) do not correspond to an actual vanish (name still in the loop, or never in any parent's loop): %s" % (
        len( staleTombstones ), ", ".join( staleTombstones ) ) )
elif retired:
    ok( "no stale tombstones" )

sys.exit( bad )
PY

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"

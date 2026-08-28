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
# commit landed, because nothing re-derived what the loop was SUPPOSED to contain.
#
# WHY IT WAS REWRITTEN (2026-08-28, gate-suite health round). The original check asserted ONLY when
# the ref under test was itself a merge commit; anything with fewer than two parents printed
# "not a merge, conservation trivially satisfied" and exited 0. That was written believing rounds land
# as merges. They do not. At 1dc7b01 the history from the last real merge (ef10e5c) to HEAD was 32
# commits with ZERO merges — the entire Codex fix round (76deb29..1dc7b01) landed as a plain linear
# chain — so every invocation at the tip of a round took the trivial-pass branch and proved nothing.
# Red-first evidence, reproducible with the plumbing in arm (B) below: a synthetic single-parent commit
# that drops `qualitykeycheck` from the loop with no tombstone was reported ALL PASS by the old gate.
# That is the exact failure mode this file exists to catch.
#
# THE CHECK (arm A). Walk EVERY commit in BASE..REF that touched test/regression.sh, and compare each
# one against EACH of its OWN parents — one parent for an ordinary commit, two or more for a merge.
# The merge case is not lost, it is simply the len(parents)>1 case of the same loop; arm (C) proves it
# still fires. For a commit C with parent P:
#
#     vanished = loop(P) - loop(C) - tombstones_new(C)
#
# Any name present in a parent's loop, absent from the child's, and not declared retired IN THAT SAME
# COMMIT is named and fails.
#
# THE WINDOW. BASE is the merge-base of REF with its upstream tracking ref (falling back to
# origin/main, then origin/HEAD). If no upstream resolves, or the merge-base IS REF — the ordinary
# state on a freshly-pushed main, where the window would otherwise be empty and the gate would be
# inert all over again — BASE falls back to REF's first parent, so the newest commit is always
# examined. A root commit with no parents at all passes trivially and says so.
#
# THE TOMBSTONE CONVENTION: a deliberate removal is not a violation, but it must be DECLARED, not merely
# absent. In the SAME commit that drops NAME from the loop, add a standalone comment line anywhere in
# test/regression.sh of the exact form
#     # retired: NAME — reason
# This gate reads every such line and subtracts those names from "vanished" before failing on what is
# left. Two failure modes are checked, not just one: a name that vanished without a tombstone (the trap
# this gate exists for), and a tombstone NEWLY ADDED by a commit that does not correspond to an actual
# vanish in that commit (either NAME is still in the loop, or NAME was never in the parent's loop) — a
# tombstone nobody needed is itself worth noticing. Only NEWLY added tombstones are judged: a tombstone
# is permanent once written, so judging the whole accumulated set at every commit would fire forever
# after the first legitimate retirement.
#
# THE MUTATION CONTROLS (arms B, C, D) — this gate spent months green while inert, so it now proves on
# every run that its walker can still go red. Each arm builds a throwaway git repository under a temp
# directory (NOT this one: no object, ref, index or working-tree state of the repo under test is
# touched) with a known-bad history and requires arm A's own walker to name the violation:
#   (B) single-parent silent drop  → must be RED   (the failure the old gate missed entirely)
#   (C) two-parent merge drop      → must be RED   (the failure the old gate did catch — preserved)
#   (D) the same drop WITH a tombstone → must be GREEN, and a tombstone matching no vanish → RED
#
# WHY docs/EVALS.md's gate-count pins do NOT get this same treatment (deliberately, not an oversight):
# manifestcheck.sh already ties every "N gate scripts" / "loop ... names N" claim in EVALS.md to the
# LOOP's ACTUAL length, derived by regex from test/regression.sh, never hand-copied. A silently-dropped
# loop entry changes the loop's length, which those arms catch the moment EVALS.md is regenerated from
# the (now-shorter) loop — EVALS.md's count is a pure function of the loop this gate already guards.
#
# EXEMPT FROM binoverridecheck.sh: this gate reads git history (`git show REF:test/regression.sh`) and
# never invokes the ripwire binary under test — see binoverridecheck.sh's EXEMPT table.
#
# USAGE: test/loopconservationcheck.sh [REF] [BASE]   (defaults: REF=HEAD, BASE derived as above). Both
# positional arguments exist for exactly one reason — pointing this gate at a specific historical or
# synthetic commit while testing the gate itself — and are never passed by regression.sh's absorb loop,
# which invokes every gate with no positional argument at all.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
REF="${1:-HEAD}"
BASE_ARG="${2:-}"
fail=0

cd "$ROOT"
git rev-parse --verify --quiet "${REF}^{commit}" >/dev/null || { printf '  FAIL  ref '\''%s'\'' does not resolve to a commit\n' "$REF"; echo "FAILURES ABOVE"; exit 1; }

python3 - "$ROOT" "$REF" "$BASE_ARG" <<'PY' || fail=1
import os, re, shutil, subprocess, sys, tempfile

ROOT, REF, BASE_ARG = sys.argv[1], sys.argv[2], sys.argv[3]
bad = 0
def ok( m ): print( "  PASS  %s" % m )
def note( m ): print( "  NOTE  %s" % m )
def no( m ):
    global bad; bad = 1; print( "  FAIL  %s" % m )

# A window this long means the branch is enormously far from its upstream; walking it all would make a
# gate that runs 462 times per suite unusable. Disclosed, never silent (non-negotiable #3).
WINDOW_CAP = 300

ENV = dict( os.environ )
ENV.update( {
    "GIT_AUTHOR_NAME": "gate", "GIT_AUTHOR_EMAIL": "gate@example.invalid",
    "GIT_COMMITTER_NAME": "gate", "GIT_COMMITTER_EMAIL": "gate@example.invalid",
    "GIT_AUTHOR_DATE": "2000-01-01T00:00:00 +0000", "GIT_COMMITTER_DATE": "2000-01-01T00:00:00 +0000",
} )

def git( repo, args, check = True ):
    p = subprocess.run( [ "git", "-C", repo ] + args, capture_output = True, text = True, env = ENV )
    if check and p.returncode != 0:
        return None
    return p.stdout

def blob( repo, ref, path ):
    return git( repo, [ "show", "%s:%s" % ( ref, path ) ] )

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

def parents_of( repo, sha ):
    out = git( repo, [ "rev-list", "--parents", "-n1", sha ] )
    return out.split()[ 1: ] if out else []

# ── the walker: every commit in base..ref that touched the loop file, against each of ITS parents ─────
# Returns ( violations, staleTombstones, commitCount, pairCount, skipped ). Pure — it reports, the arms
# below decide whether a report is expected. Arms B/C/D call this on synthetic repositories.
def walk( repo, base, ref, path = "test/regression.sh" ):
    cache = {}
    def loopAt( sha ):
        if sha not in cache:
            cache[ sha ] = blob( repo, sha, path )
        return cache[ sha ]

    revs = git( repo, [ "rev-list", "--reverse", "--full-history", "%s..%s" % ( base, ref ), "--", path ] )
    revs = revs.split() if revs else []
    truncated = 0
    if len( revs ) > WINDOW_CAP:
        truncated = len( revs ) - WINDOW_CAP
        revs = revs[ -WINDOW_CAP: ]

    violations, stale, skipped, pairs = [], [], [], 0
    for child in revs:
        childText = loopAt( child )
        childLoop = loop_names( childText )
        if childLoop is None:
            skipped.append( "%s (child has no `for _g in ...; do` loop)" % child[ :12 ] )
            continue
        childTombs = tombstones( childText )
        for par in parents_of( repo, child ):
            parText = loopAt( par )
            parLoop = loop_names( parText )
            if parLoop is None:
                skipped.append( "%s^%s (parent pre-dates the loop file)" % ( child[ :12 ], par[ :8 ] ) )
                continue
            pairs += 1
            newTombs = childTombs - tombstones( parText )
            vanished = parLoop - childLoop
            silent = sorted( vanished - newTombs )
            if silent:
                violations.append( "%s (parent %s): %d entr%s vanished from the loop with no `# retired:` tombstone: %s" % (
                    child[ :12 ], par[ :12 ], len( silent ), "y" if len( silent ) == 1 else "ies", ", ".join( silent ) ) )
            unneeded = sorted( newTombs - vanished )
            if unneeded:
                stale.append( "%s (parent %s): tombstone(s) matching no vanish in that commit: %s" % (
                    child[ :12 ], par[ :12 ], ", ".join( unneeded ) ) )
    return violations, stale, len( revs ), pairs, skipped, truncated

# ── BASE derivation ───────────────────────────────────────────────────────────────────────────────────
def derive_base( repo, ref ):
    refSha = git( repo, [ "rev-parse", "--verify", "%s^{commit}" % ref ] ).strip()
    firstParent = parents_of( repo, refSha )
    firstParent = firstParent[ 0 ] if firstParent else None
    for upstream in ( "%s@{upstream}" % ref, "@{upstream}", "origin/main", "origin/HEAD" ):
        if git( repo, [ "rev-parse", "--verify", "--quiet", "%s^{commit}" % upstream ] ) is None:
            continue
        mb = git( repo, [ "merge-base", refSha, upstream ] )
        if not mb:
            continue
        mb = mb.strip()
        if mb != refSha:
            return mb, "merge-base with %s" % upstream
        # REF is already contained in its upstream: the window would be empty and this gate inert.
        break
    if firstParent:
        return firstParent, "REF's first parent (no upstream ahead of REF — window would otherwise be empty)"
    return None, "REF is a root commit"

base, why = ( BASE_ARG, "explicit BASE argument" ) if BASE_ARG else derive_base( ROOT, REF )

# ── (A) the real history walk ─────────────────────────────────────────────────────────────────────────
if base is None:
    ok( "(A) %s is a root commit with no parents — nothing to conserve against" % REF )
else:
    violations, stale, nCommits, nPairs, skipped, truncated = walk( ROOT, base, REF )
    if truncated:
        note( "(A) window longer than %d commits — the %d OLDEST were not examined (disclosed truncation, not a pass)" % ( WINDOW_CAP, truncated ) )
    for s in skipped:
        note( "(A) skipped %s" % s )
    if violations:
        for v in violations:
            no( "(A) %s" % v )
    else:
        ok( "(A) no undeclared vanish across %s..%s (%s): %d commit(s) touched the loop, %d child/parent pair(s) compared" % (
            base[ :12 ], REF, why, nCommits, nPairs ) )
    if stale:
        for s in stale:
            no( "(A) %s" % s )
    elif nPairs:
        ok( "(A) no tombstone was added without a matching vanish" )

# ── synthetic-history fixtures for the mutation controls ──────────────────────────────────────────────
def mkrepo():
    d = tempfile.mkdtemp( prefix = "loopcons_" )
    git( d, [ "init", "-q" ] )
    git( d, [ "config", "user.name", "gate" ] )
    git( d, [ "config", "user.email", "gate@example.invalid" ] )
    os.makedirs( os.path.join( d, "test" ), exist_ok = True )
    return d

def commitLoop( repo, names, parents, tombs = () ):
    body = "#!/usr/bin/env bash\n"
    for t in tombs:
        body += "# retired: %s - synthetic fixture\n" % t
    body += "for _g in " + " ".join( names ) + "; do\n  :\ndone\n"
    with open( os.path.join( repo, "test", "regression.sh" ), "w" ) as fh:
        fh.write( body )
    git( repo, [ "add", "test/regression.sh" ] )
    tree = git( repo, [ "write-tree" ] ).strip()
    args = [ "commit-tree", tree, "-m", "fixture" ]
    for par in parents:
        args += [ "-p", par ]
    return git( repo, args ).strip()

BASE_NAMES = [ "acheck", "bcheck", "ccheck" ]

def arm( label, build, expectViolation ):
    """build(repo) -> (base, ref); expectViolation is a name that must be reported, or None for green."""
    repo = mkrepo()
    try:
        b, r = build( repo )
        violations, stale, _n, pairs, _sk, _tr = walk( repo, b, r )
        blob_ = " | ".join( violations + stale ) or "(no finding)"
        if pairs == 0:
            no( "%s the walker compared 0 child/parent pairs on the fixture — it cannot have judged anything" % label )
        elif expectViolation is None:
            if violations or stale:
                no( "%s a legitimate, tombstoned retirement was reported as a violation: %s" % ( label, blob_ ) )
            else:
                ok( "%s a retirement declared with a `# retired:` tombstone is accepted (%d pair(s) compared)" % ( label, pairs ) )
        elif any( expectViolation in v for v in violations + stale ):
            ok( "%s the walker names it: %s" % ( label, blob_ ) )
        else:
            no( "%s the walker did NOT report the planted defect (%s) — arm (A)'s PASS means nothing: %s" % (
                label, expectViolation, blob_ ) )
    finally:
        shutil.rmtree( repo, ignore_errors = True )

# ── (B) single-parent silent drop — the failure mode the OLD gate reported as ALL PASS ────────────────
def buildLinear( repo ):
    a = commitLoop( repo, BASE_NAMES + [ "victimcheck" ], [] )
    c = commitLoop( repo, BASE_NAMES, [ a ] )                       # victimcheck dropped, no tombstone
    return a, c
arm( "(B) mutation control, LINEAR silent drop —", buildLinear, "victimcheck" )

# ── (C) single-parent drop WITH the tombstone the convention requires — must stay green ───────────────
def buildLinearTombstoned( repo ):
    a = commitLoop( repo, BASE_NAMES + [ "victimcheck" ], [] )
    c = commitLoop( repo, BASE_NAMES, [ a ], tombs = [ "victimcheck" ] )
    return a, c
arm( "(C) tombstone control —", buildLinearTombstoned, None )

# ── (D) a tombstone that matches no vanish — the stale-tombstone failure mode ─────────────────────────
def buildStaleTombstone( repo ):
    a = commitLoop( repo, BASE_NAMES, [] )
    c = commitLoop( repo, BASE_NAMES, [ a ], tombs = [ "neverherecheck" ] )
    return a, c
arm( "(D) mutation control, STALE tombstone —", buildStaleTombstone, "neverherecheck" )

# ── (E) two-parent merge drop — the case the old gate DID catch; proven still live ────────────────────
def buildMerge( repo ):
    a = commitLoop( repo, BASE_NAMES, [] )
    b = commitLoop( repo, BASE_NAMES + [ "leftcheck" ], [ a ] )
    c = commitLoop( repo, BASE_NAMES + [ "rightcheck" ], [ a ] )
    m = commitLoop( repo, BASE_NAMES + [ "leftcheck" ], [ b, c ] )  # rightcheck lost in the resolution
    return a, m
arm( "(E) mutation control, MERGE drop —", buildMerge, "rightcheck" )

sys.exit( bad )
PY

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"

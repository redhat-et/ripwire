#!/usr/bin/env bash
# shardapartcheck.sh — two gates that slow each other down never land in the same CI shard.
#
# WHY (lane GATE-SPLIT, 2026-11-26). binoverridecheck.sh (a meta-gate: ~870 gates re-run against a stub, 6 worker
# threads of its own) and mcpframehonestycheck.sh (arm K: ~200 back-to-back MCP edit ingests) both sat at their
# 1200 s budget on CI's macos-26 Release shard 2/4: 1,137.4 s and 1,106.2 s on #754's run, 1,207.8 s and 1,201.3 s
# (killed) on #756's. On the macos-26 plain leg, whose skip list drops binoverridecheck, mcpframehonestycheck ran in
# under 262 s. Locally they take 314 s and 75 s. Both landed in shard 2/4 on every leg because the LPT slicer put
# them there: binoverridecheck is the 2nd-heaviest row of .github/pargates-shard-weights.json, and mcpframe the 7th
# arrived when shard 2 was the lightest. So test/pargates.py now carries SHARD_APART, a declared anti-affinity:
# a gate in a group is never handed a shard that already holds another member of its group (when N allows it).
#
# WHAT THIS GATE PROVES, against the REAL slicer (test/pargates.py --shard-plan, which runs nothing):
#   (A) the workflow's shard counts and skip lists are read out of .github/workflows/*.yml, not restated here, and
#       there is at least one sharded pargates invocation to read them from (an empty read is a FAIL, not a pass);
#   (B) for every N the workflow uses, plus N = 2..8, with no skip list and with each skip list the workflow
#       passes: the plan is a PARTITION of the leg's gate list (every gate in exactly one shard), and every pair
#       below that runs on the leg sits in two different shards;
#   (C) a synthetic root whose weights force the pair together under plain LPT (2 shards: x 200, binover 100,
#       mcpframe 50): the tree's own slicer separates them, and a copy with SHARD_APART emptied puts them in one
#       shard -- the control that shows (B)'s check can see a shared shard at all;
#   (D) .github/binoverride-weights.json, the duration hints binoverridecheck.sh dispatches longest-first by,
#       parses as a non-empty {gate: seconds} table, and binoverridecheck.sh reads it (static tell).
# Pure file/harness check: it never runs the binary under test (binoverridecheck.sh EXEMPTs it for that reason).
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
fail=0
command -v python3 >/dev/null 2>&1 || { printf '  FAIL  python3 is required by shardapartcheck\n'; echo "FAILURES ABOVE"; exit 1; }

python3 - "$ROOT" <<'PY' || fail=1
import glob, json, os, re, shutil, subprocess, sys, tempfile

ROOT = sys.argv[1]
PG = os.path.join( ROOT, "test", "pargates.py" )
PAIRS = [ ( "binoverridecheck.sh", "mcpframehonestycheck.sh" ) ]
bad = 0
def ok( m ): print( "  PASS  %s" % m )
def no( m ):
    global bad; bad = 1; print( "  FAIL  %s" % m )

def plan( root, n, excl=None, pg=PG ):
    """Run the slicer in plan mode; return ( [ set-of-gates per shard ], raw output ) or ( None, why )."""
    cmd = [ sys.executable, pg, root, os.path.join( root, "no-binary-needed" ), "--shard", "1/%d" % n, "--shard-plan" ]
    if excl:
        cmd += [ "--exclude-list", excl ]
    p = subprocess.run( cmd, capture_output=True, text=True, errors="replace", timeout=120 )
    if p.returncode != 0:
        return None, "rc=%d: %s" % ( p.returncode, ( p.stdout + p.stderr ).strip()[-300:] )
    heads = re.findall( r"^shard (\d+)/(\d+): (\d+) gates", p.stdout, re.M )
    members = re.findall( r"^  gates:(.*)$", p.stdout, re.M )
    if len( heads ) != n or len( members ) != n:
        return None, "expected %d shard lines each followed by a '  gates:' membership line, got %d and %d" % ( n, len( heads ), len( members ) )
    shards = [ m.split() for m in members ]
    for ( k, nn, cnt ), s in zip( heads, shards ):
        if int( cnt ) != len( s ):
            return None, "shard %s/%s header says %s gates, its membership line lists %d" % ( k, nn, cnt, len( s ) )
    return shards, p.stdout

def leg_gates( excl ):
    gates = sorted( os.path.basename( f ) for f in glob.glob( os.path.join( ROOT, "test", "*.sh" ) ) )
    gates = [ g for g in gates if not g.startswith( "." ) and g != "regression.sh" ]
    if excl:
        with open( os.path.join( ROOT, excl ) ) as fh:
            drop = { ln.split( "#", 1 )[0].strip() for ln in fh } - { "" }
        gates = [ g for g in gates if g not in drop ]
    return gates

# ── (A) what the workflow actually runs ───────────────────────────────────────────────────────────────
Ns, lists, invocations = set(), set(), 0
for wf in sorted( glob.glob( os.path.join( ROOT, ".github", "workflows", "*.yml" ) ) ):
    with open( wf, errors="replace" ) as fh:
        text = fh.read()
    runs = [ ln for ln in text.splitlines() if "test/pargates.py" in ln and "--shard" in ln and not ln.lstrip().startswith( "#" ) ]
    if not runs:
        continue
    invocations += len( runs )
    for ln in runs:
        Ns.update( int( x ) for x in re.findall( r"--shard\s+\S+?/(\d+)\b", ln ) )   # a literal --shard K/N
        lists.update( re.findall( r"--exclude-list\s+(\.github/\S+?\.txt)\b", ln ) )
    if any( "matrix.shards" in ln for ln in runs ):                                     # N from the matrix
        Ns.update( int( x ) for x in re.findall( r"\bshards\"?\s*:\s*(\d+)", text ) )
    lists.update( re.findall( r"\"skiplist\"\s*:\s*\"([^\"]+)\"", text ) )
if invocations == 0 or not Ns:
    no( "(A) found %d sharded pargates invocation(s) and shard count(s) %s in .github/workflows/*.yml -- nothing to check, which is not a pass" % ( invocations, sorted( Ns ) ) )
else:
    missing = sorted( l for l in lists if not os.path.isfile( os.path.join( ROOT, l ) ) )
    if missing:
        no( "(A) the workflow names skip list(s) that do not exist: %s" % ", ".join( missing ) )
    else:
        ok( "(A) %d sharded pargates invocation(s); the workflow shards %s way(s), skip lists: %s" % (
            invocations, "/".join( str( n ) for n in sorted( Ns ) ), ", ".join( sorted( lists ) ) or "none" ) )

# ── (B) the real slicer, every N the workflow uses plus 2..8, every leg's list ───────────────────────────
checked, apartSeen, bFails = 0, 0, 0
for n in sorted( Ns | set( range( 2, 9 ) ) ):
    for excl in [ None ] + sorted( lists ):
        label = "N=%d%s" % ( n, ( " " + os.path.basename( excl ) ) if excl else "" )
        shards, raw = plan( ROOT, n, excl )
        if shards is None:
            no( "(B) %s: the plan could not be read -- %s" % ( label, raw ) ); bFails += 1; continue
        want = leg_gates( excl )
        flat = [ g for s in shards for g in s ]
        if sorted( flat ) != want:
            dup = sorted( { g for g in flat if flat.count( g ) > 1 } )
            no( "(B) %s: the plan is not a partition of the leg's %d gates (listed %d, duplicated %s, missing %s)" % (
                label, len( want ), len( flat ), dup[:5], sorted( set( want ) - set( flat ) )[:5] ) ); bFails += 1; continue
        where = { g: i + 1 for i, s in enumerate( shards ) for g in s }
        checked += 1
        for a, b in PAIRS:
            if a not in where or b not in where:
                continue                         # the leg's skip list drops one of them: they cannot overlap there
            apartSeen += 1
            if where[a] == where[b]:
                no( "(B) %s: %s and %s are both in shard %d/%d" % ( label, a, b, where[a], n ) ); bFails += 1
if checked and apartSeen and not bFails:
    ok( "(B) %d plan(s) read, each a partition of its leg's gate list; the pair sits in two different shards in all %d where both run" % ( checked, apartSeen ) )
elif checked and not apartSeen:
    no( "(B) no plan held both gates of any pair -- the separation was never actually tested" )

# ── (C) sensitivity: weights that force the pair together under plain LPT ────────────────────────────────
tmp = tempfile.mkdtemp( prefix="shardapartcheck." )
try:
    os.makedirs( os.path.join( tmp, "test" ) ); os.makedirs( os.path.join( tmp, ".github" ) )
    W = { "xcheck.sh": 200, "binoverridecheck.sh": 100, "mcpframehonestycheck.sh": 50 }
    for g in W:
        open( os.path.join( tmp, "test", g ), "w" ).close()
    with open( os.path.join( tmp, ".github", "pargates-shard-weights.json" ), "w" ) as fh:
        json.dump( W, fh )
    with open( PG ) as fh:
        src = fh.read()
    shutil.copy( PG, os.path.join( tmp, "test", "pargates.py" ) )
    mut = re.sub( r"^SHARD_APART\s*=.*$", "SHARD_APART = ()", src, count=1, flags=re.M )
    mutPath = os.path.join( tmp, "pargates_noapart.py" )
    with open( mutPath, "w" ) as fh:
        fh.write( mut )
    real, rawR = plan( tmp, 2 )
    if real is None:
        no( "(C) synthetic root, the tree's slicer: plan unreadable -- %s" % rawR )
    elif any( "binoverridecheck.sh" in s and "mcpframehonestycheck.sh" in s for s in real ):
        no( "(C) synthetic root (x 200, binover 100, mcpframe 50; 2 shards): the tree's slicer put the pair in one shard: %s" % real )
    else:
        ok( "(C) synthetic root forcing the pair together under plain LPT: the tree's slicer separates them %s" % real )
    if mut == src:
        no( "(C) mutation control did not take: test/pargates.py has no 'SHARD_APART = ...' line to empty" )
    else:
        ctl, rawC = plan( tmp, 2, pg=mutPath )
        if ctl is None:
            no( "(C) mutation control (SHARD_APART emptied): plan unreadable -- %s" % rawC )
        elif any( "binoverridecheck.sh" in s and "mcpframehonestycheck.sh" in s for s in ctl ):
            ok( "(C) mutation control: with SHARD_APART emptied the same root puts the pair in one shard %s -- the check sees it" % ctl )
        else:
            no( "(C) mutation control: with SHARD_APART emptied the pair still landed apart %s -- the synthetic weights no longer force a collision" % ctl )
finally:
    shutil.rmtree( tmp, ignore_errors=True )

# ── (D) binoverridecheck's dispatch hints ─────────────────────────────────────────────────────────────
HINTS = os.path.join( ROOT, ".github", "binoverride-weights.json" )
try:
    with open( HINTS ) as fh:
        h = json.load( fh )
    good = isinstance( h, dict ) and h and all( isinstance( k, str ) and isinstance( v, ( int, float ) ) and v >= 0 for k, v in h.items() )
except ( OSError, ValueError ) as e:
    h, good = None, False
    no( "(D) .github/binoverride-weights.json is missing or not JSON: %s" % e )
if h is not None:
    if not good:
        no( "(D) .github/binoverride-weights.json is not a non-empty {gate: seconds >= 0} table" )
    else:
        live = set( leg_gates( None ) )
        ok( "(D) .github/binoverride-weights.json: %d rows, %d name a gate on disk (a gate with no row is dispatched first, as unknown)" % (
            len( h ), len( live & set( h ) ) ) )
with open( os.path.join( ROOT, "test", "binoverridecheck.sh" ), errors="replace" ) as fh:
    if "binoverride-weights.json" in fh.read():
        ok( "(D) binoverridecheck.sh reads the hint table (static tell: it names the file)" )
    else:
        no( "(D) binoverridecheck.sh never names .github/binoverride-weights.json -- its dispatch is not longest-first" )

sys.exit( bad )
PY

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"

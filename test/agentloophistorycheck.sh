#!/usr/bin/env bash
# agentloophistorycheck.sh — the agent-loop runner must not hand the agent a checkout that can reach the
# future: no commit, tag, branch, reflog entry, remote or shared object store that leads past the task's
# base_commit (bench/agentloop/run_agentloop.py).
#
# WHY THIS GATE EXISTS. Coding agents exploit local git history: "Shortcutting the Fix" (arXiv 2609.06780)
# saw shortcut attempts in 60.7-90.1% of trajectories, git-history exploits among them, and disabling the
# network did not curb them. ripwire READS git history (--cochange, --rank-by=churn, --situ, --hotspots), so
# a checkout that still holds the fix commit lets the tool surface the fix itself, and the leak is credited
# to the tool. bench/locbench/run_locbench.py already builds ancestor-only clones; the agent loop did not
# check the same property. This gate drives the runner's OWN checkout functions against a fixture and
# judges the result with an independent checker, so the runner's guard is not grading itself.
#
# FIXTURE: a bare "remote" with P -> A -> B. A is base_commit. B is the future: branch main, branch fix and
# tag v1 (annotated) and v1-light point at it. A git `url.<x>.insteadOf` rule (in a gate-private global
# config) redirects https://github.com/fx/leak.git, which is the URL checkout_repo() builds, to that remote,
# so the runner's code runs unmodified.
#
# ARMS — each judged by leak_report(): B's object is absent, no ref/reflog/FETCH_HEAD/ORIG_HEAD names B, no
# tag exists, no remote is configured, the object store is the checkout's own (no worktree, no alternates),
# HEAD is A and the file content is A's.
#   (1) FRESH    checkout_repo() once, at A.
#   (2) REUSE    checkout_repo() at B (a later instance of the same repo), then at A in the same repos dir.
#                The lock holds 4 instances per repo, so this is the ordinary case, not a corner.
#   (3) FALLBACK the remote refuses a want-by-sha (protocol v0, the default upload-pack config), so the
#                runner takes its unshallow-fetch fallback.
#   (4) PIN      checkout_local_pin() (QUESTIONS mode) from a local corpus whose repo holds B, tags and
#                branches. Here ancestors are legitimate history and must SURVIVE: P must be reachable.
#   (5) GUARD    the runner's own history_leak_findings() must flag a plain clone checked out at A (the
#                negative control, so the guard is not vacuous), and must pass arm (1)'s checkout.
#   (6) WIRED    run_one() calls checkout_leak_error() (which runs history_leak_findings()) before the
#                harness, and it refuses the leaky control and passes the clean checkout.
#
# Usage: bash test/agentloophistorycheck.sh [ripwire-binary]   (named and version-checked, then unused:
# the subject is a python runner and git.)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
# The gate binary seam (lane rules 11-26): the binary is named and its version printed on the first line, so a
# run cannot silently test some other build. The subject here is python, but a binary that does not run
# fails the gate rather than being ignored.
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
echo "BIN=$BIN $( "$BIN" --version 2>&1 | head -n 1 )"
"$BIN" --version >/dev/null 2>&1 || { echo "agentloophistorycheck: BIN=$BIN does not run"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "agentloophistorycheck: python3 required"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "agentloophistorycheck: git required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

PYTHONDONTWRITEBYTECODE=1 python3 -I - "$ROOT" "$TMP" <<'EOF'
import inspect, os, pathlib, subprocess, sys
root, tmp = sys.argv[1], pathlib.Path( sys.argv[2] )
sys.path.insert( 0, root + "/bench/agentloop" )

# A gate-private git config: nothing from the operator's ~/.gitconfig or /etc/gitconfig.
gcfg = tmp / "gitconfig"
os.environ.update( GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=str( gcfg ), GIT_TERMINAL_PROMPT="0",
                   GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t" )
def git( *args, cwd=None, check=True ):
    r = subprocess.run( [ "git", *args ], cwd=cwd, capture_output=True, text=True )
    if check and r.returncode != 0:
        raise SystemExit( f"agentloophistorycheck: fixture git {args} failed: {r.stderr.strip()}" )
    return r.stdout.strip()

# ── fixture: P -> A (base) -> B (future), B reachable from two branches and two tags ────────────────────
src = tmp / "corpus" / "leak"
src.mkdir( parents=True )
git( "init", "-q", "-b", "main", cwd=src )
( src / "f.txt" ).write_text( "p\n" ); git( "add", "f.txt", cwd=src ); git( "commit", "-qm", "P", cwd=src )
P = git( "rev-parse", "HEAD", cwd=src )
( src / "f.txt" ).write_text( "a\n" ); git( "commit", "-qam", "A", cwd=src )
A = git( "rev-parse", "HEAD", cwd=src )
( src / "f.txt" ).write_text( "b-the-fix\n" ); git( "commit", "-qam", "B", cwd=src )
B = git( "rev-parse", "HEAD", cwd=src )
git( "tag", "-a", "v1", "-m", "release with the fix", cwd=src ); git( "tag", "v1-light", cwd=src )
git( "branch", "fix", cwd=src )
remote = tmp / "remotes" / "fx" / "leak.git"
remote.parent.mkdir( parents=True )
git( "clone", "-q", "--bare", str( src ), str( remote ) )
gcfg.write_text( f'[url "file://{tmp}/remotes/"]\n\tinsteadOf = https://github.com/\n' )

import run_agentloop

fails = 0
def verdict( name, problems ):
    global fails
    if problems:
        fails += 1
        print( f"  FAIL  {name}" )
        for p in problems: print( f"          - {p}" )
    else:
        print( f"  PASS  {name}" )

def leak_report( d, *, want_ancestor=None ):
    """Independent of the runner: every way the checkout at d could reach B."""
    if d is None:
        return [ "checkout returned None" ]
    d = pathlib.Path( d )
    out = []
    def g( *a ):
        return subprocess.run( [ "git", "-C", str( d ), *a ], capture_output=True, text=True )
    if g( "cat-file", "-e", f"{B}^{{commit}}" ).returncode == 0:
        out.append( "the future commit's object is in the checkout's object store" )
    refs = g( "for-each-ref", "--format=%(objectname) %(*objectname) %(refname)" ).stdout.splitlines()
    for line in refs:
        if B in line: out.append( f"a ref reaches the future commit: {line.split()[-1]}" )
        if " refs/tags/" in f" {line.split()[-1]}": out.append( f"a tag exists: {line.split()[-1]}" )
    if B in g( "reflog", "show", "--all", "--format=%H" ).stdout:
        out.append( "the reflog names the future commit" )
    gitdir = pathlib.Path( g( "rev-parse", "--absolute-git-dir" ).stdout.strip() or d / ".git" )
    for pseudo in ( "FETCH_HEAD", "ORIG_HEAD" ):
        p = gitdir / pseudo
        if p.exists() and B in p.read_text( errors="replace" ):
            out.append( f"{pseudo} names the future commit" )
    remotes = g( "remote" ).stdout.split()
    if remotes: out.append( f"a remote is configured ({', '.join( remotes )}): `git fetch` reaches the future" )
    common = pathlib.Path( g( "rev-parse", "--path-format=absolute", "--git-common-dir" ).stdout.strip() or gitdir )
    if common.resolve() != gitdir.resolve() or not str( gitdir.resolve() ).startswith( str( d.resolve() ) ):
        out.append( f"the object store is shared with another repository ({common})" )
    if ( gitdir / "objects" / "info" / "alternates" ).exists():
        out.append( "objects/info/alternates borrows another repository's objects" )
    if g( "rev-parse", "HEAD" ).stdout.strip() != A:
        out.append( f"HEAD is not base_commit A (got {g( 'rev-parse', 'HEAD' ).stdout.strip()!r})" )
    f = d / "f.txt"
    if not f.exists() or f.read_text() != "a\n":
        out.append( "the working tree does not hold base_commit's content" )
    if want_ancestor and g( "cat-file", "-e", f"{want_ancestor}^{{commit}}" ).returncode != 0:
        out.append( "a pre-base ancestor was lost: legitimate history must survive" )
    return out

# (1) FRESH
d1 = run_agentloop.checkout_repo( "fx/leak", A, tmp / "w1" / "repos" )
verdict( "(1) FRESH: a first checkout at base_commit cannot reach the future", leak_report( d1 ) )

# (2) REUSE: a later instance of the same repo first, then the base instance
run_agentloop.checkout_repo( "fx/leak", B, tmp / "w2" / "repos" )
d2 = run_agentloop.checkout_repo( "fx/leak", A, tmp / "w2" / "repos" )
verdict( "(2) REUSE: a repo dir reused from a later instance cannot reach the future", leak_report( d2 ) )

# (3) FALLBACK: protocol v0 refuses an unadvertised want-by-sha, forcing the unshallow fallback
os.environ.update( GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="protocol.version", GIT_CONFIG_VALUE_0="0" )
probe = tmp / "probe"; probe.mkdir()
git( "init", "-q", cwd=probe )
refused = subprocess.run( [ "git", "fetch", "-q", "--depth", "1", f"file://{remote}", A ], cwd=probe,
                          capture_output=True, text=True ).returncode != 0
if not refused:
    print( "  FAIL  (3) FALLBACK: liveness — this git accepted the unadvertised want, so the fallback path is not exercised" )
    fails += 1
else:
    d3 = run_agentloop.checkout_repo( "fx/leak", A, tmp / "w3" / "repos" )
    verdict( "(3) FALLBACK: the unshallow-fetch fallback cannot reach the future", leak_report( d3 ) )
for k in ( "GIT_CONFIG_COUNT", "GIT_CONFIG_KEY_0", "GIT_CONFIG_VALUE_0" ): os.environ.pop( k )

# (4) PIN: QUESTIONS mode materializes from a local corpus; ancestors stay, the future goes
task = dict( instance_id="Q1", repo="leak", pin_ref=A[:12] )
dest = run_agentloop.checkout_local_pin( task, tmp / "w4" / "repos", tmp / "corpus" )
verdict( "(4) PIN: a QUESTIONS-mode pinned tree cannot reach the future and keeps its ancestors",
         leak_report( None if dest is None else pathlib.Path( dest ) / "leak", want_ancestor=P ) )

# (5) GUARD: the runner's own check is not vacuous
guard = getattr( run_agentloop, "history_leak_findings", None )
if guard is None:
    verdict( "(5) GUARD: run_agentloop.history_leak_findings exists", [ "no such function" ] )
else:
    leaky = tmp / "leaky"
    git( "clone", "-q", str( remote ), str( leaky ) ); git( "checkout", "-q", A, cwd=leaky )
    probs = []
    if not guard( leaky, A ): probs.append( "a plain clone checked out at A (tags, origin/main, B present) was passed as clean" )
    if d1 is not None and guard( d1, A ): probs.append( f"the arm-(1) checkout was flagged: {guard( d1, A )}" )
    verdict( "(5) GUARD: history_leak_findings flags the leaky control and passes a clean checkout", probs )

# (6) WIRED
# run_one() reaches the guard through checkout_leak_error() (one tree per pin in QUESTIONS mode); both
# links are checked, and the refusal is driven for real on the arm-(2)-shaped leaky control.
src_run_one = inspect.getsource( run_agentloop.run_one )
at_guard, at_harness = src_run_one.find( "checkout_leak_error(" ), src_run_one.find( "proc = sh( cmd" )
probs = []
if not ( 0 <= at_guard < at_harness ):
    probs.append( "run_one() never calls checkout_leak_error() ahead of the harness" )
cle = getattr( run_agentloop, "checkout_leak_error", None )
if cle is None or "history_leak_findings(" not in inspect.getsource( cle ):
    probs.append( "checkout_leak_error() is missing or does not call history_leak_findings()" )
elif guard is not None:
    if not cle( dict( base_commit=A ), tmp / "leaky", False ): probs.append( "checkout_leak_error() passed the leaky control" )
    if d1 is not None and cle( dict( base_commit=A ), d1, False ): probs.append( "checkout_leak_error() refused a clean checkout" )
verdict( "(6) WIRED: run_one() refuses a leaky checkout before the harness starts", probs )

print( f"agentloophistorycheck: {'FAIL' if fails else 'PASS'} ({fails} of 6 arms red)" )
sys.exit( 1 if fails else 0 )
EOF

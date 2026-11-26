#!/usr/bin/env bash
# norepogitcheck.sh — an MCP edit on a root git cannot see spawns no git child, and the answer is never stale.
#
# WHY THIS FILE EXISTS. MEASURE-M5 (2026-11-26) profiled mcpframehonestycheck arm K: each APPLIED MCP edit cost
# 265-314 ms, and about a third of that was git subprocesses against a temp directory that is no repository.
# A PATH shim counted them on main 5fa8f5ec0: the first edit on a non-git root started 8 git children, and every
# later edit on that same root 4 — `diff --numstat HEAD` and `diff --name-only HEAD HEAD` (gitDiffChangedMaskNumstat,
# once for the pre-edit index and once for the post-edit re-index), the diffFailed `rev-parse --verify HEAD` after each,
# one `config --get-regexp` (gitIsPartialClone, first sighting of the root), and computeHeadSnapshot's
# gitRepoHasHistory. Every one of them answered "not a git repository".
#
# Git FINDS a repository by walking up from its working directory to the first `.git` entry or bare-repository-shaped
# directory (a `HEAD`), or takes GIT_DIR from the environment. A root with none of those on its real path and no
# GIT_DIR is provably no repository, and that proof is a handful of stat calls (src/gitrootfacts.h) made on EVERY
# call — so it cannot go stale the way a remembered "not a repo" would when the user runs `git init` mid-session.
#
# ARMS
#   (P) PRECONDITION. The gate's own temp dir must sit on a real path with no `.git` and no `HEAD` in any ancestor,
#       and GIT_DIR must be unset (clean-env.sh), or (A) cannot conclude: git would discover the enclosing repo and
#       spawning would be CORRECT. Exit 2, never a vacuous pass.
#   (A) SPAWNS. One long-lived stdio server; three edits on one non-git root, then one edit on each of two fresh
#       non-git roots (arm K's shape). Every edit must APPLY and report edit_check status "no-baseline" (so the
#       contract-vs-HEAD check really ran), and every edit after the first must start at most ONE git child.
#       Red on main: 4 and 8.
#   (B) git init MID-SESSION is noticed on the NEXT call, in the same server, on a root already served as non-git:
#       after `git init` alone (a repo with no HEAD) the next edit must ask git (>= 1 child) and still say
#       "no-baseline"; after a commit the next edit must ask git and report a HEAD baseline (status not
#       "no-baseline"). A cached "not a repo" would fail both.
#   (C) THE FALL-THROUGH stays git's. Each of these must start git children and see the HEAD baseline:
#       C1 a committed repo root; C2 a SUBDIRECTORY of a committed repo (a check of `<root>/.git` alone would miss it);
#       C3 a worktree-style root whose `.git` is a FILE (`gitdir: …`). C4: GIT_DIR exported to the server and pointed
#       at a committed repo, the root a plain directory — git must still be asked (>= 1 child).
#
# Usage: bash test/norepogitcheck.sh [ripwire-binary]

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-$ROOT/build/ripwire}"
[ -x "$BIN" ] || { echo "norepogitcheck: no binary at $BIN"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "norepogitcheck: git missing (gate cannot run)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "norepogitcheck: python3 missing (gate cannot run)"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
REALGIT="$( command -v git )"

mkdir -p "$TMP/shim"
cat > "$TMP/shim/git" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$TMP/git.log"
exec "$REALGIT" "\$@"
EOF
chmod +x "$TMP/shim/git"

python3 - "$BIN" "$TMP" "$REALGIT" <<'PY'
import json, os, subprocess, sys

BIN, TMP, REALGIT = sys.argv[1], sys.argv[2], sys.argv[3]
LOG = os.path.join( TMP, "git.log" )
SRC = ( "// alpha adds one.\nint alpha( int x ) { return x + 1; }\n\n"
        "// beta doubles.\nint beta( int x ) { return x * 2; }\n" )

fails = 0
def check( cond, msg ):
    global fails
    print( ( "  PASS  " if cond else "  FAIL  " ) + msg )
    if not cond: fails += 1

# ─── (P) the precondition: nothing on the temp dir's real path that git could discover ─────────────────────
real = os.path.realpath( TMP )
d, found = real, []
while True:
    for name in ( ".git", "HEAD" ):
        if os.path.lexists( os.path.join( d, name ) ): found.append( os.path.join( d, name ) )
    parent = os.path.dirname( d )
    if parent == d: break
    d = parent
if found or "GIT_DIR" in os.environ:
    print( "norepogitcheck: the temp dir's real path holds %s (GIT_DIR %s) — git would discover a repository there, so "
           "(A) cannot conclude" % ( found or "nothing", "set" if "GIT_DIR" in os.environ else "unset" ) )
    sys.exit( 2 )
print( "  PASS  (P) %s: no .git / HEAD on its real path, GIT_DIR unset" % real )

GITENV = dict( os.environ, GIT_AUTHOR_NAME="gate", GIT_AUTHOR_EMAIL="gate@example.invalid",
               GIT_COMMITTER_NAME="gate", GIT_COMMITTER_EMAIL="gate@example.invalid" )
def git( *args, cwd ):
    subprocess.run( [ REALGIT, "-C", cwd ] + list( args ), check=True, env=GITENV,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL )

seq = [ 0 ]
def corpus( parent=None ):
    seq[ 0 ] += 1
    d = os.path.join( parent or TMP, "c%d" % seq[ 0 ] )
    os.makedirs( d )
    open( os.path.join( d, "a.h" ), "w" ).write( SRC )
    return d
def commitRepo( d ):
    git( "init", "-q", cwd=d ); git( "add", "-A", cwd=d ); git( "commit", "-qm", "seed", cwd=d )

class Server:
    def __init__( self, extraEnv=None ):
        env = dict( os.environ, PATH=os.path.join( TMP, "shim" ) + os.pathsep + os.environ.get( "PATH", "" ) )
        env.update( extraEnv or {} )
        self.p = subprocess.Popen( [ BIN, "--mcp" ], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL, env=env )
        self.n = 1
        self.send( "initialize", None )
    def send( self, method, params ):
        self.n += 1
        frame = { "jsonrpc": "2.0", "id": self.n, "method": method }
        if params is not None: frame[ "params" ] = params
        self.p.stdin.write( ( json.dumps( frame ) + "\n" ).encode() ); self.p.stdin.flush()
        return json.loads( self.p.stdout.readline().decode( "utf-8", "replace" ) )
    def edit( self, root, k ):
        """One applied replace_symbol_body: (git children it started, edit_check status or the error)."""
        before = spawns()
        r = self.send( "tools/call", { "name": "replace_symbol_body",
                                       "arguments": { "path": root, "symbol": "alpha", "file": "a.h",
                                                      "new_body": "int alpha( int x ) { return x + %d; }" % k } } )
        n = spawns() - before
        if "error" in r: return n, "ERROR " + json.dumps( r[ "error" ] )[ :200 ]
        try:
            payload = json.loads( r[ "result" ][ "content" ][ 0 ][ "text" ] )
            return n, payload.get( "edit_check", {} ).get( "status", "<no edit_check>" )
        except Exception as e:
            return n, "UNPARSED %s" % e
    def close( self ):
        try:
            self.p.stdin.close(); self.p.wait( 15 )
        except Exception:
            self.p.kill()

def spawns():
    try:
        with open( LOG ) as fh: return sum( 1 for _ in fh )
    except FileNotFoundError:
        return 0

# ═══ (A) spawns per edit on non-git roots ═══════════════════════════════════════════════════════════════════
srv = Server()
r1 = corpus()
rows = [ ( "root 1, edit 1", srv.edit( r1, 2 ) ), ( "root 1, edit 2", srv.edit( r1, 3 ) ), ( "root 1, edit 3", srv.edit( r1, 4 ) ),
         ( "fresh root 2",   srv.edit( corpus(), 5 ) ), ( "fresh root 3", srv.edit( corpus(), 6 ) ) ]
for i, ( label, ( n, status ) ) in enumerate( rows ):
    check( status == "no-baseline", "(A) %s applied and edit_check said no-baseline (got %s)" % ( label, status ) )
    if i == 0:
        print( "  INFO  (A) %s started %d git child(ren)" % ( label, n ) )
    else:
        check( n <= 1, "(A) %s started %d git child(ren) on a root git cannot see (at most 1)" % ( label, n ) )

# ═══ (B) git init mid-session, same server, same root ════════════════════════════════════════════════════════
r4 = corpus()
n0, s0 = srv.edit( r4, 7 )
check( s0 == "no-baseline", "(B) before git init: no-baseline (got %s, %d git children)" % ( s0, n0 ) )
git( "init", "-q", cwd=r4 )
n1, s1 = srv.edit( r4, 8 )
check( n1 >= 1 and s1 == "no-baseline",
       "(B) after `git init` (no HEAD yet): the next edit asked git (%d children) and said no-baseline (got %s)" % ( n1, s1 ) )
git( "add", "-A", cwd=r4 ); git( "commit", "-qm", "seed", cwd=r4 )
n2, s2 = srv.edit( r4, 9 )
check( n2 >= 1 and s2 not in ( "no-baseline", "" ) and not s2.startswith( ( "ERROR", "UNPARSED" ) ),
       "(B) after the first commit: the next edit asked git (%d children) and saw the HEAD baseline (status %s)" % ( n2, s2 ) )

# ═══ (C) the fall-through stays git's ═══════════════════════════════════════════════════════════════════════
c1 = corpus(); commitRepo( c1 )
n, s = srv.edit( c1, 10 )
check( n >= 1 and s != "no-baseline", "(C1) committed repo root: %d git children, status %s" % ( n, s ) )

outer = corpus(); sub = os.path.join( outer, "sub" ); os.makedirs( sub )
open( os.path.join( sub, "a.h" ), "w" ).write( SRC ); commitRepo( outer )
n, s = srv.edit( sub, 11 )
check( n >= 1 and s != "no-baseline", "(C2) a subdirectory of a committed repo: %d git children, status %s" % ( n, s ) )

main = corpus(); commitRepo( main )
wt = os.path.join( TMP, "wt" )
git( "worktree", "add", "-q", "--detach", wt, cwd=main )
n, s = srv.edit( wt, 12 )
check( os.path.isfile( os.path.join( wt, ".git" ) ) and n >= 1 and s != "no-baseline",
       "(C3) a worktree root whose .git is a file: %d git children, status %s" % ( n, s ) )
srv.close()

gd = corpus(); commitRepo( gd )
srv = Server( { "GIT_DIR": os.path.join( gd, ".git" ) } )
n, s = srv.edit( corpus(), 13 )
check( n >= 1, "(C4) GIT_DIR exported to the server, root a plain directory: git was asked (%d children, status %s)" % ( n, s ) )
srv.close()

print( "norepogitcheck: %s" % ( "ALL PASS" if fails == 0 else "%d FAIL" % fails ) )
sys.exit( 1 if fails else 0 )
PY

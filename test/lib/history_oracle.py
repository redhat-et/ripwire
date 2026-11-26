#!/usr/bin/env python3
"""history_oracle.py REPO [SINCE] [--include-bots] — per-path churn the way the history walks define it, from git's own log.

An oracle for the churn gates, re-derived independently of the C++ reader (src/gitmine.h, WHOSE HISTORY, AND WHAT A MOVE
IS): one `git log -c -M100% --name-status` walk, newest first, where
  - a commit whose author name or email local part ends in `[bot]`, or a listed automation account, contributes nothing
    (unless --include-bots);
  - an exact move (R100) contributes nothing, and every OLDER record of the old path counts for the file's current path;
  - every other listed path counts once for that commit.
Prints "COUNT PATH" lines, sorted by path. Paths are read from git's line output with core.quotepath=false, so this oracle
is for trees whose paths carry no control bytes or tabs (the live repo); a gate on a hostile-name fixture keeps its own.
The moves come from git's OWN exact-rename detection (-M100%), not from the blob pairing the C++ reader does, so the two
agree only where a commit's exact moves are unambiguous; that independence is the point of an oracle.
"""
import subprocess
import sys

BOT_EMAILS = { "action@github.com", "bot@renovateapp.com", "github-actions@github.com",
               "renovate@whitesourcesoftware.com", "support@dependabot.com" }
BOT_NAMES = { "dependabot", "dependabot-preview", "github-actions", "renovate", "renovate bot" }


def is_bot( name, email ):
    n, e = name.lower(), email.lower()
    local = e.split( "@", 1 )[ 0 ]
    return n.endswith( "[bot]" ) or local.endswith( "[bot]" ) or e in BOT_EMAILS or n in BOT_NAMES


def main():
    args = [ a for a in sys.argv[ 1: ] if a != "--include-bots" ]
    include_bots = "--include-bots" in sys.argv[ 1: ]
    repo = args[ 0 ]
    since = args[ 1 ] if len( args ) > 1 and args[ 1 ] else None
    cmd = [ "git", "-c", "core.quotepath=false", "-C", repo, "log", "--no-ext-diff", "--no-textconv", "-M100%", "-c",
            "--name-status", "--format=%x01%an%x02%ae" ]
    if since:
        cmd.append( "--since=" + since )
    out = subprocess.run( cmd, capture_output=True, check=True ).stdout.decode( "utf-8", "surrogateescape" )

    moved = {}        # an older spelling -> the file's current path
    counts = {}
    commit = None     # [ bot, paths ]

    def flush():
        if commit is not None and commit[ 1 ] and not ( commit[ 0 ] and not include_bots ):
            for p in commit[ 1 ]:
                counts[ p ] = counts.get( p, 0 ) + 1

    for line in out.split( "\n" ):
        if line.startswith( "\x01" ):
            flush()
            name, _, email = line[ 1: ].partition( "\x02" )
            commit = [ is_bot( name, email ), [] ]
            continue
        if not line or commit is None:
            continue
        fields = line.split( "\t" )
        status = fields[ 0 ]
        if len( fields ) == 3 and status[ :1 ] in ( "R", "C" ):
            old, new = fields[ 1 ], moved.get( fields[ 2 ], fields[ 2 ] )
            if status == "R100":
                moved[ old ] = new
            else:
                commit[ 1 ] += [ moved.get( old, old ), new ]
            continue
        commit[ 1 ].append( moved.get( fields[ -1 ], fields[ -1 ] ) )
    flush()
    for p in sorted( counts ):
        print( counts[ p ], p )


if __name__ == "__main__":
    main()

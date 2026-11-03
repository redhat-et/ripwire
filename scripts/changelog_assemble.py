#!/usr/bin/env python3
"""scripts/changelog_assemble.py — fold changelog.d/ fragments into CHANGELOG.md at release time.

WHY. Every merge to main used to make every open PR conflict on CHANGELOG.md's [Unreleased] section: each
PR added its entry to the same hunk, so the second PR to land always re-merged by hand. A change now adds
ONE NEW FILE under changelog.d/ instead, and no two PRs touch the same lines. CHANGELOG.md keeps the
released history and an [Unreleased] stub; this script turns the fragments into a dated section when a
release is cut.

A FRAGMENT is one change, byte for byte the entry it becomes:

    ### <Section> — <title>
    <blank line>
    <body: prose or bullets, at least one non-blank line>

<Section> is one of SECTIONS below. Fragments assemble in file-name order (byte order), except versions.md
(the "versions this release moves, stated once" paragraph), which always comes last. README.md in
changelog.d/ is the directory's own documentation, never a fragment.

Usage (subcommands, no dashes; zero dependencies):
    python3 scripts/changelog_assemble.py check   [ROOT]          # validate fragments + the stub; exit 1 on any error
    python3 scripts/changelog_assemble.py print   [ROOT]          # the [Unreleased] body as it would assemble
    python3 scripts/changelog_assemble.py release VER DATE [ROOT] # fold fragments under `## [VER] — DATE`, delete them

ROOT defaults to the repository this script lives in. `release` is deterministic: its output is a pure
function of CHANGELOG.md, the fragment files (names and bytes) and VER/DATE — never of directory order,
time or locale. test/changelogfragcheck.sh pins that with a golden over a fixture tree.
"""

import os
import re
import sys

SECTIONS = ( "Added", "Changed", "Deprecated", "Removed", "Fixed", "Security", "Documented" )
DIR = "changelog.d"
DOC = "README.md"
LAST = "versions.md"
UNRELEASED = "## [Unreleased]"
STUB = ( "Entries for the next release are files under [`changelog.d/`](changelog.d/README.md), one per change; this section\n"
         "stays this one paragraph. At release, the step in CONTRIBUTING.md (\"Cutting a release\") folds the files in\n"
         "under the new version's heading." )

NAME_RE = re.compile( r"^[a-z0-9][a-z0-9._-]*\.md$" )
HEAD_RE = re.compile( r"^### (\S+) — (\S.*)$" )
# A credit names a handle inside a parenthesis that also names the PR, in either house order, or (when the
# entry's heading already names the PR) the bare `(thanks @handle)`.
CREDIT_PAREN_RE = re.compile( r"\((?:#\d+(?:, #\d+)*, )?thanks @[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:, #\d+(?:, #\d+)*)?\)" )
PR_RE = re.compile( r"#\d+" )
# The macOS home root is spelled in two pieces so this tree never carries it whole (test/ripwirepubliccheck.sh arm 2).
PRIVATE_PATH_RE = re.compile( r"/" r"Users/|/home/[a-z]|[A-Za-z]:\\" r"Users\\" )


def repoRoot():
    return os.path.dirname( os.path.dirname( os.path.abspath( __file__ ) ) )


def fragmentNames( root ):
    d = os.path.join( root, DIR )
    if not os.path.isdir( d ):
        return []
    names = sorted( n for n in os.listdir( d ) if n != DOC )
    if LAST in names:
        names.remove( LAST )
        names.append( LAST )
    return names


def readText( path ):
    with open( path, "rb" ) as fh:
        raw = fh.read()
    return raw.decode( "utf-8" )  # a non-UTF-8 fragment raises: check() turns that into an error row


def validateFragment( name, text ):
    """Every problem with one fragment, as messages; [] when it is well formed."""
    errs = []
    if not NAME_RE.match( name ):
        errs.append( "%s: file name must match [a-z0-9][a-z0-9._-]*.md (one .md file per change)" % name )
        return errs
    if "\r" in text:
        errs.append( "%s: CR line ending (use LF)" % name )
    lines = text.rstrip( "\n" ).split( "\n" )
    if not text.strip():
        return errs + [ "%s: empty fragment" % name ]
    m = HEAD_RE.match( lines[ 0 ] )
    if not m:
        errs.append( "%s: line 1 must be `### <Section> — <title>` (got %r)" % ( name, lines[ 0 ][ :80 ] ) )
    elif m.group( 1 ) not in SECTIONS:
        errs.append( "%s: unknown section %r (known: %s)" % ( name, m.group( 1 ), ", ".join( SECTIONS ) ) )
    if len( lines ) < 3 or lines[ 1 ] != "" or not any( l.strip() for l in lines[ 2: ] ):
        errs.append( "%s: line 2 must be blank and a non-empty body must follow the heading" % name )
    for i, l in enumerate( lines[ 1: ], 2 ):
        if l.startswith( "### " ):
            errs.append( "%s:%d: a second `### ` heading — one change per file (split it)" % ( name, i ) )
        if l.startswith( "## " ) or l.startswith( "# " ):
            errs.append( "%s:%d: a `#`/`##` heading would break CHANGELOG.md's release structure" % ( name, i ) )
    if PRIVATE_PATH_RE.search( text ):
        errs.append( "%s: carries a private absolute path (a home directory: macOS, Linux or Windows)" % name )
    bare = len( re.findall( r"thanks @", text ) )
    formed = CREDIT_PAREN_RE.findall( text )
    if bare != len( formed ):
        errs.append( "%s: a credit must read `(thanks @handle, #N)` or `(#N, thanks @handle)` (%d of %d well formed)"
                     % ( name, len( formed ), bare ) )
    if bare and not PR_RE.search( text ):
        errs.append( "%s: credits a contributor but names no PR (#N)" % name )
    return errs


def splitChangelog( text ):
    """(head through the [Unreleased] heading line, the [Unreleased] body, the rest from the next `## [`)."""
    at = text.find( "\n" + UNRELEASED + "\n" )
    if at < 0:
        raise ValueError( "CHANGELOG.md has no `%s` heading" % UNRELEASED )
    bodyStart = at + 1 + len( UNRELEASED ) + 1
    nxt = text.find( "\n## [", bodyStart )
    if nxt < 0:
        return text[ :bodyStart ], text[ bodyStart: ], ""
    return text[ :bodyStart ], text[ bodyStart:nxt + 1 ], text[ nxt + 1: ]


def check( root ):
    errs = []
    d = os.path.join( root, DIR )
    if not os.path.isfile( os.path.join( d, DOC ) ):
        errs.append( "%s/%s is missing (the directory's own how-to)" % ( DIR, DOC ) )
    for n in fragmentNames( root ):
        p = os.path.join( d, n )
        if not os.path.isfile( p ):
            errs.append( "%s: not a regular file" % n )
            continue
        try:
            errs += validateFragment( n, readText( p ) )
        except UnicodeDecodeError:
            errs.append( "%s: not UTF-8" % n )
    try:
        _, body, _ = splitChangelog( readText( os.path.join( root, "CHANGELOG.md" ) ) )
        if body.strip() != STUB:
            errs.append( "CHANGELOG.md's [Unreleased] section carries text beyond the stub. Add your entry as a new file "
                         "changelog.d/<pr-number-or-slug>.md instead (format: changelog.d/README.md); the section itself "
                         "stays the stub so open PRs never conflict on it." )
    except ( OSError, ValueError ) as e:
        errs.append( str( e ) )
    return errs


def assembledEntries( root ):
    out = []
    for n in fragmentNames( root ):
        out.append( readText( os.path.join( root, DIR, n ) ).rstrip( "\n" ) )
    return out


def release( root, ver, date ):
    path = os.path.join( root, "CHANGELOG.md" )
    head, _, rest = splitChangelog( readText( path ) )
    entries = assembledEntries( root )
    if not entries:
        raise ValueError( "no fragments under %s/ — nothing to release" % DIR )
    if re.search( r"^## \[%s\]" % re.escape( ver ), rest, re.M ):   # CR #434: a second section for one version leaves CHANGELOG.md inconsistent
        raise ValueError( "CHANGELOG.md already has a `## [%s]` section — a version is released once (nothing was written)" % ver )
    section = "## [%s] — %s\n\n%s\n\n" % ( ver, date, "\n\n".join( entries ) )
    text = head + "\n" + STUB + "\n\n" + section + rest
    with open( path, "wb" ) as fh:
        fh.write( text.encode( "utf-8" ) )
    for n in fragmentNames( root ):
        os.remove( os.path.join( root, DIR, n ) )
    return len( entries )


def main( argv ):
    if not argv or argv[ 0 ] not in ( "check", "print", "release" ):
        sys.stderr.write( __doc__ )
        return 2
    cmd, args = argv[ 0 ], argv[ 1: ]
    if cmd == "release":
        if len( args ) not in ( 2, 3 ) or not re.match( r"^\d+\.\d+\.\d+$", args[ 0 ] ) \
           or not re.match( r"^\d{4}-\d{2}-\d{2}$", args[ 1 ] ):
            sys.stderr.write( "usage: changelog_assemble.py release X.Y.Z YYYY-MM-DD [ROOT]\n" )
            return 2
        root = args[ 2 ] if len( args ) == 3 else repoRoot()
        errs = check( root )
        if errs:
            sys.stderr.write( "".join( "changelog: %s\n" % e for e in errs ) )
            return 1
        try:
            n = release( root, args[ 0 ], args[ 1 ] )
        except ( OSError, ValueError ) as e:
            sys.stderr.write( "changelog: %s\n" % e )
            return 1
        print( "changelog: folded %d fragment(s) under ## [%s] — %s" % ( n, args[ 0 ], args[ 1 ] ) )
        return 0
    if len( args ) > 1:
        sys.stderr.write( "usage: changelog_assemble.py %s [ROOT]\n" % cmd )
        return 2
    root = args[ 0 ] if args else repoRoot()
    errs = check( root )
    if errs:
        sys.stderr.write( "".join( "changelog: %s\n" % e for e in errs ) )
        return 1
    if cmd == "print":
        sys.stdout.write( "\n\n".join( assembledEntries( root ) ) + "\n" )
    else:
        print( "changelog: %d fragment(s) well formed; [Unreleased] is the stub" % len( fragmentNames( root ) ) )
    return 0


if __name__ == "__main__":
    sys.exit( main( sys.argv[ 1: ] ) )

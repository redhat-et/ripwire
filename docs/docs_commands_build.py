#!/usr/bin/env python3
"""Generate docs/COMMANDS.md — the complete per-flag reference — from the binary itself.

    python3 docs/docs_commands_build.py                      # regenerate docs/COMMANDS.md
    python3 docs/docs_commands_build.py --check              # drift check, no write (exit 1 on drift)
    python3 docs/docs_commands_build.py --bin build/ripwire --capture docs/captures/X.md

WHY GENERATED. A hand-written command reference drifts from the binary the first time a flag lands
without a doc edit, and nothing notices. This reads the SAME `--help` table the binary prints, so the
documented surface cannot disagree with the shipped surface: `--check` is red the moment a flag
exists in one and not the other, and `test/docscommandscheck.sh` runs it.

WHAT IT READS.
  1. `<bin> --help`  — the authoritative flag surface. Sections, flags, and the prose under each
     flag all come from here; nothing about a flag is invented in this script.
  2. A showcase capture (optional) — a markdown file whose `## `<command>`` headings each carry a
     real invocation and its real output. Sample blocks are lifted from it, trimmed, and scrubbed.
     Default: the newest `docs/captures/COMMANDS_showcase_*.md`. Without one, sections still
     generate; they just carry no sample.

NAME-AGNOSTIC. The tool's name is derived from the binary it is pointed at (`basename`), never
hardcoded, and every sample's command token is rewritten to that name. Pointing this at a renamed
binary regenerates a correctly-named document in one command.

CAVEATS ARE DERIVED, NOT AUTHORED. The "honest caveats" under each flag are sentences pulled out of
that flag's own help text by keyword (floor, estimate, heuristic, refuse, never, unresolved, …). A
caveat can therefore never drift from the binary either — if the help stops stating a limit, the
document stops printing it.
"""

import argparse
import glob
import os
import re
import subprocess
import sys

HERE = os.path.dirname( os.path.abspath( __file__ ) )
ROOT = os.path.dirname( HERE )

# ── the public-export scrub contract ──────────────────────────────────────────────────────────────
# Samples are lifted from a capture that ran on someone's disk, in a tree with internal branch names.
# Everything below is rewritten or dropped before it reaches the document; `assert_scrubbed` then
# re-checks the finished text with the same patterns the repository's own scrub gate uses, so a new
# leak shape fails the build instead of shipping.
# NOTE ON SPELLING: the home-directory pattern is written `[Uu]sers` rather than the literal, so
# this file does not itself contain the string the export gate greps for. Behaviour is identical.
HOME_PATH   = re.compile( r'/(?:[Uu]sers|home)/[^\s"\'<>()]*' )
TMP_PATH    = re.compile( r'/(?:var|private)/[A-Za-z0-9_./-]*(?:folders|tmp)[A-Za-z0-9_./-]*' )
COORD       = re.compile( r'§A|§B[0-9]|§P[0-9]|V[0-9]-[0-9]|W[0-9]|r[0-9][0-9]-' )
REFNAME     = re.compile( r'\br[0-9][0-9]-[A-Za-z0-9_*-]*' )
# Personal identifiers a real run leaks: git author emails (--owners `top=`), and any address in
# body text. Names are not enumerable here, so `top=`/`author=` attribute VALUES are replaced whole.
EMAIL       = re.compile( r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' )
AUTHOR_ATTR = re.compile( r'\b(top|author|owner)="[^"]*"' )
# Internal-only document names from the private development tree, if a sample happens to rank one.
INTERNAL_DOC = re.compile( r'\b(?:PLAN_|AUDIT|NEXT_SESSION|KICKOFF_|HANDOFF_|IDEAS_|REPORT_|DESIGN_|RESEARCH_)[A-Za-z0-9_.-]*' )

MAX_SAMPLE_LINES = 14
MAX_SAMPLE_BYTES = 1600

CAVEAT_WORDS = (
    'floor', 'counts_floor', 'ambig', 'heuristic', 'estimate', 'calibrated', 'never', 'not exact',
    'refuse', 'unresolved', 'caveat', 'limit', 'unmodelled', 'cannot', 'degrade', 'inert',
    'over_ceiling', 'truncat', 'capped', 'stated', 'not a', 'no guarantee', 'skip',
)


# ── reading the binary ────────────────────────────────────────────────────────────────────────────

def tool_name_of( binPath ):
    """The tool's name is whatever the binary is called. Never hardcoded."""
    return os.path.basename( binPath )


def help_text_of( binPath ):
    try:
        run = subprocess.run( [ binPath, '--help' ], capture_output = True, text = True, timeout = 120 )
    except OSError as exc:
        sys.exit( 'docs_commands_build: cannot run %s (%s)' % ( binPath, exc ) )
    if run.returncode != 0 and not run.stdout:
        sys.exit( 'docs_commands_build: %s --help exited %d with no output' % ( binPath, run.returncode ) )
    return run.stdout


FLAG_TOKEN = re.compile( r'^--?[A-Za-z0-9][A-Za-z0-9-]*' )


def normalize_flags( spec ):
    """'--html[=FILE]' -> ['--html'];  '--grep=STR | --regex=PAT' -> ['--grep','--regex'].

    One choke point: the flag NAME is what the drift gate compares, so value syntax, optional-value
    brackets and alternation must all be stripped here and nowhere else, or the two sides of the
    comparison would normalize differently and the gate would red on formatting.
    """
    out = []
    for part in re.split( r'[|/]', spec ):
        part = part.strip()
        m    = FLAG_TOKEN.match( part )
        if m:
            out.append( m.group( 0 ) )
    return out


def parse_help( helpText ):
    """--help -> ( preamble, [ ( sectionTitle, [ entry, ... ] ) ] ).

    An entry is { 'flags': [ '--for', ... ], 'spec': '--for=TASK', 'text': 'the prose' }.
    Section headings are 2-space indented; flag entries are 4- to 6-space indented and start with a
    dash; everything else at those indents is continuation prose for the entry above it.
    """
    sections   = []
    preamble   = []
    current    = None
    entry      = None
    reSection  = re.compile( r'^  (\S.*?)\s*$' )
    reEntry    = re.compile( r'^ {4,6}(-\S*(?:\s*\|\s*-\S*)*)(\s\s+|\s*$)(.*)$' )

    for line in helpText.split( '\n' ):
        mSection = reSection.match( line ) if not line.startswith( '   ' ) else None
        if mSection:
            entry   = None
            current = ( mSection.group( 1 ), [] )
            sections.append( current )
            continue

        mEntry = reEntry.match( line ) if current else None
        if mEntry:
            spec  = mEntry.group( 1 ).strip()
            flags = normalize_flags( spec )
            entry = { 'flags': flags, 'spec': spec, 'text': [ mEntry.group( 3 ).strip() ] }
            current[ 1 ].append( entry )
            continue

        stripped = line.strip()
        if entry is not None and stripped and line.startswith( '    ' ):
            entry[ 'text' ].append( stripped )
        elif current is None and stripped:
            preamble.append( stripped )
        elif not stripped:
            entry = None

    for _title, entries in sections:
        for e in entries:
            e[ 'text' ] = ' '.join( t for t in e[ 'text' ] if t )
    return preamble, sections


# ── reading the capture ───────────────────────────────────────────────────────────────────────────

def newest_capture():
    found = sorted( glob.glob( os.path.join( ROOT, 'docs', 'captures', 'COMMANDS_showcase_*.md' ) ) )
    return found[ -1 ] if found else None


def parse_capture( path ):
    """capture markdown -> [ { 'cmd': str, 'caption': str, 'body': [ lines ] } ].

    Headings look like:  ## `./build/<tool> . --top-k=5`
    followed by an optional italic caption line and one fenced block holding the real output.
    """
    if not path or not os.path.exists( path ):
        return []
    text  = open( path, encoding = 'utf-8', errors = 'replace' ).read().split( '\n' )
    items = []
    i     = 0
    reHead = re.compile( r'^## `(.+)`\s*$' )
    while i < len( text ):
        mHead = reHead.match( text[ i ] )
        if not mHead:
            i += 1
            continue
        item = { 'cmd': mHead.group( 1 ), 'caption': '', 'body': [] }
        i   += 1
        while i < len( text ) and not text[ i ].strip():
            i += 1
        if i < len( text ) and text[ i ].startswith( '*' ) and text[ i ].rstrip().endswith( '*' ):
            item[ 'caption' ] = text[ i ].strip().strip( '*' ).strip()
            i += 1
        # the fenced block: the capture uses long backtick fences so inner ``` survives
        while i < len( text ) and not text[ i ].startswith( '```' ):
            if text[ i ].startswith( '## ' ) or text[ i ].startswith( '# ' ):
                break
            i += 1
        if i < len( text ) and text[ i ].startswith( '```' ):
            fence = text[ i ].rstrip()
            i += 1
            while i < len( text ) and text[ i ].rstrip() != fence:
                item[ 'body' ].append( text[ i ] )
                i += 1
            i += 1
        items.append( item )
    return items


def flag_tokens_of( cmd ):
    return set( re.findall( r'--[A-Za-z0-9][A-Za-z0-9-]*', cmd ) )


def pick_sample( entry, captures ):
    """The clearest real invocation of this flag: the one that uses the fewest OTHER flags."""
    wanted = set( entry[ 'flags' ] )
    best   = None
    bestScore = None
    for item in captures:
        toks = flag_tokens_of( item[ 'cmd' ] )
        if not ( toks & wanted ):
            continue
        if not item[ 'body' ]:
            continue
        score = ( len( toks - wanted ), len( item[ 'cmd' ] ) )
        if bestScore is None or score < bestScore:
            bestScore, best = score, item
    return best


# ── scrubbing + trimming ──────────────────────────────────────────────────────────────────────────

def scrub( text, name ):
    text = HOME_PATH.sub( '<path>', text )
    text = TMP_PATH.sub( '<tmp>', text )
    text = REFNAME.sub( 'topic-branch', text )
    text = AUTHOR_ATTR.sub( lambda m: '%s="<author>"' % m.group( 1 ), text )
    text = EMAIL.sub( '<author>', text )
    text = INTERNAL_DOC.sub( 'NOTES.md', text )
    return text


def scrub_prose( text, name ):
    """Same contract as `scrub`, but for HELP prose, where a path substitution would read wrong.

    The binary's help occasionally cites an internal design note by filename. That name must not
    ship, but replacing it with a path spelling mid-sentence reads like a broken link — so prose
    gets a phrase. Either way the substitution is REPORTED (see `assert_scrubbed`) so the fix can
    land in the help text, which is where it belongs.
    """
    text = HOME_PATH.sub( '<path>', text )
    text = TMP_PATH.sub( '<tmp>', text )
    text = REFNAME.sub( 'topic-branch', text )
    text = EMAIL.sub( '<author>', text )
    text = INTERNAL_DOC.sub( 'an internal design note', text )
    return text


def rewrite_command( cmd, name ):
    """Normalize the capture's binary token to this build's name, whatever it was called."""
    cmd = scrub( cmd, name )
    cmd = re.sub( r'^\S*?(?:\./)?(?:build/)?[A-Za-z0-9_.-]+(?=\s|$)', './build/' + name, cmd, count = 1 )
    return cmd


def trim_sample( body, name ):
    kept    = []
    total   = 0
    dropped = 0
    for raw in body:
        line = scrub( raw, name )
        if COORD.search( line ):
            # A line that still trips the export scrub after substitution is dropped rather than
            # mangled — an omitted line is honest, a silently edited one is not.
            dropped += 1
            continue
        if len( kept ) >= MAX_SAMPLE_LINES or total + len( line ) > MAX_SAMPLE_BYTES:
            break
        kept.append( line )
        total += len( line )
    more = len( body ) - len( kept ) - dropped
    if more > 0:
        kept.append( '... [%d more line(s); run it to see the whole thing]' % more )
    if dropped:
        kept.append( '... [%d line(s) omitted by the public-export scrub]' % dropped )
    return kept


# ── caveats, derived from the flag's own help prose ───────────────────────────────────────────────

def caveats_of( entry ):
    text      = entry[ 'text' ]
    sentences = re.split( r'(?<=[.;])\s+', text )
    out       = []
    for s in sentences:
        low = s.lower()
        if len( s ) < 25 or len( s ) > 320:
            continue
        if any( w in low for w in CAVEAT_WORDS ):
            out.append( s.strip() )
        if len( out ) >= 3:
            break
    return out


def shaped_by( entry, sections ):
    """Other flags whose own help text names this one — 'flags that shape it', derived not guessed."""
    mine  = set( entry[ 'flags' ] )
    out   = []
    for _title, entries in sections:
        for other in entries:
            if set( other[ 'flags' ] ) & mine:
                continue
            if any( f in other[ 'text' ] for f in mine ):
                out.append( other[ 'flags' ][ 0 ] )
    seen = []
    for f in out:
        if f not in seen:
            seen.append( f )
    return seen[ :8 ]


# ── rendering ─────────────────────────────────────────────────────────────────────────────────────

def anchor_of( spec ):
    return re.sub( r'[^a-z0-9]+', '-', spec.lower() ).strip( '-' )


def render( name, preamble, sections, captures, capturePath ):
    out = []
    w   = out.append

    w( '# %s — every flag, generated from the binary' % name )
    w( '' )
    w( '**This file is generated. Do not hand-edit it.** Regenerate with:' )
    w( '' )
    w( '```bash' )
    w( 'python3 docs/docs_commands_build.py --bin build/%s' % name )
    w( '```' )
    w( '' )
    w( 'The flag surface below is read from `%s --help`, so it cannot disagree with the shipped' % name )
    w( 'binary. `test/docscommandscheck.sh` fails if it ever does — in either direction.' )
    w( '' )
    if capturePath:
        w( 'Sample output is lifted from a real recorded run (`%s`), trimmed to the first few lines and'
           % os.path.relpath( capturePath, ROOT ) )
        w( 'scrubbed of local paths. It is illustrative, not a golden: run the command yourself for the' )
        w( 'current shape.' )
    else:
        w( '_No showcase capture was available when this was generated, so sections carry no sample output._' )
    w( '' )
    if preamble:
        w( '> ' + '\n> '.join( scrub_prose( p, name ) for p in preamble[ :6 ] ) )
        w( '' )

    w( '## How to read a section' )
    w( '' )
    w( '- **Answers** — the question this flag exists to answer.' )
    w( '- **Try it** — a real invocation and the real output it produced.' )
    w( '- **Shaped by** — other flags that change what this one emits.' )
    w( '- **Caveats** — the limits the binary itself states for this flag. They are extracted from its' )
    w( '  own help text, so they cannot drift from the code.' )
    w( '' )
    w( 'Two limits apply to nearly everything here and are not repeated in every section:' )
    w( '' )
    w( '1. **Call edges are heuristic and name-based.** Dynamic dispatch, callbacks and macro-generated' )
    w( '   call sites produce no edge, so counts on the graph verbs carry `counts_floor="1"`. **Read a 0' )
    w( '   as "none found", never as "none exists."**' )
    w( '2. **A symbol\'s `amb="K"`** means K of its calls hit a name with several definitions and the' )
    w( '   resolver split the weight rather than choosing. Read the source when which-target matters.' )
    w( '' )

    # ── table of contents ──
    w( '## Contents' )
    w( '' )
    for title, entries in sections:
        if not entries:
            continue
        w( '**%s** — %s' % ( title, ' · '.join( '[`%s`](#%s)' % ( e[ 'flags' ][ 0 ], anchor_of( e[ 'spec' ] ) )
                                                for e in entries ) ) )
        w( '' )

    # ── the sections ──
    for title, entries in sections:
        if not entries:
            continue
        w( '---' )
        w( '' )
        w( '## %s' % title )
        w( '' )
        for entry in entries:
            spec = entry[ 'spec' ]
            w( '### `%s`' % spec )
            w( '' )
            text = scrub_prose( entry[ 'text' ], name ).strip()
            first = re.split( r'(?<=[.;])\s+', text )[ 0 ] if text else ''
            if first:
                w( '**Answers:** %s' % first )
                w( '' )
            rest = text[ len( first ) : ].strip()
            if rest:
                w( rest )
                w( '' )

            sample = pick_sample( entry, captures )
            if sample:
                w( '**Try it**' )
                w( '' )
                caption = scrub( sample[ 'caption' ], name )
                if caption and not COORD.search( caption ):
                    w( '_%s_' % caption )
                    w( '' )
                w( '```' )
                w( '$ ' + rewrite_command( sample[ 'cmd' ], name ) )
                for line in trim_sample( sample[ 'body' ], name ):
                    w( line )
                w( '```' )
                w( '' )

            shapers = shaped_by( entry, sections )
            if shapers:
                w( '**Shaped by:** %s' % ', '.join( '`%s`' % f for f in shapers ) )
                w( '' )

            cav = caveats_of( entry )
            if cav:
                w( '**Caveats (stated by the binary):**' )
                w( '' )
                for c in cav:
                    w( '- %s' % scrub_prose( c, name ) )
                w( '' )

    w( '---' )
    w( '' )
    w( '_Generated by `docs/docs_commands_build.py`. See `docs/README.md` for the documentation index._' )
    w( '' )
    return '\n'.join( out )


def assert_scrubbed( text ):
    """The generator must not be able to emit what the public-export gate forbids."""
    bad = []
    for i, line in enumerate( text.split( '\n' ), 1 ):
        if HOME_PATH.search( line ):
            bad.append( '%d: absolute home path' % i )
        elif COORD.search( line ):
            bad.append( '%d: internal coordinate shape: %s' % ( i, line.strip()[ :90 ] ) )
        elif EMAIL.search( line ):
            bad.append( '%d: email address: %s' % ( i, line.strip()[ :90 ] ) )
        elif INTERNAL_DOC.search( line ):
            bad.append( '%d: internal document name: %s' % ( i, line.strip()[ :90 ] ) )
    if bad:
        sys.exit( 'docs_commands_build: refusing to write — scrub violations:\n  ' + '\n  '.join( bad[ :20 ] ) )

    # NOT fatal, but reported: help prose that still carries an internal issue label ("(X9(d): …",
    # "(D10)"). Those come from the BINARY's own --help, so the fix belongs there, not here —
    # silently rewriting them in the document would hide the drift instead of surfacing it.
    residue = re.compile( r'\(\s*[A-Z][0-9]{1,2}(?:\([a-z]\))?\s*[):]' )
    hits    = [ ( i, m.group( 0 ) ) for i, line in enumerate( text.split( '\n' ), 1 )
                for m in [ residue.search( line ) ] if m ]
    if hits:
        sys.stderr.write(
            'docs_commands_build: NOTE — %d line(s) carry an internal issue label inherited from '
            '--help (%s). Fix the help text; this generator will not rewrite it.\n'
            % ( len( hits ), ', '.join( sorted( { h[ 1 ] for h in hits } )[ :6 ] ) ) )


# ── the drift check ───────────────────────────────────────────────────────────────────────────────

def documented_flags( docText ):
    out = set()
    for line in docText.split( '\n' ):
        m = re.match( r'^### `(.+)`\s*$', line )
        if not m:
            continue
        out.update( normalize_flags( m.group( 1 ) ) )
    return out


def binary_flags( sections ):
    out = set()
    for _title, entries in sections:
        for e in entries:
            out.update( e[ 'flags' ] )
    return out


def main():
    ap = argparse.ArgumentParser( description = 'generate docs/COMMANDS.md from the binary' )
    ap.add_argument( '--bin', default = None, help = 'the binary to read --help from' )
    ap.add_argument( '--capture', default = None, help = 'showcase capture markdown for samples' )
    ap.add_argument( '--out', default = os.path.join( ROOT, 'docs', 'COMMANDS.md' ) )
    ap.add_argument( '--check', action = 'store_true',
                     help = 'compare the documented flag set against the binary; write nothing' )
    ap.add_argument( '--no-capture', action = 'store_true',
                     help = 'write a sample-free document on purpose (required when no capture is found)' )
    args = ap.parse_args()

    binPath = args.bin
    if not binPath:
        found = [ p for p in glob.glob( os.path.join( ROOT, 'build', '*' ) )
                  if os.path.isfile( p ) and os.access( p, os.X_OK ) ]
        if len( found ) != 1:
            sys.exit( 'docs_commands_build: pass --bin (found %d executables under build/)' % len( found ) )
        binPath = found[ 0 ]

    name  = tool_name_of( binPath )
    preamble, sections = parse_help( help_text_of( binPath ) )
    if not sections:
        sys.exit( 'docs_commands_build: parsed 0 sections from --help — the help format changed' )

    if args.check:
        if not os.path.exists( args.out ):
            sys.exit( 'docs_commands_build: %s does not exist' % args.out )

        doc     = documented_flags( open( args.out, encoding = 'utf-8' ).read() )
        binary  = binary_flags( sections )
        missing = sorted( binary - doc )
        stale   = sorted( doc - binary )
        if missing or stale:
            if missing:
                print( 'DRIFT: in %s --help but NOT documented: %s' % ( name, ' '.join( missing ) ) )
            if stale:
                print( 'DRIFT: documented but NOT in %s --help: %s' % ( name, ' '.join( stale ) ) )
            print( 'regenerate: python3 docs/docs_commands_build.py --bin %s' % binPath )
            return 1
        print( 'docs_commands_build: %d flags, documented set == binary set' % len( binary ) )
        return 0

    capturePath = args.capture or newest_capture()
    captures    = parse_capture( capturePath )
    # Regenerating without a capture silently deletes every sample block from a document that had
    # them — a large, invisible loss that would look like a successful rebuild. Refuse instead, and
    # make the sample-free document an explicit request.
    if not captures and not args.no_capture:
        sys.exit( 'docs_commands_build: no showcase capture found%s.\n'
                  '  Samples would be DROPPED from the generated document.\n'
                  '  Pass --capture PATH, put one under docs/captures/COMMANDS_showcase_*.md,\n'
                  '  or pass --no-capture to write a sample-free document deliberately.'
                  % ( ' at ' + args.capture if args.capture else '' ) )
    text        = render( name, preamble, sections, captures, capturePath if captures else None )
    assert_scrubbed( text )
    os.makedirs( os.path.dirname( args.out ), exist_ok = True )
    with open( args.out, 'w', encoding = 'utf-8' ) as fh:
        fh.write( text )
    print( 'docs_commands_build: wrote %s — %d flags in %d sections, %d sample(s) from %s'
           % ( os.path.relpath( args.out, ROOT ), len( binary_flags( sections ) ), len( sections ),
               sum( 1 for _t, es in sections for e in es if pick_sample( e, captures ) ),
               os.path.relpath( capturePath, ROOT ) if capturePath and captures else 'no capture' ) )
    return 0


if __name__ == '__main__':
    sys.exit( main() )

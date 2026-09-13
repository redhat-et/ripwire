#!/usr/bin/env bash
# ripwirepubliccheck.sh — the public-export scrub gate. This repository is an EXPORT of a private
# development tree; this gate is the machine-checked statement that nothing from that tree leaked.
#
# SCOPE: the COMMITTED tree only — every arm walks `git ls-files`, never the working directory.
# That is deliberate and is what makes the gate mean something: a clone gets exactly the committed
# files, so the committed set is the thing a stranger can read. It also lets the migration keep
# rewrite-pending files (README.md, CHANGELOG.md, CLAUDE.md, AGENTS.md, CONTRIBUTING.md) on disk as
# untracked working material without the gate reporting a leak that no clone could ever see. The
# flip side: a file this gate passes today can still fail tomorrow if it is committed unchanged, so
# run it BEFORE `git add`, not after.
#
# Arms:
#   1. the private working-copy name, case-insensitive, zero tolerance
#   1b. the private pre-release name, case-insensitive, matched by hash so this file never spells it
#      (offenders print as path:line only)
#   2. absolute /Users/ paths
#   3. audit-round coordinates (§A, §B<d>, §P<d>, V<d>-<d>, W<d>, r<dd>-) in EMITTED strings and
#      in shipped markdown — NOT in ordinary source comments
#   4. credential-shaped literals outside the redaction fixtures that legitimately need them
#   5. personal names / handles / emails outside LICENSE and AUTHORS
#   6. docs/ index coverage + no internal-pattern FILENAME anywhere in the tree
#   7. include closure: no quoted #include escapes the repo; no include path names the private tree
#   8. no reference to an internal-pattern .md name that is ABSENT from this tree (a dangling pointer
#      at a culled process doc); a reference to a .md that DOES ship is fine
#
# Usage:  bash test/ripwirepubliccheck.sh
# Exit:   0 = clean · 1 = at least one arm failed (offenders listed) · 2 = usage / missing tool.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
cd "$ROOT" || { printf 'ripwirepubliccheck: cannot cd to repo root %s\n' "$ROOT"; exit 2; }
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# A missing tool must never read as a clean tree — that is the green-while-inert failure this suite
# exists to catch. Name the tool and exit 2.
for _tool in git grep python3; do
    command -v "$_tool" >/dev/null 2>&1 || {
        printf 'ripwirepubliccheck: required tool missing: %s (gate cannot run)\n' "$_tool"; exit 2; }
done
git rev-parse --git-dir >/dev/null 2>&1 || {
    printf 'ripwirepubliccheck: not a git repository (gate scopes to git ls-files)\n'; exit 2; }

TMP="$( mktemp -d )"
trap 'rm -rf "$TMP"' EXIT
git ls-files -z > "$TMP/tracked.z" || { printf 'ripwirepubliccheck: git ls-files failed\n'; exit 2; }
tracked=$( tr -dc '\0' < "$TMP/tracked.z" | wc -c | tr -d ' ' )
[ "$tracked" -gt 0 ] || { printf 'ripwirepubliccheck: no tracked files (nothing to check)\n'; exit 2; }

# Text-only sweep over the committed set. `grep -I` skips binaries; -z keeps pathnames with spaces
# intact. Every arm below funnels through this so the scope statement above is true by construction.
#
# SELF-EXCLUSION: this file states the forbidden patterns literally, so it matches its own arms. It
# is excluded from every sweep — the same idiom the gate it replaces used. The cost is real and
# named here: a genuine leak written INTO this script is the one thing the script cannot see, so
# treat edits to it as edits to a trusted file and review them by eye.
SELF="test/$( basename "$0" )"
sweep(){  # sweep <extended-regex> [extra grep flags...]
    local re="$1"; shift
    xargs -0 grep -InE "$@" -- "$re" < "$TMP/tracked.z" 2>/dev/null | grep -vF "$SELF:"
}

# ── arm 1: the private working-copy name, anywhere, any case ──────────────────────────────────────
hits="$( sweep 'canyonraid' -i || true )"
if [ -n "$hits" ]; then
    no "arm 1 — private tree name present in $( printf '%s\n' "$hits" | wc -l | tr -d ' ' ) place(s):"
    printf '%s\n' "$hits" | sed 's/^/          /'
else
    ok "arm 1 — no reference to the private development tree"
fi

# ── arm 1b: the private pre-release name, matched by hash ─────────────────────────────────────────
# Arm 1 spells what it hunts. This arm cannot: its target is the name the project carried before it was
# public, and a detector that spells a name publishes it. So it stores the SHA-256 of the lowercase token
# and the token's length, never the token — the same "never spell what you withhold" rule
# docs/docs_commands_build.py keeps for the rebrand's rename rows. A hash of a short word keeps it out of
# grep, search indexes and a casual read of this file; it is not secrecy against someone who sets out to
# recover it, and nothing here claims otherwise.
#
# MATCHING. Every tracked text file is lowercased and split into runs of ASCII letters, and every window
# of the stored length inside a run is hashed — so the bare word, `NAME_BIN`, `name/src/x.h`, `name@sha`,
# a CamelCase `NameIndex` and `libnamerc` all match. A token broken by a non-letter (`na-me`) does not.
# Unlike the grep arms, this one needs no self-exclusion: the script carries no spelling to find.
#
# OUTPUT IS path:line ONLY. Printing the offending line would publish the name in the log of every red
# run, CI logs included — the same call docs_commands_build.py's rebrand_row_public_side makes.
#
# EXEMPT BY CONTENT HASH, NOT BY PATH. bench/recalleval/snapshot.mdpack is the recall lane's byte-frozen
# corpus — every tracked *.md at the commit snapshot.lock pins — so it still carries docs/EVALS.md's old
# wording, and recallevalcheck's check #0 reds any in-place edit: rewriting it is a recalibration, not a
# scrub. Its hits are exempt only while its bytes hash to the value pinned below. The next
# `make_snapshot.py --freeze` changes those bytes, the exemption stops applying, and a pack refrozen from
# a tree that still carries the name is reported like any other file.
#
# Every tracked PDF/PPTX (the deck) is extracted and scanned too, for arm 2b's reason: a name rendered into a
# slide is invisible to every text sweep of the tree. A deck is CLEARED only by being READ. No extractor, a
# failed extraction or an empty result FAILS this arm — never a SKIP beside a standing PASS, which pargates
# counts as proving nothing while CI still goes green.
#
# EVERY I/O STEP FAILS CLOSED. The scanner reads each tracked file and each deck itself: pdftotext writes to a
# pipe and a PPTX is unzipped in memory, so no extracted text passes through a temp file whose write could fail.
# A file it cannot read becomes an UNREAD record, never "no findings". Its report ends in a COUNT record and an END
# record, and the judge reaches PASS only by reading all of it: exit 0, END last, a deck total equal to this
# shell's own NUL-delimited count of the `git ls-files -z` list, and read totals that match the UNREAD records. A
# report that is missing, cut short or inconsistent has no verdict, and that FAILS. Paths never split on a newline:
# the list is NUL-delimited on both sides, and every printed path has its control characters escaped. The controls
# below prove each of these on planted inputs.
#
# EXTRACTION IS BOUNDED. A deck's text is read through a fixed byte bound, ARM1B_TEXT_BOUND: pdftotext's pipe is
# drained as it fills and never held past the bound, and a PPTX is refused on the uncompressed total its slide and
# notes parts DECLARE before any part is opened, then each part is read through the same bound, so a header that
# understates its size is caught by the read. A deck over the bound is UNREAD, which fails the arm; it is never
# skipped and never buffered whole. The tracked decks extract to tens of kilobytes, so the bound is a blow-up guard
# for CI memory, not a size any real deck approaches.
#
# A PPTX IS SCANNED AS THE TEXT IT DISPLAYS, NOT AS RAW XML. Slide and notes-slide parts are parsed, and the `<a:t>`
# runs of each paragraph are joined in document order into one line, because a name broken across two runs
# (`<a:t>Na</a:t><a:t>me</a:t>`, which a slide editor produces whenever formatting changes mid-word) is displayed
# whole while no raw scan can see it. Runs in different paragraphs stay on different lines. A part that declares a
# DTD is refused unparsed: slide XML never carries one, and entity expansion is the one way a part inside the bound
# could grow past it.
ARM1B_TEXT_BOUND=$(( 32 * 1024 * 1024 ))
PRERELEASE_NAME_SHA256='7 904522dda28c1584057c235feec23321855e1760d01116dfc6bf851411c69c7c'
PRERELEASE_EXEMPT_SHA256='bench/recalleval/snapshot.mdpack 6f60a279b582356f5e06091069d1c948889b6d3ccbc1b2d4e3b0d31321326717'
# deck_kind PATH — sets _kind to pdf, pptx or nothing. A glob on the WHOLE path with the extension in any case:
# no subshell and no line splitting, so a newline or a space in the path is just another character.
deck_kind(){
    case "$1" in
      *.[pP][dD][fF])     _kind=pdf ;;
      *.[pP][pP][tT][xX]) _kind=pptx ;;
      *)                  _kind= ;;
    esac
}
# count_decks LIST — sets _decks to the decks in a `git ls-files -z` LIST, counted HERE, NUL-delimited and
# independently of the scanner, so a scanner that skipped a deck cannot agree with it. Fails if LIST cannot be
# opened; a list cut short can only count low, which the judge reports as a mismatch.
count_decks(){
    local path=
    _decks=0
    { while IFS= read -r -d '' path || [ -n "$path" ]; do
          deck_kind "$path"
          [ -z "$_kind" ] || _decks=$(( _decks + 1 ))
          path=
      done; } < "$1"
}
# The scanner. argv: tracked list (ls-files -z), target rows, exempt rows. It writes nothing but its report, and
# the report's last two records are COUNT and END: a report cut short anywhere has lost at least END.
if ! cat > "$TMP/arm1b.py" <<'PY'
import hashlib, os, re, select, shutil, subprocess, sys, time, zipfile
import xml.etree.ElementTree as ET
paths = [ p for p in open( sys.argv[ 1 ], 'rb' ).read().split( b'\0' ) if p ]
BOUND = int( sys.argv[ 4 ] ) if len( sys.argv ) > 4 and re.fullmatch( r'[0-9]+', sys.argv[ 4 ] ) else 0
if BOUND < 1:
    print( 'REFUSE the extracted-text bound must be a positive byte count' )
    sys.exit( 1 )
exempt = dict( line.split() for line in sys.argv[ 3 ].splitlines() if line.strip() )
targets = {}
for line in sys.argv[ 2 ].splitlines():
    if not line.strip():
        continue
    length, digest = line.split()
    if not re.fullmatch( r'[0-9a-f]{64}', digest ) or int( length ) < 1:
        print( 'REFUSE malformed target row (want "<length> <sha256 hex>")' )
        sys.exit( 1 )
    targets.setdefault( int( length ), set() ).add( digest )
if not targets:
    print( 'REFUSE no target hashes: the arm would pass while matching nothing' )
    sys.exit( 1 )

def shown( path ):
    """A path as ONE output record: undecodable bytes and control characters (a newline above all) become \\xNN."""
    text = path.decode( 'utf-8', 'backslashreplace' ) if isinstance( path, bytes ) else path
    return re.sub( r'[\x00-\x1f\x7f]', lambda m: '\\x%02x' % ord( m.group() ), text )

DECK = re.compile( rb'\.(pdf|pptx)\Z', re.I )
TIMEOUT = 300

def run_bounded( argv, bound, timeout ):
    """( stdout, None ) when ARGV exits 0 having written at most BOUND bytes within TIMEOUT seconds, else ( None, why ).
    The pipe is drained as it fills, so the process is stopped after BOUND + 1 bytes rather than buffered whole."""
    try:
        proc = subprocess.Popen( argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL )
    except OSError as exc:
        return None, 'could not run (%s)' % exc.__class__.__name__
    fd, deadline, chunks, size, why = proc.stdout.fileno(), time.monotonic() + timeout, [], 0, None
    try:
        while True:
            left = deadline - time.monotonic()
            if left <= 0 or not select.select( [ fd ], [], [], left )[ 0 ]:
                why = 'produced no end of output within %d s' % timeout
                break
            chunk = os.read( fd, 1 << 16 )
            if not chunk:
                break
            size += len( chunk )
            if size > bound:
                why = 'wrote more than the %d-byte bound of extracted text' % bound
                break
            chunks.append( chunk )
        if why is None:
            try:
                code = proc.wait( timeout=max( deadline - time.monotonic(), 0 ) )
            except subprocess.TimeoutExpired:
                why = 'did not exit within %d s' % timeout
            else:
                if code != 0:
                    why = 'could not read it (exit %d)' % code
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        proc.stdout.close()
    return ( b''.join( chunks ), None ) if why is None else ( None, why )

A = '{http://schemas.openxmlformats.org/drawingml/2006/main}'
PART = re.compile( r'ppt/(slides|notesSlides)/[^/0-9]*([0-9]*)[^/]*\.xml' )

def part_order( name ):
    """Slides before notes, each in numeric order (slide2 before slide10), then the name for anything unnumbered."""
    match = PART.fullmatch( name )
    return ( 0 if match.group( 1 ) == 'slides' else 1, int( match.group( 2 ) or 0 ), name )

def displayed_lines( root ):
    """The text a slide part displays: one line per `<a:p>` paragraph, its `<a:t>` runs joined in document order and
    an `<a:br/>` a line break inside it. A run outside every paragraph, which the schema never produces, is kept as its
    own line rather than lost."""
    lines, inside = [], 0
    for para in root.iter( A + 'p' ):
        pieces = []
        for node in para.iter():
            if node.tag == A + 't':
                pieces.append( node.text or '' )
                inside += 1
            elif node.tag == A + 'br':
                pieces.append( '\n' )
        lines.extend( ''.join( pieces ).split( '\n' ) )
    runs = [ node.text or '' for node in root.iter( A + 't' ) ]
    if len( runs ) != inside:
        lines.extend( runs )
    return lines

def pptx_text( name, bound ):
    """( text, None ) or ( None, why ). The uncompressed total the slide and notes parts DECLARE is checked before
    any part is opened; each part is then read through the same bound, so a header that lies is caught by the read.
    A part carrying a DTD is refused unparsed: slide XML never has one, and entity expansion is the one way a part
    inside the bound could grow past it."""
    try:
        with zipfile.ZipFile( name ) as deck:
            parts = sorted( ( n for n in deck.namelist() if PART.fullmatch( n ) ), key=part_order )
            declared = sum( deck.getinfo( n ).file_size for n in parts )
            if declared > bound:
                return None, 'its slide and notes parts declare %d bytes, over the %d-byte bound' % ( declared, bound )
            lines, size = [], 0
            for n in parts:
                with deck.open( n ) as part:
                    data = part.read( bound + 1 - size )
                size += len( data )
                if size > bound:
                    return None, 'its slide and notes parts expand past the %d-byte bound' % bound
                if b'<!DOCTYPE' in data or b'<!ENTITY' in data:
                    return None, 'part %s declares a DTD, which slide XML never does' % n
                lines.extend( displayed_lines( ET.fromstring( data ) ) )
    except Exception as exc:   # any failure to read or parse the archive leaves the deck unread, never clean
        return None, 'it is not a readable PPTX (%s)' % exc.__class__.__name__
    return '\n'.join( lines ).encode( 'utf-8' ), None

def deck_text( path ):
    """( text, None ) when the deck was READ, else ( None, reason ). Nothing is written to disk: pdftotext prints to
    a pipe and the PPTX is unzipped in memory, each through BOUND. './' keeps a path that starts with '-' from reading
    as an option. A deck that displays no letters at all is UNREAD, the same rule for an image-only PDF and PPTX: a
    name rendered as pixels is invisible to every text tool, and this arm says so rather than clearing the deck."""
    name = os.fsdecode( os.path.join( b'.', path ) )
    if path.lower().endswith( b'.pdf' ):
        tool = shutil.which( 'pdftotext' )
        if not tool:
            return None, 'pdftotext (poppler) is not installed'
        text, why = run_bounded( [ tool, '-q', name, '-' ], BOUND, TIMEOUT )
        if text is None:
            return None, 'pdftotext ' + why
    else:
        text, why = pptx_text( name, BOUND )
        if text is None:
            return None, why
    if not re.search( rb'[A-Za-z]', text ):
        return None, 'extraction produced no text'
    return text, None

def make_scan( targets ):
    """data (bytes) -> the 1-based line numbers carrying a target token. Each maximal letter run is hashed
    once for the whole sweep, so a word that recurs in a thousand files costs one set of hashes."""
    run_res = { n: re.compile( rb'[a-z]{%d,}' % n ) for n in targets }
    verdict = {}
    def scan( data ):
        low = data.lower()
        bad = set()
        for n, run_re in run_res.items():
            for run in set( run_re.findall( low ) ):
                key = ( n, run )
                if key not in verdict:
                    verdict[ key ] = any( hashlib.sha256( run[ i:i + n ] ).hexdigest() in targets[ n ]
                                          for i in range( len( run ) - n + 1 ) )
                if verdict[ key ]:
                    bad.add( run )
        if not bad:
            return []
        return [ i for i, line in enumerate( low.split( b'\n' ), 1 ) if any( run in line for run in bad ) ]
    return scan

# CONTROL: the same scanner, built over a planted token's hash, must fire on every shape the comment above
# promises and stay silent on text without the token — so an empty sweep below can only mean "clean",
# never "the matcher stopped matching".
CONTROL = 'qzvkwjx'
control = make_scan( { len( CONTROL ): { hashlib.sha256( CONTROL.encode() ).hexdigest() } } )
for shape in ( 'see qzvkwjx here', 'Qzvkwjx', 'QZVKWJX_BIN', 'qzvkwjx/src/x.h', 'qzvkwjx@1234abc', 'QzvkwjxIndex', 'libqzvkwjxrc' ):
    if control( ( 'first line\n' + shape ).encode() ) != [ 2 ]:
        print( f'REFUSE control: the scanner did not fire on the planted shape {shape!r}' )
        sys.exit( 1 )
if control( b'qzvkwj qzvk-wjx' ):
    print( 'REFUSE control: the scanner fired on text that does not carry the planted token' )
    sys.exit( 1 )

scan = make_scan( targets )
tracked, unread_files, decks, decks_read = set(), 0, 0, 0
for raw in paths:
    p = os.fsdecode( raw )
    tracked.add( p )
    data = None
    try:
        if os.path.islink( raw ):
            data = os.readlink( raw )   # a symlink's committed content is its target text
        else:
            with open( raw, 'rb' ) as handle:
                data = handle.read()
    except OSError as exc:
        unread_files += 1
        print( 'UNREAD %s — %s' % ( shown( raw ), exc.strerror or exc.__class__.__name__ ) )
    if data is not None and b'\0' not in data:
        found = scan( data )
        if found and p in exempt and hashlib.sha256( data ).hexdigest() == exempt[ p ]:
            print( 'EXEMPT %d %s' % ( len( found ), shown( raw ) ) )
        else:
            for i in found:
                print( 'HIT %s:%d' % ( shown( raw ), i ) )
    if DECK.search( raw ):
        decks += 1
        text, why = deck_text( raw )
        if text is None:
            print( 'UNREAD %s — %s' % ( shown( raw ), why ) )
            continue
        decks_read += 1
        for i in scan( text ):
            print( 'HIT %s (extracted text):%d' % ( shown( raw ), i ) )
for p, digest in exempt.items():
    try:
        live = hashlib.sha256( open( p, 'rb' ).read() ).hexdigest() if p in tracked else None
    except OSError:
        live = None
    if live != digest:
        print( 'STALE %s' % shown( p ) )
print( 'COUNT %d %d %d %d' % ( len( paths ), unread_files, decks, decks_read ) )
print( 'END' )
try:
    sys.stdout.flush()
except OSError:
    os._exit( 1 )
PY
then
    no "arm 1b — could not write its scanner into $TMP"
fi
# run_scanner ROOT LIST TARGETS EXEMPT REPORT [BOUND] — the scanner over ROOT, its report to REPORT and stderr to
# REPORT.err, every deck read through BOUND bytes (ARM1B_TEXT_BOUND unless a control passes a smaller one). Sets
# _status. A report that cannot even be opened is a non-zero status like any other failure; the shell's own complaint
# about it stays out of the gate's output.
run_scanner(){
    ( cd "$1" && PYTHONIOENCODING=utf-8:backslashreplace python3 "$TMP/arm1b.py" "$2" "$3" "$4" "${6:-$ARM1B_TEXT_BOUND}" > "$5" 2> "$5.err" ) 2>/dev/null
    _status=$?
}
# is_count VALUE — true for a non-empty run of digits.
is_count(){ case "$1" in ''|*[!0-9]*) return 1 ;; esac; }
# judge_report REPORT STATUS DECKS — sets _verdict (clean, dirty or broken), _why, _hits (0/1), _unread and _files.
# CLEAN is reached only through POSITIVE reads of REPORT: exit 0, END as its last record, a well-formed COUNT whose
# deck total equals DECKS (this shell's own count) and whose read totals match the UNREAD records. A report that is
# missing, truncated, unreadable or inconsistent is BROKEN — never clean, never "zero findings".
judge_report(){
    local report="$1" status="$2" decks="$3" last counts unreadf pydecks readd records rc
    _verdict=broken
    _why=
    _hits=0
    _unread=0
    _files=0
    if [ "$status" -ne 0 ]; then
        _why="the scanner exited $status$( grep -m 1 '^REFUSE ' "$report" 2>/dev/null | sed 's/^REFUSE /: /' )"
        return 0
    fi
    if ! last="$( tail -n 1 "$report" 2>/dev/null )"; then
        _why="its report could not be read"
        return 0
    fi
    if [ "$last" != END ]; then
        _why="its report is incomplete (no END record)"
        return 0
    fi
    if ! counts="$( grep -m 1 '^COUNT ' "$report" 2>/dev/null )"; then
        _why="its report has no COUNT record"
        return 0
    fi
    read -r _ _files unreadf pydecks readd <<< "$counts"
    if ! is_count "$_files" || ! is_count "$unreadf" || ! is_count "$pydecks" || ! is_count "$readd" || [ "$readd" -gt "$pydecks" ]; then
        _why="its COUNT record is malformed"
        return 0
    fi
    if [ "$pydecks" -ne "$decks" ]; then
        _why="the scanner enumerated $pydecks deck(s) where this shell counted $decks"
        return 0
    fi
    records="$( grep -c '^UNREAD ' "$report" 2>/dev/null )"
    rc=$?
    if [ "$rc" -gt 1 ] || ! is_count "$records"; then
        _why="its report could not be re-read"
        return 0
    fi
    _unread=$(( unreadf + pydecks - readd ))
    if [ "$records" -ne "$_unread" ]; then
        _why="its COUNT record says $_unread unread but it carries $records UNREAD record(s)"
        return 0
    fi
    grep -q '^HIT ' "$report" 2>/dev/null
    rc=$?
    if [ "$rc" -gt 1 ]; then
        _why="its report could not be re-read"
        return 0
    fi
    if [ "$rc" -eq 0 ]; then
        _hits=1
    fi
    if [ "$_hits" -eq 1 ] || [ "$_unread" -ne 0 ]; then
        _verdict=dirty
    else
        _verdict=clean
    fi
}
# CONTROLS. Each runs the SAME count, scanner and judge as the sweep below.
_ctl=0
ctlfail(){ no "arm 1b control — $*"; _ctl=1; }
_ctlrepo="$TMP/arm1b.ctlrepo"
ctlgit(){ env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "$_ctlrepo" "$@"; }
_ctlhash="7 $( python3 -c 'import hashlib; print( hashlib.sha256( b"qzvkwjx" ).hexdigest() )' )"
# (1) END TO END. A temp repo tracks decks whose paths carry a NEWLINE, a SPACE and an UPPER-CASE extension, beside
#     a `.pdf.bak` decoy. Each deck holds the planted token only in compressed text. Two more PPTX decks pin the
#     display-order reading: `split.pptx` carries the token broken across `<a:t>` runs, on a slide and again in a
#     notes slide, and must be reported from both; `apart.pptx` carries the same two pieces in two PARAGRAPHS, which
#     no slide displays as one word, and must be read yet report nothing. All five must be counted and read. GIT_* is
#     cleared so an inherited GIT_DIR cannot redirect these calls.
{ mkdir -p "$_ctlrepo" && ctlgit init -q 2>/dev/null; } || ctlfail "(1) could not create its temp repo"
python3 - "$_ctlrepo" <<'PY' || ctlfail "(1) could not write the planted decks"
import os, sys, zipfile, zlib
root, word = sys.argv[ 1 ], b"qzvkwjx"
def pdf_bytes():
    """A one-page PDF whose text is the word, deflated so the raw bytes never spell it, with a real xref table."""
    stream = zlib.compress( b"BT /F1 18 Tf 20 40 Td (" + word + b") Tj ET" )
    objs = ( b"<</Type /Catalog /Pages 2 0 R>>", b"<</Type /Pages /Kids [3 0 R] /Count 1>>",
             b"<</Type /Page /Parent 2 0 R /MediaBox [0 0 300 100] /Contents 4 0 R /Resources <</Font <</F1 5 0 R>>>>>>",
             b"<</Length %d /Filter /FlateDecode>>\nstream\n" % len( stream ) + stream + b"\nendstream",
             b"<</Type /Font /Subtype /Type1 /BaseFont /Helvetica>>" )
    pdf, offsets = bytearray( b"%PDF-1.4\n" ), []
    for number, body in enumerate( objs, 1 ):
        offsets.append( len( pdf ) )
        pdf += b"%d 0 obj\n" % number + body + b"\nendobj\n"
    xref = len( pdf )
    pdf += b"xref\n0 %d\n0000000000 65535 f \n" % ( len( objs ) + 1 ) + b"".join( b"%010d 00000 n \n" % o for o in offsets )
    pdf += b"trailer\n<</Size %d /Root 1 0 R>>\nstartxref\n%d\n%%%%EOF\n" % ( len( objs ) + 1, xref )
    return bytes( pdf )
NS = b'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"'
def slide( *paragraphs ):
    """A slide part whose paragraphs are given as tuples of runs."""
    body = b"".join( b"<a:p>" + b"".join( b"<a:r><a:t>" + run + b"</a:t></a:r>" for run in runs ) + b"</a:p>" for runs in paragraphs )
    return b"<p:sld " + NS + b"><p:cSld><p:spTree><p:sp><p:txBody>" + body + b"</p:txBody></p:sp></p:spTree></p:cSld></p:sld>"
os.makedirs( os.path.join( root, "talks" ), exist_ok=True )
with zipfile.ZipFile( os.path.join( root, "talks", "new\nline.Pptx" ), "w", zipfile.ZIP_DEFLATED ) as deck:
    deck.writestr( "ppt/slides/slide1.xml", slide( ( word, ) ) )
with zipfile.ZipFile( os.path.join( root, "talks", "split.pptx" ), "w", zipfile.ZIP_DEFLATED ) as deck:
    deck.writestr( "ppt/slides/slide1.xml", slide( ( b"see ", word[ :3 ], word[ 3: ], b" here" ) ) )
    deck.writestr( "ppt/notesSlides/notesSlide1.xml", slide( ( b"notes", ), ( word[ :5 ], word[ 5: ] ) ) )
with zipfile.ZipFile( os.path.join( root, "talks", "apart.pptx" ), "w", zipfile.ZIP_DEFLATED ) as deck:
    deck.writestr( "ppt/slides/slide1.xml", slide( ( word[ :3 ], ), ( word[ 3: ], ) ) )
for name in ( "with space.pdf", "UPPER.PDF" ):
    with open( os.path.join( root, "talks", name ), "wb" ) as out:
        out.write( pdf_bytes() )
with open( os.path.join( root, "talks", "decoy.pdf.bak" ), "wb" ) as out:
    out.write( b"not a deck\n" )
PY
{ ctlgit add -A && ctlgit ls-files -z > "$TMP/arm1b.ctl.z"; } || ctlfail "(1) could not track the planted decks"
count_decks "$TMP/arm1b.ctl.z" || ctlfail "(1) could not read its own deck list"
_ctldecks=$_decks
run_scanner "$_ctlrepo" "$TMP/arm1b.ctl.z" "$_ctlhash" '' "$TMP/arm1b.ctl.report"
judge_report "$TMP/arm1b.ctl.report" "$_status" "$_ctldecks"
if [ "$_ctldecks" -ne 5 ] || [ "$_verdict" != dirty ] || [ "$_hits" -ne 1 ] || [ "$_unread" -ne 0 ]; then
    ctlfail "(1) planted decks: counted $_ctldecks, verdict $_verdict${_why:+ ($_why)}, $_unread unread — want 5 decks, all read, the token found"
fi
for _want in 'talks/new\x0aline.Pptx' 'talks/with space.pdf' 'talks/UPPER.PDF'; do
    grep -Fq "HIT $_want (extracted text):" "$TMP/arm1b.ctl.report" 2>/dev/null \
        || ctlfail "(1) the token in tracked deck $_want was not reported from its extracted text"
done
# The split-run deck reports the slide line (1) and the notes line (3: the slide's one paragraph, then "notes", then the
# split pair); the split-paragraph deck reports nothing.
for _want in 'HIT talks/split.pptx (extracted text):1' 'HIT talks/split.pptx (extracted text):3'; do
    grep -Fxq "$_want" "$TMP/arm1b.ctl.report" 2>/dev/null \
        || ctlfail "(1) a token split across <a:t> runs was not reported as the line that displays it (want '$_want')"
done
! grep -Fq 'HIT talks/apart.pptx' "$TMP/arm1b.ctl.report" 2>/dev/null \
    || ctlfail "(1) two paragraphs that each carry half the token were reported as if a slide displayed them as one word"
# (2) UNREADABLE INPUTS. The same list plus a junk .pdf, a junk .pptx and two tracked paths missing from disk: two
#     unread files and three unread decks. Unread decides the verdict, never "zero findings".
{ printf 'not a deck\n' > "$_ctlrepo/talks/junk.pdf" \
  && printf 'not a deck\n' > "$_ctlrepo/talks/junk.pptx" \
  && cp "$TMP/arm1b.ctl.z" "$TMP/arm1b.ctl2.z" \
  && printf 'talks/junk.pdf\0talks/junk.pptx\0talks/missing.txt\0talks/missing.pdf\0' >> "$TMP/arm1b.ctl2.z"; } \
    || ctlfail "(2) could not build its unreadable-input list"
count_decks "$TMP/arm1b.ctl2.z" || ctlfail "(2) could not read its deck list"
run_scanner "$_ctlrepo" "$TMP/arm1b.ctl2.z" "$_ctlhash" '' "$TMP/arm1b.ctl2.report"
judge_report "$TMP/arm1b.ctl2.report" "$_status" "$_decks"
if [ "$_verdict" != dirty ] || [ "$_unread" -ne 5 ]; then
    ctlfail "(2) unreadable inputs: verdict $_verdict${_why:+ ($_why)}, $_unread unread — want dirty with 5 unread"
fi
# (3) A WRITE THAT FAILS. The report's parent is a regular file, so the report cannot be opened — for root too.
printf 'not a directory\n' > "$TMP/arm1b.notadir" || ctlfail "(3) could not plant its non-directory"
run_scanner "$_ctlrepo" "$TMP/arm1b.ctl.z" "$_ctlhash" '' "$TMP/arm1b.notadir/report"
judge_report "$TMP/arm1b.notadir/report" "$_status" "$_ctldecks"
[ "$_verdict" = broken ] || ctlfail "(3) an unwritable report was judged $_verdict — want broken"
# (4) A WRITE THAT STOPS SHORT. Control (1)'s report without its last record, judged with exit status 0, as if the
#     failure had left no other trace.
sed '$d' "$TMP/arm1b.ctl.report" > "$TMP/arm1b.ctl.cut" || ctlfail "(4) could not cut its report"
judge_report "$TMP/arm1b.ctl.cut" 0 "$_ctldecks"
[ "$_verdict" = broken ] || ctlfail "(4) a report missing its END record was judged $_verdict — want broken"
# (5) A DECK THE SCANNER NEVER SAW. Control (1)'s complete report, judged against one more deck than it enumerated.
judge_report "$TMP/arm1b.ctl.report" 0 "$(( _ctldecks + 1 ))"
[ "$_verdict" = broken ] || ctlfail "(5) a deck-count mismatch was judged $_verdict — want broken"
# (6) THE BOUND. A PDF whose text and a PPTX whose declared slide part both exceed a 64-byte bound, and carry no token.
#     Under that bound both are UNREAD, each naming the bound, and the verdict is dirty on unread alone; under the real
#     bound the same two decks are read clean. So the bound, not the content, is what refused them, and refusal is
#     never a pass.
python3 - "$_ctlrepo" <<'PY' || ctlfail "(6) could not write its oversized decks"
import os, sys, zipfile
root = sys.argv[ 1 ]
NS = b'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"'
with zipfile.ZipFile( os.path.join( root, "talks", "big.pptx" ), "w", zipfile.ZIP_DEFLATED ) as deck:
    deck.writestr( "ppt/slides/slide1.xml", b"<p:sld " + NS + b"><a:p><a:r><a:t>" + b"abcdefgh " * 12 + b"</a:t></a:r></a:p></p:sld>" )
stream = b"BT /F1 8 Tf 10 40 Td (" + b"abcdefgh " * 12 + b") Tj ET"
objs = ( b"<</Type /Catalog /Pages 2 0 R>>", b"<</Type /Pages /Kids [3 0 R] /Count 1>>",
         b"<</Type /Page /Parent 2 0 R /MediaBox [0 0 900 100] /Contents 4 0 R /Resources <</Font <</F1 5 0 R>>>>>>",
         b"<</Length %d>>\nstream\n" % len( stream ) + stream + b"\nendstream",
         b"<</Type /Font /Subtype /Type1 /BaseFont /Helvetica>>" )
pdf, offsets = bytearray( b"%PDF-1.4\n" ), []
for number, body in enumerate( objs, 1 ):
    offsets.append( len( pdf ) )
    pdf += b"%d 0 obj\n" % number + body + b"\nendobj\n"
xref = len( pdf )
pdf += b"xref\n0 %d\n0000000000 65535 f \n" % ( len( objs ) + 1 ) + b"".join( b"%010d 00000 n \n" % o for o in offsets )
pdf += b"trailer\n<</Size %d /Root 1 0 R>>\nstartxref\n%d\n%%%%EOF\n" % ( len( objs ) + 1, xref )
with open( os.path.join( root, "talks", "big.pdf" ), "wb" ) as out:
    out.write( bytes( pdf ) )
PY
printf 'talks/big.pdf\0talks/big.pptx\0' > "$TMP/arm1b.ctl6.z" || ctlfail "(6) could not write its deck list"
count_decks "$TMP/arm1b.ctl6.z" || ctlfail "(6) could not read its deck list"
run_scanner "$_ctlrepo" "$TMP/arm1b.ctl6.z" "$_ctlhash" '' "$TMP/arm1b.ctl6.report" 64
judge_report "$TMP/arm1b.ctl6.report" "$_status" "$_decks"
if [ "$_verdict" != dirty ] || [ "$_unread" -ne 2 ] || [ "$_hits" -ne 0 ] \
   || [ "$( grep -c '^UNREAD .*bound' "$TMP/arm1b.ctl6.report" 2>/dev/null )" != 2 ]; then
    ctlfail "(6) two decks over a 64-byte bound: verdict $_verdict${_why:+ ($_why)}, $_unread unread, hits $_hits — want dirty, both UNREAD naming the bound"
fi
run_scanner "$_ctlrepo" "$TMP/arm1b.ctl6.z" "$_ctlhash" '' "$TMP/arm1b.ctl6b.report"
judge_report "$TMP/arm1b.ctl6b.report" "$_status" "$_decks"
[ "$_verdict" = clean ] || ctlfail "(6) the same two decks under the real bound were judged $_verdict${_why:+ ($_why)} — want clean"
[ "$_ctl" -eq 0 ] && ok "arm 1b control — planted decks with a newline, a space and an upper-case extension are all read and scanned, a token split across <a:t> runs is caught; unreadable inputs, an unwritable report, a truncated report, a deck-count mismatch and a deck over the text bound each fail"
# THE SWEEP. The deck count comes from this shell, the scan and its accounting from the scanner, and the verdict
# only from a report the judge read completely.
if count_decks "$TMP/tracked.z"; then
    run_scanner "$ROOT" "$TMP/tracked.z" "$PRERELEASE_NAME_SHA256" "$PRERELEASE_EXEMPT_SHA256" "$TMP/arm1b"
    judge_report "$TMP/arm1b" "$_status" "$_decks"
else
    _verdict=broken
    _why="the tracked list could not be read"
fi
case "$_verdict" in
  clean)
    ok "arm 1b — no private pre-release name in all $_files tracked file(s), including the text of all $_decks deck(s)$( awk '/^EXEMPT /{ printf " (%s line(s) in byte-frozen %s exempt by content hash)", $2, $3 }' "$TMP/arm1b" 2>/dev/null )" ;;
  dirty)
    if [ "$_hits" -eq 1 ]; then
        no "arm 1b — private pre-release name on $( grep -c '^HIT ' "$TMP/arm1b" ) line(s); locations only, the text is not echoed:"
        grep '^HIT ' "$TMP/arm1b" | cut -c5- | sed 's/^/          /'
    fi
    if [ "$_unread" -ne 0 ]; then
        no "arm 1b — $_unread input(s) NOT scanned; a file this arm could not read is not a file it cleared:"
        grep '^UNREAD ' "$TMP/arm1b" | cut -c8- | sed 's/^/          /'
    fi ;;
  *)
    no "arm 1b — no verdict, which is not a pass: $_why"
    [ -s "$TMP/arm1b.err" ] && tail -n 3 "$TMP/arm1b.err" | sed 's/^/          /' ;;
esac
sed -n 's/^STALE //p' "$TMP/arm1b" 2>/dev/null | while IFS= read -r _path; do
    printf 'NOTE: arm 1b — the content-hash exemption for %s no longer matches its bytes; it exempts nothing and can be deleted\n' "$_path"
done

# ── arm 2: absolute home-directory paths ──────────────────────────────────────────────────────────
hits="$( sweep '/Users/' || true )"
if [ -n "$hits" ]; then
    no "arm 2 — absolute /Users/ path in $( printf '%s\n' "$hits" | wc -l | tr -d ' ' ) place(s):"
    printf '%s\n' "$hits" | sed 's/^/          /'
else
    ok "arm 2 — no absolute /Users/ paths"
fi

# arm 2b — THE BINARY POPULATION. Arm 2 sweeps TEXT. Three tracked files are containers it cannot
# read, and two of them are rebuilt by a generator that runs on a contributor's machine — which is
# exactly the path this class of leak travels:
#
#     present/ripwire-showcase.pdf      built from deck5_ripwire_build.js on someone's machine
#     present/ripwire-showcase.pptx     same
#     docs/assets/showcase-preview.png  a render of those slides
#
# The mechanism is upstream of all of them: ripwire ECHOES ITS ROOT verbatim into the XML header
# (`root="/Users/…"`, 45 bytes and ~18 est_tokens), so any artifact built by running it with an
# absolute root carries the operator's filesystem layout. Three separate instances of this landed or
# nearly landed in one day — the README figures, the head-to-head bench harness, and this.
#
# This arm EXTRACTS text and greps that, rather than grepping the container. A container scan is
# shape 1 from CONTRIBUTING §2: a check examining the wrong population. Note the honest limit — for
# the PNG there is no cheap extraction, because a leak rendered as PIXELS is invisible to every text
# tool. That file's control is the crop, not this gate, and saying so here is the disclosure.
# The classes swept, kept in ONE table so the scan and its control cannot disagree about what is
# checked — the same discipline docscommandscheck arm (E) uses. Fields are ~-separated because
# '|' is the ERE alternation character inside every pattern here and cannot also be the separator. Widened 2026-09-08: this arm decoded
# the binaries correctly but greped ONE class, while the sibling capture path had six. The deck is
# built by running the tool on someone's machine, the same provenance as the capture that leaked 21
# internal headings to public main, and it is the one published artifact where a leak is invisible to
# every text tool in the suite. Measured clean on all five at the time of widening.
DECK_CLASSES='home path~(/Users|/home)/[A-Za-z0-9_.-]+
temp path~(/var/folders|/tmp)/[A-Za-z0-9_.-]+
internal doc name~(PLAN_|DESIGN_|KICKOFF_|HANDOFF_|IDEAS_|RESEARCH_|NEXT_SESSION)[A-Za-z0-9_.-]*
internal doc heading~p="NOTES\.md" id="[^"]
address~[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
DECK_CLASS_PROBES='home path~(/Users|/home)/[A-Za-z0-9_.-]+~root "/Users/someone/x"
temp path~(/var/folders|/tmp)/[A-Za-z0-9_.-]+~cache /var/folders/ab/cd
internal doc name~(PLAN_|DESIGN_|KICKOFF_|HANDOFF_|IDEAS_|RESEARCH_|NEXT_SESSION)[A-Za-z0-9_.-]*~see PLAN_ROUND_X.md
internal doc heading~p="NOTES\.md" id="[^"]~<sym p="NOTES.md" id="12. Open questions"/>
address~[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}~contact someone@example.com'

for _bin in present/ripwire-showcase.pdf present/ripwire-showcase.pptx; do
    [ -f "$ROOT/$_bin" ] || continue
    case "$_bin" in
      *.pdf)  if command -v pdftotext >/dev/null 2>&1; then _txt="$( pdftotext "$ROOT/$_bin" - 2>/dev/null )"
              else printf 'SKIP: arm 2b — pdftotext absent, %s not extractable here (NOT a pass)\n' "$_bin"; continue; fi ;;
      *.pptx) if command -v unzip >/dev/null 2>&1; then _txt="$( unzip -p "$ROOT/$_bin" 'ppt/slides/*.xml' 2>/dev/null )"
              else printf 'SKIP: arm 2b — unzip absent, %s not extractable here (NOT a pass)\n' "$_bin"; continue; fi ;;
    esac
    _dirty=0
    while IFS='~' read -r _cls _pat; do
        [ -n "$_cls" ] || continue
        if printf '%s' "$_txt" | grep -Eq "$_pat"; then
            printf 'FAIL: arm 2b — %s carries %s in its EXTRACTED text:\n' "$_bin" "$_cls"
            printf '%s' "$_txt" | grep -oE "$_pat" | sort -u | head -8 | sed 's/^/        /'
            fail=1; _dirty=1
        fi
    done <<CLASSES
$DECK_CLASSES
CLASSES
    [ "$_dirty" -eq 0 ] && printf 'PASS: arm 2b — %s extracts clean on every scrub class (%s)\n' \
        "$_bin" "home path, temp path, internal doc name, internal doc heading, address"
done
# CONTROL: every class must be able to SEE its own leak. Feed each a planted string and require its
# grep to fire, so an extraction that silently returns nothing cannot read as agreement — and so a
# class that can never match cannot pad the PASS line above with a promise it does not keep.
_ctlfail=0
while IFS='~' read -r _cls _pat _probe; do
    [ -n "$_cls" ] || continue
    printf '%s' "$_probe" | grep -Eq "$_pat" || { printf 'FAIL: arm 2b control — the %s grep is inert\n' "$_cls"; _ctlfail=1; fail=1; }
done <<PROBES
$DECK_CLASS_PROBES
PROBES
[ "$_ctlfail" -eq 0 ] && printf 'PASS: arm 2b mutation control — every scrub class fires on its planted leak\n'

# ── arm 3: audit-round coordinates in EMITTED strings and shipped markdown ────────────────────────
# Source COMMENTS are exempt on purpose: they are internal engineering notes that a user never sees.
# What a user sees is (a) string literals the binary prints and (b) the markdown that ships. Only
# those two are checked, so this arm stays honest instead of drowning in comment noise.
# The owner-accepted one-off that used to sit here (the external-tool-survey PLAN, committed at
# 7bcd8b0 as a public roadmap) was culled: its surveyed tools are folded into docs/LINEAGE.md §3b
# and the two lessons it identified as owed became §3a rows. Its own comment said to remove the
# exemption if the file was ever culled, so this arm now has NO exemptions — every
# internal-pattern filename fails, with no exceptions to keep in sync.
ONEOFF_ACCEPTED=''
python3 - "$TMP/tracked.z" "$ONEOFF_ACCEPTED" > "$TMP/arm3" <<'PY'
import re, sys
paths = open(sys.argv[1], 'rb').read().split(b'\0')
oneoff = sys.argv[2]
coord = re.compile(r'§A|§B[0-9]|§P[0-9]|V[0-9]-[0-9]|W[0-9]|r[0-9][0-9]-')
strlit = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
for raw in paths:
    if not raw:
        continue
    p = raw.decode('utf-8', 'surrogateescape')
    if p == oneoff:
        continue
    # emitted strings: OUR source only. third_party/ is upstream code we do not author, and the
    # test fixtures deliberately carry adversarial literals (base64 blobs collide with W<d>).
    is_src = p.startswith('src/') and p.endswith(('.h', '.cpp', '.inl', '.hpp'))
    is_md = p.endswith('.md')
    if not (is_src or is_md):
        continue
    try:
        lines = open(p, encoding='utf-8', errors='replace').read().split('\n')
    except OSError:
        continue
    for i, line in enumerate(lines, 1):
        if is_md:
            if coord.search(line):
                print(f'{p}:{i}:{line.strip()[:140]}')
            continue
        if line.lstrip().startswith('//'):
            continue
        for m in strlit.finditer(line):
            if coord.search(m.group(1)):
                print(f'{p}:{i}:{m.group(0)[:140]}')
PY
if [ -s "$TMP/arm3" ]; then
    no "arm 3 — audit-round coordinate in an emitted string or shipped doc:"
    sed 's/^/          /' "$TMP/arm3"
else
    ok "arm 3 — no audit-round coordinates in emitted strings or shipped docs"
fi

# ── arm 4: credential-shaped literals outside the redaction fixtures ──────────────────────────────
# --redact cannot be tested without credential-shaped strings to redact, so a fixed, enumerated set
# of files carries synthetic ones on purpose (see test/README.md). Anywhere ELSE is a leak.
SECRET_RE='AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{32,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
# bench/recalleval/snapshot.mdpack is a hash-pinned, byte-frozen copy of tracked *.md (including
# test/README.md above) — every line inside it exists at a real path this sweep already scans with
# its own per-path ruling, so scanning the copy can only double-report what the original already
# answers for. The pack is regenerated only by make_snapshot.py --freeze and integrity-checked by
# recallevalcheck's check #0, so nothing can hide in it that is not also at its source path.
SECRET_OK='^(src/redact\.h|test/README\.md|test/redactfix/|test/redactcheck\.sh|test/jsonredactcheck\.sh|test/mcpredactcheck\.sh|test/bodydialectcheck\.sh|test/w3fixlegendcheck\.sh|test/editroundtripcheck\.sh|bench/recalleval/snapshot\.mdpack)'
hits="$( sweep "$SECRET_RE" | grep -vE "$SECRET_OK" || true )"
if [ -n "$hits" ]; then
    no "arm 4 — credential-shaped literal outside the sanctioned redaction fixtures:"
    printf '%s\n' "$hits" | sed 's/^/          /'
else
    ok "arm 4 — credential-shaped literals confined to the redaction fixtures"
fi

# ── arm 5: personal identifiers outside LICENSE / AUTHORS ─────────────────────────────────────────
# The SPDX copyright notice is the one sanctioned form of the author's name in source: `Copyright
# <year> <name>` on its own comment line. Everything else — machine usernames, account handles,
# email addresses, "Created by … on <date>" residue from the origin tree — is a leak.
# A commit identity being visible in git history is not a licence to bake it into the FILES: a clone's
# tree is read by people and by agents that never look at `git log`, and `--owners`/`--pr-context` put
# real author addresses into any recorded output. The generators scrub them (docs/docs_commands_build.py,
# test/showcase_capture.py); this arm is the statement that the scrub ran.
# Concatenated on purpose: the tracked tree must not itself SPELL the identifiers this arm hunts
# (the detector was the last tracked file carrying them). The regex is byte-identical after joining.
PERSON_RE='Brew''ster|brew''ster|qga''mes|davidbrew''ster|bare''foot\.ski|quaternion''games'
hits="$( sweep "$PERSON_RE" \
         | grep -vE '^(LICENSE|AUTHORS|THIRD_PARTY\.md|test/ripwirepubliccheck\.sh):' \
         | grep -vE ':[0-9]+:[[:space:]]*(//|#)?[[:space:]]*Copyright [0-9]{4} David Brewster[[:space:]]*$' \
         || true )"
if [ -n "$hits" ]; then
    no "arm 5 — personal identifier outside LICENSE/AUTHORS and the SPDX copyright line:"
    printf '%s\n' "$hits" | sed 's/^/          /'
else
    ok "arm 5 — personal identifiers confined to LICENSE and SPDX copyright lines"
fi

# ── arm 5b: generic email-shape check — PERSON_RE above only catches NAMES it already knows; this
# catches ANY real-looking address, named or not. The discriminator is IMPORTED from
# docs/docs_commands_build.py's find_address() (same idiom as test/docscommandscheck.sh's arm E) so
# this does not re-spell the symbol@file.ext-vs-real-address rule by hand — ripwire's own community
# labels (`str@ingest.cpp:887`, `AGENTS@AGENTS.md:1:0`) are that exact shape and must not trip this.
#
# V3 MED-4: the exemption used to be `test/[^/]+\.(sh|py)$` — wholesale, by FILE. That was both too
# WIDE (any address in a top-level test/*.sh|py file was waved through, real or planted) and too
# NARROW (a fixture under test/sub/foo.sh was not exempt at all). It is replaced below by an
# allowlist keyed on the ADDRESS itself: a hit is exempt only if its domain is one of the synthetic
# domains this repo's fixtures actually construct, wherever in the tree it appears. Anything that
# is not a synthetic-domain hit gets its own explicit (path, address) exemption instead — see PAIR
# below — so nothing is waved through just for living in test/.
#
# PATH_ALLOW, enumerated by scanning the whole committed tree first (see the commit message for the
# full list this was built from):
#   third_party/**                    — vendored upstream code; its own authors' real copyright/
#                                        LICENSE emails are correct and required, not a leak of ours.
#   bench/cppbench/dataset.lock       — a benchmark dataset of real historical public open-source
#                                        commit messages (external corpus, not this repo's identity).
#   docs/docs_commands_build.py       — the generator's OWN source, describing its `symbol@basename.ext`
#                                        placeholder shape in comments (a literal ".ext", not a real TLD,
#                                        so find_address()'s TLD check does not itself filter it out).
#   src/infra/timsort.hpp             — the ONE vendored upstream file that deliberately does not live
#                                        under third_party/. src/infra/ is the portable layer that gets
#                                        copied wholesale into another tree (test/infraportcheck.sh is
#                                        the boundary that keeps it copyable), and this sorter is part
#                                        of what that layer offers, so it travels with it. Its MIT
#                                        notice names its upstream authors; the licence REQUIRES that
#                                        notice be kept, so the addresses are not removable and are not
#                                        ours. Exempted by EXACT PATH, never by directory: src/ at large
#                                        stays covered, and a second vendored file here would have to
#                                        earn its own row and say why it is not in third_party/.
#
# SYNTHETIC_DOMAINS — the exact set of throwaway domains found in test fixtures across the whole
# committed tree (`git config user.email …@x.com`/`@t.com`/`@test.com`/`example.com`/
# `example.invalid`) to exercise --owners/--pr-context/churn/merge-scout etc. test/README.md
# documents the same synthetic-fixture carve-out for arm 4's credential literals.
#
# PAIR_ALLOW — the `symbol@file.ext` / `sym@file.ext` community-label placeholder shape (a literal
# ".ext", not a synthetic domain) that two test fixtures use in prose to document ripwire's own
# `symbol@basename.ext:line:col` label format; each is exempted by its exact (path, address) pair,
# not by file, so nothing else in those files is waved through.
#
# V4 MED-1 / LOW-1: two more gaps closed. (a) the scan used to take only the FIRST address per
# LINE via find_address(line) then `continue` the whole line on a synthetic-domain match — a
# planted line with a synthetic address FOLLOWED by a real one on the same line
# (`git config user.email a@x.com  # contact: real.person@corp.io`) passed clean. It now walks
# every address on the line. (b) the synthetic-domain exemption used to apply tree-wide, but every
# legitimate synthetic-domain hit in this repo lives under test/ or bench/ (measured: 39 files,
# zero elsewhere) — it is now conjoined with a path check, so the same synthetic address in
# README/src/docs is treated as a leak, not a fixture.
PATH_ALLOW='^(third_party/|bench/cppbench/dataset\.lock$|docs/docs_commands_build\.py$|src/infra/timsort\.hpp$)'
python3 - "$TMP/tracked.z" "$ROOT" "$PATH_ALLOW" > "$TMP/arm5b" 2> "$TMP/arm5b.err" <<'PY'
import os, re, sys
paths = [p.decode('utf-8', 'surrogateescape')
         for p in open(sys.argv[1], 'rb').read().split(b'\0') if p]
ROOT = sys.argv[2]
path_allow = re.compile(sys.argv[3])
SYNTHETIC_DOMAINS = frozenset( ( 'x.com', 'example.com', 'example.invalid', 't.com', 'test.com' ) )
PAIR_ALLOW = frozenset( (
    ( 'test/docscommandscheck.sh', 'sym@file.ext' ),
    ( 'test/docscommandscheck.sh', 'symbol@file.ext' ),
    ( 'test/showcase_capture.py', 'symbol@file.ext' ),
) )

sys.path.insert(0, os.path.join(ROOT, 'docs'))
try:
    import docs_commands_build as gen
except ImportError as exc:
    print(f'REFUSE import error: {exc}')
    sys.exit(1)
if not hasattr(gen, 'find_address'):
    print('REFUSE docs_commands_build has no find_address attribute')
    sys.exit(1)
find_address = gen.find_address

# Live positive control — not merely a callable-presence check: PROVES the returned function still
# recognises an email-shaped address, so an empty scan result below can only mean "genuinely clean",
# never "the scanner silently stopped matching anything" (a crash — or a renamed/no-op function —
# previously made this arm pass while a planted address in the committed tree went undetected).
CONTROL = 'definitely-not-a-real-person@example-control-domain.test'
if not find_address(f'contact: {CONTROL}'):
    print(f'REFUSE positive control failed: find_address() did not match a known-good address ({CONTROL})')
    sys.exit(1)

SELF = 'test/ripwirepubliccheck.sh'
for p in paths:
    if p == SELF or path_allow.match(p):
        continue
    try:
        data = open(p, 'rb').read()
    except OSError:
        continue
    if b'\0' in data:
        continue   # binary, skip
    text = data.decode('utf-8', 'replace')
    for i, line in enumerate(text.split('\n'), 1):
        # Walk every address on the line — not just the first — so a synthetic-domain hit early
        # on the line cannot shield a real address later on the SAME line (e.g. a planted
        # `git config user.email a@x.com  # contact: real.person@corp.io`).
        pos = 0
        while True:
            m = find_address(line[pos:])
            if not m:
                break
            addr = m.group(0)
            pos += m.end()
            domain = addr.split('@', 1)[1].lower() if '@' in addr else ''
            # The synthetic-domain exemption is scoped to test/ and bench/ — every legitimate
            # synthetic-domain hit in this tree lives under one of those two dirs; the same
            # address in README/src/docs is not a fixture, it is a leak.
            if domain in SYNTHETIC_DOMAINS and p.startswith(('test/', 'bench/')):
                continue
            if (p, addr) in PAIR_ALLOW:
                continue
            print(f'{p}:{i}: {addr}')
PY
py_status=$?
if grep -q '^REFUSE' "$TMP/arm5b"; then
    no "arm 5b — $( grep '^REFUSE' "$TMP/arm5b" )"
elif [ "$py_status" -ne 0 ]; then
    no "arm 5b — scanner crashed (python exit $py_status): $( tail -5 "$TMP/arm5b.err" | tr '\n' ' ' )"
elif [ -s "$TMP/arm5b" ]; then
    no "arm 5b — email-shaped address outside the allowlisted vendored/benchmark paths and synthetic test domains:"
    sed 's/^/          /' "$TMP/arm5b"
else
    ok "arm 5b — no email-shaped addresses outside vendored code, benchmark data and synthetic test domains"
fi

# ── arm 6: internal-pattern filenames, and docs/ index coverage ───────────────────────────────────
INTERNAL_NAME='(^|/)(PLAN[._]|AUDIT|NEXT_SESSION|KICKOFF_|HANDOFF_|IDEAS_|REPORT_|DESIGN_|RESEARCH_)'
# No exemptions (see arm 3's note): every internal-pattern filename in the tree fails this arm.
badnames="$( tr '\0' '\n' < "$TMP/tracked.z" | grep -E "$INTERNAL_NAME" || true )"
if [ -n "$badnames" ]; then
    no "arm 6a — internal-pattern filename committed (pattern $INTERNAL_NAME):"
    printf '%s\n' "$badnames" | sed 's/^/          /'
else
    ok "arm 6a — no internal-pattern filenames in the committed tree"
fi

docfiles="$( tr '\0' '\n' < "$TMP/tracked.z" | grep '^docs/' || true )"
if [ -z "$docfiles" ]; then
    # TODO-ARM (deliberate, and it fails the moment it stops being a TODO): docs/ is written by the
    # documentation lane. While docs/ is empty there is no index to check, so this arm reports and
    # passes. As soon as ANY file is committed under docs/, the else-branch below gates it — there
    # is no configuration in which docs/ ships unindexed.
    ok "arm 6b — docs/ is empty (index arm arms itself as soon as docs/ is populated)"
elif ! printf '%s\n' "$docfiles" | grep -qx 'docs/README.md'; then
    no "arm 6b — docs/ has $( printf '%s\n' "$docfiles" | wc -l | tr -d ' ' ) file(s) but no docs/README.md index"
else
    missing=""
    for d in $docfiles; do
        [ "$d" = "docs/README.md" ] && continue
        base="${d#docs/}"
        # a file counts as indexed if named directly OR if an ancestor directory is indexed with a
        # trailing slash (e.g. `captures/` covers dated capture files without per-regeneration churn)
        covered=0
        grep -Fq "$base" docs/README.md && covered=1
        dir="${base%/*}"
        while [ "$covered" = 0 ] && [ "$dir" != "$base" ] && [ -n "$dir" ]; do
            grep -Fq "${dir}/" docs/README.md && covered=1
            case "$dir" in */*) dir="${dir%/*}" ;; *) break ;; esac
        done
        [ "$covered" = 1 ] || missing="$missing$d
"
    done
    if [ -n "$missing" ]; then
        no "arm 6b — file(s) under docs/ not listed in docs/README.md:"
        printf '%s' "$missing" | sed 's/^/          /'
    else
        ok "arm 6b — every file under docs/ is listed in docs/README.md"
    fi
fi

# ── arm 7: include closure ────────────────────────────────────────────────────────────────────────
# Every quoted #include must resolve to a file inside the repo. Resolution mirrors the compiler:
# relative to the including file first, then the project's include roots. A build-time include root
# that is NOT in the repo (a system path, an absolute path, the private tree) is exactly the leak
# this arm exists to catch, so unresolved is a FAIL, not a skip.
python3 - "$TMP/tracked.z" > "$TMP/arm7" <<'PY'
import os, re, sys
paths = [p.decode('utf-8', 'surrogateescape')
         for p in open(sys.argv[1], 'rb').read().split(b'\0') if p]
tracked = set(paths)
# The include roots the compiler is actually handed — our own targets' first, then the ones CMake
# passes the vendored dependency targets. A vendored header saying #include "tree_sitter/api.h" is
# self-contained (that header IS in this repo); arm 7 just has to model the same roots the build
# does, or it reports a closure break that no compiler would ever see.
#
# Note what this deliberately does NOT do: exempt third_party/deps/ from the arm. Vendored code is
# where an escape would be easiest to miss, so it stays swept — only the root list grows. And the
# roots are ENUMERATED, not globbed off disk, so pruning a dependency too far still fails the arm
# instead of quietly shrinking the search.
_deps = 'third_party/deps'
_grammars = ('bash', 'c', 'cpp', 'csharp', 'cuda', 'dart', 'elixir', 'go', 'java', 'javascript', 'json',
             'kotlin', 'objc', 'python', 'ruby', 'rust', 'swift', 'toml', 'yaml')
roots = (['src', 'src/infra', 'third_party', '']                        # our targets
         + [f'{_deps}/tree_sitter/lib/include']                         # PUBLIC, given to every target
         + [f'{_deps}/tree_sitter/lib/src', f'{_deps}/tree_sitter/lib/src/wasm']   # tree-sitter PRIVATE
         + [f'{_deps}/{g}/src' for g in _grammars]                      # add_ts_grammar(): PRIVATE ${_src}
         + [f'{_deps}/ts_typescript/typescript/src', f'{_deps}/ts_typescript/tsx/src']  # add_ts_object()
         + [f'{_deps}/doctest', f'{_deps}/doctest/doctest/parts'])      # doctest INTERFACE + dev root
inc = re.compile(r'^\s*#\s*include\s*"([^"]+)"')
# Generated headers: produced into the build dir by CMake, never committed. Named, not pattern-matched.
generated = {'version.h', 'embedded_queries.h'}
for p in paths:
    if not p.endswith(('.h', '.hpp', '.inl', '.cpp', '.c', '.cc')):
        continue
    try:
        lines = open(p, encoding='utf-8', errors='replace').read().split('\n')
    except OSError:
        continue
    here = os.path.dirname(p)
    for i, line in enumerate(lines, 1):
        m = inc.match(line)
        if not m:
            continue
        target = m.group(1)
        if 'canyonraid' in target.lower():
            print(f'{p}:{i}: include path names the private tree: {target}')
            continue
        if os.path.basename(target) in generated:
            continue
        cands = [os.path.normpath(os.path.join(here, target))]
        cands += [os.path.normpath(os.path.join(r, target)) if r else os.path.normpath(target)
                  for r in roots]
        if not any(c in tracked for c in cands):
            print(f'{p}:{i}: quoted include does not resolve inside the repo: {target}')
PY
if [ -s "$TMP/arm7" ]; then
    no "arm 7 — include closure is not self-contained:"
    sed 's/^/          /' "$TMP/arm7"
else
    ok "arm 7 — every quoted #include resolves inside the repo"
fi

# ── arm 8: no dangling reference to a culled internal-pattern .md name ────────────────────────────
# Arm 6a catches the internal doc ITSELF being committed; this arm catches every OTHER tracked file
# still POINTING at one after it was culled — a comment, a README line, a data file's prose field
# citing "PLAN_x.md" or "SPEC.md" when no such file ships in this tree. A name that resolves to a
# real shipped file (basename match, anywhere in the tree — docs move) is not a violation.
#
# EXEMPT (path, NAME) PAIRS — not whole files. A whole-file exemption hides a NEW dangling reference
# planted anywhere else in an exempted file forever (an unrelated PLAN_/SPEC-shaped name landing in
# test/docmentioncheck.sh, say, would sail through undetected); pinning the exact name each file is
# known to legitimately carry keeps that file's OTHER lines covered.
#   test/docmentioncheck.sh    : DESIGN_widgetTotals.md — a SYNTHETIC fixture name the gate creates
#                                 and scores at runtime (doc-mention surfacing test), never a citation.
#   test/historyoraclecheck.sh : PLAN_relief.md — a SYNTHETIC fixture doc the gate writes into its own
#                                 scratch git repo (chosen to look like an internal doc on purpose, to
#                                 prove doc-drift/whereis behave the same on a PLAN_-shaped filename),
#                                 never a citation of a real file.
#   bench/locbench/results/{r1_anchorhop,r1cpp_anchorhop}/*_candidate_implementation.patch : SPEC.md —
#                                 archived historical git diffs of a past experiment. Their hunks were
#                                 checked and carry exactly one internal-pattern name each (SPEC.md);
#                                 rewriting patch text would falsify the historical record, and the
#                                 patch is already unappliable in this tree regardless (it patches a
#                                 file — SPEC.md — that was never exported here). The SAME patch also
#                                 carries the BARE "SPEC §" shape (no ".md") that the second pattern
#                                 below catches, for the same never-rewrite-history reason.
#   RECORDED-RUN pairs (added when PLAN.md was culled and arm 8's pattern widened to catch a bare
#                       "PLAN.md" citation, not only "PLAN_x.md"): docs/captures/*.md and
#                       docs/COMMANDS.md's sample blocks are VERBATIM recordings of real runs made
#                       while PLAN.md still shipped, and bench/recalleval/snapshot.mdpack is a frozen
#                       corpus. Each contains PLAN.md only as a path INSIDE recorded tool output.
#                       Editing them would falsify the recording — the same never-rewrite-a-record
#                       rationale as the archived patches above. Self-limiting: a capture regenerated
#                       after the cull cannot contain the row, so this list does not grow.
ARM8_EXEMPT_PAIRS='test/docmentioncheck.sh|DESIGN_widgetTotals.md
bench/recalleval/snapshot.mdpack|PLAN.md
docs/COMMANDS.md|PLAN.md
docs/captures/COMMANDS_showcase_2026-08-10.md|PLAN.md
docs/captures/COMMANDS_showcase_2026-08-14.md|PLAN.md
docs/captures/COMMANDS_showcase_2026-08-15.md|PLAN.md
docs/captures/COMMANDS_showcase_2026-08-20.md|PLAN.md
docs/captures/COMMANDS_showcase_2026-08-21.md|PLAN.md
docs/captures/COMMANDS_showcase_2026-08-22.md|PLAN.md
test/historyoraclecheck.sh|PLAN_relief.md
bench/locbench/results/r1_anchorhop/r1_candidate_implementation.patch|SPEC.md
bench/locbench/results/r1cpp_anchorhop/r1cpp_candidate_implementation.patch|SPEC.md
bench/locbench/results/r1cpp_anchorhop/r1cpp_candidate_implementation.patch|SPEC §'
# A QUOTED heredoc delimiter ('PY') is deliberate: an unquoted one lets the shell expand `$vars` AND
# run backtick/`$()` command substitution over the ENTIRE body, including python source comments —
# this file's own "mirrors the main sweep's `grep -I`" comment below would otherwise get executed as
# a shell command mid-heredoc (it was, until this was caught: a bare `grep -I` with no pattern/file
# prints its usage banner to stderr). The exempt pairs are passed as an argv string instead, so no
# shell expansion touches the python source at all.
python3 - "$TMP/tracked.z" "$ARM8_EXEMPT_PAIRS" > "$TMP/arm8" <<'PY'
import os, re, sys
paths = [p.decode('utf-8', 'surrogateescape')
         for p in open(sys.argv[1], 'rb').read().split(b'\0') if p]
tracked_basenames = {os.path.basename(p) for p in paths}
SELF = 'test/ripwirepubliccheck.sh'   # this file's own arm 8 source names the pattern literally
exempt_pairs = set()
for line in sys.argv[2].splitlines():
    line = line.strip()
    if not line:
        continue
    path, name = line.split('|', 1)
    exempt_pairs.add((path, name))
# (1) NAMED-FILE shape: a citation of a specific culled .md filename (PLAN_x.md, SPEC.md, ...).
pat_named = re.compile(r'\b(?:PLAN|AUDIT|DESIGN_|RESEARCH_|NEXT_SESSION|KICKOFF_|HANDOFF_|IDEAS_|REPORT_|SPEC)[A-Za-z0-9_.-]*\.md\b')
# (2) BARE-NAME shape: no ".md" at all, e.g. "RESEARCH §2d", "PLAN §Execution", "SPEC §6/§8" — the 19
# residual dangling citations V3 found (pattern_named requires the ".md" suffix, so it silently missed
# these). Requiring the DOC WORD immediately before "§" is what keeps this narrow: a bare round label
# like "§P8"/"§A6a"/"§B12" with NO doc name in front is NOT internal-pattern-shaped and stays exempt by
# construction (nothing in this pattern can match it), and "field-notes" is included because it is the
# other never-shipped internal doc name this tree used to cite the same way (see git history: the sibling
# fix that cleared the first wave of these named it explicitly).
pat_bare = re.compile(r'\b(?:PLAN|SPEC|RESEARCH|DESIGN|AUDIT|IDEAS|HANDOFF|KICKOFF|NEXT_SESSION|field-notes)\s*§')
# V4 LOW-2: pat_bare is matched per LINE, so a citation split across a comment-continuation —
# "// see RESEARCH" then "// §4 for the rationale" — never appears in either single line and is
# invisible. pat_named cannot have the same gap: its charclass ([A-Za-z0-9_.-]*) contains no
# whitespace, so a real ".md" filename can never itself span a line break.
#
# Fix: for each line, ALSO build a 2-line joined copy with the next line's comment leader (//, #,
# *) stripped and a single space substituted for the join, then scan that copy too — but only
# report a match whose span actually CROSSES the join point (starts before the boundary, ends at
# or after it). Matches entirely inside line i are already caught by the single-line pass above;
# without this filter they would be reported twice. Reported at the FIRST line of the pair, since
# that is where a reader would look to find the citation.
comment_cont_re = re.compile(r'^[ \t]*(?://|#|\*)[ \t]*')
for p in paths:
    if p == SELF:
        continue
    try:
        data = open(p, 'rb').read()
    except OSError:
        continue
    if b'\0' in data:
        continue   # binary, skip (mirrors the main sweep's grep -I)
    text = data.decode('utf-8', 'replace')
    lines = text.split('\n')
    lineCount = len(lines)
    for lineIndex, line in enumerate(lines):
        i = lineIndex + 1
        for m in pat_named.finditer(line):
            name = m.group(0)
            if os.path.basename(name) in tracked_basenames:
                continue   # a real shipped file — not a violation
            if (p, name) in exempt_pairs:
                continue   # this EXACT (file, name) pair is a known-synthetic/archived reference
            print(f'{p}:{i}: references absent doc {name}')
        for m in pat_bare.finditer(line):
            name = m.group(0)
            if (p, name) in exempt_pairs:
                continue   # this EXACT (file, name) pair is a known-archived reference
            print(f'{p}:{i}: bare doc-name citation with no shipped doc: {name}')
        if lineIndex + 1 < lineCount:
            boundary = len(line)
            joined = line + ' ' + comment_cont_re.sub('', lines[lineIndex + 1])
            for m in pat_bare.finditer(joined):
                if not (m.start() < boundary and m.end() > boundary):
                    continue   # not a genuine cross-line span — either fully in line i (already
                               # reported above) or fully in the next line (that line's own pass
                               # will find it when lineIndex advances)
                name = m.group(0)
                if (p, name) in exempt_pairs:
                    continue   # this EXACT (file, name) pair is a known-archived reference
                print(f'{p}:{i}: bare doc-name citation split across two comment lines: {name}')
PY
if [ -s "$TMP/arm8" ]; then
    no "arm 8 — dangling reference to a culled internal-pattern .md name:"
    sed 's/^/          /' "$TMP/arm8"
else
    ok "arm 8 — no dangling references to culled internal-pattern .md names"
fi

printf 'ripwirepubliccheck: %s tracked file(s) swept\n' "$tracked"
[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"

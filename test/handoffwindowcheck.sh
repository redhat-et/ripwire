#!/usr/bin/env bash
# handoffwindowcheck.sh — WINDOW-AWARE HAND-OFF (src/handoffwindow.h; pre-registered as PR-R2). Where a --for answer hands off to
# --callers or --impact for a bound symbol, it counts that verb's rows first with the verb's own counting code. If the verb's DEFAULT
# call would window, the hand-off appends no page: it says windows="1", states next_total= (the verb's own total, a floor) and names
# the one complete call, next="--VERB=X --format=columnar --limit=<next_total>". If it would not window, the answer is byte for byte
# what it is with the lane off (RIPWIRE_NO_WINDOW_HANDOFF=1). The three hand-offs: <graph_verb verb="--callers=X"> (the key form),
# <callers [by=] of=X next="--impact=X"> (the caller hop's pointer), <reask next="--callers=X" | "--impact=X"/>.
# --uses, --grep and a byte estimate are OUT of scope: their windows have no graph signature, and bytes per row is not a constant.
#
# Every arm reads the hand-off against the DIRECT verb on the hand-off's own spelling, never against a number written here:
#   (N) non-vacuity, tracking this gate's own fixture: the classes the arms below need exist AS MEASURED (a multi-definition name whose
#       per-definition totals straddle the cap, a 2-caller symbol whose reach windows, a callers list past 50 rows served whole and one
#       inside the row zone that windows, the 40 / 41 edge), and at least 10 windowed and 10 complete hand-off cells
#   (A) prediction: windows="1" <=> the direct verb's root says has_more="1". False positives 0 AND false negatives 0
#   (B) the count is the verb's: next_total= equals the direct verb's total= on every windowed cell
#   (C) a non-windowing answer is byte-identical to the lane-off answer; and the lane-off answer of a windowed graph_verb cell DID
#       carry the page (so the comparison is not two copies of one path)
#   (D) the named call is the same rows: it answers has_more="0", n= equals next_total=, and its ( path, name, line ) rows equal those
#       of the two-call XML chain (default page, then --offset=<next_offset> --limit=<total>), as a multiset
#   (E) cost: the named call is smaller than that two-call chain on every windowed cell (the fixture is too small for the registered
#       0.85 / 0.75 corpus bounds; the ratio is printed, the bound here is < 1)
#   (V) the withholding is VISIBLE: every windowed hand-off carries windows="1", next_total=, counts_floor="1" (or its legend says
#       floor) and next=; the legend that governs it defines windows= and next_total= and says no page is appended; a windowed
#       <graph_verb> is self-closed with no verb answer after it; the block count equals the lane-off answer's (nothing vanished)
#   (G) well-formed (xmllint) and deterministic (two runs byte-identical)
# MUTATION CONTROLS — each is the real binary run under RIPWIRE_TEST_HANDOFF_MUTANT, and each must turn its arms RED:
#   (M1) threshold4:  the impact cap read as 4, not 40          -> (A) false positives > 0, and (C)
#   (M2) firstdef:    the total taken from the FIRST definition  -> (B) on a multi-definition cell, (A) false negatives where it straddles
#   (M3) limitminus1: the named call's --limit is total - 1      -> (D)
#   (M4) lane off:    windowed pages appended again              -> (A) false negatives > 0
#   (M6) indegree:    the total replaced by the in-degree proxy  -> (A) false negatives > 0 (the 2-caller, 60-reach symbol)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "handoffwindowcheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
unset RIPWIRE_NO_WINDOW_HANDOFF RIPWIRE_TEST_HANDOFF_MUTANT RIPWIRE_NO_CALLER_HOP
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export PYTHONDONTWRITEBYTECODE=1
FX="$TMP/fx"; mkdir -p "$FX"

python3 - "$FX" <<'PY'
import os, sys
FX = sys.argv[1]
def w( name, text ): open( os.path.join( FX, name ), 'w' ).write( text )
def fan( target, n, prefix ):     # n direct callers of target
    return ''.join( f"void {prefix}_{i:03d}( void ) {{ {target}(); }}\n" for i in range( n ) )
def chain( target, n, prefix ):   # prefix_000 calls target, prefix_001 calls prefix_000, ...
    return f"void {prefix}_000( void ) {{ {target}(); }}\n" + ''.join( f"void {prefix}_{i:03d}( void ) {{ {prefix}_{i-1:03d}(); }}\n" for i in range( 1, n ) )
w( 'small.c',  "void small_target( void ) {}\n" + fan( 'small_target', 5, 'small_caller' ) )
w( 'mid.c',    "void mid_target( void ) {}\n" + fan( 'mid_target', 22, 'mid_caller' ) )
w( 'edge40.c', "void edge_forty( void ) {}\n" + fan( 'edge_forty', 40, 'e40_caller' ) )
w( 'edge41.c', "void edge_fortyone( void ) {}\n" + fan( 'edge_fortyone', 41, 'e41_caller' ) )
w( 'band.c',   "void band_inside( void ) {}\n" + fan( 'band_inside', 120, 'bi' ) )                       # past the 50-row band, inside the 16,000 B one
w( 'bandout.c', "void band_outside( void ) {}\n" + fan( 'band_outside', 260, 'band_outside_direct_caller_with_a_deliberately_long_name' ) )   # <= 533 rows, past the byte band
w( 'wide.c',   "void wide_target( void ) {}\n" + fan( 'wide_target', 600, 'wide_caller' ) )                # past 533 rows: cannot fit
w( 'deep.c',   "void deep_target( void ) {}\n" + chain( 'deep_target', 30, 'deep_left' ) + chain( 'deep_target', 30, 'deep_right' ) )   # 2 callers, reach 60
w( 'dup_a.c',  "static void dup_straddle( void ) {}\n" + fan( 'dup_straddle', 10, 'dsa' ) )               # first definition alone: 10 (complete)
w( 'dup_b.c',  "static void dup_straddle( void ) {}\n" + fan( 'dup_straddle', 35, 'dsb' ) )               # both: 45 (windows)
w( 'big_a.c',  "static void dup_large( void ) {}\n" + fan( 'dup_large', 55, 'dla' ) )                     # first alone 55, both 85: windows either way
w( 'big_b.c',  "static void dup_large( void ) {}\n" + fan( 'dup_large', 30, 'dlb' ) )
w( 'wide_a.c', "static void dup_wide( void ) {}\n" + fan( 'dup_wide', 300, 'dup_wide_first_file_direct_caller_long_name' ) )   # 600 callers over both: the callers verb windows
w( 'wide_b.c', "static void dup_wide( void ) {}\n" + fan( 'dup_wide', 300, 'dup_wide_second_file_direct_caller_long_name' ) )
w( 'tiny_a.c', "static void dup_tiny( void ) {}\n" + fan( 'dup_tiny', 3, 'dta' ) )
w( 'tiny_b.c', "static void dup_tiny( void ) {}\n" + fan( 'dup_tiny', 4, 'dtb' ) )
PY

cat > "$TMP/check.py" <<'PY'
"""handoffwindowcheck's reader. argv: BIN FX OUTDIR. Prints one `ARM <id> PASS|FAIL <detail>` line per arm; exit 0 always (the
shell reads the lines, so a mutant run can assert WHICH arm went red)."""
import os, re, subprocess, sys
BIN, FX, OUT = sys.argv[1:4]
os.makedirs( OUT, exist_ok = True )
SYMS  = [ 'small_target', 'mid_target', 'edge_forty', 'edge_fortyone', 'band_inside', 'band_outside', 'wide_target', 'deep_target',
          'dup_straddle', 'dup_large', 'dup_wide', 'dup_tiny' ]
TASKS = [ ( 'key', 'callers of {}' ), ( 'who', 'who calls `{}`?' ), ( 'safe', 'Is it safe to change `{}`? What depends on it?' ), ( 'bare', '{}' ) ]
calls = {}
def run( args, env = None ):
    key = ( tuple( args ), tuple( sorted( ( env or {} ).items() ) ) )
    if key not in calls:
        e = dict( os.environ ); e.update( env or {} )   # the shell unset the lane's switches; (M4) sets the off switch for a whole reader run
        p = subprocess.run( [ BIN, FX, '--no-cache' ] + list( args ), cwd = FX, env = e, stdin = subprocess.DEVNULL, stdout = subprocess.PIPE, stderr = subprocess.DEVNULL )
        calls[ key ] = ( p.returncode, p.stdout )
    return calls[ key ]
attrs = lambda tag: dict( re.findall( r'([\w.-]+)="([^"]*)"', tag ) )
def root( doc ):
    body = re.sub( r'<!--.*?-->', '', doc, flags = re.S )
    m = re.search( r'<[A-Za-z_][^>]*>', body )
    return ( attrs( m.group( 0 ) ) if m else {} ), body
def xmlRows( body ):
    out = []
    for m in re.finditer( r'<s ([^>]*?)/>', body ):
        a = attrs( m.group( 1 ) )
        if 'n' in a and 'p' in a:
            p, _, l = a[ 'p' ].rpartition( ':' )
            out.append( ( p, a[ 'n' ], l ) )
    return out
def colRows( body ):
    pm = re.search( r'<paths>(.*?)</paths>', body, flags = re.S )
    paths = dict( re.findall( r'(\d+)=(\S+)', pm.group( 1 ) ) ) if pm else {}
    cm = re.search( r'<cols n="(\d+)"[^>]*>(.*?)</cols>', body, flags = re.S )
    if not cm: return None, []
    col = lambda k: re.search( rf'<{k}>(.*?)</{k}>', cm.group( 2 ), flags = re.S ).group( 1 ).split( ',' )
    P, N, L = col( 'path' ), col( 'name' ), col( 'line' )
    return int( cm.group( 1 ) ), [ ( paths.get( P[i], '?' ), N[i].replace( '&#44;', ',' ), L[i] ) for i in range( len( N ) ) ]
SUFFIX = re.compile( r'^(--(callers|impact)=\S+) --format=columnar --limit=(\d+)$' )
BARE   = re.compile( r'^--(callers|impact)=\S+$' )
def handoffs( doc ):
    """-> [ dict( kind, tag, attrs, legend, start ) ] for every callers / impact hand-off the answer carries."""
    out = []
    head = re.match( r'\s*(?:<!--.*?-->\s*)*<ctx\b[^>]*>((?:\s*<!--.*?-->)*)', doc, flags = re.S )
    headLegend = ( head.group( 0 ) if head else '' )
    # AF1 (2026-11-18): the default --for answer is ANSWER-FIRST: its document legend is the trailing run of comments before </ctx>,
    # inside the same answer. The document legend governs a <callers> hand-off wherever it sits, so both runs are read.
    tail = re.search( r'((?:<!--(?:(?!-->).)*-->\s*)+)</ctx>\s*\Z', doc, flags = re.S )
    headLegend += tail.group( 1 ) if tail else ''
    for m in re.finditer( r'(<!--(?:(?!-->).)*-->)?<(graph_verb|reask|callers)\b([^>]*?)(/?)>', doc, flags = re.S ):
        kind, a = m.group( 2 ), attrs( m.group( 3 ) )
        if kind == 'callers' and 'schema' in a: continue                       # a verb answer's root, not the --for hop
        if kind == 'graph_verb' and not a.get( 'verb', '' ).startswith( '--callers=' ): continue
        if kind == 'reask' and not re.match( r'--(callers|impact)=', a.get( 'next', '' ) ): continue
        legend = headLegend if kind == 'callers' else ( m.group( 1 ) or '' )
        out.append( dict( kind = kind, attrs = a, legend = legend, selfClosed = m.group( 4 ) == '/', end = m.end() ) )
    return out
def baseOf( h ):
    """The DEFAULT call this hand-off stands for, and whether its next= is the registered complete-call spelling."""
    a = h[ 'attrs' ]
    first = a.get( 'verb' ) if h[ 'kind' ] == 'graph_verb' else None
    nxt   = a.get( 'next', '' )
    m     = SUFFIX.match( nxt )
    if first: return first, m
    return ( m.group( 1 ) if m else nxt ), m
cells, answers, problems = [], [], []
for sym in SYMS:
    for tid, tpl in TASKS:
        args = [ '--for=' + tpl.format( sym ) ]
        rc, doc = run( args )
        _, off  = run( args, { 'RIPWIRE_NO_WINDOW_HANDOFF': '1' } )
        text = doc.decode( 'utf8', 'replace' )
        hs   = handoffs( text )
        ans  = dict( sym = sym, tid = tid, args = args, doc = doc, off = off, text = text, hs = hs, rc = rc, truthWindowed = False )
        answers.append( ans )
        for h in hs:
            base, spelled = baseOf( h )
            if not BARE.match( base ):
                problems.append( f"{sym}/{tid} {h['kind']}: hand-off base is not a bare callers/impact call: {base!r}" ); continue
            a, body = root( run( [ base ] )[ 1 ].decode( 'utf8', 'replace' ) )
            truth   = a.get( 'has_more' ) == '1'
            ans[ 'truthWindowed' ] = ans[ 'truthWindowed' ] or truth
            cells.append( dict( sym = sym, tid = tid, kind = h[ 'kind' ], base = base, h = h, spelled = spelled, said = h[ 'attrs' ].get( 'windows' ) == '1',
                                truth = truth, direct = a, body = body, ans = ans ) )
verb = lambda c: c[ 'base' ].split( '=' )[ 0 ].lstrip( '-' )
def arm( name, bad, detail ):
    print( f"ARM {name} {'FAIL' if bad else 'PASS'} {detail}" + ( ' :: ' + '; '.join( bad[ :4 ] ) if bad else '' ) )
lab = lambda c: f"{c['sym']}/{c['tid']}/{c['kind']}"

# (N) the fixture's classes, AS MEASURED off the direct verbs
d = lambda v, s: root( run( [ f'--{v}={s}' ] )[ 1 ].decode( 'utf8', 'replace' ) )[ 0 ]
tot = lambda a: int( a.get( 'total', a.get( 'reaches', a.get( 'count', '0' ) ) ) )
nbad = []
wn, cn = sum( c[ 'truth' ] for c in cells ), sum( not c[ 'truth' ] for c in cells )
if wn < 10 or cn < 10: nbad.append( f"{wn} windowed and {cn} complete hand-off cells: a set with fewer than 10 of either cannot decide" )
for kind in ( 'graph_verb', 'callers', 'reask' ):
    k = [ c for c in cells if c[ 'kind' ] == kind ]
    if not any( c[ 'truth' ] for c in k ) or not any( not c[ 'truth' ] for c in k ): nbad.append( f"hand-off kind {kind}: needs a windowed and a complete cell, has {sum( c['truth'] for c in k )}/{sum( not c['truth'] for c in k )}" )
if not ( d( 'impact', 'edge_forty' ).get( 'has_more' ) != '1' and tot( d( 'impact', 'edge_forty' ) ) == 40 ): nbad.append( "edge_forty: impact is not a complete 40" )
if not ( d( 'impact', 'edge_fortyone' ).get( 'has_more' ) == '1' and tot( d( 'impact', 'edge_fortyone' ) ) == 41 ): nbad.append( "edge_fortyone: impact is not a windowed 41" )
if not ( int( d( 'callers', 'deep_target' ).get( 'count', '0' ) ) <= 4 and d( 'impact', 'deep_target' ).get( 'has_more' ) == '1' ): nbad.append( "deep_target: not a few-caller symbol whose reach windows" )
if not ( int( d( 'callers', 'band_inside' ).get( 'count', '0' ) ) > 50 and d( 'callers', 'band_inside' ).get( 'has_more' ) != '1' ): nbad.append( "band_inside: not a past-50 callers list served whole" )
bo = d( 'callers', 'band_outside' )
if not ( 50 < int( bo.get( 'count', '0' ) ) <= 533 and bo.get( 'has_more' ) == '1' ): nbad.append( "band_outside: not a windowed callers list inside the row zone" )
for s in ( 'dup_straddle', 'dup_large', 'dup_tiny' ):
    if int( d( 'impact', s ).get( 'defs', '0' ) ) < 2: nbad.append( f"{s}: not a multi-definition name" )
if not any( c[ 'sym' ] in ( 'dup_straddle', 'dup_large' ) and verb( c ) == 'impact' and c[ 'truth' ] for c in cells ): nbad.append( "no windowed impact hand-off on a multi-definition name" )
arm( 'N', nbad + problems, f"cells={len( cells )} windowed={wn} complete={cn} kinds=" + ','.join( f"{k}:{sum( c['kind'] == k for c in cells )}" for k in ( 'graph_verb', 'callers', 'reask' ) ) )

# (A) the confusion matrix
tp = [ c for c in cells if c[ 'said' ] and c[ 'truth' ] ];  fp = [ c for c in cells if c[ 'said' ] and not c[ 'truth' ] ]
fn = [ c for c in cells if not c[ 'said' ] and c[ 'truth' ] ];  tn = [ c for c in cells if not c[ 'said' ] and not c[ 'truth' ] ]
print( f"CONFUSION TP={len( tp )} FP={len( fp )} FN={len( fn )} TN={len( tn )}" )
arm( 'A-fp', [ lab( c ) for c in fp ], f"false positives={len( fp )}" )
arm( 'A-fn', [ lab( c ) for c in fn ], f"false negatives={len( fn )}" )

# (B) next_total= is the direct verb's total=
arm( 'B', [ f"{lab( c )}: next_total={c['h']['attrs'].get( 'next_total' )} direct total={c['direct'].get( 'total' )}" for c in cells
            if c[ 'said' ] and c[ 'h' ][ 'attrs' ].get( 'next_total' ) != c[ 'direct' ].get( 'total', 'absent' ) ], f"windowed-as-said cells={sum( c['said'] for c in cells )}" )

# (C) a non-windowing answer is the lane-off answer byte for byte; the lane-off twin of a windowed key-form answer carried the page
cbad = [ f"{a['sym']}/{a['tid']}: differs from the lane-off answer" for a in answers if not a[ 'truthWindowed' ] and a[ 'doc' ] != a[ 'off' ] ]
gvw  = [ c for c in cells if c[ 'kind' ] == 'graph_verb' and c[ 'truth' ] ]
cbad += [ f"{lab( c )}: the lane-off answer carries no has_more=\"1\" page" for c in gvw if b'has_more="1"' not in c[ 'ans' ][ 'off' ] ]
arm( 'C', cbad, f"non-windowing answers={sum( not a['truthWindowed'] for a in answers )} of {len( answers )}; lane-off pages seen={len( gvw )}" )

# (D) the named call is the same rows; (E) and cheaper than the two-call chain
dbad, ebad, two, named, checked = [], [], 0, 0, 0
for c in cells:
    if not c[ 'truth' ]: continue
    a = c[ 'direct' ]
    p2 = run( [ c[ 'base' ], '--offset=' + a[ 'next_offset' ], '--limit=' + a[ 'total' ] ] )[ 1 ].decode( 'utf8', 'replace' )
    chain = xmlRows( c[ 'body' ] ) + xmlRows( root( p2 )[ 1 ] )
    if not c[ 'said' ] or not c[ 'spelled' ]:
        dbad.append( f"{lab( c )}: next= is not --VERB=X --format=columnar --limit=N ({c['h']['attrs'].get( 'next' )!r})" ); continue
    nd = run( c[ 'h' ][ 'attrs' ][ 'next' ].split( ' ' ) )[ 1 ].decode( 'utf8', 'replace' )
    na, nb = root( nd )
    n, rows = colRows( nb )
    checked += 1
    if na.get( 'has_more' ) != '0': dbad.append( f"{lab( c )}: the named call says has_more={na.get( 'has_more' )}" )
    elif str( n ) != c[ 'h' ][ 'attrs' ].get( 'next_total' ): dbad.append( f"{lab( c )}: n={n} next_total={c['h']['attrs'].get( 'next_total' )}" )
    elif sorted( rows ) != sorted( chain ): dbad.append( f"{lab( c )}: rows differ ({len( rows )} named, {len( chain )} chained)" )
    t = len( run( [ c[ 'base' ] ] )[ 1 ] ) + len( p2.encode() )
    two += t;  named += len( nd.encode() )
    if len( nd.encode() ) >= t: ebad.append( f"{lab( c )}: named {len( nd.encode() )} B >= chain {t} B" )
arm( 'D', dbad + ( [ 'no windowed cell was checked' ] if checked == 0 else [] ), f"named calls run={checked}" )
arm( 'E', ebad + ( [ 'no windowed cell was checked' ] if checked == 0 else [] ), f"pooled named/chain={named}/{two}" + ( f"={named / two:.3f}" if two else '' ) )

# (V) the withholding is visible
vbad = []
for c in cells:
    if not c[ 'truth' ]: continue
    a, leg = c[ 'h' ][ 'attrs' ], c[ 'h' ][ 'legend' ]
    need = [ k for k in ( 'windows', 'next_total', 'next' ) if k not in a ]
    if need: vbad.append( f"{lab( c )}: no {'/'.join( need )}= on the hand-off" ); continue
    for k in ( 'windows', 'next_total' ):
        if not re.search( r'(?<![\w:.-])' + k + r'\s*=', leg ): vbad.append( f"{lab( c )}: the legend does not define {k}=" )
    if 'floor' not in leg: vbad.append( f"{lab( c )}: the legend does not say the count is a floor" )
    if not re.search( r'no page|not appended|NO page', leg ): vbad.append( f"{lab( c )}: the legend does not say a page was withheld" )
    if c[ 'kind' ] == 'graph_verb':
        if not c[ 'h' ][ 'selfClosed' ] or '<callers schema=' in c[ 'ans' ][ 'text' ][ c[ 'h' ][ 'end' ]: ]: vbad.append( f"{lab( c )}: a windowed block still carries a verb answer" )
        if c[ 'ans' ][ 'text' ].count( '<graph_verb ' ) != c[ 'ans' ][ 'off' ].decode( 'utf8', 'replace' ).count( '<graph_verb ' ): vbad.append( f"{lab( c )}: the block count differs from the lane-off answer" )
arm( 'V', vbad + ( [ 'no windowed cell' ] if wn == 0 else [] ), f"windowed hand-offs read={wn}" )

# (G) well-formed, deterministic
gbad = []
for a in answers[ :: 3 ]:
    p = os.path.join( OUT, f"{a['sym']}.{a['tid']}.xml" )
    open( p, 'wb' ).write( a[ 'doc' ] )
    if a[ 'rc' ] not in ( 0, 4 ) or not a[ 'doc' ]: gbad.append( f"{a['sym']}/{a['tid']}: rc={a['rc']} bytes={len( a['doc'] )}" )
    if subprocess.run( [ 'xmllint', '--noout', p ], stdout = subprocess.DEVNULL, stderr = subprocess.DEVNULL ).returncode != 0: gbad.append( f"{a['sym']}/{a['tid']}: not well-formed" )
    again = subprocess.run( [ BIN, FX, '--no-cache' ] + a[ 'args' ], cwd = FX, stdin = subprocess.DEVNULL, stdout = subprocess.PIPE, stderr = subprocess.DEVNULL ).stdout
    if again != a[ 'doc' ]: gbad.append( f"{a['sym']}/{a['tid']}: two runs differ" )
arm( 'G', gbad, f"answers read={len( answers[ :: 3 ] )}" )
PY

armOf(){ grep "^ARM $2 " "$1" | head -1; }
passed(){ case "$( armOf "$1" "$2" )" in "ARM $2 PASS"*) return 0;; *) return 1;; esac; }
failed(){ case "$( armOf "$1" "$2" )" in "ARM $2 FAIL"*) return 0;; *) return 1;; esac; }

command -v xmllint >/dev/null 2>&1 || { echo "xmllint required (arm G)"; exit 2; }
python3 "$TMP/check.py" "$BIN" "$FX" "$TMP/out" >"$TMP/main.txt" 2>"$TMP/main.err" || no "the reader exited $? ($( head -c 300 "$TMP/main.err" ))"
grep '^CONFUSION' "$TMP/main.txt" | sed 's/^/  INFO  /'
for a in N A-fp A-fn B C D E V G; do
    line="$( armOf "$TMP/main.txt" "$a" )"
    if passed "$TMP/main.txt" "$a"; then ok "($a) ${line#ARM "$a" PASS }"; else no "($a) ${line:-the reader printed no line for this arm}"; fi
done

# MUTATION CONTROLS: the real binary under each registered mutation; the named arms must be RED there (and were green above)
mutant(){ # $1 label  $2 env assignment  $3.. arms that must fail
    local label="$1" envset="$2"; shift 2
    env "$envset" python3 "$TMP/check.py" "$BIN" "$FX" "$TMP/out.$label" >"$TMP/mut.$label.txt" 2>/dev/null
    local a
    for a in "$@"; do
        if failed "$TMP/mut.$label.txt" "$a"; then ok "($label) arm $a goes RED: $( armOf "$TMP/mut.$label.txt" "$a" | cut -c1-200 )"
        else no "($label) arm $a did NOT go red under the mutation: $( armOf "$TMP/mut.$label.txt" "$a" | cut -c1-200 )"; fi
    done
}
mutant M1-threshold4  RIPWIRE_TEST_HANDOFF_MUTANT=threshold4  A-fp C
mutant M2-firstdef    RIPWIRE_TEST_HANDOFF_MUTANT=firstdef    B A-fn
mutant M3-limitminus1 RIPWIRE_TEST_HANDOFF_MUTANT=limitminus1 D
mutant M4-laneoff     RIPWIRE_NO_WINDOW_HANDOFF=1             A-fn
mutant M6-indegree    RIPWIRE_TEST_HANDOFF_MUTANT=indegree    A-fn

[ "$fail" = 0 ] && echo "handoffwindowcheck: PASS" || echo "handoffwindowcheck: FAIL"
exit "$fail"

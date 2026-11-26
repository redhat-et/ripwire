#!/usr/bin/env python3
"""
Fixture tests for run_locbench.py's matched-budget control arms (PREREG_PLACEBO.md):
for-matched, placebo (unrelated files), placebo-shuffle, lexical (file-level BM25).

The property under test is the one METHODOLOGY.md §8 makes the whole comparison rest on: every control arm
is EXACTLY the matched byte size and FORMAT-IDENTICAL to the real answer, and carries no ranking signal.
Pure Python, no network, no model. Runs as a plain script (exit 1 on any failure):

    python3 bench/locbench/test_placebo_arms.py [RIPWIRE_BIN]

With a ripwire binary argument it also runs one arm against real ripwire output on test/fixture.
"""
import hashlib, inspect, json, os, pathlib, subprocess, sys, tempfile
import xml.etree.ElementTree as ET

HERE = os.path.dirname( os.path.abspath( __file__ ) )
sys.path.insert( 0, HERE )
import run_locbench as rl

LEGEND = "<!-- ripwire candidates: fixture legend, bytes must survive verbatim -->"

def esc( s ):
    return rl.xml_text_escape( s )

def cand( r, s, name, path, line, sig, kind="fn" ):
    return ( f'<cand r="{r}" s="{s}" n="{esc( name )}" id="{esc( path )}::{esc( name )}" k="{kind}" '
             f'p="{esc( path )}" l="{line}"><sig>{esc( sig )}</sig></cand>' )

def doc( rows, route="subtoken+body", total=None ):
    root = f'<candidates count="{len( rows )}" total="{total or len( rows )}" capped="0" route="{route}" anchored="0">'
    return LEGEND + root + "".join( rows ) + "</candidates>"

FILES = [ f"pkg/mod{i}.py" for i in range( 8 ) ] + [ "pkg/config_parser.py", "pkg/net/http_client.py" ]

def universe_rows():
    rows, r = [], 1
    for fi, f in enumerate( FILES ):
        for j in range( 6 ):
            name = f"func_{fi}_{j}"
            sig = f"def {name}( self, value: int, other: 'Thing & co' ) -> List[<str>]:  # helper {fi}.{j} " + "x" * ( 20 + 7 * j )
            rows.append( cand( r, f"{1.0 / r:.6f}", name, f, 10 + j * 12, sig ) ); r += 1
    return rows

def for_rows():
    # The "real answer": rows from config_parser.py, http_client.py and mod0.py, ripwire-ranked.
    uni = universe_rows()
    pick = [ x for x in uni if 'p="pkg/config_parser.py"' in x ][:4] + [ x for x in uni if 'p="pkg/net/http_client.py"' in x ][:3] \
         + [ x for x in uni if 'p="pkg/mod0.py"' in x ][:3]
    return [ rl.set_attr( rl.set_attr( x, "r", str( i + 1 ) ), "s", f"{0.9 - 0.05 * i:.6f}" ) for i, x in enumerate( pick ) ]

UNI = doc( universe_rows(), route="query-personalized" )
FOR = doc( for_rows() )

failures = []
def check( cond, msg ):
    print( ( "  PASS  " if cond else "  FAIL  " ) + msg )
    if not cond: failures.append( msg )

def rows_of( x ):
    return rl.split_candidates_doc( x )[2]

def files_of( x ):
    return [ rl.row_attr( r, "p" ) for r in rows_of( x ) ]

def strip_rank( row ):
    return rl.set_attr( rl.set_attr( row, "r", "0" ), "s", "0" )

def test_unrelated_placebo_exact_and_format_identical():
    real_files = set( files_of( FOR ) )
    ref = rl.format_signature( FOR )
    uni_shapes = rl.format_signature( UNI )["shapes"]
    targets = range( 400, rl.nbytes( FOR ) + 1, 37 )
    bad_size = bad_fmt = leaked = 0
    for t in targets:
        p = rl.build_placebo_unrelated( FOR, UNI, "inst-A", t )
        sig = rl.format_signature( p )
        bad_size += rl.nbytes( p ) != t
        bad_fmt += not ( sig["head"] == ref["head"] and sig["root"] == ref["root"] and sig["tail"] == ref["tail"]
                         and sig["shapes"] <= uni_shapes )
        leaked += bool( set( files_of( p ) ) & real_files )
    n = len( list( targets ) )
    check( bad_size == 0, f"placebo is EXACTLY the target byte size at all {n} targets ({bad_size} off)" )
    check( bad_fmt == 0, f"placebo is format-identical (legend, root attribute names, ripwire row shapes) at all {n} targets" )
    check( leaked == 0, f"placebo names none of the real answer's files at all {n} targets" )

def test_exclusion_is_not_vacuous():
    # The universe's own top rows DO include the real answer's files, so "names none of them" above is a
    # property the builder enforces, not one the fixture hands it for free.
    top = files_of( doc( rows_of( UNI )[:60] ) )
    check( bool( set( top ) & set( files_of( FOR ) ) ), "fixture universe contains the real answer's files (exclusion check is live)" )

def test_placebo_deterministic_and_seeded():
    t = rl.nbytes( FOR )
    a1 = rl.build_placebo_unrelated( FOR, UNI, "inst-A", t )
    a2 = rl.build_placebo_unrelated( FOR, UNI, "inst-A", t )
    b = rl.build_placebo_unrelated( FOR, UNI, "inst-B", t )
    check( a1 == a2, "placebo is byte-deterministic for one instance" )
    check( a1 != b, "placebo draw depends on the instance (a different instance draws different rows)" )

def test_placebo_scores_are_the_real_answers():
    p = rl.build_placebo_unrelated( FOR, UNI, "inst-A", rl.nbytes( FOR ) )
    real_s = [ rl.row_attr( r, "s" ) for r in rows_of( FOR ) ]
    got = [ rl.row_attr( r, "s" ) for r in rows_of( p ) ]
    want = [ real_s[min( i, len( real_s ) - 1 )] for i in range( len( got ) ) ]
    ranks = [ rl.row_attr( r, "r" ) for r in rows_of( p ) ]
    check( got == want, "placebo s= column is the real answer's, in order (no score signal)" )
    check( ranks == [ str( i + 1 ) for i in range( len( ranks ) ) ], "placebo r= is 1..N in position order" )

def test_shuffle_exact_bytes_same_content():
    m = rl.build_for_matched( FOR, rl.nbytes( FOR ) )
    s = rl.build_placebo_shuffle( m, "inst-A" )
    check( rl.nbytes( s ) == rl.nbytes( m ), "placebo-shuffle has the matched answer's exact byte count" )
    check( sorted( map( strip_rank, rows_of( s ) ) ) == sorted( map( strip_rank, rows_of( m ) ) ),
           "placebo-shuffle carries the same rows (content) as the real answer" )
    check( files_of( s ) != files_of( m ), "placebo-shuffle changes the order" )
    check( rl.format_signature( s ) == rl.format_signature( m ), "placebo-shuffle is format-identical" )

def test_for_matched_is_a_prefix_in_ripwire_order():
    full = rows_of( FOR )
    bad = 0
    for t in range( 600, rl.nbytes( FOR ) + 1, 53 ):
        m = rl.build_for_matched( FOR, t )
        got = rows_of( m )
        bad += rl.nbytes( m ) != t
        # every row but the (at most two) trimmed tail rows is the real row verbatim; all ids in ripwire order
        bad += got[:-2] != full[:max( 0, len( got ) - 2 )]
        bad += [ rl.row_attr( r, "id" ) for r in got ] != [ rl.row_attr( r, "id" ) for r in full[:len( got )] ]
        bad += sum( rl.row_sig_text( r ).endswith( rl.ELLIPSIS ) for r in got ) > 2
    check( bad == 0, "for-matched = ripwire's own rows, in ripwire's order, closed to the exact target (<=2 trimmed rows)" )
    check( rl.build_for_matched( FOR, rl.nbytes( FOR ) ) == FOR, "for-matched at the full size is the real answer byte-for-byte" )

def test_trim_keeps_entities_well_formed():
    # Every fixture sig holds & < > ' — a trim that cut inside an entity would not parse.
    bad = 0
    for t in range( 300, 1400, 1 ):
        try:
            ET.fromstring( rl.build_placebo_unrelated( FOR, UNI, "inst-A", t )[len( LEGEND ):] )
        except ET.ParseError:
            bad += 1
        except rl.PlaceboUnbuildable:
            pass
    check( bad == 0, "every trimmed placebo parses (no cut inside an XML entity), 1,100 consecutive targets" )

def test_unbuildable_fails_closed():
    tiny = doc( rows_of( UNI )[:2] )
    try:
        out = rl.build_placebo_unrelated( FOR, tiny, "inst-A", rl.nbytes( FOR ) )
        check( False, f"an undersized pool must raise, got a {rl.nbytes( out )}-byte document" )
    except rl.PlaceboUnbuildable:
        check( True, "an undersized pool raises PlaceboUnbuildable instead of returning a wrong-size placebo" )

def test_builders_are_gold_blind():
    builders = ( rl.build_placebo_unrelated, rl.build_placebo_shuffle, rl.build_for_matched, rl.build_lexical, rl.build_derived_arms )
    names = [ p for f in builders for p in inspect.signature( f ).parameters ]
    check( not any( "gold" in p or "primary" in p for p in names ), "no control-arm builder takes gold as an argument" )

def make_repo( root ):
    for f in FILES:
        p = pathlib.Path( root ) / f
        p.parent.mkdir( parents=True, exist_ok=True )
        p.write_text( f"# {f}\ndef helper():\n    return 1\n" )
    ( pathlib.Path( root ) / "pkg/config_parser.py" ).write_text(
        "class ConfigParser:\n    def parseConfigFile( self, path ):\n        return read_config_file( path )\n" )
    ( pathlib.Path( root ) / "pkg/net/http_client.py" ).write_text( "def send_request(): pass\n" + "config " * 3 )

def test_bm25_file_level():
    with tempfile.TemporaryDirectory() as d:
        make_repo( d )
        ranked, over = rl.bm25_rank_files( d, FILES, "Crash when I parse the config file" )
        check( ranked[0][0] == "pkg/config_parser.py", f"BM25 ranks the file whose identifiers carry the query first (got {ranked[0][0]})" )
        check( ranked[1][0] == "pkg/net/http_client.py", "BM25 is whole-file: a file with only the word 'config' ranks second" )
        check( "parse" in rl.lexical_tokens( "parseConfigFile" ) and "file" in rl.lexical_tokens( "read_config_file" ),
               "lexical tokenizer splits camelCase and snake_case identifiers" )
        big = pathlib.Path( d ) / "pkg/mod1.py"; big.write_text( "config " * 1000 )
        ranked, over = rl.bm25_rank_files( d, FILES, "config", max_bytes=1000 )
        check( over == 1 and "pkg/mod1.py" in [ f for f, _ in ranked ],
               "an oversize file is counted (bm25_oversize_files) and stays in the ranking, not dropped silently" )

def test_lexical_and_derived_end_to_end():
    with tempfile.TemporaryDirectory() as d:
        make_repo( d )
        prod = "<ctx>" + "p" * 900 + "</ctx>"          # stands in for the production --for payload: only its SIZE is used
        docs, target, meta = rl.build_derived_arms( FOR, UNI, rl.nbytes( prod ), "inst-A", d, "parse the config file", FILES )
        check( target == rl.nbytes( prod ), "matched budget = the production --for payload's own byte size" )
        check( all( rl.nbytes( x ) == target for x in docs.values() ), f"all four control arms are exactly {target} B" )
        check( files_of( docs["lexical"] )[0] == "pkg/config_parser.py", "lexical arm leads with the BM25 top file" )
        out = pathlib.Path( d ) / "payloads"
        man = rl.emit_payloads( out, "org/repo-1", docs, prod )
        on_disk = { a: hashlib.sha256( ( out / "org__repo-1" / f"{a}.xml" ).read_bytes() ).hexdigest() for a in man }
        check( all( man[a]["sha256"] == on_disk[a] for a in man ) and "for-production" in man,
               "emit_payloads writes every arm + the production payload with a matching sha256 manifest" )
        check( json.loads( ( out / "org__repo-1" / "manifest.json" ).read_text() ) == man, "manifest.json round-trips" )

def test_real_ripwire( bin_path ):
    # One arm on REAL ripwire output: the shipped --for candidates export + the coverage universe on
    # test/fixture. Proves the row/root regexes match what the binary emits, not only what the fixture says.
    fixture = os.path.join( HERE, "..", "..", "test", "fixture" )
    run = lambda *a: subprocess.run( [ bin_path, fixture, *a ], capture_output=True, text=True, errors="replace" ).stdout
    for_xml = run( "--for=distance between two points", "--format=candidates", "--top-k=3", "--no-cache" )
    uni_xml = run( "--query=distance between two points", "--format=candidates", "--top-k=1000000000", "--no-cache" )
    target = rl.nbytes( for_xml )
    p = rl.build_placebo_unrelated( for_xml, uni_xml, "fixture", target )
    ref, sig = rl.format_signature( for_xml ), rl.format_signature( p )
    check( rl.nbytes( p ) == target, f"real ripwire: placebo is exactly the --for export's {target} B" )
    check( sig["head"] == ref["head"] and sig["root"] == ref["root"] and sig["shapes"] <= rl.format_signature( uni_xml )["shapes"],
           "real ripwire: placebo is format-identical to the --for export" )
    check( not ( set( files_of( p ) ) & set( files_of( for_xml ) ) ), "real ripwire: placebo names none of the --for answer's files" )

def run_main_offline( bin_path, arms, work ):
    # Drive run_locbench.main() end to end with NO network: one fabricated instance (not a Loc-Bench row) whose
    # "repo" is test/fixture, served by a stubbed checkout(). Returns (exit message or None, results JSON).
    import contextlib, io
    fixture = os.path.realpath( os.path.join( HERE, "..", "..", "test", "fixture" ) )
    row = dict( repo="fixture/geom", base_commit="0" * 40, instance_id="fixture__geom-1", patch="",
                problem_statement="distance between two points is wrong for negative coordinates",
                edit_functions=[ "geometry.cpp:distance" ], added_functions=[] )
    ds = pathlib.Path( work ) / "datasets"; ds.mkdir( parents=True, exist_ok=True )
    ( ds / "rows_czlll__Loc-Bench_V1_test_1.json" ).write_text( json.dumps( [ row ] ) )
    saved = ( rl.checkout, rl.CTX, sys.argv )
    rl.checkout = lambda *a, **k: pathlib.Path( fixture )
    rl.CTX = bin_path
    out = pathlib.Path( work ) / "out.json"
    sys.argv = [ "run_locbench.py", "--n", "1", "--work-dir", work, "--arms", arms, "--json-out", str( out ),
                 "--emit-payloads", str( pathlib.Path( work ) / "payloads" ) ]
    msg = None
    try:
        with contextlib.redirect_stdout( io.StringIO() ), contextlib.redirect_stderr( io.StringIO() ):
            rl.main()
    except SystemExit as e:
        msg = str( e )
    finally:
        rl.checkout, rl.CTX, sys.argv = saved
    return msg, ( json.loads( out.read_text() ) if out.exists() else None )

def test_main_integration( bin_path ):
    with tempfile.TemporaryDirectory() as w:
        msg, res = run_main_offline( bin_path, "for,for-matched,placebo-shuffle,lexical", w )
        arms = ( res or {} ).get( "arms", {} )
        ok = msg is None and all( arms.get( a, {} ).get( "n" ) == 1 for a in ( "for", "for-matched", "placebo-shuffle", "lexical" ) )
        check( ok, f"main() scores the shipped + derived arms offline on a fixture instance ({msg})" )
        sizes = { arms[a]["output_bytes"] for a in ( "for-matched", "placebo-shuffle", "lexical" ) } if ok else set()
        want = min( arms["for"]["output_bytes"], arms["for"]["candidate_bytes"] ) if ok else None
        check( ok and sizes == { want }, f"derived arms are scored at min(production --for bytes, --for export bytes) = {want} ({sizes})" )
        man = pathlib.Path( w ) / "payloads" / "fixture__geom-1" / "manifest.json"
        check( man.exists() and "for-production" in json.loads( man.read_text() ), "--emit-payloads sealed the instance's payloads" )
    with tempfile.TemporaryDirectory() as w:
        # test/fixture is 14 symbols: the --for answer names every file, so no unrelated pool exists. The run must
        # STOP on that instance, not score a short or empty placebo.
        msg, _ = run_main_offline( bin_path, "for,placebo", w )
        check( bool( msg ) and "PLACEBO UNBUILDABLE" in msg, f"main() aborts on an unbuildable placebo instead of scoring it ({msg})" )

def main():
    for name, fn in sorted( globals().items() ):
        if name.startswith( "test_" ) and name not in ( "test_real_ripwire", "test_main_integration" ): fn()
    if len( sys.argv ) > 1 and os.access( sys.argv[1], os.X_OK ):
        test_real_ripwire( sys.argv[1] )
        test_main_integration( os.path.realpath( sys.argv[1] ) )
    else:
        print( "  SKIP  real-ripwire arm (no binary given)" )
    print( f"{'ALL PASS' if not failures else f'{len( failures )} FAILED'}" )
    return 1 if failures else 0

if __name__ == "__main__":
    sys.exit( main() )

#!/usr/bin/env bash
# fieldidcheck.sh — gate for rw::fieldChild / the [grammar][field] TSFieldId table (src/infra/fieldid.h),
# which replaced 199 per-AST-node `ts_node_child_by_field_name` calls (each one a linear `strncmp` scan
# over the grammar's field table, through two dyld stubs) with one resolution per grammar at prewarm.
#
# The claim being gated is narrow and total: for EVERY grammar the crawl table can name, EVERY field the
# tree asks for, and EVERY node of a real parse tree, `fieldChild( n, NodeField::X )` returns the SAME
# node `ts_node_child_by_field_name( n, "x", len )` would have. A hoisted lookup table is the kind of
# change that is right on the grammar you tested and wrong on the one you did not, so this gate does not
# sample — it enumerates, over grammars harvested FROM THE TREE (src/ingest_crawl.h's kLangTable) rather
# than from a list frozen in this file.
#
#   A. TABLE IDENTITY. For every ( grammar, NodeField ) pair, the warm table's id equals what
#      `ts_language_field_id_for_name` answers at runtime for that field's spelling. The spellings the
#      reference side uses are harvested from a PRISTINE src/infra/fieldid.h at gate time and baked into
#      the harness as literals, so a mutation of the header's own name table cannot move both sides at
#      once (arm D).
#   A0. COLD PARITY. The same equality BEFORE any grammar is warmed — the unwarmed path must be the
#      by-name answer, not a hole. This is what makes "a missed warm is slower, never wrong" a tested
#      statement instead of a comment.
#   B. ENUMERATED PAIRS, over real trees. For a fixture file per extension row of kLangTable, the whole
#      AST is walked and every ( node, field ) pair is compared node-for-node against the by-name call:
#      both null, or `ts_node_eq`. This is the arm that can see a wrong id, a wrong grammar keyed, or a
#      registry that published a slot's ids under another slot's pointer.
#   C. UNKNOWN-FIELD PARITY, and it is not vacuous. A grammar that has no `receiver:` resolves the name
#      to id 0, and `ts_node_child_by_field_id( n, 0 )` returns the null node on its first line
#      (node.c:602) — so a 0 in the table IS the by-name answer, not a bug to guard. Arm C counts the
#      ( grammar, field ) pairs where the id is 0, requires that count to be non-zero (otherwise the arm
#      proves nothing), and requires the by-name call to agree on every node of every fixture.
#   D. MUTATION. Arms A and B must be able to go red, so two scratch copies of the header are built and
#      each must fail: D1 misspells ONE field's row in kNodeFieldNames (the table's data), D2 shifts the
#      field index inside the lookup (the table's code). An arm that has never been observed failing is
#      decoration.
#   E. POPULATION. The conversion must still BE the conversion: zero `ts_node_child_by_field_name` sites
#      left in src/ outside fieldid.h's own prose, a non-trivial number of `fieldChild(` sites, and the
#      per-grammar warm actually wired into the ingest translation unit. (E-mut) performs the reverse
#      rewrite on a scratch copy and requires arm E to report every converted file — a mechanical 199-site
#      conversion is exactly where an arm can be green in BOTH directions.
#      HONEST LIMIT, stated rather than implied: arm E reads SOURCE. It proves the warm call is written
#      and reachable from ingest(); it does not prove at runtime that no grammar took the by-name
#      fallback. The runtime evidence for that is the A/B CPU measurement in the landing commit, not a
#      gate — instrumenting it would mean a second full build inside a gate, which this repo has a
#      recorded trap for.
#   F. CAPACITY. kLangTable's distinct grammar count must fit kFieldIdCapacity — a grammar that does not
#      fit is correct but silently un-warmed, so the arm is the alarm for the day a 65th grammar lands.
#
# Usage:  bash test/fieldidcheck.sh   [ CXX=clang++ ]  [ RIPWIRE_BIN=build/ripwire ]
# RIPWIRE_BIN is used ONLY to locate the build directory whose grammar OBJECT LIST names the sources to compile (the vendored
# grammars and the tree-sitter core the harness links against) — this gate never EXECUTES the ripwire
# binary. It still needs no pin in test/binoverridecheck.sh's EXEMPT dict: a sentinel RIPWIRE_BIN points at
# a directory with no grammar objects in it, so the gate goes red rather than silently green.
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
CXX="${CXX:-c++}"
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

HDR="$ROOT/src/infra/fieldid.h"
CRAWL="$ROOT/src/ingest_crawl.h"
# The files the conversion touched. Sections of src/ingest.cpp's TU, plus the two standalone consumers.
SITE_FILES="src/ingest_metrics.h src/ingest_binds.h src/ingest_sidecap.h src/ingest_relations.h src/ingest_names.h src/ingest_jsimports.h src/ingest_elixir.h src/preprocdead.h src/slice.h"

[ -f "$HDR" ]   || { echo "missing $HDR — nothing to check"; exit 2; }
[ -f "$CRAWL" ] || { echo "missing $CRAWL — the grammar table is what this gate enumerates over"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
case "$BIN" in /*) ;; *) BIN="$ROOT/$BIN";; esac
BUILDDIR="$( dirname "$BIN" )"
TSLIB="$BUILDDIR/_deps/tree_sitter-build/libtree-sitter.a"
if [ ! -f "$TSLIB" ]; then
    echo "  no tree-sitter static lib under $BUILDDIR — build first (cmake --build build -j)"; exit 2
fi
GRAMMAR_OBJS="$( find "$BUILDDIR/CMakeFiles" -type d -name 'ts_*.dir' -exec find {} -name '*.o' \; 2>/dev/null | sort )"
if [ -z "$GRAMMAR_OBJS" ]; then
    echo "  no compiled grammar objects under $BUILDDIR/CMakeFiles — build first (cmake --build build -j)"; exit 2
fi
echo "fieldidcheck: CXX=$CXX  header=src/infra/fieldid.h  build=$BUILDDIR"

# ── the harness's own grammar objects, compiled here from the vendored sources ─────────────────────────
# The build's grammar objects and libtree-sitter.a are NOT linkable from a plain command on every flavour:
# a Release build (RIPWIRE_LTO implied ON) leaves them as LTO bitcode/GIMPLE, and both ubuntu Release legs
# of PR #127 (gcc AND clang) failed the plain link while every plain leg and every macOS leg (whose linker
# reads bitcode transparently) passed; a `-flto` retry did not close it either. So the gate compiles what
# it links: the SAME sources the build compiled — discovered from the build's own object list, so the
# grammar set cannot drift from CMake's — plus the core's lib.c, at -O1, into $TMP/gobj. ~20 s, once.
CC="${CC:-cc}"
mkdir -p "$TMP/gobj"
TSCORE="$ROOT/third_party/deps/tree_sitter"
"$CC" -O1 -c "$TSCORE/lib/src/lib.c" -I "$TSCORE/lib/include" -I "$TSCORE/lib/src" -o "$TMP/gobj/ts_core.o" 2>"$TMP/gobj/core.log" \
    || { echo "  no self-built tree-sitter core: $( head -3 "$TMP/gobj/core.log" )"; exit 2; }
n_g=0
for obj in $GRAMMAR_OBJS; do
    rel="${obj#*/CMakeFiles/}"; rel="${rel#*.dir/}"; rel="${rel%.o}"     # ts_cpp.dir/third_party/deps/cpp/src/parser.c.o → third_party/deps/cpp/src/parser.c
    src="$ROOT/$rel"; [ -f "$src" ] || { echo "  grammar source missing for $obj: $src"; exit 2; }
    name="$( printf '%s' "$rel" | tr '/' '_' )"
    case "$src" in
        *.cc|*.cpp) "$CXX" "$CXXSTD" -O1 -c "$src" -I "$TSCORE/lib/include" -I "$( dirname "$src" )" -o "$TMP/gobj/$name.o" 2>"$TMP/gobj/$name.log" & ;;
        *)          "$CC"           -O1 -c "$src" -I "$TSCORE/lib/include" -I "$( dirname "$src" )" -o "$TMP/gobj/$name.o" 2>"$TMP/gobj/$name.log" & ;;
    esac
    n_g=$(( n_g + 1 ))
    [ $(( n_g % 6 )) -eq 0 ] && wait
done
wait
n_o="$( ls "$TMP"/gobj/*.o 2>/dev/null | wc -l | tr -d ' ' )"
[ "$n_o" -eq $(( n_g + 1 )) ] || { echo "  self-built grammar objects: $n_o of $(( n_g + 1 )) — $( cat "$TMP"/gobj/*.log | head -5 )"; exit 2; }
echo "  INFO  $n_g grammar source(s) + the core compiled once for the harness ($n_o objects, flavour-independent)"

# ── harvest the field spellings FROM A PRISTINE HEADER ───────────────────────────────────────────────
# Enumerator order and the { "spelling", len } rows, read as TEXT. The harness's reference side uses
# these literals, which is what lets arm D mutate the header under test without moving the reference.
NAMES="$TMP/names.txt"
python3 - "$HDR" > "$NAMES" <<'PYNAMES'
import re, sys
src = open( sys.argv[1] ).read()
enum = re.search( r'enum class NodeField\s*:\s*std::uint8_t\s*\{(.*?)\}', src, re.S )
if enum is None: sys.exit( "could not find enum class NodeField" )
members = [ m.strip() for m in enum.group( 1 ).replace( '\n', ' ' ).split( ',' ) if m.strip() ]
if members[ -1 ] != 'Count': sys.exit( "NodeField's last enumerator must be Count" )
members = members[ :-1 ]
tbl = re.search( r'kNodeFieldNames\s*=\s*\{\s*\{(.*?)\}\s*\}\s*;', src, re.S )
if tbl is None: sys.exit( "could not find kNodeFieldNames" )
rows = re.findall( r'\{\s*"([^"\\]*)"\s*,\s*(\d+)\s*\}', tbl.group( 1 ) )
if len( rows ) != len( members ):
    sys.exit( "kNodeFieldNames has %d rows for %d enumerators" % ( len( rows ), len( members ) ) )
for ( name, length ), member in zip( rows, members ):
    if int( length ) != len( name ):
        sys.exit( 'declared length %s != len("%s")' % ( length, name ) )
    print( "%s\t%s" % ( member, name ) )
PYNAMES
NFIELDS="$( wc -l < "$NAMES" | tr -d ' ' )"
if [ "${NFIELDS:-0}" -lt 20 ]; then
    no "harvested only ${NFIELDS:-0} field spellings from the header — every arm below would be vacuous"
    echo; echo "SOME CHECKS FAILED"; exit 1
fi
ok "harvested $NFIELDS field spellings from src/infra/fieldid.h (enumerator order == kNodeFieldNames order, declared lengths correct)"

# ── harvest the grammar / extension table FROM THE TREE ──────────────────────────────────────────────
ROWS="$TMP/rows.txt"
python3 - "$CRAWL" > "$ROWS" <<'PYROWS'
import re, sys
src = open( sys.argv[1] ).read()
rows = re.findall( r'\{\s*"(\.[A-Za-z0-9_]+)"\s*,\s*Lang::\w+\s*,\s*&(tree_sitter_[A-Za-z0-9_]+)\s*,', src )
for ext, fn in rows:
    print( "%s\t%s" % ( ext, fn ) )
PYROWS
NROWS="$( wc -l < "$ROWS" | tr -d ' ' )"
NGRAMMARS="$( cut -f2 "$ROWS" | sort -u | wc -l | tr -d ' ' )"
if [ "${NROWS:-0}" -lt 30 ] || [ "${NGRAMMARS:-0}" -lt 15 ]; then
    no "harvested only ${NROWS:-0} extension rows / ${NGRAMMARS:-0} grammars from kLangTable — the probe found nothing"
    echo; echo "SOME CHECKS FAILED"; exit 1
fi
ok "harvested $NROWS extension rows over $NGRAMMARS distinct grammars from src/ingest_crawl.h's kLangTable"

# ── F. capacity: every distinct grammar must FIT the registry ────────────────────────────────────────
CAP="$( sed -n 's/.*kFieldIdCapacity *= *\([0-9]*\).*/\1/p' "$HDR" | head -1 )"
if [ -z "${CAP:-}" ]; then
    no "F: could not read kFieldIdCapacity from the header"
elif [ "$NGRAMMARS" -gt "$CAP" ]; then
    no "F: kLangTable names $NGRAMMARS distinct grammars but kFieldIdCapacity is $CAP — the overflow grammars silently keep the by-name path"
else
    ok "F: $NGRAMMARS distinct grammars fit kFieldIdCapacity=$CAP"
fi

# ── pick a fixture file per extension row, from the tree, excluding vendored sources ─────────────────
FIXTURES="$TMP/fixtures.txt"
: > "$FIXTURES"
while IFS="$( printf '\t' )" read -r ext fn; do
    f="$( cd "$ROOT" && git ls-files "*$ext" 2>/dev/null | grep -v '^third_party/' | grep -v '^build/' \
          | while IFS= read -r c; do [ -f "$ROOT/$c" ] && [ "$( wc -c < "$ROOT/$c" | tr -d ' ' )" -lt 262144 ] && { printf '%s\n' "$c"; break; }; done )"
    [ -n "${f:-}" ] && printf '%s\t%s\t%s\n' "$ext" "$fn" "$f" >> "$FIXTURES"
done < "$ROWS"
NFIX="$( wc -l < "$FIXTURES" | tr -d ' ' )"
NFIXG="$( cut -f2 "$FIXTURES" | sort -u | wc -l | tr -d ' ' )"
if [ "${NFIX:-0}" -lt 25 ] || [ "${NFIXG:-0}" -lt 15 ]; then
    no "B: only ${NFIX:-0} extension rows (${NFIXG:-0} grammars) found a fixture file in the tree — arm B would be thin"
else
    ok "B: $NFIX extension rows over $NFIXG grammars have a fixture file in the tree"
fi

# ── the harness generator: shared by the real header and by the mutation copies ──────────────────────
# $1 = include dir holding the fieldid.h under test, $2 = output binary, $3 = compile log
gen_and_build(){
    local incdir="$1" out="$2" log="$3"
    python3 - "$NAMES" "$ROWS" "$FIXTURES" > "$TMP/harness.cpp" <<'PYHARNESS'
import sys
names = [ l.rstrip( "\n" ).split( "\t" ) for l in open( sys.argv[ 1 ] ) if l.strip() ]
rows  = [ l.rstrip( "\n" ).split( "\t" ) for l in open( sys.argv[ 2 ] ) if l.strip() ]
fixes = [ l.rstrip( "\n" ).split( "\t" ) for l in open( sys.argv[ 3 ] ) if l.strip() ]
grammars = sorted( { fn for _, fn in rows } )

print( '#include "fieldid.h"' )
print( """
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <string>
#include <vector>

static int failures = 0;
static void bad( const char* what, const char* g, const char* f, const char* extra )
{
    if( ++failures <= 12 ) { std::printf( "MISMATCH %s grammar=%s field=%s %s\\n", what, g, f, extra ); }
}

// The reference spelling of each field, harvested from a PRISTINE header at gate time. The table under
// test must never be consulted for these — that is the whole point of arm D.
struct Ref { const char* name; unsigned len; };
""" )
print( "static const Ref kRef[] = {" )
for member, name in names:
    print( '    { "%s", %d },' % ( name, len( name ) ) )
print( "};" )
print( "static const std::size_t kNRef = sizeof( kRef ) / sizeof( kRef[0] );" )
print( 'static_assert( kNRef == rw::kNodeFieldCount, "reference table and NodeField disagree on the field count" );' )

print( 'extern "C" {' )
for g in grammars:
    print( "const TSLanguage* %s( void );" % g )
print( "}" )
print( "struct GrammarRow { const char* name; const TSLanguage* ( *fn )( void ); };" )
print( "static const GrammarRow kGrammars[] = {" )
for g in grammars:
    print( '    { "%s", %s },' % ( g, g ) )
print( "};" )
print( "static const std::size_t kNGrammars = sizeof( kGrammars ) / sizeof( kGrammars[0] );" )
print( "struct FixtureRow { const char* ext; const char* grammar; const TSLanguage* ( *fn )( void ); const char* path; };" )
print( "static const FixtureRow kFixtures[] = {" )
for ext, fn, path in fixes:
    print( '    { "%s", "%s", %s, "%s" },' % ( ext, fn, fn, path ) )
print( "};" )
print( "static const std::size_t kNFixtures = sizeof( kFixtures ) / sizeof( kFixtures[0] );" )

print( """
static std::string slurp( const char* path )
{
    std::FILE* fp = std::fopen( path, "rb" );
    if( fp == nullptr ) { return std::string(); }
    std::string out;
    char buf[ 65536 ];
    std::size_t n = 0;
    while( ( n = std::fread( buf, 1, sizeof( buf ), fp ) ) > 0 ) { out.append( buf, n ); }
    std::fclose( fp );
    return out;
}

int main( int argc, char** argv )
{
    const char* root = ( argc > 1 ) ? argv[ 1 ] : ".";

    // ── A0: the UNWARMED path is the by-name answer ────────────────────────────────────────────────
    std::size_t coldPairs = 0;
    for( std::size_t g = 0; g < kNGrammars; ++g )
    {
        const TSLanguage* lang = kGrammars[ g ].fn();
        for( std::size_t f = 0; f < kNRef; ++f )
        {
            const TSFieldId want = ts_language_field_id_for_name( lang, kRef[ f ].name, kRef[ f ].len );
            const TSFieldId got  = rw::fieldIdFor( lang, static_cast< rw::NodeField >( f ) );
            if( want != got ) { bad( "A0", kGrammars[ g ].name, kRef[ f ].name, "cold lookup differs from by-name" ); }
            ++coldPairs;
        }
    }
    if( rw::warmedGrammarCount() != 0 ) { bad( "A0", "-", "-", "registry was not cold at start of run" ); }
    std::printf( "ARM_A0 pairs=%zu\\n", coldPairs );

    // ── A: warm every grammar, then the same equality, plus the registry population ────────────────
    for( std::size_t g = 0; g < kNGrammars; ++g ) { rw::warmFieldIds( kGrammars[ g ].fn() ); }
    for( std::size_t g = 0; g < kNGrammars; ++g ) { rw::warmFieldIds( kGrammars[ g ].fn() ); }   // idempotent
    if( rw::warmedGrammarCount() != kNGrammars )
    {
        std::printf( "MISMATCH A warmedGrammarCount=%zu expected=%zu (a warm was dropped, or warming is not idempotent)\\n",
                     rw::warmedGrammarCount(), kNGrammars );
        ++failures;
    }
    std::size_t warmPairs = 0, zeroIdPairs = 0;
    for( std::size_t g = 0; g < kNGrammars; ++g )
    {
        const TSLanguage* lang = kGrammars[ g ].fn();
        for( std::size_t f = 0; f < kNRef; ++f )
        {
            const TSFieldId want = ts_language_field_id_for_name( lang, kRef[ f ].name, kRef[ f ].len );
            const TSFieldId got  = rw::fieldIdFor( lang, static_cast< rw::NodeField >( f ) );
            if( want != got )
            {
                char extra[ 96 ];
                std::snprintf( extra, sizeof( extra ), "table=%u by-name=%u", unsigned( got ), unsigned( want ) );
                bad( "A", kGrammars[ g ].name, kRef[ f ].name, extra );
            }
            if( want == 0 ) { ++zeroIdPairs; }
            ++warmPairs;
        }
    }
    std::printf( "ARM_A pairs=%zu grammars=%zu fields=%zu zero_id_pairs=%zu\\n", warmPairs, kNGrammars, kNRef, zeroIdPairs );

    // ── C non-vacuity: at least one ( grammar, field ) pair must resolve to id 0, or arm C proves
    //    nothing about the "grammar has no such field" case that 199 single-language sites rely on.
    if( zeroIdPairs == 0 )
    {
        std::printf( "MISMATCH C every grammar has every field — the unknown-field arm is vacuous\\n" );
        ++failures;
    }

    // ── B + C: enumerated ( node, field ) pairs over real parse trees ──────────────────────────────
    std::size_t nodePairs = 0, nodesWalked = 0, filesParsed = 0, nullAgreements = 0;
    TSParser* parser = ts_parser_new();
    for( std::size_t i = 0; i < kNFixtures; ++i )
    {
        const std::string path = std::string( root ) + "/" + kFixtures[ i ].path;
        const std::string src  = slurp( path.c_str() );
        if( src.empty() ) { continue; }
        const TSLanguage* lang = kFixtures[ i ].fn();
        if( !ts_parser_set_language( parser, lang ) ) { continue; }
        TSTree* tree = ts_parser_parse_string( parser, nullptr, src.data(), static_cast< std::uint32_t >( src.size() ) );
        if( tree == nullptr ) { continue; }
        ++filesParsed;
        TSTreeCursor cursor = ts_tree_cursor_new( ts_tree_root_node( tree ) );
        for( ;; )
        {
            const TSNode n = ts_tree_cursor_current_node( &cursor );
            ++nodesWalked;
            for( std::size_t f = 0; f < kNRef; ++f )
            {
                const TSNode want = ts_node_child_by_field_name( n, kRef[ f ].name, kRef[ f ].len );
                const TSNode got  = rw::fieldChild( n, static_cast< rw::NodeField >( f ) );
                const bool   wn   = ts_node_is_null( want );
                const bool   gn   = ts_node_is_null( got );
                if( wn != gn || ( !wn && !ts_node_eq( want, got ) ) )
                {
                    char extra[ 160 ];
                    std::snprintf( extra, sizeof( extra ), "file=%s node=%s byname=%s fieldChild=%s",
                                   kFixtures[ i ].path, ts_node_type( n ),
                                   wn ? "(null)" : ts_node_type( want ), gn ? "(null)" : ts_node_type( got ) );
                    bad( "B", kFixtures[ i ].grammar, kRef[ f ].name, extra );
                }
                if( wn && gn ) { ++nullAgreements; }
                ++nodePairs;
            }
            // depth-first over the WHOLE tree, named and anonymous alike
            if( ts_tree_cursor_goto_first_child( &cursor ) ) { continue; }
            for( ;; )
            {
                if( ts_tree_cursor_goto_next_sibling( &cursor ) ) { break; }
                if( !ts_tree_cursor_goto_parent( &cursor ) ) { goto doneTree; }
            }
        }
    doneTree:
        ts_tree_cursor_delete( &cursor );
        ts_tree_delete( tree );
    }
    ts_parser_delete( parser );
    std::printf( "ARM_B files=%zu nodes=%zu pairs=%zu null_agreements=%zu\\n", filesParsed, nodesWalked, nodePairs, nullAgreements );
    if( filesParsed < 15 || nodePairs < 100000 )
    {
        std::printf( "MISMATCH B only %zu files / %zu pairs walked — too thin to be evidence\\n", filesParsed, nodePairs );
        ++failures;
    }

    // ── C: the id-0 contract, asserted directly rather than inferred from the walk ─────────────────
    {
        TSParser* p2 = ts_parser_new();
        ts_parser_set_language( p2, kGrammars[ 0 ].fn() );
        const char* tiny = "int f( int a ) { return a; }\\n";
        TSTree* t2 = ts_parser_parse_string( p2, nullptr, tiny, static_cast< std::uint32_t >( std::strlen( tiny ) ) );
        const TSNode r = ts_tree_root_node( t2 );
        if( !ts_node_is_null( ts_node_child_by_field_id( r, 0 ) ) )
        {
            std::printf( "MISMATCH C ts_node_child_by_field_id( n, 0 ) is not the null node — the whole unknown-field contract rests on this\\n" );
            ++failures;
        }
        if( !ts_node_is_null( ts_node_child_by_field_name( r, "no_such_field_anywhere", 22 ) ) )
        {
            std::printf( "MISMATCH C by-name lookup of an absent field is not null\\n" );
            ++failures;
        }
        ts_tree_delete( t2 );
        ts_parser_delete( p2 );
    }

    if( failures != 0 ) { std::printf( "FAILURES %d\\n", failures ); return 1; }
    std::printf( "UNIT_OK\\n" );
    return 0;
}
""" )
PYHARNESS
    "$CXX" "$CXXSTD" -O1 -g -Wall -Wextra \
        -I "$incdir" -I "$ROOT/third_party/deps/tree_sitter/lib/include" \
        "$TMP/harness.cpp" "$TMP"/gobj/*.o -o "$out" 2>"$log"
}

# ── A0/A/B/C against the real header ─────────────────────────────────────────────────────────────────
mkdir -p "$TMP/real" && cp "$HDR" "$TMP/real/fieldid.h"
if ! gen_and_build "$TMP/real" "$TMP/real.bin" "$TMP/real.cc.log"; then
    no "harness does not compile/link against the real fieldid.h"
    sed 's/^/    /' "$TMP/real.cc.log" | head -25
else
    if "$TMP/real.bin" "$ROOT" > "$TMP/real.out" 2>&1; then
        grep -q UNIT_OK "$TMP/real.out" || no "harness exited 0 without UNIT_OK"
        ok "A0: unwarmed fieldIdFor == ts_language_field_id_for_name — $( grep -o 'ARM_A0 pairs=[0-9]*' "$TMP/real.out" )"
        ok "A: warm table == by-name resolution — $( sed -n 's/^ARM_A //p' "$TMP/real.out" )"
        ok "C: id-0 is the null node, and the zero-id case is non-vacuous ($( sed -n 's/.*zero_id_pairs=\([0-9]*\).*/\1/p' "$TMP/real.out" ) grammar-field pairs have no such field)"
        ok "B: fieldChild == ts_node_child_by_field_name on every node of every fixture — $( sed -n 's/^ARM_B //p' "$TMP/real.out" )"
    else
        no "A/B/C: harness failed"
        sed 's/^/    /' "$TMP/real.out" | head -16
    fi
fi

# ── D. the mutation arms — each must FAIL ────────────────────────────────────────────────────────────
# D1: misspell ONE field's row in kNodeFieldNames. The table's entry for that field becomes a different
#     id (usually 0) in every grammar, and arms A and B must both see it. The reference side is unmoved
#     because the harness's literals came from the pristine header above.
mkdir -p "$TMP/mut1"
sed 's/{ "name", 4 }/{ "nane", 4 }/' "$HDR" > "$TMP/mut1/fieldid.h"
if ! grep -q '"nane"' "$TMP/mut1/fieldid.h"; then
    no "D1: could not apply the misspelling mutation — kNodeFieldNames' row for \"name\" moved, so this arm proves nothing"
elif ! gen_and_build "$TMP/mut1" "$TMP/mut1.bin" "$TMP/mut1.cc.log"; then
    no "D1: mutated header does not compile — the mutation must produce a WRONG build, not a broken one"
elif "$TMP/mut1.bin" "$ROOT" > "$TMP/mut1.out" 2>&1; then
    no "D1: arms A/B stayed GREEN with one field's spelling corrupted in the table — they cannot fail"
else
    ok "D1: arms A/B go red when one row of kNodeFieldNames is misspelled ($( sed -n 's/^FAILURES //p' "$TMP/mut1.out" ) disagreements)"
fi

# D2: shift the field index inside the LOOKUP rather than the data. Every warm grammar then answers with
#     its neighbour field's id — a defect no amount of checking the table's contents would catch.
mkdir -p "$TMP/mut2"
sed 's/return registry.ids\[ i \]\[ f \];/return registry.ids[ i ][ ( f + 1 ) % kNodeFieldCount ];/' "$HDR" > "$TMP/mut2/fieldid.h"
if ! grep -q 'f + 1 ) % kNodeFieldCount' "$TMP/mut2/fieldid.h"; then
    no "D2: could not apply the index-shift mutation — fieldIdFor's return moved, so this arm proves nothing"
elif ! gen_and_build "$TMP/mut2" "$TMP/mut2.bin" "$TMP/mut2.cc.log"; then
    no "D2: mutated header does not compile"
elif "$TMP/mut2.bin" "$ROOT" > "$TMP/mut2.out" 2>&1; then
    no "D2: arms A/B stayed GREEN with the lookup reading the wrong field slot — they cannot fail"
else
    ok "D2: arms A/B go red when the lookup reads the neighbouring field's id ($( sed -n 's/^FAILURES //p' "$TMP/mut2.out" ) disagreements)"
fi

# ── E. population: the conversion is still the conversion ────────────────────────────────────────────
# A FUNCTION OVER A DIRECTORY, not a straight-line grep of $ROOT, for the same reason nodekindcheck's
# arm D is: the mutation control has to run it against a REVERTED copy of the tree, and a gate that can
# only look at its own checkout cannot be shown to fail. Never mutate $ROOT itself.
checkPopulation(){                   # $1 = tree root to inspect; prints one line per violation, empty = clean
    local root="$1" f n k
    for f in $SITE_FILES; do
        [ -f "$root/$f" ] || { printf '%s: MISSING\n' "$f"; continue; }
        n="$( grep -c 'ts_node_child_by_field_name' "$root/$f" 2>/dev/null || true )"
        k="$( grep -c 'fieldChild(\|NodeField::' "$root/$f" 2>/dev/null || true )"
        [ "${n:-0}" -ne 0 ] && printf '%s: %s ts_node_child_by_field_name site(s) left\n' "$f" "$n"
        [ "${k:-0}" -lt 2 ] && printf '%s: only %s fieldChild/NodeField site(s) — not on the field-id table\n' "$f" "${k:-0}"
    done
    return 0
}

violations="$( checkPopulation "$ROOT" )"
if [ -n "$violations" ]; then
    printf '%s\n' "$violations" | while IFS= read -r v; do no "E: $v"; done
    fail=1
else
    TOTALSITES="$( cd "$ROOT" && grep -ho 'fieldChild(' $SITE_FILES | wc -l | tr -d ' ' )"
    if [ "${TOTALSITES:-0}" -lt 150 ]; then
        no "E: only ${TOTALSITES:-0} fieldChild( sites across the converted files — the 199-site conversion has been eroded"
    else
        ok "E: all $( echo $SITE_FILES | wc -w | tr -d ' ' ) converted files are on fieldChild ($TOTALSITES sites), with no ts_node_child_by_field_name left"
    fi
fi

# E-warm: the per-grammar warm must actually be wired into the ingest translation unit, over kLangTable.
checkWarmSite(){                     # $1 = tree root; prints one line per violation, empty = clean
    local root="$1"
    grep -q 'warmFieldIds(' "$root/src/ingest_crawl.h" 2>/dev/null \
        || printf 'src/ingest_crawl.h: no warmFieldIds( ) call — nothing fills the table\n'
    grep -q 'kLangTable' "$root/src/ingest_crawl.h" 2>/dev/null \
        || printf 'src/ingest_crawl.h: the warm does not walk kLangTable\n'
    grep -q 'warmFieldIdTable( *)' "$root/src/ingest.cpp" 2>/dev/null \
        || printf 'src/ingest.cpp: ingest() never calls warmFieldIdTable() — every grammar takes the by-name fallback\n'
    return 0
}
warmViolations="$( checkWarmSite "$ROOT" )"
if [ -n "$warmViolations" ]; then
    printf '%s\n' "$warmViolations" | while IFS= read -r v; do no "E-warm: $v"; done
    fail=1
else
    ok "E-warm: the per-grammar warm is wired over kLangTable and called from ingest()"
fi

# E-mut: the revert control. A scratch copy of the converted files is rewritten back to the by-name form
# — every `NodeField::X` to its spelling and every `fieldChild(` to `ts_node_child_by_field_name(` — and
# arm E's own function must report EVERY one of them. The count is of FILES reported, not of one
# violation shape, because the two shapes are file-dependent: a file whose sites are all direct reports
# "sites left", while src/slice.h (which reads fields through three wrappers over ONE fieldChild) reports
# the population floor instead. Requiring all nine files either way is what rules out a blind file.
mkdir -p "$TMP/reverted/src"
revertedFiles=0
for f in $SITE_FILES; do
    if python3 - "$ROOT/$f" "$TMP/reverted/$f" "$NAMES" <<'PYREVERT'
import re, sys
spell = dict( l.rstrip( "\n" ).split( "\t" ) for l in open( sys.argv[ 3 ] ) if l.strip() )
src = open( sys.argv[ 1 ] ).read()
out, n1 = re.subn( r'NodeField::(\w+)', lambda m: '"%s"' % spell.get( m.group( 1 ), m.group( 1 ) ), src )
out, n2 = re.subn( r'\bfieldChild\(', 'ts_node_child_by_field_name(', out )
open( sys.argv[ 2 ], 'w' ).write( out )
sys.exit( 0 if ( n1 + n2 ) > 0 else 1 )
PYREVERT
    then revertedFiles=$(( revertedFiles + 1 )); fi
done
NSITEFILES="$( echo $SITE_FILES | wc -w | tr -d ' ' )"
if [ "$revertedFiles" -ne "$NSITEFILES" ]; then
    no "E-mut: could only build a reverted copy of $revertedFiles of $NSITEFILES converted file(s) — the control cannot prove arm E fires"
else
    mutFiles="$( checkPopulation "$TMP/reverted" | cut -d: -f1 | sort -u | wc -l | tr -d ' ' )"
    if [ "${mutFiles:-0}" -eq "$NSITEFILES" ]; then
        ok "E-mut: arm E goes red on a full revert of the change — all $mutFiles file(s) reported (it is not green in both directions)"
    else
        no "E-mut: a full revert left arm E green on $(( NSITEFILES - ${mutFiles:-0} )) of $NSITEFILES file(s) — the arm has a blind file"
    fi
fi

# E-warm-mut: deleting the warm call must make E-warm report it.
mkdir -p "$TMP/nowarm/src"
cp "$ROOT/src/ingest_crawl.h" "$TMP/nowarm/src/ingest_crawl.h"
sed 's/warmFieldIdTable( *)/\/* removed by E-warm-mut *\//' "$ROOT/src/ingest.cpp" > "$TMP/nowarm/src/ingest.cpp"
if grep -q 'warmFieldIdTable( *)' "$TMP/nowarm/src/ingest.cpp"; then
    no "E-warm-mut: could not remove the warm call from a scratch copy — the control proves nothing"
elif [ -z "$( checkWarmSite "$TMP/nowarm" )" ]; then
    no "E-warm-mut: E-warm stayed green with the warm call deleted — the arm cannot fail"
else
    ok "E-warm-mut: E-warm goes red when ingest() stops calling warmFieldIdTable()"
fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi

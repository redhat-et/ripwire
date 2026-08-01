// columnar_comma_test.cpp — A4-F15 unit-style gate: emitColumnarSymbolRows / emitColumnarUseSites must not
// mis-zip parallel arrays when an emitted value (a markdown SECTION name, or an enclosing-symbol `in` name)
// contains a literal ','. Standalone (no CMake wiring — compiled directly by columnarcommacheck.sh) because
// the real end-to-end CLI path to get a comma into a `name`/`in` field needs a markdown section symbol that
// the flat-list verbs don't naturally surface; this drives the emission functions directly with a synthetic
// IngestResult, which is the more precise and deterministic gate for exactly this code path.
//
// Prints one line per array: "<tag> fields=<N>" where N is the array's comma-split field count as a NAIVE
// consumer (splitting on raw ',') would see it. The driver script asserts N == row count (proves the comma
// inside a value did NOT get treated as a field separator) and separately that after un-escaping '&#44;' the
// original comma-bearing value round-trips.

#include "../../src/columnar.h"

#include <cstdio>
#include <cstdlib>

using namespace rw;

int main( int argc, char** argv )
{
    if( argc < 2 ) { std::fprintf( stderr, "usage: %s OUTFILE\n", argv[0] ); return 2; }

    IngestResult ing;
    ing.files = { "docs/notes.md", "src/thing.cpp" };

    // three symbols: a plain function, a markdown SECTION whose name contains a comma, and another function.
    Symbol a; a.id = 0; a.kind = SymKind::Function; a.fileId = 1; a.line = 10; a.name = "loadThing";
    Symbol b; b.id = 1; b.kind = SymKind::Section;  b.fileId = 0; b.line = 3;  b.name = "results, discussion";
    Symbol c; c.id = 2; c.kind = SymKind::Function; c.fileId = 1; c.line = 42; c.name = "saveThing";
    ing.symbols = { a, b, c };

    std::FILE* out = std::fopen( argv[1], "wb" );
    if( !out ) { std::fprintf( stderr, "cannot open %s\n", argv[1] ); return 2; }

    // (1) emitColumnarSymbolRows: the `name` array must carry 3 fields for 3 rows, comma-in-value escaped.
    std::fprintf( out, "SYMROWS_BEGIN\n" );
    emitColumnarSymbolRows( out, ing, "callers", "of=\"x\" count=\"3\"", { 0, 1, 2 } );
    std::fprintf( out, "\nSYMROWS_END\n" );

    // (2) emitColumnarUseSites: the `in` array must carry 2 fields for 2 rows, one of which is the
    //     comma-bearing section name (a code reference whose enclosing symbol happens to be that section).
    std::vector<std::uint32_t> fileIds = { 1, 0 };
    std::vector<std::uint32_t> lines   = { 11, 4 };
    std::vector<RefRole>       roles   = { RefRole::Call, RefRole::Read };
    std::vector<std::string>   inNames = { "saveThing", "results, discussion" };
    std::fprintf( out, "USESROWS_BEGIN\n" );
    emitColumnarUseSites( out, ing, "sym=\"loadThing\" count=\"2\"", fileIds, lines, roles, inNames );
    std::fprintf( out, "\nUSESROWS_END\n" );

    std::fclose( out );
    return 0;
}

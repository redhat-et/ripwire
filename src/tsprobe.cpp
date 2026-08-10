// tsprobe.cpp — Phase 1/2 PROOF binary.
//
// Usage: ripwire_probe <directory>
// Crawls the directory, runs ingest(), and prints:
//   - file count, symbol count by kind, reference count;
//   - the first ~40 symbols (name / kind / lang / file:line) each followed by its references.
// This is the human-readable evidence that tree-sitter + the tags queries extract real
// symbols and call references across every language the ingest table knows.

#include "ingest.h"
#include "model.h"

#include "infra/Diagnostics.h"   // VERIFY — the enum-index bounds check

#include <array>
#include <cstddef>
#include <cstdio>
#include <iterator>
#include <string>
#include <vector>

namespace
{

// Lang → its terse label, a declarative table indexed by the enum value (not a switch chain), in enum
// order. The static_assert is the real guard: this file used to carry a 5-arm switch and a hardcoded
// `std::array<int, 6>` counter beside it, so every language appended to Lang after the original five
// printed "?" and — worse — indexed the counter array off its end. A plain .c corpus (Lang::C == 15)
// crashed ripwire_probe outright (H4 grammar survey). Sized off the enum, the next append breaks the
// BUILD here instead.
// The "?" at index 12 is Lang::Unknown's own label, not a hole — the enum keeps Unknown mid-table so
// serialize.h's calibration array can size on it (model.h documents why), and ingest never assigns it.
inline constexpr const char* kLangName[] = {
    "cpp", "py", "ts", "go", "rust", "swift", "objc", "md", "js", "sh", "java", "rb", "?", "json", "cs", "c",
};

static_assert( std::size( kLangName ) == std::size_t( rw::Lang::C ) + 1,
               "kLangName drifted from the Lang enum — update both together" );

// SymKind has no table here: rw::symTag() already IS the declarative one. Only its count is needed,
// and it is derived the same way — `Other` is the last kind, so an appended kind resizes the counter.
inline constexpr std::size_t kSymKindCount = std::size_t( rw::SymKind::Other ) + 1;

// A Lang / SymKind reaching these out of range means a symbol carries a value its own enum does not
// name — a corrupt invariant, not a recoverable input, so VERIFY (free in release) and no fallback:
// the static_assert above already proves every in-range value has a row.
std::size_t langIndex( rw::Lang l ) noexcept
{
    VERIFY( std::size_t( l ) < std::size( kLangName ) );
    return std::size_t( l );
}

std::size_t kindIndex( rw::SymKind k ) noexcept
{
    VERIFY( std::size_t( k ) < kSymKindCount );
    return std::size_t( k );
}

const char* langName( rw::Lang l ) noexcept
{
    return kLangName[ langIndex( l ) ];
}

}   // namespace

int main( int argc, char** argv )
{
    if( argc < 2 )
    {
        std::fprintf( stderr, "usage: %s <directory>\n", argv[ 0 ] );
        return 1;
    }

    const char* root = argv[ 1 ];
    const rw::IngestResult ir = rw::ingest( root );

    // ---- counts by kind ----
    std::array<int, kSymKindCount> kindCount {};            // indexed by SymKind underlying value
    for( const rw::Symbol& s : ir.symbols )
    {
        ++kindCount[ kindIndex( s.kind ) ];
    }

    // ---- counts by language (defs) ----
    std::array<int, std::size( kLangName )> langCount {};   // indexed by Lang underlying value
    for( const rw::Symbol& s : ir.symbols )
    {
        ++langCount[ langIndex( s.lang ) ];
    }

    std::printf( "==== ripwire ingest probe ====\n" );
    std::printf( "root:        %s\n", root );
    std::printf( "files:       %zu\n", ir.files.size() );
    std::printf( "symbols:     %zu\n", ir.symbols.size() );
    std::printf( "references:  %zu\n", ir.references.size() );

    // every kind, zeros included — a kind the corpus does NOT have is evidence too, and there are only
    // eight of them. `sec` (markdown heading) and `other` used to be off the end of the printf.
    std::printf( "\nsymbols by kind:\n " );
    for( std::size_t kind = 0; kind < kSymKindCount; ++kind )
    {
        std::printf( "  %s=%d", rw::symTag( static_cast<rw::SymKind>( kind ) ), kindCount[ kind ] );
    }
    std::printf( "\n" );

    // languages: only the ones that ACTUALLY appear — sixteen rows of mostly zeros is noise, and what
    // the probe is evidence FOR is which grammars extracted something.
    std::printf( "\ndefs by language:\n " );
    {
        int langsShown = 0;
        for( std::size_t lang = 0; lang < std::size( kLangName ); ++lang )
        {
            if( langCount[ lang ] == 0 )
            {
                continue;
            }

            std::printf( "  %s=%d", kLangName[ lang ], langCount[ lang ] );
            ++langsShown;
        }

        if( langsShown == 0 )
        {
            std::printf( "  (no defs)" );
        }
    }
    std::printf( "\n" );

    // ---- references resolved vs file-scope (fromSymbol == kNoNode) ----
    {
        std::size_t attributed = 0;
        for( const rw::Reference& r : ir.references )
        {
            if( r.fromSymbol != rw::kNoNode )
            {
                ++attributed;
            }
        }
        std::printf( "\nreferences attributed to an enclosing symbol: %zu / %zu (rest are file-scope)\n",
                     attributed, ir.references.size() );
    }

    // ---- index references by their enclosing symbol for the per-symbol dump ----
    rw::HashMap<rw::NodeId, std::vector<const rw::Reference*>> bySym;
    for( const rw::Reference& r : ir.references )
    {
        if( r.fromSymbol != rw::kNoNode )
        {
            bySym[ r.fromSymbol ].push_back( &r );
        }
    }

    // ---- first ~40 symbols + their references ----
    const std::size_t showN = ir.symbols.size() < 40 ? ir.symbols.size() : 40;
    std::printf( "\n---- first %zu symbols (name | kind | lang | file:line  -> references) ----\n", showN );

    for( std::size_t i = 0; i < showN; ++i )
    {
        const rw::Symbol& s = ir.symbols[ i ];
        const char* file = ( s.fileId < ir.files.size() ) ? ir.files[ s.fileId ].c_str() : "?";

        std::printf( "[%4u] %-28s %-7s %-4s  %s:%u\n",
                     s.id, s.name.c_str(), rw::symTag( s.kind ), langName( s.lang ), file, s.line );

        auto it = bySym.find( s.id );
        if( it != bySym.end() )
        {
            int shown = 0;
            std::printf( "        calls:" );
            for( const rw::Reference* r : it->second )
            {
                std::printf( " %s", r->calleeName.c_str() );
                if( ++shown >= 12 )
                {
                    std::printf( " ..." );
                    break;
                }
            }
            std::printf( "\n" );
        }
    }

    return 0;
}

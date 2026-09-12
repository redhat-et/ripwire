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
#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings


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
    "cpp", "py", "ts", "go", "rust", "swift", "objc", "md", "js", "sh", "java", "rb", "?", "json", "cs", "c", "toml", "yaml",
    "php", "lua", "ex", "dart", "kt",
};

static_assert( std::size( kLangName ) == rw::kLangCount,
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
        rw::emitTo( stderr, "usage: {} <directory>\n", argv[ 0 ] );
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

    rw::emitRaw( stdout, "==== ripwire ingest probe ====\n" );
    rw::emitTo( stdout, "root:        {}\n", root );
    rw::emitTo( stdout, "files:       {}\n", ir.files.size() );
    rw::emitTo( stdout, "symbols:     {}\n", ir.symbols.size() );
    rw::emitTo( stdout, "references:  {}\n", ir.references.size() );

    // every kind, zeros included — a kind the corpus does NOT have is evidence too, and there are only
    // eight of them. `sec` (markdown heading) and `other` used to be off the end of the printf.
    rw::emitRaw( stdout, "\nsymbols by kind:\n " );
    for( std::size_t kind = 0; kind < kSymKindCount; ++kind )
    {
        rw::emitTo( stdout, "  {}={}", rw::symTag( static_cast<rw::SymKind>( kind ) ), kindCount[ kind ] );
    }
    rw::emitRaw( stdout, "\n" );

    // languages: only the ones that ACTUALLY appear — sixteen rows of mostly zeros is noise, and what
    // the probe is evidence FOR is which grammars extracted something.
    rw::emitRaw( stdout, "\ndefs by language:\n " );
    {
        int langsShown = 0;
        for( std::size_t lang = 0; lang < std::size( kLangName ); ++lang )
        {
            if( langCount[ lang ] == 0 )
            {
                continue;
            }

            rw::emitTo( stdout, "  {}={}", kLangName[ lang ], langCount[ lang ] );
            ++langsShown;
        }

        if( langsShown == 0 )
        {
            rw::emitRaw( stdout, "  (no defs)" );
        }
    }
    rw::emitRaw( stdout, "\n" );

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
        rw::emitTo( stdout, "\nreferences attributed to an enclosing symbol: {} / {} (rest are file-scope)\n",
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
    rw::emitTo( stdout, "\n---- first {} symbols (name | kind | lang | file:line  -> references) ----\n", showN );

    for( std::size_t i = 0; i < showN; ++i )
    {
        const rw::Symbol& s = ir.symbols[ i ];
        const char* file = ( s.fileId < ir.files.size() ) ? ir.files[ s.fileId ].c_str() : "?";

        rw::emitTo( stdout, "[{:>4}] {:<28} {:<7} {:<4}  {}:{}\n",
                     s.id, s.name.c_str(), rw::symTag( s.kind ), langName( s.lang ), file, s.line );

        auto it = bySym.find( s.id );
        if( it != bySym.end() )
        {
            int shown = 0;
            rw::emitRaw( stdout, "        calls:" );
            for( const rw::Reference* r : it->second )
            {
                rw::emitTo( stdout, " {}", r->calleeName.c_str() );
                if( ++shown >= 12 )
                {
                    rw::emitRaw( stdout, " ..." );
                    break;
                }
            }
            rw::emitRaw( stdout, "\n" );
        }
    }

    return 0;
}

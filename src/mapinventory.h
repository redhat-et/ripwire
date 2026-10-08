#pragma once
// mapinventory.h — the default map's INVENTORY TIER (<inv>): every indexed file the ranked rows did not show is
// named (code) or counted (tests, docs, examples, config), and the program entry points are named.
//
// WHY. The ranked map prints the top-k symbols (200 by default), which covers a few dozen files of a few hundred. On
// orient questions ("map this codebase: subsystems, key files, entry points") that cut WAS the miss: subsystem files
// ranked just below it (tmux input.c #208, key-bindings.c #202 of 6361) were absent with nothing saying they existed.
// Entry points are structurally worse: `main` has no in-repo caller, so PageRank ranks it at the bottom (htop main
// #2548 of 3206) and no re-rank can surface it without demoting something else. An inventory is complete and
// disclosed where a re-rank would only move the miss.
//
// WHAT. computeMapInventory is the ONE selection both dialects render (serialize.h: the XML <inv> element and the
// JSON "inv" object), so they cannot disagree on what was listed. It reads only the index and the call graph; it
// never touches the rank vector or the ranked rows (the tier is appended after them).
//   • entries — a def named `main` (`Main` for a method: C#) whose only in-repo callers are its OWN file's module
//     scope (C/C++/Go/Rust/Java/Kotlin main has none; Python's `if __name__ == "__main__": main()` is that scope),
//     plus a Python `__main__.py` module scope. Outside test paths and the rolled-up directories below. By NAME
//     CONVENTION, language-neutral: no language is special-cased. Not detected (stated in the legend): package or
//     library entries declared in a manifest (package.json main/bin/exports, console_scripts, Cargo [[bin]]) — the
//     index does not read manifests as entry declarations.
//   • ls rows — per directory, the unshown files: code files NAMED (basename), every other file COUNTED. A file under
//     a test/bench/fixture/example/doc directory rolls up to that directory (counted, never named): those trees are
//     large (textual's docs/examples, tmux's regress) and are not where an orient answer's key files live.
#include <algorithm>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include "model.h"
#include "filter.h"   // isTestPath / isTestSymbol / pathTierOf / hasDirSegment — the shared test-path conventions

namespace rw
{

struct MapInventoryDir
{
    std::string                dir;     // root-relative directory ("." for the root); a rolled-up subtree's top dir
    std::uint32_t              total = 0;   // unshown files under it
    std::vector<std::uint32_t> named;   // the code files among them (file ids, path order)
};

struct MapInventory
{
    bool                       active   = false;   // false ⇒ the tier is not emitted at all (byte-identical map)
    std::size_t                listed   = 0;       // files the ranked rows showed (the map's <f> groups)
    std::size_t                unlisted = 0;       // every other indexed file; listed + unlisted = files=
    std::vector<NodeId>        entries;            // path order, then symbol id
    std::vector<MapInventoryDir> dirs;             // path order
};

// Directory components whose subtree rolls up count-only. pathTierOf's test/bench/fixture conventions plus the
// presentational ones (examples, docs, regress, samples) — local to the inventory on purpose: widening pathTierOf
// itself would re-tier --grep/--callers ordering on every verb.
inline constexpr std::string_view kInventoryRollupDirs[] = {
    "test/", "tests/", "__tests__/", "spec/", "specs/", "bench/", "benches/", "benchmarks/", "fixture/", "fixtures/",
    "testdata/", "example/", "examples/", "doc/", "docs/", "regress/", "sample/", "samples/",
};

// The rolled-up directory a root-relative path falls under: the prefix through the FIRST matching component, or empty.
inline std::string_view inventoryRollupDirOf( std::string_view rel ) noexcept
{
    std::size_t best = std::string_view::npos;
    std::size_t bestLen = 0;
    for( std::string_view seg : kInventoryRollupDirs )
    {
        std::size_t pos = 0;
        while( ( pos = rel.find( seg, pos ) ) != std::string_view::npos )
        {
            if( pos == 0 || rel[ pos - 1 ] == '/' )
            {
                if( pos < best ) { best = pos;  bestLen = seg.size(); }
                break;
            }
            ++pos;
        }
    }
    if( best == std::string_view::npos )
    {
        return {};
    }
    return rel.substr( 0, best + bestLen - 1 );   // without the trailing '/'
}

inline std::string_view inventoryDirOf( std::string_view rel ) noexcept
{
    const std::size_t slash = rel.rfind( '/' );
    return slash == std::string_view::npos ? std::string_view( "." ) : rel.substr( 0, slash );
}

inline std::string_view inventoryBaseOf( std::string_view rel ) noexcept
{
    const std::size_t slash = rel.rfind( '/' );
    return slash == std::string_view::npos ? rel : rel.substr( slash + 1 );
}

// A code symbol: anything a reader can open as a definition — not a data Section (doc heading, JSON/YAML key) and
// not the synthetic module-scope row every script file carries.
inline bool isInventoryCodeSymbol( const Symbol& s ) noexcept
{
    return s.kind != SymKind::Section && s.kind != SymKind::ModuleScope;
}

// `shownFile[f]` != 0 ⇔ the ranked rows printed a <f> group for file f. `pathRel` maps a file id to its display path
// (the same root-relative form every <f p=> uses).
template <class PathRel>
inline MapInventory computeMapInventory( const IngestResult& ing, const std::vector<std::uint32_t>& outOff,
                                         const std::vector<NodeId>& outTargets, const std::vector<char>& shownFile,
                                         const PathRel& pathRel )
{
    const std::size_t F = ing.files.size();
    const std::size_t S = ing.symbols.size();
    EXPECTS( shownFile.size() == F, "one shown bit per indexed file" );
    EXPECTS( outOff.size() >= S + 1 || S == 0, "outOff is the CSR offset array over the symbols" );
    MapInventory inv;

    // code symbols per file: a file with none is counted, never named
    std::vector<std::uint32_t> codeSyms( F, 0 );
    for( const Symbol& s : ing.symbols )
    {
        if( s.fileId < F && isInventoryCodeSymbol( s ) )
        {
            ++codeSyms[ s.fileId ];
        }
    }
    // Present-only: the tier rides a map whose ranked rows LEFT OUT a file with code in it. A map that shows every
    // such file has nothing to inventory (its unshown files are empty or data-only) and stays byte-identical.
    bool anyCut = false;
    for( std::size_t f = 0; f < F; ++f )
    {
        if( !shownFile[ f ] ) { ++inv.unlisted; } else { ++inv.listed; }
        anyCut = anyCut || ( !shownFile[ f ] && codeSyms[ f ] > 0 );
    }
    if( !anyCut )
    {
        return MapInventory{};
    }
    inv.active = true;

    // ── entries ──
    const auto isEntryName = [ & ]( const Symbol& s ) noexcept
    {
        return ( s.kind == SymKind::Function && s.name == "main" )
            || ( s.kind == SymKind::Method && ( s.name == "main" || s.name == "Main" ) );
    };
    const auto entryEligibleFile = [ & ]( std::uint32_t f ) noexcept
    {
        const std::string_view rel = rootRelPath( ing, f );
        return !isTestPath( rel ) && inventoryRollupDirOf( rel ).empty();
    };
    std::vector<char> candidate( S, 0 );
    for( NodeId id = 0; id < S; ++id )
    {
        const Symbol& s = ing.symbols[ id ];
        candidate[ id ] = isEntryName( s ) && s.fileId < F && !isTestSymbol( ing, id ) && entryEligibleFile( s.fileId );
    }
    // a candidate with an in-repo caller other than its own file's module scope is a library function, not an entry
    for( NodeId caller = 0; caller < S; ++caller )
    {
        const Symbol& c = ing.symbols[ caller ];
        for( std::uint32_t e = outOff[ caller ]; e < outOff[ caller + 1 ]; ++e )
        {
            const NodeId t = outTargets[ e ];
            if( t < S && candidate[ t ] && !( c.kind == SymKind::ModuleScope && c.fileId == ing.symbols[ t ].fileId ) )
            {
                candidate[ t ] = 0;
            }
        }
    }
    for( NodeId id = 0; id < S; ++id )
    {
        const Symbol& s = ing.symbols[ id ];
        const bool mainModule = s.kind == SymKind::ModuleScope && s.fileId < F
                             && inventoryBaseOf( rootRelPath( ing, s.fileId ) ) == "__main__.py" && entryEligibleFile( s.fileId );
        if( candidate[ id ] || mainModule )
        {
            inv.entries.push_back( id );
        }
    }
    std::stable_sort( inv.entries.begin(), inv.entries.end(), [ & ]( NodeId a, NodeId b )
    { return pathRel( ing.symbols[ a ].fileId ) < pathRel( ing.symbols[ b ].fileId ); } );

    // ── ls rows ──
    std::vector<std::uint32_t> unshown;
    for( std::uint32_t f = 0; f < F; ++f )
    {
        if( !shownFile[ f ] ) { unshown.push_back( f ); }
    }
    // group key: the rolled-up dir when the file sits under one, else its own dir
    struct Keyed { std::string key; bool rolled; std::uint32_t f; };
    std::vector<Keyed> keyed;
    keyed.reserve( unshown.size() );
    for( std::uint32_t f : unshown )
    {
        // classify on the ROOT-RELATIVE path (a checkout living under a tests/ dir is not a test tree — #228), group
        // and print in the display form every <f p=> uses
        const std::string_view rel    = rootRelPath( ing, f );
        const std::string_view disp   = pathRel( f );
        const std::string_view rolled = inventoryRollupDirOf( rel );
        if( rolled.empty() )
        {
            keyed.push_back( Keyed{ std::string( inventoryDirOf( disp ) ), false, f } );
            continue;
        }
        const std::size_t prefix = disp.ends_with( rel ) ? disp.size() - rel.size() : 0;
        keyed.push_back( Keyed{ std::string( disp.substr( 0, prefix ) ) + std::string( rolled ), true, f } );
    }
    std::stable_sort( keyed.begin(), keyed.end(), [ & ]( const Keyed& a, const Keyed& b )
    { return a.key != b.key ? a.key < b.key : pathRel( a.f ) < pathRel( b.f ); } );
    for( const Keyed& k : keyed )
    {
        if( inv.dirs.empty() || inv.dirs.back().dir != k.key )
        {
            inv.dirs.push_back( MapInventoryDir{ k.key, 0, {} } );
        }
        MapInventoryDir& d = inv.dirs.back();
        ++d.total;
        if( !k.rolled && codeSyms[ k.f ] > 0 && !isTestPath( rootRelPath( ing, k.f ) ) )
        {
            d.named.push_back( k.f );
        }
    }
    ENSURES( inv.listed + inv.unlisted == F, "every indexed file is listed or inventoried" );
    return inv;
}

// The legend clause (full dialect). No double hyphen: it rides inside an XML comment (G4).
inline constexpr std::string_view kMapInventoryLegend =
    "<!-- inv: the files the ranked rows above do not show, so no indexed file is silently absent; names only, weaker "
    "evidence than a ranked row. listed= files shown above, unlisted= the rest (listed+unlisted = files=). entry p= n=: a "
    "program entry by name convention, a def named main that nothing in the repo calls but its own file's module scope, "
    "or a __main__.py module scope, with its resolved callees as c rows; entries declared only in a manifest (package.json "
    "main/bin, console_scripts) are not detected. ls p= n= f=: n= unshown files under directory p=, f= the code files "
    "among them by name; test, doc and config files are counted, not named, and a test/bench/fixture/example/doc "
    "directory rolls up whole. ripwire on p= ranks that directory -->";

}  // namespace rw

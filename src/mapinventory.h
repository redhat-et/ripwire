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
//   • entries — a def named `main` by each language's OWN entry convention, never by the name alone:
//       – a Function `main` with no in-repo caller in a language whose entry IS such a function (C, C++, ObjC, Go,
//         Rust, Kotlin, Dart);
//       – a Method `main`/`Main` with no in-repo caller only where the entry is a static method (Java, C#);
//       – a Function `main` in a module-scope language (Python, JS, TS, Ruby, Bash, PHP, Lua) only when its OWN
//         file's module scope calls it and nothing else does (Python's `if __name__ == "__main__": main()`, Bash's
//         `main "$@"`, a script's top-level `main()`): an uncalled `main` there is a library function or dead code;
//       – a Python `__main__.py` module scope.
//     A method named main anywhere else (a Python/JS/Ruby class member) is never an entry. Any other language: no
//     claim (a missed entry is disclosed by the legend; a false one would not be). Outside test paths and the
//     rolled-up directories below. Not detected (stated in the legend): entries declared in a manifest
//     (package.json main/bin/exports, console_scripts, Cargo [[bin]]) or by an attribute (Swift @main, Kotlin
//     @JvmStatic) — the index does not read those as entry declarations.
//   • ls rows — per directory, the unshown files: code files NAMED (basename), every other file COUNTED. A file under
//     a test/bench/fixture/example/doc directory rolls up to that directory (counted, never named): those trees are
//     large (textual's docs/examples, tmux's regress) and are not where an orient answer's key files live.
#include <algorithm>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include "model.h"
#include "filter.h"   // isTestSymbol — the shared test-path convention
#include "resolve.h"  // includerDir — the shared directory-of-a-path splitter
#include "infra/namesplit.h"   // namesplit::afterLast — the shared basename splitter
#include "nextverb.h"           // nextFlag — the one shell-safe next= argv composer

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
    std::vector<NodeId>        entries;            // path order, then symbol id; at most kInventoryEntryCap
    std::size_t                entryTotal = 0;     // every entry found (entries.size() < entryTotal ⇒ cut, disclosed)
    std::vector<MapInventoryDir> dirs;             // path order
    std::size_t                namesTotal = 0;     // every unshown code file a directory row could name
    bool                       namesCapped = false;   // the name ceiling left some of them counted, not named (disclosed)
    // Recovery of a cut (PROCESS rule 5: every cut recoverable via next=): the argv fragment, on the same root, that
    // lists what the guard left out. Empty unless that guard fired.
    std::string                entriesNext;        // --graph-query over every def that could be a cut entry (a superset)
    std::string                namesNext;          // --tree over every indexed file (a superset of the count-only names)
};

// RUNAWAY GUARDS (PROCESS rule 5a), far above any measured answer: the eleven orient repos of the round-1 table name at
// most 199 files (htop) and list at most 5 entries (gotestsum); golang.org/x/tools, a Go tool monorepo, has 60 real
// entries and golang.org/x/text 31, so the entry cap sits well above both. A monorepo of thousands of unshown code
// files would otherwise print every name (~13 B each). Past the ceiling, directories in path order keep n= and drop f=
// (names_capped="1" names_total=N names_next=); past the entry cap, entries_capped="1" entries_total=N entries_next=.
// Each next= is an argv on the same root that lists what was cut (a superset of it), so neither cut is a dead end.
inline constexpr std::size_t kInventoryNameCeiling = 2000;
inline constexpr std::size_t kInventoryEntryCap    = 256;

// Directory components whose subtree rolls up count-only. pathTierOf's test/bench/fixture conventions plus the
// presentational ones (examples, docs, regress, samples) — local to the inventory on purpose: widening pathTierOf
// itself would re-tier --grep/--callers ordering on every verb.
inline constexpr std::string_view kInventoryRollupDirs[] = {
    "test/", "tests/", "__tests__/", "spec/", "specs/", "e2e/", "bench/", "benches/", "benchmark/", "benchmarks/",
    "fixture/", "fixtures/", "testdata/", "example/", "examples/", "_example/", "_examples/", "doc/", "docs/",
    "regress/", "sample/", "samples/",
};
// Deliberately NOT rolled up: integration/ and testing/. Both are real package names (hono's src/helper/testing is a
// library helper; an integration/ package is common), so their files stay named; a main under them is still judged
// by the entry rule. e2e/ is an end-to-end test tree by name and rolls up. Go's _examples/ convention (a leading
// underscore keeps it out of the module build) and benchmark/ (grpc-go's benchmark mains) roll up like examples/.

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

// A code symbol: anything a reader can open as a definition — not a data Section (doc heading, JSON/YAML key) and
// not the synthetic module-scope row every script file carries.
inline bool isInventoryCodeSymbol( const Symbol& s ) noexcept
{
    return s.kind != SymKind::Section && s.kind != SymKind::ModuleScope;
}

// How a language spells its program entry (the header's entry rule). EntryFn: a caller-less Function `main` IS the
// entry. EntryStaticMethod: a caller-less Method `main`/`Main` is (Java/C# static main). ModuleScopeCall: a Function
// `main` is an entry only when its own file's module scope calls it. None: no claim.
enum class InventoryEntryStyle : std::uint8_t { None, EntryFn, EntryStaticMethod, ModuleScopeCall };

inline constexpr InventoryEntryStyle inventoryEntryStyle( Lang l ) noexcept
{
    switch( l )
    {
        case Lang::C: case Lang::Cpp: case Lang::ObjC: case Lang::Go: case Lang::Rust: case Lang::Kotlin: case Lang::Dart:
            return InventoryEntryStyle::EntryFn;
        case Lang::Java: case Lang::CSharp:
            return InventoryEntryStyle::EntryStaticMethod;
        case Lang::Python: case Lang::JavaScript: case Lang::TypeScript: case Lang::Ruby: case Lang::Bash: case Lang::Php:
        case Lang::Lua:
            return InventoryEntryStyle::ModuleScopeCall;
        default:
            return InventoryEntryStyle::None;
    }
}

// A def whose name and kind fit its language's entry convention (callers are judged separately).
inline bool isInventoryEntryShape( const Symbol& s ) noexcept
{
    switch( inventoryEntryStyle( s.lang ) )
    {
        case InventoryEntryStyle::EntryFn:
        case InventoryEntryStyle::ModuleScopeCall:   return s.kind == SymKind::Function && s.name == "main";
        case InventoryEntryStyle::EntryStaticMethod: return s.kind == SymKind::Method && ( s.name == "main" || s.name == "Main" );
        case InventoryEntryStyle::None:              break;
    }
    return false;
}

inline bool isInventoryMainModule( const IngestResult& ing, const Symbol& s ) noexcept
{
    return s.kind == SymKind::ModuleScope && s.fileId < ing.files.size()
        && namesplit::afterLast( rootRelPath( ing, s.fileId ), "/" ) == "__main__.py";
}

// The recovery argv for entries past the cap: a --graph-query naming every def the cut entries could be (each name a
// cut entry carries, plus the __main__.py module scopes when one was cut), --limit sized to every symbol it can match
// so its own window never cuts. A superset — it also lists non-entries of those names (tests, methods, callees).
inline std::string inventoryEntriesNext( const IngestResult& ing, const MapInventory& inv, std::size_t from )
{
    bool lower = false, upper = false, mainModule = false;
    for( std::size_t i = from; i < inv.entries.size(); ++i )
    {
        const Symbol& s = ing.symbols[ inv.entries[ i ] ];
        mainModule = mainModule || s.kind == SymKind::ModuleScope;
        lower      = lower || ( s.kind != SymKind::ModuleScope && s.name == "main" );
        upper      = upper || ( s.kind != SymKind::ModuleScope && s.name == "Main" );
    }
    std::vector<std::string> parts;
    if( lower )      { parts.emplace_back( "name(\"main\")" ); }
    if( upper )      { parts.emplace_back( "name(\"Main\")" ); }
    if( mainModule ) { parts.emplace_back( "and(file(all,\"(^|/)__main__\\.py$\"),kind(all,modscope))" ); }
    std::size_t limit = 0;
    for( const Symbol& s : ing.symbols )
    {
        limit += ( lower && s.name == "main" ) || ( upper && s.name == "Main" ) || ( mainModule && isInventoryMainModule( ing, s ) );
    }
    std::string expr = parts.size() == 1 ? parts[ 0 ] : std::string();
    for( std::size_t i = 0; parts.size() > 1 && i < parts.size(); ++i )
    {
        expr += i == 0 ? "or(" : ",";
        expr += parts[ i ];
    }
    if( parts.size() > 1 ) { expr += ")"; }
    return nextFlag( "--graph-query=", expr ) + " --limit=" + std::to_string( limit );
}

// The program entries by each language's convention (the header's rule), outside the rolled-up directories and test
// code; and the __main__.py module scopes. Path order, at most kInventoryEntryCap kept (entryTotal counts them all;
// entriesNext lists the rest).
template <class PathRel>
inline void collectInventoryEntries( MapInventory& inv, const IngestResult& ing, const std::vector<std::uint32_t>& outOff,
                                     const std::vector<NodeId>& outTargets, const PathRel& pathRel )
{
    const std::size_t F = ing.files.size();
    const std::size_t S = ing.symbols.size();
    // test PATHS need no clause here: isTestSymbol (below) covers a candidate def, and every test directory isTestPath
    // knows (test/, tests/, __tests__/) is a rolled-up directory, which covers a __main__.py scope
    const auto entryEligibleFile = [ & ]( std::uint32_t f ) noexcept { return inventoryRollupDirOf( rootRelPath( ing, f ) ).empty(); };
    std::vector<char> candidate( S, 0 );
    std::vector<char> scopeCalled( S, 0 );   // its own file's module scope calls it
    for( NodeId id = 0; id < S; ++id )
    {
        const Symbol& s = ing.symbols[ id ];
        candidate[ id ] = isInventoryEntryShape( s ) && s.fileId < F && !isTestSymbol( ing, id ) && entryEligibleFile( s.fileId );
    }
    // a candidate with an in-repo caller other than its own file's module scope is a library function, not an entry
    for( NodeId caller = 0; caller < S; ++caller )
    {
        const Symbol& c = ing.symbols[ caller ];
        for( std::uint32_t e = outOff[ caller ]; e < outOff[ caller + 1 ]; ++e )
        {
            const NodeId t = outTargets[ e ];
            if( t >= S || !candidate[ t ] )
            {
                continue;
            }
            if( c.kind == SymKind::ModuleScope && c.fileId == ing.symbols[ t ].fileId )
            {
                scopeCalled[ t ] = 1;
            }
            else
            {
                candidate[ t ] = 0;
            }
        }
    }
    for( NodeId id = 0; id < S; ++id )
    {
        const Symbol& s = ing.symbols[ id ];
        // a module-scope language's main is an entry only when that scope runs it; elsewhere the caller-less def is
        const bool conventionHolds = inventoryEntryStyle( s.lang ) != InventoryEntryStyle::ModuleScopeCall || scopeCalled[ id ];
        const bool mainModule = isInventoryMainModule( ing, s ) && entryEligibleFile( s.fileId );
        if( ( candidate[ id ] && conventionHolds ) || mainModule )
        {
            inv.entries.push_back( id );
        }
    }
    std::stable_sort( inv.entries.begin(), inv.entries.end(), [ & ]( NodeId a, NodeId b )
    { return pathRel( ing.symbols[ a ].fileId ) < pathRel( ing.symbols[ b ].fileId ); } );
    inv.entryTotal = inv.entries.size();
    if( inv.entries.size() > kInventoryEntryCap )
    {
        inv.entriesNext = inventoryEntriesNext( ing, inv, kInventoryEntryCap );
        inv.entries.resize( kInventoryEntryCap );
    }
}

// One row per directory over the unshown files, path order. A file under a rolled-up directory groups under that
// directory and is counted; elsewhere a code file (codeSyms > 0, not test-named) is named, every other file counted.
template <class PathRel>
inline void collectInventoryDirs( MapInventory& inv, const IngestResult& ing, const std::vector<char>& shownFile,
                                  const std::vector<std::uint32_t>& codeSyms, const PathRel& pathRel )
{
    struct Keyed { std::string key; bool rolled; std::uint32_t f; };
    std::vector<Keyed> keyed;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        if( shownFile[ f ] )
        {
            continue;
        }
        // classify on the ROOT-RELATIVE path (a checkout living under a tests/ dir is not a test tree — #228), group
        // and print in the display form every <f p=> uses
        const std::string_view rel    = rootRelPath( ing, f );
        const std::string_view disp   = pathRel( f );
        const std::string_view rolled = inventoryRollupDirOf( rel );
        if( rolled.empty() )
        {
            const std::string_view dir = includerDir( disp );   // the shared directory splitter; the root's files group under "."
            keyed.push_back( Keyed{ std::string( dir.empty() ? std::string_view( "." ) : dir ), false, f } );
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
}

// The name ceiling: whole directories, path order — a directory is named completely or not at all, so f= is never a
// silent part-list; past the ceiling every later directory is count-only too (one contiguous cut).
inline void applyInventoryNameCeiling( MapInventory& inv ) noexcept
{
    for( const MapInventoryDir& d : inv.dirs )
    {
        inv.namesTotal += d.named.size();
    }
    std::size_t namedSoFar = 0;
    for( MapInventoryDir& d : inv.dirs )
    {
        if( namedSoFar + d.named.size() > kInventoryNameCeiling )
        {
            inv.namesCapped = inv.namesCapped || !d.named.empty();
            d.named.clear();
            namedSoFar = kInventoryNameCeiling;
            continue;
        }
        namedSoFar += d.named.size();
    }
    ENSURES( namedSoFar <= kInventoryNameCeiling, "the printed names stay within the ceiling" );
}

// `shownFile[f]` != 0 ⇔ the ranked rows printed a <f> group for file f. `pathRel` maps a file id to its display path
// (the same root-relative form every <f p=> uses).
template <class PathRel>
inline MapInventory computeMapInventory( const IngestResult& ing, const std::vector<std::uint32_t>& outOff,
                                         const std::vector<NodeId>& outTargets, const std::vector<char>& shownFile,
                                         const PathRel& pathRel )
{
    const std::size_t F = ing.files.size();
    EXPECTS( shownFile.size() == F, "one shown bit per indexed file" );
    EXPECTS( outOff.size() >= ing.symbols.size() + 1 || ing.symbols.empty(), "outOff is the CSR offset array over the symbols" );
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
    collectInventoryEntries( inv, ing, outOff, outTargets, pathRel );
    collectInventoryDirs( inv, ing, shownFile, codeSyms, pathRel );
    applyInventoryNameCeiling( inv );
    if( inv.namesCapped )
    {
        // --tree lists every indexed file with a symbol, ranked, paging by its own next=; --limit= files= keeps it to
        // one page. A superset of the count-only names (it repeats the ranked and the named files).
        inv.namesNext = "--tree --limit=" + std::to_string( F );
    }
    ENSURES( inv.listed + inv.unlisted == F, "every indexed file is listed or inventoried" );
    return inv;
}

// The legend clause (full dialect). No double hyphen: it rides inside an XML comment (G4).
inline constexpr std::string_view kMapInventoryLegend =
    "<!-- inv: the files the ranked rows above do not show, so no indexed file is silently absent; names only, weaker "
    "evidence than a ranked row. listed= files shown above, unlisted= the rest (listed+unlisted = files=). entry p= n=: a "
    "program entry by its language's convention: a main nothing in the repo calls in C, C++, ObjC, Go, Rust, Kotlin or "
    "Dart; a static Main/main method nothing calls in Java or C#; in a script language (Python, JS, TS, Ruby, Bash, PHP, "
    "Lua) a main that its own file's module scope calls and nothing else does; or a __main__.py module scope; its "
    "resolved callees as c rows. A method named main elsewhere, or a script main nothing runs, is not an entry; entries "
    "declared only in a manifest (package.json main/bin, console_scripts) or by an attribute (Swift @main) are not "
    "detected. ls p= n= f=: n= unshown files under directory p=, f= the code files among them by name; test, doc and "
    "config files are counted, not named, and a test/e2e/bench/benchmark/fixture/example/_examples/doc directory rolls "
    "up whole. ripwire on p= ranks that directory. Runaway guards: entries_capped=1 entries_total=N when more than 256 "
    "entries exist (the first 256 by path shown), entries_next= the argv listing every def that could be a cut entry (a "
    "superset); names_capped=1 names_total=N when the N unshown code files pass a 2000 name ceiling (directories past "
    "it, path order, keep n= only), names_next= the argv listing every indexed file (a superset) -->";

}  // namespace rw

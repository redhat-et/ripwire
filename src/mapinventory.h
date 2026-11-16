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
//     large (textual's docs/examples, tmux's regress) and are not where an orient answer's key files live. The row
//     list is BOUNDED (kInventoryDirCap, kInventoryCountOnlyCap) and the name budget is spent fewest-directory-first
//     rather than in path order — both measured, both disclosed, see the constants below.
#include <algorithm>
#include <cstdint>
#include <numeric>   // std::iota — the house index-permutation idiom
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
    std::size_t                dirTotal    = 0;    // every directory row the tier could print (dirs.size() < dirTotal => cut)
    bool                       dirsCapped  = false;   // the ROW ceiling cut directory rows (disclosed)
    std::string                dirsNext;           // --tree over every indexed file (a superset of the cut directories' files)
};

// RUNAWAY GUARDS (PROCESS rule 5a), far above any measured answer: the eleven orient repos of the round-1 table name at
// most 199 files (htop) and list at most 5 entries (gotestsum); golang.org/x/tools, a Go tool monorepo, has 60 real
// entries and golang.org/x/text 31, so the entry cap sits well above both. A monorepo of thousands of unshown code
// files would otherwise print every name (~13 B each). Past the ceiling, directories in path order keep n= and drop f=
// (names_capped="1" names_total=N names_next=); past the entry cap, entries_capped="1" entries_total=N entries_next=.
// Each next= is an argv on the same root that lists what was cut (a superset of it), so neither cut is a dead end.
inline constexpr std::size_t kInventoryNameCeiling = 2000;
inline constexpr std::size_t kInventoryEntryCap    = 256;

// The ROW ceiling (added 2026-11-15). The two guards above bound the NAMES inside a row and the ENTRIES above
// them; neither bounded the number of ROWS, so the row list grew with the corpus rather than with the question.
// Measured over 15 repos: the ranked map holds within 16,879-27,664 B across a 10x range of repository size while
// <ls> runs 2,670 B (tmux) to 192,484 B (vscode), 82.4 % of that document. The cut is taken at the measured cliff
// -- 2,102 of vscode's 2,534 rows were COUNT-ONLY, a path and a number, 121,932 B / 52 % of the whole document,
// and 959 of those said n="1". So count-only rows get a small allowance, ordered by how many files they stand for,
// and every row that NAMES code files is kept up to a backstop that is a blow-up guard rather than a tuning knob
// (above every measured named-row count: 1,211 on cockroach, 1,207 on vscode under the name allocator below).
// Disclosed as dirs_capped="1" dirs_total=N dirs_next=, the form the other two guards already use.
// docs/EVALS.md, "the map inventory tier's <ls> rows are unbounded".
inline constexpr std::size_t kInventoryCountOnlyCap = 32;
inline constexpr std::size_t kInventoryDirCap       = 2048;

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

// The languages of each style, as data (a reader checks one list, not a switch).
inline constexpr Lang kInventoryEntryFnLangs[]       = { Lang::C, Lang::Cpp, Lang::ObjC, Lang::Go, Lang::Rust, Lang::Kotlin, Lang::Dart };
inline constexpr Lang kInventoryStaticMethodLangs[]  = { Lang::Java, Lang::CSharp };
inline constexpr Lang kInventoryModuleScopeLangs[]   = { Lang::Python, Lang::JavaScript, Lang::TypeScript, Lang::Ruby, Lang::Bash,
                                                         Lang::Php, Lang::Lua };

inline constexpr InventoryEntryStyle inventoryEntryStyle( Lang l ) noexcept
{
    const auto in = [ l ]( const auto& langs ) noexcept { return std::find( std::begin( langs ), std::end( langs ), l ) != std::end( langs ); };
    return in( kInventoryEntryFnLangs )      ? InventoryEntryStyle::EntryFn
         : in( kInventoryStaticMethodLangs ) ? InventoryEntryStyle::EntryStaticMethod
         : in( kInventoryModuleScopeLangs )  ? InventoryEntryStyle::ModuleScopeCall
                                             : InventoryEntryStyle::None;
}

// A def whose name and kind fit its language's entry convention (callers are judged separately).
inline bool isInventoryEntryShape( const Symbol& s ) noexcept
{
    switch( inventoryEntryStyle( s.lang ) )
    {
        case InventoryEntryStyle::EntryFn:           return s.kind == SymKind::Function && s.name == "main";
        // a script language indexes a class member as a Function with its class as scope (Python `def main(self)`):
        // only a TOP-LEVEL main is the script's entry
        case InventoryEntryStyle::ModuleScopeCall:   return s.kind == SymKind::Function && s.name == "main" && s.scope.empty();
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
    bool on[ 3 ] = { false, false, false };   // a cut def named main, one named Main, a cut __main__.py scope
    for( std::size_t i = from; i < inv.entries.size(); ++i )
    {
        const Symbol& s = ing.symbols[ inv.entries[ i ] ];
        const bool    scope = s.kind == SymKind::ModuleScope;
        on[ 0 ] = on[ 0 ] || ( !scope && s.name == "main" );
        on[ 1 ] = on[ 1 ] || ( !scope && s.name == "Main" );
        on[ 2 ] = on[ 2 ] || scope;
    }
    static constexpr std::string_view kParts[ 3 ] = { "name(\"main\")", "name(\"Main\")",
                                                      "and(file(all,\"(^|/)__main__\\.py$\"),kind(all,modscope))" };
    std::string joined;
    int         n = 0;
    for( int i = 0; i < 3; ++i )
    {
        if( on[ i ] ) { joined += n++ ? "," : "";  joined += kParts[ i ]; }
    }
    std::size_t limit = 0;   // every symbol the expression can match, so the query's own window never cuts
    for( const Symbol& s : ing.symbols )
    {
        limit += ( on[ 0 ] && s.name == "main" ) || ( on[ 1 ] && s.name == "Main" ) || ( on[ 2 ] && isInventoryMainModule( ing, s ) );
    }
    return nextFlag( "--graph-query=", n > 1 ? "or(" + joined + ")" : joined ) + " --limit=" + std::to_string( limit );
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

// ── the ONE order both of the tier's ceilings spend their budget in ────────────────────────────────────────────
// docs/METHODOLOGY.md §9.1: a ceiling bounds the TAIL only if the cut walks priority order, and "priority" is
// never source, id or PATH order. Both guards below therefore index through one of these two orders, and neither
// is path order -- path order only ever decides a tie, which is what keeps the output deterministic.
//
// WHY FEWEST-FIRST FOR NAMES, measured 2026-11-15 and not guessed. A probe binary with the ceiling lifted to 10^8
// dumped the uncapped per-directory name counts: the MEDIAN directory holds 2 nameable code files and the maximum
// holds 300 (cockroach) to 786 (vscode). Replaying the three candidate orders at the shipped 2,000-name budget:
//   path order (shipped) : vscode 432 directories named, ZERO of 1,537 src/ rows -- the budget is spent
//                          alphabetically, on ".agents", ".github", "cli", "copilot_shim" and "extensions"
//   most-code-first      : vscode 11 directories named; envoy's api/ 538 -> 1. The outliers eat the budget, and
//                          786 filenames in one directory is not an orient answer. REGISTERED, then REJECTED.
//   fewest-code-first    : vscode 1,207 named and src/ 0 -> 806; cockroach pkg/ 535 -> 1,206; envoy source/ ~0
//                          -> 358. Maximises how many directories get named under the budget. ADOPTED.
// docs/EVALS.md, "the inventory tier's NAME ceiling spends its budget in path order", with its amendment.
// Each order is an index permutation under its own comparator, written in the house idiom (std::iota then
// std::sort over the indices, as src/declinedsites.h, src/forpage.h and src/forslots.h do) rather than behind a
// shared wrapper: the wrapper was a 119-token clone of src/eval.h's rankFiles, which --quality-delta gated.
inline std::vector<std::uint32_t> inventoryNameOrder( const std::vector<MapInventoryDir>& dirs )
{
    std::vector<std::uint32_t> order( dirs.size() );
    std::iota( order.begin(), order.end(), std::uint32_t( 0 ) );
    std::sort( order.begin(), order.end(), [ &dirs ]( std::uint32_t a, std::uint32_t b ) noexcept
    {
        if( dirs[ a ].named.size() != dirs[ b ].named.size() ) { return dirs[ a ].named.size() < dirs[ b ].named.size(); }
        return dirs[ a ].dir < dirs[ b ].dir;       // a total order, so two runs cannot disagree
    } );
    return order;
}

// The ROW order: a row that NAMES code files outranks a count-only row (the measured cliff), and among count-only
// rows the one standing for more files comes first -- "docs/ holds 1,200 unshown files" is repository shape,
// "x/ holds 1" is 58 bytes of nothing, and 959 of vscode's rows were the latter.
inline std::vector<std::uint32_t> inventoryRowOrder( const std::vector<MapInventoryDir>& dirs )
{
    std::vector<std::uint32_t> order( dirs.size() );
    std::iota( order.begin(), order.end(), std::uint32_t( 0 ) );
    std::sort( order.begin(), order.end(), [ &dirs ]( std::uint32_t a, std::uint32_t b ) noexcept
    {
        if( dirs[ a ].named.empty() != dirs[ b ].named.empty() ) { return dirs[ b ].named.empty(); }   // named rows first
        if( dirs[ a ].total != dirs[ b ].total )                 { return dirs[ a ].total > dirs[ b ].total; }
        return dirs[ a ].dir < dirs[ b ].dir;
    } );
    return order;
}

// The name ceiling: whole directories — a directory is named completely or not at all, so f= is never a silent
// part-list. The budget is spent in inventoryNameOrder (fewest-first), NOT in path order, and the survivors keep
// their place in inv.dirs, which is already path order: the emit order is unchanged, only the allocation moved.
// The stopping rule is the shipped one (stop at the first directory that does not fit), so this changes WHICH
// directories are named and not HOW MANY names are printed.
inline void applyInventoryNameCeiling( MapInventory& inv )
{
    for( const MapInventoryDir& d : inv.dirs )
    {
        inv.namesTotal += d.named.size();
    }
    if( inv.namesTotal <= kInventoryNameCeiling )
    {
        return;   // every name fits: no cut, and nothing is reordered that is not cut
    }
    std::vector<char> keepNames( inv.dirs.size(), 0 );
    std::size_t       namedSoFar = 0;
    for( std::uint32_t idx : inventoryNameOrder( inv.dirs ) )
    {
        const std::size_t want = inv.dirs[ idx ].named.size();
        if( want == 0 )
        {
            continue;                 // a count-only directory asks for no budget
        }
        if( namedSoFar + want > kInventoryNameCeiling )
        {
            break;                    // the shipped stopping rule, now in priority order
        }
        keepNames[ idx ] = 1;
        namedSoFar      += want;
    }
    for( std::size_t i = 0; i < inv.dirs.size(); ++i )
    {
        if( keepNames[ i ] == 0 && !inv.dirs[ i ].named.empty() )
        {
            inv.namesCapped = true;
            inv.dirs[ i ].named.clear();
        }
    }
    ENSURES( namedSoFar <= kInventoryNameCeiling, "the printed names stay within the ceiling" );
}

// The ROW ceiling. Runs AFTER the name ceiling, because a directory the name ceiling emptied IS a count-only row
// from here on and competes as one. Walks inventoryRowOrder, keeps every named row up to the backstop and
// count-only rows up to the allowance, then erases the rest IN PLACE -- which preserves inv.dirs' path order, so
// the survivors are emitted exactly as the tier always emitted them. `fileCount` is files=, for the recovery argv.
inline void applyInventoryDirCeiling( MapInventory& inv, std::size_t fileCount )
{
    inv.dirTotal = inv.dirs.size();
    std::vector<char> keep( inv.dirs.size(), 0 );
    std::size_t       kept          = 0;
    std::size_t       countOnlyKept = 0;
    for( std::uint32_t idx : inventoryRowOrder( inv.dirs ) )
    {
        if( kept >= kInventoryDirCap )
        {
            break;
        }
        const bool countOnly = inv.dirs[ idx ].named.empty();
        if( countOnly && countOnlyKept >= kInventoryCountOnlyCap )
        {
            continue;
        }
        keep[ idx ]   = 1;
        ++kept;
        countOnlyKept += countOnly ? 1 : 0;
    }
    if( kept == inv.dirs.size() )
    {
        return;   // nothing cut: no vocabulary, and a byte-identical tier
    }
    std::size_t write = 0;
    for( std::size_t read = 0; read < inv.dirs.size(); ++read )
    {
        if( keep[ read ] == 0 )
        {
            continue;
        }
        if( write != read )   // NEVER self-move-assign: libc++ leaves a moved-from std::string/vector EMPTY, so a
        {                     // kept FIRST row would silently lose its p= and its f= (caught by Band 1, 2026-11-15:
                              // vscode's root row shipped as <ls p="" n="14"/>, its one named file gone)
            inv.dirs[ write ] = std::move( inv.dirs[ read ] );
        }
        ++write;
    }
    inv.dirs.resize( write );
    inv.dirsCapped = true;
    // --tree lists every indexed file with a symbol, ranked, paging by its own next=; --limit= files= keeps it to
    // one page. A superset of the cut directories' files (it repeats the kept and the ranked ones).
    inv.dirsNext = "--tree --limit=" + std::to_string( fileCount );
    ENSURES( inv.dirs.size() == write && write < inv.dirTotal, "a disclosed cut removed at least one row" );
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
    applyInventoryDirCeiling( inv, F );
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
    "superset); names_capped=1 names_total=N when the N unshown code files pass a 2000 name ceiling (the directories "
    "with the FEWEST unshown code files are named first, so the budget reaches the most directories; the rest keep n= "
    "only), names_next= the argv listing every indexed file (a superset); dirs_capped=1 dirs_total=N when more than N "
    "directory rows exist: every ls row naming code files is kept and the count-only rows are cut to the 32 standing for "
    "the most files, so no indexed file leaves listed=/unlisted= and only the per-directory enumeration is shorter, "
    "dirs_next= the argv listing every indexed file (a superset) -->";

}  // namespace rw

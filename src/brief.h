#pragma once
// brief.h — `--brief="TASK"` (MCP `brief {task, bytes}`): the fresh-subagent brief. One compact, size-capped answer a parent
// pastes into a code-editing subagent's prompt, so the subagent makes its first targeted Read/Edit without the ~8 orientation
// calls a fresh one spends (ls/find, README/CLAUDE.md, broad greps, git tours: 604K mean / 400K median cached tokens per
// subagent, tmp/orch-1125/hard-orient RESULT.md §2). The contract is SPEC_SUBAGENT_BRIEF.md §2: eight sections, in order —
//   1 <layout>       top dirs with a role and a file count (depth 2-3 for a dir holding > 30 % of the files)
//   2 <build>        build/test commands QUOTED from manifests and the repo's own docs, never guessed; the test registration
//   3 <entry>        program entries and the public header, ranked by call/include reach to the task's act symbols
//   4 <task>         the --for core for TASK: confidence, <act read=> with up to 8 ranges, θ11 question sites
//   5 <edges>        callers and cross-file callees of the top-3 act symbols
//   6 <where-else>   co-change partners, tests, docs, changelog and the test-registering build file of the act files
//   7 <conventions>  agent/contributor docs as pointers: path + H2 headings with their lines
//   8 <next>         the three-moment line `ripwire wrap claude` prints (subagentblock.h), unchanged
// Size by repo class (files indexed): small < 1K -> 2,560 B; medium < 10K -> 4,096 B; large -> 6,144 B; --brief-bytes=N
// (512..8,192) overrides. Over budget, parts drop in kDropOrder and each drop is named in dropped=; act and build never drop
// (owner: "a budget that prevents answers is bad"), so an answer that still does not fit says over="1".
//
// The --for core is NOT recomputed here: the caller runs --for through its own entry point (CLI: runForLens under a stdout
// capture, verbs_brief.h; MCP: forTaskText) and hands this file the finished page, from which the root's confidence= and at=,
// the act ranges and the lined <sigs> rows are read. --for's bytes are untouched by this verb.
// Deterministic: every list is sorted before it is cut; no hash-map order reaches the output; git is read only for co-change.

#include "forqsites.h"     // questionTokens / collectSites / formatLines — the θ11 question sites, called directly (not behind RIPWIRE_THETA11)
#include "gitmine.h"       // gitCommitFileSets / cochangePartners — where-else's history-backed partners
#include "gitstamp.h"      // isShallow — history="0" on a depth-limited clone
#include "graph.h"         // Graph (inEdges / outOff / outTargets), resolveIncludeAdj
#include "lexical.h"       // routeLower — the one ASCII lowercase
#include "model.h"         // IngestResult, Symbol, rootRelPath, HashMap
#include "pattern.h"       // appendUnique — order-preserving unique push
#include "resolve.h"       // trimWs / includerDir — the one trim and dir-of-path
#include "sarif.h"         // rootPrefixOf — the question sites' root-relative paths
#include "serialize.h"     // escapeXml, attrOf
#include "subagentblock.h" // kSubagentBriefBlock — section 8
#include "infra/namesplit.h" // afterLast — the one last-segment split
#include "infra/ownedfile.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <system_error>
#include <tuple>
#include <vector>

namespace rw::brief
{

// ── the size classes and caps ───────────────────────────────────────────────────────────────────────────────────────────────
struct ClassCaps
{
    const char* name;
    int         maxFiles;        // a corpus with fewer indexed files is this class
    std::size_t budgetBytes;
    int         layoutEntries;
    int         entries;
    std::size_t imports;         // the primary file's imports shown on the edges' <i> line
};
inline constexpr std::array<ClassCaps, 3> kClassCaps = { {
    { "small", 1000, 2560, 12, 3, 6 },
    { "medium", 10000, 4096, 12, 4, 8 },
    { "large", 0, 6144, 20, 5, 8 },
} };
inline constexpr std::size_t kMinBudgetBytes  = 512;
inline constexpr std::size_t kHardCapBytes    = 8192;
inline constexpr int         kActRanges       = 8;     // E1 ACT-8: the shipped act ∪ the next lined page-1 rows
inline constexpr int         kEdgeSymbols     = 3;
inline constexpr int         kEdgesPerSide    = 5;
inline constexpr std::size_t kUsersShown      = 3;     // files that import the primary file (its registration / load points)
inline constexpr int         kWhereElseCap    = 6;
inline constexpr int         kWhereElseKept   = 3;     // what the where-else drop keeps
inline constexpr int         kHeadingsPerDoc  = 8;
inline constexpr std::size_t kConventionBytes = 400;
inline constexpr std::size_t kQsBytes         = 1000;  // forqsites.h kBlockBytes, the θ11 knee
inline constexpr std::size_t kTaskEchoBytes   = 160;
inline constexpr int         kBuildLines      = 4;
inline constexpr std::size_t kManifestReadBytes = 256 * 1024;
inline constexpr std::size_t kDocScanBytes    = 200 * 1024;
inline constexpr int         kDocScanFiles    = 4000;
inline constexpr int         kReachHops       = 12;

inline const ClassCaps& capsFor( std::size_t fileCount ) noexcept
{
    for( const ClassCaps& c : kClassCaps )
    {
        if( c.maxFiles > 0 && fileCount < std::size_t( c.maxFiles ) )
        {
            return c;
        }
    }
    return kClassCaps.back();
}

// ── what the caller hands in ────────────────────────────────────────────────────────────────────────────────────────────────
struct BriefInputs
{
    const IngestResult& ing;
    const Graph&        g;
    std::string_view    diskRoot;      // the crawl root as typed: manifests and docs are read under it
    std::string_view    task;
    std::string_view    forPage;       // the finished --for page 1 for `task`
    std::size_t         budgetBytes = 0;   // 0: the size class decides
};

namespace detail
{

// ── small text helpers ──────────────────────────────────────────────────────────────────────────────────────────────────────
inline std::string xml( std::string_view s )
{
    std::vector<char> esc;
    return std::string( escapeXml( s, esc ) );
}

inline std::string lower( std::string_view s ) { return routeLower( s ); }

inline std::string_view trim( std::string_view s ) noexcept { return trimWs( s ); }

inline std::string_view baseName( std::string_view path ) noexcept { return namesplit::afterLast( path, "/" ); }

inline std::string_view dirName( std::string_view path ) noexcept { return includerDir( path ); }

// The base name up to its first dot past a leading one: jq.test -> jq, editor.main.ts -> editor, .eslintrc -> .eslintrc.
inline std::string_view stemOf( std::string_view path ) noexcept
{
    const std::string_view b = baseName( path );
    return b.substr( 0, b.find( '.', 1 ) );
}

inline std::string joinPath( std::string_view root, std::string_view rel )
{
    std::string out( root.empty() ? std::string_view( "." ) : root );
    if( out.back() != '/' )
    {
        out += '/';
    }
    out += rel;
    return out;
}

// The first `maxBytes` of a file; nullopt when it cannot be opened.
inline std::optional<std::string> readHead( const std::string& path, std::size_t maxBytes )
{
    OwnedFile fp = openOwnedFile( path.c_str(), "rb" );
    if( !fp )
    {
        return std::nullopt;
    }
    std::string out( maxBytes, '\0' );
    const std::size_t got = std::fread( out.data(), 1, maxBytes, fp.file );
    out.resize( got );
    return out;
}

inline bool isDir( const std::string& path )
{
    std::error_code ec;
    return std::filesystem::is_directory( path, ec ) && !ec;
}

inline int commonPrefixDirs( std::string_view a, std::string_view b ) noexcept
{
    int         dirs = 0;
    std::size_t i    = 0;
    while( i < a.size() && i < b.size() && a[i] == b[i] )
    {
        if( a[i] == '/' )
        {
            ++dirs;
        }
        ++i;
    }
    return dirs;
}

// Each line of `text`, without its terminator.
template<class Visit>
inline void forEachLine( std::string_view text, Visit&& visit )
{
    int lineNo = 0;
    for( std::size_t at = 0; at < text.size(); )
    {
        std::size_t nl = text.find( '\n', at );
        if( nl == std::string_view::npos )
        {
            nl = text.size();
        }
        ++lineNo;
        if( !visit( text.substr( at, nl - at ), lineNo ) )
        {
            return;
        }
        at = nl + 1;
    }
}

// ── directory roles ─────────────────────────────────────────────────────────────────────────────────────────────────────────
// A dir NAME's role. skip= marks the two a subagent should not read: vendored copies and generated output.
struct DirRole
{
    std::string_view dir;
    const char*      role;
};
inline constexpr DirRole kDirRoles[] = {
    { "vendor", "vendored(skip)" }, { "vendored", "vendored(skip)" }, { "third_party", "vendored(skip)" }, { "third-party", "vendored(skip)" },
    { "thirdparty", "vendored(skip)" }, { "3rdparty", "vendored(skip)" }, { "external", "vendored(skip)" }, { "extern", "vendored(skip)" },
    { "node_modules", "vendored(skip)" }, { "bower_components", "vendored(skip)" },
    { "generated", "generated(skip)" }, { "__generated__", "generated(skip)" }, { "autogen", "generated(skip)" },
    { "test", "test" }, { "tests", "test" }, { "testing", "test" }, { "spec", "test" }, { "specs", "test" }, { "__tests__", "test" },
    { "unittests", "test" }, { "unittest", "test" }, { "e2e", "test" }, { "testdata", "test" }, { "test-suite", "test" },
    { "doc", "docs" }, { "docs", "docs" }, { "documentation", "docs" }, { "man", "docs" },
    { "include", "api" }, { "api", "api" },
    { "example", "examples" }, { "examples", "examples" }, { "samples", "examples" }, { "demo", "examples" },
    { "bench", "bench" }, { "benchmarks", "bench" }, { "benchmark", "bench" }, { "perf", "bench" },
    { "build", "build" }, { "cmake", "build" }, { ".github", "build" }, { "ci", "build" }, { "packaging", "build" }, { "builds", "build" },
    { "m4", "build" },
    { "scripts", "tools" }, { "script", "tools" }, { "tools", "tools" }, { "utils", "tools" }, { "hack", "tools" }, { "bin", "tools" },
};
// Untracked build output a crawl never indexes: named when the dir exists at the root with no indexed file.
inline constexpr std::string_view kBuildOutputDirs[] = { "build", "out", "dist", "target", "cmake-build-debug" };

inline const char* roleOfName( std::string_view name ) noexcept
{
    const std::string lo = lower( name );
    for( const DirRole& r : kDirRoles )
    {
        if( lo == r.dir )
        {
            return r.role;
        }
    }
    return nullptr;
}

inline bool isSkipRole( std::string_view role ) noexcept { return role.ends_with( "(skip)" ); }

// The role of a root-relative PATH: the first dir component with a skip role wins, then the first with any role.
inline std::string_view roleOfPath( std::string_view rel ) noexcept
{
    std::string_view first;
    for( std::size_t at = 0;; )
    {
        const std::size_t slash = rel.find( '/', at );
        if( slash == std::string_view::npos )
        {
            break;
        }
        if( const char* r = roleOfName( rel.substr( at, slash - at ) ); r != nullptr )
        {
            if( isSkipRole( r ) )
            {
                return r;
            }
            if( first.empty() )
            {
                first = r;
            }
        }
        at = slash + 1;
    }
    return first;
}

inline bool isTestPath( std::string_view rel ) noexcept
{
    if( roleOfPath( rel ) == "test" )
    {
        return true;
    }
    const std::string_view b = baseName( rel );
    return b.starts_with( "test_" ) || b.find( "_test." ) != std::string_view::npos || b.find( ".test." ) != std::string_view::npos
           || b.find( ".spec." ) != std::string_view::npos || b.find( "Test." ) != std::string_view::npos || b.find( "Tests." ) != std::string_view::npos;
}

inline bool isDocPath( std::string_view rel ) noexcept
{
    if( isTestPath( rel ) || isSkipRole( roleOfPath( rel ) ) )
    {
        return false;
    }
    const std::string_view b = baseName( rel );
    return roleOfPath( rel ) == "docs" || b.ends_with( ".md" ) || b.ends_with( ".rst" ) || b.ends_with( ".adoc" ) || b.ends_with( ".txt" );
}

// ── the corpus view every step reads ────────────────────────────────────────────────────────────────────────────────────────
struct Corpus
{
    const IngestResult&                    ing;
    const Graph&                           g;
    std::string                            diskRoot;
    std::vector<std::string_view>          rel;      // fileId -> root-relative path
    HashMap<std::string_view, std::uint32_t> fileOf; // root-relative path -> fileId
    std::vector<std::uint32_t>             firstSym; // fileId -> first symbol index (symbols are sorted by fileId); size files+1

    Corpus( const IngestResult& i, const Graph& gr, std::string_view root ) : ing( i ), g( gr ), diskRoot( root )
    {
        const std::size_t fileCount = ing.files.size();
        rel.reserve( fileCount );
        fileOf.reserve( fileCount );
        for( std::uint32_t f = 0; f < fileCount; ++f )
        {
            rel.push_back( rootRelPath( ing, f ) );
            fileOf.emplace( rel.back(), f );
        }
        firstSym.assign( fileCount + 1, std::uint32_t( ing.symbols.size() ) );
        for( std::size_t s = ing.symbols.size(); s-- > 0; )
        {
            const std::uint32_t f = ing.symbols[s].fileId;
            if( f < fileCount )
            {
                firstSym[f] = std::uint32_t( s );
            }
        }
        for( std::size_t f = fileCount; f-- > 0; )
        {
            firstSym[f] = std::min( firstSym[f], firstSym[f + 1] );
        }
    }
    std::optional<std::uint32_t> file( std::string_view path ) const
    {
        const auto it = fileOf.find( path );
        return it == fileOf.end() ? std::nullopt : std::optional<std::uint32_t>( it->second );
    }
    // Indexed, or a regular file on disk: manifests (CMakeLists.txt, Makefile.am, tox.ini …) are not indexed source.
    bool exists( std::string_view path ) const
    {
        std::error_code ec;
        return fileOf.contains( path ) || std::filesystem::is_regular_file( joinPath( diskRoot, path ), ec );
    }
    std::optional<std::string> read( std::string_view path, std::size_t maxBytes = kManifestReadBytes ) const
    {
        return readHead( joinPath( diskRoot, path ), maxBytes );
    }
    // The symbol a range names: the one starting on line `l` in `fileId`, else the narrowest one containing it.
    std::optional<std::uint32_t> symbolAt( std::uint32_t fileId, std::uint32_t l ) const
    {
        std::optional<std::uint32_t> best;
        std::uint32_t               bestLoc = UINT32_MAX;
        for( std::uint32_t s = firstSym[fileId]; s < firstSym[fileId + 1]; ++s )
        {
            const Symbol& sym = ing.symbols[s];
            if( sym.line == l )
            {
                return s;
            }
            if( sym.line < l && sym.line + std::max<std::uint32_t>( sym.loc, 1 ) > l && sym.loc < bestLoc )
            {
                best    = s;
                bestLoc = sym.loc;
            }
        }
        return best;
    }
    std::string shortName( std::uint32_t s ) const
    {
        const Symbol& sym = ing.symbols[s];
        std::string_view scope = sym.scope;
        if( const std::size_t cut = scope.rfind( "::" ); cut != std::string_view::npos )
        {
            scope = scope.substr( cut + 2 );
        }
        if( const std::size_t cut = scope.rfind( '.' ); cut != std::string_view::npos )
        {
            scope = scope.substr( cut + 1 );
        }
        return scope.empty() ? sym.name : std::string( scope ) + "::" + sym.name;
    }
};

// ── reading the --for page ──────────────────────────────────────────────────────────────────────────────────────────────────
struct Range
{
    std::string   path;
    std::uint32_t lo = 0;
    std::uint32_t hi = 0;
    std::string   name;   // the row's name when page 1 lists it
};

// The same lines of the same file (the row's name aside).
inline bool sameSpan( const Range& a, const Range& b ) noexcept
{
    return a.path == b.path && a.lo == b.lo && a.hi == b.hi;
}

inline std::optional<Range> parseRange( std::string_view s )
{
    const std::size_t colon = s.rfind( ':' );
    const std::size_t dash  = colon == std::string_view::npos ? std::string_view::npos : s.find( '-', colon );
    if( colon == std::string_view::npos || dash == std::string_view::npos || colon == 0 )
    {
        return std::nullopt;
    }
    Range r;
    r.path = std::string( s.substr( 0, colon ) );
    const auto num = []( std::string_view v, std::uint32_t& out )
    {
        out = 0;
        if( v.empty() )
        {
            return false;
        }
        for( const char c : v )
        {
            if( c < '0' || c > '9' )
            {
                return false;
            }
            out = out * 10 + std::uint32_t( c - '0' );
        }
        return true;
    };
    if( !num( s.substr( colon + 1, dash - colon - 1 ), r.lo ) || !num( s.substr( dash + 1 ), r.hi ) )
    {
        return std::nullopt;
    }
    return r;
}

struct ForCore
{
    std::string        confidence;
    std::string        at;
    std::vector<Range> act;     // up to kActRanges
    std::vector<Range> rows;    // every lined <sigs> row, page order
    int                shippedAct = 0;
};

// The lined rows of page 1's <sigs> CDATA (`path:l-e name …`, the default row form).
inline std::vector<Range> sigsRows( std::string_view page )
{
    std::vector<Range> rows;
    const std::size_t  sigs = page.find( "<sigs" );
    const std::size_t  open = sigs == std::string_view::npos ? sigs : page.find( "<![CDATA[", sigs );
    const std::size_t  shut = open == std::string_view::npos ? open : page.find( "]]>", open );
    if( shut == std::string_view::npos )
    {
        return rows;
    }
    forEachLine( page.substr( open + 9, shut - open - 9 ), [ & ]( std::string_view line, int )
    {
        const std::size_t sp = line.find( ' ' );
        if( std::optional<Range> r = parseRange( line.substr( 0, sp ) ) )
        {
            if( sp != std::string_view::npos )
            {
                const std::string_view rest = line.substr( sp + 1 );
                r->name = std::string( rest.substr( 0, rest.find( ' ' ) ) );
            }
            if( std::none_of( rows.begin(), rows.end(), [ & ]( const Range& x ) { return sameSpan( x, *r ); } ) )
            {
                rows.push_back( std::move( *r ) );
            }
        }
        return true;
    } );
    return rows;
}

inline ForCore readForPage( std::string_view page )
{
    ForCore          core;
    const std::size_t rootEnd = page.find( '>' );
    const std::string_view rootTag = page.substr( 0, rootEnd == std::string_view::npos ? 0 : rootEnd );
    core.confidence = std::string( attrOf( rootTag, "confidence" ) );
    core.at         = std::string( attrOf( rootTag, "at" ) );
    core.rows       = sigsRows( page );
    if( const std::size_t act = page.find( "<act read=\"" ); act != std::string_view::npos )
    {
        const std::size_t from = act + 11;
        const std::string_view list = page.substr( from, page.find( '"', from ) - from );
        for( std::size_t at = 0; at <= list.size(); )
        {
            std::size_t comma = list.find( ',', at );
            if( comma == std::string_view::npos )
            {
                comma = list.size();
            }
            if( std::optional<Range> r = parseRange( list.substr( at, comma - at ) ) )
            {
                core.act.push_back( std::move( *r ) );
            }
            at = comma + 1;
        }
    }
    core.shippedAct = int( core.act.size() );
    for( const Range& row : core.rows )
    {
        if( int( core.act.size() ) >= kActRanges )
        {
            break;
        }
        if( std::none_of( core.act.begin(), core.act.end(), [ & ]( const Range& a ) { return sameSpan( a, row ); } ) )
        {
            core.act.push_back( row );
        }
    }
    for( Range& a : core.act )
    {
        if( a.name.empty() )
        {
            if( const auto it = std::find_if( core.rows.begin(), core.rows.end(), [ & ]( const Range& r ) { return sameSpan( r, a ); } ); it != core.rows.end() )
            {
                a.name = it->name;
            }
        }
    }
    return core;
}

// The act files, in act order, each once.
inline std::vector<std::string> actFiles( const ForCore& core )
{
    std::vector<std::string> files;
    for( const Range& a : core.act )
    {
        pattern::appendUnique( files, a.path );
    }
    return files;
}

// The files that define a symbol the question names by an identifier-shaped token (BracketMatchingController, NodeAffinity), act
// files first, at most 2: the task's model or subject. They lead the file order every later step reads (entries' reach seeds,
// edges, imports, where-else). Test and skip-role definitions never count.
inline std::vector<std::string> namedFiles( const Corpus& c, std::string_view task, const std::vector<std::string>& act )
{
    std::vector<std::string> shaped;
    for( const qsites::Token& t : qsites::questionTokens( task ) )
    {
        if( t.shaped && t.wholeWord )
        {
            shaped.push_back( t.text );
        }
    }
    std::vector<std::string> named;
    for( const std::string& tok : shaped )
    {
        std::vector<std::string_view> defs;
        for( const Symbol& sym : c.ing.symbols )
        {
            if( sym.name == tok && sym.fileId < c.rel.size() && !isTestPath( c.rel[sym.fileId] ) && !isSkipRole( roleOfPath( c.rel[sym.fileId] ) ) )
            {
                defs.push_back( c.rel[sym.fileId] );
            }
        }
        std::sort( defs.begin(), defs.end(), [ & ]( std::string_view a, std::string_view b )
        {
            const bool ia = std::find( act.begin(), act.end(), a ) != act.end(), ib = std::find( act.begin(), act.end(), b ) != act.end();
            return ia != ib ? ia : a < b;
        } );
        if( !defs.empty() && std::find( named.begin(), named.end(), defs.front() ) == named.end() && named.size() < 2 )
        {
            named.emplace_back( defs.front() );
        }
    }
    return named;
}

// The working file order: the named files, then the act files.
inline std::vector<std::string> orderedFiles( const std::vector<std::string>& named, const std::vector<std::string>& act )
{
    std::vector<std::string> out = named;
    for( const std::string& f : act )
    {
        pattern::appendUnique( out, f );
    }
    return out;
}

// ── section 1: layout ───────────────────────────────────────────────────────────────────────────────────────────────────────
struct LayoutEntry
{
    std::string dir;     // with a trailing slash
    std::string role;
    int         files = 0;
    int         depth = 1;
};

inline std::string_view roleOfDir( std::string_view dir, std::string_view parentRole ) noexcept
{
    if( isSkipRole( parentRole ) || parentRole == "test" || parentRole == "docs" )
    {
        return parentRole;
    }
    const std::string_view name = baseName( dir );
    if( const char* r = roleOfName( name ) )
    {
        return r;
    }
    return parentRole.empty() ? std::string_view( "code" ) : parentRole;
}

// Files per child dir of `prefix` (an empty prefix = the root), largest first.
inline bool isDocExt( std::string_view rel ) noexcept
{
    const std::string_view b = baseName( rel );
    return b.ends_with( ".md" ) || b.ends_with( ".rst" ) || b.ends_with( ".adoc" ) || b.ends_with( ".txt" ) || b.ends_with( ".html" );
}

inline std::vector<LayoutEntry> childDirs( const Corpus& c, std::string_view prefix, std::string_view parentRole, int depth )
{
    HashMap<std::string_view, int> counts;
    HashMap<std::string_view, int> docCounts;   // a dir of prose files reads as docs whatever its name (libzmq RELICENSE/)
    counts.reserve( 64 );
    docCounts.reserve( 64 );
    for( const std::string_view r : c.rel )
    {
        if( !r.starts_with( prefix ) )
        {
            continue;
        }
        const std::string_view rest  = r.substr( prefix.size() );
        const std::size_t      slash = rest.find( '/' );
        if( slash != std::string_view::npos )
        {
            ++counts[ r.substr( 0, prefix.size() + slash + 1 ) ];
            if( isDocExt( r ) )
            {
                ++docCounts[ r.substr( 0, prefix.size() + slash + 1 ) ];
            }
        }
    }
    std::vector<LayoutEntry> out;
    out.reserve( counts.size() );
    for( const auto& [ dir, n ] : counts )
    {
        std::string role( roleOfDir( dir.substr( 0, dir.size() - 1 ), parentRole ) );
        const auto  docs = docCounts.find( dir );
        if( role == "code" && docs != docCounts.end() && docs->second * 5 >= n * 4 )
        {
            role = "docs";
        }
        out.push_back( { std::string( dir ), std::move( role ), n, depth } );
    }
    std::sort( out.begin(), out.end(), []( const LayoutEntry& a, const LayoutEntry& b ) { return a.files != b.files ? a.files > b.files : a.dir < b.dir; } );
    return out;
}

// Top dirs; a dir holding > 30 % of all files is replaced by its children (to depth 3) when `deep`.
inline std::vector<LayoutEntry> layoutEntries( const Corpus& c, bool deep )
{
    const int                total = int( c.rel.size() );
    std::vector<LayoutEntry> entries = childDirs( c, "", "", 1 );
    for( bool expanded = deep; expanded; )
    {
        expanded = false;
        for( std::size_t i = 0; i < entries.size(); ++i )
        {
            const LayoutEntry e = entries[i];
            if( e.depth >= 3 || isSkipRole( e.role ) || e.files * 10 <= total * 3 )
            {
                continue;
            }
            std::vector<LayoutEntry> kids = childDirs( c, e.dir, e.depth == 1 && e.role == "code" ? "" : e.role, e.depth + 1 );
            if( kids.size() < 2 )
            {
                continue;
            }
            entries.erase( entries.begin() + std::ptrdiff_t( i ) );
            entries.insert( entries.end(), kids.begin(), kids.end() );
            expanded = true;
            break;
        }
    }
    // the largest test dir (100+ files) shows its kinds of tests one level down (test/integration/, test/e2e/)
    const auto testDir = std::max_element( entries.begin(), entries.end(), []( const LayoutEntry& a, const LayoutEntry& b )
    {
        return ( a.role == "test" ? a.files : 0 ) < ( b.role == "test" ? b.files : 0 );
    } );
    if( deep && testDir != entries.end() && testDir->role == "test" && testDir->files >= 100 && testDir->depth < 3 )
    {
        std::vector<LayoutEntry> kids = childDirs( c, testDir->dir, "test", testDir->depth + 1 );
        if( kids.size() >= 2 )
        {
            kids.resize( std::min<std::size_t>( kids.size(), 4 ) );
            entries.erase( testDir );
            entries.insert( entries.end(), kids.begin(), kids.end() );
        }
    }
    std::sort( entries.begin(), entries.end(), []( const LayoutEntry& a, const LayoutEntry& b ) { return a.files != b.files ? a.files > b.files : a.dir < b.dir; } );
    // top-level dirs the index leaves out but a subagent's ls shows: build output (generated) and vendored copies (the crawl skips
    // third_party/, vendor/, node_modules/), each listed with 0 indexed files and its (skip) role
    const auto addUnindexed = [ & ]( std::string_view name, const char* role )
    {
        const std::string dir     = std::string( name ) + "/";
        const bool        indexed = std::any_of( entries.begin(), entries.end(), [ & ]( const LayoutEntry& e ) { return e.dir.starts_with( dir ); } );
        if( !indexed && isDir( joinPath( c.diskRoot, name ) ) )
        {
            entries.push_back( { dir, role, 0, 1 } );
        }
    };
    for( const std::string_view out : kBuildOutputDirs )
    {
        addUnindexed( out, "generated(skip)" );
    }
    for( const DirRole& r : kDirRoles )
    {
        if( isSkipRole( r.role ) )
        {
            addUnindexed( r.dir, r.role );
        }
    }
    return entries;
}

inline std::string renderLayout( const std::vector<LayoutEntry>& entries, int cap )
{
    std::string out = "<layout>";
    int         shown = 0, restDirs = 0, restFiles = 0;
    for( const LayoutEntry& e : entries )
    {
        if( shown >= cap )
        {
            ++restDirs;
            restFiles += e.files;
            continue;
        }
        out += ( shown > 0 ? " · " : "" ) + xml( e.dir ) + " " + e.role + " " + std::to_string( e.files );
        ++shown;
    }
    if( restDirs > 0 )
    {
        out += " · +" + std::to_string( restDirs ) + " dirs " + std::to_string( restFiles );
    }
    return out + "</layout>";
}

// ── section 2: build ────────────────────────────────────────────────────────────────────────────────────────────────────────
// Every line names the file it comes from. A docs line is a verbatim quote; a manifest line is the one command that manifest
// format runs, with target / script / env names quoted from the file. No manifest and no quote -> "none found".
inline constexpr std::string_view kDocSources[] = { "CLAUDE.md", "AGENTS.md", "CONTRIBUTING.md", "BUILDING.md", "HACKING.md", "README.md",
                                                    "INSTALL.md", "docs/CONTRIBUTING.md", ".github/CONTRIBUTING.md" };
inline constexpr std::string_view kCommandHeads[] = { "cmake ", "ctest ", "make ", "make\n", "ninja ", "npm ", "yarn ", "pnpm ", "go build", "go test", "cargo ",
                                                      "pytest", "python -m pytest", "python3 -m pytest", "tox", "nox", "bazel ", "meson ", "./gradlew ",
                                                      "mvn ", "./configure", "autoreconf ", "./autogen.sh", "bundle exec ", "rake " };

inline bool isCommandLine( std::string_view line ) noexcept
{
    std::string_view t = trim( line );
    if( t.starts_with( "$ " ) )
    {
        t.remove_prefix( 2 );
    }
    for( const std::string_view head : kCommandHeads )
    {
        if( t.starts_with( head ) || ( head.back() == ' ' && t == head.substr( 0, head.size() - 1 ) ) )
        {
            return t.size() <= 110;
        }
    }
    return false;
}

// The first command lines inside fenced code blocks of the repo's own docs, quoted with path:line.
inline std::vector<std::string> quotedDocCommands( const Corpus& c, int cap, std::vector<std::string>& sources )
{
    std::vector<std::string> out;
    for( const std::string_view doc : kDocSources )
    {
        if( int( out.size() ) >= cap )
        {
            break;
        }
        const std::optional<std::string> text = c.exists( doc ) ? c.read( doc ) : std::nullopt;
        if( !text )
        {
            continue;
        }
        bool inFence = false;
        forEachLine( *text, [ & ]( std::string_view line, int lineNo )
        {
            const std::string_view t = trim( line );
            if( t.starts_with( "```" ) )
            {
                inFence = !inFence;
                return true;
            }
            if( inFence && isCommandLine( t ) )
            {
                std::string_view cmd = t.starts_with( "$ " ) ? t.substr( 2 ) : t;
                if( const std::size_t hash = cmd.find( "  #" ); hash != std::string_view::npos )
                {
                    cmd = trim( cmd.substr( 0, hash ) );
                }
                const bool dup = std::any_of( out.begin(), out.end(), [ & ]( const std::string& o ) { return o.ends_with( std::string( cmd ) ); } );
                if( !dup )
                {
                    out.push_back( std::string( doc ) + ":" + std::to_string( lineNo ) + " " + std::string( cmd ) );
                    sources.emplace_back( doc );
                }
            }
            return int( out.size() ) < cap;
        } );
    }
    return out;
}

// Make targets of a Makefile that a subagent runs (quoted only when the file defines them).
inline std::vector<std::string> makeTargets( std::string_view text )
{
    static constexpr std::string_view kWanted[] = { "all", "build", "test", "check", "unit", "test-unit", "verify", "lint" };
    std::vector<std::string> found;
    forEachLine( text, [ & ]( std::string_view line, int )
    {
        const std::size_t colon = line.find( ':' );
        if( colon == std::string_view::npos || colon == 0 || line.substr( colon ).starts_with( ":=" ) )
        {
            return true;
        }
        const std::string_view name = line.substr( 0, colon );
        for( const std::string_view w : kWanted )
        {
            if( name == w && std::find( found.begin(), found.end(), name ) == found.end() )
            {
                found.emplace_back( name );
            }
        }
        return true;
    } );
    std::sort( found.begin(), found.end(), [ & ]( const std::string& a, const std::string& b )
    {
        const auto rank = [ & ]( const std::string& t ) { return std::find( std::begin( kWanted ), std::end( kWanted ), t ) - std::begin( kWanted ); };
        return rank( a ) < rank( b );
    } );
    if( found.size() > 3 )
    {
        found.resize( 3 );
    }
    return found;
}

// package.json "scripts" names a subagent runs, in a fixed order; reads only the keys of the scripts object.
inline std::vector<std::string> packageScripts( std::string_view json )
{
    static constexpr std::string_view kWanted[] = { "build", "compile", "test", "test-node", "test-unit", "watch", "lint" };
    std::vector<std::string> found;
    const std::size_t        at = json.find( "\"scripts\"" );
    const std::size_t        open = at == std::string_view::npos ? at : json.find( '{', at );
    const std::size_t        shut = open == std::string_view::npos ? open : json.find( '}', open );
    if( shut == std::string_view::npos )
    {
        return found;
    }
    const std::string_view body = json.substr( open, shut - open );
    for( const std::string_view w : kWanted )
    {
        if( body.find( "\"" + std::string( w ) + "\":" ) != std::string_view::npos || body.find( "\"" + std::string( w ) + "\" :" ) != std::string_view::npos )
        {
            found.emplace_back( w );
        }
    }
    return found;
}

// The command a package.json script runs, quoted (cut at 90 B); "" when the script is absent.
inline std::string packageScriptBody( std::string_view json, std::string_view name )
{
    const std::string key = "\"" + std::string( name ) + "\":";
    const std::size_t at  = json.find( key, json.find( "\"scripts\"" ) == std::string_view::npos ? json.size() : json.find( "\"scripts\"" ) );
    const std::size_t q1  = at == std::string_view::npos ? at : json.find( '"', at + key.size() );
    const std::size_t q2  = q1 == std::string_view::npos ? q1 : json.find( '"', q1 + 1 );
    if( q2 == std::string_view::npos )
    {
        return {};
    }
    std::string body( json.substr( q1 + 1, std::min<std::size_t>( q2 - q1 - 1, 90 ) ) );
    return body;
}

// tox.ini's envlist, quoted (the first 3 names).
inline std::string toxEnvs( std::string_view ini )
{
    const std::size_t at = ini.find( "envlist" );
    if( at == std::string_view::npos )
    {
        return {};
    }
    const std::size_t eq = ini.find( '=', at );
    std::string_view  v  = eq == std::string_view::npos ? std::string_view() : ini.substr( eq + 1 );
    v = trim( v.substr( 0, v.find( '\n' ) ) );
    std::string out;
    int         n = 0;
    for( std::size_t from = 0; from < v.size() && n < 3; )
    {
        std::size_t comma = v.find( ',', from );
        if( comma == std::string_view::npos )
        {
            comma = v.size();
        }
        const std::string_view env = trim( v.substr( from, comma - from ) );
        if( !env.empty() && env.find( '{' ) == std::string_view::npos )
        {
            out += ( n++ > 0 ? "," : "" ) + std::string( env );
        }
        from = comma + 1;
    }
    return out;
}

// The dir of the first act file that sits under `under` (Go / Bazel package paths), "" when none.
inline std::string actDirUnder( const std::vector<std::string>& files, std::string_view ext )
{
    for( const std::string& f : files )
    {
        if( f.ends_with( ext ) && !dirName( f ).empty() )
        {
            return std::string( dirName( f ) );
        }
    }
    return {};
}

// The nearest Cargo.toml above `file` with a [package] name.
inline std::string cargoCrate( const Corpus& c, std::string_view file )
{
    for( std::string_view dir = dirName( file );; dir = dirName( dir ) )
    {
        const std::string manifest = dir.empty() ? std::string( "Cargo.toml" ) : std::string( dir ) + "/Cargo.toml";
        if( c.exists( manifest ) )
        {
            if( const std::optional<std::string> t = c.read( manifest ) )
            {
                const std::size_t pkg  = t->find( "[package]" );
                const std::size_t name = pkg == std::string::npos ? pkg : t->find( "name", pkg );
                const std::size_t q1   = name == std::string::npos ? name : t->find( '"', name );
                const std::size_t q2   = q1 == std::string::npos ? q1 : t->find( '"', q1 + 1 );
                if( q2 != std::string::npos && t->substr( name, q1 - name ).find( '\n' ) == std::string::npos )
                {
                    return t->substr( q1 + 1, q2 - q1 - 1 );
                }
            }
        }
        if( dir.empty() )
        {
            return {};
        }
    }
}

// A monorepo whose root manifests name no command (llvm-project: a root pyproject.toml for its tooling only): the top dir of the
// first act file that holds a manifest of its own (llvm/CMakeLists.txt).
inline std::string monorepoManifestDir( const Corpus& c, const std::vector<std::string>& files )
{
    static constexpr std::string_view kDirManifests[] = { "CMakeLists.txt", "Makefile", "package.json", "go.mod", "Cargo.toml", "pyproject.toml", "meson.build" };
    for( const std::string& f : files )
    {
        const std::size_t slash = f.find( '/' );
        for( const std::string_view m : kDirManifests )
        {
            if( slash != std::string::npos && c.exists( f.substr( 0, slash + 1 ) + std::string( m ) ) )
            {
                return f.substr( 0, slash + 1 );
            }
        }
    }
    return {};
}

// One manifest dir's reader and the command list it appends to: has / read a file under `base`, add a `path: command` line.
struct ManifestSink
{
    const Corpus&             c;
    std::string               base;
    std::vector<std::string>& lines;
    std::vector<std::string>& sources;

    bool has( std::string_view name ) const { return c.exists( base + std::string( name ) ); }
    std::optional<std::string> read( std::string_view name ) const { return c.read( base + std::string( name ) ); }
    void add( std::string_view source, std::string cmd ) const
    {
        lines.push_back( base + std::string( source ) + ": " + std::move( cmd ) );
        sources.push_back( base + std::string( source ) );
    }
};

// CMake (ctest when the file enables testing) and autotools (make check when Makefile.am lists TESTS).
inline void addConfigureCommands( const ManifestSink& m )
{
    if( m.has( "CMakeLists.txt" ) )
    {
        const std::optional<std::string> t     = m.read( "CMakeLists.txt" );
        const bool                       tests = t && ( t->find( "enable_testing" ) != std::string::npos || t->find( "include(CTest)" ) != std::string::npos );
        const std::string                src   = m.base.empty() ? "." : m.base.substr( 0, m.base.size() - 1 );
        m.add( "CMakeLists.txt", "cmake -S " + src + " -B build && cmake --build build" + ( tests ? " && ctest --test-dir build" : "" ) );
    }
    if( m.has( "configure.ac" ) && m.has( "Makefile.am" ) )
    {
        const std::optional<std::string> t     = m.read( "Makefile.am" );
        const bool                       check = t && ( t->find( "TESTS" ) != std::string::npos || t->find( "check_PROGRAMS" ) != std::string::npos );
        m.add( "configure.ac", std::string( m.has( "autogen.sh" ) ? "./autogen.sh" : "autoreconf -fi" ) + " && ./configure && make" + ( check ? " && make check" : "" ) );
    }
}

// A Makefile's own targets, quoted by name.
inline void addMakeCommands( const ManifestSink& m )
{
    for( const std::string_view mk : { std::string_view( "Makefile" ), std::string_view( "GNUmakefile" ) } )
    {
        if( !m.has( mk ) )
        {
            continue;
        }
        const std::optional<std::string> t = m.read( mk );
        std::string                      cmd;
        for( const std::string& target : t ? makeTargets( *t ) : std::vector<std::string>{} )
        {
            cmd += ( cmd.empty() ? "make " : " · make " ) + target;
        }
        if( !cmd.empty() )
        {
            m.add( mk, cmd );
        }
        return;
    }
}

// package.json's scripts by name (the lockfile picks the tool), the test script's own body, and a gulpfile's task source.
inline void addNodeCommands( const ManifestSink& m )
{
    if( m.has( "package.json" ) )
    {
        const std::optional<std::string> t    = m.read( "package.json" );
        const std::string                tool = m.has( "yarn.lock" ) ? "yarn" : m.has( "pnpm-lock.yaml" ) ? "pnpm" : "npm";
        std::string                      cmd;
        for( const std::string& script : t ? packageScripts( *t ) : std::vector<std::string>{} )
        {
            cmd += ( cmd.empty() ? "" : " · " ) + tool + ( script == "test" && tool == "npm" ? " test" : " run " + script );
        }
        if( !cmd.empty() )
        {
            m.add( "package.json", cmd );
        }
        for( const std::string_view name : { std::string_view( "test-node" ), std::string_view( "test" ) } )
        {
            if( const std::string scriptBody = t ? packageScriptBody( *t, name ) : std::string(); !scriptBody.empty() )
            {
                m.add( "package.json", std::string( name ) + " = " + scriptBody );
                break;
            }
        }
    }
    for( const std::string_view gulp : { std::string_view( "gulpfile.js" ), std::string_view( "gulpfile.mjs" ), std::string_view( "gulpfile.ts" ) } )
    {
        if( m.has( gulp ) )
        {
            const std::optional<std::string> t   = m.read( gulp );
            const std::size_t                imp = t ? t->find( "./build/" ) : std::string::npos;
            const std::size_t                end = imp == std::string::npos ? imp : t->find_first_of( "'\"", imp );
            m.add( gulp, "gulp tasks" + ( end == std::string::npos ? std::string() : ", loaded from " + t->substr( imp + 2, end - imp - 2 ) ) );
            return;
        }
    }
}

// Go, Cargo, tox and pytest: the act's package dir / crate / tox envs narrow the test command.
inline void addLanguageToolCommands( const ManifestSink& m, const std::vector<std::string>& files )
{
    if( m.has( "go.mod" ) )
    {
        const std::string dir = actDirUnder( files, ".go" );
        m.add( "go.mod", "go build ./... · go test ./" + ( dir.empty() ? std::string( "..." ) : dir + "/..." ) );
    }
    if( m.has( "Cargo.toml" ) )
    {
        const std::string crate = files.empty() ? std::string() : cargoCrate( m.c, files.front() );
        m.add( "Cargo.toml", "cargo build · cargo test" + ( crate.empty() ? std::string() : " -p " + crate ) );
    }
    if( m.has( "tox.ini" ) )
    {
        const std::optional<std::string> t    = m.read( "tox.ini" );
        const std::string                envs = t ? toxEnvs( *t ) : std::string();
        m.add( "tox.ini", "tox" + ( envs.empty() ? std::string() : " -e " + envs ) );
    }
    const auto namesPytest = [ & ]( std::string_view f )
    {
        const std::optional<std::string> t = m.has( f ) ? m.read( f ) : std::nullopt;
        return t && t->find( "pytest" ) != std::string::npos;
    };
    static constexpr std::string_view kPytestConfigs[] = { "pyproject.toml", "setup.cfg", "pytest.ini", "tox.ini", "test_requirements.txt", "requirements-dev.txt" };
    if( std::any_of( std::begin( kPytestConfigs ), std::end( kPytestConfigs ), namesPytest ) )
    {
        m.add( m.has( "pyproject.toml" ) ? "pyproject.toml" : "setup.cfg", "pytest" + std::string( m.has( "tests/" ) || m.has( "tests" ) ? " tests" : "" ) );
    }
}

// Rake, Maven, Gradle, Bazel (the act dir's package) and meson.
inline void addBuildSystemCommands( const ManifestSink& m, const std::vector<std::string>& files )
{
    if( m.has( "Gemfile" ) && m.has( "Rakefile" ) )
    {
        m.add( "Rakefile", "bundle exec rake" );
    }
    if( m.has( "pom.xml" ) )
    {
        m.add( "pom.xml", "mvn test" );
    }
    if( m.has( "build.gradle" ) || m.has( "build.gradle.kts" ) )
    {
        m.add( m.has( "build.gradle" ) ? "build.gradle" : "build.gradle.kts", m.has( "gradlew" ) ? "./gradlew test" : "gradle test" );
    }
    if( m.has( "MODULE.bazel" ) || m.has( "WORKSPACE" ) )
    {
        const std::string dir = files.empty() ? std::string() : std::string( dirName( files.front() ) );
        m.add( m.has( "MODULE.bazel" ) ? "MODULE.bazel" : "WORKSPACE", "bazel test //" + ( dir.empty() ? std::string( "..." ) : dir + "/..." ) );
    }
    if( m.has( "meson.build" ) )
    {
        m.add( "meson.build", "meson setup build && meson test -C build" );
    }
}

// Every manifest under `base`, in a fixed family order. A script or target name is quoted from its file; a manifest kind's
// own build/test command (cmake, cargo, go, mvn …) is that tool's documented invocation, labelled with the manifest it reads.
inline void addManifestCommandsAt( const Corpus& c, const std::string& base, const std::vector<std::string>& files, std::vector<std::string>& lines,
                                   std::vector<std::string>& sources )
{
    const ManifestSink m{ c, base, lines, sources };
    addConfigureCommands( m );
    addMakeCommands( m );
    addNodeCommands( m );
    addLanguageToolCommands( m, files );
    addBuildSystemCommands( m, files );
}

// The root's manifests; when they name no command, the monorepo dir the act lives in.
inline void addManifestCommands( const Corpus& c, const std::vector<std::string>& files, std::vector<std::string>& lines, std::vector<std::string>& sources )
{
    addManifestCommandsAt( c, std::string(), files, lines, sources );
    if( const std::string sub = lines.empty() ? monorepoManifestDir( c, files ) : std::string(); !sub.empty() )
    {
        addManifestCommandsAt( c, sub, files, lines, sources );
    }
}

// The project's own name, quoted from its manifest (CMake project(), autoconf AC_INIT, package.json / Cargo / pyproject name, the
// last go.mod module segment), lower-cased; "" when none names one. It ranks the header named after the project first and joins the
// test-file stems (tests/test_black.py, tests/jq.test).
inline std::string projectName( const Corpus& c )
{
    const auto between = []( std::string_view t, std::string_view open, std::string_view stops ) -> std::string
    {
        const std::size_t at = t.find( open );
        if( at == std::string_view::npos )
        {
            return {};
        }
        std::string_view v = t.substr( at + open.size() );
        while( !v.empty() && ( v.front() == ' ' || v.front() == '[' || v.front() == '"' || v.front() == '(' ) )
        {
            v.remove_prefix( 1 );
        }
        return lower( v.substr( 0, v.find_first_of( stops ) ) );
    };
    if( const std::optional<std::string> t = c.exists( "CMakeLists.txt" ) ? c.read( "CMakeLists.txt" ) : std::nullopt )
    {
        if( std::string n = between( *t, "project(", " )\n\t\"" ); !n.empty() )
        {
            return n;
        }
    }
    if( const std::optional<std::string> t = c.exists( "configure.ac" ) ? c.read( "configure.ac" ) : std::nullopt )
    {
        if( std::string n = between( *t, "AC_INIT(", "],)\n" ); !n.empty() )
        {
            return n;
        }
    }
    for( const std::string_view m : { std::string_view( "pyproject.toml" ), std::string_view( "Cargo.toml" ) } )
    {
        if( const std::optional<std::string> t = c.exists( m ) ? c.read( m ) : std::nullopt )
        {
            if( std::string n = between( *t, "\nname = ", "\"\n" ); !n.empty() )
            {
                return n;
            }
        }
    }
    if( const std::optional<std::string> t = c.exists( "package.json" ) ? c.read( "package.json" ) : std::nullopt )
    {
        if( std::string n = between( *t, "\"name\":", "\",\n" ); !n.empty() )
        {
            return n;
        }
    }
    if( const std::optional<std::string> t = c.exists( "go.mod" ) ? c.read( "go.mod" ) : std::nullopt )
    {
        const std::string mod = between( *t, "module ", "\n " );
        return std::string( baseName( mod ) );
    }
    return {};
}

// ── the test home of the act files (shared by build's registration line and where-else) ─────────────────────────────────────
struct TestHome
{
    std::vector<std::string> testFiles;   // test files named after an act file stem or an act symbol (≤ 3)
    std::string              testDir;     // a test dir mirroring an act file (llvm/test/Transforms/LoopVectorize/)
    std::string              registrar;   // the build file that lists the test files by name, as path:line (Makefile.am:143)
    std::string              runner;      // a test runner config above the test dir (lit.cfg.py)
    std::string              helper;      // the non-test file the test files import most (tests/util.py)
    std::string              dataDir;     // the test dir's biggest subdir of fixture files (tests/data/cases/)
};

// Test files the index does not hold (tests/jq.test, tests/jqtest: data and shell drivers), listed from each top-level test dir.
inline std::vector<std::string> unindexedTestFiles( const Corpus& c )
{
    std::vector<std::string> out;
    std::vector<std::string> tops;
    for( const std::string_view r : c.rel )
    {
        const std::size_t slash = r.find( '/' );
        const std::string top( r.substr( 0, slash == std::string_view::npos ? 0 : slash ) );
        if( !top.empty() && roleOfPath( r ) == "test" && std::find( tops.begin(), tops.end(), top ) == tops.end() )
        {
            tops.push_back( top );
        }
    }
    for( const std::string& top : tops )
    {
        std::error_code ec;
        for( auto it = std::filesystem::directory_iterator( joinPath( c.diskRoot, top ), ec ); !ec && it != std::filesystem::directory_iterator(); it.increment( ec ) )
        {
            const std::string rel = top + "/" + it->path().filename().string();
            if( it->is_regular_file( ec ) && !c.fileOf.contains( rel ) )
            {
                out.push_back( rel );
            }
        }
    }
    std::sort( out.begin(), out.end() );
    return out;
}

// The project's own name opens the file name (tests/jqtest, tests/jq.test for jq): a short name matches as a prefix only.
inline bool pathNamesProject( std::string_view rel, std::string_view project )
{
    return project.size() >= 2 && lower( baseName( rel ) ).starts_with( project );
}

inline std::vector<std::string> taskStems( const ForCore& core, const std::vector<std::string>& files, std::string_view project = {} )
{
    std::vector<std::string> stems;
    const auto add = [ & ]( std::string_view s )
    {
        std::string lo = lower( s );
        if( lo.size() >= 3 && std::find( stems.begin(), stems.end(), lo ) == stems.end() )
        {
            stems.push_back( std::move( lo ) );
        }
    };
    for( std::size_t i = 0; i < files.size() && i < 3; ++i )
    {
        add( stemOf( files[i] ) );
    }
    for( std::size_t i = 0; i < core.act.size() && i < 5; ++i )
    {
        std::string_view n = core.act[i].name;
        if( const std::size_t cut = n.rfind( "::" ); cut != std::string_view::npos )
        {
            n = n.substr( cut + 2 );
        }
        add( n );
    }
    if( !project.empty() )
    {
        add( project );
    }
    return stems;
}

// The file name has a stem as one of its word parts (test_ctx_options.cpp: test, ctx, options), or — for a stem of 5+ bytes — as a
// substring once _ and - are gone (LoopVectorize/, loop_vectorize).
inline bool pathNamesStem( std::string_view rel, const std::vector<std::string>& stems )
{
    const std::string        lo = lower( baseName( rel ) );
    std::string              flat;
    std::vector<std::string> parts( 1 );
    for( const char ch : lo )
    {
        if( ch == '_' || ch == '-' || ch == '.' || ch == ' ' )
        {
            parts.emplace_back();
        }
        else
        {
            parts.back() += ch;
            flat += ch;
        }
    }
    return std::any_of( stems.begin(), stems.end(), [ & ]( const std::string& s )
    {
        return std::find( parts.begin(), parts.end(), s ) != parts.end() || ( s.size() >= 5 && flat.find( s ) != std::string::npos );
    } );
}

// Beside the first test file: the non-test file its sibling tests import most (2+ importers), and the sibling subdir with the most
// indexed files (20+), where fixture cases live.
inline void findTestSupport( const Corpus& c, const FileAdjacency& adj, TestHome& home )
{
    if( home.testFiles.empty() || !home.testDir.empty() )
    {
        return;
    }
    const std::string      dir = std::string( dirName( home.testFiles.front() ) ) + "/";
    std::vector<int>       importers( c.rel.size(), 0 );
    HashMap<std::string_view, int> subdirFiles;
    for( std::uint32_t f = 0; f < c.rel.size(); ++f )
    {
        const std::string_view r = c.rel[f];
        if( !r.starts_with( dir ) )
        {
            continue;
        }
        if( const std::size_t slash = r.find( '/', dir.size() ); slash != std::string_view::npos )
        {
            ++subdirFiles[dirName( r )];
        }
        const bool testNamed = baseName( r ).starts_with( "test" ) || isTestPath( std::string( "x/" ) + std::string( baseName( r ) ) );
        for( std::size_t k = 0; testNamed && f < adj.size() && k < adj[f].size(); ++k )
        {
            if( const std::uint32_t to = adj[f][k]; to < importers.size() && to != f )
            {
                ++importers[to];
            }
        }
    }
    int best = 1;
    for( std::uint32_t f = 0; f < c.rel.size(); ++f )
    {
        const std::string_view r = c.rel[f];
        if( r.starts_with( dir ) && dirName( r ).size() + 1 == dir.size() && !baseName( r ).starts_with( "test" ) && !baseName( r ).starts_with( "__init__" )
            && !baseName( r ).starts_with( "conftest" ) && importers[f] > best )
        {
            best        = importers[f];
            home.helper = std::string( r );
        }
    }
    int most = 19;
    for( const auto& [ d, n ] : subdirFiles )
    {
        if( n > most || ( n == most && !home.dataDir.empty() && std::string( d ) + "/" < home.dataDir ) )
        {
            most         = n;
            home.dataDir = std::string( d ) + "/";
        }
    }
}

// The project's own test file: its stem is the project name with a test prefix or suffix, or bare (test_black.py, jqtest, jq.test).
inline bool isProjectTestFile( std::string_view rel, std::string_view project )
{
    std::string stem = lower( stemOf( rel ) );
    for( const std::string_view pre : { "test_", "test-", "test" } )
    {
        if( stem.starts_with( pre ) && stem.size() > pre.size() )
        {
            stem.erase( 0, pre.size() );
            break;
        }
    }
    for( const std::string_view suf : { "_tests", "_test", "-test", "test" } )
    {
        if( stem.ends_with( suf ) && stem.size() > suf.size() )
        {
            stem.resize( stem.size() - suf.size() );
            break;
        }
    }
    // only in a top-level test dir: a nested sub-project's llvm.c under mlir/test/CAPI/ is not llvm-project's own test file
    const std::size_t slash = rel.find( '/' );
    const char*       role  = slash == std::string_view::npos ? nullptr : roleOfName( rel.substr( 0, slash ) );
    return !project.empty() && stem == project && role != nullptr && std::string_view( role ) == "test";
}

// Each test root: a path up to its first test-role dir (llvm/test/, clang/test/, tests/), from the indexed files, at most 64.
inline std::vector<std::string> testRoots( const Corpus& c )
{
    std::vector<std::string> roots;
    for( const std::string_view r : c.rel )
    {
        for( std::size_t at = 0, slash = r.find( '/' ); slash != std::string_view::npos && roots.size() < 64; at = slash + 1, slash = r.find( '/', at ) )
        {
            const char* role = roleOfName( r.substr( at, slash - at ) );
            if( role != nullptr && std::string_view( role ) == "test" )
            {
                pattern::appendUnique( roots, std::string( r.substr( 0, slash + 1 ) ) );
                break;
            }
        }
    }
    return roots;
}

// A dir name mirrors a stem: an 8+ byte shared prefix (LoopVectorize / loopvectorizationplanner) or the stem itself.
inline bool dirMirrorsStem( std::string_view dirName, const std::vector<std::string>& stems )
{
    const std::string lo = lower( dirName );
    return std::any_of( stems.begin(), stems.end(), [ & ]( const std::string& stem )
    {
        const std::ptrdiff_t shared = std::mismatch( stem.begin(), stem.end(), lo.begin(), lo.end() ).first - stem.begin();
        return shared >= 8 || ( stem.size() >= 3 && lo == stem );
    } );
}

// Entries directly in `dir`, counted to 5000.
inline int entryCount( const std::filesystem::path& dir )
{
    std::error_code ec;
    int             n = 0;
    for( auto f = std::filesystem::directory_iterator( dir, ec ); !ec && f != std::filesystem::directory_iterator() && n < 5000; f.increment( ec ) )
    {
        ++n;
    }
    return n;
}

// `dir`'s subdirs, sorted (directory_iterator order is the filesystem's).
inline std::vector<std::filesystem::path> sortedSubdirs( const std::filesystem::path& dir )
{
    std::error_code                    ec;
    std::vector<std::filesystem::path> kids;
    for( auto it = std::filesystem::directory_iterator( dir, ec ); !ec && it != std::filesystem::directory_iterator(); it.increment( ec ) )
    {
        if( it->is_directory( ec ) )
        {
            kids.push_back( it->path() );
        }
    }
    std::sort( kids.begin(), kids.end() );
    return kids;
}

// A mirrored test dir: a dir three levels or less under a test root whose name mirrors an act file's stem (LoopVectorizationPlanner.h
// -> llvm/test/Transforms/LoopVectorize/, 610 .ll files the index does not hold). Read from disk, breadth-first, at most 50000
// dirs; the fullest mirroring dir wins, ties to the smaller path.
inline std::string mirroredTestDir( const Corpus& c, const std::vector<std::string>& files )
{
    std::vector<std::string> stems;
    for( std::size_t i = 0; i < files.size() && i < 3; ++i )
    {
        stems.push_back( lower( stemOf( files[i] ) ) );
    }
    std::string best;
    int         most     = 0;
    int         dirsSeen = 0;
    for( const std::string& root : testRoots( c ) )
    {
        const std::filesystem::path        rootPath( joinPath( c.diskRoot, root ) );
        std::vector<std::filesystem::path> level{ rootPath };
        for( int depth = 0; depth < 3 && !level.empty() && dirsSeen < 50000; ++depth )
        {
            std::vector<std::filesystem::path> next;
            for( const std::filesystem::path& dir : level )
            {
                for( const std::filesystem::path& kid : sortedSubdirs( dir ) )
                {
                    if( ++dirsSeen > 50000 )
                    {
                        break;
                    }
                    next.push_back( kid );
                    const int n = dirMirrorsStem( kid.filename().string(), stems ) ? entryCount( kid ) : 0;
                    std::error_code   ec;
                    const std::string rel = root + std::filesystem::relative( kid, rootPath, ec ).generic_string() + "/";
                    if( n > most || ( n > 0 && n == most && rel < best ) )
                    {
                        most = n;
                        best = rel;
                    }
                }
            }
            level = std::move( next );
        }
    }
    return best;
}

// The candidate test files, best first: a test named by the task's own files and symbols, or the project's own test file
// (test_black.py, tests/jqtest), before one that only carries the project's name (llvm-section-types.yaml), then the nearest.
inline std::vector<std::string> rankedTestFiles( const Corpus& c, const ForCore& core, const std::vector<std::string>& files, std::string_view project,
                                                 const std::vector<std::string>& stems )
{
    std::vector<std::string> tests;
    for( const std::string_view r : c.rel )
    {
        if( isTestPath( r ) && !isSkipRole( roleOfPath( r ) ) && pathNamesStem( r, stems ) )
        {
            tests.emplace_back( r );
        }
    }
    for( std::string& r : unindexedTestFiles( c ) )
    {
        if( pathNamesStem( r, stems ) || pathNamesProject( r, project ) )
        {
            tests.push_back( std::move( r ) );
        }
    }
    const std::string_view         anchor   = files.empty() ? std::string_view() : std::string_view( files.front() );
    const std::vector<std::string> taskOnly = taskStems( core, files );
    const auto byTask = [ & ]( std::string_view t ) { return pathNamesStem( t, taskOnly ) || isProjectTestFile( t, project ) ? 1 : 0; };
    std::sort( tests.begin(), tests.end(), [ & ]( const std::string& a, const std::string& b )
    {
        const int ta = byTask( a ), tb = byTask( b );
        const int pa = commonPrefixDirs( a, anchor ), pb = commonPrefixDirs( b, anchor );
        return ta != tb ? ta > tb : pa != pb ? pa > pb : a.size() != b.size() ? a.size() < b.size() : a < b;
    } );
    return tests;
}

// Each dir from `path`'s own up to the root ("" last), until `visit` returns true.
template<class Visit>
inline void forEachDirUp( std::string_view path, Visit&& visit )
{
    for( std::string_view dir = dirName( path );; dir = dirName( dir ) )
    {
        if( visit( dir ) || dir.empty() )
        {
            return;
        }
    }
}

inline std::string underDir( std::string_view dir, std::string_view name )
{
    return dir.empty() ? std::string( name ) : std::string( dir ) + "/" + std::string( name );
}

// The build file above a test file that lists it by stem, as path:line (Makefile.am:143, CMakeLists.txt:44).
inline std::string testRegistrar( const Corpus& c, const std::vector<std::string>& testFiles )
{
    static constexpr std::string_view kRegistrars[] = { "CMakeLists.txt", "Makefile.am", "meson.build", "BUILD", "BUILD.bazel" };
    std::string registrar;
    for( const std::string& t : testFiles )
    {
        forEachDirUp( t, [ & ]( std::string_view dir )
        {
            for( const std::string_view reg : kRegistrars )
            {
                const std::string                path = underDir( dir, reg );
                const std::optional<std::string> text = c.exists( path ) ? c.read( path ) : std::nullopt;
                const std::size_t                at   = text ? text->find( std::string( stemOf( t ) ) ) : std::string::npos;
                if( at != std::string::npos )
                {
                    registrar = path + ":" + std::to_string( 1 + std::count( text->begin(), text->begin() + std::ptrdiff_t( at ), '\n' ) );
                    return true;
                }
            }
            return false;
        } );
        if( !registrar.empty() )
        {
            break;
        }
    }
    return registrar;
}

// The test runner config nearest above `from` (lit.cfg.py, conftest.py, jest.config.js).
inline std::string testRunner( const Corpus& c, std::string_view from )
{
    std::string runner;
    if( from.empty() )
    {
        return runner;
    }
    forEachDirUp( from, [ & ]( std::string_view dir )
    {
        for( const std::string_view cfg : { std::string_view( "lit.cfg.py" ), std::string_view( "conftest.py" ), std::string_view( "jest.config.js" ) } )
        {
            if( c.exists( underDir( dir, cfg ) ) )
            {
                runner = underDir( dir, cfg );
                return true;
            }
        }
        return false;
    } );
    return runner;
}

inline TestHome findTestHome( const Corpus& c, const FileAdjacency& adj, const ForCore& core, const std::vector<std::string>& files, std::string_view project )
{
    TestHome                       home;
    const std::vector<std::string> stems = taskStems( core, files, project );
    const std::vector<std::string> tests = rankedTestFiles( c, core, files, project, stems );
    home.testFiles.assign( tests.begin(), tests.begin() + std::ptrdiff_t( std::min<std::size_t>( tests.size(), 3 ) ) );
    // the mirrored dir from disk, else a test-role dir named by a stem
    home.testDir = mirroredTestDir( c, files );
    for( std::size_t i = 0; home.testDir.empty() && i < tests.size(); ++i )
    {
        const std::string_view dir = dirName( tests[i] );
        if( pathNamesStem( dir, stems ) && roleOfPath( std::string( dir ) + "/x" ) == "test" )
        {
            home.testDir = std::string( dir ) + "/";
        }
    }
    home.registrar = testRegistrar( c, home.testFiles );
    findTestSupport( c, adj, home );
    home.runner = testRunner( c, !home.testDir.empty() ? std::string_view( home.testDir ) : home.testFiles.empty() ? std::string_view() : std::string_view( home.testFiles.front() ) );
    return home;
}

inline std::string renderBuild( const std::vector<std::string>& lines, int more, const TestHome& home )
{
    std::string out = "<build>";
    for( std::size_t i = 0; i < lines.size(); ++i )
    {
        out += ( i > 0 ? " | " : "" ) + xml( lines[i] );
    }
    if( more > 0 )   // manifest commands past kBuildLines: counted, their files are in the sources the root's build_source names
    {
        out += " | +" + std::to_string( more );
    }
    if( lines.empty() )
    {
        out += "none found";
    }
    if( !home.registrar.empty() )
    {
        out += " | new test -> list it in " + xml( home.registrar );
    }
    if( !home.runner.empty() )
    {
        out += " | tests run by " + xml( home.runner ) + ( home.testDir.empty() ? std::string() : " (" + xml( home.testDir ) + ")" );
    }
    if( !home.helper.empty() || !home.dataDir.empty() )
    {
        out += " | test support:" + ( home.helper.empty() ? std::string() : " helpers " + xml( home.helper ) ) + ( home.dataDir.empty() ? std::string() : " cases " + xml( home.dataDir ) );
    }
    return out + "</build>";
}

// ── section 3: entry ────────────────────────────────────────────────────────────────────────────────────────────────────────
struct Entry
{
    std::uint32_t fileId = 0;
    std::uint32_t line   = 0;
    std::string   what;          // "main", "__main__", "package.json main", "public header"
    int           hops   = -1;   // call/include hops to the task's seeds; -1 = not reached
    int           prefix = 0;    // path words shared with the primary file (the tie-break)
    int           rankKey = 255; // EntryReach::of's key: primary hops, 64 + act hops, 255 unreached, 256 a generator; -1 = the manifest's own entry
    int           size   = 0;    // indexed files under the entry's dir: the bigger program leads among far entries
};

// Far reach is a weak signal: hops past 3 rank as one band, where program size and shared path words decide (kubelet before genman).
inline int rankBand( int rankKey ) noexcept
{
    if( rankKey < 0 || rankKey >= 255 )
    {
        return rankKey;
    }
    return rankKey < 64 ? std::min( rankKey, 3 ) : 64 + std::min( rankKey - 64, 3 );
}

// Hops from each node back to the act symbols, over callers (reverse call edges), at most kReachHops.
inline std::vector<std::int8_t> callerHops( const Corpus& c, std::span<const std::uint32_t> seeds )
{
    const std::size_t        n = c.ing.symbols.size();
    std::vector<std::int8_t> hops( n, -1 );
    std::vector<std::uint32_t> frontier;
    for( const std::uint32_t s : seeds )
    {
        if( s < n && hops[s] < 0 )
        {
            hops[s] = 0;
            frontier.push_back( s );
        }
    }
    const sparseCsr<float>& in = c.g.inEdges;
    if( in.rows() < n )
    {
        return hops;
    }
    const std::uint32_t* off = in.rowOffsets();
    const std::uint32_t* col = in.colIndices();
    for( int h = 1; h <= kReachHops && !frontier.empty(); ++h )
    {
        std::vector<std::uint32_t> next;
        for( const std::uint32_t t : frontier )
        {
            for( std::uint32_t e = off[t]; e < off[t + 1]; ++e )
            {
                const std::uint32_t from = col[e];
                if( from < n && hops[from] < 0 )
                {
                    hops[from] = std::int8_t( h );
                    next.push_back( from );
                }
            }
        }
        frontier = std::move( next );
    }
    return hops;
}

// Hops from each file back to the act files over the include/import graph (who includes them), at most kReachHops.
inline std::vector<std::int8_t> includerHops( const Corpus& c, const FileAdjacency& adj, std::span<const std::uint32_t> seeds )
{
    const std::size_t          n = c.rel.size();
    std::vector<std::int8_t>   hops( n, -1 );
    if( adj.size() != n )
    {
        return hops;
    }
    std::vector<std::uint32_t> inOff( n + 1, 0 ), inSrc;
    for( std::size_t f = 0; f < n; ++f )
    {
        for( const std::uint32_t to : adj[f] )
        {
            if( to < n )
            {
                ++inOff[to + 1];
            }
        }
    }
    for( std::size_t f = 0; f < n; ++f )
    {
        inOff[f + 1] += inOff[f];
    }
    inSrc.resize( inOff[n] );
    std::vector<std::uint32_t> fill( inOff.begin(), inOff.end() - 1 );
    for( std::uint32_t f = 0; f < n; ++f )
    {
        for( const std::uint32_t to : adj[f] )
        {
            if( to < n )
            {
                inSrc[fill[to]++] = f;
            }
        }
    }
    std::vector<std::uint32_t> frontier;
    for( const std::uint32_t s : seeds )
    {
        if( s < n && hops[s] < 0 )
        {
            hops[s] = 0;
            frontier.push_back( s );
        }
    }
    for( int h = 1; h <= kReachHops && !frontier.empty(); ++h )
    {
        std::vector<std::uint32_t> next;
        for( const std::uint32_t t : frontier )
        {
            for( std::uint32_t e = inOff[t]; e < inOff[t + 1]; ++e )
            {
                if( hops[inSrc[e]] < 0 )
                {
                    hops[inSrc[e]] = std::int8_t( h );
                    next.push_back( inSrc[e] );
                }
            }
        }
        frontier = std::move( next );
    }
    return hops;
}

inline bool isEntryDir( std::string_view rel ) noexcept
{
    const std::string_view role = roleOfPath( rel );
    // a dir starting with _ or . is outside the build (Go ignores _mock/, a dot dir is tooling)
    const std::string_view dir    = dirName( rel );
    const bool             hidden = dir.starts_with( "_" ) || dir.starts_with( "." ) || dir.find( "/_" ) != std::string_view::npos || dir.find( "/." ) != std::string_view::npos;
    return role != "test" && role != "examples" && role != "bench" && role != "docs" && role != "build" && !isSkipRole( role ) && !isTestPath( rel ) && !hidden;
}

// A JS/TS program file by name: main.ts, *.main.ts, main.js …
inline bool isScriptMainFile( std::string_view rel ) noexcept
{
    const std::string_view b = baseName( rel );
    for( const std::string_view ext : { ".ts", ".js", ".mjs", ".cjs", ".tsx" } )
    {
        if( b.ends_with( ext ) )
        {
            const std::string_view stem = b.substr( 0, b.size() - ext.size() );
            return stem == "main" || stem.ends_with( ".main" );
        }
    }
    return false;
}

// package.json "main" / "bin" targets, mapped from a build-output dir to the source file when one exists (out/main.js -> src/main.ts).
inline std::vector<std::uint32_t> packageEntryFiles( const Corpus& c )
{
    std::vector<std::uint32_t>        out;
    const std::optional<std::string> t = c.exists( "package.json" ) ? c.read( "package.json" ) : std::nullopt;
    if( !t )
    {
        return out;
    }
    for( const std::string_view key : { std::string_view( "\"main\"" ), std::string_view( "\"bin\"" ) } )
    {
        const std::size_t k  = t->find( key );
        const std::size_t q1 = k == std::string::npos ? k : t->find( '"', t->find( ':', k ) );
        const std::size_t q2 = q1 == std::string::npos ? q1 : t->find( '"', q1 + 1 );
        if( q2 == std::string::npos || t->substr( k, q1 - k ).find( '{' ) != std::string::npos )
        {
            continue;
        }
        std::string_view v = std::string_view( *t ).substr( q1 + 1, q2 - q1 - 1 );
        if( v.starts_with( "./" ) )
        {
            v.remove_prefix( 2 );
        }
        std::string stem( v );
        if( const std::size_t dot = stem.rfind( '.' ); dot != std::string::npos )
        {
            stem.resize( dot );
        }
        const std::string_view tail = std::string_view( stem ).substr( stem.find( '/' ) == std::string::npos ? 0 : stem.find( '/' ) + 1 );
        for( const std::string& cand : { std::string( v ), stem + ".ts", stem + ".js", "src/" + std::string( tail ) + ".ts", "src/" + std::string( tail ) + ".js" } )
        {
            if( const std::optional<std::uint32_t> f = c.file( cand ); f && std::find( out.begin(), out.end(), *f ) == out.end() )
            {
                out.push_back( *f );
                break;
            }
        }
    }
    return out;
}

// The most-included C/C++ header outside tests/vendored code (an include/ header first), when 3+ files include it.
inline std::optional<std::uint32_t> publicHeader( const Corpus& c, const FileAdjacency& adj, std::string_view project )
{
    if( adj.size() != c.rel.size() )
    {
        return std::nullopt;
    }
    std::vector<int> inDeg( c.rel.size(), 0 );
    for( std::size_t f = 0; f < adj.size(); ++f )
    {
        for( const std::uint32_t to : adj[f] )
        {
            if( to < inDeg.size() && to != f )
            {
                ++inDeg[to];
            }
        }
    }
    std::optional<std::uint32_t> best;
    const auto score = [ & ]( std::uint32_t f )
    {
        return std::tuple<int, int, int>( !project.empty() && lower( stemOf( c.rel[f] ) ) == project ? 1 : 0, roleOfPath( c.rel[f] ) == "api" ? 1 : 0, inDeg[f] );
    };
    for( std::uint32_t f = 0; f < c.rel.size(); ++f )
    {
        const std::string_view r = c.rel[f];
        const bool header = r.ends_with( ".h" ) || r.ends_with( ".hpp" ) || r.ends_with( ".hh" );
        if( header && inDeg[f] >= 3 && isEntryDir( r ) && ( !best || score( f ) > score( *best ) ) )
        {
            best = f;
        }
    }
    return best;
}

// The public header's implementation: the one non-test C/C++ source with its stem (include/zmq.h -> src/zmq.cpp).
inline std::optional<std::uint32_t> headerImpl( const Corpus& c, std::uint32_t header )
{
    for( std::uint32_t f = 0; f < c.rel.size(); ++f )
    {
        const std::string_view r = c.rel[f];
        const bool source = r.ends_with( ".c" ) || r.ends_with( ".cc" ) || r.ends_with( ".cpp" ) || r.ends_with( ".cxx" );
        if( source && stemOf( r ) == stemOf( c.rel[header] ) && isEntryDir( r ) )
        {
            return f;
        }
    }
    return std::nullopt;
}

// Reach from the task to every candidate: hops back from the seeds over callers and over includers/importers. The seeds are the
// question-named files (or the first act file) with their act symbols; a candidate the primary walk misses takes the walk from
// every act symbol, ranked after every primary hit.
struct EntryReach
{
    std::vector<std::int8_t> primarySym, primaryFile, allSym, allFile;

    static int fileHops( const Corpus& c, const std::vector<std::int8_t>& symHops, const std::vector<std::int8_t>& fileHopsOf, std::uint32_t f )
    {
        int best = f < fileHopsOf.size() ? fileHopsOf[f] : -1;
        for( std::uint32_t s = c.firstSym[f]; s < c.firstSym[f + 1]; ++s )
        {
            if( symHops[s] >= 0 && ( best < 0 || symHops[s] < best ) )
            {
                best = symHops[s];
            }
        }
        return best;
    }
    // (rank key, shown hops): a primary hit keys on its hops, an act-only hit on 64 + hops, a miss on 255
    std::pair<int, int> of( const Corpus& c, std::uint32_t f ) const
    {
        if( const int h = fileHops( c, primarySym, primaryFile, f ); h >= 0 )
        {
            return { h, h };
        }
        if( const int h = fileHops( c, allSym, allFile, f ); h >= 0 )
        {
            return { 64 + h, h };
        }
        return { 255, -1 };
    }
};

inline EntryReach entryReach( const Corpus& c, const FileAdjacency& adj, const std::vector<std::uint32_t>& actSyms, const std::vector<std::string>& files,
                              const std::vector<std::string>& named )
{
    const std::vector<std::string> primary = named.empty() && !files.empty() ? std::vector<std::string>{ files.front() } : named;
    std::vector<std::uint32_t>     primarySyms, primaryIds, allIds;
    for( const std::uint32_t s : actSyms )
    {
        if( std::find( primary.begin(), primary.end(), c.rel[c.ing.symbols[s].fileId] ) != primary.end() )
        {
            primarySyms.push_back( s );
        }
    }
    for( const std::string& f : files )
    {
        if( const std::optional<std::uint32_t> id = c.file( f ) )
        {
            allIds.push_back( *id );
            if( std::find( primary.begin(), primary.end(), f ) != primary.end() )
            {
                primaryIds.push_back( *id );
            }
        }
    }
    return { callerHops( c, primarySyms ), includerHops( c, adj, primaryIds ), callerHops( c, actSyms ), includerHops( c, adj, allIds ) };
}

// Path words a candidate shares with the primary file, past the generic ones (cmd/kube-scheduler and pkg/scheduler share "scheduler").
inline int sharedPathWords( std::string_view cand, std::string_view primary, std::string_view project )
{
    static constexpr std::string_view kGeneric[] = { "cmd", "pkg", "src", "lib", "libs", "internal", "main", "app", "apps", "tools", "tool", "test", "tests",
                                                     "staging", "io", "cpp", "cc", "c", "h", "go", "ts", "js", "py", "rs", "common", "util", "utils", "core" };
    const auto words = [ & ]( std::string_view p )
    {
        std::vector<std::string> out( 1 );
        for( const char ch : lower( dirName( p ) ) )
        {
            if( ch == '/' || ch == '-' || ch == '_' || ch == '.' )
            {
                out.emplace_back();
            }
            else
            {
                out.back() += ch;
            }
        }
        std::erase_if( out, [ & ]( const std::string& w )
        {
            return w.size() < 3 || w == project || std::find( std::begin( kGeneric ), std::end( kGeneric ), w ) != std::end( kGeneric );
        } );
        return out;
    };
    const std::vector<std::string> a = words( cand ), b = words( primary );
    return int( std::count_if( a.begin(), a.end(), [ & ]( const std::string& w ) { return std::find( b.begin(), b.end(), w ) != b.end(); } ) );
}

// A generator tool's dir by name: gen*, *-gen, *_gen, *codegen (cmd/genkubedocs, code-generator/cmd/validation-gen).
inline bool isGeneratorDir( std::string_view dir ) noexcept
{
    const std::string b = lower( baseName( dir ) );
    return b.starts_with( "gen" ) || b.ends_with( "-gen" ) || b.ends_with( "_gen" ) || b.ends_with( "codegen" ) || dir.find( "code-generator" ) != std::string_view::npos;
}

// Every program entry: main() definitions, __main__.py, JS/TS main files and package.json main/bin (always offered: it IS the entry).
inline std::vector<Entry> entryCandidates( const Corpus& c, const EntryReach& reach, std::string_view primary, std::string_view project )
{
    std::vector<Entry>             cands;
    HashMap<std::string_view, int> dirFiles;   // every ancestor dir -> indexed files under it
    for( const std::string_view r : c.rel )
    {
        for( std::string_view d = dirName( r ); !d.empty(); d = dirName( d ) )
        {
            ++dirFiles[d];
        }
    }
    const auto add = [ & ]( std::uint32_t f, std::uint32_t line, std::string what )
    {
        const auto [ key, hops ] = reach.of( c, f );
        const auto it            = dirFiles.find( dirName( c.rel[f] ) );
        const bool topLevel      = dirName( c.rel[f] ).find( '/' ) == std::string_view::npos;   // hack/x.py: the dir is a script bin, not a program
        cands.push_back( { f, line, std::move( what ), hops, sharedPathWords( c.rel[f], primary, project ), key, it == dirFiles.end() || topLevel ? 1 : it->second } );
        // build tooling after every program: a code/doc generator's main (cmd/genman, validation-gen) or a script directly in a
        // top-level tools dir (hack/verify-flags-underscore.py, scripts/generate_schema.py)
        if( isGeneratorDir( dirName( c.rel[f] ) ) || ( topLevel && roleOfPath( c.rel[f] ) == "tools" ) )
        {
            cands.back().rankKey = 256;
        }
    };
    for( const Symbol& sym : c.ing.symbols )
    {
        const bool fn = sym.kind == SymKind::Function || ( sym.kind == SymKind::Method && sym.fileId < c.rel.size() && stemOf( c.rel[sym.fileId] ) == "main" );
        if( fn && sym.name == "main" && sym.fileId < c.rel.size() && isEntryDir( c.rel[sym.fileId] ) )
        {
            add( sym.fileId, sym.line, "main" );
        }
    }
    for( std::uint32_t f = 0; f < c.rel.size(); ++f )
    {
        const std::string_view r = c.rel[f];
        if( isEntryDir( r ) && ( baseName( r ) == "__main__.py" || isScriptMainFile( r ) ) )
        {
            add( f, 1, baseName( r ) == "__main__.py" ? "__main__" : "program" );
            if( baseName( r ) == "__main__.py" && !project.empty() && lower( baseName( dirName( r ) ) ) == project )
            {
                cands.back().rankKey = -1;   // the project package's own `python -m` entry (src/black/__main__.py)
            }
        }
    }
    for( const std::uint32_t f : packageEntryFiles( c ) )
    {
        add( f, 1, "package.json main" );
        cands.back().rankKey = -1;   // the manifest's own entry leads
    }
    std::sort( cands.begin(), cands.end(), [ & ]( const Entry& a, const Entry& b )
    {
        if( rankBand( a.rankKey ) != rankBand( b.rankKey ) )
        {
            return rankBand( a.rankKey ) < rankBand( b.rankKey );
        }
        if( a.prefix != b.prefix )
        {
            return a.prefix > b.prefix;
        }
        // a top-level program before a nested one (cmd/kubelet before staging/src/.../main.go), then the bigger program
        const auto depth = [ & ]( const Entry& e ) { return std::count( c.rel[e.fileId].begin(), c.rel[e.fileId].end(), '/' ); };
        if( depth( a ) != depth( b ) )
        {
            return depth( a ) < depth( b );
        }
        if( a.size != b.size )
        {
            return a.size > b.size;
        }
        return a.rankKey != b.rankKey ? a.rankKey < b.rankKey : c.rel[a.fileId] < c.rel[b.fileId];
    } );
    return cands;
}

inline std::vector<Entry> findEntries( const Corpus& c, const FileAdjacency& adj, const std::vector<std::uint32_t>& actSyms, const std::vector<std::string>& files,
                                       const std::vector<std::string>& named, int cap, std::string_view project )
{
    const EntryReach                   reach   = entryReach( c, adj, actSyms, files, named );
    const std::string_view             primary = named.empty() ? ( files.empty() ? std::string_view() : std::string_view( files.front() ) ) : std::string_view( named.front() );
    const std::vector<Entry>           cands   = entryCandidates( c, reach, primary, project );
    // a monorepo of 10K+ files has no one public header (llvm-project's LLVM.h is a forwarding header): large repos list programs
    const std::optional<std::uint32_t> header  = c.rel.size() < std::size_t( kClassCaps[1].maxFiles ) ? publicHeader( c, adj, project ) : std::nullopt;
    const std::optional<std::uint32_t> impl    = header ? headerImpl( c, *header ) : std::nullopt;
    const int                          mainCap = cap - ( header ? 1 : 0 ) - ( impl ? 1 : 0 );
    std::vector<Entry>                 out;
    std::vector<std::string>           taken;   // one entry of each kind per dir: a tool dir holds one program, a package its main and its __main__
    for( const Entry& e : cands )
    {
        if( int( out.size() ) >= mainCap )
        {
            break;
        }
        std::string key = std::string( dirName( c.rel[e.fileId] ) ) + "|" + e.what;
        if( std::find( taken.begin(), taken.end(), key ) == taken.end() )
        {
            taken.push_back( std::move( key ) );
            out.push_back( e );
        }
    }
    for( const auto& [ file, what ] : { std::pair{ header, "public header" }, std::pair{ impl, "api impl" } } )
    {
        if( file )
        {
            out.push_back( { *file, 1, what, reach.of( c, *file ).second, 0, 0, 0 } );
        }
    }
    return out;
}

inline std::string renderEntries( const Corpus& c, const std::vector<Entry>& entries, int cap )
{
    std::string out = "<entry>";
    for( int i = 0; i < int( entries.size() ) && i < cap; ++i )
    {
        const Entry& e = entries[std::size_t( i )];
        out += ( i > 0 ? " · " : "" ) + xml( c.rel[e.fileId] ) + ":" + std::to_string( e.line ) + " " + e.what
               + ( e.hops >= 0 ? " hops=" + std::to_string( e.hops ) : std::string() );
    }
    if( entries.empty() )
    {
        out += "none found";
    }
    return out + "</entry>";
}

// ── section 4: task ─────────────────────────────────────────────────────────────────────────────────────────────────────────
// The θ11 question sites, collected once and formatted at any byte budget (the size fit cuts them line by line, never mid-line).
struct QuestionSites
{
    std::vector<qsites::Token>      toks;
    std::vector<qsites::TokenSites> sites;   // each points into toks

    QuestionSites( const Corpus& c, std::string_view task ) : toks( qsites::questionTokens( task ) )
    {
        if( !toks.empty() )
        {
            sites = qsites::collectSites( c.ing, toks, sarif::rootPrefixOf( c.diskRoot ) );
        }
    }
    QuestionSites( const QuestionSites& ) = delete;
    QuestionSites& operator=( const QuestionSites& ) = delete;
    std::string text( std::size_t budget ) const;
};

inline std::string QuestionSites::text( std::size_t budget ) const
{
    if( sites.empty() || budget == 0 )
    {
        return {};
    }
    std::string lines = qsites::formatLines( sites, budget );
    while( !lines.empty() && lines.back() == '\n' )
    {
        lines.pop_back();
    }
    std::string out;
    for( const char ch : lines )
    {
        if( ch != '\n' )
        {
            out += ch;
        }
    }
    return out;
}

inline std::string renderTask( const ForCore& core, std::string_view qs )
{
    std::string out = "<task confidence=\"" + xml( core.confidence ) + "\" act_shipped=\"" + std::to_string( core.shippedAct ) + "\"><act read=\"";
    for( std::size_t i = 0; i < core.act.size(); ++i )
    {
        const Range& a = core.act[i];
        out += ( i > 0 ? "," : "" ) + xml( a.path ) + ":" + std::to_string( a.lo ) + "-" + std::to_string( a.hi );
    }
    out += "\"/>";
    out += qs;
    return out + "</task>";
}

// ── section 5: edges ────────────────────────────────────────────────────────────────────────────────────────────────────────
struct EdgeSet
{
    std::string              symbol;
    std::vector<std::string> callers;
    std::vector<std::string> callees;
};

// A file's definitions ranked by how many symbols in OTHER files point at them (ties: the earlier line), at most `cap` with a user.
inline std::vector<std::uint32_t> mostUsedSymbols( const Corpus& c, std::string_view rel, std::size_t cap )
{
    std::vector<std::pair<int, std::uint32_t>> used;
    const std::optional<std::uint32_t>         id = c.file( rel );
    const sparseCsr<float>&                    in = c.g.inEdges;
    for( std::uint32_t s = id ? c.firstSym[*id] : 0; id && in.rows() >= c.ing.symbols.size() && s < c.firstSym[*id + 1]; ++s )
    {
        int users = 0;
        for( std::uint32_t e = in.rowOffsets()[s]; e < in.rowOffsets()[s + 1]; ++e )
        {
            const std::uint32_t from = in.colIndices()[e];
            users += from < c.ing.symbols.size() && c.ing.symbols[from].fileId != *id ? 1 : 0;
        }
        if( users > 0 )
        {
            used.emplace_back( -users, s );
        }
    }
    std::sort( used.begin(), used.end() );
    std::vector<std::uint32_t> out;
    for( std::size_t i = 0; i < used.size() && i < cap; ++i )
    {
        out.push_back( used[i].second );
    }
    return out;
}

inline std::vector<std::uint32_t> actSymbols( const Corpus& c, const ForCore& core, const std::vector<std::string>& named )
{
    std::vector<std::uint32_t> syms;
    for( const std::string& f : named )   // a named file gives the definitions other files use most (node_affinity.go -> New, its registration)
    {
        for( const std::uint32_t s : mostUsedSymbols( c, f, 2 ) )
        {
            syms.push_back( s );
        }
    }
    for( const Range& a : core.act )
    {
        const std::optional<std::uint32_t> f = c.file( a.path );
        const std::optional<std::uint32_t> s = f ? c.symbolAt( *f, a.lo ) : std::nullopt;
        if( s && std::find( syms.begin(), syms.end(), *s ) == syms.end() )
        {
            syms.push_back( *s );
        }
    }
    std::stable_partition( syms.begin(), syms.end(), [ & ]( std::uint32_t s )
    {
        return std::find( named.begin(), named.end(), c.rel[c.ing.symbols[s].fileId] ) != named.end();
    } );
    return syms;
}

inline std::vector<EdgeSet> findEdges( const Corpus& c, const std::vector<std::uint32_t>& syms )
{
    std::vector<EdgeSet>    out;
    const sparseCsr<float>& in = c.g.inEdges;
    const std::size_t       n  = c.ing.symbols.size();
    for( std::size_t i = 0; i < syms.size() && int( out.size() ) < kEdgeSymbols; ++i )
    {
        const std::uint32_t s   = syms[i];
        const Symbol&       sym = c.ing.symbols[s];
        EdgeSet             set{ c.shortName( s ), {}, {} };
        std::vector<std::uint32_t> callers, callees;
        if( in.rows() >= n )
        {
            for( std::uint32_t e = in.rowOffsets()[s]; e < in.rowOffsets()[s + 1]; ++e )
            {
                if( in.colIndices()[e] != s && in.colIndices()[e] < n )
                {
                    callers.push_back( in.colIndices()[e] );
                }
            }
        }
        if( c.g.outOff.size() > s + 1 )
        {
            for( std::uint32_t e = c.g.outOff[s]; e < c.g.outOff[s + 1]; ++e )
            {
                const NodeId t = c.g.outTargets[e];
                if( t < n && c.ing.symbols[t].fileId != sym.fileId )
                {
                    callees.push_back( t );
                }
            }
        }
        const auto byPlace = [ & ]( std::uint32_t a, std::uint32_t b )
        {
            const Symbol& x = c.ing.symbols[a];
            const Symbol& y = c.ing.symbols[b];
            return c.rel[x.fileId] != c.rel[y.fileId] ? c.rel[x.fileId] < c.rel[y.fileId] : x.line < y.line;
        };
        std::sort( callers.begin(), callers.end(), byPlace );
        std::sort( callees.begin(), callees.end(), byPlace );
        for( std::size_t k = 0; k < callers.size() && int( k ) < kEdgesPerSide; ++k )
        {
            const Symbol& x = c.ing.symbols[callers[k]];
            set.callers.push_back( std::string( c.rel[x.fileId] ) + ":" + std::to_string( x.line ) + " " + c.shortName( callers[k] ) );
        }
        if( const std::size_t more = callers.size() > std::size_t( kEdgesPerSide ) ? callers.size() - kEdgesPerSide : 0; more > 0 )
        {
            set.callers.push_back( "+" + std::to_string( more ) );
        }
        for( std::size_t k = 0; k < callees.size() && int( k ) < kEdgesPerSide; ++k )
        {
            const Symbol& x = c.ing.symbols[callees[k]];
            set.callees.push_back( std::string( c.rel[x.fileId] ) + ":" + std::to_string( x.line ) + "-" + std::to_string( x.line + std::max<std::uint32_t>( x.loc, 1 ) - 1 ) + " "
                                   + c.shortName( callees[k] ) );
        }
        if( const std::size_t more = callees.size() > std::size_t( kEdgesPerSide ) ? callees.size() - kEdgesPerSide : 0; more > 0 )
        {
            set.callees.push_back( "+" + std::to_string( more ) );
        }
        if( !set.callers.empty() || !set.callees.empty() )
        {
            out.push_back( std::move( set ) );
        }
    }
    return out;
}

// A Go file's in-repo import dirs: an import path under go.mod's module maps to its dir, a staged module to staging/src/<path>
// (Kubernetes' layout); an external package is not listed. Nearest dir first, at most `shown`.
inline std::string goModule( const Corpus& c )
{
    std::string                      module;
    const std::optional<std::string> mod = c.exists( "go.mod" ) ? c.read( "go.mod" ) : std::nullopt;
    if( mod )
    {
        forEachLine( *mod, [ & ]( std::string_view line, int )
        {
            if( line.starts_with( "module " ) )
            {
                module = std::string( trim( line.substr( 7 ) ) );
                return false;
            }
            return true;
        } );
    }
    return module;
}

inline std::vector<std::string> goImportDirs( const Corpus& c, std::string_view rel, std::size_t shown )
{
    std::vector<std::string>         dirs;
    const std::optional<std::string> text   = c.read( rel );
    const std::string                module = goModule( c );
    if( !text )
    {
        return dirs;
    }
    bool inBlock = false;
    forEachLine( *text, [ & ]( std::string_view line, int )
    {
        const std::string_view t = trim( line );
        inBlock = t.starts_with( "import (" ) ? true : t.starts_with( ")" ) ? false : inBlock;
        const std::size_t q1 = ( inBlock || t.starts_with( "import \"" ) ) ? t.find( '"' ) : std::string_view::npos;
        const std::size_t q2 = q1 == std::string_view::npos ? q1 : t.find( '"', q1 + 1 );
        if( t.starts_with( "func " ) || t.starts_with( "type " ) )
        {
            return false;   // past the import block
        }
        if( q2 == std::string_view::npos )
        {
            return true;
        }
        const std::string_view path = t.substr( q1 + 1, q2 - q1 - 1 );
        std::string            dir;
        if( !module.empty() && path.starts_with( module + "/" ) )
        {
            dir = std::string( path.substr( module.size() + 1 ) );
        }
        else if( isDir( joinPath( c.diskRoot, "staging/src/" + std::string( path ) ) ) )
        {
            dir = "staging/src/" + std::string( path );
        }
        if( !dir.empty() && isDir( joinPath( c.diskRoot, dir ) ) && std::find( dirs.begin(), dirs.end(), dir + "/" ) == dirs.end() )
        {
            dirs.push_back( dir + "/" );
        }
        return true;
    } );
    std::stable_sort( dirs.begin(), dirs.end(), [ & ]( const std::string& a, const std::string& b )
    {
        return commonPrefixDirs( a + "x", rel ) > commonPrefixDirs( b + "x", rel );
    } );
    if( dirs.size() > shown )
    {
        const std::size_t more = dirs.size() - shown;
        dirs.resize( shown );
        dirs.push_back( "+" + std::to_string( more ) );
    }
    return dirs;
}

// Non-test files that import the primary file, nearest first, at most kUsersShown: where a model file is registered or loaded
// (node_affinity.go -> plugins/registry.go; bracketMatching.ts -> editor.all.ts). Go imports a package: a file in the repo under
// the primary's top two dirs whose import block quotes the package path; elsewhere the include/import graph's reverse edges.
inline std::vector<std::string> primaryUsers( const Corpus& c, const FileAdjacency& adj, std::string_view primary )
{
    std::vector<std::string_view> users;
    const std::optional<std::uint32_t> id  = c.file( primary );
    const std::string_view             dir = dirName( primary );
    if( primary.ends_with( ".go" ) )
    {
        const std::string module = goModule( c );
        const std::size_t cut    = dir.find( '/', dir.find( '/' ) == std::string_view::npos ? dir.size() : dir.find( '/' ) + 1 );
        const std::string scope  = std::string( dir.substr( 0, cut == std::string_view::npos ? dir.size() : cut ) ) + "/";
        const std::string quoted = "\"" + module + "/" + std::string( dir ) + "\"";
        for( const std::string_view r : c.rel )
        {
            if( module.empty() || !r.starts_with( scope ) || !r.ends_with( ".go" ) || r.ends_with( "_test.go" ) || dirName( r ) == dir || isTestPath( r ) )
            {
                continue;
            }
            const std::optional<std::string> head = c.read( r, 4096 );
            if( head && head->find( quoted ) != std::string::npos )
            {
                users.push_back( r );
            }
        }
    }
    else if( id && adj.size() == c.rel.size() )
    {
        for( std::uint32_t f = 0; f < adj.size(); ++f )
        {
            if( f != *id && !isTestPath( c.rel[f] ) && !isSkipRole( roleOfPath( c.rel[f] ) )
                && std::find( adj[f].begin(), adj[f].end(), *id ) != adj[f].end() )
            {
                users.push_back( c.rel[f] );
            }
        }
    }
    std::stable_sort( users.begin(), users.end(), [ & ]( std::string_view a, std::string_view b )
    {
        const int pa = commonPrefixDirs( a, primary ), pb = commonPrefixDirs( b, primary );
        return pa != pb ? pa > pb : a < b;
    } );
    std::vector<std::string> out;
    for( std::size_t i = 0; i < users.size() && i < kUsersShown; ++i )
    {
        out.emplace_back( users[i] );
    }
    if( const std::size_t more = users.size() > kUsersShown ? users.size() - kUsersShown : 0; more > 0 )
    {
        out.push_back( "+" + std::to_string( more ) );
    }
    return out;
}

// The primary file's in-repo imports/includes, nearest first (most shared dirs), at most 6: the framework a model file is built
// on (bracketMatching.ts -> editorExtensions.ts, editorCommon.ts; node_affinity.go -> plugins/names, framework).
inline EdgeSet primaryImports( const Corpus& c, const FileAdjacency& adj, const std::vector<std::string>& named, const std::vector<std::string>& files, std::size_t shown )
{
    const std::string_view             primary = named.empty() ? ( files.empty() ? std::string_view() : std::string_view( files.front() ) ) : std::string_view( named.front() );
    const std::optional<std::uint32_t> id      = c.file( primary );
    EdgeSet                            set{ std::string( primary ), {}, {} };
    if( !id || adj.size() != c.rel.size() )
    {
        return set;
    }
    set.callers = primaryUsers( c, adj, primary );
    if( primary.ends_with( ".go" ) )   // Go imports name packages, not files: the in-repo package dirs, quoted from the import block
    {
        set.callees = goImportDirs( c, primary, shown );
        return set;
    }
    std::vector<int> inDeg( c.rel.size(), 0 );
    for( std::size_t f = 0; f < adj.size(); ++f )
    {
        for( const std::uint32_t to : adj[f] )
        {
            if( to < inDeg.size() )
            {
                ++inDeg[to];
            }
        }
    }
    std::vector<std::uint32_t> imports;
    for( const std::uint32_t to : adj[*id] )
    {
        if( to != *id && to < c.rel.size() && !isSkipRole( roleOfPath( c.rel[to] ) ) )
        {
            imports.push_back( to );
        }
    }
    // nearest first, then the most-imported (the subsystem's interface file before a leaf helper beside it)
    std::sort( imports.begin(), imports.end(), [ & ]( std::uint32_t a, std::uint32_t b )
    {
        const int pa = commonPrefixDirs( c.rel[a], primary ), pb = commonPrefixDirs( c.rel[b], primary );
        return pa != pb ? pa > pb : inDeg[a] != inDeg[b] ? inDeg[a] > inDeg[b] : c.rel[a] < c.rel[b];
    } );
    for( std::size_t i = 0; i < imports.size() && i < shown; ++i )
    {
        set.callees.emplace_back( c.rel[imports[i]] );
    }
    if( imports.size() > shown )
    {
        set.callees.push_back( "+" + std::to_string( imports.size() - shown ) );
    }
    return set;
}

inline std::string renderEdges( const std::vector<EdgeSet>& sets, int cap, const EdgeSet& imports )
{
    std::string out = "<edges>";
    if( !imports.callees.empty() || !imports.callers.empty() )
    {
        out += "<i f=\"" + xml( imports.symbol ) + "\">";
        for( std::size_t k = 0; k < imports.callees.size(); ++k )
        {
            out += ( k > 0 ? ", " : "" ) + xml( imports.callees[k] );
        }
        for( std::size_t k = 0; k < imports.callers.size(); ++k )
        {
            out += ( k > 0 ? ", " : imports.callees.empty() ? "used by: " : " | used by: " ) + xml( imports.callers[k] );
        }
        out += "</i>";
    }
    for( int i = 0; i < int( sets.size() ) && i < cap; ++i )
    {
        const EdgeSet& s = sets[std::size_t( i )];
        out += "<e s=\"" + xml( s.symbol ) + "\">";
        const auto list = [ & ]( const char* label, const std::vector<std::string>& xs )
        {
            if( xs.empty() )
            {
                return;
            }
            out += label;
            for( std::size_t k = 0; k < xs.size(); ++k )
            {
                out += ( k > 0 ? ", " : "" ) + xml( xs[k] );
            }
        };
        list( "callers: ", s.callers );
        if( !s.callers.empty() && !s.callees.empty() )
        {
            out += " | ";
        }
        list( "calls: ", s.callees );
        out += "</e>";
    }
    if( sets.empty() && imports.callees.empty() && imports.callers.empty() )
    {
        out += "none found";
    }
    return out + "</edges>";
}

// ── section 6: where-else ───────────────────────────────────────────────────────────────────────────────────────────────────
struct WhereElse
{
    std::vector<std::string> items;   // "kind path"
    bool                     hasHistory = false;
    int                      more       = 0;   // distinct items past kWhereElseCap: shown as +N
};

inline void addItem( WhereElse& w, std::string_view kind, std::string_view path, const std::vector<std::string>& files )
{
    if( path.empty() || std::find( files.begin(), files.end(), path ) != files.end() )
    {
        return;
    }
    const std::string item = std::string( kind ) + " " + std::string( path );
    const bool        dup  = std::any_of( w.items.begin(), w.items.end(), [ & ]( const std::string& x ) { return x.ends_with( " " + std::string( path ) ); } );
    if( dup )
    {
        return;
    }
    if( int( w.items.size() ) >= kWhereElseCap )
    {
        ++w.more;
        return;
    }
    w.items.push_back( item );
}

// Doc files that name one of `names` as a whole word, those whose path names a stem first.
inline std::vector<std::string> namingDocs( const Corpus& c, const std::vector<std::string>& names, const std::vector<std::string>& stems, int cap )
{
    std::vector<std::string_view> docs;
    for( const std::string_view r : c.rel )
    {
        if( isDocPath( r ) && baseName( r ) != "CHANGELOG.md" && baseName( r ) != "README.md" )
        {
            docs.push_back( r );
        }
    }
    std::stable_sort( docs.begin(), docs.end(), [ & ]( std::string_view a, std::string_view b ) { return pathNamesStem( a, stems ) && !pathNamesStem( b, stems ); } );
    std::vector<std::string> out;
    for( std::size_t i = 0; i < docs.size() && int( i ) < kDocScanFiles && int( out.size() ) < cap; ++i )
    {
        const std::optional<std::string> text = c.read( docs[i], kDocScanBytes );
        if( !text )
        {
            continue;
        }
        const bool named = std::any_of( names.begin(), names.end(), [ & ]( const std::string& n )
        {
            for( std::size_t at = text->find( n ); at != std::string::npos; at = text->find( n, at + 1 ) )
            {
                const auto word = []( char ch ) { return ( ch >= 'a' && ch <= 'z' ) || ( ch >= 'A' && ch <= 'Z' ) || ( ch >= '0' && ch <= '9' ) || ch == '_'; };
                const bool before = at == 0 || !word( ( *text )[at - 1] );
                const bool after  = at + n.size() >= text->size() || !word( ( *text )[at + n.size()] );
                if( before && after )
                {
                    return true;
                }
            }
            return false;
        } );
        if( named )
        {
            out.emplace_back( docs[i] );
        }
    }
    return out;
}

inline std::string changelogOf( const Corpus& c )
{
    for( const std::string_view dir : { "changelog.d/", "changelog/unreleased/", "changelog/", "changes/", ".changes/" } )
    {
        const bool any = std::any_of( c.rel.begin(), c.rel.end(), [ & ]( std::string_view r ) { return r.starts_with( dir ); } ) || isDir( joinPath( c.diskRoot, dir ) );
        if( any )
        {
            return std::string( dir );
        }
    }
    for( const std::string_view f : { "CHANGELOG.md", "CHANGES.md", "NEWS.md", "NEWS", "CHANGELOG", "ChangeLog", "HISTORY.md", "CHANGES.rst", "CHANGELOG.rst" } )
    {
        if( c.exists( f ) )
        {
            return std::string( f );
        }
    }
    return {};
}

// A name a doc mention can be trusted on: snake_case, camelCase or a digit in it, or 8+ bytes (`start` is prose; `zmq_ctx_set` is not).
inline bool isDistinctiveName( std::string_view n ) noexcept
{
    if( n.size() < 4 )
    {
        return false;
    }
    bool lowerSeen = false;
    for( const char ch : n )
    {
        if( ch == '_' || ( ch >= '0' && ch <= '9' ) || ( lowerSeen && ch >= 'A' && ch <= 'Z' ) )
        {
            return true;
        }
        lowerSeen = lowerSeen || ( ch >= 'a' && ch <= 'z' );
    }
    return n.size() >= 8;
}

inline WhereElse findWhereElse( const Corpus& c, const ForCore& core, const std::vector<std::string>& files, const TestHome& home, bool history )
{
    WhereElse w;
    w.hasHistory = history;
    if( history && !files.empty() )
    {
        const std::vector<std::vector<std::uint32_t>> sets = gitCommitFileSets( c.diskRoot, c.ing, "18 months ago", 30 );
        std::uint32_t                                 commits = 0;
        const std::vector<CoPartner>                  partners = cochangePartners( c.ing, files.front(), commits, sets );
        for( std::size_t i = 0; i < partners.size() && i < 2; ++i )
        {
            addItem( w, "co", c.rel[partners[i].fileId], files );
        }
    }
    for( const std::string& t : home.testFiles )
    {
        addItem( w, "test", t, files );
    }
    if( !home.testDir.empty() )
    {
        addItem( w, "test", home.testDir, files );
    }
    std::vector<std::string> names;
    for( std::size_t i = 0; i < core.act.size() && names.size() < 5; ++i )
    {
        std::string_view n = core.act[i].name;
        if( const std::size_t cut = n.rfind( "::" ); cut != std::string_view::npos )
        {
            n = n.substr( cut + 2 );
        }
        if( isDistinctiveName( n ) && std::find( names.begin(), names.end(), n ) == names.end() )
        {
            names.emplace_back( n );
        }
    }
    for( const std::string& d : namingDocs( c, names, taskStems( core, files ), 2 ) )
    {
        addItem( w, "doc", d, files );
    }
    addItem( w, "log", changelogOf( c ), files );
    addItem( w, "reg", home.registrar, files );
    return w;
}

inline std::string renderWhereElse( const WhereElse& w, int cap )
{
    std::string out = "<where-else history=\"" + std::string( w.hasHistory ? "1" : "0" ) + "\">";
    for( int i = 0; i < int( w.items.size() ) && i < cap; ++i )
    {
        out += ( i > 0 ? " · " : "" ) + xml( w.items[std::size_t( i )] );
    }
    const int more = w.more + std::max( 0, int( w.items.size() ) - cap );
    if( more > 0 )
    {
        out += " · +" + std::to_string( more );
    }
    if( w.items.empty() )
    {
        out += "none found";
    }
    return out + "</where-else>";
}

// ── section 7: conventions ──────────────────────────────────────────────────────────────────────────────────────────────────
inline constexpr std::string_view kConventionDocs[] = { "CLAUDE.md", "AGENTS.md", "CONTRIBUTING.md", ".github/copilot-instructions.md", "CONVENTIONS.md",
                                                        "docs/CONTRIBUTING.md", ".github/CONTRIBUTING.md" };

struct ConventionDoc
{
    std::string                                    path;
    std::vector<std::pair<std::string, int>>       headings;   // H2 text (≤ 28 B), its line
    int                                            more = 0;   // H2 headings past kHeadingsPerDoc: shown as +N
};

inline std::vector<ConventionDoc> findConventions( const Corpus& c )
{
    std::vector<ConventionDoc> out;
    for( const std::string_view doc : kConventionDocs )
    {
        const std::optional<std::string> text = c.read( doc );
        if( !text )
        {
            continue;
        }
        ConventionDoc d{ std::string( doc ), {}, 0 };
        bool          inFence = false;
        forEachLine( *text, [ & ]( std::string_view line, int lineNo )
        {
            if( trim( line ).starts_with( "```" ) )
            {
                inFence = !inFence;
            }
            else if( !inFence && line.starts_with( "## " ) && int( d.headings.size() ) >= kHeadingsPerDoc )
            {
                ++d.more;
            }
            else if( !inFence && line.starts_with( "## " ) )
            {
                std::string h( trim( line.substr( 3 ) ) );
                if( h.size() > 28 )
                {
                    h.resize( 28 );
                    while( !h.empty() && ( static_cast<unsigned char>( h.back() ) & 0xC0 ) == 0x80 )
                    {
                        h.pop_back();
                    }
                    if( !h.empty() && static_cast<unsigned char>( h.back() ) >= 0xC0 )
                    {
                        h.pop_back();
                    }
                }
                d.headings.emplace_back( std::move( h ), lineNo );
            }
            return true;
        } );
        out.push_back( std::move( d ) );
    }
    return out;
}

inline std::string renderConventions( const std::vector<ConventionDoc>& docs, bool headings )
{
    std::string out = "<conventions>";
    for( std::size_t i = 0; i < docs.size(); ++i )
    {
        std::string one = ( i > 0 ? " | " : "" ) + xml( docs[i].path );
        for( std::size_t k = 0; headings && k < docs[i].headings.size(); ++k )
        {
            one += ( k == 0 ? ": " : " · " ) + xml( docs[i].headings[k].first ) + "@" + std::to_string( docs[i].headings[k].second );
        }
        if( headings && docs[i].more > 0 )
        {
            one += " · +" + std::to_string( docs[i].more );
        }
        if( out.size() + one.size() > kConventionBytes && headings )
        {
            // past the section's byte cap a doc is named with its heading count: the doc is still listed, its headings are not
            const std::size_t more = docs[i].headings.size() + std::size_t( docs[i].more );
            one = ( i > 0 ? " | " : "" ) + xml( docs[i].path ) + ( more > 0 ? ": +" + std::to_string( more ) : std::string() );
        }
        out += one;
    }
    if( docs.empty() )
    {
        out += "none found";
    }
    return out + "</conventions>";
}

// ── the drop ladder ─────────────────────────────────────────────────────────────────────────────────────────────────────────
enum class Drop : std::uint8_t { ConventionHeadings, LayoutDepth, EntriesPast3, EdgesPast1, WhereElsePast3, QuestionSites };
inline constexpr std::array<std::pair<Drop, std::string_view>, 6> kDropOrder = { {
    { Drop::ConventionHeadings, "conventions" }, { Drop::LayoutDepth, "layout_depth" }, { Drop::EntriesPast3, "entry" },
    { Drop::EdgesPast1, "edges" }, { Drop::WhereElsePast3, "where_else" }, { Drop::QuestionSites, "qs" },
} };

struct Sections
{
    std::string layoutDeep, layoutTop, build, entryAll, entry3, task, taskNoQs, edgesAll, edges1, whereAll, where3, convFull, convPaths, next;
};

inline std::size_t bodyBytes( const Sections& s, std::span<const bool> dropped )
{
    const auto on = [ & ]( Drop d ) { return dropped[std::size_t( d )]; };
    return ( on( Drop::LayoutDepth ) ? s.layoutTop : s.layoutDeep ).size() + s.build.size() + ( on( Drop::EntriesPast3 ) ? s.entry3 : s.entryAll ).size()
           + ( on( Drop::QuestionSites ) ? s.taskNoQs : s.task ).size() + ( on( Drop::EdgesPast1 ) ? s.edges1 : s.edgesAll ).size()
           + ( on( Drop::WhereElsePast3 ) ? s.where3 : s.whereAll ).size() + ( on( Drop::ConventionHeadings ) ? s.convPaths : s.convFull ).size() + s.next.size();
}

inline std::string body( const Sections& s, std::span<const bool> dropped )
{
    const auto on = [ & ]( Drop d ) { return dropped[std::size_t( d )]; };
    return ( on( Drop::LayoutDepth ) ? s.layoutTop : s.layoutDeep ) + s.build + ( on( Drop::EntriesPast3 ) ? s.entry3 : s.entryAll )
           + ( on( Drop::QuestionSites ) ? s.taskNoQs : s.task ) + ( on( Drop::EdgesPast1 ) ? s.edges1 : s.edgesAll )
           + ( on( Drop::WhereElsePast3 ) ? s.where3 : s.whereAll ) + ( on( Drop::ConventionHeadings ) ? s.convPaths : s.convFull ) + s.next;
}

inline std::string langsOf( const Corpus& c )
{
    std::array<int, 64> perLang{};
    std::vector<std::uint8_t> seen( c.rel.size(), 0 );
    for( const Symbol& s : c.ing.symbols )
    {
        const std::size_t l = std::size_t( s.lang );
        if( s.fileId < seen.size() && !seen[s.fileId] && l < perLang.size() && s.lang != Lang::Unknown )
        {
            seen[s.fileId] = 1;
            ++perLang[l];
        }
    }
    std::vector<std::pair<int, std::size_t>> order;
    for( std::size_t l = 0; l < perLang.size(); ++l )
    {
        if( perLang[l] > 0 )
        {
            order.emplace_back( -perLang[l], l );
        }
    }
    std::sort( order.begin(), order.end() );
    std::string out;
    for( std::size_t i = 0; i < order.size() && i < 3; ++i )
    {
        out += ( i > 0 ? "," : "" ) + std::string( langTag( Lang( order[i].second ) ) );
    }
    return out;
}

}   // namespace detail

inline constexpr std::string_view kLegend = "<!-- brief: paths root-relative; path:l-e = lines; (skip) = do not read; Read act ranges in one turn -->";
static_assert( kLegend.size() <= 120, "SPEC §2: one legend comment of at most 120 B for the whole brief" );

// The brief for `in.task`, from the finished --for page and the built graph. Named steps 1-8, then the size fit.
inline std::string composeBrief( const BriefInputs& in )
{
    using namespace detail;
    const Corpus     c( in.ing, in.g, in.diskRoot );
    const ClassCaps& caps   = capsFor( c.rel.size() );
    const std::size_t budget = in.budgetBytes > 0 ? std::clamp( in.budgetBytes, kMinBudgetBytes, kHardCapBytes ) : caps.budgetBytes;
    const ForCore    core   = readForPage( in.forPage );
    const std::vector<std::string>   named   = namedFiles( c, in.task, actFiles( core ) );
    const std::vector<std::string>   files   = orderedFiles( named, actFiles( core ) );
    const std::vector<std::uint32_t> actSyms = actSymbols( c, core, named );
    const bool       history = !gitstamp::isShallow( std::string( in.diskRoot ) ) && hasEnclosingGitRepo( std::string( in.diskRoot ) );

    // 1 layout
    const std::vector<LayoutEntry> deep = layoutEntries( c, true );
    const std::vector<LayoutEntry> top  = layoutEntries( c, false );
    // 2 build (docs quotes first, then the manifests), 4 lines; the test home's registration and runner
    std::vector<std::string> buildSources;
    std::vector<std::string> buildLines = quotedDocCommands( c, 2, buildSources );
    std::vector<std::string> manifestLines;
    addManifestCommands( c, files, manifestLines, buildSources );
    int buildMore = 0;
    for( std::string& l : manifestLines )
    {
        if( int( buildLines.size() ) < kBuildLines )
        {
            buildLines.push_back( std::move( l ) );
        }
        else
        {
            ++buildMore;
        }
    }
    // the include/import graph feeds the test home's helper, 3's reach and 5's imports line
    const FileAdjacency adj     = resolveIncludeAdj( in.ing );
    const std::string   project = projectName( c );
    const TestHome      home    = findTestHome( c, adj, core, files, project );
    // 3 entry
    const std::vector<Entry> entries = findEntries( c, adj, actSyms, files, named, caps.entries, project );
    // 4 task
    const QuestionSites qs( c, in.task );
    // 5 edges
    const std::vector<EdgeSet> edges   = findEdges( c, actSyms );
    const EdgeSet              imports = primaryImports( c, adj, named, files, caps.imports );
    // 6 where-else
    const WhereElse where = findWhereElse( c, core, files, home, history );
    // 7 conventions
    const std::vector<ConventionDoc> conv = findConventions( c );
    // 8 next
    Sections s{ renderLayout( deep, caps.layoutEntries ), renderLayout( top, caps.layoutEntries ), renderBuild( buildLines, buildMore, home ),
                      renderEntries( c, entries, caps.entries ), renderEntries( c, entries, 3 ), renderTask( core, qs.text( kQsBytes ) ), renderTask( core, "" ),
                      renderEdges( edges, kEdgeSymbols, imports ), renderEdges( edges, 1, imports ), renderWhereElse( where, kWhereElseCap ), renderWhereElse( where, kWhereElseKept ),
                      renderConventions( conv, true ), renderConventions( conv, false ), "<next><![CDATA[" + std::string( kSubagentBriefBlock ) + "]]></next>" };

    // the root, then the fit: drop in kDropOrder until the whole answer is within budget
    std::string task( in.task.substr( 0, std::min( in.task.size(), kTaskEchoBytes ) ) );
    while( !task.empty() && ( static_cast<unsigned char>( task.back() ) & 0xC0 ) == 0x80 )
    {
        task.pop_back();
    }
    if( task.size() < in.task.size() && !task.empty() && static_cast<unsigned char>( task.back() ) >= 0xC0 )
    {
        task.pop_back();
    }
    const bool taskCut = task.size() < in.task.size();   // the echo is cut: task_cut="1"
    const std::string buildSource = buildLines.empty() ? "none" : std::any_of( buildSources.begin(), buildSources.end(), []( const std::string& p ) { return p.ends_with( ".md" ); } )
                                                                  ? "docs+manifest" : "manifest";
    const auto root = [ & ]( std::size_t bytes, const std::string& dropped, bool over )
    {
        return "<brief task=\"" + xml( task ) + "\"" + ( taskCut ? " task_cut=\"1\"" : "" ) + " root=\".\" at=\"" + xml( core.at ) + "\" files=\""
               + std::to_string( c.rel.size() ) + "\" langs=\"" + langsOf( c ) + "\" size_class=\"" + caps.name + "\" bytes=\"" + std::to_string( bytes ) + "\" budget=\""
               + std::to_string( budget ) + "\" confidence=\"" + xml( core.confidence ) + "\" build_source=\"" + buildSource + "\" history=\"" + ( history ? "1" : "0" ) + "\""
               + ( dropped.empty() ? "" : " dropped=\"" + dropped + "\"" ) + ( over ? " over=\"1\"" : "" ) + ">";
    };
    std::array<bool, kDropOrder.size()> dropped{};
    std::string                         droppedNames;
    const auto total = [ & ]( std::size_t guess ) { return root( guess, droppedNames, false ).size() + kLegend.size() + bodyBytes( s, dropped ) + 8; };
    for( const auto& [ drop, name ] : kDropOrder )
    {
        if( total( budget ) <= budget )
        {
            break;
        }
        dropped[std::size_t( drop )] = true;
        droppedNames += ( droppedNames.empty() ? "" : "," ) + std::string( name );
    }
    if( dropped[std::size_t( Drop::QuestionSites )] )   // the last step cuts the sites to the room left, line by line, instead of all of them
    {
        const std::size_t rest = total( budget );
        if( rest < budget )
        {
            s.taskNoQs = renderTask( core, qs.text( std::min( kQsBytes, budget - rest ) ) );
        }
    }
    const bool  over = total( budget ) > budget;
    std::string doc  = body( s, dropped ) + "</brief>";
    std::size_t bytes = 0;
    for( int pass = 0; pass < 3; ++pass )   // bytes= counts itself: converge on the digit count
    {
        bytes = root( bytes, droppedNames, over ).size() + kLegend.size() + doc.size();
    }
    return root( bytes, droppedNames, over ) + std::string( kLegend ) + doc;
}

}   // namespace rw::brief

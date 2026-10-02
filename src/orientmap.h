#pragma once
// orientmap.h — the orient sections of the default whole-repo map (fix #8; docs/EVALS.md "A default map that orients and
// names every core file"). Gate: test/orientmapcheck.sh (written first; its oracle is test/lib/orientmap.py).
//
// WHAT IT ADDS, and what it leaves alone. The ranked map answers "what matters most" by PageRank, so utility sinks and
// vendored macros led it, real subsystems fell out of the window, and nothing named the entry points. This header adds a
// PRESENTATION in front of the ranked rows; the rank vector is untouched (Gate S pins rankGraph and its inputs):
//   O1 <entry_points>  at most 5 rows of evidence-backed entry points (a manifest bin/script, a `main` definition, the
//                      package entry module), core files only; every further one is one next= away;
//   O2 <subsystems>    the first 12 groups of core files by mass, each with n= and its top 3 members;
//   O2 <overflow>      every core file not named yet, breadth-first over the groups, cut at 2,048 B and re-grouped; the
//                      cut is counted and one next= away (RIPWIRE_ORIENT_UNCAPPED=1 is the uncapped variant);
//   O3 <demoted>       utility sinks and vendored/compat files leave the ranked rows and the groups for one counted tail.
// The four elements are rendered ONCE here, so every surface (CLI XML, MCP analyze on a clean tree, MCP rank_by pagerank,
// --json, --html) carries the same bytes — Gate P.
//
// DEFINITIONS (registered; generic, no path or name list beyond the registered vendored/compat one):
//   core file   an indexed file with a code symbol (not a Section, not module scope), Source tier (pathTierOf), not
//               demo/generated (isDemoOrGeneratedPath), not demoted by O3.
//   mass        the sum of a file's symbol scores in the default map's rank vector (the k= the map prints).
//   G           from the root, descend while one child directory holds at least 2/3 of the core mass under G.
//   groups      each child directory of G (`dir/`); a file directly in G joins its name prefix (basename without the
//               extension, leading `_` removed, lowercased, cut before the first `-` or `_`; a prefix equal to a child
//               directory joins that directory); outside G, a top-level directory (`/top/`) or a root file's prefix
//               (`/prefix`). Groups by mass, then label; members by mass, then path. Paths print relative to G (g=);
//               a file outside G prints repo-relative with a leading `/`.
#include "filter.h"            // pathTierOf / isDemoOrGeneratedPath / hasDirSegment — the BASE classifications the rule reads
#include "jsrunner.h"          // jsrunner::detail::topLevelValueStart / readQuoted — the package.json walk the runner detector uses
#include "model.h"
#include "nextverb.h"          // nextAttrXml — the escapeXml policy for an attribute, byte for byte
#include "docparse.h"          // docparse::detail::readWholeFile
#include "infra/Diagnostics.h"
#include "infra/jsonesc.h"     // jsonesc::escapeInto — the JSON map's string escape (serialize.h writeJsonStr's flags)
#include "infra/sortutil.h"    // svLess
#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <string>
#include <string_view>
#include <vector>

namespace rw::orient
{

// ── the registered arms and constants (fixed in the arm's first commit; developed on ripwire/django/webpack + fixtures) ──
enum class Arm : std::uint8_t { O, Narrow, Placebo };
inline constexpr Arm kArm = Arm::O;   // the O-narrow and PLACEBO arm builds flip this one constant

inline constexpr std::size_t kGroupRows        = 12;      // O2: group rows shown
inline constexpr std::size_t kGroupTop         = 3;       // O2: members per group row
inline constexpr std::size_t kEntryRows        = 5;       // O1: entry rows shown
inline constexpr std::size_t kOverflowCutBytes = 2048;    // O2-overflow: the registered cut (half of v1's +4,096 B growth bar)
inline constexpr std::size_t kRunawayBytes     = 24576;   // the runaway guard (~7x the dev corpora's median sections); sets over_ceiling=
inline constexpr std::size_t kPageLimit        = 200;     // a follow-up page's rows (the map's default top-K)
// O3 sink: a file whose code is called from at least kSinkMinCallerFiles other core-candidate files (or kSinkCallerShare of
// them, whichever is more) and that itself calls into at most kSinkMaxCalleeFiles others — a leaf every module leans on.
inline constexpr std::size_t kSinkMinCallerFiles = 8;
inline constexpr double      kSinkCallerShare    = 0.05;
inline constexpr std::size_t kSinkMaxCalleeFiles = 2;
// O3 vendored/compat: the registered generic list (a whole leading directory component, filter.h hasDirSegment).
inline constexpr std::string_view kVendoredDirs[] = { "vendor/", "vendored/", "third_party/", "thirdparty/", "external/", "extern/", "deps/", "compat/" };
// O1: a manifest path under one of these maps to the same-stem source file (when it does not name an indexed file itself).
inline constexpr std::string_view kBuildOutputDirs[] = { "dist/", "build/", "out/", "lib/", "es/", "esm/", "cjs/", "umd/" };
inline constexpr std::string_view kSourceExts[]      = { ".ts", ".tsx", ".mts", ".cts", ".js", ".jsx", ".mjs", ".cjs" };

inline constexpr std::string_view kUncappedEnv = "RIPWIRE_ORIENT_UNCAPPED";   // the reported uncapped variant

// ── the model ──────────────────────────────────────────────────────────────────────────────────────────────────────────
struct EntryRow
{
    std::uint32_t    fileId = 0;
    std::uint32_t    line   = 1;
    std::string      name;
    std::string_view why;            // bin | script | main | entry
};

struct Group
{
    std::string                label;
    std::vector<std::uint32_t> members;   // file ids, mass desc then path
    double                     mass = 0.0;
};

struct Sections
{
    bool                       isActive = false;
    std::vector<char>          demotedFile;      // per file id: 1 = left the ranked rows and the groups (O3)
    std::vector<std::uint32_t> demoted;          // the demoted files, mass desc then path (the tail next= pages)
    std::string                rootG;            // g= (repo-relative, '/'-terminated, "" = the repo root)
    std::vector<Group>         groups;           // every group, in order
    std::vector<std::uint32_t> ranked;           // the breadth-first overflow order (file ids); ranked[i]'s group is rankedGroup[i]
    std::vector<std::uint32_t> rankedGroup;
    std::size_t                overflowShown = 0;
    bool                       isOverCeiling = false;   // the runaway guard cut the (uncapped) overflow
    std::vector<EntryRow>      entries;          // every evidence row, listing order; the first entryShown are listed
    std::size_t                entryShown = 0;
    std::string                xml;              // the four elements, one rendering for every XML surface
    std::string                json;             // the same, as the JSON map header's keys (leading comma)
};

namespace detail
{

inline bool isCodeKind( SymKind k ) noexcept
{
    return k != SymKind::Section && k != SymKind::ModuleScope;
}

inline bool isVendored( std::string_view rel ) noexcept
{
    return std::any_of( std::begin( kVendoredDirs ), std::end( kVendoredDirs ), [ & ]( std::string_view seg ) { return hasDirSegment( rel, seg ); } );
}

inline bool envIsOne( std::string_view name )
{
    const char* const value = std::getenv( std::string( name ).c_str() );   // external input: only the exact value "1" turns it on
    return value != nullptr && std::string_view( value ) == "1";
}

inline std::string prefixOf( std::string_view base )
{
    const std::size_t dot  = base.rfind( '.' );
    std::string_view  stem = ( dot == std::string_view::npos || dot == 0 ) ? base : base.substr( 0, dot );
    std::string       lowered;
    std::size_t       start = 0;
    while( start < stem.size() && stem[ start ] == '_' )
    {
        ++start;
    }
    for( std::size_t i = start; i < stem.size() && stem[ i ] != '-' && stem[ i ] != '_'; ++i )
    {
        lowered.push_back( char( std::tolower( static_cast<unsigned char>( stem[ i ] ) ) ) );
    }
    if( lowered.empty() )
    {
        for( char c : stem )
        {
            lowered.push_back( char( std::tolower( static_cast<unsigned char>( c ) ) ) );
        }
    }
    return lowered;
}

inline std::string_view firstSegment( std::string_view rel ) noexcept
{
    const std::size_t slash = rel.find( '/' );
    return slash == std::string_view::npos ? std::string_view() : rel.substr( 0, slash );
}

// a JSON object body's members: key, and the first string reachable in its value (a condition object's
// import/require/default/node string first, else its first string) — the package.json shapes "bin" and "exports" take
struct JsonMember
{
    std::string key;
    std::string value;
    bool        isObject = false;
};

inline std::string firstStringIn( std::string_view obj )
{
    for( std::string_view cond : { std::string_view( "import" ), std::string_view( "require" ), std::string_view( "default" ), std::string_view( "node" ) } )
    {
        std::size_t p = 0;
        while( ( p = obj.find( '"', p ) ) != std::string_view::npos )
        {
            const std::string k = jsrunner::detail::readQuoted( obj, p );
            std::size_t       v = p;
            while( v < obj.size() && ( obj[ v ] == ' ' || obj[ v ] == ':' || obj[ v ] == '\t' || obj[ v ] == '\n' || obj[ v ] == '\r' ) )
            {
                ++v;
            }
            if( k == cond && v < obj.size() && obj[ v ] == '"' )
            {
                return jsrunner::detail::readQuoted( obj, v );
            }
        }
    }
    std::size_t p = obj.find( ':' );
    p = ( p == std::string_view::npos ) ? std::string_view::npos : obj.find( '"', p );
    return p == std::string_view::npos ? std::string() : jsrunner::detail::readQuoted( obj, p );
}

inline std::vector<JsonMember> objectMembers( std::string_view body )
{
    std::vector<JsonMember> out;
    std::size_t             p = 0;
    while( p < body.size() )
    {
        while( p < body.size() && body[ p ] != '"' && body[ p ] != '}' )
        {
            ++p;
        }
        if( p >= body.size() || body[ p ] == '}' )
        {
            break;
        }
        JsonMember m;
        m.key = jsrunner::detail::readQuoted( body, p );
        while( p < body.size() && ( body[ p ] == ' ' || body[ p ] == ':' || body[ p ] == '\t' || body[ p ] == '\n' || body[ p ] == '\r' ) )
        {
            ++p;
        }
        if( p < body.size() && body[ p ] == '"' )
        {
            m.value = jsrunner::detail::readQuoted( body, p );
        }
        else if( p < body.size() && body[ p ] == '{' )
        {
            int               depth = 0;
            const std::size_t open  = p;
            for( ; p < body.size(); ++p )
            {
                if( body[ p ] == '"' )
                {
                    const std::size_t close = rw::jsonStringEnd( body, p );
                    p = ( close == std::string_view::npos ) ? body.size() - 1 : close;
                    continue;
                }
                depth += ( body[ p ] == '{' ) ? 1 : ( body[ p ] == '}' ) ? -1 : 0;
                if( depth == 0 )
                {
                    break;
                }
            }
            m.value    = firstStringIn( body.substr( open, p - open ) );
            m.isObject = true;
            ++p;
        }
        else
        {
            while( p < body.size() && body[ p ] != ',' && body[ p ] != '}' )
            {
                ++p;
            }
        }
        out.push_back( std::move( m ) );
    }
    return out;
}

// the object body (between its braces) of the top-level `key`, or "" when the value is not an object
inline std::string_view topLevelObject( std::string_view json, std::string_view key )
{
    std::size_t v = jsrunner::detail::topLevelValueStart( json, key );
    if( v == std::string_view::npos || json[ v ] != '{' )
    {
        return {};
    }
    int depth = 0;
    for( std::size_t p = v; p < json.size(); ++p )
    {
        if( json[ p ] == '"' )
        {
            const std::size_t close = rw::jsonStringEnd( json, p );
            p = ( close == std::string_view::npos ) ? json.size() : close;
            continue;
        }
        depth += ( json[ p ] == '{' ) ? 1 : ( json[ p ] == '}' ) ? -1 : 0;
        if( depth == 0 )
        {
            return json.substr( v + 1, p - v - 1 );
        }
    }
    return {};
}

inline std::string topLevelString( std::string_view json, std::string_view key )
{
    std::size_t v = jsrunner::detail::topLevelValueStart( json, key );
    return ( v == std::string_view::npos || json[ v ] != '"' ) ? std::string() : jsrunner::detail::readQuoted( json, v );
}

// the per-file facts every step reads, computed once
struct FileFacts
{
    std::vector<std::string> rel;            // repo-relative path
    std::vector<double>      mass;           // sum of the file's symbol scores
    std::vector<char>        isCandidate;    // code symbol, Source tier, not demo/generated
    std::vector<std::uint32_t> firstSym;     // the file's first code symbol (lowest line, then id), or UINT32_MAX
};

inline FileFacts factsOf( const IngestResult& ing, const std::vector<float>& rank )
{
    const std::size_t F = ing.files.size();
    FileFacts         ff;
    ff.rel.resize( F );
    ff.mass.assign( F, 0.0 );
    ff.isCandidate.assign( F, 0 );
    ff.firstSym.assign( F, UINT32_MAX );
    std::vector<char> hasCode( F, 0 );
    for( std::uint32_t f = 0; f < F; ++f )
    {
        ff.rel[ f ] = std::string( rootRelPath( ing, f ) );
    }
    for( std::uint32_t s = 0; s < ing.symbols.size(); ++s )
    {
        const Symbol& sym = ing.symbols[ s ];
        if( sym.fileId >= F )
        {
            continue;
        }
        ff.mass[ sym.fileId ] += s < rank.size() ? double( rank[ s ] ) : 0.0;
        if( isCodeKind( sym.kind ) )
        {
            hasCode[ sym.fileId ] = 1;
            const std::uint32_t cur = ff.firstSym[ sym.fileId ];
            if( cur == UINT32_MAX || sym.line < ing.symbols[ cur ].line )
            {
                ff.firstSym[ sym.fileId ] = s;
            }
        }
    }
    for( std::uint32_t f = 0; f < F; ++f )
    {
        ff.isCandidate[ f ] = hasCode[ f ] && pathTierOf( ff.rel[ f ] ) == PathTier::Source && !isDemoOrGeneratedPath( ff.rel[ f ] );
    }
    return ff;
}

// O3: the vendored/compat list plus the utility sinks (graph features only: caller files, callee files)
inline std::vector<char> demotedFiles( const IngestResult& ing, const std::vector<std::uint32_t>& outOff, const std::vector<NodeId>& outTargets,
                                       const FileFacts& ff )
{
    const std::size_t           F = ing.files.size();
    std::vector<std::uint64_t>  pairs;   // (caller file << 32) | callee file, candidate files only, distinct files
    for( std::uint32_t u = 0; u + 1 < outOff.size() && u < ing.symbols.size(); ++u )
    {
        const std::uint32_t fu = ing.symbols[ u ].fileId;
        if( fu >= F || !ff.isCandidate[ fu ] )
        {
            continue;
        }
        for( std::uint32_t e = outOff[ u ]; e < outOff[ u + 1 ] && e < outTargets.size(); ++e )
        {
            const NodeId v = outTargets[ e ];
            if( v >= ing.symbols.size() )
            {
                continue;
            }
            const std::uint32_t fv = ing.symbols[ v ].fileId;
            if( fv < F && fv != fu && ff.isCandidate[ fv ] )
            {
                pairs.push_back( ( std::uint64_t( fu ) << 32 ) | fv );
            }
        }
    }
    std::sort( pairs.begin(), pairs.end() );
    pairs.erase( std::unique( pairs.begin(), pairs.end() ), pairs.end() );
    std::vector<std::uint32_t> callerFiles( F, 0 );
    std::vector<std::uint32_t> calleeFiles( F, 0 );
    for( std::uint64_t pr : pairs )
    {
        ++calleeFiles[ std::uint32_t( pr >> 32 ) ];
        ++callerFiles[ std::uint32_t( pr & 0xffffffffu ) ];
    }
    const std::size_t candidateCount = std::size_t( std::count( ff.isCandidate.begin(), ff.isCandidate.end(), char( 1 ) ) );
    const std::size_t minCallers     = std::max( kSinkMinCallerFiles, std::size_t( std::ceil( kSinkCallerShare * double( candidateCount ) ) ) );
    std::vector<char> demoted( F, 0 );
    for( std::uint32_t f = 0; f < F; ++f )
    {
        if( !ff.isCandidate[ f ] )
        {
            continue;
        }
        const bool isSink = callerFiles[ f ] >= minCallers && calleeFiles[ f ] <= kSinkMaxCalleeFiles;
        demoted[ f ] = isSink || isVendored( ff.rel[ f ] );
    }
    return demoted;
}

// mass desc, then path — the one order for members, demoted files and entry rows within a class
inline auto byMassThenPath( const FileFacts& ff )
{
    return [ &ff ]( std::uint32_t a, std::uint32_t b )
    {
        if( ff.mass[ a ] != ff.mass[ b ] )
        {
            return ff.mass[ a ] > ff.mass[ b ];
        }
        return sortutil::svLess( ff.rel[ a ], ff.rel[ b ] );
    };
}

inline std::string groupingRoot( const std::vector<std::uint32_t>& core, const FileFacts& ff )
{
    std::string G;
    while( true )
    {
        double                                   total = 0.0;
        std::vector<std::pair<std::string, double>> kids;   // (child directory, mass), merged after a sort
        for( std::uint32_t f : core )
        {
            const std::string& rel = ff.rel[ f ];
            if( rel.compare( 0, G.size(), G ) != 0 )
            {
                continue;
            }
            total += ff.mass[ f ];
            const std::string_view child = firstSegment( std::string_view( rel ).substr( G.size() ) );
            if( !child.empty() )
            {
                kids.emplace_back( std::string( child ), ff.mass[ f ] );
            }
        }
        if( !( total > 0.0 ) )
        {
            return G;
        }
        std::sort( kids.begin(), kids.end(), []( const auto& a, const auto& b ) { return sortutil::svLess( a.first, b.first ); } );
        std::string hit;
        for( std::size_t i = 0; i < kids.size(); )
        {
            std::size_t j   = i;
            double      sum = 0.0;
            while( j < kids.size() && kids[ j ].first == kids[ i ].first )
            {
                sum += kids[ j ].second;
                ++j;
            }
            if( sum >= total * 2.0 / 3.0 && hit.empty() )
            {
                hit = kids[ i ].first;
            }
            i = j;
        }
        if( hit.empty() )
        {
            return G;
        }
        G += hit;
        G += '/';
    }
}

inline std::string labelOf( std::string_view rel, std::string_view G, const std::vector<std::string>& childDirs, const std::vector<std::string>& topDirs )
{
    const auto has = []( const std::vector<std::string>& v, std::string_view x ) { return std::binary_search( v.begin(), v.end(), x, []( std::string_view a, std::string_view b ) { return sortutil::svLess( a, b ); } ); };
    if( rel.substr( 0, G.size() ) == G )
    {
        const std::string_view rest  = rel.substr( G.size() );
        const std::string_view child = firstSegment( rest );
        if( !child.empty() )
        {
            return std::string( child ) + "/";
        }
        const std::string pre = prefixOf( rest );
        return has( childDirs, pre ) ? pre + "/" : pre;
    }
    const std::string_view top = firstSegment( rel );
    if( !top.empty() )
    {
        return "/" + std::string( top ) + "/";
    }
    const std::string pre = prefixOf( rel );
    return has( topDirs, pre ) ? "/" + pre + "/" : "/" + pre;
}

inline std::string printed( std::string_view rel, std::string_view G )
{
    return rel.substr( 0, G.size() ) == G ? std::string( rel.substr( G.size() ) ) : "/" + std::string( rel );
}

}   // namespace detail

// ── O1: entry points ───────────────────────────────────────────────────────────────────────────────────────────────────
namespace detail
{

// the core file a manifest path names: itself when indexed, else (under a build-output directory) the same-stem source
// file — the one whose directory path shares the most trailing components with the manifest's, then mass, then path
inline std::uint32_t manifestTarget( std::string_view manifestPath, const std::vector<std::uint32_t>& core, const FileFacts& ff )
{
    std::string_view mp = manifestPath;
    while( mp.size() >= 2 && mp[ 0 ] == '.' && mp[ 1 ] == '/' )
    {
        mp.remove_prefix( 2 );
    }
    for( std::uint32_t f : core )
    {
        if( ff.rel[ f ] == mp )
        {
            return f;
        }
    }
    const bool isBuildOutput = std::any_of( std::begin( kBuildOutputDirs ), std::end( kBuildOutputDirs ), [ & ]( std::string_view d ) { return mp.substr( 0, d.size() ) == d; } );
    if( !isBuildOutput )
    {
        return UINT32_MAX;
    }
    const std::size_t      slash = mp.rfind( '/' );
    const std::string_view base  = slash == std::string_view::npos ? mp : mp.substr( slash + 1 );
    const std::size_t      dot   = base.find( '.' );
    const std::string_view stem  = dot == std::string_view::npos ? base : base.substr( 0, dot );
    const std::string_view mdir  = mp.substr( mp.find( '/' ) + 1, slash == std::string_view::npos ? 0 : slash - mp.find( '/' ) );   // below the build dir
    std::uint32_t best = UINT32_MAX;
    std::size_t   bestShared = 0;
    for( std::uint32_t f : core )
    {
        const std::string_view rel   = ff.rel[ f ];
        const std::size_t      fs    = rel.rfind( '/' );
        const std::string_view fbase = fs == std::string_view::npos ? rel : rel.substr( fs + 1 );
        const std::size_t      fdot  = fbase.rfind( '.' );
        if( fdot == std::string_view::npos || fbase.substr( 0, fdot ) != stem
            || std::none_of( std::begin( kSourceExts ), std::end( kSourceExts ), [ & ]( std::string_view e ) { return fbase.substr( fdot ) == e; } ) )
        {
            continue;
        }
        const std::string_view fdir   = fs == std::string_view::npos ? std::string_view() : rel.substr( 0, fs + 1 );
        std::size_t            shared = 0;
        while( shared < mdir.size() && shared < fdir.size() && mdir[ mdir.size() - 1 - shared ] == fdir[ fdir.size() - 1 - shared ] )
        {
            ++shared;
        }
        if( best == UINT32_MAX || shared > bestShared || ( shared == bestShared && byMassThenPath( ff )( f, best ) ) )
        {
            best       = f;
            bestShared = shared;
        }
    }
    return best;
}

// pyproject.toml [project.scripts] / [tool.poetry.scripts]: name = "pkg.mod:func" -> (module, func)
inline std::vector<std::pair<std::string, std::string>> pyprojectScripts( std::string_view toml )
{
    std::vector<std::pair<std::string, std::string>> out;
    bool                                             inScripts = false;
    std::size_t                                      pos       = 0;
    while( pos < toml.size() )
    {
        std::size_t eol = toml.find( '\n', pos );
        eol             = eol == std::string_view::npos ? toml.size() : eol;
        std::string_view line = toml.substr( pos, eol - pos );
        pos                   = eol + 1;
        while( !line.empty() && ( line.front() == ' ' || line.front() == '\t' ) )
        {
            line.remove_prefix( 1 );
        }
        while( !line.empty() && ( line.back() == '\r' || line.back() == ' ' ) )
        {
            line.remove_suffix( 1 );
        }
        if( !line.empty() && line.front() == '[' )
        {
            inScripts = line == "[project.scripts]" || line == "[tool.poetry.scripts]";
            continue;
        }
        const std::size_t q1 = line.find( '"' );
        const std::size_t q2 = q1 == std::string_view::npos ? q1 : line.find( '"', q1 + 1 );
        if( !inScripts || line.find( '=' ) == std::string_view::npos || q2 == std::string_view::npos )
        {
            continue;
        }
        const std::string_view target = line.substr( q1 + 1, q2 - q1 - 1 );
        const std::size_t      colon  = target.find( ':' );
        if( colon != std::string_view::npos )
        {
            out.emplace_back( std::string( target.substr( 0, colon ) ), std::string( target.substr( colon + 1 ) ) );
        }
    }
    return out;
}

inline EntryRow fileRow( const IngestResult& ing, const FileFacts& ff, std::uint32_t f, std::string_view why )
{
    EntryRow r;
    r.fileId = f;
    r.why    = why;
    if( const std::uint32_t s = ff.firstSym[ f ]; s != UINT32_MAX )
    {
        r.line = std::max<std::uint32_t>( 1, ing.symbols[ s ].line );
        r.name = ing.symbols[ s ].name;
    }
    else
    {
        r.name = "<file-scope>";
    }
    return r;
}

// every evidence row from core files, listing order: bin/script, `main` definitions, the entry module (each class by file
// mass then path), then the subpath exports (never listed); one row per file, its first evidence winning
inline std::vector<EntryRow> entryRows( const IngestResult& ing, const std::vector<std::uint32_t>& core, const FileFacts& ff, std::size_t& listable )
{
    std::vector<char> isCore( ing.files.size(), 0 );
    for( std::uint32_t f : core )
    {
        isCore[ f ] = 1;
    }
    std::vector<std::vector<EntryRow>> cls( 4 );
    const std::string root = ing.crawlRoot.empty() ? std::string( "." ) : ing.crawlRoot;
    if( const std::optional<std::string> pj = docparse::detail::readWholeFile( root + "/package.json" ); pj )
    {
        const std::string_view json = *pj;
        const std::string      binStr = topLevelString( json, "bin" );
        std::vector<std::string> bins;
        if( !binStr.empty() )
        {
            bins.push_back( binStr );
        }
        for( const JsonMember& m : objectMembers( topLevelObject( json, "bin" ) ) )
        {
            bins.push_back( m.value );
        }
        for( const std::string& b : bins )
        {
            if( const std::uint32_t f = manifestTarget( b, core, ff ); f != UINT32_MAX )
            {
                cls[ 0 ].push_back( fileRow( ing, ff, f, "bin" ) );
            }
        }
        std::vector<std::string> entryPaths;
        std::vector<std::string> subpaths;
        const std::string        exportsStr = topLevelString( json, "exports" );
        if( !exportsStr.empty() )
        {
            entryPaths.push_back( exportsStr );
        }
        const std::vector<JsonMember> ex = objectMembers( topLevelObject( json, "exports" ) );
        const bool hasSubpathKeys = std::any_of( ex.begin(), ex.end(), []( const JsonMember& m ) { return !m.key.empty() && m.key.front() == '.'; } );
        for( const JsonMember& m : ex )
        {
            if( !hasSubpathKeys && !m.value.empty() )
            {
                entryPaths.push_back( m.value );   // a bare conditions object is the "." export
                break;
            }
            ( m.key == "." ? entryPaths : subpaths ).push_back( m.value );
        }
        if( const std::string mainStr = topLevelString( json, "main" ); !mainStr.empty() )
        {
            entryPaths.push_back( mainStr );
        }
        for( const std::string& e : entryPaths )
        {
            if( const std::uint32_t f = manifestTarget( e, core, ff ); f != UINT32_MAX )
            {
                cls[ 2 ].push_back( fileRow( ing, ff, f, "entry" ) );
            }
        }
        for( const std::string& e : subpaths )
        {
            if( const std::uint32_t f = manifestTarget( e, core, ff ); f != UINT32_MAX )
            {
                cls[ 3 ].push_back( fileRow( ing, ff, f, "entry" ) );
            }
        }
    }
    if( const std::optional<std::string> pp = docparse::detail::readWholeFile( root + "/pyproject.toml" ); pp )
    {
        for( const auto& [ module, func ] : pyprojectScripts( *pp ) )
        {
            std::string modPath = module;
            std::replace( modPath.begin(), modPath.end(), '.', '/' );
            for( const std::string& cand : { modPath + ".py", "src/" + modPath + ".py", modPath + "/__init__.py", "src/" + modPath + "/__init__.py" } )
            {
                const auto hit = std::find_if( core.begin(), core.end(), [ & ]( std::uint32_t f ) { return ff.rel[ f ] == cand; } );
                if( hit == core.end() )
                {
                    continue;
                }
                EntryRow r = fileRow( ing, ff, *hit, "script" );
                for( const Symbol& s : ing.symbols )
                {
                    if( s.fileId == *hit && s.name == func && isCodeKind( s.kind ) )
                    {
                        r.line = std::max<std::uint32_t>( 1, s.line );
                        r.name = s.name;
                        break;
                    }
                }
                cls[ 0 ].push_back( std::move( r ) );
                break;
            }
        }
    }
    for( const Symbol& s : ing.symbols )
    {
        if( s.name == "main" && ( s.kind == SymKind::Function || s.kind == SymKind::Method ) && s.fileId < isCore.size() && isCore[ s.fileId ] )
        {
            EntryRow r;
            r.fileId = s.fileId;
            r.line   = std::max<std::uint32_t>( 1, s.line );
            r.name   = s.name;
            r.why    = "main";
            cls[ 1 ].push_back( std::move( r ) );
        }
    }
    const auto order = byMassThenPath( ff );
    std::vector<EntryRow> out;
    std::vector<char>     taken( ing.files.size(), 0 );
    for( std::size_t c = 0; c < cls.size(); ++c )
    {
        std::stable_sort( cls[ c ].begin(), cls[ c ].end(), [ & ]( const EntryRow& a, const EntryRow& b )
                          {
                              if( a.fileId != b.fileId )
                              {
                                  return order( a.fileId, b.fileId );
                              }
                              return a.line < b.line;
                          } );
        for( EntryRow& r : cls[ c ] )
        {
            if( !taken[ r.fileId ] )
            {
                taken[ r.fileId ] = 1;
                out.push_back( std::move( r ) );
            }
        }
        if( c == 2 )
        {
            listable = std::min( out.size(), kEntryRows );
        }
    }
    return out;
}

// ── rendering: one spelling for every surface ───────────────────────────────────────────────────────────────────────
// ` name="value"` under escapeXml's policy (nextverb.h nextAttrXml writes nothing for an empty value; g="" is a value)
inline std::string attr( std::string_view name, std::string_view value )
{
    return value.empty() ? " " + std::string( name ) + "=\"\"" : nextAttrXml( value, name );
}

inline std::string num( std::string_view name, std::size_t v )
{
    return " " + std::string( name ) + "=\"" + std::to_string( v ) + "\"";
}

inline void jstr( std::string& out, std::string_view key, std::string_view value )
{
    out += ",\"";
    out += key;
    out += "\":\"";
    jsonesc::escapeInto( value, out, /*escapeAngleAmp=*/false, /*validateUtf8=*/true, /*replacementAsTextEscape=*/false );
    out += '"';
}

inline void jnum( std::string& out, std::string_view key, std::size_t v )
{
    out += ",\"";
    out += key;
    out += "\":";
    out += std::to_string( v );
}

inline std::string pageNext( std::string_view kind, std::size_t offset )
{
    return "--orient=" + std::string( kind ) + " --offset=" + std::to_string( offset ) + " --limit=" + std::to_string( kPageLimit );
}

// a section's window: shown= total= capped= [next=] [over_ceiling=]
struct Window
{
    std::size_t shown = 0;
    std::size_t total = 0;
    std::string next;              // empty when nothing is cut
    bool        isOverCeiling = false;
};

inline std::string windowAttrs( const Window& w )
{
    std::string t = num( "shown", w.shown ) + num( "total", w.total ) + num( "capped", w.shown < w.total ? 1 : 0 );
    if( !w.next.empty() )
    {
        t += nextAttrXml( w.next );
    }
    if( w.isOverCeiling )
    {
        t += " over_ceiling=\"1\"";
    }
    return t;
}

inline void windowJson( std::string& out, const Window& w )
{
    jnum( out, "shown", w.shown );
    jnum( out, "total", w.total );
    jnum( out, "capped", w.shown < w.total ? 1 : 0 );
    if( !w.next.empty() )
    {
        jstr( out, "next", w.next );
    }
    if( w.isOverCeiling )
    {
        jnum( out, "over_ceiling", 1 );
    }
}

inline std::string memberXml( std::string_view printedPath )
{
    return "<m" + attr( "p", printedPath ) + "/>";
}

inline std::string entryXml( const FileFacts& ff, const EntryRow& r )
{
    return "<e" + attr( "p", ff.rel[ r.fileId ] + ":" + std::to_string( r.line ) ) + attr( "n", r.name ) + attr( "why", r.why ) + "/>";
}

inline std::string entryJson( const FileFacts& ff, const EntryRow& r )
{
    std::string o;
    jstr( o, "p", ff.rel[ r.fileId ] + ":" + std::to_string( r.line ) );
    jstr( o, "n", r.name );
    jstr( o, "why", r.why );
    return "{" + o.substr( 1 ) + "}";
}

// one group row: <grp l= [n=]><m p=/>…</grp>, and its JSON twin
inline std::string groupXml( std::string_view label, const std::size_t* n, const std::vector<std::string>& members )
{
    std::string out = "<grp" + attr( "l", label ) + ( n ? num( "n", *n ) : std::string() ) + ">";
    for( const std::string& p : members )
    {
        out += memberXml( p );
    }
    return out + "</grp>";
}

inline std::string groupJson( std::string_view label, const std::size_t* n, const std::vector<std::string>& members )
{
    std::string o;
    jstr( o, "l", label );
    if( n )
    {
        jnum( o, "n", *n );
    }
    o += ",\"m\":[";
    for( std::size_t i = 0; i < members.size(); ++i )
    {
        std::string m;
        jstr( m, "p", members[ i ] );
        o += ( i ? ",{" : "{" ) + m.substr( 1 ) + "}";
    }
    return "{" + o.substr( 1 ) + "]}";
}

}   // namespace detail

// ── build: the model, rendered once ─────────────────────────────────────────────────────────────────────────────────────
// `rank` is the default map's vector (rankGraph). Single-root maps only: the caller decides the scope (main.cpp, mcpverbs.h).
inline Sections build( const IngestResult& ing, const std::vector<float>& rank, const std::vector<std::uint32_t>& outOff,
                       const std::vector<NodeId>& outTargets )
{
    Sections                s;
    const detail::FileFacts ff = detail::factsOf( ing, rank );
    const std::size_t       F  = ing.files.size();
    s.isActive    = true;
    s.demotedFile = detail::demotedFiles( ing, outOff, outTargets, ff );
    const auto order = detail::byMassThenPath( ff );

    std::vector<std::uint32_t> core;
    for( std::uint32_t f = 0; f < F; ++f )
    {
        if( ff.isCandidate[ f ] && s.demotedFile[ f ] )
        {
            s.demoted.push_back( f );
        }
        else if( ff.isCandidate[ f ] )
        {
            core.push_back( f );
        }
    }
    std::sort( s.demoted.begin(), s.demoted.end(), order );

    // G, then the groups (labels sorted for the merge, then ordered by mass and label)
    s.rootG = detail::groupingRoot( core, ff );
    const std::string& G = s.rootG;
    std::vector<std::string> childDirs;
    std::vector<std::string> topDirs;
    for( std::uint32_t f : core )
    {
        const std::string_view rel = ff.rel[ f ];
        if( rel.substr( 0, G.size() ) == G )
        {
            if( const std::string_view c = detail::firstSegment( rel.substr( G.size() ) ); !c.empty() )
            {
                childDirs.emplace_back( c );
            }
        }
        else if( const std::string_view t = detail::firstSegment( rel ); !t.empty() )
        {
            topDirs.emplace_back( t );
        }
    }
    const auto byteLess = []( std::string_view a, std::string_view b ) { return sortutil::svLess( a, b ); };
    for( std::vector<std::string>* v : { &childDirs, &topDirs } )
    {
        std::sort( v->begin(), v->end(), byteLess );
        v->erase( std::unique( v->begin(), v->end() ), v->end() );
    }
    std::vector<std::pair<std::string, std::uint32_t>> labelled;
    labelled.reserve( core.size() );
    for( std::uint32_t f : core )
    {
        labelled.emplace_back( detail::labelOf( ff.rel[ f ], G, childDirs, topDirs ), f );
    }
    std::sort( labelled.begin(), labelled.end(), [ & ]( const auto& a, const auto& b ) { return a.first != b.first ? sortutil::svLess( a.first, b.first ) : a.second < b.second; } );
    for( std::size_t i = 0; i < labelled.size(); )
    {
        Group g;
        g.label = labelled[ i ].first;
        for( ; i < labelled.size() && labelled[ i ].first == g.label; ++i )
        {
            g.members.push_back( labelled[ i ].second );
        }
        std::sort( g.members.begin(), g.members.end(), order );
        for( std::uint32_t f : g.members )   // summed in member order: a fixed order, so equal structures sum equal
        {
            g.mass += ff.mass[ f ];
        }
        s.groups.push_back( std::move( g ) );
    }
    std::sort( s.groups.begin(), s.groups.end(), [ & ]( const Group& a, const Group& b ) { return a.mass != b.mass ? a.mass > b.mass : sortutil::svLess( a.label, b.label ); } );

    // the breadth-first overflow order: every group's j-th member before any group's (j+1)-th, groups in order
    std::size_t widest = 0;
    for( const Group& g : s.groups )
    {
        widest = std::max( widest, g.members.size() );
    }
    for( std::size_t j = 0; j < widest; ++j )
    {
        for( std::uint32_t gi = 0; gi < s.groups.size(); ++gi )
        {
            const bool isNamed = gi < kGroupRows && j < kGroupTop;
            if( j < s.groups[ gi ].members.size() && !isNamed )
            {
                s.ranked.push_back( s.groups[ gi ].members[ j ] );
                s.rankedGroup.push_back( gi );
            }
        }
    }
    s.entries = detail::entryRows( ing, core, ff, s.entryShown );

    // ── render ──
    std::string x;
    std::string j;
    {
        const detail::Window w{ s.entryShown, s.entries.size(), s.entryShown < s.entries.size() ? detail::pageNext( "entry", s.entryShown ) : std::string() };
        x += "<entry_points" + detail::windowAttrs( w ) + ">";
        std::string jo;
        detail::windowJson( jo, w );
        jo += ",\"e\":[";
        for( std::size_t i = 0; i < s.entryShown; ++i )
        {
            x += detail::entryXml( ff, s.entries[ i ] );
            jo += ( i ? "," : "" ) + detail::entryJson( ff, s.entries[ i ] );
        }
        x += "</entry_points>";
        j += ",\"entry_points\":{" + jo.substr( 1 ) + "]}";
    }
    {
        const std::size_t    shownGroups = std::min( kGroupRows, s.groups.size() );
        const detail::Window w{ shownGroups, s.groups.size(), shownGroups < s.groups.size() ? detail::pageNext( "groups", shownGroups ) : std::string() };
        x += "<subsystems" + detail::attr( "g", G ) + detail::windowAttrs( w ) + ">";
        std::string jo;
        detail::jstr( jo, "g", G );
        detail::windowJson( jo, w );
        jo += ",\"grp\":[";
        for( std::size_t gi = 0; gi < shownGroups; ++gi )
        {
            const Group&             g = s.groups[ gi ];
            std::vector<std::string> top;
            for( std::size_t m = 0; m < std::min( kGroupTop, g.members.size() ); ++m )
            {
                top.push_back( detail::printed( ff.rel[ g.members[ m ] ], G ) );
            }
            const std::size_t n = g.members.size();
            x += detail::groupXml( g.label, &n, top );
            jo += ( gi ? "," : "" ) + detail::groupJson( g.label, &n, top );
        }
        x += "</subsystems>";
        j += ",\"subsystems\":{" + jo.substr( 1 ) + "]}";
    }
    {
        // the overflow's survivors re-grouped (group order, then member order = their breadth-first order within a group)
        const auto render = [ & ]( std::size_t k, bool isOverCeiling, bool asJson ) -> std::string
        {
            const detail::Window w{ k, s.ranked.size(), k < s.ranked.size() ? detail::pageNext( "overflow", k ) : std::string(), isOverCeiling };
            std::vector<std::vector<std::string>> byGroup( s.groups.size() );
            for( std::size_t i = 0; i < k; ++i )
            {
                byGroup[ s.rankedGroup[ i ] ].push_back( detail::printed( ff.rel[ s.ranked[ i ] ], G ) );
            }
            std::string out = asJson ? std::string() : "<overflow" + detail::windowAttrs( w ) + ">";
            std::string jo;
            if( asJson )
            {
                detail::windowJson( jo, w );
                jo += ",\"grp\":[";
            }
            bool isFirst = true;
            for( std::size_t gi = 0; gi < byGroup.size(); ++gi )
            {
                if( byGroup[ gi ].empty() )
                {
                    continue;
                }
                if( asJson )
                {
                    jo += ( isFirst ? "" : "," ) + detail::groupJson( s.groups[ gi ].label, nullptr, byGroup[ gi ] );
                }
                else
                {
                    out += detail::groupXml( s.groups[ gi ].label, nullptr, byGroup[ gi ] );
                }
                isFirst = false;
            }
            return asJson ? ",\"overflow\":{" + jo.substr( 1 ) + "]}" : out + "</overflow>";
        };
        const bool        isUncapped = detail::envIsOne( kUncappedEnv );
        const std::size_t cut        = isUncapped ? kRunawayBytes : kOverflowCutBytes;
        std::size_t       k          = 0;
        while( k < s.ranked.size() && render( k + 1, false, false ).size() <= cut )
        {
            ++k;
        }
        s.isOverCeiling = isUncapped && k < s.ranked.size();
        s.overflowShown = k;
        x += render( k, s.isOverCeiling, false );
        j += render( k, s.isOverCeiling, true );
    }
    {
        const std::string next = s.demoted.empty() ? std::string() : detail::pageNext( "demoted", 0 );
        x += "<demoted" + detail::num( "utility_demoted", s.demoted.size() ) + ( next.empty() ? std::string() : nextAttrXml( next ) ) + "/>";
        std::string jo;
        detail::jnum( jo, "utility_demoted", s.demoted.size() );
        if( !next.empty() )
        {
            detail::jstr( jo, "next", next );
        }
        j += ",\"demoted\":{" + jo.substr( 1 ) + "}";
    }
    s.xml  = std::move( x );
    s.json = std::move( j );
    return s;
}

// The ranked rows' pick under O (not O-narrow): the demoted files' symbols move behind every other symbol, rank order kept
// within each part, so the top-K never shows them. `order` is the full rank order.
inline void demoteRows( const IngestResult& ing, const Sections& s, std::vector<NodeId>& order )
{
    if( !s.isActive || kArm == Arm::Narrow || s.demoted.empty() )
    {
        return;
    }
    std::stable_partition( order.begin(), order.end(), [ & ]( NodeId id )
                           { return !( id < ing.symbols.size() && ing.symbols[ id ].fileId < s.demotedFile.size() && s.demotedFile[ ing.symbols[ id ].fileId ] ); } );
}

// ── the follow-up page: --orient=entry|groups|overflow|demoted --offset=M --limit=N ──────────────────────────────────────
inline constexpr std::string_view kPageKinds[] = { "entry", "groups", "overflow", "demoted" };

inline constexpr std::string_view kPageLegend =
    "<!-- ripwire orient: one page of a default-map orient section, rank order: <orient kind=entry|groups|overflow|demoted "
    "g=ROOT> rows <e p=FILE:LINE n=SYMBOL why=bin|script|main|entry> (entry points), <grp l=LABEL n=FILES> with its top <m "
    "p=PATH> (groups), <m p=PATH> (overflow names relative to g=, outside it repo-relative with a leading /; demoted files "
    "repo-relative). window: shown= total= capped= has_more= next_offset= offset= limit= page the list (capped=1 cut; "
    "next_offset= pastes as offset=) -->";

inline std::string page( const IngestResult& ing, const std::vector<float>& rank, const Sections& s, std::string_view kind, std::size_t offset, std::size_t limit )
{
    const detail::FileFacts ff = detail::factsOf( ing, rank );
    const std::size_t       lim   = limit == 0 ? kPageLimit : limit;
    const std::size_t       total = kind == "entry" ? s.entries.size() : kind == "groups" ? s.groups.size() : kind == "overflow" ? s.ranked.size() : s.demoted.size();
    const std::size_t       from  = std::min( offset, total );
    const std::size_t       to    = std::min( total, from + lim );
    std::string             rows;
    for( std::size_t i = from; i < to; ++i )
    {
        if( kind == "entry" )
        {
            rows += detail::entryXml( ff, s.entries[ i ] );
        }
        else if( kind == "groups" )
        {
            const Group&             g = s.groups[ i ];
            std::vector<std::string> top;
            for( std::size_t m = 0; m < std::min( kGroupTop, g.members.size() ); ++m )
            {
                top.push_back( detail::printed( ff.rel[ g.members[ m ] ], s.rootG ) );
            }
            const std::size_t n = g.members.size();
            rows += detail::groupXml( g.label, &n, top );
        }
        else if( kind == "overflow" )
        {
            rows += detail::memberXml( detail::printed( ff.rel[ s.ranked[ i ] ], s.rootG ) );
        }
        else
        {
            rows += detail::memberXml( ff.rel[ s.demoted[ i ] ] );
        }
    }
    std::string head = std::string( kPageLegend ) + "<orient" + detail::attr( "kind", kind );
    if( kind == "groups" || kind == "overflow" )
    {
        head += detail::attr( "g", s.rootG );
    }
    head += detail::num( "shown", to - from ) + detail::num( "total", total ) + detail::num( "capped", to < total ? 1 : 0 )
          + detail::num( "has_more", to < total ? 1 : 0 );
    if( to < total )
    {
        head += detail::num( "next_offset", to );
    }
    head += detail::num( "offset", from ) + detail::num( "limit", lim ) + ">";
    return head + rows + "</orient>";
}

}   // namespace rw::orient

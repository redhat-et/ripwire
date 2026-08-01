#pragma once

// ccjson.h — Wave-4 feature: --export=cc.json[:FILE]. Map the per-file metrics ripwire already
// computes (LOC, symbol count, cyclomatic cx, cognitive cx, file-level fan-in/fan-out, git churn)
// into the CodeCharta interchange format (cc.json), so ripwire becomes the metrics producer a
// CodeCharta 3D-city visualization consumes for free.
//
// Format (documented CodeCharta v1.x "flat" shape, apiVersion "1.3"): a single JSON object with
//   { projectName, apiVersion:"1.3", attributeDescriptors:{...}, nodes:[ <root Folder> ] }
// where every node is { name, type:"Folder"|"File", attributes:{metric:value}, children:[...] }.
// The tree is built from each file's path RELATIVE to the scan root; folders sort their children
// deterministically (Folders-before-Files is NOT required — CodeCharta sorts on import — but we
// emit a stable (name asc) order so the det-gate holds).
//
// NOTE ON THE v1.3 WRAPPER: CodeCharta 1.3+ additionally supports wrapping the payload in an outer
// { checksum, data:{...} } envelope. We emit the widely-importer-compatible FLAT top-level form
// (the shape shipped in CodeCharta's own sample cc.json assets); it parses as valid JSON and is
// accepted by the CodeCharta importer. We do not compute the optional MD5 checksum (no deps).
//
// Determinism: files come from ing.files (already sorted); the folder tree is built in that order
// and every children[] is sorted by name; churn/deps are the same deterministic git/graph passes
// used elsewhere. Degrades cleanly with git absent (churn=0 everywhere).

#include "model.h"
#include "graph.h"
#include "jsonesc.h"     // A4-F27: canonical escape core; ccJsonEscape below is a thin wrapper

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// ---- per-file metric bundle. SoA-ish: one struct per file, indexed by fileId (parallel arrays are
//      not warranted at this cardinality; the whole export is a cold path, not a hot loop). ----------
struct CcFileMetrics
{
    std::uint32_t loc        = 0;   // physical lines (newline count + 1 if the file is non-empty)
    std::uint32_t symbols    = 0;   // defs in this file
    std::uint32_t cx         = 0;   // Σ cyclomatic complexity over the file's symbols
    std::uint32_t ccx        = 0;   // Σ cognitive complexity over the file's symbols
    std::uint32_t fanOut     = 0;   // # distinct in-corpus files this file depends on (its #include targets)
    std::uint32_t fanIn      = 0;   // # in-corpus files that depend on this file (afferent coupling)
    std::uint32_t churn      = 0;   // # commits touching this file in the window (0 without git)
};

// physical line count of a file (newline count; +1 for a final line with no trailing newline).
// Degrades to 0 if the file cannot be opened (deleted between crawl and export).
inline std::uint32_t ccCountLoc( const std::string& path ) noexcept
{
    std::FILE* fp = std::fopen( path.c_str(), "rb" );
    if( !fp ) return 0;
    std::uint32_t lines = 0;
    bool          sawByte = false, lastNl = false;
    char          buf[ 65536 ];
    std::size_t   n;
    while( ( n = std::fread( buf, 1, sizeof( buf ), fp ) ) > 0 )
    {
        sawByte = true;
        for( std::size_t i = 0; i < n; ++i ) { lastNl = ( buf[i] == '\n' ); if( lastNl ) ++lines; }
    }
    std::fclose( fp );
    if( sawByte && !lastNl ) ++lines;   // final line without a trailing '\n'
    return lines;
}

// A4-F27: the JSON string-escaper is now a thin wrapper over the canonical core in jsonesc.h
// (jsonesc::escapeCc) — same <>& hardening + UTF-8 validation (A4-F20: invalid UTF-8 scrubs to the
// literal "�" escape sequence) this function has always had; see jsonesc.h's header comment
// for the divergence rationale vs mcp.h's and htmlexport.h's escapers. Signature/behavior
// unchanged: still appends to `out`, still byte-identical on both valid and invalid input.
inline void ccJsonEscape( std::string_view s, std::string& out )
{
    jsonesc::escapeCc( s, out );
}

// ---- the folder tree. One node per path segment; leaves carry a fileId (→ metrics), interior nodes
//      are folders. Children are looked up by an insertion-ordered vector (sorted once at emit) — the
//      cardinality is small and we want deterministic child order without a std::map. ----------------
namespace ccdetail
{
struct CcNode
{
    std::string                name;      // this segment only (not the full path)
    std::int64_t               fileId = -1;   // ≥0 ⇒ File leaf; -1 ⇒ Folder
    std::vector<std::uint32_t> children;      // indices into the node pool
};

// find-or-create a child of `parent` named `seg`; returns its pool index. Linear scan — the fan-out
// per directory is tiny; keeps the pool a flat, pointer-stable-by-index vector (no map, no rehash).
inline std::uint32_t childNamed( std::vector<CcNode>& pool, std::uint32_t parent, std::string_view seg )
{
    for( std::uint32_t ci : pool[ parent ].children )
        if( pool[ ci ].name == seg ) return ci;
    const std::uint32_t id = std::uint32_t( pool.size() );
    pool.push_back( CcNode{ std::string( seg ), -1, {} } );
    pool[ parent ].children.push_back( id );   // NOTE: pool may reallocate; do not hold a CcNode& across this
    return id;
}
}   // namespace ccdetail

// Build the per-file metrics for every ingested file. `churn` is filled by the caller (it owns the
// git pass); everything else is derived from ing/g and the file bytes. Deterministic.
inline std::vector<CcFileMetrics> ccComputeMetrics( const IngestResult& ing, const Graph& g )
{
    const std::uint32_t F = std::uint32_t( ing.files.size() );
    std::vector<CcFileMetrics> m( F );

    // LOC per file (read bytes once).
    for( std::uint32_t f = 0; f < F; ++f ) m[f].loc = ccCountLoc( ing.files[f] );

    // symbol count + Σcx + Σccx per file.
    for( const Symbol& s : ing.symbols )
    {
        CcFileMetrics& e = m[ s.fileId ];
        ++e.symbols;
        e.cx  += s.cx;
        e.ccx += s.ccx;
    }
    (void)g;   // g reserved for future symbol-level fan-in; file-level fan-in/out comes from the dep graph below

    // file-level fan-out (Ce: distinct in-corpus files this file includes) + fan-in (Ca: who includes it).
    const auto adj = resolveIncludeAdj( ing );   // forward = includes; the same graph --deps uses
    for( std::uint32_t f = 0; f < F && f < adj.size(); ++f )
    {
        std::vector<std::uint32_t> outs = adj[f];
        std::sort( outs.begin(), outs.end() );
        outs.erase( std::unique( outs.begin(), outs.end() ), outs.end() );
        m[f].fanOut = std::uint32_t( outs.size() );
        for( std::uint32_t to : outs ) if( to < F ) ++m[ to ].fanIn;   // afferent
    }
    return m;
}

// Emit the cc.json document to `out`. `root` is the scan-root path (stripped from each file so the
// tree is repo-relative); `metrics[f]` must be filled (incl. churn) for every ingested file.
// projectName defaults to the root's basename. Deterministic byte output.
inline void writeCcJson( std::FILE* out, const std::string& root, const IngestResult& ing,
                         const std::vector<CcFileMetrics>& metrics )
{
    using namespace ccdetail;

    // normalize the root prefix (drop trailing '/') so relative paths strip cleanly.
    std::string rootPrefix = root;
    while( rootPrefix.size() > 1 && rootPrefix.back() == '/' ) rootPrefix.pop_back();

    // project name = basename of the root (or "project" for "." / empty).
    std::string projectName;
    {
        std::string_view rp = rootPrefix;
        const std::size_t sl = rp.rfind( '/' );
        std::string_view base = ( sl == std::string_view::npos ) ? rp : rp.substr( sl + 1 );
        projectName = ( base.empty() || base == "." ) ? std::string( "project" ) : std::string( base );
    }

    // build the tree. pool[0] = the synthetic root folder named "root" (CodeCharta convention).
    std::vector<CcNode> pool;
    pool.push_back( CcNode{ std::string( "root" ), -1, {} } );

    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        // repo-relative path: strip "<rootPrefix>/" when present, else use the path as-is.
        std::string_view p = ing.files[f];
        if( p.size() > rootPrefix.size() + 1 && p.compare( 0, rootPrefix.size(), rootPrefix ) == 0 && p[ rootPrefix.size() ] == '/' )
            p = p.substr( rootPrefix.size() + 1 );

        // walk the path segments, creating folders; the final segment becomes a File leaf.
        std::uint32_t cur = 0;
        std::size_t   start = 0;
        while( start < p.size() )
        {
            std::size_t sl = p.find( '/', start );
            const bool  isLeaf = ( sl == std::string_view::npos );
            const std::string_view seg = p.substr( start, ( isLeaf ? p.size() : sl ) - start );
            if( !seg.empty() )
            {
                cur = childNamed( pool, cur, seg );
                if( isLeaf ) pool[ cur ].fileId = std::int64_t( f );
            }
            if( isLeaf ) break;
            start = sl + 1;
        }
    }

    // sort every folder's children by name (deterministic emit; CodeCharta re-sorts on import anyway).
    for( CcNode& n : pool )
        std::sort( n.children.begin(), n.children.end(),
                   [ & ]( std::uint32_t a, std::uint32_t b ) { return pool[a].name < pool[b].name; } );

    // ---- streamed recursive emit. A small explicit helper (no std::function alloc) via a lambda that
    //      captures itself through a reference wrapper is awkward; use an index-driven recursion with a
    //      plain recursive lambda declared as `auto&&` self-parameter. ----------------------------------
    std::string esc;   // reused escape scratch
    const auto emitAttrs = [ & ]( const CcFileMetrics& e )
    {
        std::fprintf( out,
            "\"attributes\":{\"loc\":%u,\"symbols\":%u,\"cx\":%u,\"cognitive_cx\":%u,\"fan_in\":%u,\"fan_out\":%u,\"churn\":%u}",
            e.loc, e.symbols, e.cx, e.ccx, e.fanIn, e.fanOut, e.churn );
    };

    // recursive emit of one node.
    auto emitNode = [ & ]( auto&& self, std::uint32_t id ) -> void
    {
        const CcNode& n = pool[ id ];
        esc.clear();  ccJsonEscape( n.name, esc );
        std::fprintf( out, "{\"name\":\"%s\",", esc.c_str() );

        if( n.fileId >= 0 )   // File leaf
        {
            std::fprintf( out, "\"type\":\"File\"," );
            emitAttrs( metrics[ std::uint32_t( n.fileId ) ] );
            std::fprintf( out, "}" );
            return;
        }

        // Folder: attributes are the aggregate of descendant files? CodeCharta computes folder rollups
        // itself on import, so we emit an empty folder attributes object (import-compatible) + children.
        std::fprintf( out, "\"type\":\"Folder\",\"attributes\":{},\"children\":[" );
        for( std::size_t i = 0; i < n.children.size(); ++i )
        {
            if( i ) std::fprintf( out, "," );
            self( self, n.children[i] );
        }
        std::fprintf( out, "]}" );
    };

    // attributeDescriptors: cheap, static, and makes the CodeCharta UI show friendly axis labels.
    // direction=-1 means "lower is better" (complexity/coupling), +1 means "higher is better" (none here;
    // loc/symbols are neutral, left at -1 per CodeCharta's convention for size-ish metrics). Optional per
    // the spec — included because it is one constexpr-ish blob.
    esc.clear();  ccJsonEscape( projectName, esc );
    std::fprintf( out, "{\"projectName\":\"%s\",\"apiVersion\":\"1.3\",", esc.c_str() );
    std::fprintf( out,
        "\"attributeDescriptors\":{"
        "\"loc\":{\"title\":\"Lines of Code\",\"description\":\"Physical line count\",\"direction\":-1},"
        "\"symbols\":{\"title\":\"Symbols\",\"description\":\"Definitions in the file\",\"direction\":-1},"
        "\"cx\":{\"title\":\"Cyclomatic Complexity\",\"description\":\"Sum of per-symbol cyclomatic complexity\",\"direction\":-1},"
        "\"cognitive_cx\":{\"title\":\"Cognitive Complexity\",\"description\":\"Sum of per-symbol cognitive complexity\",\"direction\":-1},"
        "\"fan_in\":{\"title\":\"Fan In\",\"description\":\"In-corpus files that depend on this file\",\"direction\":-1},"
        "\"fan_out\":{\"title\":\"Fan Out\",\"description\":\"In-corpus files this file depends on\",\"direction\":-1},"
        "\"churn\":{\"title\":\"Churn\",\"description\":\"Commits touching this file in the recent window\",\"direction\":-1}"
        "}," );
    std::fprintf( out, "\"nodes\":[" );
    emitNode( emitNode, 0 );
    std::fprintf( out, "]}\n" );
}

}   // namespace rw

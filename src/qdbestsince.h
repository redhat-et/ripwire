#pragma once

// qdbestsince.h — D4 BEST-SINCE (STAGE0 2.8, #697 idea 2): the history reader behind quality::BestSinceSource.
//
// The ratchet compares a symbol with its BEST value since a reference point, the last release tag reachable from the judged tip
// (`git describe --tags --abbrev=0`). This reads that history for the few files computeDelta names (the files of the functions a
// ratchet row could be about), measures every version with the index's own extraction (ingest.h tangleInputsInBlobs: the tags
// pass plus the callables' cc_walk), and folds each key's per-input minima and lowest score into flat sorted rows. Nothing is
// stored on disk: the walk is one ls-tree, one log and one cat-file batch per chunk over those files only, measured on demand.
// A symbol created after the tag is judged from its creation, because its first version is its first fold.

#include "crossref.h"   // crossref::gitListChecked / catFileBatch / isBlobSha / isNullSha — the read-only git plumbing
#include "ingest.h"     // tangleInputsInBlobs
#include "quality.h"    // BestSinceStore, pathQualifiedKey, foldTangleBest, gitOneLine, headSnapshotIngestMutex

#include "btree.hpp"   // gtl::btree_map — sorted iteration (house rule: never std::map)

#include <mutex>
#include <string>
#include <vector>

namespace rw::quality
{

inline constexpr std::uint32_t kBestSinceMaxBlobs   = 512;          // history versions measured per call, newest first; more = cut
inline constexpr std::size_t   kBestSinceChunkBytes = 64u << 20;   // blob bytes held at once: a chunk is read, measured, dropped

// One version of one judged file: the blob and the ROOT-relative path the ingest keys it under.
struct HistoryBlob
{
    std::string sha;
    std::string relPath;
};

// The git-relative spelling of a root-relative path and back: `prefix` is `git rev-parse --show-prefix` of the ingest root.
inline bool rootRelOfGitPath( std::string_view gitPath, std::string_view prefix, std::string& rel )
{
    if( gitPath.empty() || gitPath.front() == '"' || !gitPath.starts_with( prefix ) )
    {
        return false;   // a C-quoted path (a tab, newline or quote in it) or one outside the root: not a judged file
    }
    rel.assign( gitPath.substr( prefix.size() ) );
    return true;
}

// The versions of `relPaths` since `refSha`: each file's blob at the reference first, then every blob a non-merge commit in refSha..tip
// wrote, newest first; distinct (sha, path) pairs. nullopt when git could not list them.
inline std::optional<std::vector<HistoryBlob>> bestSinceBlobs( const std::string& root, const std::string& refSha, const std::string& tipSha,
                                                               const std::vector<std::string>& relPaths, std::string_view prefix )
{
    std::string pathspec;
    for( const std::string& p : relPaths )
    {
        pathspec += " " + shSingleQuote( p );
    }
    std::vector<HistoryBlob> out;
    std::string              rel;
    const crossref::GitListing atRef = crossref::gitListChecked( root, "--literal-pathspecs ls-tree -r --full-name " + refSha + " --" + pathspec );
    if( !atRef.ok )
    {
        return std::nullopt;
    }
    for( const std::string& line : atRef.lines )
    {
        // "<mode> blob <sha>\t<path>"
        const std::size_t tab = line.find( '\t' );
        const std::vector<std::string_view> fields = wsdetail::segmentsOf( std::string_view( line ).substr( 0, tab == std::string::npos ? 0 : tab ), ' ' );
        if( fields.size() == 3 && fields[1] == "blob" && crossref::isBlobSha( fields[2] ) && rootRelOfGitPath( std::string_view( line ).substr( tab + 1 ), prefix, rel ) )
        {
            out.push_back( { std::string( fields[2] ), rel } );
        }
    }
    const crossref::GitListing log = crossref::gitListChecked( root, "--literal-pathspecs log --format= --raw --no-abbrev --no-renames " + refSha + ".." + tipSha + " --" + pathspec );
    if( !log.ok )
    {
        return std::nullopt;
    }
    for( const std::string& line : log.lines )
    {
        // ":100644 100644 <old> <new> M\t<path>" — the new side; an all-zero sha is a delete
        const std::size_t tab = line.find( '\t' );
        if( line.empty() || line.front() != ':' || tab == std::string::npos )
        {
            continue;
        }
        const std::vector<std::string_view> fields = wsdetail::segmentsOf( std::string_view( line ).substr( 1, tab - 1 ), ' ' );
        if( fields.size() >= 4 && crossref::isBlobSha( fields[3] ) && !crossref::isNullSha( fields[3] ) && rootRelOfGitPath( std::string_view( line ).substr( tab + 1 ), prefix, rel ) )
        {
            out.push_back( { std::string( fields[3] ), rel } );
        }
    }
    std::vector<HistoryBlob> distinct;
    gtl::btree_map<std::string, char> seen;
    for( HistoryBlob& b : out )
    {
        if( seen.emplace( b.sha + '\0' + b.relPath, 0 ).second )
        {
            distinct.push_back( std::move( b ) );
        }
    }
    return distinct;
}

// One chunk of versions measured and folded into `best` (key → packed best, `seen` per key).
inline void foldTangleChunk( const std::vector<HistoryBlob>& chunk, const std::vector<std::string>& bytes, gtl::btree_map<std::uint64_t, std::uint64_t>& best,
                             BestSinceStore& store )
{
    std::vector<BlobText> texts;
    texts.reserve( chunk.size() );
    for( std::size_t i = 0; i < chunk.size(); ++i )
    {
        texts.push_back( { chunk[i].relPath, bytes[i] } );
    }
    std::vector<BlobTangleDefs> measured;
    {
        std::lock_guard<std::mutex> ingestLk( headSnapshotIngestMutex() );   // the blob pool installs queries into the process-global cache
        measured = tangleInputsInBlobs( texts );
    }
    for( std::size_t i = 0; i < chunk.size(); ++i )
    {
        if( measured[i].status != BlobDefsStatus::Parsed )
        {
            store.unread += measured[i].status == BlobDefsStatus::NoGrammar ? 0u : 1u;
            continue;
        }
        ++store.blobs;
        gtl::btree_map<std::uint64_t, TangleInputs> version;   // this version's highest-scoring overload per key (computeSnapshot's rule)
        for( const BlobTangleDef& d : measured[i].defs )
        {
            const std::uint64_t key = pathQualifiedKey( chunk[i].relPath, d.scope, measured[i].lang == Lang::Elixir ? elixirBaseName( d.name ) : std::string_view( d.name ) );
            const auto [ it, fresh ] = version.emplace( key, d.in );
            if( !fresh && tangleOutranks( d.in, it->second ) )
            {
                it->second = d.in;
            }
        }
        for( const auto& [ key, in ] : version )
        {
            const auto [ it, fresh ] = best.emplace( key, 0 );
            it->second               = foldTangleBest( it->second, !fresh, in );
        }
    }
}

// THE SOURCE: the best-since store of every symbol in `relPaths` (root-relative), read from the history of the repo at `root` up to
// `tip` ("HEAD" for the working-tree form). An empty ref is the store's "not read" state (no tag, not a repo, git refused).
inline BestSinceStore tangleBestSince( const std::string& root, const std::string& tip, const std::vector<std::string>& relPaths )
{
    BestSinceStore store;
    const std::string tipSha = gitResolveCommitSha( root, tip );
    if( tipSha.empty() || relPaths.empty() )
    {
        return store;
    }
    const std::string ref    = gitOneLine( root, "describe --tags --abbrev=0 " + tipSha + " 2>/dev/null" );
    const std::string refSha = ref.empty() ? std::string() : gitResolveCommitSha( root, "refs/tags/" + ref );
    if( refSha.empty() )
    {
        return store;
    }
    const std::string prefix = gitOneLine( root, "rev-parse --show-prefix 2>/dev/null" );
    std::optional<std::vector<HistoryBlob>> blobs = bestSinceBlobs( root, refSha, tipSha, relPaths, prefix );
    if( !blobs )
    {
        return store;
    }
    if( blobs->size() > kBestSinceMaxBlobs )
    {
        // the reference versions first, then the log newest first: the cut keeps the reference and the recent versions, and says it cut
        store.cut = true;
        blobs->resize( kBestSinceMaxBlobs );
    }
    gtl::btree_map<std::uint64_t, std::uint64_t> best;
    std::vector<HistoryBlob> chunk;
    std::vector<std::string> bytes;
    std::size_t              held = 0;
    const auto flush = [ & ]()
    {
        foldTangleChunk( chunk, bytes, best, store );
        chunk.clear();
        bytes.clear();
        held = 0;
    };
    std::vector<std::string> shas;
    for( const HistoryBlob& b : *blobs )
    {
        shas.push_back( b.sha );
    }
    std::size_t next = 0;
    const bool  read = crossref::catFileBatch( root, shas, [ & ]( const std::string&, std::string_view type, std::string_view body )
    {
        if( type == "blob" )
        {
            chunk.push_back( ( *blobs )[ next ] );
            bytes.emplace_back( body );
            held += body.size();
        }
        ++next;
        if( held >= kBestSinceChunkBytes )
        {
            flush();
        }
        return true;
    } );
    flush();
    if( !read )
    {
        store.unread += std::uint32_t( shas.size() - std::min( next, shas.size() ) );
    }
    store.ref = ref;
    store.rows.reserve( best.size() );
    for( const auto& [ key, value ] : best )
    {
        store.rows.push_back( { key, value } );   // btree order: sorted by key, as BestSinceStore::find reads it
    }
    return store;
}

}   // namespace rw::quality

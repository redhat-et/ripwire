#pragma once
// filetext.h — THE per-answer file-text reader (HOP-CONTEXT-1, 2026-11-04).
//
// Every verb that prints text out of an indexed file (a signature, a call line, a body) reads the file once per answer
// and keeps it for the rest of that answer. Six near-identical `contentOf` lambdas did that before this file (serialize.h
// x4, mcpverbs.h packConnect, eval.h); this is the one reader the hop record (hoprecord.h) and packConnect read through,
// and the one every remaining copy moves onto (reports/hop-context.md Follow-ons).
//
// It answers three things the lambdas could not:
//   * readable or not — `text()` is nullptr when the file could not be opened, so "could not read" is never "empty file";
//   * changed since indexing — `stale()` compares the read length with the parsed length the index recorded
//     (FileHealth::fileBytes; 0 = not measured, then nothing is claimed). A LENGTH compare: the index stores no content
//     hash, so a same-length edit is not seen here (the CLI indexes in the same run, and the MCP server re-stats every file's
//     mtime/size/ctime before each request, so only an edit inside one request's window reaches this reader);
//   * where a line starts — `lineStarts()` is built once per file on first ask, never by rescanning from byte 0 per site.
// Entries are heap-held, so a reference handed out stays valid while later files are read (ankerl's map moves its values
// on rehash, which the lambdas' `return contents.emplace(...)->second` relied on not happening).

#include "ingest.h"            // canonicalCrawlRoot / crawlPathStaysInRoot — the crawl's own root boundary, re-checked at read
#include "model.h"
#include "infra/ownedfile.h"   // OwnedFile — the stream is owned before any other line runs

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string_view>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <vector>

namespace rw
{

class FileTextCache
{
public:
    explicit FileTextCache( const IngestResult& ing ) : ing_( ing ) {}

    // The file's bytes, or nullptr when it could not be read (gone, permission, not a file).
    const std::string* text( std::uint32_t fid )
    {
        const Entry& e = entry( fid );
        return e.ok ? &e.text : nullptr;
    }

    // The legacy contentOf contract: the bytes, or "" when unreadable (the reader then finds no span inside it).
    const std::string& contentOf( std::uint32_t fid ) { return entry( fid ).text; }

    // True when the file was read and its length differs from the length the index parsed: byte offsets and line numbers
    // stored in the index no longer describe it. False when not measured (fileBytes 0) or unreadable (text() says that).
    bool stale( std::uint32_t fid )
    {
        const Entry& e = entry( fid );
        if( !e.ok || fid >= ing_.fileHealth.size() )
        {
            return false;
        }
        const std::uint32_t parsed = ing_.fileHealth[ fid ].fileBytes;
        return parsed != 0 && parsed != e.text.size();
    }

    // Byte offset of each line's first byte (line 1 at [0]); empty when unreadable. Built once per file.
    std::span<const std::uint32_t> lineStarts( std::uint32_t fid )
    {
        Entry& e = entry( fid );
        if( e.ok && !e.linesBuilt )
        {
            e.lines.push_back( 0 );
            for( std::size_t i = 0; i < e.text.size(); ++i )
            {
                if( e.text[i] == '\n' && i + 1 < e.text.size() )
                {
                    e.lines.push_back( std::uint32_t( i + 1 ) );
                }
            }
            e.linesBuilt = true;
        }
        return e.lines;
    }

    std::size_t filesRead() const noexcept { return reads_; }

private:
    struct Entry
    {
        std::string                text;
        std::vector<std::uint32_t> lines;
        bool                       ok         = false;
        bool                       linesBuilt = false;
    };

    Entry& entry( std::uint32_t fid )
    {
        if( const auto it = cache_.find( fid ); it != cache_.end() )
        {
            return *it->second;
        }
        auto e = std::make_unique<Entry>();
        if( fid < ing_.files.size() )
        {
            ++reads_;
            // §SEC1 at read time (CodeRabbit #535): the crawl refused a symlink out of the root, but a file replaced by one
            // after the crawl would be opened here; its resolved path must still sit inside the root, else it is unreadable
            // (fail closed). Same check, same realpath race as the crawl's own (ingest.h crawlPathStaysInRoot).
            const std::string& path = diskPath( ing_, fid );
            const std::string* root = rootRealOf( fid );
            if( root != nullptr && !crawlPathStaysInRoot( path, *root ) )
            {
                testFault( fid, *e );
                return *cache_.emplace( fid, std::move( e ) ).first->second;
            }
            if( OwnedFile in = openOwnedFile( path.c_str(), "rb" ) )
            {
                char        b[ 4096 ];
                std::size_t n = 0;
                bool        err = false;
                while( ( n = std::fread( b, 1, sizeof( b ), in.file ) ) > 0 )
                {
                    e->text.append( b, n );
                }
                err = std::ferror( in.file ) != 0;
                err = !in.close() || err;
                e->ok = !err;
                if( err )
                {
                    e->text.clear();   // a failed read is unreadable, never a short file
                }
            }
        }
        testFault( fid, *e );
        return *cache_.emplace( fid, std::move( e ) ).first->second;
    }

    // The canonical root a file was crawled under: the multi-root merge's own realpath, else the single crawl root resolved
    // once per answer; nullptr when the index names no root (an ingest built without one): nothing to check against.
    const std::string* rootRealOf( std::uint32_t fid )
    {
        if( !ing_.realPaths.empty() )
        {
            return fid < ing_.fileRoot.size() && ing_.fileRoot[ fid ] < ing_.rootReals.size() ? &ing_.rootReals[ ing_.fileRoot[ fid ] ] : nullptr;
        }
        if( !rootReal_ )
        {
            // test hook (hopcontextcheck arm 11): the root the read is checked against, as if the crawl root were elsewhere, so
            // every indexed file resolves outside it — the shape of a file swapped for an out-of-root link after the crawl,
            // which no single-process run can stage (the CLI crawls in the same run; MCP re-stats every file per request)
            const char* const moved = std::getenv( "RIPWIRE_TEST_FILETEXT_ROOT" );
            if( moved == nullptr && ing_.crawlRoot.empty() )
            {
                return nullptr;
            }
            rootReal_ = canonicalCrawlRoot( moved != nullptr ? std::string_view( moved ) : std::string_view( ing_.crawlRoot ) );
        }
        return &*rootReal_;
    }

    // Test faults (test/hopcontextcheck.sh arm 3; no child process is involved, so a PATH shim cannot reach this read): a file
    // whose path contains RIPWIRE_TEST_FILETEXT_UNREAD reads as unreadable; one containing RIPWIRE_TEST_FILETEXT_EDITED reads
    // with two lines inserted at its top, as if edited after the crawl (every stored offset and line below now points elsewhere);
    // one containing RIPWIRE_TEST_FILETEXT_BLANKED keeps its length and lines with every other byte '#' (a site whose text no
    // longer spells its callee: the macro-expanded shape, which no fixture grammar produces on its own).
    void testFault( std::uint32_t fid, Entry& e ) const
    {
        const std::string_view path = fid < ing_.files.size() ? std::string_view( ing_.files[ fid ] ) : std::string_view();
        const char* const      un   = std::getenv( "RIPWIRE_TEST_FILETEXT_UNREAD" );
        const char* const      ed   = std::getenv( "RIPWIRE_TEST_FILETEXT_EDITED" );
        const char* const      bl   = std::getenv( "RIPWIRE_TEST_FILETEXT_BLANKED" );
        if( un != nullptr && *un != '\0' && path.find( un ) != std::string_view::npos )
        {
            e.ok = false;
            e.text.clear();
        }
        else if( e.ok && ed != nullptr && *ed != '\0' && path.find( ed ) != std::string_view::npos )
        {
            e.text.insert( 0, "// edited\n// after the crawl\n" );
        }
        else if( e.ok && bl != nullptr && *bl != '\0' && path.find( bl ) != std::string_view::npos )
        {
            for( char& c : e.text )   // same length, same lines, no identifier left: a site whose text spells nothing
            {
                c = c == '\n' ? c : '#';
            }
        }
    }

    const IngestResult&                          ing_;
    HashMap<std::uint32_t, std::unique_ptr<Entry>> cache_;
    std::size_t                                  reads_ = 0;
    std::optional<std::string>                   rootReal_;
};

}   // namespace rw

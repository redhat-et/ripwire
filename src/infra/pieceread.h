#pragma once

// pieceread.h — read a byte stream of any size as LINE-ALIGNED PIECES in bounded memory (LARGE-PARTIAL-1).
//
// The lexical readers (--whereis' and --stray-content's git blob streams, --grep's scan of the files the crawl did
// not index) used to SKIP a file or blob over a size cap (2 MiB for a git blob, the crawl ceiling for grep), so a
// name sitting in vscode's 2.36 MB agentService.test.ts read as on-head="0" hits="0" while --callers found its
// definition and 39 callers. Owner rule 2026-11-14: lexical readers skip nothing; they read every byte, streamed.
//
// readInPieces hands a reader at most kPieceBytes at a time, cut after a newline so a piece holds whole lines and
// line numbers stay exact (firstLine). A single line longer than half the window is the one exception: it is cut
// inside the line, and the next piece starts with the last kPieceOverlapBytes of the previous one again (carried=),
// so a needle that straddles the cut is still found whole in the next piece; a reader that counts matches skips
// the ones lying entirely inside the carried prefix (they were counted already). The memory bound is one window per
// reader, whatever the stream's size.

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

namespace rw
{

constexpr std::size_t kPieceBytes        = std::size_t( 2 ) << 20;   // the window: the old blob cap, now a read size
constexpr std::size_t kPieceOverlapBytes = 4096;                     // re-served across a cut inside one long line
constexpr std::size_t kPieceBinaryProbe  = 8192;                     // a NUL in the first bytes ⇒ binary (crossref's kBinaryProbe)

struct BlobPiece
{
    std::string_view bytes;               // whole lines, except a cut inside one long line (midLine on the next piece)
    std::uint32_t    firstLine = 1;       // the 1-based line number of bytes[0]
    std::size_t      carried   = 0;       // bytes at the front the PREVIOUS piece already served (a mid-line cut's overlap)
    std::size_t      total     = 0;       // the whole stream's size
    bool             midLine   = false;   // bytes[0] continues the previous piece's last line
    bool             last      = false;   // the final piece of this stream
};

enum class PieceRead : std::uint8_t
{
    Text,     // every byte served, in pieces
    Binary,   // a NUL in the probe window: consumed, nothing served
    Short,    // the stream ended before `size` bytes: what was served stands, the rest is unread
};

// `read( char* dst, std::size_t n ) -> std::size_t` pulls up to n bytes (0 = the stream ended). `win` is the caller's
// reusable window buffer; it holds at most kPieceBytes bytes.
template<class Read, class OnPiece>
inline PieceRead readInPieces( std::size_t size, Read read, std::string& win, OnPiece onPiece )
{
    win.clear();
    std::size_t   left    = size;
    std::uint32_t line    = 1;
    bool          midLine = false;
    std::size_t   carried = 0;
    bool          probed  = false;
    for( ;; )
    {
        const std::size_t at   = win.size();
        const std::size_t want = std::min( kPieceBytes - at, left );
        win.resize( at + want );
        std::size_t got = 0;
        while( got < want )
        {
            const std::size_t n = read( win.data() + at + got, want - got );
            if( n == 0 )
            {
                break;
            }
            got += n;
        }
        win.resize( at + got );
        left -= got;
        if( got < want )
        {
            return PieceRead::Short;
        }
        if( !probed )
        {
            probed = true;
            if( std::string_view( win ).substr( 0, std::min( win.size(), kPieceBinaryProbe ) ).find( '\0' ) != std::string_view::npos )
            {
                while( left > 0 )   // the stream is framed: consume the rest unread
                {
                    win.resize( std::min( left, kPieceBytes ) );
                    const std::size_t n = read( win.data(), win.size() );
                    if( n == 0 )
                    {
                        return PieceRead::Short;
                    }
                    left -= n;
                }
                win.clear();
                return PieceRead::Binary;
            }
        }
        const bool  last    = left == 0;
        std::size_t cut     = win.size();
        std::size_t keep    = 0;     // bytes moved to the next window's front
        bool        nextMid = false;
        if( !last )
        {
            const std::size_t nl = std::string_view( win ).rfind( '\n' );
            if( nl != std::string_view::npos && win.size() - ( nl + 1 ) <= kPieceBytes / 2 )
            {
                cut  = nl + 1;
                keep = win.size() - cut;   // the partial last line, not yet served
            }
            else
            {
                keep    = std::min( kPieceOverlapBytes, win.size() );   // a cut inside one long line: re-serve its tail
                nextMid = true;
            }
        }
        const std::string_view piece( win.data(), cut );
        onPiece( BlobPiece{ piece, line, carried, size, midLine, last } );
        if( last )
        {
            return PieceRead::Text;
        }
        line += std::uint32_t( std::count( piece.begin(), piece.end(), '\n' ) );
        midLine = nextMid;
        carried = nextMid ? keep : 0;
        win.erase( 0, win.size() - keep );
    }
}

} // namespace rw

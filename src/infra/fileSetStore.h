#pragma once

// fileSetStore.h: the file graph's two stores, both immutable after build, both free of per-file allocation.
//   FileAdjacency  one row of file ids per file: flat offsets + flat targets. Row access is O(1), a row is contiguous.
//   FileSetStore   one sorted set of file ids per file, in the fewest bytes that keep a membership test and an in-order
//                  walk cheap. No insert, union or run containers, and no dependency.
//
// WHO USES FileSetStore. The file graph's transitive include closure (resolve.h::buildFileClosure). A row answers "which files
// does this file reach over >= 1 include or import edge?".
//
// LAYOUT. An id splits into high = id >> chunkBits and low = the rest. A row is its non-empty chunks in high order.
//   rowOfFile[f]   -> row. Files with an identical set share one row, so a row's payload exists once.
//   heads[row]     -> { first chunk, cardinality } followed by the row's presence bitmap, one bit per high value,
//                     dirWords words. A chunk is found by popcount rank, so no chunk stores its own high value, and
//                     the whole row head normally sits in one cache line.
//   chunkOff[k]    -> start of chunk k in words[]; its length is chunkOff[k + 1] - chunkOff[k].
//   words[]        -> u16 payload: a sorted array of lows, or a bitset, whichever is smaller.
// A chunk's form is never stored: a length below the chunk's bitset width means a sorted array, a length equal to it
// means a bitset. The last chunk of the universe is truncated, so its bitset is narrower.
//
// LOOKUP COST, in cache lines touched: rowOfFile, row head, then on a present chunk chunkOff and payload. A sorted array
// adds its binary search's lines, up to about 7 at 16-bit chunks and at most one at 8-bit chunks, where an array holds
// fewer than 16 lows. A miss on the bitmap, 90 % or more of real probes, stops at the row head.
//
// CHUNK SIZE IS DATA-DEPENDENT, so it is a field of the store, picked at build from a fixed sample of rows
// (fileSetChooseChunkBits) and overridable for tests. bench/FILEGRAPH.md has the measurements and the forms that lost.
//
// SELF. A row may hold the file itself: every member of an include cycle shares one row that holds them all. The
// store's contract is the closure's "a file is never in its own set", so contains() and forEach() skip the file, and
// empty() stays exact because the builder never stores a row that holds only its own file.

#include <algorithm>
#include <bit>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <span>
#include <vector>

#include "hashutil.h"
#include "Diagnostics.h"
#include "unordered_dense.h"

namespace rw
{

// Direct edges, file -> file. A row keeps whatever its builder gave it: directive order and duplicates in the un-deduped
// form, sorted and duplicate-free in the deduped one, so its readers' contract is the same as the nested vectors' was.
// Built once from an edge list: a stable counting sort by source, so a row keeps its edges' order and the whole build
// allocates three arrays. retainRows is the one edit after build, and it only shrinks rows.
class FileAdjacency
{
public:
    FileAdjacency() = default;
    explicit FileAdjacency( std::uint32_t files ) : off_( std::size_t( files ) + 1, 0 ) {}

    std::size_t size() const noexcept { return off_.empty() ? 0 : off_.size() - 1; }
    bool        empty() const noexcept { return size() == 0; }
    std::size_t edgeCount() const noexcept { return tgt_.size(); }
    std::size_t bytes() const noexcept { return off_.capacity() * 4 + tgt_.capacity() * 4; }

    std::span<const std::uint32_t> operator[]( std::size_t f ) const noexcept
    {
        ASSUME( f + 1 < off_.size() );
        return { tgt_.data() + off_[f], off_[f + 1] - off_[f] };
    }

    // `from` and `to` are parallel; every from[i] < files. dedup sorts each row and drops repeats.
    static FileAdjacency fromEdges( std::uint32_t files, std::span<const std::uint32_t> from, std::span<const std::uint32_t> to, bool dedup )
    {
        FileAdjacency a( files );
        ASSUME( from.size() == to.size() );
        for( const std::uint32_t f : from )
        {
            ++a.off_[f + 1];
        }
        for( std::uint32_t f = 0; f < files; ++f )
        {
            a.off_[f + 1] += a.off_[f];
        }
        a.tgt_.resize( to.size() );
        std::vector<std::uint32_t> cursor( a.off_.begin(), a.off_.end() - 1 );
        for( std::size_t i = 0; i < from.size(); ++i )
        {
            a.tgt_[cursor[from[i]]++] = to[i];
        }
        if( dedup )
        {
            a.retainRows( []( std::uint32_t, std::span<std::uint32_t> row )
            {
                std::sort( row.begin(), row.end() );
                return std::size_t( std::unique( row.begin(), row.end() ) - row.begin() );
            } );
        }
        a.tgt_.shrink_to_fit();
        return a;
    }

    // Calls fn( file, row ) per file in file order; fn compacts the row in place and returns how many ids it kept.
    template <class Fn>
    void retainRows( Fn&& fn )
    {
        std::uint32_t write = 0, start = 0;
        for( std::size_t f = 0; f < size(); ++f )
        {
            const std::uint32_t end  = off_[f + 1];
            const std::size_t   kept = fn( std::uint32_t( f ), std::span<std::uint32_t>( tgt_.data() + start, end - start ) );
            std::copy_n( tgt_.data() + start, kept, tgt_.data() + write );
            off_[f] = write;
            write += std::uint32_t( kept );
            start = end;
        }
        if( !off_.empty() )
        {
            off_.back() = write;
        }
        tgt_.resize( write );
    }

private:
    std::vector<std::uint32_t> off_;   // file -> first target; files + 1 entries
    std::vector<std::uint32_t> tgt_;
};

class FileSetStore
{
public:
    FileSetStore() = default;

    std::uint32_t fileCount() const noexcept { return std::uint32_t( rowOfFile_.size() ); }
    std::uint32_t rowCount() const noexcept { return rowCount_; }
    std::uint32_t chunkBits() const noexcept { return chunkBits_; }
    std::uint32_t chunkCount() const noexcept { return chunkOff_.empty() ? 0 : std::uint32_t( chunkOff_.size() - 1 ); }

    // True when `file` reaches `id`. A file or id outside the universe is simply not a member.
    bool contains( std::uint32_t file, std::uint32_t id ) const noexcept
    {
        return file < rowOfFile_.size() && id != file && rowHolds( rowOfFile_[file], id );
    }

    // How many files `file` reaches.
    std::uint32_t setSize( std::uint32_t file ) const noexcept
    {
        return file >= rowOfFile_.size() ? 0 : cardinalityHint( file ) - ( rowHolds( rowOfFile_[file], file ) ? 1 : 0 );
    }

    // True when `file` reaches nothing, or is outside the store.
    bool empty( std::uint32_t file ) const noexcept { return file >= rowOfFile_.size() || cardinalityHint( file ) == 0; }

    // The row's size; one more than the set when `file` is on a cycle. A cost hint for choosing between a walk and
    // probes, never an answer.
    std::uint32_t cardinalityHint( std::uint32_t file ) const noexcept
    {
        return file >= rowOfFile_.size() ? 0 : std::uint32_t( heads_[std::size_t( rowOfFile_[file] ) * headWords_] & 0xFFFFFFFFu );
    }

    // Visits the set in ascending id order. No span: chunked rows are not contiguous.
    template <class Fn>
    void forEach( std::uint32_t file, Fn&& fn ) const
    {
        if( file >= rowOfFile_.size() )
        {
            return;
        }
        const std::uint64_t* head = heads_.data() + std::size_t( rowOfFile_[file] ) * headWords_;
        std::uint32_t        k    = std::uint32_t( head[0] >> 32 );
        const std::uint32_t  dw   = dirWords();
        for( std::uint32_t w = 0; w < dw; ++w )
        {
            for( std::uint64_t d = head[1 + w]; d != 0; d &= d - 1, ++k )
            {
                const std::uint32_t  high = w * 64 + std::uint32_t( std::countr_zero( d ) );
                const std::uint32_t  base = high << chunkBits_;
                const std::uint32_t  off  = chunkOff_[k];
                const std::uint32_t  len  = chunkOff_[k + 1] - off;
                const std::uint16_t* p    = words_.data() + off;
                if( len < bitWords( high ) )
                {
                    for( std::uint32_t i = 0; i < len; ++i )
                    {
                        const std::uint32_t id = base + p[i];
                        if( id != file )
                        {
                            fn( id );
                        }
                    }
                    continue;
                }
                for( std::uint32_t i = 0; i < len; ++i )
                {
                    for( std::uint32_t m = p[i]; m != 0; m &= m - 1 )
                    {
                        const std::uint32_t id = base + i * 16 + std::uint32_t( std::countr_zero( m ) );
                        if( id != file )
                        {
                            fn( id );
                        }
                    }
                }
            }
        }
    }

    std::size_t bytes() const noexcept
    {
        return rowOfFile_.capacity() * 4 + heads_.capacity() * 8 + chunkOff_.capacity() * 4 + words_.capacity() * 2;
    }
    std::size_t payloadBytes() const noexcept { return words_.size() * 2; }

    // How many chunks hold a sorted array; the rest hold a bitset. Reports and gates only.
    std::uint32_t arrayChunkCount() const noexcept
    {
        std::uint32_t arrays = 0;
        for( std::uint32_t row = 0; row < rowCount_; ++row )
        {
            const std::uint64_t* head = heads_.data() + std::size_t( row ) * headWords_;
            std::uint32_t        k    = std::uint32_t( head[0] >> 32 );
            for( std::uint32_t w = 0; w + 1 < headWords_; ++w )
            {
                for( std::uint64_t d = head[1 + w]; d != 0; d &= d - 1, ++k )
                {
                    const std::uint32_t high = w * 64 + std::uint32_t( std::countr_zero( d ) );
                    arrays += chunkOff_[k + 1] - chunkOff_[k] < bitWords( high ) ? 1 : 0;
                }
            }
        }
        return arrays;
    }

private:
    friend class FileSetBuilder;

    bool rowHolds( std::uint32_t row, std::uint32_t id ) const noexcept
    {
        if( id >= universe_ )
        {
            return false;
        }
        const std::uint64_t* head = heads_.data() + std::size_t( row ) * headWords_;
        const std::uint32_t  high = id >> chunkBits_;
        const std::uint32_t  w    = high / 64;
        const std::uint64_t  bit  = std::uint64_t( 1 ) << ( high % 64 );
        const std::uint64_t* dir  = head + 1;
        if( ( dir[w] & bit ) == 0 )
        {
            return false;
        }
        std::uint32_t rank = std::uint32_t( std::popcount( dir[w] & ( bit - 1 ) ) );
        for( std::uint32_t i = 0; i < w; ++i )
        {
            rank += std::uint32_t( std::popcount( dir[i] ) );
        }
        const std::uint32_t  k   = std::uint32_t( head[0] >> 32 ) + rank;
        const std::uint32_t  off = chunkOff_[k];
        const std::uint32_t  len = chunkOff_[k + 1] - off;
        const std::uint16_t* p   = words_.data() + off;
        const std::uint32_t  low = id & lowMask();
        if( len < bitWords( high ) )
        {
            return std::binary_search( p, p + len, std::uint16_t( low ) );
        }
        return ( p[low >> 4] >> ( low & 15 ) ) & 1;
    }

    std::uint32_t dirWords() const noexcept
    {
        const std::uint32_t highs = universe_ == 0 ? 1 : ( ( universe_ - 1 ) >> chunkBits_ ) + 1;
        return ( highs + 63 ) / 64;
    }
    std::uint32_t lowMask() const noexcept { return ( std::uint32_t( 1 ) << chunkBits_ ) - 1; }

    // Width of chunk `high`'s bitset in u16 words: a full chunk, or what is left of the universe.
    std::uint32_t bitWords( std::uint32_t high ) const noexcept
    {
        const std::uint32_t start = high << chunkBits_;
        const std::uint32_t width = std::min( std::uint32_t( 1 ) << chunkBits_, universe_ - start );
        return ( width + 15 ) / 16;
    }

    std::uint32_t              universe_  = 0;
    std::uint32_t              chunkBits_ = 16;
    std::uint32_t              headWords_ = 2;
    std::uint32_t              rowCount_  = 0;
    std::vector<std::uint32_t> rowOfFile_;   // file -> row
    std::vector<std::uint64_t> heads_;       // per row: ( first chunk << 32 ) | cardinality, then the presence bitmap
    std::vector<std::uint32_t> chunkOff_;    // chunk -> start in words_; chunkCount + 1 entries
    std::vector<std::uint16_t> words_;       // per chunk: sorted lows, or a bitset
};

// Takes rows in any order, so a sinks-first fold can hand each one over as soon as it is known. A row arrives as a word
// bitset over the universe, or as sorted ids: a row identical to an earlier one is rolled back and shared, so the build
// needs no per-row allocation. The hash map is build-only and freed by finish().
class FileSetBuilder
{
public:
    FileSetBuilder( std::uint32_t universe, std::uint32_t files, std::uint32_t chunkBits )
    {
        s_.universe_  = universe;
        s_.chunkBits_ = chunkBits;
        s_.headWords_ = 1 + s_.dirWords();
        s_.rowOfFile_.assign( files, 0 );
        s_.chunkOff_.push_back( 0 );
        // Row 0 is the empty row, so a file with no row of its own costs one u32 and nothing else.
        s_.heads_.assign( s_.headWords_, 0 );
        s_.rowCount_ = 1;
    }

    // Adds a row from `n` strictly ascending ids and returns its row number.
    std::uint32_t addSorted( const std::uint32_t* ids, std::size_t n )
    {
        if( n == 0 )
        {
            return 0;
        }
        beginRow();
        for( std::size_t i = 0; i < n; )
        {
            const std::uint32_t high = ids[i] >> s_.chunkBits_;
            std::size_t         j    = i;
            while( j < n && ( ids[j] >> s_.chunkBits_ ) == high )
            {
                ++j;
            }
            emitChunk( high, ids + i, j - i );
            i = j;
        }
        return endRow( std::uint32_t( n ) );
    }

    // Adds a row from a bitset of `wordCount` u64 words over the universe and returns its row number.
    std::uint32_t addBits( const std::uint64_t* bits, std::uint32_t wordCount )
    {
        scratch_.clear();
        for( std::uint32_t q = 0; q < wordCount; ++q )
        {
            for( std::uint64_t m = bits[q]; m != 0; m &= m - 1 )
            {
                scratch_.push_back( q * 64 + std::uint32_t( std::countr_zero( m ) ) );
            }
        }
        // scratch_ is reused by nothing below addSorted, so a row costs no allocation once it has grown.
        return addSorted( scratch_.data(), scratch_.size() );
    }

    void setRow( std::uint32_t file, std::uint32_t row ) noexcept
    {
        ASSUME( file < s_.rowOfFile_.size() && row < s_.rowCount_ );
        s_.rowOfFile_[file] = row;
    }

    FileSetStore finish()
    {
        firstRowOfHash_ = {};
        scratch_        = {};
        s_.heads_.shrink_to_fit();
        s_.chunkOff_.shrink_to_fit();
        s_.words_.shrink_to_fit();
        return std::move( s_ );
    }

private:
    void beginRow()
    {
        rowStart_ = s_.heads_.size();
        s_.heads_.resize( rowStart_ + s_.headWords_, 0 );
        s_.heads_[rowStart_] = std::uint64_t( std::uint32_t( s_.chunkOff_.size() - 1 ) ) << 32;
        hash_                = kHashSeed;
    }

    void mix( std::uint64_t v ) noexcept { hash_ = hashutil::fnv1aMultiply( hash_ ^ v ); }

    void emitChunk( std::uint32_t high, const std::uint32_t* ids, std::size_t card )
    {
        const std::uint32_t mask = s_.lowMask();
        const std::uint32_t bw   = s_.bitWords( high );
        const std::size_t   off  = s_.words_.size();
        s_.heads_[rowStart_ + 1 + high / 64] |= std::uint64_t( 1 ) << ( high % 64 );
        mix( high );
        if( card < bw )
        {
            for( std::size_t k = 0; k < card; ++k )
            {
                const auto low = std::uint16_t( ids[k] & mask );
                s_.words_.push_back( low );
                mix( low );
            }
        }
        else
        {
            s_.words_.resize( off + bw, 0 );
            for( std::size_t k = 0; k < card; ++k )
            {
                const std::uint32_t low = ids[k] & mask;
                s_.words_[off + ( low >> 4 )] = std::uint16_t( s_.words_[off + ( low >> 4 )] | ( 1u << ( low & 15 ) ) );
            }
            for( std::uint32_t k = 0; k < bw; ++k )
            {
                mix( s_.words_[off + k] );
            }
        }
        s_.chunkOff_.push_back( std::uint32_t( s_.words_.size() ) );
    }

    std::uint32_t endRow( std::uint32_t card )
    {
        s_.heads_[rowStart_] |= card;
        const std::uint32_t row = s_.rowCount_;
        auto [ it, fresh ]      = firstRowOfHash_.try_emplace( hash_, row );
        if( !fresh && sameAsRow( it->second ) )
        {
            s_.words_.resize( s_.chunkOff_[std::uint32_t( s_.heads_[rowStart_] >> 32 )] );
            s_.chunkOff_.resize( std::size_t( s_.heads_[rowStart_] >> 32 ) + 1 );
            s_.heads_.resize( rowStart_ );
            return it->second;
        }
        ++s_.rowCount_;
        return row;
    }

    // Verify, since the row is shared on a hash: same bitmap and cardinality, same chunk lengths, same payload.
    bool sameAsRow( std::uint32_t row ) const noexcept
    {
        const std::uint64_t* a  = s_.heads_.data() + std::size_t( row ) * s_.headWords_;
        const std::uint64_t* b  = s_.heads_.data() + rowStart_;
        if( ( a[0] & 0xFFFFFFFFu ) != ( b[0] & 0xFFFFFFFFu ) || !std::equal( a + 1, a + s_.headWords_, b + 1 ) )
        {
            return false;
        }
        std::uint32_t chunks = 0;
        for( std::uint32_t i = 1; i < s_.headWords_; ++i )
        {
            chunks += std::uint32_t( std::popcount( b[i] ) );
        }
        const std::uint32_t ka = std::uint32_t( a[0] >> 32 ), kb = std::uint32_t( b[0] >> 32 );
        const std::uint32_t oa = s_.chunkOff_[ka], ob = s_.chunkOff_[kb];
        const std::uint32_t la = s_.chunkOff_[ka + chunks] - oa, lb = s_.chunkOff_[kb + chunks] - ob;
        return la == lb && std::equal( s_.chunkOff_.begin() + ka, s_.chunkOff_.begin() + ka + chunks + 1, s_.chunkOff_.begin() + kb,
                                       [ oa, ob ]( std::uint32_t x, std::uint32_t y ) noexcept { return x - oa == y - ob; } )
               && std::equal( s_.words_.begin() + oa, s_.words_.begin() + oa + la, s_.words_.begin() + ob );
    }

    static constexpr std::uint64_t kHashSeed = 1469598103934665603ull;

    FileSetStore                                               s_;
    ankerl::unordered_dense::map<std::uint64_t, std::uint32_t> firstRowOfHash_;
    std::vector<std::uint32_t>                                 scratch_;
    std::size_t                                                rowStart_ = 0;
    std::uint64_t                                              hash_     = 0;
};

// Picks the chunk size with the fewest bytes for a set of sample rows. Candidates, widest first; a tie keeps the wider.
// Deterministic: a pure function of the sample.
inline std::uint32_t fileSetChooseChunkBits( std::span<const std::vector<std::uint32_t>> sample, std::uint32_t universe ) noexcept
{
    static constexpr std::uint32_t kCandidates[] = { 16, 12, 10, 8 };
    std::uint32_t                  best          = 16;
    std::size_t                    bestBytes     = ~std::size_t( 0 );
    for( const std::uint32_t bits : kCandidates )
    {
        const std::uint32_t highs = universe == 0 ? 1 : ( ( universe - 1 ) >> bits ) + 1;
        std::size_t         bytes = std::size_t( 1 + ( highs + 63 ) / 64 ) * 8 * sample.size();
        for( const std::vector<std::uint32_t>& row : sample )
        {
            for( std::size_t i = 0; i < row.size(); )
            {
                const std::uint32_t high = row[i] >> bits;
                std::size_t         j    = i;
                while( j < row.size() && ( row[j] >> bits ) == high )
                {
                    ++j;
                }
                const std::uint32_t width = std::min( std::uint32_t( 1 ) << bits, universe - ( high << bits ) );
                bytes += std::min( j - i, std::size_t( ( width + 15 ) / 16 ) ) * 2 + 4;
                i = j;
            }
        }
        if( bytes < bestBytes )
        {
            bestBytes = bytes;
            best      = bits;
        }
    }
    return best;
}

struct FileClosureStats
{
    std::uint32_t sccs          = 0;
    std::uint32_t bitRowsPeak   = 0;   // working bitset rows alive at once; each is universe / 8 bytes
    std::size_t   workPeakBytes = 0;
};

// The transitive closure: for each file, every file it reaches over >= 1 edge, never itself. `adj` needs size() and
// operator[] giving a range of u32; duplicate ids, self edges and ids >= adj.size() are tolerated and contribute nothing.
//
// A word-parallel fold over the strongly connected components, sinks first: a component's row is the OR of its
// successors' rows plus their ids, so each edge costs universe / 64 word operations whatever the closure's size, where
// a walk per file costs the closure's size per file. A row is compressed into the store as soon as it is known and its
// working bitset is reused once every predecessor has read it, so the bitsets alive at once are the fold's frontier,
// not N. Each component's members share one row, which holds them all when the component is a cycle.
//
// Result is a pure function of `adj`: Tarjan runs in file-id order, the row a file gets is decided by its set alone.
// chunkBitsOverride != 0 forces the chunk size (tests); otherwise it comes from a fixed stride of up to 64 files.
template <class Adj>
inline FileSetStore buildFileClosure( const Adj& adj, std::uint32_t chunkBitsOverride = 0, FileClosureStats* statsOut = nullptr )
{
    static constexpr std::uint32_t kNone = ~std::uint32_t( 0 );
    const std::uint32_t            F     = std::uint32_t( adj.size() );
    const std::uint32_t            words = ( F + 63 ) / 64;

    // Tarjan, iterative: no recursion on any thread. Components come out sinks first.
    std::vector<std::uint32_t> index( F, 0 ), low( F, 0 ), comp( F, kNone ), edgePos( F, 0 ), onStack, callStack, order, compStart;
    std::uint32_t              counter = 0;
    for( std::uint32_t r = 0; r < F; ++r )
    {
        if( index[r] != 0 )
        {
            continue;
        }
        index[r] = low[r] = ++counter;
        onStack.push_back( r );
        callStack.push_back( r );
        while( !callStack.empty() )
        {
            const std::uint32_t v   = callStack.back();
            const auto&         row = adj[v];
            if( edgePos[v] < row.size() )
            {
                const std::uint32_t w = row[edgePos[v]++];
                if( w >= F )
                {
                    continue;
                }
                if( index[w] == 0 )
                {
                    index[w] = low[w] = ++counter;
                    onStack.push_back( w );
                    callStack.push_back( w );
                }
                else if( comp[w] == kNone )
                {
                    low[v] = std::min( low[v], index[w] );
                }
                continue;
            }
            callStack.pop_back();
            if( !callStack.empty() )
            {
                low[callStack.back()] = std::min( low[callStack.back()], low[v] );
            }
            if( low[v] == index[v] )
            {
                const std::uint32_t id = std::uint32_t( compStart.size() );
                compStart.push_back( std::uint32_t( order.size() ) );
                std::uint32_t w = kNone;
                do
                {
                    w = onStack.back();
                    onStack.pop_back();
                    comp[w] = id;
                    order.push_back( w );
                } while( w != v );
            }
        }
    }
    compStart.push_back( F );
    const std::uint32_t C = std::uint32_t( compStart.size() - 1 );
    index = {};  low = {};  edgePos = {};  onStack = {};  callStack = {};

    // A component's readers: every edge that enters it from another component. Its bitset is free after the last.
    std::vector<std::uint32_t> readers( C, 0 );
    for( std::uint32_t v = 0; v < F; ++v )
    {
        for( const std::uint32_t w : adj[v] )
        {
            if( w < F && comp[w] != comp[v] )
            {
                ++readers[comp[w]];
            }
        }
    }

    std::uint32_t chunkBits = chunkBitsOverride;
    if( chunkBits == 0 )
    {
        // Sample: up to 64 files with an edge, at a fixed stride, walked once each; the bytes per candidate are arithmetic.
        std::vector<std::vector<std::uint32_t>> sample;
        std::vector<std::uint32_t>              seen( F, kNone ), stack;
        const std::uint32_t                     stride = std::max( F / 64, std::uint32_t( 1 ) );
        for( std::uint32_t s = 0; s < F && sample.size() < 64; s += stride )
        {
            std::vector<std::uint32_t> row;
            stack.assign( 1, s );
            seen[s] = s;
            while( !stack.empty() )
            {
                const std::uint32_t v = stack.back();
                stack.pop_back();
                for( const std::uint32_t w : adj[v] )
                {
                    if( w < F && seen[w] != s )
                    {
                        seen[w] = s;
                        stack.push_back( w );
                        row.push_back( w );
                    }
                }
            }
            if( !row.empty() )
            {
                std::sort( row.begin(), row.end() );
                sample.push_back( std::move( row ) );
            }
        }
        chunkBits = fileSetChooseChunkBits( sample, F );
    }

    FileSetBuilder                b( F, F, chunkBits );
    std::vector<std::uint64_t*>   slotOfComp( C, nullptr );
    std::vector<std::uint64_t*>   freeSlots;
    std::vector<std::unique_ptr<std::uint64_t[]>> slots;
    std::uint32_t                 alive = 0, alivePeak = 0;
    const auto release = [ & ]( std::uint64_t* p )
    {
        freeSlots.push_back( p );
        --alive;
    };
    for( std::uint32_t k = 0; k < C; ++k )
    {
        const std::uint32_t a = compStart[k], z = compStart[k + 1];
        bool                any = z - a > 1;
        for( std::uint32_t i = a; i < z && !any; ++i )
        {
            for( const std::uint32_t w : adj[order[i]] )
            {
                if( w < F && comp[w] != k )
                {
                    any = true;
                    break;
                }
            }
        }
        if( !any )
        {
            continue;   // a sink with no cycle: reaches nothing, stays on the shared empty row, costs no bitset
        }
        std::uint64_t* dst = nullptr;
        if( !freeSlots.empty() )
        {
            dst = freeSlots.back();
            freeSlots.pop_back();
        }
        else
        {
            slots.push_back( std::make_unique<std::uint64_t[]>( words ) );
            dst = slots.back().get();
        }
        alivePeak = std::max( alivePeak, ++alive );
        std::fill_n( dst, words, std::uint64_t( 0 ) );
        for( std::uint32_t i = a; i < z; ++i )
        {
            const std::uint32_t v = order[i];
            if( z - a > 1 )
            {
                dst[v / 64] |= std::uint64_t( 1 ) << ( v % 64 );
            }
            for( const std::uint32_t w : adj[v] )
            {
                if( w >= F || comp[w] == k )
                {
                    continue;
                }
                dst[w / 64] |= std::uint64_t( 1 ) << ( w % 64 );
                const std::uint32_t cw = comp[w];
                if( const std::uint64_t* src = slotOfComp[cw]; src != nullptr )
                {
                    for( std::uint32_t q = 0; q < words; ++q )
                    {
                        dst[q] |= src[q];
                    }
                }
                if( --readers[cw] == 0 && slotOfComp[cw] != nullptr )
                {
                    release( slotOfComp[cw] );
                    slotOfComp[cw] = nullptr;
                }
            }
        }
        const std::uint32_t row = b.addBits( dst, words );
        for( std::uint32_t i = a; i < z; ++i )
        {
            b.setRow( order[i], row );
        }
        if( readers[k] == 0 )
        {
            release( dst );
        }
        else
        {
            slotOfComp[k] = dst;
        }
    }
    if( statsOut != nullptr )
    {
        statsOut->sccs          = C;
        statsOut->bitRowsPeak   = alivePeak;
        statsOut->workPeakBytes = std::size_t( alivePeak ) * words * 8;
    }
    return b.finish();
}

} // namespace rw

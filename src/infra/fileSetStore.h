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
//                     dirWords words. A chunk is found by popcount rank, so no chunk stores its own high value. A head
//                     is 16 B at 16-bit chunks up to 128 K files; heads_ is not aligned, so a longer one can straddle
//                     two cache lines.
//   chunkOff[k]    -> start of chunk k in words[]; its length is chunkOff[k + 1] - chunkOff[k].
//   words[]        -> u16 payload: a sorted array of lows, or a bitset, whichever is smaller.
// A chunk's form is never stored: a length below the chunk's bitset width means a sorted array, a length equal to it
// means a bitset. The last chunk of the universe is truncated, so its bitset is narrower.
//
// LOOKUP COST, in cache lines touched: rowOfFile, row head, then on a present chunk chunkOff and payload. A sorted array
// adds its binary search's lines, up to about 7 at 16-bit chunks and at most one at 8-bit chunks, where an array holds
// fewer than 16 lows. Only a miss on the BITMAP stops at the row head, and that is 0-100 % of real probes, by repo: 100 %
// terraform, 94 % cockroach, 91 % envoy, 64 % vscode, 52 % cpython, 0 % zed (every probe there lands in a present chunk).
// The rest reach chunkOff and the payload: a sorted array's search or a bitset's word. bench/FILEGRAPH.md has the table.
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
#include <cstring>
#include <limits>
#include <memory>
#include <new>
#include <ranges>
#include <span>
#include <vector>

#include "hashutil.h"
#include "Diagnostics.h"
#include "fileGraphStop.h"
#include "profileScope.h"   // PROFILE_SCOPE_DESCRIBE: the closure build's phases; ((void)0) unless -DRIPWIRE_PROFILE=ON
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

    // Derived from off_, so a moved-from adjacency is empty (size 0), not a count of rows it no longer has.
    std::size_t size() const noexcept { return off_.empty() ? 0 : off_.size() - 1; }
    bool        empty() const noexcept { return size() == 0; }
    std::size_t edgeCount() const noexcept { return tgt_.size(); }
    std::size_t bytes() const noexcept { return off_.capacity() * 4 + tgt_.capacity() * 4; }

    std::span<const std::uint32_t> operator[]( std::size_t f ) const noexcept
    {
        ASSUME( f + 1 < off_.size() );
        return { tgt_.data() + off_[f], off_[f + 1] - off_[f] };
    }

    // `from` and `to` are parallel; every from[i] < files. dedup sorts each row and drops repeats. Offsets are u32, so more
    // than `edgeLimit` (default 2^32 - 1) edges cannot be stored: the stop is recorded (fileGraphStop.h) and the result has
    // `files` empty rows, which callers must not answer from. 4 G edges is 16 GB of targets, so no real tree reaches it;
    // the limit is a parameter so a test can.
    static FileAdjacency fromEdges( std::uint32_t files, std::span<const std::uint32_t> from, std::span<const std::uint32_t> to, bool dedup,
                                    std::uint64_t edgeLimit = std::numeric_limits<std::uint32_t>::max() )
    {
        FileAdjacency a( files );
        ASSUME( from.size() == to.size() );
        if( to.size() > edgeLimit )
        {
            DISCLOSE( Diagnostics::answerRefused, "fileSetStore: more file-graph edges than a 32-bit offset holds — stop recorded, no answer from this graph" );
            fileGraphStopRecord( FileGraphStop::Capacity );
            return a;
        }
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
    std::vector<std::uint32_t> off_;   // file -> first target; files + 1 entries (empty only when default-constructed or moved from)
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

    std::size_t bytes() const noexcept { return rowOfFile_.size() * 4 + heads_.size() * 8 + chunkOff_.size() * 4 + words_.size() * 2; }
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

    // ORs row `row` (a finished row: its successor's head, or the store's end, bounds its chunks) into a working row.
    template <class Work>
    void orRowInto( std::uint32_t row, Work& dst ) const
    {
        const std::uint64_t* head = heads_.data() + std::size_t( row ) * headWords_;
        std::uint32_t        k    = std::uint32_t( head[0] >> 32 );
        const std::uint32_t  last = row + 1 < rowCount_ ? std::uint32_t( heads_[std::size_t( row + 1 ) * headWords_] >> 32 ) : chunkCount();
        const std::uint32_t  dw   = dirWords();
        for( std::uint32_t w = 0; w < dw && k < last; ++w )
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
                        dst.set( base + p[i] );
                    }
                    continue;
                }
                std::uint32_t i = 0;
                if constexpr( std::endian::native == std::endian::little )
                {
                    // A chunk of >= 64 ids starts on a u64 boundary of the universe: four payload words are one working word.
                    for( ; chunkBits_ >= 6 && i + 4 <= len; i += 4 )
                    {
                        std::uint64_t quad = 0;
                        std::memcpy( &quad, p + i, sizeof quad );
                        dst.orBits64( base + i * 16, quad );
                    }
                }
                for( ; i < len; ++i )
                {
                    dst.orBits16( base + i * 16, p[i] );
                }
            }
        }
    }

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

// One working row for the fold: a bitset over the universe plus the list of words it has touched, so a component costs its
// own row and not N / 64 words to clear and scan. Whatever a row is ORed from, a store row or an edge, only touched words
// are ever visited.
class FileWorkRow
{
public:
    explicit FileWorkRow( std::uint32_t universe ) : bits_( ( std::size_t( universe ) + 63 ) / 64, 0 ) {}

    void set( std::uint32_t id ) { orWord( id / 64, std::uint64_t( 1 ) << ( id % 64 ) ); }
    // `v` is the 64 bits that start at id `id0`, a multiple of 64.
    void orBits64( std::uint32_t id0, std::uint64_t v )
    {
        if( v != 0 )
        {
            orWord( id0 / 64, v );
        }
    }
    // `v` is up to 16 bits that start at bit `id0` (a multiple of 16), so they never straddle a word.
    void orBits16( std::uint32_t id0, std::uint64_t v )
    {
        if( v != 0 )
        {
            orWord( id0 / 64, v << ( id0 % 64 ) );
        }
    }

    std::size_t wordCount() const noexcept { return bits_.size(); }
    std::size_t bytes() const noexcept { return bits_.capacity() * 8 + touched_.capacity() * 4; }

    // The row's ids in ascending order into `out`, then the row is cleared. A row that touched more than a sixteenth of the
    // words is scanned in place, since sorting the touched list would cost more than the scan.
    void drain( std::vector<std::uint32_t>& out )
    {
        out.clear();
        const bool scan = touched_.size() > bits_.size() / 16;
        if( !scan )
        {
            std::sort( touched_.begin(), touched_.end() );
        }
        const std::size_t n = scan ? bits_.size() : touched_.size();
        for( std::size_t t = 0; t < n; ++t )
        {
            const std::uint32_t q = scan ? std::uint32_t( t ) : touched_[t];
            for( std::uint64_t m = bits_[q]; m != 0; m &= m - 1 )
            {
                out.push_back( q * 64 + std::uint32_t( std::countr_zero( m ) ) );
            }
            bits_[q] = 0;
        }
        touched_.clear();
    }

private:
    void orWord( std::uint32_t q, std::uint64_t v )
    {
        if( bits_[q] == 0 )
        {
            touched_.push_back( q );
        }
        bits_[q] |= v;
    }

    std::vector<std::uint64_t> bits_;
    std::vector<std::uint32_t> touched_;
};

// Takes rows in any order. A row arrives as sorted ids, or as a working row: a row identical to an earlier one is rolled
// back and shared, so the build needs no per-row allocation. The hash map is build-only and freed by finish().
//
// `hashMask` is a test seam: the row hash is ANDed with it, so a gate can force every row onto one hash and prove the
// verify, not the hash, decides what is shared. `wordLimit` is the largest payload the u32 chunk offsets can address
// (2^32 - 1 words, a parameter so a test can reach the stop): past it a row is rolled back, nothing wraps, overflowed()
// turns true, and the caller must stop and disclose.
class FileSetBuilder
{
public:
    FileSetBuilder( std::uint32_t universe, std::uint32_t files, std::uint32_t chunkBits, std::uint64_t hashMask = ~std::uint64_t( 0 ),
                    std::uint64_t wordLimit = std::numeric_limits<std::uint32_t>::max() )
        : hashMask_( hashMask ), wordLimit_( wordLimit )
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

    // Adds a row from `n` strictly ascending ids and returns its row number (0 when nothing was stored: n == 0 or overflow).
    std::uint32_t addSorted( const std::uint32_t* ids, std::size_t n )
    {
        if( n == 0 || overflowed_ )
        {
            return 0;
        }
        beginRow();
        for( std::size_t i = 0; i < n && !overflowed_; )
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

    // Adds the working row's ids as a row, and clears the working row.
    std::uint32_t addWork( FileWorkRow& work )
    {
        work.drain( scratch_ );
        // scratch_ is reused by nothing below addSorted, so a row costs no allocation once it has grown.
        return addSorted( scratch_.data(), scratch_.size() );
    }

    // ORs a finished row into a working row. Row 0 is empty.
    void orRowInto( std::uint32_t row, FileWorkRow& work ) const { s_.orRowInto( row, work ); }

    void setRow( std::uint32_t file, std::uint32_t row ) noexcept
    {
        ASSUME( file < s_.rowOfFile_.size() && row < s_.rowCount_ );
        s_.rowOfFile_[file] = row;
    }

    // An estimate, so a growing array never holds its old and new copies at once: that doubling, not the store, was the
    // peak on a large graph. The caller clamps it (fileSetReservePlan); an allocation the OS refuses is no reserve at all.
    void reserve( std::size_t rows, std::size_t chunks, std::size_t words ) noexcept
    {
        try
        {
            s_.heads_.reserve( rows * s_.headWords_ );
            s_.chunkOff_.reserve( chunks + 1 );
            s_.words_.reserve( words );
        }
        catch( const std::bad_alloc& )
        {
            DISCLOSE( Diagnostics::answerUnchanged, "fileSetStore: the reserve was refused, so the arrays grow by doubling; the rows are the same" );
        }
    }

    bool          overflowed() const noexcept { return overflowed_; }
    std::size_t   payloadWords() const noexcept { return s_.words_.size(); }
    std::uint32_t rowCount() const noexcept { return s_.rowCount_; }

    // No shrink_to_fit: it would hold two copies at the peak, to return pages that were never touched.
    FileSetStore finish()
    {
        firstRowOfHash_ = {};
        scratch_        = {};
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
        if( off + std::min<std::size_t>( card, bw ) > wordLimit_ )
        {
            DISCLOSE( Diagnostics::answerRefused, "fileSetStore: the payload would pass a 32-bit chunk offset — the row is rolled back, the fold stops" );
            overflowed_ = true;
            return;
        }
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
        // off + bw <= wordLimit_ <= 2^32 - 1 was checked above, so this cast cannot wrap.
        s_.chunkOff_.push_back( std::uint32_t( s_.words_.size() ) );
    }

    void rollBackRow()
    {
        s_.words_.resize( s_.chunkOff_[std::uint32_t( s_.heads_[rowStart_] >> 32 )] );
        s_.chunkOff_.resize( std::size_t( s_.heads_[rowStart_] >> 32 ) + 1 );
        s_.heads_.resize( rowStart_ );
    }

    std::uint32_t endRow( std::uint32_t card )
    {
        if( overflowed_ )
        {
            rollBackRow();
            return 0;
        }
        s_.heads_[rowStart_] |= card;
        const std::uint32_t row = s_.rowCount_;
        auto [ it, fresh ]      = firstRowOfHash_.try_emplace( hash_ & hashMask_, row );
        if( !fresh && sameAsRow( it->second ) )
        {
            rollBackRow();
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
    std::uint64_t                                              hashMask_;
    std::uint64_t                                              wordLimit_;
    bool                                                       overflowed_ = false;
};

// The chunk size with the fewest bytes for a set of sample rows, and what that size costs the sample. Candidates, widest
// first; a tie keeps the wider. Deterministic: a pure function of the sample.
struct FileSetChunkChoice
{
    std::uint32_t bits   = 16;
    std::size_t   chunks = 0;
    std::size_t   words  = 0;
};

inline FileSetChunkChoice fileSetChooseChunkBits( std::span<const std::vector<std::uint32_t>> sample, std::uint32_t universe ) noexcept
{
    static constexpr std::uint32_t kCandidates[] = { 16, 12, 10, 8 };
    FileSetChunkChoice             best;
    std::size_t                    bestBytes = ~std::size_t( 0 );
    for( const std::uint32_t bits : kCandidates )
    {
        const std::uint32_t highs  = universe == 0 ? 1 : ( ( universe - 1 ) >> bits ) + 1;
        std::size_t         chunks = 0, words = 0;
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
                words += std::min( j - i, std::size_t( ( width + 15 ) / 16 ) );
                ++chunks;
                i = j;
            }
        }
        const std::size_t bytes = std::size_t( 1 + ( highs + 63 ) / 64 ) * 8 * sample.size() + chunks * 4 + words * 2;
        if( bytes < bestBytes )
        {
            bestBytes = bytes;
            best      = { bits, chunks, words };
        }
    }
    return best;
}

// What the fold did, for reports and gates. `stop` is None unless the fold gave up: then the store is PARTIAL (the rows of
// the components not yet folded are empty) and must not be answered from.
struct FileClosureStats
{
    std::uint32_t sccs          = 0;
    std::size_t   workPeakBytes = 0;   // the working row and its touched list: one row, whatever the graph
    std::size_t   reservedWords = 0;   // payload words reserved up front, after the clamp
    std::uint32_t checks        = 0;   // how many times the stop callback was asked
    FileGraphStop stop          = FileGraphStop::None;
};

// Options for buildFileClosure. All default to the production behaviour; the rest are seams for tests and callers.
struct FileClosureOptions
{
    std::uint32_t      chunkBits = 0;                                              // != 0 forces the chunk size (tests); else sampled
    FileClosureStats*  stats     = nullptr;
    bool             (*shouldStop)() noexcept = nullptr;                           // asked every checkEvery folded components, or every kFoldCheckWords of new payload
    std::uint32_t      checkEvery = 4096;                                          // kFoldCheckComponents; 1 for the memory guard's fold seam
    std::uint64_t      hashMask  = ~std::uint64_t( 0 );                            // test seam: forces row-hash collisions (FileSetBuilder)
    std::uint64_t      wordLimit = std::numeric_limits<std::uint32_t>::max();      // test seam: the payload size a u32 chunk offset can address
};

// Strongly connected components, sinks first: order[ start[c] .. start[c + 1] ) are component c's files.
struct FileComponents
{
    std::vector<std::uint32_t> compOf, order, start;
    std::uint32_t              count() const noexcept { return std::uint32_t( start.size() - 1 ); }
};

// Tarjan, iterative: no recursion on any thread. Runs in file-id order, so it is a pure function of `adj`.
template <class Adj>
inline FileComponents fileComponents( const Adj& adj )
{
    static constexpr std::uint32_t kNone = ~std::uint32_t( 0 );
    const std::uint32_t            F     = std::uint32_t( adj.size() );
    FileComponents                 c;
    c.compOf.assign( F, kNone );
    std::vector<std::uint32_t> index( F, 0 ), low( F, 0 ), edgePos( F, 0 ), onStack, callStack;
    std::uint32_t              counter = 0;
    const auto                 enter   = [ & ]( std::uint32_t v )
    {
        index[v] = low[v] = ++counter;
        onStack.push_back( v );
        callStack.push_back( v );
    };
    const auto leave = [ & ]( std::uint32_t v )
    {
        if( !callStack.empty() )
        {
            low[callStack.back()] = std::min( low[callStack.back()], low[v] );
        }
        if( low[v] != index[v] )
        {
            return;
        }
        const std::uint32_t id = std::uint32_t( c.start.size() );
        c.start.push_back( std::uint32_t( c.order.size() ) );
        std::uint32_t w = kNone;
        do
        {
            w = onStack.back();
            onStack.pop_back();
            c.compOf[w] = id;
            c.order.push_back( w );
        } while( w != v );
    };
    for( std::uint32_t r = 0; r < F; ++r )
    {
        if( index[r] != 0 )
        {
            continue;
        }
        enter( r );
        while( !callStack.empty() )
        {
            const std::uint32_t v   = callStack.back();
            const auto&         row = adj[v];
            if( edgePos[v] == row.size() )
            {
                callStack.pop_back();
                leave( v );
                continue;
            }
            const std::uint32_t w = row[edgePos[v]++];
            if( w < F && index[w] == 0 )
            {
                enter( w );
            }
            else if( w < F && c.compOf[w] == kNone )
            {
                low[v] = std::min( low[v], index[w] );
            }
        }
    }
    c.start.push_back( F );
    return c;
}

// Up to 64 files with an edge, at a fixed stride, walked once each; what each candidate costs them is arithmetic.
template <class Adj>
inline std::vector<std::vector<std::uint32_t>> fileClosureSample( const Adj& adj )
{
    const std::uint32_t                     F = std::uint32_t( adj.size() );
    std::vector<std::vector<std::uint32_t>> sample;
    std::vector<std::uint32_t>              seen( F, ~std::uint32_t( 0 ) ), stack;
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
    return sample;
}

// True when component `k` reaches anything: it is a cycle, or one of its files has an edge leaving it.
template <class Adj>
inline bool fileComponentReaches( const Adj& adj, const FileComponents& c, std::uint32_t k )
{
    const std::uint32_t a = c.start[k], z = c.start[k + 1];
    if( z - a > 1 )
    {
        return true;
    }
    const std::uint32_t F = std::uint32_t( adj.size() );
    return std::ranges::any_of( adj[c.order[a]], [ & ]( std::uint32_t w ) { return w < F && c.compOf[w] != k; } );
}

// How much to reserve up front, from a sample of rows scaled to the rows the fold will really store. Sharing is why the scale
// is the number of components that reach something, not the number of files: one giant cycle is one row at any size. Every
// term is clamped, since an estimate must never be able to abort a tree that fits: rows by what could exist, the payload by a
// fixed ceiling past which the arrays simply grow by doubling.
struct FileSetReservePlan
{
    std::size_t rows = 0, chunks = 0, words = 0;
};
inline constexpr std::size_t kReserveMaxChunks = std::size_t( 1 ) << 27;   // 512 MiB of u32 offsets, address space only
inline constexpr std::size_t kReserveMaxWords  = std::size_t( 1 ) << 30;   // 2 GiB of u16 payload, address space only: a 100,000-file chain stores 654 MB

inline FileSetReservePlan fileSetReservePlan( const FileSetChunkChoice& sample, std::size_t sampleRows, std::size_t reachingComps ) noexcept
{
    FileSetReservePlan plan;
    plan.rows = reachingComps + 1;
    if( sampleRows == 0 )
    {
        return plan;
    }
    // mean per sample row x rows to store, plus a quarter, since the sample can run light
    const auto scaled = [ & ]( std::size_t perSample ) { return std::size_t( ( double( perSample ) / double( sampleRows ) ) * double( reachingComps ) * 1.25 ) + 1; };
    plan.chunks = std::min( scaled( sample.chunks ), kReserveMaxChunks );
    plan.words  = std::min( scaled( sample.words ), kReserveMaxWords );
    return plan;
}

// How often the fold asks `shouldStop`: every this many folded components, or when this much payload was added, whichever
// first. A footprint reading is one syscall; both are far apart enough that its cost is below the noise (bench/FILEGRAPH.md).
inline constexpr std::uint32_t kFoldCheckComponents = 4096;
inline constexpr std::size_t   kFoldCheckWords      = std::size_t( 1 ) << 21;   // 4 MiB of payload

// The transitive closure: for each file, every file it reaches over >= 1 edge, never itself. `adj` needs size() and
// operator[] giving a range of u32; duplicate ids, self edges and ids >= adj.size() are tolerated and contribute nothing.
//
// A fold over the strongly connected components, sinks first: a component's row is the OR of its successors' rows plus their
// ids, so each edge costs the successor's row, whatever the closure's size, where a walk per file costs the closure's size per
// file. Each finished row goes into the store at once, and a successor's row is ORed back from there, so the fold holds ONE
// working row, not a frontier that grows with a file's fan-out (an umbrella file importing 40,000 modules held 40,000
// bitsets in the first form). A component's members share one row, which holds them all when the component is a cycle.
//
// The result is a pure function of `adj`; the row a file gets is decided by its set alone.
//
// The fold can GIVE UP, and says so in opts.stats->stop: the memory callback asked it to (options.shouldStop), a payload offset
// would have passed 32 bits, or an allocation failed. The returned store is then partial; the caller must not answer from it.
template <class Adj>
inline FileSetStore buildFileClosure( const Adj& adj, const FileClosureOptions& opts = {} )
{
    const std::uint32_t  F     = std::uint32_t( adj.size() );
    const FileComponents comps = [ & ]
    {
        PROFILE_SCOPE_DESCRIBE( "closure/1 strongly connected components (Tarjan)" );
        return fileComponents( adj );
    }();
    const std::uint32_t C = comps.count();
    FileClosureStats    local;
    FileClosureStats&    st = opts.stats != nullptr ? *opts.stats : local;
    st                      = FileClosureStats{};
    st.sccs                 = C;

    std::uint32_t reaching = 0;
    {
        PROFILE_SCOPE_DESCRIBE( "closure/2 components that reach something (the reserve's scale)" );
        for( std::uint32_t k = 0; k < C; ++k )
        {
            reaching += fileComponentReaches( adj, comps, k ) ? 1 : 0;
        }
    }

    try
    {
        std::uint32_t      chunkBits = opts.chunkBits;
        FileSetChunkChoice choice;
        std::size_t        sampleRows = 0;
        if( chunkBits == 0 )
        {
            PROFILE_SCOPE_DESCRIBE( "closure/3 chunk-size sample (walks <= 64 files, scores 4 sizes)" );
            const std::vector<std::vector<std::uint32_t>> sample = fileClosureSample( adj );
            choice     = fileSetChooseChunkBits( sample, F );
            chunkBits  = choice.bits;
            sampleRows = sample.size();
        }
        FileSetBuilder b( F, F, chunkBits, opts.hashMask, opts.wordLimit );
        if( sampleRows != 0 )
        {
            const FileSetReservePlan plan = fileSetReservePlan( choice, sampleRows, reaching );
            b.reserve( plan.rows, plan.chunks, plan.words );
            st.reservedWords = plan.words;
        }

        PROFILE_SCOPE_DESCRIBE( "closure/4 fold over the components, sinks first (includes 4a-4c)" );
        FileWorkRow                work( F );
        std::vector<std::uint32_t> rowOfComp( C, 0 ), mergedInto( std::size_t( reaching ) + 2, 0 );
        std::uint32_t              sinceCheck = 0;
        std::size_t                wordsAtCheck = 0;
        for( std::uint32_t k = 0; k < C; ++k )
        {
            if( !fileComponentReaches( adj, comps, k ) )
            {
                continue;   // a sink with no cycle: stays on the shared empty row
            }
            const std::uint32_t a = comps.start[k], z = comps.start[k + 1];
            for( std::uint32_t i = a; i < z; ++i )
            {
                const std::uint32_t v = comps.order[i];
                if( z - a > 1 )
                {
                    work.set( v );
                }
                for( const std::uint32_t w : adj[v] )
                {
                    if( w >= F || comps.compOf[w] == k )
                    {
                        continue;
                    }
                    work.set( w );
                    const std::uint32_t r = rowOfComp[comps.compOf[w]];
                    if( r != 0 && mergedInto[r] != k + 1 )
                    {
                        mergedInto[r] = k + 1;   // the same row twice (a diamond, a shared row) adds nothing
                        PROFILE_SCOPE_DESCRIBE( "closure/4a row decode + OR (a stored successor row into the working row)" );
                        b.orRowInto( r, work );
                    }
                }
            }
            std::uint32_t row = 0;
            {
                PROFILE_SCOPE_DESCRIBE( "closure/4b row compression (working row -> ids -> hash, verify, store)" );
                row = b.addWork( work );
            }
            if( b.overflowed() )
            {
                st.stop = FileGraphStop::Capacity;
                break;
            }
            for( std::uint32_t i = a; i < z; ++i )
            {
                b.setRow( comps.order[i], row );
            }
            rowOfComp[k] = row;
            if( opts.shouldStop != nullptr && ( ++sinceCheck >= std::max( opts.checkEvery, std::uint32_t( 1 ) ) || b.payloadWords() - wordsAtCheck >= kFoldCheckWords ) )
            {
                sinceCheck   = 0;
                wordsAtCheck = b.payloadWords();
                ++st.checks;
                PROFILE_SCOPE_DESCRIBE( "closure/4c memory check (one footprint reading)" );
                if( opts.shouldStop() )
                {
                    st.stop = FileGraphStop::MemoryLimit;
                    break;
                }
            }
        }
        st.workPeakBytes = work.bytes();
        return b.finish();
    }
    catch( const std::bad_alloc& )
    {
        DISCLOSE( Diagnostics::answerRefused, "fileSetStore: an allocation failed in the closure fold — the caller stops, no answer from a partial store" );
        st.stop = FileGraphStop::AllocFailure;
        return FileSetStore();
    }
}

} // namespace rw

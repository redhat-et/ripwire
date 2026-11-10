#pragma once
// internedtext.h — MEM-REF-SHRINK step 2: a reference's NAME texts (Reference::calleeName / qualifier / recvVar, RawRef::name /
// qualifier / recvVar) as a 4 B id into ONE process-wide, append-only text pool instead of a 24 B (libc++) / 32 B (libstdc++)
// std::string header each. Step 1's Stage 0 counts (reports/mem-ref-shrink.md): 59-116 K distinct callee names over 1.2-2.0 M
// references on envoy / cockroach / vscode, and two row copies live at the parse-pool peak, so the header bytes, not the text, are
// the cost.
//
// WHY ONE POOL, NOT PER-THREAD TABLES REMAPPED AT MERGE. Most readers hold only a `const Reference&` (no IngestResult, no table),
// and the parse workers both write and READ their RawRefs' names while they extract (erase_if passes, suffix tests, re-splits). A
// per-thread table would need a thread-local "current table" for every one of those reads, a remap pass over every row at the
// parse-pool join, a second one for cache-hit rows, and a rule for rows copied between results. One shared pool needs none: an id
// means the same text in every thread for the life of the process, so a row moves, copies and merges as four plain bytes.
//
// DETERMINISM. Ids are assigned in first-intern order, which depends on thread timing, so an id must never reach output, an order
// or a hash. That is enforced by the type, not by convention: InternedText exposes no id; ordering is the TEXT's
// (operator<=>), and equality of two InternedTexts is id equality only because interning is canonical (one text, one id), which
// gives exactly the text answer. No std::hash is provided, so a hash container keyed by one must name its text.
//
// THREADING. intern() takes one of kShards mutexes (picked by the text's hash), so two threads interning the same text serialise
// and get the same id. text() takes no lock: slots live in segments that never move or shrink (segment k holds kFirst << k
// slots), a slot is written once, before its id is published under the shard lock, and every reader got the id from that lock
// or from a row handed across a thread join. A segment pointer is published with a release CAS and read with acquire.
//
// LIFETIME. The pool lives for the process and never frees a text: a long-running server keeps every name it has interned, which is
// bounded by the distinct names of the trees it indexed (about 3 MB of headers per 100 K names), not by the rows.

#include <atomic>
#include <bit>
#include <compare>
#include <cstddef>
#include <cstdint>
#include <format>
#include <mutex>
#include <string>
#include <string_view>
#include <vector>

#include "unordered_dense.h"   // ankerl::unordered_dense::hash<std::string_view> — the pool's text hash

namespace rw
{

class TextPool
{
public:
    static constexpr std::uint32_t kEmptyId = 0;   // the empty text: no slot, no lock, no hash

    constexpr TextPool() noexcept = default;
    TextPool( const TextPool& )            = delete;
    TextPool& operator=( const TextPool& ) = delete;
    ~TextPool()
    {
        for( std::size_t seg = 0; seg < kSegments; ++seg )
        {
            delete[] segments_[ seg ].load( std::memory_order_relaxed );
        }
    }

    std::uint32_t intern( std::string_view text )
    {
        if( text.empty() )
        {
            return kEmptyId;
        }
        const std::uint64_t hash  = ankerl::unordered_dense::hash<std::string_view>{}( text );
        Shard&              shard = shards_[ hash >> ( 64 - kShardBits ) ];
        const std::uint32_t tag   = std::uint32_t( hash );
        std::lock_guard     lock( shard.mutex );
        if( 2 * ( shard.used + 1 ) > shard.slots.size() )
        {
            growShard( shard );
        }
        const std::size_t mask = shard.slots.size() - 1;
        for( std::size_t probe = tag & mask;; probe = ( probe + 1 ) & mask )
        {
            Slot& slot = shard.slots[ probe ];
            if( slot.id == kEmptyId )
            {
                const std::uint32_t id = next_.fetch_add( 1, std::memory_order_relaxed );
                makeSlot( id ) = std::string( text );
                slot = { tag, id };
                ++shard.used;
                return id;
            }
            if( slot.tag == tag && this->text( slot.id ) == text )
            {
                return slot.id;
            }
        }
    }

    const std::string& text( std::uint32_t id ) const noexcept
    {
        if( id == kEmptyId )
        {
            return emptyText_;
        }
        const auto [ seg, offset ] = locate( id );
        return segments_[ seg ].load( std::memory_order_acquire )[ offset ];
    }

private:
    static constexpr std::uint32_t kFirst     = 4096;   // segment 0's slots; segment k holds kFirst << k
    static constexpr std::size_t   kSegments  = 20;     // ~4.3 G slots: past any u32 id the counter can hand out in practice
    static constexpr unsigned      kShardBits = 6;
    struct Slot
    {
        std::uint32_t tag = 0;          // the low 32 bits of the text's hash: most probes stop here
        std::uint32_t id  = kEmptyId;   // kEmptyId = a free slot (no text is interned under it)
    };
    struct Shard
    {
        std::mutex        mutex;
        std::vector<Slot> slots;   // open addressing, linear probe, a power of two at most half full
        std::size_t       used = 0;
    };

    static void growShard( Shard& shard )
    {
        std::vector<Slot> grown( shard.slots.empty() ? 64 : 2 * shard.slots.size() );
        const std::size_t mask = grown.size() - 1;
        for( const Slot& slot : shard.slots )
        {
            if( slot.id != kEmptyId )
            {
                std::size_t probe = slot.tag & mask;
                while( grown[ probe ].id != kEmptyId )
                {
                    probe = ( probe + 1 ) & mask;
                }
                grown[ probe ] = slot;
            }
        }
        shard.slots.swap( grown );
    }

    // id 1 is the first text (0 is the empty one); slot index = id - 1. Segment k covers indices [kFirst*(2^k - 1), kFirst*(2^(k+1) - 1)).
    struct SlotPlace
    {
        unsigned    seg;
        std::size_t offset;
    };
    static SlotPlace locate( std::uint32_t id ) noexcept
    {
        const std::uint64_t index = std::uint64_t( id ) - 1;
        const unsigned      seg   = unsigned( std::bit_width( index / kFirst + 1 ) ) - 1;
        return { seg, std::size_t( index - std::uint64_t( kFirst ) * ( ( std::uint64_t( 1 ) << seg ) - 1 ) ) };
    }
    // The slot a NEW id's text goes in, making its segment on the first id that lands there (a release CAS: another shard's
    // first intern may race for the same segment, and the loser frees its copy).
    std::string& makeSlot( std::uint32_t id )
    {
        const auto [ seg, offset ] = locate( id );
        std::string* base = segments_[ seg ].load( std::memory_order_acquire );
        if( base == nullptr )
        {
            std::string* fresh = new std::string[ std::size_t( kFirst ) << seg ];
            if( segments_[ seg ].compare_exchange_strong( base, fresh, std::memory_order_acq_rel, std::memory_order_acquire ) )
            {
                base = fresh;
            }
            else
            {
                delete[] fresh;
            }
        }
        return base[ offset ];
    }

    std::atomic<std::string*>  segments_[ kSegments ] = {};
    std::atomic<std::uint32_t> next_{ 1 };
    Shard                      shards_[ std::size_t( 1 ) << kShardBits ];
    std::string                emptyText_;
};

// The one pool every reference name lives in. The constexpr constructor makes it constant-initialised (no guard on the read path,
// built before any dynamic initialiser could intern); `constinit` is not spelled because MSVC's STL made std::mutex's constructor
// constexpr only recently.
inline TextPool gRefTextPool;

// A reference name: 4 B, read like a const std::string, assigned from any text. No mutation in place: an edit builds the new text
// and assigns it (`r.qualifier = std::string( r.qualifier ) + "::x"`). See the DETERMINISM note above for why no id is exposed.
class InternedText
{
public:
    InternedText() noexcept = default;
    explicit InternedText( std::string_view text ) : id_( gRefTextPool.intern( text ) ) {}   // explicit: no text converts to a name behind a comparison
    InternedText& operator=( std::string_view text )
    {
        id_ = gRefTextPool.intern( text );
        return *this;
    }
    InternedText& operator=( const std::string& text ) { return *this = std::string_view( text ); }
    InternedText& operator=( const char* text ) { return *this = std::string_view( text ); }
    InternedText& assign( std::string_view text ) { return *this = text; }
    // The edits a writer makes build the new text and intern it (the pool's texts never change): same result as std::string's.
    InternedText& operator+=( std::string_view tail ) { return *this = std::string( str() ).append( tail ); }
    InternedText& operator+=( char tail ) { return *this = std::string( str() ) + tail; }
    void          push_back( char tail ) { *this += tail; }

    const std::string& str() const noexcept { return gRefTextPool.text( id_ ); }
    operator const std::string&() const noexcept { return str(); }
    operator std::string_view() const noexcept { return str(); }

    bool        empty() const noexcept { return id_ == TextPool::kEmptyId; }
    std::size_t size() const noexcept { return str().size(); }
    std::size_t length() const noexcept { return str().size(); }
    const char* data() const noexcept { return str().data(); }
    const char* c_str() const noexcept { return str().c_str(); }
    char        operator[]( std::size_t i ) const noexcept { return str()[ i ]; }
    char        front() const noexcept { return str().front(); }
    char        back() const noexcept { return str().back(); }
    auto        begin() const noexcept { return str().begin(); }
    auto        end() const noexcept { return str().end(); }
    std::string substr( std::size_t pos = 0, std::size_t n = std::string::npos ) const { return str().substr( pos, n ); }
    template <class... Args> std::size_t find( Args&&... args ) const noexcept { return str().find( std::forward<Args>( args )... ); }
    template <class... Args> std::size_t rfind( Args&&... args ) const noexcept { return str().rfind( std::forward<Args>( args )... ); }
    template <class... Args> std::size_t find_first_of( Args&&... args ) const noexcept { return str().find_first_of( std::forward<Args>( args )... ); }
    template <class... Args> std::size_t find_last_of( Args&&... args ) const noexcept { return str().find_last_of( std::forward<Args>( args )... ); }
    template <class... Args> std::size_t find_first_not_of( Args&&... args ) const noexcept { return str().find_first_not_of( std::forward<Args>( args )... ); }
    template <class... Args> std::size_t find_last_not_of( Args&&... args ) const noexcept { return str().find_last_not_of( std::forward<Args>( args )... ); }
    template <class Arg> bool starts_with( Arg&& a ) const noexcept { return str().starts_with( std::forward<Arg>( a ) ); }
    template <class Arg> bool ends_with( Arg&& a ) const noexcept { return str().ends_with( std::forward<Arg>( a ) ); }
    template <class Arg> bool contains( Arg&& a ) const noexcept { return std::string_view( str() ).find( std::forward<Arg>( a ) ) != std::string_view::npos; }
    template <class... Args> int compare( Args&&... args ) const noexcept { return str().compare( std::forward<Args>( args )... ); }
    void clear() noexcept { id_ = TextPool::kEmptyId; }

    friend std::string operator+( std::string lhs, const InternedText& rhs ) { return lhs.append( rhs.str() ); }
    friend std::string operator+( const InternedText& lhs, std::string_view rhs ) { return std::string( lhs.str() ).append( rhs ); }
    friend std::string operator+( const InternedText& lhs, const InternedText& rhs ) { return lhs + std::string_view( rhs.str() ); }
    friend std::string operator+( const InternedText& lhs, char rhs ) { return std::string( lhs.str() ) + rhs; }

    friend bool operator==( const InternedText& a, const InternedText& b ) noexcept { return a.id_ == b.id_; }   // canonical: same text, same id
    friend bool operator==( const InternedText& a, std::string_view b ) noexcept { return std::string_view( a.str() ) == b; }
    friend std::strong_ordering operator<=>( const InternedText& a, const InternedText& b ) noexcept
    {
        return a.id_ == b.id_ ? std::strong_ordering::equal : std::string_view( a.str() ) <=> std::string_view( b.str() );
    }
    friend std::strong_ordering operator<=>( const InternedText& a, std::string_view b ) noexcept { return std::string_view( a.str() ) <=> b; }

private:
    std::uint32_t id_ = TextPool::kEmptyId;
};
static_assert( sizeof( InternedText ) == 4, "a reference name is one u32 id: the whole point of the pool" );

}   // namespace rw

template <> struct std::formatter<rw::InternedText, char> : std::formatter<std::string_view, char>
{
    auto format( const rw::InternedText& t, std::format_context& ctx ) const { return std::formatter<std::string_view, char>::format( t.str(), ctx ); }
};

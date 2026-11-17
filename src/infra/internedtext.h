#pragma once
// internedtext.h — a text as a 4 B id into an append-only, thread-safe text pool (TextPool), and InternedTextOf<Domain>, a
// string-like value that holds one. A host picks one process-wide pool per Domain (a type with `static TextPool& pool()`); the
// pool's texts are never freed while the process runs, so a row that carries an id moves, copies and merges as four plain bytes.
//
// DETERMINISM. Ids are assigned in first-intern order, which depends on thread timing, so an id must never reach output, an order
// or a hash. That is enforced by the type, not by convention: InternedTextOf exposes no id; ordering is the TEXT's (operator<=>),
// and equality of two values is id equality only because interning is canonical (one text, one id), which gives exactly the text
// answer. No std::hash is provided, so a hash container keyed by one must name its text. The one named escape hatch (owner 11-11,
// K1 option (a)) is infra/idkeyedmap.h's IdKeyedMap: a friend that hashes the id, and has no iteration API, so the id-dependent
// slot order can never be observed (test/textpoolcheck.sh arm N holds that).
//
// THREADING. intern() takes one of kShards mutexes (picked by the text's hash), so two threads interning the same text serialise
// and get the same id. text() takes no lock: slots live in segments that never move or shrink (segment k holds kFirst << k
// slots), a slot is written once, before its id is published under the shard lock, and every reader got the id from that lock
// or from a row handed across a thread join. A segment pointer is published with a release CAS and read with acquire: the formal
// guarantee for a reader that reaches an id some other way. No gate observes that ordering (the shard locks order every access a
// test can make). Each shard and the id counter sit on their own destructive-interference line: shards packed two to a line
// bounced lock lines between threads (measured: flat instructions, more cycles).
//
// LIFETIME. A host's process-wide pool must outlive every thread that can intern, including a DETACHED one still running when main
// returns: hold it in NoDestroy (below), which keeps constant initialisation and never runs the destructor. TextPool's own
// destructor frees its segments, for a pool with a scope (a test's). The pool grows with the distinct texts interned, never shrinks.

#include <atomic>
#include <bit>
#include <compare>
#include <cstddef>
#include <cstdint>
#include <format>
#include <memory>   // std::construct_at / std::destroy_at: a segment's slots are constructed one id at a time (NIT-7)
#include <mutex>
#include <new>      // ::operator new / delete: a segment is raw storage
#include <optional>  // InternedTextOf::ifInterned
#include <string>
#include <string_view>
#include <vector>

#include "Diagnostics.h"     // EXPECTS / DASSERT / PANIC — intern's preconditions and the pool's capacity
#include "sortutil.h"        // rw::sortutil::svCompare — <=> without libstdc++'s wrapping size subtraction
#include "platform.h"        // infra::platform::hardware_destructive_interference_size — one shard per line
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
    // Every id below next_ has its slot constructed (makeSlot runs under the shard lock that hands the id out), and a pool with a
    // scope is destroyed after its last interning thread joined: destroy those slots, then free each raw segment.
    ~TextPool()
    {
        const std::uint32_t end = next_.load( std::memory_order_relaxed );
        for( std::uint32_t id = 1; id < end && id <= kCapacity; ++id )
        {
            const auto [ seg, offset ] = locate( id );
            std::destroy_at( segments_[ seg ].load( std::memory_order_relaxed ) + offset );
        }
        for( std::size_t seg = 0; seg < kSegments; ++seg )
        {
            ::operator delete( segments_[ seg ].load( std::memory_order_relaxed ) );
        }
    }

    static std::uint64_t hashOf( std::string_view text ) noexcept { return ankerl::unordered_dense::hash<std::string_view>{}( text ); }

    std::uint32_t intern( std::string_view text ) { return text.empty() ? kEmptyId : intern( text, hashOf( text ) ); }

    // For a caller that already hashed the text (internCached's front cache). Preconditions: `text` is non-empty and `hash` is
    // exactly hashOf( text ); a wrong hash would give one text two ids and break canonicality (and so == and determinism).
    std::uint32_t intern( std::string_view text, std::uint64_t hash )
    {
        EXPECTS( !text.empty() );
        DASSERT( hash == hashOf( text ) );
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
                if( id == kEmptyId || id > kCapacity ) [[unlikely]]
                {
                    PANIC( "text pool full: more than kCapacity distinct texts" );   // ~4.29 G texts (100+ GB): no row can hold a past-the-end id
                }
                std::construct_at( makeSlot( id ), text );   // NIT-7: constructed here, under this shard's lock
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

    // The id `text` already has, kAbsentId when no one interned it — never inserts (a lookup key that was never interned names
    // nothing a table built from interned texts can hold). Takes the shard lock, as intern does: a reader racing an intern of the
    // same text sees it or not, and either answer is one the pool gave at some instant.
    static constexpr std::uint32_t kAbsentId = 0xFFFFFFFFu;   // past kCapacity: never an id
    std::uint32_t lookup( std::string_view text, std::uint64_t hash ) const
    {
        DASSERT( !text.empty() && hash == hashOf( text ) );
        const Shard&        shard = shards_[ hash >> ( 64 - kShardBits ) ];
        const std::uint32_t tag   = std::uint32_t( hash );
        std::lock_guard     lock( shard.mutex );
        if( shard.slots.empty() )
        {
            return kAbsentId;
        }
        const std::size_t mask = shard.slots.size() - 1;
        for( std::size_t probe = tag & mask;; probe = ( probe + 1 ) & mask )
        {
            const Slot& slot = shard.slots[ probe ];
            if( slot.id == kEmptyId )
            {
                return kAbsentId;   // a shard is at most half full: a probe always reaches a free slot
            }
            if( slot.tag == tag && this->text( slot.id ) == text )
            {
                return slot.id;
            }
        }
    }

    // how many distinct texts the pool holds (ids handed out so far; the empty text is none of them); a host stats line reads it
    std::uint32_t idCount() const noexcept { return next_.load( std::memory_order_relaxed ) - 1; }

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
    static constexpr std::size_t   kSegments  = 20;
    static constexpr std::uint64_t kCapacity  = std::uint64_t( kFirst ) * ( ( std::uint64_t( 1 ) << kSegments ) - 1 );   // 4,294,963,200 ids
    static_assert( kCapacity < std::uint64_t( 1 ) << 32, "every slot has a u32 id; the counter's wrap (to kEmptyId) is past the end too" );
    static constexpr unsigned      kShardBits = 6;
    static constexpr std::size_t   kLine      = infra::platform::hardware_destructive_interference_size;
    struct Slot
    {
        std::uint32_t tag = 0;          // the low 32 bits of the text's hash: most probes stop here
        std::uint32_t id  = kEmptyId;   // kEmptyId = a free slot (no text is interned under it)
    };
    struct alignas( kLine ) Shard   // one shard per destructive-interference line: no false sharing between shards' locks
    {
        mutable std::mutex mutex;   // lookup (const) locks it too
        std::vector<Slot>  slots;   // open addressing, linear probe, a power of two at most half full
        std::size_t       used = 0;
    };
    // alignas( kLine ) is the no-false-sharing guarantee: no two shards share a line on any platform. One shard fits ONE line
    // only where the line is 128 B (ARM, where the bounce was measured); on x86 (64 B) libstdc++'s 40 B std::mutex + the
    // vector + used = 72 B, and MSVC's mutex is fatter, so a shard takes two lines of its own there (#608 CI). A shard past
    // two lines means a much fatter mutex: re-measure the bounce.
    static_assert( sizeof( Shard ) % kLine == 0 && sizeof( Shard ) <= 2 * kLine, "a Shard outgrew two lines (a fatter std::mutex?): re-measure the bounce" );

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
    // The RAW slot a NEW id's text is constructed in, making its segment on the first id that lands there (a release CAS: another
    // shard's first intern may race for the same segment, and the loser frees its copy). NIT-7 (MEM-R1c): the segment is raw
    // storage and intern constructs each slot, under the shard lock that hands out its id, so a segment's untouched tail stays
    // untouched (`new std::string[ n ]` constructed, and so wrote, all of segment k's kFirst << k slots at its first id: 6 MiB at
    // segment 6). Nothing reads a slot before its id is published, and the destructor destroys exactly the ids below next_.
    std::string* makeSlot( std::uint32_t id )
    {
        const auto [ seg, offset ] = locate( id );
        std::string* base = segments_[ seg ].load( std::memory_order_acquire );
        if( base == nullptr )
        {
            std::string* fresh = static_cast<std::string*>( ::operator new( sizeof( std::string ) * ( std::size_t( kFirst ) << seg ) ) );
            if( segments_[ seg ].compare_exchange_strong( base, fresh, std::memory_order_acq_rel, std::memory_order_acquire ) )
            {
                base = fresh;
            }
            else
            {
                ::operator delete( fresh );
            }
        }
        return base + offset;
    }

    std::atomic<std::string*>  segments_[ kSegments ] = {};
    alignas( kLine ) std::atomic<std::uint32_t> next_{ 1 };
    Shard                      shards_[ std::size_t( 1 ) << kShardBits ];
    std::string                emptyText_;
};

// A value that is constructed (constant-initialised when T's constructor is constexpr) and never destroyed: a process-wide pool
// must outlive every thread that can still use it, including a detached one running while static destructors run. Its storage
// stays reachable from the global, so LeakSanitizer does not report it.
template <class T> union NoDestroy
{
    T value;
    constexpr NoDestroy() : value() {}
    ~NoDestroy() {}
    NoDestroy( const NoDestroy& )            = delete;
    NoDestroy& operator=( const NoDestroy& ) = delete;
};

// Domain::pool().intern (kInsert) or .lookup behind a per-thread, direct-mapped front cache of the ids this thread got last: when
// texts repeat, a hit skips the shard lock. A hit is proven, not guessed: the cached id's text must equal `text`. Every cached id
// came from the same pool on this thread, so its slot was published to this thread under the shard lock (the read is race-free).
// Each instantiation has its own cache. A lookup caches only hits: a text interned later is found by the next miss.
template <class Domain, bool kInsert> std::uint32_t frontCached( std::string_view text )
{
    if( text.empty() )
    {
        return TextPool::kEmptyId;
    }
    struct FrontSlot
    {
        std::uint32_t tag = 0;
        std::uint32_t id  = TextPool::kEmptyId;
    };
    constexpr std::size_t kFrontSlots = 512;   // 4 KB per thread
    thread_local FrontSlot front[ kFrontSlots ];
    TextPool&           pool = Domain::pool();
    const std::uint64_t hash = TextPool::hashOf( text );
    FrontSlot&          slot = front[ hash & ( kFrontSlots - 1 ) ];
    const std::uint32_t tag  = std::uint32_t( hash >> 32 );
    if( slot.id != TextPool::kEmptyId && slot.tag == tag && std::string_view( pool.text( slot.id ) ) == text )
    {
        return slot.id;
    }
    const std::uint32_t id = kInsert ? pool.intern( text, hash ) : pool.lookup( text, hash );
    if( id != TextPool::kAbsentId )
    {
        slot = { tag, id };
    }
    return id;
}
// Domain::pool().intern behind the front cache
template <class Domain> std::uint32_t internCached( std::string_view text ) { return frontCached<Domain, true>( text ); }
// The id `text` has in Domain's pool, TextPool::kAbsentId when it was never interned. Never inserts.
template <class Domain> std::uint32_t lookupCached( std::string_view text ) { return frontCached<Domain, false>( text ); }

template <class Domain, class V> class IdKeyedMap;   // infra/idkeyedmap.h: the one reader of an id (lookup-only, no iteration)

// A text in Domain's pool: 4 B, read like a const std::string, assigned from any text. No mutation in place: an edit builds the new
// text and assigns it. `+=` and push_back do that per call (copy, re-intern), so build a long text in a std::string and assign once.
// See the DETERMINISM note above for why no id is exposed.
template <class Domain> class InternedTextOf
{
public:
    InternedTextOf() noexcept = default;
    explicit InternedTextOf( std::string_view text ) : id_( internCached<Domain>( text ) ) {}   // explicit: no text converts to a name behind a comparison
    // The value `text` names when someone already interned it, nullopt otherwise; never inserts (a lookup by a name some table
    // may hold: an absent text cannot be one of its keys).
    static std::optional<InternedTextOf> ifInterned( std::string_view text )
    {
        const std::uint32_t id = lookupCached<Domain>( text );
        if( id == TextPool::kAbsentId )
        {
            return std::nullopt;
        }
        InternedTextOf found;
        found.id_ = id;
        return found;
    }
    InternedTextOf& operator=( std::string_view text )
    {
        id_ = internCached<Domain>( text );
        return *this;
    }
    InternedTextOf& operator=( const std::string& text ) { return *this = std::string_view( text ); }
    InternedTextOf& operator=( const char* text ) { return *this = std::string_view( text ); }
    InternedTextOf& assign( std::string_view text ) { return *this = text; }
    // The edits a writer makes build the new text and intern it (the pool's texts never change): same result as std::string's.
    InternedTextOf& operator+=( std::string_view tail ) { return *this = std::string( str() ).append( tail ); }
    InternedTextOf& operator+=( char tail ) { return *this = std::string( str() ) + tail; }
    void          push_back( char tail ) { *this += tail; }

    const std::string& str() const noexcept { return Domain::pool().text( id_ ); }
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
    void clear() noexcept { id_ = TextPool::kEmptyId; }

    friend std::string operator+( std::string lhs, const InternedTextOf& rhs ) { return lhs.append( rhs.str() ); }
    friend std::string operator+( const InternedTextOf& lhs, std::string_view rhs ) { return std::string( lhs.str() ).append( rhs ); }
    friend std::string operator+( const InternedTextOf& lhs, const InternedTextOf& rhs ) { return lhs + std::string_view( rhs.str() ); }
    friend std::string operator+( const InternedTextOf& lhs, char rhs ) { return std::string( lhs.str() ) + rhs; }

    friend bool operator==( const InternedTextOf& a, const InternedTextOf& b ) noexcept { return a.id_ == b.id_; }   // canonical: same text, same id
    friend bool operator==( const InternedTextOf& a, std::string_view b ) noexcept { return std::string_view( a.str() ) == b; }
    friend std::strong_ordering operator<=>( const InternedTextOf& a, const InternedTextOf& b ) noexcept
    {
        return a.id_ == b.id_ ? std::strong_ordering::equal : sortutil::svCompare( a.str(), b.str() );
    }
    // svCompare, not string_view's <=>: libstdc++'s computes `n1 - n2` on size_t, which the G1 integer sanitizer aborts on
    // (sortutil.h; #608's Linux ASan leg died in ValueRefWalk::leave's binary_search on 1 - 8).
    friend std::strong_ordering operator<=>( const InternedTextOf& a, std::string_view b ) noexcept { return sortutil::svCompare( a.str(), b ); }

private:
    template <class D, class V> friend class IdKeyedMap;   // the ONE reader of id_: a lookup-only table that never iterates
    std::uint32_t id_ = TextPool::kEmptyId;
};

// A pool id's VALUE depends on thread timing: a raw-bytes writer (a blob's POD put) must refuse one. Checked by quality.h qsnapPut.
template <class T> inline constexpr bool isPoolId = false;
template <class Domain> inline constexpr bool isPoolId<InternedTextOf<Domain>> = true;

}   // namespace rw

template <class Domain> struct std::formatter<rw::InternedTextOf<Domain>, char> : std::formatter<std::string_view, char>
{
    auto format( const rw::InternedTextOf<Domain>& t, std::format_context& ctx ) const { return std::formatter<std::string_view, char>::format( t.str(), ctx ); }
};

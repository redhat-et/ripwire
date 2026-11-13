#pragma once
// idkeyedmap.h — tables keyed by ( a u32 owner, an interned name ) on ONE packed u64: the owner in the high half, the name's pool
// id in the low (hashutil::packPair). K1 KEY-PACK option (a), owner 11-11: a string key "<owner>#<name>" costs a heap text per
// entry and a text build plus a text hash per lookup; the packed key is 8 B, built and hashed with no allocation.
//
// DETERMINISM. A pool id depends on thread timing (internedtext.h), so the key's VALUE does, and so does the slot a key lands in.
// Both tables are therefore LOOKUP-ONLY: insert, find, contains, size. There is no begin / end / iteration member, so no slot order
// can reach output, an order or a hash (test/textpoolcheck.sh arm N fails on one). IdKeyedMap is the only friend allowed to read
// an InternedTextOf id. A caller that needs its entries in an order keeps that order itself (IdKeyedCsr: first-add order).
//
// IdKeyedCsr<Domain, V> is the multimap form: each key's values in add order, contiguous, behind a 4 B slot (a CSR: one u32 start
// per key, one value array). Adds are staged; seal() lays them out, and a later add followed by seal() appends after a key's
// sealed values (the same order as appending to a per-key vector). A key's value equal to an earlier one of the same key is
// dropped (addUnique), as a "push unless present" vector does. Lookups require a sealed table.

#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <string_view>
#include <utility>
#include <vector>

#include "Diagnostics.h"     // EXPECTS / DASSERT
#include "hashutil.h"        // packPair: the ( owner, id ) key
#include "internedtext.h"    // InternedTextOf: the name half, read through the friendship

#if defined( CTX_USE_STD_MAP )
    #include <unordered_map>
#else
    #include "unordered_dense.h"
#endif

namespace rw
{

template <class Domain, class V> class IdKeyedMap
{
public:
    using Name = InternedTextOf<Domain>;

    void        reserve( std::size_t n ) { map_.reserve( n ); }
    std::size_t size() const noexcept { return map_.size(); }
    void        clear() noexcept { map_.clear(); }

    // ( the value now under the key, true when this call inserted `v` )
    std::pair<V*, bool> try_emplace( std::uint32_t owner, Name name, V v )
    {
        const auto [ it, fresh ] = map_.try_emplace( keyOf( owner, name ), std::move( v ) );
        return { &it->second, fresh };
    }
    V*       find( std::uint32_t owner, Name name ) { return at( map_, owner, name ); }
    const V* find( std::uint32_t owner, Name name ) const { return at( map_, owner, name ); }
    bool     contains( std::uint32_t owner, Name name ) const { return map_.contains( keyOf( owner, name ) ); }

private:
    static std::uint64_t keyOf( std::uint32_t owner, Name name ) noexcept { return hashutil::packPair( owner, name.id_ ); }
    template <class M> static auto at( M& map, std::uint32_t owner, Name name ) -> decltype( &map.begin()->second )
    {
        const auto it = map.find( keyOf( owner, name ) );
        return it == map.end() ? nullptr : &it->second;
    }

#if defined( CTX_USE_STD_MAP )
    std::unordered_map<std::uint64_t, V> map_;
#else
    ankerl::unordered_dense::map<std::uint64_t, V> map_;   // its u64 hash is hashutil::hashMix's (wyhash multiply-fold)
#endif
};

template <class Domain, class V> class IdKeyedCsr
{
public:
    using Name = InternedTextOf<Domain>;

    // stage `v` under ( owner, name ); seal() keeps it unless an equal value of that key came first
    void addUnique( std::uint32_t owner, Name name, V v )
    {
        const auto [ slot, fresh ] = slotOf_.try_emplace( owner, name, slotCount_ );
        if( fresh )
        {
            ++slotCount_;
        }
        staged_.emplace_back( *slot, std::move( v ) );
    }

    // lay the staged values out after each key's sealed ones, in add order, dropping repeats within a key; frees the staging
    void seal()
    {
        if( staged_.empty() )
        {
            return;
        }
        // a stable counting sort of the staged rows by slot (slots are dense, 0..slotCount_)
        std::vector<std::uint32_t> stagedStart( std::size_t( slotCount_ ) + 1, 0 );
        for( const auto& row : staged_ )
        {
            ++stagedStart[ row.first + 1 ];
        }
        for( std::size_t s = 0; s < slotCount_; ++s )
        {
            stagedStart[ s + 1 ] += stagedStart[ s ];
        }
        std::vector<std::uint32_t> order( staged_.size() );
        {
            std::vector<std::uint32_t> next( stagedStart.begin(), stagedStart.end() - 1 );
            for( std::uint32_t i = 0; i < staged_.size(); ++i )
            {
                order[ next[ staged_[ i ].first ]++ ] = i;
            }
        }
        const std::size_t  sealedSlots = start_.empty() ? 0 : start_.size() - 1;
        std::vector<V>     values;
        std::vector<std::uint32_t> start;
        values.reserve( values_.size() + staged_.size() );
        start.reserve( std::size_t( slotCount_ ) + 1 );
        for( std::size_t s = 0; s < slotCount_; ++s )
        {
            const std::size_t first = values.size();
            start.push_back( std::uint32_t( first ) );
            if( s < sealedSlots )
            {
                for( std::uint32_t i = start_[ s ]; i < start_[ s + 1 ]; ++i )
                {
                    values.push_back( std::move( values_[ i ] ) );   // already unique within the key
                }
            }
            for( std::uint32_t k = stagedStart[ s ]; k < stagedStart[ s + 1 ]; ++k )
            {
                V& v = staged_[ order[ k ] ].second;
                bool seen = false;
                for( std::size_t i = first; i < values.size() && !seen; ++i )
                {
                    seen = values[ i ] == v;
                }
                if( !seen )
                {
                    values.push_back( std::move( v ) );
                }
            }
        }
        EXPECTS( values.size() <= 0xFFFFFFFFu, "a CSR offset is a u32" );
        start.push_back( std::uint32_t( values.size() ) );
        values.shrink_to_fit();
        values_ = std::move( values );
        start_  = std::move( start );
        std::vector<std::pair<std::uint32_t, V>>().swap( staged_ );
    }

    // the key's values in add order; empty when the key was never added
    std::span<V> find( std::uint32_t owner, Name name )
    {
        const auto [ b, e ] = range( owner, name );
        return { values_.data() + b, values_.data() + e };
    }
    std::span<const V> find( std::uint32_t owner, Name name ) const
    {
        const auto [ b, e ] = range( owner, name );
        return { values_.data() + b, values_.data() + e };
    }
    bool contains( std::uint32_t owner, Name name ) const { return slotOf_.contains( owner, name ); }

    std::size_t keyCount() const noexcept { return slotCount_; }
    std::size_t valueCount() const noexcept { return values_.size(); }
    // bytes held (the slot table's entries, the offsets, the values and any staging), for the host's stats line
    std::size_t heapBytes() const noexcept
    {
        return slotOf_.size() * 16 + start_.capacity() * sizeof( std::uint32_t ) + values_.capacity() * sizeof( V )
             + staged_.capacity() * sizeof( std::pair<std::uint32_t, V> );
    }

private:
    std::pair<std::size_t, std::size_t> range( std::uint32_t owner, Name name ) const
    {
        DASSERT( staged_.empty(), "IdKeyedCsr: lookups read a sealed table (seal() after the last add)" );
        const std::uint32_t* slot = slotOf_.find( owner, name );
        if( slot == nullptr || std::size_t( *slot ) + 1 >= start_.size() )
        {
            return { 0, 0 };
        }
        return { start_[ *slot ], start_[ *slot + 1 ] };
    }

    IdKeyedMap<Domain, std::uint32_t>        slotOf_;         // ( owner, name ) → its slot, dense in first-add order
    std::uint32_t                            slotCount_ = 0;
    std::vector<std::uint32_t>               start_;          // sealed: slot s's values are [ start_[ s ], start_[ s + 1 ] )
    std::vector<V>                           values_;
    std::vector<std::pair<std::uint32_t, V>> staged_;         // ( slot, value ) added since the last seal, in add order
};

}   // namespace rw

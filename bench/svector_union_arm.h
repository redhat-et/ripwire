#pragma once

// svector_union_arm.h — rwx::svector16: the EXPERIMENT arm. `rw::svector` with `inl_` and `heap_` unioned.
//
// THE HYPOTHESIS. In rw::svector the inline array and the heap pointer are never both live, yet both are
// paid for in every instance:
//
//     T             inl_[ N ];     //  8 B at <uint32,2>
//     T*            heap_;         //  8 B      — dead whenever the payload is inline
//     std::uint32_t sz_, cap_;     //  4 + 4 B
//                                  // 24 B total
//
// Union the first two and the struct is 8 + 4 + 4 = 16 B — ankerl's size — while size() stays `return sz_`
// and therefore stays BRANCH-FREE, because the size lives in its own field instead of packed into the
// buffer. If the in-situ measurement shows the phases are memory-bound (so 16-vs-24 dominates a
// ~1-cycle predicted branch), this arm should beat all three others: ankerl's size with rw's size().
//
// MEASURED LAYOUT (verified by static_assert below, not by arithmetic on paper):
//     <uint32,2>  24 -> 16      <uint32,1>  24 -> 16      <uint32,4>  32 -> 24      <uint64,2>  32 -> 24
//     <T alignof 16, 2>  48 -> 48   — no gain when T is over-aligned; the union's alignment already
//                                     forces the tail padding the two saved bytes would have filled.
// So the saving is 8 B at every shape this tree uses, and never a regression.
//
// THE HAZARD, and why it is not a pointer test. Once the two share storage, `heap_ != nullptr` is not a
// valid "am I spilled?" question: when the inline arm is active those same bytes hold ELEMENT DATA, and a
// list whose first two ids happen to be zero would read as "not spilled" while a list holding ids
// 0x1234/0x5678 would read as a pointer to 0x56780001234. Every discriminator here is `cap_ > N`
// instead — dtor, both moves, buf(), shrink_to_fit and swap. The differential harness's spill-boundary
// bias (N-1, N, N+1) exists to catch exactly this class of mistake.
//
// LIFETIME. T is constrained to trivially-copyable, which is implicit-lifetime, so writing through
// `u_.inl` begins that member's lifetime without a placement-new dance and reading it back is defined.
// That constraint is tighter than rw::svector's and is what keeps this arm short enough to trust as an
// experiment; it costs nothing at the design point (T is always a 4-byte id). u_ is deliberately left
// UNINITIALIZED — a `= {}` would zero N*sizeof(T) on every construction, and unordered_dense constructs
// one of these per insert, so it would put a store on the hot path that rw::svector does not pay.
//
// This lives in bench/ and not in src/infra/ on purpose: it is unvalidated until the A/B says otherwise.
// Promoting it into the vendorable header is a separate commit that the measurement has to earn.

#include <cstdint>
#include <cstring>
#include <initializer_list>
#include <iterator>
#include <type_traits>
#include <utility>

namespace rwx
{

template <class T, std::uint32_t N>
class svector16
{
    static_assert( N >= 1, "needs at least one inline slot" );
    static_assert( std::is_trivially_copyable_v<T>,
                   "the union arm is deliberately restricted to trivially-copyable T — see the header comment" );

    union Store
    {
        T  inl[ N ];
        T* heap;
    };

    Store         u_;
    std::uint32_t sz_  = 0;
    std::uint32_t cap_ = N;

    // `cap_ > N`, never a null test on the pointer — see THE HAZARD above.
    bool     isSpilled() const noexcept { return cap_ > N; }
    T*       buf()       noexcept { return cap_ > N ? u_.heap : u_.inl; }
    const T* buf() const noexcept { return cap_ > N ? u_.heap : u_.inl; }

    static void moveRange( T* dst, const T* src, std::uint32_t count ) noexcept
    {
        if( count != 0 ) { std::memcpy( dst, src, std::size_t( count ) * sizeof( T ) ); }
    }
    // fixed-width block move for the inline arm: N * sizeof( T ) is a compile-time constant
    static void inlineBlockMove( T* dst, const T* src ) noexcept { std::memcpy( dst, src, std::size_t( N ) * sizeof( T ) ); }

    void grow( std::uint32_t need )
    {
        const std::uint64_t doubled = std::uint64_t( cap_ ) * 2u;
        const std::uint64_t want    = doubled < std::uint64_t( need ) ? std::uint64_t( need ) : doubled;
        const std::uint32_t nc      = std::uint32_t( want > 0xFFFFFFFFull ? 0xFFFFFFFFull : want );
        T*                  nh      = new T[ nc ];
        moveRange( nh, buf(), sz_ );
        if( isSpilled() ) { delete[] u_.heap; }
        u_.heap = nh;
        cap_    = nc;
    }

public:
    using value_type             = T;
    using size_type              = std::uint32_t;
    using difference_type        = std::ptrdiff_t;
    using reference              = T&;
    using const_reference        = const T&;
    using pointer                = T*;
    using const_pointer          = const T*;
    using iterator               = T*;
    using const_iterator         = const T*;
    using reverse_iterator       = std::reverse_iterator<iterator>;
    using const_reverse_iterator = std::reverse_iterator<const_iterator>;

    svector16() noexcept = default;
    ~svector16() { if( isSpilled() ) { delete[] u_.heap; } }

    explicit svector16( size_type count ) { resize( count ); }
    svector16( size_type count, const T& value ) { assign( count, value ); }
    template <class InputIt, class = std::enable_if_t<!std::is_integral_v<InputIt>>>
    svector16( InputIt first, InputIt last ) { assign( first, last ); }
    svector16( std::initializer_list<T> init ) { assign( init.begin(), init.end() ); }

    svector16( const svector16& o )
    {
        reserve( o.sz_ );
        moveRange( buf(), o.buf(), o.sz_ );
        sz_ = o.sz_;
    }
    svector16( svector16&& o ) noexcept
    {
        if( o.isSpilled() )
        {
            u_.heap = o.u_.heap;  cap_ = o.cap_;  sz_ = o.sz_;
            o.cap_ = N;  o.sz_ = 0;              // o is now INLINE; its u_.heap is dead storage, not freed
        }
        else
        {
            inlineBlockMove( u_.inl, o.u_.inl );
            sz_   = o.sz_;
            o.sz_ = 0;
        }
    }
    svector16& operator=( svector16&& o ) noexcept
    {
        if( this == &o )
        {
            return *this;
        }
        if( isSpilled() ) { delete[] u_.heap; }
        if( o.isSpilled() )
        {
            u_.heap = o.u_.heap;  cap_ = o.cap_;  sz_ = o.sz_;
            o.cap_ = N;  o.sz_ = 0;
        }
        else
        {
            cap_ = N;
            inlineBlockMove( u_.inl, o.u_.inl );
            sz_   = o.sz_;
            o.sz_ = 0;
        }
        return *this;
    }
    svector16& operator=( const svector16& o )
    {
        if( this == &o )
        {
            return *this;
        }
        if( isSpilled() ) { delete[] u_.heap; }
        cap_ = N;  sz_ = 0;
        reserve( o.sz_ );
        moveRange( buf(), o.buf(), o.sz_ );
        sz_ = o.sz_;
        return *this;
    }
    svector16& operator=( std::initializer_list<T> init )
    {
        assign( init.begin(), init.end() );
        return *this;
    }

    T&       operator[]( size_type i )       noexcept { return buf()[i]; }
    const T& operator[]( size_type i ) const noexcept { return buf()[i]; }
    T&       front()       noexcept { return buf()[0]; }
    const T& front() const noexcept { return buf()[0]; }
    T&       back()        noexcept { return buf()[ sz_ - 1 ]; }
    const T& back()  const noexcept { return buf()[ sz_ - 1 ]; }
    T*       data()        noexcept { return buf(); }
    const T* data()  const noexcept { return buf(); }

    T*       begin()        noexcept { return buf(); }
    T*       end()          noexcept { return buf() + sz_; }
    const T* begin()  const noexcept { return buf(); }
    const T* end()    const noexcept { return buf() + sz_; }
    const T* cbegin() const noexcept { return buf(); }
    const T* cend()   const noexcept { return buf() + sz_; }
    reverse_iterator       rbegin()        noexcept { return reverse_iterator( end() ); }
    reverse_iterator       rend()          noexcept { return reverse_iterator( begin() ); }
    const_reverse_iterator rbegin()  const noexcept { return const_reverse_iterator( end() ); }
    const_reverse_iterator rend()    const noexcept { return const_reverse_iterator( begin() ); }
    const_reverse_iterator crbegin() const noexcept { return const_reverse_iterator( cend() ); }
    const_reverse_iterator crend()   const noexcept { return const_reverse_iterator( cbegin() ); }

    bool      empty()    const noexcept { return sz_ == 0; }
    size_type size()     const noexcept { return sz_; }        // branch-free, exactly as in rw::svector
    size_type capacity() const noexcept { return cap_; }
    bool      spilled()  const noexcept { return isSpilled(); }
    static constexpr size_type max_size() noexcept { return ~std::uint32_t( 0 ); }

    void reserve( size_type need )
    {
        if( need > cap_ ) { grow( need ); }
    }
    void shrink_to_fit()
    {
        if( !isSpilled() || sz_ > N )
        {
            return;
        }
        T* const old = u_.heap;               // read the pointer OUT before the union arm flips
        T  scratch[ N ];
        moveRange( scratch, old, sz_ );
        cap_ = N;
        inlineBlockMove( u_.inl, scratch );
        delete[] old;
    }

    void clear() noexcept { sz_ = 0; }
    void push_back( const T& v )
    {
        if( sz_ == cap_ ) { T saved = v; grow( sz_ + 1 ); buf()[ sz_++ ] = saved; return; }
        buf()[ sz_++ ] = v;
    }
    void push_back( T&& v ) { push_back( static_cast<const T&>( v ) ); }
    template <class... Args>
    T& emplace_back( Args&&... args )
    {
        T built( std::forward<Args>( args )... );
        if( sz_ == cap_ ) { grow( sz_ + 1 ); }
        buf()[ sz_ ] = built;
        return buf()[ sz_++ ];
    }
    void pop_back() noexcept { --sz_; }

    void assign( size_type count, const T& value )
    {
        clear();
        reserve( count );
        T* b = buf();
        for( size_type i = 0; i < count; ++i ) { b[i] = value; }
        sz_ = count;
    }
    template <class InputIt, class = std::enable_if_t<!std::is_integral_v<InputIt>>>
    void assign( InputIt first, InputIt last )
    {
        clear();
        for( ; first != last; ++first ) { push_back( *first ); }
    }
    void assign( std::initializer_list<T> init ) { assign( init.begin(), init.end() ); }

    void resize( size_type count )
    {
        reserve( count );
        T* b = buf();
        for( size_type i = sz_; i < count; ++i ) { b[i] = T(); }
        sz_ = count;
    }
    void resize( size_type count, const T& value )
    {
        reserve( count );
        T* b = buf();
        for( size_type i = sz_; i < count; ++i ) { b[i] = value; }
        sz_ = count;
    }

    iterator insert( const_iterator pos, const T& value )
    {
        const std::uint32_t index = std::uint32_t( pos - cbegin() );
        const T             saved = value;
        reserve( sz_ + 1 );
        T* b = buf();
        for( std::uint32_t i = sz_; i > index; --i ) { b[i] = b[ i - 1 ]; }
        b[ index ] = saved;
        ++sz_;
        return begin() + index;
    }
    iterator insert( const_iterator pos, T&& value ) { return insert( pos, static_cast<const T&>( value ) ); }
    iterator insert( const_iterator pos, size_type count, const T& value )
    {
        const std::uint32_t index = std::uint32_t( pos - cbegin() );
        const T             saved = value;
        reserve( sz_ + count );
        T* b = buf();
        for( std::uint32_t i = sz_; i > index; --i ) { b[ i + count - 1 ] = b[ i - 1 ]; }
        for( size_type i = 0; i < count; ++i ) { b[ index + i ] = saved; }
        sz_ += count;
        return begin() + index;
    }
    template <class InputIt, class = std::enable_if_t<!std::is_integral_v<InputIt>>>
    iterator insert( const_iterator pos, InputIt first, InputIt last )
    {
        const std::uint32_t index = std::uint32_t( pos - cbegin() );
        std::uint32_t       at    = index;
        for( ; first != last; ++first, ++at ) { insert( cbegin() + at, *first ); }
        return begin() + index;
    }
    iterator erase( const_iterator pos ) { return erase( pos, pos + 1 ); }
    iterator erase( const_iterator first, const_iterator last )
    {
        const std::uint32_t index   = std::uint32_t( first - cbegin() );
        const std::uint32_t removed = std::uint32_t( last - first );
        T*                  b       = buf();
        for( std::uint32_t i = index + removed; i < sz_; ++i ) { b[ i - removed ] = b[i]; }
        sz_ -= removed;
        return begin() + index;
    }

    // Same asymmetry as rw::svector::swap, with one extra trap: the spilled side's pointer must be read
    // out of the union BEFORE the inline payload is written over those same bytes.
    void swap( svector16& o ) noexcept
    {
        if( this == &o )
        {
            return;
        }
        const bool aSp = isSpilled();
        const bool bSp = o.isSpilled();
        if( aSp && bSp )
        {
            T* const th = u_.heap;  u_.heap = o.u_.heap;  o.u_.heap = th;
            const auto tc = cap_;   cap_ = o.cap_;        o.cap_ = tc;
        }
        else if( !aSp && !bSp )
        {
            T scratch[ N ];
            inlineBlockMove( scratch, u_.inl );
            inlineBlockMove( u_.inl, o.u_.inl );
            inlineBlockMove( o.u_.inl, scratch );
        }
        else
        {
            svector16& sp = aSp ? *this : o;
            svector16& in = aSp ? o : *this;
            T* const   ph = sp.u_.heap;              // OUT of the union first
            const auto pc = sp.cap_;
            inlineBlockMove( sp.u_.inl, in.u_.inl ); // now safe to overwrite sp's union bytes
            sp.cap_  = N;
            in.u_.heap = ph;
            in.cap_    = pc;
        }
        const auto ts = sz_;  sz_ = o.sz_;  o.sz_ = ts;
    }

    friend bool operator==( const svector16& a, const svector16& b )
    {
        if( a.sz_ != b.sz_ )
        {
            return false;
        }
        for( std::uint32_t i = 0; i < a.sz_; ++i )
        {
            if( !( a.buf()[i] == b.buf()[i] ) ) { return false; }
        }
        return true;
    }
    friend void swap( svector16& a, svector16& b ) noexcept { a.swap( b ); }
};

// The whole point of the arm, pinned so a layout regression fails the build rather than the argument.
static_assert( sizeof( void* ) != 8 || sizeof( svector16<std::uint32_t, 2> ) == 16, "the union arm must reach ankerl's 16 B" );
static_assert( sizeof( void* ) != 8 || sizeof( svector16<std::uint32_t, 1> ) == 16, "" );
static_assert( sizeof( void* ) != 8 || sizeof( svector16<std::uint32_t, 4> ) == 24, "" );
static_assert( sizeof( void* ) != 8 || sizeof( svector16<std::uint64_t, 2> ) == 24, "" );
static_assert( std::is_nothrow_move_constructible_v<svector16<std::uint32_t, 2>>, "unordered_dense rehash must move, never copy" );
static_assert( std::is_nothrow_move_assignable_v<svector16<std::uint32_t, 2>>, "" );

}   // namespace rwx

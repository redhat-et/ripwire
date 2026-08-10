#pragma once

// svector.h — rw::svector: a small-vector with N INLINE slots that spills to the heap only past N.
// 16 bytes at <uint32,2>, with a BRANCH-FREE size(). Both, not one or the other.
//
// ── THE DESIGN, AND WHY IT IS THIS ONE ───────────────────────────────────────────────────────────────
// The shape ripwire leans on hardest is `Map<K, svector<V,N>>` — many tiny id-lists (byName /
// canonByName / shard maps, and ~100 more structures after the conversion wave): WRITE-ONCE during the
// parse/merge, then READ-HOT during resolve.
//
// Three things matter for that shape, and the layout below gets all three:
//   • no per-list malloc — the N small lists that would each allocate are inline;
//   • a BRANCH-FREE size() — `return sz_`, because the size lives in its own field;
//   • 16 BYTES per instance — because `inl_` and `heap_` are never both live, so they share storage.
//
// The union is the whole trick. The previous revision of this file paid 8 extra bytes (24 B) for the
// explicit size field, on the reasoning that a branch-free size() was worth it. That was a false
// choice: union the inline array with the heap pointer and the struct reaches 16 B — ankerl's size —
// while the size stays in its own field and size() stays branch-free.
//
// THE TRADE THAT REMAINS, stated honestly. At 16 bytes you can have:
//   • ankerl::svector's 3 inline slots, with a size() that branches on is_direct() (and, once spilled,
//     dereferences into the heap block to read the size — a dependent load, not just a branch); or
//   • this type's 2 inline slots, with size() branch-free.
// The measurement chose the second. See bench/SVECTORAB.md; the short version is below.
//
// ── WHAT THE MEASUREMENT ACTUALLY SAID (bench/SVECTORAB.md, hardware counters + working-set sweep) ────
// At 200 000 distinct names the profile is memory-bound (IPC 0.70, L1D-MPKI 225, LLC-MPKI 84.9) and this
// layout beats the old 24-byte one by 11.7% on the size-hot loop — 39x that column's 0.3% noise floor.
// Two mechanisms, separable because this type differs from the old one ONLY in size and from ankerl ONLY
// in the size() implementation:
//   • INSTANCE SIZE (16 vs 24 B) — worth ~11.7% at 200K entries, and 0.2-0.5% at the 3 220 / 43 354
//     distinct names `byName` alone holds. It switches on past a ~2.3 MB value array. The conversion
//     wave's census (~113 000 allocation-bearing entries on ripwire's own tree, ~363 000 on the large
//     corpus) puts the AGGREGATE working set well past that line, which is what makes this layout the
//     right default rather than a micro-optimization.
//   • THE size() COST — ~6-7% against ankerl for inline lists at every cardinality tested, rising to
//     42-55% once lists spill past ankerl's inline 3, because its spilled size() is a dependent load.
//
// Do NOT quote bench/bench_svector3.cpp's "~25% over martinus / ~45% over std::vector". That is a
// microbenchmark ratio; in situ the whole-container choice moves `buildGraph` by ~2%, which is ~1.5% of
// post-parse pipeline time and ~0.05% of a run. The layout is right; the stakes are modest.
//
// ── THE ONE CONSTRAINT THE UNION IMPOSES ─────────────────────────────────────────────────────────────
// T must be TRIVIALLY COPYABLE, asserted below. Sharing storage between `inl_` and `heap_` means the
// active member has to be tracked and switched, and doing that for a type with a real constructor and
// destructor is the placement-new lifetime machinery this file exists to avoid. Trivially-copyable types
// are implicit-lifetime, so writing through `u_.inl` simply begins that member's lifetime and reading it
// back is defined. Every element this tree stores in one of these is a 4-byte id or a pair of them.
// For anything else — an over-aligned T, a T with a side-effecting destructor — use
// ankerl::svector (third_party/svector.h), which does real element lifetime management.
//
// ── THE HAZARD, and why nothing here tests `heap_` for null ──────────────────────────────────────────
// Once the two share storage, `heap_ != nullptr` is NOT a valid "am I spilled?" question: when the
// inline arm is active those same bytes hold ELEMENT DATA. A list whose first two ids are 0 would read
// as "not spilled"; one holding ids 0x1234/0x5678 would read as a pointer to 0x5678'00001234. EVERY
// inline/heap decision in this file keys on `cap_ > N` instead — destructor, both moves, buf(),
// shrink_to_fit and swap. bench/bench_svector_diff.cpp's spill-boundary bias (N-1, N, N+1) and its
// exhaustive swap sweep exist to catch exactly this class of mistake.
//
// ── INTERFACE CONTRACT: this type MIRRORS ankerl::svector ────────────────────────────────────────────
// Every operation below carries ankerl's exact name and signature, so a call site can switch between
// `std::vector<T>`, `ankerl::svector<T,N>` and `rw::svector<T,N>` by changing ONE alias (see
// src/smallvec.h) and the whole tree changes implementation. That is what makes the A/B a build flag
// instead of ~138 edits per arm, so new operations copy ankerl, never invent.
//
// THREE DELIBERATE DIVERGENCES (asserting on these in a differential harness would make the harness
// wrong, not this code):
//   1. `size_type` is `std::uint32_t`, not `std::size_t` — it is what keeps the struct at 16 B.
//   2. `capacity()` and the growth schedule differ from ankerl's, which derives inline capacity from a
//      padding-filling formula (ankerl::svector<uint32,2> reports capacity 3, not 2).
//   3. `max_size()` is 2^32-1, the largest value size_type can hold.
//
// ONE DELIBERATE OMISSION, so nobody re-litigates it: **`at()` is absent on purpose.** It reports a
// range error by throwing `std::out_of_range`, and CONTRIBUTING.md §3 permits a throw only at the
// `operator new` seam — preconditions here are `VERIFY`. An `at()` would be a house-style violation
// dressed as a convenience. Use `operator[]`. The omission fails LOUDLY (a compile error at the call
// site), which is the right failure mode and makes the one-alias flip self-checking.
//
// ── ELEMENT MOVEMENT ─────────────────────────────────────────────────────────────────────────────────
// Every bulk move funnels through moveRange/inlineBlockMove below, which are plain memcpy: the
// trivially-copyable constraint that makes the union safe also makes the fast path unconditional, so
// there is no `if constexpr` fork left to keep in sync. This matters more than the growth path suggests
// — ankerl::unordered_dense keeps its values in one contiguous vector, so every rehash MOVES EVERY
// ELEMENT, thousands of times per run, against the well under 1 KB that all of grow() moves.

#include <compare>
#include <cstdint>
#include <cstring>
#include <initializer_list>
#include <iterator>
#include <type_traits>
#include <utility>

namespace rw
{

template <class T, std::uint32_t N>
class svector
{
    static_assert( N >= 1, "svector needs at least one inline slot — `T inl[0]` is not a valid array" );
    // The constraint the union imposes. See "THE ONE CONSTRAINT" in the header comment; use
    // ankerl::svector for anything this rejects.
    static_assert( std::is_trivially_copyable_v<T>,
                   "rw::svector unions its inline array with its heap pointer, so T must be trivially copyable "
                   "(implicit-lifetime). For a T with a real constructor/destructor, or an over-aligned T, use "
                   "ankerl::svector (third_party/svector.h)." );
    // grow() allocates with `new T[nc]`, which for a trivially-copyable T is a raw allocation with NO
    // per-element work (new T[n] default-initializes, a no-op for trivial types). The placement-new
    // machinery that buys ankerl its generality would buy this type nothing at its design point.
    static_assert( std::is_default_constructible_v<T>, "grow() allocates a `new T[]` block" );

    union Store
    {
        T  inl[ N ];
        T* heap;
    };

    Store         u_;              // deliberately UNINITIALIZED — see the note on the default ctor
    std::uint32_t sz_  = 0;
    std::uint32_t cap_ = N;

    // `cap_ > N`, NEVER a null test on the pointer — see THE HAZARD in the header comment.
    bool     isSpilled() const noexcept { return cap_ > N; }
    T*       buf()       noexcept { return cap_ > N ? u_.heap : u_.inl; }
    const T* buf() const noexcept { return cap_ > N ? u_.heap : u_.inl; }

    // memcpy( _, _, 0 ) with a null pointer is UB even though it copies nothing — hence the count guard,
    // which costs nothing on the paths where count is a compile-time constant.
    static void moveRange( T* dst, const T* src, std::uint32_t count ) noexcept
    {
        if( count != 0 ) { std::memcpy( dst, src, std::size_t( count ) * sizeof( T ) ); }
    }
    // The INLINE arm moves the WHOLE N-slot block rather than exactly sz_ elements: `N * sizeof( T )` is
    // a compile-time constant — 8 bytes at <uint32,2>, one register-width move — where the
    // variable-length form leaves the compiler a general loop with a bounds check it cannot fold. The
    // up-to-N-1 slots of garbage carried past sz_ are never read, because every read is bounded by sz_.
    static void inlineBlockMove( T* dst, const T* src ) noexcept { std::memcpy( dst, src, std::size_t( N ) * sizeof( T ) ); }

    void grow( std::uint32_t need )
    {
        // Widen before doubling: cap_ * 2 is unsigned arithmetic on a uint32 and wraps at 2^31, which
        // `-fsanitize=integer` reports as unsigned-integer-overflow. Unreachable at this tree's sizes,
        // but a wrap-free cold path costs nothing and keeps the sanitizer stack honest.
        const std::uint64_t doubled = std::uint64_t( cap_ ) * 2u;
        const std::uint64_t want    = doubled < std::uint64_t( need ) ? std::uint64_t( need ) : doubled;
        const std::uint32_t nc      = want > std::uint64_t( maxSize() ) ? maxSize() : std::uint32_t( want );
        T*                  nh      = new T[ nc ];
        moveRange( nh, buf(), sz_ );
        if( isSpilled() ) { delete[] u_.heap; }
        u_.heap = nh;                  // writing the pointer member makes it active; cap_ agrees below
        cap_    = nc;
    }

    // shift the tail [index, sz_) right by `count` slots, growing first if needed. The caller writes the
    // opened hole. Used by insert/emplace.
    void openHole( std::uint32_t index, std::uint32_t count )
    {
        reserve( sz_ + count );
        T* b = buf();
        // right-to-left, so an overlapping shift cannot clobber a source slot it has not read yet
        for( std::uint32_t i = sz_; i > index; --i )
        {
            b[ i + count - 1 ] = b[ i - 1 ];
        }
        sz_ += count;
    }

    static constexpr std::uint32_t maxSize() noexcept { return ~std::uint32_t( 0 ); }

public:
    // ── member types (ankerl's spelling, so the alias flip type-checks) ───────────────────────────────
    using value_type             = T;
    using size_type              = std::uint32_t;          // DIVERGENCE 1 — see the header comment
    using difference_type        = std::ptrdiff_t;
    using reference              = T&;
    using const_reference        = const T&;
    using pointer                = T*;
    using const_pointer          = const T*;
    using iterator               = T*;
    using const_iterator         = const T*;
    using reverse_iterator       = std::reverse_iterator<iterator>;
    using const_reverse_iterator = std::reverse_iterator<const_iterator>;

    // ── construct / destroy ───────────────────────────────────────────────────────────────────────────
    // u_ is left UNINITIALIZED on purpose: a `= {}` would zero N*sizeof(T) on every construction, and
    // unordered_dense constructs one of these per insert, so it would put a store on the hot path for
    // bytes that sz_ already guarantees are never read.
    svector() noexcept = default;
    ~svector() { if( isSpilled() ) { delete[] u_.heap; } }

    explicit svector( size_type count ) { resize( count ); }
    svector( size_type count, const T& value ) { assign( count, value ); }
    template <class InputIt, class = std::enable_if_t<!std::is_integral_v<InputIt>>>
    svector( InputIt first, InputIt last ) { assign( first, last ); }
    svector( std::initializer_list<T> init ) { assign( init.begin(), init.end() ); }

    svector( const svector& o )
    {
        reserve( o.sz_ );
        moveRange( buf(), o.buf(), o.sz_ );
        sz_ = o.sz_;
    }
    svector( svector&& o ) noexcept
    {
        if( o.isSpilled() )
        {
            u_.heap = o.u_.heap;  cap_ = o.cap_;  sz_ = o.sz_;
            o.cap_ = N;  o.sz_ = 0;          // o is INLINE again; its u_.heap is now dead storage, not freed
        }
        else
        {
            inlineBlockMove( u_.inl, o.u_.inl );
            sz_   = o.sz_;
            o.sz_ = 0;
        }
    }
    svector& operator=( svector&& o ) noexcept
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
    svector& operator=( const svector& o )
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
    svector& operator=( std::initializer_list<T> init )
    {
        assign( init.begin(), init.end() );
        return *this;
    }

    // ── element access (no at(): see the header comment — it would have to throw) ─────────────────────
    T&       operator[]( size_type i )       noexcept { return buf()[i]; }
    const T& operator[]( size_type i ) const noexcept { return buf()[i]; }
    T&       front()       noexcept { return buf()[0]; }
    const T& front() const noexcept { return buf()[0]; }
    T&       back()        noexcept { return buf()[ sz_ - 1 ]; }
    const T& back()  const noexcept { return buf()[ sz_ - 1 ]; }
    T*       data()        noexcept { return buf(); }
    const T* data()  const noexcept { return buf(); }

    // ── iterators ─────────────────────────────────────────────────────────────────────────────────────
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

    // ── capacity ──────────────────────────────────────────────────────────────────────────────────────
    bool      empty()    const noexcept { return sz_ == 0; }
    size_type size()     const noexcept { return sz_; }            // branch-free — the whole point (see header)
    size_type capacity() const noexcept { return cap_; }
    bool      spilled()  const noexcept { return isSpilled(); }    // rw-only; ankerl spells this is_direct()
    static constexpr size_type max_size() noexcept { return maxSize(); }   // DIVERGENCE 3

    // reserve() takes a by-value COUNT, never a `const T&`, so the self-alias hazard push_back guards
    // against (a `v` pointing into this vector, invalidated when grow() frees the old buffer) cannot
    // arise here — there is no T reference to invalidate. Probed deliberately; recorded so the question
    // is not re-opened.
    void reserve( size_type need )
    {
        if( need > cap_ )
        {
            grow( need );
        }
    }
    // Genuinely returns to INLINE storage when the payload fits again. Without this, a single
    // `reserve( n > N )` is a one-way door that permanently forfeits the inline win, which is the entire
    // point of the type. A heap block that is merely oversized is left alone — shrink_to_fit is a
    // non-binding request in the standard, and reallocating heap->smaller-heap buys nothing here.
    void shrink_to_fit()
    {
        if( !isSpilled() || sz_ > N )
        {
            return;
        }
        T* const old = u_.heap;              // read the pointer OUT before the union arm flips
        T        scratch[ N ];
        moveRange( scratch, old, sz_ );
        cap_ = N;                            // inline arm is active from here
        inlineBlockMove( u_.inl, scratch );
        delete[] old;
    }

    // ── modifiers ─────────────────────────────────────────────────────────────────────────────────────
    // clear() RETAINS the heap buffer (std::vector-compatible), which also keeps the differential
    // harness valid against std::vector.
    void clear() noexcept { sz_ = 0; }

    // self-alias safe: if v points into this vector, grow() would free the old heap before the copy —
    // save a local copy first on the grow path (the common non-growing path stays a single assignment).
    void push_back( const T& v )
    {
        if( sz_ == cap_ ) { const T saved = v; grow( sz_ + 1 ); buf()[ sz_++ ] = saved; return; }
        buf()[ sz_++ ] = v;
    }
    void push_back( T&& v ) { push_back( static_cast<const T&>( v ) ); }
    template <class... Args>
    T& emplace_back( Args&&... args )
    {
        const T built( std::forward<Args>( args )... );   // built BEFORE any grow, so an argument that
        if( sz_ == cap_ ) { grow( sz_ + 1 ); }            // aliases this vector is read while still valid
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
        // Grown slots are value-initialized: `new T[]` DEFAULT-initializes, which leaves a trivial T
        // holding whatever the allocator handed back. std::vector::resize promises a value, so this
        // writes one rather than exposing indeterminate bytes.
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
        const T             saved = value;        // read BEFORE openHole grows/shifts, in case it aliases us
        openHole( index, 1 );
        buf()[ index ] = saved;
        return begin() + index;
    }
    iterator insert( const_iterator pos, T&& value ) { return insert( pos, static_cast<const T&>( value ) ); }
    iterator insert( const_iterator pos, size_type count, const T& value )
    {
        const std::uint32_t index = std::uint32_t( pos - cbegin() );
        const T             saved = value;
        openHole( index, count );
        T* b = buf();
        for( size_type i = 0; i < count; ++i ) { b[ index + i ] = saved; }
        return begin() + index;
    }
    template <class InputIt, class = std::enable_if_t<!std::is_integral_v<InputIt>>>
    iterator insert( const_iterator pos, InputIt first, InputIt last )
    {
        const std::uint32_t index = std::uint32_t( pos - cbegin() );
        std::uint32_t       at    = index;
        for( ; first != last; ++first, ++at )
        {
            insert( cbegin() + at, *first );
        }
        return begin() + index;
    }
    iterator insert( const_iterator pos, std::initializer_list<T> init ) { return insert( pos, init.begin(), init.end() ); }

    template <class... Args>
    iterator emplace( const_iterator pos, Args&&... args )
    {
        const std::uint32_t index = std::uint32_t( pos - cbegin() );
        const T             built( std::forward<Args>( args )... );
        openHole( index, 1 );
        buf()[ index ] = built;
        return begin() + index;
    }

    // erase( first, end() ) is the TRUNCATE idiom and costs nothing: the shift loop below does not
    // execute when last == end(), so it lowers to `sz_ -= removed`. That is why no truncate( n ) exists
    // — it would be an invented name for an operation ankerl already spells.
    iterator erase( const_iterator pos ) { return erase( pos, pos + 1 ); }
    iterator erase( const_iterator first, const_iterator last )
    {
        const std::uint32_t index   = std::uint32_t( first - cbegin() );
        const std::uint32_t removed = std::uint32_t( last - first );
        T*                  b       = buf();
        for( std::uint32_t i = index + removed; i < sz_; ++i )
        {
            b[ i - removed ] = b[i];
        }
        sz_ -= removed;
        return begin() + index;
    }

    // The inline<->heap asymmetry is where small-vector implementations actually break: when exactly one
    // side is spilled this is NOT a pointer exchange. Handing the spilled side a pointer to the other
    // object's inline array produces a dangling interior pointer the moment either object moves — so the
    // inline payload is CARRIED across first. With the union there is a second trap on top: the spilled
    // side's pointer must be read OUT before the inline payload is written over those same bytes.
    void swap( svector& o ) noexcept
    {
        if( this == &o )
        {
            return;
        }
        const bool aSp = isSpilled();
        const bool bSp = o.isSpilled();
        if( aSp && bSp )
        {
            T* const   th = u_.heap;  u_.heap = o.u_.heap;  o.u_.heap = th;
            const auto tc = cap_;     cap_    = o.cap_;     o.cap_    = tc;
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
            svector&   sp = aSp ? *this : o;         // the spilled one
            svector&   in = aSp ? o : *this;         // the inline one
            T* const   ph = sp.u_.heap;              // OUT of the union first
            const auto pc = sp.cap_;
            inlineBlockMove( sp.u_.inl, in.u_.inl ); // now safe to overwrite sp's union bytes
            sp.cap_    = N;
            in.u_.heap = ph;
            in.cap_    = pc;
        }
        const auto ts = sz_;  sz_ = o.sz_;  o.sz_ = ts;
    }

    // ── comparison (hidden friends: found by ADL, never by an unqualified lookup elsewhere) ───────────
    friend bool operator==( const svector& a, const svector& b )
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
    friend auto operator<=>( const svector& a, const svector& b )
    {
        const std::uint32_t common = a.sz_ < b.sz_ ? a.sz_ : b.sz_;
        for( std::uint32_t i = 0; i < common; ++i )
        {
            if( const auto c = a.buf()[i] <=> b.buf()[i]; c != 0 ) { return c; }
        }
        return a.sz_ <=> b.sz_;
    }
    friend void swap( svector& a, svector& b ) noexcept { a.swap( b ); }
};

// ── LAYOUT PINS ───────────────────────────────────────────────────────────────────────────────────────
// src/layout.h records a change that silently made FixedStr read 16 bytes instead of 32, with no test to
// catch it. These fail the BUILD instead, and test/svectorcheck.sh mutates a scratch copy of this header
// to prove they actually fire rather than merely existing.
//
// THESE NUMBERS ARE THE POINT OF THE TYPE. 16 bytes at <uint32,2> is what the union buys; if a member is
// added back, or the union is unpicked, the struct returns to 24 and this build stops. A ~100-structure
// conversion wave multiplies every byte here by ~113 000 entries on ripwire's own tree and ~363 000 on
// the large corpus, so a silent regression to 24 B would cost ~0.9 MB and ~2.9 MB of resident footprint
// respectively — squarely back over the ~2.3 MB line where the locality effect switches on.
//
// The `sizeof( void* ) != 8 ||` guard is not hedging: the numbers are 64-bit-target numbers, and a pin
// that would be false on a 32-bit build should self-disable rather than lie.
static_assert( sizeof( void* ) != 8 || sizeof( svector<std::uint32_t, 2> ) == 16,
               "svector<uint32,2> must be 16 B: 8 B of union (inl[2] over heap) + 4 + 4 of sz_/cap_. If this "
               "fires, the union has been unpicked or a member added, and the type has silently become the "
               "24-byte design the measurement rejected." );
static_assert( sizeof( void* ) != 8 || alignof( svector<std::uint32_t, 2> ) == 8, "pointer-aligned, not over-aligned" );
static_assert( sizeof( void* ) != 8 || sizeof( svector<std::uint32_t, 1> ) == 16, "N=1 shares the pointer's 8 B" );
static_assert( sizeof( void* ) != 8 || sizeof( svector<std::uint32_t, 4> ) == 24, "N=4 needs 16 B of inline slots" );
static_assert( sizeof( void* ) != 8 || sizeof( svector<std::uint64_t, 2> ) == 24, "the 8-byte-element shape (varSpans' pair<uint32,uint32>) is 24 B" );

// Move construction is the HOTTEST operation on this type and nothing in the tree calls it explicitly:
// ankerl::unordered_dense keeps values in one contiguous vector, so every rehash moves every element. A
// move that is not noexcept makes that rehash COPY instead, silently, with no diagnostic anywhere.
static_assert( std::is_nothrow_move_constructible_v<svector<std::uint32_t, 2>>,
               "a throwing move turns every unordered_dense rehash into a copy — the one regression this type cannot afford" );
static_assert( std::is_nothrow_move_assignable_v<svector<std::uint32_t, 2>>, "same reason as the move constructor" );

// Not trivially copyable, and that is correct, not a defect: past N it owns a heap buffer. The pin exists
// so nobody "optimizes" a container of these into a memcpy of the instances.
static_assert( !std::is_trivially_copyable_v<svector<std::uint32_t, 2>>,
               "svector owns a heap buffer past N — an instance must never be memcpy'd, only its ELEMENTS are" );

}   // namespace rw

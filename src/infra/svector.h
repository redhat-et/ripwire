#pragma once

// svector.h — rw::svector: a small-vector with N INLINE slots that spills to the heap only past N.
//
// ── WHY THIS EXISTS ALONGSIDE the vendored martinus/svector (third_party/svector.h, ankerl::svector) ──
// It is purpose-built for the ONE shape ripwire leans on hardest — a `Map<K, svector<V,N>>` of many tiny
// id-lists (byName / canonByName / shard maps): WRITE-ONCE during the parse/merge, then READ-HOT during
// resolve.
//
//   • build win (shared with martinus): the N small lists that would each malloc become inline — one fewer
//     heap allocation per collection, no pointer-chase to the payload.
//   • read win (the differentiator): size() is `return sz_` — BRANCH-FREE. martinus packs its size into the
//     SVO buffer to reach 16 B, so its size() branches on is_direct(). We keep an explicit sz_ field
//     instead: sizeof(svector<uint32,2>) = 24 B, 8 B more than martinus, spent to make the hot read
//     branch-free.
//
// ── WHEN THIS TYPE IS THE RIGHT CHOICE, AND WHEN IT IS NOT ───────────────────────────────────────────
// Measured, not argued — hardware counters plus a working-set sweep, both in bench/SVECTORAB.md. Three
// effects separate, and they do NOT live in the same regime:
//
//   • the size() cost is REAL and REACHES this tree. ankerl's size() branches on is_direct(); worse, on
//     a SPILLED list it is `indirect()->size()`, a dependent load into the heap block — a second cache
//     miss under a memory-bound profile, not a predicted branch. Measured on the size-hot loop: ~6-7%
//     for inline lists at both real cardinalities, and 42-55% once lists spill past ankerl's inline 3.
//   • the 8-byte SIZE advantage of a 16-byte small-vector does NOT reach this tree. It is worth 11.7%
//     at 200 000 distinct names and 0.2-0.5% — at or under the noise floor — at the 3 220 and 43 354
//     this tool actually indexes. It switches on past a ~2.3 MB value array and not before.
//   • ITERATION is a wash at real cardinality. If a site range-fors and never polls size(), prefer the
//     vendored ankerl::svector: same speed, 8 bytes smaller, complete and maintained.
//
// So: poll size() in a hot loop -> this type. Iterate -> ankerl. The stakes are modest either way
// (1.5% of post-parse pipeline time, 0.05% of total runtime), so this is a tie-breaker, not a mandate.
//
// TWO RETRACTIONS, kept visible because both were confidently wrong. (1) A previous revision claimed
// "~25% over martinus, ~45% over std::vector" from bench/bench_svector3.cpp; that is a microbenchmark
// ratio and does not transfer — in situ it is 1.9% of buildGraph. (2) A previous revision of this
// comment then over-corrected, arguing the microbenchmark "understates the cost of SIZE and overstates
// the cost of the BRANCH". That is backwards, and hardware counters said so: at 200K names the profile
// is memory-bound (IPC 0.70, LLC-MPKI 84.9) and the microbenchmark OVERSTATES size, because 200K names
// is a working set nothing real here reaches. Reasoning about which effect "should" dominate produced
// the wrong answer twice; the counters produced it once.
// The authoritative comparison is the in-situ four-way A/B: bench/svectorab.py (see bench/SVECTORAB.md).
//
// ── INTERFACE CONTRACT: this type MIRRORS ankerl::svector ────────────────────────────────────────────
// Every operation below carries ankerl's exact name and signature, so a call site can switch between
// `std::vector<T>`, `ankerl::svector<T,N>` and `rw::svector<T,N>` by changing ONE alias (see
// src/smallvec.h) and the whole tree changes implementation. Deviating from that spelling would
// turn a build-configuration experiment into 138 edits per arm, so new operations copy ankerl, never
// invent.
//
// FOUR DELIBERATE DIVERGENCES (asserting on these in a differential harness would make the harness
// wrong, not this code):
//   1. `size_type` is `std::uint32_t`, not `std::size_t`. Load-bearing: it is what keeps the struct at
//      24 B with a branch-free size().
//   2. `capacity()` and the growth schedule differ from ankerl's, which derives inline capacity from a
//      padding-filling formula (ankerl::svector<uint32,2> reports capacity 3, not 2, and is 16 B).
//   3. `max_size()` is 2^32-1, the largest value size_type can hold.
//   4. ELEMENT LIFETIME IS BUFFER LIFETIME. Storage is `new T[cap_]`, so every slot of the buffer holds a
//      live T; clear()/pop_back()/erase()/resize()-down lower `sz_` but do not run element destructors,
//      which instead run when the buffer dies. For the trivially-copyable ids this type is designed for
//      that is exactly free and unobservable. For a T with a side-effecting destructor it is WRONG —
//      use ankerl::svector, which does real element lifetime management. The default-constructible
//      static_assert below is the visible half of the same constraint.
//
// ONE DELIBERATE OMISSION, so nobody re-litigates it: **`at()` is absent on purpose.** It reports a
// range error by throwing `std::out_of_range`, and CONTRIBUTING.md §3 permits a throw only at the
// `operator new` seam — preconditions here are `VERIFY`. An `at()` would be a house-style violation
// dressed as a convenience. Use `operator[]`. The omission fails LOUDLY (a compile error at the call
// site), which is the right failure mode and makes the one-alias flip self-checking.
//
// ── TRIVIAL-TYPE FAST PATHS ──────────────────────────────────────────────────────────────────────────
// Every bulk element movement funnels through moveRange/copyRange/inlineBlockCopy below, which dispatch
// on `std::is_trivially_copyable_v<T>` at COMPILE time (`if constexpr`, never a runtime test). This
// matters far more than the growth path suggests: ankerl::unordered_dense keeps its values in one
// contiguous vector, so every rehash MOVES EVERY ELEMENT — thousands of svector moves per run on a 9K
// -entry byName, against the well under 1 KB that all of grow() moves in a whole run. This type had no
// such path at all before this revision, so any A/B measured before it was measuring that handicap
// rather than the design.
//
// WHERE ANKERL ACTUALLY SITS (audited against third_party/svector.h at the vendored commit, so the
// comparison is between two optimized types rather than an optimized one and a naive one):
//   • explicit `if constexpr` memcpy: reallocation only (uninitialized_move_and_destroy, its l.249-256,
//     three call sites, all inside realloc).
//   • explicit destroy elision on is_trivially_destructible_v: dtor, clear, pop_back, resize-shrink.
//   • NO explicit trait branch on copy-ctor, copy-assign, the inline arm of move-ctor/move-assign,
//     insert, or erase — those call std::uninitialized_copy/std::uninitialized_move, which reach memcpy
//     via libstdc++'s internal dispatch but, on libc++ (this Darwin box), only if LLVM's
//     loop-idiom-recognize fires. That is the one axis where an A/B result could be attributed to the
//     standard library rather than to either container's design. bench/svectorab.py keeps each arm's
//     binary, so the emitted memcpy/memmove calls at those sites can be counted rather than assumed.
//   • its swap() is `std::swap(*this, other)` — three full moves, carrying its own "TODO we could try to
//     do the minimum number of moves". The hand-written swap below is structurally cheaper; that is a
//     real difference and not a measurement artifact.
//   • its inline-arm move copies exactly size() elements, never a fixed-N block.
//
// Hand-rolled RAII (raw new[]/delete[], per house style), move + copy.

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
    static_assert( N >= 1, "svector needs at least one inline slot — `T inl_[0]` is not a valid array" );
    // grow() allocates with `new T[nc]`: the DOD form this specialist keeps on purpose. For a trivially
    // copyable T that is a raw allocation with NO per-element work (new T[n] default-initializes, which
    // is a no-op for trivial types), so the raw-storage/placement-new machinery that buys ankerl its
    // generality would buy this type nothing at its design point. The price is this constraint, asserted
    // here rather than left to a template error 40 frames deep.
    static_assert( std::is_default_constructible_v<T>,
                   "rw::svector stores elements in a `new T[]` block, so T must be default-constructible. "
                   "For a type that is not, use ankerl::svector (third_party/svector.h)." );

    T             inl_[ N ];
    T*            heap_ = nullptr;        // non-null ⇒ payload is on the heap (cap_ > N)
    std::uint32_t sz_   = 0;
    std::uint32_t cap_  = N;

    T*       buf()       noexcept { return heap_ ? heap_ : inl_; }
    const T* buf() const noexcept { return heap_ ? heap_ : inl_; }

    // ── bulk element movement: ONE place, so the five paths that move elements cannot drift apart ────
    // (grow, copy-ctor, copy-assign, move-ctor inline arm, move-assign inline arm). `if constexpr`, so a
    // trivially-copyable T lowers the whole thing to a single memcpy with no loop left behind.
    // memcpy( _, _, 0 ) with a null pointer is UB even though it copies nothing — hence the count guard,
    // which costs nothing on the paths where count is a compile-time constant.
    static void moveRange( T* dst, T* src, std::uint32_t count ) noexcept
    {
        if constexpr( std::is_trivially_copyable_v<T> )
        {
            if( count != 0 ) { std::memcpy( dst, src, std::size_t( count ) * sizeof( T ) ); }
        }
        else
        {
            for( std::uint32_t i = 0; i < count; ++i ) { dst[i] = std::move( src[i] ); }
        }
    }
    static void copyRange( T* dst, const T* src, std::uint32_t count )
    {
        if constexpr( std::is_trivially_copyable_v<T> )
        {
            if( count != 0 ) { std::memcpy( dst, src, std::size_t( count ) * sizeof( T ) ); }
        }
        else
        {
            for( std::uint32_t i = 0; i < count; ++i ) { dst[i] = src[i]; }
        }
    }
    // The INLINE arm moves the WHOLE N-slot block rather than exactly sz_ elements: `N * sizeof( T )` is a
    // compile-time constant — 8 bytes at <uint32,2>, one register-width move — where the variable-length
    // form leaves the compiler a general loop with a bounds check it cannot fold. The up-to-N-1 slots of
    // garbage carried past sz_ are never read, because every read is bounded by sz_. Trivially-copyable T
    // only; anything else falls back to the exact-count path (copying a live element past sz_ would run a
    // real assignment operator on it).
    static void inlineBlockMove( T* dst, T* src, std::uint32_t count ) noexcept
    {
        if constexpr( std::is_trivially_copyable_v<T> )
        {
            (void) count;
            std::memcpy( dst, src, std::size_t( N ) * sizeof( T ) );
        }
        else
        {
            moveRange( dst, src, count );
        }
    }

    void grow( std::uint32_t need )
    {
        // Widen before doubling: cap_ * 2 is unsigned arithmetic on a uint32 and wraps at 2^31, which
        // `-fsanitize=integer` reports as unsigned-integer-overflow. Unreachable at this tree's sizes
        // (the largest id-list is single digits), but a wrap-free cold path costs nothing and keeps the
        // sanitizer stack honest rather than exempted.
        const std::uint64_t doubled = std::uint64_t( cap_ ) * 2u;
        const std::uint64_t want    = doubled < std::uint64_t( need ) ? std::uint64_t( need ) : doubled;
        const std::uint32_t nc      = want > std::uint64_t( maxSize() ) ? maxSize() : std::uint32_t( want );
        T*                  nh      = new T[ nc ];
        moveRange( nh, buf(), sz_ );
        delete[] heap_;
        heap_ = nh;
        cap_  = nc;
    }

    // shift the tail [index, sz_) right by `count` slots, growing first if needed. Returns nothing; the
    // caller writes the opened hole. Used by insert/emplace.
    void openHole( std::uint32_t index, std::uint32_t count )
    {
        reserve( sz_ + count );
        T* b = buf();
        // right-to-left, so an overlapping shift cannot clobber a source slot it has not read yet
        // (this is memmove's contract, and the exact-count loop below matches it deliberately).
        for( std::uint32_t i = sz_; i > index; --i )
        {
            b[ i + count - 1 ] = std::move( b[ i - 1 ] );
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
    svector() noexcept = default;
    ~svector() { delete[] heap_; }

    explicit svector( size_type count ) { resize( count ); }
    svector( size_type count, const T& value ) { assign( count, value ); }
    template <class InputIt, class = std::enable_if_t<!std::is_integral_v<InputIt>>>
    svector( InputIt first, InputIt last ) { assign( first, last ); }
    svector( std::initializer_list<T> init ) { assign( init.begin(), init.end() ); }

    svector( const svector& o )
    {
        reserve( o.sz_ );
        copyRange( buf(), o.buf(), o.sz_ );
        sz_ = o.sz_;
    }
    svector( svector&& o ) noexcept
    {
        if( o.heap_ )
        {
            heap_ = o.heap_;  cap_ = o.cap_;  sz_ = o.sz_;
            o.heap_ = nullptr;  o.cap_ = N;  o.sz_ = 0;
        }
        else
        {
            inlineBlockMove( inl_, o.inl_, o.sz_ );
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
        delete[] heap_;
        if( o.heap_ )
        {
            heap_ = o.heap_;  cap_ = o.cap_;  sz_ = o.sz_;
            o.heap_ = nullptr;  o.cap_ = N;  o.sz_ = 0;
        }
        else
        {
            heap_ = nullptr;
            cap_  = N;
            inlineBlockMove( inl_, o.inl_, o.sz_ );
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
        delete[] heap_;  heap_ = nullptr;  cap_ = N;  sz_ = 0;
        reserve( o.sz_ );
        copyRange( buf(), o.buf(), o.sz_ );
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
    bool      spilled()  const noexcept { return heap_ != nullptr; }   // rw-only; ankerl spells this is_direct()
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
    // `reserve( n > N )` is a one-way door that permanently forfeits the inline-cache win, which is the
    // entire point of the type. A heap block that is merely oversized is left alone — shrink_to_fit is a
    // non-binding request in the standard, and reallocating heap→smaller-heap buys nothing here.
    void shrink_to_fit()
    {
        if( heap_ == nullptr || sz_ > N )
        {
            return;
        }
        moveRange( inl_, heap_, sz_ );
        delete[] heap_;
        heap_ = nullptr;
        cap_  = N;
    }

    // ── modifiers ─────────────────────────────────────────────────────────────────────────────────────
    // clear() RETAINS the heap buffer (std::vector-compatible). Elements past the new size stay live
    // until the buffer dies — divergence 4 in the header comment.
    void clear() noexcept { sz_ = 0; }

    // self-alias safe: if v points into this vector, grow() would free the old heap before the copy —
    // save a local copy first on the grow path (the common non-growing path stays a single assignment).
    void push_back( const T& v )
    {
        if( sz_ == cap_ ) { T saved = v; grow( sz_ + 1 ); buf()[ sz_++ ] = std::move( saved ); return; }
        buf()[ sz_++ ] = v;
    }
    void push_back( T&& v )
    {
        if( sz_ == cap_ ) { T saved = std::move( v ); grow( sz_ + 1 ); buf()[ sz_++ ] = std::move( saved ); return; }
        buf()[ sz_++ ] = std::move( v );
    }
    template <class... Args>
    T& emplace_back( Args&&... args )
    {
        T built( std::forward<Args>( args )... );      // built BEFORE any grow, so an argument that
        if( sz_ == cap_ ) { grow( sz_ + 1 ); }         // aliases this vector is read while still valid
        buf()[ sz_ ] = std::move( built );
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
        T                   saved = value;      // read BEFORE openHole grows/shifts, in case it aliases us
        openHole( index, 1 );
        buf()[ index ] = std::move( saved );
        return begin() + index;
    }
    iterator insert( const_iterator pos, T&& value )
    {
        const std::uint32_t index = std::uint32_t( pos - cbegin() );
        T                   saved = std::move( value );
        openHole( index, 1 );
        buf()[ index ] = std::move( saved );
        return begin() + index;
    }
    iterator insert( const_iterator pos, size_type count, const T& value )
    {
        const std::uint32_t index = std::uint32_t( pos - cbegin() );
        T                   saved = value;
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
        T                   built( std::forward<Args>( args )... );
        openHole( index, 1 );
        buf()[ index ] = std::move( built );
        return begin() + index;
    }

    iterator erase( const_iterator pos ) { return erase( pos, pos + 1 ); }
    iterator erase( const_iterator first, const_iterator last )
    {
        const std::uint32_t index   = std::uint32_t( first - cbegin() );
        const std::uint32_t removed = std::uint32_t( last - first );
        T*                  b       = buf();
        for( std::uint32_t i = index + removed; i < sz_; ++i )
        {
            b[ i - removed ] = std::move( b[i] );
        }
        sz_ -= removed;
        return begin() + index;
    }

    // The inline↔heap asymmetry is where small-vector implementations actually break: when exactly one
    // side is spilled this is NOT a pointer exchange. Handing the spilled side a pointer to the other
    // object's inl_ produces a dangling interior pointer the moment either object moves — so the inline
    // payload is CARRIED into the spilled object's (currently unused) inline array first.
    void swap( svector& o ) noexcept
    {
        if( this == &o )
        {
            return;
        }
        if( ( heap_ != nullptr ) == ( o.heap_ != nullptr ) )
        {
            // symmetric: both spilled (exchange the pointers) or both inline (exchange the blocks)
            if( heap_ != nullptr )
            {
                T* const  th = heap_;   heap_ = o.heap_;   o.heap_ = th;
                const auto tc = cap_;   cap_  = o.cap_;    o.cap_  = tc;
            }
            else
            {
                T scratch[ N ];
                inlineBlockMove( scratch, inl_, sz_ );
                inlineBlockMove( inl_, o.inl_, o.sz_ );
                inlineBlockMove( o.inl_, scratch, sz_ );
            }
        }
        else
        {
            svector& sp = ( heap_ != nullptr ) ? *this : o;      // the spilled one
            svector& in = ( heap_ != nullptr ) ? o : *this;      // the inline one
            inlineBlockMove( sp.inl_, in.inl_, in.sz_ );         // carry the payload across
            in.heap_ = sp.heap_;   in.cap_ = sp.cap_;
            sp.heap_ = nullptr;    sp.cap_ = N;
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
// catch it. These fail the BUILD instead. They cover the two instantiations this tree actually uses —
// <uint32_t,2> is also <NodeId,2>, since NodeId is uint32_t; naming it that way keeps this header free of
// ripwire types so it stays vendorable.
//
// The `sizeof( void* ) != 8 ||` guard is not hedging: the numbers below are 64-bit-target numbers, and a
// pin that would be false on a 32-bit build should self-disable rather than lie.
static_assert( sizeof( void* ) != 8 || sizeof( svector<std::uint32_t, 2> ) == 24,
               "svector<uint32,2> must stay 24 B — 8 B of inl_, 8 B of heap_, 4+4 of sz_/cap_. The 8 B over "
               "ankerl's 16 is the price of a branch-free size(); if this fires, that trade changed." );
static_assert( sizeof( void* ) != 8 || alignof( svector<std::uint32_t, 2> ) == 8, "pointer-aligned, not over-aligned" );
static_assert( sizeof( void* ) != 8 || sizeof( svector<std::uint64_t, 2> ) == 32, "the 8-byte-element shape (varSpans' pair<uint32,uint32>) is 32 B" );

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

#pragma once

// svector.h — rw::svector: a small-vector with N INLINE slots that spills to the heap only past N.
//
// WHY THIS EXISTS ALONGSIDE the vendored martinus/svector (third_party/svector.h, ankerl::svector):
// it's purpose-built for the ONE shape ripwire leans on hardest — a `Map<K, svector<V,N>>` of many tiny
// id-lists (byName / shard maps): WRITE-ONCE during the parse/merge, then READ-HOT during resolve.
//
//   • build win (shared with martinus): the N small lists that would each malloc become inline — one fewer
//     heap allocation per collection, no pointer-chase to the payload.
//   • read win (the differentiator): size() is `return sz_` — BRANCH-FREE. martinus packs its size into the
//     SVO buffer to reach 16 B, so its size() branches on is_direct(); on a 4M-read hot loop that branch
//     costs ~6 ms. We keep an explicit sz_ field instead: sizeof(svector<uint32,2>) = 24 B (same as
//     std::vector), 8 B more than martinus — we spend those 8 bytes to make the hot read branch-free.
//
// Measured 3-way (std::vector vs martinus vs this) in bench/bench_svector3.cpp: for the read-hot map value,
// this wins ~25% over martinus and ~45% over std::vector. Prefer martinus when compactness matters, for
// general standalone use, or when the value is iterated (begin()/end() branch in BOTH) more than size()'d.
//
// Hand-rolled RAII (raw new[]/delete[], per house style), move + copy. Tuned for trivially-copyable V
// (ids); fine for any movable V.

#include <cstdint>
#include <utility>

namespace rw
{

template <class T, std::uint32_t N>
class svector
{
    T             inl_[ N ];
    T*            heap_ = nullptr;        // non-null ⇒ payload is on the heap (cap_ > N)
    std::uint32_t sz_   = 0;
    std::uint32_t cap_  = N;

    T*       buf()       noexcept { return heap_ ? heap_ : inl_; }
    const T* buf() const noexcept { return heap_ ? heap_ : inl_; }
    void grow( std::uint32_t need )
    {
        std::uint32_t nc = cap_ * 2;
        if( nc < need )
        {
            nc = need;
        }
        T* nh = new T[ nc ];
        for( std::uint32_t i = 0; i < sz_; ++i )
        {
            nh[i] = std::move( buf()[i] );
        }
        delete[] heap_;  heap_ = nh;  cap_ = nc;
    }

public:
    svector() noexcept = default;
    ~svector() { delete[] heap_; }

    svector( const svector& o )
    {
        reserve( o.sz_ );
        for( std::uint32_t i = 0; i < o.sz_; ++i )
        {
            buf()[i] = o.buf()[i];
        }
        sz_ = o.sz_;
    }
    svector( svector&& o ) noexcept
    {
        if( o.heap_ ) { heap_ = o.heap_; cap_ = o.cap_; sz_ = o.sz_; o.heap_ = nullptr; o.cap_ = N; o.sz_ = 0; }
        else
        {
            for( std::uint32_t i = 0; i < o.sz_; ++i )
            {
                inl_[i] = std::move( o.inl_[i] );
            }
            sz_ = o.sz_;
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
        if( o.heap_ ) { heap_ = o.heap_; cap_ = o.cap_; sz_ = o.sz_; o.heap_ = nullptr; o.cap_ = N; o.sz_ = 0; }
        else
        {
            heap_ = nullptr;
            cap_ = N;
            sz_ = o.sz_;
            for( std::uint32_t i = 0; i < o.sz_; ++i )
            {
                inl_[i] = std::move( o.inl_[i] );
            }
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
        for( std::uint32_t i = 0; i < o.sz_; ++i )
        {
            buf()[i] = o.buf()[i];
        }
        sz_ = o.sz_;
        return *this;
    }

    void reserve( std::uint32_t need )
    {
        if( need > cap_ )
        {
            grow( need );
        }
    }
    // self-alias safe: if v points into this vector, grow() would free the old heap before the copy —
    // save a local copy first on the grow path (the common non-growing path stays a single assignment).
    void          push_back( const T& v ) { if( sz_ == cap_ ) { T saved = v; grow( sz_ + 1 ); buf()[ sz_++ ] = std::move( saved ); return; } buf()[ sz_++ ] = v; }
    std::uint32_t size() const noexcept { return sz_; }            // branch-free — the whole point (see header)
    bool          spilled() const noexcept { return heap_ != nullptr; }
    T*            begin()       noexcept { return buf(); }
    T*            end()         noexcept { return buf() + sz_; }
    const T*      begin() const noexcept { return buf(); }
    const T*      end()   const noexcept { return buf() + sz_; }
};

}   // namespace rw

// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

#pragma once

// sparseCsr<T> — compressed-sparse-row matrix + matrix-free operators for the math library.
//
// Companion to matrixDyn<T> (dense). This is the SPARSE substrate that graph ranking runs
// on: a CSR matrix, a matrix-free SpMV (apply), and a generic power-iteration
// dominantEigenvector(). ripwire's mixed-precision PageRank kernel lives in src/pagerank.cpp.
//
// Discipline (same as matrixDyn):
//   * DOD storage: three owning, contiguous, 128-B-aligned SoA arrays — rowOffsets[rows+1],
//     colIndices[nnz], values[nnz]. 32-bit indices (handles, not pointers). Move-only.
//   * NEON on the SpMV: the gather x[col[k]] is scalarised (Apple Silicon has no cheap
//     vector gather), but the multiply-accumulate is vectorised (vfmaq_f32) with a scalar
//     tail. float fast-path via if constexpr; any other T takes the scalar path.
//   * DETERMINISTIC block-reduce for every global sum (dangling mass, norms, residual):
//     fixed-size blocks, partials summed in canonical block order. Bit-stable run-to-run —
//     load-bearing because PageRank output is a sorted top-K with no tolerance band.
//
// Layering: depends ONLY on fastmath.h (VERIFY + cache-line const). NOT infrastucture/
// (infra depends on math → a cycle). Parallelism is therefore INJECTED by the caller: the
// SpMV is embarrassingly parallel by row and the reductions are block-structured for a
// deterministic parallel reduce (compute partials[block] in parallel, sum them in block
// order → identical result). math/ stays dependency-free + single-threaded here; ripwire
// drops DispatchSystem::parallelFor over the row/block ranges.

#include "fastmath.h"   // VERIFY / fastmath::hardware_constructive_interference_size

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <new>
#include <type_traits>
#include <utility>

#if defined( __ARM_NEON ) || defined( __ARM_NEON__ )
    #include <arm_neon.h>
    #define SPARSECSR_NEON 1
#else
    #define SPARSECSR_NEON 0
#endif

namespace csrdetail
{
    inline constexpr std::align_val_t kAlign{ fastmath::hardware_constructive_interference_size };

    template<class U> inline U*   anew( std::size_t n ) { return n ? static_cast<U*>( ::operator new( n * sizeof( U ), kAlign ) ) : nullptr; }
    template<class U> inline void adel( U* p ) noexcept { if( p ) ::operator delete( p, kAlign ); }

    // one SpMV row:  Σ_k val[k] * x[col[k]]   (vectorised FMA over a scalarised gather)
    template<class T>
    inline T spmvRow( const T* val, const std::uint32_t* col, const T* x, std::size_t n ) noexcept
    {
        T acc = T( 0 );
        std::size_t k = 0;

#if SPARSECSR_NEON
        if constexpr ( std::is_same_v<T, float> )
        {
            float32x4_t v = vdupq_n_f32( 0.f );
            for( ; k + 4 <= n; k += 4 )
            {
                const float g[4] = { x[col[k]], x[col[k + 1]], x[col[k + 2]], x[col[k + 3]] };  // gather
                v = vfmaq_f32( v, vld1q_f32( val + k ), vld1q_f32( g ) );
            }
            acc = vaddvq_f32( v );
        }
#endif
        for( ; k < n; ++k )
            acc += val[k] * x[col[k]];
        return acc;
    }

    // deterministic Σ a[i]*b[i] over [0,n): fixed blocks, partials added in canonical order.
    // (Pass a==b for Σ a[i]².) NEON within a block; the block split is what a parallel
    // reduce would partition on, so the numeric result is independent of thread count.
    template<class T>
    inline T blockReduceDot( const T* a, const T* b, std::size_t n ) noexcept
    {
        constexpr std::size_t kBlock = 1024;
        T total = T( 0 );

        for( std::size_t base = 0; base < n; base += kBlock )
        {
            const std::size_t end = ( base + kBlock < n ) ? base + kBlock : n;
            T part = T( 0 );
            std::size_t i = base;

#if SPARSECSR_NEON
            if constexpr ( std::is_same_v<T, float> )
            {
                float32x4_t v = vdupq_n_f32( 0.f );
                for( ; i + 4 <= end; i += 4 )
                    v = vfmaq_f32( v, vld1q_f32( a + i ), vld1q_f32( b + i ) );
                part = vaddvq_f32( v );
            }
#endif
            for( ; i < end; ++i )
                part += a[i] * b[i];

            total += part;   // partials folded in increasing-block order → deterministic
        }
        return total;
    }

    template<class T>
    inline void scaleVec( T* x, T s, std::size_t n ) noexcept
    {
        std::size_t i = 0;
#if SPARSECSR_NEON
        if constexpr ( std::is_same_v<T, float> )
        {
            const float32x4_t vs = vdupq_n_f32( s );
            for( ; i + 4 <= n; i += 4 )
                vst1q_f32( x + i, vmulq_f32( vld1q_f32( x + i ), vs ) );
        }
#endif
        for( ; i < n; ++i )
            x[i] *= s;
    }
}

// ---- sparseCsr<T> -----------------------------------------------------------------------
template<class T>
class sparseCsr
{
public:

    sparseCsr() noexcept = default;

    // allocate the three arrays; caller fills rowOffsets()/colIndices()/values().
    sparseCsr( std::size_t rows, std::size_t cols, std::size_t nnz )
    : m_rows( rows ), m_cols( cols ), m_nnz( nnz )
    {
        m_rowOff = csrdetail::anew<std::uint32_t>( rows + 1 );
        m_col    = csrdetail::anew<std::uint32_t>( nnz );
        m_val    = csrdetail::anew<T>( nnz );
        if( m_rowOff )
            std::memset( m_rowOff, 0, ( rows + 1 ) * sizeof( std::uint32_t ) );
    }

    ~sparseCsr()
    {
        csrdetail::adel( m_rowOff );
        csrdetail::adel( m_col );
        csrdetail::adel( m_val );
    }

    sparseCsr( sparseCsr&& o ) noexcept
    : m_rowOff( o.m_rowOff ), m_col( o.m_col ), m_val( o.m_val ),
      m_rows( o.m_rows ), m_cols( o.m_cols ), m_nnz( o.m_nnz )
    {
        o.m_rowOff = nullptr; o.m_col = nullptr; o.m_val = nullptr;
        o.m_rows = o.m_cols = o.m_nnz = 0;
    }

    sparseCsr& operator=( sparseCsr&& o ) noexcept
    {
        if( this != &o )
        {
            csrdetail::adel( m_rowOff ); csrdetail::adel( m_col ); csrdetail::adel( m_val );
            m_rowOff = o.m_rowOff; m_col = o.m_col; m_val = o.m_val;
            m_rows = o.m_rows; m_cols = o.m_cols; m_nnz = o.m_nnz;
            o.m_rowOff = nullptr; o.m_col = nullptr; o.m_val = nullptr;
            o.m_rows = o.m_cols = o.m_nnz = 0;
        }
        return *this;
    }

    sparseCsr( const sparseCsr& )            = delete;
    sparseCsr& operator=( const sparseCsr& ) = delete;

    // -- shape + raw arrays (mutable for the builder, const for the operators) --
    std::size_t rows() const noexcept { return m_rows; }
    std::size_t cols() const noexcept { return m_cols; }
    std::size_t nnz()  const noexcept { return m_nnz; }

    std::uint32_t* rowOffsets()       noexcept { return m_rowOff; }
    std::uint32_t* colIndices()       noexcept { return m_col; }
    T*             values()           noexcept { return m_val; }
    const std::uint32_t* rowOffsets() const noexcept { return m_rowOff; }
    const std::uint32_t* colIndices() const noexcept { return m_col; }
    const T*             values()     const noexcept { return m_val; }

    // y = A * x   (matrix-free SpMV). y, x caller-owned: |x|=cols, |y|=rows.
    void applyInto( const T* x, T* y ) const noexcept
    {
        if constexpr ( std::is_same_v<T, float> )
        {
            // SpMV is gather-bound. A scalar body with 8 INDEPENDENT accumulators keeps 8
            // random x[col[k]] misses in flight (memory-level parallelism) — it beats the NEON
            // gather, which serialises one FMA chain behind a store→load round-trip to build
            // each float32x4 (perf-tournament winner). Two software prefetches pull future
            // gather targets in early; the m_nnz guard keeps the m_col read in bounds (ASan-safe).
            constexpr std::size_t PF = 32;
            for( std::size_t i = 0; i < m_rows; ++i )
            {
                std::size_t       k = m_rowOff[i];
                const std::size_t e = m_rowOff[i + 1];

                float a0=0, a1=0, a2=0, a3=0, b0=0, b1=0, b2=0, b3=0;
                for( ; k + 8 <= e; k += 8 )
                {
                    if( k + PF + 4 < m_nnz )
                    {
                        __builtin_prefetch( &x[ m_col[ k + PF     ] ], 0, 0 );
                        __builtin_prefetch( &x[ m_col[ k + PF + 4 ] ], 0, 0 );
                    }
                    a0 += m_val[k  ] * x[ m_col[k  ] ];   a1 += m_val[k+1] * x[ m_col[k+1] ];
                    a2 += m_val[k+2] * x[ m_col[k+2] ];   a3 += m_val[k+3] * x[ m_col[k+3] ];
                    b0 += m_val[k+4] * x[ m_col[k+4] ];   b1 += m_val[k+5] * x[ m_col[k+5] ];
                    b2 += m_val[k+6] * x[ m_col[k+6] ];   b3 += m_val[k+7] * x[ m_col[k+7] ];
                }
                float acc = ( ( a0 + a1 ) + ( a2 + a3 ) ) + ( ( b0 + b1 ) + ( b2 + b3 ) );
                for( ; k < e; ++k ) acc += m_val[k] * x[ m_col[k] ];
                y[i] = acc;
            }
        }
        else
        {
            for( std::size_t i = 0; i < m_rows; ++i )
            {
                const std::uint32_t b = m_rowOff[i];
                const std::uint32_t e = m_rowOff[i + 1];
                y[i] = csrdetail::spmvRow( m_val + b, m_col + b, x, std::size_t( e - b ) );
            }
        }
    }

private:

    std::uint32_t* m_rowOff = nullptr;   // size rows+1
    std::uint32_t* m_col    = nullptr;   // size nnz
    T*             m_val    = nullptr;   // size nnz
    std::size_t    m_rows = 0, m_cols = 0, m_nnz = 0;
};

// ---- matrix-free operators (reuse applyInto + the deterministic block-reduce) -----------

// Power iteration for the principal eigenpair of a SQUARE A whose dominant eigenvalue is
// positive (the graph / non-negative case — Perron–Frobenius). x is in/out (caller-owned,
// size N, must start nonzero). Returns the dominant eigenvalue (Rayleigh quotient). The L2
// norm + residual use the deterministic block-reduce, so the result is bit-stable.
template<class T>
inline T dominantEigenvector( const sparseCsr<T>& A, T* x, T tol = T( 1e-6 ), unsigned maxIter = 1000 )
{
    VERIFY( A.rows() == A.cols() );
    const std::size_t N = A.rows();
    if( N == 0 )
        return T( 0 );

    T* y = csrdetail::anew<T>( N );

    {
        const T nrm = std::sqrt( csrdetail::blockReduceDot( x, x, N ) );
        VERIFY( nrm > T( 0 ) );
        csrdetail::scaleVec( x, T( 1 ) / nrm, N );
    }

    T lambda = T( 0 );
    for( unsigned it = 0; it < maxIter; ++it )
    {
        A.applyInto( x, y );                                   // y = A x

        lambda = csrdetail::blockReduceDot( y, x, N );         // Rayleigh xᵀAx (x is unit)
        const T ynrm = std::sqrt( csrdetail::blockReduceDot( y, y, N ) );
        VERIFY( ynrm > T( 0 ) );
        const T inv = T( 1 ) / ynrm;

        T resid = T( 0 );                                      // ‖y/‖y‖ − x‖₂, then update x
        for( std::size_t i = 0; i < N; ++i )
        {
            const T nx = y[i] * inv;
            const T d  = nx - x[i];
            resid += d * d;
            x[i] = nx;
        }
        if( std::sqrt( resid ) < tol )
            break;
    }

    csrdetail::adel( y );
    return lambda;
}

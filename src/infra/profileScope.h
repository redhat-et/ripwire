// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  profileScope.h
//
//  Header-only scope profiler tuned for Apple ARM64.
//
//  USAGE
//    PROFILE_SCOPE();                          // measure the enclosing scope
//    PROFILE_SCOPE_DESCRIBE( "phase B2-b" );   // ... with a label
//    prof::report();  (or PROFILE_REPORT();)   // print; also auto-prints at exit
//
//  WHY IT IS SHAPED THIS WAY
//    * Clock: reads CNTVCT_EL0 directly (a constant 24 MHz system counter on
//      Apple Silicon — immune to P/E migration and DVFS). Raw ticks only on the
//      hot path; the tick->ns multiply happens once, at print time.
//    * Hot path: a per-site `thread_local Record*` resolves the (thread x site)
//      accumulator exactly once per thread per site. After that it is a guard
//      check + pointer load + two counter reads + a few relaxed stores. No hash,
//      no lock, no allocation on the hot path.
//    * Counters are single-writer relaxed atomics: only the owning thread writes
//      a Record; the reporter reads it. Relaxed load/store compiles to plain
//      LDR/STR on ARM64, so this is "defined behaviour for the concurrent
//      reader" at ~zero cost over plain ints.
//    * Lifetime: per-thread data is heap-owned by a leaked registry core, so a
//      cached Record* (and a thread retiring at exit) is always safe — a
//      use-after-free is structurally impossible. Threads that exit RETIRE their
//      data (preserved for the report); the reporter frees retired worker blocks
//      at exit and WARNS (does not crash) about threads still running.
//
//  This is a from-scratch replacement for the std::function-based log/profiler.h
//  and realises that file's three TODOs: nested/tree-ordered output, a
//  compile-time site table, and sort-by-longest.
//

#pragma once

// ---- configuration (override by #define-ing before the include) -------------
#ifndef PROFILE_ENABLED
  // Debug builds profile; release builds (NDEBUG) collapse every macro to
  // ((void)0). Override with -DPROFILE_ENABLED=1 to profile a Release binary.
  #if defined( NDEBUG )
    #define PROFILE_ENABLED 0
  #else
    #define PROFILE_ENABLED 1      // 0 -> every macro is ((void)0), zero codegen
  #endif
#endif
#ifndef PROFILE_TREE
  #define PROFILE_TREE 1           // capture parent scope for tree-ordered output
#endif
#ifndef PROFILE_BARRIER
  #define PROFILE_BARRIER 0        // isb before the counter read (see note below)
#endif
#ifndef PROFILE_AUTO_REPORT
  #define PROFILE_AUTO_REPORT 1    // print a report at static destruction
#endif
#ifndef PROFILE_PMC
  // Sample Apple Silicon hardware performance counters (cycles, instructions,
  // branch/cache misses) per scope, IN ADDITION to the CNTVCT wall time. Defaults
  // on wherever profiling is on, but self-disables at runtime unless the process
  // is privileged (root or the com.apple.private.kperf entitlement) — when it
  // can't arm the counters the report silently drops the count columns and shows
  // timing only (see profilePmc.h). Heavier hot path when active (two kpc reads
  // per scope). Set -DPROFILE_PMC=0 to compile it out entirely.
  #define PROFILE_PMC PROFILE_ENABLED
#endif

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <atomic>
#include <mutex>
#include <vector>
#include <algorithm>
#include <pthread.h>

#include "platform.h"              // ALWAYS_INLINE, fastmath::min/max (integral), cache-line size
#include "profilePmc.h"            // prof::pmc — optional Apple Silicon HW counters

#if !( defined( __aarch64__ ) || defined( __arm64__ ) )
  #include <chrono>               // portable fallback clock for non-ARM dev/CI
#endif

namespace prof
{

// single-writer counters: relaxed is enough — see file header
inline constexpr std::memory_order rlx = std::memory_order_relaxed;

// Apple Silicon L1d lines are 128 B; pad cross-thread hot storage to this
inline constexpr std::size_t kCacheLine = fastmath::hardware_destructive_interference_size;

// ============================================================================
// detail: clock + compile/print-time string helpers
// ============================================================================
namespace detail
{

// CNTVCT_EL0 read. PROFILE_BARRIER adds an `isb` to pin the read against
// out-of-order execution. It is OFF by default: the 24 MHz counter already
// quantises to ~41.7 ns (wider than the OoO window an isb closes), and the isb
// adds a SYSTEMATIC per-read bias that averaging cannot remove — whereas OoO
// error is random and averages out over the many calls a profiler aggregates.
ALWAYS_INLINE uint64_t now_ticks() noexcept
{
#if defined( __aarch64__ ) || defined( __arm64__ )
    uint64_t t;
  #if PROFILE_BARRIER
    asm volatile( "isb\n\tmrs %0, cntvct_el0" : "=r"( t ) :: "memory" );
  #else
    asm volatile( "mrs %0, cntvct_el0" : "=r"( t ) );
  #endif
    return t;
#else
    return (uint64_t) std::chrono::duration_cast<std::chrono::nanoseconds>(
               std::chrono::steady_clock::now().time_since_epoch() ).count();
#endif
}

inline uint64_t tick_hz() noexcept
{
#if defined( __aarch64__ ) || defined( __arm64__ )
    uint64_t f;
    asm volatile( "mrs %0, cntfrq_el0" : "=r"( f ) );   // 24'000'000 on Apple Silicon
    return f;
#else
    return 1'000'000'000ull;                            // fallback ticks are already ns
#endif
}

inline double ns_per_tick() noexcept
{
    static const double k = 1.0e9 / double( tick_hz() );
    return k;
}

// measured cost of the matched counter-read pair every scope pays (lower bound)
inline uint64_t overhead_ticks() noexcept
{
    static const uint64_t v = []() noexcept
    {
        uint64_t best = UINT64_MAX;
        for( int i = 0; i < 2048; ++i )
        {
            const uint64_t a = now_ticks();
            const uint64_t b = now_ticks();
            best = fastmath::min( best, b - a );
        }
        return best;
    }();
    return v;
}

// strip the directory at compile time; the result points into the __FILE__ literal
constexpr const char* basename( const char* path ) noexcept
{
    const char* base = path;
    for( const char* p = path; *p != '\0'; ++p )
        if( *p == '/' )
            base = p + 1;
    return base;
}

// find the parameter-list '(' in a __PRETTY_FUNCTION__, skipping operator()'s parens
inline std::size_t param_paren( const char* s, std::size_t n ) noexcept
{
    for( std::size_t i = 0; i < n; ++i )
    {
        if( s[ i ] != '(' )
            continue;

        std::size_t j = i;
        while( j > 0 && s[ j - 1 ] == ' ' )
            --j;

        const bool isOperator = j >= 8 && std::strncmp( s + j - 8, "operator", 8 ) == 0;
        if( !isOperator )
            return i;

        // skip the operator's own parens, then keep scanning for the real list
        int depth = 0;
        for( ; i < n; ++i )
        {
            if( s[ i ] == '(' )           ++depth;
            else if( s[ i ] == ')' && --depth == 0 ) break;
        }
    }
    return n;
}

// trim "ret-type Scope::Class::name(args) qualifiers" down to "Scope::Class::name"
inline void trim_pretty( const char* pretty, char* out, std::size_t outsz ) noexcept
{
    const std::size_t n     = std::strlen( pretty );
    const std::size_t paren = param_paren( pretty, n );

    // walk left from the param list to the last top-level space (skips return type)
    int         depth = 0;
    std::size_t start = 0;
    for( std::size_t k = paren; k-- > 0; )
    {
        const char c = pretty[ k ];
        if( c == ')' || c == '>' )            ++depth;
        else if( c == '(' || c == '<' )       --depth;
        else if( c == ' ' && depth == 0 ) { start = k + 1; break; }
    }

    std::size_t len = paren - start;
    if( len >= outsz )
        len = outsz - 1;
    std::memcpy( out, pretty + start, len );
    out[ len ] = '\0';
}

}   // namespace detail

// ============================================================================
// Site — one immutable, constant-initialised descriptor per PROFILE_SCOPE site
// ============================================================================
struct Site
{
    const char* pretty;        // __PRETTY_FUNCTION__ (trimmed at print time)
    const char* file;          // basename( __FILE__ )
    const char* description;   // PROFILE_SCOPE_DESCRIBE text, or nullptr
    int         line;
};

// ============================================================================
// Record — accumulator for one (thread x site). Written only by the owning
// thread; read by the reporter. Lives in a 128-aligned arena block (below).
// ============================================================================
struct Record
{
    // ---- hot: owner writes (relaxed), reporter reads (relaxed) ----
    std::atomic<uint64_t> calls    { 0 };
    std::atomic<uint64_t> total    { 0 };           // ticks, top-level inclusive
    std::atomic<uint64_t> minTicks { UINT64_MAX };
    std::atomic<uint64_t> maxTicks { 0 };

#if PROFILE_PMC
    // per-event hardware-counter totals; top-level inclusive, exactly like `total`
    std::atomic<uint64_t> events[ prof::pmc::kMaxEvents ] {};
#endif

    // ---- identity / tree ----
    const Site*              site   { nullptr };
    std::atomic<const Site*> parent { nullptr };     // last-seen caller (PROFILE_TREE)

    // ---- owner-private scratch (reporter never touches these) ----
    uint64_t startTicks { 0 };
#if PROFILE_PMC
    prof::pmc::Snapshot startEvents {};              // counters at the outermost enter
#endif
    uint32_t depth      { 0 };                       // recursion guard

    ALWAYS_INLINE void enter( uint64_t t ) noexcept
    {
        if( depth++ == 0 )                           // only the outermost frame times
            startTicks = t;
    }

    ALWAYS_INLINE void leave( uint64_t t ) noexcept
    {
        if( --depth != 0 )
            return;

        const uint64_t d = t - startTicks;
        calls   .store( calls.load( rlx ) + 1, rlx );
        total   .store( total.load( rlx ) + d, rlx );
        maxTicks.store( fastmath::max( maxTicks.load( rlx ), d ), rlx );
        minTicks.store( fastmath::min( minTicks.load( rlx ), d ), rlx );
    }

#if PROFILE_PMC
    // fold (end - startEvents) into the per-event totals — outermost frame only,
    // mirroring leave()'s tick accounting. Counters are monotonic, so no clamp.
    ALWAYS_INLINE void addEvents( const prof::pmc::Snapshot& end ) noexcept
    {
        for( unsigned i = 0; i < prof::pmc::kMaxEvents; ++i )
            events[ i ].store( events[ i ].load( rlx ) + ( end.values[ i ] - startEvents.values[ i ] ), rlx );
    }
#endif
};

// ============================================================================
// RecordArena — pointer-stable, raw new/delete, 128-aligned blocks. A cached
// Record* must stay valid for the program's life, so records never move.
// ============================================================================
class RecordArena
{
public:
    RecordArena()                                = default;
    RecordArena( const RecordArena& )            = delete;
    RecordArena& operator=( const RecordArena& ) = delete;

    ~RecordArena()
    {
        for( Block* b : m_blocks )
            delete b;
    }

    Record* alloc()
    {
        if( m_next == kBlock )
        {
            m_blocks.push_back( new Block() );       // Block is over-aligned -> aligned new
            m_next = 0;
        }
        return &m_blocks.back()->records[ m_next++ ];
    }

private:
    static constexpr std::size_t kBlock = 64;

    struct Block
    {
        alignas( kCacheLine ) Record records[ kBlock ];
    };

    std::vector<Block*> m_blocks;
    std::size_t         m_next { kBlock };           // force the first alloc to push
};

// ============================================================================
// ThreadData — one heap node per thread, owned by the registry. The hot path
// never touches this after acquire(); the mutex guards add/snapshot only.
// ============================================================================
struct alignas( kCacheLine ) ThreadData
{
    ThreadData() noexcept
    {
        pthread_threadid_np( nullptr, &tid );
        name[ 0 ] = '\0';
        pthread_getname_np( pthread_self(), name, sizeof( name ) );
        isMain = pthread_main_np() != 0;
    }

    // once per (thread, site); rare — never on the hot path
    Record* add_record( const Site* s )
    {
        std::lock_guard<std::mutex> lock( mtx );
        Record* r = arena.alloc();
        r->site = s;
        records.push_back( r );
        return r;
    }

    uint64_t          tid { 0 };
    char              name[ 32 ];
    bool              isMain { false };
    std::atomic<bool> retired { false };

    std::mutex           mtx;
    RecordArena          arena;
    std::vector<Record*> records;
};

// ============================================================================
// Registry — the global directory of thread nodes. Its storage is intentionally
// leaked (never destroyed) so retire() is safe even during static destruction.
// ============================================================================
class Registry
{
public:
    ThreadData* create()
    {
        ThreadData* d = new ThreadData();
        std::lock_guard<std::mutex> lock( m_mtx );
        m_threads.push_back( d );
        return d;
    }

    // thread exit: keep the data, just mark it. release pairs with teardown's acquire
    void retire( ThreadData* d ) noexcept
    {
        d->retired.store( true, std::memory_order_release );
    }

    // copy every thread's rows out under the locks; the sink runs while locked
    template<class Sink>
    void snapshot( Sink&& sink )
    {
        std::lock_guard<std::mutex> lock( m_mtx );
        for( ThreadData* d : m_threads )
        {
            std::lock_guard<std::mutex> tlock( d->mtx );
            sink( d );
        }
    }

    // at exit: free retired WORKER nodes (owner gone -> safe), warn about live
    // ones (a thread never joined), never free main or the core
    void teardown() noexcept
    {
        std::lock_guard<std::mutex> lock( m_mtx );
        for( ThreadData*& d : m_threads )
        {
            if( d == nullptr || d->isMain )
                continue;

            if( d->retired.load( std::memory_order_acquire ) )
            {
                delete d;
                d = nullptr;
            }
            else
            {
                std::fprintf( stderr,
                    "PROFILE WARNING: thread %llu (%s) still running at exit — join it "
                    "before main() returns; leaking its profile data to stay safe\n",
                    (unsigned long long) d->tid, d->name[ 0 ] ? d->name : "unnamed" );
            }
        }
    }

private:
    std::mutex               m_mtx;
    std::vector<ThreadData*> m_threads;
};

inline Registry& registry() noexcept
{
    static Registry* core = new Registry();          // leaked on purpose; see header
    return *core;
}

void report();                                       // fwd decl; defined below

// reporter whose destructor fires at static destruction. Constructed on first
// thread registration so its destructor is guaranteed to run.
struct Reporter
{
    ~Reporter()
    {
#if PROFILE_AUTO_REPORT
        report();
#endif
        registry().teardown();
    }
};

inline Reporter& reporter() noexcept
{
    static Reporter r;
    return r;
}

// ============================================================================
// thread-local plumbing
// ============================================================================
#if PROFILE_TREE
inline thread_local Record* tls_current = nullptr;   // active scope on this thread
#endif

namespace detail
{

struct ThreadDataHandle
{
    ThreadData* data;

    ThreadDataHandle() : data( registry().create() )
    {
        reporter();                                  // ensure the exit report is wired
#if PROFILE_PMC
        prof::pmc::ensure_thread_counting();         // load + arm HW counters for this thread
#endif
    }

    ~ThreadDataHandle()
    {
        registry().retire( data );
    }
};

inline ThreadData& tls_data() noexcept
{
    thread_local ThreadDataHandle handle;            // ctor registers, dtor retires
    return *handle.data;
}

inline Record* tls_acquire( const Site* s )          // first touch per (thread, site)
{
    return tls_data().add_record( s );
}

}   // namespace detail

// ============================================================================
// ScopedTimer — RAII. Tree bookkeeping is excluded from the measured interval
// (start is read AFTER it; the end is read BEFORE the restore).
// ============================================================================
class ScopedTimer
{
public:
    ALWAYS_INLINE explicit ScopedTimer( Record* rec ) noexcept
        : m_rec( rec )
    {
#if PROFILE_TREE
        m_prev = tls_current;
        tls_current = rec;
        if( m_prev != rec )
            rec->parent.store( m_prev ? m_prev->site : nullptr, rlx );
#endif
#if PROFILE_PMC
        // counters read BEFORE the (tight) start tick, so the tick interval excludes
        // the kpc-read cost; only the outermost frame keeps the start snapshot.
        const bool          pmc = prof::pmc::active();
        prof::pmc::Snapshot s;
        if( pmc )
            s = prof::pmc::read();
#endif
        rec->enter( detail::now_ticks() );
#if PROFILE_PMC
        if( pmc && rec->depth == 1 )
            rec->startEvents = s;
#endif
    }

    ALWAYS_INLINE ~ScopedTimer() noexcept
    {
#if PROFILE_PMC
        const bool outer = prof::pmc::active() && m_rec->depth == 1;   // closing the outermost frame
#endif
        const uint64_t t = detail::now_ticks();                       // tight end tick, before any kpc read
#if PROFILE_PMC
        prof::pmc::Snapshot e;
        if( outer )
            e = prof::pmc::read();
#endif
        m_rec->leave( t );
#if PROFILE_PMC
        if( outer )
            m_rec->addEvents( e );
#endif
#if PROFILE_TREE
        tls_current = m_prev;
#endif
    }

    ScopedTimer()                                = delete;
    ScopedTimer( const ScopedTimer& )            = delete;
    ScopedTimer( ScopedTimer&& )                 = delete;
    ScopedTimer& operator=( const ScopedTimer& ) = delete;
    ScopedTimer& operator=( ScopedTimer&& )      = delete;

private:
    Record* m_rec;
#if PROFILE_TREE
    Record* m_prev { nullptr };
#endif
};

// ============================================================================
// Bench timer — a minimal, standalone A/B timer for micro-benchmarks (e.g. the
// bench/ radix and container harnesses). Unlike ScopedTimer it registers no Site,
// never touches the registry, builds no call tree, and does not guard recursion: it just folds wall
// time into a caller-owned Accum read back numerically. Single-thread use.
// ============================================================================
struct Accum
{
    uint64_t ticks { 0 };
    uint64_t calls { 0 };

    void     reset()       noexcept { ticks = 0; calls = 0; }
    double   ms()    const noexcept { return double( ticks ) * detail::ns_per_tick() * 1e-6; }
    double   us()    const noexcept { return double( ticks ) * detail::ns_per_tick() * 1e-3; }
    uint64_t count() const noexcept { return calls; }
};

class BenchTimer
{
public:
    ALWAYS_INLINE explicit BenchTimer( Accum& a ) noexcept
        : m_acc( a ), m_start( detail::now_ticks() ) {}

    ALWAYS_INLINE ~BenchTimer() noexcept
    {
        m_acc.ticks += detail::now_ticks() - m_start;
        ++m_acc.calls;
    }

    BenchTimer()                               = delete;
    BenchTimer( const BenchTimer& )            = delete;
    BenchTimer( BenchTimer&& )                 = delete;
    BenchTimer& operator=( const BenchTimer& ) = delete;
    BenchTimer& operator=( BenchTimer&& )      = delete;

private:
    Accum&   m_acc;
    uint64_t m_start;
};

// ----------------------------------------------------------------------------
// Optimizer barriers for micro-benchmarks. Without these the compiler is free
// to delete a benchmarked loop whose results are never read (dead-store
// elimination) or hoist a loop-invariant computation out of the timed region —
// either way the measured time is meaningless. clobberMemory() is an empty asm
// that "may read/write all memory" — but on its own it does NOT help for a
// non-escaped local buffer: the compiler can prove the asm has no way to reach
// an address it never saw, so it still elides/hoists. escape() closes that gap.
ALWAYS_INLINE void clobberMemory() noexcept
{
    asm volatile( "" : : : "memory" );
}

// escape() — feed a buffer's address INTO an (empty) asm that also clobbers
// memory. Once the pointer has visibly escaped, the compiler must assume the asm
// may read AND write through it, so it (a) emits any pending stores to the buffer
// before the barrier and (b) reloads from it afterwards. Call escape() on BOTH
// the input and the output of a benchmarked pass to stop the optimizer deleting
// the stores OR hoisting a loop-invariant computation out of the timed loop.
ALWAYS_INLINE void escape( const volatile void* p ) noexcept
{
    asm volatile( "" : : "r,m"( p ) : "memory" );
}

// Pin a single value so the compiler can't fold it away (the scalar twin of
// escape; use when there's a result register rather than a buffer).
template< class T >
ALWAYS_INLINE void doNotOptimize( T& value ) noexcept
{
    asm volatile( "" : "+r,m"( value ) : : "memory" );
}

// ============================================================================
// report() — snapshot (under locks) -> convert -> sort -> print. Cold path.
// ============================================================================
namespace detail
{

struct Row
{
    const Site* site;
    const Site* parent;
    uint64_t    calls;
    uint64_t    total;
    uint64_t    minT;
    uint64_t    maxT;
#if PROFILE_PMC
    uint64_t    events[ prof::pmc::kMaxEvents ] {};
#endif
};

struct ThreadSnap
{
    uint64_t         tid;
    char             name[ 32 ];
    bool             retired;
    bool             isMain;
    std::vector<Row> rows;
};

// number of PMC columns the table shows: 0 unless built with PROFILE_PMC AND the
// counters actually armed at runtime. Header and rows share it so they stay aligned.
inline unsigned events_shown() noexcept
{
#if PROFILE_PMC
    return prof::pmc::active() ? prof::pmc::event_count() : 0u;
#else
    return 0u;
#endif
}

// humanize a big counter total so the (wide) PMC columns stay narrow + scannable
inline void fmt_count( char* buf, std::size_t sz, uint64_t v ) noexcept
{
    if(      v < 1000ull )           std::snprintf( buf, sz, "%llu",  (unsigned long long) v );
    else if( v < 1000000ull )        std::snprintf( buf, sz, "%.2fk", double( v ) * 1e-3  );
    else if( v < 1000000000ull )     std::snprintf( buf, sz, "%.2fM", double( v ) * 1e-6  );
    else if( v < 1000000000000ull )  std::snprintf( buf, sz, "%.2fG", double( v ) * 1e-9  );
    else                             std::snprintf( buf, sz, "%.2fT", double( v ) * 1e-12 );
}

// shared column header — TIME block first (total/avg/min/max [+ %thread]), then
// the COUNT block (calls, then one column per armed PMC event), then the scope.
inline void print_header( bool tree )
{
    std::printf( "%12s %10s %10s %10s", "total ms", "avg us", "min us", "max us" );
    std::printf( " %7s", tree ? "%thread" : "" );
    std::printf( " %12s", "calls" );
    for( unsigned e = 0, n = events_shown(); e < n; ++e )
        std::printf( " %10s", prof::pmc::event_label( e ) );
    std::printf( "  %-40s %s\n", "scope", "(file:line)" );
}

inline void print_row( const char* indentedName, const char* loc,
                       const Row& r, double nspt, double pctParent )
{
    const double totalMs = double( r.total ) * nspt * 1e-6;
    const double avgUs    = r.calls ? double( r.total ) / double( r.calls ) * nspt * 1e-3 : 0.0;
    const double minUs    = ( r.minT == UINT64_MAX ? 0.0 : double( r.minT ) * nspt * 1e-3 );
    const double maxUs    = double( r.maxT ) * nspt * 1e-3;

    // time block first
    std::printf( "%12.3f %10.3f %10.3f %10.3f", totalMs, avgUs, minUs, maxUs );
    if( pctParent >= 0.0 ) std::printf( " %6.1f%%", pctParent );
    else                   std::printf( " %7s", "" );

    // then the count block: calls, then per-scope PMC totals (humanized)
    std::printf( " %12llu", (unsigned long long) r.calls );
#if PROFILE_PMC
    for( unsigned e = 0, n = events_shown(); e < n; ++e )
    {
        char b[ 16 ];
        fmt_count( b, sizeof( b ), r.events[ e ] );
        std::printf( " %10s", b );
    }
#endif

    std::printf( "  %-40s %s\n", indentedName, loc );
}

inline void name_and_loc( const Row& r, char* nameBuf, std::size_t nameSz,
                          char* locBuf, std::size_t locSz )
{
    char fn[ 96 ];
    trim_pretty( r.site->pretty, fn, sizeof( fn ) );
    if( r.site->description )
        std::snprintf( nameBuf, nameSz, "%s [%s]", fn, r.site->description );
    else
        std::snprintf( nameBuf, nameSz, "%s", fn );
    std::snprintf( locBuf, locSz, "%s:%d", r.site->file, r.site->line );
}

inline int index_of_site( const ThreadSnap& s, const Site* site )
{
    if( site == nullptr )
        return -1;
    for( std::size_t i = 0; i < s.rows.size(); ++i )
        if( s.rows[ i ].site == site )
            return int( i );
    return -1;
}

inline void print_tree_node( const ThreadSnap& s, const std::vector<std::vector<int>>& kids,
                             int i, int depth, double nspt, uint64_t threadTotal,
                             uint64_t parentTotal, std::vector<char>& visited )
{
    if( depth > 64 || visited[ i ] )
        return;
    visited[ i ] = 1;

    const Row& r = s.rows[ i ];

    char nameBuf[ 160 ];
    char loc[ 64 ];
    name_and_loc( r, nameBuf, sizeof( nameBuf ), loc, sizeof( loc ) );

    // One Record per (thread x site): a scope reached from more than one caller has
    // its time summed across all of them, but the tree can only hang it under the
    // last-seen parent. The tell is total > parent-total (impossible for a true single
    // child). Mark it '*' so the edge reads as approximate, not as a real >100% share.
    const bool multiParent = parentTotal && r.total > parentTotal;

    char indented[ 208 ];
    const int pad = depth * 2;
    std::snprintf( indented, sizeof( indented ), "%*s%s%s", pad, "", nameBuf,
                   multiParent ? " *" : "" );

    // Percentage is share of the thread's top-level time (a fixed, bounded denominator),
    // not child/parent -- the latter is meaningless once a child aggregates many callers.
    const double pct = threadTotal ? 100.0 * double( r.total ) / double( threadTotal ) : -1.0;
    print_row( indented, loc, r, nspt, pct );

    for( int c : kids[ i ] )
        print_tree_node( s, kids, c, depth + 1, nspt, threadTotal, r.total, visited );
}

// ----------------------------------------------------------------------------
// Aggregated (per-SITE, across all threads) view + machine-readable emission.
//
// The per-(thread x site) flat dump forced the reader to sum a scope's rows
// across every worker thread by hand (a fill spawns 100+ pool threads). These
// helpers collapse to ONE row per site and print the numbers you actually act on
// (IPC + misses-per-kilo-instruction) so no post-processing / awk is needed.
// ----------------------------------------------------------------------------

// One Row per unique site: sum calls/total/events, widen min/max. parent is
// dropped (this is a flat per-site view, not a tree).
inline std::vector<Row> aggregate_by_site( const std::vector<ThreadSnap>& snaps )
{
    std::vector<Row> agg;
    for( const ThreadSnap& s : snaps )
        for( const Row& r : s.rows )
        {
            Row* dst = nullptr;
            for( Row& a : agg ) if( a.site == r.site ) { dst = &a; break; }
            if( !dst ) { agg.push_back( r ); agg.back().parent = nullptr; continue; }
            dst->calls += r.calls;
            dst->total += r.total;
            dst->minT   = fastmath::min( dst->minT, r.minT );
            dst->maxT   = fastmath::max( dst->maxT, r.maxT );
#if PROFILE_PMC
            for( unsigned e = 0; e < prof::pmc::kMaxEvents; ++e ) dst->events[ e ] += r.events[ e ];
#endif
        }
    std::sort( agg.begin(), agg.end(),
               []( const Row& a, const Row& b ) { return a.total > b.total; } );
    return agg;
}

// Armed-event slot whose canonical alias == `alias` (e.g. "cycles",
// "instructions", "l1d-cache-misses", "branch-misses"); -1 if not armed.
inline int event_index( const char* alias )
{
#if PROFILE_PMC
    for( unsigned e = 0, n = events_shown(); e < n; ++e )
        if( std::strcmp( prof::pmc::event_name( e ), alias ) == 0 ) return ( int ) e;
#endif
    ( void ) alias;
    return -1;
}

// Derived-metric column indices, resolved once per report.
struct Derived
{
    int cyc = -1, inst = -1, l1d = -1, br = -1;
    bool ipc()      const { return cyc  >= 0 && inst >= 0; }
    bool l1dMpki()  const { return l1d  >= 0 && inst >= 0; }
    bool brMpki()   const { return br   >= 0 && inst >= 0; }
};
inline Derived resolve_derived()
{
    Derived d;
    d.cyc  = event_index( "cycles" );
    d.inst = event_index( "instructions" );
    d.l1d  = event_index( "l1d-cache-misses" );
    d.br   = event_index( "branch-misses" );
    return d;
}

inline void print_agg_header( const Derived& d )
{
    std::printf( "%12s %6s %12s", "total ms", "%tot", "calls" );
    if( d.ipc()     ) std::printf( " %6s", "IPC" );
    if( d.l1dMpki() ) std::printf( " %8s", "l1dMPKI" );
    if( d.brMpki()  ) std::printf( " %8s", "brMPKI" );
    for( unsigned e = 0, n = events_shown(); e < n; ++e )
        std::printf( " %10s", prof::pmc::event_label( e ) );
    std::printf( "  %-40s %s\n", "scope", "(file:line)" );
}

inline void print_agg_row( const Row& r, double nspt, double pctTotal, const Derived& d )
{
    std::printf( "%12.3f %5.1f%% %12llu",
                 double( r.total ) * nspt * 1e-6, pctTotal, (unsigned long long) r.calls );
#if PROFILE_PMC
    const double inst = ( d.inst >= 0 ) ? double( r.events[ d.inst ] ) : 0.0;
    if( d.ipc() )     { const double c = double( r.events[ d.cyc ] );
                        std::printf( " %6.2f", c > 0.0 ? inst / c : 0.0 ); }
    if( d.l1dMpki() )   std::printf( " %8.2f", inst > 0.0 ? 1000.0 * double( r.events[ d.l1d ] ) / inst : 0.0 );
    if( d.brMpki() )    std::printf( " %8.2f", inst > 0.0 ? 1000.0 * double( r.events[ d.br  ] ) / inst : 0.0 );
    for( unsigned e = 0, n = events_shown(); e < n; ++e )
    { char b[ 16 ]; fmt_count( b, sizeof( b ), r.events[ e ] ); std::printf( " %10s", b ); }
#else
    ( void ) d;
#endif
    char nameBuf[ 160 ]; char loc[ 64 ];
    name_and_loc( r, nameBuf, sizeof( nameBuf ), loc, sizeof( loc ) );
    std::printf( "  %-40s %s\n", nameBuf, loc );
}

// Fenced, tab-separated, one-row-per-site block with RAW integer counters +
// derived ratios — read it with `awk -F'\t'` / a spreadsheet, no parsing of the
// humanized table needed. Sentinels let a tool grab exactly this region.
inline void print_tsv( const std::vector<Row>& agg, double nspt, const Derived& d )
{
    std::printf( "\n#PROF_TSV_BEGIN\tone row per scope, aggregated across threads; counters are RAW integers\n" );
    std::printf( "scope\tfile\tline\tcalls\ttotal_ms" );
    if( d.ipc()     ) std::printf( "\tipc" );
    if( d.l1dMpki() ) std::printf( "\tl1d_mpki" );
    if( d.brMpki()  ) std::printf( "\tbr_mpki" );
    for( unsigned e = 0, n = events_shown(); e < n; ++e )
        std::printf( "\t%s", prof::pmc::event_name( e ) );
    std::printf( "\n" );

    for( const Row& r : agg )
    {
        char fn[ 96 ]; trim_pretty( r.site->pretty, fn, sizeof( fn ) );
        const char* scope = r.site->description ? r.site->description : fn;
        std::printf( "%s\t%s\t%d\t%llu\t%.3f", scope, r.site->file, r.site->line,
                     (unsigned long long) r.calls, double( r.total ) * nspt * 1e-6 );
#if PROFILE_PMC
        const double inst = ( d.inst >= 0 ) ? double( r.events[ d.inst ] ) : 0.0;
        if( d.ipc() )     { const double c = double( r.events[ d.cyc ] );
                            std::printf( "\t%.3f", c > 0.0 ? inst / c : 0.0 ); }
        if( d.l1dMpki() )   std::printf( "\t%.3f", inst > 0.0 ? 1000.0 * double( r.events[ d.l1d ] ) / inst : 0.0 );
        if( d.brMpki() )    std::printf( "\t%.3f", inst > 0.0 ? 1000.0 * double( r.events[ d.br  ] ) / inst : 0.0 );
        for( unsigned e = 0, n = events_shown(); e < n; ++e )
            std::printf( "\t%llu", (unsigned long long) r.events[ e ] );
#else
        ( void ) d;
#endif
        std::printf( "\n" );
    }
    std::printf( "#PROF_TSV_END\n" );
}

}   // namespace detail

inline void report()
{
    using namespace detail;

    std::vector<ThreadSnap> snaps;
    registry().snapshot( [ & ]( ThreadData* d )
    {
        ThreadSnap s;
        s.tid     = d->tid;
        std::memcpy( s.name, d->name, sizeof( s.name ) );
        s.retired = d->retired.load( std::memory_order_acquire );
        s.isMain  = d->isMain;

        s.rows.reserve( d->records.size() );
        for( Record* r : d->records )
        {
            Row row { r->site, r->parent.load( rlx ),
                      r->calls.load( rlx ), r->total.load( rlx ),
                      r->minTicks.load( rlx ), r->maxTicks.load( rlx ) };
#if PROFILE_PMC
            for( unsigned e = 0; e < prof::pmc::kMaxEvents; ++e )
                row.events[ e ] = r->events[ e ].load( rlx );
#endif
            s.rows.push_back( row );
        }
        snaps.push_back( std::move( s ) );
    } );

    const double   nspt = ns_per_tick();
    const uint64_t oh   = overhead_ticks();

    std::printf( "\n================================ PROFILE REPORT ================================\n" );
    std::printf( "clock %.3f MHz (%.3f ns/tick = counter resolution)   threads %zu\n",
                 double( tick_hz() ) * 1e-6, nspt, snaps.size() );
    if( oh )
        std::printf( "measurement overhead ~%.1f ns/scope (subtract from short scopes)\n", double( oh ) * nspt );
    else
        std::printf( "measurement overhead below counter resolution (<= %.1f ns/scope)\n", nspt );

#if PROFILE_PMC
    if( prof::pmc::active() )
    {
        std::printf( "PMC (per-scope HW counters, inclusive totals): " );
        for( unsigned e = 0, n = prof::pmc::event_count(); e < n; ++e )
            std::printf( "%s%s", e ? ", " : "", prof::pmc::event_name( e ) );
        std::printf( "\n" );
    }
    else
        std::printf( "PMC: unavailable (run privileged for HW counters; -DPROFILE_PMC=0 to compile out)\n" );
#endif

    // ---- aggregated (per-site, across threads) flat view + machine block ----
    // One row per scope instead of one per (thread x site): for a 100+-thread fill
    // you no longer hand-sum a scope across threads. Adds the act-on-it ratios
    // (IPC, MPKI) so no awk pass is needed, then a fenced raw-TSV block for tools.
    const Derived der = resolve_derived();

    // grandTotal = total top-level CPU across all threads (root scopes only) — the
    // %tot denominator; inclusive child scopes share that fixed bound.
    uint64_t grandTotal = 0;
    for( const ThreadSnap& s : snaps )
        for( std::size_t i = 0; i < s.rows.size(); ++i )
        {
            const int p = index_of_site( s, s.rows[ i ].parent );
            if( p < 0 || p == ( int ) i ) grandTotal += s.rows[ i ].total;   // a root
        }

    const std::vector<Row> agg = aggregate_by_site( snaps );

    std::printf( "\n-- hottest scopes (aggregated across %zu threads, by total) --------------------\n",
                 snaps.size() );
    std::printf( "( %%tot = share of total top-level CPU; counters are per-scope inclusive sums;"
                 " IPC = inst/cyc, MPKI = misses per 1k-inst )\n" );
    print_agg_header( der );
    for( const Row& r : agg )
    {
        const double pct = grandTotal ? 100.0 * double( r.total ) / double( grandTotal ) : 0.0;
        print_agg_row( r, nspt, pct, der );
    }

    print_tsv( agg, nspt, der );   // fenced #PROF_TSV block — raw ints, for tooling

    // ---- per-thread call trees, siblings by total ----
    std::printf( "\n( %%thread = share of this thread's top-level time;"
                 "  * = scope also entered from another caller, time is summed across all )\n" );
    for( const ThreadSnap& s : snaps )
    {
        std::printf( "\n-- thread %llu (%s)%s%s  --  call tree ----------------------------------\n",
                     (unsigned long long) s.tid,
                     s.name[ 0 ] ? s.name : "unnamed",
                     s.isMain  ? " [main]"    : "",
                     s.retired ? " [retired]" : "" );
        print_header( true );

        const std::size_t n = s.rows.size();

        // build parent -> children from last-seen parent sites
        std::vector<std::vector<int>> kids( n );
        std::vector<int>              roots;
        for( std::size_t i = 0; i < n; ++i )
        {
            const int p = index_of_site( s, s.rows[ i ].parent );
            if( p >= 0 && p != int( i ) )
                kids[ p ].push_back( int( i ) );
            else
                roots.push_back( int( i ) );
        }

        auto byTotal = [ & ]( int a, int b ) { return s.rows[ a ].total > s.rows[ b ].total; };
        std::sort( roots.begin(), roots.end(), byTotal );
        for( auto& k : kids )
            std::sort( k.begin(), k.end(), byTotal );

        // fixed per-thread denominator: the sum of top-level scopes' time
        uint64_t threadTotal = 0;
        for( int r : roots )
            threadTotal += s.rows[ r ].total;

        std::vector<char> visited( n, 0 );
        for( int r : roots )
            print_tree_node( s, kids, r, 0, nspt, threadTotal, 0, visited );
    }

    std::printf( "================================================================================\n\n" );
}

}   // namespace prof

// ============================================================================
// macros
// ============================================================================
#ifdef PROFILE_SCOPE
  #undef PROFILE_SCOPE
#endif
#ifdef PROFILE_SCOPE_DESCRIBE
  #undef PROFILE_SCOPE_DESCRIBE
#endif
#ifdef PROFILE_REPORT
  #undef PROFILE_REPORT
#endif

#if PROFILE_ENABLED

#define PROF_CAT_( a, b ) a##b
#define PROF_CAT( a, b )  PROF_CAT_( a, b )

// __COUNTER__ (captured once via the arg) keeps two scopes on one line distinct
#define PROFILE_SCOPE_DESCRIBE( desc ) PROF_SCOPE_IMPL_( desc, PROF_CAT( prof_id_, __COUNTER__ ) )

#define PROF_SCOPE_IMPL_( desc, id )                                                       \
    static const ::prof::Site PROF_CAT( prof_site_, id ) {                                 \
        __PRETTY_FUNCTION__, ::prof::detail::basename( __FILE__ ), ( desc ), __LINE__ };    \
    static thread_local ::prof::Record* const PROF_CAT( prof_rec_, id ) =                  \
        ::prof::detail::tls_acquire( &PROF_CAT( prof_site_, id ) );                         \
    ::prof::ScopedTimer PROF_CAT( prof_timer_, id ) { PROF_CAT( prof_rec_, id ) }

#define PROFILE_SCOPE()  PROFILE_SCOPE_DESCRIBE( nullptr )
#define PROFILE_REPORT() ::prof::report()

#else   // PROFILE_ENABLED == 0

#define PROFILE_SCOPE_DESCRIBE( desc ) ( (void) 0 )
#define PROFILE_SCOPE()                ( (void) 0 )
#define PROFILE_REPORT()               ( (void) 0 )

#endif

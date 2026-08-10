// bench_svector_diff.cpp — the CORRECTNESS oracle for the small-vector arms. Not a benchmark; it is the
// thing that has to be green before any number from bench_svector_wave.cpp means anything.
//
// A seeded, randomized operation stream is replayed against four containers in lockstep and their
// contents are compared after EVERY operation:
//
//     std::vector<uint32_t>            the ORACLE — the semantics everything else claims to match
//     ankerl::svector<uint32_t,N>      third_party/svector.h (MIT), the vendored complete implementation
//     rw::svector<uint32_t,N>          src/infra/svector.h, the branch-free-size() specialist
//     rwx::svector16<uint32_t,N>       bench/svector_union_arm.h, the 16-byte union experiment
//
// ── WHAT IT ASSERTS, AND WHAT IT MUST NOT ────────────────────────────────────────────────────────────
// ELEMENT SEQUENCE and size(). Nothing else. Three divergences between these types are DELIBERATE and
// documented, and an assertion on any of them would make this harness wrong rather than the code:
//   * size_type — rw/rwx use uint32_t, ankerl and std use size_t;
//   * capacity() and the growth schedule — ankerl::svector<uint32,2> reports capacity 3, because it
//     fills its padding; rw/rwx report 2; std::vector reports whatever it likes. So the four cross the
//     spill boundary at DIFFERENT sizes, which is exactly why the stream below is biased to sweep the
//     whole 0..N+3 band rather than to poke one number;
//   * max_size() — 2^32-1 for rw/rwx.
// Iterator addresses and growth points are likewise never compared.
//
// ── THE BIAS ─────────────────────────────────────────────────────────────────────────────────────────
// Uniform random sizes almost never sit on a boundary. The generator therefore steers the working size
// toward the N-1 / N / N+1 band, and a dedicated sweep at the end drives every (inline, spilled) pairing
// through swap() — the inline<->heap asymmetry is where small-vector implementations actually break, and
// for the union arm a null-pointer test on a union holding element data is a live hazard rather than a
// hypothetical.
//
// Build (the standalone one-liner every bench here uses — no CMake target, deliberately):
//   c++ -O2 -std=c++23 bench/bench_svector_diff.cpp -Isrc -Isrc/infra -Ithird_party -o /tmp/rw_svdiff
//   /tmp/rw_svdiff              # default seed, printed
//   /tmp/rw_svdiff 12345 20000  # SEED and step count — a failure reproduces from the printed seed
//
// Exits non-zero on the first divergence, naming the seed, the step index, the operation and both
// sequences. Gated by test/svectorcheck.sh.

#include "infra/svector.h"
#include "svector_union_arm.h"
#include "../third_party/svector.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

namespace
{

constexpr std::uint32_t kN = 2;   // the inline capacity every production site uses

// ── the generator, hand-rolled on purpose ────────────────────────────────────────────────────────────
// NOT std::mt19937_64, for two reasons that both matter to a harness whose whole value is reproducing a
// failure from a printed seed:
//   * libc++'s mersenne_twister_engine wraps an unsigned left shift by design, which G1's Clang-only
//     `integer` group reports as unsigned-shift-base and, under -fno-sanitize-recover=all, ABORTS the
//     run. Library-internal, intentional and not UB — the same shape CMakeLists.txt:660 documents for
//     libstdc++'s string_view::rfind — but a bench harness should not need an ignorelist entry to run
//     under the project's own sanitizer stack.
//   * a hand-rolled stream is identical on libc++ and libstdc++, so a seed that fails in Linux CI
//     reproduces byte for byte on a Mac.
// This is plain xorshift64. Each left shift masks its base FIRST, which is not an approximation: the
// high bits a 64-bit `<< 13` discards are exactly the bits `& 0x0007FFFFFFFFFFFF` removes, so the
// result is bit-identical to the wrapping form — the truncation is just written down instead of implied.
struct Rng
{
    std::uint64_t s;

    explicit Rng( std::uint64_t seed ) noexcept : s( seed != 0 ? seed : 0x9E3779B97F4A7C15ull ) {}

    std::uint64_t next() noexcept
    {
        s ^= ( s & 0x0007FFFFFFFFFFFFull ) << 13;      // low 51 bits: everything a << 13 keeps
        s ^= s >> 7;
        s ^= ( s & 0x00007FFFFFFFFFFFull ) << 17;      // low 47 bits: everything a << 17 keeps
        return s;
    }
    std::uint64_t operator()() noexcept { return next(); }
};

// ── the operation stream ─────────────────────────────────────────────────────────────────────────────
enum class Op : std::uint8_t
{
    PushBack, EmplaceBack, PopBack, Clear, Reserve, ShrinkToFit, ResizeUp, ResizeDown, ResizeValue,
    AssignCount, AssignRange, InsertOne, InsertCount, InsertRange, EraseOne, EraseRange, WriteIndex,
    Swap, CopyAssign, MoveAssign, SelfSwap, Count_
};

const char* opName( Op o )
{
    switch( o )
    {
        case Op::PushBack:    return "push_back";
        case Op::EmplaceBack: return "emplace_back";
        case Op::PopBack:     return "pop_back";
        case Op::Clear:       return "clear";
        case Op::Reserve:     return "reserve";
        case Op::ShrinkToFit: return "shrink_to_fit";
        case Op::ResizeUp:    return "resize(up)";
        case Op::ResizeDown:  return "resize(down)";
        case Op::ResizeValue: return "resize(n,v)";
        case Op::AssignCount: return "assign(n,v)";
        case Op::AssignRange: return "assign(first,last)";
        case Op::InsertOne:   return "insert(pos,v)";
        case Op::InsertCount: return "insert(pos,n,v)";
        case Op::InsertRange: return "insert(pos,first,last)";
        case Op::EraseOne:    return "erase(pos)";
        case Op::EraseRange:  return "erase(first,last)";
        case Op::WriteIndex:  return "operator[]=";
        case Op::Swap:        return "swap(x,y)";
        case Op::CopyAssign:  return "x = y (copy)";
        case Op::MoveAssign:  return "x = move(tmp)";
        case Op::SelfSwap:    return "x.swap(x)";
        default:              return "?";
    }
};

struct Step
{
    Op            op;
    std::uint8_t  target;    // 0 -> x, 1 -> y (so both instances reach mixed inline/spilled states)
    std::uint32_t n;         // a count or an index, interpreted per op
    std::uint32_t v;         // a value
    std::uint32_t extra;     // a second count where an op needs one
};

// The band that matters. Uniform random would spend almost all its time far from N; this keeps the
// working size hovering across the inline<->heap boundary of all four implementations at once (rw/rwx
// spill past 2, ankerl past 3, std::vector immediately).
std::uint32_t biasedSize( Rng& rng )
{
    const std::uint32_t roll = std::uint32_t( rng() % 100u );
    if( roll < 70u ) { return std::uint32_t( rng() % ( kN + 3u ) ); }        // 0 .. N+2, the boundary band
    if( roll < 90u ) { return kN + 1u + std::uint32_t( rng() % 4u ); }       // just past it
    return std::uint32_t( rng() % 40u );                                     // occasionally well past
}

std::vector<Step> makeStream( std::uint64_t seed, std::size_t stepCount )
{
    Rng               rng( seed );
    std::vector<Step> out;
    out.reserve( stepCount );
    for( std::size_t i = 0; i < stepCount; ++i )
    {
        Step s {};
        s.op     = Op( rng() % std::uint64_t( Op::Count_ ) );
        s.target = std::uint8_t( rng() % 2u );
        s.n      = biasedSize( rng );
        s.v      = std::uint32_t( rng() & 0xFFFFu );
        s.extra  = std::uint32_t( rng() % ( kN + 3u ) );
        out.push_back( s );
    }
    return out;
}

// ── replay ───────────────────────────────────────────────────────────────────────────────────────────
// One body, four instantiations. Every container below supports this surface with ANKERL'S SPELLING,
// which is the substitutability claim the one-alias conversion experiment rests on — if an arm stops
// compiling here, the alias flip would have broken at a real call site instead.
template <class V>
void applyOne( V& c, const Step& s, const std::vector<std::uint32_t>& feed )
{
    using SizeT = decltype( c.size() );
    const SizeT sz = c.size();
    switch( s.op )
    {
        case Op::PushBack:    c.push_back( s.v ); break;
        case Op::EmplaceBack: c.emplace_back( s.v ); break;
        case Op::PopBack:     if( sz != 0 ) { c.pop_back(); } break;
        case Op::Clear:       c.clear(); break;
        case Op::Reserve:     c.reserve( SizeT( s.n ) ); break;
        case Op::ShrinkToFit: c.shrink_to_fit(); break;
        case Op::ResizeUp:    c.resize( SizeT( sz + s.extra ) ); break;
        case Op::ResizeDown:  c.resize( SizeT( s.extra < sz ? sz - s.extra : 0 ) ); break;
        case Op::ResizeValue: c.resize( SizeT( s.n ), s.v ); break;
        case Op::AssignCount: c.assign( SizeT( s.n ), s.v ); break;
        case Op::AssignRange: c.assign( feed.begin(), feed.begin() + ( s.n % ( feed.size() + 1 ) ) ); break;
        case Op::InsertOne:   c.insert( c.cbegin() + ( sz == 0 ? 0 : s.n % ( sz + 1 ) ), s.v ); break;
        case Op::InsertCount: c.insert( c.cbegin() + ( sz == 0 ? 0 : s.n % ( sz + 1 ) ), SizeT( s.extra ), s.v ); break;
        case Op::InsertRange: c.insert( c.cbegin() + ( sz == 0 ? 0 : s.n % ( sz + 1 ) ),
                                        feed.begin(), feed.begin() + ( s.extra % ( feed.size() + 1 ) ) ); break;
        case Op::EraseOne:    if( sz != 0 ) { c.erase( c.cbegin() + ( s.n % sz ) ); } break;
        case Op::EraseRange:
        {
            if( sz != 0 )
            {
                const SizeT from = SizeT( s.n % sz );
                const SizeT to   = SizeT( from + ( s.extra % ( sz - from + 1 ) ) );
                c.erase( c.cbegin() + from, c.cbegin() + to );
            }
            break;
        }
        case Op::WriteIndex:  if( sz != 0 ) { c[ SizeT( s.n % sz ) ] = s.v; } break;
        default: break;
    }
}

template <class V>
struct Pair
{
    V x, y;
};

// Ops that touch BOTH instances live here, so the single-instance path above stays uniform.
template <class V>
void applyPair( Pair<V>& p, const Step& s, const std::vector<std::uint32_t>& feed )
{
    V& primary = ( s.target == 0 ) ? p.x : p.y;
    V& other   = ( s.target == 0 ) ? p.y : p.x;
    switch( s.op )
    {
        case Op::Swap:       primary.swap( other ); break;
        case Op::SelfSwap:   primary.swap( primary ); break;      // must be a no-op, not a corruption
        case Op::CopyAssign: primary = other; break;
        case Op::MoveAssign:
        {
            V tmp( other );                                       // copy-construct, then move-assign it in
            primary = std::move( tmp );
            break;
        }
        default: applyOne( primary, s, feed ); break;
    }
}

template <class V>
void snapshot( const Pair<V>& p, std::vector<std::uint32_t>& out )
{
    out.clear();
    out.push_back( std::uint32_t( p.x.size() ) );
    for( const auto& e : p.x ) { out.push_back( std::uint32_t( e ) ); }
    out.push_back( 0xFFFFFFFFu );                                  // separator, so "x empty, y=[1]" and
    out.push_back( std::uint32_t( p.y.size() ) );                  // "x=[1], y empty" cannot collide
    for( const auto& e : p.y ) { out.push_back( std::uint32_t( e ) ); }
}

std::string render( const std::vector<std::uint32_t>& v )
{
    std::string s;
    for( std::uint32_t e : v )
    {
        char b[ 16 ];
        if( e == 0xFFFFFFFFu ) { s += " | "; continue; }
        std::snprintf( b, sizeof( b ), "%u ", e );
        s += b;
    }
    return s;
}

int  g_failures = 0;
void report( const char* arm, std::uint64_t seed, std::size_t step, const Step& s,
             const std::vector<std::uint32_t>& want, const std::vector<std::uint32_t>& got )
{
    std::printf( "  FAIL  %s diverged from std::vector at step %zu (seed=%llu, op=%s, target=%u, n=%u, v=%u, extra=%u)\n",
                 arm, step, (unsigned long long) seed, opName( s.op ), unsigned( s.target ), s.n, s.v, s.extra );
    std::printf( "          oracle: %s\n", render( want ).c_str() );
    std::printf( "          %-6s: %s\n", arm, render( got ).c_str() );
    ++g_failures;
}

// ── the deliberate swap sweep ────────────────────────────────────────────────────────────────────────
// Every (sizeA, sizeB) pairing across the boundary band, driven through swap() and then read back. The
// random stream reaches these too, but only incidentally; an exhaustive sweep is what makes the
// asymmetric case non-negotiable rather than probabilistic.
template <class V>
bool swapSweep( const char* arm )
{
    bool ok = true;
    for( std::uint32_t a = 0; a <= kN + 3u; ++a )
    {
        for( std::uint32_t b = 0; b <= kN + 3u; ++b )
        {
            std::vector<std::uint32_t> ea, eb;
            V va, vb;
            for( std::uint32_t i = 0; i < a; ++i ) { va.push_back( 1000u + i ); ea.push_back( 1000u + i ); }
            for( std::uint32_t i = 0; i < b; ++i ) { vb.push_back( 2000u + i ); eb.push_back( 2000u + i ); }
            va.swap( vb );
            std::vector<std::uint32_t> ga( va.begin(), va.end() ), gb( vb.begin(), vb.end() );
            if( ga != eb || gb != ea || va.size() != b || vb.size() != a )
            {
                std::printf( "  FAIL  %s swap(size=%u inline/heap, size=%u) did not exchange contents\n", arm, a, b );
                ok = false;
                ++g_failures;
            }
        }
    }
    return ok;
}

}   // namespace

int main( int argc, char** argv )
{
    // Deterministic by default and PRINTED either way, so a CI failure reproduces from its own log.
    std::uint64_t seed  = 0xA5F00D5EEDULL;
    std::size_t   steps = 20000;
    if( argc > 1 ) { seed  = std::strtoull( argv[1], nullptr, 10 ); }
    if( argc > 2 ) { steps = std::size_t( std::strtoull( argv[2], nullptr, 10 ) ); }

    std::printf( "bench_svector_diff: seed=%llu steps=%zu N=%u\n", (unsigned long long) seed, steps, kN );
    std::printf( "  sizeof: std::vector=%zu  ankerl=%zu  rw=%zu  rwx(union)=%zu\n",
                 sizeof( std::vector<std::uint32_t> ),
                 sizeof( ankerl::svector<std::uint32_t, kN> ),
                 sizeof( rw::svector<std::uint32_t, kN> ),
                 sizeof( rwx::svector16<std::uint32_t, kN> ) );

    // a fixed feed for the range-taking operations, so every arm is handed identical input
    std::vector<std::uint32_t> feed;
    for( std::uint32_t i = 0; i < 8; ++i ) { feed.push_back( 500u + i ); }

    const std::vector<Step> stream = makeStream( seed, steps );

    Pair<std::vector<std::uint32_t>>            oracle;
    Pair<ankerl::svector<std::uint32_t, kN>>    ank;
    Pair<rw::svector<std::uint32_t, kN>>        rws;
    Pair<rwx::svector16<std::uint32_t, kN>>     uni;

    std::vector<std::uint32_t> wo, wa, wr, wu;
    for( std::size_t i = 0; i < stream.size(); ++i )
    {
        const Step& s = stream[i];
        applyPair( oracle, s, feed );
        applyPair( ank,    s, feed );
        applyPair( rws,    s, feed );
        applyPair( uni,    s, feed );

        snapshot( oracle, wo );
        snapshot( ank,    wa );
        snapshot( rws,    wr );
        snapshot( uni,    wu );

        if( wa != wo ) { report( "ankerl", seed, i, s, wo, wa ); }
        if( wr != wo ) { report( "rw",     seed, i, s, wo, wr ); }
        if( wu != wo ) { report( "rwx",    seed, i, s, wo, wu ); }
        if( g_failures >= 5 )
        {
            std::printf( "  (stopping after %d divergences)\n", g_failures );
            break;
        }
    }
    if( g_failures == 0 )
    {
        std::printf( "  PASS  %zu operations, 4 arms in lockstep, element sequence + size() identical throughout\n", steps );
    }

    const bool sa = swapSweep<ankerl::svector<std::uint32_t, kN>>( "ankerl" );
    const bool sr = swapSweep<rw::svector<std::uint32_t, kN>>( "rw" );
    const bool su = swapSweep<rwx::svector16<std::uint32_t, kN>>( "rwx" );
    if( sa && sr && su )
    {
        std::printf( "  PASS  swap sweep (%u x %u size pairings per arm, every inline/heap combination)\n", kN + 4u, kN + 4u );
    }

    if( g_failures != 0 )
    {
        std::printf( "bench_svector_diff: FAILED (%d divergences) — reproduce with: %s %llu %zu\n",
                     g_failures, argv[0], (unsigned long long) seed, steps );
        return 1;
    }
    std::printf( "bench_svector_diff: OK\n" );
    return 0;
}

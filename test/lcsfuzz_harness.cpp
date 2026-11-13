// lcsfuzz_harness.cpp — the fuzz arm of test/lcsidentitycheck.sh (QD-LCS: the Type-3 LCS early exit).
//
// The Type-3 clone pass (src/clones.h findClonesType3) keeps a pair when 2·LCS/(|a|+|b|) ≥ kType3MinSimilarity. QD-LCS lets
// the LCS stop early once the length cannot reach type3LcsNeed. This harness checks, on deterministic random token streams
// (a fixed-seed LCG: the same pairs on every run and machine), that:
//   F1  cloneLcsLen with no `need` equals an independent textbook DP (written out below, not shared with clones.h);
//   F2  with a `need`, an answer ≥ need is the exact length, and an answer < need comes from a pair whose exact length is
//       < need too (and is an upper bound of it), for need = type3LcsNeed(|a|+|b|) and for random needs;
//   F3  the premise: pairs were compared, some stopped early, and some reached need (a vacuous run FAILS);
//   F4  type3LcsNeed never asks for more than a kept pair has: for every ratio denominator up to two capped bodies, the
//       least length whose float ratio reaches kType3MinSimilarity is at least the need.
//
// The streams: alphabets of 1 to 5000 tokens, lengths 0 to 300 with the 64-bit word edges (63/64/65, 127/128/129) forced, a
// few up to kType3MaxTokensForLcs, and edited copies (2-50 % of the tokens substituted, deleted or inserted) so the ratios
// land on both sides of the 0.8 threshold. Exit 0 = pass; the counts are printed for the gate to read.

#include "../src/clones.h"

#include <cstdint>
#include <cstdio>
#include <span>
#include <vector>

namespace
{

struct Lcg
{
    std::uint64_t s = 0x2545f4914f6cdd1dull;
    std::uint32_t next()
    {
        s = s * 6364136223846793005ull + 1442695040888963407ull;
        return std::uint32_t( s >> 33 );
    }
    std::uint32_t below( std::uint32_t n ) { return n == 0 ? 0 : next() % n; }
};

// The textbook two-row DP, kept independent of clones.h on purpose.
std::size_t referenceLcs( const std::vector<std::uint32_t>& a, const std::vector<std::uint32_t>& b )
{
    std::vector<std::size_t> prev( b.size() + 1, 0 ), cur( b.size() + 1, 0 );
    for( std::size_t i = 1; i <= a.size(); ++i )
    {
        for( std::size_t j = 1; j <= b.size(); ++j )
        {
            if( a[i - 1] == b[j - 1] )
            {
                cur[j] = prev[j - 1] + 1;
            }
            else
            {
                cur[j] = prev[j] > cur[j - 1] ? prev[j] : cur[j - 1];
            }
        }
        prev.swap( cur );
    }
    return prev[b.size()];
}

std::vector<std::uint32_t> randomStream( Lcg& rng, std::size_t len, std::uint32_t alphabet )
{
    std::vector<std::uint32_t> v( len );
    for( auto& t : v )
    {
        t = rng.below( alphabet );
    }
    return v;
}

// a copy of `a` with about pct % of its positions edited (substitute, delete or insert, equally likely)
std::vector<std::uint32_t> editedCopy( Lcg& rng, const std::vector<std::uint32_t>& a, std::uint32_t pct, std::uint32_t alphabet )
{
    std::vector<std::uint32_t> b;
    b.reserve( a.size() + a.size() / 2 + 1 );
    for( const std::uint32_t t : a )
    {
        if( rng.below( 100 ) >= pct )
        {
            b.push_back( t );
            continue;
        }
        switch( rng.below( 3 ) )
        {
            case 0: b.push_back( rng.below( alphabet ) ); break;
            case 1: break;
            default:
                b.push_back( t );
                b.push_back( rng.below( alphabet ) );
                break;
        }
    }
    if( b.size() > rw::kType3MaxTokensForLcs )
    {
        b.resize( rw::kType3MaxTokensForLcs );
    }
    return b;
}

struct Counts
{
    std::uint64_t pairs = 0, exactChecks = 0, needChecks = 0, exits = 0, reached = 0, failures = 0;
};

void checkPair( const std::vector<std::uint32_t>& a, const std::vector<std::uint32_t>& b, Lcg& rng, Counts& c )
{
    std::vector<std::uint32_t> rowA, rowB;
    const std::span<const std::uint32_t> sa( a ), sb( b );
    const std::size_t                    ref = referenceLcs( a, b );
    ++c.pairs;

    const std::size_t exact = rw::cloneLcsLen( sa, sb, rowA, rowB );
    ++c.exactChecks;
    if( exact != ref )
    {
        ++c.failures;
        std::printf( "FAIL F1 na=%zu nb=%zu ref=%zu got=%zu\n", a.size(), b.size(), ref, exact );
    }

    const std::size_t shortest = a.size() < b.size() ? a.size() : b.size();
    const std::size_t needs[]  = { rw::type3LcsNeed( a.size() + b.size() ), std::size_t( rng.below( std::uint32_t( shortest + 3 ) ) ) };
    for( const std::size_t need : needs )
    {
        const std::size_t got = rw::cloneLcsLen( sa, sb, rowA, rowB, need );
        ++c.needChecks;
        const bool ok = got >= need ? got == ref : ( ref < need && got >= ref );
        c.exits += got < need ? 1 : 0;
        c.reached += ( need > 0 && got >= need ) ? 1 : 0;
        if( !ok )
        {
            ++c.failures;
            std::printf( "FAIL F2 na=%zu nb=%zu need=%zu ref=%zu got=%zu\n", a.size(), b.size(), need, ref, got );
        }
    }
}

}   // namespace

int main()
{
    Lcg           rng;
    Counts        c;
    const std::uint32_t alphabets[] = { 1, 2, 3, 8, 64, 5000 };
    const std::size_t   edges[]     = { 0, 1, 63, 64, 65, 127, 128, 129 };

    // the word edges, against each other, on every alphabet
    for( const std::uint32_t alpha : alphabets )
    {
        for( const std::size_t la : edges )
        {
            for( const std::size_t lb : edges )
            {
                checkPair( randomStream( rng, la, alpha ), randomStream( rng, lb, alpha ), rng, c );
            }
        }
    }
    // random lengths: unrelated streams, and edited copies at every edit rate
    const std::uint32_t pcts[] = { 2, 5, 10, 15, 20, 30, 50 };
    for( int round = 0; round < 400; ++round )
    {
        const std::uint32_t        alpha = alphabets[rng.below( 6 )];
        std::vector<std::uint32_t> a     = randomStream( rng, rng.below( 301 ), alpha );
        checkPair( a, randomStream( rng, rng.below( 301 ), alpha ), rng, c );
        for( const std::uint32_t pct : pcts )
        {
            checkPair( a, editedCopy( rng, a, pct, alpha ), rng, c );
        }
    }
    // a few long bodies, up to the cap
    for( int round = 0; round < 6; ++round )
    {
        const std::uint32_t        alpha = round % 2 == 0 ? 40 : 5000;
        std::vector<std::uint32_t> a     = randomStream( rng, 1500 + rng.below( std::uint32_t( rw::kType3MaxTokensForLcs - 1500 ) + 1 ), alpha );
        checkPair( a, editedCopy( rng, a, pcts[round], alpha ), rng, c );
    }

    // F4: the need is safe for every denominator the pass can see
    std::uint64_t needDens = 0;
    for( std::size_t den = 1; den <= 2 * rw::kType3MaxTokensForLcs; ++den )
    {
        std::size_t least = 0;
        while( 2.0f * float( least ) / float( den ) < rw::kType3MinSimilarity )
        {
            ++least;
        }
        ++needDens;
        if( rw::type3LcsNeed( den ) > least )
        {
            ++c.failures;
            std::printf( "FAIL F4 den=%zu need=%zu least_kept=%zu\n", den, rw::type3LcsNeed( den ), least );
        }
    }
    std::printf( "LCSNEED dens=%llu\n", (unsigned long long)needDens );
    std::printf( "LCSFUZZ pairs=%llu exact_checks=%llu need_checks=%llu early_exits=%llu reached=%llu failures=%llu\n",
                 (unsigned long long)c.pairs, (unsigned long long)c.exactChecks, (unsigned long long)c.needChecks, (unsigned long long)c.exits,
                 (unsigned long long)c.reached, (unsigned long long)c.failures );
    if( c.failures != 0 )
    {
        return 1;
    }
    if( c.pairs == 0 || c.exits == 0 || c.reached == 0 )
    {
        std::printf( "FAIL F3 vacuous: a run must compare pairs, stop some early and keep some\n" );
        return 1;
    }
    return 0;
}

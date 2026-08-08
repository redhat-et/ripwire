// Three-arm race for buildNewlineOffsets' byte scan (src/ingest.cpp): the byte-at-a-time loop that
// ships today, libc memchr in a loop, and rw::findByte — the hand-rolled NEON/SSE2 kernel that lives
// beside FixedStr's compare/hash in src/fixedStr.h.
//
// Build: c++ -O3 -march=native -std=c++23 bench/bench_newline_ab.cpp -Isrc -Isrc/infra -Ithird_party -o /tmp/ripwire_newline_ab
// Run:   /tmp/ripwire_newline_ab [repoRoot] [targetMiB]
//
// METHOD, following bench/bench_radix_ab.cpp: every arm sees byte-identical inputs, the arms are run
// ALTERNATING (the arm that goes first rotates each round) so thermal drift and frequency ramps cannot
// settle on one arm, and the reported figure is the MEDIAN of the per-round totals, not the mean or the
// best. Timing is prof::BenchTimer into a prof::Accum; prof::escape() pins the input and the output
// vector so the optimizer can neither hoist the scan out of the timed region nor delete it as a dead
// store. The result is reported as ms over the corpus and as GB/s of input consumed.
//
// CORRECTNESS IS THE GATE, NOT A FOOTNOTE. Before any timing runs, all three arms scan the whole corpus
// plus a set of hand-built edge cases and their offset vectors must be IDENTICAL, element for element.
// The edge cases exist because they are exactly where a vectorised scan goes wrong: an empty span, a
// needle at position 0, a span with no trailing newline, a span shorter than one vector, a span whose
// length is an exact vector multiple, and CRLF bytes. '\r' is NOT a line break here — the shipping loop
// tests `src[i] == '\n'` and nothing else, so every arm must ignore '\r' the same way, and the CRLF
// fixture is what proves they do. Since the kernel is exact, shipping it cannot perturb any output and
// ripwire's determinism contract is untouched by construction (see the note on rw::findByte itself).

#include "fixedStr.h"
#include "profileScope.h"

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <string_view>
#include <vector>

namespace
{

// ---- arm (a): the loop that ships today, lifted verbatim from src/ingest.cpp:8361 ----
std::vector<std::uint32_t> armScalarLoop( std::string_view src )
{
    std::vector<std::uint32_t> off;
    for( std::uint32_t i = 0; i < src.size(); ++i )
    {
        if( src[i] == '\n' )
        {
            off.push_back( i );
        }
    }
    return off;
}

// ---- arm (b): libc memchr in a loop — the "use others' efforts, even libc's" control.
// Apple's arm64 memchr is a hand-tuned NEON routine, so this arm is not a straw man.
std::vector<std::uint32_t> armMemchr( std::string_view src )
{
    std::vector<std::uint32_t> off;
    const char* const begin = src.data();
    const char*       first = begin;
    const char* const last  = begin + src.size();
    while( first < last )
    {
        const void* hit = std::memchr( first, '\n', std::size_t( last - first ) );
        if( hit == nullptr )
        {
            break;
        }
        first = static_cast<const char*>( hit );
        off.push_back( std::uint32_t( first - begin ) );
        ++first;
    }
    return off;
}

// ---- arm (c): rw::findByte — our own NEON/SSE2 kernel, same loop shape as arm (b) so the
// comparison isolates the KERNEL and not the loop around it. Scalar fallback on other arches
// is inside findByte, behind the identical interface.
std::vector<std::uint32_t> armFindByte( std::string_view src )
{
    std::vector<std::uint32_t> off;
    const char* const begin = src.data();
    const char*       first = begin;
    const char* const last  = begin + src.size();
    while( first < last )
    {
        first = rw::findByte( first, last, '\n' );
        if( first == last )
        {
            break;
        }
        off.push_back( std::uint32_t( first - begin ) );
        ++first;
    }
    return off;
}

struct Arm
{
    const char*                                  name;
    std::vector<std::uint32_t>                 ( *fn )( std::string_view );
};

double median( std::vector<double> samples )
{
    std::sort( samples.begin(), samples.end() );
    return samples[ samples.size() / 2 ];
}

// ---- corpus: real bytes from the repo, chosen by a DETERMINISTIC rule ----
// Sorted paths, no timestamps, no directory-iteration order dependence, no randomness: the same
// checkout produces the same corpus on every machine, so two runs of this bench are comparable.
// .git and the build trees are excluded — packfiles and object files are not the text this scan
// actually meets, and they would make the corpus depend on local build state.
bool isExcluded( const std::filesystem::path& path, const std::filesystem::path& root )
{
    for( const auto& part : std::filesystem::relative( path, root ) )
    {
        const std::string name = part.string();
        if( name.empty() )
        {
            continue;
        }
        if( name[0] == '.' || name == "build" || name.rfind( "build_", 0 ) == 0 || name == "asan" || name == "tsan" )
        {
            return true;
        }
    }
    return false;
}

std::vector<std::string> loadCorpus( const std::filesystem::path& root, std::size_t targetBytes, std::size_t& totalBytesOut )
{
    std::vector<std::filesystem::path> paths;
    std::error_code                    ec;
    for( std::filesystem::recursive_directory_iterator it( root, std::filesystem::directory_options::skip_permission_denied, ec ), end;
         it != end;
         it.increment( ec ) )
    {
        if( ec )
        {
            break;
        }
        if( it->is_directory( ec ) )
        {
            if( isExcluded( it->path(), root ) )
            {
                it.disable_recursion_pending();
            }
            continue;
        }
        if( !it->is_regular_file( ec ) || isExcluded( it->path(), root ) )
        {
            continue;
        }
        paths.push_back( it->path() );
    }
    std::sort( paths.begin(), paths.end() );   // determinism: the file LIST is sorted before anything is read

    std::vector<std::string> files;
    std::size_t              total = 0;
    for( const std::filesystem::path& path : paths )
    {
        if( total >= targetBytes )
        {
            break;
        }
        std::ifstream in( path, std::ios::binary );
        if( !in )
        {
            continue;
        }
        std::string bytes( ( std::istreambuf_iterator<char>( in ) ), std::istreambuf_iterator<char>() );
        total += bytes.size();
        files.push_back( std::move( bytes ) );
    }
    totalBytesOut = total;
    return files;
}

// ---- edge fixtures: the inputs a vectorised scan gets wrong ----
std::vector<std::string> edgeCases()
{
    return {
        std::string( "" ),                                  // empty span — no load may be issued at all
        std::string( "\n" ),                                // needle at position 0, span shorter than a vector
        std::string( "no trailing newline" ),               // last line unterminated
        std::string( "a\nb" ),                              // newline mid-span, unterminated tail
        std::string( "\n\n\n\n" ),                          // adjacent needles
        std::string( "a\r\nb\r\nc\r\n" ),                   // CRLF: '\r' must be IGNORED, exactly as the shipping loop ignores it
        std::string( "\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r" ),  // one full vector of near-misses, no match
        std::string( 15, 'x' ),                             // one byte short of a vector, no match
        std::string( 16, 'x' ),                             // exactly one vector, no match
        std::string( 17, 'x' ),                             // one vector plus a scalar tail, no match
        std::string( 15, 'x' ) + "\n",                      // match as the final byte of the first vector
        std::string( 16, 'x' ) + "\n",                      // match as the first byte of the scalar tail
        std::string( 64, '\n' ),                            // every byte a match, several vectors deep
        std::string( 1000, 'x' ) + "\n" + std::string( 1000, 'y' ),
    };
}

bool checkIdentical( const std::vector<Arm>& arms, const std::vector<std::string>& inputs, const char* label )
{
    for( std::size_t inputIndex = 0; inputIndex < inputs.size(); ++inputIndex )
    {
        const std::vector<std::uint32_t> reference = arms[0].fn( inputs[ inputIndex ] );
        for( std::size_t armIndex = 1; armIndex < arms.size(); ++armIndex )
        {
            const std::vector<std::uint32_t> candidate = arms[ armIndex ].fn( inputs[ inputIndex ] );
            if( candidate != reference )
            {
                std::fprintf( stderr, "IDENTICAL-OUTPUT CHECK FAILED: %s input #%zu, arm '%s' disagrees with arm '%s'\n",
                              label, inputIndex, arms[ armIndex ].name, arms[0].name );
                std::fprintf( stderr, "  sizes: %zu vs %zu\n", candidate.size(), reference.size() );
                for( std::size_t i = 0; i < std::min( candidate.size(), reference.size() ); ++i )
                {
                    if( candidate[i] != reference[i] )
                    {
                        std::fprintf( stderr, "  first divergence at element %zu: %u vs %u\n", i, candidate[i], reference[i] );
                        break;
                    }
                }
                return false;
            }
        }
    }
    return true;
}

}   // namespace

int main( int argc, char** argv )
{
    const std::filesystem::path root       = argc > 1 ? std::filesystem::path( argv[1] ) : std::filesystem::path( "." );
    const std::size_t           targetMiB  = argc > 2 ? std::strtoull( argv[2], nullptr, 10 ) : 16;
    const char*                 machine    = std::getenv( "RIPWIRE_MACHINE" );
    if( machine == nullptr )
    {
        machine = "local";
    }

    const std::vector<Arm> arms = {
        { "scalar byte loop", armScalarLoop },
        { "libc memchr",      armMemchr     },
        { "rw::findByte",     armFindByte   },
    };

    std::size_t                    corpusBytes = 0;
    const std::vector<std::string> corpus      = loadCorpus( root, targetMiB * 1024u * 1024u, corpusBytes );
    if( corpus.empty() )
    {
        std::fprintf( stderr, "corpus is empty — pass the repo root as argv[1]\n" );
        return 2;
    }

    // ---- correctness first: no timing number is printed until every arm agrees on every byte ----
    if( !checkIdentical( arms, edgeCases(), "edge fixtures" ) )
    {
        return 3;
    }
    if( !checkIdentical( arms, corpus, "repo corpus" ) )
    {
        return 3;
    }

    std::size_t newlineCount = 0;
    for( const std::string& file : corpus )
    {
        newlineCount += armScalarLoop( file ).size();
    }

    std::printf( "ripwire newline A/B/C: root=%s files=%zu bytes=%zu (%.2f MiB) newlines=%zu machine=%s\n",
                 root.string().c_str(), corpus.size(), corpusBytes, double( corpusBytes ) / ( 1024.0 * 1024.0 ), newlineCount, machine );
    std::printf( "identical-output check: PASS — %zu edge fixtures + %zu corpus files, all 3 arms byte-for-byte equal\n",
                 edgeCases().size(), corpus.size() );

    constexpr int                   kRounds = 9;
    std::vector<std::vector<double>> samples( arms.size() );

    for( int round = 0; round < kRounds; ++round )
    {
        for( std::size_t step = 0; step < arms.size(); ++step )
        {
            // Rotate which arm leads each round so no arm permanently owns the cold-cache slot.
            const std::size_t armIndex = ( std::size_t( round ) + step ) % arms.size();
            prof::Accum       accum;
            std::vector<std::uint32_t> sink;
            {
                prof::BenchTimer timer( accum );
                for( const std::string& file : corpus )
                {
                    prof::escape( file.data() );
                    sink = arms[ armIndex ].fn( file );
                    prof::escape( sink.data() );
                }
                prof::clobberMemory();
            }
            samples[ armIndex ].push_back( accum.ms() );
        }
    }

    std::printf( "\n%-20s %12s %12s %10s   (median of %d rounds, alternating, rotating lead)\n",
                 "arm", "ms", "GB/s", "vs scalar", kRounds );
    const double scalarMs = median( samples[0] );
    for( std::size_t armIndex = 0; armIndex < arms.size(); ++armIndex )
    {
        const double ms     = median( samples[ armIndex ] );
        const double gbPerS = ( double( corpusBytes ) / 1e9 ) / ( ms / 1e3 );
        std::printf( "%-20s %12.3f %12.3f %9.2fx\n", arms[ armIndex ].name, ms, gbPerS, scalarMs / ms );
    }
    return 0;
}

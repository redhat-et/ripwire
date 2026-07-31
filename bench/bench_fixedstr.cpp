#include "../src/fixedStr.h"
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <functional>
#include <string>
#include <vector>
using namespace ctx;
using Clock = std::chrono::steady_clock;
static double nsPer( Clock::time_point a, Clock::time_point b, std::size_t ops )
{ return std::chrono::duration_cast<std::chrono::nanoseconds>( b - a ).count() / double( ops ); }
int main()
{
    std::vector<std::string> names;
    { std::ifstream f( "/tmp/names.txt" ); std::string l; while( std::getline( f, l ) ) if( !l.empty() && l.size() <= 31 ) names.push_back( l ); }
    const std::size_t N = names.size();
    std::vector<FixedStr> fs;  fs.reserve( N );  for( auto& n : names ) fs.emplace_back( n );
    std::vector<FixedStr> fcopy = fs;
    std::vector<std::string> copy = names;
    const int R = 301;   // ODD — a summing accumulator can't cancel; sinks printed so nothing elides

    std::printf( "corpus: %zu names; sizeof FixedStr=%zu std::string=%zu\n", N, sizeof( FixedStr ), sizeof( std::string ) );

    std::hash<std::string> sh;
    std::uint64_t a1 = 0;  auto t0 = Clock::now(); for( int r = 0; r < R; ++r ) for( std::size_t i = 0; i < N; ++i ) a1 += sh( names[i] ); auto t1 = Clock::now();
    std::uint64_t a2 = 0;  auto t2 = Clock::now(); for( int r = 0; r < R; ++r ) for( std::size_t i = 0; i < N; ++i ) a2 += fs[i].hash(); auto t3 = Clock::now();
    double hs = nsPer( t0, t1, N * R ), hf = nsPer( t2, t3, N * R );

    std::uint64_t e1 = 0;  auto t4 = Clock::now(); for( int r = 0; r < R; ++r ) for( std::size_t i = 0; i < N; ++i ) e1 += ( names[i] == copy[i] ); auto t5 = Clock::now();
    std::uint64_t e2 = 0;  auto t6 = Clock::now(); for( int r = 0; r < R; ++r ) for( std::size_t i = 0; i < N; ++i ) e2 += ( fs[i] == fcopy[i] ); auto t7 = Clock::now();
    double es = nsPer( t4, t5, N * R ), ef = nsPer( t6, t7, N * R );

    std::printf( "hash        : std::string %5.2f ns   FixedStr %5.2f ns   %.2fx   [sinks %llu %llu]\n", hs, hf, hs / hf, (unsigned long long)a1, (unsigned long long)a2 );
    std::printf( "equal (hit) : std::string %5.2f ns   FixedStr %5.2f ns   %.2fx   [hits %llu %llu]\n", es, ef, es / ef, (unsigned long long)e1, (unsigned long long)e2 );
    return 0;
}

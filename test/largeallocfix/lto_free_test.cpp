// lto_free_test.cpp — driven by test/largeallocpeakcheck.sh arm L, linked with src/largealloc.cpp under -O2 -flto: the
// one build shape where the optimizer sees a function's `operator new` call and the replaced `operator delete`'s body
// together. A block freed in the function that allocated it must still go back to the OS whole, and nothing else with it.
//
// churn() has the shape of the 0.7.0 candidate's pageRankDouble: a local array of 256 KiB or more, filled by a libc call
// (which leaves the argument registers holding whatever it liked), read, and freed at scope exit.
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <vector>
#include <mach/mach.h>

static std::size_t footprint() noexcept
{
    task_vm_info_data_t    info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if( task_info( mach_task_self(), TASK_VM_INFO, reinterpret_cast<task_info_t>( &info ), &count ) != KERN_SUCCESS )
    {
        return 0;
    }
    return static_cast<std::size_t>( info.phys_footprint );
}

[[gnu::noinline]] static double churn( std::size_t n, const double* from )
{
    std::vector<double> block( n );
    std::memcpy( block.data(), from, n * sizeof( double ) );
    double sum = 0;
    for( std::size_t i = 0; i < n; i += 512 )
    {
        sum += block[ i ];
    }
    return sum;
}

int main()
{
    constexpr std::size_t kDoubles = std::size_t( 1 ) << 20;   // 8 MiB a block: routed, and every page of it written
    constexpr int         kRounds  = 48;
    std::vector<double> source( kDoubles, 1.0 );
    std::vector<double> above( kDoubles, 2.0 );    // a live routed block that a wrong-length unmap can take with it
    const std::size_t before = footprint();
    double            sum    = 0;
    for( int round = 0; round < kRounds; ++round )
    {
        sum += churn( kDoubles, source.data() );
    }
    const std::size_t after = footprint();
    double            live  = 0;
    for( std::size_t i = 0; i < kDoubles; i += 512 )
    {
        live += source[ i ] + above[ i ];   // faults if a free unmapped more than its own block
    }
    const std::size_t grownMiB = after > before ? ( after - before ) >> 20 : 0;
    std::printf( "  footprint grew %zu MiB over %d freed 8 MiB blocks (sum %.0f, live %.0f)\n", grownMiB, kRounds, sum, live );
    if( before == 0 || after == 0 )
    {
        std::printf( "  FAIL the footprint could not be read\n" );
        return 1;
    }
    if( grownMiB >= 64 )   // 48 blocks kept would be 384 MiB; one or two stray pages of noise are not
    {
        std::printf( "  FAIL freed blocks stayed mapped: the unmap was given a length that is not the block's\n" );
        return 1;
    }
    std::printf( "LTO_FREE_OK\n" );
    return 0;
}

// forrowfeatures_unit.cpp — the (U) half of test/forrowfeaturescheck.sh: rowfeat_detail::fileRanks on a synthetic IngestResult,
// including a symbol whose fileId is past the file table, which no ingest the CLI runs hands over. The driver is compiled with the
// standard library's bounds checks on (libc++ hardening, libstdc++ assertions), so an out-of-range index aborts it instead of
// writing past the vector. Exit 0 = every case holds; each case prints PASS or FAIL, and the driver FAILs when it ran no case.

#include "forrowfeatures.h"

#include <array>
#include <cstdint>
#include <ranges>
#include <string_view>
#include <vector>

namespace
{

// An ingest with `files` files and one symbol per entry of `fileOf`, in that file.
rw::IngestResult withFiles( std::size_t files, const std::vector<std::uint32_t>& fileOf )
{
    rw::IngestResult ing;
    ing.files.resize( files );
    ing.symbols = fileOf | std::views::transform( []( std::uint32_t f ) { rw::Symbol s; s.fileId = f; return s; } ) | std::ranges::to<std::vector>();
    return ing;
}

struct Case
{
    std::string_view what;
    bool             held;
};

} // namespace

int main()
{
    // Two files; symbol 2 names file 7 (past the table): it has no rank and no slot, and the in-range files still rank.
    const std::vector<std::uint32_t> stray = rw::rowfeat_detail::fileRanks( withFiles( 2, { 0, 1, 7 } ), { 0.5f, 0.9f, 3.0f } );
    // The in-range control: the best symbol score per file decides; a file whose symbols all score 0 reads 0 (unranked).
    const std::vector<std::uint32_t> inRange = rw::rowfeat_detail::fileRanks( withFiles( 3, { 2, 0, 2, 1 } ), { 0.2f, 0.4f, 0.7f, 0.0f } );
    const std::array cases {
        Case { "(U) a fileId past the file table: one rank per file (2), no slot for the stray id", stray.size() == 2 },
        Case { "(U) a fileId past the file table: the in-range files rank 1 (file 1) and 2 (file 0)", stray == std::vector<std::uint32_t> { 2, 1 } },
        Case { "(U) in range: file 2 (best 0.7) ranks 1, file 0 ranks 2, file 1 (all 0) reads 0", inRange == std::vector<std::uint32_t> { 2, 0, 1 } },
    };
    const auto failed = std::ranges::count_if( cases, []( const Case& c ) { return !c.held; } );
    for( const Case& c : cases )
    {
        rw::emitTo( stdout, "  {}  {}\n", c.held ? "PASS" : "FAIL", c.what );
    }
    rw::emitTo( stdout, "forrowfeatures_unit: {} case(s), {} failed\n", cases.size(), failed );
    return failed == 0 && !cases.empty() ? 0 : 1;
}

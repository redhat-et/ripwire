// forrowfeatures_unit.cpp — the (U) half of test/forrowfeaturescheck.sh: rowfeat_detail::fileRanks on a synthetic IngestResult,
// including a symbol whose fileId is past the file table, which no ingest the CLI runs hands over. The driver is compiled with the
// standard library's bounds checks on (libc++ hardening, libstdc++ assertions), so an out-of-range index aborts it instead of
// writing past the vector. Exit 0 = every case holds; each case prints PASS or FAIL, and the driver FAILs when it ran no case.

#include "forrowfeatures.h"

#include <cstdint>
#include <cstdio>
#include <string_view>
#include <vector>

namespace
{

int failures = 0;
int cases    = 0;

void expect( bool cond, std::string_view what )
{
    ++cases;
    rw::emitTo( stdout, "  {}  {}\n", cond ? "PASS" : "FAIL", what );
    failures += cond ? 0 : 1;
}

rw::IngestResult ingest( std::size_t files, const std::vector<std::uint32_t>& fileOf )
{
    rw::IngestResult ing;
    ing.files.resize( files );
    ing.symbols.resize( fileOf.size() );
    for( std::size_t i = 0; i < fileOf.size(); ++i )
    {
        ing.symbols[i].fileId = fileOf[i];
    }
    return ing;
}

} // namespace

int main()
{
    // Two files; symbol 2 names file 7 (past the table): it has no rank and no slot, and the in-range files still rank.
    const rw::IngestResult           bad   = ingest( 2, { 0, 1, 7 } );
    const std::vector<std::uint32_t> ranks = rw::rowfeat_detail::fileRanks( bad, { 0.5f, 0.9f, 3.0f } );
    expect( ranks.size() == 2, "(U) a fileId past the file table: one rank per file (2), no slot for the stray id" );
    expect( ranks.size() == 2 && ranks[1] == 1 && ranks[0] == 2, "(U) a fileId past the file table: the in-range files rank 1 (file 1) and 2 (file 0)" );

    // The in-range control: the best symbol score per file decides; a file whose symbols all score 0 reads 0 (unranked).
    const rw::IngestResult           good   = ingest( 3, { 2, 0, 2, 1 } );
    const std::vector<std::uint32_t> ranks2 = rw::rowfeat_detail::fileRanks( good, { 0.2f, 0.4f, 0.7f, 0.0f } );
    expect( ranks2 == std::vector<std::uint32_t> { 2, 0, 1 }, "(U) in range: file 2 (best 0.7) ranks 1, file 0 ranks 2, file 1 (all 0) reads 0" );

    if( cases == 0 )
    {
        rw::emitTo( stdout, "  FAIL  (U) no case ran\n" );
        return 1;
    }
    rw::emitTo( stdout, "forrowfeatures_unit: {} case(s), {} failed\n", cases, failures );
    return failures == 0 ? 0 : 1;
}

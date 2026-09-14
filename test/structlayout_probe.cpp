#include "structlayout.h"

#include <cstdio>
#include <cstring>

namespace
{

const char* stateName( rw::layout_registry::CheckState state )
{
    switch( state )
    {
        case rw::layout_registry::CheckState::NoRecords: return "no-records";
        case rw::layout_registry::CheckState::NotChecked: return "not-checked";
        case rw::layout_registry::CheckState::Agree: return "agree";
        case rw::layout_registry::CheckState::Disagree: return "disagree";
    }
    return "unknown";
}

}   // namespace

int main( int argc, char** argv )
{
    const rw::layout_registry::LayoutCheck result = rw::layout_registry::compare();
    std::printf( "state=%s units=%zu types=%zu", stateName( result.state ), result.unitCount, result.typeCount );
    if( result.mismatch.typeName != nullptr )
    {
        std::printf( " type=%s unit0=%s unit1=%s size0=%zu size1=%zu align0=%zu align1=%zu",
                     result.mismatch.typeName,
                     result.mismatch.unit0,
                     result.mismatch.unit1,
                     result.mismatch.size0,
                     result.mismatch.size1,
                     result.mismatch.align0,
                     result.mismatch.align1 );
    }
    std::putchar( '\n' );

    const bool single = argc > 1 && std::strcmp( argv[1], "single" ) == 0;
    if( single )
    {
        return result.state == rw::layout_registry::CheckState::NotChecked && result.unitCount == 1 ? 0 : 1;
    }
    return result.state == rw::layout_registry::CheckState::Disagree
                && result.unitCount == 2
                && result.mismatch.typeName != nullptr
                && result.mismatch.size0 != result.mismatch.size1
            ? 0
            : 1;
}

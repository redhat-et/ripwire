#pragma once

#include "structlayout.h"

#include <cstdint>

struct FixtureLayout
{
    std::uint32_t value = 0;
#if defined( RIPWIRE_LAYOUT_FIXTURE_WIDE )
    std::uint32_t extra = 0;
#endif
};

RIPWIRE_LAYOUT_REGISTER_TYPES( RIPWIRE_LAYOUT_TYPE_ENTRY( FixtureLayout ) );

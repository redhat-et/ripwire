#pragma once

// Sorts LAST, after zy_cog.hpp. Its bodyless re-declaration of `Cog` is the second claimant the
// anchor rule must decline to prefer, because the first claimant already carries a body.

namespace fixture
{

/// Re-declaration of the cog type, for headers that only need the name.
class Cog;

}   // namespace fixture

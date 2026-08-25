#pragma once

// The INERT-BRANCH control for the anchor-side rule, and it only works because of where this file
// sorts: BEFORE zz_cog_fwd.hpp. The first symbol named `Cog` in NodeId order is therefore the one
// below, which carries a body — so the anchor rule has nothing to prefer and must not move a byte.
// This is the fixture form of the duckdb/rocksdb rows the registration audits as unreachable
// (`TableCatalogEntry`, `ColumnFamilyData`), where an out-of-line constructor in the .cpp sorts ahead
// of the class definition in the header and already carries the claim.

namespace fixture
{

/// The cog: defined here, and re-declared later in a file that sorts after this one.
class Cog
{
public:
    /// Construct a cog with a tooth count.
    explicit Cog( int teeth )
        : teeth_( teeth )
    {
    }

    /// How many teeth the cog has.
    int teeth() const
    {
        return teeth_;
    }

private:
    int teeth_ = 0;
};

}   // namespace fixture

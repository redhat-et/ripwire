// estcalibfix — a FROZEN corpus for the est_tokens calibration band (tokenbudgetcheck #18).
// Do not edit: test/estcalib.manifest pins real o200k_base token counts of ripwire's output on
// THIS tree, and any edit here invalidates every pin. Regenerate with bench/tokenaudit/pin.py.
#include <cstddef>
#include <string>
#include <vector>

namespace ledger
{

struct Entry
{
    std::string name;
    std::size_t inputTokens;
    std::size_t outputTokens;
    std::size_t cacheReadTokens;
};

// Sum one class across the ledger. A zero here means "none found in these rows", never "none exists".
inline std::size_t sumInput( const std::vector<Entry>& rows )
{
    std::size_t total = 0;
    for( const Entry& e : rows )
    {
        total += e.inputTokens;
    }
    return total;
}

inline std::size_t sumOutput( const std::vector<Entry>& rows )
{
    std::size_t total = 0;
    for( const Entry& e : rows )
    {
        total += e.outputTokens;
    }
    return total;
}

// Cache reads are charged at a different rate than fresh input, so they are never folded into
// sumInput; a caller that wants one number asks for it and says which classes it merged.
inline std::size_t sumCacheRead( const std::vector<Entry>& rows )
{
    std::size_t total = 0;
    for( const Entry& e : rows )
    {
        total += e.cacheReadTokens;
    }
    return total;
}

inline std::size_t billableTotal( const std::vector<Entry>& rows )
{
    return sumInput( rows ) + sumOutput( rows ) + sumCacheRead( rows );
}

inline bool isEmpty( const std::vector<Entry>& rows )
{
    return rows.empty();
}

class Report
{
public:
    explicit Report( std::vector<Entry> rows ) : rows_( std::move( rows ) ) {}

    std::size_t total() const
    {
        return billableTotal( rows_ );
    }

    std::size_t rowCount() const
    {
        return rows_.size();
    }

    bool degenerate() const
    {
        return isEmpty( rows_ ) || total() == 0;
    }

private:
    std::vector<Entry> rows_;
};

}   // namespace ledger

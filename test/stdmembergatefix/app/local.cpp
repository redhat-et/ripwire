#include <vector>

namespace
{
struct Shelf
{
    bool empty() const { return true; }
};
}   // namespace

bool anyEmpty( const std::vector<int>& w ) { return w.empty(); }

// cachefix/friendly.cpp — the PRECISION half of the cache-rules fixture: the same jobs as
// unfriendly.cpp done cache-consciously. NO cache-* rule may fire anywhere in this file — the gate
// asserts zero findings, so every rule is measured against its own fix, not just its target.
// Parsed only, never run.
#include <algorithm>
#include <cstddef>
#include <memory>
#include <vector>

struct Node { int v; int next; };

// flat sorted pairs + lower_bound instead of std::map; contiguous values instead of std::list.
std::vector<std::pair<int, int>> g_lookup;
std::vector<Node> g_items;

// ownership and 2-D data stay contiguous: values by value, one flat buffer with a stride.
std::vector<Node> g_nodes;
std::vector<int> g_gridFlat;
std::size_t g_gridCols = 0;

void allocOnceOutsideLoop( int n, std::vector<int>& sink )
{
    sink.resize( static_cast<std::size_t>( n ) );
    for( int i = 0; i < n; ++i )
    {
        sink[ static_cast<std::size_t>( i ) ] = i;
    }
}

int sequentialWalk( const std::vector<Node>& nodes )
{
    int sum = 0;
    for( std::size_t i = 0; i < nodes.size(); ++i )
    {
        sum += nodes[ i ].v;
    }
    return sum;
}

void sequentialScan( std::vector<float>& a, float delta )
{
    for( std::size_t i = 0; i < a.size(); ++i )
    {
        a[ i ] += delta;
    }
}

int flatGrid( const std::vector<int>& grid, std::size_t rows, std::size_t cols )
{
    int sum = 0;
    for( std::size_t i = 0; i < rows; ++i )
    {
        for( std::size_t j = 0; j < cols; ++j )
        {
            sum += grid[ i * cols + j ];
        }
    }
    return sum;
}

int sharedByRef( const std::shared_ptr<Node>& sp )
{
    return sp ? sp->v : 0;
}

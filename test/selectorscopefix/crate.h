#pragma once
// selectorscopecheck fixture — the OTHER lid. See box.h.
namespace fixns
{

struct Crate
{
    int lid( int x ) { return crateHelper( x ); }
    int crateHelper( int x ) { return x + 2; }
};

}   // namespace fixns

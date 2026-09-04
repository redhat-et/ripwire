// Phase 5 fixture — the C-family arms (docs/EVALS.md "Phase 5").
//   free_fn    (F) bare `find( 3 )` from a FREE function: `find` is in the C++ table (<algorithm>), the only
//                  same-name symbols are METHODS of unrelated classes (`Buf::find`, `Other2::find`) — not
//                  reachable by an unqualified call from outside any class. Today: a split (`amb="1"`).
//                  After: vetoed, counted `external=`.
//   uses_decl  (G) control — bare `clamp( 1 )`: `clamp` is in the table too, but ext.h (included) DECLARES an
//                  in-repo free `clamp`, defined in decl.cpp: include evidence, the edge stays.
//   Grid::go   (M) bare `size()` inside a METHOD of `Grid : Buf` — Rule 1 misses (`Grid` defines no `size`),
//                  today the ladder splits `Buf::size` / `Other2::size` (`amb="1"`). After: the base walk
//                  lands `Buf::size` (`receiver-rule`), no `amb=`.
#include "ext.h"
#include <cstddef>

struct Buf
{
    std::size_t size() const
    {
        return 0;
    }
    int find( int v ) const
    {
        return v;
    }
};

struct Other2
{
    std::size_t size() const
    {
        return 1;
    }
    int find( int v ) const
    {
        return -v;
    }
};

struct Grid : Buf
{
    int go() const
    {
        return int( size() );
    }
};

int free_fn()
{
    return find( 3 );
}

int uses_decl()
{
    return clamp( 1 );
}

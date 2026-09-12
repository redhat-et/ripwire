// test/stdqualfix — file 12: the CUDA arm. `.cu` is Lang::Cpp parsed by tree-sitter-cuda, a different grammar
// from `.cpp`, so it proves the guard reads the qualifier that grammar hands over, not just tree-sitter-cpp's.

struct Grid
{
    int cells = 0;
    void fill( int v ) { cells = v; }   // the ONLY `fill` in the corpus
};

void clearHost( int* first, int* last )
{
    std::fill( first, last, 0 );         // → external (was: an edge to Grid::fill)
}

void clearGrid( Grid& g )
{
    g.fill( 0 );                         // → Grid::fill, a TRUE member call, kept
}

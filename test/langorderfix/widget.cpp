// langorderfix: the ANCHOR language holds only the bottom rung (Function, rank 2).
// LSP context (this document) and the corpus census both anchor here; task D makes
// `int Shape` front the struct/trait/module despite its rung.
int Shape( int f )
{
    return f * 4;
}

int use_shape( int k )
{
    return Shape( k );
}

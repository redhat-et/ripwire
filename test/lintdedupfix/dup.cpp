// §P6.1 gate fixture — two DISTINCT number_literal AST nodes carrying the SAME value, on the
// SAME line, inside the SAME function (mirrors bench/bench_convergence.cpp's shardOf, the
// originally-reported case). --lint's row shape carries only file:line (no column), so these
// two genuinely different captures render as a byte-identical <f> row unless the lint pipeline
// collapses them. Real-world instance of this class: h ^= h >> 33 appearing twice on one line.
static unsigned int scramble( unsigned long long h )
{
    h ^= h >> 33;  h *= 0xff51afd7ed558ccdULL;  h ^= h >> 33;
    return static_cast<unsigned int>( h );
}

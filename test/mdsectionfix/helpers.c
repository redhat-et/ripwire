/* helpers.c — the code side of the md fixture: the doc->code mention target and the
 * code-query pollution probe. codeIdentFn is mentioned in guide.md's backticks; the
 * cache warm compute wording overlaps guide.md's section prose ON PURPOSE, so the
 * code-vs-doc ranking arm has real competition to measure. */

/* the cache warm compute path for the pollution arm */
int zqCodeAnchorFn( int warmCount )
{
    return warmCount + 1;
}

int codeIdentFn( int x )
{
    return zqCodeAnchorFn( x );
}

// expandsibsfix/lonely.c — the ZERO case for test/expandsibscheck.sh: one symbol, no includes, so sibs=
// and inc= are both ABSENT (a documented zero, per model.h's skippedOversize convention — absence means
// "checked, found none", not "not computed").
int lonelyFn( void )
{
    return 42;
}

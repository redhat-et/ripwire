// expandtopk0fix/unique.c — the EXACT-NAME case for test/expandtopk0check.sh: uniqueTarget has exactly one
// definition in this corpus, so a bare --expand=uniqueTarget must default its own map to top-k=0.
int uniqueTarget( void )
{
    return 1;
}

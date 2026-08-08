// expandmodefix/small.c — the SMALL-file case for test/expandmodecheck.sh: the whole file is byte-cheaper
// than the default --expand bundle (map + body), so auto mode-selection must serve mode="whole-file".
int smallProbe( int value )
{
    return value * 2 + 1;
}

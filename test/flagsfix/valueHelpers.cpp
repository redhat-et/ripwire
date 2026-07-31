// valueHelpers.cpp — what the value-gated branches CALL once the gate is flipped on. Their only job is to
// be a real downstream edge from valueEntry, so --flip's "what starts executing" answer is non-empty.

int waveHelper()
{
    return 1;
}

int turnHelper()
{
    return 2;
}

// drains the pending eviction list — deliberately shares NO token with the gate's query, so plain
// lexical ranking scores it 0; only graph expansion from its caller can surface it.
void flushEvictionQueue()
{
    int drained = 0;
    (void)drained;
}

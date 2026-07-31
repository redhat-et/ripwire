// frobnicate the widget cache after a bulk insert — the LEXICAL ANCHOR for the gate's query
// ("frobnicate the widget cache"): its name carries every query token, so it tops the BM25 ranking.
// Its direct callee lives in queue.cpp and shares NO query token — lexically invisible on purpose.
void frobnicateWidgetCache()
{
    flushEvictionQueue();
    flushEvictionQueue();
}

// widget cache init — a second, weaker lexical hit (two query tokens).
void widgetCacheInit()
{
    int ready = 1;
    (void)ready;
}

// widget cache lookup — a third lexical hit (two query tokens).
int widgetCacheLookup( int key )
{
    return key;
}

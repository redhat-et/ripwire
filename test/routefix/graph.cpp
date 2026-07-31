// buildGraph — the identifier-named symbol the router's NameExact case targets. A query that literally
// says "buildGraph" must route to name-exact BM25 and surface THIS symbol, not every builder/every graph.
void buildGraph()
{
    int nodeCount = 0;
    (void)nodeCount;
}

// resolveSymbol — the resolution subsystem's entry point; the conceptual-query gate ("how does resolution
// work") should route to subtoken+body BM25 and can surface this by its "resolution" body vocabulary.
int resolveSymbol( int id )
{
    // resolution walks the scope chain until it finds a matching definition
    return id;
}

// buildIndex — a second builder, so "buildGraph" (whole-name) must NOT rank every builder equally.
void buildIndex()
{
    int rowCount = 0;
    (void)rowCount;
}

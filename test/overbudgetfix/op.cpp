// op.cpp — A4-F9 fixture: a symbol whose NAME contains "--" (C++ operator--). When it lands on the
// packBodies over-budget OMISSION path, its name is spliced into an XML comment where "--" is ill-formed
// (and "-->" terminates the comment early) — the pre-fix code emitted "<!-- ... operator-- -->", which
// xmllint rejects (breaking the G4 gate). The gate forces this path with a tiny --pack-budget-bytes.
struct Counter
{
    int v = 0;
    // a filler body big enough to consume the whole pack budget, so the NEXT def is omitted (over budget)
    int bump( int n )
    {
        int total = 0;
        for( int i = 0; i < n; ++i ) total += i * 2 + 1;
        total += v;
        v = total;
        return total;
    }
    Counter& operator--()
    {
        --v;
        return *this;
    }
};

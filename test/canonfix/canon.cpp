// canonfix/canon.cpp — gate fixture for S6-C canonical SCIP-style symbol strings.
//
// Two classes A and B BOTH define compute(). Each carries a canonical id `…::A::compute` vs
// `…::B::compute` — DISTINCT even though the bare name "compute" collides. A::driver() makes a bare
// member call compute(); under the §2a name ladder that is ambiguous (two same-name DEFS in one file)
// so driver gets edges to BOTH computes and the call is flagged amb. With S6-C the call resolves to the
// caller's own enclosing class A (member-scope narrowing + canonical-prefix locality), so the only edge
// is driver → A::compute and the call is NO LONGER ambiguous — `ambiguous=` drops to 0.
//
// Out-of-line definitions (the realistic C++ layout): the qualified `A::compute` / `A::driver`
// declarators give each def its enclosing scope, so the canonical id and the narrow have a scope to use.

struct A
{
    void driver();
    int  compute();
    int  value = 0;
};

struct B
{
    int  compute();
    int  value = 0;
};

int A::compute()
{
    return value + 1;
}

int B::compute()
{
    return value + 2;
}

void A::driver()
{
    value = compute();   // S6-C: resolves to A::compute ONLY (canonical scope A) — not B::compute
}

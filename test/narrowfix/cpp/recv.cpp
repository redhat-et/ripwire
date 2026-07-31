// narrowfix/recv.cpp — gate fixture for P2-D Rule 2 receiver-variable type narrowing.
//
// Foo and Bar BOTH define run(). g() declares `Foo x;` and `auto y = Bar();`, then calls x.run()
// and y.run(). Under the bare §2a ladder `run` is ambiguous (two same-name DEFS in one file) so each
// call splits 1/k across Foo::run AND Bar::run — a WRONG edge. Rule 2 resolves x.run() to Foo::run
// (x's type is Foo) and y.run() to Bar::run (y's inferred type is Bar) → no cross edge, `ambiguous=` drops.

struct Foo
{
    void run();
    int  value = 0;
};

struct Bar
{
    void run();
    int  value = 0;
};

void Foo::run()
{
    value = 1;
}

void Bar::run()
{
    value = 2;
}

void g()
{
    Foo  x;
    auto y = Bar();
    x.run();           // Rule 2: resolves to Foo::run ONLY (x : Foo)
    y.run();           // Rule 2: resolves to Bar::run ONLY (y : Bar, inferred from the Bar() ctor)
}

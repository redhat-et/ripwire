// resolvefix/shapes.cpp — gate fixture for P2-D one-hop type narrowing (Rule 1: class membership).
//
// Two classes A and B BOTH define process(). A::run() calls this->process(). Under the bare §2a
// ladder, `process` is ambiguous (two same-name DEFS in the same file/dir) so the call splits 1/k
// across A::process AND B::process — a WRONG edge to B. Rule 1 narrows `this->process()` to the
// caller's enclosing class (A) → the only edge is run → A::process, and `ambiguous=` drops.
//
// Out-of-line A::run() (defined below the class) is the realistic C++ layout: the qualified `A::run`
// declarator gives the caller scope = "A", so the receiver-is-`this` narrow has a scope to resolve
// against even when the body is not lexically inside the class braces.

struct A
{
    void run();
    void process();
    int  value = 0;
};

struct B
{
    void process();
    int  value = 0;
};

void A::process()
{
    value = 1;
}

void B::process()
{
    value = 2;
}

void A::run()
{
    this->process();   // Rule 1: resolves to A::process ONLY (not B::process)
}

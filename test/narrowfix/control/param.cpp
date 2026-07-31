// narrowfix/control/param.cpp — the NEGATIVE control for P2-D Rule 2 receiver-variable narrowing.
//
// Same two-classes-share-a-method setup as cpp/recv.cpp, but the receiver is a function PARAMETER
// (`Foo* p`), which has NO captured local var→type binding. So Rule 2 CANNOT fire: `p->run()` falls
// through to the §2a ladder and stays HONESTLY AMBIGUOUS (an edge to BOTH Foo::run and Bar::run,
// `ambiguous=1`). This is what makes the narrowcheck gate meaningful — it proves the cpp/recv.cpp
// `ambiguous=0` is a REAL narrow on a real binding, not a vacuously-unambiguous fixture: remove the
// binding (use a parameter) and the very same call shape goes ambiguous again.

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

void h( Foo* p )
{
    p->run();   // p is a PARAMETER (no var→type binding) → Rule 2 cannot fire → stays AMBIGUOUS (§2a)
}

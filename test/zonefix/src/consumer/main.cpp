// consumer/main.cpp — drives the dependency edges so pain/useless/balanced get the Ca/Ce this fixture
// is hand-verified against. Also supplies a `main` symbol so this module is a reachability entry point.
// Deliberately does NOT include useless/shape.h — nothing in this fixture does, so useless/ keeps Ca=0
// (module depended-on-by-nothing is the whole point of the Zone-of-Uselessness case).
#include "../pain/util.h"
#include "../balanced/mix.h"

int main()
{
    Util u;
    Mixed* m = nullptr;
    ( void )u;
    ( void )m;
    return 0;
}

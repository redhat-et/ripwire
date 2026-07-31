// alpha.cpp — tricky content for the regex→trigram prefilter soundness gate.
#include <cstdio>

struct Widget        // a CamelCase type for [A-Z]\w+ and char-class tests
{
    int   count;
    float ratio;
};

int   compute( int n )      { return n * 2; }            // ^int  anchored line target
int   tally  ( int n )      { return n + 1; }            // a second ^int  line

// A spanning pattern target: "Foo" ... (stuff) ... "Bar" on one logical line.
const char* span = "Foo middle Bar";                     // Foo.*Bar should match HERE

// alternation targets
void  alpha_open();
void  alpha_close();

// a deliberately RARE token so a rare-trigram regex narrows to one file (speedup demo).
const char* zylophoneXyzzy = "zylophoneXyzzy_marker";

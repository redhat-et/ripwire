// chaconefix/a.cpp — the FIRST call whose receiver static type is Hound: the Hound cone is computed here.
#include "zoo.h"

void g1() { Hound d; d.vocalize(); }   // cone {Hound, Creature} → Creature::vocalize only; Automaton::vocalize dropped

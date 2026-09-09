// chaconefix/b.cpp — the SECOND file to ask for the Hound cone (a memo HIT must equal the first answer),
// plus a different cone on the same callee name, a receiver with no inheritance facts, and a control.
#include "zoo.h"

void g2() { Hound d; d.vocalize(); }        // memo hit: byte-identical to g1's answer (Creature::vocalize only)
void g3() { Lynx c; c.vocalize(); }        // a DIFFERENT cone {Lynx, Creature} keyed on the same callee `vocalize`
void g4() { Lamp l; l.vocalize(); }       // cone {Lamp} keeps nothing → DEGRADE: tier untouched, stays ambiguous
void g5( Hound& p ) { p.vocalize(); }       // control: parameter receiver → no var→type binding → cone cannot fire
void g6() { Droid d; d.vocalize(); }        // a THIRD cone {Droid, Machine}: the memo grows AFTER Hound's entry exists
void g7() { Hound h; h.vocalize(); }        // Hound AGAIN, after the memo grew: a hit must be Hound's cone, not the newest

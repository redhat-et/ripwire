// The ACCESS sites. Each function below is one <function, struct type> co-access observation in the
// Chilimbi sense: the pairs it forms are every unordered pair of the DISTINCT fields it touches.
#include "hot.h"
#include "ambig.h"

// Touches x,y,z,vx,vy,vz -> 6 distinct fields -> 15 pairs, three of which (x/vx, y/vy, z/vz) sit exactly
// 64 bytes apart and are therefore un-colocatable at wt=0.00.
void integrateParticle( Particle* p, float dt )
{
    p->x = p->x + p->vx * dt;
    p->y = p->y + p->vy * dt;
    p->z = p->z + p->vz * dt;
}

// A second co-accessing function over the same three pairs, so the pair counts are 2, not 1 — the gate
// asserts a count that can only come from unioning two distinct functions.
void dampParticle( Particle* p )
{
    p->vx = p->vx * 0.5f + p->x * 0.0f;
    p->vy = p->vy * 0.5f + p->y * 0.0f;
    p->vz = p->vz * 0.5f + p->z * 0.0f;
}

// Cold path over the tag block only. Shares NO field with the two above, so it must not add to any
// position/velocity pair.
std::uint64_t hashTags( const Particle* p )
{
    return p->tagA ^ p->tagB ^ p->tagC ^ p->tagD ^ p->tagE ^ p->tagF;
}

// Straddler: `payload` is co-accessed with headA and trailer, so the straddle finding has a co-access
// witness and is not fired on an untouched field.
double sumStraddler( const Straddler* s )
{
    return s->payload[0] + s->payload[1] + double( s->headA ) + double( s->trailer );
}

// Compact: three co-accessed fields already inside one line. Nothing may fire.
float luminance( const Compact* c )
{
    return c->red * 0.2126f + c->green * 0.7152f + c->blue * 0.0722f;
}

// Ambiguous: `slot` is declared by both LeftBox and RightBox. Both accesses must be refused and counted.
std::uint64_t readSlots( LeftBox* l, RightBox* r )
{
    return l->slot + r->slot + l->leftOnly + r->rightOnly;
}

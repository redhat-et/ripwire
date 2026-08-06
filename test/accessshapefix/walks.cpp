// accessshapefix/walks.cpp — the four discriminating traps PLAN.md's Phase A design named as REQUIRED
// (its "correctness review" minimal set), plus the ambiguous-chase-field demo. Every function ALSO
// performs a normal field access so --field-affinity has a co-access observation to attribute (Phase A
// rides that existing pass; a loop whose fields are never touched via `.`/`->` produces no <f> row for
// this test to assert against, the same "touched fields only" filter fieldaffinity.h has always had).
#include "shapes.h"

// TRAP 1 — index despite an arrow-deref BODY. The advance is pointer arithmetic on `p` (`++p`); the
// `->payload` in the body is a plain field write, never an assignment through `p`'s OWN field, so no
// as-chase signal can ever fire on it (the pattern requires the RHS of an assignment to literally BE a
// field_expression — `p->payload = 0` has an field_expression on the LEFT of `=`, not the right).
void indexWalk( LinkedNode* first, int n )
{
    for( LinkedNode* p = first; p != first + n; ++p )
    {
        p->payload = 0;
    }
}

// TRAP 2 — chase. The advance itself reads p's own `next` field.
void chaseWalk( LinkedNode* head )
{
    for( LinkedNode* p = head; p; p = p->next )
    {
        p->payload = 0;
    }
}

// TRAP 3 — unknown. `it` has NO explicit pointer type (auto), so it cannot satisfy the as-ptrvar
// pointer_declarator gate; ++it is syntactically identical to a raw-pointer increment but this design
// fails closed rather than guess (PLAN.md Open Question 2's stated default).
void iteratorWalk( LinkedNode* v, int n )
{
    for( auto it = v; it != v + n; ++it )
    {
        it->payload = 0;
    }
}

// TRAP 4 — mixed. ONE loop, a comma-expression update carrying BOTH signals: `p` chases via `->next`,
// `idx` advances via `++`. Both are pointer-declared in the SAME initializer.
void mixedWalk( LinkedNode* head, LinkedNode* first )
{
    for( LinkedNode* p = head, *idx = first; p; p = p->next, ++idx )
    {
        p->payload = idx->payload;
    }
}

// Ambiguous-field demo — StepperA::step IS a real chase advance, but `step` is also declared by
// StepperB (shapes.h), so fieldaffinity.h's FieldOwners must refuse to attribute it to either struct:
// no <f n="step"> row anywhere may carry chase="1".
void stepperWalk( StepperA* s )
{
    for( ; s; s = s->step )
    {
        s->val = 0;
    }
}

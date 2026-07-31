/* C CALL-FORM MATRIX fixture — one line per call SPELLING the grammar distinguishes.
 * C has no `::`, so it carries no §H4 exposure by construction; this fixture is the sibling
 * control that says so out loud, and the parity reference for the ObjC field-call row.
 * Expected counts are literals read off this file. */

#define C_MAC( x ) ( ( x ) + 1 )

int cBareFn( void ) { return 1; }

int cPtrTargetFn( void ) { return 2; }

struct Ops
{
    int ( *dotFp )( void );
    int ( *arrowFp )( void );
};

int callerC( struct Ops* p, struct Ops val )
{
    int a = cBareFn();          /* 1. bare call */
    a += val.dotFp();           /* 2. field call through a struct value  — EXTRACTS as dotFp, never resolves */
    a += p->arrowFp();          /* 3. field call through a pointer       — EXTRACTS as arrowFp, never resolves */
    a += C_MAC( a );            /* 4. macro call — the macro def is itself a callable symbol */
    return a;
}

int callerCFnPtr( void )
{
    /* 5. EXTRACTS (as `fp`), never RESOLVES — call through a function-pointer variable.
     * Spelled with the extra accumulate step on purpose: the minimal two-line form is the same
     * token sequence as the C++ fixture's callerFnPtr, and a matrix whose language files clone
     * each other reads as new duplication debt rather than as parallel coverage. */
    int ( *fp )( void ) = &cPtrTargetFn;
    int total = 0;
    total += fp();
    total += total;
    return total;
}

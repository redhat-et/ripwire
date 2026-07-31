// dead.cpp — fixture for the "unreachable-code" built-in lint rule.
// Each function is annotated with whether the check MUST or MUST NOT flag it.

// MUST flag: statement after a same-block return.
int afterReturn( int x )
{
    return x + 1;
    int dead = compute();   // UNREACHABLE — flagged at THIS line
}

// MUST NOT flag: the return is inside an if-branch; the following statement is a reachable
// sibling of the `if`, not of the `return`. This is the critical false-positive guard.
int guardedReturn( int x )
{
    if( x < 0 )
        return -1;
    int reachable = x * 2;   // REACHABLE — must NOT be flagged
    return reachable;
}

// MUST flag: statement after a throw in the same block.
void afterThrow( int x )
{
    throw x;
    cleanup();               // UNREACHABLE — flagged
}

// MUST flag: statement after a break inside a loop body block.
void afterBreak()
{
    for( int i = 0; i < 10; ++i )
    {
        break;
        step( i );           // UNREACHABLE — flagged
    }
}

// MUST NOT flag: a bare `return;` as the LAST statement — nothing follows it.
void lastReturn( int x )
{
    doWork( x );
    return;
}

// MUST NOT flag: goto is excluded — the statement after it can be a label target.
void withGoto( int x )
{
    if( x ) goto done;
    fallthrough();           // REACHABLE via the straight-line path — must NOT be flagged
done:
    finish();
}

// MUST NOT flag: a comment after a return is not dead CODE.
int commentAfterReturn( int x )
{
    return x;
    // just an explanatory comment, not a statement
}

int compute();
void cleanup();
void step( int );
void doWork( int );
void fallthrough();
void finish();

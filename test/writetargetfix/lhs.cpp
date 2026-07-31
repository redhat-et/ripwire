// writetargetfix/lhs.cpp — A4-F24 gate fixture: isWriteTarget must classify the BASE OBJECT of a
// subscript/field LHS as the WRITE target (`a` in `a[i]=x`, `p` in `p->f=x`), while the index / member
// and every RHS name stay READs. Line numbers are LOAD-BEARING (writetargetcheck.sh pins each role to
// its exact line) — never insert/remove lines above a use-site without updating the gate.
//
//   line 14: buf[ idx ] = val;   → buf WRITE ; idx READ ; val READ
//   line 16: p->f      = val;   → p   WRITE ; val READ            (`f` is a field name, not a value use)
//   line 17: buf[ idx ] += 1;   → buf WRITE (augmented) ; idx READ

struct Node { int f = 0; };

void store( int* buf, int idx, int val, Node* p )
{
    buf[ idx ] = val;
    (void)0;
    p->f = val;
    buf[ idx ] += 1;
}

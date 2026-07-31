// alpha.cpp — one of TWO sibling files that each define a same-named free function `handler`.
// ctxpack's name resolver cannot tell which `handler` a bare `handler()` call means (both are in the
// same directory as the caller → tier-2 keeps both → an AMBIGUOUS split edge). The SCIP index pins the
// call to THIS one, so `--scip` collapses the split to a single precise edge tagged prov="scip".

int helperAlpha( int x )
{
    return x + 1;
}

void handler()
{
    helperAlpha( 41 );
}

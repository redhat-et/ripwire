// beta.cpp — the OTHER sibling defining the same-named `handler`. The name resolver treats it as an
// equally-valid target for a bare `handler()` call from caller.cpp; SCIP pins the call to alpha.cpp's
// `handler`, so under `--scip` NO edge to this `handler` is produced (the guess is replaced).

int helperBeta( int x )
{
    return x - 1;
}

void handler()
{
    helperBeta( 43 );
}

// caller.cpp — the site of the ambiguity. `run()` makes a bare `handler()` call. Two same-named
// `handler` defs live in sibling files (alpha.cpp, beta.cpp), both same-directory as this caller, so the
// name resolver keeps BOTH as targets → a split, AMBIGUOUS edge. The SCIP index (index.scip, generated
// by make_index.py) records that THIS call-site resolves to alpha.cpp's `handler`, so `--scip` produces
// exactly ONE precise edge run → alpha::handler, tagged prov="scip", and drops the beta guess.

void run()
{
    handler();
}

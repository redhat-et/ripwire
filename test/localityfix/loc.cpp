// localityfix/loc.cpp — gate fixture for the S6-C locality tie-break (adversarial HIGH-1 regression).
//
// THE BUG (now fixed): the locality tie-break used to compare canonical ids `path::scope::name` by RAW BYTE
// prefix. Two UNRELATED classes whose names merely start with the same letter (`Xenon` caller vs class `Xtra`)
// then scored a longer shared byte-run — *inside* the scope segment — than the genuinely-correct class
// (`Bravo`). So `Bravo b; b.go();` inside `Xenon::call()` resolved CONFIDENTLY to `Xtra::go` (WRONG) and the
// header reported `ambiguous=0`. The legitimate `Bravo::go` edge the §2a ladder reached was silently dropped.
//
// THE FIX: `sharedLocality` compares on WHOLE `/`- and `::`-delimited SEGMENTS. A partial overlap inside a
// segment (`Xenon` vs `Xtra`) counts as ZERO locality. So both `Xtra` and `Bravo` share only the file PATH with
// the caller — they TIE — no candidate is strictly more local, and the call stays HONESTLY AMBIGUOUS (count=2,
// ambiguous=1) instead of a false-confident wrong pick. The receiver is a PARAMETER (`Bravo* b`), NOT a local:
// P2-D Rule 2 narrows a *local* `Bravo b` to its type (before the tie-break), but a param has no binding to use.
//
// Out-of-line method defs (the realistic C++ layout) give each `go` its enclosing scope, so the canonical ids
// `…::Xtra::go` / `…::Bravo::go` exist and the tie-break has scopes to (correctly NOT) discriminate on.

struct Xtra
{
    int go();
};

struct Bravo
{
    int go();
};

int Xtra::go()  { return 1; }
int Bravo::go() { return 2; }

struct Xenon
{
    void call( Bravo* b );
};

void Xenon::call( Bravo* b )
{
    // b is a PARAMETER → no var→type binding → Rule 2 cannot fire → this call reaches the locality tie-break.
    b->go();  // FIXED: stays AMBIGUOUS (Xtra/Bravo tie on path-only locality) — never a confident Xtra::go pick
}

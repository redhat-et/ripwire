// cppqualdecoyfix/hostile.cpp — THIS FILE IS DELIBERATELY NOT VALID C++. It exists to pin the behaviour of
// operatorNameStart() on the one spelling that violated its documented contract (V3-L-2).
//
// The contract says: return the start of the TRAILING operator name, npos for a plain identifier. Written
// with a bare `rfind( "operator" )` it also returned non-npos for a NON-trailing operator segment —
// `op::operator>::go` yielded opStart=4, so the re-split produced name `operator>::go` and qualifier `op`.
// An operator cannot name a scope, so no valid C++ reaches it; the helper now requires the operator's
// punctuation run to reach end-of-text, which rejects the spelling outright.
//
// HONEST LABEL, so nobody reads more into this file than it carries: this is a REGRESSION FENCE, not
// red-first evidence. Measured on both binaries, pre-fix and post-fix, the graph output for the line below
// is IDENTICAL (the reference is named `go` either way) — the contract violation was never observable
// through the C++ capture path, which is why it was a LOW and not a defect. The fence pins that the
// spelling keeps resolving to `go` and keeps adding no ambiguity, so a future change to the operator scan
// cannot start mis-splitting it unnoticed.
//
// Kept in its OWN file so tree-sitter's error recovery cannot perturb decoy.cpp, whose gate assertions are
// line-number literals.

namespace op
{

struct Q { int v = 0; };

int go( const Q& q ) { return q.v; }

}

int hostileCaller( const op::Q& q )
{
    return op::operator>::go( q );   // not compilable: an operator cannot name a scope
}

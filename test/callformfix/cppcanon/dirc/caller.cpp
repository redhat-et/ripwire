// C++ CANONICAL-MULTI-MATCH caller — the C++ face of the W3-RUST fixup's `|| canonical` change to
// graph.h's tier-3 rescue, carried into this round's matrix because cppqualcheck was frozen by
// other lanes when the fix landed (§V3 fixup wave, "Carry to
// W4").
//
// THE CLASS: a qualified call whose canonical key `q::canonFn` matches SEVERAL definitions, none of
// them in this caller's file or directory. Before the fix the canonical tier returned "not unique"
// and the call fell to tier-3's unique-global-or-DROP rule, so BOTH edges died SILENTLY — no edge,
// no `amb=`, no `unresolved=` movement. That is the round's headline failure mode (a silent drop is
// worse than an ambiguous one), and it is measured here rather than asserted.
//
// EXPECTED, read off the three files by hand: exactly ONE call site, TWO definitions of equal
// arity under the SAME qualifier => two `<c n="canonFn"/>` rows and `amb="1"` on this caller, and
// `ambiguous=1` in the corpus header. Never one silently-chosen target, and never zero.

int crossDirCaller( int a )
{
    return q::canonFn( a );
}

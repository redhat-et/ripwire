// leaf.cpp -- a purely PERIPHERAL cluster: several members (6), a STAR topology (leafRun calls each leaf
// member directly; members never call each other, so no member is a chain dead-end that pools cascading
// PageRank -- a plain linked chain would create exactly that rank-sink artifact at its tail, which is not
// the "several trivial members" shape this fixture needs). A single inbound edge from orchestratorMain and
// no other external fan-in. Deliberately the LARGEST cluster in this fixture so the pre-fix "order by raw
// member count" sort ranks it first; the mass-based fix (V6) must not rank it above the much smaller, much
// more cross-cluster-connected hub cluster in hub.cpp.

int leafMember1() { return 1; }
int leafMember2() { return 2; }
int leafMember3() { return 3; }
int leafMember4() { return 4; }
int leafMember5() { return 5; }
int leafRun()
{
    // separate statements, not one summed return expression -- test/zoomfix/core/engine.cpp's
    // engineStepA4 already has that shape, and reusing it here structurally cloned against a PREEXISTING
    // fixture symbol (quality-delta flagged it as a preexisting-worse duplication finding, not a
    // new-symbol one). The call-graph edges (leafRun -> each leafMember) are what this fixture needs;
    // the statement shape is free to differ.
    leafMember1();
    leafMember2();
    leafMember3();
    leafMember4();
    return leafMember5();
}

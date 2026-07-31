// core/engine.cpp — a tightly-coupled cluster A (engine sub-system). Each fn calls the next, forming a
// dense intra-cluster chain so Louvain groups them at level 0; the cluster then contracts upward.
//
// `empty()` is a deliberately trivial accessor-named helper called from A1-A4 (fan-in 4, higher than
// engineStepA1's fan-in of 3 — the next highest in the cluster) — reproduces §P6.2: the pre-fix label
// picker chose the highest-PageRank member with no regard for whether its name is a meaningless accessor,
// so this cluster's community label became `empty@engine.cpp` instead of a name that tells a reader
// anything. `engineRun` deliberately does NOT call empty() — a 3-term sum kept distinct from engineStepA4's
// 4-term sum so the two functions don't read as a structural clone of each other to --quality-delta.

int empty()        { return 0; }
int engineStepA1() { return 1 + empty(); }
int engineStepA2() { return engineStepA1() + engineStepA1() + empty(); }
int engineStepA3() { return engineStepA2() + engineStepA1() + empty(); }
int engineStepA4() { return engineStepA3() + engineStepA2() + engineStepA1() + empty(); }
int engineRun()    { return engineStepA4() + engineStepA3() + engineStepA2(); }

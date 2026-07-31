// core/scheduler.cpp — a second cluster B in core (scheduler sub-system). Dense intra-cluster chain, with a
// SINGLE thin edge into the engine cluster (engineRun) so the two core clusters sit in the same top module
// after contraction but remain distinct level-0 communities.

int engineRun();   // cross-cluster (still in core/)

int schedStepB1() { return 2; }
int schedStepB2() { return schedStepB1() + schedStepB1(); }
int schedStepB3() { return schedStepB2() + schedStepB1(); }
int schedStepB4() { return schedStepB3() + schedStepB2() + schedStepB1(); }
int schedRun()    { return schedStepB4() + schedStepB3() + engineRun(); }

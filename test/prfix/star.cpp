// star.cpp — a 4-function PageRank oracle: three symmetric callers all call the same hub, and NOTHING
// else. Hand-derivable expectation: hub's rank is the highest and (by symmetry) each caller's rank is
// EQUAL to the other two; hub's rank is well above any single caller's (a caller only ever forwards
// 1/N_out of ITS OWN modest rank into hub, while hub gathers all three).

int hub() { return 0; }

int caller_x() { return hub(); }
int caller_y() { return hub(); }
int caller_z() { return hub(); }

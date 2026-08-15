// module_l.cpp -- see module_a.cpp; a further satellite cluster bridging into hub.cpp.

int validateCore();   // cross-cluster (hub.cpp)

int lStep1()     { return 1; }
int lStep2()     { return lStep1() + lStep1(); }
int moduleLRun() { return lStep2() + lStep1() + validateCore(); }

// module_i.cpp -- see module_a.cpp; a further satellite cluster bridging into hub.cpp.

int validateCore();   // cross-cluster (hub.cpp)

int iStep1()     { return 1; }
int iStep2()     { return iStep1() + iStep1(); }
int moduleIRun() { return iStep2() + iStep1() + validateCore(); }

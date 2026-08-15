// module_g.cpp -- see module_a.cpp; a further satellite cluster bridging into hub.cpp.

int validateCore();   // cross-cluster (hub.cpp)

int gStep1()     { return 7; }
int gStep2()     { return gStep1() + gStep1(); }
int moduleGRun() { return gStep2() + gStep1() + validateCore(); }

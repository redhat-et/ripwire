// module_j.cpp -- see module_a.cpp; a further satellite cluster bridging into hub.cpp.

int validateCore();   // cross-cluster (hub.cpp)

int jStep1()     { return 1; }
int jStep2()     { return jStep1() + jStep1(); }
int moduleJRun() { return jStep2() + jStep1() + validateCore(); }

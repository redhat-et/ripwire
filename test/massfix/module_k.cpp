// module_k.cpp -- see module_a.cpp; a further satellite cluster bridging into hub.cpp.

int validateCore();   // cross-cluster (hub.cpp)

int kStep1()     { return 1; }
int kStep2()     { return kStep1() + kStep1(); }
int moduleKRun() { return kStep2() + kStep1() + validateCore(); }

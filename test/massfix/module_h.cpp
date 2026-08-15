// module_h.cpp -- see module_a.cpp; a further satellite cluster bridging into hub.cpp.

int validateCore();   // cross-cluster (hub.cpp)

int hStep1()     { return 8; }
int hStep2()     { return hStep1() + hStep1(); }
int moduleHRun() { return hStep2() + hStep1() + validateCore(); }

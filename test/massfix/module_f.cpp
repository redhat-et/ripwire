// module_f.cpp -- see module_a.cpp; a further satellite cluster bridging into hub.cpp.

int validateCore();   // cross-cluster (hub.cpp)

int fStep1()     { return 6; }
int fStep2()     { return fStep1() + fStep1(); }
int moduleFRun() { return fStep2() + fStep1() + validateCore(); }

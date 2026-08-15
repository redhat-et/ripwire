// module_e.cpp -- see module_a.cpp; a further satellite cluster bridging into hub.cpp.

int validateCore();   // cross-cluster (hub.cpp)

int eStep1()     { return 5; }
int eStep2()     { return eStep1() + eStep1(); }
int moduleERun() { return eStep2() + eStep1() + validateCore(); }

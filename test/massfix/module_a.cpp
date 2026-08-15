// module_a.cpp -- one of twelve small satellite clusters (module_a..module_l.cpp) whose only job (besides
// its own tiny internal chain) is to place a single bridge edge into hub.cpp's validateCore, giving the
// hub cluster fan-in from TWELVE distinct communities instead of the usual single bridge every other
// fixture cluster carries.

int validateCore();   // cross-cluster (hub.cpp)

int aStep1()     { return 1; }
int aStep2()     { return aStep1() + aStep1(); }
int moduleARun() { return aStep2() + aStep1() + validateCore(); }

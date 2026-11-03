#include "depslog.h"
bool OpenLog(DepsLog* log, std::string* err) { return log->Recompact("x", err); }
int main() { DepsLog l; std::string e; return OpenLog(&l, &e) ? 0 : 1; }

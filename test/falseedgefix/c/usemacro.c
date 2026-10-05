#include "macro.h"
int region(int);
int clampit(int v) { return CLAMP(v, 0, 10) + region(v); }

#include "mux.h"

int
window_count(void)
{
	return 1;
}

/* clock() is the C library's: a call never reaches struct clock, and the library name proves it is outside. */
long
elapsed(void)
{
	return (long)clock();
}

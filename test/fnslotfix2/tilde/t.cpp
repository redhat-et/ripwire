struct tops { void (*tdraw)(void); };
static void tdrawImpl(void) {}
struct tops tinst = { .tdraw = tdrawImpl };
void tfire(struct tops *p) { p->tdraw(); }
int operator~(tops& p) { p.tdraw(); return 0; }

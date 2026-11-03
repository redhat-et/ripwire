struct ops { void (*draw)(void); };
static void cdraw(void) {}
struct ops o = { .draw = cdraw };
void cfire(struct ops *p) { p->draw(); }

// near miss: an inline member-pointer field declarator `int (Hdr2::*fn)( int )` parses as an ERROR node (a floor: no row)
struct Hdr2 { int Walk(int x); };
int Hdr2::Walk(int x) { return x; }
struct Slot2 { const char* name; int (Hdr2::*fn)(int); };
static const Slot2 kSlots2[] = { { "walk", &Hdr2::Walk } };
int go_inline(Hdr2* h, const Slot2* s) { return (*h.*s->fn)(1); }

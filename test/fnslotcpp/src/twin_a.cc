namespace a { struct Twin { int Go(int x); }; int Twin::Go(int x) { return x; } }
struct Hook { int (a::Twin::*cb)(int); };
static Hook kA = { &a::Twin::Go };
int fire_twin(a::Twin* t, Hook* h) { return (t->*h->cb)(1) + (*t.*kA.cb)(2); }

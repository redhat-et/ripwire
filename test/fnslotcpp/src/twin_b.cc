namespace b { struct Twin { int Go(int x); }; int Twin::Go(int x) { return x * 2; } }
// X20: a C++ function-pointer field named like the Go fixture's field (x/box.go Hook.cb)
struct Hook2 { int (*cb)(int); };
static int cpp_cb(int x) { return x; }
static Hook2 kH2 = { &cpp_cb };
int fire_h2(struct Hook2* h) { return h->cb(1); }

/* L-1: a nested store the climb cannot type (6 levels, a 2-D array) hides behind the typed tier: the site says how many */
typedef struct L5_ { int (*cb)(int); } L5;
typedef struct L4_ { L5 a; } L4;
typedef struct L3_ { L4 a; } L3;
typedef struct L2_ { L3 a; } L2;
typedef struct L1_ { L2 a; } L1;
typedef struct L0_ { L1 a; } L0;
static int deepfn(int x) { return x; }
static int shallowfn(int x) { return x; }
static const L0 kDeep = { .a = { .a = { .a = { .a = { .a = { .cb = deepfn } } } } } };
static const L2 kShallow = { .a = { .a = { .a = { .cb = shallowfn } } } };
int deep_use(L0* d, L2* s) {
  return d->a.a.a.a.a.cb(2) + s->a.a.a.cb(3);
}

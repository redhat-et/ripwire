/* F-4: a struct with more than 4 slot fields — the cap keeps the field a caller calls through, not the first four by name */
typedef struct Cls_ {
  int (*aaa)(int);
  int (*bbb)(int);
  int (*ccc)(int);
  int (*ddd)(int);
  int (*zzw)(int);
} Cls;
static int fa(int x) { return x; }
static int fb(int x) { return x; }
static int fc(int x) { return x; }
static int fd(int x) { return x; }
static int z1(int x) { return x; }
static int z2(int x) { return x + 1; }
static int z3(int x) { return x + 2; }
static const Cls kC1 = { .aaa = fa, .bbb = fb, .ccc = fc, .ddd = fd, .zzw = z1 };
static const Cls kC2 = { .zzw = z2 };
static const Cls kC3 = { .zzw = z3 };
int run_zzw(Cls* c) { return c->zzw(1); }

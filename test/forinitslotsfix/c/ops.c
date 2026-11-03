struct ops {
    int (*run)(int);
    int (*stop)(int);
};

static int f(int x) { return x + 1; }
static int g(int x) { return x - 1; }

const struct ops o = { .run = f, .stop = g };

struct plain {
    int a;
    int b;
};

int dispatch(const struct ops *p, int v) { return p->run(v) + p->stop(v); }

const struct ops positional_ops = { f, g };

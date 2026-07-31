/* C call-form fixture. */
struct Ops { int (*init)(void); };
static int freeFn(void) { return 1; }
#define MAC() freeFn()

static int caller(struct Ops* ops, struct Ops val)
{
    int a = freeFn();        /* 1. bare call */
    a += ops->init();        /* 2. arrow field call */
    a += val.init();         /* 3. dot field call */
    a += MAC();              /* 4. macro call */
    int (*fp)(void) = freeFn;
    a += fp();               /* 5. fn-pointer var call */
    return a;
}

struct ops { void (*run)(int v); };
void sink_write(int v);
static void run_fast(int v) { sink_write(v + 1); }
static void run_slow(int v) { int w = v * 2; w = w + 3; sink_write(w); }
static void run_noop(int v) { (void)v; }
static struct ops g_ops_a = { .run = run_fast };
static struct ops g_ops_b = { .run = run_slow };
static struct ops g_ops_c = { .run = run_noop };
struct ops *pick(int k) { return k ? &g_ops_a : (k < 0 ? &g_ops_c : &g_ops_b); }
void start_job(struct ops *o, int v)
{
    o->run(v);
}
void sink_write(int v) { (void)v; }

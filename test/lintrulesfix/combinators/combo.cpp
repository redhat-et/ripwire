// combinators fixture — exercises inside / not-inside / not-matches span algebra.
// Parsed only, never run. Line numbers are load-bearing: the test asserts WHICH lines survive.
//
// Layout (1-based line numbers matter — do not reflow):
//   - a raw `new` at namespace scope (OUTSIDE any function) → dropped by `inside (function_definition)`
//   - a raw `new` INSIDE a function                          → kept by `inside`
//   - `new Pool<int>()` inside a function                    → kept by inside, but DROPPED by not-matches ^Pool
//   - a `log()` call inside a normal function                → kept by not-inside
//   - a `log()` call inside a function named skipMe          → DROPPED by not-inside (scope name ^skip)

struct Widget { int v; };
struct PoolThing { int v; };

// namespace-scope new — NOT inside any function_definition
static Widget* g_stray = new Widget{ 1 };            // L15: inside → DROP (no enclosing function)

void makesWidget()
{
    Widget* w = new Widget{ 2 };                     // L19: inside → KEEP (enclosing function)
    (void)w;
}

void makesPool()
{
    PoolThing* p = new PoolThing();                  // L25: not-matches ^Pool → DROP (kept by inside otherwise)
    (void)p;
}

void log( const char* ) {}

void normalCaller()
{
    log( "hello" );                                  // L33: not-inside skip* → KEEP (scope is normalCaller)
}

void skipMe()
{
    log( "quiet" );                                  // L38: not-inside skip* → DROP (scope name starts with skip)
}

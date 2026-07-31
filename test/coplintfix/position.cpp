// connascence-of-position fixture: calls with many positional args vs few-arg calls.
// The CoP smell: function calls with 5+ positional arguments force callers to know
// the precise order; reordering arguments breaks all callers silently.

#include <cstdint>
#include <string>

// ── "bad" function: 6 positional args (CoP violation) ──────────────────────────
// Callers MUST know the order: x, y, z, radius, color_id, flags
void drawCircle(
    float x,
    float y,
    float z,
    float radius,
    uint32_t color_id,
    uint32_t flags
)
{
    // function body (irrelevant)
}

// ── "good" function: 3 positional args (healthy) ────────────────────────────────
void setPosition( float x, float y, float z )
{
    // body irrelevant
}

void demo()
{
    // BAD: call with 6 positional args — this is the CoP smell we want to catch
    drawCircle( 1.5f, 2.5f, 3.5f, 0.5f, 0xFF0000, 0x01 );   // <- SHOULD BE FLAGGED

    // GOOD: call with 3 positional args — healthy
    setPosition( 1.0f, 2.0f, 3.0f );   // <- OK, not flagged

    // GOOD: call with 4 args — still below threshold
    float results[ 4 ] = { 0, 0, 0, 0 };
    // some_func( 1, 2, 3, 4 );   // <- OK (commented, but if not would be OK at 4)

    // GOOD: call with 2 args
    printf( "result: %d\n", 42 );   // <- OK, only 2 args
}

// ── another "bad" function: 7 positional args ────────────────────────────────
// More egregious CoP violation
bool allocateMemory(
    uint32_t id,
    size_t size,
    int priority,
    bool persistent,
    void* owner,
    const char* label,
    int timeout_ms
)
{
    return true;
}

void testBadAlloc()
{
    // SHOULD BE FLAGGED: 7 positional args
    allocateMemory( 1, 1024, 10, true, nullptr, "buffer", 5000 );   // <- FLAGGED
}

// ── "good" function but badly called ────────────────────────────────────────
void transformMatrix(
    float a, float b, float c,
    float d, float e, float f,
    float g, float h, float i
)
{
    // 9 positional parameters (arguably bad design, but we're testing calls, not defs)
}

void testMatrixCall()
{
    // This call has 9 positional args — should be flagged
    transformMatrix( 1, 0, 0, 0, 1, 0, 0, 0, 1 );   // <- FLAGGED (9 args)
}

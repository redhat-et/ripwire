// H4 gate fixture (ObjC): field_expression call parity with the C grammar. `ops->init()` is
// a call through a function-pointer struct field — it now EXTRACTS a "init" reference (matching
// C's own documented behavior for the identical shape) but there is no symbol named "init" in
// this fixture, so the reference stays UNRESOLVED — a zero-cost honesty gain, not a resolution
// gain. Control: freeFn() is a bare C call, already captured pre-H4.
struct Ops { void (*init)(void); };
static void freeFn(void) {}

static void caller(struct Ops* ops)
{
    freeFn();      // control: bare call (worked before H4)
    ops->init();   // field-expression call (H4 widening: extracts, resolves to nothing)
}

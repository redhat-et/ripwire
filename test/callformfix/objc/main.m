/* OBJC CALL-FORM MATRIX fixture — one line per call SPELLING the grammar distinguishes.
 * Expected counts are literals read off this file.
 *
 * The `ops->init()` row is this round's C/ObjC PARITY line: queries/objc/tags.scm had no
 * field_expression call pattern although its parent C grammar carries one, so a struct
 * function-pointer field call minted no reference at all. It extracts now; it still does not
 * RESOLVE (the field name is not a function definition), which is the honest end state and the
 * same one queries/c/tags.scm produces. */

@interface Widget
- (int)messageFn;
- (int)messageArgFn:(int)a with:(int)b;
@end

@implementation Widget
- (int)messageFn { return 1; }
- (int)messageArgFn:(int)a with:(int)b { return a + b; }
@end

struct Ops
{
    int ( *initFp )( void );
};

int objcBareFn( void ) { return 2; }

int callerObjc( Widget* obj )
{
    int a = objcBareFn();               /* 1. plain C function call */
    a += [obj messageFn];               /* 2. message send, no arguments */
    a += [obj messageArgFn:1 with:2];   /* 3. message send with keyword arguments */
    return a;
}

/* Kept in its OWN caller so the probe's 12-references-per-symbol cap cannot hide it: the field-call
 * row is asserted PRE-resolution, and a truncated list would make that arm vacuous. */
int callerObjcField( struct Ops* ops )
{
    return ops->initFp();               /* 4. struct fn-pointer field call — EXTRACTS, never resolves */
}

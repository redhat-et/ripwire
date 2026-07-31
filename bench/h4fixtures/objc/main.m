// ObjC call-form fixture.
@interface Widget : NSObject
- (void)bump;
+ (Widget*)make;
@end
@implementation Widget
- (void)bump {}
+ (Widget*)make { return 0; }
@end

struct Ops { void (*init)(void); };
static void freeFn(void) {}

static void caller(struct Ops* ops)
{
    freeFn();                     // 1. C-style bare call
    ops->init();                  // 2. call through struct field
    Widget* w = [Widget make];    // 3. class message send
    [w bump];                     // 4. instance message send
}

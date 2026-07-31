// C++ call-form fixture — every call SPELLING the grammar distinguishes.
namespace ctx { namespace inner {
    int targetFn( int x ) { return x; }
    struct Widget
    {
        static int make();
        int bump();
    };
    int Widget::make() { return 1; }
    int Widget::bump() { return 2; }
} }
namespace ctx { int midFn() { return 3; } }
int freeFn() { return 4; }
template <typename T> T tmplFn( T v ) { return v; }
struct S { int method() { return 5; } };

int caller()
{
    int a = freeFn();                          // 1. bare call
    a += ctx::midFn();                         // 2. 2-segment qualified
    a += ctx::inner::targetFn( a );            // 3. 3-segment qualified
    a += ctx::inner::Widget::make();           // 4. 4-segment qualified (static method)
    S s; a += s.method();                      // 5. member call (dot)
    S* p = &s; a += p->method();               // 6. member call (arrow)
    a += ::freeFn();                           // 7. global-scope qualified ::f()
    a += tmplFn<int>( a );                     // 8. explicit-template-arg call
    a += ctx::inner::Widget().bump();          // 9. temp-object member call
    int (*fp)() = &freeFn; a += fp();          // 10. call through fn pointer var
    return a;
}

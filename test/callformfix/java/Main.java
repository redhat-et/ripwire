// JAVA CALL-FORM MATRIX fixture — one line per call SPELLING the grammar distinguishes.
// Expected counts are literals read off this file. ABSENT rows are asserted at 0 and fence an
// honest reject.
package demo.pkgx;

class Widget
{
    static int makeFn() { return 1; }
    int memberFn() { return 2; }
}

class Outer
{
    static class Inner
    {
        static int threeSeg() { return 3; }
        int ping() { return 4; }
    }
    static class Mid
    {
        static class Deep { int pong() { return 5; } }
    }
}

class PkgType { int hum() { return 6; } }

class GenBox<T> { T hold( T v ) { return v; } }

class GenOuter
{
    static class GenInner<T> { T grip( T v ) { return v; } }
}

class Main
{
    static int bareFn() { return 7; }

    int thisFn() { return 8; }

    int runSpellings()
    {
        int a = bareFn();                             // 1. bare call
        Widget w = new Widget();                      // 5. new, unqualified ctor
        a += w.memberFn();                            // 2. member call
        a += Widget.makeFn();                         // 3. static call through the type
        a += Outer.Inner.threeSeg();                  // 4. 3-segment invocation chain
        a += this.thisFn();                           // 6. explicit this receiver
        Outer.Inner i = new Outer.Inner();            // 7. scoped new, 2 segments
        a += i.ping();
        Outer.Mid.Deep d = new Outer.Mid.Deep();      // 8. scoped new, 3 segments
        a += d.pong();
        demo.pkgx.PkgType p = new demo.pkgx.PkgType();// 9. fully package-qualified new
        a += p.hum();
        return a;
    }

    int runAbsent()
    {
        // 10. ABSENT (disclosed callback caveat) — a method REFERENCE is not an invocation; it
        //     names the target without calling it, so no call edge is minted.
        java.util.function.Supplier<Integer> s = Widget::makeFn;
        // 11. ABSENT — a BARE generic `new`: the type child is a generic_type, not a
        //     type_identifier, so the object_creation pattern does not bind.
        GenBox<String> g = new GenBox<String>();
        // 12. ABSENT — a QUALIFIED generic `new`, same mechanism one level out.
        GenOuter.GenInner<String> q = new GenOuter.GenInner<String>();
        return s.get() + g.hold( "x" ).length() + q.grip( "y" ).length();
    }
}

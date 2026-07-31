// Java call-form fixture.
class Widget {
    Widget() {}
    static Widget make() { return new Widget(); }
    void bump() {}
}
class Outer {
    static class Inner {
        Inner() {}
        static void go() {}
    }
}
public class Main {
    void helper() {}
    void caller() {
        helper();                     // 1. bare call
        Widget w = Widget.make();     // 2. Type.static call
        w.bump();                     // 3. method call
        Outer.Inner.go();             // 4. 3-segment chain call
        this.helper();                // 5. this-qualified
        new Widget();                 // 6. bare new
        new Outer.Inner();            // 7. qualified new
        Runnable r = Widget::make;    // 8. method reference
        java.util.List.of(1);         // 9. fq static call
    }
}

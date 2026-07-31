// H4 gate fixture (Java): qualified `new` at 2 and 3 segments, plus a bare-new control.
// No explicit constructors anywhere — every class name is a single unambiguous def
// (tree-sitter emits no constructor_declaration node for an implicit default ctor), so
// ambiguous=0 for the whole fixture. The ctor-collision precedent (a class WITH an explicit
// same-named constructor) is exercised separately by bench/h4fixtures/java.
class Widget {}

class Outer {
    static class Inner {}
}

class A {
    static class B {
        static class C {}
    }
}

public class Main {
    void caller() {
        new Widget();          // control: bare new (worked before H4)
        new Outer.Inner();     // 2-segment qualified new (H4 widening)
        new A.B.C();           // 3-segment qualified new (H4 widening)
    }
}

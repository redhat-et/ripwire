// JavaScript call-form fixture.
class Widget {
    static make() { return new Widget(); }
    bump() {}
}
function free() {}
const obj = { deep: { fn() {} } };
const ns = { Inner: class Inner2 { static go() {} } };

function caller() {
    free();                    // 1. bare call
    const w = Widget.make();   // 2. static member call
    w.bump();                  // 3. method call
    obj.deep.fn();             // 4. 3-level member chain
    ns.Inner.go();             // 5. object-namespace chain
    w?.bump();                 // 6. optional-chain call
    new Widget();              // 7. bare new
    new ns.Inner();            // 8. qualified new
    tag`x`;                    // 9. tagged template
}
function tag(s) { return s; }

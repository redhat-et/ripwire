// H4 gate fixture (JS): qualified `new` at 2 and 3 segments, plus a bare-new control.
// No explicit constructors — every class name is a single unambiguous def (ambiguous=0).
class Widget {}
// QnInner (not "Inner"): the widened pattern binds the PROPERTY name (`ns.Inner` -> "Inner"), so
// the class AND the property key must both read "QnInner" for this to resolve locally. Plain
// "Inner" would collide with the sibling survey fixture bench/h4fixtures/js/main.js, which has a
// dangling `new ns.Inner()` ref with NO local "Inner" def (its class is deliberately named
// "Inner2" — see H4_grammarSurvey_2026-07-30.md's TS/JS section) — real tier-3 unique-global
// resolver behavior, but cross-fixture noise this gate doesn't want to own.
class QnInner { static go() {} }
class Boxed { static make() {} }
const ns = { QnInner: QnInner, deep: { Boxed: Boxed } };

function caller() {
    new Widget();          // control: bare new (worked before H4)
    new ns.QnInner();       // 2-segment qualified new (H4 widening)
    new ns.deep.Boxed();   // 3-segment qualified new (H4 widening)
}

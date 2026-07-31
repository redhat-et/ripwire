// H4 gate fixture (TS): qualified `new` at 2 and 3 segments, plus a bare-new control.
// No explicit constructors anywhere — every class name is a single unambiguous def, so the
// resolver keeps ambiguous=0 for the whole fixture (the ctor-collision case is covered
// separately by bench/h4fixtures/java, not re-derived here).
export class Widget {}

export namespace ns {
    // QnInner (not "Inner"): bench/h4fixtures/js/main.js's own survey fixture has a dangling
    // `new ns.Inner()` ref with NO local "Inner" def (its class is deliberately named "Inner2" —
    // see H4_grammarSurvey_2026-07-30.md's TS/JS section). A bare "Inner" here would give that
    // unrelated fixture's dangling ref a same-name global target via tier-3 unique-global
    // resolution — real resolver behavior, but cross-fixture noise this gate doesn't want to own.
    export class QnInner { static go(): void {} }
    export namespace deep {
        export class Boxed { static make(): void {} }
    }
}

export function caller(): void {
    new Widget();          // control: bare new (worked before H4)
    new ns.QnInner();       // 2-segment qualified new (H4 widening)
    new ns.deep.Boxed();   // 3-segment qualified new (H4 widening)
}

// TypeScript call-form fixture.
export class Widget {
    static make(): Widget { return new Widget(); }
    bump(): void {}
}
export namespace ns {
    export function nsFn(): void {}
    export class Inner { static go(): void {} }
}
export function free(): void {}
export function generic<T>(x: T): T { return x; }
const obj = { deep: { fn(): void {} } };

export function caller(): void {
    free();                    // 1. bare call
    const w = Widget.make();   // 2. static member call
    w.bump();                  // 3. method call
    obj.deep.fn();             // 4. 3-level member chain
    ns.nsFn();                 // 5. namespace-qualified call
    ns.Inner.go();             // 6. namespace.Class.static chain
    generic<number>(1);        // 7. explicit-type-arg call
    w?.bump();                 // 8. optional-chain call
    new Widget();              // 9. bare new
    new ns.Inner();            // 10. qualified new
}

// JAVASCRIPT CALL-FORM MATRIX fixture — one line per call SPELLING the grammar distinguishes.
// Expected counts are literals read off this file. ABSENT rows are asserted at 0.

export function bareFn() { return 1; }

export function genericFn( v ) { return v; }

export function tagFn( strings ) { return strings.length; }

export class Widget
{
    memberFn() { return 2; }
    optionalFn() { return 3; }
}

export const obj = { deep: { threeLevel() { return 4; } } };

export const ns = {
    Inner: class { ping() { return 5; } },
    mid: { Deep: class { pong() { return 6; } } },
};

export function caller()
{
    let a = bareFn();                          // 1. bare call
    const w = new Widget();                    // 6. new, unqualified ctor
    a += w.memberFn();                         // 2. member call
    a += obj.deep.threeLevel();                // 3. 3-level member chain
    a += w?.optionalFn();                      // 4. optional-chain call
    a += genericFn( 1 );                       // 5. plain call (JS has no type arguments)
    const i = new ns.Inner();                  // 7. qualified new, 2 segments
    a += i.ping();
    const d = new ns.mid.Deep();               // 8. qualified new, 3 segments
    a += d.pong();
    a += tagFn`x`;                             // 9. tagged template — a call_expression in this grammar
    return a;
}

export function callerAbsent()
{
    // 10. ABSENT — computed member in constructor position: `new a.b[c]()` is a subscript, not a
    //     property_identifier, so nothing binds. Deliberate.
    const tbl = { ns: { Inner: ns.Inner } };
    const k = "Inner";
    const c = new tbl.ns[ k ]();
    return c ? 1 : 0;
}

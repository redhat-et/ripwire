// TYPESCRIPT CALL-FORM MATRIX fixture — one line per call SPELLING the grammar distinguishes.
// Expected counts are literals read off this file. ABSENT rows are asserted at 0 and fence an
// honest reject.
//
// W4 FINDING vs the round record. §Execution V1-L5 says
// "qualified GENERIC new `new pkg.Outer.Inner<String>()` and bare `new Gen<String>()` DROP
// (pre-existing) — pin as documented-absent rows". MEASURED, that is TRUE OF JAVA ONLY. In
// TypeScript both spellings produce a reference: `new GenWidget<string>()` binds on the BASE
// (pre-round) binary too, and `new ns.GenInner<string>()` binds at HEAD because the type-argument
// list hangs off the new_expression while `constructor:` stays an identifier / member_expression.
// So these two rows are CAPTURED here, and the arms below pin them that way — pinning them at 0
// would have shipped a gate that is green only while the tool is wrong.

export function bareFn(): number { return 1; }

export function genericFn<T>(v: T): T { return v; }

export class Widget
{
    memberFn(): number { return 2; }
    optionalFn(): number { return 3; }
}

export class GenWidget<T>
{
    hold( v: T ): T { return v; }
}

export const obj = { deep: { threeLevel(): number { return 4; } } };

export namespace ns
{
    export class Inner { ping(): number { return 5; } }
    export namespace mid { export class Deep { pong(): number { return 6; } } }
    export class Outer { static x = 0; }
    export class GenInner<T> { grip( v: T ): T { return v; } }
}

export function caller(): number
{
    let a = bareFn();                          // 1. bare call
    const w = new Widget();                    // 6. new, unqualified ctor
    a += w.memberFn();                         // 2. member call
    a += obj.deep.threeLevel();                // 3. 3-level member chain
    a += w?.optionalFn();                      // 4. optional-chain call
    a += genericFn<number>( 1 );               // 5. generic call
    const i = new ns.Inner();                  // 7. qualified new, 2 segments
    a += i.ping();
    const d = new ns.mid.Deep();               // 8. qualified new, 3 segments
    a += d.pong();
    return a;
}

export function callerAbsent(): number
{
    // 9. ABSENT — computed member in constructor position: `new a.b[c]()` is a subscript, not a
    //    property_identifier, so nothing binds. Deliberate.
    const tbl: any = { ns: { Inner: ns.Inner } };
    const k = "Inner";
    const c = new tbl.ns[ k ]();
    // 10. CAPTURED — a BARE generic `new`. Contradicts V1-L5 (see the header): measured on the
    //     PRE-ROUND binary as well, so it is not a widening this round made.
    const g = new GenWidget<string>();
    // 11. CAPTURED at HEAD, DROPPED on the pre-round binary — the qualified generic `new`. Same
    //     member_expression constructor the L-NEW lane widened; the type arguments do not block it.
    const q = new ns.GenInner<string>();
    return ( c ? 1 : 0 ) + g.hold( "x" ).length + q.grip( "y" ).length;
}

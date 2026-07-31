// SWIFT CALL-FORM MATRIX fixture — one line per call SPELLING the grammar distinguishes.
// Expected counts are literals read off this file.

func bareFn() -> Int { return 1 }

func genericFn<T>( _ v: T ) -> T { return v }

func specFn<T>( _ v: T ) -> T { return v }

struct Widget
{
    static func staticFn() -> Int { return 2 }
    func memberFn() -> Int { return 3 }
}

enum Util
{
    static func nsFn() -> Int { return 4 }
    enum Deep
    {
        static func deepFn() -> Int { return 5 }
    }
}

func caller() -> Int
{
    var a = bareFn()                    // 1. bare call
    a += Widget.staticFn()              // 2. Type.static
    let w = Widget()                    // 6. initializer call
    a += w.memberFn()                   // 3. method call
    a += Util.nsFn()                    // 4. enum-namespace call
    a += Util.Deep.deepFn()             // 5. 3-segment navigation chain
    a += genericFn( 7 )                 // 7. inferred generic
    let f = bareFn
    a += f()                            // 8. call through a variable holding a function
    return a
}

func callerSpecialization() -> Int
{
    // 9. NOT-CHECKED in the survey: an EXPLICIT specialization spelling. Swift's own grammar has
    //    no explicit type-argument list at a function call site (inference is the language rule),
    //    so what this line means to tree-sitter-swift is exactly the open question the matrix
    //    exists to answer. Whatever it does, the arm pins it.
    return specFn<Int>( 8 )
}

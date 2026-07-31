// ctxpack S6-B fixture — Swift mutating purity
// Used by test/swiftcheck.sh to verify pure="1" on non-mutating funcs.

struct Counter {
    var count: Int = 0

    // Non-mutating: reads self but does not write to it.
    // A non-mutating func on a struct = const-equivalent → pure="1"
    func value() -> Int { return count }

    // Mutating: modifies self.count — NOT pure
    mutating func increment() { count += 1 }

    // Non-mutating helper: pure="1"
    func doubled() -> Int { return count * 2 }

    // Mutating reset — NOT pure
    mutating func reset() { count = 0 }
}

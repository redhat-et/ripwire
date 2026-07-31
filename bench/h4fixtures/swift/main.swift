// Swift call-form fixture.
struct Widget {
    static func make() -> Widget { return Widget() }
    func bump() {}
}
enum Util {
    static func tool() {}
    enum Deep { static func deepfn() {} }
}
func free() {}
func generic<T>(_ v: T) -> T { return v }

func caller() {
    free()                    // 1. bare call
    let w = Widget.make()     // 2. Type.static call
    w.bump()                  // 3. method call
    Util.tool()               // 4. enum-namespace call
    Util.Deep.deepfn()        // 5. 3-segment chain
    _ = Widget()              // 6. init call
    _ = generic(1)            // 7. generic call (inferred)
    let f = free
    f()                       // 8. call through variable
}

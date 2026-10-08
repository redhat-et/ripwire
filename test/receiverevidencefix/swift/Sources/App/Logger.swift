func render(_ s: String) -> String {
    return "[" + s + "]"
}

class Base {
    func flush() {
        print("base flush")
    }
}

// A bare call is self.method() or a free function; never an unrelated class's method.
class Logger: Base {
    func line(_ s: String) -> String {
        return render(s)
    }

    func close() {
        flush()
        reset()
    }

    private func reset() {
        print("reset")
    }
}

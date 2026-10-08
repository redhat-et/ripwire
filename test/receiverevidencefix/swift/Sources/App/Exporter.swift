class Exporter {
    func flush() {
        print("exporter flush")
    }

    func render(_ s: String) -> String {
        return "<" + s + ">"
    }
}

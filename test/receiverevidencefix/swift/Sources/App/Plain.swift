import Foundation

// Plain inherits from an OUTSIDE class: a bare flush() never reaches Base or Exporter.
class Plain: FileHandle {
    func finish() {
        flush()
    }
}

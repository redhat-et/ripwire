package app

// Plain inherits flush() from an OUTSIDE class: Base and Exporter are unrelated.
class Plain : java.io.Writer() {
    fun finish() {
        flush()
    }
}

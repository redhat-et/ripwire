package app

fun render(s: String): String = "[$s]"

open class Base {
    fun flush() {
        println("base flush")
    }
}

// A bare call is this.method() or a top-level function; never an unrelated class's method.
class Logger : Base() {
    fun line(s: String): String = render(s)

    fun close() {
        flush()
        reset()
    }

    private fun reset() {
        println("reset")
    }
}

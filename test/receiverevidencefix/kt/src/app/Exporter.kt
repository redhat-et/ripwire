package app

class Exporter {
    fun flush() {
        println("exporter flush")
    }

    fun render(s: String): String = "<$s>"
}

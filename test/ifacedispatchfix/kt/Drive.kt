interface Sink {
    fun emit(v: Int): Int
}

class FileSink : Sink {
    override fun emit(v: Int): Int = v + 1
}

class NetSink : Sink {
    override fun emit(v: Int): Int = v + 2
}

fun drain(s: Sink): Int {
    return s.emit(3)
}

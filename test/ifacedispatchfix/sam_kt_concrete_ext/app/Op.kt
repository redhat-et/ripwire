package app
interface Base { fun ap(x: Int): Int; fun bp(): Int }
class Inc : Base, java.io.Closeable { override fun ap(x: Int): Int = x + 1; override fun bp(): Int = 0; override fun close() {} }
fun runBase(s: Base): Int = s.ap(1)

package app
interface Base<T> { fun ap(x: T): T }
interface Sub : Base<Int>
class Inc : Sub { override fun ap(x: Int): Int = x + 1 }
fun runSub(s: Sub): Int = s.ap(1)

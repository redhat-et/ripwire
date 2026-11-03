package app
interface Base { fun ap(x: Int): Int }
interface Sub : Base
class Inc : Sub { override fun ap(x: Int): Int = x + 1 }
fun runSub(s: Sub): Int = s.ap(1)

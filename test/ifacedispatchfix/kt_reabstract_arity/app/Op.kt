package app
interface Base { fun ap(): Int = 0 }
interface Mid : Base { fun ap(x: Int): Int }
interface Sub : Mid { override fun ap(): Int = 1 }
class Inc : Sub { override fun ap(x: Int): Int = x + 1 }
fun runSub(s: Sub): Int = s.ap(1)

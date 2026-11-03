package app
interface Base { fun ap(x: Int): Int = 0; fun cp(): Int }
interface Sub : Base { override fun ap(x: Int): Int }
class Inc : Sub { override fun ap(x: Int): Int = x + 1; override fun cp(): Int = 1 }
fun runSub(s: Sub): Int = s.ap(1)

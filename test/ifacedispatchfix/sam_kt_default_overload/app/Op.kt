package app
interface Base { fun ap(x: Int): Int; fun bp(): Int; fun bp(n: Int): Int }
interface Sub : Base { override fun bp(n: Int): Int = n }
class Inc : Sub { override fun ap(x: Int): Int = x + 1; override fun bp(): Int = 0 }
fun runSub(s: Sub): Int = s.ap(1)

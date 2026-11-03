package app
interface Base { fun ap(x: Int): Int; fun bp(): Int }
interface Sub : Base { override fun bp(): Int }
class Inc : Sub { override fun ap(x: Int): Int = x + 1; override fun bp(): Int = 0 }
fun runSub(s: Sub): Int = s.ap(1)

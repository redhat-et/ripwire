package app
interface Base { fun ap(x: Int): Int; fun bp(): Int }
interface Def : Base { override fun bp(): Int = 0 }
interface Sub : Def
class Inc : Sub { override fun ap(x: Int): Int = x + 1 }
fun runSub(s: Sub): Int = s.ap(1)

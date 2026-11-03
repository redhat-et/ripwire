package app
interface Op {
    fun ap(x: Int): Int
}
class Inc : Op {
    override fun ap(x: Int): Int = x + 1
}
fun runOp(o: Op): Int = o.ap(1)
interface Two {
    fun first(x: Int): Int
    fun second(x: Int): Int
}
class TwoImpl : Two {
    override fun first(x: Int): Int = x
    override fun second(x: Int): Int = x
}
fun runTwo(t: Two): Int = t.first(1)

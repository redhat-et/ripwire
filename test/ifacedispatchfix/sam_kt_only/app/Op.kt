package app
interface Op {
    fun ap(x: Int): Int
}
class Inc : Op {
    override fun ap(x: Int): Int = x + 1
}
fun runOp(o: Op): Int = o.ap(1)

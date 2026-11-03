package kt1
fun interface Op { fun apply(x: Int): Int }
class Inc : Op { override fun apply(x: Int): Int = x + 1 }
fun run(o: Op): Int = o.apply(1)
fun main() {
    run(Inc())
    run { it * 2 }
    run(object : Op { override fun apply(x: Int): Int = x - 1 })
}

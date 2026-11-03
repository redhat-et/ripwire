package kt1
interface Two { fun first(): Int; fun second(): Int }
class TwoImpl : Two { override fun first(): Int = 1; override fun second(): Int = 2 }
fun runTwo(t: Two): Int = t.first()
fun mainTwo(): Int = runTwo(TwoImpl()) + runTwo(object : Two { override fun first(): Int = 3; override fun second(): Int = 4 })

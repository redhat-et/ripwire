package kt1
fun interface Lam { fun call(x: Int): Int }
class LamImpl : Lam { override fun call(x: Int): Int = x }
fun runLam(l: Lam): Int = l.call(1)
fun mainLam(): Int = runLam(LamImpl()) + runLam { it + 1 }

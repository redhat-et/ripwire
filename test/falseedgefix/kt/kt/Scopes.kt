fun useWith(sb: StringBuilder): String = with(sb) { toString() }

fun useApply(): MutableList<Int> = mutableListOf<Int>().apply { add(1) }

fun useLet(s: String?): Int = s?.let { it.length } ?: 0

fun useAlso(xs: MutableList<Int>) = xs.also { it.clear() }

fun realWith(b: lib.Builder) = b.with("x")

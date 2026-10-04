package app

// The two SIDES of a class lookup: a companion member is the CLASS side, an instance member the other.
class Dial {
    companion object {
        fun read(): Int = 1
    }
    fun turn(): Int = 2
}

class Knob {
    fun read(): Int = 3
}

fun onClass(): Int = Dial.read()
fun onInstance(): Int = Knob().read()

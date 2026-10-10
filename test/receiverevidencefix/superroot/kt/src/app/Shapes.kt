package app

open class Base {
    open fun render(): String = "base"
}

class Widget {
    fun render(): String = "widget"
}

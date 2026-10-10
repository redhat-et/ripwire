package app

import outside.makeAny

class Panel : Base() {
    fun typed(): String {
        val base = Widget()
        return base.render()
    }

    fun untyped(): String {
        val base = makeAny()
        return base.render()
    }

    fun realSuper(): String {
        return super.render()
    }
}

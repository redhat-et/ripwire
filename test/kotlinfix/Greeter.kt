package com.example

import com.example.util.square

class Greeter(private val name: String) {
    companion object {
        fun of(name: String): Greeter = Greeter(name)
    }

    fun greet(): String {
        val doubled = square(2)
        return "Hello, $name ($doubled)"
    }
}

fun Int.doubled(): Int = this * 2

// A QUALIFIED Kotlin -> Java call on a name BOTH languages define. Kotlin receivers do not narrow
// candidates yet (ingest_binds.h), so under the JVM bridge's own-language-first rule this binds Util.kt's
// Kotlin Extra.helper, not the Java class it names — the disclosed trade-off kotlincheck §5 pins.
fun useJavaHelper(): Int = JavaBridge.helper(5)

// A qualified Kotlin -> Java call on a name ONLY Java defines: the case the bridge exists for (§3).
fun useJavaOnly(): Int = JavaBridge.javaOnly(3)

// A BARE call on a name both languages define: Util.kt's Extra.helper (Kotlin) and JavaBridge.java's
// helper (Java). With no receiver and no import evidence it binds its OWN language's definition — never
// both (which only ever held in this one-directory layout) and never neither (what the same two calls
// did once the files sat in different directories).
fun ambiguousCall(): Int = helper(5)

fun runAll(): Int {
    val g = Greeter.of("world")
    return g.greet().length + 1.doubled() + useJavaHelper() + useJavaOnly() + ambiguousCall()
}

class Task {
    fun run(block: () -> Unit) = block()
}

fun go(t: Task) = t.run { }

fun build(s: String): Int = s.run { length }

fun kick(j: jobs.Job) {
    j.run()
}

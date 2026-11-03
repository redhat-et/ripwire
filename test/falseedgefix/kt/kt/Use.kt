data class User(val name: String)

fun build(s: String): User = s.run { User(this) }

fun kick(j: jobs.Job) {
    j.run()
}

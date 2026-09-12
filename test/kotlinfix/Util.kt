package com.example.util

fun square(n: Int): Int = n * n

class Formatter {
    fun format(n: Int): String = "n=$n"
}

// Same-name-as-Java-method object, deliberately UNRELATED to JavaBridge.helper — the collision fixture
// for the JVM bridge (graph.h langCompatible + keepOwnJvmLanguageCandidates). A Kotlin call to
// `helper(...)` binds THIS one, because its own language defines a candidate; a Java call would bind
// JavaBridge's for the same reason.
object Extra {
    fun helper(n: Int): Int = n - 1
}

// Same-name-as-Java-class collision fixture for the `enum class` shape specifically. Kotlin's
// enum-class body nests under `enum_class_body`, a DIFFERENT positional child than a plain class's
// `class_body` — the ObjC/Kotlin body-fallback (ingest_sidecap.h) originally recognized only
// `class_body`, so an `enum class` read as bodyless was deleted from the candidate pool by graph.h's
// decl/def collapse whenever a same-name Java class existed (JavaBridge.java's package-private
// `Mode`, below), the exact same silent-drop §5 exists to catch for `helper`.
enum class Mode { ON, OFF }

// captureBases (src/ingest_relations.h) delegation_specifier fixture — exercises BOTH shapes in one
// class header, neither of which any prior fixture reached: `Shape()` is WRAPPED (delegation_specifier
// -> constructor_invocation -> user_type) and `Labeled` is DIRECT (bare interface, no call — user_type
// sits right under delegation_specifier with no constructor_invocation wrapper). Before this fixture
// existed, a copy-paste slip in captureBases' isClause/isBaseTypeNode tables, or a grammar-shape change
// on a future tree-sitter-kotlin bump, could silently zero out every Kotlin inherit edge with nothing
// in test/kotlincheck.sh to notice (§9 pins both shapes by name via --uses=Shape / --uses=Labeled).
interface Labeled {
    fun label(): String
}

open class Shape {
    open fun area(): Int = 0
}

class Square(private val side: Int) : Shape(), Labeled {
    override fun area(): Int = side * side
    override fun label(): String = "square"
}

// countParams (src/ingest_metrics.h) fixture: function_value_parameters counts `parameter` children
// ONLY — a parameter's own modifiers (`vararg`) and its default-value expression are SIBLINGS of the
// `parameter` node in this grammar, not nested inside it, so the generic "every named child" rule
// misreads these 3 real params as 5 (the default-value expression on `age` and the `vararg` modifier
// on `tags` each add one extra named sibling). No prior fixture had more than one parameter on any
// Kotlin function, so this specific miscount had no gate (§10 pins params="3" via --metrics).
fun describe(name: String, age: Int = 0, vararg tags: String): String = "$name/$age/${tags.size}"

// TRULY bodyless collision fixture (§11, a post-PR-review finding): Kotlin has no forward-declaration
// syntax for types, so an interface with NO braces at all — no `class_body`/`enum_class_body` child for
// ingest_sidecap.h's positional-body fallback to find at all — is still the type's sole, complete
// definition, unlike `Labeled` above (which HAS a body and already exercises that fallback). Before
// graph.h's decl/def collapse gained the Kotlin-class exception, this bodyless Taggable read exactly
// like a bodyless forward declaration and was silently deleted whenever JavaBridge.java's same-name
// Taggable class existed — the same silent-drop shape §5/§8 exist to catch, but for a definition that
// was NEVER going to grow a body fallback to find, because it has no body at all.
interface Taggable

// The phase-3b repro: a TOP-LEVEL function against a same-file class method.
//
// `Caller.go` bare-calls `compute()`. Before phase 4 S6-C pinned `Helper::compute` silently; phase 4's
// `Graph::localityKey` made it a full tie and an honest split. Since FE-B (test/receiverevidencecheck.sh) Kotlin's
// implicit receiver decides it: a bare call inside `Caller` reaches Caller's own members, its bases, or a top-level
// function — never the unrelated `Helper.compute`. ONE plain edge to the top-level `compute`, no `amb=`, no `lpin=`:
// the module-level def is not lost, it is the answer. The honest-split shape lives on in modlevel.m (Objective-C).
class Caller {
    fun go(): Int {
        return compute()
    }
}
class Helper {
    fun compute(): Int {
        return 5
    }
}
fun compute(): Int {
    return 6
}

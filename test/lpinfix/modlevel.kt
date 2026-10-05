// The phase-3b repro: a TOP-LEVEL function against a same-file class method.
//
// `Caller.go` bare-calls `compute()`. Two defs answer: `Helper.compute` (canonical id
// `modlevel.kt::Helper::compute`) and the top-level `compute` — whose canonical id degrades to the BARE
// NAME `compute`, sharing ZERO segments with any caller. Before phase 4 S6-C pinned `Helper::compute`
// silently on that asymmetry. With `Graph::localityKey` (`modlevel.kt::compute` for the unscoped def) both
// candidates share exactly `modlevel.kt::` — a full tie — so the call is an honest split: `amb="1"` on
// `Caller::go`, no `lpin=`, and `ambiguous=` counts it. (Kotlin: Python, the vehicle until FE-A, now binds the module def.)
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

// The S6-C locality tie-break's PINNING shape (same as test/pincensusfix/pinned.kt).
//
// `Alpha.run` makes a BARE (implicit-`this`) `helper()` call. `Alpha.helper` and `Beta.helper` both live in THIS file,
// so the same-file rung keeps both and S6-C decides: `pinned.kt::Alpha::` beats `pinned.kt::`. ONE confident edge, NO
// `amb=` — and, since phase 4 (docs/EVALS.md "Phase 4"), `lpin="1"` on the caller row: the pin is a prior's guess and
// the map now says so instead of dressing it as an evidence-backed resolution. (Python until FE-A, see pincensusfix.)
class Alpha {
    fun helper(): Int {
        return 1
    }
    fun run(): Int {
        return helper()
    }
}
class Beta {
    fun helper(): Int {
        return 2
    }
}

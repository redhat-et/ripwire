// The S6-C locality tie-break's PINNING shape, minimal and deliberate (Kotlin; Python until FE-A, whose bare call reaches
// no method at all — test/falseedgecheck.sh). `Alpha.run` makes a BARE, implicit-`this` `helper()` call. Two in-repo defs
// answer to that name and BOTH live in THIS file, so the tier-1 (same-file) rung keeps both and the call reaches the
// locality tie-break still holding two candidates. No receiver rule fires on a bare call here, the CHA cone has no
// receiver type to work from, and the arity filter cannot exclude either def. So S6-C decides: `pinned.kt::Alpha::run`
// shares the whole `pinned.kt::Alpha::` prefix with `Alpha.helper` but only `pinned.kt::` with `Beta.helper` ->
// Alpha.helper is pinned (the right answer: `this.helper()`), ONE confident edge is emitted, and `amb=` is NOT
// incremented. That silent commitment is what the census exists to make visible.
//
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

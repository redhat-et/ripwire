// The S6-C locality tie-break's PINNING shape, as FE-B (test/receiverevidencecheck.sh) leaves it.
//
// `Kappa.run` makes a BARE (implicit-`this`) `step()` call. The receiver is `this`, so only Kappa's own `step` and the
// one it inherits from `Lambda` can answer — both are proven candidates, both live in THIS file, and S6-C decides:
// `pinnedcone.kt::Kappa::` beats `pinnedcone.kt::Lambda::`. ONE confident edge, NO `amb=`, and `lpin="1"` on the caller
// row: which of an override and its base a call reaches is still a prior's pick, and the map says so.
open class Lambda {
    open fun step(): Int {
        return 1
    }
}
class Kappa : Lambda() {
    override fun step(): Int {
        return 2
    }
    fun run(): Int {
        return step()
    }
}

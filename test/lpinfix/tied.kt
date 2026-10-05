// The tie-break's NON-pinning control. `Eps.go` bare-calls `other()`; `Gamma.other` and `Delta.other` are
// SIBLINGS sharing exactly `tied.kt::` with the caller, so NEITHER is more local. The tier stays full, the
// call is an honest 1/k split, `amb="1"` counts it, and there is NO `lpin=` — a split is not a pin.
class Eps {
    fun go(): Int {
        return other()
    }
}
class Gamma {
    fun other(): Int {
        return 3
    }
}
class Delta {
    fun other(): Int {
        return 4
    }
}

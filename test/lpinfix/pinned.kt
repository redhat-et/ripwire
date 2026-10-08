// Was the S6-C locality tie-break's PINNING shape (same as test/pincensusfix/pinned.kt); since FE-B
// (test/receiverevidencecheck.sh) it is EVIDENCE: `Alpha.run` makes a BARE (implicit-`this`) `helper()` call, and an
// implicit `this` reaches Alpha's own members and its bases, never the unrelated `Beta.helper`. ONE confident edge to
// `Alpha.helper`, NO `amb=`, and NO `lpin=` — nothing was left for a prior to pick. The pin itself is pinnedcone.kt.
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

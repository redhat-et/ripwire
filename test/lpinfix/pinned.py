# The S6-C locality tie-break's PINNING shape (same as test/pincensusfix/pinned.py).
#
# `Alpha.run` makes a BARE `helper()` call. `Alpha.helper` and `Beta.helper` both live in THIS file, so
# the same-file rung keeps both and S6-C decides: `pinned.py::Alpha::` beats `pinned.py::`. ONE confident
# edge, NO `amb=` — and, since phase 4 (docs/EVALS.md "Phase 4"), `lpin="1"` on the caller row: the pin is
# a prior's guess and the map now says so instead of dressing it as an evidence-backed resolution.
class Alpha:
    def helper( self ):
        return 1

    def run( self ):
        return helper()


class Beta:
    def helper( self ):
        return 2

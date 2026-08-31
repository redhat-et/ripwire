# The tie-break's NON-pinning shape — the control that proves the census label discriminates.
#
# `Eps.go` calls a bare `other()`; both defs live in this file but in SIBLING classes, so both share
# exactly `tied.py::` with the caller and NEITHER is more local. S6-C leaves the tier FULL, the call
# emits as an honest 1/k split, and `amb=` counts it. A census that labelled this `locality` would be
# claiming a pin that never happened.
class Eps:
    def go( self ):
        return other()


class Gamma:
    def other( self ):
        return 3


class Delta:
    def other( self ):
        return 4

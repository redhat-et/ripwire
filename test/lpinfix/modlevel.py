# The phase-3b repro: a MODULE-LEVEL function against a same-file class method.
#
# `Caller.go` bare-calls `compute()`. Two defs answer: `Helper.compute` (canonical id
# `modlevel.py::Helper::compute`) and the module-level `compute` — whose canonical id degrades to the BARE
# NAME `compute`, sharing ZERO segments with any caller. Before phase 4 S6-C pinned `Helper::compute`
# silently on that asymmetry. With `Graph::localityKey` (`modlevel.py::compute` for the unscoped def) both
# candidates share exactly `modlevel.py::` — a full tie — so the call is an honest split: `amb="1"` on
# `Caller::go`, no `lpin=`, and `ambiguous=` counts it.
class Caller:
    def go( self ):
        return compute()


class Helper:
    def compute( self ):
        return 5


def compute():
    return 6

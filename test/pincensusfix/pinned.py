# The S6-C locality tie-break's PINNING shape, minimal and deliberate.
#
# `Alpha.run` makes a BARE `helper()` call. Two in-repo defs answer to that name and BOTH live in
# THIS file, so the tier-1 (same-file) rung keeps both and the call reaches the locality tie-break
# still holding two candidates. Rule 1 cannot fire (Python, no `self.` receiver), the CHA cone has no
# receiver type to work from, and the arity filter cannot exclude either def. So S6-C decides:
# `pinned.py::Alpha::run` shares the whole `pinned.py::Alpha::` segment prefix with `Alpha.helper` but
# only `pinned.py::` with `Beta.helper` -> Alpha.helper is pinned, ONE confident edge is emitted, and
# `amb=` is NOT incremented. That silent commitment is what the census exists to make visible.
class Alpha:
    def helper( self ):
        return 1

    def run( self ):
        return helper()


class Beta:
    def helper( self ):
        return 2

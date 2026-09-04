# Phase 5 fixture — the EXTERNAL-NAME VETO and the receiver MRO walk (docs/EVALS.md "Phase 5"), in the
# smallest form. Every site below is named by its gate arm (test/externalvetocheck.sh A–E, H–I;
# test/mrowalkcheck.sh K, L, N).
#
#   norm()   (A) bare `sum(…)` — a Python builtin; `Rep.sum` and `Other.sum` both exist in this file, so the
#                name ladder reaches S6-C holding both and pins the caller's own `Rep::sum` (`lpin="1"`).
#                A bare Python call never reaches a method: the veto refuses the edge, counted `external=`.
#   conv()   (B) `np.dtype(…)` — the receiver `np` is bound by `import numpy as np`, a module the indexed
#                tree does not contain. Today: pinned to `Rep::dtype`. After: vetoed.
#   get()    (C) `OrderedDict.__getitem__(…)` — `from collections import OrderedDict`, a stdlib module.
#                Today: pinned to `Rep::__getitem__`. After: vetoed.
#   use()    (D) control — `helper(1)` under `from .own import helper`: an IN-REPO import binding is
#                evidence, the edge to `own.py::helper` stays.
#   Leaf.run (K) `super().run()` — `Leaf(Mid)`, `Mid(Base)`, only `Base` defines `run`: today NO edge (the
#                bare-name ladder pins the caller's own `Leaf::run`, a self-loop, dropped). After: the MRO
#                walk lands `Base::run` (`receiver-rule`).
#   Ext.reset (L) `super().__init__()` in `Ext(dict)` — no in-repo base defines `__init__`; today a `unique`
#                edge to `Other::__init__` (the only `__init__` in the file). After: vetoed — the MRO left
#                the indexed tree.
#             (N) control — `self.keys()`: no in-repo `keys` anywhere, no row before or after.
import numpy as np
from collections import OrderedDict
from .own import helper


class Rep:
    def sum( self, xs ):
        return xs

    def dtype( self ):
        return 0

    def __getitem__( self, k ):
        return k

    def norm( self ):
        return sum( self.parts )

    def conv( self ):
        return np.dtype( "f8" )

    def get( self, k ):
        return OrderedDict.__getitem__( self.d, k )

    def use( self ):
        return helper( 1 )


class Other:
    def __init__( self ):
        self.d = {}

    def sum( self, xs ):
        return xs

    def dtype( self ):
        return 0

    def __getitem__( self, k ):
        return k


class Base:
    def run( self ):
        return 1


class Mid( Base ):
    def area( self ):
        return 2


class Leaf( Mid ):
    def run( self ):
        return super().run()


class Ext( dict ):
    def reset( self ):
        super().__init__()
        return self.keys()

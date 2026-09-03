# Rule 2c — the CLASS-NAME receiver route (docs/EVALS.md "Phase 4b"), in the smallest form.
#
# `Box.__setitem__` calls `Interval.validate(v)`: a classmethod call THROUGH THE CLASS NAME. Both `Box` and
# `Interval` define `validate`, so the tier reaches S6-C holding both and — before Rule 2c — the caller's own
# `Box::validate` wins by the scope segment: the wrong pin, silently, `lpin="1"`. Rule 2c reads the receiver
# token as the type it names: `Interval::validate` is a real definition, so the call narrows there
# (census mech `receiver-rule`), one edge, no `lpin=`.
#
# Controls, one per clause of the rule:
#   other()     — `item.validate(v)` on an UNTYPED local: not a class name, the S6-C pin stands (`lpin="1"`)
#   shadowed()  — a PARAMETER named `Interval` shadows the class: vetoed, the S6-C pin stands (`lpin="1"`)
#   inherited() — `Leaf.validate(v)` where `Leaf(Interval)` defines no `validate`: the DIRECT-base walk lands
#                 `Interval::validate` (receiver-rule), no `lpin=`
#   miss()      — `Point.validate(v)` where `Point` defines no `validate` and has no bases: nothing fires,
#                 the unchanged ladder pins by locality as before (`lpin="1"`)
class Interval:
    @classmethod
    def validate( cls, v ):
        return v


class Leaf( Interval ):
    def area( self ):
        return 0


class Point:
    def norm( self ):
        return 0


class Box:
    def validate( self, v ):
        return v

    def __setitem__( self, k, v ):
        self.k = Interval.validate( v )

    def other( self, item, v ):
        return item.validate( v )

    def shadowed( self, Interval, v ):
        return Interval.validate( v )

    def inherited( self, v ):
        return Leaf.validate( v )

    def miss( self, v ):
        return Point.validate( v )

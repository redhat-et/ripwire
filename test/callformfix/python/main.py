"""PYTHON CALL-FORM MATRIX fixture — one line per call SPELLING the grammar distinguishes.

Every callee has a UNIQUE name so `--uses=<name>` is a per-spelling assertion; expected counts are
literals read off this file.
"""


def bare_fn():
    return 1


class Holder:
    @staticmethod
    def two_level():
        return 2

    def member_fn(self):
        return 3


class Outer:
    class Inner:
        @staticmethod
        def three_level():
            return 4


class Widget:
    def __init__(self):
        self.n = 0


def caller():
    a = bare_fn()                       # 1. bare call
    a += Holder.two_level()             # 2. 2-level attribute call
    a += Outer.Inner.three_level()      # 3. 3-level attribute chain
    h = Holder()
    a += h.member_fn()                  # 4. method call through an instance
    w = Widget()                        # 5. constructor call
    a += 0 if w is None else 0
    return a


def caller_var_call():
    # 6. EXTRACTS (as `f`), never RESOLVES — a call through a variable holding a function.
    f = bare_fn
    return f()

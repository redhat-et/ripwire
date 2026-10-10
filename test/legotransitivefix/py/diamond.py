# A diamond: Bottom reaches Top through Left AND Right; it is ONE deeper row, at its shallowest depth.
class Top:
    pass


class Left(Top):
    pass


class Right(Top):
    pass


class Bottom(Left, Right):
    pass


class Deepest(Bottom):
    pass


class Alone:
    pass


class OnlyChild(Alone):
    pass

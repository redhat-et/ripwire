"""Names a nested def captures from its ENCLOSING function: a bound-method alias and a parameter."""


class Tree:
    def label_width(self, x):
        return x

    def render(self, xs):
        label_width = self.label_width

        def line_width(x):
            # label_width is the enclosing method's local (the bound method): a true edge
            return label_width(x)

        widest = 0
        for x in xs:
            widest = max(widest, line_width(x))
        return widest


def wrap(reparse):
    def run():
        # reparse is the enclosing function's PARAMETER: which function it holds is unknown here, so the
        # previous resolution stands (no rule of FE-A decides a call through a captured name)
        return reparse()

    return run

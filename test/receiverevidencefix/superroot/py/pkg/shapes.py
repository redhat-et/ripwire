class Base:
    def render(self):
        return "base"


class Widget:
    def render(self):
        return "widget"


def make_base():
    return object()

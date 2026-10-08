from .css.styles import Styles
from .css.stylesheet import Stylesheet as Sheet
from .css.stylesheet import Stylesheet


class Holder:
    """Near misses: constructor-assigned field, typed parameter, construction, import alias."""

    def __init__(self):
        self.sheet = Stylesheet()

    def sync(self, other):
        self.sheet.update(other)


def apply(styles: Styles):
    return styles.animate("color", 1)


def build(path):
    sheet = Stylesheet()
    sheet.update({})
    alias = Sheet()
    return alias.read(path)


def clone(styles):
    """Near miss: a class-name receiver is evidence."""
    return Styles.copy(styles)

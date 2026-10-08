from .parse import parse
from .styles import Styles


class Stylesheet:
    """Builtin dict/set receivers in a file that imports Styles: the import is no evidence about them."""

    def __init__(self):
        self.source = {}
        self._invalid_css = set()
        self.styles = Styles()

    def update(self, other):
        self.source.update(other)

    def read(self, path):
        return open(path).read()

    def reparse(self, other):
        cache = {}
        for key, value in self.source.items():
            cache[key] = value
        self._invalid_css.update(other._invalid_css)
        rules_map = {"a": 1}
        names = sorted(rules_map.keys())
        return cache.get(names[0])

    def refresh_rules(self, animator):
        animator.animate(self, "opacity")

    def own(self, other):
        self.update(other)
        return self.styles.get("color")

    def parse_rules(self, css):
        return list(parse(css))

    @classmethod
    def blank(cls):
        return cls.default_rules()

    @classmethod
    def default_rules(cls):
        return []

class StylesBase:
    def __init__(self):
        self._rules = {}

    def get(self, key, default=None):
        return self._rules.get(key, default)

    def keys(self):
        return list(self._rules)

    def items(self):
        return list(self._rules.items())

    def animate(self, attribute, value):
        self._rules[attribute] = value


class Styles(StylesBase):
    def copy(self):
        return Styles()

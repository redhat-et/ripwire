"""A worker whose methods are spelled like plain helper names and builtins."""


class Worker:
    def process(self, item):
        return item

    def open(self):
        return self

    def _default():
        return {}

    DEFAULTS = _default()

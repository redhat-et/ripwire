class Fmt:
    """A same-named class in a module that is not the entry point's module."""

    def format(self, line):
        return "tools:" + line

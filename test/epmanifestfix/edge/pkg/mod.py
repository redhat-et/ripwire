class Fmt:
    """Formats a report line for the registered formatter."""

    def format(self, line):
        return "fmt:" + line


class Other:
    """Another formatter registered in a second group."""

    def format(self, line):
        return "other:" + line


class Lonely:
    """A formatter whose group no code loads."""

    def format(self, line):
        return "lonely:" + line

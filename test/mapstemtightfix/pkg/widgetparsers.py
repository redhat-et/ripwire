class WidgetError(Exception):
    pass


class WidgetParser:
    def __init__(self, source):
        self.source = source

    def parse(self):
        if self.source is None:
            raise WidgetError("no source")
        return [part.strip() for part in self.source.split(";")]

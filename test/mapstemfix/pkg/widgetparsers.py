class WidgetError(Exception):
    pass


class WidgetParser:
    def __init__(self, text):
        self.text = text

    def parse(self):
        if not self.text:
            raise WidgetError("empty")
        return self.text.split(",")

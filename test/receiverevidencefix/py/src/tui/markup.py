class MarkupParser:
    def parse(self, text):
        return [text]


class TokenParser:
    def parse(self, text):
        return text.split()

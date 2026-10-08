class Parser:
    def feed(self, data):
        return list(data)


class XTermParser(Parser):
    def feed(self, data):
        return [chr(b) for b in data]

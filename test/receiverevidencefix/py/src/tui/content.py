class Content:
    def __init__(self, text=""):
        self.text = text

    def append(self, other):
        return Content(self.text + str(other))

    def split(self, sep=" "):
        return [Content(t) for t in self.text.split(sep)]

    def join(self, parts):
        return Content(self.text.join(str(p) for p in parts))

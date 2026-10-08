class Region:
    def __init__(self, x, y):
        self.x = x
        self.y = y

    def split(self, cut):
        return Region(self.x, cut), Region(cut, self.y)

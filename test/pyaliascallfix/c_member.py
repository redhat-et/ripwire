from m import f as gm


class Box:
    def gm(self):
        return 2

    def call_self(self):
        return self.gm()


def call_obj(o):
    return o.gm()

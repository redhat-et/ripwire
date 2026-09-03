def widen(a, b):
    return a + b


def narrow(a):
    return a - 1


class Gauge:
    def read(self, unit):
        return unit

    def reset(self):
        return 0

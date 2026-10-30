from m import f as g


def call_outer():
    g = 1

    def call_inner():
        return g()
    return call_inner

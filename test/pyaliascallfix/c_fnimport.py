def setup():
    from m import f as g
    return g


def call_fnimport():
    return g()

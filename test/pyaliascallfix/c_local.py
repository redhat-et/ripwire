from m import f as g
from m2 import f as other


def call_local():
    g = other
    return g()

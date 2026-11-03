try:
    from m import f as g
except ImportError:
    from m2 import f as g


def call_twomod():
    return g()

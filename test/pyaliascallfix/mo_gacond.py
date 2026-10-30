import sys

if sys.platform == "never":
    def f():
        return 1


def __getattr__(name):
    return len

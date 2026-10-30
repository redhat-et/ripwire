try:
    def f():
        return 1
except ImportError:
    pass


def __getattr__(name):
    return len

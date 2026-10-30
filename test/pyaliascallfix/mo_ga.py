def f():
    return 1


def __getattr__(name):
    raise AttributeError(name)

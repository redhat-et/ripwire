def f():
    return 1


def __getattr__(name):
    return len


globals()["f"] = len

from ui.lists import append


def grow(items):
    # a true edge: the imported in-repo append
    return append(items, 1)


def helper(x):
    return x * 2


def twice(x):
    # a true edge: a same-module function called bare
    return helper(x)

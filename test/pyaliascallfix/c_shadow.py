from m import f as g


def call_comp(fs):
    return [g() for g in fs]


def call_gen(fs):
    return list(g() for g in fs)


def call_lambda():
    return lambda g: g()


def call_outside(fs):
    names = [g for g in fs]
    return names, g()

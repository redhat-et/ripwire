# kills.py — sliceflowsensfix, the KILL class (Python). Expectations: expect.tsv.


def pk01(a):
    x = a
    x = 5
    return x


def pk02(a):
    x = 1
    if a > 0:
        x = 2
        return x
    return x


def pk03(a):
    x = 1
    if a > 0:
        x = 2
    else:
        sink(x)
    return x


def pk04(a):
    x = 1
    for i in a:
        sink(x)
        x = i
        x = i + 1
    return x


def pk05(a):
    x = 1
    if a < 0:
        x = 2
        raise ValueError(x)
    return x


def pk06(a):
    x = 1
    with open(a) as handle:
        x = handle.read()
    return x

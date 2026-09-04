# straight.py — sliceflowsensfix, the STRAIGHT-LINE control class (Python). Expectations: expect.tsv.


def ps01(a):
    return a


def ps02(a):
    x = a + 1
    sink(x)
    return x


def ps03(a):
    x = 1
    x += a
    x += 2
    return x


def ps04(a):
    x = a
    y = x * 2
    return y + x


def ps05(a):
    x = a
    sink(x
         + 1)
    return x

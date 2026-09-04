# disclosed.py — sliceflowsensfix, the DISCLOSED-CONSTRUCT class (Python): the expectation encodes the
# disclosed behaviour of each construct, not the language's truth. Expectations: expect.tsv.


def pd01(a):
    global G
    G = 1
    G = 2
    return G


def pd02(a):
    x = 1

    def inner():
        x = 2
        return x

    return x


def pd03(a):
    x = 1
    y = (x := 2) if a else 0
    return x


def pd04(a):
    x = 1
    y = [x for x in a]
    return x

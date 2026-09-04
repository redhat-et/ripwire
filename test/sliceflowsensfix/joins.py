# joins.py — sliceflowsensfix, the JOIN class (Python). Expectations: expect.tsv.


def pj01(a):
    x = 1
    if a > 0:
        x = 2
    return x


def pj02(a, b):
    x = 1
    if a > 0:
        x = 2
    elif b > 0:
        x = 3
    return x


def pj03(a):
    x = 1
    while a > 0:
        sink(x)
        x = a
        a = a - 1
    return x


def pj04(a):
    x = 1
    try:
        x = fetch(a)
        x = 2
    except ValueError:
        sink(x)
    finally:
        sink(x)
    return x


def pj05(a):
    x = 1
    for i in a:
        if i > 3:
            x = i
            break
    else:
        x = 2
    return x


def pj06(a):
    x = 1
    match a:
        case 1:
            x = 2
        case 2:
            x = 3
    return x

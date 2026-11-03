from pkg.formparsers import FormParserError


def a():
    try:
        return 1
    except FormParserError:
        return 2


def b():
    try:
        return a()
    except FormParserError:
        return 3


def c():
    try:
        return b()
    except FormParserError:
        return 4

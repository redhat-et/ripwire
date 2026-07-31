# star.py — asymmetric call-graph star for rankbycheck.sh (all five --rank-by modes).
#
#   hub()  calls a(), b(), c()          — hub is a HUB (high out-degree / high HITS-hub score)
#   d(), e() both call sink()           — sink is an AUTHORITY (high in-degree / high HITS-authority score)
#
# hub and sink are deliberately NOT connected to each other, so the two HITS roles (hub vs authority) land
# on two different, unambiguous symbols and --rank-by=hub / --rank-by=authority can be told apart.


def a():
    return 1


def b():
    return 2


def c():
    return 3


def hub():
    return a() + b() + c()


def sink():
    return 0


def d():
    return sink()


def e():
    return sink()

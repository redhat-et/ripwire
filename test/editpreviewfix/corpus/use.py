from mod import widen, narrow


def drive(x):
    return widen(x, 2) + narrow(x)


def drive_gauge(g, x):
    return g.read(x) + g.reset()

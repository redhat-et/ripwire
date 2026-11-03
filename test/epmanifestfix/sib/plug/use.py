import pkg_resources


def go():
    for e in pkg_resources.iter_entry_points("x.hooks"):
        e.load()
    return entry_points()["x.pkg"]


def lookalike(m):
    return m.get("x.pkg")


def many_a(ep):
    return ep.group == "x.many"


def many_b(ep):
    return ep.group != "x.many"


def many_c():
    return entry_points(group="x.many")


def many_d():
    return entry_points().select(group="x.many")


def by_name():
    return entry_points(name="i", group="x.pkg")

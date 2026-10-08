from .content import Content


def gather(nodes):
    """list.append on a list literal local, in a file that imports Content (which defines append)."""
    out = []
    for node in nodes:
        out.append(node)
    return out


def grow(text):
    """Near miss: a constructed Content's append is that class's method."""
    c = Content(text)
    return c.append("!")

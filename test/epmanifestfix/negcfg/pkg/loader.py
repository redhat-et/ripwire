from importlib.metadata import entry_points


def load(ep):
    # ep.group == "x.report" in a comment is not a consumer
    if ep.group == "x.report":
        return ep.load()
    return None


def misread(name):
    if name == "x.report":
        return 1
    return 0


def make_fake():
    return _ep(group="x.report")


def load_other():
    return [e.load() for e in entry_points(group="y.other")]


def _ep(group):
    return group

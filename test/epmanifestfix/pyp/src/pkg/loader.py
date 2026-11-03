from importlib.metadata import entry_points


def load_reports():
    return [e.load() for e in entry_points().select(group="x.report")]

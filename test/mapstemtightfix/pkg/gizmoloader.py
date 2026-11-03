def load_gizmo(name):
    return name.upper()


class GizmoLoaderBase:
    def __init__(self, name):
        self.name = name
        self.seen = []

    def load(self):
        self.seen.append(self.name)
        return [self.name, len(self.seen)]

    def reload(self):
        self.seen.clear()
        return self.load()


class GizmoLoader:
    def run(self):
        return 1

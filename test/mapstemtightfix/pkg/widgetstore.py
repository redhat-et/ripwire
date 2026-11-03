def open_widget_store(path):
    return path.strip()


class WidgetRegistryStore:
    def __init__(self, path):
        self.path = path

    def put(self, key, value):
        return (self.path, key, value)

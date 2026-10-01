class AdminRouter:
    def __init__(self):
        self.table = {}

    def add_route(self, path, handler):
        self.table[path] = handler
        return len(self.table)

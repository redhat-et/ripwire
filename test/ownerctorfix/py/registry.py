def make_store(options):
    return {"options": options, "items": []}


class Registry:
    def __init__(self, options):
        self.store = make_store(options)
        self.count = 0

    def create(self, name):
        entry = dict(self.store)
        entry["name"] = name
        return entry

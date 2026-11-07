class Ledger:
    def post_entry(self, e):
        return e


def proven_hop(led: Ledger):
    return led.post_entry(1)


def name_hop(x):
    return x.post_entry(2)


class Svc:
    def relay(self, led: Ledger):
        return led.post_entry(3)


def only_by_name():
    return name_hop(None)


def both_paths():
    proven_hop(Ledger())
    return name_hop(None)


def by_name_edge(s):
    return s.relay(None)


def crossed(s):
    name_hop(None)
    return s.relay(None)

class Ledger:
    def post_entry(self, e):
        return e


class Client:
    def submit(self, led: Ledger):
        return led.post_entry(1)


def driver(c):
    return c.submit(None)

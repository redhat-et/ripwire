class Strategy:
    def run(self):
        raise NotImplementedError


class FastStrategy(Strategy):
    def run(self):
        return 1

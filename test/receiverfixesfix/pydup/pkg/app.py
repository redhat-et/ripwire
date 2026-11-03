from pkg.a import mgr


class App:
    def __init__(self):
        self.dup: mgr.Manager | None = None

    def goDup(self):
        self.dup.start()

    def start(self):
        return 0

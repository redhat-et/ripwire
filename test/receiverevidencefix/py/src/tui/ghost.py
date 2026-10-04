# A class with __getattr__: Python calls the hook only after normal lookup MISSES, so a method the class defines
# resolves as usual and only a name the lookup misses is left to the name ladder.
class Proxyish:
    def __getattr__(self, name):
        return lambda: 0

    def real(self):
        return 1

    def run(self):
        self.real()
        return self.ghost()


class Haunted:
    def ghost(self):
        return 2

    def real(self):
        return 3

"""A method's bare call never reaches a sibling class's method, nor its own class's (that needs self.)."""


class Alpha:
    def helper(self):
        return 1

    def run(self):
        # helper is no name in scope here: Python looks up locals, the module and the builtins, never the class
        return helper()


class Beta:
    def helper(self):
        return 2

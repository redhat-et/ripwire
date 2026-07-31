# narrowfix/recv.py — Rule 2 for Python: x = Foo(); x.run() resolves run to Foo.run (not Bar.run).

class Foo:
    def run(self):
        return 1

class Bar:
    def run(self):
        return 2

def g():
    x = Foo()
    y = Bar()
    x.run()    # Rule 2: Foo.run only
    y.run()    # Rule 2: Bar.run only

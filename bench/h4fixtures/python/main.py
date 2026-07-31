# Python call-form fixture.
class Widget:
    @staticmethod
    def make():
        return Widget()
    def bump(self):
        pass

class Outer:
    class Inner:
        @staticmethod
        def go():
            pass

def free():
    pass

def caller():
    free()                 # 1. bare call
    w = Widget.make()      # 2. Class.static call
    w.bump()               # 3. method call
    Outer.Inner.go()       # 4. 3-level attribute chain
    Widget()               # 5. constructor call
    f = free
    f()                    # 6. call through variable

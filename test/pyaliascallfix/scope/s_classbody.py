def use_classbody():
    class Spray:
        b = 1

    class Outer:
        inner = [Spray()]

    return Outer

from m import f as g

globals()["g"] = len


def call_dynamic():
    return g()

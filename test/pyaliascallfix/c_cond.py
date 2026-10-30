import os

if os.environ.get("X"):
    from m import f as g


def call_cond():
    return g()

from m import f as gm0


def __getattr__(name):
    return len


def call_cgetattr():
    return gm0()

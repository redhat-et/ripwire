import ffimod


def relay_transform(value):
    return ffimod.fast_transform(value)

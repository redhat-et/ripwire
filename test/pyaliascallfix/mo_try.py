def f():
    return 1


try:
    from fast_over import f
except ImportError:
    pass

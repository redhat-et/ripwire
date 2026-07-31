# CONTROL for A4-R5 gate (d): a LOCAL Python function whose name collides with a
# pybind11 alias ("combine", bound to combine_impl in module.cpp). The local
# same-language def MUST win — no cross-language binding edge may steal it.
def combine(a, b):
    return a * b


def use_local(v):
    # Resolves to the LOCAL combine above (same-language §2a), NEVER to combine_impl.
    return combine(v, v)

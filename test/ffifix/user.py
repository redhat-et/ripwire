import ctypes

# Load the C library and call an extern-C export by name via ctypes.
lib = ctypes.CDLL("./clib.so")


def scale_via_ctypes(value):
    # `lib` is a known ctypes CDLL handle → `lib.clib_scale` is a low-confidence
    # binding edge to the extern-C `clib_scale` in clib.cpp.
    return lib.clib_scale(value)

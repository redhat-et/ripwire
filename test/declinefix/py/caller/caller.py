def py_declined(response):
    return response.pyfetch()


def py_unique(solo):
    return solo.pyonly()


def py_external(values):
    return sum(values)


def py_undefined():
    return nowhere_defined()


def py_self(n):
    return py_self(n - 1)


py_undefined()

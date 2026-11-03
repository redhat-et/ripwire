def py_nest_helper(): pass


def outer():
    def nested_fn():
        py_nest_helper()
    return nested_fn

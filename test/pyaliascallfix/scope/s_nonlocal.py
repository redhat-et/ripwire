def outer_nonlocal():
    class Spray:
        pass

    def rebind():
        nonlocal Spray
        Spray = dict

    rebind()
    return Spray()

def outer_enclosing():
    class Spray:
        pass

    def inner_enclosing():
        return Spray()

    return inner_enclosing

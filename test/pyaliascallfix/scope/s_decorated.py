import functools


def use_decorated():
    @functools.total_ordering
    class Spray:
        pass

    return Spray()

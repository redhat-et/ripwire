class Spray:
    pass


def use_default(made=Spray()):
    class Spray:
        pass

    return made, Spray()

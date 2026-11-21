def make_holder():
    class Spray:
        pass

    class Holder:
        def Spray(self):
            return 1

        def go_method(self):
            return self.Spray()

    return Holder

"""Two classes whose methods are spelled like the imported match function."""


class FuzzyIndex:
    def match(self, query, candidate):
        return query in candidate


class Scorer:
    def match(self, candidate):
        return bool(candidate)

# fieldusesfix/tally.py — Python instance fields: `self.x = …` in methods and class-body annotations.
# LINE NUMBERS ARE LOAD-BEARING (fieldusescheck.sh pins role + line).


class Tally:
    limit: int = 10                    # line 6: Tally.limit — an annotated class attribute stays a t="var" SYMBOL (not a field)

    def __init__(self):
        self.total = 0                 # line 9: Tally.total DEFINITION (the first assignment; a def, not a use)
        self.hits = []                 # line 10: Tally.hits DEFINITION

    def add(self, n):
        self.total += n                # line 13: Tally.total WRITE (augmented)
        self.hits.append(n)            # line 14: Tally.hits READ (receiver of a method call)

    def read(self):
        return self.total              # line 17: Tally.total READ


class Meter:
    def __init__(self):
        self.total = 0.0               # line 22: Meter.total DEFINITION (same name as Tally.total)

    def merge(self, other):
        self.total += other.total      # line 25: Meter.total WRITE · other.total → untyped receiver → amb="2"

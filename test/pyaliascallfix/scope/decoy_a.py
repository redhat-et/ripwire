class Spray:
    """A decoy Spray: no call in the scope fixtures may bind it unless it imports it."""

    def __init__(self):
        self.where = "decoy_a"

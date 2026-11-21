def make_decoy():
    class Spray:
        """Another test's local Spray: unreachable by name from any other function."""

    return Spray


class Spray:
    """A second module-level decoy Spray."""

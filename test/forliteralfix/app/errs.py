"""errs: the module docstring says bad things happened here, once."""
import os


class Boom(Exception):
    """The class docstring: bad things happened here too."""

    def explain(self):
        """The method docstring: bad things happened here again."""
        return os.sep


def long_sig(
    a,
    b,
) -> None:
    """After a multi-line signature: bad things happened here as well."""
    return a + b


def fail_hard(x):
    if x:
        raise ValueError(
            """bad things happened here"""
        )
    return x


def branch_str(x):
    if x:
        """bad things happened here, a bare string in an if body"""
    return x

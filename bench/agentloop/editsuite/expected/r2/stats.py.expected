"""Small statistics helpers used by the report module."""


def mean(values):
    if not values:
        return 0.0
    return sum(values) / len(values)


def variance(values):
    m = mean(values)
    return sum((v - m) ** 2 for v in values) / len(values)


def median(values):
    ordered = sorted(values)
    n = len(ordered)
    mid = n // 2
    if n % 2 == 1:
        return ordered[mid]
    return (ordered[mid - 1] + ordered[mid]) / 2


def describe(values):
    return {
        "mean": mean(values),
        "variance": variance(values),
        "median": median(values),
    }

from stats import mean, median, variance


def test_mean():
    assert mean([1, 2, 3]) == 2


def test_median():
    assert median([3, 1, 2]) == 2


def test_variance():
    assert variance([1, 1, 1]) == 0

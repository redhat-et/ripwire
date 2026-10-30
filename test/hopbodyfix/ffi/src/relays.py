def relay_value_log(value):
    print("relay", value)
    print("value", value)
    return value


def relay_value_count(value):
    total = 0
    for v in value:
        total += 1
    return total


def relay_value_check(value):
    if value is None:
        raise ValueError("relay value")
    return value

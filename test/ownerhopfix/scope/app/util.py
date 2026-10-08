def fan_out(listener, change):
    return listener(change)


def record(change):
    return [change]


def flush_queue(bus):
    return bus


def mark_dirty(change):
    return change


def persist_value(key, value):
    return {key: value}


def update(store, change):
    """Update the store with a change and notify listeners."""
    return record(change)


def cache(change):
    """Cache a change for listeners."""
    return mark_dirty(change)


def listeners(change):
    """Listeners of a change in the store."""
    return fan_out(None, change)

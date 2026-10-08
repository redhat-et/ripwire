"""Reactive values: a change notifies watchers."""


class Reactive:
    """A reactive value."""

    def __init__(self, value):
        self.value = value
        self.watchers = []

    def _notify(self, old, new):
        for w in self.watchers:
            invoke_watcher(w, old, new)
        schedule_refresh(self)


class Signal:
    """A signal: a reactive value without a default."""

    def __init__(self):
        self.handlers = []

    def _notify(self, old, new):
        for h in self.handlers:
            invoke_watcher(h, old, new)
        record_signal(self)


def invoke_watcher(watcher, old, new):
    stamp(watcher)
    return watcher(old, new)


def schedule_refresh(obj):
    stamp(obj)
    return obj


def record_signal(obj):
    stamp(obj)
    return obj


def stamp(obj):
    """mark an object as touched (a proven callee for the three helpers above)."""
    return obj


def refresh(obj):
    """redraw."""
    return schedule_refresh(obj)

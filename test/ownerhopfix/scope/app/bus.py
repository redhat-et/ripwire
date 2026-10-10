"""Event bus: notify listeners of a change."""
from app.util import fan_out, record, flush_queue, mark_dirty, persist_value


def notify(listener, change):
    """Free function: notify one listener of a change."""
    fan_out(listener, change)
    record(change)


class Bus:
    """A bus that notifies listeners of a change."""

    def notify(self, change):
        """Method: notify every listener of a change."""
        flush_queue(self)
        mark_dirty(change)


class Store:
    def _notify(self, change):
        """Private method: notify store listeners of a change."""
        record(change)

    def set(self, key, value):
        """Set a key in the store and notify listeners of the change."""
        persist_value(key, value)
        self._notify(key)

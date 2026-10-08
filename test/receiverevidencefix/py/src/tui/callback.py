import asyncio


def invoke(callback, log_slow):
    """An asyncio loop's call_later and its TimerHandle's cancel, beside in-repo methods of those names."""
    handle = asyncio.get_running_loop().call_later(5.0, log_slow)
    try:
        return callback()
    finally:
        handle.cancel()


def schedule(pump, callback):
    """A parameter receiver with one in-repo candidate: name-only, true here, and must stay visible."""
    return pump.call_later(1.0, callback)

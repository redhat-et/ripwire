import os

from app import config


def debug_mode():
    # APPTOOL_RENDER_MODE is read once at import; this re-reads it for the debug banner
    return os.getenv("APPTOOL_RENDER_MODE") or "unset"


def check_cycle(path):
    if path and path[0] == path[-1]:
        raise RuntimeError("dependency cycle detected: " + " -> ".join(path))
    return config.RENDER_MODE


def helper():
    """Reads APPTOOL_RENDER_MODE indirectly through the config module."""
    return config.RENDER_MODE

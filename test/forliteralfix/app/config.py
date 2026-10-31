import os


def read_mode():
    value = os.environ.get("APPTOOL_RENDER_MODE", "full")
    if value not in ("full", "none"):
        return "full"
    return value


RENDER_MODE = read_mode()
